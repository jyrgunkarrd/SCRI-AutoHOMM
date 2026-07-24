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
local SPAWNER_COLOR = { 0, 62 / 255, 202 / 255, 1 }
local SPAWNER_OUTLINE_COLOR = { 1, 1, 1, 1 }
local SPAWNER_SIZE = 34
local NOTIFICATION_DURATION = 4
local NOTIFICATION_FADE_DURATION = 1
local EXIT_PANEL_WIDTH = 640
local EXIT_PANEL_HEIGHT = 240
local EXIT_BUTTON_WIDTH = 250
local EXIT_BUTTON_HEIGHT = 54
local EXIT_BUTTON_GAP = 24

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
    mapName = "untitled_map",
    mapNameInput = nil,
    palettes = {},
    paletteIndex = 1,
    selectedColor = 1,
    tiles = {},
    spawners = {},
    preparationTiles = {},
    spawnerInput = nil,
    wipFiles = {},
    wipIndex = 1,
    hoverCell = nil,
    painting = false,
    dirty = false,
    allowQuit = false,
    exitPromptOpen = false,
    message = "",
    messageTime = 0,
}

local function setMessage(message)
    state.message = message
    state.messageTime = NOTIFICATION_DURATION
end

local function markDirty()
    state.dirty = true
end

local function joinPath(...)
    return table.concat({ ... }, "/"):gsub("//+", "/")
end

local function trim(text)
    return text:match("^%s*(.-)%s*$")
end

local function getBaseName(path)
    local fileName = path:match("([^/]+)$") or path

    return (fileName:gsub("%.[^%.]+$", ""))
end

local function getMapFileName(mapName)
    local safeName = mapName
        :gsub("[%c/\\:*?\"<>|]", "_")
        :gsub("%s+", "_")
        :gsub("[^%w%._%-]", "_")
        :gsub("_+", "_")
        :gsub("^%.+", "")
        :gsub("%.+$", "")

    if safeName == "" then
        safeName = "map"
    end

    return safeName .. ".lua"
end

local function getExitPromptLayout()
    local panel = {
        x = (love.graphics.getWidth() - EXIT_PANEL_WIDTH) / 2,
        y = (love.graphics.getHeight() - EXIT_PANEL_HEIGHT) / 2,
        width = EXIT_PANEL_WIDTH,
        height = EXIT_PANEL_HEIGHT,
    }
    local buttonsWidth = EXIT_BUTTON_WIDTH * 2 + EXIT_BUTTON_GAP
    local buttonX = panel.x + (panel.width - buttonsWidth) / 2
    local buttonY = panel.y + panel.height - EXIT_BUTTON_HEIGHT - 28

    return {
        panel = panel,
        exit = {
            x = buttonX,
            y = buttonY,
            width = EXIT_BUTTON_WIDTH,
            height = EXIT_BUTTON_HEIGHT,
        },
        cancel = {
            x = buttonX + EXIT_BUTTON_WIDTH + EXIT_BUTTON_GAP,
            y = buttonY,
            width = EXIT_BUTTON_WIDTH,
            height = EXIT_BUTTON_HEIGHT,
        },
    }
end

local function requestExit()
    state.painting = false

    if state.dirty then
        state.exitPromptOpen = true
        return
    end

    state.allowQuit = true
    love.event.quit()
end

local function confirmExitWithoutSaving()
    state.allowQuit = true
    state.exitPromptOpen = false
    love.event.quit()
end

