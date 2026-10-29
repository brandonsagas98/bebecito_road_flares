RoadFlares = RoadFlares or {}
RoadFlares.Placing = RoadFlares.Placing or {}

local Placing = {}
RoadFlares.Placing = Placing

local Constants = RoadFlares.Constants or {}
local Utils = RoadFlares.Utils or {}
local Animations = (RoadFlares.Client and RoadFlares.Client.Animations) or nil
local Effects = (RoadFlares.Client and RoadFlares.Client.Effects) or nil

local InternalState = {
    INACTIVE = 'inactive',
    MOVING = 'moving',
    ORIENTING = 'orienting',
    ANIMATING = 'animating',
    COMPLETED = 'completed',
    FAILED = 'failed'
}

local SelectionMaxAgeMilliseconds = 5000
local ApproachEpsilon = 0.0001
local MovementHeartbeatMilliseconds = 300
local MovementHeartbeatMaxSamples = 20

local state = {
    active = false,
    internalState = InternalState.INACTIVE,
    expectedPed = nil,
    sessionToken = nil,
    selection = nil,
    selectionId = nil,
    expectedSelectionId = nil,
    onComplete = nil,
    isSessionValid = nil,
    target = nil,
    approach = nil,
    desiredHeading = nil,
    ownsMovementTask = false,
    ownsHeadingTask = false,
    suppressCallback = false,
    currentReason = nil,
    threadGeneration = 0,
    config = nil,
    startAt = 0,
    movementStartAt = 0,
    movementLastProgressAt = 0,
    movementLastProgressCoords = nil
}

local function debugPrint(message)
    Utils.debugPrint(message, Constants and Constants.ResourceName or 'bebecito_road_flares')
end

local function nowMilliseconds()
    return Utils.nowMilliseconds()
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

local function copyVector3(values)
    if type(values) ~= 'table' then
        return nil
    end
    return {
        x = toNumber(values.x, nil),
        y = toNumber(values.y, nil),
        z = toNumber(values.z, nil)
    }
end

local function isValidVector(values)
    return isFiniteNumber(values and values.x) and isFiniteNumber(values and values.y) and isFiniteNumber(values and values.z)
end

local function vectorDistance(a, b)
    if not isValidVector(a) or not isValidVector(b) then
        return nil
    end

    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function vectorDistanceFlat(a, b)
    if not isValidVector(a) or not isValidVector(b) then
        return nil
    end

    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt((dx * dx) + (dy * dy))
end

local function normalizeAngle(value)
    local normalized = value % 360.0
    if normalized < 0 then
        normalized = normalized + 360.0
    end
    return normalized
end

local function angleDelta(from, to)
    local delta = (to - from + 180.0) % 360.0 - 180.0
    if delta < 0 then
        delta = -delta
    end
    return delta
end

local function headingFromTo(fromCoords, toCoords)
    if not isValidVector(fromCoords) or not isValidVector(toCoords) then
        return nil
    end

    local dx = toCoords.x - fromCoords.x
    local dy = toCoords.y - fromCoords.y
    if dx == 0 and dy == 0 then
        return nil
    end

    -- GTA heading convention: 0 = north (+Y), 90 = east (+X), 180 = south (-Y), 270 = west (-X).
    return normalizeAngle((-math.deg(math.atan2(dy, dx))) + 90.0)
end

local function hasHeldFlare()
    if not Effects or not Effects.getHeldFlare then
        return false
    end
    return Effects.getHeldFlare() ~= nil
end

local function normalizeNumber(name, minValue, maxValue, fallback)
    local cfg = Config and Config.Placing or {}
    local value = toNumber(cfg[name], fallback)
    if minValue and value < minValue then
        value = minValue
    end
    if maxValue and value > maxValue then
        value = maxValue
    end
    return value
end

