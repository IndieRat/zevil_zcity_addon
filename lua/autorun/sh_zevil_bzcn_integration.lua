if SERVER then AddCSLuaFile() end

-- Zevil integration for the pinned BZCN shared API.
-- Zevil keeps its own virus lifecycle and locomotion, while its NPCs opt into
-- the BZCN injury bridge through Zevil.AttachZCityNPCSupport. The bridge is
-- responsible for creating native organism state; this file only registers profiles.
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

    BZCN.RegisterClass("ZevilCivilian", {
        Name = "Zevil Civilian",
        PlayerClassName = "civilian",
        Model = "models/player/group03/male_07.mdl",
        Health = 100,
        Speed = 90,
        BaseSpeedOverride = 90,
        WalkSpeed = 48,
        Faction = "civilian",
        TeamName = "Survivor",
        EnemyPlayers = false,
        EnemyFactions = {"zombie", "Zevil", "ZevilInfected"},
        FollowAllies = false,
        Ranged = false,
        Combat = false,
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

-- Zevil is the infection source of truth. If the full external BZCN addon is
-- also mounted, turn off its legacy headcrab conversion rule to prevent a
-- second, competing infection lifecycle from converting victims.
if SERVER then
    hook.Add("Initialize", "Zevil_DisableLegacyHeadcrabInfection", function()
        timer.Simple(0, function()
            local legacyRule = GetConVar("bzcn_rule_headcrab_infection")
            if legacyRule and legacyRule:GetBool() then
                RunConsoleCommand("bzcn_rule_headcrab_infection", "0")
                print("[Zevil] Disabled legacy BZCN headcrab infection; Zevil owns infection progression.")
            end
        end)
    end)
end

