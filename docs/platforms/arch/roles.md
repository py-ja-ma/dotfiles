# Roles

[Platforms](../../README.md) › [Arch Linux](../README.md) › Roles

A host is a hostname, its detected hardware and a list of roles, and that is enough to know every package it installs.
`install/lib/roles.sh` is the only reader of a host's roles and package lists: bootstrap, `dram apply`, `dram doctor`, `bin/check.sh` and the Mac's tools all source it, so they agree on what a host takes.

| | |
|---|---|
| Code | `install/lib/roles.sh`, `install/lib/detect.sh`, `modules/hosts/`, `modules/options.nix`, `packages/base.txt`, `packages/metal.txt`, `packages/cpu-*.txt`, `packages/gpu-*.txt`, `packages/laptop.txt`, `packages/host-cabin.txt` |
| Runs on | every Arch host and WSL clone |
| Needs | bash; `lspci` for the GPU |
| Decided in | [decision 0009](../../../decisions/0009-roles-and-host-shape.md) (roles), [decision 0004](../../../decisions/0004-module-split.md) (host flags), [decision 0021](../../../decisions/0021-wsl-clone.md) (the WSL form) |

## How it works

A host's roles are one line of its host file, quoted, which Nix reads as `dram.roles` and the shell scripts read with grep:

```nix
roles = [ "desktop" "gaming" "dev" ];
```

A role exists when `packages/roles/<role>.txt` does: `modules/options.nix` builds the list of allowed roles from that directory.
The lists a host installs follow from its roles, its hardware and its form:

| List | Taken by | Holds |
|---|---|---|
| `packages/base.txt` | every host | the userland: shell, networking tools, the maintenance tools |
| `packages/metal.txt` | every host on its own hardware | the kernel and firmware, the boot chain, disks, power, Wi-Fi, disk health, snapshots, the firewall |
| `packages/cpu-amd.txt`, `cpu-intel.txt` | metal hosts, by detected CPU | the CPU's microcode |
| `packages/gpu-nvidia.txt`, `gpu-intel.txt`, `gpu-amd.txt` | metal hosts, one per detected GPU vendor | the graphics driver, Vulkan, VA-API |
| `packages/laptop.txt` | metal hosts with a battery | laptop audio firmware, the TPM2 library for the disk unlock |
| `packages/roles/<role>.txt` | each role on the host's line | what the role is for |
| `packages/host-<host>.txt` | the host of that name | packages about that one machine: cabin's second kernel and its case display |

A WSL clone (`form = "wsl"`) takes `base.txt`, its roles and its host list, minus the names in `packages/wsl-skip.tsv`, and never a metal or hardware list ([WSL](../wsl/README.md)).
The `builder` role is the exception to "a role is a list": `system/dram-builder-setup.sh` installs its list itself, after it sets up the build chroot.

## The roles

| Role | For | Hosts (2026-10-13) |
|---|---|---|
| desktop | the Hyprland desktop, the Letterpress look, browser, mail, files, audio | cabin, lantern, campfire |
| gaming | Steam and what games need | cabin, lantern |
| emulation | the emulator set and its frontends | cabin |
| dump-kit | reading my own discs and console images | cabin, lantern |
| creator | OBS on the machine being recorded | cabin, campfire |
| recording | editing on the recorder | cabin, campfire |
| re-lab | reverse engineering and hardware hacking | cabin, lantern, thermos-wsl |
| dev | languages, VSCodium, rootless Podman | cabin, lantern, cabin-wsl, thermos-wsl |
| docker | Docker, for a tool that insists on it | cabin |
| ml | local models and PyTorch on cabin's GPU | cabin |
| ml-cuda | the CUDA toolkit, to compile CUDA code | none |
| sysadmin | the homelab and network kit | cabin, lantern, campfire, cabin-wsl, thermos-wsl |
| college | Computer Engineering coursework | cabin, lantern, cabin-wsl, thermos-wsl |
| office | tasks, notes, money, documents | cabin, lantern, cabin-wsl, thermos-wsl |
| telephony | the Yate lab | cabin, lantern |
| builder | the `[dram]` package builder | cabin |