local function getPlacingConfig()
    return {
        WalkSpeed = normalizeNumber('WalkSpeed', 0.7, 2.0, 1.0),
        ArrivalDistance = normalizeNumber('ArrivalDistance', 0.35, 2.5, 0.85),
        PlacementOffsetDistance = normalizeNumber('PlacementOffsetDistance', 0.1, 1.8, 0.55),
        MovementTimeoutMilliseconds = normalizeNumber('MovementTimeoutMilliseconds', 500, 60000, 10000),
        StuckTimeoutMilliseconds = normalizeNumber('StuckTimeoutMilliseconds', 250, 20000, 2500),
        ProgressCheckMilliseconds = normalizeNumber('ProgressCheckMilliseconds', 20, 500, 100),
        MinimumProgressDistance = normalizeNumber('MinimumProgressDistance', 0.01, 2.0, 0.12),
        HeadingTimeoutMilliseconds = normalizeNumber('HeadingTimeoutMilliseconds', 250, 8000, 1500),
        HeadingToleranceDegrees = normalizeNumber('HeadingToleranceDegrees', 1.0, 90.0, 12.0),
        NavMeshFlags = toNumber((Config and Config.Placing and Config.Placing.NavMeshFlags), 0)
    }
end

local function setInternalState(nextState, reason)
    state.internalState = nextState
    state.currentReason = reason

    if Config and Config.Debug then
        debugPrint(('Placing internalState=%s reason=%s'):format(tostring(nextState), tostring(reason)))
    end
end

local function isCurrentPed()
    return state.expectedPed and state.expectedPed ~= 0 and DoesEntityExist(state.expectedPed)
end

local function isSessionContextValid()
    if state.suppressCallback then
        return false
    end
    if not state.active then
        return false
    end
    if state.sessionToken == nil then
        return false
    end
    if not isCurrentPed() then
        return false
    end
    if state.expectedPed ~= PlayerPedId() then
        return false
    end
    if IsEntityDead(state.expectedPed) then
        return false
    end
    if IsPedInAnyVehicle(state.expectedPed, false) then
        return false
    end
    if type(state.isSessionValid) == 'function' and not state.isSessionValid() then
        return false
    end
    return true
end

local function copySelection(input)
    if type(input) ~= 'table' then
        return nil
    end

    return {
        coords = copyVector3(input.coords),
        normal = copyVector3(input.normal),
        entity = toNumber(input.entity, 0) or 0,
        direct = input.direct == true,
        selectedAt = toNumber(input.selectedAt, 0) or 0,
        sessionToken = input.sessionToken,
        generation = toNumber(input.generation, 0) or 0,
        selectionId = toNumber(input.selectionId, 0) or 0
    }
end

local function getSelectionSnapshot()
    return copySelection(state.selection)
end

local function validateSelection(selection, generation)
    if generation ~= state.threadGeneration then
        return nil, 'session_stale'
    end

    if type(selection) ~= 'table' then
        return nil, 'selection_missing'
    end

    if not isValidVector(selection.coords) or not isValidVector(selection.normal) then
        return nil, 'selection_invalid'
    end

    if selection.selectionId == nil or selection.selectionId <= 0 then
        return nil, 'selection_stale'
    end

    if state.expectedSelectionId == nil or selection.selectionId ~= state.expectedSelectionId then
        return nil, 'selection_stale'
    end

    if not selection.sessionToken or selection.sessionToken ~= state.sessionToken then
        return nil, 'selection_stale'
    end

    if not isFiniteNumber(selection.generation) or selection.generation <= 0 then
        return nil, 'selection_stale'
    end

    local now = nowMilliseconds()
    if not isFiniteNumber(selection.selectedAt) or selection.selectedAt <= 0
        or now - selection.selectedAt > SelectionMaxAgeMilliseconds then
        return nil, 'selection_stale'
    end

    if not isSessionContextValid() then
        return nil, 'session_stale'
    end

    if not hasHeldFlare() then
        return nil, 'placed_flare_missing'
    end

    local placementDistance = toNumber((Config and Config.Distances and Config.Distances.Placement), 20.0) or 20.0
    local pedCoords = GetEntityCoords(state.expectedPed)
    local distanceToSelection = vectorDistance(pedCoords, selection.coords)
    if not isFiniteNumber(distanceToSelection) or distanceToSelection > placementDistance then
        return nil, 'placement_selection_too_far'
    end

    if not isFiniteNumber(selection.normal.x) or not isFiniteNumber(selection.normal.y) or not isFiniteNumber(selection.normal.z) then
        return nil, 'selection_invalid'
    end

    return selection, nil
