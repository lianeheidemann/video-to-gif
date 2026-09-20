<div align="center">

<img width="100" src="assets/icon/icon-v4.png"/>

# Video to GIF

<img width="460" src="assets/video-to-gif-badges-adaptive-6.svg"/><br>

[![CI](https://img.shields.io/github/actions/workflow/status/lianeheidemann/video-to-gif/ci.yml?branch=main&style=flat-square&label=CI&logo=github&logoColor=white&labelColor=372b4d)](https://github.com/lianeheidemann/video-to-gif/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/actions/workflow/status/lianeheidemann/video-to-gif/release.yml?branch=main&style=flat-square&label=Release&logo=github&logoColor=white&labelColor=372b4d)](https://github.com/lianeheidemann/video-to-gif/actions/workflows/release.yml)

**Turn videos and photos into animated GIF (or WebP)<br>
directly on Android — privately and offline.**

<img src="assets/linha-lilas-v3.svg"/>

<img src="assets/gif/video-to-gif-interface-v2.webp"/>

</div>

## About

Android app built with Flutter, with three editors that share the same
editor shell, frame library and on-device export pipeline, plus a fourth
tool for quick format swaps:

| Tool | What it does |
|---|---|
| **Video to GIF/WebP** | Converts MP4, MOV, AVI, MKV, WebM and 3GP to **GIF or animated WebP** — trim, crop, speed, resolution, frame rate, colors and a decorative frame. For GIF it also **estimates the final file size before converting**. |
| **Frame on a photo** | Puts the same procedural or phone-mockup frames around a single photo, with content-fit modes, color adjustment and a transparent or colored background. |
| **Photo collage** | Assembles several photos into one composition — layouts, margins, borders, stickers, imported fonts, crop and color adjustment. If any photo is animated, the whole collage exports **animated**. |
| **Convert format** | Picks any video, GIF or WebP and re-encodes it to GIF, animated WebP or MP4, with a resolution slider — no trim, quality or preview otherwise. |

Choose the format that best fits your destination:

| Format | Best for | Notes |
|---|---|---|
| **GIF** | Broad compatibility and predictable sharing limits | Includes file-size estimation and destination compatibility checks |
| **Animated WebP** | Better color, transparency and smaller files at similar quality | Includes a quality slider; some older apps may not play the animation |

> All conversion runs on-device with FFmpeg. The app has no internet
> permission.
>
> **[⬇ Download the APK](https://github.com/lianeheidemann/video-to-gif/releases/latest)**
> — installs straight onto Android, no store needed.

## The problem it solves

Converting video to GIF is slow, and the output size is unpredictable — the
same settings can produce 800 KB for one video and 14 MB for another,
depending on how much the scene moves. This app estimates the size **while
you adjust the controls**, without converting anything, and the **Measure**
button refines that estimate by converting two short clips and calibrating
on their real size.

> [!WARNING]
> **The estimate is still being refined.** Before measuring it relies on
> bitrate alone, and a few content types (e.g. moving gradients) can fall
> outside the range even after. Full methodology and accuracy in
> [`docs/en/HOW_THE_ESTIMATE_WORKS.md`](docs/en/HOW_THE_ESTIMATE_WORKS.md).

### Shared across the app

The three editors share one shell: a bottom tab bar where each tab opens its
own panel over the preview, save/share/convert actions, and undo/redo. Every
panel scrolls within a height cap, and collapsing it never drops the current
selection. They also share one **color adjustment** panel — brightness,
exposure, contrast, highlights, shadows, saturation, hue and temperature —
driven by a single color matrix that the live preview and the FFmpeg export
both use, so what you see is what gets encoded.

### Video → GIF / WebP

- Preview with a timeline, duration trim and crop (presets or custom)
- Speed 0.25x–4x, resolution as a percentage of the original (with pixel
  preview), frame rate 5–24 fps, loop or play once
- Output as GIF (256-color palette, two-pass conversion) or animated WebP
  (full color, transparency, its own quality slider)
- GIF color quality — up to 256 colors, five dithering levels, three
  palette strategies
- Size tab with the estimate, its confidence range and a destination
  compatibility check, next to the "Measure" button

### Frames (video and single photo)

- Procedural border — thin, medium or thick, with color and corner rounding
- Image frame — bundled phone mockups, or your own with an
  automatically-detected transparent window
- Content fit — auto, fill, fit or expand with zoom
- Transparent (real alpha on WebP/PNG) or solid-color background

### Photo collage

- Layouts from a single row to a free grid, with aspect ratio, margins and
  borders per photo or for the whole montage
- Background — transparent, solid color or an imported image, set
  separately for the montage and for the photos inside it
- Per-photo replace, crop, rotate and flip from the cell menu; color
  adjustment for one photo or for all of them at once
- Stickers (bundled or your own, organized in folders) and text with
  imported fonts
- Animated export (PNG, GIF or WebP) whenever a photo in the collage is
  itself animated

### Convert format

Picks up any video, GIF or animated WebP from the system gallery and
re-encodes it to GIF, WebP or MP4, with a resolution slider and the
source's own format disabled in the picker. Static photos are rejected
up front — there is a dedicated tool for those.

## How to run it

Requires Flutter 3.44+ (Dart 3.12+) and the Android SDK (API 36) with NDK
installed.

```bash
git clone https://github.com/lianeheidemann/video-to-gif.git
cd video-to-gif
```
```
flutter pub get
flutter test
```
```
flutter run
```

### Build the release APK

```bash
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. For
split APKs per ABI instead of one universal build (smaller downloads, closer
to what [Releases](https://github.com/lianeheidemann/video-to-gif/releases) ship), add `--split-per-abi`:

```bash
flutter build apk --release --split-per-abi
```

CI pins the Flutter version to **3.47.0** (`FLUTTER_VERSION` in
`.github/workflows/ci.yml`). If `dart format` complains there but passes on
your machine, run it on that same version.

## Structure

```
lib/
├── models/     # settings, layouts and the value objects the editors share
├── services/   # size estimation, FFmpeg, compositing and the import stores
└── ui/         # the three editors, the crop screen and the shared widgets

test/           # see "Quality" below
tool/           # icon generation, the accuracy script and the asset-list sync

assets/
├── background/ # ready-made backgrounds for the collage
├── fonts/      # fonts offered for collage text
├── frame/      # ready-made image frames
└── sticker/    # ready-made stickers, one folder per theme

.github/workflows/
├── ci.yml      # formatting, analysis, tests and a debug APK
└── release.yml # publishes the APKs to a Release
```

### Adding art to the app

Drop a file into `assets/fonts`, `assets/frame` or `assets/sticker` and
build — the app reads those folders at startup, so it shows up on its own.
Fonts are registered under a family name derived from the filename;
frames get their transparent window auto-detected; stickers land in a
"Novos" folder that only appears once it has something in it. A **new
sub-folder** is the one case needing a command first, since Flutter's asset
declaration isn't recursive:

```bash
python3 tool/sincronizar_assets.py   # rewrites the assets: list in pubspec.yaml
```

CI runs this in check mode on every push, so a forgotten sub-folder can't
reach a release unnoticed.

`size_estimator.dart` is pure Dart, with no Flutter or FFmpeg dependency,
so it's fully testable without an emulator — the same is true of
`collage_painter.dart`, which draws both the live preview and the exported
frames from one code path.

## Quality

**353 automated tests** cover the estimation model against real FFmpeg
output, the size and quality panels, frame and crop geometry, the export
arguments for every format, the import stores, and the collage — framing,
color, layout, compositing against golden pixels and the animation
timeline.

`tool/medir_precisao.py` produces five synthetic videos, from a static title
card to incompressible noise, converts each and records the sizes; a test
feeds those measurements back through the model and checks the error. Once
calibrated, the prediction lands within **±1% for three of the five cases,
−7% for the fourth**. Full table, including the cases that still miss, in
[`docs/en/HOW_THE_ESTIMATE_WORKS.md`](docs/en/HOW_THE_ESTIMATE_WORKS.md).

`.github/workflows/ci.yml` runs formatting, analysis, the full test suite
and a debug APK build on every push — the APK build catches Gradle,
manifest-merging and native-packaging issues the other steps can't see.

## Download the APK

Every published version becomes a
[Release](https://github.com/lianeheidemann/video-to-gif/releases)
with ready-to-install APKs — start with `arm64-v8a`, which covers
practically every current Android phone. `universal` is larger, but works
on any device.

## Stack

| Layer | Choice | Why |
|---|---|---|
| Interface | Flutter 3.44 (Material 3) | one codebase, with a native Android look |
| Conversion | `ffmpeg_kit_flutter_new_video` ([FFmpeg](https://github.com/FFmpeg/FFmpeg) LGPL) | variant without GPL components (bundles libwebp for WebP export), allows closed-source distribution |
| File picking | `file_picker` | uses the system picker, no media permission required |
| Preview | `video_player` | shows the clip and crop frame before converting |
| Frame and sticker art | `flutter_svg` | renders the bundled and imported vector art without losing sharpness at any output resolution |
| Collage rendering | `dart:ui` (`PictureRecorder`) | the same painter draws the live preview and the exported frames |
| Output | `gal` + `share_plus` | save to gallery and share |

## License

App code: Proprietary — all rights reserved (see [LICENSE](LICENSE)).
FFmpeg: LGPL-2.1-or-later — attribution in [`NOTICE`](NOTICE), details and
obligations in [`docs/en/LICENSES.md`](docs/en/LICENSES.md).

---

<p align="center">Developed by <strong>Liane Heidemann</strong></p>
