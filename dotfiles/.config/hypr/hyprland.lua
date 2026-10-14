-- pj's Hyprland config. Lives in ~/git/dotfiles (dotfiles/.config/hypr/); applied by dram-switch.

-- This is an example Hyprland Lua config file.
-- Refer to the wiki for more information.
-- https://wiki.hypr.land/Configuring/Start/

-- Please note not all available settings / options are set here.
-- For a full list, see the wiki

-- You can (and should!!) split this configuration into multiple files
-- Create your files separately and then require them like this:
-- require("myColors")


------------------
---- MONITORS ----
------------------

-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- Physical left-to-right order: screen 3 (main) | screen 2 | laptop (screen 1)
--
-- The two externals are identical NZXT CANVAS 27Q panels, told apart only by the
-- serial at the end of their description (desc:). A rule by description follows a
-- panel from port to port; the dock renumbers its DP-* ports across redocks (DP-6/DP-4
-- have become DP-5/DP-8), which silently breaks port-based rules. The descriptions
-- are this host's own, kept out of the repo in ~/.config/dram/monitors.lua, which
-- monitors-pin.sh writes from the panels as they stand; without it the rules name
-- cabin's ports.
local MONITORS = (function()
  local ok, t = pcall(dofile, os.getenv("HOME") .. "/.config/dram/monitors.lua")
  return (ok and type(t) == "table") and t or {}
end)()
local MON_MAIN = MONITORS.main or "DP-1"       -- leftmost
local MON_MID  = MONITORS.mid or "HDMI-A-1"    -- middle
local MON_LAP  = "eDP-1"                        -- laptop panel (internal name is stable)

-- One config, any machine. The host facts come from Nix (modules/core.nix
-- writes ~/.config/dram/facts.lua = { host, laptop, gpu, location, backupPeer }
-- from the dram.* flags); before the first `dram switch` the file is missing
-- and the probes below stand in. cabin is the desktop with the SAME two NZXT
-- panels and nothing else. Everything laptop-only below is gated on IS_LAPTOP.
local FACTS = (function()
  local ok, t = pcall(dofile, os.getenv("HOME") .. "/.config/dram/facts.lua")
  return (ok and type(t) == "table") and t or {}
end)()
local HOST = os.getenv("DRAM_HOST") or FACTS.host or (function()   -- DRAM_HOST=<name> overrides, for testing
  local f = io.open("/etc/hostname"); if not f then return "" end
  local h = f:read("*l") or ""; f:close(); return h
end)()
local function exists(p) local f = io.open(p) if f then f:close() return true end return false end
-- Laptop = dram.isLaptop, else "has a battery". DRAM_LAPTOP=0/1 overrides, for testing.
local IS_LAPTOP = (function()
  if os.getenv("DRAM_LAPTOP") == "1" then return true end
  if os.getenv("DRAM_LAPTOP") == "0" then return false end
  if type(FACTS.laptop) == "boolean" then return FACTS.laptop end
  return exists("/sys/class/power_supply/BAT0/present") or exists("/sys/class/power_supply/BAT1/present")
end)()
-- Workspaces 1-3 live on the laptop panel when there is one; on the desktop
-- they join MON_MAIN (so MAIN holds 1-6, MID holds 7-9).
local WS_FIRST = IS_LAPTOP and MON_LAP or MON_MAIN
-- The NZXT panels do 165 Hz on DP and 144 Hz on HDMI at 1440p. The laptop dock
-- only drives them at 60, so it keeps 59.95. NOT "highrr": that picks the highest
-- rate at ANY resolution and dropped the desktop to 1920x1080@165 (2026-10-05).
local MON_MODE_MAIN = IS_LAPTOP and "2560x1440@59.95" or "2560x1440@165"
local MON_MODE_MID  = IS_LAPTOP and "2560x1440@59.95" or "2560x1440@144"

hl.monitor({ output = MON_MAIN, mode = MON_MODE_MAIN,     position = "0x0",      scale = 1 })   -- MAIN, leftmost
hl.monitor({ output = MON_MID,  mode = MON_MODE_MID,      position = "2560x0",   scale = 1 })   -- middle
if IS_LAPTOP then
  hl.monitor({ output = MON_LAP,  mode = "1920x1200@60",    position = "5120x640", scale = 1.5 }) -- laptop, rightmost, bottom-aligned
end
-- Fallback for any other monitor
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })


---------------------
---- MY PROGRAMS ----
---------------------

-- Set programs that you use
local terminal    = "kitty"
local fileManager = "thunar"
-- rofi 2.0 (native Wayland) is the launcher
local menu        = "rofi -show drun"
local browser     = "librewolf"
local appgrid     = "nwg-drawer -c 6 -is 64 -fm thunar -term kitty"  -- GNOME-style full-screen app grid


