namespace ExcalidrawZ.Domain.Documents;

public interface IAtomicDocumentStore
{
    Task WriteAsync(
        string destinationPath,
        ReadOnlyMemory<byte> content,
        CancellationToken cancellationToken = default);
}
