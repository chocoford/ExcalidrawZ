using System.Text.Json;
using System.Text.Json.Serialization;

namespace ExcalidrawZ.Canvas.Bridge;

public sealed record BridgeMessage
{
    [JsonPropertyName("protocolVersion")]
    public required int ProtocolVersion { get; init; }

    [JsonPropertyName("messageId")]
    public required string MessageId { get; init; }

    [JsonPropertyName("correlationId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? CorrelationId { get; init; }

    [JsonPropertyName("event")]
    public required string EventName { get; init; }

    [JsonPropertyName("payload")]
    public required JsonElement Payload { get; init; }

    public static BridgeMessage Create(
        string eventName,
        object payload,
        string? correlationId = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(eventName);
        ArgumentNullException.ThrowIfNull(payload);

        return new BridgeMessage
        {
            ProtocolVersion = BridgeProtocol.CurrentVersion,
            MessageId = Guid.NewGuid().ToString("D"),
            CorrelationId = correlationId,
            EventName = eventName,
            Payload = JsonSerializer.SerializeToElement(payload, BridgeJsonCodec.SerializerOptions),
        };
    }
}
