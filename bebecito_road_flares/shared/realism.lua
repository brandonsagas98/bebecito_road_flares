RoadFlares = RoadFlares or {}
local R = {}
RoadFlares.Realism = R
-- Perceptual spill under sunlight; smooth twilight avoids an hourly switch.
function R.ambientLight(hour,minute)
    local h=((hour or 13)+(minute or 0)/60)%24
    local night=math.max(0,math.min(1,(math.abs(h-12)-5)/2))
    night=night*night*(3-2*night)
    return .30+.70*night
end
function R.lightFlicker(config,t,seed)
    if not config or config.Enabled==false then return 1 end
    local lo,hi=config.MinimumMultiplier or .96,config.MaximumMultiplier or 1.04
    local phase=t*75/math.max(16,config.UpdateMilliseconds or 75)
    local wave=.5+(.035*math.sin(phase*.017+(seed or 0))+.02*math.sin(phase*.031+(seed or 0)*2))/.11
    return lo+(hi-lo)*wave
end
local function unit(v)
    local m=math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z)
    if m<0.00001 then return {x=0,y=1,z=0} end
    return {x=v.x/m,y=v.y/m,z=v.z/m}
end
local function cross(a,b)return{x=a.y*b.z-a.z*b.y,y=a.z*b.x-a.x*b.z,z=a.x*b.y-a.y*b.x}end
function R.stage(ignitedAt,duration,now)
    return math.max(0,math.min(3,math.floor((now-ignitedAt)/duration*4)))
end
function R.groundRotation(normal,heading)
    local n=unit(normal);local angle=math.rad(heading or 0)
    local h={x=-math.sin(angle),y=math.cos(angle),z=0}
    local dot=h.x*n.x+h.y*n.y
    h=unit({x=h.x-dot*n.x,y=h.y-dot*n.y,z=-dot*n.z})
    local pitch=math.rad((Config.Realism and Config.Realism.GroundPitchDegrees) or 80)
    local z={x=h.x*math.sin(pitch)+n.x*math.cos(pitch),y=h.y*math.sin(pitch)+n.y*math.cos(pitch),z=h.z*math.sin(pitch)+n.z*math.cos(pitch)}
    local x=unit(cross(h,n));local y=cross(z,x)
    return {x=math.deg(math.atan(y.z,z.z)),y=math.deg(math.asin(math.max(-1,math.min(1,-x.z)))),z=math.deg(math.atan(x.y,x.x))}
end
