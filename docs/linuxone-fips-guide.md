# LinuxONE FIPS Validation Guide

s390x-specific FIPS 140-2 compliance validation for Confluent Platform on IBM LinuxONE.

## Key Differences from x86 FIPS

| Aspect | x86 (OpenJDK) | s390x (IBM Semeru) |
|--------|---------------|-------------------|
| FIPS Provider | Bouncy Castle FIPS (`BcFipsProviderCreator`) | `IBMJCEPlusFIPS` / `IBMJCEFIPS` |
| Keystore Format | BCFKS (Bouncy Castle FIPS Keystore) | PKCS12 |
| Crypto Acceleration | Software-only (or AES-NI) | CPACF (hardware, transparent) |
| Provider Config | `java.security` + BC FIPS JARs | `java.security` provider order (built-in) |
| FIPS Enablement (OS) | `fips-mode-setup --enable` + reboot | Same |
| FIPS Enablement (OCP) | Post-install possible | Must be enabled at install time |

## Validation Checks

### 1. OS-Level FIPS

```bash
cat /proc/sys/crypto/fips_enabled
# Must return: 1
```

### 2. IBM JDK FIPS Providers

```bash
java -XshowSettings:security 2>&1 | grep -i fips
# Should show IBMJCEPlusFIPS or IBMJCEFIPS in provider list
```

### 3. CPACF Detection (Informational)

```bash
# Check for CPACF instruction support
cat /proc/cpuinfo | grep -i "facilities"
# Look for: MSA (Message Security Assist) facility indicators
```

CPACF accelerates crypto transparently. Its presence improves performance but is not required for FIPS compliance.

### 4. PKCS12 Keystore Validation

```bash
# Verify keystore loads on FIPS-enabled system
keytool -list -keystore /etc/kafka/ssl/broker0.keystore.p12 \
  -storetype PKCS12 -storepass "${KEYSTORE_PASSWORD}"
```

If this fails with MAC algorithm errors, regenerate with:

```bash
keytool -importkeystore -srckeystore old.p12 -destkeystore new.p12 \
  -deststoretype PKCS12 \
  -J-Dkeystore.pkcs12.macAlgorithm=HmacPBESHA256 \
  -J-Dkeystore.pkcs12.macIterationCount=100000
```

### 5. TLS Handshake Verification

```bash
openssl s_client -connect broker0.kafka.fsi.internal:9093 \
  -CAfile /etc/kafka/ssl/ca-cert.pem \
  -verify_return_error -brief
```

### 6. NTP Skew Check

```bash
# Verify time sync (FIPS cert validation is time-sensitive)
chronyc sources -v
# Offset should be < 1 second
```

## Ansible Playbook

The extended `validate-fips.yml` playbook detects architecture and runs the appropriate checks:

```bash
# On s390x: runs IBM provider + PKCS12 + CPACF checks
# On x86: runs BC FIPS + BCFKS checks
ansible-playbook playbooks/validate-fips.yml
```
