RoadFlares = RoadFlares or {}
RoadFlares.Client = RoadFlares.Client or {}

local Placement = {}
RoadFlares.Placement = Placement

local Constants = RoadFlares.Constants or {}
local Utils = RoadFlares.Utils or {}
local Effects = RoadFlares.Client and RoadFlares.Client.Effects or nil

local State = {
    INACTIVE = 'inactive',
    ACTIVE = 'active',
    TARGETING = 'targeting'
}

local RaycastState = {
    NONE = 'none',
    PENDING = 'pending',
    COMPLETE = 'complete',
    INVALID = 'invalid',
    TIMEOUT = 'timeout'
}

local state = {
    mode = State.INACTIVE,
    active = false,
    generation = 0,
    sessionToken = nil,
    isSessionValid = nil,
    ped = nil,

    raycastHandle = 0,
    raycastState = RaycastState.NONE,
    raycastRequestedAt = 0,
    raycastCompletedAt = 0,
    raycastStartedAt = 0,
    lastResultAt = 0,

    lastHit = false,
    lastCoords = nil,
    lastNormal = nil,
    lastEntity = 0,
    lastReason = 'no_hit',
    lastValid = false,

    selection = nil,
    selectionId = 0,
    selectionSequence = 0,
    selectionLocked = false,
    maxPreviewAgeMs = 0,
    shapeTestIntervalMs = 0,
    shapeTestTimeoutMs = 0,
    placementDistance = 0,
    minimumSurfaceNormalZ = 0.65,

    threadGeneration = 0
}

local function debugPrint(message)
    Utils.debugPrint(message, Constants and Constants.ResourceName or 'bebecito_road_flares')
end

local function toNumber(value, fallback)
    local candidate = tonumber(value)
    if type(candidate) ~= 'number' or candidate ~= candidate then
        return fallback
    end
    return candidate
end

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value and value > -1e9 and value < 1e9
end

local function nowMilliseconds()
    return Utils.nowMilliseconds()
end

local function copyVector3(values)
    if not values then
        return nil
    end
    if type(values) == 'vector3' then
        return {
            x = values.x,
            y = values.y,
            z = values.z
        }
    end
    if type(values) ~= 'table' then
        return nil
    end
    return {
        x = tonumber(values.x),
        y = tonumber(values.y),
        z = tonumber(values.z)
    }
end

local function validVector(values)
    if not values then
        return false
    end
    return isFiniteNumber(values.x) and isFiniteNumber(values.y) and isFiniteNumber(values.z)
end

local function vectorDistance(a, b)
    if not a or not b or not validVector(a) or not validVector(b) then
        return nil
    end
    local dx = (a.x - b.x)
    local dy = (a.y - b.y)
    local dz = (a.z - b.z)
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function normalizePreviewEntry()
    local placementConfig = Config and Config.Placement or {}
    state.shapeTestIntervalMs = toNumber(placementConfig.RaycastIntervalMilliseconds, 50)
    state.shapeTestTimeoutMs = toNumber(placementConfig.ResultTimeoutMilliseconds, 500)
    state.maxPreviewAgeMs = toNumber(placementConfig.MaximumPreviewAgeMilliseconds, 250)
    state.minimumSurfaceNormalZ = toNumber(placementConfig.MinimumSurfaceNormalZ, 0.65)
    state.placementDistance = toNumber((Config and Config.Distances and Config.Distances.Placement), 20.0)

    if state.shapeTestIntervalMs < 15 then
        state.shapeTestIntervalMs = 15
    end
    if state.shapeTestTimeoutMs < 100 then
        state.shapeTestTimeoutMs = 100
    end
    if state.maxPreviewAgeMs < 50 then
        state.maxPreviewAgeMs = 50
    end
    if state.minimumSurfaceNormalZ < -1 then
        state.minimumSurfaceNormalZ = -1
    end
    if state.minimumSurfaceNormalZ > 1 then
        state.minimumSurfaceNormalZ = 1
    end
    if state.placementDistance <= 0 then
        state.placementDistance = 1.0
    end