-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
hl.on("hyprland.start", function ()
  -- Hand the Wayland session to the user manager and bring graphical-session.target
  -- up through hyprland-session.target (modules/desktop.nix): ly starts Hyprland
  -- without uwsm, so nothing else ever activates it, and the HM units WantedBy it
  -- (protonmail-bridge, dram-theme-auto) never ran at login.
  hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP && systemctl --user start hyprland-session.target")
  hl.exec_cmd("systemctl --user start hyprpolkitagent")   -- polkit agent (Hyprland's own; replaced polkit-kde-agent 2026-10-05)
  hl.exec_cmd("$HOME/.local/bin/quote-wallpaper.sh")       -- quote wallpaper (via awww-daemon)
  hl.exec_cmd("$HOME/.local/bin/wallpaper-hotplug.sh")     -- repaint wallpaper on monitor hotplug/dock (a new output stayed black until repainted)
  hl.exec_cmd("waybar")                                       -- status bar
  hl.exec_cmd("$HOME/.local/bin/waybar-fullscreen.sh")      -- hide the bar while the active window is fullscreen (games)
  hl.exec_cmd("env LANG=ru_RU.UTF-8 swaync")  -- the empty state reads «Нет уведомлений», times «Сейчас»                                       -- notifications (history + control center)
  hl.exec_cmd("$HOME/.local/bin/welcome.sh")                  -- "Welcome back, PJ" login toast (comment out to disable)
  hl.exec_cmd("command -v swayosd-server >/dev/null 2>&1 && swayosd-server")  -- volume/brightness OSD
  hl.exec_cmd("udiskie")                                      -- auto-mount USB / removable drives (no tray; waybar custom/usb shows the indicator)
  -- blueman-applet retired: waybar's own bluetooth module (in group/tools) shows a
  -- themed word instead of blueman's white tray icon (invisible on light themes).
  -- Its on-click still opens blueman-manager.
  -- hl.exec_cmd("blueman-applet")
  hl.exec_cmd("hyprsunset")                                   -- blue-light schedule (hyprsunset.conf); SUPER+ALT+N overrides it over IPC
  hl.exec_cmd("hypridle")                                     -- idle: lock 30m (+suspend on battery), screens off 45m (hypridle.conf)
  hl.exec_cmd("wl-paste --type text --watch cliphist store")  -- clipboard history: text
  hl.exec_cmd("wl-paste --type image --watch cliphist store") -- clipboard history: images
  hl.exec_cmd("wl-clip-persist --clipboard regular")         -- keep the clipboard alive after the source app closes
  -- Gaming desktops: Steam starts minimised, so it works through the shader caches in
  -- the background after each boot instead of making the first launch wait
  -- (docs/toolchain/profiles/gaming.md "Shader pre-caching"). Not on a laptop: battery.
  for _, r in ipairs(FACTS.roles or {}) do
    if r == "gaming" and not IS_LAPTOP then hl.exec_cmd("steam -silent") end
  end
end)


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")   -- Qt apps follow the GTK theme dram-theme sets (qt6ct left 2026-10-10)
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")   -- Java/Ghidra on XWayland: blank windows otherwise


-----------------------
----- PERMISSIONS -----
-----------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Permissions/
-- Please note permission changes here require a Hyprland restart and are not applied on-the-fly
-- for security reasons

-- hl.config({
--   ecosystem = {
--     enforce_permissions = true,
--   },
-- })

-- hl.permission("/usr/(bin|local/bin)/grim", "screencopy", "allow")
-- hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")
-- hyprctl gets no permission here.
-- Plugins come from our own signed [dram] repo as packages (pkgs/hyprland-plugin-*,
-- docs/toolchain/packaging/README.md): hl.plugin.load registers the .so, Hyprland loads it after the
-- config pass and re-runs the guarded plugin.* blocks below. hyprpm is retired;
-- a host without [dram] runs without the plugins (the blocks are guarded).
hl.plugin.load("/usr/lib/hyprland/libhyprtasking.so")
hl.plugin.load("/usr/lib/hyprland/libhyprfocus.so")

-- silence the update-news popup on version bumps and the twice-yearly donation nag
hl.config({ ecosystem = { no_update_news = true, no_donation_nag = true } })


-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/

-- Palette comes from the active theme (dram-theme switches the symlink)
local theme = dofile(os.getenv("HOME") .. "/.config/themes/current/palette.lua")

hl.config({
    general = {
        -- Letterpress (docs/design/README.md): a page has margins, not bubbles.
        gaps_in  = 6,
        gaps_out = 18,

        border_size = 2,

        col = {
            -- The active border is a rule in the theme's ONE accent ink, fading
            -- to the same ink darker (palette.accent / accent_dim). Themes
            -- without the accent slot fall back to the old active1/active2 pair.
            active_border   = { colors = {theme.accent or theme.active1, theme.accent_dim or theme.accent or theme.active2}, angle = theme.angle },
            inactive_border = theme.inactive,
        },

        resize_on_border     = true,   -- drag borders/gaps to resize
        hover_icon_on_border = true,
        snap = { enabled = true },     -- edge snapping for the floating pavucontrol/nmtui/cava

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = true,    -- lets `immediate` windows (games) tear: lowest latency. VRR stays off: with tearing on, Hyprland bounces between the two modes (discussion #13244).

        layout = "dwindle",
    },

    decoration = {
        -- Letterpress: square-ish chrome. 4px is "a card's corner", not a pill.
        rounding       = 4,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 1.0,   -- kitty is opaque; dim_inactive below is the focus cue instead
        dim_inactive     = true,
        dim_strength     = 0.08,  -- whisper-level dim so focus is felt, text stays readable

        -- A wide, soft shadow is what lifts a flat sheet off the page; it does
        -- the work the old blur/glass did.
        shadow = {
            enabled      = true,
            range        = 24,
            render_power = 4,
            color        = theme.shadow,
        },

        -- No glass. Hyprland's blur is one global kernel (there is no per-layer
        -- size/passes), and disabling it here disables it for layers too — so
        -- rofi/swaync are flat near-opaque paper (their CSS alpha is
        -- ~0.95). The layer rules below only matter if this is ever re-enabled.
        blur = {
            enabled   = false,
            size      = 2,
            passes    = 1,
            vibrancy  = 0,
            popups    = false,
        },
    },

    animations = {
        enabled = true,
    },
})

-- Default curves and animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

-- Default springs
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })
-- Bouncy spring for window movement — same mass/stiffness as "easy" but much
-- LOWER dampening (~0.53 of critical vs ~0.94), so windows overshoot and
-- jiggle into place when they settle (tile swap, snap, drop). Lower dampening =
-- more wobble; raise toward 15 to calm it, drop toward 7 for more jiggle.
hl.curve("jiggle",         { type = "spring", mass = 1, stiffness = 71.2633, dampening = 8.9 })  -- 8.9: ~40% less overshoot than the original 7.0 (2026-10-05)

