RoadFlares = RoadFlares or {}
RoadFlares.Client = RoadFlares.Client or {}

local WorldFlares = {}
RoadFlares.WorldFlares = WorldFlares

local recordsById = {}
local recordsByNetId = {}
local ownedActiveCount = nil
local currentRoutingBucket = nil
local latestSnapshotVersion = 0
local subscriptions = {}
local nextSubscriptionId = 1

local function toNumber(value)
    local number = tonumber(value)
    if type(number) ~= 'number' or number ~= number then
        return nil
    end
    return number
end

local function sanitizeVector(values)
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

local function sanitizeRecord(record)
    if type(record) ~= 'table' then
        return nil
    end

    local flareId = record.flareId
    local netId = toNumber(record.netId)
    local ownerServerId = toNumber(record.ownerServerId)
    local status = record.status

    if flareId == nil or flareId == '' then
        return nil
    end
    if netId == nil or netId <= 0 then
        return nil
    end
    if ownerServerId == nil then
        return nil
    end

    if status == nil or (status ~= 'active' and status ~= 'automatic_extinguishing' and status ~= 'manual_extinguishing') then
        status = 'active'
    end

    local coords = sanitizeVector(record.coords)
    local normal = sanitizeVector(record.normal)

    return {
        flareId = tostring(flareId),
        netId = netId,
        ownerServerId = ownerServerId,
        createdAt = toNumber(record.createdAt),
        extinguishDurationMilliseconds = toNumber(record.extinguishDurationMilliseconds),
        extinguishRemainingMilliseconds = toNumber(record.extinguishRemainingMilliseconds),
        extinguishStartedAt = toNumber(record.extinguishStartedAt), manualActorSource=toNumber(record.manualActorSource),
        coords = coords,
        normal = normal,
        status = status,
        routingBucket = toNumber(record.routingBucket),tipLength=toNumber(record.tipLength),burnStage=toNumber(record.burnStage)
    }
end

local function cloneEventPayload(payload)
    local clone = {}
    if type(payload) ~= 'table' then
        return clone
    end

    for key, value in pairs(payload) do
        if type(value) == 'table' then
            local nested = {}
            for nestedKey, nestedValue in pairs(value) do
                if type(nestedValue) == 'table' then
                    nested[nestedKey] = cloneEventPayload(nestedValue)
                else
                    nested[nestedKey] = nestedValue
                end
            end
            clone[key] = nested
        else
            clone[key] = value
        end
    end

    return clone
end

local function emitWorldFlaresEvent(eventName, payload)
    if type(payload) ~= 'table' then
        payload = {}
    end
    payload.type = eventName

    local clonePayload = cloneEventPayload(payload)

    for _, subscription in pairs(subscriptions) do
        if type(subscription) == 'table' and type(subscription.callback) == 'function' then
            pcall(subscription.callback, eventName, clonePayload)
        end
    end
end

local function cloneRecord(record)
    if type(record) ~= 'table' then
        return nil
    end

    return {
        flareId = record.flareId,
        netId = record.netId,
        ownerServerId = record.ownerServerId,
        tipLength=record.tipLength,burnStage=record.burnStage,
        createdAt = toNumber(record.createdAt),
        extinguishDurationMilliseconds = toNumber(record.extinguishDurationMilliseconds),
        extinguishRemainingMilliseconds = toNumber(record.extinguishRemainingMilliseconds),
        extinguishStartedAt = toNumber(record.extinguishStartedAt), manualActorSource=toNumber(record.manualActorSource),
        status = record.status,
        routingBucket = record.routingBucket,
        coords = record.coords and {
            x = record.coords.x,
            y = record.coords.y,
            z = record.coords.z
        } or nil,
        normal = record.normal and {
            x = record.normal.x,
            y = record.normal.y,
            z = record.normal.z
        } or nil
    }
end

