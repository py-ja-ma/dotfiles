#!/usr/bin/env bash
# Sourced, not run: the only reader of a host's roles and package lists
# (decisions/0009-roles-and-host-shape.md). Used by install/bootstrap.sh, `dram apply`
# / `dram doctor` and bin/check.sh, so they agree on what a host installs.
#
# A host's roles live on one line of modules/hosts/<name>.nix, quoted, for example
#   roles = [ "desktop" "gaming" "sysadmin" ];
# Nix reads the same line as the `dram.roles` option (modules/options.nix).
# Hardware lists (cpu-*, gpu-*, laptop) are chosen by detection, not by role. A WSL
# clone (`form = "wsl";`, decisions/0021) reads no metal or hardware list at all.
#
#   roles_of <host.nix>               roles named in the file, one per line
#   role_files <repo> <host>          packages/roles/<r>.txt for each role, one per line
#   known_roles <repo>                every role that has a file in packages/roles/
#   host_package_files <repo> <host> <cpu> <form> <gpu>...
#                                     form laptop|desktop (metal): base + metal + cpu +
#                                     gpu(s) + laptop + roles + host-<host>.txt; form wsl:
#                                     base + roles + host-<host>.txt — every role except
#                                     builder, which system/dram-builder-setup.sh installs itself
#   host_form <repo> <host>           metal | wsl: the host file's `form = "…";` (default metal)
#   host_wsl <repo> <host> <key>      a `wsl = { <key> = "…"; }` value (windowsHost, distro, sshAgent)
#   wsl_skip_names <repo>             the names packages/wsl-skip.tsv keeps off a WSL host
#   host_addresses <repo>             name=address for every metal host file that sets
#                                     dram.address (the Mac's ssh targets; a WSL clone's
#                                     address is its Windows PC's: bin/push-host.sh --wsl)
#   hosts_with_role <repo> <role>     host names whose roles include <role>

roles_of() {
  [ -f "$1" ] || return 0
  sed -nE 's/^[[:space:]]*(dram\.)?roles[[:space:]]*=[[:space:]]*\[([^]]*)\].*/\2/p' "$1" \
    | head -1 | tr -d '"' | tr -s '[:space:]' '\n' | grep -v '^$' || true
}

role_files() {
  local repo="$1" host="$2" r
  for r in $(roles_of "$repo/modules/hosts/$host.nix"); do
    echo "$repo/packages/roles/$r.txt"
  done
}

known_roles() {
  local f
  for f in "$1"/packages/roles/*.txt; do
    [ -f "$f" ] && basename "$f" .txt
  done
  return 0
}

host_package_files() {
  local repo="$1" host="$2" cpu="$3" form="$4" g
  shift 4
  echo "$repo/packages/base.txt"
  # Windows owns a WSL clone's kernel, boot chain, disks and devices (decisions/0021)
  if [ "$form" != wsl ]; then
    echo "$repo/packages/metal.txt"
    [ -n "$cpu" ] && [ "$cpu" != unknown ] && echo "$repo/packages/cpu-$cpu.txt"
    for g in "$@"; do echo "$repo/packages/gpu-$g.txt"; done
    [ "$form" = laptop ] && echo "$repo/packages/laptop.txt"
  fi
  role_files "$repo" "$host" | grep -v '/builder\.txt$' || true
  [ -f "$repo/packages/host-$host.txt" ] && echo "$repo/packages/host-$host.txt"
  return 0
}

# host_form <repo> <host>: metal | wsl, from `form = "…";` in modules/hosts/<host>.nix
host_form() {
  local f
  f=$(sed -nE 's/^[[:space:]]*(dram\.)?form[[:space:]]*=[[:space:]]*"([^"]+)".*/\2/p' "$1/modules/hosts/$2.nix" 2>/dev/null | head -1)
  echo "${f:-metal}"
}

# host_wsl <repo> <host> <key>: windowsHost, distro or sshAgent from the host file's
# `wsl = { … };` (either spelling, one key per line or all on one); distro defaults to the host
host_wsl() {
  local v
  v=$(sed -nE -e '/^[[:space:]]*#/d' -e 's/^/ /' -e "s/.*[^A-Za-z0-9_]$3[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\\1/p" "$1/modules/hosts/$2.nix" 2>/dev/null | head -1)
  [ -z "$v" ] && [ "$3" = distro ] && v="$2"
  echo "$v"
}

# wsl_skip_names <repo>: the first column of packages/wsl-skip.tsv
wsl_skip_names() {
  grep -vE '^[[:space:]]*(#|$)' "$1/packages/wsl-skip.tsv" 2>/dev/null | cut -f1 || true
}

host_addresses() {
  local f name addr
  for f in "$1"/modules/hosts/*.nix; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .nix)
    # a WSL clone is reached through its Windows PC, never by ssh to Linux
    [ "$(host_form "$1" "$name")" = wsl ] && continue
    # same parse as bin/release.sh: `address = "…"` inside dram = { } or dram.address = "…"
    addr=$(sed -nE 's/^[[:space:]]*(dram\.)?address[[:space:]]*=[[:space:]]*"([^"]+)".*/\2/p' "$f" | head -1)
    [ -n "$addr" ] && echo "$name=$addr"
  done
  return 0
}

# host_user <repo> <host>: the host's login (dram.user in modules/hosts/<host>.nix), default pj
host_user() {
  local u
  u=$(sed -nE 's/^[[:space:]]*(dram\.)?user[[:space:]]*=[[:space:]]*"([^"]+)".*/\2/p' "$1/modules/hosts/$2.nix" 2>/dev/null | head -1)
  echo "${u:-pj}"
}
hosts_with_role() {
  local f
  for f in "$1"/modules/hosts/*.nix; do
    [ -f "$f" ] || continue
    roles_of "$f" | grep -qx "$2" && basename "$f" .nix
  done
  return 0
}
