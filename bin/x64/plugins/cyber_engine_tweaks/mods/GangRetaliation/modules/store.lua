local Store = {
    path = "data/gang_retaliation.json",
    schema = 1,
    data = nil,
    -- Sube con cada "Store.dirty = true": el menu se reconstruye solo cuando cambia.
    version = 0,
}

local dirty = false
setmetatable(Store, {
    __index = function(_, key)
        if key == "dirty" then return dirty end
    end,
    __newindex = function(t, key, value)
        if key == "dirty" then
            dirty = value
            if value then rawset(t, "version", t.version + 1) end
        else
            rawset(t, key, value)
        end
    end,
})

local function emptyData()
    return { schema = Store.schema, campaigns = {} }
end

function Store.load()
    local file = io.open(Store.path, "r")
    if not file then
        Store.data = emptyData()
        return
    end

    local content = file:read("*a")
    file:close()

    local ok, decoded = pcall(json.decode, content)
    if ok and type(decoded) == "table" and type(decoded.campaigns) == "table" then
        Store.data = decoded
        for key, campaign in pairs(Store.data.campaigns) do
            if type(campaign.nemeses) ~= "table" or (#campaign.nemeses == 0 and #(campaign.homes or {}) == 0) then
                Store.data.campaigns[key] = nil
                Store.dirty = true
            end
        end
    else
        print("[GangRetaliation] JSON corrupto, se guarda copia en " .. Store.path .. ".bak")
        local backup = io.open(Store.path .. ".bak", "w")
        if backup then
            backup:write(content)
            backup:close()
        end
        Store.data = emptyData()
    end
end

function Store.save()
    if not Store.data then return false end

    local ok, encoded = pcall(json.encode, Store.data)
    if not ok then
        print("[GangRetaliation] Error al serializar: " .. tostring(encoded))
        return false
    end

    local file = io.open(Store.path, "w")
    if not file then
        print("[GangRetaliation] No se pudo escribir " .. Store.path)
        return false
    end
    file:write(encoded)
    file:close()
    Store.dirty = false
    return true
end

local EMPTY_CAMPAIGN = { nemeses = {} }

function Store.campaign(id)
    if not Store.data then Store.load() end
    return Store.data.campaigns[tostring(id)] or EMPTY_CAMPAIGN
end

function Store.ensureCampaign(id)
    if not Store.data then Store.load() end
    local key = tostring(id)
    local campaign = Store.data.campaigns[key]
    if not campaign then
        campaign = { created = os.time(), nemeses = {} }
        Store.data.campaigns[key] = campaign
        Store.dirty = true
    end
    return campaign
end

function Store.addNemesis(id, nemesis)
    local campaign = Store.ensureCampaign(id)
    campaign.nextId = (campaign.nextId or #campaign.nemeses) + 1
    nemesis.id = campaign.nextId
    table.insert(campaign.nemeses, nemesis)
    Store.dirty = true
    return nemesis
end

function Store.countAlive(id, gang)
    local count = 0
    for _, n in ipairs(Store.campaign(id).nemeses) do
        if n.gang == gang and n.status ~= "dead" then
            count = count + 1
        end
    end
    return count
end

function Store.clearCampaign(id)
    if not Store.data then return end
    Store.data.campaigns[tostring(id)] = nil
    Store.dirty = true
end

return Store
