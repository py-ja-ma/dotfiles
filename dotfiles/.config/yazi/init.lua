-- dotfiles/.config/yazi/README.md ("The flavors"): the mode word is a plain word — NORMAL /
-- SELECT / UNSET — but upstream Status:mode() truncates it to 3 chars (NOR).
-- Mirrors yazi v26.9.1 yazi-plugin/preset/components/status.lua minus :sub(1, 3).
function Status:mode()
	local mode = tostring(self._tab.mode):upper()

	local style = self:style()
	return ui.Line {
		ui.Span(th.status.sep_left.open):fg(style.main:bg()):bg(App.bg()),
		ui.Span(" " .. mode .. " "):style(style.main),
		ui.Span(th.status.sep_left.close):fg(style.main:bg()):bg(style.alt:bg()),
	}
end
