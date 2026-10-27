module GangRetaliation

public class GRTaunts extends ScriptableSystem {
    private let m_lastTaunt: Float;

    private let m_lowSaid: array<EntityID>;
    private let m_playerLowSaid: Bool;

    public static func Get(gi: GameInstance) -> ref<GRTaunts> {
        return GameInstance.GetScriptableSystemsContainer(gi).Get(n"GangRetaliation.GRTaunts") as GRTaunts;
    }

    private func Now() -> Float {
        return EngineTime.ToFloat(GameInstance.GetSimTime(this.GetGameInstance()));
    }

    private func HealthPercent(obj: ref<GameObject>) -> Float {
        return GameInstance.GetStatPoolsSystem(this.GetGameInstance()).GetStatPoolValue(Cast<StatsObjectID>(obj.GetEntityID()), gamedataStatPoolType.Health, true);
    }

    private func Say(npc: ref<GameObject>, key: String, variants: Int32, cooldown: Float, chance: Float) -> Bool {
        let spawner: ref<GRSpawner> = GRSpawner.Get(this.GetGameInstance());
        let system: ref<GRSystem> = GRSystem.Get(this.GetGameInstance());
        if !IsDefined(npc) || !IsDefined(spawner) || !IsDefined(system) {
            return false;
        }
        let now: Float = this.Now();
        if now - this.m_lastTaunt < cooldown || RandF() > chance {
            return false;
        }
        let name: String = spawner.GetNemesisName(npc.GetEntityID());
        if StrLen(name) == 0 {
            return false;
        }
        let fullKey: String = key + "-" + IntToString(Min(RandRange(1, variants + 1), variants));
        let text: String = system.GetText(fullKey);
        if StrLen(text) == 0 || Equals(text, fullKey) {
            return false;
        }
        GRSpeech.Say(npc, name, text, 4.0);
        this.m_lastTaunt = now;
        return true;
    }

    public static func OnTrait(hitEvent: ref<gameHitEvent>, trait: String) {
        let speaker: ref<GameObject> = Equals(trait, "deadly") ? hitEvent.attackData.GetInstigator() : hitEvent.target;
        if !IsDefined(speaker) {
            return;
        }
        let taunts: ref<GRTaunts> = GRTaunts.Get(speaker.GetGame());
        if IsDefined(taunts) {
            taunts.Say(speaker, "GR-Taunt-" + trait, 2, 10.0, 0.6);
        }
    }

    public func CheckHealth(npc: ref<ScriptedPuppet>) {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) || !player.IsInCombat() {
            return;
        }
        if !ArrayContains(this.m_lowSaid, npc.GetEntityID()) && this.HealthPercent(npc) < 30.0 {
            if this.Say(npc, "GR-Taunt-Low", 3, 0.0, 1.0) {
                ArrayPush(this.m_lowSaid, npc.GetEntityID());
            }
        }
        if !this.m_playerLowSaid && this.HealthPercent(player) < 25.0 {
            if this.Say(npc, "GR-Taunt-PlayerLow", 3, 4.0, 1.0) {
                this.m_playerLowSaid = true;
            }
        }
    }

    public func Reset() {
        ArrayClear(this.m_lowSaid);
        this.m_playerLowSaid = false;
    }
}
