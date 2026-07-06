# Fastlane Commands

Concise command reference. For workflow rules and file layout, see `RELEASE.md`.

## List Lanes

```sh
fastlane lanes
```

## App Store Metadata

macOS metadata dry-run:

```sh
fastlane upload_metadata platform:mac version:2.2.2 dry_run:true
```

macOS metadata upload:

```sh
fastlane upload_metadata platform:mac version:2.2.2
```

iOS metadata dry-run:

```sh
fastlane upload_metadata platform:ios version:2.2.2 dry_run:true
```

iOS metadata upload:

```sh
fastlane upload_metadata platform:ios version:2.2.2
```

iOS metadata and screenshots dry-run:

```sh
fastlane upload_ios_release_assets version:2.2.2 dry_run:true
```

iOS metadata and screenshots upload:

```sh
fastlane upload_ios_release_assets version:2.2.2
```

## Sparkle

Generate localized Sparkle release notes:

```sh
fastlane generate_sparkle_release_notes version:2.2.2
```

## Screenshots

Generate sample screenshots for visual checking:

```sh
fastlane generate_preview_samples device:iphone
fastlane generate_preview_samples device:ipad
```

Render localized preview strips only:

```sh
fastlane render_preview_strips device:iphone
fastlane render_preview_strips device:ipad
```

Split existing preview strips only:

```sh
fastlane split_screenshots device:iphone
fastlane split_screenshots device:ipad
```

Generate preview strips and split screenshots:

```sh
fastlane generate_previews device:iphone
fastlane generate_previews device:ipad
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
