# FSI Flink SQL-runner — s390x Custom Image

The `Dockerfile` in this directory defines the custom `cp-flink` image with the
Kafka connector, Avro-Confluent format connector, and the GoodLabs `fsi-sql-runner.jar`
pre-installed. This image is **shipped as a Dockerfile** — it is not built by
this accelerator. You must build and push it to your registry before applying
the FlinkApplication CRs (see KNOWN-GAPS.md G-12).

---

## JAR version matrix

| Component | Version | Notes |
|-----------|---------|-------|
| `cp-flink` base image | `confluentinc/cp-flink:1.20.0-cp1` | CP 8.2.0; verify `cp1` tag at hub.docker.com/r/confluentinc/cp-flink |
| `flink-sql-connector-kafka` | `3.2.0-1.20` | Matches Flink 1.20.x + Kafka 3.6/3.7 protocol |
| `flink-sql-avro-confluent-registry` | `1.20.0` | Required for `avro-confluent` format connector |
| `fsi-sql-runner.jar` | GoodLabs build | Reads `--sql-file` and submits to Flink SQL gateway |

Verify all JAR versions against the Confluent CP 8.2.0 compatibility matrix before
building. Patch `ENV` variables in the Dockerfile if versions differ.

---

## Build and push

**Prerequisite:** Docker Desktop or Docker Engine with `buildx` and s390x QEMU
emulation (or a native s390x build host). The image must run on s390x (LinuxONE)
workers — do not push an x86-only image.

```bash
# 1. Build the fsi-sql-runner.jar (Java 17 Maven project)
#    The source for SqlRunner is not included in this accelerator — provide your
#    implementation of com.goodlabs.fsi.flink.SqlRunner that reads --sql-file
#    and submits via the Flink SQL gateway REST API.
mvn -f fsi-sql-runner/pom.xml package -DskipTests
cp fsi-sql-runner/target/fsi-sql-runner-*.jar sql-runner/fsi-sql-runner.jar

# 2. Build the image for linux/s390x
#    Replace <YOUR_REGISTRY> with your OCP internal registry or external registry.
docker buildx build \
  --platform linux/s390x \
  --build-arg FLINK_VERSION=1.20.0 \
  --build-arg KAFKA_CONNECTOR_VERSION=3.2.0-1.20 \
  --build-arg AVRO_CONFLUENT_VERSION=1.20.0 \
  -f sql-runner/Dockerfile \
  -t <YOUR_REGISTRY>/fsi-flink-sql-runner:1.20.0-cp1 \
  sql-runner/ \
  --push

# 3. Update FlinkApplication CRs and FlinkEnvironment with the pushed image reference
#    Replace <PLACEHOLDER_CP_FLINK_SQL_RUNNER_IMAGE> in:
#      layers/05-flink/flink-environment.yaml
#      layers/05-flink/applications/txn-volume-tumbling-window.yaml
#      layers/05-flink/applications/account-transaction-enrichment.yaml
```

### Air-gapped environments

If the build environment cannot reach Maven Central, download the JARs before building:

```bash
# Download JARs to sql-runner/lib/
mkdir -p sql-runner/lib
wget -P sql-runner/lib/ \
  https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/3.2.0-1.20/flink-sql-connector-kafka-3.2.0-1.20.jar
wget -P sql-runner/lib/ \
  https://repo1.maven.org/maven2/org/apache/flink/flink-sql-avro-confluent-registry/1.20.0/flink-sql-avro-confluent-registry-1.20.0.jar
```

Then replace the `RUN wget` lines in the Dockerfile with `COPY lib/filename.jar /opt/flink/lib/`.

---

## OCP internal registry push

```bash
# Log in to the OCP internal registry
oc registry login

# Tag and push
docker tag <YOUR_REGISTRY>/fsi-flink-sql-runner:1.20.0-cp1 \
  $(oc registry info)/confluent/fsi-flink-sql-runner:1.20.0-cp1
docker push $(oc registry info)/confluent/fsi-flink-sql-runner:1.20.0-cp1
```

---

## Cross-reference

- KNOWN-GAPS.md G-12: custom s390x SQL-runner image required before FlinkApplications can start
- FlinkApplication CRs: `layers/05-flink/applications/*.yaml`
- FlinkEnvironment default image: `layers/05-flink/flink-environment.yaml`
