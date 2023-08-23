<div align="center" style="display:flex;flex-direction:column;">
  <a href="https://excalidraw.com">
    <img src="./ExcalidrawZ/Assets.xcassets/AppIcon.appiconset/AppIcon-128.0x128.0@2x.png?raw=true" alt="ExcalidrawZ logo" />
  </a>
  <h3>Excalidraw app for mac. Powered by pure SwiftUI.</h3>
</div>
![GitHub](https://img.shields.io/github/license/chocoford/ExcalidrawZ)[![Twitter](https://img.shields.io/twitter/url/https/twitter.com/cloudposse.svg?style=social&label=Follow%20%40Chocoford)](https://twitter.com/dove_zachary)

## The motivation

[Excalidraw](https://github.com/excalidraw/excalidraw) is a very useful web app, but the lack of file management can be troublesome and unsettling. We often need to manually save and maintain multiple different Excalidraw files. Therefore, ExcalidrawZ has wrapped it up to automatically save edited files for users and added file grouping functionality. In future versions, iCloud automatic backup will also be added to greatly reduce the insecurity of using a web app.

## Preview
![App preview](https://github.com/chocoford/ExcalidrawZ/assets/28218759/8188d209-0fed-469d-b702-37631985c1a3)

## Features

#### create groups to store excalidraw files

By using the `Create folder` button located in the bottom left corner of the app, you can create new folders to organize your work.

#### `.excalidraw` file import

You can import any file ending with excalidraw into the app through the menu bar.

#### Share

Sharing allows you to make your work output more seamless. ExcalidrawZ supports sharing your work with others through the clipboard, file system, and system sharing menu. Additionally, ExcalidrawZ provides backup for all your files through archiving.

* export image
* export file
* archive all files

![export image](https://github.com/chocoford/ExcalidrawZ/assets/28218759/5d49daa4-323b-4145-bcb3-1f7a2cdedd19)



#### History

Safety is a feature that ExcalidrawZ highly prioritize as a local client. To ensure this, ExcalidrawZ performs a checkpoint record of the file before you loading another file. You can tap the button on the top right of app to view the history. 

![File History](https://github.com/chocoford/ExcalidrawZ/assets/28218759/b4feb7df-4278-4a5c-8c78-c83200efc99b)

## RoadMap

- [ ] iCloud synchronization



## Develop Tips

* Remove preload of fonts in `index.html`, otherwise fonts will not be loaded.
