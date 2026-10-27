// Gang Retaliation - fase 2: reaparicion de Nemesis y emboscadas (Codeware DynamicEntitySystem)
// Patrones de colocacion y hostilidad copiados de Dark Future (DFRandomEncounterSystem).
// CET decide cuando y quien embosca; aqui se comprueba si es seguro, se genera y se limpia.

module GangRetaliation

public class GRSpawner extends ScriptableSystem {
    private let m_entityIDs: array<EntityID>;
    // 0 = escolta (pandillero normal), >0 = id del Nemesis.
    private let m_nemesisIDs: array<Int32>;
    // Frase que dice al aparecer ("" = ninguna).
    private let m_lines: array<String>;
    // Nombre del Nemesis ("" = escolta): se usa en las frases y en el escaner.
    private let m_speakers: array<String>;
    // Icono sobre la cabeza del Nemesis.
    private let m_mappins: array<NewMappinID>;
    private let m_hasMappin: array<Bool>;
    // Nemesis muertos pendientes de leer por CET.
    private let m_deaths: array<Int32>;
    // Apariencia real con la que aparece cada Nemesis ("id:apariencia"), para que CET la guarde.
    private let m_appearanceReports: array<String>;

    // Emboscada en curso.
    private let m_ambushActive: Bool;
    private let m_ambushStart: Float;
    private let m_ambushSawCombat: Bool;
    private let m_ambushCalmSince: Float;

    // Resultado de FindReachableSpot.
    private let m_spotFound: Bool;

    public static func Get(gi: GameInstance) -> ref<GRSpawner> {
        return GameInstance.GetScriptableSystemsContainer(gi).Get(n"GangRetaliation.GRSpawner") as GRSpawner;
    }

    private func OnAttach() {
        GameInstance.GetDynamicEntitySystem().RegisterListener(n"GangRetaliation", this, n"OnEntityEvent");
    }

    private func OnDetach() {
        GameInstance.GetDynamicEntitySystem().UnregisterListener(n"GangRetaliation", this, n"OnEntityEvent");
    }

    private func Now() -> Float {
        return EngineTime.ToFloat(GameInstance.GetSimTime(this.GetGameInstance()));
    }

    // Dia del calendario del juego, con decimales (la jerarquia cuenta las vacantes en dias).
    public func GetGameDay() -> Float {
        return GameInstance.GetTimeSystem(this.GetGameInstance()).GetGameTimeStamp() / 86400.0;
    }

    // Tiempo de juego en segundos (se para con la pausa). CET lo usa para el aviso por SMS.
    public func GetTime() -> Float {
        return this.Now();
    }