What each role installs, and why, is on [Toolchain](../../toolchain/README.md): the standard app set of the desktop role, the developer's kit, and one page per profile.
The Windows PCs use the same role names for their own lists in `packages/winget/` ([renderer](../windows/renderer.md#roles)).

## What bootstrap detects

| Fact | How | What it decides |
|---|---|---|
| WSL or its own hardware | WSL's interop markers, then `systemd-detect-virt -c`, then Microsoft's kernel string | the metal and hardware lists, the WSL hooks |
| CPU vendor | `vendor_id` in `/proc/cpuinfo` | `cpu-amd.txt` or `cpu-intel.txt` |
| GPU vendors | the PCI vendor IDs of display controllers (class `03xx`) in `lspci -nn`, never the names | one `gpu-<vendor>.txt` each; early KMS in bootstrap's phase 5 |
| nvidia-open | the card's family: Turing or newer | `nvidia-open`, or `nvidia-dkms` for an older card |
| Laptop or desktop | a battery under `/sys/class/power_supply/`, then the DMI chassis type | `laptop.txt`, and `isLaptop` in a new host file |
| Boot mode | `/sys/firmware/efi` exists | a warning when it is not UEFI |

`bash -c '. install/lib/detect.sh && detect_report'` prints all of it on any machine.
`DRAM_FORM=wsl`, `laptop` or `desktop` overrides the platform and form, for a test or a wrong guess.

## Hardware lists

| | lantern | cabin |
|---|---|---|
| CPU | Intel: `intel-ucode` | AMD: `amd-ucode` |
| GPU | Intel Iris Xe: `intel-media-driver`, `vulkan-intel`, `lib32-vulkan-intel` | NVIDIA RTX 3080 Ti: `nvidia-open`, `nvidia-utils`, `lib32-nvidia-utils`, `nvidia-settings`, `libva-nvidia-driver`, `egl-wayland` |
| Early KMS modules | `i915` | `nvidia nvidia_modeset nvidia_uvm nvidia_drm`, the `kms` hook removed so nouveau stays out |
| Kernel parameter | none | `nvidia_drm.modeset=1` |
| VA-API (`modules/gpu.nix`) | `LIBVA_DRIVER_NAME=iHD` | `LIBVA_DRIVER_NAME=nvidia`, `NVD_BACKEND=direct` |

NVIDIA's modules come prebuilt, one package per kernel: `nvidia-open` for `linux` and `nvidia-open-lts` for cabin's `linux-lts`, from `packages/host-cabin.txt` ([decision log](../../../decisions/log.md#d18)).
A hybrid machine gets the lists and early KMS modules of every GPU it has.
`isLaptop` links `lid.sh` and keeps Waybar's battery module (`modules/laptop.nix`); a desktop gets the shared Waybar config with the battery stripped.

## Use it

```sh
bash -c '. install/lib/roles.sh && roles_of modules/hosts/cabin.nix'         # the roles, one per line
bash -c '. install/lib/roles.sh && host_package_files . cabin amd desktop nvidia'   # the lists cabin reads
dram apply --dry-run      # on a host: what its roles would install, enable and run
```

A new role is a new `packages/roles/<role>.txt` with a register row for each name; then its name goes on a host's roles line.
[Handbook chapter 7](../../records/handbook/07-packages.md) has the steps, and [packages/README.md](../../../packages/README.md) lists every list and its reader.

## When it breaks

| Symptom | Check | Fix |
|---|---|---|
| `bin/check.sh` §11 fails a host file | the file has no one-line `roles = [ … ];`, names a role without a list, or misses `hostName`, `isLaptop` or `gpu` | write the line on one line, quoted; add the missing flag |
| §3 warns that a host's explicit package is in no list | `hosts/<host>/packages/` is the host's last harvest | declare it in a list, or remove it on the host |
| §3 warns that a declared name is installed nowhere | the list has it, no harvest shows it | install it on a host and harvest, or drop the line |
| `dram` refuses to run in WSL with a metal host file | the distro took the Windows computer's name | name the distro in `/etc/wsl.conf` ([WSL](../wsl/README.md#when-something-is-wrong)) |

## Limits

- Detection reads PCI vendor IDs and the CPU's vendor string; the nvidia-open check is a heuristic on the card's family name and says no when unsure.
- A host file written by the installer has no `user`, `address` or secrets line: those come by hand ([Install](install.md#the-host-file)).
