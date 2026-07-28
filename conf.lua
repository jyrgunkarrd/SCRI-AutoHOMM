function love.conf(t)
    local toolMode

    if arg then
        for _, value in ipairs(arg) do
            if value == "--portrait-tool" then
                toolMode = "portrait"
            elseif value == "--map-editor" then
                toolMode = "map"
            end
        end
    end

    t.identity = "scri-autohomm"
    t.version = "11.5"

    if toolMode == "portrait" then
        t.window.title = "SCRI AutoHOMM Hex Portrait Editor"
        t.window.width = 1280
        t.window.height = 900
        t.window.fullscreen = false
        t.window.resizable = true
    elseif toolMode == "map" then
        t.window.title = "SCRI AutoHOMM Map Editor"
        t.window.width = 1920
        t.window.height = 1080
        t.window.fullscreen = true
        t.window.fullscreentype = "desktop"
        t.window.resizable = false
    else
        t.window.title = "SCRI AutoHOMM"
        t.window.width = 1920
        t.window.height = 1080
        t.window.fullscreen = true
        t.window.fullscreentype = "exclusive"
        t.window.resizable = false
    end

    t.window.vsync = 1
    t.window.msaa = 4
end
