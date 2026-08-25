--[[
  emoji/plants.lua — the family's reactive vegetation, at EBB's mechanics
  (the latest generation of the system; constants verbatim from
  emoji-ball-battles/main.lua:4560-4790, 1705-1763).

  A plant is an emoji sprite pivoting at its BASE whose rotation is the sum
  of independent channels:

    ambient   0.2*sin(1.4*t + 0.005*x)   — traveling wave (x = phase)
    moving    accel 80, cap 4            — something passing through
                                           (0.4-0.6s), THE KILL CHANNEL
    direct    accel 200, cap 6           — impacts (0.1-0.2s), snappy
    gust      (optional, invaders-era)   — plants_start_gust sweeps a
                                           left-to-right front (0.002*x
                                           onset stagger); EBB itself did
                                           not ship this channel

  All channel r/v decay with math.damping(0.9, 1, dt) (to 10% in 1s).
  Force intensities are jittered ±1/3 on application.

  DEATH (EBB): moving forces with can_kill (default true) count toward
  force_count; a moving force with |intensity| > 150 past force_count 5
  rolls remap(count, 5..15 → 0..100)% — on death the plant launches as a
  dying_plant (tumbling, damped, gravity-accruing, accelerating blink-out)
  and plays the pitched-up (1.3-1.4) grass "pluck" (nil-safe: silent until
  the game loads grass_land1-3).

  Spawning: plant_spawn_group(index, x, y) — EBB's 8 hand-authored cluster
  compositions verbatim (seedling/sheaf/blossom/tulip/four_leaf_clover,
  sizes 12-22, front/back split) — or plant_spawn_random_group(x, y).
  Requires plant_imgs = { seedling = img, ... } (emoji/init.lua loads them).

  Host contract:
    collection_update(plants, sdt)                 -- in update()
    plants_draw(game_layer, false)                 -- back plants, pre-entities
    plants_draw(game_layer, true)                  -- front plants, post-entities
  Interaction hooks (call from gameplay):
    plants_apply_moving(x, y, dir, intensity, radius?, can_kill?)
    plants_apply_direct(x, y, radius, vy)          -- EBB ground-impact push:
                                                   -- away from x, 75..25
                                                   -- falloff, scaled by |vy|/150
    plants_apply_direct_falloff(x, y, radius, max_i, min_i)  -- muzzle/zap form
    plants_start_gust(duration, force)
]]

plants = {}

-- ── terrain adapter (host-settable) ──────────────────────────────────────────
-- When set, spawned plants sit ON the surface — each cluster member samples
-- its own x (a group on a slope no longer floats/sinks at its edges) — and
-- tilt toward the surface normal by plants_tilt (1 = fully perpendicular,
-- the family's wall-plant convention generalized to slopes; 0 = always
-- vertical). nil = flat behavior, exactly as before.
--   plants_terrain = { height = fn(x) -> y, angle = fn(x) -> radians }
plants_terrain = nil
plants_tilt    = 1

-- =============================================================================
-- plant
-- =============================================================================
plant = class()

function plant:new(x, y, args)
  args = args or {}
  self.x, self.y = x, y
  self.image = args.image
  self.scale = (args.w or 14)/self.image.width
  self.front = args.front
  self.base_r = args.base_r or 0     -- rest tilt (surface normal on slopes)
  self.min_rotation = args.min_rotation
  self.max_rotation = args.max_rotation
  make_entity(self)

  -- moving channel (slower; the kill channel)
  self.moving_r, self.moving_v = 0, 0
  self.moving_accel      = 80
  self.base_moving_max_v = 4
  self.moving_max_v      = self.base_moving_max_v
  self.moving_until      = -1

  -- direct channel (faster, snappier)
  self.direct_r, self.direct_v = 0, 0
  self.direct_accel      = 200
  self.base_direct_max_v = 6
  self.direct_max_v      = self.base_direct_max_v
  self.direct_until      = -1

  -- optional gust channel (driven by the module-global gust front)
  self.gust_r, self.gust_v = 0, 0

  -- death tracking
  self.force_count     = 0
  self.force_threshold = 5
  self.dying           = false
end

local function step_channel(r, v, accel, max_v, applying, dt)
  if applying then
    if max_v > 0 then v = math.min(v + accel*dt, max_v)
    else              v = math.max(v - accel*dt, max_v) end
    r = r + v*dt
  end
  r = math.damping(0.9, 1, dt, r)
  v = math.damping(0.9, 1, dt, v)
  return r, v
end

