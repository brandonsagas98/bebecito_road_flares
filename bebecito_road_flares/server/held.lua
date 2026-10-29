-- Authoritative announcements; observer clients build local attached props.
RoadFlares.Server.Held={}
local H=RoadFlares.Server.Held
local records={};local running=false
local event='bebecito_road_flares:client:heldUpdated'
local function now()return RoadFlares.Utils.nowMilliseconds()end
local function payload(r)
    return {source=r.source,requestId=r.requestId,routingBucket=r.bucket,
        duration=r.duration,remaining=math.max(0,r.expiresAt-now()),
        visibleDelay=math.max(0,r.visibleAt-now()),active=true}
end
local function broadcast(r,data)
    for _,player in ipairs(GetPlayers())do
        local target=tonumber(player)
        if target and target~=r.source and GetPlayerRoutingBucket(target)==r.bucket then TriggerClientEvent(event,target,data)end
    end
end
function H.clear(src,requestId)
    local r=records[src]
    if not r or(requestId and r.requestId~=requestId)then return false end
    records[src]=nil;broadcast(r,{source=src,requestId=r.requestId,active=false});return true
end
function H.begin(src,burn)
    if records[src]and records[src].requestId==burn.requestId then return end
    H.clear(src)
    local r={source=src,requestId=burn.requestId,bucket=GetPlayerRoutingBucket(src),
        duration=burn.duration,expiresAt=burn.expiresAt,visibleAt=now()+1800}
    records[src]=r;broadcast(r,payload(r))
    if running then return end
    running=true
    CreateThread(function()
        while next(records)do
            for sourceId in pairs(records)do
                if not RoadFlares.Server.Inventory.hasLit(sourceId)then H.clear(sourceId)end
            end
            Wait(1000)
        end
        running=false
    end)
end
function H.snapshot(bucket)
    local list={}
    for src,r in pairs(records)do
        if r.bucket==bucket and RoadFlares.Server.Inventory.hasLit(src)then list[#list+1]=payload(r)end
    end
    return list
end
RegisterNetEvent('bebecito_road_flares:server:discardIgnition',function(data)
    local src=tonumber(source)
    if src and type(data)=='table'and type(data.requestId)=='string'and H.clear(src,data.requestId)then
        RoadFlares.Server.Inventory.clear(src)
    end
end)
AddEventHandler('playerDropped',function()H.clear(tonumber(source))end)
