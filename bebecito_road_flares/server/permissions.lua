RoadFlares = RoadFlares or {}
RoadFlares.Server = RoadFlares.Server or {}

local Permissions = {}
RoadFlares.Server.Permissions = Permissions

local Utils = RoadFlares.Utils

function Permissions.canUse(src)
    if not Config or not Config.Permissions or Config.Permissions.Enabled ~= true then
        return true
    end
    if IsPlayerAceAllowed then
        return IsPlayerAceAllowed(src, Config.Permissions.AcePermission or '')
    end
    return false
end

function Permissions.canUseMethod(_src, method)
    return Utils.isActivationMethodEnabled(method)
end

function Permissions.isConsole(src)
    return src == 0
end

function Permissions.allowAdmin(src)
    return Permissions.isConsole(src) or IsPlayerAceAllowed(src, 'command') or IsPlayerAceAllowed(src, 'admin')
end
