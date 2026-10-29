RoadFlares = RoadFlares or {}
RoadFlares.Client = RoadFlares.Client or {}

local Deployment = {}
RoadFlares.Client.Deployment = Deployment

local Constants = RoadFlares.Constants
local Utils = RoadFlares.Utils
local pendingIgnition = {}
local activeIgnitionRequest
local burnEndsAt
RegisterNetEvent(Constants.Events.Client.IgnitionResult, function(payload)
    if type(payload)=='table' and payload.requestId==pendingIgnition.requestId then
        pendingIgnition.response=payload
    end
end)

local function getEffectsModule()
    if RoadFlares.Client and RoadFlares.Client.Effects then
        return RoadFlares.Client.Effects
    end
    return nil
end

local function getAnimationsModule()
    if RoadFlares.Client and RoadFlares.Client.Animations then
        return RoadFlares.Client.Animations
    end
    return nil
end

local function getVisualsModule()
    if RoadFlares.Visuals then
        return RoadFlares.Visuals
    end
    return nil
end

local function getPlacementModule()
    if RoadFlares.Placement then
        return RoadFlares.Placement
    end
    return nil
end

local function getPlacingModule()
    if RoadFlares.Placing then
        return RoadFlares.Placing
    end
    return nil
end

local function getAudioModule()
    if RoadFlares.Audio then
        return RoadFlares.Audio
    end
    return nil
end

local function getWorldFlaresModule()
    if RoadFlares.WorldFlares then
        return RoadFlares.WorldFlares
    end
    return nil
end

local function getGroundVisualsModule()
    if RoadFlares.GroundVisuals then
        return RoadFlares.GroundVisuals
    end
    return nil
end

local state = Constants.States.IDLE
local session = {
    token = nil,
    method = nil,
    startedAt = nil,
    timeoutAt = nil,
    ped = nil
}
local pendingAuthorization = {
    requestId = nil,
    requestToken = nil,
    startedAt = nil,
    timeoutAt = nil
}

local loopToken = 0
local requestCounter = 0
local notifiedReasons = {}
local confirmPressedBlocked = false
local placementSelectPressed = false
local stoppingState = {
    isVoluntary = false,
    reason = nil,
    timeoutAt = nil
}
local commitState = {
    requestId = nil,
    payload = nil,
    selection = nil,
    retriesRemaining = 0,
    maxRetries = 0,
    startedAt = nil,
    timeoutAt = nil,
    requestTimeout = 0,
    ownerServerId = nil
}

local transitionRules = {
    [Constants.States.IDLE] = {
        [Constants.States.AUTHORIZING] = true
    },
    [Constants.States.AUTHORIZING] = {
        [Constants.States.EQUIPPING] = true,
        [Constants.States.IDLE] = true
    },
    [Constants.States.EQUIPPING] = {
        [Constants.States.EQUIPPED_UNLIT] = true,
        [Constants.States.STOPPING] = true,
        [Constants.States.IDLE] = true
    },
    [Constants.States.EQUIPPED_UNLIT] = {
        [Constants.States.IGNITING] = true,
        [Constants.States.STOPPING] = true
    },
    [Constants.States.IGNITING] = {
        [Constants.States.DEPLOYMENT_READY] = true,
        [Constants.States.STOPPING] = true,
        [Constants.States.IDLE] = true
    },
    [Constants.States.DEPLOYMENT_READY] = {
        [Constants.States.PLACING] = true,
        [Constants.States.COMMITTING] = true,
        [Constants.States.STOPPING] = true
    },
    [Constants.States.PLACING] = {
        [Constants.States.COMMITTING] = true,
        [Constants.States.DEPLOYMENT_READY] = true,
        [Constants.States.STOPPING] = true,
        [Constants.States.IDLE] = true
    },
    [Constants.States.COMMITTING] = {
        [Constants.States.DEPLOYMENT_READY] = true,
        [Constants.States.STOPPING] = true,
        [Constants.States.IDLE] = true
    },
    [Constants.States.STOPPING] = {
        [Constants.States.IDLE] = true
    }
}

local function debugPrint(message)
    Utils.debugPrint(message, Constants.ResourceName)
end

local function toNumber(value)
    local number = tonumber(value)
    if type(number) ~= 'number' or number ~= number then
        return nil
    end
    return number
end

local function shortToken(value)
    if type(value) ~= 'string' then
        return tostring(value)
    end
    local trimmed = value:gsub('%s+', '')
    if #trimmed <= 16 then
        return trimmed
    end
    return trimmed:sub(1, 8) .. '...'
end

local function notify(messageKey, fallback)
    local message = Utils.localize(messageKey)
    if message == messageKey then
        message = fallback or messageKey
    end
    if RoadFlares.Presentation then RoadFlares.Presentation.notify(message); return end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

local function notifyOnce(reasonKey)
    local now = Utils.nowMilliseconds()
    local last = notifiedReasons[reasonKey]
    if last and (now - last) < 1000 then
        return
    end
    notify(reasonKey, Utils.localize('unknown_error'))
    notifiedReasons[reasonKey] = now
end

local function clearNotifications()
    notifiedReasons = {}
end

local function clearPlacementCommit()
    commitState.requestId = nil
    commitState.payload = nil
    commitState.selection = nil
    commitState.retriesRemaining = 0
    commitState.maxRetries = 0
    commitState.startedAt = nil
    commitState.timeoutAt = nil
    commitState.requestTimeout = 0
    commitState.ownerServerId = nil
end

local function clearPendingAuthorization()
    pendingAuthorization.requestId = nil
    pendingAuthorization.requestToken = nil
    pendingAuthorization.startedAt = nil
    pendingAuthorization.timeoutAt = nil
end

local function isCurrentPendingAuthorization(requestId, requestToken)
    return pendingAuthorization.requestId == requestId and pendingAuthorization.requestToken == requestToken and pendingAuthorization.requestId ~= nil and requestToken ~= nil
end

local function requestMethodAllowed(method)
    return Utils.isActivationMethodEnabled(method)
end

local function makeRequestId()
    requestCounter = requestCounter + 1
    return ('rf-%d-%s'):format(Utils.nowMilliseconds(), requestCounter)
end

local function makePlacementRequestId()
    local now = Utils.nowMilliseconds()
    local randomSeed = now % 100000
    local suffix = tostring(math.random(0, 999999))
    requestCounter = requestCounter + 1
    return ('pl-%s-%s-%d'):format(tostring(now + randomSeed), suffix, requestCounter)
end

local function showHelp(messageKeyPrimary, messageKeySecondary)
    local message = Utils.localize(messageKeyPrimary)
    if messageKeySecondary then
        message = ('%s\n%s'):format(message, Utils.localize(messageKeySecondary))
    end
    if RoadFlares.Presentation then RoadFlares.Presentation.prompt(message); return end
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

local function getOwnedActiveCount()
    local WorldFlares = getWorldFlaresModule()
    if not WorldFlares or not WorldFlares.getOwnedActiveCount then
        return nil
    end
    return WorldFlares.getOwnedActiveCount()
