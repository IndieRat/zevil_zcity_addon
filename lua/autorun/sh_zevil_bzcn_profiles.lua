-- Zevil-specific BZCN profiles must be registered independently of the vendored API.
-- When the full Better Z-City NPC addon is mounted, sh_zevil_bzcn_api.lua
-- intentionally reuses its API and exits early; these profiles still need to exist.
if SERVER then AddCSLuaFile() end

local function RegisterZevilProfiles()
    if not (BZCN and isfunction(BZCN.RegisterClass)) then return false end

    BZCN.RegisterClass("ZevilInfected", {
        Name = "Infected",
        PlayerClassName = "headcrabzombie",
        TeamName = "Zevil",
        Faction = "zombie",
        -- This is the important native headcrab-zombie styling profile. The
        -- model is intentionally omitted: Zevil selects a Z-City appearance
        -- model first, then ApplyClass layers compatible zombie materials on it.
        ZombieStyle = true,
        EnemyPlayers = true,
        EnemyFactions = {"default", "civilian", "Combine", "Metrocop", "Rebel", "furry"},
        FollowAllies = true,
        FollowRange = 850,
        FollowDistance = 80,
        HelpRange = 600,
        HelpMemory = 5,
        Ranged = false,
        MeleeDamage = 12,
        MeleeRange = 78,
        AttackDelay = 1.65,
        MeleeSound = "npc/zombie/claw_strike1.wav",
        MeleeMissSound = "npc/zombie/claw_miss1.wav",
        AnimationHoldType = "normal",
        WeaponClass = "weapon_hands_sh",
        MedicalRange = 0,
        Inventory = {
            Weapons = {weapon_hands_sh = true},
            Items = {},
            Ammo = {},
            Attachments = {},
            Armor = {}
        }
    })

    BZCN.RegisterClass("ZevilCivilian", {
        Name = "Zevil Survivor",
        PlayerClassName = "default",
        TeamName = "Survivor",
        Faction = "civilian",
        CivilianStyle = true,
        EnemyPlayers = false,
        EnemyFactions = {},
        FollowAllies = true,
        FollowRange = 1000,
        FollowDistance = 150,
        HelpRange = 1200,
        HelpMemory = 10,
        Ranged = false,
        WeaponClass = "weapon_hands_sh",
        MedicalRange = 320,
        Inventory = {
            Weapons = {
                weapon_hands_sh = true,
                weapon_medkit_sh = true,
                weapon_bandage_sh = true
            },
            Items = {},
            Ammo = {},
            Attachments = {},
            Armor = {}
        }
    })

    return true
end

local attempts = 0
local function EnsureZevilProfiles()
    if RegisterZevilProfiles() then return end
    attempts = attempts + 1
    if attempts < 40 then
        timer.Simple(0.25, EnsureZevilProfiles)
    elseif SERVER then
        ErrorNoHalt("[Zevil] BZCN class profiles were not registered: BZCN.RegisterClass is unavailable.\n")
    end
end

EnsureZevilProfiles()
