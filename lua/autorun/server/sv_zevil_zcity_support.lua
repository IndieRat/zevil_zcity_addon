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

local function AttachNativeZCityOrganismOnly(ent)
    local api = hg and hg.organism
    if not IsValid(ent) or ent:IsPlayer() or not (istable(api)
        and istable(api.list) and isfunction(api.Add) and isfunction(api.Clear)) then
        return false
    end
    if not (BZCN and isfunction(BZCN.InstallAdapter)
        and isfunction(BZCN.IsManaged) and BZCN.IsManaged(ent)) then
        return false
    end

    local org = ent.organism
    local registered = istable(org) and api.list[ent] == org and org.owner == ent
    if not registered then
        local ok, result = pcall(api.Add, ent)
        if not ok or not istable(ent.organism) then
            if not ent.ZevilNativeOrganismWarned then
                ent.ZevilNativeOrganismWarned = true
                ErrorNoHalt("[Zevil] hg.organism.Add failed for "
                    .. tostring(ent:GetClass()) .. ": " .. tostring(result) .. "\n")
            end
            return false
        end
        org = ent.organism
        ent.ZevilNativeOrganismNeedsClear = true
    end

    -- Run Z-City's actual Org Clear initialization after Add. If load order makes
    -- a required Clear hook throw, retain the registered table and retry Clear;
    -- don't repeatedly call Add and wipe any wounds that were already recorded.
    if ent.ZevilNativeOrganismNeedsClear then
        local ok, result = pcall(api.Clear, org)
        if not ok then
            if not ent.ZevilNativeOrganismWarned then
                ent.ZevilNativeOrganismWarned = true
                ErrorNoHalt("[Zevil] hg.organism.Clear failed for "
                    .. tostring(ent:GetClass()) .. ": " .. tostring(result) .. "\n")
            end
            return false
        end
        ent.ZevilNativeOrganismNeedsClear = nil
        ent.ZevilNativeOrganismWarned = nil
    end

    org.owner = ent
    org.fakePlayer = true
    org.alive = ent:Health() > 0
    org.entindex = ent:EntIndex()
    org.health = tonumber(org.health) or math.max(ent:Health(), 0)
    org.maxHealth = tonumber(org.maxHealth) or math.max(tonumber(ent:GetMaxHealth()) or 100, 1)

    -- Native Org Clear modules normally populate these. Fill only missing fields
    -- so partial module load cannot make the official wound hook index nil tables.
    local defaults = {
        blood = 5000, maxBlood = 5000, pain = 0, shock = 0, immobilization = 0,
        wounds = {}, arterialwounds = {}, dmgstack = {},
        bulletwounds = 0, slashwounds = 0, stabwounds = 0, bruises = 0,
        burns = 0, explosionwounds = 0,
        larm = 0, rarm = 0, lleg = 0, rleg = 0, chest = 0, pelvis = 0,
        spine1 = 0, spine2 = 0, spine3 = 0, skull = 0, brain = 0,
        liver = 0, intestines = 0, heart = 0, stomach = 0,
        lungsL = {0, 0}, lungsR = {0, 0}
    }
    for key, value in pairs(defaults) do
        if org[key] == nil then
            org[key] = istable(value) and table.Copy(value) or value
        end
    end

    ent.organism = org
    ent.BZCN_Organism = org
    api.list[ent] = org
    ent.IsOrganism = true
    ent.hg_organism = true
    ent.ZevilZCitySupportAttached = true
    ent.ZevilZCitySupportNative = true
    ent.ZevilZCitySupportMode = "native-only"

    if isfunction(ent.SetNetVar) then
        pcall(ent.SetNetVar, ent, "wounds", org.wounds)
        pcall(ent.SetNetVar, ent, "arterialwounds", org.arterialwounds)
    elseif BZCN and isfunction(BZCN.SetNetVar) then
        pcall(BZCN.SetNetVar, ent, "wounds", org.wounds)
        pcall(BZCN.SetNetVar, ent, "arterialwounds", org.arterialwounds)
    end

    if not ent.ZevilNativeOrganismCleanupInstalled and ent.CallOnRemove then
        ent.ZevilNativeOrganismCleanupInstalled = true
        ent:CallOnRemove("ZevilNativeOrganismCleanup", function(removed)
            local currentAPI = hg and hg.organism
            if not (istable(currentAPI) and istable(currentAPI.list)
                and currentAPI.list[removed] == removed.organism) then return end
            if isfunction(currentAPI.Remove) then
                pcall(currentAPI.Remove, removed)
            else
                currentAPI.list[removed] = nil
            end
        end)
    end

    return true
