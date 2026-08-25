--[[
  emoji/fx.lua — the particle/impact effect set shared by the emoji games.
  Ported from Emoji Aimer (which ported them from EBB / super-emoji-pop /
  super-emoji-box). Four classes + spawn wrappers:

    hit_circle(x, y, args)            — expanding/shrinking ring at an impact
    hit_effect(x, y, args)            — the 'hit1' white "pow" spritesheet burst
    hit_particle(x, y, args)          — directional colored streak w/ gravity
    emoji_particle(x, y, image, args) — flying emoji sprite (stars, sparkles...)

  Every spawn_* wrapper registers into the global `fxs` list; the host runs
  `collection_update(fxs, sdt)` in update() and `for _, f in ipairs(fxs) do
  f:draw() end` in draw(). All draw to `effects_layer` by default (override
  with args.layer) so they ride the outline + shadow treatment.

  Common args: flash_on_spawn (true, or a fraction of duration for
  emoji_particle) makes the effect spawn white then reveal its color —
  the "flash white, bleed to color" idiom.

  Standard cascades (reference values, from Emoji Aimer):
    on hit:  hit_effect(s=1) + 2 yellow hit_particles (vel 120-200, grav 256,
             flash) + 1 star emoji_particle (vel 80-150, grav 256, flash 0.25)
    on die:  2-4 yellow hit_particles (vel 100-350, w=14 h=8, grav 228, flash)
             + 2 star emoji_particles (vel 120-240, dur 0.6-1.2, spin, flash 0.3)
    big/crit: hit_effect(s=1.5) + 6-9 red hit_particles (vel 140-320,
             grav 256-512, w 8-14, h 4-8) + slow_time(0.33, 0.5) +
             rotation-only shake_trauma + camera_punch at the hit point
]]

fxs = {}

-- =============================================================================
-- hit_circle — ring that tweens radius to 0 over `duration`, then dies.
-- args: radius (12), color (yellow), duration (0.2), layer, flash_on_spawn,
--       color_2 + color_swap — the family's TWO-TONE life: starts color,
--       switches to color_2 at color_swap fraction of the duration
--       (default 0.5). Impact color → owner color is the canonical use.
-- =============================================================================
hit_circle = class()

function hit_circle:new(x, y, args)
  args = args or {}
  self.x, self.y = x, y
  self.radius    = args.radius   or 12
  self.color     = args.color    or yellow
  self.color_2   = args.color_2
  self.duration  = args.duration or 0.2
  self.layer     = args.layer    or effects_layer
  self.flashing  = false
  self.age       = 0
  self.swap_at   = (args.color_swap or 0.5)*self.duration
  make_entity(self)
  self.timer = timer_new()
  timer_tween(self.timer, self.duration, self, { radius = 0 },
              math.cubic_in_out, function() self:kill() end)
  if args.flash_on_spawn then
    self.flashing = true
    timer_after(self.timer, 0.1, function() self.flashing = false end)
  end
end

function hit_circle:update(dt)
  timer_update(self.timer, dt)
  self.age = self.age + dt
end

function hit_circle:draw()
  local base = (self.color_2 and self.age > self.swap_at) and self.color_2 or self.color
  local col  = self.flashing and white() or base()
  layer_circle(self.layer, self.x, self.y, self.radius, col)
end

function hit_circle:destroy() end

-- =============================================================================
-- hit_effect — plays the 'hit1' spritesheet (0.03s/frame) once at a random
-- rotation, then dies. args: s (scale multiplier over the 1.35 base), layer
-- =============================================================================
hit_effect = class()

function hit_effect:new(x, y, args)
  args = args or {}
  self.x, self.y = x, y
  self.r         = random_angle()
  self.sx        = args.s or 1
  self.sy        = args.s or 1
  self.layer     = args.layer or effects_layer
  make_entity(self)
  self.animation = animation_new('hit1', 0.03, 'once')
end

function hit_effect:update(dt)
  animation_update(self.animation, dt)
  if self.animation.dead then self:kill() end
end

function hit_effect:draw()
  -- 1.35 base scale matches the super-emoji-pop reference; args.s stacks.
  local s = 1.35
  layer_push(self.layer, self.x, self.y, self.r, self.sx*s, self.sy*s)
  layer_animation(self.layer, self.animation, 0, 0)
  layer_pop(self.layer)
end

function hit_effect:destroy() end

