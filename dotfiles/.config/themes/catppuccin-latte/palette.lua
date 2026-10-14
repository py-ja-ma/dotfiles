-- Catppuccin Latte — Hyprland palette (loaded by hyprland.lua via dofile)
return {
    accent     = "rgba(1e66f5ee)",  -- the ONE accent ink: active border, waybar №, cursor
    accent_dim = "rgba(2c5fcbee)",  -- same ink, darker: far end of the border gradient
    active1  = "rgba(1e66f5ee)",  -- blue
    active2  = "rgba(8839efee)",  -- mauve
    angle    = 45,
    inactive = "rgba(bcc0ccaa)",  -- surface1
    shadow   = "rgba(4c4f6959)",  -- dark grey drop-shadow (latte @text) — was a pale white halo.
                                   -- Darkness is what makes it read as a shadow; tune alpha 0x4d..0x66 if heavy/faint.
}
