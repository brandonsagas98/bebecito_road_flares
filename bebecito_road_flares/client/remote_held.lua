-- Distance-culled observer rendering. No remote inventory decision is accepted here.
RoadFlares.RemoteHeld={}
local R=RoadFlares.RemoteHeld
local records={};local running=false;local generation=0
local function now()return GetGameTimer()end
local function removeProp(r)
    RoadFlares.Combustion.remove('remote:'..r.source)
    if r.entity then DeleteEntity(r.entity);r.entity=nil end
end
local function start()
    if running then return end
    running=true;local epoch=generation
    CreateThread(function()
        while generation==epoch and next(records)do
            local candidates={};local p=GetEntityCoords(PlayerPedId())
            for src,r in pairs(records)do
                r.selected=false
                if now()>=r.deadline then removeProp(r);records[src]=nil
                else
                    local index=GetPlayerFromServerId(src)
                    local ped=index~=-1 and GetPlayerPed(index)or 0
                    if ped~=0 and DoesEntityExist(ped)and not IsEntityDead(ped)and now()>=r.visibleAt then
                        local q=GetEntityCoords(ped);r.distance=(p.x-q.x)^2+(p.y-q.y)^2+(p.z-q.z)^2;r.ped=ped
                        local range=(Config.Realism and Config.Realism.GlowDistance)or 120
                        if r.distance<=range*range then candidates[#candidates+1]=r end
                    else removeProp(r)end
                end
            end
            local selected={}
            for i=1,#candidates do
                local r=candidates[i];selected[r]=true;r.selected=true
                local stage=RoadFlares.Realism.stage(r.deadline-r.duration,r.duration,now())
                if (r.entity and not DoesEntityExist(r.entity))or r.stage~=stage or r.attachedPed~=r.ped then removeProp(r)end
                if not r.entity and not r.loading then
                    r.loading=true
                    CreateThread(function()
                        local model=stage==0 and 'bd_road_flare_lit'or('bd_road_flare_lit_'..stage)
                        local hash=joaat(model);RequestModel(hash);local deadline=now()+3000
                        while not HasModelLoaded(hash)and now()<deadline and generation==epoch do Wait(25)end
                        if HasModelLoaded(hash)and generation==epoch and records[r.source]==r and r.selected and DoesEntityExist(r.ped)then
                            local q=GetEntityCoords(r.ped);local e=CreateObjectNoOffset(hash,q.x,q.y,q.z,false,false,false)
                            if e and e~=0 then
                                local h=Config.FlareProp.Hand;local pos,rot=h.Position,h.Rotation
                                SetEntityCollision(e,false,false)
                                AttachEntityToEntity(e,r.ped,GetPedBoneIndex(r.ped,h.Bone),pos.x,RoadFlares.Utils.heldOffsetY(pos.y,stage),pos.z,rot.x,rot.y,rot.z,false,false,false,true,2,true)
                                r.entity=e;r.stage=stage;r.attachedPed=r.ped
                            end
                        end
                        SetModelAsNoLongerNeeded(hash);r.loading=false
                    end)
                elseif r.entity then
                    RoadFlares.Combustion.upsert('remote:'..r.source,r.entity,{tipLength=Config.BurnModels[stage+1].length,burnStage=stage,remote=true,ped=r.ped})
                end
            end
            for _,r in pairs(records)do if not selected[r]then removeProp(r)end end
            Wait(400)
        end
        if generation==epoch then running=false end
    end)
end
function R.upsert(data)
    if type(data)~='table'then return end
    local src=tonumber(data.source)
    if not src or src==GetPlayerServerId(PlayerId())then return end
    local old=records[src]
    if not data.active then
        if old and old.requestId==data.requestId then removeProp(old);records[src]=nil end
        return
    end
    local remaining,duration=tonumber(data.remaining),tonumber(data.duration)
    if not remaining or not duration or remaining<=0 or duration<1000 or duration>3600000 or remaining>duration then return end
    if old and old.requestId~=data.requestId then removeProp(old);old=nil end
    local r=old or{source=src,requestId=data.requestId}
    r.deadline=now()+remaining;r.duration=duration;r.visibleAt=now()+math.max(0,tonumber(data.visibleDelay)or 0)
    records[src]=r;start()
end
function R.clear()
    generation=generation+1;running=false
    for _,r in pairs(records)do removeProp(r)end
    records={}
end
function R.snapshot(list)
    R.clear();for _,data in ipairs(list or{})do R.upsert(data)end
end
RegisterNetEvent('bebecito_road_flares:client:heldUpdated',R.upsert)
