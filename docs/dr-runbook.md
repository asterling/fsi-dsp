# FSI Kafka Platform -- DR Runbook

**Last Updated:** 2026-03-24
**Owner:** FSI C4E
**Status:** Active

## Overview

This runbook covers disaster recovery procedures for the FSI Kafka Platform using Confluent Cloud Cluster Linking. It is the authoritative reference for on-call engineers during DR events.

**Architecture:** East (primary, active) <-> West (DR, passive) via bidirectional Cluster Link.
**Service Discovery:** Consul KV (`fsi/kafka/active-region`) flips Kafka, Schema Registry, and Oracle endpoints atomically.
**DR CLI:** `scripts/fsi-dr.sh` automates the procedures below. Manual steps are documented as fallback.

**Key architectural decisions:**
- ADR-003: Consul for service discovery (single KV flip for all endpoints)
- ADR-005: Cluster Linking over MRC (async replication, manual 6-step failover)
- ADR-008: DR tier classification (SLA-based RPO/RTO targets and mirror lag thresholds)

## Quick Reference

| Action | Command |
|--------|---------|
| Check DR status | `fsi-dr.sh status` |
| Preview failover | `fsi-dr.sh failover --dry-run` |
| Execute failover | `fsi-dr.sh failover` |
| Execute failover (CI) | `fsi-dr.sh failover --force` |
| Preview failback | `fsi-dr.sh failback --dry-run` |
| Execute failback | `fsi-dr.sh failback` |
| Execute failback (CI) | `fsi-dr.sh failback --force` |

## Prerequisites

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `FSI_DR_ENV_ID` | Yes | -- | Production (East) environment ID |
| `FSI_DR_CLUSTER_ID` | Yes | -- | Production (East) cluster ID |
| `FSI_DR_DR_ENV_ID` | Yes | -- | DR (West) environment ID |
| `FSI_DR_DR_CLUSTER_ID` | Yes | -- | DR (West) cluster ID |
| `FSI_CONNECT_URL` | No | `http://localhost:8083` | Kafka Connect REST endpoint |
| `CONSUL_HTTP_ADDR` | No | `http://localhost:8500` | Consul HTTP address |
| `FSI_CLUSTER_LINK_NAME` | No | `cluster_link_bidir_east_west` | Cluster link name |
| `FSI_DR_STATE_FILE` | No | `/tmp/fsi-dr-state.json` | State file path |
| `FSI_DR_BACKEND` | No | `cluster-linking` | DR backend (cluster-linking or mm2) |
| `FSI_DR_SYNC_TIMEOUT` | No | `300` | Failback sync wait timeout (seconds) |

### Tool Dependencies

- `confluent` CLI (2.x) -- authenticated with appropriate service account
- `consul` CLI (1.x) -- configured with `CONSUL_HTTP_ADDR`
- `jq` (1.6+) -- JSON processing
- `curl` (7.x) -- Connect REST API calls
- `dig` (system) -- DNS endpoint verification

### Pre-Deployment Verification

Before any DR event, verify your environment:

```bash
# Verify CLI authentication
confluent environment list

# Verify cluster access
confluent kafka cluster describe $FSI_DR_CLUSTER_ID --environment $FSI_DR_ENV_ID

# Verify Consul connectivity
consul kv get fsi/kafka/active-region

# Verify Connect API
curl -s $FSI_CONNECT_URL/connectors

# Full pre-flight check
fsi-dr.sh status
```

## SLA Tier Reference

| SLA Tier | RPO Target | RTO Target | Mirror Lag Warn | Mirror Lag Alert | Priority |
|----------|-----------|-----------|-----------------|------------------|----------|
| critical | < 5 min | < 15 min | 30s | 60s | P1 -- immediate |
| compliance | RPO = 0 | < 15 min | 10s | 30s | P1 -- immediate |
| standard | < 2 hours | < 1 hour | 5 min | 15 min | P2 -- business hours |
| best-effort | < 24 hours | < 4 hours | 1 hour | 4 hours | P3 -- next business day |

