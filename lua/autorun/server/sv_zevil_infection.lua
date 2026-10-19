-- Zevil Z-City: independent infection lifecycle.
-- Intentionally does not replace player models or mutate Z-City organism tables.
if not SERVER then return end

AddCSLuaFile("autorun/client/cl_zevil_mutation.lua")
util.AddNetworkString("Zevil_VirusState")

Zevil = Zevil or {}
Zevil.Config = Zevil.Config or {}
local Z = Zevil
local cv = {}
local function convar(name, default, help)
    cv[name] = CreateConVar(name, tostring(default), FCVAR_ARCHIVE, help)
    return cv[name]
end

convar("zevil_enabled", 1, "Enable Zevil infection systems")
convar("zevil_transmission", 1, "Allow infection transmission")
convar("zevil_incubation", 90, "Seconds before exposed hosts become symptomatic")
convar("zevil_progression", 120, "Seconds between mutation stages")
convar("zevil_bite_infect_chance", 0.35, "Probability that an infected bite infects a victim")
convar("zevil_player_visuals", 1, "Enable clientside infected player mutation visuals")
convar("zevil_mutation_strength", 1, "Visual mutation intensity")
convar("zevil_max_infected", 24, "Maximum Zevil infected NPCs")
convar("zevil_exposure_decay", 0.25, "Exposure removed per second when not exposed")

Z.Config.CVars = cv
local function enabled() return cv.zevil_enabled:GetBool() end
local function validHost(ent)
    return IsValid(ent) and (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot())
end

function Z.GetVirus(ent)
    if not IsValid(ent) then return nil end
    return ent.ZevilVirus
end

local function replicate(ent)
    if not IsValid(ent) then return end
    local v = ent.ZevilVirus
    if ent:IsPlayer() then
        net.Start("Zevil_VirusState")
        net.WriteBool(istable(v) and v.Infected == true)
        net.WriteUInt(istable(v) and math.Clamp(v.Stage or 0, 0, 5) or 0, 3)
        net.WriteFloat(istable(v) and math.Clamp(v.Exposure or 0, 0, 100) or 0)
        net.Send(ent)
        ent:SetNW2Bool("ZevilInfected", istable(v) and v.Infected == true)
        ent:SetNW2Int("ZevilStage", istable(v) and (v.Stage or 0) or 0)
    else
        ent:SetNW2Bool("ZevilInfected", istable(v) and v.Infected == true)
        ent:SetNW2Int("ZevilStage", istable(v) and (v.Stage or 0) or 0)
    end
end

function Z.Expose(ent, amount, source)
    if not enabled() or not cv.zevil_transmission:GetBool() or not validHost(ent) then return false end
    if ent:IsPlayer() and not ent:Alive() then return false end
    local v = ent.ZevilVirus
    if istable(v) and v.Infected then return false end
    if not istable(v) then
        v = {Infected = false, Stage = 0, Exposure = 0, LastExposure = CurTime(), Source = nil}
        ent.ZevilVirus = v
    end
    v.Exposure = math.Clamp((v.Exposure or 0) + math.max(tonumber(amount) or 0, 0), 0, 100)
    v.LastExposure = CurTime()
    v.Source = IsValid(source) and source or v.Source
    replicate(ent)
    if v.Exposure >= 100 then Z.Infect(ent, source) end
    return true
end

function Z.Infect(ent, source)
    if not enabled() or not validHost(ent) then return false end
    if ent:IsPlayer() and not ent:Alive() then return false end
    local old = ent.ZevilVirus
    if istable(old) and old.Infected then return false end
    ent.ZevilVirus = {
        Infected = true, Stage = 1, Exposure = 100,
        InfectedAt = CurTime(), NextStage = CurTime() + cv.zevil_incubation:GetFloat(),
        NextDamage = CurTime() + 8, Source = IsValid(source) and source or (old and old.Source),
        LastMutation = 0, Feeding = false
    }
    replicate(ent)
    hook.Run("Zevil_Infected", ent, ent.ZevilVirus.Source)
    return true
