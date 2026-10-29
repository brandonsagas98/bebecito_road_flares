-- Passive vehicle ribbon. No ambient driver/vehicle access or recurring worker.
RoadFlares=RoadFlares or {}
local T={};RoadFlares.TrafficLite=T
local W=RoadFlares.WorldFlares
local enabled=not(Config and Config.TrafficLite and Config.TrafficLite.Enabled==false)
local records,pieces,links={},{},{}
local rejected={}
local poses={}
local model=joaat('blista') -- longer empty passive body: fewer entities per connected row
local lo,hi,loading
local batching=false
local revision=0
local MAX_NODES,MAX_PIECES=12,24
local stats={mode='passive-ribbon',worker=false,collision=false,active=0,entities=0,limited=0,created=0,removed=0}
local function erase(key)
 local e=pieces[key];if e then if DoesEntityExist(e)then DeleteEntity(e)end;pieces[key]=nil;poses[key]=nil;stats.removed=stats.removed+1 end
end
local function position(e,p,heading)
 SetEntityHeading(e,heading)
 SetEntityCoordsNoOffset(e,p.x+0.0,p.y+0.0,p.z-lo.z,false,false,false)
 local c=GetOffsetFromEntityInWorldCoords(e,(lo.x+hi.x)*.5,(lo.y+hi.y)*.5,0.0)
 SetEntityCoordsNoOffset(e,2*p.x-c.x,2*p.y-c.y,p.z-lo.z,false,false,false)
