RoadFlares = RoadFlares or {}
RoadFlares.Client = RoadFlares.Client or {}

local Animations = {}
RoadFlares.Client.Animations = Animations

local Utils = RoadFlares.Utils
local Constants = RoadFlares.Constants

local activeAnimation = {
    name = nil,
    dictionary = nil,
    clip = nil,
    ped = nil,
    sessionToken = nil,
    isPlaying = false
}

local function debugPrint(message)
    Utils.debugPrint(message, Constants and Constants.ResourceName or 'bebecito_road_flares')
end

local function toPositiveNumber(value, fallback)
    local numberValue = tonumber(value)
    if type(numberValue) ~= 'number' or numberValue ~= numberValue or numberValue <= 0 then
        return fallback
    end
    return numberValue
end

local function toString(value)
    if type(value) ~= 'string' then
        return ''
    end
    return Utils.trim(value)
end

local function getConfiguredAnimation(name)
    local animations = (Config and Config.Animations) or {}
    local base = animations[name]
    if type(base) ~= 'table' then
        return nil
    end

    local dictionary = toString(base.Dictionary)
    local clip = toString(base.Clip)
    if dictionary == '' or clip == '' then
        return nil
    end

    local timeout = toPositiveNumber(base.DurationMilliseconds, 1000)
    local playbackRate = toPositiveNumber(base.PlaybackRate, 1.0)
    local flag = tonumber(base.Flag) or 48
    if flag < 0 or flag ~= flag then flag=48 end
    local blendIn = toPositiveNumber(base.BlendInSpeed, 4.0)
    local blendOut = toPositiveNumber(base.BlendOutSpeed, 4.0)

    return {
        dictionary = dictionary,
        clip = clip,
        timeout = toPositiveNumber(animations.LoadTimeoutMilliseconds, 5000),
        duration = timeout,
        playbackRate = playbackRate,
        flag = flag,
        blendIn = blendIn,
        blendOut = blendOut,
        source = name
    }
end

local function stopActiveAnimation(reason)
    if not activeAnimation.isPlaying then
        return false
    end

    local ped = activeAnimation.ped
    for _,model in ipairs(activeAnimation.preloadedModels or {}) do
        SetModelAsNoLongerNeeded(model)
    end
    activeAnimation.preloadedModels=nil
    if activeAnimation.cap and DoesEntityExist(activeAnimation.cap)then DeleteEntity(activeAnimation.cap)end
    activeAnimation.cap=nil
    if activeAnimation.wristGuide and DoesEntityExist(activeAnimation.wristGuide)then DeleteEntity(activeAnimation.wristGuide)end
    activeAnimation.wristGuide=nil
    if activeAnimation.ignitionPose then
        StopAnimTask(ped,'bd_roadflare_ignition','hold',3.0)
        RemoveAnimDict('bd_roadflare_ignition');activeAnimation.ignitionPose=nil
    end
    if activeAnimation.overlay then StopAnimTask(ped,'bd_roadflare_pose',activeAnimation.overlay,3.0);activeAnimation.overlay=nil end
    local dictionary = activeAnimation.dictionary
    local clip = activeAnimation.clip

    local keepCarry = reason == 'completed' and activeAnimation.keepCarry == true
    if not keepCarry and type(ped) == 'number' and DoesEntityExist(ped) and dictionary and clip then
        if IsEntityPlayingAnim(ped, dictionary, clip, 3) then
            StopAnimTask(ped, dictionary, clip, 1.0)
        end
    end

    if dictionary and not keepCarry then
        RemoveAnimDict(dictionary)
    end

    if reason then
        debugPrint(('Animation cleared reason=%s name=%s'):format(tostring(reason), tostring(activeAnimation.name)))
    end

    activeAnimation.name = nil
    activeAnimation.keepCarry = nil
    activeAnimation.placeTarget = nil
    activeAnimation.placeStart = nil
    activeAnimation.dictionary = nil
    activeAnimation.clip = nil
    activeAnimation.ped = nil
    activeAnimation.sessionToken = nil
    activeAnimation.isPlaying = false

    return true
end

local function isCurrentPed(ped)
    return ped and type(ped) == 'number' and ped ~= 0 and ped == PlayerPedId() and DoesEntityExist(ped)
end

local function isSessionStillValid(isSessionValid)
    if type(isSessionValid) ~= 'function' then
        return true
    end
    if not isSessionValid() then
        return false
    end
    return true
end

