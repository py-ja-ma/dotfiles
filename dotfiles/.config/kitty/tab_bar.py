"""kitty tab bar — the running head (tab_bar_style custom, see README.md here).

The tabs are drawn exactly as kitty's own `separator` style would draw them
(title template, tab_separator, the theme's tab colours), and after the last
tab the date is set flush right in italic, in the inactive-tab ink — the way a
printed page carries its chapter title on one side and its folio on the other.

Russian-with-fallback rule: the date is Russian when the ru_RU.UTF-8 locale
exists, English otherwise. Any failure in the running head leaves the tabs
untouched (and kitty's own wrapper falls back to its fade style if this file
fails to load at all), so the theme's tab colours always hold.
"""
import datetime
import locale

from kitty.fast_data_types import Screen
from kitty.tab_bar import DrawData, ExtraData, TabBarData, as_rgb, draw_tab_with_separator
from kitty.utils import color_as_int

try:
    locale.setlocale(locale.LC_TIME, "ru_RU.UTF-8")
except locale.Error:
    pass  # English date; see docs/design/typography/README.md ("Russian")

_cache: tuple = (None, "")


def running_head() -> str:
    """Today as "Вторник, 6 октября" (or "Tuesday, 6 October"), cached per day."""
    global _cache
    today = datetime.date.today()
    if _cache[0] != today:
        _cache = (today, today.strftime("%A, %-d %B"))
    return _cache[1]


def draw_running_head(draw_data: DrawData, screen: Screen) -> None:
    text = running_head()
    start = screen.columns - len(text) - 1  # one cell of slack, like the leading space
    if start < screen.cursor.x + 2:
        return  # the tabs need the room more than the date does
    screen.cursor.x = start
    screen.cursor.bg = as_rgb(color_as_int(draw_data.default_bg))
    screen.cursor.fg = as_rgb(color_as_int(draw_data.inactive_fg))
    screen.cursor.bold, screen.cursor.italic = False, True
    screen.draw(text)
    screen.cursor.italic = False
    screen.cursor.fg = screen.cursor.bg = 0


def draw_tab(
    draw_data: DrawData, screen: Screen, tab: TabBarData, before: int,
    max_tab_length: int, index: int, is_last: bool, extra_data: ExtraData,
) -> int:
    end = draw_tab_with_separator(draw_data, screen, tab, before, max_tab_length, index, is_last, extra_data)
    if is_last and not getattr(extra_data, "for_layout", False):
        try:
            draw_running_head(draw_data, screen)
        except Exception:
            pass
    return end
