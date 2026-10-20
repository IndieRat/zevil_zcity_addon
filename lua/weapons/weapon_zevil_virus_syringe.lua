-- Zevil infection delivery syringe.
-- Standalone SWEP: does not depend on Z-City's medical weapon implementation.
if SERVER then AddCSLuaFile() end

SWEP.Base = "weapon_bandage_sh"
SWEP.PrintName = "Zevil Virus Syringe"
SWEP.Author = "Zevil Z-City"
SWEP.Instructions = "LMB: inject yourself. RMB: inject a nearby person or NPC."
SWEP.Category = "Zevil - Biohazard"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.UseHands = true
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.showstats = false
SWEP.modeNames = {[1] = "viral dose"}
SWEP.Slot = 4
SWEP.SlotPos = 3
SWEP.HoldType = "normal"
SWEP.ViewModel = ""
SWEP.WorldModel = "models/bloocobalt/l4d/items/w_eq_adrenaline.mdl"
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local INJECTION_RANGE = 112
local INJECTION_COOLDOWN = 1.1

local function Tell(ply, message)
    if not IsValid(ply) then return end
    if ply:IsPlayer() then
        ply:ChatPrint("[Zevil] " .. message)
    end
end

local function IsValidVirusHost(ent)
    return IsValid(ent)
        and (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot())
        and ent:Health() > 0
        and not (ent:IsPlayer() and not ent:Alive())
        and not (ent:IsPlayer() and ent:Team() == TEAM_SPECTATOR)
end

local function ResolveHitTarget(ent)
    if not IsValid(ent) then return nil end

    -- Allow injecting a managed NPC while its Z-City knockdown ragdoll is the
    -- visible hit target; the owner stays the authoritative gameplay entity.
    local owner = ent.BZCNNPCOwner
    if not IsValid(owner) and istable(ent.organism) then
        owner = ent.organism.owner
    end
    if IsValid(owner) and owner ~= ent then ent = owner end

    if IsValidVirusHost(ent) then return ent end
    return nil
end

function SWEP:CanInject()
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() or not owner:Alive() or self.ZevilSpent then return false end
    if (self.ZevilNextInjection or 0) > CurTime() then return false end
    self.ZevilNextInjection = CurTime() + INJECTION_COOLDOWN
    self:SetNextPrimaryFire(CurTime() + INJECTION_COOLDOWN)
    self:SetNextSecondaryFire(CurTime() + INJECTION_COOLDOWN)
    return true
end

function SWEP:Inject(target, owner)
    if not SERVER then return end
    if not IsValid(owner) or not owner:IsPlayer() or not owner:Alive() then return end
    if not IsValidVirusHost(target) then
        Tell(owner, "There is no valid living target to inject.")
        return
    end
    if not Zevil or not isfunction(Zevil.Infect) then
        Tell(owner, "The virus system is not loaded. Check the server console for [Zevil] startup errors.")
        return
    end

    if target.ZevilVirus and target.ZevilVirus.Infected then
        Tell(owner, "That target is already infected; the syringe is still intact.")
        return
    end

    -- Capture display facts before Z.Infect: fully infected human NPCs are
    -- replaced by a roaming NextBot inside the infection hook.
    local injectingSelf = target == owner
    local targetIsPlayer = target:IsPlayer()
    local targetName = target.BZCNDisplayName
        or (targetIsPlayer and target:Nick() or target:GetClass())
    target:EmitSound("snd_jack_hmcd_needleprick.wav", 62, math.random(96, 104))

    local ok = Zevil.Infect(target, owner)
    if not ok then
        Tell(owner, "Injection failed. The virus system may be disabled or the target may be invalid.")
        return
    end

    if injectingSelf then
        if IsValid(target) then target:ViewPunch(Angle(-2, math.Rand(-1.5, 1.5), 0)) end
        Tell(owner, "You injected the Zevil virus into yourself.")
    elseif targetIsPlayer then
        if IsValid(target) then
            target:ViewPunch(Angle(-1.5, math.Rand(-1, 1), 0))
            Tell(target, "You have been injected with an unknown virus.")
        end
        Tell(owner, "Injected " .. targetName .. ".")
    else
        Tell(owner, "Injected " .. targetName .. ".")
    end

    hook.Run("Zevil_VirusInjected", target, owner)
    self.ZevilSpent = true
    if isfunction(self.SetHolding) then self:SetHolding(100) end

    -- Leave the syringe in hand briefly so Z-City's arm pose can play, then
    -- consume it and return the player to hands.
    timer.Simple(0.65, function()
        if not IsValid(owner) then return end
        owner:SelectWeapon("weapon_hands_sh")
        owner:StripWeapon("weapon_zevil_virus_syringe")
    end)
end

function SWEP:PrimaryAttack()
    if not self:CanInject() then return end
    local owner = self:GetOwner()
    if SERVER then
        self:Inject(owner, owner)
    end
end

function SWEP:SecondaryAttack()
    if not self:CanInject() then return end
    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    if SERVER then
        local startPos = owner:GetShootPos()
        local trace = util.TraceLine({
            start = startPos,
            endpos = startPos + owner:GetAimVector() * INJECTION_RANGE,
            filter = owner,
            mask = MASK_SHOT
        })
        local target = trace.Hit and ResolveHitTarget(trace.Entity) or nil
        if not IsValid(target) then
            Tell(owner, "Aim at a living person or NPC within arm's reach.")
            return
        end
        if target == owner then
            Tell(owner, "Use primary attack to inject yourself.")
            return
        end
        self:Inject(target, owner)
    end
end

function SWEP:Reload()
    -- The item is deliberately single-use; reload does not manufacture a dose.
    return false
end
