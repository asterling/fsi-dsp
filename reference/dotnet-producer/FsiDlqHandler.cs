// =============================================================================
// FSI C4E DLQ Handler -- .NET
// =============================================================================
// Routes failed messages to {source-topic}.dlq with error categorization,
// exponential backoff retry, and Kafka header metadata.
//
// This is a reference implementation. Copy and adapt for your application.
// =============================================================================

using System;
using System.Collections.Generic;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Confluent.Kafka;

namespace Fsi.Kafka.Producer
{
    /// <summary>
    /// DLQ handler for .NET Kafka producers. Routes failed messages to
    /// {source-topic}.dlq with error categorization and retry logic.
    /// </summary>
    public class FsiDlqHandler : IDisposable
    {
        /// <summary>Maximum retry attempts before routing to DLQ.</summary>
        public const int MaxRetries = 3;

        /// <summary>Base backoff in milliseconds (doubles each retry: 1s, 2s, 4s).</summary>
        public const int BaseBackoffMs = 1000;

        private readonly IProducer<byte[], byte[]> _dlqProducer;
        private readonly string _dlqTopic;
        private readonly string _sourceTopic;
        private readonly string _clientId;
        private long _dlqSent;

        /// <summary>Total messages routed to DLQ (observable metric).</summary>
        public long DlqSent => Interlocked.Read(ref _dlqSent);

        /// <summary>
        /// Create a DLQ handler with a dedicated raw-bytes producer.
        /// </summary>
        /// <param name="config">Producer config with connection details.</param>
        /// <param name="sourceTopic">Original topic name -- DLQ topic will be {sourceTopic}.dlq.</param>
        public FsiDlqHandler(FsiProducerConfig config, string sourceTopic)
        {
            _sourceTopic = sourceTopic;
            _dlqTopic = sourceTopic + ".dlq";
            _clientId = (config.ClientId ?? "fsi-dlq") + "-dlq";

            var dlqConfig = new ProducerConfig
            {
                BootstrapServers = config.BootstrapServers ?? "kafka.fsi.internal:9092",
                ClientId = _clientId,
            };

            // Copy SASL config if credentials provided
            if (!string.IsNullOrEmpty(config.SaslUsername))
            {
                dlqConfig.SecurityProtocol = SecurityProtocol.SaslSsl;
                dlqConfig.SaslMechanism = SaslMechanism.Plain;
                dlqConfig.SaslUsername = config.SaslUsername;
                dlqConfig.SaslPassword = config.SaslPassword;
            }

            _dlqProducer = new ProducerBuilder<byte[], byte[]>(dlqConfig).Build();

            Console.WriteLine($"[FSI DLQ Handler] Initialized. DLQ topic: {_dlqTopic}");
        }

        /// <summary>
        /// Check if a produce exception is retryable.
        /// </summary>
        public bool IsRetryable(ProduceException<string, Avro.Generic.GenericRecord> ex)
        {
            return ex.Error.Code switch
            {
                // Retryable errors
                ErrorCode.Local_MsgTimedOut => true,
                ErrorCode.NotLeaderForPartition => true,
                ErrorCode.LeaderNotAvailable => true,
                ErrorCode.RequestTimedOut => true,
                ErrorCode.BrokerNotAvailable => true,

                // Non-retryable errors
                ErrorCode.Local_ValueSerialization => false,
                ErrorCode.Local_KeySerialization => false,
                ErrorCode.TopicAuthorizationFailed => false,
                ErrorCode.GroupAuthorizationFailed => false,
                ErrorCode.ClusterAuthorizationFailed => false,

                // Default: assume retryable
                _ => true,
            };
        }

        /// <summary>
        /// Calculate exponential backoff delay for a given retry count.
        /// </summary>
        /// <param name="retryCount">Current retry attempt (0-based).</param>
        /// <returns>Backoff in milliseconds (1s, 2s, 4s).</returns>
        public int GetBackoffMs(int retryCount)
        {
            return BaseBackoffMs * (1 << retryCount);
        }

