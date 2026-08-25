// =============================================================================
// ricochet-template — unified draw shader (single fragment shader for the
// whole project, installed via set_draw_shader as the engine's default).
//
// THREE-AXIS MODEL
//   Every fragment is processed as:
//
//       f   = pattern(world_pos, time, scale, param)   // [0, 1]
//       f   = dither(f, pixel_pos)                     // {0, 1/n, …, 1}
//       rgb = color(base_rgb, f, palette[color_a], palette[color_b])
//
//   Pattern owns spatial structure AND animation. Color is a pure recipe
//   that picks/mixes palette tokens by f. Dither inserts the pixel-art
//   stipple between them. The three are independent — any combination is
//   valid. See effect.lua for the registered names per axis.
//
// VARYING INPUTS (from engine vertex shader; do not rename)
//   vPos       World-space fragment position. For camera-attached layers
//              this is camera-transformed world space.
//   vUV        0..1 UV inside the draw's quad (or sprite UV for sprites).
//   vColor     Per-vertex RGBA color (the `color` arg passed to layer_*).
//   vType      Shape dispatch: 0=rect, 1=circle, 2=sprite, 3=line/capsule,
//              4=triangle, 5=polygon, 6=rounded rect.
//   vShape0..4 Per-shape parameter bundle.
//   vAddColor  Per-vertex additive RGB offset (engine 'flash' channel).
//
// UNIFORMS YOU SET FROM LUA (via effect.lua's effect_set)
//   u_pattern_kind   int   1=organic 2=solid 3=plasma 4=waves 5=marble
//                          6=sine_grid 7=wood 8=truchet 9=contours
//                          10=linear_gradient 11=radial_gradient (LOCAL)
//   u_pattern_scale  float world-units multiplier for the pattern field
//                          (ignored by the LOCAL gradient patterns)
//   u_pattern_param  float pattern-specific knob (unused by organic/solid)
//   u_pattern_param2 float 2nd pattern-specific knob — gradient OFFSET / RANGE
//   u_dither_kind    int   0=off, 1=bayer4_2, 2=bayer8_2, 3=noise_2
//   u_deco_kind      int   0=none 1=circle 2=square 3=diamond 4=hexagon
//                          5=cross 6=triangle 7=sprite — the DECO layer
//                          (shapes composited OVER the base; see DECO block)
//   u_color_kind     int   0=none (passthrough), 1=solid, 2=mix, 3=ramp
//   u_ramp_tokens[8] int   ordered palette token indices for color='ramp'
//   u_ramp_count     int   number of active ramp stops (2..8)
//   u_color_a        int   palette token index (0..25)
//   u_color_b        int   palette token index (0..25)
//   u_time           float elapsed seconds (for time-varying patterns)
//   u_palette[26]    vec4  active palette; .rgb per token (alpha unused)
//
// PALETTE TOKEN INDICES (mirrors emoji/palette.lua's palette_token_names) —
// the 22 Twemoji tokens (chrome ladder + accent hue wheel + extras + sky);
// slots 22..25 are unused headroom.
//   0 black       1 bg_color     2 gray         3 fg_dark      4 fg
//   5 white       6 red          7 orange       8 yellow       9 star_yellow
//  10 green      11 blue        12 purple      13 pink        14 brown
//  15 bowstring  16 bronze      17 silver      18 medal_gold  19 sky_top
//  20 sky_bottom 21 wall_color
//
// HOW TO ADD A NEW PATTERN
//   1. Add a function below the "PATTERNS" header that takes
//      (vec2 world_pos, float scale, float param, float t) and returns a
//      float in [0, 1].
//   2. Add a branch in pattern_field() for a new kind id.
//   3. In effect.lua: add to pattern_kinds + pattern_cycle_names.
//
// HOW TO ADD A NEW COLOR RECIPE
//   1. Add a branch in apply_color() for a new kind id. The recipe receives
//      (base, f, palette[color_a], palette[color_b]) — use what you need.
//   2. In effect.lua: add to color_kinds + color_cycle_names.
//
// HOW TO ADD A NEW DITHER
//   1. Add a branch in apply_dither() with the quantization math.
//   2. In effect.lua: add to dither_kinds + dither_cycle_names.
// =============================================================================

in vec2 vPos;
in vec2 vUV;
in vec4 vColor;
in float vType;
in vec4 vShape0;
in vec4 vShape1;
in vec4 vShape2;
in vec4 vShape3;
in vec4 vShape4;
in vec3 vAddColor;

out vec4 FragColor;

uniform float u_aa_width;
uniform sampler2D u_texture;

// Three-axis effect uniforms (write from Lua via effect_set).
uniform int   u_pattern_kind;
uniform float u_pattern_scale;
uniform float u_pattern_param;     // per-pattern intrinsic knob (meaning varies by pattern)
uniform float u_pattern_param2;    // second per-pattern intrinsic knob (used by the local gradients)
uniform float u_pattern_speed;     // animation rate multiplier (universal)
uniform float u_pattern_contrast;  // mid-range spread (universal): <1 softer, >1 punchier
uniform float u_value_mult;        // final-RGB multiplier (universal): a whole-recipe
                                   // darken/brighten — the SNKRX "darker shade of the
                                   // same colors" idiom (glyph ink). <=0 reads as 1
                                   // (unset-uniform safety; effect_clear resets to 1)