**Priority ordering:** During a multi-topic outage, prioritize failover verification by tier: compliance and critical first, then standard, then best-effort.

**Data loss assessment:** Before failover, run `fsi-dr.sh failover --dry-run` to see per-topic lag. Any topic with lag above its tier's alert threshold represents potential data loss if failover proceeds.

## Failover Procedure

### When to Failover

- East region confirmed unavailable (not a transient network issue)
- RTO clock has started for critical/compliance topics
- On-call lead has approved DR activation
- `fsi-dr.sh failover --dry-run` pre-flight checks pass

### Decision Tree: Go / No-Go

```
1. Is East confirmed down?
   |
   +-- NO --> Wait 5 minutes, re-check. Is it still down?
   |          |
   |          +-- NO --> Do not failover. Monitor.
   |          +-- YES --> Continue to step 2.
   |
   +-- YES --> Continue to step 2.

2. Run: fsi-dr.sh failover --dry-run
   Is pre-flight green (all checks pass)?
   |
   +-- NO --> Fix reported issues first:
   |          - DR cluster unreachable? Escalate to cloud ops.
   |          - No active mirrors? Check cluster link health.
   |          - Connect API down? Proceed without connectors (manual resume later).
   |          - Consul down? Proceed with manual DNS updates.
   |
   +-- YES --> Continue to step 3.

3. Are critical/compliance topics within RPO threshold?
   (Check mirror lag in dry-run output)
   |
   +-- NO --> Acknowledge data loss risk.
   |          Document: which topics, how much lag, business impact.
   |          Get explicit approval from on-call lead.
   |
   +-- YES --> Continue to step 4.

4. Execute: fsi-dr.sh failover
   (or: fsi-dr.sh failover --force for CI/automation)
```

### Step-by-Step: Failover

The automated failover (`fsi-dr.sh failover`) executes 6 steps in sequence. Each step is documented below with success criteria, abort criteria, rollback guidance, and manual fallback commands.

#### Step 1: Pause Connectors

- **What happens:** Snapshots the current state of all Kafka Connect connectors, then pauses all RUNNING connectors via the Connect REST API. Intentionally-paused connectors are tracked but not touched.
- **Success criteria:** All targeted connectors report `state=PAUSED`. State snapshot is saved.
- **Abort criteria:** Connect REST API unreachable after retries. System is not yet modified -- safe to abort.
- **Rollback:** Resume paused connectors:
  ```bash
  curl -s -X PUT ${FSI_CONNECT_URL}/connectors/<name>/resume
  ```
- **Manual fallback:** `./scripts/connect-pause-all.sh pause`

#### Step 2: Promote Mirror Topics

- **What happens:** Promotes all active mirror topics on the West (DR) cluster using `confluent kafka mirror failover`. After promotion, topics on West become read-write (no longer mirroring).
- **Success criteria:** All mirror topics report `status=STOPPED` (promoted, now R/W on West).
- **Abort criteria:** No active mirrors found on DR cluster. Check cluster link health: `confluent kafka mirror list --link $FSI_CLUSTER_LINK_NAME --cluster $FSI_DR_DR_CLUSTER_ID --environment $FSI_DR_DR_ENV_ID`
- **Rollback:** Cannot un-promote mirrors. Once promoted, topics are independent. Requires full failback procedure to restore East as primary.
- **Manual fallback:** `./scripts/mirror-failover.sh`
- **WARNING:** The CLI uses `mirror failover` (emergency promotion). Do NOT use `mirror promote` (planned migration) during a DR event -- different semantics.

#### Step 3: Flip Consul to West

