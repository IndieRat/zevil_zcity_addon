AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

local MODELS = {
    -- Zevil infected intentionally use ordinary civilian player models. The
    -- infected identity comes from behavior, pose, and mouth bleeding, not a
    -- static zombie model that can lack the right skeleton or physics.
    "models/player/group01/male_01.mdl",
    "models/player/group01/male_02.mdl",
    "models/player/group01/male_03.mdl",
    "models/player/group01/male_04.mdl",
    "models/player/group01/male_05.mdl",
    "models/player/group01/male_06.mdl",
    "models/player/group01/male_07.mdl",
    "models/player/group01/male_08.mdl",
    "models/player/group01/male_09.mdl",
    "models/player/group01/female_01.mdl",
    "models/player/group01/female_02.mdl",
    "models/player/group01/female_03.mdl",
    "models/player/group01/female_04.mdl",
    "models/player/group01/female_05.mdl",
    "models/player/group01/female_06.mdl",
    "models/player/group03/male_01.mdl",
    "models/player/group03/male_02.mdl",
    "models/player/group03/male_03.mdl",
    "models/player/group03/male_04.mdl",
    "models/player/group03/male_05.mdl",
    "models/player/group03/male_06.mdl",
    "models/player/group03/male_07.mdl",
    "models/player/group03/male_08.mdl",
    "models/player/group03/male_09.mdl",
    "models/player/group03/female_01.mdl",
    "models/player/group03/female_02.mdl",
    "models/player/group03/female_03.mdl",
    "models/player/group03/female_04.mdl",
    "models/player/group03/female_05.mdl",
    "models/player/group03/female_06.mdl"
}

