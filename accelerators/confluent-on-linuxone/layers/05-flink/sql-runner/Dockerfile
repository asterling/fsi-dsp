# =============================================================================
# sql-runner/Dockerfile — Custom s390x cp-flink SQL-runner image
# =============================================================================
# Re-bases scenarios/cfk-openshift/flink/flink-docker/Dockerfile onto the
# Confluent cp-flink 1.20.x s390x image and layers in:
#   - fsi-sql-runner.jar  — GoodLabs SQL runner that accepts --sql-file
#   - flink-sql-connector-kafka  — Kafka source/sink SQL connector
#   - flink-sql-avro-confluent-registry  — Avro + Schema Registry format
#
# THIS IMAGE IS SHIPPED AS A DOCKERFILE — NOT BUILT HERE.
# See sql-runner/README.md for the docker buildx --platform linux/s390x
# build instructions and the JAR version matrix.
# The image reference in FlinkApplication CRs is <PLACEHOLDER_CP_FLINK_SQL_RUNNER_IMAGE>.
#
# JAR version matrix (matched to Apache Flink 1.20.x):
#   flink-sql-connector-kafka:     3.2.0-1.20
#   flink-sql-avro-confluent-registry: 1.20.0
#   cp-flink base image:           confluentinc/cp-flink:1.20.0-cp1 (CP 8.2.0)
#
# Air-gapped environments: replace wget with COPY after downloading JARs locally.
# =============================================================================

# cp-flink is the Confluent-packaged Flink image with s390x multi-arch support.
# Tag format: {flink-version}-cp{cp-incremental} — verify the exact cp1 tag for
# CP 8.2.0 at hub.docker.com/r/confluentinc/cp-flink before building.
FROM confluentinc/cp-flink:1.20.0-cp1

# ARG (not ENV) so values can be overridden at build time via
# `docker buildx build --build-arg KAFKA_CONNECTOR_VERSION=...`.
# These versions are only used in the wget URLs below — no runtime visibility
# is needed, so plain ARG suffices.
ARG FLINK_VERSION=1.20.0
# Kafka connector version: matches Flink 1.20.x and Kafka 3.6/3.7 protocol
ARG KAFKA_CONNECTOR_VERSION=3.2.0-1.20
# Avro-Confluent format connector version: matches Flink 1.20.x
ARG AVRO_CONFLUENT_VERSION=1.20.0

# Download Kafka SQL connector JAR into Flink's lib/ directory.
# This adds Kafka source/sink support to Flink SQL TABLE API.
RUN wget -P /opt/flink/lib/ \
    https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/${KAFKA_CONNECTOR_VERSION}/flink-sql-connector-kafka-${KAFKA_CONNECTOR_VERSION}.jar

# Download Avro-Confluent Registry format connector.
# Required for 'value.format'='avro-confluent' WITH clause — without this JAR,
# Flink SQL cannot deserialize Avro messages from Schema Registry-registered topics.
RUN wget -P /opt/flink/lib/ \
    https://repo1.maven.org/maven2/org/apache/flink/flink-sql-avro-confluent-registry/${AVRO_CONFLUENT_VERSION}/flink-sql-avro-confluent-registry-${AVRO_CONFLUENT_VERSION}.jar

# Copy the GoodLabs FSI SQL runner JAR.
# Build from: accelerators/confluent-on-linuxone/layers/05-flink/sql-runner/
# The runner reads a --sql-file argument and submits DDL + DML to the Flink SQL gateway.
COPY fsi-sql-runner.jar /opt/flink/usrlib/fsi-sql-runner.jar

# Maintain non-root user for OCP security context (Confluent image default: flink uid=999)
USER flink
