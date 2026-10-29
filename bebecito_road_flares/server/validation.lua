RoadFlares = RoadFlares or {}
RoadFlares.Server = RoadFlares.Server or {}

RoadFlares.Server.Validation = RoadFlares.Server.Validation or {}

local Validation = RoadFlares.Server.Validation
local Utils = RoadFlares.Utils

local cooldowns = {}
local activationCooldowns = {}
local placementCooldowns = {}
local snapshotCooldowns = {}
local manualExtinguishCooldowns = {}
local recentPlacementRequests = {}

local function toNumber(value)
    local number = tonumber(value)
    if type(number) ~= 'number' or number ~= number then
        return nil
    end
    return number
end

local function hasFiniteCoordinates(values)
    if type(values) ~= 'table' then
        return false
    end
    return toNumber(values.x) ~= nil and toNumber(values.y) ~= nil and toNumber(values.z) ~= nil
end

local function normalizeFinite(value)
    local number = toNumber(value)
    if number == nil then
        return nil
    end
    if number == math.huge or number == -math.huge then
        return nil
    end
    return number
end

local function normalizeCoordValue(value)
    local number = normalizeFinite(value)
    if number == nil then
        return nil
    end
    return number
end

local function nowMilliseconds()
    return Utils.nowMilliseconds()
end

local function pruneRecentRequests(sourceKey, nowMs)
    local requests = recentPlacementRequests[sourceKey]
    if not requests then
        return
    end

    local ttl = toNumber(Config.ServerPlacement and Config.ServerPlacement.RecentRequestTtlMilliseconds) or 15000
    local maxEntries = toNumber(Config.ServerPlacement and Config.ServerPlacement.MaximumRecentRequestsPerPlayer) or 32

    for requestId, entry in pairs(requests) do
        if not entry or not entry.createdAt or (nowMs - entry.createdAt) > ttl then
            requests[requestId] = nil
        end
    end

    local processing = {}
    local completed = {}
    for requestId, entry in pairs(requests) do
        if entry and entry.status == 'processing' then
            processing[#processing + 1] = {
                requestId = requestId,
                createdAt = entry.createdAt
            }
        else
            if entry and entry.createdAt then
                completed[#completed + 1] = {
                    requestId = requestId,
                    createdAt = entry.createdAt
                }
            end
        end
    end

    local maxCompleted = maxEntries - #processing
    if maxCompleted < 0 then
        maxCompleted = 0
    end

    while #completed > maxCompleted do
        local oldestId
        local oldestAt
        for _, entry in ipairs(completed) do
            if not oldestAt or (entry.createdAt and entry.createdAt < oldestAt) then
                oldestAt = entry.createdAt
                oldestId = entry.requestId
            end
        end
        if not oldestId then
            break
        end
        requests[oldestId] = nil
        for index, entry in ipairs(completed) do
            if entry.requestId == oldestId then
                table.remove(completed, index)
                break
            end
        end
    end

    while #processing > maxEntries do
        local oldestId
        local oldestAt
        for _, entry in ipairs(processing) do
            if not oldestAt or (entry.createdAt and entry.createdAt < oldestAt) then
                oldestAt = entry.createdAt
                oldestId = entry.requestId
            end
        end
        if not oldestId then
            break
        end
        requests[oldestId] = nil
        for index, entry in ipairs(processing) do
            if entry.requestId == oldestId then
                table.remove(processing, index)
                break
            end
        end
    end

    if next(requests) == nil then
        recentPlacementRequests[sourceKey] = nil
    end
end

function Validation.hasCooldown(src, key, cooldownMs)
    local now = nowMilliseconds()
    local state = cooldowns[key] or {}
    local last = state[src] or 0
    if (now - last) < (cooldownMs or 0) then
        return true
    end
    state[src] = now
    cooldowns[key] = state
    return false
end

function Validation.isVector(value)
    return Utils.isVectorLike(value)
end

function Validation.sanitizePoint(rawPoint)
    local point = Utils.normalizeVector(rawPoint)
    if not point then
        return nil
    end
    return {
        x = point.x,
        y = point.y,
        z = point.z
    }
