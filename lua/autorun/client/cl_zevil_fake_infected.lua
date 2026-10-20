-- Infected mouth-blood effect for the visible shadow-ragdoll puppet.
if not CLIENT then return end

local bloodMat = Material("sprites/glow04_noz")

-- Client-facing body resolver for wound renderers/compatibility adapters.
-- Prefer the entity the server says is currently visible, including BZCN's
-- knockdown ragdoll; fall back to the NextBot when no proxy is active.
Zevil = Zevil or {}
Zevil.InfectedFake = Zevil.InfectedFake or {}
function Zevil.InfectedFake.GetVisibleBody(ent)
    if not IsValid(ent) then return nil end
    local body = ent.GetNW2Entity and ent:GetNW2Entity("ZevilVisibleBody") or nil
    return IsValid(body) and body or ent
end

function Zevil.InfectedFake.GetOwner(body)
    if not IsValid(body) then return nil end

    -- Resolve Zevil's own puppet first, then the BZCN adapter owner, then the
    -- native Z-City fake-ragdoll "ply" convention used by third-party effects.
    local owner = body.GetNW2Entity and body:GetNW2Entity("ZevilPuppetOwner") or nil
    if not IsValid(owner) and body.GetNW2Entity then
        owner = body:GetNW2Entity("BZCNNPCOwner")
    end
    if not IsValid(owner) and body.GetNW2Entity then
        owner = body:GetNW2Entity("ply")
    end
    if not IsValid(owner) and body.GetNWEntity then
        owner = body:GetNWEntity("ply")
    end
    if not IsValid(owner) and body.GetNetVar then
        local ok, value = pcall(body.GetNetVar, body, "ply", nil)
        if ok then owner = value end
    end
    if not IsValid(owner) and body.GetNWEntity then
        owner = body:GetNWEntity("BZCNNPCOwner")
    end
    return IsValid(owner) and owner or nil
end
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

        local headPos, headAng
        local matrix = rag:GetBoneMatrix(head)
        if matrix then
            headPos = matrix:GetTranslation()
            headAng = matrix:GetAngles()
        else
            headPos, headAng = rag:GetBonePosition(head)
        end
        if not isvector(headPos) or headPos == vector_origin or not isangle(headAng) then continue end

        -- Use the actual head orientation rather than the ragdoll entity's root
        -- angles, so the mouth cue stays on the face when its head is turned.
        local forward, up = headAng:Forward(), headAng:Up()
        local mouth = headPos + forward * 3.6 - up * 3.2
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
