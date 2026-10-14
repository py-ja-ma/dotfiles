# tests

[Operations](../docs/operations/README.md) › [Quality](../docs/operations/quality/README.md) › Tests

The tests behind the tiers T0 to T4: static checks anywhere, real packages in a container, installs in a VM on the Mac, a rollback drill, and smoke tests on the machines.
`bin/check.sh` runs the T0 tests on each change, and the rest run by hand.

| | |
|---|---|
| Needs | bash and python3 for T0; Colima with an amd64 Arch container for T1; QEMU, edk2's OVMF and swtpm for T2 and T3; tested on the Mac in 2026-10 |
| Copy alone | no: each test drives this repo's scripts; the VM harness of `t2-vm.sh` and `vm-auto.sh` is the part worth borrowing |
| License | MIT |

## The tiers

| Tier | Proves | Where |
|---|---|---|
| T0 | the static checks: `bin/check.sh` with shellcheck and shfmt, the T0 tests against stand-ins in a temp directory, and `nix flake check` for each host | any machine with bash; Nix in a container on the Mac |
| T1 | real packages: each role's list resolves, and the hooks work against Arch's own files | a throwaway amd64 Arch container under Colima |
| T2 | a whole install: the pinned ISO, `install/arch-install.sh` unattended, the first boot with checks over ssh; T2-SB adds Secure Boot, and T2b runs `install/bootstrap.sh` on the result | QEMU on the Mac |
| T3 | the rollback drill: a package installed, its snapshot's boot entry booted, the system rolled back to it | the same VM |
| T4 | smoke tests on hardware: Gaming Mode on NVIDIA, a game, each emulator with an owned dump, OBS into the recorder, Windows booting with Secure Boot on | the machines themselves |

A VM cannot show Gaming Mode on NVIDIA or an emulator's speed, which is what T4 is for.

## What it needs

| Tier | Needs |
|---|---|
| T0 | bash, git and python3; bsdtar and curl for `push-windows.sh`; no network and no root |
| T1 | Colima and the docker CLI on the Mac, the image `archlinux:latest` for `linux/amd64`; pacman's download sandbox does not run under Rosetta, so the T1 tests turn it off inside the container |
| T2, T3 | Homebrew's QEMU (x86_64 under TCG on Apple silicon), the Secure Boot build of edk2's OVMF, swtpm, python3's `http.server`; the ISO that `install/get-iso.sh` fetches and checks against `install/iso.pin`; room under `~/vm-bench`, capped at 150 GB |
| `windows-vm.sh` | cabin's KVM, with qemu, edk2-ovmf, swtpm and mtools from the `sysadmin` role, and a Windows 11 ISO |

## Copy it alone

The tests are not built to leave this repo: each one drives a script from it.
The VM harness is the part to borrow.
`t2-vm.sh` boots the stock Arch ISO in QEMU with the kernel parameter `script=http://10.0.2.2:8000/vm-auto.sh`, and serves that script and a tarball of the repo with python3's `http.server`.
The ISO runs `vm-auto.sh`, which runs the installer unattended and logs each line to the serial console.
To reuse it, copy both files, then replace the installer call in `vm-auto.sh` and the checks at the end of `t2-vm.sh`.

## How it is wired here

- `bin/check.sh` runs the T0 tests: §16 `gaming-switch.sh`, §17 `rec-websocket.py`, §18 `yubikey-t0.sh`, §19 `push-windows.sh`, §20 `case-display.py`.
- The VM tests install with the preset `install/presets/vm-test.env`: one disk, no LUKS, a small system pool, a serial console, sshd on.
- `fixtures/` holds a small render for `push-windows.sh`: a manifest in the renderer's shape and three winget documents; the test fills in the sha256 values.
- The later tests leave the T2 disk unwritten: `t2-bootstrap.sh`, `t3-vm.sh` and `gaming-vm.sh` work on a copy or an overlay.

## Files

| Test | Tier | Covers | Runs |
|---|---|---|---|
| `gaming-switch.sh` | T0 | Gaming Mode's session names and one-shot autologin (`pkgs/dram-gaming-mode`, `system/apply-ly.sh`) | `bin/check.sh` §16 |
| `rec-websocket.py` | T0 | `rec` against a mock obs-websocket server | `bin/check.sh` §17 |
| `yubikey-t0.sh` | T0 | `system/yubikey-setup.sh` on copies of the PAM files, `secrets-bootstrap.sh --register-yubikey`, `bin/yubikey.sh`'s refusals | `bin/check.sh` §18 |
| `push-windows.sh` | T0 | `bin/push-windows.sh`, `install/windows/apply-windows.sh` and `install/lib/windows-stage.sh` against a stand-in ssh, scp and Windows | `bin/check.sh` §19 |
| `case-display.py` | T0 | the case display's frame encoder, USB calls and loop against fakes (`pkgs/dram-case-display`) | `bin/check.sh` §20 |
| `yubikey-t1.sh` | T1 | the YubiKey PAM line with real packages, the self-test, the initramfs with libfido2, `install/lib/luks.sh`, `harden.sh`'s sshd drop-in | by hand, in the container |
| `t2-vm.sh`, `vm-auto.sh` | T2 | `install/arch-install.sh` unattended, then a boot with checks; `--bench` for cabin's two-disk preset | by hand on the Mac, tens of minutes |
| `t2-bootstrap.sh` | T2b | `install/bootstrap.sh` on a copy of the T2 disk, and what handbook chapter 1 promises after it | by hand on the Mac, an hour or more |
| `t3-vm.sh` | T2-SB, T3 | Secure Boot enforcing with swtpm, snapshots with signed boot entries, a snapshot boot, the rollback | by hand on the Mac |
| `gaming-vm.sh` | T2 | a real switch from the desktop into Gaming Mode through ly and polkit | by hand on the Mac |
| `windows-vm.sh` | none | Windows 11 installed from `install/windows/autounattend.xml`, through the first logon, in a VM | by hand on cabin |

## Run them

```sh
bash bin/check.sh                                     # each T0 test, on the Mac or a host
tests/t2-vm.sh                                        # T2: install, boot, check
tests/t2-vm.sh --roles desktop --sys-gib 28           # the disk tests/t2-bootstrap.sh needs
tests/t2-bootstrap.sh                                 # T2b
tests/t3-vm.sh                                        # T2-SB and T3, on a copy of the T2 disk
```

Each T1 test's header holds its `docker run` line: the container mounts the repo read-only at `/repo` and runs the test as root.

## License

MIT, Patrick Jordan.
