using System.Text.Json;
using ExcalidrawZ.App.ViewModels;
using ExcalidrawZ.Canvas.Bridge;
using ExcalidrawZ.Canvas.Hosting;
using ExcalidrawZ.Domain.Documents;
using ExcalidrawZ.Storage.Documents;
using Microsoft.UI.Xaml;
using Windows.Storage;
using Windows.Storage.Pickers;

namespace ExcalidrawZ.App;

public sealed partial class MainWindow : Window
{
    private readonly AtomicFileDocumentStore documentStore = new();
    private readonly Dictionary<string, TaskCompletionSource<BridgeMessage>> pendingResponses = [];
    private WebViewCanvasHost? canvasHost;
    private string? currentDocumentPath;

    public MainWindowViewModel ViewModel { get; } = new();

    public MainWindow()
    {
        InitializeComponent();
        Title = ViewModel.WindowTitle;
        ViewModel.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName is nameof(MainWindowViewModel.WindowTitle))
            {
                Title = ViewModel.WindowTitle;
            }
        };

        RootGrid.Loaded += RootGrid_Loaded;
        Closed += MainWindow_Closed;
    }

    private async void RootGrid_Loaded(object sender, RoutedEventArgs e)
    {
        RootGrid.Loaded -= RootGrid_Loaded;

        try
        {
            canvasHost = new WebViewCanvasHost(CanvasWebView);
            canvasHost.MessageReceived += CanvasHost_MessageReceived;
            canvasHost.MessageRejected += (_, reason) => ViewModel.StatusText = reason;
            canvasHost.ExternalNavigationBlocked += (_, uri) =>
                ViewModel.StatusText = $"Blocked external navigation: {uri.Host}";

            string contentRoot = Path.Combine(AppContext.BaseDirectory, "CanvasContent");
            await canvasHost.InitializeAsync(contentRoot);
        }
        catch (Exception exception)
        {
            ViewModel.StatusText = $"Canvas startup failed: {exception.Message}";
        }
    }

    private async void OpenButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            FileOpenPicker picker = new()
            {
                SuggestedStartLocation = PickerLocationId.DocumentsLibrary,
                ViewMode = PickerViewMode.List,
            };
            picker.FileTypeFilter.Add(".excalidraw");
            picker.FileTypeFilter.Add(".json");

            nint windowHandle = WinRT.Interop.WindowNative.GetWindowHandle(this);
            WinRT.Interop.InitializeWithWindow.Initialize(picker, windowHandle);

            StorageFile? file = await picker.PickSingleFileAsync();
            if (file is null)
            {
                return;
            }

            string json = await File.ReadAllTextAsync(file.Path);
            ExcalidrawDocument document = ExcalidrawDocument.Parse(json);

            canvasHost?.Send(BridgeMessage.Create(
                BridgeEvents.OpenDocument,
                new
                {
                    document = document.Root,
                    fileName = file.Name,
                }));

            currentDocumentPath = file.Path;
            ViewModel.DocumentName = file.Name;
            ViewModel.IsDirty = false;
            ViewModel.StatusText = "Document opened";
            SaveButton.IsEnabled = true;
        }
        catch (Exception exception)
        {
            ViewModel.StatusText = $"Open failed: {exception.Message}";
        }
    }

    private async void SaveButton_Click(object sender, RoutedEventArgs e)
    {
        if (canvasHost is null || currentDocumentPath is null)
        {
            return;
        }

        BridgeMessage request = BridgeMessage.Create(BridgeEvents.RequestSnapshot, new { });
        TaskCompletionSource<BridgeMessage> responseSource = new(
            TaskCreationOptions.RunContinuationsAsynchronously);
        pendingResponses.Add(request.MessageId, responseSource);

        try
        {
            ViewModel.StatusText = "Saving…";
            canvasHost.Send(request);

            BridgeMessage response = await responseSource.Task.WaitAsync(TimeSpan.FromSeconds(10));
            if (!response.Payload.TryGetProperty("document", out JsonElement documentElement))
            {
                throw new JsonException("The canvas response did not contain a document.");
            }

            ExcalidrawDocument document = ExcalidrawDocument.Parse(documentElement.GetRawText());
            await documentStore.WriteTextAsync(currentDocumentPath, document.ToJson());

            ViewModel.IsDirty = false;
            ViewModel.StatusText = "Saved";
        }
        catch (Exception exception)
        {
            ViewModel.StatusText = $"Save failed: {exception.Message}";
        }
        finally
        {
            pendingResponses.Remove(request.MessageId);
        }
    }

    private void CanvasHost_MessageReceived(object? sender, BridgeMessage message)
    {
        switch (message.EventName)
        {
            case BridgeEvents.CanvasReady:
                ViewModel.IsCanvasReady = true;
                ViewModel.StatusText = "Canvas bridge ready";
                OpenButton.IsEnabled = true;
                break;

            case BridgeEvents.DocumentChanged:
                if (message.Payload.TryGetProperty("isDirty", out JsonElement isDirty) &&
                    isDirty.ValueKind is JsonValueKind.True or JsonValueKind.False)
                {
                    ViewModel.IsDirty = isDirty.GetBoolean();
                }
                break;

            case BridgeEvents.DocumentSnapshot:
                if (message.CorrelationId is not null &&
                    pendingResponses.TryGetValue(
                        message.CorrelationId,
                        out TaskCompletionSource<BridgeMessage>? snapshotSource))
                {
                    snapshotSource.TrySetResult(message);
                }
                break;

            case BridgeEvents.BridgeError:
                string error = message.Payload.TryGetProperty("message", out JsonElement errorMessage)
                    ? errorMessage.GetString() ?? "Canvas reported an error"
                    : "Canvas reported an error";
                ViewModel.StatusText = $"Canvas error: {error}";

                if (message.CorrelationId is not null &&
                    pendingResponses.TryGetValue(
                        message.CorrelationId,
                        out TaskCompletionSource<BridgeMessage>? errorSource))
                {
                    errorSource.TrySetException(new InvalidOperationException(error));
                }
                break;
        }
    }

    private void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        canvasHost?.Dispose();
    }
}
