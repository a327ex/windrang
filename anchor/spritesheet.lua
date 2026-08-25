--[[
  spritesheet — thin wrapper for C spritesheet handles.

  Usage:
    spritesheets.hit = spritesheet_register('hit', 'assets/hit1.png', 96, 48)
    layer_spritesheet(game_layer, spritesheets.hit, 1, 100, 100)

  A spritesheet is a plain wrapper with .handle, .frame_width, .frame_height, .frames.
]]

spritesheet = class()

function spritesheet:new(handle)
  self.handle = handle
  self.frame_width = spritesheet_get_frame_width(handle)
  self.frame_height = spritesheet_get_frame_height(handle)
  self.frames = spritesheet_get_total_frames(handle)
end

-- Load a spritesheet from a file, wrap it, and add to the global `spritesheets` table.
-- (Named _register instead of _load to avoid colliding with the C `spritesheet_load`.)
function spritesheet_register(name, path, frame_w, frame_h)
  local handle = spritesheet_load(path, frame_w, frame_h)
  local sheet = spritesheet(handle)
  if spritesheets then spritesheets[name] = sheet end
  return sheet
end