- **What happens:** Updates Consul KV key `fsi/kafka/active-region` from `east` to `west`. This atomically redirects all Consul-resolved endpoints (Kafka bootstrap, Schema Registry, Oracle JDBC) to the West region.
- **Success criteria:** `consul kv get fsi/kafka/active-region` returns `west`.
- **Abort criteria:** Consul unreachable. Mirrors are promoted but endpoints still point to East. Applications will see errors until Consul is flipped.
- **Rollback:** `consul kv put fsi/kafka/active-region east`
- **Manual fallback:** `./scripts/consul-flip-region.sh west`

#### Step 4: Verify Endpoint Resolution

- **What happens:** Verifies DNS resolves Kafka, Schema Registry, and Oracle endpoints to West IPs. Retries up to 10 times with 3-second intervals to handle DNS propagation delay.
- **Success criteria:** `dig +short kafka.fsi.internal`, `dig +short schema.fsi.internal`, and `dig +short oracle.fsi.internal` all return West IPs.
- **Abort criteria:** DNS not updating after 30 seconds. Check Consul DNS health, DNS TTL, and Consul agent status.
- **Rollback:** If endpoints resolve incorrectly, flip Consul back: `consul kv put fsi/kafka/active-region east`
- **Manual verification:**
  ```bash
  dig +short kafka.fsi.internal
  dig +short schema.fsi.internal
  dig +short oracle.fsi.internal
  ```

#### Step 5: Resume Connectors

- **What happens:** Resumes only connectors that were RUNNING before Step 1 (from the state file snapshot). Intentionally-paused connectors are NOT resumed.
- **Success criteria:** Previously-RUNNING connectors report `state=RUNNING`.
- **Abort criteria:** Connector fails to resume. Check Connect worker logs. Failover is functionally complete at this point -- connector issues are operational, not DR-blocking.
- **Rollback:** N/A. Failover is functionally complete. Connector issues can be resolved separately.
- **Note:** Connectors that were intentionally PAUSED before failover remain paused per state tracking.

#### Step 6: Final Validation

- **What happens:** Verifies West (DR) cluster is serving traffic: cluster accessible, mirrors promoted (no active mirrors remaining), connectors running.
- **Success criteria:** All validation checks pass.
- **Abort criteria:** N/A. This is informational -- failover is complete by this step.
- **Rollback:** N/A. If validation fails, investigate specific issues rather than rolling back.

### Post-Failover Checklist

After failover completes:

- [ ] Verify applications are producing to West cluster
- [ ] Check consumer lag on West cluster
- [ ] Verify Schema Registry is accessible on West
- [ ] Confirm Connect connectors are processing records
- [ ] Monitor West cluster for any resource warnings (CPU, storage, throughput)
- [ ] Update incident ticket with failover completion time and any data loss assessment
- [ ] Begin planning failback (when East is recovered)

## Failback Procedure

### When to Failback

- East region confirmed recovered and stable (not intermittently available)
- Mirror lag from West to East is near-zero (verify with `fsi-dr.sh status`)
- Change window approved (failback is a planned operation, not an emergency)
- On-call lead has approved failback execution
- `fsi-dr.sh failback --dry-run` pre-flight checks pass

### Decision Tree: Go / No-Go

```
1. Is East confirmed healthy and stable?
   |
   +-- NO --> Wait. Do not attempt failback to an unstable cluster.
   |          Monitor East health metrics for at least 30 minutes.
   |
   +-- YES --> Continue to step 2.

2. Run: fsi-dr.sh failback --dry-run
   Are pre-flight checks green?
   |
   +-- NO --> Fix reported issues:
   |          - East unreachable? Cannot failback. Wait for recovery.
   |          - West unreachable? Cannot failback (data source unavailable).
   |          - Connect API down? Proceed without connectors (manual resume later).
   |
   +-- YES --> Continue to step 3.

3. Is this a planned change window?
   |
   +-- NO --> Schedule a change window. Failback is not an emergency.
   |          Failback involves destructive operations (truncate-and-restore)
   |          that require careful execution and monitoring.
   |
   +-- YES --> Continue to step 4.

4. Execute: fsi-dr.sh failback
   (or: fsi-dr.sh failback --force for CI/automation)
```