-- Material 3 curves (end-4 / illogical-impulse style): decel-in, accel-out
hl.curve("md3Decel",    { type = "bezier", points = { {0.05, 0.7}, {0.1, 1}    } })
hl.curve("md3Accel",    { type = "bezier", points = { {0.3, 0},    {0.8, 0.15} } })
hl.curve("fluentDecel", { type = "bezier", points = { {0.1, 1},    {0, 1}      } })

hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 2.5,  spring = "jiggle" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 3,    bezier = "md3Decel",     style = "popin 92%" })   -- 92%: a sheet settling, not a pop
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 2,    bezier = "md3Accel",     style = "popin 90%" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 2,    bezier = "md3Decel" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.5,  bezier = "md3Accel" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
-- pages turn with a short slide (8%), not a swipe
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 2.5,  bezier = "fluentDecel",  style = "slidefade 8%" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 2.5,  bezier = "fluentDecel",  style = "slidefade 8%" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 2.5,  bezier = "fluentDecel",  style = "slidefade 8%" })
hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick" })

-- Ref https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- "Smart gaps" / "No gaps when only"
-- uncomment all if you wish to use that.
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })

-- Persistent workspaces, 3 per monitor. The built-in LAPTOP panel owns 1-3; the
-- EXTERNAL monitors own 4-6 and 7-9. Total persistent set = 1-9. Each waybar shows
-- only its own monitor's active workspace, as "№ n".
-- Hardware note: monitors are matched by EDID/serial (the MON_* locals above),
-- not port. If one is absent (undocked / different dock), Hyprland ignores its
-- rules and those workspaces open on whatever monitor is connected — degrades
-- gracefully and survives DP-* port re-enumeration.
hl.workspace_rule({ workspace = "1", monitor = WS_FIRST, default = true, persistent = true })
hl.workspace_rule({ workspace = "2", monitor = WS_FIRST, persistent = true })
hl.workspace_rule({ workspace = "3", monitor = WS_FIRST, persistent = true })
hl.workspace_rule({ workspace = "4", monitor = MON_MAIN, default = IS_LAPTOP, persistent = true })
hl.workspace_rule({ workspace = "5", monitor = MON_MAIN, persistent = true })
hl.workspace_rule({ workspace = "6", monitor = MON_MAIN, persistent = true })
hl.workspace_rule({ workspace = "7", monitor = MON_MID,  default = true, persistent = true })
hl.workspace_rule({ workspace = "8", monitor = MON_MID,  persistent = true })
hl.workspace_rule({ workspace = "9", monitor = MON_MID,  persistent = true })
-- hl.window_rule({
--     name  = "no-gaps-wtv1",
--     match = { float = false, workspace = "w[tv1]" },
--     border_size = 0,
--     rounding    = 0,
-- })
-- hl.window_rule({
--     name  = "no-gaps-f1",
--     match = { float = false, workspace = "f[1]" },
--     border_size = 0,
--     rounding    = 0,
-- })

-- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
hl.config({
    dwindle = {
        preserve_split = true, -- You probably want this
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
hl.config({
    master = {
        new_status = "master",
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/ for more
-- Scrolling = windows on an endless horizontal tape (niri/PaperWM style).
-- Off by default (general.layout = dwindle); SUPER+ALT+L swaps it in for the
-- session, SUPER+CTRL+arrows / +F / +P then drive the tape (see KEYBINDINGS).
hl.config({
    scrolling = {
        column_width             = 0.5,    -- a new column takes half the screen
        fullscreen_on_one_column = true,   -- a lone column spans the whole screen
        follow_focus             = true,   -- focusing a window scrolls it into view
    },
})

-- Plugins (packages hyprland-plugin-hyprtasking / -hyprfocus from [dram],
-- registered with hl.plugin.load above). Guarded: Hyprland loads
-- them after this file runs, which triggers a config reload; on the first pass
-- hl.plugin.<name> is nil and these blocks are skipped. See docs/design/shell-and-bars/keybinds.md.
if hl.plugin ~= nil and hl.plugin.hyprtasking ~= nil then
  hl.config({
    plugin = {
      hyprtasking = {
        layout          = "grid",
        gap_size        = 10,
        bg_color        = 0xff000000,   -- hyprtasking takes ARGB ints, not the palette strings
        border_size     = 2,
        exit_on_hovered = false,
        grid = { rows = 3, cols = 3, loop = false, layers = 1 },
        gestures = { enabled = true, open_fingers = 4 },   -- 4-finger swipe opens/closes (3 = workspace swipe above)
      },
    },
  })
end
if hl.plugin ~= nil and hl.plugin.hyprfocus ~= nil then
  hl.config({
    plugin = {
      hyprfocus = {
        enable                   = true,
        keyboard_focus_animation = "flash",   -- brief opacity dip on the newly focused window
        mouse_focus_animation    = "none",
        fade_opacity             = 0.85,
        animate_floating         = true,
      },
    },
  })
end

----------------
----  MISC  ----
----------------

hl.config({
    misc = {
        force_default_wallpaper = 0,     -- 0 = no built-in wallpaper (kills the flash before quote-wallpaper loads)
        disable_hyprland_logo   = true,  -- no hyprland logo / mascot background
        focus_on_activate       = true,  -- clicked browser links actually focus the window
        key_press_enables_dpms  = true,  -- any key wakes screens after dpms-off
        middle_click_paste      = false, -- no accidental primary-selection pastes
        on_focus_under_fullscreen = 2,   -- focusing under a fullscreen window unfullscreens it
        -- JELLO DRAG: run mouse-dragged windows THROUGH the animation curve
        -- (the under-damped "jiggle" spring) instead of snapping 1:1 to the
        -- cursor, so a dragged window wobbles/lags behind the cursor like jello.
        -- (Hyprland disables this by default as the window can trail the cursor.)
        animate_mouse_windowdragging = true,
    },
})


---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout  = "us,ru",                    -- SUPER+ALT+SPACE / Alt+Shift run kb-layout.sh (all keyboards together); waybar shows en / ru
        kb_variant = "",
        kb_model   = "",
        kb_options = "",                         -- no xkb grp toggle: it flips ONE keyboard and desyncs the rest (kb-layout.sh instead)
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.
        accel_profile = "flat",   -- flat: same deltas on desktop and in XWayland games

        touchpad = {
            natural_scroll = false,
        },
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace"
})

-- Per-device config, if ever needed:
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/


---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- CONVENTION: every bind carries BOTH a trailing `-- comment` (parsed by
-- keybind-cheatsheet.sh for SUPER+/ and for docs/design/shell-and-bars/keybinds.md) AND a
-- `description` flag (shown by `hyprctl binds`). Keep each bind on ONE line so
-- the parser sees it. Regenerate the doc after editing binds:
--   KEYBIND_CONF=dotfiles/.config/hypr/hyprland.lua dotfiles/.local/bin/keybind-cheatsheet.sh --markdown > docs/design/shell-and-bars/keybinds.md

-- Layout-aware helper: on the scrolling layout run `scrollingDsp`, otherwise
-- (dwindle) run `otherDsp`. Evaluated at keypress, not at config load - see
-- "Conditional bind resolution" on the Binds wiki page.
local function whenScrolling(scrollingDsp, otherDsp)
  return function()
    if hl.get_config("general.layout") == "scrolling" then hl.dispatch(scrollingDsp) else hl.dispatch(otherDsp) end
  end
end

-- hyprtasking overview, guarded: plugins are loaded by hl.plugin.load AFTER
-- the config, and may be absent entirely (package hyprland-plugin-hyprtasking).
local function overviewToggle()
  if hl.plugin ~= nil and hl.plugin.hyprtasking ~= nil then
    hl.plugin.hyprtasking.toggle("cursor")
  else
    hl.notification.create({ text = "hyprtasking is not loaded - pacman -S hyprland-plugin-hyprtasking", timeout = 4000 })
  end
end

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal), { description = "terminal" })                                 -- terminal
local closeWindowBind = hl.bind(mainMod .. " + C", hl.dsp.window.close(), { description = "close window" })          -- close window
-- closeWindowBind:set_enabled(false)
-- power menu (same as SUPER+X): the old bind exited Hyprland instantly with no
-- confirmation — logoff now lives behind the power menu's "logout" entry instead.
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("$HOME/.local/bin/power-menu.sh"), { description = "power menu (alias for SUPER+X)" })  -- power menu (alias for SUPER+X)
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager), { description = "file manager" })                          -- file manager
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }), { description = "toggle floating" })          -- toggle floating
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu), { description = "app launcher" })                                 -- app launcher
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(menu), { description = "launcher (alias for SUPER+R)" })             -- launcher (alias for SUPER+R)
-- keyboard layout: every "keyboard" device at once (see kb-layout.sh); both modifier orders of Alt+Shift
hl.bind(mainMod .. " + ALT + SPACE", hl.dsp.exec_cmd("$HOME/.local/bin/kb-layout.sh toggle"), { description = "keyboard layout en/ru" })  -- keyboard layout en/ru
hl.bind("ALT + SHIFT_L", hl.dsp.exec_cmd("$HOME/.local/bin/kb-layout.sh toggle"), { description = "keyboard layout en/ru (Alt+Shift)" })  -- keyboard layout en/ru (Alt+Shift)
hl.bind("SHIFT + ALT_L", hl.dsp.exec_cmd("$HOME/.local/bin/kb-layout.sh toggle"), { description = "keyboard layout en/ru (Shift+Alt)" })  -- keyboard layout en/ru (Shift+Alt)
hl.bind(mainMod .. " + G", hl.dsp.exec_cmd(appgrid), { description = "app grid (nwg-drawer)" })                     -- GNOME-style app grid (browse all apps)
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser), { description = "browser" })                                   -- open browser
-- power menu: a five-line rofi list (power-menu.sh; wlogout left 2026-10-10,
-- decisions/0013 Community).
hl.bind(mainMod .. " + X", hl.dsp.exec_cmd("$HOME/.local/bin/power-menu.sh"), { description = "power menu" })     -- power menu
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("kitty --class cava-visualizer -e cava"), { description = "audio visualizer (cava)" })  -- audio visualizer (needs cava)
-- SUPER+L stays the lock (muscle memory); the layout toggle lives on SUPER+ALT+L.
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("pidof hyprlock || hyprlock"), { description = "lock screen" })    -- lock the screen
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen(), { description = "fullscreen toggle" })                        -- fullscreen toggle (press again to leave)
-- clipboard history (cliphist watchers + wl-clip-persist run from autostart)
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd("sel=\"$(cliphist list | rofi -dmenu -i -p clipboard)\" && [ -n \"$sel\" ] && printf '%s\\n' \"$sel\" | cliphist decode | wl-copy"), { description = "clipboard history" })  -- clipboard history (ESC = no-op, clipboard untouched)
hl.bind(mainMod .. " + slash", hl.dsp.exec_cmd("$HOME/.local/bin/keybind-cheatsheet.sh"), { description = "keybind cheatsheet" })  -- searchable keybind cheatsheet
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("$HOME/.local/bin/dram-theme"), { description = "theme switcher" })      -- theme switcher menu
hl.bind(mainMod .. " + SHIFT + G", hl.dsp.exec_cmd("$HOME/.local/bin/gamemode.sh"), { description = "game mode toggle" })  -- game mode: eye candy off/on
-- Gaming Mode (decisions/0012): log out and straight into Steam Big Picture; back with
-- SUPER+CTRL+D there. Only on hosts with the gaming role (facts.lua roles; dram-gaming-mode).
local HAS_GAMING, HAS_CREATOR = false, false
for _, r in ipairs(FACTS.roles or {}) do
  if r == "gaming" then HAS_GAMING = true end
  if r == "creator" then HAS_CREATOR = true end
