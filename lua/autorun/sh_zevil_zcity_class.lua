-- Z-City player-class bridge for Zevil infection.
-- Mirrors the relevant headcrabzombie class behavior without replacing the player's
-- current model or touching Z-City's organism table during class setup.
if SERVER then AddCSLuaFile() end

Zevil = Zevil or {}

local CLASS_NAME = "zevil_infected"
local HANDS_CLASS = "weapon_hands_sh"

local combineClasses = {
    npc_combine_s = true, npc_metropolice = true, npc_helicopter = true,
    npc_combinegunship = true, npc_combine = true, npc_stalker = true,
    npc_hunter = true, npc_strider = true, npc_turret_floor = true,
    npc_combine_camera = true, npc_manhack = true, npc_cscanner = true,
    npc_clawscanner = true
}

local rebelClasses = {
    npc_barney = true, npc_citizen = true, npc_dog = true, npc_eli = true,
    npc_kleiner = true, npc_magnusson = true, npc_monk = true,
    npc_mossman = true, npc_odessa = true, npc_rollermine_hacked = true,
    npc_turret_floor_resistance = true, npc_vortigaunt = true, npc_alyx = true
}

local undeadClasses = {
    npc_fastzombie = true, npc_fastzombie_torso = true, npc_headcrab = true,
    npc_headcrab_black = true, npc_headcrab_fast = true, npc_poisonzombie = true,
    npc_zombie = true, npc_zombie_torso = true, npc_zombine = true
}

local function IsZevilPlayer(ply)
    return IsValid(ply) and ply:IsPlayer()
        and istable(ply.ZevilVirus) and ply.ZevilVirus.Infected == true
        and ply:Alive()
end

local function EnsureHands(ply)
    if not IsZevilPlayer(ply) then return false end
    if not (weapons and isfunction(weapons.GetStored)
        and weapons.GetStored(HANDS_CLASS)) then return false end

    if not ply:HasWeapon(HANDS_CLASS) then
        local hands = ply:Give(HANDS_CLASS)
        if not IsValid(hands) then return false end
    end

    local active = ply:GetActiveWeapon()
    if not IsValid(active) or active:GetClass() ~= HANDS_CLASS then
        ply:SelectWeapon(HANDS_CLASS)
    end

    return true
end

local function SetNPCRelation(npc, ply, infected)
    if not IsValid(npc) or not npc:IsNPC() or not IsValid(ply) then return end
    if not isfunction(npc.AddEntityRelationship) then return end

    local class = npc:GetClass()
    if infected then
        if undeadClasses[class] then
            npc:AddEntityRelationship(ply, D_LI, 99)
        elseif rebelClasses[class] or combineClasses[class] then
            npc:AddEntityRelationship(ply, D_HT, 99)
        end
    else
        -- Restore the same broad relationships the native headcrab-zombie class
        -- restores when it is removed. The player's previous class can refine them.
        if rebelClasses[class] then
            npc:AddEntityRelationship(ply, D_LI, 99)
        elseif combineClasses[class] or undeadClasses[class] then
            npc:AddEntityRelationship(ply, D_HT, 99)
        end
    end
end

local function UpdateNPCRelations(ply, infected)
    if not SERVER or not IsValid(ply) then return end
    for _, ent in ipairs(ents.GetAll()) do
        SetNPCRelation(ent, ply, infected)
    end

    local hookName = "ZevilClassNPCRelations_" .. ply:EntIndex()
    hook.Remove("OnEntityCreated", hookName)
    if infected then
        hook.Add("OnEntityCreated", hookName, function(ent)
            timer.Simple(0, function()
                if not IsValid(ent) or not IsValid(ply)
                    or ply.PlayerClassName ~= CLASS_NAME
                    or not IsZevilPlayer(ply) then return end
                SetNPCRelation(ent, ply, true)
            end)
        end)
    end
end

