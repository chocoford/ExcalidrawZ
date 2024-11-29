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