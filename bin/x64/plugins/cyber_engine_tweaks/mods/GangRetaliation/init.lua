-- Gang Retaliation - capa CET (persistencia JSON, nombres y ventana de debug)

local Store = require("modules/store")
local Names = require("modules/names")
local Ambush = require("modules/ambush")
local Traits = require("modules/traits")
local Hierarchy = require("modules/hierarchy")

local GR = {
    overlayOpen = false,
    campaignId = 0,
    sessionToken = 0,
    saveTimer = 0,
    lastAction = "",
    -- Avisos en cola: el juego solo muestra uno a la vez.
    messages = {},
    messageTimer = 0,
    -- Emboscada anunciada por SMS: { id, due, giveUp } en tiempo de juego (segundos).
    pendingAmbush = nil,
    -- Gigs ya tirados en esta sesion ("gigId/banda" -> true): una tirada por gig y banda.
    gigRolled = {},
    -- Nemesis de la emboscada o gig en curso: si sigue vivo al acabar, gana renombre.
    encounterId = nil,
    -- Debug: dias de juego extra para probar la jerarquia sin esperar.
    dayOffset = 0,
}

-- Sistemas de redscript (nil si el juego aun no ha cargado una partida).
local function getSystem(name)
    local container = Game.GetScriptableSystemsContainer()
    if not container then return nil end
    return container:Get(name)
end

local function text(key, fallback)
    local sys = getSystem("GangRetaliation.GRSystem")
    if sys then
        local value = sys:GetText(key)
        if value and value ~= "" and value ~= key then return value end
    end
    return fallback or key
end

local function lang()
    return text("GR-Lang", "en")
end

local function getSettings()
    return getSystem("GangRetaliation.GRSettings")
end

local function getDetection()
    return getSystem("GangRetaliation.GRDetection")
end

local function debugLog(msg)
    local settings = getSettings()
    if settings and settings.debugLog then
        print("[GangRetaliation] " .. msg)
    end
end

local function notify(msg)
    table.insert(GR.messages, msg)
    print("[GangRetaliation] " .. msg)
end

-- Muestra el siguiente aviso de la cola cada 3,5 s.
local function flushMessages(delta)
    GR.messageTimer = GR.messageTimer - delta
    if GR.messageTimer > 0 or #GR.messages == 0 then return end
    local det = getDetection()
    if not det then return end
    det:Notify(table.remove(GR.messages, 1))
    GR.messageTimer = 3.5
end

local function traitName(key)
    return text("GR-Trait-" .. key, key)
end

local function rankLabel(rank, gender)
    if rank == 3 and gender == "Female" then return text("GR-RankBossF", "Boss") end
    if rank == 3 then return text("GR-RankBoss", "Boss") end
    if rank == 2 then return text("GR-RankLieutenant", "Lieutenant") end
    return text("GR-RankSoldier", "Soldier")
end

local function getSpawner()
    return getSystem("GangRetaliation.GRSpawner")
end

local function findNemesis(id)
    for _, n in ipairs(Store.campaign(GR.campaignId).nemeses) do
        if n.id == id then return n end
    end
    return nil
end

local function labelOf(n)
    return Names.display(n, lang()) .. " (" .. Names.gangLabel(n.gang) .. ")"
end

-- Nombre con rango para el escaner y las frases: Teniente Kenji Mori "el Rencoroso".
local function fullName(n)
    if (n.rank or 1) <= 1 then return Names.display(n, lang()) end
    return rankLabel(n.rank, n.gender) .. " " .. Names.display(n, lang())
end

-- Dia de juego (con decimales) + el adelanto de debug.
local function gameDay()
    local spawner = getSystem("GangRetaliation.GRSpawner")
    return (spawner and spawner:GetGameDay() or 0) + GR.dayOffset
end

-- Pasa los rasgos a redscript antes de generar al Nemesis.
local function pushTraits(n)
    if Traits.ensure(n) then Store.dirty = true end
    local sys = getSystem("GangRetaliation.GRTraits")
    if sys then sys:SetTraits(n.id, Traits.csv(n)) end
end

