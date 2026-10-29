RoadFlares = RoadFlares or {}
RoadFlares.Client = RoadFlares.Client or {}

local Deployment = RoadFlares.Client.Deployment
local Interaction = RoadFlares.Client.Interaction
local WorldFlares = RoadFlares.WorldFlares
local GroundVisuals = RoadFlares.GroundVisuals
local Constants = RoadFlares.Constants
local Utils = RoadFlares.Utils

local commandRegistered = false
local keybindRegistered = false
local keybindPressed = false
local stateBagHandler = nil
local snapshotRequested = false
local resourceGeneration = 0
local bagToFlareId = {}

-- Event-driven cancellation: no polling thread and no extra prompt text.
-- Leave chat/inventory input alone. requestStop also cancels an owned gesture
-- and invalidates its session before a delayed action can finish.
local function cancelHeldFlare()
    if not IsNuiFocused() and Deployment.isActive() then
        Deployment.requestStop('user_cancelled')
    end
end
for _,binding in ipairs({{'x','X'},{'escape','ESCAPE'},{'delete','DELETE'}})do
    local command='bd_roadflare_cancel_'..binding[1]
    RegisterCommand('+'..command,cancelHeldFlare,false)
    RegisterCommand('-'..command,function()end,false)
    RegisterKeyMapping('+'..command,'Roadflares: cancelar','keyboard',binding[2])
end

RegisterNetEvent('bebecito_road_flares:client:useInventory', function()
    Deployment.requestToggle('inventory')
end)

-- OX item has consume=0: the server removes one on ignition.
exports('useFlare', function(data)
    if GetResourceState('ox_inventory') ~= 'started' or type(data) ~= 'table' then return false end
    exports.ox_inventory:useItem(data, function(used)
        if used then Deployment.requestToggle('inventory') end
    end)
    return true
end)

local function toNumber(value)
    return type(value) == 'number' and value or tonumber(value)
end

local function debugPrint(message)
    Utils.debugPrint(message, Constants.ResourceName)
end

local function getLocalBucket()
    return WorldFlares and WorldFlares.getRoutingBucket and WorldFlares.getRoutingBucket() or nil
end

local function normalizeMetadata(value)
    if type(value) ~= 'table' then
        return nil
    end

    local flareId = value.flareId
    if flareId == nil or tostring(flareId) == '' then
        return nil
    end

    local netId = toNumber(value.netId)
    if netId == nil or netId <= 0 then
        return nil
    end

    local createdAt = toNumber(value.createdAt)
    local routingBucket = toNumber(value.routingBucket)
    local ownerSource = toNumber(value.ownerSource)
    local status = value.status
    if status ~= 'active' and status ~= 'automatic_extinguishing' and status ~= 'manual_extinguishing' then
        return nil
    end

    return {
        flareId = tostring(flareId),
        ownerSource = ownerSource,
        ownerServerId = ownerSource,
        coords = Utils.normalizeVector(value.coords),
        normal = Utils.normalizeVector(value.normal),
        status = status,
        createdAt = createdAt,
        routingBucket = routingBucket,
        netId = netId,
        extinguishDurationMilliseconds = toNumber(value.extinguishDurationMilliseconds),
        extinguishRemainingMilliseconds = toNumber(value.extinguishRemainingMilliseconds),
        extinguishStartedAt = toNumber(value.extinguishStartedAt),manualActorSource=toNumber(value.manualActorSource)
        ,tipLength=toNumber(value.tipLength),burnStage=toNumber(value.burnStage)
    }
end

local function resolveStateBagEntity(bagName)
    if type(GetEntityFromStateBagName) ~= 'function' then
        return 0
    end
    if type(bagName) ~= 'string' then
        return 0
    end
    local ok, entity = pcall(GetEntityFromStateBagName, bagName)
    if not ok then
        return 0
    end
    if type(entity) ~= 'number' then
        return 0
    end
    return entity
end

local function extractStateBagValues(args)
    local value = args[3]
    local oldValue = nil
    for index = 4, 6 do
        if type(args[index]) == 'table' then
            oldValue = args[index]
            break
        end
    end
    return value, oldValue
end

