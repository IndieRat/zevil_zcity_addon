-- Server-authoritative feeding, curse transmission, blood pools and vampire physiology.
if not SERVER then return end

ZevilVampire = ZevilVampire or {}
local ZV = ZevilVampire
local CLASS_NAME = "vampire"
local pools = {}
local MAX_POOLS = 120
local POOL_LIFETIME = 300
local USE_DISTANCE = 110
local POOL_USE_RADIUS = 68
local DRINK_INTERVAL = 0.85
local HEAD_BONE = "ValveBiped.Bip01_Head1"

local function MakeConVarSafe(name, default, help)
    if ConVarExists(name) then return GetConVar(name) end
    return CreateConVar(name, tostring(default), FCVAR_ARCHIVE, help)
end

local cvEnabled = MakeConVarSafe("zevil_vampire_enabled", 1, "Enable the native Z-City vampire class mechanics")
local cvCurseChance = MakeConVarSafe("zevil_vampire_curse_chance", 2, "Percent chance per surviving vampire bite to curse a living player")
local cvBiteDamage = MakeConVarSafe("zevil_vampire_bite_damage", 4, "Damage dealt by each vampire bite")
local cvBloodDrain = MakeConVarSafe("zevil_vampire_blood_drain", 105, "Blood units taken per feed pulse")
local cvFireMultiplier = MakeConVarSafe("zevil_vampire_fire_multiplier", 5, "Damage multiplier for fire damage to vampires")
local cvRegenRate = MakeConVarSafe("zevil_vampire_regen", 5, "Vampire health regeneration per second")
local cvBloodCost = MakeConVarSafe("zevil_vampire_regen_blood_cost", 12, "Blood units consumed per second while regenerating")

local function IsVampire(ply)
    return IsValid(ply) and ply:IsPlayer() and ply:Alive()
        and ply.PlayerClassName == CLASS_NAME and cvEnabled:GetBool()
end

local function GetOrganism(ent)
    if not IsValid(ent) then return nil end
    local org = ent.organism
    if not istable(org) and hg and hg.organism and istable(hg.organism.list) then
        org = hg.organism.list[ent]
    end
    if not istable(org) or not isnumber(org.blood) then return nil end
    return org
end

local function GetHeadBone(ent)
    if not IsValid(ent) or not isfunction(ent.LookupBone) then return nil end
    local bone = ent:LookupBone(HEAD_BONE)
    return isnumber(bone) and bone >= 0 and bone or nil
end

local function SetHeadDown(ent, enabled)
    local bone = GetHeadBone(ent)
    if not bone then return end

    if enabled then
        if not ent.ZevilVampireHeadPoseSaved then
            local old = Angle(0, 0, 0)
            if isfunction(ent.GetManipulateBoneAngles) then
                local ok, result = pcall(ent.GetManipulateBoneAngles, ent, bone)
                if ok and isangle(result) then old = result end
            end
            ent.ZevilVampireHeadPoseSaved = {bone = bone, angle = old}
        end
        ent:ManipulateBoneAngles(bone, Angle(28, 0, 0))
        return
    end

    local saved = ent.ZevilVampireHeadPoseSaved
    if saved then
        ent:ManipulateBoneAngles(saved.bone or bone, saved.angle or Angle(0, 0, 0))
        ent.ZevilVampireHeadPoseSaved = nil
    end
end

local function IsOpenWound(org)
    if not istable(org) then return false end
    if isnumber(org.bleed) and org.bleed > 0.01 then return true end
    if not istable(org.wounds) then return false end
    for _, wound in pairs(org.wounds) do
        if istable(wound) and isnumber(wound[1]) and wound[1] > 0.01 then
            return true
        end
    end
    return false
end

local function FindSurface(pos, filter)
    if not isvector(pos) then return nil end
    local tr = util.TraceLine({
        start = pos + Vector(0, 0, 8),
        endpos = pos - Vector(0, 0, 128),
        filter = filter,
        mask = MASK_SOLID
    })
    if not tr.Hit or tr.HitSky then return nil end
    return tr.HitPos, tr.HitNormal, tr.Entity
