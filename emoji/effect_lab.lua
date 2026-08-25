--[[
  emoji/effect_lab.lua — the F5 effect inspector. The eye-testing surface
  for the four-axis system (pattern × color × dither × deco): a canvas of
  sample drawables — each with its own live spec — and a two-tab inspector
  panel (BASE: pattern/color/dither + tokens + modifiers; DECO: the
  decoration layer's shape/driver/knobs).

  Samples draw on overlay_layer (plain — no outline pass, so you judge the
  raw effect) through the effect_* single-call wrappers. Sample 2 is the
  DECO showcase (screentone dots fading along a gradient over a flat base);
  sample 4 is an emoji in image-as-content luminance mode — set its deco
  with driver 'main' and the dots get SIZED by the image's own luminance
  (dot-halftone of a real image).

  Host wiring (demo main.lua):
    bind('toggle_effect_lab', 'key:f5')
    -- in update(), after ui_begin(dt):
    effect_lab_update(dt)
  Scene clicks should be suppressed while effect_lab_active (the demo's
  guard covers it). Opening the lab closes the F4 gallery and vice versa.

  Controls: click a sample to select it (corner marks); tabs switch the
  panel page; DUMP prints the spec as a paste-ready Lua literal AND copies
  it to the clipboard (for baking eye-tested specs).
]]

effect_lab_active = false

local PANEL_W = 152

-- Sample drawables — each spec starts from a different illustrative
-- default. All axis fields explicit so the cyclers step from a known state.
local samples = {
  { kind = 'rrect', w = 64, h = 64,
    spec = { pattern = 'organic', color = 'mix', dither = 'off',
             deco = 'none', deco2 = 'none',
             color_a = 'green', color_b = 'blue', pattern_scale = 0.3 } },
  -- The deco showcase: flat blue base, darker screentone dots whose size
  -- fades along the main linear gradient (color='solid' ignores f, so the
  -- pattern is free to drive the deco). Layer 2 starts off — stack big
  -- outlined circles on it from the 'dec 2' tab.
  { kind = 'rect', w = 88, h = 88,
    spec = { pattern = 'linear_gradient', color = 'solid', dither = 'off',
             color_a = 'blue', deco = 'circle', deco_size = 7, deco_pitch = 13,
             deco_size_var = 1, deco_shade = -0.14, deco2 = 'none' } },
  { kind = 'circle', w = 64, h = 64,
    spec = { pattern = 'plasma', color = 'ramp', dither = 'off',
             deco = 'none', deco2 = 'none',
             color_a = 'red', color_b = 'orange', pattern_scale = 0.4 } },
  { kind = 'image', w = 72, h = 72,
    spec = { pattern = 'solid', color = 'mix', dither = 'cluster_6',
             deco = 'none', deco2 = 'none',
             color_a = 'bg_color', color_b = 'white', pattern_scale = 0.3,
             image_field = true } },
}
local selected = 2
local tab      = 1        -- 1 = base, 2 = deco

local function layout_samples()
  local cx0 = PANEL_W + (gw - PANEL_W)/2
  local cy0 = gh/2
  local pitch = 96
  local pos = {
    { cx0 - pitch/2 - 8, cy0 - pitch/2 - 2 },
    { cx0 + pitch/2 + 8, cy0 - pitch/2 - 2 },
    { cx0 - pitch/2 - 8, cy0 + pitch/2 + 2 },
    { cx0 + pitch/2 + 8, cy0 + pitch/2 + 2 },
  }
  for i, s in ipairs(samples) do
    s.x = pos[i][1] - s.w/2
    s.y = pos[i][2] - s.h/2
  end
end
local laid_out = false

-- Serialize a spec as a paste-ready Lua literal, print + clipboard.
local function dump_spec(spec)
  local parts = {}
  for _, k in ipairs({ 'pattern', 'color', 'dither', 'color_a', 'color_b',
                       'pattern_scale', 'speed', 'contrast', 'value',
                       'pattern_param', 'pattern_param2', 'image_field',
                       'deco', 'deco_size', 'deco_size_var', 'deco_pitch',
                       'deco_rotation', 'deco_rotation_var', 'deco_jitter',
                       'deco_outline', 'deco_color_mode', 'deco_shade',
                       'deco_color', 'deco_color_b',
                       'deco_driver', 'deco_driver_scale', 'deco_driver_speed',
                       'deco2', 'deco2_size', 'deco2_size_var', 'deco2_pitch',
                       'deco2_rotation', 'deco2_rotation_var', 'deco2_jitter',
                       'deco2_outline', 'deco2_color_mode', 'deco2_shade',
                       'deco2_color', 'deco2_color_b',
                       'deco2_driver', 'deco2_driver_scale', 'deco2_driver_speed' }) do
    local v = spec[k]
    if v ~= nil then
      if type(v) == 'string' then
        parts[#parts + 1] = k .. " = '" .. v .. "'"
      elseif type(v) == 'number' then
        parts[#parts + 1] = k .. ' = ' .. string.format('%.3g', v)
      elseif type(v) == 'boolean' then
        parts[#parts + 1] = k .. ' = ' .. tostring(v)
      end
    end
  end
  local out = '{ ' .. table.concat(parts, ', ') .. ' }'
  print('[effect_lab] ' .. out)
  pcall(clipboard_set, out)
end

-- One label + slider row inside the inspector stack; maps 0..1 → [lo, hi].
local function slider_row(st, label, id, value, lo, hi, fmt)
  local row = st:take(12)
  ui_text({ rect = { x = row.x, y = row.y, w = 46, h = row.h },
            text = label, color = fg_dark })
  ui_text({ rect = { x = row.x + row.w - 34, y = row.y, w = 34, h = row.h },
            text = string.format(fmt or '%.2f', value), align_h = 'right' })
  local sl = ui_slider({ rect = { x = row.x + 48, y = row.y, w = row.w - 48 - 38, h = row.h },
                         id = id, value = (value - lo)/(hi - lo) })
  return lo + sl.value*(hi - lo)
end

local function base_page(st, spec)
  local f = ui_field({ rect = st:take(14), id = 'el_pattern', label = 'pat',
                       value = spec.pattern })
  if f.prev_clicked then spec.pattern = effect_prev_pattern(spec.pattern) end
  if f.next_clicked then spec.pattern = effect_next_pattern(spec.pattern) end

  f = ui_field({ rect = st:take(14), id = 'el_color', label = 'col',
                 value = spec.color })
  if f.prev_clicked then spec.color = effect_prev_color(spec.color) end
  if f.next_clicked then spec.color = effect_next_color(spec.color) end

  f = ui_field({ rect = st:take(14), id = 'el_dither', label = 'dit',
                 value = effect_dither_label(spec.dither) })
  if f.prev_clicked then spec.dither = effect_prev_dither(spec.dither) end
  if f.next_clicked then spec.dither = effect_next_dither(spec.dither) end

  st:gap(3)
  st:sublabel('color a / b')
  local grid_h = ui_swatch_grid_height(#palette_token_names, st.w, 9)
  local sw = ui_swatch_row({ rect = st:take(grid_h), id = 'el_ca',
                             selected = spec.color_a, size = 9 })
  if sw.clicked then spec.color_a = sw.token end
  sw = ui_swatch_row({ rect = st:take(grid_h), id = 'el_cb',
                       selected = spec.color_b, size = 9 })
  if sw.clicked then spec.color_b = sw.token end

  st:gap(3)
  spec.pattern_scale = slider_row(st, 'scale', 'el_scale',
    spec.pattern_scale or 0.15, 0.02, 1.5)
  spec.speed = slider_row(st, 'speed', 'el_speed', spec.speed or 1.0, 0, 3)
  spec.contrast = slider_row(st, 'contr', 'el_contrast', spec.contrast or 1.0, 0, 3)
end

-- One deco layer's page. `L` = 1 or 2; layer 1 fields use the 'deco' spec
-- prefix, layer 2 'deco2'. Widget ids carry the layer suffix so the two
-- pages keep independent juice/drag state.
local deco_color_mode_cycle = { 'shade', 'solid', 'across', 'inside', 'flow' }

local function deco_page(st, spec, L)
  local K = (L == 1) and 'deco' or 'deco2'
  local function get(name) return spec[K .. '_' .. name] end
  local function set(name, v) spec[K .. '_' .. name] = v end
  local id = 'el' .. L .. '_'

  local f = ui_field({ rect = st:take(14), id = id .. 'deco', label = 'deco',
                       value = effect_deco_label(spec[K]) })
  if f.prev_clicked then spec[K] = effect_prev_deco(spec[K]) end
  if f.next_clicked then spec[K] = effect_next_deco(spec[K]) end
  if spec[K] == 'sprite' and not get('icon') then
    set('icon', star_img)   -- default stamp so the kind shows something
  end

  f = ui_field({ rect = st:take(14), id = id .. 'driver', label = 'drv',
                 value = get('driver') or 'main' })
  if f.prev_clicked then
    local new = effect_prev_deco_driver(get('driver') or 'main')
    set('driver', (new ~= 'main') and new or nil)
  end
  if f.next_clicked then
    local new = effect_next_deco_driver(get('driver') or 'main')
    set('driver', (new ~= 'main') and new or nil)
  end

  -- Color mode + its conditional controls: shade slider, or token grid(s).
  local mode = get('color_mode') or (get('color') and 'solid' or 'shade')
  f = ui_field({ rect = st:take(14), id = id .. 'cmode', label = 'color',
                 value = mode })
  local mi = 1
  for i, m in ipairs(deco_color_mode_cycle) do if m == mode then mi = i end end
  if f.prev_clicked then mode = deco_color_mode_cycle[(mi - 2)%#deco_color_mode_cycle + 1]; set('color_mode', mode) end
  if f.next_clicked then mode = deco_color_mode_cycle[mi%#deco_color_mode_cycle + 1];       set('color_mode', mode) end

  if mode == 'shade' then
    set('shade', slider_row(st, 'shade', id .. 'shade', get('shade') or -0.12, -0.5, 0.5))
  else
    local grid_h = ui_swatch_grid_height(#palette_token_names, st.w, 8)
    local sw = ui_swatch_row({ rect = st:take(grid_h), id = id .. 'ca',
                               selected = get('color') or 'white', size = 8, gap = 3 })
    if sw.clicked then set('color', sw.token) end
    if mode ~= 'solid' then
      sw = ui_swatch_row({ rect = st:take(grid_h), id = id .. 'cb',
                           selected = get('color_b') or 'fg', size = 8, gap = 3 })
      if sw.clicked then set('color_b', sw.token) end
    end
  end

  st:gap(3)
  set('size',  slider_row(st, 'size',  id .. 'size',  get('size') or 10, 1, 32, '%.0f'))
  set('pitch', slider_row(st, 'pitch', id .. 'pitch', get('pitch') or 22, 4, 48, '%.0f'))
  set('size_var', slider_row(st, 'var', id .. 'var', get('size_var') or 0, 0, 1))
  set('jitter', slider_row(st, 'jitter', id .. 'jit', get('jitter') or 0, 0, 1))
  set('outline', slider_row(st, 'outln', id .. 'outl', get('outline') or 0, 0, 6, '%.1f'))
  set('rotation_var', slider_row(st, 'rotvar', id .. 'rotv', get('rotation_var') or 0, 0, 1))
  if get('driver') then
    set('driver_scale', slider_row(st, 'drvscl', id .. 'drvs',
      get('driver_scale') or 0.3, 0.02, 1.5))
  end
end

function effect_lab_update(dt)
  if input_pressed('toggle_effect_lab') then
    effect_lab_active = not effect_lab_active
    if effect_lab_active then ui_gallery_active = false end
  end
  if not effect_lab_active then return end
  if not laid_out then layout_samples(); laid_out = true end

  -- Bg + samples on the plain overlay layer (raw effect, no outline).
  layer_rectangle(overlay_layer, 0, 0, gw, gh, bg_color())
  for i, s in ipairs(samples) do
    if s.kind == 'rect' then
      effect_rectangle(overlay_layer, s.x, s.y, s.w, s.h, s.spec)
    elseif s.kind == 'rrect' then
      effect_rounded_rectangle(overlay_layer, s.x, s.y, s.w, s.h, 6, s.spec)
    elseif s.kind == 'circle' then
      effect_circle(overlay_layer, s.x + s.w/2, s.y + s.h/2, s.w/2, s.spec)
    elseif s.kind == 'image' then
      effect_image(overlay_layer, slight_smile, s.x, s.y, s.w, s.h, s.spec)
    end
  end

  -- Selection corner marks (white Ls) around the selected sample.
  do
    local s   = samples[selected]
    local m   = 4
    local arm = 7
    local x1, y1 = s.x - m, s.y - m
    local x2, y2 = s.x + s.w + m, s.y + s.h + m
    local col = white()
    layer_rectangle(overlay_layer, x1, y1, arm, 2, col)
    layer_rectangle(overlay_layer, x1, y1, 2, arm, col)
    layer_rectangle(overlay_layer, x2 - arm, y1, arm, 2, col)
    layer_rectangle(overlay_layer, x2 - 2, y1, 2, arm, col)
    layer_rectangle(overlay_layer, x1, y2 - 2, arm, 2, col)
    layer_rectangle(overlay_layer, x1, y2 - arm, 2, arm, col)
    layer_rectangle(overlay_layer, x2 - arm, y2 - 2, arm, 2, col)
    layer_rectangle(overlay_layer, x2 - 2, y2 - arm, 2, arm, col)
  end

  -- Sample selection: click right of the panel.
  if input_pressed('click') then
    local mx, my = mouse_position()
    if mx > PANEL_W then
      for i, s in ipairs(samples) do
        if mx >= s.x - 6 and mx <= s.x + s.w + 6 and
           my >= s.y - 6 and my <= s.y + s.h + 6 then
          selected = i
          break
        end
      end
    end
  end

  -- ── inspector panel ──────────────────────────────────────────────────
  local spec = samples[selected].spec
  ui_panel({ rect = { x = 4, y = 4, w = PANEL_W - 8, h = gh - 8 } })
  local st = ui_stack({ x = 12, y = 10, w = PANEL_W - 24 }, 2)
  st:heading('effect lab')

  local tb = ui_tabs({ rect = st:take(16), id = 'el_tabs', active = tab,
                       labels = { 'base', 'dec 1', 'dec 2' } })
  tab = tb.active
  st:gap(2)

  if tab == 1 then
    base_page(st, spec)
  else
    deco_page(st, spec, tab - 1)
  end

  st:gap(4)
  local row = st:take(16)
  if ui_button({ rect = { x = row.x, y = row.y, w = 52, h = 16 },
                 id = 'el_dump', label = 'dump' }).clicked then
    dump_spec(spec)
  end
  ui_text({ rect = { x = row.x + 58, y = row.y, w = st.w - 58, h = 16 },
            text = 'f5 close', color = fg_dark })
end
