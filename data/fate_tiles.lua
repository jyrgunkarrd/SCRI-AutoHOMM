-- data/fate_tiles.lua
-- fate tile definitions

local fate_tiles = {

    {

        id = "NEUTRAL",
        value = 0,

    },
    
    {

        id = "PLUS 1",
        value = 1,

    },

    {

        id = "PLUS 2",
        value = 2,

    },

    {

        id = "NEG 1",
        value = 1,
        neg = true,

    },

    {

        id = "NEG 2",
        value = 2,
        neg = true,

    },

    {

        id = "FAIL",
        value = 0,
        fail = true,

    },

    {

        id = "CRIT",
        value = 2,
        crit = true,

    },

    {

        id = "FATIGUE",
        value = 0,
        fail = true,

    },

}

return fate_tiles