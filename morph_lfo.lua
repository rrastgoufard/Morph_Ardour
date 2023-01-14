ardour {
  ["type"]    = "dsp",
  name        = "Morph LFO",
  category    = "Utility",
  license     = "MIT",
  author      = "RR",
  description = [[Morph LFO for controlling an external automation lane.  Uses morph_locator to target a specific external plugin and morph_lane_linker for connection.  Set reset=1 to lock the timer at initialization and move to reset=0 to start running.]]
}

MAX_TARGETS = 8

function dsp_ioconfig()
  return {
    {audio_in = -1, audio_out = -1},
  }
end

function dsp_params()
  local output = {
    { ["type"] = "input", name = "shape", min = 0, max = 1, default = 0, enum = true, scalepoints = { ["sine"] = 0, ["saw"] = 1} },
    { ["type"] = "input", name = "freq (Hz)", min = 0.001, max = 10, default = 1, logarithmic = true },
    { ["type"] = "input", name = "phase (deg)", min = 0, max = 360, default = 0 },
    { ["type"] = "input", name = "reset", min = 0, max = 1, default = 0, integer = true },
    { ["type"] = "input", name = "locator ID", min = -1, max = 128, default = -1, integer = true },
    { ["type"] = "input", name = "nth param", min = -1, max = 4096, default = -1, integer = true },
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
end

function dsp_run(ins, outs, n_samples)
  -- process all channels
  for c = 1, #ins do
    -- when not processing in-place, copy the data from input to output first
    if ins[c] ~= outs[c] then
      ARDOUR.DSP.copy_vector (outs[c], ins[c], n_samples)
    end
  end
end