end

local function AddBloodPool(pos, amount, filter)
    local surfacePos, normal, surfaceEnt = FindSurface(pos, filter)
    if not surfacePos then return nil end

    local now = CurTime()
    for _, pool in ipairs(pools) do
        if pool.amount > 0 and pool.pos:DistToSqr(surfacePos) <= 34 * 34 then
            pool.amount = math.min(1800, pool.amount + math.max(tonumber(amount) or 0, 0))
            pool.touched = now
            pool.expires = now + POOL_LIFETIME
            if normal then
                util.Decal("Blood", surfacePos + normal * 2, surfacePos - normal * 2, surfaceEnt)
            end
            return pool
        end
    end

    local pool = {
        pos = surfacePos,
        amount = math.Clamp(tonumber(amount) or 0, 0, 1800),
        created = now,
        touched = now,
        expires = now + POOL_LIFETIME
    }
    pools[#pools + 1] = pool
    if normal then
        util.Decal("Blood", surfacePos + normal * 2, surfacePos - normal * 2, surfaceEnt)
    end

    while #pools > MAX_POOLS do table.remove(pools, 1) end
    return pool
end

local function FindBloodPool(pos, radius)
    local nearest, nearestDist
    local maxDist = (radius or POOL_USE_RADIUS) ^ 2
    for _, pool in ipairs(pools) do
        if pool.amount > 0 and pool.expires > CurTime() then
            local dist = pool.pos:DistToSqr(pos)
            if dist <= maxDist and (not nearestDist or dist < nearestDist) then
                nearest, nearestDist = pool, dist
            end
        end
    end
    return nearest
end

local function ClearVictimGrab(target, vampire)
    if not IsValid(target) or not target:IsPlayer() then return end
    if IsValid(target.ZevilVampireGrabbedBy) and vampire
        and target.ZevilVampireGrabbedBy ~= vampire then return end

    target.ZevilVampireGrabbedBy = nil
    target:SetNW2Entity("ZevilVampireGrabber", NULL)
    target:SetNW2Bool("ZevilVampireBeingBitten", false)
    SetHeadDown(target, false)
end

function ZV.StopDrinking(ply, reason)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local state = ply.ZevilVampireFeedState
    ply.ZevilVampireFeedState = nil
    ply:SetNW2Bool("ZevilVampireDrinking", false)
    ply:SetNW2Entity("ZevilVampireFeedTarget", NULL)
    SetHeadDown(ply, false)

    if state and IsValid(state.target) then
        ClearVictimGrab(state.target, ply)
    end
end

local function StartDrinking(ply, target, pool)
    if not IsVampire(ply) or ply.ZevilVampireFeedState then return false end
    if target == ply then return false end

    if IsValid(target) then
        local org = GetOrganism(target)
        if not org then return false end

        if target:IsPlayer() and target:Alive() then
            if not ply:OnGround() or ply:Crouching() then
                ply:ChatPrint("[Vampire] Stand upright to grab a living victim.")
                return false
            end
            if target:InVehicle() or ply:InVehicle() then return false end
        end
    elseif not pool or pool.amount <= 0 then
        return false
    end

    local state = {
        target = IsValid(target) and target or nil,
        pool = pool,
        nextPulse = CurTime() + 0.2,
        started = CurTime()
    }
    ply.ZevilVampireFeedState = state
    ply:SetNW2Bool("ZevilVampireDrinking", true)
    ply:SetNW2Entity("ZevilVampireFeedTarget", IsValid(target) and target or NULL)
    SetHeadDown(ply, true)

    if IsValid(target) and target:IsPlayer() and target:Alive() then
        target.ZevilVampireGrabbedBy = ply
        target:SetNW2Entity("ZevilVampireGrabber", ply)
        target:SetNW2Bool("ZevilVampireBeingBitten", true)
        SetHeadDown(target, true)
    end

    ply:EmitSound("npc/vort/claw_swing2.wav", 58, math.random(92, 104), 0.5)
    return true
end

local function ResolvePlayer(text)
    if not isstring(text) or text == "" then return nil end
    local needle = string.lower(text)
    for _, candidate in ipairs(player.GetAll()) do
        if string.lower(candidate:Nick()) == needle
            or tostring(candidate:UserID()) == needle
            or tostring(candidate:SteamID()) == needle then
            return candidate
        end
    end
    for _, candidate in ipairs(player.GetAll()) do
        if string.find(string.lower(candidate:Nick()), needle, 1, true) then
            return candidate
        end
    end
end

local function SetVampireClass(ply, cursed)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return false end

    if cursed ~= false then
        ply.ZevilVampireCursed = true
        ply:SetNW2Bool("ZevilVampireCursed", true)
    end

    local classList = player and player.classList
    if not (istable(classList) and istable(classList[CLASS_NAME])
        and isfunction(ply.SetPlayerClass)) then
        if not ply.ZevilVampireApplyPending then
            ply.ZevilVampireApplyPending = true
            timer.Simple(0.5, function()
                if not IsValid(ply) then return end
                ply.ZevilVampireApplyPending = nil
                if ply:Alive() and (ply.ZevilVampireCursed or cursed == false) then
                    SetVampireClass(ply, cursed)
                end
            end)
        end
        return false
    end

    if ply.PlayerClassName ~= CLASS_NAME then
        if not ply.ZevilVampirePreviousClassSaved then
            ply.ZevilVampirePreviousClass = isstring(ply.PlayerClassName) and ply.PlayerClassName or "none"
            ply.ZevilVampirePreviousClassSaved = true
        end
        ply:SetPlayerClass(CLASS_NAME)
    end
    return true
end

function ZV.Apply(ply)
    return SetVampireClass(ply, true)
end

function ZV.Cure(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return false end
    ply.ZevilVampireCursed = nil
    ply:SetNW2Bool("ZevilVampireCursed", false)
    ply.ZevilVampireApplyPending = nil
    ZV.StopDrinking(ply, "cured")

    if ply:Alive() and ply.PlayerClassName == CLASS_NAME then
        local previous = ply.ZevilVampirePreviousClass or "none"
        local classList = player and player.classList or {}
        if previous ~= "none" and not istable(classList[previous]) then previous = "none" end

        ply.ZevilVampirePreviousClass = nil
        ply.ZevilVampirePreviousClassSaved = nil
        ply:SetPlayerClass(previous)
    end
    return true
end

local function DrinkFromOrganism(vampire, target, state)
    local sourceOrg = GetOrganism(target)
    if not sourceOrg or sourceOrg.blood <= 0 then
        ZV.StopDrinking(vampire, "source exhausted")
        return
    end

    local vampireOrg = GetOrganism(vampire)
    local requested = math.max(1, cvBloodDrain:GetFloat())
    local amount = math.min(requested, sourceOrg.blood)
    sourceOrg.blood = math.max(0, sourceOrg.blood - amount)

    if vampireOrg then
        vampireOrg.blood = math.min(5000, math.max(0, vampireOrg.blood) + amount)
    end

    if target:IsPlayer() and target:Alive() or target:IsNPC() and target:Health() > 0
        or target.IsNextBot and target:Health() > 0 then
        local info = DamageInfo()
        info:SetAttacker(vampire)
        info:SetInflictor(vampire)
        info:SetDamage(math.max(0.1, cvBiteDamage:GetFloat()))
        info:SetDamageType(DMG_SLASH)
        local bitePos = target:WorldSpaceCenter()
        info:SetDamagePosition(bitePos)
        info:SetDamageForce((target:GetPos() - vampire:GetPos()):GetNormalized() * 120)
        target:TakeDamageInfo(info)

        if target:IsPlayer() and target:Alive()
            and target.PlayerClassName ~= CLASS_NAME
            and math.Rand(0, 100) < math.Clamp(cvCurseChance:GetFloat(), 0, 100) then
            target:ChatPrint("[Vampire] You feel a strange curse taking hold...")
            vampire:ChatPrint("[Vampire] The curse has passed to " .. target:Nick() .. ".")
            SetVampireClass(target, true)
        end

        -- Feeding restores some stamina without bypassing Z-City's wound and
        -- organ-damage processing; the real blood amount remains authoritative.
        if vampireOrg and istable(vampireOrg.stamina) and isnumber(vampireOrg.stamina[1]) then
            vampireOrg.stamina[1] = math.min(vampireOrg.stamina.max or 100, vampireOrg.stamina[1] + 8)
        end
        vampire:SetHealth(math.min(vampire:GetMaxHealth(), vampire:Health() + 3))
    end
end

local function FeedPulse(ply)
    local state = ply.ZevilVampireFeedState
    if not state or not IsVampire(ply) or not ply:KeyDown(IN_USE) then
        ZV.StopDrinking(ply, "feeding released")
        return
    end

    if state.target then
        if not IsValid(state.target) then
            ZV.StopDrinking(ply, "target removed")
            return
        end
        if ply:GetPos():DistToSqr(state.target:GetPos()) > 125 * 125 then
            ZV.StopDrinking(ply, "target out of reach")
            return
        end
        DrinkFromOrganism(ply, state.target, state)
        if ply.ZevilVampireFeedState and state.target:IsPlayer()
            and not state.target:Alive() then
            ZV.StopDrinking(ply, "victim died")
        end
    elseif state.pool then
        local amount = math.min(math.max(1, cvBloodDrain:GetFloat() * 0.65), state.pool.amount)
        local org = GetOrganism(ply)
        state.pool.amount = math.max(0, state.pool.amount - amount)
        if org then org.blood = math.min(5000, math.max(0, org.blood) + amount) end
        ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + 2))
        if state.pool.amount <= 0 then ZV.StopDrinking(ply, "pool exhausted") end
    else
        ZV.StopDrinking(ply, "no source")
    end
