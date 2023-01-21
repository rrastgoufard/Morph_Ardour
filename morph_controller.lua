ardour {
  ["type"]    = "dsp",
  name        = "Morph Controller (ver2)",
  category    = "Utility",
  license     = "MIT",
  author      = "RR",
  description = [[generalized Morph for controlling multiple automation lanes.  This processor contains multiple lanes and needs to be coupled with the Session Script morph_lane_linker.lua as well as Morph Locator plugins.]]
}

MAX_TARGETS = 8
PARAMS_PER_TARGET = 14
PID_PARAM = 12
LFO_PARAM_START = MAX_TARGETS*PARAMS_PER_TARGET + 1

local sample_rate = 0
local targets = {}
local locators = {}
local self_proc = -1

function dsp_ioconfig()
  return {
    {audio_in = -1, audio_out = -1, midi_in = 1, midi_out = 1},
  }
end


function dsp_init(rate)
  sample_rate = rate
end

function dsp_configure(ins, outs)
  assert (ins:n_audio() == outs:n_audio())
  n_out = outs
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
  table.insert(output,  { ["type"] = "input", name = "freq (Hz)", min = 0.001, max = 10, default = 0.1, logarithmic = true })
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

function add_target(locator_id, proc, nextproc)
  local ctrl = CtrlPorts:array()
  for i = 0, MAX_TARGETS - 1 do
    local id = ctrl[i*PARAMS_PER_TARGET + PID_PARAM + 1]
    if math.floor(id) == math.floor(locator_id) then
      locators[i] = proc
      if nextproc:isnil() then 
        targets[i] = nil
      else
        targets[i] = nextproc
      end
    end
  end
end

function find_targets()
  targets = {} -- reset all targets
  locators = {} -- reset all locators
  
  for r in Session:get_routes():iter() do
    local i = 0 -- keep track of plugin index on this route
    while true do
      local proc = r:nth_plugin(i)
      if proc:isnil() then break end -- go to next route
      local plug = proc:to_insert():plugin(0)
      local label = plug:label()
      if label == "Morph Locator (ver2)" then
        local nextproc = r:nth_plugin(i+1)
        local locator_id = ARDOUR.LuaAPI.get_processor_param(proc, 0)
        add_target(locator_id, proc, nextproc)
      end
      if plug:id():to_s() == self:id():to_s() then
        self_proc = proc
      end
      i = i + 1
    end
  end
end

function get_interp(value, start, pd)
  local ctrl = CtrlPorts:array()
  count = math.floor(ctrl[start])
  scaled = value * (count - 1)
  lower_idx = math.floor(scaled)
  upper_idx = lower_idx + 1
  lower_value = ctrl[start+lower_idx+1]
  upper_value = ctrl[start+upper_idx+1]
  
  -- ensure the two values are in range
  lower_value = math.min(math.max(lower_value, pd.lower), pd.upper)
  upper_value = math.min(math.max(upper_value, pd.lower), pd.upper)
  
  percentage = scaled - lower_idx
  
  if pd.logarithmic then
    lower_value = math.log(lower_value) / math.log(10)
    upper_value = math.log(upper_value) / math.log(10)
  end
  interped = (1-percentage)*lower_value + percentage*upper_value
  if pd.logarithmic then
    interped = 10^interped
  end
  
  return interped
end

function do_the_morph(verbose)
  local ctrl = CtrlPorts:array()
  value = ctrl[1]
  for t=0,MAX_TARGETS-1 do    
    local start = t*PARAMS_PER_TARGET + 1 + 1
    local plugin_id = math.floor(ctrl[start+11])
    local nth_param = math.floor(ctrl[start+12])
    local enabled = ctrl[start+13] > 0.5
    local target = targets[t]
    local locator = locators[t]
    if verbose then
      if target then
        print(t, plugin_id, target, "resolved to", target:to_insert():plugin(0):label())
      else
        print(t, plugin_id, nth_param, target, locator)
      end
    end
    if enabled then
      if target and nth_param >= 0 then
        -- this silently fails if nth_param is not a valid input parameter for the target processor
        _, _, pd = ARDOUR.LuaAPI.plugin_automation(target, nth_param)
        interped = get_interp(value, start, pd)
        if locator and locator:to_insert():enabled() then
          ARDOUR.LuaAPI.set_processor_param(target, nth_param, interped)
        end
      end
    end
  end
end

local t0 = 0
local v0 = 0.5
local a0 = 0
function do_the_lfo(n_samples, verbose)
  local ctrl = CtrlPorts:array()
  local dt = n_samples / sample_rate
  
  local proc_shape = ctrl[LFO_PARAM_START + 1 + 0]
  local proc_freq = ctrl[LFO_PARAM_START + 1 + 1]
  local proc_beat = ctrl[LFO_PARAM_START + 1 + 2]
  local proc_speedmode = ctrl[LFO_PARAM_START + 1 + 3] > 0.5
  local proc_phase = ctrl[LFO_PARAM_START + 1 + 4]
  local proc_reset = ctrl[LFO_PARAM_START + 1 + 5] > 0.5
  local use_lfo = ctrl[LFO_PARAM_START + 1 + 6] > 0.5
  
  local f1 = proc_freq
  if proc_speedmode then -- if true, then we're in tempo sync
    local tnow = Temporal.timepos_t(Session:transport_sample())
    local tm = Temporal.TempoMap.read()
    local bpm = tm:quarters_per_minute_at(tnow)
    f1 = bpm / 60 * proc_beat
  end
  
  local t1 = t0 + dt
  local theta = 0 -- theta is unused unless sine is selected
  
  if proc_reset then
    dt = 0
    t1 = 0
  end
  
  if proc_shape == 0 then -- sine
    if proc_reset then
      phase = proc_phase / 180 * math.pi
    else
      -- the old angle @ f0,t0 should be the same as the new angle @ f1,t0
      -- 2*pi*f0*t0 = a0 = 2*pi*f1*t0 + phase
      phase = a0 - 2*math.pi*f1*t0
    end
    theta = 2*math.pi*f1*t1 + phase
    v1 = 0.5*math.sin(theta) + 0.5 -- value in [0,1]
  end
  if proc_shape == 1 then -- saw
    if proc_reset then
      phase = proc_phase / 360
    else
      phase = v0
    end
    v1 = phase + dt * f1
    if v1 > 1 then
      v1 = v1 - 1
    end
  end
  
  -- roll back time in order to not overflow
  period = 1/f1
  if t1 > 10*period then
    t1 = t1 - 10*period
  end   
  
  t0 = t1
  v0 = v1
  a0 = theta
  
  if verbose then
    print(t0, v0, a0)
  end
  
  if use_lfo then
    ARDOUR.LuaAPI.set_processor_param(self_proc, 0, v1)
  end
  
end

-- https://github.com/Ardour/ardour/blob/master/share/scripts/_rawmidi.lua
function dsp_runmap (bufs, in_map, out_map, n_samples, offset)
  ARDOUR.DSP.process_map (bufs, n_out, in_map, out_map, n_samples, offset)
  
  if not Session:transport_rolling() then
    find_targets()
  end
  do_the_lfo(n_samples, false)
  do_the_morph(false)
end
