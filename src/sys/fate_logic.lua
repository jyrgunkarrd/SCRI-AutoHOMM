local ImageLoader = require("src.assets.image_loader")

local FateStacks = require("data.fate_stacks")
local FateTiles = require("data.fate_tiles")

local FateLogic = {}

local ICON_PATH = "assets/images/icons/fate.webp"
local BUTTON_SIZE = 74
local MODAL_MARGIN_X = 60
local MODAL_TOP = 86
local MODAL_BOTTOM = 70
local MODAL_PADDING = 24
local MODAL_HEADER_HEIGHT = 58
local SLOT_REGION_HEIGHT = 560
local PANEL_GAP = 14
local TILE_GAP = 8
local TILE_HEIGHT = 56
local SCROLL_STEP = 72

local COLORS = {
    dim = { 0, 0, 0, 0.68 },
    modal = { 0.025, 0.03, 0.04, 0.985 },
    panel = { 0.075, 0.085, 0.11, 1 },
    panelHeader = { 0.12, 0.14, 0.18, 1 },
    border = { 0.82, 0.85, 0.9, 1 },
    text = { 1, 1, 1, 1 },
    muted = { 0.65, 0.69, 0.76, 1 },
    button = { 0.12, 0.15, 0.22, 1 },
    normalTile = { 0.15, 0.27, 0.43, 1 },
    negativeTile = { 0.50, 0.16, 0.18, 1 },
    failTile = { 0.28, 0.04, 0.055, 1 },
    criticalTile = { 0.64, 0.45, 0.08, 1 },
    scrollTrack = { 0.03, 0.035, 0.05, 1 },
    scrollThumb = { 0.56, 0.62, 0.72, 1 },
}

local stacksById = {}
local tilesById = {}
local runtimeStacks = {}
local activeIndex = 1
local icon
local modalOpen = false

local function indexDefinitions(definitions, label)
    local index = {}

    for position, definition in ipairs(definitions) do
        if type(definition) ~= "table" then
            error(("%s definition %d must be a table"):format(label, position))
        end

        if type(definition.id) ~= "string" or not definition.id:match("%S") then
            error(("%s definition %d requires a non-empty id"):format(label, position))
        end

        if index[definition.id] then
            error(("duplicate %s id %q"):format(label, definition.id))
        end

        index[definition.id] = definition
    end

    return index
end

stacksById = indexDefinitions(FateStacks, "fate stack")
tilesById = indexDefinitions(FateTiles, "fate tile")

local function isInside(x, y, bounds)
    return x >= bounds.x
        and x <= bounds.x + bounds.width
        and y >= bounds.y
        and y <= bounds.y + bounds.height
end

local function newTileObject(definition, serial, origin)
    return {
        id = definition.id,
        definition = definition,
        serial = serial,
        origin = origin,
    }
end

