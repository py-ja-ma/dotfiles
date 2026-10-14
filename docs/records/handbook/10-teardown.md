# 10. Teardown

> **Read this block before any command on this page.**
>
> Four things on this page cannot be undone by any script in this repo:
>
> - **The copy you keep.** Backups are paused until the NAS
>   (`decisions/0014-backups-paused-until-nas.md`): no host's data lives on another
>   host. What survives a host is what you copied to the Mac (chapter 5 §3) and the commits
>   the Mac pulled. Everything else on the disk goes with it.
> - **The age key** (`~/.config/sops/age/keys.txt`, one per host). It decrypts
>   `secrets/pj.yaml` for that host — every commit of it. Either YubiKey decrypts the file
>   too (chapter 8), so a lost host key costs nothing while a key is in hand; lose both
>   YubiKeys *and* every host key and the file is sealed.
> - **The `[dram]` signing key** (`~/.gnupg` on the builder, cabin). The private half
>   exists nowhere else unless you exported it. Without it, the next builder makes a new key
>   (`dram pkgs key --new`) and every package is rebuilt and re-signed (chapter 7).
> - **The disk.** No script on a running system wipes anything. `install/arch-install.sh`,
>   from the ISO, wipes every disk it is given (chapter 1); that is the step that destroys.
>
> `--plan` is the default of both teardown scripts and changes nothing. `--execute` asks
> for the hostname typed back and refuses without a terminal — never pipe into it, never
> run it over `ssh host 'bash …'`.

Reference: `system/decommission.sh --help` (the host side), `bin/forget-host.sh --help`
(the Mac side), `docs/security/identity/yubikeys.md` ("A key is lost"), `docs/toolchain/packaging/README.md` §2 ("The signing
key"), `pkgs/README.md` ("Key custody"), `docs/security/network/vpn.md`.

## Before you start

- The Mac has a clean tree (`git status` prints nothing) and reaches the host
  (`ssh <user>@<address> true`). A host that is already dead skips its own steps;
  everything else on this page still applies.
- Proton Pass holds the YubiKeys' PINs and PUK, the LUKS recovery key (laptops), and the
  signing-key export if you keep one.

## 1. Reinstall a host under its own name

The common case — cabin in 2026-10. The name, the host file and the roles stay; the disk,
its keys and its state are new. Not a retirement: skip the rest of this page.

```sh
# on the Mac, while the old system still runs: the copy you keep (chapter 5 §3)
mkdir -p ~/backups/<host>
rsync -aHv --info=progress2 <user>@<address>:documents/ ~/backups/<host>/documents/   # and each path you keep
git pull <user>@<address>:git/dotfiles master                                         # its unpulled commits
```

Then decide the builder's signing key (cabin only; §2 step 3): export it to keep the
packages' signatures, or let it go and make a new one after the install (chapter 7,
"`[dram]` from scratch"). Nothing else is removed by hand: the installer wipes the disk,
`dram harvest` rewrites `hosts/<host>/`, and chapter 8 ("After the 2026-10 reinstall")
re-makes the age key when a secret is needed. The Mac forgets the old host key with
`ssh-keygen -R <address>` when chapter 1 §7 asks for it.

## 2. Retire a host

`HOST` is the host being retired, `USER@ADDRESS` how the Mac reaches it
(`modules/hosts/HOST.nix`: `user`, `address`). Every step prints what it would do before
anything is removed.

### 1. The copy you keep

```sh
# on the Mac
mkdir -p ~/backups/HOST
rsync -aHv --info=progress2 USER@ADDRESS:documents/ ~/backups/HOST/documents/       # each path you keep (chapter 5 §3)
git pull USER@ADDRESS:git/dotfiles master                                          # this repo; ~/documents/vault and ~/documents/finance the same way
```

### 2. Read both plans

```sh
# on HOST
bash ~/git/dotfiles/system/decommission.sh          # --plan is the default; ten numbered items and an order
# on the Mac
bin/forget-host.sh HOST                              # --plan is the default; nine items
```

The host's plan is the inventory: the copy you keep, its key on other machines, its sops
recipient, its module and harvest, the Mac scripts that name it, the builder role (with the
signing-key export command when HOST is the builder), the YubiKeys (nothing on them is per
host), the UniFi and GitHub entries, and the local state. Items tagged `[Mac]` are printed
there and done from the Mac. With a backup peer (after the NAS) both plans add the peer's
Borg repository, the pinned key there and any host whose `backupPeer` is HOST.

### 3. If HOST is the builder: the signing key

Only when the plan's builder item shows a fingerprint. Keep it — before the disk goes:

```sh
# on HOST
gpg --armor --export-secret-keys <fingerprint> > ~/dram-signing-key.private.asc
# move the file to Proton Pass (as a note) or to the Mac, then on HOST:
shred -u ~/dram-signing-key.private.asc
```

