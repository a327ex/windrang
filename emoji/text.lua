--[[
  emoji/text.lua — the family's inline text-effect markup + the payout
  typewriter ledger.

  ── rich text ────────────────────────────────────────────────────────────
  Markup: '[text](tag1, tag2)' — untagged runs draw plain. Tags:

    <color name>       any palette global ('yellow', 'red', 'fg_dark'...)
    wavy1..wavy4       per-char sine bob, amplitudes 0.25/0.5/0.75/2 at
                       freqs 2/3/3/4, phase-offset by char index (the 2022
                       engines' exact tables)
    <color>_flash      fg/white for 0.15s after (re)start, then the color
    typewriter         chars reveal at 0.025s per char from (re)start
    shake              per-char ±1px jitter

    rt = rich_text_new('press [play](yellow, wavy2) to [begin](typewriter)', fonts.main)
    rich_text_draw(rt, ui_content_layer, x, y)      -- top-left anchored
    rich_text_restart(rt)                            -- re-arm timed tags
  rt.w is the total pixel width (for centering).

  ── ui_ledger ────────────────────────────────────────────────────────────
  Emoji Aimer's payout screen generalized: lines drop in (6px settle) on a
  0.4s stagger and typewrite left-to-right segment by segment (label →
  amount → detail) at 50 chars/s; a click during the reveal skips to done.

    led = ui_ledger_new({ { 'WAVES CLEARED', '5' },
                          { 'GOLD EARNED', '23', 'nice' } })
    ui_ledger_update(led, dt, x, y, w)   -- draws; led.finished when revealed
    (host advances on its own click once led.finished)
]]

-- ── parsing ───────────────────────────────────────────────────────────────
local wavy_params = {
  wavy1 = { 0.25, 2 }, wavy2 = { 0.5, 3 }, wavy3 = { 0.75, 3 }, wavy4 = { 2, 4 },
}

local function resolve_tags(tag_str)
  local tags = {}
  for tag in tag_str:gmatch('[^,%s]+') do
    if wavy_params[tag] then
      tags.wavy = wavy_params[tag]
    elseif tag == 'typewriter' then
      tags.typewriter = true
    elseif tag == 'shake' then
      tags.shake = true
    elseif tag:sub(-6) == '_flash' then
      local c = _G[tag:sub(1, -7)]
      if type(c) == 'table' and c.r then tags.flash_color = c end
    else
      local c = _G[tag]
      if type(c) == 'table' and c.r then tags.color = c end
    end
  end
  return tags
end

function rich_text_new(str, font)
  font = font or fonts.main
  local rt = { chars = {}, font = font, t0 = time, w = 0 }
  local pos = 1
  while pos <= #str do
    local s, e, text, tag_str = str:find('%[(.-)%]%((.-)%)', pos)
    if not s then
      for i = pos, #str do
        rt.chars[#rt.chars + 1] = { ch = str:sub(i, i), tags = {} }
      end
      break
    end
    for i = pos, s - 1 do
      rt.chars[#rt.chars + 1] = { ch = str:sub(i, i), tags = {} }
    end
    local tags = resolve_tags(tag_str)
    for i = 1, #text do
      rt.chars[#rt.chars + 1] = { ch = text:sub(i, i), tags = tags }
    end
    pos = e + 1
  end
  for _, c in ipairs(rt.chars) do
    c.w = font:text_width(c.ch)
    rt.w = rt.w + c.w
  end
  return rt
end

function rich_text_restart(rt)
  rt.t0 = time
end

function rich_text_draw(rt, layer, x, y)
  local cx = x
  local elapsed = time - rt.t0
  for i, c in ipairs(rt.chars) do
    local t = c.tags
    local visible = true
    if t.typewriter and elapsed < (i - 1)*0.025 then visible = false end
    if visible then
      local oy, ox = 0, 0
      if t.wavy then oy = t.wavy[1]*math.sin(t.wavy[2]*time + i) end
      if t.shake then
        ox = random_float(-1, 1)
        oy = oy + random_float(-1, 1)
      end
      local col = t.color or white
      if t.flash_color then
        col = elapsed < 0.15 and fg or t.flash_color
      end
      layer_text(layer, c.ch, rt.font, cx + ox, y + oy, col())
    end
    cx = cx + c.w
  end
end

-- ── ui_ledger ─────────────────────────────────────────────────────────────
local LINE_STAGGER = 0.4
local CHAR_TIME    = 0.02      -- 50 chars/s
local DROP_TIME    = 0.2
local LINE_H       = 14

function ui_ledger_new(lines, opts)
  opts = opts or {}
  local led = { lines = {}, t = 0, finished = false, skip_t = nil }
  local total_t = 0
  for i, l in ipairs(lines) do
    local label, amount, detail = l[1], tostring(l[2] or ''), l[3]
    local start_t = (i - 1)*LINE_STAGGER
    local type_t  = (#label + #amount + #(detail or ''))*CHAR_TIME
    led.lines[#led.lines + 1] = {
      label = label, amount = amount, detail = detail, start_t = start_t,
    }
    total_t = math.max(total_t, start_t + type_t)
  end
  led.full_t = total_t
  return led
end

-- Draws label left / amount right of label column / detail after, revealing
-- per the elapsed clock. Click while revealing → jump to done.
function ui_ledger_update(led, dt, x, y, w)
  led.t = led.t + dt
  if not led.finished and input_pressed('click') and led.t > 0.15 then
    led.t = led.full_t + 1
  end
  if led.t >= led.full_t then led.finished = true end

  for i, l in ipairs(led.lines) do
    local lt = led.t - l.start_t
    if lt > 0 then
      local drop = 6*(1 - math.cubic_out(math.clamp(lt/DROP_TIME, 0, 1)))
      local ly   = y + (i - 1)*LINE_H + drop

      -- sequential reveal: label chars, then amount, then detail
      local chars = math.floor(lt/CHAR_TIME)
      local label = l.label:sub(1, chars)
      layer_text(ui_content_layer, label, fonts.main, x, ly, white())
      chars = chars - #l.label
      if chars > 0 then
        local amount = l.amount:sub(1, chars)
        layer_text(ui_content_layer, amount, fonts.main,
                   x + w - 60, ly, yellow())
        chars = chars - #l.amount
        if chars > 0 and l.detail then
          layer_text(ui_content_layer, l.detail:sub(1, chars), fonts.main,
                     x + w - 60 + fonts.main:text_width(l.amount) + 8, ly, fg_dark())
        end
      end
    end
  end
  return led.finished
end