function WorldFlares.upsert(record, fromSnapshot)
    local safeRecord = sanitizeRecord(record)
    if not safeRecord then
        return false
    end

    local flareId = tostring(safeRecord.flareId)
    local existingByNetId = recordsByNetId[safeRecord.netId]
    if existingByNetId and existingByNetId ~= flareId then
        if Config and Config.Debug then
            print(('[RoadFlares.WorldFlares] netId conflict: netId=%d existing=%s new=%s'):format(
                safeRecord.netId,
                tostring(existingByNetId),
                tostring(flareId)
            ))
        end
        return false
    end

    local existing = recordsById[flareId]
    if existing then
        local previous = cloneRecord(existing)
        existing.tipLength=safeRecord.tipLength;existing.burnStage=safeRecord.burnStage
        if existing.netId~=safeRecord.netId then recordsByNetId[existing.netId]=nil end

        existing.coords = safeRecord.coords
        existing.normal = safeRecord.normal
        existing.ownerServerId = safeRecord.ownerServerId
        existing.status = safeRecord.status
        existing.extinguishDurationMilliseconds = safeRecord.extinguishDurationMilliseconds
        existing.extinguishStartedAt = safeRecord.extinguishStartedAt;existing.manualActorSource=safeRecord.manualActorSource
        existing.extinguishRemainingMilliseconds = safeRecord.extinguishRemainingMilliseconds
        existing.routingBucket = safeRecord.routingBucket
        existing.netId = safeRecord.netId
        recordsByNetId[safeRecord.netId] = flareId
        emitWorldFlaresEvent('upsert', {
            flareId = flareId,
            record = cloneRecord(safeRecord),
            previous = previous,
            recordType = 'update', fromSnapshot = fromSnapshot == true
        })
        return true
    end

    recordsById[flareId] = safeRecord
    recordsByNetId[safeRecord.netId] = flareId

    if ownedActiveCount ~= nil and (safeRecord.status == 'active' or safeRecord.status == 'automatic_extinguishing' or safeRecord.status == 'manual_extinguishing') then
        ownedActiveCount = ownedActiveCount + 1
    end

    emitWorldFlaresEvent('upsert', {
        flareId = flareId,
        record = cloneRecord(safeRecord),
        previous = nil,
        recordType = 'insert', fromSnapshot = fromSnapshot == true
    })

    return true
end

function WorldFlares.add(record)
    return WorldFlares.upsert(record)
end

function WorldFlares.getRoutingBucket()
    return currentRoutingBucket
end

function WorldFlares.getLatestSnapshotVersion()
    return latestSnapshotVersion
end

function WorldFlares.remove(flareId, fromSnapshot)
    if flareId == nil then
        return false
    end

    local key = tostring(flareId)
    local removed = recordsById[key]
    if not removed then
        return false
    end

    local previous = cloneRecord(removed)

    recordsById[key] = nil
    for netId, trackedId in pairs(recordsByNetId) do
        if trackedId == key then
            recordsByNetId[netId] = nil
            break
        end
    end
    if ownedActiveCount ~= nil and (removed.status == 'active' or removed.status == 'automatic_extinguishing' or removed.status == 'manual_extinguishing') then
        ownedActiveCount = math.max(0, (ownedActiveCount - 1))
    end

    emitWorldFlaresEvent('remove', {
        flareId = key,
        record = previous,
        recordType = 'remove', fromSnapshot = fromSnapshot == true
    })

    return true
end

function WorldFlares.removeByNetId(netId)
    local key = toNumber(netId)
    if not key then
        return false
    end

    local flareId = recordsByNetId[key]
    if not flareId then
        return false
    end

    return WorldFlares.remove(flareId)
end

function WorldFlares.get(flareId)
    if flareId == nil then
        return nil
    end
    return cloneRecord(recordsById[tostring(flareId)])
end

function WorldFlares.getByNetId(netId)
    local key = toNumber(netId)
    if not key then
        return nil
    end
    local flareId = recordsByNetId[key]
    if not flareId then
        return nil
    end
    return cloneRecord(recordsById[tostring(flareId)])
end

function WorldFlares.getAll()
    local list = {}
    local index = 1
    for _, record in pairs(recordsById) do
        list[index] = cloneRecord(record)
        index = index + 1
    end
    return list
end

-- Called by the existing ground scan using already-read network coordinates.
-- No new network messages or physics polling worker are needed.
function WorldFlares.updatePhysicalPosition(flareId,coords)
    local record=recordsById[tostring(flareId)]
    if not record or not coords then return end
    local previous=record.coords
    if previous then
        local x,y,z=coords.x-previous.x,coords.y-previous.y,coords.z-previous.z
        if x*x+y*y+z*z<.0009 then return end
    end
    record.coords={x=coords.x,y=coords.y,z=coords.z}
    emitWorldFlaresEvent('moved',{flareId=record.flareId,record=cloneRecord(record)})
end

function WorldFlares.getOwnedActiveCount()
    return ownedActiveCount
end

function WorldFlares.setOwnedActiveCount(count)
    local nextCount = toNumber(count)
    if not nextCount then
        return false
    end
    if nextCount < 0 then
        nextCount = 0
    end
    ownedActiveCount = nextCount
    return true
end

function WorldFlares.getActiveCount()
    local count = 0
    for _, record in pairs(recordsById) do
    if record and (record.status == 'active' or record.status == 'automatic_extinguishing' or record.status == 'manual_extinguishing') then
        count = count + 1
    end
    end
    return count
