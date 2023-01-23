ardour {
  ["type"]    = "dsp",
  name        = "Morph Controller (ver2)",
  category    = "Utility",
  license     = "MIT",
  author      = "RR",
  description = [[generalized Morph for controlling multiple automation lanes.  This processor contains multiple lanes and needs to be coupled with the Session Script morph_lane_linker.lua as well as Morph Locator plugins.]]
}

MAX_TARGETS = 8
MEMORY_PER_TARGET = 10

CTRL_IDX = {}
PARAM_IDX = {}
PARAM_COUNT = 0

local sample_rate = 0
local targets = {}
local locators = {}
local self_proc = -1

local samples_since_draw = 0
local samples_per_draw = 0

function dsp_ioconfig()
  return {
    {audio_in = -1, audio_out = -1, midi_in = 1, midi_out = 1},
  }
end


function dsp_init(rate)
  sample_rate = rate
  samples_per_draw = math.floor(rate / 25)
  samples_since_draw = samples_per_draw
end

function dsp_configure(ins, outs)
  assert (ins:n_audio() == outs:n_audio())
  n_out = outs
  
  -- keep track of 
  --   1: interpolated value
  --   2: parameter min value
  --   3: parameter max value
  --   4: parameter log
  --   5: is valid?
  --   6: ctrl_idx tnpid
  --   7: ctrl_idx tn_ct
  --   8: ctrl_idx tnlin
  --   9: is enabled?
  --   10: target exists?
  -- all of these are needed because this is the only (?) way to get arrays of data to the graphics render_inline function
  -- it _seems_ that single variables in the global scope can make it across, but not lua tables
  -- Scratch that!  A snapshot of global state is given to render_inline upon gui creation, but the values are not updated.
  -- shmem() and CtrlPorts are the only ways to get live data to render_inline
  
  -- REMEMBER to update MEMORY_PER_TARGET if adding new variables here
  
  self:shmem():allocate(MEMORY_PER_TARGET*MAX_TARGETS)
  self:shmem():clear()
  
  
  
end

function add_param(output, cfg)
  
  -- this line is sufficient for creating the parameters
  table.insert(output, cfg)
  
  -- because parameters might be re-ordered, it is nice to keep track of parameter indices by name for easy access later
  name = cfg["name"]
  PARAM_IDX[name] = PARAM_COUNT
  -- increment index here so that first PARAM_IDX starts at 0 and first CTRL_IDX starts at 1
  PARAM_COUNT = PARAM_COUNT + 1
  CTRL_IDX[name] = PARAM_COUNT
end

function dsp_params()
  local output = {}
  add_param(output, { ["type"] = "input", name = "Controller", min = 0, max = 1, default = 0 } )
  add_param(output, { ["type"] = "input", name = "Visualize", min = -1, max = 7, default = -1, integer = true } )
  
  add_param(output,  { ["type"] = "input", name = "lfo shape", min = 0, max = 1, default = 0, enum = true, scalepoints = { ["sine"] = 0, ["saw"] = 1} })
  add_param(output,  { ["type"] = "input", name = "lfo freq (Hz)", min = 0.001, max = 20, default = 0.1, logarithmic = true })
  add_param(output,  { ["type"] = "input", name = "lfo beat div", min = 0, max = 10, default = 1, enum = true, scalepoints = { 
    ["1/1"] = 0.25,
    ["1/2"] = 0.5,
    ["1/4"] = 1,
    ["1/4T"] = 1.5,
    ["1/8"] = 2,
    ["1/8T"] = 3,
    ["1/16"] = 4,
    ["1/16T"] = 6,
  }})
  add_param(output,  { ["type"] = "input", name = "lfo mode", min = 0, max = 1, default = 0, enum = true, scalepoints = { ["freq (Hz)"] = 0, ["beat div"] = 1} })
  add_param(output,  { ["type"] = "input", name = "lfo phase (deg)", min = 0, max = 360, default = 0 })
  add_param(output,  { ["type"] = "input", name = "lfo reset", min = 0, max = 1, default = 0, integer = true })
  add_param(output,  { ["type"] = "input", name = "Use LFO?", min = 0, max = 1, default = 0, integer = true, toggled = true })
  
  for i=0, MAX_TARGETS-1 do
    add_param(output, { ["type"] = "input", name = "t" .. i .. "_ct", min = 2, max = 10, default = 2, integer = true })  -- how many points to use for control.  0 means disabled
    add_param(output, { ["type"] = "input", name = "t" .. i .. "_0", min = -99999, max = 99999, default = 0 })
    add_param(output, { ["type"] = "input", name = "t" .. i .. "_1", min = -99999, max = 99999, default = 0 })
    add_param(output, { ["type"] = "input", name = "t" .. i .. "_2", min = -99999, max = 99999, default = 0 })
    add_param(output, { ["type"] = "input", name = "t" .. i .. "_3", min = -99999, max = 99999, default = 0 })
    add_param(output, { ["type"] = "input", name = "t" .. i .. "_4", min = -99999, max = 99999, default = 0 })
    add_param(output, { ["type"] = "input", name = "t" .. i .. "_5", min = -99999, max = 99999, default = 0 })
    add_param(output, { ["type"] = "input", name = "t" .. i .. "_6", min = -99999, max = 99999, default = 0 })
    add_param(output, { ["type"] = "input", name = "t" .. i .. "_7", min = -99999, max = 99999, default = 0 })
    add_param(output, { ["type"] = "input", name = "t" .. i .. "_8", min = -99999, max = 99999, default = 0 })
    add_param(output, { ["type"] = "input", name = "t" .. i .. "_9", min = -99999, max = 99999, default = 0 })
    add_param(output, { ["type"] = "input", name = "t" .. i .. "pid", min = -1, max = 127, default = -1, integer = true })
    add_param(output, { ["type"] = "input", name = "t" .. i .. "nth", min = -1, max = 4096, default = -1, integer = true })
    add_param(output, { ["type"] = "input", name = "t" .. i .. "ena", min = 0, max = 1, default = 1, integer = true, toggled = true })
    add_param(output, { ["type"] = "input", name = "t" .. i .. "lin", min = 0, max = 1, default = 1, integer = true, scalepoints = {
      ["linear"] = 1,
      ["discrete"] = 0,
    }})
  end
  
  return output