end

hook.Add("KeyPress", "Zevil_VampireStartFeeding", function(ply, key)
    if key ~= IN_USE or not IsVampire(ply) or ply.ZevilVampireFeedState then return end

    local tr = ply:GetEyeTrace()
    if tr.Hit and IsValid(tr.Entity) and tr.Entity ~= ply
        and ply:GetPos():DistToSqr(tr.Entity:GetPos()) <= USE_DISTANCE * USE_DISTANCE
        and GetOrganism(tr.Entity) then
        if StartDrinking(ply, tr.Entity, nil) then return end
    end

    if tr.Hit then
        local pool = FindBloodPool(tr.HitPos, POOL_USE_RADIUS)
        if pool then StartDrinking(ply, nil, pool) end
    end
end)

hook.Add("KeyRelease", "Zevil_VampireStopFeeding", function(ply, key)
    if key == IN_USE and ply.ZevilVampireFeedState then
        ZV.StopDrinking(ply, "feeding released")
    end
end)

hook.Add("PlayerUse", "Zevil_VampireConsumeFeedUse", function(ply, ent)
    if not IsVampire(ply) then return end
    if ply.ZevilVampireFeedState then return false end
    if IsValid(ent) and GetOrganism(ent) then return false end

    local tr = ply:GetEyeTrace()
    if tr.Hit and FindBloodPool(tr.HitPos, POOL_USE_RADIUS) then return false end
end)