end

local function normalizeConfigVectors(input)
    return {
        x = toNumber(input.x, 0.0) or 0.0,
        y = toNumber(input.y, 0.0) or 0.0,
        z = toNumber(input.z, 0.0) or 0.0
    }
end

local function getPreviewConfig()
    local defaultConfig = {
        Type = 1,
        HeightOffset = 0.03,
        Enabled = true,
        Scale = {
            x = 0.18,
            y = 0.18,
            z = 0.08
        },
        ValidColor = {
            r = 40,
            g = 220,
            b = 80,
            a = 180
        },
        InvalidColor = {
            r = 220,
            g = 50,
            b = 40,
            a = 150
        }
    }
    local configured = (Config and Config.Placement and Config.Placement.Preview) or {}
    return {
        Type = toNumber(configured.Type, defaultConfig.Type),
        Enabled = configured.Enabled == true,
        HeightOffset = toNumber(configured.HeightOffset, defaultConfig.HeightOffset) or defaultConfig.HeightOffset,
        Scale = normalizeConfigVectors(configured.Scale or {}),
        ValidColor = {
            r = toNumber((configured.ValidColor and configured.ValidColor.r), defaultConfig.ValidColor.r) or defaultConfig.ValidColor.r,
            g = toNumber((configured.ValidColor and configured.ValidColor.g), defaultConfig.ValidColor.g) or defaultConfig.ValidColor.g,
            b = toNumber((configured.ValidColor and configured.ValidColor.b), defaultConfig.ValidColor.b) or defaultConfig.ValidColor.b,
            a = toNumber((configured.ValidColor and configured.ValidColor.a), defaultConfig.ValidColor.a) or defaultConfig.ValidColor.a
        },
        InvalidColor = {
            r = toNumber((configured.InvalidColor and configured.InvalidColor.r), defaultConfig.InvalidColor.r) or defaultConfig.InvalidColor.r,
            g = toNumber((configured.InvalidColor and configured.InvalidColor.g), defaultConfig.InvalidColor.g) or defaultConfig.InvalidColor.g,
            b = toNumber((configured.InvalidColor and configured.InvalidColor.b), defaultConfig.InvalidColor.b) or defaultConfig.InvalidColor.b,
            a = toNumber((configured.InvalidColor and configured.InvalidColor.a), defaultConfig.InvalidColor.a) or defaultConfig.InvalidColor.a
        }
    }
end

local function getFlags(key, fallback)
    local configured = (Config and Config.Placement) or {}
    local defaultValue = toNumber(fallback, 17)
    local value = configured[key]
    if value == nil then
        return defaultValue
    end
    value = toNumber(value, defaultValue)
    if value < 0 then
        value = defaultValue
    end
    return value
end

local function isCurrentPed()
    return type(state.ped) == 'number' and state.ped ~= 0 and DoesEntityExist(state.ped)
end

local function isSessionStillValid()
    if not state.active then
        return false
    end
    if not state.sessionToken then
        return false
    end
    if not isCurrentPed() then
        return false
    end
    if state.ped ~= PlayerPedId() then
        return false
    end
    if type(state.isSessionValid) == 'function' and not state.isSessionValid() then
        return false
    end
    return true
end

local function clearShapeTest()
    state.raycastHandle = 0
    if state.raycastState == RaycastState.PENDING then
        state.raycastState = RaycastState.NONE
    end
end

local function isShapeTestComplete(status)
    if type(status) == 'number' then
        return status ~= 0
    end
    if type(status) == 'boolean' then
        return status
    end
    return false
end

local function isHitStatus(status)
    return status == true or status == 1
end