end


-- the following two functions look through all routes to find Locators.
-- If a Locator is found with an ID that this Controller cares about, then save it and the following processor for later access.

function add_target(locator_id, proc, nextproc)
  local ctrl = CtrlPorts:array()
  for i = 0, MAX_TARGETS - 1 do
    local id = ctrl[CTRL_IDX["t"..i.."pid"]]
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


-- check the nth param of target.  If it is a valid parameter, then return its description.  Otherwise, return nil
function get_check_param(target, nth_param)
  if target:isnil() then return nil end
  plug = target:to_insert():plugin(0)
  if nth_param > plug:parameter_count() - 1 or nth_param < 0 then
    return nil
  end
  _, _, pd = ARDOUR.LuaAPI.plugin_automation(target, nth_param)
  return pd
end


-- Look through all of a target's control points to find the minimum and maximum.
-- This is used for scaling the output displays.
-- (Naively, the parameter range is -99999 to 99999, but using those as axis limits will make a movement of 200 -> 300 invisible)

function get_min_max(t)
  local ctrl = CtrlPorts:array()
  local start = CTRL_IDX["t"..t.."_ct"]
  local count = math.floor(ctrl[start])
  local settings_min = ctrl[start+1]
  local settings_max = ctrl[start+1]
  for i = 1,(count-1) do
    settings_min = math.min(settings_min, ctrl[start+1+i])
    settings_max = math.max(settings_max, ctrl[start+1+i])
  end
  return settings_min, settings_max
end

-- Store values in memory so that render_inline can have access to these things.
-- Many of these are in global scope but are stored in lua tables which don't seem to be globally accessible from render_inline

function store_values_memory(t, value, param_lower, param_upper, logarithmic, valid, target_exists)  
  settings_min, settings_max = get_min_max(t)
  local ctrl = CtrlPorts:array()
  local start = t*MEMORY_PER_TARGET
  local shmem = self:shmem():to_float(0):array()
  shmem[start+1] = value
  shmem[start+2] = math.max(param_lower, settings_min)
  shmem[start+3] = math.min(param_upper, settings_max)
  if logarithmic then
    shmem[start+4] = 1
  else
    shmem[start+4] = 0
  end
  shmem[start+5] = valid
  shmem[start+6] = CTRL_IDX["t"..t.."pid"]
  shmem[start+7] = CTRL_IDX["t"..t.."_ct"]
  shmem[start+8] = CTRL_IDX["t"..t.."lin"]
  
  enabled = ctrl[CTRL_IDX["t"..t.."ena"]] > 0.5
  if enabled then
    shmem[start+9] = 1
  else
    shmem[start+9] = 0
  end
  
  shmem[start+10] = target_exists
end