end

function Z.Cure(ent)
    if not IsValid(ent) or not istable(ent.ZevilVirus) then return false end
    ent.ZevilVirus = nil
    ent:SetNW2Bool("ZevilInfected", false)
    ent:SetNW2Int("ZevilStage", 0)
    if ent:IsPlayer() then
        net.Start("Zevil_VirusState")
        net.WriteBool(false) net.WriteUInt(0, 3) net.WriteFloat(0)
        net.Send(ent)
    end
    hook.Run("Zevil_Cured", ent)
    return true
end

function Z.SetStage(ent, stage)
    if not IsValid(ent) then return false end
    stage = math.Clamp(math.floor(tonumber(stage) or 1), 1, 5)
    if not (istable(ent.ZevilVirus) and ent.ZevilVirus.Infected) then Z.Infect(ent) end
    local v = ent.ZevilVirus
    if not v then return false end
    v.Stage = stage
    v.NextStage = CurTime() + cv.zevil_progression:GetFloat()
    replicate(ent)
    hook.Run("Zevil_StageChanged", ent, stage)
    return true
end

local function getTargetsInSphere(pos, radius)
    local found = ents.FindInSphere(pos, radius)
    for _, ent in ipairs(found) do
        if IsValid(ent) and ent:IsPlayer() and ent:Alive() and not ent.ZevilVirus then
            -- Exposure is accumulated; no instant conversion from proximity.
            Z.Expose(ent, 2, nil)
        end
    end
end

hook.Add("EntityTakeDamage", "Zevil_BiteTransmission", function(target, dmg)
    if not enabled() or not validHost(target) then return end
    local attacker = dmg:GetAttacker()
    if not IsValid(attacker) then return end
    local av = attacker.ZevilVirus
    if not (istable(av) and av.Infected) then return end
    local inflictor = dmg:GetInflictor()
    local isBite = attacker.ZevilBiteDamage == true or (IsValid(inflictor) and inflictor.ZevilBiteDamage == true)
    if not isBite then return end
    if math.Rand(0, 1) <= cv.zevil_bite_infect_chance:GetFloat() then
        Z.Expose(target, 100, attacker)
    else
        Z.Expose(target, 20, attacker)
    end
end)

hook.Add("EntityTakeDamage", "ZevilPlayerExposureFromInfected", function(target, dmg)
    if not enabled() or not validHost(target) then return end
    local attacker = dmg:GetAttacker()
    if not IsValid(attacker) or attacker == target then return end
    if attacker.ZevilVirus and attacker.ZevilVirus.Infected then return end
    -- Generic infected contact damage can expose hosts when explicitly marked by Zevil AI.
    if attacker.ZevilInfectedAttacker then Z.Expose(target, 25, attacker) end
end)

hook.Add("PlayerInitialSpawn", "ZevilSyncOnJoin", function(ply)
    timer.Simple(1, function() if IsValid(ply) then replicate(ply) end end)
end)

hook.Add("PlayerDeath", "ZevilKeepVirusAcrossDeath", function(ply)
    -- Death is not a cure. Keep the virus state for the next spawn.
    if istable(ply.ZevilVirus) then ply.ZevilVirus.DeadAt = CurTime() end
end)

hook.Add("PlayerSpawn", "ZevilRestoreAfterSpawn", function(ply)
    timer.Simple(0.5, function() if IsValid(ply) then replicate(ply) end end)
end)

