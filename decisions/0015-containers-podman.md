# 0015: Rootless Podman by default, Docker by role, Colima on the Mac

[Toolchain › Development](../docs/toolchain/development/README.md) · accepted 2026-10-11

Containers run rootless under Podman on the hosts and under Colima on the Mac, with Docker only where a role asks for it; the cost is a `$CONTAINER` override in the scripts that call one.

## Context

Docker is in the base set and needs firewall forward rules that fight the default-drop
nftables ruleset (`system/nftables.conf`). Docker Desktop on the Mac is
proprietary and fails `decisions/0013`.

## Decision

- Hosts: rootless **Podman** (+ `podman-compose`, distrobox where useful) in the `dev`
  role; containers live on the `@containers` subvolume. Docker moves to an opt-in role
  with the forward rules it needs ([D22](log.md#d22)).
- Mac: **Colima** replaces Docker Desktop for the test bench (T1 package resolution) and
  the `nix flake check` container ([D26](log.md#d26)).
- Console SDKs (devkitPro, ps2dev, pspdev) run in containers, not on the host.

## Consequences

- Rootless Podman works under the default-drop firewall with no forward rules.
- Scripts that call `docker` take a `$CONTAINER` override; `podman` is the default.

## As built

- `packages/roles/dev.txt`: podman, buildah, skopeo, aardvark-dns, passt, podman-compose,
  distrobox; `packages/roles/docker.txt` is the opt-in role (docker, buildx, compose moved
  out of sysadmin); cabin has it. GPU containers through `nvidia-container-toolkit` (CDI)
  in the ml role. Guide: `docs/toolchain/development/README.md`.

## How it is checked

Nothing checks the choice itself.
`docker` is declared only by the opt-in `packages/roles/docker.txt`, and `bin/check.sh` §3 fails a name listed twice across the lists, so it cannot creep into another role unnoticed.

## History

- 2026-10-10: proposed ([D22](log.md#d22)).
- 2026-10-11: accepted and built.
- 2026-10-12: the WSL clones run rootless Podman too, Docker only through the docker role ([D54](log.md#d54)).
