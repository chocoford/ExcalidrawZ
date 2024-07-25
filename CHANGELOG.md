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