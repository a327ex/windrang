--[[
  emoji/juice.lua — the cross-cutting feel conventions of the emoji games.

  Four pieces:

  1. hitfx — the spring + white-flash pair every interactive entity carries.
     hitfx_init(e) attaches the standard springs ('hit' uniform pop,
     'squash_x'/'squash_y' directional deform) to an entity that already has
     a .timer (timer_new) — it creates e.spring if absent and e.flashing.
     hitfx_hit(e, pull, flash_duration) is the standard "I got hit" reaction.
     Draw side: scale by e.spring.hit.x and pass
     `e.flashing and white()` as layer_image's flash arg.

  2. hitfx_squash — directional wall-impact deformation (from
     emoji-ball-bounce / EBB): squash perpendicular to the wall, stretch
     along it, with the opposite axis pulled at HALF magnitude for a
     teardrop-ish flatten. wall_hit_intensity(speed) is EBB's intensity
     curve (linear 0..800 speed, cubic_in_out below the midpoint,
     circ_in above).

  3. slow_mo — micro slow-motion for impact moments. slow_time(scale,
     restore_duration) dips the engine time_scale instantly and tweens it
     back to 1 (cubic_out). The host calls juice_update(dt) at the top of
     update(); it pushes slow_mo.scale into the engine and returns the
     SCALED dt the rest of update should use (`local sdt = juice_update(dt)`).
     The recovery tween itself runs on scaled time, so deep slows naturally
     stretch their real-time recovery — Emoji Aimer's choice, kept.

  4. camera_punch — the punch-in zoom that keeps the hit point fixed on
     screen (the world scales outward from the impact instead of the camera
     panning to it). Two-phase: 0.03s cubic_in punch, 0.5s cubic_out
     recover. Named tween, so back-to-back punches replace cleanly.

  Camera conventions (the host sets these up in main.lua — structural):
    main_camera = camera_new(gw, gh)
    shake_handcam(main_camera.shake, true, { x = 2, y = 2, rotation = 0.02 }, 0.5)
  and per-impact `shake_trauma(main_camera.shake, amount, duration, opts?)`
  — rotation-only trauma ({ x = 0, y = 0, rotation = 0.18, zoom = 0 }) is
  the crit "twist".

  Reference parameter values (from the emoji games' effects catalog):
    hit feedback   pull 0.2-0.3   flash 0.08-0.15s
    spawn flash    0.3-0.5s
    wall squash    0.4 * wall_hit_intensity(speed)
    springs        freq 3, bounce 0.5 (squash) / 0.7 (hit)
]]

juice_timer = timer_new()
slow_mo = { scale = 1.0 }

-- Attach the standard hitfx springs + flash flag to an entity. Requires
-- e.timer; creates e.spring if the entity doesn't have one yet.
function hitfx_init(e)
  e.spring = e.spring or spring_new()
  spring_add(e.spring, 'hit',      1, 3, 0.7)
  spring_add(e.spring, 'squash_x', 1, 3, 0.5)
  spring_add(e.spring, 'squash_y', 1, 3, 0.5)
  e.flashing = false
end

-- The standard hit reaction: uniform pop + white flash. Pass
-- flash_duration = false to pop without flashing.
function hitfx_hit(e, pull, flash_duration)
  spring_pull(e.spring, 'hit', pull or 0.3, 3, 0.5)
  if flash_duration ~= false then
    e.flashing = true
    timer_after(e.timer, flash_duration or 0.1, 'hitfx_flash', function()
      e.flashing = false
    end)
  end
end

-- Directional deformation on wall hits: squash perpendicular to the wall,
-- stretch along it. Hitting a horizontal wall (floor/ceiling) stretches x
-- and compresses y; a vertical wall does the opposite. The opposite-axis
-- pull is half the magnitude — EBB's teardrop flatten.
function hitfx_squash(e, normal_x, normal_y, amount)
  amount = amount or 0.3
  if math.abs(normal_y) > math.abs(normal_x) then
    spring_pull(e.spring, 'squash_x',  amount,      3, 0.5)
    spring_pull(e.spring, 'squash_y', -amount*0.5,  3, 0.5)
  else
    spring_pull(e.spring, 'squash_y',  amount,      3, 0.5)
    spring_pull(e.spring, 'squash_x', -amount*0.5,  3, 0.5)
  end
end

-- EBB's wall-impact intensity curve: linear in the 0..800 speed range,
-- shaped cubic_in_out below the midpoint (gentle at low speeds), circ_in
-- above (sharper as speed climbs). Multiply into the squash amount.
function wall_hit_intensity(speed)
  local intensity = math.clamp(math.remap(speed, 0, 800, 0, 1), 0, 1)
  if intensity < 0.5 then
    return 0.5*math.cubic_in_out(intensity/0.5)
  else
    return 0.5 + 0.5*math.circ_in((intensity - 0.5)/0.5)
  end
end

-- Instant dip of the game's time_scale to `scale`, cubic_out back to 1
-- over restore_duration. Defensive snap at the end so replaced/drifted
-- tweens still land at exactly 1.0.
function slow_time(scale, restore_duration)
  slow_mo.scale = scale
  timer_tween(juice_timer, restore_duration, 'slow_time',
              slow_mo, { scale = 1.0 }, math.cubic_out, function()
    slow_mo.scale = 1.0
    set_time_scale(1.0)
  end)
end

-- Call at the top of update(); returns the scaled dt for everything else.
-- The unscaled timer ticks on RAW dt — it's what lets hitstop restore
-- itself while scaled time is frozen at zero.
juice_unscaled_timer = timer_new()

function juice_update(dt)
  timer_update(juice_unscaled_timer, dt)
  set_time_scale(slow_mo.scale)
  local sdt = dt*slow_mo.scale
  timer_update(juice_timer, sdt)
  return sdt
end

-- =============================================================================
-- hitstop — EBB's frozen frame + recency gate. hitstop(d) zeroes the time
-- scale and restores it on the unscaled timer. try_hitstop(d) rolls EBB's
-- anti-fatigue probability: 0 if a stop fired < 0.75s ago, quint_out ramp
-- to certain at 1.5s of quiet — flurries stay smooth, isolated hits slam.
-- =============================================================================
last_hitstop_time = -10

function hitstop_probability()
  local t = (time - last_hitstop_time)/1.5
  if t < 0.5 then return 0 end
  return math.quint_out(math.remap(math.clamp(t, 0.5, 1), 0.5, 1, 0, 1))
end

function hitstop(duration)
  slow_mo.scale = 0
  timer_after(juice_unscaled_timer, duration, 'hitstop', function()
    slow_mo.scale = 1
    set_time_scale(1)
  end)
end

function try_hitstop(duration)
  if random_bool(hitstop_probability()) then
    last_hitstop_time = time
    hitstop(duration)
    return true
  end
  return false
end

-- =============================================================================
-- the two slams (soundless — the host plays its chord after the call)
-- =============================================================================

-- Reward slam (Emoji Aimer's dagger-kill sandwich): slow-mo + rotation-only
-- trauma + punch-zoom solved around the point + big hit effect + red burst.
function reward_slam(cam, x, y, opts)
  opts = opts or {}
  slow_time(opts.slow or 0.33, opts.slow_restore or 0.5)
  shake_trauma(cam.shake, opts.trauma or 1.0, opts.trauma_duration or 0.5,
               { x = 0, y = 0, rotation = 0.18, zoom = 0 })
  camera_punch(cam, x, y, opts.zoom or 1.5, opts.zoom_restore or 0.5)
  spawn_hit_effect(x, y, { s = opts.effect_scale or 1.5 })
  for i = 1, random_int(6, 9) do
    spawn_hit_particle(x, y, {
      velocity = random_float(140, 320), direction = random_angle(),
      duration = random_float(0.3, 0.7), color = opts.color or red,
      gravity = random_float(256, 512),
      w = random_float(8, 14), h = random_float(4, 8),
      flash_on_spawn = true,
    })
  end
end

-- Hurt slam (the family's player-hit package): half-speed for a second +
-- noise trauma. Blink/i-frames stay host-side (they're entity state).
function hurt_slam(cam, opts)
  opts = opts or {}
  slow_time(opts.slow or 0.5, opts.slow_restore or 1.0)
  shake_trauma(cam.shake, opts.trauma or 0.5, opts.trauma_duration or 0.4)
end

-- =============================================================================
-- landing squash — the family grammar: stretch x / flatten y, both remapped
-- from impact speed (0..1000 → 0..1 / -0.2..0), on a stiffer spring.
-- =============================================================================
function hitfx_land(e, impact_vy)
  spring_pull(e.spring, 'squash_x', math.remap(impact_vy, 0, 1000, 0, 1),    6, 0.5)
  spring_pull(e.spring, 'squash_y', math.remap(impact_vy, 0, 1000, -0.2, 0), 6, 0.5)
end

-- =============================================================================
-- telegraph — the charge-up grammar (invaders aliens/clouds): over the
-- duration the entity swells toward 1.2, its flash color climbs black→white
-- and its scale jitters. telegraph_start drives e.charging/e.charge_t on
-- e.timer (tag 'telegraph'); read the draw side with telegraph_draw_state.
-- =============================================================================
function telegraph_start(e, duration, on_release)
  e.charging = true
  e.charge_t = 0
  timer_tween(e.timer, duration, 'telegraph', e, { charge_t = 1 }, math.linear,
              function()
    e.charging = false
    e.charge_t = 0
    on_release()
  end)
end

-- Returns swell (scale multiplier incl. jitter) and the flash color (packed,
-- or nil) for the current frame. Entity flash (e.flashing) wins over charge.
function telegraph_draw_state(e)
  local jitter = e.charging and random_float(0, 0.05) or 0
  local swell  = 1 + 0.2*(e.charge_t or 0) + jitter
  local flash  = nil
  if e.flashing then flash = white()
  elseif e.charging then flash = color_mix(black, white, e.charge_t)() end
  return swell, flash
end

-- =============================================================================
-- blink-out despawn — the universal debris expiry: toggle e.hidden, then
-- kill. Fixed cadence by default (dagger/wall-debris: 7 toggles at 0.035s);
-- pass accelerate = {duration, start_step, end_step} for the EBB corpse
-- variant (0.1s steps tightening to 0.03s).
-- =============================================================================
function blink_out(e, opts)
  opts = opts or {}
  if opts.accelerate then
    local a = opts.accelerate
    timer_during_step(e.timer, a[1], a[2] or 0.1, a[3] or 0.03, 'blink',
      function() e.hidden = not e.hidden end, nil, function() e:kill() end)
  else
    local toggles = 0
    local total   = opts.toggles or 7
    timer_every(e.timer, opts.interval or 0.035, 'blink', function()
      e.hidden = not e.hidden
      toggles = toggles + 1
      if toggles >= total then e:kill() end
    end)
  end
end

-- Punch-in zoom fixing the world point (x, y) at its current screen pixel —
-- the camera position is solved so the hit point stays put and the rest of
-- the world scales outward from it.
function camera_punch(cam, x, y, zoom, restore_duration)
  zoom = zoom or 1.5
  local punch_cx = x - (x - width/2)/zoom
  local punch_cy = y - (y - height/2)/zoom
  timer_tween(juice_timer, 0.03, 'punch_zoom', cam,
    { x = punch_cx, y = punch_cy, zoom = zoom }, math.cubic_in, function()
    timer_tween(juice_timer, restore_duration or 0.5, 'punch_zoom', cam,
      { x = width/2, y = height/2, zoom = 1.0 }, math.cubic_out)
  end)
end
