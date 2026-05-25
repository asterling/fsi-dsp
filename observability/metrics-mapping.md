# Cross-Provider Metrics Mapping

Maps Confluent Cloud Metrics API metric names to equivalent queries in each observability provider. Use this document to verify cross-provider dashboard parity.

---

## Cluster Health Metrics

| Metric Name (CC Metrics API) | Description | Grafana (PromQL) | Dynatrace (DQL) | Datadog (query) | Splunk (SPL) | New Relic (NRQL) | Instana (query) |
|------------------------------|-------------|------------------|-----------------|-----------------|--------------|------------------|-----------------|
| `io.confluent.kafka.server/active_connection_count` | Active broker connections | `confluent_kafka_server_active_connection_count{kafka_id="$CLUSTER_ID"}` | `fetch dt.entity.custom_device \| fields active_connection_count \| filter kafka_id == "$CLUSTER_ID"` | `confluent_kafka_server.active_connection_count{kafka_id:$CLUSTER_ID}` | `index=kafka sourcetype=confluent_metrics metric_name="active_connection_count" kafka_id="$CLUSTER_ID"` | `SELECT average(active_connection_count) FROM ConfluentCloudMetric WHERE kafka_id = '$CLUSTER_ID'` | `metrics("active_connection_count").filter("kafka_id", "$CLUSTER_ID")` |
| `io.confluent.kafka.server/request_count` | Request rate (produce + fetch + metadata) | `rate(confluent_kafka_server_request_count{kafka_id="$CLUSTER_ID"}[5m])` | `fetch dt.entity.custom_device \| fields request_count \| filter kafka_id == "$CLUSTER_ID" \| rate(5m)` | `rate:confluent_kafka_server.request_count{kafka_id:$CLUSTER_ID}.as_rate()` | `index=kafka sourcetype=confluent_metrics metric_name="request_count" kafka_id="$CLUSTER_ID" \| timechart span=5m rate(request_count)` | `SELECT rate(sum(request_count), 5 MINUTES) FROM ConfluentCloudMetric WHERE kafka_id = '$CLUSTER_ID'` | `metrics("request_count").filter("kafka_id", "$CLUSTER_ID").rate(300)` |
| `io.confluent.kafka.server/partition_count` | Total partitions across all topics | `confluent_kafka_server_partition_count{kafka_id="$CLUSTER_ID"}` | `fetch dt.entity.custom_device \| fields partition_count \| filter kafka_id == "$CLUSTER_ID"` | `confluent_kafka_server.partition_count{kafka_id:$CLUSTER_ID}` | `index=kafka sourcetype=confluent_metrics metric_name="partition_count" kafka_id="$CLUSTER_ID" \| stats latest(partition_count) by broker_id` | `SELECT latest(partition_count) FROM ConfluentCloudMetric WHERE kafka_id = '$CLUSTER_ID' FACET broker_id` | `metrics("partition_count").filter("kafka_id", "$CLUSTER_ID").groupBy("broker_id")` |
| `io.confluent.kafka.server/successful_authentication_count` | Successful authentication rate | `rate(confluent_kafka_server_successful_authentication_count{kafka_id="$CLUSTER_ID"}[5m])` | `fetch dt.entity.custom_device \| fields successful_authentication_count \| filter kafka_id == "$CLUSTER_ID" \| rate(5m)` | `rate:confluent_kafka_server.successful_authentication_count{kafka_id:$CLUSTER_ID}.as_rate()` | `index=kafka sourcetype=confluent_metrics metric_name="successful_authentication_count" kafka_id="$CLUSTER_ID" \| timechart span=5m rate(successful_authentication_count)` | `SELECT rate(sum(successful_authentication_count), 5 MINUTES) FROM ConfluentCloudMetric WHERE kafka_id = '$CLUSTER_ID'` | `metrics("successful_authentication_count").filter("kafka_id", "$CLUSTER_ID").rate(300)` |
| JMX: `kafka.server:type=ReplicaManager,name=UnderReplicatedPartitions` | Under-replicated partitions (0 = healthy) | `kafka_server_replica_manager_under_replicated_partitions{kafka_id="$CLUSTER_ID"}` | `fetch dt.entity.custom_device \| fields under_replicated_partitions \| filter kafka_id == "$CLUSTER_ID"` | `kafka.server.replica_manager.under_replicated_partitions{kafka_id:$CLUSTER_ID}` | `index=kafka sourcetype=jmx metric_name="under_replicated_partitions" kafka_id="$CLUSTER_ID"` | `SELECT latest(under_replicated_partitions) FROM KafkaBrokerSample WHERE kafka_id = '$CLUSTER_ID'` | `metrics("under_replicated_partitions").filter("kafka_id", "$CLUSTER_ID")` |