local function cancelExitPrompt()
    state.exitPromptOpen = false
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
                setMessage(("Skipped %s: %s"):format(fileName, tostring(paletteError)))
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
        setMessage("No palette images found; using the built-in palette.")
    else
        setMessage(("Loaded %d palette(s)."):format(#state.palettes))
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
    local changed = false

    for _, cell in ipairs(BattleMap.getCells()) do
        if state.tiles[cell.key] ~= 1 then
            changed = true
            break
        end
    end

    state.tiles = {}

    for _, cell in ipairs(BattleMap.getCells()) do
        state.tiles[cell.key] = 1
    end

    return changed
end

local function setTextInputEnabled(enabled)
    if love.keyboard and love.keyboard.setTextInput then
        love.keyboard.setTextInput(enabled)
    end
end

local function beginSpawnerEdit()
    local cell = state.hoverCell

    if not cell then
        setMessage("Hover a hex before pressing S.")
        return
    end

    state.painting = false
    state.spawnerInput = {
        cellKey = cell.key,
        original = state.spawners[cell.key],
        value = state.spawners[cell.key] or "",
        suppressInitialS = true,
    }
    setMessage("Enter a target string for spawner " .. cell.key)
    setTextInputEnabled(true)
end

local function finishSpawnerEdit()
    local input = state.spawnerInput

    if not input then
        return
    end

    if not input.value:match("%S") then
        setMessage("Spawner target cannot be empty.")
        return
    end

    if input.original ~= input.value then
        state.spawners[input.cellKey] = input.value
        markDirty()
    end
    setMessage(("Spawner %s targets %q."):format(input.cellKey, input.value))
    state.spawnerInput = nil
    setTextInputEnabled(false)
end

local function cancelSpawnerEdit()
    if not state.spawnerInput then
        return
    end

    state.spawnerInput = nil
    setMessage("Spawner edit cancelled.")
    setTextInputEnabled(false)
end

local function removeHoveredSpawner()
    local cell = state.hoverCell

    if not cell or not state.spawners[cell.key] then
        setMessage("The hovered hex has no spawner.")
        return
    end

    state.spawners[cell.key] = nil
    markDirty()
    setMessage("Removed spawner " .. cell.key)
end

local function toggleHoveredPreparationTile()
    local cell = state.hoverCell

    if not cell then
        setMessage("Hover a hex before pressing P.")
        return
    end

    state.painting = false

    if state.preparationTiles[cell.key] then
        state.preparationTiles[cell.key] = nil
        setMessage("Removed Preparation flag from " .. cell.key)
    else
        state.preparationTiles[cell.key] = true
        setMessage("Flagged " .. cell.key .. " as a Preparation tile.")
    end

    markDirty()
end

local function removeLastUtf8Character(text)
    local offset = #text

    while offset > 0 do
        local byte = text:byte(offset)

        if byte < 128 or byte >= 192 then
            break
        end

        offset = offset - 1
    end

    return text:sub(1, math.max(0, offset - 1))
end

local function beginMapNameEdit()
    state.painting = false
    state.mapNameInput = {
        value = state.mapName == "untitled_map" and "" or state.mapName,
        suppressInitialM = true,
    }
    setMessage("Enter a name for this map.")
    setTextInputEnabled(true)
end

local function finishMapNameEdit()
    local input = state.mapNameInput

    if not input then
        return
    end

    local name = trim(input.value)

    if not name:match("%S") then
        setMessage("Map name cannot be empty.")
        return
    end

    if state.mapName ~= name then
        state.mapName = name
        markDirty()
    end
    state.mapNameInput = nil
    setMessage("Map renamed to " .. name)
    setTextInputEnabled(false)
end

local function cancelMapNameEdit()
    if not state.mapNameInput then
        return
    end

    state.mapNameInput = nil
    setMessage("Map rename cancelled.")
    setTextInputEnabled(false)
end

local function changePalette(offset)
    if #state.palettes == 0 then
        return
    end

    local previousIndex = state.paletteIndex
    state.paletteIndex = (state.paletteIndex - 1 + offset) % #state.palettes + 1

    if state.paletteIndex ~= previousIndex then
        markDirty()
    end
    setMessage("Palette: " .. getCurrentPalette().name)
end

local function changeWip(offset)
    if #state.wipFiles == 0 then
        setMessage("No WIP maps found in " .. WIP_MAP_DIR)
        return
    end

    state.wipIndex = (state.wipIndex - 1 + offset) % #state.wipFiles + 1
    setMessage("Selected WIP: " .. state.wipFiles[state.wipIndex])
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
        setMessage("No WIP maps found in " .. WIP_MAP_DIR)
        return
    end

    local path = joinPath(WIP_MAP_DIR, fileName)
    local map, mapError = MapData.load(path)

    if not map then
        setMessage("Load failed: " .. tostring(mapError))
        return
    end

    activateMapPalette(map.palette)

    for _, cell in ipairs(BattleMap.getCells()) do
        state.tiles[cell.key] = map.tiles[cell.key] or 1
    end

    state.spawners = {}

    for key, target in pairs(map.spawners or {}) do
        state.spawners[key] = target
    end

    state.preparationTiles = {}

    for key, flagged in pairs(map.preparation_tiles or {}) do
        if flagged then
            state.preparationTiles[key] = true
        end
    end

    state.mapName = map.name or getBaseName(fileName)
    state.dirty = false
    setMessage("Loaded " .. fileName)
end

local function buildMapData()
    local palette = getCurrentPalette()
    local colors = {}
    local tiles = {}
    local spawners = {}
    local preparationTiles = {}

    for index, color in ipairs(palette.colors) do
        colors[index] = copyColor(color)
    end

    for _, cell in ipairs(BattleMap.getCells()) do
        tiles[cell.key] = state.tiles[cell.key] or 1

        if state.spawners[cell.key] then
            spawners[cell.key] = state.spawners[cell.key]
        end

        if state.preparationTiles[cell.key] then
            preparationTiles[cell.key] = true
        end
    end

    return {
        format = MapData.FORMAT,
        version = MapData.VERSION,
        name = state.mapName,
        palette = {
            name = palette.name,
            colors = colors,
        },
        tiles = tiles,
        spawners = spawners,
        preparation_tiles = preparationTiles,
    }
end

local function exportMap()
    local encoded, encodeError = MapData.encode(buildMapData())

    if not encoded then
        setMessage("Export failed: " .. tostring(encodeError))
        return
    end

    local sourceRoot = getSourceRoot():gsub("/+$", "")
    local nativeDirectory = joinPath(sourceRoot, SAVED_MAP_DIR):gsub("%z", "")
    local fileName = getMapFileName(state.mapName)
    local nativePath = joinPath(nativeDirectory, fileName)

    ensureNativeDirectory(nativeDirectory)

    local file, fileError = io.open(nativePath, "wb")

    if not file then
        setMessage("Export failed: " .. tostring(fileError))
        return
    end

    file:write(encoded)
    file:close()
    state.dirty = false
    setMessage("Exported " .. joinPath(SAVED_MAP_DIR, fileName))
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

local function drawSpawners()
    for _, cell in ipairs(BattleMap.getCells()) do
        local hasSpawner = state.spawners[cell.key] ~= nil
            or state.spawnerInput
                and state.spawnerInput.cellKey == cell.key

        if hasSpawner then
            local left = cell.x - SPAWNER_SIZE / 2
            local top = cell.y - SPAWNER_SIZE / 2

            love.graphics.setColor(SPAWNER_COLOR)
            love.graphics.rectangle(
                "fill",
                left,
                top,
                SPAWNER_SIZE,
                SPAWNER_SIZE
            )
            love.graphics.setColor(SPAWNER_OUTLINE_COLOR)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle(
                "line",
                left,
                top,
                SPAWNER_SIZE,
                SPAWNER_SIZE
            )
            love.graphics.printf(
                "S",
                left,
                cell.y - 8,
                SPAWNER_SIZE,
                "center"
            )
        end
    end
end

local function drawPreparationTiles()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.setLineWidth(3)

    for _, cell in ipairs(BattleMap.getCells()) do
        if state.preparationTiles[cell.key] then
            local vertices = BattleMap.getHexVertices(cell)
            local insetVertices = {}

            for index = 1, #vertices, 2 do
                insetVertices[index] = cell.x
                    + (vertices[index] - cell.x) * 0.62
                insetVertices[index + 1] = cell.y
                    + (vertices[index + 1] - cell.y) * 0.62
            end

            love.graphics.polygon("line", insetVertices)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

local function drawSpawnerInput()
    local input = state.spawnerInput

    if not input then
        return
    end

    local width = 760
    local height = 96
    local left = (love.graphics.getWidth() - width) / 2
    local top = 22

    love.graphics.setColor(PANEL_COLOR)
    love.graphics.rectangle("fill", left, top, width, height, 6, 6)
    love.graphics.setColor(SPAWNER_OUTLINE_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", left, top, width, height, 6, 6)
    love.graphics.print("SPAWNER TARGET — Enter to save, Esc to cancel", left + 16, top + 12)
    love.graphics.setColor(TEXT_COLOR)
    love.graphics.printf(
        input.value .. "_",
        left + 16,
        top + 48,
        width - 32,
        "left"
    )
end

local function drawMapNameInput()
    local input = state.mapNameInput

    if not input then
        return
    end

    local width = 760
    local height = 96
    local left = (love.graphics.getWidth() - width) / 2
    local top = 22

    love.graphics.setColor(PANEL_COLOR)
    love.graphics.rectangle("fill", left, top, width, height, 6, 6)
    love.graphics.setColor(SPAWNER_OUTLINE_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", left, top, width, height, 6, 6)
    love.graphics.print("MAP NAME — Enter to save, Esc to cancel", left + 16, top + 12)
    love.graphics.setColor(TEXT_COLOR)
    love.graphics.printf(
        input.value .. "_",
        left + 16,
        top + 48,
        width - 32,
        "left"
    )
end

local function drawPanel()
    local palette = getCurrentPalette()

    love.graphics.setColor(PANEL_COLOR)
    love.graphics.rectangle("fill", PANEL_X, PANEL_Y, PANEL_WIDTH, 880, 6, 6)

    love.graphics.setColor(TEXT_COLOR)
    love.graphics.print("MAP EDITOR", PANEL_X + 10, PANEL_Y + 12)
    love.graphics.setColor(MUTED_TEXT_COLOR)
    love.graphics.printf(
        "Map: " .. state.mapName
            .. (state.dirty and " *" or "")
            .. "\nPalette: " .. palette.name,
        PANEL_X + 10,
        PANEL_Y + 38,
        PANEL_WIDTH - 20,
        "left"
    )

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
        "[ / ] palette\n, / . WIP map\nL load  E export\n1-0 choose color\nM rename map\nS add/edit spawner\nP toggle Preparation\nDel remove spawner\nR reset  O rescan",
        PANEL_X + 10,
        wipY + 160,
        PANEL_WIDTH - 20,
        "left"
    )

    if state.hoverCell and state.spawners[state.hoverCell.key] then
        love.graphics.setColor(SPAWNER_OUTLINE_COLOR)
        love.graphics.printf(
            "Target:\n" .. state.spawners[state.hoverCell.key],
            PANEL_X + 10,
            wipY + 380,
            PANEL_WIDTH - 20,
            "left"
        )
    end
end

local function drawNotification()
    if state.message == "" or state.messageTime <= 0 then
        return
    end

    local alpha = math.min(
        1,
        state.messageTime / NOTIFICATION_FADE_DURATION
    )
    local width = 900
    local height = 58
    local left = (love.graphics.getWidth() - width) / 2
    local top = love.graphics.getHeight() - height - 20

    love.graphics.setColor(0, 0, 0, 0.88 * alpha)
    love.graphics.rectangle("fill", left, top, width, height, 6, 6)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.printf(
        state.message,
        left + 18,
        top + 20,
        width - 36,
        "center"
    )
end

local function drawExitPromptButton(label, bounds, color)
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
        bounds.y + 18,
        bounds.width,
        "center"
    )
end

local function drawUnsavedExitPrompt()
    if not state.exitPromptOpen then
        return
    end

    local layout = getExitPromptLayout()
    local panel = layout.panel

    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.rectangle(
        "fill",
        0,
        0,
        love.graphics.getWidth(),
        love.graphics.getHeight()
    )
    love.graphics.setColor(0.025, 0.03, 0.04, 0.99)
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
        "UNSAVED CHANGES",
        panel.x,
        panel.y + 34,
        panel.width,
        "center"
    )
    love.graphics.printf(
        "This map has changes that have not been exported.\nExit without saving them?",
        panel.x + 30,
        panel.y + 78,
        panel.width - 60,
        "center"
    )

    drawExitPromptButton(
        "EXIT WITHOUT SAVING",
        layout.exit,
        { 0.62, 0.12, 0.12, 1 }
    )
    drawExitPromptButton(
        "CANCEL",
        layout.cancel,
        { 0.16, 0.2, 0.28, 1 }
    )
    love.graphics.setColor(1, 1, 1, 1)
end

local function paintAt(x, y)
    local cell = BattleMap.getHexAt(x, y)

    if cell and state.tiles[cell.key] ~= state.selectedColor then
        state.tiles[cell.key] = state.selectedColor
        markDirty()
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
            setMessage(("Selected color %d."):format(index))
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
    state.mapName = "untitled_map"
    state.mapNameInput = nil
    state.spawners = {}
    state.preparationTiles = {}
    state.spawnerInput = nil
    state.dirty = false
    state.allowQuit = false
    state.exitPromptOpen = false
end

function editor.update(dt)
    state.messageTime = math.max(0, state.messageTime - dt)
end

function editor.draw()
    love.graphics.clear(
        BACKGROUND_COLOR[1],
        BACKGROUND_COLOR[2],
        BACKGROUND_COLOR[3],
        BACKGROUND_COLOR[4]
    )
    BattleMap.draw(getColorMap())
    drawPreparationTiles()
    drawSpawners()

    if state.hoverCell then
        BattleMap.drawHexOutline(state.hoverCell, HOVER_COLOR, 3)
    end

    drawPanel()
    drawSpawnerInput()
    drawMapNameInput()
    drawNotification()
    drawUnsavedExitPrompt()
    love.graphics.setColor(1, 1, 1, 1)
end

function editor.keypressed(key)
    if state.spawnerInput then
        if key == "return" or key == "kpenter" then
            finishSpawnerEdit()
        elseif key == "escape" then
            cancelSpawnerEdit()
        elseif key == "backspace" then
            state.spawnerInput.value = removeLastUtf8Character(
                state.spawnerInput.value
            )
        end

        return
    end

    if state.mapNameInput then
        if key == "return" or key == "kpenter" then
            finishMapNameEdit()
        elseif key == "escape" then
            cancelMapNameEdit()
        elseif key == "backspace" then
            state.mapNameInput.value = removeLastUtf8Character(
                state.mapNameInput.value
            )
        end

        return
    end

    if state.exitPromptOpen then
        if key == "escape" then
            cancelExitPrompt()
        end

        return
    end

    if key == "escape" then
        requestExit()
    elseif key == "m" then
        beginMapNameEdit()
    elseif key == "s" then
        beginSpawnerEdit()
    elseif key == "p" then
        toggleHoveredPreparationTile()
    elseif key == "delete" then
        removeHoveredSpawner()
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
        if resetTiles() then
            markDirty()
            setMessage("Reset every hex to color 1.")
        else
            setMessage("Every hex already uses color 1.")
        end
    elseif key == "o" then
        scanPalettes()
        scanWipMaps()
        setMessage("Rescanned palettes and WIP maps.")
    elseif key:match("^[1-9]$") then
        state.selectedColor = tonumber(key)
    elseif key == "0" then
        state.selectedColor = 10
    end
end

function editor.textinput(text)
    local spawnerInput = state.spawnerInput

    if spawnerInput then
        if spawnerInput.suppressInitialS then
            spawnerInput.suppressInitialS = false

            if text:lower() == "s" then
                return
            end
        end

        if #spawnerInput.value + #text <= MapData.MAX_SPAWNER_TARGET_LENGTH then
            spawnerInput.value = spawnerInput.value .. text
        else
            setMessage((
                "Spawner targets are limited to %d bytes."
            ):format(MapData.MAX_SPAWNER_TARGET_LENGTH))
        end

        return
    end

    local mapNameInput = state.mapNameInput

    if mapNameInput then
        if mapNameInput.suppressInitialM then
            mapNameInput.suppressInitialM = false

            if text:lower() == "m" then
                return
            end
        end

        if #mapNameInput.value + #text <= MapData.MAX_MAP_NAME_LENGTH then
            mapNameInput.value = mapNameInput.value .. text
        else
            setMessage((
                "Map names are limited to %d bytes."
            ):format(MapData.MAX_MAP_NAME_LENGTH))
        end
    end
end

function editor.mousepressed(x, y, button)
    if state.exitPromptOpen then
        if button == 2 then
            cancelExitPrompt()
        elseif button == 1 then
            local layout = getExitPromptLayout()

            if isInside(
                x,
                y,
                layout.exit.x,
                layout.exit.y,
                layout.exit.width,
                layout.exit.height
            ) then
                confirmExitWithoutSaving()
            elseif isInside(
                x,
                y,
                layout.cancel.x,
                layout.cancel.y,
                layout.cancel.width,
                layout.cancel.height
            ) or not isInside(
                x,
                y,
                layout.panel.x,
                layout.panel.y,
                layout.panel.width,
                layout.panel.height
            ) then
                cancelExitPrompt()
            end
        end

        return
    end

    if button ~= 1 or state.spawnerInput or state.mapNameInput then
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

function editor.quit()
    if state.allowQuit or not state.dirty then
        return false
    end

    state.painting = false
    state.exitPromptOpen = true

    return true
end

function editor.hasUnsavedChanges()
    return state.dirty
end

function editor.isExitPromptOpen()
    return state.exitPromptOpen
end

return editor
