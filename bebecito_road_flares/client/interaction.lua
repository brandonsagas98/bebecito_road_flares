RoadFlares = RoadFlares or {}
RoadFlares.Client = RoadFlares.Client or {}

local Interaction = {}
RoadFlares.Client.Interaction = Interaction

local Deployment = RoadFlares.Client.Deployment
local WorldFlares = RoadFlares.WorldFlares
local GroundVisuals = RoadFlares.GroundVisuals
local Animations = RoadFlares.Client.Animations
local Constants = RoadFlares.Constants
local Utils = RoadFlares.Utils
local requested, hasFlares = false, false

local state = {
    running = false,
    generation = 0,
    thread = nil,
    nearest = nil,
    pending = nil,
    lastScanAt = 0,
    requestCounter = 0,
    lastRequestId = nil,
    lastRequestTime = nil
}

local tapState = {
    active = false,
    token = nil,
    flareId = nil,
    startAt = nil
}

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
    local trimmed = Utils.trim(value)
    if trimmed == '' then
        return nil
    end
    return trimmed
end

local function nowMilliseconds()
    return Utils.nowMilliseconds()
end

local function getConfig()
    return Config and Config.ManualExtinguish or {}
end

local function notifyOnce(messageKey)
    if type(messageKey) ~= 'string' or messageKey == '' then
        return
    end
    if Config and Config.Debug then
        Utils.debugPrint(('Manual interaction notify: %s'):format(tostring(messageKey)))
    end
    if RoadFlares.Presentation then RoadFlares.Presentation.notify(Utils.localize(messageKey)); return end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(Utils.localize(messageKey))
    EndTextCommandThefeedPostTicker(false, false)
end

local function isEnabled()
    return getConfig().Enabled == true
end

local function getRequestTimeout()
    return toNumber(getConfig().RequestTimeoutMilliseconds) or 4000
end

local function getScanInterval()
    return toNumber(getConfig().ProximityCheckMilliseconds) or 200
end

local function getInteractionDistance()
    -- Includes the standing ped's height above the road. A larger radius makes
    -- the crouching hand reach metres beyond the arm instead of the flare.
    return math.min(1.3,toNumber(Config and Config.Distances and Config.Distances.Interaction) or 2.0)
end

local function isEntityValid(entity)
    return type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity)
end

local function isDeploymentIdle()
    return not (Deployment and Deployment.isActive and Deployment.isActive())
end

local function isPlayerReady(ped)
    return isEntityValid(ped)
        and not IsEntityDead(ped)
        and not IsPedInAnyVehicle(ped, false)
end

local function getPlayerPed()
    local ped = PlayerPedId()
    if isPlayerReady(ped) then
        return ped
    end
    return nil
end

local function getInteractionCooldown()
    return toNumber(getConfig().RequestRateLimitMilliseconds) or 750
end

local function sanitizeResponse(payload)
    if type(payload) ~= 'table' then
        return nil
    end
    local requestId = Utils.sanitizeRequestId(payload.requestId)
    if not requestId then
        return nil
    end
    local flareId = toString(payload.flareId)
    if not flareId then
        return nil
    end
    local reason = toString(payload.reason)
    return requestId, flareId, payload.success == true, reason
end

local function isCandidate(record)
    return record ~= nil and record.status == 'active'
end

local function getDistanceMeters(entity, ped)
    if not isEntityValid(entity) or not isEntityValid(ped) then
        return nil
    end
    local pedCoords = GetEntityCoords(ped)
    local entityCoords = GetEntityCoords(entity)
    if not pedCoords or not entityCoords then
        return nil
    end
    local dx = pedCoords.x - entityCoords.x
    local dy = pedCoords.y - entityCoords.y
    local dz = pedCoords.z - entityCoords.z
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function clearPending()
    state.pending = nil
    state.nearest = nil
end

