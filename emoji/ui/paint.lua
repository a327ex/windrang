--[[
  ui/paint.lua — the emoji UI paint chokepoint (two-layer chrome model).

  Every widget draw routes through here. The emoji chrome physics:

    • STRUCTURAL FILLS (panels, chips, tracks, stripes) draw to the current
      tier's PANEL layer, in palette tokens.
    • CONTENT (text, icons, marks) draws to the current tier's CONTENT
      layer — text WHITE by default, icons in their natural emoji colors.
    • BORDERS ARE NOT DRAWN. The pipeline's outline pass derives a chunky
      black outline around each layer's silhouette — that's all the border
      chrome this style has. White text gets its black halo the same way.
      Interior edges (a fill drawn over another fill on the same layer)
      produce NO outline — outlines are per-layer silhouettes.
    • UI layers carry no drop shadow (faithful to Aimer/EBB: the (4,4)
      shadow derives from the game/effects layers only).

  TIERS. Overlapping chrome (tooltips, modals) must not outline-merge with
  what's underneath, so paint targets one of two layer PAIRS:
    base — ui_panel_layer    / ui_content_layer
    top  — ui_top_panel_layer / ui_top_content_layer
  ui_tier('top') / ui_tier('base') switches the target; ui_tooltip brackets
  its own body with it. Layer globals are created by the host's
  emoji_layers{} declaration (resolved lazily here — paint loads first).

  THE DORMANT SPEC HOOK. Every paint call accepts a `spec` argument
  (threaded from opts.spec by widgets) and resolves it via
  ui_spec_for(token, override). TODAY this returns nothing actionable —
  draws are flat. When the four-axis effect system is ported, ui_spec_for
  grows the token → recipe logic and the paint functions grow their
  effect_set / effect_clear brackets. No widget changes.

  JUICE TRANSFORM. A widget's pixels span both layers, so scale-pops go
  through ui_paint_push(cx, cy, s) / ui_paint_pop() — push/pop the same
  transform on BOTH layers of the current tier.
]]

ui_current_tier = 'base'

function ui_tier(name)
  ui_current_tier = name or 'base'
end

-- Resolve the current tier's (panel, content) layer pair. Lazy: the layer
-- globals only exist after the host's emoji_layers{} call.
local function tier()
  if ui_current_tier == 'top' then
    return ui_top_panel_layer, ui_top_content_layer
  end
  return ui_panel_layer, ui_content_layer
end

--[[
  THE UI COLOR RECIPE (`ui_color`) — how UI draws route through the effect
  system now that it's live:
    'flat' — DEFAULT. ui_spec_for returns nil, draws stay raw (no bracket,
             zero overhead). The emoji style's baseline: locked flat tokens.
    'mix'  — the breathe A/B mode: each token mixed with its
             palette_breathe_partner, swept by the organic field. Not the
             emoji default — a comparison tool (and the Persona-style
             exploration starts from here).
  Per-element `opts.spec` overrides always win regardless of mode.
]]
ui_color       = 'flat'
ui_field_scale = 0.4     -- breathe noise density when ui_color = 'mix'
ui_dither      = 'off'   -- breathe dither mode NAME when ui_color = 'mix'

-- Reverse lookup: a palette color OBJECT → its token NAME (built from the
-- adapter in emoji/palette.lua). Non-token colors (cooldown shade, cloud
-- tint, color_mix results like hover-white precomputes) resolve nil → raw
-- draw, so custom colors never break.
ui_token_name = {}
for name, col in pairs(palette) do
  ui_token_name[col] = name
end

--[[
  ui_spec_for(token, override) -> spec | nil
  The effect-spec resolver. An explicit override table wins; otherwise the
  ui_color mode decides. nil means "draw raw" — the fast path every flat
  draw takes.
]]
function ui_spec_for(token, override)
  if type(override) == 'table' then return override end
  if ui_color == 'flat' then return nil end
  local name = ui_token_name[token]
  if not name then return nil end
  return { pattern = 'organic', pattern_scale = ui_field_scale,
           color = 'mix', color_a = name,
           color_b = palette_breathe_partner[name] or name,
           dither = ui_dither }
end

