# Fastlane Commands

Concise command reference. For workflow rules and file layout, see `RELEASE.md`.

## Interactive Console

Run from Terminal, or double-click the file in Finder:

```sh
./ExcalidrawZRelease.command
```

The console covers metadata uploads, platform release assets, screenshot generation,
Sparkle release notes, dry runs, and common status/output-folder tools. The
commands below remain available for automation and troubleshooting.

## List Lanes

```sh
fastlane lanes
```

## App Store Metadata

macOS metadata dry-run:

```sh
fastlane upload_metadata platform:mac version:x.y.z dry_run:true
```

macOS metadata upload:

```sh
fastlane upload_metadata platform:mac version:x.y.z
```

macOS metadata and screenshots dry-run:

```sh
fastlane upload_mac_release_assets version:x.y.z dry_run:true
```

macOS metadata and screenshots upload:

```sh
fastlane upload_mac_release_assets version:x.y.z
```

iOS metadata dry-run:

```sh
fastlane upload_metadata platform:ios version:x.y.z dry_run:true
```

iOS metadata upload:

```sh
fastlane upload_metadata platform:ios version:x.y.z
```

iOS metadata and screenshots dry-run:

```sh
fastlane upload_ios_release_assets version:x.y.z dry_run:true
```

iOS metadata and screenshots upload:

```sh
fastlane upload_ios_release_assets version:x.y.z
```

For an upload that needs a local HTTP/HTTPS proxy, add its port. Omit the
option to connect directly:

```sh
fastlane upload_mac_release_assets version:x.y.z proxy_port:7890
```

## Sparkle

Prepare an appcast containing the Sparkle update signature and localized
release notes before uploading the GitHub release asset:

```sh
fastlane mac prepare_sparkle_release version:x.y.z
```

After the matching GitHub release asset is uploaded, regenerate and verify its
download URL:

```sh
fastlane mac prepare_sparkle_release version:x.y.z verify_asset:true
```

Generate localized Sparkle release notes:

```sh
fastlane mac generate_sparkle_release_notes version:x.y.z
```

## Screenshots

Generate sample screenshots for visual checking:

```sh
fastlane generate_preview_samples device:iphone
fastlane generate_preview_samples device:ipad
fastlane generate_preview_samples device:mac
```

Render localized preview strips only:

```sh
fastlane render_preview_strips device:iphone
fastlane render_preview_strips device:ipad
fastlane render_preview_strips device:mac
```

Split existing preview strips only:

```sh
fastlane split_screenshots device:iphone
fastlane split_screenshots device:ipad
fastlane split_screenshots device:mac
```

Generate preview strips and split screenshots:

```sh
fastlane generate_previews device:iphone
fastlane generate_previews device:ipad
fastlane generate_previews device:mac
```

Generate one locale:

```sh
fastlane generate_previews device:ipad locales:zh-Hans
```

Preview screenshot work without writing files:

```sh
fastlane generate_previews device:ipad dry_run:true
fastlane split_screenshots device:ipad dry_run:true
```
