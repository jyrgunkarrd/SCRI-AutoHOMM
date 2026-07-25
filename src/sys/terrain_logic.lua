local TerrainById = require("data.terrain.index")
local ImageLoader = require("src.assets.image_loader")
local BattleMap = require("src.sys.battle_map")
local BlockLogic = require("src.sys.block_logic")
local HealthLogic = require("src.sys.health_logic")
local MapData = require("src.sys.map_data")

local TerrainLogic = {}

local IMAGE_DIR = "assets/images/terrain"
local TOOLTIP_WIDTH = 250
local TOOLTIP_HEIGHT = 148
local TOOLTIP_PADDING = 12
local TOOLTIP_GAP = 12
local TOOLTIP_MARGIN = 8
local TOOLTIP_NAME_HEIGHT = 30
local TOOLTIP_IMAGE_SIZE = 86
local PANEL_COLOR = { 0.025, 0.03, 0.04, 0.96 }
local PANEL_BORDER_COLOR = { 1, 1, 1, 0.92 }
local TEXT_COLOR = { 1, 1, 1, 1 }
local DETAIL_COLOR = { 0.72, 0.76, 0.8, 1 }

local terrainByCell = {}
local imageCache = {}

local function normalizeTerrainType(value)
    return type(value) == "string" and value:lower() or ""
end

local function isDeathPitValue(value)
    return type(value) == "string"
        and value:lower():gsub("[%s_%-]+", " ") == "death pit"
end

local function getCellKey(cellOrKey)
    return type(cellOrKey) == "table" and cellOrKey.key or cellOrKey
end

local function getImagePath(id)
    if not id:match("^[%w_%-]+$") then
        return nil, "terrain id contains characters that are unsafe in an image path"
    end

    return ("%s/%s.webp"):format(IMAGE_DIR, id)
end

local function validateDefinition(definition)
    if type(definition.name) ~= "string"
        or not definition.name:match("%S") then
        return nil, "requires a non-empty string name"
    end

    if type(definition.type) ~= "string"
        or not definition.type:match("%S") then
        return nil, "requires a non-empty string type"
    end

    local valueType = type(definition.value)

    if valueType ~= "string" and valueType ~= "number" then
        return nil, "requires a string or number value"
    end

    local terrainType = normalizeTerrainType(definition.type)

    if terrainType == "cover"
        and (
            valueType ~= "number"
            or definition.value < 0
            or definition.value ~= definition.value
            or definition.value == math.huge
        ) then
        return nil, "cover requires a finite non-negative numeric value"
    end

    if terrainType == "hazard"
        and valueType == "string"
        and not isDeathPitValue(definition.value) then
        return nil, "hazard string values must be \"death pit\""
    end

    if terrainType == "hazard"
        and valueType == "number"
        and (
            definition.value < 0
            or definition.value ~= definition.value
            or definition.value == math.huge
        ) then
        return nil, "hazard damage must be a finite non-negative number"
    end

    return true
end

local function loadTerrainImage(definition)
    local cached = imageCache[definition.id]

    if cached then
        return cached
    end

    local path, pathError = getImagePath(definition.id)

    if not path then
        return nil, pathError
    end

    local loaded, image = pcall(ImageLoader.newImage, path)

    if not loaded or not image then
        return nil, (
            "unable to load image for terrain %q from %s: %s"
        ):format(definition.id, path, tostring(image))
    end

    imageCache[definition.id] = image

    return image
end

