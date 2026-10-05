//
//  ViewerLocalScripts.swift
//  ExcalidrawZ
//
//  JS bridge for session lifetime and display preferences. Scene messages
//  travel directly over the local WebSocket connection.
//

#if os(macOS)
enum ViewerLocalScripts {
    // Set before the web app mounts, so Viewer storage and controlled read-only
    // props can be configured before any state change occurs.
    static let bootstrap = "window.__excalidrawZLocalViewer = true;"

    /// Keep the audience canvas free of editor chrome. Following disables
    /// pointer input; holding the view allows panning and zooming.
    static let chromeStyle = """
    (() => {
      const style = document.createElement("style");
      style.textContent = `
        .excalidraw .layer-ui__wrapper,
        .excalidraw .App-menu_top,
        .excalidraw .App-bottom-bar,
        .excalidraw .welcome-screen-center {
          display: none !important;
        }
        html.excalidrawz-viewer-inert body {
          pointer-events: none;
        }
      `;
      document.head.appendChild(style);
      document.documentElement.classList.add("excalidrawz-viewer-inert");
    })();
    """

    static let isSupported = """
    const helper = window.excalidrawZHelper;
    return helper?.localViewerProtocolVersion === 1 &&
      typeof helper.startLocalViewerSession === "function" &&
      typeof helper.setLocalViewerFollowing === "function" &&
      typeof helper.stopLocalViewerSession === "function";
    """

    static let start = """
    const helper = window.excalidrawZHelper;
    window.__excalidrawZNativeViewerSession = sessionId;
    let timer;
    try {
      await Promise.race([
        helper.startLocalViewerSession({
          role, sessionId, transportURL, followCamera,
          ...(role === "viewer" ? {
            pointerAppearance: { visible: pointerVisible, color: pointerColor }
          } : {})
        }),
        new Promise((_, reject) => {
          timer = setTimeout(() => reject(new Error("Local Viewer connection timed out")), 8000);
        }),
      ]);
      return true;
    } finally {
      clearTimeout(timer);
    }
    """

    static let setFollowing = """
    if (window.__excalidrawZNativeViewerSession !== sessionId) return false;
    window.excalidrawZHelper.setLocalViewerFollowing(enabled);
    document.documentElement.classList.toggle("excalidrawz-viewer-inert", enabled);
    return true;
    """

    static let supportsPointerAppearance = """
    return typeof window.excalidrawZHelper?.setLocalViewerPointerAppearance === "function";
    """

    static let supportsPresentationReadiness = """
    return typeof window.excalidrawZHelper?.waitForLocalViewerReady === "function";
    """

    /// The helper resolves after the current session's initial snapshot,
    /// resources and camera have been applied and the first frame has painted.
    static let waitUntilReady = """
    if (window.__excalidrawZNativeViewerSession !== sessionId) {
      throw new Error("Local Viewer session was superseded");
    }
    let timer;
    try {
      await Promise.race([
        window.excalidrawZHelper.waitForLocalViewerReady({ sessionId }),
        new Promise((_, reject) => {
          timer = setTimeout(() => reject(new Error("Local Viewer presentation timed out")), 8000);
        }),
      ]);
      if (window.__excalidrawZNativeViewerSession !== sessionId) {
        throw new Error("Local Viewer session was superseded");
      }
      return true;
    } finally {
      clearTimeout(timer);
    }
    """

    static let setPointerAppearance = """
    if (window.__excalidrawZNativeViewerSession !== sessionId) return false;
    const helper = window.excalidrawZHelper;
    if (typeof helper?.setLocalViewerPointerAppearance !== "function") return false;
    helper.setLocalViewerPointerAppearance({ sessionId, visible, color });
    return true;
    """

    static let stop = """
    window.excalidrawZHelper?.stopLocalViewerSession?.(sessionId);
    if (window.__excalidrawZNativeViewerSession === sessionId) {
      delete window.__excalidrawZNativeViewerSession;
    }
    return true;
    """
}
#endif