local function getCameraRay()
    local origin = GetGameplayCamCoord()
    if not validVector(origin) then
        return nil, nil, 'camera_origin_invalid'
    end

    local rotation = GetGameplayCamRot(2)
    if not validVector(rotation) then
        return nil, nil, 'camera_rotation_invalid'
    end

    local yaw = math.rad(rotation.z)
    local pitch = math.rad(rotation.x)
    local cosPitch = math.abs(math.cos(pitch))
    local direction = {
        x = -math.sin(yaw) * cosPitch,
        y = math.cos(yaw) * cosPitch,
        z = math.sin(pitch)
    }

    if not validVector(direction) then
        return nil, nil, 'camera_direction_invalid'
    end

    local directionLength = math.sqrt((direction.x * direction.x) + (direction.y * direction.y) + (direction.z * direction.z))
    if directionLength <= 0 then
        return nil, nil, 'camera_direction_invalid'
    end

    local normalizedDirection = {
        x = direction.x / directionLength,
        y = direction.y / directionLength,
        z = direction.z / directionLength
    }

    if not validVector(normalizedDirection) then
        return nil, nil, 'camera_direction_invalid'
    end

    if state.placementDistance <= 0 then
        return nil, nil, 'placement_distance_invalid'
    end

    local destination = {
        x = origin.x + (normalizedDirection.x * state.placementDistance),
        y = origin.y + (normalizedDirection.y * state.placementDistance),
        z = origin.z + (normalizedDirection.z * state.placementDistance)
    }

    if not validVector(destination) then
        return nil, nil, 'camera_destination_invalid'
    end

    return {
        origin = origin,
        direction = normalizedDirection,
        destination = destination
    }, state.placementDistance
end

local function updatePreviewValues(result)
    local now = nowMilliseconds()
    local hadHit = result.hit
    state.lastHit = hadHit == true
    state.lastResultAt = now
    state.lastCoords = copyVector3(result.coords)
    state.lastNormal = copyVector3(result.normal)
    state.lastEntity = toNumber(result.entity, 0) or 0
    state.lastReason = result.reason
    state.lastValid = result.valid == true
    state.lastCoords = state.lastCoords
    state.lastNormal = state.lastNormal

    if hadHit then
        if Config and Config.Debug then
            if state.lastValid then
                debugPrint(('Preview valid reason=%s generation=%d'):format(tostring(state.lastReason), state.generation))
            else
                debugPrint(('Preview invalid reason=%s generation=%d'):format(tostring(state.lastReason), state.generation))
            end
        end
    else
        state.lastCoords = nil
        state.lastNormal = nil
        state.lastEntity = 0
    end
end

local function validateCandidate(hit, coords, normal, entity)
    local result = {
        valid = false,
        reason = 'no_hit'
    }

    if not hit then
        result.reason = 'no_hit'
        return result
    end

    if not validVector(coords) or not validVector(normal) then
        result.reason = 'invalid_geometry'
        return result
    end

    local ped = state.ped
    if not isFiniteNumber(ped) or not DoesEntityExist(ped) then
        result.reason = 'session_stale'
        return result
    end

    local pedPosition = GetEntityCoords(ped)
    local distance = vectorDistance(pedPosition, coords)
    if not isFiniteNumber(distance) then
        result.reason = 'distance_invalid'
        return result
    end
    if distance > state.placementDistance then
        result.reason = 'too_far'
        return result
    end

    if normal.z < state.minimumSurfaceNormalZ then
        result.reason = 'too_steep'
        return result
    end

    if entity and entity ~= 0 and DoesEntityExist(entity) then
        if IsEntityAPed(entity) then
            if entity == ped then
                result.reason = 'invalid_entity'
                return result
            end
            result.reason = 'hit_ped'
            return result
        end

        if IsEntityAVehicle(entity) then
            result.reason = 'hit_vehicle'
            return result
        end

        if Effects and Effects.getHeldFlare then
            local heldFlare = Effects.getHeldFlare()
            if heldFlare and entity == heldFlare then
                result.reason = 'held_flare'
                return result
            end
        end
    end

    result.valid = true
    result.reason = 'valid'
    return result