end
if HAS_GAMING then
  hl.bind(mainMod .. " + CTRL + G", hl.dsp.exec_cmd("steamos-session-select gaming"), { description = "switch to Gaming Mode" })  -- log out and straight into Gaming Mode (gaming hosts)
end
-- Recording (docs/toolchain/profiles/creator.md, creator role): OBS on the recorder starts/stops over
-- obs-websocket (OBS has no global hotkeys on Wayland), with the local spare along; and
-- a compositor zoom the capture card sees (cursor.zoom_factor, follows the pointer).
if HAS_CREATOR then
  hl.bind(mainMod .. " + CTRL + R", hl.dsp.exec_cmd("$HOME/.local/bin/rec toggle 2>&1 | head -2 | xargs -0 notify-send -a rec Recording"), { description = "record on the recorder (toggle)" })  -- start/stop OBS on the recorder + the local spare (creator hosts)
  local zoom = 1.0
  local function set_zoom(z)
    zoom = math.max(1.0, math.min(z, 4.0))
    hl.config({ cursor = { zoom_factor = zoom } })
  end
  hl.bind(mainMod .. " + CTRL + equal", function() set_zoom(zoom + 0.5) end, { description = "zoom in (recording)" })  -- zoom in around the cursor (creator hosts)
  hl.bind(mainMod .. " + CTRL + minus", function() set_zoom(zoom - 0.5) end, { description = "zoom out (recording)" })  -- zoom out
  hl.bind(mainMod .. " + CTRL + 0", function() set_zoom(1.0) end, { description = "zoom off" })  -- zoom off