local function isMetadataInLocalBucket(metadata)
    local localBucket = getLocalBucket()
    local activeBucket = localBucket
    if WorldFlares and WorldFlares.getRoutingBucket then
        activeBucket = WorldFlares.getRoutingBucket()
    end

    if activeBucket == nil then
        return true
    end
    if metadata.routingBucket == nil then
        return true
    end
    return metadata.routingBucket == activeBucket
end

local function applyStateBagRemoval(identifier, reason)
    if not identifier then
        return
    end
    local flareId = tostring(identifier)
    if WorldFlares and WorldFlares.remove then
        WorldFlares.remove(flareId)
    end
    if GroundVisuals and GroundVisuals.remove then
        GroundVisuals.remove(flareId, reason or 'state_bag_removed')
    end
end

local function onRoadFlareStateChanged(...)
    local args = { ... }
    local bagName = args[1]
    local key = args[2]
    if key ~= 'bebecitoRoadFlare' then
        return
    end

    local value, oldValue = extractStateBagValues(args)
    local stateBagEntity = resolveStateBagEntity(bagName)

    if type(value) == 'table' and (value.status == 'active' or value.status == 'automatic_extinguishing' or value.status == 'manual_extinguishing') then
        local metadata = normalizeMetadata(value)
        if metadata then
            -- State bags indicate entity scope, not permission to create a flare.
            -- Only a server update or complete snapshot can establish that record.
            local known = WorldFlares and WorldFlares.get(metadata.flareId)
            if not known or known.netId ~= metadata.netId then return end
            if isMetadataInLocalBucket(metadata) then
                if stateBagEntity ~= 0 and type(Entity(stateBagEntity)) == 'table' then
                    local entityState = Entity(stateBagEntity).state
                    if entityState then
                        local stateBagValue = entityState.bebecitoRoadFlare
                        if type(stateBagValue) == 'table' and tostring(stateBagValue.flareId or '') ~= tostring(metadata.flareId) then
                            return
                        end
                    end
                end
                if GroundVisuals and GroundVisuals.upsert then
                    GroundVisuals.upsert(known)
                end
                if metadata.flareId then
                    bagToFlareId[tostring(bagName)] = tostring(metadata.flareId)
                end
                if Config and Config.Debug then
                    debugPrint(('State bag active received flareId=%s netId=%s routingBucket=%s'):format(
                        tostring(metadata.flareId),
                        tostring(metadata.netId),
                        tostring(metadata.routingBucket)
                    ))
                end
            elseif Config and Config.Debug then
                debugPrint(('State bag stale rejected flareId=%s worldBucket=%s'):format(
                    tostring(metadata.flareId),
                    tostring((WorldFlares and WorldFlares.getRoutingBucket()) or getLocalBucket())
                ))
            end
        end
        return
    end

    local staleFlareId = nil
    if type(oldValue) == 'table' and oldValue.flareId ~= nil then
        staleFlareId = oldValue.flareId
    end
    if staleFlareId == nil and type(value) == 'table' and value.flareId ~= nil then
        staleFlareId = value.flareId
    end
    if staleFlareId == nil and bagName then
        staleFlareId = bagToFlareId[tostring(bagName)]
    end

    if staleFlareId then
        if Config and Config.Debug then
            debugPrint(('State bag inactive/removed flareId=%s'):format(tostring(staleFlareId)))
        end
        if GroundVisuals and GroundVisuals.remove then
            GroundVisuals.remove(tostring(staleFlareId), 'state_bag_inactive')
        end
    end

    if bagName then
        bagToFlareId[tostring(bagName)] = nil
    end
end

local function registerStateBagHandler()
    if stateBagHandler then
        return
    end
    if AddStateBagChangeHandler then
        local generation = resourceGeneration
        stateBagHandler = AddStateBagChangeHandler('bebecitoRoadFlare', nil, function(...)
            if resourceGeneration ~= generation then
                return
            end
            onRoadFlareStateChanged(...)
        end)
    end
end

local function startGroundRuntime()
    resourceGeneration = resourceGeneration + 1
    registerStateBagHandler()
    if GroundVisuals and GroundVisuals.start then
        GroundVisuals.start()
    end
    if Interaction and Interaction.start then
        Interaction.start()
    end
    if not snapshotRequested then
        snapshotRequested = true
        TriggerServerEvent(Constants.Events.Server.RequestFlareSnapshot, {})
        if Config and Config.Debug then
            debugPrint('Snapshot requested on client start')
        end
    end