-- =============================================================================
-- hit_particle — directional rounded-rect streak; flies along `direction`,
-- accumulates gravity, scales to nothing. Streak size defaults from velocity.
-- args: velocity, direction, color, duration, gravity, w, h, layer,
--       flash_on_spawn
-- =============================================================================
hit_particle = class()

function hit_particle:new(x, y, args)
  args = args or {}
  self.x, self.y            = x, y
  self.velocity             = args.velocity or random_float(50, 150)
  self.gravity_velocity     = 0
  self.gravity_acceleration = args.gravity or 0
  self.direction            = args.direction or random_angle()
  self.color                = args.color or yellow
  self.color_2              = args.color_2      -- two-tone swap (see hit_circle)
  self.layer                = args.layer or effects_layer
  self.w  = args.w or math.remap(self.velocity, 0, 250, 4, 12)
  self.h  = args.h or math.remap(self.velocity, 0, 250, 2, 6)
  self.sx, self.sy = 1, 1
  self.duration = args.duration or random_float(0.25, 0.5)
  self.swap_at  = (args.color_swap or 0.5)*self.duration
  self.age      = 0
  self.flashing = false
  make_entity(self)
  self.timer = timer_new()
  timer_tween(self.timer, self.duration, self, { velocity = 0, sx = 0, sy = 0 },
              math.linear, function() self:kill() end)
  if args.flash_on_spawn then
    self.flashing = true
    timer_after(self.timer, 0.1, function() self.flashing = false end)
  end
end

function hit_particle:update(dt)
  timer_update(self.timer, dt)
  self.age = self.age + dt
  self.gravity_velocity = self.gravity_velocity + self.gravity_acceleration*dt
  local vx = self.velocity*math.cos(self.direction)
  local vy = self.velocity*math.sin(self.direction) + self.gravity_velocity
  self.x = self.x + vx*dt
  self.y = self.y + vy*dt
  self._draw_angle = math.atan(vy, vx)
end

function hit_particle:draw()
  local base = (self.color_2 and self.age > self.swap_at) and self.color_2 or self.color
  local col  = self.flashing and white() or base()
  local r    = math.min(self.w, self.h)/2
  layer_push(self.layer, self.x, self.y, self._draw_angle or 0, self.sx, self.sy)
  layer_rounded_rectangle(self.layer, -self.w/2, -self.h/2, self.w, self.h, r, col)
  layer_pop(self.layer)
end

function hit_particle:destroy() end

-- =============================================================================
-- emoji_particle — flying emoji sprite. Scale is normalized so args.scale=1
-- gives a 14-px-wide emoji regardless of source PNG size. angle_mode:
-- nil = free spin (rotation_speed), a number = fixed angle, 'forward' /
-- 'backward' = face the velocity vector. flash_on_spawn: true, or a fraction
-- of duration to stay white for.
-- args: velocity, direction, duration, gravity, scale, angle_mode,
--       rotation_speed, layer, flash_on_spawn
-- =============================================================================
emoji_particle = class()

function emoji_particle:new(x, y, image, args)
  args = args or {}
  self.x, self.y = x, y
  self.image     = image
  self.scale     = 14*(args.scale or 1)/self.image.width
  self.layer     = args.layer or effects_layer

  self.velocity         = args.velocity or random_float(75, 150)
  self.direction        = args.direction or random_angle()
  self.duration         = args.duration or random_float(0.4, 0.6)
  self.gravity_velocity = 0
  self.gravity          = args.gravity or 0

  self.angle_mode = args.angle_mode
  if type(self.angle_mode) == 'number' then
    self.rotation = self.angle_mode
  else
    self.rotation = random_angle()
  end
  self.rotation_speed = args.rotation_speed or random_float(-4*math.pi, 4*math.pi)
  if self.angle_mode then self.rotation_speed = 0 end

  self.flashing = false
  make_entity(self)
  self.timer  = timer_new()
  self.spring = spring_new()
  spring_add(self.spring, 'main', 1)
  timer_tween(self.timer, self.duration, self, { velocity = 0, scale = 0 },
              math.linear, function() self:kill() end)

  if args.flash_on_spawn then
    self.flashing = true
    local f = type(args.flash_on_spawn) == 'number' and args.flash_on_spawn or 1
    timer_after(self.timer, f*self.duration, function() self.flashing = false end)
    spring_pull(self.spring, 'main', 0.3, 3, 0.7)
  end
end