local function ApplyZevilPlayerClass(ply, retries)
    retries = retries or 0
    if not IsZevilPlayer(ply) then return false end

    local classList = player and player.classList
    if not (istable(classList) and istable(classList[CLASS_NAME])
        and isfunction(ply.SetPlayerClass)) then
        if retries < 40 and not ply.ZevilClassApplyPending then
            ply.ZevilClassApplyPending = true
            timer.Simple(0.5, function()
                if not IsValid(ply) then return end
                ply.ZevilClassApplyPending = nil
                ApplyZevilPlayerClass(ply, retries + 1)
            end)
        end
        return false
    end

    if ply.PlayerClassName == CLASS_NAME then
        EnsureHands(ply)
        return true
    end

    if not ply.ZevilClassStateSaved then
        ply.ZevilClassStateSaved = true
        local oldClass = isstring(ply.PlayerClassName) and ply.PlayerClassName or ""
        ply.ZevilPreviousPlayerClass = oldClass ~= CLASS_NAME and oldClass or ""
        local active = ply:GetActiveWeapon()
        ply.ZevilPreviousWeaponClass = IsValid(active) and active:GetClass() or ""
    end

    ply:SetPlayerClass(CLASS_NAME)
    EnsureHands(ply)
    return true
end

local function RestoreZevilPlayerClass(ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply.ZevilClassStateSaved then return end

    local shouldRestore = ply:Alive() and ply.PlayerClassName == CLASS_NAME
    local previousClass = ply.ZevilPreviousPlayerClass or ""
    local previousWeapon = ply.ZevilPreviousWeaponClass or ""

    ply.ZevilClassStateSaved = nil
    ply.ZevilPreviousPlayerClass = nil
    ply.ZevilPreviousWeaponClass = nil
    ply.ZevilClassApplyPending = nil

    if not shouldRestore then return end

    local classList = player and player.classList or {}
    if previousClass == "" or not istable(classList[previousClass]) then
        previousClass = "none"
    end

    ply:SetPlayerClass(previousClass)

    timer.Simple(0, function()
        if not IsValid(ply) or not ply:Alive()
            or (istable(ply.ZevilVirus) and ply.ZevilVirus.Infected) then return end
        if previousWeapon ~= "" and ply:HasWeapon(previousWeapon) then
            ply:SelectWeapon(previousWeapon)
        end
    end)
end

local function RegisterZevilClass()
    if not (player and isfunction(player.RegClass)) then return false end

    local class = player.RegClass(CLASS_NAME)
    if class.ZevilClassBridgeInstalled then return true end
    class.ZevilClassBridgeInstalled = true
    class.CanUseDefaultPhrase = false
    class.CanEmitRNDSound = false
    class.CanUseGestures = false

    function class.On(ply)
        if not SERVER or not IsValid(ply) or not ply:IsPlayer() then return end
        if not IsZevilPlayer(ply) then return end
        UpdateNPCRelations(ply, true)
        timer.Simple(0, function()
            if IsValid(ply) and ply.PlayerClassName == CLASS_NAME then EnsureHands(ply) end
        end)
    end

    function class.Off(ply)
        if not SERVER or not IsValid(ply) or not ply:IsPlayer() then return end
        UpdateNPCRelations(ply, false)
    end

    function class.Think(ply)
        if not SERVER or not IsZevilPlayer(ply) or ply.PlayerClassName ~= CLASS_NAME then return end
        EnsureHands(ply)

        -- Keep only the safe, useful organism adjustments from the Z-City zombie
        -- class. Do not clear organ damage, dislocations, blood loss, or wounds.
        local org = ply.organism
        if not istable(org) then return end
        if istable(org.stamina) then
            org.stamina.max = 200
            org.stamina.range = 200
        end
        if istable(org.o2) then org.o2.curregen = 2 end
        org.pulse = 70
        if isnumber(org.brain) and org.brain > 0 and org.brain < 0.1 then
            org.brain = 0.05
        end
    end

    function class.PlayerDeath(ply)
        if SERVER and IsValid(ply) then UpdateNPCRelations(ply, false) end
    end

    return true
end

if SERVER then
    hook.Add("Zevil_Infected", "Zevil_ApplyZCityPlayerClass", function(ent)
        if IsValid(ent) and ent:IsPlayer() then ApplyZevilPlayerClass(ent) end
    end)

    hook.Add("Zevil_Cured", "Zevil_RestoreZCityPlayerClass", function(ent)
        if IsValid(ent) and ent:IsPlayer() then RestoreZevilPlayerClass(ent) end
    end)

    hook.Add("Player Think", "Zevil_KeepZCityClassAndHands", function(ply)
        if IsZevilPlayer(ply) then ApplyZevilPlayerClass(ply) end
    end)
end

-- The infection addon may autorun before Homigrad's class manager. Register as
-- soon as the native player.RegClass API is ready, then attach any early infections.
timer.Create("Zevil_RegisterZCityPlayerClass", 0.25, 0, function()
    if not RegisterZevilClass() then return end
    timer.Remove("Zevil_RegisterZCityPlayerClass")
    if SERVER then
        for _, ply in ipairs(player.GetAll()) do
            if IsZevilPlayer(ply) then ApplyZevilPlayerClass(ply) end
        end
    end
end)

RegisterZevilClass()

if SERVER then
    hook.Add("HG_MovementCalc_2", "Zevil_ZCitySpeedMultiplier", function(mul, ply)
        if not IsValid(ply) or ply.PlayerClassName ~= CLASS_NAME
            or not IsZevilPlayer(ply) or not istable(mul) then return end

        -- Match Z-City's headcrab-zombie movement convention: 0.8 walking,
        -- 1.2 sprinting, and the native 70 speed-gain setting.
        local multiplier = ply:IsSprinting() and 1.2 or 0.8
        local stage = math.Clamp(tonumber(ply.ZevilVirus.Stage) or 1, 1, 5)
        if stage >= 4 then multiplier = multiplier * 0.86 end
        if stage >= 5 then multiplier = multiplier * 0.86 end
        mul[1] = multiplier
        if ply.SpeedGainMul ~= 70 then ply.SpeedGainMul = 70 end
    end)

    hook.Add("PlayerCanPickupWeapon", "Zevil_ZCityHandsOnlyPickup", function(ply, weapon)
        if IsValid(ply) and ply.PlayerClassName == CLASS_NAME
            and IsValid(weapon) and weapon:GetClass() ~= HANDS_CLASS then
            return false
        end
    end)

    hook.Add("PlayerSwitchWeapon", "Zevil_ZCityHandsOnlySwitch", function(ply, oldWeapon, newWeapon)
        if IsValid(ply) and ply.PlayerClassName == CLASS_NAME
            and IsValid(newWeapon) and newWeapon:GetClass() ~= HANDS_CLASS then
            return true
        end
    end)

    hook.Add("PlayerCanLegAttack", "Zevil_ZCityDisableLegAttacks", function(ply)
        if IsValid(ply) and ply.PlayerClassName == CLASS_NAME then return false end
    end)

    hook.Add("CanPlayerEnterVehicle", "Zevil_ZCityNoVehicles", function(ply)
        if IsValid(ply) and ply.PlayerClassName == CLASS_NAME then return false end
    end)

    hook.Add("HG_PlayerCanHearPlayersVoice", "Zevil_ZCityInfectedVoice", function(listener, speaker)
        if IsValid(speaker) and speaker.PlayerClassName == CLASS_NAME then
            return false, false
        end
    end)

    hook.Add("HG_PlayerFootstep", "Zevil_ZCityFootsteps", function(ply)
        if not IsZevilPlayer(ply) or ply.PlayerClassName ~= CLASS_NAME then return end
        if IsValid(ply.FakeRagdoll) and isfunction(ply.GetNetVar)
            and ply:GetNetVar("lastFake", 0) == 0 then return end

        local character = hg and isfunction(hg.GetCurrentCharacter)
            and hg.GetCurrentCharacter(ply) or ply
        if not IsValid(character) then return end
        if not ply:IsSprinting() and (ply:KeyDown(IN_DUCK) or ply:KeyDown(IN_WALK)) then
            character:EmitSound("npc/zombie/foot_slide" .. math.random(1, 3) .. ".wav",
                60, math.random(95, 105), 0.5)
        else
            character:EmitSound("npc/zombie/foot" .. math.random(1, 3) .. ".wav",
                65, math.random(95, 105))
        end
        return true
    end)
else
    hook.Add("CalcMainActivity", "Zevil_ZCityInfectedAnimations", function(ply, velocity)
        if not IsValid(ply) or ply.PlayerClassName ~= CLASS_NAME then return end

        local anim = ACT_HL2MP_RUN_ZOMBIE
        if velocity:LengthSqr() <= 0 then
            anim = ACT_HL2MP_IDLE_ZOMBIE
        end
        if ply:IsFlagSet(FL_ANIMDUCKING) then
            anim = ACT_HL2MP_WALK_CROUCH_ZOMBIE_01
        end
        if not ply:OnGround() and ply:GetMoveType() ~= MOVETYPE_NOCLIP then
            if velocity:Length2DSqr() >= 17000 then
                anim = ACT_HL2MP_RUN_ZOMBIE_FAST
            else
                anim = ACT_HL2MP_JUMP_SLAM
            end
        end

        return anim, -1
    end)

    hook.Add("UpdateAnimation", "Zevil_ZCityInfectedAnimationRate", function(ply, velocity, maxSeqGroundSpeed)
        if not IsValid(ply) or ply.PlayerClassName ~= CLASS_NAME or not ply:Alive() then return end
        if velocity:LengthSqr() >= 77000 and velocity:LengthSqr() < 110000 then
            ply:SetPlaybackRate(1.1)
            return ply, velocity, maxSeqGroundSpeed
        end
        if velocity:LengthSqr() >= 17000 then
            ply:SetPlaybackRate(1.2)
            return ply, velocity, maxSeqGroundSpeed
        end
        if not ply:OnGround() then
            ply:SetPlaybackRate(0.8)
            return ply, velocity, maxSeqGroundSpeed
        end
    end)
end

-- Make the native blood module clot Zevil's ordinary open wounds at 35% of
-- its normal rate. Wrapping only module.blood[2] keeps Z-City in control of
-- actual bleeding, physiology, networking and organism lifecycle.
if SERVER then
    local function InstallInfectedClotting()
        local organism = hg and hg.organism
        local blood = organism and organism.module and organism.module.blood
        if not istable(blood) or not isfunction(blood[2]) then return false end
        if blood[2].ZevilSlowerClotting then return true end

        local nativeBloodThink = blood[2]
        local function SlowerClotting(owner, org, mulTime)
            local virus = IsValid(owner) and owner.ZevilVirus or nil
            if not (istable(virus) and virus.Infected == true
                and IsValid(owner) and owner:Health() > 0
                and istable(org) and istable(org.wounds)) then
                return nativeBloodThink(owner, org, mulTime)
            end

            local before = {}
            for index, wound in ipairs(org.wounds) do
                if istable(wound) and isnumber(wound[1]) and wound[1] > 0 then
                    before[wound] = {size = wound[1], index = index}
                end
            end

            local resultA, resultB, resultC = nativeBloodThink(owner, org, mulTime)
            if not IsValid(owner) or not istable(org.wounds) then
                return resultA, resultB, resultC
            end

            local present = {}
            for _, wound in ipairs(org.wounds) do present[wound] = true end
            local changed = false
            for wound, state in pairs(before) do
                local remaining = math.max(tonumber(wound[1]) or 0, 0)
                local normalReduction = math.max(state.size - remaining, 0)
                if normalReduction > 0 then
                    local slowedRemaining = math.max(state.size - normalReduction * 0.35, remaining)
                    wound[1] = slowedRemaining
                    changed = true
                    if slowedRemaining > 0 and not present[wound] then
                        table.insert(org.wounds, math.min(state.index, #org.wounds + 1), wound)
                        present[wound] = true
                    end
                end
            end

            if changed and isfunction(owner.SetNetVar) then
                pcall(owner.SetNetVar, owner, "wounds", org.wounds)
            end
            return resultA, resultB, resultC
        end

        SlowerClotting.ZevilSlowerClotting = true
        SlowerClotting.ZevilNativeFunction = nativeBloodThink
        blood[2] = SlowerClotting
        print("[Zevil] Installed native Z-City slower-clotting adapter (35% clot speed).")
        return true
    end

    timer.Create("Zevil_ZCityClottingAdapter", 1, 0, function()
        if InstallInfectedClotting() then
            timer.Remove("Zevil_ZCityClottingAdapter")
        end
    end)
    InstallInfectedClotting()
end
