## 2.2.9

#### Bug fixed

- Fixed permission errors and incomplete moves when moving drawings or folders between levels of a Linked Folder.
- Fixed moved local files remaining as unavailable entries in the Sidebar until a later refresh.
- Fixed the Move to menu being unavailable from Home and missing the Linked Folder root as a destination.
- Fixed active local drawings losing their folder context after being moved.

## 2.2.8

#### Features

- Redesigned Media Files as a responsive image gallery with faster thumbnails and a dedicated detail inspector.
- Added an interactive media cleanup workflow that identifies orphaned media, items used only by File History, and media attached to files in Trash. Destructive cleanup actions show the affected media, files, and checkpoints before confirmation.

#### Optimizations

- Improved file opening and switching so interrupted or overlapping loads resolve more reliably, with clearer recovery and a retry action when a drawing cannot be loaded.
- Improved Home and File Home transitions by keeping the destination state synchronized and preparing off-screen file cards before returning from the editor.
- Improved Media Files references so related drawings can be opened directly and unavailable or trashed source files are clearly identified.

#### Bug fixed

- Fixed custom fonts disappearing from Settings after changing tabs or replacing fonts that had already been added.
- Fixed interrupted file transitions that could leave Home visible while a drawing was already active.
- Fixed permanently deleted files and collaboration files leaving unreferenced media behind.
- Fixed Media Cleanup checkpoint rows opening an unrelated checkpoint detail popover.

## 2.2.5

#### Bug fixed

- Fixed an issue on compact iOS layouts where creating or editing text on the canvas could immediately dismiss the text editor, preventing text input.

## 2.2.4

#### Bug fixed

- Fixed compatibility with the latest Excalidraw stroke width and pressure settings.
- Fixed cases where drawings or backups containing newer stroke data could fail to load or back up correctly.
- Fixed cases where the compact AI quick editor could leave controls misaligned after the keyboard was dismissed.
- Fixed cases where compact iOS AI Chat message rows could disappear while scrolling longer conversations.
- Fixed cases where AI proposal cards could remain visible after applying a proposal.
- Fixed Paywall to AI Usage navigation on compact iOS.
- Fixed cases where low-credit buttons could hit actor-isolation issues in App Store builds.
- Fixed compatibility with older OS versions in the animated presence helper used by collapsing UI sections.

## 2.2.3

#### Bug fixed

- Fixed compatibility with the latest Excalidraw stroke width settings, including the newer stroke width key used by recent drawing settings.
- Fixed cases where drawings or backups containing newer stroke data could fail to load or back up correctly.
- Improved support for pen pressure and stroke settings in the drawing settings panel.

## 2.2.2

#### Optimizations

- Improved Apple Pencil setup with a refreshed first-run mode picker and clearer finger interaction options.
- Improved iCloud Drive refresh for open files so remote changes are detected and applied more reliably while editing.
- Improved collaboration rooms with clearer loading guidance, better transition covers, and more reliable local cleanup.
- Improved viewport handling so each device can keep its own canvas position without syncing another device's scroll position.
- Improved sidebar behavior on iPadOS, including scrolling the active file into view more reliably.
- Improved Mermaid to Excalidraw sheet sizing on iPhone and iPad.
- Improved MCP settings on iPhone and iPad by clearly marking MCP server features as macOS-only.

#### Bug fixed

- Fixed cases where Apple Pencil tool changes could leave the toolbar showing the wrong active tool.
- Fixed cases where opening a collaboration room and returning to a normal file could leave tool actions bound to the wrong canvas.
- Fixed cases where file save paths could miss metadata updates such as modified time.
- Fixed cases where moving local files to Trash from Home did not refresh the UI immediately.
- Fixed cases where the Trash group could disappear even when it still contained files.
- Fixed cases where synced viewport state from one device could affect another device's canvas position.
- Fixed Mermaid to Excalidraw sheet width issues on iPad.

## 2.2.1

#### Optimizations

- Improved file opening and closing so returning to Home and switching between drawings feels smoother, especially when the trailing sidebar is open.
- Improved saving and loading performance for larger drawings, reducing visible pauses during everyday canvas work.
- Improved file cover generation so recent drawings, checkpoint previews, and library item previews appear more reliably without interrupting the editor.
- Improved File History previews by loading checkpoint thumbnails lazily and keeping each row easier to scan.
- Improved Home, File Home, and sidebar interactions to reduce unnecessary refreshes while files are saving or previews are updating.
- Improved Mermaid insertion on macOS with a wider edit-and-preview layout that better uses available space.

