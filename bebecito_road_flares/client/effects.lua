RoadFlares = RoadFlares or {}
RoadFlares.Client = RoadFlares.Client or {}

local Effects = {}
RoadFlares.Client.Effects = Effects

local Utils = RoadFlares.Utils
local Constants = RoadFlares.Constants

local heldFlare = {
    handle = nil,
    sessionToken = nil,
    modelHash = nil,
    visualState = nil
}

local function debugPrint(message)
    Utils.debugPrint(message, Constants and Constants.ResourceName or 'bebecito_road_flares')
end

local function flareConfig()
    return (Config and Config.FlareProp) or {}
end

local function getOffsetTable(values, defaults)
    local source = values or {}
    local fallback = defaults or {}
    return {
        x = tonumber(source.x) or fallback.x or 0.0,
        y = tonumber(source.y) or fallback.y or 0.0,
        z = tonumber(source.z) or fallback.z or 0.0
    }
end

local function getConfiguredModel()
    local modelName = flareConfig().Model
    if type(modelName) ~= 'string' then
        return nil
    end
    modelName = Utils.trim(modelName)
    if modelName == '' then
        return nil
    end
    return modelName
end

local function isModelSafe(modelName)
    if not modelName or modelName == '' then
        return false, 'flare_model_invalid', nil
    end

    local hash = nil
    if _G.joaat then
        hash = joaat(modelName)
    else
        hash = GetHashKey(modelName)
    end

    if type(hash) ~= 'number' or hash == 0 then
        return false, 'flare_model_invalid', nil
    end

    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        return false, 'flare_model_invalid', hash
    end

    return true, nil, hash
end

local function isValidFlareHandle(handle)
    return type(handle) == 'number' and handle ~= 0 and DoesEntityExist(handle)
end

local function clearInvalidFlare()
    if not isValidFlareHandle(heldFlare.handle) then
        heldFlare.handle = nil
        heldFlare.sessionToken = nil
        heldFlare.modelHash = nil
        heldFlare.visualState = nil
    end
end

local function isAttachedToPed(handle, ped)
    return isValidFlareHandle(handle) and IsEntityAttachedToEntity(handle, ped)
end

function Effects.getHeldFlare()
    if isValidFlareHandle(heldFlare.handle) then
        return heldFlare.handle
    end
    return nil
end

function Effects.hasHeldFlare()
    return Effects.getHeldFlare() ~= nil
end

function Effects.isHeldFlareAttached(ped)
    local handle = Effects.getHeldFlare()
    local ownerPed = ped
    if type(ownerPed) ~= 'number' then
        ownerPed = PlayerPedId()
    end
    return isAttachedToPed(handle, ownerPed)
end

function Effects.getHeldFlareVisualState()
    if Effects.hasHeldFlare() then
        return heldFlare.visualState
    end
    return nil
end

function Effects.setHeldFlareVisualState(state)
    if not Effects.hasHeldFlare() then
        heldFlare.visualState = nil
        return false, 'no_flare'
    end

    if state ~= 'unlit' and state ~= 'lit' then
        return false, 'invalid_visual_state'
    end

    heldFlare.visualState = state
    debugPrint(('Held flare visual state changed state=%s'):format(state))
    return true, nil
end

function Effects.removeHeldFlare(reason)
    local handle = heldFlare.handle
    local gripPed=heldFlare.gripPed
    if reason~='remove_cap'and gripPed and DoesEntityExist(gripPed)then
        for _,clip in ipairs({'carry','carry_walk'})do
            if IsEntityPlayingAnim(gripPed,'bd_roadflare_pose',clip,3)then StopAnimTask(gripPed,'bd_roadflare_pose',clip,3.0)end
        end
    end
    heldFlare.gripPed=nil
    heldFlare.handle = nil
    heldFlare.sessionToken = nil
    heldFlare.modelHash = nil
    heldFlare.visualState = nil

    if not isValidFlareHandle(handle) then
        return false
    end

    if IsEntityAttached(handle) then
        DetachEntity(handle, true, true)
    end

    SetEntityAsMissionEntity(handle, true, true)
    DeleteEntity(handle)

    if isValidFlareHandle(handle) then
        SetEntityAsMissionEntity(handle, true, true)
        DeleteEntity(handle)
    end

    local deleted = not isValidFlareHandle(handle)
    if deleted then
        debugPrint(('Held flare removed reason=%s'):format(tostring(reason or 'unknown')))
    else
        debugPrint(('Held flare removal failed reason=%s handle=%s'):format(tostring(reason or 'unknown'), tostring(handle)))
    end
    return deleted