end

local function getMaxActive()
    local maxActive = toNumber(Config.MaxActiveFlaresPerPlayer)
    if not maxActive then
        return 0
    end
    return maxActive
end

local function clampServerCount(value)
    local current = getOwnedActiveCount()
    local maxActive = getMaxActive()
    local nextValue = toNumber(value)
    if nextValue == nil then
        return current
    end
    if nextValue < 0 then
        return 0
    end
    if maxActive > 0 and nextValue > maxActive then
        return maxActive
    end
    return math.floor(nextValue + 0.000001)
end

local function showPlacementHelp()
    showHelp('placement_prompt_ready')
end

local function clearHeldFlare(reason)
    local Effects = getEffectsModule()
    if Config and Config.Debug then
        local details = Effects and Effects.getHeldFlareDiagnostics and Effects.getHeldFlareDiagnostics(session.ped) or {}
        debugPrint(('Held cleanup callback=clearHeldFlare reason=%s state=%s sessionToken=%s loopToken=%s ped=%s currentPed=%s held=%s exists=%s attached=%s heldToken=%s'):format(
            tostring(reason or 'unknown'),
            tostring(state),
            tostring(session.token),
            tostring(loopToken),
            tostring(session.ped),
            tostring(PlayerPedId()),
            tostring(details.handle),
            tostring(details.exists),
            tostring(details.attached),
            tostring(details.sessionToken)
        ))
    end
    if Effects and Effects.clear then
        Effects.clear(reason)
    elseif Effects and Effects.removeHeldFlare then
        Effects.removeHeldFlare(reason)
    end
end

local function clearAnimations(reason)
    local Animations = getAnimationsModule()
    if Animations and Animations.clear then
        Animations.clear(reason)
    end
end

local function clearVisuals(reason, preserveResidualSmoke)
    local Visuals = getVisualsModule()
    if Visuals and Visuals.clear then
        Visuals.clear(reason, preserveResidualSmoke == true)
    end
end

local function allowsResidualSmoke(reason)
    return reason ~= 'resource_stop'
        and reason ~= 'session_invalidating'
        and reason ~= 'session_replaced'
end

local function clearAudio(reason)
    local Audio = getAudioModule()
    if not Audio then
        return
    end
    if Audio.clear then
        Audio.clear(reason)
    end
end

local function isGracefulStop(reason, sourceState)
    sourceState = sourceState or state
    if reason == 'deployment_saved' then
        return true
    end

    if reason == 'toggle' and sourceState == Constants.States.DEPLOYMENT_READY then
        local Visuals = getVisualsModule()
        if Visuals and Visuals.isActive then
            return Visuals.isActive()
        end
    end

    return false
end

local function gracefulStopWaitMilliseconds()
    local fallback = 450
    local configValue = Config and Config.FlareVisuals and Config.FlareVisuals.StopRampMilliseconds
    if type(configValue) == 'number' and configValue == configValue then
        return configValue
    end
    return fallback
end

local function clearSession()
    if activeIgnitionRequest then
        TriggerServerEvent('bebecito_road_flares:server:discardIgnition',{requestId=activeIgnitionRequest})
        activeIgnitionRequest=nil
    end
    pendingIgnition = {}
    burnEndsAt = nil
    session.method = nil
    session.token = nil
    session.startedAt = nil
    session.timeoutAt = nil
    session.ped = nil
    clearPendingAuthorization()
    confirmPressedBlocked = false
    placementSelectPressed = false
    clearPlacementCommit()
end

local function clearPlacement(reason)
    local Placement = getPlacementModule()
    if not Placement then
        return false
    end
    if Placement.stopTargeting then
        return Placement.stopTargeting(reason)
    end
    if Placement.clear then
        return Placement.clear(reason)
    end
    return false
end

local function clearPlacing(reason)
    local Placing = getPlacingModule()
    if not Placing then
        return false
    end
    if Placing.cancel then
        return Placing.cancel(reason)
    end
    if Placing.clear then
        return Placing.clear(reason)
    end
    return false
end

local function sanitizeVector(value)
    if not value then
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

local function isPlacingFailureCritical(reason)
    if reason == 'player_died' or reason == 'entered_vehicle' or reason == 'ped_changed' or reason == 'session_stale' then
        return true
    end
    if reason == 'placed_flare_missing' or reason == 'selection_missing' then
        return true
    end
    return false
end

local function shouldIgnorePlacingFailure(reason)
    return reason == 'selection_stale'
end

local function commitPayload()
    local selection = commitState.payload
    if type(selection) ~= 'table' then
        return nil
    end
    local worldSafeCoords = sanitizeVector(selection.coords)
    local worldSafeNormal = sanitizeVector(selection.normal)
    if not worldSafeCoords or not worldSafeNormal then
        return nil
    end

    local requestId = commitState.requestId
    if type(requestId) ~= 'string' or requestId == '' then
        return nil
    end

    local selectionId = selection.selectionId
    if type(selectionId) ~= 'number' and type(selectionId) ~= 'string' then
        selectionId = 0
    else
        selectionId = toNumber(selectionId) or 0
    end

    return {
        requestId = requestId,
        selectionId = selectionId,
        coords = worldSafeCoords,
        normal = worldSafeNormal
    }
end

local function sendPlacementCommit()
    local payload = commitPayload()
    if not payload then
        transitionTo(Constants.States.DEPLOYMENT_READY, 'selection_stale')
        return
    end

    TriggerServerEvent(Constants.Events.Server.RequestPlaceFlare, payload)
    if Config and Config.Debug then
        debugPrint(('Placement commit sent request=%s'):format(tostring(payload.requestId)))
    end
end