-- Un Nemesis que ya existia vuelve a escapar.
local function updateNemesis(evt)
    local n = findNemesis(evt.nemesisId)
    if not n then return end
    n.encounters = (n.encounters or 1) + 1
    n.health = evt.health
    n.pos = { x = evt.posX, y = evt.posY, z = evt.posZ }

    n.escapes = (n.escapes or 0) + 1
    Hierarchy.addRenown(n, 2)
    Traits.ensure(n)
    Traits.grow(n)
    notify(string.format(text("GR-MsgAgainEscaped", "%s escaped you again. They are getting stronger."), labelOf(n)))
    Store.dirty = true
    Store.save()
end

-- Convierte un evento de redscript en un Nemesis guardado.
local function createNemesis(evt)
    if evt.nemesisId and evt.nemesisId > 0 then
        updateNemesis(evt)
        return
    end

    local gang = evt.gang
    local settings = getSettings()
    local maxPerGang = settings and settings.maxPerGang or 8

    if Store.countAlive(GR.campaignId, gang) >= maxPerGang then
        debugLog(string.format(text("GR-MsgGangFull", "%s already has its maximum of Nemeses."), Names.gangLabel(gang)))
        return
    end

    local name, titleEn, titleEs = Names.generate(gang, evt.gender, evt.origin)
    local nemesis = Store.addNemesis(GR.campaignId, {
        name = name,
        titleEn = titleEn,
        titleEs = titleEs,
        gang = gang,
        rank = 1,
        origin = evt.origin,
        status = "alive",
        encounters = 1,
        recordID = evt.recordID,
        appearance = evt.appearance,
        gender = evt.gender,
        health = evt.health,
        pos = { x = evt.posX, y = evt.posY, z = evt.posZ },
        created = os.time(),
        traits = {},
    })
    Traits.ensure(nemesis)
    Store.save()

    local label = Names.display(nemesis, lang()) .. " (" .. Names.gangLabel(gang) .. ")"
    if evt.origin == "fled" then
        notify(string.format(text("GR-MsgFled", "%s ran away. They will come back for you."), label))
    else
        notify(string.format(text("GR-MsgEscaped", "%s got away wounded. They will remember you."), label))
    end
end

local function processPending()
    local det = getDetection()
    if not det then return end
    local count = det:GetPendingCount()
    if count == 0 then return end

    for i = 0, count - 1 do
        local evt = det:GetPending(i)
        if evt then
            local ok, err = pcall(createNemesis, evt)
            if not ok then print("[GangRetaliation] Error creando Nemesis: " .. tostring(err)) end
        end
    end
    det:ClearPending()
end

-- Nemesis generados por el mod que han muerto.
local function processDeaths()
    local spawner = getSpawner()
    if not spawner then return end
    local count = spawner:GetDeathCount()
    if count == 0 then return end

    for i = 0, count - 1 do
        local n = findNemesis(spawner:GetDeath(i))
        if n and n.status ~= "dead" then
            n.status = "dead"
            n.diedAt = os.time()
            Store.dirty = true
            notify(string.format(text("GR-MsgNemesisDead", "%s is dead... for now."), labelOf(n)))
            Hierarchy.onDeath(Store.ensureCampaign(GR.campaignId), n, gameDay())
            if (n.rank or 1) == Hierarchy.BOSS then
                notify(string.format(text("GR-MsgBossDown", "The %s lost their boss. Someone will want the throne..."), Names.gangLabel(n.gang)))
            end
        end
    end
    spawner:ClearDeaths()
    Store.save()
end

-- Genera la emboscada ya. Devuelve un texto con el resultado para la ventana de debug.
local function launchAmbush(n)
    local settings = getSettings()
    local spawner = getSpawner()
    if not settings or not spawner then return "no systems" end

    local speaker = fullName(n)
    local line = text(Ambush.lineKey(n), "...")
    local escorts = Ambush.escorts(n, settings.ambushMaxEscorts)
    pushTraits(n)
    if not spawner:StartAmbush(n.id, n.recordID, n.appearance or "", escorts, line, speaker) then
        return "spawn failed"
    end

    n.ambushes = (n.ambushes or 0) + 1
    GR.encounterId = n.id
    Store.dirty = true
    notify(string.format(text("GR-MsgAmbush", "Ambush! %s found you."), labelOf(n)))
    return "ambush #" .. n.id
end

