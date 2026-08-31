namespace ExcalidrawZ.Canvas.Bridge;

public readonly record struct BridgeParseResult(
    bool IsSuccess,
    BridgeMessage? Message,
    string? Error)
{
    public static BridgeParseResult Success(BridgeMessage message) => new(true, message, null);

    public static BridgeParseResult Failure(string error) => new(false, null, error);
}