end

local function processShapeResult(status, hasHit, endCoords, normal, entityHit)
    local now = nowMilliseconds()
    local hit = isHitStatus(hasHit)
    local result = {
        hit = hit,
        coords = copyVector3(endCoords),
        normal = copyVector3(normal),
        entity = toNumber(entityHit, 0) or 0
    }

    local validated = validateCandidate(hit, result.coords, result.normal, result.entity)
    result.valid = validated.valid
    result.reason = validated.reason
    state.raycastState = RaycastState.COMPLETE
    updatePreviewValues(result)
    state.lastResultAt = now
    state.raycastCompletedAt = now
    clearShapeTest()
end

local function requestShapeTest()
    if not isSessionStillValid() then
        debugPrint(('Shape test ignored: stale session generation=%d'):format(state.generation))
        clearShapeTest()
        return
    end

    normalizePreviewEntry()

    local ray, maxDistance, rayError = getCameraRay()
    if not ray or maxDistance <= 0 then
        state.raycastState = RaycastState.INVALID
        updatePreviewValues({
            hit = false,
            coords = nil,
            normal = nil,
            entity = 0,
            reason = rayError or 'camera_ray_invalid'
        })
        debugPrint(('Shape test skipped: %s generation=%d'):format(tostring(rayError), state.generation))
        return
    end

    local flags = getFlags('RaycastFlags', 17)
    local optionFlags = getFlags('RaycastOptionFlags', 0)
    local ignoreEntity = state.ped
    if not ignoreEntity or ignoreEntity == 0 then
        ignoreEntity = PlayerPedId()
    end

    local handle = StartShapeTestLosProbe(
        ray.origin.x,
        ray.origin.y,
        ray.origin.z,
        ray.destination.x,
        ray.destination.y,
        ray.destination.z,
        flags,
        ignoreEntity,
        optionFlags
    )

    if type(handle) ~= 'number' or handle <= 0 then
        state.raycastState = RaycastState.INVALID
        updatePreviewValues({
            hit = false,
            coords = nil,
            normal = nil,
            entity = 0,
            reason = 'raycast_handle_invalid'
        })
        if Config and Config.Debug then
            debugPrint(('Shape test handle invalid generation=%d'):format(state.generation))
        end
        return
    end

    state.raycastHandle = handle
    state.raycastState = RaycastState.PENDING
    state.raycastStartedAt = nowMilliseconds()
    state.raycastRequestedAt = state.raycastStartedAt
    if Config and Config.Debug then
        debugPrint(('Shape test started handle=%s generation=%d'):format(tostring(handle), state.generation))
    end
end

local function updateRaycast()
    if not isSessionStillValid() then
        debugPrint(('Pending result ignored stale token generation=%d'):format(state.generation))
        clearShapeTest()
        return
    end

    if not state.raycastHandle or state.raycastHandle == 0 then
        return
    end

    local status, hit, endCoords, normal, entityHit = GetShapeTestResult(state.raycastHandle)
    if not isShapeTestComplete(status) then
        if (nowMilliseconds() - state.raycastStartedAt) >= state.shapeTestTimeoutMs then
            state.raycastState = RaycastState.TIMEOUT
            updatePreviewValues({
                hit = false,
                coords = nil,
                normal = nil,
                entity = 0,
                reason = 'raycast_timeout'
            })
            clearShapeTest()
            if Config and Config.Debug then
                debugPrint(('Raycast timeout generation=%d'):format(state.generation))
            end
        end
        return
    end

    processShapeResult(status, hit, endCoords, normal, entityHit)
    if Config and Config.Debug then
        debugPrint(('Raycast completed generation=%d reason=%s valid=%s'):format(
            state.generation,
            tostring(state.lastReason),
            tostring(state.lastValid)
        ))
    end
end

