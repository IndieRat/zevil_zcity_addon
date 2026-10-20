-- Zevil infected procedural ragdoll puppets.
-- This is deliberately independent of Homigrad's player FakeRagdoll/organism path:
-- the NextBot continues to own navigation and AI, while a physics ragdoll follows
-- its animated skeleton with soft shadow control and a small asymmetrical infected pose.
if not SERVER then return end

AddCSLuaFile("autorun/client/cl_zevil_fake_infected.lua")

Zevil = Zevil or {}
Zevil.InfectedFake = Zevil.InfectedFake or {}
local Fake = Zevil.InfectedFake

local enabled = GetConVar("zevil_fake_infected") or CreateConVar(
    "zevil_fake_infected", "1", FCVAR_ARCHIVE,
    "Render Zevil infected NextBots as procedural shadow-controlled ragdolls"
)
local rate = GetConVar("zevil_fake_infected_rate") or CreateConVar(
    "zevil_fake_infected_rate", "20", FCVAR_ARCHIVE,
    "Procedural infected ragdoll control updates per second", 5, 35
)
local strength = GetConVar("zevil_fake_infected_strength") or CreateConVar(
    "zevil_fake_infected_strength", "1", FCVAR_ARCHIVE,
    "Strength of Zevil infected procedural body pose", 0, 2
)

local active = setmetatable({}, {__mode = "k"})
local function IsInfectedBot(ent)
    return IsValid(ent) and ent:GetClass() == "npc_zevil_infected"
end

local function HasUsableSkeleton(ent)
    if not IsValid(ent) or not isfunction(ent.LookupBone) then return false end
    return ent:LookupBone("ValveBiped.Bip01_Pelvis") ~= nil
        and ent:LookupBone("ValveBiped.Bip01_Spine2") ~= nil
        and ent:LookupBone("ValveBiped.Bip01_Head1") ~= nil
end

local function CopyAppearance(source, rag)
    if source.GetSkin and rag.SetSkin then
        local skin = source:GetSkin()
        if skin and skin >= 0 then rag:SetSkin(skin) end
    end

    if source.GetNumBodyGroups and rag.GetNumBodyGroups then
        local maxGroup = math.min(source:GetNumBodyGroups(), rag:GetNumBodyGroups())
        for group = 0, maxGroup - 1 do
            rag:SetBodygroup(group, source:GetBodygroup(group))
        end
    end

    rag:SetColor(source:GetColor())

    -- Do not copy arbitrary material overrides from the source entity. Some
    -- addons store a model/material path here rather than a valid VMT override;
    -- applying that to the ragdoll can trigger shader warnings such as bad $bumpmap.
    -- The ragdoll already uses the same model, skin, bodygroups and authored materials.
end

local function MirrorZCityWounds(host, rag, force)
    if not IsValid(host) or not IsValid(rag) then return end
    local org = host.organism or host.BZCN_Organism
    if not istable(org) then return end

    local wounds = istable(org.wounds) and org.wounds or nil
    local arterial = istable(org.arterialwounds) and org.arterialwounds or nil
    if (not wounds or not arterial) and isfunction(host.GetNetVar) then
        wounds = wounds or host:GetNetVar("wounds", nil)
        arterial = arterial or host:GetNetVar("arterialwounds", nil)
    end
    if not istable(wounds) then wounds = {} end
    if not istable(arterial) then arterial = {} end

    local schedule = tonumber(org.sendPlyTime)
    local changed = force == true
        or rag.ZevilWoundSchedule ~= schedule
        or rag.ZevilWoundSource ~= wounds
        or rag.ZevilArterialWoundSource ~= arterial
        or CurTime() >= (rag.ZevilNextWoundRefresh or 0)
    if not changed then return end

    -- Give the visible puppet the same wound NetVars that Z-City/BZCN publishes
    -- on the living NextBot. Mods such as ABL can then read GetNetVar("wounds")
    -- from the rendered ragdoll rather than searching for a hidden host.
    if BZCN and isfunction(BZCN.InstallAdapter) and not rag.ZevilBZCNAdapterInstalled then
        local ok = pcall(BZCN.InstallAdapter, rag)
        rag.ZevilBZCNAdapterInstalled = ok
    end
    if isfunction(rag.SetNetVar) then
        pcall(rag.SetNetVar, rag, "wounds", table.Copy(wounds))
        pcall(rag.SetNetVar, rag, "arterialwounds", table.Copy(arterial))
    elseif BZCN and isfunction(BZCN.SetNetVar) then
        pcall(BZCN.SetNetVar, rag, "wounds", table.Copy(wounds))
        pcall(BZCN.SetNetVar, rag, "arterialwounds", table.Copy(arterial))
    end

    -- Do not assign rag.organism here. Z-City's damage hook treats any
    -- entity with that field as a live organism, which would process the puppet
    -- hit once and then process it again when this controller forwards damage.
    -- Wound NetVars are enough for ABL and other visual readers.
    rag.BZCNNPCOwner = host
    if rag.SetNW2Entity then rag:SetNW2Entity("BZCNNPCOwner", host) end
    if rag.SetNWEntity then rag:SetNWEntity("BZCNNPCOwner", host) end
    rag.ZevilWoundSchedule = schedule
    rag.ZevilWoundSource = wounds
    rag.ZevilArterialWoundSource = arterial
    rag.ZevilNextWoundRefresh = CurTime() + 0.75
