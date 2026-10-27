-- Gang Retaliation - generador de nombres y titulos de Nemesis
-- Cada banda tiene su estilo. Los titulos se guardan en ES y EN para que el
-- Nemesis conserve el mismo apodo aunque se cambie el idioma del juego.

local Names = {}

Names.gangLabels = {
    Maelstrom = "Maelstrom",
    TygerClaws = "Tyger Claws",
    Valentinos = "Valentinos",
    SixthStreet = "6th Street",
    Animals = "Animals",
    VoodooBoys = "Voodoo Boys",
    Wraiths = "Wraiths",
    Scavengers = "Scavs",
    Barghest = "Barghest",
}

-- style: "full" = nombre + apellido, "handle" = solo alias callejero
local pools = {
    Maelstrom = {
        style = "handle",
        handles = { "Static", "Gristle", "Socket", "Torque", "Scrap", "Hex", "Volt", "Rust", "Grinder", "Patch", "Glitch", "Rivet", "Servo", "Cathode", "Ferrum", "Null" },
    },
    TygerClaws = {
        style = "full",
        male = { "Kenji", "Hiro", "Daisuke", "Ryo", "Takeshi", "Akira", "Jin", "Shun", "Kaito", "Wei" },
        female = { "Mei", "Yuki", "Aiko", "Rin", "Hana", "Sakura", "Lian", "Emi" },
        last = { "Mori", "Tanaka", "Ono", "Sato", "Kato", "Ito", "Nakamura", "Kobayashi", "Watanabe", "Hayashi" },
    },
    Valentinos = {
        style = "full",
        male = { "Javier", "Mateo", "Diego", "Luis", "Rafael", "Esteban", "Paco", "Joaquín", "Ramón", "Héctor" },
        female = { "Rosa", "Carmen", "Lupe", "Marisol", "Ximena", "Paloma", "Inés", "Dolores" },
        last = { "Ortega", "Navarro", "Morales", "Reyes", "Castillo", "Vargas", "Delgado", "Fuentes", "Ibarra", "Salazar" },
    },
    SixthStreet = {
        style = "full",
        male = { "Hank", "Cole", "Travis", "Wade", "Jesse", "Dale", "Buck", "Clint", "Earl", "Rusty" },
        female = { "Carla", "Dottie", "Jolene", "Tammy", "Reba", "Darla", "Wanda", "Lacey" },
        last = { "Dawson", "Brennan", "Hart", "Miller", "Boyd", "Tucker", "Hayes", "Colt", "Pruitt", "Rhodes" },
    },
    Animals = {
        style = "handle",
        handles = { "Tank", "Bruiser", "Ox", "Mauler", "Bull", "Grizzly", "Rhino", "Boar", "Bison", "Gorilla", "Brick", "Hammerhead", "Moose", "Mastiff" },
    },
    VoodooBoys = {
        style = "full",
        male = { "Marcel", "Toussaint", "Lucien", "Emmanuel", "Gérard", "Fritz", "Ti-Jean", "Wilner" },
        female = { "Celestine", "Fabienne", "Marie-Ange", "Yolande", "Nadège", "Odette" },
        last = { "Duval", "Joseph", "Pierre", "Laurent", "Baptiste", "Dorvil", "Saint-Fleur", "Désir" },
    },
    Wraiths = {
        style = "handle",
        handles = { "Dust", "Vulture", "Ash", "Coyote", "Grit", "Rattler", "Buzzard", "Cinder", "Hollow", "Drifter", "Bonesaw", "Mirage" },
    },
    Scavengers = {
        style = "full",
        male = { "Dmitri", "Yuri", "Oleg", "Pavel", "Sergei", "Boris", "Anatoly", "Grigori" },
        female = { "Olga", "Irina", "Katya", "Svetlana", "Nadia", "Vera" },
        last = { "Volkov", "Sokolov", "Petrov", "Morozov", "Kuznetsov", "Lebedev", "Orlov", "Zaitsev" },
    },
    Barghest = {
        style = "full",
        male = { "Kurt", "Malik", "Rhys", "Tariq", "Viktor", "Dario", "Emeka", "Hassan" },
        female = { "Nadia", "Leyla", "Ingrid", "Amara", "Zara", "Freya" },
        last = { "Hale", "Osei", "Calder", "Brandt", "Haddad", "Kovač", "Mensah", "Ruiz" },
    },
}

-- Titulos segun el origen. es_f = forma femenina en espanol cuando cambia.
local titles = {
    escaped = {
        { en = "the Survivor", es = "el Superviviente", es_f = "la Superviviente" },
        { en = "Scarface", es = "Caracortada" },
        { en = "the Runner", es = "el Fugitivo", es_f = "la Fugitiva" },
        { en = "the Unkillable", es = "el Inmortal", es_f = "la Inmortal" },
        { en = "Lucky", es = "el Suertudo", es_f = "la Suertuda" },
        { en = "Patchwork", es = "el Remendado", es_f = "la Remendada" },
        { en = "the Rat", es = "la Rata" },
        { en = "Half-Dead", es = "Medio Muerto", es_f = "Medio Muerta" },
        { en = "the Grudge", es = "el Rencoroso", es_f = "la Rencorosa" },
    },
}
titles.fled = {
    { en = "the Coward", es = "el Cobarde", es_f = "la Cobarde" },
    { en = "the Hare", es = "la Liebre" },
    { en = "Quickfeet", es = "Pies Ligeros" },
    { en = "the Deserter", es = "el Desertor", es_f = "la Desertora" },
    { en = "the Ghost", es = "el Fantasma" },
    { en = "Runaway", es = "el Prófugo", es_f = "la Prófuga" },
}
titles.debug = titles.escaped
-- Reclutados por la jerarquia para cubrir un puesto vacante.
titles.promoted = {
    { en = "the Heir", es = "el Heredero", es_f = "la Heredera" },
    { en = "the Usurper", es = "el Usurpador", es_f = "la Usurpadora" },
    { en = "Iron Fist", es = "Puño de Hierro" },
    { en = "the Climber", es = "el Trepa", es_f = "la Trepa" },
    { en = "the New Blood", es = "Sangre Nueva" },
    { en = "the Enforcer", es = "el Ejecutor", es_f = "la Ejecutora" },
}

local function pick(list)
    return list[math.random(#list)]
end

local function isFemale(gender)
    return gender == "Female"
end

function Names.generate(gang, gender, origin)
    local pool = pools[gang] or pools.Maelstrom
    local name
    if pool.style == "handle" then
        name = pick(pool.handles)
    else
        local first = isFemale(gender) and pick(pool.female) or pick(pool.male)
        name = first .. " " .. pick(pool.last)
    end

    local title = pick(titles[origin] or titles.escaped)
    local titleEs = title.es
    if isFemale(gender) and title.es_f then titleEs = title.es_f end

    return name, title.en, titleEs
end

-- Nombre completo para mostrar: Static "the Survivor" / Static "el Superviviente"
function Names.display(nemesis, lang)
    local title = (lang == "es") and nemesis.titleEs or nemesis.titleEn
    if not title or title == "" then return nemesis.name or "?" end
    return string.format('%s "%s"', nemesis.name or "?", title)
end

function Names.gangLabel(gang)
    return Names.gangLabels[gang] or gang or "?"
end

return Names
