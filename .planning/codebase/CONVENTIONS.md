# Coding Conventions

**Analysis Date:** 2026-03-21

## Naming Patterns

**Files:**
- Java source files: PascalCase class name matching `ClassName.java` (e.g., `FsiProducer.java`)
- Configuration files: kebab-case with extensions (e.g., `connect-distributed-east.properties`, `terraform.tfvars.example`)
- Schema files: kebab-case `.avsc` (e.g., `account-transaction.avsc`)
- Terraform files: `main.tf`, `variables.tf`, `outputs.tf` per module
- Shell scripts: kebab-case with shebang (e.g., `mirror-failover.sh`, `roundtrip-test.sh`)
- .NET classes: PascalCase (e.g., `FsiProducer.cs`, `FsiProducerConfig.cs`)

**Functions/Methods:**
- Java: camelCase for instance methods (e.g., `send()`, `sendSync()`, `buildProperties()`)
- Java: UPPER_SNAKE_CASE for constants (e.g., `BOOTSTRAP_SERVERS_CONFIG`)
- Shell: snake_case for functions and variables (e.g., `$MIRROR_TOPICS`, `$CONFIRM`)
- .NET: PascalCase for public methods (e.g., `ProduceAsync()`, `Flush()`)

**Variables:**
- Java: camelCase (e.g., `topicName`, `totalSent`, `recordHandler`)
- Java atomic counters: camelCase with clear intent (e.g., `totalConsumed`, `lastLatencyMs`)
- Terraform: snake_case (e.g., `var.domain`, `local.topic_name`, `var.producer_service_accounts`)
- Shell: UPPER_SNAKE_CASE for env vars and module-level state (e.g., `$DR_ENV_ID`, `$MIRROR_TOPICS`)
- Shell: lowercase for loop variables and temps (e.g., `i`, `err`)
- .NET: camelCase for private fields (e.g., `_producer`, `_topicName`, `_totalErrors`)

**Types:**
- Terraform: explicit type declarations (e.g., `type = string`, `type = list(string)`, `type = bool`)
- Avro schemas: snake_case field names with logical types (e.g., `transaction_id`, `timestamp` with `timestamp-millis` logical type)
- Java generics: single letter or clear abbreviation (e.g., `KafkaProducer<String, GenericRecord>`)

## Code Style

