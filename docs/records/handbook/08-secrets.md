# 8. Secrets

The repo carries secrets as ciphertext only. `sops` encrypts
`secrets/pj.yaml` with `age` for a list of recipients — one software key per host, plus
the two YubiKeys (`docs/security/identity/yubikeys.md`); the sops-nix Home Manager module decrypts it on the
host at login and on every `dram switch` into a tmpfs file that programs read by path. The
only secret it was made for is the Borg passphrase, and backups are paused (chapter 5), so
every host built in the 2026-10 reinstall starts with `secrets.enable = false` and the
file is re-made when the first secret is needed (§"After the 2026-10 reinstall"). Nothing
in this chapter prints a secret.

Reference: `docs/security/identity/secrets.md` (the model and the runbook), `modules/secrets.nix`
(the sops-nix options), `.sops.yaml` (the recipients), `secrets/README.md`,
`system/secrets-bootstrap.sh --help`, `docs/commands.md`.

## Before you start

- A host past chapter 2. `sops`, `age` and `age-keygen` come from the flake
  (`modules/dev.nix`): `type -a sops age age-keygen` lists them under
  `~/.nix-profile/bin`.
- The Mac for the registration step (it runs the same script with bash 3.2).
- On a host that already works, `dram doctor` shows a `secrets` section with
  three `[ok]` lines; that is what every host converges to.

## The model

| Thing | Where | In git? |
|---|---|---|
| age private key, one per host | `~/.config/sops/age/keys.txt` (0600, directory 0700) | never |
| age public keys | `.sops.yaml`: a `# host: <name>` marker, then `- &<name> age1…`; the anchors are repeated under `creation_rules` → `key_groups` → `age` | yes |
| the YubiKeys' recipients | `.sops.yaml`: `# yubikey: <label>`, `- &yk_<label> age1yubikey1…`, `*yk_<label>` in the rule; the identity stub `~/.config/sops/age/yubikey-<label>.txt` names the key and slot (no secret) | the recipients yes; the stubs stay on each machine |
| the secrets | `secrets/pj.yaml`, sops ciphertext for every recipient | yes; the flake only sees tracked files |
| decrypted copies | `$XDG_RUNTIME_DIR/secrets.d/<generation>/…` (tmpfs), written by the user unit `sops-nix.service`; stable symlink `~/.config/sops-nix/secrets/<name>`, mode 0400 | no (runtime) |
| plaintext scratch | `secrets/*.plain`, `*.plain.yaml` | gitignored and refused by `bin/check.sh` §7 |

`modules/secrets.nix` is imported on every host and does nothing until
`modules/hosts/<host>.nix` sets `dram.secrets.enable = true` (no host does after the
2026-10 reinstall, until a secret is needed). With the flag on it sets `sops.age.keyFile` to the path above,
`sops.defaultSopsFile = ../secrets/pj.yaml`, and declares
`sops.secrets.borg_passphrase` with mode 0400. sops-nix validates
`secrets/pj.yaml` at evaluation time, so the file must exist and be committed
before a host flips the flag; a brand-new host can `dram switch` with the flag
off and no key.

The YubiKeys are what make a lost host harmless: either key decrypts and re-keys
`secrets/pj.yaml` on any machine with age-plugin-yubikey (its PIV PIN once, a touch), so
adding or replacing a host never needs a surviving host. The hosts keep their own software
key because the login-time decrypt must never wait for a PIN or a touch.

```sh
SOPS_AGE_KEY_FILE=~/.config/sops/age/yubikey-primary.txt sops secrets/pj.yaml              # edit
SOPS_AGE_KEY_FILE=~/.config/sops/age/yubikey-primary.txt sops updatekeys secrets/pj.yaml   # re-encrypt for .sops.yaml's recipients
```

## What a working host looks like

```sh
systemctl --user status sops-nix               # "inactive (dead)" with status=0/SUCCESS is the good state (oneshot, no RemainAfterExit)
ls -lL ~/.config/sops-nix/secrets/             # -r-------- borg_passphrase
ls -l ~/.config/sops/age/keys.txt              # -rw-------
age-keygen -y ~/.config/sops/age/keys.txt      # this host's PUBLIC key; must equal its line in .sops.yaml
bash ~/git/dotfiles/system/secrets-bootstrap.sh --verify   # prints: ==> match: secrets/pj.yaml#borg_passphrase == /home/pj/.config/borgmatic/passphrase
dram doctor                                    # secrets section:
```

```
secrets
[ok] sops-nix.service last run succeeded
[ok] borg_passphrase secret present, 0400
[ok] age key is 0600
```

`--verify` decrypts `borg_passphrase` with this host's key and compares its
sha256 with the plain fallback `~/.config/borgmatic/passphrase`; it prints
`==> match: secrets/pj.yaml#borg_passphrase == /home/pj/.config/borgmatic/passphrase`
or `MISMATCH` and nothing else. A host with the flag off prints
`[i] sops not enabled (docs/security/identity/secrets.md)` instead of the three lines.

## Adding a secret