end

local function clearGroundRuntime()
    if RoadFlares.RemoteHeld then RoadFlares.RemoteHeld.clear() end
    if RoadFlares.Combustion then RoadFlares.Combustion.clear() end
    resourceGeneration = resourceGeneration + 1
    if stateBagHandler and RemoveStateBagChangeHandler then
        RemoveStateBagChangeHandler(stateBagHandler)
    end
    stateBagHandler = nil
    bagToFlareId = {}
    snapshotRequested = false
    if GroundVisuals and GroundVisuals.clear then
        GroundVisuals.clear('resource_stop')
    end
    if Interaction and Interaction.stop then
        Interaction.stop('resource_stop')
    end
    if WorldFlares and WorldFlares.clear then
        WorldFlares.clear('resource_stop')
    end
    if Deployment and Deployment.requestStop then
        Deployment.requestStop('resource_stop')
    end
end

local function handleFlareSnapshot(payload)
    if type(payload) ~= 'table' then
        return
    end

    local records = payload.records
    local activeCount = payload.ownedActiveCount
    local maxActive = payload.maxActive
    local routingBucket = payload.routingBucket
    local syncVersion = toNumber(payload.syncVersion)

    if syncVersion == nil then
        if Config and Config.Debug then
            debugPrint('Snapshot ignored: missing syncVersion')
        end
        return
    end

    if type(records) ~= 'table' then
        return
    end

    local latestSnapshotVersion = 0
    if WorldFlares and WorldFlares.getLatestSnapshotVersion then
        latestSnapshotVersion = toNumber(WorldFlares.getLatestSnapshotVersion()) or 0
    end
    if syncVersion < latestSnapshotVersion then
        if Config and Config.Debug then
            debugPrint(('Stale snapshot ignored version=%s latest=%s'):format(tostring(syncVersion), tostring(latestSnapshotVersion)))
        end
        return
    end

    local previousBucket = WorldFlares.getRoutingBucket and WorldFlares.getRoutingBucket()
    if RoadFlares.RemoteHeld then RoadFlares.RemoteHeld.snapshot(payload.held) end
    local result
    if WorldFlares and WorldFlares.reconcileSnapshot then
        result = WorldFlares.reconcileSnapshot(records, activeCount, maxActive, routingBucket, syncVersion)
    end

    if result and result.bucketChanged then
        if Deployment and Deployment.handleRoutingBucketChanged then
            Deployment.handleRoutingBucketChanged(result.oldBucket, result.newBucket)
        end
        if GroundVisuals and GroundVisuals.clear then
            GroundVisuals.clear('bucket_changed', previousBucket)
        end
        if Config and Config.Debug then
            debugPrint(('Snapshot bucket changed old=%s new=%s'):format(
                tostring(result.oldBucket),
                tostring(result.newBucket)
            ))
        end
    end

    if GroundVisuals and GroundVisuals.start then
        GroundVisuals.start()
    end
    if Config and Config.Debug then
        local printedVersion = toNumber(WorldFlares and WorldFlares.getLatestSnapshotVersion() or syncVersion) or syncVersion
        debugPrint(('Snapshot received version=%s records=%d reason=%s'):format(
            tostring(printedVersion),
            #records,
            tostring(payload.reason)
        ))
    end
end

local function isValidCommandName(name)
    if type(name) ~= 'string' then
        return false
    end
    local normalized = Utils.trim(name)
    return normalized ~= '' and normalized:match('^[A-Za-z0-9_]+$') ~= nil
end

local function registerActivationCommand()
    if commandRegistered then
        return
    end

    if not Config or not Config.Activation or Config.Activation.Command.Enabled ~= true then
        return
    end

    local commandName = Utils.trim(Config.Activation.Command.Name or '')
    if not isValidCommandName(commandName) then
        if Config.Debug then
            Utils.debugPrint('Invalid activation command name, command registration skipped.')
        end
        return
    end

    RegisterCommand(commandName, function()
        if Deployment and Deployment.requestToggle then
            Deployment.requestToggle('command')
        end
    end, false)

    commandRegistered = true
