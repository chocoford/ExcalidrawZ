<div align="center" style="display:flex;flex-direction:column;">
  <a href="https://excalidraw.com">
    <img src="./ExcalidrawZ/Assets.xcassets/AppIcon-macOS.imageset/ExcalidrawZ Icon 26-iOS-Default-83.5x83.5@3x.png?raw=true" alt="ExcalidrawZ logo" />
  </a>
  <h3>Excalidraw app for mac. Powered by pure SwiftUI.</h3>
</div>

![GitHub](https://img.shields.io/github/license/chocoford/ExcalidrawZ) [![Twitter](https://img.shields.io/twitter/url/https/twitter.com/cloudposse.svg?style=social&label=Follow%20%40Chocoford)](https://x.com/Chocoford_) [![Discord](https://img.shields.io/discord/944160092914319361)](https://discord.gg/aCv6w4HxDg)

<a href="https://www.chocoford.com/donation" target="_blank"><img src="https://github.com/chocoford/chocoford/blob/main/public/Donation%20Button.png?raw=true" alt="Donation to Chocoford" style="height: 60px !important;"></a>

[Excalidraw](https://github.com/excalidraw/excalidraw) is a very useful web app, but the lack of file management can be troublesome and unsettling. We often need to manually save and maintain multiple different Excalidraw files. Therefore, ExcalidrawZ has wrapped it up to automatically save edited files for users and added file grouping functionality. In future versions, iCloud automatic backup will also be added to greatly reduce the insecurity of using a web app.

## Download

[![Download Link - App Store](assets/README/Download_on_the_App_Store_Badge_US-UK.svg)](https://apps.apple.com/app/excalidrawz/id6636493997) 

**Non-App Store version**

1. Download the latest image file (.dmg) from [Releases](https://github.com/chocoford/ExcalidrawZ/releases)
2. Click the `.dmg` to install it

## Preview
![App overview](assets/README/ExcalidrawZ%20-%20Overview.png)

## Features

#### create groups to store excalidraw files

By using the `Create folder` button located in the bottom left corner of the app, you can create new folders to organize your work.

- [x] Database groups
  - [x] Customize file sort
- [x] Local Folders
- [x] Temporary files (Directly open an `.excalidraw` file)

#### Collaboration

ExcalidrawZ also supports collaboration.

![Collaboration](assets/README/ExcalidrawZ%20-%20Collaboration.gif)

#### `.excalidraw` file import

You can import any file ending with excalidraw into the app through the menu bar.

#### Share

Sharing allows you to make your work output more seamless. ExcalidrawZ supports sharing your work with others through the clipboard, file system, and system sharing menu. Additionally, ExcalidrawZ provides backup for all your files through archiving.

* export image
* export file
* export to PDF Lossless
* archive all files

![Export editable image](assets/README/Export%20editable%20image.gif)



#### History

Safety is a feature that ExcalidrawZ highly prioritize as a local client. To ensure this, ExcalidrawZ performs a checkpoint record of the file before you loading another file. You can tap the button on the top right of app to view the history. 

![File History](assets/README/File%20History.gif)


#### Multiple excalidraw file format support
ExcalidrawZ now support editing of `.excalidraw`, `.excalidraw.png`, and `.excalidraw.svg` files (directly in the file system), as well as importing them into the main program.

https://github.com/user-attachments/assets/486f13c4-e0ce-4e59-a21d-bc6be5d91a81

ExcalidrawZ also supports maintaining editability when exporting images. The image files will end with `.excalidraw.png` or `.excalidraw.svg`, and ExcalidrawZ will be able to edit these types of files directly.

https://github.com/user-attachments/assets/09323b30-29f0-4522-8190-46f7ef6a9dd3

#### iOS & iPadOS support

ExcalidrawZ for iOS&iPadOS is now available. All data are synchronised by iCloud.

- Apple pencil interaction support.
- Tap with two fingers to undo.
- Tap with three fingers to redo. 

## RoadMap

- [x] iCloud synchronization
- [x] iOS support.
- [x] Support deep links.

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