1. Edit the file with sops on any host that decrypts it (the Mac has no age
   key, so not there). sops opens `$EDITOR` on the plaintext, re-encrypts for
   every recipient in `.sops.yaml` on save, and leaves nothing on disk:

   ```sh
   cd ~/git/dotfiles
   sops secrets/pj.yaml          # add a line:  name: value   (quote the value if it has YAML punctuation)
   git commit -am "secrets: <name>"
   ```

   `git diff` of the result shows only ciphertext and a changed `mac`.

2. Declare it for sops-nix in `modules/secrets.nix`, inside the existing
   `config = lib.mkIf config.dram.secrets.enable { … }` block:

   ```nix
   sops.secrets.<name> = { };          # 0400 by default; { mode = "0440"; } or { path = "…"; } when needed
   ```

3. `dram switch` on each host (it restarts `sops-nix.service`), then
   `ls -lL ~/.config/sops-nix/secrets/<name>` shows a 0400 file. Get the commit
   to the other hosts first: on the Mac, `git pull <user>@<address>:git/dotfiles master`
   from the host the edit was made on, then `bin/push-host.sh <user>@<address>` to the
   others. The hosts have no git remote; the Mac carries every commit.

Reading it:

- **From a Home Manager module**: the path, never the value, and only behind
  the flag, so evaluation does not touch `config.sops.*` on a host with it
  off. The pattern from `modules/backup.nix`:

  ```nix
  passphraseFile =
    if config.dram.secrets.enable then config.sops.secrets.<name>.path
    else "<fallback path>";
  ```

  and the program is handed that path (`encryption_passcommand = "cat ${passphraseFile}"`).
  A secret must never become a string in a Nix expression: that would copy it
  into the world-readable Nix store.

- **From a script on the host**: `cat ~/.config/sops-nix/secrets/<name>`
  (0400, owned by `pj`, present after login). To read straight from the
  ciphertext without the unit, from the repo root:

  ```sh
  sops --decrypt --extract '["<name>"]' secrets/pj.yaml
  ```

  sops finds the key in `~/.config/sops/age/keys.txt` (its default) and the
  rules in `.sops.yaml`. Pipe it into the consumer; do not echo it.

## Adding a host

Order: key on the host, registered on the Mac and committed, the ciphertext
re-encrypted from a host that already decrypts, then the flag.

1. **On the new host**, generate its key. The script creates the directory
   (0700) and file (0600) if missing and prints only the public half:

   ```sh
   bash ~/git/dotfiles/system/secrets-bootstrap.sh
   ```

   ```
   ==> generating the age key for <host> -> /home/pj/.config/sops/age/keys.txt

   public key for <host>:
     age1…

   next, on the Mac:
     bash system/secrets-bootstrap.sh --register <host> age1…
   ```

2. **In `.sops.yaml`**, add the host's two anchors by hand (the script only
   fills an existing marker). Under `keys:`

   ```yaml
     # host: <host>
     - &<host> age1REPLACE
   ```

   and under `creation_rules` → `key_groups` → `age:`

   ```yaml
             - *<host>
   ```

3. **On the Mac**, register the real key and commit:

   ```sh
   bash system/secrets-bootstrap.sh --register <host> age1…
   git add .sops.yaml && git commit -m "sops: register <host>"
   ```

   It prints `==> registered <host> in .sops.yaml` and, because `pj.yaml`
   exists, names the next step. It refuses a malformed key and
   refuses to overwrite a real one (`already has a different real key`).

4. **With a YubiKey, on any host that has its stub** (the new host itself works once
   `dram yubikey enroll` or `age-plugin-yubikey --identity` made the stub there),
   re-encrypt for the new recipient set, then commit:

   ```sh
   cd ~/git/dotfiles                   # after bin/push-host.sh <user>@<address> from the Mac brought the .sops.yaml commit
   SOPS_AGE_KEY_FILE=~/.config/sops/age/yubikey-primary.txt sops updatekeys secrets/pj.yaml   # shows the added recipient, asks: y
   git commit -am "secrets: re-key for <host>"
   ```

   On the Mac: `git pull <user>@<address>:git/dotfiles master` from that host, then
   `bin/push-host.sh` to the others.

5. **On the new host**, set `secrets.enable = true;` inside the `dram = { … };`
   block of `modules/hosts/<host>.nix`, commit, and:

   ```sh
   dram switch
   dram doctor        # the three [ok] lines above
   ```

   `sops-nix.service` failing with a message about no matching key means step
   4 was not committed or not pulled; `journalctl --user -u sops-nix` shows it.

`bash system/secrets-bootstrap.sh --dry-run` with any mode says what would
change and changes nothing.

## Re-keying or removing a host

**Re-key** (the key may have leaked, or the host was rebuilt without restoring
`~/.config`):

1. On the host, move the old key aside (the script keeps an existing file):
   `mv ~/.config/sops/age/keys.txt ~/.config/sops/age/keys.txt.old`, then
   `bash ~/git/dotfiles/system/secrets-bootstrap.sh` prints the new public key.
