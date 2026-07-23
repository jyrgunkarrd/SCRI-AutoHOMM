local BattleMap = require("src.sys.battle_map")

local MapData = {}

MapData.FORMAT = "scri-autohomm-map"
MapData.VERSION = 1
MapData.PALETTE_SIZE = 10

local validCellKeys = {}

for _, cell in ipairs(BattleMap.getCells()) do
    validCellKeys[cell.key] = true
end

local function isColor(color)
    if type(color) ~= "table" then
        return false
    end

    for channel = 1, 4 do
        local value = color[channel]

        if type(value) ~= "number" or value < 0 or value > 1 then
            return false
        end
    end

    return true
end

function MapData.validate(map)
    if type(map) ~= "table" then
        return nil, "map data must be a table"
    end

    if map.format ~= MapData.FORMAT then
        return nil, "unsupported map format"
    end

    if map.version ~= MapData.VERSION then
        return nil, "unsupported map version"
    end

    if type(map.palette) ~= "table"
        or type(map.palette.name) ~= "string"
        or type(map.palette.colors) ~= "table" then
        return nil, "map palette is missing or invalid"
    end

    if #map.palette.colors ~= MapData.PALETTE_SIZE then
        return nil, "map palette must contain exactly 10 colors"
    end

    for index, color in ipairs(map.palette.colors) do
        if not isColor(color) then
            return nil, ("palette color %d is invalid"):format(index)
        end
    end

    if type(map.tiles) ~= "table" then
        return nil, "map tiles are missing or invalid"
    end

    for key, paletteIndex in pairs(map.tiles) do
        if not validCellKeys[key] then
            return nil, "map contains an unknown hex: " .. tostring(key)
        end

        if type(paletteIndex) ~= "number"
            or paletteIndex % 1 ~= 0
            or paletteIndex < 1
            or paletteIndex > MapData.PALETTE_SIZE then
            return nil, "invalid palette index for hex " .. key
        end
    end

    return true
end

function MapData.load(path)
    local chunk, loadError = love.filesystem.load(path)

    if not chunk then
        return nil, loadError
    end

    local ok, map = pcall(chunk)

    if not ok then
        return nil, map
    end

    local valid, validationError = MapData.validate(map)

    if not valid then
        return nil, validationError
    end

    return map
end

function MapData.toColorMap(map)
    local valid, validationError = MapData.validate(map)

    if not valid then
        return nil, validationError
    end

    local colors = {}

    for _, cell in ipairs(BattleMap.getCells()) do
        local paletteIndex = map.tiles[cell.key] or 1
        colors[cell.key] = map.palette.colors[paletteIndex]
    end

    return colors
end

function MapData.encode(map)
    local valid, validationError = MapData.validate(map)

    if not valid then
        return nil, validationError
    end

    local lines = {
        "return {",
        ("    format = %q,"):format(MapData.FORMAT),
        ("    version = %d,"):format(MapData.VERSION),
        ("    palette = { name = %q, colors = {"):format(map.palette.name),
    }

    for _, color in ipairs(map.palette.colors) do
        lines[#lines + 1] = (
            "        { %.6f, %.6f, %.6f, %.6f },"
        ):format(color[1], color[2], color[3], color[4])
    end

    lines[#lines + 1] = "    } },"
    lines[#lines + 1] = "    tiles = {"

    for _, cell in ipairs(BattleMap.getCells()) do
        lines[#lines + 1] = (
            "        [%q] = %d,"
        ):format(cell.key, map.tiles[cell.key] or 1)
    end

    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "}"

    return table.concat(lines, "\n") .. "\n"
end

return MapData
