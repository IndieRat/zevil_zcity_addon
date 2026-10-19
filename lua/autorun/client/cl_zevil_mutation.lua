-- Client-only mutation overlay. Never changes the player's model.
if not CLIENT then return end
Zevil = Zevil or {}
local infected = false
local stage = 0
local exposure = 0
local cvVisuals = CreateClientConVar("zevil_cl_mutation_visuals", "1", true, false, "Render Zevil mutation visuals")
local mat = Material("models/charple/charple1_sheet")

net.Receive("Zevil_VirusState", function()
    infected = net.ReadBool()
    stage = net.ReadUInt(3)
    exposure = net.ReadFloat()
end)

hook.Add("Think", "Zevil_ClientMutationState", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    infected = ply:GetNW2Bool("ZevilInfected", infected)
    stage = ply:GetNW2Int("ZevilStage", stage)
end)

hook.Add("PrePlayerDraw", "Zevil_ModelPreservingMutation", function(ply)
    if not cvVisuals:GetBool() or not GetConVar("zevil_player_visuals") then return end
    if not GetConVar("zevil_player_visuals"):GetBool() then return end
    local isInfected = ply:GetNW2Bool("ZevilInfected", false)
    if not isInfected then return end
    local s = math.Clamp(ply:GetNW2Int("ZevilStage", 1), 1, 5)
    local strength = GetConVar("zevil_mutation_strength")
        and math.Clamp(GetConVar("zevil_mutation_strength"):GetFloat(), 0, 2) or 1
    local blend = math.Clamp((s - 1) / 4, 0, 1) * strength
    local oldColor = ply:GetColor()
    local oldMaterial = ply:GetMaterial()
    local oldRenderMode = ply:GetRenderMode()
    local r = math.floor(255 - 100 * blend)
    local g = math.floor(255 - 125 * blend)
    local b = math.floor(255 - 115 * blend)
    ply:SetColor(Color(r, g, b, oldColor.a))
    if s >= 3 and oldMaterial == "" then ply:SetMaterial("models/charple/charple1_sheet") end
    if s >= 4 then ply:SetRenderMode(RENDERMODE_TRANSALPHA) end
    -- Bone scaling is applied and restored in PostPlayerDraw so the current
    -- model, clothing and bodygroups remain intact.
    ply.ZevilRenderRestore = {color = oldColor, material = oldMaterial, mode = oldRenderMode}
    for i = 0, ply:GetBoneCount() - 1 do
        local name = string.lower(ply:GetBoneName(i) or "")
        local scale = Vector(1, 1, 1)
        if s >= 3 and (string.find(name, "spine", 1, true) or string.find(name, "neck", 1, true)) then
            scale = Vector(1 - 0.04 * blend, 1, 1 + 0.03 * blend)
        elseif s >= 4 and (string.find(name, "upperarm", 1, true) or string.find(name, "forearm", 1, true)) then
            scale = Vector(1 + 0.06 * blend, 1, 1 - 0.04 * blend)
        end
        if scale ~= Vector(1, 1, 1) then ply:ManipulateBoneScale(i, scale) end
    end
end)

hook.Add("PostPlayerDraw", "Zevil_RestoreMutationVisuals", function(ply)
    local restore = ply.ZevilRenderRestore
    if not restore then return end
    ply:SetColor(restore.color or color_white)
    ply:SetMaterial(restore.material or "")
    ply:SetRenderMode(restore.mode or RENDERMODE_NORMAL)
    for i = 0, ply:GetBoneCount() - 1 do ply:ManipulateBoneScale(i, Vector(1, 1, 1)) end
    ply.ZevilRenderRestore = nil
end)

hook.Add("HUDPaint", "Zevil_InfectionHUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:GetNW2Bool("ZevilInfected", false) then return end
    local s = ply:GetNW2Int("ZevilStage", 1)
    draw.SimpleText("INFECTION  //  STAGE " .. s, "DermaDefaultBold",
        ScrW() - 28, ScrH() - 82, Color(190, 55, 45), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end)
