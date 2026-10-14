# obs

[Toolchain](../../docs/toolchain/README.md) › [Profiles](../../docs/toolchain/profiles/README.md) › [Creator](../../docs/toolchain/profiles/creator.md)

OBS Studio scene collections and profiles for recording tutorials: one for the machine on screen, one for the recorder.
Both record 2560×1440 at 60 fps to MKV in `/data/recordings`, with named audio tracks so an editor can redo the mix.

| | |
|---|---|
| Needs | OBS Studio with PipeWire screen capture; a UVC capture card and a webcam on the recorder; tested 2026-10 |
| Copy alone | yes, after choosing your own devices in OBS |
| License | MIT |

## What it needs

- OBS Studio on Linux, with screen capture through the PipeWire portal (`xdg-desktop-portal-hyprland` here).
- On the recorder: a capture card that speaks UVC, a webcam and a microphone, chosen once in OBS.
- A writable `/data/recordings`, or another `RecFilePath` in the profile.
- Not needed: Nix, Home Manager or `rec`. The `rec` command only starts and stops recording from the other machine.

## Copy it alone

1. Copy a scene collection to `~/.config/obs-studio/basic/scenes/`, and its profile directory to `~/.config/obs-studio/basic/profiles/`.
2. Start OBS and pick the scene collection and the profile with the same name.
3. Choose your own capture card, webcam and mic for each source: the files hold the source names, not your devices.
4. Change `RecFilePath` in the profile if `/data/recordings` does not exist.
5. Record ten seconds and check the tracks with `mediainfo`.

## How it is wired here

`modules/creator.nix` copies `creator/` on a host with the creator role and `recording/` on a host with the recording role, each file only when it is missing.
It does not link them: OBS saves through a temporary file and a rename, which would replace a link with a plain file.
`rec templates-save` copies the live files back here for a commit, and `bin/check.sh` §17 refuses a stream key, a password or a home path in this directory.
`system/creator-setup.sh` gives `/data/recordings` to the main user.
The workflow, the device choices and the recorder's firewall are on the [Creator](../../docs/toolchain/profiles/creator.md) page.

## Files

| File | What it does |
|---|---|
| `creator/scenes/Cabin.json` | the Cabin scene collection: the screen through PipeWire and desktop audio, for a local copy or the SRT fallback |
| `creator/profiles/Cabin/basic.ini` | the Cabin profile: 2560×1440 at 60 fps, MKV, track 1 the mix and track 3 the desktop audio |
| `recording/scenes/Recorder.json` | the Recorder scene collection: the capture card, cabin's audio from the card, the webcam, the processed and the raw mic, and three scenes (screen with camera, screen, camera) |
| `recording/profiles/Recorder/basic.ini` | the Recorder profile: 2560×1440 at 60 fps, MKV split by time, four named tracks (mix, raw mic, cabin audio, webcam mic) |

## License

MIT, Patrick Jordan.
