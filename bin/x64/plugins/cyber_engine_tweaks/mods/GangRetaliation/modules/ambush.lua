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

Ambush.policeRecords = {
    "Character.prevention_police_handgun_wa",
    "Character.prevention_police_rifle_ma",
    "Character.prevention_police_rifle_wa",
    "Character.prevention_police_shotgun_ma",
    "Character.prevention_police_shotgun_wa",
}

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

-- Casas de V (x, y). Cerca de casa es mas seguro: sin ataques a menos de homeSafe metros
-- (en horizontal, el H10 esta a 120 m de altura) y probabilidad normal a partir de homeFull.
-- El H10 viene de fabrica; el resto se aprende donde V duerme (campaign.homes).
Ambush.builtinHomes = {
    { x = -1381.7, y = 1270.8 }, -- H10, Watson
}
Ambush.homeSafe = 60
Ambush.homeFull = 300
Ambush.homeRadius = 30

local function distance2D(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

function Ambush.allHomes(campaign)
    local list = {}
    for _, home in ipairs(Ambush.builtinHomes) do table.insert(list, home) end
    for _, home in ipairs(campaign.homes or {}) do table.insert(list, home) end
    return list
end

function Ambush.homeFactor(pos, campaign)
    local nearest = math.huge
    for _, home in ipairs(Ambush.allHomes(campaign)) do
        nearest = math.min(nearest, distance2D(pos.x, pos.y, home.x, home.y))
    end
    if nearest <= Ambush.homeSafe then return 0, nearest end
    if nearest >= Ambush.homeFull then return 1, nearest end
    return (nearest - Ambush.homeSafe) / (Ambush.homeFull - Ambush.homeSafe), nearest
end

function Ambush.nearHome(campaign)
    local player = Game.GetPlayer()
    if not player then return false end
    local factor, distance = Ambush.homeFactor(player:GetWorldPosition(), campaign)
    return math.random() > factor, distance
end

-- Un sitio pasa a ser casa tras dormir ahi 2 noches distintas (radio homeRadius). Devuelve true si se agrego.
function Ambush.recordSleep(campaign, x, y, day)
    for _, home in ipairs(Ambush.allHomes(campaign)) do
        if distance2D(x, y, home.x, home.y) < Ambush.homeRadius then return false end
    end
    campaign.sleeps = campaign.sleeps or {}
    for _, sleep in ipairs(campaign.sleeps) do
        if distance2D(x, y, sleep.x, sleep.y) < Ambush.homeRadius and math.floor(day) ~= math.floor(sleep.day) then
            campaign.homes = campaign.homes or {}
            table.insert(campaign.homes, { x = x, y = y })
            local kept = {}
            for _, other in ipairs(campaign.sleeps) do
                if distance2D(x, y, other.x, other.y) >= Ambush.homeRadius then table.insert(kept, other) end
            end
            campaign.sleeps = kept
            return true
        end
    end
    table.insert(campaign.sleeps, { x = x, y = y, day = day })
    while #campaign.sleeps > 20 do table.remove(campaign.sleeps, 1) end
    return false
end

-- Quita la casa aprendida mas cercana a pos (el H10 de fabrica no se puede quitar).
function Ambush.removeNearestHome(campaign, pos)
    local best, bestDistance = nil, math.huge
    for i, home in ipairs(campaign.homes or {}) do
        local d = distance2D(pos.x, pos.y, home.x, home.y)
        if d < bestDistance then best, bestDistance = i, d end
    end
    if not best then return nil end
    table.remove(campaign.homes, best)
    return bestDistance
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