end

local function clearNavigation(reason)
    if not isCurrentPed() then
        return
    end
    if not state.ownsMovementTask and not state.ownsHeadingTask then
        return
    end
    if Config and Config.Debug then
        debugPrint(('Placing clear navigation reason=%s'):format(tostring(reason)))
    end
    ClearPedTasks(state.expectedPed)
    state.ownsMovementTask = false
    state.ownsHeadingTask = false
end

local lastResult
local function completeFlow(threadGeneration, expectedSelectionId, result, reason)
    if threadGeneration ~= state.threadGeneration then
        return
    end
    if state.expectedSelectionId == nil or expectedSelectionId == nil then
        return
    end
    if state.expectedSelectionId ~= expectedSelectionId then
        return
    end
    if state.suppressCallback then
        return
    end

    local callback = state.onComplete
    if type(callback) ~= 'function' then
        return
    end

    lastResult={result=result,reason=reason}
    callback(result, reason)
end

local function computeApproachCoords(targetCoords, pedCoords, placementOffsetDistance)
    if not isValidVector(targetCoords) or not isValidVector(pedCoords) then
        return nil
    end

    local distance = vectorDistanceFlat(targetCoords, pedCoords)
    if not isFiniteNumber(distance) then
        return nil
    end

    if distance <= ApproachEpsilon then
        return {
            x = pedCoords.x,
            y = pedCoords.y,
            z = targetCoords.z
        }
    end

    local requestedOffset = toNumber(placementOffsetDistance, 0.0) or 0.0
    if requestedOffset <= 0 then
        return {
            x = targetCoords.x,
            y = targetCoords.y,
            z = targetCoords.z
        }
    end

    local effectiveOffset = math.min(requestedOffset, distance)
    local targetToPedX = pedCoords.x - targetCoords.x
    local targetToPedY = pedCoords.y - targetCoords.y
    local scale = 1.0 / distance
    local approachX = targetCoords.x + (targetToPedX * scale * effectiveOffset)
    local approachY = targetCoords.y + (targetToPedY * scale * effectiveOffset)
    if not isFiniteNumber(approachX) or not isFiniteNumber(approachY) then
        return nil
    end

    return {
        x = approachX,
        y = approachY,
        z = targetCoords.z
    }
end

local function computeHeadingToTarget(pedCoords, targetCoords)
    return headingFromTo(pedCoords, targetCoords)
end

