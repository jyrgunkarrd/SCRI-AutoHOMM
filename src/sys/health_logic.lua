local BlockLogic = require("src.sys.block_logic")

local HealthLogic = {}

local GAUGE_BACKING_COLOR = { 0, 0, 0, 1 }
local GAUGE_FULL_COLOR = { 175 / 255, 230 / 255, 0, 1 }
local GAUGE_HALF_COLOR = { 1, 230 / 255, 0, 1 }
local GAUGE_EMPTY_COLOR = { 1, 0, 0, 1 }
local GAUGE_DEAD_COLOR = { 1, 0, 0, 1 }
local GAUGE_FILL_SCALE = 0.76
local GAUGE_DEAD_X_SCALE = 0.52
local GAUGE_DEAD_X_WIDTH = 2.5
local GAUGE_SEGMENTS = 48
local PIE_START_ANGLE = -math.pi / 2
local deathHandler

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function lerpColor(from, to, amount)
    return {
        from[1] + (to[1] - from[1]) * amount,
        from[2] + (to[2] - from[2]) * amount,
        from[3] + (to[3] - from[3]) * amount,
        from[4] + (to[4] - from[4]) * amount,
    }
end

local function getGaugeColor(fraction)
    if fraction >= 0.5 then
        return lerpColor(
            GAUGE_HALF_COLOR,
            GAUGE_FULL_COLOR,
            (fraction - 0.5) * 2
        )
    end

    return lerpColor(GAUGE_EMPTY_COLOR, GAUGE_HALF_COLOR, fraction * 2)
end

local function getBaseMaxHp(definition)
    for _, stat in ipairs(definition.stats or {}) do
        if type(stat) == "table" and stat.hp ~= nil then
            return stat.hp
        end
    end

    return nil
end

function HealthLogic.initialize(entity)
    if type(entity) ~= "table" or type(entity.definition) ~= "table" then
        return nil, "health requires an entity with a definition"
    end

    local maxHp = getBaseMaxHp(entity.definition)

    if type(maxHp) ~= "number"
        or maxHp ~= maxHp
        or maxHp == math.huge
        or maxHp == -math.huge
        or maxHp <= 0 then
        return nil, (
            "entity %q requires a positive numeric hp stat"
        ):format(tostring(entity.id))
    end

    entity.maxHp = maxHp
    entity.hp = maxHp
    entity.dead = false

    local blocked, blockError = BlockLogic.initialize(entity)

    if not blocked then
        return nil, blockError
    end

    return entity
end

function HealthLogic.getFraction(entity)
    if type(entity) ~= "table"
        or type(entity.hp) ~= "number"
        or type(entity.maxHp) ~= "number"
        or entity.maxHp <= 0 then
        return 0
    end

    return clamp(entity.hp / entity.maxHp, 0, 1)
end

function HealthLogic.getGaugeColor(entity)
    if entity and entity.dead then
        return GAUGE_DEAD_COLOR
    end

    return getGaugeColor(HealthLogic.getFraction(entity))
end

function HealthLogic.setDeathHandler(handler)
    if handler ~= nil and type(handler) ~= "function" then
        return nil, "death handler must be a function or nil"
    end

    deathHandler = handler

    return true
end

function HealthLogic.setHp(entity, hp)
    if type(entity) ~= "table"
        or type(entity.maxHp) ~= "number"
        or entity.maxHp <= 0 then
        return nil, "entity health has not been initialized"
    end

    if type(hp) ~= "number" or hp ~= hp then
        return nil, "hp must be a number"
    end

    local wasDead = entity.dead == true

    entity.hp = clamp(hp, 0, entity.maxHp)
    entity.dead = entity.hp <= 0

    if entity.dead then
        entity.exhausted = false
        entity.initiativeExhaustionPending = nil
    end

    if entity.dead and not wasDead and deathHandler then
        deathHandler(entity)
    end

    return entity.hp
end

function HealthLogic.damage(entity, amount)
    if type(amount) ~= "number" or amount < 0 or amount ~= amount then
        return nil, "damage must be a non-negative number"
    end

    local remainingDamage, blockError = BlockLogic.absorbDamage(
        entity,
        amount
    )

    if remainingDamage == nil then
        return nil, blockError
    end

    return HealthLogic.setHp(
        entity,
        (entity and entity.hp or 0) - remainingDamage
    )
end

function HealthLogic.heal(entity, amount)
    if type(amount) ~= "number" or amount < 0 or amount ~= amount then
        return nil, "healing must be a non-negative number"
    end

    return HealthLogic.setHp(entity, (entity and entity.hp or 0) + amount)
end

function HealthLogic.drawGauge(entity, centerX, centerY, radius)
    local fraction = HealthLogic.getFraction(entity)
    local fillRadius = radius * GAUGE_FILL_SCALE

    love.graphics.setColor(GAUGE_BACKING_COLOR)
    love.graphics.circle(
        "fill",
        centerX,
        centerY,
        radius,
        GAUGE_SEGMENTS
    )

    if fraction > 0 then
        love.graphics.setColor(HealthLogic.getGaugeColor(entity))

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

    if entity.dead then
        local xRadius = radius * GAUGE_DEAD_X_SCALE
        local previousLineWidth = love.graphics.getLineWidth()

        love.graphics.setColor(GAUGE_DEAD_COLOR)
        love.graphics.setLineWidth(GAUGE_DEAD_X_WIDTH)
        love.graphics.line(
            centerX - xRadius,
            centerY - xRadius,
            centerX + xRadius,
            centerY + xRadius
        )
        love.graphics.line(
            centerX + xRadius,
            centerY - xRadius,
            centerX - xRadius,
            centerY + xRadius
        )
        love.graphics.setLineWidth(previousLineWidth)
    end
end

return HealthLogic