local function finalizePlacementCommit(success, payload)
    local WorldFlares = getWorldFlaresModule()
    local requestId = commitState.requestId

    if state ~= Constants.States.COMMITTING then
        return
    end
    if not requestId then
        return
    end
    if type(payload) ~= 'table' then
        payload = nil
        success = false
    end

    local responseRequestId = Utils.sanitizeRequestId(payload and payload.requestId)
    if not responseRequestId or responseRequestId ~= requestId then
        if Config and Config.Debug then
            debugPrint(('Ignoring stale place flare result req=%s activeReq=%s'):format(
                tostring(payload and payload.requestId),
                tostring(requestId)
            ))
        end
        return
    end

    if success then
        local owner = GetPlayerServerId(PlayerId())
        if WorldFlares then
            local recordCoords = commitState.payload and commitState.payload.coords
            local recordNormal = commitState.payload and commitState.payload.normal
            local record = {
                flareId = payload.flareId,
                netId = toNumber(payload.netId),
                ownerServerId = toNumber(owner),
                coords = sanitizeVector(recordCoords),
                normal = sanitizeVector(recordNormal),
                status = 'active',
                tipLength = toNumber(payload.tipLength),
                burnStage = toNumber(payload.burnStage),
                routingBucket = toNumber(payload.routingBucket)
            }
            local upserted = WorldFlares.add(record)
            if upserted then
                local GroundVisuals = getGroundVisualsModule()
                if GroundVisuals and GroundVisuals.upsert then
                    GroundVisuals.upsert(record)
                end

                if payload.activeCount ~= nil then
                    WorldFlares.setOwnedActiveCount(clampServerCount(payload.activeCount))
                end
            end
        end

        debugPrint(('Placement commit success request=%s flareId=%s'):format(tostring(requestId), tostring(payload and payload.flareId)))
        clearPlacementCommit()
        if (Config.Realism and Config.Realism.ConsumeOnIgnition) or toNumber(payload.remainingItems) == 0 then
            transitionTo(Constants.States.STOPPING, 'items_exhausted')
            return
        end
        transitionTo(Constants.States.DEPLOYMENT_READY, 'placement_committed')
        return
    end

    local reason = type(payload and payload.reason) == 'string' and payload.reason or 'unknown_error'
    local activeCount = toNumber(payload and payload.activeCount)
    if activeCount then
        WorldFlares.setOwnedActiveCount(clampServerCount(activeCount))
    end

    if reason == 'duplicate_request_processing' then
        return
    end

    if reason == 'limit_reached' then
        notifyOnce('flare_limit_reached')
        transitionTo(Constants.States.STOPPING, reason)
        return
    end

    if reason == 'rate_limited' or reason == 'invalid_coordinates' or reason == 'invalid_normal' or reason == 'spawn_failed' then
        notifyOnce(reason)
        clearPlacementCommit()
        transitionTo(Constants.States.DEPLOYMENT_READY, reason)
        return
    end

    if reason == 'too_far' then
        notifyOnce('flare_placing_unreachable')
        clearPlacementCommit()
        transitionTo(Constants.States.DEPLOYMENT_READY, reason)
        return
    end

    if reason == 'placement_commit_timeout' then
        notifyOnce('placement_commit_timeout')
        clearPlacementCommit()
        transitionTo(Constants.States.DEPLOYMENT_READY, reason)
        return
    end

    if reason == 'invalid_request' or reason == 'invalid_player' or reason == 'registry_failed' then
        notifyOnce('flare_placement_server_failed')
        clearPlacementCommit()
        transitionTo(Constants.States.STOPPING, reason)
        return
    end

    if reason == 'routing_bucket_changed' then
        clearPlacementCommit()
        transitionTo(Constants.States.STOPPING, 'session_invalidating')
        return
    end

    if reason == 'missing_flare_item' or reason == 'inventory_unavailable' or reason == 'session_expired' then
        clearPlacementCommit()
        notifyOnce(reason)
        transitionTo(Constants.States.STOPPING, 'session_invalidating')
        return
    end

    if reason == 'session_stale' or reason == 'selection_stale' then
        clearPlacementCommit()
        transitionTo(Constants.States.DEPLOYMENT_READY, reason)
        return
    end

    clearPlacementCommit()
    notifyOnce(reason)
    transitionTo(Constants.States.DEPLOYMENT_READY, reason)
end

function Deployment.handlePlaceFlareResult(payload)
    if state ~= Constants.States.COMMITTING then
        if Config and Config.Debug then
            debugPrint(('Ignoring stale place flare result while in state=%s'):format(tostring(state)))
        end
        return
    end

    if type(payload) ~= 'table' then
        debugPrint('Placement result ignored: invalid payload')
        notifyOnce('flare_placement_server_failed')
        clearPlacementCommit()
        transitionTo(Constants.States.DEPLOYMENT_READY, 'placement_result_invalid')
        return
    end

    local responseRequestId = Utils.sanitizeRequestId(payload.requestId)
    if not responseRequestId then
        debugPrint('Placement result ignored: invalid requestId')
        notifyOnce('flare_placement_server_failed')
        clearPlacementCommit()
        transitionTo(Constants.States.DEPLOYMENT_READY, 'placement_result_invalid')
        return
    end

    if responseRequestId ~= commitState.requestId then
        if Config and Config.Debug then
            debugPrint(('Ignoring stale place flare response id=%s expected=%s'):format(
                tostring(responseRequestId),
                tostring(commitState.requestId)
            ))
        end
        return
    end

    local success = payload.success == true
    finalizePlacementCommit(success, payload)
end

