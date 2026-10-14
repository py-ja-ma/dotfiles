-- Gaming Mode (decisions/0012): Hyprland with nothing but Steam Big Picture.
-- ly's "Gaming Mode" entry runs /usr/lib/dram/session-hyprland gaming, which starts
-- Hyprland with THIS file instead of hyprland.lua (pkgs/dram-gaming-mode). No bar, no
-- wallpaper, no idle lock, one monitor. It is the default gaming entry until cabin's
-- hardware test promotes "Gaming Mode (gamescope, experimental)" (docs/toolchain/profiles/gaming.md).
--
--   SUPER+CTRL+D        back to the Desktop (ly logs you straight in; keyring stays locked)
--   SUPER+SHIFT+ESCAPE  leave Gaming Mode to the ly menu
--   SUPER+Q             a terminal, SUPER+C closes a window, SUPER+F fullscreen

local function exists(p) local f = io.open(p) if f then f:close() return true end return false end
local FACTS = (function()
  local ok, t = pcall(dofile, os.getenv("HOME") .. "/.config/dram/facts.lua")
  return (ok and type(t) == "table") and t or {}
end)()
local IS_LAPTOP = (type(FACTS.laptop) == "boolean") and FACTS.laptop
  or exists("/sys/class/power_supply/BAT0/present") or exists("/sys/class/power_supply/BAT1/present")

------------------
---- MONITORS ----
------------------
-- One screen, like a console: the main (left) panel at its full 165 Hz, the middle one
-- off. The panels are named as in hyprland.lua, from ~/.config/dram/monitors.lua or by
-- cabin's ports. Anything else, a laptop panel included, takes its preferred mode.
local MONITORS = (function()
  local ok, t = pcall(dofile, os.getenv("HOME") .. "/.config/dram/monitors.lua")
  return (ok and type(t) == "table") and t or {}
end)()
local MON_MAIN = MONITORS.main or "DP-1"
local MON_MID  = MONITORS.mid or "HDMI-A-1"
hl.monitor({ output = MON_MAIN, mode = IS_LAPTOP and "2560x1440@59.95" or "2560x1440@165", position = "0x0", scale = 1 })
hl.monitor({ output = MON_MID, disabled = true })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-------------------
---- AUTOSTART ----
-------------------
hl.on("hyprland.start", function ()
  -- the same hand-off as hyprland.lua: portals, the polkit agent and the HM user units
  -- need the Wayland environment and graphical-session.target
  hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP DRAM_SESSION && systemctl --user start hyprland-session.target")
  hl.exec_cmd("systemctl --user start hyprpolkitagent")
  -- Big Picture; when Steam exits for good, so does Gaming Mode (back to the ly menu)
  hl.exec_cmd("steam -gamepadui; hyprctl dispatch 'hl.dsp.exit()'")
end)

-----------------
---- LOOK -------
-----------------
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.config({ ecosystem = { no_update_news = true, no_donation_nag = true } })
hl.config({
    general = {
        gaps_in = 0,
        gaps_out = 0,
        border_size = 0,
        allow_tearing = true,   -- `immediate` games tear for the lowest latency, as on the desktop
        layout = "dwindle",
    },
    decoration = {
        rounding = 0,
        blur = { enabled = false },
        shadow = { enabled = false },
    },
    animations = { enabled = false },
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
        focus_on_activate = true,
        key_press_enables_dpms = true,
    },
    input = {
        kb_layout = "us",
        follow_mouse = 1,
        sensitivity = 0,
        accel_profile = "flat",   -- the same deltas as the desktop (docs/toolchain/profiles/gaming.md)
    },
})

-------------------
---- RULES --------
-------------------
-- Big Picture and every game are real fullscreen; games present immediately (tearing).
hl.window_rule({
    name  = "gaming-steam-fullscreen",
    match = { class = "^(steam|steamwebhelper)$" },
    fullscreen = true,
})
hl.window_rule({
    name  = "gaming-games-fullscreen",
    match = { class = "^(cs2|steam_app_\\d+)$" },
    fullscreen = true,
    immediate  = true,
})
-- no hypridle runs here; a fullscreen window still inhibits any idle client that does
hl.window_rule({
    name  = "gaming-no-idle",
    match = { fullscreen = true },
    idle_inhibit = "fullscreen",
})

-------------------
---- KEYS ---------
-------------------
local mainMod = "SUPER"
hl.bind(mainMod .. " + CTRL + D", hl.dsp.exec_cmd("steamos-session-select desktop"), { description = "back to the Desktop" })
hl.bind(mainMod .. " + SHIFT + Escape", hl.dsp.exit(), { description = "leave Gaming Mode (ly menu)" })
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd("kitty"), { description = "terminal" })
hl.bind(mainMod .. " + C", hl.dsp.window.close(), { description = "close window" })
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen(), { description = "fullscreen toggle" })
