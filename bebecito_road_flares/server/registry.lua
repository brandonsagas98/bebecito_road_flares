RoadFlares = RoadFlares or {}
RoadFlares.Server = RoadFlares.Server or {}
RoadFlares.Server.Registry = RoadFlares.Server.Registry or {}

local Registry = RoadFlares.Server.Registry
local Utils = RoadFlares.Utils

local function normalizeId(value)
    if value == nil then
        return nil
    end
    local text = tostring(value)
    if text == '' then
        return nil
    end
    return text
end

local function nowMilliseconds()
    return (Utils and Utils.nowMilliseconds and Utils.nowMilliseconds()) or (GetGameTimer and GetGameTimer() or 0)
end

local function toNumber(value)
    local number = tonumber(value)
    if type(number) ~= 'number' or number ~= number then
        return nil
    end
    return number
end

local function normalizeStatus(status)
    if status == 'manual_extinguishing' then
        return 'manual_extinguishing'
    end
    if status == 'automatic_extinguishing' then
        return 'automatic_extinguishing'
    end
    if status == 'removed' then
        return 'removed'
    end
    return 'active'
end

local function sanitizeVector(value)
    if type(value) ~= 'table' then
        return nil
    end
    local x = toNumber(value.x)
    local y = toNumber(value.y)
    local z = toNumber(value.z)
    if x == nil or y == nil or z == nil then
        return nil
    end
    return {
        x = x,
        y = y,
        z = z
    }
end

local function cloneRecord(record)
    if type(record) ~= 'table' then
        return nil
    end
    return {
        id = record.id,
        ownerSource = record.ownerSource,
        entity = record.entity,
        netId = record.netId,
        routingBucket = toNumber(record.routingBucket),
        coords = sanitizeVector(record.coords),
        normal = sanitizeVector(record.normal),
        status = normalizeStatus(record.status),
        createdAt = toNumber(record.createdAt),
        placementRequestId = record.placementRequestId,
        expiresAt = record.expiresAt,
        tipLength=record.tipLength,burnStage=record.burnStage,ignitedAt=record.ignitedAt,
        burnDurationMilliseconds=record.burnDurationMilliseconds,
        lifecycleGeneration = toNumber(record.lifecycleGeneration),
        extinguishStartedAt = toNumber(record.extinguishStartedAt),
        extinguishDurationMilliseconds = toNumber(record.extinguishDurationMilliseconds),
        extinguishMode = record.extinguishMode,
        manualActorSource = toNumber(record.manualActorSource)
    }
end

local function deleteEntity(entity)
    if type(entity) ~= 'number' or entity == 0 then
        return
    end
    if DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
end

if type(Registry.flaresById) ~= 'table' then
    Registry.flaresById = {}
end
if type(Registry.flaresByOwner) ~= 'table' then
    Registry.flaresByOwner = {}
end
if type(Registry.flaresByNetId) ~= 'table' then
    Registry.flaresByNetId = {}
end
if type(Registry.nextFlareId) ~= 'number' then
    Registry.nextFlareId = 0
end

function Registry._reset()
    Registry.flaresById = {}
    Registry.flaresByOwner = {}
    Registry.flaresByNetId = {}
    Registry.nextFlareId = 0
end

function Registry.createRecord(ownerSource, entity, netId, coords, normal, routingBucket, placementRequestId, status)
    local owner = toNumber(ownerSource)
    if owner == nil or owner <= 0 then
        return nil
    end
    local entityRecord = toNumber(entity)
    if entityRecord == nil then
        return nil
    end
    local validNetId = toNumber(netId)
    if validNetId == nil or validNetId <= 0 then
        return nil
    end

    local safeCoords = sanitizeVector(coords)
    local safeNormal = sanitizeVector(normal)
    if not safeCoords or not safeNormal then
        return nil
    end

    Registry.nextFlareId = Registry.nextFlareId + 1
    local flareId = tostring(Registry.nextFlareId)

    local record = {
        id = flareId,
        ownerSource = owner,
        entity = entityRecord,
        netId = validNetId,
        routingBucket = toNumber(routingBucket) or 0,
        coords = safeCoords,
        normal = safeNormal,
        status = normalizeStatus(status),
        lifecycleGeneration = 1,
        createdAt = nowMilliseconds(),
        placementRequestId = normalizeId(placementRequestId),
        expiresAt = nil
    }

    return record
end

