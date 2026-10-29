RoadFlares = RoadFlares or {}
RoadFlares.Server = RoadFlares.Server or {}

local Permissions = RoadFlares.Server.Permissions
local Validation = RoadFlares.Server.Validation
local Registry = RoadFlares.Server.Registry
local Lifecycle = RoadFlares.Server.Lifecycle
local constants = RoadFlares.Constants
local Utils = RoadFlares.Utils
local Inventory = RoadFlares.Server.Inventory
local placementInFlight = 0
local placementEntities = {}

local function nowMilliseconds()
    return RoadFlares.Utils.nowMilliseconds()
end

local function toNumber(value)
    local number = tonumber(value)
    if type(number) ~= 'number' or number ~= number then
        return nil
    end
    return number
end

local function toString(value)
    if type(value) ~= 'string' then
        return nil
    end
    if value == '' then
        return nil
    end
    return value
end

local snapshotVersionByPlayer = {}

local function normalizePlayerSource(player)
    if type(player) == 'number' and player > 0 then
        return player
    end
    local source = toNumber(player)
    if source ~= nil and source > 0 then
        return source
    end
    return nil
end

local function getPlayerRoutingBucketNumber(player)
    local source = normalizePlayerSource(player)
    if not source then
        return nil
    end
    return toNumber(GetPlayerRoutingBucket(source))
end

local function notifyResponse(src, requestId, response)
    TriggerClientEvent(constants.Events.Client.PlaceFlareResult, src, response)
    if Config and Config.Debug then
        RoadFlares.Utils.debugPrint(('Server placement response src=%s requestId=%s success=%s reason=%s'):format(
            tostring(src),
            tostring(requestId),
            tostring(response.success),
            tostring(response.reason or 'none')
        ))
    end
end

local function notifyManualExtinguishResponse(src, requestId, response)
    TriggerClientEvent(constants.Events.Client.ManualExtinguishResult, src, response)
    if Config and Config.Debug then
        RoadFlares.Utils.debugPrint(('Server manual extinguish response src=%s requestId=%s success=%s reason=%s'):format(
            tostring(src),
            tostring(requestId),
            tostring(response.success),
            tostring(response.reason or 'none')
        ))
    end
end

local function sendActiveCountUpdated(ownerSource)
    local owner = toNumber(ownerSource)
    if owner == nil then
        return false
    end

    local activeCount = Registry.getActiveCount(owner)
    local maxActive = toNumber(Config.MaxActiveFlaresPerPlayer) or 0

    local player = tonumber(owner)
    if not player or player <= 0 then
        return false
    end
    local ped = GetPlayerPed(player)
    if not ped or ped == 0 then
        return false
    end

    TriggerClientEvent(constants.Events.Client.ActiveCountUpdated, player, {
        activeCount = activeCount,
        maxActive = maxActive
    })

    if Config and Config.Debug then
        RoadFlares.Utils.debugPrint(('Active count updated owner=%s active=%s max=%s'):format(
            tostring(owner),
            tostring(activeCount),
            tostring(maxActive)
        ))
    end
    return true
end

local function respondActivation(src, requestId, requestToken, allowed, reason)
    TriggerClientEvent(constants.Events.Client.AuthorizationResponse, src, {
        requestId = requestId,
        requestToken = requestToken,
        allowed = allowed,
        reason = reason
    })
end

local function modelHashFromConfig(override)
    local modelName = override or (Config and Config.FlareProp and Config.FlareProp.Model) or ''
    if type(modelName) ~= 'string' or modelName == '' then
        return nil
    end
    modelName = modelName:gsub('^%s*(.-)%s*$', '%1')
    if modelName == '' then
        return nil
    end
    if _G.joaat then
        return joaat(modelName)
    end
    return GetHashKey(modelName)
end

local function isValidModel(model)
    return RoadFlares.Utils.isFiniteNumber(model) and model ~= 0
end

local function createFlareObject(model, coords)
    if type(CreateObjectNoOffset) ~= 'function' then
        return 0
    end

    local x = toNumber(coords.x)
    local y = toNumber(coords.y)
    local z = toNumber(coords.z)
    if x == nil or y == nil or z == nil then
        return 0
    end

    local entity = CreateObjectNoOffset(model, x, y, z, true, true, false)
    return entity or 0
end

local function deleteEntityIfNeeded(entity)
    if type(entity) ~= 'number' or entity == 0 then
        return
    end
    if not DoesEntityExist(entity) then
        return
    end
    DeleteEntity(entity)
end

local function cloneVector(values)
    if type(values) ~= 'table' then
        return nil
    end
    local x = toNumber(values.x)
    local y = toNumber(values.y)
    local z = toNumber(values.z)
    if x == nil or y == nil or z == nil then
        return nil
    end
    return {
        x = x,
        y = y,
        z = z
    }
end

