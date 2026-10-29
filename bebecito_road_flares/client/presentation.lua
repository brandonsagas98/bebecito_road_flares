-- Native, non-interactive prompt. No NUI focus, mouse capture or idle thread.
RoadFlares = RoadFlares or {}
local P = {}; RoadFlares.Presentation = P
local cachedMessage, cachedWidth, cachedAspect
local checkAt = 0
function P.prompt(message)
    if IsPauseMenuActive() or IsNuiFocused() then return end
    local t=GetGameTimer()
    if t>=checkAt then
        local aspect=GetAspectRatio(false)
        if aspect~=cachedAspect then cachedMessage=nil;cachedAspect=aspect end
        checkAt=t+1000
    end
    SetTextFont(0); SetTextScale(.0,.30)
    if message~=cachedMessage then
        BeginTextCommandGetWidth('STRING'); AddTextComponentSubstringPlayerName(message)
        cachedWidth=EndTextCommandGetWidth(true)+(.031/cachedAspect)*1.95
        cachedMessage=message
    end
    local left,top,height=.025,.10,.031
    local unit=height/cachedAspect
    DrawRect(left+cachedWidth/2,top+height/2,cachedWidth,height,9,12,17,222)
    DrawRect(left+unit*.06,top+height/2,unit*.12,height,235,56,43,255)
    -- Small upright roadflare mark, drawn without loading a texture or font icon.
    local ix=left+unit*.75
    DrawRect(ix,top+height*.59,unit*.18,height*.43,228,55,43,255)
    DrawRect(ix,top+height*.82,unit*.22,height*.07,89,94,101,255)
    DrawRect(ix,top+height*.32,unit*.25,height*.12,255,135,69,255)
    DrawRect(ix,top+height*.26,unit*.12,height*.14,255,241,202,255)
    SetTextColour(250,250,247,255)
    SetTextCentre(false)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(message)
    EndTextCommandDisplayText(left+unit*1.45,top+.005)

end
function P.notify(message)
    SendNUIMessage({type='bd:notice',message=message})
end
