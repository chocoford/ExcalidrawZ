//
//  ViewerMirrorScripts.swift
//  ExcalidrawZ
//
//  JavaScript used to mirror the editor scene into the read-only Viewer window.
//  Kept in one place so it can be moved into the Excalidraw fork later.
//

#if os(macOS)
import Foundation

enum ViewerMirrorScripts {
    /// Hides every piece of Excalidraw UI in the Viewer. While following the
    /// editor the page is also inert (`excalidrawz-viewer-inert`); when the
    /// presenter holds the view, pan/zoom gestures are allowed through.
    /// Injected as a user script at document end.
    static let viewerChromeStyle = """
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

    /// Toggles whether the Viewer accepts pointer input.
    ///
    /// Arguments: `inert: Bool`.
    static let viewerSetInert = """
    document.documentElement.classList.toggle("excalidrawz-viewer-inert", inert);
    return true;
    """

    /// Puts the Viewer page into view + zen mode and stops it from reporting
    /// `onStateChanged` to Swift, so nothing the mirror does is ever persisted.
    static let viewerPrepare = """
    const helper = window.excalidrawZHelper;
    if (!helper || !helper._api) {
        throw new Error("viewerPrepare: excalidrawAPI not ready");
    }
    if (!window.__excalidrawZViewerMirror) {
        window.__excalidrawZViewerMirror = { generation: -1 };
        helper._beginStateChangeSuppression?.();
    }
    helper.setCanvasPreferences({ viewModeEnabled: true, zenModeEnabled: true });
    return true;
    """

    /// Installs (idempotently) a scene-change subscription in the editor page.
    /// It posts a single `onViewerMirrorDirty` message per sync cycle; the
    /// flag is reset by `editorTakeDelta`.
    static let editorSubscribe = """
    const api = window.excalidrawZHelper?._api;
    if (!api || typeof api.onChange !== "function") {
        throw new Error("editorSubscribe: excalidrawAPI not ready");
    }
    if (window.__excalidrawZViewerMirror) {
        return false;
    }
    const state = {
        generation: 0,
        versions: new Map(),
        sentFileIds: new Set(),
        lastPrefsKey: null,
        lastCameraKey: null,
        notified: false,
    };
    window.__excalidrawZViewerMirror = state;
    api.onChange(() => {
        if (state.notified) {
            return;
        }
        state.notified = true;
        window.webkit?.messageHandlers?.excalidrawZ?.postMessage({
            event: "onViewerMirrorDirty",
            data: null,
        });
    });
    return true;
    """

    /// Computes what changed in the editor scene since the previous call and
    /// returns it as a JSON string, or `null` when nothing changed.
    ///
    /// Elements are diffed by `version:versionNonce`, the same key Excalidraw
    /// uses for collaboration reconciliation. Deletions are soft (`isDeleted`)
    /// so they travel as normal element updates; ids that vanish entirely
    /// (e.g. a file switch) are reported in `removedIds`. Binary files are sent
    /// once per generation. `full` resets all tracking and sends the whole scene.
    ///
    /// Arguments: `full: Bool`.
    static let editorTakeDelta = """
    const api = window.excalidrawZHelper?._api;
    const state = window.__excalidrawZViewerMirror;
    if (!api || !state) {
        throw new Error("editorTakeDelta: mirror subscription not installed");
    }
    state.notified = false;
    if (full) {
        state.generation += 1;
        state.versions = new Map();
        state.sentFileIds = new Set();
        state.lastPrefsKey = null;
        state.lastCameraKey = null;
    }

    const all = api.getSceneElementsIncludingDeleted();
    const elements = [];
    const seen = new Set();
    for (const element of all) {
        seen.add(element.id);
        const key = `${element.version}:${element.versionNonce}`;
        if (state.versions.get(element.id) === key) {
            continue;
        }
        state.versions.set(element.id, key);
        if (!full || !element.isDeleted) {
            elements.push(element);
        }
    }
    const removedIds = [];
    for (const id of Array.from(state.versions.keys())) {
        if (!seen.has(id)) {
            removedIds.push(id);
            state.versions.delete(id);
        }
    }

