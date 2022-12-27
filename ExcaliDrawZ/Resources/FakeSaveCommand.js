(() => {
  const event = new KeyboardEvent("keydown", {
    key: "s",
    metaKey: true,
    code: "KeyS",
    bubbles: true,
  });

  document.querySelector(".excalidraw-container").dispatchEvent(event);
})();
