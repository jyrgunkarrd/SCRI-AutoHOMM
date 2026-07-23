local EntitiesById = require("data.entities.index")
local BattleMap = require("src.sys.battle_map")
local JACLLogic = require("src.sys.JACL_logic")
local MapData = require("src.sys.map_data")

local SpawnerLogic = {}

local handlers = {
    JACL = JACLLogic,
}

local spawnedEntities = {}
local occupiedCells = {}

local function getHandler(definition)
    local entityType = definition.entity_type
    local handler = handlers[entityType]

    if not handler then
        return nil, (
            "entity %q has unsupported entity_type %q"
        ):format(definition.id, tostring(entityType))
    end

    return handler
end

function SpawnerLogic.loadMap(map)
    local valid, validationError = MapData.validate(map)

    if not valid then
        return nil, validationError
    end

    local nextEntities = {}
    local nextOccupiedCells = {}

    -- Iterating the battle-map cells gives deterministic spawn order.
    for _, spawnerCell in ipairs(BattleMap.getCells()) do
        local targetId = (map.spawners or {})[spawnerCell.key]

        if targetId then
            local definition = EntitiesById[targetId]

            if not definition then
                return nil, (
                    "spawner %s targets unknown entity id %q"
                ):format(spawnerCell.key, targetId)
            end

            local handler, handlerError = getHandler(definition)

            if not handler then
                return nil, (
                    "spawner %s cannot create %q: %s"
                ):format(spawnerCell.key, targetId, handlerError)
            end

            local footprint, footprintError = handler.getFootprint(
                definition,
                spawnerCell
            )

            if not footprint then
                return nil, (
                    "spawner %s cannot create %q: %s"
                ):format(spawnerCell.key, targetId, footprintError)
            end

            for _, cell in ipairs(footprint) do
                local occupant = nextOccupiedCells[cell.key]

                if occupant then
                    return nil, (
                        "spawner %s for %q overlaps %q on hex %s"
                    ):format(
                        spawnerCell.key,
                        targetId,
                        occupant.id,
                        cell.key
                    )
                end
            end

            local entity, spawnError = handler.spawn(
                definition,
                spawnerCell
            )

            if not entity then
                return nil, (
                    "spawner %s cannot create %q: %s"
                ):format(spawnerCell.key, targetId, spawnError)
            end

            entity.spawnerKey = spawnerCell.key
            entity.logic = handler
            nextEntities[#nextEntities + 1] = entity

            for _, cell in ipairs(footprint) do
                nextOccupiedCells[cell.key] = entity
            end
        end
    end

    spawnedEntities = nextEntities
    occupiedCells = nextOccupiedCells

    return spawnedEntities
end

function SpawnerLogic.getEntities()
    return spawnedEntities
end

function SpawnerLogic.getEntityAt(cellOrKey)
    local key = type(cellOrKey) == "table" and cellOrKey.key or cellOrKey

    return occupiedCells[key]
end

function SpawnerLogic.draw()
    for _, entity in ipairs(spawnedEntities) do
        entity.logic.draw(entity)
    end
end

return SpawnerLogic
