RoadFlares = RoadFlares or {}
RoadFlares.GroundVisuals = RoadFlares.GroundVisuals or {}

local GroundVisuals = {}
RoadFlares.GroundVisuals = GroundVisuals

local Utils = RoadFlares.Utils
local Constants = RoadFlares.Constants
local WorldFlares = RoadFlares.WorldFlares
local countRuntimes
-- Only the bounded, reconciled light set needs work every rendered frame.
local lightRuntimes = {}

local function toNumber(value)
    local number = tonumber(value)
    if type(number) ~= 'number' or number ~= number then
        return nil
    end
    return number
end

local function clamp(value, minimum, maximum)
    if type(value) ~= 'number' or value ~= value then
        return nil
    end
    if minimum ~= nil and value < minimum then
        return minimum
    end
    if maximum ~= nil and value > maximum then
        return maximum
    end
    return value
end

local function nowMilliseconds()
    return Utils.nowMilliseconds()
end

local function debugPrint(message)
    if Config and Config.Debug then
        Utils.debugPrint(message, Constants.ResourceName)
    end
end

local function resolveConfig()
    local base = {
        Enabled = false,
        ReconcileMilliseconds = 400,
        VisualRetryMilliseconds = 5000,
        ParticleDistance = 160.0,
        LightDistance = 120.0,
        ScopeLostGraceMilliseconds = 1000,
        StartRampMilliseconds = 450,
        Particle = {
            Enabled = true,
            Asset = 'core',
            Name = 'proj_flare_fuse',
            Offset = {
                x = 0.0,
                y = 0.0,
                z = 0.02
            },
            Rotation = {
                x = 0.0,
                y = 0.0,
                z = 0.0
            },
            Scale = 1.0
        },
        Light = {
            Enabled = true,
            Color = {
                r = 255,
                g = 35,
                b = 10
            },
            Range = 12.0,
            Intensity = 6.0,
            Offset = {
                x = 0.0,
                y = 0.0,
                z = 0.04
            },
            Flicker = {
                Enabled = true,
                MinimumMultiplier = 0.82,
                MaximumMultiplier = 1.12,
                UpdateMilliseconds = 75
            }
        }
    }

    local configured = Config and Config.GroundVisuals or {}
    local flareVisuals = Config and Config.FlareVisuals or {}

    local result = {
        Enabled = configured.Enabled == true,
        ReconcileMilliseconds = clamp(toNumber(configured.ReconcileMilliseconds), 60, 5000) or base.ReconcileMilliseconds,
        VisualRetryMilliseconds = clamp(toNumber(configured.VisualRetryMilliseconds), 250, 30000) or base.VisualRetryMilliseconds,
        ParticleDistance = clamp(toNumber(configured.ParticleDistance), 0, 5000) or base.ParticleDistance,
        LightDistance = clamp(toNumber(configured.LightDistance), 0, 5000) or base.LightDistance,
        ScopeLostGraceMilliseconds = clamp(toNumber(configured.ScopeLostGraceMilliseconds), 0, 30000) or base.ScopeLostGraceMilliseconds,
        StartRampMilliseconds = clamp(toNumber(configured.StartRampMilliseconds), 0, 5000) or base.StartRampMilliseconds
    }
    result.MaximumParticles = math.floor(clamp(toNumber(configured.MaximumParticles), 0, 64) or 24)
    result.MaximumLights = math.floor(clamp(toNumber(configured.MaximumLights), 0, 32) or 8)

    local useParticlePreference = true
    if configured.UseHeldParticleConfiguration ~= nil then
        useParticlePreference = configured.UseHeldParticleConfiguration == true
    elseif configured.UseHeldFlareConfiguration ~= nil then
        useParticlePreference = configured.UseHeldFlareConfiguration == true
    end
    local useLightPreference = true
    if configured.UseHeldLightConfiguration ~= nil then
        useLightPreference = configured.UseHeldLightConfiguration == true
    end

    local flareParticle = configured.Particle or flareVisuals.Particle or {}
    local flareLight = flareVisuals.Light or {}

    result.Particle = {
        Enabled = useParticlePreference and flareParticle.Enabled ~= false,
        Asset = (type(flareParticle.Asset) == 'string' and flareParticle.Asset ~= '') and flareParticle.Asset or base.Particle.Asset,
        Name = (type(flareParticle.Name) == 'string' and flareParticle.Name ~= '') and flareParticle.Name or base.Particle.Name,
        Offset = {
            x = toNumber(flareParticle.Offset and flareParticle.Offset.x) or base.Particle.Offset.x,
            y = toNumber(flareParticle.Offset and flareParticle.Offset.y) or base.Particle.Offset.y,
            z = toNumber(flareParticle.Offset and flareParticle.Offset.z) or base.Particle.Offset.z
        },
        Rotation = {
            x = toNumber(flareParticle.Rotation and flareParticle.Rotation.x) or base.Particle.Rotation.x,
            y = toNumber(flareParticle.Rotation and flareParticle.Rotation.y) or base.Particle.Rotation.y,
            z = toNumber(flareParticle.Rotation and flareParticle.Rotation.z) or base.Particle.Rotation.z
        },
        Scale = clamp(toNumber(flareParticle.Scale), 0.1, 12.0) or base.Particle.Scale
    }

    result.Light = {
        Enabled = useLightPreference and flareLight.Enabled ~= false,
        Color = {
            r = toNumber(flareLight.Color and flareLight.Color.r) or base.Light.Color.r,
            g = toNumber(flareLight.Color and flareLight.Color.g) or base.Light.Color.g,
            b = toNumber(flareLight.Color and flareLight.Color.b) or base.Light.Color.b
        },
        Range = clamp(toNumber(flareLight.Range), 0.5, 200.0) or base.Light.Range,
        Intensity = clamp(toNumber(flareLight.Intensity), 0.0, 20.0) or base.Light.Intensity,
        Offset = {
            x = toNumber(flareLight.Offset and flareLight.Offset.x) or base.Light.Offset.x,
            y = toNumber(flareLight.Offset and flareLight.Offset.y) or base.Light.Offset.y,
            z = toNumber(flareLight.Offset and flareLight.Offset.z) or base.Light.Offset.z
        },
        Flicker = {
            Enabled = flareLight.Flicker and flareLight.Flicker.Enabled ~= false,
            MinimumMultiplier = clamp(toNumber(flareLight.Flicker and flareLight.Flicker.MinimumMultiplier), 0.1, 5.0) or base.Light.Flicker.MinimumMultiplier,
            MaximumMultiplier = clamp(toNumber(flareLight.Flicker and flareLight.Flicker.MaximumMultiplier), 0.1, 5.0) or base.Light.Flicker.MaximumMultiplier,
            UpdateMilliseconds = clamp(toNumber(flareLight.Flicker and flareLight.Flicker.UpdateMilliseconds), 16, 5000) or base.Light.Flicker.UpdateMilliseconds
        }
    }

    if result.Light.Flicker.MinimumMultiplier > result.Light.Flicker.MaximumMultiplier then
        result.Light.Flicker.MinimumMultiplier, result.Light.Flicker.MaximumMultiplier = result.Light.Flicker.MaximumMultiplier, result.Light.Flicker.MinimumMultiplier
    end
    result.Light.Color.r = clamp(toNumber(result.Light.Color.r), 0, 255) or base.Light.Color.r
    result.Light.Color.g = clamp(toNumber(result.Light.Color.g), 0, 255) or base.Light.Color.g
    result.Light.Color.b = clamp(toNumber(result.Light.Color.b), 0, 255) or base.Light.Color.b

    return result
