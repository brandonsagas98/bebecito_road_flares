-- Native road-node leases follow authoritative flare lifecycle; no traffic polling.
RoadFlares=RoadFlares or {}
local T={};RoadFlares.NativeRoutes=T
local W=RoadFlares.WorldFlares
local available=Config and Config.NativeRoadClosure and Config.NativeRoadClosure.Enabled==true
local records,nodes={},{}
local baseline,related={},{}
local preexisting={}
local enabled=available
local version,bucket=0,0
local batching=false
local MAX=24
local changes,queries,rejected=0,0,0
local clearing=false
local function yes(v)return v==true or v==1 end
local function box(p)return {x1=p.x-.15,y1=p.y-.15,z1=p.z-.4,x2=p.x+.15,y2=p.y+.15,z2=p.z+.4}end
local function state(id)queries=queries+1;return yes(GetVehicleNodeIsSwitchedOff(id))end
local original
local function branch(p)
 queries=queries+1
 local ok,_,heading,lanes=GetNthClosestVehicleNodeWithHeading(p.x+0.0,p.y+0.0,p.z+0.0,1,1,3.0,2.5)
 if not yes(ok)then return nil end
 return {heading=heading,lanes=lanes}
end
local function sameExit(a,p)
 local b=branch(p)
 return a and b and a.lanes==1 and b.lanes==1 and math.cos(math.rad(a.heading-b.heading))>.8
end
local function anyOwned()
 for _,n in pairs(nodes)do if n.owned then return true end end;return false
end
local function preserveExisting()
 for id,p in pairs(preexisting)do if not state(id)then
  local b=box(p);SetRoadsInArea(b.x1,b.y1,b.z1,b.x2,b.y2,b.z2,false,false);changes=changes+1
 end end
end
local function reapplyRemaining(alreadyRestored)
 -- Native closures can affect a whole connected road segment. Reconcile overlap
 -- only on a last-reference removal; never in a frame/proximity loop.
 if clearing then return end
 if not alreadyRestored then for _,n in pairs(nodes)do if n.owned then local b=n.box
  SetRoadsBackToOriginal(b.x1,b.y1,b.z1,b.x2,b.y2,b.z2,0);changes=changes+1
 end end end
 for _,n in pairs(nodes)do if n.owned then local b=n.box
  SetRoadsInArea(b.x1,b.y1,b.z1,b.x2,b.y2,b.z2,false,false);changes=changes+1
 end end
 preserveExisting()
end
original=function(id)
 if baseline[id]==nil then
  local current=state(id)
  if current and anyOwned()then
   -- A newly discovered closed node may be a side effect of our own areas.
   -- Read its baseline with our areas temporarily restored, then reapply them
   -- in this same event, without yielding or creating a polling worker.
   for _,n in pairs(nodes)do if n.owned then local b=n.box
    SetRoadsBackToOriginal(b.x1,b.y1,b.z1,b.x2,b.y2,b.z2,0);changes=changes+1
   end end
   preserveExisting();baseline[id]=state(id);reapplyRemaining(true)
  else baseline[id]=current end
 end
 return baseline[id]
end
local function restoreNode(n)
 if not n.owned then return end
 local b=n.box
 local hadExternal=next(preexisting)~=nil
 SetRoadsBackToOriginal(b.x1,b.y1,b.z1,b.x2,b.y2,b.z2,0);changes=changes+1;n.owned=false
 reapplyRemaining()
 SetTimeout(250,function()
  n.restored=state(n.id)==n.before
  for id,entry in pairs(related)do if not state(id)then related[id]=nil end end
  if not n.restored and not n.before and not nodes[n.id]and not anyOwned()and not hadExternal then
   SetRoadsInArea(b.x1,b.y1,b.z1,b.x2,b.y2,b.z2,true,false);changes=changes+1
   n.restoreFallback=true
  end
  
 end)
end
local function release(id)
 local r=records[id];if not r or not r.node then return end
 local n=nodes[r.node];r.node=nil
 if n then n.refs[id]=nil
  if not next(n.refs)and not batching then nodes[n.id]=nil;restoreNode(n);if not next(nodes)then baseline={};related={};preexisting={}end end
 end
end
local function clear()
 clearing=true
 for _,n in pairs(nodes)do restoreNode(n)end
 preserveExisting();nodes={};baseline={};related={};preexisting={};clearing=false;for _,r in pairs(records)do r.node=nil end