function TerrainLogic.loadMap(map)
    local valid, validationError = MapData.validate(map)

    if not valid then
        return nil, validationError
    end

    local nextTerrainByCell = {}

    for _, cell in ipairs(BattleMap.getCells()) do
        local terrainId = (map.terrain_features or {})[cell.key]

        if terrainId then
            local definition = TerrainById[terrainId]

            if not definition then
                return nil, (
                    "terrain feature %s targets unknown terrain id %q"
                ):format(cell.key, terrainId)
            end

            local definitionValid, definitionError =
                validateDefinition(definition)

            if not definitionValid then
                return nil, (
                    "terrain feature %s targets invalid terrain %q: %s"
                ):format(cell.key, terrainId, definitionError)
            end

            local image, imageError = loadTerrainImage(definition)

            if not image then
                return nil, (
                    "terrain feature %s cannot use %q: %s"
                ):format(cell.key, terrainId, imageError)
            end

            nextTerrainByCell[cell.key] = {
                id = terrainId,
                definition = definition,
                image = image,
            }
        end
    end

    terrainByCell = nextTerrainByCell

    return terrainByCell
end

function TerrainLogic.get(cellOrKey)
    return terrainByCell[getCellKey(cellOrKey)]
end

function TerrainLogic.getDefinition(cellOrKey)
    local terrain = TerrainLogic.get(cellOrKey)

    return terrain and terrain.definition
end

function TerrainLogic.isTerrainCell(cellOrKey)
    return TerrainLogic.get(cellOrKey) ~= nil
end

function TerrainLogic.isCoverCell(cellOrKey)
    local definition = TerrainLogic.getDefinition(cellOrKey)

    return definition
        and normalizeTerrainType(definition.type) == "cover"
        or false
end

function TerrainLogic.isHazardCell(cellOrKey)
    local definition = TerrainLogic.getDefinition(cellOrKey)

    return definition
        and normalizeTerrainType(definition.type) == "hazard"
        or false
end

function TerrainLogic.footprintHasHazard(footprint)
    for _, cell in ipairs(footprint or {}) do
        if TerrainLogic.isHazardCell(cell) then
            return true
        end
    end

    return false
end

local function applyCover(entity, definition)
    if type(entity.block) ~= "number" then
        return nil, "entity block has not been initialized"
    end

    if entity.block >= definition.value then
        return 0
    end

    local previousBlock = entity.block
    local block, blockError = BlockLogic.setBlock(entity, definition.value)

    if block == nil then
        return nil, blockError
    end

    return block - previousBlock
end

local function applyHazard(entity, definition)
    if isDeathPitValue(definition.value) then
        local hp, deathError = HealthLogic.setHp(entity, 0)

        if hp == nil then
            return nil, deathError
        end

        return {
            damage = 0,
            killed = true,
            deathPit = true,
        }
    end

    local previousHp = entity.hp
    local previousBlock = entity.block
    local hp, damageError = HealthLogic.damage(entity, definition.value)

    if hp == nil then
        return nil, damageError
    end

    return {
        damage = previousHp - hp,
        blockLost = previousBlock - entity.block,
        killed = entity.dead == true,
        deathPit = false,
    }
end

