// Gang Retaliation - fase 1: deteccion de candidatos a Nemesis
//
// - Pandillero herido por V que sigue vivo (y consciente) cuando V sale de combate,
//   con la vida por debajo del umbral -> "escaped".
// - Ultimo pandillero en pie y malherido: huye gritando; si sobrevive -> "fled".
//
// Redscript solo detecta y encola eventos; la capa CET les da nombre y los guarda.

module GangRetaliation

// Pandillero al que V ha herido en el combate actual.
public class GRCandidate {
    public let entityID: EntityID;
    // >0 si es un Nemesis ya existente generado por el mod.
    public let nemesisId: Int32;
    public let gang: String;
    public let recordID: TweakDBID;
    public let appearance: CName;
    public let gender: CName;
    public let health: Float;
    public let position: Vector4;
    public let fleeing: Bool;
}

// Evento que lee CET (solo tipos simples para que Lua los lea sin problemas).
public class GRNemesisEvent {
    public let origin: String;
    public let nemesisId: Int32;
    public let gang: String;
    public let recordID: String;
    public let appearance: String;
    public let gender: String;
    public let health: Float;
    public let posX: Float;
    public let posY: Float;
    public let posZ: Float;
}

public class GRDetection extends ScriptableSystem {
    private let m_candidates: array<ref<GRCandidate>>;
    private let m_pending: array<ref<GRNemesisEvent>>;
    // Entidades ya convertidas en esta sesion, para no duplicar.
    private let m_promoted: array<EntityID>;
    // Pandilleros que han participado en el combate actual (golpeados por V o que golpearon a V).
    private let m_combatants: array<wref<ScriptedPuppet>>;
    // Solo huye uno por combate.
    private let m_someoneFled: Bool;
    // Pandilleros huyendo: se convierten en Nemesis cuando escapan de verdad.
    private let m_fleeing: array<ref<GRCandidate>>;
    private let m_fleeStart: array<Float>;
    // Modo de huida (debug desde CET): 0 = correr lejos, 1 = miedo, 2 = ambos.
    private let m_fleeMode: Int32;

    public static func Get(gi: GameInstance) -> ref<GRDetection> {
        return GameInstance.GetScriptableSystemsContainer(gi).Get(n"GangRetaliation.GRDetection") as GRDetection;
    }

    private func OnAttach() {
        // Por defecto: correr lejos + miedo (probado en el juego, 2026-10-26).
        this.m_fleeMode = 2;
    }

    // -------------------------------------------------------------------------
    // Utilidades
    // -------------------------------------------------------------------------
    public static func GetGang(npc: ref<ScriptedPuppet>) -> String {
        let record: wref<Character_Record> = npc.GetRecord();
        if !IsDefined(record) || !IsDefined(record.Affiliation()) {
            return "";
        }
        switch record.Affiliation().Type() {
            case gamedataAffiliation.Maelstrom: return "Maelstrom";
            case gamedataAffiliation.TygerClaws: return "TygerClaws";
            case gamedataAffiliation.Valentinos: return "Valentinos";
            case gamedataAffiliation.SixthStreet: return "SixthStreet";
            case gamedataAffiliation.Animals: return "Animals";
            case gamedataAffiliation.VoodooBoys: return "VoodooBoys";
            case gamedataAffiliation.Wraiths: return "Wraiths";
            case gamedataAffiliation.Scavengers: return "Scavengers";
            case gamedataAffiliation.Barghest: return "Barghest";
            default: return "";
        }
    }

    public static func IsEligible(npc: ref<ScriptedPuppet>) -> Bool {
        if !IsDefined(npc) || npc.IsPlayer() || npc.IsCrowd() || npc.IsCharacterCivilian() {
            return false;
        }
        // Jefes de mision y personajes unicos quedan fuera.
        let record: wref<Character_Record> = npc.GetRecord();
        if IsDefined(record) && IsDefined(record.Rarity()) {
            let rarity: gamedataNPCRarity = record.Rarity().Type();
            if Equals(rarity, gamedataNPCRarity.Boss) || Equals(rarity, gamedataNPCRarity.MaxTac) {
                return false;
            }
        }
        return NotEquals(GRDetection.GetGang(npc), "");
    }

    // Muerto, derribado o inconsciente.
    public static func IsNeutralized(npc: ref<ScriptedPuppet>) -> Bool {
        return !IsDefined(npc) || npc.IsDead() || ScriptedPuppet.IsDefeated(npc) || ScriptedPuppet.IsUnconscious(npc);
    }

