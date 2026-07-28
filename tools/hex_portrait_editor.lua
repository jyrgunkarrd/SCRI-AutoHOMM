local image_loader = require("src.assets.image_loader")

local editor = {}

local INPUT_DIR = "assets/images/process_queue"
local OUTPUT_DIR = "assets/images/processed"
local FONT_PATH = "assets/fonts/Furore.otf"
local EXPORT_SIZE = 512
local EXPORT_RADIUS = EXPORT_SIZE / 2
local PREVIEW_RADIUS = 310
local GAME_HEX_SIZE = 42
local GAME_PORTRAIT_RADIUS = GAME_HEX_SIZE * 0.78
local BACKGROUND_COLOR = { 0.055, 0.058, 0.068, 1 }
local MASK_COLOR = { 0.09, 0.095, 0.105, 0.72 }
local OVERLAY_COLOR = { 0.95, 0.86, 0.56, 0.9 }
local OVERLAY_FILL_COLOR = { 1, 1, 1, 0.055 }
local PREVIEW_TILE_COLOR = { 0.36, 0.66, 0.78, 1 }
local PREVIEW_OUTLINE_COLOR = { 0.015, 0.012, 0.01, 1 }
local TEXT_COLOR = { 0.88, 0.88, 0.82, 1 }

local state = {
    files = {},
    index = 1,
    image = nil,
    image_path = nil,
    image_name = nil,
    pan_x = 0,
    pan_y = 0,
    scale = 1,
    dragging = false,
    message = "",
}

local function isSupportedImage(path)
    local extension = path:match("%.([^%.]+)$")

    if not extension then
        return false
    end

    extension = extension:lower()

    return extension == "png"
        or extension == "jpg"
        or extension == "jpeg"
        or extension == "bmp"
        or extension == "tga"
        or extension == "webp"
end

local function getSourceRoot()
    local source = love.filesystem.getSource()

    if source and source:match("%.love$") then
        return love.filesystem.getSourceBaseDirectory()
    end

    return source or "."
end

local function joinPath(...)
    local parts = { ... }
    local path = table.concat(parts, "/"):gsub("//+", "/")

    return path
end

local function stripTrailingSlash(path)
    return (path:gsub("/+$", ""))
end

local function shellQuote(path)
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function getBaseName(path)
    local file_name = path:match("([^/]+)$") or path

    return (file_name:gsub("%.[^%.]+$", ""))
end

local function getOutputPath()
    return joinPath(OUTPUT_DIR, getBaseName(state.image_name) .. "_hex.png")
end

local function getNativeOutputPath()
    local path = joinPath(stripTrailingSlash(getSourceRoot()), getOutputPath()):gsub("%z", "")

    return path
end

local function getNativeOutputDir()
    local path = joinPath(stripTrailingSlash(getSourceRoot()), OUTPUT_DIR):gsub("%z", "")

    return path
end