    private func IndexOf(id: EntityID) -> Int32 {
        let i: Int32 = 0;
        while i < ArraySize(this.m_entityIDs) {
            if this.m_entityIDs[i] == id {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    // 0 si la entidad no es un Nemesis generado por el mod.
    public func GetNemesisId(id: EntityID) -> Int32 {
        let index: Int32 = this.IndexOf(id);
        return index >= 0 ? this.m_nemesisIDs[index] : 0;
    }

    public func IsNemesisSpawned(nemesisId: Int32) -> Bool {
        for id in this.m_nemesisIDs {
            if id == nemesisId {
                return true;
            }
        }
        return false;
    }

    // -------------------------------------------------------------------------
    // Colocacion
    // -------------------------------------------------------------------------
    private func GetDirection(player: ref<PlayerPuppet>, angle: Float) -> Vector4 {
        return Vector4.RotateAxis(player.GetWorldForward(), Vector4(0.0, 0.0, 1.0, 0.0), angle / 180.0 * Pi());
    }

    // Punto en el suelo navegable a "distance" metros de V, girado "angle" grados desde donde mira.
    private func GetGroundPosition(player: ref<PlayerPuppet>, angle: Float, distance: Float) -> Vector4 {
        let raw: Vector4 = player.GetWorldPosition() + this.GetDirection(player, angle) * distance;
        return GameInstance.GetNavigationSystem(this.GetGameInstance()).GetNearestNavmeshPointBelowOnlyHumanNavmesh(raw, 1.0, 5);
    }

    // Punto desde el que se puede llegar a pie hasta V: suelo navegable, altura parecida
    // y una ruta sin rodeos enormes (evita muros, azoteas y zonas fuera del mapa).
    private func IsReachable(player: ref<PlayerPuppet>, pos: Vector4, distance: Float) -> Bool {
        let target: Vector4 = player.GetWorldPosition();
        if Vector4.IsZero(pos) || AbsF(pos.Z - target.Z) > 4.0 {
            return false;
        }
        let path: ref<NavigationPath> = GameInstance.GetNavigationSystem(this.GetGameInstance()).CalculatePathOnlyHumanNavmesh(pos, target, NavGenAgentSize.Human, 1.0);
        if !IsDefined(path) || ArraySize(path.path) < 2 {
            return false;
        }
        // La ruta tiene que acabar junto a V y no ser mucho mas larga que la linea recta.
        let last: Vector4 = path.path[ArraySize(path.path) - 1];
        return Vector4.Distance(last, target) < 3.0 && path.CalculateLength() < distance * 2.5 + 10.0;
    }

    // Busca un punto alcanzable cerca del angulo y la distancia pedidos: prueba angulos
    // cada vez mas abiertos y luego mas cerca de V. Deja m_spotFound en false si no hay ninguno.
    private func FindReachableSpot(player: ref<PlayerPuppet>, angle: Float, distance: Float) -> Vector4 {
        let offsets: array<Float> = [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0, 120.0, -120.0];
        let scales: array<Float> = [1.0, 0.7, 0.45];
        for scale in scales {
            for offset in offsets {
                let pos: Vector4 = this.GetGroundPosition(player, angle + offset, distance * scale);
                if this.IsReachable(player, pos, distance * scale) {
                    this.m_spotFound = true;
                    return pos;
                }
            }
        }
        this.m_spotFound = false;
        return player.GetWorldPosition();
    }

    // Orientado hacia V.
    private func GetFacingPlayer(player: ref<PlayerPuppet>, from: Vector4) -> Quaternion {
        return EulerAngles.ToQuat(Vector4.ToRotation(player.GetWorldPosition() - from));
    }

    private func SpawnAt(nemesisId: Int32, recordID: String, appearance: String, position: Vector4, orientation: Quaternion, line: String, speaker: String) -> Bool {
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if !IsDefined(des) || !des.IsReady() {
            return false;
        }
        let spec: ref<DynamicEntitySpec> = new DynamicEntitySpec();
        spec.recordID = TDBID.Create(recordID);
        spec.appearanceName = StrLen(appearance) > 0 ? StringToName(appearance) : n"random";
        spec.position = position;
        spec.orientation = orientation;
        spec.persistState = false;
        spec.persistSpawn = false;
        spec.alwaysSpawned = false;
        spec.spawnInView = true;
        spec.active = true;
        ArrayPush(spec.tags, n"GangRetaliation");

        let entityID: EntityID = des.CreateEntity(spec);
        ArrayPush(this.m_entityIDs, entityID);
        ArrayPush(this.m_nemesisIDs, nemesisId);
        ArrayPush(this.m_lines, line);
        ArrayPush(this.m_speakers, speaker);
        let noMappin: NewMappinID;
        ArrayPush(this.m_mappins, noMappin);
        ArrayPush(this.m_hasMappin, false);
        return true;
    }

    // Nombre del Nemesis para el escaner ("" si no es un Nemesis del mod).
    public func GetNemesisName(id: EntityID) -> String {
        let index: Int32 = this.IndexOf(id);
        if index < 0 || this.m_nemesisIDs[index] <= 0 {
            return "";
        }
        return this.m_speakers[index];
    }

    private func AddMappin(index: Int32, npc: ref<GameObject>) {
        let data: MappinData;
        data.mappinType = t"Mappins.DefaultStaticMappin";
        data.variant = gamedataMappinVariant.HuntForPsychoVariant;
        data.active = true;
        data.visibleThroughWalls = true;
        this.m_mappins[index] = GameInstance.GetMappinSystem(this.GetGameInstance()).RegisterMappinWithObject(data, npc, n"poi_mappin", new Vector3(0.0, 0.0, 2.2));
        this.m_hasMappin[index] = true;
    }

    private func RemoveMappin(index: Int32) {
        if this.m_hasMappin[index] {
            GameInstance.GetMappinSystem(this.GetGameInstance()).UnregisterMappin(this.m_mappins[index]);
            this.m_hasMappin[index] = false;
        }
    }

    // Registra la muerte de un Nemesis (una sola vez). Lo llaman el evento de
    // DynamicEntitySystem, el hook de muerte de NPC y la limpieza de la emboscada.
    public func MarkDead(id: EntityID) {
        let index: Int32 = this.IndexOf(id);
        if index < 0 {
            return;
        }
        this.RemoveMappin(index);
        let nemesisId: Int32 = this.m_nemesisIDs[index];
        if nemesisId > 0 {
            ArrayPush(this.m_deaths, nemesisId);
            // Deja de contar como Nemesis: ni rasgos ni segunda muerte.
            this.m_nemesisIDs[index] = 0;
            GRLog("Nemesis #" + IntToString(nemesisId) + " muerto");
        }
    }

    // Muertos o derribados que el juego no ha notificado.
    private func CheckNeutralized() {
        let i: Int32 = ArraySize(this.m_entityIDs) - 1;
        while i >= 0 {
            if this.m_nemesisIDs[i] > 0 {
                let npc: ref<ScriptedPuppet> = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_entityIDs[i]) as ScriptedPuppet;
                if IsDefined(npc) && (npc.IsDead() || ScriptedPuppet.IsDefeated(npc) || ScriptedPuppet.IsUnconscious(npc)) {
                    this.MarkDead(this.m_entityIDs[i]);
                }
            }
            i -= 1;
        }
    }

    // Frases de poca vida (del Nemesis o de V).
    private func CheckTaunts() {
        let taunts: ref<GRTaunts> = GRTaunts.Get(this.GetGameInstance());
        if !IsDefined(taunts) {
            return;
        }
        let i: Int32 = 0;
        while i < ArraySize(this.m_entityIDs) {
            if this.m_nemesisIDs[i] > 0 {
                let npc: ref<ScriptedPuppet> = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_entityIDs[i]) as ScriptedPuppet;
                if IsDefined(npc) && !GRDetection.IsNeutralized(npc) {
                    taunts.CheckHealth(npc);
                }
            }
            i += 1;
        }
    }

    // Debug: genera al Nemesis delante de V.
    public func SpawnNearPlayer(nemesisId: Int32, recordID: String, appearance: String, distance: Float, name: String) -> Bool {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) || this.IsNemesisSpawned(nemesisId) {
            return false;
        }
        let pos: Vector4 = this.FindReachableSpot(player, 0.0, distance);
        if !this.m_spotFound {
            return false;
        }
        let ok: Bool = this.SpawnAt(nemesisId, recordID, appearance, pos, this.GetFacingPlayer(player, pos), "", name);
        if ok {
            GRLog("Generando Nemesis #" + IntToString(nemesisId) + " (" + recordID + ")");
        }
        return ok;
    }

