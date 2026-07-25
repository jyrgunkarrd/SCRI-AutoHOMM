local AgencyLogic = require("src.sys.agency_logic")
local BattleMap = require("src.sys.battle_map")
local BlockLogic = require("src.sys.block_logic")
local ConditionLogic = require("src.sys.condition_logic")
local FateLogic = require("src.sys.fate_logic")
local HealthLogic = require("src.sys.health_logic")
local ImageLoader = require("src.assets.image_loader")
local MapPathfindingLogic = require("src.sys.map_pathfinding_logic")
local ReflexLogic = require("src.sys.reflex_logic")
local Sfx = require("src.sys.sfx")
local ShoveLogic = require("src.sys.shove_logic")

local function newCombat(config)
config = config or {}

local combatName = config.name or "Combat"
local attackKey = config.attackKey
local projectileDirectory = config.projectileDirectory
local launchSfx = config.launchSfx
local noAttackReason = config.noAttackReason or "no_attack"
local ammunitionField = config.ammunitionField or "fireAmmo"
local ammunitionCapacityField = config.ammunitionCapacityField
    or "fireAmmoCapacity"

assert(type(attackKey) == "string", "combat attackKey is required")
assert(
    type(projectileDirectory) == "string",
    "combat projectileDirectory is required"
)
assert(type(launchSfx) == "string", "combat launchSfx is required")

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
local SHOVE_BASE_DURATION = 0.12
local SHOVE_DURATION_PER_HEX = 0.08
local HAZARD_DEATH_FREEZE_DURATION = 0.07
local HAZARD_DEATH_REACTION_DURATION = 0.11
local HAZARD_DEATH_SETTLE_DURATION = 0.12
local HAZARD_DEATH_SQUASH_SCALE = 0.85
local HAZARD_DEATH_OFFSET = 6
local KILL_HIT_STOP_DURATION = 0.08
local KILL_FLASH_WHITE_DURATION = 0.08
local KILL_FLASH_RED_START = 0.05
local KILL_FLASH_RED_DURATION = 0.12
local KILL_COLLAPSE_START = 0.12
local KILL_COLLAPSE_DURATION = 0.3
local KILL_COLLAPSE_DISTANCE = 55
local KILL_BADGE_DELAY = 0.18
local STUN_FLASH_DURATION = 0.11
local STUN_JITTER_DURATION = 0.18
local STUN_JITTER_DISTANCE = 10
local STUN_STAMP_POP_DURATION = 0.12
local STUN_STAMP_HOLD_DURATION = 0.26
local STUN_STAMP_FADE_DURATION = 0.16
local STUN_STAMP_SIZE = 72
local STUN_STAMP_PADDING = 5
local AMMO_DROP_DURATION = 0.14
local AMMO_HOLD_DURATION = 0.32
local AMMO_FADE_DURATION = 0.12
local AMMO_DROP_DISTANCE = 28
local AMMO_TILE_WIDTH = 144
local AMMO_TILE_HEIGHT = 40
local AMMO_TILE_GAP = 10
local AMMO_ICON_SIZE = 27
local AMMO_ROW_GAP = 9
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
local activeShoveAnimation
local activeHazardDeathAnimation
local activeAmmunitionAnimation
local combatEntities = {}
local phaseRandom
local projectileCache = {}
local deathCutInShader
local stunCutInShader
local stunConditionIcon
local ammunitionIcon

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