function TerrainLogic.onEntityEntered(entity, cells)
    if type(entity) ~= "table" then
        return nil, "terrain entry requires an entity"
    end

    if type(cells) ~= "table" then
        return nil, "terrain entry requires a cell or cell array"
    end

    if cells.key then
        cells = { cells }
    end

    local result = {
        blockGained = 0,
        damage = 0,
        blockLost = 0,
        killed = entity.dead == true,
        deathPit = false,
        entered = {},
    }

    for _, cell in ipairs(cells) do
        local terrain = TerrainLogic.get(cell)

        if terrain then
            local definition = terrain.definition
            local terrainType = normalizeTerrainType(definition.type)

            result.entered[#result.entered + 1] = terrain

            if terrainType == "cover" and not entity.dead then
                local gained, blockError = applyCover(entity, definition)

                if gained == nil then
                    return nil, (
                        "unable to apply cover %q to %q: %s"
                    ):format(
                        terrain.id,
                        tostring(entity.id),
                        tostring(blockError)
                    )
                end

                result.blockGained = result.blockGained + gained
            elseif terrainType == "hazard" and not entity.dead then
                local hazardResult, hazardError =
                    applyHazard(entity, definition)

                if not hazardResult then
                    return nil, (
                        "unable to apply hazard %q to %q: %s"
                    ):format(
                        terrain.id,
                        tostring(entity.id),
                        tostring(hazardError)
                    )
                end

                result.damage = result.damage + hazardResult.damage
                result.blockLost =
                    result.blockLost + (hazardResult.blockLost or 0)
                result.killed = hazardResult.killed
                result.deathPit =
                    result.deathPit or hazardResult.deathPit
            end
        end

        if entity.dead then
            result.killed = true
            break
        end
    end

    return result
end

local function getTooltipLayout(cell)
    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    local x = cell.x - TOOLTIP_WIDTH / 2
    local aboveY = cell.y
        - BattleMap.HEX_RADIUS
        - TOOLTIP_GAP
        - TOOLTIP_HEIGHT
    local y = aboveY

    if y < TOOLTIP_MARGIN then
        y = cell.y + BattleMap.HEX_RADIUS + TOOLTIP_GAP
    end

    x = math.max(
        TOOLTIP_MARGIN,
        math.min(x, screenWidth - TOOLTIP_WIDTH - TOOLTIP_MARGIN)
    )
    y = math.max(
        TOOLTIP_MARGIN,
        math.min(y, screenHeight - TOOLTIP_HEIGHT - TOOLTIP_MARGIN)
    )

    return {
        x = x,
        y = y,
        width = TOOLTIP_WIDTH,
        height = TOOLTIP_HEIGHT,
    }
end

local function drawTerrainImage(image, x, y)
    local imageWidth, imageHeight = image:getDimensions()
    local scale = math.min(
        TOOLTIP_IMAGE_SIZE / imageWidth,
        TOOLTIP_IMAGE_SIZE / imageHeight
    )
    local drawWidth = imageWidth * scale
    local drawHeight = imageHeight * scale

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
        image,
        x + (TOOLTIP_IMAGE_SIZE - drawWidth) / 2,
        y + (TOOLTIP_IMAGE_SIZE - drawHeight) / 2,
        0,
        scale,
        scale
    )
end

function TerrainLogic.drawTooltip()
    local cell = BattleMap.getHoveredCell()
    local terrain = cell and TerrainLogic.get(cell)

    if not terrain then
        return
    end

    local layout = getTooltipLayout(cell)
    local definition = terrain.definition
    local bodyY = layout.y + TOOLTIP_PADDING + TOOLTIP_NAME_HEIGHT
    local detailX = layout.x
        + TOOLTIP_PADDING
        + TOOLTIP_IMAGE_SIZE
        + TOOLTIP_PADDING
    local detailWidth = layout.x
        + layout.width
        - TOOLTIP_PADDING
        - detailX
    local detailText = ("%s: %s"):format(
        definition.type,
        tostring(definition.value)
    )
    local font = love.graphics.getFont()
    local fontHeight = font:getHeight()

    love.graphics.setColor(PANEL_COLOR)
    love.graphics.rectangle(
        "fill",
        layout.x,
        layout.y,
        layout.width,
        layout.height,
        6,
        6
    )
    love.graphics.setColor(PANEL_BORDER_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle(
        "line",
        layout.x,
        layout.y,
        layout.width,
        layout.height,
        6,
        6
    )
    love.graphics.setColor(TEXT_COLOR)
    love.graphics.printf(
        definition.name,
        layout.x + TOOLTIP_PADDING,
        layout.y + TOOLTIP_PADDING,
        layout.width - TOOLTIP_PADDING * 2,
        "center"
    )

    drawTerrainImage(
        terrain.image,
        layout.x + TOOLTIP_PADDING,
        bodyY
    )

    love.graphics.setColor(DETAIL_COLOR)
    love.graphics.printf(
        detailText,
        detailX,
        bodyY
            + (TOOLTIP_IMAGE_SIZE - fontHeight * 2) / 2,
        detailWidth,
        "center"
    )
    love.graphics.setColor(1, 1, 1, 1)
end

TerrainLogic.draw = TerrainLogic.drawTooltip

return TerrainLogic