hook.Add("Player Think", "Zevil_VampireFeedThink", function(ply)
    local state = ply.ZevilVampireFeedState
    if not state then return end
    if CurTime() < (state.nextPulse or 0) then return end
    state.nextPulse = CurTime() + DRINK_INTERVAL
    FeedPulse(ply)
end)

hook.Add("SetupMove", "Zevil_VampireHoldVictim", function(ply, mv)
    local vampire = ply.ZevilVampireGrabbedBy
    if not IsValid(vampire) or not IsVampire(vampire) then
        if vampire ~= nil then ClearVictimGrab(ply, vampire) end
        return
    end

    local state = vampire.ZevilVampireFeedState
    if not state or state.target ~= ply or not vampire:KeyDown(IN_USE) then
        ClearVictimGrab(ply, vampire)
        return
    end

    -- Hold horizontal movement while the vampire is feeding. Vertical velocity
    -- remains intact, so gravity and the engine's movement state keep working.
    mv:SetForwardSpeed(0)
    mv:SetSideSpeed(0)
    mv:SetUpSpeed(0)
    local velocity = mv:GetVelocity()
    mv:SetVelocity(Vector(0, 0, velocity.z))
end)

hook.Add("PlayerSpawn", "Zevil_VampireCursePersistence", function(ply)
    if not ply.ZevilVampireCursed then return end
    timer.Simple(0.2, function()
        if not IsValid(ply) or not ply:Alive() or not ply.ZevilVampireCursed then return end
        if ply.PlayerClassName ~= CLASS_NAME then SetVampireClass(ply, true) end
    end)
end)

