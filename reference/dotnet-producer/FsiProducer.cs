// =============================================================================
// FSI C4E Reference Producer — .NET (API Event Grid)
// =============================================================================
// Dependencies:
//   dotnet add package Confluent.Kafka
//   dotnet add package Confluent.SchemaRegistry.Serdes.Avro
// =============================================================================

using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Confluent.Kafka;
using Confluent.SchemaRegistry;
using Confluent.SchemaRegistry.Serdes;
using Avro.Generic;

namespace Fsi.Kafka.Producer
{
    /// <summary>
    /// Reference producer for .NET applications (API Event Grid).
    /// Mirrors the Java reference: idempotent, Avro, Dynatrace stats callback.
    /// </summary>
    public class FsiProducer : IDisposable
    {
        private readonly IProducer<string, GenericRecord> _producer;
        private readonly CachedSchemaRegistryClient _schemaRegistry;
        private readonly string _topicName;

        // Metrics for Dynatrace (exposed via Statistics callback)
        private long _totalSent;
        private long _totalErrors;

        public FsiProducer(FsiProducerConfig config)
        {
            _topicName = config.TopicName
                ?? throw new ArgumentException("TopicName is required");

            // Schema Registry client
            var srConfig = new SchemaRegistryConfig
            {
                Url = config.SchemaRegistryUrl ?? "https://schema.fsi.internal",
                BasicAuthCredentialsSource = AuthCredentialsSource.UserInfo,
                BasicAuthUserInfo = config.SchemaRegistryAuth
            };
            _schemaRegistry = new CachedSchemaRegistryClient(srConfig);

            // Producer config
            var producerConfig = new ProducerConfig
            {
                BootstrapServers = config.BootstrapServers ?? "kafka.fsi.internal:9092",
                SecurityProtocol = SecurityProtocol.SaslSsl,
                SaslMechanism = SaslMechanism.Plain,
                SaslUsername = config.SaslUsername,
                SaslPassword = config.SaslPassword,

                // C4E MANDATORY: Idempotent producer
                EnableIdempotence = true,
                Acks = Acks.All,
                MaxInFlight = 5,

                // Reliability
                MessageSendMaxRetries = int.MaxValue,
                MessageTimeoutMs = 120000,

                // Performance
                CompressionType = CompressionType.Zstd,
                BatchSize = 32768,
                LingerMs = 20,

                // Client identification
                ClientId = config.ClientId ?? $"fsi-{_topicName.Split('.')[0]}-producer-dotnet",

                // Statistics for Dynatrace
                StatisticsIntervalMs = 30000 // 30s
            };

            _producer = new ProducerBuilder<string, GenericRecord>(producerConfig)
                .SetValueSerializer(new AvroSerializer<GenericRecord>(_schemaRegistry))
                .SetStatisticsHandler((_, json) => HandleStatistics(json))
                .SetErrorHandler((_, error) =>
                {
                    Console.Error.WriteLine($"[FSI Producer ERROR] {error.Reason}");
                    Interlocked.Increment(ref _totalErrors);
                })
                .Build();

            Console.WriteLine($"[FSI Producer] Initialized for topic: {_topicName}");
        }

        /// <summary>
        /// Produce a record asynchronously.
        /// Key should be the natural business key (e.g., event_id, account_number).
        /// </summary>
        public async Task<DeliveryResult<string, GenericRecord>> ProduceAsync(
            string key, GenericRecord value, CancellationToken ct = default)
        {
            try
            {
                var result = await _producer.ProduceAsync(
                    _topicName,
                    new Message<string, GenericRecord> { Key = key, Value = value },
                    ct);

                Interlocked.Increment(ref _totalSent);
                return result;
            }
            catch (ProduceException<string, GenericRecord> ex)
            {
                Interlocked.Increment(ref _totalErrors);
                Console.Error.WriteLine(
                    $"[FSI Producer] Failed to produce [key={key}]: {ex.Error.Reason}");
                throw;
            }
        }

        /// <summary>
        /// Fire-and-forget produce (callbacks only).
        /// Use when you don't need to await the delivery confirmation.
        /// </summary>
        public void Produce(string key, GenericRecord value,
            Action<DeliveryReport<string, GenericRecord>> handler = null)
        {
            _producer.Produce(
                _topicName,
                new Message<string, GenericRecord> { Key = key, Value = value },
                handler ?? (report =>
                {
                    if (report.Error.IsError)
                    {
                        Interlocked.Increment(ref _totalErrors);
                        Console.Error.WriteLine(
                            $"[FSI Producer] Delivery failed: {report.Error.Reason}");
                    }
                    else
                    {
                        Interlocked.Increment(ref _totalSent);
                    }
                }));
        }

        public void Flush(TimeSpan? timeout = null)
            => _producer.Flush(timeout ?? TimeSpan.FromSeconds(30));

        /// <summary>
        /// Statistics callback — Dynatrace .NET OneAgent can scrape these via
        /// custom metrics or the statistics JSON emitted to stdout.
        /// </summary>
        private void HandleStatistics(string json)
        {
            // Dynatrace .NET integration: log statistics JSON for OneAgent ingestion
            // In production, parse and push to custom Dynatrace metrics API
            Console.WriteLine($"[FSI Producer Stats] sent={_totalSent} errors={_totalErrors}");
        }

        public void Dispose()
        {
            Console.WriteLine($"[FSI Producer] Shutting down. sent={_totalSent} errors={_totalErrors}");
            _producer?.Flush(TimeSpan.FromSeconds(30));
            _producer?.Dispose();
            _schemaRegistry?.Dispose();
        }
    }

    public class FsiProducerConfig
    {
        public string BootstrapServers { get; set; }
        public string SaslUsername { get; set; }
        public string SaslPassword { get; set; }
        public string SchemaRegistryUrl { get; set; }
        public string SchemaRegistryAuth { get; set; }  // "api_key:api_secret"
        public string TopicName { get; set; }
        public string ClientId { get; set; }
    }
}