end

function Zevil.AttachZCityNPCSupport(ent, className, faction)
    if not IsValid(ent) or ent:IsPlayer() then return false end
    if ent.ZevilZCitySupportRetryScheduled then return true end

    ent.ZevilZCitySupportRetryScheduled = true
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
                    ent.ZevilZCitySupportMode = "bzcn"
                    ent.ZevilZCitySupportRetryScheduled = nil
                    ent.IsOrganism = true
                    ent.hg_organism = true
                    ent.ZevilZCitySupportWarned = nil
                    if not ent.ZevilZCitySupportLogged then
                        ent.ZevilZCitySupportLogged = true
                        print("[Zevil] Native Z-City wounds attached: "
                            .. ent:GetClass() .. "#" .. ent:EntIndex())
                    end
                    return
                end
            elseif not ok and not ent.ZevilZCitySupportWarned then
                ent.ZevilZCitySupportWarned = true
                ErrorNoHalt("[Zevil] Z-City NPC injury attachment failed for "
                    .. tostring(ent:GetClass()) .. ": " .. tostring(state) .. "\n")
            end
        end

        -- If the optional BZCN injury bridge isn't mounted, use Z-City's
        -- own Add/Clear/list lifecycle directly. This still creates a real native
        -- organism for Z-City's EntityTakeDamage wound pipeline; it intentionally
        -- does not pretend to provide BZCN's extra limb-tracking/downed recovery.
        if not (support and isfunction(support.Attach)) and nativeAPIReady then
            local ok, attached = pcall(AttachNativeZCityOrganismOnly, ent)
            if ok and attached then
                ent.ZevilZCitySupportRetryScheduled = nil
                ent.ZevilZCitySupportWarned = nil
                if not ent.ZevilZCitySupportLogged then
                    ent.ZevilZCitySupportLogged = true
                    print("[Zevil] Native Z-City organism/wounds attached (native-only; "
                        .. "BZCN downed recovery unavailable): "
                        .. ent:GetClass() .. "#" .. ent:EntIndex())
                end
                return
            elseif not ok and not ent.ZevilZCitySupportWarned then
                ent.ZevilZCitySupportWarned = true
                ErrorNoHalt("[Zevil] Native-only organism attachment failed for "
                    .. tostring(ent:GetClass()) .. ": " .. tostring(attached) .. "\n")
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

        if count >= 40 then ent.ZevilZCitySupportRetryScheduled = nil end
    end

    attempt(0)
    return true
end


local function CountZevilWounds(ent, key)
    local org = ent.organism or ent.BZCN_Organism
    if istable(org) and istable(org[key]) then return table.Count(org[key]) end
    if isfunction(ent.GetNetVar) then
        local ok, value = pcall(ent.GetNetVar, ent, key, {})
        if ok and istable(value) then return table.Count(value) end
    end
    return 0
end

