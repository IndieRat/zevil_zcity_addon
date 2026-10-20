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
local EMPTY_ANGLE = Angle(0, 0, 0)

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
    rag:SetMaterial(source:GetMaterial() or "")

    if source.GetNumSubMaterials and source.GetSubMaterial and rag.SetSubMaterial then
        for index = 0, source:GetNumSubMaterials() - 1 do
            rag:SetSubMaterial(index, source:GetSubMaterial(index) or "")
        end
    end
end

function Fake.Detach(host, keepCorpse)
    if not IsValid(host) then return nil end

    local rag = host.ZevilFakePuppet or active[host]
    active[host] = nil
    host.ZevilFakePuppet = nil
    host:SetNW2Entity("ZevilFakePuppet", NULL)

    if IsValid(rag) then
        rag.ZevilPuppetOwner = nil
        rag:SetNW2Entity("ZevilPuppetOwner", NULL)
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
    rag:SetNW2Entity("ZevilPuppetOwner", host)
    rag.ZevilPuppetOwner = host
    rag.ZevilPuppetConstraint = constraint.NoCollide(host, rag, 0, 0)

    host.ZevilFakePuppet = rag
    host:SetNW2Entity("ZevilFakePuppet", rag)
    host:SetNoDraw(true)
    host:DrawShadow(false)
    active[host] = rag

    -- Do not copy the animated NPC's origin into the ragdoll every frame. The
    -- individual physics bodies are eased toward bone targets below, so hits and
    -- ground contact can make the body lag and settle instead of snapping.
    return true
end

local function ApplyInfectedPose(name, angle, time, phase, movement, amount)
    local a = Angle(angle.p, angle.y, angle.r)
    local gait = math.sin(time * (movement > 15 and 7.5 or 1.8) + phase)
    local sway = math.sin(time * 1.35 + phase * 0.7)
    local idleTremor = math.sin(time * 5.1 + phase) * 1.5

    if name == "valvebiped.bip01_pelvis" then
        a:RotateAroundAxis(a:Forward(), sway * 2.5 * amount)
    elseif name == "valvebiped.bip01_spine" or name == "valvebiped.bip01_spine1"
        or name == "valvebiped.bip01_spine2" then
        a:RotateAroundAxis(a:Right(), (9 + gait * 2.5) * amount)
        a:RotateAroundAxis(a:Forward(), (7 * sway + idleTremor) * amount)
    elseif name == "valvebiped.bip01_spine4" or name == "valvebiped.bip01_neck1" then
        a:RotateAroundAxis(a:Right(), (4 - gait * 2) * amount)
        a:RotateAroundAxis(a:Forward(), (-5 * sway) * amount)
    elseif name == "valvebiped.bip01_head1" then
        a:RotateAroundAxis(a:Right(), (7 + 4 * sway) * amount)
        a:RotateAroundAxis(a:Forward(), (9 * math.sin(time * 1.05 + phase)) * amount)
        a:RotateAroundAxis(a:Up(), (6 * math.sin(time * 0.8 + phase * 1.3)) * amount)
    elseif name == "valvebiped.bip01_l_upperarm" then
        a:RotateAroundAxis(a:Right(), -13 * amount)
        a:RotateAroundAxis(a:Forward(), -11 * amount)
    elseif name == "valvebiped.bip01_l_forearm" then
        a:RotateAroundAxis(a:Right(), -27 * amount)
    elseif name == "valvebiped.bip01_r_upperarm" then
        a:RotateAroundAxis(a:Right(), 17 * amount)
        a:RotateAroundAxis(a:Forward(), 12 * amount)
    elseif name == "valvebiped.bip01_r_forearm" then
        a:RotateAroundAxis(a:Right(), -38 * amount)
    elseif name == "valvebiped.bip01_l_thigh" then
        a:RotateAroundAxis(a:Right(), gait * 5 * amount)
    elseif name == "valvebiped.bip01_r_thigh" then
        a:RotateAroundAxis(a:Right(), -gait * 3 * amount)
    elseif name == "valvebiped.bip01_l_calf" then
        a:RotateAroundAxis(a:Right(), math.max(gait, 0) * 6 * amount)
    elseif name == "valvebiped.bip01_r_calf" then
        a:RotateAroundAxis(a:Right(), math.max(-gait, 0) * 8 * amount)
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

    host:SetupBones()
    local rootPos, rootAng = host:GetPos(), host:GetAngles()
    local movement = host:GetVelocity():Length2D()
    local phase = host:EntIndex() * 0.73
    local poseAmount = math.Clamp(strength:GetFloat(), 0, 2)
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
        local boneName = string.lower(rag:GetBoneName(ragBone) or "")
        if boneName == "" then continue end

        local sourceBone = host:LookupBone(boneName)
        if not sourceBone then continue end
        local matrix = host:GetBoneMatrix(sourceBone)
        if not matrix then continue end

        local localPos, localAng = WorldToLocal(
            matrix:GetTranslation(), matrix:GetAngles(), rootPos, rootAng
        )
        local targetAng = ApplyInfectedPose(
            boneName, localAng, now, phase, movement, poseAmount
        )
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

hook.Add("Zevil_HumanNPCConverted", "Zevil_FakeInfected_RefreshConvertedModel", function(_, infected)
    QueueAttach(infected, true)
end)

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
        if now < (host.ZevilFakeNextControl or 0) then continue end
        host.ZevilFakeNextControl = now + interval
        ControlPuppet(host, rag, now)
    end
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
