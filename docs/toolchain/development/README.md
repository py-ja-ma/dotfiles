# Development

[Toolchain](../README.md) › Development

The programmer's kit: editors, toolchains, rootless containers, the homelab tools and, on cabin, local language models.
Each part is a role, so a host takes only what it uses, and the WSL clones take the terminal half of each.
Git, delta, lazygit, direnv and ripgrep come with `modules/dev.nix` on every host, role or not.

| Branch | What it does | Code | Copy alone |
|---|---|---|---|
| Dev kit | editors, toolchains, debuggers, `gh`, `uv` | `packages/roles/dev.txt`, `modules/dev.nix` | the list, yes; `modules/dev.nix` after replacing my git identity and signing keys |
| Editor | VSCodium with Open Remote - SSH, secrets in the keyring | `pkgs/vscodium-bin/`, `dotfiles/.config/codium-flags.conf` | yes, with its `[dram]` recipe |
| Containers | rootless Podman and distrobox; Docker by opt-in | `packages/roles/dev.txt`, `packages/roles/docker.txt` | yes |
| Homelab kit | Kubernetes, infrastructure and network tools | `modules/dev.nix`, `packages/roles/sysadmin.txt` | yes |
| VMs | virt-manager over libvirt, disks on `/data/vm` | `system/virt-setup.sh` | yes, with an nftables include directory |
| Local models | llama.cpp as a user service, PyTorch per project | `modules/ml.nix`, `packages/roles/ml.txt`, `packages/roles/ml-cuda.txt` | yes |
| Telephony lab | Yate for the POTS lab in `~/git/homelab/pots` | `packages/roles/telephony.txt` | yes |

| Role | Hosts |
|---|---|
| `dev` | cabin, lantern, cabin-wsl, thermos-wsl; natively on cabin-win |
| `sysadmin` | cabin, lantern, campfire, cabin-wsl, thermos-wsl; natively on cabin-win |
| `docker` | cabin |
| `ml` | cabin |
| `ml-cuda` | none by default |
| `telephony` | cabin, lantern |

## The dev kit

