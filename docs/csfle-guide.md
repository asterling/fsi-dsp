# Client-Side Field-Level Encryption (CSFLE) Setup Guide

## Overview

Client-Side Field-Level Encryption (CSFLE) provides field-level encryption for Kafka messages, enabling FSI teams to protect PII and sensitive data at the field level. Fields tagged as PII are encrypted at the producer before being sent to Kafka and decrypted only by authorized consumers with access to the encryption keys.

CSFLE uses **envelope encryption**:
- A **Key Encryption Key (KEK)** is stored in a KMS (AWS KMS, Azure Key Vault, GCP Cloud KMS, or HashiCorp Vault Transit)
- A **Data Encryption Key (DEK)** is generated automatically by the Confluent Schema Registry DEK Registry
- The KEK wraps (encrypts) the DEK; the DEK encrypts individual fields
- Only consumers with access to the KEK (via KMS permissions) can unwrap the DEK and decrypt fields

This approach ensures that:
- PII is encrypted at rest in Kafka brokers (brokers never see plaintext PII)
- PII is encrypted in transit (beyond TLS -- the payload itself is encrypted)
- Only authorized consumers with KMS access can read PII fields
- Non-PII fields remain readable by all authorized consumers

## Prerequisites

1. **Stream Governance Advanced** package must be enabled on your Confluent Cloud environment. CSFLE is a premium feature and is not available with Essentials or standard Advanced packages. Without this package, schema registration with encryption rules will fail with "encryption rules not supported".

2. **KMS access** configured for your cloud provider (see KMS Provider Setup below).

3. **Schema Registry API credentials** with permissions to register KEKs and schemas.

4. **Confluent Terraform Provider** v2.0+ (already pinned in all CC scenarios).

## KMS Provider Setup

CSFLE requires a KMS to store the KEK. Each cloud provider has a different KMS with its own key ID format and access model.

### AWS KMS

**Key policy:** Grant the Confluent Cloud Schema Registry service principal access to the KMS key for encrypt/decrypt operations.

**Key ID format (ARN):**
```
arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789abc
```

**Terraform KMS type:** `aws-kms`

**Setup steps:**
1. Create a KMS key in the target AWS region
2. Add a key policy granting Confluent Cloud's service principal `kms:Encrypt` and `kms:Decrypt` permissions
3. Record the full ARN for use as `csfle_kms_key_id`

**IAM policy example:**
```json
{
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::CONFLUENT_ACCOUNT_ID:root"
  },
  "Action": [
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:GenerateDataKey"
  ],
  "Resource": "*"
}
```

### Azure Key Vault

**Access policy:** Grant the Confluent Cloud service principal access to the Key Vault key for wrap/unwrap operations.

**Key Identifier URI format:**
```
https://my-keyvault.vault.azure.net/keys/my-key/1234567890abcdef
```

**Terraform KMS type:** `azure-kms`

**Setup steps:**
1. Create a Key Vault with an RSA key (2048-bit or higher)
2. Add an access policy granting Confluent Cloud's service principal `Wrap Key` and `Unwrap Key` permissions
3. Record the full Key Identifier URI (including version) for use as `csfle_kms_key_id`

### GCP Cloud KMS

**IAM binding:** Grant the Confluent Cloud service account the `cloudkms.cryptoKeyEncrypterDecrypter` role on the key.

**Resource name format:**
```
projects/my-project/locations/us-central1/keyRings/my-keyring/cryptoKeys/my-key
```

**Terraform KMS type:** `gcp-kms`

**Setup steps:**
1. Create a Key Ring and Crypto Key in Cloud KMS
2. Add an IAM binding granting Confluent Cloud's service account the `cloudkms.cryptoKeyEncrypterDecrypter` role
3. Record the full resource name for use as `csfle_kms_key_id`

### HashiCorp Vault Transit

**Transit engine:** Configure a Vault Transit secrets engine with an encryption key for Confluent CSFLE.

**Key ID format:**
```
vault://transit/keys/my-csfle-key
```

**Terraform KMS type:** `hcvault`

**Setup steps:**
1. Enable the Transit secrets engine: `vault secrets enable transit`
2. Create an encryption key: `vault write -f transit/keys/my-csfle-key type=rsa-2048`
3. Create a Vault policy granting encrypt/decrypt on the key
4. Provide Vault address and token to the Schema Registry configuration

## Terraform Configuration

The FSI topic module supports CSFLE through data classification. When a topic is classified as `confidential` with PII fields specified, the module creates the necessary KEK registration and schema encryption rules automatically.

### Module Variables

| Variable | Description | Required for CSFLE |
|----------|-------------|-------------------|
| `data_classification` | Set to `"confidential"` to enable CSFLE | Yes |
| `pii_fields` | List of field names to encrypt (e.g., `["ssn", "account_number"]`) | Yes |
| `kek_name` | Name for the Key Encryption Key registration | Yes |
| `csfle_kms_type` | KMS provider: `"aws-kms"`, `"azure-kms"`, `"gcp-kms"`, or `"hcvault"` | Yes |
| `csfle_kms_key_id` | KMS key identifier (ARN, URI, resource name, or Vault path) | Yes |

