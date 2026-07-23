local FateLogic = require("src.sys.fate_logic")

local Controls = {}

local PANEL_WIDTH = 520
local PANEL_HEIGHT = 220
local BUTTON_WIDTH = 180
local BUTTON_HEIGHT = 52
local BUTTON_GAP = 24

local state = {
    exitPromptOpen = false,
}

local function isInside(x, y, bounds)
    return x >= bounds.x
        and x <= bounds.x + bounds.width
        and y >= bounds.y
        and y <= bounds.y + bounds.height
end

function Controls.getExitPromptLayout()
    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    local panel = {
        x = (screenWidth - PANEL_WIDTH) / 2,
        y = (screenHeight - PANEL_HEIGHT) / 2,
        width = PANEL_WIDTH,
        height = PANEL_HEIGHT,
    }
    local buttonsWidth = BUTTON_WIDTH * 2 + BUTTON_GAP
    local buttonStartX = panel.x + (PANEL_WIDTH - buttonsWidth) / 2
    local buttonY = panel.y + PANEL_HEIGHT - BUTTON_HEIGHT - 28

    return {
        panel = panel,
        yes = {
            x = buttonStartX,
            y = buttonY,
            width = BUTTON_WIDTH,
            height = BUTTON_HEIGHT,
        },
        no = {
            x = buttonStartX + BUTTON_WIDTH + BUTTON_GAP,
            y = buttonY,
            width = BUTTON_WIDTH,
            height = BUTTON_HEIGHT,
        },
    }
end

function Controls.isExitPromptOpen()
    return state.exitPromptOpen
end

function Controls.closeExitPrompt()
    state.exitPromptOpen = false
end

function Controls.keypressed(key)
    if key == "escape" then
        state.exitPromptOpen = not state.exitPromptOpen
        return true
    end

    if state.exitPromptOpen then
        return true
    end

    return FateLogic.keypressed(key)
end

function Controls.mousepressed(x, y, button)
    if state.exitPromptOpen then
        if button == 2 then
            Controls.closeExitPrompt()
            return true
        end

        if button ~= 1 then
            return true
        end

        local layout = Controls.getExitPromptLayout()

        if isInside(x, y, layout.yes) then
            love.event.quit()
        elseif isInside(x, y, layout.no)
            or not isInside(x, y, layout.panel) then
            Controls.closeExitPrompt()
        end

        return true
    end

    return FateLogic.mousepressed(x, y, button)
end

function Controls.wheelmoved(_, wheelY)
    if state.exitPromptOpen then
        return true
    end

    local mouseX, mouseY = love.mouse.getPosition()

    return FateLogic.wheelmoved(mouseX, mouseY, wheelY)
end

local function drawButton(label, bounds, color)
    love.graphics.setColor(color)
    love.graphics.rectangle(
        "fill",
        bounds.x,
        bounds.y,
        bounds.width,
        bounds.height,
        5,
        5
    )
    love.graphics.setColor(1, 1, 1, 1)
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
    love.graphics.printf(
        label,
        bounds.x,
        bounds.y + 17,
        bounds.width,
        "center"
    )
end

function Controls.draw()
    if not state.exitPromptOpen then
        return
    end

    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    local layout = Controls.getExitPromptLayout()
    local panel = layout.panel

    love.graphics.setColor(0, 0, 0, 0.58)
    love.graphics.rectangle("fill", 0, 0, screenWidth, screenHeight)

    love.graphics.setColor(0.025, 0.03, 0.04, 0.98)
    love.graphics.rectangle(
        "fill",
        panel.x,
        panel.y,
        panel.width,
        panel.height,
        8,
        8
    )
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle(
        "line",
        panel.x,
        panel.y,
        panel.width,
        panel.height,
        8,
        8
    )
    love.graphics.printf(
        "EXIT GAME?",
        panel.x,
        panel.y + 38,
        panel.width,
        "center"
    )
    love.graphics.printf(
        "Are you sure you want to exit?",
        panel.x,
        panel.y + 78,
        panel.width,
        "center"
    )

    drawButton("YES", layout.yes, { 0.62, 0.12, 0.12, 1 })
    drawButton("NO", layout.no, { 0.16, 0.2, 0.28, 1 })
    love.graphics.setColor(1, 1, 1, 1)
end

return Controls
