--[[
  emoji/cursor.lua — the signature emoji cursor (👆 backhand index pointing
  up), ported from Emoji Aimer / super-emoji-pop. The system cursor is hidden
  and this draws on its own outlined layer so it reads with the same chunky
  black halo as everything else, on top of the whole scene.

  Juice carried:
    - horizontal sway: mouse stops after fast horizontal motion → rotation
      spring pull in the motion direction (clamped ±π/4, 0.2s cooldown)
    - vertical squash: mouse stops after fast vertical motion → brief
      y-squash tweened back (deeper + longer for faster motion)
    - click press: main-spring pull 0.5 + tilt π/16 + squash (0.9, 0.7)
    - click release: main-spring pull 0.25 + tween back
    - cursor:flash(duration?) — white blink acknowledgement (pickups etc.)
    - cursor:pulse(force?)    — bare spring pulse (hover acknowledgement)

  Requirements on the host:
    - bind('click', 'mouse:1')                (cursor reads the 'click' action)
    - a 'cursor'-named layer in emoji_layers  (draws to cursor_layer)
    - spawn_cursor() after emoji_layers; then the_cursor:update(dt) at the
      END of update() and the_cursor:draw() in draw().

  The (+7, +9) draw offset and the -π/8 base tilt are the super-emoji-pop
  calibration that lands the sprite's FINGERTIP on the actual mouse position.
  They're right for the backhand sprite; swap self.image (and re-calibrate
  image_rotation_offset / the offset) for a different cursor emoji.
]]

cursor = class()

function cursor:new(args)
  args = args or {}
  self.x, self.y = 0, 0
  make_entity(self)
  self.timer  = timer_new()
  self.spring = spring_new()
  spring_add(self.spring, 'main', 1)
  spring_add(self.spring, 'r', 0)

  self.size = args.size or 22

  self.previous_mouse_deltas_x = {}
  self.previous_mouse_deltas_y = {}
  self.mouse_dt_sy      = 1
  self.last_sway_x_time = 0
  self.last_sway_y_time = 0

  self.click_r  = 0
  self.click_sx, self.click_sy = 1, 1

  self.flashing = false

  self.image                 = args.image or backhand_index_pointing_up
  self.image_scale           = self.size/self.image.width
  self.image_rotation_offset = args.rotation_offset or -math.pi/8

  mouse_set_visible(false)
end

-- White blink acknowledgement + spring pulse (resource pickup, purchase...).
-- Named timer so back-to-back flashes replace the in-flight unflash cleanly.
function cursor:flash(duration)
  spring_pull(self.spring, 'main', 0.3)
  self.flashing = true
  timer_after(self.timer, duration or 0.1, 'cursor_flash', function()
    self.flashing = false
  end)
end

-- Light sympathetic pulse (hover-enter on juicy UI elements).
function cursor:pulse(force)
  spring_pull(self.spring, 'main', force or 0.05)
end

-- Error persona (Emoji Aimer's buy-fail): the cursor becomes a red X for
-- `duration`, deliberately WITHOUT spring/rotation styling — it reads as a
-- stamp, not a character. Restores the base sprite afterwards.
function cursor:error(duration)
  self.erroring = true
  timer_after(self.timer, duration or 0.4, 'cursor_error', function()
    self.erroring = false
  end)
end

function cursor:update(dt)
  timer_update(self.timer, dt)
  spring_update(self.spring, dt)

  self.x, self.y = mouse_position()
  local dx, dy   = mouse_delta()

  -- Track last 10 frames of mouse delta. Insert at front, drop the 11th.
  table.insert(self.previous_mouse_deltas_x, 1, dx)
  if #self.previous_mouse_deltas_x > 10 then self.previous_mouse_deltas_x[11] = nil end
  table.insert(self.previous_mouse_deltas_y, 1, dy)
  if #self.previous_mouse_deltas_y > 10 then self.previous_mouse_deltas_y[11] = nil end

  -- Horizontal sway: cursor stopped, recent motion was significant. Pull the
  -- rotation spring by the remapped average delta, clamped to ±π/4; 0.2s
  -- cooldown so it doesn't re-fire while the spring still oscillates back.
  local avg_x = array.average(self.previous_mouse_deltas_x) or 0
  if dx == 0 and math.abs(avg_x) > 2 and time - self.last_sway_x_time >= 0.2 then
    self.last_sway_x_time = time
    local sway = math.clamp(
      math.remap(math.abs(avg_x), 0, 20, 0, math.sign(avg_x)*math.pi/4),
      -math.pi/4, math.pi/4)
    spring_pull(self.spring, 'r', sway)
  end

  -- Vertical squash: cursor stopped after vertical motion. Snap mouse_dt_sy
  -- down (more squash for faster motion) and tween back over a duration that
  -- scales with the same speed. Named tween replaces any in-flight one.
  local avg_y = array.average(self.previous_mouse_deltas_y) or 0
  if dy == 0 and math.abs(avg_y) > 2 and time - self.last_sway_y_time >= 0.2 then
    self.last_sway_y_time = time
    self.mouse_dt_sy = math.clamp(math.remap(math.abs(avg_y), 0, 12, 1, 0.5), 0.5, 1)
    timer_tween(self.timer,
      math.remap(math.abs(avg_y), 0, 12, 0.1, 0.2),
      'squash', self, { mouse_dt_sy = 1 }, math.cubic_in_out)
  end

  -- Click press / release. Named 'click_scale' so a press during a still-
  -- running release tween replaces it cleanly (and vice versa).
  if input_pressed('click') then
    spring_pull(self.spring, 'main', 0.5)
    timer_tween(self.timer, 0.05, 'click_scale', self,
      { click_r = math.pi/16, click_sx = 0.9, click_sy = 0.7 },
      math.cubic_in_out)
  end
  if input_released('click') then
    spring_pull(self.spring, 'main', 0.25)
    timer_tween(self.timer, 0.1, 'click_scale', self,
      { click_r = 0, click_sx = 1, click_sy = 1 },
      math.cubic_in_out)
  end
end

function cursor:draw()
  -- Error persona: flat red-X stamp, all styling stripped.
  if self.erroring then
    local s = self.size/x_mark_img.width
    layer_push(cursor_layer, self.x + 7, self.y + 9, 0, s, s)
    layer_image(cursor_layer, x_mark_img, 0, 0)
    layer_pop(cursor_layer)
    return
  end

  -- Outer transform: click squash + movement squash. Inner: rotation +
  -- uniform main-spring scale. The (+7, +9) offset places the fingertip
  -- at (self.x, self.y).
  local sx = self.click_sx
  local sy = self.mouse_dt_sy*self.click_sy
  local r  = self.spring.r.x + self.image_rotation_offset + self.click_r
  local s  = self.image_scale*self.spring.main.x
  layer_push(cursor_layer, self.x, self.y, 0, sx, sy)
  layer_push(cursor_layer, 7, 9, r, s, s)
  layer_image(cursor_layer, self.image, 0, 0, nil, self.flashing and white())
  layer_pop(cursor_layer)
  layer_pop(cursor_layer)
end

function cursor:destroy() end

function spawn_cursor(args)
  the_cursor = cursor(args)
  return the_cursor
end