end
hl.bind(mainMod .. " + SHIFT + X", hl.dsp.exec_cmd("$HOME/.local/bin/ocr-copy.sh"), { description = "OCR region to clipboard" })  -- OCR region -> clipboard
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a"), { description = "color picker" })              -- color picker -> clipboard

-- Window management extras
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo(), { description = "pseudo-tile window" })                           -- pseudo-tile window
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.window.pin(), { description = "pin window (floating, every workspace)" })  -- pin window: a floating window follows you to every workspace
hl.bind(mainMod .. " + ALT + C", hl.dsp.window.center(), { description = "center window" })                          -- center the window on its monitor (floating)
hl.bind(mainMod .. " + Tab", hl.dsp.exec_cmd("rofi -show window -modes window"), { description = "window switcher" })  -- window switcher (rofi, every workspace)
hl.bind(mainMod .. " + SHIFT + Tab", hl.dsp.focus({ last = true }), { description = "previous window" })             -- back to the previously focused window

-- Notifications (swaync) and the bar
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("swaync-client -t -sw"), { description = "notification center" })        -- notification center toggle
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.exec_cmd("swaync-client -d -sw"), { description = "do not disturb toggle" })  -- do-not-disturb toggle
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd("$HOME/.local/bin/waybar-toggle.sh"), { description = "toggle waybar" })  -- hide/show waybar (manual; overrides the fullscreen auto-hide until pressed again)
hl.bind(mainMod .. " + ALT + N", hl.dsp.exec_cmd("$HOME/.local/bin/nightlight.sh"), { description = "night light toggle" })  -- blue-light filter toggle (4000K; IPC into a scheduled hyprsunset if one runs)

-- Pickers
hl.bind(mainMod .. " + period", hl.dsp.exec_cmd("rofimoji --action copy --skin-tone neutral --prompt emoji"), { description = "emoji picker" })  -- emoji picker -> clipboard
hl.bind(mainMod .. " + equal", hl.dsp.exec_cmd("rofi -show calc -modi calc -no-show-match -no-sort -calc-command \"echo -n '{result}' | wl-copy\""), { description = "calculator" })    -- calculator (rofi-calc on qalc): Enter copies the result
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("$HOME/.local/bin/wallpaper-menu.sh"), { description = "wallpaper picker" })  -- wallpaper picker (~/pictures/wallpapers, fades in on the focused monitor)

-- Laptop lid: disable the built-in screen when closed (docked), re-enable when opened
if IS_LAPTOP then
  hl.bind("switch:on:Lid Switch",  hl.dsp.exec_cmd("$HOME/.local/bin/lid.sh close"), { locked = true })
  hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("$HOME/.local/bin/lid.sh open"),  { locked = true })
end

-- Screenshots: one naming scheme for all of them (screenshot.sh):
-- ~/pictures/screenshots/screenshot-YYYYMMDD-HHMMSS.png, the pattern satty's config uses.
-- region/window open in satty (annotate; Ctrl+C copies, Ctrl+S saves); the
-- output/all shots are saved + copied straight away and the path is notified.
hl.bind("Print", hl.dsp.exec_cmd("$HOME/.local/bin/screenshot.sh region"), { description = "screenshot: region -> satty" })  -- region screenshot -> annotate (satty)
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd("$HOME/.local/bin/screenshot.sh all"), { description = "screenshot: all monitors -> file" })  -- all monitors -> file + clipboard
hl.bind(mainMod .. " + SHIFT + Print", hl.dsp.exec_cmd("$HOME/.local/bin/screenshot.sh window"), { description = "screenshot: active window -> satty" })  -- active window -> annotate (satty)
hl.bind(mainMod .. " + CTRL + Print", hl.dsp.exec_cmd("$HOME/.local/bin/screenshot.sh output"), { description = "screenshot: focused monitor -> file" })  -- focused monitor -> file + clipboard

-- Screen recording (gpu-screen-recorder: NVENC on cabin, VA-API on lantern)
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("$HOME/.local/bin/record-toggle.sh"), { description = "record focused monitor (toggle)" })  -- start/stop recording the focused monitor -> ~/videos/recordings/rec-<stamp>.mp4
hl.bind(mainMod .. " + ALT + R", hl.dsp.exec_cmd("gsr-ui-cli toggle-replay || notify-send -a record 'Replay needs gsr-ui' 'Start GPU Screen Recorder (gsr-ui) first'"), { description = "instant replay on/off (gsr-ui)" })  -- instant-replay buffer on/off (needs gsr-ui running)

