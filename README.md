# Audio Extractor

A small Windows app that saves the audio from YouTube videos. It's a friendly window
around [yt-dlp](https://github.com/yt-dlp/yt-dlp) (downloading) and [FFmpeg](https://ffmpeg.org)
(converting). See [Credits](#credits).

## Start it

Double-click **`Audio Extractor.cmd`**.

Inside the app, click **Add to Start menu** to get a Start menu and desktop shortcut with
its own icon (and no console flash). If you move this folder later, click it again.

## Use it

1. Copy a YouTube link, then switch to the app. It fills the link in for you
   (or paste several links, one per line). With *Queue YouTube links I copy* on, copying
   is enough: see [Copy to queue](#copy-to-queue) below.
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

### Copy to queue

With *Queue YouTube links I copy (Ctrl+C)* checked (the default), the app watches the
clipboard while it is open. Copy a YouTube link in any other app (browser, chat, etc.) and it
is added to the download queue right away; you don't need to switch to the window.

- Each link keeps the format, quality, clip times, tag and playlist options, and folder that
  were selected **when it was copied**. To get different clips or formats, change the settings
  in the app, then copy the next link.
- Downloads run one after another. The *Up next* list shows the waiting links and their settings.
- While a download runs, the settings stay editable and the button reads **Add to queue**, so
  links pasted into the box can be added the same way.
- If the clip times are invalid when a link is copied, the link is not queued; it is placed in
  the Links box and the status line says what to fix.
- Copying the same link again with the same settings while it is still waiting is ignored.
- Text copied inside the app's own window is not queued.
- **Cancel** stops the current download and empties the queue; unfinished links go back into
  the Links box.

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
- `settings.json`: your last-used format, quality, folder and clipboard option (created automatically)
- `AudioExtractor.ico`: created when you click *Add to Start menu*

## Credits

This app is only a front end. The downloading and converting are done by:

- [yt-dlp](https://github.com/yt-dlp/yt-dlp): downloads the audio from YouTube. Released under
  the Unlicense. yt-dlp is a fork of [youtube-dl](https://github.com/ytdl-org/youtube-dl).
- [FFmpeg](https://ffmpeg.org): converts and cuts the audio, embeds cover art. LGPL/GPL.
- [Deno](https://deno.com): JavaScript runtime that yt-dlp uses for YouTube. MIT.

The same credits, with links, are shown at the bottom of the app window.

Only download content you own or have permission to save. Most YouTube videos are
covered by YouTube's Terms of Service and copyright.
