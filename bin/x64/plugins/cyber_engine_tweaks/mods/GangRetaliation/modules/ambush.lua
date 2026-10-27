-- Gang Retaliation - eleccion de emboscadas (quien embosca, con cuantos escoltas y que dice)

local Escorts = require("modules/escorts")

local Ambush = {}

-- "TygerClaws,Scavengers" -> { TygerClaws = true, Scavengers = true }
function Ambush.parseGangs(list)
    local set = {}
    for gang in string.gmatch(list or "", "[^,]+") do
        set[gang] = true
    end
    return set
end

-- Ya se ha cruzado con V: se le escapo o aparecio en un gig o emboscada.
function Ambush.hasMetV(n)
    return (n.encounters or 1) > 0 or (n.gigs or 0) > 0 or (n.ambushes or 0) > 0
end

-- Nemesis vivo al azar. Los de la banda del distrito pesan x4 y el rango multiplica.
-- metOnly = solo los que ya conocen a V (los de la cupula inicial no emboscan a un desconocido).
function Ambush.pick(nemeses, districtGangs, metOnly)
    local pool, total = {}, 0
    for _, n in ipairs(nemeses) do
        if n.status ~= "dead" and n.recordID and n.id and (not metOnly or Ambush.hasMetV(n)) then
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

-- Escoltas segun rango (soldado 1, teniente 2, jefe 4), limitado por el ajuste.
-- Devuelve recordIDs separados por comas para redscript.
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

-- Nemesis vivo de una banda concreta (para los gigs); el rango pesa mas.
function Ambush.pickFromGang(nemeses, gang)
    local list = {}
    for _, n in ipairs(nemeses) do
        if n.gang == gang then table.insert(list, n) end
    end
    return Ambush.pick(list, {})
end

-- Clave del SMS de aviso.
function Ambush.smsKey(nemesis)
    return "GR-Sms-" .. math.random(6)
end

-- Clave de la frase al llegar como refuerzo en un gig.
function Ambush.gigLineKey(nemesis)
    return "GR-Gig-" .. math.random(3)
end

-- Clave de la frase de entrada.
function Ambush.lineKey(nemesis)
    return "GR-Ambush-" .. math.random(6)
end

return Ambush
