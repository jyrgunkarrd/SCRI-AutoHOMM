local EntitiesById = require("data.entities.index")
local BattleMap = require("src.sys.battle_map")
local JACLLogic = require("src.sys.JACL_logic")
local AgentLogic = require("src.sys.agent_logic")
local HostilesLogic = require("src.sys.hostiles_logic")
local MapData = require("src.sys.map_data")

local SpawnerLogic = {}

local handlers = {
    JACL = JACLLogic,
    AGENT = AgentLogic,
    HOSTILE = HostilesLogic,
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
    AgentLogic.deselect()

    return spawnedEntities
end

function SpawnerLogic.getEntities()
    return spawnedEntities
end

function SpawnerLogic.getEntityAt(cellOrKey)
    local key = type(cellOrKey) == "table" and cellOrKey.key or cellOrKey

    return occupiedCells[key]
end

function SpawnerLogic.moveAgent(entity, anchorCell, cellAllowed)
    if not entity or entity.entityType ~= "AGENT" then
        return nil, "only Agent entities can be moved during Preparation"
    end

    if not anchorCell then
        return nil, "Agent destination must be a valid hex"
    end

    local isSpawned = false

    for _, spawnedEntity in ipairs(spawnedEntities) do
        if spawnedEntity == entity then
            isSpawned = true
            break
        end
    end

    if not isSpawned then
        return nil, "Agent is not part of the loaded map"
    end

    local footprint, footprintError = entity.logic.getFootprint(
        entity.definition,
        anchorCell
    )

    if not footprint then
        return nil, footprintError
    end

    for _, cell in ipairs(footprint) do
        if cellAllowed and not cellAllowed(cell) then
            return nil, "Agent footprint must remain on Preparation hexes"
        end

        local occupant = occupiedCells[cell.key]

        if occupant and occupant ~= entity then
            return nil, (
                "destination hex %s is occupied by %q"
            ):format(cell.key, occupant.id)
        end
    end

    for _, cell in ipairs(entity.footprint) do
        if occupiedCells[cell.key] == entity then
            occupiedCells[cell.key] = nil
        end
    end

    entity.anchor = anchorCell
    entity.footprint = footprint

    for _, cell in ipairs(footprint) do
        occupiedCells[cell.key] = entity
    end

    return true
end

function SpawnerLogic.drawEntities()
    for _, entity in ipairs(spawnedEntities) do
        entity.logic.draw(entity)
    end
end

function SpawnerLogic.drawMovementOverlay()
    AgentLogic.drawMovementOverlay()
end

function SpawnerLogic.drawInterface()
    AgentLogic.drawSelectionOverlay()
    AgentLogic.drawProfilePanel()
end

function SpawnerLogic.draw()
    SpawnerLogic.drawEntities()
    SpawnerLogic.drawInterface()
end

function SpawnerLogic.update(dt)
    AgentLogic.update(dt)
end

function SpawnerLogic.mousepressed(x, y, button)
    if button == 2 then
        return AgentLogic.deselect()
    end

    if button ~= 1 then
        return false
    end

    local cell = BattleMap.getHexAt(x, y)
    local entity = cell and occupiedCells[cell.key]

    if entity
        and (entity.entityType == "AGENT"
            or entity.entityType == "HOSTILE") then
        return AgentLogic.select(entity)
    end

    return false
end

function SpawnerLogic.getSelectedAgent()
    return AgentLogic.getSelected()
end

function SpawnerLogic.getAgencyButtonBounds()
    return AgentLogic.getAgencyButtonBounds()
end

return SpawnerLogic
