--[[
  windrang — WIND RANG variation. Slice 2: hop-player on the terrain.

  Movement is ToTeMoJi's slope-solved hop controller (no stack, no hurt).
  A/D hop-walk, W/Up/Space jump. R re-rolls plants + clouds and respawns.
]]

require('anchor')({
  width  = 640,
  height = 360,
  title  = 'windrang',
  scale  = 2,
  filter = 'rough',
})

gw, gh = width, height

require('emoji')

-- -----------------------------------------------------------------------------
-- constants — ToTeMoJi / invaders hop values
-- -----------------------------------------------------------------------------
MOVE_MAX_V      = 128
HOP_VY          = -90
JUMP_VY         = -300
JUMP_CUT_TRAVEL = 34
JUMP_CUT_VY     = -65
GRAVITY_Y       = 685
HARD_LAND_VY    = 200

SQUASH          = 1.8

HOP_T         = 2*(-HOP_VY)/GRAVITY_Y
HOP_L         = MOVE_MAX_V*HOP_T
HOP_MAX_GRADE = math.tan(math.rad(50))
HOP_DOWNHILL  = 0.4

PLAYER_RADIUS    = 10.5
DUST_TERRAIN_MIX = 0.5

ROLL_TARGET_V    = 360   -- motor cruise: throttle fades to 0 here, never reverses
ROLL_ACCEL       = 720   -- ground motor accel along the slope
ROLL_AIR_ACCEL   = 360   -- air x motor
ROLL_FLOAT_ACCEL = 370   -- air y vs gravity while holding up
ROLL_AIR_SMOOTH  = 0.15  -- seconds to cover 90% of an air-thrust change
ROLL_FRICTION    = 0.40  -- low so a fall onto a downhill keeps its tangent speed
ROLL_RESTITUTION = 0.25  -- Box2D bounce on land; mix is max(player, terrain)
ROLL_JUMP_VY     = -200  -- roll jump impulse (hop still uses JUMP_VY)

-- -----------------------------------------------------------------------------
-- physics
-- -----------------------------------------------------------------------------
physics_init()
physics_set_gravity(0, GRAVITY_Y)
physics_register_tag('player')
physics_register_tag('solid')
physics_enable_collision('player', 'solid')

-- -----------------------------------------------------------------------------
-- input
-- -----------------------------------------------------------------------------
bind('left',  'key:a');  bind('left',  'key:left')
bind('right', 'key:d');  bind('right', 'key:right')
bind('jump',  'key:w');  bind('jump',  'key:up');  bind('jump', 'key:space')
bind('down',  'key:s');  bind('down',  'key:down')
bind('restart', 'key:r')
bind('toggle_mode', 'mouse:1')
bind('toggle_tweak', 'key:f1')
bind('toggle_sound_tuner', 'key:f3')
bind('ui_gallery_prev', 'key:[')
bind('ui_gallery_next', 'key:]')

-- -----------------------------------------------------------------------------
-- layers (ToTeMoJi order: back plants, terrain+entities, front plants +
-- duplicate terrain face so feet/bases sink behind the lip)
-- -----------------------------------------------------------------------------
emoji_layers({
  { 'bg' },
  { 'bg_plants',      outline = true },
  { 'game',           outline = true, shadow = true },
  { 'cover',          outline = true },
  { 'effects',        outline = true, shadow = true },
  { 'overlay' },
  { 'ui_panel',       outline = true },
  { 'ui_content',     outline = true },
  { 'ui_top_panel',   outline = true },
  { 'ui_top_content', outline = true },
})

main_camera = camera_new(gw, gh)
main_camera.x, main_camera.y = gw/2, gh/2

dizzy_img = image_load('dizzy', 'assets/dizzy.png')

for _, n in ipairs({ 'hop', 'grass_land1', 'grass_land2', 'grass_land3',
                     'land_impact' }) do
  sound_declare(n, 'assets/sounds/' .. n .. '.ogg')
