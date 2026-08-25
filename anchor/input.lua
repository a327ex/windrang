--[[
  input — thin wrapper layer over the engine's built-in action binding system.

  The C engine provides input_bind/is_down/is_pressed/is_released/etc.
  This module provides function wrappers that forward to those. Function
  wrappers (instead of direct aliases) are used so that the engine C
  functions are resolved at *call* time, not at module *load* time.
  (The engine registers its functions during engine_init(), which runs
  AFTER this module is loaded.)

  Usage:
    bind('left', 'key:a')
    bind('left', 'key:left')
    bind('shoot', 'mouse:1')

    if input_down('left') then ... end
    if input_pressed('shoot') then ... end

  Bind string format (parsed by the engine):
    'key:<name>'    -- keyboard key (e.g., 'key:a', 'key:space', 'key:left')
    'mouse:<num>'   -- mouse button (e.g., 'mouse:1' for left, 'mouse:2' for right)
]]

-- Registration
function bind(action, control) input_bind(action, control) end
function unbind(action, control) input_unbind(action, control) end
function unbind_all(action) input_unbind_all(action) end
function bind_chord(name, actions) input_bind_chord(name, actions) end
function bind_sequence(name, sequence) input_bind_sequence(name, sequence) end
function bind_hold(name, duration, source) input_bind_hold(name, duration, source) end

-- Queries
function input_down(action) return is_down(action) end
function input_pressed(action) return is_pressed(action) end
function input_released(action) return is_released(action) end

-- Composite queries
function input_axis(neg, pos) return input_get_axis(neg, pos) end
function input_vector(left, right, up, down) return input_get_vector(left, right, up, down) end
function input_hold_duration(name) return input_get_hold_duration(name) end
function input_last_type() return input_get_last_type() end
function input_pressed_action() return input_get_pressed_action() end

-- Capture (for a "press a key to rebind" UI flow)
function input_capture_start() input_start_capture() end
function input_capture_get() return input_get_captured() end
function input_capture_stop() input_stop_capture() end

-- Deadzone for gamepad axes
function input_deadzone(d) input_set_deadzone(d) end
