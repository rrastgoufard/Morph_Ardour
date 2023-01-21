 
ardour {
  ["type"]    = "dsp",
  name        = "Morph Debug",
  category    = "Utility",
  license     = "MIT",
  author      = "RR",
  description = [[Morph Debug.  Tries various things, prints out various messages.]]
}

local sample_rate = 0
local n_out = 0

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
  
    -- these start at 0 for set/get_processor_param
    -- but they start at 1 for ctrl
  
    { ["type"] = "input", name = "locator_ID", min = 0, max = 127, default = 0, integer = true },
    { ["type"] = "input", name = "value", min = 0, max = 1, default = 0 },
    { ["type"] = "output", name = "value_out", min = 0, max = 1, default = 0 },
    { ["type"] = "output", name = "debug_count", min = 0, max = 9999, default = 0, integer = true },
    { ["type"] = "output", name = "route_count", min = 0, max = 9999, default = 0, integer = true },
    { ["type"] = "input", name = "Press to Describe", min = 0, max = 1, default = 0, toggled = true },
  }
  
  return output
end


-- the following code will flash a button several times when pressed.
-- while it is flashing, manual button presses need to be ignored.
local isflashing = false
local seconds_flashing = 0
local T_FLASH = 0.25
local MAX_FLASHES = 3

local isprinting = false
local printing_proc = nil
local printing_current_param = 0

function check_is_flashing_or_printing(proc, n_samples)
  if isflashing then
    seconds_flashing = seconds_flashing + n_samples/sample_rate
    local Ts = seconds_flashing / T_FLASH
    local remainder = Ts - math.floor(Ts)
    if remainder <= 0.5 then
      ARDOUR.LuaAPI.set_processor_param(proc, 5, 1)
    elseif remainder > 0.5 then
      ARDOUR.LuaAPI.set_processor_param(proc, 5, 0)
    end
    if seconds_flashing >= MAX_FLASHES*T_FLASH and not isprinting then
      ARDOUR.LuaAPI.set_processor_param(proc, 5, 0)
      isflashing = false
      seconds_flashing = 0
    end
  end
  
  if isprinting then
    -- print_parameters() will set isprinting = false when finished.
    print_parameters(printing_proc, printing_current_param, printing_current_param + n_samples)
  end
end

function print_parameters(proc, start_param, end_param)
  if proc:isnil() then
    print("Cannot print processor parameters because it is nil")
    isprinting = false
    return
  end
  plug = proc:to_insert():plugin(0)
  name = plug:label()
  if start_param == 0 then 
    print(name)
  end
  
  param_count = start_param
  for j = start_param, end_param do
    if j > plug:parameter_count() - 1 then 
      isprinting = false
      return
    end
    
    if plug:parameter_is_control(j) then
      local label = plug:parameter_label(j)
      local _, descriptor_table = plug:get_parameter_descriptor(j, ARDOUR.ParameterDescriptor())
      local pd = descriptor_table[2]
      if plug:parameter_is_input(j) then
        print("     ", param_count, " ", label, "| min =", pd.lower, ", max =", pd.upper, ", log =", pd.logarithmic)
      else
        print("       ", " ", label, "| min =", pd.lower, ", max =", pd.upper, ", log =", pd.logarithmic)
      end
      param_count = param_count + 1
    end
  end
  printing_current_param = param_count
end






stepcount = 0
maxcount = 10000

-- https://github.com/Ardour/ardour/blob/master/share/scripts/_rawmidi.lua
function dsp_runmap (bufs, in_map, out_map, n_samples, offset)
  ARDOUR.DSP.process_map (bufs, n_out, in_map, out_map, n_samples, offset)
  
  stepcount = stepcount + 1
  if stepcount > maxcount then
    stepcount = 0
  end
  
  local ctrl = CtrlPorts:array()
  ctrl[3] = ctrl[2]
  
  local routecount = 0
  local debugcount = 0
  
  for r in Session:get_routes():iter() do
    routecount = routecount + 1
    local routename = r:name()
    local i = 0 -- keep track of plugin index on this route
      
    -- iterate through all plugins on this route
    while true do
      local proc = r:nth_plugin(i)
      if proc:isnil() then break end
      local pi = proc:to_insert()
      local pp = pi:plugin(0)
      local name = pi:type() .. "-" .. pp:unique_id() .. " named: " .. pp:label()
      local id = pp:id():to_s()
      
      if pp:label() == "Morph Debug" then
        debugcount = debugcount + 1
      end
      if id == self:id():to_s() then
        ARDOUR.LuaAPI.set_processor_param(proc, 1, stepcount/maxcount)
        
        -- this triggers when "Press to Describe" is pressed
        if ctrl[6] > 0.5 and not isflashing and not isprinting then
          print()
          print(string.format("Hi!  I am a Morph Debug, plugin %d on %s, with ID=%d", i+1, routename, ctrl[1]))
          isflashing = true
          isprinting = true
          printing_proc = r:nth_plugin(i+1)
          printing_current_param = 0
        end
        
        check_is_flashing_or_printing(proc, n_samples) -- proc is self here
        
      end
      i = i + 1
    end
    
  end
  
  ctrl[4] = debugcount
  ctrl[5] = routecount
  
  
end