end

local function getLifecycleConfig()
    local configured = Config and Config.Lifecycle or {}
    return {
        ParticleFadeEnabled = (configured.ParticleFade and configured.ParticleFade.Enabled) == true,
        MinimumAlpha = clamp(toNumber(configured.ParticleFade and configured.ParticleFade.MinimumAlpha), 0.0, 1.0) or 0.0,
        MinimumScaleMultiplier = clamp(toNumber(configured.ParticleFade and configured.ParticleFade.MinimumScaleMultiplier), 0.0, 1.0) or 0.35
    }
end

local function isNumber(value)
    return type(value) == 'number' and value == value
end

local function isExtinguishingStatus(status)
    return status == 'automatic_extinguishing' or status == 'manual_extinguishing'
end

local function sanitizeRecord(record)
    if type(record) ~= 'table' then
        return nil
    end

    local flareId = tostring(record.flareId or '')
    if flareId == '' then
        return nil
    end

    local netId = toNumber(record.netId)
    if netId == nil or netId <= 0 then
        return nil
    end

    if record.status ~= 'active' and record.status ~= 'automatic_extinguishing' and record.status ~= 'manual_extinguishing' then
        return nil
    end

    return {
        flareId = flareId,
        netId = netId,
        routingBucket = toNumber(record.routingBucket),
        createdAt = toNumber(record.createdAt),
        extinguishDurationMilliseconds = toNumber(record.extinguishDurationMilliseconds),
        extinguishRemainingMilliseconds = toNumber(record.extinguishRemainingMilliseconds),
        extinguishStartedAt = toNumber(record.extinguishStartedAt), manualActorSource=toNumber(record.manualActorSource),
        status = record.status,
        ownerSource = toNumber(record.ownerSource),tipLength=toNumber(record.tipLength),burnStage=toNumber(record.burnStage)
    }
end

local function cloneRuntime(runtime)
    if type(runtime) ~= 'table' then
        return nil
    end
    return {
        flareId = runtime.flareId,
        netId = runtime.netId,
        routingBucket = runtime.routingBucket,
        createdAt = runtime.createdAt,
        entity = runtime.entity,
        particleHandle = runtime.particleHandle,
        particleActive = runtime.particleActive,
        lightActive = runtime.lightWanted,
        flickerMultiplier = runtime.flickerMultiplier,
        lastFlickerAt = runtime.lastFlickerAt,
        extinguishing = runtime.extinguishing,
        extinguishDurationMilliseconds = runtime.extinguishDurationMilliseconds,
        extinguishStartedAt = runtime.extinguishStartedAt,
        manualActorSource = runtime.manualActorSource,
        extinguishRemainingMilliseconds = runtime.extinguishRemainingMilliseconds,
        generation = runtime.generation,
        lastSeenAt = runtime.lastSeenAt
    }
end

local function isPlayerValid()
    local player = PlayerId()
    return isNumber(player) and player >= 0
end

local function getLocalBucket()
    if not isPlayerValid() then
        return nil
    end
    local bucket = WorldFlares and WorldFlares.getRoutingBucket and WorldFlares.getRoutingBucket()
    if bucket == nil then
        return nil
    end
    return toNumber(bucket)
end

local function isEntityValid(entity)
    return isNumber(entity) and entity ~= 0 and DoesEntityExist(entity)
end

local state = {
    generation = 0,
    running = false,
    config = nil,
    reconcilerRunning = false,
    lightRendererRunning = false,
    runtimeTable = {},
    netIdTable = {}
}

local assetState = {
    isLoaded = false,
    isLoading = false,
    loadGeneration = 0,
    users = 0,
    failUntil = 0
}

