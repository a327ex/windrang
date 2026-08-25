--[[
  font — thin wrapper over C font functions.

  Usage:
    fonts.main = font_register('main', 'assets/monogram.ttf', 11)
    layer_text(game_layer, "Hello", fonts.main, 100, 50, color)

  A font is a plain table with .name, .size, .height plus query methods.
  Stays as a simple class/struct pattern for consistent access.
]]

font = class()

--- `filter` is optional: 'smooth' (grayscale atlas + linear sampling) or
--- 'rough' (1-bit mono atlas + nearest sampling). Defaults to the engine's
--- current global filter mode. The filter is baked into the atlas at load time
--- and cannot be changed afterward — load two copies if you need both.
function font:new(name, path, size, filter)
  self.name = name
  self.size = size
  self.filter = filter
  font_load(name, path, size, filter)
  self.height = font_get_height(name)
  self.ascent = font_get_ascent(name)
end

function font:text_width(text)
  return font_get_text_width(self.name, text)
end

function font:char_width(codepoint)
  return font_get_char_width(self.name, codepoint)
end

function font:glyph_metrics(codepoint)
  return font_get_glyph_metrics(self.name, codepoint)
end

-- Convenience: register a font and add it to the global `fonts` table.
function font_register(name, path, size, filter)
  local f = font(name, path, size, filter)
  if fonts then fonts[name] = f end
  return f
end