local function waitForMovementResult(ped, approachCoords, config, threadGeneration)
    if not isFiniteNumber(config.ArrivalDistance) or not isFiniteNumber(config.MovementTimeoutMilliseconds) then
        return false, 'config_missing'
    end

    setInternalState(InternalState.MOVING, 'movement_started')
    state.ownsMovementTask = true
    state.ownsHeadingTask = false
    if Config and Config.Debug then
        debugPrint((
            'Placing movement native native=TaskFollowNavMeshToCoord ped=%s coords=(%.3f,%.3f,%.3f) '
            .. 'speed=%.2f timeout=-1 stoppingRange=0.0 persistFollowing=false unknown=0.0 navMeshFlags=%s'
        ):format(
            tostring(ped),
            approachCoords.x,
            approachCoords.y,
            approachCoords.z,
            config.WalkSpeed,
            tostring(config.NavMeshFlags)
        ))
    end
    TaskFollowNavMeshToCoord(
        ped,
        approachCoords.x,
        approachCoords.y,
        approachCoords.z,
        config.WalkSpeed,
        -1,
        0.0,
        0.0,
        0.0,
        config.NavMeshFlags
    )

    state.movementStartAt = nowMilliseconds()
    state.movementLastProgressAt = state.movementStartAt
    state.movementLastProgressCoords = copyVector3(GetEntityCoords(ped))

    local heartbeatSample = 0
    local heartbeatNextAt = state.movementStartAt
    local heartbeatPreviousDistance = vectorDistance(state.movementLastProgressCoords, approachCoords)

    local checkInterval = config.ProgressCheckMilliseconds
    if checkInterval < 20 then
        checkInterval = 20
    end

    while state.active and state.internalState == InternalState.MOVING and threadGeneration == state.threadGeneration do
        if not isSessionContextValid() then
            clearNavigation('session_stale')
            return false, 'session_stale'
        end

        local now = nowMilliseconds()
        local currentCoords = GetEntityCoords(ped)
        if not isValidVector(currentCoords) then
            return false, 'ped_invalid'
        end

        -- Ped origin is above the pavement; use horizontal arrival on the same floor.
        local toApproachDistance = vectorDistanceFlat(currentCoords, approachCoords)
        if math.abs(currentCoords.z - approachCoords.z) > 2.0 then
            toApproachDistance = math.huge
        end
        if not isFiniteNumber(toApproachDistance) then
            return false, 'distance_invalid'
        end

        if toApproachDistance <= config.ArrivalDistance then
            clearNavigation('movement_complete')
            return true, nil
        end

        local elapsed = now - state.movementStartAt
        if elapsed >= config.MovementTimeoutMilliseconds then
            clearNavigation('movement_timeout')
            return false, 'movement_timeout'
        end

        if state.movementLastProgressCoords then
            local progressDistance = vectorDistance(currentCoords, state.movementLastProgressCoords)
            if isFiniteNumber(progressDistance) and progressDistance >= config.MinimumProgressDistance then
                state.movementLastProgressCoords = copyVector3(currentCoords)
                state.movementLastProgressAt = now
                if Config and Config.Debug then
                    debugPrint(('Placing progress moved %.3f'):format(progressDistance))
                end
            end
        end

        if Config and Config.Debug and heartbeatSample < MovementHeartbeatMaxSamples and now >= heartbeatNextAt then
            heartbeatSample = heartbeatSample + 1
            local previousDistance = heartbeatPreviousDistance
            local distanceDelta = isFiniteNumber(previousDistance) and (previousDistance - toApproachDistance) or 0.0
            local pedSpeed = GetEntitySpeed(ped)
            local pedStill = IsPedStill(ped)
            debugPrint((
                'Placing movement heartbeat sample=%d selectionId=%s ped=%s '
                .. 'pedCoords=(%.3f,%.3f,%.3f) targetCoords=(%.3f,%.3f,%.3f) '
                .. 'approachCoords=(%.3f,%.3f,%.3f) distanceToApproach=%.3f '
                .. 'previousDistance=%.3f distanceDelta=%.3f pedSpeed=%.3f isPedStill=%s '
                .. 'taskStatus=not_sampled elapsedMs=%d timeSinceLastProgressMs=%d '
                .. 'progressThreshold=%.3f stuckThresholdMs=%d arrivalRadius=%.3f'
            ):format(
                heartbeatSample,
                tostring(state.selectionId),
                tostring(ped),
                currentCoords.x,
                currentCoords.y,
                currentCoords.z,
                state.target.x,
                state.target.y,
                state.target.z,
                approachCoords.x,
                approachCoords.y,
                approachCoords.z,
                toApproachDistance,
                previousDistance or toApproachDistance,
                distanceDelta,
                pedSpeed,
                tostring(pedStill),
                elapsed,
                now - state.movementLastProgressAt,
                config.MinimumProgressDistance,
                config.StuckTimeoutMilliseconds,
                config.ArrivalDistance
            ))
            heartbeatPreviousDistance = toApproachDistance
            heartbeatNextAt = now + MovementHeartbeatMilliseconds
        end

        if now - state.movementLastProgressAt >= config.StuckTimeoutMilliseconds then
            clearNavigation('movement_stuck')
            return false, 'movement_stuck'
        end

        Wait(checkInterval)
    end

    return false, 'placement_interrupted'
end