local function startPlacement(selection)
    local Placing = getPlacingModule()
    if not Placing then
        return false, 'placing_module_missing'
    end
    if not Placing.start then
        return false, 'placing_module_incomplete'
    end
    if type(selection) ~= 'table' then
        return false, 'selection_missing'
    end
    if state ~= Constants.States.DEPLOYMENT_READY then
        return false, 'invalid_state'
    end

    local sessionToken = session.token
    if not sessionToken then
        return false, 'session_stale'
    end

    local selectionCoords = sanitizeVector(selection.coords)
    local selectionNormal = sanitizeVector(selection.normal)
    local selectionId = toNumber(selection.selectionId)
    local selectionGeneration = toNumber(selection.generation)
    local selectedAt = toNumber(selection.selectedAt)
    if not selectionCoords or not selectionNormal or not selectionId or selectionId <= 0
        or not selectionGeneration or selectionGeneration <= 0 or not selectedAt then
        return false, 'selection_stale'
    end
    if selection.sessionToken ~= sessionToken then
        return false, 'session_stale'
    end

    if not clearPlacement('placing_started') then
        -- placement module was already inactive or unavailable. This is still valid.
        if Config and Config.Debug then
            debugPrint('Placement targeting stop request returned false during PLACING start.')
        end
    end

    local expectedSelectionId = selectionId
    local expectedPlacementToken = session.token

    local function onPlacementComplete(result, reason)
        if state ~= Constants.States.PLACING then
            return
        end

        local PlacingModule = getPlacingModule()
        local placingState = PlacingModule and PlacingModule.getState and PlacingModule.getState()
        local placingToken = PlacingModule and PlacingModule.getSessionToken and PlacingModule.getSessionToken()
        if placingToken ~= expectedPlacementToken then
            return
        end
        if placingState and placingState.selectionId and expectedSelectionId and placingState.selectionId ~= expectedSelectionId then
            if Config and Config.Debug then
                debugPrint(('Ignoring stale placement result for selection=%s active=%s'):format(
                    tostring(expectedSelectionId),
                    tostring(placingState.selectionId)
                ))
            end
            return
        end

        local finalSelectionId = selection.selectionId
        if finalSelectionId and finalSelectionId > 0 and Config and Config.Debug then
            debugPrint(('Placing complete callback result=%s reason=%s selection=%s'):format(
                tostring(result),
                tostring(reason),
                tostring(finalSelectionId)
            ))
        end

        if result == 'completed' then
            local selectionToCommit = {
                coords = sanitizeVector(selection.coords),
                normal = sanitizeVector(selection.normal),
                selectionId = finalSelectionId
            }
            if not selectionToCommit.coords or not selectionToCommit.normal then
                transitionTo(Constants.States.DEPLOYMENT_READY, 'selection_stale')
                return
            end

            if finalSelectionId and finalSelectionId > 0 then
                local placement = getPlacementModule()
                if placement and placement.clearSelection then
                    placement.clearSelection()
                end
            end

            if Config and Config.Debug then
                debugPrint('Placing completed successfully, requesting commit')
            end

            local newRequestId = makePlacementRequestId()
            local maxRetries = toNumber(Config.ServerPlacement and Config.ServerPlacement.MaximumRetries) or 1
            local requestTimeout = toNumber(Config.Timeouts and Config.Timeouts.PlacementCommitMilliseconds) or 5000
            local ownerServerId = GetPlayerServerId(PlayerId())
            commitState.requestId = newRequestId
            commitState.payload = {
                coords = selectionToCommit.coords,
                normal = selectionToCommit.normal,
                selectionId = selectionToCommit.selectionId
            }
            commitState.selection = selection
            commitState.retriesRemaining = maxRetries
            commitState.maxRetries = maxRetries
            commitState.startedAt = Utils.nowMilliseconds()
            commitState.requestTimeout = requestTimeout
            commitState.timeoutAt = commitState.startedAt + requestTimeout
            commitState.ownerServerId = ownerServerId

            if not transitionTo(Constants.States.COMMITTING, 'placement_completed') then
                clearPlacementCommit()
                transitionTo(Constants.States.DEPLOYMENT_READY, 'placement_commit_rejected')
                return
            end

            sendPlacementCommit()
            return
        end

        if shouldIgnorePlacingFailure(reason) then
            debugPrint(('Ignoring stale placement result reason=%s'):format(tostring(reason)))
            transitionTo(Constants.States.DEPLOYMENT_READY, 'stale_placement')
            return
        end

        if reason == 'placement_selection_too_far' or reason == 'movement_timeout' or reason == 'movement_stuck' or reason == 'heading_failed' then
            notifyOnce('flare_placing_unreachable')
        else
            notifyOnce('flare_placing_failed')
        end

        if isPlacingFailureCritical(reason) then
            transitionTo(Constants.States.STOPPING, reason or 'placement_failed')
        else
            transitionTo(Constants.States.DEPLOYMENT_READY, reason or 'placement_failed')
        end
    end

    local function isPlacingSessionValid()
        return (state == Constants.States.DEPLOYMENT_READY or state == Constants.States.PLACING) and sessionToken == session.token and session.ped == PlayerPedId()
    end

    local started, startReason = Placing.start(
        session.ped,
        selection,
        sessionToken,
        isPlacingSessionValid,
        onPlacementComplete
    )
    if not started then
        return false, startReason or 'placement_start_failed'
    end

    local placement = getPlacementModule()
    if placement and placement.clearSelection then
        placement.clearSelection()
    end

    if not transitionTo(Constants.States.PLACING, 'placement_started') then
        Placing.cancel('placement_transition_failed')
        return false, 'placement_transition_failed'
    end

    return true, nil
end

local function startPlacementTargeting()
    local Placement = getPlacementModule()
    if not Placement or not Placement.startTargeting then
        return false, 'placement_module_missing'
    end
    local function isSessionValid()
        return state == Constants.States.DEPLOYMENT_READY and session.token ~= nil and session.ped ~= nil and session.ped == PlayerPedId()
    end

    return Placement.startTargeting(session.ped, session.token, isSessionValid, true)
end

local function isPedAborted()
    local ped = session.ped or PlayerPedId()
    if session.ped and session.ped ~= PlayerPedId() then
        return 'ped_changed'
    end
    if ped == 0 then
        return 'ped_missing'
    end
    if not DoesEntityExist(ped) then
        return 'ped_missing'
    end
    if IsEntityDead(ped) then
        return 'player_died'
    end
    if IsPedInAnyVehicle(ped, false) then
        return 'entered_vehicle'
    end
    return nil
end

local function stopActiveLoop()
    loopToken = loopToken + 1
end

local function runEquipmentSequence()
    local Effects = getEffectsModule()
    if not Effects or not Effects.createHeldFlare or not Effects.getHeldFlare then
        notifyOnce('invalid_request')
        debugPrint('Equipment failed: effects module unavailable')
        return false, 'effects_unavailable'
    end

    local sessionToken = session.token
    local expectedPed = session.ped
    if not expectedPed then
        return false, 'ped_missing'
    end

    local function isSessionValid()
        return state == Constants.States.EQUIPPING and session.token == sessionToken and session.ped == PlayerPedId()
    end

    local function mapEquipFailureReason(rawReason)
        if rawReason == 'flare_model_invalid' or rawReason == 'flare_model_load_failed' or rawReason == 'flare_prepare_failed' then
            return rawReason
        end
        if rawReason == 'session_cancelled' then
            return 'session_cancelled'
        end
        return 'flare_equip_animation_failed'
    end

    local created, createReason = Effects.createHeldFlare(expectedPed, sessionToken, isSessionValid)
    if not created then
        local normalizedReason = createReason
        if not isSessionValid() then
            return false, 'session_cancelled'
        end
        return false, normalizedReason
    end

    if not Effects.getHeldFlare() or not Effects.isHeldFlareAttached(expectedPed) then
        clearHeldFlare('prepare_failed')
        return false, 'flare_prepare_failed'
    end

    local Animations = getAnimationsModule()
    if not Animations or not Animations.playEquip then
        clearHeldFlare('animations_unavailable')
        return false, 'flare_equip_animation_failed'
    end

    local animationPlayed, animationReason = Animations.playEquip(expectedPed, sessionToken, isSessionValid)
    if not animationPlayed then
        clearHeldFlare('equip_animation_failed')
        if animationReason == 'session_cancelled' or not isSessionValid() then
            return false, 'session_cancelled'
        end
        return false, mapEquipFailureReason(animationReason)
    end

    if not isSessionValid() then
        clearHeldFlare('session_changed')
        return false, 'session_cancelled'
    end

    if not Effects.getHeldFlare() or not Effects.isHeldFlareAttached(expectedPed) then
        clearHeldFlare('prepare_failed')
        return false, 'flare_prepare_failed'
    end

    debugPrint(('Equipment animation finished token=%s'):format(tostring(sessionToken)))
    return true, nil
end