local function getAttackRange(entity)
    local attack = entity.definition[attackKey]

    if attack == nil then
        return nil, nil, false
    end

    if type(attack) ~= "table" then
        return nil, nil, true, attackKey .. " must be a table"
    end

    local range
    local minimumRange

    for _, attackEntry in ipairs(attack) do
        if type(attackEntry) ~= "table" then
            return nil, nil, true,
                attackKey .. " entries must be tables"
        end

        if attackEntry.rng ~= nil then
            if type(attackEntry.rng) ~= "number"
                or attackEntry.rng ~= attackEntry.rng
                or attackEntry.rng == math.huge
                or attackEntry.rng == -math.huge
                or attackEntry.rng < 0 then
                return nil, nil, true,
                    attackKey .. " rng must be non-negative"
            end

            range = attackEntry.rng
        end

        if attackEntry.min_rng ~= nil then
            if type(attackEntry.min_rng) ~= "number"
                or attackEntry.min_rng ~= attackEntry.min_rng
                or attackEntry.min_rng == math.huge
                or attackEntry.min_rng == -math.huge
                or attackEntry.min_rng < 0 then
                return nil, nil, true,
                    attackKey .. " min_rng must be non-negative"
            end

            minimumRange = attackEntry.min_rng
        end
    end

    if range == nil then
        return nil, nil, true, attackKey .. " requires an rng value"
    end

    if config.requiresMinimumRange and minimumRange == nil then
        return nil, nil, true,
            attackKey .. " requires a min_rng value"
    end

    minimumRange = minimumRange or -1

    if minimumRange >= range then
        return nil, nil, true,
            attackKey .. " min_rng must be less than rng"
    end

    return range, minimumRange, true
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

local function selectTarget(
    attacker,
    entities,
    range,
    minimumRange,
    random
)
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

            if distance <= range and distance > minimumRange then
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

local function getAmmunitionCapacity(entity)
    local capacity = entity.definition.ammo

    if type(capacity) ~= "number"
        or capacity ~= capacity
        or capacity == math.huge
        or capacity % 1 ~= 0
        or capacity < 0 then
        return nil, (
            "%s %q requires a non-negative integer ammo value"
        ):format(entity.entityType, entity.id)
    end

    return capacity
end

local function initializeEntityAmmunition(entity, replenish)
    if not config.usesAmmunition
        or entity.definition[attackKey] == nil then
        return true
    end

    local capacity, capacityError = getAmmunitionCapacity(entity)

    if capacity == nil then
        return nil, capacityError
    end

    entity[ammunitionCapacityField] = capacity

    if replenish or entity[ammunitionField] == nil then
        entity[ammunitionField] = capacity
    end

    return true
end

function SteelCombat.initializeAmmunition(entities, replenish)
    for _, entity in ipairs(entities or {}) do
        local initialized, initializeError =
            initializeEntityAmmunition(entity, replenish == true)

        if not initialized then
            return nil, initializeError
        end
    end

    return true
end