### Example Module Call

```hcl
module "compliance_screening_result" {
  source = "../../modules/topic"

  domain          = "compliance"
  application     = "screening"
  schema_version  = "v1"
  entity          = "result"
  sla_tier        = "critical"
  owner_email     = "compliance-team@example.com"
  schema_file     = "../../schemas/examples/compliance-screening-result.avsc"

  # Data classification triggers CSFLE
  data_classification = "confidential"
  pii_fields          = ["subject_name", "ssn", "date_of_birth", "address"]

  # CSFLE KMS configuration
  kek_name         = "compliance-pii-kek"
  csfle_kms_type   = "aws-kms"
  csfle_kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-..."

  # Service accounts (at least one consumer required for confidential topics)
  producer_service_accounts = ["sa-111111"]
  consumer_service_accounts = ["sa-222222", "sa-333333"]

  # Cluster configuration
  kafka_cluster_id    = local.infra.kafka_cluster_id
  kafka_rest_endpoint = local.infra.kafka_rest_endpoint
  # ... remaining cluster config
}
```

### What the Module Creates

For a confidential topic, the module produces:

1. **KEK registration** (`confluent_schema_registry_kek`):
   ```hcl
   resource "confluent_schema_registry_kek" "pii" {
     name       = var.kek_name
     kms_type   = var.csfle_kms_type    # "aws-kms", "azure-kms", "gcp-kms"
     kms_key_id = var.csfle_kms_key_id
     shared     = true  # Required for DEK Registry to call KMS
   }
   ```

2. **Schema with encryption ruleset** (`confluent_schema` with `ruleset`):
   ```hcl
   ruleset {
     domain_rules {
       name = "encryptPII"
       kind = "TRANSFORM"
       type = "ENCRYPT"
       mode = "WRITEREAD"
       tags = ["PII"]
       params = {
         "encrypt.kek.name" = var.kek_name
       }
     }
   }
   ```

3. **Terraform validation** enforcing:
   - At least one consumer SA listed (no open access for confidential data)
   - PII fields list is non-empty

**Important:** Do NOT define an empty `ruleset {}` block. The Confluent provider explicitly prohibits empty ruleset blocks. The topic module uses `dynamic` blocks to conditionally include the ruleset only when `data_classification == "confidential"`.

## Client Configuration

Producers and consumers must include CSFLE-specific properties to encrypt and decrypt fields.

### Java Producer

```properties
# Standard OAUTHBEARER authentication (see scenarios/cc-*/oauth.tf)
bootstrap.servers=pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
security.protocol=SASL_SSL
sasl.mechanism=OAUTHBEARER
sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginCallbackHandler

# Schema Registry with CSFLE
schema.registry.url=https://psrc-xxxxx.us-east-1.aws.confluent.cloud
basic.auth.credentials.source=USER_INFO
schema.registry.basic.auth.user.info=SR_API_KEY:SR_API_SECRET

# CSFLE encryption/decryption rules
rule.executors=io.confluent.kafka.schemaregistry.encryption.FieldEncryptionExecutor
rule.executors.io.confluent.kafka.schemaregistry.encryption.FieldEncryptionExecutor.param.kek.name=compliance-pii-kek
rule.actions=io.confluent.kafka.schemaregistry.rules.RuleAction

# Value serializer with rule support
value.serializer=io.confluent.kafka.serializers.KafkaAvroSerializer
value.serializer.rule.executors=io.confluent.kafka.schemaregistry.encryption.FieldEncryptionExecutor
```

**Maven dependency:**
```xml
<dependency>
  <groupId>io.confluent</groupId>
  <artifactId>kafka-schema-registry-client-encryption</artifactId>
  <version>7.6.0</version>
</dependency>
```

### Java Consumer

```properties
# Standard OAUTHBEARER authentication
bootstrap.servers=pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
security.protocol=SASL_SSL
sasl.mechanism=OAUTHBEARER
sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginCallbackHandler

# Schema Registry with CSFLE
schema.registry.url=https://psrc-xxxxx.us-east-1.aws.confluent.cloud
basic.auth.credentials.source=USER_INFO
schema.registry.basic.auth.user.info=SR_API_KEY:SR_API_SECRET

# CSFLE decryption rules
rule.executors=io.confluent.kafka.schemaregistry.encryption.FieldEncryptionExecutor
rule.actions=io.confluent.kafka.schemaregistry.rules.RuleAction

# Value deserializer with rule support
value.deserializer=io.confluent.kafka.serializers.KafkaAvroDeserializer
value.deserializer.rule.executors=io.confluent.kafka.schemaregistry.encryption.FieldEncryptionExecutor
```

### .NET Producer

