local AgencyLogic = require("src.sys.agency_logic")
local BattleMap = require("src.sys.battle_map")
local ConditionLogic = require("src.sys.condition_logic")
local Controls = require("src.input.controls")
local FateLogic = require("src.sys.fate_logic")
local FireCombat = require("src.sys.fire_combat")
local GameMap = require("src.sys.game_map")
local GlanceTooltips = require("src.sys.glance_tooltips")
local HealthLogic = require("src.sys.health_logic")
local ImageLoader = require("src.assets.image_loader")
local MovementSpdLogic = require("src.sys.movement_spd_logic")
local PreparationLogic = require("src.sys.preparation_logic")
local ReflexLogic = require("src.sys.reflex_logic")
local SpawnerLogic = require("src.sys.spawner_logic")
local StartLogic = require("src.sys.start_logic")
local SteelCombat = require("src.sys.steel_combat")
local TerrainLogic = require("src.sys.terrain_logic")
local TurnLogic = require("src.sys.turn_logic")

local AgentDefinitions = require("data.entities.agents")

local GameStates = {}

local DEFAULT_FONT_PATH = "assets/fonts/Furore.otf"
local DEFAULT_FONT_SIZE = 18
local INITIAL_STATE = "The Draft"
local DRAFT_CHOICE_COUNT = 3
local AGENT_IMAGE_DIRECTORY = "assets/images/agents"
local DRAFT_BACKGROUND_COLOR = { 0.035, 0.04, 0.06, 1 }
local DRAFT_PANEL_COLOR = { 0.075, 0.085, 0.115, 1 }
local DRAFT_PANEL_BORDER_COLOR = { 0.72, 0.76, 0.84, 1 }
local DRAFT_TITLE_COLOR = { 0.93, 0.88, 0.72, 1 }
local DRAFT_SIDE_MARGIN = 96
local DRAFT_PANEL_GAP = 42
local DRAFT_TOP_MARGIN = 150
local DRAFT_BOTTOM_MARGIN = 90
local DRAFT_PANEL_PADDING = 16
local DRAFT_PANEL_CORNER_RADIUS = 12
local DRAFT_PANEL_DROP_DISTANCE = 46
local DRAFT_PANEL_DROP_DURATION = 0.24
local DRAFT_PANEL_DROP_DELAY = 0.09

local states = {}
local currentState
local currentStateName

local BattleMapState = {}

function BattleMapState.load()
    love.graphics.setBackgroundColor(0.055, 0.065, 0.09)
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
    SteelCombat.reset()
    FireCombat.reset()
    local ammunitionInitialized, ammunitionError =
        FireCombat.initializeAmmunition(entities, true)

    if not ammunitionInitialized then
        error("Failed to initialize ammunition: " .. tostring(ammunitionError))
    end

    HealthLogic.setDeathHandler(function(entity)
        ReflexLogic.removeEntity(entity)
        MovementSpdLogic.removeEntity(entity)
        SteelCombat.removeEntity(entity)
        FireCombat.removeEntity(entity)
    end)
    TurnLogic.setResolutionHandler(function(phase, round)
        SpawnerLogic.deselect()

        if phase == "Start" then
            return StartLogic.resolve(entities)
        elseif phase == "Reflex" then
            return ReflexLogic.resolveRound(entities, round)
        elseif phase == "March" then
            MovementSpdLogic.beginMarch(entities, round)
            return true
        elseif phase == "Steel" then
            return SteelCombat.beginSteel(entities, round)
        elseif phase == "Fire" then
            return FireCombat.beginFire(entities, round)
        end

        return true
    end)
    TurnLogic.setResolutionReadyCheck(function(phase)
        if phase == "Reflex" then
            return not ReflexLogic.isAnimating()
        elseif phase == "March" then
            return not MovementSpdLogic.isProcessing()
        elseif phase == "Steel" then
            return not SteelCombat.isProcessing()
        elseif phase == "Fire" then
            return not FireCombat.isProcessing()
        end

        return true
    end)
    TurnLogic.setCleanupHandler(function(phase)
        if phase == "End" then
            MovementSpdLogic.reset()
            SteelCombat.reset()
            FireCombat.reset()
            return ReflexLogic.clearInitiativeSequence()
        end

        ReflexLogic.repopulateInitiativeSequence()
        return true
    end)

    if not PreparationLogic.loadMap(map) then
        TurnLogic.begin()
    end
end