---

## Consumer Lag Metrics

| Metric Name (CC Metrics API) | Description | Grafana (PromQL) | Dynatrace (DQL) | Datadog (query) | Splunk (SPL) | New Relic (NRQL) | Instana (query) |
|------------------------------|-------------|------------------|-----------------|-----------------|--------------|------------------|-----------------|
| `io.confluent.kafka.server/consumer_lag_offsets` | Consumer group lag in records | `confluent_kafka_server_consumer_lag_offsets{kafka_id="$CLUSTER_ID", topic=~"$DOMAIN_PREFIX.*", consumer_group_id=~"$CONSUMER_GROUP"}` | `fetch dt.entity.custom_device \| fields consumer_lag_offsets, topic, consumer_group_id \| filter kafka_id == "$CLUSTER_ID" AND topic LIKE "$DOMAIN_PREFIX.*"` | `confluent_kafka_server.consumer_lag_offsets{kafka_id:$CLUSTER_ID, topic:$DOMAIN_PREFIX.*}` | `index=kafka sourcetype=confluent_metrics metric_name="consumer_lag_offsets" kafka_id="$CLUSTER_ID" topic="$DOMAIN_PREFIX.*" \| stats sum(consumer_lag_offsets) by consumer_group_id, topic` | `SELECT sum(consumer_lag_offsets) FROM ConfluentCloudMetric WHERE kafka_id = '$CLUSTER_ID' AND topic LIKE '$DOMAIN_PREFIX%' FACET consumer_group_id, topic` | `metrics("consumer_lag_offsets").filter("kafka_id", "$CLUSTER_ID").filter("topic", "$DOMAIN_PREFIX.*").groupBy("consumer_group_id", "topic")` |
| Consumer group state | Consumer group state (active/rebalancing/empty) | `kafka_consumergroup_state{kafka_id="$CLUSTER_ID", consumer_group=~"$CONSUMER_GROUP"}` | `fetch dt.entity.custom_device \| fields consumer_group_state \| filter kafka_id == "$CLUSTER_ID"` | `kafka.consumer_group.state{kafka_id:$CLUSTER_ID}` | `index=kafka sourcetype=confluent_metrics metric_name="consumer_group_state" kafka_id="$CLUSTER_ID"` | `SELECT latest(state) FROM KafkaConsumerGroupSample WHERE kafka_id = '$CLUSTER_ID' FACET consumer_group` | `metrics("consumer_group_state").filter("kafka_id", "$CLUSTER_ID").groupBy("consumer_group")` |

---

## Connect Status Metrics

| Metric Name | Description | Grafana (PromQL) | Dynatrace (DQL) | Datadog (query) | Splunk (SPL) | New Relic (NRQL) | Instana (query) |
|-------------|-------------|------------------|-----------------|-----------------|--------------|------------------|-----------------|
| Connect REST API `/connectors` | List of all connectors | HTTP JSON datasource: `GET $CONNECT_REST_URL/connectors` | HTTP check: `GET $CONNECT_REST_URL/connectors` | HTTP check: `GET $CONNECT_REST_URL/connectors` | `\| inputlookup connect_connectors.csv` or scripted input polling `$CONNECT_REST_URL/connectors` | Flex integration: `GET $CONNECT_REST_URL/connectors` | HTTP endpoint: `GET $CONNECT_REST_URL/connectors` |
| Connect REST API `/connectors/{name}/status` | Connector state: RUNNING, PAUSED, FAILED, UNASSIGNED; task state; worker ID | HTTP JSON datasource: `GET $CONNECT_REST_URL/connectors/{name}/status` | HTTP check: `GET $CONNECT_REST_URL/connectors/{name}/status` | HTTP check: `GET $CONNECT_REST_URL/connectors/{name}/status` | Scripted input: `$CONNECT_REST_URL/connectors/{name}/status` | Flex integration: `GET $CONNECT_REST_URL/connectors/{name}/status` | HTTP endpoint: `GET $CONNECT_REST_URL/connectors/{name}/status` |

