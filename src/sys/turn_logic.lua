local Sfx = require("src.sys.sfx")

local TurnLogic = {}

local PHASES = {
    "Start",
    "Reflex",
    "March",
    "Steel",
    "Fire",
    "End",
}

local TRACKER_COLUMNS = 2
local TRACKER_GAP = 8
local TRACKER_TOP_GAP = 10
local PHASE_WIDTH = 138
local PHASE_HEIGHT = 42
local SIDE_CELL_WIDTH = 112
local RESOLUTION_DURATION = 0.35
local CLEANUP_DURATION = 0.15

local COLORS = {
    inactiveFill = { 0.055, 0.065, 0.085, 0.94 },
    inactiveBorder = { 0.34, 0.38, 0.46, 1 },
    inactiveText = { 0.66, 0.70, 0.77, 1 },
    activeFill = { 0.82, 0.85, 0.90, 1 },
    activeBorder = { 1, 1, 1, 1 },
    activeText = { 0.025, 0.03, 0.04, 1 },
    resolvingFill = { 249 / 255, 161 / 255, 0, 1 },
    resolvingBorder = { 0, 0, 0, 1 },
    resolvingText = { 0, 0, 0, 1 },
}

local currentPhaseIndex = 1
local round = 0
local phaseState = "queue"
local stateElapsed = 0
local autoEnabled = false
local started = false

local function isInside(x, y, bounds)
    return x >= bounds.x
        and x <= bounds.x + bounds.width
        and y >= bounds.y
        and y <= bounds.y + bounds.height
end

local function beginResolution()
    if phaseState ~= "queue" then
        return false
    end

    phaseState = "resolution"
    stateElapsed = 0

    return true
end

local function copyBounds(bounds)
    return {
        x = bounds.x,
        y = bounds.y,
        width = bounds.width,
        height = bounds.height,
    }
end

local function playCurrentPhaseCue()
    if started and currentPhaseIndex == 1 then
        Sfx.play("round_start")
    end
end

function TurnLogic.reset()
    currentPhaseIndex = 1
    round = 0
    phaseState = "queue"
    stateElapsed = 0
    autoEnabled = false
    started = false
end

function TurnLogic.begin()
    if started then
        return false
    end

    started = true
    playCurrentPhaseCue()

    return true
end

function TurnLogic.hasBegun()
    return started
end

function TurnLogic.getPhases()
    local phases = {}

    for index, name in ipairs(PHASES) do
        phases[index] = name
    end

    return phases
end

function TurnLogic.getCurrentPhase()
    return PHASES[currentPhaseIndex], currentPhaseIndex
end

function TurnLogic.getRound()
    return round
end

function TurnLogic.getPhaseState()
    return phaseState
end

function TurnLogic.isAutoEnabled()
    return autoEnabled
end

function TurnLogic.getStateDurations()
    return {
        resolution = RESOLUTION_DURATION,
        cleanup = CLEANUP_DURATION,
    }
end

function TurnLogic.setPhase(phase)
    local nextIndex

    if type(phase) == "number"
        and phase % 1 == 0
        and PHASES[phase] then
        nextIndex = phase
    elseif type(phase) == "string" then
        for index, name in ipairs(PHASES) do
            if name:lower() == phase:lower() then
                nextIndex = index
                break
            end
        end
    end

    if not nextIndex then
        return nil, "phase must be a valid phase name or index"
    end

    currentPhaseIndex = nextIndex
    phaseState = "queue"
    stateElapsed = 0
    playCurrentPhaseCue()

    return PHASES[currentPhaseIndex]
end

function TurnLogic.nextPhase()
    currentPhaseIndex = currentPhaseIndex + 1

    if currentPhaseIndex > #PHASES then
        currentPhaseIndex = 1
        round = round + 1
    end

    phaseState = "queue"
    stateElapsed = 0
    playCurrentPhaseCue()

    return PHASES[currentPhaseIndex], round
end

function TurnLogic.requestAdvance()
    return beginResolution()
end

function TurnLogic.setAutoEnabled(enabled)
    autoEnabled = enabled == true

    if autoEnabled then
        beginResolution()
    end

    return autoEnabled
end

function TurnLogic.toggleAuto()
    return TurnLogic.setAutoEnabled(not autoEnabled)
end

function TurnLogic.update(dt)
    dt = math.max(0, tonumber(dt) or 0)

    if phaseState == "queue" then
        if autoEnabled then
            beginResolution()
        end

        return
    end

    stateElapsed = stateElapsed + dt

    if phaseState == "resolution"
        and stateElapsed >= RESOLUTION_DURATION then
        phaseState = "cleanup"
        stateElapsed = 0
    elseif phaseState == "cleanup"
        and stateElapsed >= CLEANUP_DURATION then
        TurnLogic.nextPhase()

        if autoEnabled then
            beginResolution()
        end
    end
end

