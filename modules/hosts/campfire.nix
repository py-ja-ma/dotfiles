{ ... }:

# campfire: the recorder, whose capture card, webcam and mic record what cabin shows
# (docs/toolchain/profiles/creator.md). Not installed yet (2026-10-13).
#   RAM: 32 GB    GPU: NVIDIA RTX 3060 (Ampere: NVENC H.264 + HEVC, no AV1 encode)
#   Capture card on a USB 3.2 Gen2 (10 Gbps) rear port
#
# Everything this host needs follows from the flags below (modules/options.nix):
#   isLaptop = false, gpu = "nvidia" -> NVIDIA Wayland env (modules/gpu.nix)
# Set `address` once the UniFi reservation exists (bin/release.sh pushes to it, and the
# firewall rule on this host is written from cabin's address: system/recording-setup.sh).
{
  dram = {
    hostName = "campfire";
    user = "pj";
    roles = [ "desktop" "creator" "recording" "sysadmin" ];   # one line: install/lib/roles.sh reads it with grep (decisions/0009)
    secrets.enable = false;
    isLaptop = false;
    gpu = "nvidia";
  };
}
