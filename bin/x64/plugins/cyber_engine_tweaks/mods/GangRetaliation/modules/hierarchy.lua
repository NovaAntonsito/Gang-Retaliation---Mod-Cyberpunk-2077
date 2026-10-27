-- Gang Retaliation - fase 5: jerarquia de cada banda (Soldado -> Teniente -> Jefe)
--
-- Cada banda tiene 1 Jefe, 2 Tenientes y el resto Soldados. Los Nemesis ganan renombre
-- (escaparse, sobrevivir a emboscadas) y suben de rango:
--   - Ascenso rapido: hay hueco arriba y tiene renombre de sobra.
--   - Vacante: tras unos dias de juego sube el de mas renombre del rango inferior o,
--     si no hay nadie, aparece un Nemesis nuevo directamente en ese rango.
--   - Luchas internas: de vez en cuando alguien desafia a su superior.
-- Todo es logica pura: init.lua le pasa un contexto (ctx) con el dia de juego, ajustes y avisos.

local Traits = require("modules/traits")
local Names = require("modules/names")
local Escorts = require("modules/escorts")

local Hierarchy = {}

Hierarchy.SOLDIER, Hierarchy.LIEUTENANT, Hierarchy.BOSS = 1, 2, 3
-- Plazas por rango (los soldados llenan el resto hasta el maximo por banda).
Hierarchy.cap = { [2] = 2, [3] = 1 }
-- Renombre para el ascenso rapido al rango indicado.
Hierarchy.fastRenown = { [2] = 4, [3] = 8 }

local function alive(n)
    return n.status ~= "dead"
end

function Hierarchy.members(campaign, gang, rank)
    local list = {}
    for _, n in ipairs(campaign.nemeses) do
        if n.gang == gang and alive(n) and (rank == nil or (n.rank or 1) == rank) then
            table.insert(list, n)
        end
    end
    return list
end

-- Bandas con al menos un Nemesis vivo.
function Hierarchy.activeGangs(campaign)
    local gangs, seen = {}, {}
    for _, n in ipairs(campaign.nemeses) do
        if alive(n) and n.gang and not seen[n.gang] then
            seen[n.gang] = true
            table.insert(gangs, n.gang)
        end
    end
    table.sort(gangs)
    return gangs
end

local function gangState(campaign, gang)
    campaign.hierarchy = campaign.hierarchy or {}
    local state = campaign.hierarchy[gang]
    if not state then
        state = { vacant = {} }
        campaign.hierarchy[gang] = state
    end
    state.vacant = state.vacant or {}
    return state
end

-- El de mas renombre (empate: al azar). skip(n) = true para descartar.
local function best(list, ctx, skip)
    local top, topScore = nil, -1
    for _, n in ipairs(list) do
        if not (skip and skip(n)) then
            local score = (n.renown or 0) + ctx.random() * 0.5
            if score > topScore then top, topScore = n, score end
        end
    end
    return top
end

function Hierarchy.addRenown(n, amount)
    n.renown = (n.renown or 0) + amount
end

-- Sube un rango. El nuevo rango trae una fortaleza; el Jefe es siempre "duro" si puede.
function Hierarchy.promote(n, ctx)
    n.rank = math.min(3, (n.rank or 1) + 1)
    n.promotedDay = ctx.day
    if n.rank == Hierarchy.BOSS and not Traits.has(n, "tough") then
        Traits.addKey(n, "tough")
    else
        Traits.grow(n, 4)
    end
end

