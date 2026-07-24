local AgencyLogic = require("src.sys.agency_logic")
local BattleMap = require("src.sys.battle_map")
local FateLogic = require("src.sys.fate_logic")
local Sfx = require("src.sys.sfx")

local ReflexLogic = {}

local MAX_CRITICAL_DRAWS = 1000
local VISIBLE_ENTRIES_PER_SIDE = 5
local TOKEN_SIZE = 56
local TOKEN_GAP = 7
local BUTTON_QUEUE_GAP = 12
local TOKEN_OUTLINE_WIDTH = 3
local INACTIVE_TOKEN_SCALE = 0.86
local INACTIVE_TOKEN_OPACITY = 0.45
local BADGE_WIDTH = 32
local BADGE_HEIGHT = 21
local RESULT_DURATION = 0.6
local RESULT_FLASH_DURATION = 0.15
local RESULT_SETTLE_DURATION = 0.25
local ICON_FONT_PATH = "assets/fonts/icons.otf"
local ICON_FONT_SIZE = 38
local FAIL_GLYPH = "\239\129\158" -- U+F05E

local COLORS = {
    tokenOutline = { 0, 0, 0, 1 },
    badgeFill = { 0, 0, 0, 0.96 },
    badgeBorder = { 1, 1, 1, 1 },
    badgeText = { 1, 1, 1, 1 },
    critical = { 1, 165 / 255, 0, 1 },
    failGlyph = { 1, 1, 1, 1 },
}

local initiativeSequence = {}
local agentQueue = {}
local hostileQueue = {}
local resolvedRound
local animationQueue = {}
local activeAnimation
local animatedEntities = {}
local iconFont

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function clearEntityEffect(entity)
    entity.initiativeEffectScale = nil
    entity.initiativeEffectOpacity = nil
    entity.initiativeEffectRed = nil
    entity.initiativeEffectGreen = nil
    entity.initiativeEffectBlue = nil
end

local function clearAnimationState()
    for _, entity in ipairs(animatedEntities) do
        clearEntityEffect(entity)
        entity.initiativeExhaustionPending = nil
    end

    animationQueue = {}
    activeAnimation = nil
    animatedEntities = {}
end

local function applyAnimationState(animation)
    local entity = animation.entity
    local elapsed = animation.elapsed

    if animation.kind == "crit" then
        local scaleAmount

        if elapsed <= RESULT_FLASH_DURATION then
            scaleAmount = elapsed / RESULT_FLASH_DURATION
        else
            scaleAmount = 1 - clamp(
                (elapsed - RESULT_FLASH_DURATION)
                    / RESULT_SETTLE_DURATION,
                0,
                1
            )
        end

        local colorAmount = 1 - clamp(
            (elapsed - RESULT_FLASH_DURATION)
                / RESULT_SETTLE_DURATION,
            0,
            1
        )

        entity.initiativeEffectScale = 1 + 0.14 * scaleAmount
        entity.initiativeEffectOpacity = 1
        entity.initiativeEffectRed = 1
        entity.initiativeEffectGreen = 1
            - (1 - 165 / 255) * colorAmount
        entity.initiativeEffectBlue = 1 - colorAmount
    else
        if elapsed <= RESULT_FLASH_DURATION then
            local pulse = math.sin(
                math.pi * elapsed / RESULT_FLASH_DURATION
            )

            entity.initiativeEffectScale = 1 + 0.04 * pulse
            entity.initiativeEffectOpacity = 1
        elseif elapsed
            <= RESULT_FLASH_DURATION + RESULT_SETTLE_DURATION then
            local progress = (
                elapsed - RESULT_FLASH_DURATION
            ) / RESULT_SETTLE_DURATION

            entity.initiativeEffectScale = 1 - 0.12 * progress
            entity.initiativeEffectOpacity = 1 - 0.6 * progress
        else
            local progress = clamp(
                (
                    elapsed
                        - RESULT_FLASH_DURATION
                        - RESULT_SETTLE_DURATION
                ) / (
                    RESULT_DURATION
                        - RESULT_FLASH_DURATION
                        - RESULT_SETTLE_DURATION
                ),
                0,
                1
            )

            entity.initiativeEffectScale = 0.88 + 0.12 * progress
            entity.initiativeEffectOpacity = 0.4
        end

        entity.initiativeEffectRed = 1
        entity.initiativeEffectGreen = 1
        entity.initiativeEffectBlue = 1
    end
end

local function beginNextAnimation()
    if activeAnimation or #animationQueue == 0 then
        return false
    end

    activeAnimation = table.remove(animationQueue, 1)
    activeAnimation.elapsed = 0
    applyAnimationState(activeAnimation)

    if activeAnimation.kind == "crit" then
        Sfx.play("bonus_action")
    else
        Sfx.play("skip_turn")
    end

    return true
