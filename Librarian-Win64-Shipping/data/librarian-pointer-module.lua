-- Live right-hand pointer. Only transient visual components are created.
local api,vr=uevr.api,uevr.params.vr
local M={}
local actor,beam,dot,hidden
local last,elapsed={},1
local hp,hq=UEVR_Vector3f.new(),UEVR_Quaternionf.new()
local rp,rq=UEVR_Vector3f.new(),UEVR_Quaternionf.new()
local origin,offset=UEVR_Vector3f.new(),UEVR_Quaternionf.new()
local adjusted_offset=UEVR_Quaternionf.new()
local camera_attachment
local settings={aim_yaw_degrees=0,aim_pitch_degrees=0,title_gap_pixels=24,title_smoothing_seconds=0.12,title_deadzone_pixels=3,held_label_right_pixels=90,held_label_up_pixels=64,held_label_smoothing_seconds=0.18}
local settings_elapsed=1
local title_state={widgets={},x=nil,y=nil}
local held_state={x=nil,y=nil,found=false}
local held_widget,held_hud
local previous_ui_follow
local ui_metrics={height=1080,width=1920,distance=200,size=200,x=0,y=-50}
local sys=api:find_uobject('Class /Script/Engine.KismetSystemLibrary'):as_class():get_class_default_object()
local gs=api:find_uobject('Class /Script/Engine.GameplayStatics'):as_class():get_class_default_object()
local widget_layout=api:find_uobject('Class /Script/UMG.WidgetLayoutLibrary'):as_class():get_class_default_object()
local break_names={}
do
    local fn=api:find_uobject('Function /Script/Engine.GameplayStatics.BreakHitResult')
    if fn then
        local p=fn:as_struct():get_child_properties()
        while p do table.insert(break_names,p:get_fname():to_string());p=p:get_next() end
    end
