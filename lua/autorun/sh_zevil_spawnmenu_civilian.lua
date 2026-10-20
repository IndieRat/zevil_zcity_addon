if SERVER then AddCSLuaFile() end

list.Set("NPC", "npc_zevil_civilian", {
    Name = "Zevil Civilian",
    Class = "npc_zevil_civilian",
    Category = "Zevil - Survivors"
})

if CLIENT then
    language.Add("npc_zevil_civilian", "Zevil Civilian")
end
