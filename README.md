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
| LIBRARY / MENU | Open the shelf. The record slides back into the jacket. | Return to the platter. |
| Wheel drag | Volume. Clockwise turns it up. | Flip through albums, with momentum. |
| Center | Play or pause. | Play the centered album. |
| Play / pause | Play or pause. | Play or pause. If nothing is loaded, play the centered album. |
| Previous / next | Previous or next track. Previous restarts the song after 3 seconds. | Move one album. |
| Progress bar | Scrub. |  |

Lock screen controls and headphone unplug behave like a normal player.

## Add music

Use **Add Music** in the app and pick files from the Files app. They are copied into this app and indexed.

Or copy files with the Files app or Filza into **On My iPhone → Flac Player**. The app watches that folder.

For a shared jailbreak folder, create `/var/mobile/Media/FlacPlayer` and put albums there. To add another folder, create `library.path` in the app's Documents folder with one absolute path per line. Lines starting with `#` are ignored. Reading outside the sandbox only works if the app is installed without a sandbox (see below).

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
