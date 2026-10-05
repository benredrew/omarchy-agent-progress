-- Replaces Omarchy's default SUPER+P pseudo-window binding.
hl.unbind("SUPER + P")
hl.bind("SUPER + P", hl.dsp.global("benredrew.progress:toggle"), {
  description = "Toggle work progress picker",
})

-- These default-layer binds are disabled except while the picker is open.
-- Quickshell flips them synchronously through `benredrew_progress_keys`.
local progress_picker_keys = {}
local function set_progress_picker_keys(enabled)
  for _, keybind in ipairs(progress_picker_keys) do
    keybind:set_enabled(enabled)
  end
end
_G.benredrew_progress_keys = set_progress_picker_keys

table.insert(progress_picker_keys, hl.bind("up", hl.dsp.global("benredrew.progress:previous"), {
  description = "Previous progress timer",
  repeating = true,
}))
table.insert(progress_picker_keys, hl.bind("i", hl.dsp.global("benredrew.progress:previous"), {
  description = "Previous progress timer",
  repeating = true,
}))
table.insert(progress_picker_keys, hl.bind("down", hl.dsp.global("benredrew.progress:next"), {
  description = "Next progress timer",
  repeating = true,
}))
table.insert(progress_picker_keys, hl.bind("k", hl.dsp.global("benredrew.progress:next"), {
  description = "Next progress timer",
  repeating = true,
}))
table.insert(progress_picker_keys, hl.bind("escape", hl.dsp.global("benredrew.progress:close"), {
  description = "Close progress picker",
}))
table.insert(progress_picker_keys, hl.bind("return", hl.dsp.global("benredrew.progress:confirm"), {
  description = "Confirm progress timer",
}))
set_progress_picker_keys(false)
