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

    function love.mousepressed(x, y, button, isTouch, presses)
        MapEditor.mousepressed(x, y, button, isTouch, presses)
    end

    function love.mousereleased(x, y, button, isTouch, presses)
        MapEditor.mousereleased(x, y, button, isTouch, presses)
    end

    function love.mousemoved(x, y, dx, dy, isTouch)
        MapEditor.mousemoved(x, y, dx, dy, isTouch)
    end

    return
end

local BattleMap = require("src.sys.battle_map")

function love.load()
    love.graphics.setBackgroundColor(0.055, 0.065, 0.09)
    love.graphics.setLineStyle("smooth")
end

function love.draw()
    BattleMap.draw()
end