local function waitForAnimationStart(ped, dictionary, clip)
    local startedAt = Utils.nowMilliseconds()
    while not IsEntityPlayingAnim(ped, dictionary, clip, 3) do
        if not activeAnimation.isPlaying or not isCurrentPed(ped) then return false end
        if Utils.nowMilliseconds() - startedAt >= 400 then
            return false
        end
        Wait(0)
    end
    return true
end

local function waitForAnimationFinish(ped, definition, isSessionValid)
    local durationMs = definition.duration
    if definition.flag % 2 == 0 and definition.dictionary and definition.clip then
        local nativeDuration = GetAnimDuration(definition.dictionary, definition.clip)
        if type(nativeDuration) == 'number' and nativeDuration > 0.03 then
            local ms = math.floor(nativeDuration * 1000 / definition.playbackRate)
            if ms > 0 then
                durationMs = ms
            end
        end
    end

    local startedAt = Utils.nowMilliseconds()
    while Utils.nowMilliseconds() - startedAt < durationMs do
        if not isSessionStillValid(isSessionValid) then
            return false, 'session_cancelled'
        end

        local ped = activeAnimation.ped
        if not isCurrentPed(ped) or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
            return false, 'abort'
        end

        if not IsEntityPlayingAnim(ped, definition.dictionary, definition.clip, 3) then
            -- GTA blends a one-shot task out before the dictionary's nominal
            -- duration. Accept only that final release window, never an early stop.
            if Utils.nowMilliseconds()-startedAt >= durationMs*.85 then return true,nil end
            return false, 'animation_interrupted'
        end
        if activeAnimation.placeTarget then
            local p=activeAnimation.placeTarget
            local t=math.min(1,(Utils.nowMilliseconds()-startedAt)/math.max(1,durationMs))
            -- Reach the selected point and keep the hand low through release.
            -- Returning to the carrying pose here made the prop appear to jump.
            local reach=math.min(1,t/.65)
            reach=reach*reach*(3-2*reach)
            local q=activeAnimation.placeStart
            SetIkTarget(ped,4,0,-1,q.x+(p.x-q.x)*reach,q.y+(p.y-q.y)*reach,q.z+(p.z+.10-q.z)*reach,1,180,180)
        end
        Wait(0)
    end

    return true, nil
end

local function playConfiguredAnimation(animationName, ped, sessionToken, isSessionValid, target)
    if activeAnimation.isPlaying then return false,'animation_busy' end
    if not sessionToken then
        return false, 'session_cancelled'
    end

    if not isCurrentPed(ped) then
        return false, 'ped_missing'
    end

    if not isSessionStillValid(isSessionValid) then
        return false, 'session_cancelled'
    end

    local config = getConfiguredAnimation(animationName)
    if not config then
        return false, 'animation_config_invalid'
    end

    local dictionary = config.dictionary
    local clip = config.clip
    if dictionary == '' or clip == '' then
        return false, 'animation_config_invalid'
    end

    stopActiveAnimation('replaced')

    local timeout = config.timeout

    debugPrint(('Requesting animation dict=%s clip=%s for %s'):format(dictionary, clip, tostring(animationName)))

    local requestedAt = Utils.nowMilliseconds()
    activeAnimation.name = animationName
    activeAnimation.placeTarget = target
    if target then activeAnimation.placeStart=GetPedBoneCoords(ped,57005,0.0,0.0,0.0)end
    activeAnimation.dictionary = dictionary
    activeAnimation.clip = clip
    activeAnimation.ped = ped
    activeAnimation.sessionToken = sessionToken
    activeAnimation.isPlaying = true

    RequestAnimDict(dictionary)

    while not HasAnimDictLoaded(dictionary) do
        if not activeAnimation.isPlaying or not isSessionStillValid(isSessionValid) or not isCurrentPed(ped) then
            RemoveAnimDict(dictionary)
            stopActiveAnimation('cancelled')
            return false, 'session_cancelled'
        end

        if Utils.nowMilliseconds() - requestedAt >= timeout then
            RemoveAnimDict(dictionary)
            stopActiveAnimation('timeout')
            debugPrint(('Animation dict timeout dictionary=%s'):format(dictionary))
            return false, 'animation_dict_timeout'
        end

        Wait(0)
    end

    if not activeAnimation.isPlaying or not isSessionStillValid(isSessionValid) or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
        RemoveAnimDict(dictionary)
        stopActiveAnimation('abort')
        return false, 'abort'
    end

    debugPrint(('Loaded animation dict=%s'):format(dictionary))

    activeAnimation.isPlaying = true
    local playedAt = Utils.nowMilliseconds()

    -- Do not stop the grip before the crouch. Reapply it once after the new
    -- full-body task so that the gardener's open fingers cannot override it.

    TaskPlayAnim(
        ped,
        dictionary,
        clip,
        config.blendIn,
        config.blendOut,
        -1,
        config.flag,
        config.playbackRate,
        false,
        false,
        false,
        false,
        false
    )

    if animationName=='Place' then
        activeAnimation.overlay='carry'
        TaskPlayAnim(ped,'bd_roadflare_pose','carry',3.0,3.0,-1,33,1.0,false,false,false)
    end

    if not waitForAnimationStart(ped, dictionary, clip) then
        stopActiveAnimation('start_failed')
        return false, 'animation_start_failed'
    end

    debugPrint(('Animation started name=%s dictionary=%s clip=%s'):format(tostring(animationName), dictionary, clip))

    local finished, reason = waitForAnimationFinish(ped, config, isSessionValid)
    RemoveAnimDict(dictionary)

    if not finished then
        stopActiveAnimation(reason or 'animation_cancelled')
        return false, reason or 'animation_failed'
    end

    -- A clip that is no longer playing completed normally; only the session
    -- owner may classify the sequence as cancelled.
    if not isSessionStillValid(isSessionValid) then
        stopActiveAnimation('session_cancelled')
        return false, 'session_cancelled'
    end

    debugPrint(('Animation finished name=%s durationMs=%s playedMs=%s'):format(tostring(animationName), tostring(config.duration), tostring(Utils.nowMilliseconds() - playedAt)))

    stopActiveAnimation('completed')
    return true, nil
