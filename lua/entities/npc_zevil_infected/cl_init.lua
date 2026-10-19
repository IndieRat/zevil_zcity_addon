include("shared.lua")

local bloodMat = Material("sprites/glow04_noz")

function ENT:Draw()
    self:DrawModel()
    local stage = self:GetNW2Int("ZevilStage", 2)
    if stage < 2 then return end
    local head = self:LookupBone("ValveBiped.Bip01_Head1")
    if not head then return end
    local headPos = self:GetBonePosition(head)
    if not headPos or headPos == vector_origin then return end

    -- A dark, wet-looking stain/drop around the mouth; the drop shifts as the
    -- infected moves instead of changing or replacing the host model.
    local forward = self:GetForward()
    local mouth = headPos + forward * 4 - self:GetUp() * 5
    local pulse = 0.75 + math.abs(math.sin(CurTime() * 2.2 + self:EntIndex())) * 0.25
    render.SetMaterial(bloodMat)
    render.DrawSprite(mouth, 5 * pulse, 7 * pulse, Color(95, 8, 10, 220))
    if math.sin(CurTime() * 1.7 + self:EntIndex()) > 0.55 then
        local drip = mouth - self:GetUp() * (2 + math.abs(math.sin(CurTime() * 3)) * 3)
        render.DrawSprite(drip, 2.5, 4, Color(125, 12, 14, 205))
    end
end