local function drawMarker()
    local previewConfig = getPreviewConfig()
    if not previewConfig.Enabled then
        return
    end
    if not state.lastHit or not state.lastCoords then
        return
    end

    local color = previewConfig.InvalidColor
    if state.lastValid then
        color = previewConfig.ValidColor
    end

    DrawMarker(
        previewConfig.Type,
        state.lastCoords.x,
        state.lastCoords.y,
        (state.lastCoords.z + previewConfig.HeightOffset),
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        previewConfig.Scale.x,
        previewConfig.Scale.y,
        previewConfig.Scale.z,
        color.r,
        color.g,
        color.b,
        color.a,
        false,
        false,
        2,
        false,
        nil,
        nil,
        false
    )
end

local function clearSelection()
    state.selection = nil
    state.selectionLocked = false
end

local function stopAndClear(reason)
    if not state.active then
        return
    end
    if Config and Config.Debug then
        debugPrint(('Placement.stopTargeting reason=%s generation=%d'):format(tostring(reason or 'unknown'), state.generation))
    end
    state.active = false
    state.mode = State.INACTIVE
    state.raycastState = RaycastState.NONE
    state.raycastHandle = 0
    state.lastHit = false
    state.lastCoords = nil
    state.lastNormal = nil
    state.lastEntity = 0
    state.lastReason = 'inactive'
    state.lastResultAt = nowMilliseconds()
    clearSelection()
    state.threadGeneration = state.threadGeneration + 1
    state.generation = state.generation + 1
end

local function isValidPreview()
    local now = nowMilliseconds()
    if not state.lastHit then
        return false
    end
    if not state.lastValid then
        return false
    end
    if (now - state.lastResultAt) > state.maxPreviewAgeMs then
        return false
    end
    return true
end

local function cloneSelection(selection)
    if not selection then
        return nil
    end
    return {
        coords = copyVector3(selection.coords),
        normal = copyVector3(selection.normal),
        entity = selection.entity,
        selectedAt = selection.selectedAt,
        sessionToken = selection.sessionToken,
        generation = selection.generation,
        selectionId = selection.selectionId
    }
end

function Placement.startTargeting(ped, sessionToken, isSessionValid, withoutPreview)
    normalizePreviewEntry()

    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false, 'invalid_ped'
    end

    if not sessionToken then
        return false, 'invalid_session'
    end

    if state.active and state.sessionToken == sessionToken and state.ped == ped then
        if isSessionStillValid() then
            return true, 'already_active'
        end
    end

    state.generation = state.generation + 1
    state.threadGeneration = state.threadGeneration + 1
    state.active = true
    state.mode = State.TARGETING
    state.sessionToken = sessionToken
    state.ped = ped
    state.isSessionValid = isSessionValid

    clearSelection()
    state.raycastHandle = 0
    state.raycastState = RaycastState.NONE
    state.raycastRequestedAt = 0
    state.raycastStartedAt = 0
    state.raycastCompletedAt = 0
    state.lastResultAt = 0
    state.lastHit = false
    state.lastReason = 'no_hit'
    state.lastValid = false
    state.lastCoords = nil
    state.lastNormal = nil
    state.lastEntity = 0

    if Config and Config.Debug then
        debugPrint(('Placement targeting started mode=%s token=%s'):format(state.mode, tostring(sessionToken)))
    end

    -- Direct placement keeps only the validated session; no aiming raycasts,
    -- marker drawing or preview thread runs while the player carries a flare.
    if withoutPreview then return true,nil end
    local runningGeneration = state.threadGeneration
    CreateThread(function()
        local lastRaycastAttempt = 0
        while state.active and runningGeneration == state.threadGeneration and state.mode == State.TARGETING do
            if not isSessionStillValid() then
                if Config and Config.Debug then
                    debugPrint(('Placement thread ended invalid session generation=%d'):format(runningGeneration))
                end
                break
            end

            if not state.raycastHandle or state.raycastHandle == 0 then
                if state.raycastState ~= RaycastState.PENDING then
                    local now = nowMilliseconds()
                    if now - lastRaycastAttempt >= state.shapeTestIntervalMs then
                        lastRaycastAttempt = now
                        requestShapeTest()
                    end
                end
            else
                updateRaycast()
            end

            drawMarker()
            Wait(0)
        end
        stopAndClear('thread_end')
    end)

    return true, nil
