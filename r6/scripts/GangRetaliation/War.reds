// Gang Retaliation - fase 8: guerras de bandas
//
// - Lista de distritos del juego con sus bandas originales (TweakDB), para que CET arme el territorio.
// - Escaramuzas: dos grupos de bandas en guerra se tirotean cerca de V. Van aparte de las emboscadas
//   (otra etiqueta de DynamicEntitySystem) para no mezclarse con su limpieza.
// La simulacion (influencia, guerras, quien gana) vive en CET: modules/war.lua.

module GangRetaliation

public class GRWar extends ScriptableSystem {
    private let m_entityIDs: array<EntityID>;
    // 0 = bando A, 1 = bando B (paralelo a m_entityIDs).
    private let m_sides: array<Int32>;
    private let m_active: Bool;
    private let m_start: Float;
    private let m_fightSeen: Bool;
    // Por que fallo el ultimo Start (para la ventana de debug).
    private let m_lastError: String;

    public static func Get(gi: GameInstance) -> ref<GRWar> {
        return GameInstance.GetScriptableSystemsContainer(gi).Get(n"GangRetaliation.GRWar") as GRWar;
    }

    private func OnAttach() {
        GameInstance.GetDynamicEntitySystem().RegisterListener(n"GangRetaliationWar", this, n"OnEntityEvent");
    }

    private func OnDetach() {
        GameInstance.GetDynamicEntitySystem().UnregisterListener(n"GangRetaliationWar", this, n"OnEntityEvent");
    }

    private func Now() -> Float {
        return EngineTime.ToFloat(GameInstance.GetSimTime(this.GetGameInstance()));
    }

    // -------------------------------------------------------------------------
    // Distritos
    // -------------------------------------------------------------------------
    private func DistrictLabel(district: wref<District_Record>) -> String {
        let name: String = GetLocalizedText(district.LocalizedName());
        return StrLen(name) > 0 ? name : district.EnumName();
    }

    // "Clave|Nombre|Zona|BandaA,BandaB;..." con los barrios del juego (Kabuki, Little China...).
    // En TweakDB las bandas estan en la zona (Watson, Heywood...): cada barrio hereda las de su zona.
    // Zona sin barrios (Dogtown): cuenta como barrio.
    public func GetAllDistricts() -> String {
        let records: array<ref<TweakDBRecord>> = TweakDBInterface.GetRecords(n"District");
        let parents: array<TweakDBID>;
        for record in records {
            let district: ref<District_Record> = record as District_Record;
            if IsDefined(district) && IsDefined(district.ParentDistrict()) {
                ArrayPush(parents, district.ParentDistrict().GetID());
            }
        }
        let result: String = "";
        for record in records {
            let district: ref<District_Record> = record as District_Record;
            if IsDefined(district) {
                let top: wref<District_Record> = district;
                let depth: Int32 = 0;
                while IsDefined(top.ParentDistrict()) {
                    top = top.ParentDistrict();
                    depth += 1;
                }
                let isNeighborhood: Bool = depth == 1 || (depth == 0 && !ArrayContains(parents, district.GetID()));
                // Bandas propias o, si no tiene, las del primer distrito de arriba que tenga.
                let source: wref<District_Record> = district;
                while IsDefined(source) && source.GetGangsCount() == 0 {
                    source = source.ParentDistrict();
                }
                if isNeighborhood && IsDefined(source) {
                    let gangs: array<wref<Affiliation_Record>>;
                    source.Gangs(gangs);
                    let list: String = "";
                    for gang in gangs {
                        list += (StrLen(list) > 0 ? "," : "") + NameToString(gang.EnumName());
                    }
                    result += (StrLen(result) > 0 ? ";" : "") + district.EnumName() + "|" + this.DistrictLabel(district)
                        + "|" + this.DistrictLabel(top) + "|" + list;
                }
            }
        }
        return result;
    }

