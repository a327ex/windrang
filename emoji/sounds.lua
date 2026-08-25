--[[
  emoji/sounds.lua — audio conventions: the sfx pipeline + the (deliberately
  empty) bank. This is KVP's sound stack (Horse Game, 2026-08-01 era) ported
  bank-side: DSP + per-sound pitch ranges + the offset knob + per-key mutes +
  family re-rolls + lazy loading. The KVP-only layers (sound MOMENTS, item /
  trigger bindings — the F7 effect-lab machinery) are NOT here; they come
  over if/when this game grows its own effect lab.

  ⛔ THE TEMPLATE SHIPS NO SOUNDS (owner decision 2026-07-18): sounds are
  chosen game-by-game, per fork. Games DECLARE theirs with
  `sound_declare(key, path)` + a volumes entry (declaring does no I/O — see
  LAZY LOADING below).

  sfx(handle, volume, pitch) — nil-safe play with per-sound runtime DSP
  (bitcrush + sample-rate reduce), pitch range, offset and mutes, all looked
  up from emoji/sound_tuning.lua (path -> { bits, sr_div, pitch_lo?,
  pitch_hi?, offset? }; empty = clean at the classic 0.95-1.05 jitter).
  nil-safety is load-bearing: toolkit call sites (e.g. ui/juice.lua's hover
  pair) reference sounds.ui_hover / sounds.ui_pop that may not exist — they
  no-op silently until a game defines them.

  MUTES: SOUND_DISABLED[key] = true drops one recording. A muted variant
  makes its family re-roll among what remains (muting boom2 makes boom roll
  1-or-3, never silence); a muted single key is simply silent. Toggled by
  the F3 sound tool, shipped in emoji/sound_mutes.lua.
]]

sound_tuning = require('emoji.sound_tuning')

SOUND_DISABLED = {}
do
  local ok, t = pcall(require, 'emoji.sound_mutes')
  if ok and type(t) == 'table' then
    for _, k in ipairs(t) do SOUND_DISABLED[k] = true end
  end
end

