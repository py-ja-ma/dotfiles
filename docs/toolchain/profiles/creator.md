# Creator

[Toolchain](../README.md) › [Profiles](README.md) › Creator

Recording tutorials takes two machines: cabin is what's on screen, and the recorder records it from a capture card.
Nothing of the recording runs on cabin's GPU, CPU or compositor, so it works the same in the Desktop and in both Gaming Modes.

| | |
|---|---|
| Code | `packages/roles/creator.txt`, `packages/roles/recording.txt`, `modules/creator.nix`, `dotfiles/.local/bin/rec`, [`dotfiles/obs/`](../../../dotfiles/obs/README.md), `system/creator-setup.sh`, `system/recording-setup.sh`, `system/v4l2loopback.conf`, `system/v4l2loopback-load.conf` |
| Runs on | cabin (creator, recording); campfire, the recorder (creator, recording), not built as of 2026-10-13; cabin-win (creator) |
| Needs | OBS Studio with obs-websocket 5, a UVC capture card, PipeWire |
| Decided in | [D93](../../../decisions/log.md#d93) for Windows' virtual camera |

| Host | Roles | What they bring |
|---|---|---|
| cabin | `creator`, `recording` | OBS as a local spare and the SRT fallback, OBS's virtual camera, asciinema, `rec`, the zoom keys |
| campfire | `creator`, `recording`, `sysadmin` | OBS that records everything; Kdenlive, Ardour, Inkscape, GIMP, Krita |
| cabin-win | `creator` | OBS with its virtual camera and background removal |

campfire has 32 GB of RAM and an NVIDIA RTX 3060, which encodes H.264 and HEVC with NVENC and has no AV1 encoder.
Its install is `install/arch-install.sh` with the desktop preset and the roles in `modules/hosts/campfire.nix`.

## How it works

```text
cabin  HDMI out ──► capture card (HDMI in) ──► recorder USB 3.2 Gen2 (10 Gbps), uvcvideo
                     card HDMI out ──► the middle monitor
cabin  audio ──► a PipeWire combine sink: headphones + the NVIDIA HDMI output (rides in the HDMI)
recorder: webcam + mic ──► OBS "Recorder": MKV, 4 tracks
          T1 mix · T2 raw mic · T3 cabin audio · T4 webcam mic
```

- The card is an Elgato Game Capture 4K X (UVC, no driver), on a 10 Gbps rear port. On `linux-lts` 6.18, check that its quirk is in: `cat /sys/bus/usb/devices/<dev>/quirks` shows `0x20000`, and `lsusb -t` shows `10000M` and `Driver=uvcvideo`.
- Only the monitor in series with the card is captured, so tutorial work stays on that monitor.
- `SUPER+CTRL+R` runs `rec toggle`. It starts or stops OBS on the recorder over obs-websocket, because OBS has no global hotkeys on Wayland. It also starts or stops the local `gpu-screen-recorder` spare on cabin, so a failed take on the card still has a copy. `rec status` says what is running.
- `SUPER+CTRL+=`, `SUPER+CTRL+-` and `SUPER+CTRL+0` drive Hyprland's cursor zoom, and the card sees it like everything else on screen.
- There is no keystroke overlay: each maintained one fails a rule (showmethekey fails Origin; wshowkeys is unmaintained). Type slowly in a large font, say the shortcut, and add keycaps in Kdenlive.

## Set it up once

On the recorder, after the first `dram apply`:

```sh
sudo bash ~/git/dotfiles/system/recording-setup.sh   # firewall: 4455 and 9000 from the creator hosts only (dram apply asks)
rec server-setup                                      # obs-websocket on, a random password; prints 3 lines
```

On cabin, put the three printed lines in `~/.config/dram/obs-websocket` and `chmod 600` it.
That file stays out of git.

In OBS on the recorder, pick Scene Collection › Recorder and Profile › Recorder, which `dram switch` seeds from `dotfiles/obs/recording/`.
Then choose the devices once:

| Source | Choose |
|---|---|
| Capture card (cabin screen) | the card under `/dev/v4l/by-id/` |
| Cabin audio (card, track 3) | the card's USB audio input |
| Webcam | the webcam under `/dev/v4l/by-id/` |
| Mic (processed and raw) | the mic or the audio interface, the same device for both sources |
| Settings › Output › Recording › Encoder | NVENC HEVC, about 20 Mbps at 1440p60 |

The mic chain on track 1 is RNNoise noise suppression, a compressor and a limiter.
Track 2 keeps the raw mic, so Kdenlive or Ardour can redo the processing.
Set each audio source's sync offset once (Advanced Audio Properties), and clap at the start of each session.

To save OBS changes back to the repo, run `rec templates-save`, review `git diff dotfiles/obs`, and commit.
`bin/check.sh` §17 refuses stream keys, passwords and home paths in those files.
`modules/creator.nix` copies the OBS files into place only when they are missing, and does not link them, because OBS replaces a file when it saves.

To send cabin's sound into the card, a PipeWire combine sink plays it to the headphones and the NVIDIA HDMI output at once, so it travels inside the HDMI signal on the video's clock.
Find the HDMI sink with `wpctl status` (an `alsa_output.pci-…hdmi…` node), then write `~/.config/pipewire/pipewire.conf.d/50-record.conf`:

```text
context.modules = [
  { name = libpipewire-module-combine-stream
    args = {
      combine.mode = sink
      node.name = "record_combine"
      node.description = "Headphones + capture card"
      combine.props = { audio.position = [ FL FR ] }
      stream.rules = [
        { matches = [ { node.name = "<the HDMI sink>" } { node.name = "<your headphones>" } ]
          actions = { create-stream = { } } }
      ]
    }
  }
]
```

Then `systemctl --user restart pipewire`, and make "Headphones + capture card" the default output.
The file lives outside the repo until the hardware exists; once the node names are known it moves into `modules/creator.nix`.

## Fallbacks

1. SRT over the LAN, with no card.
   On cabin, OBS profile Cabin › Settings › Output › Recording › Custom Output (FFmpeg): URL `srt://recorder:9000?mode=caller&latency=120000`, container `mpegts`, NVENC HEVC at 40 Mbps.
   On the recorder: `ffmpeg -i "srt://0.0.0.0:9000?mode=listener" -c copy take.mkv`.
   The mic runs on another clock, so align it with Kdenlive's *Align audio to reference*.
2. Local only: `SUPER+SHIFT+R` (gpu-screen-recorder) on cabin, then rsync the file over.

## OBS on cabin

`obs-studio` is in the creator role.
Screen capture comes through the PipeWire portal (`xdg-desktop-portal-hyprland`): add a source of type *Screen Capture (PipeWire)*.
Encoding uses NVENC from the NVIDIA driver.
Quick clips without OBS: `SUPER+SHIFT+R` (`gpu-screen-recorder`).

OBS's *Start Virtual Camera* needs the `v4l2loopback` kernel module.
`v4l2loopback-dkms` is in the creator role, built by DKMS for each installed kernel.
`system/v4l2loopback.conf` makes one device, `/dev/video10`, named "OBS Virtual Camera" with `exclusive_caps=1`, and `system/v4l2loopback-load.conf` loads it at boot; `system/maintenance.sh` installs both.

```sh
sudo pacman -S --needed v4l2loopback-dkms      # DKMS builds it for each kernel
sudo bash ~/git/dotfiles/system/maintenance.sh  # installs the two conf files, loads the module
ls /dev/video10                                 # the virtual camera
```

Then in OBS, *Start Virtual Camera*, and in Vesktop, Voice & Video › Camera › "OBS Virtual Camera".
The Vesktop Flatpak has `devices=all` for this ([Flatpak](../packaging/flatpak.md)).
After a kernel update DKMS rebuilds the module, and `dram doctor` checks that each kernel has its DKMS modules.
If `/dev/video10` is missing after a reboot, `dkms status` and `sudo modprobe v4l2loopback` say why.

On cabin-win, OBS's own virtual camera with obs-backgroundremoval 1.4.1 replaced XSplit VCam ([D93](../../../decisions/log.md#d93)).
The `obs-background-removal` unit installs the plugin from its GitHub release, pinned by SHA-256, because winget's copy is the stale 1.1.13.

## Storage and editing

A raw hour takes about 13 to 15 GB: the 1440p60 HEVC screen, the webcam and four audio tracks.
Recordings go to `/data/recordings`, its own subvolume on the data pool.
`system/creator-setup.sh`, a `dram apply` hook, gives it to the main user and links it as `~/videos/recordings`, where `SUPER+SHIFT+R`'s clips land too.
Backups are paused until the NAS ([decision 0014](../../../decisions/0014-backups-paused-until-nas.md)), so a raw take exists once: keep a second copy of anything you cannot record again.

Kdenlive with proxies edits 1440p and 4K.
Finals render with the CPU encoders (x264, x265, SVT-AV1), and NVENC is for drafts.
Ardour mixes narration, and Inkscape with GIMP makes thumbnails.
Not used: Audacity (Origin), DaVinci Resolve (not free software), NDI and DistroAV (a proprietary runtime), OBS plugins from the AUR.

## When it breaks

| Symptom | Check | Fix |
|---|---|---|
| `rec toggle` does nothing on the recorder | `rec status` | `~/.config/dram/obs-websocket` on cabin holds the three lines from `rec server-setup`; `system/recording-setup.sh` on the recorder opened 4455 to cabin's address |
| the card drops frames | `lsusb -t` shows less than `10000M` | move it to a 10 Gbps rear port |
| no virtual camera | `ls /dev/video10` | `dkms status`, then `sudo modprobe v4l2loopback` |

## Tests

- `tests/rec-websocket.py`, run by `bin/check.sh` §17 on any machine: `rec` against a mock obs-websocket v5 server, with the password challenge, start, stop, toggle, status and `server-setup`.
- On the recorder once it exists, by hand: the card checks above, a 10-minute take with all four tracks, `rec toggle` from cabin through the firewall, and a clap test for sync.

## Limits

- The recorder does not exist yet, so the card path and the SRT fallback are untested as of 2026-10-13.
