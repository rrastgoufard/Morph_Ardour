ardour {
  ["type"]    = "dsp",
  name        = "Morph Controller",
  category    = "Utility",
  license     = "MIT",
  author      = "RR",
  description = [[generalized Morph for controlling multiple automation lanes.  This processor contains multiple lanes and needs to be coupled with the Session Script morph_lane_linker.lua as well as Morph Locator plugins.]]
}

MAX_TARGETS = 8

function dsp_ioconfig()
  return {
    {audio_in = -1, audio_out = -1, midi_in = 1, midi_out = 1},
  }
end

function dsp_params()
  local output = {
    { ["type"] = "input", name = "con", min = 0, max = 1, default = 0 },
  }
  
  for i=0, MAX_TARGETS-1 do
    table.insert(output, { ["type"] = "input", name = "t" .. i .. "_ct", min = 2, max = 10, default = 2, integer = true })  -- how many points to use for control.  0 means disabled
    table.insert(output, { ["type"] = "input", name = "t" .. i .. "_0", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "t" .. i .. "_1", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "t" .. i .. "_2", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "t" .. i .. "_3", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "t" .. i .. "_4", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "t" .. i .. "_5", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "t" .. i .. "_6", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "t" .. i .. "_7", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "t" .. i .. "_8", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "t" .. i .. "_9", min = -99999, max = 99999, default = 0 })
    table.insert(output, { ["type"] = "input", name = "t" .. i .. "pid", min = -1, max = 128, default = -1, integer = true })
    table.insert(output, { ["type"] = "input", name = "t" .. i .. "nth", min = -1, max = 4096, default = -1, integer = true })
    table.insert(output, { ["type"] = "input", name = "t" .. i .. "ena", min = 0, max = 1, default = 1, integer = true })
  end
  
  table.insert(output,  { ["type"] = "input", name = "shape", min = 0, max = 1, default = 0, enum = true, scalepoints = { ["sine"] = 0, ["saw"] = 1} })
  table.insert(output,  { ["type"] = "input", name = "freq (Hz)", min = 0.001, max = 10, default = 1, logarithmic = true })
  table.insert(output,  { ["type"] = "input", name = "beat div", min = 0, max = 10, default = 1, enum = true, scalepoints = { 
    ["1/1"] = 0.25,
    ["1/2"] = 0.5,
    ["1/4"] = 1,
    ["1/4T"] = 1.5,
    ["1/8"] = 2,
    ["1/8T"] = 3,
    ["1/16"] = 4,
    ["1/16T"] = 6,
  }})
  table.insert(output,  { ["type"] = "input", name = "speed mode", min = 0, max = 1, default = 0, enum = true, scalepoints = { ["freq (Hz)"] = 0, ["beat div"] = 1} })
  table.insert(output,  { ["type"] = "input", name = "phase (deg)", min = 0, max = 360, default = 0 })
  table.insert(output,  { ["type"] = "input", name = "reset", min = 0, max = 1, default = 0, integer = true })
  table.insert(output,  { ["type"] = "input", name = "USE LFO?", min = 0, max = 1, default = 0, integer = true })
  
  
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