---

## DR Readiness Metrics

| Metric Name (CC Metrics API) | Description | Grafana (PromQL) | Dynatrace (DQL) | Datadog (query) | Splunk (SPL) | New Relic (NRQL) | Instana (query) |
|------------------------------|-------------|------------------|-----------------|-----------------|--------------|------------------|-----------------|
| `io.confluent.kafka.server/cluster_link_mirror_topic_offset_lag` | Mirror topic offset lag (records) | `confluent_kafka_server_cluster_link_mirror_topic_offset_lag{kafka_id="$CLUSTER_ID", topic=~"$DOMAIN_PREFIX.*"}` | `fetch dt.entity.custom_device \| fields cluster_link_mirror_topic_offset_lag, topic \| filter kafka_id == "$CLUSTER_ID"` | `confluent_kafka_server.cluster_link_mirror_topic_offset_lag{kafka_id:$CLUSTER_ID, topic:$DOMAIN_PREFIX.*}` | `index=kafka sourcetype=confluent_metrics metric_name="cluster_link_mirror_topic_offset_lag" kafka_id="$CLUSTER_ID" topic="$DOMAIN_PREFIX.*"` | `SELECT latest(cluster_link_mirror_topic_offset_lag) FROM ConfluentCloudMetric WHERE kafka_id = '$CLUSTER_ID' AND topic LIKE '$DOMAIN_PREFIX%' FACET topic` | `metrics("cluster_link_mirror_topic_offset_lag").filter("kafka_id", "$CLUSTER_ID").groupBy("topic")` |
| Mirror lag in seconds (derived) | Derived from offset lag and throughput rate | `confluent_kafka_server_cluster_link_mirror_topic_offset_lag{kafka_id="$CLUSTER_ID"} / on(topic) rate(confluent_kafka_server_received_records{kafka_id="$CLUSTER_ID"}[5m])` | Calculated metric: `offset_lag / throughput_rate` | `confluent_kafka_server.cluster_link_mirror_topic_offset_lag / confluent_kafka_server.received_records.as_rate()` | `\| eval mirror_lag_seconds = offset_lag / throughput_rate` | `SELECT latest(cluster_link_mirror_topic_offset_lag) / rate(sum(received_records), 5 MINUTES) FROM ConfluentCloudMetric FACET topic` | `expression("offset_lag / throughput_rate")` |
| Cluster link status | Cluster link active/inactive state | `confluent_kafka_server_cluster_link_state{kafka_id="$CLUSTER_ID"}` | `fetch dt.entity.custom_device \| fields cluster_link_state \| filter kafka_id == "$CLUSTER_ID"` | `confluent_kafka_server.cluster_link_state{kafka_id:$CLUSTER_ID}` | `index=kafka sourcetype=confluent_metrics metric_name="cluster_link_state" kafka_id="$CLUSTER_ID"` | `SELECT latest(cluster_link_state) FROM ConfluentCloudMetric WHERE kafka_id = '$CLUSTER_ID'` | `metrics("cluster_link_state").filter("kafka_id", "$CLUSTER_ID")` |

---

## Flink Jobs Metrics

Confluent Cloud Flink metrics are exposed via the CC Metrics API under the `io.confluent.flink/*` namespace. These metrics are available when Flink compute pools and SQL statements are running in a CC environment. In PromQL (Grafana), dots and slashes in metric names are replaced with underscores (e.g., `io.confluent.flink/num_records_out` becomes `io_confluent_flink_num_records_out`).

> **Note:** CC Metrics API does not expose a checkpoint duration metric. Apache Flink's `checkpointAlignmentTime` JMX metric is not available in CC Flink. Use `pending_records` as a backpressure proxy and `num_records_out` rate for throughput monitoring -- these provide equivalent operational insight for managed Flink.