2. On the Mac, replace the `- &<host> age1…` line in `.sops.yaml` by hand
   (`--register` refuses to replace a real key on purpose), commit.
3. With a YubiKey (the line above step 4 of "Adding a host"), `sops updatekeys
   secrets/pj.yaml`, commit, push to every host.
4. On the re-keyed host, `dram switch`, `dram doctor`, then delete
   `keys.txt.old`.

**Remove a host**: delete its `# host:` marker, its `&<host>` line and its
`*<host>` line from `.sops.yaml`, `sops updatekeys secrets/pj.yaml` with a YubiKey,
commit. The git history still holds ciphertext that the
removed key can open, so if that key may be in someone else's hands, change
the secrets themselves as well (for the Borg passphrase: `docs/operations/backups/README.md`).

## If a key is lost

- **The host is alive, only the file is gone**, or **the host is dead**: re-key it
  (above); a YubiKey does the re-encryption, so nothing is locked.
- **A YubiKey is lost**: remove its three lines from `.sops.yaml` and `sops updatekeys`
  with the other key (`docs/security/identity/yubikeys.md`, "A key is lost").
- **Every host key and both YubiKeys are gone**: `secrets/pj.yaml` cannot be opened
  by anyone. The passphrase itself survives in Proton Pass. Rebuild a host (chapter 1),
  generate a key, register it, set the flag, then recreate the ciphertext
  rather than opening the old one: place the passphrase in
  `~/.config/borgmatic/passphrase` (0600, one line), delete the old
  `secrets/pj.yaml`, and run `bash ~/git/dotfiles/system/secrets-bootstrap.sh --init-borg`.
  It encrypts that file as `borg_passphrase` for every real recipient in
  `.sops.yaml`, verifies, and stages the result; commit it. It never prints the
  value, and refuses while any recipient is still `age1REPLACE`.

## After the 2026-10 reinstall

`.sops.yaml` still names the old cabin and lantern keys, and `secrets/pj.yaml` is
encrypted for them: both died with the old installs (the fresh start kept no keys), so
nothing opens the file now, and nothing needs it while backups are paused. When the
first secret is needed again:

1. Each host: `bash ~/git/dotfiles/system/secrets-bootstrap.sh` (a new key; its public
   half printed).
2. On the Mac: set each `- &<host> age1…` line back to `- &<host> age1REPLACE` (by hand),
   then `bash system/secrets-bootstrap.sh --register <host> age1…` per host; the YubiKeys
   are in already if `dram yubikey enroll` ran (chapter 2 §5).
3. On the Mac: `git rm secrets/pj.yaml`, commit, push.
4. On a host: put the secret in place and create the file — for the Borg passphrase
   `bash ~/git/dotfiles/system/secrets-bootstrap.sh --init-borg` (it encrypts for every
   recipient, the YubiKeys included); for anything else `sops secrets/pj.yaml`. Commit,
   bring it to the Mac, set `secrets.enable = true` in the hosts that need it.

## What must never be committed, and the guard

Never tracked: `~/.config/sops/age/keys.txt` or any copy of it, `*.plain`,
`*.plain.yaml`, `~/.config/borgmatic/passphrase`, `~/.ssh/id_*`,
`~/.ssh/config.d/*.conf`, anything under `~/.gnupg`. The repo's `.gitignore`
lists `secrets/**/*.plain` and `*.plain.yaml`; the `sops` edit flow leaves no
plaintext behind, and `--init-borg` works in a 0700 temporary directory that
is removed on exit.

`bash bin/check.sh` §7 is the guard, run on the Mac before every push and by
chapter 3's cadence:

- it fails on any tracked path whose name looks like key material
  (`id_<anything>`, `*.key`, `*.pem`) or contains `passphrase`, `secret` or
  `token`, except the sops scaffold it knows (`modules/secrets.nix`,
  `docs/security/identity/secrets.md`, `secrets/README.md`, `.sops.yaml`,
  `system/secrets-bootstrap.sh`, `secrets/*.yaml`);
- it fails on any tracked file containing a `BEGIN … PRIVATE KEY` block.

A hit prints `[!] secret-looking tracked files: <paths>` or
`[!] private key material in: <paths>` and the run ends with `N failure(s)`.
Remove the file from the index (`git rm --cached <path>`), add an ignore rule,
and if it was ever pushed, treat the secret as leaked and rotate it.

## Done when

- [ ] `dram doctor` on every host with `secrets.enable = true` prints the three `[ok]`
      lines of the `secrets` section (the others print `[i] sops not enabled`).
- [ ] `.sops.yaml` lists both YubiKeys (`# yubikey: primary`, `# yubikey: spare`).
- [ ] `age-keygen -y ~/.config/sops/age/keys.txt` on each host equals that
      host's line in `.sops.yaml`.
- [ ] `git ls-files secrets/` lists only `README.md` and `pj.yaml`, and
      `bash bin/check.sh` passes §7.
- [ ] Proton Pass holds each YubiKey's PIV PIN and PUK.
