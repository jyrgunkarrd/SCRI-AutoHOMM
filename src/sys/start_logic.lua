local BlockLogic = require("src.sys.block_logic")

local StartLogic = {}

local function getToughness(entity)
    for _, statEntry in ipairs(entity.definition.stats or {}) do
        for name, value in pairs(statEntry) do
            if type(name) == "string"
                and name:lower() == "tgh"
                and type(value) == "number" then
                return math.max(0, value)
            end
        end
    end

    return 0
end

function StartLogic.resolve(entities)
    if type(entities) ~= "table" then
        return nil, "Start processing requires an entity list"
    end

    for _, entity in ipairs(entities) do
        local toughness = getToughness(entity)

        if toughness > 0 then
            local block, blockError = BlockLogic.add(entity, toughness)

            if block == nil then
                return nil, (
                    "unable to grant Start Block to %q: %s"
                ):format(tostring(entity.id), tostring(blockError))
            end
        end
    end

    return true
end

return StartLogic