end

local function SuspendPuppetForZCityDowned(host, puppet)
    active[host] = nil
    host.ZevilFakePuppet = nil
    if IsValid(puppet) then
        puppet.ZevilPuppetOwner = nil
        puppet:SetNW2Bool("ZevilFakePuppet", false)
        SafeRemoveEntity(puppet)
    end

    -- BZCN's injury support owns the real downed ragdoll and recovery animation.
    -- Never show our upright shadow puppet alongside that physical body.
    host:SetNoDraw(true)
    host:DrawShadow(false)
    host.ZevilFakeUsingZCityDowned = true
end

function Fake.Detach(host, keepCorpse)
    if not IsValid(host) then return nil end

    local rag = host.ZevilFakePuppet or active[host]
    active[host] = nil
    host.ZevilFakePuppet = nil

    if IsValid(rag) then
        rag.ZevilPuppetOwner = nil
        rag:SetNW2Bool("ZevilFakePuppet", false)
        if not keepCorpse then SafeRemoveEntity(rag) end
    end

    if not keepCorpse then
        host:SetNoDraw(false)
        host:DrawShadow(true)
        host.ZevilFakeDetached = false
    else
        host.ZevilFakeDetached = true
    end

    return rag
end

function Fake.Attach(host, forceRefresh)
    if not enabled:GetBool() or not IsInfectedBot(host) then return false end
    if not HasUsableSkeleton(host) then return false end

    local existing = host.ZevilFakePuppet
    if IsValid(existing) and not forceRefresh and existing:GetModel() == host:GetModel() then
        return true
    end
    if IsValid(existing) then Fake.Detach(host, false) end

    local model = host:GetModel()
    if not isstring(model) or model == "" or not util.IsValidModel(model) then return false end

    local rag = ents.Create("prop_ragdoll")
    if not IsValid(rag) then return false end
    rag:SetModel(model)
    rag:SetPos(host:GetPos())
    rag:SetAngles(host:GetAngles())
    rag:Spawn()
    rag:Activate()

    if not IsValid(rag) or rag:GetPhysicsObjectCount() < 5
        or not HasUsableSkeleton(rag) then
        if IsValid(rag) then SafeRemoveEntity(rag) end
        return false
    end

    CopyAppearance(host, rag)
    rag:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    rag:SetNW2Bool("ZevilFakePuppet", true)
    rag:SetNW2Int("ZevilStage", host:GetNW2Int("ZevilStage", 2))
    rag.ZevilPuppetOwner = host
    rag.ZevilPuppetConstraint = constraint.NoCollide(host, rag, 0, 0)
    MirrorZCityWounds(host, rag, true)

    host.ZevilFakePuppet = rag
    host:SetNoDraw(true)
    host:DrawShadow(false)
    active[host] = rag

    -- Do not copy the animated NPC's origin into the ragdoll every frame. The
    -- individual physics bodies are eased toward bone targets below, so hits and
    -- ground contact can make the body lag and settle instead of snapping.
    return true
end

