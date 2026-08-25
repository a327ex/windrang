--[[
  ui/rect.lua — RectCut layout primitive for the UI toolkit.

  A rect is a plain table {x, y, w, h}. Three families of operations:

    cut_*(r, n) — mutates r (eats n pixels from one side), returns the eaten slice.
    get_*(r, n) — pure: returns a slice of r without mutating.
    add_*(r, n) — pure: returns a new rect adjacent to r (extends outward).

  Plus utilities: contract / expand (inset / outset), center (place a w×h
  rect centered inside another), split_h / split_v (divide into n equal parts).

  Origin: cut/get/add are the Halt RectCut pattern. Cuts are destructive on
  the parent so successive cuts walk the rect. Canonical idiom:
    local topbar = rect_cut_top(r, 24)   -- r is now the body below the topbar
    local botbar = rect_cut_bot(r, 22)   -- r is now the body between bars

  Verbatim from the Anchor App (Anchor2/app/rect.lua) — proven, unchanged.
]]

function rect_new(x, y, w, h)
  return {x = x, y = y, w = w, h = h}
end

-- cut_*: mutate r (eat n from one side), return the eaten slice.
function rect_cut_left(r, n)
  local s = {x = r.x, y = r.y, w = n, h = r.h}
  r.x = r.x + n
  r.w = r.w - n
  return s
end
function rect_cut_right(r, n)
  r.w = r.w - n
  return {x = r.x + r.w, y = r.y, w = n, h = r.h}
end
function rect_cut_top(r, n)
  local s = {x = r.x, y = r.y, w = r.w, h = n}
  r.y = r.y + n
  r.h = r.h - n
  return s
end
function rect_cut_bot(r, n)
  r.h = r.h - n
  return {x = r.x, y = r.y + r.h, w = r.w, h = n}
end

-- get_*: return an edge slice without mutating r.
function rect_get_left(r, n)  return {x = r.x,            y = r.y,            w = n,   h = r.h} end
function rect_get_right(r, n) return {x = r.x + r.w - n,  y = r.y,            w = n,   h = r.h} end
function rect_get_top(r, n)   return {x = r.x,            y = r.y,            w = r.w, h = n}   end
function rect_get_bot(r, n)   return {x = r.x,            y = r.y + r.h - n,  w = r.w, h = n}   end

-- add_*: return a rect adjacent to r (extends outward by n on one side).
function rect_add_left(r, n)  return {x = r.x - n,    y = r.y,        w = n,   h = r.h} end
function rect_add_right(r, n) return {x = r.x + r.w,  y = r.y,        w = n,   h = r.h} end
function rect_add_top(r, n)   return {x = r.x,        y = r.y - n,    w = r.w, h = n}   end
function rect_add_bot(r, n)   return {x = r.x,        y = r.y + r.h,  w = r.w, h = n}   end

-- contract / expand: inset / outset.
-- One arg → uniform on all sides. Four args (CSS order: top, right, bot, left) → per-side.
function rect_contract(r, t, ri, b, l)
  if ri == nil then ri, b, l = t, t, t end
  return {x = r.x + l, y = r.y + t, w = r.w - l - ri, h = r.h - t - b}
end
function rect_expand(r, t, ri, b, l)
  if ri == nil then ri, b, l = t, t, t end
  return {x = r.x - l, y = r.y - t, w = r.w + l + ri, h = r.h + t + b}
end

-- center: place a w×h rect centered inside r.
function rect_center(r, w, h)
  return {x = r.x + (r.w - w)/2, y = r.y + (r.h - h)/2, w = w, h = h}
end

-- split_h / split_v: divide r into n equal pieces along x or y.
-- Leftover pixels distribute to the first slices so the union covers r exactly.
function rect_split_h(r, n)
  local out = {}
  local each = math.floor(r.w/n)
  local extra = r.w - each*n
  local x = r.x
  for i = 1, n do
    local w = each + (i <= extra and 1 or 0)
    out[i] = {x = x, y = r.y, w = w, h = r.h}
    x = x + w
  end
  return out
end
function rect_split_v(r, n)
  local out = {}
  local each = math.floor(r.h/n)
  local extra = r.h - each*n
  local y = r.y
  for i = 1, n do
    local h = each + (i <= extra and 1 or 0)
    out[i] = {x = r.x, y = y, w = r.w, h = h}
    y = y + h
  end
  return out
end
