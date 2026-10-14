# avatar

[Design](../../../../docs/design/README.md) › [Iconography](../../../../docs/design/iconography/README.md) › The seal

The "pj" seal: my initials in EB Garamond Italic, light paper on a vermilion disc ringed in paper, on washi's dark paper.
Windows shows it as my account picture: on the sign-in screen, in Start and in Settings.
`avatar/` holds it at 12 sizes, from 32 to 1080 px.

![The "pj" seal: light italic letters on a vermilion disc inside a thin light ring, on dark paper.](avatar/pj-240.png)

*`avatar/pj-240.png`, rendered 2026-10-12.*

| | |
|---|---|
| Needs | nothing to show it; ImageMagick 7 and EB Garamond Italic to render it, tested 2026-10 with ImageMagick 7.1.2-31 |
| Copy alone | yes, after rendering your own letters: these are my initials |
| License | MIT |

## What it needs

- To show it on Windows: `install/windows/dram-windows/account-picture.ps1`, run as administrator.
  It set the seal on cabin-win, Windows 11, on 2026-10-12.
- To render it again: bash, ImageMagick 7's `magick`, and an EB Garamond Italic font file.
  `bin/gen-avatar.sh` takes the file named in `AVATAR_FONT`.
  Without it, the script asks fontconfig for `EB Garamond:italic` and keeps the answer if its path names Garamond and Italic.
  Failing that, it looks in the Nix store for `EBGaramond-Italic.otf` or `EBGaramond12-Italic.otf`.
- On the Mac I render it in the nixos/nix container under Colima, with the flake's own nixpkgs ([the Nix container on the Mac](../../../../decisions/log.md#d26)).
  The command is in the header of `bin/gen-avatar.sh`.
- Not needed: Nix, Home Manager or `dram`, to use the images.

## Copy it alone

1. Replace "pj" in each place it appears, since these are my initials.
   In `bin/gen-avatar.sh` that is the text at the end of the `-annotate +6-58 'pj'` line and the `pj-` of the file names it writes.
   In `account-picture.ps1` it is the `pj-$s.png` names it reads and writes, and its default `-User pj`.
2. Render your letters into a new directory:

   ```sh
   AVATAR_FONT=<EB Garamond Italic file> bash gen-avatar.sh --out <dir>
   ```

   It writes the 1080 px master and the 11 smaller sizes.
   Letters of another shape may need a new offset in `-annotate +6-58`, which moves the text 6 px right and 58 px up from the center.
3. On Windows, put the PNGs in an `avatar\` folder beside `account-picture.ps1`, and run the script as administrator, first as a dry run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File account-picture.ps1 -User <account> -DryRun
   powershell -ExecutionPolicy Bypass -File account-picture.ps1 -User <account>
   ```

   `<account>` is the account's name on that PC.
4. Lock the screen with Win+L.
   The sign-in screen shows the new picture.
5. On Linux, copy the 512 px file to `~/.face` for a greeter that reads it.

## How it is wired here

The Windows desktop role stages `avatar/` whole to `C:\ProgramData\dram\avatar\` and runs `account-picture.ps1` elevated, in phase 20 of each converge (`windows/roles/desktop.nix`).
The script copies the 11 sizes Windows keeps, 32 to 448 px and 1080 px, to `C:\Users\Public\AccountPictures\<SID>\`.
It points one `Image<size>` value per size at those files, under `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AccountPicture\Users\<SID>`, as Settings does, and skips a size whose file and value already match.
The seal as the account picture, apart from the wallpaper, was [decided 2026-10-12](../../../../decisions/log.md#d91).

The role stages the whole directory, so a file added to `avatar/` would reach Windows and change the rendered build.
`windows/build/cabin-win/inputs.json` lists the directory, and `bin/check.sh` §19 fails until `bin/render-windows.sh` runs again.
That is why this README sits one level above `avatar/`.

`pj-512.png` is meant for `~/.face` on the Arch hosts, and no module or script installs it as of 2026-10.
ly, the greeter there, shows no picture.

The committed images were rendered on 2026-10-12 in the container, with ImageMagick 7.1.2-31 from the flake's pinned nixpkgs.
There the script's last fallback applies, the Nix store, which holds nixpkgs' `eb-garamond` 0.016.
The Zebar masthead draws its own seal in CSS, and the "pj" of [the boot screens](../../../../docs/design/shell-and-bars/boot-screens.md) is a separate mark set in Fraunces.

## The drawing

| Part | In the 1080 px master | Color |
|---|---|---|
| ground | the whole square | washi's dark paper, `#1c140f` |
| disc | 494 px radius, centered | vermilion, `#c0442b` |
| ring | 448 px radius, a 9 px line | light paper, `#f3e9df` |
| letters | "pj" in EB Garamond Italic at 600 points, 6 px right of center and 58 px above it | light paper, `#f3e9df` |

The smaller sizes are Lanczos reductions of the master, and `-strip` leaves no metadata in them.

## Files

| File | What it does |
|---|---|
| `avatar/pj-1080.png` | the master, which Windows keeps as its largest size |
| `avatar/pj-<size>.png` | the reductions: 32, 40, 48, 64, 96, 192, 208, 240, 424, 448 and 512 px |
| `bin/gen-avatar.sh` | renders them |
| `install/windows/dram-windows/account-picture.ps1` | makes them the account picture on Windows |
| `windows/roles/desktop.nix` | stages `avatar/` and runs the script |

## License

MIT, Patrick Jordan.
The images show my initials, so render your own before using the seal as a picture of yourself.
EB Garamond's license, OFL-1.1, does not extend to pictures made with the font.
