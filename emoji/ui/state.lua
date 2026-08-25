--[[
  ui/state.lua — frame-local UI interaction state.

  `ui_state` holds the three interaction IDs, rebuilt every frame:
    hot_id     widget under the cursor this frame
    active_id  widget the mouse-down landed on (persists until release)
    focus_id   widget last clicked (persists until the next click)

  `ui_state_begin_frame()` clears hot_id; call it once per frame before
  any widget calls (the gallery does this in ui_gallery_update; a real
  game calls it once per frame too). Widget IDs are explicit, caller-
  provided strings — no auto-IDs.

  This is the rules-based, frame-local interaction layer the project's
  action-vs-rules UI doctrine sanctions — it is NOT hidden persistent
  state. Persistent UI state (what occupies a slot, a drag in progress)
  is action-based and lives in caller-owned data, never here.
]]

ui_state = { hot_id = nil, active_id = nil, focus_id = nil }

-- True for any frame a ui_text_input is focused (the field sets it
-- during draw). Reset every frame in ui_state_begin_frame, re-set by
-- the focused field. Readers (hotkey suppression) use the snapshot
-- below instead — it carries last frame's value across this frame's
-- reset, so the suppression is one-frame-lagged in the safe direction
-- (when a field is freshly focused, hotkeys are suppressed from the
-- NEXT frame on; when a field unfocuses, hotkeys re-enable one frame
-- after).
ui_capturing_text     = false
ui_capturing_text_was = false  -- snapshot of last frame's end value

-- Raised by the caller while a modal is open, BEFORE drawing the
-- screen behind it — ui_claim_hot then refuses every widget, so the
-- background goes inert. ui_modal lowers it again for its own content
-- (which is drawn last, on top). Reset every frame.
ui_input_locked = false

function ui_state_begin_frame()
  ui_state.hot_id       = nil
  ui_capturing_text_was = ui_capturing_text
  ui_capturing_text     = false
  ui_input_locked       = false
end

function ui_is_hot(id)     return ui_state.hot_id    == id end
function ui_is_active(id)  return ui_state.active_id == id end
function ui_is_focused(id) return ui_state.focus_id  == id end

-- Point-in-rect test. r is a {x, y, w, h} table (a RectCut rect).
function ui_point_in_rect(px, py, r)
  return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h
end

--[[
  ui_claim_hot(id, r)

  Claim hot status for widget `id` if the cursor is inside rect r.
  Respects "active wins": while some other widget is active, nothing
  else can become hot. Last caller in a frame wins ties — the topmost
  widget (drawn last) takes hot when widgets overlap.
]]
function ui_claim_hot(id, r)
  if ui_input_locked then return end
  local mx, my = mouse_position()
  if not ui_point_in_rect(mx, my, r) then return end
  if ui_state.active_id ~= nil and ui_state.active_id ~= id then return end
  ui_state.hot_id = id
end
