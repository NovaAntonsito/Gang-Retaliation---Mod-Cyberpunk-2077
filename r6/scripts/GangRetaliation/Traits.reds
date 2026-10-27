module GangRetaliation

public class GRTraits extends ScriptableSystem {
    private let m_nemesisIDs: array<Int32>;
    private let m_traits: array<array<String>>;

    private let m_reveals: array<String>;

    private let m_shown: array<String>;

    public static func Get(gi: GameInstance) -> ref<GRTraits> {
        return GameInstance.GetScriptableSystemsContainer(gi).Get(n"GangRetaliation.GRTraits") as GRTraits;
    }

    private func IndexOf(nemesisId: Int32) -> Int32 {
        let i: Int32 = 0;
        while i < ArraySize(this.m_nemesisIDs) {
            if this.m_nemesisIDs[i] == nemesisId {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    public func SetTraits(nemesisId: Int32, csv: String) {
        let list: array<String> = StrSplit(csv, ",");
        let index: Int32 = this.IndexOf(nemesisId);
        if index >= 0 {
            this.m_traits[index] = list;
        } else {
            ArrayPush(this.m_nemesisIDs, nemesisId);
            ArrayPush(this.m_traits, list);
        }
    }

    public func Has(nemesisId: Int32, trait: String) -> Bool {
        let index: Int32 = this.IndexOf(nemesisId);
        if index < 0 {
            return false;
        }
        for t in this.m_traits[index] {
            if Equals(t, trait) {
                return true;
            }
        }
        return false;
    }

    private func Reveal(nemesisId: Int32, what: String) {
        let key: String = IntToString(nemesisId) + ":" + what;
        for shown in this.m_shown {
            if Equals(shown, key) {
                return;
            }
        }
        ArrayPush(this.m_shown, key);
        ArrayPush(this.m_reveals, key);
    }

    private static func DamageOf(hitEvent: ref<gameHitEvent>, type: gamedataDamageType) -> Float {
        let values: array<Float> = hitEvent.attackComputed.GetAttackValues();
        let index: Int32 = EnumInt(type);
        if index >= 0 && index < ArraySize(values) {
            return values[index];
        }
        return 0.0;
    }

    private func ScaleType(nemesisId: Int32, hitEvent: ref<gameHitEvent>, trait: String, mult: Float, type: gamedataDamageType) {
        if this.Has(nemesisId, trait) && GRTraits.DamageOf(hitEvent, type) > 0.0 {
            hitEvent.attackComputed.MultAttackValue(mult, type);
            this.Reveal(nemesisId, trait);
            GRTaunts.OnTrait(hitEvent, trait);
        }
    }

    private func ScaleAll(nemesisId: Int32, hitEvent: ref<gameHitEvent>, trait: String, mult: Float) {
        if this.Has(nemesisId, trait) {
            hitEvent.attackComputed.MultAttackValue(mult);
            this.Reveal(nemesisId, trait);
            GRTaunts.OnTrait(hitEvent, trait);
        }
    }

    private func ApplyDefense(nemesisId: Int32, hitEvent: ref<gameHitEvent>) {
        this.ScaleType(nemesisId, hitEvent, "fireproof", 0.25, gamedataDamageType.Thermal);
        this.ScaleType(nemesisId, hitEvent, "fear_fire", 2.0, gamedataDamageType.Thermal);
        this.ScaleType(nemesisId, hitEvent, "insulated", 0.25, gamedataDamageType.Electric);
        this.ScaleType(nemesisId, hitEvent, "weak_shock", 2.0, gamedataDamageType.Electric);
        this.ScaleType(nemesisId, hitEvent, "toxproof", 0.25, gamedataDamageType.Chemical);
        this.ScaleType(nemesisId, hitEvent, "weak_tox", 2.0, gamedataDamageType.Chemical);

        let attack: ref<AttackData> = hitEvent.attackData;
        let attackType: gamedataAttackType = attack.GetAttackType();
        if AttackData.IsMelee(attackType) {
            this.ScaleAll(nemesisId, hitEvent, "brawler", 0.5);
            this.ScaleAll(nemesisId, hitEvent, "weak_melee", 1.75);
        }
        if AttackData.IsExplosion(attackType) {
            this.ScaleAll(nemesisId, hitEvent, "blastproof", 0.4);
            this.ScaleAll(nemesisId, hitEvent, "weak_blast", 2.0);
        }
        if attack.HasFlag(hitFlag.QuickHack) {
            this.ScaleAll(nemesisId, hitEvent, "firewall", 0.3);
            this.ScaleAll(nemesisId, hitEvent, "weak_hack", 2.0);
        }
        if attack.HasFlag(hitFlag.Headshot) {
            this.ScaleAll(nemesisId, hitEvent, "hardhead", 0.5);
            this.ScaleAll(nemesisId, hitEvent, "glass_jaw", 1.75);
        }
        this.ScaleAll(nemesisId, hitEvent, "tough", 0.75);
    }

    public static func OnHit(hitEvent: ref<gameHitEvent>) {
        if !IsDefined(hitEvent) || !IsDefined(hitEvent.target) || !IsDefined(hitEvent.attackData) || !IsDefined(hitEvent.attackComputed) {
            return;
        }
        let instigator: wref<GameObject> = hitEvent.attackData.GetInstigator();
        if !IsDefined(instigator) {
            return;
        }
        let gi: GameInstance = hitEvent.target.GetGame();
        let spawner: ref<GRSpawner> = GRSpawner.Get(gi);
        let traits: ref<GRTraits> = GRTraits.Get(gi);
        if !IsDefined(spawner) || !IsDefined(traits) || spawner.GetSpawnedCount() == 0 {
            return;
        }

        if instigator.IsPlayer() {
            let targetId: Int32 = spawner.GetNemesisId(hitEvent.target.GetEntityID());
            if targetId > 0 {
                traits.ApplyDefense(targetId, hitEvent);

                let attack: ref<AttackData> = hitEvent.attackData;
                spawner.RecordPlayerHit(targetId, attack.HasFlag(hitFlag.Headshot) || AttackData.IsExplosion(attack.GetAttackType()));
            }
        } else {
            if hitEvent.target.IsPlayer() {
                let attackerId: Int32 = spawner.GetNemesisId(instigator.GetEntityID());
                if attackerId > 0 {
                    traits.ScaleAll(attackerId, hitEvent, "deadly", 1.3);
                }
            }
        }
    }

    public func OnScanned(npc: ref<ScriptedPuppet>) {
        let spawner: ref<GRSpawner> = GRSpawner.Get(this.GetGameInstance());
        if !IsDefined(spawner) {
            return;
        }
        let nemesisId: Int32 = spawner.GetNemesisId(npc.GetEntityID());
        if nemesisId > 0 {
            this.Reveal(nemesisId, "scan");
        }
    }

    public func GetRevealCount() -> Int32 {
        return ArraySize(this.m_reveals);
    }

    public func GetReveal(index: Int32) -> String {
        return this.m_reveals[index];
    }

    public func ClearReveals() {
        ArrayClear(this.m_reveals);
    }
}

@wrapMethod(DamageSystem)
private final func CalculateSourceModifiers(hitEvent: ref<gameHitEvent>, cache: ref<CacheData>) -> Void {
    wrappedMethod(hitEvent, cache);
    GRTraits.OnHit(hitEvent);
}

@wrapMethod(ScriptedPuppet)
protected cb func OnScanningEvent(evt: ref<ScanningEvent>) -> Bool {
    let result: Bool = wrappedMethod(evt);
    if IsDefined(evt) && (Equals(evt.state, gameScanningState.Complete) || Equals(evt.state, gameScanningState.ShallowComplete)) {
        let traits: ref<GRTraits> = GRTraits.Get(this.GetGame());
        if IsDefined(traits) {
            traits.OnScanned(this);
        }
    }
    return result;
}
