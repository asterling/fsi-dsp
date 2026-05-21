# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-21)

**Core value:** Any FSI team can stand up a governed, observable, DR-ready Kafka/Flink/SR cluster with a single automation run.
**Current focus:** Phase 17 — FSI-Hardened Confluent-on-LinuxONE Accelerator

## Current Position

Phase: 17 of 17 (FSI-Hardened Confluent-on-LinuxONE Accelerator)
Plan: Tracked as quick task
Status: Complete
Last activity: 2026-05-21 — Executed quick task 260521-26u: built accelerators/confluent-on-linuxone/ (10 tasks, 53 files, 10 commits)

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

- Update UPSTREAM_SHA in base/fetch-upstream.sh to actual mmondics/Confluent-LinuxONE-Mirror commit SHA
- Regenerate .flox/env/manifest.lock on a Flox-equipped machine (KNOWN-GAPS G-07)
- Build custom s390x Connect image with Splunk Sink + HTTP Sink JARs (KNOWN-GAPS G-08)

### Blockers/Concerns

- s390x compatibility must be verified per tool/image; gaps go in accelerator KNOWN-GAPS.md

## Session Continuity

Last session: 2026-05-21
Stopped at: Completed quick task 260521-26u — accelerators/confluent-on-linuxone/ fully built
Resume file: None
