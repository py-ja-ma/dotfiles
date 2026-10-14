{ config, lib, dram, ... }:

# dram.gpu selects the driver-specific session env. The pacman side (driver
# packages, early KMS) is packages/gpu-<vendor>.txt + install/bootstrap.sh.
let
  inherit (dram) link;
in {
  config = lib.mkMerge [
    (lib.mkIf (config.dram.gpu == "nvidia") {
      # ---- NVIDIA on Wayland ---------------------------------------------------
      # LIBVA_DRIVER_NAME + NVD_BACKEND are required for hardware video decode via
      # libva-nvidia-driver. GBM_BACKEND and __GLX_VENDOR_LIBRARY_NAME were required
      # on older drivers; on 555+ they are usually redundant but remain harmless, and
      # are kept because this box runs a mixed Electron/Chromium/Steam stack where
      # some clients still consult them.
      home.sessionVariables = {
        LIBVA_DRIVER_NAME        = "nvidia";
        NVD_BACKEND              = "direct";
        GBM_BACKEND              = "nvidia-drm";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";

        # ---- NVIDIA shader disk cache -----------------------------------------
        # The driver caps its on-disk shader cache at a small default. CS2 alone has
        # far more compiled pipelines than that, so the cache evicts itself and the
        # game recompiles on EVERY launch ("Processing Vulkan shaders", ~1h). Lift
        # the cap to 10 GB and stop the driver pruning it. The cache lives at
        # ~/.cache/nvidia/GLCache (ext4, persistent). Steam's own Fossilize cache
        # in steamapps/shadercache/<appid> is separate and is legitimately
        # re-processed once after a driver update - that one is expected.
        __GL_SHADER_DISK_CACHE              = "1";
        __GL_SHADER_DISK_CACHE_SIZE         = "10000000000";
        __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
      };

      # Feral gamemode: performance tuned profile via tuned-ppd, split-lock
      # mitigation off per game, no screensaver inhibit (hypridle's fullscreen
      # idle_inhibit rule already covers it). Desktop-only: the laptop's iGPU
      # gaming is the SUPER+SHIFT+G compositor toggle (gamemode.sh), not this.
      xdg.configFile."gamemode.ini".source = link ".config/gamemode.ini";
    })

    (lib.mkIf (config.dram.gpu == "intel") {
      # Intel VA-API. i915 is the driver in use; `xe` also autoloads on this kernel
      # but binds no device (refcount 0) and is harmless.
      home.sessionVariables = {
        LIBVA_DRIVER_NAME = "iHD";
      };
    })

    # "amd": nothing yet. Mesa's radeonsi picks itself up without env vars; add a
    # branch here when the first AMD-GPU host needs one.
    # "none": nothing. The WSL clone's GPU is Windows' (CUDA through the
    # driver's /usr/lib/wsl/lib, GL through Mesa's d3d12 under WSLg): the NVIDIA vars
    # above would break that path. GALLIUM_DRIVER=d3d12 only if WSLg is on.
  ];
}