end

local function registerActivationKeybind()
    if keybindRegistered then
        return
    end

    if not Config or not Config.Activation or Config.Activation.Keybind.Enabled ~= true then
        return
    end

    RegisterCommand(Constants.Commands.InternalActivationToggle, function()
        if keybindPressed then
            if Config and Config.Debug then
                Utils.debugPrint('Keybind press ignored (already held).')
            end
            return
        end

        keybindPressed = true
        if Deployment and Deployment.requestToggle then
            Deployment.requestToggle('keybind')
        end
    end, false)

    RegisterCommand(Constants.Commands.InternalActivationToggleRelease, function()
        keybindPressed = false
        if Config and Config.Debug then
            Utils.debugPrint('Keybind released.')
        end
    end, false)

    local description = Utils.localize('keybind_description')
    if description == 'keybind_description' then
        description = Config.Activation.Keybind.Description or 'Toggle flare deployment mode'
    end

    RegisterKeyMapping(
        Constants.Commands.InternalActivationToggle,
        description,
        'keyboard',
        Config.Activation.Keybind.DefaultKey or 'F6'
    )

    keybindRegistered = true
end

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    registerActivationCommand()
    registerActivationKeybind()
    startGroundRuntime()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    clearGroundRuntime()
end)

RegisterNetEvent(Constants.Events.Client.FlareSnapshot, function(payload)
    handleFlareSnapshot(payload)
end)

RegisterNetEvent(Constants.Events.Client.FlareUpdated, function(payload)
    local metadata = normalizeMetadata(payload)
    if not metadata or not isMetadataInLocalBucket(metadata) then return end
    if WorldFlares.upsert(metadata) then GroundVisuals.upsert(metadata) end
end)

RegisterNetEvent(Constants.Events.Client.FlareRemoved, function(payload)
    if not payload or type(payload) ~= 'table' then
        return
    end

    local flareId = payload.flareId or payload.flare_id or payload.id
    if flareId ~= nil then
        if RoadFlares.Combustion and RoadFlares.Combustion.spawnSpent then RoadFlares.Combustion.spawnSpent(payload) end
        applyStateBagRemoval(flareId, payload.reason or 'flare_removed')
    end
    if Config and Config.Debug and payload.reason then
        debugPrint(('Flare removed from server reason=%s flareId=%s'):format(
            tostring(payload.reason),
            tostring(flareId)
        ))
    end
end)

RegisterNetEvent(Constants.Events.Client.ManualExtinguishResult, function(payload)
    if Interaction and Interaction.handleManualExtinguishResult then
        Interaction.handleManualExtinguishResult(payload)
    end
end)

RegisterNetEvent(Constants.Events.Client.ActiveCountUpdated, function(payload)
    if not payload or type(payload) ~= 'table' then
        return
    end

    if WorldFlares and WorldFlares.setOwnedActiveCount then
        WorldFlares.setOwnedActiveCount(payload.activeCount)
    end
end)

exports('GetClientState', function()
    if Deployment and Deployment.getState then
        return Deployment.getState()
    end
    return nil
end)

exports('IsDeploymentActive', function()
    if Deployment and Deployment.isActive then
        return Deployment.isActive()
    end
    return false
end)

exports('GetDiagnostics', function()
    return { state = Deployment.getState(), bucket = WorldFlares.getRoutingBucket(),
        luaMemoryKiB=collectgarbage('count'),
        placing = RoadFlares.Placing and RoadFlares.Placing.getState(),
        worldRecords = WorldFlares.getActiveCount(), ground = GroundVisuals.getDiagnostics(),
        traffic=RoadFlares.TrafficLite and RoadFlares.TrafficLite.getDiagnostics(),
        interaction=Interaction and Interaction.getDiagnostics and Interaction.getDiagnostics(),
          nativeRoutes=RoadFlares.NativeRoutes and RoadFlares.NativeRoutes.getDiagnostics(),
        audio=RoadFlares.Audio and RoadFlares.Audio.getDiagnostics and RoadFlares.Audio.getDiagnostics(),
        combustion=RoadFlares.Combustion and RoadFlares.Combustion.getDiagnostics() }
end)