-- Bracket helper: resolve the spec; when non-nil, effect_set before the
-- draw and effect_clear after (the caller passes a closure-free draw via
-- explicit code — each paint fn inlines the pattern for zero allocs).
local function spec_open(layer, token, override)
  local sp = ui_spec_for(token, override)
  if sp then effect_set(layer, sp) end
  return sp
end

-- ── structural fills (panel layer) ────────────────────────────────────────
function ui_fill_rrect(x, y, w, h, rad, token, spec)
  local p = tier()
  local sp = spec_open(p, token, spec)
  layer_rounded_rectangle(p, x, y, w, h, rad, token())
  if sp then effect_clear(p) end
end

function ui_fill_rect(x, y, w, h, token, spec)
  local p = tier()
  local sp = spec_open(p, token, spec)
  layer_rectangle(p, x, y, w, h, token())
  if sp then effect_clear(p) end
end

function ui_fill_circle(cx, cy, r, token, spec)
  local p = tier()
  local sp = spec_open(p, token, spec)
  layer_circle(p, cx, cy, r, token())
  if sp then effect_clear(p) end
end

-- ── content draws (content layer) ─────────────────────────────────────────
-- Text defaults WHITE (the signature: white glyphs + derived black halo).
function ui_content_text(str, font, x, y, color, spec)
  local _, c = tier()
  local sp = spec_open(c, color or white, spec)
  layer_text(c, str, font, x, y, (color or white)())
  if sp then effect_clear(c) end
end

-- Icons draw in their natural emoji colors, CENTERED at (cx, cy), scaled to
-- `size` px wide. Pass tint / flash through to layer_image when needed.
-- Icons take the effect bracket ONLY via an explicit spec (their token is
-- nil) — image-as-content effects are deliberate, never ambient.
function ui_content_icon(img, cx, cy, size, spec, tint, flash)
  local _, c = tier()
  local sp = type(spec) == 'table' and spec or nil
  if sp then effect_set(c, sp) end
  local s = size/img.width
  layer_push(c, cx, cy, 0, s, s)
  layer_image(c, img, 0, 0, tint, flash)
  layer_pop(c)
  if sp then effect_clear(c) end
end

-- White marks (checkbox ticks, heading rules, slider knobs) — content-layer
-- primitives so they pick up the outline treatment like text does.
function ui_content_rect(x, y, w, h, color, spec)
  local _, c = tier()
  local sp = spec_open(c, color or white, spec)
  layer_rectangle(c, x, y, w, h, (color or white)())
  if sp then effect_clear(c) end
end

function ui_content_circle(cx, cy, r, color, spec)
  local _, c = tier()
  local sp = spec_open(c, color or white, spec)
  layer_circle(c, cx, cy, r, (color or white)())
  if sp then effect_clear(c) end
end

-- Rotated content rect (the checkbox tick arms) — centered at (cx, cy).
function ui_content_rect_rot(cx, cy, w, h, rot, color, spec)
  local _, c = tier()
  local sp = spec_open(c, color or white, spec)
  layer_push(c, cx, cy, rot, 1, 1)
  layer_rectangle(c, -w/2, -h/2, w, h, (color or white)())
  layer_pop(c)
  if sp then effect_clear(c) end
end

-- ── the juice transform ───────────────────────────────────────────────────
-- rot (optional) carries the hover-wobble rotation from ui_juice_transform.
function ui_paint_push(cx, cy, s, rot)
  local p, c = tier()
  layer_push(p, cx, cy, rot or 0, s, s)
  layer_push(c, cx, cy, rot or 0, s, s)
end

function ui_paint_pop()
  local p, c = tier()
  layer_pop(p)
  layer_pop(c)
end

-- Stencil brackets on the current tier's PANEL layer (the bar flat-cut).
function ui_paint_stencil_mask()  local p = tier() layer_stencil_mask(p)  end
function ui_paint_stencil_test()  local p = tier() layer_stencil_test(p)  end
function ui_paint_stencil_off()   local p = tier() layer_stencil_off(p)   end
function ui_paint_stencil_rect(x, y, w, h)
  local p = tier()
  layer_rectangle(p, x, y, w, h, white())
end