local function ApplyInfectedPose(name, angle, time, phase, movement, amount, crawling)
    local a = Angle(angle.p, angle.y, angle.r)
    local isLeft = name:find("_l_", 1, true) ~= nil
    local isRight = name:find("_r_", 1, true) ~= nil
    local sidePhase = isRight and math.pi or 0

    -- Drive both sides from a shared clock but half a cycle apart. This avoids
    -- a mirrored/stiff "march" and gives the legs and opposite arms a real gait.
    local speed = math.max(movement, 0)
    local run = math.Clamp((speed - 70) / 50, 0, 1)
    local moving = math.Clamp((speed - 7) / 55, 0, 1)
    local cadence = math.Clamp(2.7 + speed * 0.038, 2.7, 10.5)
    local cycle = time * cadence + phase + sidePhase
    local legSwing = math.sin(cycle) * moving
    local armSwing = math.sin(cycle + math.pi) * moving
    local kneeLift = math.max(math.sin(cycle + math.pi * 0.5), 0) * moving
    local bodySway = math.sin(time * (1.1 + run * 1.5) + phase) * (1.8 + moving * 2.2)
    local bodyTwist = math.sin(cycle * 0.5) * (2.5 + moving * 3.5)
    local headBob = math.sin(cycle * 2) * (0.7 + moving * 1.5)
    local tremor = math.sin(time * 5.1 + phase) * 1.2
    local tuck = math.Clamp(moving + run * 0.35, 0, 1)

    if name == "valvebiped.bip01_pelvis" then
        a:RotateAroundAxis(a:Forward(), bodySway * amount)
        a:RotateAroundAxis(a:Up(), bodyTwist * 0.55 * amount)
        a:RotateAroundAxis(a:Right(), (run * 5 + tremor * 0.3) * amount)

    elseif name == "valvebiped.bip01_spine" or name == "valvebiped.bip01_spine1"
        or name == "valvebiped.bip01_spine2" or name == "valvebiped.bip01_spine4" then
        local level = name == "valvebiped.bip01_spine" and 0
            or name == "valvebiped.bip01_spine1" and 1
            or name == "valvebiped.bip01_spine2" and 2 or 3
        local runLean = 5 + level * 4 + run * (8 + level * 4)
        local forwardBend = crawling and (34 + level * 3) or runLean
        a:RotateAroundAxis(a:Right(), (forwardBend + math.sin(cycle) * (1.3 + moving * 2.2)) * amount)
        a:RotateAroundAxis(a:Forward(), (bodySway * 0.8 + tremor) * amount)
        a:RotateAroundAxis(a:Up(), (bodyTwist + legSwing * 2.5) * amount)

    elseif name == "valvebiped.bip01_neck1" then
        a:RotateAroundAxis(a:Right(), ((crawling and 20 or (3 - run * 5)) - headBob) * amount)
        a:RotateAroundAxis(a:Forward(), (-bodySway * 0.6) * amount)
        a:RotateAroundAxis(a:Up(), (-bodyTwist * 0.35) * amount)

    elseif name == "valvebiped.bip01_head1" then
        -- Counterbalance the running hunch so the head stays aimed generally ahead.
        a:RotateAroundAxis(a:Right(), ((crawling and -10 or (5 - run * 7)) + headBob) * amount)
        a:RotateAroundAxis(a:Forward(), (8 * math.sin(time * 1.05 + phase) - bodySway * 0.45) * amount)
        a:RotateAroundAxis(a:Up(), (5 * math.sin(time * 0.8 + phase * 1.3) - bodyTwist * 0.25) * amount)

    elseif name == "valvebiped.bip01_l_upperarm" or name == "valvebiped.bip01_r_upperarm" then
        if crawling then
            a:RotateAroundAxis(a:Right(), (isLeft and -48 or 42) * amount)
            a:RotateAroundAxis(a:Forward(), (isLeft and -22 or 18) * amount)
        else
            -- Both shoulders fold in; mirrored roll brings the elbows closer to
            -- the chest. The fore/aft swing is opposite the same-side leg.
            local shoulderSwing = armSwing * (9 + run * 9)
            a:RotateAroundAxis(a:Right(), (-19 + shoulderSwing - run * 5) * amount)
            a:RotateAroundAxis(a:Forward(), (isLeft and -12 or 12) * amount)
            a:RotateAroundAxis(a:Up(), (isLeft and 5 or -5) * amount)
        end

    elseif name == "valvebiped.bip01_l_forearm" or name == "valvebiped.bip01_r_forearm" then
        if crawling then
            a:RotateAroundAxis(a:Right(), (isLeft and -62 or -58) * amount)
        else
            -- Bent elbows keep the forearms tucked instead of hanging straight.
            local elbowFlex = -54 - tuck * 12 + math.max(armSwing, 0) * 7
            a:RotateAroundAxis(a:Right(), elbowFlex * amount)
            a:RotateAroundAxis(a:Forward(), (isLeft and 13 or -13) * amount)
        end

    elseif name == "valvebiped.bip01_l_hand" or name == "valvebiped.bip01_r_hand" then
        a:RotateAroundAxis(a:Right(), (crawling and -12 or -8 - tuck * 9) * amount)
        a:RotateAroundAxis(a:Forward(), (isLeft and 7 or -7) * amount)

    elseif name == "valvebiped.bip01_l_thigh" or name == "valvebiped.bip01_r_thigh" then
        a:RotateAroundAxis(a:Right(), (crawling and -25 or legSwing * (8 + run * 10)) * amount)
        a:RotateAroundAxis(a:Forward(), (isLeft and -1.5 or 1.5) * amount)

    elseif name == "valvebiped.bip01_l_calf" or name == "valvebiped.bip01_r_calf" then
        local kneeBend = kneeLift * (9 + run * 14)
        a:RotateAroundAxis(a:Right(), (crawling and 33 or kneeBend) * amount)

    elseif name == "valvebiped.bip01_l_foot" or name == "valvebiped.bip01_r_foot" then
        a:RotateAroundAxis(a:Right(), (crawling and -8 or -kneeLift * (4 + run * 5)) * amount)
        a:RotateAroundAxis(a:Forward(), (isLeft and 2 or -2) * amount)
    end

    return a