function Registry.add(record)
    if type(record) ~= 'table' then
        return false
    end
    local flareId = normalizeId(record.id)
    local owner = toNumber(record.ownerSource)
    local validNetId = toNumber(record.netId)
    local entity = toNumber(record.entity)
    local createdAt = toNumber(record.createdAt)
    if
        not flareId or
        owner == nil or owner <= 0 or
        validNetId == nil or validNetId <= 0 or
        entity == nil or entity <= 0 or
        createdAt == nil
    then
        return false
    end
    local status = normalizeStatus(record.status)
    if status ~= 'active' and status ~= 'automatic_extinguishing' and status ~= 'manual_extinguishing' and status ~= 'removed' then
        return false
    end
    if type(sanitizeVector(record.coords)) ~= 'table' then
        return false
    end
    if type(sanitizeVector(record.normal)) ~= 'table' then
        return false
    end

    if Registry.flaresById[flareId] then
        return false
    end
    if Registry.flaresByNetId[validNetId] then
        return false
    end
    if toNumber(record.routingBucket) == nil then
        return false
    end

    Registry.flaresById[flareId] = record
    Registry.flaresByNetId[validNetId] = flareId
    Registry.flaresByOwner[owner] = Registry.flaresByOwner[owner] or {}
    Registry.flaresByOwner[owner][flareId] = true
    if toNumber(record.lifecycleGeneration) == nil then
        record.lifecycleGeneration = 1
    end
    return true
end

function Registry.get(flareId)
    return Registry.flaresById[normalizeId(flareId)]
end

-- Event-driven pose refresh: serialization, interaction and removal only.
-- The engine already replicates physics; no server polling worker is added.
function Registry.refreshPhysicalPose(record)
    if type(record)~='table' or not record.physicsCarrier or not DoesEntityExist(record.entity)then return end
    local p=GetEntityCoords(record.entity)
    local coords=RoadFlares.Utils.normalizeVector(p)
    if coords then record.coords={x=coords.x,y=coords.y,z=coords.z};record.entityCoords=record.coords end
    if GetEntityRotation then
        local rot=RoadFlares.Utils.normalizeVector(GetEntityRotation(record.entity,0))
        if rot then record.rotation={x=rot.x,y=rot.y,z=rot.z}end
    end
end

function Registry.remove(flareId, reason)
    local flareIdKey = normalizeId(flareId)
    if not flareIdKey then
        return false
    end

    local record = Registry.flaresById[flareIdKey]
    if not record then
        return false
    end

    local owner = record.ownerSource
    local recordNetId = toNumber(record.netId)

    Registry.flaresById[flareIdKey] = nil
    if recordNetId ~= nil then
        Registry.flaresByNetId[recordNetId] = nil
    end

    if Registry.flaresByOwner[owner] then
        Registry.flaresByOwner[owner][flareIdKey] = nil
        if not next(Registry.flaresByOwner[owner]) then
    Registry.flaresByOwner[owner] = nil
        end
    end

    Registry.refreshPhysicalPose(record)
    deleteEntity(record.entity)
    record.lifecycleGeneration = (toNumber(record.lifecycleGeneration) or 0) + 1
    record.status = 'removed'
    record.removalReason = reason or 'removed'
    record.removedAt = nowMilliseconds()
    return record
end

function Registry.rebind(flareId,entity,netId)
    local record=Registry.get(flareId)
    if not record or not entity or not netId or netId<=0 or Registry.flaresByNetId[netId] then return false end
    Registry.flaresByNetId[record.netId]=nil
    record.entity=entity;record.netId=netId
    Registry.flaresByNetId[netId]=record.id
    return true
end

function Registry.getByNetId(netId)
    local flareId = Registry.flaresByNetId[toNumber(netId)]
    if not flareId then
        return nil
    end
    return Registry.flaresById[flareId]
end

