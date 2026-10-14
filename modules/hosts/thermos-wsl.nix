{ ... }:

# thermos-wsl — Arch in WSL 2 on thermos, the ThinkPad L14 that travels with Windows 11 only
# (decisions/0021, docs/platforms/wsl/README.md; after thermos' reset): the same clone as
# cabin-wsl (dev,
# sysadmin, and office and college's terminal half for work and finance) plus the re-lab
# role, whose USB tools (the Tigard, the CH341A, the FX2 analyser, serial adapters) reach
# the clone through `usbipd attach --wsl` on demand.
#   Disk: an ext4 VHDX on C: (thermos has only C:), capped at 96 GB and sparse
#   Name: /etc/wsl.conf sets hostname=thermos-wsl
#   Keys: Windows keeps the YubiKey (wsl2-ssh-agent, modules/dev.nix)
#   No `address` until thermos has a LAN reservation: bin/release.sh does not push
#   to it; stage a bundle by hand with bin/push-host.sh --wsl thermos-wsl pj@<address>
#
# Everything this host needs follows from the flags below (modules/options.nix); see
# modules/hosts/cabin-wsl.nix for what form = "wsl" and gpu = "none" do.
{
  dram = {
    hostName = "thermos-wsl";
    user = "pj";
    roles = [ "dev" "sysadmin" "re-lab" "office" "college" ];   # one line: install/lib/roles.sh reads it with grep (decisions/0009)
    form = "wsl";
    wsl = {
      windowsHost = "thermos";      # HostKeyAlias thermos-win (bin/push-host.sh --wsl)
      distro = "thermos-wsl";
      sshAgent = "windows";
    };
    secrets.enable = false;
    isLaptop = false;
    gpu = "none";
  };
}
