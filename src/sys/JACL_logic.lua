local ImageLoader = require("src.assets.image_loader")
local BattleMap = require("src.sys.battle_map")

local JACLLogic = {}

local PORTRAIT_DIR = "assets/images/jacl"
local PORTRAIT_DIAMETER_IN_HEX_RADII = {
    [1] = 2,
    [2] = 5,
}
local PORTRAIT_OUTLINE_COLOR = { 0, 0, 0, 1 }
local PORTRAIT_OUTLINE_WIDTH = 4

local function buildHexPoints(centerX, centerY, radius)
    local points = {}

    for corner = 0, 5 do
        local angle = math.rad(60 * corner - 30)
        points[#points + 1] = centerX + radius * math.cos(angle)
        points[#points + 1] = centerY + radius * math.sin(angle)
    end

    return points
end

local function getPortraitPath(definition)
    if not definition.id:match("^[%w_%-]+$") then
        return nil, "JACL id contains characters that are unsafe in an image path"
    end

    return ("%s/%s_hex.webp"):format(PORTRAIT_DIR, definition.id)
end

function JACLLogic.getFootprint(definition, anchorCell)
    if type(definition) ~= "table" then
        return nil, "JACL definition must be a table"
    end

    if not anchorCell then
        return nil, "JACL requires a valid anchor hex"
    end

    if definition.size == 1 then
        return { anchorCell }
    end

    if definition.size == 2 then
        local neighbors = BattleMap.getNeighbors(anchorCell)

        if #neighbors ~= 6 then
            return nil, (
                "size-2 JACL %q requires six hexes surrounding spawner %s"
            ):format(definition.id, anchorCell.key)
        end

        local footprint = { anchorCell }

        for _, neighbor in ipairs(neighbors) do
            footprint[#footprint + 1] = neighbor
        end

        return footprint
    end

    return nil, (
        "JACL %q has unsupported size %s; expected 1 or 2"
    ):format(tostring(definition.id), tostring(definition.size))
end

function JACLLogic.spawn(definition, anchorCell)
    local footprint, footprintError = JACLLogic.getFootprint(
        definition,
        anchorCell
    )

    if not footprint then
        return nil, footprintError
    end

    local portraitPath, pathError = getPortraitPath(definition)

    if not portraitPath then
        return nil, pathError
    end

    local loaded, portrait = pcall(ImageLoader.newImage, portraitPath)

    if not loaded then
        return nil, (
            "unable to load portrait for JACL %q from %s: %s"
        ):format(definition.id, portraitPath, tostring(portrait))
    end

    return {
        id = definition.id,
        entityType = "JACL",
        definition = definition,
        anchor = anchorCell,
        footprint = footprint,
        portrait = portrait,
        portraitPath = portraitPath,
    }
end

function JACLLogic.draw(entity)
    local size = entity.definition.size
    local diameter = BattleMap.HEX_RADIUS
        * PORTRAIT_DIAMETER_IN_HEX_RADII[size]
    local imageWidth, imageHeight = entity.portrait:getDimensions()
    local scale = diameter / math.max(imageWidth, imageHeight)

    -- The footprint stencil guarantees that portrait pixels can never spill
    -- onto a hex that the entity does not occupy.
    love.graphics.stencil(function()
        for _, cell in ipairs(entity.footprint) do
            love.graphics.polygon(
                "fill",
                BattleMap.getHexVertices(cell)
            )
        end
    end, "replace", 1)

    love.graphics.setStencilTest("equal", 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
        entity.portrait,
        entity.anchor.x,
        entity.anchor.y,
        0,
        scale,
        scale,
        imageWidth / 2,
        imageHeight / 2
    )
    love.graphics.setStencilTest()

    local outlineRadius = diameter / 2 - PORTRAIT_OUTLINE_WIDTH / 2

    love.graphics.setColor(PORTRAIT_OUTLINE_COLOR)
    love.graphics.setLineWidth(PORTRAIT_OUTLINE_WIDTH)
    love.graphics.polygon(
        "line",
        buildHexPoints(entity.anchor.x, entity.anchor.y, outlineRadius)
    )
end

return JACLLogic
