local Escorts = require("modules/escorts")

local CyberLooks = {}

CyberLooks.preferred = {
    Maelstrom = {},
}

local function isFemaleRecord(recordID)
    return string.match(recordID or "", "_[wf][a-z]$") ~= nil
end

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

    if #list == 0 then return any end
    return list
end

function CyberLooks.apply(n)
    local list = CyberLooks.candidates(n.gang, n.gender)
    local options = {}
    for _, recordID in ipairs(list) do
        if recordID ~= n.recordID then table.insert(options, recordID) end
    end
    if #options == 0 then options = list end
    if #options == 0 then
        n.appearance = nil
        return false
    end
    n.recordID = options[math.random(#options)]
    n.appearance = nil
    return true
end

return CyberLooks
