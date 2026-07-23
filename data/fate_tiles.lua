-- data/fate_tiles.lua
-- fate tile definitions

local fate_tiles = {

    {

        id = "BSC0",
        value = 0,

    },
    
    {

        id = "BSC1",
        value = 1,

    },

    {

        id = "BSC2",
        value = 2,

    },

    {

        id = "BSCNEG1",
        value = 1,
        neg = true,

    },

    {

        id = "BSCNEG2",
        value = 2,
        neg = true,

    },

    {

        id = "BSCFAIL",
        value = 0,
        fail = true,

    },

    {

        id = "BSCCRIT",
        value = 2,
        crit = true,

    },

    {

        id = "BSCFATIGUE",
        value = 0,
        fail = true,

    },

}

return fate_tiles