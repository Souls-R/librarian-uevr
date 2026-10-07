-- Librarian: right-hand aim and readable book titles. UEVR nightly 01143.
local api,vr=uevr.api,uevr.params.vr
UEVR_UObjectHook.activate()
local elapsed=1
local originals={}
local status={version=3,mode='right_controller',updates=0}
local hp,hr=UEVR_Vector3f.new(),UEVR_Quaternionf.new()
local rp,rr=UEVR_Vector3f.new(),UEVR_Quaternionf.new()
local function vec(v) return {x=v.x,y=v.y,z=v.z} end
local function quat(v) return {x=v.x,y=v.y,z=v.z,w=v.w} end
local function move_slot(widget,top,height,width)
    if not widget or not widget.Slot then return end
    local slot=widget.Slot
    local key=slot:get_address()
    if not originals[key] then
        local d=slot.LayoutData
        originals[key]={slot=slot,name=slot:get_full_name(),layout={Anchors={Minimum={X=d.Anchors.Minimum.X,Y=d.Anchors.Minimum.Y},Maximum={X=d.Anchors.Maximum.X,Y=d.Anchors.Maximum.Y}},Alignment={X=d.Alignment.X,Y=d.Alignment.Y},Offsets={Left=d.Offsets.Left,Top=d.Offsets.Top,Right=d.Offsets.Right,Bottom=d.Offsets.Bottom}}}
    end
    slot:SetAnchors({Minimum={X=0.5,Y=0.5},Maximum={X=0.5,Y=0.5}})
    slot:SetAlignment({X=0,Y=0})
    slot:SetPosition({X=-width/2,Y=top})
    slot:SetSize({X=width,Y=height})
end
local function update()
    local pc=api:get_player_controller(0)
    local pawn=api:get_local_pawn(0)
    if not pc or not pawn then return end
    local main=pc.MyHUD and pc.MyHUD.MainUMG
    local hud=main and main.WBP_PlayerInfo
    if hud then
        move_slot(hud.Text_LookingItem,45,60,720)
        if hud.Panel_LookingBookName then
            local panel=hud.Panel_LookingBookName
            for i=0,panel:GetChildrenCount()-1 do
                local child=panel:GetChildAt(i)
                if child and child:get_short_name()=='Image_143' then move_slot(child,36,80,820) end
            end
        end
    end
    status.aim_method=vr.get_aim_method()
    status.control_rotation=vec(pc:GetControlRotation())
    local cam=pc.PlayerCameraManager
    status.camera_position=vec(cam:GetCameraLocation())
    status.camera_rotation=vec(cam:GetCameraRotation())
    status.sensor_actor=pawn.ObjectSensorComponent.currentActor and pawn.ObjectSensorComponent.currentActor:get_full_name() or ''
    status.sensor_item=pawn.ObjectSensorComponent.currentItem and tostring(pawn.ObjectSensorComponent.currentItem) or ''
    vr.get_pose(vr.get_hmd_index(),hp,hr)
    vr.get_pose(vr.get_right_controller_index(),rp,rr)
    status.hmd={position=vec(hp),rotation=quat(hr)}
    status.right={position=vec(rp),rotation=quat(rr)}
    status.paused=pawn.IsPauseGame
    status.updates=status.updates+1
end
uevr.sdk.callbacks.on_pre_engine_tick(function(engine,delta)
    elapsed=elapsed+delta
    if elapsed<1 then return end
    elapsed=0
    local ok,err=pcall(update)
    status.error=ok and '' or tostring(err)
    json.dump_file('librarian-comfort-status.json',status,2)
end)
uevr.sdk.callbacks.on_script_reset(function()
    for _,entry in pairs(originals) do
        if UEVR_UObjectHook.exists(entry.slot) then
            pcall(function() if entry.slot:get_full_name()==entry.name then entry.slot:SetLayout(entry.layout) end end)
        end
    end
end)
-- Retire the head-pitch experiment and use UEVR's controller orientation tracking.
vr.set_aim_method(2)
vr.set_mod_value('VR_AimModifyPlayerControlRotation','true')
vr.set_mod_value('VR_AimInterp','false')
vr.save_config()
uevr.params.functions.log_info('[LibrarianComfort] v3: right controller aim, no head pitch override.')
