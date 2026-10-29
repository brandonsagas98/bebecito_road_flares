-- Distance-culled combustion renderer: original world-space smoke and native flare glow.
-- This module never captures input or changes the gameplay camera.
RoadFlares=RoadFlares or {}
local C={};RoadFlares.Combustion=C
local entries,visible,smokeList,spent={},{},{},{}
local lingering={}
local smokeBudget=0
local distant={}
local SMOKE_LIFETIME=4.2
local running=false;local generation=0;local textureReady=false;local txd
local textureRetryAt=0;local flameHandle,smokeHandle,glowHandle;local textureError
local smokeAmbient=1
local frameTriangles,frameSmokeQuads,frameSmokeLimit=0,0,256
-- Resolve the same native once. Every argument below is already a scalar with
-- the correct ABI type, and the texture dictionary/name are constant strings. This skips
-- the generated Lua wrapper/hash lookup for hundreds of triangles per frame.
local submitPoly=Citizen and Citizen.GetNative and Citizen.GetNative(0x29280002282F1928)or DrawTexturedPoly
local function smokePuffLimit()
    return math.max(24,math.min(256,math.floor(tonumber(Config.Realism and Config.Realism.MaximumSmokePuffs)or 256)))
end
local function drawPoly(...)
    -- Keep transient graphics submissions bounded even during mass removals.
    if frameTriangles>=960 then return end
    frameTriangles=frameTriangles+1;submitPoly(...)
end
local V={};RoadFlares.Visuals=V
local uvFrames={}
for f=0,15 do
    local u,v=(f%4)/4,math.floor(f/4)/4
    uvFrames[f]={{u,v+.25},{u+.25,v+.25},{u+.25,v},{u,v}}
end
local function now()return GetGameTimer()end
local function stopFx(r,key)
    local handle=r[key]
    if key=='smoke' then r.smoke=nil;return end
    if handle then StopParticleFxLooped(handle,false);r[key]=nil end
end
local function remove(key)
    local r=entries[key];if not r then return end
    if RoadFlares.Audio and RoadFlares.Audio.remove then RoadFlares.Audio.remove(key)end
    if r.sceneEntity and DoesEntityExist(r.sceneEntity)then DeleteEntity(r.sceneEntity)end
    if r.manualModel then SetModelAsNoLongerNeeded(r.manualModel)end
    stopFx(r,'smoke');stopFx(r,'glow');entries[key]=nil
end
local function visualEntity(r)return r.sceneEntity or r.entity end
local function manualScene(r,t)
    if not r.manualActorSource or not r.stoppingAt then return end
    local progress=math.max(0,math.min(1,(t-r.stoppingAt)/(r.fadeDuration or 4000)))
    if progress<.2 then return end
    if not r.sceneEntity then
        local model=r.manualModel
        if not model then model=joaat('bd_road_flare_lit'..((r.stage or 0)>0 and('_'..r.stage)or''));r.manualModel=model;RequestModel(model)end
        if not HasModelLoaded(model)then return end
        local p=GetEntityCoords(r.entity);r.sceneBase={x=p.x,y=p.y,z=p.z}
        local e=CreateObjectNoOffset(model,p.x,p.y,p.z,false,false,false);SetModelAsNoLongerNeeded(model)
        if not e or e==0 then return end
        SetEntityCollision(e,false,false);FreezeEntityPosition(e,true);r.sceneEntity=e
    end
    local p=r.sceneBase;local lift=.08
    if RoadFlares.Audio and RoadFlares.Audio.oneShot then
        if progress>=.62 and progress<.70 and not r.tapSound1 then r.tapSound1=true;RoadFlares.Audio.oneShot('tap',p)end
        if progress>=.78 and progress<.86 and not r.tapSound2 then r.tapSound2=true;RoadFlares.Audio.oneShot('tap',p)end
    end
    if progress<.55 then lift=.08*math.sin((progress-.2)/.35*math.pi*.5)
    elseif progress<.87 then lift=.07*math.abs(math.sin((progress-.55)/.32*math.pi*2))
    else lift=0 end
    -- The cold end is grasped, then the burning head taps the pavement twice.
    SetEntityCoordsNoOffset(r.sceneEntity,p.x,p.y,p.z+r.tip+.012+lift,false,false,false)
    SetEntityRotation(r.sceneEntity,180.0,0.0,0.0,2,true)
    SetEntityLocallyInvisible(r.entity)
    local player=GetPlayerFromServerId(r.manualActorSource)
    if player and player~=-1 then
        local ped=GetPlayerPed(player)
        if DoesEntityExist(ped)then
            local actor=GetEntityCoords(ped)
            local dx,dy=actor.x-p.x,actor.y-p.y
            -- Never stretch an actor's arm if they walk away during the scene.
            if dx*dx+dy*dy<=.85*.85 and math.abs(actor.z-p.z)<1.6 then
                SetIkTarget(ped,4,0,-1,p.x,p.y,p.z+r.tip+.012+lift,0,100,100)
            end
        end
    end