#### Bug fixed

- Fixed cases where JavaScript-side errors were not surfaced through the app toast layer.
- Fixed cases where closing a file could save the visible cover before the latest canvas viewport was persisted.
- Fixed cases where closing the last window could finish the backup task but fail to terminate the app.
- Fixed backup behavior so app termination can still back up unlocked content even when locked files exist.

## 2.2.0

#### Features

- Added MCP Services, allowing compatible MCP clients to create and edit ExcalidrawZ drawings through Basic or Optimized interaction modes.
- Added a richer Math tool with LaTeX formula editing, function graph rendering, reusable templates, and AI-assisted formula generation.
- Added custom toolbar tool ordering, with drawing tool shortcuts following the configured order.

#### Optimizations

- Improved AI and MCP canvas tools with export support, canvas image/PDF reading, canvas preference updates, file navigation, file history restore, and library-aware workflows.
- Improved SVG and math media handling so inserted formulas persist and preview more reliably across canvas, file covers, and media settings.

## 2.1.1

#### Optimizations

- Optimized the iPhone and iPad editor toolbar with quicker access to Library, Search, File History, AI, and editing controls.
- Improved iPad and iPhone mouse and trackpad handling so canvas scroll and zoom gestures are recognized more naturally.

#### Bug fixed

- Fixed a macOS toolbar rendering issue that could leave toolbar picker items empty after switching layouts.

## 2.1.0

#### Features

- Added Locked Files. Protect sensitive drawings with Touch ID or your Mac password, keep a Recovery Key for fallback access, and encrypt saved file data and checkpoints on disk.
- Locked file content is protected from AI access. AI can still help by creating proposal drawings that you can review and apply manually.
- Added AI visibility controls for each file, so you can choose whether AI can read and edit the current drawing.
- Added encrypted backups for ExcalidrawZ-managed backup snapshots.

#### Optimizations

- Added clearer Security settings for managing locked content, resetting the Recovery Key, and reviewing protected files.
- Improved AI proposal previews in chat and island mode, including repeated apply support and canvas focus after applying.
- Improved backup export and preview behavior for protected content.
- Improved local folder permission handling when previewing and opening external Excalidraw files.

#### Bug fixed

- Fixed cases where opening a file could briefly show an empty canvas.
- Fixed collaboration files repeatedly creating checkpoints after opening.
- Fixed compatibility with Excalidraw files that no longer include legacy chart metadata.
- Fixed several Settings, Share, and Whats New layout and localization issues.

## 2.0.2

#### Optimizations

- Updated the non-App Store update feed to use the new ExcalidrawZ website for future releases.

## 2.0.1

#### Optimizations

- AI features are now disabled by default and require an explicit opt-in before ExcalidrawZ sends AI requests or refreshes AI account and credits data.
- Added clearer AI privacy information in Settings, including cloud processing, what data may be sent, third-party model providers, user controls, and links to Privacy Policy and Terms of Use.
- Added an AI enable consent sheet that explains cloud AI usage and requires confirmation before turning AI features on.

## 2.0.0

#### Features

- Added AI Chat for ExcalidrawZ. You can now ask AI to understand the current canvas, edit drawings, create diagrams, adjust layouts, navigate large canvases, and use library items.
- Added image-aware AI prompts. Paste or attach images when asking AI for help, and ExcalidrawZ will choose an image-capable model when needed.
- Added prompt revision and AI revert support, so you can revise previous AI requests or revert AI-made canvas changes.
- Added AI account and usage information in Settings, including credits, recent credit activity, account identity, and model preferences.
- Added refreshed AI plans and credits with Starter, Pro, and Max tiers. Max plans unlock Extra High models.

#### Bug fixed

- Fixed cases where opening a file could briefly show an empty canvas.
- Fixed cases where AI-generated drawings could fail to save or reopen correctly.
- Fixed prompt draft loss when switching between AI chat surfaces; text and pasted images now stay in memory per conversation/file.

## 1.7.4

#### Features

- Tabbed inspector with Library, History, Search, and Canvas Preferences.
- Canvas search with in-canvas highlights and keyboard navigation.
- Canvas Preferences — per-canvas overrides for grid, zen, view mode, snapping, theme, background, selection tool, and drawing defaults.
- Lasso selection tool.
- In-app library browser — import directly from libraries.excalidraw.com without leaving the app.
- Filter and rename library items.
- Choose 1x / 2x / 3x scale on image export.

#### Optimizations