end
local function rebuild()
 if not lo then return end
 local nodes={};for id,r in pairs(records)do nodes[#nodes+1]={id=id,p=r.coords}end
 table.sort(nodes,function(a,b)return a.id<b.id end)
 local edges,root,degree={},{},{}
 for i=1,#nodes do root[i]=i;degree[i]=0 end
 local function find(i)while root[i]~=i do i=root[i]end;return i end
 for i=1,#nodes do for j=i+1,#nodes do
  local a,b=nodes[i].p,nodes[j].p;local dx,dy=a.x-b.x,a.y-b.y;local d=math.sqrt(dx*dx+dy*dy)
  if d>.2 and d<=12 and math.abs(a.z-b.z)<1 then edges[#edges+1]={i=i,j=j,d=d}end
 end end
 table.sort(edges,function(a,b)if math.abs(a.d-b.d)<.00001 then return a.i*MAX_NODES+a.j<b.i*MAX_NODES+b.j end;return a.d<b.d end)
 local wanted,used,newLinks={},0,{}
 stats.limited=0
 local length=hi.y-lo.y
 for _,edge in ipairs(edges)do
  local i,j=edge.i,edge.j
  if find(i)~=find(j)and degree[i]<2 and degree[j]<2 then
   local n=math.ceil(edge.d/(length*.9))
   local a,b=nodes[i],nodes[j]
   root[find(j)]=find(i);degree[i]=degree[i]+1;degree[j]=degree[j]+1
   if used+n<=MAX_PIECES then
    local heading=(math.deg(math.atan(-(b.p.x-a.p.x),b.p.y-a.p.y))+360)%360
    local keys={}
    for k=1,n do
     local t=(k-.5)/n
     local key=a.id..':'..b.id..':'..k;keys[#keys+1]=key
     wanted[key]={p={x=a.p.x+(b.p.x-a.p.x)*t,y=a.p.y+(b.p.y-a.p.y)*t,z=a.p.z+(b.p.z-a.p.z)*t},heading=heading}
    end
    used=used+n;newLinks[#newLinks+1]={a=a.p,b=b.p,aId=a.id,bId=b.id,width=hi.x-lo.x,covered=true,budgeted=true,keys=keys}
   else
    stats.limited=stats.limited+1
    newLinks[#newLinks+1]={a=a.p,b=b.p,aId=a.id,bId=b.id,width=hi.x-lo.x,covered=false,budgeted=false,reason='piece_limit',keys={}}
   end
  end
 end
 for i,node in ipairs(nodes)do if degree[i]==0 then
  if used<MAX_PIECES then wanted[node.id]={p=node.p,heading=90.0};used=used+1 else stats.limited=stats.limited+1 end
 end end
 local gone={};for key in pairs(pieces)do if not wanted[key]then gone[#gone+1]=key end end
 for _,key in ipairs(gone)do erase(key)end
 local count=0
 for key,pose in pairs(wanted)do
  local e=pieces[key]
  if e and not DoesEntityExist(e)then pieces[key]=nil;poses[key]=nil;e=nil end
  if not e then
   local p=pose.p;e=CreateVehicle(model,p.x+0.0,p.y+0.0,p.z-lo.z,pose.heading,false,false)
   if e~=0 then
    SetEntityCollision(e,false,false);FreezeEntityPosition(e,true);SetEntityVisible(e,false,false)
    pieces[key]=e;stats.created=stats.created+1
   end
  end
  if e and e~=0 then
   local old=poses[key];local p=pose.p
   if not old or (p.x-old.p.x)^2+(p.y-old.p.y)^2+(p.z-old.p.z)^2>.0009 or math.abs(pose.heading-old.heading)>.25 then
    position(e,p,pose.heading);poses[key]=pose
   end
   count=count+1
  end
 end
 stats.incomplete=0
 for _,link in ipairs(newLinks)do if link.budgeted then for _,key in ipairs(link.keys)do
  if not pieces[key]or not DoesEntityExist(pieces[key])then link.covered=false;stats.incomplete=stats.incomplete+1;break end
 end end end
 local complete=0;for _,link in ipairs(newLinks)do if link.covered then complete=complete+1 end end
 stats.active=#nodes;stats.entities=count;stats.links=complete;stats.plannedLinks=#newLinks;links=newLinks
end
local function ready()
 if batching then return end
 if lo then rebuild();return end
 if loading or not next(records)then return end
 loading=true;RequestModel(model)
 CreateThread(function()
  local deadline=GetGameTimer()+4000
  while not HasModelLoaded(model)and GetGameTimer()<deadline do Wait(25)end
  loading=false;if not HasModelLoaded(model)then return end
  lo,hi=GetModelDimensions(model);rebuild()
 end)
end
local function upsert(r,interest)
 if not enabled or type(r)~='table'or not r.flareId then return end
 local id=tostring(r.flareId);local p=r.coords
 if r.status~='active'then
  if rejected[id]then rejected[id]=nil;stats.unselected=math.max(0,(stats.unselected or 0)-1)end
  if records[id]then records[id]=nil;revision=revision+1;ready()end;return
 end
 if type(p)~='table'then return end
 for _,axis in ipairs({'x','y','z'})do local n=p[axis];if type(n)~='number'or n~=n or math.abs(n)>20000 then return end end
 local me=interest or GetEntityCoords(PlayerPedId())
 if (p.x-me.x)^2+(p.y-me.y)^2>120.0^2 then return end
 local old=records[id]
 if old then
  local q=old.coords;if (p.x-q.x)^2+(p.y-q.y)^2+(p.z-q.z)^2<.0009 then return end
 else local n=0;for _ in pairs(records)do n=n+1 end;if n>=MAX_NODES then
  if not rejected[id]then rejected[id]=true;stats.unselected=(stats.unselected or 0)+1 end;return
 end end
 rejected[id]=nil
 records[id]=r;revision=revision+1;ready()
end
local function snapshot(force)
 local before=revision;local keep={};batching=true;rejected={};stats.unselected=0
 local me=GetEntityCoords(PlayerPedId())
 local all=W.getAll()
 -- Release capacity before admitting additions, regardless of snapshot order.
 for _,r in ipairs(all)do
  local p=r.coords
  if r.status=='active'and type(p)=='table'and type(p.x)=='number'and type(p.y)=='number'
   and (p.x-me.x)^2+(p.y-me.y)^2<=120^2 then keep[tostring(r.flareId)]=true end
 end
 for id in pairs(records)do if not keep[id]then records[id]=nil;revision=revision+1 end end
 for _,r in ipairs(all)do upsert(r,me)end
 batching=false
 if not force then for _,e in pairs(pieces)do if not DoesEntityExist(e)then force=true;break end end end
 if force or before~=revision then ready()end
end
W.subscribe(function(event,payload)
 if payload and payload.fromSnapshot then return end -- reconcile the committed set once
 if event=='clear'then records={};rejected={};stats.unselected=0;ready()
 elseif event=='snapshot'and payload.applied~=false then snapshot()
 elseif event=='remove'then
  if rejected[tostring(payload.flareId)]then rejected[tostring(payload.flareId)]=nil;stats.unselected=math.max(0,(stats.unselected or 0)-1)end
  if records[tostring(payload.flareId)]then records[tostring(payload.flareId)]=nil;revision=revision+1;snapshot(true)end
 elseif event=='upsert'or event=='moved'then
  local r=payload.record
  if r and records[tostring(r.flareId)]and r.status~='active'then
   batching=true;upsert(r);batching=false;snapshot(true)
  else upsert(r)end
 end
end)
-- Reuse the ground reconciler's existing player position and sanitized records.
-- No extra proximity worker or world/vehicle pool scan is introduced.
local lastScope
local lastRepair=-10000
function T.reconcileScope(p,world)
 if not enabled then return end
 if lo and next(pieces)then
  for _,e in pairs(pieces)do if not DoesEntityExist(e)then
   local now=GetGameTimer()
   if now-lastRepair>=5000 then lastRepair=now;rebuild();stats.repairs=(stats.repairs or 0)+1 end
   break
  end end
 end
 if lastScope and (p.x-lastScope.x)^2+(p.y-lastScope.y)^2<1600 then return end
 lastScope={x=p.x,y=p.y};local nearby={}
 for _,r in pairs(world)do if r.status=='active'and r.coords then
  local q=r.coords;local d=(q.x-p.x)^2+(q.y-p.y)^2
  if d<=120^2 then nearby[#nearby+1]={r=r,d=d}end
 end end
 table.sort(nearby,function(a,b)return a.d<b.d end)
 records={};rejected={};batching=true
 for i=1,math.min(MAX_NODES,#nearby)do local r=nearby[i].r;records[tostring(r.flareId)]=r end
 for i=MAX_NODES+1,#nearby do rejected[tostring(nearby[i].r.flareId)]=true end
 batching=false;stats.unselected=math.max(0,#nearby-MAX_NODES);ready()
end
AddEventHandler('onResourceStop',function(r)
 if r~=GetCurrentResourceName()then return end
 local keys={};for key in pairs(pieces)do keys[#keys+1]=key end
 for _,key in ipairs(keys)do erase(key)end
 if lo then SetModelAsNoLongerNeeded(model)end
end)
function T.getDiagnostics()
 local d={};for k,v in pairs(stats)do d[k]=v end
 d.maximumEntities=MAX_PIECES;d.limit=MAX_NODES;d.width=hi and hi.x-lo.x or 1.759;d.passiveModel='blista'
 d.running=loading==true;d.held=0;d.delegated=0;d.poolReads=0;d.decisions=0;d.brakes=0
 return d
end
exports('GetPassiveTrialDiagnostics',T.getDiagnostics)
exports('GetPassiveTrialBounds',function()
 local result={}
 for id in pairs(records)do
  local covered=pieces[id]and DoesEntityExist(pieces[id])or false
  result[id]={ribbon=covered==true,covered=covered==true,width=hi and hi.x-lo.x or 1.759}
 end
 for _,link in ipairs(links)do if link.covered then
  local valid=true;for _,key in ipairs(link.keys)do if not pieces[key]or not DoesEntityExist(pieces[key])then valid=false;break end end
  if valid then for _,id in ipairs({link.aId,link.bId})do if result[id]then result[id].covered=true;result[id].ribbon=true end end end
 end end
 return result
end)
exports('GetPassiveRibbonBounds',function()
 local result={}
 for _,link in ipairs(links)do
  local covered=link.budgeted~=false
  for _,key in ipairs(link.keys)do if not pieces[key]or not DoesEntityExist(pieces[key])then covered=false;break end end
  result[#result+1]={a=link.a,b=link.b,width=link.width,covered=covered,reason=link.reason}
 end
 return result
end)
snapshot()