local function waitForHeading(ped, targetCoords, config, threadGeneration)
    local pedCoords = GetEntityCoords(ped)
    if not isValidVector(pedCoords) then
        return false, 'ped_invalid'
    end

    local desiredHeading = computeHeadingToTarget(pedCoords, targetCoords)
    if not isFiniteNumber(desiredHeading) then
        return false, 'heading_invalid'
    end

    state.desiredHeading = desiredHeading
    setInternalState(InternalState.ORIENTING, 'heading_started')
    state.ownsHeadingTask = true
    state.ownsMovementTask = false
    TaskAchieveHeading(ped, desiredHeading, config.HeadingTimeoutMilliseconds)

    local checkInterval = config.ProgressCheckMilliseconds
    if checkInterval < 20 then
        checkInterval = 20
    end

    local timeoutAt = nowMilliseconds() + config.HeadingTimeoutMilliseconds
    while threadGeneration == state.threadGeneration and state.active and state.internalState == InternalState.ORIENTING and nowMilliseconds() <= timeoutAt do
        if not isSessionContextValid() then
            clearNavigation('session_stale')
            return false, 'session_stale'
        end

        local currentHeading = GetEntityHeading(ped)
        if isFiniteNumber(currentHeading) then
            local delta = angleDelta(currentHeading, desiredHeading)
            if delta <= config.HeadingToleranceDegrees then
                clearNavigation('heading_complete')
                return true, nil
            end
        end

        Wait(checkInterval)
    end

    if not state.active or state.internalState ~= InternalState.ORIENTING then
        return false, 'placement_interrupted'
    end

    if not isSessionContextValid() then
        clearNavigation('session_stale')
        return false, 'session_stale'
    end

    local finalHeading = GetEntityHeading(ped)
    if not isFiniteNumber(finalHeading) then
        return false, 'ped_invalid'
    end

    local finalDelta = angleDelta(finalHeading, desiredHeading)
    if finalDelta <= config.HeadingToleranceDegrees then
        clearNavigation('heading_complete')
        return true, nil
    end

    clearNavigation('heading_failed')
    return false, 'heading_failed'
end

local function runPlacementAnimation(ped, config, threadGeneration)
    if not Animations or not Animations.playPlace then
        return false, 'place_animation_unavailable'
    end
    setInternalState(InternalState.ANIMATING, 'animation_started')

    if not isSessionContextValid() then
        return false, 'session_stale'
    end

    local played, reason = Animations.playPlace(ped, state.sessionToken, state.isSessionValid, state.target)
    if not played then
        return false, reason or 'place_animation_failed'
    end

    if not isSessionContextValid() then
        return false, 'session_stale'
    end

    if config then
        local finalPedCoords = GetEntityCoords(ped)
        local distanceToTarget = vectorDistanceFlat(finalPedCoords, state.target)
        if math.abs(finalPedCoords.z - state.target.z) > 2.0 then
            return false, 'placement_complete_distance'
        end
        if not isFiniteNumber(distanceToTarget) or distanceToTarget > (config.ArrivalDistance * 2.0) then
            return false, 'placement_complete_distance'
        end
    end

    if threadGeneration ~= state.threadGeneration then
        return false, 'session_stale'
    end

    return true, nil
end

