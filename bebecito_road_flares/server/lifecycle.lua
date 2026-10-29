RoadFlares = RoadFlares or {}
RoadFlares.Server = RoadFlares.Server or {}
RoadFlares.Server.Lifecycle = RoadFlares.Server.Lifecycle or {}

local Lifecycle = RoadFlares.Server.Lifecycle
local Registry = RoadFlares.Server.Registry
local Utils = RoadFlares.Utils

local statePublisher = nil
local removalNotifier = nil
local modelUpdater
function Lifecycle.setModelUpdater(fn) modelUpdater=fn end

local function debugPrint(message)
    if Config and Config.Debug then
        Utils.debugPrint(message, (Config.ResourceName or RoadFlares.Constants.ResourceName) or 'BebecitoRoadFlares')
    end
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
    local text = Utils.trim(value)
    if text == '' then
        return nil
    end
    return text
end

local function nowMilliseconds()
    return Utils.nowMilliseconds()
end

local function clampPositiveInteger(value, fallback, minimum, maximum)
    local number = toNumber(value)
    if number == nil then
        return fallback
    end
    if number < minimum then
        number = minimum
    end
    if maximum ~= nil and number > maximum then
        number = maximum
    end
    return number
end

local function getConfigNumber(value, fallback, minimum, maximum)
    local valueNumber = toNumber(value)
    if valueNumber == nil or valueNumber <= 0 then
        if Config and Config.Debug then
            Utils.debugPrint('[lifecycle-config] invalid numeric value, using fallback')
        end
        return fallback
    end
    return clampPositiveInteger(valueNumber, fallback, minimum, maximum)
end

local function getLifecycleDurationMilliseconds()
    return getConfigNumber(Config and Config.FlareDurationMinutes, 15, 1, 1000000) * 60 * 1000
end

local function getAutomaticExtinguishDurationMilliseconds()
    return getConfigNumber(
        Config and Config.Lifecycle and Config.Lifecycle.AutomaticExtinguishDurationMilliseconds,
        3500,
        1,
        30000
    )
end

local function getManualExtinguishDurationMilliseconds()
    return getConfigNumber(
        Config and Config.ManualExtinguish and Config.ManualExtinguish.ExtinguishDurationMilliseconds,
        4000,
        1,
        30000
    )
end

function Lifecycle.buildReplicatedFlareMetadata(record, extra)
    Registry.refreshPhysicalPose(record)
    if type(record) ~= 'table' then
        return nil
    end

    local base = {
        flareId = tostring(record.id),
        ownerSource = toNumber(record.ownerSource),
        status = record.status or 'active',
        createdAt = toNumber(record.createdAt),
        routingBucket = toNumber(record.routingBucket),
        netId = toNumber(record.netId),
        coords = record.coords,
        normal = record.normal
    }
    base.tipLength=record.tipLength
    base.burnStage=record.burnStage
    base.burnDurationMilliseconds=record.burnDurationMilliseconds
    base.burnRemainingMilliseconds=record.expiresAt and math.max(0,record.expiresAt-nowMilliseconds()) or nil
    if not base.flareId or base.ownerSource == nil then
        return nil
    end

    if extra == nil then
        extra = {}
    end
    if extra.status ~= nil then
        base.status = extra.status
    end

    local extinguishDuration = toNumber(extra.extinguishDurationMilliseconds)
    if extinguishDuration == nil then
        extinguishDuration = toNumber(record.extinguishDurationMilliseconds)
    end
    if extinguishDuration ~= nil then
        base.extinguishDurationMilliseconds = extinguishDuration
    end

    local extinguishStartedAt = toNumber(extra.extinguishStartedAt)
    if extinguishStartedAt == nil then
        extinguishStartedAt = toNumber(record.extinguishStartedAt)
    end
    if extinguishStartedAt ~= nil then
        base.extinguishStartedAt = extinguishStartedAt
        if extinguishDuration ~= nil then
            base.extinguishRemainingMilliseconds = math.max(0, extinguishStartedAt + extinguishDuration - nowMilliseconds())
        end
    end

    local extinguishMode = toString(extra.extinguishMode)
    if extinguishMode == nil then
        extinguishMode = toNumber(extra.extinguishMode)
    end
    if extinguishMode == nil then
        extinguishMode = toString(record.extinguishMode)
    end
    if extinguishMode ~= nil then
        base.extinguishMode = extinguishMode
    end

    local manualActorSource = toNumber(extra.manualActorSource)
    if manualActorSource == nil then
        manualActorSource = toNumber(record.manualActorSource)
    end
    if manualActorSource ~= nil then
        base.manualActorSource = manualActorSource
    end

    return base
