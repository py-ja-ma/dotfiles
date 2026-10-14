#!/usr/bin/env bash
# usage: yubikey-t1.sh
#
# Test tier T1 for the YubiKeys (decisions/0019), inside a throwaway amd64 Arch
# container as root — it rewrites /etc/pam.d and refuses to run anywhere else. Real
# packages, no key: sudo with system/yubikey-setup.sh's pam_u2f line (no map line ->
# the password alone; a map line and no key -> refused and faillock counts nothing;
# pam-u2f missing or the map missing -> the password alone), u2f-selftest.py failing
# fast without a key, the initramfs mkinitcpio builds with libfido2 installed,
# install/lib/luks.sh on a file-backed LUKS2 header, and harden.sh's sshd drop-in
# through `sshd -T`. From the Mac (tests/README.md, Colima profile t1):
#   docker --context colima-t1 run --rm --platform linux/amd64 -v "$PWD:/repo:ro" \
#     archlinux:latest bash /repo/tests/yubikey-t1.sh
#
#   -h, --help    this text
#
# exit: 0 every check passed · 1 a check failed or not a container · 2 bad usage
# see: docs/security/identity/yubikeys.md

case "${1:-}" in
  "") ;;
  -h | --help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    sed -n '2s/^# \{0,1\}//p' "$0" >&2
    exit 2
    ;;
esac

set -uo pipefail
[ -f /.dockerenv ] || [ -f /run/.containerenv ] || {
  echo "yubikey-t1: not inside a container — refusing (it rewrites /etc/pam.d)" >&2
  exit 1
}
[ "$(id -u)" -eq 0 ] || {
  echo "yubikey-t1: run as root inside the container" >&2
  exit 1
}
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
R=/opt/dram-t1
FAILS=0
ok() { echo "ok   $1"; }
bad() {
  echo "FAIL $1${2:+ — $2}"
  FAILS=$((FAILS + 1))
}
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want '$3', got '$2'"; fi; }

# a writable copy of the repo pieces the hooks read
rm -rf "$R" && mkdir -p "$R"
(cd "$SRC" && tar -cf - system keys install bin) | tar -xf - -C "$R"
# packages: the pacman sandbox does not work under Rosetta; mirrors as on a new host
grep -qx 'DisableSandbox' /etc/pacman.conf || sed -i 's/^\[options\]/[options]\nDisableSandbox/' /etc/pacman.conf
cp "$SRC/install/mirrorlist" /etc/pacman.d/mirrorlist
pacman -Sy --noconfirm --needed archlinux-keyring >/dev/null 2>&1
pacman -Su --noconfirm >/dev/null 2>&1
pacman -S --noconfirm --needed sudo polkit ly hyprlock pam-u2f libfido2 cryptsetup mkinitcpio linux openssh python >/dev/null 2>&1 \
  || bad "pacman -S of the test set"
id t1user >/dev/null 2>&1 || useradd -m -G wheel -s /bin/bash t1user
printf 't1user:t1-pass\n' | chpasswd
printf '%%wheel ALL=(ALL:ALL) ALL\n' >/etc/sudoers.d/wheel && chmod 440 /etc/sudoers.d/wheel
sudo_as() { su t1user -c "printf '%s\n%s\n%s\n' '$1' '$1' '$1' | timeout 30 sudo -S -k -p '' true" >/dev/null 2>&1; }
MAP=/etc/dram/u2f_mappings

# --- the hook and the PAM outcomes ------------------------------------------------------
DRAM_USER=t1user bash "$R/system/yubikey-setup.sh" >/tmp/t1-hook.log 2>&1
expect_eq "yubikey-setup.sh with nothing listed: exit 0" "$?" 0
line="$(grep -E '^auth[[:space:]].*pam_u2f\.so' "$R/system/pam-u2f.conf")"
for f in sudo login polkit-1; do
  if grep -qxF "$line" "/etc/pam.d/$f"; then ok "/etc/pam.d/$f has the line"; else bad "/etc/pam.d/$f has the line"; fi
done
for f in ly hyprlock; do
  if grep -qE '^auth[[:space:]]+include[[:space:]]+login' "/etc/pam.d/$f"; then ok "/etc/pam.d/$f includes login"; else bad "/etc/pam.d/$f includes login"; fi
done
grep -q 'pam_permit' /etc/pam.d/ly-autologin && ok "ly-autologin (the Gaming Mode switch) stays pam_permit" || bad "ly-autologin stays pam_permit"
sudo_as t1-pass
expect_eq "no map line: the password alone" "$?" 0
printf 't1user:AAAAbbbbCCCCdddd==,BBBBccccDDDD==,es256,+presence\n' >"$MAP"
faillock --user t1user --reset
sudo_as t1-pass
expect_eq "a map line and no key: refused" "$?" 1
expect_eq "… and faillock counts nothing" "$(faillock --user t1user | tail -n +3 | grep -c .)" 0
mv /usr/lib/security/pam_u2f.so /usr/lib/security/pam_u2f.so.t1
sudo_as t1-pass
expect_eq "pam-u2f missing: the password alone (module_unknown=ignore)" "$?" 0
mv /usr/lib/security/pam_u2f.so.t1 /usr/lib/security/pam_u2f.so
rm -f "$MAP"
sudo_as t1-pass
expect_eq "the map missing: the password alone (nouserok)" "$?" 0
sudo_as wrong-pass
expect_eq "a wrong password: refused" "$?" 1
faillock --user t1user --reset
printf 't1user:AAAAbbbbCCCCdddd==,BBBBccccDDDD==,es256,+presence\n' >/tmp/t1-cand && chmod 644 /tmp/t1-cand
start="$(date +%s)"
python3 -I "$R/system/u2f-selftest.py" --authfile /tmp/t1-cand --user t1user >/dev/null 2>&1
expect_eq "u2f-selftest.py without a key: exit 1" "$?" 1
[ $(($(date +%s) - start)) -le 5 ] && ok "… within 5 s" || bad "… within 5 s"
[ -e /etc/pam.d/dram-u2f-test ] && bad "the self-test removes its service" || ok "the self-test removes its service"
DRAM_USER=t1user bash "$R/system/yubikey-setup.sh" --off >/dev/null 2>&1
expect_eq "--off: the map has no line" "$(grep -c '^t1user:' "$MAP")" 0

