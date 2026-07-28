local BlockLogic = {}

local GAUGE_BACKING_COLOR = { 0, 0, 0, 1 }
local GAUGE_BLOCK_COLOR = { 175 / 255, 179 / 255, 139 / 255, 1 }
local GAUGE_FILL_SCALE = 0.76
local GAUGE_SEGMENTS = 48
local PIE_START_ANGLE = -math.pi / 2

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function BlockLogic.initialize(entity)
    if type(entity) ~= "table" then
        return nil, "block requires an entity"
    end

    entity.block = 0
    entity.blockGaugePeak = 0

    return entity
end

function BlockLogic.getFraction(entity)
    if type(entity) ~= "table"
        or type(entity.block) ~= "number"
        or entity.block <= 0
        or type(entity.blockGaugePeak) ~= "number"
        or entity.blockGaugePeak <= 0 then
        return 0
    end

    return clamp(entity.block / entity.blockGaugePeak, 0, 1)
end

function BlockLogic.getGaugePeak(entity)
    if type(entity) ~= "table"
        or type(entity.blockGaugePeak) ~= "number" then
        return 0
    end

    return math.max(0, entity.blockGaugePeak)
end

function BlockLogic.getGaugeColor()
    return GAUGE_BLOCK_COLOR
end

function BlockLogic.setBlock(entity, block)
    if type(entity) ~= "table"
        or type(entity.block) ~= "number"
        or type(entity.blockGaugePeak) ~= "number" then
        return nil, "entity block has not been initialized"
    end

    if type(block) ~= "number"
        or block ~= block
        or block == math.huge
        or block == -math.huge then
        return nil, "block must be a finite number"
    end

    entity.block = math.max(0, block)

    if entity.block <= 0 then
        entity.block = 0
        entity.blockGaugePeak = 0
    elseif entity.block > entity.blockGaugePeak then
        entity.blockGaugePeak = entity.block
    end

    return entity.block
end

function BlockLogic.add(entity, amount)
    if type(amount) ~= "number"
        or amount < 0
        or amount ~= amount
        or amount == math.huge then
        return nil, "block gain must be a finite non-negative number"
    end

    return BlockLogic.setBlock(
        entity,
        (entity and entity.block or 0) + amount
    )
end

function BlockLogic.absorbDamage(entity, amount)
    if type(amount) ~= "number" or amount < 0 or amount ~= amount then
        return nil, "damage must be a non-negative number"
    end

    if type(entity) ~= "table" or type(entity.block) ~= "number" then
        return nil, "entity block has not been initialized"
    end

    local absorbed = math.min(entity.block, amount)
    local block, blockError = BlockLogic.setBlock(
        entity,
        entity.block - absorbed
    )

    if block == nil then
        return nil, blockError
    end

    return amount - absorbed, absorbed
end

function BlockLogic.grantFromAgencyTile(entity, tile)
    if type(tile) ~= "table" or type(tile.definition) ~= "table" then
        return nil, "a valid Agency tile is required"
    end

    local blockTotal = 0

    for _, actionEntry in ipairs(tile.definition.actions or {}) do
        for actionType, value in pairs(actionEntry) do
            if type(actionType) == "string"
                and actionType:lower() == "block" then
                if type(value) ~= "number"
                    or value ~= value
                    or value < 0 then
                    return nil, (
                        "Agency tile %q has an invalid Block value"
                    ):format(tostring(tile.id))
                end

                blockTotal = blockTotal + value
            end
        end
    end

    if blockTotal > 0 then
        local block, blockError = BlockLogic.add(entity, blockTotal)

        if block == nil then
            return nil, blockError
        end
    end

    return blockTotal
end

function BlockLogic.drawGauge(entity, centerX, centerY, radius)
    local fraction = BlockLogic.getFraction(entity)

    if fraction <= 0 then
        return
    end

    local fillRadius = radius * GAUGE_FILL_SCALE

    love.graphics.setColor(GAUGE_BACKING_COLOR)
    love.graphics.circle(
        "fill",
        centerX,
        centerY,
        radius,
        GAUGE_SEGMENTS
    )
    love.graphics.setColor(GAUGE_BLOCK_COLOR)

    if fraction >= 1 then
        love.graphics.circle(
            "fill",
            centerX,
            centerY,
            fillRadius,
            GAUGE_SEGMENTS
        )
    else
        love.graphics.arc(
            "fill",
            centerX,
            centerY,
            fillRadius,
            PIE_START_ANGLE,
            PIE_START_ANGLE + math.pi * 2 * fraction,
            GAUGE_SEGMENTS
        )
    end
end

return BlockLogic
