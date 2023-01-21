 
ardour {
  ["type"]    = "dsp",
  name        = "Morph Locator (ver2)",
  category    = "Utility",
  license     = "MIT",
  author      = "RR",
  description = [[generalized Morph for controlling multiple automation lanes.  This processor must be placed immediately before a plugin which is to be controlled.]]
}

local sample_rate = 0
local n_out = 0
local samples_per_draw = -1 -- how many samples need to elapse between draw calls
local samples_since_last_draw = -1 -- how many samples have elapsed since last draw

local last_id = -1
local valid = 0
local last_valid = -1

function dsp_ioconfig()
  return {
    {audio_in = -1, audio_out = -1, midi_in = 1, midi_out = 1},
  }
end

function dsp_init(rate)
  sample_rate = rate
  
  -- shared memory will hold whether or not the next
  -- plugin exists
  self:shmem():allocate(1)
  self:shmem():clear()
  
  -- rate is samples/sec
  -- we want about 25 fps, so we draw once every rate/25 samples
  samples_per_draw = rate/25
  samples_since_last_draw = samples_per_draw -- initialize this so that we draw immediately
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
local printing_params_found = 0

function check_is_flashing_or_printing(proc, n_samples)
  if isflashing then
    seconds_flashing = seconds_flashing + n_samples/sample_rate
    local Ts = seconds_flashing / T_FLASH
    local remainder = Ts - math.floor(Ts)
    if remainder <= 0.5 then
      ARDOUR.LuaAPI.set_processor_param(proc, 1, 1)
    elseif remainder > 0.5 then
      ARDOUR.LuaAPI.set_processor_param(proc, 1, 0)
    end
    if seconds_flashing >= MAX_FLASHES*T_FLASH and not isprinting then
      ARDOUR.LuaAPI.set_processor_param(proc, 1, 0)
      isflashing = false
      seconds_flashing = 0
    end
  end
  
  if isprinting then
    -- print_parameters() will set isprinting = false when finished.
--     print_parameters(printing_proc, printing_current_param, printing_current_param + n_samples/4)
    print_parameters(printing_proc, printing_current_param, printing_current_param + 1)
  end
end

function check_next_proc(proc)
  local shmem = self:shmem () -- get the shared memory region
  local state = shmem:to_float (0):array () -- "cast" into lua-table
  
  valid = 1
  if proc:isnil() then
    valid = 0
  end
  state[1] = valid
end

-- print_parameters is softened so that it only prints
-- from start_param to end_param in a single pass.
-- This helps it to distribute large print jobs over
-- multiple buffers.
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
    printing_params_found = 0
  end
  
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
        print("     ", printing_params_found, " ", label, "| min =", pd.lower, ", max =", pd.upper, ", log =", pd.logarithmic)
      else
        print("       ", " ", label, "| min =", pd.lower, ", max =", pd.upper, ", log =", pd.logarithmic)
      end
      printing_params_found = printing_params_found + 1
    end
  end
  printing_current_param = end_param + 1
end



-- https://github.com/Ardour/ardour/blob/master/share/scripts/_rawmidi.lua
function dsp_runmap (bufs, in_map, out_map, n_samples, offset)
  ARDOUR.DSP.process_map (bufs, n_out, in_map, out_map, n_samples, offset)
  
  local ctrl = CtrlPorts:array()
  
  -- morph locator only needs to look at its own route
  local r = self:route()
  local i = 0 -- keep track of plugin index on this route
    
  -- iterate through all plugins on this route
  while true do
    local proc = r:nth_plugin(i)
    if proc:isnil() then break end
    local plug = proc:to_insert():plugin(0)
    local id = plug:id():to_s()
    
    if id == self:id():to_s() then        
      -- this triggers when "Press to Describe" is pressed
      if ctrl[2] > 0.5 and not isflashing and not isprinting then
        local routename = r:name()
        print()
        print(string.format("Hi!  I am a Morph Debug, plugin %d on %s, with ID=%d", i+1, routename, ctrl[1]))
        isflashing = true
        isprinting = true
        printing_proc = r:nth_plugin(i+1)
        printing_current_param = 0
      end
      
      check_is_flashing_or_printing(proc, n_samples) -- proc is self here
      check_next_proc(r:nth_plugin(i+1))
      
    end
    i = i + 1
  end
  
  samples_since_last_draw = samples_since_last_draw + n_samples
  if samples_since_last_draw > samples_per_draw then
    samples_since_last_draw = samples_since_last_draw % samples_per_draw
    if not (last_id == ctrl[1]) or not (last_valid == valid) then
      self:queue_draw()
    end
    last_id = ctrl[1]
    last_valid = valid
  end
end



function hsv_to_rgb(h) 
  -- https://cs.stackexchange.com/questions/64549/convert-hsv-to-rgb-colors
  local v = 1
  local s = 1
  local c = v * s
  local hp = h / 60
  local x = c*(1 - math.abs((hp % 2) - 1))
  
  if hp >= 0 and hp < 1 then r, g, b = c, x, 0 end
  if hp >= 1 and hp < 2 then r, g, b = x, c, 0 end
  if hp >= 2 and hp < 3 then r, g, b = 0, c, x end
  if hp >= 3 and hp < 4 then r, g, b = 0, x, c end
  if hp >= 4 and hp < 5 then r, g, b = x, 0, c end
  if hp >= 5 and hp < 6 then r, g, b = c, 0, x end
  
  local m = v - c
  return r + m, g+m, b+m
end


local txt = nil -- cache font description (in GUI context)

function render_inline(ctx, w, max_h)
  local ctrl = CtrlPorts:array() -- control port array
  local shmem = self:shmem() -- shared memory region
  local state = shmem:to_float(0):array() -- cast to lua-table
  
  -- prepare text rendering
  if not txt then
    -- allocate PangoLayout and set font
    --http://manual.ardour.org/lua-scripting/class_reference/#Cairo:PangoLayout
    txt = Cairo.PangoLayout (ctx, "Mono 16px")
  end  
  
  local h = w/2
  
  -- clear background
  r, g, b = 0.1, 0.1, 0.1
  ctx:rectangle(0, 0, w, h)
  ctx:set_source_rgba(r, g, b, 1.0)
  ctx:fill()
  
  if state[1] > 0.5 then
    r, g, b = hsv_to_rgb(ctrl[1]/128 * 360)
  else
    r, g, b = 0, 0, 0
  end
  ctx:rectangle(0, 0, 0.25*w, h)
  ctx:set_source_rgba(r, g, b, 1.0)
  ctx:fill()
  
  txt:set_text(string.format("%d", ctrl[1]));
  local tw, th = txt:get_pixel_size()
  ctx:set_source_rgba(1, 1, 1, 1.0)
  ctx:move_to(5*w/8 - tw/2, h/2 - th/2)
  txt:show_in_cairo_context(ctx)
  
  return {w, h}
end