local function DescribeZevilNPC(ent)
    local api = hg and hg.organism
    local nativeList = api and api.list
    local registered = istable(nativeList) and ent.organism ~= nil
        and nativeList[ent] == ent.organism
    local profile = ent.BZCNClassProfile or {}
    local puppet = ent.ZevilFakePuppet
    local downed = ent.BZCNNPCRagdoll
    local body = IsValid(puppet) and puppet or (IsValid(downed) and downed or ent)
    local bodyWounds = IsValid(body) and CountZevilWounds(body, "wounds") or 0
    print(string.format(
        "[Zevil] %s#%d model=%s class=%s zombieStyle=%s appearanceCatalogue=%s attached=%s mode=%s nativeFlag=%s registry=%s hostWounds=%d hostArterial=%d body=%s bodyWounds=%d",
        ent:GetClass(), ent:EntIndex(), tostring(ent:GetModel()),
        tostring(ent.BZCNClass or ent.PlayerClassName or "none"),
        tostring(profile.ZombieStyle == true),
        tostring(ent.ZevilHGAppearance == true),
        tostring(ent.ZevilZCitySupportAttached == true),
        tostring(ent.ZevilZCitySupportMode or "none"),
        tostring(ent.ZevilZCitySupportNative == true),
        tostring(registered),
        CountZevilWounds(ent, "wounds"),
        CountZevilWounds(ent, "arterialwounds"),
        IsValid(body) and (body:GetClass() .. "/" .. tostring(body:GetModel())) or "invalid",
        bodyWounds
    ))
end

-- Autorun order differs across workshop collections. Keep watching so NPCs
-- spawned before the injury module loads can gain real native support later.
timer.Create("Zevil_ZCitySupportWatchdog", 5, 0, function()
    local api = hg and hg.organism
    local support = hg and hg.BZCNNPCSupport
    local nativeList = api and api.list
    local nativeAPIReady = istable(nativeList)
        and isfunction(api.Add) and isfunction(api.Clear)

    for _, className in ipairs({"npc_zevil_infected", "npc_zevil_civilian"}) do
        local classProfile = className == "npc_zevil_infected" and "ZevilInfected" or "ZevilCivilian"
        local faction = className == "npc_zevil_infected" and "zombie" or "civilian"
        for _, ent in ipairs(ents.FindByClass(className)) do
            if not IsValid(ent) then continue end
            local registered = nativeAPIReady and ent.organism ~= nil
                and nativeList[ent] == ent.organism
            local canUpgradeNativeOnly = ent.ZevilZCitySupportMode == "native-only"
                and support and isfunction(support.Attach)
            if registered and ent.ZevilZCitySupportAttached == true and not canUpgradeNativeOnly then
                ent.ZevilZCitySupportNative = true
                ent.IsOrganism = true
                ent.hg_organism = true
            else
                ent.ZevilZCitySupportNative = nil
                ent.IsOrganism = nil
                ent.hg_organism = nil
                Zevil.AttachZCityNPCSupport(ent, classProfile, faction)
            end
        end
    end
end)

concommand.Add("zevil_zcity_status", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local api = hg and hg.organism
    local support = hg and hg.BZCNNPCSupport
    local infectedProfile = BZCN and BZCN.GetClass and BZCN.GetClass("ZevilInfected") or nil
    print("[Zevil] ---- Z-City integration status ----")
    print(string.format(
        "[Zevil] organismAPI=%s list=%s Add=%s Clear=%s BZCN=%s ApplyClass=%s injuryAttach=%s infectedZombieStyle=%s",
        tostring(istable(api)), tostring(api and istable(api.list) or false),
        tostring(api and isfunction(api.Add) or false),
        tostring(api and isfunction(api.Clear) or false),
        tostring(BZCN ~= nil), tostring(BZCN and isfunction(BZCN.ApplyClass) or false),
        tostring(support and isfunction(support.Attach) or false),
        tostring(istable(infectedProfile) and infectedProfile.ZombieStyle == true)
    ))
    for _, className in ipairs({"npc_zevil_infected", "npc_zevil_civilian"}) do
        for _, ent in ipairs(ents.FindByClass(className)) do
            if IsValid(ent) then DescribeZevilNPC(ent) end
        end
    end
    print("[Zevil] ---- end integration status ----")
end, nil, "Diagnose Zevil appearance, visible puppets and native Z-City wound registration.")

print("[Zevil] Z-City NPC injury adapter loaded.")
