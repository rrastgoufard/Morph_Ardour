ardour {
  ["type"]    = "dsp",
  name        = "Morph Processor",
  category    = "Utility",
  license     = "MIT",
  author      = "RR",
  description = [[generalized Morph for controlling multiple automation lanes.  This processor contains multiple lanes and needs to be coupled with the Session Script morph_lane_linker.lua]]
}

function dsp_ioconfig()
  return {
    {audio_in = -1, audio_out = -1},
  }
end

function dsp_params()
  return {
    { ["type"] = "input", name = "p0", min = 0, max = 1, default = 0 },
    { ["type"] = "input", name = "p1", min = 0, max = 1, default = 0 },
    { ["type"] = "input", name = "p2", min = 0, max = 1, default = 0 },
    { ["type"] = "input", name = "p3", min = 0, max = 1, default = 0 },
    { ["type"] = "input", name = "p4", min = 0, max = 1, default = 0 },
    { ["type"] = "input", name = "p5", min = 0, max = 1, default = 0 },
    { ["type"] = "input", name = "p6", min = 0, max = 1, default = 0 },
    { ["type"] = "input", name = "p7", min = 0, max = 1, default = 0 },
  }
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

end
