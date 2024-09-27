<div align="center" style="display:flex;flex-direction:column;">
  <a href="https://excalidraw.com">
    <img src="./ExcalidrawZ/Assets.xcassets/AppIcon.appiconset/AppIcon-128.0x128.0@2x.png?raw=true" alt="ExcalidrawZ logo" />
  </a>
  <h3>Excalidraw app for mac. Powered by pure SwiftUI.</h3>
</div>

![GitHub](https://img.shields.io/github/license/chocoford/ExcalidrawZ) [![Twitter](https://img.shields.io/twitter/url/https/twitter.com/cloudposse.svg?style=social&label=Follow%20%40Chocoford)](https://twitter.com/dove_zachary)

<a href="https://www.buymeacoffee.com/Chocoford" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>


[Excalidraw](https://github.com/excalidraw/excalidraw) is a very useful web app, but the lack of file management can be troublesome and unsettling. We often need to manually save and maintain multiple different Excalidraw files. Therefore, ExcalidrawZ has wrapped it up to automatically save edited files for users and added file grouping functionality. In future versions, iCloud automatic backup will also be added to greatly reduce the insecurity of using a web app.

## Download

> [!WARNING]
> ### If you have already installed an older version of ExcalidrawZ, please export your files before downloading the official latest version. Otherwise you will lose your existing data.

[![Download Link - App Store](assets/README/Download_on_the_App_Store_Badge_US-UK.svg)](https://apps.apple.com/app/excalidrawz/id6636493997) 

**Non-App Store version**

1. Download the latest image file (.dmg) from [Releases](https://github.com/chocoford/ExcalidrawZ/releases)
2. Click the `.dmg` to install it

## Preview
![App overview](assets/README/App%20overview.png)

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

#### Multiple hand-writing fonts supported

> If you need more languages support, please do not hesitate to contact me.

- [x] English (Native excalidraw font)
- [x] 简体中文（杨任东竹书体）
- [x] 日本語（瀬戸体）

## RoadMap

- [ ] iCloud synchronization

## Develop Tips

* ~~Remove preload of fonts in `index.html`, otherwise fonts will not be loaded.~~

* ~~Add hook in `excalidraw-app/App.tsx/onChange` to track the activated tool changed.~~

* The `excalidraw` core is built and uploaded with the `dmg` file. You can download it from [Releases](https://github.com/chocoford/ExcalidrawZ/releases).

  * Or you can build your own core from [`excalidraw`](https://github.com/excalidraw/excalidraw)

* Hide toolbar in `packages/excalidraw/components/LayerUI.tsx/LayerUI`.

* Add fonts after build.

  * add the codes below to `index.html`.
    ```html
    <link rel="preload" href="YRDZST-Regular.ttf" as="font" type="font/ttf" crossorigin="anonymous">
    <link rel="preload" href="SetoFont.ttf" as="font" type="font/ttf" crossorigin="anonymous">
    <link rel="stylesheet" href="fonts.css" />
    ```

    
