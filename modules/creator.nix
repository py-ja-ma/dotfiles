{ config, lib, dram, ... }:

# Recording (docs/toolchain/profiles/creator.md), the user half.
#   creator   (cabin, the recorder): `rec` — start/stop OBS on the recorder over
#             obs-websocket (SUPER+CTRL+R in hyprland.lua) — and the "Cabin" OBS scene
#             collection + profile (local / SRT fallback);
#   recording (the recorder): the "Recorder" scene collection + profile (capture card,
#             webcam, mic with RNNoise/compressor/limiter, four audio tracks).
# OBS templates are COPIED into ~/.config/obs-studio when absent, never linked: libobs
# saves through a temp file + rename, which would replace a symlink with a plain file.
# `rec templates-save` copies the live files back to dotfiles/obs/ for a commit.
let
  hasRole = r: lib.elem r config.dram.roles;
  obsDir = "${config.home.homeDirectory}/.config/obs-studio/basic";
  seed = role: ''
    for f in "${dram.repo}/dotfiles/obs/${role}"/scenes/*.json; do
      [ -e "$f" ] || continue
      t="${obsDir}/scenes/$(basename "$f")"
      [ -e "$t" ] || { run mkdir -p "${obsDir}/scenes" && run cp $VERBOSE_ARG "$f" "$t"; }
    done
    for d in "${dram.repo}/dotfiles/obs/${role}"/profiles/*/; do
      [ -d "$d" ] || continue
      t="${obsDir}/profiles/$(basename "$d")"
      [ -e "$t/basic.ini" ] || { run mkdir -p "$t" && run cp $VERBOSE_ARG "$d/basic.ini" "$t/basic.ini"; }
    done
  '';
in
{
  config = lib.mkMerge [
    (lib.mkIf (hasRole "creator") {
      home.file.".local/bin/rec".source = dram.link ".local/bin/rec";
      home.activation.seedObsCreator = lib.hm.dag.entryAfter [ "linkGeneration" ] (seed "creator");
    })
    (lib.mkIf (hasRole "recording") {
      home.activation.seedObsRecording = lib.hm.dag.entryAfter [ "linkGeneration" ] (seed "recording");
    })
  ];
}