end

local function startOwnedPose(ped,clip,isSessionValid)
    if not isCurrentPed(ped) or IsEntityDead(ped) or IsPedInAnyVehicle(ped,false) or not isSessionStillValid(isSessionValid) then return false end
    local dict='bd_roadflare_pose';RequestAnimDict(dict)
    local deadline=Utils.nowMilliseconds()+3000
    while not HasAnimDictLoaded(dict)and Utils.nowMilliseconds()<deadline and activeAnimation.isPlaying and isSessionStillValid(isSessionValid)do Wait(25)end
    if not HasAnimDictLoaded(dict)or not activeAnimation.isPlaying or not isSessionStillValid(isSessionValid)then return false end
    if not IsEntityPlayingAnim(ped,dict,clip,3) then
        TaskPlayAnim(ped,dict,clip,3.0,3.0,-1,33,1.0,false,false,false)
    end
    return waitForAnimationStart(ped,dict,clip)
end
function Animations.playEquip(ped, sessionToken, isSessionValid)
    if activeAnimation.isPlaying then return false,'animation_busy' end
    activeAnimation={name='Equip',ped=ped,sessionToken=sessionToken,isPlaying=true}
    activeAnimation.dictionary='bd_roadflare_pose';activeAnimation.clip='carry';activeAnimation.keepCarry=true
    if not startOwnedPose(ped,'carry',isSessionValid)then stopActiveAnimation('cancelled');return false,'session_cancelled'end
    local deadline=Utils.nowMilliseconds()+650
    while Utils.nowMilliseconds()<deadline do
        if not activeAnimation.isPlaying or not isSessionStillValid(isSessionValid)or not isCurrentPed(ped)or IsEntityDead(ped)or IsPedInAnyVehicle(ped,false)then
            stopActiveAnimation('cancelled');return false,'session_cancelled'
        end
        Wait(25)
    end
    stopActiveAnimation('completed');return true
end

-- A temporary local orientation target follows the forearm instead of forcing
-- the wrist to the pelvis orientation. It exists only during ignition.
local function guideStrikingWrist(ped, guide, localPoint)
    local p=GetOffsetFromEntityInWorldCoords(ped,localPoint.x,localPoint.y,localPoint.z)
    local elbow=GetPedBoneCoords(ped,61163,0.0,0.0,0.0)
    local x,y,z=p.x-elbow.x,p.y-elbow.y,p.z-elbow.z
    local length=math.sqrt(x*x+y*y+z*z)
    if length<.02 then return end
    x,y,z=x/length,y/length,z/length
    -- The palm faces the carrier, so the striker is held beside the tip.
    -- Project its normal onto the forearm plane; no wrist flexion is required.
    local facing=GetEntityForwardVector(ped)
    local dot=-(facing.x*x+facing.y*y+facing.z*z)
    local ux,uy,uz=-facing.x-x*dot,-facing.y-y*dot,-facing.z-z*dot
    local upLength=math.sqrt(ux*ux+uy*uy+uz*uz)
    if upLength<.1 then return end
    ux,uy,uz=ux/upLength,uy/upLength,uz/upLength
    local fx,fy,fz=uy*z-uz*y,uz*x-ux*z,ux*y-uy*x
    SetEntityMatrix(guide,fx,fy,fz,x,y,z,ux,uy,uz,p.x,p.y,p.z)
    SetIkTarget(ped,3,guide,-1,0.0,0.0,0.0,65,120,380)
