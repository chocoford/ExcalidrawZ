# ExcalidrawZ for Windows

This directory contains the native Windows implementation of ExcalidrawZ.

The Windows app is a new client, not a port of the existing Swift code. It may
use the Apple app as a behavioral reference, but Windows UI, persistence,
platform integration, and application lifecycle code are implemented
independently in C#.

## Status

Technical prototype scaffolding is in progress. The solution now contains the
initial App, Domain, Storage, and Canvas boundaries, a versioned bridge contract,
an atomic file writer, and contract tests. The current WebView content is a
temporary bridge harness rather than the Excalidraw runtime.

The App project is temporarily configured for unpackaged launch so its source
can be prepared without generating binary MSIX assets on macOS. Moving it onto
the official packaged WinUI template remains a required first-milestone task and
is tracked in `WINDOWS-VALIDATION.md`.

## Prototype Build

On Windows, install the .NET 10 SDK and the Visual Studio Windows application
development workload, then run:

```powershell
cd Windows
dotnet restore ExcalidrawZ.Windows.sln
dotnet test ExcalidrawZ.Windows.sln
dotnet run --project src/ExcalidrawZ.App/ExcalidrawZ.App.csproj -p:Platform=x64
```

Use `-p:Platform=ARM64` for the ARM64 target. Until the Excalidraw bundle is
connected, the app displays a local JSON editor used to exercise the trusted
WebView2 origin, versioned bridge, file picker, and atomic save path.

## Product Direction

The Windows app should preserve the main ExcalidrawZ product model:

- a native desktop shell around the Excalidraw canvas;
- My Files, groups, recent files, and file history;
- direct access to local files and linked folders;
- linked cloud storage providers;
- collaboration, presentations, AI, and MCP integration;
- Windows-native keyboard, mouse, drag-and-drop, windowing, and file handling.

The goal is not strict source-level parity with the Apple client. Features
should follow Windows conventions while preserving compatible document formats
and user-visible behavior.

## Technical Baseline

- **Language:** C# on the current .NET LTS release
- **UI:** WinUI 3 with the Windows App SDK
- **Canvas host:** Microsoft Edge WebView2 using the Evergreen Runtime
- **Application pattern:** MVVM with `CommunityToolkit.Mvvm`
- **Metadata database:** SQLite through Entity Framework Core
- **Document storage:** regular files, separate from the metadata database
- **Packaging:** MSIX, suitable for Microsoft Store and signed direct installs
- **Initial target:** Windows 11 on x64 and ARM64

WinUI 3 is the native UI layer. WebView2 is used only for the Excalidraw canvas
and other web content that is already part of the Excalidraw runtime. The app
shell, sidebar, settings, dialogs, menus, file management, and system
integrations should remain native WinUI.

## Repository Layout

The intended solution structure is:

```text
Windows/
  ExcalidrawZ.Windows.sln
  src/
    ExcalidrawZ.App/          WinUI views, app lifecycle, and composition
    ExcalidrawZ.Domain/       Documents, groups, history, and domain services
    ExcalidrawZ.Storage/      SQLite, filesystem, credentials, and providers
    ExcalidrawZ.Canvas/       WebView2 host and native/JavaScript bridge
  tests/
    ExcalidrawZ.Domain.Tests/
    ExcalidrawZ.Storage.Tests/
    ExcalidrawZ.Canvas.Tests/
```

Keep the project split small while the first prototype is being validated.
Additional projects should only be introduced when a real ownership or testing
boundary requires them.

## Shared Assets and Contracts

The Windows and Apple clients do not share native application code. They may
share or consume the following platform-neutral artifacts:

- the Excalidraw web bundle;
- `.excalidraw` document compatibility rules;
- native/JavaScript bridge schemas;
- cloud service API contracts;
- MCP tool schemas and prompts;
- localization source strings, visual assets, and test fixtures;
- server-side collaboration, AI, and OAuth services.

Shared artifacts should eventually live under a repository-level `Shared/`
directory. Do not move existing Apple resources until the Windows prototype
establishes an actual shared build requirement.

## Canvas Bridge

The WebView2 bridge replaces the Apple client's `WKWebView` host. Communication
must use versioned, structured JSON messages:

