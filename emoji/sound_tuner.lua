--[[
  emoji/sound_tuner.lua — THE sound tool (F3), the bank scope of KVP's merged
  F3/Q editor (Horse Game, 2026-08-01 era) ported here. KVP's ITEM scope (the
  per-item moment tree) needs an effect lab this game doesn't have yet — it
  stays behind; this file carries everything else:

    BANK (F3, anywhere): every DECLARED sound, one scrolling list — the game
      FREEZES while it is open (gate world updates on sound_tuner_paused()).
      Click a row to select + audition it. `*` = has a tuning entry;
      `~name` = member of a variant family.

    THE UNIFIED EDITOR (right column), for the selected sound:
      bits / sr     runtime bitcrush + sample-rate divide (the lo-fi DSP)
      vol           the key's volume (volumes[key], diff-saved)
      p.lo / p.hi   per-sound pitch range every play rolls inside
                    (default the classic 0.95-1.05; lo == hi = fixed)
      delay         ms; + delays the play, - starts INTO the clip (skips a
                    wind-up so the impact lands earlier)
      play / clean / mute (mute = SOUND_DISABLED: a muted variant makes its
      family re-roll among the rest; a muted single key is silent)

    DRAG-DROP IMPORT: drop an audio file onto the window while a row is
      selected — it converts (ogg byte-copy; else ffmpeg -q:a 10, full
      length, no trims), lands as assets/sounds/fx_<key>.ogg, replaces the
      key's sound live, and records WHERE IT CAME FROM in sound_overrides.lua
      (project root) — the attribution record for credits. Never lose `src`.

  Everything auto-saves: emoji/sound_tuning.lua (DSP + pitch + offset),
  emoji/volume_tuning.lua (volumes, diffed against the baseline snapshot),
  emoji/sound_mutes.lua (mutes), sound_overrides.lua (imports).

  Host wiring:
    bind('toggle_sound_tuner', 'key:f3')
    bind('ui_gallery_prev', 'key:[');  bind('ui_gallery_next', 'key:]')
    sound_declare(...) baselines, then sound_overrides_apply()
    -- in update(), after ui_begin(dt):
    sound_tuner_update(dt)
    -- and gate world updates on sound_tuner_paused()
]]

sound_tuner_active = false

function sound_tuner_paused()
  return sound_tuner_active
end

local bank_scroll = 0                -- wheel = 2 rows, [ / ] = a page
local selected = nil
local cur_bits, cur_div = 16, 1
local cur_vol = 1.0
local cur_off = 0     -- seconds; + delays the play, - starts further into the clip
local cur_pl, cur_ph = 0.95, 1.05    -- pitch range
local replay_cooldown = 0
local saved_flash_t = -1
local flash_msg, flash_t = nil, -1   -- import/mute feedback line
local ROWS = 16

local function tuner_flash(msg)
  flash_msg, flash_t = msg, time
  print('sound_tuner: ' .. msg)
end

