ardour {
  ["type"]    = "session",
  name        = "Morph Lane Linker",
  license     = "MIT",
  author      = "RR",
  description = [[generalized Morph lane linker.  Needs morph_locator.lua placed before each plugin that is to be controlled as well as a morph_controller.lua plugin to do the actual controlling.]]
} 

function factory()

  unique_plugins = {}
  located_plugins = {}
  morph_instances = {}
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
          table.insert(morph_instances, proc)
        end
        if pp:label() == "Morph Locator" then 
          next_is_located = true
          next_id = tostring(math.floor(ARDOUR.LuaAPI.get_processor_param(proc, 0)))
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
          ARDOUR.LuaAPI.set_processor_param(target, nth_param, interped)
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
    for k, m in pairs(morph_instances) do
      if verbose then
        print("Morph Controller", k)
      end
      do_the_morph(m, verbose)
    end
  end
  
  find_morph_locations()
  print_parameters()
  print_warnings()
  calculate_morphs(true) -- run it once in verbose mode

  return function(n_samples)
    calculate_morphs(false)
  end
end