timer.Create("ZevilVirusThink", 1, 0, function()
    if not enabled() then return end
    local now = CurTime()
    for _, ent in ipairs(ents.GetAll()) do
        if not validHost(ent) then continue end
        local v = ent.ZevilVirus
        if not istable(v) then continue end
        if not v.Infected then
            local decay = cv.zevil_exposure_decay:GetFloat()
            v.Exposure = math.max((v.Exposure or 0) - decay, 0)
            if v.Exposure <= 0 then ent.ZevilVirus = nil end
            continue
        end
        if ent:IsPlayer() and not ent:Alive() then continue end
        if now >= (v.NextStage or math.huge) and (v.Stage or 1) < 5 then
            v.Stage = v.Stage + 1
            v.NextStage = now + cv.zevil_progression:GetFloat()
            replicate(ent)
            hook.Run("Zevil_StageChanged", ent, v.Stage)
        end
        -- Early stages are mainly symptomatic. Damage is deliberately mild and
        -- independent from organism internals; no assumptions about org schema.
        if ent:IsPlayer() and v.Stage >= 3 and now >= (v.NextDamage or math.huge) then
            local damage = DamageInfo()
            damage:SetDamage(v.Stage >= 5 and 2 or 1)
            damage:SetDamageType(DMG_GENERIC)
            damage:SetAttacker(IsValid(v.Source) and v.Source or game.GetWorld())
            damage:SetInflictor(IsValid(v.Source) and v.Source or game.GetWorld())
            ent:TakeDamageInfo(damage)
            v.NextDamage = now + (v.Stage >= 5 and 8 or 15)
        end
        if ent:IsPlayer() and now - (v.LastMutation or 0) > 4 then
            v.LastMutation = now
            replicate(ent)
        end
    end
end)

local function findPlayer(needle)
    needle = string.Trim(string.lower(tostring(needle or "")))
    if needle == "" then return nil end
    for _, ply in ipairs(player.GetAll()) do
        if tostring(ply:UserID()) == needle or string.find(string.lower(ply:Nick()), needle, 1, true) then return ply end
    end
end

concommand.Add("zevil_infect", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local target = findPlayer(table.concat(args, " "))
    if not IsValid(target) then if IsValid(ply) then ply:ChatPrint("[Zevil] Player not found.") end return end
    Z.Infect(target, ply)
    if IsValid(ply) then ply:ChatPrint("[Zevil] Infected " .. target:Nick()) end
end)

concommand.Add("zevil_cure", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local target = findPlayer(table.concat(args, " "))
    if not IsValid(target) then if IsValid(ply) then ply:ChatPrint("[Zevil] Player not found.") end return end
    Z.Cure(target)
    if IsValid(ply) then ply:ChatPrint("[Zevil] Cured " .. target:Nick()) end
end)

concommand.Add("zevil_status", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local infected, exposed, npcs = 0, 0, 0
    for _, ent in ipairs(ents.GetAll()) do
        local v = ent.ZevilVirus
        if istable(v) and v.Infected then
            infected = infected + 1
            if not ent:IsPlayer() then npcs = npcs + 1 end
        elseif istable(v) and (v.Exposure or 0) > 0 then exposed = exposed + 1 end
    end
    local msg = string.format("[Zevil] infected=%d (NPCs=%d), exposed=%d", infected, npcs, exposed)
    if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end)

concommand.Add("zevil_spawn_infected", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local count = 0
    for _, ent in ipairs(ents.FindByClass("npc_zevil_infected")) do
        if IsValid(ent) then count = count + 1 end
    end
    if count >= cv.zevil_max_infected:GetInt() then
        if IsValid(ply) then ply:ChatPrint("[Zevil] Infected NPC limit reached.") end
        return
    end
    local pos, ang
    if IsValid(ply) then
        local tr = ply:GetEyeTrace()
        pos = tr.HitPos + tr.HitNormal * 8
        ang = Angle(0, ply:EyeAngles().y + 180, 0)
    else
        pos = Vector(0, 0, 32)
        ang = angle_zero
    end
    local ent = ents.Create("npc_zevil_infected")
    if not IsValid(ent) then
        if IsValid(ply) then ply:ChatPrint("[Zevil] Could not create npc_zevil_infected.") end
        return
    end
    ent:SetPos(pos)
    ent:SetAngles(ang)
    ent:Spawn()
    ent:Activate()
    if IsValid(ply) then ply:ChatPrint("[Zevil] Spawned infected NPC.") end
end)

print("[Zevil] Virus lifecycle loaded (independent organism-safe state).")
