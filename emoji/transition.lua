--[[
  emoji/transition.lua — the circle-wipe screen transition (SNKRX heritage,
  via emoji-merge / Emoji Aimer): a colored circle expands from the screen
  center covering everything, a mid callback fires while covered (swap
  scenes / reset state there), then the circle contracts to reveal.

  Host contract:
    - declare a 'transition' layer LAST in emoji_layers (outlined, above
      the cursor) — the wipe covers everything, chunky black edge included.
    - call transition_update(dt) once per update() (ticks + queues the draw).
    - transition_start(mid_cb, opts?) — opts: color (yellow), expand (0.5s),
      hold (0.25s), contract (0.5s), and the wipe ORIGIN: either a fixed
      point (x, y — default screen center) or origin = function() -> x, y,
      re-evaluated at the start of the expand AND the contract (Emoji
      Aimer's wipe recenters on the cursor's CURRENT position for the
      reveal). No-op if a wipe is already running.
  transition_active is true for the whole wipe (guard input on it).
]]

transition_active = false

local tr = { radius = 0, color = nil, x = 0, y = 0 }
local tr_timer = timer_new()

-- Radius needed for a circle at (x, y) to cover the whole screen, + margin.
local function cover_radius(x, y)
  local dx = math.max(x, gw - x)
  local dy = math.max(y, gh - y)
  return math.length(dx, dy)*1.1
end

function transition_start(mid_cb, opts)
  if transition_active then return end
  opts = opts or {}
  transition_active = true
  tr.color  = opts.color or yellow
  tr.radius = 0
  local get_origin = opts.origin
  if get_origin then tr.x, tr.y = get_origin()
  else tr.x, tr.y = opts.x or gw/2, opts.y or gh/2 end
  timer_tween(tr_timer, opts.expand or 0.5, tr, { radius = cover_radius(tr.x, tr.y) },
              math.cubic_in_out, function()
    if mid_cb then mid_cb() end
    timer_after(tr_timer, opts.hold or 0.25, function()
      if get_origin then tr.x, tr.y = get_origin() end
      tr.radius = cover_radius(tr.x, tr.y)
      timer_tween(tr_timer, opts.contract or 0.5, tr, { radius = 0 },
                  math.cubic_in_out, function()
        transition_active = false
      end)
    end)
  end)
end

function transition_update(dt)
  timer_update(tr_timer, dt)
  if tr.radius > 0.5 then
    layer_circle(transition_layer, tr.x, tr.y, tr.radius, tr.color())
  end
end
