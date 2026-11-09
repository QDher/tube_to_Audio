# Audio Extractor

A small Windows app that saves the audio from YouTube videos. It's a friendly window
around [yt-dlp](https://github.com/yt-dlp/yt-dlp) (downloading) and ffmpeg (converting).

## Start it

Double-click **`Audio Extractor.cmd`**.

Inside the app, click **Add to Start menu** to get a Start menu and desktop shortcut with
its own icon (and no console flash). If you move this folder later, click it again.

## Use it

1. Copy a YouTube link, then switch to the app. It fills the link in for you
   (or paste several links, one per line).
2. Pick a format:
   | Format | When to use it |
   |---|---|
   | **MP3** | Plays everywhere. "Best (VBR)" is recommended. |
   | **M4A** | AAC kept exactly as YouTube sends it, with no re-encoding. Good for Apple devices. |
   | **Opus** | YouTube's best stream, kept as-is. Smallest files. |
   | **FLAC / WAV** | For audio editors. Larger files, same quality as the source. |
3. Press **Extract audio** (or Ctrl+Enter).

Files go to `Music\YouTube Audio` unless you choose another folder.

**Options**
- *Add cover art & tags*: embeds the thumbnail, title, artist and so on.
- *Whole playlist*: when a link contains `&list=...`, downloads every track (numbered).
- *Only a clip*: set a start and/or end time (e.g. `0:45` to `2:10`). The file name gets a
  `(clip ...)` suffix.

Links that fail stay in the box so you can retry them. **Show details** shows yt-dlp's full output.

If your save folder isn't available when the app starts (for example a cloud drive that
hasn't mounted yet, or a drive that this PC doesn't have), files go to `Music\YouTube Audio`
for now. The app keeps your usual folder saved and switches back to it once it's available.

## Requirements

Windows 10 or 11. Already installed on this PC via winget: `yt-dlp`, `ffmpeg`, and `deno`
(YouTube needs a JavaScript runtime).

## Using it on another PC

1. Copy `AudioExtractor.ps1` and `Audio Extractor.cmd` into one folder.
2. Double-click `Audio Extractor.cmd`. If yt-dlp is missing, the app offers to install it.
   The winget package brings ffmpeg and Deno along with it. You can also install it yourself:
   ```
   winget install yt-dlp.yt-dlp
   ```
3. Click **Add to Start menu** on that PC.

If Windows warns that the files came from the internet, right-click each one,
choose **Properties**, then **Unblock**. Managed work or school PCs may block PowerShell
scripts entirely.

## When downloads start failing

YouTube changes often. Click **Update yt-dlp** in the app (it runs
`winget upgrade yt-dlp.yt-dlp`). That fixes most problems.

## Files

- `AudioExtractor.ps1`: the app (PowerShell + WPF, no other dependencies)
- `Audio Extractor.cmd`: launcher
- `settings.json`: your last-used format, quality and folder (created automatically)
- `AudioExtractor.ico`: created when you click *Add to Start menu*

Only download content you own or have permission to save. Most YouTube videos are
covered by YouTube's Terms of Service and copyright.
