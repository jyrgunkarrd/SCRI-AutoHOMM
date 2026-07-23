local BattleMap = require("src.sys.battle_map")
local MapData = require("src.sys.map_data")

local editor = {}

local PALETTE_DIR = "assets/images/map_palettes"
local SAVED_MAP_DIR = "assets/maps/saved_maps"
local WIP_MAP_DIR = "assets/maps/wip_maps"
local FONT_PATH = "assets/fonts/Furore.otf"

local PANEL_X = 16
local PANEL_Y = 170
local PANEL_WIDTH = 180
local BUTTON_HEIGHT = 34
local SWATCH_SIZE = 48
local SWATCH_GAP = 8
local SWATCH_START_Y = 286

local BACKGROUND_COLOR = { 0.055, 0.065, 0.09, 1 }
local PANEL_COLOR = { 0.025, 0.03, 0.045, 0.94 }
local TEXT_COLOR = { 0.88, 0.9, 0.94, 1 }
local MUTED_TEXT_COLOR = { 0.58, 0.62, 0.68, 1 }
local HOVER_COLOR = { 1, 1, 1, 0.9 }
local SELECTED_COLOR = { 1, 1, 1, 1 }

local FALLBACK_PALETTE = {
    { 0.12, 0.18, 0.24, 1 },
    { 0.36, 0.66, 0.78, 1 },
    { 0.22, 0.42, 0.34, 1 },
    { 0.48, 0.66, 0.38, 1 },
    { 0.78, 0.72, 0.38, 1 },
    { 0.82, 0.50, 0.28, 1 },
    { 0.76, 0.28, 0.27, 1 },
    { 0.58, 0.30, 0.62, 1 },
    { 0.78, 0.60, 0.82, 1 },
    { 0.84, 0.86, 0.88, 1 },
}

local state = {
    palettes = {},
    paletteIndex = 1,
    selectedColor = 1,
    tiles = {},
    wipFiles = {},
    wipIndex = 1,
    hoverCell = nil,
    painting = false,
    message = "",
}

local function joinPath(...)
    return table.concat({ ... }, "/"):gsub("//+", "/")
end

local function isInside(x, y, left, top, width, height)
    return x >= left and x <= left + width
        and y >= top and y <= top + height
end

local function isSupportedImage(fileName)
    local extension = fileName:match("%.([^%.]+)$")

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

local function shellQuote(path)
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function ensureNativeDirectory(path)
    if package.config:sub(1, 1) == "\\" then
        os.execute('mkdir "' .. path:gsub('"', '""') .. '" 2>nul')
    else
        os.execute("mkdir -p " .. shellQuote(path))
    end
end

local function copyColor(color)
    return { color[1], color[2], color[3], color[4] or 1 }
end

local function colorsMatch(left, right)
    for index = 1, MapData.PALETTE_SIZE do
        for channel = 1, 4 do
            if math.abs(left[index][channel] - right[index][channel]) > 0.000001 then
                return false
            end
        end
    end

    return true
end

local function getCurrentPalette()
    return state.palettes[state.paletteIndex]
end

local function loadPaletteImageData(path)
    if path:lower():match("%.webp$") then
        local bytes, readError = love.filesystem.read(path)

        if not bytes then
            return nil, readError
        end

        local imageData = require("src.render.love-webp").loadImage(bytes)

        if not imageData then
            return nil, "unable to decode WebP palette"
        end

        return imageData
    end

    local ok, imageData = pcall(love.image.newImageData, path)

    if not ok then
        return nil, imageData
    end

    return imageData
end

local function readPalette(path, fileName)
    local imageData, imageError = loadPaletteImageData(path)

    if not imageData then
        return nil, imageError
    end

    local width, height = imageData:getDimensions()

    if width < MapData.PALETTE_SIZE
        and height < MapData.PALETTE_SIZE then
        return nil, "palette image must be at least 10 pixels wide or tall"
    end

    local horizontal = width >= height
    local colors = {}

    for index = 1, MapData.PALETTE_SIZE do
        local x
        local y

        if horizontal then
            x = math.min(width - 1, math.floor((index - 0.5) * width / MapData.PALETTE_SIZE))
            y = math.floor(height / 2)
        else
            x = math.floor(width / 2)
            y = math.min(height - 1, math.floor((index - 0.5) * height / MapData.PALETTE_SIZE))
        end

        local red, green, blue, alpha = imageData:getPixel(x, y)
        colors[index] = { red, green, blue, alpha }
    end

    return {
        name = fileName,
        colors = colors,
    }
