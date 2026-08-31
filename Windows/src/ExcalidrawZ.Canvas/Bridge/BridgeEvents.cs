namespace ExcalidrawZ.Canvas.Bridge;

public static class BridgeEvents
{
    public const string CanvasReady = "canvas.ready";
    public const string DocumentChanged = "document.changed";
    public const string DocumentSnapshot = "document.snapshot";
    public const string BridgeError = "bridge.error";

    public const string OpenDocument = "document.open";
    public const string RequestSnapshot = "document.requestSnapshot";
    public const string SetTheme = "canvas.setTheme";

    internal static readonly ISet<string> JavaScriptToNativeEvents = new HashSet<string>(
        StringComparer.Ordinal)
    {
        CanvasReady,
        DocumentChanged,
        DocumentSnapshot,
        BridgeError,
    };

    internal static readonly ISet<string> NativeToJavaScriptEvents = new HashSet<string>(
        StringComparer.Ordinal)
    {
        OpenDocument,
        RequestSnapshot,
        SetTheme,
    };
}
