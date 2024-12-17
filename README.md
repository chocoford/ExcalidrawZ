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

![Export editable image](assets/README/Export%20editable%20image.gif)



#### History

Safety is a feature that ExcalidrawZ highly prioritize as a local client. To ensure this, ExcalidrawZ performs a checkpoint record of the file before you loading another file. You can tap the button on the top right of app to view the history. 

![File History](assets/README/File%20History.gif)

#### Multiple hand-writing fonts supported

> If you need more languages support, please do not hesitate to contact me.

- [x] English (Native excalidraw font)
- [x] 简体中文（杨任东竹书体）
- [x] 日本語（瀬戸体）
- [x] [한국어 (빙그레 싸만코체)](http://www.bingfont.co.kr/license.html)


#### Multiple excalidraw file format support
ExcalidrawZ now support editing of `.excalidraw`, `.excalidraw.png`, and `.excalidraw.svg` files (directly in the file system), as well as importing them into the main program.

https://github.com/user-attachments/assets/486f13c4-e0ce-4e59-a21d-bc6be5d91a81

ExcalidrawZ also supports maintaining editability when exporting images. The image files will end with `.excalidraw.png` or `.excalidraw.svg`, and ExcalidrawZ will be able to edit these types of files directly.

https://github.com/user-attachments/assets/09323b30-29f0-4522-8190-46f7ef6a9dd3

#### iOS & iPadOS support

ExcalidrawZ for iOS&iPadOS is now available. All data are synchronised by iCloud.

## RoadMap

- [x] iCloud synchronization
- [x] iOS support.

## Contact me

Welcome to my [Discord server](https://discord.gg/aCv6w4HxDg) to share suggestions or report issues for ExcalidrawZ, helping make ExcalidrawZ even better!

## Development Guide

* The `excalidraw` core for `ExcalidrawZ` is also open-source. You can find it [here](https://github.com/chocoford/excalidraw/tree/ExcalidrawZ-core) and build for your own purposes.
  * And don't forget to give it a star 😁.
* Before you start coding, don't forget to add your own `Overrides.xcconfig` in `ExcalidrawZ/Config` and populate it with the following content:

```xcconfig
DEVELOPMENT_TEAM = <YOUR_DEVELOPMENT_TEAM_FOR_DEBUG>;
ICLOUD_CONTAINER = <YOUR_ICLOUD_CONTAINER_IDNENTIFIER_FOR_DEBUG>;
```

