fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

### upload_metadata

```sh
[bundle exec] fastlane upload_metadata
```

Upload App Store Connect metadata for one explicit platform. Build upload stays manual.

### upload_ios_release_assets

```sh
[bundle exec] fastlane upload_ios_release_assets
```

Upload iOS App Store metadata and iOS/iPadOS screenshots. Build upload stays manual.

### split_screenshots

```sh
[bundle exec] fastlane split_screenshots
```

Split localized App Store preview strips into fastlane screenshot folders.

### render_preview_strips

```sh
[bundle exec] fastlane render_preview_strips
```

Render localized App Store preview strips from a text-free template.

### generate_previews

```sh
[bundle exec] fastlane generate_previews
```

Render localized preview strips and split them into App Store screenshots.

### generate_preview_samples

```sh
[bundle exec] fastlane generate_preview_samples
```

Generate only en-US and zh-Hans preview samples for visual checks.

----


## Mac

### mac prepare_sparkle_release

```sh
[bundle exec] fastlane mac prepare_sparkle_release
```

Prepare localized Sparkle release notes and an appcast containing the Sparkle update signature.

### mac generate_sparkle_release_notes

```sh
[bundle exec] fastlane mac generate_sparkle_release_notes
```

Generate localized Sparkle release notes and patch local website appcast.

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
