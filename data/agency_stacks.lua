-- Agency stack definitions. A stack id matches its owning entity id after
-- the leading `AGENT_` or `HOSTILE_` prefix is removed.
return {
    {
        id = "MAM",
        tiles = {
            { tileid = "SHOVE 2", quantity = 28 },
            { tileid = "BLOCK 2", quantity = 28 },
            { tileid = "STUN 1", quantity = 4 },
        },
    },

    {
        id = "FORG",
        tiles = {
            { tileid = "FATALISM", quantity = 56 },
            { tileid = "BURST C", quantity = 4 },
        },
    },
}
