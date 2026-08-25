--[[
  emoji/ — the Twitter-emoji visual-style toolkit. require('emoji') (AFTER
  require('anchor')({...})) loads everything:

    palette.lua  — the Twemoji named colors (bg_color / fg / yellow / ...)
    pipeline.lua — the outline + drop-shadow layer pipeline
                   (emoji_layers { ... } + emoji_render())
    juice.lua    — hitfx springs/flash, directional squash, slow_time,
                   camera_punch, juice_update
    fx.lua       — hit_circle / hit_effect / hit_particle / emoji_particle
                   + spawn_* wrappers + the global fxs list
    cursor.lua   — the 👆 emoji cursor (spawn_cursor)
    sounds.lua   — sfx wrapper (runtime DSP hook) + starter EBB foley bank

  Plus the starter assets loaded below: core emoji sprites, the 'hit1'
  impact spritesheet, and the three standard fonts. Top up emoji sprites
  with the /download-emoji skill (Twemoji 512x512 from emojipedia's CDN).

  This file is the toolkit aggregator; structural things (physics matrix,
  the layer stack declaration, camera, entity lists, update/draw order)
  stay explicit in main.lua.
]]

require('emoji.palette')
require('emoji.pipeline')
require('emoji.effect')  -- four-axis effect system (pattern × color × dither × shape)
require('emoji.juice')
require('emoji.fx')
require('emoji.plants')  -- reactive vegetation (EBB mechanics + plant death)
require('emoji.cursor')
require('emoji.transition')  -- the circle-wipe screen transition
require('emoji.sounds')
require('emoji.text')    -- rich-text tags + the typewriter ledger
require('emoji.ui')     -- the UI toolkit (see emoji/ui/init.lua host contract)
require('emoji.effect_lab')  -- F5 effect inspector (built on the toolkit)
require('emoji.sound_tuner') -- F3 bitcrush/sample-rate tuner

-- ── starter images (Twemoji 512x512 PNGs) ─────────────────────────────────
slight_smile               = image_load('slight_smile', 'assets/slight_smile.png')
no_mouth                   = image_load('no_mouth',     'assets/no_mouth.png')
no_mouth_hit               = image_load('no_mouth_hit', 'assets/no_mouth_hit.png')
star_img                   = image_load('star',         'assets/star.png')
dash_img                   = image_load('dash',         'assets/dash.png')
cloud_img                  = image_load('cloud',        'assets/cloud.png')
backhand_index_pointing_up = image_load('backhand_index_pointing_up',
                                        'assets/backhand_index_pointing_up.png')
x_mark_img                 = image_load('x_mark',       'assets/x_mark.png')

-- Glyph sprites (gray-bg / white-glyph, recolorable via recolor.frag) for
-- damage_number / spawn_emoji_text / emoji_badge_text. Indexed by CHARACTER
-- ("0".."9", "a".."z", "+", "-").
digit_imgs = {}
for i = 0, 9 do
  digit_imgs[tostring(i)] = image_load('digit_' .. i, 'assets/' .. i .. '.png')
end
for c = string.byte('a'), string.byte('z') do
  local ch = string.char(c)
  digit_imgs[ch] = image_load('glyph_' .. ch, 'assets/' .. ch .. '.png')
end
digit_imgs['+'] = image_load('digit_plus',  'assets/plus.png')
digit_imgs['-'] = image_load('digit_minus', 'assets/minus.png')

-- Plant species sprites (the emoji/plants.lua module's spawn grammar).
plant_imgs = {
  seedling         = image_load('seedling', 'assets/seedling.png'),
  sheaf            = image_load('sheaf',    'assets/sheaf.png'),
  blossom          = image_load('blossom',  'assets/blossom.png'),
  tulip            = image_load('tulip',    'assets/tulip.png'),
  four_leaf_clover = image_load('four_leaf_clover', 'assets/four_leaf_clover.png'),
}

-- ── spritesheets ──────────────────────────────────────────────────────────
spritesheet_register('hit1', 'assets/hit1.png', 96, 48)

-- ── fonts ─────────────────────────────────────────────────────────────────
font_register('main', 'assets/LanaPixel.ttf',   11)   -- body / default
font_register('big',  'assets/FatPixelFont.ttf', 8)   -- chunky display headers
font_register('mid',  'assets/Awesome 9.ttf',   16)   -- mid-size headers / score

-- ── effect system boot ────────────────────────────────────────────────────
-- Installs the four-axis draw shader (replaces the engine default) and
-- pushes the 22-token palette to u_palette[]. Shader default state is
-- passthrough, so everything renders identically until a spec is set.
palette_init()
effect_setup()
