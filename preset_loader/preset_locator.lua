 
ardour {
  ["type"]    = "dsp",
  name        = "Preset Locator",
  category    = "Utility",
  license     = "MIT",
  author      = "RR",
  description = [[Preset Locator.  Place on track immediately before the target plugin and automate its single parameter to change presets.  Requires preset_loader.lua session script running.]]
}

function dsp_ioconfig()
  return {
    {audio_in = -1, audio_out = -1, midi_in = 0, midi_out = 0},
    {audio_in = -1, audio_out = -1, midi_in = 1, midi_out = 1},
  }
end

function dsp_params()
  local output = {
    { ["type"] = "input", name = "locator_ID", min = 0, max = 128, default = 0, integer = true },
  }
  
  return output
end

local sample_rate = 0

function dsp_init(rate)
  sample_rate = rate
end

function dsp_configure(ins, outs)
  assert (ins:n_audio() == outs:n_audio())
  collectgarbage()
  
  n_out = outs
end

-- https://github.com/Ardour/ardour/blob/master/share/scripts/_rawmidi.lua
function dsp_runmap (bufs, in_map, out_map, n_samples, offset)
  ARDOUR.DSP.process_map (bufs, n_out, in_map, out_map, n_samples, offset)
end