function plant:update(dt)
  self.moving_r, self.moving_v = step_channel(self.moving_r, self.moving_v,
    self.moving_accel, self.moving_max_v, time < self.moving_until, dt)
  self.direct_r, self.direct_v = step_channel(self.direct_r, self.direct_v,
    self.direct_accel, self.direct_max_v, time < self.direct_until, dt)

  -- gust front: onset staggered 0.002*x so the wind visibly travels
  local onset = plants_gust.start_t + 0.002*self.x
  if time > onset and time < onset + plants_gust.duration then
    local cap = plants_gust.force/10
    self.gust_v = math.clamp(self.gust_v + random_float(0.6, 1.4)*40*dt, -cap, cap)
    self.gust_r = self.gust_r + random_float(0.6, 1.4)*self.gust_v*dt
  end
  self.gust_r = math.damping(0.9, 1, dt, self.gust_r)
  self.gust_v = math.damping(0.9, 1, dt, self.gust_v)
end

function plant:force_rotation()
  local force_r = self.moving_r + self.direct_r + self.gust_r
  if self.min_rotation and force_r < self.min_rotation then force_r = self.min_rotation end
  if self.max_rotation and force_r > self.max_rotation then force_r = self.max_rotation end
  return force_r
end

function plant:get_rotation()
  return self.base_r + 0.2*math.sin(1.4*time + 0.005*self.x) + self:force_rotation()
end

function plant:draw(layer)
  layer_push(layer, self.x, self.y, self:get_rotation(), self.scale, self.scale)
  layer_image(layer, self.image, 0, -self.image.height/2)
  layer_pop(layer)
end

-- Moving force: something passing through (slower, longer). THE kill path:
-- can_kill (default true) increments force_count; |intensity| > 150 past
-- the threshold rolls the death probability.
function plant:apply_moving_force(direction, intensity, can_kill)
  intensity = intensity or 50
  if can_kill == nil then can_kill = true end
  if can_kill then self.force_count = self.force_count + 1 end
  intensity = intensity + random_float(-intensity/3, intensity/3)
  self.moving_max_v = direction*math.remap(math.clamp(math.abs(intensity), 0, 150), 0, 150, 0, self.base_moving_max_v)
  self.moving_until = time + random_float(0.4, 0.6)

  if can_kill and math.abs(intensity) > 150 and self.force_count > self.force_threshold
     and not self.dying then
    local death_probability = math.remap(self.force_count, self.force_threshold,
                                         self.force_threshold + 10, 0, 100)
    if random_bool(death_probability/100) then
      self.dying = true
      sfx_any('grass_land', 3, 0.75, random_float(1.3, 1.4))   -- the pluck
      fxs[#fxs + 1] = dying_plant(self.x, self.y - self.image.height*self.scale/2, {
        image = self.image, scale = self.scale,
        rotation = self:get_rotation(),
        force_direction = direction, intensity = intensity,
      })
      self:kill()
    end
  end
end

-- Direct force: impact nearby (faster, shorter). Counts toward the
-- threshold but never kills by itself (EBB semantics).
function plant:apply_direct_force(direction, intensity)
  intensity = intensity or 50
  self.force_count = self.force_count + 1
  intensity = intensity + random_float(-intensity/3, intensity/3)
  self.direct_max_v = direction*math.remap(math.clamp(math.abs(intensity), 0, 100), 0, 100, 0, self.base_direct_max_v)
  self.direct_until = time + random_float(0.1, 0.2)
end

function plant:destroy() end

-- =============================================================================
-- dying_plant — EBB's tumbling remnant: launched along the killing force
-- with an upward bump, damped hard while gravity accrues, spinning from
-- the intensity, accelerating blink-out (0.1 → 0.03 steps). Lives in fxs.
-- =============================================================================
dying_plant = class()

function dying_plant:new(x, y, args)
  args = args or {}
  self.x, self.y = x, y
  self.image    = args.image
  self.scale    = args.scale or 1
  self.rotation = args.rotation or 0
  self.layer    = args.layer or effects_layer
  make_entity(self)
  self.timer = timer_new()

  local dir       = args.force_direction or 1
  local intensity = args.intensity or 150
  self.vx = dir*random_float(140, 240)
  self.vy = random_float(-200, -100)
  self.gravity = 0
  self.rv = dir*math.remap(math.clamp(intensity, 0, 150), 0, 150, 5, 25)*random_float(0.6, 2)

  self.hidden = false
  local blink_delay = random_float(0.3, 0.4)
  local total       = random_float(1, 2)
  timer_after(self.timer, blink_delay, function()
    timer_during_step(self.timer, total - blink_delay, 0.1, 0.03,
      function() self.hidden = not self.hidden end, nil,
      function() self:kill() end)
  end)
end

function dying_plant:update(dt)
  timer_update(self.timer, dt)
  self.vx = math.damping(0.9, 0.5, dt, self.vx)
  self.vy = math.damping(0.9, 0.5, dt, self.vy)
  self.rv = math.damping(0.9, 0.5, dt, self.rv)
  self.gravity = self.gravity + 128*dt
  self.x = self.x + self.vx*dt
  self.y = self.y + (self.vy + self.gravity)*dt
  self.rotation = self.rotation + self.rv*dt
end

function dying_plant:draw()
  if self.hidden then return end
  layer_push(self.layer, self.x, self.y, self.rotation, self.scale, self.scale)
  layer_image(self.layer, self.image, 0, 0)
  layer_pop(self.layer)
