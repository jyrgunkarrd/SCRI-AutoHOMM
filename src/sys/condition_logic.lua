local BattleMap = require("src.sys.battle_map")
local ConditionDefinitions = require("data.conditions")
local ImageLoader = require("src.assets.image_loader")

local ConditionLogic = {}

local ICON_DIR = "assets/images/icons"
local BADGE_HALF_SIZE = 12
local BADGE_ICON_SIZE = 18
local BADGE_VERTEX_INSET = 10
local CROWN_ICON_SIZE = 30
local CROWN_OUTLINE_WIDTH = 3
local CROWN_ICON_GAP = 7
local CROWN_ROW_GAP = 5
local CROWN_ARC_DEPTH = 5
local CROWN_PORTRAIT_GAP = 10
local CROWN_COLUMNS = 5
local SCREEN_MARGIN = 4
local PORTRAIT_DIAMETER_IN_HEX_RADII = {
    [1] = 2,
    [2] = 5,
}

local definitionsById = {}
local imageCache = {}
local missingImages = {}
local nextInstanceId = 0

local function validateAndIndexDefinitions()
    for index, definition in ipairs(ConditionDefinitions) do
        if type(definition) ~= "table" then
            error(("condition definition %d must be a table"):format(index))
        end

        if type(definition.id) ~= "string"
            or not definition.id:match("^[%w_%-]+$") then
            error(("condition definition %d has an invalid id"):format(index))
        end

        if definitionsById[definition.id] then
            error(("duplicate condition id %q"):format(definition.id))
        end

        if definition.type ~= "neg" and definition.type ~= "pos" then
            error((
                "condition %q type must be \"neg\" or \"pos\""
            ):format(definition.id))
        end

        definitionsById[definition.id] = definition
    end
end

validateAndIndexDefinitions()

local function getEntityCenter(entity)
    return entity.movementVisualX or entity.anchor.x,
        (entity.movementVisualY or entity.anchor.y)
            + (entity.hazardDeathEffectOffsetY or 0)
end

local function getPortraitDiameter(entity)
    local diameterScale = entity
        and entity.definition
        and PORTRAIT_DIAMETER_IN_HEX_RADII[entity.definition.size]

    if not diameterScale then
        return nil
    end

    return BattleMap.HEX_RADIUS
        * diameterScale
        * (entity.initiativeEffectScale or 1)
        * (entity.hazardDeathEffectScale or 1)
end

local function getImagePath(id)
    return ("%s/%s.webp"):format(ICON_DIR, id)
end

local function loadImage(id, fallbackId)
    if imageCache[id] then
        return imageCache[id]
    end

    if missingImages[id] then
        return fallbackId and loadImage(fallbackId) or nil
    end

    local path = getImagePath(id)

    if not love.filesystem.getInfo(path, "file") then
        missingImages[id] = true

        if fallbackId then
            return loadImage(fallbackId)
        end

        return nil
    end

    local loaded, image = pcall(ImageLoader.newImage, path)

    if not loaded or not image then
        missingImages[id] = true

        if fallbackId then
            return loadImage(fallbackId)
        end

        return nil
    end

    imageCache[id] = image
    return image
end

local function drawImageCentered(image, x, y, size)
    if not image then
        return
    end

    local width, height = image:getDimensions()
    local scale = size / math.max(width, height)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
        image,
        x,
        y,
        0,
        scale,
        scale,
        width / 2,
        height / 2
    )
end

local function entityContainsCell(entity, cell)
    for _, footprintCell in ipairs(entity.footprint or {}) do
        if footprintCell == cell or footprintCell.key == cell.key then
            return true
        end
    end

    return false
end

function ConditionLogic.getDefinition(id)
    return definitionsById[id]
end

function ConditionLogic.getInstances(entity)
    if type(entity) ~= "table" or type(entity.conditions) ~= "table" then
        return {}
    end

    return entity.conditions
end

