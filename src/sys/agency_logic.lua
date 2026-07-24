local Sfx = require("src.sys.sfx")
local ImageLoader = require("src.assets.image_loader")

local AgencyStacks = require("data.agency_stacks")
local AgencyTiles = require("data.agency_tiles")

local AgencyLogic = {}

local MODAL_MARGIN_X = 60
local MODAL_TOP = 86
local MODAL_BOTTOM = 70
local MODAL_PADDING = 24
local MODAL_HEADER_HEIGHT = 58
local STACK_PANEL_HEIGHT = 560
local PANEL_GAP = 14
local TILE_GAP = 8
local TILE_HEIGHT = 56
local TILE_COLUMNS = 6
local SCROLL_STEP = 72
local ACTION_ICON_DIR = "assets/images/icons"
local ACTION_ICON_SIZE = 34
local ACTION_VALUE_GAP = 7
local ACTION_GROUP_GAP = 14

local COLORS = {
    dim = { 0, 0, 0, 0.68 },
    modal = { 0.025, 0.03, 0.04, 0.985 },
    panel = { 0.075, 0.085, 0.11, 1 },
    panelHeader = { 0.12, 0.14, 0.18, 1 },
    border = { 0.82, 0.85, 0.9, 1 },
    text = { 1, 1, 1, 1 },
    muted = { 0.65, 0.69, 0.76, 1 },
    tile = { 0, 0, 0, 1 },
    scrollTrack = { 0.03, 0.035, 0.05, 1 },
    scrollThumb = { 0.56, 0.62, 0.72, 1 },
}

local stacksById = {}
local tilesById = {}
local runtimeStacks = {}
local modalOpen = false
local activeStack
local actionIconCache = {}
local missingActionIcons = {}

local function indexDefinitions(definitions, label)
    local index = {}

    for position, definition in ipairs(definitions) do
        if type(definition) ~= "table" then
            error(("%s definition %d must be a table"):format(
                label,
                position
            ))
        end

        if type(definition.id) ~= "string"
            or not definition.id:match("%S") then
            error(("%s definition %d requires a non-empty id"):format(
                label,
                position
            ))
        end

        if index[definition.id] then
            error(("duplicate %s id %q"):format(label, definition.id))
        end

        index[definition.id] = definition
    end

    return index
end

stacksById = indexDefinitions(AgencyStacks, "Agency stack")
tilesById = indexDefinitions(AgencyTiles, "Agency tile")

local function isInside(x, y, bounds)
    return x >= bounds.x
        and x <= bounds.x + bounds.width
        and y >= bounds.y
        and y <= bounds.y + bounds.height
end

local function getStackIdForEntity(entity)
    if entity.entityType == "HOSTILE" then
        return entity.id:gsub("^HOSTILE_", "")
    end

    return entity.id:gsub("^AGENT_", "")
end

local function buildRuntimeStack(entity, definition)
    if type(definition.tiles) ~= "table" then
        return nil, ("Agency stack %q requires a tiles table"):format(
            definition.id
        )
    end

    local tiles = {}

    for position, entry in ipairs(definition.tiles) do
        if type(entry) ~= "table"
            or type(entry.tileid) ~= "string"
            or not entry.tileid:match("%S") then
            return nil, (
                "Agency stack %q has an invalid tile at position %d"
            ):format(definition.id, position)
        end

        if type(entry.quantity) ~= "number"
            or entry.quantity % 1 ~= 0
            or entry.quantity < 0 then
            return nil, (
                "Agency stack %q tile %q requires a non-negative integer quantity"
            ):format(definition.id, entry.tileid)
        end

        local tileDefinition = tilesById[entry.tileid]

        if not tileDefinition then
            return nil, (
                "Agency stack %q references unknown tile %q"
            ):format(definition.id, entry.tileid)
        end

        for serial = 1, entry.quantity do
            tiles[#tiles + 1] = {
                id = tileDefinition.id,
                definition = tileDefinition,
                serial = serial,
                origin = "stack",
            }
        end
    end

    return {
        id = definition.id,
        definition = definition,
        entity = entity,
        tiles = tiles,
        scroll = 0,
        discarded = {
            id = "discarded",
            tiles = {},
            scroll = 0,
        },
        additional = {
            id = "additional",
            tiles = {},
            scroll = 0,
        },
    }
