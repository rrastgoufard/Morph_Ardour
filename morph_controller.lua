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
MEMORY_PER_TARGET = 5

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
  self:shmem():allocate(MEMORY_PER_TARGET*MAX_TARGETS)
	self:shmem():clear()
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
    table.insert(output, { ["type"] = "input", name = "t" .. i .. "pid", min = -1, max = 127, default = -1, integer = true })
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

function get_min_max(t)
  local ctrl = CtrlPorts:array()
  local start = t*PARAMS_PER_TARGET + 1 + 1
  local count = math.floor(ctrl[start])
  local settings_min = ctrl[start+1]
  local settings_max = ctrl[start+1]
  for i = 1,(count-1) do
    settings_min = math.min(settings_min, ctrl[start+1+i])
    settings_max = math.max(settings_max, ctrl[start+1+i])
  end
  return settings_min, settings_max
end

function store_values_memory(t, value, param_lower, param_upper, logarithmic, valid)  
  settings_min, settings_max = get_min_max(t)
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
    lower_value = math.log(upper_value) / math.log(10)
  end
  interped = (1-percentage)*lower_value + percentage*upper_value
  if pd.logarithmic then
    interped = 10^interped
  end
  
  return interped, pd.lower, pd.upper, pd.logarithmic
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
        interped, param_lower, param_upper, logarithmic = get_interp(value, start, pd)
        store_values_memory(t, interped, param_lower, param_upper, logarithmic, 1)
        if locator and locator:to_insert():enabled() then
          ARDOUR.LuaAPI.set_processor_param(target, nth_param, interped)
        end
      end
    end
    if not target then
      store_values_memory(t, 0, 0, 0, 0, 0)
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

function draw_target(t, tx, ty, w, h, ctx, txt, ctrl, state)
  local start_ctrl = t*PARAMS_PER_TARGET + 1 + 1
  local start_shmem = t*MEMORY_PER_TARGET + 1
  local plugin_id = math.floor(ctrl[start_ctrl+11])
  
  local value = state[start_shmem + 0]
  local minval = state[start_shmem + 1]
  local maxval = state[start_shmem + 2]
  local logarithmic = state[start_shmem + 3] > 0.5
  local valid = state[start_shmem + 4]
  
  txt:set_text(string.format("%d", plugin_id));

  local tw, th = txt:get_pixel_size()
  ctx:set_source_rgba(1, 1, 1, 1.0)
  ctx:move_to(tx + w/2 - tw/2, ty + h - th)
  txt:show_in_cairo_context(ctx)
  
  local cap = 10
  local barheight = h - th - cap
  
  if valid > 0.5 then
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
    ctx:set_line_width(6.0)
    ctx:set_source_rgba(0.1, 0.1, 0.1, 1.0)
    ctx:move_to(tx + w/2, ty + h - th - cap/2)
    ctx:rel_line_to(0, -barheight)
    ctx:stroke()
    
    -- fill partially with color
    ctx:set_source_rgba(r, g, b, 1.0)
    ctx:move_to(tx + w/2, ty + h - th - cap/2)
    ctx:rel_line_to(0, -height)
    ctx:stroke()
  end
  
  if valid < 0.5 then
    ctx:rectangle(tx, ty, w, h)
    ctx:set_source_rgba(0.1, 0.1, 0.1, 0.5)
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
  
  for t = 0,(MAX_TARGETS-1) do
    
    local NROWS = 2
    local NCOLS = MAX_TARGETS/NROWS
    local row = math.floor(t / (MAX_TARGETS/NROWS))
    local col = t % NCOLS
    local tx = col*(w/NCOLS)
    local ty = row*(h/NROWS)
    
    draw_target(t, tx, ty, w/NCOLS, h/NROWS, ctx, txt, ctrl, state)
  end
  
  return {w, h}
end
