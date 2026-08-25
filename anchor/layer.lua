--[[
  Layer module — procedural API over the engine layer handle.

  Layers are FBOs that accumulate draw commands during the frame. Commands are
  deferred and processed via layer_render() with GL batching. Composite to the
  screen with layer_draw().

  Usage:
    game_layer = layer_new('game')
    layer_rectangle(game_layer, 100, 100, 50, 30, color)
    layer_render(game_layer)
    layer_draw(game_layer)

  State table shape (from layer_new): { name, handle, parallax_x, parallax_y }
  All layer_* functions below take that table as the first argument `lyr`.

  ---------------------------------------------------------------------------
  ENGINE NAME CONFLICTS (Lua globals registered by anchor.c)

  The C engine binds the same symbol names to raw engine implementations whose
  first argument is a C layer pointer (lightuserdata), e.g. layer_rectangle(ptr, ...).

  This file captures those implementations in `eng` at load time, then REPLACES
  the globals with wrappers whose first argument is a layer state table from
  layer_new() (field .handle holds the pointer). Wrappers also accept a raw
  handle for occasional interop.

  After require('anchor.layer'), direct engine-style calls like
  layer_rectangle(userdata_ptr, x, y, w, h, c) no longer use the C binding
  unless you passed a lightuserdata: the wrapper treats a non-table first arg
  as a raw handle (see lyr_handle).

  Shadowed globals: layer_rectangle, layer_circle, layer_line, layer_render,
  layer_draw, layer_push, layer_pop, layer_clear, layer_get_texture, and every
  other layer_* wrapper defined below. layer_create is NOT shadowed — use
  layer_new() from game code.
  ---------------------------------------------------------------------------
]]

-- Raw engine bindings (first arg = C layer pointer). Captured before we shadow globals.
local eng = {
  create = layer_create,
  rectangle = layer_rectangle,
  circle = layer_circle,
  rectangle_line = layer_rectangle_line,
  circle_line = layer_circle_line,
  line = layer_line,
  capsule = layer_capsule,
  capsule_line = layer_capsule_line,
  triangle = layer_triangle,
  triangle_line = layer_triangle_line,
  polygon = layer_polygon,
  polygon_line = layer_polygon_line,
  rounded_rectangle = layer_rounded_rectangle,
  rounded_rectangle_line = layer_rounded_rectangle_line,
  rectangle_gradient_h = layer_rectangle_gradient_h,
  rectangle_gradient_v = layer_rectangle_gradient_v,
  draw_texture = layer_draw_texture,
  draw_spritesheet_frame = layer_draw_spritesheet_frame,
  draw_text = layer_draw_text,
  push = layer_push,
  pop = layer_pop,
  set_blend_mode = layer_set_blend_mode,
  draw = layer_draw,
  apply_shader = layer_apply_shader,
  shader_set_float = layer_shader_set_float,
  shader_set_vec2 = layer_shader_set_vec2,
  shader_set_vec4 = layer_shader_set_vec4,
  shader_set_int = layer_shader_set_int,
  shader_set_texture = layer_shader_set_texture,
  get_texture = layer_get_texture,
  reset_effects = layer_reset_effects,
  clear = layer_clear,
  render = layer_render,
  draw_from = layer_draw_from,
  stencil_mask = layer_stencil_mask,
  stencil_test = layer_stencil_test,
  stencil_test_inverse = layer_stencil_test_inverse,
  stencil_off = layer_stencil_off,
}

--- Resolve layer state table or raw C handle (lightuserdata) for engine calls.
local function lyr_handle(lyr)
  if type(lyr) == 'table' then
    return lyr.handle
  end
  return lyr
end

--- Create a layer state table and optionally register in global `layers`.
--- `filter` is optional: 'smooth' (antialiased edges, linear sampling) or
--- 'rough' (hard edges, nearest sampling). Defaults to the engine's current
--- global filter mode, which is 'rough' unless changed via set_filter_mode.
--- `w`, `h` are optional: a fixed-size layer that keeps its resolution
--- regardless of window/canvas resizes (the C binding already supported this
--- for embedded games; needed e.g. for window-resolution post-process passes).
function layer_new(name, filter, w, h)
  local lyr = {
    name = name,
    handle = eng.create(name, filter, w, h),
    filter = filter,
    parallax_x = 1,
    parallax_y = 1,
  }
  if layers then
    layers[name] = lyr
  end
  return lyr
end

function layer_rectangle(lyr, x, y, w, h, color)
  eng.rectangle(lyr_handle(lyr), x, y, w, h, color)
end

function layer_circle(lyr, x, y, radius, color)
  eng.circle(lyr_handle(lyr), x, y, radius, color)
end

function layer_rectangle_line(lyr, x, y, w, h, color, line_width)
  eng.rectangle_line(lyr_handle(lyr), x, y, w, h, color, line_width or 1)
end

function layer_circle_line(lyr, x, y, radius, color, line_width)
  eng.circle_line(lyr_handle(lyr), x, y, radius, color, line_width or 1)
end

function layer_line(lyr, x1, y1, x2, y2, width, color)
  eng.line(lyr_handle(lyr), x1, y1, x2, y2, width, color)
end

function layer_capsule(lyr, x1, y1, x2, y2, radius, color)
  eng.capsule(lyr_handle(lyr), x1, y1, x2, y2, radius, color)
end