-- Intenta lanzar una emboscada. force = ignorar espera y probabilidad (debug).
-- warnSeconds = segundos entre el SMS y el ataque (nil = el ajuste; 0 = sin SMS).
-- Devuelve un texto con el resultado para la ventana de debug.
local function tryAmbush(force, warnSeconds)
    local settings = getSettings()
    local spawner = getSpawner()
    if not settings or not spawner then return "no systems" end
    if not settings.enabled or (not force and not settings.ambushEnabled) then return "disabled" end
    if GR.pendingAmbush then return "sms sent, waiting" end

    local campaign = Store.campaign(GR.campaignId)
    if not force then
        local waited = os.time() - (campaign.lastAmbush or 0)
        if waited < settings.ambushCooldownMinutes * 60 then return "cooldown" end
        if math.random(100) > settings.ambushChancePercent then return "roll failed" end
    end

    local blocker = spawner:GetAmbushBlocker()
    if blocker ~= "" then return "blocked: " .. blocker end

    local districtGangs = Ambush.parseGangs(spawner:GetDistrictGangs())
    local n = Ambush.pick(campaign.nemeses, districtGangs)
    if not n then return "no living Nemesis" end

    Store.ensureCampaign(GR.campaignId).lastAmbush = os.time()
    Store.dirty = true

    local delay = warnSeconds or settings.ambushSmsSeconds or 0
    local phone = getSystem("GangRetaliation.GRPhone")
    if delay <= 0 or not phone or not phone:SendThreat(Names.display(n, lang()), text(Ambush.smsKey(n), "...")) then
        return launchAmbush(n)
    end
    local now = spawner:GetTime()
    -- Si a la hora no se puede (combate, coche...), espera hasta 5 min mas y luego desiste.
    GR.pendingAmbush = { id = n.id, due = now + delay, giveUp = now + delay + 300 }
    return "sms #" .. n.id .. ", ambush in " .. delay .. " s"
end

-- Lanza la emboscada anunciada cuando pasa el tiempo del SMS.
local function updatePendingAmbush()
    local pending = GR.pendingAmbush
    local spawner = getSpawner()
    if not pending or not spawner then return end

    local now = spawner:GetTime()
    if now < pending.due then return end

    local n = findNemesis(pending.id)
    if not n or n.status == "dead" then
        GR.pendingAmbush = nil
        return
    end
    local blocker = spawner:GetAmbushBlocker()
    -- "spawn failed" = no hay sitio alcanzable cerca de V: se reintenta como si estuviera bloqueada.
    local result = blocker == "" and launchAmbush(n) or ("blocked: " .. blocker)
    if result ~= "spawn failed" and blocker == "" then
        GR.pendingAmbush = nil
        debugLog("Emboscada anunciada: " .. result)
    elseif now > pending.giveUp then
        GR.pendingAmbush = nil
        debugLog("Emboscada anunciada cancelada: " .. blocker)
    end
end

-- Gig: si V pelea contra la banda de un Nemesis vivo, este puede llegar como refuerzo.
-- force = sin gig ni tirada (debug). Devuelve un texto con el resultado, o nil si no hay nada que contar.
local function tryGig(force)
    local settings = getSettings()
    local spawner = getSpawner()
    local det = getDetection()
    if not settings or not spawner or not det then return "no systems" end
    if not settings.enabled or (not force and not settings.gigEnabled) then return nil end

    local gigId = spawner:GetActiveGigId()
    if gigId == "" and not force then return nil end
    local blocker = spawner:GetReinforcementBlocker()
    if blocker ~= "" then return force and ("blocked: " .. blocker) or nil end

    local campaign = Store.campaign(GR.campaignId)
    for gang in pairs(Ambush.parseGangs(det:GetFightGangs())) do
        local key = gigId .. "/" .. gang
        if force or not GR.gigRolled[key] then
            GR.gigRolled[key] = true
            local n = Ambush.pickFromGang(campaign.nemeses, gang)
            local roll = math.random(100)
            if n and (force or roll <= settings.gigChancePercent) then
                local speaker = fullName(n)
                local line = text(Ambush.gigLineKey(n), "...")
                local escorts = Ambush.escorts(n, math.min(1, settings.ambushMaxEscorts))
                pushTraits(n)
                if not spawner:StartReinforcement(n.id, n.recordID, n.appearance or "", escorts, line, speaker) then
                    return "spawn failed"
                end
                n.gigs = (n.gigs or 0) + 1
                GR.encounterId = n.id
                Store.dirty = true
                notify(string.format(text("GR-MsgGig", "%s heard you were coming and brought backup!"), labelOf(n)))
                return "gig reinforcement #" .. n.id
            end
            debugLog(string.format("Gig %s / %s: %s", gigId, gang, n and ("tirada " .. roll .. " fallida") or "sin Nemesis vivo"))
        end
    end
    return force and "no Nemesis for this fight" or nil
