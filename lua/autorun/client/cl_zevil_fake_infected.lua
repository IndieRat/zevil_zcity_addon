-- Infected mouth-blood effect for the visible shadow-ragdoll puppet.
if not CLIENT then return end

local bloodMat = Material("sprites/glow04_noz")
local puppets = setmetatable({}, {__mode = "k"})
local nextScan = 0

hook.Add("Think", "Zevil_FakeInfected_FindPuppets", function()
    if CurTime() < nextScan then return end
    nextScan = CurTime() + 0.4

    local found = setmetatable({}, {__mode = "k"})
    for _, ent in ipairs(ents.FindByClass("prop_ragdoll")) do
        if IsValid(ent) and ent:GetNW2Bool("ZevilFakePuppet", false) then
            found[ent] = true
        end
    end
    puppets = found
end)

hook.Add("PostDrawOpaqueRenderables", "Zevil_FakeInfected_MouthBlood", function(drawingDepth, drawingSkybox)
    if drawingDepth or drawingSkybox then return end

    for rag in pairs(puppets) do
        if not IsValid(rag) or not rag:GetNW2Bool("ZevilFakePuppet", false) then
            puppets[rag] = nil
            continue
        end

        local head = rag:LookupBone("ValveBiped.Bip01_Head1")
        if not head then continue end
        local headPos = rag:GetBonePosition(head)
        if not headPos or headPos == vector_origin then continue end

        local forward, up = rag:GetForward(), rag:GetUp()
        local mouth = headPos + forward * 4 - up * 5
        local phase = rag:EntIndex()
        local pulse = 0.75 + math.abs(math.sin(CurTime() * 2.2 + phase)) * 0.25

        render.SetMaterial(bloodMat)
        render.DrawSprite(mouth, 5 * pulse, 7 * pulse, Color(95, 8, 10, 220))
        if math.sin(CurTime() * 1.7 + phase) > 0.55 then
            local drip = mouth - up * (2 + math.abs(math.sin(CurTime() * 3)) * 3)
            render.DrawSprite(drip, 2.5, 4, Color(125, 12, 14, 205))
        end
    end
end)