    // Barrio en el que esta V (el mismo nivel que GetAllDistricts: hijo directo de una zona,
    // o la zona si no tiene barrios).
    public func GetCurrentDistrict() -> String {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return "";
        }
        let district: wref<District_Record> = player.GetPreventionSystem().GetCurrentDistrict().GetDistrictRecord();
        if !IsDefined(district) {
            return "";
        }
        // Sube hasta quedar justo debajo de la zona.
        while IsDefined(district.ParentDistrict()) && IsDefined(district.ParentDistrict().ParentDistrict()) {
            district = district.ParentDistrict();
        }
        return district.EnumName();
    }

    // -------------------------------------------------------------------------
    // Escaramuzas
    // -------------------------------------------------------------------------
    public func IsActive() -> Bool {
        return this.m_active;
    }

    public func GetBlocker() -> String {
        let gi: GameInstance = this.GetGameInstance();
        let player: ref<PlayerPuppet> = GetPlayer(gi);
        if !IsDefined(player) || player.IsDead() {
            return "no player";
        }
        if this.m_active {
            return "skirmish active";
        }
        let spawner: ref<GRSpawner> = GRSpawner.Get(gi);
        if IsDefined(spawner) && spawner.IsAmbushActive() {
            return "ambush active";
        }
        if !GameInstance.GetDynamicEntitySystem().IsReady() {
            return "entity system not ready";
        }
        if VehicleComponent.IsMountedToVehicle(gi, player) {
            return "in vehicle";
        }
        if player.IsInCombat() {
            return "in combat";
        }
        if StatusEffectSystem.ObjectHasStatusEffectWithTag(player, n"NoCombat") {
            return "no-combat zone";
        }
        if IsDefined(spawner) && spawner.IsInScene() {
            return "scene (no weapons)";
        }
        if GRSpawner.IsTWRSquadActive() {
            return "They Will Remember squad";
        }
        return "";
    }

    // Punto de suelo a pie a la altura de V (sin azoteas ni sotanos). Se busca desde 2 m por encima
    // para encontrar el suelo aunque suba un poco respecto a V.
    private func GroundNear(player: ref<PlayerPuppet>, raw: Vector4) -> Vector4 {
        let pos: Vector4 = GameInstance.GetNavigationSystem(this.GetGameInstance()).GetNearestNavmeshPointBelowOnlyHumanNavmesh(raw + new Vector4(0.0, 0.0, 2.0, 0.0), 2.0, 6);
        if Vector4.IsZero(pos) || AbsF(pos.Z - player.GetWorldPosition().Z) > 6.0 {
            return Vector4.EmptyVector();
        }
        return pos;
    }

    // Dos grupos enfrentados a unos 40 m de V, delante o a los lados, separados unos 18 m.
    // recordsA / recordsB: recordIDs separados por comas. Devuelve false si no hay sitio.
    public func GetLastError() -> String {
        return this.m_lastError;
    }

    public func Start(recordsA: String, recordsB: String) -> Bool {
        this.m_lastError = this.GetBlocker();
        if StrLen(this.m_lastError) > 0 {
            return false;
        }
        let spawner: ref<GRSpawner> = GRSpawner.Get(this.GetGameInstance());
        if !IsDefined(spawner) {
            this.m_lastError = "no spawner";
            return false;
        }
        // Dos puntos alcanzables a pie desde V (como las emboscadas), a unos 30 m y separados
        // por unos 25 grados: cada bando en uno. Se prueban varias direcciones.
        let angles: array<Float> = [0.0, 60.0, -60.0, 120.0, -120.0, 180.0];
        for angle in angles {
            let posA: Vector4 = spawner.FindWarSpot(angle - 13.0, 30.0);
            let posB: Vector4 = spawner.FindWarSpot(angle + 13.0, 30.0);
            if !Vector4.IsZero(posA) && !Vector4.IsZero(posB) && Vector4.Distance(posA, posB) > 6.0 {
                this.SpawnSide(recordsA, posA, posB, 0);
                this.SpawnSide(recordsB, posB, posA, 1);
                this.m_active = ArraySize(this.m_entityIDs) > 0;
                this.m_start = this.Now();
                this.m_fightSeen = false;
                GRLog("Escaramuza: " + IntToString(ArraySize(this.m_entityIDs)) + " pandilleros");
                if !this.m_active {
                    this.m_lastError = "no entities created";
                }
                return this.m_active;
            }
        }
        this.m_lastError = "no reachable ground near V";
        GRLog("Escaramuza: sin sitio cerca de V");
        return false;
    }

    private func SpawnSide(records: String, at: Vector4, facing: Vector4, side: Int32) {
        let list: array<String> = StrSplit(records, ",");
        let i: Int32 = 0;
        while i < ArraySize(list) {
            let spec: ref<DynamicEntitySpec> = new DynamicEntitySpec();
            spec.recordID = TDBID.Create(list[i]);
            spec.appearanceName = n"random";
            // En fila, separados 2,5 m.
            spec.position = at + new Vector4(RandRangeF(-2.5, 2.5) + Cast<Float>(i) * 0.8, RandRangeF(-2.5, 2.5), 0.0, 0.0);
            spec.orientation = EulerAngles.ToQuat(Vector4.ToRotation(facing - at));
            spec.persistState = false;
            spec.persistSpawn = false;
            spec.alwaysSpawned = false;
            spec.spawnInView = true;
            spec.active = true;
            ArrayPush(spec.tags, n"GangRetaliationWar");
            ArrayPush(this.m_entityIDs, GameInstance.GetDynamicEntitySystem().CreateEntity(spec));
            ArrayPush(this.m_sides, side);
            i += 1;
        }
    }

    // Al aparecer, cada pandillero se vuelve hostil con los del otro bando ya presentes (y ellos con el).
    private cb func OnEntityEvent(event: ref<DynamicEntityEvent>) {
        let index: Int32 = -1;
        let i: Int32 = 0;
        while i < ArraySize(this.m_entityIDs) && index < 0 {
            if this.m_entityIDs[i] == event.GetEntityID() {
                index = i;
            }
            i += 1;
        }
        if index < 0 {
            return;
        }
        let eventType: DynamicEntityEventType = event.GetEventType();
        if Equals(eventType, DynamicEntityEventType.Spawned) {
            let npc: ref<ScriptedPuppet> = GameInstance.GetDynamicEntitySystem().GetEntity(event.GetEntityID()) as ScriptedPuppet;
            if !IsDefined(npc) {
                return;
            }
            i = 0;
            while i < ArraySize(this.m_entityIDs) {
                if this.m_sides[i] != this.m_sides[index] {
                    let enemy: ref<ScriptedPuppet> = GameInstance.GetDynamicEntitySystem().GetEntity(this.m_entityIDs[i]) as ScriptedPuppet;
                    if IsDefined(enemy) {
                        npc.GetAttitudeAgent().SetAttitudeTowards(enemy.GetAttitudeAgent(), EAIAttitude.AIA_Hostile);
                        enemy.GetAttitudeAgent().SetAttitudeTowards(npc.GetAttitudeAgent(), EAIAttitude.AIA_Hostile);
                        StimBroadcasterComponent.SendStimDirectly(enemy, gamedataStimType.CombatHit, npc);
                        StimBroadcasterComponent.SendStimDirectly(npc, gamedataStimType.CombatHit, enemy);
                    }
                }
                i += 1;
            }
        }
        if Equals(eventType, DynamicEntityEventType.Deleted) {
            ArrayErase(this.m_entityIDs, index);
            ArrayErase(this.m_sides, index);
            if ArraySize(this.m_entityIDs) == 0 {
                this.m_active = false;
            }
        }
    }

    // Vivos de un bando (los que no se ven cuentan como vivos).
    private func Alive(side: Int32) -> Int32 {
        let count: Int32 = 0;
        let i: Int32 = 0;
        while i < ArraySize(this.m_entityIDs) {
            if this.m_sides[i] == side {
                let npc: ref<ScriptedPuppet> = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_entityIDs[i]) as ScriptedPuppet;
                if !IsDefined(npc) || !(npc.IsDead() || ScriptedPuppet.IsDefeated(npc) || ScriptedPuppet.IsUnconscious(npc)) {
                    count += 1;
                }
            }
            i += 1;
        }
        return count;
    }

    // Lo llama CET cada segundo: limpia al acabar (un bando sin nadie, V lejos o 3 minutos).
    public func Tick() {
        if !this.m_active {
            return;
        }
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        let elapsed: Float = this.Now() - this.m_start;
        let oneSideDown: Bool = this.Alive(0) == 0 || this.Alive(1) == 0;
        if oneSideDown && !this.m_fightSeen {
            this.m_fightSeen = true;
            this.m_start = this.Now() - 150.0;
        }
        if elapsed > 180.0 || !IsDefined(player) {
            GRLog("Fin de escaramuza: limpiando");
            this.Despawn();
        }
    }

    public func Despawn() {
        GameInstance.GetDynamicEntitySystem().DeleteTagged(n"GangRetaliationWar");
        ArrayClear(this.m_entityIDs);
        ArrayClear(this.m_sides);
        this.m_active = false;
    }
}
