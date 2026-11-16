# Giffer

A small macOS app that converts a video file to a GIF.

Drag a video (`.mp4`, `.mov`, `.webm`, `.mkv` and most other formats) onto the Dock icon or the app window. A settings window opens, you press Convert, and the GIF is written next to the source file with the same name and a `.gif` extension.

## Download

[Download Giffer.zip](https://github.com/mgunneras/giffer/releases/latest/download/Giffer.zip) (about 31 MB). Requires macOS 14 or later, Apple Silicon or Intel. Nothing else needs to be installed; ffmpeg is included in the app.

### First launch

The app is not signed with an Apple Developer ID and is not notarised, so macOS blocks it the first time. To open it:

1. Unzip and move `Giffer.app` to Applications.
2. Double-click it. macOS shows "Apple could not verify…". Click Done.
3. Open System Settings → Privacy & Security, scroll down, and click **Open Anyway** next to the Giffer message.

This is needed once. The first conversion from Desktop, Documents or Downloads may also ask for permission to access that folder.

## Settings

| Setting | Options |
| --- | --- |
| Frame rate | 5 to 30 fps |
| Width | Original, or 1600 down to 320 px |
| Colours | 256, 128, 64, 32 |
| Dithering | Smooth, Pattern, None |
| Speed | 1×, 1.5×, 2×, 4× |
| Trim | Start and end time in seconds |

The window shows the output dimensions, frame count and an approximate file size before converting. The estimate adjusts itself from the sizes of earlier conversions. Settings other than trim are remembered.

During conversion the window shows a progress bar and a live preview. Afterwards it shows the finished GIF, its size, and buttons to copy it or reveal it in Finder. If a GIF with the same name already exists, the app asks before replacing it.

For the smallest files: lower the width and frame rate first, then reduce colours, and set dithering to None for screen recordings.

## Limitations

- One file at a time.
- AV1 video is not supported.
- The Intel build of ffmpeg is compiled without assembly optimisations, so decoding is slower on Intel Macs.

## Building

Requires Xcode command line tools and `gpg`.

```sh
./build-ffmpeg.sh    # once: downloads, verifies and compiles ffmpeg into vendor/ffmpeg
./build.sh           # builds build/Giffer.app and build/Giffer.zip
./build.sh install   # also copies the app to /Applications
```

`build.sh` signs ad hoc by default. Set `SIGN_ID` to a Developer ID Application identity to sign with it.

## How it works

The app is Swift (AppKit and SwiftUI) and runs ffmpeg twice: one pass builds a colour palette for the clip (`palettegen`), the second encodes the GIF with it (`paletteuse`). Both passes also emit a small raw preview stream that the app reads for the preview image and progress.

## Third-party software

Release builds include [FFmpeg](https://ffmpeg.org) 9.0.2, built unmodified from the official source tarball with the configuration in `build-ffmpeg.sh`, and licensed under the GNU LGPL version 2.1 or later. The licence text is in the app at `Contents/Resources/COPYING.LGPLv2.1`. Source: <https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz>.
