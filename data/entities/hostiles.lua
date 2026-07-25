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
        steel_atk = {
            
            { rng = 1 },
        
        },
        fire_atk = {

            { min_rng = 0},
            { rng = 3 },

        },
        ammo = 2,
        shout = "I proudly serve.",
        slain = "masc",
    },

}

return hostiles