-- Layouts: dwindle is the default (general.layout); SUPER+ALT+L swaps in scrolling
-- for the session. The SUPER+CTRL binds are layout-aware (see whenScrolling).
hl.bind(mainMod .. " + ALT + L", hl.dsp.exec_cmd("$HOME/.local/bin/layout-toggle.sh"), { description = "layout: dwindle <-> scrolling" })  -- toggle layout dwindle <-> scrolling
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"), { description = "toggle split direction (dwindle)" })       -- toggle split direction (dwindle)
hl.bind(mainMod .. " + CTRL + F", hl.dsp.layout("fit expand"), { description = "scrolling: expand column into free space" })  -- scrolling: expand the column into the free space
hl.bind(mainMod .. " + CTRL + P", hl.dsp.layout("promote"), { description = "scrolling: window to its own column" })  -- scrolling: promote the window to its own column
hl.bind(mainMod .. " + CTRL + SHIFT + left",  hl.dsp.layout("swapcol l"), { description = "scrolling: swap column left" })   -- scrolling: swap column with the one on the left
hl.bind(mainMod .. " + CTRL + SHIFT + right", hl.dsp.layout("swapcol r"), { description = "scrolling: swap column right" })  -- scrolling: swap column with the one on the right

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }), { description = "focus left" })     -- focus left
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }), { description = "focus right" })   -- focus right
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }), { description = "focus up" })         -- focus up
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }), { description = "focus down" })     -- focus down

-- Move the active window with mainMod + SHIFT + arrow keys
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "left" }), { description = "move window left" })    -- move window left
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }), { description = "move window right" })  -- move window right
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "up" }), { description = "move window up" })        -- move window up
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "down" }), { description = "move window down" })    -- move window down

-- Resize the active window with mainMod + CTRL + arrow keys (hold to repeat).
-- left/right are layout-aware: on scrolling they move the tape by one column.
hl.bind(mainMod .. " + CTRL + left",  whenScrolling(hl.dsp.layout("move -col"), hl.dsp.window.resize({ x = -40, y = 0, relative = true })), { repeating = true, description = "resize narrower / scrolling: column left" })   -- resize narrower (scrolling: scroll one column left)
hl.bind(mainMod .. " + CTRL + right", whenScrolling(hl.dsp.layout("move +col"), hl.dsp.window.resize({ x = 40,  y = 0, relative = true })), { repeating = true, description = "resize wider / scrolling: column right" })    -- resize wider (scrolling: scroll one column right)
hl.bind(mainMod .. " + CTRL + up",    hl.dsp.window.resize({ x = 0,   y = -40, relative = true }), { repeating = true, description = "resize shorter" })   -- resize shorter
hl.bind(mainMod .. " + CTRL + down",  hl.dsp.window.resize({ x = 0,   y = 40,  relative = true }), { repeating = true, description = "resize taller" })    -- resize taller

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}),             { description = "workspace " .. i })
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }),      { description = "move window to workspace " .. i })
end
-- Relative workspaces: e±1 = next/previous EXISTING workspace (no empty ones)
hl.bind(mainMod .. " + bracketleft",  hl.dsp.focus({ workspace = "e-1" }), { description = "previous workspace" })   -- previous workspace
hl.bind(mainMod .. " + bracketright", hl.dsp.focus({ workspace = "e+1" }), { description = "next workspace" })       -- next workspace
hl.bind(mainMod .. " + SHIFT + bracketleft",  hl.dsp.window.move({ workspace = "e-1", follow = true }), { description = "move window to previous workspace" })  -- move window to the previous workspace (and follow)
hl.bind(mainMod .. " + SHIFT + bracketright", hl.dsp.window.move({ workspace = "e+1", follow = true }), { description = "move window to next workspace" })      -- move window to the next workspace (and follow)

-- Workspace overview (hyprtasking plugin; grid of every workspace, drag windows between them)
hl.bind(mainMod .. " + grave", overviewToggle, { description = "workspace overview (hyprtasking)" })                  -- workspace overview on this monitor (hyprtasking; press again or right-click a workspace to leave)

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"), { description = "scratchpad" })           -- scratchpad workspace
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }), { description = "move window to scratchpad" })  -- move window to scratchpad

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "next workspace" })       -- next workspace
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }), { description = "previous workspace" })   -- previous workspace

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "drag window" })     -- drag window
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "resize window" })   -- resize window