local function broadcastFlareRemoved(record, reason)
    if type(record) ~= 'table' then
        return
    end

    local flareId = tostring(record.id)
    if flareId == '' then
        return
    end

    local payload = {
        flareId = flareId,
        netId = toNumber(record.netId),
        coords = record.entityCoords or record.coords,
        rotation = record.rotation,
        burnStage = record.burnStage or 0,
        reason = reason or record.removalReason or 'removed'
    }

    local routingBucket = toNumber(record.routingBucket) or 0
    local players = GetPlayers()
    for _, sourceText in ipairs(players) do
        local sourceId = tonumber(sourceText)
        if sourceId and sourceId > 0 then
            local playerBucket = GetPlayerRoutingBucket(sourceId)
            if toNumber(playerBucket) == routingBucket then
                TriggerClientEvent(constants.Events.Client.FlareRemoved, sourceId, payload)
            end
        end
    end
end

local function broadcastFlareUpdated(record)
    local metadata = Lifecycle.buildReplicatedFlareMetadata(record)
    if not metadata then return end
    for _, player in ipairs(GetPlayers()) do
        local target = tonumber(player)
        if target and GetPlayerRoutingBucket(target) == record.routingBucket then
            TriggerClientEvent(constants.Events.Client.FlareUpdated, target, metadata)
        end
    end
end

Lifecycle.setModelUpdater(function(record,stage)
    if stage<=(record.burnStage or 0)then return false end
    if record.rebinding or not Config.BurnModels or not Config.BurnModels[stage+1] then return false end
    Registry.refreshPhysicalPose(record)
    record.rebinding=true
    local model=Config.BurnModels[stage+1]
    local coords=record.entityCoords or record.coords
    local entity=createFlareObject(modelHashFromConfig(model.name),coords)
    local deadline=nowMilliseconds()+5000
    while entity~=0 and not DoesEntityExist(entity) and nowMilliseconds()<deadline do Wait(0) end
    local netId=entity~=0 and DoesEntityExist(entity) and NetworkGetNetworkIdFromEntity(entity) or 0
    while entity~=0 and DoesEntityExist(entity) and netId<=0 and nowMilliseconds()<deadline do
        Wait(0);netId=NetworkGetNetworkIdFromEntity(entity)
    end
    if netId<=0 or Registry.get(record.id)~=record or record.status~='active' then
        deleteEntityIfNeeded(entity);record.rebinding=nil;return false
    end
    -- Creation may yield; read the live BD pose again immediately before swap.
    Registry.refreshPhysicalPose(record)
    if record.physicsCarrier and SetEntityCoords then
        local current=record.entityCoords or record.coords
        SetEntityCoords(entity,current.x,current.y,current.z,false,false,false,false)
        if GetEntityVelocity and SetEntityVelocity then
            local velocity=GetEntityVelocity(record.entity)
            SetEntityVelocity(entity,velocity.x,velocity.y,velocity.z)
        end
        if GetEntityRotationVelocity and SetEntityAngularVelocity then
            local velocity=GetEntityRotationVelocity(record.entity)
            SetEntityAngularVelocity(entity,velocity.x,velocity.y,velocity.z)
        end
    end
    SetEntityRoutingBucket(entity,record.routingBucket);FreezeEntityPosition(entity,record.physicsCarrier~=true)
    if SetEntityHasGravity then SetEntityHasGravity(entity,record.physicsCarrier==true)end
    if SetEntityOrphanMode then SetEntityOrphanMode(entity,2) end
    if record.rotation and SetEntityRotation then SetEntityRotation(entity,record.rotation.x,record.rotation.y,record.rotation.z,0,true) end
    local old=record.entity
    if not Registry.rebind(record.id,entity,netId) then deleteEntityIfNeeded(entity);record.rebinding=nil;return false end
    record.burnStage=stage;record.tipLength=model.length;record.rebinding=nil
    Entity(entity).state:set('bebecitoRoadFlare',Lifecycle.buildReplicatedFlareMetadata(record),true)
    broadcastFlareUpdated(record)
    deleteEntityIfNeeded(old)
    return true
end)

Lifecycle.setStatePublisher(function(metadata, record)
    if type(metadata) ~= 'table' then
        return false
    end
    if type(record) ~= 'table' then
        return false
    end

    local stateBagValue = Lifecycle.buildReplicatedFlareMetadata(record, {
        status = metadata.status,
        extinguishDurationMilliseconds = metadata.extinguishDurationMilliseconds,
        extinguishStartedAt = metadata.extinguishStartedAt,
        extinguishMode = metadata.extinguishMode,
        manualActorSource = metadata.manualActorSource
    })
    if not stateBagValue then
        return false
    end

    local entity = record.entity
    local entityHandle = Entity(entity)
    if not (entityHandle and entityHandle.state) then
        return false
    end

    local ok = pcall(function()
        entityHandle.state:set('bebecitoRoadFlare', stateBagValue, true)
    end)
    if not ok and Config and Config.Debug then
        RoadFlares.Utils.debugPrint(('Lifecycle state publish failed flareId=%s'):format(tostring(record.id)))
    end
    if ok then broadcastFlareUpdated(record) end
    return ok
end)