end

function Animations.playIgnite(ped, sessionToken, isSessionValid, onStrike)
    if activeAnimation.isPlaying then return false,'animation_busy' end
    -- A short original hand-strike pose; IK targets expire after each frame.
    -- It uses neither a welding tool animation nor any camera/input override.
    local start=Utils.nowMilliseconds();local duration=1800
    activeAnimation={name='Ignite',ped=ped,sessionToken=sessionToken,isPlaying=true}
    activeAnimation.dictionary='bd_roadflare_pose';activeAnimation.clip='carry'
    activeAnimation.keepCarry=true
    if not startOwnedPose(ped,'carry',isSessionValid)then stopActiveAnimation('cancelled');return false,'session_cancelled'end
    -- Pin the uncapped model before moving either hand. Streaming it at cap
    -- removal yields inside the IK path and leaves the contact clock running.
    local litModel=Config.FlareProp.LitModel
    if litModel then
        local litHash=joaat(litModel)
        activeAnimation.preloadedModels={litHash}
        RequestModel(litHash)
        local deadline=Utils.nowMilliseconds()+3000
        while not HasModelLoaded(litHash) do
            if not activeAnimation.isPlaying or not isSessionStillValid(isSessionValid) or not isCurrentPed(ped) or IsEntityDead(ped) or IsPedInAnyVehicle(ped,false) then
                stopActiveAnimation('cancelled');return false,'session_cancelled'
            end
            if Utils.nowMilliseconds()>=deadline then stopActiveAnimation('model_timeout');return false,'flare_model_load_failed'end
            Wait(0)
        end
    end
    local capHash=joaat('bd_road_flare_cap');RequestModel(capHash)
    local loadDeadline=Utils.nowMilliseconds()+3000
    while not HasModelLoaded(capHash)and Utils.nowMilliseconds()<loadDeadline and isSessionStillValid(isSessionValid)do Wait(25)end
    if not HasModelLoaded(capHash)or not activeAnimation.isPlaying or not isSessionStillValid(isSessionValid)then
        SetModelAsNoLongerNeeded(capHash);stopActiveAnimation('cancelled');return false,'session_cancelled'
    end
    local origin=GetEntityCoords(ped)
    local guide=CreateObjectNoOffset(capHash,origin.x,origin.y,origin.z,false,false,false)
    if not guide or guide==0 then
        SetModelAsNoLongerNeeded(capHash);stopActiveAnimation('anchor_failed');return false,'animation_start_failed'
    end
    activeAnimation.wristGuide=guide
    SetEntityVisible(guide,false,false);SetEntityCollision(guide,false,false)
    SetEntityHasGravity(guide,false);FreezeEntityPosition(guide,true)
    local held=RoadFlares.Client.Effects.getHeldFlare()
    if not held or not DoesEntityExist(held) then
        SetModelAsNoLongerNeeded(capHash);stopActiveAnimation('held_missing');return false,'animation_start_failed'
    end
    RequestAnimDict('bd_roadflare_ignition')
    local poseDeadline=Utils.nowMilliseconds()+2000
    while not HasAnimDictLoaded('bd_roadflare_ignition')and Utils.nowMilliseconds()<poseDeadline and activeAnimation.isPlaying and isSessionStillValid(isSessionValid)do Wait(25)end
    if not HasAnimDictLoaded('bd_roadflare_ignition')or not activeAnimation.isPlaying or not isSessionStillValid(isSessionValid)then
        RemoveAnimDict('bd_roadflare_ignition');SetModelAsNoLongerNeeded(capHash);stopActiveAnimation('cancelled');return false,'animation_dict_timeout'
    end
    activeAnimation.ignitionPose=true
    TaskPlayAnim(ped,'bd_roadflare_ignition','hold',4.0,4.0,-1,33,1.0,false,false,false)
    -- Raise the free hand while the holding arm turns, then sample the real tip.
    local settleStarted=Utils.nowMilliseconds()
    local leftStart=GetPedBoneCoords(ped,18905,0.0,0.0,0.0)
    local leftRest=GetOffsetFromEntityGivenWorldCoords(ped,leftStart.x,leftStart.y,leftStart.z)
    local settleUntil=settleStarted+400
    while Utils.nowMilliseconds()<settleUntil do
        if not activeAnimation.isPlaying or not isSessionStillValid(isSessionValid)or not isCurrentPed(ped)or IsEntityDead(ped)or IsPedInAnyVehicle(ped,false)then
            SetModelAsNoLongerNeeded(capHash);stopActiveAnimation('cancelled');return false,'session_cancelled'
        end
        local u=math.min(1,(Utils.nowMilliseconds()-settleStarted)/400);u=u*u*(3-2*u)
        guideStrikingWrist(ped,guide,{x=leftRest.x-.025*u,y=leftRest.y+(.32-leftRest.y)*u,z=leftRest.z+.12*u})
        Wait(0)
    end
    if not DoesEntityExist(held)then SetModelAsNoLongerNeeded(capHash);stopActiveAnimation('held_missing');return false,'animation_start_failed'end
    local tip=GetOffsetFromEntityInWorldCoords(held,0.0,0.0,.220)
    local head=GetOffsetFromEntityGivenWorldCoords(ped,tip.x,tip.y,tip.z)
    -- Sample the actual tip after the ignition pose has blended in. Predicting
    -- it from a nominal shoulder rotation aimed the free hand at an old point.
    -- GetPedBoneCoords still reports the base animation before the IK solve.
    -- Continue from the authored settle endpoint, not that untouched idle hand.
    local rest={x=leftRest.x-.025,y=.32,z=leftRest.z+.12}
    -- Clear the torso before crossing toward the tip. Do not drive the hand
    -- all the way back to a sampled idle point: releasing IK there caused a
    -- second visible return when the live idle pose took over.
    local front=math.max(.32,head.y+.06)
    local ignitionPoints={{0,rest.x,rest.y,rest.z},
        -- The settle already raised the hand. Continue forward at that height
        -- instead of raising it another 12 cm and visibly repeating the reach.
        {.18,rest.x-.025,front,rest.z},
        -- The 25 mm striker sits forward of the wrist. Align its striking
        -- face with the head, rather than ending the wrist 11 cm to its side.
        {.36,head.x-.047,head.y+.025,head.z+.002},
        {.54,head.x-.047,head.y-.030,head.z-.013}}
    start=Utils.nowMilliseconds();local opened=false;local struck=false;local strikeCommitted=false
    while Utils.nowMilliseconds()-start<duration do
        if not activeAnimation.isPlaying or not isSessionStillValid(isSessionValid)or not isCurrentPed(ped)or IsEntityDead(ped)or IsPedInAnyVehicle(ped,false)then
            SetModelAsNoLongerNeeded(capHash);stopActiveAnimation('cancelled');return false,'session_cancelled'
        end
        local t=(Utils.nowMilliseconds()-start)/duration
        if t>=.36 and not opened then
            local effects=RoadFlares.Client.Effects
            effects.removeHeldFlare('remove_cap')
            local ok,why=effects.createHeldFlare(ped,sessionToken,isSessionValid,Config.FlareProp.LitModel)
            if not ok then SetModelAsNoLongerNeeded(capHash);stopActiveAnimation('cancelled');return false,why end
            local p=GetEntityCoords(ped);local cap=CreateObjectNoOffset(capHash,p.x,p.y,p.z,false,false,false)
            if cap and cap~=0 then
                SetEntityCollision(cap,false,false)
                AttachEntityToEntity(cap,ped,GetPedBoneIndex(ped,18905),.08,-.02,.016,-90.0,0.0,0.0,true,true,false,true,2,true)
                activeAnimation.cap=cap
            end
            SetModelAsNoLongerNeeded(capHash);opened=true
        end
        -- The validated carrying pose keeps the right fist and wrist neutral.
        -- The left reach and brief holding-arm turn use the carrier basis.
        if t>=.54 and not strikeCommitted then
            strikeCommitted=true
            if onStrike then
                local ok,why=onStrike()
                if not ok then SetModelAsNoLongerNeeded(capHash);stopActiveAnimation('strike_failed');return false,why end
            end
            struck=true
            if RoadFlares.Audio and RoadFlares.Audio.oneShot then RoadFlares.Audio.oneShot('strike',GetEntityCoords(ped))end
        end
        if t>=.78 and activeAnimation.ignitionPose then
            -- Keep the turn through contact and the 380 ms left-hand release.
            -- Only then restore the approved grip once.
            TaskPlayAnim(ped,'bd_roadflare_pose','carry',4.0,4.0,-1,33,1.0,false,false,false)
            activeAnimation.ignitionPose=nil;RemoveAnimDict('bd_roadflare_ignition')
        end
        local points=ignitionPoints
        local left
        for i=2,#points do
            local a,b=points[i-1],points[i]
            if t<=b[1]then
                local u=math.max(0,math.min(1,(t-a[1])/(b[1]-a[1])));u=u*u*(3-2*u)
                left={x=a[2]+(b[2]-a[2])*u,y=a[3]+(b[3]-a[3])*u,z=a[4]+(b[4]-a[4])*u}
                break
            end
        end
        -- One handoff: immediately after the strike, stop submitting IK targets.
        -- Its 380 ms blend-out returns to the current base pose once. Keep the
        -- guide alive until the fade has finished; the right carry is untouched.
        if left then guideStrikingWrist(ped,guide,left)end
        Wait(t>.54 and 25 or 0)
    end
    SetModelAsNoLongerNeeded(capHash);stopActiveAnimation('completed');return true