end

function Validation.deriveDistance(firstPoint, secondPoint)
    return RoadFlares.Utils.distance2d(firstPoint, secondPoint) or 0.0
end

function Validation.clearCooldowns(src)
    for _, state in pairs(cooldowns) do
        state[src] = nil
    end
    activationCooldowns[src] = nil
    placementCooldowns[src] = nil
    snapshotCooldowns[src] = nil
    manualExtinguishCooldowns[src] = nil
    recentPlacementRequests[tostring(src)] = nil
end

function Validation.validateActivationRequest(src, payload)
    if type(src) ~= 'number' or src <= 0 then
        return false, nil, nil, nil, 'invalid_request'
    end

    if type(payload) ~= 'table' then
        return false, nil, nil, nil, 'invalid_request'
    end

    local requestId = Utils.sanitizeRequestId(payload.requestId)
    local requestToken = Utils.sanitizeRequestId(payload.requestToken)
    if not requestId then
        return false, nil, nil, nil, 'invalid_request'
    end

    local method = Utils.sanitizeMethod(payload.method)
    if not method then
        return false, requestId, nil, requestToken, 'invalid_request'
    end

    if not Utils.isActivationMethodEnabled(method) then
        return false, requestId, method, requestToken, 'method_disabled'
    end

    return true, requestId, method, requestToken, 'allowed'
end

function Validation.isActivationRateLimited(src)
    if type(src) ~= 'number' or src <= 0 then
        return true
    end

    local now = nowMilliseconds()
    local timeout = toNumber(Config.RateLimits and Config.RateLimits.ActivationMilliseconds) or 750
    local last = activationCooldowns[src] or 0
    if (now - last) < timeout then
        return true
    end
    activationCooldowns[src] = now
    return false
end

local function validatePlacementCoordinates(coords)
    if not hasFiniteCoordinates(coords) then
        return false
    end
    local limit = toNumber(Config.ServerPlacement and Config.ServerPlacement.CoordinateAbsoluteLimit) or 20000.0
    local x = normalizeCoordValue(coords.x)
    local y = normalizeCoordValue(coords.y)
    local z = normalizeCoordValue(coords.z)
    if x == nil or y == nil or z == nil then
        return false
    end
    if math.abs(x) > limit or math.abs(y) > limit or math.abs(z) > limit then
        return false
    end
    return true
end

local function validatePlacementNormal(normal)
    if not hasFiniteCoordinates(normal) then
        return false
    end

    local nx = normalizeCoordValue(normal.x)
    local ny = normalizeCoordValue(normal.y)
    local nz = normalizeCoordValue(normal.z)
    if nx == nil or ny == nil or nz == nil then
        return false
    end

    local length = math.sqrt((nx * nx) + (ny * ny) + (nz * nz))
    if math.abs(length - 1.0) > 0.05 then
        return false
    end

    local minimumZ = toNumber(Config.Placement and Config.Placement.MinimumSurfaceNormalZ) or 0.65
    if nz / length < minimumZ then
        return false
    end

    return true
end

function Validation.validatePlacementRequest(src, payload)
    if type(src) ~= 'number' or src <= 0 then
        return false, nil, nil, nil, nil, 'invalid_player'
    end

    if type(payload) ~= 'table' then
        return false, nil, nil, nil, nil, 'invalid_request'
    end

    local requestId = Utils.sanitizeRequestId(payload.requestId)
    local selectionId = toNumber(payload.selectionId)
    if not requestId then
        return false, nil, nil, nil, nil, 'invalid_request'
    end

    local coords = payload.coords
    if type(coords) ~= 'table' or not validatePlacementCoordinates(coords) then
        return false, requestId, selectionId, nil, nil, 'invalid_coordinates'
    end

    local normal = payload.normal
    if type(normal) ~= 'table' or not validatePlacementNormal(normal) then
        return false, requestId, selectionId, coords, nil, 'invalid_normal'
    end

    return true, requestId, selectionId, coords, normal, 'allowed'
end

