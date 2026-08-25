--[[
  emoji/pipeline.lua — the signature emoji-style render pipeline.

  The look: every content layer gets a chunky BLACK OUTLINE derived from its
  own alpha (outline.frag, a 5x5 neighbor sample), composited immediately
  beneath it, and the world layers cast a shared DROP SHADOW offset (4, 4)
  down-right (shadow.frag). UI/text drawn in white reads as black-outlined
  white glyphs for free. This is the pipeline every emoji game hand-rolled
  (Emoji Ball Battles, Emoji Aimer, emoji-ball-bounce, and the 2022-24
  engine generations before them) — here it's declarative.

  Usage (in main.lua, after require('emoji')):

    emoji_layers({
      { 'bg' },                                  -- plain: no outline, no shadow
      { 'game',    outline = true, shadow = true },
      { 'effects', outline = true, shadow = true },
      { 'ui',      outline = true },
      { 'cursor',  outline = true },
    })

  This creates a global `<name>_layer` per entry (bg_layer, game_layer, ...),
  a derived `<name>_outline` layer per outlined entry, and one shared
  `emoji_shadow_layer`. Queue draws into the content layers as usual
  (camera_attach brackets and all draw calls stay host-side), then end
  draw() with:

    emoji_render()

  which runs the whole canonical composite:
    1. layer_render every content layer (flush queued commands to FBOs)
    2. derive the shared shadow from every shadow-flagged layer
    3. derive each outline from its layer
    4. composite in declaration order — the shadow is drawn once,
       immediately before the first outlined-or-shadowed layer, and each
       outline is drawn immediately beneath its own layer.

  Config knobs (set before emoji_render, defaults are the current-gen look):
    emoji_shadow_offset_x / _y  — shadow displacement (default 4, 4)
    outline.frag                — outline reach comes from u_pixel_size,
                                  set to 1 game-pixel at load time
    shadow.frag                 — shadow color/alpha lives in the shader
                                  (gray 0.5 @ 50% alpha, the new-gen value;
                                  the 2020-24 games used 0.1 @ 20%)

  Shaders are loaded at require time (shadow / outline / recolor /
  grayscale); recolor + grayscale are shipped for the damage-number and
  disabled-item passes (used by later modules), not by the composite here.
]]

shadow_shader       = shader_load_file('assets/shadow.frag')
outline_shader      = shader_load_file('assets/outline.frag')
recolor_shader      = shader_load_file('assets/recolor.frag')
grayscale_shader    = shader_load_file('assets/grayscale.frag')
outline_only_shader = shader_load_file('assets/outline_only.frag')
shader_set_vec2_immediate(outline_shader,      'u_pixel_size', 1/width, 1/height)
shader_set_vec2_immediate(outline_only_shader, 'u_pixel_size', 1/width, 1/height)

emoji_layer_defs      = nil
emoji_shadow_layer    = nil
emoji_shadow_offset_x = 4
emoji_shadow_offset_y = 4

-- ── injection hooks ──────────────────────────────────────────────────────
-- Multiple consumers can run between content render and outline/shadow
-- derivation (damage-number recolor bucketing, the icon channels below).
-- The legacy single `emoji_render_inject` global is still honored.
emoji_render_injects = {}

