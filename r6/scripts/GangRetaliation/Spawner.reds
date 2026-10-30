module GangRetaliation

public class GRSpawner extends ScriptableSystem {
    private let m_entityIDs: array<EntityID>;

    private let m_nemesisIDs: array<Int32>;

    private let m_lines: array<String>;

    private let m_speakers: array<String>;

    private let m_mappins: array<NewMappinID>;
    private let m_hasMappin: array<Bool>;

    private let m_sides: array<Int32>;
    private let m_spawnSide: Int32;
    private let m_raidMode: Bool;
    private let m_raidHitGang: Bool;
    private let m_raidHitPolice: Bool;
    private let m_raidOutcome: String;
    private let m_raidHeat: Int32;
    private let m_policeImmune: Bool;
    private let m_immuneRaidEnd: Float;
    private let m_raidPoliceOnV: Bool;

    private let m_deaths: array<Int32>;
    private let m_deathKinds: array<String>;

    private let m_finisherIds: array<Int32>;

    private let m_lastHitIds: array<Int32>;
    private let m_lastHitBy: array<String>;
    private let m_deathCauses: array<String>;

    private let m_appearanceReports: array<String>;

    private let m_ambushActive: Bool;
    private let m_ambushStart: Float;
    private let m_ambushSawCombat: Bool;
    private let m_ambushCalmSince: Float;
    private let m_stuckChecked: Bool;

    private let m_spawnPositions: array<Vector4>;

    // Emboscada en vehiculo: 0 = a pie, 1 = esperando que carguen, 2 = montados, 3 = conduciendo, 4 = bajados.
    private let m_vehicleID: EntityID;
    private let m_vehicleState: Int32;
    private let m_vehicleStateTime: Float;

    private let m_spotFound: Bool;
    // Por que fallo la ultima busqueda de sitio (para el log): alcanzable, cielo abierto, despejado, a la vista.
    private let m_spotFails: array<Int32>;

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

    public func GetGameDay() -> Float {
        return GameInstance.GetTimeSystem(this.GetGameInstance()).GetGameTimeStamp() / 86400.0;
    }

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

    private func GetDirection(player: ref<PlayerPuppet>, angle: Float) -> Vector4 {
        return Vector4.RotateAxis(player.GetWorldForward(), Vector4(0.0, 0.0, 1.0, 0.0), angle / 180.0 * Pi());
    }

    private func GetGroundPosition(player: ref<PlayerPuppet>, angle: Float, distance: Float) -> Vector4 {
        let raw: Vector4 = player.GetWorldPosition() + this.GetDirection(player, angle) * distance;
        return GameInstance.GetNavigationSystem(this.GetGameInstance()).GetNearestNavmeshPointBelowOnlyHumanNavmesh(raw, 1.0, 5);
    }

    private func IsReachable(player: ref<PlayerPuppet>, pos: Vector4, distance: Float) -> Bool {
        let target: Vector4 = player.GetWorldPosition();
        // Poca diferencia de altura y camino corto: en edificios de varios pisos evita puntos de otro
        // piso o detras de paredes (habitaciones cerradas del megaedificio).
        if Vector4.IsZero(pos) || AbsF(pos.Z - target.Z) > 2.0 {
            return false;
        }
        let path: ref<NavigationPath> = GameInstance.GetNavigationSystem(this.GetGameInstance()).CalculatePathOnlyHumanNavmesh(pos, target, NavGenAgentSize.Human, 1.0);
        if !IsDefined(path) || ArraySize(path.path) < 2 {
            return false;
        }

        let last: Vector4 = path.path[ArraySize(path.path) - 1];
        return Vector4.Distance(last, target) < 3.0 && path.CalculateLength() < distance * 1.8 + 5.0;
    }

    // Punto metido en una pared: rayos cortos a la altura del pecho chocan en casi todas las direcciones.
    private func IsClearSpot(pos: Vector4) -> Bool {
        let spatial: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(this.GetGameInstance());
        let chest: Vector4 = pos + new Vector4(0.0, 0.0, 1.2, 0.0);
        let dirs: array<Vector4> = [new Vector4(0.6, 0.0, 0.0, 0.0), new Vector4(-0.6, 0.0, 0.0, 0.0), new Vector4(0.0, 0.6, 0.0, 0.0), new Vector4(0.0, -0.6, 0.0, 0.0)];
        let hits: Int32 = 0;
        for dir in dirs {
            let result: TraceResult;
            if spatial.SyncRaycastByCollisionGroup(chest, chest + dir, n"Static", result, true, false) {
                hits += 1;
            }
        }
        return hits < 3;
    }

    // Solo a cielo abierto: en un megaedificio o un interior el piso de arriba tapa el cielo. Si V esta bajo
    // techo no hay punto valido y la emboscada anunciada espera a que salga a la calle.
    private func IsOpenSky(pos: Vector4) -> Bool {
        let result: TraceResult;
        return !GameInstance.GetSpatialQueriesSystem(this.GetGameInstance()).SyncRaycastByCollisionGroup(pos + new Vector4(0.0, 0.0, 2.0, 0.0), pos + new Vector4(0.0, 0.0, 40.0, 0.0), n"Static", result, true, false);
    }

