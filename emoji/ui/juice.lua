--[[
  ui/juice.lua — per-widget retained juice. Ported from snkrx-template
  (architecture + tuning unchanged; the bar tween is Emoji Aimer's own
  cash-register mechanic coming home).

  Immediate-mode widgets are pure functions — these registries are where
  their springs and eased values live, keyed by explicit widget id:

    ui_juice[id]     = { spring, was_hovered }   -- hover/click bounce
    ui_bar_juice[id] = { front, back, shown_value, y_offset, ... }

  Lifecycle:
    ui_juice_update(dt)                    — tick (ui_begin runs this)
    ui_juice_hover(id, hov, clickable?, rect?) — hover-edge bounce + sound
    ui_juice_pull(id, force, rect?)        — kick a spring (on click)
    ui_juice_scale(id) -> num              — current widget scale
    ui_bar_feed(id, frac, value)           — the two-bar HP tween

  AREA-SCALED INTENSITY: passing `rect` scales the pull by
  sqrt(900 / area) clamped to [0.3, 1.0] — big elements pop gently.
]]

ui_juice     = {}
ui_bar_juice = {}

-- Shared scheduler for the bar tweens; entries named per bar id so a
-- fresh hit replaces the in-flight tween.
ui_timer = timer_new()

local BAR_FRONT_DUR  = 0.18
local BAR_BACK_DELAY = 0.15
local BAR_BACK_DUR   = 0.5
local BAR_VALUE_DUR  = 0.35

-- The cash-register kick: on damage the whole bar drops BAR_KICK px
-- instantly, then returns linearly to 0.
local BAR_KICK     = 4
local BAR_KICK_DUR = 0.25

-- UI scale-spring tuning — softer than the framework defaults.
local UI_SPRING_FREQ   = 3
local UI_SPRING_BOUNCE = 0.4

local AREA_BASELINE = 900   -- ~30×30 (a slot) = full intensity
local function area_scale(rect)
  if not rect then return 1 end
  local a = rect.w*rect.h
  if a <= 0 then return 1 end
  return math.max(0.3, math.min(1, math.sqrt(AREA_BASELINE/a)))
end

local function entry(id)
  local e = ui_juice[id]
  if not e then
    local sp = spring_new()
    spring_add(sp, 'main', 1, UI_SPRING_FREQ, UI_SPRING_BOUNCE)
    -- Per-element hover wobble: a tiny handcam shake (Emoji Aimer's shop
    -- values — ±2px, rotation 0.05, no zoom, freq 1.0) faded in/out by
    -- hover_amount so the element drifts while hovered and settles when
    -- left. Random phase so neighboring elements don't wobble in sync.
    local sh = shake_new()
    shake_handcam(sh, true, { x = 2, y = 2, rotation = 0.05, zoom = 0 }, 1.0)
    sh.handcam_time = random_float(0, 100)
    e = { spring = sp, shake = sh, was_hovered = false,
          hover_amount = 0, hover_target = 0 }
    ui_juice[id] = e
  end
  return e
end

function ui_juice_update(dt)
  for _, e in pairs(ui_juice) do
    spring_update(e.spring, dt)
    shake_update(e.shake, dt)
    e.hover_amount = e.hover_amount + (e.hover_target - e.hover_amount)*dt*10
  end
  if ui_counter_update then ui_counter_update(dt) end
  timer_update(ui_timer, dt)
end

function ui_juice_scale(id)
  return entry(id).spring.main.x
end

-- Full hover transform for widget `id`: wobble offsets + rotation (shake
-- scaled by the hover fade) and the spring scale. Widgets push
-- (cx + ox, cy + oy, rot, s, s) — Aimer's shop-tile treatment.
function ui_juice_transform(id)
  if not id then return 0, 0, 0, 1 end
  local e = entry(id)
  local ox, oy, rot = shake_get_effects(e.shake)
  return ox*e.hover_amount, oy*e.hover_amount, rot*e.hover_amount,
         e.spring.main.x
end

function ui_juice_pull(id, force, rect)
  spring_pull(entry(id).spring, 'main', (force or 0.2)*area_scale(rect))
end

-- Hover-enter edge: a GENTLE pulse (Aimer's 0.08 — the wobble carries the
-- hover feel, not the pop), the hover sound, and a sympathetic cursor
-- pulse. hover_target drives the wobble fade every frame.
function ui_juice_hover(id, hovered, clickable, rect)
  local e = entry(id)
  if hovered and not e.was_hovered then
    spring_pull(e.spring, 'main', 0.08)
    sfx(sounds.ui_hover, 0.5, random_float(1.3, 1.5))
    if clickable ~= false then
      sfx(sounds.ui_pop, 0.5, random_float(0.95, 1.05))
    end
    if the_cursor then the_cursor:pulse() end
  end
  e.hover_target = hovered and 1 or 0
  e.was_hovered  = hovered
