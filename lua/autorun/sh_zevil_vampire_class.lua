-- Native Z-City vampire player class.
-- This is an addon class: it registers through player.RegClass and leaves the
-- base class manager, player model, organism lifecycle, and injury code intact.
if SERVER then AddCSLuaFile() end

local CLASS_NAME = "vampire"

local function RegisterVampireClass()
    if not (player and isfunction(player.RegClass)) then return false end

    local class = player.RegClass(CLASS_NAME)
    if class.ZevilNativeVampireInstalled then return true end
    class.ZevilNativeVampireInstalled = true

    class.CanUseDefaultPhrase = true
    class.CanEmitRNDSound = true
    class.CanUseGestures = true

    function class.On(ply)
        if not SERVER or not IsValid(ply) or not ply:IsPlayer() then return end

        -- Preserve the prior native class so the optional cure command can
        -- restore it rather than forcing everyone into the default class.
        if not ply.ZevilVampirePreviousClassSaved then
            local oldClass = isstring(ply.PlayerClassNameOld) and ply.PlayerClassNameOld or ""
            if oldClass ~= CLASS_NAME then
                ply.ZevilVampirePreviousClass = oldClass
                ply.ZevilVampirePreviousClassSaved = true
            end
        end

        if not ply.ZevilVampireOriginalStats then
            ply.ZevilVampireOriginalStats = {
                maxHealth = isfunction(ply.GetMaxHealth) and ply:GetMaxHealth() or 100,
                jumpPower = isfunction(ply.GetJumpPower) and ply:GetJumpPower() or 200
            }
        end

        ply:SetMaxHealth(math.max(150, ply:GetMaxHealth()))
        if isfunction(ply.SetJumpPower) then
            local original = ply.ZevilVampireOriginalStats.jumpPower or 200
            ply:SetJumpPower(math.max(200, original * 1.3))
        end
        ply:SetNW2Bool("ZevilVampireActive", true)
        ply:SetNW2Bool("ZevilVampireDrinking", false)
        ply:SetNW2Bool("ZevilVampireBeingBitten", false)
    end

    function class.Off(ply)
        if not SERVER or not IsValid(ply) or not ply:IsPlayer() then return end

        local system = ZevilVampire
        if system and isfunction(system.StopDrinking) then
            system.StopDrinking(ply, "class changed")
        end

        ply:SetNW2Bool("ZevilVampireActive", false)
        ply:SetNW2Bool("ZevilVampireDrinking", false)

        local stats = ply.ZevilVampireOriginalStats
        ply.ZevilVampireOriginalStats = nil
        if stats then
            local maxHealth = math.max(1, tonumber(stats.maxHealth) or 100)
            ply:SetMaxHealth(maxHealth)
            if ply:Health() > maxHealth then ply:SetHealth(maxHealth) end
            if isfunction(ply.SetJumpPower) then
                ply:SetJumpPower(math.max(0, tonumber(stats.jumpPower) or 200))
            end
        end
    end

    function class.PlayerDeath(ply)
        if SERVER and IsValid(ply) and ZevilVampire
            and isfunction(ZevilVampire.StopDrinking) then
            ZevilVampire.StopDrinking(ply, "death")
        end
    end

    return true
end

-- Autorun files can execute before Homigrad's class manager. Retry until the
-- native registration API exists rather than shadowing or replacing it.
timer.Create("Zevil_RegisterNativeVampireClass", 0.25, 0, function()
    if RegisterVampireClass() then
        timer.Remove("Zevil_RegisterNativeVampireClass")
    end
end)
RegisterVampireClass()

if CLIENT then
    hook.Add("CalcMainActivity", "Zevil_VampireFeedingPose", function(ply)
        if not IsValid(ply) then return end
        if not (ply:GetNW2Bool("ZevilVampireDrinking")
            or ply:GetNW2Bool("ZevilVampireBeingBitten")) then return end
        if not ply:OnGround() then return end
        return ACT_HL2MP_IDLE_CROUCH, -1
    end)
end
