# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-21)

**Core value:** Any FSI team can stand up a governed, observable, DR-ready Kafka/Flink/SR cluster with a single automation run.
**Current focus:** Phase 17 — FSI-Hardened Confluent-on-LinuxONE Accelerator

## Current Position

Phase: 17 of 17 (FSI-Hardened Confluent-on-LinuxONE Accelerator)
Plan: Tracked as quick task
Status: Complete
Last activity: 2026-05-22 — Executed quick task 260522-kjt: added layers/05-flink to accelerators/confluent-on-linuxone/ (8 tasks, 28 files, 7 commits)

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**
- Total plans completed: v1.0 + v2.0 + Phase 16 (archived)
- v2.0 milestone audit: 42/42 requirements passed

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Recent:

- [Accelerator]: Base = fetch-by-SHA (upstream repo has no LICENSE)
- [Accelerator]: auditor-readonly = audit-topic-scoped (no business-payload access)
- [Accelerator]: Reuse existing cfk_operator / cp_rbac / cp_mtls / observability assets

### Pending Todos

- Regenerate .flox/env/manifest.lock on a Flox-equipped machine (KNOWN-GAPS G-07)
- Build custom s390x Connect image with Splunk Sink + HTTP Sink JARs (KNOWN-GAPS G-08)
- Build custom s390x SQL-runner image per layers/05-flink/sql-runner/README.md (KNOWN-GAPS G-12)
- Configure encrypted StorageClass/SSE endpoint for Flink checkpoint state (KNOWN-GAPS G-13)

### Blockers/Concerns

- s390x compatibility must be verified per tool/image; gaps go in accelerator KNOWN-GAPS.md

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260521-26u | FSI-hardened Confluent-on-LinuxONE accelerator — fork Mondics runbook + 4 hardening layers | 2026-05-21 | c511571 | [260521-26u-build-accelerators-confluent-on-linuxone](./quick/260521-26u-build-accelerators-confluent-on-linuxone/) |
| 260522-kjt | Add Apache Flink as layer 05 of the confluent-on-linuxone accelerator | 2026-05-22 | e4b08da | [260522-kjt-add-apache-flink-as-layer-05-of-the-conf](./quick/260522-kjt-add-apache-flink-as-layer-05-of-the-conf/) |

## Session Continuity

Last session: 2026-05-22
Stopped at: Completed quick task 260522-kjt — layers/05-flink added to accelerators/confluent-on-linuxone/
Resume file: None