local function runIgniteSequence()
    local Effects = getEffectsModule()
    if not Effects then
        return false, 'effects_unavailable'
    end
    local Animations = getAnimationsModule()
    if not Animations or not Animations.playIgnite then
        return false, 'animations_unavailable'
    end
    local Visuals = getVisualsModule()
    if not Visuals or not Visuals.startHeldFlare then
        return false, 'visuals_unavailable'
    end
    local Audio = getAudioModule()
    local audioStarted = true
    local audioReason = nil

    local sessionToken = session.token
    local expectedPed = session.ped
    local ignitionLoopToken = loopToken
    if not expectedPed then
        return false, 'ped_missing'
    end

    local flareEntity = Effects.getHeldFlare()
    if not flareEntity then
        return false, 'flare_visual_start_failed'
    end

    local function isSessionValid()
        local heldLightState = state == Constants.States.IGNITING
            or state == Constants.States.DEPLOYMENT_READY
            or state == Constants.States.PLACING
            or state == Constants.States.COMMITTING
        if not heldLightState then
            return false, 'deployment_state_invalid', {
                ignitionLoopToken = ignitionLoopToken,
                currentLoopToken = loopToken
            }
        end
        if session.token ~= sessionToken then
            return false, 'deployment_session_token_changed', {
                ignitionLoopToken = ignitionLoopToken,
                currentLoopToken = loopToken
            }
        end
        if session.ped ~= expectedPed then
            return false, 'deployment_session_ped_changed', {
                ignitionLoopToken = ignitionLoopToken,
                currentLoopToken = loopToken
            }
        end
        if PlayerPedId() ~= expectedPed then
            return false, 'player_ped_changed', {
                ignitionLoopToken = ignitionLoopToken,
                currentLoopToken = loopToken
            }
        end
        return true, nil
    end

    local function mapIgniteFailureReason(rawReason)
        if rawReason == 'session_cancelled' or rawReason == 'abort' then
            return 'session_cancelled'
        end
        return 'flare_ignite_animation_failed'
    end

    if Config.Realism and Config.Realism.ConsumeOnIgnition then
        local requestId = ('ignite-%d-%d'):format(GetGameTimer(), math.random(1,999999))
        pendingIgnition = {requestId=requestId}
        TriggerServerEvent(Constants.Events.Server.RequestIgnition,{requestId=requestId})
        local deadline = GetGameTimer()+5000
        while not pendingIgnition.response and GetGameTimer()<deadline and isSessionValid() do Wait(25) end
        local response = pendingIgnition.response
        if not response or not response.allowed then return false, response and response.reason or 'authorization_timeout' end
        burnEndsAt = GetGameTimer()+(tonumber(response.remainingMilliseconds) or 0)
        activeIgnitionRequest=requestId
        pendingIgnition = {}
    end
    local combustionStarted=false
    local function startCombustionAtStrike()
        if combustionStarted then return true end
        if not isSessionValid() then return false,'session_cancelled' end
        if Config.FlareProp.LitModel and Effects.getHeldFlareVisualState()~='lit' then
            Effects.removeHeldFlare('cap_removed')
            local created, why = Effects.createHeldFlare(expectedPed,sessionToken,isSessionValid,Config.FlareProp.LitModel)
            if not created then return false,why end
            flareEntity = Effects.getHeldFlare()
        end
        flareEntity = Effects.getHeldFlare()
        local visualsStarted, visualReason = Visuals.startHeldFlare(flareEntity, expectedPed, sessionToken, isSessionValid,burnEndsAt)
        if not visualsStarted then
            debugPrint(('Visual start failed reason=%s'):format(tostring(visualReason)))
            clearVisuals('ignite_visual_failed')
            clearAnimations('ignite_visual_failed')
            clearHeldFlare('ignite_visual_failed')
            return false, visualReason or 'flare_visual_start_failed'
        end

        if Audio then
            if Audio.startHeldFlare then
                audioStarted, audioReason = Audio.startHeldFlare(flareEntity, expectedPed, sessionToken, isSessionValid)
            end
            if not audioStarted then
                local required = Config and Config.FlareAudio and Config.FlareAudio.Required == true
                if required then
                    debugPrint(('Ignite audio failed and is required. reason=%s'):format(tostring(audioReason)))
                    clearAudio('ignite_audio_failed')
                    clearVisuals('ignite_audio_failed')
                    clearAnimations('ignite_audio_failed')
                    clearHeldFlare('ignite_audio_failed')
                    return false, audioReason or 'flare_audio_start_failed'
                end
                if Config and Config.Debug then
                    debugPrint(('Ignite audio failed but is optional. reason=%s'):format(tostring(audioReason)))
                end
            end
        end

        if not Visuals.isActive() then
            clearVisuals('ignite_visual_inactive')
            clearAnimations('ignite_visual_inactive')
            clearHeldFlare('ignite_visual_inactive')
            return false, 'flare_visual_start_failed'
        end

        if audioStarted and Audio and Audio.isActive and not Audio.isActive() then
            debugPrint('Audio state did not become active after start; clearing only audio.')
            clearAudio('audio_state_inactive')
            audioStarted = false
        end

        local setStateResult, setStateReason = Effects.setHeldFlareVisualState('lit')
        if not setStateResult then
            clearVisuals('visual_state_failed')
            clearAnimations('visual_state_failed')
            clearHeldFlare('visual_state_failed')
            debugPrint(('Unable to set flare visual state to lit: %s'):format(tostring(setStateReason)))
            return false, 'flare_visual_start_failed'
        end

        combustionStarted=true
        return true,nil
    end
    local played,playReason=Animations.playIgnite(expectedPed,sessionToken,isSessionValid,startCombustionAtStrike)
    if not played then
        clearAudio('ignite_animation_failed');clearVisuals('ignite_animation_failed')
        if playReason=='session_cancelled'or not isSessionValid()then return false,'session_cancelled'end
        return false,mapIgniteFailureReason(playReason)
    end
    if not isSessionValid()then clearAudio('session_cancelled');clearVisuals('session_cancelled');return false,'session_cancelled'end
    -- Compatibility for animation adapters without a strike callback.
    if not combustionStarted then return startCombustionAtStrike()end

    return true, nil
end

