/**
 *
 * @param {number[]} buffer
 */
const loadFile = (buffer) => {
    stopWatchState();
    const uint8Array = new Uint8Array(buffer);
    const file = new File([uint8Array], "file.excalidraw", {
    lastModified: new Date().getTime(),
    type: "",
    });
    
    function FakeDataTransfer(file) {
        this.dropEffect = "all";
        this.effectAllowed = "all";
        this.items = [{ getAsFileSystemHandle: async () => null }];
        this.types = ["Files"];
        this.getData = function () {
            return file;
        };
        this.files = {
        item: () => {
            return file;
        },
        };
    }
    
    const fakeDropEvent = new DragEvent("drop", { bubbles: true });
    fakeDropEvent.simulated = true;
    Object.defineProperty(fakeDropEvent, "dataTransfer", {
    value: new FakeDataTransfer(file),
    });
    
    const excalidrawContainer = document.querySelector(".excalidraw-container");
    if (!excalidrawContainer) return;
    excalidrawContainer.dispatchEvent(fakeDropEvent);
    startWatchState();
};

const saveFile = () => {
    const data = localStorage.getItem("excalidraw");
    try {
        // data = JSON.parse(data);
        sendMessage({
        event: "saveFileDone",
            data,
        });
    } catch {}
};

const downloadFile = () => {
    document.dispatchEvent(
                           new KeyboardEvent("keydown", {
                           key: "s",
                           code: "KeyS",
                           altKey: false,
                           shiftKey: false,
                           metaKey: true,
                           composed: true,
                           keyCode: 83,
                           which: 83,
                           }),
                           );
};

/**
 *
 * @param {'dark' | 'light' | undefined} theme
 */
const toggleColorTheme = (theme = undefined) => {
    if (document.documentElement.classList.contains(theme)) {
        return;
    }
    document.dispatchEvent(
                           new KeyboardEvent("keydown", {
                           key: "Î",
                           code: "KeyD",
                           altKey: true,
                           shiftKey: true,
                           composed: true,
                           keyCode: 68,
                           which: 68,
                           }),
                           );
};

/**
 *
 * @param {'png' | 'svg'} type
 */
const exportImage = (type = "png") => {
    document.dispatchEvent(
                           new KeyboardEvent("keydown", {
                           key: "e",
                           code: "KeyE",
                           metaKey: true,
                           shiftKey: true,
                           composed: true,
                           keyCode: 69,
                           which: 69,
                           }),
                           );
    setTimeout(() => {
        const modalContainer = document.querySelector(
                                                      ".excalidraw-modal-container",
                                                      );
        modalContainer.querySelector('button[aria-label="Export to PNG"]').click();
        modalContainer.querySelector('button[aria-label="Close"]').click();
    }, 100);
};

const startWatchState = () => {
    clearInterval(window.excalidrawZHelper.watcher);
    let lastVersion = "";
    window.excalidrawZHelper.watcher = setInterval(() => {
        const data = localStorage.getItem("excalidraw");
        let state = localStorage.getItem("excalidraw-state");
        const version = localStorage.getItem("version-files");
        if (lastVersion === version) {
            return;
        }
        // try {
        //   state = JSON.parse(state);
        //   // data = JSON.parse(data);
        //   sendMessage({
        //     event: "onStateChanged",
        //     data: {
        //       state,
        //       data,
        //     },
        //   });
        // } catch {}
        downloadFile();
        lastVersion = version;
    }, 2000);
};

const stopWatchState = () => {
    clearInterval(window.excalidrawZHelper.watcher);
};

const sendMessage = ({ event, data }) => {
    console.info("sendMessage", { event, data });
    if (
        window.webkit &&
        window.webkit.messageHandlers &&
        window.webkit.messageHandlers.excalidrawZ
        ) {
            window.webkit.messageHandlers.excalidrawZ.postMessage({
                event,
                data,
            });
        }
};

const hideEls = () => {
    const targetNode = document.body;
    // Options for the observer (which mutations to observe)
    const config = { attributes: true, childList: true, subtree: true };
    // Callback function to execute when mutations are observed
    const callback = (mutationList, observer) => {
        for (const mutation of mutationList) {
            console.log(mutation);
            if (mutation.type === "childList") {
                mutation.addedNodes.forEach((node) => {
                    if (
                        node.classList.contains("dropdown-menu-button") ||
                        node.classList.contains("welcome-screen-decor-hint--menu")
                        ) {
                            node.style.display = "none";
                        }
                    
                    if (node.classList.contains("welcome-screen-center")) {
                        node.querySelector(".welcome-screen-menu").style.display = "none";
                    }
                });
                
                if (
                    mutation.nextSibling &&
                    mutation.nextSibling.classList.contains(
                                                            "layer-ui__wrapper__footer-right",
                                                            )
                    ) {
                        mutation.nextSibling.style.display = "none";
                    }
                
                // top right
                if (
                    mutation.target.classList.contains("layer-ui__wrapper__top-right")
                    ) {
                        mutation.target.style.display = "none";
                    }
                // model container
                if (mutation.target.classList.contains("excalidraw-modal-container")) {
                    mutation.target.style.opacity = 0;
                    mutation.target.style.pointerEvents = "none";
                }
            }
        }
    };
    
    // Create an observer instance linked to the callback function
    const observer = new MutationObserver(callback);
    
    // Start observing the target node for configured mutations
    observer.observe(targetNode, config);
};

const onload = () => {
    hideEls();
};

window.addEventListener("DOMContentLoaded", onload);

window.excalidrawZHelper = {
    loadFile,
    saveFile,
    downloadFile,
    
    toggleColorTheme,
    exportImage,
getIsDark: () => document.documentElement.classList.contains("dark"),
};

0;