Lifecycle.setRemovalNotifier(function(record, reason)
    broadcastFlareRemoved(record, reason or 'removed')
    if type(record) == 'table' then
        sendActiveCountUpdated(record.ownerSource)
    end
end)

local function buildFailureResponse(requestId, reason, activeCount, maxActive)
    local response = {
        requestId = requestId,
        success = false,
        reason = reason
    }
    if activeCount ~= nil then
        response.activeCount = activeCount
    end
    if maxActive ~= nil then
        response.maxActive = maxActive
    end
    return response
end

local function buildSuccessResponse(requestId, record)
    return {
        requestId = requestId,
        success = true,
        flareId = record.id,
        netId = record.netId,
        tipLength = record.tipLength,
        burnStage = record.burnStage,
        activeCount = Registry.getActiveCount(record.ownerSource),
        maxActive = Config.MaxActiveFlaresPerPlayer,
        routingBucket = record.routingBucket,
        reason = 'placed'
    }
end

local function buildManualFailureResponse(requestId, reason)
    return {
        requestId = requestId,
        success = false,
        reason = reason
    }
end

local function buildManualSuccessResponse(requestId, flareId, extinguishDurationMilliseconds)
    return {
        requestId = requestId,
        success = true,
        flareId = flareId,
        extinguishDurationMilliseconds = extinguishDurationMilliseconds,
        reason = 'manual_extinguishing'
}
end

local function scheduleFlareLifecycle(record)
    if type(record) ~= 'table' then
        return false
    end
    if type(Lifecycle.schedule) ~= 'function' then
        return false
    end
    return Lifecycle.schedule(record.id)
end

local function applyServerPlacementCleanup(entity, reason, flareId)
    if type(entity) == 'number' and entity ~= 0 then
        deleteEntityIfNeeded(entity)
    end
    if flareId == nil then
        return
    end
    Registry.remove(flareId, reason or 'placement_cleanup')
end

local function markSuccessState(entity, record, requestId)
    if not record then
        return false
    end
    if not DoesEntityExist(entity) then
        return false
    end

    local bucket = GetPlayerRoutingBucket(record.ownerSource)
    if type(bucket) == 'number' then
        SetEntityRoutingBucket(entity, bucket)
    end

    if SetEntityOrphanMode then
        SetEntityOrphanMode(entity, 2)
    end

    if SetEntityHasGravity then
        SetEntityHasGravity(entity,record.physicsCarrier==true)
    end

    FreezeEntityPosition(entity,record.physicsCarrier~=true)

    local stateBagValue = Lifecycle.buildReplicatedFlareMetadata(record, {
        status = 'active'
    })
    local entityHandle = Entity(entity)
    if not (entityHandle and entityHandle.state) then
        if Config and Config.Debug then
            RoadFlares.Utils.debugPrint(('Entity state bag unavailable for flare id=%s'):format(tostring(record.id)))
        end
        return false
    end

    local setOk = pcall(function()
        entityHandle.state:set('bebecitoRoadFlare', stateBagValue, true)
    end)
    if not setOk then
        if Config and Config.Debug then
            RoadFlares.Utils.debugPrint(('Failed to set entity state bag for flare id=%s'):format(tostring(record.id)))
        end
        return false
    end

    -- Collision is disabled by each observing client in ground_visuals.lua.
    return true
end

local function isRequestWithinDistance(ped, coords)
    local pedCoords = GetEntityCoords(ped)
    if not pedCoords then
        return false
    end
    local dx = pedCoords.x - toNumber(coords.x)
    local dy = pedCoords.y - toNumber(coords.y)
    local dz = pedCoords.z - toNumber(coords.z)
    local distance = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
    local allowed = toNumber(Config.ServerPlacement and Config.ServerPlacement.MaximumPlayerDistance) or 3.0
    return distance <= allowed
end

local function getRecordDistanceFromSource(ped, record)
    Registry.refreshPhysicalPose(record)
    if type(ped) ~= 'number' or ped == 0 or not DoesEntityExist(ped) then
        return nil
    end

    local entity = toNumber(record.entity)
    if entity ~= nil and entity > 0 and DoesEntityExist(entity) then
        local entityCoords = GetEntityCoords(entity)
        if entityCoords then
            local pedCoords = GetEntityCoords(ped)
            local dx = pedCoords.x - entityCoords.x
            local dy = pedCoords.y - entityCoords.y
            local dz = pedCoords.z - entityCoords.z
            return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
        end
    end

    local recordCoords = record.coords
    if type(recordCoords) == 'table' then
        local x = toNumber(recordCoords.x)
        local y = toNumber(recordCoords.y)
        local z = toNumber(recordCoords.z)
        if x ~= nil and y ~= nil and z ~= nil then
            local pedCoords = GetEntityCoords(ped)
            local dx = pedCoords.x - x
            local dy = pedCoords.y - y
            local dz = pedCoords.z - z
            return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
        end
    end

    return nil