    // -------------------------------------------------------------------------
    // Emboscadas
    // -------------------------------------------------------------------------
    // Motivo por el que no se puede emboscar ahora ("" = se puede).
    public func GetAmbushBlocker() -> String {
        let blocker: String = this.GetSpawnBlocker();
        if StrLen(blocker) > 0 {
            return blocker;
        }
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if player.IsInCombat() {
            return "in combat";
        }
        if StatusEffectSystem.ObjectHasStatusEffectWithTag(player, n"NoCombat") {
            return "no-combat zone";
        }
        return "";
    }

    // Lo que impide generar a cualquier grupo (emboscada o refuerzo).
    private func GetSpawnBlocker() -> String {
        let gi: GameInstance = this.GetGameInstance();
        let player: ref<PlayerPuppet> = GetPlayer(gi);
        if !IsDefined(player) || player.IsDead() {
            return "no player";
        }
        if this.m_ambushActive {
            return "ambush active";
        }
        if !GameInstance.GetDynamicEntitySystem().IsReady() {
            return "entity system not ready";
        }
        if VehicleComponent.IsMountedToVehicle(gi, player) {
            return "in vehicle";
        }
        return "";
    }

    // Refuerzo en un gig: solo en pleno combate.
    public func GetReinforcementBlocker() -> String {
        let blocker: String = this.GetSpawnBlocker();
        if StrLen(blocker) > 0 {
            return blocker;
        }
        if !GetPlayer(this.GetGameInstance()).IsInCombat() {
            return "not in combat";
        }
        return "";
    }

