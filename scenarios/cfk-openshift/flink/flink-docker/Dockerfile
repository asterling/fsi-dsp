# =============================================================================
# Custom Flink Image with Avro-Confluent and Kafka Connector JARs
# =============================================================================
# Required because the base Flink image does not include avro-confluent format
# (Pitfall 7 from research). All FlinkDeployment CRDs in this scenario use
# this custom image.
#
# Build:
#   docker build -t fsi-flink:1.20 scenarios/cfk-openshift/flink/flink-docker/
#
# For air-gapped environments, download JARs locally and COPY instead of wget:
#   COPY flink-sql-connector-kafka-3.2.0-1.20.jar /opt/flink/lib/
#   COPY flink-sql-avro-confluent-registry-1.20.0.jar /opt/flink/lib/
# =============================================================================

FROM flink:1.20-java17

ENV FLINK_VERSION=1.20.0
ENV KAFKA_CONNECTOR_VERSION=3.2.0-1.20
ENV AVRO_CONFLUENT_VERSION=1.20.0

# Download Kafka SQL connector (matches Phase 7 decision for Kafka 3.6/7.6 protocol compatibility)
RUN wget -P /opt/flink/lib/ \
    https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/${KAFKA_CONNECTOR_VERSION}/flink-sql-connector-kafka-${KAFKA_CONNECTOR_VERSION}.jar

# Download Avro-Confluent Registry format connector for Schema Registry integration
RUN wget -P /opt/flink/lib/ \
    https://repo1.maven.org/maven2/org/apache/flink/flink-sql-avro-confluent-registry/${AVRO_CONFLUENT_VERSION}/flink-sql-avro-confluent-registry-${AVRO_CONFLUENT_VERSION}.jar

# Maintain non-root user for security
USER flink
