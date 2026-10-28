-- Gang Retaliation - fase 8: guerras de bandas (simulacion pura; init.lua le pasa el contexto).
--
-- Territorio: cada distrito del juego con bandas (TweakDB) guarda la influencia de cada banda (0-100).
-- Manda la que tiene mas. Una vez por dia de juego:
--   - Las guerras en curso mueven influencia segun la fuerza de cada bando.
--   - Puede empezar una guerra nueva: una banda presente en un distrito ajeno (o la mas fuerte) ataca.
-- Fuerza de una banda: sus Nemesis vivos (Jefe 5, Teniente 3, Soldado 1) + renombre/3,
-- menos 3 por cada Nemesis que V le mato en los ultimos 3 dias (debilitada).
-- campaign.war = { districts = { [clave] = { label, region, inf = { banda = n } } }, order = { claves },
--                  wars = { { district, a, d, start, finish } }, rumors = { { day, kind, a, d, district } },
--                  lastDay }

local War = {}

War.rankWeight = { 1, 3, 5 }
War.weakDays = 3
War.weakPenalty = 3
War.maxWars = 2
War.maxRumors = 8

local function state(campaign)
    campaign.war = campaign.war or {}
    local w = campaign.war
    w.districts = w.districts or {}
    w.order = w.order or {}
    w.wars = w.wars or {}
    w.rumors = w.rumors or {}
    return w
end

