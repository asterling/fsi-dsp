# =============================================================================
# FSI Kafka Platform -- Flink SQL Local Dev Image
# =============================================================================
# Custom Flink image with Kafka and Avro-Confluent connector JARs pre-installed.
# Based on Apache Flink 1.20 (last stable 1.x release).
#
# Connector versions:
#   - flink-sql-connector-kafka: 3.2.0-1.20
#     Chosen for Kafka 3.6/7.6 protocol compatibility. The 3.4.0-1.20 version
#     targets a newer Kafka client that may introduce protocol negotiation issues
#     with Confluent Platform 7.6.0 (which bundles Kafka 3.6.x). Using 3.2.0-1.20
#     ensures the embedded Kafka client aligns with our broker version.
#   - flink-sql-avro-confluent: 1.20.0 (Avro + Confluent Schema Registry format)
# =============================================================================
FROM flink:1.20-java17

# Download Kafka SQL connector and Avro-Confluent format JARs from Maven Central
# These enable: CREATE TABLE ... WITH ('connector' = 'kafka', 'format' = 'avro-confluent')
RUN wget -q -P /opt/flink/lib/ \
    https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/3.2.0-1.20/flink-sql-connector-kafka-3.2.0-1.20.jar && \
    wget -q -P /opt/flink/lib/ \
    https://repo1.maven.org/maven2/org/apache/flink/flink-sql-avro-confluent/1.20.0/flink-sql-avro-confluent-1.20.0.jar

# Verify JARs were downloaded
RUN ls -la /opt/flink/lib/flink-sql-connector-kafka-*.jar /opt/flink/lib/flink-sql-avro-confluent-*.jar