    // Los dos puntos se conectan a pie (los dos bandos de una redada pueden llegar a pelear).
    private func IsConnected(from: Vector4, to: Vector4) -> Bool {
        let path: ref<NavigationPath> = GameInstance.GetNavigationSystem(this.GetGameInstance()).CalculatePathOnlyHumanNavmesh(from, to, NavGenAgentSize.Human, 1.0);
        if !IsDefined(path) || ArraySize(path.path) < 2 {
            return false;
        }
        let last: Vector4 = path.path[ArraySize(path.path) - 1];
        return Vector4.Distance(last, to) < 3.0 && path.CalculateLength() < Vector4.Distance(from, to) * 2.0 + 10.0;
    }

    // V ve el punto: ninguna pared entre sus ojos y el pecho del NPC.
    private func HasLineOfSight(player: ref<PlayerPuppet>, pos: Vector4) -> Bool {
        let result: TraceResult;
        let eyes: Vector4 = player.GetWorldPosition() + new Vector4(0.0, 0.0, 1.7, 0.0);
        return !GameInstance.GetSpatialQueriesSystem(this.GetGameInstance()).SyncRaycastByCollisionGroup(eyes, pos + new Vector4(0.0, 0.0, 1.5, 0.0), n"Static", result, true, false);
    }

    private func FindReachableSpot(player: ref<PlayerPuppet>, angle: Float, distance: Float) -> Vector4 {
        return this.FindSpot(player, angle, distance, 120.0, 0.45, false);
    }