# --- the initramfs: what sd-encrypt adds with libfido2 installed --------------------------
kver="$(ls /usr/lib/modules | head -1)"
printf 'HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)\n' >/tmp/t1-mk.conf
if mkinitcpio -c /tmp/t1-mk.conf -k "$kver" -g /tmp/t1.img -S autodetect >/tmp/t1-mk.log 2>&1; then
  list="$(lsinitcpio /tmp/t1.img)"
  for f in usr/lib/libfido2.so.1 usr/lib/cryptsetup/libcryptsetup-token-systemd-fido2.so usr/lib/udev/rules.d/60-fido-id.rules usr/lib/udev/fido_id; do
    grep -qx "$f" <<<"$list" && ok "initramfs has $f" || bad "initramfs has $f"
  done
  for m in usbhid hid-generic xhci-hcd xhci-pci hid; do
    grep -q "/$m.ko" "/usr/lib/modules/$kver/modules.builtin" && ok "$m is built into the kernel" || bad "$m is built into the kernel"
  done
else bad "mkinitcpio" "$(tail -1 /tmp/t1-mk.log)"; fi

# --- install/lib/luks.sh on a real LUKS2 header -------------------------------------------
img=/tmp/t1-luks.img
rm -f "$img" && truncate -s 40M "$img"
printf 'k1' >/tmp/t1-k1 && printf 'k2' >/tmp/t1-k2
cryptsetup luksFormat --type luks2 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --batch-mode "$img" /tmp/t1-k1 >/dev/null 2>&1
cryptsetup luksAddKey --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --key-file /tmp/t1-k1 "$img" /tmp/t1-k2 >/dev/null 2>&1
cryptsetup luksAddKey --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --key-file /tmp/t1-k1 "$img" /tmp/t1-k2 >/dev/null 2>&1
printf '{"type":"systemd-tpm2","keyslots":["1"],"tpm2-pin":true}' >/tmp/t1-tpm.json
printf '{"type":"systemd-fido2","keyslots":["2"],"fido2-credential":"AAAA","fido2-salt":"BBBB","fido2-rp":"io.systemd.cryptsetup","fido2-clientPin-required":true,"fido2-up-required":true,"fido2-uv-required":false}' >/tmp/t1-fido.json
{ cryptsetup token import --disable-external-tokens --json-file /tmp/t1-tpm.json "$img" \
  && cryptsetup token import --disable-external-tokens --json-file /tmp/t1-fido.json "$img"; } >/dev/null 2>&1 || bad "cryptsetup token import"
# shellcheck source=../install/lib/luks.sh
. "$R/install/lib/luks.sh"
expect_eq "luks: the options for TPM2 + YubiKey" "$(luks_rd_options "$img")" "tpm2-device=auto,fido2-device=auto,tries=0,discard"
expect_eq "luks: the TPM2 slot starts at normal" "$(luks_query "$img" priority:1)" 1
luks_prefer_tpm2 "$img" >/dev/null 2>&1
expect_eq "luks: … and is prefer afterwards" "$(luks_query "$img" priority:1)" 2
cryptsetup luksDump "$img" | grep -q 'Priority:[[:space:]]*preferred' && ok "luks: cryptsetup agrees (preferred)" || bad "luks: cryptsetup agrees (preferred)"

# --- sshd: the drop-in harden.sh writes ------------------------------------------------------
ssh-keygen -A >/dev/null 2>&1
mkdir -p /etc/ssh/sshd_config.d
sed -n "/^cat >\"\$tmp_sshd\" <<'EOF2'\$/,/^EOF2\$/p" "$R/system/harden.sh" | sed '1d;$d' >/etc/ssh/sshd_config.d/10-keys-only.conf
/usr/sbin/sshd -t && ok "sshd -t accepts the drop-in" || bad "sshd -t accepts the drop-in"
t="$(/usr/sbin/sshd -T 2>/dev/null)"
grep -qi '^authorizedkeysfile .ssh/authorized_keys /etc/ssh/authorized_keys.d/%u' <<<"$t" && ok "sshd -T: both keys files" || bad "sshd -T: both keys files"
grep -qi '^pubkeyauthoptions touch-required' <<<"$t" && ok "sshd -T: touch-required" || bad "sshd -T: touch-required"

[ "$FAILS" -eq 0 ] || {
  echo "yubikey-t1: $FAILS check(s) failed" >&2
  exit 1
}
echo "yubikey-t1: all checks passed"
