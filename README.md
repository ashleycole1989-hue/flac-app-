# Flac Player

Offline music player for a jailbroken iPhone 7. It keeps a SQLite index of local files so launch stays fast, plays FLAC through Core Audio, and uses two screens: a vinyl platter and a Cover Flow shelf, both driven by a click wheel.

## What you get

- Playback reads FLAC, ALAC, AAC, MP3, WAV, and AIFF from the app's Documents folder. On a jailbreak it also reads `/var/mobile/Media/FlacPlayer` and any folders listed in `Documents/library.path`.
- The first launch indexes tags in the background. Later launches open the saved index.
- Playback uses `AVAudioEngine` and `AVAudioFile`. iOS has decoded FLAC in Core Audio since iOS 11, so the A10 uses the system decoder instead of a bundled libFLAC. That is the lower-power path on this phone.
- While a song plays, the record slides out of the jacket and turns at 33⅓ RPM. The light on the vinyl stays still. Pause freezes the platter. The screen can sleep in the library, and the spin stops when the app is backgrounded so the GPU is not burning battery behind the lock screen. Audio keeps going.
- Library is a Cover Flow stack. The wheel's angle and flick momentum move it. Crossing an angle threshold fires a Taptic tick. The center button drops the record back onto the platter.

## Controls

| Control | Playback | Library |
| --- | --- | --- |
| MENU or LIBRARY | Open the shelf. The record slides back into the jacket. | |
| Wheel drag | Volume. Clockwise turns it up. | Flip through albums, with momentum. |
| Center | Play or pause. | Play the centered album. |
| Hold center | Choose the music folder. | Choose the music folder. |
| Previous / next | Previous or next track. Previous restarts the song after 3 seconds. | Move one album. |
| Progress bar | Scrub. |  |

Lock screen controls and headphone unplug behave like a normal player.

## Add music

Open the shelf and tap **Choose Folder**, or the **Folder** label once albums are showing. You can also press and hold the center of the wheel. Pick the top folder of your library. The app reads every audio file in that folder and in the folders inside it, and keeps playing them from that location.

Cover art is taken from the file itself. If a song has no picture, the app uses `cover.jpg`, `folder.jpg`, or the only image sitting in that song's folder.

You can still copy files into **On My iPhone → Flac Player**, or into `/var/mobile/Media/FlacPlayer` on a jailbreak. A `library.path` file in Documents, one absolute path per line, adds more folders. Lines starting with `#` are ignored. Reading outside the sandbox only works if the app is installed without a sandbox (see below).

## Build

This is a UIKit app. It has to be compiled with Xcode on a Mac, or with the GitHub Action in `.github/workflows/ios.yml`. It targets iOS 14 so it runs on an iPhone 7 (newest system for that phone is iOS 15.8).

On a Mac:

```bash
make ipa
```

That writes `FlacPlayer-unsigned.ipa`.

From Windows, push the project to GitHub and run the **Build unsigned IPA** workflow, then download the artifact.

Xcode 16 can still deploy to iOS 15. If a newer Xcode refuses an iOS 14 deployment target, keep the target at or below 15.0. An iPhone 7 cannot boot a newer system than 15.8.

## Install on a jailbroken iPhone 7

iPhone 7 is an A10 device.

- **iOS 14.0–15.4.1:** TrollStore can install the unsigned IPA permanently.
- **iOS 15.x including 15.8:** palera1n, then install with TrollStore where it still applies, or with AppSync Unified / Filza.
- **Any version, no jailbreak required for playback:** Sideloadly or AltStore on Windows can re-sign the IPA with an Apple ID. A free Apple ID expires every 7 days. The sandboxed build still plays files you add with **Add Music** or the Files app.

The project does not embed private entitlements, so a normal Apple ID can sign it. To let a TrollStore or ldid install read the whole filesystem, re-sign the binary with `FlacPlayer/Jailbreak.entitlements` (`platform-application` and `com.apple.private.security.no-sandbox`). Do not turn that file on for a normal Xcode provisioning profile. The profile will be rejected.

```bash
ldid -SFlacPlayer/Jailbreak.entitlements Payload/FlacPlayer.app/FlacPlayer
```

Open the project in Xcode with `FlacPlayer.xcodeproj`, pick your team, and run it on the phone if you are signing the normal way.