-- "Clave|Nombre|Region|BandaA,BandaB;..." (GRWar.GetAllDistricts). known(banda) = la banda existe en el mod.
-- Solo crea los distritos que faltan: el territorio ganado se conserva entre cargas.
function War.init(campaign, list, known)
    local w = state(campaign)
    -- Distritos que ya no estan en la lista del juego (version vieja con zonas): fuera, con sus guerras.
    local valid = {}
    for entry in string.gmatch(list or "", "[^;]+") do
        local key = string.match(entry, "^([^|]*)|")
        if key then valid[key] = true end
    end
    if next(valid) then
        local order = {}
        for _, key in ipairs(w.order) do
            if valid[key] then table.insert(order, key) else w.districts[key] = nil end
        end
        w.order = order
        local wars = {}
        for _, war in ipairs(w.wars) do
            if valid[war.district] then table.insert(wars, war) end
        end
        w.wars = wars
    end
    for entry in string.gmatch(list or "", "[^;]+") do
        local key, label, region, gangs = string.match(entry, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
        if key and not w.districts[key] then
            local present = {}
            for gang in string.gmatch(gangs, "[^,]+") do
                if known(gang) then table.insert(present, gang) end
            end
            if #present > 0 then
                local inf = {}
                if #present == 1 then
                    inf[present[1]] = 100
                else
                    -- La primera banda del distrito es la principal.
                    inf[present[1]] = 60
                    local rest = math.floor(40 / (#present - 1))
                    for i = 2, #present do inf[present[i]] = rest end
                end
                w.districts[key] = { label = label, region = region, inf = inf }
                table.insert(w.order, key)
            end
        end
    end
end

function War.owner(district)
    local best, bestValue = nil, -1
    for gang, value in pairs(district.inf) do
        if value > bestValue or (value == bestValue and gang < best) then best, bestValue = gang, value end
    end
    return best
end

-- Nemesis de la banda muertos a manos de V en los ultimos dias.
function War.recentLosses(campaign, gang, day)
    local count = 0
    for _, n in ipairs(campaign.nemeses) do
        if n.gang == gang and n.status == "dead" and (n.diedBy == nil or n.diedBy == "v") and n.deathDay
            and day - n.deathDay <= War.weakDays then
            count = count + 1
        end
    end
    return count
end

function War.strength(campaign, gang, day)
    local value = 0
    for _, n in ipairs(campaign.nemeses) do
        if n.gang == gang and n.status ~= "dead" then
            value = value + (War.rankWeight[n.rank or 1] or 1) + math.floor((n.renown or 0) / 3)
        end
    end
    value = value - War.recentLosses(campaign, gang, day) * War.weakPenalty
    return math.max(1, value)
end

function War.activeWarAt(campaign, key)
    for _, war in ipairs(state(campaign).wars) do
        if war.district == key then return war end
    end
    return nil
end

-- Bandas con peso en el distrito (para las emboscadas): la que manda y las que tienen 25 o mas.
-- nil si el distrito no esta en el territorio (se usa entonces lo del juego).
function War.districtGangs(campaign, key)
    local district = key and state(campaign).districts[key]
    if not district then return nil end
    local set = {}
    for gang, value in pairs(district.inf) do
        if value >= 25 then set[gang] = true end
    end
    set[War.owner(district)] = true
    return set
end

local function rumor(w, day, kind, a, d, key, ctx)
    table.insert(w.rumors, 1, { day = day, kind = kind, a = a, d = d, district = key })
    while #w.rumors > War.maxRumors do table.remove(w.rumors) end
    ctx.event(kind, a, d, key)
end

-- Ajusta la influencia para que sume 100 (sin bajar de 0).
local function normalize(inf)
    local total = 0
    for gang, value in pairs(inf) do
        inf[gang] = math.max(0, value)
        total = total + inf[gang]
    end
    if total <= 0 then return end
    for gang, value in pairs(inf) do inf[gang] = math.floor(value * 100 / total + 0.5) end
end

local function advanceWars(campaign, w, today, ctx)
    local i = 1
    while i <= #w.wars do
        local war = w.wars[i]
        local district = w.districts[war.district]
        if not district then
            table.remove(w.wars, i)
        else
            local sa, sd = War.strength(campaign, war.a, today), War.strength(campaign, war.d, today)
            -- El atacante gana entre -10 y +20 por dia segun la diferencia de fuerza (mas un poco de azar).
            local shift = 6 + 14 * (sa - sd) / (sa + sd) + (ctx.random() * 6 - 3)
            shift = math.max(-10, math.min(20, shift))
            district.inf[war.a] = (district.inf[war.a] or 0) + shift
            district.inf[war.d] = (district.inf[war.d] or 0) - shift
            normalize(district.inf)
            if today >= war.finish then
                table.remove(w.wars, i)
                if War.owner(district) == war.a then
                    rumor(w, today, "warWon", war.a, war.d, war.district, ctx)
                else
                    rumor(w, today, "warHeld", war.d, war.a, war.district, ctx)
                end
            else
                i = i + 1
            end
        end
    end
end

-- Elige distrito y atacante: una banda presente que no manda, o (a veces) la banda mas fuerte de fuera.
local function startWar(campaign, w, today, ctx, gangs)
    local candidates = {}
    for _, key in ipairs(w.order) do
        local district = w.districts[key]
        if district and not War.activeWarAt(campaign, key) then
            local owner = War.owner(district)
            local best, bestStrength = nil, 0
            for gang, value in pairs(district.inf) do
                if gang ~= owner and value > 0 then
                    local s = War.strength(campaign, gang, today)
                    if s > bestStrength then best, bestStrength = gang, s end
                end
            end
            if best then table.insert(candidates, { key = key, a = best, d = owner }) end
        end
    end
    local pick
    if #candidates > 0 and ctx.random() < 0.75 then
        pick = candidates[math.floor(ctx.random() * #candidates) + 1]
    else
        -- Invasion: la banda mas fuerte ataca un distrito de una mas debil.
        local strongest, top = nil, 0
        for _, gang in ipairs(gangs) do
            local s = War.strength(campaign, gang, today)
            if s > top then strongest, top = gang, s end
        end
        local targets = {}
        for _, key in ipairs(w.order) do
            local district = w.districts[key]
            local owner = district and War.owner(district)
            if owner and owner ~= strongest and not War.activeWarAt(campaign, key)
                and War.strength(campaign, owner, today) < top then
                table.insert(targets, { key = key, a = strongest, d = owner })
            end
        end
        if #targets > 0 then pick = targets[math.floor(ctx.random() * #targets) + 1] end
    end
    if not pick then return end
    w.districts[pick.key].inf[pick.a] = w.districts[pick.key].inf[pick.a] or 0
    table.insert(w.wars, { district = pick.key, a = pick.a, d = pick.d, start = today,
        finish = today + 2 + math.floor(ctx.random() * 3) })
    rumor(w, today, "warStart", pick.a, pick.d, pick.key, ctx)
end

-- Paso periodico: actua una vez por dia de juego.
-- ctx = { day, random(), event(kind, a, d, districtKey), settings = { warChancePercent }, gangs = { ... } }
function War.update(campaign, ctx)
    local w = state(campaign)
    if not next(w.districts) then return end
    local today = math.floor(ctx.day)
    if w.lastDay == nil then
        -- Primera vez: no empieza nada el mismo dia que se crea el territorio.
        w.lastDay = today
        return
    end
    if w.lastDay >= today then return end
    w.lastDay = today
    advanceWars(campaign, w, today, ctx)
    if #w.wars < War.maxWars and ctx.random() * 100 < (ctx.settings.warChancePercent or 30) then
        startWar(campaign, w, today, ctx, ctx.gangs or {})
    end
end

-- Debug: empieza una guerra ya (sin tirada).
function War.forceWar(campaign, ctx)
    local w = state(campaign)
    if #w.wars >= War.maxWars then return false end
    local before = #w.wars
    startWar(campaign, w, math.floor(ctx.day), ctx, ctx.gangs or {})
    return #w.wars > before
end

return War
