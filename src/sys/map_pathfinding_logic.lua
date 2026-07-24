local BattleMap = require("src.sys.battle_map")

local MapPathfindingLogic = {}

-- findPath(start, goal, options) accepts battle-map cells or cell keys.
--
-- Supported options:
--   blocked            Array or key-set of impassable cells.
--   isBlocked(cell)    Dynamic occupancy callback.
--   allowBlockedGoal   Permits the final cell even when blocked.
--   getCost(from, to)  Positive traversal-cost callback.
--   heuristic(cell, goal)
--                      Optional finite, non-negative A* heuristic.
--   minimumStepCost    Scales the default hex-distance heuristic when using
--                      custom costs. Defaults to zero for custom costs.
--   includeStart       Set false to omit the starting cell from the result.
--   maxIterations      Positive search-iteration safety limit.
--
-- Success returns path, totalCost. Failure returns nil, errorMessage.
--
-- getReachableCells(start, movementPoints, options) supports blocked,
-- isBlocked, getCost, includeStart, and maxIterations. It returns an ordered
-- cell array plus a key-to-cost table.

local function resolveCell(cellOrKey)
    if type(cellOrKey) == "table" then
        if type(cellOrKey.key) ~= "string" then
            return nil
        end

        return BattleMap.getCellByKey(cellOrKey.key)
    end

    if type(cellOrKey) == "string" then
        return BattleMap.getCellByKey(cellOrKey)
    end
end

local function offsetToAxial(cell)
    return cell.column - (cell.row - cell.row % 2) / 2, cell.row
end

function MapPathfindingLogic.getHexDistance(leftCellOrKey, rightCellOrKey)
    local left = resolveCell(leftCellOrKey)
    local right = resolveCell(rightCellOrKey)

    if not left or not right then
        return nil, "hex distance requires two valid battle-map cells"
    end

    local leftQ, leftR = offsetToAxial(left)
    local rightQ, rightR = offsetToAxial(right)
    local deltaQ = leftQ - rightQ
    local deltaR = leftR - rightR

    return (
        math.abs(deltaQ)
            + math.abs(deltaR)
            + math.abs(deltaQ + deltaR)
    ) / 2
end

local function normalizeBlockedCells(blocked)
    local blockedByKey = {}

    if type(blocked) ~= "table" then
        return blockedByKey
    end

    for key, value in pairs(blocked) do
        if type(key) == "number" then
            local cell = resolveCell(value)

            if cell then
                blockedByKey[cell.key] = true
            end
        elseif value then
            local cell = resolveCell(key)

            if cell then
                blockedByKey[cell.key] = true
            end
        end
    end

    return blockedByKey
end

local function newMinHeap()
    return {
        items = {},
        sequence = 0,
    }
end

local function hasHigherPriority(left, right)
    if left.priority ~= right.priority then
        return left.priority < right.priority
    end

    if left.heuristic ~= right.heuristic then
        return left.heuristic < right.heuristic
    end

    return left.sequence < right.sequence
end

local function heapPush(heap, cell, priority, heuristic, cost)
    heap.sequence = heap.sequence + 1

    local item = {
        cell = cell,
        priority = priority,
        heuristic = heuristic,
        cost = cost,
        sequence = heap.sequence,
    }
    local items = heap.items
    local index = #items + 1

    items[index] = item

    while index > 1 do
        local parentIndex = math.floor(index / 2)

        if hasHigherPriority(items[parentIndex], item) then
            break
        end

        items[index] = items[parentIndex]
        index = parentIndex
        items[index] = item
    end
end