end

local function ControlPuppet(host, rag, now)
    if not IsValid(host) or not IsValid(rag) then return end
    if host:Health() <= 0 then return end
    if host:GetModel() ~= rag:GetModel() then
        Fake.Attach(host, true)
        return
    end

    -- SetupBones is not exposed on every server-side NextBot/entity Lua metatable.
    -- Bone matrices/positions are still readable on supported models without it.
    if isfunction(host.SetupBones) then host:SetupBones() end
    local rootPos, rootAng = host:GetPos(), host:GetAngles()
    local movement = host:GetVelocity():Length2D()
    local phase = host:EntIndex() * 0.73
    local poseAmount = math.Clamp(strength:GetFloat(), 0, 2)
    local maxHealth = math.max(host:GetMaxHealth(), 1)
    local crawling = host.ZevilCrawling == true or host:Health() <= maxHealth * 0.22
    local stage = host:GetNW2Int("ZevilStage", 2)
    if rag:GetNW2Int("ZevilStage", 2) ~= stage then rag:SetNW2Int("ZevilStage", stage) end
    local control = {
        secondstoarrive = math.Clamp(0.075 / math.max(poseAmount, 0.4), 0.035, 0.14),
        maxangular = 420 + 180 * poseAmount,
        maxangulardamp = 110,
        maxspeed = 500 + math.min(movement * 2, 500),
        maxspeeddamp = 115,
        dampfactor = 0.82,
        teleportdistance = 0
    }

    for physIndex = 0, rag:GetPhysicsObjectCount() - 1 do
        local phys = rag:GetPhysicsObjectNum(physIndex)
        if not IsValid(phys) then continue end

        local ragBone = rag:TranslatePhysBoneToBone(physIndex)
        if not ragBone or ragBone < 0 then continue end
        local boneName = rag:GetBoneName(ragBone) or ""
        if boneName == "" then continue end
        local lowerBoneName = string.lower(boneName)

        -- Keep the original case for LookupBone; only normalize names used by
        -- the procedural pose table, since ValveBiped bone lookup is case-sensitive.
        local sourceBone = host:LookupBone(boneName)
        if not sourceBone then continue end
        local worldPos, worldAng
        if isfunction(host.GetBoneMatrix) then
            local matrix = host:GetBoneMatrix(sourceBone)
            if matrix then
                worldPos, worldAng = matrix:GetTranslation(), matrix:GetAngles()
            end
        end

        -- Some server-side animated entities do not provide a usable bone
        -- matrix on every tick. Fall back to the public bone-position accessor.
        if (not worldPos or not worldAng) and isfunction(host.GetBonePosition) then
            local pos, ang = host:GetBonePosition(sourceBone)
            if isvector(pos) and isangle(ang) then
                worldPos, worldAng = pos, ang
            end
        end
        if not isvector(worldPos) or not isangle(worldAng) then continue end

        local localPos, localAng = WorldToLocal(
            worldPos, worldAng, rootPos, rootAng
        )
        local targetAng = ApplyInfectedPose(
            lowerBoneName, localAng, now, phase, movement, poseAmount, crawling
        )

        -- Crawl posture lowers the upper body toward the floor while keeping
        -- pelvis/legs closer to the NextBot's collision origin. Standing, walking,
        -- and running continue to inherit the source activity's animated bones.
        if crawling then
            if lowerBoneName == "valvebiped.bip01_pelvis" then
                localPos.z = localPos.z - 5
            elseif lowerBoneName == "valvebiped.bip01_spine"
                or lowerBoneName == "valvebiped.bip01_spine1"
                or lowerBoneName == "valvebiped.bip01_spine2" then
                localPos.z = localPos.z - 18
            elseif lowerBoneName == "valvebiped.bip01_spine4"
                or lowerBoneName == "valvebiped.bip01_neck1"
                or lowerBoneName == "valvebiped.bip01_head1" then
                localPos.z = localPos.z - 29
            elseif lowerBoneName:find("_upperarm", 1, true) then
                localPos.z = localPos.z - 14
            elseif lowerBoneName:find("_forearm", 1, true)
                or lowerBoneName:find("_hand", 1, true) then
                localPos.z = localPos.z - 19
            end
        end

        local targetPos, targetWorldAng = LocalToWorld(localPos, targetAng, rootPos, rootAng)

        control.pos = targetPos
        control.angle = targetWorldAng
        phys:Wake()
        phys:ComputeShadowControl(control)
    end