end
local V=Vector3d.new
local function xyz(v) return {x=v.x,y=v.y,z=v.z} end
local function add(a,b) return V(a.x+b.x,a.y+b.y,a.z+b.z) end
local function sub(a,b) return V(a.x-b.x,a.y-b.y,a.z-b.z) end
local function mul(a,s) return V(a.x*s,a.y*s,a.z*s) end
local function len(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end
local function dot_product(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function forward(rot)
    local p,y=math.rad(rot.x),math.rad(rot.y)
    return V(math.cos(p)*math.cos(y),math.cos(p)*math.sin(y),math.sin(p))
end
local function qrot(q,v)
    local tx,ty,tz=2*(q.y*v.z-q.z*v.y),2*(q.z*v.x-q.x*v.z),2*(q.x*v.y-q.y*v.x)
    return V(v.x+q.w*tx+q.y*tz-q.z*ty,v.y+q.w*ty+q.z*tx-q.x*tz,v.z+q.w*tz+q.x*ty-q.y*tx)
end
local function tracking_to_world(v,yaw)
    local a=qrot(offset,v)
    local y=math.rad(-yaw)
    local x,z=math.cos(y)*a.x+math.sin(y)*a.z,-math.sin(y)*a.x+math.cos(y)*a.z
    return V(-z,x,a.y)
end
function M.init()
    previous_ui_follow=vr:get_mod_value('UI_FollowView')
    vr.set_mod_value('UI_FollowView','true')
    vr.save_config()
end
local function update_settings(pawn,delta)
    settings_elapsed=settings_elapsed+delta
    if settings_elapsed<1 then return end
    settings_elapsed=0
    local ok,data=pcall(json.load_file,'librarian-pointer-settings.json')
    if ok and type(data)=='table' then
        for name,value in pairs(settings) do
            if type(data[name])=='number' then settings[name]=data[name] end
        end
    end
    settings.aim_yaw_degrees=clamp(settings.aim_yaw_degrees,-15,15)
    settings.aim_pitch_degrees=clamp(settings.aim_pitch_degrees,-15,15)
    settings.title_smoothing_seconds=clamp(settings.title_smoothing_seconds,0.03,0.5)
    settings.held_label_smoothing_seconds=clamp(settings.held_label_smoothing_seconds,0.03,0.5)
    local dpi=widget_layout:GetViewportScale(pawn)
    local size=widget_layout:GetViewportSize(pawn)
    ui_metrics.height=(size.Y or size.y)/math.max(dpi,0.1)
    ui_metrics.width=(size.X or size.x)/math.max(dpi,0.1)
    ui_metrics.distance=(tonumber(vr:get_mod_value('UI_Distance')) or 2)*100
    ui_metrics.size=(tonumber(vr:get_mod_value('UI_Size')) or 2)*100
    ui_metrics.x=(tonumber(vr:get_mod_value('UI_X_Offset')) or 0)*100
    ui_metrics.y=(tonumber(vr:get_mod_value('UI_Y_Offset')) or -0.5)*100
end
local function translate_widget(w,x,y)
    if not w then return end
    local key=w:get_address()
    if not title_state.widgets[key] then
        local t=w.RenderTransform.Translation
        title_state.widgets[key]={w=w,name=w:get_full_name(),x=t.X,y=t.Y}
    end
    w:SetRenderTranslation({X=x,Y=y})
end
local function project_to_ui(base,yaw,point)
    local head=add(base,mul(tracking_to_world(sub(hp,origin),yaw),100))
    local relative=sub(point,head)
    local f=tracking_to_world(qrot(hq,V(0,0,-1)),yaw)
    local r=tracking_to_world(qrot(hq,V(1,0,0)),yaw)
    local u=tracking_to_world(qrot(hq,V(0,1,0)),yaw)
    local depth=dot_product(relative,f)
    if depth<10 then return end
    local px_per_cm=ui_metrics.height/ui_metrics.size
    local x=(dot_product(relative,r)*ui_metrics.distance/depth-ui_metrics.x)*px_per_cm
    local y=-(dot_product(relative,u)*ui_metrics.distance/depth-ui_metrics.y)*px_per_cm
    return x,y
end
local function update_title(pc,base,yaw,finish,delta)
    local main=pc.MyHUD and pc.MyHUD.MainUMG
    local hud=main and main.WBP_PlayerInfo
    if not hud or not hud.Panel_LookingBookName then return end
    local x,y=project_to_ui(base,yaw,finish)
    if not x then return end
    y=y+settings.title_gap_pixels-45
    x=clamp(x,-math.max(0,ui_metrics.width/2-440),math.max(0,ui_metrics.width/2-440))
    y=clamp(y,-ui_metrics.height/2+100,ui_metrics.height/2-180)
    if not title_state.x then title_state.x=x;title_state.y=y end
    local dx,dy=x-title_state.x,y-title_state.y
    local distance=math.sqrt(dx*dx+dy*dy)
    if distance>settings.title_deadzone_pixels then
        local alpha=1-math.exp(-math.min(delta,0.1)/settings.title_smoothing_seconds)
        local factor=(distance-settings.title_deadzone_pixels)/distance*alpha
        title_state.x=title_state.x+dx*factor;title_state.y=title_state.y+dy*factor
    end
    translate_widget(hud.Panel_LookingBookName,title_state.x,title_state.y)
    translate_widget(main.ActionWidget,title_state.x,title_state.y)
end
local function update_held_label(pc,base,yaw,start,delta)
    local main=pc.MyHUD and pc.MyHUD.MainUMG
    local hud=main and main.WBP_PlayerInfo
    local held=hud and hud.WBP_BookNameList
    if not held and hud then
        if held_hud==hud and held_widget and UEVR_UObjectHook.exists(held_widget) then held=held_widget
        else
            local root=hud.Panel_LookingBookName and hud.Panel_LookingBookName:GetParent()
            if root then
                for i=0,root:GetChildrenCount()-1 do
                    local child=root:GetChildAt(i)
                    if child:get_short_name()=='WBP_BookNameList' then held=child;break end
                end
            end
            held_hud,held_widget=hud,held
        end
    end
    if not held or not held.Slot then return end
    held_state.found=true
    local x,y=project_to_ui(base,yaw,start)
    if not x then return end
    -- Keep the native inventory widget, including its selected-book arrow
    -- and automatic updates. Only move its presentation near the right hand.
    x=x+settings.held_label_right_pixels
    y=y-settings.held_label_up_pixels
    x=clamp(x,-math.max(0,ui_metrics.width/2-430),math.max(0,ui_metrics.width/2-430))
    y=clamp(y,-ui_metrics.height/2+80,ui_metrics.height/2-100)
    if not held_state.x then held_state.x=x;held_state.y=y end
    local dx,dy=x-held_state.x,y-held_state.y
    local distance=math.sqrt(dx*dx+dy*dy)
    if distance>4 then
        local alpha=1-math.exp(-math.min(delta,0.1)/settings.held_label_smoothing_seconds)
        local factor=(distance-4)/distance*alpha
        held_state.x=held_state.x+dx*factor;held_state.y=held_state.y+dy*factor
    end
    local d=held.Slot.LayoutData
    local old_x=d.Anchors.Minimum.X*ui_metrics.width+d.Offsets.Left-d.Alignment.X*d.Offsets.Right
    local old_y=d.Anchors.Minimum.Y*ui_metrics.height+d.Offsets.Top-d.Alignment.Y*d.Offsets.Bottom
    local new_x=ui_metrics.width/2+held_state.x-400
    local new_y=ui_metrics.height/2+held_state.y
    translate_widget(held,new_x-old_x,new_y-old_y)
    local actual=held.RenderTransform.Translation
    held_state.translation={x=actual.X,y=actual.Y}
end
local function transform()
    local t=StructObject.new(api:find_uobject('ScriptStruct /Script/CoreUObject.Transform'))
    t.Rotation={X=0,Y=0,Z=0,W=1};t.Translation=V(0,0,0);t.Scale3D=V(1,1,1)
    return t
end
local function create_visuals(pawn)
    local t=transform()
    actor=gs:BeginDeferredActorSpawnFromClass(pawn,api:find_uobject('Class /Script/Engine.Actor'),t,1,pawn,0)
    assert(actor,'Pointer actor creation failed')
    gs:FinishSpawningActor(actor,t,0)
    local cls=api:find_uobject('Class /Script/Engine.StaticMeshComponent')
    beam=actor:AddComponentByClass(cls,false,t,false)
    dot=actor:AddComponentByClass(cls,true,t,false)
    -- Opaque/unlit: contributes depth and rigid-motion velocity, unlike the
    -- old additive debug material which smeared in temporal reconstruction.
    local material=api:find_uobject('Material /Engine/EngineMaterials/GizmoMaterial.GizmoMaterial')
    for _,c in ipairs({beam,dot}) do
        c:SetMobility(2);c:SetCollisionEnabled(0);c:SetGenerateOverlapEvents(false)
        c:SetCastShadow(false);c:SetAbsolute(true,true,true)
        c:SetMaterial(0,material);c:SetHiddenInGame(false,false)
    end
    beam:SetStaticMesh(api:find_uobject('StaticMesh /Engine/BasicShapes/Cube.Cube'))
    dot:SetStaticMesh(api:find_uobject('StaticMesh /Engine/BasicShapes/Sphere.Sphere'))
end
local function hide_crosshair(pc)
    local main=pc.MyHUD and pc.MyHUD.MainUMG
    local hud=main and main.WBP_PlayerInfo
    local panel=hud and hud.Panel_LookingBookName
    local root=panel and panel:GetParent()
    if not root then return end
    for i=0,root:GetChildrenCount()-1 do
        local w=root:GetChildAt(i)
        if w:get_short_name()=='Image_0' then
            if not hidden or hidden.w~=w then hidden={w=w,opacity=w:GetRenderOpacity()} end
            w:SetRenderOpacity(0)
        end
    end
end
local function trace(pawn,start,finish)
    local out={}
    local hit=sys:LineTraceSingle(pawn,start,finish,0,true,{pawn,actor},0,out,true,{R=0,G=1,B=1,A=1},{R=0,G=1,B=0,A=1},0)
    local result=out.result
    local owner=result and result.Component and result.Component:GetOwner()
    if hit and not owner and #break_names>0 then
        local args,outs={result},{}
        for i=2,#break_names do args[i]={};outs[break_names[i]]=args[i] end
        gs:BreakHitResult(table.unpack(args))
        owner=outs.HitActor and outs.HitActor.result
    end
    if hit then
        local p=result.ImpactPoint
        return V(p.x or p.X,p.y or p.Y,p.z or p.Z),owner,hit
    end
    return finish,owner,hit
end
local function place(start,finish)
    local d=sub(finish,start)
    local length=len(d)
    local rot=V(math.deg(math.atan(d.z,math.sqrt(d.x*d.x+d.y*d.y))),math.deg(math.atan(d.y,d.x)),0)
    beam:K2_SetWorldLocationAndRotation(mul(add(start,finish),0.5),rot,false,{},false)
    beam:SetWorldScale3D(V(length/100,0.0035,0.0035))
    dot:K2_SetWorldLocationAndRotation(finish,V(0,0,0),false,{},false)
    dot:SetWorldScale3D(V(0.007,0.007,0.007))
end
local function stabilize_camera(pawn)
    local cam=pawn.FirstPersonCameraComponent
    if not cam or (camera_attachment and camera_attachment.cam==cam) then return end
    local parent=cam:GetAttachParent()
    local relative=cam:GetRelativeTransform()
    local socket=cam:GetAttachSocketName():to_string()
    local world=cam:K2_GetComponentLocation()
    local body=pawn:K2_GetActorLocation()
    local height=world.z-body.z
    if height<30 or height>120 then height=65.3031 end
    camera_attachment={cam=cam,parent=parent,relative=relative,socket=socket,lock_to_hmd=cam.bLockToHmd,height=height}
    -- UEVR applies HMD tracking during stereo rendering. Unreal's own HMD
    -- camera path otherwise resets RelativeLocation to zero every frame.
    cam.bLockToHmd=false
    local anchor=pawn:AddComponentByClass(api:find_uobject('Class /Script/Engine.SceneComponent'),true,transform(),false)
    assert(anchor,'Cannot create stable camera anchor')
    camera_attachment.anchor=anchor
    anchor:K2_AttachToComponent(pawn.RootComponent,'None',0,0,0,false)
    anchor:K2_SetRelativeLocation(V(0,0,height),false,{},true)
    assert(cam:K2_AttachToComponent(anchor,'None',2,1,1,false),'Cannot stabilize the camera attachment')
    -- The game resets the camera's local translation; the stationary parent
    -- carries eye height while UEVR supplies physical headset translation.
    cam:K2_SetRelativeLocation(V(0,0,0),false,{},true)
end
function M.tick(engine,delta)
    local pc,pawn=api:get_player_controller(0),api:get_local_pawn(0)
    if not pc or not pawn then return end
    update_settings(pawn,delta)
    stabilize_camera(pawn)
    if not actor or not UEVR_UObjectHook.exists(actor) then create_visuals(pawn) end
    elapsed=elapsed+delta
    local visible=vr.is_using_controllers() and not pawn.IsPauseGame
    beam:SetHiddenInGame(not visible,false);dot:SetHiddenInGame(not visible,false)
    if not visible then return end
    vr.get_pose(vr.get_hmd_index(),hp,hq)
    vr.get_pose(vr.get_right_controller_index(),rp,rq)
    vr.get_standing_origin(origin);vr.get_rotation_offset(offset)
    local cam=pc.PlayerCameraManager
    local base=cam:GetCameraLocation()
    local rot=pc:GetControlRotation()
    local start=add(base,mul(tracking_to_world(sub(rp,origin),rot.y),100))
    -- get_pose exposes the grip pose in this build, not the aim pose.
    -- UEVR's control rotation already uses the runtime's correct aim pose.
    local calibrated=V(rot.x+settings.aim_pitch_degrees,rot.y+settings.aim_yaw_degrees,0)
    local dir=forward(calibrated)
    local finish,hand_actor,hit=trace(pawn,start,add(start,mul(dir,500)))
    place(start,finish)
    update_title(pc,base,rot.y,finish,delta)
    update_held_label(pc,base,rot.y,start,delta)
    -- Redirect the game's camera-based detector toward the controller ray hit.
    -- Counter-rotate the tracking origin so this does not turn the headset view.
    local target=sub(add(finish,mul(dir,0.15)),base)
    local corrected=V(math.deg(math.atan(target.z,math.sqrt(target.x*target.x+target.y*target.y))),math.deg(math.atan(target.y,target.x)),0)
    local angle=math.rad(corrected.y-rot.y)/2
    local c,s=math.cos(angle),math.sin(angle)
    adjusted_offset.x=c*offset.x+s*offset.z
    adjusted_offset.y=c*offset.y+s*offset.w
    adjusted_offset.z=c*offset.z-s*offset.x
    adjusted_offset.w=c*offset.w-s*offset.y
    vr.set_rotation_offset(adjusted_offset)
    pc:SetControlRotation(corrected)
    if elapsed>=1 then
        elapsed=0;hide_crosshair(pc)
        local camera_hit,camera_actor=trace(pawn,base,add(base,mul(forward(rot),500)))
        last={version=7,settings=settings,held_label=held_state,title_position={x=title_state.x,y=title_state.y},ui_metrics=ui_metrics,ui_follow_view=vr:get_mod_value('UI_FollowView'),visual_material=beam:GetMaterial(0):get_full_name(),beam_width_mm=3.5,camera_stabilized=camera_attachment~=nil,camera_offset=xyz(sub(base,pawn:K2_GetActorLocation())),visible=visible,crosshair_hidden=hidden~=nil,hand=xyz(start),direction=xyz(dir),hit=xyz(finish),camera=xyz(base),control=xyz(rot),corrected=xyz(corrected),native_actor=pawn.ObjectSensorComponent.currentActor and pawn.ObjectSensorComponent.currentActor:get_full_name() or '',hand_actor=hand_actor and hand_actor:get_full_name() or '',camera_actor=camera_actor and camera_actor:get_full_name() or '',has_hit=hit}
        json.dump_file('librarian-pointer-status.json',last,2)
    end
end
function M.cleanup()
    for _,entry in pairs(title_state.widgets) do
        if UEVR_UObjectHook.exists(entry.w) then
            pcall(function() if entry.w:get_full_name()==entry.name then entry.w:SetRenderTranslation({X=entry.x,Y=entry.y}) end end)
        end
    end
    if previous_ui_follow~=nil then vr.set_mod_value('UI_FollowView',tostring(previous_ui_follow)) end
    if camera_attachment and UEVR_UObjectHook.exists(camera_attachment.cam) and UEVR_UObjectHook.exists(camera_attachment.parent) then
        local old=camera_attachment
        old.cam:K2_AttachToComponent(old.parent,old.socket,0,0,0,false)
        old.cam:K2_SetRelativeTransform(old.relative,false,{},true)
        if old.lock_to_hmd~=nil then old.cam.bLockToHmd=old.lock_to_hmd end
    end
    if camera_attachment and camera_attachment.anchor and UEVR_UObjectHook.exists(camera_attachment.anchor) then
        camera_attachment.anchor:K2_DestroyComponent(camera_attachment.cam:GetOwner())
    end
    camera_attachment=nil
    if actor and UEVR_UObjectHook.exists(actor) then actor:K2_DestroyActor() end
    if hidden and UEVR_UObjectHook.exists(hidden.w) then hidden.w:SetRenderOpacity(hidden.opacity) end
    actor,beam,dot,hidden=nil,nil,nil,nil
end
return M
