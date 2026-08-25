--[[
  ui/widgets.lua — interactive widgets (consult ui_state + juice). Contracts
  follow snkrx-template (opts table in, ui_ret out, id → interactive /
  omit id → static, caller-owned state); the skin is EMOJI AIMER's actual
  shop/HUD pixel decisions (main.lua ~3100-4400), generalized:

    fills      cream `fg` is THE chrome fill; empty/disabled = `fg_dark`
    hover      fill turns WHITE + the hover wobble (ui_juice_transform)
    accent     GREEN (primary buttons, active tab segment, selection)
    yellow     money / attention (card banners, affordability)
    blue       info badges (slot keycaps, levels)
    error      red
    text       white Lana, pixel-snapped; BUTTON/TAB labels draw OUTSIDE
               the wobble transform (fills wobble, glyphs stay pixel-sharp
               — Aimer's draw_shop_button treatment); slot/card content
               rides INSIDE the transform (Aimer's tile treatment)
    radii      chips 2 · buttons/slots/tabs 4 · cards/tooltips 6

  Widget set: button · icon_button · slot · tabs · bar · hud_bar ·
  checkbox · slider · list_row · card (the banner tile) · field.
]]

local cooldown_shade = color(0, 0, 0, 140)

-- The banner/header band trick (Aimer's tile + tooltip): a rounded rect
-- flush with the bottom (or top) of a same-radius panel, its inner-edge
-- rounded corners squared off with two filler rects.
local function band_bottom(x, y, w, h, rad, token, spec)
  ui_fill_rrect(x, y, w, h, rad, token, spec)
  ui_fill_rect(x,           y, rad, rad, token, spec)
  ui_fill_rect(x + w - rad, y, rad, rad, token, spec)
end
local function band_top(x, y, w, h, rad, token, spec)
  ui_fill_rrect(x, y, w, h, rad, token, spec)
  ui_fill_rect(x,           y + h - rad, rad, rad, token, spec)
  ui_fill_rect(x + w - rad, y + h - rad, rad, rad, token, spec)
end

--[[
  ui_button(opts) -> { hovered, clicked, ... }
  Aimer's draw_shop_button: cream fill (green primary / red danger), hover
  → WHITE, disabled → fg_dark fill, white pixel-snapped label drawn
  OUTSIDE the transform. Default footprint 70×18, radius 4.
  opts: rect | x, y (auto-size) · label · id · variant ('primary' |
        'secondary' | 'danger' | 'ghost') · color (explicit fill token) ·
        disabled · font · radius · spec?
]]
function ui_button(opts)
  local id      = opts.id
  local variant = opts.variant or 'secondary'
  local font    = opts.font or fonts.main
  local rad     = opts.radius or 4
  local spec    = opts.spec

  local r = opts.rect
  if not r then
    local px = opts.pad_x or 8
    local py = opts.pad_y or 3
    r = { x = opts.x, y = opts.y,
          w = font:text_width(opts.label) + 2*px,
          h = font.height + 2*py }
  end

  local iid = (not opts.disabled) and id or nil
  local hovered, _, clicked, pressed = ui_interact(iid, r)
  if pressed then ui_juice_pull(id, 0.2, r) end
  if iid then ui_juice_hover(id, hovered, nil, r) end

  local fill = opts.color
    or (variant == 'primary' and green)
    or (variant == 'danger'  and red)
    or (variant ~= 'ghost'   and fg)
  if opts.disabled then fill = fg_dark end
  if hovered       then fill = white   end

  local cx, cy = r.x + r.w/2, r.y + r.h/2
  if fill then
    local ox, oy, rot, s = ui_juice_transform(iid)
    ui_paint_push(cx + ox, cy + oy, s, rot)
    ui_fill_rrect(-r.w/2, -r.h/2, r.w, r.h, rad, fill, spec)
    ui_paint_pop()
  end
  -- Label at absolute pixel-snapped position, outside the transform.
  ui_content_text(opts.label, font,
    math.floor(cx - font:text_width(opts.label)/2),
    math.floor(cy - font.height/2 + 1) + 1, white, spec)

  return ui_ret(r, { hovered = hovered, clicked = clicked })
end

--[[
  ui_icon_button(opts) -> { hovered, clicked, ... }
  Square button with an emoji image or a short glyph. Same fill rules as
  ui_button. opts: rect | x, y + size · id · image | label · color ·
  disabled · radius · spec?
]]
function ui_icon_button(opts)
  local size = opts.size or 16
  local r    = opts.rect or { x = opts.x, y = opts.y, w = size, h = size }
  local id   = opts.id

  local iid = (not opts.disabled) and id or nil
  local hovered, _, clicked, pressed = ui_interact(iid, r)
  if pressed then ui_juice_pull(id, 0.25, r) end
  if iid then ui_juice_hover(id, hovered, nil, r) end

  local fill = hovered and white or opts.color or (opts.disabled and fg_dark) or fg
  local cx, cy = r.x + r.w/2, r.y + r.h/2
  local ox, oy, rot, s = ui_juice_transform(iid)
  ui_paint_push(cx + ox, cy + oy, s, rot)
  ui_fill_rrect(-r.w/2, -r.h/2, r.w, r.h, opts.radius or 4, fill, opts.spec)
  if opts.image then
    ui_content_icon(opts.image, 0, 0, math.min(r.w, r.h) - 6, opts.spec)
  end
  ui_paint_pop()
  if opts.label then
    local font = opts.font or fonts.main
    ui_content_text(opts.label, font,
      math.floor(cx - font:text_width(opts.label)/2),
      math.floor(cy - font.height/2 + 1) + 1, white, opts.spec)
  end
  return ui_ret(r, { hovered = hovered, clicked = clicked })
end

--[[
  ui_slot(opts) -> { hovered, clicked, ... }
  Aimer's owned/inventory slot: 28×28 cream rounded (radius 4), icon at
  ~16px CENTERED (smaller than the slot — icons never fill), hover →
  white frame + wobble, EMPTY = flat fg_dark fill (inert look, still
  clickable if given an id). selected = green frame. Extras: cooldown
  sweep, cooldown_text, keycap (blue pill — the Aimer badge color).
  opts: rect · id · image · icon_size · selected · disabled · cooldown ·
        cooldown_text · key · spec?
]]
function ui_slot(opts)
  local r    = opts.rect
  local id   = opts.id
  local spec = opts.spec

  local iid = (not opts.disabled) and id or nil
  local hovered, _, clicked, pressed = ui_interact(iid, r)
  if pressed then ui_juice_pull(id, 0.25, r) end
  if iid then ui_juice_hover(id, hovered, nil, r) end

  -- Empty slot: the flat desaturated placeholder, no wobble.
  if not opts.image and not opts.selected and not hovered then
    ui_fill_rrect(r.x, r.y, r.w, r.h, 4, opts.disabled and fg_dark or fg_dark, spec)
    return ui_ret(r, { hovered = hovered, clicked = clicked })
  end

  local frame = hovered and white
    or opts.selected and green
    or opts.disabled and fg_dark
    or fg

  local cx, cy = r.x + r.w/2, r.y + r.h/2
  local ox, oy, rot, s = ui_juice_transform(iid)
  ui_paint_push(cx + ox, cy + oy, s, rot)
  local lr = { x = -r.w/2, y = -r.h/2, w = r.w, h = r.h }

  ui_fill_rrect(lr.x, lr.y, r.w, r.h, 4, frame, spec)
  if opts.image then
    local icon = opts.icon_size or math.floor(math.min(r.w, r.h)*0.6)
    ui_content_icon(opts.image, 0, 0, icon, spec, opts.disabled and gray())
  end

  -- Cooldown sweep: translucent dark rect growing bottom-up, inset 1px.
  if opts.cooldown and opts.cooldown > 0 then
    local ch = math.floor((r.h - 2)*math.clamp(opts.cooldown, 0, 1))
    ui_fill_rect(lr.x + 1, lr.y + r.h - 1 - ch, r.w - 2, ch, cooldown_shade, spec)
  end
  if opts.cooldown_text then
    ui_text({ rect = lr, text = tostring(opts.cooldown_text),
              font = fonts.mid, align_h = 'center', spec = spec })
  end

  -- Keycap: blue pill top-left (Aimer's badge color), white key letter.
  if opts.key then
    local kw, kh = 11, 11
    ui_fill_rrect(lr.x + 1, lr.y + 1, kw, kh, 2, blue, spec)
    ui_text({ rect = { x = lr.x + 1, y = lr.y + 1, w = kw, h = kh },
              text = string.upper(opts.key), font = fonts.main,
              align_h = 'center', spec = spec })
  end

  ui_paint_pop()
  return ui_ret(r, { hovered = hovered, clicked = clicked })
end

--[[
  ui_tabs(opts) -> { active, changed, hovered_index, ... }
  Aimer's tier-selector strip: ONE cream rounded strip (radius 4), N flush
  segments, active = GREEN full-bleed fill (rounded outer corners on
  first/last via the notch trick), hovered = white fill, full-height 1px
  fg_dark dividers skipped around the active segment, white pixel-snapped
  labels outside any transform. Caller owns `active` (1-based).
  opts: rect · id · labels (array) · active · disabled (set of indices,
        optional — renders label muted, inert) · spec?
]]
function ui_tabs(opts)
  local r      = opts.rect
  local id     = opts.id
  local labels = opts.labels or {}
  local n      = #labels
  local active = opts.active or 1
  local spec   = opts.spec
  local rad    = 4
  local seg_w  = r.w/n

  ui_fill_rrect(r.x, r.y, r.w, r.h, rad, fg, spec)

  local changed, hovered_index = false, nil
  for i = 1, n do
    local sx = r.x + math.floor((i - 1)*seg_w)
    local sw = math.floor(i*seg_w) - math.floor((i - 1)*seg_w)
    local sr = { x = sx, y = r.y, w = sw, h = r.h }
    local disabled = opts.disabled and opts.disabled[i]
    local sid = (id and not disabled) and (id .. '_seg' .. i) or nil
    local hovered, _, clicked = ui_interact(sid, sr)
    if sid then ui_juice_hover(sid, hovered, nil, sr) end
    if hovered then hovered_index = i end
    if clicked and i ~= active then active, changed = i, true end

    local fill
    if i == active then fill = green
    elseif hovered and not disabled then fill = white end
    if fill then
      -- Full-bleed segment fill; first/last keep the strip's rounded
      -- outer corners, middles are flat, inner edges squared via notches.
      if i == 1 and i == n then
        ui_fill_rrect(sr.x, sr.y, sr.w, sr.h, rad, fill, spec)
      elseif i == 1 then
        ui_fill_rrect(sr.x, sr.y, sr.w, sr.h, rad, fill, spec)
        ui_fill_rect(sr.x + sr.w - rad, sr.y, rad, rad, fill, spec)
        ui_fill_rect(sr.x + sr.w - rad, sr.y + sr.h - rad, rad, rad, fill, spec)
      elseif i == n then
        ui_fill_rrect(sr.x, sr.y, sr.w, sr.h, rad, fill, spec)
        ui_fill_rect(sr.x, sr.y, rad, rad, fill, spec)
        ui_fill_rect(sr.x, sr.y + sr.h - rad, rad, rad, fill, spec)
      else
        ui_fill_rect(sr.x, sr.y, sr.w, sr.h, fill, spec)
      end
    end
  end

  -- Dividers, skipped on both sides of the active segment.
  for i = 1, n - 1 do
    if active ~= i and active ~= i + 1 then
      ui_fill_rect(r.x + math.floor(i*seg_w), r.y, 1, r.h, fg_dark, spec)
    end
  end

  -- Labels at absolute integer positions (pixel-clean).
  for i = 1, n do
    local cx = r.x + (i - 0.5)*seg_w
    local disabled = opts.disabled and opts.disabled[i]
    ui_content_text(labels[i], fonts.main,
      math.floor(cx - fonts.main:text_width(labels[i])/2),
      math.floor(r.y + r.h/2 - fonts.main.height/2 + 1) + 1,
      disabled and fg_dark or white, spec)
  end

  return ui_ret(r, { active = active, changed = changed,
                     hovered_index = hovered_index })
end

-- One bar segment: full-width rounded fill stencil-masked to frac, so the
-- outer corners stay rounded while the moving edge cuts flat.
local function draw_bar_segment(r, rad, frac, color, spec)
  if frac <= 0 then return end
  local seg_w = math.floor(r.w*frac + 0.5)
  ui_paint_stencil_mask()
  ui_paint_stencil_rect(r.x, r.y, seg_w, r.h)
  ui_paint_stencil_test()
  ui_fill_rrect(r.x, r.y, r.w, r.h, rad, color, spec)
  ui_paint_stencil_off()
end

--[[
  ui_bar(opts) -> {}
  Progress / health bar: black rounded track + flat-cut fill (the EBB
  hp_bar heritage). opts: rect · fill (0..1) | value + max (health mode,
  centered 'value / max' text) · color (green) · track (black) · back
  (white) · radius (2) · id (two-bar tween + cash-register kick) ·
  kick = false · spec? / fill_spec?
]]
function ui_bar(opts)
  local r     = opts.rect
  local id    = opts.id
  local rad   = opts.radius or 2
  local color = opts.color or green
  local track = opts.track or black
  local back  = opts.back  or white
  local spec  = opts.spec

  local frac
  if opts.max then
    frac = math.clamp((opts.value or 0)/opts.max, 0, 1)
  else
    frac = math.clamp(opts.fill or 0, 0, 1)
  end

  local front_f, back_f, shown_v, y_off = frac, frac, opts.value, 0
  if id then
    front_f, back_f, shown_v, y_off = ui_bar_feed(id, frac, opts.value or 0)
  end
  if opts.kick == false then y_off = 0 end

  local dr = { x = r.x, y = math.floor(r.y + y_off + 0.5), w = r.w, h = r.h }

  ui_fill_rrect(dr.x, dr.y, dr.w, dr.h, rad, track, spec)
  if back_f > front_f + 0.001 then
    draw_bar_segment(dr, rad, back_f, back, spec)
  end
  draw_bar_segment(dr, rad, front_f, color, opts.fill_spec or spec)

  if opts.max then
    ui_text({ rect = { x = dr.x, y = dr.y, w = dr.w, h = dr.h },
              align_h = 'center', spec = spec,
              text = math.floor((shown_v or 0) + 0.5) .. ' / ' .. opts.max })
  end
  return ui_ret(r, {})
end

--[[
  ui_hud_bar(opts) -> {}
  One-line resource readout: [emoji icon][bar][value]. opts: x, y, w ·
  icon · frac | value + max · value_text · val_w · h (12) · color /
  track / id / kick / spec / fill_spec → threaded to ui_bar.
]]
function ui_hud_bar(opts)
  local h      = opts.h or 12
  local icon_w = opts.icon and (h + 2) or 0
  local gap    = opts.icon and 4 or 0
  local val_s  = opts.value_text or (opts.value and tostring(opts.value)) or ''
  local val_w  = opts.val_w or (val_s ~= '' and fonts.main:text_width(val_s) + 4) or 0
  local r      = { x = opts.x, y = opts.y, w = opts.w, h = math.max(h, icon_w) }

  if opts.icon then
    ui_content_icon(opts.icon, r.x + icon_w/2, r.y + r.h/2, icon_w, opts.spec)
  end
  local bar_r = { x = r.x + icon_w + gap, y = r.y + (r.h - h)/2,
                  w = r.w - icon_w - gap - val_w, h = h }
  ui_bar({ rect = bar_r, fill = opts.frac, value = opts.value, max = opts.max,
           color = opts.color, track = opts.track, id = opts.id,
           kick = opts.kick, spec = opts.spec, fill_spec = opts.fill_spec })
  if val_s ~= '' and not opts.max then
    ui_text({ rect = { x = bar_r.x + bar_r.w + 4, y = r.y, w = val_w - 4, h = r.h },
              text = val_s, spec = opts.spec })
  end
  return ui_ret(r, {})
end

--[[
  ui_checkbox(opts) -> { checked, clicked, ... }
  Rounded box + optional label; whole row clickable. Off = fg_dark box,
  hover = white box, on = green fill + white geometric tick. Caller-owned
  state. opts: x, y · label · checked · id · size (12) · spec?
]]
function ui_checkbox(opts)
  local size  = opts.size or 12
  local font  = opts.font or fonts.main
  local lw    = opts.label and (font:text_width(opts.label) + 6) or 0
  local r     = { x = opts.x, y = opts.y, w = size + lw, h = size }
  local id    = opts.id

  local hovered, _, clicked, pressed = ui_interact(id, r)
  if pressed then ui_juice_pull(id, 0.25, { x = 0, y = 0, w = size, h = size }) end
  if id then ui_juice_hover(id, hovered, nil, r) end
  local checked = opts.checked
  if clicked then checked = not checked end

  local fill = checked and green or hovered and white or fg_dark
  local ox, oy, rot, s = ui_juice_transform(id)
  ui_paint_push(r.x + size/2 + ox, r.y + size/2 + oy, s, rot)
  ui_fill_rrect(-size/2, -size/2, size, size, 3, fill, opts.spec)
  if checked then
    ui_content_rect_rot(-size*0.16, size*0.10, size*0.32, 2,  math.pi/4, white, opts.spec)
    ui_content_rect_rot( size*0.10, -size*0.04, size*0.55, 2, -math.pi/4, white, opts.spec)
  end
  ui_paint_pop()

  if opts.label then
    ui_text({ rect = { x = r.x + size + 6, y = r.y, w = lw - 6, h = size },
              text = opts.label, font = font, spec = opts.spec })
  end
  return ui_ret(r, { checked = checked, clicked = clicked, hovered = hovered })
end

--[[
  ui_slider(opts) -> { value, changed, ... }
  fg_dark rounded track + green fill + white outlined knob. Press anywhere
  on the row to grab; drag tracks the cursor. Caller-owned value (0..1).
  opts: rect · value · id · color (green) · track (fg_dark) · spec?
]]
function ui_slider(opts)
  local r       = opts.rect
  local id      = opts.id
  local track_h = 4
  local knob_r  = 4

  local hovered, active, _, pressed = ui_interact(id, r)
  if pressed then ui_juice_pull(id, 0.2, r) end
  if id then ui_juice_hover(id, hovered, nil, r) end

  local value   = math.clamp(opts.value or 0, 0, 1)
  local changed = false
  if id and ui_is_active(id) then
    local mx = mouse_position()
    local new = math.clamp((mx - r.x)/r.w, 0, 1)
    changed = math.abs(new - value) > 0.0001
    value = new
  end

  local ty = r.y + (r.h - track_h)/2
  ui_fill_rrect(r.x, ty, r.w, track_h, 2, opts.track or fg_dark, opts.spec)
  local fw = math.floor(r.w*value + 0.5)
  if fw > 0 then
    ui_fill_rrect(r.x, ty, fw, track_h, 2, opts.color or green, opts.spec)
  end
  ui_content_circle(r.x + r.w*value, ty + track_h/2, knob_r, white, opts.spec)

  return ui_ret(r, { value = value, changed = changed, hovered = hovered })
end

--[[
  ui_list_row(opts) -> { hovered, clicked, ... }
  One row of a list. Cells: strings, or tables { text, w (fixed px; omit →
  flex share), align, color, font }. hover = white fill; selected = white
  fill + 2px green left stripe; header = fg_dark fill, muted inert. Rows
  sit over a ui_panel — interior fills, no extra outlines.
  opts: rect · cells · id · selected · header · spec?
]]
function ui_list_row(opts)
  local r    = opts.rect
  local id   = (not opts.header) and opts.id or nil
  local spec = opts.spec

  local hovered, _, clicked, pressed = ui_interact(id, r)
  if pressed then ui_juice_pull(id, 0.1, r) end
  if id then ui_juice_hover(id, hovered, nil, r) end

  if opts.header then
    ui_fill_rect(r.x, r.y, r.w, r.h, fg_dark, spec)
  elseif opts.selected then
    ui_fill_rect(r.x, r.y, r.w, r.h, white, spec)
    ui_fill_rect(r.x, r.y, 2, r.h, green, spec)
  elseif hovered then
    ui_fill_rect(r.x, r.y, r.w, r.h, white, spec)
  end

  -- 8px left inset so cell text clears the 2px selection stripe (and its
  -- glyph outlines) with real air; 4px on the right.
  local cells = opts.cells or {}
  local fixed, flex_n = 0, 0
  for _, c in ipairs(cells) do
    if type(c) == 'table' and c.w then fixed = fixed + c.w else flex_n = flex_n + 1 end
  end
  local flex_w = flex_n > 0 and math.max(0, (r.w - 12 - fixed)/flex_n) or 0
  local cx = r.x + 8
  for _, c in ipairs(cells) do
    local cell = type(c) == 'table' and c or { text = c }
    local cw   = cell.w or flex_w
    ui_text({ rect = { x = cx, y = r.y, w = cw, h = r.h },
              text = cell.text or '', font = cell.font,
              color = cell.color or (opts.header and white) or nil,
              align_h = cell.align, spec = spec })
    cx = cx + cw
  end
  return ui_ret(r, { hovered = hovered, clicked = clicked })
end

--[[
  ui_card(opts) -> { hovered, clicked, ... }
  Aimer's shop tile, generalized: cream rounded frame (radius 6), emoji
  icon in the body, a COLORED BANNER BAND flush with the bottom (rounded
  bottom corners, squared top via the notch trick) carrying the card's
  label. hover → white frame + wobble; selected → green frame; disabled →
  fg_dark frame + gray banner + gray-tinted icon. Optional desc lines
  between icon and banner for taller cards.
  opts: rect · id · image · icon_size (22) · banner (label string) ·
        banner_color (token, default yellow) · lines (array, optional) ·
        selected · disabled · spec?
]]
function ui_card(opts)
  local r    = opts.rect
  local id   = opts.id
  local spec = opts.spec
  local rad  = 6

  local iid = (not opts.disabled) and id or nil
  local hovered, _, clicked, pressed = ui_interact(iid, r)
  if pressed then ui_juice_pull(id, 0.2, r) end
  if iid then ui_juice_hover(id, hovered, nil, r) end

  local frame = hovered and white
    or opts.selected and green
    or opts.disabled and fg_dark
    or fg
  local banner_col = opts.disabled and gray or opts.banner_color or yellow

  local cx, cy = r.x + r.w/2, r.y + r.h/2
  local ox, oy, rot, s = ui_juice_transform(iid)
  ui_paint_push(cx + ox, cy + oy, s, rot)
  local lr = { x = -r.w/2, y = -r.h/2, w = r.w, h = r.h }

  ui_fill_rrect(lr.x, lr.y, r.w, r.h, rad, frame, spec)

  local banner_h = opts.banner and 14 or 0
  if opts.banner then
    band_bottom(lr.x, lr.y + r.h - banner_h, r.w, banner_h, rad, banner_col, spec)
  end

  -- Icon centered in the body space above the banner (and above any lines).
  -- icon_grayscale routes the emoji through the pipeline's grayscale
  -- channel (Aimer's unaffordable-tile treatment) — drawn into the channel
  -- source layer with the SAME juice transform so it rides the wobble.
  local lines_h = #(opts.lines or {})*(fonts.main.height + 1)
  if opts.image then
    local icon = opts.icon_size or 22
    local body_h = r.h - banner_h - lines_h
    if opts.icon_grayscale and emoji_channel_targets and emoji_channel_targets.gray then
      local isc = icon/opts.image.width
      layer_push(emoji_gray_layer, cx + ox, cy + oy, rot, s, s)
      layer_push(emoji_gray_layer, 0, lr.y + body_h/2, 0, isc, isc)
      layer_image(emoji_gray_layer, opts.image, 0, 0)
      layer_pop(emoji_gray_layer)
      layer_pop(emoji_gray_layer)
    else
      ui_content_icon(opts.image, 0, lr.y + body_h/2, icon, spec,
                      opts.disabled and gray())
    end
  end
  local ly = lr.y + r.h - banner_h - lines_h - 2
  for _, l in ipairs(opts.lines or {}) do
    ui_text({ rect = { x = lr.x, y = ly, w = r.w, h = fonts.main.height },
              text = l, align_h = 'center', align_v = 'top', spec = spec })
    ly = ly + fonts.main.height + 1
  end

  -- Banner label: pixel-snapped, vertically centered in the band (the
  -- Aimer recipe: floor(banner_y + h/2 - 11/2 + 2)).
  if opts.banner then
    local by = lr.y + r.h - banner_h
    ui_content_text(opts.banner, fonts.main,
      math.floor(-fonts.main:text_width(opts.banner)/2),
      math.floor(by + banner_h/2 - fonts.main.height/2 + 2), white, spec)
  end

  ui_paint_pop()
  return ui_ret(r, { hovered = hovered, clicked = clicked })
end

--[[
  ui_swatch_row(opts) -> { clicked, token, ... }
  A wrapping grid of palette-token color swatches (the color picker — the
  F5 inspector uses it for color_a / color_b). Swatches are raw flat fills
  of each token's color; the selected one gets a 2px green ring (Anchor3's
  inset stroke — exact-px). Click to pick; returns the clicked token NAME.
  Caller-owned selection: pass opts.selected (a token name).
  opts: rect (width drives wrapping) · id · selected · size (10) · gap (3) ·
        tokens (default palette_token_names)
]]
function ui_swatch_row(opts)
  local r      = opts.rect
  local id     = opts.id
  local size   = opts.size or 10
  local gap    = opts.gap or 3
  local tokens = opts.tokens or palette_token_names
  local per_row = math.max(1, math.floor((r.w + gap)/(size + gap)))

  local clicked_token = nil
  for i, name in ipairs(tokens) do
    local row = math.floor((i - 1)/per_row)
    local col = (i - 1)%per_row
    local sr  = { x = r.x + col*(size + gap), y = r.y + row*(size + gap),
                  w = size, h = size }
    local sid = id and (id .. '_' .. name)
    local hovered, _, clicked = ui_interact(sid, sr)
    if clicked then clicked_token = name end
    ui_fill_rrect(sr.x, sr.y, size, size, 2, palette[name])
    if opts.selected == name then
      local p = ui_panel_layer
      layer_rounded_rectangle_line(p, sr.x, sr.y, size, size, 2, green(), 2)
    elseif hovered then
      local p = ui_panel_layer
      layer_rounded_rectangle_line(p, sr.x, sr.y, size, size, 2, white(), 1)
    end
  end

  local rows = math.ceil(#tokens/per_row)
  local h    = rows*size + (rows - 1)*gap
  return ui_ret({ x = r.x, y = r.y, w = r.w, h = h },
                { clicked = clicked_token ~= nil, token = clicked_token })
end

-- Height the swatch grid will occupy for n tokens at width w — for sizing
-- the rect before calling.
function ui_swatch_grid_height(n, w, size, gap)
  size = size or 10
  gap  = gap or 3
  local per_row = math.max(1, math.floor((w + gap)/(size + gap)))
  local rows    = math.ceil(n/per_row)
  return rows*size + (rows - 1)*gap
end

--[[
  ui_field(opts) -> { prev_clicked, next_clicked, ... }
  The 'LABEL  value  [<][>]' cycler. Caller owns the value.
  opts: rect · id · label · value (string) · spec?
]]
function ui_field(opts)
  local r    = opts.rect
  local id   = opts.id
  local bs   = r.h
  local spec = opts.spec

  if opts.label then
    ui_text({ rect = { x = r.x, y = r.y, w = r.w, h = r.h },
              text = string.upper(opts.label), font = fonts.main,
              color = fg_dark, spec = spec })
  end
  local next_b = ui_icon_button({ rect = { x = r.x + r.w - bs, y = r.y, w = bs, h = bs },
                                  id = id and (id .. '_next'), label = '>', spec = spec })
  local prev_b = ui_icon_button({ rect = { x = r.x + r.w - 2*bs - 2, y = r.y, w = bs, h = bs },
                                  id = id and (id .. '_prev'), label = '<', spec = spec })
  ui_text({ rect = { x = r.x, y = r.y, w = r.w - 2*bs - 6, h = r.h },
            text = tostring(opts.value or ''), align_h = 'right', spec = spec })

  return ui_ret(r, { prev_clicked = prev_b.clicked, next_clicked = next_b.clicked })
end