end

function Animations.playPlace(ped, sessionToken, isSessionValid, target)
    return playConfiguredAnimation('Place', ped, sessionToken, isSessionValid, target)
end

local function waitForDelay(milliseconds, isSessionValid)
    local delay = toPositiveNumber(milliseconds, 0)
    if delay <= 0 then
        return true
    end

    local target = Utils.nowMilliseconds() + delay
    while Utils.nowMilliseconds() < target do
        if not isSessionStillValid(isSessionValid) then
            return false
        end
        Wait(0)
    end
    return true
end

function Animations.playExtinguishTap(ped, sessionToken, isSessionValid)
    if activeAnimation.isPlaying then return false,'animation_busy' end
    if not isCurrentPed(ped)or not sessionToken then return false,'ped_missing'end
    local dictionary='amb@world_human_gardener_plant@male@base';local clip='base'
    activeAnimation={name='ExtinguishTap',dictionary=dictionary,clip=clip,ped=ped,sessionToken=sessionToken,isPlaying=true}
    RequestAnimDict(dictionary);local deadline=Utils.nowMilliseconds()+1000
    while not HasAnimDictLoaded(dictionary)and Utils.nowMilliseconds()<deadline and activeAnimation.isPlaying and isSessionStillValid(isSessionValid)do Wait(0)end
    if not HasAnimDictLoaded(dictionary)or not activeAnimation.isPlaying or not isSessionStillValid(isSessionValid)then stopActiveAnimation('load_cancelled');return false,'animation_dict_timeout'end
    TaskPlayAnim(ped,dictionary,clip,4.0,4.0,3600,1,1.0,false,false,false)
    local untilAt=Utils.nowMilliseconds()+3600
    while Utils.nowMilliseconds()<untilAt do
        if not activeAnimation.isPlaying or not isCurrentPed(ped)or IsEntityDead(ped)or IsPedInAnyVehicle(ped,false)or not isSessionStillValid(isSessionValid)then
            stopActiveAnimation('cancelled');return false,'session_cancelled'
        end
        Wait(0)
    end
    stopActiveAnimation('completed');return true
end

function Animations.cancel(reason)
    return stopActiveAnimation(reason)
end

function Animations.clear(reason)
    stopActiveAnimation(reason)
    activeAnimation = {
        name = nil,
        dictionary = nil,
        clip = nil,
        ped = nil,
        sessionToken = nil,
        isPlaying = false
    }
    return true
end

function Animations.isPlaying()
    return activeAnimation.isPlaying == true
end

function Animations.getCurrent()
    if not activeAnimation.isPlaying and not activeAnimation.name then
        return nil
    end
    return {
        name = activeAnimation.name,
        dictionary = activeAnimation.dictionary,
        clip = activeAnimation.clip,
        ped = activeAnimation.ped,
        sessionToken = activeAnimation.sessionToken,
        isPlaying = activeAnimation.isPlaying
    }
end
