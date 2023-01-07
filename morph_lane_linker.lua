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
    {"p0", 19561, "Frequency 0", 10000, 50},
    {"p0", 19561, "Gain 0", 0.25, 13.5},
    
  }

  all_plugins = {}

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
        local name = pi:type() .. "-" .. pp:unique_id()
        local id = pp:id():to_s()
        print("    " .. i .. " " .. id .. " " .. name)
        all_plugins[id] = proc
        
        i = i + 1
      end
    end
  end
  
  function link_lanes()
    
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
      
      plugin = all_plugins[plugin_id]:to_automatable()
      print(plugin)
      for p in plugin:all_automatable_params():iter() do
        print("  ", p)
      end
      
    end
    
    
    
--     for a in ARDOUR:ParameterList:iter() do
--       print(a)
--     end
    

    return ""
  end  


  collect_plugins()
  link_lanes()
  

  return function(n_samples)
    local route = Session:route_by_name("Morph")
    assert (not route:isnil())
    
    local plugin = route:nth_plugin(0)
    assert (not plugin:isnil())
    
    -- get the value of p0 and forcibly set p1 and p2 to that value
    local value = ARDOUR.LuaAPI.get_processor_param(plugin, 0)
    ARDOUR.LuaAPI.set_processor_param(plugin, 1, value)
    ARDOUR.LuaAPI.set_processor_param(plugin, 2, value)
  end
end