- JavaScript to native: `WebMessageReceived`
- native to JavaScript: `PostWebMessageAsJson`

The host must validate the message version, event name, payload, and source
origin. External navigation and unintended `file:` navigation should be blocked
at `NavigationStarting` unless explicitly handled by the application.

Avoid building a second ad hoc bridge around `ExecuteScriptAsync`. Script
execution may be used for bootstrap compatibility, but application commands and
events should use the structured message channel.

## My Files and Persistence

My Files remains a core Windows feature. Only its Apple-specific implementation
is replaced.

SQLite stores structured metadata such as:

- groups and document records;
- recent-item state and sorting;
- checkpoint indexes;
- linked-storage accounts and locations;
- presentation metadata;
- AI conversation metadata.

Large or user-recoverable content stays in the filesystem:

```text
ExcalidrawZ/
  workspace.db
  documents/<document-id>.excalidraw
  media/<media-id>
  checkpoints/<document-id>/<checkpoint-id>.excalidraw
  covers/<document-id>.webp
```

Document writes must be atomic. Storage code should use temporary-file writes,
flush the completed content, and then replace the destination. File history and
external-change handling must be designed before autosave is enabled broadly.

Database migrations must be explicit, versioned, and covered by migration
tests. Document contents and media should not be stored as large SQLite blobs by
default.

## Linked Storage

The provider layer should not depend on WinUI views. Define provider-neutral
operations for browsing, downloading, uploading, moving, deleting, refreshing,
and conflict reporting.

Expected providers include:

- local linked folders;
- OneDrive;
- Dropbox;
- WebDAV.

iCloud is not a first-class Windows backend. If iCloud for Windows exposes an
iCloud Drive directory, users may link that directory as a normal local folder.
The Apple client's private CloudKit-backed My Files database is not part of the
initial Windows scope.

OAuth refresh tokens and other secrets must be stored with Windows credential
protection rather than in SQLite or plain configuration files.

## First Milestone

The first milestone is a technical prototype, not a feature-complete app. It
should prove that the selected stack works before the persistence model and full
UI are built.

1. Create a packaged WinUI 3 application.
2. Load the bundled Excalidraw runtime in WebView2.
3. Establish a versioned JSON bridge in both directions.
4. Open one `.excalidraw` file from the Windows file picker.
5. Edit and atomically save that file.
6. Validate Chinese and English IME input.
7. Validate mouse, pen, keyboard shortcuts, clipboard, and drag-and-drop.
8. Measure startup time, idle memory, large-file loading, and WebView recovery.
9. Add bridge contract tests using fixed request and response fixtures.

Do not begin the full My Files implementation until this milestone is stable.

## Initial Non-Goals

The technical prototype does not need:

- CloudKit or transparent Apple My Files synchronization;
- complete feature parity with macOS and iPadOS;
- screen annotation;
- Store entitlement sharing with Apple purchases;
- every cloud provider;
- Android abstractions or a cross-platform UI framework.

These exclusions keep the first iteration focused on the risks unique to the
Windows client: WebView2 integration, native input, file correctness, and the
application architecture.

## Engineering Principles

- Prefer Windows-native controls and system behavior outside the canvas.
- Keep domain and persistence logic independent from WinUI views.
- Treat the bridge as a public, versioned contract.
- Keep user drawings recoverable without requiring the database to be healthy.
- Use structured parsers and serializers rather than manipulating JSON strings.
- Add abstractions only when they represent a real platform or ownership
  boundary.
- Preserve `.excalidraw` compatibility and avoid private format extensions unless
  they are optional and documented.

## References

- [WinUI 3](https://learn.microsoft.com/windows/apps/winui/winui3/)
- [Windows App SDK](https://learn.microsoft.com/windows/apps/windows-app-sdk/)
- [WebView2 in WinUI 3](https://learn.microsoft.com/windows/apps/develop/ui/controls/webview2)
- [MVVM Toolkit](https://learn.microsoft.com/dotnet/communitytoolkit/mvvm/)
- [SQLite in Windows apps](https://learn.microsoft.com/windows/apps/develop/data-access/sqlite-data-access)
- [MSIX packaging and publishing](https://learn.microsoft.com/windows/apps/package-and-deploy/publish-first-app)