end
local function remaining(r,t)
    if not r.stoppingAt then return 1 end
    return math.max(0,1-(t-r.stoppingAt)/(r.fadeDuration or 450))
end
local function smoke(r)
    if not r.smoke then r.smoke={puffs={},nextAt=now()+(r.seed%160)}end
end
local function glow(r)
    if not(r.held or r.remote)or r.glow or not HasNamedPtfxAssetLoaded('core') then return end
    UseParticleFxAssetNextCall('core')
    local handle=StartParticleFxLoopedOnEntity('proj_flare_fuse',r.entity,0.0,0.0,r.tip,0.0,0.0,0.0,.18,false,false,false)
    if type(handle)=='number'and handle>0 and DoesParticleFxLoopedExist(handle)then r.glow=handle end
end
local function texture()
    if textureReady then return true end
    if now()<textureRetryAt then return false end
    textureRetryAt=now()+5000
    txd=txd or CreateRuntimeTxd('bd_flare_combustion')
    if not flameHandle then local ok,h=pcall(CreateRuntimeTextureFromImage,txd,'flame','textures/combustion.png');if ok and h and h~=0 then flameHandle=h else textureError='flame: '..tostring(h) end end
    if not smokeHandle then local ok,h=pcall(CreateRuntimeTextureFromImage,txd,'smoke','textures/smoke.png');if ok and h and h~=0 then smokeHandle=h else textureError='smoke: '..tostring(h) end end
    if not glowHandle then local ok,h=pcall(CreateRuntimeTextureFromImage,txd,'halo','textures/glow.png');if ok and h and h~=0 then glowHandle=h else textureError='halo: '..tostring(h)end end
    textureReady=flameHandle~=nil and smokeHandle~=nil and glowHandle~=nil
    if textureReady then textureError=nil end
    return textureReady
end
-- Native UV arguments must remain Lua floats (integer 1 is a different ABI value).
local smokeUV={{0.0,1.0},{1.0,1.0},{1.0,0.0},{0.0,0.0}}
local function smokeTriangle(a,b,c,u,v,w,alpha,red,green,blue)
    -- Avoid a second Lua call/vararg forwarding for each smoke triangle.
    if frameTriangles>=960 then return end
    frameTriangles=frameTriangles+1
    submitPoly(a.x,a.y,a.z,b.x,b.y,b.z,c.x,c.y,c.z,red,green,blue,alpha,'bd_flare_combustion','smoke',u[1],u[2],1.0,v[1],v[2],1.0,w[1],w[2],1.0)
end
-- Full camera-facing basis, including overhead views. No horizontal-distance cutout.
local function cameraBasis(camera,x,y,z)
    local dx,dy,dz=camera.x-x,camera.y-y,camera.z-z
    local horizontal=math.sqrt(dx*dx+dy*dy);local length=math.sqrt(dx*dx+dy*dy+dz*dz)
    if length<.0001 then return end
    local rx,ry=1.0,0.0
    if horizontal>.0001 then rx,ry=-dy/horizontal,dx/horizontal end
    return rx,ry,-dz*ry/length,dz*rx/length,(dx*ry-dy*rx)/length