-- get_interp is the main function for interpolating through control points
-- It requires 
--    a value, 
--    the ctrl index of a target's count parameter, 
--    ctrl index of linear/discrete, 
--    and parameter descriptor containing lower, upper, log

function get_interp(value, ctrl_ct, ctrl_lin, pd)
  local ctrl = CtrlPorts:array()
  
  if ctrl[ctrl_lin] > 0.5 then
    return get_interp_linear(value, ctrl_ct, ctrl_lin, pd)
  else
    return get_interp_discrete(value, ctrl_ct, ctrl_lin, pd)
  end
end
  
function get_interp_discrete(value, ctrl_ct, ctrl_lin, pd)
  local ctrl = CtrlPorts:array()
  count = math.floor(ctrl[ctrl_ct])
  idx = math.min(math.floor(value * count), count-1)
  idx_value = ctrl[ctrl_ct+idx+1]
  idx_value = math.min(math.max(idx_value, pd.lower), pd.upper)
  return idx_value
end
  
function get_interp_linear(value, ctrl_ct, ctrl_lin, pd)
  local ctrl = CtrlPorts:array()
  count = math.floor(ctrl[ctrl_ct])
  scaled = value * (count - 1)
  lower_idx = math.floor(scaled)
  upper_idx = lower_idx + 1
  
  upper_idx = math.min(upper_idx, count - 1) -- ignoring this causes a problem when value == 1
  
  lower_value = ctrl[ctrl_ct+lower_idx+1]
  upper_value = ctrl[ctrl_ct+upper_idx+1]
  
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



-- iterates through all targets, and for all valid target/locator/parameter configurations, use lua to write the processor parameter

function do_the_morph(verbose)
  local ctrl = CtrlPorts:array()
  value = ctrl[1]
  for t=0,MAX_TARGETS-1 do    
    local plugin_id = math.floor(ctrl[CTRL_IDX["t"..t.."pid"]])
    local nth_param = math.floor(ctrl[CTRL_IDX["t"..t.."nth"]])
    local enabled = ctrl[CTRL_IDX["t"..t.."ena"]] > 0.5
    
    local ctrl_ct = CTRL_IDX["t"..t.."_ct"]
    local ctrl_lin = CTRL_IDX["t"..t.."lin"]
    
    local target = targets[t]
    local locator = locators[t]
    if verbose then
      if target then
        print(t, plugin_id, target, "resolved to", target:to_insert():plugin(0):label())
      else
        print(t, plugin_id, nth_param, target, locator)
      end
    end
    if target then
      local interped
      local pd = get_check_param(target, nth_param)
      if pd then
        interped = get_interp(value, ctrl_ct, ctrl_lin, pd)
        
        -- target exists and is valid
        store_values_memory(t, interped, pd.lower, pd.upper, pd.logarithmic, 1, 1)
        
        if enabled then
          if locator and locator:to_insert():enabled() then
            ARDOUR.LuaAPI.set_processor_param(target, nth_param, interped)
          end
        end
      
      else
        -- target exists but is not valid
        store_values_memory(t, 0, 0, 0, 0, 0, 1)
      end
    else
    
      -- target does not exist
      store_values_memory(t, 0, 0, 0, 0, 0, 0)
    end
  end
end


-- keep track of LFO state at all times, but only write the value to ctrl["Controller"] if Use LFO is enabled

local t0 = 0
local v0 = 0.5
local a0 = 0
function do_the_lfo(n_samples, verbose)
  local ctrl = CtrlPorts:array()
  local dt = n_samples / sample_rate
  
  local proc_shape = ctrl[CTRL_IDX["lfo shape"]]
  local proc_freq = ctrl[CTRL_IDX["lfo freq (Hz)"]]
  local proc_beat = ctrl[CTRL_IDX["lfo beat div"]]
  local proc_speedmode = ctrl[CTRL_IDX["lfo mode"]] > 0.5
  local proc_phase = ctrl[CTRL_IDX["lfo phase (deg)"]]
  local proc_reset = ctrl[CTRL_IDX["lfo reset"]] > 0.5
  local use_lfo = ctrl[CTRL_IDX["Use LFO?"]] > 0.5
  
  local f1 = proc_freq
  if proc_speedmode then -- if true, then we're in tempo sync
    local tnow = Temporal.timepos_t(Session:transport_sample())
    local tm = Temporal.TempoMap.read()
    local bpm = tm:quarters_per_minute_at(tnow)
    f1 = bpm / 60 * proc_beat
    ARDOUR.LuaAPI.set_processor_param(self_proc, PARAM_IDX["lfo freq (Hz)"], f1)
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
  
  samples_since_draw = samples_since_draw + n_samples
  if samples_since_draw > samples_per_draw then
    samples_since_draw = samples_since_draw % samples_per_draw
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