The next builder imports it (`gpg --import`, then the fingerprint into
`~/.config/dram/gpgkey`) after `DRAM_BUILDER_HOST=<name> sudo bash
system/dram-builder-setup.sh`; `bin/sync-dram-repo.sh` `SRC=` then points at it. Or let it
go: the next builder runs `dram pkgs key --new` (it pins the new key in
`system/pacman-dram-repo.sh` and `pkgs/dram.asc`), rebuilds and publishes every package,
and every host runs `sudo bash system/pacman-dram-repo.sh`, which trusts the new key and
drops the old one (chapter 7, "`[dram]` from scratch").

### 4. The Mac: forget the host

```sh
bin/forget-host.sh HOST --execute                    # asks: type the host name
```

It `git rm`s `modules/hosts/HOST.nix` and `hosts/HOST/`, drops the three `.sops.yaml`
lines for HOST, prints the `bin/sync-dram-repo.sh` lines to edit by hand, and runs
`bin/check.sh`. `check.sh` may fail on two things that are follow-ups, not errors:
`docs/commands.md` (`python3 bin/gen-commands-doc.py`) and docs that cite a path under
`hosts/HOST/`. Nothing is committed; do that once the edits are complete, then re-encrypt
the secrets without HOST's key — with a YubiKey, on any host that has its stub:

```sh
# on the Mac
python3 bin/gen-commands-doc.py
git commit -am "forget HOST"
bin/release.sh                                       # every remaining host gets the commit (chapter 4 §8)
# on a remaining host, at its keyboard, a YubiKey plugged in
cd ~/git/dotfiles && dram update
SOPS_AGE_KEY_FILE=~/.config/sops/age/yubikey-primary.txt sops updatekeys -y secrets/pj.yaml   # PIV PIN, touch
git commit -am "sops: forget HOST"
# on the Mac
git pull <user>@<address>:git/dotfiles master
ssh-keygen -R ADDRESS                                # the Mac's known_hosts
```

With `secrets/pj.yaml` not yet re-made (chapter 8, "After the 2026-10 reinstall") there is
nothing to re-encrypt: the `.sops.yaml` edit is the whole step.

### 5. UniFi and GitHub (by hand)

- UniFi → Settings → VPN → VPN Server → WireGuard: delete the client `HOST`. Client
  Devices: release the reservation for its address, or keep it for the replacement
  (`docs/security/network/vpn.md`).
- GitHub → Settings → SSH and GPG keys: if you added HOST's key, remove **both** entries
  with the fingerprint the plan's GitHub item printed — the authentication key and the
  signing key.

### 6. The host: local teardown

```sh
# on HOST, at its own keyboard or an interactive ssh session (a TTY)
bash ~/git/dotfiles/system/decommission.sh --execute --dry-run     # the commands, nothing changes
bash ~/git/dotfiles/system/decommission.sh --execute               # a warning block, then: type the hostname
```

What it removes: the user timers (`dram-theme-auto`, and `borgmatic` while backups run),
the Home Manager profiles and state (`~/.local/state/nix/profiles`,
`~/.local/state/home-manager`, `~/.local/state/dram`, `~/.config/sops-nix`), a plaintext
Borg passphrase if one exists, and on the builder `/srv/dram` and
`/var/lib/archbuild/dram-x86_64` (sudo). What it leaves: `~/.ssh`, `~/.gnupg`,
`/var/lib/dram-repo`, `/etc/wireguard`, and the age key — that one only with
`--delete-age-key`, after you have decided (step 4 already re-encrypted the secrets without
it).

### 7. Reinstall or wipe (the owner's step)

From the ISO, never from the running system. `install/arch-install.sh` for a reinstall
(chapter 1; a new name means a new host file, chapter 1 §6); `blkdiscard /dev/<disk>` for
an SSD that leaves the house, `dd if=/dev/zero of=/dev/<disk> bs=4M status=progress` for
anything. On a laptop the LUKS header goes with it: the TPM2, FIDO2 and recovery keyslots
open nothing afterwards. The host's private keys (`~/.ssh/id_ed25519`, `~/.gnupg`,
`/etc/wireguard/home.conf`, `/etc/ssh/ssh_host_*`, the age key) die with the disk; every
public counterpart went in steps 4 and 5.

## 3. Retire a YubiKey

A key that is lost: `docs/security/identity/yubikeys.md`, "A key is lost" — its public lines out of the repo, a
release, `dram apply` on each host, its LUKS slot wiped on lantern. A key that is in hand
and leaves the house (sold, given away, replaced): do the same, then wipe it, plugged in
alone:

```sh
ykman fido reset          # every FIDO2 credential: the SSH keys, the pam-u2f credential, the LUKS slot's secret; asks to re-plug and touch
ykman piv reset           # the age identity (a retired PIV slot), the PIV PIN, PUK and management key
ykman fido info           # no PIN set
ykman piv info            # warns about the default PIN
```

The other key keeps working throughout; nothing on a host changes until the release.

## 4. Retire the whole dram

Every host and the Mac's part. The order protects the one thing worth keeping: a readable
copy of each host's data.

1. **Decide what survives.** The irreplaceable set of each host on the Mac (chapter 5 §3),
   the git repos pulled to the Mac, and a second copy of both on an external disk.
2. **The signing key.** Export it from the builder (§2 step 3), or let it die; nothing
   outside this dram uses it.
