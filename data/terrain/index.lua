-- Add each terrain-definition module here. Every module must return an array
-- of tables containing a unique, non-empty string in its `id` field.
local sources = {
    {
        name = "data.terrain.cover",
        definitions = require("data.terrain.cover"),
    },
    {
        name = "data.terrain.hazards",
        definitions = require("data.terrain.hazards"),
    },
}

local terrainById = {}
local sourceById = {}

for _, source in ipairs(sources) do
    if type(source.definitions) ~= "table" then
        error(("Terrain source %q must return a table."):format(source.name))
    end

    for index, definition in ipairs(source.definitions) do
        if type(definition) ~= "table" then
            error((
                "Terrain definition %d in %q must be a table."
            ):format(index, source.name))
        end

        local id = definition.id

        if type(id) ~= "string" or not id:match("%S") then
            error((
                "Terrain definition %d in %q requires a non-empty string id."
            ):format(index, source.name))
        end

        if terrainById[id] then
            error((
                "Duplicate terrain id %q in %q; it was already defined in %q."
            ):format(id, source.name, sourceById[id]))
        end

        terrainById[id] = definition
        sourceById[id] = source.name
    end
end

return terrainById