local txt = nil -- cache font description (in GUI context)


-- Draw a bar corresponding to a target within the space allowed (top left corner is tx, ty, bottom right is tx+w, ty+h)
-- This is called 8 times, once for each of the Controller's targets, to provide an overview of all targets simultaneously

function draw_target(t, tx, ty, w, h, ctx, txt, ctrl, state)
  
  local start_shmem = t*MEMORY_PER_TARGET
  
  local value = state[start_shmem + 1]
  local minval = state[start_shmem + 2]
  local maxval = state[start_shmem + 3]
  local logarithmic = state[start_shmem + 4] > 0.5
  local valid = state[start_shmem + 5] > 0.5
  local ctrl_pid = state[start_shmem + 6]
  local enabled = state[start_shmem + 9] > 0.5
  local target_exists = state[start_shmem + 10] > 0.5
  
  local plugin_id = math.floor(ctrl[ctrl_pid])
  
  txt:set_text(string.format("%d", plugin_id));

  local tw, th = txt:get_pixel_size()
  ctx:set_source_rgba(1, 1, 1, 1.0)
  ctx:move_to(tx + w/2 - tw/2, ty + h - th)
  txt:show_in_cairo_context(ctx)
  
  local cap = 10
  local barheight = h - th - cap
  
  if valid then
    if logarithmic then 
      value = math.log(value) / math.log(10)
      minval = math.log(minval) / math.log(10)
      maxval = math.log(maxval) / math.log(10)
    end
    if maxval - minval > 0 then
      height = (value - minval) / (maxval - minval) 
    else
      height = 1
    end
    height = height * barheight
    
    r, g, b = hsv_to_rgb(plugin_id/128*360)
    
    ctx:set_line_cap(Cairo.LineCap.Round)
    
    -- draw outer white line
    ctx:set_line_width(cap)
    ctx:set_source_rgba(1, 1, 1, 1.0)
    ctx:move_to(tx + w/2, ty + h - th - cap/2)
    ctx:rel_line_to(0, -barheight)
    ctx:stroke()
    
    -- fill with black
    ctx:set_line_width(cap-2)
    ctx:set_source_rgba(0.1, 0.1, 0.1, 1.0)
    ctx:move_to(tx + w/2, ty + h - th - cap/2)
    ctx:rel_line_to(0, -barheight)
    ctx:stroke()
    
    -- fill partially with color
    ctx:set_line_width(cap-4)
    ctx:set_source_rgba(r, g, b, 1.0)
    ctx:move_to(tx + w/2, ty + h - th - cap/2)
    ctx:rel_line_to(0, -height)
    ctx:stroke()
  end
  
  
  if target_exists and not valid then
    ctx:rectangle(tx, ty, w, h)
    ctx:set_source_rgba(0.5, 0.1, 0.1, 0.5)
    ctx:fill()
  end
  if not target_exists then
    ctx:rectangle(tx, ty, w, h)
    ctx:set_source_rgba(0.1, 0.1, 0.1, 0.5)
    ctx:fill()
  end  
  if not enabled then
    ctx:rectangle(tx, ty, w, h)
    ctx:set_source_rgba(0.5, 0.5, 0.5, 0.5)
    ctx:fill()
  end
end


-- This draw call visualizes a single target's state in detail.
-- It interpolates through the entire range to create a plot of how the parameter will change