end

function dying_plant:destroy() end

-- =============================================================================
-- spawning — EBB's 8 cluster groups, verbatim compositions
-- =============================================================================
-- While a group spawns, spawn_group_y holds its anchor y so the recipes'
-- small y tweaks (y - 1, y - 2) survive the terrain resample as offsets.
local spawn_group_y = nil

local function add(x, y, species, w, front, min_rot)
  local base_r = 0
  if plants_terrain then
    local tweak = spawn_group_y and (y - spawn_group_y) or 0
    y = plants_terrain.height(x) + tweak
    base_r = (plants_terrain.angle(x) or 0)*plants_tilt
  end
  plants[#plants + 1] = plant(x, y, { image = plant_imgs[species], w = w,
                                      front = front, min_rotation = min_rot,
                                      base_r = base_r })
end

function plant_spawn_group(index, x, y)
  spawn_group_y = y
  if index == 1 then
    add(x - 4, y, 'seedling', 12, true)
    add(x + 4, y, 'sheaf',    16, true)
  elseif index == 2 then
    add(x - 4, y, 'seedling', 12, false)
    add(x + 4, y, 'seedling', 16, true)
  elseif index == 3 then
    add(x - 8, y, 'sheaf',    12, false)
    add(x + 0, y, 'seedling', 22, false)
    add(x + 8, y, 'sheaf',    16, false)
  elseif index == 4 then
    add(x - 6, y - 2, 'blossom',  22, true)
    add(x + 8, y,     'seedling', 12, false)
  elseif index == 5 then
    add(x - 12, y,     'sheaf',    18, false)
    add(x + 0,  y - 2, 'tulip',    22, true)
    add(x + 12, y,     'seedling', 14, true)
  elseif index == 6 then
    add(x - 16, y,     'sheaf',            16, true)
    add(x + 0,  y - 1, 'four_leaf_clover', 19, false, -0.15)
    add(x + 12, y,     'seedling',         14, true)
  elseif index == 7 then
    add(x - 16, y,     'sheaf',    16, true)
    add(x + 0,  y - 2, 'blossom',  22, false)
    add(x + 4,  y,     'seedling', 12, true)
    add(x + 14, y,     'seedling', 12, true)
    add(x + 30, y,     'sheaf',    16, true)
  elseif index == 8 then
    add(x - 20, y - 2, 'tulip', 16, true)
    add(x + 0,  y - 2, 'tulip', 22, true)
    add(x + 20, y - 2, 'tulip', 14, false)
  end
  spawn_group_y = nil
end

function plant_spawn_random_group(x, y)
  plant_spawn_group(random_int(1, 8), x, y)
end

function plants_clear()
  for _, p in ipairs(plants) do if not p._dead then p:kill() end end
  plants = {}
end

function plants_draw(layer, front)
  for _, p in ipairs(plants) do
    if not p._dead and (not p.front) == (not front) then p:draw(layer) end
  end
end

-- =============================================================================
-- interaction helpers
-- =============================================================================

-- Something passing through near (x, y): moving force in its travel
-- direction. This is the path that can mow plants down (intensity > 150).
function plants_apply_moving(x, y, dir, intensity, radius, can_kill)
  radius = radius or 25
  for _, p in ipairs(plants) do
    if not p._dead and math.abs(p.x - x) < radius and math.abs(p.y - y) < 40 then
      p:apply_moving_force(dir, intensity, can_kill)
    end
  end
end

-- EBB's ground-impact push: plants shove AWAY from the impact, closer =
-- harder (75..25), whole thing scaled by |vy|/150 (soft touches barely stir).
function plants_apply_direct(x, y, radius, vy)
  local vy_multiplier = math.min(1, math.remap(math.abs(vy or 150), 0, 150, 0, 1))
  for _, p in ipairs(plants) do
    if not p._dead then
      local dx = x - p.x
      if math.abs(dx) < radius and math.abs(p.y - y) < 40 then
        p:apply_direct_force(-math.sign(dx),
          math.remap(math.abs(dx), 0, radius, 75, 25)*vy_multiplier)
      end
    end
  end
end

-- The muzzle-blast / lightning form (invaders): away-push with an explicit
-- max_i..min_i falloff over the radius.
function plants_apply_direct_falloff(x, y, radius, max_i, min_i)
  for _, p in ipairs(plants) do
    if not p._dead then
      local dx = x - p.x
      if math.abs(dx) < radius and math.abs(p.y - y) < 40 then
        p:apply_direct_force(-math.sign(dx),
          math.remap(math.abs(dx), 0, radius, max_i or 100, min_i or 50))
      end
    end
  end
end

-- Optional gust front (invaders-era extra; EBB shipped without it).
plants_gust = { start_t = -100, duration = 0, force = 0 }

function plants_start_gust(duration, force)
  plants_gust.start_t  = time
  plants_gust.duration = duration or 2
  plants_gust.force    = force or 30
end
