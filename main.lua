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

local GameStates = require("src.states.game_states")

function love.load()
    GameStates.load()
end

function love.draw()
    GameStates.draw()
end

function love.update(dt)
    GameStates.update(dt)
end

function love.keypressed(key, scancode, isRepeat)
    GameStates.keypressed(key, scancode, isRepeat)
end

function love.mousepressed(x, y, button, isTouch, presses)
    GameStates.mousepressed(x, y, button, isTouch, presses)
end

function love.mousereleased(x, y, button, isTouch, presses)
    GameStates.mousereleased(x, y, button, isTouch, presses)
end

function love.mousemoved(x, y, dx, dy, isTouch)
    GameStates.mousemoved(x, y, dx, dy, isTouch)
end

function love.wheelmoved(x, y)
    GameStates.wheelmoved(x, y)
end
