ardour {
	["type"]    = "session",
	name        = "Morph Lane Linker",
	license     = "MIT",
	author      = "RR",
	description = [[generalized Morph lane linker]]
} 

function factory()

  desired_links = {

  -- morph lane, plugin id, parameter name, value at 0, value at 1
    {"p0", 35775, "Frequency 0", 10000, 50},
--     {"p0", 30445, "Gain 0", 0.25, 13.5},
    
  }

  all_plugins = {}
  morph_instances = {}

  function collect_plugins()
    print()
    print()
    print("Searching all routes for plugins")

    for r in Session:get_routes():iter() do
      print("  Route " .. r:name())
      local i = 0
      while true do
        local proc = r:nth_plugin(i)
        if proc:isnil() then break end
        local pi = proc:to_insert()
        local pp = pi:plugin(0)
        local name = pi:type() .. "-" .. pp:unique_id() .. " named: " .. pp:label()
        local id = pp:id():to_s()
        print("    " .. i .. " " .. id .. " " .. name)
        if pp:label() == "Morph Processor" then
          table.insert(morph_instances, proc)
        end
        all_plugins[id] = proc
        
        i = i + 1
      end
    end
  end
  
  function configure_morph_processors()
    print("Configuring morph processors")
    for i, proc in pairs(morph_instances) do
      print(i, proc)
    end
  end
  
  function link_lanes()
  
    print("Linking lanes")
    
    print(desired_links)
    print(all_plugins)
    
    for k, v in pairs(all_plugins) do
      print(k, v)
    end

    for _, case in ipairs(desired_links) do
      source_lane = case[1]
      plugin_id = tostring(case[2])
      target_lane_name = case[3]
      target_at_0 = case[4]
      target_at_1 = case[5]
      
      print(source_lane, plugin_id, target_lane_name)
      
      proc = all_plugins[plugin_id]
      if not proc then
        print("Uh oh... proc", plugin_id, "does not exist...")
      else
        plug = proc:to_insert():plugin(0)
        print(plug:label())
        param_count = 0
        for j=0, plug:parameter_count() - 1 do
          if plug:parameter_is_control(j) then
            local label = plug:parameter_label(j)
            print("    ", param_count, " ", label)
            param_count = param_count + 1
          end
        end
      end
    end
    
    
    
--     for a in ARDOUR:ParameterList:iter() do
--       print(a)
--     end
    

    return ""
  end  


  collect_plugins()
--   configure_morph_processors()
  link_lanes()
  
  function get_interp(m, value, start)
    count = math.floor(ARDOUR.LuaAPI.get_processor_param(m, start))
    scaled = value * (count - 1)
    lower_idx = math.floor(scaled)
    upper_idx = math.ceil(scaled)
    percentage = scaled - lower_idx
    lower_value = ARDOUR.LuaAPI.get_processor_param(m, start+lower_idx+1)
    upper_value = ARDOUR.LuaAPI.get_processor_param(m, start+upper_idx+1)
    return (1-percentage)*lower_value + percentage*upper_value
  end
  
  function do_the_morph(m)
    MAX_TARGETS = 4
    PARAMS_PER_TARGET = 14
    value = ARDOUR.LuaAPI.get_processor_param(m, 0)
    for t=0,MAX_TARGETS-1 do
      local start = t*PARAMS_PER_TARGET + 1
      local plugin_id = math.floor(ARDOUR.LuaAPI.get_processor_param(m, start+11))
      local nth_param = math.floor(ARDOUR.LuaAPI.get_processor_param(m, start+12))
      local enabled = ARDOUR.LuaAPI.get_processor_param(m, start+13) > 0.5
      local target = all_plugins[tostring(plugin_id)]
      if enabled then
        if target then
          interped = get_interp(m, value, start)
          ARDOUR.LuaAPI.set_processor_param(target, nth_param, interped)
        else
          if plugin_id >= 0 then
            print("Target with id", plugin_id, "not found?")
          end
        end
      end
    end
  end
  
  

  return function(n_samples)
    for _,m in pairs(morph_instances) do
      do_the_morph(m)
    end
--     local route = Session:route_by_name("Morph")
--     assert (not route:isnil())
--     
--     local plugin = route:nth_plugin(0)
--     assert (not plugin:isnil())
--     
--     -- get the value of p0 and forcibly set p1 and p2 to that value
--     local value = ARDOUR.LuaAPI.get_processor_param(plugin, 0)
--     ARDOUR.LuaAPI.set_processor_param(plugin, 1, value)
--     ARDOUR.LuaAPI.set_processor_param(plugin, 2, value)
  end
end