local function setState(nextState)
    local token = loopToken + 1
    debugPrint(('Activation loop start: state=%s token=%d'):format(tostring(nextState), token))
    state = nextState
    stopActiveLoop()
    token = loopToken

    if nextState == Constants.States.EQUIPPED_UNLIT and Config and Config.Debug then
        local heartbeatToken = token
        local heartbeatSessionToken = session.token
        CreateThread(function()
            for sample = 1, 10 do
                if state ~= Constants.States.EQUIPPED_UNLIT or loopToken ~= heartbeatToken or session.token ~= heartbeatSessionToken then
                    break
                end
                local Effects = getEffectsModule()
                local details = Effects and Effects.getHeldFlareDiagnostics and Effects.getHeldFlareDiagnostics(session.ped) or {}
                debugPrint(('Held heartbeat sample=%d state=%s sessionToken=%s loopToken=%s ped=%s currentPed=%s held=%s exists=%s attached=%s heldToken=%s visualState=%s'):format(
                    sample,
                    tostring(state),
                    tostring(session.token),
                    tostring(loopToken),
                    tostring(session.ped),
                    tostring(PlayerPedId()),
                    tostring(details.handle),
                    tostring(details.exists),
                    tostring(details.attached),
                    tostring(details.sessionToken),
                    tostring(details.visualState)
                ))
                Wait(500)
            end
        end)
    end

    CreateThread(function()
        while token == loopToken do
            if burnEndsAt and GetGameTimer()>=burnEndsAt and state~=Constants.States.STOPPING and state~=Constants.States.IDLE then
                transitionTo(Constants.States.STOPPING,'burned_out_in_hand')
                break
            end
            if state == Constants.States.AUTHORIZING then
                local authorizationRequestId = pendingAuthorization.requestId
                local authorizationRequestToken = pendingAuthorization.requestToken
                local authorizationTimeoutAt = pendingAuthorization.timeoutAt

                if not isCurrentPendingAuthorization(authorizationRequestId, authorizationRequestToken) then
                    debugPrint('Authorization monitoring ended: pending authorization changed.')
                    break
                end

                if authorizationTimeoutAt and Utils.nowMilliseconds() >= authorizationTimeoutAt then
                    notifyOnce('authorization_timeout')
                    transitionTo(Constants.States.IDLE, 'authorization_timeout')
                    break
                end

                local abortReason = isPedAborted()
                if abortReason then
                    debugPrint(('Authorization aborted while waiting: %s'):format(abortReason))
                    transitionTo(Constants.States.IDLE, abortReason)
                    break
                end

                Wait(250)
            elseif state == Constants.States.EQUIPPING then
                debugPrint('State reached EQUIPPING waiting for explicit sequence handler.')
                break
            elseif state == Constants.States.EQUIPPED_UNLIT then
                local abortReason = isPedAborted()
                if abortReason then
                    debugPrint(('Session aborted in equipped_unlit: %s'):format(abortReason))
                    transitionTo(Constants.States.STOPPING, abortReason)
                    break
                end

                if IsControlReleased(0, Constants.Inputs.Confirm) then
                    confirmPressedBlocked = false
                end

                showHelp('placement_prompt_equip')

                if not IsNuiFocused() and not IsPauseMenuActive() and IsControlJustPressed(0, Constants.Inputs.Confirm) and not confirmPressedBlocked then
                    confirmPressedBlocked = true
                    debugPrint('E pressed in EQUIPPED_UNLIT -> IGNITING')
                    transitionTo(Constants.States.IGNITING, 'ignite_pressed')
                    break
                end

                Wait(0)
            elseif state == Constants.States.IGNITING then
                local abortReason = isPedAborted()
                if abortReason then
                    debugPrint(('Session aborted in igniting: %s'):format(abortReason))
                    transitionTo(Constants.States.STOPPING, abortReason)
                    break
                end

                local ignited, igniteReason = runIgniteSequence()
                if not ignited then
                    if igniteReason ~= 'session_cancelled' then
                        local notifyReason = 'flare_ignite_animation_failed'
                        if igniteReason == 'flare_visual_asset_failed' then
                            notifyReason = 'flare_visual_asset_failed'
                        elseif igniteReason == 'flare_visual_start_failed' then
                            notifyReason = 'flare_visual_start_failed'
                        elseif igniteReason == 'visuals_unavailable' then
                            notifyReason = 'flare_visual_start_failed'
                        end
                        notifyOnce(notifyReason)
                    end
                    clearHeldFlare('ignite_failed')
                    transitionTo(Constants.States.IDLE, igniteReason or 'flare_ignite_animation_failed')
                    break
                end

                transitionTo(Constants.States.DEPLOYMENT_READY, 'ignition_completed')
                break
            elseif state == Constants.States.DEPLOYMENT_READY then
                local abortReason = isPedAborted()
                if abortReason then
                    debugPrint(('Session aborted in deployment_ready: %s'):format(abortReason))
                    transitionTo(Constants.States.STOPPING, abortReason)
                    break
                end

                if IsControlReleased(0, Constants.Inputs.Confirm) then
                    confirmPressedBlocked = false
                end

                if not IsNuiFocused() and not IsPauseMenuActive() then
                    if IsControlJustPressed(0, Constants.Inputs.Confirm) and not confirmPressedBlocked then
                        confirmPressedBlocked = true
                        local ok = Deployment.requestPlacement()
                        if not ok then notifyOnce('flare_placement_invalid') end
                    end
                end

                showPlacementHelp()
                Wait(0)
            elseif state == Constants.States.PLACING then
                local Placing = getPlacingModule()
                local abortReason = isPedAborted()
                if abortReason then
                    debugPrint(('Placing aborted by critical event: %s'):format(tostring(abortReason)))
                    transitionTo(Constants.States.STOPPING, abortReason)
                    break
                end

                if Placing and Placing.isActive and not Placing.isActive() then
                    debugPrint('Placing inactive in PLACING state, returning')
                    transitionTo(Constants.States.DEPLOYMENT_READY, 'placing_inactive')
                    break
                end

                if Config and Config.Placing and Config.Placing.DisableAttackWhilePlacing then
                    DisableControlAction(0, Constants.Inputs.PrimaryAction, true)
                    DisableControlAction(0, 24, true)
                    DisableControlAction(0, 25, true)
                end

                if IsControlJustPressed(0, Constants.Inputs.Confirm) then
                    confirmPressedBlocked = true
                end

                Wait(Config.Placing and Config.Placing.ProgressCheckMilliseconds or 100)
            elseif state == Constants.States.COMMITTING then
                local now = Utils.nowMilliseconds()
                local abortReason = isPedAborted()
                if abortReason then
                    debugPrint(('Committing aborted by event: %s'):format(tostring(abortReason)))
                    transitionTo(Constants.States.STOPPING, abortReason)
                    break
                end

                if not commitState.requestId then
                    transitionTo(Constants.States.DEPLOYMENT_READY, 'placement_commit_missing')
                    break
                end

                DisableControlAction(0, Constants.Inputs.PrimaryAction, true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                if IsControlPressed(0, Constants.Inputs.Confirm) then
                    -- inert while committing
                    confirmPressedBlocked = true
                end

                if now >= (commitState.timeoutAt or 0) then
                    if commitState.retriesRemaining > 0 then
                        commitState.retriesRemaining = commitState.retriesRemaining - 1
                        commitState.timeoutAt = now + (commitState.requestTimeout or 5000)
                        sendPlacementCommit()
                    else
                        if Config and Config.Debug then
                            debugPrint(('Placement commit timed out request=%s'):format(tostring(commitState.requestId)))
                        end
                        notifyOnce('placement_commit_timeout')
                        clearPlacementCommit()
                        transitionTo(Constants.States.DEPLOYMENT_READY, 'placement_commit_timeout')
                        break
                    end
                end

                showPlacementHelp()
                Wait(0)
            elseif state == Constants.States.STOPPING then
                local abortReason = isPedAborted()
                if abortReason then
                    debugPrint(('Stopping aborted by critical event: %s'):format(abortReason))
                    clearAudio(abortReason)
                    clearVisuals(abortReason)
                    clearHeldFlare(abortReason)
                    clearSession()
                    state = Constants.States.IDLE
                    break
                end

                local Visuals = getVisualsModule()
                local activeVisuals = Visuals and Visuals.isActive and Visuals.isActive()
                local now = Utils.nowMilliseconds()

                if (not activeVisuals) or (stoppingState.timeoutAt and now >= stoppingState.timeoutAt) then
                    if activeVisuals then
                        debugPrint('Stopping timeout reached; forcing visual cleanup.')
                        clearVisuals(stoppingState.reason or 'deploy_stop_timeout', true)
                    end
                    clearAudio(stoppingState.reason or 'deploy_stop_timeout')
                    clearHeldFlare(stoppingState.reason or 'deploy_stop_timeout')
                    clearSession()
                    state = Constants.States.IDLE
                    break
                end

                if not stoppingState.isVoluntary then
                    clearAudio(stoppingState.reason)
                    clearVisuals(stoppingState.reason)
                    clearHeldFlare(stoppingState.reason)
                    clearSession()
                    state = Constants.States.IDLE
                    break
                end

                Wait(0)
            else
                break
            end
        end
        debugPrint(('Activation loop end: state=%s token=%d'):format(tostring(state), token))
    end)
end

function transitionTo(nextState, reason)
    if state == nextState then
        return true
    end

    local currentTransitions = transitionRules[state]
    if not currentTransitions or not currentTransitions[nextState] then
        debugPrint(('Invalid state transition: %s -> %s (%s)'):format(tostring(state), tostring(nextState), tostring(reason or 'none')))
        return false
    end

    local previousState = state
    if Config and Config.Debug then
        local Effects = getEffectsModule()
        local details = Effects and Effects.getHeldFlareDiagnostics and Effects.getHeldFlareDiagnostics(session.ped) or {}
        debugPrint(('Transition: %s -> %s (%s) sessionToken=%s loopToken=%s ped=%s currentPed=%s held=%s exists=%s attached=%s heldToken=%s'):format(
            tostring(previousState),
            tostring(nextState),
            tostring(reason or 'none'),
            tostring(session.token),
            tostring(loopToken),
            tostring(session.ped),
            tostring(PlayerPedId()),
            tostring(details.handle),
            tostring(details.exists),
            tostring(details.attached),
            tostring(details.sessionToken)
        ))
    else
        debugPrint(('Transition: %s -> %s (%s)'):format(tostring(previousState), tostring(nextState), tostring(reason or 'none')))
    end
    state = nextState
    stoppingState.reason = reason
    stoppingState.isVoluntary = false
    stoppingState.timeoutAt = nil

    if nextState == Constants.States.STOPPING then
        stopActiveLoop()
        clearPlacing(reason)
        clearPlacement(reason)
        clearAnimations(reason)
        local Audio = getAudioModule()
        if Audio and Audio.stopHeldFlare then
            Audio.stopHeldFlare(reason)
        elseif Audio and Audio.clear then
            Audio.clear(reason)
        end

        local shouldStopGradually = isGracefulStop(reason, previousState)
        if shouldStopGradually then
            local Visuals = getVisualsModule()
            if Visuals and Visuals.stopHeldFlare then
                local stopped, stopMode = Visuals.stopHeldFlare(reason, false)
                if stopped and stopMode ~= 'already_inactive' then
                    stoppingState.isVoluntary = true
                    stoppingState.timeoutAt = Utils.nowMilliseconds() + gracefulStopWaitMilliseconds()
                    clearNotifications()
                    setState(Constants.States.STOPPING)
                    return true
                end
            end
        end


        if allowsResidualSmoke(reason) then
            local Visuals = getVisualsModule()
            if Visuals and Visuals.stopHeldFlare then
                Visuals.stopHeldFlare(reason, false)
            end
        end

        clearVisuals(reason, allowsResidualSmoke(reason))
        clearHeldFlare(reason)
        clearPlacement(reason)
        clearSession()
        state = Constants.States.IDLE
        return true
    end

    if nextState == Constants.States.IDLE then
        clearSession()
        clearPlacing(reason)
        clearAnimations(reason)
        clearVisuals(reason)
        clearAudio(reason)
        clearHeldFlare(reason)
        stopActiveLoop()
    else
        clearNotifications()
    end

    if nextState ~= Constants.States.STOPPING then
        setState(nextState)
    end

    return true
end

function Deployment.getState()
    return state
end

function Deployment.isActive()
    return state == Constants.States.EQUIPPING
        or state == Constants.States.EQUIPPED_UNLIT
        or state == Constants.States.IGNITING
        or state == Constants.States.DEPLOYMENT_READY
        or state == Constants.States.PLACING
        or state == Constants.States.COMMITTING
end

function Deployment.requestStart(method)
    local normalizedMethod = Utils.sanitizeMethod(method)
    if not normalizedMethod then
        notifyOnce('invalid_request')
        debugPrint('requestStart rejected: invalid method')
        return false
    end

    if state ~= Constants.States.IDLE then
        debugPrint(('requestStart ignored in state=%s method=%s'):format(tostring(state), tostring(normalizedMethod)))
        return false
    end

    if not requestMethodAllowed(normalizedMethod) then
        notifyOnce('method_disabled')
        debugPrint(('requestStart denied: method disabled %s'):format(tostring(normalizedMethod)))
        return false
    end

    local now = Utils.nowMilliseconds()
    local requestId = makeRequestId()
    local requestToken = requestId .. '-' .. tostring(now)

    local requestPed = PlayerPedId()
    if requestPed == 0 or not DoesEntityExist(requestPed) then
        notifyOnce('ped_missing')
        return false
    end

    clearPendingAuthorization()
    pendingAuthorization.requestId = requestId
    pendingAuthorization.requestToken = requestToken
    pendingAuthorization.startedAt = now
    pendingAuthorization.timeoutAt = now + (Config.Timeouts and Config.Timeouts.AuthorizationMilliseconds or 5000)

    requestCounter = requestCounter + 1
    session.token = requestCounter
    session.method = normalizedMethod
    session.startedAt = now
    session.ped = requestPed

    debugPrint(('requestStart %s token=%s method=%s'):format(requestId, shortToken(requestToken), normalizedMethod))

    if not transitionTo(Constants.States.AUTHORIZING, 'request_started') then
        clearPendingAuthorization()
        return false
    end

    TriggerServerEvent(Constants.Events.Server.RequestActivation, {
        requestId = requestId,
        requestToken = requestToken,
        method = session.method
    })

    return true
end

function Deployment.requestStop(reason)
    local targetReason = reason or 'request_stop'
    if targetReason == 'resource_stop' then
        -- Cleanup must finish synchronously before streamed archetypes unload.
        stopActiveLoop()
        clearPlacing(targetReason)
        clearPlacement(targetReason)
        clearAnimations(targetReason)
        clearAudio(targetReason)
        clearVisuals(targetReason, false)
        clearHeldFlare(targetReason)
        clearSession()
        state = Constants.States.IDLE
        return true
    end
    if state == Constants.States.IDLE then
        if targetReason == 'resource_stop' then
            clearVisuals(targetReason, false)
        end
        debugPrint(('requestStop ignored in %s with reason=%s'):format(tostring(state), tostring(targetReason)))
        return false
    end

    if state == Constants.States.STOPPING then
        if targetReason == 'resource_stop' then
            clearVisuals(targetReason, false)
            clearHeldFlare(targetReason)
        end
        debugPrint(('requestStop already stopping, reason=%s'):format(tostring(targetReason)))
        return true
    end

    if state == Constants.States.AUTHORIZING then
        debugPrint(('requestStop from AUTHORIZING reason=%s'):format(tostring(targetReason)))
        return transitionTo(Constants.States.IDLE, targetReason)
    end

    debugPrint(('requestStop request reason=%s from=%s'):format(tostring(targetReason), tostring(state)))
    return transitionTo(Constants.States.STOPPING, targetReason)
end

function Deployment.requestToggle(method)
    local requestedMethod = Utils.sanitizeMethod(method or 'command')
    if state == Constants.States.IDLE then
        debugPrint(('requestToggle start method=%s'):format(tostring(requestedMethod)))
        return Deployment.requestStart(requestedMethod)
    end

    if state == Constants.States.AUTHORIZING then
        debugPrint(('requestToggle ignored while authorizing method=%s'):format(tostring(requestedMethod)))
        return false
    end

    debugPrint(('requestToggle stop reason=toggle method=%s state=%s'):format(tostring(requestedMethod), tostring(state)))
    return Deployment.requestStop('toggle')
end

function Deployment.handleAuthorizationResponse(payload)
    if type(payload) ~= 'table' then
        debugPrint('Authorization response ignored: invalid payload type')
        return false
    end

    local responseRequestId = Utils.sanitizeRequestId(payload.requestId)
    local responseRequestToken = Utils.sanitizeRequestId(payload.requestToken)
    if not responseRequestId then
        notifyOnce('invalid_request')
        debugPrint('Authorization response ignored: invalid requestId')
        return false
    end

    if state ~= Constants.States.AUTHORIZING then
        debugPrint(('Authorization response ignored for state=%s req=%s'):format(tostring(state), shortToken(responseRequestId)))
        return false
    end

    if not isCurrentPendingAuthorization(responseRequestId, responseRequestToken) then
        debugPrint(('Authorization response ignored (stale) req=%s token=%s'):format(shortToken(responseRequestId), shortToken(responseRequestToken)))
        return false
    end

    local allowed = payload.allowed == true
    local reason = type(payload.reason) == 'string' and payload.reason or 'invalid_request'
    if Config and Config.Debug then
        debugPrint(('Authorization response req=%s allowed=%s reason=%s'):format(shortToken(responseRequestId), tostring(allowed), tostring(reason)))
    end

    if not allowed then
        notifyOnce(reason)
        return transitionTo(Constants.States.IDLE, reason)
    end

    if not transitionTo(Constants.States.EQUIPPING, 'authorization_allowed') then
        clearPendingAuthorization()
        return false
    end

    clearPendingAuthorization()

    local equipped, equipReason = runEquipmentSequence()
    if not equipped then
        if equipReason ~= 'session_cancelled' then
            local notifyReason = equipReason
            if equipReason == 'flare_model_invalid' then
                notifyReason = 'flare_model_load_failed'
            end
            if equipReason == 'flare_model_load_failed' or equipReason == 'flare_prepare_failed' or equipReason == 'flare_equip_animation_failed' then
                notifyOnce(notifyReason)
            elseif equipReason == 'effects_unavailable' or equipReason == 'animation' then
                notifyOnce('flare_equip_animation_failed')
            else
                notifyOnce('flare_equip_animation_failed')
            end
            debugPrint(('Held flare setup failed reason=%s'):format(tostring(equipReason)))
        end
        return transitionTo(Constants.States.IDLE, equipReason or 'flare_equip_animation_failed')
    end

    local Effects = getEffectsModule()
    if Effects then
        Effects.setHeldFlareVisualState('unlit')
    end

    return transitionTo(Constants.States.EQUIPPED_UNLIT, 'flare_equipped')
end

function Deployment.resetSession(reason)
    return transitionTo(Constants.States.IDLE, reason)
end

function Deployment.handleRoutingBucketChanged(oldBucket, newBucket)
    if not Deployment.isActive() then
        return false
    end
    debugPrint(('Deployment bucket changed old=%s new=%s state=%s'):format(
        tostring(oldBucket),
        tostring(newBucket),
        tostring(state)
    ))
    transitionTo(Constants.States.STOPPING, 'session_invalidating')
    return true
end

RegisterNetEvent(Constants.Events.Client.AuthorizationResponse, function(payload)
    Deployment.handleAuthorizationResponse(payload)
end)

RegisterNetEvent(Constants.Events.Client.PlaceFlareResult, function(payload)
    Deployment.handlePlaceFlareResult(payload)
end)

exports('StartDeploymentMode', function()
    return Deployment.requestStart('inventory')
end)

function Deployment.requestIgnition()
    if state~=Constants.States.EQUIPPED_UNLIT or IsNuiFocused()or IsPauseMenuActive()then return false,'invalid_state'end
    return transitionTo(Constants.States.IGNITING,'integration_ignition')
end
function Deployment.requestPlacementAt(coords,normal,direct)
    if state~=Constants.States.DEPLOYMENT_READY or IsNuiFocused()or IsPauseMenuActive()then return false,'invalid_state'end
    local placement=getPlacementModule()
    if not placement or not placement.selectPoint then return false,'placement_module_missing'end
    if not placement.isActive() then
        local ok,why=startPlacementTargeting();if not ok then return false,why end
    end
    local selected,reason=placement.selectPoint(coords,normal)
    if not selected then return false,reason end
    selected.direct=direct==true
    local ok,why=startPlacement(selected)
    if not ok then placement.clearSelection()end
    return ok,why
end
-- Probe once on demand immediately in front of the feet, never the camera.
function Deployment.requestPlacement()
    if state~=Constants.States.DEPLOYMENT_READY or IsNuiFocused() or IsPauseMenuActive() then return false,'invalid_state' end
    local token=session.token;local ped=PlayerPedId()
    local q=GetOffsetFromEntityInWorldCoords(ped,0,.60,0)
    local handle=StartShapeTestLosProbe(q.x,q.y,q.z+.30,q.x,q.y,q.z-1.65,1,ped,7)
    local deadline=Utils.nowMilliseconds()+500
    local status,hit,point,normal
    repeat
        status,hit,point,normal=GetShapeTestResult(handle)
        if status==1 then Wait(0) end
    until status~=1 or Utils.nowMilliseconds()>=deadline
    if token~=session.token or ped~=PlayerPedId() then return false,'session_stale' end
    if status~=2 or (hit~=true and hit~=1) then return false,'no_ground' end
    return Deployment.requestPlacementAt(point,normal,true)
end
exports('PlaceHeldFlare',Deployment.requestPlacement)
exports('IgniteHeldFlare',Deployment.requestIgnition)
exports('PlaceHeldFlareAt',Deployment.requestPlacementAt)