end

local function publishState(record)
    if type(statePublisher) ~= 'function' then
        return false
    end

    local metadata = Lifecycle.buildReplicatedFlareMetadata(record)
    if not metadata then
        return false
    end

    local ok, published = pcall(statePublisher, metadata, record)
    if not ok and Config and Config.Debug then
        debugPrint(('Lifecycle publishState failed for flareId=%s'):format(tostring(record and record.id)))
        if published then
            Utils.debugPrint(tostring(published))
        end
    end
    return ok
end

function Lifecycle.setStatePublisher(publisher)
    if type(publisher) == 'function' then
        statePublisher = publisher
        return true
    end
    statePublisher = nil
    return false
end

function Lifecycle.setRemovalNotifier(notifier)
    if type(notifier) == 'function' then
        removalNotifier = notifier
        return true
    end
    removalNotifier = nil
    return false
end

function Lifecycle.schedule(flareId)
    local record = Registry.get(flareId)
    if not record then
        return false, 'not_found'
    end
    local flareIdValue = tostring(record.id)
    if record.status ~= 'active' then
        return false, 'invalid_status'
    end

    local durationMilliseconds = record.expiresAt and (record.expiresAt - nowMilliseconds()) or getLifecycleDurationMilliseconds()
    if durationMilliseconds == nil or durationMilliseconds <= 0 then
        return false, 'invalid_duration'
    end

    local creationTime = nowMilliseconds()
    local expiresAt = creationTime + durationMilliseconds
    record.expiresAt = expiresAt
    record.lifecycleGeneration = toNumber(record.lifecycleGeneration) or 1

    if Config and Config.Debug then
        debugPrint(('Lifecycle scheduled flareId=%s expiresAt=%s generation=%s durationMs=%s'):format(
            flareIdValue,
            tostring(expiresAt),
            tostring(record.lifecycleGeneration),
            tostring(durationMilliseconds)
        ))
    end

    local expectedGeneration = record.lifecycleGeneration
    if modelUpdater and record.ignitedAt and record.burnDurationMilliseconds then
        for stage=1,3 do
            local delay=record.ignitedAt+record.burnDurationMilliseconds*stage/4-creationTime
            if delay>0 then
                local nextStage=stage
                Citizen.SetTimeout(math.floor(delay),function()
                    local current=Registry.get(flareIdValue)
                    if current==record and current.status=='active' and current.lifecycleGeneration==expectedGeneration then
                        modelUpdater(current,nextStage)
                    end
                end)
            end
        end
    end
    Citizen.SetTimeout(durationMilliseconds, function()
        Lifecycle.beginAutomaticExtinguish(flareIdValue, expectedGeneration)
    end)
    return true
end

local function beginExtinguish(flareId, expectedStatus, targetStatus, extinguishMode, extinguishDurationMilliseconds, actorSource)
    local record = Registry.get(flareId)
    if not record then
        return false, 'not_found'
    end
    if toString(expectedStatus) then
        if record.status ~= expectedStatus then
            return false, 'invalid_status'
        end
    end

    local duration = toNumber(extinguishDurationMilliseconds)
    if duration == nil or duration <= 0 then
        return false, 'invalid_duration'
    end

    local nextGeneration = (record.lifecycleGeneration or 0) + 1
    local updated, err = Registry.updateStatus(
        flareId,
        expectedStatus,
        targetStatus,
        {
            lifecycleGeneration = nextGeneration,
            extinguishStartedAt = nowMilliseconds(),
            extinguishDurationMilliseconds = duration,
            extinguishMode = extinguishMode,
            manualActorSource = actorSource
        }
    )
    if not updated then
        if Config and Config.Debug then
            debugPrint(('Lifecycle status transition failed flareId=%s reason=%s'):format(tostring(flareId), tostring(err)))
        end
        return false, err
    end

    local startedGeneration = toNumber(updated.lifecycleGeneration) or nextGeneration
    publishState(updated)

    Citizen.SetTimeout(duration, function()
        if targetStatus == 'automatic_extinguishing' then
            Lifecycle.removeExpired(flareId, startedGeneration, targetStatus, 'automatic_expired')
        else
            Lifecycle.removeExpired(flareId, startedGeneration, targetStatus, 'manual_extinguished')
        end
    end)

    return true, updated
