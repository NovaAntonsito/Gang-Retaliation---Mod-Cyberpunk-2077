-- Gang Retaliation - rasgos de los Nemesis (eleccion y guardado; redscript los aplica)
-- n.traits = { { key = "fireproof", revealed = false }, ... }

local Traits = {}

Traits.strengths = { "fireproof", "insulated", "toxproof", "brawler", "blastproof", "firewall", "hardhead", "tough", "deadly" }
Traits.weaknesses = { "fear_fire", "weak_shock", "weak_tox", "weak_melee", "weak_blast", "weak_hack", "glass_jaw" }

-- Una fortaleza y una debilidad del mismo grupo se contradicen.
local group = {
    fireproof = "fire", fear_fire = "fire",
    insulated = "shock", weak_shock = "shock",
    toxproof = "tox", weak_tox = "tox",
    brawler = "melee", weak_melee = "melee",
    blastproof = "blast", weak_blast = "blast",
    firewall = "hack", weak_hack = "hack",
    hardhead = "head", glass_jaw = "head",
}

local isWeak = {}
for _, key in ipairs(Traits.weaknesses) do isWeak[key] = true end

function Traits.isWeakness(key)
    return isWeak[key] == true
end

function Traits.has(n, key)
    for _, t in ipairs(n.traits or {}) do
        if t.key == key then return true end
    end
    return false
end

local function conflicts(n, key)
    local g = group[key]
    if not g then return false end
    for _, t in ipairs(n.traits or {}) do
        if group[t.key] == g then return true end
    end
    return false
end

-- Anade un rasgo al azar de la lista que no tenga ni contradiga. Devuelve la clave o nil.
function Traits.add(n, list)
    local options = {}
    for _, key in ipairs(list) do
        if not Traits.has(n, key) and not conflicts(n, key) then table.insert(options, key) end
    end
    if #options == 0 then return nil end
    local key = options[math.random(#options)]
    n.traits = n.traits or {}
    table.insert(n.traits, { key = key, revealed = false })
    return key
end

-- Anade un rasgo concreto si no lo tiene ni lo contradice. Devuelve true si lo anade.
function Traits.addKey(n, key)
    if Traits.has(n, key) or conflicts(n, key) then return false end
    n.traits = n.traits or {}
    table.insert(n.traits, { key = key, revealed = false })
    return true
end

function Traits.countStrengths(n)
    local count = 0
    for _, t in ipairs(n.traits or {}) do
        if not isWeak[t.key] then count = count + 1 end
    end
    return count
end

-- Garantiza los rasgos minimos: 1 debilidad y 1 fortaleza por cada huida (max 3).
-- Tambien sirve para Nemesis creados antes de esta fase.
function Traits.ensure(n)
    if type(n.traits) ~= "table" then n.traits = {} end
    local changed = false
    local hasWeak = false
    for _, t in ipairs(n.traits) do
        if isWeak[t.key] then hasWeak = true end
    end
    if not hasWeak and Traits.add(n, Traits.weaknesses) then changed = true end

    local wanted = math.min(3, 1 + (n.escapes or 0))
    while Traits.countStrengths(n) < wanted do
        if not Traits.add(n, Traits.strengths) then break end
        changed = true
    end
    return changed
end

-- Al volver a escapar gana una fortaleza (max 3; al ascender, max 4). Devuelve la clave nueva o nil.
function Traits.grow(n, max)
    if Traits.countStrengths(n) >= (max or 3) then return nil end
    return Traits.add(n, Traits.strengths)
end

function Traits.csv(n)
    local keys = {}
    for _, t in ipairs(n.traits or {}) do table.insert(keys, t.key) end
    return table.concat(keys, ",")
end

-- Marca un rasgo como descubierto. Devuelve true si no se conocia.
function Traits.reveal(n, key)
    for _, t in ipairs(n.traits or {}) do
        if t.key == key and not t.revealed then
            t.revealed = true
            return true
        end
    end
    return false
end

function Traits.revealAll(n)
    local any = false
    for _, t in ipairs(n.traits or {}) do
        if not t.revealed then
            t.revealed = true
            any = true
        end
    end
    return any
end

-- Nombres separados por comas. nameOf(key) devuelve el texto localizado.
-- weak = true/false filtra por tipo; onlyRevealed oculta los que no se conocen.
function Traits.list(n, nameOf, weak, onlyRevealed)
    local names = {}
    for _, t in ipairs(n.traits or {}) do
        if (isWeak[t.key] == true) == weak and (t.revealed or not onlyRevealed) then
            table.insert(names, nameOf(t.key))
        end
    end
    return table.concat(names, ", ")
end

return Traits