    // Busca un punto a 'distance' en la direccion 'angle' (0 = delante de V), desviandose como mucho
    // maxOffset grados y acercandose como mucho hasta distance * minScale. hidden: fuera de la vista de V.
    private func FindSpot(player: ref<PlayerPuppet>, angle: Float, distance: Float, maxOffset: Float, minScale: Float, hidden: Bool) -> Vector4 {
        let offsets: array<Float> = [0.0, 15.0, -15.0, 30.0, -30.0, 45.0, -45.0, 60.0, -60.0, 80.0, -80.0, 120.0, -120.0];
        let scales: array<Float> = [1.0, 0.85, 0.7, 0.45];
        this.m_spotFails = [0, 0, 0, 0];
        for scale in scales {
            if scale >= minScale {
                for offset in offsets {
                    if AbsF(offset) <= maxOffset {
                        let pos: Vector4 = this.GetGroundPosition(player, angle + offset, distance * scale);
                        if !this.IsReachable(player, pos, distance * scale) {
                            this.m_spotFails[0] += 1;
                        } else {
                            if !this.IsOpenSky(pos) {
                                this.m_spotFails[1] += 1;
                            } else {
                                if !this.IsClearSpot(pos) {
                                    this.m_spotFails[2] += 1;
                                } else {
                                    if hidden && this.HasLineOfSight(player, pos) {
                                        this.m_spotFails[3] += 1;
                                    } else {
                                        this.m_spotFound = true;
                                        return pos;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        this.m_spotFound = false;
        return player.GetWorldPosition();
    }

    // Escolta junto al lider (el grupo llega junto), ajustada al navmesh; si no hay sitio, en el del lider.
    private func EscortSpot(leader: Vector4, index: Int32) -> Vector4 {
        let angle: Float = Cast<Float>(index) * 2.4 + RandRangeF(-0.4, 0.4);
        let radius: Float = RandRangeF(2.5, 5.0);
        let raw: Vector4 = leader + new Vector4(CosF(angle) * radius, SinF(angle) * radius, 1.0, 0.0);
        let pos: Vector4 = GameInstance.GetNavigationSystem(this.GetGameInstance()).GetNearestNavmeshPointBelowOnlyHumanNavmesh(raw, 1.0, 5);
        if Vector4.IsZero(pos) || AbsF(pos.Z - leader.Z) > 1.5 || !this.IsClearSpot(pos) {
            return leader;
        }
        return pos;
    }

    public func FindWarSpot(angle: Float, distance: Float) -> Vector4 {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return Vector4.EmptyVector();
        }
        let pos: Vector4 = this.FindReachableSpot(player, angle, distance);
        return this.m_spotFound ? pos : Vector4.EmptyVector();
    }

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
        ArrayPush(this.m_spawnPositions, position);
        ArrayPush(this.m_nemesisIDs, nemesisId);
        ArrayPush(this.m_lines, line);
        ArrayPush(this.m_speakers, speaker);
        let noMappin: NewMappinID;
        ArrayPush(this.m_mappins, noMappin);
        ArrayPush(this.m_hasMappin, false);
        ArrayPush(this.m_sides, this.m_spawnSide);
        return true;
    }

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

    public func MarkDead(id: EntityID) {
        let index: Int32 = this.IndexOf(id);
        if index < 0 {
            return;
        }
        this.RemoveMappin(index);
        let nemesisId: Int32 = this.m_nemesisIDs[index];
        if nemesisId > 0 {
            let kind: String = this.DeathKind(nemesisId, GameInstance.FindEntityByID(this.GetGameInstance(), id) as ScriptedPuppet);
            ArrayPush(this.m_deaths, nemesisId);
            let cause: String = this.TakeLastHit(nemesisId);
            if Equals(kind, "confirmed") && NotEquals(cause, "v") {
                kind = "normal";
            }
            ArrayPush(this.m_deathKinds, kind);
            ArrayPush(this.m_deathCauses, cause);
            ArrayRemove(this.m_finisherIds, nemesisId);

            this.m_nemesisIDs[index] = 0;
            GRLog("Nemesis #" + IntToString(nemesisId) + " muerto (" + kind + ", " + cause + ")");
        }
    }

    private func DeathKind(nemesisId: Int32, npc: ref<ScriptedPuppet>) -> String {
        if IsDefined(npc) && !npc.IsDead() && (ScriptedPuppet.IsUnconscious(npc) || ScriptedPuppet.IsDefeated(npc)) {
            return "knockout";
        }
        if ArrayContains(this.m_finisherIds, nemesisId) {
            return "confirmed";
        }
        if IsDefined(npc) && IsDefined(npc.GetDismembermentComponent()) {
            let limbs = npc.GetDismembermentComponent().GetDismemberedLimbCount();
            if limbs.fleshDismemberments + limbs.cyberDismemberments > 0u {
                return "confirmed";
            }
        }
        return "normal";
    }

    public func RecordHitBy(nemesisId: Int32, source: String) {
        let i: Int32 = ArrayFindFirst(this.m_lastHitIds, nemesisId);
        if i >= 0 {
            this.m_lastHitBy[i] = source;
        } else {
            ArrayPush(this.m_lastHitIds, nemesisId);
            ArrayPush(this.m_lastHitBy, source);
        }
        if NotEquals(source, "v") {
            ArrayRemove(this.m_finisherIds, nemesisId);
        }
    }

    private func TakeLastHit(nemesisId: Int32) -> String {
        let i: Int32 = ArrayFindFirst(this.m_lastHitIds, nemesisId);
        if i < 0 {
            return "other";
        }
        let source: String = this.m_lastHitBy[i];
        ArrayErase(this.m_lastHitIds, i);
        ArrayErase(this.m_lastHitBy, i);
        return source;
    }

    public func RecordPlayerHit(nemesisId: Int32, finisher: Bool) {
        this.RecordHitBy(nemesisId, "v");
        if finisher {
            if !ArrayContains(this.m_finisherIds, nemesisId) {
                ArrayPush(this.m_finisherIds, nemesisId);
            }
        } else {
            ArrayRemove(this.m_finisherIds, nemesisId);
        }
    }

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
        if this.IsInScene() {
            return "scene (no weapons)";
        }
        if GRSpawner.IsTWRSquadActive() {
            return "They Will Remember squad";
        }
        return "";
    }

    // They Will Remember manda sus propias venganzas (tag TheyWillRemember.Squad): no sumar otra encima.
    public static func IsTWRSquadActive() -> Bool {
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if !IsDefined(des) {
            return false;
        }
        let squad: array<ref<Entity>> = des.GetTagged(n"TheyWillRemember.Squad");
        return ArraySize(squad) > 0;
    }

    // Tier de escena 2-5: V camina sin armas (departamento, escenas de mision). En la calle es 1.
    public func IsInScene() -> Bool {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return false;
        }
        let tier: Int32 = player.GetPlayerStateMachineBlackboard().GetInt(GetAllBlackboardDefs().PlayerStateMachine.HighLevel);
        return tier >= 2 && tier <= 5;
    }

    // Mision de historia seguida (no gigs): ahi una huida puede dejar la mision sin terminar.
    public func IsStoryQuestTracked() -> Bool {
        let quest: wref<JournalQuest> = this.GetTrackedQuest();
        if !IsDefined(quest) {
            return false;
        }
        let questType: gameJournalQuestType = quest.GetType();
        return Equals(questType, gameJournalQuestType.MainQuest) || Equals(questType, gameJournalQuestType.SideQuest)
            || Equals(questType, gameJournalQuestType.MinorQuest) || Equals(questType, gameJournalQuestType.StreetStory);
    }

    public func IsOwnSpawn(id: EntityID) -> Bool {
        return this.IndexOf(id) >= 0;
    }

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

    public func GetDistrictGangs() -> String {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return "";
        }
        let district: wref<District_Record> = player.GetPreventionSystem().GetCurrentDistrict().GetDistrictRecord();
        let result: String = "";

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

    public func StartAmbush(nemesisId: Int32, recordID: String, appearance: String, escortRecords: String, line: String, speaker: String) -> Bool {
        let blocker: String = this.GetAmbushBlocker();
        if StrLen(blocker) > 0 || this.IsNemesisSpawned(nemesisId) {
            GRLog("A pie: no se intenta (bloqueo=" + blocker + ", ya generado=" + ToString(this.IsNemesisSpawned(nemesisId)) + ")");
            return false;
        }
        this.m_raidMode = false;
        if !this.SpawnGroup(nemesisId, recordID, appearance, escortRecords, line, speaker, 40.0) {
            return false;
        }
        this.m_ambushSawCombat = false;
        GRLog("Emboscada: Nemesis #" + IntToString(nemesisId));
        return true;
    }

    // Llegan en un vehiculo de la banda: aparece fuera de la vista a ~70 m detras de V, conducen hasta V y
    // se bajan a pelear. Los comandos de IA se mandan desde el tick (nunca desde eventos).
    public func StartVehicleAmbush(nemesisId: Int32, recordID: String, appearance: String, escortRecords: String, line: String, speaker: String, vehicleRecord: String) -> Bool {
        let blocker: String = this.GetAmbushBlocker();
        if StrLen(blocker) > 0 || this.IsNemesisSpawned(nemesisId) {
            GRLog("Vehiculo: no se intenta (bloqueo=" + blocker + ", ya generado=" + ToString(this.IsNemesisSpawned(nemesisId)) + ")");
            return false;
        }
        if !IsDefined(TweakDBInterface.GetVehicleRecord(TDBID.Create(vehicleRecord))) {
            GRLog("Vehiculo: record inexistente " + vehicleRecord);
            return false;
        }
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        // Primero detras de V; si no hay sitio, cualquier lado salvo delante, y mas cerca.
        let pos: Vector4 = this.FindSpot(player, RandRangeF(165.0, 195.0), 70.0, 120.0, 0.45, true);
        if !this.m_spotFound {
            GRLog("Vehiculo: sin sitio alrededor de V (descartes: no alcanzable=" + IntToString(this.m_spotFails[0])
                + ", bajo techo=" + IntToString(this.m_spotFails[1]) + ", ocupado=" + IntToString(this.m_spotFails[2])
                + ", a la vista=" + IntToString(this.m_spotFails[3]) + ")");
            return false;
        }
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        let spec: ref<DynamicEntitySpec> = new DynamicEntitySpec();
        spec.recordID = TDBID.Create(vehicleRecord);
        spec.position = pos;
        spec.orientation = this.GetFacingPlayer(player, pos);
        spec.persistState = false;
        spec.persistSpawn = false;
        spec.alwaysSpawned = false;
        spec.spawnInView = true;
        spec.active = true;
        ArrayPush(spec.tags, n"GangRetaliation");
        this.m_vehicleID = des.CreateEntity(spec);
        if !EntityID.IsDefined(this.m_vehicleID) {
            GRLog("Vehiculo: CreateEntity fallo para " + vehicleRecord);
            return false;
        }

        this.m_raidMode = false;
        this.m_vehicleState = 1;
        this.m_vehicleStateTime = this.Now();
        this.SpawnAt(nemesisId, recordID, appearance, pos, spec.orientation, line, speaker);
        let escorts: array<String>;
        if StrLen(escortRecords) > 0 {
            escorts = StrSplit(escortRecords, ",");
        }
        // Como mucho 3 escoltas: el vehiculo tiene 4 asientos.
        let i: Int32 = 0;
        while i < ArraySize(escorts) && i < 3 {
            this.SpawnAt(0, escorts[i], "", this.EscortSpot(pos, i), spec.orientation, "", "");
            i += 1;
        }
        this.m_ambushActive = true;
        this.m_ambushStart = this.Now();
        this.m_ambushCalmSince = 0.0;
        this.m_ambushSawCombat = false;
        this.m_stuckChecked = true;
        GRLog("Emboscada en vehiculo: Nemesis #" + IntToString(nemesisId) + " (" + vehicleRecord + ")");
        return true;
    }

    private func SeatName(index: Int32) -> CName {
        switch index {
            case 0: return n"seat_front_left";
            case 1: return n"seat_front_right";
            case 2: return n"seat_back_left";
            default: return n"seat_back_right";
        }
    }

    private func MountData(index: Int32) -> ref<MountEventData> {
        let data: ref<MountEventData> = new MountEventData();
        data.slotName = this.SeatName(index);
        data.mountParentEntityId = this.m_vehicleID;
        data.isInstant = true;
        data.ignoreHLS = true;
        return data;
    }

    private func GetVehicle() -> ref<VehicleObject> {
        return GameInstance.FindEntityByID(this.GetGameInstance(), this.m_vehicleID) as VehicleObject;
    }

    private func TickVehicle(player: ref<PlayerPuppet>, now: Float) {
        let vehicle: ref<VehicleObject> = this.GetVehicle();
        let elapsed: Float = now - this.m_vehicleStateTime;
        if this.m_vehicleState == 1 {
            let ready: Bool = IsDefined(vehicle);
            let i: Int32 = 0;
            while i < ArraySize(this.m_entityIDs) {
                if !IsDefined(GameInstance.FindEntityByID(this.GetGameInstance(), this.m_entityIDs[i]) as ScriptedPuppet) {
                    ready = false;
                }
                i += 1;
            }
            if ready {
                let seat: Int32 = 0;
                while seat < ArraySize(this.m_entityIDs) {
                    let npc: ref<ScriptedPuppet> = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_entityIDs[seat]) as ScriptedPuppet;
                    let mount: ref<AIMountCommand> = new AIMountCommand();
                    mount.mountData = this.MountData(seat);
                    npc.GetAIControllerComponent().SendCommand(mount);
                    seat += 1;
                }
                GRLog("Vehiculo: montando " + IntToString(ArraySize(this.m_entityIDs)) + " NPC");
                this.SetVehicleState(2, now);
            } else {
                if elapsed > 15.0 {
                    GRLog("Vehiculo: no cargo a tiempo, se bajan a pie");
                    this.StartVehicleFight(player, now);
                }
            }
        } else {
            if this.m_vehicleState == 2 && elapsed > 2.0 {
                if IsDefined(vehicle) {
                    let drive: ref<AIVehicleDriveToPointAutonomousCommand> = new AIVehicleDriveToPointAutonomousCommand();
                    drive.targetPosition = Vector4.Vector4To3(player.GetWorldPosition());
                    drive.minimumDistanceToTarget = 10.0;
                    drive.maxSpeed = 14.0;
                    drive.minSpeed = 5.0;
                    drive.clearTrafficOnPath = true;
                    drive.driveDownTheRoadIndefinitely = false;
                    drive.needDriver = true;
                    let evt: ref<AICommandEvent> = new AICommandEvent();
                    evt.command = drive;
                    vehicle.QueueEvent(evt);
                    GRLog("Vehiculo: conduciendo hacia V");
                }
                this.SetVehicleState(3, now);
            } else {
                if this.m_vehicleState == 3 {
                    let close: Bool = IsDefined(vehicle) && Vector4.Distance(vehicle.GetWorldPosition(), player.GetWorldPosition()) < 20.0;
                    if close || !IsDefined(vehicle) || elapsed > 35.0 || player.IsInCombat() {
                        GRLog("Vehiculo: se bajan (cerca=" + ToString(close) + ", " + FloatToString(elapsed) + " s)");
                        this.StartVehicleFight(player, now);
                    }
                }
            }
        }
    }

    private func SetVehicleState(state: Int32, now: Float) {
        this.m_vehicleState = state;
        this.m_vehicleStateTime = now;
    }

    // Se bajan y atacan; desde aqui sigue como una emboscada normal (con chequeo de atasco).
    private func StartVehicleFight(player: ref<PlayerPuppet>, now: Float) {
        let i: Int32 = 0;
        while i < ArraySize(this.m_entityIDs) {
            let npc: ref<ScriptedPuppet> = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_entityIDs[i]) as ScriptedPuppet;
            if IsDefined(npc) {
                if this.m_vehicleState >= 2 {
                    let unmount: ref<AIUnmountCommand> = new AIUnmountCommand();
                    unmount.mountData = this.MountData(i);
                    unmount.mountData.isInstant = false;
                    npc.GetAIControllerComponent().SendCommand(unmount);
                }
                this.MakeHostile(i, npc, player);
                this.m_spawnPositions[i] = npc.GetWorldPosition();
            }
            i += 1;
        }
        this.SetVehicleState(4, now);
        this.m_ambushStart = now;
        this.m_stuckChecked = false;
    }

    private func MakeHostile(index: Int32, npc: ref<ScriptedPuppet>, player: ref<PlayerPuppet>) {
        if !IsDefined(npc.GetAttitudeAgent()) || !IsDefined(player.GetAttitudeAgent()) {
            return;
        }
        npc.GetAttitudeAgent().SetAttitudeTowards(player.GetAttitudeAgent(), EAIAttitude.AIA_Hostile);
        StimBroadcasterComponent.SendStimDirectly(player, gamedataStimType.CombatHit, npc);
        if StrLen(this.m_lines[index]) > 0 {
            GRSpeech.Say(npc, this.m_speakers[index], this.m_lines[index], 5.0);
        }
    }

    public func StartReinforcement(nemesisId: Int32, recordID: String, appearance: String, escortRecords: String, line: String, speaker: String) -> Bool {
        if StrLen(this.GetReinforcementBlocker()) > 0 || this.IsNemesisSpawned(nemesisId) {
            return false;
        }
        this.m_raidMode = false;
        if !this.SpawnGroup(nemesisId, recordID, appearance, escortRecords, line, speaker, 20.0) {
            return false;
        }
        this.m_ambushSawCombat = true;
        GRLog("Refuerzo en gig: Nemesis #" + IntToString(nemesisId));
        return true;
    }

    private func SpawnGroup(nemesisId: Int32, recordID: String, appearance: String, escortRecords: String, line: String, speaker: String, distance: Float) -> Bool {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());

        // Detras de V (arco de +-60 grados), sin acercarse a menos del 70% de la distancia: no aparecen
        // delante ni encima. Si no hay sitio, la emboscada anunciada espera y reintenta.
        let angle: Float = RandRangeF(165.0, 195.0);
        let pos: Vector4 = this.FindSpot(player, angle, distance, 45.0, 0.7, false);
        if !this.m_spotFound {
            GRLog("Sin punto alcanzable detras de V: no se genera");
            return false;
        }
        if !this.SpawnAt(nemesisId, recordID, appearance, pos, this.GetFacingPlayer(player, pos), line, speaker) {
            return false;
        }

        let escorts: array<String>;
        if StrLen(escortRecords) > 0 {
            escorts = StrSplit(escortRecords, ",");
        }
        let i: Int32 = 0;
        while i < ArraySize(escorts) {
            let escortPos: Vector4 = this.EscortSpot(pos, i);
            this.SpawnAt(0, escorts[i], "", escortPos, this.GetFacingPlayer(player, escortPos), "", "");
            i += 1;
        }

        this.m_ambushActive = true;
        this.m_ambushStart = this.Now();
        this.m_ambushCalmSince = 0.0;
        this.m_stuckChecked = false;
        GRLog(IntToString(ArraySize(escorts)) + " escoltas");
        return true;
    }

    public func StartRaid(nemesisId: Int32, recordID: String, appearance: String, escortRecords: String, speaker: String, policeRecords: String) -> Bool {
        if StrLen(this.GetAmbushBlocker()) > 0 || this.IsNemesisSpawned(nemesisId) {
            return false;
        }
        // A ~55 m (minimo ~40) y fuera de la vista de V: se oye el tiroteo y V se acerca, no aparece de la nada.
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        let angles: array<Float> = [0.0, 60.0, -60.0, 120.0, -120.0, 180.0];
        for angle in angles {
            let posA: Vector4 = this.FindSpot(player, angle - 10.0, 55.0, 15.0, 0.75, true);
            if !this.m_spotFound {
                posA = Vector4.EmptyVector();
            }
            let posB: Vector4 = this.FindSpot(player, angle + 10.0, 55.0, 15.0, 0.75, true);
            if !this.m_spotFound {
                posB = Vector4.EmptyVector();
            }
            if !Vector4.IsZero(posA) && !Vector4.IsZero(posB) && Vector4.Distance(posA, posB) > 6.0 && this.IsConnected(posA, posB) {
                this.m_raidMode = true;
                this.m_raidHitGang = false;
                this.m_raidHitPolice = false;
                this.m_raidOutcome = "";
                this.m_raidHeat = 0;
                this.m_policeImmune = true;
                this.m_immuneRaidEnd = 0.0;
                this.m_raidPoliceOnV = false;
                this.m_spawnSide = 0;
                let facing: Quaternion = EulerAngles.ToQuat(Vector4.ToRotation(posB - posA));
                if !this.SpawnAt(nemesisId, recordID, appearance, posA, facing, "", speaker) {
                    this.m_raidMode = false;
                    return false;
                }
                this.SpawnRaidSide(escortRecords, posA, posB);
                this.m_spawnSide = 1;
                this.SpawnRaidSide(policeRecords, posB, posA);
                this.m_spawnSide = 0;

                this.m_ambushActive = true;
                this.m_ambushSawCombat = true;
                this.m_ambushStart = this.Now();
                this.m_ambushCalmSince = 0.0;
                this.m_stuckChecked = false;
                GRLog("Redada NCPD: Nemesis #" + IntToString(nemesisId) + ", " + IntToString(ArraySize(this.m_entityIDs)) + " NPC");
                return true;
            }
        }
        GRLog("Redada NCPD: sin sitio cerca de V");
        return false;
    }

    private func SpawnRaidSide(records: String, at: Vector4, facing: Vector4) {
        if StrLen(records) == 0 {
            return;
        }
        let list: array<String> = StrSplit(records, ",");
        let orientation: Quaternion = EulerAngles.ToQuat(Vector4.ToRotation(facing - at));
        let i: Int32 = 0;
        while i < ArraySize(list) {
            let raw: Vector4 = at + new Vector4(RandRangeF(-2.5, 2.5) + Cast<Float>(i) * 0.8, RandRangeF(-2.5, 2.5), 0.0, 0.0);
            // Ajustar al navmesh para no aparecer dentro de paredes; si no hay suelo, en el punto central.
            let pos: Vector4 = GameInstance.GetNavigationSystem(this.GetGameInstance()).GetNearestNavmeshPointBelowOnlyHumanNavmesh(raw + new Vector4(0.0, 0.0, 1.0, 0.0), 1.0, 5);
            if Vector4.IsZero(pos) || AbsF(pos.Z - at.Z) > 2.0 {
                pos = at;
            }
            this.SpawnAt(0, list[i], "", pos, orientation, "", "");
            i += 1;
        }
    }

    public func RecordRaidHitByV(id: EntityID) {
        if !this.m_raidMode {
            return;
        }
        let index: Int32 = this.IndexOf(id);
        if index < 0 {
            return;
        }
        if this.m_sides[index] == 0 {
            this.m_raidHitGang = true;
        } else {
            this.m_raidHitPolice = true;
        }
    }

    public func TakeRaidOutcome() -> String {
        let outcome: String = this.m_raidOutcome;
        this.m_raidOutcome = "";
        return outcome;
    }

    public func GiveMoney(amount: Int32) -> Bool {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) || amount <= 0 {
            return false;
        }
        return GameInstance.GetTransactionSystem(this.GetGameInstance()).GiveItem(player, MarketSystem.Money(), amount);
    }