function emoji_particle:update(dt)
  timer_update(self.timer, dt)
  spring_update(self.spring, dt)
  self.gravity_velocity = self.gravity_velocity + self.gravity*dt
  local vx = self.velocity*math.cos(self.direction)
  local vy = self.velocity*math.sin(self.direction) + self.gravity_velocity
  self.x = self.x + vx*dt
  self.y = self.y + vy*dt
  if self.angle_mode == 'forward' then
    self.rotation = math.atan(vy, vx)
  elseif self.angle_mode == 'backward' then
    self.rotation = math.atan(vy, vx) + math.pi
  elseif type(self.angle_mode) ~= 'number' then
    self.rotation = self.rotation + self.rotation_speed*dt
  end
end

function emoji_particle:draw()
  local s = self.scale*self.spring.main.x
  layer_push(self.layer, self.x, self.y, self.rotation, s, s)
  layer_image(self.layer, self.image, 0, 0, nil, self.flashing and white())
  layer_pop(self.layer)
end

function emoji_particle:destroy() end

-- =============================================================================
-- damage_number — per-digit keycap number that rises and fades (the EBB/Aimer
-- damage popup). Each digit is a gray keycap sprite from assets/0..9.png (+
-- 'plus.png'); digits wobble/bob while the group rises; holds at full scale
-- for 25% of duration then shrinks out.
--
-- RENDERING IS SPECIAL: digits don't draw in the fxs loop (draw() is a
-- no-op). They queue onto a private digit layer inside the pipeline's
-- emoji_render_inject hook, bucketed by `rarity_color`, and each bucket is
-- recolored through recolor.frag (gray keycap → the bucket color, white
-- glyph stays white) into effects_layer — BEFORE outline derivation, so
-- numbers get the black halo like everything else.
-- args: color (palette color OBJECT, default white — the keycap tint) ·
--       vy (-80) · duration_multiplier (0.5)
-- =============================================================================
damage_number = class()

local digit_layer = layer_new('emoji_digit')   -- private intermediate

function damage_number:new(x, y, amount, args)
  args = args or {}
  self.x, self.y           = x, y
  self.vy                  = args.vy or -80
  self.duration_multiplier = args.duration_multiplier or 0.5
  self.glyph_size          = args.size or 12
  self.scale               = self.glyph_size/512
  self.rarity_color        = args.color or white   -- the bucket key
  make_entity(self)
  self.timer  = timer_new()
  self.spring = spring_new()
  spring_pull(self.spring, 'main', 0.5, 3, 0.7)

  -- Per-digit wobble/bob state. Tiny phase offsets + halved amplitude so
  -- the digits read as one cohesive number, not a jagged stack.
  self.characters = {}
  local text = tostring(amount)
  for i = 1, #text do
    local img = digit_imgs[text:sub(i, i)]
    if img then
      self.characters[#self.characters + 1] = {
        image         = img,
        rotation      = random_float(-math.pi/16, math.pi/16),
        angular_speed = random_float(-math.pi/4,  math.pi/4),
        offset_y      = 0,
      }
    end
  end

  timer_after(self.timer, 0.25*self.duration_multiplier, function()
    timer_tween(self.timer, 0.75*self.duration_multiplier, self, { scale = 0 },
                math.cubic_in_out, function() self:kill() end)
  end)
end

function damage_number:update(dt)
  timer_update(self.timer, dt)
  spring_update(self.spring, dt)
  for i, ch in ipairs(self.characters) do
    ch.rotation = ch.rotation + ch.angular_speed*dt
    ch.offset_y = 2*math.sin(time + i*0.3)
  end
  self.y = self.y + self.vy*dt
end

function damage_number:draw() end   -- queued by the inject hook instead

function damage_number:draw_digits()
  local adv     = self.glyph_size
  local total_w = #self.characters*adv
  local start_x = self.x - total_w/2
  local s       = self.scale*self.spring.main.x
  for i, ch in ipairs(self.characters) do
    local cx = start_x + (i - 0.5)*adv
    local cy = self.y + ch.offset_y
    layer_push(digit_layer, cx, cy, ch.rotation, s, s)
    layer_image(digit_layer, ch.image, 0, 0)
    layer_pop(digit_layer)
  end
end

function damage_number:destroy() end