    const liveFiles = typeof api.getFiles === "function" ? api.getFiles() : {};
    const files = {};
    for (const element of all) {
        const fileId = element.fileId;
        if (!fileId || element.isDeleted || state.sentFileIds.has(fileId)) {
            continue;
        }
        const file = liveFiles[fileId];
        if (file) {
            files[fileId] = file;
            state.sentFileIds.add(fileId);
        }
    }

    const appState = api.getAppState();
    const prefs = {
        theme: appState.theme,
        viewBackgroundColor: appState.viewBackgroundColor,
        gridModeEnabled: !!appState.gridModeEnabled,
    };
    const prefsKey = JSON.stringify(prefs);
    const prefsChanged = prefsKey !== state.lastPrefsKey;
    state.lastPrefsKey = prefsKey;

    const camera = {
        scrollX: appState.scrollX,
        scrollY: appState.scrollY,
        zoom: appState.zoom.value,
        width: appState.width,
        height: appState.height,
    };
    const cameraKey = JSON.stringify(camera);
    const cameraChanged = cameraKey !== state.lastCameraKey;
    state.lastCameraKey = cameraKey;

    if (
        !full &&
        elements.length === 0 &&
        removedIds.length === 0 &&
        Object.keys(files).length === 0 &&
        !prefsChanged &&
        !cameraChanged
    ) {
        return null;
    }
    return JSON.stringify({
        generation: state.generation,
        full,
        elements,
        removedIds,
        files,
        prefs: prefsChanged ? prefs : null,
        camera: cameraChanged ? camera : null,
    });
    """

    /// Applies a delta produced by `editorTakeDelta` to the Viewer scene.
    /// Returns `"resync"` when the delta belongs to a generation the Viewer has
    /// not seen, which tells Swift to request a full delta.
    ///
    /// Arguments: `payload: String`, `followCamera: Bool`.
    static let viewerApplyDelta = """
    const api = window.excalidrawZHelper?._api;
    const state = window.__excalidrawZViewerMirror;
    if (!api || !state) {
        throw new Error("viewerApplyDelta: viewer not prepared");
    }
    const delta = JSON.parse(payload);
    if (!delta.full && delta.generation !== state.generation) {
        return "resync";
    }
    state.generation = delta.generation;

    const fileList = Object.values(delta.files || {});
    if (fileList.length > 0) {
        api.addFiles(fileList);
    }

    if (delta.full || delta.elements.length > 0 || delta.removedIds.length > 0) {
        let next;
        if (delta.full) {
            next = delta.elements;
        } else {
            const byId = new Map(
                api.getSceneElementsIncludingDeleted().map((element) => [element.id, element]),
            );
            for (const element of delta.elements) {
                byId.set(element.id, element);
            }
            for (const id of delta.removedIds) {
                byId.delete(id);
            }
            next = Array.from(byId.values());
        }
        // Element order is z-order; Excalidraw does not re-sort by fractional
        // index on updateScene, so restore it here.
        next.sort((a, b) => (a.index < b.index ? -1 : a.index > b.index ? 1 : 0));
        api.updateScene({ elements: next, captureUpdate: "NEVER" });
    }

    const appStateUpdate = {};
    if (delta.prefs) {
        Object.assign(appStateUpdate, delta.prefs);
    }
    if (followCamera && delta.camera) {
        // The Viewer window rarely matches the editor's size, so instead of
        // copying scroll/zoom verbatim, show the same scene rectangle the
        // editor shows, scaled to fit (letterboxed) and centred.
        const source = delta.camera;
        const target = api.getAppState();
        const targetWidth = Number(target.width) || window.innerWidth;
        const targetHeight = Number(target.height) || window.innerHeight;
        const sceneWidth = Math.max(source.width / source.zoom, 1);
        const sceneHeight = Math.max(source.height / source.zoom, 1);
        const sceneCenterX = -source.scrollX + sceneWidth / 2;
        const sceneCenterY = -source.scrollY + sceneHeight / 2;
        const zoom = Math.min(targetWidth / sceneWidth, targetHeight / sceneHeight);
        appStateUpdate.scrollX = targetWidth / 2 / zoom - sceneCenterX;
        appStateUpdate.scrollY = targetHeight / 2 / zoom - sceneCenterY;
        appStateUpdate.zoom = { value: zoom };
    }
    if (Object.keys(appStateUpdate).length > 0) {
        api.updateScene({ appState: appStateUpdate, captureUpdate: "NEVER" });
    }
    return "applied";
    """
}
#endif
