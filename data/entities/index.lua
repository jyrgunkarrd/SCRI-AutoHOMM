-- Add each entity-definition module here. Every module must return an array
-- of tables containing a unique, non-empty string in its `id` field.
local sources = {
    {
        name = "data.entities.jacls",
        definitions = require("data.entities.jacls"),
    },
    {
        name = "data.entities.agents",
        definitions = require("data.entities.agents"),
    },
    {
        name = "data.entities.hostiles",
        definitions = require("data.entities.hostiles"),
    },
}

local entitiesById = {}
local sourceById = {}

for _, source in ipairs(sources) do
    if type(source.definitions) ~= "table" then
        error(("Entity source %q must return a table."):format(source.name))
    end

    for index, definition in ipairs(source.definitions) do
        if type(definition) ~= "table" then
            error((
                "Entity definition %d in %q must be a table."
            ):format(index, source.name))
        end

        local id = definition.id

        if type(id) ~= "string" or not id:match("%S") then
            error((
                "Entity definition %d in %q requires a non-empty string id."
            ):format(index, source.name))
        end

        if entitiesById[id] then
            error((
                "Duplicate entity id %q in %q; it was already defined in %q."
            ):format(id, source.name, sourceById[id]))
        end

        entitiesById[id] = definition
        sourceById[id] = source.name
    end
end

return entitiesById