uniform int   u_dither_kind;
// DECO — TWO independent decoration layers: per-cell shapes composited OVER
// the base (tone-on-tone anime-bg outlines, manga screentone dots). The base
// renders normally; deco never masks it away. Each layer has its own grid,
// driver field, and color recipe; layer 2 composites over layer 1's result.
// Color modes (u_decoN_color_mode):
//   0 shade  — deco color = base * (1 + shade); the tone-on-tone default
//   1 solid  — palette[color]
//   2 across — mix(color, color_b, driver field at the CELL) — one color per
//              shape, varying across the whole draw
//   3 inside — mix(color, color_b, gauge metric) — center→edge gradient
//              self-contained within every shape
//   4 flow   — mix(color, color_b, driver field at the FRAGMENT) — shapes as
//              windows onto one continuous gradient
uniform int   u_deco_kind;          // 0=none 1=circle 2=square 3=diamond 4=hexagon 5=cross 6=triangle 7=sprite
uniform float u_deco_size;          // base shape size, px
uniform float u_deco_size_var;      // 0..1 — how much the driver field modulates size
uniform float u_deco_pitch;         // cell spacing, px
uniform float u_deco_rotation;      // shared rotation, 0..1 = a full turn
uniform float u_deco_rotation_var;  // 0..1 — per-cell hashed extra rotation
uniform float u_deco_jitter;        // 0..1 — per-cell position offset (fraction of pitch)
uniform float u_deco_outline;       // 0 = filled; >0 = outline band width, px (rings/hollow shapes)
uniform float u_deco_shade;         // color mode 0: deco color = base * (1 + shade)
uniform int   u_deco_color_mode;    // see the mode list above
uniform int   u_deco_color;         // token A
uniform int   u_deco_color_b;       // token B (mix modes 2/3/4)
uniform int   u_deco_driver;        // pattern kind driving the variation; 0 = the draw's main pattern
uniform float u_deco_driver_scale;  // driver field density
uniform float u_deco_driver_speed;  // driver animation rate
uniform sampler2D u_deco_tex;       // layer 1 sprite stamp; texture unit 2 (layer_shader_set_texture)

uniform int   u_deco2_kind;         // layer 2 — same contract as layer 1
uniform float u_deco2_size;
uniform float u_deco2_size_var;
uniform float u_deco2_pitch;
uniform float u_deco2_rotation;
uniform float u_deco2_rotation_var;
uniform float u_deco2_jitter;
uniform float u_deco2_outline;
uniform float u_deco2_shade;
uniform int   u_deco2_color_mode;
uniform int   u_deco2_color;
uniform int   u_deco2_color_b;
uniform int   u_deco2_driver;
uniform float u_deco2_driver_scale;
uniform float u_deco2_driver_speed;
uniform sampler2D u_deco2_tex;      // layer 2 sprite stamp; texture unit 3
uniform int   u_color_kind;
uniform int   u_color_a;
uniform int   u_color_b;
uniform int   u_ramp_tokens[8];    // ordered palette token indices for color='ramp'
uniform int   u_ramp_count;        // number of active ramp stops (2..8)
uniform float u_time;
uniform int   u_image_field;       // sprite field source: 0 = pattern (effect_field),
                                   // 1 = the drawn image's own luminance (dither/recolor a real image)
uniform float u_image_pattern_amount; // luminance mode: how much the animated pattern ripples the
                                      // image's field before dither (0 = static, →1 = flowing)

// Active palette. Written once at boot (and on palette switch) by
// effect_write_palette(). Indexed by token; only .rgb is read.
uniform vec4 u_palette[26];

// =============================================================================
// SDF FUNCTIONS — one per shape vType. Unchanged from the engine's default.
// =============================================================================