local function buildRuntimeStack(entity)
    local stackId = entity.definition.fate

    if type(stackId) ~= "string" or not stackId:match("%S") then
        return nil, ("JACL %q requires a fate stack id"):format(entity.id)
    end

    local definition = stacksById[stackId]

    if not definition then
        return nil, (
            "JACL %q references unknown fate stack %q"
        ):format(entity.id, stackId)
    end

    if type(definition.tiles) ~= "table" then
        return nil, ("fate stack %q requires a tiles table"):format(stackId)
    end

    local slots = {}

    for slotIndex, entry in ipairs(definition.tiles) do
        if type(entry) ~= "table"
            or type(entry.slot) ~= "string"
            or not entry.slot:match("%S") then
            return nil, (
                "fate stack %q has an invalid slot at position %d"
            ):format(stackId, slotIndex)
        end

        if type(entry.quantity) ~= "number"
            or entry.quantity % 1 ~= 0
            or entry.quantity < 0 then
            return nil, (
                "fate stack %q slot %q requires a non-negative integer quantity"
            ):format(stackId, entry.slot)
        end

        local tileDefinition = tilesById[entry.slot]

        if not tileDefinition then
            return nil, (
                "fate stack %q references unknown tile %q"
            ):format(stackId, entry.slot)
        end

        local slot = {
            id = entry.slot,
            definition = tileDefinition,
            tiles = {},
            scroll = 0,
        }

        for serial = 1, entry.quantity do
            slot.tiles[#slot.tiles + 1] = newTileObject(
                tileDefinition,
                serial,
                "stack"
            )
        end

        slots[#slots + 1] = slot
    end

    return {
        id = definition.id,
        definition = definition,
        entity = entity,
        slots = slots,
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

local function getActiveStack()
    return runtimeStacks[activeIndex]
end

local function getButtonBounds()
    return {
        x = (love.graphics.getWidth() - BUTTON_SIZE) / 2,
        y = 12,
        width = BUTTON_SIZE,
        height = BUTTON_SIZE,
    }
end

local function getModalBounds()
    local width = love.graphics.getWidth() - MODAL_MARGIN_X * 2
    local height = love.graphics.getHeight() - MODAL_TOP - MODAL_BOTTOM

    return {
        x = MODAL_MARGIN_X,
        y = MODAL_TOP,
        width = width,
        height = height,
    }
end

local function addPanel(panels, panelState, title, x, y, width, height)
    panels[#panels + 1] = {
        state = panelState,
        title = title,
        x = x,
        y = y,
        width = width,
        height = height,
    }
end

function FateLogic.getLayout()
    local stack = getActiveStack()
    local modal = getModalBounds()
    local panels = {}

    if not stack then
        return {
            button = getButtonBounds(),
            modal = modal,
            panels = panels,
        }
    end

    local contentX = modal.x + MODAL_PADDING
    local contentWidth = modal.width - MODAL_PADDING * 2
    local slotsTop = modal.y + MODAL_HEADER_HEIGHT + MODAL_PADDING
    local rowGap = PANEL_GAP
    local panelHeight = (SLOT_REGION_HEIGHT - rowGap) / 2
    local slotCount = #stack.slots
    local columns = math.max(1, math.ceil(slotCount / 2))
    local panelWidth = (
        contentWidth - PANEL_GAP * (columns - 1)
    ) / columns

    for row = 1, 2 do
        local firstIndex = (row - 1) * columns + 1
        local count = math.min(columns, slotCount - firstIndex + 1)

        if count > 0 then
            local rowWidth = panelWidth * count + PANEL_GAP * (count - 1)
            local rowX = contentX + (contentWidth - rowWidth) / 2
            local rowY = slotsTop + (row - 1) * (panelHeight + rowGap)

            for column = 1, count do
                local slot = stack.slots[firstIndex + column - 1]
                addPanel(
                    panels,
                    slot,
                    ("%s  (%d)"):format(slot.id, #slot.tiles),
                    rowX + (column - 1) * (panelWidth + PANEL_GAP),
                    rowY,
                    panelWidth,
                    panelHeight
                )
            end
        end
    end

    local lowerTop = slotsTop + SLOT_REGION_HEIGHT + PANEL_GAP
    local lowerHeight = modal.y + modal.height
        - MODAL_PADDING - lowerTop
    local lowerWidth = (contentWidth - PANEL_GAP) / 2

    addPanel(
        panels,
        stack.discarded,
        ("DISCARDED  (%d)"):format(#stack.discarded.tiles),
        contentX,
        lowerTop,
        lowerWidth,
        lowerHeight
    )
    addPanel(
        panels,
        stack.additional,
        ("ADDITIONAL TILES  (%d)"):format(#stack.additional.tiles),
        contentX + lowerWidth + PANEL_GAP,
        lowerTop,
        lowerWidth,
        lowerHeight
    )

    return {
        button = getButtonBounds(),
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
    local rows = math.ceil(#panel.state.tiles / 2)
    local contentHeight = math.max(
        0,
        rows * (TILE_HEIGHT + TILE_GAP) - TILE_GAP
    )

    return math.max(0, contentHeight - viewport.height)
end

local function getTileColor(definition)
    if definition.fail then
        return COLORS.failTile
    elseif definition.crit then
        return COLORS.criticalTile
    elseif definition.neg then
        return COLORS.negativeTile
    end

    return COLORS.normalTile
end

local function getTileValueLabel(definition)
    if definition.fail then
        return "FAIL"
    elseif definition.crit then
        return ("CRIT +%s"):format(tostring(definition.value))
    elseif definition.neg then
        return "-" .. tostring(definition.value)
    elseif definition.value > 0 then
        return "+" .. tostring(definition.value)
    end

    return "0"
end

local function drawTile(tile, x, y, width)
    love.graphics.setColor(getTileColor(tile.definition))
    love.graphics.rectangle("fill", x, y, width, TILE_HEIGHT, 4, 4)
    love.graphics.setColor(COLORS.border)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, width, TILE_HEIGHT, 4, 4)
    love.graphics.setColor(COLORS.text)
    love.graphics.printf(tile.id, x + 7, y + 7, width - 14, "left")
    love.graphics.printf(
        getTileValueLabel(tile.definition),
        x + 7,
        y + 29,
        width - 14,
        "right"
    )
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
    local tileWidth = (viewport.width - TILE_GAP) / 2
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
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
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
        local trackY = viewport.y
        local thumbHeight = math.max(
            24,
            viewport.height * viewport.height
                / (viewport.height + maxScroll)
        )
        local thumbTravel = viewport.height - thumbHeight
        local thumbY = trackY
            + thumbTravel * panel.state.scroll / maxScroll

        love.graphics.setColor(COLORS.scrollTrack)
        love.graphics.rectangle(
            "fill",
            trackX,
            trackY,
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

local function drawButton(bounds)
    love.graphics.setColor(COLORS.button)
    love.graphics.rectangle(
        "fill",
        bounds.x,
        bounds.y,
        bounds.width,
        bounds.height,
        5,
        5
    )
    love.graphics.setColor(COLORS.border)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle(
        "line",
        bounds.x,
        bounds.y,
        bounds.width,
        bounds.height,
        5,
        5
    )

    if icon then
        local width, height = icon:getDimensions()
        local available = BUTTON_SIZE - 18
        local scale = available / math.max(width, height)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
            icon,
            bounds.x + bounds.width / 2,
            bounds.y + bounds.height / 2,
            0,
            scale,
            scale,
            width / 2,
            height / 2
        )
    end
end

function FateLogic.loadEntities(entities)
    local nextStacks = {}

    for _, entity in ipairs(entities) do
        if entity.entityType == "JACL" then
            local stack, stackError = buildRuntimeStack(entity)

            if not stack then
                return nil, stackError
            end

            entity.fateStack = stack
            nextStacks[#nextStacks + 1] = stack
        end
    end

    local loaded, loadedIcon = pcall(ImageLoader.newImage, ICON_PATH)

    if not loaded then
        return nil, (
            "unable to load fate icon from %s: %s"
        ):format(ICON_PATH, tostring(loadedIcon))
    end

    runtimeStacks = nextStacks
    activeIndex = 1
    icon = loadedIcon
    modalOpen = false

    return runtimeStacks
end

function FateLogic.getStacks()
    return runtimeStacks
end

function FateLogic.getActiveStack()
    return getActiveStack()
end

function FateLogic.isModalOpen()
    return modalOpen
end

function FateLogic.close()
    modalOpen = false
end

function FateLogic.keypressed(key)
    if key == "f" and getActiveStack() then
        modalOpen = not modalOpen
        return true
    end

    return modalOpen
end

function FateLogic.mousepressed(x, y, button)
    if modalOpen then
        if button == 2 then
            FateLogic.close()
        elseif button == 1 then
            local modal = getModalBounds()

            if not isInside(x, y, modal) then
                FateLogic.close()
            end
        end

        return true
    end

    if button == 1
        and getActiveStack()
        and isInside(x, y, getButtonBounds()) then
        modalOpen = true
        return true
    end

    return false
end

function FateLogic.wheelmoved(mouseX, mouseY, wheelY)
    if not modalOpen then
        return false
    end

    for _, panel in ipairs(FateLogic.getLayout().panels) do
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

function FateLogic.draw()
    local stack = getActiveStack()

    if not stack then
        return
    end

    local layout = FateLogic.getLayout()
    drawButton(layout.button)

    if not modalOpen then
        return
    end

    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    local modal = layout.modal

    love.graphics.setColor(COLORS.dim)
    love.graphics.rectangle("fill", 0, 0, screenWidth, screenHeight)
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
        "FATE STACK — " .. stack.entity.definition.name,
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

return FateLogic
