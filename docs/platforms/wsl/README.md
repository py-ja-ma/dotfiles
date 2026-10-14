# WSL

[Platforms](../README.md) › WSL

Arch runs inside WSL 2 on each Windows PC, converged from this repo like any Arch host: the same package lists and register, `dram apply`, Home Manager, releases, channels and rollback.
It is where Windows does its coding and homelab work, and the terminal half of work and college.
VSCodium runs natively on Windows and edits inside the clone; git, the toolchains, npm, rootless Podman and kind live in the clone, and so do the notes, the journal and the coursework, since git does.

| | |
|---|---|
| Code | `modules/hosts/cabin-wsl.nix`, `modules/hosts/thermos-wsl.nix`, `system/wsl-setup.sh`, `system/wsl/`, `packages/wsl-skip.tsv`, `install/windows/dram-windows/wsl.ps1`, `install/windows/wslconfig`, `hosts/cabin-wsl/`, `hosts/thermos-wsl/` |
| Runs on | cabin-win as cabin-wsl; thermos as thermos-wsl, after thermos' reset |
| Needs | WSL 2 with the official Arch image (`wsl --install archlinux`), Windows' OpenSSH Authentication Agent; tested on cabin-win 2026-10-12 |
| Decided in | [decision 0021](../../../decisions/0021-wsl-clone.md) |

| Host | Windows PC | Roles | Disk | Address, for pushes |
|---|---|---|---|---|
| `cabin-wsl` | cabin-win | dev, sysadmin, office, college | `C:\WSL\cabin-wsl`, capped at 128 GB, sparse | `cabin`, Windows' OpenSSH as `cabin-win` |
| `thermos-wsl` | thermos | dev, sysadmin, re-lab, office, college | `C:\WSL\thermos-wsl`, capped at 96 GB | none yet: no LAN reservation, so stage by hand |

The host files set `form = "wsl"`, `gpu = "none"` and a `wsl` block; the Windows side is `install/windows/wslconfig` and `install/windows/dram-windows/wsl.ps1`.
Each clone's record is its README: [cabin-wsl](../../../hosts/cabin-wsl/README.md), [thermos-wsl](../../../hosts/thermos-wsl/README.md).

## What the clone is not

It is the user layer (`modules/`) and the command-line roles' packages, on the official Arch image, which is monthly, reproducible and signed.
It is never the system layer:

- no kernel, initramfs, boot chain, Secure Boot or snapshots: Microsoft's kernel boots the VM, `wsl --update` on Windows updates it, and `wsl --export` is the whole-system copy;
- no Hyprland, greeter, audio, power or Bluetooth: the GUI apps are Windows', and WSLg is off ([decision log](../../../decisions/log.md#d80));
- no firewall or network manager: Windows' firewall and the Hyper-V firewall filter the clone, WSL answers DNS, and mirrored networking shares 127.0.0.1 and Windows' VPNs;
- no GPU driver: the GPU is Windows', and CUDA, if ever wanted, would come from Windows' `libcuda`;
- no gaming, emulation, creator, recording or builder role, and no `[dram]` repo;
- not always on: it stops when idle, so its timers run only while it runs;
- not private from Windows: an administrator on Windows is root of the VM, and the VHDX is only as private as BitLocker on C:.

What its roles would install but the clone leaves out is `packages/wsl-skip.tsv`, one reason per name; `packages/metal.txt` and the hardware lists never reach it.
`bin/check.sh` §21 fails a clone whose plan holds a hardware or `[dram]` package, or a skip row without a reason.

## What it holds

Arch's own role lists, so the same packages as on cabin, and `base.txt` and the shell (`modules/shell.nix`, `modules/cli.nix`) as everywhere.

| Profile (role) | In the clone | Native on Windows (`packages/winget/`) |
|---|---|---|
| coding (dev) | git, neovim, tmux, rootless Podman, distrobox, rustup, Go, Node LTS with npm and pnpm, clang, cmake, uv, just, github-cli, opencode; lazygit, delta, direnv | VSCodium |
| homelab (sysadmin) | nmap with ncat, tcpdump, tshark and dumpcap, mtr, iperf3, dig, arp-scan, freeipmi, sshs; kubectl, helm, k9s, kind, talosctl, opentofu, ansible, sops | Wireshark without Npcap (its sshdump captures in the clone), WireGuard, PuTTY, Rufus |
| work and finance (office) | Taskwarrior, vit, Timewarrior, zk, marksman, hledger with its UI and web front ends, qpdf, img2pdf; `office-init` | LibreOffice, Zettlr, PDF Arranger, calibre, hledger; printing and scanning |
| work (college) | TeX Live and biber, Typst, Octave (`octave-cli`), gnuplot, ngspice, Verilator, Icarus Verilog, Yosys, prjtrellis, openFPGALoader, arduino-cli, PlatformIO, avr-gcc, avrdude | KiCad, Octave's GUI, draw.io, Xournal++, Anki, Arduino CLI |
| re-lab (thermos-wsl only) | Ghidra headless, radare2, gdb with pwndbg, pwntools, binwalk, yara, flashrom, openocd, sigrok-cli | x64dbg, System Informer, usbipd-win |

