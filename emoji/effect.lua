--[[
  effect.lua — four-axis visual effect system (pattern × color × dither × deco).

  ⭐ USAGE GUIDE: .claude/CLAUDE.md "Effect system — COOKBOOK" — mental
  model, field routing, knobs-by-intent table, paste-ready recipes, the
  F5→DUMP workflow. Read it before picking knobs for a requested look.

  THE 30-SECOND MENTAL MODEL
    Every draw routes through assets/draw_shader.frag. The shader composes:

        f    = pattern(world_pos, time)       -- spatial structure + animation
                                              -- (or, for an image, its luminance)
        f    = dither(f, pixel_pos)           -- quantize to discrete levels
        base = color(base_rgb, f, palette)    -- map f → palette token(s)
        rgb  = deco(base, pixel_pos)          -- DECORATION layer composited OVER
                                              -- the base (never masks it away)

    Pattern owns "what the field looks like" AND "whether it moves over time."
    Color is a pure recipe that picks (or mixes) palette tokens by f. Dither
    inserts the pixel-art stipple. DECO stamps a cell grid of shapes over the
    finished base — tone-on-tone outlines, manga screentone dots — with size /
    rotation / position varied per cell by a driver field (the main pattern,
    or an independent one). All four are independent.

  PUBLIC API
    effect_setup(opts)                       install draw shader, cache its
                                             GL program ID, push the palette
    effect_set(layer, spec)                  write effect uniforms for this
                                             layer's subsequent draws
    effect_clear(layer)                      pattern/color/dither/deco → passthrough
    effect_draw(layer, spec, fn, ...)        scoped form (set, run fn, clear)
    -- SINGLE-CALL WRAPPERS (set + draw + clear in one; PREFER these):
    effect_rectangle(layer, x, y, w, h, spec)
    effect_circle(layer, x, y, r, spec)
    effect_image(layer, img, x, y, w, h, spec)  -- fits img into the box; also the
                                             -- image-as-content path (spec.image_field)
    effect_write_palette()                   re-push u_palette to the shader
                                             (called automatically by palette_init
                                             and effect_setup)

    Cycle helpers (return the NEXT/PREV name in each axis's cycle):
      effect_next_pattern(cur), effect_prev_pattern(cur)
      effect_next_color(cur),   effect_prev_color(cur)
      effect_next_dither(cur),  effect_prev_dither(cur)
      effect_next_deco(cur),    effect_prev_deco(cur)
      effect_next_deco_driver(cur), effect_prev_deco_driver(cur)
      effect_next_token(cur),   effect_prev_token(cur)

  SPEC TABLE
    Every field is optional; defaults shown.
      pattern        'solid'     -- 'organic' | 'solid'
      color          'none'      -- 'none' | 'solid' | 'mix' | 'ramp'
      dither         'off'       -- see DITHER list below
      color_a        'white'     -- palette token name (string)
      color_b        'fg'        -- palette token name (string), used by mix
      ramp           effect_ramp -- ordered token-name list, used by color='ramp'
      -- DECO — TWO decoration layers (shapes composited OVER the base;
      -- layer 2 over layer 1's result). Layer 1 = 'deco' prefix, layer 2 =
      -- 'deco2' (same fields: deco2, deco2_size, ...):
      deco             'none'    -- 'none'|'circle'|'square'|'diamond'|'hexagon'|'cross'|'triangle'|'sprite'
      deco_size        10        -- base shape size, px
      deco_size_var    0         -- 0..1 — driver field's grip on size (1 = fully driven)
      deco_pitch       22        -- cell spacing, px
      deco_rotation    0         -- shared rotation, 0..1 = a full turn
      deco_rotation_var 0        -- 0..1 — per-cell hashed rotation wobble
      deco_jitter      0         -- 0..1 — per-cell position jitter (breaks the grid)
      deco_outline     0         -- 0 = filled; >0 = outline band width px (hollow shapes)
      deco_color_mode  nil       -- 'shade' (tone-on-tone, default) | 'solid' |
                                 -- 'across' (one color per shape, field at cell) |
                                 -- 'inside' (center→edge gradient within each shape) |
                                 -- 'flow' (field at fragment — shapes as windows).
                                 -- nil resolves: deco_color set → solid, else shade
      deco_shade       -0.12     -- shade mode: deco color = base * (1 + shade)
      deco_color       nil       -- token A (solid / across / inside / flow)
      deco_color_b     'fg'      -- token B (across / inside / flow)
      deco_driver      nil       -- pattern name driving the variation; nil = main pattern
      deco_driver_scale 0.3      -- driver field density
      deco_driver_speed 1        -- driver animation rate
      deco_icon        nil       -- sprite deco: the stamp image
      pattern_scale  0.15        -- pattern field density (world units * scale)
      pattern_param  0           -- pattern-specific knob (unused by organic/solid)
      pattern_param2 0           -- 2nd pattern-specific knob (gradient OFFSET / RANGE)
      image_field    false       -- sprite draws: true = field from image luminance
      image_pattern_amount 0      -- luminance mode: ripple the field with the moving pattern

  AXIS CONTENTS
    Pattern:
      organic  Balatro 3-point smooth noise, time-varying. Breathing look.
      solid    f = 0.5. Time-invariant. The degenerate pattern — pair with
               color='mix' for a flat 50/50 dither texture.
      plasma / waves / marble / sine_grid / wood / truchet / contours
               world-anchored gallery patterns; each has an intrinsic param.
      linear_gradient / radial_gradient
               LOCAL: sampled from the draw's own UV, so the field is locked
               to the rect's box. param = ANGLE / SHAPE; CONTRAST = steepness;
               scale + speed inert.
    Color:
      none     base vColor passthrough (no token mapping). For raw draws
               that should NOT be re-colored by the pipeline.
      solid    use palette[color_a]. Ignores base color, ignores f.
      mix      mix(palette[color_a], palette[color_b], f). Combined with a
               2-level dither this becomes per-pixel A-or-B with no blending;
               with a multi-level dither it becomes N-step palette interp.
      ramp     f mapped across the ordered `ramp` token list (generalizes mix
               to N tokens). "Polychrome", kept on-palette. The pattern decides
               f, so an animated pattern sweeps the ramp in time and a gradient
               pattern sweeps it across space; the recipe stays pure in f.
    Dither (34 modes; see dither_pretty_names for HUD labels):
      off                                          passthrough
      bayer4_2, bayer8_2, noise_2                  2-level (strict palette snap)
      bayer2_4, bayer4_4, bayer4_8, bayer8_7,      Bayer ordered dither,
        bayer8_9, bayer8_16                          multi-level
      noise_4, noise_8                             white-noise stipple, multi-level
      cluster_4, cluster_6, cluster_8              halftone cluster dots
      line_diag_2 … line_diag_8                    diagonal stripes
      line_diag_flip_2 … line_diag_flip_8          anti-diagonal stripes
      line_horiz, line_vert                        scanlines
      triangle_5, triangle_6, triangle_7           triangle/diamond
      hearts_6                                     heart-shape stipple

    The level count baked into each multi-level dither's name controls how
    smoothly mix(A, B, f) transitions. n=2 = hard A/B; n=16 = effectively
    smooth gradient. Pick by intended use:
      - hard ink-on-paper stipple   →  2-level group
      - 4-band/8-band soft transition →  bayer4_4/bayer4_8 etc
      - smooth fade                  →  bayer8_16

  GOTCHAS
    - effect_set writes uniforms into the layer's command queue. They affect
      every subsequent draw on this layer until rewritten. Use effect_clear
      after a bracketed set to keep other draws clean.
    - Different layers have independent effect state.
    - Shimmer is anchored to WORLD coords (uses vPos in the shader), so it
      stays stable as the camera moves on camera-attached layers.
]]

-- =============================================================================
-- AXIS REGISTRIES
-- The integer values are what the shader's `u_*_kind` uniforms expect.
-- Keep these tables in lockstep with the if-ladders in assets/draw_shader.frag.
-- =============================================================================

pattern_kinds = {
  organic         = 1,
  solid           = 2,
  plasma          = 3,
  waves           = 4,
  marble          = 5,
  sine_grid       = 6,
  wood            = 7,
  truchet         = 8,
  contours        = 9,
  -- LOCAL patterns: sample the draw's own 0..1 UV instead of world position,
  -- so the field is locked to the rectangle's box (moves/scales WITH the rect).
  -- param = ANGLE (linear) / SHAPE (radial); CONTRAST acts as steepness;
  -- SCALE + SPEED are inert for these two.
  linear_gradient = 10,
  radial_gradient = 11,
}

color_kinds = {
  none  = 0,
  solid = 1,
  mix   = 2,
  ramp  = 3,
}

-- Ordered palette tokens for color='ramp' — the on-palette "polychrome". f maps
-- across this list, linearly interpolating between adjacent stops. Reorder /
-- edit freely; max 8 stops. Default: the accent spectrum (red→…→pink).
effect_ramp = { 'red', 'orange', 'yellow', 'green', 'blue', 'pink' }

-- DECO: the decoration layer — a screen-anchored cell grid of shapes
-- composited OVER the base color (never masking it away). The anime-bg /
-- manga-screentone language: tone-on-tone outlined shapes, dots of varying
-- size adding noise to a flat or gradient image. Shape size varies with a
-- DRIVER field sampled per cell (the draw's main pattern by default, or an
-- independent pattern via deco_driver); per-cell hashes add jitter +
-- rotation wobble. See apply_deco()/deco_gauge() in the shader.
deco_kinds = {
  none     = 0,
  circle   = 1,
  square   = 2,
  diamond  = 3,
  hexagon  = 4,
  cross    = 5,
  triangle = 6,
  -- sprite: each cell stamped with a chosen icon's alpha (deco_icon binds it
  -- to unit 2). Tiny tone-on-tone stars/sparkles tiling a bg, etc.
  sprite   = 7,
}

-- 34 modes total (plus off). Integer ids must match the if-ladder in
-- assets/draw_shader.frag's apply_dither(). 2-level group at the top
-- (modes 1..3) for strict palette snap; multi-level groups follow in
-- family order (bayer, white-noise, cluster, line_diag, line_diag_flip,
-- scanlines, triangle, hearts).
dither_kinds = {
  off              = 0,
  -- 2-level (strict palette snap; pair with color='mix' for hard A/B)
  bayer4_2         = 1,
  bayer8_2         = 2,
  noise_2          = 3,
  -- Bayer ordered dither, multi-level
  bayer2_4         = 4,
  bayer4_4         = 5,
  bayer4_8         = 6,
  bayer8_7         = 7,
  bayer8_9         = 8,
  bayer8_16        = 9,
  -- White-noise stipple, multi-level
  noise_4          = 10,
  noise_8          = 11,
  -- Cluster dot / halftone
  cluster_4        = 12,
  cluster_6        = 13,
  cluster_8        = 14,
  -- Diagonal stripes
  line_diag_2      = 15,
  line_diag_3      = 16,
  line_diag_4      = 17,
  line_diag_5      = 18,
  line_diag_6      = 19,
  line_diag_7      = 20,
  line_diag_8      = 21,
  -- Anti-diagonal stripes
  line_diag_flip_2 = 22,
  line_diag_flip_3 = 23,
  line_diag_flip_4 = 24,
  line_diag_flip_5 = 25,
  line_diag_flip_6 = 26,
  line_diag_flip_7 = 27,
  line_diag_flip_8 = 28,
  -- Scanlines
  line_horiz       = 29,
  line_vert        = 30,
  -- Triangle / diamond
  triangle_5       = 31,
  triangle_6       = 32,
  triangle_7       = 33,
  -- Hearts (n=6 is the only tuned size)
  hearts_6         = 34,
}

-- Cycle order — drives effect_next_*/prev_*. Ordering chosen so each axis
-- starts from passthrough and progresses to more "active" options, but the
-- exact sequence is editorial; rearrange if a different order reads better
-- in the test scene.
pattern_cycle_names = {
  'organic', 'solid', 'plasma', 'waves', 'marble', 'sine_grid', 'wood',
  'truchet', 'contours', 'linear_gradient', 'radial_gradient',
}
color_cycle_names   = { 'none', 'solid', 'mix', 'ramp' }
deco_cycle_names    = {
  'none', 'circle', 'square', 'diamond', 'triangle', 'hexagon', 'cross',
  'sprite',
}

-- Human-readable deco labels for the DECO cycler field.
deco_pretty_names = {
  none     = 'off',
  circle   = 'circle',
  square   = 'square',
  diamond  = 'diamond',
  triangle = 'triangle',
  hexagon  = 'hexagon',
  cross    = 'cross',
  sprite   = 'icon',
}

-- Driver cycle for the deco DRIVER field: 'main' = the draw's own pattern
-- (deco_driver = nil), else an independent pattern with its own scale/speed.
deco_driver_cycle_names = {
  'main', 'organic', 'plasma', 'waves', 'marble', 'sine_grid', 'wood',
  'truchet', 'contours', 'linear_gradient', 'radial_gradient',
}

-- Dither cycle order matches the integer id order in dither_kinds (and the
-- if-ladder in the shader). 2-level group first, then multi-level families.
dither_cycle_names = {
  'off',
  -- 2-level
  'bayer4_2', 'bayer8_2', 'noise_2',
  -- Bayer multi-level
  'bayer2_4', 'bayer4_4', 'bayer4_8', 'bayer8_7', 'bayer8_9', 'bayer8_16',
  -- White-noise multi-level
  'noise_4', 'noise_8',
  -- Cluster dots
  'cluster_4', 'cluster_6', 'cluster_8',
  -- Diagonal stripes
  'line_diag_2', 'line_diag_3', 'line_diag_4', 'line_diag_5',
  'line_diag_6', 'line_diag_7', 'line_diag_8',
  -- Anti-diagonal stripes
  'line_diag_flip_2', 'line_diag_flip_3', 'line_diag_flip_4', 'line_diag_flip_5',
  'line_diag_flip_6', 'line_diag_flip_7', 'line_diag_flip_8',
  -- Scanlines
  'line_horiz', 'line_vert',
  -- Triangle / diamond
  'triangle_5', 'triangle_6', 'triangle_7',
  -- Hearts
  'hearts_6',
}

-- Human-readable names (for HUD). Pattern/color slugs are already readable;
-- dither labels are spelled out a bit so the HUD reads more like the snkrx
-- catalog ("bayer 4x4 / 4 lvl" rather than "bayer4_4").
dither_pretty_names = {
  off              = 'off',
  bayer4_2         = 'bayer 4x4 / 2 lvl',
  bayer8_2         = 'bayer 8x8 / 2 lvl',
  noise_2          = 'noise / 2 lvl',
  bayer2_4         = 'bayer 2x2 / 4 lvl',
  bayer4_4         = 'bayer 4x4 / 4 lvl',
  bayer4_8         = 'bayer 4x4 / 8 lvl',
  bayer8_7         = 'bayer 8x8 / 7 lvl',
  bayer8_9         = 'bayer 8x8 / 9 lvl',
  bayer8_16        = 'bayer 8x8 / 16 lvl',
  noise_4          = 'noise / 4 lvl',
  noise_8          = 'noise / 8 lvl',
  cluster_4        = 'cluster dot 4x4',
  cluster_6        = 'cluster dot 6x6',
  cluster_8        = 'cluster dot 8x8',
  line_diag_2      = 'line diag 2x2',
  line_diag_3      = 'line diag 3x3',
  line_diag_4      = 'line diag 4x4',
  line_diag_5      = 'line diag 5x5',
  line_diag_6      = 'line diag 6x6',
  line_diag_7      = 'line diag 7x7',
  line_diag_8      = 'line diag 8x8',
  line_diag_flip_2 = 'line diag flip 2x2',
  line_diag_flip_3 = 'line diag flip 3x3',
  line_diag_flip_4 = 'line diag flip 4x4',
  line_diag_flip_5 = 'line diag flip 5x5',
  line_diag_flip_6 = 'line diag flip 6x6',
  line_diag_flip_7 = 'line diag flip 7x7',
  line_diag_flip_8 = 'line diag flip 8x8',
  line_horiz       = 'line horizontal',
  line_vert        = 'line vertical',
  triangle_5       = 'triangle 5x5',
  triangle_6       = 'triangle 6x6',
  triangle_7       = 'triangle 7x7',
  hearts_6         = 'hearts 6x6',
}

effect_draw_shader = nil

-- Used by effect_set when spec.pattern_scale is omitted. 0.15 matches the
-- Balatro / Invoker / SNKRX default: slow, broad organic noise good for
-- large surfaces. Bump higher (0.3..1.0) for dense per-entity shimmer.
effect_default_pattern_scale = 0.15

--[[
  effect_setup(opts)
  Install the custom draw shader and cache its GL program ID. Call ONCE at
  boot, AFTER palette_init('dark' | 'light') so the palette is ready to push.

  opts.draw_shader   path to the fragment shader file
                     (default 'assets/draw_shader.frag').

  Side effects:
    - Replaces the engine's default draw shader with the loaded file.
    - Sets `effect_draw_shader` (global) to the GL program ID.
    - Calls effect_write_palette() to push the active palette to u_palette.
]]
function effect_setup(opts)
  opts = opts or {}
  local path = opts.draw_shader or 'assets/draw_shader.frag'
  set_draw_shader(path)
  effect_draw_shader = get_draw_shader()
  effect_write_palette()
end

--[[
  effect_write_palette()
  Push the active palette to the shader's u_palette[] uniform array. Each
  token's RGB is written as a vec4 (alpha is unused — the shader reads .rgb).
  Called automatically by effect_setup() AND by palette_init() — but the
  latter is a no-op until the shader exists. Safe to call manually after
  switching palettes (palette_init does that).

  No-op if effect_setup hasn't run yet (shader not loaded) or palette_init
  hasn't run yet (no active palette).
]]
function effect_write_palette()
  if not effect_draw_shader then return end
  if not palette then return end
  for i, name in ipairs(palette_token_names) do
    local c = palette[name]
    shader_set_vec4_immediate(effect_draw_shader, 'u_palette[' .. (i - 1) .. ']',
                              c.r / 255, c.g / 255, c.b / 255, 1.0)
  end
end

local function resolve_color(name)
  return palette_token_index[name] or 0
end

-- Deco color modes → shader ints. A nil mode resolves for back-compat:
-- deco_color set → 'solid', otherwise 'shade'.
local deco_color_modes = { shade = 0, solid = 1, across = 2, inside = 3, flow = 4 }

--[[
  effect_write_deco(layer, spec, key, uni, unit)
  Write one deco layer's uniform block. `key` is the spec prefix — the kind
  lives at spec[key] ('deco' / 'deco2'), the knobs at spec[key .. '_size']
  etc. `uni` is the uniform prefix ('u_deco_' / 'u_deco2_'); `unit` is the
  sprite stamp's texture unit (2 / 3). Kind 0 writes only the kind (the
  shader early-outs on it; stale knob values are inert).
]]
function effect_write_deco(layer, spec, key, uni, unit)
  local kind = deco_kinds[spec[key] or 'none'] or 0
  layer_shader_set_int(layer, effect_draw_shader, uni .. 'kind', kind)
  if kind == 0 then return end
  local function v(name) return spec[key .. '_' .. name] end
  layer_shader_set_float(layer, effect_draw_shader, uni .. 'size',         v('size') or 10)
  layer_shader_set_float(layer, effect_draw_shader, uni .. 'size_var',     v('size_var') or 0)
  layer_shader_set_float(layer, effect_draw_shader, uni .. 'pitch',        v('pitch') or 22)
  layer_shader_set_float(layer, effect_draw_shader, uni .. 'rotation',     v('rotation') or 0)
  layer_shader_set_float(layer, effect_draw_shader, uni .. 'rotation_var', v('rotation_var') or 0)
  layer_shader_set_float(layer, effect_draw_shader, uni .. 'jitter',       v('jitter') or 0)
  layer_shader_set_float(layer, effect_draw_shader, uni .. 'outline',      v('outline') or 0)
  layer_shader_set_float(layer, effect_draw_shader, uni .. 'shade',        v('shade') or -0.12)
  layer_shader_set_int  (layer, effect_draw_shader, uni .. 'color_mode',
                         deco_color_modes[v('color_mode')] or (v('color') and 1 or 0))
  layer_shader_set_int  (layer, effect_draw_shader, uni .. 'color',   resolve_color(v('color') or 'white'))
  layer_shader_set_int  (layer, effect_draw_shader, uni .. 'color_b', resolve_color(v('color_b') or 'fg'))
  -- Driver: nil = the draw's main pattern; a pattern name = an independent
  -- field with its own scale/speed (gradient bg + plasma-driven dots).
  layer_shader_set_int  (layer, effect_draw_shader, uni .. 'driver',
                         v('driver') and (pattern_kinds[v('driver')] or 0) or 0)
  layer_shader_set_float(layer, effect_draw_shader, uni .. 'driver_scale', v('driver_scale') or 0.3)
  layer_shader_set_float(layer, effect_draw_shader, uni .. 'driver_speed', v('driver_speed') or 1)
  -- Sprite deco: bind the chosen icon (an image table with .handle) as the
  -- per-cell stamp. Harmless for non-sprite kinds (only kind 7 samples it).
  local icon = v('icon')
  if icon and icon.handle then
    layer_shader_set_texture(layer, effect_draw_shader, uni .. 'tex', icon.handle, unit)
  end
