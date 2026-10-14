#version 300 es
// grain.frag — paper-grain screen shader for Hyprland (decoration:screen_shader).
// (#version stays on line 1: Hyprland picks the vertex shader by the first bytes.)
//
// Static hash noise (2.5%) multiplied into the final frame plus a 1.5% warm
// vignette, so the desktop reads like stock rather than a backlit panel.
//
// ABI (Hyprland 0.56, src/render/OpenGL.cpp applyScreenShader / Shader.cpp):
//   #version 300 es            -> paired with the TEXVERTSRC (300 es) vertex shader
//   in  vec2 v_texcoord        -> 0..1 across the output
//   uniform sampler2D tex      -> the composited frame
//   uniform vec2 fullSize      -> output size in px ("screen_size"/"screenSize" are aliases)
//   uniform int  wl_output     -> monitor id (unused here)
//   layout(location = 0) out vec4 fragColor
// Deliberately NO `time` uniform: Hyprland disables damage tracking for a shader
// that declares it, which means a full-screen redraw every frame (hot NVIDIA).
// The noise is keyed off the pixel position only, so it is stable per frame.
//
// gamemode.sh clears this (decoration:screen_shader = "") while game mode is on.

precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
uniform vec2 fullSize;
layout(location = 0) out vec4 fragColor;

const float GRAIN     = 0.025;   // +-2.5% luminance
const float VIGNETTE  = 0.015;   // 1.5% at the corners
const vec3  WARM      = vec3(1.00, 0.985, 0.955);   // edges drop blue a touch more than red

float hash(vec2 p) {
    // classic one-liner hash; good enough for grain, no texture needed
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec4 color = texture(tex, v_texcoord);

    // grain on integer pixel coords so it never swims under damage-tracked redraws
    vec2 px = floor(v_texcoord * max(fullSize, vec2(1.0)));
    float n = hash(px) - 0.5;                 // -0.5 .. 0.5
    color.rgb *= 1.0 + n * 2.0 * GRAIN;

    // soft warm vignette: 0 in the middle, full at the corners
    float d = length((v_texcoord - 0.5) * vec2(1.0, fullSize.y / max(fullSize.x, 1.0)) * 2.0);
    float v = smoothstep(0.55, 1.35, d);
    color.rgb *= mix(vec3(1.0), WARM * (1.0 - VIGNETTE), v);

    fragColor = color;
}