local function createRuntime(record)
    local duration = toNumber(record.extinguishDurationMilliseconds)
    local serverStartedAt = toNumber(record.extinguishStartedAt)
    local remaining = toNumber(record.extinguishRemainingMilliseconds)
    local startedAt = nowMilliseconds() - math.max(0, (duration or 0) - (remaining or duration or 0))
    local status = record.status
    local extinguishMode = isExtinguishingStatus(status)
    if extinguishMode and startedAt == nil then
        startedAt = nowMilliseconds()
    end
    return {
        flareId = record.flareId,
        netId = record.netId,
        routingBucket = record.routingBucket,
        createdAt = record.createdAt,
        status = status,
        manualActorSource=record.manualActorSource,
        entity = 0,
        particleHandle = nil,
        tipLength=record.tipLength or .220,burnStage=record.burnStage or 0,
        particleActive = false,
        lightWanted = false,
        lightStartedAt = 0,
        extinguishing = extinguishMode,
        extinguishDurationMilliseconds = extinguishMode and duration or nil,
        extinguishStartedAt = extinguishMode and startedAt or nil,
        serverExtinguishStartedAt = serverStartedAt,
        extinguishRemainingMilliseconds = toNumber(record.extinguishRemainingMilliseconds),
        flickerMultiplier = 1.0,
        lastFlickerAt = 0,
        lastSeenAt = 0,
        scopeLostAt = nil,
        entityValid = false,
        generation = state.generation,
        particleRetryAt = 0,
        ownerSource = record.ownerSource
    }
end

local function isRecordForBucket(record, localBucket)
    if localBucket == nil then
        return true
    end
    if record.routingBucket == nil then
        return true
    end
    return record.routingBucket == localBucket
end

local function getParticleAssetName()
    if not state.config then
        return nil
    end
    return state.config.Particle.Asset
end

local function requestParticleAsset()
    if not state.config then
        return false
    end
    if not state.config.Particle.Enabled then
        return false
    end

    local asset = getParticleAssetName()
    if type(asset) ~= 'string' or asset == '' then
        return false
    end
    if assetState.isLoaded and HasNamedPtfxAssetLoaded(asset) then
        return true
    end
    -- The held-flare renderer can release the same dictionary between placements.
    assetState.isLoaded = false

    local now = nowMilliseconds()
    if now < assetState.failUntil then
        return false
    end
    if assetState.isLoading then
        return false
    end

    local loadGeneration = assetState.loadGeneration + 1
    assetState.loadGeneration = loadGeneration
    assetState.isLoading = true
    local timeout = toNumber(Config.FlareVisuals and Config.FlareVisuals.AssetLoadTimeoutMilliseconds) or 5000
    local requestedAt = now
    local cfg = state.config

    CreateThread(function()
        local localGeneration = state.generation
        RequestNamedPtfxAsset(asset)
        while true do
            if state.generation ~= localGeneration then
                return
            end
            if HasNamedPtfxAssetLoaded(asset) then
                assetState.isLoading = false
                assetState.isLoaded = true
                if Config and Config.Debug then
                    debugPrint(('GroundVisuals particle asset loaded: %s'):format(asset))
                end
                return
            end
            if nowMilliseconds() - requestedAt >= timeout then
                assetState.isLoading = false
                assetState.failUntil = nowMilliseconds() + (cfg.VisualRetryMilliseconds or 5000)
                if Config and Config.Debug then
                    debugPrint(('GroundVisuals particle asset failed: %s'):format(asset))
                end
                return
            end
            Wait(0)
        end
    end)

    return false
end

local function ensureAssetLoaded()
    if not state.config then
        return false
    end
    if not state.config.Particle.Enabled then
        return false
    end
    if assetState.isLoaded and HasNamedPtfxAssetLoaded(state.config.Particle.Asset) then
        return true
    end
    return requestParticleAsset()
end

local function releaseParticleAsset()
    if not state.config then
        return
    end
    assetState.users = math.max(0, assetState.users - 1)
    if assetState.users <= 0 and assetState.isLoaded then
        local asset = getParticleAssetName()
        if asset and HasNamedPtfxAssetLoaded(asset) then
            RemoveNamedPtfxAsset(asset)
            if Config and Config.Debug then
                debugPrint(('GroundVisuals particle asset removed: %s'):format(asset))
            end
            assetState.isLoaded = false
        end
    end
end

local function isMatchingMetadata(entity, flareId)
    local entityState = Entity(entity)
    if not entityState or not entityState.state then
        return false
    end
    local metadata = entityState.state.bebecitoRoadFlare
    if type(metadata) ~= 'table' then
        return false
    end
    if tostring(metadata.flareId or '') ~= tostring(flareId) then
        return false
    end
    if metadata.status ~= 'active' and metadata.status ~= 'automatic_extinguishing' and metadata.status ~= 'manual_extinguishing' then
        return false
    end
    return true
end

local function stopParticle(runtime, reason)
    if not runtime or not runtime.particleActive then
        return
    end

    local handle = runtime.particleHandle
    if isNumber(handle) and handle > 0 and DoesParticleFxLoopedExist(handle) then
        StopParticleFxLooped(handle, false)
    end
    runtime.particleHandle = nil
    runtime.particleActive = false
    runtime.particleRetryAt = 0
    runtime.flickerMultiplier = 1.0
    runtime.lastFlickerAt = 0

    if Config and Config.Debug then
        debugPrint(('GroundVisuals particle stopped flareId=%s reason=%s'):format(runtime.flareId, tostring(reason or 'unknown')))
    end
    releaseParticleAsset()
end