function visualize_single(t, w, h, ctx, txt, ctrl, state)
  
  local start_shmem = t*MEMORY_PER_TARGET
  
  local value = state[start_shmem + 1]
  local minval = state[start_shmem + 2]
  local maxval = state[start_shmem + 3]
  local logarithmic = state[start_shmem + 4] > 0.5
  local valid = state[start_shmem + 5] > 0.5
  local ctrl_pid = state[start_shmem + 6]
  local ctrl_ct = state[start_shmem + 7]
  local ctrl_lin = state[start_shmem + 8]
  local enabled = state[start_shmem + 9] > 0.5
  local target_exists = state[start_shmem + 10] > 0.5
  
  local plugin_id = math.floor(ctrl[ctrl_pid])
  local r,g,b = 1, 1, 1
  
  txt:set_text(string.format("t%d | %d", t, plugin_id));
  
  local tw, th = txt:get_pixel_size()
  ctx:set_source_rgba(r, g, b, 1.0)
  ctx:move_to(w/2 - tw/2, h - th)
  txt:show_in_cairo_context(ctx)
  
  if valid then
    r, g, b = 0.5, 0.5, 0.5
    local pd = {}
    pd.lower = minval
    pd.upper = maxval
    pd.logarithmic = logarithmic
    if logarithmic then 
      minval = math.log(minval) / math.log(10)
      maxval = math.log(maxval) / math.log(10)
    end    
    
    local padH = 5
    local padW = 5
    local W = w - 2*padW
    local H = h - th
    
    -- interpolate the path that the parameter will take over [0,1]
    ctx:set_line_width(1)
    ctx:set_source_rgba(r, g, b, 1.0)
    for x = 0, W do
      local trackvalue = x / W
      local interped = get_interp(trackvalue, ctrl_ct, ctrl_lin, pd)
      local scaled
      if logarithmic then 
        interped = math.log(interped) / math.log(10)
      end      
      if maxval - minval > 0 then
        scaled = (interped - minval) / (maxval - minval)
      else
        scaled = 0.5
      end
      local y = (H-2*padH)*(1 - scaled) + padH
      if x == 0 then ctx:move_to(padW, y) end
      ctx:line_to(x + padW, y)
    end
    ctx:stroke()
    
    local interped = get_interp(ctrl[1], ctrl_ct, ctrl_lin, pd)
    local scaled
    if logarithmic then 
      interped = math.log(interped) / math.log(10)
    end
    if maxval - minval > 0 then
      scaled = (interped - minval) / (maxval - minval)
    else
      scaled = 0.5
    end
    
    
    -- draw dot
    local cap = 10
    local x = ctrl[1]*W + padW
    local y = (H-2*padH)*(1-scaled) + padH
    
    ctx:set_line_cap(Cairo.LineCap.Round)
    
    -- draw outer white line
    ctx:set_line_width(cap)
    ctx:set_source_rgba(1, 1, 1, 1.0)
    ctx:move_to(x, y)
    ctx:rel_line_to(0, 0)
    ctx:stroke()
    
    -- fill with black
    ctx:set_line_width(cap-2)
    ctx:set_source_rgba(0.1, 0.1, 0.1, 1.0)
    ctx:move_to(x, y)
    ctx:rel_line_to(0, 0)
    ctx:stroke()
    
    -- add colored dot
    r, g, b = hsv_to_rgb(plugin_id/128*360)
    ctx:set_line_width(cap-4)
    ctx:set_source_rgba(r, g, b, 1.0)
    ctx:move_to(x, y)
    ctx:rel_line_to(0, 0)
    ctx:stroke()
  end
  
  if target_exists and not valid then
    ctx:rectangle(0, 0, w, h)
    ctx:set_source_rgba(0.5, 0.1, 0.1, 0.5)
    ctx:fill()
  end
  if not target_exists then
    ctx:rectangle(0, 0, w, h)
    ctx:set_source_rgba(0.1, 0.1, 0.1, 0.5)
    ctx:fill()
  end
  if not enabled then
    ctx:rectangle(0, 0, w, h)
    ctx:set_source_rgba(0.5, 0.5, 0.5, 0.5)
    ctx:fill()
  end
  
end


function render_inline(ctx, w, max_h)
  local ctrl = CtrlPorts:array() -- control port array
  local shmem = self:shmem() -- shared memory region
  local state = shmem:to_float(0):array() -- cast to lua-table
  
  -- prepare text rendering
  if not txt then
    -- allocate PangoLayout and set font
    --http://manual.ardour.org/lua-scripting/class_reference/#Cairo:PangoLayout
    txt = Cairo.PangoLayout (ctx, "Mono 9px")
  end  
  
  local h = max_h
  
  -- clear background
  r, g, b = 0.1, 0.1, 0.1
  ctx:rectangle(0, 0, w, h)
  ctx:set_source_rgba(r, g, b, 1.0)
  ctx:fill()
  
  local visualize_all = ctrl[2] < -0.5
  if visualize_all then
    
    local NROWS = 2
    local NCOLS = MAX_TARGETS/NROWS
    
    for t = 0,(MAX_TARGETS-1) do  
      local row = math.floor(t / (MAX_TARGETS/NROWS))
      local col = t % NCOLS
      local tx = col*(w/NCOLS)
      local ty = row*(h/NROWS)
      draw_target(t, tx, ty, w/NCOLS, h/NROWS, ctx, txt, ctrl, state)
    end
  else
    visualize_single(ctrl[2], w, h, ctx, txt, ctrl, state)
  end
  
  return {w, h}
end
