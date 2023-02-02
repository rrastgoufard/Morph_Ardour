
ardour {
  ["type"]    = "Session",
  name        = "Preset Loader",
  category    = "Utility",
  license     = "MIT",
  author      = "RR",
  description = [[Preset Loader, to be coupled with Preset Locators placed in tracks.]]
}

--[[

This is completely undocumented, but see this post on the forums for motivation.
https://discourse.ardour.org/t/ardour-for-live-performance-with-surge-xt/108257/2

Also, look at the sample script for implementation help.
https://github.com/Ardour/ardour/blob/master/share/scripts/s_pluginutils.lua

]]

function factory ()   

  -- keep track of the last preset for every processor
  local last_set_by_proc_id = {}

  -- try to set the processor's preset to the given number
  function set_preset(proc, preset_number)
    if proc:isnil() then return end
    local plug = proc:to_insert():plugin(0)
    local psets = plug:get_info():get_presets()
    local id = plug:id():to_s()
    local last = last_set_by_proc_id[id]
    
    -- don't set the preset if it is not different
    if last and last == preset_number then
      return
    end
    
    -- find the jth preset, and if that is the desired one, then set it
    j = 1
    for pset in psets:iter() do
      if j == preset_number then
        local label = plug:label()
        plug:load_preset(pset)
        last_set_by_proc_id[id] = preset_number
        print("Changed", label, "to preset", pset.label)
        return
      end
      j = j + 1
    end
  end


  -- find locator and plugin immediately following it
  function scan_routes(verbose)
    
    for r in Session:get_routes():iter() do
      local i = 0 -- keep track of plugin index on this route
      while true do
        local proc = r:nth_plugin(i)
        if proc:isnil() then break end -- go to next route
        local plug = proc:to_insert():plugin(0)
        local label = plug:label()
        local unique_id = plug:unique_id()
        
        
        if verbose then
          print(label, unique_id)
          
          local psets = plug:get_info():get_presets()
          if psets and not psets:empty() then
            local j = 1
            for pset in psets:iter() do
              print("--", j, pset.label)
              j = j + 1
            end
          end
        
        end
        
        if label == "Preset Locator" then
          local locator_id = ARDOUR.LuaAPI.get_processor_param(proc, 0)
          locator_id = math.floor(locator_id)
          set_preset(r:nth_plugin(i+1), locator_id)
        end
        
        i = i + 1
        
      end
    end
    
  end
  
  -- scan routes once while printing out all of the numbered presets
  -- then do it every time step without printing
  scan_routes(true)
  return function (n_samples)
    scan_routes(false)
  end 
  
end
