AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

local MODELS = {
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

local function PickCivilianModel()
    local available = {}
    for _, model in ipairs(MODELS) do
        if util.IsValidModel(model) then available[#available + 1] = model end
    end
    if #available == 0 then return "models/player/group03/male_07.mdl" end
    return available[math.random(#available)]
end

function ENT:Initialize()
    self:SetModel(PickCivilianModel())
    self:SetHealth(100)
    self:SetMaxHealth(100)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionGroup(COLLISION_GROUP_NPC)
    self:SetCollisionBounds(Vector(-13, -13, 0), Vector(13, 13, 72))
    self.loco:SetDesiredSpeed(90)
    self.loco:SetAcceleration(450)
    self.loco:SetDeceleration(650)
    self.loco:SetStepHeight(18)
    self.loco:SetJumpHeight(35)
    self.ZevilCivilian = true
    self.ZevilCivilianName = "Survivor " .. self:EntIndex()
    self:SetNW2Bool("ZevilCivilian", true)
    self:SetNW2String("ZevilCivilianName", self.ZevilCivilianName)
    self.NextPanic = 0
end

function ENT:SpawnFunction(ply, trace, className)
    if not trace or not trace.Hit then return end
    local civilian = ents.Create(className or "npc_zevil_civilian")
    if not IsValid(civilian) then return end
    civilian:SetPos(trace.HitPos + trace.HitNormal * 8)
    civilian:SetAngles(Angle(0, IsValid(ply) and ply:EyeAngles().y or 0, 0))
    civilian:Spawn()
    civilian:Activate()
    return civilian
end

function ENT:NearestThreat()
    local best, bestDist
    for _, ent in ipairs(ents.FindInSphere(self:GetPos(), 850)) do
        if not IsValid(ent) or ent == self or ent:Health() <= 0 then continue end
        if not (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()) then continue end
        local infected = ent:GetClass() == "npc_zevil_infected"
            or ent.ZevilInfectedAttacker == true
            or (istable(ent.ZevilVirus) and ent.ZevilVirus.Infected == true)
        if not infected then continue end
        local dist = self:GetPos():DistToSqr(ent:GetPos())
        if not bestDist or dist < bestDist then best, bestDist = ent, dist end
    end
    return best, bestDist
end

function ENT:RunBehaviour()
    while IsValid(self) do
        local threat, dist = self:NearestThreat()
        if IsValid(threat) and dist < 600 * 600 then
            self:StartActivity(ACT_RUN)
            self.loco:SetDesiredSpeed(185)
            local away = self:GetPos() - threat:GetPos()
            away.z = 0
            if away:LengthSqr() < 1 then away = VectorRand() end
            away:Normalize()
            self:MoveToPos(self:GetPos() + away * math.random(350, 650), {
                tolerance = 45, maxage = 1.5, lookahead = 250
            })
            if CurTime() >= self.NextPanic then
                self.NextPanic = CurTime() + math.Rand(2.5, 5)
                self:EmitSound("vo/npc/male01/runforyourlife01.wav", 65, math.random(95, 108))
            end
        else
            self:StartActivity(ACT_WALK)
            self.loco:SetDesiredSpeed(math.random(35, 55))
            self:MoveToPos(self:GetPos() + VectorRand() * math.random(100, 240), {
                tolerance = 35, maxage = 2.5, lookahead = 150
            })
        end
        coroutine.yield()
    end
end

function ENT:OnInjured(dmg)
    local attacker = dmg:GetAttacker()
    if IsValid(attacker) and attacker ~= self then
        local direction = self:GetPos() - attacker:GetPos()
        direction.z = 0
        if direction:LengthSqr() > 0 then
            direction:Normalize()
            self.loco:SetVelocity(direction * 160 + Vector(0, 0, 35))
        end
    end
end

function ENT:OnKilled(dmg)
    local rag = ents.Create("prop_ragdoll")
    if IsValid(rag) then
        rag:SetModel(self:GetModel())
        rag:SetPos(self:GetPos())
        rag:SetAngles(self:GetAngles())
        rag:Spawn()
        rag:Activate()
        SafeRemoveEntityDelayed(rag, 180)
    end
    self:Remove()
end