local function startParticle(runtime)
    if not runtime or not state.config then
        return false
    end
    if runtime.particleActive then
        return true
    end
    if not state.config.Particle.Enabled then
        return false
    end
    if not isNumber(runtime.netId) or runtime.netId <= 0 then
        return false
    end

    local now = nowMilliseconds()
    if runtime.particleRetryAt > now then
        return false
    end

    if not ensureAssetLoaded() then
        return false
    end

    if not isEntityValid(runtime.entity) then
        return false
    end
    if not isMatchingMetadata(runtime.entity, runtime.flareId) then
        return false
    end

    local cfg = state.config
    local visualEntity=RoadFlares.Combustion and RoadFlares.Combustion.getVisualEntity('ground:'..runtime.flareId)or runtime.visualEntity or runtime.entity
    UseParticleFxAssetNextCall(cfg.Particle.Asset)
    local handle = StartParticleFxLoopedOnEntity(
        cfg.Particle.Name,
        visualEntity,
        cfg.Particle.Offset.x,
        cfg.Particle.Offset.y,
        runtime.tipLength or cfg.Particle.Offset.z,
        cfg.Particle.Rotation.x,
        cfg.Particle.Rotation.y,
        cfg.Particle.Rotation.z,
        cfg.Particle.Scale,
        false,
        false,
        false
    )
    if not isNumber(handle) or handle <= 0 or not DoesParticleFxLoopedExist(handle) then
        runtime.particleRetryAt = now + (cfg.VisualRetryMilliseconds or 5000)
        if Config and Config.Debug then
            debugPrint(('GroundVisuals particle start failed flareId=%s netId=%s'):format(
                runtime.flareId,
                tostring(runtime.netId)
            ))
        end
        return false
    end

    runtime.particleHandle = handle
    runtime.particleEntity = visualEntity
    runtime.particleActive = true
    runtime.particleRetryAt = 0
    runtime.particleScale = cfg.Particle.Scale
    runtime.flickerMultiplier = 1.0
    runtime.lastFlickerAt = 0
    runtime.lightWanted = runtime.lightWanted
    assetState.users = assetState.users + 1

    if Config and Config.Debug then
        debugPrint(('GroundVisuals particle started flareId=%s netId=%s'):format(runtime.flareId, tostring(runtime.netId)))
    end
    return true
end

local function resolveExtinguishProgress(runtime, now)
    if not runtime or not runtime.extinguishing then
        return 0, false
    end

    local duration = toNumber(runtime.extinguishDurationMilliseconds)
    if duration == nil or duration <= 0 then
        return 1.0, true
    end

    if runtime.extinguishStartedAt == nil then
        if runtime.extinguishRemainingMilliseconds ~= nil then
            runtime.extinguishStartedAt = now - (duration - runtime.extinguishRemainingMilliseconds)
        else
            runtime.extinguishStartedAt = now
        end
    end

    local elapsed = now - toNumber(runtime.extinguishStartedAt)
    local progress = elapsed / duration
    if progress >= 1.0 then
        return 1.0, true
    end
    if progress < 0.0 then
        return 0.0, false
    end
    return progress, false
end

local function applyExtinguishVisuals(runtime, now, baseIntensity)
    local progress, isComplete = resolveExtinguishProgress(runtime, now)
    local fade = 1.0 - progress
    if fade < 0.0 then
        fade = 0.0
    end
    if fade > 1.0 then
        fade = 1.0
    end

    local finalIntensity = baseIntensity * fade
    if runtime.particleActive and runtime.particleHandle then
        local cfg = getLifecycleConfig()
        if cfg.ParticleFadeEnabled then
            local alpha = (cfg.MinimumAlpha or 0.0)
            alpha = alpha + ((1.0 - alpha) * fade)
            SetParticleFxLoopedAlpha(runtime.particleHandle, alpha)

            local scale = toNumber(runtime.particleScale or (state.config and state.config.Particle and state.config.Particle.Scale) or nil)
            if scale == nil then
                scale = 1.0
            end
            local minimumScale = cfg.MinimumScaleMultiplier
            if minimumScale > 1.0 then
                minimumScale = 1.0
            end
            local scaleMultiplier = 1.0 - ((1.0 - minimumScale) * progress)
            if scaleMultiplier < 0.0 then
                scaleMultiplier = 0.0
            end
            SetParticleFxLoopedScale(runtime.particleHandle, scale * scaleMultiplier)
        end
    end

    if isComplete then
        runtime.extinguishingCompleted = true
        runtime.extinguishCompletedAt = now
        if runtime.particleActive then
            stopParticle(runtime, 'extinguish_complete')
        end
        if runtime.lightWanted then
            runtime.lightWanted = false
            runtime.lightStartedAt = 0
        end
        if Config and Config.Debug then
            debugPrint(('GroundVisuals ground flare visual extinguish completed flareId=%s'):format(tostring(runtime.flareId)))
        end
    end

    return finalIntensity, isComplete
end

local function hasAnyLightNeeded()
    if not state.config or not state.config.Light.Enabled then
        return false
    end
    for _, runtime in pairs(state.runtimeTable) do
        if runtime.lightWanted then
            return true
        end
    end
    return false
end

