local ImageLoader = require("src.assets.image_loader")
local BattleMap = require("src.sys.battle_map")
local MapPathfindingLogic = require("src.sys.map_pathfinding_logic")
local Sfx = require("src.sys.sfx")

local AgentLogic = {}

local PORTRAIT_DIR = "assets/images/agents"
local PORTRAIT_DIAMETER_IN_HEX_RADII = {
    [1] = 2,
    [2] = 5,
}
local PORTRAIT_OUTLINE_COLOR = { 0, 0, 0, 1 }
local PORTRAIT_OUTLINE_WIDTH = 4
local EXHAUSTED_PORTRAIT_OPACITY = 0.4
local PROFILE_MARGIN = 12
local PROFILE_PADDING = 12
local PROFILE_TOP = 18
local PROFILE_MIN_WIDTH = 160
local PROFILE_BACKGROUND_COLOR = { 0.025, 0.03, 0.04, 0.96 }
local PROFILE_BORDER_COLOR = { 0.72, 0.76, 0.84, 1 }
local PROFILE_TEXT_COLOR = { 1, 1, 1, 1 }
local PROFILE_MUTED_COLOR = { 0.62, 0.67, 0.74, 1 }
local PROFILE_STAT_COLOR = { 0.10, 0.12, 0.16, 1 }
local INVENTORY_SLOT_COLOR = { 0.065, 0.075, 0.095, 1 }
local INVENTORY_SLOT_BORDER_COLOR = { 0.48, 0.52, 0.60, 1 }
local INVENTORY_SLOT_ICON_OPACITY = 0.5
local INVENTORY_SLOT_COLUMNS = 2
local INVENTORY_SLOT_ROWS = 5
local INVENTORY_SLOT_GAP = 8
local INVENTORY_ICON_PADDING = 9
local SLOT_ICON_DIR = "assets/images/icons"
local AGENCY_ICON_PATH = "assets/images/icons/agency.webp"
local AGENCY_BUTTON_SIZE = 64
local AGENCY_BUTTON_GAP = 12
local AGENCY_BUTTON_COLOR = { 0.12, 0.15, 0.22, 1 }
local SLOT_ICON_ALIASES = {
    legs = "foot",
}
local PULSE_SPEED = 3
local PULSE_AMOUNT = 0.08
local SHOUT_CHARACTERS_PER_SECOND = 58
local SHOUT_MIN_TYPE_DURATION = 0.08
local SHOUT_CHARACTER_FADE_DURATION = 0.04
local SHOUT_HOLD_DURATION = 0.75
local SHOUT_FADE_DURATION = 0.45
local SHOUT_MAX_TEXT_WIDTH = 276
local SHOUT_MIN_BOX_WIDTH = 40
local SHOUT_PADDING_X = 10
local SHOUT_PADDING_Y = 7
local SHOUT_BOX_COLOR = { 1, 1, 1, 0.96 }
local SHOUT_BORDER_COLOR = { 0, 0, 0, 1 }
local SHOUT_TEXT_COLOR = { 0, 0, 0, 1 }
local SHOUT_BORDER_WIDTH = 3
local AGENT_MOVEMENT_FILL_COLOR = { 1, 1, 1, 0.22 }
local HOSTILE_MOVEMENT_FILL_COLOR = { 1, 0, 73 / 255, 0.28 }
local MOVEMENT_OUTLINE_COLOR = { 0, 0, 0, 0.90 }
local MOVEMENT_OUTLINE_WIDTH = 2

local selectedAgent
local pulseTime = 0
local activeShout
local movementCells = {}
local slotIconCache = {}
local missingSlotIcons = {}
local agencyButtonIcon
local agencyButtonIconMissing = false
local agencyButtonBounds