function ConditionLogic.add(entity, id)
    if type(entity) ~= "table" then
        return nil, "condition requires an entity"
    end

    local definition = definitionsById[id]

    if not definition then
        return nil, ("unknown condition %q"):format(tostring(id))
    end

    if type(entity.conditions) ~= "table" then
        entity.conditions = {}
    end

    nextInstanceId = nextInstanceId + 1

    local instance = {
        instanceId = nextInstanceId,
        id = definition.id,
        definition = definition,
    }

    entity.conditions[#entity.conditions + 1] = instance
    return instance
end

function ConditionLogic.addInstances(entity, id, count)
    if type(count) ~= "number"
        or count ~= count
        or count == math.huge
        or count % 1 ~= 0
        or count < 0 then
        return nil, "condition instance count must be a non-negative integer"
    end

    if not definitionsById[id] then
        return nil, ("unknown condition %q"):format(tostring(id))
    end

    local added = {}

    for _ = 1, count do
        local instance, addError = ConditionLogic.add(entity, id)

        if not instance then
            return nil, addError
        end

        added[#added + 1] = instance
    end

    return added
end

function ConditionLogic.getAgencyActionCount(tile, requestedAction)
    if type(tile) ~= "table" or type(tile.definition) ~= "table" then
        return nil, "a valid Agency tile is required"
    end

    if type(requestedAction) ~= "string"
        or not requestedAction:match("%S") then
        return nil, "an Agency action name is required"
    end

    requestedAction = requestedAction:lower()

    local total = 0

    for _, actionEntry in ipairs(tile.definition.actions or {}) do
        for actionType, value in pairs(actionEntry) do
            if type(actionType) == "string"
                and actionType:lower() == requestedAction then
                if type(value) ~= "number"
                    or value ~= value
                    or value == math.huge
                    or value % 1 ~= 0
                    or value < 0 then
                    return nil, (
                        "Agency tile %q has an invalid %s value"
                    ):format(tostring(tile.id), requestedAction)
                end

                total = total + value
            end
        end
    end

    return total
end

-- Conditions are consumed oldest-first so separately added instances retain
-- their own lifetime and ordering.
function ConditionLogic.consume(entity, id)
    if type(entity) ~= "table" or type(entity.conditions) ~= "table" then
        return nil
    end

    for index, instance in ipairs(entity.conditions) do
        if instance.id == id then
            return table.remove(entity.conditions, index)
        end
    end
end

function ConditionLogic.clear(entity)
    if type(entity) ~= "table" then
        return nil, "condition clearing requires an entity"
    end

    local removed = type(entity.conditions) == "table"
        and #entity.conditions
        or 0

    entity.conditions = {}
    return removed
end

function ConditionLogic.getBadgeKind(entity)
    local instances = ConditionLogic.getInstances(entity)

    if #instances == 0 then
        return nil
    end

    local hasNegative = false
    local hasPositive = false

    for _, instance in ipairs(instances) do
        local definition = instance.definition
            or definitionsById[instance.id]

        if definition and definition.type == "neg" then
            hasNegative = true
        elseif definition and definition.type == "pos" then
            hasPositive = true
        end
    end

    if hasNegative and hasPositive then
        return "mix"
    elseif hasPositive then
        return "pos"
    elseif hasNegative then
        return "neg"
    end
end

function ConditionLogic.getBadgeBounds(entity)
    if not ConditionLogic.getBadgeKind(entity) then
        return nil
    end

    local diameter = getPortraitDiameter(entity)

    if not diameter then
        return nil
    end

    local centerX, centerY = getEntityCenter(entity)
    local vertexRadius = diameter / 2 - BADGE_VERTEX_INSET

    return {
        x = centerX + math.sqrt(3) / 2 * vertexRadius,
        y = centerY + vertexRadius / 2,
        halfSize = BADGE_HALF_SIZE,
    }
end

function ConditionLogic.isBadgeHovered(entity, mouseX, mouseY)
    local hoveredCell = BattleMap.getHoveredCell()

    if not hoveredCell or not entityContainsCell(entity, hoveredCell) then
        return false
    end

    local bounds = ConditionLogic.getBadgeBounds(entity)

    if not bounds then
        return false
    end

    if mouseX == nil or mouseY == nil then
        mouseX, mouseY = love.mouse.getPosition()
    end

    local dx = mouseX - bounds.x
    local dy = mouseY - bounds.y

    return math.abs(dx) <= bounds.halfSize
        and math.abs(dy) <= bounds.halfSize
end

function ConditionLogic.getHoveredBadgeEntity(entities, mouseX, mouseY)
    for _, entity in ipairs(entities or {}) do
        if ConditionLogic.isBadgeHovered(entity, mouseX, mouseY) then
            return entity
        end
    end
end

function ConditionLogic.getCrownLayout(entity)
    local instances = ConditionLogic.getInstances(entity)

    if #instances == 0 then
        return {}
    end

    local diameter = getPortraitDiameter(entity)

    if not diameter then
        return {}
    end

    local centerX, centerY = getEntityCenter(entity)
    local rowCount = math.ceil(#instances / CROWN_COLUMNS)
    local nearestRowY = centerY
        - diameter / 2
        - CROWN_PORTRAIT_GAP
        - CROWN_ICON_SIZE / 2
    local topY = nearestRowY
        - (rowCount - 1) * (CROWN_ICON_SIZE + CROWN_ROW_GAP)
        - CROWN_ICON_SIZE / 2
    local verticalShift = math.max(0, SCREEN_MARGIN - topY)
    local layout = {}

    for index, instance in ipairs(instances) do
        local row = math.floor((index - 1) / CROWN_COLUMNS)
        local firstIndex = row * CROWN_COLUMNS + 1
        local count = math.min(
            CROWN_COLUMNS,
            #instances - firstIndex + 1
        )
        local column = index - firstIndex
        local offset = column - (count - 1) / 2
        local halfSpan = math.max(1, (count - 1) / 2)
        local arcAmount = math.abs(offset) / halfSpan

        layout[#layout + 1] = {
            instance = instance,
            x = centerX
                + offset * (CROWN_ICON_SIZE + CROWN_ICON_GAP),
            y = nearestRowY
                - row * (CROWN_ICON_SIZE + CROWN_ROW_GAP)
                + arcAmount * arcAmount * CROWN_ARC_DEPTH
                + verticalShift,
            size = CROWN_ICON_SIZE,
        }
    end

    return layout
end

local function drawBadge(entity)
    local kind = ConditionLogic.getBadgeKind(entity)
    local bounds = kind and ConditionLogic.getBadgeBounds(entity)

    if not bounds then
        return false
    end

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle(
        "fill",
        bounds.x - bounds.halfSize,
        bounds.y - bounds.halfSize,
        bounds.halfSize * 2,
        bounds.halfSize * 2
    )
    drawImageCentered(
        loadImage(kind .. "_cond"),
        bounds.x,
        bounds.y,
        BADGE_ICON_SIZE
    )

    return true
end

local function drawCrown(entity)
    for _, item in ipairs(ConditionLogic.getCrownLayout(entity)) do
        local definition = item.instance.definition
            or definitionsById[item.instance.id]
        local fallbackId = definition
            and definition.type == "pos"
            and "pos_cond"
            or "neg_cond"

        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle(
            "fill",
            item.x - item.size / 2 - CROWN_OUTLINE_WIDTH,
            item.y - item.size / 2 - CROWN_OUTLINE_WIDTH,
            item.size + CROWN_OUTLINE_WIDTH * 2,
            item.size + CROWN_OUTLINE_WIDTH * 2
        )
        drawImageCentered(
            loadImage(item.instance.id, fallbackId),
            item.x,
            item.y,
            item.size
        )
    end
end

function ConditionLogic.draw(entities)
    local drawn = 0

    for _, entity in ipairs(entities or {}) do
        if drawBadge(entity) then
            drawn = drawn + 1
        end
    end

    local hoveredEntity =
        ConditionLogic.getHoveredBadgeEntity(entities)

    if hoveredEntity then
        drawCrown(hoveredEntity)
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)

    return drawn
end

function ConditionLogic.getMissingImages()
    return missingImages
end

return ConditionLogic
