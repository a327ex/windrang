--[[
  emoji/ui/ — the UI toolkit. snkrx-template's architecture (opts-table
  widgets, uniform ui_ret returns, the ui_interact machine, per-id juice,
  caller-owned state) wearing the emoji chrome (two-layer panel/content
  model, outline-pass borders, white text, natural emoji icons). See
  paint.lua for the chrome physics and the dormant effect-spec hook.

  HOST CONTRACT:
    • emoji_layers{} must declare, in order: 'overlay' (plain),
      'ui_panel' + 'ui_content' + 'ui_top_panel' + 'ui_top_content'
      (all outline = true, no shadow).
    • update(): call ui_begin(dt) once BEFORE any widget call, then make
      widget calls from update (mouse edge events are update-only).
    • draw(): nothing extra — emoji_render() composites the UI layers.
      (No ui_render here, unlike snkrx: the pipeline owns compositing.)
]]

require('emoji.ui.rect')
require('emoji.ui.state')
require('emoji.ui.juice')
require('emoji.ui.paint')
require('emoji.ui.core')
require('emoji.ui.primitives')
require('emoji.ui.widgets')
require('emoji.ui.gallery')

ui_typed_text = ''

-- Once per frame, before any widget call: drain SDL's text-input queue
-- (it fills up and warns forever if undrained — capture for future
-- text_input widgets), reset frame-local interaction state, tick juice,
-- and reset the UI layers' effect state to passthrough (defensive baseline
-- — snkrx's idiom; the paint brackets restore passthrough themselves, this
-- guards against any stray effect_set leaking across frames).
function ui_begin(dt)
  ui_typed_text = engine_get_typed_text()
  ui_state_begin_frame()
  ui_juice_update(dt)
  if ui_panel_layer then
    effect_clear(ui_panel_layer)
    effect_clear(ui_content_layer)
    effect_clear(ui_top_panel_layer)
    effect_clear(ui_top_content_layer)
  end
end