end
local function drawSmoke(r,camera,t)
    local s=r.smoke;if not s or(not r.retired and not r.frameValid)then return end
    if not r.retired and t>=s.nextAt and remaining(r,t)>.05 then
        local p=r.frameTip or GetOffsetFromEntityInWorldCoords(visualEntity(r),0.0,0.0,r.tip)
        -- World-space birth positions preserve the trail when the carrier walks.
        local count=r.smokeQuality or 24
        while #s.puffs>=count do table.remove(s.puffs,1)end
        local wind=r.wind or{x=0,y=0};local phase=r.seed+t*.001
        local rotation=phase*2.39996
        local nozzle=GetOffsetFromEntityInWorldCoords(visualEntity(r),0.0,0.0,r.tip+.04)
        s.puffs[#s.puffs+1]={x=p.x,y=p.y,z=p.z,born=t,strength=remaining(r,t),vx=wind.x*.24+math.sin(phase)*.035,vy=wind.y*.24+math.cos(phase)*.035,cos=math.cos(rotation),sin=math.sin(rotation),jx=(nozzle.x-p.x)*2,jy=(nozzle.y-p.y)*2,jz=(nozzle.z-p.z)*2}
        s.nextAt=t+math.floor(SMOKE_LIFETIME*1000/count)
    end
    -- One facing basis per smoke trail rather than two square roots per puff.
    -- Parallel quads remain visible from overhead without changing puff motion.
    local head=s.puffs[#s.puffs]
    if not head then return end
    local brx,bry,bux,buy,buz=cameraBasis(camera,head.x,head.y,head.z)
    s.points=s.points or{{},{},{},{}}
    local a,b,c,d=table.unpack(s.points)
    local u,v,w,k=table.unpack(smokeUV)
    local base=255*smokeAmbient;local emberAmbient=1-smokeAmbient
    local neutral=emberAmbient==0 and math.floor(base) or nil
    local opacity=(r.smokeOpacity or 1)*math.max(0,math.min(4,tonumber(Config.Realism and Config.Realism.SmokeDensityMultiplier)or 1))
    for i=#s.puffs,1,-1 do
        local q=s.puffs[i];local age=(t-q.born)/1000
        if age>=SMOKE_LIFETIME then table.remove(s.puffs,i)
        elseif brx and frameSmokeQuads<frameSmokeLimit then
            local jet=math.min(1,age*4)
            local x=q.x+q.vx*age+(q.jx or 0)*jet
            local y=q.y+q.vy*age+(q.jy or 0)*jet
            local curl=math.sin(age*2.1+q.born*.003)*age*.025
            x=x+curl;y=y+math.cos(age*1.7+q.born*.002)*age*.02
            local z=q.z+age*.48+(q.jz or 0)*jet;local size=.09+age*.19
            local rx,ry,ux,uy,uz=brx,bry,bux,buy,buz
            if rx and frameSmokeQuads<frameSmokeLimit then
                frameSmokeQuads=frameSmokeQuads+1
                local co,si=q.cos or 1,q.sin or 0
                rx,ry,ux,uy,uz=(brx*co+bux*si)*size,(bry*co+buy*si)*size,(-brx*si+bux*co)*size,(-bry*si+buy*co)*size,buz*co*size
                local rz=buz*si*size
                -- Already-emitted smoke keeps its own lifetime when combustion stops.
                local fade=math.min(1,age*8)*(1-age/SMOKE_LIFETIME)^1.25*(q.strength or 1)
                -- Preserve plume density when the distant tier uses fewer quads.
                local alpha=math.floor(math.min(245,155*fade*opacity))
                -- Both halves of one puff have identical lighting and age.
                local red,green,blue=neutral,neutral,neutral
                if not neutral then
                    local ember=math.exp(-age*4)*emberAmbient
                    red=math.floor(math.min(255,base+ember*125))
                    green=math.floor(base+ember*20)
                    blue=math.floor(base+ember*8)
                end
                a.x=x-rx-ux;a.y=y-ry-uy;a.z=z-rz-uz;b.x=x+rx-ux;b.y=y+ry-uy;b.z=z+rz-uz
                c.x=x+rx+ux;c.y=y+ry+uy;c.z=z+rz+uz;d.x=x-rx+ux;d.y=y-ry+uy;d.z=z-rz+uz
                smokeTriangle(a,b,c,u,v,w,alpha,red,green,blue);smokeTriangle(a,c,d,u,w,k,alpha,red,green,blue)
            end
        end
    end
end
local function triangle(a,b,c,uv1,uv2,uv3,alpha)
    drawPoly(a.x,a.y,a.z,b.x,b.y,b.z,c.x,c.y,c.z,255,255,255,alpha,'bd_flare_combustion','flame',uv1[1],uv1[2],1.0,uv2[1],uv2[2],1.0,uv3[1],uv3[2],1.0)
end
local function flame(r,camera,t,far,simplified)
    if frameTriangles>956 then return end
    if not r.frameValid then return end
    local p=r.frameTip or GetOffsetFromEntityInWorldCoords(visualEntity(r),0.0,0.0,r.tip)
    local rightX,rightY,upX,upY,upZ=cameraBasis(camera,p.x,p.y,p.z)
    if not rightX then return end
    local phase=t*.013+r.seed;local h=.145+.008*math.sin(phase)+.005*math.sin(phase*2.3)
    local width=.060+.003*math.sin(phase*.7)
    local distance=math.sqrt(r.distance or 0)
    local coreBlend=1-math.max(0,math.min(1,(distance-25)/20))
    if simplified or frameTriangles>954 then coreBlend=0 end
    -- Preserve the near silhouette across the LOD boundary; distant pixels need
    -- a bounded optical footprint to remain a useful road-warning signal.
    if far then width=math.max(width,math.min(.28,distance*.0018));h=math.max(h,math.min(.40,distance*.0024))end
    -- Looking down a rising flame exposes its compact head, not its full side profile.
    h=h*math.max(.24,upZ)
    local wind=r.wind or {x=0,y=0};local bendX=wind.x*.008;local bendY=wind.y*.008
    r.points=r.points or {{},{},{},{}}
    local a,b,c,d=table.unpack(r.points)
    a.x=p.x-rightX*width;a.y=p.y-rightY*width;a.z=p.z-.004
    b.x=p.x+rightX*width;b.y=p.y+rightY*width;b.z=p.z-.004
    c.x=p.x+rightX*width+upX*h+bendX;c.y=p.y+rightY*width+upY*h+bendY;c.z=p.z+upZ*h
    d.x=p.x-rightX*width+upX*h+bendX;d.y=p.y-rightY*width+upY*h+bendY;d.z=p.z+upZ*h
    local f=(math.floor(t/42)+r.seed)%16
    local uvA,uvB,uvC,uvD=table.unpack(uvFrames[f])
    local ramp=remaining(r,t)
    local alpha=math.floor(255*ramp)
    do
        -- A compact optical halo around the incandescent root, not a second fire.
        -- Blend the optical footprint in gradually so the 35m detail boundary
        -- never changes the source size in a single frame.
        local opticalBlend=math.max(0,math.min(1,(distance-30)/60))
        local radius=.115+.005*math.sin(phase*.73)+opticalBlend*math.min(.885,distance*.00635)
        -- Optical halo only: double luminous area without enlarging the flame.
        radius=radius*math.sqrt(math.max(0,math.min(4,tonumber(Config.Realism and Config.Realism.HaloAreaMultiplier)or 1)))
        local x,y,z=p.x,p.y,p.z+.018
        r.haloPoints=r.haloPoints or {{},{},{},{}}
        local a,b,c,d=table.unpack(r.haloPoints)
        a.x=x-rightX*radius-upX*radius;a.y=y-rightY*radius-upY*radius;a.z=z-upZ*radius
        b.x=x+rightX*radius-upX*radius;b.y=y+rightY*radius-upY*radius;b.z=z-upZ*radius
        c.x=x+rightX*radius+upX*radius;c.y=y+rightY*radius+upY*radius;c.z=z+upZ*radius
        d.x=x-rightX*radius+upX*radius;d.y=y-rightY*radius+upY*radius;d.z=z+upZ*radius
        local u,v,w,k=table.unpack(smokeUV)
        local haloAlpha=math.floor(alpha*(.80+.20*coreBlend))
        drawPoly(a.x,a.y,a.z,b.x,b.y,b.z,c.x,c.y,c.z,255,255,255,haloAlpha,'bd_flare_combustion','halo',u[1],u[2],1.0,v[1],v[2],1.0,w[1],w[2],1.0)
        drawPoly(a.x,a.y,a.z,c.x,c.y,c.z,d.x,d.y,d.z,255,255,255,haloAlpha,'bd_flare_combustion','halo',u[1],u[2],1.0,w[1],w[2],1.0,k[1],k[2],1.0)
    end
    if coreBlend>0 then
        -- Compact incandescent core uses the same frame and source position.
        -- It adds density without a second animated flame or larger crown.
        r.corePoints=r.corePoints or{{},{},{},{}}
        for i,v in ipairs(r.points)do
            local q=r.corePoints[i];q.x=p.x+(v.x-p.x)*.65;q.y=p.y+(v.y-p.y)*.65;q.z=p.z+(v.z-p.z)*.65
        end
        local q,w,e,k=table.unpack(r.corePoints);local coreAlpha=math.floor(170*ramp*coreBlend)
        triangle(q,w,e,uvA,uvB,uvC,coreAlpha);triangle(q,e,k,uvA,uvC,uvD,coreAlpha)
    end
    triangle(a,b,c,uvA,uvB,uvC,alpha);triangle(a,c,d,uvA,uvC,uvD,alpha)
    -- This billboard always faces the camera; reverse faces would double its cost.
end
local function sparks(r,t)
    if not DrawLine or (Config.Realism and Config.Realism.Sparks==false)then return end
    if not r.held and (r.distance or 0)>64 then return end
    local p=r.frameTip;if not p then return end
    local cycle=t+r.seed*19
    r.sparkPaths=r.sparkPaths or {}
    for i=0,3 do
        local phase=cycle+i*223;local burst=math.floor(phase/1250)
        local age=(phase%1250)/1000
        if age<.28 then
            local path=r.sparkPaths[i]
            if not path or path.burst~=burst then
                local direction=r.seed+i*2.4+burst*2.1
                path={burst=burst,vx=math.cos(direction)*.25,vy=math.sin(direction)*.25,vz=.46+(i%3)*.07};r.sparkPaths[i]=path
            end
            local tail=math.max(0,age-.04)
            local za=p.z+.018+tail*path.vz-tail*tail*.95
            local zb=p.z+.018+age*path.vz-age*age*.95
            DrawLine(p.x+path.vx*tail,p.y+path.vy*tail,za,p.x+path.vx*age,p.y+path.vy*age,zb,255,175,90,math.floor(230*(1-age/.28)*remaining(r,t)))
            if (r.stage or 0)>0 and i%2==0 then
                local ax=p.x-path.vx*age*.45;local ay=p.y-path.vy*age*.45
                local az=p.z+age*.12-age*age*.55
                DrawLine(ax,ay,az,ax+.0015,ay+.001,az+.003,154,148,137,math.floor(140*(1-age/.28)*remaining(r,t)))
            end
        end
    end
end
local function start()
    if running then return end
    running=true;generation=generation+1;local epoch=generation
    CreateThread(function()
        while running and generation==epoch do
            local player=GetEntityCoords(PlayerPedId());local candidates={};local total=0;local needsNativeGlow=false;distant={}
            local hour=GetClockHours and GetClockHours()or 13
            local ambient=RoadFlares.Realism.ambientLight(hour,GetClockMinutes and GetClockMinutes()or 0)
            smokeAmbient=.40+.60*(1-ambient)/.70
            local direction=GetWindDirection and GetWindDirection()or{x=0,y=0,z=0}
            local speed=GetWindSpeed and math.min(2.5,math.max(.15,GetWindSpeed()*.35))or 1
            local wind={x=direction.x*speed,y=direction.y*speed}
            local limit=(Config.Realism and Config.Realism.DetailDistance)or 35
            for key,r in pairs(entries)do
                r.customSelected=false
                if (not r.swapping and not DoesEntityExist(r.entity))or(r.validator and not r.validator())then remove(key)
                else
                    total=total+1;local p=GetEntityCoords(r.entity)
                    if r.held or r.remote then needsNativeGlow=true end
                    if r.physicsCarrier then
                        local dx,dy,dz=p.x-(r.lastX or p.x),p.y-(r.lastY or p.y),p.z-(r.lastZ or p.z)
                        r.moving=dx*dx+dy*dy+dz*dz>.000001
                        r.lastX,r.lastY,r.lastZ=p.x,p.y,p.z
                    end
                    r.distance=(p.x-player.x)^2+(p.y-player.y)^2+(p.z-player.z)^2
                    r.wind=wind
                    if r.remote then glow(r)end
                    local smokeDistance=(Config.Realism and Config.Realism.SmokeDistance)or 60
                    local glowDistance=(Config.Realism and Config.Realism.GlowDistance)or 120
                    local fullSmoke=(Config.Realism and Config.Realism.FullSmokeDistance)or 8
                    r.smokeQuality=(r.held or r.distance<=fullSmoke*fullSmoke)and 24 or(r.distance>80*80 and 6 or 10)
                    if r.held or r.distance<=smokeDistance*smokeDistance then candidates[#candidates+1]=r
                    elseif r.distance<=glowDistance*glowDistance then distant[#distant+1]=r;r.customSelected=true end
                    r.far=r.distance>limit*limit
                    if r.held and r.deadline and RoadFlares.Client.Deployment.getState()=='DEPLOYMENT_READY' then
                        local duration=(Config.FlareDurationMinutes or 15)*60000
                        local stage=RoadFlares.Realism.stage(r.deadline-duration,duration,now())
                        if stage~=r.stage and not r.swapping then
                            r.swapping=true
                            CreateThread(function()
                                local effects=RoadFlares.Client.Effects
                                local model=stage==0 and 'bd_road_flare_lit'or('bd_road_flare_lit_'..stage)
                                -- Keep the old prop until the replacement is resident.
                                local hash=joaat(model);RequestModel(hash);local loadDeadline=now()+3000
                                while not HasModelLoaded(hash)and now()<loadDeadline and entries.held==r and r.validator()do Wait(25)end
                                if not HasModelLoaded(hash)or entries.held~=r or not r.validator()then
                                    SetModelAsNoLongerNeeded(hash);r.swapping=false;return
                                end
                                effects.removeHeldFlare('burn_stage')
                                local ok=effects.createHeldFlare(r.ped,r.token,r.validator,model)
                                SetModelAsNoLongerNeeded(hash)
                                if ok and entries.held==r then
                                    stopFx(r,'glow');r.entity=effects.getHeldFlare();r.stage=stage;r.tip=Config.BurnModels[stage+1].length
                                end
                                r.swapping=false
                            end)
                        end
                    end
                end
            end
            table.sort(candidates,function(a,b)if a.held~=b.held then return a.held==true end;return a.distance<b.distance end)
            visible={};smokeList={};local detailList={}
            local detailMax=math.max(0,math.floor(tonumber(Config.Realism and Config.Realism.MaximumDetailedFlames)or 0))
            if detailMax==0 then detailMax=#candidates end
            local smokeMax=math.max(0,math.floor(tonumber(Config.Realism and Config.Realism.MaximumSmokeEmitters)or 0))
            if smokeMax==0 then smokeMax=detailMax end
            smokeMax=math.min(detailMax,smokeMax)
            smokeMax=math.min(smokeMax,smokePuffLimit())
            local perEmitter=math.max(1,math.floor(smokePuffLimit()/math.max(1,math.min(#candidates,smokeMax))))
            smokeBudget=smokeMax+#lingering
            for i,r in ipairs(candidates)do
                if i<=detailMax then visible[#visible+1]=r;detailList[r]=true;r.customSelected=true end
                if i<=smokeMax then
                    local desired=r.smokeQuality
                    r.smokeQuality=math.min(desired,perEmitter)
                    r.smokeOpacity=math.min(1.8,(desired==6 and 1.35 or 1)*math.sqrt(desired/r.smokeQuality))
                    smokeList[r]=true;smoke(r)
                end
                glow(r)
            end
            for _,r in pairs(entries)do
                if not smokeList[r]then stopFx(r,'smoke')end
                if not detailList[r]and r.sceneEntity then DeleteEntity(r.sceneEntity);r.sceneEntity=nil;r.sceneBase=nil end
            end
            for i=#lingering,1,-1 do if now()-lingering[i].retiredAt>=SMOKE_LIFETIME*1000 then table.remove(lingering,i)end end
            if total==0 and #lingering==0 then break end
            if needsNativeGlow and not HasNamedPtfxAssetLoaded('core')then RequestNamedPtfxAsset('core')end
            Wait(400)
        end
        if generation==epoch then running=false;visible={}end
    end)
    CreateThread(function()
        while running and generation==epoch do
            local frameAt=now()
            frameTriangles=0;frameSmokeQuads=0;frameSmokeLimit=smokePuffLimit()
            for _,r in ipairs(visible)do
                -- No yields occur between this validation and the draw passes.
                r.frameValid=entries[r.key]==r and DoesEntityExist(r.entity)
                r.inView=false
                if r.frameValid then
                    manualScene(r,frameAt)
                    if r.held or r.remote or r.moving or r.manualActorSource or not r.frameTip then r.frameTip=GetOffsetFromEntityInWorldCoords(visualEntity(r),0.0,0.0,r.tip)end
                end
            end
            if RoadFlares.Audio and RoadFlares.Audio.update then RoadFlares.Audio.update(visible)end
            if (#visible>0 or #distant>0 or #lingering>0)and texture()then
                local camera=(GetFinalRenderedCamCoord or GetGameplayCamCoord)();local t=frameAt
                local smokeSlots=smokeBudget
                local simplified=#visible+#distant>128
                -- Warning sources have priority over smoke when the shared draw
                -- budget is busy. Reduce the extra core before hiding a signal.
                for _,r in ipairs(visible)do if entries[r.key]==r and r.frameValid then
                    r.inView=not IsSphereVisible or IsSphereVisible(r.frameTip.x,r.frameTip.y,r.frameTip.z+1.0,2.5)
                    if r.inView then
                        flame(r,camera,t,r.far,simplified);sparks(r,t)
                    end
                    if r.smoke then smokeSlots=smokeSlots-1 end
                end end
                for _,r in ipairs(distant)do
                    r.frameValid=entries[r.key]==r and DoesEntityExist(r.entity)
                    if r.frameValid then
                    if r.remote or not r.frameTip then r.frameTip=GetOffsetFromEntityInWorldCoords(r.entity,0.0,0.0,r.tip)end
                    if not IsSphereVisible or IsSphereVisible(r.frameTip.x,r.frameTip.y,r.frameTip.z,.5)then flame(r,camera,t,true,simplified)end
                end end
                for _,r in ipairs(visible)do if entries[r.key]==r and r.inView then drawSmoke(r,camera,t)end end
                for i=#lingering,math.max(1,#lingering-smokeSlots+1),-1 do drawSmoke(lingering[i],camera,t)end
            end
            local r=entries.held
            if r and DoesEntityExist(r.entity)then
                local p=r.frameTip or GetOffsetFromEntityInWorldCoords(r.entity,0,0,r.tip)
                local light=Config.FlareVisuals.Light
                if light.Enabled~=false then
                    local ambient=RoadFlares.Realism.ambientLight(GetClockHours and GetClockHours()or 13,GetClockMinutes and GetClockMinutes()or 0)
                    local flicker=RoadFlares.Realism.lightFlicker(light.Flicker,now(),r.seed)
                    DrawLightWithRange(p.x,p.y,p.z+.01,light.Color.r,light.Color.g,light.Color.b,light.Range,light.Intensity*ambient*flicker*remaining(r,now()))
                end
            end
            if #visible==0 and #distant==0 and #lingering==0 and not r then Wait(150)else Wait(0)end
        end
    end)
end
function C.upsert(key,entity,data)
    if not DoesEntityExist(entity)then return end
    local r=entries[key]
    if r and r.entity~=entity then
        -- Burning replaces the mesh, not the world-space plume already emitted.
        stopFx(r,'glow')
        if r.sceneEntity and DoesEntityExist(r.sceneEntity)then DeleteEntity(r.sceneEntity)end
        r.sceneEntity=nil;r.sceneBase=nil;r.entity=entity;r.frameTip=nil
    end
    if not r then
        local seed=0;for i=1,#key do seed=(seed*31+key:byte(i))%997 end
        r={key=key,entity=entity,seed=seed,tip=data.tipLength or .220};entries[key]=r
    end
    r.tip=data.tipLength or r.tip;r.ground=true;r.remote=data.remote==true;r.ped=data.ped
    r.physicsCarrier=data.physicsCarrier==true
    if r.physicsCarrier then r.frameTip=nil end
    if data.burnStage~=r.stage or r.entity~=entity then r.frameTip=nil end
    r.stage=data.burnStage or r.stage;r.manualActorSource=data.manualActorSource
    r.stoppingAt=data.extinguishing and data.extinguishStartedAt or nil
    r.fadeDuration=data.extinguishDurationMilliseconds or 450
    start()
end
function C.getVisualEntity(key)
    local r=entries[key];return r and r.sceneEntity
end
function C.hasGroundEffects(key)
    local r=entries[key]
    return textureReady and r~=nil and r.customSelected==true
end
function C.remove(key,reason)
    local r=entries[key]
    if r and r.smoke and(reason=='automatic_expired'or reason=='manual_extinguished')then
        lingering[#lingering+1]={smoke=r.smoke,smokeOpacity=r.smokeOpacity,smokeQuality=r.smokeQuality,retired=true,retiredAt=now()}
    end
    remove(key)
end
function C.spawnSpent(data)
    -- A server removal carries the pose: the network entity may already be gone.
    if data.reason=='automatic_expired'or data.reason=='manual_extinguished' then
        local p,rotation=data.coords,data.rotation
        if type(p)~='table'or type(rotation)~='table'then return end
        for _,key in ipairs({'x','y','z'})do
            for _,vector in ipairs({p,rotation})do
                local v=vector[key]
                if type(v)~='number'or v~=v or math.abs(v)>100000 then return end
            end
        end
        local player=GetEntityCoords(PlayerPedId())
        if (p.x-player.x)^2+(p.y-player.y)^2+(p.z-player.z)^2>10000 then return end
        local epoch=generation
        CreateThread(function()
            local stage=math.max(0,math.min(3,math.floor(tonumber(data.burnStage)or 0)))
            local model=data.reason=='manual_extinguished' and Config.BurnModels[stage+1].name or 'bd_road_flare_spent'
            local hash=joaat(model);RequestModel(hash);local deadline=now()+4000
            while not HasModelLoaded(hash)and now()<deadline do Wait(25)end
            if not HasModelLoaded(hash)or epoch~=generation then SetModelAsNoLongerNeeded(hash);return end
            while #spent>=((Config.Realism and Config.Realism.MaximumSpentProps)or 12)do DeleteEntity(table.remove(spent,1))end
            local e=CreateObjectNoOffset(hash,p.x,p.y,p.z,false,false,false)
            if not e or e==0 then SetModelAsNoLongerNeeded(hash);return end
            SetEntityRotation(e,rotation.x,rotation.y,rotation.z,0,true);FreezeEntityPosition(e,true);SetEntityCollision(e,false,false);SetModelAsNoLongerNeeded(hash)
            spent[#spent+1]=e
            SetTimeout((Config.Realism and Config.Realism.SpentLifetimeMilliseconds)or 60000,function()
                for i=#spent,1,-1 do if spent[i]==e then table.remove(spent,i);DeleteEntity(e);break end end
            end)
        end)
    end
end
function C.clear()
    generation=generation+1;running=false
    if RoadFlares.Audio and RoadFlares.Audio.shutdown then RoadFlares.Audio.shutdown()end
    for key in pairs(entries)do remove(key)end
    for _,entity in ipairs(spent)do DeleteEntity(entity)end
    spent={};visible={};lingering={};distant={}
end
function C.getDiagnostics()
    local result={records=0,detailed=#visible,distant=#distant,smoke=0,smokePuffs=0,residualPuffs=0,manualProps=0,textureReady=textureReady,textureError=textureError,heldGlow=0,remoteGlow=0,spent=#spent,running=running}
    result.drawTriangles=running and frameTriangles or 0;result.drawSmokeQuads=running and frameSmokeQuads or 0
    for _,r in ipairs(lingering)do result.residualPuffs=result.residualPuffs+#r.smoke.puffs end
    for _,r in pairs(entries)do
        result.records=result.records+1
        if r.sceneEntity then result.manualProps=result.manualProps+1 end
        if r.smoke then result.smoke=result.smoke+1;result.smokePuffs=result.smokePuffs+#r.smoke.puffs end
        if r.glow then local k=r.held and 'heldGlow'or'remoteGlow';result[k]=result[k]+1 end
    end
    return result
end
function V.startHeldFlare(entity,ped,token,validator,deadline)
    remove('held');entries.held={key='held',entity=entity,ped=ped,token=token,validator=validator,deadline=deadline,held=true,stage=0,tip=.220,seed=137}
    start();return true
end
function V.stopHeldFlare(reason,immediate)
    if not entries.held then return true,'already_inactive'end
    if immediate then remove('held')else entries.held.stoppingAt=now()end
    return true,immediate and'inactive'or'stopping'
end
function V.clear()remove('held');return true end
function V.isActive()return entries.held~=nil end
function V.getState()return entries.held and'active'or'inactive'end
function V.getParticleHandle()return entries.held and entries.held.glow end
function V.getSessionToken()return entries.held and entries.held.token end