-- ⚠ sound_keys(), not pairs(sounds): the bank lists every DECLARED key, and a
-- lazy table only contains what has already been played. Listing does not
-- load — a handle is fetched when a row is selected or auditioned.
local function sound_names()
  local names = {}
  for _, name in ipairs(sound_keys()) do
    if name ~= 'ui_pop' then names[#names + 1] = name end
  end
  return names
end

local function select_sound(name)
  selected = name
  local h = sounds[name]
  local tune = h and sound_tuning[sound_get_path(h)]
  cur_bits = tune and tune.bits     or 16
  cur_div  = tune and tune.sr_div   or 1
  cur_pl   = tune and tune.pitch_lo or 0.95
  cur_ph   = tune and tune.pitch_hi or 1.05
  cur_off  = tune and tune.offset   or 0
  cur_vol  = volumes[name] or 1.0
end

function sound_tuner_select(name) select_sound(name) end
function sound_tuner_selected()
  return sound_tuner_active and selected or nil
end

local function pitch_default()
  return math.abs(cur_pl - 0.95) < 0.001 and math.abs(cur_ph - 1.05) < 0.001
end

local function store_current()
  if not selected or not sounds[selected] then return end
  local path = sound_get_path(sounds[selected])
  if cur_bits >= 16 and cur_div <= 1 and pitch_default() and math.abs(cur_off) < 0.001 then
    sound_tuning[path] = nil     -- fully clean: no entry at all
  else
    sound_tuning[path] = { bits = cur_bits, sr_div = cur_div,
                           pitch_lo = (not pitch_default()) and cur_pl or nil,
                           pitch_hi = (not pitch_default()) and cur_ph or nil,
                           offset   = (math.abs(cur_off) >= 0.001) and cur_off or nil }
  end
end

local function serialize_tuning()
  local paths = {}
  for path in pairs(sound_tuning) do paths[#paths + 1] = path end
  table.sort(paths)
  local out = {
    '--[[',
    '  emoji/sound_tuning.lua — per-sound runtime DSP + pitch-range table,',
    '  consulted by sfx() on every play. Maps asset path -> { bits, sr_div,',
    '  pitch_lo?, pitch_hi?, offset? }. `offset` is seconds: positive DELAYS the',
    '  play, negative starts that far INTO the clip (skipping a wind-up), which',
    '  is the only way to make an impact land earlier. Auto-saved by the tool;',
    '  safe to edit by hand. Sounds without an entry play clean at the',
    '  0.95-1.05 jitter.',
    ']]',
    '',
    'return {',
  }
  for _, path in ipairs(paths) do
    local t = sound_tuning[path]
    local extra = ''
    if t.pitch_lo or t.pitch_hi then
      extra = string.format(', pitch_lo = %g, pitch_hi = %g',
                            t.pitch_lo or 0.95, t.pitch_hi or 1.05)
    end
    if t.offset then extra = extra .. string.format(', offset = %g', t.offset) end
    out[#out + 1] = string.format("  ['%s'] = { bits = %d, sr_div = %d%s },",
                                  path, t.bits, t.sr_div, extra)
  end
  out[#out + 1] = '}'
  return table.concat(out, '\n') .. '\n'
end

local function save_tuning()
  if file_write_string('emoji/sound_tuning.lua', serialize_tuning()) then
    saved_flash_t = time
  else
    print('sound tuner: FAILED to write emoji/sound_tuning.lua')
  end
end
sound_tuner_save_tuning = save_tuning

local function serialize_volumes()
  local out = {
    '--[[',
    '  emoji/volume_tuning.lua — per-sound volume overrides (gameplay-name key ->',
    '  volume). Auto-saved by the F3 sound tool; loaded on top of the baseline',
    '  volumes by volumes_apply_overrides(). Safe to edit by hand.',
    ']]',
    '',
    'return {',
  }
  local keys = {}
  for k, v in pairs(volumes) do
    local base = volumes_defaults and volumes_defaults[k]
    if base == nil or v ~= base then keys[#keys + 1] = k end
  end
  table.sort(keys)
  for _, k in ipairs(keys) do
    out[#out + 1] = string.format('  %s = %g,', k, volumes[k])
  end
  out[#out + 1] = '}'
  return table.concat(out, '\n') .. '\n'
end

local function save_volumes()
  if file_write_string('emoji/volume_tuning.lua', serialize_volumes()) then
    saved_flash_t = time
  else
    print('sound tuner: FAILED to write emoji/volume_tuning.lua')
  end
end
sound_tuner_save_volumes = save_volumes

-- ── mutes ────────────────────────────────────────────────────────────────────
local function save_mutes()
  local keys = {}
  for k, v in pairs(SOUND_DISABLED) do if v then keys[#keys + 1] = k end end
  table.sort(keys)
  local out = {
    '-- emoji/sound_mutes.lua — muted recordings (F3 sound tool). A muted',
    '-- variant drops out of its family roll; a muted single key is silent.',
    '-- Auto-saved; safe to edit by hand.',
    'return {',
  }
  for _, k in ipairs(keys) do out[#out + 1] = string.format('  %q,', k) end
  out[#out + 1] = '}'
  if file_write_string('emoji/sound_mutes.lua', table.concat(out, '\n') .. '\n') then
    saved_flash_t = time
  else
    print('sound tuner: FAILED to write emoji/sound_mutes.lua')
  end
end

function sound_toggle_muted(key)
  SOUND_DISABLED[key] = not SOUND_DISABLED[key] or nil
  save_mutes()
  tuner_flash((SOUND_DISABLED[key] and 'muted ' or 'unmuted ') .. key)
end

-- ── imports (drag-drop) ──────────────────────────────────────────────────────
-- sound_overrides.lua (project root): key = { file, src, at }. `file` is the
-- fx_<key>.ogg the drop was renamed to; `src` is the ORIGINAL path — the
-- attribution record for the credits. Never drop it when editing by hand.
SOUND_IMPORTS = {}
do
  local ok, t = pcall(dofile, 'sound_overrides.lua')
  if ok and type(t) == 'table' then SOUND_IMPORTS = t end
end

function sound_import_entry(k)
  local e = SOUND_IMPORTS[k]
  if type(e) == 'string' then return { file = e } end
  return e
end

local function imports_save()
  local f = io.open('sound_overrides.lua', 'w')
  if not f then print('sound tuner: cannot write sound_overrides.lua') return end
  f:write('-- imported sounds (F3 drag-drop): sounds.<key> = sound_load(<file>).\n')
  f:write('-- Applied by sound_overrides_apply() after the baseline declarations.\n')
  f:write('-- ⚠ `src` is the ORIGINAL file the drop renamed — the ATTRIBUTION record\n')
  f:write('--   for the credits. Never drop it when editing this file by hand.\n')
  f:write('return {\n')
  local keys = {}
  for k in pairs(SOUND_IMPORTS) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local e = sound_import_entry(k)
    f:write(('  %s = { file = %q'):format(k, e.file))
    if e.src then f:write((', src = %q'):format(e.src)) end
    if e.at  then f:write((', at = %q'):format(e.at))   end
    f:write(' },\n')
  end
  f:write('}\n')
  f:close()
end

-- Host call, ONCE, after the baseline sound_declare()s: re-points imported
-- keys at their fx_<key>.ogg files (lazy — nothing loads here).
function sound_overrides_apply()
  for k, _ in pairs(SOUND_IMPORTS) do
    local e = sound_import_entry(k)
    if e and e.file then sound_declare(k, e.file) end
  end
end

local function import_sound(src)
  local key = selected
  if not key then tuner_flash('select a row first, then drop') return end
  local ext = src:lower():match('%.([a-z0-9]+)$')
  if ext ~= 'ogg' and ext ~= 'wav' and ext ~= 'mp3' then
    tuner_flash('unsupported file type: ' .. tostring(ext))
    return
  end
  local dest = 'assets/sounds/fx_' .. key .. '.ogg'
  if ext == 'ogg' then
    -- already the house format: byte-copy, no re-encode
    local i = io.open(src, 'rb')
    if not i then tuner_flash('cannot read ' .. src) return end
    local data = i:read('*a'); i:close()
    local o = io.open(dest, 'wb')
    if not o then tuner_flash('cannot write ' .. dest) return end
    o:write(data); o:close()
  else
    -- the house conversion: -q:a 10, full length, all channels, no trims
    local cmd = ('ffmpeg -y -loglevel error -i "%s" -q:a 10 "%s"'):format(src, dest)
    local ok = os.execute(cmd)
    if not ok then tuner_flash('ffmpeg failed on ' .. src) return end
  end
  local probe = io.open(dest, 'rb')
  if not probe then tuner_flash('conversion produced nothing') return end
  probe:close()
  sound_declare(key, dest)                -- the drop is a declaration...
  rawset(sounds, key, sound_load(dest))   -- ...loaded eagerly: you dropped it to hear it now
  if volumes[key] == nil then
    volumes[key] = 0.5
    save_volumes()
  end
  SOUND_IMPORTS[key] = { file = dest, src = src, at = os.date('%Y-%m-%d') }
  imports_save()
  select_sound(key)
  tuner_flash(('%s <- %s'):format(key, src:match('[^\\/]+$') or src))
  sfx(sounds[key], volumes[key])
end

-- ── the tool ─────────────────────────────────────────────────────────────────
function sound_tuner_update(dt)
  if input_pressed('toggle_sound_tuner') then
    sound_tuner_active = not sound_tuner_active
    if sound_tuner_active then
      ui_gallery_active = false
      effect_lab_active = false
    end
  end
  if not sound_tuner_active then return end

  replay_cooldown = replay_cooldown - dt
  layer_rectangle(overlay_layer, 0, 0, gw, gh, bg_color())

  -- OS drag-and-drop: a dropped audio file lands in the selected row
  -- (first file only — variants go in one at a time, each auditioned)
  local drops = engine_get_drops and engine_get_drops() or {}
  for i, d in ipairs(drops) do
    if d.kind == 'file' then
      if i == 1 then import_sound(d.value)
      else tuner_flash('extra file ignored: ' .. (d.value:match('[^\\/]+$') or d.value)) end
    end
  end

  -- scrolling: wheel = 2 rows, [ / ] = a page
  local wheel_dy = 0
  if mouse_wheel then local _, wy = mouse_wheel(); wheel_dy = wy end
  local page_dy = 0
  if input_pressed('ui_gallery_prev') then page_dy = -1 end
  if input_pressed('ui_gallery_next') then page_dy =  1 end

  ui_text({ x = 16, y = 6, text = 'SOUNDS — bank', font = fonts.mid })
  ui_text({ x = 16, y = gh - 14,
            text = 'wheel or [ ] scrolls | drop a file on the selected row | f3 close',
            color = fg_dark })

  -- ── left: the bank list ─────────────────────────────────────────────────
  local list_x, list_y, list_w, row_hh = 16, 30, 180, 16
  ui_panel({ rect = { x = list_x, y = list_y, w = list_w,
                      h = ROWS*row_hh + 4 }, radius = 3 })
  local names = sound_names()
  local maxs  = math.max(0, #names - ROWS)
  bank_scroll = bank_scroll - wheel_dy*2 + page_dy*ROWS
  bank_scroll = math.max(0, math.min(bank_scroll, maxs))
  -- ⚠ rows stay on the FRAME'S OWN tier on purpose: their hover/selected
  -- fill merges into the panel silhouette and gets NO outline of its own
  -- (a highlight band is not an object — outlining it boxes every row).
  local ry = list_y + 2
  for i = 1, ROWS do
    local idx  = bank_scroll + i
    local name = names[idx]
    if not name then break end
    local tuned = (sound_is_loaded(name)
                   and sound_tuning[sound_get_path(sounds[name])]) and '*' or ''
    local fam = ''
    local mom = sound_moment_of(name)
    if mom ~= name and sound_family_n(mom) > 1 then fam = '  ~' .. mom end
    local muted = SOUND_DISABLED[name] and ' (muted)' or ''
    local lr = ui_list_row({
      rect = { x = list_x + 2, y = ry, w = list_w - 4, h = row_hh },
      id = 'tuner_row' .. i, selected = selected == name,
      cells = { { text = name .. tuned .. muted .. fam } } })
    if lr.clicked then
      select_sound(name)
      sfx_preview(sounds[name], cur_vol)
    end
    ry = ry + row_hh
  end
  ui_text({ x = list_x, y = list_y + ROWS*row_hh + 8,
            text = ('%d-%d of %d'):format(math.min(bank_scroll + 1, #names),
                    math.min(bank_scroll + ROWS, #names), #names), color = fg_dark })
  if flash_t > 0 and time - flash_t < 3 then
    ui_text({ x = list_x, y = list_y + ROWS*row_hh + 20,
              text = tostring(flash_msg):sub(1, 52), color = green })
  end

  -- ── right: the unified editor ──────────────────────────────────────────
  local rx = list_x + list_w + 16
  if selected then
    ui_text({ x = rx, y = 28, text = selected, font = fonts.main })
    local info = {}
    do
      local mom  = sound_moment_of(selected)
      local famn = sound_family_n(mom)
      if famn > 1 then info[#info + 1] = ('family %s x%d'):format(mom, famn) end
      if SOUND_DISABLED[selected] then info[#info + 1] = 'MUTED' end
      if not sounds[selected] then info[#info + 1] = 'empty - drop a file' end
    end
    if #info > 0 then
      ui_text({ x = rx, y = 39, text = table.concat(info, ' · '), color = fg_dark })
    end
    -- ⭐ THE ORIGIN LINE: an imported sound was renamed to fx_<key>.ogg on
    -- drop; this is the only surviving link to the original for credits.
    -- Optional content PUSHES the layout — the sliders start under it.
    local ry2 = 54
    local imp = sound_import_entry(selected)
    if imp then
      local from = imp.src and (imp.src:match('[^\\/]+$') or imp.src)
                   or '? (imported before origins were recorded)'
      ui_text({ x = rx, y = 50, text = 'from: ' .. from, color = fg_dark })
      ry2 = ry2 + 14
    end
    local h = sounds[selected]

    -- one row = label · slider · VALUE. The quantizer runs INSIDE, so the
    -- number shown is exactly the number stored.
    local function slider_row(y, label, cur, lo, hi, id, q, fmt)
      ui_text({ rect = { x = rx, y = y, w = 40, h = 12 }, text = label, color = fg_dark })
      local s = ui_slider({ rect = { x = rx + 44, y = y, w = 150, h = 12 },
                            value = math.remap(cur, lo, hi, 0, 1), id = id })
      local v = q(math.remap(s.value, 0, 1, lo, hi))
      ui_text({ rect = { x = rx + 200, y = y, w = 46, h = 12 },
                text = fmt:format(v), color = white })
      return v
    end
    local function q_int(v)  return math.floor(v + 0.5) end
    local function q_step(v) return math.floor(v/0.05 + 0.5)*0.05 end
    local q_ms = function(v) return math.floor(v/10 + 0.5)*10 end

    local nb = slider_row(ry2,      'bits',  cur_bits, 16, 1,  'tuner_bits', q_int,  '%d')
    local nd = slider_row(ry2 + 18, 'sr',    cur_div,  1,  8,  'tuner_div',  q_int,  '%d')
    local nv = slider_row(ry2 + 36, 'vol',   cur_vol,  0,  2,  'tuner_vol',  q_step, '%.2f')
    local pl = slider_row(ry2 + 54, 'p.lo',  cur_pl,   0.5, 2, 'tuner_plo',  q_step, '%.2f')
    local ph = slider_row(ry2 + 72, 'p.hi',  cur_ph,   0.5, 2, 'tuner_phi',  q_step, '%.2f')
    -- delay in ms, zero centred: left starts INTO the clip (impact earlier),
    -- right delays the whole play. 10ms steps.
    local noff = slider_row(ry2 + 90, 'delay', cur_off*1000, -500, 500, 'tuner_off', q_ms, '%dms')/1000
    if pl > ph then
      -- the moved handle pushes the other, never crosses
      if math.abs(pl - cur_pl) > 0.001 then ph = pl else pl = ph end
    end

    local dsp_changed = (nb ~= cur_bits or nd ~= cur_div
                         or math.abs(pl - cur_pl) > 0.001 or math.abs(ph - cur_ph) > 0.001)
    if dsp_changed then
      cur_bits, cur_div, cur_pl, cur_ph = nb, nd, pl, ph
      store_current()
      save_tuning()
      if h and replay_cooldown <= 0 then
        replay_cooldown = 0.2
        sfx_preview(h, cur_vol, random_float(cur_pl, cur_ph))
      end
    end
    if math.abs(noff - cur_off) > 0.0001 then
      cur_off = noff
      store_current()
      save_tuning()
      -- audition through the REAL path so a negative offset is actually heard
      -- as a shortened head; sfx_preview would play the raw file
      if h and replay_cooldown <= 0 then
        replay_cooldown = 0.25
        sfx(h, cur_vol)
      end
    end
    if math.abs(nv - cur_vol) > 0.001 then
      cur_vol = nv
      volumes[selected] = cur_vol
      save_volumes()
      if h and replay_cooldown <= 0 then
        replay_cooldown = 0.2
        sfx_preview(h, cur_vol)
      end
    end

    local by = ry2 + 112
    local b = ui_button({ x = rx, y = by, label = 'play', id = 'tuner_play',
                          variant = 'primary' })
    if b.clicked and h then sfx_preview(h, cur_vol, random_float(cur_pl, cur_ph)) end
    local c = ui_button({ x = b.next_x, y = by, label = 'clean', id = 'tuner_clean' })
    if c.clicked then
      cur_bits, cur_div, cur_pl, cur_ph, cur_off = 16, 1, 0.95, 1.05, 0
      store_current()
      save_tuning()
      if h then sfx_preview(h, cur_vol) end
    end
    local mlabel = SOUND_DISABLED[selected] and 'unmute' or 'mute'
    local mb = ui_button({ x = c.next_x, y = by, label = mlabel, id = 'tuner_mute' })
    if mb.clicked then sound_toggle_muted(selected) end
  else
    ui_text({ x = rx, y = 34, text = 'select a sound', color = fg_dark })
  end

  local saved = time - saved_flash_t < 1.2
  ui_text({ x = rx, y = gh - 44,
            text = saved and 'saved' or 'auto-saves (DSP + pitch + volume + mutes)',
            color = saved and green or fg_dark })
end
