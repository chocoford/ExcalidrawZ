using System.Text.Json;
using System.Text.Json.Serialization;

namespace ExcalidrawZ.Canvas.Bridge;

public static class BridgeJsonCodec
{
    internal static readonly JsonSerializerOptions SerializerOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        PropertyNameCaseInsensitive = false,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
    };

    public static BridgeParseResult Deserialize(string json, BridgeDirection direction)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return BridgeParseResult.Failure("The bridge message is empty.");
        }

        BridgeMessage? message;
        try
        {
            message = JsonSerializer.Deserialize<BridgeMessage>(json, SerializerOptions);
        }
        catch (JsonException exception)
        {
            return BridgeParseResult.Failure($"The bridge message is invalid JSON: {exception.Message}");
        }

        if (message is null)
        {
            return BridgeParseResult.Failure("The bridge message cannot be null.");
        }

        string? validationError = Validate(message, direction);
        return validationError is null
            ? BridgeParseResult.Success(message)
            : BridgeParseResult.Failure(validationError);
    }

    public static string Serialize(BridgeMessage message, BridgeDirection direction)
    {
        ArgumentNullException.ThrowIfNull(message);

        string? validationError = Validate(message, direction);
        if (validationError is not null)
        {
            throw new ArgumentException(validationError, nameof(message));
        }

        return JsonSerializer.Serialize(message, SerializerOptions);
    }

    private static string? Validate(BridgeMessage message, BridgeDirection direction)
    {
        if (message.ProtocolVersion != BridgeProtocol.CurrentVersion)
        {
            return $"Unsupported bridge protocol version '{message.ProtocolVersion}'.";
        }

        if (!Guid.TryParseExact(message.MessageId, "D", out _))
        {
            return "The bridge messageId must be a canonical GUID.";
        }

        if (message.CorrelationId is not null &&
            !Guid.TryParseExact(message.CorrelationId, "D", out _))
        {
            return "The bridge correlationId must be a canonical GUID when present.";
        }

        ISet<string> allowedEvents = direction switch
        {
            BridgeDirection.JavaScriptToNative => BridgeEvents.JavaScriptToNativeEvents,
            BridgeDirection.NativeToJavaScript => BridgeEvents.NativeToJavaScriptEvents,
            _ => throw new ArgumentOutOfRangeException(nameof(direction), direction, null),
        };

        if (string.IsNullOrWhiteSpace(message.EventName) || !allowedEvents.Contains(message.EventName))
        {
            return $"The event '{message.EventName}' is not allowed for {direction}.";
        }

        if (message.Payload.ValueKind is JsonValueKind.Undefined)
        {
            return "The bridge payload is required.";
        }

        return ValidatePayload(message);
    }

    private static string? ValidatePayload(BridgeMessage message)
    {
        if (message.Payload.ValueKind is not JsonValueKind.Object)
        {
            return $"The payload for '{message.EventName}' must be a JSON object.";
        }

        return message.EventName switch
        {
            BridgeEvents.CanvasReady => ValidateArrayProperty(message.Payload, "capabilities"),
            BridgeEvents.DocumentChanged => ValidateBooleanProperty(message.Payload, "isDirty"),
            BridgeEvents.DocumentSnapshot =>
                message.CorrelationId is null
                    ? "A document snapshot must include correlationId."
                    : ValidateObjectProperty(message.Payload, "document"),
            BridgeEvents.BridgeError => ValidateStringProperty(message.Payload, "message"),
            BridgeEvents.OpenDocument =>
                ValidateObjectProperty(message.Payload, "document") ??
                ValidateStringProperty(message.Payload, "fileName"),
            BridgeEvents.RequestSnapshot => null,
            BridgeEvents.SetTheme => ValidateTheme(message.Payload),
            _ => $"No payload schema is registered for '{message.EventName}'.",
        };
    }

    private static string? ValidateArrayProperty(JsonElement payload, string propertyName)
    {
        return payload.TryGetProperty(propertyName, out JsonElement value) &&
            value.ValueKind is JsonValueKind.Array
            ? null
            : $"The payload property '{propertyName}' must be an array.";
    }

    private static string? ValidateBooleanProperty(JsonElement payload, string propertyName)
    {
        return payload.TryGetProperty(propertyName, out JsonElement value) &&
            value.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? null
            : $"The payload property '{propertyName}' must be a boolean.";
    }

    private static string? ValidateObjectProperty(JsonElement payload, string propertyName)
    {
        return payload.TryGetProperty(propertyName, out JsonElement value) &&
            value.ValueKind is JsonValueKind.Object
            ? null
            : $"The payload property '{propertyName}' must be an object.";
    }

    private static string? ValidateStringProperty(JsonElement payload, string propertyName)
    {
        return payload.TryGetProperty(propertyName, out JsonElement value) &&
            value.ValueKind is JsonValueKind.String &&
            !string.IsNullOrWhiteSpace(value.GetString())
            ? null
            : $"The payload property '{propertyName}' must be a non-empty string.";
    }

    private static string? ValidateTheme(JsonElement payload)
    {
        string? propertyError = ValidateStringProperty(payload, "theme");
        if (propertyError is not null)
        {
            return propertyError;
        }

        string? theme = payload.GetProperty("theme").GetString();
        return theme is "light" or "dark" or "system"
            ? null
            : "The canvas theme must be 'light', 'dark', or 'system'.";
    }
}
