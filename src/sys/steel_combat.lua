local newCombat = require("src.sys.combat_logic")

local SteelCombat = newCombat({
    name = "Steel",
    attackKey = "steel_atk",
    projectileDirectory = "assets/images/attacks/steel",
    launchSfx = "steel_atk",
    noAttackReason = "no_steel_attack",
})

SteelCombat.beginSteel = SteelCombat.begin

return SteelCombat
