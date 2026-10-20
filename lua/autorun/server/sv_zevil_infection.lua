-- Zevil Z-City: independent infection lifecycle.
-- Intentionally does not replace player models or mutate Z-City organism tables.
if not SERVER then return end

AddCSLuaFile("autorun/client/cl_zevil_mutation.lua")
util.AddNetworkString("Zevil_VirusState")

Zevil = Zevil or {}
Zevil.Config = Zevil.Config or {}
local Z = Zevil
local cv = {}
local function convar(name, default, help, flags)
    cv[name] = CreateConVar(name, tostring(default), flags or FCVAR_ARCHIVE, help)
    return cv[name]
end

convar("zevil_enabled", 1, "Enable Zevil infection systems")
convar("zevil_transmission", 1, "Allow infection transmission")
convar("zevil_incubation", 90, "Seconds before exposed hosts become symptomatic")
convar("zevil_progression", 120, "Seconds between mutation stages")
convar("zevil_bite_infect_chance", 0.35, "Probability that an infected bite infects a victim")
-- Replicate visual settings so client draw hooks can actually read them.
convar("zevil_player_visuals", 1, "Enable clientside infected player mutation visuals", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED))
convar("zevil_mutation_strength", 1, "Visual mutation intensity", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED))
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

-- A human NPC becomes a roaming infected entity at full infection. Players keep
-- their existing entity/model so their controls and Z-City player systems survive.
local function isHumanNPC(ent)
    if not IsValid(ent) or ent:IsPlayer() then return false end
    local model = string.lower(ent:GetModel() or "")
    local class = string.lower(ent:GetClass() or "")
    return string.StartWith(model, "models/humans/") or string.StartWith(model, "models/player/")
        or class == "npc_citizen" or class == "npc_metropolice"
        or class == "npc_barney" or class == "npc_alyx"
        or class == "npc_kleiner" or class == "npc_mossman"
        or class == "npc_zevil_rookiecop" or class == "npc_zevil_civilian"
end

hook.Add("Zevil_Infected", "Zevil_ConvertHumanNPC", function(host, source)
    if not enabled() or not isHumanNPC(host) or host:GetClass() == "npc_zevil_infected" then return end
    local old = host
    local pos = old:GetPos()
    local velocity = old:GetVelocity()

    -- Source NPCs can have stale body yaw while turning or strafing. Prefer the
    -- current enemy or infector direction, then movement direction, so the
    -- replacement player-model NextBot doesn't inherit a sideways body heading.
    local facingTarget
    if isfunction(old.GetEnemy) then
        local enemy = old:GetEnemy()
        if IsValid(enemy) and enemy ~= old then facingTarget = enemy end
    end
    if not IsValid(facingTarget) and IsValid(source) and source ~= old then
        facingTarget = source
    end

    local yaw = old:GetAngles().y
    if IsValid(facingTarget) then
        local direction = facingTarget:WorldSpaceCenter() - old:WorldSpaceCenter()
        direction.z = 0
        if direction:LengthSqr() > 16 then yaw = direction:Angle().y end
    elseif velocity:Length2DSqr() > 900 then
        yaw = velocity:Angle().y
    end
    local ang = Angle(0, yaw, 0)
    local hp, maxhp = math.max(old:Health(), 1), math.max(old:GetMaxHealth(), 1)
    local formerName = isfunction(old.Nick) and old:Nick() or (isfunction(old.GetName) and old:GetName() or "")
    local infected = table.Copy(old.ZevilVirus or {})
    local zombie = ents.Create("npc_zevil_infected")
    if not IsValid(zombie) then
        ErrorNoHalt("[Zevil] Failed to convert infected human NPC; keeping original entity.\n")
        return
    end
    zombie.ZevilFormerName = formerName ~= "" and formerName or nil
    zombie:SetPos(pos)
    zombie:SetAngles(ang)
    zombie:Spawn()
    zombie:Activate()
    if not IsValid(zombie) then return end
    -- Restore the resolved yaw after initialization; BodyUpdate then maintains
    -- movement pose parameters on the new player-model NextBot.
    zombie:SetAngles(ang)
    -- The infected entity selects a random civilian player model during
    -- Initialize; do not overwrite it with Combine/zombie/special NPC models.
    zombie:SetMaxHealth(maxhp)
    zombie:SetHealth(math.min(hp, maxhp))
    zombie:SetVelocity(velocity)
    zombie.ZevilVirus = infected
    zombie.ZevilVirus.Infected = true
    zombie.ZevilVirus.Stage = math.max(zombie.ZevilVirus.Stage or 1, 2)
    zombie.ZevilVirus.Source = IsValid(source) and source or zombie.ZevilVirus.Source
    zombie:SetNW2Bool("ZevilInfected", true)
    zombie:SetNW2Int("ZevilStage", zombie.ZevilVirus.Stage)
    hook.Run("Zevil_HumanNPCConverted", old, zombie)
    old:Remove()
end)

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
    if attacker.ZevilInfectedAttacker then Z.Expose(target, 25, attacker) end
end)

hook.Add("Zevil_Infected", "Zevil_PlayerConversionFeedback", function(ent)
    if not IsValid(ent) or not ent:IsPlayer() then return end
    ent:ChatPrint("[Zevil] Infection established. Visible symptoms will worsen over time.")
    ent:ChatPrint("[Zevil] At stage 3, use the console command zevil_bite to infect nearby targets.")
end)