| Metric Name (CC Metrics API) | Description | Grafana (PromQL) | Dynatrace (DQL) | Datadog (query) | Splunk (SPL) | New Relic (NRQL) | Instana (query) |
|------------------------------|-------------|------------------|-----------------|-----------------|--------------|------------------|-----------------|
| `io.confluent.flink/num_records_in` | Records consumed by Flink statement | `io_confluent_flink_num_records_in{resource_type="flink_statement"}` | `timeseries avg(io.confluent.flink.num_records_in), by:{statement_name}` | `avg:confluent_cloud.flink.num_records_in{*} by {statement_name}` | `index=confluent_cloud source="cc_metrics_api" metric_name="io.confluent.flink/num_records_in" \| timechart avg(metric_value) by statement_name` | `SELECT rate(sum(io.confluent.flink.num_records_in), 1 minute) FROM ConfluentCloudFlinkSample FACET statement_name TIMESERIES` | `metrics("io.confluent.flink/num_records_in").rollup("rate").groupBy("statement_name")` |
| `io.confluent.flink/num_records_out` | Records produced by Flink statement | `io_confluent_flink_num_records_out{resource_type="flink_statement"}` | `timeseries avg(io.confluent.flink.num_records_out), by:{statement_name}` | `avg:confluent_cloud.flink.num_records_out{*} by {statement_name}` | `index=confluent_cloud source="cc_metrics_api" metric_name="io.confluent.flink/num_records_out" \| timechart avg(metric_value) by statement_name` | `SELECT rate(sum(io.confluent.flink.num_records_out), 1 minute) FROM ConfluentCloudFlinkSample FACET statement_name TIMESERIES` | `metrics("io.confluent.flink/num_records_out").rollup("rate").groupBy("statement_name")` |
| `io.confluent.flink/pending_records` | Records pending processing (backpressure indicator) | `io_confluent_flink_pending_records{resource_type="flink_statement"}` | `timeseries max(io.confluent.flink.pending_records), by:{statement_name}` | `max:confluent_cloud.flink.pending_records{*} by {statement_name}` | `index=confluent_cloud source="cc_metrics_api" metric_name="io.confluent.flink/pending_records" \| stats max(metric_value) as pending by statement_name` | `SELECT latest(io.confluent.flink.pending_records) FROM ConfluentCloudFlinkSample FACET statement_name` | `metrics("io.confluent.flink/pending_records").rollup("max").groupBy("statement_name")` |
| `io.confluent.flink/current_cfu` | Current CFU usage by compute pool | `io_confluent_flink_current_cfu{resource_type="flink_compute_pool"}` | `timeseries avg(io.confluent.flink.current_cfu), by:{compute_pool_name}` | `avg:confluent_cloud.flink.current_cfu{*} by {compute_pool_name}` | `index=confluent_cloud source="cc_metrics_api" metric_name="io.confluent.flink/current_cfu" \| stats latest(metric_value) by compute_pool_name` | `SELECT latest(io.confluent.flink.current_cfu) FROM ConfluentCloudFlinkSample FACET compute_pool_name` | `metrics("io.confluent.flink/current_cfu").rollup("last").groupBy("compute_pool_name")` |
| `io.confluent.flink/max_cfu` | Maximum CFU configured for compute pool | `io_confluent_flink_max_cfu{resource_type="flink_compute_pool"}` | `timeseries avg(io.confluent.flink.max_cfu), by:{compute_pool_name}` | `avg:confluent_cloud.flink.max_cfu{*} by {compute_pool_name}` | `index=confluent_cloud source="cc_metrics_api" metric_name="io.confluent.flink/max_cfu" \| stats latest(metric_value) by compute_pool_name` | `SELECT latest(io.confluent.flink.max_cfu) FROM ConfluentCloudFlinkSample FACET compute_pool_name` | `metrics("io.confluent.flink/max_cfu").rollup("last").groupBy("compute_pool_name")` |

---

## Lakehouse Sink Metrics (ADR-011)

Metrics for the DB-C (Databricks Delta Lake Sink) and SF-A (Snowflake
Snowpipe Streaming) paths. Connector JMX metrics are emitted by the
self-managed Connect worker; CC-managed sinks emit equivalent metrics via
the CC Metrics API.