    // Id del gig (encargo de fixer) que V lleva seguido, o "" si lo seguido no es un gig.
    public func GetActiveGigId() -> String {
        let quest: wref<JournalQuest> = this.GetTrackedQuest();
        if !IsDefined(quest) || NotEquals(quest.GetType(), gameJournalQuestType.Contract) {
            return "";
        }
        return quest.GetId();
    }

    public func GetActiveGigTitle() -> String {
        let quest: wref<JournalQuest> = this.GetTrackedQuest();
        if !IsDefined(quest) {
            return "";
        }
        return quest.GetTitle(GameInstance.GetJournalManager(this.GetGameInstance()));
    }

    // Lo seguido es un objetivo: se sube por fase hasta la mision.
    private func GetTrackedQuest() -> wref<JournalQuest> {
        let journal: ref<JournalManager> = GameInstance.GetJournalManager(this.GetGameInstance());
        let entry: wref<JournalEntry> = journal.GetTrackedEntry();
        let depth: Int32 = 0;
        while IsDefined(entry) && depth < 6 {
            let quest: wref<JournalQuest> = entry as JournalQuest;
            if IsDefined(quest) {
                return quest;
            }
            entry = journal.GetParentEntry(entry);
            depth += 1;
        }
        return null;
    }

    // Bandas que controlan el distrito actual, separadas por comas (p. ej. "TygerClaws,Scavengers").
    public func GetDistrictGangs() -> String {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return "";
        }
        let district: wref<District_Record> = player.GetPreventionSystem().GetCurrentDistrict().GetDistrictRecord();
        let result: String = "";
        // Si el distrito no tiene bandas, se sube al distrito padre (igual que Dark Future).
        while IsDefined(district) && StrLen(result) == 0 {
            if district.GetGangsCount() > 0 {
                let gangs: array<wref<Affiliation_Record>>;
                district.Gangs(gangs);
                for gang in gangs {
                    result += (StrLen(result) > 0 ? "," : "") + NameToString(gang.EnumName());
                }
            }
            district = district.ParentDistrict();
        }
        return result;
    }

    public func GetDistrictName() -> String {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return "";
        }
        let district: wref<District_Record> = player.GetPreventionSystem().GetCurrentDistrict().GetDistrictRecord();
        return IsDefined(district) ? district.EnumName() : "";
    }

    // Genera al Nemesis a la espalda de V y a sus escoltas alrededor.
    // escortRecords: recordIDs separados por comas (uno por escolta).
    public func StartAmbush(nemesisId: Int32, recordID: String, appearance: String, escortRecords: String, line: String, speaker: String) -> Bool {
        if StrLen(this.GetAmbushBlocker()) > 0 || this.IsNemesisSpawned(nemesisId) {
            return false;
        }
        if !this.SpawnGroup(nemesisId, recordID, appearance, escortRecords, line, speaker, 25.0) {
            return false;
        }
        this.m_ambushSawCombat = false;
        GRLog("Emboscada: Nemesis #" + IntToString(nemesisId));
        return true;
    }

    // Gig: el Nemesis llega como refuerzo en mitad del combate. Se limpia igual que una emboscada.
    public func StartReinforcement(nemesisId: Int32, recordID: String, appearance: String, escortRecords: String, line: String, speaker: String) -> Bool {
        if StrLen(this.GetReinforcementBlocker()) > 0 || this.IsNemesisSpawned(nemesisId) {
            return false;
        }
        if !this.SpawnGroup(nemesisId, recordID, appearance, escortRecords, line, speaker, 20.0) {
            return false;
        }
        this.m_ambushSawCombat = true;
        GRLog("Refuerzo en gig: Nemesis #" + IntToString(nemesisId));
        return true;
    }

    private func SpawnGroup(nemesisId: Int32, recordID: String, appearance: String, escortRecords: String, line: String, speaker: String, distance: Float) -> Bool {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());

        // Nemesis detras de V (entre 150 y 210 grados), en un punto desde el que pueda llegar a V.
        let angle: Float = RandRangeF(150.0, 210.0);
        let pos: Vector4 = this.FindReachableSpot(player, angle, distance);
        if !this.m_spotFound {
            GRLog("Sin punto alcanzable cerca de V: no se genera");
            return false;
        }
        if !this.SpawnAt(nemesisId, recordID, appearance, pos, this.GetFacingPlayer(player, pos), line, speaker) {
            return false;
        }
        // Escoltas repartidos a los lados del Nemesis, con apariencia aleatoria.
        let escorts: array<String>;
        if StrLen(escortRecords) > 0 {
            escorts = StrSplit(escortRecords, ",");
        }
        let i: Int32 = 0;
        while i < ArraySize(escorts) {
            let offset: Float = (i % 2 == 0 ? 1.0 : -1.0) * (20.0 + 15.0 * Cast<Float>(i / 2));
            let escortPos: Vector4 = this.FindReachableSpot(player, angle + offset, distance + RandRangeF(-5.0, 3.0));
            if this.m_spotFound {
                this.SpawnAt(0, escorts[i], "", escortPos, this.GetFacingPlayer(player, escortPos), "", "");
            }
            i += 1;
        }

        this.m_ambushActive = true;
        this.m_ambushStart = this.Now();
        this.m_ambushCalmSince = 0.0;
        GRLog(IntToString(ArraySize(escorts)) + " escoltas");
        return true;
    }

    public func IsAmbushActive() -> Bool {
        return this.m_ambushActive;
    }

    // Lo llama CET cada segundo: limpia la emboscada cuando ha terminado.
    public func Tick() {
        this.CheckNeutralized();
        this.CheckTaunts();
        if !this.m_ambushActive {
            return;
        }
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return;
        }
        let now: Float = this.Now();
        if player.IsInCombat() {
            this.m_ambushSawCombat = true;
            this.m_ambushCalmSince = 0.0;
            return;
        }
        if this.m_ambushCalmSince == 0.0 {
            this.m_ambushCalmSince = now;
        }
        // Tras el combate: 20 s de calma. Si nunca hubo combate (V no los vio): 3 minutos.
        let calm: Float = now - this.m_ambushCalmSince;
        if (this.m_ambushSawCombat && calm > 20.0) || now - this.m_ambushStart > 180.0 {
            GRLog("Fin de emboscada: limpiando");
            this.CheckNeutralized();
            this.DespawnAll();
        }
    }

    public func DespawnAll() {
        let i: Int32 = 0;
        while i < ArraySize(this.m_entityIDs) {
            this.RemoveMappin(i);
            i += 1;
        }
        GameInstance.GetDynamicEntitySystem().DeleteTagged(n"GangRetaliation");
        let taunts: ref<GRTaunts> = GRTaunts.Get(this.GetGameInstance());
        if IsDefined(taunts) {
            taunts.Reset();
        }
        ArrayClear(this.m_entityIDs);
        ArrayClear(this.m_nemesisIDs);
        ArrayClear(this.m_lines);
        ArrayClear(this.m_speakers);
        ArrayClear(this.m_mappins);
        ArrayClear(this.m_hasMappin);
        this.m_ambushActive = false;
    }

    public func GetSpawnedCount() -> Int32 {
        return ArraySize(this.m_entityIDs);
    }

    private cb func OnEntityEvent(event: ref<DynamicEntityEvent>) {
        let index: Int32 = this.IndexOf(event.GetEntityID());
        if index < 0 {
            return;
        }
        let eventType: DynamicEntityEventType = event.GetEventType();

        if Equals(eventType, DynamicEntityEventType.Spawned) {
            let npc: ref<ScriptedPuppet> = GameInstance.GetDynamicEntitySystem().GetEntity(event.GetEntityID()) as ScriptedPuppet;
            let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
            if IsDefined(npc) && IsDefined(player) {
                npc.GetAttitudeAgent().SetAttitudeTowards(player.GetAttitudeAgent(), EAIAttitude.AIA_Hostile);
                StimBroadcasterComponent.SendStimDirectly(player, gamedataStimType.CombatHit, npc);
                if StrLen(this.m_lines[index]) > 0 {
                    GRSpeech.Say(npc, this.m_speakers[index], this.m_lines[index], 5.0);
                }
                if this.m_nemesisIDs[index] > 0 && !this.m_hasMappin[index] {
                    this.AddMappin(index, npc);
                    ArrayPush(this.m_appearanceReports, IntToString(this.m_nemesisIDs[index]) + ":" + NameToString(npc.GetCurrentAppearanceName()));
                }
            }
        }

        if Equals(eventType, DynamicEntityEventType.Dead) {
            this.MarkDead(event.GetEntityID());
        }

        if Equals(eventType, DynamicEntityEventType.Deleted) {
            this.RemoveMappin(index);
            ArrayErase(this.m_entityIDs, index);
            ArrayErase(this.m_nemesisIDs, index);
            ArrayErase(this.m_lines, index);
            ArrayErase(this.m_speakers, index);
            ArrayErase(this.m_mappins, index);
            ArrayErase(this.m_hasMappin, index);
        }
    }

    // API para CET
    public func GetDeathCount() -> Int32 {
        return ArraySize(this.m_deaths);
    }

    public func GetDeath(index: Int32) -> Int32 {
        return this.m_deaths[index];
    }

    public func ClearDeaths() {
        ArrayClear(this.m_deaths);
    }

    public func GetAppearanceReportCount() -> Int32 {
        return ArraySize(this.m_appearanceReports);
    }

    public func GetAppearanceReport(index: Int32) -> String {
        return this.m_appearanceReports[index];
    }

    public func ClearAppearanceReports() {
        ArrayClear(this.m_appearanceReports);
    }
}

// -----------------------------------------------------------------------------
// Escaner: muestra el nombre del Nemesis en lugar del generico
// -----------------------------------------------------------------------------
@wrapMethod(NPCPuppet)
protected func CompileScannerChunks() -> Bool {
    let result: Bool = wrappedMethod();
    let spawner: ref<GRSpawner> = GRSpawner.Get(this.GetGame());
    if IsDefined(spawner) {
        let name: String = spawner.GetNemesisName(this.GetEntityID());
        if StrLen(name) > 0 {
            let nameChunk: ref<ScannerName> = new ScannerName();
            nameChunk.Set(name);
            let scanner: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGame()).Get(GetAllBlackboardDefs().UI_ScannerModules);
            scanner.SetVariant(GetAllBlackboardDefs().UI_ScannerModules.ScannerName, ToVariant(nameChunk), true);
        }
    }
    return result;
}
