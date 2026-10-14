# dram-gaming-mode review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › dram-gaming-mode

My own glue for [decision 0012](../../decisions/0012-gaming-mode.md): three ly sessions and switching between them, which upstream provides only for LightDM and SDDM.
Its fact box, its files and how to copy it are in [README.md](README.md).

## What it is

- `/usr/share/wayland-sessions/dram-desktop.desktop` ("Desktop") and `dram-gaming.desktop` ("Gaming Mode") both run `/usr/lib/dram/session-hyprland`, which starts `start-hyprland`, the gaming one with `--config ~/.config/hypr/gaming.lua`. Neither has `DesktopNames=`: ly 1.4.1 matches an autologin session by file name, `Name=` or `DesktopNames=`, case-insensitively, and the first hit wins, so `Hyprland` there would collide with Arch's `hyprland.desktop`. The third entry, "Gaming Mode (gamescope, experimental)", is `gamescope-session-steam.desktop` from that package.
- `/usr/lib/os-session-select` is the hook `steamos-session-select` runs. It maps the SteamOS names (`desktop`, `gamescope`, `plasma…`) and mine (`gaming`, `big-picture`) to a session. `/etc/dram/gaming-mode` set to `gamescope` makes the experimental session the default Gaming Mode.
- `/usr/lib/dram/session-switch` runs as root through `pkexec`, under the polkit action `org.dram.session-select`, which allows the active local session only: no remote or inactive caller, and no password at the machine. The user is `PKEXEC_UID`, never an argument, and the session is one of three fixed names. It writes `/run/dram/ly-next-session`, then a transient system unit (`systemd-run`) ends the caller's ly session and restarts `ly@ttyN`. `--finish`, what that unit runs, refuses to run under pkexec, so no user can use it to end other sessions.
- `/usr/lib/dram/ly-prepare` and the drop-in `ly@.service.d/dram-session.conf` (`ExecStartPre=-`) run before each ly start.
  A request younger than five minutes becomes ly's `auto_login_session` and `auto_login_user`, and otherwise both keys are removed.
  ly logs in automatically once per start (its `ly-autologin` PAM service is `pam_permit`), never after a logout, so the keys cannot fire again.
  There is no lasting autologin.
  The login keyring stays locked after a switch, because no password reached PAM, and [decision 0012](../../decisions/0012-gaming-mode.md) accepts that.
- `/usr/share/applications/dram-gaming-mode.desktop` is "Switch to Gaming Mode", and `/usr/lib/modules-load.d/dram-uinput.conf` loads `uinput` for Steam Input's virtual pads.

## Runs at build and install time

`package()` installs the files; there is no `.install` and no hook.

## Tests

`tests/gaming-switch.sh`, in `bin/check.sh` §16 on any machine with bash, runs `os-session-select --print` and `ly-prepare` against temporary ini and Lua configs.
The amd64 container test builds and installs the package.