| Metric Name | Description | Grafana (PromQL) | Dynatrace (DQL) | Datadog (query) | Splunk (SPL) | New Relic (NRQL) | Instana (query) |
|-------------|-------------|------------------|-----------------|-----------------|--------------|------------------|-----------------|
| `kafka_connect_sink_record_send_total` | Total records successfully sent to lakehouse target | `rate(kafka_connect_sink_record_send_total{connector=~"lakehouse-.*"}[5m])` | `timeseries rate(kafka_connect.sink.record_send_total), by:{connector}` | `rate:kafka.connect.sink.record_send_total{connector:lakehouse-*}.as_rate()` | `index=kafka sourcetype=jmx metric_name="kafka_connect_sink_record_send_total" connector="lakehouse-*"` | `SELECT rate(sum(kafka.connect.sink.record_send_total), 5 MINUTES) FROM KafkaConnectSinkSample WHERE connector LIKE 'lakehouse-%' FACET connector` | `metrics("kafka.connect.sink.record_send_total").filter("connector", "lakehouse-*").rate(300).groupBy("connector")` |
| `kafka_connect_connector_task_status` | Per-task state (running / failed / paused / unassigned) | `kafka_connect_connector_task_status{connector=~"lakehouse-.*", state="failed"}` | `fetch dt.entity.kafka_connector \| fields task_state \| filter connector startsWith "lakehouse-"` | `kafka.connect.connector.task_status{connector:lakehouse-*,state:failed}` | `index=kafka sourcetype=jmx metric_name="kafka_connect_connector_task_status" connector="lakehouse-*"` | `SELECT latest(kafka.connect.connector.task_status) FROM KafkaConnectSample WHERE connector LIKE 'lakehouse-%' FACET connector, state` | `metrics("kafka.connect.connector.task_status").filter("connector", "lakehouse-*").groupBy("connector", "state")` |
| `kafka_connect_sink_put_batch_duration_ms` | Histogram of batch put duration (Connect -> target commit) | `histogram_quantile(0.95, sum by (connector, le) (rate(kafka_connect_sink_put_batch_duration_ms_bucket{connector=~"lakehouse-.*"}[5m])))` | `timeseries percentile(kafka_connect.sink.put_batch_duration_ms, 95), by:{connector}` | `p95:kafka.connect.sink.put_batch_duration_ms{connector:lakehouse-*}` | `index=kafka sourcetype=jmx metric_name="kafka_connect_sink_put_batch_duration_ms" connector="lakehouse-*" \| stats p95(metric_value) by connector` | `SELECT percentile(kafka.connect.sink.put_batch_duration_ms, 95) FROM KafkaConnectSinkSample WHERE connector LIKE 'lakehouse-%' FACET connector TIMESERIES` | `metrics("kafka.connect.sink.put_batch_duration_ms").filter("connector", "lakehouse-*").rollup("p95").groupBy("connector")` |
| DLQ topic throughput (records/sec) | Rate of records written to `lakehouse.dlq.*` topics | `sum(rate(confluent_kafka_server_received_records{topic=~"lakehouse\\.dlq\\..*"}[5m]))` | `fetch dt.entity.kafka_topic \| filter topic startsWith "lakehouse.dlq." \| timeseries rate(received_records)` | `rate:confluent_kafka_server.received_records{topic:lakehouse.dlq.*}.as_rate()` | `index=kafka sourcetype=confluent_metrics metric_name="received_records" topic="lakehouse.dlq.*" \| timechart span=5m rate(received_records)` | `SELECT rate(sum(received_records), 5 MINUTES) FROM ConfluentCloudMetric WHERE topic LIKE 'lakehouse.dlq.%' FACET topic` | `metrics("received_records").filter("topic", "lakehouse.dlq.*").rate(300).groupBy("topic")` |
| `snowflake_streaming_channel_offset_lag` | Per-channel offset gap between Kafka consumer position and Snowflake commit offset (SF-A only) | `snowflake_streaming_channel_offset_lag{connector=~"lakehouse-snowflake-.*"}` | `fetch dt.entity.kafka_connector \| fields snowflake_channel_lag \| filter connector startsWith "lakehouse-snowflake-"` | `snowflake.streaming.channel_offset_lag{connector:lakehouse-snowflake-*}` | `index=kafka sourcetype=jmx metric_name="snowflake_streaming_channel_offset_lag" connector="lakehouse-snowflake-*"` | `SELECT latest(snowflake.streaming.channel_offset_lag) FROM KafkaConnectSinkSample WHERE connector LIKE 'lakehouse-snowflake-%' FACET connector, channel` | `metrics("snowflake.streaming.channel_offset_lag").filter("connector", "lakehouse-snowflake-*").groupBy("connector", "channel")` |
| `snowflake_streaming_insert_errors_total` | Snowpipe Streaming insert errors by error code (SF-A only) | `rate(snowflake_streaming_insert_errors_total{connector=~"lakehouse-snowflake-.*"}[5m])` | `timeseries rate(snowflake.streaming.insert_errors_total), by:{connector, error_code}` | `rate:snowflake.streaming.insert_errors_total{connector:lakehouse-snowflake-*}.as_rate()` | `index=kafka sourcetype=jmx metric_name="snowflake_streaming_insert_errors_total" connector="lakehouse-snowflake-*" \| stats sum(metric_value) by error_code` | `SELECT rate(sum(snowflake.streaming.insert_errors_total), 5 MINUTES) FROM KafkaConnectSinkSample WHERE connector LIKE 'lakehouse-snowflake-%' FACET error_code` | `metrics("snowflake.streaming.insert_errors_total").filter("connector", "lakehouse-snowflake-*").rate(300).groupBy("error_code")` |

