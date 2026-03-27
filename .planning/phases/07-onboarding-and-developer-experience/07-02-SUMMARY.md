---
phase: 07-onboarding-and-developer-experience
plan: 02
subsystem: reference-implementations
tags: [python, kafka, avro, dlq, producer, consumer, prometheus, confluent-kafka, dead-letter-queue]

# Dependency graph
requires:
  - phase: 06-flink-on-confluent-cloud
    provides: "DLQ pattern SQL template and topic naming convention"
provides:
  - "Python FsiProducer with Avro, idempotence, Prometheus metrics, DLQ routing"
  - "Python FsiConsumer with manual commit, handler pattern, AvroDeserializer"
  - "Python FsiDlqHandler with 3-retry exponential backoff and error categorization"
  - "Java FsiDlqHandler retrofitted into existing Java producer"
  - ".NET FsiDlqHandler retrofitted into existing .NET producer"
  - "DLQ handling pattern consistent across all 3 languages (Java, .NET, Python)"
affects: [07-onboarding-and-developer-experience, reference-implementations, observability]

# Tech tracking
tech-stack:
  added: [confluent-kafka-python-2.13.2, prometheus_client-0.24.1]
  patterns: [dlq-error-categorization, exponential-backoff-retry, kafka-headers-metadata, multi-language-parity]

key-files:
  created:
    - reference/python-producer/fsi_producer.py
    - reference/python-producer/fsi_dlq_handler.py
    - reference/python-producer/requirements.txt
    - reference/python-producer/README.md
    - reference/python-consumer/fsi_consumer.py
    - reference/python-consumer/requirements.txt
    - reference/python-consumer/README.md
    - reference/java-producer/src/main/java/org/fsi/kafka/producer/FsiDlqHandler.java
    - reference/dotnet-producer/FsiDlqHandler.cs
  modified:
    - reference/java-producer/src/main/java/org/fsi/kafka/producer/FsiProducer.java
    - reference/dotnet-producer/FsiProducer.cs

key-decisions:
  - "Python uses modern AvroSerializer/AvroDeserializer API (not deprecated AvroProducer/AvroConsumer)"
  - "Prometheus metrics for Python (Counter/Gauge) vs Java JMX vs .NET public property -- per-language idiomatic observability"
  - "DLQ producer is a separate raw-bytes producer instance in all 3 languages to avoid serialization coupling"
  - "Consumer metrics port defaults to 9091 to avoid collision with producer metrics on 9090"

patterns-established:
  - "DLQ handler pattern: 3 retries, exponential backoff (1s/2s/4s), error categorization (SERIALIZATION/AUTH_DENIED/BROKER_TIMEOUT/SCHEMA_INCOMPATIBLE/UNKNOWN)"
  - "DLQ topic naming: {source-topic}.dlq convention across all languages"
  - "DLQ Kafka headers: dlq.original.topic, dlq.error.type, dlq.error.message, dlq.timestamp, dlq.retry.count, dlq.producer.client.id"
  - "Python reference pattern: dict-based config, context manager, Prometheus metrics"

requirements-completed: [ONBOARD-03, ONBOARD-06]

# Metrics
duration: 6min
completed: 2026-03-27
---

# Phase 07 Plan 02: Reference Implementations & DLQ Summary

**Python producer/consumer mirroring Java patterns with Avro/Prometheus/DLQ, plus DLQ handlers retrofitted into all 3 languages (Java, .NET, Python) with identical 3-retry exponential backoff and error categorization**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-27T14:34:50Z
- **Completed:** 2026-03-27T14:41:28Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments

- Python FsiProducer with idempotent delivery, Avro serialization (modern AvroSerializer API), Prometheus metrics, and DLQ routing -- mirrors Java FsiProducer method signatures (send, send_sync, flush, close)
- Python FsiConsumer with manual offset commit, handler function pattern, AvroDeserializer, SIGTERM/SIGINT shutdown -- mirrors Java FsiConsumer (start, shutdown)
- DLQ handlers in all 3 languages with identical behavior: 3-retry exponential backoff (1s/2s/4s), error categorization (SERIALIZATION, AUTH_DENIED, BROKER_TIMEOUT, SCHEMA_INCOMPATIBLE, UNKNOWN), 6 Kafka metadata headers, {source-topic}.dlq naming
- DLQ metrics observable in all 3 languages: Java JMX getDlqSent(), Python Prometheus Counter, .NET public DlqSent property with Dispose() log

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Python reference producer and consumer with DLQ handler** - `56095f7` (feat)
2. **Task 2: Retrofit DLQ handling into existing Java and .NET producers** - `b100efb` (feat)

## Files Created/Modified

- `reference/python-producer/fsi_producer.py` - Python FsiProducer class with Avro, idempotence, Prometheus metrics, DLQ
- `reference/python-producer/fsi_dlq_handler.py` - Python DLQ handler with error categorization and retry logic
- `reference/python-producer/requirements.txt` - confluent-kafka[avro]==2.13.2, prometheus_client==0.24.1
- `reference/python-producer/README.md` - Usage examples, config reference, metrics, DLQ behavior
- `reference/python-consumer/fsi_consumer.py` - Python FsiConsumer class with manual commit and handler pattern
- `reference/python-consumer/requirements.txt` - confluent-kafka[avro]==2.13.2, prometheus_client==0.24.1
- `reference/python-consumer/README.md` - Usage examples, config reference, shutdown behavior
- `reference/java-producer/.../FsiDlqHandler.java` - Java DLQ handler with NON_RETRYABLE set, sendToDlq, classifyError
- `reference/java-producer/.../FsiProducer.java` - Added dlqHandler field, DLQ routing in send callback, getDlqSent JMX
- `reference/dotnet-producer/FsiDlqHandler.cs` - .NET DLQ handler with SendToDlqAsync, IsRetryable, DlqSent property
- `reference/dotnet-producer/FsiProducer.cs` - Added _dlqHandler field, DLQ routing in ProduceAsync catch, DLQ in Dispose log

## Decisions Made

- **Modern confluent-kafka API:** Python uses AvroSerializer/AvroDeserializer (not deprecated AvroProducer/AvroConsumer) for forward compatibility
- **Per-language idiomatic observability:** Java exposes DLQ metrics via JMX MBean, Python via Prometheus Counter, .NET via public property + console log -- each follows the language's existing observability pattern
- **Separate DLQ producer:** All 3 languages create a dedicated raw-bytes Producer for DLQ writes, avoiding serialization coupling with the main Avro producer
- **Consumer metrics port 9091:** Python consumer defaults to port 9091 for Prometheus to avoid collision with producer on 9090

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all code is fully wired with real logic.

## Next Phase Readiness

- Python teams can now use the same C4E-compliant patterns as Java and .NET teams
- DLQ handling is consistent across all 3 language reference implementations
- Ready for plan 03 (onboarding documentation and starter kits)

---
*Phase: 07-onboarding-and-developer-experience*
*Completed: 2026-03-27*