local function clearTapSession(reason)
    if not tapState.active then
        return
    end
    tapState.active = false
    tapState.token = nil
    tapState.flareId = nil
    tapState.startAt = nil
    if Config and Config.Debug and reason then
        Utils.debugPrint(('Manual tap cleared: %s'):format(tostring(reason)))
    end
    if Animations and Animations.cancel then
        Animations.cancel(reason or 'manual_interaction_stop')
    end
end

local function isTapSessionValid(token)
    return tapState.active
        and tapState.token == token
        and isEnabled()
        and isDeploymentIdle()
end

local function runTapSequence(flareId, token)
    if not Animations or not Animations.playExtinguishTap then
        return false, 'animation_system_missing'
    end

    local ped = getPlayerPed()
    if not ped then
        return false, 'ped_missing'
    end

    local runtime = nil
    local entity = nil
    local fallbackCoords = nil

    if GroundVisuals and GroundVisuals.getRuntime then
        runtime = GroundVisuals.getRuntime(flareId)
        if runtime then
            entity = runtime.entity
        end
    end
    if (not isEntityValid(entity)) and WorldFlares then
        local record = WorldFlares.get(flareId)
        if record and record.coords then
            fallbackCoords = record.coords
        end
    end

    local facingMs = toNumber(getConfig().FaceTargetDurationMilliseconds) or 600
    if isEntityValid(entity) then
        TaskTurnPedToFaceEntity(ped, entity, facingMs)
    elseif fallbackCoords and fallbackCoords.x and fallbackCoords.y and fallbackCoords.z then
        TaskTurnPedToFaceCoord(ped, fallbackCoords.x, fallbackCoords.y, fallbackCoords.z, facingMs)
    end
    local facingUntil=nowMilliseconds()+math.min(600,math.max(0,facingMs))
    while nowMilliseconds()<facingUntil do
        if not isTapSessionValid(token)then return false,'session_cancelled'end
        Wait(0)
    end

    local ok, reason = Animations.playExtinguishTap(
        ped,
        token,
        function()
            return isTapSessionValid(token)
        end
    )
    return ok, reason
end

local function isNearestStale(nearest, ped)
    if not nearest then
        return true
    end
    if not nearest.runtime or not isEntityValid(nearest.runtime.entity) then
        return true
    end
    local entityDistance = getDistanceMeters(nearest.runtime.entity, ped)
    if not entityDistance then
        return true
    end
    return entityDistance > getInteractionDistance()
end

local function resolveNearestCandidate(ped, localBucket)
    if not ped then
        return nil
    end

    local nearest
    local nearestDistance
    local limit = getInteractionDistance()
    local pedCoords=GetEntityCoords(ped)

    if not WorldFlares then
        return nil
    end

    local all = WorldFlares.getAll() or {}
    for _, record in ipairs(all) do
        if not isCandidate(record) then
            goto continue
        end
        -- Ground props are frozen at authoritative positions. Reject distant
        -- records before cloning runtimes and calling entity natives.
        local p=record.coords
        if p and pedCoords then
            local dx,dy,dz=p.x-pedCoords.x,p.y-pedCoords.y,p.z-pedCoords.z
            if dx*dx+dy*dy+dz*dz>(limit+.15)^2 then goto continue end
        end

        local recordBucket = toNumber(record.routingBucket)
        if localBucket ~= nil and recordBucket ~= nil and recordBucket ~= localBucket then
            goto continue
        end

        local runtime = nil
        local runtimeEntity = nil
        if GroundVisuals and GroundVisuals.getRuntime then
            runtime = GroundVisuals.getRuntime(record.flareId)
            if runtime then
                runtimeEntity = runtime.entity
            end
        end

        if not isEntityValid(runtimeEntity) then
            goto continue
        end

        local distance = getDistanceMeters(runtimeEntity, ped)
        if not distance or distance > limit then
            goto continue
        end

        if nearestDistance == nil or distance < nearestDistance then
            nearestDistance = distance
            nearest = {
                flareId = toString(record.flareId),
                routingBucket = recordBucket,
                distance = distance,
                runtime = runtime
            }
        end

        ::continue::
    end

    return nearest