- Faster file switching — the Excalidraw scene is awaited before sync.
- Image and SVG exports use a direct return path instead of the old id-based round-trip.
- Drawing preferences are read from each file's appState, avoiding stale values from the previous file.
- Inspector auto-collapses when returning to Home.

#### Bug fixed

- Canvas and drawing preferences not refreshing on file switch.
- Race that could cause `setAvailableFonts` to run before the helper was ready.
- New/empty files misreported as "Customized" due to inherited `currentItem*` defaults.

## 1.7.3

#### Optimizations
- Optimized local folder import enumeration and security-scoped resource handling.
- Added support for Excalidraw cardinality arrowheads.

#### Bug fixed

- Fixed hidden files and hidden directories being imported when importing local folders.
- Fixed import failures from the menu bar not presenting a clear error to the user.
- Fixed automatic update preference not persisting correctly across app launches.
- Improved decoding compatibility for Excalidraw linear elements with missing fields.

## 1.7.2

#### Bug fixed

- Fix bug causing exported images to not show the latest content.

- Fix incompatibility issues with certain data formats.
- Fix issue preventing the stats panel from opening (Option + /)

## 1.7.1

#### Optimizations

- Reduced App Size
  - Optimized code and dependencies to reduce the app size by about 30%.
- Excalidraw Core Update — Improved Dark Mode Support

- Improved the Drawing Settings to support additional configuration options.
- Improve PDF export with support for orientation, paper size, and other settings.

#### Bug fixed

- Fixed an issue where the archive operation failed under certain conditions.
- Fix issue where the "Create Drawing" button wasn't displayed on iOS.

## 1.7.0

#### Features

- Improved File Storage
- Import PDF support
- Custom Drawing Settings

#### Optimizations

- Keep viewport when switching between files.
- Now the canvas viewport will not be reset after synchronous update.

## 1.6.1

Update excalidraw core.

## 1.6.0

#### Optimizations

- Completely redesigned UI
- Refined interaction details to improve the user experience
  -  drag-and-drop to move
  -  reorder files and groups,
  - double-clicking library (.lib) files to open them directly
  -  and more...
- Sidebar scroll when opening a group/folder

#### Fixes

- App froze when first launching iCloud syncing without network.
- Library shapes are not loading correctly.
- "Export All" creates empty folder.
- Repeating beep sound when moving the canvas with space + drag
- `The data could not be read because it is missing` when using arrow
- Unexpected behavior when save temporary files 
- Open temporary file without activate it.
- Recovered file not selected
- Crash during UI updates

## 1.5.1

#### Optimizations

- Optimize the loading performance of local folders.
- No longer display hidden folders.

#### Fixes

- Issue with Some Custom Fonts Not Working

## 1.5.0

#### New Features

- Custom Fonts

#### Optimizations

- Add back `hand` tool on the toolbar.

#### Fixes

- Fix some issues with the wording for operations when selecting multiple files.
- Fix the issue where the buttons on the right side of the toolbar do not display on macOS 13.

## 1.4.5

#### New Features

- The sidebar of files supports multi-selection operations.

#### Optimizations