end

local function getIconFont()
    if iconFont then
        return iconFont
    end

    local loaded, font = pcall(
        love.graphics.newFont,
        ICON_FONT_PATH,
        ICON_FONT_SIZE
    )

    if loaded then
        iconFont = font
    end

    return iconFont
end

local function getAgility(entity)
    for _, statEntry in ipairs(entity.definition.stats or {}) do
        for name, value in pairs(statEntry) do
            if type(name) == "string"
                and name:lower() == "agi"
                and type(value) == "number" then
                return value
            end
        end
    end

    return 0
end

local function getRandomUnit(random)
    local value

    if random then
        value = random()
    elseif love and love.math and love.math.random then
        value = love.math.random()
    else
        value = math.random()
    end

    return tonumber(value) or 0
end

local function getFateStack(entity)
    if entity.entityType == "HOSTILE" then
        return FateLogic.getHostileStack()
    end

    return FateLogic.getActiveStack()
end

local function getFateModifier(tile)
    local definition = tile.definition
    local value = tonumber(definition.value) or 0

    if definition.neg then
        return -value
    end

    return value
end

local function resolveEntity(entity, random, exceptionalEvents)
    local fateStack = getFateStack(entity)

    if not fateStack then
        return nil, (
            "%s %q has no available Fate stack"
        ):format(entity.entityType, entity.id)
    end

    if not entity.agencyStack then
        return nil, (
            "%s %q has no Agency stack"
        ):format(entity.entityType, entity.id)
    end

    local agencyTile, agencyError = AgencyLogic.drawTile(
        entity.agencyStack,
        random
    )

    if not agencyTile then
        return nil, (
            "unable to draw Agency tile for %q: %s"
        ):format(entity.id, tostring(agencyError))
    end

    local agencyDiscarded, agencyDiscardError = AgencyLogic.discardTile(
        entity.agencyStack,
        agencyTile
    )

    if not agencyDiscarded then
        return nil, agencyDiscardError
    end

    local agility = getAgility(entity)
    local entries = {}
    local fateTiles = {}
    local exhausted = false
    local draws = 0
    local continueDrawing = true

    while continueDrawing do
        draws = draws + 1

        if draws > MAX_CRITICAL_DRAWS then
            return nil, (
                "initiative for %q exceeded %d consecutive Crit draws"
            ):format(entity.id, MAX_CRITICAL_DRAWS)
        end

        local tile, drawError = FateLogic.drawModifier(
            fateStack,
            random
        )

        if not tile then
            return nil, (
                "unable to draw Fate tile for %q: %s"
            ):format(entity.id, tostring(drawError))
        end

        fateTiles[#fateTiles + 1] = tile

        local definition = tile.definition

        if definition.fail then
            exhausted = true
            entries = {}
            entity.initiativeExhaustionPending = true
            exceptionalEvents[#exceptionalEvents + 1] = {
                kind = "fail",
                entity = entity,
                tile = tile,
            }
        else
            local initiative

            if definition.crit then
                initiative = (
                    agility + getFateModifier(tile)
                ) * 2
            else
                initiative = agility + getFateModifier(tile)
            end

            local entry = {
                entity = entity,
                entityType = entity.entityType,
                initiative = initiative,
                fateTile = tile,
                agencyTile = agencyTile,
                tieBreaker = getRandomUnit(random),
                critical = definition.crit == true,
            }
            entries[#entries + 1] = entry

            if definition.crit then
                exceptionalEvents[#exceptionalEvents + 1] = {
                    kind = "crit",
                    entity = entity,
                    tile = tile,
                    entry = entry,
                }
            end
        end

        local discarded, discardError = FateLogic.discardModifier(
            fateStack,
            tile,
            random
        )

        if not discarded then
            return nil, discardError
        end

        continueDrawing = definition.crit == true and not exhausted
    end

    entity.exhausted = exhausted
    entity.initiativeFateTiles = fateTiles
    entity.initiativeAgencyTile = agencyTile

    return entries
end

local function compareEntries(left, right)
    if left.initiative ~= right.initiative then
        return left.initiative > right.initiative
    end

    if left.tieBreaker ~= right.tieBreaker then
        return left.tieBreaker > right.tieBreaker
    end

    if left.entity.id ~= right.entity.id then
        return left.entity.id < right.entity.id
    end

    return left.drawIndex < right.drawIndex
end

local function refreshSideQueues()
    agentQueue = {}
    hostileQueue = {}

    for _, entry in ipairs(initiativeSequence) do
        local target = entry.entityType == "HOSTILE"
            and hostileQueue
            or agentQueue

        if #target < VISIBLE_ENTRIES_PER_SIDE then
            target[#target + 1] = entry
        end
    end
end

local function buildHexPoints(centerX, centerY, radius)
    local points = {}

    for corner = 0, 5 do
        local angle = math.rad(60 * corner - 30)
        points[#points + 1] = centerX + radius * math.cos(angle)
        points[#points + 1] = centerY + radius * math.sin(angle)
    end

    return points
end

local function drawEntry(entry, centerX, centerY, isHighest)
    local tokenScale = isHighest and 1 or INACTIVE_TOKEN_SCALE
    local tokenOpacity = isHighest and 1 or INACTIVE_TOKEN_OPACITY
    local tokenSize = TOKEN_SIZE * tokenScale
    local portrait = entry.entity.portrait

    if portrait then
        local width, height = portrait:getDimensions()
        local scale = tokenSize / math.max(width, height)

        love.graphics.setColor(1, 1, 1, tokenOpacity)
        love.graphics.draw(
            portrait,
            centerX,
            centerY,
            0,
            scale,
            scale,
            width / 2,
            height / 2
        )
    end

    love.graphics.setColor(
        COLORS.tokenOutline[1],
        COLORS.tokenOutline[2],
        COLORS.tokenOutline[3],
        tokenOpacity
    )
    love.graphics.setLineWidth(TOKEN_OUTLINE_WIDTH)
    love.graphics.polygon(
        "line",
        buildHexPoints(centerX, centerY, tokenSize / 2)
    )

    local criticalBadgeActive = activeAnimation
        and activeAnimation.kind == "crit"
        and activeAnimation.entry == entry
    local badgeScale = 1

    if criticalBadgeActive then
        badgeScale = 1 + 0.18 * math.sin(
            math.pi * clamp(
                activeAnimation.elapsed / RESULT_DURATION,
                0,
                1
            )
        )
    end

    local badgeWidth = BADGE_WIDTH * badgeScale
    local badgeHeight = BADGE_HEIGHT * badgeScale
    local badgeX = centerX - badgeWidth / 2
    local badgeY = centerY + tokenSize / 2 - badgeHeight

    love.graphics.setColor(
        criticalBadgeActive and COLORS.critical or COLORS.badgeFill
    )
    love.graphics.rectangle(
        "fill",
        badgeX,
        badgeY,
        badgeWidth,
        badgeHeight,
        3,
        3
    )
    love.graphics.setColor(COLORS.badgeBorder)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle(
        "line",
        badgeX,
        badgeY,
        badgeWidth,
        badgeHeight,
        3,
        3
    )
    love.graphics.setColor(COLORS.badgeText)
    local font = love.graphics.getFont and love.graphics.getFont()
    local fontHeight = font and font:getHeight() or 18
    local labelY = math.floor(
        badgeY + (badgeHeight - fontHeight) / 2 + 0.5
    )

    love.graphics.printf(
        tostring(entry.initiative),
        badgeX,
        labelY,
        badgeWidth,
        "center"
    )
end

function ReflexLogic.reset()
    clearAnimationState()
    initiativeSequence = {}
    agentQueue = {}
    hostileQueue = {}
    resolvedRound = nil
end

function ReflexLogic.resolveRound(entities, round, random)
    clearAnimationState()

    local nextSequence = {}
    local exceptionalEvents = {}

    for _, entity in ipairs(entities or {}) do
        if entity.entityType == "AGENT"
            or entity.entityType == "HOSTILE" then
            animatedEntities[#animatedEntities + 1] = entity
            entity.exhausted = false
            entity.initiativeFateTiles = nil
            entity.initiativeAgencyTile = nil
            entity.initiativeExhaustionPending = nil
            clearEntityEffect(entity)

            local entries, resolveError = resolveEntity(
                entity,
                random,
                exceptionalEvents
            )

            if not entries then
                return nil, resolveError
            end

            for _, entry in ipairs(entries) do
                entry.drawIndex = #nextSequence + 1
                nextSequence[#nextSequence + 1] = entry
            end
        end
    end

    table.sort(nextSequence, compareEntries)

    for position, entry in ipairs(nextSequence) do
        entry.position = position
    end

    initiativeSequence = nextSequence
    resolvedRound = round
    animationQueue = exceptionalEvents
    refreshSideQueues()

    return initiativeSequence
end

function ReflexLogic.getInitiativeSequence()
    return initiativeSequence
end

function ReflexLogic.getAgentQueue()
    return agentQueue
end

function ReflexLogic.getHostileQueue()
    return hostileQueue
end

function ReflexLogic.getResolvedRound()
    return resolvedRound
end

function ReflexLogic.isAnimating()
    return activeAnimation ~= nil or #animationQueue > 0
end

function ReflexLogic.getActiveAnimation()
    return activeAnimation
end

function ReflexLogic.update(dt)
    dt = math.max(0, tonumber(dt) or 0)
    beginNextAnimation()

    while activeAnimation do
        local remaining = RESULT_DURATION - activeAnimation.elapsed
        local step = math.min(dt, remaining)

        activeAnimation.elapsed = activeAnimation.elapsed + step
        applyAnimationState(activeAnimation)
        dt = dt - step

        if activeAnimation.elapsed >= RESULT_DURATION then
            local completed = activeAnimation

            clearEntityEffect(completed.entity)

            if completed.kind == "fail" then
                completed.entity.initiativeExhaustionPending = nil
            end

            activeAnimation = nil

            if not beginNextAnimation() then
                break
            end
        elseif step == 0 then
            break
        else
            break
        end
    end
end

function ReflexLogic.drawMapEffects()
    local animation = activeAnimation

    if not animation then
        return
    end

    local entity = animation.entity
    local progress = clamp(
        animation.elapsed / RESULT_DURATION,
        0,
        1
    )

    if animation.kind == "crit" then
        local size = entity.definition.size or 1
        local baseRadius = BattleMap.HEX_RADIUS
            * (size == 2 and 2.5 or 1)
        local radius = baseRadius * (1 + 0.48 * progress)

        love.graphics.setColor(
            COLORS.critical[1],
            COLORS.critical[2],
            COLORS.critical[3],
            1 - progress
        )
        love.graphics.setLineWidth(5 - 2 * progress)
        love.graphics.polygon(
            "line",
            buildHexPoints(entity.anchor.x, entity.anchor.y, radius)
        )
    else
        if animation.elapsed <= RESULT_FLASH_DURATION then
            local flashAlpha = 0.55 * (
                1 - animation.elapsed / RESULT_FLASH_DURATION
            )
            local size = entity.definition.size or 1
            local radius = BattleMap.HEX_RADIUS
                * (size == 2 and 2.5 or 1)

            love.graphics.setColor(1, 1, 1, flashAlpha)
            love.graphics.polygon(
                "fill",
                buildHexPoints(
                    entity.anchor.x,
                    entity.anchor.y,
                    radius
                )
            )
        end

        local font = getIconFont()

        if font then
            local previousFont = love.graphics.getFont()
            local alpha = animation.elapsed
                <= RESULT_FLASH_DURATION + RESULT_SETTLE_DURATION
                and 1
                or 1 - clamp(
                    (
                        animation.elapsed
                            - RESULT_FLASH_DURATION
                            - RESULT_SETTLE_DURATION
                    ) / (
                        RESULT_DURATION
                            - RESULT_FLASH_DURATION
                            - RESULT_SETTLE_DURATION
                    ),
                    0,
                    1
                )

            love.graphics.setFont(font)
            love.graphics.setColor(
                COLORS.failGlyph[1],
                COLORS.failGlyph[2],
                COLORS.failGlyph[3],
                alpha
            )
            love.graphics.printf(
                FAIL_GLYPH,
                entity.anchor.x - 38,
                entity.anchor.y - font:getHeight() / 2,
                76,
                "center"
            )
            love.graphics.setFont(previousFont)
        end
    end

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function ReflexLogic.draw(round, jaclButtonBounds, hostileButtonBounds)
    if resolvedRound == nil or resolvedRound ~= round then
        return
    end

    if not jaclButtonBounds or not hostileButtonBounds then
        return
    end

    local centerY = jaclButtonBounds.y + jaclButtonBounds.height / 2
    local activeEntry = initiativeSequence[1]

    for index, entry in ipairs(agentQueue) do
        local centerX = jaclButtonBounds.x
            - BUTTON_QUEUE_GAP
            - TOKEN_SIZE / 2
            - (index - 1) * (TOKEN_SIZE + TOKEN_GAP)

        drawEntry(
            entry,
            centerX,
            centerY,
            entry == activeEntry
        )
    end

    for index, entry in ipairs(hostileQueue) do
        local centerX = hostileButtonBounds.x
            + hostileButtonBounds.width
            + BUTTON_QUEUE_GAP
            + TOKEN_SIZE / 2
            + (index - 1) * (TOKEN_SIZE + TOKEN_GAP)

        drawEntry(
            entry,
            centerX,
            centerY,
            entry == activeEntry
        )
    end

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

return ReflexLogic