function emoji_render_add_inject(fn)
  emoji_render_injects[#emoji_render_injects + 1] = fn
end

-- ── derived icon channels ────────────────────────────────────────────────
-- Three shader-derived draw paths for icons/glyphs. Queue draws into the
-- channel's source layer during update; at render time the source is
-- pulled through its shader into a TARGET content layer (before outline
-- derivation, so results get the black halo like everything else).
--   grayscale    — desaturated icons (Aimer's unaffordable-tile treatment)
--   outline_only — hollow ring of the drawn shape (EBB's empty heart)
--   badge        — keycap glyphs recolored to badge_color (Aimer's blue
--                  count badges); draw with emoji_badge_text below
-- Host wiring (after emoji_layers):
--   emoji_set_icon_channels({ grayscale = ui_content_layer,
--     outline_only = ui_content_layer, badge = ui_content_layer,
--     badge_color = blue })
emoji_gray_layer  = layer_new('emoji_gray_src')
emoji_ring_layer  = layer_new('emoji_ring_src')
emoji_badge_layer = layer_new('emoji_badge_src')
emoji_channel_targets = {}
emoji_badge_color     = nil

function emoji_set_icon_channels(opts)
  opts = opts or {}
  emoji_channel_targets.gray  = opts.grayscale
  emoji_channel_targets.ring  = opts.outline_only
  emoji_channel_targets.badge = opts.badge
  emoji_badge_color           = opts.badge_color
end

-- Keycap glyph run into the badge channel (top-left anchored, size px per
-- glyph). Characters come from digit_imgs (digits, letters, +, -).
function emoji_badge_text(x, y, text, size)
  size = size or 8
  for i = 1, #text do
    local img = digit_imgs[text:sub(i, i)]
    if img then
      local s = size/img.width
      layer_push(emoji_badge_layer, x + (i - 0.5)*size, y + size/2, 0, s, s)
      layer_image(emoji_badge_layer, img, 0, 0)
      layer_pop(emoji_badge_layer)
    end
  end
end

local function process_icon_channels()
  local t = emoji_channel_targets
  if t.gray then
    layer_render(emoji_gray_layer)
    layer_draw_from(t.gray, emoji_gray_layer, grayscale_shader)
    layer_clear(emoji_gray_layer)
  end
  if t.ring then
    layer_render(emoji_ring_layer)
    layer_draw_from(t.ring, emoji_ring_layer, outline_only_shader)
    layer_clear(emoji_ring_layer)
  end
  if t.badge then
    layer_render(emoji_badge_layer)
    if emoji_badge_color then
      shader_set_vec4_immediate(recolor_shader, 'u_target_color',
        emoji_badge_color.r/255, emoji_badge_color.g/255, emoji_badge_color.b/255, 1)
    end
    layer_draw_from(t.badge, emoji_badge_layer, recolor_shader)
    layer_clear(emoji_badge_layer)
  end
end

function emoji_layers(defs)
  emoji_layer_defs = defs
  for _, def in ipairs(defs) do
    local name = def[1]
    _G[name .. '_layer'] = layer_new(name)
    if def.outline then
      _G[name .. '_outline'] = layer_new(name .. '_outline')
    end
  end
  emoji_shadow_layer = layer_new('emoji_shadow')
end

function emoji_render()
  -- 1. Flush queued commands into each content layer's FBO.
  for _, def in ipairs(emoji_layer_defs) do
    layer_render(_G[def[1] .. '_layer'])
  end

  -- 1b. Injection point: content FBOs are rendered, derivations haven't
  --     run — anything drawn into a content layer here still gets its
  --     outline/shadow. Consumers: the damage-number recolor bucketing
  --     (emoji/fx.lua), the icon channels, and anything registered via
  --     emoji_render_add_inject.
  if emoji_render_inject then emoji_render_inject() end
  for _, fn in ipairs(emoji_render_injects) do fn() end
  process_icon_channels()

  -- 2. Shared shadow: every shadow-flagged layer stamped through shadow.frag.
  layer_clear(emoji_shadow_layer)
  for _, def in ipairs(emoji_layer_defs) do
    if def.shadow then
      layer_draw_from(emoji_shadow_layer, _G[def[1] .. '_layer'], shadow_shader)
    end
  end

  -- 3. Per-layer outline derivation.
  for _, def in ipairs(emoji_layer_defs) do
    if def.outline then
      local o = _G[def[1] .. '_outline']
      layer_clear(o)
      layer_draw_from(o, _G[def[1] .. '_layer'], outline_shader)
    end
  end

  -- 4. Composite bottom-to-top. The shadow slots in before the first layer
  --    that participates in the treatment (so plain backdrop layers stay
  --    beneath it), each outline immediately beneath its own layer.
  local shadow_drawn = false
  for _, def in ipairs(emoji_layer_defs) do
    if not shadow_drawn and (def.shadow or def.outline) then
      layer_draw(emoji_shadow_layer, emoji_shadow_offset_x, emoji_shadow_offset_y)
      shadow_drawn = true
    end
    if def.outline then layer_draw(_G[def[1] .. '_outline']) end
    layer_draw(_G[def[1] .. '_layer'])
  end
end
