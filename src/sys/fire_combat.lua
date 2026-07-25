local newCombat = require("src.sys.combat_logic")

local FireCombat = newCombat({
    name = "Fire",
    attackKey = "fire_atk",
    projectileDirectory = "assets/images/attacks/fire",
    launchSfx = "fire_atk",
    noAttackReason = "no_fire_attack",
    requiresMinimumRange = true,
    usesAmmunition = true,
})

FireCombat.beginFire = FireCombat.begin

return FireCombat