3. **The hosts.** For each, `decommission.sh --plan`, then `--execute` (with
   `--delete-age-key` when you will never read `secrets/pj.yaml` again).
4. **The Mac's part.** `bash install/mac-launchd.sh --uninstall` if the pull job is still
   loaded (`--status` exits 1 when it is not). Then, only once step 1 is done:
   `~/backups/dram/` (the `[dram]` package mirror), `~/backups/<host>/`, and the older
   copies in `~/backups/` (the Borg mirrors, the 2026-10 one-offs).
5. **Keys and accounts.** GitHub: the hosts' authentication and signing keys. UniFi: the
   WireGuard clients, the reservations. The YubiKeys: §3's reset, or keep them for other
   accounts — they hold nothing of the dram after the reset. Proton Pass: the PINs, the PUK,
   the recovery keys and the signing-key export go with the last thing they open, not before.
6. **The repo.** The hosts' clones go with their disks. The Mac's clone has no public
   remote; keep it, or push it somewhere, before the last wipe.
7. **Wipe** every host from the ISO (§2 step 7).

## 5. Retire only the Mac

The Mac holds four roles. Each moves to another machine before the Mac goes.

| Role | Lives in | Moves by |
|---|---|---|
| The repo and the release tooling | `~/git/dotfiles` with no public remote; `bin/release.sh`, `bin/push-host.sh` (chapter 4 §8) | `git clone <user>@<address>:git/dotfiles` on the new box (a host's clone is complete), or push the Mac's clone to a remote first |
| The way into the hosts | the Mac's software key in each host's `~/.ssh/authorized_keys` (the Mac's YubiKey route is paused, `docs/security/identity/yubikeys.md` "The Mac (lodge)") | a box with OpenSSH 8.2+ built with libfido2 needs no host change: `ssh-keygen -K` loads the YubiKeys' SSH handles and every host's sshd already lists them (`/etc/ssh/authorized_keys.d`). Otherwise append the new box's `~/.ssh/id_ed25519.pub` to each host's `authorized_keys` from the Mac first. Then remove the Mac's line: `ssh <user>@<address> "sed -i '/ pj@Patricks-MacBook-Pro.local\$/d' ~/.ssh/authorized_keys"` (verify the comment on your host) |
| The `[dram]` carrier | `bin/sync-dram-repo.sh`, `~/backups/dram/` | the same clone; the mirror refetches from the builder on the first run |
| The copies you keep | `~/backups/<host>/` (chapter 5 §3) | copy them over, and keep the external-disk copy current |

Then on the Mac: `bash install/mac-launchd.sh --uninstall` if the pull job is still
loaded, delete `~/backups` once the new box holds every copy, and the clone. Nothing on the
hosts changes except the `authorized_keys` lines.

## Undo

What each teardown step destroyed, and where a copy still is.

| Gone | Comes back from | How |
|---|---|---|
| `modules/hosts/HOST.nix`, `hosts/HOST/` | git history | `git log --diff-filter=D --name-only -- modules/hosts` to find the commit; `git checkout <commit>^ -- modules/hosts/HOST.nix hosts/HOST` |
| the `.sops.yaml` recipient | git history + the host's age key | restore the three lines (or `bash system/secrets-bootstrap.sh --register HOST <age1…>` after re-adding the marker), then `sops updatekeys` with a YubiKey (chapter 8) |
| the host's Home Manager state | the flake | `dram switch` rebuilds it; the symlinks were never removed |
| the age key | only a copy you made | a new key: `bash system/secrets-bootstrap.sh`, `--register` on the Mac, `updatekeys` with a YubiKey (chapter 8, "Adding a host") |
| the signing key | only an export you made | `gpg --import`; else `dram pkgs key --new` and a full rebuild (chapter 7) |
| a YubiKey after `ykman fido reset` | nothing | enrol it again under a new label (`docs/security/identity/yubikeys.md`) |
| the data on a wiped disk | the copies on the Mac (chapter 5 §3) | `rsync` back; nothing else holds it until the NAS |
| UniFi client, GitHub keys | nothing | create again (`docs/security/network/vpn.md`; chapter 2) |

## Done when

- [ ] Reinstall: the copy you keep is on the Mac and dated in your notes; the builder's
      signing key is exported or the re-key is decided.
- [ ] Retire a host: `bash bin/check.sh` on the Mac passes with the host gone (the
      `hosts:` line of §2 lists only the survivors), and `nix flake check` on a remaining
      host is green.
- [ ] Retire a host: `grep -c HOST .sops.yaml` prints `0`; `sops --decrypt
      secrets/pj.yaml` with a YubiKey's stub still works (when the file exists).
- [ ] Retire a host: `decommission.sh --execute` printed `local steps done` on the host;
      the disk was wiped or reinstalled from the ISO.
- [ ] Retire a YubiKey: its lines are gone from `keys/ssh.pub`, `keys/pam-u2f.txt` and
      `.sops.yaml`; `dram yubikey status` on a host lists only the other key.
- [ ] Retire the Mac: the new box runs `bin/check.sh` and reaches each host; no host's
      `authorized_keys` names the Mac.