function BattleMapState.draw()
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
    TerrainLogic.drawTooltip()
    ConditionLogic.draw(SpawnerLogic.getEntities())
    GlanceTooltips.draw(SpawnerLogic.getEntities())
    SteelCombat.draw()
    FireCombat.draw()
    Controls.draw()
end

function BattleMapState.update(dt)
    SpawnerLogic.update(dt)
    ReflexLogic.update(dt)
    MovementSpdLogic.update(dt, SpawnerLogic.getEntities())
    SteelCombat.update(dt)
    FireCombat.update(dt)

    if not PreparationLogic.isActive() then
        TurnLogic.update(dt)
    end
end

function BattleMapState.keypressed(key, scancode, isRepeat)
    Controls.keypressed(key, scancode, isRepeat)
end

function BattleMapState.mousepressed(x, y, button, isTouch, presses)
    Controls.mousepressed(x, y, button, isTouch, presses)
end

function BattleMapState.mousereleased(x, y, button, isTouch, presses)
    Controls.mousereleased(x, y, button, isTouch, presses)
end

function BattleMapState.mousemoved(x, y, dx, dy, isTouch)
    Controls.mousemoved(x, y, dx, dy, isTouch)
end

function BattleMapState.wheelmoved(x, y)
    Controls.wheelmoved(x, y)
end

local DraftState = {
    choices = {},
    titleFont = nil,
    animationElapsed = 0,
}

local function hasCaptainTag(definition)
    if definition.entity_type ~= "AGENT" then
        return false
    end

    for _, tag in ipairs(definition.spec_tag or {}) do
        if type(tag) == "string" and tag:lower() == "captain" then
            return true
        end
    end

    return false
end

local function getAgentImagePath(definition)
    if not definition.id:match("^[%w_%-]+$") then
        return nil
    end

    return ("%s/%s.webp"):format(
        AGENT_IMAGE_DIRECTORY,
        definition.id
    )
end

local function getCaptainDefinitionsWithImages()
    local captains = {}

    for _, definition in ipairs(AgentDefinitions) do
        local imagePath = getAgentImagePath(definition)

        if hasCaptainTag(definition)
            and imagePath
            and love.filesystem.getInfo(imagePath, "file") then
            captains[#captains + 1] = {
                definition = definition,
                imagePath = imagePath,
            }
        end
    end

    return captains
end

local function shuffle(items)
    for index = #items, 2, -1 do
        local otherIndex = love.math.random(index)

        items[index], items[otherIndex] = items[otherIndex], items[index]
    end
end

