{ ... }:

# lantern: the travel Arch laptop, called panasonic until its reinstall
# (hosts/lantern/README.md). Login: ranger. What it becomes:
#   CPU: Intel TigerLake-LP        GPU: Intel Iris Xe (i915)
#   Disk: NVMe 512 GB — LUKS2 (TPM2 + PIN), btrfs, hibernation (install/presets/laptop.env)
#   Boot: UEFI -> rEFInd -> a signed UKI (systemd-boot behind it) -> Plymouth -> ly@tty2 -> Hyprland
#   Panel: eDP-1 1920x1200 @ scale 1.5, plus 2x NZXT CANVAS 27Q externals when docked
#   Battery: BAT1 (not BAT0)
#
# Everything this host needs follows from the flags below (modules/options.nix):
#   isLaptop = true   -> lid.sh linked, waybar keeps the battery module (modules/laptop.nix)
#   gpu = "intel"     -> LIBVA_DRIVER_NAME=iHD (modules/gpu.nix)
{
  dram = {
    hostName = "lantern";
    user = "ranger";
    roles = [ "desktop" "gaming" "dump-kit" "re-lab" "sysadmin" "dev" "college" "office" "telephony" ];   # one line: install/lib/roles.sh reads it with grep (decisions/0009)
    address = "lantern";   # the Mac's ssh name for it (the LAN's DNS or ~/.ssh/config), as ranger@
    # sops-nix off until this install's age key is in .sops.yaml (docs/security/identity/secrets.md)
    secrets.enable = false;
    isLaptop = true;
    gpu = "intel";
  };
}