end

function Lifecycle.beginAutomaticExtinguish(flareId, expectedGeneration)
    local record = Registry.get(flareId)
    if not record then
        return false, 'not_found'
    end
    if expectedGeneration ~= nil and record.lifecycleGeneration ~= expectedGeneration then
        if Config and Config.Debug then
            debugPrint(('Stale automatic callback ignored (generation): flareId=%s'):format(tostring(flareId)))
        end
        return false, 'stale_generation'
    end
    if tostring(record.id) ~= tostring(flareId) then
        return false, 'stale_identifier'
    end

    local extinguishDurationMilliseconds = getAutomaticExtinguishDurationMilliseconds()
    return beginExtinguish(
        flareId,
        'active',
        'automatic_extinguishing',
        'automatic',
        extinguishDurationMilliseconds
    )
end

function Lifecycle.beginManualExtinguish(flareId, actorSource)
    local record = Registry.get(flareId)
    if not record then
        return false, 'not_found'
    end

    local extinguishDurationMilliseconds = getManualExtinguishDurationMilliseconds()
    return beginExtinguish(
        flareId,
        'active',
        'manual_extinguishing',
        'manual',
        extinguishDurationMilliseconds,
        actorSource
    )
end

function Lifecycle.removeExpired(flareId, expectedGeneration, expectedStatus, reason)
    local record = Registry.get(flareId)
    if not record then
        if Config and Config.Debug then
            debugPrint(('Stale lifecycle callback ignored (removed): flareId=%s'):format(tostring(flareId)))
        end
        return false, 'not_found'
    end
    if tostring(record.id) ~= tostring(flareId) then
        return false, 'stale_identifier'
    end
    if expectedGeneration ~= nil and record.lifecycleGeneration ~= expectedGeneration then
        if Config and Config.Debug then
            debugPrint(('Stale lifecycle callback ignored (generation): flareId=%s'):format(tostring(flareId)))
        end
        return false, 'stale_generation'
    end

    local targetStatus = expectedStatus or 'automatic_extinguishing'
    if record.status ~= targetStatus then
        if Config and Config.Debug then
            debugPrint(('Stale lifecycle callback ignored (status=%s): flareId=%s'):format(tostring(record.status), tostring(flareId)))
        end
        return false, 'invalid_status'
    end

    local removalReason = reason or (targetStatus == 'manual_extinguishing' and 'manual_extinguished' or 'automatic_expired')
    local removed = Registry.remove(flareId, removalReason)
    if not removed then
        return false, 'remove_failed'
    end

    if Config and Config.Debug then
        debugPrint(('Lifecycle removal completed flareId=%s reason=%s'):format(tostring(flareId), tostring(removalReason)))
    end

    if type(removalNotifier) == 'function' then
        pcall(function()
            removalNotifier(removed, removalReason)
        end)
    end

    return true, removed
end

function Lifecycle.invalidate(flareId, reason)
    local record = Registry.get(flareId)
    if not record then
        return false, 'not_found'
    end

    record.lifecycleGeneration = (toNumber(record.lifecycleGeneration) or 0) + 1
    record.lifecycleInvalidationReason = reason or 'invalidated'
    return true
end

function Lifecycle.clear(reason)
    if reason == nil then
        reason = 'clear'
    end
    if Config and Config.Debug then
        debugPrint(('Lifecycle clear requested reason=%s'):format(tostring(reason)))
    end
    return true
end

return Lifecycle