function SteelCombat.getAmmunition(entity)
    if not config.usesAmmunition then
        return nil
    end

    return entity and entity[ammunitionField],
        entity and entity[ammunitionCapacityField]
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
            "unable to draw %s Fate tile for %q: %s"
        ):format(combatName, attacker.id, tostring(fateError))
    end

    local agencyTile, agencyError = AgencyLogic.drawTile(
        attacker.agencyStack,
        random
    )

    if not agencyTile then
        return nil, (
            "unable to draw %s Agency tile for %q: %s"
        ):format(combatName, attacker.id, tostring(agencyError))
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
            "unable to grant %s Agency Block to %q: %s"
        ):format(combatName, attacker.id, tostring(blockError))
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

    local range, minimumRange, hasAttack, rangeError =
        getAttackRange(attacker)

    if rangeError then
        return nil, (
            "invalid %s attack for %q: %s"
        ):format(combatName, attacker.id, rangeError)
    end

    if not hasAttack then
        result.reason = noAttackReason
        return result
    end

    if config.usesAmmunition
        and (attacker[ammunitionField] or 0) <= 0 then
        result.reason = "no_ammunition"
        return result
    end

    local target, targetError = selectTarget(
        attacker,
        entities,
        range,
        minimumRange,
        random
    )

    if targetError then
        return nil, (
            "unable to select %s target for %q: %s"
        ):format(combatName, attacker.id, tostring(targetError))
    end

    if not target then
        result.reason = "no_target_in_range"
        return result
    end

    local tiles, tileError = drawAttackTiles(attacker, random)

    if not tiles then
        return nil, tileError
    end

    if config.usesAmmunition then
        attacker[ammunitionField] = attacker[ammunitionField] - 1
    end

    local failed = tiles.fateTile.definition.fail == true
    local strength = getStat(attacker, "str")
    local damage = failed
        and 0
        or math.max(0, strength + getFateModifier(tiles.fateTile))

    result.attacked = true
    result.target = target
    result.range = range
    result.minimumRange = minimumRange
    result.ammunitionRemaining = config.usesAmmunition
        and attacker[ammunitionField]
        or nil
    result.strength = strength
    result.damage = damage
    result.failed = failed
    result.fateTile = tiles.fateTile
    result.agencyTile = tiles.agencyTile
    result.blockGranted = tiles.blockGranted
    local shoveDistance, shoveError =
        ShoveLogic.getDistance(tiles.agencyTile)

    if shoveDistance == nil then
        return nil, shoveError
    end

    result.shoveDistance = shoveDistance
    local stunCount, stunError = ConditionLogic.getAgencyActionCount(
        tiles.agencyTile,
        "stun"
    )

    if stunCount == nil then
        return nil, stunError
    end

    result.stunCount = stunCount
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
                "unable to apply %s damage from %q: %s"
            ):format(
                combatName,
                result.attacker.id,
                tostring(damageError)
            )
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

        Sfx.play(
            type(slainTreatment) == "string"
                and slainTreatment:lower() == "masc"
                and "slain_masc"
                or "slain_fem"
        )
    end
end

local function playShoveTerrainSfx(target, terrainResult)
    if not terrainResult then
        return
    end

    if (terrainResult.damage or 0) > 0
        or (terrainResult.blockLost or 0) > 0 then
        Sfx.play("damage")
    end

    if terrainResult.killed then
        local slainTreatment = target.definition.slain

        Sfx.play(
            type(slainTreatment) == "string"
                and slainTreatment:lower() == "masc"
                and "slain_masc"
                or "slain_fem"
        )
    end
end

local function applyAgencyConditions(result)
    if result.conditionsApplied then
        return true
    end

    result.conditionsApplied = true
    result.stunApplied = 0

    if result.target.dead or result.stunCount <= 0 then
        return true
    end

    local added, addError = ConditionLogic.addInstances(
        result.target,
        "NEG_STUN",
        result.stunCount
    )

    if not added then
        return nil, (
            "unable to apply %s Stun from %q: %s"
        ):format(combatName, result.attacker.id, tostring(addError))
    end

    result.stunApplied = #added
    result.stunInstances = added

    return true
end

local function beginShove(result)
    if result.target.dead or result.shoveDistance <= 0 then
        result.shoveResolved = true
        return false
    end

    local destination, selectionOrError = ShoveLogic.selectDestination(
        result.attacker,
        result.target,
        result.shoveDistance,
        phaseRandom
    )

    if not destination then
        if selectionOrError then
            return nil, (
                "unable to select %s shove destination from %q: %s"
            ):format(
                combatName,
                result.attacker.id,
                tostring(selectionOrError)
            )
        end

        result.shoveResolved = true
        result.shove = {
            distance = result.shoveDistance,
            moved = false,
            reason = "no_valid_destination",
        }
        return false
    end

    local target = result.target
    local travelDistance, distanceError =
        MapPathfindingLogic.getHexDistance(target.anchor, destination)

    if travelDistance == nil then
        return nil, (
            "unable to measure %s shove from %q: %s"
        ):format(
            combatName,
            result.attacker.id,
            tostring(distanceError)
        )
    end

    target.movementVisualX = target.anchor.x
    target.movementVisualY = target.anchor.y
    activeShoveAnimation = {
        result = result,
        target = target,
        origin = target.anchor,
        destination = destination,
        selection = selectionOrError,
        elapsed = 0,
        duration = SHOVE_BASE_DURATION
            + travelDistance * SHOVE_DURATION_PER_HEX,
    }
    return true
