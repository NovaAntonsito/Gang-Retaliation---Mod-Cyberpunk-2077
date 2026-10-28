local Escorts = require("modules/escorts")

local Ambush = {}

function Ambush.parseGangs(list)
    local set = {}
    for gang in string.gmatch(list or "", "[^,]+") do
        set[gang] = true
    end
    return set
end

function Ambush.hasMetV(n)
    return (n.encounters or 1) > 0 or (n.gigs or 0) > 0 or (n.ambushes or 0) > 0
end

function Ambush.pick(nemeses, districtGangs, metOnly)
    local pool, total = {}, 0
    for _, n in ipairs(nemeses) do
        if n.status ~= "dead" and not n.jailedUntil and n.recordID and n.id and (not metOnly or Ambush.hasMetV(n)) then
            local weight = (n.rank or 1) * (districtGangs[n.gang] and 4 or 1)
            total = total + weight
            table.insert(pool, { n = n, w = weight })
        end
    end
    if total == 0 then return nil end

    local roll = math.random() * total
    for _, entry in ipairs(pool) do
        roll = roll - entry.w
        if roll <= 0 then return entry.n end
    end
    return pool[#pool].n
end

-- Patrullas de la NCPD para las redadas (recordIDs del prevention system del juego).
Ambush.policeRecords = {
    "Character.prevention_police_handgun_wa",
    "Character.prevention_police_rifle_ma",
    "Character.prevention_police_rifle_wa",
    "Character.prevention_police_shotgun_ma",
    "Character.prevention_police_shotgun_wa",
}

-- Policias para la redada: mas cuanto mas alto el rango del Nemesis (3 / 4 / 5).
function Ambush.police(nemesis)
    local ids = {}
    for i = 1, 2 + (nemesis.rank or 1) do
        ids[i] = Ambush.policeRecords[math.random(#Ambush.policeRecords)]
    end
    return table.concat(ids, ",")
end

function Ambush.escorts(nemesis, maxEscorts)
    local byRank = { 1, 2, 4 }
    local count = math.min(maxEscorts or 0, byRank[nemesis.rank or 1] or 1)
    if count <= 0 then return "" end

    local list = Escorts[nemesis.gang]
    local ids = {}
    for i = 1, count do
        if list and #list > 0 then
            ids[i] = list[math.random(#list)]
        else
            ids[i] = nemesis.recordID
        end
    end
    return table.concat(ids, ",")
end

function Ambush.pickFromGang(nemeses, gang)
    local list = {}
    for _, n in ipairs(nemeses) do
        if n.gang == gang then table.insert(list, n) end
    end
    return Ambush.pick(list, {})
end

function Ambush.smsKey(nemesis)
    return "GR-Sms-" .. math.random(6)
end

function Ambush.gigLineKey(nemesis)
    return "GR-Gig-" .. math.random(3)
end

function Ambush.lineKey(nemesis)
    return "GR-Ambush-" .. math.random(6)
end

return Ambush
