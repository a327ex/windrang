--[[
  ui/gallery.lua — the F4 widget gallery: a paged, interactive showcase of
  every toolkit element, drawn over the running scene on a full-screen
  charcoal bg (overlay_layer — plain, so the fill takes no outline).

  Host wiring (the demo main.lua does this):
    bind('toggle_ui_gallery', 'key:f4')
    bind('ui_gallery_prev',   'key:[')
    bind('ui_gallery_next',   'key:]')
    -- in update(), after ui_begin(dt):
    ui_gallery_update(dt)
  While ui_gallery_active the host should suppress its own click actions
  (the demo guards its target hit-test on it).

  Pages own small demo state (checkbox values, a fake HP pool, the selected
  card) in the local `gal` table — throwaway, gallery-only.
]]

ui_gallery_active = false

local page  = 1
local pages = {}

-- Gallery demo state.
local gal = {
  chk_shake = true,
  chk_sfx   = false,
  slider    = 0.6,
  sel_row   = 2,
  field_i   = 1,
  hp        = 34,
  hp_max    = 40,
  sel_card  = 2,
  tab       = 1,
}
local field_values = { 'organic', 'plasma', 'waves', 'truchet' }

-- ── page 1: controls ──────────────────────────────────────────────────────
pages[#pages + 1] = { name = 'controls', draw = function(r)
  -- Tabs strip full-width up top, then two columns: buttons + form left,
  -- list right.
  local st = ui_stack(r, ui_sp.s3)
  st:heading('tabs')
  local tb = ui_tabs({ rect = { x = st.x, y = st:take(18).y, w = 272, h = 18 },
                       id = 'g_tabs', active = gal.tab,
                       labels = { 'TIER 1', 'TIER 2', 'TIER 3', 'TIER 4' },
                       disabled = { [4] = true } })
  gal.tab = tb.active

  local left  = ui_stack({ x = r.x,       y = st.y, w = 210 },        ui_sp.s3)
  local right = ui_stack({ x = r.x + 240, y = st.y, w = r.w - 240 },  ui_sp.s3)

  left:heading('buttons')
  local row = left:take(18)
  local b = ui_button({ x = row.x, y = row.y, label = 'play', id = 'g_play', variant = 'primary' })
  b = ui_button({ x = b.next_x, y = row.y, label = 'options', id = 'g_opts' })
  ui_button({ x = b.next_x, y = row.y, label = 'delete', id = 'g_del', variant = 'danger' })
  local row2 = left:take(18)
  b = ui_button({ x = row2.x, y = row2.y, label = 'ghost', id = 'g_ghost', variant = 'ghost' })
  ui_button({ x = b.next_x, y = row2.y, label = 'disabled', disabled = true })

  left:heading('form controls')
  local c1 = ui_checkbox({ x = left.x, y = left:take(12).y, label = 'screen shake',
                           checked = gal.chk_shake, id = 'g_chk1' })
  gal.chk_shake = c1.checked
  local c2 = ui_checkbox({ x = left.x, y = left:take(12).y, label = 'mute sfx',
                           checked = gal.chk_sfx, id = 'g_chk2' })
  gal.chk_sfx = c2.checked
  local sl = ui_slider({ rect = { x = left.x, y = left:take(14).y, w = 120, h = 14 },
                         value = gal.slider, id = 'g_slider' })
  gal.slider = sl.value
  local f = ui_field({ rect = { x = left.x, y = left:take(16).y, w = 170, h = 16 },
                       id = 'g_field', label = 'pattern',
                       value = field_values[gal.field_i] })
  if f.prev_clicked then gal.field_i = (gal.field_i - 2)%#field_values + 1 end
  if f.next_clicked then gal.field_i = gal.field_i%#field_values + 1 end

  right:heading('list')
  -- Rows sit FLUSH (no gaps) on a backing panel, so the selected/hover
  -- white fills are interior — no per-row outline box; the list block
  -- carries one clean silhouette (owner-picked look).
  local row_h  = 16
  local rows = { { 'slight smile', 'ball',   '12' },
                 { 'no mouth',     'target', '3'  },
                 { 'cloud',        'decor',  '-'  } }
  local list_r = { x = right.x, y = right.y, w = right.w,
                   h = (#rows + 1)*row_h + 4 }
  ui_panel({ rect = list_r, radius = 3 })
  local ry = list_r.y + 2
  ui_list_row({ rect = { x = list_r.x + 2, y = ry, w = list_r.w - 4, h = row_h },
                header = true,
                cells = { { text = 'name' }, { text = 'kind', w = 55 }, { text = 'hp', w = 25, align = 'right' } } })
  ry = ry + row_h
  for i, data in ipairs(rows) do
    local lr = ui_list_row({ rect = { x = list_r.x + 2, y = ry, w = list_r.w - 4, h = row_h },
                             id = 'g_row' .. i, selected = gal.sel_row == i,
                             cells = { { text = data[1] }, { text = data[2], w = 55 },
                                       { text = data[3], w = 25, align = 'right' } } })
    if lr.clicked then gal.sel_row = i end
    ry = ry + row_h
  end
end }

-- ── page 2: hud ───────────────────────────────────────────────────────────
pages[#pages + 1] = { name = 'hud', draw = function(r)
  local st = ui_stack(r, ui_sp.s3)
  st:heading('chips')
  local row = st:take(24)
  local ch = ui_label({ x = row.x, y = row.y, icon = star_img, text = '128', min_text_w = 24 })
  ch = ui_label({ x = ch.next_x, y = row.y, icon = slight_smile, text = 'x3' })
  ui_label({ x = ch.next_x, y = row.y, text = 'ROUND 2', fill = blue })

  st:heading('bars')
  ui_hud_bar({ x = st.x, y = st:take(12).y, w = 180, icon = star_img,
               value = gal.hp, max = gal.hp_max, color = red, id = 'g_hp' })
  ui_hud_bar({ x = st.x, y = st:take(12).y, w = 180, icon = cloud_img,
               frac = 0.7, value_text = '70', val_w = 24, color = blue })
  local row2 = st:take(18)
  local db = ui_button({ x = row2.x, y = row2.y, label = 'damage', id = 'g_dmg', variant = 'danger' })
  if db.clicked then
    gal.hp = gal.hp - random_int(4, 9)
    if gal.hp <= 0 then gal.hp = gal.hp_max end
  end
  if ui_button({ x = db.next_x, y = row2.y, label = 'heal', id = 'g_heal', variant = 'primary' }).clicked then
    gal.hp = math.min(gal.hp + 6, gal.hp_max)
  end

  st:heading('slots')
  local row3 = st:take(28)
  local s = ui_slot({ rect = { x = row3.x, y = row3.y, w = 28, h = 28 },
                      id = 'g_slot1', image = slight_smile, key = 'q' })
  s = ui_slot({ rect = { x = s.next_x, y = row3.y, w = 28, h = 28 },
                id = 'g_slot2', image = star_img, selected = true, key = 'w' })
  s = ui_slot({ rect = { x = s.next_x, y = row3.y, w = 28, h = 28 },
                id = 'g_slot3', image = no_mouth, cooldown = 0.55,
                cooldown_text = 3, key = 'e' })
  s = ui_slot({ rect = { x = s.next_x, y = row3.y, w = 28, h = 28 }, id = 'g_slot4' })
  ui_slot({ rect = { x = s.next_x, y = row3.y, w = 28, h = 28 },
            image = cloud_img, disabled = true })
end }

-- ── page 3: cards & tooltip ───────────────────────────────────────────────
-- The Aimer shop-tile idiom: 48×48 banner cards (yellow = buyable, gray =
-- can't afford, disabled = sold out) + the anchored header-band tooltip on
-- hover. Click to select (green frame).
pages[#pages + 1] = { name = 'cards', draw = function(r)
  local st = ui_stack(r, ui_sp.s3)
  st:heading('shop tiles (hover for tooltips)')
  local row = st:take(48)
  local defs = {
    { image = slight_smile, banner = 'SMILER', bc = yellow, price = '12',
      desc = 'the demo ball, at rest. bounces with joy and clicks right through.' },
    { image = no_mouth, banner = 'QUIET', bc = yellow, price = '25',
      desc = 'says nothing. takes three pokes before it goes.' },
    { image = star_img, banner = 'STAR', bc = gray, price = '80',
      desc = 'sparkles on every impact. you cannot afford this one yet.' },
    { image = cloud_img, banner = 'CLOUD', bc = yellow, price = '5',
      desc = 'drifts politely across the sky.', disabled = true },
  }
  local cx = row.x
  local hovered_i, hovered_rect = nil, nil
  for i, d in ipairs(defs) do
    local rect = { x = cx, y = row.y, w = 48, h = 48 }
    local c = ui_card({ rect = rect, id = 'g_card' .. i, image = d.image,
                        banner = d.banner, banner_color = d.bc,
                        disabled = d.disabled, selected = gal.sel_card == i })
    if c.clicked then gal.sel_card = i end
    if c.hovered then hovered_i, hovered_rect = i, rect end
    cx = c.next_x + ui_sp.s2
  end

  st:gap(ui_sp.s4)
  st:heading('taller card (desc lines)')
  local row2 = st:take(74)
  ui_card({ rect = { x = row2.x, y = row2.y, w = 64, h = 74 },
            id = 'g_card_tall', image = star_img, banner = 'EPIC',
            banner_color = blue,
            lines = { 'sparkles on', 'every impact' } })

  if hovered_i then
    local d = defs[hovered_i]
    local topts = { title = d.banner, desc = d.desc,
                    value = d.price, value_icon = star_img,
                    header_color = d.bc == gray and gray or yellow }
    local tx, ty = ui_tooltip_position(hovered_rect, topts)
    topts.x, topts.y = tx, ty
    ui_tooltip(topts)
  end
end }

-- Background modes — the backdrop changes how the chrome reads, so the
-- eye-test should happen in the REAL context. In Emoji Aimer the shop
-- chrome sits over the sky-gradient board and the cream wall columns,
-- not over raw charcoal.
--   board — charcoal page + inset sky-gradient board (the faithful
--           context, DEFAULT)
--   dark  — flat charcoal (the old look, kept for comparison)
--   live  — no fill; the running demo scene shows through
local bg_modes = { 'board', 'dark', 'live' }
local bg_mode  = 1

local function draw_gallery_bg()
  local mode = bg_modes[bg_mode]
  if mode == 'live' then return end
  layer_rectangle(overlay_layer, 0, 0, gw, gh, bg_color())
  if mode == 'board' then
    local m = 12
    layer_rectangle_gradient_v(overlay_layer, m, m, gw - 2*m, gh - 2*m,
                               sky_top(), sky_bottom())
  end
end

-- ── the update entry ──────────────────────────────────────────────────────
function ui_gallery_update(dt)
  if input_pressed('toggle_ui_gallery') then
    ui_gallery_active = not ui_gallery_active
    if ui_gallery_active then effect_lab_active = false end
  end
  if not ui_gallery_active then return end

  if input_pressed('ui_gallery_prev') then page = (page - 2)%#pages + 1 end
  if input_pressed('ui_gallery_next') then page = page%#pages + 1 end
  if input_pressed('ui_gallery_bg')   then bg_mode = bg_mode%#bg_modes + 1 end

  -- Bg on the plain overlay layer (no outline pass — never put a
  -- fullscreen fill on an outlined layer).
  draw_gallery_bg()

  -- Header: title left (Awesome — the display font), page indicator right,
  -- keys hint at the bottom.
  ui_text({ x = 16, y = 6, text = 'UI GALLERY', font = fonts.mid })
  ui_text({ rect = { x = gw - 116, y = 8, w = 100, h = fonts.main.height },
            text = string.format('%d/%d %s', page, #pages, pages[page].name),
            align_h = 'right', align_v = 'top', color = fg_dark })
  ui_text({ x = 16, y = gh - 14,
            text = '[ / ] page | b: bg (' .. bg_modes[bg_mode] .. ') | f4 close',
            color = fg_dark })

  pages[page].draw({ x = 16, y = 28, w = gw - 32, h = gh - 52 })
end
