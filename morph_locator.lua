 
ardour {
  ["type"]    = "dsp",
  name        = "Morph Locator",
  category    = "Utility",
  license     = "MIT",
  author      = "RR",
  description = [[generalized Morph for controlling multiple automation lanes.  This processor must be placed immediately before a plugin which is to be controlled.]]
}

function dsp_ioconfig()
  return {
    {audio_in = -1, audio_out = -1},
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
