--[[
  layer3 module — procedural API over the engine's 3D scene layer.

  Mirrors layer.lua's shadowing pattern: captures the raw engine bindings
  (first arg = C Layer3 pointer), then replaces the globals with wrappers
  whose first argument is a layer3 state table from layer3_new() (field
  .handle holds the pointer; wrappers also accept a raw handle).

  A layer3 renders flat-shaded 3D primitives into a standard layer's FBO,
  so the result composites like any other layer. The state table exposes
  the backing layer at `.layer` (a raw Layer handle — every layer_* wrapper
  accepts it directly).

  Usage:
    scene = layer3_new('scene')
    layer3_set_background(scene, bg_color())

    -- update():
    camera3_apply(cam, scene)                 -- or layer3_camera(scene, ...)
    layer3_sphere(scene, x, y, z, 0.5, red())
    layer3_box(scene, 0, -0.5, 0, 40, 1, 40, 0, 0, 0, 1, gray())

    -- draw():
    layer3_render(scene)                      -- 3D pass into the FBO
    layer_draw(scene.layer)                   -- composite like any 2D layer

  Colors are packed 0xRRGGBBAA (same as the 2D API — pass color()).
  Rotations are quaternions (x, y, z, w); use math3's quat_* helpers.
]]

-- Raw engine bindings (first arg = C Layer3 pointer). Captured before shadowing.
local eng = {
  create = layer3_create,
  get_layer = layer3_get_layer,
  camera = layer3_camera,
  set_light = layer3_set_light,
  set_background = layer3_set_background,
  box = layer3_box,
  sphere = layer3_sphere,
  cylinder = layer3_cylinder,
  capsule = layer3_capsule,
  plane = layer3_plane,
  line = layer3_line,
  render = layer3_render,
  unproject = layer3_unproject,
  debug_draw = layer3_debug_draw,
}

local function l3_handle(l3)
  if type(l3) == 'table' then
    return l3.handle
  end
  return l3
end

--- Create a layer3 state table and optionally register in global `layers`.
function layer3_new(name)
  local l3 = {
    name = name,
    handle = eng.create(name),
  }
  l3.layer = eng.get_layer(l3.handle)   -- backing Layer (raw handle)
  if layers then
    layers[name] = l3
  end
  return l3
end

function layer3_camera(l3, eye_x, eye_y, eye_z, target_x, target_y, target_z, fov, near, far)
  eng.camera(l3_handle(l3), eye_x, eye_y, eye_z, target_x, target_y, target_z, fov, near, far)
end

function layer3_set_light(l3, dir_x, dir_y, dir_z, ambient)
  eng.set_light(l3_handle(l3), dir_x, dir_y, dir_z, ambient)
end

function layer3_set_background(l3, color)
  eng.set_background(l3_handle(l3), color)
end

function layer3_box(l3, x, y, z, w, h, d, qx, qy, qz, qw, color)
  eng.box(l3_handle(l3), x, y, z, w, h, d, qx, qy, qz, qw, color)
end

function layer3_sphere(l3, x, y, z, radius, color)
  eng.sphere(l3_handle(l3), x, y, z, radius, color)
end

function layer3_cylinder(l3, x, y, z, height, radius, qx, qy, qz, qw, color)
  eng.cylinder(l3_handle(l3), x, y, z, height, radius, qx, qy, qz, qw, color)
end

function layer3_capsule(l3, x, y, z, height, radius, qx, qy, qz, qw, color)
  eng.capsule(l3_handle(l3), x, y, z, height, radius, qx, qy, qz, qw, color)
end

function layer3_plane(l3, x, y, z, w, d, qx, qy, qz, qw, color)
  eng.plane(l3_handle(l3), x, y, z, w, d, qx, qy, qz, qw, color)
end

function layer3_line(l3, x1, y1, z1, x2, y2, z2, color)
  eng.line(l3_handle(l3), x1, y1, z1, x2, y2, z2, color)
end

--- Run the 3D pass into the backing layer's FBO. Composite with
--- layer_draw(l3.layer) afterwards.
function layer3_render(l3)
  eng.render(l3_handle(l3))
end

function layer3_unproject(l3, screen_x, screen_y)
  return eng.unproject(l3_handle(l3), screen_x, screen_y)
end

--- Queue the Box3D world's debug geometry into this layer3.
--- opts: {shapes=, joints=, contacts=, bounds=}
function layer3_debug_draw(l3, opts)
  eng.debug_draw(l3_handle(l3), opts)
end
