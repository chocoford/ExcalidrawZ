using System.Text;
using ExcalidrawZ.Domain.Documents;

namespace ExcalidrawZ.Storage.Documents;

/// <summary>
/// Writes a complete document to a sibling temporary file, flushes it to disk,
/// and only then replaces the destination.
/// </summary>
public sealed class AtomicFileDocumentStore : IAtomicDocumentStore
{
    public async Task WriteAsync(
        string destinationPath,
        ReadOnlyMemory<byte> content,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(destinationPath);

        string fullDestinationPath = Path.GetFullPath(destinationPath);
        string? directoryPath = Path.GetDirectoryName(fullDestinationPath);
        if (string.IsNullOrEmpty(directoryPath))
        {
            throw new ArgumentException("The destination must have a parent directory.", nameof(destinationPath));
        }

        Directory.CreateDirectory(directoryPath);

        string temporaryPath = Path.Combine(
            directoryPath,
            $".{Path.GetFileName(fullDestinationPath)}.{Guid.NewGuid():N}.tmp");

        try
        {
            await using (FileStream stream = new(temporaryPath, new FileStreamOptions
            {
                Access = FileAccess.Write,
                BufferSize = 64 * 1024,
                Mode = FileMode.CreateNew,
                Options = FileOptions.Asynchronous | FileOptions.WriteThrough,
                Share = FileShare.None,
            }))
            {
                await stream.WriteAsync(content, cancellationToken);
                await stream.FlushAsync(cancellationToken);
                stream.Flush(flushToDisk: true);
            }

            cancellationToken.ThrowIfCancellationRequested();
            ReplaceDestination(temporaryPath, fullDestinationPath);
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }
    }

    public Task WriteTextAsync(
        string destinationPath,
        string content,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(content);
        return WriteAsync(destinationPath, Encoding.UTF8.GetBytes(content), cancellationToken);
    }

    private static void ReplaceDestination(string temporaryPath, string destinationPath)
    {
        if (File.Exists(destinationPath))
        {
            File.Replace(
                temporaryPath,
                destinationPath,
                destinationBackupFileName: null,
                ignoreMetadataErrors: true);
            return;
        }

        try
        {
            File.Move(temporaryPath, destinationPath);
        }
        catch (IOException) when (File.Exists(destinationPath))
        {
            // Another writer won the create race. Replace that complete file rather
            // than exposing a partially-written destination.
            File.Replace(
                temporaryPath,
                destinationPath,
                destinationBackupFileName: null,
                ignoreMetadataErrors: true);
        }
    }
}