end

--[[
  ui_value_feed(id, value) -> shown, kick
  The cash-register grammar for a plain number chip (Emoji Aimer's gold
  counter): the displayed value scrubs toward the real one with cubic_out,
  and on any change the chip kicks down 4px, returning linearly. Draw the
  chip at y + kick with math.floor(shown + 0.5).
]]
ui_value_juice = {}

function ui_value_feed(id, value)
  local v = ui_value_juice[id]
  if not v then
    v = { shown = value, kick = 0, target = value }
    ui_value_juice[id] = v
    return v.shown, v.kick
  end
  if value ~= v.target then
    v.target = value
    timer_tween(ui_timer, 0.3, 'value_scrub_' .. id, v, { shown = value }, math.cubic_out)
    v.kick = 4
    timer_tween(ui_timer, 0.25, 'value_kick_' .. id, v, { kick = 0 }, math.linear)
  end
  return v.shown, v.kick
end

--[[
  ui_counter_feed(id, value, n) -> oys, scale
  The 2022-family counter grammar (guncraft/emojian's emoji_value_ui): on
  a value change, each of the n display elements (icon, digits, ...) drops
  oy = 3 in a 0.03s-per-element stagger and tweens back linearly over 0.2s,
  while a shared spring double-taps (0.3 then 0.15). Draw element i at
  y + oys[i], scaled by `scale`.
]]
ui_counter_juice = {}

function ui_counter_feed(id, value, n)
  n = n or 2
  local c = ui_counter_juice[id]
  if not c then
    c = { oys = {}, target = value, spring = spring_new() }
    spring_add(c.spring, 'main', 1, UI_SPRING_FREQ, UI_SPRING_BOUNCE)
    for i = 1, n do c.oys[i] = 0 end
    ui_counter_juice[id] = c
  end
  for i = #c.oys + 1, n do c.oys[i] = 0 end
  if value ~= c.target then
    c.target = value
    spring_pull(c.spring, 'main', 0.3)
    timer_after(ui_timer, 0.1, 'counter_tap_' .. id, function()
      spring_pull(c.spring, 'main', 0.15)
    end)
    for i = 1, n do
      timer_after(ui_timer, (i - 1)*0.03, 'counter_drop_' .. id .. i, function()
        c.oys[i] = 3
        timer_tween(ui_timer, 0.2, 'counter_rise_' .. id .. i,
                    c.oys, { [i] = 0 }, math.linear)
      end)
    end
  end
  return c.oys, c.spring.main.x
end

function ui_counter_update(dt)
  for _, c in pairs(ui_counter_juice) do spring_update(c.spring, dt) end
end

--[[
  ui_bar_feed(id, frac, value) -> front, back, shown_value, y_offset
  The v1/Emoji-Aimer HP tween: fast front bar, delayed slow white back bar
  exposing the lost chunk, counting-down value, and the cash-register kick
  on drops (heals follow up together, no kick). Named timer entries per id
  so overlapping damage chains smoothly.
]]
function ui_bar_feed(id, frac, value)
  local b = ui_bar_juice[id]
  if not b then
    b = { front = frac, back = frac, shown_value = value, y_offset = 0,
          target = frac, target_value = value }
    ui_bar_juice[id] = b
    return b.front, b.back, b.shown_value, b.y_offset
  end

  if math.abs(frac - b.target) > 0.0001 then
    local heal = frac > b.target
    b.target       = frac
    b.target_value = value

    timer_tween(ui_timer, BAR_FRONT_DUR, 'bar_front_' .. id,
      b, { front = frac }, math.cubic_out)
    timer_tween(ui_timer, BAR_VALUE_DUR, 'bar_value_' .. id,
      b, { shown_value = value }, math.cubic_out)

    if heal then
      timer_cancel(ui_timer, 'bar_back_' .. id)
      timer_tween(ui_timer, BAR_FRONT_DUR, 'bar_backtween_' .. id,
        b, { back = frac }, math.cubic_out)
    else
      b.y_offset = BAR_KICK
      timer_tween(ui_timer, BAR_KICK_DUR, 'bar_kick_' .. id,
        b, { y_offset = 0 }, math.linear)
      timer_after(ui_timer, BAR_BACK_DELAY, 'bar_back_' .. id, function()
        timer_tween(ui_timer, BAR_BACK_DUR, 'bar_backtween_' .. id,
          b, { back = frac }, math.cubic_in_out)
      end)
    end
  end

  return b.front, b.back, b.shown_value, b.y_offset
end
