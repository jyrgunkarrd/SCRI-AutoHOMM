local ImageLoader = require("src.assets.image_loader")
local AgentLogic = require("src.sys.agent_logic")

local HostilesLogic = {}

local PORTRAIT_DIR = "assets/images/hostiles"

local function getImagePath(definition, suffix)
    if type(definition.id) ~= "string"
        or not definition.id:match("^[%w_%-]+$") then
        return nil, "Hostile id contains characters that are unsafe in an image path"
    end

    return ("%s/%s%s.webp"):format(
        PORTRAIT_DIR,
        definition.id,
        suffix or ""
    )
end

function HostilesLogic.getFootprint(definition, anchorCell)
    return AgentLogic.getFootprint(definition, anchorCell)
end

function HostilesLogic.spawn(definition, anchorCell)
    local footprint, footprintError = HostilesLogic.getFootprint(
        definition,
        anchorCell
    )

    if not footprint then
        return nil, footprintError
    end

    local portraitPath, portraitPathError = getImagePath(
        definition,
        "_hex"
    )

    if not portraitPath then
        return nil, portraitPathError
    end

    local profileImagePath, profilePathError = getImagePath(definition)

    if not profileImagePath then
        return nil, profilePathError
    end

    local portraitLoaded, portrait = pcall(
        ImageLoader.newImage,
        portraitPath
    )

    if not portraitLoaded then
        return nil, (
            "unable to load portrait for Hostile %q from %s: %s"
        ):format(definition.id, portraitPath, tostring(portrait))
    end

    local profileLoaded, profileImage = pcall(
        ImageLoader.newImage,
        profileImagePath
    )

    if not profileLoaded then
        return nil, (
            "unable to load profile image for Hostile %q from %s: %s"
        ):format(
            definition.id,
            profileImagePath,
            tostring(profileImage)
        )
    end

    return {
        id = definition.id,
        entityType = "HOSTILE",
        hostile = true,
        isAgentLike = true,
        definition = definition,
        anchor = anchorCell,
        footprint = footprint,
        portrait = portrait,
        portraitPath = portraitPath,
        profileImage = profileImage,
        profileImagePath = profileImagePath,
    }
end

function HostilesLogic.draw(entity)
    AgentLogic.draw(entity)
end

return HostilesLogic
