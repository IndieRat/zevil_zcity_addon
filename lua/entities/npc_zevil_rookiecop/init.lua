AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

-- Reuse the Better Z-City NPC framework when installed. The class definition
-- falls back to a stock citizen NextBot base if BZCN is not mounted.
function ENT:Initialize()
    if self.BaseClass and self.BaseClass.Initialize then
        self.BaseClass.Initialize(self)
    end
    if self.SetNW2String then
        self:SetNW2String("ZevilSurvivorRole", "rookie_cop")
    end
    self.ZevilSurvivor = true
end