end

local function canShowPrompt(ped, alreadyReady)
    if IsNuiFocused() or IsPauseMenuActive() then
        return false
    end
    if not isEnabled() then
        return false
    end
    if state.pending ~= nil then
        return false
    end
    if not isDeploymentIdle() then
        return false
    end
    if not alreadyReady and not isPlayerReady(ped) then
        return false
    end
    if tapState.active then
        return false
    end
    return state.nearest ~= nil
end

local function drawPrompt()
    if RoadFlares.Presentation then RoadFlares.Presentation.prompt(Utils.localize('flare_extinguish_prompt')); return end
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(Utils.localize('flare_extinguish_prompt'))
    EndTextCommandDisplayHelp(0, false, false, -1)
end

local function makeRequestId()
    state.requestCounter = (toNumber(state.requestCounter) or 0) + 1
    return ('rfm-%s-%s'):format(tostring(nowMilliseconds()), tostring(state.requestCounter))
end

local function sendManualExtinguishRequest()
    if not state.nearest then
        return false
    end

    local now = nowMilliseconds()
    if state.lastRequestId == state.nearest.flareId and (toNumber(state.lastRequestTime) or 0) + getInteractionCooldown() > now then
        return false
    end

    state.pending = {
        requestId = makeRequestId(),
        flareId = state.nearest.flareId,
        startedAt = now,
        timeoutAt = now + getRequestTimeout(),
        requestGeneration = state.generation
    }

    state.lastRequestId = state.nearest.flareId
    state.lastRequestTime = now

    TriggerServerEvent(
        Constants.Events.Server.RequestManualExtinguish,
        {
            requestId = state.pending.requestId,
            flareId = state.pending.flareId
        }
    )
    return true
end

function Interaction.start()
    requested = true
    hasFlares = WorldFlares and WorldFlares.getActiveCount() > 0 or false
    if state.running then
        return
    end
    if not isEnabled() then
        return
    end
    if not hasFlares then return end

    state.running = true
    state.generation = state.generation + 1
    local generation = state.generation
    local scanInterval = getScanInterval()

    state.thread = CreateThread(function()
        while state.running and state.generation == generation do
            if not hasFlares and not state.pending and not tapState.active then break end
            local now = nowMilliseconds()

            if not isEnabled() then
                state.running = false
                state.generation = state.generation + 1
                clearPending()
                clearTapSession('manual_extinguish_disabled')
                return
            end

            if state.pending and now >= toNumber(state.pending.timeoutAt) then
                clearPending()
            end

            local ped = getPlayerPed()
            local localBucket = nil
            if WorldFlares and WorldFlares.getRoutingBucket then
                localBucket = WorldFlares.getRoutingBucket()
            end

            if ped and isDeploymentIdle() and not state.pending then
                if now - state.lastScanAt >= scanInterval then
                    state.lastScanAt = now
                    state.nearest = resolveNearestCandidate(ped, localBucket)
                end

                if canShowPrompt(ped, true) then
                    drawPrompt()

                    if IsControlJustReleased(0, Constants.Inputs.Interact) then
                        if sendManualExtinguishRequest() then
                            if Config and Config.Debug then
                                Utils.debugPrint(('Manual extinguish request sent flareId=%s'):format(tostring(state.pending and state.pending.flareId)))
                            end
                        end
                    end

                    Wait(0)
                else
                    if state.nearest then
                        if isNearestStale(state.nearest, ped) then
                            state.nearest = nil
                        end
                    end
                    Wait(scanInterval)
                end
            else
                state.nearest = nil
                Wait(scanInterval)
            end

            if tapState.active and not isTapSessionValid(tapState.token) then
                clearTapSession('invalid_session')
            end

            ::loop_continue::
        end
        if state.generation == generation then
            state.running = false
            state.thread = nil
            state.nearest = nil
        end
    end)
