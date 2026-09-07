# Licenses — what you need to know before publishing

This app uses **FFmpeg**, which is free software. That's great (you don't
pay anything and can publish a closed-source app), but it comes with a few
small, mandatory obligations. Ignoring them is the kind of thing that gets
an app's removal requested.

## The core point: LGPL yes, GPL no

FFmpeg can be built in two ways:

| Variant | License | Usable in a closed-source app? |
|---|---|---|
| **LGPL** (default) | LGPL 2.1+ | ✅ Yes |
| **GPL** (with x264, x265, xvid, vid.stab) | GPL 2+ | ❌ No — would require you to open-source the whole app |

This project uses the **`ffmpeg_kit_flutter_new_video`** package, which is
an **LGPL** variant and **contains no GPL components**. That's
intentional.

Compared to the `ffmpeg_kit_flutter_new_min` package used before WebP
export existed, `_video` additionally bundles `libwebp` (needed for the
WebP export option), plus `dav1d`, `libvpx` and `libtheora` — all of them
LGPL or permissively licensed, none of them GPL. `libwebp` itself is
Google's own BSD-style-licensed library (not GPL/LGPL), so bundling it
inside the LGPL `_video` package doesn't introduce a GPL component either.

> ⚠️ **Never switch to the packages ending in `_gpl`** (nor to the "full"
> `ffmpeg_kit_flutter_new`, which is GPL) without open-sourcing the app
> under GPL. To convert to GIF you don't need any of that: the GIF encoder
> and the `palettegen`/`paletteuse` filters are part of FFmpeg's core,
> which is LGPL. The same goes for WebP: the `libwebp`-based encoder in
> `_video` is LGPL/BSD, not GPL.

If one day you want to export **MP4 with H.264**, that's where you'd run
into this — and the way out is to use Android's hardware encoder
(MediaCodec), not x264.

## What the LGPL requires of you

1. **State that you use FFmpeg and under which license.**
   Already done: `lib/licenses.dart` registers the notice, which shows up
   under *About → View licenses* inside the app.

2. **Point to where to get FFmpeg's source code.**
   Also in the same notice, with a link to the official repository.

3. **Allow the library to be replaced.**
   Automatically satisfied: FFmpeg is bundled in the APK as a dynamic
   library (`.so`), not compiled into your code.

4. **Don't modify FFmpeg** — or, if you do, publish the modifications.
   You aren't modifying anything.

In other words: the work is already done in the code. Just **don't
remove** the call to `registerThirdPartyLicenses()` in `main.dart`, nor
the *About* button on the home screen.

## Where the Play Store looks at this

Google doesn't automatically verify code licensing, but:

- the **intellectual property** policy lets authors report apps that
  violate the license;
- complaints of this kind usually come from people who follow open-source
  projects, and FFmpeg has a track record of calling this out publicly
  (the project's "hall of shame");
- the consequence is the app's removal and, on repeat offenses, the
  developer account being shut down.

The cost of being compliant is a licenses screen. It's worth it.

## The other dependencies

All with permissive licenses, with no obligations beyond the automatic
notice Flutter already generates under *View licenses*:

| Package | License |
|---|---|
| `flutter` and official packages (`video_player`, `path_provider`, `share_plus`) | BSD-3-Clause |
| `file_picker` | MIT |
| `gal` | MIT |
| `ffmpeg_kit_flutter_new_video` | LGPL-3.0 |
| FFmpeg (binary) | LGPL-2.1-or-later |
| `libwebp` (bundled inside the FFmpeg binary) | BSD-style (Google) |