### Step-by-Step: Failback

The automated failback (`fsi-dr.sh failback`) executes 8 steps in sequence. Failback has two confirmation gates at destructive operations (Steps 3 and 5).

#### Step 1: Verify East Cluster

- **What happens:** Verifies the East (production) cluster is reachable and healthy. This is a prerequisite -- failback cannot proceed if East is down.
- **Success criteria:** East cluster responds to `confluent kafka cluster describe` with valid JSON.
- **Abort criteria:** East cluster not reachable. Wait for East recovery before retrying.
- **Rollback:** N/A. No changes made. System remains on West.

#### Step 2: Pause Connectors on West

- **What happens:** Snapshots the state of all connectors on the current active (West) cluster, then pauses all RUNNING connectors to prevent writes during data sync.
- **Success criteria:** All targeted connectors report `state=PAUSED`.
- **Abort criteria:** Connect REST API unreachable. System is still running on West -- safe to abort.
- **Rollback:** Resume paused connectors:
  ```bash
  curl -s -X PUT ${FSI_CONNECT_URL}/connectors/<name>/resume
  ```
- **Manual fallback:** `./scripts/connect-pause-all.sh pause`

#### Step 3: Truncate and Restore (DESTRUCTIVE)

- **What happens:** Truncates East topic data and configures East topics as mirrors from West. This copies current West data to East. **This is a destructive operation** -- East topic data is truncated.
- **Success criteria:** East topics are now mirrors of West topics. `confluent kafka mirror list` shows mirrors in ACTIVE state on East.
- **Abort criteria:** If truncate-and-restore fails partway, some East topics may be truncated while others are not. Check mirror status carefully.
- **Rollback:** **CRITICAL** -- If partially completed, some East topics may have truncated data. Check East mirror status:
  ```bash
  confluent kafka mirror list --link $FSI_CLUSTER_LINK_NAME --cluster $FSI_DR_CLUSTER_ID --environment $FSI_DR_ENV_ID
  ```
  If East topics are truncated but not yet mirroring, data may be lost. Consult this runbook's "Failback Recovery" section.
- **Manual fallback:** `./scripts/mirror-failback.sh` (Step 1: truncate-and-restore)
- **Confirmation gate:** Operator must confirm before this step proceeds. Automated execution with `--force` bypasses the prompt.

#### Step 4: Wait for Sync

- **What happens:** Polls mirror lag on East cluster (which is now mirroring from West) until all topics reach near-zero lag. Default timeout is 300 seconds (5 minutes). Configurable via `FSI_DR_SYNC_TIMEOUT`.
- **Success criteria:** All mirrored topics show lag below their tier's warn threshold.
- **Abort criteria:** Sync timeout exceeded. Data is still syncing. Check `fsi-dr.sh status` and retry when lag is acceptable.
- **Rollback:** Data is syncing from West to East but not yet complete. Safe to wait longer. Run `fsi-dr.sh status` to monitor progress.
- **Note:** Sync time depends on data volume. For large topics (TBs of data), increase `FSI_DR_SYNC_TIMEOUT` or monitor manually.

#### Step 5: Reverse and Start

- **What happens:** Reverses the mirror direction: East becomes read-write (primary), West becomes mirrors again. After this step, East is the active production cluster.
- **Success criteria:** East topics are R/W (no longer mirroring). West topics become mirrors of East.
- **Abort criteria:** Reverse-and-start fails. East has data but is still mirroring. Cannot serve traffic yet.
- **Rollback:** Retry reverse-and-start manually:
  ```bash
  confluent kafka mirror reverse-and-start <topics> --link $FSI_CLUSTER_LINK_NAME --cluster $FSI_DR_CLUSTER_ID --environment $FSI_DR_ENV_ID
  ```
- **Manual fallback:** `./scripts/mirror-failback.sh` (Step 2: reverse-and-start)
- **Confirmation gate:** Second operator confirmation required. Automated execution with `--force` bypasses the prompt.

