local BattleMap = require("src.sys.battle_map")
local SpawnerLogic = require("src.sys.spawner_logic")
local Sfx = require("src.sys.sfx")
local TurnLogic = require("src.sys.turn_logic")

local PreparationLogic = {}

local LABEL_HEIGHT = 38
local BUTTON_WIDTH = 286
local BUTTON_HEIGHT = 42
local ELEMENT_GAP = 8
local TOP_GAP = 10
local DIM_COLOR = { 0, 0, 0, 0.62 }
local BUTTON_FILL_COLOR = { 0.055, 0.065, 0.085, 0.96 }
local BUTTON_BORDER_COLOR = { 1, 1, 1, 1 }
local BUTTON_TEXT_COLOR = { 1, 1, 1, 1 }

local active = false
local preparationTiles = {}
local draggedAgent

local function isInside(x, y, bounds)
    return x >= bounds.x
        and x <= bounds.x + bounds.width
        and y >= bounds.y
        and y <= bounds.y + bounds.height
end

local function isPreparationCell(cell)
    return cell and preparationTiles[cell.key] == true
end

function PreparationLogic.loadMap(map)
    preparationTiles = {}
    draggedAgent = nil

    for key, flagged in pairs(map and map.preparation_tiles or {}) do
        if flagged then
            preparationTiles[key] = true
        end
    end

    active = next(preparationTiles) ~= nil

    return active
end

function PreparationLogic.isActive()
    return active
end

function PreparationLogic.isPreparationCell(cellOrKey)
    local key = type(cellOrKey) == "table"
        and cellOrKey.key
        or cellOrKey

    return preparationTiles[key] == true
end

function PreparationLogic.getLayout(fateButtonBounds)
    local anchor = fateButtonBounds or {
        x = (love.graphics.getWidth() - 74) / 2,
        y = 12,
        width = 74,
        height = 74,
    }
    local centerX = anchor.x + anchor.width / 2
    local label = {
        x = centerX - BUTTON_WIDTH / 2,
        y = anchor.y + anchor.height + TOP_GAP,
        width = BUTTON_WIDTH,
        height = LABEL_HEIGHT,
    }

    return {
        label = label,
        finish = {
            x = centerX - BUTTON_WIDTH / 2,
            y = label.y + label.height + ELEMENT_GAP,
            width = BUTTON_WIDTH,
            height = BUTTON_HEIGHT,
        },
    }
end

function PreparationLogic.finish()
    if not active then
        return false
    end

    active = false
    draggedAgent = nil
    Sfx.play("prepared")
    TurnLogic.begin()

    return true
end

function PreparationLogic.mousepressed(x, y, button, fateButtonBounds)
    if not active or button ~= 1 then
        return false
    end

    local layout = PreparationLogic.getLayout(fateButtonBounds)

    if isInside(x, y, layout.finish) then
        PreparationLogic.finish()
        return true
    end

    local cell = BattleMap.getHexAt(x, y)
    local entity = cell and SpawnerLogic.getEntityAt(cell)

    if entity and entity.entityType == "AGENT" then
        draggedAgent = entity
        return true
    end

    return cell ~= nil
end

function PreparationLogic.mousemoved(x, y)
    if not active or not draggedAgent then
        return false
    end

    local cell = BattleMap.getHexAt(x, y)

    if not isPreparationCell(cell) then
        return true
    end

    SpawnerLogic.moveAgent(
        draggedAgent,
        cell,
        isPreparationCell
    )

    return true
end

function PreparationLogic.mousereleased(_, _, button)
    if button ~= 1 or not draggedAgent then
        return false
    end

    draggedAgent = nil

    return true
end

function PreparationLogic.drawMapOverlay()
    if not active then
        return
    end

    love.graphics.setColor(DIM_COLOR)

    for _, cell in ipairs(BattleMap.getCells()) do
        if not preparationTiles[cell.key] then
            love.graphics.polygon(
                "fill",
                BattleMap.getHexVertices(cell)
            )
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function PreparationLogic.draw(fateButtonBounds)
    if not active then
        return
    end

    local layout = PreparationLogic.getLayout(fateButtonBounds)
    local font = love.graphics.getFont and love.graphics.getFont()
    local fontHeight = font and font:getHeight() or 18

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(
        "Prepare Your Forces",
        layout.label.x,
        math.floor(
            layout.label.y
                + (layout.label.height - fontHeight) / 2
                + 0.5
        ),
        layout.label.width,
        "center"
    )

    love.graphics.setColor(BUTTON_FILL_COLOR)
    love.graphics.rectangle(
        "fill",
        layout.finish.x,
        layout.finish.y,
        layout.finish.width,
        layout.finish.height,
        4,
        4
    )
    love.graphics.setColor(BUTTON_BORDER_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle(
        "line",
        layout.finish.x,
        layout.finish.y,
        layout.finish.width,
        layout.finish.height,
        4,
        4
    )
    love.graphics.setColor(BUTTON_TEXT_COLOR)
    love.graphics.printf(
        "Finish Preparing",
        layout.finish.x,
        math.floor(
            layout.finish.y
                + (layout.finish.height - fontHeight) / 2
                + 0.5
        ),
        layout.finish.width,
        "center"
    )

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

return PreparationLogic
