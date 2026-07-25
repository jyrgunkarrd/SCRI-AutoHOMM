local AgencyLogic = require("src.sys.agency_logic")
local BlockLogic = require("src.sys.block_logic")
local FateLogic = require("src.sys.fate_logic")
local HealthLogic = require("src.sys.health_logic")
local ImageLoader = require("src.assets.image_loader")
local MapPathfindingLogic = require("src.sys.map_pathfinding_logic")
local ReflexLogic = require("src.sys.reflex_logic")
local Sfx = require("src.sys.sfx")

local SteelCombat = {}

local DEFENDER_ENTRANCE_START = 0
local ATTACKER_ENTRANCE_START = 0.28
local ENTRANCE_DURATION = 0.3
local PROJECTILE_LAUNCH_TIME = 0.7
local FATE_DROP_START = PROJECTILE_LAUNCH_TIME
local AGENCY_DROP_START = PROJECTILE_LAUNCH_TIME + 0.1
local TILE_DROP_DURATION = 0.18
local IMPACT_TIME = 0.98
local BOUNCE_END_TIME = 1.25
local FADE_START_TIME = 1.42
local ACTION_DURATION = 1.68
local KILL_HIT_STOP_DURATION = 0.08
local KILL_FLASH_WHITE_DURATION = 0.08
local KILL_FLASH_RED_START = 0.05
local KILL_FLASH_RED_DURATION = 0.12
local KILL_COLLAPSE_START = 0.12
local KILL_COLLAPSE_DURATION = 0.3
local KILL_COLLAPSE_DISTANCE = 55
local KILL_BADGE_DELAY = 0.18
local COMBATANT_MAX_SIZE = 410
local COMBATANT_SCREEN_HEIGHT = 0.58
local COMBATANT_SCREEN_WIDTH = 0.28
local COMBATANT_CENTER_OFFSET = 0.58
local COMBATANT_ENTRANCE_OFFSET = 55
local PROJECTILE_SIZE = 96
local TILE_WIDTH = 154
local TILE_HEIGHT = 56
local TILE_GAP = 8
local TILE_DROP_DISTANCE = 52
local DAMAGE_BADGE_WIDTH = 108
local DAMAGE_BADGE_HEIGHT = 52

local phaseQueue = {}
local results = {}
local processing = false
local resolvedRound
local actionIndex = 0
local activeAnimation
local combatEntities = {}
local phaseRandom
local projectileCache = {}
local deathCutInShader

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function smoothstep(value)
    value = clamp(value, 0, 1)
    return value * value * (3 - 2 * value)
end

local function getTimedProgress(elapsed, startTime, duration)
    return clamp((elapsed - startTime) / duration, 0, 1)
end

local function isKillingResult(result)
    return result.damageApplied and result.slain == true
end

local function getActionDuration(result)
    return ACTION_DURATION
        + (isKillingResult(result) and KILL_HIT_STOP_DURATION or 0)
end

local function getVisualElapsed(animation)
    local elapsed = animation.elapsed

    if not isKillingResult(animation.result) then
        return elapsed
    end

    if elapsed <= IMPACT_TIME + KILL_HIT_STOP_DURATION then
        return math.min(elapsed, IMPACT_TIME)
    end

    return elapsed - KILL_HIT_STOP_DURATION
end

local function getStat(entity, requestedName)
    for _, statEntry in ipairs(entity.definition.stats or {}) do
        for name, value in pairs(statEntry) do
            if type(name) == "string"
                and name:lower() == requestedName
                and type(value) == "number" then
                return value
            end
        end
    end

    return 0
end

local function getSteelRange(entity)
    local attack = entity.definition.steel_atk

    if attack == nil then
        return nil, false
    end

    if type(attack) ~= "table" then
        return nil, true, "steel_atk must be a table"
    end

    for _, attackEntry in ipairs(attack) do
        if type(attackEntry) ~= "table" then
            return nil, true, "steel_atk entries must be tables"
        end

        if attackEntry.rng ~= nil then
            if type(attackEntry.rng) ~= "number"
                or attackEntry.rng ~= attackEntry.rng
                or attackEntry.rng == math.huge
                or attackEntry.rng == -math.huge
                or attackEntry.rng < 0 then
                return nil, true, "steel_atk rng must be non-negative"
            end

            return attackEntry.rng, true
        end
    end

    return nil, true, "steel_atk requires an rng value"
