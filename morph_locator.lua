 
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

local valid = 0

local proc_id = ""
local proc_params = {}
local proc_display_string = ""

function dsp_ioconfig()
  return {
    {audio_in = -1, audio_out = -1, midi_in = 0, midi_out = 0},
    {audio_in = -1, audio_out = -1, midi_in = 1, midi_out = 1},
  }
end

function dsp_init(rate)
  sample_rate = rate
  
  -- shared memory will hold whether or not the next
  -- plugin exists
  -- as well as 32 bytes for some string data
  self:shmem():allocate(1+32)
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

  }
  
  return output
end

-- don't check the full range of parameters... this bogs down the dsp processor severely
-- simply scan through say 10 params per buffer
local check_param_start = 0
local check_param_stride = 10
local ctrl_count = 0
local param_label = ""
function check_param_diff(proc)
  local plug = proc:to_insert():plugin(0)
  for check_param = check_param_start, check_param_start + check_param_stride - 1 do
    local j = check_param
    local N = plug:parameter_count()
    if j >= N then
      check_param_start = 0
      ctrl_count = 0
      return
    end
    if plug:parameter_is_control(j) then
      ctrl_count = ctrl_count + 1
      if plug:parameter_is_input(j) then
        local nowvalue = ARDOUR.LuaAPI.get_processor_param(proc, ctrl_count-1) -- get_processor_param starts at 0
        local prev = proc_params[ctrl_count]
        if not (nowvalue == prev) then
          if prev then
            param_label = plug:parameter_label(j)
            proc_display_string = string.format("%d %s", ctrl_count-1, param_label) -- ctrl_count-1 because again get/set_processor_param starts at 0
          else
            param_label = "#total"
            proc_display_string = string.format("%d %s", ctrl_count, param_label) -- here we report the total count, not the ardour-indexed count, so remove the -1
          end
        end
        proc_params[ctrl_count] = nowvalue
      end
    end
  end
  check_param_start = check_param_start + check_param_stride
end

-- helper functions for writing strings to shared memory
-- and then reading them back.
-- We assume exactly 1 string is available per target and that it can have a maximum length of 32 characters

function write_string_to_memory(s)
  local memint = self:shmem():to_int(0):array()
  local start = 1
  local s32 = string.format("%32s", s)
  for i=1,32 do
    memint[start+i] = string.byte(s32,i)
  end
end

function read_string_from_memory()
  local memint = self:shmem():to_int(0):array()
  local start = 1
  local s = ""
  for i = 1,32 do
    s = s .. string.char(memint[start+i])
  end
  return s:match("^%s*(.-)%s*$") -- trim any spaces at beginning or end
end

function reset_proc()
  proc_id = ""
  proc_params = {}
  check_param_start = 0
  check_param_stride = 10
  ctrl_count = 0
  param_label = ""
end

function check_next_proc(proc)
  local shmem = self:shmem () -- get the shared memory region
  local state = shmem:to_float (0):array () -- "cast" into lua-table
  
  valid = 1
  if proc:isnil() then
    valid = 0
    reset_proc()
  else
    local plug = proc:to_insert():plugin(0)
    local id = plug:id():to_s()
    if id == proc_id then
      check_param_diff(proc)
    else
      reset_proc()
      proc_id = id
    end
  end
  state[1] = valid
  write_string_to_memory(proc_display_string)
  collectgarbage()
end


function check_self()  
  
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
      check_next_proc(r:nth_plugin(i+1))
    end
    i = i + 1
  end
end



local self_id = nil
local wait_cycles = 999999
local cycles_waited = 0
local finished_waiting = false
local max_wait_seconds = 3
function randomly_wait_a_bit_at_startup(n_samples, verbose)
  if finished_waiting then
    return false
  end
  local wait_more = false
  if not self_id then
  
    -- hopefully this will stagger the startups of these processors
    -- so that Ardour isn't bogged down and overwhelmed when opening the project
    self_id = tonumber(self:id():to_s())
    local max_wait_cycles = sample_rate / n_samples * max_wait_seconds
    local waiting_percent = math.random(1, 100) / 100
    wait_cycles = waiting_percent * max_wait_cycles
    if verbose then
      print(string.format(
        "Hi!  I am %s with id=%s.  Waiting %.0f cycles (%.2f sec) to start up.", 
        self:name(), 
        self_id, 
        wait_cycles, 
        waiting_percent*max_wait_seconds
      ))
    end
  end
  if cycles_waited < wait_cycles then
    cycles_waited = cycles_waited + 1
    wait_more = true
  else
    finished_waiting = true
    if verbose then
      print(self_id, "is done waiting!")
    end
  end
  return wait_more
end



-- https://github.com/Ardour/ardour/blob/master/share/scripts/_rawmidi.lua
function dsp_runmap (bufs, in_map, out_map, n_samples, offset)
  ARDOUR.DSP.process_map (bufs, n_out, in_map, out_map, n_samples, offset)
  
  if randomly_wait_a_bit_at_startup(n_samples, verbose) then
    return
  end
  
  check_self()
  
  samples_since_last_draw = samples_since_last_draw + n_samples
  if samples_since_last_draw > samples_per_draw then
    samples_since_last_draw = samples_since_last_draw % samples_per_draw
    self:queue_draw()
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


local txt_large = nil -- cache font description (in GUI context)
local txt_small = nil

function render_inline(ctx, w, max_h)
  local ctrl = CtrlPorts:array() -- control port array
  local shmem = self:shmem() -- shared memory region
  local state = shmem:to_float(0):array() -- cast to lua-table
  local display_string = read_string_from_memory()
  
  -- prepare text rendering
  if not txt_large then
    -- allocate PangoLayout and set font
    --http://manual.ardour.org/lua-scripting/class_reference/#Cairo:PangoLayout
    txt_large = Cairo.PangoLayout (ctx, "Mono 16px")
    txt_small = Cairo.PangoLayout (ctx, "Mono 10px")
  end  
  
  txt_large:set_text(string.format("%d", ctrl[1]));
  local twl, thl = txt_large:get_pixel_size()
  
  txt_small:set_text(string.format("%s", display_string));
  local tws, ths = txt_small:get_pixel_size()
  

  local h = thl + ths
  
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
  
  ctx:set_source_rgba(1, 1, 1, 1.0)
  ctx:move_to(w/4 + 2, 0)
  txt_large:show_in_cairo_context(ctx)
  
  ctx:move_to(w/4 + 2, thl)
  txt_small:show_in_cairo_context(ctx)
  
  return {w, h}
end