end

function Effects.clear(reason)
    return Effects.removeHeldFlare(reason or 'clear')
end

function Effects.createHeldFlare(ped, sessionToken, isSessionValid, modelOverride)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false, 'ped_missing'
    end

    if IsEntityDead(ped) then
        return false, 'player_died'
    end

    if IsPedInAnyVehicle(ped, false) then
        return false, 'entered_vehicle'
    end

    if type(isSessionValid) == 'function' and not isSessionValid() then
        return false, 'session_cancelled'
    end

    if isValidFlareHandle(heldFlare.handle) then
        if heldFlare.sessionToken == sessionToken then
            return true, 'already_exists'
        end

        if not isSessionValid or isSessionValid() then
            Effects.removeHeldFlare('refresh')
        end
    end

    local config = flareConfig()
    local modelName = modelOverride or getConfiguredModel()
    local validModel, validationError, modelHash = isModelSafe(modelName)
    if not validModel then
        debugPrint(('Flare model invalid model=%s reason=%s'):format(tostring(modelName), tostring(validationError)))
        return false, validationError or 'flare_model_invalid'
    end

    local timeout = config.ModelLoadTimeoutMilliseconds or 5000
    local startedAt = Utils.nowMilliseconds()
    RequestModel(modelHash)
    debugPrint(('Flare model requested name=%s hash=%s'):format(tostring(modelName), tostring(modelHash)))

    while not HasModelLoaded(modelHash) do
        if type(isSessionValid) == 'function' and not isSessionValid() then
            SetModelAsNoLongerNeeded(modelHash)
            debugPrint('Flare model load aborted due to stale session.')
            return false, 'session_cancelled'
        end

        if Utils.nowMilliseconds() - startedAt >= timeout then
            SetModelAsNoLongerNeeded(modelHash)
            debugPrint(('Flare model load timeout name=%s elapsed=%dms'):format(tostring(modelName), Utils.nowMilliseconds() - startedAt))
            return false, 'flare_model_load_failed'
        end

        Wait(0)
    end
    debugPrint(('Flare model loaded name=%s hash=%s'):format(tostring(modelName), tostring(modelHash)))

    local coords = GetEntityCoords(ped)
    local handle = CreateObject(modelHash, coords.x, coords.y, coords.z, false, false, false)
    if not isValidFlareHandle(handle) then
        SetModelAsNoLongerNeeded(modelHash)
        return false, 'flare_prepare_failed'
    end

    if type(isSessionValid) == 'function' and not isSessionValid() then
        SetEntityAsMissionEntity(handle, true, true)
        DeleteEntity(handle)
        SetModelAsNoLongerNeeded(modelHash)
        return false, 'session_cancelled'
    end

    SetEntityAsMissionEntity(handle, true, true)
    SetEntityCollision(handle, false, false)
    SetEntityHasGravity(handle, false)

    local handConfig = config.Hand or {}
    local boneIndex = handConfig.Bone
    if type(boneIndex) ~= 'number' then
        boneIndex = 57005
    end
    boneIndex = GetPedBoneIndex(ped, boneIndex)

    local offsets = getOffsetTable(handConfig.Position or {}, { x = 0.113, y = -0.055, z = -0.016 })
    offsets.y=Utils.heldOffsetY(offsets.y,tonumber(modelName:match("_lit_(%d)$"))or 0)
    local rotations = getOffsetTable(handConfig.Rotation or {}, { x = -90.0, y = 0.0, z = 0.0 })

    if boneIndex == -1 then
        SetEntityAsMissionEntity(handle, true, true)
        DeleteEntity(handle)
        SetModelAsNoLongerNeeded(modelHash)
        return false, 'flare_prepare_failed'
    end

    AttachEntityToEntity(
        handle,
        ped,
        boneIndex,
        offsets.x,
        offsets.y,
        offsets.z,
        rotations.x,
        rotations.y,
        rotations.z,
        false,
        false,
        false,
        true,
        2,
        true
    )

    debugPrint(('Held flare attached handle=%s bone=%s'):format(tostring(handle), tostring(boneIndex)))

    if not isAttachedToPed(handle, ped) then
        SetEntityAsMissionEntity(handle, true, true)
        DeleteEntity(handle)
        SetModelAsNoLongerNeeded(modelHash)
        return false, 'flare_prepare_failed'
    end

    SetModelAsNoLongerNeeded(modelHash)

    heldFlare.handle = handle
    heldFlare.sessionToken = sessionToken
    heldFlare.modelHash = modelHash
    heldFlare.visualState = modelOverride and modelOverride~=Config.FlareProp.Model and 'lit'or'unlit'
    heldFlare.gripPed=ped
    CreateThread(function()
        local dict='bd_roadflare_pose'
        RequestAnimDict(dict);local deadline=Utils.nowMilliseconds()+2000
        while not HasAnimDictLoaded(dict)and Utils.nowMilliseconds()<deadline and heldFlare.handle==handle do Wait(25)end
        while HasAnimDictLoaded(dict)and heldFlare.handle==handle and DoesEntityExist(ped)do
            local deployment=RoadFlares.Client.Deployment
            local phase=deployment and deployment.getState()
            local ready=not deployment or phase=='DEPLOYMENT_READY'or phase=='EQUIPPED_UNLIT'
            local anim=RoadFlares.Client.Animations
            -- One arm pose for every pace. Swapping to carry_walk released the
            -- shoulder on each run transition and amplified its lateral swing.
            -- Never drive locomotion or restart a pose just because speed changed.
            local clip='carry'
            if ready and not(anim and anim.isPlaying())and not IsEntityDead(ped)and not IsPedInAnyVehicle(ped,false)
                then
                if IsEntityPlayingAnim(ped,dict,'carry_walk',3)then
                    StopAnimTask(ped,dict,'carry_walk',3.0)
                end
                if not IsEntityPlayingAnim(ped,dict,clip,3)then
                    -- Secondary, sparse bone tracks only. The upper-body task mask (16)
                    -- blends the locomotion torso into this arm-only clip during
                    -- walking/start-up. Do not apply that whole-torso mask here.
                    TaskPlayAnim(ped,dict,clip,4.0,4.0,-1,33,1.0,false,false,false)
                end
            end
            Wait(200)
        end
        if not heldFlare.handle then RemoveAnimDict(dict)end
    end)

    debugPrint(('Held flare created model=%s handle=%s token=%s'):format(tostring(modelName), tostring(handle), tostring(sessionToken)))
    return true, nil
end

function Effects.ensureHeldFlare(ped, sessionToken, isSessionValid)
    clearInvalidFlare()

    if Effects.hasHeldFlare() and heldFlare.sessionToken == sessionToken then
        debugPrint('Held flare creation skipped because it already exists.')
        return true, 'already_exists'
    end

    return Effects.createHeldFlare(ped, sessionToken, isSessionValid)
end


function Effects.getSessionToken()
    return heldFlare.sessionToken
end

function Effects.getHeldFlareDiagnostics(ped)
    local handle = heldFlare.handle
    local exists = isValidFlareHandle(handle)
    local ownerPed = type(ped) == 'number' and ped or PlayerPedId()
    return {
        handle = handle,
        exists = exists,
        attached = exists and type(ownerPed) == 'number' and ownerPed ~= 0 and IsEntityAttachedToEntity(handle, ownerPed) or false,
        sessionToken = heldFlare.sessionToken,
        visualState = heldFlare.visualState
    }
end
