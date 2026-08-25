--[[
  ui/core.lua — shared UI core: spacing, the uniform return, the interaction
  machine, the id guard, and layout helpers. Ported from snkrx-template's
  ui/core.lua (architecture unchanged); the section labels draw in the emoji
  language (white outlined text + a white hairline rule).

  CONVENTIONS
    • Every ui_* widget returns a TABLE via `ui_ret`: `next_x` / `next_y`
      (just past the widget + a `ui_sp.s2` gap, for chaining), the occupied
      rect (`x` / `y` / `w` / `h`), merged with the widget's own fields
      (`clicked` / `value` / `checked` / ...).
    • Interactive widgets pass `id`; OMITTING `id` makes the widget STATIC
      (no hover / click / juice). Intentionally permissive — a button with
      no id is a valid static badge. `ui_req_id` is the OPT-IN guard for
      the rare widget where a missing id is definitely a bug.
]]

-- Spacing scale (px). s2 is the standard inter-widget chaining gap (used
-- by ui_ret's next_x/next_y), s3 the default stack row gap. Roomier than
-- snkrx's values (4/6) — owner-tuned: the emoji chrome wants more air
-- between elements so silhouettes don't crowd.
ui_sp = { s1 = 2, s2 = 6, s3 = 8, s4 = 12, s5 = 16 }

-- The uniform widget return. See snkrx core.lua — unchanged.
function ui_ret(rect, fields)
  local r = fields or {}
  r.x, r.y, r.w, r.h = rect.x, rect.y, rect.w, rect.h
  r.next_x = rect.x + rect.w + ui_sp.s2
  r.next_y = rect.y + rect.h + ui_sp.s2
  return r
end

function ui_req_id(opts, name)
  return opts.id or error('emoji ui: ui_' .. name .. ' requires an id', 3)
end

--[[
  ui_interact(id, rect) -> hovered, active, clicked, pressed
  The shared immediate-mode machine: claim hot, a press grabs active +
  focus, a release-on-hot fires `clicked`. `pressed` is the press-landed-
  this-frame edge (kick juice on it). nil id → all-false (the static path).
]]
function ui_interact(id, rect)
  if not id then return false, false, false, false end
  ui_claim_hot(id, rect)
  local hovered = ui_is_hot(id)
  local pressed = false
  if hovered and mouse_is_pressed(1) then
    ui_state.active_id = id
    ui_state.focus_id  = id
    pressed = true
  end
  local active, clicked = (ui_state.active_id == id), false
  if active and mouse_is_released(1) then
    if hovered then clicked = true end
    ui_state.active_id = nil
  end
  return hovered, active, clicked, pressed
end

-- ---------------------------------------------------------------------------
-- Layout: section labels + a vertical stack cursor (rect_cut still splits
-- regions; these cover the common cases).
-- ---------------------------------------------------------------------------

-- An uppercase section label + a white hairline rule under it. Lana, not
-- FatPixel — FatPixel renders ~3x its reported height and is reserved for
-- rare deliberate display use.
-- opts: x, y, w, text, spec?.
function ui_heading(o)
  ui_text({ rect = { x = o.x, y = o.y, w = o.w, h = fonts.main.height },
            text = string.upper(o.text), font = fonts.main,
            align_v = 'top', spec = o.spec })
  local ly = o.y + fonts.main.height + ui_sp.s1
  ui_content_rect(o.x, ly, o.w, 1, white, o.spec)
  return { next_y = ly + ui_sp.s3, next_x = o.x + o.w }
end

-- A muted uppercase label, no rule. opts: x, y, text, spec?.
function ui_sublabel(o)
  ui_text({ rect = { x = o.x, y = o.y, w = 9999, h = fonts.main.height },
            text = string.upper(o.text), font = fonts.main,
            color = fg_dark, align_v = 'top', spec = o.spec })
  return { next_y = o.y + fonts.main.height + ui_sp.s2 }
end

-- Vertical layout cursor over a region rect. :take(h) returns a row and
-- advances; :skip / :gap advance; :heading / :sublabel draw + advance.
local stack_mt = {}
stack_mt.__index = stack_mt
function stack_mt:take(h)
  local r = { x = self.x, y = self.y, w = self.w, h = h }
  self.y = self.y + h + self._gap
  return r
end
function stack_mt:skip(n) self.y = self.y + n; return self end
function stack_mt:gap(n)  self.y = self.y + (n or self._gap); return self end
function stack_mt:heading(text)
  self.y = ui_heading({ text = text, x = self.x, y = self.y, w = self.w }).next_y
  return self
end
function stack_mt:sublabel(text)
  self.y = ui_sublabel({ text = text, x = self.x, y = self.y }).next_y
  return self
end
function ui_stack(rect, gap)
  return setmetatable({ x = rect.x, y = rect.y, w = rect.w, _gap = gap or ui_sp.s3 },
                      stack_mt)
end
