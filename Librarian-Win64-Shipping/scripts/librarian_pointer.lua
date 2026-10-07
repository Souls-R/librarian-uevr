-- Load and reload the right-hand pointer module from the profile data folder.
UEVR_UObjectHook.activate()
local module,source,elapsed=nil,nil,1
local module_status={}
local function invoke(name,...)
    if not module or not module[name] then return end
    local ok,err=pcall(module[name],...)
    if not ok then
        module_status.error=tostring(err)
        if module.cleanup then pcall(module.cleanup) end
        module=nil
        json.dump_file('librarian-pointer-status.json',module_status,2)
    end
end
uevr.sdk.callbacks.on_pre_engine_tick(function(engine,delta)
    elapsed=elapsed+delta
    if elapsed>=1 then
        elapsed=0
        local new_source=fs.read('librarian-pointer-module.lua')
        if new_source and #new_source>0 and new_source~=source then
            invoke('cleanup')
            module=nil
            source=new_source
            local fn,err=load(source,'librarian-pointer-module','t')
            if fn then
                local ok,result=pcall(fn)
                if ok then module=result;module_status={loaded=true};invoke('init')
                else module_status={error=tostring(result)} end
            else module_status={error=tostring(err)} end
            json.dump_file('librarian-pointer-loader.json',module_status,2)
        end
    end
    invoke('tick',engine,delta)
end)
uevr.sdk.callbacks.on_pre_calculate_stereo_view_offset(function(...) invoke('pre_render',...) end)
uevr.sdk.callbacks.on_pre_viewport_client_draw(function(...) invoke('pre_draw',...) end)
uevr.sdk.callbacks.on_post_engine_tick(function(...) invoke('post_tick',...) end)
uevr.sdk.callbacks.on_script_reset(function() invoke('cleanup') end)
