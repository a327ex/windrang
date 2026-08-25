--[[
  emoji/sound_tuning.lua — per-sound runtime DSP + pitch-range table,
  consulted by sfx() on every play. Maps asset path -> { bits, sr_div,
  pitch_lo?, pitch_hi?, offset? }. `offset` is seconds: positive DELAYS the
  play, negative starts that far INTO the clip (skipping a wind-up), which
  is the only way to make an impact land earlier. Auto-saved by the tool;
  safe to edit by hand. Sounds without an entry play clean at the
  0.95-1.05 jitter.
]]

return {
  ['assets/ball_wall.ogg'] = { bits = 8, sr_div = 3 },
  ['assets/sounds/grass_land1.ogg'] = { bits = 8, sr_div = 3 },
  ['assets/sounds/grass_land2.ogg'] = { bits = 8, sr_div = 3 },
  ['assets/sounds/grass_land3.ogg'] = { bits = 8, sr_div = 3 },
  ['assets/sounds/hop.ogg'] = { bits = 8, sr_div = 3 },
  ['assets/sounds/land_impact.ogg'] = { bits = 8, sr_div = 3 },
}