end

-- Los Nemesis sin apariencia fija (reclutados) se quedan con la cara con la que aparecen.
local function processAppearances()
    local spawner = getSpawner()
    if not spawner or spawner:GetAppearanceReportCount() == 0 then return end
    for i = 0, spawner:GetAppearanceReportCount() - 1 do
        local id, appearance = string.match(spawner:GetAppearanceReport(i) or "", "^(%d+):(.+)$")
        local n = id and findNemesis(tonumber(id))
        if n and (not n.appearance or n.appearance == "" or n.appearance == "random") and appearance ~= "None" then
            n.appearance = appearance
            Store.dirty = true
        end
    end
    spawner:ClearAppearanceReports()
end

-- Sobrevivir a una emboscada o gig (V no lo mato) da renombre.
local function checkEncounter()
    local spawner = getSpawner()
    if not GR.encounterId or not spawner or spawner:IsAmbushActive() then return end
    local n = findNemesis(GR.encounterId)
    GR.encounterId = nil
    if n and n.status ~= "dead" then
        Hierarchy.addRenown(n, 1)
        n.survived = (n.survived or 0) + 1
        Store.dirty = true
        debugLog(Names.display(n, lang()) .. " sobrevive al encuentro: renombre " .. n.renown)
    end
end

-- Avisos de la jerarquia (ascensos, reclutas y rumores de luchas internas).
local function hierarchyEvent(kind, a, b)
    local gang = Names.gangLabel(a.gang)
    local nameA = Names.display(a, lang())
    local nameB = b and Names.display(b, lang()) or ""
    local rankA = rankLabel(a.rank, a.gender)
    if kind == "promoted" then
        notify(string.format(text("GR-MsgPromoted", "%s rose to %s of the %s."), nameA, rankA, gang))
    elseif kind == "recruited" then
        notify(string.format(text("GR-MsgRecruited", "New face in the %s: %s, %s."), gang, nameA, rankA))
    elseif kind == "feudKill" then
        notify(string.format(text("GR-MsgFeudKill", "Rumor: %s killed %s and is now %s of the %s."), nameA, nameB, rankA, gang))
    elseif kind == "feudDemote" then
        notify(string.format(text("GR-MsgFeudDemote", "Rumor: %s overthrew %s and is now %s of the %s."), nameA, nameB, rankA, gang))
    elseif kind == "feudFail" then
        notify(string.format(text("GR-MsgFeudFail", "Rumor: %s put %s in their place."), nameA, nameB))
    elseif kind == "feudFailDead" then
        -- a = el superior que gana, b = el retador que muere.
        notify(string.format(text("GR-MsgFeudFailDead", "Rumor: %s challenged %s and paid with their life."), nameB, nameA))
    end
    Store.dirty = true
end

-- Paso de la jerarquia. feudChance = forzar la probabilidad de lucha interna (debug).
local function updateHierarchy(feudChance)
    local settings = getSettings()
    local spawner = getSpawner()
    if not settings or not spawner or not settings.enabled then return end
    local campaign = Store.campaign(GR.campaignId)
    if #campaign.nemeses == 0 then return end

    Hierarchy.update(Store.ensureCampaign(GR.campaignId), {
        day = gameDay(),
        settings = {
            vacancyDays = settings.vacancyDays,
            feudChancePercent = feudChance or settings.feudChancePercent,
            maxPerGang = settings.maxPerGang,
        },
        random = math.random,
        isSpawned = function(id) return spawner:IsNemesisSpawned(id) end,
        addNemesis = function(data) return Store.addNemesis(GR.campaignId, data) end,
        event = hierarchyEvent,
    })
end