| Job | Tools |
|---|---|
| Editors | VSCodium (`codium`, from `[dram]`), Neovim, tmux |
| Remote editing | Open Remote - SSH in VSCodium, from Open VSX |
| Containers | rootless Podman with buildah, skopeo and podman-compose; distrobox for other distributions' tools |
| Toolchains | Rust (stable is rustup's default), Go, Node LTS with npm and pnpm, clang, cmake, ninja, Python through `uv` |
| Measure and debug | valgrind, perf, hyperfine; strace is the re-lab role's |
| GitHub | `gh`, git-lfs |
| Checks | `just`, shellcheck, shfmt, pre-commit |
| AI | OpenCode in the terminal, pointed at cabin's local `llama-server` |

`dram switch` installs Open Remote - SSH once, and sets Rust's stable toolchain as rustup's default when none is chosen (`modules/dev.nix`).
In VSCodium, *Remote Explorer › SSH* reaches `pj@cabin` or `ranger@lantern`.
On Windows the native VSCodium reaches the WSL clone at `127.0.0.1:2222` ([WSL](../../platforms/wsl/README.md)).

Commits are signed with SSH.
Once `keys/ssh.pub` lists a YubiKey, the signing key is the one on the key, with a touch per commit.
Until then it is the host's own ed25519 key, made before the first commit.
`~/.config/git/allowed_signers` lists the public keys, so `git log --show-signature` checks my own commits.

## The editor

VSCodium is the community build of Microsoft's MIT-licensed sources, without the branding, telemetry and proprietary license.
It replaced Microsoft's VS Code on 2026-10-10: Microsoft's build fails the FOSS rule ([D4](../../../decisions/log.md#d4)).
`pkgs/vscodium-bin/` repackages the release tarball, and `REVIEW.md` there records what it checks.

- `dotfiles/.config/codium-flags.conf` starts it on Wayland, with the input method and `--password-store=gnome-libsecret`.
- `dotfiles/.config/VSCodium/User/settings.json.default` seeds the settings once. The live `settings.json` stays machine state.
- The Letterpress themes are a generated extension ([Design](../../design/README.md)). Other extensions are not tracked: reinstall them.

## Containers

```sh
podman run --rm -it docker.io/library/alpine sh   # no daemon, no root, no firewall rule
podman compose up                                  # compose files work as with Docker
distrobox create -i fedora:latest -n fed && distrobox enter fed
```

Images live under `~/.local/share/containers`, and root containers under `/var/lib/containers` on the work pool.
Console SDKs (pspdev, ps2dev, devkitPro) run this way too ([Re-lab](../profiles/re-lab.md)).
A GPU in a container on cabin: `podman run --device nvidia.com/gpu=all …`, after `sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`.

Give a host the `docker` role only for a tool that insists on the daemon; cabin has it.
Docker's forward rules do not survive a reload of the default-drop firewall, so restart docker after `system/harden.sh`.
Why rootless Podman first: [decision 0015](../../../decisions/0015-containers-podman.md).

## The homelab kit

The sysadmin role splits its tools between two layers.
A daemon, a kernel-adjacent tool or anything with a window comes from pacman.
A self-contained command-line tool whose version I want pinned comes from nixpkgs, so `talosctl` and `kubectl` are the same version on every host.

| nixpkgs (`modules/dev.nix`, pinned by `flake.lock`) | pacman (`packages/roles/sysadmin.txt`) |
|---|---|
| `kubectl`, `kubernetes-helm`, `k9s`, `kubectx`, `talosctl` | `nmap`, `tcpdump`, `arp-scan`, `ethtool`, `mtr`, `iperf3` (raw sockets) |
| `yq-go`, `sops`, `age`, `step-cli` | `wireshark-qt` and `wireshark-cli`, `bind` for `dig`, `sshs` |
| `opentofu`, `lazydocker`, `kind`, `ansible` | `freeipmi` (`ipmi-sensors`, `ipmi-power`, `ipmi-chassis`) |
| `mkcert`, on every host | QEMU with OVMF and swtpm, virt-manager, libvirt, dnsmasq |

`jq` is pacman's (`packages/base.txt`), because systemd user units see `/usr/bin` only.
`KUBECONFIG` and `TALOSCONFIG` point at `~/.kube/config` and `~/.talos/config` on each host, and neither file is tracked.
The groups to join once are `docker`, `wireshark` and `uucp`.

`system/virt-setup.sh` turns on `libvirtd.socket`, adds the main user to `libvirt` and lets the VMs on `virbr0` reach the host's dnsmasq through `/etc/nftables.d/libvirt.nft`.
It is an `ask` hook of `dram apply`, because it touches the firewall.
VM disks belong on `/data/vm`, beside the headless kit `tests/windows-vm.sh` uses.

## Local models

On cabin's RTX 3080 Ti (12 GB) everything runs locally, and nothing needs an account.

PyTorch comes per project through uv:

```sh
uv init my-project && cd my-project
uv add torch torchvision --index https://download.pytorch.org/whl/cu128
uv add --dev jupyterlab ipykernel && uv run jupyter lab
```

The wheels bring their own CUDA runtime, so no system CUDA is needed; the PyPI `nvidia-*` wheels are waived ([decision 0013](../../../decisions/0013-software-rules-and-waivers.md)).
To compile CUDA code (course GPU labs, llama.cpp from source), give cabin the opt-in `ml-cuda` role: cuda, cudnn and nccl, about 2.6 GB, also waived.

`llama-cpp` with `ggml-vulkan` needs no toolkit.
`modules/ml.nix` runs `llama-server` as a user service on `127.0.0.1:8080`, an OpenAI-compatible API that OpenCode uses.
It starts only when `~/models/default.gguf` exists:

```sh
mkdir -p ~/models && uv tool install "huggingface_hub[cli]"
hf download google/gemma-4-12b-it-qat-q4_0-gguf --local-dir ~/models/gemma-4-12b
ln -sf ~/models/gemma-4-12b/*.gguf ~/models/default.gguf
systemctl --user restart llama-server
```

A model must carry an OSI license (Apache-2.0 or MIT) and come from an organization that passes the Origin rule, with every model it was fine-tuned from ([D23](../../../decisions/log.md#d23)).

| Allowed | License | From | Fits 12 GB |
|---|---|---|---|
| Gemma 4 12B QAT (Q4_0) | Apache-2.0 | Google | yes (6.5 GiB) |
| Ministral 3 14B | Apache-2.0 | Mistral AI (France) | yes at Q4 |
| Granite 4.2 8B | Apache-2.0 | IBM | yes (5 GiB Q4_K_M) |
| OLMo 3 7B | Apache-2.0 | Ai2, open data and code | yes |
| Phi-4 14B | MIT | Microsoft | yes at Q4 |
| gpt-oss-20b | Apache-2.0 | OpenAI | tight (10.8 GiB) |

Not allowed: Llama (a custom license), older Gemma terms, Nemotron, Falcon, Command R and StarCoder2, none of them OSI licenses.
Also not allowed: any model from a Chinese lab (Qwen, DeepSeek, GLM, Yi, Kimi, MiniMax) or one fine-tuned from it.
LM Studio is closed source, so I do not use it.

Where I learn from: Karpathy's *Zero to Hero*, then d2l.ai or fast.ai, the Hugging Face LLM course, then nanochat.

## Operating it

Adding or removing a package: [handbook chapter 7](../../records/handbook/07-packages.md).
Giving a host a role: its host file's `roles` line, then `dram apply` ([decision 0009](../../../decisions/0009-roles-and-host-shape.md)).

## Status

As of 2026-10-13 the dev, sysadmin, docker and ml roles run on cabin, and dev and sysadmin on lantern and both WSL clones.
`ml-cuda` is on no host.
