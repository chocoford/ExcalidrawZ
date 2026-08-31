using System.Text;
using ExcalidrawZ.Storage.Documents;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace ExcalidrawZ.Storage.Tests;

[TestClass]
public sealed class AtomicFileDocumentStoreTests
{
    [TestMethod]
    public async Task WriteAsync_CreatesNewDocument()
    {
        using TemporaryDirectory directory = new();
        string destinationPath = Path.Combine(directory.Path, "drawing.excalidraw");
        AtomicFileDocumentStore store = new();

        await store.WriteAsync(destinationPath, Encoding.UTF8.GetBytes("{\"elements\":[]}"));

        Assert.AreEqual("{\"elements\":[]}", await File.ReadAllTextAsync(destinationPath));
        Assert.AreEqual(0, Directory.GetFiles(directory.Path, "*.tmp").Length);
    }

    [TestMethod]
    public async Task WriteAsync_ReplacesExistingDocument()
    {
        using TemporaryDirectory directory = new();
        string destinationPath = Path.Combine(directory.Path, "drawing.excalidraw");
        await File.WriteAllTextAsync(destinationPath, "old");
        AtomicFileDocumentStore store = new();

        await store.WriteAsync(destinationPath, Encoding.UTF8.GetBytes("new"));

        Assert.AreEqual("new", await File.ReadAllTextAsync(destinationPath));
        Assert.AreEqual(0, Directory.GetFiles(directory.Path, "*.tmp").Length);
    }

    private sealed class TemporaryDirectory : IDisposable
    {
        public TemporaryDirectory()
        {
            Path = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(),
                $"ExcalidrawZ.Tests.{Guid.NewGuid():N}");
            Directory.CreateDirectory(Path);
        }

        public string Path { get; }

        public void Dispose()
        {
            if (Directory.Exists(Path))
            {
                Directory.Delete(Path, recursive: true);
            }
        }
    }
}