end

local function isOpponent(left, right)
    return left
        and right
        and (
            left.entityType == "AGENT"
                and right.entityType == "HOSTILE"
            or left.entityType == "HOSTILE"
                and right.entityType == "AGENT"
        )
end

local function getFootprintDistance(left, right)
    local closest = math.huge

    for _, leftCell in ipairs(left.footprint or {}) do
        for _, rightCell in ipairs(right.footprint or {}) do
            local distance, distanceError =
                MapPathfindingLogic.getHexDistance(
                    leftCell,
                    rightCell
                )

            if distance == nil then
                return nil, distanceError
            end

            closest = math.min(closest, distance)
        end
    end

    if closest == math.huge then
        return nil, "combat entities require a map footprint"
    end

    return closest
end

local function getRandomIndex(limit, random)
    local value

    if random then
        value = random(limit)
    elseif love and love.math and love.math.random then
        value = love.math.random(limit)
    else
        value = math.random(limit)
    end

    return math.max(1, math.min(limit, math.floor(tonumber(value) or 1)))
end

local function selectTarget(attacker, entities, range, random)
    local candidates = {}
    local lowestHp = math.huge

    for _, candidate in ipairs(entities) do
        if not candidate.dead and isOpponent(attacker, candidate) then
            local distance, distanceError = getFootprintDistance(
                attacker,
                candidate
            )

            if distance == nil then
                return nil, distanceError
            end

            if distance <= range then
                if candidate.hp < lowestHp then
                    candidates = { candidate }
                    lowestHp = candidate.hp
                elseif candidate.hp == lowestHp then
                    candidates[#candidates + 1] = candidate
                end
            end
        end
    end

    if #candidates == 0 then
        return nil
    end

    return candidates[getRandomIndex(#candidates, random)]
end

local function getFateStack(entity)
    if entity.entityType == "HOSTILE" then
        return FateLogic.getHostileStack()
    end

    return FateLogic.getActiveStack()
end

local function getFateModifier(tile)
    local value = tonumber(tile.definition.value) or 0

    if tile.definition.neg then
        return -value
    end

    return value
end

local function drawAttackTiles(attacker, random)
    local fateStack = getFateStack(attacker)

    if not fateStack then
        return nil, ("%s %q has no available Fate stack"):format(
            attacker.entityType,
            attacker.id
        )
    end

    if not attacker.agencyStack then
        return nil, ("%s %q has no Agency stack"):format(
            attacker.entityType,
            attacker.id
        )
    end

    local fateTile, fateError = FateLogic.drawModifier(
        fateStack,
        random
    )

    if not fateTile then
        return nil, (
            "unable to draw Steel Fate tile for %q: %s"
        ):format(attacker.id, tostring(fateError))
    end

    local agencyTile, agencyError = AgencyLogic.drawTile(
        attacker.agencyStack,
        random
    )

    if not agencyTile then
        return nil, (
            "unable to draw Steel Agency tile for %q: %s"
        ):format(attacker.id, tostring(agencyError))
    end

    local fateDiscarded, fateDiscardError =
        FateLogic.discardModifier(fateStack, fateTile, random)

    if not fateDiscarded then
        return nil, fateDiscardError
    end

    local agencyDiscarded, agencyDiscardError =
        AgencyLogic.discardTile(attacker.agencyStack, agencyTile)

    if not agencyDiscarded then
        return nil, agencyDiscardError
    end

    local blockGranted, blockError =
        BlockLogic.grantFromAgencyTile(attacker, agencyTile)

    if blockGranted == nil then
        return nil, (
            "unable to grant Steel Agency Block to %q: %s"
        ):format(attacker.id, tostring(blockError))
    end

    return {
        fateTile = fateTile,
        agencyTile = agencyTile,
        blockGranted = blockGranted,
    }
end

local function resolveEntry(entry, entities, random)
    local attacker = entry.entity
    local result = {
        entry = entry,
        attacker = attacker,
        attacked = false,
    }

    if attacker.dead then
        result.reason = "dead"
        return result
    end

    local range, hasAttack, rangeError = getSteelRange(attacker)

    if rangeError then
        return nil, (
            "invalid Steel attack for %q: %s"
        ):format(attacker.id, rangeError)
    end

    if not hasAttack then
        result.reason = "no_steel_attack"
        return result
    end

    local target, targetError = selectTarget(
        attacker,
        entities,
        range,
        random
    )

    if targetError then
        return nil, (
            "unable to select Steel target for %q: %s"
        ):format(attacker.id, tostring(targetError))
    end

    if not target then
        result.reason = "no_target_in_range"
        return result
    end

    local tiles, tileError = drawAttackTiles(attacker, random)

    if not tiles then
        return nil, tileError
    end

    local failed = tiles.fateTile.definition.fail == true
    local strength = getStat(attacker, "str")
    local damage = failed
        and 0
        or math.max(0, strength + getFateModifier(tiles.fateTile))

    result.attacked = true
    result.target = target
    result.range = range
    result.strength = strength
    result.damage = damage
    result.failed = failed
    result.fateTile = tiles.fateTile
    result.agencyTile = tiles.agencyTile
    result.blockGranted = tiles.blockGranted
    result.blockAbsorbed = 0
    result.hpLost = 0
    result.damageApplied = false
    result.slain = false

    return result
end

local function applyImpact(result)
    if result.damageApplied then
        return true
    end

    local target = result.target
    local hpBefore = target.hp
    local blockBefore = target.block
    local wasDead = target.dead == true

    if result.damage > 0 then
        local hp, damageError = HealthLogic.damage(
            target,
            result.damage
        )

        if hp == nil then
            return nil, (
                "unable to apply Steel damage from %q: %s"
            ):format(result.attacker.id, tostring(damageError))
        end
    end

    result.blockAbsorbed = blockBefore - target.block
    result.hpLost = hpBefore - target.hp
    result.damageApplied = true
    result.slain = not wasDead and target.dead == true

    return true
end

local function playImpactSfx(result)
    if result.damage > 0 then
        Sfx.play("damage")

        if result.fateTile.definition.crit then
            Sfx.play("crit_damage")
        end
    else
        Sfx.play("no_damage")
    end

    if result.slain then
        local slainTreatment = result.target.definition.slain
        local slainSfx = type(slainTreatment) == "string"
            and slainTreatment:lower() == "masc"
            and "slain_masc"
            or "slain_fem"

        Sfx.play(slainSfx)
    end
end

local function finishProcessing()
    processing = false
    activeAnimation = nil
    ReflexLogic.setPhaseActiveEntry(nil)
end

local function prepareNextAction()
    while processing do
        actionIndex = actionIndex + 1

        local entry = phaseQueue[actionIndex]

        if not entry then
            finishProcessing()
            return true
        end

        ReflexLogic.setPhaseActiveEntry(entry)

        local result, resolveError = resolveEntry(
            entry,
            combatEntities,
            phaseRandom
        )

        if not result then
            finishProcessing()
            return nil, resolveError
        end

        results[#results + 1] = result

        if result.attacked then
            activeAnimation = {
                result = result,
                elapsed = 0,
                launchSfxPlayed = false,
                impactSfxPlayed = false,
            }
            return true
        end
    end

    return true
end

function SteelCombat.reset()
    phaseQueue = {}
    results = {}
    processing = false
    resolvedRound = nil
    actionIndex = 0
    activeAnimation = nil
    combatEntities = {}
    phaseRandom = nil
    ReflexLogic.setPhaseActiveEntry(nil)
end

function SteelCombat.beginSteel(entities, round, random)
    SteelCombat.reset()
    resolvedRound = round
    combatEntities = entities or {}
    phaseRandom = random

    for _, entry in ipairs(ReflexLogic.getInitiativeSequence()) do
        phaseQueue[#phaseQueue + 1] = entry
    end

    processing = true

    local prepared, prepareError = prepareNextAction()

    if not prepared then
        return nil, prepareError
    end

    return phaseQueue
end

function SteelCombat.isProcessing()
    return processing
end

function SteelCombat.removeEntity(entity)
    local nextQueue = {}
    local nextActionIndex = 0
    local removed = 0

    for index, entry in ipairs(phaseQueue) do
        if entry.entity == entity then
            removed = removed + 1
        else
            nextQueue[#nextQueue + 1] = entry

            if index <= actionIndex then
                nextActionIndex = nextActionIndex + 1
            end
        end
    end

    phaseQueue = nextQueue
    actionIndex = nextActionIndex

    if activeAnimation
        and activeAnimation.result.attacker == entity
        and not activeAnimation.result.damageApplied then
        activeAnimation = nil

        if processing then
            local prepared, prepareError = prepareNextAction()

            if not prepared then
                error(prepareError)
            end
        end
    end

    return removed
end

function SteelCombat.update(dt)
    if not processing or not activeAnimation then
        return
    end

    dt = math.max(0, tonumber(dt) or 0)

    while processing and activeAnimation do
        local animation = activeAnimation

        if animation.result.attacker.dead
            and not animation.result.damageApplied then
            activeAnimation = nil

            local prepared, prepareError = prepareNextAction()

            if not prepared then
                error(prepareError)
            end

            if dt <= 0 then
                break
            end
        else
            local previousElapsed = animation.elapsed
            local actionDuration = getActionDuration(animation.result)
            local remaining = actionDuration - previousElapsed
            local step = math.min(dt, remaining)

            animation.elapsed = previousElapsed + step
            dt = dt - step

            if not animation.launchSfxPlayed
                and animation.elapsed >= PROJECTILE_LAUNCH_TIME then
                Sfx.play("steel_atk")
                animation.launchSfxPlayed = true
            end

            if not animation.result.damageApplied
                and animation.elapsed >= IMPACT_TIME then
                local impacted, impactError = applyImpact(
                    animation.result
                )

                if not impacted then
                    finishProcessing()
                    error(impactError)
                end
            end

            if animation.result.damageApplied
                and not animation.impactSfxPlayed then
                playImpactSfx(animation.result)
                animation.impactSfxPlayed = true
            end

            if animation.elapsed >= getActionDuration(animation.result) then
                activeAnimation = nil

                local prepared, prepareError = prepareNextAction()

                if not prepared then
                    error(prepareError)
                end
            else
                break
            end

            if dt <= 0 then
                break
            end
        end
    end
end

function SteelCombat.getPhaseQueue()
    return phaseQueue
end

function SteelCombat.getResults()
    return results
end

function SteelCombat.getActiveAnimation()
    return activeAnimation
end

local function getProjectileImage(entity)
    local cached = projectileCache[entity.id]

    if cached then
        return cached
    end

    local candidates = {
        ("assets/images/attacks/steel/%s.webp"):format(entity.id),
    }

    if entity.entityType == "HOSTILE" then
        candidates[#candidates + 1] = (
            "assets/images/attacks/steel/%s.webp"
        ):format(entity.id:gsub("^HOSTILE_", "ENEMY_"))
    end

    for _, path in ipairs(candidates) do
        if love.filesystem.getInfo(path, "file") then
            local loaded, image = pcall(ImageLoader.newImage, path)

            if not loaded then
                error((
                    "unable to load Steel attack image for %q from %s: %s"
                ):format(entity.id, path, tostring(image)))
            end

            projectileCache[entity.id] = image
            return image
        end
    end

    error(("no Steel attack image found for %q"):format(entity.id))
end

local function getCutInLayout(result)
    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    local combatantSize = math.min(
        COMBATANT_MAX_SIZE,
        screenHeight * COMBATANT_SCREEN_HEIGHT,
        screenWidth * COMBATANT_SCREEN_WIDTH
    )
    local centerX = screenWidth / 2
    local centerY = screenHeight / 2 + combatantSize * 0.16
    local centerOffset = combatantSize * COMBATANT_CENTER_OFFSET
    local agentX = centerX - centerOffset
    local hostileX = centerX + centerOffset
    local attackerX = result.attacker.entityType == "AGENT"
        and agentX
        or hostileX
    local defenderX = result.target.entityType == "AGENT"
        and agentX
        or hostileX

    return {
        screenWidth = screenWidth,
        screenHeight = screenHeight,
        combatantSize = combatantSize,
        centerY = centerY,
        attackerX = attackerX,
        defenderX = defenderX,
    }
end

local function getDeathCutInShader()
    if not deathCutInShader then
        deathCutInShader = love.graphics.newShader([[
            extern number whiteAmount;
            extern number redAmount;
            extern number deathProgress;

            vec4 effect(
                vec4 color,
                Image image,
                vec2 textureCoordinates,
                vec2 screenCoordinates
            ) {
                vec4 pixel = Texel(image, textureCoordinates);
                float gray = dot(
                    pixel.rgb,
                    vec3(0.299, 0.587, 0.114)
                );
                vec3 treated = mix(
                    pixel.rgb,
                    vec3(gray * 0.62),
                    deathProgress
                );
                treated = mix(treated, vec3(1.0), whiteAmount);
                treated = mix(
                    treated,
                    vec3(0.82, 0.015, 0.015),
                    redAmount
                );
                return vec4(treated, pixel.a) * color;
            }
        ]])
    end

    return deathCutInShader
end

local function drawCombatant(
    entity,
    targetX,
    centerY,
    size,
    role,
    elapsed,
    opacity,
    deathAge
)
    local startTime = role == "defender"
        and DEFENDER_ENTRANCE_START
        or ATTACKER_ENTRANCE_START
    local fadeProgress = getTimedProgress(
        elapsed,
        startTime,
        ENTRANCE_DURATION * 0.62
    )
    local shiftProgress = smoothstep(getTimedProgress(
        elapsed,
        startTime + ENTRANCE_DURATION * 0.28,
        ENTRANCE_DURATION * 0.72
    ))

    if fadeProgress <= 0 then
        return
    end

    local direction = entity.entityType == "AGENT" and -1 or 1
    local drawX = targetX
        + direction * COMBATANT_ENTRANCE_OFFSET * (1 - shiftProgress)
    local image = entity.profileImage
    local imageWidth, imageHeight = image:getDimensions()
    local collapseProgress = deathAge
        and smoothstep(getTimedProgress(
            deathAge,
            KILL_COLLAPSE_START,
            KILL_COLLAPSE_DURATION
        ))
        or 0
    local scale = size / math.max(imageWidth, imageHeight)
        * (1 - collapseProgress * 0.08)
    local drawY = centerY + collapseProgress * KILL_COLLAPSE_DISTANCE
    local previousShader

    if deathAge then
        local whiteAmount = 1 - getTimedProgress(
            deathAge,
            0,
            KILL_FLASH_WHITE_DURATION
        )
        local redAmount = deathAge >= KILL_FLASH_RED_START
            and 1 - getTimedProgress(
                deathAge,
                KILL_FLASH_RED_START,
                KILL_FLASH_RED_DURATION
            )
            or 0
        local shader = getDeathCutInShader()

        shader:send("whiteAmount", whiteAmount)
        shader:send("redAmount", redAmount)
        shader:send("deathProgress", collapseProgress)
        previousShader = love.graphics.getShader()
        love.graphics.setShader(shader)
    end

    love.graphics.setColor(
        1,
        1,
        1,
        fadeProgress * opacity * (1 - collapseProgress)
    )
    love.graphics.draw(
        image,
        drawX,
        drawY,
        0,
        scale,
        scale,
        imageWidth / 2,
        imageHeight / 2
    )

    if deathAge then
        if previousShader then
            love.graphics.setShader(previousShader)
        else
            love.graphics.setShader()
        end
    end
end

local function drawDroppedTile(
    drawer,
    tile,
    x,
    targetY,
    elapsed,
    startTime,
    opacity
)
    local progress = smoothstep(getTimedProgress(
        elapsed,
        startTime,
        TILE_DROP_DURATION
    ))

    if elapsed < PROJECTILE_LAUNCH_TIME then
        return
    end

    local appearance = getTimedProgress(
        elapsed,
        PROJECTILE_LAUNCH_TIME,
        0.08
    )
    local drawY = targetY - TILE_DROP_DISTANCE * (1 - progress)
    drawer(tile, x, drawY, TILE_WIDTH, appearance * opacity)
end

local function drawDamageBadge(result, x, y, elapsed, fade)
    if elapsed < IMPACT_TIME or not result.damageApplied then
        return
    end

    local badgeX = x - DAMAGE_BADGE_WIDTH / 2
    local badgeY = y - DAMAGE_BADGE_HEIGHT / 2
    local label = isKillingResult(result)
        and elapsed - IMPACT_TIME >= KILL_BADGE_DELAY
        and "SLAIN"
        or tostring(result.damage)

    love.graphics.setColor(0, 0, 0, 0.94 * fade)
    love.graphics.rectangle(
        "fill",
        badgeX,
        badgeY,
        DAMAGE_BADGE_WIDTH,
        DAMAGE_BADGE_HEIGHT,
        5,
        5
    )
    love.graphics.setColor(1, 1, 1, fade)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle(
        "line",
        badgeX,
        badgeY,
        DAMAGE_BADGE_WIDTH,
        DAMAGE_BADGE_HEIGHT,
        5,
        5
    )
    love.graphics.printf(
        label,
        badgeX,
        badgeY + 15,
        DAMAGE_BADGE_WIDTH,
        "center"
    )
end

local function drawProjectile(result, layout, elapsed, fade)
    if elapsed < PROJECTILE_LAUNCH_TIME then
        return
    end

    local fromX = layout.attackerX
    local fromY = layout.centerY
    local toX = layout.defenderX
    local toY = layout.centerY
    local direction = toX > fromX and 1 or -1
    local drawX
    local drawY
    local rotation
    local opacity = fade

    if elapsed <= IMPACT_TIME then
        local progress = smoothstep(getTimedProgress(
            elapsed,
            PROJECTILE_LAUNCH_TIME,
            IMPACT_TIME - PROJECTILE_LAUNCH_TIME
        ))

        drawX = fromX + (toX - fromX) * progress
        drawY = fromY + (toY - fromY) * progress
        rotation = direction * 0.08 * progress
    else
        local progress = smoothstep(getTimedProgress(
            elapsed,
            IMPACT_TIME,
            BOUNCE_END_TIME - IMPACT_TIME
        ))

        drawX = toX - direction * 118 * progress
        drawY = toY - 54 * math.sin(progress * math.pi)
        rotation = direction * (0.08 - 0.72 * progress)

        if elapsed > BOUNCE_END_TIME then
            opacity = opacity * (
                1 - getTimedProgress(
                    elapsed,
                    BOUNCE_END_TIME,
                    FADE_START_TIME - BOUNCE_END_TIME
                )
            )
        end
    end

    if opacity <= 0 then
        return
    end

    local image = getProjectileImage(result.attacker)
    local imageWidth, imageHeight = image:getDimensions()
    local scale = PROJECTILE_SIZE / math.max(imageWidth, imageHeight)

    love.graphics.setColor(1, 1, 1, opacity)
    love.graphics.draw(
        image,
        drawX,
        drawY,
        rotation,
        scale,
        scale,
        imageWidth / 2,
        imageHeight / 2
    )
end

function SteelCombat.draw()
    if not activeAnimation then
        return
    end

    local result = activeAnimation.result
    local elapsed = getVisualElapsed(activeAnimation)
    local layout = getCutInLayout(result)
    local fade = 1 - getTimedProgress(
        elapsed,
        FADE_START_TIME,
        ACTION_DURATION - FADE_START_TIME
    )
    local overlayFade = math.min(
        getTimedProgress(elapsed, 0, 0.12),
        fade
    )

    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 0.76 * overlayFade)
    love.graphics.rectangle(
        "fill",
        0,
        0,
        layout.screenWidth,
        layout.screenHeight
    )

    drawCombatant(
        result.target,
        layout.defenderX,
        layout.centerY,
        layout.combatantSize,
        "defender",
        elapsed,
        fade,
        isKillingResult(result)
            and math.max(0, elapsed - IMPACT_TIME)
            or nil
    )
    drawCombatant(
        result.attacker,
        layout.attackerX,
        layout.centerY,
        layout.combatantSize,
        "attacker",
        elapsed,
        fade,
        nil
    )

    if elapsed >= PROJECTILE_LAUNCH_TIME then
        local tileX = layout.attackerX - TILE_WIDTH / 2
        local fateY = layout.centerY
            - layout.combatantSize / 2
            - TILE_HEIGHT
            - 18
        local agencyY = fateY - TILE_HEIGHT - TILE_GAP

        drawDroppedTile(
            FateLogic.drawTileCard,
            result.fateTile,
            tileX,
            fateY,
            elapsed,
            FATE_DROP_START,
            fade
        )
        drawDroppedTile(
            AgencyLogic.drawTileCard,
            result.agencyTile,
            tileX,
            agencyY,
            elapsed,
            AGENCY_DROP_START,
            fade
        )
    end

    drawDamageBadge(
        result,
        layout.defenderX,
        layout.centerY,
        elapsed,
        fade
    )
    drawProjectile(result, layout, elapsed, fade)
    love.graphics.pop()
end

function SteelCombat.getResolvedRound()
    return resolvedRound
end

return SteelCombat
