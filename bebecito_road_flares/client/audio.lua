-- Original BD combustion sound. Audio-only NUI never requests mouse/keyboard focus.
RoadFlares=RoadFlares or {}
local A={};RoadFlares.Audio=A
local heldToken,heldEntity;local mix={};local nextAt=0;local sent=false
local browser={state='loading',voices=0};local messages=0
local lastMix,lastSentAt={},0
local function send(sources)
    SendNUIMessage({action='bdFlareMix',sources=sources});messages=messages+1;sent=#sources>0
    lastSentAt=GetGameTimer();lastMix={}
    for i,s in ipairs(sources)do lastMix[i]={id=s.id,gain=s.gain,pan=s.pan}end
end
local function changed(sources)
    if #sources~=#lastMix then return true end
    for i,s in ipairs(sources)do local old=lastMix[i]
        if s.id~=old.id or s.gain~=old.gain or s.pan~=old.pan then return true end
    end
    return false
end
if RegisterNUICallback then RegisterNUICallback('bdAudioStatus',function(data,cb)
    if type(data)=='table' then browser={state=tostring(data.state or 'unknown'):sub(1,24),voices=math.min(8,math.max(0,tonumber(data.voices)or 0)),playedShots=math.max(0,tonumber(data.playedShots)or 0),error=type(data.error)=='string'and data.error:sub(1,160)or nil}end
    cb({ok=true})
end)end
function A.update(records)
    if GetGameTimer()<nextAt then return end
    local t=GetGameTimer()
    nextAt=t+125
    local cfg=Config.FlareAudio or {};local selected={}
    if cfg.Enabled~=false and #records>0 then
        local camera=GetFinalRenderedCamCoord();local rotation=GetFinalRenderedCamRot(2)
        local yaw=math.rad(rotation.z);local rightX,rightY=math.cos(yaw),math.sin(yaw)
        local range=math.min(20,math.max(2,tonumber(cfg.Distance)or 12));local volume=math.min(.5,math.max(0,tonumber(cfg.Volume)or .22))
        local maximum=math.min(4,math.max(0,math.floor(tonumber(cfg.MaximumSources)or 4)))
        for _,r in ipairs(records)do if DoesEntityExist(r.entity)then
            local p=r.frameTip or GetOffsetFromEntityInWorldCoords(r.sceneEntity or r.entity,0.0,0.0,r.tip or .22)
            local dx,dy,dz=p.x-camera.x,p.y-camera.y,p.z-camera.z
            local squared=dx*dx+dy*dy+dz*dz
            if maximum>0 and squared<range*range and (#selected<maximum or squared<selected[#selected].distance^2)then
                local distance=math.sqrt(squared)
                local fade=r.stoppingAt and math.max(0,1-(t-r.stoppingAt)/(r.fadeDuration or 450))or 1
                local item={id=r.key,distance=distance,gain=volume*(1-distance/range)^2*fade,pan=(dx*rightX+dy*rightY)/math.max(1,distance)}
                local index=#selected+1
                while index>1 and selected[index-1].distance>distance do index=index-1 end
                table.insert(selected,index,item)
                if #selected>maximum then selected[#selected]=nil end
            end
        end end
    end
    mix=selected
    -- Preserve exact parameter changes; heartbeat precedes the browser's 1200ms watchdog.
    if (#mix>0 and (t-lastSentAt>=750 or changed(mix)))or(#mix==0 and sent)then send(mix)end
end
function A.remove(key)
    local changed=false
    for i=#mix,1,-1 do if mix[i].id==key then table.remove(mix,i);changed=true end end
    if changed then send(mix)end
end
function A.startHeldFlare(entity,ped,token,valid)
    if not DoesEntityExist(entity)or not DoesEntityExist(ped)or(valid and not valid())then return false,'invalid_audio_context'end
    heldToken=token;heldEntity=entity;return true
end
function A.oneShot(name,point)
    local cfg=Config.FlareAudio or {}
    if cfg.Enabled==false or(name~='strike'and name~='tap')then return end
    local gain=math.min(.3,math.max(0,tonumber(cfg.Volume)or .22));local pan=0.0
    if point then
        local camera=GetFinalRenderedCamCoord();local yaw=math.rad(GetFinalRenderedCamRot(2).z)
        local dx,dy,dz=point.x-camera.x,point.y-camera.y,point.z-camera.z
        local distance=math.sqrt(dx*dx+dy*dy+dz*dz);local range=math.min(20,math.max(2,tonumber(cfg.Distance)or 12))
        gain=gain*math.max(0,1-distance/range)^2;pan=(dx*math.cos(yaw)+dy*math.sin(yaw))/math.max(1,distance)
    end
    if gain>.001 then SendNUIMessage({action='bdFlareShot',name=name,gain=gain,pan=pan})end
end
function A.stopHeldFlare()heldToken=nil;heldEntity=nil;A.remove('held');return true end
function A.clear()return A.stopHeldFlare()end
function A.shutdown()heldToken=nil;heldEntity=nil;mix={};nextAt=0;if sent then send({})end end
function A.isActive()return heldToken~=nil end
function A.getState()return heldToken and 'active'or 'inactive'end
function A.getSoundId()return nil end
function A.getSessionToken()return heldToken end
function A.getDiagnostics()return {selected=#mix,browserState=browser.state,browserVoices=browser.voices,playedShots=browser.playedShots,error=browser.error,messages=messages}end
AddEventHandler('onResourceStop',function(name)if name==GetCurrentResourceName()then A.shutdown()end end)
return A
