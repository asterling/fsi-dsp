# Attribution

## Upstream Reference — Matt Mondics (IBM)

The `base/` directory of this accelerator is structured around the public reference
runbook authored by **Matt Mondics** of IBM, published 2026-05-20:

- **Repository:** `https://github.com/mmondics/Confluent-LinuxONE-Mirror`
- **Article:** "Deploying Confluent Platform on IBM LinuxONE with OpenShift and CFK" (2026-05-20)

Mondics's runbook demonstrates Confluent Platform 8.2.0 on IBM LinuxONE via the
CFK operator on Red Hat OpenShift, including Cluster Linking for x86→LinuxONE
migration. It is the foundational generic demo that this accelerator extends with
FSI hardening controls.

## License status and fetch-by-SHA rationale

The upstream repository (`mmondics/Confluent-LinuxONE-Mirror`) **does not contain a
LICENSE file** as of the pinned SHA. Without an explicit open-source license, the
default "all rights reserved" applies — GoodLabs has no redistribution right.

For this reason, this accelerator does **not vendor or copy** Mondics's YAML files.
Instead:
- `base/fetch-upstream.sh` clones the repository at a pinned commit SHA at activation time.
- The fetched `base/upstream/` directory is **gitignored and never committed** to this repo.
- `ATTRIBUTION.md` (this file) and `base/UPSTREAM.md` document the upstream source.

If Mondics subsequently publishes a permissive license (MIT, Apache-2.0), the
appropriate path is to vendor the manifests and remove the fetch-at-activation
dependency. See `KNOWN-GAPS.md` for the network-access implication of the current approach.

## GoodLabs additions

Everything outside of `base/upstream/` — the four FSI hardening layers
(`layers/01-rbac/`, `layers/02-tls/`, `layers/03-schema-governance/`, `layers/04-audit/`),
the Flox environment, RUNBOOK.md, MIGRATION.md, KNOWN-GAPS.md, and this DESIGN.md —
is original GoodLabs work and is covered by this repository's license.

## Acknowledgements

Thanks to Matt Mondics and IBM for making a practical, working reference implementation
publicly available. The FSI hardening layers in this accelerator are designed to be
read alongside his upstream runbook, not as a replacement for it.