-- Datos para la ventana de Nemesis del menu (Menu.reds): textos ya traducidos.
-- Los rasgos sin descubrir salen como "???" para que escanear siga teniendo sentido.
local function pushMenu()
    local sys = getSystem("GangRetaliation.GRMenuData")
    if not sys then return end
    sys:Clear()

    local list = {}
    for _, n in ipairs(Store.campaign(GR.campaignId).nemeses) do
        if n.gang then table.insert(list, n) end
    end
    table.sort(list, function(a, b)
        if a.gang ~= b.gang then return Names.gangLabel(a.gang) < Names.gangLabel(b.gang) end
        return (a.renown or 0) > (b.renown or 0)
    end)

    local l = lang()
    for _, n in ipairs(list) do
        local parts = {}
        for _, t in ipairs(n.traits or {}) do
            if t.revealed then
                table.insert(parts, (Traits.isWeakness(t.key) and "- " or "+ ") .. traitName(t.key))
            else
                table.insert(parts, "???")
            end
        end
        -- Dos rasgos por linea para que quepan en la tarjeta.
        local lines = {}
        for i = 1, #parts, 2 do
            table.insert(lines, parts[i] .. (parts[i + 1] and ("    " .. parts[i + 1]) or ""))
        end
        local traits = table.concat(lines, "\n")
        local stats = string.format(text("GR-MenuStats", "Encounters %d  |  Renown %d  |  Ambushes %d"),
            n.encounters or 1, n.renown or 0, n.ambushes or 0)
        if n.status == "dead" then
            stats = stats .. "  |  " .. (n.diedBy == "feud" and text("GR-MenuDiedFeud", "Killed by their own gang") or text("GR-MenuDiedV", "Killed by V"))
        end
        sys:Add(n.gang, Names.gangLabel(n.gang), n.rank or 1, n.status == "dead", Names.display(n, l), traits, stats)
    end
end

-- Rasgos descubiertos en combate o al escanear.
local function processReveals()
    local sys = getSystem("GangRetaliation.GRTraits")
    if not sys then return end
    local count = sys:GetRevealCount()
    if count == 0 then return end

    for i = 0, count - 1 do
        local id, what = string.match(sys:GetReveal(i) or "", "^(%d+):(.+)$")
        local n = id and findNemesis(tonumber(id))
        if n then
            if what == "scan" then
                if Traits.revealAll(n) then
                    local none = text("GR-UiNone", "none")
                    local strong = Traits.list(n, traitName, false, true)
                    local weak = Traits.list(n, traitName, true, true)
                    notify(string.format(text("GR-MsgScan", "%s - Strengths: %s. Weaknesses: %s."), Names.display(n, lang()), strong ~= "" and strong or none, weak ~= "" and weak or none))
                end
            elseif Traits.reveal(n, what) then
                local key = Traits.isWeakness(what) and "GR-MsgTraitWeak" or "GR-MsgTraitStrong"
                local fallback = Traits.isWeakness(what) and "Weakness found - %s: %s" or "Strength found - %s: %s"
                notify(string.format(text(key, fallback), Names.display(n, lang()), traitName(what)))
            end
            Store.dirty = true
        end
    end
    sys:ClearReveals()
end

-- Detecta cambios de partida: cada save tiene su campaignId.
local function refreshCampaign()
    if not Game.GetPlayer() then
        GR.campaignId = 0
        return
    end
    local sys = getSystem("GangRetaliation.GRSystem")
    if not sys then return end

    local id = sys:GetCampaignId()
    local token = sys:GetSessionToken()
    if id ~= 0 and (id ~= GR.campaignId or token ~= GR.sessionToken) then
        GR.campaignId = id
        GR.sessionToken = token
        GR.pendingAmbush = nil
        GR.gigRolled = {}
        GR.encounterId = nil
        debugLog("Campana activa: " .. tostring(id))
    end
end

registerForEvent("onInit", function()
    math.randomseed(os.time())
    Store.load()

    print("[GangRetaliation] CET cargado")
end)

registerForEvent("onShutdown", function()
    if Store.dirty then Store.save() end
end)

