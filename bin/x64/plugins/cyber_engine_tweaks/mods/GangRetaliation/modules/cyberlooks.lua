-- Gang Retaliation - fase 7: aspecto de un Nemesis que vuelve de la muerte reconstruido con cyberware.
-- Se cambia a otro tipo de NPC de su banda de rango alto (los de nivel 2/3 llevan mas implantes a la vista;
-- en Maelstrom todos). La apariencia concreta la elige el juego al aparecer y CET la guarda (processAppearances).
-- La lista es una primera aproximacion: los que no se vean "cromados" se quitan aqui tras probarlos en el juego.

local Escorts = require("modules/escorts")

local CyberLooks = {}

-- Tipos con mas cyberware visible por banda (vacio = se filtran de los escoltas por nivel).
CyberLooks.preferred = {
    Maelstrom = {},
}

local function isFemaleRecord(recordID)
    return string.match(recordID or "", "_[wf][a-z]$") ~= nil
end

-- Tipos candidatos de la banda para el mismo sexo: primero los preferidos, si no los de nivel 2 o 3.
function CyberLooks.candidates(gang, gender)
    local female = gender == "Female"
    local list = {}
    local source = CyberLooks.preferred[gang]
    if not source or #source == 0 then source = Escorts[gang] or {} end
    local any = {}
    for _, recordID in ipairs(source) do
        if isFemaleRecord(recordID) == female then
            table.insert(any, recordID)
            if gang == "Maelstrom" or string.match(recordID, "[%a]+[23]_") ~= nil then
                table.insert(list, recordID)
            end
        end
    end
    -- Bandas sin tipos de nivel alto en la lista (Barghest): cualquiera del mismo sexo.
    if #list == 0 then return any end
    return list
end

-- Cambia el tipo de NPC por uno con cyberware (distinto del actual si se puede) y borra la apariencia
-- guardada para que el juego le asigne una nueva. Devuelve true si cambio algo.
function CyberLooks.apply(n)
    local list = CyberLooks.candidates(n.gang, n.gender)
    local options = {}
    for _, recordID in ipairs(list) do
        if recordID ~= n.recordID then table.insert(options, recordID) end
    end
    if #options == 0 then options = list end
    if #options == 0 then
        -- Banda sin lista (Voodoo Boys): mismo tipo, apariencia nueva.
        n.appearance = nil
        return false
    end
    n.recordID = options[math.random(#options)]
    n.appearance = nil
    return true
end

return CyberLooks