-- Recluta un Nemesis nuevo directamente en un rango (vacante sin candidatos).
-- Necesita un tipo de NPC de la banda: la lista de escoltas o, si no hay, uno de sus Nemesis.
local function recruit(campaign, gang, rank, ctx)
    local recordID
    local list = Escorts[gang]
    if list and #list > 0 then
        recordID = list[math.floor(ctx.random() * #list) + 1]
    else
        local any = Hierarchy.members(campaign, gang)[1]
        recordID = any and any.recordID
    end
    if not recordID then return nil end

    -- Los registros de mujer acaban en _wa/_wb/_fa...
    local gender = (string.match(recordID, "_[wf][a-z]$") and "Female") or "Male"
    local name, titleEn, titleEs = Names.generate(gang, gender, "promoted")
    local n = ctx.addNemesis({
        name = name, titleEn = titleEn, titleEs = titleEs,
        gang = gang, rank = 1, origin = "promoted", status = "alive",
        encounters = 0, recordID = recordID, gender = gender, health = 100,
        renown = Hierarchy.fastRenown[rank] or 0, created = os.time(), traits = {},
    })
    Traits.ensure(n)
    while (n.rank or 1) < rank do Hierarchy.promote(n, ctx) end
    return n
end

-- Ocupa los huecos de Teniente y Jefe de una banda.
local function fillRanks(campaign, gang, ctx)
    local state = gangState(campaign, gang)
    local settings = ctx.settings
    for rank = 3, 2, -1 do
        local key = tostring(rank)
        local free = Hierarchy.cap[rank] - #Hierarchy.members(campaign, gang, rank)
        if free <= 0 then
            state.vacant[key] = nil
        else
            state.vacant[key] = state.vacant[key] or ctx.day
            local waited = ctx.day - state.vacant[key]
            local below = Hierarchy.members(campaign, gang, rank - 1)
            -- Ascenso rapido: renombre de sobra, sin esperar.
            local candidate = best(below, ctx, function(n) return (n.renown or 0) < Hierarchy.fastRenown[rank] end)
            local reason = "fast"
            if not candidate and waited >= settings.vacancyDays then
                candidate = best(below, ctx)
                reason = "vacancy"
            end
            if candidate and not ctx.isSpawned(candidate.id) then
                Hierarchy.promote(candidate, ctx)
                state.vacant[key] = nil
                ctx.event("promoted", candidate, nil, reason)
            elseif not candidate and waited >= settings.vacancyDays and #below == 0
                and #Hierarchy.members(campaign, gang) < settings.maxPerGang then
                local n = recruit(campaign, gang, rank, ctx)
                state.vacant[key] = nil
                if n then ctx.event("recruited", n) end
            end
        end
    end
end

-- Lucha interna: alguien de rango inferior desafia a un superior.
local function feud(campaign, gang, ctx)
    local state = gangState(campaign, gang)
    local today = math.floor(ctx.day)
    if state.lastFeudDay == today then return end
    state.lastFeudDay = today
    if ctx.random() * 100 >= ctx.settings.feudChancePercent then return end

    -- Desafia el subordinado con mas renombre que tenga a alguien por encima.
    local challenger, target
    for rank = 2, 1, -1 do
        local above = Hierarchy.members(campaign, gang, rank + 1)
        if #above > 0 and not challenger then
            challenger = best(Hierarchy.members(campaign, gang, rank), ctx, function(n) return ctx.isSpawned(n.id) end)
            target = above[math.floor(ctx.random() * #above) + 1]
        end
    end
    if not challenger or not target or ctx.isSpawned(target.id) then return end

    local function score(n) return (n.renown or 0) + (n.rank or 1) * 2 + ctx.random() * 6 end
    local winner, loser = challenger, target
    if score(target) >= score(challenger) then winner, loser = target, challenger end

    local killed = ctx.random() < 0.5
    if winner == challenger then
        -- El retador ocupa el puesto; el superior muere o baja al hueco del retador.
        local targetRank = loser.rank or 1
        if killed then
            loser.status = "dead"
            loser.diedAt = os.time()
            loser.diedBy = "feud"
        else
            loser.rank = math.max(1, targetRank - 1)
        end
        while (winner.rank or 1) < targetRank do Hierarchy.promote(winner, ctx) end
        Hierarchy.addRenown(winner, 2)
        ctx.event(killed and "feudKill" or "feudDemote", winner, loser)
    else
        if killed then
            loser.status = "dead"
            loser.diedAt = os.time()
            loser.diedBy = "feud"
        else
            loser.renown = math.max(0, (loser.renown or 0) - 2)
        end
        Hierarchy.addRenown(winner, 1)
        ctx.event(killed and "feudFailDead" or "feudFail", winner, loser)
    end
end

-- Corrige datos viejos o imposibles: mas Jefes o Tenientes de los que caben.
local function enforceCaps(campaign, gang, ctx)
    for rank = 3, 2, -1 do
        local members = Hierarchy.members(campaign, gang, rank)
        table.sort(members, function(a, b) return (a.renown or 0) > (b.renown or 0) end)
        for i = Hierarchy.cap[rank] + 1, #members do
            members[i].rank = rank - 1
        end
    end
end

-- Paso periodico (init.lua lo llama una vez por minuto).
-- ctx = { day, settings = { vacancyDays, feudChancePercent }, random(), isSpawned(id),
--         addNemesis(data), event(kind, a, b, reason) }
function Hierarchy.update(campaign, ctx)
    for _, gang in ipairs(Hierarchy.activeGangs(campaign)) do
        enforceCaps(campaign, gang, ctx)
        fillRanks(campaign, gang, ctx)
        feud(campaign, gang, ctx)
    end
end

-- V ha matado a un Nemesis: si era Jefe o Teniente, su puesto queda libre desde hoy.
function Hierarchy.onDeath(campaign, n, day)
    if (n.rank or 1) > 1 and n.gang then
        local state = gangState(campaign, n.gang)
        state.vacant[tostring(n.rank)] = state.vacant[tostring(n.rank)] or day
    end
end

return Hierarchy