Arch keeps the rest: the session and every GUI while WSLg is off, gaming, emulation, creator, recording, dump-kit (the optical drives), telephony (the Yate lab), ml (cabin's GPU), Docker (rootless Podman here, [decision log](../../../decisions/log.md#d54)), the VM kit and the `[dram]` packages.
A board, programmer or analyzer reaches the clone only through `usbipd attach --wsl`, which waits on a waiver for usbipd-win ([decision log](../../../decisions/log.md#d118)); until then flashing is Windows' (Arduino CLI) or Arch's, and GTKWave's waves open on Arch.

## Create

Before: Windows' OpenSSH answers the Mac with the Mac's key, as `install/windows/apply-windows.sh` connects with `HostKeyAlias cabin-win`.
On thermos, its reset comes first ([Windows](../windows/README.md#thermos)).

1. The Mac stages the clone's files on the Windows PC, from a clean tree:

   ```sh
   bin/push-host.sh --wsl cabin-wsl pj@cabin master
   ```

   `C:\ProgramData\dram` then holds `dotfiles.bundle` (the repo), `wsl.ps1`, `wslconfig` and `wsl.conf`.
   A release (`bin/release.sh`) does the same for every WSL host with an address, when its PC runs Windows.

2. Windows builds the clone, in Terminal (Admin), signed in as pj:

   ```powershell
   powershell -ExecutionPolicy Bypass -File C:\ProgramData\dram\wsl.ps1 -Machine cabin -DryRun
   powershell -ExecutionPolicy Bypass -File C:\ProgramData\dram\wsl.ps1 -Machine cabin
   ```

   It writes `.wslconfig` first, before the distro exists, since `defaultVhdSize` caps only a new disk.
   It installs or updates WSL, and exits 3 when Windows needs a restart before it runs again.
   It sets the OpenSSH Authentication Agent to Automatic, then runs `wsl --install archlinux --name cabin-wsl --location C:\WSL\cabin-wsl --no-launch`.
   The root pass fills the keyring, runs `pacman -Syu git sudo`, puts pj in wheel with the password you type, turns on linger and writes `/etc/wsl.conf` with the distro's name, and the distro restarts.
   Then, as pj, it clones the repo from the bundle and runs `install/bootstrap.sh --yes`, of which WSL runs phases 1 (`dram apply`) and 3 (Nix and Home Manager) only.
   The clone checks out the newest release that knows the host, else `master` on channel main.

3. Open it (`wsl -d cabin-wsl`, or its Windows Terminal profile, which takes the Letterpress defaults) and run `dram doctor`.
   Its wsl section checks the clone; the boot, network and firewall checks say they don't apply.

4. The YubiKey through Windows' agent, the default ([decision log](../../../decisions/log.md#d79)):
   - on Windows, with the key plugged in, `ssh-add -K` loads its resident SSH key into Windows' agent, asking for its FIDO2 PIN;
   - in the clone, put the public half of the key you carry where ssh and git find it in the agent: `grep ' yubikey:primary$' ~/git/dotfiles/keys/ssh.pub | cut -d' ' -f1,2 > ~/.ssh/id_ed25519_sk.pub`;
   - `ssh-add -L` lists it, and an ssh login or a signed commit asks for one touch in the Windows Hello dialog.

   On demand instead, once usbipd-win is waived: `usbipd bind --busid <id>` once as administrator, then `usbipd attach --wsl --busid <id>`.
   The key is then the clone's alone until detached, and `dram yubikey ssh` copies its handles as on Arch.

5. VSCodium on Windows reaches the clone's sshd on `127.0.0.1:2222`: loopback only, keys only, a touch per login (`system/wsl/sshd.conf`).
   WSL stops a distro about 15 s after its last `wsl.exe` session ends, and an ssh session doesn't count, so the connection goes through `wsl.exe`, which starts the clone and keeps it up while VSCodium is connected; `ncat` comes with nmap, in the sysadmin role.
   In Windows' `%UserProfile%\.ssh\config`:

   ```
   Host cabin-wsl
       HostName 127.0.0.1
       Port 2222
       User pj
       HostKeyAlias cabin-wsl
       ProxyCommand C:\Windows\System32\wsl.exe -d cabin-wsl -- ncat 127.0.0.1 2222
   ```

   Then Remote Explorer, SSH, `cabin-wsl`: Open Remote - SSH, not Open Remote - WSL, which is stale and has an open shell-injection report ([decision log](../../../decisions/log.md#d55)).
   Without the ProxyCommand line it connects straight to `127.0.0.1:2222`, since mirrored networking shares loopback, but only while a terminal keeps the clone running.
   `instanceIdleTimeout=-1` in `.wslconfig` would keep the clone running forever instead; it isn't set.

## Update

- The Mac: a release stages the bundle for `cabin-wsl` when cabin runs Windows.
  When cabin runs Arch, Arch's host key answers instead of `cabin-win`'s, so the push is a warning and the clone catches up at the next one.
  By hand: `bin/push-host.sh --wsl cabin-wsl pj@cabin`.
- The clone: `dram update` receives a newer staged bundle first (`dram receive`), then runs as on Arch: the channel's target, the keyring, the cache, `pacman -Syu`, `dram switch`, `dram doctor --brief`.
  Instead of asking to reboot, it asks to restart the distro after `/etc/wsl.conf` changed: from Windows, `wsl.exe --terminate cabin-wsl`, then open it again.
- Windows' side, `.wslconfig` and WSL itself: run `wsl.ps1` again; it rewrites only what differs and shuts WSL down when `.wslconfig` changed.

## Test

In a new clone, after the steps above:

| What | Check |
|---|---|
| the clone | `dram doctor`: the wsl section clean, the agent lines once the key is loaded |
| containers | `podman run --rm docker.io/library/hello-world`: rootless, no daemon |
| Kubernetes | `KIND_EXPERIMENTAL_PROVIDER=podman systemd-run --scope --user -p Delegate=yes kind create cluster`, then `kubectl get nodes` and `kind delete cluster`: kind, not k3s, in the clone ([decision log](../../../decisions/log.md#d56)) |
| Node | `npm` and `pnpm` in a project |
| work | `office-init` makes the vault and the journal as git repos; `task add test`, then `task 1 edit` opens vim; `zk init` once in `~/documents/vault`, then `zk new` |
| finance | `hledger -f ~/documents/finance/main.journal balance`; `hledger-web --serve -f` with the same journal, then `http://127.0.0.1:5000` in Windows' browser |
| college | `latexmk -pdf` and `typst compile` on a report, `octave-cli --eval 'disp(pi)'`, `iverilog` and `verilator --lint-only` on a module, `arduino-cli version`, `pio --version` |
| capture | `sudo tshark -D` lists the interfaces, and `tshark -r` reads a capture; capturing wants root or the `wireshark` group, as on Arch |
| signing | `git commit -S` in a scratch repo takes one touch, and `git log --show-signature` verifies it on Arch |
| the editor | VSCodium, Open Remote - SSH, `cabin-wsl` |
| updates | `dram update` from a pushed bundle |
| a rebuild | `wsl --unregister cabin-wsl`, then the steps above, in under an hour |

cabin-wsl was converged on 2026-10-12, its roles' tools answered, and it took a release through a staged bundle.
The YubiKey lines wait for `ssh-add -K` on Windows.

## Rebuild

The VHDX is disposable: what isn't in this repo or pushed somewhere else is lost.
Before a risky change, `wsl --export cabin-wsl C:\WSL\cabin-wsl-<date>.tar` makes a whole-system copy, on C:'s space.
Then `wsl --unregister cabin-wsl` deletes the VHDX, and steps 1 to 5 build it again.

## When something is wrong

| Symptom | Check | Fix |
|---|---|---|
| `dram`: "this is WSL, but modules/hosts/cabin.nix is a metal host" | `uname -n`, `cat /etc/wsl.conf` | the distro runs under Windows' name: `sudo bash ~/git/dotfiles/system/wsl-setup.sh` (or `wsl.ps1`), then `wsl.exe --terminate cabin-wsl` |
| ssh or git: no key, "agent refused" | `systemctl --user status wsl2-ssh-agent`, `ssh-add -L`, `echo $SSH_AUTH_SOCK` | on Windows, `Get-Service ssh-agent` running and `ssh-add -K`; in the clone, a new login shell |
| VSCodium can't connect | `ss -tlnp` shows `127.0.0.1:2222`; `.wslconfig` says `networkingMode=mirrored` | `sudo bash ~/git/dotfiles/system/wsl-setup.sh`; `wsl.ps1` for `.wslconfig` |
| rootless Podman: "newuidmap: could not set caps", or "/ is not a shared mount" | `getcap /usr/bin/newuidmap`, `findmnt -no PROPAGATION /` | `sudo bash ~/git/dotfiles/system/wsl-setup.sh` |
| the disk fills | `df -h /`: the size is the cap | `podman system prune`, `dram update --clean`; a bigger cap: `wsl --manage cabin-wsl --resize <size>` (WSL 2.5 and later) |
| a push from the Mac fails | is the PC in Windows, with its OpenSSH up? | nothing to undo: push again later |

## Status

As of 2026-10-13: cabin-wsl is converged and follows releases through staged bundles.
thermos-wsl waits for thermos' reset.
The `system/` files the clone installs are described in [system/wsl/README.md](../../../system/wsl/README.md).
