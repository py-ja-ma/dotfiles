{ ... }:

# dev - coding happens in the WSL clone (Arch's dev list: podman, rustup, go, node, uv...);
# natively only the editor (packages/winget/dev.txt), which reaches the clone through Open Remote
# - SSH at 127.0.0.1:2222 (decisions/log.md#d55; docs/platforms/wsl/README.md). git only in the
# clone (decisions/log.md#d108).
{
  windows.role.dev = {
    script = {
      # the editor's way into the WSL clone (sshd on 127.0.0.1:2222, docs/platforms/wsl/README.md): the
      # extension Arch's dram switch installs too (modules/dev.nix), fetched from Open VSX, for
      # this user, once VSCodium is in (30-machine runs before 30-user)
      vscodium-open-remote-ssh = {
        description = "Open Remote - SSH in VSCodium (jeanp413, MIT, Open VSX; accepted 2026-10-11), not Open Remote - WSL";
        elevated = false;
        phase = "30";
        package = "manual:open-remote-ssh";
        dependsOn = [ "vscodium" ];
      };
    };
  };
}