end

local function QueueAttach(ent, forceRefresh)
    timer.Simple(0.12, function()
        if not IsValid(ent) or not enabled:GetBool() then return end
        Fake.Attach(ent, forceRefresh == true)
    end)
end

hook.Add("OnEntityCreated", "Zevil_FakeInfected_QueueAttach", function(ent)
    if ent:GetClass() == "npc_zevil_infected" then QueueAttach(ent, false) end
end)

hook.Add("InitPostEntity", "Zevil_FakeInfected_AttachExisting", function()
    for _, ent in ipairs(ents.FindByClass("npc_zevil_infected")) do
        QueueAttach(ent, false)
    end
end)

hook.Add("Org Think", "Zevil_FakeInfected_MirrorZCityWounds", function(owner, org)
    if not IsValid(owner) or owner:GetClass() ~= "npc_zevil_infected" or not istable(org) then return end
    timer.Simple(0, function()
        if not IsValid(owner) or owner.organism ~= org then return end
        local puppet = owner.ZevilFakePuppet
        if IsValid(puppet) and puppet.ZevilPuppetOwner == owner then
            MirrorZCityWounds(owner, puppet, true)
        end
    end)
end)

hook.Add("Zevil_HumanNPCConverted", "Zevil_FakeInfected_RefreshConvertedModel", function(_, infected)
    -- The conversion routine sets model/skin/bodygroups synchronously after Spawn;
    -- the delayed attach therefore sees the final model and stays idempotent.
    QueueAttach(infected, false)
end)


local function GetPuppetMouthPosition(host, rag)
    local headBone = rag:LookupBone("ValveBiped.Bip01_Head1")
    if headBone then
        local physBone = rag:TranslateBoneToPhysBone(headBone)
        if physBone and physBone >= 0 then
            local phys = rag:GetPhysicsObjectNum(physBone)
            if IsValid(phys) then
                local pos, ang = phys:GetPos(), phys:GetAngles()
                return pos + ang:Forward() * 4 - ang:Up() * 3, ang
            end
        end
    end

    local hostHead = host:LookupBone("ValveBiped.Bip01_Head1")
    if hostHead and isfunction(host.GetBonePosition) then
        local pos = host:GetBonePosition(hostHead)
        if isvector(pos) and pos ~= vector_origin then
            local matrix = host:GetBoneMatrix(hostHead)
            return pos, matrix and matrix:GetAngles() or host:GetAngles()
        end
    end
    return host:WorldSpaceCenter() + Vector(0, 0, 20), host:GetAngles()
end

