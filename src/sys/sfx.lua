local Sfx = {}

local DEFINITIONS = {
    click = "assets/audio/sfx/click.wav",
    prepared = "assets/audio/sfx/prepared.wav",
    round_start = "assets/audio/sfx/round_start.wav",
}

local sources = {}
local masterVolume = 1
local activeVoice

local function getCachedSource(cacheKey, path, label)
    if sources[cacheKey] then
        return sources[cacheKey]
    end

    local loaded, source = pcall(function()
        return love.audio.newSource(path, "static")
    end)

    if not loaded then
        return nil, (
            "unable to load %s from %s: %s"
        ):format(label, path, tostring(source))
    end

    source:setVolume(masterVolume)
    sources[cacheKey] = source

    return source
end

local function getSource(name)
    local path = DEFINITIONS[name]

    if not path then
        return nil, ("unknown sound effect %q"):format(tostring(name))
    end

    return getCachedSource(name, path, ("sound effect %q"):format(name))
end

function Sfx.load(name)
    local source, loadError = getSource(name)

    if not source then
        return nil, loadError
    end

    return true
end

function Sfx.play(name)
    local source, loadError = getSource(name)

    if not source then
        return nil, loadError
    end

    source:stop()
    source:play()

    return true
end

function Sfx.playVoice(agentId)
    if type(agentId) ~= "string"
        or not agentId:match("^[%w_%-]+$") then
        return nil, "Agent id is unsafe for a voice-line path"
    end

    local path = (
        "assets/audio/sfx/voices/%s.wav"
    ):format(agentId)
    local source, loadError = getCachedSource(
        "voice:" .. agentId,
        path,
        ("voice line for Agent %q"):format(agentId)
    )

    if not source then
        return nil, loadError
    end

    if activeVoice and activeVoice ~= source then
        activeVoice:stop()
    end

    source:stop()
    source:play()
    activeVoice = source

    return true
end

function Sfx.stopVoice()
    if not activeVoice then
        return false
    end

    activeVoice:stop()
    activeVoice = nil

    return true
end

function Sfx.setVolume(volume)
    if type(volume) ~= "number" or volume < 0 or volume > 1 then
        return nil, "SFX volume must be a number from 0 to 1"
    end

    masterVolume = volume

    for _, source in pairs(sources) do
        source:setVolume(masterVolume)
    end

    return true
end

function Sfx.getVolume()
    return masterVolume
end

return Sfx