local function buildHexPoints(centerX, centerY, radius)
    local points = {}

    for corner = 0, 5 do
        local angle = math.rad(60 * corner - 30)
        points[#points + 1] = centerX + radius * math.cos(angle)
        points[#points + 1] = centerY + radius * math.sin(angle)
    end

    return points
end

local function scalePointsFromCenter(points, centerX, centerY, scale)
    local scaled = {}

    for index = 1, #points, 2 do
        scaled[index] = centerX + (points[index] - centerX) * scale
        scaled[index + 1] = centerY
            + (points[index + 1] - centerY) * scale
    end

    return scaled
end

local function getUtf8CharacterCount(text)
    local count = 0

    for index = 1, #text do
        local byte = text:byte(index)

        if byte < 128 or byte >= 192 then
            count = count + 1
        end
    end

    return count
end

local function getUtf8Prefix(text, characterCount)
    if characterCount <= 0 then
        return ""
    end

    local count = 0

    for index = 1, #text do
        local byte = text:byte(index)

        if byte < 128 or byte >= 192 then
            count = count + 1

            if count > characterCount then
                return text:sub(1, index - 1)
            end
        end
    end

    return text
end

local function getUtf8Characters(text)
    local characters = {}
    local characterStart

    for index = 1, #text do
        local byte = text:byte(index)

        if byte < 128 or byte >= 192 then
            if characterStart then
                characters[#characters + 1] = text:sub(
                    characterStart,
                    index - 1
                )
            end

            characterStart = index
        end
    end

    if characterStart then
        characters[#characters + 1] = text:sub(characterStart)
    end

    return characters
end

local function getShoutTextLayout(text)
    if not love.graphics.getFont then
        return {
            lines = { text },
            textWidth = SHOUT_MAX_TEXT_WIDTH,
            lineHeight = 22,
            characterCount = getUtf8CharacterCount(text),
        }
    end

    local font = love.graphics.getFont()
    local unwrappedWidth = font:getWidth(text)
    local wrappedWidth
    local lines

    if unwrappedWidth <= SHOUT_MAX_TEXT_WIDTH
        and not text:find("\n", 1, true) then
        wrappedWidth = unwrappedWidth
        lines = { text }
    else
        wrappedWidth, lines = font:getWrap(
            text,
            SHOUT_MAX_TEXT_WIDTH
        )
    end

    local characterCount = 0

    for _, line in ipairs(lines) do
        characterCount = characterCount + getUtf8CharacterCount(line)
    end

    return {
        font = font,
        lines = lines,
        textWidth = math.min(wrappedWidth, SHOUT_MAX_TEXT_WIDTH),
        lineHeight = font:getHeight() * font:getLineHeight(),
        characterCount = characterCount,
    }
end

local function drawSmoothTypewriter(layout, progress, x, y, alpha)
    if not layout.font then
        local visibleCharacters = math.min(
            layout.characterCount,
            math.floor(progress)
        )

        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.printf(
            getUtf8Prefix(layout.lines[1], visibleCharacters),
            x,
            y,
            layout.textWidth,
            "center"
        )
        return
    end

    local characterIndex = 0
    local fadeLengthInCharacters = SHOUT_CHARACTERS_PER_SECOND
        * SHOUT_CHARACTER_FADE_DURATION

    for lineIndex, line in ipairs(layout.lines) do
        local characters = getUtf8Characters(line)
        local lineWidth = layout.font:getWidth(line)
        local characterX = x + (layout.textWidth - lineWidth) / 2
        local characterY = y + (lineIndex - 1) * layout.lineHeight

        for _, character in ipairs(characters) do
            local visibility = characterIndex == 0
                and 1
                or math.max(
                    0,
                    math.min(
                        1,
                        (progress - characterIndex)
                            / fadeLengthInCharacters
                    )
                )

            if visibility > 0 and character ~= " " then
                love.graphics.setColor(
                    SHOUT_TEXT_COLOR[1],
                    SHOUT_TEXT_COLOR[2],
                    SHOUT_TEXT_COLOR[3],
                    alpha * visibility
                )
                love.graphics.print(character, characterX, characterY)
            end

            characterX = characterX + layout.font:getWidth(character)
            characterIndex = characterIndex + 1
        end
    end
end

local function getShoutTypeDuration(characterCount)
    if characterCount <= 0 then
        return 0
    end

    return math.max(
        characterCount / SHOUT_CHARACTERS_PER_SECOND,
        SHOUT_MIN_TYPE_DURATION
    )
end

local function beginShout(entity)
    local text = entity.definition.shout
        or entity.definition.shout_select

    if type(text) ~= "string" or not text:match("%S") then
        activeShout = nil
        return
    end

    local layout = getShoutTextLayout(text)

    activeShout = {
        entity = entity,
        text = text,
        characterCount = layout.characterCount,
        layout = layout,
        elapsed = 0,
    }
end

local function drawShout(entity, diameter)
    local shout = activeShout

    if not shout or shout.entity ~= entity then
        return
    end

    local typeDuration = getShoutTypeDuration(shout.characterCount)
    local fadeStart = typeDuration + SHOUT_HOLD_DURATION
    local alpha = 1

    if shout.elapsed > fadeStart then
        alpha = math.max(
            0,
            1 - (shout.elapsed - fadeStart) / SHOUT_FADE_DURATION
        )
    end

    local typedRatio = typeDuration > 0
        and math.min(shout.elapsed / typeDuration, 1)
        or 1
    local fadeLengthInCharacters = SHOUT_CHARACTERS_PER_SECOND
        * SHOUT_CHARACTER_FADE_DURATION
    local characterProgress = math.min(
        shout.characterCount + fadeLengthInCharacters,
        math.max(
            1,
            typedRatio * shout.characterCount
                + math.max(0, shout.elapsed - typeDuration)
                    * SHOUT_CHARACTERS_PER_SECOND
        )
    )
    local completedCharacters = math.min(
        shout.characterCount,
        math.floor(characterProgress)
    )
    local nextCharacter = math.min(
        shout.characterCount,
        completedCharacters + 1
    )
    local dimensionProgress = characterProgress
        - math.floor(characterProgress)
    local completedLayout = getShoutTextLayout(
        getUtf8Prefix(shout.text, completedCharacters)
    )
    local layout = getShoutTextLayout(
        getUtf8Prefix(shout.text, nextCharacter)
    )
    local animatedTextWidth = completedLayout.textWidth
        + (layout.textWidth - completedLayout.textWidth)
            * dimensionProgress
    local completedTextHeight = #completedLayout.lines
        * completedLayout.lineHeight
    local nextTextHeight = #layout.lines * layout.lineHeight
    local animatedTextHeight = completedTextHeight
        + (nextTextHeight - completedTextHeight)
            * dimensionProgress
    local boxWidth = math.max(
        SHOUT_MIN_BOX_WIDTH,
        animatedTextWidth + SHOUT_PADDING_X * 2
    )
    local boxHeight = animatedTextHeight + SHOUT_PADDING_Y * 2
    local x = entity.anchor.x - boxWidth / 2
    local y = entity.anchor.y + diameter * 0.08
    local textX = x + SHOUT_PADDING_X

    love.graphics.setColor(
        SHOUT_BOX_COLOR[1],
        SHOUT_BOX_COLOR[2],
        SHOUT_BOX_COLOR[3],
        SHOUT_BOX_COLOR[4] * alpha
    )
    love.graphics.rectangle(
        "fill",
        x,
        y,
        boxWidth,
        boxHeight
    )
    love.graphics.setColor(
        SHOUT_BORDER_COLOR[1],
        SHOUT_BORDER_COLOR[2],
        SHOUT_BORDER_COLOR[3],
        alpha
    )
    love.graphics.setLineWidth(SHOUT_BORDER_WIDTH)
    love.graphics.rectangle(
        "line",
        x,
        y,
        boxWidth,
        boxHeight
    )
    love.graphics.setLineWidth(1)
    drawSmoothTypewriter(
        layout,
        characterProgress,
        textX,
        y + SHOUT_PADDING_Y,
        alpha
    )
end

local function getPulseScale(entity)
    if entity ~= selectedAgent then
        return 1
    end

    return 1 + math.sin(pulseTime * PULSE_SPEED) * PULSE_AMOUNT
end

local function getSpeed(definition)
    for _, statEntry in ipairs(definition.stats or {}) do
        if type(statEntry.spd) == "number" then
            return math.max(0, statEntry.spd)
        end
    end

    return 0
end

local function refreshMovementRange(entity)
    local speed = getSpeed(entity.definition)
    local cells = MapPathfindingLogic.getReachableCells(
        entity.anchor,
        speed,
        {
            includeStart = false,
        }
    )

    movementCells = cells or {}
end

local function getPortraitPath(definition)
    if not definition.id:match("^[%w_%-]+$") then
        return nil, "Agent id contains characters that are unsafe in an image path"
    end

    return ("%s/%s_hex.webp"):format(PORTRAIT_DIR, definition.id)
end

local function getProfileImagePath(definition)
    if not definition.id:match("^[%w_%-]+$") then
        return nil, "Agent id contains characters that are unsafe in an image path"
    end

    return ("%s/%s.webp"):format(PORTRAIT_DIR, definition.id)
end

local function getSlotIconPath(slotName)
    if type(slotName) ~= "string" or not slotName:match("%S") then
        return nil
    end

    local iconName = slotName:lower()
        :gsub("%s+", "_")
        :gsub("[^%w_%-]", "")

    iconName = SLOT_ICON_ALIASES[iconName] or iconName

    return ("%s/slot_%s.webp"):format(SLOT_ICON_DIR, iconName)
end

local function getSlotIcon(slotName)
    local path = getSlotIconPath(slotName)

    if not path or missingSlotIcons[path] then
        return nil
    end

    if slotIconCache[path] then
        return slotIconCache[path]
    end

    local loaded, icon = pcall(ImageLoader.newImage, path)

    if not loaded or not icon then
        missingSlotIcons[path] = true
        return nil
    end

    slotIconCache[path] = icon

    return icon
end

local function getAgencyButtonIcon()
    if agencyButtonIcon or agencyButtonIconMissing then
        return agencyButtonIcon
    end

    local loaded, icon = pcall(ImageLoader.newImage, AGENCY_ICON_PATH)

    if not loaded or not icon then
        agencyButtonIconMissing = true
        return nil
    end

    agencyButtonIcon = icon

    return agencyButtonIcon
end

local function getProfileBounds()
    local mapLeft = math.huge

    for _, cell in ipairs(BattleMap.getCells()) do
        local vertices = BattleMap.getHexVertices(cell)

        for index = 1, #vertices, 2 do
            mapLeft = math.min(mapLeft, vertices[index])
        end
    end

    local width = math.max(
        PROFILE_MIN_WIDTH,
        mapLeft - PROFILE_MARGIN * 2
    )

    return {
        x = PROFILE_MARGIN,
        y = PROFILE_TOP,
        width = width,
        height = love.graphics.getHeight() - PROFILE_TOP - PROFILE_MARGIN,
    }
end

local function drawProfileImage(entity, bounds, y)
    local image = entity.profileImage
    local imageWidth, imageHeight = image:getDimensions()
    local availableWidth = bounds.width - PROFILE_PADDING * 2
    local availableHeight = math.min(availableWidth, 250)
    local scale = math.min(
        availableWidth / imageWidth,
        availableHeight / imageHeight
    )
    local drawWidth = imageWidth * scale
    local drawHeight = imageHeight * scale
    local drawX = bounds.x + (bounds.width - drawWidth) / 2

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, drawX, y, 0, scale, scale)

    return y + drawHeight
end

local function drawStats(entity, bounds, startY)
    local stats = entity.definition.stats or {}
    local rowHeight = 34
    local rowGap = 5
    local x = bounds.x + PROFILE_PADDING
    local width = bounds.width - PROFILE_PADDING * 2
    local y = startY

    love.graphics.setColor(PROFILE_MUTED_COLOR)
    love.graphics.print("STATS", x, y)
    y = y + 28

    for _, statEntry in ipairs(stats) do
        local labels = {}

        for label in pairs(statEntry) do
            labels[#labels + 1] = label
        end

        table.sort(labels)

        for _, label in ipairs(labels) do
            love.graphics.setColor(PROFILE_STAT_COLOR)
            love.graphics.rectangle(
                "fill",
                x,
                y,
                width,
                rowHeight,
                4,
                4
            )
            love.graphics.setColor(PROFILE_MUTED_COLOR)
            love.graphics.print(label:upper(), x + 9, y + 8)
            love.graphics.setColor(PROFILE_TEXT_COLOR)
            love.graphics.printf(
                tostring(statEntry[label]),
                x + 9,
                y + 8,
                width - 18,
                "right"
            )
            y = y + rowHeight + rowGap
        end
    end

    return y
end

local function drawInventorySlots(entity, bounds, startY)
    local slots = entity.definition.slots or {}
    local x = bounds.x + PROFILE_PADDING
    local width = bounds.width - PROFILE_PADDING * 2
    local slotSize = (
        width
            - INVENTORY_SLOT_GAP * (INVENTORY_SLOT_COLUMNS - 1)
    ) / INVENTORY_SLOT_COLUMNS
    local y = startY

    love.graphics.setColor(PROFILE_MUTED_COLOR)
    love.graphics.print("INVENTORY", x, y)
    y = y + 28

    for index = 1, INVENTORY_SLOT_COLUMNS * INVENTORY_SLOT_ROWS do
        local column = (index - 1) % INVENTORY_SLOT_COLUMNS
        local row = math.floor((index - 1) / INVENTORY_SLOT_COLUMNS)
        local slotX = x + column * (slotSize + INVENTORY_SLOT_GAP)
        local slotY = y + row * (slotSize + INVENTORY_SLOT_GAP)

        love.graphics.setColor(INVENTORY_SLOT_COLOR)
        love.graphics.rectangle(
            "fill",
            slotX,
            slotY,
            slotSize,
            slotSize,
            4,
            4
        )
        love.graphics.setColor(INVENTORY_SLOT_BORDER_COLOR)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle(
            "line",
            slotX,
            slotY,
            slotSize,
            slotSize,
            4,
            4
        )

        local icon = getSlotIcon(slots[index])

        if icon then
            local iconWidth, iconHeight = icon:getDimensions()
            local availableSize = slotSize - INVENTORY_ICON_PADDING * 2
            local scale = availableSize / math.max(iconWidth, iconHeight)

            love.graphics.setColor(1, 1, 1, INVENTORY_SLOT_ICON_OPACITY)
            love.graphics.draw(
                icon,
                slotX + slotSize / 2,
                slotY + slotSize / 2,
                0,
                scale,
                scale,
                iconWidth / 2,
                iconHeight / 2
            )
        end
    end

    love.graphics.setLineWidth(1)

    return y + INVENTORY_SLOT_ROWS * slotSize
        + (INVENTORY_SLOT_ROWS - 1) * INVENTORY_SLOT_GAP
end

local function drawAgencyButton(entity, bounds, startY)
    if not entity.agencyStack then
        agencyButtonBounds = nil
        return
    end

    agencyButtonBounds = {
        x = bounds.x + PROFILE_PADDING,
        y = startY + AGENCY_BUTTON_GAP,
        width = bounds.width - PROFILE_PADDING * 2,
        height = AGENCY_BUTTON_SIZE,
    }

    local button = agencyButtonBounds

    love.graphics.setColor(AGENCY_BUTTON_COLOR)
    love.graphics.rectangle(
        "fill",
        button.x,
        button.y,
        button.width,
        button.height,
        5,
        5
    )
    love.graphics.setColor(PROFILE_BORDER_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle(
        "line",
        button.x,
        button.y,
        button.width,
        button.height,
        5,
        5
    )

    local icon = getAgencyButtonIcon()

    if icon then
        local iconWidth, iconHeight = icon:getDimensions()
        local availableSize = AGENCY_BUTTON_SIZE - 14
        local scale = availableSize / math.max(iconWidth, iconHeight)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
            icon,
            button.x + button.width / 2,
            button.y + button.height / 2,
            0,
            scale,
            scale,
            iconWidth / 2,
            iconHeight / 2
        )
    end

    love.graphics.setLineWidth(1)
end

function AgentLogic.getFootprint(definition, anchorCell)
    if type(definition) ~= "table" then
        return nil, "Agent definition must be a table"
    end

    if not anchorCell then
        return nil, "Agent requires a valid anchor hex"
    end

    if definition.size == 1 then
        return { anchorCell }
    end

    if definition.size == 2 then
        local neighbors = BattleMap.getNeighbors(anchorCell)

        if #neighbors ~= 6 then
            return nil, (
                "size-2 Agent %q requires six hexes surrounding spawner %s"
            ):format(definition.id, anchorCell.key)
        end

        local footprint = { anchorCell }

        for _, neighbor in ipairs(neighbors) do
            footprint[#footprint + 1] = neighbor
        end

        return footprint
    end

    return nil, (
        "Agent %q has unsupported size %s; expected 1 or 2"
    ):format(tostring(definition.id), tostring(definition.size))
end

function AgentLogic.spawn(definition, anchorCell)
    local footprint, footprintError = AgentLogic.getFootprint(
        definition,
        anchorCell
    )

    if not footprint then
        return nil, footprintError
    end

    local portraitPath, pathError = getPortraitPath(definition)

    if not portraitPath then
        return nil, pathError
    end

    local profileImagePath, profilePathError = getProfileImagePath(definition)

    if not profileImagePath then
        return nil, profilePathError
    end

    local loaded, portrait = pcall(ImageLoader.newImage, portraitPath)

    if not loaded then
        return nil, (
            "unable to load portrait for Agent %q from %s: %s"
        ):format(definition.id, portraitPath, tostring(portrait))
    end

    local profileLoaded, profileImage = pcall(
        ImageLoader.newImage,
        profileImagePath
    )

    if not profileLoaded then
        return nil, (
            "unable to load profile image for Agent %q from %s: %s"
        ):format(definition.id, profileImagePath, tostring(profileImage))
    end

    return {
        id = definition.id,
        entityType = "AGENT",
        definition = definition,
        anchor = anchorCell,
        footprint = footprint,
        portrait = portrait,
        portraitPath = portraitPath,
        profileImage = profileImage,
        profileImagePath = profileImagePath,
    }
end

function AgentLogic.draw(entity)
    local size = entity.definition.size
    local diameter = BattleMap.HEX_RADIUS
        * PORTRAIT_DIAMETER_IN_HEX_RADII[size]
    local imageWidth, imageHeight = entity.portrait:getDimensions()
    local pulseScale = getPulseScale(entity)
        * (entity.initiativeEffectScale or 1)
    local scale = diameter / math.max(imageWidth, imageHeight) * pulseScale

    love.graphics.stencil(function()
        for _, cell in ipairs(entity.footprint) do
            love.graphics.polygon(
                "fill",
                scalePointsFromCenter(
                    BattleMap.getHexVertices(cell),
                    entity.anchor.x,
                    entity.anchor.y,
                    pulseScale
                )
            )
        end
    end, "replace", 1)

    local exhaustedOpacity = entity.exhausted
        and not entity.initiativeExhaustionPending
        and EXHAUSTED_PORTRAIT_OPACITY
        or 1

    love.graphics.setStencilTest("equal", 1)
    love.graphics.setColor(
        entity.initiativeEffectRed or 1,
        entity.initiativeEffectGreen or 1,
        entity.initiativeEffectBlue or 1,
        entity.initiativeEffectOpacity or exhaustedOpacity
    )
    love.graphics.draw(
        entity.portrait,
        entity.anchor.x,
        entity.anchor.y,
        0,
        scale,
        scale,
        imageWidth / 2,
        imageHeight / 2
    )
    love.graphics.setStencilTest()

    local outlineRadius = (
        diameter / 2 - PORTRAIT_OUTLINE_WIDTH / 2
    ) * pulseScale

    love.graphics.setColor(PORTRAIT_OUTLINE_COLOR)
    love.graphics.setLineWidth(PORTRAIT_OUTLINE_WIDTH)
    love.graphics.polygon(
        "line",
        buildHexPoints(entity.anchor.x, entity.anchor.y, outlineRadius)
    )
end

function AgentLogic.update(dt)
    pulseTime = pulseTime + dt

    if activeShout then
        activeShout.elapsed = activeShout.elapsed + dt

        local typeDuration = getShoutTypeDuration(
            activeShout.characterCount
        )
        local totalDuration = typeDuration
            + SHOUT_HOLD_DURATION
            + SHOUT_FADE_DURATION

        if activeShout.elapsed >= totalDuration then
            activeShout = nil
        end
    end
end

function AgentLogic.select(entity)
    if not entity
        or (entity.entityType ~= "AGENT"
            and entity.entityType ~= "HOSTILE") then
        return false
    end

    selectedAgent = entity
    pulseTime = 0
    refreshMovementRange(entity)
    beginShout(entity)
    Sfx.play("click")
    Sfx.playVoice(entity.id)

    return true
end

function AgentLogic.deselect()
    local hadSelection = selectedAgent ~= nil

    selectedAgent = nil
    pulseTime = 0
    activeShout = nil
    movementCells = {}
    agencyButtonBounds = nil
    Sfx.stopVoice()

    return hadSelection
end

function AgentLogic.getSelected()
    return selectedAgent
end

function AgentLogic.getMovementCells()
    return movementCells
end

function AgentLogic.getAgencyButtonBounds()
    return agencyButtonBounds
end

function AgentLogic.getActiveShout()
    return activeShout
end

function AgentLogic.drawSelectionOverlay()
    local entity = selectedAgent

    if not entity or not activeShout then
        return
    end

    local diameter = BattleMap.HEX_RADIUS
        * PORTRAIT_DIAMETER_IN_HEX_RADII[entity.definition.size]

    drawShout(entity, diameter * getPulseScale(entity))
end

function AgentLogic.drawMovementOverlay()
    local entity = selectedAgent

    if not entity or #movementCells == 0 then
        return
    end

    local fillColor = entity.entityType == "HOSTILE"
        and HOSTILE_MOVEMENT_FILL_COLOR
        or AGENT_MOVEMENT_FILL_COLOR

    love.graphics.setColor(fillColor)

    for _, cell in ipairs(movementCells) do
        love.graphics.polygon(
            "fill",
            BattleMap.getHexVertices(cell)
        )
    end

    love.graphics.setColor(MOVEMENT_OUTLINE_COLOR)
    love.graphics.setLineWidth(MOVEMENT_OUTLINE_WIDTH)

    for _, cell in ipairs(movementCells) do
        love.graphics.polygon(
            "line",
            BattleMap.getHexVertices(cell)
        )
    end

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function AgentLogic.drawProfilePanel()
    local entity = selectedAgent

    if not entity then
        agencyButtonBounds = nil
        return
    end

    local bounds = getProfileBounds()
    local contentX = bounds.x + PROFILE_PADDING

    love.graphics.setColor(PROFILE_BACKGROUND_COLOR)
    love.graphics.rectangle(
        "fill",
        bounds.x,
        bounds.y,
        bounds.width,
        bounds.height,
        7,
        7
    )
    love.graphics.setColor(PROFILE_BORDER_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle(
        "line",
        bounds.x,
        bounds.y,
        bounds.width,
        bounds.height,
        7,
        7
    )
    love.graphics.setColor(PROFILE_TEXT_COLOR)
    love.graphics.printf(
        entity.definition.name or entity.id,
        contentX,
        bounds.y + PROFILE_PADDING,
        bounds.width - PROFILE_PADDING * 2,
        "center"
    )

    local imageBottom = drawProfileImage(
        entity,
        bounds,
        bounds.y + PROFILE_PADDING + 38
    )

    local statsBottom = drawStats(entity, bounds, imageBottom + 20)

    local inventoryBottom = drawInventorySlots(
        entity,
        bounds,
        statsBottom + 5
    )

    drawAgencyButton(entity, bounds, inventoryBottom)
    love.graphics.setColor(1, 1, 1, 1)
end

return AgentLogic
