-- Safe bridge from Zevil NextBots into BZCN's Z-City injury support.
-- Never attach this path to Players; their native Z-City organism lifecycle stays authoritative.
if not SERVER then return end

Zevil = Zevil or {}

local function InstallManagedIdentity(ent, className, faction)
    if not IsValid(ent) or ent:IsPlayer() then return false end
    if not (BZCN and isfunction(BZCN.InstallAdapter)) then return false end

    ent.BZCNManaged = true
    ent:SetNW2Bool("BZCNManaged", true)
    ent.BZCNClass = className or ent.BZCNClass or "ZevilInfected"

    local profile = BZCN.GetClass and BZCN.GetClass(ent.BZCNClass) or nil
    if istable(profile) then
        ent.BZCNClassProfile = ent.BZCNClassProfile or table.Copy(profile)
        ent.PlayerClassName = ent.PlayerClassName or profile.PlayerClassName or ent.BZCNClass
    else
        ent.BZCNClassProfile = ent.BZCNClassProfile or {
            ClassName = ent.BZCNClass,
            PlayerClassName = ent.BZCNClass,
            Faction = faction or "Zevil",
            TeamName = faction or "Zevil"
        }
        ent.PlayerClassName = ent.PlayerClassName or ent.BZCNClass
    end

    ent.BZCN_Faction = ent.BZCN_Faction or faction or "Zevil"
    ent.BZCN_TeamName = ent.BZCN_TeamName or faction or "Zevil"
    ent:SetNW2String("BZCNClass", ent.BZCNClass)
    ent:SetNW2String("PlayerClassName", ent.PlayerClassName)
    ent:SetNW2String("BZCNFaction", ent.BZCN_Faction)
    ent:SetNW2String("BZCNTeamName", ent.BZCN_TeamName)

    local ok, result = pcall(BZCN.InstallAdapter, ent)
    if not ok then
        ErrorNoHalt("[Zevil] Could not install BZCN NPC adapter: " .. tostring(result) .. "\n")
        return false
    end
    return true
end

function Zevil.AttachZCityNPCSupport(ent, className, faction)
    if not IsValid(ent) or ent:IsPlayer() then return false end

    InstallManagedIdentity(ent, className, faction)

    local function attempt(count)
        if not IsValid(ent) then return end
        local support = hg and hg.BZCNNPCSupport
        local organismAPI = hg and hg.organism
        local nativeAPIReady = istable(organismAPI)
            and istable(organismAPI.list)
            and isfunction(organismAPI.Add)
            and isfunction(organismAPI.Clear)

        -- Do not invoke BZCN's fallback attachment until Z-City's own Add/Clear
        -- lifecycle is registered. Some BZCN fallback modes expose a compatible
        -- organism-shaped table without registering it in hg.organism.list.
        if support and isfunction(support.Attach) and nativeAPIReady then
            local ok, state = pcall(support.Attach, ent)
            if ok and istable(state) then
                ent.ZevilZCitySupportAttached = true
                ent.ZevilZCitySupportNative = state.usesZCityOrganism == true
                if ent.ZevilZCitySupportNative then
                    ent.IsOrganism = true
                    ent.hg_organism = true
                    ent.ZevilZCitySupportWarned = nil
                    return
                end
            elseif not ok and not ent.ZevilZCitySupportWarned then
                ent.ZevilZCitySupportWarned = true
                ErrorNoHalt("[Zevil] Z-City NPC injury attachment failed for "
                    .. tostring(ent:GetClass()) .. ": " .. tostring(state) .. "\n")
            end
        end

        -- BZCN.ApplyClass may optimistically set these flags when only its
        -- adapter is loaded. Clear them until a native organism is registered.
        if not nativeAPIReady or ent.ZevilZCitySupportNative ~= true then
            ent.IsOrganism = nil
            ent.hg_organism = nil
        end

        -- Autorun order differs across collections; retry until the BZCN
        -- injury bridge and native Z-City organism registry are both ready.
        if count < 40 then
            timer.Simple(0.5, function()
                if IsValid(ent) then attempt(count + 1) end
            end)
        elseif not ent.ZevilZCitySupportNative and not ent.ZevilZCitySupportWarned then
            ent.ZevilZCitySupportWarned = true
            print("[Zevil] Native Z-City NPC injury support is unavailable; "
                .. tostring(ent:GetClass()) .. " will use its standalone behavior.")
        end
    end

    attempt(0)
    return true
end

print("[Zevil] Z-City NPC injury adapter loaded.")