end

function WorldFlares.clear(reason)
    emitWorldFlaresEvent('clear', {
        reason = reason
    })

    recordsById = {}
    recordsByNetId = {}
    ownedActiveCount = nil
    currentRoutingBucket = nil
    latestSnapshotVersion = 0
    if Config and Config.Debug then
        print(('[RoadFlares.WorldFlares] clear: ' .. tostring(reason or 'unknown')))
    end

    subscriptions = {}
    nextSubscriptionId = 1
end

function WorldFlares.reconcileSnapshot(records, activeCountFromServer, maxActive, routingBucket, syncVersion)
    local incomingVersion = toNumber(syncVersion)
    if incomingVersion == nil then
        emitWorldFlaresEvent('snapshot', {
            applied = false,
            reason = 'missing_sync_version'
        })
        return {
            applied = false,
            reason = 'missing_sync_version'
        }
    end

    if incomingVersion < latestSnapshotVersion then
        emitWorldFlaresEvent('snapshot', {
            applied = false,
            reason = 'stale_snapshot',
            syncVersion = incomingVersion
        })
        return {
            applied = false,
            reason = 'stale_snapshot'
        }
    end

    latestSnapshotVersion = incomingVersion

    local incoming = {}
    local upserted = 0
    local removedCount = 0
    local incomingBucket
    if routingBucket ~= nil then
        incomingBucket = toNumber(routingBucket)
    end
    local previousBucket = currentRoutingBucket
    if incomingBucket == nil then
        incomingBucket = previousBucket
    end
    local bucketChanged = false
    if previousBucket ~= nil and incomingBucket ~= nil and previousBucket ~= incomingBucket then
        bucketChanged = true
    end

    if type(records) == 'table' then
        for _, record in ipairs(records) do
            local safe = sanitizeRecord(record)
            if safe then
                incoming[safe.flareId] = true
                if incomingBucket == nil and type(safe.routingBucket) == 'number' then
                    incomingBucket = safe.routingBucket
                end
                WorldFlares.upsert(safe, true)
                upserted = upserted + 1
            end
        end
    end

    if incomingBucket == nil then
        incomingBucket = previousBucket
    end

    if incomingBucket ~= nil then
        local toRemove = {}
        for flareId, record in pairs(recordsById) do
            if not incoming[tostring(flareId)] then
                toRemove[tostring(flareId)] = true
            end
        end

        for flareId in pairs(toRemove) do
            WorldFlares.remove(flareId, true)
            removedCount = removedCount + 1
        end
    end

    if bucketChanged then
        local toReset = {}
        for flareId, record in pairs(recordsById) do
            if record and toNumber(record.routingBucket) == previousBucket then
                toReset[tostring(flareId)] = true
            end
        end
        for flareId in pairs(toReset) do
            WorldFlares.remove(flareId, true)
            removedCount = removedCount + 1
        end
    end

    if activeCountFromServer ~= nil then
        local parsed = toNumber(activeCountFromServer)
        if not parsed then
            parsed = ownedActiveCount or 0
        end
        if parsed < 0 then
            parsed = 0
        end
        local maxActiveNumber = toNumber(maxActive)
        if maxActiveNumber ~= nil and maxActiveNumber > 0 then
            parsed = math.min(parsed, maxActiveNumber)
        end
        ownedActiveCount = parsed
    end

    currentRoutingBucket = incomingBucket

    emitWorldFlaresEvent('snapshot', {
        applied = true,
        bucketChanged = bucketChanged,
        oldBucket = previousBucket,
        newBucket = incomingBucket,
        incomingCount = upserted,
        removedCount = removedCount,
        syncVersion = incomingVersion
    })

    if bucketChanged then
        emitWorldFlaresEvent('bucket_changed', {
            oldBucket = previousBucket,
            newBucket = incomingBucket
        })
    end

    return {
        applied = true,
        bucketChanged = bucketChanged,
        oldBucket = previousBucket,
        newBucket = incomingBucket
    }
end

function WorldFlares.subscribe(callback)
    if type(callback) ~= 'function' then
        return nil
    end

    for subscriptionId, subscription in pairs(subscriptions) do
        if subscription and subscription.callback == callback then
            return subscriptionId
        end
    end

    local subscriptionId = nextSubscriptionId
    nextSubscriptionId = nextSubscriptionId + 1
    subscriptions[subscriptionId] = {
        callback = callback
    }
    return subscriptionId
end

function WorldFlares.unsubscribe(subscriptionId)
    if not subscriptionId then
        return false
    end

    local removed = subscriptions[subscriptionId] ~= nil
    subscriptions[subscriptionId] = nil
    return removed == true
end