local function sequenceLoop(threadGeneration)
    if threadGeneration ~= state.threadGeneration then
        return
    end

    local ped = state.expectedPed
    local cfg = state.config or getPlacingConfig()
    state.config = cfg

    if not isSessionContextValid() then
        completeFlow(threadGeneration, state.expectedSelectionId, 'failed', 'session_stale')
        clearNavigation('session_invalid')
        state.active = false
        state.internalState = InternalState.INACTIVE
        return
    end

    local selection, selectionError = validateSelection(getSelectionSnapshot(), threadGeneration)
    if not selection then
        completeFlow(threadGeneration, state.expectedSelectionId, 'failed', selectionError or 'selection_invalid')
        clearNavigation(selectionError)
        state.active = false
        state.internalState = InternalState.INACTIVE
        return
    end
    local expectedSelectionId = selection.selectionId

    local pedCoords = GetEntityCoords(ped)
    if not isValidVector(pedCoords) then
        completeFlow(threadGeneration, expectedSelectionId, 'failed', 'ped_invalid')
        clearNavigation('ped_invalid')
        state.active = false
        state.internalState = InternalState.INACTIVE
        return
    end

    local targetDistance = vectorDistanceFlat(pedCoords, selection.coords)
    if not isFiniteNumber(targetDistance) then
        completeFlow(threadGeneration, expectedSelectionId, 'failed', 'distance_invalid')
        clearNavigation('distance_invalid')
        state.active = false
        state.internalState = InternalState.INACTIVE
        return
    end

    if selection.direct and targetDistance > .85 then
        completeFlow(threadGeneration, expectedSelectionId, 'failed', 'placement_selection_too_far')
        state.active=false
        state.internalState=InternalState.INACTIVE
        return
    end
    if not selection.direct and targetDistance > cfg.ArrivalDistance then
        if Config and Config.Debug then
            debugPrint(('Placing movement target selection=%s target=(%.3f,%.3f,%.3f)'):format(
                tostring(state.selectionId),
                selection.coords.x,
                selection.coords.y,
                selection.coords.z
            ))
        end
    end

    if targetDistance > toNumber((Config and Config.Distances and Config.Distances.Placement), 20.0) then
        completeFlow(threadGeneration, expectedSelectionId, 'failed', 'placement_selection_too_far')
        clearNavigation('selection_too_far')
        state.active = false
        state.internalState = InternalState.INACTIVE
        return
    end

    local approachCoords = computeApproachCoords(selection.coords, pedCoords, cfg.PlacementOffsetDistance)
    if not approachCoords then
        completeFlow(threadGeneration, expectedSelectionId, 'failed', 'approach_invalid')
        clearNavigation('approach_invalid')
        state.active = false
        state.internalState = InternalState.INACTIVE
        return
    end

    state.approach = copyVector3(approachCoords)
    state.target = copyVector3(selection.coords)
    state.selection = selection

    if Config and Config.Debug then
        debugPrint(('Placing start selectionId=%s approach=(%.3f,%.3f,%.3f)'):format(
            tostring(state.selectionId),
            approachCoords.x,
            approachCoords.y,
            approachCoords.z
        ))
    end

    if not selection.direct and targetDistance > cfg.ArrivalDistance then
        local moved, reason = waitForMovementResult(ped, approachCoords, cfg, threadGeneration)
        if not moved then
            completeFlow(threadGeneration, expectedSelectionId, 'failed', reason or 'movement_failed')
            state.active = false
            state.internalState = InternalState.INACTIVE
            return
        end
        if Config and Config.Debug then
            debugPrint(('Placing movement completed selectionId=%s'):format(tostring(state.selectionId)))
        end
    else
        clearNavigation('already_near')
    end

    if not isSessionContextValid() then
        completeFlow(threadGeneration, expectedSelectionId, 'failed', 'session_stale')
        clearNavigation('session_invalid')
        state.active = false
        state.internalState = InternalState.INACTIVE
        return
    end

    local headingDone, headingError = true,nil
    if not selection.direct then
        headingDone,headingError=waitForHeading(ped, selection.coords, cfg, threadGeneration)
    end
    if not headingDone then
        completeFlow(threadGeneration, expectedSelectionId, 'failed', headingError or 'heading_failed')
        state.active = false
        state.internalState = InternalState.INACTIVE
        return
    end

    if not isSessionContextValid() then
        completeFlow(threadGeneration, expectedSelectionId, 'failed', 'session_stale')
        state.active = false
        state.internalState = InternalState.INACTIVE
        return
    end

    local animated, animationError = runPlacementAnimation(ped, cfg, threadGeneration)
    if not animated then
        completeFlow(threadGeneration, expectedSelectionId, 'failed', animationError or 'placement_animation_failed')
        state.active = false
        state.internalState = InternalState.INACTIVE
        return
    end

    local finalSelection = getSelectionSnapshot()
    if not finalSelection or threadGeneration ~= state.threadGeneration then
        completeFlow(threadGeneration, expectedSelectionId, 'failed', 'selection_missing')
        state.active = false
        state.internalState = InternalState.INACTIVE
        return
    end

    if not isSessionContextValid() then
        completeFlow(threadGeneration, expectedSelectionId, 'failed', 'session_stale')
        state.active = false
        state.internalState = InternalState.INACTIVE
        return
    end

    setInternalState(InternalState.COMPLETED, 'complete')
    if Config and Config.Debug then
        debugPrint(('Placing complete selectionId=%s'):format(tostring(state.selectionId)))
    end
    state.active = false
    state.internalState = InternalState.INACTIVE
    completeFlow(threadGeneration, expectedSelectionId, 'completed', nil)
