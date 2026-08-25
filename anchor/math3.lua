--[[
  math3 — 3D vector and quaternion helpers.

  Conventions (match the engine's physics3/layer3 bindings):
    - Y-up, right-handed, meters.
    - Quaternions are passed/returned as 4 numbers: x, y, z, w.
    - Vectors are passed/returned as 3 numbers: x, y, z.
  All functions are plain multiple-return functions — no vector tables, no
  allocation per call.
]]

-- Vectors ---------------------------------------------------------------------

function vec3_length(x, y, z)
  return math.sqrt(x*x + y*y + z*z)
end

function vec3_distance(ax, ay, az, bx, by, bz)
  local dx, dy, dz = bx - ax, by - ay, bz - az
  return math.sqrt(dx*dx + dy*dy + dz*dz)
end

function vec3_normalize(x, y, z)
  local len = math.sqrt(x*x + y*y + z*z)
  if len < 1e-12 then return 0, 0, 0 end
  return x/len, y/len, z/len
end

function vec3_dot(ax, ay, az, bx, by, bz)
  return ax*bx + ay*by + az*bz
end

function vec3_cross(ax, ay, az, bx, by, bz)
  return ay*bz - az*by, az*bx - ax*bz, ax*by - ay*bx
end

function vec3_lerp(ax, ay, az, bx, by, bz, t)
  return ax + (bx - ax)*t, ay + (by - ay)*t, az + (bz - az)*t
end

-- Quaternions ------------------------------------------------------------------

function quat_identity()
  return 0, 0, 0, 1
end

--[[
  quat_from_axis_angle(ax, ay, az, angle)
  Axis must be normalized. Angle in radians.
]]
function quat_from_axis_angle(ax, ay, az, angle)
  local h = angle*0.5
  local s = math.sin(h)
  return ax*s, ay*s, az*s, math.cos(h)
end

--[[
  quat_from_euler(yaw, pitch, roll)
  Yaw around Y (heading), pitch around X, roll around Z. Radians.
  Applied in yaw → pitch → roll order.
]]
function quat_from_euler(yaw, pitch, roll)
  local cy, sy = math.cos(yaw*0.5), math.sin(yaw*0.5)
  local cp, sp = math.cos(pitch*0.5), math.sin(pitch*0.5)
  local cr, sr = math.cos(roll*0.5), math.sin(roll*0.5)
  -- q = qy(yaw) * qx(pitch) * qz(roll)
  local x = cy*sp*cr + sy*cp*sr
  local y = sy*cp*cr - cy*sp*sr
  local z = cy*cp*sr - sy*sp*cr
  local w = cy*cp*cr + sy*sp*sr
  return x, y, z, w
end

function quat_mul(ax, ay, az, aw, bx, by, bz, bw)
  return
    aw*bx + ax*bw + ay*bz - az*by,
    aw*by + ay*bw + az*bx - ax*bz,
    aw*bz + az*bw + ax*by - ay*bx,
    aw*bw - ax*bx - ay*by - az*bz
end

function quat_normalize(x, y, z, w)
  local len = math.sqrt(x*x + y*y + z*z + w*w)
  if len < 1e-12 then return 0, 0, 0, 1 end
  return x/len, y/len, z/len, w/len
end

--[[
  quat_rotate_vec(qx, qy, qz, qw, vx, vy, vz)
  Rotates vector v by quaternion q. Returns the rotated vector.
]]
function quat_rotate_vec(qx, qy, qz, qw, vx, vy, vz)
  -- t = 2 * cross(q.xyz, v); v' = v + w*t + cross(q.xyz, t)
  local tx = 2*(qy*vz - qz*vy)
  local ty = 2*(qz*vx - qx*vz)
  local tz = 2*(qx*vy - qy*vx)
  return
    vx + qw*tx + qy*tz - qz*ty,
    vy + qw*ty + qz*tx - qx*tz,
    vz + qw*tz + qx*ty - qy*tx
end
