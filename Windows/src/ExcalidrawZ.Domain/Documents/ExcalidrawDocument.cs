using System.Text.Json;

namespace ExcalidrawZ.Domain.Documents;

/// <summary>
/// A validated, platform-neutral Excalidraw document payload.
/// Unknown properties are preserved so newer Excalidraw versions remain compatible.
/// </summary>
public sealed class ExcalidrawDocument
{
    private static readonly JsonDocumentOptions DocumentOptions = new()
    {
        AllowTrailingCommas = false,
        CommentHandling = JsonCommentHandling.Disallow,
        MaxDepth = 256,
    };

    private static readonly JsonSerializerOptions IndentedSerializerOptions = new()
    {
        WriteIndented = true,
    };

    private ExcalidrawDocument(JsonElement root)
    {
        Root = root;
    }

    public JsonElement Root { get; }

    public static ExcalidrawDocument Parse(string json)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(json);

        using JsonDocument document = JsonDocument.Parse(json, DocumentOptions);
        JsonElement root = document.RootElement;

        if (root.ValueKind is not JsonValueKind.Object)
        {
            throw new JsonException("An Excalidraw document must be a JSON object.");
        }

        ValidateOptionalPropertyKind(root, "type", JsonValueKind.String);
        ValidateOptionalPropertyKind(root, "elements", JsonValueKind.Array);
        ValidateOptionalPropertyKind(root, "appState", JsonValueKind.Object);
        ValidateOptionalPropertyKind(root, "files", JsonValueKind.Object);

        return new ExcalidrawDocument(root.Clone());
    }

    public string ToJson(bool writeIndented = false)
    {
        return writeIndented
            ? JsonSerializer.Serialize(Root, IndentedSerializerOptions)
            : Root.GetRawText();
    }

    private static void ValidateOptionalPropertyKind(
        JsonElement root,
        string propertyName,
        JsonValueKind expectedKind)
    {
        if (root.TryGetProperty(propertyName, out JsonElement value) && value.ValueKind != expectedKind)
        {
            throw new JsonException(
                $"The Excalidraw property '{propertyName}' must be {expectedKind} when present.");
        }
    }
}