-- Laptop multimedia keys for volume and LCD brightness — through swayosd for
-- the on-screen display bubble, falling back to bare wpctl/brightnessctl
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("command -v swayosd-client >/dev/null 2>&1 && swayosd-client --output-volume raise --max-volume 100 || wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true, description = "volume up" })  -- volume up (OSD)
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("command -v swayosd-client >/dev/null 2>&1 && swayosd-client --output-volume lower || wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),                      { locked = true, repeating = true, description = "volume down" })  -- volume down (OSD)
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("command -v swayosd-client >/dev/null 2>&1 && swayosd-client --output-volume mute-toggle || wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),               { locked = true, repeating = true, description = "mute toggle" })  -- mute toggle
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("command -v swayosd-client >/dev/null 2>&1 && swayosd-client --input-volume mute-toggle || wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),              { locked = true, repeating = true, description = "mic mute toggle" })  -- mic mute toggle
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("command -v swayosd-client >/dev/null 2>&1 && swayosd-client --brightness raise || brightnessctl -e4 -n2 set 5%+"),                                     { locked = true, repeating = true, description = "brightness up" })  -- brightness up (OSD)
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("command -v swayosd-client >/dev/null 2>&1 && swayosd-client --brightness lower || brightnessctl -e4 -n2 set 5%-"),                                     { locked = true, repeating = true, description = "brightness down" })  -- brightness down (OSD)

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true, description = "media: next" })        -- media: next track
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "media: play/pause" })  -- media: play/pause
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "media: play/pause" })  -- media: play/pause
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true, description = "media: previous" })    -- media: previous track


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Example window rules that are useful

local suppressMaximizeRule = hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Games: Steam/Proton titles (class steam_app_<id>) and native CS2 run in
-- "fullscreen windowed", which Hyprland treats as an ordinary window - so the bar
-- stays on top of them. Make them real fullscreen: the bar is covered, the
-- idle-inhibit rule below applies, and SUPER+F still toggles it off.
hl.window_rule({
    name  = "games-fullscreen",
    match = { class = "^(cs2|steam_app_\\d+)$" },
    fullscreen = true,
    immediate  = true,   -- present frames immediately (tearing) for lowest input latency
})

-- Games and video: a fullscreen window must never trigger hypridle's lock/dpms.
hl.window_rule({
    name  = "no-idle-when-fullscreen",
    match = { fullscreen = true },
    idle_inhibit = "fullscreen",
})

-- Layer rules also return a handle.
-- local overlayLayerRule = hl.layer_rule({
--     name  = "no-anim-overlay",
--     match = { namespace = "^my-overlay$" },
--     no_anim = true,
-- })
-- overlayLayerRule:set_enabled(false)

-- Letterpress popups (rofi, swaync): flat paper. decoration.blur is
-- OFF, so these rules are inert today; they name the only layers that may ever
-- frost (ignore_alpha keeps the hairline/shadow pixels from blurring) if blur
-- is re-enabled for a theme. The bar never blurs: it is a transparent masthead.
hl.layer_rule({ name = "paper-rofi",    match = { namespace = "^rofi$" },   blur = true, ignore_alpha = 0.2 })
hl.layer_rule({ name = "paper-swaync",  match = { namespace = "^swaync-" }, blur = true, ignore_alpha = 0.2 })

-- Hyprland-run windowrule
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})

-- Float the cava audio visualizer (SUPER+A)
hl.window_rule({
    name  = "float-cava",
    match = { class = "cava-visualizer" },

    float = true,
    size  = "900 380",
})

-- Audio modal: pavucontrol (waybar sound click) — small, centred float
hl.window_rule({
    name  = "float-pavucontrol",
    match = { class = "org.pulseaudio.pavucontrol" },

    float = true,
    size  = "760 560",
    move  = "monitor_w/2-380 monitor_h/2-280",
})

-- Network picker: nmtui (NetworkManager's own TUI) in kitty — the waybar network click
-- opens `kitty --class nmtui -e nmtui connect`; small, centred float (docs/security/network/networkmanager.md).
hl.window_rule({
    name  = "float-nmtui",
    match = { class = "^nmtui$" },

    float    = true,
    size     = "500 580",
    move     = "monitor_w/2-250 monitor_h/2-290",
    rounding = 4,
    opacity  = 1.0,    -- flat paper: blur is off (decoration.blur), so any alpha only
                       -- bleeds the wallpaper through the text — same as gsimplecal below
})

-- Calendar: gsimplecal (waybar clock click) — centre it horizontally under the
-- centre clock module (with the house fonts gsimplecal measures 339 px logical
-- wide — hyprctl clients on lantern 2026-10-06 — so half = 170).
-- monitor_w is logical, so this stays centred on every monitor regardless of scale.
-- rounding here because GTK3 can't round its own toplevel.
hl.window_rule({
    name  = "place-gsimplecal",
    match = { class = "gsimplecal" },

    float    = true,
    move     = "monitor_w/2-170 46",
    rounding = 4,
})


-- Paper-grain screen shader (shaders/grain.frag): static hash grain + a warm
-- vignette over the final frame. No `time` uniform, so damage tracking stays on.
-- gamemode.sh clears it while game mode is on; dotfiles/.config/hypr/README.md ("Grain shader") has the details.
hl.config({ decoration = { screen_shader = os.getenv("HOME") .. "/.config/hypr/shaders/grain.frag" } })

-- HyprMod managed settings
require("hyprland-gui")
