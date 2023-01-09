ardour {
  ["type"]    = "dsp",
  name        = "Morph Processor",
  category    = "Utility",
  license     = "MIT",
  author      = "RR",
  description = [[generalized Morph for controlling multiple automation lanes.  This processor contains multiple lanes and needs to be coupled with the Session Script morph_lane_linker.lua as well as Morph Locator plugins.]]
}

MAX_TARGETS = 8

function dsp_ioconfig()
  return {
    {audio_in = -1, audio_out = -1},
  }
end

function dsp_params()
  local output = {
    { ["type"] = "input", name = "controller", min = 0, max = 1, default = 0 },
  }
  
  for i=0, MAX_TARGETS-1 do
    table.insert(output, { ["type"] = "input", name = "target" .. i .. "_control_point_count", min = 2, max = 10, default = 2, integer = true })  -- how many points to use for control.  0 means disabled
    table.insert(output, { ["type"] = "input", name = "target" .. i .. "_control0", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "target" .. i .. "_control1", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "target" .. i .. "_control2", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "target" .. i .. "_control3", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "target" .. i .. "_control4", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "target" .. i .. "_control5", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "target" .. i .. "_control6", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "target" .. i .. "_control7", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "target" .. i .. "_control8", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "target" .. i .. "_control9", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "__target" .. i .. "_plugin_id", min = -1, max = 128, default = -1, integer = true })
    table.insert(output, { ["type"] = "input", name = "__target" .. i .. "_nth_param", min = -1, max = 4096, default = -1, integer = true })
    table.insert(output, { ["type"] = "input", name = "__target" .. i .. "_enabled", min = 0, max = 1, default = 1, integer = true })
  end
  
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

end