function Registry.getOwned(owner)
    local ownerSource = toNumber(owner)
    if ownerSource == nil or ownerSource <= 0 then
        return {}
    end
    local byOwner = Registry.flaresByOwner[ownerSource]
    if not byOwner then
        return {}
    end

    local list = {}
    for id in pairs(byOwner) do
        local record = Registry.flaresById[id]
        if record then
            list[#list + 1] = record
        end
    end
    return list
end

function Registry.getActiveCount(ownerSource)
    local count = 0
    local records = Registry.getOwned(ownerSource)
    for i = 1, #records do
        local status = normalizeStatus(records[i].status)
        if status == 'active' or status == 'automatic_extinguishing' or status == 'manual_extinguishing' then
            count = count + 1
        end
    end
    return count
end

function Registry.getAll()
    local list = {}
    for id, record in pairs(Registry.flaresById) do
        list[id] = record
    end
    return list
end

function Registry.getActiveInBucket(bucket)
    local targetBucket = toNumber(bucket)
    if targetBucket == nil then
        return {}
    end

    local records = {}
    for _, record in pairs(Registry.flaresById) do
        local recordBucket = toNumber(record.routingBucket)
        local recordStatus = normalizeStatus(record.status)
        if recordBucket == targetBucket and (recordStatus == 'active' or recordStatus == 'automatic_extinguishing' or recordStatus == 'manual_extinguishing') then
            records[#records + 1] = cloneRecord(record)
        end
    end
    return records
end

function Registry.clearOwner(ownerSource, reason)
    local records = Registry.getOwned(ownerSource)
    local removed = {}
    for i = 1, #records do
        local removedRecord = Registry.remove(records[i].id, reason or 'owner_left')
        if removedRecord then
            removed[#removed + 1] = removedRecord
        end
    end
    return removed
end

function Registry.clearAll(reason)
    local allIds = {}
    local removed = {}
    for id in pairs(Registry.flaresById) do
        allIds[#allIds + 1] = id
    end
    for i = 1, #allIds do
        local removedRecord = Registry.remove(allIds[i], reason or 'resource_stop')
        if removedRecord then
            removed[#removed + 1] = removedRecord
        end
    end
    return removed
end

function Registry.audit()
    local duplicateNetIds = {}
    local activeCountByOwner = {}
    for id, record in pairs(Registry.flaresById) do
        if type(record) == 'table' then
            if record.netId then
                local key = tostring(record.netId)
                duplicateNetIds[key] = (duplicateNetIds[key] or 0) + 1
            end
            if record.ownerSource then
                local recordStatus = normalizeStatus(record.status)
                if recordStatus == 'active' or recordStatus == 'automatic_extinguishing' or recordStatus == 'manual_extinguishing' then
                    activeCountByOwner[record.ownerSource] = (activeCountByOwner[record.ownerSource] or 0) + 1
                end
            end
        end
    end
    return {
        duplicateNetIds = duplicateNetIds,
        activeCountByOwner = activeCountByOwner
    }
end

function Registry.updateStatus(flareId, expectedStatus, newStatus, metadata)
    local flareIdKey = normalizeId(flareId)
    if not flareIdKey then
        return nil, 'invalid_flare_id'
    end

    local record = Registry.flaresById[flareIdKey]
    if not record then
        return nil, 'not_found'
    end

    local currentStatus = normalizeStatus(record.status)
    local resolvedNewStatus = normalizeStatus(newStatus)
    local resolvedExpected = nil
    if expectedStatus ~= nil then
        resolvedExpected = normalizeStatus(expectedStatus)
        if currentStatus ~= resolvedExpected then
            return nil, 'status_mismatch'
        end
    end
    if not resolvedNewStatus or resolvedNewStatus == 'removed' then
        return nil, 'invalid_status'
    end

    local nextGeneration = toNumber(metadata and metadata.lifecycleGeneration)
    if nextGeneration == nil then
        nextGeneration = (toNumber(record.lifecycleGeneration) or 0) + 1
    end

    record.status = resolvedNewStatus
    record.lifecycleGeneration = nextGeneration
    if resolvedNewStatus == 'automatic_extinguishing' or resolvedNewStatus == 'manual_extinguishing' then
        local extinguishStartedAt = toNumber(metadata and metadata.extinguishStartedAt)
        local extinguishDuration = toNumber(metadata and metadata.extinguishDurationMilliseconds)
        local extinguishMode = tostring(metadata and metadata.extinguishMode or '')
        if extinguishStartedAt == nil then
            extinguishStartedAt = nowMilliseconds()
        end
        if extinguishDuration == nil or extinguishDuration <= 0 then
            extinguishDuration = nil
        end
        record.extinguishStartedAt = extinguishStartedAt
        record.extinguishDurationMilliseconds = extinguishDuration
        record.extinguishMode = extinguishMode ~= '' and extinguishMode or nil
        if resolvedNewStatus == 'manual_extinguishing' then
            local manualActorSource = toNumber(metadata and metadata.manualActorSource)
            if manualActorSource then
                record.manualActorSource = manualActorSource
            else
                record.manualActorSource = nil
            end
        else
            record.manualActorSource = nil
        end
    else
        record.extinguishStartedAt = nil
        record.extinguishDurationMilliseconds = nil
        record.extinguishMode = nil
        record.manualActorSource = nil
    end
    record.updatedAt = nowMilliseconds()

    local clone = cloneRecord(record)
    return clone, nil
end
