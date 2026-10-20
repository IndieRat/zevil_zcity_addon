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

local function SetupBZCNCivilianIdentity(self)
    if not (BZCN and isfunction(BZCN.InstallAdapter)) then return end

    self.BZCNManaged = true
    self.BZCNClass = "ZevilCivilian"
    self.PlayerClassName = "civilian"
    self.BZCNClassProfile = table.Copy(BZCN.GetClass and BZCN.GetClass("ZevilCivilian") or {
        ClassName = "ZevilCivilian",
        PlayerClassName = "civilian",
        Faction = "civilian",
        TeamName = "Survivor"
    })
    self.BZCN_Faction = "civilian"
    self.BZCN_TeamName = "Survivor"
    self:SetNW2Bool("BZCNManaged", true)
    self:SetNW2String("BZCNClass", "ZevilCivilian")
    self:SetNW2String("PlayerClassName", "civilian")
    self:SetNW2String("BZCNFaction", "civilian")
    self:SetNW2String("BZCNTeamName", "Survivor")
    pcall(BZCN.InstallAdapter, self)
end

local function RandomizeFallbackAppearance(self)
    self:SetModel(PickCivilianModel())
    local skinCount = isfunction(self.SkinCount) and self:SkinCount() or 1
    if skinCount > 0 then self:SetSkin(math.random(0, skinCount - 1)) end

    -- The player citizen models have optional bodygroups as well as skins;
    -- vary them when the Z-City appearance generator is unavailable.
    if isfunction(self.GetBodyGroups) and isfunction(self.SetBodygroup) then
        for _, group in ipairs(self:GetBodyGroups() or {}) do
            local id = tonumber(group.id)
            local count = tonumber(group.num) or 0
            if id and id >= 0 and count > 1 then
                self:SetBodygroup(id, math.random(0, count - 1))
            end
        end
    end
end

local function ApplyHGAppearance(self)
    local appearanceAPI = hg and hg.Appearance
    if not (appearanceAPI and isfunction(appearanceAPI.GetRandomAppearance)
        and isfunction(appearanceAPI.ForceApplyAppearance)) then
        return false
    end

    local ok, raw = pcall(appearanceAPI.GetRandomAppearance)
    if not ok or not istable(raw) then return false end
    local appearance = table.Copy(raw)
    if isstring(appearance.AModel) and not util.IsValidModel(appearance.AModel) then
        appearance.AModel = nil
    end

    local modelSex = BZCN and isfunction(BZCN.GetModelSex)
        and BZCN.GetModelSex(appearance.AModel) or nil
    local playerModels = appearanceAPI.PlayerModels
    local isFemale = modelSex == 2
    if modelSex == nil and istable(playerModels) and isstring(appearance.AModel) then
        local modelInfo = (playerModels[1] and playerModels[1][appearance.AModel])
            or (playerModels[2] and playerModels[2][appearance.AModel])
        if istable(modelInfo) then
            isFemale = modelInfo.sex == true
            modelSex = isFemale and 2 or 1
        end
    end

    -- Match BZCN's civilian generation: sex-aware names and independently mixed
    -- shirt/pants/boots themes prevent a crowd of clones in matching outfits.
    if BZCN and isfunction(BZCN.GetRandomHumanName) then
        appearance.AName = BZCN.GetRandomHumanName(modelSex or (isFemale and 2 or 1))
    end
    local clothingSets = appearanceAPI.Clothes and appearanceAPI.Clothes[isFemale and 2 or 1]
    if istable(clothingSets) then
        local themes = {}
        for theme in pairs(clothingSets) do themes[#themes + 1] = theme end
        if #themes >= 2 then
            local function PickTheme(except)
                local choices = {}
                for _, theme in ipairs(themes) do
                    if theme ~= except then choices[#choices + 1] = theme end
                end
                if #choices == 0 then choices = themes end
                return choices[math.random(#choices)]
            end
            local mainTheme = PickTheme(nil)
            local pantsTheme = PickTheme(mainTheme)
            local bootsTheme = PickTheme(mainTheme)
            if bootsTheme == pantsTheme and #themes > 2 then bootsTheme = PickTheme(pantsTheme) end
            appearance.AClothes = {main = mainTheme, pants = pantsTheme, boots = bootsTheme}
        end
    end

    -- Z-City's player appearance applier expects several Player-only methods.
    -- Install the same short-lived compatibility shims used by the BZCN base.
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

    local applied, applyResult = pcall(appearanceAPI.ForceApplyAppearance, self, appearance)
    for _, saved in ipairs(savedMethods) do self[saved[1]] = saved[2] end
    if not applied or not util.IsValidModel(self:GetModel()) then
        if not self.ZevilAppearanceWarned then
            self.ZevilAppearanceWarned = true
            ErrorNoHalt("[Zevil] Z-City civilian appearance failed: " .. tostring(applyResult) .. "\n")
        end
        return false
    end

    self.CurAppearance = table.Copy(appearance)
    self.BZCNDisplayName = appearance.AName
    self.PlayerName = appearance.AName
    self:SetNW2String("BZCNDisplayName", appearance.AName or ("Survivor " .. self:EntIndex()))
    if isfunction(self.SetNetVar) then
        pcall(self.SetNetVar, self, "Accessories", table.Copy(appearance.AAttachments or {}))
        pcall(self.SetNetVar, self, "PlayerName", appearance.AName or ("Survivor " .. self:EntIndex()))
    elseif BZCN and isfunction(BZCN.SetNetVar) then
        pcall(BZCN.SetNetVar, self, "Accessories", table.Copy(appearance.AAttachments or {}))
        pcall(BZCN.SetNetVar, self, "PlayerName", appearance.AName or ("Survivor " .. self:EntIndex()))
    end
    if istable(self.BZCNClassProfile) then self.BZCNClassProfile.Model = self:GetModel() end
    return true
end

-- Avoid resetting walk/run sequence progress every time the behavior coroutine
-- resumes; BodyMoveXY drives the sequence's locomotion pose parameters.
function ENT:SetZevilActivity(activity)
    if self.ZevilCurrentActivity == activity then return end
    self.ZevilCurrentActivity = activity
    self:StartActivity(activity)
end

function ENT:BodyUpdate()
    if self.BZCNNPCDowned then return end
    self:BodyMoveXY()
end

function ENT:Initialize()
    self:SetModel(PickCivilianModel())
    SetupBZCNCivilianIdentity(self)
    if not ApplyHGAppearance(self) then RandomizeFallbackAppearance(self) end
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

    if Zevil and isfunction(Zevil.AttachZCityNPCSupport) then
        Zevil.AttachZCityNPCSupport(self, "ZevilCivilian", "civilian")
    end
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
        if self.BZCNNPCDowned then
            coroutine.wait(0.15)
            continue
        end
        local threat, dist = self:NearestThreat()
        if IsValid(threat) and dist < 600 * 600 then
            self:SetZevilActivity(ACT_RUN)
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
            self:SetZevilActivity(ACT_WALK)
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