function DraftState.load()
    love.graphics.setBackgroundColor(DRAFT_BACKGROUND_COLOR)
    Controls.closeExitPrompt()
    DraftState.choices = {}
    DraftState.titleFont = love.graphics.newFont(DEFAULT_FONT_PATH, 36)
    DraftState.animationElapsed = 0

    local captains = getCaptainDefinitionsWithImages()

    if #captains < DRAFT_CHOICE_COUNT then
        error((
            "The Draft requires %d captain-tagged Agents with images; found %d"
        ):format(DRAFT_CHOICE_COUNT, #captains))
    end

    shuffle(captains)

    for index = 1, DRAFT_CHOICE_COUNT do
        local choice = captains[index]
        local loaded, image = pcall(
            ImageLoader.newImage,
            choice.imagePath
        )

        if not loaded then
            error((
                "Unable to load draft image for Agent %q from %s: %s"
            ):format(
                choice.definition.id,
                choice.imagePath,
                tostring(image)
            ))
        end

        DraftState.choices[index] = {
            definition = choice.definition,
            image = image,
        }
    end
end

function DraftState.update(dt)
    DraftState.animationElapsed = DraftState.animationElapsed
        + math.max(dt, 0)
end

local function setColorWithOpacity(color, opacity)
    love.graphics.setColor(
        color[1],
        color[2],
        color[3],
        color[4] * opacity
    )
end

local function drawDraftPanel(choice, x, y, width, height, opacity)
    setColorWithOpacity(DRAFT_PANEL_COLOR, opacity)
    love.graphics.rectangle(
        "fill",
        x,
        y,
        width,
        height,
        DRAFT_PANEL_CORNER_RADIUS,
        DRAFT_PANEL_CORNER_RADIUS
    )

    local imageX = x + DRAFT_PANEL_PADDING
    local imageY = y + DRAFT_PANEL_PADDING
    local imageWidth = width - DRAFT_PANEL_PADDING * 2
    local imageHeight = height - DRAFT_PANEL_PADDING * 2
    local sourceWidth, sourceHeight = choice.image:getDimensions()
    local scale = math.min(
        imageWidth / sourceWidth,
        imageHeight / sourceHeight
    )
    local drawWidth = sourceWidth * scale
    local drawHeight = sourceHeight * scale

    love.graphics.setColor(1, 1, 1, opacity)
    love.graphics.draw(
        choice.image,
        imageX + (imageWidth - drawWidth) / 2,
        imageY + (imageHeight - drawHeight) / 2,
        0,
        scale,
        scale
    )

    setColorWithOpacity(DRAFT_PANEL_BORDER_COLOR, opacity)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle(
        "line",
        x,
        y,
        width,
        height,
        DRAFT_PANEL_CORNER_RADIUS,
        DRAFT_PANEL_CORNER_RADIUS
    )
end

function DraftState.draw()
    love.graphics.push("all")

    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    local availableWidth = screenWidth
        - DRAFT_SIDE_MARGIN * 2
        - DRAFT_PANEL_GAP * (DRAFT_CHOICE_COUNT - 1)
    local panelWidth = availableWidth / DRAFT_CHOICE_COUNT
    local panelHeight = screenHeight
        - DRAFT_TOP_MARGIN
        - DRAFT_BOTTOM_MARGIN
    local title = "Choose A Captain"

    love.graphics.setFont(DraftState.titleFont)
    love.graphics.setColor(DRAFT_TITLE_COLOR)
    love.graphics.print(
        title,
        (screenWidth - DraftState.titleFont:getWidth(title)) / 2,
        58
    )

    for index, choice in ipairs(DraftState.choices) do
        local x = DRAFT_SIDE_MARGIN
            + (index - 1) * (panelWidth + DRAFT_PANEL_GAP)
        local startTime = (index - 1) * DRAFT_PANEL_DROP_DELAY
        local progress = math.max(0, math.min(
            1,
            (DraftState.animationElapsed - startTime)
                / DRAFT_PANEL_DROP_DURATION
        ))

        if progress > 0 then
            local easedProgress = 1 - (1 - progress) ^ 3
            local y = DRAFT_TOP_MARGIN
                - DRAFT_PANEL_DROP_DISTANCE * (1 - easedProgress)
            local opacity = math.min(1, progress * 2)

            drawDraftPanel(
                choice,
                x,
                y,
                panelWidth,
                panelHeight,
                opacity
            )
        end
    end

    love.graphics.pop()
    Controls.draw()
end

function DraftState.keypressed(key)
    if key == "escape" or Controls.isExitPromptOpen() then
        return Controls.keypressed(key)
    end
end

function DraftState.mousepressed(x, y, button)
    if Controls.isExitPromptOpen() then
        return Controls.mousepressed(x, y, button)
    end
end

states["Battle Map"] = BattleMapState
states["The Draft"] = DraftState

local function callCurrentState(methodName, ...)
    local method = currentState and currentState[methodName]

    if method then
        return method(...)
    end
end

function GameStates.setState(name)
    local nextState = states[name]

    if not nextState then
        error(("Unknown game state %q"):format(tostring(name)))
    end

    callCurrentState("leave")
    currentState = nextState
    currentStateName = name
    callCurrentState("load")
end

function GameStates.getState()
    return currentStateName
end

function GameStates.load()
    love.graphics.setLineStyle("smooth")
    love.graphics.setFont(
        love.graphics.newFont(DEFAULT_FONT_PATH, DEFAULT_FONT_SIZE)
    )
    GameStates.setState(INITIAL_STATE)
end

function GameStates.draw()
    callCurrentState("draw")
end

function GameStates.update(dt)
    callCurrentState("update", dt)
end

function GameStates.keypressed(key, scancode, isRepeat)
    callCurrentState("keypressed", key, scancode, isRepeat)
end

function GameStates.mousepressed(x, y, button, isTouch, presses)
    callCurrentState("mousepressed", x, y, button, isTouch, presses)
end

function GameStates.mousereleased(x, y, button, isTouch, presses)
    callCurrentState("mousereleased", x, y, button, isTouch, presses)
end

function GameStates.mousemoved(x, y, dx, dy, isTouch)
    callCurrentState("mousemoved", x, y, dx, dy, isTouch)
end

function GameStates.wheelmoved(x, y)
    callCurrentState("wheelmoved", x, y)
end

return GameStates
