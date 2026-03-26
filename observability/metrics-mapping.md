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

> **Stub -- wired in Phase 6.** Flink metric names below are from Flink's built-in metrics system. Actual queries will be completed when Flink deployment is implemented in Phase 6.

| Metric Name | Description | Grafana (PromQL) | Dynatrace (DQL) | Datadog (query) | Splunk (SPL) | New Relic (NRQL) | Instana (query) |
|-------------|-------------|------------------|-----------------|-----------------|--------------|------------------|-----------------|
| `flink_jobmanager_job_uptime` | Job uptime in milliseconds | `flink_jobmanager_job_uptime{job_name=~".*"}` | `fetch dt.entity.custom_device \| fields flink_job_uptime` | `flink.jobmanager.job.uptime{*}` | `index=flink metric_name="job_uptime"` | `SELECT latest(job_uptime) FROM FlinkMetric FACET job_name` | `metrics("flink_job_uptime").groupBy("job_name")` |
| `flink_taskmanager_job_task_checkpointAlignmentTime` | Checkpoint alignment time (ms) | `flink_taskmanager_job_task_checkpointAlignmentTime{job_name=~".*"}` | `fetch dt.entity.custom_device \| fields checkpoint_alignment_time` | `flink.taskmanager.job.task.checkpointAlignmentTime{*}` | `index=flink metric_name="checkpoint_alignment_time"` | `SELECT average(checkpointAlignmentTime) FROM FlinkMetric FACET job_name` | `metrics("checkpoint_alignment_time").groupBy("job_name")` |
| `flink_taskmanager_job_task_backPressuredTimeMsPerSecond` | Backpressure time (ms/s) | `flink_taskmanager_job_task_backPressuredTimeMsPerSecond{job_name=~".*"}` | `fetch dt.entity.custom_device \| fields back_pressured_time` | `flink.taskmanager.job.task.backPressuredTimeMsPerSecond{*}` | `index=flink metric_name="back_pressured_time"` | `SELECT average(backPressuredTimeMsPerSecond) FROM FlinkMetric FACET job_name, task_name` | `metrics("back_pressured_time").groupBy("job_name", "task_name")` |
| `flink_taskmanager_job_task_numRecordsOutPerSecond` | Output throughput (records/sec) | `flink_taskmanager_job_task_numRecordsOutPerSecond{job_name=~".*"}` | `fetch dt.entity.custom_device \| fields records_out_per_second` | `flink.taskmanager.job.task.numRecordsOutPerSecond{*}` | `index=flink metric_name="records_out_per_second"` | `SELECT average(numRecordsOutPerSecond) FROM FlinkMetric FACET job_name, task_name` | `metrics("records_out_per_second").groupBy("job_name", "task_name")` |

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
