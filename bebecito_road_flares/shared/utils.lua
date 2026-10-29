RoadFlares = RoadFlares or {}

RoadFlares.Utils = RoadFlares.Utils or {}

local Utils = RoadFlares.Utils

function Utils.isFiniteNumber(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

function Utils.nowMilliseconds()
    if GetGameTimer then
        return GetGameTimer()
    end
    return os.time() * 1000
end

function Utils.getLocale()
    if Config and Config.Locale then
        return Config.Locale
    end
    return 'en'
end

function Utils.tostringSafe(value)
    if value == nil then
        return ''
    end
    return tostring(value)
end

function Utils.tableCount(values)
    local count = 0
    if type(values) ~= 'table' then
        return 0
    end
    for _ in pairs(values) do
        count = count + 1
    end
    return count
end

function Utils.isVectorLike(value)
    if type(value) ~= 'table' then
        return false
    end
    return Utils.isFiniteNumber(value.x)
        and Utils.isFiniteNumber(value.y)
        and Utils.isFiniteNumber(value.z)
end

function Utils.normalizeVector(value)
    if not value then
        return nil
    end
    if type(value) == 'vector3' then
        return { x = value.x, y = value.y, z = value.z }
    end
    if Utils.isVectorLike(value) then
        return { x = tonumber(value.x) or 0.0, y = tonumber(value.y) or 0.0, z = tonumber(value.z) or 0.0 }
    end
    return nil
end

function Utils.distance2d(a, b)
    if not Utils.isVectorLike(a) or not Utils.isVectorLike(b) then
        return nil
    end
    local dx = (a.x - b.x)
    local dy = (a.y - b.y)
    return math.sqrt((dx * dx) + (dy * dy))
end

function Utils.clampValue(value, minValue, maxValue)
    if type(value) ~= 'number' or value ~= value then
        return minValue
    end
    if minValue and value < minValue then
        return minValue
    end
    if maxValue and value > maxValue then
        return maxValue
    end
    return value
end

function Utils.getLocalesTable()
    if Locales then
        return Locales
    end
    return {}
end

function Utils.localize(key, ...)
    local locales = Utils.getLocalesTable()
    local locale = locales[Utils.getLocale()] or locales.en or {}
    local value = locale[key]
    if type(value) ~= 'string' then
        return key
    end
    if select('#', ...) > 0 then
        return string.format(value, ...)
    end
    return value
end

function Utils.debugPrint(message, resource)
    if Config and Config.Debug then
        local tag = (RoadFlares.Constants and RoadFlares.Constants.DebugTag) or '[BebecitoRoadFlares]'
        local sender = resource or 'road_flares'
        print(('%s [%s] %s'):format(tag, sender, message))
    end
end

function Utils.isString(value, minLength, maxLength)
    if type(value) ~= 'string' then
        return false
    end
    local length = #value
    if minLength and length < minLength then
        return false
    end
    if maxLength and length > maxLength then
        return false
    end
    return true
end

function Utils.trim(value)
    if type(value) ~= 'string' then
        return ''
    end
    local trimmed = value:gsub('^%s+', ''):gsub('%s+$', '')
    return trimmed
end

function Utils.sanitizeMethod(method)
    if type(method) ~= 'string' then
        return nil
    end
    local normalized = Utils.trim(method:lower())
    if not Utils.isString(normalized, 2, 32) then
        return nil
    end
    if not normalized:match('^[a-z_]+$') then
        return nil
    end
    return normalized
end

function Utils.sanitizeRequestId(requestId)
    if type(requestId) == 'number' then
        if requestId <= 0 or requestId ~= requestId or requestId > 9999999999 then
            return nil
        end
        return tostring(math.floor(requestId))
    end
    if type(requestId) == 'string' then
        local normalized = Utils.trim(requestId)
        if not Utils.isString(normalized, 1, 64) then
            return nil
        end
        if not normalized:match('^[%w%-_%.]+$') then
            return nil
        end
        return normalized
    end
    return nil
end

local function activationSectionEnabled(section)
    local sectionConfig = Config and Config.Activation and Config.Activation[section]
    return type(sectionConfig) == 'table' and sectionConfig.Enabled == true
end

function Utils.getActivationMethods()
    return {
        command = activationSectionEnabled('Command'),
        keybind = activationSectionEnabled('Keybind'),
        inventory = activationSectionEnabled('Inventory')
    }
end

function Utils.isActivationMethodEnabled(method)
    local normalizedMethod = Utils.sanitizeMethod(method)
    if not normalizedMethod then
        return false
    end

    local methods = Utils.getActivationMethods()
    return methods[normalizedMethod] == true
end

-- Keep the burning tip clear of the palm as the remaining stick gets shorter.
function Utils.heldOffsetY(base, stage)
    local model=Config.BurnModels and Config.BurnModels[(tonumber(stage)or 0)+1]
    return model and math.max(base,.04-model.length)or base
end