- Collaboration is now integrated with [excalidraw.com](https://excalidraw.com).

#### Fixes

- Fix the issue of failing to open image files. 
  - `.excalidraw.png`, `.excalidraw.svg`, `png`, `svg`

## 1.4.4

#### Optimization

- Disable auto capitalization
- Optimize the loading logic for library items.
- Add shortcuts for buttons (sidebar toggle, library toggle, share...)
  - Sidebar - `⌘ 0`
  - Library - `⌘ ⌥ 0`
  - share - `⌘ ⇧ S`


#### Fixes

- Fix the issue of automatically adding `https` to external links incorrectly.
- Fix the incorrect display issues related to collaboration UI on iOS.

## 1.4.3

Fix the issue where the toolbar does not display correctly in the file sharing sheet on macOS 14.

## 1.4.2

#### New Features

- External links support

#### Optimizations

- Support tool lock
- Optimize syncing indicator

#### Bugs fixed

- Fix toolbar not working in collaboration room.
- Fix the UI issue of the `Mermaid to Excalidraw` dialog on the iOS side.

## 1.4.1

#### Features

- Live Collaboration
- Customize Files sort
- Search & Spotlight support

#### Optimizations

- iCloud syncing mask
- Adaptive toolbar

#### Bugs fixed

- nullfy webview when localfile is deleted outside.
- Errors when backup local files.

## 1.3.1

- Fix issues occured in iOS.
- Optimize sidebar UI - Adds `New Group` bottom button back.
- Fix bugs in refresh folders content logic.

## 1.3.0

- Local files support
- Subfolders & subgroups support
- Create drawing from clipboard (image)
- Math (LaTeX) insertion support
- New toolbar for iPadOS
- Fixed backup logic issue
- Improved backups UI

## 1.2.11

Fixing data compatibility issues, which previously involved multiple aspects such as library imports, arrow head types, and compatibility for reading and writing old files.

## 1.2.10

- More Excalidraw tools support.
  - `Frame tool`, `Web Embed`, `Text to diagram`, `Mermaid to Excalidraw`, `Wireframe to code`.
- Lossless PDF Export.
- Fallback to `Excalifont`.
- Optimize Excalidraw data compatibility.

## 1.2.8

* Optimize i18n, now supports `English`, `简体中文`, `繁體中文`, `日本語`, `한국어`, `Español`, `Français`, `Deutsch`, `Italiano`, `Русский`, `Português`, `Nederlands`, `Polski`, `Türkçe`, `العربية`, `हिन्दी`, `ไทย`, `Tiếng Việt`

## 1.2.7

- New feature: Export PDF.
- New feature: Export images without background.
- New feature: Undo & Redo via multi-touch gestures.
- New feature: iCloud data sync toggle within the app.
- Apple Pencil support.
  - Also support drawing with the Apple Pencil and directly dragging the canvas with your finger.
- Fix issue where Sidebar was not clickable.
- Accessibility improvements for offline usage on iOS.
- Fix issue with File History not working properly on iPad.
- Sync with the latest Excalidraw core code.
- Add Korean font support.

## 1.2.6

- Fixed an issue where the sidebar `file` could not be clicked on some Mac devices.

- Fixed an issue where duplicated `default` and `Recently deleted` folders appeared during the initial data synchronization.

## 1.2.5

- Added a “What’s New” sheet.
- Fixed the issue where images were lost after saving directly opened Excalidraw files.
- Improved compatibility with improperly formatted data.
- Fixed a bug where backups failed in the presence of data compatibility issues.
- Fixed a bug where exports failed in the presence of data compatibility issues.
- Fixed an issue where files in the trash were not included during export.
- Fixed the issue where pressing the spacebar would continuously trigger warning sounds.

## 1.2.4

Fixed multiple issues where behavior did not meet expectations on macOS 14.

* The Sidebar Toggle was not displayed.
* The Settings View does not select a tab when displayed.
* After deleting a file, an existing file is not automatically selected for loading.
* Switching folders does not automatically select an existing file for loading.
* Duplicating a file does not load the newly created file.

## 1.2.3

#### New Features

* Add multiplatform support!
  * Also with iCloud data synchronisation.
  * Now you can edit and view your excalidraw work on iOS.
* Add a toggle for user to choose if preventing the invert of images in dark mode.

#### Optimization

* Optimize the file loading speed.
  *  by splitting the media files with excalidraw elements.

## 1.1.0

#### New Features

* Add support for editing `.excalidraw` file directly.
* Add support for exporting, importing and editing  `.excalidraw.png` or `.excalidraw.svg` file directly.
* Support quick look for `.excalidraw` file.

#### Bugs fixed

* Fix the bug of failed to import old version library files.

## 1.0.1

Fix the annoying sound.

## 1.0.0

#### New Features

* Excalidraw Libraries supprt
  * Support for importing `.excalidrawlib` files:
    - Import via drag-and-drop.
    - Import via the "Import" button.
    - Import via the "Add to Library" option from the context menu.
  * Support for exporting to `.excalidrawlib` files.
  - Library management operations:
    - Rename items.
    - Merge items.
    - Remove items.
    - Perform operations on multiple selected items.
* Compatibility extension: Now supports as old as macOS 12.0.
* Add Localization for `Chinese-simplified`
* Add `merge with` option for groups.
* Synchronized the `Excalidraw` core to the latest version.
* Optimized the Share interface UI.
* Moved the Toolbar to the top sidebar of the application to simplify the canvas.
* More handwriting fonts supported: `English`, `Chiniese`, `Jpanese`.

#### Optimization

* Increase stability of database. (Especially for concurrency operations.)
* Optimize multithreaded performance.

#### Bugs Fixed

* Issues with archive file when there are file name duplications.
* UI errors in the Settings view.
* Annoying alert sounds when pressing keys.
* Can not add image with toolbar.

## 1.0.0-beta-1

* Fix compatibility with older versions of the Libraries.
* Optimize multithreaded performance.

## 1.0.0-alpha-5

* Optimize i18n
  * add localization for `Chinese-simplified`

## 1.0.0-alpha-4

* Optimize import functionality 
* Add `merge with` option for groups.
* Increase stability of database. (Especially for concurrency operations.)

## 1.0.0-alpha-3

* Optimize first launch experience. 

## 1.0.0-alpha-2

* Optimize performance

## 1.0.0-alpha-1

* Synchronized the `Excalidraw` core to the latest version.
* Compatibility extension: Now supports as old as macOS 12.0.
* Optimized the Share interface UI.
* Moved the Toolbar to the top sidebar of the application to simplify the canvas.
* More handwriting fonts supported: English, Chiniese, Jpanese.
* Multiple bug fixes: 
  * Issues with archive file when there are file name duplications.
  * UI errors in the Settings view.
  * Annoying alert sounds when pressing keys.
  * Can not add image with toolbar.

## 0.4.5

* Revert update: `Remove alert sound when using keyboard.`

## 0.4.4

* Remove alert sound when using keyboard. (Special thanks to  [DervexDev](https://github.com/chocoford/ExcalidrawZ/issues?q=is%3Apr+author%3ADervexDev))
* Fixed the duplicated sidebar toggle bug in macOS 15.

<aside 
       data-v-0ca053f3="" 
       aria-label="important" 
       style="margin: 20px; 
              text-align: start;
              display: block;
              background-color: rgb(255, 251, 242);
              border-color: rgb(158, 103, 0);
              box-shadow: rgb(158, 103, 0) 0px 0px 1px 0px inset, rgb(158, 103, 0) 0px 0px 1px 0px;
              border-radius: 15px;
              padding: .9411764706rem;
              boder-style: solid;
              border-width: 1px;
              "
       >
  <p data-v-0ca053f3="" class="label" style="color: rgb(158, 103, 0); font-size: 17px; font-weight: 600;">Important</p>
  <p style="margin-top: 6.8px; font-size: 17px; letter-spacing: 0.374px; text-align: start;">
There is a significant performance drop in macOS 15, and we are developing a new version to accommodate the upcoming macOS 15. This version will be the last minor release in 0.4. Starting with the next version, the minimum required version will be raised to macOS 14.
  </p>
</aside>

## 0.4.3

* Add settings for color scheme of excalidraw webview. 
* Bug fixed: copy on elements not working 
* Optimize the UI of `Settings`.

## 0.4.2

* Bug fixed: Export image stuck in loading...
* Optimization: Auto add export file extension for user.

## 0.4.1

* Optimize sidebar UI.
* Support Chinese handwriting font.

## 0.4.0

* New sidebar design

*  New `Share` button. You can export image/export file/archive all files. `MacOS 13.0 only`

  <img src="https://github.com/chocoford/ExcalidrawZ/assets/28218759/5d49daa4-323b-4145-bcb3-1f7a2cdedd19" alt="export image" style="zoom:50%;" />

* New file history. Protects your works.

  <img src="https://github.com/chocoford/ExcalidrawZ/assets/28218759/b4feb7df-4278-4a5c-8c78-c83200efc99b" alt="File History" style="zoom:50%;" />

* Bugs fixed.

## 0.3.5

* Add `Settings`
  * support changing color scheme
  * support manually checking updates & enable/disable auto update.

## 0.3.4

* Add `export image` feature.

  ![image-20230404024927888](assets/CHANGELOG/image-20230404024927888.png)

## 0.3.3

* Add backward compability: now app can be run on macOS 12.0 and newer.

## 0.3.2

* Optimize UI: now user can hide sidebar.
* Add `import`&`exportAll` in command menu.

## 0.3.1

* **Important**: fix the bug that will cause saving files failed.
* optimize deletion & recover mechanism.
* fix the bug user first come to app without group selection.
* fix the bug that will cause infinite loop when current file is `nil`.
* fix the bug that may cause saving empty data to existed file.

## 0.3.0

* Migrate storage from file system to core data.
* Hide the dropdown menu button in `excalidraw.com`
* App now can create groups to store files.
* App now can remember group selection.
* File group moving is now available.
* Files that being deleted will be move to `trash`.
* Context menu on `file` and `folder` is now available.

## 0.2.4

* test `Sparkle` framework for sandbox app.

## 0.2.3

* fix bug in x86 mac: import file failed.

## 0.2.2

* Test `Sparkle` framework

## 0.2.1

* Integrates `sparkle` framework for updates
