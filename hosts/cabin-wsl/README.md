# cabin-wsl

Arch in WSL 2 on cabin's Windows 11 (`modules/hosts/cabin-wsl.nix`, `form = "wsl"`): the user layer and the dev, sysadmin, office and college roles, converged by `dram apply` and Home Manager, never the system layer.
Their terminal tools live here; the GUIs are Windows', so `packages/wsl-skip.tsv` leaves them out ([WSL](../../docs/platforms/wsl/README.md)).
Converged on 2026-10-12; its first `dram harvest` fills this directory with its package lists, enabled units, `/etc` copies and a `hardware.txt` that says `form: wsl`.

| | |
|---|---|
| Distro | `cabin-wsl`, the official Arch image (`wsl --install archlinux`), registered for pj on cabin-win |
| Disk | ext4 VHDX at `C:\WSL\cabin-wsl` on the MX500, capped at 128 GB, sparse |
| Name | `/etc/wsl.conf`: `hostname=cabin-wsl`, systemd on, user pj, `appendWindowsPath=false` |
| Reach | VSCodium on Windows, Open Remote - SSH to `127.0.0.1:2222`: loopback only, keys only, a touch per login |
| Updates | a bundle staged in `C:\ProgramData\dram` through Windows' OpenSSH (`HostKeyAlias cabin-win`); `dram update` in the clone receives it |