hook.Add("PlayerDeath", "Zevil_VampireCleanupOnDeath", function(ply)
    ZV.StopDrinking(ply, "death")
    local grabber = ply.ZevilVampireGrabbedBy
    if IsValid(grabber) then ZV.StopDrinking(grabber, "victim died") end
end)

hook.Add("PlayerDisconnected", "Zevil_VampireCleanupDisconnect", function(ply)
    ZV.StopDrinking(ply, "disconnect")
    for _, candidate in ipairs(player.GetAll()) do
        if candidate.ZevilVampireFeedState
            and candidate.ZevilVampireFeedState.target == ply then
            ZV.StopDrinking(candidate, "target disconnected")
        end
    end
end)

hook.Add("EntityTakeDamage", "Zevil_VampireDamageWeaknessesAndBloodPools", function(ent, dmg)
    if not IsValid(ent) or not dmg then return end

    local org = GetOrganism(ent)
    local amount = math.max(tonumber(dmg:GetDamage()) or 0, 0)
    local hitPos = dmg:GetDamagePosition()
    if not isvector(hitPos) or hitPos:LengthSqr() < 1 then
        hitPos = ent:WorldSpaceCenter()
    end
    if org and amount >= 2 then
        AddBloodPool(hitPos, math.Clamp(amount * 7, 30, 320), ent)
    end

    if ent:IsPlayer() and IsValid(ent.ZevilVampireGrabbedBy) then
        local grabber = ent.ZevilVampireGrabbedBy
        if dmg:GetAttacker() ~= grabber and amount > 0 then
            ZV.StopDrinking(grabber, "victim was hit")
        end
    end

    if not IsVampire(ent) then return end

    local damageType = dmg:GetDamageType() or 0
    local fireMask = DMG_BURN
    if DMG_SLOWBURN then fireMask = bit.bor(fireMask, DMG_SLOWBURN) end
    if bit.band(damageType, fireMask) ~= 0 then
        dmg:SetDamage(dmg:GetDamage() * math.max(1, cvFireMultiplier:GetFloat()))
        ent.ZevilVampireBurnUntil = CurTime() + 2.5
    end

    -- The heart point is estimated from the native Spine2 bone and the player's
    -- own left/front axes. Only genuine, positioned physical hits qualify.
    if not isvector(hitPos) or hitPos:LengthSqr() < 1 then return end
    if bit.band(damageType, bit.bor(DMG_BULLET, DMG_BUCKSHOT, DMG_SLASH, DMG_CLUB, DMG_BLAST)) == 0 then
        return
    end
    if amount < 12 then return end

    local spine = ent:LookupBone("ValveBiped.Bip01_Spine2")
    if not isnumber(spine) or spine < 0 then return end
    local chestPos = ent:GetBonePosition(spine)
    if not isvector(chestPos) or chestPos:LengthSqr() < 1 then return end
    local heartPos = chestPos - ent:GetRight() * 4 + ent:GetForward() * 2 - ent:GetUp() * 2
    if hitPos:DistToSqr(heartPos) <= 10 * 10 then
        local liveOrg = GetOrganism(ent)
        if liveOrg then
            liveOrg.heart = 1
            liveOrg.heartstop = true
        end
        ent.ZevilVampireHeartFatal = true
        dmg:SetDamage(math.max(dmg:GetDamage(), 1000))
    end
end)

