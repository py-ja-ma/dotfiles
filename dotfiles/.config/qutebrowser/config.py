# =============================================================================
#  qutebrowser — Catppuccin Mocha + minimalist tweaks
#  Lives at ~/.config/qutebrowser/config.py. Reload live with  :config-source
# =============================================================================

config.load_autoconfig(False)   # ignore the GUI-written autoconfig.yml; this file is source of truth

# ---- Catppuccin Mocha palette ----------------------------------------------
p = {
    "rosewater": "#f5e0dc", "flamingo": "#f2cdcd", "pink": "#f5c2e7",
    "mauve": "#cba6f7", "red": "#f38ba8", "maroon": "#eba0ac",
    "peach": "#fab387", "yellow": "#f9e2af", "green": "#a6e3a1",
    "teal": "#94e2d5", "sky": "#89dceb", "sapphire": "#74c7ec",
    "blue": "#89b4fa", "lavender": "#b4befe",
    "text": "#cdd6f4", "subtext1": "#bac2de", "subtext0": "#a6adc8",
    "overlay2": "#9399b2", "overlay1": "#7f849c", "overlay0": "#6c7086",
    "surface2": "#585b70", "surface1": "#45475a", "surface0": "#313244",
    "base": "#1e1e2e", "mantle": "#181825", "crust": "#11111b",
}

# ---- Fonts -----------------------------------------------------------------
# House fonts (docs/design/typography/README.md): Literata is the text/UI face (Cyrillic-safe),
# Monaspace Xenon the mono. sans-serif is left to fontconfig (Noto Sans).
c.fonts.default_family = "Literata"
c.fonts.default_size = "11pt"
c.fonts.web.family.standard = "Literata"
c.fonts.web.family.serif = "Literata"
c.fonts.web.family.fixed = "Monaspace Xenon"

# ---- Minimalist behaviour --------------------------------------------------
c.tabs.position = "top"
c.tabs.show = "multiple"          # hide the tab bar when only one tab is open
c.tabs.indicator.width = 2        # thin loading indicator
c.tabs.title.format = "{audio}{current_title}"
c.tabs.favicons.scale = 1.0
c.statusbar.widgets = ["keypress", "url", "scroll", "history", "tabs", "progress"]
c.scrolling.smooth = True
c.downloads.position = "bottom"
c.completion.height = "33%"
c.completion.shrink = True
c.completion.scrollbar.width = 6
c.content.autoplay = False
c.colors.webpage.preferred_color_scheme = "dark"   # ask sites for their dark theme (no forced inversion)

# search engines
c.url.searchengines = {
    "DEFAULT": "https://duckduckgo.com/?q={}",
    "g": "https://www.google.com/search?q={}",
    "aw": "https://wiki.archlinux.org/?search={}",
    "gh": "https://github.com/search?q={}",
    "yt": "https://www.youtube.com/results?search_query={}",
}

# ---- Colors: Catppuccin Mocha ----------------------------------------------
# completion menu
c.colors.completion.fg = p["text"]
c.colors.completion.odd.bg = p["mantle"]
c.colors.completion.even.bg = p["base"]
c.colors.completion.category.fg = p["blue"]
c.colors.completion.category.bg = p["base"]
c.colors.completion.category.border.top = p["base"]
c.colors.completion.category.border.bottom = p["base"]
c.colors.completion.item.selected.fg = p["text"]
c.colors.completion.item.selected.bg = p["surface1"]
c.colors.completion.item.selected.border.top = p["surface1"]
c.colors.completion.item.selected.border.bottom = p["surface1"]
c.colors.completion.item.selected.match.fg = p["blue"]
c.colors.completion.match.fg = p["blue"]
c.colors.completion.scrollbar.fg = p["text"]
c.colors.completion.scrollbar.bg = p["base"]

# context menu
c.colors.contextmenu.menu.bg = p["base"]
c.colors.contextmenu.menu.fg = p["text"]
c.colors.contextmenu.selected.bg = p["surface1"]
c.colors.contextmenu.selected.fg = p["text"]
c.colors.contextmenu.disabled.bg = p["mantle"]
c.colors.contextmenu.disabled.fg = p["overlay0"]