end

local function clearShoveVisual(animation)
    if animation and animation.target then
        animation.target.movementVisualX = nil
        animation.target.movementVisualY = nil
    end
end

local function clearHazardDeathVisual(animation)
    local target = animation and animation.target

    if not target then
        return
    end

    target.hazardDeathEffectScale = nil
    target.hazardDeathEffectOffsetY = nil
    target.hazardDeathGrayAmount = nil
    target.hazardDeathWhiteAmount = nil
    target.hazardDeathRedAmount = nil
    target.hazardDeathHideGauges = nil
end

local function beginHazardDeath(result)
    local target = result.target

    target.hazardDeathEffectScale = 1
    target.hazardDeathEffectOffsetY = 0
    target.hazardDeathGrayAmount = 0
    target.hazardDeathWhiteAmount = 1
    target.hazardDeathRedAmount = 0
    target.hazardDeathHideGauges = true
    activeHazardDeathAnimation = {
        result = result,
        target = target,
        elapsed = 0,
        duration = HAZARD_DEATH_FREEZE_DURATION
            + HAZARD_DEATH_REACTION_DURATION
            + HAZARD_DEATH_SETTLE_DURATION,
    }
end

local prepareNextAction

local function beginAmmunitionAnimation(result)
    if not config.usesAmmunition
        or result.ammunitionRemaining == nil
        or result.ammunitionAnimationStarted then
        return false
    end

    result.ammunitionAnimationStarted = true
    activeAmmunitionAnimation = {
        result = result,
        entity = result.attacker,
        remaining = result.ammunitionRemaining,
        capacity = result.attacker[ammunitionCapacityField],
        elapsed = 0,
        duration = AMMO_DROP_DURATION
            + AMMO_HOLD_DURATION
            + AMMO_FADE_DURATION,
    }

    return true
end

local function continueAfterAttack(result)
    if beginAmmunitionAnimation(result) then
        return true
    end

    local prepared, prepareError = prepareNextAction()

    if not prepared then
        return nil, prepareError
    end

    return true
end

local function finishProcessing()
    clearShoveVisual(activeShoveAnimation)
    clearHazardDeathVisual(activeHazardDeathAnimation)
    processing = false
    activeAnimation = nil
    activeShoveAnimation = nil
    activeHazardDeathAnimation = nil
    activeAmmunitionAnimation = nil
    ReflexLogic.setPhaseActiveEntry(nil)
end

prepareNextAction = function()
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
    clearShoveVisual(activeShoveAnimation)
    activeShoveAnimation = nil
    clearHazardDeathVisual(activeHazardDeathAnimation)
    activeHazardDeathAnimation = nil
    activeAmmunitionAnimation = nil
    combatEntities = {}
    phaseRandom = nil
    ReflexLogic.setPhaseActiveEntry(nil)
end