end
sound_overrides_apply()
volumes.hop         = 0.15
volumes.grass_land1 = 0.35
volumes.grass_land2 = 0.35
volumes.grass_land3 = 0.35
volumes.land_impact = 0.4
volumes_apply_overrides()

-- -----------------------------------------------------------------------------
-- the terrain — ONE continuous surface polyline, x = 0..640.
-- High ground at both side walls, a rolling center-left hill, the meadow,
-- a right-side climb. Slopes stay under ~40°.
--
--   collider  a single static Box2D chain: down the left wall face, across
--             the surface, up the right wall face. One shape = no internal
--             seams. v3 chains are ONE-SIDED: this winding puts normals
--             into the play area.
--   draw      one quad per segment down to y=480, extended past both walls
--             so camera shake never exposes the void. Same fill drawn again
--             on the cover layer (the feet-sink depth trick).
-- -----------------------------------------------------------------------------
TERRAIN = {
  { 0,   232 }, { 34,  238 }, { 66,  254 }, { 96,  278 }, { 124, 294 },
  { 150, 296 },
  { 176, 278 }, { 200, 264 }, { 224, 260 },
  { 248, 268 }, { 272, 288 }, { 296, 308 },
  { 324, 318 }, { 360, 322 }, { 400, 318 },
  { 440, 323 }, { 480, 318 }, { 516, 320 },
  { 540, 310 }, { 568, 292 }, { 596, 270 },
  { 620, 250 }, { 640, 236 },
}
TERRAIN_WALL_TOP = -80
TERRAIN_BOTTOM   = 480

