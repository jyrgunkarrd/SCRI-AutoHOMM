local MapData = require("src.sys.map_data")

local GameMap = {}

local activeMap
local activeColorMap
local activePath

local function trim(value)
    return value:match("^%s*(.-)%s*$")
end

local function resolveMapPath(reference)
    if type(reference) ~= "string" then
        return nil, "map reference must be a string"
    end

    reference = trim(reference):gsub("\\", "/"):gsub("^/+", "")

    if reference == "" then
        return nil, "map reference cannot be empty"
    end

    for segment in reference:gmatch("[^/]+") do
        if segment == ".." then
            return nil, "map reference cannot leave assets/maps"
        end
    end

    local path

    if reference:match("^assets/maps/") then
        path = reference
    else
        path = "assets/maps/" .. reference
    end

    if not path:lower():match("%.lua$") then
        path = path .. ".lua"
    end

    return path
end

function GameMap.loadFromDefinition(definition)
    if type(definition) ~= "table" then
        return nil, "map definition must be a table"
    end

    local path, pathError = resolveMapPath(definition.map)

    if not path then
        return nil, pathError
    end

    local map, loadError = MapData.load(path)

    if not map then
        return nil, ("unable to load %s: %s"):format(path, tostring(loadError))
    end

    local colorMap, colorError = MapData.toColorMap(map)

    if not colorMap then
        return nil, ("unable to prepare %s: %s"):format(path, tostring(colorError))
    end

    activeMap = map
    activeColorMap = colorMap
    activePath = path

    return activeMap
end

function GameMap.loadDevelopmentMap()
    return GameMap.loadFromDefinition(require("data.dev_map"))
end

function GameMap.getData()
    return activeMap
end

function GameMap.getColorMap()
    return activeColorMap
end

function GameMap.getPath()
    return activePath
end

function GameMap.getSpawnerTarget(cellOrKey)
    if not activeMap then
        return nil, "no map is loaded"
    end

    return MapData.getSpawnerTarget(activeMap, cellOrKey)
end

return GameMap