float sdf_rect(vec2 p, vec2 center, vec2 half_size) {
    vec2 d = abs(p - center) - half_size;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdf_rounded_rect(vec2 p, vec2 center, vec2 half_size, float radius) {
    vec2 d = abs(p - center) - half_size + radius;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

float sdf_circle(vec2 p, vec2 center, float radius) {
    return length(p - center) - radius;
}

float sdf_capsule(vec2 p, vec2 a, vec2 b, float radius) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - radius;
}

float sdf_triangle(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
    vec2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
    vec2 v0 = p - p0, v1 = p - p1, v2 = p - p2;
    vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                     vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                     vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

float sdf_polygon(vec2 p, vec2 v[8], int n) {
    float d = dot(p - v[0], p - v[0]);
    float s = 1.0;
    for (int i = 0, j = n - 1; i < n; j = i, i++) {
        vec2 e = v[j] - v[i];
        vec2 w = p - v[i];
        vec2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
        d = min(d, dot(b, b));
        bvec3 c = bvec3(p.y >= v[i].y, p.y < v[j].y, e.x * w.y > e.y * w.x);
        if (all(c) || all(not(c))) s *= -1.0;
    }
    return s * sqrt(d);
}

// =============================================================================
// PATTERNS — produce a scalar field f ∈ [0, 1] at the fragment's world_pos.
// New patterns: add a function here, add a branch in pattern_field().
// =============================================================================

// Balatro's 3-point smooth pseudo-noise. Three sample points drift over time
// via independent sin/cos sources; their lengths/components are summed and
// normalized to roughly [0, 1]. Anchored to world coordinates, so on
// camera-attached layers the pattern stays stable as the camera moves.
float pattern_organic(vec2 world_pos, float scale, float t) {
    vec2 uv = world_pos * scale;
    vec2 p1 = uv + 50.0 * vec2(sin(-t / 143.634), cos(-t / 99.4324));
    vec2 p2 = uv + 50.0 * vec2(cos(t / 53.1532),  cos(t / 61.4532));
    vec2 p3 = uv + 50.0 * vec2(sin(-t / 87.53218), sin(-t / 49.0));
    return (1.0 + (
        cos(length(p1) / 19.483) +
        sin(length(p2) / 33.155) * cos(p2.y / 15.73) +
        cos(length(p3) / 27.193) * sin(p3.x / 21.92)
    )) / 2.0;
}

// ---- smooth single-octave value noise (shared by several patterns) ----
float value_hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = value_hash(i);
    float b = value_hash(i + vec2(1.0, 0.0));
    float c = value_hash(i + vec2(0.0, 1.0));
    float d = value_hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// === EXPLORATION PATTERNS ===
// All take (world_pos, scale, time) and return a value in [0,1]. Internal
// frequencies are tuned so a scale around 0.3-0.5 shows ~2-3 features across
// a ~340px rect (the "reads like the reference, not static" zoom). Each is
// normalised to spend most of its range mid-band so the dither stays visible
// (no fully-solid-black/white swallowing).

// Each pattern takes a `param` in [0,1] — its one intrinsic knob. The
// default value noted per pattern (set in main.lua's gallery table)
// reproduces the original look; sweeping param explores that pattern's range.

// plasma — sum of sines. param = WARP (default 0): displaces the sample
// before the sines, swirling the blobs.
float pattern_plasma(vec2 wp, float scale, float t, float param) {
    vec2 p = wp * scale;
    p += param * 12.0 * vec2(sin(p.y * 0.05 + t * 0.3), cos(p.x * 0.05 - t * 0.2));
    float v = sin(p.x * 0.14 + t)
            + sin(p.y * 0.13 - t * 0.8)
            + sin((p.x + p.y) * 0.10 + t * 0.6)
            + sin(length(p - vec2(40.0, 30.0)) * 0.12 - t * 1.1);
    return clamp(0.5 + v * 0.125, 0.0, 1.0);
}

// waves — plane-wave interference. param = CROSSHATCH (default 1): weights
// the 2nd/3rd waves. param→0 = single parallel band set; param 1 = full
// 3-way cross-hatch (the original).
float pattern_waves(vec2 wp, float scale, float t, float param) {
    vec2 p = wp * scale;
    float v = sin(dot(p, vec2( 0.12,  0.04)) + t)
            + param * sin(dot(p, vec2(-0.03,  0.13)) - t * 0.7)
            + param * sin(dot(p, vec2( 0.08, -0.09)) + t * 0.5);
    float norm = 1.0 + 2.0 * param;
    return clamp(0.5 + v / (2.0 * norm), 0.0, 1.0);
}

// marble — sine veins perturbed by noise. param = VEIN (default 0.5 → 6.0,
// the original noise influence). Higher = more contorted veins.
float pattern_marble(vec2 wp, float scale, float t, float param) {
    vec2 p = wp * scale;
    float n = value_noise(p * 0.03 + vec2(t * 0.04, 0.0));
    float v = sin(p.x * 0.05 + n * (param * 12.0) + t * 0.5);
    return clamp(0.5 + 0.5 * v, 0.0, 1.0);
}

// sine_grid — egg-carton lattice. param = ASPECT (default 0.5 → square).
// Skews the y frequency relative to x, stretching the cells.
float pattern_sine_grid(vec2 wp, float scale, float t, float param) {
    vec2 p = wp * scale;
    float fy = 0.10 * (0.3 + param * 1.4);
    float v = sin(p.x * 0.10 + t * 0.5) * sin(p.y * fy - t * 0.4);
    return 0.5 + 0.5 * v;
}

// wood — concentric grain perturbed by noise. param = GRAIN (default 0.5 →
// 8.0, the original perturbation). Higher = wavier grain.
float pattern_wood(vec2 wp, float scale, float t, float param) {
    vec2 p = wp * scale;
    float n = value_noise(p * 0.02);
    float rings = sin(length(p) * 0.08 + n * (param * 16.0) - t * 0.5);
    return 0.5 + 0.5 * rings;
}

// truchet — per-cell randomly-oriented arcs connecting into flowing maze /
// circuit curves. param = LINE WIDTH (default 0.3): arc thickness. Animated
// by a slow translation of the whole tiling: the arcs connect continuously
// across cell edges and each cell's orientation is fixed to its integer
// coordinate, so panning the sample point just scrolls the fixed infinite
// maze by — smooth, no popping. SPEED scales the drift rate.
float pattern_truchet(vec2 wp, float scale, float t, float param) {
    vec2 p = wp * scale * 0.025 + vec2(t * 0.05, t * 0.035);  // gradual drift
    vec2 cell = floor(p);
    vec2 f = fract(p);
    if (value_hash(cell) < 0.5) f.x = 1.0 - f.x;   // flip orientation per cell
    float d1 = abs(length(f) - 0.5);               // arc centered at (0,0)
    float d2 = abs(length(f - vec2(1.0, 1.0)) - 0.5);  // arc centered at (1,1)
    float d = min(d1, d2);
    float w = 0.06 + param * 0.4;
    return clamp(1.0 - smoothstep(0.0, w, d), 0.0, 1.0);
}

// contours — nested iso-line bands of a noise field → topographic-map look.
// param = LINES (default 0.35): number of contour bands (3..12). Triangle
// wave of the noise keeps the field continuous at band boundaries.
float pattern_contours(vec2 wp, float scale, float t, float param) {
    vec2 p = wp * scale * 0.02 + vec2(t * 0.02, 0.0);
    float n = value_noise(p);
    float k = 3.0 + param * 9.0;
    return abs(2.0 * fract(n * k) - 1.0);
}

// ---- LOCAL patterns (rect-relative, NOT world-anchored) ----
// Every pattern above samples world_pos, so it's global: anchored to world
// coordinates, camera-stable, and independent of which rect is drawn over it.
// These two instead sample the draw's own 0..1 UV, so the field is locked to
// the rectangle's box — it moves and scales WITH the rect. `quad_px` is the
// quad's pixel size, used to aspect-correct (UV is normalized per-axis and so
// otherwise loses the rect's true proportions). Neither animates; the "how
// fast the gradient goes" / steepness knob is the universal CONTRAST modifier
// (applied for free in effect_field) — contrast 1 = gentle even ramp,
// contrast > 1 = a sharp narrow transition with flat A/B plateaus.

// linear_gradient — A→B ramp across the rect. param = ANGLE (0..1 → 0..2π),
// aspect-corrected so the angle reads as a true screen angle. param2 = OFFSET
// ([-1, 1]): biases the midline (f = 0.5) along the angle — 0 = rect center,
// +1 slides it to the far corner, -1 to the near corner. Normalized so the
// ramp spans the rect corner-to-corner along the angle direction.
float pattern_linear_gradient(vec2 uv, vec2 quad_px, float param, float offset) {
    float ang = param * 6.28318530718;
    vec2 dir = vec2(cos(ang), sin(ang));
    vec2 c = (uv - 0.5) * quad_px;                                  // centered, pixel space
    float proj = dot(c, dir);
    float half_extent = 0.5 * (abs(dir.x) * quad_px.x + abs(dir.y) * quad_px.y);
    return clamp(0.5 + 0.5 * (proj / max(half_extent, 1.0) - offset), 0.0, 1.0);
}

// radial_gradient — center→edge ramp. param = SHAPE: 0 = true circle
// (aspect-corrected, inscribed in the rect's short side), 1 = ellipse fit to
// the rect (reaches the edge midpoints proportionally). param2 = RANGE: scales
// the circle's reach — >1 pushes the transition outward (bigger bright core),
// <1 pulls it in. (RANGE = size of the circle; CONTRAST = sharpness of edge.)
float pattern_radial_gradient(vec2 uv, vec2 quad_px, float param, float range) {
    vec2 c = uv - 0.5;
    float d_ellipse = length(c) * 2.0;                             // circle in UV = ellipse on screen
    float short_half = 0.5 * min(quad_px.x, quad_px.y);
    float d_circle = length(c * quad_px) / max(short_half, 1.0);   // true circle in pixel space
    float d = mix(d_circle, d_ellipse, param);
    return clamp(d / max(range, 0.01), 0.0, 1.0);
}

float pattern_field(int kind, vec2 world_pos, vec2 uv, vec2 quad_px, float scale, float param, float param2, float t) {
    if (kind == 1)  return clamp(pattern_organic(world_pos, scale, t), 0.0, 1.0);
    if (kind == 3)  return pattern_plasma(world_pos, scale, t, param);
    if (kind == 4)  return pattern_waves(world_pos, scale, t, param);
    if (kind == 5)  return pattern_marble(world_pos, scale, t, param);
    if (kind == 6)  return pattern_sine_grid(world_pos, scale, t, param);
    if (kind == 7)  return pattern_wood(world_pos, scale, t, param);
    if (kind == 8)  return pattern_truchet(world_pos, scale, t, param);
    if (kind == 9)  return pattern_contours(world_pos, scale, t, param);
    if (kind == 10) return pattern_linear_gradient(uv, quad_px, param, param2);
    if (kind == 11) return pattern_radial_gradient(uv, quad_px, param, param2);
    // kind == 2 (solid) or unknown → constant midpoint.
    return 0.5;
}

// Compose the active pattern with the universal SPEED + CONTRAST modifiers.
// SPEED scales the animation clock; CONTRAST spreads (>1, punchier toward
// black/white) or compresses (<1, more uniform mid-grey → more dither
// texture visible) the field around its mid-point. Called from both draw
// paths so the SDF and sprite branches stay identical.
// `sample_uv` = the TEXTURE-SAMPLING uv (atlas coords for sprite quads);
// `uv` = the QUAD-LOCAL 0..1 uv the LOCAL patterns map over. Identical for SDF
// draws; they differ only for atlas sprites/glyphs (see the sprite branch).
float field_eval(int driver, float drv_scl, float drv_spd, vec2 world_pos, vec2 sample_uv, vec2 uv, vec2 quad_px) {
    // ONE pattern_field instantiation. The old shape (effect_field + separate
    // driver calls) instantiated the whole 11-pattern dispatch at ~18 call
    // sites once inlining was done, and ANGLE's D3D translation ground on it
    // for a minute on cache-cold loads. Same math, one site.
    int   k   = (driver > 0) ? driver  : u_pattern_kind;
    float scl = (driver > 0) ? drv_scl : u_pattern_scale;
    float p1  = (driver > 0) ? 0.0     : u_pattern_param;
    float p2  = (driver > 0) ? 0.0     : u_pattern_param2;
    float spd = (driver > 0) ? drv_spd : u_pattern_speed;
    float f = pattern_field(k, world_pos, uv, quad_px, scl, p1, p2, u_time * spd);
    if (driver > 0) return f;
    if (u_image_field == 1) {
        float lum = dot(textureLod(u_texture, sample_uv, 0.0).rgb, vec3(0.299, 0.587, 0.114));
        lum = clamp((lum - 0.5) * u_pattern_contrast + 0.5, 0.0, 1.0);
        if (u_image_pattern_amount > 0.0) {
            lum = clamp(lum + (f - 0.5) * u_image_pattern_amount, 0.0, 1.0);
        }
        return lum;
    }
    return clamp((f - 0.5) * u_pattern_contrast + 0.5, 0.0, 1.0);
}

float effect_field(vec2 world_pos, vec2 sample_uv, vec2 uv, vec2 quad_px) {
    return field_eval(0, 0.0, 0.0, world_pos, sample_uv, uv, quad_px);
}

// =============================================================================
// DITHER — quantize the continuous field f to N discrete levels using a
// per-pixel threshold function. apply_dither returns a value in
// {0, 1/(N-1), 2/(N-1), …, 1}. Downstream color='mix' lerps mix(A, B, f)
// by that value:
//   N=2  → hard A or B regions, no intermediate. Strict palette snap.
//   N=4  → A, 1/3-mix, 2/3-mix, B. Soft transitions in 4 bands.
//   N=16 → effectively smooth gradient. Use for soft fades.
//
// Thirty-four modes total. 2-level group (modes 1..3) sits at the top of
// the cycle for the strict-palette default; multi-level groups follow in
// family order (bayer, white noise, cluster dots, line_diag, line_diag_flip,
// scanlines, triangle, hearts). Threshold functions ported verbatim from
// snkrx-template (which inherited them from Surma's ditherpunk catalog +
// Invoker's orb dither). Procedural patterns (line/cluster/triangle/hearts)
// derive their threshold from gl_FragCoord — no const matrices, trivial to
// reparameterize.
// =============================================================================

const float BAYER2[4] = float[4](
    0.0, 2.0,
    3.0, 1.0
);
const float BAYER4[16] = float[16](
     0.0,  8.0,  2.0, 10.0,
    12.0,  4.0, 14.0,  6.0,
     3.0, 11.0,  1.0,  9.0,
    15.0,  7.0, 13.0,  5.0
);
const float BAYER8[64] = float[64](
     0.0, 32.0,  8.0, 40.0,  2.0, 34.0, 10.0, 42.0,
    48.0, 16.0, 56.0, 24.0, 50.0, 18.0, 58.0, 26.0,
    12.0, 44.0,  4.0, 36.0, 14.0, 46.0,  6.0, 38.0,
    60.0, 28.0, 52.0, 20.0, 62.0, 30.0, 54.0, 22.0,
     3.0, 35.0, 11.0, 43.0,  1.0, 33.0,  9.0, 41.0,
    51.0, 19.0, 59.0, 27.0, 49.0, 17.0, 57.0, 25.0,
    15.0, 47.0,  7.0, 39.0, 13.0, 45.0,  5.0, 37.0,
    63.0, 31.0, 55.0, 23.0, 61.0, 29.0, 53.0, 21.0
);

float bayer2(vec2 pix) {
    int x = int(mod(pix.x, 2.0));
    int y = int(mod(pix.y, 2.0));
    return BAYER2[y * 2 + x] / 4.0;
}

float bayer4(vec2 pix) {
    int x = int(mod(pix.x, 4.0));
    int y = int(mod(pix.y, 4.0));
    return BAYER4[y * 4 + x] / 16.0;
}

float bayer8(vec2 pix) {
    int x = int(mod(pix.x, 8.0));
    int y = int(mod(pix.y, 8.0));
    return BAYER8[y * 8 + x] / 64.0;
}

// Pseudo-random hash from pixel coords. Classic GLSL sin-fract trick;
// sufficient for stochastic dither stipple.
float dither_noise(vec2 pix) {
    return fract(sin(dot(pix, vec2(12.9898, 78.233))) * 43758.5453);
}

// Diagonal stripes: threshold ramps along x + y modulo n. Period n.
float dither_line_diag(vec2 pix, float n) {
    return mod(floor(pix.x) + floor(pix.y), n) / n;
}

// Anti-diagonal stripes: threshold ramps along x - y modulo n. GLSL's mod
// handles negative inputs correctly so no offset trick needed.
float dither_line_diag_flip(vec2 pix, float n) {
    return mod(floor(pix.x) - floor(pix.y), n) / n;
}

// Horizontal scanlines, period 2.
float dither_line_horiz(vec2 pix) {
    return mod(floor(pix.y), 2.0) * 0.5;
}

// Vertical scanlines, period 2.
float dither_line_vert(vec2 pix) {
    return mod(floor(pix.x), 2.0) * 0.5;
}

// Cluster-dot (halftone). Threshold = Euclidean distance from cell center,
// normalized so the corner reaches ~1. Low thresholds at center mean a dot
// emerges there as f rises and grows outward toward the corners. Classic
// halftone-printing look.
float dither_cluster_dot(vec2 pix, float n) {
    vec2 p = mod(pix, n) - n * 0.5 + 0.5;
    return clamp(length(p) / (n * 0.5), 0.0, 1.0);
}

// Triangle / diamond pattern. L1 (Manhattan) distance from cell center —
// the "dot" is a diamond rather than a circle.
float dither_triangle(vec2 pix, float n) {
    vec2 p = abs(mod(pix, n) - n * 0.5 + 0.5);
    return clamp((p.x + p.y) / n, 0.0, 1.0);
}

// Hearts. Implicit heart curve (cardioid-inspired): low threshold inside
// the heart shape so a heart emerges as f rises. Tuned for n = 6.
float dither_hearts(vec2 pix, float n) {
    vec2 p = (mod(pix, n) - n * 0.5 + 0.5) / (n * 0.5);
    p.y = -(p.y + 0.15);
    float a = p.x * p.x + p.y * p.y - 0.55;
    float h = a * a * a - p.x * p.x * p.y * p.y * p.y;
    return clamp(h * 0.6 + 0.45, 0.0, 1.0);
}

// Quantize `field` (continuous [0,1]) to `levels` discrete steps using a
// per-pixel `threshold` offset in [0,1]. Output in {0, 1/(L-1), …, 1}.
// Standard ordered-dither math: high-threshold pixels jump to the next
// level earlier (so as field rises, pixels flip on in matrix order).
float dither_quantize(float field, float levels, float threshold) {
    return clamp(floor(field * levels + threshold), 0.0, levels - 1.0) / (levels - 1.0);
}

float apply_dither(float field, int mode, vec2 pix) {
    // 2-level group (strict palette snap; pairs naturally with color='mix').
    if (mode == 1)  return dither_quantize(field,  2.0, bayer4(pix));
    if (mode == 2)  return dither_quantize(field,  2.0, bayer8(pix));
    if (mode == 3)  return dither_quantize(field,  2.0, dither_noise(pix));

    // Bayer ordered-dither, multi-level.
    if (mode == 4)  return dither_quantize(field,  4.0, bayer2(pix));
    if (mode == 5)  return dither_quantize(field,  4.0, bayer4(pix));
    if (mode == 6)  return dither_quantize(field,  8.0, bayer4(pix));
    if (mode == 7)  return dither_quantize(field,  7.0, bayer8(pix));
    if (mode == 8)  return dither_quantize(field,  9.0, bayer8(pix));
    if (mode == 9)  return dither_quantize(field, 16.0, bayer8(pix));

    // White-noise stipple, multi-level.
    if (mode == 10) return dither_quantize(field,  4.0, dither_noise(pix));
    if (mode == 11) return dither_quantize(field,  8.0, dither_noise(pix));

    // Cluster dot / halftone.
    if (mode == 12) return dither_quantize(field,  8.0, dither_cluster_dot(pix, 4.0));
    if (mode == 13) return dither_quantize(field, 12.0, dither_cluster_dot(pix, 6.0));
    if (mode == 14) return dither_quantize(field, 16.0, dither_cluster_dot(pix, 8.0));

    // Diagonal stripes, periods 2..8.
    if (mode == 15) return dither_quantize(field,  2.0, dither_line_diag(pix, 2.0));
    if (mode == 16) return dither_quantize(field,  3.0, dither_line_diag(pix, 3.0));
    if (mode == 17) return dither_quantize(field,  4.0, dither_line_diag(pix, 4.0));
    if (mode == 18) return dither_quantize(field,  5.0, dither_line_diag(pix, 5.0));
    if (mode == 19) return dither_quantize(field,  6.0, dither_line_diag(pix, 6.0));
    if (mode == 20) return dither_quantize(field,  7.0, dither_line_diag(pix, 7.0));
    if (mode == 21) return dither_quantize(field,  8.0, dither_line_diag(pix, 8.0));

    // Anti-diagonal stripes, periods 2..8.
    if (mode == 22) return dither_quantize(field,  2.0, dither_line_diag_flip(pix, 2.0));
    if (mode == 23) return dither_quantize(field,  3.0, dither_line_diag_flip(pix, 3.0));
    if (mode == 24) return dither_quantize(field,  4.0, dither_line_diag_flip(pix, 4.0));
    if (mode == 25) return dither_quantize(field,  5.0, dither_line_diag_flip(pix, 5.0));
    if (mode == 26) return dither_quantize(field,  6.0, dither_line_diag_flip(pix, 6.0));
    if (mode == 27) return dither_quantize(field,  7.0, dither_line_diag_flip(pix, 7.0));
    if (mode == 28) return dither_quantize(field,  8.0, dither_line_diag_flip(pix, 8.0));

    // Scanlines.
    if (mode == 29) return dither_quantize(field,  2.0, dither_line_horiz(pix));
    if (mode == 30) return dither_quantize(field,  2.0, dither_line_vert(pix));

    // Triangle / diamond, sizes 5..7.
    if (mode == 31) return dither_quantize(field,  5.0, dither_triangle(pix, 5.0));
    if (mode == 32) return dither_quantize(field,  6.0, dither_triangle(pix, 6.0));
    if (mode == 33) return dither_quantize(field,  7.0, dither_triangle(pix, 7.0));

    // Hearts (n = 6, the only tuned size).
    if (mode == 34) return dither_quantize(field,  6.0, dither_hearts(pix, 6.0));

    return field;  // off (mode == 0) or unknown
}

// =============================================================================
// DECO — the decoration layer: a screen-anchored cell grid of shapes
// composited OVER the base color (the anime-bg / manga-screentone language).
// The base renders normally (flat, gradient, dithered, whatever); deco never
// masks it away — output = mix(base, deco_color, mask). Deco color defaults
// to a SHADE of the base (tone-on-tone: slightly darker outlines / dots);
// color mode 1 uses an explicit palette token instead.
//
// Per-cell variation: shape SIZE is modulated by a DRIVER field sampled once
// at the (jittered) cell center — either the draw's main pattern (driver 0;
// includes image luminance when u_image_field is set, so deco dots can
// halftone a real image) or an independent pattern with its own scale/speed
// (gradient bg + plasma-driven dots). Per-cell hashes add position jitter and
// rotation wobble so the grid can stop reading as a grid. Runs on every draw
// with u_deco_kind > 0 — INDEPENDENT of the color recipe (a flat vColor rect
// takes deco too).
// =============================================================================

// Normalized gauge metric for the deco shapes: 0 at the shape center, 1 at
// the boundary. q = cell-local offset / (shape half-size), already rotated.
float deco_gauge(int kind, vec2 q) {
    vec2 a = abs(q);
    if (kind == 2) return max(a.x, a.y);                                    // square (Chebyshev)
    if (kind == 3) return a.x + a.y;                                        // diamond (Manhattan)
    if (kind == 4) return max(a.x, dot(a, vec2(0.5, 0.866025))) / 0.866025; // hexagon (gauge)
    if (kind == 5) {                                                        // cross / plus
        float w = 0.42;
        float d = min(max(a.x - 1.0, a.y - w), max(a.y - 1.0, a.x - w));    // box union, d<0 inside
        return 1.0 + d;                                                     // boundary at 1
    }
    if (kind == 6) return max(-q.y, 0.866025 * a.x + 0.5 * q.y) * 2.0;      // triangle (upward, gauge)
    return length(q);                                                       // circle
}

// Composite one deco layer over `base`. idx (a call-site literal, 1 or 2)
// selects which uniform block to read. Derivative calls sit under uniform
// control flow (the kind test only). sample_uv / uv / quad_px as in
// effect_field — needed to reconstruct the field at the cell center.
vec3 apply_deco_layer(int idx, vec3 base, vec2 sample_uv, vec2 uv, vec2 quad_px) {
    int kind = (idx == 1) ? u_deco_kind : u_deco2_kind;
    if (kind == 0) return base;
    float pitch    = max((idx == 1) ? u_deco_pitch : u_deco2_pitch, 2.0);
    float dsize    = (idx == 1) ? u_deco_size          : u_deco2_size;
    float size_var = (idx == 1) ? u_deco_size_var      : u_deco2_size_var;
    float rot      = (idx == 1) ? u_deco_rotation      : u_deco2_rotation;
    float rot_var  = (idx == 1) ? u_deco_rotation_var  : u_deco2_rotation_var;
    float jitter   = (idx == 1) ? u_deco_jitter        : u_deco2_jitter;
    float outl     = (idx == 1) ? u_deco_outline       : u_deco2_outline;
    float shade    = (idx == 1) ? u_deco_shade         : u_deco2_shade;
    int   cmode    = (idx == 1) ? u_deco_color_mode    : u_deco2_color_mode;
    int   tok_a    = (idx == 1) ? u_deco_color         : u_deco2_color;
    int   tok_b    = (idx == 1) ? u_deco_color_b       : u_deco2_color_b;
    int   driver   = (idx == 1) ? u_deco_driver        : u_deco2_driver;
    float drv_scl  = (idx == 1) ? u_deco_driver_scale  : u_deco2_driver_scale;
    float drv_spd  = (idx == 1) ? u_deco_driver_speed  : u_deco2_driver_speed;

    vec2 cell = floor(gl_FragCoord.xy / pitch);
    // Per-cell hashes: jitter offset (h1, h2) + rotation wobble (h3). Layer 2
    // hashes from an offset lattice so the two layers never correlate.
    vec2 hoff = (idx == 1) ? vec2(0.0) : vec2(101.0, 57.0);
    float h1 = value_hash(cell + hoff + 17.0);
    float h2 = value_hash(cell + hoff + 43.0);
    float h3 = value_hash(cell + hoff + 71.0);
    vec2 cc = (cell + 0.5) * pitch + (vec2(h1, h2) - 0.5) * jitter * pitch;

    // Driver field at the cell center (world/uv reconstructed from screen-
    // space derivatives — exact for the 2D affine camera).
    vec2 dpx  = cc - gl_FragCoord.xy;
    vec2 wc   = vPos + dFdx(vPos) * dpx.x + dFdy(vPos) * dpx.y;
    vec2 suvc = sample_uv + dFdx(sample_uv) * dpx.x + dFdy(sample_uv) * dpx.y;
    vec2 uvc  = uv + dFdx(uv) * dpx.x + dFdy(uv) * dpx.y;
    float g = field_eval(driver, drv_scl, drv_spd, wc, suvc, uvc, quad_px);

    float size_px = dsize * mix(1.0, g, size_var);
    if (size_px < 0.5) return base;

    // Cell-local coords, rotated (shared rotation + per-cell wobble).
    float rang = (rot + (h3 - 0.5) * rot_var) * 6.28318530718;
    float rcs = cos(rang), rsn = sin(rang);
    vec2 q = mat2(rcs, -rsn, rsn, rcs) * (gl_FragCoord.xy - cc);
    float s = size_px * 0.5;

    float mask;
    float m;   // gauge metric (0 center → 1 boundary); also the 'inside' mix t
    if (kind == 7) {
        // sprite stamp: the icon's alpha, fitted to the shape box. Y flipped
        // (gl_FragCoord is bottom-up, texture origin top-left).
        m = length(q) / max(s, 0.001);
        vec2 tuv = vec2(0.5 + q.x / size_px, 0.5 - q.y / size_px);
        if (tuv.x < 0.0 || tuv.x > 1.0 || tuv.y < 0.0 || tuv.y > 1.0) {
            mask = 0.0;
        } else {
            mask = (idx == 1) ? textureLod(u_deco_tex,  tuv, 0.0).a
                              : textureLod(u_deco2_tex, tuv, 0.0).a;
        }
    } else {
        m = deco_gauge(kind, q / s);
        if (u_aa_width > 0.0) {
            // Smooth mode: ~1px anti-aliased edges.
            float e = 1.0 / max(s, 1.0);   // metric units
            if (outl > 0.0) {
                float hw = (outl * 0.5) / s;   // half band width, metric units
                mask = 1.0 - smoothstep(hw - e, hw + e, abs(m - 1.0));
            } else {
                mask = 1.0 - smoothstep(1.0 - e, 1.0 + e, m);
            }
        } else {
            // Rough mode: hard pixel edges, matching the engine's SDF draws
            // (u_aa_width == 0 is the 'rough' filter signal).
            if (outl > 0.0) {
                float hw = (outl * 0.5) / s;
                mask = 1.0 - step(hw, abs(m - 1.0));
            } else {
                mask = 1.0 - step(1.0, m);
            }
        }
    }
    if (mask <= 0.0) return base;

    vec3 dcol;
    if (cmode == 1) {
        dcol = u_palette[tok_a].rgb;
    } else if (cmode == 2) {
        // across: one color per shape, the driver field at the cell.
        dcol = mix(u_palette[tok_a].rgb, u_palette[tok_b].rgb, clamp(g, 0.0, 1.0));
    } else if (cmode == 3) {
        // inside: center→edge gradient self-contained within every shape.
        dcol = mix(u_palette[tok_a].rgb, u_palette[tok_b].rgb, clamp(m, 0.0, 1.0));
    } else if (cmode == 4) {
        // flow: the driver field at the FRAGMENT — shapes as windows onto
        // one continuous gradient.
        float gf = field_eval(driver, drv_scl, drv_spd, vPos, sample_uv, uv, quad_px);
        dcol = mix(u_palette[tok_a].rgb, u_palette[tok_b].rgb, clamp(gf, 0.0, 1.0));
    } else {
        dcol = clamp(base * (1.0 + shade), 0.0, 1.0);   // shade-of-base
    }
    return mix(base, dcol, mask);
}

// Both layers in order — layer 2 composites over layer 1's result.
vec3 apply_deco(vec3 base, vec2 sample_uv, vec2 uv, vec2 quad_px) {
    vec3 c = apply_deco_layer(1, base, sample_uv, uv, quad_px);
    return apply_deco_layer(2, c, sample_uv, uv, quad_px);
}

// =============================================================================
// COLOR — recipe over (base_rgb, f, palette[color_a], palette[color_b]).
// =============================================================================

// ramp: map f across an ordered list of palette tokens (u_ramp_tokens, count
// u_ramp_count), linearly interpolating between adjacent stops. Generalizes
// `mix` from 2 tokens to N — "polychrome", kept on the Ricochet palette.
// f drives WHERE along the ramp we land; the pattern axis decides what f is, so
// an animated pattern sweeps the ramp over time and a gradient pattern sweeps
// it across space — the color recipe itself stays a pure function of f.
vec3 color_ramp(float f) {
    int n = u_ramp_count;
    if (n <= 1) return u_palette[u_ramp_tokens[0]].rgb;
    float x = clamp(f, 0.0, 1.0) * float(n - 1);   // [0, n-1]
    int i = clamp(int(floor(x)), 0, n - 2);
    int ia = u_ramp_tokens[i];
    int ib = u_ramp_tokens[i + 1];
    return mix(u_palette[ia].rgb, u_palette[ib].rgb, x - float(i));
}

vec3 apply_color(int kind, vec3 base, float f, vec3 ca, vec3 cb) {
    if (kind == 1) return ca;                // solid: ignores base, ignores f
    if (kind == 2) return mix(ca, cb, f);    // mix: f drives the A↔B blend
    if (kind == 3) return color_ramp(f);     // ramp: f across N palette tokens
    return base;                              // none: passthrough
}

// =============================================================================
// MAIN — dispatch by vType, compute alpha from SDF (or sample texture for
// sprites), apply effect, output.
// =============================================================================

void main() {
    float d;
    float stroke = 0.0;
    vec2 quad_px = vec2(1.0);   // quad pixel size, for local (rect-relative) patterns

    // shared-tail inputs (set by the sprite branch directly; by the shape
    // post-processing below for every SDF type)
    vec3 s_col = vec3(0.0); vec2 s_suv = vUV; vec2 s_uv = vUV; vec2 s_qpx = vec2(1.0);
    float s_alpha = 1.0; float alpha = 1.0; bool is_shape = true;

    if (vType < 0.5) {
        // Rectangle
        vec2 quad_size = vShape0.xy;
        quad_px = quad_size;
        vec2 local_p = vUV * quad_size;
        vec2 center = quad_size * 0.5;
        vec2 half_size = vShape0.zw;
        stroke = vShape1.x;
        if (u_aa_width == 0.0) { local_p = floor(local_p) + 0.5; }
        d = sdf_rect(local_p, center, half_size);
    } else if (vType < 1.5) {
        // Circle
        float quad_size = vShape0.x;
        quad_px = vec2(quad_size);
        vec2 local_p = vUV * quad_size;
        vec2 center = vec2(quad_size * 0.5);
        float radius = vShape0.z;
        stroke = vShape0.w;
        if (u_aa_width == 0.0) { radius = floor(radius + 0.5); }
        d = sdf_circle(local_p, center, radius);
    } else if (vType < 2.5) {
        // Sprite
        ivec2 texSize = textureSize(u_texture, 0);
        vec2 snappedUV = (floor(vUV * vec2(texSize)) + 0.5) / vec2(texSize);
        vec4 texColor = texture(u_texture, snappedUV);
        float sprite_alpha = texColor.a * vColor.a;
        if (sprite_alpha <= 0.0) discard;
        vec3 col = texColor.rgb * vColor.rgb + vAddColor;
        // Quad-local uv for the LOCAL patterns: glyph / spritesheet quads
        // carry their atlas sub-rect in vShape0 = (u0, v0, u1, v1) (engine
        // batch_add_uv_quad*); remap vUV into it so a gradient spans THIS
        // quad, not the whole atlas. Zeroed vShape0 (full-texture sprites,
        // older engine builds) falls back to the old whole-texture mapping.
        // Hoisted out of the color branch — apply_deco needs it too.
        vec2 quad_uv = vUV;
        vec2 spr_quad_px = vec2(texSize);
        vec2 uv0 = vShape0.xy, uv1 = vShape0.zw;
        if (uv1.x > uv0.x && uv1.y > uv0.y) {
            quad_uv = (vUV - uv0) / (uv1 - uv0);
            spr_quad_px = (uv1 - uv0) * vec2(texSize);
        }
        // fall through to the ONE shared field/dither/color/deco tail below —
        // a second inlined copy of that tail used to double the whole
        // shader's compile cost
        s_col = col; s_suv = vUV; s_uv = quad_uv; s_qpx = spr_quad_px; s_alpha = sprite_alpha;
        is_shape = false;
    } else if (vType < 3.5) {
        // Line / capsule
        vec2 quad_size = vShape0.xy;
        quad_px = quad_size;
        vec2 local_p = vUV * quad_size;
        vec2 center = quad_size * 0.5;
        float half_len = vShape0.z;
        float radius = vShape0.w;
        stroke = vShape1.x;
        vec2 a = center - vec2(half_len, 0.0);
        vec2 b = center + vec2(half_len, 0.0);
        d = sdf_capsule(local_p, a, b, radius);
    } else if (vType < 4.5) {
        // Triangle
        vec2 quad_size = vShape0.xy;
        quad_px = quad_size;
        vec2 local_p = vUV * quad_size;
        stroke = vShape0.z;
        vec2 v0 = vShape1.xy;
        vec2 v1 = vShape1.zw;
        vec2 v2 = vShape2.xy;
        d = sdf_triangle(local_p, v0, v1, v2);
    } else if (vType < 5.5) {
        // Polygon (up to 8 vertices)
        int n = int(vShape0.x);
        stroke = vShape0.y;
        vec2 quad_size = vShape0.zw;
        quad_px = quad_size;
        vec2 local_p = vUV * quad_size;
        vec2 v[8];
        v[0] = vShape1.xy; v[1] = vShape1.zw;
        v[2] = vShape2.xy; v[3] = vShape2.zw;
        v[4] = vShape3.xy; v[5] = vShape3.zw;
        v[6] = vShape4.xy; v[7] = vShape4.zw;
        d = sdf_polygon(local_p, v, n);
    } else if (vType < 6.5) {
        // Rounded rectangle
        vec2 quad_size = vShape0.xy;
        quad_px = quad_size;
        vec2 local_p = vUV * quad_size;
        vec2 center = quad_size * 0.5;
        vec2 half_size = vShape0.zw;
        float radius = vShape1.x;
        stroke = vShape1.y;
        d = sdf_rounded_rect(local_p, center, half_size, radius);
    } else {
        discard;
    }

    if (is_shape) {
        if (stroke > 0.0) {
            d = abs(d) - stroke * 0.5;
        }
        if (u_aa_width > 0.0) {
            alpha = 1.0 - smoothstep(-u_aa_width, u_aa_width, d);
        } else {
            alpha = 1.0 - step(0.0, d);
        }
        if (alpha <= 0.0) discard;
        s_col = vColor.rgb + vAddColor;
        s_suv = vUV; s_uv = vUV; s_qpx = quad_px;
        s_alpha = vColor.a * alpha;
    }

    // THE shared tail (single inlined instance of field/dither/color/deco).
    // Field computed under the uniform `u_color_kind` test (NOT the per-fragment
    // `alpha` test) so effect_field's callers' dFdx/dFdy stay in uniform
    // control flow.
    vec3 col = s_col;
    if (u_color_kind > 0) {
        float f  = effect_field(vPos, s_suv, s_uv, s_qpx);
        float fd = apply_dither(f, u_dither_kind, gl_FragCoord.xy);
        vec3 ccol = apply_color(u_color_kind, col, fd, u_palette[u_color_a].rgb, u_palette[u_color_b].rgb);
        if (alpha > 0.01) col = ccol;
    }
    // Deco composites over the base — INDEPENDENT of the color recipe, so a
    // flat vColor rect takes deco too (the decorated-background case).
    col = apply_deco(col, s_suv, s_uv, s_qpx);

    FragColor = vec4(col * ((u_value_mult > 0.0) ? u_value_mult : 1.0), s_alpha);
}
