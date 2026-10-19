-- Zevil integration for the pinned BZCN shared API.
-- This deliberately uses the API's compatibility adapter without calling
-- BZCN.ApplyClass: that routine marks NPCs as organism-backed and expects the
-- separate BZCN organism-support module. Zevil's virus state stays independent.
if not BZCN or not isfunction(BZCN.RegisterClass) then return end

local function RegisterZevilClasses()
    BZCN.RegisterClass("ZevilInfected", {
        Name = "Zevil Infected",
        PlayerClassName = "ZevilInfected",
        Model = "models/player/zombie_classic.mdl",
        Health = 100,
        Speed = 112,
        BaseSpeedOverride = 112,
        WalkSpeed = 68,
        Faction = "zombie",
        TeamName = "Zevil",
        EnemyPlayers = true,
        EnemyFactions = {"default", "civilian", "Combine", "Metrocop", "Rebel", "furry", "ZevilRookieCop"},
        FollowAllies = true,
        ZombieStyle = false,
        Ranged = false,
        MeleeDamage = 12,
        MeleeRange = 78,
        AttackDelay = 1.65,
        WeaponClass = "",
        Inventory = {Weapons = {}, Items = {}, Ammo = {}, Attachments = {}, Armor = {}}
    })

    BZCN.RegisterClass("ZevilRookieCop", {
        Name = "Leon Kennedy",
        DisplayNames = {"Leon Kennedy"},
        PlayerClassName = "Metrocop",
        Model = "models/player/police.mdl",
        Health = 125,
        Speed = 180,
        BaseSpeedOverride = 180,
        WalkSpeed = 100,
        Faction = "Survivor",
        TeamName = "Survivor",
        EnemyPlayers = false,
        EnemyFactions = {"zombie", "Zevil"},
        FollowAllies = true,
        FollowRange = 900,
        FollowDistance = 150,
        HelpRange = 1100,
        HelpMemory = 12,
        Ranged = true,
        WeaponDamage = 10,
        WeaponRange = 1000,
        AttackDelay = 0.62,
        AnimationClass = "metrocop",
        AnimationHoldType = "pistol",
        WeaponClass = "Pistol:9mm",
        Inventory = {
            Weapons = {["Pistol:9mm"] = true, weapon_hands_sh = true},
            Items = {},
            Ammo = {},
            Attachments = {},
            Armor = {}
        }
    })
end

RegisterZevilClasses()
