ardour {
  ["type"]    = "session",
  name        = "Morph Lane Linker",
  license     = "MIT",
  author      = "RR",
  description = [[generalized Morph lane linker.  Needs morph_locator.lua placed before each plugin that is to be controlled as well as a morph_controller.lua plugin to do the actual controlling.  Can now run morph_lfo.lua as a low frequency oscillator.]]
} 

function factory()

  unique_plugins = {}
  located_plugins = {}
  morph_locators = {}
  morph_controllers = {}
  morph_lfos = {}
  warnings = {}
  
  function find_morph_locations()
    print("\n\n\nSearching all plugins on all routes")
    for r in Session:get_routes():iter() do
      local i = 0
      local next_is_located = false
      local next_id = -1
      while true do
        local proc = r:nth_plugin(i)
        if proc:isnil() then break end
        local pi = proc:to_insert()
        local pp = pi:plugin(0)
        local name = pi:type() .. "-" .. pp:unique_id() .. " named: " .. pp:label()
        local id = pp:id():to_s()
        
        unique_plugins[pp:unique_id()] = proc -- keep track of all plugins so that we can print out their parameter lists later
        
        if next_is_located then
          located_plugins[next_id] = proc -- this is value is set in the locator and identifies it
          print("Morph Locator with id", next_id, "is looking at", name)
        end
        if pp:label() == "Morph Controller" or pp:label() == "Morph Processor" then
          table.insert(morph_controllers, proc)
        end
        if pp:label() == "Morph LFO" then
          table.insert(morph_lfos, {proc, 0, 0.5, 0})
        end
        if pp:label() == "Morph Locator" then 
          next_is_located = true
          next_id = tostring(math.floor(ARDOUR.LuaAPI.get_processor_param(proc, 0)))
          morph_locators[next_id] = proc
          print("Found a Morph Locator set to", next_id)
          if located_plugins[next_id] then
            table.insert(warnings, "the id " .. next_id .. " has already been used by a Morph Locator")
          end
        else
          next_is_located = false
          next_id = -1
        end
        
        i = i + 1
      end
    end
    print("Finished examining all plugins")
  end
  
  function print_parameters()
    for name, proc in pairs(unique_plugins) do
      print(name)
      plug = proc:to_insert():plugin(0)
      param_count = 0
      for j = 0, plug:parameter_count() - 1 do
        if plug:parameter_is_control(j) then
          local label = plug:parameter_label(j)
          local _, descriptor_table = plug:get_parameter_descriptor(j, ARDOUR.ParameterDescriptor())
          local pd = descriptor_table[2]
          print("     ", param_count, " ", label, pd.lower, pd.upper, ", logarithmic =", pd.logarithmic)
          param_count = param_count + 1
        end
      end
    end
  end  
  
  function get_interp(m, value, start, pd)
    count = math.floor(ARDOUR.LuaAPI.get_processor_param(m, start))
    scaled = value * (count - 1)
    lower_idx = math.floor(scaled)
    upper_idx = lower_idx + 1
    lower_value = ARDOUR.LuaAPI.get_processor_param(m, start+lower_idx+1)
    upper_value = ARDOUR.LuaAPI.get_processor_param(m, start+upper_idx+1)
    
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
  
  function do_the_morph(m, verbose)
    MAX_TARGETS = 8
    PARAMS_PER_TARGET = 14
    value = ARDOUR.LuaAPI.get_processor_param(m, 0)
    for t=0,MAX_TARGETS-1 do    
      local start = t*PARAMS_PER_TARGET + 1
      local plugin_id = math.floor(ARDOUR.LuaAPI.get_processor_param(m, start+11))
      local nth_param = math.floor(ARDOUR.LuaAPI.get_processor_param(m, start+12))
      local enabled = ARDOUR.LuaAPI.get_processor_param(m, start+13) > 0.5
      local target = located_plugins[tostring(plugin_id)]
      local locator = morph_locators[tostring(plugin_id)]
      if verbose then
        if target then
          print(m, t, plugin_id, target, "resolved to", target:to_insert():plugin(0):label())
        else
          print(m, t, plugin_id, target)
        end
      end
      if enabled then
        if target and nth_param >= 0 then
          -- this silently fails if nth_param is not a valid input parameter for the target processor
          _, _, pd = ARDOUR.LuaAPI.plugin_automation(target, nth_param)
          interped = get_interp(m, value, start, pd)
          if locator:to_insert():enabled() and m:to_insert():enabled() then
            ARDOUR.LuaAPI.set_processor_param(target, nth_param, interped)
          end
        end
      end
    end
  end
  
  function do_the_lfo(m, n_samples, verbose)
    dt = n_samples / Session:sample_rate()
    proc = m[1]
    
    proc_shape = ARDOUR.LuaAPI.get_processor_param(proc, 0)
    proc_freq = ARDOUR.LuaAPI.get_processor_param(proc, 1)
    proc_phase = ARDOUR.LuaAPI.get_processor_param(proc, 2)
    proc_reset = ARDOUR.LuaAPI.get_processor_param(proc, 3) > 0.5
    plugin_id = math.floor(ARDOUR.LuaAPI.get_processor_param(proc, 4))
    nth_param = math.floor(ARDOUR.LuaAPI.get_processor_param(proc, 5))
    local target = located_plugins[tostring(plugin_id)]
    local locator = morph_locators[tostring(plugin_id)]
    
    t0 = m[2] -- the previous time instant
    v0 = m[3] -- the previous value
    a0 = m[4] -- the previous angle
    
    f1 = proc_freq
    t1 = t0 + dt
    theta = 0 -- theta is unused unless sine is selected
    
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
    
    m[2] = t1
    m[3] = v1
    m[4] = theta
    
    if verbose then
      print(proc, m[2], m[3], m[4])
    end
    
    enabled = true
    if enabled then
      if target and nth_param >= 0 then
        -- this silently fails if nth_param is not a valid input parameter for the target processor
        _, _, pd = ARDOUR.LuaAPI.plugin_automation(target, nth_param)
        if proc:to_insert():enabled() and locator:to_insert():enabled() then
          ARDOUR.LuaAPI.set_processor_param(target, nth_param, v1)
        end
      end
    end
        
    
  end
    
  
  function print_warnings()
    for _,w in pairs(warnings) do
      print("WARNING:", w)
    end
  end
  
  function calculate_morphs(verbose)
    for k, m in pairs(morph_controllers) do
      if verbose then
        print("Morph Controller", k)
      end
      do_the_morph(m, verbose)
    end
  end
  
  function calculate_lfos(n_samples, verbose)
    for k, m in pairs(morph_lfos) do
      if verbose then
        print("Morph LFO", k)
      end
--       do_the_lfo(m, verbose)
      do_the_lfo(m, n_samples, verbose)
    end
  end
  
  find_morph_locations()
  print_parameters()
  print_warnings()
  calculate_morphs(true) -- run it once in verbose mode
  calculate_lfos(0, true) -- run lfos once too

  return function(n_samples)
    calculate_morphs(false)
    calculate_lfos(n_samples, false)
  end
end
