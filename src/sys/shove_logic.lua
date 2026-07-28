local BattleMap = require("src.sys.battle_map")
local MapPathfindingLogic = require("src.sys.map_pathfinding_logic")
local SpawnerLogic = require("src.sys.spawner_logic")
local TerrainLogic = require("src.sys.terrain_logic")

local ShoveLogic = {}

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

local function getFootprintDistance(leftFootprint, rightFootprint)
    local closest = math.huge

    for _, leftCell in ipairs(leftFootprint or {}) do
        for _, rightCell in ipairs(rightFootprint or {}) do
            local distance, distanceError =
                MapPathfindingLogic.getHexDistance(leftCell, rightCell)

            if distance == nil then
                return nil, distanceError
            end

            closest = math.min(closest, distance)
        end
    end

    if closest == math.huge then
        return nil, "shove participants require map footprints"
    end

    return closest
end

local function getFootprintHazardDamage(footprint)
    local damage

    for _, cell in ipairs(footprint) do
        local cellDamage = TerrainLogic.getHazardDamage(cell)

        if cellDamage ~= nil
            and (damage == nil or cellDamage > damage) then
            damage = cellDamage
        end
    end

    return damage
end

local function footprintHasCover(footprint)
    for _, cell in ipairs(footprint) do
        if TerrainLogic.isCoverCell(cell) then
            return true
        end
    end

    return false
end

function ShoveLogic.getDistance(tile)
    if type(tile) ~= "table" or type(tile.definition) ~= "table" then
        return nil, "a valid Agency tile is required"
    end

    local total = 0

    for _, actionEntry in ipairs(tile.definition.actions or {}) do
        for actionType, value in pairs(actionEntry) do
            if type(actionType) == "string"
                and actionType:lower() == "shove" then
                if type(value) ~= "number"
                    or value ~= value
                    or value == math.huge
                    or value % 1 ~= 0
                    or value < 0 then
                    return nil, (
                        "Agency tile %q has an invalid Shove value"
                    ):format(tostring(tile.id))
                end

                total = total + value
            end
        end
    end

    return total
end

function ShoveLogic.selectDestination(attacker, defender, distance, random)
    if type(attacker) ~= "table" or type(defender) ~= "table" then
        return nil, "shove requires an attacker and defender"
    end

    if type(distance) ~= "number"
        or distance ~= distance
        or distance == math.huge
        or distance % 1 ~= 0
        or distance < 0 then
        return nil, "shove distance must be a non-negative integer"
    end

    if distance == 0 then
        return nil
    end

    local startingAttackerDistance, startingDistanceError =
        getFootprintDistance(attacker.footprint, defender.footprint)

    if startingAttackerDistance == nil then
        return nil, startingDistanceError
    end

    local hazards = {}
    local bestHazardDamage
    local emptyCandidates = {}

    for _, cell in ipairs(BattleMap.getCells()) do
        local shoveDistance, shoveDistanceError =
            MapPathfindingLogic.getHexDistance(defender.anchor, cell)

        if shoveDistance == nil then
            return nil, shoveDistanceError
        end

        if shoveDistance > 0 and shoveDistance <= distance then
            local footprint = SpawnerLogic.canEntityOccupy(defender, cell)

            if footprint and not footprintHasCover(footprint) then
                local attackerDistance, attackerDistanceError =
                    getFootprintDistance(attacker.footprint, footprint)

                if attackerDistance == nil then
                    return nil, attackerDistanceError
                end

                -- A valid landing space must put the defender farther from the
                -- attacker. Intervening cells are intentionally never checked.
                if attackerDistance > startingAttackerDistance then
                    local hazardDamage =
                        getFootprintHazardDamage(footprint)

                    if hazardDamage ~= nil then
                        if bestHazardDamage == nil
                            or hazardDamage > bestHazardDamage then
                            hazards = { cell }
                            bestHazardDamage = hazardDamage
                        elseif hazardDamage == bestHazardDamage then
                            hazards[#hazards + 1] = cell
                        end
                    elseif shoveDistance == distance then
                        emptyCandidates[#emptyCandidates + 1] = {
                            cell = cell,
                            attackerDistance = attackerDistance,
                        }
                    end
                end
            end
        end
    end

    if #hazards > 0 then
        return hazards[getRandomIndex(#hazards, random)], {
            hazard = true,
            hazardDamage = bestHazardDamage,
        }
    end

    if #emptyCandidates == 0 then
        return nil
    end

    -- Prefer the landing that is most directly away from the attacker, then
    -- use the stable map key so non-hazard shoves do not consume randomness.
    table.sort(emptyCandidates, function(left, right)
        if left.attackerDistance ~= right.attackerDistance then
            return left.attackerDistance > right.attackerDistance
        end

        return left.cell.key < right.cell.key
    end)

    return emptyCandidates[1].cell, {
        hazard = false,
        distance = distance,
    }
end

function ShoveLogic.moveTo(defender, distance, destination, selection)
    selection = selection or {}
    local origin = defender.anchor
    local moved, moveError, terrainResult =
        SpawnerLogic.moveEntity(defender, destination)

    if not moved then
        return nil, moveError
    end

    return {
        distance = distance,
        moved = true,
        origin = origin,
        destination = destination,
        hazard = selection.hazard,
        hazardDamage = selection.hazardDamage,
        terrain = terrainResult,
    }
end

function ShoveLogic.resolve(attacker, defender, distance, random)
    local destination, selectionOrError =
        ShoveLogic.selectDestination(attacker, defender, distance, random)

    if not destination then
        if selectionOrError then
            return nil, selectionOrError
        end

        return {
            distance = distance,
            moved = false,
            reason = "no_valid_destination",
        }
    end

    return ShoveLogic.moveTo(
        defender,
        distance,
        destination,
        selectionOrError
    )
end

return ShoveLogic