-- The pipeline injection: bucket live damage_numbers by color, render each
-- bucket to the digit layer, pull it through recolor.frag (tinted to the
-- bucket color) into effects_layer. Runs after content renders, before
-- outline derivation (see emoji/pipeline.lua). Digits are world-space:
-- ride main_camera when the host defines one.
emoji_render_add_inject(function()
  local buckets = {}
  for _, f in ipairs(fxs) do
    if not f._dead and f.rarity_color and f.draw_digits then
      buckets[f.rarity_color] = buckets[f.rarity_color] or {}
      table.insert(buckets[f.rarity_color], f)
    end
  end
  if not next(buckets) then return end
  if main_camera then camera_attach(main_camera, digit_layer) end
  for col, bucket in pairs(buckets) do
    for _, dn in ipairs(bucket) do dn:draw_digits() end
    layer_render(digit_layer)
    shader_set_vec4_immediate(recolor_shader, 'u_target_color',
                              col.r/255, col.g/255, col.b/255, 1)
    layer_draw_from(effects_layer, digit_layer, recolor_shader)
  end
  if main_camera then camera_detach(main_camera, digit_layer) end
end)

-- =============================================================================
-- spawn_marker — the family's enemy-arrival grammar: a circle grows to
-- `radius` over 0.35s cubic_in_out with per-frame radius jitter, POPS
-- (spawn sound + the on_spawn callback + a burst of fast particles), then
-- shrinks out linearly. Host keeps its own list or uses spawn_spawn_marker.
-- =============================================================================
spawn_marker = class()

function spawn_marker:new(x, y, col, on_spawn, args)
  args = args or {}
  self.x, self.y = x, y
  self.color  = col or fg
  self.radius = 0
  self.layer  = args.layer or effects_layer
  make_entity(self)
  self.timer = timer_new()
  timer_tween(self.timer, 0.35, self, { radius = args.radius or 12 },
              math.cubic_in_out, function()
    sfx(sounds.spawn, args.volume or 0.5)
    if on_spawn then on_spawn() end
    for i = 1, random_int(6, 8) do
      spawn_hit_particle(self.x, self.y, {
        velocity = random_float(150, 300), direction = random_angle(),
        duration = random_float(0.2, 0.5), color = self.color,
        flash_on_spawn = true, layer = self.layer,
      })
    end
    timer_tween(self.timer, 0.25, self, { radius = 0 }, math.linear, function()
      self:kill()
    end)
  end)
end

function spawn_marker:update(dt) timer_update(self.timer, dt) end

function spawn_marker:draw()
  if self.radius > 0.5 then
    layer_circle(self.layer, self.x, self.y, self.radius*random_float(0.9, 1.1),
                 self.color())
  end
end

function spawn_marker:destroy() end

-- -----------------------------------------------------------------------------
-- spawn wrappers — construct + register into the global fxs list
-- -----------------------------------------------------------------------------
function spawn_damage_number(x, y, amount, args)
  local e = damage_number(x, y, amount, args)
  fxs[#fxs + 1] = e
  return e
end

-- Word floats ("+1 dmg" style): same class, letter glyphs — any character
-- present in digit_imgs (digits, a-z, +, -). Lowercased automatically.
function spawn_emoji_text(x, y, text, args)
  return spawn_damage_number(x, y, tostring(text):lower(), args)
end

function spawn_spawn_marker(x, y, col, on_spawn, args)
  local e = spawn_marker(x, y, col, on_spawn, args)
  fxs[#fxs + 1] = e
  return e
end

-- Landing dust: the two 💨 puffs flung nearly horizontally from the feet.
function spawn_landing_dust(x, y)
  for i = -1, 1, 2 do
    spawn_emoji_particle(x + i*8, y, dash_img, {
      velocity  = random_float(30, 50),
      direction = (i < 0 and math.pi or 0) + i*math.pi/24,
      duration  = 0.7, scale = 0.9, angle_mode = 0,
    })
  end
end

function spawn_hit_circle(x, y, args)
  local e = hit_circle(x, y, args)
  fxs[#fxs + 1] = e
  return e
end

function spawn_hit_effect(x, y, args)
  local e = hit_effect(x, y, args)
  fxs[#fxs + 1] = e
  return e
end

function spawn_hit_particle(x, y, args)
  local e = hit_particle(x, y, args)
  fxs[#fxs + 1] = e
  return e
end

function spawn_emoji_particle(x, y, image, args)
  local e = emoji_particle(x, y, image, args)
  fxs[#fxs + 1] = e
  return e
end