function SteelCombat.begin(entities, round, random)
    SteelCombat.reset()
    resolvedRound = round
    combatEntities = entities or {}
    phaseRandom = random

    local initialized, initializeError =
        SteelCombat.initializeAmmunition(combatEntities)

    if not initialized then
        return nil, initializeError
    end

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

    if activeShoveAnimation and activeShoveAnimation.target == entity then
        clearShoveVisual(activeShoveAnimation)
        activeShoveAnimation = nil

        if processing then
            local prepared, prepareError = prepareNextAction()

            if not prepared then
                error(prepareError)
            end
        end
    end

    if activeHazardDeathAnimation
        and activeHazardDeathAnimation.target == entity then
        clearHazardDeathVisual(activeHazardDeathAnimation)
        activeHazardDeathAnimation = nil

        if processing then
            local prepared, prepareError = prepareNextAction()

            if not prepared then
                error(prepareError)
            end
        end
    end

    if activeAmmunitionAnimation
        and activeAmmunitionAnimation.entity == entity then
        activeAmmunitionAnimation = nil

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
    if not processing
        or (
            not activeAnimation
            and not activeShoveAnimation
            and not activeHazardDeathAnimation
            and not activeAmmunitionAnimation
        ) then
        return
    end

    dt = math.max(0, tonumber(dt) or 0)

    while processing
        and (
            activeAnimation
            or activeShoveAnimation
            or activeHazardDeathAnimation
            or activeAmmunitionAnimation
        ) do
        if activeAmmunitionAnimation then
            local animation = activeAmmunitionAnimation
            local remaining = animation.duration - animation.elapsed
            local step = math.min(dt, remaining)

            animation.elapsed = animation.elapsed + step
            dt = dt - step

            if animation.elapsed >= animation.duration then
                animation.result.ammunitionAnimationResolved = true
                activeAmmunitionAnimation = nil

                local prepared, prepareError = prepareNextAction()

                if not prepared then
                    error(prepareError)
                end
            else
                break
            end
        elseif activeHazardDeathAnimation then
            local animation = activeHazardDeathAnimation
            local remaining = animation.duration - animation.elapsed
            local step = math.min(dt, remaining)

            animation.elapsed = animation.elapsed + step
            dt = dt - step

            local reactionStart = HAZARD_DEATH_FREEZE_DURATION
            local settleStart = reactionStart
                + HAZARD_DEATH_REACTION_DURATION

            if animation.elapsed <= reactionStart then
                animation.target.hazardDeathEffectScale = 1
                animation.target.hazardDeathEffectOffsetY = 0
                animation.target.hazardDeathGrayAmount = 0
                animation.target.hazardDeathWhiteAmount = 1
                animation.target.hazardDeathRedAmount = 0
            elseif animation.elapsed <= settleStart then
                local progress = smoothstep(
                    (animation.elapsed - reactionStart)
                        / HAZARD_DEATH_REACTION_DURATION
                )

                animation.target.hazardDeathEffectScale = 1
                    - (1 - HAZARD_DEATH_SQUASH_SCALE) * progress
                animation.target.hazardDeathEffectOffsetY =
                    HAZARD_DEATH_OFFSET * progress
                animation.target.hazardDeathGrayAmount = progress * 0.5
                animation.target.hazardDeathWhiteAmount = 1 - progress
                animation.target.hazardDeathRedAmount =
                    math.sin(progress * math.pi) * 0.9
            else
                local progress = smoothstep(
                    (animation.elapsed - settleStart)
                        / HAZARD_DEATH_SETTLE_DURATION
                )

                animation.target.hazardDeathEffectScale =
                    HAZARD_DEATH_SQUASH_SCALE
                        + (1 - HAZARD_DEATH_SQUASH_SCALE) * progress
                animation.target.hazardDeathEffectOffsetY =
                    HAZARD_DEATH_OFFSET * (1 - progress)
                animation.target.hazardDeathGrayAmount =
                    0.5 + progress * 0.5
                animation.target.hazardDeathWhiteAmount = 0
                animation.target.hazardDeathRedAmount =
                    (1 - progress) * 0.45
            end

            if animation.elapsed >= animation.duration then
                clearHazardDeathVisual(animation)
                activeHazardDeathAnimation = nil

                local continued, continueError =
                    continueAfterAttack(animation.result)

                if not continued then
                    error(continueError)
                end
            else
                break
            end
        elseif activeShoveAnimation then
            local animation = activeShoveAnimation
            local remaining = animation.duration - animation.elapsed
            local step = math.min(dt, remaining)

            animation.elapsed = animation.elapsed + step
            dt = dt - step

            local progress = math.min(
                1,
                animation.elapsed / animation.duration
            )
            local easedProgress = 1 - (1 - progress) ^ 3

            animation.target.movementVisualX = animation.origin.x
                + (animation.destination.x - animation.origin.x)
                    * easedProgress
            animation.target.movementVisualY = animation.origin.y
                + (animation.destination.y - animation.origin.y)
                    * easedProgress

            if animation.elapsed >= animation.duration then
                clearShoveVisual(animation)
                activeShoveAnimation = nil

                local shove, shoveError = ShoveLogic.moveTo(
                    animation.target,
                    animation.result.shoveDistance,
                    animation.destination,
                    animation.selection
                )

                if not shove then
                    finishProcessing()
                    error((
                        "unable to resolve %s shove from %q: %s"
                    ):format(
                        combatName,
                        animation.result.attacker.id,
                        tostring(shoveError)
                    ))
                end

                animation.result.shove = shove
                animation.result.shoveResolved = true
                playShoveTerrainSfx(
                    animation.target,
                    shove.terrain
                )

                if shove.terrain and shove.terrain.killed then
                    beginHazardDeath(animation.result)
                else
                    local continued, continueError =
                        continueAfterAttack(animation.result)

                    if not continued then
                        error(continueError)
                    end
                end
            else
                break
            end
        else
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
                    Sfx.play(launchSfx)
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

                    local applied, conditionError =
                        applyAgencyConditions(animation.result)

                    if not applied then
                        finishProcessing()
                        error(conditionError)
                    end

                    local started, shoveError =
                        beginShove(animation.result)

                    if started == nil then
                        finishProcessing()
                        error(shoveError)
                    end

                    if not started then
                        local continued, continueError =
                            continueAfterAttack(animation.result)

                        if not continued then
                            error(continueError)
                        end
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