end
local function diagnostic()
 local d={mode='nearest-node-per-flare',enabled=enabled,expired=false,worker=false,active=false,
  changes=changes,queries=queries,maximumFlares=MAX,maximumMilliseconds=0,lifetimeBoundToFlares=true,confirmedClosedNodes=0,pendingNodes=0,flareCount=0,rejected=rejected,nodes={},bindings={},relatedNodes={}}
 for _,n in pairs(nodes)do
  local actual=state(n.id)
  local count=0;for _ in pairs(n.refs)do count=count+1 end
  d.nodes[#d.nodes+1]={id=n.id,p=n.p,region=n.box,refs=count,owned=n.owned,closed=actual,before=n.before,status=n.status,collateral=n.collateral,lanes=n.branch and n.branch.lanes,heading=n.branch and n.branch.heading}
  if actual then d.confirmedClosedNodes=d.confirmedClosedNodes+1 end
  if n.status=='pending'then d.pendingNodes=d.pendingNodes+1 end
 end
 for id,n in pairs(related)do if not nodes[id]and state(id)then d.relatedNodes[#d.relatedNodes+1]={id=id,p=n.p}end end
 d.associatedClosedNodes=#d.relatedNodes;d.totalClosedNodes=d.confirmedClosedNodes+d.associatedClosedNodes
 for id,r in pairs(records)do
  d.flareCount=d.flareCount+1
  local n=r.node and nodes[r.node]
  d.bindings[#d.bindings+1]={flareId=id,p=r.p,nodeId=r.node,nodePoint=n and n.p or nil,reason=r.reason}
 end
 d.active=d.confirmedClosedNodes>0 or d.pendingNodes>0
 table.sort(d.nodes,function(a,b)return a.id<b.id end)
 return d
end
local function bind(id,r,knownNode)
 if not enabled then return end
 local p=r.p
 -- Flag1 INCLUDES switched-off nodes: do not skip a node we already closed.
 local nid=knownNode
 if not nid then queries=queries+1;nid=GetNthClosestVehicleNodeId(p.x+0.0,p.y+0.0,p.z+0.0,1,1,3.0,2.5)end
 if not nid or nid==0 then r.reason='no_node';return end
 local n=nodes[nid]
 if n then n.refs[id]=true;r.node=nid;r.reason='shared_node';return end
 -- Only use a freshly returned node ID when requesting its position.
 local q=GetVehicleNodePosition(nid)
 if (q.x-p.x)^2+(q.y-p.y)^2>225 or math.abs(q.z-p.z)>2.5 then r.reason='node_too_far_or_wrong_level';return end
 local b=box(q);local witnesses,seen={},{}
 for nth=2,7 do
  queries=queries+1;local other=GetNthClosestVehicleNodeId(p.x+0.0,p.y+0.0,p.z+0.0,nth,1,3.0,2.5)
  if other and other~=0 and other~=nid and not seen[other]then seen[other]=true;local before=original(other);local wp=GetVehicleNodePosition(other);local point={x=wp.x,y=wp.y,z=wp.z};if before then preexisting[other]=point end;witnesses[#witnesses+1]={id=other,before=before,p=point}end
 end
 n={id=nid,p={x=q.x,y=q.y,z=q.z},box=b,refs={[id]=true},before=original(nid),owned=false,status='preexisting',branch=branch(q)}
 nodes[nid]=n;r.node=nid;r.reason='nearest_node';n.closed=n.before
 if n.before then preexisting[nid]=n.p end
 if n.before then return end
 SetRoadsInArea(b.x1,b.y1,b.z1,b.x2,b.y2,b.z2,false,false)
 n.owned=true;n.status='pending';changes=changes+1
 SetTimeout(250,function()
  if nodes[nid]~=n or not n.owned then return end
  n.closed=state(nid);local collateral=false
  for _,w in ipairs(witnesses)do
   local off=state(w.id)
   -- Other nodes legitimately closed by other flares are allowed.
   local expected=w.before;if nodes[w.id]then expected=nodes[w.id].owned or nodes[w.id].before end
   if off and not expected then
    if math.abs(w.p.z-n.p.z)<1 and sameExit(n.branch,w.p)then
     related[w.id]={p=w.p}
    else collateral=true;n.collateral=n.collateral or{};n.collateral[#n.collateral+1]={id=w.id,expected=expected,actual=off,p=w.p}end
   end
  end
  if not n.closed or collateral then
   n.status=collateral and 'collateral_node_change' or 'closure_not_confirmed'
   restoreNode(n);n.closed=false;r.reason=n.status
  else n.status='closed'end
  
 end)
end
local function valid(r)
 if type(r)~='table'or not r.flareId or r.status~='active'or not r.coords then return false end
 if r.routingBucket~=nil and tonumber(r.routingBucket)~=bucket then return false end
 for _,a in ipairs({'x','y','z'})do local n=r.coords[a];if type(n)~='number'or n~=n or math.abs(n)>20000 then return false end end
 local me=GetEntityCoords(PlayerPedId());return (r.coords.x-me.x)^2+(r.coords.y-me.y)^2<=120^2
end
local function upsert(r)
 if not available or type(r)~='table'or not r.flareId then return end
 local id=tostring(r.flareId);local old=records[id]
 if not valid(r)then release(id);records[id]=nil;return end
 local p=r.coords
 if old then local q=old.p
  if (p.x-q.x)^2+(p.y-q.y)^2+(p.z-q.z)^2<1.0 then return end
  queries=queries+1;local nid=GetNthClosestVehicleNodeId(p.x+0.0,p.y+0.0,p.z+0.0,1,1,3.0,2.5)
  if old.node and old.node==nid then old.p={x=p.x,y=p.y,z=p.z};return end
  local replacement={p={x=p.x,y=p.y,z=p.z}}
  bind(id,replacement,nid);release(id);records[id]=replacement;return
 else
  local count=0;for _ in pairs(records)do count=count+1 end
  if count>=MAX then rejected=rejected+1;return end
 end
 records[id]={p={x=p.x,y=p.y,z=p.z}};bind(id,records[id]);
end
local function applySnapshot(data)
 if not available or type(data)~='table'or type(data.records)~='table'then return end
 local v=tonumber(data.syncVersion)or 0;if v<version then return end;version=v
 local nextBucket=tonumber(data.routingBucket)or bucket
 if nextBucket~=bucket then clear();records={};bucket=nextBucket end
 batching=true
 local keep={};for _,r in ipairs(data.records)do if valid(r)then keep[tostring(r.flareId)]=true end end
 local gone={};for id in pairs(records)do if not keep[id]then gone[#gone+1]=id end end
 for _,id in ipairs(gone)do release(id);records[id]=nil end
 for _,r in ipairs(data.records)do upsert(r)end
 batching=false
 local unused={};for id,n in pairs(nodes)do if not next(n.refs)then unused[#unused+1]=id end end
 clearing=true
 for _,id in ipairs(unused)do local n=nodes[id];nodes[id]=nil;restoreNode(n)end
 clearing=false;if #unused>0 then reapplyRemaining()end
 if not next(nodes)then baseline={};related={};preexisting={}end
 
end
W.subscribe(function(event,payload)
 if not available then return end
 if payload and payload.fromSnapshot then return end -- keep leases until snapshot commit
 if event=='clear'then clear();records={}
 elseif event=='upsert'or event=='moved'then upsert(payload.record)
 elseif event=='remove'then
  local id=tostring(payload.flareId);release(id);records[id]=nil
 elseif event=='snapshot'and payload.applied~=false then
  applySnapshot({records=W.getAll(),routingBucket=W.getRoutingBucket(),syncVersion=W.getLatestSnapshotVersion()})
 end
end)
local lastScope
function T.reconcileScope(p,world)
 if not available then return end
 if lastScope and (p.x-lastScope.x)^2+(p.y-lastScope.y)^2<1600 then return end
 lastScope={x=p.x,y=p.y};local list={};for _,r in pairs(world)do list[#list+1]=r end
 applySnapshot({records=list,routingBucket=W.getRoutingBucket(),syncVersion=W.getLatestSnapshotVersion()})
end
T.getDiagnostics=diagnostic
exports('GetNativeClosureTrialDiagnostics',diagnostic)
AddEventHandler('onResourceStop',function(r)
 if r==GetCurrentResourceName()or r=='bebecito_road_flares'then clear();records={}end
end)
applySnapshot({records=W.getAll(),routingBucket=W.getRoutingBucket(),syncVersion=W.getLatestSnapshotVersion()})
