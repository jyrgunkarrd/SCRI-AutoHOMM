-- data/entities/hostiles.lua
-- hostile definitions

local hostiles = {

    {

        id = "HOSTILE_FORG",
        entity_type = "HOSTILE",
        size = 1,
        name = "Forgiven",
        slots = {

            "Head",
            "Body",
            "Hand",
            "Hand",
            "Legs",
            "Jewelry",
            "Belt",
            "Belt",
            "Machine",
            "Ally",

        },
        stats = {
            {hp = 3},
            {str = 1},
            {agi = 0},
            {spd = 2},
            {tgh = 0},
            {lex = 0}, 
        },
        actions_art = {
            
            { cardid = "ATK", art = "MAM_ATK" },
            { cardid = "DFN", art = "MAM_DFN" },
        
        },
        shout = "I proudly serve.",
    },

}

return hostiles