local function EmitZCityFalseMouthBleed(host, rag)
    if not IsValid(host) or not IsValid(rag) then return end
    local mouth, headAng = GetPuppetMouthPosition(host, rag)

    -- Use Z-City's existing blood-particle network message when the organism
    -- particle module registered it. This is presentation only: no fake
    -- organism table, wound, or player damage is created for the NextBot.
    if util.NetworkStringToID("hg_bloodimpact") > 0 then
        net.Start("hg_bloodimpact")
        net.WriteVector(mouth)
        -- Z-City's client receiver multiplies this vector by 500 and expects
        -- a multiplier of at least 1. A sub-one value can produce an invalid
        -- random range and silently prevent the effect from spawning.
        local flow = headAng and (-headAng:Forward() * 0.02 + Vector(0, 0, 0.035))
            or Vector(0, 0, 0.035)
        net.WriteVector(flow)
        net.WriteFloat(1)
        net.WriteInt(host:GetNW2Int("ZevilStage", 2) >= 4 and 2 or 1, 8)
        net.Broadcast()
        return
    end

    -- Standalone fallback for servers without Z-City's custom blood particles.
    local effect = EffectData()
    effect:SetOrigin(mouth)
    effect:SetMagnitude(0.25)
    effect:SetScale(0.25)
    util.Effect("BloodImpact", effect, true, true)
end

hook.Add("Think", "Zevil_FakeInfected_Control", function()
    if not enabled:GetBool() then
        for host in pairs(active) do
            if IsValid(host) then Fake.Detach(host, false) else active[host] = nil end
        end
        return
    end

    local interval = 1 / math.Clamp(rate:GetFloat(), 5, 35)
    local now = CurTime()
    for host, rag in pairs(active) do
        if not IsValid(host) then
            active[host] = nil
            continue
        end
        if not IsValid(rag) then
            Fake.Detach(host, false)
            continue
        end

        if host.BZCNNPCDowned and IsValid(host.BZCNNPCRagdoll) then
            SuspendPuppetForZCityDowned(host, rag)
            continue
        end

        MirrorZCityWounds(host, rag, false)
        if host:GetNW2Int("ZevilStage", 2) >= 2
            and now >= (host.ZevilNextMouthBleed or 0) then
            EmitZCityFalseMouthBleed(host, rag)
            host.ZevilNextMouthBleed = now + math.Rand(0.55, 0.9)
        end

        if now < (host.ZevilFakeNextControl or 0) then continue end
        host.ZevilFakeNextControl = now + interval
        ControlPuppet(host, rag, now)
    end
end)

local nextRecoveryScan = 0
hook.Add("Think", "Zevil_FakeInfected_ResumeAfterZCityRecovery", function()
    local now = CurTime()
    if now < nextRecoveryScan then return end
    nextRecoveryScan = now + 0.25
    for _, host in ipairs(ents.FindByClass("npc_zevil_infected")) do
        if not IsValid(host) or not host.ZevilFakeUsingZCityDowned then continue end
        if host:Health() <= 0 then
            host.ZevilFakeUsingZCityDowned = nil
            continue
        end
        if host.BZCNNPCDowned or IsValid(host.BZCNNPCRagdoll) then continue end

        host.ZevilFakeUsingZCityDowned = nil
        host:SetNoDraw(false)
        host:DrawShadow(true)
        QueueAttach(host, true)
    end
end)

hook.Add("EntityTakeDamage", "Zevil_FakeInfected_DamageBridge", function(target, damage)
    local owner = target.ZevilPuppetOwner
    if not IsValid(owner) or owner.ZevilFakePuppet ~= target
        or owner.ZevilFakeForwardingDamage then return end

    -- The puppet is the visible, physically traceable body. Forward its damage
    -- to the AI owner so bullets and melee still affect the infected.
    local forwarded = DamageInfo()
    forwarded:SetDamage(damage:GetDamage())
    forwarded:SetDamageType(damage:GetDamageType())
    forwarded:SetAttacker(damage:GetAttacker())
    forwarded:SetInflictor(damage:GetInflictor())
    forwarded:SetDamagePosition(damage:GetDamagePosition())
    forwarded:SetDamageForce(damage:GetDamageForce())

    owner.ZevilFakeForwardingDamage = true
    owner:TakeDamageInfo(forwarded)
    owner.ZevilFakeForwardingDamage = nil
    damage:SetDamage(0)
end)

hook.Add("EntityRemoved", "Zevil_FakeInfected_Cleanup", function(ent)
    if ent.ZevilFakePuppet then
        local rag = ent.ZevilFakePuppet
        active[ent] = nil
        ent.ZevilFakePuppet = nil
        if IsValid(rag) and rag.ZevilPuppetOwner == ent then
            rag.ZevilPuppetOwner = nil
            SafeRemoveEntity(rag)
        end
        return
    end

    local owner = ent.ZevilPuppetOwner
    if IsValid(owner) and owner.ZevilFakePuppet == ent then
        Fake.Detach(owner, false)
    end
end)

print("[Zevil] Procedural infected ragdoll controller loaded.");