end

function Placing.start(ped, selection, sessionToken, isSessionValid, onComplete)
    if state.active then
        return false, 'already_active'
    end
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false, 'invalid_ped'
    end
    if IsEntityDead(ped) then
        return false, 'player_died'
    end
    if IsPedInAnyVehicle(ped, false) then
        return false, 'entered_vehicle'
    end
    if type(onComplete) ~= 'function' then
        return false, 'missing_callback'
    end

    local normalizedSelection = copySelection(selection)
    if not normalizedSelection then
        return false, 'selection_missing'
    end

    local hasValidToken = isFiniteNumber(sessionToken) or type(sessionToken) == 'string'
    if not hasValidToken then
        return false, 'session_missing'
    end

    local cfg = getPlacingConfig()
    local threadGeneration = state.threadGeneration + 1

    state.threadGeneration = threadGeneration
    state.config = cfg
    state.active = true
    state.suppressCallback = false
    state.expectedPed = ped
    state.sessionToken = sessionToken
    state.selection = normalizedSelection
    state.selectionId = normalizedSelection.selectionId
    state.expectedSelectionId = normalizedSelection.selectionId
    state.onComplete = onComplete
    state.isSessionValid = isSessionValid
    state.currentReason = nil
    state.target = nil
    state.approach = nil
    state.desiredHeading = nil
    state.ownsMovementTask = false
    state.ownsHeadingTask = false
    state.startAt = nowMilliseconds()
    state.movementStartAt = 0
    state.movementLastProgressAt = 0
    state.movementLastProgressCoords = nil
    setInternalState(InternalState.INACTIVE, 'start')

    if isSessionContextValid() == false then
        local reason = 'session_stale'
        clearNavigation(reason)
        state.active = false
        state.internalState = InternalState.INACTIVE
        return false, reason
    end

    CreateThread(function()
        sequenceLoop(threadGeneration)
    end)

    return true, nil
end

function Placing.cancel(reason)
    if not state.active then
        return false, 'inactive'
    end

    state.suppressCallback = true
    clearNavigation(reason or 'placing_cancelled')
    if Animations and Animations.cancel then
        Animations.cancel('placing_cancelled')
    end

    state.active = false
    state.internalState = InternalState.INACTIVE
    state.expectedSelectionId = nil
    state.selection = nil
    state.target = nil
    state.approach = nil
    state.desiredHeading = nil
    state.ownsMovementTask = false
    state.ownsHeadingTask = false
    state.movementLastProgressAt = 0
    state.movementLastProgressCoords = nil
    state.currentReason = reason
    state.threadGeneration = state.threadGeneration + 1
    return true, nil
end

function Placing.clear(reason)
    if not state.active and state.internalState == InternalState.INACTIVE then
        return false, 'inactive'
    end

    state.suppressCallback = true
    clearNavigation(reason or 'placing_clear')
    if Animations and Animations.cancel then
        Animations.cancel('placing_clear')
    end

    state.active = false
    state.internalState = InternalState.INACTIVE
    state.expectedSelectionId = nil
    state.selection = nil
    state.target = nil
    state.approach = nil
    state.desiredHeading = nil
    state.ownsMovementTask = false
    state.ownsHeadingTask = false
    state.movementLastProgressAt = 0
    state.movementLastProgressCoords = nil
    state.currentReason = reason
    state.threadGeneration = state.threadGeneration + 1
    return true, nil
end

function Placing.isActive()
    return state.active == true
end

function Placing.getState()
    return {
        active = state.active,
        state = state.internalState,
        sessionToken = state.sessionToken,
        selectionId = state.selectionId,
        reason = state.currentReason,
        lastResult = lastResult and {result=lastResult.result,reason=lastResult.reason} or nil
    }
end

function Placing.getSessionToken()
    return state.sessionToken
end

function Placing.getTarget()
    return copyVector3(state.target)
end
