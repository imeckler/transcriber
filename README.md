# Transcriber

Transcriber turns audio and video recordings into text on your Mac. The app includes whisper.cpp, llama.cpp, and FFmpeg. Only model downloads use the internet.

## Getting started

Download **Transcriber-Mac.zip** from Releases, unzip it, and move **Transcriber.app** to Applications. The bundle runs natively on Intel and Apple silicon. This release is ad-hoc signed and has no Apple notarization.

1. Choose a recording and download a speech model. Base is a good starting point. Tiny uses less memory.
2. Select the spoken language or let Transcriber detect it. Choose **Transcribe recording** to start.
3. Read or copy the transcript, or use **Export** to save plain text, SubRip (.srt), or WebVTT (.vtt). Plain text groups speech into paragraphs. Subtitles retain individual cue times.
4. For optional cleanup, enable **Remove filler words** and download Qwen. You can clean the existing transcript in the same session. Switch between **Original** and **Cleaned** to review edits.

For separate stereo microphones, choose **Left / right speakers**. For English recordings with mixed voices, the experimental **Speaker Turns** model marks likely changes of speaker. Model Library shows download sizes and lets you remove unused models.

## Building

On a Mac with Xcode, CMake, Python 3, and Make installed, run `make app`. The build scripts fetch checksum-pinned sources and produce `dist/Transcriber.app` and `dist/Transcriber-Mac.zip`. Run `make test` for transcript cleanup and export regression checks.

The speech and cleanup engines use up to eight CPU threads. The cleanup validator preserves word order, punctuation, numbers, and existing capitalization. It allows the model to add capitalization and omit a small set of English hesitation sounds. If a suggestion adds or removes other words, Transcriber falls back to the source wording.

## Bundled engines

The build uses whisper.cpp v1.7.5 with a stereo downmix correction, llama.cpp b4514, and FFmpeg 6.1.2. The app includes their license notices. The release includes the corresponding FFmpeg source archive. Build configuration is in the scripts directory.
