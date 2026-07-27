local BehaviorLogic = {}

local AGGRO = "aggro"
local SKIRM = "skirm"

local function getAttackValues(definition, attackKey)
    local attack = definition and definition[attackKey]

    if type(attack) ~= "table" then
        return nil
    end

    local maximumRange
    local minimumRange = -1

    for _, entry in ipairs(attack) do
        if type(entry) == "table" then
            if type(entry.rng) == "number"
                and entry.rng == entry.rng
                and entry.rng >= 0
                and entry.rng < math.huge then
                maximumRange = entry.rng
            end

            if type(entry.min_rng) == "number"
                and entry.min_rng == entry.min_rng
                and entry.min_rng >= 0
                and entry.min_rng < math.huge then
                minimumRange = entry.min_rng
            end
        end
    end

    if maximumRange == nil or minimumRange >= maximumRange then
        return nil
    end

    return {
        minimum = minimumRange,
        maximum = maximumRange,
        attackKey = attackKey,
    }
end

local function isFireUsable(entity)
    local ammunition = entity.fireAmmo

    if ammunition == nil then
        ammunition = entity.definition and entity.definition.ammo
    end

    return type(ammunition) == "number" and ammunition > 0
end

local function preferStableCell(left, right)
    return not right or left.cell.key < right.cell.key
end

local function selectAggroCandidate(entity, startingDistance, candidates)
    local best = {
        cell = entity.anchor,
        distance = startingDistance,
        cost = 0,
    }
    local bestDistance = startingDistance
    local bestCost = 0

    for _, candidate in ipairs(candidates) do
        if candidate.distance < bestDistance
            or candidate.distance == bestDistance
                and candidate.cost > bestCost
            or candidate.distance == bestDistance
                and candidate.cost == bestCost
                and preferStableCell(candidate, best) then
            best = candidate
            bestDistance = candidate.distance
            bestCost = candidate.cost
        end
    end

    return best
end

local function selectFurthestCandidate(candidates, predicate)
    local best

    for _, candidate in ipairs(candidates) do
        if predicate(candidate)
            and (
                not best
                or candidate.distance > best.distance
                or candidate.distance == best.distance
                    and preferStableCell(candidate, best)
            ) then
            best = candidate
        end
    end

    return best
end

function BehaviorLogic.get(entity)
    local behavior = entity
        and entity.definition
        and entity.definition.bhav

    if type(behavior) == "string"
        and behavior:lower() == SKIRM then
        return SKIRM
    end

    return AGGRO
end

function BehaviorLogic.getPreferredAttackBand(entity)
    if type(entity) ~= "table" or type(entity.definition) ~= "table" then
        return nil
    end

    local profiles = {}
    local steel = getAttackValues(entity.definition, "steel_atk")

    if steel then
        profiles[#profiles + 1] = steel
    end

    if isFireUsable(entity) then
        local fire = getAttackValues(entity.definition, "fire_atk")

        if fire then
            profiles[#profiles + 1] = fire
        end
    end

    local preferred

    for _, profile in ipairs(profiles) do
        if not preferred
            or profile.maximum > preferred.maximum
            or profile.maximum == preferred.maximum
                and profile.minimum < preferred.minimum then
            preferred = profile
        end
    end

    return preferred
end

-- Candidates contain { cell, distance, cost }. A nil result means that the
-- entity should remain at its current anchor.
function BehaviorLogic.selectMovementCandidate(
    entity,
    startingDistance,
    candidates
)
    if BehaviorLogic.get(entity) ~= SKIRM then
        return selectAggroCandidate(entity, startingDistance, candidates)
    end

    local band = BehaviorLogic.getPreferredAttackBand(entity)

    if not band then
        return selectAggroCandidate(entity, startingDistance, candidates)
    end

    local function isInBand(candidate)
        return candidate.distance > band.minimum
            and candidate.distance <= band.maximum
    end

    if startingDistance > band.maximum then
        local firstInRange = selectFurthestCandidate(
            candidates,
            isInBand
        )

        if firstInRange then
            return firstInRange
        end

        return selectAggroCandidate(entity, startingDistance, candidates)
    end

    if startingDistance > band.minimum then
        return selectFurthestCandidate(candidates, function(candidate)
            return isInBand(candidate)
                and candidate.distance > startingDistance
        end)
    end

    local recoveredRange = selectFurthestCandidate(
        candidates,
        isInBand
    )

    if recoveredRange then
        return recoveredRange
    end

    return selectFurthestCandidate(candidates, function(candidate)
        return candidate.distance > startingDistance
            and candidate.distance <= band.maximum
    end)
end

BehaviorLogic.AGGRO = AGGRO
BehaviorLogic.SKIRM = SKIRM

return BehaviorLogic