hook.Add("Org Think", "Zevil_VampireRegeneration", function(owner, org, mulTime)
    if not IsVampire(owner) or not istable(org) then return end
    if CurTime() < (owner.ZevilVampireBurnUntil or 0) then return end
    if org.heartstop or (isnumber(org.heart) and org.heart >= 0.98) then return end
    if not isnumber(org.blood) or org.blood < 1500 then return end

    local dt = math.Clamp(tonumber(mulTime) or 0.1, 0, 0.25)
    if dt <= 0 then return end

    local maxHealth = owner:GetMaxHealth()
    owner:SetHealth(math.min(maxHealth, owner:Health() + dt * math.max(0, cvRegenRate:GetFloat())))
    org.blood = math.max(0, org.blood - dt * math.max(0, cvBloodCost:GetFloat()))

    -- Repair tissue and ordinary open wounds quickly; heart-stop/fatal heart
    -- damage is deliberately excluded above. Z-City still owns the core organs.
    local organFields = {
        "brain", "liver", "stomach", "intestines", "chest", "pelvis",
        "skull", "trachea", "spine1", "spine2", "spine3",
        "lleg", "rleg", "larm", "rarm"
    }
    local organRepair = dt * 0.055
    for _, field in ipairs(organFields) do
        if isnumber(org[field]) then org[field] = math.max(0, org[field] - organRepair) end
    end

    if istable(org.wounds) then
        for index = #org.wounds, 1, -1 do
            local wound = org.wounds[index]
            if istable(wound) and isnumber(wound[1]) then
                wound[1] = math.max(0, wound[1] - dt * 3)
                if wound[1] <= 0 then table.remove(org.wounds, index) end
            end
        end
        if isfunction(owner.SetNetVar) then
            owner:SetNetVar("wounds", org.wounds)
        end
    end
end)

hook.Add("Org Think", "Zevil_VampireBleedSurfacePools", function(owner, org)
    if not IsValid(owner) or not istable(org) or not isnumber(org.blood)
        or org.blood <= 0 or not IsOpenWound(org) then return end
    if CurTime() < (owner.ZevilVampireNextBloodPool or 0) then return end

    owner.ZevilVampireNextBloodPool = CurTime() + 1.8
    local pos = owner:WorldSpaceCenter()
    AddBloodPool(pos, 34, owner)
end)

timer.Create("Zevil_VampirePoolCleanup", 30, 0, function()
    local now = CurTime()
    for index = #pools, 1, -1 do
        local pool = pools[index]
        if not pool or pool.amount <= 0 or pool.expires <= now then
            table.remove(pools, index)
        end
    end
end)

hook.Add("HG_MovementCalc_2", "Zevil_VampireSuperhumanMovement", function(mul, ply)
    if not IsVampire(ply) or not istable(mul) then return end
    mul[1] = ply:IsSprinting() and 1.45 or 1.15
    if ply.SpeedGainMul ~= 85 then ply.SpeedGainMul = 85 end
end)

concommand.Add("zevil_vampire", function(caller, _, args)
    if IsValid(caller) and not caller:IsAdmin() then return end
    local target = args[1] and ResolvePlayer(args[1]) or (IsValid(caller) and caller or nil)
    if not IsValid(target) then
        if IsValid(caller) then caller:ChatPrint("Usage: zevil_vampire <player name/userid>") end
        return
    end
    if SetVampireClass(target, true) then
        target:ChatPrint("[Vampire] The curse has taken hold.")
    end
end)

concommand.Add("zevil_cure_vampire", function(caller, _, args)
    if IsValid(caller) and not caller:IsAdmin() then return end
    local target = args[1] and ResolvePlayer(args[1]) or (IsValid(caller) and caller or nil)
    if not IsValid(target) then
        if IsValid(caller) then caller:ChatPrint("Usage: zevil_cure_vampire <player name/userid>") end
        return
    end
    ZV.Cure(target)
    target:ChatPrint("[Vampire] The curse has been lifted.")
end)

print("[Zevil] Native Z-City vampire player class mechanics loaded.")