local function heapPop(heap)
    local items = heap.items

    if #items == 0 then
        return nil
    end

    local first = items[1]
    local last = table.remove(items)

    if #items == 0 then
        return first
    end

    local index = 1
    items[1] = last

    while true do
        local leftIndex = index * 2
        local rightIndex = leftIndex + 1
        local bestIndex = index

        if leftIndex <= #items
            and hasHigherPriority(items[leftIndex], items[bestIndex]) then
            bestIndex = leftIndex
        end

        if rightIndex <= #items
            and hasHigherPriority(items[rightIndex], items[bestIndex]) then
            bestIndex = rightIndex
        end

        if bestIndex == index then
            break
        end

        items[index], items[bestIndex] = items[bestIndex], items[index]
        index = bestIndex
    end

    return first
end

local function reconstructPath(cameFrom, goal)
    local reversed = { goal }
    local current = goal

    while cameFrom[current.key] do
        current = cameFrom[current.key]
        reversed[#reversed + 1] = current
    end

    local path = {}

    for index = #reversed, 1, -1 do
        path[#path + 1] = reversed[index]
    end

    return path
end

local function isFinitePositiveNumber(value)
    return type(value) == "number"
        and value > 0
        and value < math.huge
        and value == value
end

function MapPathfindingLogic.findPath(startCellOrKey, goalCellOrKey, options)
    options = options or {}

    if type(options) ~= "table" then
        return nil, "path options must be a table"
    end

    local start = resolveCell(startCellOrKey)

    if not start then
        return nil, "path start is not a valid battle-map cell"
    end

    local goal = resolveCell(goalCellOrKey)

    if not goal then
        return nil, "path goal is not a valid battle-map cell"
    end

    if start == goal then
        if options.includeStart == false then
            return {}, 0
        end

        return { start }, 0
    end

    local blockedByKey = normalizeBlockedCells(options.blocked)
    local isBlockedCallback = options.isBlocked
    local getCost = options.getCost
    local heuristicCallback = options.heuristic
    local minimumStepCost = options.minimumStepCost

    if minimumStepCost == nil then
        minimumStepCost = type(getCost) == "function" and 0 or 1
    end

    if type(minimumStepCost) ~= "number"
        or minimumStepCost < 0
        or minimumStepCost == math.huge
        or minimumStepCost ~= minimumStepCost then
        return nil, "minimumStepCost must be a finite non-negative number"
    end

    local maxIterations = options.maxIterations
        or #BattleMap.getCells() * 8

    if type(maxIterations) ~= "number"
        or maxIterations % 1 ~= 0
        or maxIterations < 1 then
        return nil, "maxIterations must be a positive integer"
    end

    local function isBlocked(cell)
        if cell == start then
            return false
        end

        if cell == goal and options.allowBlockedGoal then
            return false
        end

        if blockedByKey[cell.key] then
            return true
        end

        return type(isBlockedCallback) == "function"
            and isBlockedCallback(cell)
            or false
    end

    if isBlocked(goal) then
        return nil, "path goal is blocked"
    end

    local function getHeuristic(cell)
        local value

        if type(heuristicCallback) == "function" then
            value = heuristicCallback(cell, goal)
        else
            value = MapPathfindingLogic.getHexDistance(cell, goal)
                * minimumStepCost
        end

        if type(value) ~= "number"
            or value < 0
            or value == math.huge
            or value ~= value then
            return nil
        end

        return value
    end

    local initialHeuristic = getHeuristic(start)

    if not initialHeuristic then
        return nil, "path heuristic must return a finite non-negative number"
    end

    local frontier = newMinHeap()
    local cameFrom = {}
    local costs = {
        [start.key] = 0,
    }
    local iterations = 0

    heapPush(
        frontier,
        start,
        initialHeuristic,
        initialHeuristic,
        0
    )

    while #frontier.items > 0 do
        iterations = iterations + 1

        if iterations > maxIterations then
            return nil, "path search exceeded maxIterations"
        end

        local currentItem = heapPop(frontier)
        local current = currentItem.cell
        local knownCost = costs[current.key]

        -- Multiple heap entries may exist for a cell. Ignore stale ones.
        if currentItem.cost == knownCost then
            if current == goal then
                local path = reconstructPath(cameFrom, goal)

                if options.includeStart == false then
                    table.remove(path, 1)
                end

                return path, knownCost
            end

            for _, neighbor in ipairs(BattleMap.getNeighbors(current)) do
                if not isBlocked(neighbor) then
                    local stepCost = type(getCost) == "function"
                        and getCost(current, neighbor)
                        or 1

                    if not isFinitePositiveNumber(stepCost) then
                        return nil, (
                            "path cost from %s to %s must be a finite positive number"
                        ):format(current.key, neighbor.key)
                    end

                    local nextCost = knownCost + stepCost
                    local previousCost = costs[neighbor.key]

                    if not previousCost or nextCost < previousCost then
                        local heuristic = getHeuristic(neighbor)

                        if not heuristic then
                            return nil, (
                                "path heuristic must return a finite non-negative number"
                            )
                        end

                        costs[neighbor.key] = nextCost
                        cameFrom[neighbor.key] = current
                        heapPush(
                            frontier,
                            neighbor,
                            nextCost + heuristic,
                            heuristic,
                            nextCost
                        )
                    end
                end
            end
        end
    end

    return nil, "no path exists between the requested cells"
end

function MapPathfindingLogic.getReachableCells(
    startCellOrKey,
    movementPoints,
    options
)
    options = options or {}

    if type(options) ~= "table" then
        return nil, "reachable-area options must be a table"
    end

    local start = resolveCell(startCellOrKey)

    if not start then
        return nil, "reachable-area start is not a valid battle-map cell"
    end

    if type(movementPoints) ~= "number"
        or movementPoints < 0
        or movementPoints == math.huge
        or movementPoints ~= movementPoints then
        return nil, "movementPoints must be a finite non-negative number"
    end

    local blockedByKey = normalizeBlockedCells(options.blocked)
    local isBlockedCallback = options.isBlocked
    local getCost = options.getCost
    local maxIterations = options.maxIterations
        or #BattleMap.getCells() * 8

    if type(maxIterations) ~= "number"
        or maxIterations % 1 ~= 0
        or maxIterations < 1 then
        return nil, "maxIterations must be a positive integer"
    end

    local function isBlocked(cell)
        if cell == start then
            return false
        end

        if blockedByKey[cell.key] then
            return true
        end

        return type(isBlockedCallback) == "function"
            and isBlockedCallback(cell)
            or false
    end

    local frontier = newMinHeap()
    local costs = {
        [start.key] = 0,
    }
    local reachable = {}
    local iterations = 0

    heapPush(frontier, start, 0, 0, 0)

    while #frontier.items > 0 do
        iterations = iterations + 1

        if iterations > maxIterations then
            return nil, "reachable-area search exceeded maxIterations"
        end

        local currentItem = heapPop(frontier)
        local current = currentItem.cell
        local knownCost = costs[current.key]

        if currentItem.cost == knownCost then
            if current ~= start or options.includeStart ~= false then
                reachable[#reachable + 1] = current
            end

            for _, neighbor in ipairs(BattleMap.getNeighbors(current)) do
                if not isBlocked(neighbor) then
                    local stepCost = type(getCost) == "function"
                        and getCost(current, neighbor)
                        or 1

                    if not isFinitePositiveNumber(stepCost) then
                        return nil, (
                            "reachable-area cost from %s to %s must be a finite positive number"
                        ):format(current.key, neighbor.key)
                    end

                    local nextCost = knownCost + stepCost
                    local previousCost = costs[neighbor.key]

                    if nextCost <= movementPoints
                        and (not previousCost or nextCost < previousCost) then
                        costs[neighbor.key] = nextCost
                        heapPush(
                            frontier,
                            neighbor,
                            nextCost,
                            0,
                            nextCost
                        )
                    end
                end
            end
        end
    end

    return reachable, costs
end

return MapPathfindingLogic