function layer_capsule_line(lyr, x1, y1, x2, y2, radius, color, line_width)
  eng.capsule_line(lyr_handle(lyr), x1, y1, x2, y2, radius, color, line_width or 1)
end

function layer_triangle(lyr, x1, y1, x2, y2, x3, y3, color)
  eng.triangle(lyr_handle(lyr), x1, y1, x2, y2, x3, y3, color)
end

function layer_triangle_line(lyr, x1, y1, x2, y2, x3, y3, color, line_width)
  eng.triangle_line(lyr_handle(lyr), x1, y1, x2, y2, x3, y3, color, line_width or 1)
end

function layer_polygon(lyr, vertices, color)
  eng.polygon(lyr_handle(lyr), vertices, color)
end

function layer_polygon_line(lyr, vertices, color, line_width)
  eng.polygon_line(lyr_handle(lyr), vertices, color, line_width or 1)
end

function layer_rounded_rectangle(lyr, x, y, w, h, radius, color)
  eng.rounded_rectangle(lyr_handle(lyr), x, y, w, h, radius, color)
end

function layer_rounded_rectangle_line(lyr, x, y, w, h, radius, color, line_width)
  eng.rounded_rectangle_line(lyr_handle(lyr), x, y, w, h, radius, color, line_width or 1)
end

function layer_rectangle_gradient_h(lyr, x, y, w, h, color1, color2)
  eng.rectangle_gradient_h(lyr_handle(lyr), x, y, w, h, color1, color2)
end

function layer_rectangle_gradient_v(lyr, x, y, w, h, color1, color2)
  eng.rectangle_gradient_v(lyr_handle(lyr), x, y, w, h, color1, color2)
end

--- Image object (has .handle) or pass-through same as engine.
function layer_image(lyr, img, x, y, color, flash)
  eng.draw_texture(lyr_handle(lyr), img.handle, x, y, color or 0xFFFFFFFF, flash or 0)
end

--- Raw texture userdata / handle at x, y.
function layer_texture(lyr, tex, x, y, color)
  eng.draw_texture(lyr_handle(lyr), tex, x, y, color or 0xFFFFFFFF, 0)
end

function layer_spritesheet(lyr, sheet, frame, x, y, color, flash)
  eng.draw_spritesheet_frame(lyr_handle(lyr), sheet.handle, frame, x, y, color or 0xFFFFFFFF, flash or 0)
end

function layer_animation(lyr, animation_object, x, y, color, flash)
  eng.draw_spritesheet_frame(
    lyr_handle(lyr),
    animation_object.spritesheet.handle,
    animation_object.frame,
    x, y,
    color or 0xFFFFFFFF,
    flash or 0
  )
end

function layer_text(lyr, text, f, x, y, color)
  local font_name = type(f) == 'string' and f or f.name
  eng.draw_text(lyr_handle(lyr), text, font_name, x, y, color)
end

function layer_push(lyr, x, y, r, sx, sy)
  eng.push(lyr_handle(lyr), x, y, r, sx, sy)
end

function layer_pop(lyr)
  eng.pop(lyr_handle(lyr))
end

function layer_set_blend_mode(lyr, mode)
  eng.set_blend_mode(lyr_handle(lyr), mode)
end

--- Queue this layer for compositing to the screen (after layer_render).
function layer_draw(lyr, x, y)
  eng.draw(lyr_handle(lyr), x or 0, y or 0)
end

function layer_apply_shader(lyr, shader)
  eng.apply_shader(lyr_handle(lyr), shader)
end

function layer_shader_set_float(lyr, shader, name, value)
  eng.shader_set_float(lyr_handle(lyr), shader, name, value)
end

function layer_shader_set_vec2(lyr, shader, name, x, y)
  eng.shader_set_vec2(lyr_handle(lyr), shader, name, x, y)
end

function layer_shader_set_vec4(lyr, shader, name, x, y, z, w)
  eng.shader_set_vec4(lyr_handle(lyr), shader, name, x, y, z, w)
end

function layer_shader_set_int(lyr, shader, name, value)
  eng.shader_set_int(lyr_handle(lyr), shader, name, value)
end

function layer_shader_set_texture(lyr, shader, name, texture_id, unit)
  eng.shader_set_texture(lyr_handle(lyr), shader, name, texture_id, unit or 1)
end

function layer_get_texture(lyr)
  return eng.get_texture(lyr_handle(lyr))
end

function layer_reset_effects(lyr)
  eng.reset_effects(lyr_handle(lyr))
end

function layer_clear(lyr)
  eng.clear(lyr_handle(lyr))
end

--- Process queued draw commands into this layer's FBO.
--- `clear` is optional (default true): pass false for a second render pass in
--- the same frame — processes newly queued commands ON TOP of the existing FBO
--- contents instead of clearing first (e.g. applying a post-process shader to
--- content deposited by layer_draw_from).
function layer_render(lyr, clear)
  eng.render(lyr_handle(lyr), clear)
end

function layer_draw_from(lyr, source, shader)
  eng.draw_from(lyr_handle(lyr), lyr_handle(source), shader)
end

function layer_stencil_mask(lyr)
  eng.stencil_mask(lyr_handle(lyr))
end

function layer_stencil_test(lyr)
  eng.stencil_test(lyr_handle(lyr))
end

function layer_stencil_test_inverse(lyr)
  eng.stencil_test_inverse(lyr_handle(lyr))
end

function layer_stencil_off(lyr)
  eng.stencil_off(lyr_handle(lyr))
end