        /// <summary>
        /// Send a failed message to the DLQ topic with error metadata headers.
        /// </summary>
        public async Task SendToDlqAsync(byte[] key, byte[] value, Exception error, int retryCount)
        {
            var errorType = ClassifyError(error);
            var errorMessage = error.Message?.Length > 1024
                ? error.Message.Substring(0, 1024)
                : error.Message ?? "null";
            var timestamp = DateTimeOffset.UtcNow.ToString("o");

            var headers = new Headers
            {
                { "dlq.original.topic", Encoding.UTF8.GetBytes(_sourceTopic) },
                { "dlq.error.type", Encoding.UTF8.GetBytes(errorType) },
                { "dlq.error.message", Encoding.UTF8.GetBytes(errorMessage) },
                { "dlq.timestamp", Encoding.UTF8.GetBytes(timestamp) },
                { "dlq.retry.count", Encoding.UTF8.GetBytes(retryCount.ToString()) },
                { "dlq.producer.client.id", Encoding.UTF8.GetBytes(_clientId) },
            };

            var message = new Message<byte[], byte[]>
            {
                Key = key,
                Value = value,
                Headers = headers,
            };

            try
            {
                var result = await _dlqProducer.ProduceAsync(_dlqTopic, message);
                Interlocked.Increment(ref _dlqSent);
                Console.Error.WriteLine(
                    $"[FSI DLQ Handler] Sent to {result.Topic}-{result.Partition.Value} " +
                    $"offset={result.Offset.Value} [error_type={errorType}, retries={retryCount}]");
            }
            catch (ProduceException<byte[], byte[]> ex)
            {
                Console.Error.WriteLine(
                    $"[FSI DLQ Handler] Failed to deliver to DLQ {_dlqTopic}: {ex.Error.Reason}");
            }
        }

        /// <summary>
        /// Classify an exception into a human-readable error category.
        /// </summary>
        /// <returns>One of: SERIALIZATION, AUTH_DENIED, BROKER_TIMEOUT, UNKNOWN.</returns>
        public string ClassifyError(Exception ex)
        {
            if (ex is ProduceException<string, Avro.Generic.GenericRecord> pe)
            {
                return pe.Error.Code switch
                {
                    ErrorCode.Local_ValueSerialization => "SERIALIZATION",
                    ErrorCode.Local_KeySerialization => "SERIALIZATION",
                    ErrorCode.TopicAuthorizationFailed => "AUTH_DENIED",
                    ErrorCode.GroupAuthorizationFailed => "AUTH_DENIED",
                    ErrorCode.ClusterAuthorizationFailed => "AUTH_DENIED",
                    ErrorCode.Local_MsgTimedOut => "BROKER_TIMEOUT",
                    ErrorCode.RequestTimedOut => "BROKER_TIMEOUT",
                    ErrorCode.NotLeaderForPartition => "BROKER_TIMEOUT",
                    ErrorCode.LeaderNotAvailable => "BROKER_TIMEOUT",
                    _ => "UNKNOWN",
                };
            }

            // Fallback for non-Kafka exceptions
            if (ex.Message?.Contains("serializ", StringComparison.OrdinalIgnoreCase) == true)
                return "SERIALIZATION";
            if (ex.Message?.Contains("authoriz", StringComparison.OrdinalIgnoreCase) == true)
                return "AUTH_DENIED";
            if (ex.Message?.Contains("timeout", StringComparison.OrdinalIgnoreCase) == true)
                return "BROKER_TIMEOUT";

            return "UNKNOWN";
        }

        /// <summary>
        /// Flush and dispose the DLQ producer. Logs final DLQ metrics.
        /// </summary>
        public void Dispose()
        {
            Console.Error.WriteLine($"[FSI DLQ Handler] Total DLQ messages: {DlqSent}");
            _dlqProducer?.Flush(TimeSpan.FromSeconds(10));
            _dlqProducer?.Dispose();
        }
    }
}
