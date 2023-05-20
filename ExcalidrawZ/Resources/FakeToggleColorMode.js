 (() => {
     var event = new KeyboardEvent("keydown", {
     keyCode: 68,
     key: "D",
     code: "D",
     altKey: true,
     shiftKey: true
     });
     
     document.querySelector(".excalidraw-container").dispatchEvent(event);
 })();
