RoadFlares = RoadFlares or {}
RoadFlares.Server = RoadFlares.Server or {}
local Inventory = { sessions = {}, locks = {} }
RoadFlares.Server.Inventory = Inventory
local adapter, esxRegistered
local function cfg() return Config.Inventory or {} end
local function item() return cfg().ItemName or 'bd_road_flare' end
local function started(name) return GetResourceState(name) == 'started' end
local function provider()
    local selected = cfg().Provider or 'auto'
    if selected ~= 'auto' then return selected end
    if started('ox_inventory') then return 'ox' end
    if started('qb-inventory') and started('qb-core') then return 'qb' end
    if started('es_extended') then return 'esx' end
    return 'unavailable'
end
local function esxPlayer(src)
    if not started('es_extended') then return end
    return exports.es_extended:getSharedObject().GetPlayerFromId(src)
end
function Inventory.getProvider() return provider() end
function Inventory.count(src)
    local mode = provider()
    local ok, value = pcall(function()
        if mode == 'none' then return 1 end
        if mode == 'ox' then return exports.ox_inventory:GetItemCount(src, item()) end
        if mode == 'qb' then
            local player = exports['qb-core']:GetCoreObject().Functions.GetPlayer(src)
            local count = 0
            for _, entry in pairs(player and player.PlayerData.items or {}) do
                if entry.name == item() then count = count + (tonumber(entry.amount) or 0) end
            end
            return count
        end
        if mode == 'esx' then
            local player = esxPlayer(src)
            return player and player.getInventoryItem(item()).count or 0
        end
        if mode == 'custom' and adapter then return adapter.count(src, item()) end
        return 0
    end)
    if not ok or not RoadFlares.Utils.isFiniteNumber(value) then return 0 end
    return math.max(0, math.floor(value))
end
local function removeOne(src)
    if Inventory.count(src) < 1 then return false end
    local mode = provider()
    local ok, removed = pcall(function()
        if mode == 'none' then return true end
        if mode == 'ox' then return exports.ox_inventory:RemoveItem(src, item(), 1) == true end
        if mode == 'qb' then return exports['qb-inventory']:RemoveItem(src, item(), 1, false, 'bd-road-flare') == true end
        if mode == 'esx' then
            local player = esxPlayer(src)
            if not player then return false end
            local before = player.getInventoryItem(item()).count
            if before < 1 then return false end
            player.removeInventoryItem(item(), 1)
            return player.getInventoryItem(item()).count == before - 1
        end
        if mode == 'custom' and adapter then return adapter.remove(src, item(), 1) == true end
        return false
    end)
    return ok and removed == true
end
function Inventory.authorize(src, method)
    local ped = GetPlayerPed(src)
    if ped == 0 or not DoesEntityExist(ped) or GetEntityHealth(ped) <= 0 then return false, 'invalid_player' end
    if provider() == 'unavailable' or provider() == 'custom' and not adapter then return false, 'inventory_unavailable' end
    if Inventory.count(src) < 1 then return false, 'missing_flare_item' end
    Inventory.sessions[src] = { ped = ped, bucket = GetPlayerRoutingBucket(src), method = method,
        expires = RoadFlares.Utils.nowMilliseconds() + (cfg().SessionMilliseconds or 300000) }
    return true
end
function Inventory.valid(src)
    local session = Inventory.sessions[src]
    return session and RoadFlares.Utils.nowMilliseconds() < session.expires
        and GetPlayerPed(src) == session.ped and DoesEntityExist(session.ped)
        and GetEntityHealth(session.ped) > 0 and GetPlayerRoutingBucket(src) == session.bucket
        and RoadFlares.Utils.isActivationMethodEnabled(session.method)
end
function Inventory.clear(src) Inventory.sessions[src] = nil end

local function realistic() return Config.Realism and Config.Realism.ConsumeOnIgnition == true end
function Inventory.hasLit(src)
    local session = Inventory.sessions[src]
    return Inventory.valid(src) and session.burn and session.burn.expiresAt > RoadFlares.Utils.nowMilliseconds()
end
function Inventory.ignite(src, requestId)
    if not Inventory.valid(src) then return false, 'session_expired' end
    local session = Inventory.sessions[src]
    if not session.burn and session.lastIgnitionRequestId == requestId then return false, 'ignition_consumed' end
    if session.burn then
        if session.burn.requestId == requestId and Inventory.hasLit(src) then return true, session.burn end
        return false, 'already_ignited'
    end
    if Inventory.locks[src] then return false, 'busy' end
    if realistic() and not removeOne(src) then return false, 'missing_flare_item' end
    local now = RoadFlares.Utils.nowMilliseconds()
    local duration = math.max(1000, math.min(3600000, (tonumber(Config.FlareDurationMinutes) or 15) * 60000))
    session.burn = { requestId=requestId, ignitedAt=now, expiresAt=now+duration, duration=duration }
    session.lastIgnitionRequestId = requestId
    session.expires = now + duration + 5000
    return true, session.burn
end
function Inventory.getBurn(src)
    return Inventory.hasLit(src) and Inventory.sessions[src].burn or nil
end
function Inventory.consume(src)
    if not realistic() then return removeOne(src) end
    if not Inventory.hasLit(src) then return false end
    Inventory.sessions[src].burn = nil
    return true
end

-- Local server export, never a client event. Custom providers must implement
-- synchronous, authoritative count/remove operations; do not remove in the UI.
exports('RegisterInventoryAdapter', function(value)
    if type(value) ~= 'table' or type(value.count) ~= 'function' or type(value.remove) ~= 'function' then return false end
    if cfg().Provider ~= 'custom' then return false end
    adapter = value
    return true
end)
exports('GetInventoryProvider', Inventory.getProvider)
local function activate(src)
    if type(src) ~= 'number' or src <= 0 or Inventory.count(src) < 1 then return end
    TriggerClientEvent('bebecito_road_flares:client:useInventory', src)
end
local function registerUsable()
    local mode = provider()
    if mode == 'esx' and started('es_extended') and esxRegistered ~= mode then
        exports.es_extended:getSharedObject().RegisterUsableItem(item(), activate)
        esxRegistered = 'esx'
    elseif mode == 'qb' and started('qb-core') and started('qb-inventory') and esxRegistered ~= mode then
        exports['qb-core']:GetCoreObject().Functions.CreateUseableItem(item(), activate)
        esxRegistered = 'qb'
    end
end
AddEventHandler('onResourceStart', function(name)
    if name == GetCurrentResourceName() or name == 'es_extended' or name == 'qb-core' or name == 'qb-inventory' or name == 'ox_inventory' then registerUsable() end
end)
AddEventHandler('onResourceStop', function(name)
    if name == 'es_extended' or name == 'qb-core' then esxRegistered = nil end
    -- Re-evaluate auto after a provider stops; OX callbacks come from its item export.
    if name == 'ox_inventory' or name == 'qb-inventory' or name == 'qb-core' or name == 'es_extended' then
        registerUsable()
    end
end)