hook.Add("Zevil_StageChanged", "Zevil_PlayerStageFeedback", function(ent, stage)
    if not IsValid(ent) or not ent:IsPlayer() then return end
    local messages = {
        [2] = "[Zevil] Stage 2: visible decay and infected vocalizations have begun.",
        [3] = "[Zevil] Stage 3: the infection is damaging you. Bite nearby targets with zevil_bite.",
        [4] = "[Zevil] Stage 4: motor control is degrading; movement is impaired.",
        [5] = "[Zevil] Stage 5: terminal infection. Your movement is heavily impaired."
    }
    if messages[stage] then ent:ChatPrint(messages[stage]) end
end)

-- Apply stage penalties to the movement command rather than persistent player
-- speed settings, so a cure restores ordinary movement without cleanup races.
hook.Add("SetupMove", "Zevil_InfectedPlayerMovement", function(ply, mv)
    if not IsValid(ply) or not ply:Alive() then return end
    local v = ply.ZevilVirus
    if not (istable(v) and v.Infected) then return end
    local stage = math.Clamp(tonumber(v.Stage) or 1, 1, 5)
    local multiplier = stage >= 5 and 0.74 or stage >= 4 and 0.86 or stage >= 3 and 0.94 or 1
    if multiplier < 1 then
        mv:SetMaxSpeed(mv:GetMaxSpeed() * multiplier)
        mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * multiplier)
    end
end)

hook.Add("PlayerInitialSpawn", "ZevilSyncOnJoin", function(ply)
    timer.Simple(1, function() if IsValid(ply) then replicate(ply) end end)
end)

hook.Add("PlayerDeath", "ZevilKeepVirusAcrossDeath", function(ply)
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
        if ent:IsPlayer() and v.Stage >= 2 and now >= (v.NextGroan or 0) then
            local groans = {
                "npc/zombie/moan1.wav",
                "npc/zombie/moan2.wav",
                "npc/zombie/moan3.wav"
            }
            ent:EmitSound(groans[math.random(#groans)], 58, math.random(92, 106), 0.45)
            v.NextGroan = now + math.Rand(22, 36)
        end
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

-- Infected players remain player-controlled. At advanced stages they can
-- deliberately bite nearby victims instead of being forcibly replaced by AI.
local playerBiteCooldown = setmetatable({}, {__mode = "k"})
concommand.Add("zevil_bite", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
    local v = ply.ZevilVirus
    if not (istable(v) and v.Infected and (v.Stage or 1) >= 3) then
        ply:ChatPrint("[Zevil] You need to reach infection stage 3 to bite.")
        return
    end
    if CurTime() < (playerBiteCooldown[ply] or 0) then return end
    playerBiteCooldown[ply] = CurTime() + 1.4
    local startPos = ply:EyePos()
    local aim = ply:GetAimVector()
    local best, bestDistance
    for _, target in ipairs(ents.FindInSphere(ply:GetPos(), 88)) do
        if target == ply or not validHost(target) or target:Health() <= 0 then continue end
        if target:IsPlayer() and (not target:Alive() or target:Team() == TEAM_SPECTATOR) then continue end
        if target.ZevilVirus and target.ZevilVirus.Infected then continue end
        local delta = target:WorldSpaceCenter() - startPos
        local distance = delta:Length()
        if distance > 88 or aim:Dot(delta:GetNormalized()) < 0.15 then continue end
        if not bestDistance or distance < bestDistance then best, bestDistance = target, distance end
    end
    ply:EmitSound("npc/zombie/claw_strike" .. math.random(1, 3) .. ".wav", 75, math.random(85, 105))
    if not IsValid(best) then return end
    local damage = DamageInfo()
    damage:SetDamage(9 + (v.Stage or 1))
    damage:SetDamageType(DMG_SLASH)
    damage:SetAttacker(ply)
    damage:SetInflictor(ply)
    damage:SetDamagePosition(best:WorldSpaceCenter())
    ply.ZevilBiteDamage = true
    best:TakeDamageInfo(damage)
    ply.ZevilBiteDamage = false
    Z.Expose(best, 20, ply)
    util.Decal("Blood", best:WorldSpaceCenter() + Vector(0, 0, 12), best:WorldSpaceCenter() - Vector(0, 0, 36), {ply, best})
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

concommand.Add("zevil_give_syringe", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then
        print("[Zevil] Run zevil_give_syringe from an in-game admin console.")
        return
    end
    if not ply:IsAdmin() then
        ply:ChatPrint("[Zevil] Admin permission required.")
        return
    end
    if not enabled() then
        ply:ChatPrint("[Zevil] Infection is disabled by zevil_enabled.")
        return
    end
    if not weapons.GetStored("weapon_zevil_virus_syringe") then
        ply:ChatPrint("[Zevil] Syringe SWEP is not registered. Check Lua errors and restart/reload the addon.")
        return
    end
    ply:Give("weapon_zevil_virus_syringe")
    ply:SelectWeapon("weapon_zevil_virus_syringe")
    ply:ChatPrint("[Zevil] Virus syringe issued. LMB injects yourself; RMB injects a nearby target.")
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
