module GangRetaliation

public class GRSpawner extends ScriptableSystem {
    private let m_entityIDs: array<EntityID>;

    private let m_nemesisIDs: array<Int32>;

    private let m_lines: array<String>;

    private let m_speakers: array<String>;

    private let m_mappins: array<NewMappinID>;
    private let m_hasMappin: array<Bool>;

    // Redada de la NCPD: bando de cada entidad (0 = banda, 1 = policia)
    private let m_sides: array<Int32>;
    private let m_spawnSide: Int32;
    private let m_raidMode: Bool;
    // Lo que hizo V en la redada: golpeo a la banda / a la policia. Al acabar queda el resultado
    // ("helpedPolice" si la banda cayo entera con ayuda de V; "helpedPoliceHurtCops" si ademas V
    // le pego a algun policia: cobra con descuento).
    private let m_raidHitGang: Bool;
    private let m_raidHitPolice: Bool;
    private let m_raidOutcome: String;
    // Diagnostico: ultimo nivel de busqueda visto y ultimo estado "la policia apunta a V".
    private let m_raidHeat: Int32;
    // Inmunidad ante la policia: desde que empieza la redada hasta que termina Y V enfunda el arma
    // (como mucho 60 s despues del final). Mientras dura, nada de lo que haga V cuenta como delito.
    private let m_policeImmune: Bool;
    private let m_immuneRaidEnd: Float;
    private let m_raidPoliceOnV: Bool;

    private let m_deaths: array<Int32>;
    private let m_deathKinds: array<String>;

    private let m_finisherIds: array<Int32>;

    // Ultimo golpe a cada Nemesis vivo (GRTraits.HitSource) y causa de cada muerte.
    private let m_lastHitIds: array<Int32>;
    private let m_lastHitBy: array<String>;
    private let m_deathCauses: array<String>;

    private let m_appearanceReports: array<String>;

    private let m_ambushActive: Bool;
    private let m_ambushStart: Float;
    private let m_ambushSawCombat: Bool;
    private let m_ambushCalmSince: Float;

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
        if Vector4.IsZero(pos) || AbsF(pos.Z - target.Z) > 4.0 {
            return false;
        }
        let path: ref<NavigationPath> = GameInstance.GetNavigationSystem(this.GetGameInstance()).CalculatePathOnlyHumanNavmesh(pos, target, NavGenAgentSize.Human, 1.0);
        if !IsDefined(path) || ArraySize(path.path) < 2 {
            return false;
        }

        let last: Vector4 = path.path[ArraySize(path.path) - 1];
        return Vector4.Distance(last, target) < 3.0 && path.CalculateLength() < distance * 2.5 + 10.0;
    }

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
            // Un remate solo es definitivo si lo dio V.
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
        // Si otro le da el ultimo golpe, el remate de V ya no cuenta.
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
        return "";
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
        if StrLen(this.GetAmbushBlocker()) > 0 || this.IsNemesisSpawned(nemesisId) {
            return false;
        }
        this.m_raidMode = false;
        if !this.SpawnGroup(nemesisId, recordID, appearance, escortRecords, line, speaker, 25.0) {
            return false;
        }
        this.m_ambushSawCombat = false;
        GRLog("Emboscada: Nemesis #" + IntToString(nemesisId));
        return true;
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

        let angle: Float = RandRangeF(150.0, 210.0);
        let pos: Vector4 = this.FindReachableSpot(player, angle, distance);
        if !this.m_spotFound {
            GRLog("Sin punto alcanzable cerca de V: no se genera");
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

    // Redada: el Nemesis y su escolta contra una patrulla de la NCPD, a unos 30 m de V (como las
    // escaramuzas de GRWar). policeRecords: recordIDs separados por comas.
    public func StartRaid(nemesisId: Int32, recordID: String, appearance: String, escortRecords: String, speaker: String, policeRecords: String) -> Bool {
        if StrLen(this.GetAmbushBlocker()) > 0 || this.IsNemesisSpawned(nemesisId) {
            return false;
        }
        let angles: array<Float> = [0.0, 60.0, -60.0, 120.0, -120.0, 180.0];
        for angle in angles {
            let posA: Vector4 = this.FindWarSpot(angle - 13.0, 30.0);
            let posB: Vector4 = this.FindWarSpot(angle + 13.0, 30.0);
            if !Vector4.IsZero(posA) && !Vector4.IsZero(posB) && Vector4.Distance(posA, posB) > 6.0 {
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
            let pos: Vector4 = at + new Vector4(RandRangeF(-2.5, 2.5) + Cast<Float>(i) * 0.8, RandRangeF(-2.5, 2.5), 0.0, 0.0);
            this.SpawnAt(0, list[i], "", pos, orientation, "", "");
            i += 1;
        }
    }

    // V (o un aliado) golpeo a alguien de la redada.
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

    // Resultado de la ultima redada terminada (se vacia al leerlo).
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

    // Vivos de un bando (los que aun no aparecen cuentan como vivos).
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

    // Fin de la redada: un bando sin nadie en pie (y 20 s para que V lo vea) o 3 minutos.
    // Cada segundo: la policia vuelve a ser amistosa con V (el juego puede cambiarlo en combate)
    // y se registra si V tiene busqueda o si algun policia lo considera enemigo.
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
        ArrayClear(this.m_sides);
        this.m_ambushActive = false;
        this.m_raidMode = false;
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
                npc.GetAttitudeAgent().SetAttitudeTowards(player.GetAttitudeAgent(), EAIAttitude.AIA_Hostile);
                StimBroadcasterComponent.SendStimDirectly(player, gamedataStimType.CombatHit, npc);
                if StrLen(this.m_lines[index]) > 0 {
                    GRSpeech.Say(npc, this.m_speakers[index], this.m_lines[index], 5.0);
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
            ArrayErase(this.m_nemesisIDs, index);
            ArrayErase(this.m_lines, index);
            ArrayErase(this.m_speakers, index);
            ArrayErase(this.m_mappins, index);
            ArrayErase(this.m_hasMappin, index);
            ArrayErase(this.m_sides, index);
        }
    }

    // Al aparecer en una redada, cada NPC se vuelve hostil con los del otro bando ya presentes (y ellos con el).
    private func SetRaidHostility(index: Int32, npc: ref<ScriptedPuppet>) {
        if !IsDefined(npc.GetAttitudeAgent()) {
            return;
        }
        // La banda, hostil con V (sin avisarla: solo ataca si lo ve). Si fuera neutral, dispararle
        // seria un delito y la policia iria a por V aunque la estuviera ayudando.
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