local function GetInfectedModel(requested)
    if isstring(requested) and requested ~= ""
        and (string.StartWith(string.lower(requested), "models/player/group01/")
            or string.StartWith(string.lower(requested), "models/player/group03/"))
        and util.IsValidModel(requested) then
        return requested
    end
    local available = {}
    for _, model in ipairs(MODELS) do
        if util.IsValidModel(model) then available[#available + 1] = model end
    end
    if #available > 0 then return available[math.random(#available)] end
    return "models/player/group03/male_07.mdl"
end

local function CountZevilInfected()
    local count = 0
    for _, ent in ipairs(ents.FindByClass("npc_zevil_infected")) do
        if IsValid(ent) then count = count + 1 end
    end
    return count
end

function ENT:SpawnFunction(ply, trace, className)
    if not trace or not trace.Hit then return end
    local limit = GetConVar("zevil_max_infected")
    if limit and CountZevilInfected() >= limit:GetInt() then
        if IsValid(ply) and ply:IsPlayer() then
            ply:ChatPrint("[Zevil] Infected NPC limit reached. Increase zevil_max_infected to spawn more.")
        end
        return
    end

    local zombie = ents.Create(className or "npc_zevil_infected")
    if not IsValid(zombie) then return end
    zombie:SetPos(trace.HitPos + trace.HitNormal * 8)
    zombie:SetAngles(Angle(0, IsValid(ply) and ply:EyeAngles().y or 0, 0))
    zombie:Spawn()
    zombie:Activate()
    return zombie
end
local function isAliveTarget(ent)
    return IsValid(ent) and ent ~= NULL and ent:Health() > 0
        and (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot())
        and not (ent:IsPlayer() and not ent:Alive())
        and not (ent.ZevilVirus and ent.ZevilVirus.Infected)
end

local function HasInfectedAppearanceSkeleton(ent)
    return IsValid(ent) and isfunction(ent.LookupBone)
        and ent:LookupBone("ValveBiped.Bip01_Pelvis") ~= nil
        and ent:LookupBone("ValveBiped.Bip01_Spine2") ~= nil
        and ent:LookupBone("ValveBiped.Bip01_Head1") ~= nil
end

local function RandomizeInfectedFallbackAppearance(self)
    -- Keep a supported ValveBiped fallback if the appearance catalogue selects
    -- a model that cannot drive the procedural puppet.
    self:SetModel(GetInfectedModel())
    local skinCount = isfunction(self.SkinCount) and self:SkinCount() or 1
    if skinCount > 0 then self:SetSkin(math.random(0, skinCount - 1)) end
    for _, group in ipairs(self:GetBodyGroups() or {}) do
        local id, count = tonumber(group.id), tonumber(group.num) or 0
        if id and id >= 0 and count > 1 then
            self:SetBodygroup(id, math.random(0, count - 1))
        end
    end
end

local function ApplyHGInfectedAppearance(self)
    local appearanceAPI = hg and hg.Appearance
    if not (appearanceAPI and isfunction(appearanceAPI.GetRandomAppearance)
        and isfunction(appearanceAPI.ForceApplyAppearance)) then
        return false
    end

    local ok, raw = pcall(appearanceAPI.GetRandomAppearance)
    if not ok or not istable(raw) then
        ErrorNoHalt("[Zevil] Could not generate a Z-City infected appearance: "
            .. tostring(raw) .. "\n")
        return false
    end

    local appearance = table.Copy(raw)
    if isstring(appearance.AModel) and not util.IsValidModel(appearance.AModel) then
        appearance.AModel = nil
    end
    -- Keep Z-City's random model/clothing, but remove civilian accessories.
    appearance.AAttachments = ""

    local modelSex = BZCN and isfunction(BZCN.GetModelSex)
        and BZCN.GetModelSex(appearance.AModel) or nil
    if BZCN and isfunction(BZCN.GetRandomHumanName) then
        appearance.AName = BZCN.GetRandomHumanName(modelSex or appearance.AModel)
    end

    local fallbackModel = self:GetModel()
    local savedMethods = {}
    local function InstallShim(name, fn)
        savedMethods[#savedMethods + 1] = {name, self[name]}
        self[name] = fn
    end
    InstallShim("SetPlayerColor", function(ent, color)
        if not isvector(color) then return end
        ent.BZCNPlayerColor = color
        if ent.SetNW2Vector then ent:SetNW2Vector("PlayerColor", color) end
    end)
    InstallShim("SetNWVector", function(ent, key, value)
        if ent.SetNW2Vector and isvector(value) then ent:SetNW2Vector(key, value) end
    end)
    InstallShim("SetBodyGroups", function(ent, groups)
        if not isstring(groups) then return end
        for _, bodygroup in ipairs(ent:GetBodyGroups() or {}) do
            local id = tonumber(bodygroup.id)
            if id and id >= 0 then
                local digit = string.sub(groups, id + 1, id + 1)
                if digit ~= "" then ent:SetBodygroup(id, tonumber(digit) or 0) end
            end
        end
    end)

    local applied, result = pcall(appearanceAPI.ForceApplyAppearance, self, appearance)
    for _, saved in ipairs(savedMethods) do self[saved[1]] = saved[2] end

    if not applied or not util.IsValidModel(self:GetModel())
        or not HasInfectedAppearanceSkeleton(self) then
        self:SetModel(fallbackModel)
        if not self.ZevilAppearanceWarned then
            self.ZevilAppearanceWarned = true
            ErrorNoHalt("[Zevil] Z-City infected appearance was incompatible; using a "
                .. "ValveBiped citizen fallback. " .. tostring(result or "") .. "\n")
        end
        return false
    end

    self.CurAppearance = table.Copy(appearance)
    self.BZCNDisplayName = appearance.AName
    self.PlayerName = appearance.AName
    self:SetNW2String("BZCNDisplayName", appearance.AName or ("Infected " .. self:EntIndex()))
    if isfunction(self.SetNetVar) then
        pcall(self.SetNetVar, self, "Accessories", "")
        pcall(self.SetNetVar, self, "PlayerName", appearance.AName or ("Infected " .. self:EntIndex()))
    elseif BZCN and isfunction(BZCN.SetNetVar) then
        pcall(BZCN.SetNetVar, self, "Accessories", "")
        pcall(BZCN.SetNetVar, self, "PlayerName", appearance.AName or ("Infected " .. self:EntIndex()))
    end
    return true
end

local function SetupBZCNCompatibility(self)
    if not BZCN or not isfunction(BZCN.InstallAdapter) or not isfunction(BZCN.GetClass) then return end

    -- Mark the NextBot as managed and apply the registered BZCN zombie
    -- profile. Native organism ownership is still established separately by
    -- hg.BZCNNPCSupport.Attach below, never by fabricating a Player character.
    self.BZCNManaged = true
    self.BZCNClass = "ZevilInfected"
    self.PlayerClassName = "ZevilInfected"
    self.BZCNClassProfile = table.Copy(BZCN.GetClass("ZevilInfected") or {})
    self:SetNW2Bool("BZCNManaged", true)
    self:SetNW2String("BZCNClass", "ZevilInfected")
    self:SetNW2String("PlayerClassName", "ZevilInfected")
    self:SetNW2String("BZCNClassName", "Zevil Infected")
    self.BZCN_Faction = "zombie"
    self.BZCN_TeamName = "Zevil"
    self:SetNW2String("BZCNFaction", "zombie")
    self:SetNW2String("BZCNTeamName", "Zevil")

    -- Run the same BZCN class application that gives its native headcrab
    -- zombie the ZombieStyle appearance/material treatment. The actual model
    -- remains Zevil's randomized civilian model; ApplyClass sets class metadata
    -- and materials but does not replace the current entity model.
    local classApplied = false
    if isfunction(BZCN.ApplyClass) then
        local ok, result = pcall(BZCN.ApplyClass, self, "ZevilInfected", true)
        classApplied = ok and result == true
        if not ok then
            ErrorNoHalt("[Zevil] BZCN infected class application failed: " .. tostring(result) .. "\n")
        end
    end
    if not classApplied then
        local ok, err = pcall(BZCN.InstallAdapter, self)
        if not ok then
            ErrorNoHalt("[Zevil] Could not install BZCN adapter: " .. tostring(err) .. "\n")
        end
    end

    local formerName = string.Trim(tostring(self.ZevilFormerName
        or (istable(self.CurAppearance) and self.CurAppearance.AName) or ""))
    local displayName = formerName ~= "" and (formerName .. " (infected)") or ("Infected " .. tostring(self:EntIndex()))
    self.BZCNDisplayName = displayName
    self.PlayerName = displayName
    self:SetNW2String("BZCNDisplayName", displayName)
    if isfunction(BZCN.SetNetVar) then
        BZCN.SetNetVar(self, "PlayerName", displayName)
        BZCN.SetNetVar(self, "BZCNFaction", "zombie")
        BZCN.SetNetVar(self, "Inventory", {
            Weapons = {}, Items = {}, Ammo = {}, Attachments = {}, Armor = {}
        })
        BZCN.SetNetVar(self, "Armor", {})
    end
end

-- StartActivity resets the sequence cycle, so calling it on every AI coroutine
-- iteration makes the walk/run animation repeatedly jump back to frame one.
-- Keep the current activity stable until the behavior actually changes.
function ENT:SetZevilActivity(activity)
    if self.ZevilCurrentActivity == activity then return end
    self.ZevilCurrentActivity = activity
    self:StartActivity(activity)
end

-- Remember the intended walk/run state while a melee sequence temporarily
-- replaces it. ChaseTarget can remain active for several seconds after a lunge;
-- without a timed return the bot kept trying to locomote in its attack sequence.
function ENT:SetZevilLocomotionActivity(activity)
    self.ZevilLocomotionActivity = activity
    if not self.ZevilAttackUntil or CurTime() >= self.ZevilAttackUntil then
        self:SetZevilActivity(activity)
    end
end

function ENT:PlayZevilAttack(target, duration)
    self.ZevilAttackFacingTarget = IsValid(target) and target or nil
    self.ZevilAttackUntil = CurTime() + (duration or 0.7)
    self:SetZevilActivity(ACT_MELEE_ATTACK1)
end

-- BodyMoveXY drives the locomotion pose, but does not guarantee root yaw is
-- aligned after an attack sequence. Keep the model pointed at its attack target
-- during the swing, then align to its actual travel vector so path cornering does
-- not look like sideways shuffling on civilian models.
function ENT:BodyUpdate()
    if self.BZCNNPCDowned then return end

    local now = CurTime()
    if self.ZevilAttackUntil and now >= self.ZevilAttackUntil then
        self.ZevilAttackUntil = nil
        self.ZevilAttackFacingTarget = nil
        if self.ZevilLocomotionActivity then
            self:SetZevilActivity(self.ZevilLocomotionActivity)
        end
    end

    self:BodyMoveXY()

    local desiredYaw
    local attackTarget = self.ZevilAttackFacingTarget
    if self.ZevilAttackUntil and now < self.ZevilAttackUntil
        and IsValid(attackTarget) and attackTarget:Health() > 0 then
        local direction = attackTarget:WorldSpaceCenter() - self:WorldSpaceCenter()
        direction.z = 0
        if direction:LengthSqr() > 1 then
            desiredYaw = direction:Angle().y
        end
    else
        local velocity = self:GetVelocity()
        velocity.z = 0
        if velocity:LengthSqr() > 225 then
            desiredYaw = velocity:Angle().y
        elseif IsValid(self.Target) and self.Target:Health() > 0 then
            local direction = self.Target:WorldSpaceCenter() - self:WorldSpaceCenter()
            direction.z = 0
            if direction:LengthSqr() > 1 then
                desiredYaw = direction:Angle().y
            end
        end
    end

    if desiredYaw then
        -- Fast enough to correct a 180-degree reversal promptly, but still
        -- smooths direction changes as the path curves around an obstacle.
        local turnRate = 1080 * math.max(FrameTime(), 0)
        local yaw = math.ApproachAngle(self:GetAngles().y, desiredYaw, turnRate)
        self:SetAngles(Angle(0, yaw, 0))
    end
end

function ENT:Initialize()
    self:SetModel(GetInfectedModel(self.ZevilModel))
    self:SetHealth(100)
    self:SetMaxHealth(100)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionGroup(COLLISION_GROUP_NPC)
    self:SetColor(Color(132, 145, 112, 255)) -- sickly, desaturated infected skin
    self:SetCollisionBounds(Vector(-13, -13, 0), Vector(13, 13, 72))
    self.loco:SetDesiredSpeed(95)
    self.loco:SetAcceleration(500)
    self.loco:SetDeceleration(700)
    self.loco:SetStepHeight(18)
    self.loco:SetJumpHeight(35)
    self.ZevilInfectedAttacker = true
    self.ZevilVirus = {Infected = true, Stage = 2, Exposure = 100, InfectedAt = CurTime(), NextStage = CurTime() + 120}
    self:SetNW2Bool("ZevilInfected", true)
    self:SetNW2Int("ZevilStage", 2)

    -- Use Z-City's appearance catalogue, including configured/custom player
    -- models and clothing, before applying the registered zombie-style profile.
    -- Models without the required ValveBiped skeleton fall back safely.
    local usedHGAppearance = ApplyHGInfectedAppearance(self)
    if not usedHGAppearance then
        RandomizeInfectedFallbackAppearance(self)
    end
    self.ZevilHGAppearance = usedHGAppearance == true
    self:SetNW2Bool("ZevilHGAppearance", self.ZevilHGAppearance)
    self:SetNW2String("ZevilAppearanceModel", self:GetModel())

    SetupBZCNCompatibility(self)

    if Zevil and isfunction(Zevil.AttachZCityNPCSupport) then
        Zevil.AttachZCityNPCSupport(self, "ZevilInfected", "zombie")
    end
    self.NextBite = 0
    self.NextLunge = 0
    self.NextSearch = 0
    self.Target = nil
end

function ENT:FindVictim()
    local best, bestDist
    for _, ent in ipairs(ents.FindInSphere(self:GetPos(), 1200)) do
        if not isAliveTarget(ent) then continue end
        if ent:IsPlayer() and ent:Team() == TEAM_SPECTATOR then continue end
        local d = self:GetPos():DistToSqr(ent:GetPos())
        if not bestDist or d < bestDist then best, bestDist = ent, d end
    end
    return best
end

function ENT:CanSeeTarget(target)
    if not IsValid(target) then return false end
    local tr = util.TraceLine({
        start = self:EyePos(), endpos = target:WorldSpaceCenter(),
        filter = {self}, mask = MASK_VISIBLE
    })
    return not tr.Hit or tr.Entity == target
end

function ENT:Bite(target)
    if not isAliveTarget(target) or CurTime() < self.NextBite then return end
    if self:GetPos():DistToSqr(target:GetPos()) > 78 * 78 then return end
    self.NextBite = CurTime() + 1.65
    self:PlayZevilAttack(target, 0.72)
    self:EmitSound("npc/zombie/claw_strike" .. math.random(1, 3) .. ".wav", 75, math.random(82, 108))
    local hitPos = target:WorldSpaceCenter()
    util.Decal("Blood", hitPos + Vector(0, 0, 16), hitPos - Vector(0, 0, 48), {self, target})
    local dmg = DamageInfo()
    dmg:SetDamage(12)
    dmg:SetDamageType(DMG_SLASH)
    dmg:SetAttacker(self)
    dmg:SetInflictor(self)
    dmg:SetDamagePosition(target:WorldSpaceCenter())
    self.ZevilBiteDamage = true
    target:TakeDamageInfo(dmg)
    self.ZevilBiteDamage = false
    if Zevil and Zevil.Expose then Zevil.Expose(target, 18, self) end
    if target:IsPlayer() and target:Alive() then
        target:ViewPunch(Angle(math.Rand(-2, 2), math.Rand(-3, 3), 0))
    end
end

function ENT:FindCorpse()
    local best, bestDist
    for _, ent in ipairs(ents.FindInSphere(self:GetPos(), 500)) do
        if not IsValid(ent) or ent == self or ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot() then continue end
        if not ent:GetClass():lower():find("ragdoll", 1, true) then continue end
        local d = self:GetPos():DistToSqr(ent:GetPos())
        if not bestDist or d < bestDist then best, bestDist = ent, d end
    end
    return best
end

function ENT:Feed(corpse)
    if not IsValid(corpse) then return false end
    self.ZevilFeeding = true
    self.ZevilAttackUntil = nil
    self.ZevilAttackFacingTarget = nil
    self.ZevilLocomotionActivity = ACT_IDLE
    self:SetZevilActivity(ACT_IDLE)
    self.loco:SetDesiredSpeed(0)
    self:EmitSound("npc/zombie/zo_attack" .. math.random(1, 2) .. ".wav", 65, 75)
    local finish = CurTime() + 4
    while IsValid(self) and IsValid(corpse) and CurTime() < finish do
        if self:Health() < self:GetMaxHealth() then self:SetHealth(math.min(self:Health() + 1, self:GetMaxHealth())) end
        coroutine.wait(0.5)
    end
    if IsValid(self) then
        self.ZevilFeeding = false
        self.loco:SetDesiredSpeed(95)
    end
    return true
end

function ENT:RunBehaviour()
    while true do
        if not IsValid(self) or self:Health() <= 0 then return end
        if self.BZCNNPCDowned then
            coroutine.wait(0.15)
            continue
        end
        local target = self:FindVictim()
        self.Target = target
        if IsValid(target) then
            local critical = self:Health() <= math.max(self:GetMaxHealth(), 1) * 0.22
            self:SetZevilLocomotionActivity(critical and ACT_WALK or ACT_RUN)
            -- Critically injured infected drag themselves forward in the procedural
            -- crawl pose rather than sprinting upright with a broken-body silhouette.
            self.loco:SetDesiredSpeed(critical and 34 or (95 + (self.ZevilVirus.Stage or 2) * 7))
            if self:CanSeeTarget(target) then
                self:ChaseTarget(target)
            else
                self:MoveToPos(target:GetPos(), {lookahead = 300, tolerance = 50, maxage = 1.5})
            end
        else
            local corpse = self:FindCorpse()
            if IsValid(corpse) then
                self:SetZevilLocomotionActivity(ACT_WALK)
                self.loco:SetDesiredSpeed(65)
                self:MoveToPos(corpse:GetPos(), {tolerance = 45, maxage = 2})
                if IsValid(corpse) and self:GetPos():DistToSqr(corpse:GetPos()) < 55 * 55 then self:Feed(corpse) end
            else
                self:SetZevilLocomotionActivity(ACT_WALK)
                self.loco:SetDesiredSpeed(45)
                self:MoveToPos(self:GetPos() + VectorRand() * math.random(100, 250), {tolerance = 30, maxage = 2})
            end
        end
        coroutine.yield()
    end
end

function ENT:ChaseTarget(target)
    local path = Path("Follow")
    path:SetMinLookAheadDistance(200)
    path:SetGoalTolerance(42)
    path:Compute(self, target:GetPos())
    if not path:IsValid() then return end
    while path:IsValid() and IsValid(target) and isAliveTarget(target) and not self.BZCNNPCDowned do
        local distanceSqr = self:GetPos():DistToSqr(target:GetPos())
        if distanceSqr <= 75 * 75 then
            self:Bite(target)
        elseif distanceSqr <= 150 * 150 and CurTime() >= self.NextLunge then
            -- Occasional forward lunge breaks up the straight-line shamble.
            self.NextLunge = CurTime() + math.Rand(3.5, 6.5)
            self:PlayZevilAttack(target, 0.62)
            local direction = (target:WorldSpaceCenter() - self:WorldSpaceCenter()):GetNormalized()
            self.loco:SetVelocity(direction * math.Rand(170, 245) + Vector(0, 0, 85))
            self:EmitSound("npc/zombie/zo_attack" .. math.random(1, 2) .. ".wav", 72, math.random(80, 100))
        end
        path:Compute(self, target:GetPos())
        path:Update(self)
        if self.loco:IsStuck() then self.loco:ClearStuck() return end
        coroutine.wait(0.15)
    end
end

function ENT:OnInjured(dmg)
    local attacker = dmg:GetAttacker()
    if isAliveTarget(attacker) and not (attacker.ZevilVirus and attacker.ZevilVirus.Infected) then self.Target = attacker end
end

function ENT:OnKilled(dmg)
    -- Keep the live procedural puppet as the corpse so death does not pop into
    -- a second, default-pose ragdoll. The controller detaches it from the AI.
    local rag
    if Zevil and Zevil.InfectedFake and isfunction(Zevil.InfectedFake.Detach) then
        rag = Zevil.InfectedFake.Detach(self, true)
    end

    if not IsValid(rag) then
        rag = ents.Create("prop_ragdoll")
        if IsValid(rag) then
            rag:SetModel(self:GetModel())
            rag:SetPos(self:GetPos())
            rag:SetAngles(self:GetAngles())
            rag:Spawn()
            rag:Activate()
        end
    end

    if IsValid(rag) then
        rag.ZevilCorpse = true
        rag:SetNW2Bool("ZevilFakePuppet", false)
        SafeRemoveEntityDelayed(rag, 180)
    end

    hook.Run("Zevil_InfectedKilled", self, dmg)
    self:Remove()
end
