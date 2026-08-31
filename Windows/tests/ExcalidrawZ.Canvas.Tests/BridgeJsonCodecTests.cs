using ExcalidrawZ.Canvas.Bridge;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace ExcalidrawZ.Canvas.Tests;

[TestClass]
public sealed class BridgeJsonCodecTests
{
    [TestMethod]
    public async Task Deserialize_AcceptsVersionedFixture()
    {
        string fixturePath = Path.Combine(
            AppContext.BaseDirectory,
            "Fixtures",
            "canvas-ready.v1.json");
        string json = await File.ReadAllTextAsync(fixturePath);

        BridgeParseResult result = BridgeJsonCodec.Deserialize(
            json,
            BridgeDirection.JavaScriptToNative);

        Assert.IsTrue(result.IsSuccess, result.Error);
        BridgeMessage message = result.Message ??
            throw new AssertFailedException("The parsed bridge message was null.");
        Assert.AreEqual(BridgeEvents.CanvasReady, message.EventName);
    }

    [TestMethod]
    public void Deserialize_RejectsUnsupportedProtocolVersion()
    {
        const string Json = """
            {
              "protocolVersion": 99,
              "messageId": "8dd00a0e-a525-4b97-8176-a1c3e1ab003c",
              "event": "canvas.ready",
              "payload": {}
            }
            """;

        BridgeParseResult result = BridgeJsonCodec.Deserialize(
            Json,
            BridgeDirection.JavaScriptToNative);

        Assert.IsFalse(result.IsSuccess);
        StringAssert.Contains(result.Error ?? string.Empty, "Unsupported bridge protocol version");
    }

    [TestMethod]
    public void Deserialize_RejectsEventInWrongDirection()
    {
        const string Json = """
            {
              "protocolVersion": 1,
              "messageId": "8dd00a0e-a525-4b97-8176-a1c3e1ab003c",
              "event": "document.open",
              "payload": {}
            }
            """;

        BridgeParseResult result = BridgeJsonCodec.Deserialize(
            Json,
            BridgeDirection.JavaScriptToNative);

        Assert.IsFalse(result.IsSuccess);
        StringAssert.Contains(result.Error ?? string.Empty, "not allowed");
    }

    [TestMethod]
    public void Deserialize_RejectsUnknownEnvelopeProperty()
    {
        const string Json = """
            {
              "protocolVersion": 1,
              "messageId": "8dd00a0e-a525-4b97-8176-a1c3e1ab003c",
              "event": "canvas.ready",
              "payload": {},
              "unexpected": true
            }
            """;

        BridgeParseResult result = BridgeJsonCodec.Deserialize(
            Json,
            BridgeDirection.JavaScriptToNative);

        Assert.IsFalse(result.IsSuccess);
    }

    [TestMethod]
    public void Deserialize_RejectsInvalidEventPayload()
    {
        const string Json = """
            {
              "protocolVersion": 1,
              "messageId": "8dd00a0e-a525-4b97-8176-a1c3e1ab003c",
              "event": "document.changed",
              "payload": { "isDirty": "yes" }
            }
            """;

        BridgeParseResult result = BridgeJsonCodec.Deserialize(
            Json,
            BridgeDirection.JavaScriptToNative);

        Assert.IsFalse(result.IsSuccess);
        StringAssert.Contains(result.Error ?? string.Empty, "must be a boolean");
    }

    [TestMethod]
    public void Serialize_ProducesNativeToJavaScriptMessage()
    {
        BridgeMessage message = BridgeMessage.Create(
            BridgeEvents.RequestSnapshot,
            new { reason = "user-save" });

        string json = BridgeJsonCodec.Serialize(message, BridgeDirection.NativeToJavaScript);

        StringAssert.Contains(json, "\"protocolVersion\":1");
        StringAssert.Contains(json, "\"event\":\"document.requestSnapshot\"");
    }
}
