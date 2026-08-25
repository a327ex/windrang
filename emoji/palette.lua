--[[
  emoji/palette.lua — the Twitter-emoji (Twemoji) named palette.

  Plain global color objects, matching the idiom of every emoji game
  (Emoji Ball Battles, Emoji Aimer, emoji-ball-bounce, ...). Exact RGB
  values carried over from those games — these are sampled from the
  Twemoji set itself, so anything drawn in them sits naturally next to
  the emoji sprites.

  Anchor colors are CALLABLE: pass `yellow()` (the packed int) to layer_*
  draws, mutate fields on the table (`yellow.a = 128`) before calling.

  NOTE (from Emoji Aimer): if a game reassigns a global named `gold` to
  its currency integer, the medal color must live under a different name
  or `gold()` becomes a call on a number and crashes the draw pass. The
  template names the medal color `medal_gold` from the start.
]]

white      = color(255, 255, 255)
black      = color(0, 0, 0)
gray       = color(128, 128, 128)
bg_color   = color(48, 49, 50)      -- the charcoal page (#303132)
fg         = color(231, 232, 233)   -- off-white foreground (#e7e8e9)
fg_dark    = color(201, 202, 203)
yellow     = color(253, 205, 86)
star_yellow= color(255, 172, 51)    -- the star emoji's deeper yellow
orange     = color(244, 146, 0)
blue       = color(83, 175, 239)
green      = color(122, 179, 87)
red        = color(223, 37, 64)
purple     = color(172, 144, 216)
brown      = color(193, 105, 79)
pink       = color(244, 154, 194)
bowstring  = color(217, 158, 130)   -- sandy/tan rope tint

-- Medal disc-face colors sampled from Twemoji 1f947/1f948/1f949.
bronze     = color(248, 136, 56)
silver     = color(200, 208, 216)
medal_gold = color(248, 168, 48)

-- Sky gradient (subtle blue -> off-white, the EBB arena backdrop).
sky_top    = color(135, 206, 235)
sky_bottom = color(231, 232, 233)   -- same as fg

-- Wall/board frame tint: fg warmed 10% toward yellow.
wall_color = color_mix(fg, yellow, 0.1)

-- =============================================================================
-- THE EFFECT ADAPTER — what emoji/effect.lua consumes (the snkrx/palette.lua
-- pattern). Maps the EXISTING globals above into the token tables; defines
-- nothing new.
--
-- palette_token_names ORDER == the shader's u_palette[] index order. The
-- shader declares `uniform vec4 u_palette[26]`; we write 22 tokens and leave
-- 22..25 as headroom. If you ADD a token, append it here AND update the index
-- comment in assets/draw_shader.frag.
-- =============================================================================

palette_token_names = {
  -- 0..5 : chrome ladder (dark → light)
  'black', 'bg_color', 'gray', 'fg_dark', 'fg', 'white',
  -- 6..13 : accent hue wheel
  'red', 'orange', 'yellow', 'star_yellow', 'green', 'blue', 'purple', 'pink',
  -- 14..18 : extras
  'brown', 'bowstring', 'bronze', 'silver', 'medal_gold',
  -- 19..21 : environment
  'sky_top', 'sky_bottom', 'wall_color',
}

-- name → color OBJECT. effect_write_palette reads c.r/.g/.b off these;
-- spec_color() returns one of these so FX/particles tint to the spec color.
palette = {
  black = black, bg_color = bg_color, gray = gray, fg_dark = fg_dark,
  fg = fg, white = white,
  red = red, orange = orange, yellow = yellow, star_yellow = star_yellow,
  green = green, blue = blue, purple = purple, pink = pink,
  brown = brown, bowstring = bowstring, bronze = bronze, silver = silver,
  medal_gold = medal_gold,
  sky_top = sky_top, sky_bottom = sky_bottom, wall_color = wall_color,
}

-- name → 0-based index. effect_set converts a spec's color_a/color_b string
-- into the integer the shader indexes u_palette[] with.
palette_token_index = {}
for i, n in ipairs(palette_token_names) do
  palette_token_index[n] = i - 1
end

palette_token_count = #palette_token_names

-- Push the active palette to the shader's u_palette[] uniform. No-op until
-- effect_setup has installed the shader (it re-pushes on install).
function palette_init()
  if effect_write_palette then effect_write_palette() end
end

-- =============================================================================
-- BREATHE PARTNERS — each token's neighbor for a 2-token `mix` breathe (the
-- SNKRX shimmer recipe: color='mix' between a token and its partner, swept by
-- an organic field). The emoji style defaults to FLAT — this table mostly
-- feeds the F5 inspector's color_b default and the ui_color='mix' A/B mode.
-- Chrome partners up the lightness ladder; accents to the next hue; extras
-- to their nearest hue.
-- =============================================================================
palette_breathe_partner = {
  -- chrome ladder, dark → light
  black = 'bg_color', bg_color = 'gray', gray = 'fg_dark', fg_dark = 'fg',
  fg = 'white', white = 'fg',
  -- accent hue wheel
  red = 'orange', orange = 'yellow', yellow = 'star_yellow',
  star_yellow = 'green', green = 'blue', blue = 'purple', purple = 'pink',
  pink = 'red',
  -- extras → nearest hue
  brown = 'orange', bowstring = 'brown', bronze = 'orange',
  silver = 'fg', medal_gold = 'yellow',
  -- environment
  sky_top = 'sky_bottom', sky_bottom = 'sky_top', wall_color = 'fg',
}