# downloads
c.colors.downloads.bar.bg = p["base"]
c.colors.downloads.start.fg = p["base"]
c.colors.downloads.start.bg = p["blue"]
c.colors.downloads.stop.fg = p["base"]
c.colors.downloads.stop.bg = p["teal"]
c.colors.downloads.error.fg = p["red"]

# hints
c.colors.hints.fg = p["crust"]
c.colors.hints.bg = p["yellow"]
c.colors.hints.match.fg = p["blue"]

# keyhint
c.colors.keyhint.fg = p["text"]
c.colors.keyhint.suffix.fg = p["yellow"]
c.colors.keyhint.bg = p["base"]

# messages
c.colors.messages.error.fg = p["crust"]
c.colors.messages.error.bg = p["red"]
c.colors.messages.error.border = p["red"]
c.colors.messages.warning.fg = p["crust"]
c.colors.messages.warning.bg = p["peach"]
c.colors.messages.warning.border = p["peach"]
c.colors.messages.info.fg = p["text"]
c.colors.messages.info.bg = p["base"]
c.colors.messages.info.border = p["base"]

# prompts
c.colors.prompts.fg = p["text"]
c.colors.prompts.border = p["base"]
c.colors.prompts.bg = p["mantle"]
c.colors.prompts.selected.bg = p["surface0"]
c.colors.prompts.selected.fg = p["text"]

# statusbar
c.colors.statusbar.normal.fg = p["text"]
c.colors.statusbar.normal.bg = p["base"]
c.colors.statusbar.insert.fg = p["base"]
c.colors.statusbar.insert.bg = p["green"]
c.colors.statusbar.passthrough.fg = p["base"]
c.colors.statusbar.passthrough.bg = p["sky"]
c.colors.statusbar.private.fg = p["text"]
c.colors.statusbar.private.bg = p["crust"]
c.colors.statusbar.command.fg = p["text"]
c.colors.statusbar.command.bg = p["mantle"]
c.colors.statusbar.command.private.fg = p["text"]
c.colors.statusbar.command.private.bg = p["mantle"]
c.colors.statusbar.caret.fg = p["text"]
c.colors.statusbar.caret.bg = p["mauve"]
c.colors.statusbar.caret.selection.fg = p["text"]
c.colors.statusbar.caret.selection.bg = p["blue"]
c.colors.statusbar.progress.bg = p["blue"]
c.colors.statusbar.url.fg = p["text"]
c.colors.statusbar.url.error.fg = p["red"]
c.colors.statusbar.url.hover.fg = p["sky"]
c.colors.statusbar.url.success.http.fg = p["teal"]
c.colors.statusbar.url.success.https.fg = p["green"]
c.colors.statusbar.url.warn.fg = p["peach"]

# tabs
c.colors.tabs.bar.bg = p["base"]
c.colors.tabs.indicator.start = p["blue"]
c.colors.tabs.indicator.stop = p["teal"]
c.colors.tabs.indicator.error = p["red"]
c.colors.tabs.odd.fg = p["text"]
c.colors.tabs.odd.bg = p["mantle"]
c.colors.tabs.even.fg = p["text"]
c.colors.tabs.even.bg = p["base"]
c.colors.tabs.selected.odd.fg = p["text"]
c.colors.tabs.selected.odd.bg = p["surface1"]
c.colors.tabs.selected.even.fg = p["text"]
c.colors.tabs.selected.even.bg = p["surface1"]
c.colors.tabs.pinned.even.bg = p["teal"]
c.colors.tabs.pinned.even.fg = p["base"]
c.colors.tabs.pinned.odd.bg = p["green"]
c.colors.tabs.pinned.odd.fg = p["base"]
c.colors.tabs.pinned.selected.even.bg = p["surface1"]
c.colors.tabs.pinned.selected.even.fg = p["text"]
c.colors.tabs.pinned.selected.odd.bg = p["surface1"]
c.colors.tabs.pinned.selected.odd.fg = p["text"]
