using CommunityToolkit.Mvvm.ComponentModel;

namespace ExcalidrawZ.App.ViewModels;

public sealed class MainWindowViewModel : ObservableObject
{
    private string documentName = "No document";
    private string statusText = "Starting WebView2…";
    private bool isCanvasReady;
    private bool isDirty;

    public string DocumentName
    {
        get => documentName;
        set
        {
            if (SetProperty(ref documentName, value))
            {
                OnPropertyChanged(nameof(WindowTitle));
            }
        }
    }

    public string StatusText
    {
        get => statusText;
        set => SetProperty(ref statusText, value);
    }

    public bool IsCanvasReady
    {
        get => isCanvasReady;
        set => SetProperty(ref isCanvasReady, value);
    }

    public bool IsDirty
    {
        get => isDirty;
        set
        {
            if (SetProperty(ref isDirty, value))
            {
                OnPropertyChanged(nameof(WindowTitle));
            }
        }
    }

    public string WindowTitle => IsDirty
        ? $"{DocumentName} * — ExcalidrawZ"
        : $"{DocumentName} — ExcalidrawZ";
}
