# CFK on OpenShift on LinuxONE (s390x)

Confluent for Kubernetes on OpenShift running on IBM LinuxONE (s390x architecture).

## Prerequisites

- OpenShift Container Platform 4.x on s390x (or mixed-arch cluster with s390x workers)
- CFK operator installed (Helm or OLM)
- Multi-arch container images (Confluent provides s390x variants)

## LinuxONE-Specific Notes

- **FIPS**: On s390x, FIPS must be enabled at OCP install time. Post-install enablement is NOT supported. See `docs/linuxone-fips-guide.md`.
- **Node affinity**: The Helm values include `nodeAffinity` rules targeting `kubernetes.io/arch: s390x` for mixed-arch clusters. Remove if the cluster is s390x-only.
- **Sidecar images**: Monitoring agents and log shippers may run x86 under QEMU emulation with ~10x throughput penalty. Verify s390x-native builds are available.
- **Multi-arch images**: Confluent multi-arch images include s390x variants. Set `pullPolicy: IfNotPresent` to avoid unnecessary pulls.

## Quick Start

```bash
# 1. Install CFK operator
helm repo add confluentinc https://packages.confluent.io/helm
helm install confluent-operator confluentinc/confluent-for-kubernetes -n confluent

# 2. Apply s390x-specific values
helm upgrade confluent-operator confluentinc/confluent-for-kubernetes \
  -n confluent -f values/kafka.yaml

# 3. Verify pods running on s390x nodes
oc get pods -n confluent -o wide
```

## Troubleshooting

See `docs/linuxone-troubleshooting.md` for s390x-specific debugging guidance.