function TurnLogic.getLayout(fateButtonBounds)
    local anchor = fateButtonBounds or {
        x = (love.graphics.getWidth() - 74) / 2,
        y = 12,
        width = 74,
        height = 74,
    }
    local trackerWidth = TRACKER_COLUMNS * PHASE_WIDTH
        + (TRACKER_COLUMNS - 1) * TRACKER_GAP
    local trackerX = anchor.x + anchor.width / 2 - trackerWidth / 2
    local trackerY = anchor.y + anchor.height + TRACKER_TOP_GAP
    local cells = {}

    for index, name in ipairs(PHASES) do
        local column = (index - 1) % TRACKER_COLUMNS
        local row = math.floor((index - 1) / TRACKER_COLUMNS)

        cells[index] = {
            name = name,
            index = index,
            x = trackerX + column * (PHASE_WIDTH + TRACKER_GAP),
            y = trackerY + row * (PHASE_HEIGHT + TRACKER_GAP),
            width = PHASE_WIDTH,
            height = PHASE_HEIGHT,
        }
    end

    local secondRowY = cells[3].y
    local roundBounds = {
        x = trackerX - TRACKER_GAP - SIDE_CELL_WIDTH,
        y = secondRowY,
        width = SIDE_CELL_WIDTH,
        height = PHASE_HEIGHT,
    }
    local autoBounds = {
        x = trackerX + trackerWidth + TRACKER_GAP,
        y = secondRowY,
        width = SIDE_CELL_WIDTH,
        height = PHASE_HEIGHT,
    }
    local advanceBounds = {
        x = autoBounds.x,
        y = autoBounds.y - TRACKER_GAP - PHASE_HEIGHT,
        width = PHASE_HEIGHT,
        height = PHASE_HEIGHT,
    }

    return {
        anchor = copyBounds(anchor),
        x = trackerX,
        y = trackerY,
        width = trackerWidth,
        height = math.ceil(#PHASES / TRACKER_COLUMNS) * PHASE_HEIGHT
            + (math.ceil(#PHASES / TRACKER_COLUMNS) - 1) * TRACKER_GAP,
        cells = cells,
        round = roundBounds,
        autoToggle = autoBounds,
        advance = advanceBounds,
    }
end

function TurnLogic.draw(fateButtonBounds)
    local layout = TurnLogic.getLayout(fateButtonBounds)
    local font = love.graphics.getFont and love.graphics.getFont()
    local fontHeight = font and font:getHeight() or 18

    local function drawTrackerCell(cell, label, treatment)
        local active = treatment == "active"
        local resolving = treatment == "resolving"
        local labelY = math.floor(
            cell.y + (cell.height - fontHeight) / 2 + 0.5
        )

        local fillColor = resolving
            and COLORS.resolvingFill
            or active and COLORS.activeFill
            or COLORS.inactiveFill
        local borderColor = resolving
            and COLORS.resolvingBorder
            or active and COLORS.activeBorder
            or COLORS.inactiveBorder
        local textColor = resolving
            and COLORS.resolvingText
            or active and COLORS.activeText
            or COLORS.inactiveText

        love.graphics.setColor(fillColor)
        love.graphics.rectangle(
            "fill",
            cell.x,
            cell.y,
            cell.width,
            cell.height,
            4,
            4
        )
        love.graphics.setColor(borderColor)
        love.graphics.setLineWidth(active and 3 or 2)
        love.graphics.rectangle(
            "line",
            cell.x,
            cell.y,
            cell.width,
            cell.height,
            4,
            4
        )
        love.graphics.setColor(textColor)
        love.graphics.printf(
            label,
            cell.x,
            labelY,
            cell.width,
            "center"
        )
    end

    for index, cell in ipairs(layout.cells) do
        local isCurrent = index == currentPhaseIndex
        local treatment = isCurrent
            and phaseState ~= "queue"
            and "resolving"
            or isCurrent and "active"
            or "inactive"

        drawTrackerCell(
            cell,
            cell.name:upper(),
            treatment
        )
    end

    drawTrackerCell(layout.round, "ROUND " .. round, "inactive")
    drawTrackerCell(
        layout.autoToggle,
        autoEnabled and "AUTO ON" or "AUTO OFF",
        autoEnabled and "active" or "inactive"
    )
    drawTrackerCell(
        layout.advance,
        ">",
        phaseState == "queue" and "active" or "inactive"
    )

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function TurnLogic.mousepressed(x, y, button, fateButtonBounds)
    if button ~= 1 then
        return false
    end

    local layout = TurnLogic.getLayout(fateButtonBounds)

    if isInside(x, y, layout.advance) then
        TurnLogic.requestAdvance()
        return true
    end

    if isInside(x, y, layout.autoToggle) then
        TurnLogic.toggleAuto()
        return true
    end

    return false
end

function TurnLogic.keypressed(key)
    if key == "." then
        TurnLogic.requestAdvance()
        return true
    end

    if key == "space" then
        TurnLogic.toggleAuto()
        return true
    end

    return false
end

return TurnLogic
