local BattleMap = {}

local SQRT_3 = math.sqrt(3)

local MAIN_ROWS = 12
local MAIN_COLUMNS = 20
local MAIN_START_ROW = 4
local MAIN_START_COLUMN = 0
local HEX_RADIUS = 42

local GRID_COLOR = { 0.36, 0.66, 0.78, 1 }

-- Both map sections use this shared lattice origin. Row 3 is deliberately
-- left empty, creating a one-row gap above the primary map.
local GRID_ORIGIN_X = 251
local GRID_ORIGIN_Y = 60

local function getHexCenter(column, row)
    local hexWidth = SQRT_3 * HEX_RADIUS

    return GRID_ORIGIN_X
        + column * hexWidth
        + (row % 2) * hexWidth / 2,
        GRID_ORIGIN_Y + row * HEX_RADIUS * 1.5
end

-- Returns the six vertices of a pointy-topped hexagon.
local function hexVertices(centerX, centerY, radius)
    local vertices = {}

    for corner = 0, 5 do
        local angle = math.rad(60 * corner - 30)
        vertices[#vertices + 1] = centerX + radius * math.cos(angle)
        vertices[#vertices + 1] = centerY + radius * math.sin(angle)
    end

    return vertices
end

local cells = {}

local function addCell(column, row, section)
    local centerX, centerY = getHexCenter(column, row)

    cells[#cells + 1] = {
        key = ("%d:%d"):format(row, column),
        column = column,
        row = row,
        section = section,
        x = centerX,
        y = centerY,
    }
end

local upperClusters = {
    {
        { 1, 0 }, { 2, 0 },
        { 0, 1 }, { 1, 1 }, { 2, 1 },
        { 1, 2 }, { 2, 2 },
    },
    {
        { 18, 0 }, { 19, 0 },
        { 17, 1 }, { 18, 1 }, { 19, 1 },
        { 18, 2 }, { 19, 2 },
    },
}

for _, cluster in ipairs(upperClusters) do
    for _, hex in ipairs(cluster) do
        addCell(hex[1], hex[2], "upper")
    end
end

for row = MAIN_START_ROW, MAIN_START_ROW + MAIN_ROWS - 1 do
    for column = MAIN_START_COLUMN,
        MAIN_START_COLUMN + MAIN_COLUMNS - 1 do
        addCell(column, row, "main")
    end
end

local function drawHex(centerX, centerY, radius, color)
    local vertices = hexVertices(centerX, centerY, radius)

    love.graphics.setColor(color)
    love.graphics.polygon("fill", vertices)
    love.graphics.polygon("line", vertices)
end

function BattleMap.getCells()
    return cells
end

function BattleMap.getDefaultColor()
    return GRID_COLOR
end

function BattleMap.getHexAt(x, y)
    for _, cell in ipairs(cells) do
        local dx = math.abs(x - cell.x)
        local dy = math.abs(y - cell.y)

        if dx <= SQRT_3 * HEX_RADIUS / 2
            and dy <= HEX_RADIUS
            and dx / SQRT_3 + dy <= HEX_RADIUS then
            return cell
        end
    end
end

function BattleMap.drawHexOutline(cell, color, lineWidth)
    love.graphics.setColor(color)
    love.graphics.setLineWidth(lineWidth or 2)
    love.graphics.polygon(
        "line",
        hexVertices(cell.x, cell.y, HEX_RADIUS)
    )
end

function BattleMap.draw(tileColors)
    love.graphics.setLineWidth(1.5)

    for _, cell in ipairs(cells) do
        local color = tileColors and tileColors[cell.key] or GRID_COLOR
        drawHex(cell.x, cell.y, HEX_RADIUS, color)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

BattleMap.HEX_RADIUS = HEX_RADIUS

return BattleMap