---

## Tableflow Metrics (CC-only, ADR-011 DB-A / SF-B)

Tableflow exposes managed metrics via the CC Metrics API only. These do not
exist for CP / CFK / LinuxONE deployments. Use the lakehouse sink metrics
above for those models.

| Metric Name (CC Metrics API) | Description | Grafana (PromQL) | Dynatrace (DQL) | Datadog (query) | Splunk (SPL) | New Relic (NRQL) | Instana (query) |
|------------------------------|-------------|------------------|-----------------|-----------------|--------------|------------------|-----------------|
| `io.confluent.kafka.server/tableflow_topic_state` | Tableflow topic state (ACTIVE / PAUSED / ERROR) | `io_confluent_kafka_server_tableflow_topic_state{kafka_id="$CLUSTER_ID"}` | `fetch dt.entity.custom_device \| fields tableflow_topic_state \| filter kafka_id == "$CLUSTER_ID"` | `confluent_kafka_server.tableflow_topic_state{kafka_id:$CLUSTER_ID}` | `index=confluent_cloud source="cc_metrics_api" metric_name="io.confluent.kafka.server/tableflow_topic_state"` | `SELECT latest(tableflow_topic_state) FROM ConfluentCloudMetric WHERE kafka_id = '$CLUSTER_ID' FACET topic` | `metrics("tableflow_topic_state").filter("kafka_id", "$CLUSTER_ID").groupBy("topic")` |
| `io.confluent.kafka.server/tableflow_materialization_lag_seconds` | Lag between record append and visibility in materialized table | `histogram_quantile(0.95, sum by (le) (rate(io_confluent_kafka_server_tableflow_materialization_lag_seconds_bucket{kafka_id="$CLUSTER_ID"}[5m])))` | `timeseries percentile(tableflow_materialization_lag_seconds, 95), by:{topic}` | `p95:confluent_kafka_server.tableflow_materialization_lag_seconds{kafka_id:$CLUSTER_ID}` | `index=confluent_cloud source="cc_metrics_api" metric_name="io.confluent.kafka.server/tableflow_materialization_lag_seconds" \| stats p95(metric_value) by topic` | `SELECT percentile(tableflow_materialization_lag_seconds, 95) FROM ConfluentCloudMetric WHERE kafka_id = '$CLUSTER_ID' FACET topic TIMESERIES` | `metrics("tableflow_materialization_lag_seconds").filter("kafka_id", "$CLUSTER_ID").rollup("p95").groupBy("topic")` |
| `io.confluent.kafka.server/tableflow_records_materialized_total` | Records processed by Tableflow per topic | `rate(io_confluent_kafka_server_tableflow_records_materialized_total{kafka_id="$CLUSTER_ID"}[5m])` | `timeseries rate(tableflow_records_materialized_total), by:{topic}` | `rate:confluent_kafka_server.tableflow_records_materialized_total{kafka_id:$CLUSTER_ID}.as_rate()` | `index=confluent_cloud source="cc_metrics_api" metric_name="io.confluent.kafka.server/tableflow_records_materialized_total" \| timechart span=5m rate(metric_value) by topic` | `SELECT rate(sum(tableflow_records_materialized_total), 5 MINUTES) FROM ConfluentCloudMetric WHERE kafka_id = '$CLUSTER_ID' FACET topic` | `metrics("tableflow_records_materialized_total").filter("kafka_id", "$CLUSTER_ID").rate(300).groupBy("topic")` |
| `io.confluent.kafka.server/tableflow_file_size_bytes` | File size distribution for materialized Iceberg/Delta files | `avg by (topic) (io_confluent_kafka_server_tableflow_file_size_bytes{kafka_id="$CLUSTER_ID"})` | `timeseries avg(tableflow_file_size_bytes), by:{topic}` | `avg:confluent_kafka_server.tableflow_file_size_bytes{kafka_id:$CLUSTER_ID} by {topic}` | `index=confluent_cloud source="cc_metrics_api" metric_name="io.confluent.kafka.server/tableflow_file_size_bytes" \| stats avg(metric_value) by topic` | `SELECT average(tableflow_file_size_bytes) FROM ConfluentCloudMetric WHERE kafka_id = '$CLUSTER_ID' FACET topic` | `metrics("tableflow_file_size_bytes").filter("kafka_id", "$CLUSTER_ID").rollup("avg").groupBy("topic")` |
| `io.confluent.kafka.server/tableflow_catalog_sync_errors_total` | Catalog integration errors (Unity Catalog / Snowflake Horizon writes) | `rate(io_confluent_kafka_server_tableflow_catalog_sync_errors_total{kafka_id="$CLUSTER_ID"}[5m])` | `timeseries rate(tableflow_catalog_sync_errors_total), by:{topic, catalog_target}` | `rate:confluent_kafka_server.tableflow_catalog_sync_errors_total{kafka_id:$CLUSTER_ID}.as_rate()` | `index=confluent_cloud source="cc_metrics_api" metric_name="io.confluent.kafka.server/tableflow_catalog_sync_errors_total" \| timechart span=5m rate(metric_value) by catalog_target` | `SELECT rate(sum(tableflow_catalog_sync_errors_total), 5 MINUTES) FROM ConfluentCloudMetric WHERE kafka_id = '$CLUSTER_ID' FACET topic, catalog_target` | `metrics("tableflow_catalog_sync_errors_total").filter("kafka_id", "$CLUSTER_ID").rate(300).groupBy("topic", "catalog_target")` |

