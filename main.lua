local function hasArg(name)
    if not arg then
        return false
    end

    for _, value in ipairs(arg) do
        if value == name then
            return true
        end
    end

    return false
end

if hasArg("--portrait-tool") then
    local PortraitEditor = require("tools.hex_portrait_editor")

    function love.load()
        PortraitEditor.load()
    end

    function love.update(dt)
        PortraitEditor.update(dt)
    end

    function love.draw()
        PortraitEditor.draw()
    end

    function love.keypressed(key, scancode, isRepeat)
        PortraitEditor.keypressed(key, scancode, isRepeat)
    end

    function love.mousepressed(x, y, button, isTouch, presses)
        PortraitEditor.mousepressed(x, y, button, isTouch, presses)
    end

    function love.mousereleased(x, y, button, isTouch, presses)
        PortraitEditor.mousereleased(x, y, button, isTouch, presses)
    end

    function love.mousemoved(x, y, dx, dy, isTouch)
        PortraitEditor.mousemoved(x, y, dx, dy, isTouch)
    end

    function love.wheelmoved(x, y)
        PortraitEditor.wheelmoved(x, y)
    end

    return
end

if hasArg("--map-editor") then
    local MapEditor = require("tools.map_editor")

    function love.load()
        MapEditor.load()
    end

    function love.update(dt)
        MapEditor.update(dt)
    end

    function love.draw()
        MapEditor.draw()
    end

    function love.keypressed(key, scancode, isRepeat)
        MapEditor.keypressed(key, scancode, isRepeat)
    end

    function love.textinput(text)
        MapEditor.textinput(text)
    end

    function love.mousepressed(x, y, button, isTouch, presses)
        MapEditor.mousepressed(x, y, button, isTouch, presses)
    end

    function love.mousereleased(x, y, button, isTouch, presses)
        MapEditor.mousereleased(x, y, button, isTouch, presses)
    end

    function love.mousemoved(x, y, dx, dy, isTouch)
        MapEditor.mousemoved(x, y, dx, dy, isTouch)
    end

    function love.quit()
        return MapEditor.quit()
    end

    return
end

local BattleMap = require("src.sys.battle_map")
local GameMap = require("src.sys.game_map")
local SpawnerLogic = require("src.sys.spawner_logic")
local FateLogic = require("src.sys.fate_logic")
local AgencyLogic = require("src.sys.agency_logic")
local TurnLogic = require("src.sys.turn_logic")
local PreparationLogic = require("src.sys.preparation_logic")
local ReflexLogic = require("src.sys.reflex_logic")
local MovementSpdLogic = require("src.sys.movement_spd_logic")
local Controls = require("src.input.controls")

local DEFAULT_FONT_PATH = "assets/fonts/Furore.otf"
local DEFAULT_FONT_SIZE = 18

function love.load()
    love.graphics.setBackgroundColor(0.055, 0.065, 0.09)
    love.graphics.setLineStyle("smooth")
    love.graphics.setFont(
        love.graphics.newFont(DEFAULT_FONT_PATH, DEFAULT_FONT_SIZE)
    )
    TurnLogic.reset()

    local map, mapError = GameMap.loadDevelopmentMap()

    if not map then
        error("Failed to load development map: " .. tostring(mapError))
    end

    local entities, spawnError = SpawnerLogic.loadMap(map)

    if not entities then
        error("Failed to spawn map entities: " .. tostring(spawnError))
    end

    local fateStacks, fateError = FateLogic.loadEntities(entities)

    if not fateStacks then
        error("Failed to load fate stacks: " .. tostring(fateError))
    end

    local agencyStacks, agencyError = AgencyLogic.loadEntities(entities)

    if not agencyStacks then
        error("Failed to load Agency stacks: " .. tostring(agencyError))
    end

    ReflexLogic.reset()
    MovementSpdLogic.reset()
    TurnLogic.setResolutionHandler(function(phase, round)
        if phase == "Reflex" then
            return ReflexLogic.resolveRound(entities, round)
        elseif phase == "March" then
            MovementSpdLogic.beginMarch(entities, round)
            return true
        end

        return true
    end)
    TurnLogic.setResolutionReadyCheck(function(phase)
        if phase == "Reflex" then
            return not ReflexLogic.isAnimating()
        elseif phase == "March" then
            return not MovementSpdLogic.isProcessing()
        end

        return true
    end)

    if not PreparationLogic.loadMap(map) then
        TurnLogic.begin()
    end
end

function love.draw()
    BattleMap.draw(GameMap.getColorMap())
    PreparationLogic.drawMapOverlay()

    if not PreparationLogic.isActive() then
        if MovementSpdLogic.isProcessing() then
            MovementSpdLogic.draw()
        else
            SpawnerLogic.drawMovementOverlay()
        end
    end

    SpawnerLogic.drawEntities()
    ReflexLogic.drawMapEffects()
    BattleMap.drawHover()
    SpawnerLogic.drawInterface()

    if PreparationLogic.isActive() then
        PreparationLogic.draw(FateLogic.getButtonGroupBounds())
    else
        TurnLogic.draw(FateLogic.getButtonGroupBounds())
    end

    ReflexLogic.draw(
        TurnLogic.getRound(),
        FateLogic.getButtonBounds(),
        FateLogic.getHostileButtonBounds()
    )
    FateLogic.draw()
    AgencyLogic.draw()
    Controls.draw()
end

function love.update(dt)
    SpawnerLogic.update(dt)
    ReflexLogic.update(dt)
    MovementSpdLogic.update(dt, SpawnerLogic.getEntities())

    if not PreparationLogic.isActive() then
        TurnLogic.update(dt)
    end
end

function love.keypressed(key, scancode, isRepeat)
    Controls.keypressed(key, scancode, isRepeat)
end

function love.mousepressed(x, y, button, isTouch, presses)
    Controls.mousepressed(x, y, button, isTouch, presses)
end

function love.mousereleased(x, y, button, isTouch, presses)
    Controls.mousereleased(x, y, button, isTouch, presses)
end

function love.mousemoved(x, y, dx, dy, isTouch)
    Controls.mousemoved(x, y, dx, dy, isTouch)
end

function love.wheelmoved(x, y)
    Controls.wheelmoved(x, y)
end