    private func GetHealthPercent(npc: ref<ScriptedPuppet>) -> Float {
        return GameInstance.GetStatPoolsSystem(this.GetGameInstance()).GetStatPoolValue(Cast<StatsObjectID>(npc.GetEntityID()), gamedataStatPoolType.Health, true);
    }

    private func IsEnabled() -> Bool {
        let settings: ref<GRSettings> = GRSettings.Get(this.GetGameInstance());
        return !IsDefined(settings) || settings.enabled;
    }

    private func Debug(msg: String) {
        let settings: ref<GRSettings> = GRSettings.Get(this.GetGameInstance());
        if IsDefined(settings) && settings.debugLog {
            GRLog(msg);
        }
    }

    private func GetSpawnedNemesisId(id: EntityID) -> Int32 {
        let spawner: ref<GRSpawner> = GRSpawner.Get(this.GetGameInstance());
        return IsDefined(spawner) ? spawner.GetNemesisId(id) : 0;
    }

    private func FindCandidate(id: EntityID) -> Int32 {
        let i: Int32 = 0;
        while i < ArraySize(this.m_candidates) {
            if this.m_candidates[i].entityID == id {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    private func WasPromoted(id: EntityID) -> Bool {
        for promoted in this.m_promoted {
            if promoted == id {
                return true;
            }
        }
        return false;
    }

    private func IsPlayerDead() -> Bool {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) || player.IsDead() {
            return true;
        }
        let health: Float = GameInstance.GetStatPoolsSystem(this.GetGameInstance()).GetStatPoolValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.Health, true);
        return health <= 0.0;
    }

    private func MakeCandidate(npc: ref<ScriptedPuppet>) -> ref<GRCandidate> {
        let candidate: ref<GRCandidate> = new GRCandidate();
        candidate.entityID = npc.GetEntityID();
        candidate.gang = GRDetection.GetGang(npc);
        candidate.nemesisId = this.GetSpawnedNemesisId(npc.GetEntityID());
        candidate.recordID = npc.GetRecord().GetID();
        candidate.appearance = npc.GetCurrentAppearanceName();
        candidate.gender = npc.GetResolvedGenderName();
        candidate.health = this.GetHealthPercent(npc);
        candidate.position = npc.GetWorldPosition();
        return candidate;
    }

    // Busca o crea el candidato y actualiza su vida y posicion.
    private func UpsertCandidate(npc: ref<ScriptedPuppet>) -> ref<GRCandidate> {
        let index: Int32 = this.FindCandidate(npc.GetEntityID());
        if index >= 0 {
            let candidate: ref<GRCandidate> = this.m_candidates[index];
            candidate.health = this.GetHealthPercent(npc);
            candidate.position = npc.GetWorldPosition();
            return candidate;
        }
        let created: ref<GRCandidate> = this.MakeCandidate(npc);
        ArrayPush(this.m_candidates, created);
        this.Debug("Candidato: " + created.gang + " " + TDBID.ToStringDEBUG(created.recordID));
        return created;
    }

    private func AddCombatant(npc: ref<ScriptedPuppet>) {
        for combatant in this.m_combatants {
            if combatant == npc {
                return;
            }
        }
        ArrayPush(this.m_combatants, npc);
    }

    private func ResetFight() {
        ArrayClear(this.m_candidates);
        ArrayClear(this.m_combatants);
        this.m_someoneFled = false;
    }

    // -------------------------------------------------------------------------
    // Huida del ultimo en pie
    // -------------------------------------------------------------------------
    private func CheckLastStanding() {
        let settings: ref<GRSettings> = GRSettings.Get(this.GetGameInstance());
        if this.m_someoneFled || !IsDefined(settings) || !settings.lastManFlees {
            return;
        }
        // "Ultimo que queda": tiene que haber habido al menos dos pandilleros en la pelea.
        if ArraySize(this.m_combatants) < 2 {
            return;
        }
        let last: ref<ScriptedPuppet>;
        let alive: Int32 = 0;
        for combatant in this.m_combatants {
            if !GRDetection.IsNeutralized(combatant) {
                alive += 1;
                last = combatant;
            }
        }
        if alive != 1 {
            return;
        }
        // Nunca con vehiculos de por medio: las ordenes de movimiento a un NPC montado son peligrosas.
        let gi: GameInstance = this.GetGameInstance();
        if VehicleComponent.IsMountedToVehicle(gi, last) || VehicleComponent.IsMountedToVehicle(gi, GetPlayer(gi)) {
            this.Debug("Huida cancelada: hay un vehiculo de por medio");
            return;
        }
        let health: Float = this.GetHealthPercent(last);
        if health > 0.0 && health <= Cast<Float>(settings.fleeHealthPercent) {
            this.MakeFlee(last);
        }
    }

    private func Now() -> Float {
        return EngineTime.ToFloat(GameInstance.GetSimTime(this.GetGameInstance()));
    }

    private func MakeFlee(npc: ref<ScriptedPuppet>) {
        if !IsDefined(npc) || !npc.IsAttached() || VehicleComponent.IsMountedToVehicle(this.GetGameInstance(), npc) {
            return;
        }
        this.m_someoneFled = true;
        let candidate: ref<GRCandidate> = this.UpsertCandidate(npc);
        candidate.fleeing = true;
        ArrayPush(this.m_fleeing, candidate);
        ArrayPush(this.m_fleeStart, this.Now());

        let puppet: ref<NPCPuppet> = npc as NPCPuppet;
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if IsDefined(puppet) && IsDefined(player) {
            if this.m_fleeMode == 0 || this.m_fleeMode == 2 {
                // Deja de pelear y corre a un punto alejado de V.
                puppet.GetAttitudeAgent().SetAttitudeTowards(player.GetAttitudeAgent(), EAIAttitude.AIA_Neutral);
                let away: Vector4 = Vector4.Normalize(npc.GetWorldPosition() - player.GetWorldPosition());
                let wp: WorldPosition;
                WorldPosition.SetVector4(wp, npc.GetWorldPosition() + away * 60.0);
                let target: AIPositionSpec;
                AIPositionSpec.SetWorldPosition(target, wp);
                let move: ref<AIMoveToCommand> = new AIMoveToCommand();
                move.movementTarget = target;
                move.movementType = moveMovementType.Sprint;
                move.ignoreNavigation = false;
                move.finishWhenDestinationReached = true;
                move.desiredDistanceFromTarget = 2.0;
                puppet.GetAIControllerComponent().SendCommand(move);
            }
            if this.m_fleeMode == 1 || this.m_fleeMode == 2 {
                NPCPuppet.ChangeHighLevelState(puppet, gamedataNPCHighLevelState.Fear);
            }
        }
        // Frase de miedo con su propia voz (si su voz no la tiene, no suena nada).
        GameObject.PlayVoiceOver(npc, n"fear_run", n"Scripts:GangRetaliation");
        this.SayFleeLine(npc, candidate.gang);
        this.Debug("Huye el ultimo en pie (modo " + IntToString(this.m_fleeMode) + "): " + candidate.gang + " vida " + FloatToString(candidate.health) + "%");
    }

    private func SayFleeLine(npc: ref<ScriptedPuppet>, gang: String) {
        let loc: ref<GRSystem> = GRSystem.Get(this.GetGameInstance());
        if !IsDefined(loc) {
            return;
        }
        let line: String = loc.GetText("GR-Flee-" + IntToString(RandRange(1, 9)));
        GRSpeech.Say(npc, loc.GetText("GR-Gang-" + gang), line, 5.0);
    }

    // Lo llama CET cada segundo: decide si los que huyen han escapado.
    public func UpdateFleeing() {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        let i: Int32 = ArraySize(this.m_fleeing) - 1;
        while i >= 0 {
            let candidate: ref<GRCandidate> = this.m_fleeing[i];
            let npc: ref<ScriptedPuppet> = GameInstance.FindEntityByID(this.GetGameInstance(), candidate.entityID) as ScriptedPuppet;
            let done: Bool = false;
            if !IsDefined(npc) {
                // Ha desaparecido del mundo: ha escapado.
                this.Promote(candidate, "fled");
                done = true;
            } else {
                if GRDetection.IsNeutralized(npc) {
                    done = true;
                } else {
                    candidate.health = this.GetHealthPercent(npc);
                    candidate.position = npc.GetWorldPosition();
                    let far: Bool = IsDefined(player) && Vector4.Distance(npc.GetWorldPosition(), player.GetWorldPosition()) > 45.0;
                    if far || this.Now() - this.m_fleeStart[i] > 25.0 {
                        this.Promote(candidate, "fled");
                        done = true;
                    }
                }
            }
            if done {
                ArrayErase(this.m_fleeing, i);
                ArrayErase(this.m_fleeStart, i);
            }
            i -= 1;
        }
    }

    public func GetFleeMode() -> Int32 {
        return this.m_fleeMode;
    }

    public func SetFleeMode(mode: Int32) {
        this.m_fleeMode = mode;
    }

    // -------------------------------------------------------------------------
    // Entradas desde los hooks
    // -------------------------------------------------------------------------
    public func OnPlayerHitNPC(npc: ref<ScriptedPuppet>) {
        if !this.IsEnabled() || !GRDetection.IsEligible(npc) || this.WasPromoted(npc.GetEntityID()) {
            return;
        }
        this.AddCombatant(npc);
        this.UpsertCandidate(npc);
        this.CheckLastStanding();
    }

    public func OnNPCHitPlayer(npc: ref<ScriptedPuppet>) {
        if this.IsEnabled() && GRDetection.IsEligible(npc) {
            this.AddCombatant(npc);
        }
    }

    public func OnNPCDeath(npc: ref<ScriptedPuppet>) {
        let spawner: ref<GRSpawner> = GRSpawner.Get(this.GetGameInstance());
        if IsDefined(spawner) {
            spawner.MarkDead(npc.GetEntityID());
        }
        let index: Int32 = this.FindCandidate(npc.GetEntityID());
        if index >= 0 {
            ArrayErase(this.m_candidates, index);
        }
        let f: Int32 = 0;
        while f < ArraySize(this.m_fleeing) {
            if this.m_fleeing[f].entityID == npc.GetEntityID() {
                ArrayErase(this.m_fleeing, f);
                ArrayErase(this.m_fleeStart, f);
                f = ArraySize(this.m_fleeing);
            }
            f += 1;
        }
        let i: Int32 = 0;
        while i < ArraySize(this.m_combatants) {
            if this.m_combatants[i] == npc {
                ArrayErase(this.m_combatants, i);
                // Sigue contando como participante para la regla de "al menos dos".
                ArrayPush(this.m_combatants, null);
                i = ArraySize(this.m_combatants);
            }
            i += 1;
        }
        if this.IsEnabled() {
            this.CheckLastStanding();
        }
    }

    public func OnPlayerCombatEnded() {
        if !this.IsEnabled() {
            this.ResetFight();
            return;
        }
        // Si el combate termina porque V ha muerto, nadie "escapa".
        if this.IsPlayerDead() {
            this.Debug("Fin de combate por muerte de V: sin huidas");
            return;
        }
        let threshold: Float = Cast<Float>(GRSettings.Get(this.GetGameInstance()).escapeHealthPercent);

        for candidate in this.m_candidates {
            let npc: ref<ScriptedPuppet> = GameInstance.FindEntityByID(this.GetGameInstance(), candidate.entityID) as ScriptedPuppet;
            let neutralized: Bool = false;
            if IsDefined(npc) {
                // Muerto, derribado o inconsciente: V lo ha neutralizado, no escapa.
                neutralized = GRDetection.IsNeutralized(npc);
                if !neutralized {
                    candidate.health = this.GetHealthPercent(npc);
                    candidate.position = npc.GetWorldPosition();
                }
            }
            // Si ya no existe (se alejo y desaparecio) se usan los ultimos datos conocidos.
            if !neutralized {
                this.Debug("Fin de combate: " + candidate.gang + " vida " + FloatToString(candidate.health) + "%" + (candidate.fleeing ? " (huyendo)" : ""));
                // Los que huyen los resuelve UpdateFleeing.
                if !candidate.fleeing && candidate.health > 0.0 && candidate.health <= threshold {
                    this.Promote(candidate, "escaped");
                }
            }
        }
        this.ResetFight();
    }

    // -------------------------------------------------------------------------
    // Debug (desde la ventana de CET)
    // -------------------------------------------------------------------------
    private func GetLookAtNPC() -> ref<ScriptedPuppet> {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        let target: ref<ScriptedPuppet> = GameInstance.GetTargetingSystem(this.GetGameInstance()).GetLookAtObject(player, false, false) as ScriptedPuppet;
        if !GRDetection.IsEligible(target) {
            GRLog("Debug: el objetivo no es un pandillero valido");
            return null;
        }
        return target;
    }

    // Convierte en Nemesis al NPC al que apunta V.
    public func DebugPromoteLookAt() -> Bool {
        let target: ref<ScriptedPuppet> = this.GetLookAtNPC();
        if !IsDefined(target) {
            return false;
        }
        this.Promote(this.MakeCandidate(target), "debug");
        return true;
    }

    // Hace huir al NPC al que apunta V (sin comprobar vida ni companeros).
    public func DebugFleeLookAt() -> Bool {
        let target: ref<ScriptedPuppet> = this.GetLookAtNPC();
        if !IsDefined(target) {
            return false;
        }
        this.AddCombatant(target);
        this.MakeFlee(target);
        return true;
    }

    private func Promote(candidate: ref<GRCandidate>, origin: String) {
        if this.WasPromoted(candidate.entityID) {
            return;
        }
        ArrayPush(this.m_promoted, candidate.entityID);

        let evt: ref<GRNemesisEvent> = new GRNemesisEvent();
        evt.origin = origin;
        evt.nemesisId = candidate.nemesisId;
        evt.gang = candidate.gang;
        evt.recordID = TDBID.ToStringDEBUG(candidate.recordID);
        evt.appearance = NameToString(candidate.appearance);
        evt.gender = NameToString(candidate.gender);
        evt.health = candidate.health;
        evt.posX = candidate.position.X;
        evt.posY = candidate.position.Y;
        evt.posZ = candidate.position.Z;
        ArrayPush(this.m_pending, evt);
        GRLog("Nuevo Nemesis (" + origin + "): " + evt.gang + " " + evt.recordID);
    }

    // -------------------------------------------------------------------------
    // API para CET
    // -------------------------------------------------------------------------
    public func GetPendingCount() -> Int32 {
        return ArraySize(this.m_pending);
    }

    public func GetPending(index: Int32) -> ref<GRNemesisEvent> {
        return this.m_pending[index];
    }

    public func ClearPending() {
        ArrayClear(this.m_pending);
    }

    // Bandas que pelean contra V en este combate, separadas por comas (para los gigs).
    public func GetFightGangs() -> String {
        let result: String = "";
        for combatant in this.m_combatants {
            if IsDefined(combatant) {
                let gang: String = GRDetection.GetGang(combatant);
                if StrLen(gang) > 0 && !StrContains(result, gang) {
                    result += (StrLen(result) > 0 ? "," : "") + gang;
                }
            }
        }
        return result;
    }

    public func GetCandidateCount() -> Int32 {
        return ArraySize(this.m_candidates);
    }

    public func Notify(text: String) {
        let msg: SimpleScreenMessage;
        msg.isShown = true;
        msg.duration = 6.0;
        msg.message = text;
        let defs = GetAllBlackboardDefs();
        GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(defs.UI_Notifications).SetVariant(defs.UI_Notifications.WarningMessage, ToVariant(msg), true);
    }
}

// -----------------------------------------------------------------------------
// Hooks (mismas firmas que ya envuelven otros mods instalados)
// -----------------------------------------------------------------------------
@wrapMethod(HitReactionComponent)
public func EvaluateHit(newHitEvent: ref<gameHitEvent>) -> Void {
    wrappedMethod(newHitEvent);
    if !IsDefined(newHitEvent) || !IsDefined(newHitEvent.attackData) {
        return;
    }
    // Un pandillero hiere a V: se recuerda como posible asesino y como participante.
    if IsDefined(newHitEvent.target as PlayerPuppet) {
        let attacker: ref<ScriptedPuppet> = newHitEvent.attackData.GetInstigator() as ScriptedPuppet;
        if IsDefined(attacker) {
            let det: ref<GRDetection> = GRDetection.Get(attacker.GetGame());
            if IsDefined(det) {
                det.OnNPCHitPlayer(attacker);
            }
        }
        return;
    }
    // V hiere a un pandillero.
    if IsDefined(newHitEvent.attackData.GetInstigator() as PlayerPuppet) {
        let npc: ref<ScriptedPuppet> = newHitEvent.target as ScriptedPuppet;
        if IsDefined(npc) {
            let system: ref<GRDetection> = GRDetection.Get(npc.GetGame());
            if IsDefined(system) {
                system.OnPlayerHitNPC(npc);
            }
        }
    }
}

@wrapMethod(NPCPuppet)
protected cb func OnDeath(evt: ref<gameDeathEvent>) -> Bool {
    let system: ref<GRDetection> = GRDetection.Get(this.GetGame());
    if IsDefined(system) {
        system.OnNPCDeath(this);
    }
    return wrappedMethod(evt);
}

@wrapMethod(PlayerPuppet)
protected cb func OnCombatStateChanged(newState: Int32) -> Bool {
    let wasInCombat: Bool = this.IsInCombat();
    let result: Bool = wrappedMethod(newState);
    if wasInCombat && newState != 1 {
        let system: ref<GRDetection> = GRDetection.Get(this.GetGame());
        if IsDefined(system) {
            system.OnPlayerCombatEnded();
        }
    }
    return result;
}
