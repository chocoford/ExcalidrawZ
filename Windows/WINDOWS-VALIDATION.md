# Windows validation checklist

This file tracks checks that cannot be completed from the macOS development host.
Do not mark an item complete based only on static review.

## Toolchain and build

- [ ] Install the current .NET 10 SDK and Visual Studio Windows application development workload.
- [ ] Run `dotnet restore ExcalidrawZ.Windows.sln`.
- [ ] Run all tests with `dotnet test ExcalidrawZ.Windows.sln`.
- [ ] Build and launch `ExcalidrawZ.App` for x64.
- [ ] Build and launch `ExcalidrawZ.App` for ARM64.
- [ ] Replace the temporary unpackaged launch configuration with the official packaged WinUI template and MSIX assets.

## Canvas host and security

- [ ] Confirm the Evergreen WebView2 Runtime availability check and missing-runtime UX.
- [ ] Confirm `https://appassets.excalidrawz.local/` loads from packaged content.
- [ ] Confirm HTTP, external HTTPS, `file:`, popup, and redirect navigation cannot escape the trusted origin.
- [ ] Confirm malformed, wrong-version, wrong-direction, and wrong-origin bridge messages are rejected.
- [ ] Connect the bundled Excalidraw runtime in place of the bridge harness.

## File correctness

- [ ] Open a real `.excalidraw` file with the Windows picker.
- [ ] Edit and save over the existing file.
- [ ] Interrupt saving and verify the previous complete file remains recoverable.
- [ ] Verify behavior on local NTFS, OneDrive-backed folders, removable media, and network shares.
- [ ] Define external-change and save-conflict UX before enabling autosave.

## Native interaction and performance

- [ ] Validate English and Chinese IME composition.
- [ ] Validate mouse, precision touchpad, touch, and pen input.
- [ ] Validate keyboard shortcuts, clipboard, and drag-and-drop.
- [ ] Measure cold/warm startup, idle memory, and large-document load time.
- [ ] Kill the WebView2 process and verify recovery without document loss.