end

local function getManualSourceState(src)
    if type(src) ~= 'number' or src <= 0 then
        return false, nil, nil
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false, nil, nil
    end

    return true, ped, GetEntityCoords(ped)
end

local function isManualExtinguishTooFar(src, record)
    local sourceValid, ped = getManualSourceState(src)
    if not sourceValid or not ped then
        return true
    end

    if GetEntityHealth(ped) <= 0 then
        return true
    end

    local sourceDistance = getRecordDistanceFromSource(ped, record)
    if sourceDistance == nil then
        return true
    end

    local limit = toNumber(Config.ManualExtinguish and Config.ManualExtinguish.ServerMaximumDistance) or 3.0
    return sourceDistance > limit
end

local function buildFlareSnapshotForPlayer(src)
    local source = normalizePlayerSource(src)
    if not source then
        return nil
    end

    local bucket = getPlayerRoutingBucketNumber(source)
    if bucket == nil then
        bucket = 0
    end

    local records = {}
    local bucketRecords = Registry.getActiveInBucket(bucket)
    for _, record in ipairs(bucketRecords) do
        if record then
            Registry.refreshPhysicalPose(record)
            local safeStatus = record.status
            local item = {
                flareId = tostring(record.id),
                netId = toNumber(record.netId),
                ownerServerId = toNumber(record.ownerSource),
                coords = cloneVector(record.coords),
                normal = cloneVector(record.normal),
                status = safeStatus,
                routingBucket = bucket,
                createdAt = toNumber(record.createdAt)
            }
            item.tipLength=record.tipLength;item.burnStage=record.burnStage
            item.burnDurationMilliseconds=record.burnDurationMilliseconds
            item.burnRemainingMilliseconds=record.expiresAt and math.max(0,record.expiresAt-nowMilliseconds()) or nil
            if safeStatus == 'automatic_extinguishing' or safeStatus == 'manual_extinguishing' then
                local extinguishDuration = toNumber(record.extinguishDurationMilliseconds)
                local extinguishStartedAt = toNumber(record.extinguishStartedAt)
                local remainingMilliseconds = nil
                if extinguishDuration ~= nil and extinguishStartedAt ~= nil then
                    remainingMilliseconds = extinguishStartedAt + extinguishDuration - nowMilliseconds()
                    if remainingMilliseconds < 0 then
                        remainingMilliseconds = 0
                    end
                end
                if extinguishDuration ~= nil then
                    item.extinguishDurationMilliseconds = extinguishDuration
                end
                if remainingMilliseconds ~= nil then
                    item.extinguishRemainingMilliseconds = remainingMilliseconds
                end
                item.extinguishMode = toNumber(record.extinguishMode) and tostring(record.extinguishMode) or toString(record.extinguishMode)
                item.manualActorSource = toNumber(record.manualActorSource)
            end
            records[#records + 1] = item
        end
    end

    local maxActive = toNumber(Config.MaxActiveFlaresPerPlayer) or 0
    local snapshotVersion = (snapshotVersionByPlayer[source] or 0) + 1
    snapshotVersionByPlayer[source] = snapshotVersion

    return {
        records = records,
        held = RoadFlares.Server.Held and RoadFlares.Server.Held.snapshot(bucket) or {},
        ownedActiveCount = Registry.getActiveCount(source),
        maxActive = maxActive,
        routingBucket = bucket,
        syncVersion = snapshotVersion
    }
end

local function sendFlareSnapshot(src, reason, skipRateLimit)
    local source = normalizePlayerSource(src)
    if not source then
        return false
    end

    if not skipRateLimit and Validation.isSnapshotRateLimited(source) then
        return false
    end

    local payload = buildFlareSnapshotForPlayer(source)
    if not payload then
        return false
    end

    payload.reason = reason or constants.SnapshotReasons.Initial

    TriggerClientEvent(constants.Events.Client.FlareSnapshot, source, payload)

    if Config and Config.Debug then
        RoadFlares.Utils.debugPrint(('Snapshot sent source=%s version=%s bucket=%s records=%d'):format(
            tostring(source),
            tostring(payload.syncVersion),
            tostring(payload.routingBucket),
            #payload.records
        ))
    end

    return true
end

local function finalizePlacementResult(source, requestId, response)
    Validation.completePlacementRequest(source, requestId, response)
    notifyResponse(source, requestId, response)
end

local function resolveManualRecordFailureReason(status)
    if status == 'automatic_extinguishing' or status == 'manual_extinguishing' then
        return 'already_extinguishing'
    end
    return 'not_active'
end

local function buildManualTransitionResponse(requestId, record)
    if type(record) ~= 'table' then
        return nil
    end

    return buildManualSuccessResponse(
        requestId,
        record.id,
        toNumber(record.extinguishDurationMilliseconds) or 4000
    )
end

local function mapLifecycleFailureToManualReason(fallbackReason, record)
    local status = toString(record and record.status)
    if fallbackReason == 'not_found' then
        return 'flare_not_found'
    end
    if fallbackReason == 'invalid_status' then
        return resolveManualRecordFailureReason(status)
    end
    if fallbackReason == 'invalid_duration' or fallbackReason == 'stale_generation' or fallbackReason == 'stale_identifier' then
        return 'manual_extinguish_failed'
    end
    return 'manual_extinguish_failed'
end

local function isActiveStatusForManualExtinguish(status)
    return status == 'active'
end

local function validateManualExtinguishRequestPayload(src, payload)
    if type(src) ~= 'number' or src <= 0 then
        return false, nil, nil, 'invalid_player'
    end

    if type(payload) ~= 'table' then
        return false, nil, nil, 'invalid_request'
    end

    local requestId = Utils.sanitizeRequestId(payload.requestId)
    local flareId = toString(payload.flareId)
    if not flareId then
        flareId = toString(payload.FlareId)
    end
    if not flareId then
        return false, nil, nil, 'invalid_request'
    end

    return true, requestId, flareId, nil
end

RegisterNetEvent(constants.Events.Server.RequestManualExtinguish, function(payload)
    local src = source
    local sourceNumber = normalizePlayerSource(src)
    if not sourceNumber then
        return
    end

    local valid, requestId, flareId, reason = validateManualExtinguishRequestPayload(sourceNumber, payload)
    if not valid then
        if requestId == nil then
            requestId = nil
        end
        notifyManualExtinguishResponse(sourceNumber, requestId, buildManualFailureResponse(
            requestId,
            reason or 'invalid_request'
        ))
        return
    end

    if Config and Config.ManualExtinguish and Config.ManualExtinguish.Enabled == false then
        notifyManualExtinguishResponse(sourceNumber, requestId, buildManualFailureResponse(requestId, 'manual_extinguish_failed'))
        return
    end

    if not Permissions.canUse(sourceNumber) then
        notifyManualExtinguishResponse(sourceNumber, requestId, buildManualFailureResponse(requestId, 'permission_denied'))
        return
    end

    if Validation.isManualExtinguishRateLimited(sourceNumber) then
        notifyManualExtinguishResponse(sourceNumber, requestId, buildManualFailureResponse(requestId, 'rate_limited'))
        return
    end

    local sourceValid, ped = getManualSourceState(sourceNumber)
    if not sourceValid or not ped or GetEntityHealth(ped) <= 0 then
        notifyManualExtinguishResponse(sourceNumber, requestId, buildManualFailureResponse(requestId, 'invalid_player'))
        return
    end

    local record = Registry.get(flareId)
    if not record then
        notifyManualExtinguishResponse(sourceNumber, requestId, buildManualFailureResponse(requestId, 'flare_not_found'))
        return
    end

    local recordStatus = toString(record.status) or 'active'
    if not isActiveStatusForManualExtinguish(recordStatus) then
        notifyManualExtinguishResponse(sourceNumber, requestId, buildManualFailureResponse(requestId, resolveManualRecordFailureReason(recordStatus)))
        return
    end

    local recordBucket = toNumber(record.routingBucket)
    local sourceBucket = getPlayerRoutingBucketNumber(sourceNumber)
    if recordBucket == nil or sourceBucket == nil or recordBucket ~= sourceBucket then
        notifyManualExtinguishResponse(sourceNumber, requestId, buildManualFailureResponse(requestId, 'wrong_bucket'))
        return
    end

    local recordEntity = toNumber(record.entity)
    if recordEntity == nil or recordEntity <= 0 or not DoesEntityExist(recordEntity) then
        notifyManualExtinguishResponse(sourceNumber, requestId, buildManualFailureResponse(requestId, 'flare_not_found'))
        return
    end

    if isManualExtinguishTooFar(sourceNumber, record) then
        notifyManualExtinguishResponse(sourceNumber, requestId, buildManualFailureResponse(requestId, 'too_far'))
        return
    end

    local transitionStarted, transitionResult = Lifecycle.beginManualExtinguish(flareId, sourceNumber)
    if not transitionStarted then
        local mappedReason = mapLifecycleFailureToManualReason(transitionResult, record)
    notifyManualExtinguishResponse(sourceNumber, requestId, buildManualFailureResponse(requestId, mappedReason))
    return
    end

    local response = buildManualTransitionResponse(requestId, transitionResult)
    if not response then
        notifyManualExtinguishResponse(sourceNumber, requestId, buildManualFailureResponse(requestId, 'manual_extinguish_failed'))
        return
    end

    notifyManualExtinguishResponse(sourceNumber, requestId, response)
end)

RegisterNetEvent(constants.Events.Server.RequestActivation, function(payload)
    local src = source
    local valid, requestId, method, requestToken, reason = Validation.validateActivationRequest(src, payload)
    if not valid then
        if requestId then
            respondActivation(src, requestId, requestToken, false, reason)
        end
        return
    end

    if not Permissions.canUse(src) then
        respondActivation(src, requestId, requestToken, false, 'permission_denied')
        return
    end

    if not Permissions.canUseMethod(src, method) then
        respondActivation(src, requestId, requestToken, false, 'method_disabled')
        return
    end

    if Validation.isActivationRateLimited(src) then
        respondActivation(src, requestId, requestToken, false, 'rate_limited')
        return
    end

    local allowed, inventoryReason = Inventory.authorize(src, method)
    if not allowed then
        respondActivation(src, requestId, requestToken, false, inventoryReason)
        return
    end
    respondActivation(src, requestId, requestToken, true, 'allowed')
end)

RegisterNetEvent(constants.Events.Server.RequestFlareSnapshot, function()
    local src = source
    if not normalizePlayerSource(src) then
        return
    end

    sendFlareSnapshot(src, constants.SnapshotReasons.ManualRequest)
end)

AddEventHandler('onPlayerBucketChange', function(player, bucket, oldBucket)
    local source = normalizePlayerSource(player)
    if not source then
        return
    end

    local newBucket = toNumber(bucket)
    local previousBucket = toNumber(oldBucket)
    if newBucket == previousBucket then
        return
    end

    -- The event can run inside SetPlayerRoutingBucket in another resource.
    -- Querying bucket natives synchronously here causes a resource deadlock.
    Citizen.SetTimeout(0, function()
        Inventory.clear(source)
        sendFlareSnapshot(source, constants.SnapshotReasons.BucketChanged, true)
    end)
    if Config and Config.Debug then
        RoadFlares.Utils.debugPrint(('Snapshot sent on bucket change source=%s oldBucket=%s newBucket=%s'):format(
            tostring(source),
            tostring(previousBucket),
            tostring(newBucket)
        ))
    end
end)

RegisterNetEvent(constants.Events.Server.RequestIgnition, function(payload)
    local src = normalizePlayerSource(source)
    local requestId = type(payload)=='table' and Utils.sanitizeRequestId(payload.requestId)
    if not src or not requestId then return end
    local ok, burn = false, 'invalid_player'
    if Permissions.canUse(src) then ok, burn = Inventory.ignite(src, requestId) end
    if ok and RoadFlares.Server.Held then RoadFlares.Server.Held.begin(src,burn) end
    TriggerClientEvent(constants.Events.Client.IgnitionResult, src, {requestId=requestId,allowed=ok,
        remainingMilliseconds=ok and math.max(0,burn.expiresAt-nowMilliseconds()) or nil,
        reason=not ok and burn or nil})
end)

local function placeFlare(src, payload)
    local startedAt = nowMilliseconds()
    local source = normalizePlayerSource(src)
    if not source then
        return
    end
    src = source
    if not Inventory.valid(src) then
        notifyResponse(src, type(payload) == 'table' and payload.requestId, buildFailureResponse(
            type(payload) == 'table' and payload.requestId, 'session_expired'))
        return
    end
    local valid, requestId, selectionId, coords, normal, reason = Validation.validatePlacementRequest(src, payload)
    if not valid then
        if requestId then
            finalizePlacementResult(src, requestId, buildFailureResponse(requestId, reason))
        end
        return
    end

    local isStarted, existing = Validation.beginPlacementRequest(src, requestId)
    if not isStarted then
        if existing then
            if existing.status == 'completed' and existing.response then
                notifyResponse(src, requestId, existing.response)
                return
            end
            if existing.status == 'processing' then
                -- Duplicate arrives while previous request is still in-progress.
                -- Do not complete/overwrite the shared dedupe entry owned by the
                -- original coroutine; its authoritative result remains replayable.
                notifyResponse(src, requestId, buildFailureResponse(requestId, 'duplicate_request_processing'))
                return
            end

            finalizePlacementResult(src, requestId, buildFailureResponse(requestId, 'duplicate_request'))
            return
        end
    end

    local response
    if Config.Realism and Config.Realism.ConsumeOnIgnition and not Inventory.hasLit(src) then
        finalizePlacementResult(src, requestId, buildFailureResponse(requestId, 'flare_not_lit'))
        return
    end
    if Validation.isPlacementRateLimited(src) then
        response = buildFailureResponse(requestId, 'rate_limited')
        finalizePlacementResult(src, requestId, response)
        return
    end

    if not Permissions.canUse(src) then
        response = buildFailureResponse(requestId, 'invalid_player')
        finalizePlacementResult(src, requestId, response)
        return
    end

    local sourceValid, ped, pedCoords = Validation.getPlacementSourceState(src)
    if not sourceValid or not ped then
        response = buildFailureResponse(requestId, 'invalid_player')
        finalizePlacementResult(src, requestId, response)
        return
    end

    local activeCount = Registry.getActiveCount(src)
    local maxActive = toNumber(Config.MaxActiveFlaresPerPlayer) or 0
    if maxActive > 0 and activeCount >= maxActive then
        response = buildFailureResponse(requestId, 'limit_reached')
        response.activeCount = activeCount
        response.maxActive = maxActive
        finalizePlacementResult(src, requestId, response)
        return
    end

    if not isRequestWithinDistance(ped, coords) then
        response = buildFailureResponse(requestId, 'too_far')
        finalizePlacementResult(src, requestId, response)
        return
    end

    local requestBucket = getPlayerRoutingBucketNumber(src)
    if requestBucket == nil then
        response = buildFailureResponse(requestId, 'routing_bucket_changed')
        finalizePlacementResult(src, requestId, response)
        return
    end

    if toNumber(GetPlayerRoutingBucket(src)) ~= requestBucket then
        response = buildFailureResponse(requestId, 'routing_bucket_changed')
        finalizePlacementResult(src, requestId, response)
        return
    end

    local burnInfo=Inventory.getBurn(src)
    local stage=burnInfo and RoadFlares.Realism.stage(burnInfo.ignitedAt,burnInfo.duration,nowMilliseconds()) or 0
    local burnModel=Config.BurnModels and Config.BurnModels[stage+1]
    local model = modelHashFromConfig(burnModel and burnModel.name)
    local physical=Config.GroundPhysics and Config.GroundPhysics.Enabled~=false
    if not model then
        response = buildFailureResponse(requestId, 'invalid_request')
        finalizePlacementResult(src, requestId, response)
        return
    end
    if not isValidModel(model) then
        response = buildFailureResponse(requestId, 'spawn_failed')
        finalizePlacementResult(src, requestId, response)
        return
    end

    local lift=(Config.Realism and Config.Realism.GroundLiftMeters) or 0
    local entityCoords={x=coords.x+normal.x*lift,y=coords.y+normal.y*lift,z=coords.z+normal.z*lift}
    local entity = createFlareObject(model, entityCoords)
    if not entity or entity == 0 then
        response = buildFailureResponse(requestId, 'spawn_failed')
        finalizePlacementResult(src, requestId, response)
        return
    end
    placementEntities[src] = { entity = entity }

    local spawnTimeout = toNumber(Config.ServerPlacement and Config.ServerPlacement.SpawnTimeoutMilliseconds) or 3000
    local targetWaitAt = nowMilliseconds() + spawnTimeout
    while not DoesEntityExist(entity) do
        if nowMilliseconds() >= targetWaitAt then
            deleteEntityIfNeeded(entity)
            response = buildFailureResponse(requestId, 'spawn_failed')
            finalizePlacementResult(src, requestId, response)
            return
        end
        Wait(0)
    end

    if not DoesEntityExist(entity) then
        response = buildFailureResponse(requestId, 'spawn_failed')
        finalizePlacementResult(src, requestId, response)
        return
    end

    local netId
    local netWaitAt = nowMilliseconds() + spawnTimeout
    while true do
        netId = NetworkGetNetworkIdFromEntity(entity)
        if netId and netId > 0 then
            break
        end
        if nowMilliseconds() >= netWaitAt then
            applyServerPlacementCleanup(entity, 'spawn_failed')
            response = buildFailureResponse(requestId, 'spawn_failed')
            finalizePlacementResult(src, requestId, response)
            return
        end
        Wait(0)
    end

    if not netId or netId <= 0 then
        applyServerPlacementCleanup(entity, 'spawn_failed')
        response = buildFailureResponse(requestId, 'spawn_failed')
        finalizePlacementResult(src, requestId, response)
        return
    end

    if toNumber(GetPlayerRoutingBucket(src)) ~= requestBucket then
        applyServerPlacementCleanup(entity, 'routing_bucket_changed')
        response = buildFailureResponse(requestId, 'routing_bucket_changed')
        finalizePlacementResult(src, requestId, response)
        return
    end

    local bucket = GetPlayerRoutingBucket(src)
    if type(bucket) == 'number' then
        SetEntityRoutingBucket(entity, bucket)
    end

    if FreezeEntityPosition then
        FreezeEntityPosition(entity,not physical)
    end

    local rotation
    if RoadFlares.Realism and SetEntityRotation then
        rotation=RoadFlares.Realism.groundRotation(normal,GetEntityHeading and GetEntityHeading(ped) or 0)
        SetEntityRotation(entity,rotation.x,rotation.y,rotation.z,0,true)
    end

    local record = Registry.createRecord(src, entity, netId, coords, normal, bucket, requestId)
    if not record then
        applyServerPlacementCleanup(entity, 'registry_failed')
        response = buildFailureResponse(requestId, 'registry_failed')
        finalizePlacementResult(src, requestId, response)
        return
    end
    if not Registry.add(record) then
        applyServerPlacementCleanup(entity, 'registry_failed')
        response = buildFailureResponse(requestId, 'registry_failed')
        finalizePlacementResult(src, requestId, response)
        return
    end
    placementEntities[src].flareId = record.id
    record.physicsCarrier=physical==true
    record.rotation=rotation;record.entityCoords=entityCoords;record.burnStage=stage
    record.tipLength=burnModel and burnModel.length or .220
    local burn = Inventory.getBurn(src)
    if burn then
        record.ignitedAt = burn.ignitedAt
        record.burnDurationMilliseconds = burn.duration
        record.expiresAt = burn.expiresAt
    end

    if not markSuccessState(entity, record, requestId) then
        applyServerPlacementCleanup(entity, 'state_bag_failed', record.id)
        response = buildFailureResponse(requestId, 'registry_failed')
        finalizePlacementResult(src, requestId, response)
        return
    end

    local scheduled, scheduleError = scheduleFlareLifecycle(record)
    if not scheduled then
        applyServerPlacementCleanup(entity, 'lifecycle_schedule_failed', record.id)
        if Config and Config.Debug then
            RoadFlares.Utils.debugPrint(('Lifecycle schedule failed source=%s flareId=%s reason=%s'):format(
                tostring(src),
                tostring(record.id),
                tostring(scheduleError)
            ))
        end
        response = buildFailureResponse(requestId, 'lifecycle_schedule_failed')
        finalizePlacementResult(src, requestId, response)
        return
    end

    -- Commit the already paid ignition ticket. Legacy mode charges here.
    if not Inventory.valid(src) or not Inventory.consume(src) then
        applyServerPlacementCleanup(entity, 'inventory_rejected', record.id)
        finalizePlacementResult(src, requestId, buildFailureResponse(requestId, 'missing_flare_item'))
        return
    end
    placementEntities[src] = nil
    if RoadFlares.Server.Held then RoadFlares.Server.Held.clear(src) end
    response = buildSuccessResponse(requestId, record)
    response.remainingItems = Inventory.count(src)
    broadcastFlareUpdated(record)
    response.selectionId = selectionId
    response.requestId = requestId

    if Config and Config.Debug then
        RoadFlares.Utils.debugPrint(('Placement placed source=%s flareId=%s netId=%s request=%s elapsed=%sms'):format(
            tostring(src),
            tostring(record.id),
            tostring(netId),
            tostring(requestId),
            tostring(nowMilliseconds() - startedAt)
        ))
    end

    finalizePlacementResult(src, requestId, response)
end

RegisterNetEvent(constants.Events.Server.RequestPlaceFlare, function(payload)
    local src = tonumber(source)
    if not src or src <= 0 or Inventory.locks[src] then return end
    local requestId = type(payload) == 'table' and Utils.sanitizeRequestId(payload.requestId)
    local previous = requestId and Validation.getRecentPlacementRequest(src, requestId)
    if previous and previous.status == 'completed' and previous.response then
        notifyResponse(src, requestId, previous.response)
        return
    end
    local globalLimit = tonumber(Config.MaxActiveFlaresGlobal) or 0
    if globalLimit > 0 and Utils.tableCount(Registry.flaresById) + placementInFlight >= globalLimit then
        local id = type(payload) == 'table' and Utils.sanitizeRequestId(payload.requestId)
        notifyResponse(src, id, buildFailureResponse(id, 'global_limit_reached'))
        return
    end
    Inventory.locks[src] = true
    placementInFlight = placementInFlight + 1
    local ok, failure = pcall(placeFlare, src, payload)
    local pending = placementEntities[src]
    if pending then applyServerPlacementCleanup(pending.entity, 'transaction_cleanup', pending.flareId) end
    placementEntities[src] = nil
    Inventory.locks[src] = nil
    placementInFlight = placementInFlight - 1
    if not ok then
        print('[BD Road Flares] Placement failed safely: '..tostring(failure))
        local id = type(payload) == 'table' and Utils.sanitizeRequestId(payload.requestId)
        if id then finalizePlacementResult(src, id, buildFailureResponse(id, 'spawn_failed')) end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    Inventory.clear(src)
    Validation.clearCooldowns(src)
    local removed = Registry.clearOwner(src, 'player_dropped')
    snapshotVersionByPlayer[src] = nil
    if type(removed) == 'table' then
        for i = 1, #removed do
            broadcastFlareRemoved(removed[i], 'player_dropped')
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    for _, src in ipairs(GetPlayers()) do
        Validation.clearCooldowns(tonumber(src))
        snapshotVersionByPlayer[src] = nil
    end

    Registry.clearAll('resource_stop')
end)

-- Routing buckets have no universal framework change event. Poll inexpensive
-- player bucket IDs; snapshots are sent only when an actual change occurs.
CreateThread(function()
    local known = {}
    while true do
        local present = {}
        for _, text in ipairs(GetPlayers()) do
            local src = tonumber(text)
            local bucket = GetPlayerRoutingBucket(src)
            present[src] = true
            if known[src] ~= nil and known[src] ~= bucket then
                Inventory.clear(src)
                sendFlareSnapshot(src, constants.SnapshotReasons.BucketChanged, true)
            end
            known[src] = bucket
        end
        for src in pairs(known) do if not present[src] then known[src] = nil end end
        Wait(1000)
    end
end)
