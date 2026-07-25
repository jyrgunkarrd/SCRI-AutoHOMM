local BattleMap = require("src.sys.battle_map")

local GlanceTooltips = {}

local FONT_PATH = "assets/fonts/Furore.otf"
local FONT_SIZE = 10
local TILE_PADDING_X = 4
local TILE_PADDING_Y = 2
local TILE_GAP = 2
local TILE_MARGIN = 3
local TILE_MIN_WIDTH = 18
local TILE_BACKGROUND_COLOR = { 0, 0, 0, 0.94 }

local tooltipFont

local function getTooltipFont()
    if not tooltipFont then
        tooltipFont = love.graphics.newFont(FONT_PATH, FONT_SIZE)
    end

    return tooltipFont
end

local function formatValue(value)
    if value % 1 == 0 then
        return tostring(math.floor(value))
    end

    return ("%g"):format(value)
end

local function entityContainsCell(entity, cell)
    for _, footprintCell in ipairs(entity.footprint or {}) do
        if footprintCell == cell or footprintCell.key == cell.key then
            return true
        end
    end

    return false
end

local function getHoveredEntity(entities)
    local hoveredCell = BattleMap.getHoveredCell()

    if not hoveredCell then
        return nil
    end

    for _, entity in ipairs(entities or {}) do
        if entityContainsCell(entity, hoveredCell) then
            return entity
        end
    end
end

local function getGaugeDescriptors(entity)
    local provider = entity
        and entity.logic
        and entity.logic.getGaugeDescriptors

    if type(provider) ~= "function" then
        return {}
    end

    local descriptors = provider(entity)

    return type(descriptors) == "table" and descriptors or {}
end

local function isDrawableGauge(gauge)
    local maximumIsValid = gauge
        and (
            gauge.maximum == nil
            or type(gauge.maximum) == "number"
                and gauge.maximum == gauge.maximum
        )

    return type(gauge) == "table"
        and gauge.visible ~= false
        and type(gauge.x) == "number"
        and type(gauge.y) == "number"
        and type(gauge.radius) == "number"
        and gauge.radius >= 0
        and type(gauge.current) == "number"
        and gauge.current == gauge.current
        and maximumIsValid
        and type(gauge.color) == "table"
end

local function getTileLayout(gauge, font)
    local currentText = formatValue(gauge.current)
    local maximumText = gauge.maximum ~= nil
        and formatValue(gauge.maximum)
        or nil
    local lineHeight = font:getHeight()
    local currentWidth = font:getWidth(currentText)
    local hasMaximum = maximumText ~= nil
    local valueWidth = hasMaximum
        and math.max(currentWidth, font:getWidth(maximumText))
        or currentWidth
    local width = hasMaximum
        and math.max(
            TILE_MIN_WIDTH,
            valueWidth * 2 + TILE_PADDING_X * 4 + 1
        )
        or math.max(
            TILE_MIN_WIDTH,
            valueWidth + TILE_PADDING_X * 2
        )
    local height = lineHeight + TILE_PADDING_Y * 2
    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    local x = gauge.x - width / 2
    local y = gauge.y + gauge.radius + TILE_GAP

    x = math.max(
        TILE_MARGIN,
        math.min(x, screenWidth - width - TILE_MARGIN)
    )

    if y + height > screenHeight - TILE_MARGIN then
        y = gauge.y - gauge.radius - TILE_GAP - height
    end

    return {
        x = x,
        y = math.max(TILE_MARGIN, y),
        width = width,
        height = height,
        currentText = currentText,
        maximumText = maximumText,
        lineHeight = lineHeight,
        hasMaximum = hasMaximum,
        halfWidth = hasMaximum and (width - 1) / 2 or width,
    }
end

local function drawGaugeTile(gauge, font)
    local tile = getTileLayout(gauge, font)
    local color = gauge.color
    local dividerX = tile.x + tile.halfWidth

    love.graphics.setColor(TILE_BACKGROUND_COLOR)
    love.graphics.rectangle(
        "fill",
        tile.x,
        tile.y,
        tile.width,
        tile.height,
        3,
        3
    )
    love.graphics.setColor(
        color[1] or 1,
        color[2] or 1,
        color[3] or 1,
        color[4] or 1
    )
    love.graphics.printf(
        tile.currentText,
        tile.x,
        tile.y + TILE_PADDING_Y,
        tile.halfWidth,
        "center"
    )

    if tile.hasMaximum then
        love.graphics.line(
            dividerX,
            tile.y + TILE_PADDING_Y,
            dividerX,
            tile.y + tile.height - TILE_PADDING_Y
        )
        love.graphics.printf(
            tile.maximumText,
            dividerX + 1,
            tile.y + TILE_PADDING_Y,
            tile.halfWidth,
            "center"
        )
    end
end

-- Gauge providers live on each entity's logic module as
-- getGaugeDescriptors(entity). Adding another descriptor automatically adds
-- another glance tile without changing this renderer.
function GlanceTooltips.draw(entities)
    local entity = getHoveredEntity(entities)

    if not entity then
        return 0
    end

    local gauges = getGaugeDescriptors(entity)
    local font = getTooltipFont()
    local previousFont = love.graphics.getFont()
    local previousLineWidth = love.graphics.getLineWidth()
    local drawn = 0

    love.graphics.setFont(font)
    love.graphics.setLineWidth(1)

    for _, gauge in ipairs(gauges) do
        if isDrawableGauge(gauge) then
            drawGaugeTile(gauge, font)
            drawn = drawn + 1
        end
    end

    love.graphics.setFont(previousFont)
    love.graphics.setLineWidth(previousLineWidth)
    love.graphics.setColor(1, 1, 1, 1)

    return drawn
end

return GlanceTooltips