end

function Interaction.stop(reason)
    requested = false
    if not state.running then
        return
    end

    state.generation = state.generation + 1
    state.running = false
    if state.thread then
        state.thread = nil
    end

    clearPending()
    clearTapSession(reason or 'resource_stop')
    state.nearest = nil

    if Animations and Animations.cancel then
        Animations.cancel(reason or 'resource_stop')
    end
end

function Interaction.reset()
    clearPending()
    clearTapSession('reset')
end

function Interaction.handleManualExtinguishResult(payload)
    local requestId, flareId, success, reason = sanitizeResponse(payload)
    if not requestId then
        return
    end

    if state.pending == nil then
        if Config and Config.Debug then
            Utils.debugPrint(('Ignoring manual extinguish response without pending req=%s'):format(tostring(requestId)))
        end
        return
    end
    if not state.pending.requestGeneration or state.pending.requestGeneration ~= state.generation then
        if Config and Config.Debug then
            Utils.debugPrint(('Ignoring stale generation in manual extinguish response req=%s'):format(tostring(requestId)))
        end
        clearPending()
        return
    end

    if not state.pending or state.pending.requestId ~= requestId then
        if Config and Config.Debug then
            Utils.debugPrint(('Ignoring stale manual extinguish response req=%s'):format(tostring(requestId)))
        end
        return
    end

    if not success then
        if reason == 'too_far' then
            notifyOnce('flare_extinguish_too_far')
        elseif reason == 'already_extinguishing' or reason == 'not_active' then
            -- intentional silent failure
        elseif reason == 'manual_extinguish_failed' or not reason or reason == 'invalid_request' then
            notifyOnce('flare_extinguish_failed')
        elseif reason == 'permission_denied' then
            notifyOnce('permission_denied')
        else
            local translation = toString(Utils.localize(reason))
            if translation == 'flare_extinguish_failed' then
                notifyOnce('flare_extinguish_failed')
            else
                notifyOnce('flare_extinguish_failed')
            end
        end
        clearPending()
        return
    end

    if reason ~= 'manual_extinguishing' then
        clearPending()
        return
    end

    if flareId ~= state.pending.flareId then
        clearPending()
        return
    end

    clearPending()

    tapState.active = true
    tapState.token = requestId
    tapState.flareId = flareId
    tapState.startAt = nowMilliseconds()

    local ok, tapReason = runTapSequence(flareId, requestId)
    if not ok then
        if tapReason == 'session_cancelled' or tapReason == 'abort' then
            -- not an error on gameplay terms
        elseif Config and Config.Debug then
            Utils.debugPrint(('Tap sequence failed for %s reason=%s'):format(tostring(flareId), tostring(tapReason)))
        end
    end
    clearTapSession('completed')
end

-- Inventory/radial-menu integration uses the same proximity and server validation as E.
exports('ExtinguishNearestFlare',function()
    local ped=getPlayerPed()
    state.nearest=resolveNearestCandidate(ped,WorldFlares and WorldFlares.getRoutingBucket())
    if not canShowPrompt(ped)then return false,'interaction_unavailable'end
    return sendManualExtinguishRequest()
end)
-- Wake only for a committed world change. Empty scenes need no proximity timer.
if WorldFlares and WorldFlares.subscribe then
    WorldFlares.subscribe(function(event, payload)
        if event == 'clear' then hasFlares = false; return end
        if not requested or (payload and payload.fromSnapshot) then return end
        if event == 'upsert' then
            hasFlares = true
            if state.running then return end
        end
        if event == 'upsert' or event == 'remove'
            or (event == 'snapshot' and payload.applied ~= false) then Interaction.start() end
    end)
end
function Interaction.getDiagnostics()
    return {requested=requested, worker=state.running, hasFlares=hasFlares,
        pending=state.pending~=nil, tapping=tapState.active}
end
return Interaction