#### Step 6: Flip Consul to East

- **What happens:** Updates Consul KV key `fsi/kafka/active-region` from `west` to `east`. This atomically redirects all Consul-resolved endpoints back to the East region.
- **Success criteria:** `consul kv get fsi/kafka/active-region` returns `east`.
- **Abort criteria:** Consul unreachable. East is ready but applications still resolve to West.
- **Rollback:** Manual Consul flip: `consul kv put fsi/kafka/active-region east`
- **Manual fallback:** `./scripts/consul-flip-region.sh east`

#### Step 7: Resume Connectors

- **What happens:** Resumes only connectors that were RUNNING before Step 2 (from the state file snapshot).
- **Success criteria:** Previously-RUNNING connectors report `state=RUNNING`.
- **Abort criteria:** Connector fails to resume. Failback is functionally complete at this point.
- **Rollback:** Resume connectors manually. Failback is complete; connector issues are operational.

#### Step 8: Final Validation

- **What happens:** Verifies East cluster is accessible, Consul points to east, and connectors are running.
- **Success criteria:** All validation checks pass.
- **Abort criteria:** N/A. Failback is complete. Investigation-only.
- **Rollback:** N/A. Address specific validation failures individually.

### Post-Failback Checklist

After failback completes:

- [ ] Verify applications are producing to East cluster
- [ ] Check consumer lag on East cluster
- [ ] Verify Schema Registry is accessible on East
- [ ] Confirm West cluster is mirroring from East (check mirror status)
- [ ] Verify Connect connectors are processing records
- [ ] Monitor East cluster for any resource warnings
- [ ] Update incident ticket with failback completion time
- [ ] Schedule post-incident review

## Troubleshooting

### Common Issues

#### Mirror lag increasing

- **Check:** `fsi-dr.sh status`
- **Cause:** Network between regions, producer throughput spike, cluster resource constraints
- **Action:** Monitor trend for 5-10 minutes. If critical/compliance topics exceeding RPO threshold, escalate to cloud ops. If increasing steadily, check cluster metrics for disk/CPU/network bottlenecks.

#### Connect REST API unreachable

- **Check:** `curl -s ${FSI_CONNECT_URL}/connectors`
- **Cause:** Connect worker down, network issue, or Connect cluster overloaded
- **Action:** Failover/failback can proceed without Connect (Steps 1/2 pause and Steps 5/7 resume can be skipped). Resume connectors manually after DR operation completes:
  ```bash
  curl -s -X PUT ${FSI_CONNECT_URL}/connectors/<name>/resume
  ```

#### Consul KV updated but DNS stale

- **Check:** Compare `dig +short kafka.fsi.internal` with `consul kv get fsi/kafka/active-region`
- **Cause:** DNS caching, Consul DNS TTL, stale Consul agent
- **Action:** Wait for TTL expiry (default ~30 seconds) or restart local DNS cache. Verify Consul agent health: `consul members`. Check Consul DNS configuration: `consul info | grep dns`.

#### Partial mirror promotion

- **Check:** `confluent kafka mirror list --link ${FSI_CLUSTER_LINK_NAME} --cluster ${FSI_DR_DR_CLUSTER_ID} --environment ${FSI_DR_DR_ENV_ID}`
- **Cause:** CLI timeout, cluster overloaded, network partition
- **Action:** Identify remaining active mirrors and promote manually:
  ```bash
  confluent kafka mirror failover <remaining-topics> --link $FSI_CLUSTER_LINK_NAME --cluster $FSI_DR_DR_CLUSTER_ID --environment $FSI_DR_DR_ENV_ID
  ```

#### Truncate-and-restore partially failed (failback)