end

function Placement.stopTargeting(reason)
    stopAndClear(reason)
    return true
end

function Placement.clear(reason)
    stopAndClear(reason)
    return true
end

function Placement.isActive()
    return state.active == true
end

function Placement.getPreview()
    return {
        hasHit = state.lastHit == true,
        valid = state.lastValid == true,
        coords = copyVector3(state.lastCoords),
        normal = copyVector3(state.lastNormal),
        entity = isFiniteNumber(state.lastEntity) and state.lastEntity or 0,
        reason = state.lastReason
    }
end

function Placement.hasValidPreview()
    return isValidPreview()
end

-- Script integrations use the same validated selection path without aiming or
-- synthesizing mouse input. Server distance/slope/inventory checks still apply.
function Placement.selectPoint(coords,normal)
    if not state.active or state.mode~=State.TARGETING or not isSessionStillValid()then return nil,'not_active'end
    if state.selection then return nil,'selection_locked'end
    local p,n=copyVector3(coords),copyVector3(normal)
    if not p or not n then return nil,'invalid_preview'end
    local validation=validateCandidate(true,p,n,0)
    if not validation.valid then return nil,validation.reason end
    state.selectionSequence=state.selectionSequence+1
    state.selection={coords=p,normal=n,entity=0,selectedAt=nowMilliseconds(),
        sessionToken=state.sessionToken,generation=state.generation,selectionId=state.selectionSequence}
    state.selectionId=state.selectionSequence;state.selectionLocked=true
    return cloneSelection(state.selection)
end

function Placement.selectCurrentPoint()
    if not state.active or state.mode ~= State.TARGETING then
        return nil, 'not_active'
    end

    if not state.lastHit then
        return nil, state.lastReason or 'no_hit'
    end

    local now = nowMilliseconds()
    if (now - state.lastResultAt) > state.maxPreviewAgeMs then
        return nil, 'stale_preview'
    end

    if not isSessionStillValid() then
        if Config and Config.Debug then
            debugPrint(('Selection rejected stale token generation=%d'):format(state.generation))
        end
        return nil, 'stale_session'
    end

    if state.selection then
        return nil, 'selection_locked'
    end

    if not state.lastValid then
        return nil, state.lastReason or 'invalid_preview'
    end

    local currentCoords = copyVector3(state.lastCoords)
    local currentNormal = copyVector3(state.lastNormal)
    if not currentCoords or not currentNormal then
        return nil, 'invalid_preview'
    end

    local validation = validateCandidate(true, currentCoords, currentNormal, state.lastEntity)
    if not validation.valid then
        return nil, validation.reason
    end

    state.selection = {
        coords = currentCoords,
        normal = currentNormal,
        entity = toNumber(state.lastEntity, 0),
        selectedAt = now,
        sessionToken = state.sessionToken,
        generation = state.generation,
        selectionId = (state.selectionSequence + 1)
    }
    state.selectionSequence = state.selection.selectionId
    state.selectionId = state.selection.selectionId
    state.selectionLocked = true

    if Config and Config.Debug then
        debugPrint(('Selection created generation=%d'):format(state.generation))
    end
    return cloneSelection(state.selection), nil
end

function Placement.getSelection()
    return cloneSelection(state.selection)
end

function Placement.clearSelection()
    clearSelection()
end

function Placement.getState()
    return {
        active = state.active,
        mode = state.mode,
        generation = state.generation,
        sessionToken = state.sessionToken,
        hasSelection = state.selection ~= nil
    }
end