Vendor coverage status: Grafana dashboards ship in this phase. Datadog,
Dynatrace, NewRelic, Instana, and Splunk equivalents follow the queries
above; promote to first-class dashboards via the same templates when the
operator needs them.

---

## Database Connector Metrics (ADR-012)

Metrics for the MongoDB / Redis / CockroachDB / PostgreSQL connectors.
Connect-based connectors emit JMX (scraped via the platform JMX exporter);
CockroachDB native changefeed metrics live in the CRDB Prometheus endpoint,
not in Connect.

### Connect-based connectors (MongoDB, Redis, JDBC sinks, Debezium Postgres)

The Lakehouse-section metrics (`kafka_connect_sink_record_send_total`,
`kafka_connect_connector_task_status`, `kafka_connect_sink_put_batch_duration_ms`)
apply identically; filter by `connector=~"database-.*"` instead of
`connector=~"lakehouse-.*"`.

DLQ queries change prefix from `lakehouse.dlq.*` to `database.dlq.*`:

| Metric | Grafana (PromQL) |
|---|---|
| DLQ rate -- all database connectors | `sum(rate(confluent_kafka_server_received_records{topic=~"database\\.dlq\\..*"}[5m]))` |
| DLQ rate -- MongoDB only | `sum(rate(confluent_kafka_server_received_records{topic=~"database\\.dlq\\.mongodb-.*"}[5m]))` |
| DLQ rate -- Postgres CDC only | `sum(rate(confluent_kafka_server_received_records{topic=~"database\\.dlq\\.postgres-source-.*"}[5m]))` |

### CDC-specific JMX metrics

| Metric | Description | Grafana (PromQL) | Datadog | Splunk |
|---|---|---|---|---|
| `mongodb_kafka_connect_source_cursor_age_seconds` | Age of oldest unconsumed change-stream change | `mongodb_kafka_connect_source_cursor_age_seconds{connector=~"database-mongodb-source-.*"}` | `mongodb.kafka_connect.source.cursor_age{connector:database-mongodb-source-*}` | `index=kafka sourcetype=jmx metric_name="mongodb_kafka_connect_source_cursor_age_seconds"` |
| `debezium_metrics_milliseconds_behind_source` | Postgres CDC consumer lag in ms | `debezium_metrics_milliseconds_behind_source{connector=~"database-postgres-source-.*"}` | `debezium.metrics.milliseconds_behind_source{connector:database-postgres-source-*}` | `index=kafka sourcetype=jmx metric_name="debezium_metrics_milliseconds_behind_source"` |
| `debezium_metrics_rows_scanned` | Rows snapshotted during initial sync | `debezium_metrics_rows_scanned{connector=~"database-postgres-source-.*"}` | `debezium.metrics.rows_scanned` | `index=kafka sourcetype=jmx metric_name="debezium_metrics_rows_scanned"` |

