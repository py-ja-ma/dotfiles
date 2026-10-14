# thermos-wsl

Arch in WSL 2 on thermos, the ThinkPad L14 with Windows 11 (`modules/hosts/thermos-wsl.nix`, `form = "wsl"`): the user layer and the dev, sysadmin, re-lab, office and college roles.
Their terminal tools live here; the GUIs are Windows', so `packages/wsl-skip.tsv` leaves them out ([WSL](../../docs/platforms/wsl/README.md)).
Not created yet: it follows thermos' reset from this repo, then `dram harvest` in the clone fills this directory.

| | |
|---|---|
| Distro | `thermos-wsl`, the official Arch image, registered for pj on thermos |
| Disk | ext4 VHDX at `C:\WSL\thermos-wsl` (thermos has only C:), capped at 96 GB, sparse |
| Name | `/etc/wsl.conf`: `hostname=thermos-wsl`, systemd on, user pj, `appendWindowsPath=false` |
| USB | the re-lab hardware through `usbipd attach --wsl` on demand, once usbipd-win has its waiver ([decision log](../../decisions/log.md#d118)) |
| Updates | no LAN reservation yet, so no `address`: stage a bundle by hand (`bin/push-host.sh --wsl thermos-wsl pj@<address>`) |