- **Check:** `confluent kafka mirror list --link ${FSI_CLUSTER_LINK_NAME} --cluster ${FSI_DR_CLUSTER_ID} --environment ${FSI_DR_ENV_ID}`
- **Cause:** CLI timeout, East cluster instability, network issue during destructive operation
- **Action:** **CRITICAL** -- Some East topics may be truncated while others are not.
  1. Identify which topics were successfully restored as mirrors (status=ACTIVE)
  2. Identify which topics were truncated but not restored (missing from mirror list)
  3. For truncated-but-not-restored topics, retry: `confluent kafka mirror truncate-and-restore <topic-names> --link $FSI_CLUSTER_LINK_NAME --cluster $FSI_DR_CLUSTER_ID --environment $FSI_DR_ENV_ID`
  4. If retry fails, West still has the data. Applications remain on West until failback completes.

#### State file corruption

- **Check:** `cat /tmp/fsi-dr-state.json | jq .`
- **Cause:** Concurrent DR operations, disk full, process killed mid-write
- **Action:** The state file tracks progress but is not required for manual completion. Delete the state file and complete remaining steps manually:
  ```bash
  rm -f /tmp/fsi-dr-state.json
  ```
  Use `fsi-dr.sh status` or Confluent CLI to determine which steps have completed.

#### Failover/failback hangs at confirmation prompt

- **Cause:** Running in interactive mode without `--force` flag
- **Action:** Type `yes` and press Enter, or kill the process and restart with `--force`:
  ```bash
  fsi-dr.sh failover --force
  ```

### Escalation Path

If automated DR fails and manual recovery is needed:

1. **On-call engineer:** Attempt manual steps documented in this runbook
2. **Platform team lead:** If manual steps fail or situation is unclear
3. **Confluent support:** If cluster link or mirror operations return unexpected errors
4. **Cloud provider support:** If underlying infrastructure (network, compute) is the root cause

## Failback Recovery

This section covers recovery from a failed or partial failback operation.

### Scenario: Failback failed at Step 3 (truncate-and-restore)

The most critical failure scenario. East topics may be partially truncated.

1. **Do not panic.** West still has all data and is still serving traffic (Consul still points to West).
2. Check East mirror status:
   ```bash
   confluent kafka mirror list --link $FSI_CLUSTER_LINK_NAME --cluster $FSI_DR_CLUSTER_ID --environment $FSI_DR_ENV_ID
   ```
3. If some topics are mirroring and others are not, retry truncate-and-restore for the remaining topics.
4. If East is in an inconsistent state, wait for Confluent support before proceeding.
5. Applications remain on West. There is no immediate business impact.

### Scenario: Failback failed at Step 5 (reverse-and-start)

East has synced data but is still in mirror mode.

1. Retry reverse-and-start:
   ```bash
   confluent kafka mirror reverse-and-start <topics> --link $FSI_CLUSTER_LINK_NAME --cluster $FSI_DR_CLUSTER_ID --environment $FSI_DR_ENV_ID
   ```
2. If retry succeeds, continue with Steps 6-8 manually (Consul flip, resume connectors, validate).
3. If retry fails, East has the data but cannot serve traffic. Applications remain on West.

### Scenario: Consul flip failed

East is ready (R/W) but applications still resolve to West.

1. Manual Consul flip: `consul kv put fsi/kafka/active-region east`
2. Verify: `consul kv get fsi/kafka/active-region`
3. If Consul is completely down, update application configurations directly to point to East endpoints.

## Emergency Contacts

| Role | Contact | Scope |
|------|---------|-------|
| On-call engineer | [Team rotation] | First responder for DR events |
| Platform team lead | [Name/contact] | Escalation for complex DR scenarios |
| Confluent support | [Support portal/ticket] | Cluster link, mirror, and platform issues |
| Cloud provider support | [AWS/Azure/GCP support] | Infrastructure issues |

*Update this section with your organization's specific contacts.*

## Revision History

| Date | Change | Author |
|------|--------|--------|
| 2026-03-24 | Initial runbook creation with failover, failback, troubleshooting | FSI C4E |