end

local function getModalBounds()
    return {
        x = MODAL_MARGIN_X,
        y = MODAL_TOP,
        width = love.graphics.getWidth() - MODAL_MARGIN_X * 2,
        height = love.graphics.getHeight() - MODAL_TOP - MODAL_BOTTOM,
    }
end

local function addPanel(panels, state, title, x, y, width, height, columns)
    panels[#panels + 1] = {
        state = state,
        title = title,
        x = x,
        y = y,
        width = width,
        height = height,
        columns = columns,
    }
end

function AgencyLogic.getLayout()
    local modal = getModalBounds()
    local panels = {}

    if not activeStack then
        return {
            modal = modal,
            panels = panels,
        }
    end

    local contentX = modal.x + MODAL_PADDING
    local contentWidth = modal.width - MODAL_PADDING * 2
    local stackTop = modal.y + MODAL_HEADER_HEIGHT + MODAL_PADDING

    addPanel(
        panels,
        activeStack,
        ("AGENCY TILES  (%d)"):format(#activeStack.tiles),
        contentX,
        stackTop,
        contentWidth,
        STACK_PANEL_HEIGHT,
        TILE_COLUMNS
    )

    local lowerTop = stackTop + STACK_PANEL_HEIGHT + PANEL_GAP
    local lowerHeight = modal.y + modal.height
        - MODAL_PADDING - lowerTop
    local lowerWidth = (contentWidth - PANEL_GAP) / 2

    addPanel(
        panels,
        activeStack.discarded,
        ("DISCARDED  (%d)"):format(#activeStack.discarded.tiles),
        contentX,
        lowerTop,
        lowerWidth,
        lowerHeight,
        2
    )
    addPanel(
        panels,
        activeStack.additional,
        ("ADDITIONAL TILES  (%d)"):format(#activeStack.additional.tiles),
        contentX + lowerWidth + PANEL_GAP,
        lowerTop,
        lowerWidth,
        lowerHeight,
        2
    )

    return {
        modal = modal,
        panels = panels,
    }
end

local function getPanelViewport(panel)
    return {
        x = panel.x + 10,
        y = panel.y + 42,
        width = panel.width - 20,
        height = panel.height - 52,
    }
end

local function getMaxScroll(panel)
    local viewport = getPanelViewport(panel)
    local rows = math.ceil(#panel.state.tiles / panel.columns)
    local contentHeight = math.max(
        0,
        rows * (TILE_HEIGHT + TILE_GAP) - TILE_GAP
    )

    return math.max(0, contentHeight - viewport.height)
end

local function getActionIcon(actionType)
    if type(actionType) ~= "string"
        or not actionType:match("^[%w_%-]+$") then
        return nil
    end

    local path = ("%s/agency_%s.webp"):format(
        ACTION_ICON_DIR,
        actionType:lower()
    )

    if actionIconCache[path] then
        return actionIconCache[path]
    end

    if missingActionIcons[path] then
        return nil
    end

    local loaded, icon = pcall(ImageLoader.newImage, path)

    if not loaded or not icon then
        missingActionIcons[path] = true
        return nil
    end

    actionIconCache[path] = icon

    return icon
end

local function getTileActions(definition)
    local actions = {}

    for _, actionEntry in ipairs(definition.actions or {}) do
        local actionTypes = {}

        for actionType in pairs(actionEntry) do
            actionTypes[#actionTypes + 1] = actionType
        end

        table.sort(actionTypes)

        for _, actionType in ipairs(actionTypes) do
            actions[#actions + 1] = {
                actionType = actionType,
                value = actionEntry[actionType],
                icon = getActionIcon(actionType),
            }
        end
    end

    return actions
end

local function drawTile(tile, x, y, width)
    love.graphics.setColor(COLORS.tile)
    love.graphics.rectangle("fill", x, y, width, TILE_HEIGHT, 4, 4)
    love.graphics.setColor(COLORS.border)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, width, TILE_HEIGHT, 4, 4)

    local actions = getTileActions(tile.definition)
    local font = love.graphics.getFont and love.graphics.getFont()
    local groups = {}
    local totalWidth = 0

    for _, action in ipairs(actions) do
        local valueText = tostring(action.value)
        local valueWidth = font
            and font:getWidth(valueText)
            or #valueText * 10
        local groupWidth = valueWidth

        if action.icon then
            groupWidth = groupWidth
                + ACTION_ICON_SIZE
                + ACTION_VALUE_GAP
        end

        groups[#groups + 1] = {
            action = action,
            valueText = valueText,
            valueWidth = valueWidth,
            width = groupWidth,
        }
        totalWidth = totalWidth + groupWidth
    end

    totalWidth = totalWidth
        + math.max(0, #groups - 1) * ACTION_GROUP_GAP

    local drawX = x + (width - totalWidth) / 2
    local fontHeight = font and font:getHeight() or 18

    for _, group in ipairs(groups) do
        if group.action.icon then
            local iconWidth, iconHeight = group.action.icon:getDimensions()
            local scale = ACTION_ICON_SIZE
                / math.max(iconWidth, iconHeight)

            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(
                group.action.icon,
                drawX + ACTION_ICON_SIZE / 2,
                y + TILE_HEIGHT / 2,
                0,
                scale,
                scale,
                iconWidth / 2,
                iconHeight / 2
            )
            drawX = drawX + ACTION_ICON_SIZE + ACTION_VALUE_GAP
        end

        love.graphics.setColor(COLORS.text)
        love.graphics.print(
            group.valueText,
            drawX,
            y + (TILE_HEIGHT - fontHeight) / 2
        )
        drawX = drawX + group.valueWidth + ACTION_GROUP_GAP
    end
end

local function drawPanel(panel)
    love.graphics.setColor(COLORS.panel)
    love.graphics.rectangle(
        "fill",
        panel.x,
        panel.y,
        panel.width,
        panel.height,
        5,
        5
    )
    love.graphics.setColor(COLORS.panelHeader)
    love.graphics.rectangle(
        "fill",
        panel.x,
        panel.y,
        panel.width,
        34,
        5,
        5
    )
    love.graphics.setColor(COLORS.border)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle(
        "line",
        panel.x,
        panel.y,
        panel.width,
        panel.height,
        5,
        5
    )
    love.graphics.setColor(COLORS.text)
    love.graphics.printf(
        panel.title,
        panel.x + 9,
        panel.y + 9,
        panel.width - 18,
        "left"
    )

    local viewport = getPanelViewport(panel)
    local tileWidth = (
        viewport.width - TILE_GAP * (panel.columns - 1)
    ) / panel.columns
    local maxScroll = getMaxScroll(panel)

    panel.state.scroll = math.max(
        0,
        math.min(panel.state.scroll, maxScroll)
    )
    love.graphics.setScissor(
        viewport.x,
        viewport.y,
        viewport.width,
        viewport.height
    )

    for index, tile in ipairs(panel.state.tiles) do
        local column = (index - 1) % panel.columns
        local row = math.floor((index - 1) / panel.columns)
        local tileX = viewport.x + column * (tileWidth + TILE_GAP)
        local tileY = viewport.y
            + row * (TILE_HEIGHT + TILE_GAP)
            - panel.state.scroll

        if tileY + TILE_HEIGHT >= viewport.y
            and tileY <= viewport.y + viewport.height then
            drawTile(tile, tileX, tileY, tileWidth)
        end
    end

    love.graphics.setScissor()

    if maxScroll > 0 then
        local trackWidth = 5
        local trackX = panel.x + panel.width - trackWidth - 3
        local thumbHeight = math.max(
            24,
            viewport.height * viewport.height
                / (viewport.height + maxScroll)
        )
        local thumbTravel = viewport.height - thumbHeight
        local thumbY = viewport.y
            + thumbTravel * panel.state.scroll / maxScroll

        love.graphics.setColor(COLORS.scrollTrack)
        love.graphics.rectangle(
            "fill",
            trackX,
            viewport.y,
            trackWidth,
            viewport.height
        )
        love.graphics.setColor(COLORS.scrollThumb)
        love.graphics.rectangle(
            "fill",
            trackX,
            thumbY,
            trackWidth,
            thumbHeight
        )
    end
end

function AgencyLogic.loadEntities(entities)
    local nextStacks = {}

    for _, entity in ipairs(entities) do
        if entity.entityType == "AGENT"
            or entity.entityType == "HOSTILE" then
            local stackId = getStackIdForEntity(entity)
            local definition = stacksById[stackId]

            if definition then
                local stack, stackError = buildRuntimeStack(
                    entity,
                    definition
                )

                if not stack then
                    return nil, stackError
                end

                entity.agencyStack = stack
                nextStacks[#nextStacks + 1] = stack
            else
                entity.agencyStack = nil
            end
        end
    end

    runtimeStacks = nextStacks
    modalOpen = false
    activeStack = nil

    return runtimeStacks
end

function AgencyLogic.getStacks()
    return runtimeStacks
end

function AgencyLogic.getActiveStack()
    return activeStack
end

function AgencyLogic.isModalOpen()
    return modalOpen
end

function AgencyLogic.openForAgent(entity)
    if modalOpen
        or not entity
        or not entity.agencyStack then
        return false
    end

    activeStack = entity.agencyStack
    modalOpen = true
    Sfx.play("click")

    return true
end

function AgencyLogic.close()
    modalOpen = false
    activeStack = nil
end

function AgencyLogic.mousepressed(x, y, button, entity, buttonBounds)
    if modalOpen then
        if button == 2 then
            AgencyLogic.close()
        elseif button == 1 and not isInside(x, y, getModalBounds()) then
            AgencyLogic.close()
        end

        return true
    end

    if button == 1
        and entity
        and entity.agencyStack
        and buttonBounds
        and isInside(x, y, buttonBounds) then
        return AgencyLogic.openForAgent(entity)
    end

    return false
end

function AgencyLogic.wheelmoved(mouseX, mouseY, wheelY)
    if not modalOpen then
        return false
    end

    for _, panel in ipairs(AgencyLogic.getLayout().panels) do
        if isInside(mouseX, mouseY, panel) then
            local maxScroll = getMaxScroll(panel)

            panel.state.scroll = math.max(
                0,
                math.min(
                    maxScroll,
                    panel.state.scroll - wheelY * SCROLL_STEP
                )
            )
            break
        end
    end

    return true
end

function AgencyLogic.draw()
    if not modalOpen or not activeStack then
        return
    end

    local layout = AgencyLogic.getLayout()
    local modal = layout.modal

    love.graphics.setColor(COLORS.dim)
    love.graphics.rectangle(
        "fill",
        0,
        0,
        love.graphics.getWidth(),
        love.graphics.getHeight()
    )
    love.graphics.setColor(COLORS.modal)
    love.graphics.rectangle(
        "fill",
        modal.x,
        modal.y,
        modal.width,
        modal.height,
        8,
        8
    )
    love.graphics.setColor(COLORS.border)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle(
        "line",
        modal.x,
        modal.y,
        modal.width,
        modal.height,
        8,
        8
    )
    love.graphics.setColor(COLORS.text)
    love.graphics.printf(
        "AGENCY STACK — "
            .. (activeStack.entity.definition.name
                or activeStack.entity.id),
        modal.x,
        modal.y + 20,
        modal.width,
        "center"
    )

    for _, panel in ipairs(layout.panels) do
        drawPanel(panel)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return AgencyLogic