-- the family's roll, respecting mutes: prefer the already-rolled incoming
-- variant when it is enabled; else roll among the enabled ones; nil = none
local function enabled_variant(fam, n, incoming)
  if incoming and not SOUND_DISABLED[incoming] then return incoming end
  local pool = {}
  for i = 1, n do
    local k = fam .. i
    if sounds[k] and not SOUND_DISABLED[k] then pool[#pool + 1] = k end
  end
  if #pool == 0 then return nil end
  return pool[random_int(1, #pool)]
end

-- handle -> key reverse lookup (sfx receives handles; mutes are keyed).
-- Cached; entries self-invalidate when a key is reloaded (drag-drop import).
local key_cache = {}
local function sound_key_of(h)
  local k = key_cache[h]
  if k and sounds[k] == h then return k end
  for name, hh in pairs(sounds) do
    if hh == h then key_cache[h] = name; return name end
  end
end

function sound_moment_of(key)          -- 'boom2' -> 'boom'; 'magnet' -> 'magnet'
  return (key:gsub('%d+$', ''))
end

-- how many variants a family has (name1..nameN); 0 = not a family
-- ⚠ Probes SOUND_FILES, not `sounds`: through the lazy __index, asking whether
-- `boom4` exists would LOAD boom1..3 as a side effect of counting them.
function sound_family_n(name)
  local n = 0
  while SOUND_FILES[name .. (n + 1)] or rawget(sounds, name .. (n + 1)) do n = n + 1 end
  return n
end

-- When non-nil, every voice sfx_raw starts is appended here. Armed only for
-- the duration of one sfx_tracked call.
local collect_voices = nil

-- the wired play path: DSP lookup + the engine call. Never resolves mutes.
local function sfx_raw(handle, volume, pitch)
  if not handle then return end
  -- normalize to the game-relative 'assets/...' path: hosted on the site the
  -- engine stores the games/<name>/-prefixed load path, but sound_tuning.lua
  -- keys are written by the desktop tuner as 'assets/...'
  local path   = sound_get_path(handle) or ''
  local tune   = sound_tuning[path:match('assets/.*') or path]
  local bits   = tune and tune.bits   or 16
  local sr_div = tune and tune.sr_div or 1
  -- per-sound PITCH RANGE: every play rolls inside [pitch_lo, pitch_hi]
  -- (default the classic 0.95..1.05 jitter; lo == hi = fixed pitch). An
  -- explicit `pitch` argument from a call site still wins.
  if not pitch then
    local lo = tune and tune.pitch_lo or 0.95
    local hi = tune and tune.pitch_hi or 1.05
    pitch = random_float(lo, hi)
  end
  -- ── THE OFFSET ──────────────────────────────────────────────────────────
  --   offset > 0  DELAY. Schedule the play.
  --   offset < 0  EARLIER — start further INTO the clip, skipping a wind-up
  --               baked into its head, so the impact arrives sooner.
  -- On juice_unscaled_timer so a delay is REAL time — slow-mo must not
  -- stretch the gap between a hit and its sound.
  local off = (tune and tune.offset) or 0
  if off > 0 and not collect_voices then
    -- ⚠ not for a TRACKED play: sfx_tracked needs the voice id back now
    timer_after(juice_unscaled_timer, off, function()
      sound_play_handle(handle, volume or 1, pitch, bits, sr_div, 0)
    end)
    return
  end
  local v = sound_play_handle(handle, volume or 1, pitch, bits, sr_div,
                              (off < 0) and -off or 0)
  if collect_voices and v and v >= 0 then collect_voices[#collect_voices + 1] = v end
end

-- play "the wired sound": the incoming rolled variant if it is enabled, a
-- re-rolled enabled sibling if not, silence if the whole family (or a muted
-- single key) is out
local function play_wired(handle, key, moment, volume, pitch)
  if not SOUND_DISABLED[key] then sfx_raw(handle, volume, pitch) return end
  local n = (moment ~= key) and sound_family_n(moment) or 0
  if n > 0 then
    local k2 = enabled_variant(moment, n, nil)
    if k2 then sfx_raw(sounds[k2], volumes[k2] or volume, pitch) end
  end
end

-- ── STOPPABLE PLAYS ──────────────────────────────────────────────────────────
-- For a sound whose length is set by the CLIP but whose meaning is set by the
-- GAME. Play with sfx_tracked, keep the returned list, stop it when the thing
-- it describes is over. Returns a LIST of voice ids.
function sfx_tracked(handle, volume, pitch)
  local vs = {}
  collect_voices = vs
  sfx(handle, volume, pitch)
  collect_voices = nil
  return vs
end

-- Stop a tracked play. `fade` (seconds) ramps the voices down first — a hard
-- cut on a clip with body to it clicks. Needs a timer to ride: pass the
-- caller's, or any timer still updated when the fade lands.
function sfx_stop(vs, fade, t)
  if not vs or #vs == 0 then return end
  local function kill()
    for _, v in ipairs(vs) do sound_handle_stop(v) end
  end
  if not fade or fade <= 0 or not t then kill() return end
  local v0 = {}
  for i, v in ipairs(vs) do v0[i] = 1 end
  timer_during(t, fade, function(dt, progress)
    local u = 1 - math.clamp(progress or 0, 0, 1)
    for i, v in ipairs(vs) do sound_handle_set_volume(v, v0[i]*u) end
  end, kill)
end

-- audition ONE recording exactly as stored — no mute, no re-roll. The F3
-- panel previews through this so clicking boom2's row plays boom2.
function sfx_preview(handle, volume, pitch)
  sfx_raw(handle, volume, pitch)
end

function sfx(handle, volume, pitch)
  if not handle then return end
  local key = sound_key_of(handle)
  if key then play_wired(handle, key, sound_moment_of(key), volume, pitch)
  else sfx_raw(handle, volume, pitch) end
end

-- Variation pick: sfx_any('grass_land', 3, vol) plays grass_land1..3 —
-- the family's 2-3-recorded-variations convention. Nil-safe like sfx.
-- Volume is taken from the PLAYED variant's own key (volumes[prefixN]) so the
-- F3 tuner — which edits volume per loaded sound name — is respected in-game;
-- the passed `volume` is only a fallback for variants with no volumes entry.
function sfx_any(prefix, n, volume, pitch)
  local name = prefix .. random_int(1, n)
  sfx(sounds[name], volumes[name] or volume, pitch)
end

-- Layered pair: two samples stacked at different volumes (the family's
-- hover/click/crit chords).
function sfx_pair(a, vol_a, b, vol_b, pitch)
  sfx(a, vol_a, pitch)
  sfx(b, vol_b, pitch)
end

-- ── LAZY LOADING ─────────────────────────────────────────────────────────────
-- `sound_load` is not cheap: it reads the file AND runs a verification decode
-- on every clip. So DECLARING a sound and LOADING it are separate. SOUND_FILES
-- is pure data (key -> path, no I/O); `sounds` loads a key the first time
-- anything touches it and caches the handle in the table itself, so every
-- `sfx(sounds.hop, ...)` call site is unchanged and pays the cost once.
-- ⚠ ANYTHING THAT ENUMERATES SOUNDS MUST WALK SOUND_FILES, NOT `sounds` —
-- pairs() over a lazy table sees only what has already been touched.
SOUND_FILES = {}

sounds = setmetatable({}, {
  __index = function(t, k)
    local path = SOUND_FILES[k]
    if not path then return nil end
    local h = sound_load(path)
    rawset(t, k, h)
    return h
  end,
})

-- Declare without loading. Replaces `sounds.x = sound_load(path)` at boot.
function sound_declare(key, path)
  SOUND_FILES[key] = path
end

-- Is this key loaded ALREADY? (Enumerators that must not trigger a load.)
function sound_is_loaded(key)
  return rawget(sounds, key) ~= nil
end

-- Every declared key, loaded or not — the list every enumerator wants.
function sound_keys()
  local out = {}
  for k in pairs(SOUND_FILES) do out[#out + 1] = k end
  for k in pairs(sounds) do if not SOUND_FILES[k] then out[#out + 1] = k end end
  table.sort(out)
  return out
end

-- THE WARMER. Lazy alone would stutter the first time each sound fires. This
-- walks the declaration list in the background (call from update()) so the
-- bank is warm within a few seconds of boot. Budgeted in MILLISECONDS, not
-- files — a big clip simply takes a frame to itself. Returns true when done.
local warm_queue, warm_i = nil, 1
function sounds_warm_step(budget_ms)
  if warm_queue and warm_i > #warm_queue then return true end
  if not warm_queue then
    warm_queue = {}
    for k in pairs(SOUND_FILES) do warm_queue[#warm_queue + 1] = k end
    table.sort(warm_queue)
  end
  local t0     = os.clock()
  local budget = (budget_ms or 2)/1000
  while warm_i <= #warm_queue do
    local k = warm_queue[warm_i]
    warm_i = warm_i + 1
    if rawget(sounds, k) == nil then local _ = sounds[k] end
    if os.clock() - t0 >= budget then return false end
  end
  return true
end

sounds.ball_wall = sound_load('assets/ball_wall.ogg')   -- the one test sound

volumes = {
  ball_wall = 0.36,
}

-- Volume override layer (parallels sound_tuning for DSP). The host sets its
-- baseline `volumes.X = ...` entries, then calls volumes_apply_overrides() ONCE
-- (after the last baseline). That snapshots the baseline as volumes_defaults and
-- loads emoji/volume_tuning.lua on top; the F3 tuner edits volumes live and
-- writes volume_tuning.lua (diffing against the snapshot). Games that skip the
-- call still get live volume editing — just no cross-run persistence.
volumes_defaults = nil
function volumes_apply_overrides()
  volumes_defaults = {}
  for k, v in pairs(volumes) do volumes_defaults[k] = v end
  local ok, overrides = pcall(require, 'emoji.volume_tuning')
  if ok and type(overrides) == 'table' then
    for k, v in pairs(overrides) do volumes[k] = v end
  end
end
