local BattleMap = require("src.sys.battle_map")
local MapPathfindingLogic = require("src.sys.map_pathfinding_logic")
local ReflexLogic = require("src.sys.reflex_logic")
local SpawnerLogic = require("src.sys.spawner_logic")

local MovementSpdLogic = {}

local PREVIEW_DURATION = 0.45
local MOVE_BASE_DURATION = 0.22
local MOVE_DURATION_PER_HEX = 0.18
local GHOST_OPACITY = 0.38
local OVERLAY_OUTLINE_WIDTH = 2
local TOKEN_OUTLINE_WIDTH = 4
local PORTRAIT_DIAMETER_IN_HEX_RADII = {
    [1] = 2,
    [2] = 5,
}

local COLORS = {
    agentFill = { 1, 1, 1, 0.22 },
    hostileFill = { 1, 0, 73 / 255, 0.28 },
    outline = { 0, 0, 0, 0.9 },
    path = { 1, 1, 1, 0.9 },
}

local phaseQueue = {}
local currentAction
local actionIndex = 0
local processing = false
local resolvedRound

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

local function getFootprintDistance(leftFootprint, rightFootprint)
    local closest = math.huge

    for _, leftCell in ipairs(leftFootprint) do
        for _, rightCell in ipairs(rightFootprint) do
            local distance = MapPathfindingLogic.getHexDistance(
                leftCell,
                rightCell
            )

            closest = math.min(closest, distance)
        end
    end

    return closest
end

local function isInOpposingZoneOfControl(entity)
    for _, occupiedCell in ipairs(entity.footprint) do
        for _, neighbor in ipairs(BattleMap.getNeighbors(occupiedCell)) do
            local occupant = SpawnerLogic.getEntityAt(neighbor)

            if isOpponent(entity, occupant) then
                return true
            end
        end
    end

    return false
end

local function getClosestOpponent(entity, entities)
    local closest
    local closestDistance = math.huge

    for _, candidate in ipairs(entities) do
        if isOpponent(entity, candidate) then
            local distance = getFootprintDistance(
                entity.footprint,
                candidate.footprint
            )

            if distance < closestDistance
                or distance == closestDistance
                    and (
                        not closest
                        or candidate.id < closest.id
                    ) then
                closest = candidate
                closestDistance = distance
            end
        end
    end

    return closest, closestDistance
end

local function canOccupy(entity, cell)
    return SpawnerLogic.canEntityOccupy(entity, cell) ~= nil
end

local function selectDestination(entity, target, speed)
    if speed <= 0 then
        return entity.anchor, { entity.anchor }, {}
    end

    local startingDistance = getFootprintDistance(
        entity.footprint,
        target.footprint
    )

    if startingDistance <= 1 then
        return entity.anchor, { entity.anchor }, {}
    end

    local reachable, costs = MapPathfindingLogic.getReachableCells(
        entity.anchor,
        speed,
        {
            includeStart = true,
            isBlocked = function(cell)
                return not canOccupy(entity, cell)
            end,
        }
    )

    if not reachable then
        return entity.anchor, { entity.anchor }, {}
    end

    local destination = entity.anchor
    local bestDistance = startingDistance
    local bestCost = 0

    for _, cell in ipairs(reachable) do
        local footprint = SpawnerLogic.canEntityOccupy(entity, cell)

        if footprint then
            local distance = getFootprintDistance(
                footprint,
                target.footprint
            )
            local cost = costs[cell.key] or 0

            if distance < bestDistance
                or distance == bestDistance and cost > bestCost
                or distance == bestDistance
                    and cost == bestCost
                    and cell.key < destination.key then
                destination = cell
                bestDistance = distance
                bestCost = cost
            end
        end
    end

    local path = { entity.anchor }

    if destination ~= entity.anchor then
        path = MapPathfindingLogic.findPath(
            entity.anchor,
            destination,
            {
                includeStart = true,
                isBlocked = function(cell)
                    return not canOccupy(entity, cell)
                end,
            }
        ) or path
    end

    return destination, path, reachable
end

local function clearMovementVisual(entity)
    if not entity then
        return
    end

    entity.movementVisualX = nil
    entity.movementVisualY = nil
end

local function finishProcessing()
    if currentAction then
        clearMovementVisual(currentAction.entity)
    end

    currentAction = nil
    processing = false
    ReflexLogic.setPhaseActiveEntry(nil)
end

