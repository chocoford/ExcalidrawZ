#if WINDOWS
using ExcalidrawZ.Canvas.Bridge;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;

namespace ExcalidrawZ.Canvas.Hosting;

/// <summary>
/// Owns the trusted local WebView2 origin and the versioned native/JavaScript message channel.
/// </summary>
public sealed class WebViewCanvasHost : IDisposable
{
    public const string AssetHostName = "appassets.excalidrawz.local";

    private static readonly Uri EntryPointUri = new($"https://{AssetHostName}/index.html");

    private readonly WebView2 webView;
    private bool isInitialized;

    public WebViewCanvasHost(WebView2 webView)
    {
        this.webView = webView ?? throw new ArgumentNullException(nameof(webView));
    }

    public event EventHandler<BridgeMessage>? MessageReceived;

    public event EventHandler<string>? MessageRejected;

    public event EventHandler<Uri>? ExternalNavigationBlocked;

    public async Task InitializeAsync(string contentRoot)
    {
        if (isInitialized)
        {
            return;
        }

        string fullContentRoot = Path.GetFullPath(contentRoot);
        if (!Directory.Exists(fullContentRoot))
        {
            throw new DirectoryNotFoundException(
                $"The canvas content directory does not exist: {fullContentRoot}");
        }

        await webView.EnsureCoreWebView2Async();

        CoreWebView2 coreWebView = webView.CoreWebView2;
        coreWebView.Settings.IsWebMessageEnabled = true;
        coreWebView.Settings.AreHostObjectsAllowed = false;
        coreWebView.Settings.IsScriptEnabled = true;
#if !DEBUG
        coreWebView.Settings.AreDevToolsEnabled = false;
#endif

        coreWebView.SetVirtualHostNameToFolderMapping(
            AssetHostName,
            fullContentRoot,
            CoreWebView2HostResourceAccessKind.DenyCors);

        coreWebView.WebMessageReceived += OnWebMessageReceived;
        coreWebView.NavigationStarting += OnNavigationStarting;
        coreWebView.NewWindowRequested += OnNewWindowRequested;

        isInitialized = true;
        webView.Source = EntryPointUri;
    }

    public void Send(BridgeMessage message)
    {
        if (!isInitialized)
        {
            throw new InvalidOperationException("The canvas host has not been initialized.");
        }

        string json = BridgeJsonCodec.Serialize(message, BridgeDirection.NativeToJavaScript);
        webView.CoreWebView2.PostWebMessageAsJson(json);
    }

    public void Dispose()
    {
        if (!isInitialized)
        {
            return;
        }

        CoreWebView2 coreWebView = webView.CoreWebView2;
        coreWebView.WebMessageReceived -= OnWebMessageReceived;
        coreWebView.NavigationStarting -= OnNavigationStarting;
        coreWebView.NewWindowRequested -= OnNewWindowRequested;
        isInitialized = false;
    }

    private void OnWebMessageReceived(
        CoreWebView2 sender,
        CoreWebView2WebMessageReceivedEventArgs args)
    {
        if (!IsTrustedOrigin(args.Source))
        {
            MessageRejected?.Invoke(this, $"Rejected bridge message from '{args.Source}'.");
            return;
        }

        BridgeParseResult result = BridgeJsonCodec.Deserialize(
            args.WebMessageAsJson,
            BridgeDirection.JavaScriptToNative);

        if (!result.IsSuccess || result.Message is null)
        {
            MessageRejected?.Invoke(this, result.Error ?? "Rejected an unknown bridge message.");
            return;
        }

        MessageReceived?.Invoke(this, result.Message);
    }

    private void OnNavigationStarting(
        CoreWebView2 sender,
        CoreWebView2NavigationStartingEventArgs args)
    {
        if (IsTrustedOrigin(args.Uri) || string.Equals(args.Uri, "about:blank", StringComparison.Ordinal))
        {
            return;
        }

        args.Cancel = true;
        if (Uri.TryCreate(args.Uri, UriKind.Absolute, out Uri? uri))
        {
            ExternalNavigationBlocked?.Invoke(this, uri);
        }
    }

    private void OnNewWindowRequested(
        CoreWebView2 sender,
        CoreWebView2NewWindowRequestedEventArgs args)
    {
        args.Handled = true;
        if (Uri.TryCreate(args.Uri, UriKind.Absolute, out Uri? uri))
        {
            ExternalNavigationBlocked?.Invoke(this, uri);
        }
    }

    private static bool IsTrustedOrigin(string source)
    {
        return Uri.TryCreate(source, UriKind.Absolute, out Uri? uri) &&
            string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.Ordinal) &&
            string.Equals(uri.Host, AssetHostName, StringComparison.Ordinal) &&
            uri.IsDefaultPort;
    }
}
#endif