registerForEvent("onUpdate", function(delta)
    refreshCampaign()
    if GR.campaignId == 0 then return end

    -- Una vez por segundo: comprobar si los que huyen han escapado.
    GR.fleeTimer = (GR.fleeTimer or 0) + delta
    if GR.fleeTimer >= 1 then
        GR.fleeTimer = 0
        local det = getDetection()
        if det then det:UpdateFleeing() end
        local speech = getSystem("GangRetaliation.GRSpeech")
        if speech then speech:Tick() end
        local spawner = getSpawner()
        if spawner then spawner:Tick() end
        pcall(updatePendingAmbush)
        GR.menuTimer = (GR.menuTimer or 0) + 1
        if GR.menuTimer >= 2 then
            GR.menuTimer = 0
            local okM, errM = pcall(pushMenu)
            if not okM then print("[GangRetaliation] Error en datos del menu: " .. tostring(errM)) end
        end
        local ok, result = pcall(tryGig, false)
        if result then debugLog("Gig: " .. tostring(result)) end
    end

    -- Una vez por minuto: tirada de emboscada.
    GR.ambushTimer = (GR.ambushTimer or 0) + delta
    if GR.ambushTimer >= 60 then
        GR.ambushTimer = 0
        local ok, result = pcall(tryAmbush, false)
        debugLog("Emboscada: " .. tostring(result))
        local okH, errH = pcall(updateHierarchy)
        if not okH then print("[GangRetaliation] Error en jerarquia: " .. tostring(errH)) end
    end

    processPending()
    processDeaths()
    checkEncounter()
    processAppearances()
    processReveals()
    flushMessages(delta)

    -- Guardado agrupado: como mucho una escritura cada 5 s.
    if Store.dirty then
        GR.saveTimer = GR.saveTimer + delta
        if GR.saveTimer >= 5 then
            GR.saveTimer = 0
            Store.save()
        end
    end
end)

registerForEvent("onOverlayOpen", function() GR.overlayOpen = true end)
registerForEvent("onOverlayClose", function() GR.overlayOpen = false end)