function SteelCombat.getActiveShoveAnimation()
    return activeShoveAnimation
end

function SteelCombat.getActiveHazardDeathAnimation()
    return activeHazardDeathAnimation
end

function SteelCombat.getActiveAmmunitionAnimation()
    return activeAmmunitionAnimation
end

local function getProjectileImage(entity)
    local cached = projectileCache[entity.id]

    if cached then
        return cached
    end

    local candidates = {
        ("%s/%s.webp"):format(projectileDirectory, entity.id),
    }

    if entity.entityType == "HOSTILE" then
        candidates[#candidates + 1] = (
            "%s/%s.webp"
        ):format(
            projectileDirectory,
            entity.id:gsub("^HOSTILE_", "ENEMY_")
        )
    end

    for _, path in ipairs(candidates) do
        if love.filesystem.getInfo(path, "file") then
            local loaded, image = pcall(ImageLoader.newImage, path)

            if not loaded then
                error((
                    "unable to load %s attack image for %q from %s: %s"
                ):format(combatName, entity.id, path, tostring(image)))
            end

            projectileCache[entity.id] = image
            return image
        end
    end

    error((
        "no %s attack image found for %q"
    ):format(combatName, entity.id))
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

local function getStunCutInShader()
    if not stunCutInShader then
        stunCutInShader = love.graphics.newShader([[
            extern number whiteAmount;

            vec4 effect(
                vec4 color,
                Image image,
                vec2 textureCoordinates,
                vec2 screenCoordinates
            ) {
                vec4 pixel = Texel(image, textureCoordinates);
                vec3 treated = mix(
                    pixel.rgb,
                    vec3(1.0),
                    whiteAmount
                );
                return vec4(treated, pixel.a) * color;
            }
        ]])
    end

    return stunCutInShader
end

local function getStunConditionIcon()
    if stunConditionIcon then
        return stunConditionIcon
    end

    local path = "assets/images/icons/NEG_STUN.webp"
    local loaded, image = pcall(ImageLoader.newImage, path)

    if not loaded or not image then
        error((
            "unable to load Stun condition icon from %s: %s"
        ):format(path, tostring(image)))
    end

    stunConditionIcon = image
    return image
end