```csharp
var producerConfig = new ProducerConfig
{
    BootstrapServers = "pkc-xxxxx.us-east-1.aws.confluent.cloud:9092",
    SecurityProtocol = SecurityProtocol.SaslSsl,
    SaslMechanism = SaslMechanism.OAuthBearer,
    // OAUTHBEARER callback configured via handler
};

var schemaRegistryConfig = new SchemaRegistryConfig
{
    Url = "https://psrc-xxxxx.us-east-1.aws.confluent.cloud",
    BasicAuthUserInfo = "SR_API_KEY:SR_API_SECRET"
};

// CSFLE encryption is handled automatically by the serializer
// when the schema has encryption rules registered
var avroSerializerConfig = new AvroSerializerConfig
{
    // Rule executor handles field-level encryption
    RuleExecutors = "Confluent.SchemaRegistry.Encryption.FieldEncryptionExecutor"
};
```

## Validation

After configuring CSFLE, verify that encryption is working correctly.

### Step 1: Produce a Message

Send a message with PII fields populated:

```bash
# Using kafka-avro-console-producer with CSFLE config
kafka-avro-console-producer \
  --broker-list pkc-xxxxx.us-east-1.aws.confluent.cloud:9092 \
  --topic compliance.screening.v1.result \
  --property schema.registry.url=https://psrc-xxxxx.us-east-1.aws.confluent.cloud \
  --property value.schema.id=100001 \
  --producer.config csfle-producer.properties
```

### Step 2: Consume Raw (Verify Encryption)

Consume the message without CSFLE decryption configured. PII fields should appear as encrypted (base64-encoded bytes):

```bash
kafka-console-consumer \
  --bootstrap-server pkc-xxxxx.us-east-1.aws.confluent.cloud:9092 \
  --topic compliance.screening.v1.result \
  --from-beginning --max-messages 1 \
  --consumer.config basic-auth.properties
```

**Expected:** PII fields (ssn, subject_name, etc.) are encrypted byte arrays. Non-PII fields are readable.

### Step 3: Consume with Authorized Consumer (Verify Decryption)

Consume the message with CSFLE decryption configured and KMS access:

```bash
kafka-avro-console-consumer \
  --bootstrap-server pkc-xxxxx.us-east-1.aws.confluent.cloud:9092 \
  --topic compliance.screening.v1.result \
  --from-beginning --max-messages 1 \
  --consumer.config csfle-consumer.properties
```

**Expected:** All fields, including PII, are decrypted and readable in plaintext.

### Step 4: Consume Without KMS Access (Verify Authorization)

Consume with a consumer that does NOT have KMS key access:

**Expected:** Deserialization fails with a KMS permission error. This confirms that only authorized consumers can decrypt PII.

## Troubleshooting

### "encryption rules not supported"

**Cause:** The Confluent Cloud environment does not have the Stream Governance Advanced package enabled.

**Fix:** Upgrade the environment's Stream Governance package to Advanced. Contact your Confluent account team or enable via the Confluent Cloud console under Environment Settings > Stream Governance.

### KMS Permission Errors

**Cause:** The Confluent Cloud service principal does not have encrypt/decrypt permissions on the KMS key.

**Fix per provider:**
- **AWS KMS:** Verify the key policy includes the Confluent Cloud account ID with `kms:Encrypt`, `kms:Decrypt`, and `kms:GenerateDataKey` actions
- **Azure Key Vault:** Verify the access policy includes `Wrap Key` and `Unwrap Key` permissions for the Confluent service principal
- **GCP Cloud KMS:** Verify the IAM binding includes the `cloudkms.cryptoKeyEncrypterDecrypter` role for the Confluent service account
- **Vault Transit:** Verify the Vault policy includes `transit/encrypt/*` and `transit/decrypt/*` capabilities

### Empty Ruleset Block Error

**Cause:** An empty `ruleset {}` block was defined in the Terraform schema resource. The Confluent provider explicitly prohibits this.

**Fix:** Remove the empty `ruleset {}` block. Use `dynamic "ruleset"` blocks to conditionally include encryption rules only when `data_classification == "confidential"`. See the topic module implementation for the correct pattern.

### DEK Generation Fails

**Cause:** The KEK was registered with `shared = false`, preventing the DEK Registry from calling the KMS to generate DEKs.

**Fix:** Set `shared = true` on the `confluent_schema_registry_kek` resource. This is required for Connect and ksqlDB workloads and is the default in the topic module.

### Consumer Cannot Decrypt Despite KMS Access

**Cause:** The consumer is missing the CSFLE rule executor configuration.

**Fix:** Add the `rule.executors` and `rule.actions` properties to the consumer configuration (see Client Configuration above). The CSFLE encryption/decryption is handled by the serializer/deserializer rule executors, not the broker.

### Schema Registration Fails with Compatibility Error

**Cause:** Adding encryption rules to an existing schema may violate the compatibility mode (especially `FULL_TRANSITIVE` for critical topics).

**Fix:** For existing topics, register the encryption rules as a new schema version. Ensure the encryption rules are additive (new `ruleset` block on a compatible schema evolution). For new topics, register the schema with encryption rules from the start.
