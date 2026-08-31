using System.Text.Json;
using ExcalidrawZ.Domain.Documents;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace ExcalidrawZ.Domain.Tests;

[TestClass]
public sealed class ExcalidrawDocumentTests
{
    [TestMethod]
    public void Parse_PreservesUnknownProperties()
    {
        const string Json = """
            {
              "type": "excalidraw",
              "elements": [],
              "appState": {},
              "files": {},
              "futureProperty": { "enabled": true }
            }
            """;

        ExcalidrawDocument document = ExcalidrawDocument.Parse(Json);

        Assert.IsTrue(document.Root.TryGetProperty("futureProperty", out JsonElement futureProperty));
        Assert.IsTrue(futureProperty.GetProperty("enabled").GetBoolean());
    }

    [TestMethod]
    public void Parse_RejectsArrayRoot()
    {
        Assert.ThrowsExactly<JsonException>(() => ExcalidrawDocument.Parse("[]"));
    }

    [TestMethod]
    public void Parse_RejectsInvalidKnownPropertyKind()
    {
        const string Json = """{ "type": "excalidraw", "elements": {} }""";

        Assert.ThrowsExactly<JsonException>(() => ExcalidrawDocument.Parse(Json));
    }
}