local function stopAllRuntimes(reason)
    local all = {}
    for flareId in pairs(state.runtimeTable) do
        all[#all + 1] = flareId
    end

    for _, flareId in ipairs(all) do
        local runtime = state.runtimeTable[flareId]
        if runtime then
            stopParticle(runtime, reason)
            if RoadFlares.Combustion then RoadFlares.Combustion.remove('ground:'..flareId,reason) end
            runtime.entity = 0
            runtime.lightWanted = false
            runtime.lightStartedAt = 0
            state.runtimeTable[flareId] = nil
            if runtime.netId then
                state.netIdTable[runtime.netId] = nil
            end
        end
    end

    if assetState.isLoaded and assetState.users <= 0 then
        local asset = getParticleAssetName()
        if asset and HasNamedPtfxAssetLoaded(asset) then
            RemoveNamedPtfxAsset(asset)
            assetState.isLoaded = false
        end
    end
    state.lightRendererRunning = false
end

local function clearRuntimesByBucket(bucket, reason)
    local targetBucket = toNumber(bucket)
    if not targetBucket then
        stopAllRuntimes(reason)
        return 0
    end

    local toClear = {}
    for flareId, runtime in pairs(state.runtimeTable) do
        if runtime and toNumber(runtime.routingBucket) == targetBucket then
            toClear[#toClear + 1] = flareId
        end
    end

    local count = 0
    for _, flareId in ipairs(toClear) do
        local runtime = state.runtimeTable[flareId]
        if runtime then
            count = count + 1
            if RoadFlares.Combustion then RoadFlares.Combustion.remove('ground:'..flareId,reason) end
            state.runtimeTable[flareId] = nil
            if runtime.netId ~= nil then
                state.netIdTable[runtime.netId] = nil
            end
            if Config and Config.Debug then
                debugPrint(('GroundVisuals clearByBucket flareId=%s bucket=%s reason=%s'):format(
                    tostring(flareId),
                    tostring(targetBucket),
                    tostring(reason or 'unknown')
                ))
            end
            stopParticle(runtime, reason or 'removed')
            runtime.lightWanted = false
            runtime.lightStartedAt = 0
            runtime.entity = 0
        end
    end

    if assetState.users < 0 then
        assetState.users = 0
    end

    if countRuntimes() == 0 and assetState.isLoaded then
        local asset = getParticleAssetName()
        if asset then
            if HasNamedPtfxAssetLoaded(asset) then
                RemoveNamedPtfxAsset(asset)
            end
            assetState.isLoaded = false
        end
    end

    if countRuntimes() == 0 and state.lightRendererRunning then
        state.lightRendererRunning = false
    end

    return count
end

local function resolveEntity(runtime)
    local netId = runtime.netId
    if not isNumber(netId) or netId <= 0 then
        return 0, false
    end
    if not NetworkDoesEntityExistWithNetworkId(netId) then
        return 0, false
    end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not isEntityValid(entity) then
        return 0, false
    end
    if not isMatchingMetadata(entity, runtime.flareId) then
        return entity, false
    end
    return entity, true
end

local function maybeSetCollision(entity)
    if not isEntityValid(entity) then
        return
    end
    if state.config and state.config.CollisionOptional then
        return
    end
    if RoadFlares.GroundPhysics and Config.GroundPhysics and Config.GroundPhysics.Enabled==true then
        for _,model in ipairs(Config.BurnModels or{})do
            if GetEntityModel(entity)==joaat(model.name)then return end
        end
    end
    SetEntityCollision(entity, false, false)
end

local function startLightRenderer()
    if state.lightRendererRunning then
        return
    end
    if not state.config or not state.config.Light.Enabled then
        return
    end
    if not hasAnyLightNeeded() then
        return
    end

    local generation = state.generation
    local cfg = state.config
    state.lightRendererRunning = true
    if Config and Config.Debug then
        debugPrint('GroundVisuals light renderer started')
    end

    CreateThread(function()
        local localGeneration = generation
        local localCfg = cfg
        while state.generation == localGeneration and state.running do
            if not state.config or not state.config.Light.Enabled then
                break
            end

            local now = nowMilliseconds()
            local player = PlayerPedId()
            local pedCoords = GetEntityCoords(player)
            local hasVisible = false
            local hasWanted = false
            local frameAmbient

            for _, runtime in ipairs(lightRuntimes) do
                if runtime.lightWanted then
                    hasWanted = true
                    if not isEntityValid(runtime.entity) then
                        runtime.lightWanted = false
                        runtime.lightStartedAt = 0
                    else
                        -- Ground objects are frozen. The reconciler checks metadata
                        -- and refreshes coordinates; avoid decoding state bags per frame.
                        local coords = runtime.renderCoords or GetEntityCoords(runtime.entity)
                        local dx,dy,dz=coords.x-pedCoords.x,coords.y-pedCoords.y,coords.z-pedCoords.z
                        if dx*dx+dy*dy+dz*dz <= localCfg.LightDistance*localCfg.LightDistance then
                            hasVisible = true
                            local ramp = 1.0
                            local rampStart = runtime.lightStartedAt
                            if rampStart == 0 then
                                rampStart = now
                                runtime.lightStartedAt = now
                            end
                            if (localCfg.StartRampMilliseconds or 0) > 0 then
                                ramp = (now - rampStart) / (localCfg.StartRampMilliseconds)
                                if ramp < 0.0 then
                                    ramp = 0.0
                                elseif ramp > 1.0 then
                                    ramp = 1.0
                                end
                            end

                            -- Chemical combustion shimmers continuously, without random steps.
                            runtime.flickerMultiplier=RoadFlares.Realism and RoadFlares.Realism.lightFlicker and
                                RoadFlares.Realism.lightFlicker(localCfg.Light.Flicker,now,runtime.entity)or 1

                            -- Clock/ambient is shared by every light in this frame.
                            if frameAmbient==nil then
                                frameAmbient=RoadFlares.Realism and RoadFlares.Realism.ambientLight and RoadFlares.Realism.ambientLight(GetClockHours and GetClockHours()or 13,GetClockMinutes and GetClockMinutes()or 0)or 1
                            end
                            local baseIntensity = localCfg.Light.Intensity * frameAmbient * ramp * runtime.flickerMultiplier
                            local intensity
                            if runtime.extinguishing then
                                intensity = applyExtinguishVisuals(runtime, now, baseIntensity)
                            else
                                intensity = baseIntensity
                            end

                            local proxy=RoadFlares.Combustion and RoadFlares.Combustion.getVisualEntity('ground:'..runtime.flareId)or(runtime.physicsCarrier and runtime.visualEntity)
                            local lightCoords=proxy and GetOffsetFromEntityInWorldCoords(proxy,0.0,0.0,runtime.tipLength or .220)or runtime.lightCoords or coords
                            local drawX = lightCoords.x + localCfg.Light.Offset.x
                            local drawY = lightCoords.y + localCfg.Light.Offset.y
                            local drawZ = lightCoords.z + .01
                            DrawLightWithRange(
                                drawX,
                                drawY,
                                drawZ,
                                localCfg.Light.Color.r,
                                localCfg.Light.Color.g,
                                localCfg.Light.Color.b,
                                localCfg.Light.Range,
                                intensity
                            )
                            hasVisible = true
                        else
                            runtime.lightWanted = false
                            runtime.lightStartedAt = 0
                        end
                    end
                end
            end

            if not hasVisible or not hasWanted then
                break
            end
            Wait(0)
        end

        state.lightRendererRunning = false
        if Config and Config.Debug then
            debugPrint('GroundVisuals light renderer stopped')
        end
        if state.generation == localGeneration and state.running then
            if hasAnyLightNeeded() then
                startLightRenderer()
            end
        end
    end)
end

countRuntimes = function()
    local count = 0
    for _ in pairs(state.runtimeTable) do
        count = count + 1
    end
    return count
end

local function evaluateRuntime(runtime, pedCoords, localBucket, now, budget, entity, isUsable)
    if not runtime then
        return
    end
    if runtime.routingBucket ~= nil and localBucket ~= nil and runtime.routingBucket ~= localBucket then
        return
    end

    local cfg = state.config
    if not cfg then
        return
    end

    -- Resolve state bags once per reconciliation. If an asset load yielded long
    -- enough to invalidate that scan, validate again rather than trusting it.
    if nowMilliseconds()-now>100 then entity,isUsable=resolveEntity(runtime);runtime.scanCoords=nil
    elseif isUsable and not isEntityValid(entity)then isUsable=false end
    if isUsable then
        if runtime.entity ~= entity then
            if isEntityValid(runtime.entity) then
                stopParticle(runtime, 'entity_recreated')
            end
            runtime.entity = entity
            runtime.scopeLostAt = nil
            runtime.entityValid = true
            maybeSetCollision(entity)
            if Config and Config.Debug then
                debugPrint(('GroundVisuals entity entered local scope flareId=%s netId=%s'):format(runtime.flareId, tostring(runtime.netId)))
            end
        end

        runtime.lastSeenAt = now
        local coords = runtime.scanCoords or GetEntityCoords(entity)
        runtime.renderCoords = coords
        local visual=RoadFlares.GroundPhysics and RoadFlares.GroundPhysics.resolve(runtime,entity)or entity
        runtime.visualEntity=visual
        if runtime.physicsCarrier and RoadFlares.WorldFlares.updatePhysicalPosition then
            RoadFlares.WorldFlares.updatePhysicalPosition(runtime.flareId,coords)
        end
        if RoadFlares.Combustion then RoadFlares.Combustion.upsert('ground:'..runtime.flareId,visual,runtime) end
        local proxy=RoadFlares.Combustion and RoadFlares.Combustion.getVisualEntity('ground:'..runtime.flareId)or visual
        if runtime.particleActive and runtime.particleEntity and runtime.particleEntity~=proxy then stopParticle(runtime,'manual_pickup')end
        local distance = Vdist(
            pedCoords.x,
            pedCoords.y,
            pedCoords.z,
            coords.x,
            coords.y,
            coords.z
        )
        local custom=RoadFlares.Combustion
        local customOwnsEffect=custom and custom.hasGroundEffects and custom.hasGroundEffects('ground:'..runtime.flareId)
        -- The custom renderer owns ground combustion. Native fuse particles are
        -- a fallback for missing/unready textures, not a second overlapping fire.
        local shouldParticle = not customOwnsEffect and cfg.Particle.Enabled and distance <= (cfg.ParticleDistance or 0) and budget.particles < cfg.MaximumParticles
        local shouldLight = cfg.Light.Enabled and distance <= (cfg.LightDistance or 0) and budget.lights < cfg.MaximumLights
        if shouldLight and GetOffsetFromEntityInWorldCoords then
            runtime.lightCoords=GetOffsetFromEntityInWorldCoords(visual,0,0,runtime.tipLength or .220)
        end
        if shouldParticle then budget.particles = budget.particles + 1 end
        if shouldLight then budget.lights = budget.lights + 1 end

        if shouldParticle then
            if not runtime.particleActive then
                startParticle(runtime)
            end
        elseif runtime.particleActive then
            stopParticle(runtime, 'out_of_range')
        end

        runtime.lightWanted = shouldLight
        if not shouldLight then
            runtime.lightStartedAt = 0
        end
        return
    end

    if runtime.scopeLostAt == nil then
        runtime.scopeLostAt = now
    end

    if now - runtime.scopeLostAt >= (cfg.ScopeLostGraceMilliseconds or 0) then
        runtime.scopeLostAt = nil
        if RoadFlares.GroundPhysics then RoadFlares.GroundPhysics.release(tostring(runtime.flareId)) end
        runtime.visualEntity = nil
        runtime.entity = 0
        runtime.entityValid = false
        runtime.lightWanted = false
        runtime.lightStartedAt = 0
        if runtime.particleActive then
            stopParticle(runtime, 'scope_lost')
        end
        if Config and Config.Debug then
            debugPrint(('GroundVisuals entity left local scope flareId=%s netId=%s'):format(runtime.flareId, tostring(runtime.netId)))
        end
    end
end

local function applyLifecycleState(runtime, safeRecord, now)
    runtime.tipLength=safeRecord.tipLength or .220;runtime.burnStage=safeRecord.burnStage or 0
    if not runtime or not safeRecord then
        return
    end

    runtime.status = safeRecord.status;runtime.manualActorSource=safeRecord.manualActorSource
    runtime.extinguishDurationMilliseconds = toNumber(safeRecord.extinguishDurationMilliseconds)
    runtime.extinguishRemainingMilliseconds = toNumber(safeRecord.extinguishRemainingMilliseconds)
    local extinguishMode = isExtinguishingStatus(safeRecord.status)
    local previousMode = runtime.extinguishing == true

    if extinguishMode then
        runtime.extinguishing = true
        runtime.extinguishCompleted = false
        local serverStartedAt = toNumber(safeRecord.extinguishStartedAt)
        local duration = runtime.extinguishDurationMilliseconds
        local remaining = runtime.extinguishRemainingMilliseconds
        if not previousMode or runtime.serverExtinguishStartedAt ~= serverStartedAt then
            -- Server and client timers have unrelated origins. Anchor remaining
            -- duration once on the local clock, never extend it on reconciliation.
            runtime.extinguishStartedAt = now - math.max(0, (duration or 0) - (remaining or duration or 0))
        end
        runtime.serverExtinguishStartedAt = serverStartedAt
        if not previousMode and Config and Config.Debug then
            debugPrint(('GroundVisuals ground flare entered extinguishing flareId=%s'):format(tostring(runtime.flareId)))
        end
    else
        runtime.extinguishing = false
        runtime.extinguishDurationMilliseconds = nil
        runtime.extinguishStartedAt = nil
        runtime.serverExtinguishStartedAt = nil
        runtime.extinguishRemainingMilliseconds = nil
        runtime.extinguishCompleted = nil
        runtime.extinguishCompletedAt = nil
    end

    local particleEnabled = runtime.particleActive
    if previousMode and not extinguishMode and particleEnabled then
        stopParticle(runtime, 'extinguish_cancelled')
    end
    if extinguishMode and not particleEnabled and safeRecord.extinguishDurationMilliseconds and safeRecord.extinguishDurationMilliseconds > 0 then
        if Config and Config.Debug then
            debugPrint(('GroundVisuals particle fade started flareId=%s'):format(tostring(runtime.flareId)))
        end
    end
end

local function runReconcile()
    local generation = state.generation
    state.reconcilerRunning = true

    while state.generation == generation and state.running do
        local cfg = state.config
        if not cfg or not cfg.Enabled then
            break
        end

        local count = countRuntimes()
        if count == 0 then
            break
        end

        local localBucket = getLocalBucket()
        local now = nowMilliseconds()
        local ped = PlayerPedId()
        local pedCoords = GetEntityCoords(ped)

        local byFlareId = {}
        if WorldFlares then
            for _, record in ipairs(WorldFlares.getAll() or {}) do
                local safeRecord = sanitizeRecord(record)
                if safeRecord and isRecordForBucket(safeRecord, localBucket) then
                    -- WorldFlares already sanitized these coordinates. Keep them
                    -- for passive scope selection; visual metadata omits them.
                    safeRecord.coords = record.coords
                    byFlareId[safeRecord.flareId] = safeRecord
                end
            end
        end

        if RoadFlares.TrafficLite and RoadFlares.TrafficLite.reconcileScope then
            RoadFlares.TrafficLite.reconcileScope(pedCoords, byFlareId)
        end
        if RoadFlares.NativeRoutes and RoadFlares.NativeRoutes.reconcileScope then
            RoadFlares.NativeRoutes.reconcileScope(pedCoords, byFlareId)
        end
        for _, safeRecord in pairs(byFlareId) do
            local existing = state.runtimeTable[safeRecord.flareId]
            if existing then
                if existing.netId ~= safeRecord.netId then
                    stopParticle(existing, 'netid_changed')
                    if existing.netId then
                        state.netIdTable[existing.netId] = nil
                    end
                    existing.netId = safeRecord.netId
                    existing.entity = 0
                    existing.entityValid = false
                    existing.lightWanted = false
                    existing.lightStartedAt = 0
                end
                existing.routingBucket = safeRecord.routingBucket
                existing.createdAt = safeRecord.createdAt
                existing.ownerSource = safeRecord.ownerSource
                existing.lastSeenAt = now
                applyLifecycleState(existing, safeRecord, now)
            else
                state.runtimeTable[safeRecord.flareId] = createRuntime(safeRecord)
                state.netIdTable[safeRecord.netId] = safeRecord.flareId
                if Config and Config.Debug then
                    debugPrint(('GroundVisuals record upserted flareId=%s netId=%s'):format(safeRecord.flareId, tostring(safeRecord.netId)))
                end
            end
        end

        local toRemove = {}
        local candidates = {}
        for flareId, runtime in pairs(state.runtimeTable) do
            local safeRecord = byFlareId[flareId]
            if not safeRecord then
                toRemove[#toRemove + 1] = flareId
            else
                local entity, usable = resolveEntity(runtime)
                runtime.scanEntity=entity;runtime.scanUsable=usable
                local coords = usable and GetEntityCoords(entity)
                runtime.scanCoords=coords or nil
                runtime.budgetDistance = coords and Vdist(pedCoords.x, pedCoords.y, pedCoords.z, coords.x, coords.y, coords.z) or math.huge
                candidates[#candidates + 1] = runtime
            end
        end
        table.sort(candidates, function(a,b)
            if a.budgetDistance == b.budgetDistance then return tostring(a.flareId) < tostring(b.flareId) end
            return a.budgetDistance < b.budgetDistance
        end)
        local budget = { particles = 0, lights = 0 }
        for _, runtime in ipairs(candidates) do evaluateRuntime(runtime, pedCoords, localBucket, now, budget,runtime.scanEntity,runtime.scanUsable) end
        lightRuntimes = {}
        for _, runtime in ipairs(candidates) do
            if runtime.lightWanted then lightRuntimes[#lightRuntimes+1]=runtime end
        end

        for i = 1, #toRemove do
            GroundVisuals.remove(toRemove[i], 'reconcile_not_active')
        end

        if hasAnyLightNeeded() then
            startLightRenderer()
        end

        if countRuntimes() == 0 then
            break
        end
        Wait(cfg.ReconcileMilliseconds or 400)
    end

    state.reconcilerRunning = false
end

function GroundVisuals.start()
    if state.running then
        if state.config and not state.config.Enabled then
            GroundVisuals.stop('disabled')
            return false
        end
        if countRuntimes() > 0 and not state.reconcilerRunning then
            state.reconcilerRunning = true
            CreateThread(runReconcile)
        end
        return true
    end

    state.generation = state.generation + 1
    state.running = true
    state.config = resolveConfig()
    if not state.config.Enabled then
        state.running = false
        return false
    end

    state.reconcilerRunning = true
    CreateThread(runReconcile)
    return true
end

function GroundVisuals.stop(reason)
    if not state.running then
        return false
    end
    state.generation = state.generation + 1
    state.running = false
    state.reconcilerRunning = false
    state.lightRendererRunning = false
    lightRuntimes = {}
    if Config and Config.Debug then
        debugPrint(('GroundVisuals stop reason=%s'):format(tostring(reason or 'unknown')))
    end
    stopAllRuntimes(reason)
    return true
end

function GroundVisuals.clear(reason, routingBucket)
    if routingBucket ~= nil then
        clearRuntimesByBucket(routingBucket, reason or 'bucket_changed')
        return true
    end

    GroundVisuals.stop(reason)
    state.runtimeTable = {}
    state.netIdTable = {}
    assetState.isLoaded = false
    assetState.isLoading = false
    assetState.users = 0
    assetState.failUntil = 0
    assetState.loadGeneration = 0
    return true
end

function GroundVisuals.isRunning()
    return state.running
end

function GroundVisuals.getRuntime(flareId)
    if not flareId then
        return nil
    end
    return cloneRuntime(state.runtimeTable[tostring(flareId)])
end

function GroundVisuals.getActiveVisualCount()
    local count = 0
    for _, runtime in pairs(state.runtimeTable) do
        if runtime.particleActive or runtime.lightWanted then
            count = count + 1
        end
    end
    return count
end

function GroundVisuals.getDiagnostics()
    local result = { records = 0, particles = 0, lights = 0,
        reconciler = state.reconcilerRunning, renderer = state.lightRendererRunning }
    for _, runtime in pairs(state.runtimeTable) do
        result.records = result.records + 1
        if runtime.particleActive then result.particles = result.particles + 1 end
        if runtime.lightWanted then result.lights = result.lights + 1 end
    end
    return result
end

function GroundVisuals.upsert(record)
    if not state.running then
        return false
    end
    local safe = sanitizeRecord(record)
    if not safe then
        return false
    end

    local localBucket = getLocalBucket()
    if not isRecordForBucket(safe, localBucket) then
        return false
    end

    local duplicate = state.netIdTable[safe.netId]
    if duplicate and duplicate ~= safe.flareId then
        if Config and Config.Debug then
            debugPrint(('GroundVisuals netId conflict flareId=%s existing=%s netId=%s'):format(
                safe.flareId,
                tostring(duplicate),
                tostring(safe.netId)
            ))
        end
        return false
    end

    local runtime = state.runtimeTable[safe.flareId]
    if runtime then
        runtime.routingBucket = safe.routingBucket
        runtime.ownerSource = safe.ownerSource
        runtime.createdAt = safe.createdAt
        applyLifecycleState(runtime, safe, nowMilliseconds())
        runtime.lastSeenAt = nowMilliseconds()
        runtime.particleRetryAt = 0
        runtime.scopeLostAt = nil
        if runtime.netId ~= safe.netId then
            state.netIdTable[runtime.netId] = nil
            runtime.netId = safe.netId
            runtime.entity = 0
            runtime.entityValid = false
            stopParticle(runtime, 'netid_rebind')
        end
    else
        state.runtimeTable[safe.flareId] = createRuntime(safe)
        state.netIdTable[safe.netId] = safe.flareId
        if Config and Config.Debug then
            debugPrint(('GroundVisuals record upserted flareId=%s netId=%s'):format(safe.flareId, tostring(safe.netId)))
        end
    end

    if not state.reconcilerRunning and countRuntimes() > 0 then
        state.reconcilerRunning = true
        CreateThread(runReconcile)
    end
    return true
end

function GroundVisuals.remove(flareId, reason)
    local key = tostring(flareId)
    if RoadFlares.Combustion then RoadFlares.Combustion.remove('ground:'..key,reason) end
    local runtime = state.runtimeTable[key]
    if not runtime then
        return false
    end
    state.runtimeTable[key] = nil
    if runtime.netId ~= nil then
        state.netIdTable[runtime.netId] = nil
    end
    if Config and Config.Debug then
        debugPrint(('GroundVisuals flare removed flareId=%s reason=%s'):format(key, tostring(reason or 'unknown')))
    end
    stopParticle(runtime, reason or 'removed')
    runtime.lightWanted = false
    runtime.lightStartedAt = 0
    runtime.entity = 0
    return true
end

return GroundVisuals
