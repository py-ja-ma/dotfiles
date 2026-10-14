#!/usr/bin/env python3
"""usage: gen-vscode-themes.py [theme ...]

Writes one VS Code colour theme per dram theme (or per named theme) into the local extension dotfiles/.vscode/extensions/letterpress-themes, and its package.json on a full run. A dev-time generator; commit the output; codium-themes-install registers the extension.

The editor is the printed page again: every workbench surface is the paper
(`base`), panels and widgets are the mantle, the chrome is separated by 1 px
hairlines in alpha(text, .18) instead of coloured bars, and ONE accent ink
carries the cursor, the focus ring, links, the active tab's rule, the find
match and the badges. Syntax is set in five inks: body ink, the accent for
keywords, a second (ochre) tone for strings, blue/teal for types, subtext
italic for comments. No bold, no rainbow brackets.

    dotfiles/.config/themes/<t>/waybar.css   base mantle crust text subtext overlay
                                             surface0 surface1 red green yellow blue
                                             teal peach mauve
  + dotfiles/.config/themes/<t>/palette.lua  accent, accent_dim (the ONE accent ink)
  + dotfiles/.config/themes/<t>/meta.sh      COLOR_SCHEME (light/dark), MENU_NAME (label)
  + dotfiles/.config/themes/<t>/kitty.conf   color0..15 -> the integrated terminal
  = dotfiles/.vscode/extensions/letterpress-themes/themes/letterpress-<t>-color-theme.json
  = dotfiles/.vscode/extensions/letterpress-themes/package.json   (contributes.themes)

Workbench mapping (palette field -> VS Code colour key):
    base              -> editor, sideBar, activityBar, statusBar, titleBar, tabs,
                         panel, terminal, breadcrumbs: every surface is the paper
    mantle            -> input, dropdown, editorWidget (find/suggest/hover),
                         quickInput, notifications, menu, peekView, sticky scroll hover
    alpha(text,.18)   -> every *.border key (hairlines); .12 for indent guides
    accent            -> focusBorder, editorCursor, textLink, button, badge,
                         activityBarBadge, tab.activeBorderTop, activityBar.activeBorder,
                         panelTitle.activeBorder, progressBar, peekView.border,
                         list.highlightForeground, inputOption.activeBorder
    alpha(accent,…)   -> list.activeSelectionBackground (.20), editor.findMatch (.40 / .35),
                         findMatchHighlight (.18), selectionHighlight (.12), bracket match
    alpha(text,.14)   -> editor.selectionBackground (a neutral grey, never an accent fill)
    subtext           -> editorLineNumber, descriptions, inactive tabs/titles, icons
    overlay           -> disabled text, placeholders, code lens, inactive activity icons
    red/yellow/blue   -> editorError / editorWarning / editorInfo, gutter + diff colours,
    green                git decorations (modified = yellow, added = green, deleted = red)
    kitty color0..15  -> terminal.ansi*
Token colours (TextMate scope -> ink):
    comment                     subtext italic
    string, markup.inline.raw   yellow  (the second tone; raised to >= 4.5:1 on the paper)
    keyword, storage            accent
    entity.name.type/class      blue;  support.type, namespace, HTML tag -> teal
    constant.numeric/language   numbers = accent_dim on light, accent mixed toward
                                the ink on dark (accent_dim is too dark on a dark page)
    function, variable, operator  text (plain weight)
    punctuation                 subtext
    invalid                     red

Run from anywhere:  python3 bin/gen-vscode-themes.py [theme ...]
No arguments = every theme dir (package.json is written only on a full run).
Idempotent; prints the files it rewrote. VERSION is bumped by hand — a run date
would rewrite package.json daily.
See dotfiles/.vscode/extensions/letterpress-themes/README.md.

  theme ...     theme dir ids under dotfiles/.config/themes (default: every theme)
  -h, --help    this text

exit: 0 ok · 1 a theme failed to render · 2 bad usage
see: dotfiles/.vscode/extensions/letterpress-themes/README.md
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEMES = os.path.join(ROOT, "dotfiles", ".config", "themes")
EXT = os.path.join(ROOT, "dotfiles", ".vscode", "extensions", "letterpress-themes")

PUBLISHER = "pj"
NAME = "letterpress-themes"
VERSION = "2026.10.6"   # semver x.y.z; bump when the set or the mapping changes
LABEL = "Letterpress — "  # + MENU_NAME from meta.sh

NEEDED = ["base", "mantle", "crust", "text", "subtext", "overlay", "surface0", "surface1",
          "red", "green", "yellow", "blue", "teal", "peach", "mauve"]
HAIRLINE = 0.18   # the Letterpress rule: alpha(text, .18)
MIN_CONTRAST = 4.5


# ---- colour maths -------------------------------------------------------------
def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hexs(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(v))) for v in c)


def mix(a, b, t):  # t=0 -> a, t=1 -> b
    a, b = rgb(a), rgb(b)
    return hexs(tuple(a[i] + (b[i] - a[i]) * t for i in range(3)))


def alpha(h, a):  # #rrggbb + aa
    return h + "%02x" % round(a * 255)


def luminance(h):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(v) for v in rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def readable(ink, paper, toward, minimum=MIN_CONTRAST):
    """Mix `ink` toward `toward` (the body ink) in 5 % steps until it reads on the paper."""
    out, t = ink, 0.0
    while contrast(out, paper) < minimum and t < 1.0:
        t += 0.05
        out = mix(ink, toward, t)
    return out


def best_on(bg, candidates):
    return max(candidates, key=lambda c: contrast(c, bg))


# ---- inputs -------------------------------------------------------------------
def define_colors(path):
    s = open(path, encoding="utf-8").read()
    return {k: v.lower() for k, v in re.findall(r"@define-color\s+(\S+)\s+(#[0-9a-fA-F]{6})\s*;", s)}


def palette_lua(path):
    # `accent = "rgba(RRGGBBAA)"` and `accent_dim = ...`; the alpha is Hyprland's
    s = open(path, encoding="utf-8").read()
    out = {}
    for key in ("accent", "accent_dim"):
        m = re.search(r'^\s*%s\s*=\s*"rgba\(([0-9a-fA-F]{6})[0-9a-fA-F]{2}\)"' % key, s, re.M)
        if m:
            out[key] = "#" + m.group(1).lower()
    return out


def meta(path):
    s = open(path, encoding="utf-8").read()
    out = {}
    for key in ("COLOR_SCHEME", "MENU_NAME"):
        m = re.search(r'^%s="([^"]*)"' % key, s, re.M)
        if m:
            out[key] = m.group(1)
    return out


def kitty_ansi(path):
    s = open(path, encoding="utf-8").read()
    return {int(n): v.lower() for n, v in re.findall(r"^color(\d+)\s+(#[0-9a-fA-F]{6})", s, re.M)}


# ---- the mapping ----------------------------------------------------------------
def workbench(c, accent, accent_dim, light, ansi):
    paper, mantle, crust = c["base"], c["mantle"], c["crust"]
    text, subtext, overlay = c["text"], c["subtext"], c["overlay"]
    surface0, surface1 = c["surface0"], c["surface1"]
    red, yellow, green, blue = c["red"], c["yellow"], c["green"], c["blue"]
    hairline = alpha(text, HAIRLINE)
    faint = alpha(text, 0.12)
    none = "#00000000"
    on_accent = best_on(accent, ["#ffffff", crust, text, paper])
    hover = accent_dim if light else mix(accent, text, 0.15)
    sel_accent = alpha(accent, 0.20)
    w = {
        # --- the page -----------------------------------------------------------
        "foreground": text,
        "descriptionForeground": subtext,
        "disabledForeground": overlay,
        "errorForeground": red,
        "icon.foreground": subtext,
        "focusBorder": accent,
        "selection.background": alpha(text, 0.20),
        "widget.border": hairline,
        "widget.shadow": none,
        "sash.hoverBorder": accent,
        "textLink.foreground": accent,
        "textLink.activeForeground": hover,
        "textBlockQuote.background": mantle,
        "textBlockQuote.border": accent,
        "textCodeBlock.background": mantle,
        "textPreformat.foreground": text,
        "textPreformat.background": mantle,
        "textSeparator.foreground": hairline,
        "toolbar.hoverBackground": alpha(text, 0.08),
        "toolbar.activeBackground": alpha(text, 0.12),
        # --- editor -------------------------------------------------------------
        "editor.background": paper,
        "editor.foreground": text,
        "editorCursor.foreground": accent,
        "editorCursor.background": paper,
        "editorLineNumber.foreground": subtext,
        "editorLineNumber.activeForeground": text,
        "editor.lineHighlightBackground": alpha(text, 0.04),
        "editor.lineHighlightBorder": none,
        "editor.selectionBackground": alpha(text, 0.14),
        "editor.inactiveSelectionBackground": alpha(text, 0.08),
        "editor.selectionHighlightBackground": alpha(accent, 0.12),
        "editor.wordHighlightBackground": alpha(text, 0.08),
        "editor.wordHighlightStrongBackground": alpha(text, 0.12),
        "editor.findMatchBackground": alpha(accent, 0.35 if light else 0.40),
        "editor.findMatchHighlightBackground": alpha(accent, 0.18),
        "editor.findRangeHighlightBackground": alpha(text, 0.05),
        "editor.hoverHighlightBackground": alpha(text, 0.06),
        "editor.rangeHighlightBackground": alpha(text, 0.04),
        "editor.foldBackground": alpha(text, 0.06),
        "editorLink.activeForeground": accent,
        "editorWhitespace.foreground": faint,
        "editorIndentGuide.background1": faint,
        "editorIndentGuide.activeBackground1": alpha(text, 0.28),
        "editorRuler.foreground": faint,
        "editorCodeLens.foreground": overlay,
        "editorInlayHint.foreground": subtext,
        "editorInlayHint.background": none,
        "editorBracketMatch.background": alpha(accent, 0.16),
        "editorBracketMatch.border": alpha(accent, 0.55),
        "editorBracketHighlight.foreground1": text,
        "editorBracketHighlight.foreground2": subtext,
        "editorBracketHighlight.foreground3": overlay,
        "editorBracketHighlight.foreground4": text,
        "editorBracketHighlight.foreground5": subtext,
        "editorBracketHighlight.foreground6": overlay,
        "editorBracketHighlight.unexpectedBracket.foreground": red,
        "editorGutter.background": paper,
        "editorGutter.addedBackground": green,
        "editorGutter.modifiedBackground": yellow,
        "editorGutter.deletedBackground": red,
        "editorGutter.commentRangeForeground": overlay,
        "editorGutter.foldingControlForeground": subtext,
        "editorOverviewRuler.border": none,
        "editorOverviewRuler.findMatchForeground": alpha(accent, 0.6),
        "editorOverviewRuler.errorForeground": red,
        "editorOverviewRuler.warningForeground": yellow,
        "editorOverviewRuler.infoForeground": blue,
        "editorOverviewRuler.addedForeground": green,
        "editorOverviewRuler.modifiedForeground": yellow,
        "editorOverviewRuler.deletedForeground": red,
        "editorError.foreground": red,
        "editorWarning.foreground": yellow,
        "editorInfo.foreground": blue,
        "editorHint.foreground": subtext,
        "editorUnnecessaryCode.opacity": "#00000080",
        "editorLightBulb.foreground": yellow,
        "editorLightBulbAutoFix.foreground": accent,
        "editorStickyScroll.background": paper,
        "editorStickyScroll.border": hairline,
        "editorStickyScrollHover.background": mantle,
        "editorWidget.background": mantle,
        "editorWidget.foreground": text,
        "editorWidget.border": hairline,
        "editorWidget.resizeBorder": accent,
        "editorSuggestWidget.background": mantle,
        "editorSuggestWidget.border": hairline,
        "editorSuggestWidget.foreground": text,
        "editorSuggestWidget.highlightForeground": accent,
        "editorSuggestWidget.focusHighlightForeground": accent,
        "editorSuggestWidget.selectedBackground": sel_accent,
        "editorSuggestWidget.selectedForeground": text,
        "editorHoverWidget.background": mantle,
        "editorHoverWidget.border": hairline,
        "editorHoverWidget.foreground": text,
        "editorHoverWidget.statusBarBackground": mantle,
        "editorMarkerNavigation.background": mantle,
        "editorMarkerNavigationError.background": red,
        "editorMarkerNavigationWarning.background": yellow,
        "editorMarkerNavigationInfo.background": blue,
        "editorGroup.border": hairline,
        "editorGroup.dropBackground": alpha(accent, 0.10),
        "editorGroupHeader.tabsBackground": paper,
        "editorGroupHeader.tabsBorder": hairline,
        "editorGroupHeader.noTabsBackground": paper,
        "editorGroupHeader.border": none,
        "editorPane.background": paper,
        "diffEditor.insertedTextBackground": alpha(green, 0.18),
        "diffEditor.removedTextBackground": alpha(red, 0.18),
        "diffEditor.insertedLineBackground": alpha(green, 0.10),
        "diffEditor.removedLineBackground": alpha(red, 0.10),
        "diffEditor.border": hairline,
        "diffEditor.diagonalFill": faint,
        "merge.currentHeaderBackground": alpha(green, 0.35),
        "merge.currentContentBackground": alpha(green, 0.12),
        "merge.incomingHeaderBackground": alpha(blue, 0.35),
        "merge.incomingContentBackground": alpha(blue, 0.12),
        "merge.border": hairline,
        "peekView.border": accent,
        "peekViewEditor.background": mantle,
        "peekViewEditorGutter.background": mantle,
        "peekViewEditor.matchHighlightBackground": alpha(accent, 0.25),
        "peekViewResult.background": mantle,
        "peekViewResult.fileForeground": text,
        "peekViewResult.lineForeground": subtext,
        "peekViewResult.matchHighlightBackground": alpha(accent, 0.25),
        "peekViewResult.selectionBackground": sel_accent,
        "peekViewResult.selectionForeground": text,
        "peekViewTitle.background": mantle,
        "peekViewTitleLabel.foreground": text,
        "peekViewTitleDescription.foreground": subtext,
        "scrollbar.shadow": none,
        "scrollbarSlider.background": alpha(text, 0.12),
        "scrollbarSlider.hoverBackground": alpha(text, 0.20),
        "scrollbarSlider.activeBackground": alpha(text, 0.30),
        "minimap.findMatchHighlight": accent,
        "minimap.selectionHighlight": alpha(text, 0.30),
        "minimap.errorHighlight": red,
        "minimap.warningHighlight": yellow,
        "minimapSlider.background": alpha(text, 0.08),
        "minimapSlider.hoverBackground": alpha(text, 0.12),
        "minimapSlider.activeBackground": alpha(text, 0.16),
        "minimapGutter.addedBackground": green,
        "minimapGutter.modifiedBackground": yellow,
        "minimapGutter.deletedBackground": red,
        # --- chrome: paper with hairlines, no coloured bars ---------------------
        "activityBar.background": paper,
        "activityBar.foreground": text,
        "activityBar.inactiveForeground": overlay,
        "activityBar.border": hairline,
        "activityBar.activeBorder": accent,
        "activityBar.activeBackground": none,
        "activityBar.dropBorder": accent,
        "activityBarBadge.background": accent,
        "activityBarBadge.foreground": on_accent,
        "activityBarTop.foreground": text,
        "activityBarTop.inactiveForeground": overlay,
        "activityBarTop.activeBorder": accent,
        "badge.background": accent,
        "badge.foreground": on_accent,
        "sideBar.background": paper,
        "sideBar.foreground": text,
        "sideBar.border": hairline,
        "sideBar.dropBackground": alpha(accent, 0.10),
        "sideBarTitle.foreground": subtext,
        "sideBarSectionHeader.background": paper,
        "sideBarSectionHeader.foreground": text,
        "sideBarSectionHeader.border": hairline,
        "sideBarStickyScroll.background": paper,
        "sideBarStickyScroll.border": hairline,
        "statusBar.background": paper,
        "statusBar.foreground": subtext,
        "statusBar.border": hairline,
        "statusBar.focusBorder": accent,
        "statusBar.noFolderBackground": paper,
        "statusBar.noFolderForeground": subtext,
        "statusBar.noFolderBorder": hairline,
        "statusBar.debuggingBackground": paper,
        "statusBar.debuggingForeground": accent,
        "statusBar.debuggingBorder": accent,
        "statusBarItem.hoverBackground": alpha(text, 0.08),
        "statusBarItem.activeBackground": alpha(text, 0.14),
        "statusBarItem.prominentBackground": alpha(text, 0.08),
        "statusBarItem.prominentForeground": text,
        "statusBarItem.prominentHoverBackground": alpha(text, 0.14),
        "statusBarItem.remoteBackground": paper,
        "statusBarItem.remoteForeground": accent,
        "statusBarItem.remoteHoverBackground": alpha(text, 0.08),
        "statusBarItem.errorBackground": paper,
        "statusBarItem.errorForeground": red,
        "statusBarItem.errorHoverBackground": alpha(text, 0.08),
        "statusBarItem.warningBackground": paper,
        "statusBarItem.warningForeground": yellow,
        "statusBarItem.warningHoverBackground": alpha(text, 0.08),
        "statusBarItem.focusBorder": accent,
        "titleBar.activeBackground": paper,
        "titleBar.activeForeground": text,
        "titleBar.inactiveBackground": paper,
        "titleBar.inactiveForeground": subtext,
        "titleBar.border": hairline,
        "menubar.selectionBackground": alpha(text, 0.08),
        "menubar.selectionForeground": text,
        "menu.background": mantle,
        "menu.foreground": text,
        "menu.selectionBackground": sel_accent,
        "menu.selectionForeground": text,
        "menu.selectionBorder": none,
        "menu.separatorBackground": hairline,
        "menu.border": hairline,
        "commandCenter.background": mantle,
        "commandCenter.foreground": subtext,
        "commandCenter.activeForeground": text,
        "commandCenter.activeBackground": alpha(text, 0.06),
        "commandCenter.border": hairline,
        "commandCenter.inactiveBorder": hairline,
        "commandCenter.inactiveForeground": overlay,
        "commandCenter.activeBorder": hairline,
        "tab.activeBackground": paper,
        "tab.activeForeground": text,
        "tab.inactiveBackground": paper,
        "tab.inactiveForeground": subtext,
        "tab.unfocusedActiveBackground": paper,
        "tab.unfocusedActiveForeground": subtext,
        "tab.unfocusedInactiveBackground": paper,
        "tab.unfocusedInactiveForeground": overlay,
        "tab.hoverBackground": mantle,
        "tab.hoverForeground": text,
        "tab.border": hairline,
        "tab.activeBorder": paper,
        "tab.activeBorderTop": accent,
        "tab.unfocusedActiveBorderTop": alpha(accent, 0.5),
        "tab.lastPinnedBorder": hairline,
        "tab.activeModifiedBorder": yellow,
        "tab.inactiveModifiedBorder": alpha(yellow, 0.5),
        "tab.dragAndDropBorder": accent,
        "breadcrumb.background": paper,
        "breadcrumb.foreground": subtext,
        "breadcrumb.focusForeground": text,
        "breadcrumb.activeSelectionForeground": text,
        "breadcrumbPicker.background": mantle,
        "panel.background": paper,
        "panel.border": hairline,
        "panel.dropBorder": accent,
        "panelTitle.activeBorder": accent,
        "panelTitle.activeForeground": text,
        "panelTitle.inactiveForeground": subtext,
        "panelTitle.border": hairline,
        "panelInput.border": hairline,
        "panelSection.border": hairline,
        "panelSectionHeader.background": paper,
        "panelSectionHeader.foreground": text,
        "panelSectionHeader.border": hairline,
        "terminal.background": paper,
        "terminal.foreground": text,
        "terminal.border": hairline,
        "terminal.selectionBackground": alpha(text, 0.18),
        "terminal.inactiveSelectionBackground": alpha(text, 0.10),
        "terminal.findMatchBackground": alpha(accent, 0.35 if light else 0.40),
        "terminal.findMatchHighlightBackground": alpha(accent, 0.18),
        "terminalCursor.foreground": accent,
        "terminalCursor.background": paper,
        "terminal.tab.activeBorder": accent,
        "terminalStickyScroll.background": paper,
        "terminalStickyScrollHover.background": mantle,
        # --- lists, inputs, pickers -------------------------------------------
        "list.activeSelectionBackground": sel_accent,
        "list.activeSelectionForeground": text,
        "list.activeSelectionIconForeground": text,
        "list.inactiveSelectionBackground": alpha(text, 0.08),
        "list.inactiveSelectionForeground": text,
        "list.focusBackground": alpha(accent, 0.12),
        "list.focusForeground": text,
        "list.focusOutline": accent,
        "list.focusAndSelectionOutline": accent,
        "list.inactiveFocusOutline": hairline,
        "list.hoverBackground": alpha(text, 0.05),
        "list.hoverForeground": text,
        "list.dropBackground": alpha(accent, 0.10),
        "list.highlightForeground": accent,
        "list.focusHighlightForeground": accent,
        "list.deemphasizedForeground": overlay,
        "list.errorForeground": red,
        "list.warningForeground": yellow,
        "list.invalidItemForeground": red,
        "list.filterMatchBackground": alpha(accent, 0.20),
        "list.filterMatchBorder": none,
        "listFilterWidget.background": mantle,
        "listFilterWidget.outline": accent,
        "listFilterWidget.noMatchesOutline": red,
        "listFilterWidget.shadow": none,
        "tree.indentGuidesStroke": alpha(text, 0.28),
        "tree.inactiveIndentGuidesStroke": faint,
        "tree.tableColumnsBorder": hairline,
        "tree.tableOddRowsBackground": alpha(text, 0.03),
        "input.background": mantle,
        "input.foreground": text,
        "input.border": hairline,
        "input.placeholderForeground": overlay,
        "inputOption.activeBackground": sel_accent,
        "inputOption.activeBorder": accent,
        "inputOption.activeForeground": text,
        "inputOption.hoverBackground": alpha(text, 0.08),
        "inputValidation.errorBackground": mantle,
        "inputValidation.errorForeground": text,
        "inputValidation.errorBorder": red,
        "inputValidation.warningBackground": mantle,
        "inputValidation.warningForeground": text,
        "inputValidation.warningBorder": yellow,
        "inputValidation.infoBackground": mantle,
        "inputValidation.infoForeground": text,
        "inputValidation.infoBorder": blue,
        "dropdown.background": mantle,
        "dropdown.listBackground": mantle,
        "dropdown.foreground": text,
        "dropdown.border": hairline,
        "checkbox.background": mantle,
        "checkbox.foreground": text,
        "checkbox.border": hairline,
        "checkbox.selectBackground": mantle,
        "checkbox.selectBorder": accent,
        "radio.activeForeground": text,
        "radio.activeBackground": sel_accent,
        "radio.activeBorder": accent,
        "radio.inactiveForeground": subtext,
        "radio.inactiveBackground": mantle,
        "radio.inactiveBorder": hairline,
        "button.background": accent,
        "button.foreground": on_accent,
        "button.hoverBackground": hover,
        "button.border": none,
        "button.separator": alpha(on_accent, 0.4),
        "button.secondaryBackground": surface0,
        "button.secondaryForeground": text,
        "button.secondaryHoverBackground": surface1 if not light else mix(surface0, text, 0.1),
        "progressBar.background": accent,
        "quickInput.background": mantle,
        "quickInput.foreground": text,
        "quickInputTitle.background": mantle,
        "quickInputList.focusBackground": sel_accent,
        "quickInputList.focusForeground": text,
        "quickInputList.focusIconForeground": text,
        "pickerGroup.foreground": accent,
        "pickerGroup.border": hairline,
        "keybindingLabel.background": alpha(text, 0.06),
        "keybindingLabel.foreground": text,
        "keybindingLabel.border": hairline,
        "keybindingLabel.bottomBorder": hairline,
        "notifications.background": mantle,
        "notifications.foreground": text,
        "notifications.border": hairline,
        "notificationCenter.border": hairline,
        "notificationCenterHeader.background": mantle,
        "notificationCenterHeader.foreground": text,
        "notificationToast.border": hairline,
        "notificationLink.foreground": accent,
        "notificationsErrorIcon.foreground": red,
        "notificationsWarningIcon.foreground": yellow,
        "notificationsInfoIcon.foreground": blue,
        "banner.background": mantle,
        "banner.foreground": text,
        "banner.iconForeground": accent,
        "settings.headerForeground": text,
        "settings.modifiedItemIndicator": accent,
        "settings.focusedRowBackground": alpha(text, 0.04),
        "settings.focusedRowBorder": accent,
        "settings.rowHoverBackground": alpha(text, 0.03),
        "settings.headerBorder": hairline,
        "settings.sashBorder": hairline,
        "settings.dropdownBackground": mantle,
        "settings.dropdownBorder": hairline,
        "settings.dropdownListBorder": hairline,
        "settings.checkboxBackground": mantle,
        "settings.checkboxBorder": hairline,
        "settings.textInputBackground": mantle,
        "settings.textInputBorder": hairline,
        "settings.numberInputBackground": mantle,
        "settings.numberInputBorder": hairline,
        "welcomePage.background": paper,
        "welcomePage.tileBackground": mantle,
        "welcomePage.tileHoverBackground": alpha(text, 0.06),
        "welcomePage.tileBorder": hairline,
        "welcomePage.progress.background": faint,
        "welcomePage.progress.foreground": accent,
        "walkThrough.embeddedEditorBackground": mantle,
        "extensionButton.prominentBackground": accent,
        "extensionButton.prominentForeground": on_accent,
        "extensionButton.prominentHoverBackground": hover,
        "extensionButton.background": accent,
        "extensionButton.foreground": on_accent,
        "extensionButton.hoverBackground": hover,
        "extensionBadge.remoteBackground": accent,
        "extensionBadge.remoteForeground": on_accent,
        "extensionIcon.starForeground": yellow,
        "extensionIcon.verifiedForeground": accent,
        "extensionIcon.preReleaseForeground": yellow,
        "gitDecoration.addedResourceForeground": green,
        "gitDecoration.modifiedResourceForeground": yellow,
        "gitDecoration.deletedResourceForeground": red,
        "gitDecoration.renamedResourceForeground": green,
        "gitDecoration.untrackedResourceForeground": green,
        "gitDecoration.ignoredResourceForeground": overlay,
        "gitDecoration.conflictingResourceForeground": red,
        "gitDecoration.submoduleResourceForeground": subtext,
        "gitDecoration.stageModifiedResourceForeground": yellow,
        "gitDecoration.stageDeletedResourceForeground": red,
        "problemsErrorIcon.foreground": red,
        "problemsWarningIcon.foreground": yellow,
        "problemsInfoIcon.foreground": blue,
        "searchEditor.findMatchBackground": alpha(accent, 0.18),
        "searchEditor.textInputBorder": hairline,
        "search.resultsInfoForeground": subtext,
        "debugToolBar.background": mantle,
        "debugToolBar.border": hairline,
        "debugIcon.breakpointForeground": red,
        "debugIcon.breakpointDisabledForeground": overlay,
        "debugIcon.startForeground": green,
        "debugIcon.pauseForeground": yellow,
        "debugIcon.stopForeground": red,
        "debugIcon.continueForeground": green,
        "debugIcon.stepOverForeground": blue,
        "debugIcon.stepIntoForeground": blue,
        "debugIcon.stepOutForeground": blue,
        "debugIcon.restartForeground": green,
        "editor.stackFrameHighlightBackground": alpha(yellow, 0.20),
        "editor.focusedStackFrameHighlightBackground": alpha(green, 0.20),
        "debugConsole.infoForeground": blue,
        "debugConsole.warningForeground": yellow,
        "debugConsole.errorForeground": red,
        "debugConsole.sourceForeground": subtext,
        "debugConsoleInputIcon.foreground": accent,
        "testing.iconPassed": green,
        "testing.iconFailed": red,
        "testing.iconErrored": red,
        "testing.iconQueued": yellow,
        "testing.iconSkipped": overlay,
        "testing.iconUnset": subtext,
        "testing.runAction": accent,
        "charts.foreground": text,
        "charts.lines": hairline,
        "charts.red": red,
        "charts.blue": blue,
        "charts.yellow": yellow,
        "charts.orange": c["peach"],
        "charts.green": green,
        "charts.purple": c["mauve"],
        "symbolIcon.classForeground": blue,
        "symbolIcon.interfaceForeground": blue,
        "symbolIcon.structForeground": blue,
        "symbolIcon.enumeratorForeground": blue,
        "symbolIcon.typeParameterForeground": blue,
        "symbolIcon.namespaceForeground": c["teal"],
        "symbolIcon.moduleForeground": c["teal"],
        "symbolIcon.packageForeground": c["teal"],
        "symbolIcon.functionForeground": text,
        "symbolIcon.methodForeground": text,
        "symbolIcon.constructorForeground": text,
        "symbolIcon.variableForeground": text,
        "symbolIcon.fieldForeground": text,
        "symbolIcon.propertyForeground": text,
        "symbolIcon.keywordForeground": accent,
        "symbolIcon.constantForeground": accent_dim if light else mix(accent, text, 0.3),
        "symbolIcon.enumeratorMemberForeground": accent_dim if light else mix(accent, text, 0.3),
        "symbolIcon.stringForeground": yellow,
        "symbolIcon.numberForeground": accent_dim if light else mix(accent, text, 0.3),
        "symbolIcon.textForeground": subtext,
        "symbolIcon.snippetForeground": subtext,
        "symbolIcon.fileForeground": subtext,
        "symbolIcon.folderForeground": subtext,
        "symbolIcon.colorForeground": subtext,
        "symbolIcon.keyForeground": text,
        "symbolIcon.nullForeground": accent_dim if light else mix(accent, text, 0.3),
        "symbolIcon.booleanForeground": accent_dim if light else mix(accent, text, 0.3),
        "symbolIcon.operatorForeground": subtext,
        "symbolIcon.unitForeground": subtext,
        "symbolIcon.eventForeground": text,
        "symbolIcon.arrayForeground": text,
        "symbolIcon.objectForeground": text,
        "symbolIcon.referenceForeground": text,
    }
    names = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]
    for i, n in enumerate(names):
        if i in ansi and i + 8 in ansi:
            w["terminal.ansi" + n] = ansi[i]
            w["terminal.ansiBright" + n] = ansi[i + 8]
    return w


def syntax(c, accent, accent_dim, light):
    paper, text, subtext = c["base"], c["text"], c["subtext"]
    numbers = accent_dim if light else mix(accent, text, 0.3)
    ink = {
        "string": readable(c["yellow"], paper, text),
        "type": readable(c["blue"], paper, text),
        "support": readable(c["teal"], paper, text),
        "numbers": readable(numbers, paper, text),
        "keyword": accent,
        "text": text,
        "subtext": subtext,
        "red": c["red"],
        "green": readable(c["green"], paper, text),
        "yellow": readable(c["yellow"], paper, text),
    }
    rules = [
        ("Comments", ["comment", "punctuation.definition.comment", "string.comment"],
         {"foreground": ink["subtext"], "fontStyle": "italic"}),
        ("Body ink: variables, functions, operators", [
            "variable", "variable.other", "variable.parameter", "variable.other.property",
            "entity.name.function", "support.function", "meta.function-call",
            "entity.name.variable", "entity.name.label", "entity.name.section",
            "keyword.operator", "keyword.operator.assignment", "keyword.operator.arithmetic",
            "keyword.operator.comparison", "keyword.operator.logical",
            "support.variable", "support.type.property-name", "meta.object-literal.key",
            "entity.other.attribute-name", "source", "meta.embedded",
        ], {"foreground": ink["text"]}),
        ("Punctuation", [
            "punctuation", "punctuation.separator", "punctuation.terminator",
            "punctuation.definition", "punctuation.accessor", "meta.brace",
            "punctuation.definition.tag", "punctuation.section",
        ], {"foreground": ink["subtext"]}),
        ("Keywords and storage: the accent", [
            "keyword", "keyword.control", "keyword.other", "keyword.operator.new",
            "keyword.operator.expression", "keyword.operator.delete",
            "keyword.operator.typeof", "keyword.operator.instanceof", "keyword.operator.wordlike",
            "storage", "storage.type", "storage.modifier", "storage.type.function",
            "storage.type.class", "variable.language", "keyword.control.directive",
            "entity.name.function.preprocessor", "keyword.other.unit.suffix",
        ], {"foreground": ink["keyword"]}),
        ("Strings: the second tone", [
            "string", "string.quoted", "string.template", "string.regexp",
            "string.other.link", "punctuation.definition.string",
            "markup.inline.raw", "markup.fenced_code", "markup.raw",
            "entity.other.attribute-name.value",
        ], {"foreground": ink["string"]}),
        ("Interpolation and escapes inside strings", [
            "constant.character.escape", "punctuation.definition.template-expression",
            "punctuation.section.embedded", "meta.template.expression",
            "constant.character.format.placeholder", "punctuation.definition.interpolation",
        ], {"foreground": ink["numbers"]}),
        ("Types and classes", [
            "entity.name.type", "entity.name.class", "entity.name.struct", "entity.name.enum",
            "entity.name.interface", "entity.name.type.class", "entity.other.inherited-class",
            "support.class", "entity.name.scope-resolution", "meta.type.annotation",
            "entity.other.attribute-name.class.css", "entity.other.attribute-name.id.css",
        ], {"foreground": ink["type"]}),
        ("Built-in types, namespaces, tags", [
            "support.type", "support.type.primitive", "support.type.builtin",
            "entity.name.namespace", "entity.name.module", "entity.name.tag",
            "entity.name.tag.css", "support.constant.property-value",
        ], {"foreground": ink["support"]}),
        ("Numbers, constants, booleans, null", [
            "constant", "constant.numeric", "constant.language", "constant.character",
            "constant.other", "variable.other.constant", "support.constant",
            "keyword.other.unit", "entity.name.function.decorator", "meta.decorator",
            "punctuation.decorator", "variable.other.enummember",
        ], {"foreground": ink["numbers"]}),
        ("Markup: headings", ["markup.heading", "entity.name.section.markdown",
                              "punctuation.definition.heading"],
         {"foreground": ink["text"], "fontStyle": "bold"}),
        ("Markup: emphasis", ["markup.italic"], {"fontStyle": "italic"}),
        ("Markup: strong", ["markup.bold"], {"fontStyle": "bold"}),
        ("Markup: links", ["markup.underline.link", "string.other.link.title",
                           "constant.other.reference.link"],
         {"foreground": ink["keyword"]}),
        ("Markup: quotes", ["markup.quote"], {"foreground": ink["subtext"], "fontStyle": "italic"}),
        ("Markup: list bullets", ["punctuation.definition.list.begin",
                                  "markup.list punctuation.definition.list"],
         {"foreground": ink["keyword"]}),
        ("Diff", ["markup.inserted", "markup.inserted punctuation.definition.inserted"],
         {"foreground": ink["green"]}),
        ("Diff", ["markup.deleted", "markup.deleted punctuation.definition.deleted"],
         {"foreground": ink["red"]}),
        ("Diff", ["markup.changed"], {"foreground": ink["yellow"]}),
        ("Diff header", ["meta.diff.header", "meta.diff.range", "meta.diff.index",
                         "punctuation.definition.from-file", "punctuation.definition.to-file"],
         {"foreground": ink["subtext"], "fontStyle": "italic"}),
        ("Invalid", ["invalid", "invalid.illegal"], {"foreground": ink["red"]}),
        ("Deprecated", ["invalid.deprecated"], {"foreground": ink["yellow"], "fontStyle": "strikethrough"}),
    ]
    token_colors = [{"name": n, "scope": s, "settings": st} for n, s, st in rules]
    semantic = {
        "comment": {"foreground": ink["subtext"], "fontStyle": "italic"},
        "string": ink["string"],
        "keyword": ink["keyword"],
        "modifier": ink["keyword"],
        "macro": ink["keyword"],
        "selfKeyword": ink["keyword"],
        "builtinType": ink["support"],
        "type": ink["type"],
        "class": ink["type"],
        "struct": ink["type"],
        "interface": ink["type"],
        "enum": ink["type"],
        "typeParameter": ink["type"],
        "typeAlias": ink["type"],
        "namespace": ink["support"],
        "function": ink["text"],
        "method": ink["text"],
        "variable": ink["text"],
        "parameter": ink["text"],
        "property": ink["text"],
        "number": ink["numbers"],
        "enumMember": ink["numbers"],
        "boolean": ink["numbers"],
        "decorator": ink["numbers"],
        "operator": ink["text"],
        "*.deprecated": {"fontStyle": "strikethrough"},
    }
    return token_colors, semantic, ink


# ---- outputs ----------------------------------------------------------------------
def theme_json(theme, cols, pal, m, ansi):
    light = m.get("COLOR_SCHEME") == "prefer-light"
    accent = pal.get("accent") or cols.get("accent") or cols["blue"]
    accent_dim = pal.get("accent_dim") or mix(accent, cols["base"], 0.25)
    label = LABEL + m.get("MENU_NAME", theme)
    token_colors, semantic, ink = syntax(cols, accent, accent_dim, light)
    return label, {
        "$schema": "vscode://schemas/color-theme",
        "name": label,
        "type": "light" if light else "dark",
        "semanticHighlighting": True,
        "colors": workbench(cols, accent, accent_dim, light, ansi),
        "tokenColors": token_colors,
        "semanticTokenColors": semantic,
    }, light


def package_json(contributed):
    return {
        "name": NAME,
        "displayName": "Letterpress themes",
        "description": "One VS Code colour theme per dram theme: paper, ink, one accent, hairlines "
                       "(generated by bin/gen-vscode-themes.py; do not edit).",
        "publisher": PUBLISHER,
        "version": VERSION,
        "license": "MIT",
        "engines": {"vscode": "^1.90.0"},
        "categories": ["Themes"],
        "contributes": {"themes": contributed},
    }


def dump(obj):
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def write(target, out):
    old = open(target, encoding="utf-8").read() if os.path.exists(target) else None
    if old != out:
        os.makedirs(os.path.dirname(target), exist_ok=True)
        open(target, "w", encoding="utf-8").write(out)
        print("wrote", os.path.relpath(target, ROOT))


def render(theme):
    d = os.path.join(THEMES, theme)
    cols = define_colors(os.path.join(d, "waybar.css"))
    missing = [k for k in NEEDED if not cols.get(k)]
    if missing:
        sys.exit(f"{theme}: waybar.css lacks {missing}")
    pal = palette_lua(os.path.join(d, "palette.lua"))
    m = meta(os.path.join(d, "meta.sh"))
    ansi = kitty_ansi(os.path.join(d, "kitty.conf"))
    label, obj, light = theme_json(theme, cols, pal, m, ansi)
    rel = f"themes/letterpress-{theme}-color-theme.json"
    write(os.path.join(EXT, rel), dump(obj))
    return {"label": label, "uiTheme": "vs" if light else "vs-dark", "path": "./" + rel}


def _parse_args():
    """argparse over the module docstring: usage line, description, hidden flags."""
    import argparse
    doc = (__doc__ or "").strip().splitlines()
    ap = argparse.ArgumentParser(
        prog=doc[0].split()[1], usage=doc[0][len("usage: "):],
        description="\n".join(doc[1:]).strip(), add_help=False,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-h", "--help", action="help", help=argparse.SUPPRESS)
    ap.add_argument("theme", nargs="*", help=argparse.SUPPRESS)
    return ap.parse_args()


def main(argv):
    every = sorted(
        t for t in os.listdir(THEMES)
        if os.path.isdir(os.path.join(THEMES, t)) and t != "current"
    )
    contributed = [render(t) for t in (argv or every)]
    if not argv:  # package.json lists every theme; only a full run knows them all
        write(os.path.join(EXT, "package.json"), dump(package_json(contributed)))


if __name__ == "__main__":
    main(_parse_args().theme)