function Validation.getPlacementSourceState(src)
    if type(src) ~= 'number' or src <= 0 then
        return false, nil, nil
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false, nil, nil
    end

    return true, ped, GetEntityCoords(ped)
end

function Validation.isPlacementRateLimited(src)
    if type(src) ~= 'number' or src <= 0 then
        return true
    end

    local now = nowMilliseconds()
    local timeout = toNumber(Config.RateLimits and Config.RateLimits.PlacementMilliseconds) or 500
    local last = placementCooldowns[src] or 0
    if (now - last) < timeout then
        return true
    end
    placementCooldowns[src] = now
    return false
end

function Validation.isManualExtinguishRateLimited(src)
    if type(src) ~= 'number' or src <= 0 then
        return true
    end
    local now = nowMilliseconds()
    local timeout = toNumber(Config.ManualExtinguish and Config.ManualExtinguish.RequestRateLimitMilliseconds) or 750
    local last = manualExtinguishCooldowns[src] or 0
    if (now - last) < timeout then
        return true
    end
    manualExtinguishCooldowns[src] = now
    return false
end

function Validation.isSnapshotRateLimited(src)
    if type(src) ~= 'number' or src <= 0 then
        return true
    end

    local now = nowMilliseconds()
    local timeout = toNumber(Config.RateLimits and Config.RateLimits.SnapshotMilliseconds) or 1000
    local last = snapshotCooldowns[src] or 0
    if (now - last) < timeout then
        return true
    end

    snapshotCooldowns[src] = now
    return false
end

function Validation.getRecentPlacementRequest(sourceKey, requestId)
    if sourceKey == nil then
        return nil
    end
    local key = tostring(sourceKey)
    pruneRecentRequests(key, nowMilliseconds())

    local requests = recentPlacementRequests[key]
    if not requests then
        return nil
    end
    local normalizedRequestId = Utils.sanitizeRequestId(requestId)
    if not normalizedRequestId then
        return nil
    end
    local entry = requests[normalizedRequestId]
    if not entry then
        return nil
    end

    return entry
end

function Validation.recordPlacementRequestStart(sourceKey, requestId)
    local normalizedRequestId = Utils.sanitizeRequestId(requestId)
    if not normalizedRequestId then
        return false, nil
    end

    local key = tostring(sourceKey)
    local now = nowMilliseconds()
    local requests = recentPlacementRequests[key]
    if not requests then
        requests = {}
        recentPlacementRequests[key] = requests
    end
    pruneRecentRequests(key, now)

    local existing = requests[normalizedRequestId]
    if existing then
        return false, existing
    end

    local ttl = toNumber(Config.ServerPlacement and Config.ServerPlacement.RecentRequestTtlMilliseconds) or 15000
    requests[normalizedRequestId] = {
        status = 'processing',
        createdAt = now,
        updatedAt = now,
        expiresAt = now + ttl,
        response = nil,
        requestId = normalizedRequestId
    }
    return true, requests[normalizedRequestId]
end

function Validation.recordPlacementRequestResult(sourceKey, requestId, response)
    local key = tostring(sourceKey)
    local normalizedRequestId = Utils.sanitizeRequestId(requestId)
    if not normalizedRequestId then
        return false
    end

    local requests = recentPlacementRequests[key]
    if not requests then
        requests = {}
        recentPlacementRequests[key] = requests
    end

    local ttl = toNumber(Config.ServerPlacement and Config.ServerPlacement.RecentRequestTtlMilliseconds) or 15000
    local now = nowMilliseconds()
    local existing = requests[normalizedRequestId]
    requests[normalizedRequestId] = {
        status = 'completed',
        createdAt = existing and existing.createdAt or now,
        updatedAt = now,
        expiresAt = now + ttl,
        response = response,
        requestId = normalizedRequestId
    }
    pruneRecentRequests(key, now)
    return true
end

function Validation.beginPlacementRequest(sourceKey, requestId)
    return Validation.recordPlacementRequestStart(sourceKey, requestId)
end

function Validation.completePlacementRequest(sourceKey, requestId, response)
    return Validation.recordPlacementRequestResult(sourceKey, requestId, response)
end