local function buildHexPoints(center_x, center_y, radius)
    local points = {}

    for index = 0, 5 do
        local angle = math.rad(-90 + index * 60)
        points[#points + 1] = center_x + radius * math.cos(angle)
        points[#points + 1] = center_y + radius * math.sin(angle)
    end

    return points
end

local function getPreviewCenter()
    return love.graphics.getWidth() / 2, love.graphics.getHeight() / 2
end

local function resetFraming()
    state.pan_x = 0
    state.pan_y = 0
    state.scale = 1

    if state.image then
        local image_width = state.image:getWidth()
        local image_height = state.image:getHeight()
        local min_scale_x = PREVIEW_RADIUS * math.sqrt(3) / image_width
        local min_scale_y = PREVIEW_RADIUS * 2 / image_height

        state.scale = math.max(min_scale_x, min_scale_y)
    end
end

local function loadFile(index)
    state.index = index
    state.image = nil
    state.image_path = nil
    state.image_name = nil

    local file_name = state.files[state.index]

    if not file_name then
        state.message = "No source images in " .. INPUT_DIR
        return
    end

    local path = joinPath(INPUT_DIR, file_name)
    local ok, image = pcall(image_loader.newImage, path)

    if not ok then
        state.message = image
        return
    end

    state.image = image
    state.image_path = path
    state.image_name = file_name
    state.message = "Loaded " .. file_name
    resetFraming()
end

local function scanInputDirectory()
    love.filesystem.createDirectory(INPUT_DIR)
    love.filesystem.createDirectory(OUTPUT_DIR)

    state.files = {}

    for _, file_name in ipairs(love.filesystem.getDirectoryItems(INPUT_DIR)) do
        local path = joinPath(INPUT_DIR, file_name)
        local info = love.filesystem.getInfo(path)

        if info and info.type == "file" and isSupportedImage(file_name) then
            state.files[#state.files + 1] = file_name
        end
    end

    table.sort(state.files)

    if state.index > #state.files then
        state.index = 1
    end

    loadFile(state.index)
end

local function drawImageAt(center_x, center_y, scale_factor)
    if not state.image then
        return
    end

    local scale = state.scale * scale_factor
    local x = center_x + state.pan_x * scale_factor
    local y = center_y + state.pan_y * scale_factor

    love.graphics.draw(
        state.image,
        x,
        y,
        0,
        scale,
        scale,
        state.image:getWidth() / 2,
        state.image:getHeight() / 2
    )
end

local function drawHexMask(center_x, center_y)
    local points = buildHexPoints(center_x, center_y, PREVIEW_RADIUS)

    love.graphics.stencil(function()
        love.graphics.polygon("fill", points)
    end, "replace", 1)

    love.graphics.setStencilTest("notequal", 1)
    love.graphics.setColor(MASK_COLOR)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    love.graphics.setStencilTest()

    love.graphics.setColor(OVERLAY_FILL_COLOR)
    love.graphics.polygon("fill", points)
    love.graphics.setColor(OVERLAY_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.polygon("line", points)
    love.graphics.setLineWidth(1)
end

local function drawGamePreview()
    local margin = 26
    local center_x = margin + GAME_HEX_SIZE
    local center_y = love.graphics.getHeight() - margin - GAME_HEX_SIZE
    local tile_points = buildHexPoints(center_x, center_y, GAME_HEX_SIZE)
    local portrait_points = buildHexPoints(center_x, center_y, GAME_PORTRAIT_RADIUS)
    local scale_factor = GAME_PORTRAIT_RADIUS / PREVIEW_RADIUS

    love.graphics.setColor(PREVIEW_TILE_COLOR)
    love.graphics.polygon("fill", tile_points)

    love.graphics.stencil(function()
        love.graphics.polygon("fill", portrait_points)
    end, "replace", 1)

    love.graphics.setStencilTest("equal", 1)
    love.graphics.setColor(1, 1, 1, 1)
    drawImageAt(center_x, center_y, scale_factor)
    love.graphics.setStencilTest()

    love.graphics.setColor(PREVIEW_OUTLINE_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.polygon("line", portrait_points)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

local function drawStatus()
    local file_text = state.message

    if state.image_name then
        file_text = ("%s  %d/%d  scale %.2f"):format(state.image_name, state.index, #state.files, state.scale)
    end

    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), 64)
    love.graphics.setColor(TEXT_COLOR)
    love.graphics.print(file_text, 16, 10)

    if state.message ~= "" and state.message ~= file_text then
        love.graphics.print(state.message, 16, 34)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

local function writeFile(path, data)
    os.execute("mkdir -p " .. shellQuote(getNativeOutputDir()))

    local file, err = io.open(path, "wb")

    if not file then
        return nil, err
    end

    file:write(data)
    file:close()

    return true
end

local function exportPng()
    if not state.image then
        state.message = "No image loaded."
        print(state.message)
        return
    end

    local native_output_path = getNativeOutputPath()

    state.message = "Exporting " .. native_output_path
    print(state.message)

    local canvas = love.graphics.newCanvas(EXPORT_SIZE, EXPORT_SIZE, { format = "rgba8" })
    local previous_canvas = love.graphics.getCanvas()
    local previous_blend_mode, previous_alpha_mode = love.graphics.getBlendMode()
    local scale_factor = EXPORT_RADIUS / PREVIEW_RADIUS
    local points = buildHexPoints(EXPORT_RADIUS, EXPORT_RADIUS, EXPORT_RADIUS)

    love.graphics.setCanvas({ canvas, stencil = true })
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setBlendMode("alpha", "alphamultiply")
    love.graphics.stencil(function()
        love.graphics.polygon("fill", points)
    end, "replace", 1)
    love.graphics.setStencilTest("equal", 1)
    love.graphics.setColor(1, 1, 1, 1)
    drawImageAt(EXPORT_RADIUS, EXPORT_RADIUS, scale_factor)
    love.graphics.setStencilTest()
    love.graphics.setCanvas(previous_canvas)
    love.graphics.setBlendMode(previous_blend_mode, previous_alpha_mode)

    local image_data = canvas:newImageData()
    local file_data = image_data:encode("png")
    local ok, err = writeFile(native_output_path, file_data:getString())

    if not ok then
        state.message = "Export failed: " .. tostring(err)
        print(state.message)
        return
    end

    state.message = "Exported " .. native_output_path
    print(state.message)
end

function editor.load()
    love.window.setTitle("SCRI AutoHOMM Hex Portrait Editor")
    love.graphics.setBackgroundColor(BACKGROUND_COLOR)
    love.graphics.setDefaultFilter("linear", "linear", 1)
    love.graphics.setFont(love.graphics.newFont(FONT_PATH, 18))
    scanInputDirectory()
end

function editor.update() end

function editor.draw()
    local center_x, center_y = getPreviewCenter()

    love.graphics.clear(BACKGROUND_COLOR[1], BACKGROUND_COLOR[2], BACKGROUND_COLOR[3], BACKGROUND_COLOR[4])
    love.graphics.setColor(1, 1, 1, 1)
    drawImageAt(center_x, center_y, 1)
    drawHexMask(center_x, center_y)
    drawGamePreview()
    drawStatus()
end

function editor.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "r" then
        resetFraming()
    elseif key == "e" or key == "return" or key == "kpenter" then
        exportPng()
    elseif key == "o" then
        scanInputDirectory()
    elseif key == "right" or key == "n" then
        if #state.files > 0 then
            loadFile(state.index % #state.files + 1)
        end
    elseif key == "left" or key == "p" then
        if #state.files > 0 then
            loadFile((state.index - 2) % #state.files + 1)
        end
    elseif key == "0" then
        state.pan_x = 0
        state.pan_y = 0
    end
end

function editor.mousepressed(_, _, button)
    if button == 1 then
        state.dragging = true
    end
end

function editor.mousereleased(_, _, button)
    if button == 1 then
        state.dragging = false
    end
end

function editor.mousemoved(_, _, dx, dy)
    if not state.dragging then
        return
    end

    state.pan_x = state.pan_x + dx
    state.pan_y = state.pan_y + dy
end

function editor.wheelmoved(_, y)
    if y == 0 then
        return
    end

    local multiplier = y > 0 and 1.08 or 0.925

    state.scale = math.max(0.05, math.min(12, state.scale * multiplier))
end

return editor