end

local function scanPalettes()
    love.filesystem.createDirectory(PALETTE_DIR)
    state.palettes = {}

    local items = love.filesystem.getDirectoryItems(PALETTE_DIR)
    table.sort(items)

    for _, fileName in ipairs(items) do
        if isSupportedImage(fileName) then
            local path = joinPath(PALETTE_DIR, fileName)
            local palette, paletteError = readPalette(path, fileName)

            if palette then
                state.palettes[#state.palettes + 1] = palette
            else
                state.message = ("Skipped %s: %s"):format(fileName, tostring(paletteError))
            end
        end
    end

    if #state.palettes == 0 then
        local colors = {}

        for index, color in ipairs(FALLBACK_PALETTE) do
            colors[index] = copyColor(color)
        end

        state.palettes[1] = {
            name = "Built-in Default",
            colors = colors,
        }
        state.message = "No palette images found; using the built-in palette."
    else
        state.message = ("Loaded %d palette(s)."):format(#state.palettes)
    end

    state.paletteIndex = math.min(state.paletteIndex, #state.palettes)
end

local function scanWipMaps()
    love.filesystem.createDirectory(WIP_MAP_DIR)
    state.wipFiles = {}

    for _, fileName in ipairs(love.filesystem.getDirectoryItems(WIP_MAP_DIR)) do
        local path = joinPath(WIP_MAP_DIR, fileName)
        local info = love.filesystem.getInfo(path)

        if info and info.type == "file" and fileName:lower():match("%.lua$") then
            state.wipFiles[#state.wipFiles + 1] = fileName
        end
    end

    table.sort(state.wipFiles)
    state.wipIndex = math.min(state.wipIndex, math.max(1, #state.wipFiles))
end

local function resetTiles()
    state.tiles = {}

    for _, cell in ipairs(BattleMap.getCells()) do
        state.tiles[cell.key] = 1
    end
end

local function changePalette(offset)
    if #state.palettes == 0 then
        return
    end

    state.paletteIndex = (state.paletteIndex - 1 + offset) % #state.palettes + 1
    state.message = "Palette: " .. getCurrentPalette().name
end

local function changeWip(offset)
    if #state.wipFiles == 0 then
        state.message = "No WIP maps found in " .. WIP_MAP_DIR
        return
    end

    state.wipIndex = (state.wipIndex - 1 + offset) % #state.wipFiles + 1
    state.message = "Selected WIP: " .. state.wipFiles[state.wipIndex]
end

local function activateMapPalette(mapPalette)
    for index, palette in ipairs(state.palettes) do
        if palette.name == mapPalette.name
            and colorsMatch(palette.colors, mapPalette.colors) then
            state.paletteIndex = index
            return
        end
    end

    local colors = {}

    for index, color in ipairs(mapPalette.colors) do
        colors[index] = copyColor(color)
    end

    state.palettes[#state.palettes + 1] = {
        name = mapPalette.name,
        colors = colors,
    }
    state.paletteIndex = #state.palettes
end

local function loadSelectedWip()
    local fileName = state.wipFiles[state.wipIndex]

    if not fileName then
        state.message = "No WIP maps found in " .. WIP_MAP_DIR
        return
    end

    local path = joinPath(WIP_MAP_DIR, fileName)
    local map, mapError = MapData.load(path)

    if not map then
        state.message = "Load failed: " .. tostring(mapError)
        return
    end

    activateMapPalette(map.palette)

    for _, cell in ipairs(BattleMap.getCells()) do
        state.tiles[cell.key] = map.tiles[cell.key] or 1
    end

    state.message = "Loaded " .. fileName
end

local function buildMapData()
    local palette = getCurrentPalette()
    local colors = {}
    local tiles = {}

    for index, color in ipairs(palette.colors) do
        colors[index] = copyColor(color)
    end

    for _, cell in ipairs(BattleMap.getCells()) do
        tiles[cell.key] = state.tiles[cell.key] or 1
    end

    return {
        format = MapData.FORMAT,
        version = MapData.VERSION,
        palette = {
            name = palette.name,
            colors = colors,
        },
        tiles = tiles,
    }
end

local function exportMap()
    local encoded, encodeError = MapData.encode(buildMapData())

    if not encoded then
        state.message = "Export failed: " .. tostring(encodeError)
        return
    end

    local sourceRoot = getSourceRoot():gsub("/+$", "")
    local nativeDirectory = joinPath(sourceRoot, SAVED_MAP_DIR):gsub("%z", "")
    local fileName = os.date("map_%Y%m%d_%H%M%S.lua")
    local nativePath = joinPath(nativeDirectory, fileName)

    ensureNativeDirectory(nativeDirectory)

    local file, fileError = io.open(nativePath, "wb")

    if not file then
        state.message = "Export failed: " .. tostring(fileError)
        return
    end

    file:write(encoded)
    file:close()
    state.message = "Exported " .. joinPath(SAVED_MAP_DIR, fileName)
end

local function getColorMap()
    local palette = getCurrentPalette()
    local colorMap = {}

    for _, cell in ipairs(BattleMap.getCells()) do
        colorMap[cell.key] = palette.colors[state.tiles[cell.key] or 1]
    end

    return colorMap
end

local function drawButton(label, x, y, width, active)
    love.graphics.setColor(active and 0.25 or 0.12, active and 0.38 or 0.15, active and 0.48 or 0.2, 1)
    love.graphics.rectangle("fill", x, y, width, BUTTON_HEIGHT, 4, 4)
    love.graphics.setColor(TEXT_COLOR)
    love.graphics.printf(label, x, y + 8, width, "center")
end

local function drawPanel()
    local palette = getCurrentPalette()

    love.graphics.setColor(PANEL_COLOR)
    love.graphics.rectangle("fill", PANEL_X, PANEL_Y, PANEL_WIDTH, 880, 6, 6)

    love.graphics.setColor(TEXT_COLOR)
    love.graphics.print("MAP EDITOR", PANEL_X + 10, PANEL_Y + 12)
    love.graphics.setColor(MUTED_TEXT_COLOR)
    love.graphics.printf(palette.name, PANEL_X + 10, PANEL_Y + 42, PANEL_WIDTH - 20, "left")

    drawButton("<", PANEL_X + 10, PANEL_Y + 76, 72, #state.palettes > 1)
    drawButton(">", PANEL_X + 98, PANEL_Y + 76, 72, #state.palettes > 1)

    for index, color in ipairs(palette.colors) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local x = PANEL_X + 30 + column * (SWATCH_SIZE + SWATCH_GAP)
        local y = SWATCH_START_Y + row * (SWATCH_SIZE + SWATCH_GAP)

        love.graphics.setColor(color)
        love.graphics.rectangle("fill", x, y, SWATCH_SIZE, SWATCH_SIZE, 4, 4)
        love.graphics.setColor(index == state.selectedColor and SELECTED_COLOR or { 0, 0, 0, 0.8 })
        love.graphics.setLineWidth(index == state.selectedColor and 4 or 2)
        love.graphics.rectangle("line", x, y, SWATCH_SIZE, SWATCH_SIZE, 4, 4)
        love.graphics.setColor(TEXT_COLOR)
        love.graphics.print(index == 10 and "0" or tostring(index), x + 5, y + 3)
    end

    local wipY = 590
    love.graphics.setColor(TEXT_COLOR)
    love.graphics.print("WIP MAP", PANEL_X + 10, wipY)
    love.graphics.setColor(MUTED_TEXT_COLOR)
    love.graphics.printf(
        state.wipFiles[state.wipIndex] or "(none)",
        PANEL_X + 10,
        wipY + 25,
        PANEL_WIDTH - 20,
        "left"
    )
    drawButton("<", PANEL_X + 10, wipY + 65, 48, #state.wipFiles > 1)
    drawButton("LOAD", PANEL_X + 64, wipY + 65, 62, #state.wipFiles > 0)
    drawButton(">", PANEL_X + 132, wipY + 65, 38, #state.wipFiles > 1)
    drawButton("EXPORT", PANEL_X + 10, wipY + 109, 160, true)

    love.graphics.setColor(MUTED_TEXT_COLOR)
    love.graphics.printf(
        "[ / ] palette\n, / . WIP map\nL load  E export\n1-0 choose color\nR reset  O rescan",
        PANEL_X + 10,
        wipY + 160,
        PANEL_WIDTH - 20,
        "left"
    )

    love.graphics.setColor(TEXT_COLOR)
    love.graphics.printf(
        state.message,
        PANEL_X + 10,
        wipY + 270,
        PANEL_WIDTH - 20,
        "left"
    )
end

local function paintAt(x, y)
    local cell = BattleMap.getHexAt(x, y)

    if cell then
        state.tiles[cell.key] = state.selectedColor
    end
end

local function handlePanelClick(x, y)
    if isInside(x, y, PANEL_X + 10, PANEL_Y + 76, 72, BUTTON_HEIGHT) then
        changePalette(-1)
        return true
    elseif isInside(x, y, PANEL_X + 98, PANEL_Y + 76, 72, BUTTON_HEIGHT) then
        changePalette(1)
        return true
    end

    for index = 1, MapData.PALETTE_SIZE do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local swatchX = PANEL_X + 30 + column * (SWATCH_SIZE + SWATCH_GAP)
        local swatchY = SWATCH_START_Y + row * (SWATCH_SIZE + SWATCH_GAP)

        if isInside(x, y, swatchX, swatchY, SWATCH_SIZE, SWATCH_SIZE) then
            state.selectedColor = index
            state.message = ("Selected color %d."):format(index)
            return true
        end
    end

    local wipY = 590

    if isInside(x, y, PANEL_X + 10, wipY + 65, 48, BUTTON_HEIGHT) then
        changeWip(-1)
        return true
    elseif isInside(x, y, PANEL_X + 64, wipY + 65, 62, BUTTON_HEIGHT) then
        loadSelectedWip()
        return true
    elseif isInside(x, y, PANEL_X + 132, wipY + 65, 38, BUTTON_HEIGHT) then
        changeWip(1)
        return true
    elseif isInside(x, y, PANEL_X + 10, wipY + 109, 160, BUTTON_HEIGHT) then
        exportMap()
        return true
    end

    return isInside(x, y, PANEL_X, PANEL_Y, PANEL_WIDTH, 880)
end

function editor.load()
    love.window.setTitle("SCRI AutoHOMM Map Editor")
    love.graphics.setBackgroundColor(BACKGROUND_COLOR)
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setFont(love.graphics.newFont(FONT_PATH, 15))

    love.filesystem.createDirectory(SAVED_MAP_DIR)
    scanPalettes()
    scanWipMaps()
    resetTiles()
end

function editor.update() end

function editor.draw()
    love.graphics.clear(
        BACKGROUND_COLOR[1],
        BACKGROUND_COLOR[2],
        BACKGROUND_COLOR[3],
        BACKGROUND_COLOR[4]
    )
    BattleMap.draw(getColorMap())

    if state.hoverCell then
        BattleMap.drawHexOutline(state.hoverCell, HOVER_COLOR, 3)
    end

    drawPanel()
    love.graphics.setColor(1, 1, 1, 1)
end

function editor.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "[" then
        changePalette(-1)
    elseif key == "]" then
        changePalette(1)
    elseif key == "," then
        changeWip(-1)
    elseif key == "." then
        changeWip(1)
    elseif key == "l" then
        loadSelectedWip()
    elseif key == "e" then
        exportMap()
    elseif key == "r" then
        resetTiles()
        state.message = "Reset every hex to color 1."
    elseif key == "o" then
        scanPalettes()
        scanWipMaps()
        state.message = "Rescanned palettes and WIP maps."
    elseif key:match("^[1-9]$") then
        state.selectedColor = tonumber(key)
    elseif key == "0" then
        state.selectedColor = 10
    end
end

function editor.mousepressed(x, y, button)
    if button ~= 1 then
        return
    end

    if handlePanelClick(x, y) then
        return
    end

    state.painting = true
    paintAt(x, y)
end

function editor.mousereleased(_, _, button)
    if button == 1 then
        state.painting = false
    end
end

function editor.mousemoved(x, y)
    state.hoverCell = BattleMap.getHexAt(x, y)

    if state.painting then
        paintAt(x, y)
    end
end

return editor
