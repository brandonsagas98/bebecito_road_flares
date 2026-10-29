-- Embedded BD collision only. No proxy, substitute model or persistent worker.
RoadFlares=RoadFlares or {}
local P={};RoadFlares.GroundPhysics=P
local entries={}
local models={}
for _,model in ipairs(Config.BurnModels or{})do models[joaat(model.name)]=true end
function P.release(id)entries[tostring(id)]=nil end
local function clear()entries={}end
function P.resolve(runtime,entity)
    local cfg=Config.GroundPhysics
    if not cfg or cfg.Enabled~=true then return entity end
    if not models[GetEntityModel(entity)]then return entity end
    runtime.physicsCarrier=true
    local id=tostring(runtime.flareId);local r=entries[id]
    if not r or r.entity~=entity then r={entity=entity};entries[id]=r;SetEntityCollision(entity,true,true)end
    local control=NetworkHasControlOfEntity(entity);local owner=control==true or control==1
    if owner and not r.owner then
        SetEntityDynamic(entity,true);SetEntityHasGravity(entity,true)
        FreezeEntityPosition(entity,runtime.extinguishing==true)
        SetObjectPhysicsParams(entity,math.max(.1,math.min(.5,tonumber(cfg.Mass)or .2)),1.0,.1,.1,0.0,.1,.1,0.0,.02,4.0,1.0)
        ActivatePhysics(entity)
    end
    r.owner=owner
    if runtime.extinguishing and not r.stopping and owner then FreezeEntityPosition(entity,true);r.stopping=true end
    return entity
end
RoadFlares.WorldFlares.subscribe(function(event,payload)
    if event=='remove'then P.release(payload.flareId)
    elseif event=='clear'then clear()
    elseif event=='snapshot'and payload.applied~=false then
        local keep={};for _,record in ipairs(RoadFlares.WorldFlares.getAll())do keep[tostring(record.flareId)]=true end
        for id in pairs(entries)do if not keep[id]then entries[id]=nil end end
    end
end)
AddEventHandler('onResourceStop',function(name)if name==GetCurrentResourceName()then clear()end end)