    public func IsRaidActive() -> Bool {
        return this.m_ambushActive && this.m_raidMode;
    }

    private func SideAlive(side: Int32) -> Int32 {
        let count: Int32 = 0;
        let i: Int32 = 0;
        while i < ArraySize(this.m_entityIDs) {
            if this.m_sides[i] == side {
                let npc: ref<ScriptedPuppet> = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_entityIDs[i]) as ScriptedPuppet;
                if !IsDefined(npc) || !GRDetection.IsNeutralized(npc) {
                    count += 1;
                }
            }
            i += 1;
        }
        return count;
    }

    private func KeepPoliceFriendly() {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) || !IsDefined(player.GetAttitudeAgent()) {
            return;
        }
        let onV: Bool = false;
        let i: Int32 = 0;
        while i < ArraySize(this.m_entityIDs) {
            if this.m_sides[i] == 1 {
                let cop: ref<ScriptedPuppet> = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_entityIDs[i]) as ScriptedPuppet;
                if IsDefined(cop) && IsDefined(cop.GetAttitudeAgent()) && !GRDetection.IsNeutralized(cop) {
                    if NotEquals(GameObject.GetAttitudeBetween(cop, player), EAIAttitude.AIA_Friendly) {
                        onV = true;
                    }
                    cop.GetAttitudeAgent().SetAttitudeTowards(player.GetAttitudeAgent(), EAIAttitude.AIA_Friendly);
                }
            }
            i += 1;
        }
        let heat: Int32 = Cast<Int32>(player.GetPreventionSystem().GetHeatStageAsInt());
        if heat != this.m_raidHeat || NotEquals(onV, this.m_raidPoliceOnV) {
            GRLog("Redada: busqueda=" + IntToString(heat) + " policia no amistosa con V=" + ToString(onV)
                + " (V golpeo banda=" + ToString(this.m_raidHitGang) + " policia=" + ToString(this.m_raidHitPolice) + ")");
            this.m_raidHeat = heat;
            this.m_raidPoliceOnV = onV;
        }
    }

    private func TickRaid(now: Float) {
        this.KeepPoliceFriendly();
        let fighting: Bool = this.SideAlive(0) > 0 && this.SideAlive(1) > 0;
        if fighting {
            this.m_ambushCalmSince = 0.0;
        } else {
            if this.m_ambushCalmSince == 0.0 {
                this.m_ambushCalmSince = now;
            }
        }
        if (!fighting && now - this.m_ambushCalmSince > 20.0) || now - this.m_ambushStart > 180.0 {
            if this.SideAlive(0) == 0 && this.m_raidHitGang {
                this.m_raidOutcome = this.m_raidHitPolice ? "helpedPoliceHurtCops" : "helpedPolice";
            }
            GRLog("Fin de redada: limpiando (V gang=" + ToString(this.m_raidHitGang) + " police=" + ToString(this.m_raidHitPolice) + ")");
            this.CheckNeutralized();
            this.DespawnAll();
        }
    }

    public func IsAmbushActive() -> Bool {
        return this.m_ambushActive;
    }

    public func IsPoliceImmune() -> Bool {
        return this.m_policeImmune;
    }

    private func IsWeaponDrawn(player: ref<PlayerPuppet>) -> Bool {
        return IsDefined(GameInstance.GetTransactionSystem(this.GetGameInstance()).GetItemInSlot(player, t"AttachmentSlots.WeaponRight"));
    }

    private func TickImmunity() {
        if !this.m_policeImmune || this.IsRaidActive() {
            return;
        }
        let now: Float = this.Now();
        if this.m_immuneRaidEnd == 0.0 {
            this.m_immuneRaidEnd = now;
        }
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) || !this.IsWeaponDrawn(player) || now - this.m_immuneRaidEnd > 60.0 {
            this.m_policeImmune = false;
            GRLog("Redada: fin de la inmunidad ante la policia");
        }
    }

    public func Tick() {
        this.CheckNeutralized();
        this.CheckTaunts();
        this.TickImmunity();
        if !this.m_ambushActive {
            return;
        }
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return;
        }
        let now: Float = this.Now();
        if this.m_vehicleState >= 1 && this.m_vehicleState <= 3 {
            this.TickVehicle(player, now);
            return;
        }
        if !this.m_stuckChecked && now - this.m_ambushStart > 40.0 {
            this.m_stuckChecked = true;
            if this.IsStuck() {
                GRLog("Emboscada atascada: nadie se movio ni cayo en 40 s, limpiando");
                this.CheckNeutralized();
                this.DespawnAll();
                return;
            }
        }
        if this.m_raidMode {
            this.TickRaid(now);
            return;
        }
        if player.IsInCombat() {
            this.m_ambushSawCombat = true;
            this.m_ambushCalmSince = 0.0;
            return;
        }
        if this.m_ambushCalmSince == 0.0 {
            this.m_ambushCalmSince = now;
        }

        let calm: Float = now - this.m_ambushCalmSince;
        if (this.m_ambushSawCombat && calm > 20.0) || now - this.m_ambushStart > 180.0 {
            GRLog("Fin de emboscada: limpiando");
            this.CheckNeutralized();
            this.DespawnAll();
        }
    }

    // Atascada: ningun NPC cayo ni se alejo mas de 3 m de donde aparecio (o ni siquiera llego a cargarse).
    private func IsStuck() -> Bool {
        let i: Int32 = 0;
        while i < ArraySize(this.m_entityIDs) {
            let npc: ref<ScriptedPuppet> = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_entityIDs[i]) as ScriptedPuppet;
            if IsDefined(npc) {
                if GRDetection.IsNeutralized(npc) || Vector4.Distance(npc.GetWorldPosition(), this.m_spawnPositions[i]) > 3.0 {
                    return false;
                }
            }
            i += 1;
        }
        return true;
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
        ArrayClear(this.m_spawnPositions);
        ArrayClear(this.m_nemesisIDs);
        ArrayClear(this.m_lines);
        ArrayClear(this.m_speakers);
        ArrayClear(this.m_mappins);
        ArrayClear(this.m_hasMappin);
        ArrayClear(this.m_sides);
        this.m_ambushActive = false;
        this.m_raidMode = false;
        this.m_vehicleState = 0;
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
            if IsDefined(npc) && IsDefined(player) && this.m_raidMode {
                this.SetRaidHostility(index, npc);
                if this.m_nemesisIDs[index] > 0 && !this.m_hasMappin[index] {
                    this.AddMappin(index, npc);
                    ArrayPush(this.m_appearanceReports, IntToString(this.m_nemesisIDs[index]) + ":" + NameToString(npc.GetCurrentAppearanceName()));
                }
            } else if IsDefined(npc) && IsDefined(player) {
                // En vehiculo se vuelven hostiles al bajarse (StartVehicleFight), no al aparecer.
                if this.m_vehicleState == 0 {
                    npc.GetAttitudeAgent().SetAttitudeTowards(player.GetAttitudeAgent(), EAIAttitude.AIA_Hostile);
                    StimBroadcasterComponent.SendStimDirectly(player, gamedataStimType.CombatHit, npc);
                    if StrLen(this.m_lines[index]) > 0 {
                        GRSpeech.Say(npc, this.m_speakers[index], this.m_lines[index], 5.0);
                    }
                }
                if this.m_nemesisIDs[index] > 0 && !this.m_hasMappin[index] {
                    this.AddMappin(index, npc);
                    ArrayPush(this.m_appearanceReports, IntToString(this.m_nemesisIDs[index]) + ":" + NameToString(npc.GetCurrentAppearanceName()));
                    if GRIsBossBarNemesis(npc as NPCPuppet) {
                        GRNotifyBossBar(player, npc, false);
                    }
                }
            }
        }

        if Equals(eventType, DynamicEntityEventType.Dead) {
            this.MarkDead(event.GetEntityID());
        }

        if Equals(eventType, DynamicEntityEventType.Deleted) {
            if this.m_nemesisIDs[index] > 0 {
                GRNotifyBossBar(GetPlayer(this.GetGameInstance()), null, true);
                this.TakeLastHit(this.m_nemesisIDs[index]);
            }
            this.RemoveMappin(index);
            ArrayErase(this.m_entityIDs, index);
            ArrayErase(this.m_spawnPositions, index);
            ArrayErase(this.m_nemesisIDs, index);
            ArrayErase(this.m_lines, index);
            ArrayErase(this.m_speakers, index);
            ArrayErase(this.m_mappins, index);
            ArrayErase(this.m_hasMappin, index);
            ArrayErase(this.m_sides, index);
        }
    }

    private func SetRaidHostility(index: Int32, npc: ref<ScriptedPuppet>) {
        if !IsDefined(npc.GetAttitudeAgent()) {
            return;
        }
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if IsDefined(player) && IsDefined(player.GetAttitudeAgent()) {
            npc.GetAttitudeAgent().SetAttitudeTowards(player.GetAttitudeAgent(),
                this.m_sides[index] == 0 ? EAIAttitude.AIA_Hostile : EAIAttitude.AIA_Friendly);
        }
        let i: Int32 = 0;
        while i < ArraySize(this.m_entityIDs) {
            if this.m_sides[i] != this.m_sides[index] {
                let enemy: ref<ScriptedPuppet> = GameInstance.GetDynamicEntitySystem().GetEntity(this.m_entityIDs[i]) as ScriptedPuppet;
                if IsDefined(enemy) && IsDefined(enemy.GetAttitudeAgent()) {
                    npc.GetAttitudeAgent().SetAttitudeTowards(enemy.GetAttitudeAgent(), EAIAttitude.AIA_Hostile);
                    enemy.GetAttitudeAgent().SetAttitudeTowards(npc.GetAttitudeAgent(), EAIAttitude.AIA_Hostile);
                    StimBroadcasterComponent.SendStimDirectly(enemy, gamedataStimType.CombatHit, npc);
                    StimBroadcasterComponent.SendStimDirectly(npc, gamedataStimType.CombatHit, enemy);
                }
            }
            i += 1;
        }
    }

    public func GetDeathCount() -> Int32 {
        return ArraySize(this.m_deaths);
    }

    public func GetDeath(index: Int32) -> Int32 {
        return this.m_deaths[index];
    }

    public func GetDeathKind(index: Int32) -> String {
        return index < ArraySize(this.m_deathKinds) ? this.m_deathKinds[index] : "normal";
    }

    public func GetDeathCause(index: Int32) -> String {
        return index < ArraySize(this.m_deathCauses) ? this.m_deathCauses[index] : "v";
    }

    public func ClearDeaths() {
        ArrayClear(this.m_deaths);
        ArrayClear(this.m_deathKinds);
        ArrayClear(this.m_deathCauses);
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
