# Linux_One (Deprecated)

> **This directory is deprecated.** All content has been absorbed into the main platform.

## Where Things Moved

| Original | New Location |
|----------|-------------|
| `ansible-mtls/roles/kafka_ca/` | `ansible/roles/cp_mtls/tasks/ca.yml` |
| `ansible-mtls/roles/kafka_broker_cert/` | `ansible/roles/cp_mtls/tasks/broker_cert.yml` |
| `ansible-mtls/roles/kafka_client_cert/` | `ansible/roles/cp_mtls/tasks/client_cert.yml` |
| `ansible-mtls/roles/kafka_truststore/` | `ansible/roles/cp_mtls/tasks/truststore.yml` |
| `ansible-mtls/roles/kafka_ssl_config/` | `ansible/roles/cp_mtls/tasks/ssl_config.yml` |
| `ansible-mtls/playbooks/` | `scenarios/cp-rhel-linuxone/playbooks/` |
| `mTLS-CP-LinuxOne.docx` | `docs/linuxone-mtls-guide.md` + `docs/linuxone-troubleshooting.md` |

## Key Changes

- 5 standalone roles consolidated into single `cp_mtls` composite role
- Fidelity branding generalized (`Fidelity` -> configurable `cp_mtls_ca_org`)
- `community.crypto >= 2.15.0` added to `ansible/requirements.yml`
- PKCS#11/CEX HSM support added as optional mode (`cp_mtls_keystore_backend: pkcs11`)
- Molecule tests and CI integration added
- s390x-specific FIPS validation added to `scripts/validate-fips.sh`

## LinuxONE Deployment

See:
- `scenarios/cp-rhel-linuxone/` -- CP on RHEL on LinuxONE scenario
- `scenarios/cfk-openshift-linuxone/` -- CFK on OpenShift on LinuxONE scenario
- `docs/linuxone-mtls-guide.md` -- mTLS setup guide
- `docs/linuxone-troubleshooting.md` -- Troubleshooting guide
- `docs/linuxone-fips-guide.md` -- FIPS validation guide
- `docs/linuxone-cex-guide.md` -- CEX/PKCS#11 HSM guide
- `docs/adr/009-linuxone-deployment-guidance.md` -- Architecture Decision Record