### Postgres slot lag (Postgres exporter, NOT Connect)

The single most important Postgres CDC metric: if the slot lag grows
unbounded, Postgres disk fills. **Alert > 1 GiB.** Source is
`postgres_exporter`, not Connect.

| Metric | Description | Grafana (PromQL) |
|---|---|---|
| `pg_replication_slots_pg_wal_lsn_diff` | Bytes of WAL retained by the slot | `max(pg_replication_slots_pg_wal_lsn_diff{slot_name=~"fsi_kafka_.*"})` |
| Alert condition | Slot lag > 1 GiB | `max(pg_replication_slots_pg_wal_lsn_diff{slot_name=~"fsi_kafka_.*"}) > 1073741824` |

### CockroachDB native changefeed (NOT Connect-based)

Metrics live in the CRDB Prometheus endpoint (port 8080 by default;
26258 on CRDB 23.2+). The Grafana dashboard for this path requires a
separate Prometheus scrape job targeting CRDB nodes.

| Metric | Description | Grafana (PromQL) |
|---|---|---|
| `changefeed_running` | Currently running changefeed jobs | `count(changefeed_running{cluster="$CRDB_CLUSTER"})` |
| `changefeed_emitted_messages` | Events delivered to Kafka | `rate(changefeed_emitted_messages{cluster="$CRDB_CLUSTER"}[5m])` |
| `changefeed_emit_latency` | CRDB-to-Kafka emit latency (histogram, nanoseconds) | `histogram_quantile(0.95, sum by (le) (rate(changefeed_emit_latency_bucket{cluster="$CRDB_CLUSTER"}[5m]))) / 1000000` (ms) |
| `changefeed_error_retries` | Sink errors retried | `sum(rate(changefeed_error_retries{cluster="$CRDB_CLUSTER"}[1m])) * 60` |
| `changefeed_checkpoint_progress` | Highest resolved-timestamp emitted (nanoseconds) | `(time() - changefeed_checkpoint_progress{cluster="$CRDB_CLUSTER"} / 1000000000)` (sec lag) |

Equivalents for other vendors follow the same shape -- substitute the
metric name into the vendor's query syntax. Grafana ships as the baseline
in this phase; promote to first-class dashboards in Datadog / Dynatrace /
NewRelic / Instana / Splunk when operator demand emerges.

---

## Provider Reference

| Provider | Metrics Ingestion Endpoint | Authentication | Documentation |
|----------|--------------------------|----------------|---------------|
| Grafana/Prometheus | CC Metrics API Prometheus export: `https://api.telemetry.confluent.cloud/v2/metrics/cloud/export` | Basic auth (CC API key/secret) | [Confluent Docs: Metrics API](https://docs.confluent.io/cloud/current/monitoring/metrics-api.html) |
| Dynatrace | Dynatrace API v2: `{ENV_URL}/api/v2/metrics/ingest` | API token with `metrics.ingest` scope | [Dynatrace Docs: Metrics Ingestion](https://www.dynatrace.com/support/help/dynatrace-api/environment-api/metric-v2) |
| Datadog | Datadog API: `https://api.datadoghq.com/api/v1/series` | API key + Application key | [Datadog Docs: Metrics API](https://docs.datadoghq.com/api/latest/metrics/) |
| Splunk | HTTP Event Collector: `https://{SPLUNK_HOST}:8088/services/collector` | HEC token | [Splunk Docs: HEC](https://docs.splunk.com/Documentation/Splunk/latest/Data/UsetheHTTPEventCollector) |
| New Relic | New Relic Metrics API: `https://metric-api.newrelic.com/metric/v1` | Ingest license key | [New Relic Docs: Metrics API](https://docs.newrelic.com/docs/telemetry-data-platform/ingest-apis/metric-api/) |
| IBM Instana | Instana REST API: `https://{INSTANA_HOST}/api/custom-dashboards` | API token | [Instana Docs: REST API](https://www.ibm.com/docs/en/instana-observability/current?topic=api-rest) |
