# Decision log

[Office of Records](../docs/records/README.md) › [Decisions](README.md) › Log

Every numbered decision behind this repo, D1 to D149, one section each.
A number is permanent: it is never reused or renumbered.
A superseded decision keeps its section and links the one that replaced it.
Cite a decision as `D65` in code, comments and commit subjects, and in a page as a relative link to its section, `[D65](decisions/log.md#d65)` from the repository root.
D1 to D43 came from rebuilding the Arch hosts on 2026-10-10 and 2026-10-11, D44 to D144 from bringing Windows under this repo on 2026-10-12 and 2026-10-13, D145 to D148 record choices of the same days that had no number, and D149 the games that left cabin-win on 2026-10-19.
The architecture decision records beside this page explain the larger choices, and [the index](README.md) lists them with every open decision.
Per-package verdicts and the dates of their waivers live in `packages/register.tsv`.

## Log

### D1

Every package passes three rules (FOSS, Origin, Community) or carries a signed waiver with a re-check date.

Decided 2026-10-10 · Security › Software supply · [ADR 0013](0013-software-rules-and-waivers.md)

### D2

Before the rebuild began, master took the merged fixes of the 2026-10-07 review, and the review's merged branches were deleted.
The branch holding the vendored lib32 wine libraries stayed unmerged until [D31](#d31) dropped them.

Decided 2026-10-10 · Operations › Releases & pushes · a one-off action

### D3

LUKS2 encrypts the laptop's disk only, unlocked by TPM2 with a PIN and backed by a recovery key.
The desktops are not encrypted.

Decided 2026-10-10 · Security › Boot trust · [ADR 0011](0011-disk-boot-secure-boot-snapshots.md)

### D4

The editor is VSCodium with Open Remote - SSH, not Microsoft's VS Code.

Decided 2026-10-10 · Toolchain › Development · [ADR 0013](0013-software-rules-and-waivers.md), `packages/register.tsv` (`vscodium-bin`)

### D5

A Markdown vault in git, edited with Zettlr, replaces Obsidian, which is proprietary.
The swap was made on 2026-10-11, after a trial on a copy of the notes.

Decided 2026-10-10 · Toolchain › Profiles · [ADR 0013](0013-software-rules-and-waivers.md), `templates/office/`, `packages/register.tsv` (`obsidian`, `zettlr`)

### D6

Signed FOSS waivers until 2027-10-10 cover Steam, the NVIDIA userspace, firmware and microcode, Spotify, the Jagex Launcher, the Discord service behind Vesktop, nmap, and CUDA with cuDNN for the opt-in ml-cuda role.
Tools a course requires carry a waiver for the length of their term.

Decided 2026-10-10 · Security › Software supply · [ADR 0013](0013-software-rules-and-waivers.md), `packages/register.tsv` (the `waiver` rows)

### D7

Every confirmed Origin failure was swapped out: fastfetch, Papirus, 7-Zip and unrar, ipmitool, qt6ct, Rizin and Cutter.

Decided 2026-10-10 · Security › Software supply · [ADR 0013](0013-software-rules-and-waivers.md), `packages/register.tsv` (`fastfetch`, `papirus-icon-theme`, `7zip`, `unrar`, `ipmitool`, `qt6ct`, `rizin`)

### D8

There is no modchip for the Switch Lite and no Switch emulator on these machines.

Decided 2026-10-10 · Toolchain › Profiles · [ADR 0016](0016-emulation-set-and-flatpak.md)

### D9

The system layer converges with `dram apply`: a host's roles declare its packages, units and files, and the command makes the host match them.
An image-based A/B system is left for a trial in 2027.

Decided 2026-10-10 · Platforms › Arch Linux · [ADR 0008](0008-system-layer-converge.md), `dotfiles/.local/bin/dram`

### D10

cabin builds and signs the `[dram]` repo, with the key made at the fresh start ([D147](#d147)), not the old one restored from its offline export.

Decided 2026-10-10, amended by [D147](#d147) on 2026-10-11 · Toolchain › Packaging · [ADR 0005](0005-own-package-repo.md)

### D11

Windows 11 was to be reinstalled alone on cabin's SATA disk, with the NVMe drives unplugged.
Windows kept its install instead, and its boot files moved to an ESP of its own on its disk ([D65](#d65)).

Superseded by [D65](#d65) on 2026-10-12 · Platforms › Windows · [ADR 0017](0017-cabin-bench-layout.md)

### D12

The plan was borgbackup on the Mac for a restore test, and an encrypted second copy on an external disk, both before the wipe.
The fresh start dropped the pre-wipe run, so neither was needed ([D147](#d147)).

Superseded by [D147](#d147) on 2026-10-11 · Operations › Backups · [ADR 0014](0014-backups-paused-until-nas.md)

### D13

When a project's origin is unclear because its leads publish no location, I rule on it case by case, judging the people who lead the commits; an accepted project becomes `pass-flag`.
The first rulings accepted yazi, strace, SageMath, Logisim-evolution and the emulator group.

Decided 2026-10-10 · Security › Software supply · [ADR 0013](0013-software-rules-and-waivers.md), `packages/register.tsv` (the `pass-flag` rows)

### D14

A license the FSF calls free passes the FOSS rule even when the OSI has not listed it, as ly's WTFPL and vim's license do.
nmap's NPSL is neither, so nmap carries a waiver ([D6](#d6)).

Decided 2026-10-10 · Security › Software supply · [ADR 0013](0013-software-rules-and-waivers.md), `packages/register.tsv` (`ly`, `vim`, `nmap`)

### D15

Arch is installed by the repo's own pacstrap script, not archinstall.
It installs to one disk chosen by id and a typed serial, refuses NTFS and BitLocker disks, and uses a pinned ISO and a shipped mirror list.

Decided 2026-10-10 · Platforms › Arch Linux · [ADR 0010](0010-install-path.md), `install/arch-install.sh`

### D16

Every kernel boots as a signed UKI, and each snapshot has a signed UKI of its own behind systemd-boot.
Since 2026-10-12 rEFInd is the themed menu in front of that chain, and systemd-boot keeps the snapshot and fallback entries.

Decided 2026-10-10, amended on 2026-10-12 · Platforms › Arch Linux · [ADR 0011](0011-disk-boot-secure-boot-snapshots.md)

### D17

Desktops get two btrfs pools, /home gets light snapshots, and snapper keeps 12 snapshots plus 6 marked important.
The laptop hibernates.

Decided 2026-10-10 · Platforms › Arch Linux · [ADR 0011](0011-disk-boot-secure-boot-snapshots.md), `install/arch-install.sh`, `system/snapper/`

### D18

NVIDIA's open kernel modules come prebuilt for each kernel (`nvidia-open`, `nvidia-open-lts`), not built by DKMS.

Decided 2026-10-10 · Platforms › Arch Linux · [ADR 0011](0011-disk-boot-secure-boot-snapshots.md), `packages/gpu-nvidia.txt`

### D19

ly offers the desktop, Gaming Mode on Hyprland with Steam's Big Picture, which is the default Gaming Mode, and Gaming Mode on gamescope.
Decky is not installed, and Proton-GE is opt-in.

Decided 2026-10-10 · Toolchain › Profiles · [ADR 0012](0012-gaming-mode.md), `pkgs/dram-gaming-mode/`

### D20

Homebrew that runs on a console, and never on these PCs, is outside the three rules.
It shares its ruling with [D8](#d8).

Decided 2026-10-10 · Toolchain › Profiles · [ADR 0016](0016-emulation-set-and-flatpak.md)

### D21

Reverse engineering uses radare2 and Ghidra.
Rizin and Cutter left with the Origin swaps ([D7](#d7)).

Decided 2026-10-10 · Toolchain › Profiles · `packages/roles/re-lab.txt`, `packages/register.tsv` (`radare2`, `ghidra`, `rizin`)

### D22

Containers are rootless Podman on the hosts, Docker is an opt-in role, and the Mac runs Colima instead of Docker Desktop.

Decided 2026-10-10 · Toolchain › Development · [ADR 0015](0015-containers-podman.md), `packages/roles/docker.txt`

### D23

Machine learning uses PyTorch managed by uv, llama.cpp, and Jupyter in uv, with CUDA as an opt-in role under a waiver.
Only model weights on the ml role's allowlist are downloaded.

Decided 2026-10-10 · Toolchain › Development · `packages/roles/ml.txt`, `modules/ml.nix`

### D24

The office role keeps accounts in hledger, imports bank CSV files first, and gives the phone no access.
The vault's git remote is a bare repository on the Mac until the NAS exists.

Decided 2026-10-10 · Toolchain › Profiles · `modules/office.nix`, `dotfiles/.local/bin/office-init`, `templates/office/`

### D25

`dram apply` reports undeclared packages and removes them only when asked, and the old `apply-packages.sh` script is retired.
The snapshot hooks are the repo's own: snap-pac failed the Community rule and was replaced before the first rebuild.

Decided 2026-10-10, amended on 2026-10-11 · Platforms › Arch Linux · [ADR 0008](0008-system-layer-converge.md), [ADR 0011](0011-disk-boot-secure-boot-snapshots.md), `system/hooks/00-dram-snap-pre.hook`

### D26

`nix flake check` runs on the Mac in a throwaway `nixos/nix` container under Colima.
Since 2026-10-12 the Windows render runs there too.

Decided 2026-10-10 · Operations › Quality · `flake.nix`, `bin/render-windows.sh`

### D27

The plan was an sbctl rehearsal on the old cabin install before the wipe, to show that the GPU's option ROM survives with Microsoft's keys enrolled.
The fresh start dropped the pre-wipe run ([D147](#d147)).

Superseded by [D147](#d147) on 2026-10-11 · Security › Boot trust · [ADR 0011](0011-disk-boot-secure-boot-snapshots.md)

### D28

Emulation installs the compliant equivalent of what EmuDeck includes.

Decided 2026-10-10 · Toolchain › Profiles · [ADR 0016](0016-emulation-set-and-flatpak.md), `packages/roles/emulation.txt`

### D29

An emulator that Arch's extra repository lacks comes from a Flathub-verified Flatpak, or from `[dram]` when no verified build exists.

Decided 2026-10-10 · Toolchain › Profiles · [ADR 0016](0016-emulation-set-and-flatpak.md), `packages/flatpak/emulation.txt`

### D30

Projects that failed the Community rule were swapped: wlogout for a rofi power menu, iwgtk for NetworkManager, paru off the hosts, Bibata for the Adwaita cursors, ble.sh dropped, picocom for minicom, wireless_tools for iw, and unzip for libarchive.
unzip came back on 2026-10-12 as winetricks' dependency alone ([D146](#d146)).

Decided 2026-10-10 · Security › Software supply · [ADR 0013](0013-software-rules-and-waivers.md), `packages/register.tsv` (`wlogout`, `iwgtk`, `paru`, `bibata-cursor-theme`, `blesh`, `picocom`, `unzip`)

### D31

The twelve vendored lib32 wine libraries and lib32-pipewire-jack left `pkgs/`.
Gaming Mode does not need them.

Decided 2026-10-11 · Toolchain › Packaging · `pkgs/manifest.txt`

### D32

ES-DE is not installed: it needs FreeImage, which Arch moved to the AUR and whose last release, from 2018, has open CVEs.
Steam ROM Manager adds the games to Steam instead, and ES-DE comes back for a new decision if it drops FreeImage.

Decided 2026-10-11 · Toolchain › Profiles · [ADR 0016](0016-emulation-set-and-flatpak.md), `packages/flatpak/emulation.txt`

### D33

The free libretro cores (Mesen, bsnes, Beetle PSX, BlastEm and the rest) fall under the RetroArch group ruling, without a ruling each.

Decided 2026-10-11 · Toolchain › Profiles · [ADR 0016](0016-emulation-set-and-flatpak.md)

### D34

On a desktop, pam_u2f is required, so sudo over SSH fails there: the key has to be at the machine.
Headless hosts keep password sudo behind an SSH login that needs a YubiKey.

Decided 2026-10-11 · Security › Identity · [ADR 0019](0019-yubikeys.md)

### D35

sudo, polkit, ly, the console and hyprlock each ask for a YubiKey touch.

Decided 2026-10-11 · Security › Identity · [ADR 0019](0019-yubikeys.md), `system/yubikey-setup.sh`

### D36

SSH keys are resident ed25519-sk keys on the YubiKeys, used with a touch and no PIN.

Decided 2026-10-11 · Security › Identity · [ADR 0019](0019-yubikeys.md), `keys/ssh.pub`

### D37

lantern's disk unlocks with TPM2 and a PIN, or with either YubiKey as the backup.

Decided 2026-10-11 · Security › Boot trust · [ADR 0019](0019-yubikeys.md), `system/fido2-enroll.sh`

### D38

age-plugin-yubikey is accepted as `pass-flag`, so the sops key can live on a YubiKey.

Decided 2026-10-11 · Security › Identity · [ADR 0019](0019-yubikeys.md), `packages/register.tsv` (`age-plugin-yubikey`)

### D39

OTP over USB is turned off on the YubiKeys.

Decided 2026-10-11 · Security › Identity · [ADR 0019](0019-yubikeys.md)

### D40

The fleet uses one pam_u2f origin, `pam://dram`.

Decided 2026-10-11 · Security › Identity · [ADR 0019](0019-yubikeys.md), `system/pam-u2f.conf`

### D41

pam_u2f lets a login through when its root-owned state is missing (`nouserok`, `module_unknown=ignore`), and `dram doctor` warns about it.

Decided 2026-10-11 · Security › Identity · [ADR 0019](0019-yubikeys.md)

### D42

The TPM PIN and the FIDO2 PIN are separate, and the keys stay unplugged at boot.

Decided 2026-10-11 · Security › Identity · [ADR 0019](0019-yubikeys.md)

### D43

The Mac (lodge) stays out of the YubiKey setup and keeps its software SSH key in the hosts' `authorized_keys`.

Decided 2026-10-11 · Platforms › macOS · [ADR 0019](0019-yubikeys.md)

### D44

On 2026-10-12 cabin's Windows was set up first and its Arch second.

Decided 2026-10-12 · Platforms › Windows · a one-off action

### D45

Chat (Mumble, IRC and TeamSpeak) belongs on every declarative build, as the apps only, with no servers configured.
Windows has the chat role; Arch's chat list is still to be written.

Decided 2026-10-12 · Toolchain › Profiles · `packages/winget/chat.txt`

### D46

TeamSpeak carries a FOSS waiver on every build until 2027-10-12, as part of the chat role.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`winget:TeamSpeakSystems.TeamSpeakClient`)

### D47

The external drive eva is tidied and never wiped.
Its 2.5 TB of old Linux trash was emptied once its contents were copied.

Decided 2026-10-12 · Operations › Backups · `system/backup-eva.sh`

### D48

No machine restarts while a copy to or from the old drives runs.

Decided 2026-10-12 · Operations › Backups · a one-off rule for the copies of 2026-10-12

### D49

No game was copied from the old Arch Steam library: Steam downloads again whatever is still played.

Decided 2026-10-12 · Operations › Backups · a one-off action

### D50

The old drives are wiped once everything on them is extracted.
The old Windows SSD (the SSK) becomes a spare, and the old Crucial P2 a local borg target.

Decided 2026-10-12 · Operations › Backups · [ADR 0014](0014-backups-paused-until-nas.md)

### D51

Steam does not start at sign-in on Windows.

Decided 2026-10-12 · Platforms › Windows · [ADR 0026](0026-clean-windows.md), `install/windows/dram-windows/autostart.ps1`

### D52

Windows roles carry Arch's role names, plus chat.
Dual-boot and laptop settings are host shape, set in the host file or by detection.

Decided 2026-10-12 · Platforms › Windows · [ADR 0020](0020-windows-from-the-flake.md), `windows/roles/`

### D53

The profiles map to roles: desktop to `desktop`, gaming to `gaming` and `creator`, work to `office` and `college`, finance to `office`, coding to `dev`, homelab to `sysadmin` with `docker` on request, and chat to `chat`.
thermos also takes `re-lab`.

Decided 2026-10-12 · Toolchain › Profiles · `packages/roles/`, `windows/roles/`

### D54

In the WSL clone, containers are rootless Podman, and the Docker engine comes only with the docker role.
Neither Docker Desktop nor Podman Desktop is installed, and Colima stays on the Mac.

Decided 2026-10-12 · Platforms › WSL clone · [ADR 0021](0021-wsl-clone.md)

### D55

VSCodium runs natively on Windows and reaches the clone through Open Remote - SSH, not Open Remote - WSL.

Decided 2026-10-12 · Platforms › WSL clone · [ADR 0021](0021-wsl-clone.md), `windows/units/vscodium-open-remote-ssh.ps1`

### D56

The clone has no k3s; kind makes throwaway clusters there.

Decided 2026-10-12 · Platforms › WSL clone · [ADR 0021](0021-wsl-clone.md)

### D57

Toolchains and npm live in the clone.
Native Node LTS, rustup or Go go on Windows only for Windows targets.

Decided 2026-10-12 · Platforms › WSL clone · [ADR 0021](0021-wsl-clone.md)

### D58

git lives only in the clone, and Git for Windows is not installed.

Decided 2026-10-12 · Platforms › WSL clone · [ADR 0021](0021-wsl-clone.md), `packages/register.tsv` (`winget:Git.Git`)

### D59

`debloat.ps1` and `autostart.ps1` declare what Windows must not have: the removed apps, the stopped services and the startup entries left off.

Decided 2026-10-12 · Platforms › Windows · [ADR 0026](0026-clean-windows.md), `install/windows/dram-windows/debloat.ps1`, `install/windows/dram-windows/autostart.ps1`

### D60

On cabin-win, sshd starts automatically and takes keys only once the Store's Spotify has installed over a key login.
On thermos, sshd starts by hand, answers only private networks and the local subnet, and takes keys only.

Decided 2026-10-12 · Security › Identity · set on each PC; `install/windows/dram-windows/autostart.ps1` keeps sshd running

### D61

The Windows swaps and the never-add list are `fail` rows in the register, so `bin/check-register.py` refuses them.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (the Windows `fail` rows), `bin/check-register.py`

### D62

Windows runs no emulators, except Xenia Canary if I want it.

Decided 2026-10-12 · Toolchain › Profiles · `packages/winget/` (no emulation list)

### D63

Windows is rendered from the flake: `windows/` describes each PC, and `winget configure` applies the result.

Decided 2026-10-12 · Platforms › Windows · [ADR 0020](0020-windows-from-the-flake.md)

### D64

On a PC the build lives in `C:\ProgramData\dram` and arrives only by an explicit push.
A PC follows the main channel while the renderer settles, then stable, and neither Ansible nor WinUtil's data is used.

Decided 2026-10-12 · Platforms › Windows · [ADR 0020](0020-windows-from-the-flake.md), `bin/push-windows.sh`, `install/windows/dram-windows/dram.ps1`

### D65

Windows boots from its own ESP on the MX500, made in place: WinRE rebuilt after a slightly shrunk C:, the new ESP last on the disk, and `bcdboot` pointed at it.
Arch's ESP keeps no Windows files once Windows has booted from its own.

Decided 2026-10-12 · Platforms › Windows · [ADR 0023](0023-windows-own-esp-and-boot-order.md), `install/windows/dram-windows/own-esp.ps1`, `system/windows-esp-retire.sh`

### D66

Windows starts only from its own firmware entry, and rEFInd never chain-loads `bootmgfw.efi`.

Decided 2026-10-12 · Platforms › Arch Linux · [ADR 0023](0023-windows-own-esp-and-boot-order.md), `system/apply-refind.sh`

### D67

Every OS keeps rEFInd first in the boot order, and Arch owns the firmware's boot variables.

Decided 2026-10-12 · Platforms › Windows · [ADR 0023](0023-windows-own-esp-and-boot-order.md), `install/windows/dram-windows/boot-guard.ps1`, `windows/units/boot-guard-task.ps1`

### D68

Windows takes Arch's and the bench's disks offline one by one, and never by a SAN policy that would take every disk offline, eva included.

Decided 2026-10-12 · Platforms › Windows · [ADR 0023](0023-windows-own-esp-and-boot-order.md)

### D69

Windows opts out of changing Secure Boot, the firmware and the boot order: the Firmware device class is denied, the boot guard runs, and Windows' servicing task stays on.

Decided 2026-10-12 · Security › Boot trust · [ADR 0023](0023-windows-own-esp-and-boot-order.md), `windows/hosts/cabin-win.nix`

### D70

Proposed: restore cabin's dbx from Arch, after a preflight over every binary on the ESPs, before BitLocker and before the anti-cheat tests.

Open since 2026-10-12 · Security › Boot trust · [ADR 0024](0024-secure-boot-custody.md)

### D71

Proposed: either Arch's KEK alone, so that only Arch can change db and dbx, or Arch's KEK beside Microsoft's, with Windows' opt-outs and detection.
The recommendation is Arch's alone, kept only if League still runs afterwards.

Open since 2026-10-12 · Security › Boot trust · [ADR 0024](0024-secure-boot-custody.md)

### D72

Proposed: keep `PK.key` and `KEK.key` offline, and bring them back to cabin only for a db or KEK change.
Encrypting cabin's disk is a separate question.

Open since 2026-10-12 · Security › Boot trust · [ADR 0024](0024-secure-boot-custody.md)

### D73

cabin's MSI firmware is updated by M-Flash only, with IOMMU, SVM and NX on, and Arch boots first after any firmware update.

Decided 2026-10-12 · Security › Boot trust · [ADR 0023](0023-windows-own-esp-and-boot-order.md)

### D74

Proposed: Memory Integrity on cabin-win only when Vanguard's on-demand mode or FACEIT needs it, after timing games with it on and off.

Open since 2026-10-12 · Security › Boot trust · [ADR 0024](0024-secure-boot-custody.md)

### D75

Proposed: BitLocker on cabin-win as the last step, with its recovery key in Proton Pass and its PCR profile checked.

Open since 2026-10-12 · Security › Boot trust · [ADR 0024](0024-secure-boot-custody.md)

### D76

Enforcing Microsoft's BlackLotus revocations waits until a Windows install medium signed with the 2023 certificates exists.

Decided 2026-10-12 · Security › Boot trust · [ADR 0024](0024-secure-boot-custody.md)

### D77

Proposed: Arch in WSL 2 as a clone of the Arch user layer (`form = "wsl"`), built from the repo and not copied from a disk, without `wsl --mount`.
It is built and runs as cabin-wsl; its acceptance is pending.

Open since 2026-10-12 · Platforms › WSL clone · [ADR 0021](0021-wsl-clone.md)

### D78

Proposed: cabin-wsl comes first as a disposable proving ground, then thermos-wsl, and machine learning stays on cabin's Arch.
cabin-wsl is built and runs.

Open since 2026-10-12 · Platforms › WSL clone · [ADR 0021](0021-wsl-clone.md)

### D79

In WSL, the keys reach the clone through a bridge to Windows' SSH agent by default, and through usbipd when the YubiKey itself is needed.

Decided 2026-10-12 · Security › Identity · [ADR 0021](0021-wsl-clone.md), `install/windows/dram-windows/wsl.ps1`

### D80

The clone's `.wslconfig` values are fixed in the repo.

Decided 2026-10-12 · Platforms › WSL clone · [ADR 0021](0021-wsl-clone.md), `install/windows/wslconfig`

### D81

Proposed: on the bench disk each OS gets its own ESP, Arch keeps the firmware's boot variables, installs run in a VM first, and the order is Debian, NixOS, then Fedora 45.

Open since 2026-10-12 · Platforms › Bench OSes · [ADR 0017](0017-cabin-bench-layout.md)

### D82

Proposed: NixOS signs its boot files with its own db key.

Open since 2026-10-12 · Platforms › Bench OSes · [ADR 0017](0017-cabin-bench-layout.md)

### D83

The bench OSes start on nouveau for the GPU.

Decided 2026-10-12 · Platforms › Bench OSes · [ADR 0017](0017-cabin-bench-layout.md)

### D84

Windows takes its look from Arch's palettes: `bin/gen-windows-look.py` writes the files and `look.ps1` applies them.

Decided 2026-10-12 · Design › Themes · [ADR 0025](0025-one-look-on-every-os.md), `bin/gen-windows-look.py`

### D85

Windows installs the house fonts machine-wide from `install/windows/fonts.pin`.

Decided 2026-10-12 · Design › Typography · [ADR 0025](0025-one-look-on-every-os.md)

### D86

The terminal and the prompt look as they do on Arch.
Opacity stays at 100 and the grain stays off until both are tested.

Decided 2026-10-12 · Design › Shell & bars · [ADR 0025](0025-one-look-on-every-os.md), `windows/units/conhost-letterpress.ps1`

### D87

Every app that can take the look gets it, and nothing patches the taskbar or Start.

Decided 2026-10-12 · Design › Themes · [ADR 0025](0025-one-look-on-every-os.md)

### D88

Windows used its Windows Black pointer, played no sounds and showed a clear sign-in screen.
The Adwaita pointer replaced Windows Black ([D132](#d132)); the sounds and the sign-in screen stand.

Superseded by [D132](#d132) on 2026-10-12 · Design › Iconography · [ADR 0025](0025-one-look-on-every-os.md)

### D89

My Windows account has the Russian keyboard layout beside English, and the sign-in screen keeps English only.

Decided 2026-10-12 · Design › Shell & bars · [ADR 0025](0025-one-look-on-every-os.md), `windows/units/keyboard-us-ru.ps1`

### D90

Proposed: HackBGRT from Arch, as a signed `[dram]` package on Windows' ESP with its own boot entry, added before BitLocker, kept only if Vanguard accepts it, and dropped if I play FACEIT.

Open since 2026-10-12 · Security › Boot trust · [ADR 0024](0024-secure-boot-custody.md)

### D91

The "pj" seal is the account picture on Windows and `~/.face` on Arch.

Decided 2026-10-12 · Design › Iconography · [ADR 0025](0025-one-look-on-every-os.md), `bin/gen-avatar.sh`, `install/windows/dram-windows/account-picture.ps1`

### D92

Riot Client, League of Legends and Vanguard stay on cabin-win under a waiver of the Origin and FOSS rules, re-checked 2027-10-12.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`manual:riot-client`), [ADR 0013](0013-software-rules-and-waivers.md)

### D93

XSplit VCam was swapped for OBS's virtual camera with obs-backgroundremoval.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`winget:OBSProject.OBSStudio`), `windows/units/obs-background-removal.ps1`

### D94

The Epic Games Launcher is accepted with an Origin flag: Tencent holds about 28 % of Epic, without control.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`winget:EpicGames.EpicGamesLauncher`)

### D95

Easy Anti-Cheat is accepted as part of the games that ship it.

Decided 2026-10-12 · Security › Software supply · no row of its own: it comes inside its games

### D96

Ubisoft Connect is accepted with an Origin flag.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`manual:ubisoft-connect`), `windows/units/ubisoft-connect.ps1`

### D97

The EA app with EA Javelin carries a FOSS waiver on cabin-win until 2027-10-12.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`winget:ElectronicArts.EADesktop`)

### D98

Battle.net carries a FOSS waiver on cabin-win until 2027-10-12.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`manual:battle.net`), `windows/units/battle-net.ps1`

### D99

The Hytale launcher carries a FOSS waiver until 2027-10-12.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`winget:HypixelStudios.Hytale`)

### D100

GeForce NOW is dropped, and `debloat.ps1` removes it.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`winget:Nvidia.GeForceNow`), `install/windows/dram-windows/debloat.ps1`

### D101

Proposed: the FACEIT client and its anti-cheat get a waiver only if I play FACEIT.

Open since 2026-10-12 · Security › Software supply · no register row until then

### D102

The waivers for Steam, the Jagex Launcher, Spotify and the NVIDIA userspace extend to Windows with the same dates.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`winget:Valve.Steam`, `manual:jagex-launcher`, `msstore:9NCBCSZSJRSB`, `manual:nvidia-app`)

### D103

RuneLite is accepted as `pass-flag`.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`winget:RuneLite.RuneLite`)

### D104

Transmission replaces qBittorrent, whose origin is unclear.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`winget:qBittorrent.qBittorrent`, `winget:Transmission.Transmission`)

### D105

VLC is accepted with an Origin flag, as SageMath was: VideoLAN is French, and one of its leads lists Hong Kong.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`winget:VideoLAN.VLC`)

### D106

File Converter is dropped: it failed the Community rule.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`winget:AdrienAllard.FileConverter`)

### D107

Proposed: rule on NAPS2's unclear origin, or scan without it through the scanner's driverless mode.

Open since 2026-10-12 · Security › Software supply · no register row yet

### D108

Git for Windows and its mingw-w64 toolchain are not installed, and git lives in the WSL clone.
A mingw runtime that ships inside an app belongs to that app ([D143](#d143)).

Decided 2026-10-12, amended by [D143](#d143) on 2026-10-12 · Security › Software supply · `packages/register.tsv` (`winget:Git.Git`), [ADR 0021](0021-wsl-clone.md)

### D109

Proposed: the MSVC Build Tools only if I build Windows binaries.

Open since 2026-10-12 · Security › Software supply · no register row yet

### D110

Npcap is not installed: its license is its own, and the nmap waiver does not cover it.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`manual:npcap`, `winget:Insecure.Nmap`)

### D111

Proposed: System Informer replaces the Sysinternals tools, and Autoruns and Process Monitor get a waiver only if I use them.

Open since 2026-10-12 · Security › Software supply · `packages/register.tsv` (`winget:WinsiderSS.SystemInformer`)

### D112

Proposed: a waiver for Lenovo's BIOS and EC firmware on thermos, until thermos retires.

Open since 2026-10-12 · Security › Software supply · no register row yet

### D113

Proposed: thermos runs without Lenovo's power manager, Base Utility and thermal drivers, and a waiver is signed only for what turns out to be missed.

Open since 2026-10-12 · Security › Software supply · no register row yet

### D114

Closed tools and drivers that an employer hands out are left out of the package lists.
One comes back only under the work-mandated waiver class ([D128](#d128)).

Decided 2026-10-13 · Security › Software supply · `packages/register.tsv`

### D115

Epson's software and the Access Runtime are not installed: the printer works driverless, and mdbtools in the WSL clone reads Access files.

Decided 2026-10-12 · Security › Software supply · no register rows: nothing installs them

### D116

Proposed: RustDesk is dropped, Moonlight comes only with Sunshine, and the microphone is tested without the Fortemedia driver.

Open since 2026-10-12 · Security › Software supply · no register rows yet

### D117

Proposed: efitools gets a Community waiver for the boot-trust scripts alone, re-checked in 2027-10, so the repo needs no cryptography code of its own.

Open since 2026-10-12 · Security › Software supply · [ADR 0024](0024-secure-boot-custody.md)

### D118

Proposed: usbipd-win gets a waiver until 2027-10-12, if usbip is used.

Open since 2026-10-12 · Security › Software supply · `packages/register.tsv` (`winget:dorssel.usbipd-win`), [ADR 0021](0021-wsl-clone.md)

### D119

Proposed: the TeamSpeak 6 Flatpak on the bench falls under TeamSpeak's waiver ([D46](#d46)).

Open since 2026-10-12 · Security › Software supply · no register row yet

### D120

Proposed: the NVIDIA userspace waiver widens to the bench, and to WSL if the clone takes the ml role.

Open since 2026-10-12 · Security › Software supply · no register row yet

### D121

Proposed: the Windows 11 waiver ([D148](#d148)) also covers the FOSS rule for the closed Windows apps I accepted, never an Origin failure, and not Sysinternals, MSVC or Epson's software.

Open since 2026-10-12 · Security › Software supply · [ADR 0013](0013-software-rules-and-waivers.md)

### D122

Every app in the Windows catalogue has a register row: `pass` for the apps that passed, such as PrismLauncher, Vortex, Mumble and Halloy, and `fail` for the never-add list.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv`

### D123

The case display runs my own code on both OSes: `dram-case-display` on Arch, and `case-display.ps1` with LibreHardwareMonitor on Windows.
The vendor's iUnity service is removed.

Decided 2026-10-12 · Design › Shell & bars · [ADR 0027](0027-case-display.md), `pkgs/dram-case-display/`, `install/windows/dram-windows/case-display.ps1`

### D124

PawnIO, the kernel driver that LibreHardwareMonitor needs to read the CPU temperature, is accepted as `pass-flag`.

Decided 2026-10-12 · Security › Software supply · [ADR 0027](0027-case-display.md), `packages/register.tsv` (`winget:namazso.PawnIO`)

### D125

Withdrawn; the number is not reused.

Withdrawn 2026-10-14 · Security

### D126

Withdrawn; the number is not reused.

Withdrawn 2026-10-14 · Security

### D127

GnuPG never starts scdaemon: the YubiKeys' PIV is reached through pcscd by age-plugin-yubikey and ykman, and scdaemon would hold the reader for itself.

Decided 2026-10-12 · Security › Identity · [ADR 0019](0019-yubikeys.md), `modules/desktop.nix`

### D128

Proposed: a work-mandated waiver class, like the course-mandated one ([D6](#d6)), for closed tools an employer requires.
Each waiver would cover one tool for one job, named by the employer, and never an Origin failure.

Open since 2026-10-12 · Security › Software supply · [ADR 0013](0013-software-rules-and-waivers.md)

### D129

Withdrawn; the number is not reused.

Withdrawn 2026-10-14 · Security

### D130

Windows has a Zebar top bar on each monitor, generated from washi's palette and Waybar's layout.
The taskbar hides at the bottom, and policies declutter Start and Explorer.

Decided 2026-10-12 · Design › Shell & bars · [ADR 0025](0025-one-look-on-every-os.md), `install/windows/letterpress/zebar/`

### D131

GlazeWM would tile windows on Windows, but it is held: its IPC on `127.0.0.1:6123` accepts any WebSocket without an Origin check and runs `shell-exec`, so a web page could start programs.
It is checked again once glzr-io/glazewm#1443 ships.

Held since 2026-10-12 · Design › Shell & bars · [ADR 0025](0025-one-look-on-every-os.md), `packages/register.tsv` (`winget:glzr-io.glazewm`)

### D132

Arch and Windows use one pointer: Adwaita, from GNOME's own Windows build, pinned by sha256.

Decided 2026-10-12 · Design › Iconography · [ADR 0025](0025-one-look-on-every-os.md), `install/windows/cursors.pin`

### D133

Windhawk is a register `fail`: its engine injects into every process, and Vanguard reports errors with it.
It is revisited at Windhawk 2.0 in inclusion-only mode, after a test with League.

Decided 2026-10-12 · Platforms › Windows · [ADR 0026](0026-clean-windows.md), `packages/register.tsv` (`winget:RamenSoftware.Windhawk`)

### D134

WinUtil never runs on cabin-win: its reset deletes `HKLM\SOFTWARE\Policies`, and its service tweaks once set Vanguard's `vgc` to Manual.
Its 15 useful items are adopted as declared units.

Decided 2026-10-12 · Platforms › Windows · [ADR 0026](0026-clean-windows.md)

### D135

No system file is ever changed for an icon: `SfcIsFileProtected` is checked before every write, and system icons change only through registry overrides.

Decided 2026-10-12 · Design › Iconography · [ADR 0025](0025-one-look-on-every-os.md), `install/windows/dram-windows/icons.ps1`

### D136

AutoHotkey is off cabin-win: ARC Raiders' anti-cheat treats it as a detection, and nothing in the build uses it.

Decided 2026-10-12 · Platforms › Windows · [ADR 0026](0026-clean-windows.md), `packages/register.tsv` (`winget:AutoHotkey.AutoHotkey`)

### D137

Each display runs at its highest refresh rate: 165 Hz on DisplayPort and 144 Hz on HDMI, as on Arch.
G-SYNC Compatible is ticked once by hand, without NVIDIA Profile Inspector, which ARC Raiders flags.

Decided 2026-10-12 · Design › Shell & bars · [ADR 0025](0025-one-look-on-every-os.md)

### D138

Marvel Rivals stays on cabin-win under a waiver, as League does ([D92](#d92)), re-checked 2027-10-12.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`manual:marvel-rivals`)

### D139

Clock, Sound Recorder, Media Player and Camera are removed from Windows, and the vermilion title bars stay.
KiCad and LibreOffice are `pass-flag`, NixOS-WSL is struck from the plan for one flake on every machine ([ADR 0018](0018-one-flake-every-machine.md)), and Windows repaired itself while idle.

Decided 2026-10-12 · Platforms › Windows · [ADR 0026](0026-clean-windows.md), `install/windows/dram-windows/debloat.ps1`

### D140

The flake renders cabin-win and `dram.ps1` applies the render, the look included: fonts, icons, the bar and the pointer.
This accepted [D63](#d63).

Decided 2026-10-12 · Platforms › Windows · [ADR 0020](0020-windows-from-the-flake.md), `windows/hosts/cabin-win.nix`

### D141

The WSL clones take the terminal halves of office and college (hledger, Taskwarrior, zk, TeX Live, Typst, Octave, the HDL and AVR toolchains), and their GUIs stay native on Windows.
tshark joins sysadmin, and Home Manager makes Rust stable rustup's default.

Decided 2026-10-12 · Platforms › WSL clone · [ADR 0021](0021-wsl-clone.md)

### D142

cabin-win denies WCH's USB-serial driver by device id: vendor 1A86's CH340, CH340K, CH341, CH342, CH343 and CH9102.
thermos keeps the driver for its re-lab work over usbipd, and on Arch the kernel's own driver serves the chips.

Decided 2026-10-12 · Platforms › Windows · [ADR 0026](0026-clean-windows.md), `windows/hosts/cabin-win.nix`

### D143

[D108](#d108) concerns the Git-for-Windows toolchain: a mingw-w64 runtime that ships inside an app (Octave, Xournal++, PDF Arranger, hledger, Zettlr's pandoc) belongs to that app and is not a separate install.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`winget:Git.Git`)

### D144

Blitz is installed by hand and kept out of the build: the host file names it under `windows.unmanaged`, and `dram harvest` skips it.

Decided 2026-10-13 · Platforms › Windows · [ADR 0020](0020-windows-from-the-flake.md), `windows/hosts/cabin-win.nix`

### D145

cabin's firewall is on: `harden.sh`'s default deny, with Steam Remote Play and Steam Link opened to the LAN on Valve's ports.

Decided 2026-10-12 · Security › Network · `system/harden.sh`, `system/nftables.conf`, `system/gaming-setup.sh`

### D146

unzip is installed only as winetricks' dependency, under a waiver until 2027-10-12.

Decided 2026-10-12 · Security › Software supply · `packages/register.tsv` (`unzip`)

### D147

The rebuild started fresh: there was no pre-wipe run, and the `[dram]` signing key, the age keys and the SSH keys were made new at install.
The old keys are retired.

Decided 2026-10-11 · Security › Identity · `pkgs/dram.asc`, `keys/ssh.pub`

### D148

Windows 11 and the closed software tested inside it carry a FOSS waiver on cabin's Windows disk and on thermos, re-checked 2027-10-11: some of what I use does not run on Linux.

Decided 2026-10-11 · Security › Software supply · [ADR 0013](0013-software-rules-and-waivers.md)

### D149

League of Legends, with the Riot Client and Vanguard, and Blitz are removed from cabin-win, which keeps the games that are good for the mind and for playing with others online; the waiver [D92](#d92) lapses, and `manual:riot-client` is a `fail` row.
With Vanguard's kernel driver gone, the game test after each Secure Boot step ([ADR 0024](0024-secure-boot-custody.md)) and the Vanguard case for Memory Integrity ([D74](#d74)) are to be revisited; `windows.unmanaged` ([D144](#d144)) stays, with no name under it on cabin-win.

Decided 2026-10-19 · Security › Software supply · `packages/register.tsv` (`manual:riot-client`), `packages/winget/gaming.txt`, `windows/hosts/cabin-win.nix`
