{ ... }:

# cabin-wsl: Arch in WSL 2 on cabin's Windows 11 (decisions/0021, docs/platforms/wsl/README.md),
# the clone of
# the Arch user layer and the CLI roles, converged by `dram apply` + Home Manager like any
# Arch host, rebuilt from the repo in under an hour. Never the system layer: no kernel, boot
# chain, firewall, session or GPU driver of its own (Windows owns the VM).
#   Disk: an ext4 VHDX on C: (the MX500), C:\WSL\cabin-wsl, capped at 128 GB and sparse
#         (install/windows/wslconfig, set before the distro existed)
#   Name: /etc/wsl.conf sets hostname=cabin-wsl; WSL would otherwise take the Windows name
#         `cabin` and `dram` would load the bench host (it refuses a metal host file in WSL)
#   Keys: Windows keeps the YubiKey; ssh and git signing reach Windows' agent through
#         wsl2-ssh-agent (modules/dev.nix); usbipd-win only on demand
#   Reach: VSCodium on Windows -> Open Remote - SSH -> 127.0.0.1:2222 (system/wsl-setup.sh)
#   Roles: the work profiles on Windows (docs/platforms/wsl/README.md): coding (dev),
#         homelab (sysadmin), and
#         the terminal half of work and finance (office, college): Taskwarrior, zk, hledger,
#         TeX Live, Typst, the HDL and microcontroller toolchains. Their GUIs are Windows'
#         (packages/winget/), so packages/wsl-skip.tsv leaves them out here
#
# Everything this host needs follows from the flags below (modules/options.nix):
#   form = "wsl"     -> base + roles minus packages/wsl-skip.tsv; the wsl pseudo-role's units
#                       and hooks, never the metal ones (system/*.tsv); dram's WSL checks
#   gpu = "none"     -> no driver env (modules/gpu.nix): the GPU belongs to Windows
#   isLaptop = false -> no lid.sh (the VM has no battery)
{
  dram = {
    hostName = "cabin-wsl";
    user = "pj";
    roles = [ "dev" "sysadmin" "office" "college" ];   # one line: install/lib/roles.sh reads it with grep (decisions/0009)
    form = "wsl";
    wsl = {
      windowsHost = "cabin";        # its OpenSSH is the push door: HostKeyAlias cabin-win (bin/push-host.sh --wsl)
      distro = "cabin-wsl";
      sshAgent = "windows";
    };
    address = "cabin";      # Windows' OpenSSH on cabin (the same name as Arch's): bin/release.sh stages the bundle there
    # sops-nix off: no age key in the clone (docs/security/identity/secrets.md)
    secrets.enable = false;
    isLaptop = false;
    gpu = "none";
  };
}
