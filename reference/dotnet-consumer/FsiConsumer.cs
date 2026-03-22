// =============================================================================
// FSI C4E Reference Consumer — .NET (API Event Grid)
// =============================================================================

using System;
using System.Threading;
using Confluent.Kafka;
using Confluent.SchemaRegistry;
using Confluent.SchemaRegistry.Serdes;
using Avro.Generic;

namespace Fsi.Kafka.Consumer
{
    /// <summary>
    /// Reference consumer for .NET applications.
    /// Manual offset commit, graceful shutdown, Dynatrace stats callback.
    /// </summary>
    public class FsiConsumer : IDisposable
    {
        private readonly IConsumer<string, GenericRecord> _consumer;
        private readonly CachedSchemaRegistryClient _schemaRegistry;
        private readonly CancellationTokenSource _cts = new();

        private long _totalConsumed;
        private long _totalErrors;

        public FsiConsumer(FsiConsumerConfig config)
        {
            var srConfig = new SchemaRegistryConfig
            {
                Url = config.SchemaRegistryUrl ?? "https://schema.fsi.internal",
                BasicAuthCredentialsSource = AuthCredentialsSource.UserInfo,
                BasicAuthUserInfo = config.SchemaRegistryAuth
            };
            _schemaRegistry = new CachedSchemaRegistryClient(srConfig);

            var consumerConfig = new ConsumerConfig
            {
                BootstrapServers = config.BootstrapServers ?? "kafka.fsi.internal:9092",
                SecurityProtocol = SecurityProtocol.SaslSsl,
                SaslMechanism = SaslMechanism.Plain,
                SaslUsername = config.SaslUsername,
                SaslPassword = config.SaslPassword,

                GroupId = config.GroupId
                    ?? throw new ArgumentException("GroupId is required"),

                // C4E MANDATORY: Manual commit
                EnableAutoCommit = false,
                AutoOffsetReset = AutoOffsetReset.Earliest,

                // Performance
                MaxPollIntervalMs = 300000,
                FetchMinBytes = 1024,
                FetchWaitMaxMs = 500,

                ClientId = config.ClientId
                    ?? $"fsi-{config.GroupId}-consumer-dotnet",

                StatisticsIntervalMs = 30000
            };

            _consumer = new ConsumerBuilder<string, GenericRecord>(consumerConfig)
                .SetValueDeserializer(new AvroDeserializer<GenericRecord>(_schemaRegistry).AsSyncOverAsync())
                .SetStatisticsHandler((_, json) =>
                    Console.WriteLine($"[FSI Consumer Stats] consumed={_totalConsumed} errors={_totalErrors}"))
                .SetErrorHandler((_, error) =>
                    Console.Error.WriteLine($"[FSI Consumer ERROR] {error.Reason}"))
                .Build();

            Console.WriteLine($"[FSI Consumer] Initialized, group: {config.GroupId}");
        }

        /// <summary>
        /// Start consuming. Blocks until cancellation.
        /// </summary>
        /// <param name="topics">Comma-separated topic names</param>
        /// <param name="handler">Record processing function</param>
        public void Start(string topics, Action<string, GenericRecord> handler)
        {
            var topicList = topics.Split(',', StringSplitOptions.RemoveEmptyEntries);
            _consumer.Subscribe(topicList);
            Console.WriteLine($"[FSI Consumer] Subscribed to: {topics}");

            try
            {
                while (!_cts.IsCancellationRequested)
                {
                    var result = _consumer.Consume(_cts.Token);

                    try
                    {
                        handler(result.Message.Key, result.Message.Value);
                        Interlocked.Increment(ref _totalConsumed);
                    }
                    catch (Exception ex)
                    {
                        Interlocked.Increment(ref _totalErrors);
                        Console.Error.WriteLine(
                            $"[FSI Consumer] Error processing [{result.Topic}/{result.Partition}@{result.Offset}]: {ex.Message}");
                        // Default: log and continue (at-least-once)
                    }

                    // Commit after each record (can batch for throughput)
                    _consumer.Commit(result);
                }
            }
            catch (OperationCanceledException)
            {
                Console.WriteLine("[FSI Consumer] Cancelled — shutting down");
            }
            finally
            {
                _consumer.Close();
            }
        }

        public void Shutdown() => _cts.Cancel();

        public void Dispose()
        {
            _cts.Cancel();
            _consumer?.Dispose();
            _schemaRegistry?.Dispose();
        }
    }

    public class FsiConsumerConfig
    {
        public string BootstrapServers { get; set; }
        public string SaslUsername { get; set; }
        public string SaslPassword { get; set; }
        public string SchemaRegistryUrl { get; set; }
        public string SchemaRegistryAuth { get; set; }
        public string GroupId { get; set; }
        public string ClientId { get; set; }
    }
}