end

--[[
  effect_set(layer, spec)
  Write the effect uniforms for `layer`'s subsequent draws. spec is a sparse
  table — any omitted field uses the documented default (see top of file).

  Always writes u_time so animated patterns advance frame-to-frame.

  Performance: enqueues ~14 uniform writes per call (plus the ramp token list
  when color='ramp'). Cheap (a few bytes each).
]]
function effect_set(layer, spec)
  spec = spec or {}
  local p  = pattern_kinds[spec.pattern or 'solid'] or 2
  local c  = color_kinds[spec.color or 'none'] or 0
  local d  = dither_kinds[spec.dither or 'off'] or 0
  local ca = resolve_color(spec.color_a or 'white')
  local cb = resolve_color(spec.color_b or 'fg')
  local scale    = spec.pattern_scale or effect_default_pattern_scale
  local param    = spec.pattern_param or 0
  local param2   = spec.pattern_param2 or 0
  -- Universal modifiers. Default 1.0 = neutral (speed 1 = normal animation,
  -- contrast 1 = field unchanged, value 1 = recipe colors untouched). MUST
  -- default to 1, not 0 — a 0 here would freeze animation / flatten the
  -- field to mid-grey / black the draw out.
  local speed    = spec.speed or 1.0
  local contrast = spec.contrast or 1.0
  -- value: final-RGB multiplier — darken (<1) or brighten (>1) the WHOLE
  -- recipe. The SNKRX "same colors, a shade darker" idiom: a glyph_spec can
  -- reuse the body's exact tokens with value 0.78 (see units.lua).
  local value    = spec.value or 1.0

  layer_shader_set_int  (layer, effect_draw_shader, 'u_pattern_kind',     p)
  layer_shader_set_int  (layer, effect_draw_shader, 'u_color_kind',       c)
  layer_shader_set_int  (layer, effect_draw_shader, 'u_dither_kind',      d)
  -- DECO layers 1 + 2 — shapes composited over the base (layer 2 over
  -- layer 1's result). Spec prefixes 'deco' / 'deco2'; see write_deco.
  effect_write_deco(layer, spec, 'deco',  'u_deco_',  2)
  effect_write_deco(layer, spec, 'deco2', 'u_deco2_', 3)
  layer_shader_set_int  (layer, effect_draw_shader, 'u_color_a',          ca)
  layer_shader_set_int  (layer, effect_draw_shader, 'u_color_b',          cb)
  -- color='ramp': push the ordered token list (indices + count). Only when the
  -- recipe is active — other recipes leave the (unused) ramp uniforms as-is.
  if c == 3 then
    local ramp = spec.ramp or effect_ramp
    local rn = math.min(#ramp, 8)
    layer_shader_set_int(layer, effect_draw_shader, 'u_ramp_count', rn)
    for i = 1, rn do
      layer_shader_set_int(layer, effect_draw_shader, 'u_ramp_tokens[' .. (i - 1) .. ']', resolve_color(ramp[i]))
    end
  end
  layer_shader_set_float(layer, effect_draw_shader, 'u_pattern_scale',    scale)
  layer_shader_set_float(layer, effect_draw_shader, 'u_pattern_param',    param)
  layer_shader_set_float(layer, effect_draw_shader, 'u_pattern_param2',   param2)
  layer_shader_set_float(layer, effect_draw_shader, 'u_pattern_speed',    speed)
  layer_shader_set_float(layer, effect_draw_shader, 'u_pattern_contrast', contrast)
  layer_shader_set_float(layer, effect_draw_shader, 'u_value_mult',       value)
  -- image_field: sprite draws only. 1 = the image's own luminance drives the
  -- field (dither/recolor a real image); 0 = the pattern drives it (default).
  layer_shader_set_int  (layer, effect_draw_shader, 'u_image_field',
                         spec.image_field and 1 or 0)
  -- image_pattern_amount: luminance mode only. How much the animated pattern
  -- ripples the image's field before dither (0 = static, →1 = flowing).
  layer_shader_set_float(layer, effect_draw_shader, 'u_image_pattern_amount',
                         spec.image_pattern_amount or 0)
  layer_shader_set_float(layer, effect_draw_shader, 'u_time',             time)
end

--[[
  effect_clear(layer)
  Reset pattern/color/dither on this layer to passthrough. The other
  uniforms (color_a/b, scale, param) are left as-is — they only have an
  effect when a non-zero kind reads them. u_value_mult IS reset: unlike
  those, it multiplies every draw (even passthrough), so a lingering
  glyph-ink darken would tint everything after the bracket.
]]
function effect_clear(layer)
  layer_shader_set_int(layer, effect_draw_shader, 'u_pattern_kind', 2)  -- solid
  layer_shader_set_int(layer, effect_draw_shader, 'u_color_kind',   0)  -- none (passthrough)
  layer_shader_set_int(layer, effect_draw_shader, 'u_dither_kind',  0)  -- off
  layer_shader_set_int(layer, effect_draw_shader, 'u_deco_kind',    0)  -- none
  layer_shader_set_int(layer, effect_draw_shader, 'u_deco2_kind',   0)  -- none
  layer_shader_set_float(layer, effect_draw_shader, 'u_value_mult', 1.0)
end

--[[
  effect_draw(layer, spec, fn, ...)
  Scoped form: set the effect, run fn(...), then reset to passthrough.
  Forwards extra arguments to fn so closures can stay light.
]]
function effect_draw(layer, spec, fn, ...)
  effect_set(layer, spec)
  fn(...)
  effect_clear(layer)
end

--[[
  spec_color(spec) -> color object
  The representative color of a spec — used to tint FX / particles that are
  NOT drawn through the pipeline (they want a single flat color matching the
  drawable's effect, the way the old edition system used edition_base_color).
  Resolves the spec's primary token:
    color='ramp' -> the ramp's first stop
    otherwise    -> color_a
  Falls back to the `white` token for a nil spec / unknown token.
]]
function spec_color(spec)
  if not spec then return palette.white end
  if spec.color == 'ramp' then
    local r = spec.ramp or effect_ramp
    return palette[r[1]] or palette.white
  end
  return palette[spec.color_a] or palette.white
end

-- =============================================================================
-- SINGLE-CALL DRAW WRAPPERS
-- Draw one primitive through the full effect pipeline in ONE call: set + draw +
-- clear. `spec` is the same table effect_set takes (every field optional, see the
-- SPEC TABLE docblock). The base draw color is white — irrelevant for color≠none
-- (the whole point of these); use a plain layer_* call if you want color='none'.
-- For sprite deco, pass spec.deco_icon = <image> (e.g. star_img).
--
--   effect_rectangle(layer, x, y, w, h, spec)
--   effect_circle(layer, x, y, r, spec)
--   effect_image(layer, img, x, y, w, h, spec)   -- fits img into the box (contain)
-- =============================================================================

function effect_rectangle(layer, x, y, w, h, spec)
  effect_set(layer, spec)
  layer_rectangle(layer, x, y, w, h, 0xFFFFFFFF)
  effect_clear(layer)
end

-- Rounded-rect variant (entities / projectiles / the player are rounded
-- rects). Most entities draw under a layer_push transform (rotation + scale
-- springs), so they bracket effect_set / effect_clear around their own draw
-- instead of using this; this is for the untransformed case.
function effect_rounded_rectangle(layer, x, y, w, h, rad, spec)
  effect_set(layer, spec)
  layer_rounded_rectangle(layer, x, y, w, h, rad, 0xFFFFFFFF)
  effect_clear(layer)
end

function effect_circle(layer, x, y, r, spec)
  effect_set(layer, spec)
  layer_circle(layer, x, y, r, 0xFFFFFFFF)
  effect_clear(layer)
end

-- The engine draws textures at native size, so we scale via a layer_push
-- transform to fit `img` into the (x, y, w, h) box (contain, centered). `img` is
-- an image table (.handle / .width / .height, from image_load).
function effect_image(layer, img, x, y, w, h, spec)
  effect_set(layer, spec)
  local sc = math.min(w / img.width, h / img.height)
  layer_push(layer, x + w/2, y + h/2, 0, sc, sc)
  layer_image(layer, img, 0, 0)
  layer_pop(layer)
  effect_clear(layer)
end

-- =============================================================================
-- CYCLING — wrap-around step through each axis's named cycle.
-- Pass nil to get the first entry; pass an unknown name to get the first too.
-- =============================================================================

local function cycle_next(list, cur)
  for i, v in ipairs(list) do
    if v == cur then return list[(i % #list) + 1] end
  end
  return list[1]
end

local function cycle_prev(list, cur)
  for i, v in ipairs(list) do
    if v == cur then return list[((i - 2) % #list) + 1] end
  end
  return list[#list]
end

function effect_next_pattern(cur) return cycle_next(pattern_cycle_names, cur) end
function effect_prev_pattern(cur) return cycle_prev(pattern_cycle_names, cur) end
function effect_next_color(cur)   return cycle_next(color_cycle_names, cur) end
function effect_prev_color(cur)   return cycle_prev(color_cycle_names, cur) end
function effect_next_dither(cur)  return cycle_next(dither_cycle_names, cur) end
function effect_prev_dither(cur)  return cycle_prev(dither_cycle_names, cur) end
function effect_next_deco(cur)   return cycle_next(deco_cycle_names, cur) end
function effect_prev_deco(cur)   return cycle_prev(deco_cycle_names, cur) end
function effect_next_deco_driver(cur) return cycle_next(deco_driver_cycle_names, cur) end
function effect_prev_deco_driver(cur) return cycle_prev(deco_driver_cycle_names, cur) end

-- Cycle palette tokens (used by the test scene for color_a / color_b).
function effect_next_token(cur) return cycle_next(palette_token_names, cur) end
function effect_prev_token(cur) return cycle_prev(palette_token_names, cur) end

-- HUD helpers. Pattern/color cycle names are already readable; dither has
-- a prettier alias table for the long names.
function effect_dither_label(name) return dither_pretty_names[name] or name or '?' end
function effect_deco_label(name)   return deco_pretty_names[name]   or name or '?' end
