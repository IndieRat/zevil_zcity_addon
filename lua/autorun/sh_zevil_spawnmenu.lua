-- Explicit Spawn Menu registration so the Zevil infected appears in the NPC list
-- as well as the scripted-entities browser. This is client and server safe.
if SERVER then AddCSLuaFile() end

if list and isfunction(list.Set) then
    list.Set("NPC", "npc_zevil_infected", {
        Name = "Zevil Infected",
        Class = "npc_zevil_infected",
        Category = "Zevil - Resident Evil"
    })
end

if CLIENT and language and isfunction(language.Add) then
    language.Add("npc_zevil_infected", "Zevil Infected")
end