**Formatting:**
- Java: 4-space indentation (standard Java convention)
- Terraform: 2-space indentation (HCL standard)
- Shell: 2-space indentation
- .NET: 4-space indentation (C# standard)
- No automatic formatter detected — manual consistency required

**Linting:**
- Java: No formal linter config found (Maven enforcer could be added)
- Terraform: Validation syntax is built-in (`terraform validate`)
- Shell: Uses `set -euo pipefail` for strict error handling (see `mirror-failover.sh`)
- .NET: No explicit linting configuration

**Comment Style:**
- Java: JavaDoc for public methods with `/**` blocks (see `FsiProducer.java` lines 42-51, 65-68)
- Java: Single-line comments (`//`) for implementation details
- Shell: Full-width separator comments for sections (e.g., lines 2-3 in `mirror-failover.sh`)
- Terraform: Inline comments with `#` for documentation (see `modules/topic/main.tf` lines 32-34)

## Import Organization

**Order (Java):**
1. JDK imports (e.g., `java.util.*`, `java.time.*`, `java.nio.*`)
2. Third-party framework imports (e.g., Kafka, Confluent, Avro)
3. SLF4J logging
4. Application/local imports

**Example from `FsiProducer.java`:**
```java
import io.confluent.kafka.serializers.KafkaAvroSerializer;
import org.apache.avro.generic.GenericRecord;
import org.apache.kafka.clients.producer.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.management.*;
import java.lang.management.ManagementFactory;
import java.time.Duration;
import java.util.*;
```

**Terraform:**
- No explicit ordering — blocks grouped by logical function (e.g., topic config, RBAC bindings, DR mirror)
- Variable references via `var.x` and local computed values via `local.x`

**Path Aliases:**
- No path aliases detected in Java codebase
- Terraform uses relative file paths (e.g., `var.schema_file` expects a relative `.avsc` path from the calling module)

## Error Handling

**Java Pattern: Try-Catch with Logging**
```java
try {
    // Operation
    producer.send(record).get();
    totalSent.incrementAndGet();
} catch (Exception e) {
    totalErrors.incrementAndGet();
    log.error("Failed to produce to {} [key={}]: {}", topicName, key, e.getMessage(), e);
    // Application-specific error handling here (DLQ, retry, alert)
}
```
- Log errors at `ERROR` level with context (topic, key, offset)
- Increment error counter atomically
- Include both message and exception (`.getMessage(), e`)
- Comments indicate options: DLQ, retry, alert (see `FsiProducer.java` lines 134-141)

**Shell Pattern: Exit on Error**
```bash
set -euo pipefail
# Causes immediate exit on error, undefined vars, pipe failures
```
- Exit code checked implicitly by `set -e`
- User confirmation before destructive operations (see `mirror-failover.sh` lines 34-35)

**.NET Pattern: Exception Propagation**
```csharp
try {
    var result = await _producer.ProduceAsync(...);
    Interlocked.Increment(ref _totalSent);
    return result;
} catch (ProduceException<string, GenericRecord> ex) {
    Interlocked.Increment(ref _totalErrors);
    Console.Error.WriteLine($"[FSI Producer] Failed to produce [key={key}]: {ex.Error.Reason}");
    throw;
}
```
- Specific exception types caught
- Error counters incremented
- Exceptions re-thrown for caller handling

**Terraform Pattern: Variable Validation**
```hcl
variable "domain" {
  description = "Business domain (e.g., cncb, rtfd, ofac)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.domain))
    error_message = "Domain must be lowercase alphanumeric with hyphens, 2-31 chars, starting with a letter."
  }
}
```
- Inline validation blocks with `regex()` for string constraints
- Clear error messages matching constraint description
- Replaces runtime errors with build-time validation

## Logging

**Framework:** SLF4J with slf4j-simple backend

**Patterns (Java):**
```java
private static final Logger log = LoggerFactory.getLogger(ClassName.class);
```
- Static logger instance per class (see `FsiProducer.java` line 32)
- Use parameterized messages: `log.info("Message: {}", param)` not string concatenation
- Log levels:
  - `INFO`: Initialization, shutdown, key state changes (see line 62: "FSI Producer initialized")
  - `DEBUG`: Record details (see line 144: "Produced to topic-partition")
  - `ERROR`: Exceptions with full context (see line 136: "Failed to produce")
  - `WARN`: JMX registration failures (see line 203: "Failed to register JMX metrics")

**.NET Pattern:**
```csharp
Console.WriteLine($"[FSI Producer] Initialized for topic: {_topicName}");
Console.Error.WriteLine($"[FSI Producer ERROR] {error.Reason}");
```
- Console output with `[FSI Producer]` prefix for identification
- Errors to `Console.Error`
- No structured logging framework detected

## Comments

**When to Comment:**
- Explain WHY, not WHAT (code shows what, comment explains business reason or non-obvious choice)
- Mark integration points and special behaviors (see `FsiProducer.java` line 28: "reference implementation. Copy and adapt")
- Document configuration defaults and justifications (see `modules/topic/main.tf` lines 72-107 for C4E mandatory settings)

**JavaDoc/TSDoc (Java):**
- Public classes: Full block with purpose and key characteristics (see `FsiProducer.java` lines 18-29)
- Public methods: Block with `@param` and description (see line 42-51)
- Configuration/builder patterns: Explain the "why" of values (see lines 65-68)

**Example:**
```java
/**
 * FSI C4E Reference Producer
 *
 * Key characteristics:
 * - Idempotent (enable.idempotence=true) for exactly-once per partition
 * - Avro serialization with Schema Registry auto-registration
 * - JMX metrics exposed for Dynatrace OneAgent
 * - Graceful shutdown with flush + close
 * - Callback-based error handling with logging
 *
 * This is a reference implementation. Copy and adapt for your application.
 */
```

## Function Design

**Size:** Reference implementations are 200-250 lines (whole-class); individual methods 20-50 lines

**Parameters:**
- Map-based config injection: `FsiProducer(Map<String, String> config)` (see line 52)
- Handler functions as functional interfaces: `BiConsumer<String, GenericRecord> recordHandler` (see `FsiConsumer.java` line 44)
- No builder pattern — plain constructor with Map config, derived from environment/Vault at call site

**Return Values:**
- Void for fire-and-forget (asynchronous): `send(String key, GenericRecord value)` with callback
- RecordMetadata for synchronous: `sendSync()` returns offset/partition/topic
- Wrapper objects for multiple returns (e.g., `FsiProducerConfig` class holds config data)

## Module Design

**Exports (Java):**
- Public classes implement interfaces (e.g., `FsiProducer implements AutoCloseable`) for try-with-resources
- Private inner classes for metrics (e.g., `FsiProducerMetrics implements FsiProducerMetricsMBean`)
- Static logger and atomic counters for telemetry

**Terraform Modules:**
- Single module `modules/topic/` exported via `source = "../../modules/topic"` in environment configs
- Outputs defined in `modules/topic/outputs.tf` (structure not shown, but patterns in `main.tf` lines 91-245 suggest topic name, partition count, schema subject)
- No barrel files — each Terraform module is a single unit

## Shutdown and Lifecycle

**Java Pattern: AutoCloseable with Graceful Shutdown**
```java
@Override
public void close() {
    log.info("Shutting down producer for topic: {}", topicName);
    producer.flush();
    producer.close(Duration.ofSeconds(30));
    log.info("Producer closed. Total sent: {}, errors: {}", totalSent.get(), totalErrors.get());
}
```
- Flush before close to ensure durability
- 30-second timeout for graceful termination
- Log final metrics (total sent, errors)
- Implement try-with-resources usage

**Shutdown Hooks (Consumer):**
```java
private void registerShutdownHook() {
    Runtime.getRuntime().addShutdownHook(new Thread(() -> {
        log.info("Shutdown hook triggered");
        shutdown();
    }, "fsi-consumer-shutdown"));
}
```
- Named thread for identification in logs
- Calls `consumer.wakeup()` to unblock poll loop

## Cross-Cutting Concerns

**Validation:**
- Terraform: Inline `validation` blocks with regex or function-based checks (see `modules/topic/variables.tf` lines 12-15, 103-106)
- Java: Constructor parameter validation with `IllegalArgumentException` (see `FsiProducer.java` lines 54-56)
- Email validation: RFC-like pattern `^[^@]+@[^@]+\\.[^@]+$` (see `variables.tf` line 56)

**Configuration:**
- Environment variable defaults in Java: `config.getOrDefault("key", "default")`
- Terraform locals for computed values (topic_name assembly, SLA-tier mappings)
- Shell: Environment variables with `${VAR:?Set VAR}` for required, `${VAR:-default}` for optional

**Dependency Injection:**
- Map-based config object passed to constructor (not Spring annotations or frameworks)
- Handler functions injected as functional interfaces (consumer pattern)
- Terraform variables injected via tfvars files or environment

---

*Convention analysis: 2026-03-21*
