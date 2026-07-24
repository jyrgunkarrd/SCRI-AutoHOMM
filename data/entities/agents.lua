-- data/entities/agents.lua
-- agent definitions

local agents = {

    {

        id = "AGENT_MAM",
        entity_type = "AGENT",
        size = 1,
        name = "Mammoth",
        slots = {

            "Head",
            "Body",
            "Hand",
            "Hand",
            "Legs",
            "Jewelry",
            "Belt",
            "Lex",
            "Lex",
            "Lex",

        },
        stats = {
            {hp = 10},
            {str = 3},
            {agi = 1},
            {spd = 2},
            {tgh = 1},
            {lex = 1}, 
        },
        actions_art = {
            
            { cardid = "ATK", art = "MAM_ATK" },
            { cardid = "DFN", art = "MAM_DFN" },
        
        },
        shout = "As a river bends.",
        skill_trees = {

            tab1ID = "MAM_TREE_K-J",
            tab2ID = "MAM_TREE_KIM",
            tab3ID = "MAM_TREE_T-Y",

        },

    },

    {

        id = "APEX",
        name = "Apex",
        slots = {

            "Head",
            "Body",
            "Hand",
            "Hand",
            "Legs",
            "Jewelry",
            "Jewelry",
            "Belt",
            "Belt",

        },
        stats = {
            {hp = 40},
            {ap = 5},
            {lp = 2},
            {strength = 1},
            {agility = 2},
            {lex = 1}, 
        },
        hpgrowth = 4,
        fate = "BSCSTACK",
        actions = {

            "BSCDECK",

        },
        shout_select = "I see them.",
        start_equip_cache = {

            rumors = {

                "MAM_8",
                "MAM_SENG",

            },

            luggage = {

                "bag",
                "brief",
                "truck",

            },

        },

    },

    {

        id = "SAW",
        name = "Snow &\nMiss White",
        slots = {

            "Head",
            "Body",
            "Hand",
            "Hand",
            "Legs",
            "Jewelry",
            "Belt",
            "Lex",
            "Ally",
            "Ally",

        },
        stats = {
            {hp = 30},
            {ap = 5},
            {lp = 2},
            {strength = 0},
            {agility = 4},
            {lex = 1}, 
        },
        hpgrowth = 2,
        fate = "BSCSTACK",
        actions = {

            "BSCDECK",

        },
        shout_select = "We're ready.",
        start_equip_cache = {

            rumors = {

                "MAM_8",
                "MAM_SENG",

            },

            luggage = {

                "bag",
                "brief",
                "truck",

            },

        },

    },

    {

        id = "WICK",
        name = "Wick",
        slots = {

            "Head",
            "Body",
            "Hand",
            "Hand",
            "Jewelry",
            "Machine",
            "Lex",
            "Lex",
            "Lex",
            "Ally",

        },
        stats = {
            {hp = 10},
            {ap = 5},
            {lp = 14},
            {strength = 0},
            {agility = 0},
            {lex = 7}, 
        },
        hpgrowth = 2,
        fate = "BSCSTACK",
        actions = {

            "BSCDECK",

        },
        actions_art = {
            
            { cardid = "ATK", art = "WICK_ATK" },
            { cardid = "DFN", art = "WICK_DFN" },
        
        },
        start_equip_slot = {

            "PHNX",

        },
        shout_select = "Say the word.",
        start_equip_cache = {

            rumors = {

                "MAM_8",
                "MAM_SENG",

            },

            luggage = {

                "bag",
                "brief",
                "truck",

            },

            consumables = {

                "RSTIT",
                "RSTIT",
                "BPUL",

            },

        },

    },

    {

        id = "BMNCH",
        name = "Big Munch",
        slots = {

            "Head",
            "Body",
            "Body",
            "Hand",
            "Hand",
            "Legs",
            "Legs",
            "Jewelry",
            "Lex",
            "Lex",

        },
        stats = {
            {hp = 60},
            {ap = 5},
            {lp = 2},
            {strength = 1},
            {agility = 0},
            {lex = 1}, 
        },
        hpgrowth = 6,
        fate = "BSCSTACK",
        actions = {

            "BSCDECK",

        },
        shout_select = "MUNCH HUNGRY!",
        start_equip_cache = {

            rumors = {

                "MAM_8",
                "MAM_SENG",

            },

            luggage = {

                "bag",
                "brief",
                "truck",

            },

        },

    },

    {

        id = "B6",
        name = "Betty Six",
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
            {hp = 30},
            {ap = 5},
            {lp = 0},
            {strength = 2},
            {agility = 3},
            {lex = 0}, 
        },
        hpgrowth = 4,
        fate = "BSCSTACK",
        actions = {

            "BSCDECK",

        },
        actions_art = {
            
            { cardid = "ATK", art = "B6_ATK" },
            { cardid = "DFN", art = "B6_DFN" },
        
        },
        shout_select = "They're dead already.",
        start_equip_cache = {

            rumors = {

                "MAM_8",
                "MAM_SENG",

            },

            luggage = {

                "bag",
                "brief",
                "truck",

            },

        },

    },

    {

        id = "TMW",
        name = "Tomorrow",
        slots = {

            "Head",
            "Body",
            "Hand",
            "Hand",
            "Legs",
            "Jewelry",
            "Belt",
            "Machine",
            "Lex",
            "Lex",
        },
        stats = {
            {hp = 20},
            {ap = 5},
            {lp = 2},
            {strength = 1},
            {agility = 4},
            {lex = 1}, 
        },
        hpgrowth = 2,
        fate = "BSCSTACK",
        actions = {

            "BSCSLYDECK",

        },
        actions_art = {
            
            { cardid = "ATK", art = "TMW_ATK" },
            { cardid = "DFN", art = "TMW_DFN" },
            { cardid = "BYP", art = "TMW_BYP" },
        
        },
        shout_select = "Good news?",
        start_equip_cache = {

            rumors = {

                "MAM_8",
                "MAM_SENG",

            },

            luggage = {

                "bag",
                "brief",
                "truck",

            },

        },

    },

}

return agents