function terrain_height(x)
  if x <= TERRAIN[1][1] then return TERRAIN[1][2] end
  local last = TERRAIN[#TERRAIN]
  if x >= last[1] then return last[2] end
  for i = 2, #TERRAIN do
    local a, b = TERRAIN[i - 1], TERRAIN[i]
    if x <= b[1] then
      return math.remap(x, a[1], b[1], a[2], b[2])
    end
  end
  return last[2]
end

function terrain_angle(x)
  local last = TERRAIN[#TERRAIN]
  if x <= TERRAIN[1][1] then x = TERRAIN[1][1] + 0.01 end
  if x >= last[1] then x = last[1] - 0.01 end
  for i = 2, #TERRAIN do
    local a, b = TERRAIN[i - 1], TERRAIN[i]
    if x <= b[1] then return math.atan(b[2] - a[2], b[1] - a[1]) end
  end
  return 0
end

function terrain_walk(x0, dir, dist)
  local first_x, last_x = TERRAIN[1][1], TERRAIN[#TERRAIN][1]
  local x = math.clamp(x0, first_x, last_x)
  local remaining = dist
  while remaining > 0 do
    local a, b
    if dir > 0 then
      if x >= last_x then return last_x end
      for i = 2, #TERRAIN do
        if x < TERRAIN[i][1] then a, b = TERRAIN[i - 1], TERRAIN[i] break end
      end
    else
      if x <= first_x then return first_x end
      for i = #TERRAIN - 1, 1, -1 do
        if x > TERRAIN[i][1] then a, b = TERRAIN[i], TERRAIN[i + 1] break end
      end
    end
    local seg_dx  = b[1] - a[1]
    local seg_dy  = b[2] - a[2]
    local cos_t   = seg_dx/math.sqrt(seg_dx*seg_dx + seg_dy*seg_dy)
    local edge_x  = dir > 0 and b[1] or a[1]
    local avail   = math.abs(edge_x - x)/cos_t
    if remaining <= avail then
      return x + dir*remaining*cos_t
    end
    remaining = remaining - avail
    x = edge_x
  end
  return x
end

terrain = nil

terrain_body = class()

function terrain_body:new()
  make_entity(self)
  local verts = { TERRAIN[1][1], TERRAIN_WALL_TOP }
  for _, p in ipairs(TERRAIN) do
    verts[#verts + 1] = p[1]
    verts[#verts + 1] = p[2]
  end
  local last = TERRAIN[#TERRAIN]
  verts[#verts + 1] = last[1]
  verts[#verts + 1] = TERRAIN_WALL_TOP
  self.collider = collider(self, 'solid', 'static', 'chain', verts, false)
  self.collider:set_position(0, 0)
  self.collider:set_friction(ROLL_FRICTION, self.collider.chain)

  self.strip = { { TERRAIN[1][1] - 40, TERRAIN[1][2] } }
  for _, p in ipairs(TERRAIN) do self.strip[#self.strip + 1] = p end
  self.strip[#self.strip + 1] = { last[1] + 40, last[2] }
end

function terrain_body:update(dt) end

function terrain_body:draw(layer)
  local c = green()
  for i = 2, #self.strip do
    local a, b = self.strip[i - 1], self.strip[i]
    layer_polygon(layer, { a[1], a[2], b[1], b[2],
                           b[1], TERRAIN_BOTTOM, a[1], TERRAIN_BOTTOM }, c)
  end
end

function terrain_body:destroy()
  self.collider:destroy()
end

-- -----------------------------------------------------------------------------
-- clouds — family sky dressing: drifting + wrapping, soft-tinted, on bg.
-- -----------------------------------------------------------------------------
clouds     = {}
cloud_tint = color(255, 255, 255, 150)

function build_clouds(n)
  clouds = {}
  for i = 1, n do
    local x, y
    for attempt = 1, 20 do
      x = random_float(20, gw - 20)
      y = random_float(16, 110)
      local ok = true
      for _, c in ipairs(clouds) do
        if math.abs(c.x - x) < 70 and math.abs(c.y - y) < 30 then ok = false break end
      end
      if ok then break end
    end
    clouds[#clouds + 1] = {
      x = x, y = y,
      speed = random_float(4, 8),
      scale = random_float(30, 44)/cloud_img.width,
    }
  end
end

local function clouds_update(dt)
  for _, c in ipairs(clouds) do
    c.x = c.x + c.speed*dt
    local w = cloud_img.width*c.scale
    if c.x - w/2 > gw then c.x = -w/2 end
  end
end

local function clouds_draw()
  for _, c in ipairs(clouds) do
    layer_push(bg_layer, c.x, c.y, 0, c.scale, c.scale)
    layer_image(bg_layer, cloud_img, 0, 0, cloud_tint())
    layer_pop(bg_layer)
  end
end

-- -----------------------------------------------------------------------------
-- player — two modes (left click toggles; default roll):
--   hop  ToTeMoJi's slope-solved hop controller
--   roll physics circle: force along the ground, free rotation, gravity
-- -----------------------------------------------------------------------------
player = class()

function player:new(x, y)
  self.x, self.y = x, y
  make_entity(self)
  self.timer = timer_new()
  hitfx_init(self)
  self.collider = collider(self, 'player', 'dynamic', 'circle', PLAYER_RADIUS)
  self.collider:set_position(x, y)
  self.collider:set_restitution(0)  -- hop stays 0; roll applies ROLL_RESTITUTION
  self.mode = 'roll'
  self:reset_state()
  self:set_mode('roll')
end

function player:reset_state()
  self.direction     = 0
  self.speed         = 0
  self.moving_left   = true
  self.moving_right  = true
  self.movement_jump = true
  self.can_jump      = true
  self.jumping       = true
  self.bouncing      = false
  self.jump_y        = 0
  self.grounded      = false
  self.air_t         = 0
  self.hop_active    = false
  self.hop_launch_t  = -1
  self.visual_r      = 0
  self.last_vy       = 0
  self.dizzy_until   = -1
  self.roll_ax       = 0    -- smoothed air thrust (px/s^2)
  self.roll_ay       = 0
end

function player:set_mode(mode)
  self.mode = mode
  if mode == 'roll' then
    self.collider:set_fixed_rotation(false)
    self.collider:set_friction(ROLL_FRICTION)
    self.collider:set_restitution(ROLL_RESTITUTION)
    self.collider:set_gravity_scale(1)
    self.collider:set_linear_damping(0)
    self.collider:set_angular_damping(0)
    self.collider:set_bullet(true)
    self.collider:set_awake(true)
  else
    self.collider:set_fixed_rotation(true)
    self.collider:set_friction(0)
    self.collider:set_restitution(0)
    self.collider:set_angular_velocity(0)
    self.collider:set_angle(0)
    self.visual_r = 0
    self.hop_active = false
    self.speed = 0
  end
end

function player:do_hop(dir)
  self.movement_jump = false
  self.direction     = dir
  local T      = HOP_T
  local land_x = terrain_walk(self.x, dir, HOP_L)
  local dx     = math.abs(land_x - self.x)
  local dy     = terrain_height(land_x) - terrain_height(self.x)
  if dy > 0 and dx > 1 then
    local k = 1 + HOP_DOWNHILL*math.min(dy/dx, 1)
    T       = HOP_T*k
    land_x  = terrain_walk(self.x, dir, HOP_L*k)
    dx      = math.abs(land_x - self.x)
    dy      = terrain_height(land_x) - terrain_height(self.x)
  end
  dy = math.clamp(dy, -dx*HOP_MAX_GRADE, dx*HOP_MAX_GRADE)
  self.speed        = dx/T
  self.hop_active   = true
  self.hop_launch_t = time
  spring_pull(self.spring, 'squash_x', -0.07, 6, 0.45)
  spring_pull(self.spring, 'squash_y',  0.11, 6, 0.45)
  sfx(sounds.hop, volumes.hop)
  return dy/T - GRAVITY_Y*T/2
end

function player:is_grounded()
  local y2 = self.y + PLAYER_RADIUS + 1.5
  return raycast_entity(self.x - 9, self.y, self.x - 9, y2, { 'solid' }) ~= nil
      or raycast_entity(self.x + 9, self.y, self.x + 9, y2, { 'solid' }) ~= nil
      or raycast_entity(self.x,     self.y, self.x,     y2, { 'solid' }) ~= nil
end

function player:update(dt)
  timer_update(self.timer, dt)
  spring_update(self.spring, dt)
  self.collider:sync()

  local vx, vy = self.collider:get_velocity()

  local was_grounded = self.grounded
  self.grounded = self:is_grounded()
  if not self.grounded then self.air_t = self.air_t + dt end

  if self.grounded and vy >= -10 and time - self.hop_launch_t > 0.09 then
    self.movement_jump = true
    self.can_jump      = true
    self.jumping       = false
    self.bouncing      = false
    self.hop_active    = false
  end

  if self.grounded and not was_grounded and self.air_t > 0.04 then
    local impact = math.max(vy, self.last_vy)
    spring_pull(self.spring, 'squash_x', math.remap(impact, 0, 1000, 0, 1)*SQUASH,    6, 0.45)
    spring_pull(self.spring, 'squash_y', math.remap(impact, 0, 1000, -0.2, 0)*SQUASH, 6, 0.45)
    if self.mode == 'hop' then
      timer_tween(self.timer, 0.05, 'rot_snap', self,
                  { visual_r = math.snap(self.visual_r, 2*math.pi) }, math.linear,
                  function() self.visual_r = 0 end)
    end
  end
  if self.grounded then self.air_t = 0 end

  if input_pressed('toggle_mode') and not tweak_active then
    self:set_mode(self.mode == 'roll' and 'hop' or 'roll')
  end

  if self.mode == 'roll' then
    self:update_roll(dt)
  else
    self:update_hop(dt)
  end
end

function player:update_roll(dt)
  local mx = 0
  if input_down('left')  then mx = mx - 1 end
  if input_down('right') then mx = mx + 1 end
  if mx ~= 0 then self.direction = mx end

  local mass = self.collider:get_mass()
  local vx, vy = self.collider:get_velocity()
  local fx, fy = 0, 0
  -- throttle 1 at rest, 0 at/over cruise in that direction (never negative = never a brake)
  local function motor(v, dir)
    if dir == 0 then return 0 end
    return dir * math.clamp(1 - dir*v/ROLL_TARGET_V, 0, 1)
  end

  if self.grounded then
    self.roll_ax = math.lerp_dt(0.9, 0.12, dt, self.roll_ax, 0)
    self.roll_ay = math.lerp_dt(0.9, 0.12, dt, self.roll_ay, 0)
    local a = terrain_angle(self.x)
    local along = vx*math.cos(a) + vy*math.sin(a)
    local F = mass * ROLL_ACCEL * motor(along, mx)
    fx, fy = F*math.cos(a), F*math.sin(a)
  else
    local want_ay = 0
    if input_down('jump') then want_ay = want_ay - ROLL_FLOAT_ACCEL end
    if input_down('down') then want_ay = want_ay + ROLL_FLOAT_ACCEL end
    self.roll_ax = math.lerp_dt(0.9, ROLL_AIR_SMOOTH, dt, self.roll_ax, ROLL_AIR_ACCEL * motor(vx, mx))
    self.roll_ay = math.lerp_dt(0.9, ROLL_AIR_SMOOTH, dt, self.roll_ay, want_ay)
    fx = mass * self.roll_ax
    fy = mass * self.roll_ay
  end

  if fx ~= 0 or fy ~= 0 then
    self.collider:apply_force(fx, fy)
    self.collider:set_awake(true)
  end

  if input_down('jump') and self.can_jump then
    vx, vy = self.collider:get_velocity()
    self.jump_y       = self.y
    self.jumping      = true
    self.can_jump     = false
    self.hop_launch_t = time
    self.collider:set_velocity(vx, vy + ROLL_JUMP_VY)
    spring_pull(self.spring, 'squash_x', -0.14, 6, 0.45)
    spring_pull(self.spring, 'squash_y',  0.22, 6, 0.45)
  end

  vx, vy = self.collider:get_velocity()
  if math.abs(vx) > 8 then
    plants_apply_moving(self.x, self.y, math.sign(vx), 0.5*math.abs(vx), nil, false)
  end
  self.last_vy = vy
end

function player:update_hop(dt)
  local vx, vy = self.collider:get_velocity()

  if input_down('left') then
    if self.movement_jump and not self.jumping and not self.bouncing
       and self.can_jump then
      self.moving_left = true
      vy = self:do_hop(-1)
    else
      self.moving_left = true
      self.direction   = -1
      if not self.hop_active then self.speed = MOVE_MAX_V end
    end
  end
  if input_down('right') then
    if self.movement_jump and not self.jumping and not self.bouncing
       and self.can_jump then
      self.moving_right = true
      vy = self:do_hop(1)
    else
      self.moving_right = true
      self.direction    = 1
      if not self.hop_active then self.speed = MOVE_MAX_V end
    end
  end
  if not input_down('left') then
    if self.moving_left then self.speed = 0; self.hop_active = false end
    self.moving_left = false
  end
  if not input_down('right') then
    if self.moving_right then self.speed = 0; self.hop_active = false end
    self.moving_right = false
  end
  if (input_released('left') or input_released('right'))
     and not self.jumping and not self.bouncing then
    if vy < 0 then vy = 0 end
  end

  if input_down('jump') then
    if self.can_jump then
      self.jump_y       = self.y
      self.jumping      = true
      self.can_jump     = false
      self.hop_active   = false
      self.hop_launch_t = time
      vy = JUMP_VY
      spring_pull(self.spring, 'squash_x', -0.14, 6, 0.45)
      spring_pull(self.spring, 'squash_y',  0.22, 6, 0.45)
    end
  else
    if self.jumping and not self.bouncing then
      if vy < 0 and math.abs(self.y - self.jump_y) > JUMP_CUT_TRAVEL then
        vy = JUMP_CUT_VY
        self.jumping = false
      end
    end
  end

  if self.jumping or self.bouncing then
    self.visual_r = self.visual_r + self.direction*4*math.pi*dt
  end

  local resting = self.grounded and self.speed == 0
                  and not input_down('jump') and vy >= 0 and vy < 30
  self.collider:set_gravity_scale(resting and 0 or 1)
  if resting then vy = 0 end

  self.collider:set_velocity(self.direction*self.speed, vy)

  if self.speed > 0 then
    plants_apply_moving(self.x, self.y, self.direction, 0.5*self.speed, nil, false)
  end

  self.last_vy = vy
end

function player:draw()
  local img = time < self.dizzy_until and dizzy_img or slight_smile
  local s   = (22/img.width)*self.spring.hit.x
  local sx  = s*self.spring.squash_x.x
  local sy  = s*self.spring.squash_y.x
  local r   = self.mode == 'roll' and self.collider:get_angle() or self.visual_r
  layer_push(game_layer, self.x, self.y, r, sx, sy)
  layer_image(game_layer, img, 0, 0, nil, self.flashing and white())
  layer_pop(game_layer)
end

function player:destroy()
  self.collider:destroy()
end

function spawn_player()
  local x = gw/2
  return player(x, terrain_height(x) - PLAYER_RADIUS)
end

-- -----------------------------------------------------------------------------
-- F1 — live movement tweaks. World keeps running. Values write to globals;
-- friction/gravity also push into the live bodies.
-- -----------------------------------------------------------------------------
tweak_active = false

TWEAKS = {
  { 'ROLL_TARGET_V',    80,   500, '%.0f', 'r.cruise' },
  { 'ROLL_ACCEL',       40,   800, '%.0f', 'r.accel'  },
  { 'ROLL_AIR_ACCEL',    0,   600, '%.0f', 'r.air x'  },
  { 'ROLL_FLOAT_ACCEL',  0,   800, '%.0f', 'r.float'  },
  { 'ROLL_AIR_SMOOTH', 0.05,  1.2, '%.2f', 'r.smooth' },
  { 'ROLL_FRICTION',     0,   1.5, '%.2f', 'r.frict'  },
  { 'ROLL_RESTITUTION',  0,     1, '%.2f', 'r.bounce' },
  { 'ROLL_JUMP_VY',   -400,   -40, '%.0f', 'r.jump'   },
  { 'GRAVITY_Y',       200,  1200, '%.0f', 'gravity'  },
  { 'JUMP_VY',        -500,  -80,  '%.0f', 'h.jump'   },
  { 'MOVE_MAX_V',       60,   280, '%.0f', 'h.speed'  },
  { 'HOP_VY',         -220,   -30, '%.0f', 'h.hop'    },
  { 'HOP_DOWNHILL',      0,     1, '%.2f', 'h.down'   },
}

function tweak_update(dt)
  if input_pressed('toggle_tweak') then tweak_active = not tweak_active end
  if not tweak_active or sound_tuner_active then return end
  local px, py, pw = gw - 248, 8, 240
  ui_panel({ rect = { x = px, y = py, w = pw, h = #TWEAKS*16 + 22 }, radius = 3 })
  ui_text({ x = px + 6, y = py + 4, text = 'MOVE (F1)', color = fg_dark })
  local y = py + 18
  for _, t in ipairs(TWEAKS) do
    local name, lo, hi, fmt, label = t[1], t[2], t[3], t[4], t[5]
    ui_text({ rect = { x = px + 6, y = y, w = 78, h = 12 },
              text = label, color = fg_dark })
    local s = ui_slider({ rect = { x = px + 86, y = y, w = 104, h = 12 },
                          value = math.remap(_G[name], lo, hi, 0, 1),
                          id = 'tw_' .. name })
    _G[name] = math.remap(s.value, 0, 1, lo, hi)
    ui_text({ rect = { x = px + 194, y = y, w = 42, h = 12 },
              text = fmt:format(_G[name]), color = white })
    y = y + 16
  end
  physics_set_gravity(0, GRAVITY_Y)
  HOP_T = 2*(-HOP_VY)/GRAVITY_Y
  HOP_L = MOVE_MAX_V*HOP_T
  if p1 and p1.collider then
    p1.collider:set_friction(ROLL_FRICTION)
    if p1.mode == 'roll' then p1.collider:set_restitution(ROLL_RESTITUTION) end
  end
  if terrain and terrain.collider then
    terrain.collider:set_friction(ROLL_FRICTION, terrain.collider.chain)
  end
end

-- -----------------------------------------------------------------------------
-- plants — ToTeMoJi spawn recipe: pick 4-8 of the surface x-slots, roll a
-- weighted cluster at each. Members sit ON the terrain and tilt to it.
-- -----------------------------------------------------------------------------
PLANT_XS = { 96, 150, 200, 224, 290, 330, 360, 390, 420, 450, 480, 516, 560, 600 }

local function weighted_pick(...)
  local weights = { ... }
  local total = 0
  for _, w in ipairs(weights) do total = total + w end
  local roll = random_float(0, total)
  for i, w in ipairs(weights) do
    roll = roll - w
    if roll <= 0 then return i end
  end
  return #weights
end

function spawn_plants()
  local pool = {}
  for _, x in ipairs(PLANT_XS) do pool[#pool + 1] = x end
  for i = 1, random_int(4, 8) do
    local x = table.remove(pool, random_int(1, #pool))
    plant_spawn_group(weighted_pick(25, 20, 15, 10, 10, 10, 6, 4),
                      x, terrain_height(x))
  end
end

-- -----------------------------------------------------------------------------
-- scene
-- -----------------------------------------------------------------------------
terrain = terrain_body()
plants_terrain = { height = terrain_height, angle = terrain_angle }
spawn_plants()
build_clouds(5)
p1 = spawn_player()

function reset_scene()
  plants_clear()
  spawn_plants()
  build_clouds(5)
  local x = gw/2
  p1.collider:set_position(x, terrain_height(x) - PLAYER_RADIUS)
  p1.collider:set_velocity(0, 0)
  p1.collider:set_gravity_scale(1)
  p1:reset_state()
end

-- -----------------------------------------------------------------------------
-- main loop
-- -----------------------------------------------------------------------------
function update(dt)
  sync_engine_globals()
  local sdt = juice_update(dt)

  ui_begin(dt)
  sound_tuner_update(dt)
  tweak_update(dt)
  sounds_warm_step(2)

  if not sound_tuner_paused() then
    camera_update(main_camera, sdt)
    if not p1._dead then p1:update(sdt) end
    collection_update(plants, sdt)
    collection_update(fxs, sdt)
    clouds_update(sdt)
    if input_pressed('restart') then reset_scene() end
  end

  process_destroy_queue()
end

function draw()
  layer_rectangle_gradient_v(bg_layer, 0, 0, gw, gh, sky_top(), sky_bottom())
  clouds_draw()

  camera_attach(main_camera, bg_plants_layer)
  plants_draw(bg_plants_layer, false)
  camera_detach(main_camera, bg_plants_layer)

  camera_attach(main_camera, game_layer)
  terrain:draw(game_layer)
  if not p1._dead then p1:draw() end
  camera_detach(main_camera, game_layer)

  camera_attach(main_camera, cover_layer)
  plants_draw(cover_layer, true)
  terrain:draw(cover_layer)
  camera_detach(main_camera, cover_layer)

  camera_attach(main_camera, effects_layer)
  for _, f in ipairs(fxs) do f:draw() end
  camera_detach(main_camera, effects_layer)

  layer_text(overlay_layer, p1.mode, fonts.main, 8, 8, fg())
  emoji_render()
end