registerForEvent("onDraw", function()
    if not GR.overlayOpen then return end

    if ImGui.Begin("Gang Retaliation (dev)") then
        if GR.campaignId == 0 then
            ImGui.Text(text("GR-UiWaiting", "Waiting for a loaded save..."))
        else
            local campaign = Store.campaign(GR.campaignId)
            local l = lang()
            ImGui.Text(text("GR-UiCampaign", "Campaign") .. ": " .. tostring(GR.campaignId))
            ImGui.Text(text("GR-UiNemeses", "Nemeses") .. ": " .. tostring(#campaign.nemeses))

            local det = getDetection()
            if det then
                ImGui.Text(text("GR-UiCandidates", "Wounded gangers in this fight") .. ": " .. tostring(det:GetCandidateCount()))
            end
            local sp = getSpawner()
            if sp then
                ImGui.TextDisabled(string.format("%s [%s]  ambush: %s", sp:GetDistrictName(), sp:GetDistrictGangs(), sp:IsAmbushActive() and "ACTIVE" or (sp:GetAmbushBlocker() ~= "" and sp:GetAmbushBlocker() or "ready")))
                if GR.pendingAmbush then
                    ImGui.TextDisabled(string.format("SMS #%d: ambush in %.0f s", GR.pendingAmbush.id, GR.pendingAmbush.due - sp:GetTime()))
                end
                local gigId = sp:GetActiveGigId()
                ImGui.TextDisabled(string.format("gig: %s  fight: [%s]", gigId ~= "" and (sp:GetActiveGigTitle() .. " (" .. gigId .. ")") or "-", det and det:GetFightGangs() or ""))
            end

            local settings = getSettings()
            if settings then
                ImGui.Separator()
                ImGui.Text(string.format("enabled=%s  maxPerGang=%d  debugLog=%s", tostring(settings.enabled), settings.maxPerGang, tostring(settings.debugLog)))
                ImGui.Text(string.format("escapeHealth=%d%%  fleeHealth=%d%%", settings.escapeHealthPercent, settings.fleeHealthPercent))
            end

            ImGui.Separator()
            if #campaign.nemeses == 0 then
                ImGui.Text(text("GR-UiNoData", "No Nemeses yet."))
            end
            local spawner = getSpawner()
            for _, n in ipairs(campaign.nemeses) do
                local dead = n.status == "dead"
                ImGui.Text(string.format("#%d %s%s", n.id or 0, Names.display(n, l), dead and (" [" .. text("GR-UiDead", "dead") .. "]") or ""))
                ImGui.Text(string.format("    %s - %s - %s - %.0f%% - x%d - ren %d", Names.gangLabel(n.gang), rankLabel(n.rank, n.gender), n.origin or "?", n.health or 0, n.encounters or 1, n.renown or 0))
                if n.recordID then
                    if n.traits and #n.traits > 0 then
                        local parts = {}
                        for _, t in ipairs(n.traits) do
                            table.insert(parts, (Traits.isWeakness(t.key) and "-" or "+") .. traitName(t.key) .. (t.revealed and "" or " (?)"))
                        end
                        ImGui.TextWrapped("    " .. table.concat(parts, ", "))
                    end
                    ImGui.TextDisabled("    " .. tostring(n.recordID) .. " / " .. tostring(n.appearance))
                    if spawner and not dead and n.id then
                        ImGui.SameLine()
                        if ImGui.SmallButton(text("GR-UiSpawn", "Spawn") .. "##" .. tostring(n.id)) then
                            pushTraits(n)
                            local ok = spawner:SpawnNearPlayer(n.id, n.recordID, n.appearance or "", 8.0, fullName(n))
                            GR.lastAction = ok and ("Spawn #" .. n.id) or "Spawn: no disponible / not available"
                        end
                        ImGui.SameLine()
                        if ImGui.SmallButton(text("GR-UiMarkDead", "Mark dead") .. "##dead" .. tostring(n.id)) then
                            n.status = "dead"
                            n.diedAt = os.time()
                            Store.save()
                        end
                    end
                end
            end

            ImGui.Separator()
            if ImGui.Button(text("GR-UiPromoteTarget", "Debug: make target a Nemesis")) then
                local det2 = getDetection()
                if det2 then
                    GR.lastAction = det2:DebugPromoteLookAt() and "OK" or "No valido / not valid"
                end
            end
            ImGui.SameLine()
            if ImGui.Button(text("GR-UiFleeTarget", "Debug: make target flee")) then
                local det3 = getDetection()
                if det3 then
                    GR.lastAction = det3:DebugFleeLookAt() and "Flee OK" or "No valido / not valid"
                end
            end
            local det4 = getDetection()
            if det4 then
                local mode = det4:GetFleeMode()
                ImGui.Text("Flee mode:")
                for _, opt in ipairs({ { 0, "A: run" }, { 1, "B: fear" }, { 2, "C: both" } }) do
                    ImGui.SameLine()
                    if ImGui.RadioButton(opt[2], mode == opt[1]) then det4:SetFleeMode(opt[1]) end
                end
            end
            if ImGui.Button(text("GR-UiForceAmbush", "Debug: ambush now")) then
                local ok, result = pcall(tryAmbush, true)
                GR.lastAction = tostring(result)
            end
            ImGui.SameLine()
            if ImGui.Button(text("GR-UiSmsAmbush", "Debug: SMS + ambush in 15 s")) then
                local ok, result = pcall(tryAmbush, true, 15)
                GR.lastAction = tostring(result)
            end
            if ImGui.Button("Debug: gig reinforcement now") then
                local ok, result = pcall(tryGig, true)
                GR.lastAction = tostring(result)
            end
            ImGui.SameLine()
            if ImGui.Button("Hide lines") then
                local speech = getSystem("GangRetaliation.GRSpeech")
                if speech then speech:HideAll() end
            end
            ImGui.SameLine()
            if ImGui.Button(text("GR-UiDespawnAll", "Despawn all")) then
                local sp = getSpawner()
                if sp then sp:DespawnAll() end
            end
            ImGui.TextDisabled(string.format("game day %.2f (+%d debug)", gameDay(), GR.dayOffset))
            if ImGui.Button("Debug: +1 game day") then
                GR.dayOffset = GR.dayOffset + 1
                local ok, err = pcall(updateHierarchy)
                GR.lastAction = ok and "+1 day" or tostring(err)
            end
            ImGui.SameLine()
            if ImGui.Button("Debug: force feud") then
                for _, state in pairs(Store.ensureCampaign(GR.campaignId).hierarchy or {}) do state.lastFeudDay = nil end
                local ok, err = pcall(updateHierarchy, 100)
                GR.lastAction = ok and "feud" or tostring(err)
            end
            if ImGui.Button("Save now") then Store.save() end
            ImGui.SameLine()
            if ImGui.Button("Clear campaign") then Store.clearCampaign(GR.campaignId) end
            if GR.lastAction ~= "" then ImGui.TextDisabled(GR.lastAction) end
        end
    end
    ImGui.End()
end)

return GR
