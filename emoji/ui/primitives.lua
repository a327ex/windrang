--[[
  ui/primitives.lua — pure-draw UI elements (no interaction, no juice).
  Contracts follow snkrx-template; the skin is the emoji language: rounded
  token fills on the panel layer, white outlined text + natural-color emoji
  icons on the content layer, borders from the pipeline's outline pass.

  Elements: ui_panel · ui_text · ui_divider · ui_label (the HUD chip) ·
  ui_item_icon · ui_tooltip.

  Skin defaults (Emoji Aimer's): panel fill `fg` (cream) · hover WHITE ·
  accent `green` · money/attention `yellow` · info badges `blue` · danger
  `red` · empty/disabled `fg_dark` · text `white`.
  Fonts: fonts.main (Lana 11) for nearly everything · fonts.mid (Awesome
  16) for display/titles/score. ⚠ fonts.big (FatPixel) renders ~3x its
  registered 8px height — RARE deliberate use only, never in layout-
  measured UI.
]]

-- ── panel — a rounded structural fill ─────────────────────────────────────
-- opts: rect, color (token, default fg), radius (default 3), spec?
function ui_panel(opts)
  local r = opts.rect
  ui_fill_rrect(r.x, r.y, r.w, r.h, opts.radius or 3, opts.color or fg, opts.spec)
  return ui_ret(r, {})
end

-- ── text — single line, aligned inside a rect (or bare at x, y) ───────────
-- opts: rect | x, y · text · font (default fonts.main) · color (default
-- white) · align_h ('left'|'center'|'right') · align_v ('center'|'top') ·
-- spec?. LanaPixel sits high in its box, so fonts.main gets a +1 nudge.
function ui_text(opts)
  local font = opts.font or fonts.main
  local str  = opts.text or ''
  local r    = opts.rect or { x = opts.x, y = opts.y,
                              w = font:text_width(str), h = font.height }
  local x = r.x
  if opts.align_h == 'center' then
    x = r.x + (r.w - font:text_width(str))/2
  elseif opts.align_h == 'right' then
    x = r.x + r.w - font:text_width(str)
  end
  local y = r.y
  if opts.align_v ~= 'top' then
    y = r.y + (r.h - font.height)/2
    if font == fonts.main then y = y + 1 end
  end
  ui_content_text(str, font, math.floor(x), math.floor(y), opts.color, opts.spec)
  return ui_ret(r, {})
end

-- ── divider — a white hairline (outlined by the pipeline) ─────────────────
-- opts: x, y, w · color? · spec?
function ui_divider(opts)
  ui_content_rect(opts.x, opts.y, opts.w, 1, opts.color or white, opts.spec)
  return ui_ret({ x = opts.x, y = opts.y, w = opts.w, h = 1 }, {})
end

-- ── item_icon — an emoji image centered in a rect ─────────────────────────
-- opts: rect · image · size (default fits the rect minus 4px) · fill
-- (optional token — draw a rounded tile behind the icon) · radius · spec?
function ui_item_icon(opts)
  local r = opts.rect
  if opts.fill then
    ui_fill_rrect(r.x, r.y, r.w, r.h, opts.radius or 2, opts.fill, opts.spec)
  end
  if opts.image then
    local size = opts.size or (math.min(r.w, r.h) - 4)
    ui_content_icon(opts.image, r.x + r.w/2, r.y + r.h/2, size, opts.spec)
  end
  return ui_ret(r, {})
end

-- ── label — the HUD chip: rounded fill + optional icon + text ─────────────
-- The Emoji Aimer draw_hud_chip, promoted to a toolkit element. Position-
-- only; auto-sizes from content.
-- opts: x, y · text · icon (image, optional) · font ('main' object default)
--       · fill (token, default fg) · text_color (default white) · gap
--       (icon→text, default 4) · min_text_w (fix the text region so ticking
--       digits don't twitch the chip) · pad_x (3) · pad_y (5) · spec?
function ui_label(opts)
  local font   = opts.font or fonts.main
  local str    = opts.text or ''
  local pad_x  = opts.pad_x or 3
  local pad_y  = opts.pad_y or 5
  local icon_w = opts.icon and 14 or 0
  local gap    = opts.icon and (opts.gap or 4) or 0
  local txt_w  = font:text_width(str)
  if opts.min_text_w and opts.min_text_w > txt_w then txt_w = opts.min_text_w end
  local w = pad_x + icon_w + gap + txt_w + pad_x
  local h = pad_y + math.max(icon_w, font.height) + pad_y
  local r = { x = opts.x, y = opts.y, w = w, h = h }

  ui_fill_rrect(r.x, r.y, r.w, r.h, opts.radius or 2, opts.fill or fg, opts.spec)
  if opts.icon then
    ui_content_icon(opts.icon, r.x + pad_x + icon_w/2, r.y + h/2, icon_w, opts.spec)
  end
  ui_text({ rect = { x = r.x + pad_x + icon_w + gap, y = r.y, w = txt_w, h = h },
            text = str, font = font, color = opts.text_color, spec = opts.spec })
  return ui_ret(r, {})
end

-- ── word wrap — greedy on whitespace (Aimer's wrap_text) ──────────────────
-- Words longer than max_w live on their own (over-wide) line. Returns an
-- array of line strings.
function ui_wrap_text(text, max_w, font)
  font = font or fonts.main
  local space_w = font:text_width(' ')
  local lines, cur, cur_w = {}, nil, 0
  for word in text:gmatch('%S+') do
    local word_w = font:text_width(word)
    if cur == nil then
      cur, cur_w = word, word_w
    elseif cur_w + space_w + word_w > max_w then
      lines[#lines + 1] = cur
      cur, cur_w = word, word_w
    else
      cur   = cur .. ' ' .. word
      cur_w = cur_w + space_w + word_w
    end
  end
  if cur then lines[#lines + 1] = cur end
  return lines
end

-- ── tooltip — Aimer's shop tooltip, generalized ───────────────────────────
-- WHITE rounded panel (radius 6) + a COLORED HEADER BAND (rounded top,
-- squared bottom via the notch trick) carrying the title left and an
-- optional [icon value] chip right. Body = word-wrapped white lines
-- (line_h 12, wrap width 130, min content width 130). Drawn on the TOP
-- tier so its outline never merges with the chrome it floats over.
-- Position with ui_tooltip_position (below) rather than hand-clamping.
-- opts: x, y · title · desc (string, wrapped) | lines (pre-split array) ·
--       header_color (token, default yellow) · value (string, optional) ·
--       value_icon (image, optional, 9px) · w (force width) · spec?
UI_TOOLTIP_PAD    = 6
UI_TOOLTIP_LINE_H = 12
UI_TOOLTIP_HEAD_H = 16
UI_TOOLTIP_MIN_W  = 130
UI_TOOLTIP_WRAP_W = 130

function ui_tooltip_size(opts)
  local pad   = UI_TOOLTIP_PAD
  local lines = opts.lines or (opts.desc and ui_wrap_text(opts.desc, UI_TOOLTIP_WRAP_W)) or {}
  local w = opts.w
  if not w then
    w = fonts.main:text_width(opts.title or '')
    if opts.value then
      w = w + 12 + (opts.value_icon and 12 or 0) + fonts.main:text_width(opts.value)
    end
    for _, l in ipairs(lines) do w = math.max(w, fonts.main:text_width(l)) end
    w = math.max(w + 2*pad, UI_TOOLTIP_MIN_W)
  end
  local h = UI_TOOLTIP_HEAD_H + pad + #lines*UI_TOOLTIP_LINE_H + pad
  return w, h, lines
end

function ui_tooltip(opts)
  local pad    = UI_TOOLTIP_PAD
  local head_h = UI_TOOLTIP_HEAD_H
  local rad    = 6
  local w, h, lines = ui_tooltip_size(opts)
  local x, y   = opts.x, opts.y
  local r      = { x = x, y = y, w = w, h = h }

  ui_tier('top')
  -- Panel + header band (rounded top corners, squared bottom via notches).
  ui_fill_rrect(x, y, w, h, rad, white, opts.spec)
  local head_col = opts.header_color or yellow
  ui_fill_rrect(x, y, w, head_h, rad, head_col, opts.spec)
  ui_fill_rect(x,           y + head_h - rad, rad, rad, head_col, opts.spec)
  ui_fill_rect(x + w - rad, y + head_h - rad, rad, rad, head_col, opts.spec)

  -- Header: title left, optional [icon value] chip right. The Aimer text-y
  -- recipe: floor(y + head_h/2 - 11/2 + 1) + 1.
  local head_ty = math.floor(y + head_h/2 - fonts.main.height/2 + 1) + 1
  ui_content_text(opts.title or '', fonts.main, x + pad, head_ty, white, opts.spec)
  if opts.value then
    local vs   = tostring(opts.value)
    local vs_w = fonts.main:text_width(vs)
    local ics  = opts.value_icon and 9 or 0
    local vx   = x + w - pad - (ics > 0 and ics + 3 or 0) - vs_w
    if opts.value_icon then
      ui_content_icon(opts.value_icon, math.floor(vx + ics/2), y + head_h/2, ics, opts.spec)
      vx = vx + ics + 3
    end
    ui_content_text(vs, fonts.main, vx, head_ty, white, opts.spec)
  end

  -- Body lines.
  local cy = y + head_h + pad
  for _, l in ipairs(lines) do
    ui_content_text(l, fonts.main, x + pad, cy, white, opts.spec)
    cy = cy + UI_TOOLTIP_LINE_H
  end
  ui_tier('base')
  return ui_ret(r, {})
end

-- ── tooltip anchoring — right of the element, flipped/clamped (Aimer) ─────
-- el is any {x, y, w, h}; pass the tooltip opts to measure. Returns x, y.
function ui_tooltip_position(el, opts)
  local tip_w, tip_h = ui_tooltip_size(opts)
  local gap, pad = 4, 4
  local x = el.x + el.w + gap
  local y = math.floor(el.y + el.h/2 - tip_h/2)
  if x + tip_w > gw - pad then x = el.x - tip_w - gap end
  if y + tip_h > gh - pad then y = gh - pad - tip_h   end
  if y < pad then y = pad end
  if x < pad then x = pad end
  return x, y
end
