{ config, lib, dram, ... }:

# Role office (docs/toolchain/profiles/office.md): `office-init` creates ~/documents/vault and
# ~/documents/finance from templates/office/ as git repos (never overwrites).
lib.mkIf (lib.elem "office" config.dram.roles) {
  home.file.".local/bin/office-init".source = dram.link ".local/bin/office-init";
}