local function prepareNextAction(entities)
    while processing do
        actionIndex = actionIndex + 1

        local entry = phaseQueue[actionIndex]

        if not entry then
            finishProcessing()
            return false
        end

        local entity = entry.entity
        local target = getClosestOpponent(entity, entities)

        ReflexLogic.setPhaseActiveEntry(entry)

        if target then
            local speed = math.max(0, math.floor(getStat(entity, "spd")))
            local destination, path, reachable = selectDestination(
                entity,
                target,
                speed
            )

            if destination ~= entity.anchor and #path > 1 then
                currentAction = {
                    entry = entry,
                    entity = entity,
                    target = target,
                    origin = entity.anchor,
                    destination = destination,
                    path = path,
                    reachable = reachable,
                    state = "preview",
                    elapsed = 0,
                    moveDuration = MOVE_BASE_DURATION
                        + (#path - 1) * MOVE_DURATION_PER_HEX,
                }

                return true
            end
        end
    end

    return false
end

local function updateMovingPosition(action)
    local path = action.path
    local segmentCount = #path - 1
    local progress = math.min(
        1,
        action.elapsed / action.moveDuration
    )
    local pathProgress = progress * segmentCount
    local segmentIndex = math.min(
        segmentCount,
        math.floor(pathProgress) + 1
    )
    local segmentProgress = pathProgress - (segmentIndex - 1)

    if progress >= 1 then
        segmentIndex = segmentCount
        segmentProgress = 1
    end

    segmentProgress = segmentProgress
        * segmentProgress
        * (3 - 2 * segmentProgress)

    local from = path[segmentIndex]
    local to = path[segmentIndex + 1]

    action.entity.movementVisualX = from.x
        + (to.x - from.x) * segmentProgress
    action.entity.movementVisualY = from.y
        + (to.y - from.y) * segmentProgress
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

local function drawGhost(action, opacity)
    local entity = action.entity
    local destination = action.destination
    local footprint = SpawnerLogic.canEntityOccupy(entity, destination)

    if not footprint then
        return
    end

    love.graphics.stencil(function()
        for _, cell in ipairs(footprint) do
            love.graphics.polygon(
                "fill",
                BattleMap.getHexVertices(cell)
            )
        end
    end, "replace", 1)

    love.graphics.setStencilTest("equal", 1)

    local imageWidth, imageHeight = entity.portrait:getDimensions()
    local diameter = BattleMap.HEX_RADIUS
        * PORTRAIT_DIAMETER_IN_HEX_RADII[entity.definition.size]
    local scale = diameter / math.max(imageWidth, imageHeight)

    love.graphics.setColor(1, 1, 1, opacity)
    love.graphics.draw(
        entity.portrait,
        destination.x,
        destination.y,
        0,
        scale,
        scale,
        imageWidth / 2,
        imageHeight / 2
    )
    love.graphics.setStencilTest()
    love.graphics.setColor(0, 0, 0, opacity)
    love.graphics.setLineWidth(TOKEN_OUTLINE_WIDTH)
    love.graphics.polygon(
        "line",
        buildHexPoints(
            destination.x,
            destination.y,
            diameter / 2 - TOKEN_OUTLINE_WIDTH / 2
        )
    )
end

function MovementSpdLogic.reset()
    if currentAction then
        clearMovementVisual(currentAction.entity)
    end

    phaseQueue = {}
    currentAction = nil
    actionIndex = 0
    processing = false
    resolvedRound = nil
    ReflexLogic.setPhaseActiveEntry(nil)
end

function MovementSpdLogic.beginMarch(entities, round)
    MovementSpdLogic.reset()
    resolvedRound = round

    local blockedByZoneOfControl = {}

    for _, entity in ipairs(entities or {}) do
        if entity.entityType == "AGENT"
            or entity.entityType == "HOSTILE" then
            blockedByZoneOfControl[entity] =
                isInOpposingZoneOfControl(entity)
        end
    end

    for _, entry in ipairs(ReflexLogic.getInitiativeSequence()) do
        if not blockedByZoneOfControl[entry.entity] then
            phaseQueue[#phaseQueue + 1] = entry
        end
    end

    processing = true
    prepareNextAction(entities)

    return phaseQueue
end

function MovementSpdLogic.isProcessing()
    return processing
end

function MovementSpdLogic.getPhaseQueue()
    return phaseQueue
end

function MovementSpdLogic.getCurrentAction()
    return currentAction
end

function MovementSpdLogic.getResolvedRound()
    return resolvedRound
end

function MovementSpdLogic.update(dt, entities)
    if not processing or not currentAction then
        return
    end

    dt = math.max(0, tonumber(dt) or 0)

    while processing and currentAction do
        local action = currentAction
        local duration = action.state == "preview"
            and PREVIEW_DURATION
            or action.moveDuration
        local remaining = duration - action.elapsed
        local step = math.min(dt, remaining)

        action.elapsed = action.elapsed + step
        dt = dt - step

        if action.state == "moving" then
            updateMovingPosition(action)
        end

        if action.elapsed >= duration then
            if action.state == "preview" then
                action.state = "moving"
                action.elapsed = 0
                action.entity.movementVisualX = action.origin.x
                action.entity.movementVisualY = action.origin.y
            else
                clearMovementVisual(action.entity)
                SpawnerLogic.moveEntity(
                    action.entity,
                    action.destination
                )
                currentAction = nil
                prepareNextAction(entities)
            end
        else
            break
        end

        if dt <= 0 then
            break
        end
    end
end

function MovementSpdLogic.draw()
    local action = currentAction

    if not action then
        return
    end

    local fillColor = action.entity.entityType == "HOSTILE"
        and COLORS.hostileFill
        or COLORS.agentFill
    local movingProgress = action.state == "moving"
        and math.min(1, action.elapsed / action.moveDuration)
        or 0
    local treatmentAlpha = 1 - movingProgress * 0.55

    love.graphics.setColor(
        fillColor[1],
        fillColor[2],
        fillColor[3],
        fillColor[4] * treatmentAlpha
    )

    for _, cell in ipairs(action.reachable) do
        if cell ~= action.origin then
            love.graphics.polygon(
                "fill",
                BattleMap.getHexVertices(cell)
            )
        end
    end

    love.graphics.setColor(
        COLORS.outline[1],
        COLORS.outline[2],
        COLORS.outline[3],
        COLORS.outline[4] * treatmentAlpha
    )
    love.graphics.setLineWidth(OVERLAY_OUTLINE_WIDTH)

    for _, cell in ipairs(action.reachable) do
        if cell ~= action.origin then
            love.graphics.polygon(
                "line",
                BattleMap.getHexVertices(cell)
            )
        end
    end

    love.graphics.setColor(
        COLORS.path[1],
        COLORS.path[2],
        COLORS.path[3],
        COLORS.path[4] * treatmentAlpha
    )
    love.graphics.setLineWidth(3)
    love.graphics.line(
        action.origin.x,
        action.origin.y,
        action.destination.x,
        action.destination.y
    )
    drawGhost(
        action,
        GHOST_OPACITY * treatmentAlpha
    )

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

return MovementSpdLogic