local function getAmmunitionIcon()
    if ammunitionIcon then
        return ammunitionIcon
    end

    local path = "assets/images/icons/ammo.webp"
    local loaded, image = pcall(ImageLoader.newImage, path)

    if not loaded or not image then
        error((
            "unable to load ammunition icon from %s: %s"
        ):format(path, tostring(image)))
    end

    ammunitionIcon = image
    return image
end

local function isApplyingStun(result)
    return result.damageApplied
        and not result.target.dead
        and (result.stunCount or 0) > 0
end

local function getStunJitter(result, elapsed)
    if not isApplyingStun(result) then
        return 0
    end

    local age = elapsed - IMPACT_TIME

    if age < 0 or age >= STUN_JITTER_DURATION then
        return 0
    end

    local progress = age / STUN_JITTER_DURATION

    return math.sin(progress * math.pi * 6)
        * STUN_JITTER_DISTANCE
        * (1 - progress)
end

local function drawCombatant(
    entity,
    targetX,
    centerY,
    size,
    role,
    elapsed,
    opacity,
    deathAge,
    stunFlashAmount
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
    local shaderApplied = false

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
        shaderApplied = true
    elseif stunFlashAmount and stunFlashAmount > 0 then
        local shader = getStunCutInShader()

        shader:send("whiteAmount", stunFlashAmount)
        previousShader = love.graphics.getShader()
        love.graphics.setShader(shader)
        shaderApplied = true
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

    if shaderApplied then
        if previousShader then
            love.graphics.setShader(previousShader)
        else
            love.graphics.setShader()
        end
    end
end

local function drawStunStamp(result, layout, elapsed, fade)
    if not isApplyingStun(result) then
        return
    end

    local age = elapsed - IMPACT_TIME
    local totalDuration = STUN_STAMP_POP_DURATION
        + STUN_STAMP_HOLD_DURATION
        + STUN_STAMP_FADE_DURATION

    if age < 0 or age >= totalDuration then
        return
    end

    local popProgress = smoothstep(
        age / STUN_STAMP_POP_DURATION
    )
    local scale = 1 + 0.4 * (1 - popProgress)
    local fadeStart = STUN_STAMP_POP_DURATION
        + STUN_STAMP_HOLD_DURATION
    local opacity = age <= fadeStart
        and 1
        or 1 - getTimedProgress(
            age,
            fadeStart,
            STUN_STAMP_FADE_DURATION
        )

    opacity = opacity * fade

    local size = STUN_STAMP_SIZE * scale
    local centerX = layout.defenderX
    local centerY = layout.centerY - layout.combatantSize * 0.36
    local backingSize = size + STUN_STAMP_PADDING * 2
    local icon = getStunConditionIcon()
    local iconWidth, iconHeight = icon:getDimensions()
    local iconScale = size / math.max(iconWidth, iconHeight)

    love.graphics.setColor(0, 0, 0, opacity)
    love.graphics.rectangle(
        "fill",
        centerX - backingSize / 2,
        centerY - backingSize / 2,
        backingSize,
        backingSize
    )
    love.graphics.setColor(1, 1, 1, opacity)
    love.graphics.draw(
        icon,
        centerX,
        centerY,
        0,
        iconScale,
        iconScale,
        iconWidth / 2,
        iconHeight / 2
    )

    if result.stunCount > 1 then
        local labelWidth = 34
        local labelHeight = 22
        local labelX = centerX + backingSize / 2 - labelWidth
        local labelY = centerY + backingSize / 2 - labelHeight

        love.graphics.setColor(0, 0, 0, 0.96 * opacity)
        love.graphics.rectangle(
            "fill",
            labelX,
            labelY,
            labelWidth,
            labelHeight
        )
        love.graphics.setColor(1, 1, 1, opacity)
        love.graphics.printf(
            "x" .. tostring(result.stunCount),
            labelX,
            labelY + 2,
            labelWidth,
            "center"
        )
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

local function drawAmmunitionTile()
    local animation = activeAmmunitionAnimation

    if not animation then
        return
    end

    local dropProgress = smoothstep(
        animation.elapsed / AMMO_DROP_DURATION
    )
    local fadeStart = AMMO_DROP_DURATION + AMMO_HOLD_DURATION
    local opacity = animation.elapsed < AMMO_DROP_DURATION
        and dropProgress
        or animation.elapsed <= fadeStart
            and 1
            or 1 - getTimedProgress(
                animation.elapsed,
                fadeStart,
                AMMO_FADE_DURATION
            )
    local entity = animation.entity
    local size = entity.definition.size or 1
    local portraitRadius = BattleMap.HEX_RADIUS
        * (size == 2 and 2.5 or 1)
    local centerX = entity.movementVisualX or entity.anchor.x
    local entityY = entity.movementVisualY or entity.anchor.y
    local targetY = entityY
        - portraitRadius
        - AMMO_TILE_GAP
        - AMMO_TILE_HEIGHT / 2
    local centerY = targetY
        - AMMO_DROP_DISTANCE * (1 - dropProgress)
    local tileX = centerX - AMMO_TILE_WIDTH / 2
    local tileY = centerY - AMMO_TILE_HEIGHT / 2
    local label = ("%d / %d"):format(
        animation.remaining,
        animation.capacity
    )
    local font = love.graphics.getFont()
    local fontWidth = font and font:getWidth(label) or #label * 10
    local fontHeight = font and font:getHeight() or 18
    local icon = getAmmunitionIcon()
    local iconWidth, iconHeight = icon:getDimensions()
    local iconScale = AMMO_ICON_SIZE
        / math.max(iconWidth, iconHeight)
    local contentWidth = fontWidth + AMMO_ROW_GAP + AMMO_ICON_SIZE
    local contentX = centerX - contentWidth / 2

    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 0.94 * opacity)
    love.graphics.rectangle(
        "fill",
        tileX,
        tileY,
        AMMO_TILE_WIDTH,
        AMMO_TILE_HEIGHT
    )
    love.graphics.setColor(1, 1, 1, 0.9 * opacity)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle(
        "line",
        tileX,
        tileY,
        AMMO_TILE_WIDTH,
        AMMO_TILE_HEIGHT
    )
    love.graphics.setColor(
        249 / 255,
        161 / 255,
        0,
        opacity
    )
    love.graphics.print(
        label,
        contentX,
        centerY - fontHeight / 2
    )
    love.graphics.setColor(1, 1, 1, opacity)
    love.graphics.draw(
        icon,
        contentX + fontWidth + AMMO_ROW_GAP
            + AMMO_ICON_SIZE / 2,
        centerY,
        0,
        iconScale,
        iconScale,
        iconWidth / 2,
        iconHeight / 2
    )
    love.graphics.pop()
end

function SteelCombat.draw()
    drawAmmunitionTile()

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

    local stunJitter = getStunJitter(result, elapsed)
    local stunFlashAmount = isApplyingStun(result)
        and 1 - getTimedProgress(
            elapsed,
            IMPACT_TIME,
            STUN_FLASH_DURATION
        )
        or 0

    drawCombatant(
        result.target,
        layout.defenderX + stunJitter,
        layout.centerY,
        layout.combatantSize,
        "defender",
        elapsed,
        fade,
        isKillingResult(result)
            and math.max(0, elapsed - IMPACT_TIME)
            or nil,
        stunFlashAmount
    )
    drawCombatant(
        result.attacker,
        layout.attackerX,
        layout.centerY,
        layout.combatantSize,
        "attacker",
        elapsed,
        fade,
        nil,
        0
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
    drawStunStamp(result, layout, elapsed, fade)
    love.graphics.pop()
end

function SteelCombat.getResolvedRound()
    return resolvedRound
end

return SteelCombat
end

return newCombat
