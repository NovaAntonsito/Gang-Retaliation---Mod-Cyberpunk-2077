module GangRetaliation

// Barra de jefe del juego (BossHealthBarGameController) para los Némesis.
// El juego solo la muestra si IsBoss() o rareza MaxTac; aquí se deja pasar
// también a los Némesis vivos (no a su escolta) y se pone su nombre completo.

public func GRIsBossBarNemesis(puppet: ref<NPCPuppet>) -> Bool {
    if !IsDefined(puppet) {
        return false;
    }
    let settings: ref<GRSettings> = GRSettings.Get(puppet.GetGame());
    if IsDefined(settings) && (!settings.enabled || !settings.bossBar) {
        return false;
    }
    let spawner: ref<GRSpawner> = GRSpawner.Get(puppet.GetGame());
    return IsDefined(spawner) && spawner.GetNemesisId(puppet.GetEntityID()) > 0;
}

// Avisa al HUD del jugador para que añada (o reevalúe, si combatEnded) la barra.
public func GRNotifyBossBar(player: ref<GameObject>, npc: ref<GameObject>, combatEnded: Bool) {
    if !IsDefined(player) {
        return;
    }
    let evt: ref<BossCombatNotifier> = new BossCombatNotifier();
    evt.bossEntity = npc;
    evt.combatEnded = combatEnded;
    player.QueueEvent(evt);
}

@wrapMethod(BossHealthBarGameController)
protected cb func OnDamageDealt(evt: ref<gameTargetDamageEvent>) -> Bool {
    let result: Bool = wrappedMethod(evt);
    let puppet: ref<NPCPuppet> = evt.target as NPCPuppet;
    if GRIsBossBarNemesis(puppet) && !ScriptedPuppet.IsDefeated(puppet) && !puppet.IsDead() {
        this.AddBoss(puppet);
    }
    return result;
}

@wrapMethod(BossHealthBarGameController)
private final func AddBoss(boss: ref<NPCPuppet>) -> Void {
    if !GRIsBossBarNemesis(boss) {
        wrappedMethod(boss);
        return;
    }
    if ArrayContains(this.m_bossPuppets, boss) {
        if boss != this.m_boss {
            this.ShowBossHealthBar(boss, true);
        }
        return;
    }
    ArrayPush(this.m_bossPuppets, boss);
    this.ShowBossHealthBar(boss, false);
}

@wrapMethod(BossHealthBarGameController)
private final func ShowBossHealthBar(puppet: ref<NPCPuppet>, useSilentUpdate: Bool) -> Void {
    if !GRIsBossBarNemesis(puppet) {
        wrappedMethod(puppet, useSilentUpdate);
        return;
    }
    if !ScriptedPuppet.IsAlive(puppet) {
        return;
    }
    let playUnfoldAnim: Bool = !IsDefined(this.m_boss);
    this.UnregisterPreviousBoss();
    this.RegisterToNewBoss(puppet, useSilentUpdate);
    this.m_root.SetVisible(true);
    if playUnfoldAnim {
        if IsDefined(this.m_foldAnimation) && this.m_foldAnimation.IsPlaying() {
            this.m_foldAnimation.UnregisterFromAllCallbacks(inkanimEventType.OnFinish);
            this.m_foldAnimation.Stop();
        }
        if !IsDefined(this.m_unfoldAnimation) || !this.m_unfoldAnimation.IsPlaying() {
            this.m_unfoldAnimation = this.PlayLibraryAnimation(n"unfold");
        }
    }
}

@wrapMethod(BossHealthBarGameController)
private final func RegisterToNewBoss(boss: ref<NPCPuppet>, useSilentUpdate: Bool) -> Void {
    wrappedMethod(boss, useSilentUpdate);
    let spawner: ref<GRSpawner> = GRSpawner.Get(boss.GetGame());
    if IsDefined(spawner) {
        let name: String = spawner.GetNemesisName(boss.GetEntityID());
        if StrLen(name) > 0 {
            inkTextRef.SetText(this.m_bossName, name);
        }
    }
}
