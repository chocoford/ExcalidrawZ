<div align="center" style="display:flex;flex-direction:column;">
  <a href="https://excalidraw.com">
    <img src="./ExcalidrawZ/Assets.xcassets/AppIcon.appiconset/AppIcon-128.0x128.0@2x.png?raw=true" alt="ExcalidrawZ logo" />
  </a>
  <h3>Excalidraw app for mac. Powered by pure SwiftUI.</h3>
</div>

![GitHub](https://img.shields.io/github/license/chocoford/ExcalidrawZ) [![Twitter](https://img.shields.io/twitter/url/https/twitter.com/cloudposse.svg?style=social&label=Follow%20%40Chocoford)](https://twitter.com/dove_zachary)

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
  <p data-v-0ca053f3="" class="label" style="color: rgb(158, 103, 0); font-size: 17px; font-weight: 600;">Developing...</p>
  <p style="margin-top: 6.8px; font-size: 17px; letter-spacing: 0.374px; text-align: start;">
This new version is under development. The TCA framework will be removed.
  </p>
</aside>



## The motivation

[Excalidraw](https://github.com/excalidraw/excalidraw) is a very useful web app, but the lack of file management can be troublesome and unsettling. We often need to manually save and maintain multiple different Excalidraw files. Therefore, ExcalidrawZ has wrapped it up to automatically save edited files for users and added file grouping functionality. In future versions, iCloud automatic backup will also be added to greatly reduce the insecurity of using a web app.

## Preview
![App overview](assets/README/App%20overview.png)

## Installation

1. Download the latest image file (.dmg) from [Releases](https://github.com/chocoford/ExcalidrawZ/releases)
2. Click the `.dmg` to install it

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

* Hide toolbar in `packages/excalidraw/components/LayerUI.tsx/LayerUI`.

* Add fonts after build.

  * add the codes below to `index.html`.
    ```html
    <link rel="preload" href="YRDZST-Regular.ttf" as="font" type="font/ttf" crossorigin="anonymous">
    <link rel="preload" href="SetoFont.ttf" as="font" type="font/ttf" crossorigin="anonymous">
    <link rel="stylesheet" href="fonts.css" />
    ```

    