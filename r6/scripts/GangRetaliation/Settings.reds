module GangRetaliation

@if(ModuleExists("ModSettingsModule"))
public func GRRegisterSettingsListener(listener: ref<IScriptable>) {
    ModSettings.RegisterListenerToClass(listener);
    ModSettings.RegisterListenerToModifications(listener);
}

@if(ModuleExists("ModSettingsModule"))
public func GRUnregisterSettingsListener(listener: ref<IScriptable>) {
    ModSettings.UnregisterListenerToClass(listener);
    ModSettings.UnregisterListenerToModifications(listener);
}

@if(!ModuleExists("ModSettingsModule"))
public func GRRegisterSettingsListener(listener: ref<IScriptable>) {}

@if(!ModuleExists("ModSettingsModule"))
public func GRUnregisterSettingsListener(listener: ref<IScriptable>) {}

public class GRSettings extends ScriptableSystem {
    public static func Get(gi: GameInstance) -> ref<GRSettings> {
        return GameInstance.GetScriptableSystemsContainer(gi).Get(n"GangRetaliation.GRSettings") as GRSettings;
    }

    private func OnAttach() {
        GRRegisterSettingsListener(this);
    }

    private func OnDetach() {
        GRUnregisterSettingsListener(this);
    }

    public func OnModSettingsChange() {
        GRLog("Ajustes actualizados");
    }

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatGeneral")
    @runtimeProperty("ModSettings.category.order", "10")
    @runtimeProperty("ModSettings.displayName", "GR-SetEnabled")
    @runtimeProperty("ModSettings.description", "GR-SetEnabledDesc")
    public let enabled: Bool = true;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatGeneral")
    @runtimeProperty("ModSettings.category.order", "10")
    @runtimeProperty("ModSettings.displayName", "GR-SetMaxPerGang")
    @runtimeProperty("ModSettings.description", "GR-SetMaxPerGangDesc")
    @runtimeProperty("ModSettings.step", "1")
    @runtimeProperty("ModSettings.min", "3")
    @runtimeProperty("ModSettings.max", "12")
    public let maxPerGang: Int32 = 8;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatGeneral")
    @runtimeProperty("ModSettings.category.order", "10")
    @runtimeProperty("ModSettings.displayName", "GR-SetBossBar")
    @runtimeProperty("ModSettings.description", "GR-SetBossBarDesc")
    public let bossBar: Bool = true;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatTriggers")
    @runtimeProperty("ModSettings.category.order", "20")
    @runtimeProperty("ModSettings.displayName", "GR-SetEscapeHealth")
    @runtimeProperty("ModSettings.description", "GR-SetEscapeHealthDesc")
    @runtimeProperty("ModSettings.step", "5")
    @runtimeProperty("ModSettings.min", "5")
    @runtimeProperty("ModSettings.max", "50")
    public let escapeHealthPercent: Int32 = 25;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatTriggers")
    @runtimeProperty("ModSettings.category.order", "20")
    @runtimeProperty("ModSettings.displayName", "GR-SetLastManFlees")
    @runtimeProperty("ModSettings.description", "GR-SetLastManFleesDesc")
    public let lastManFlees: Bool = true;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatTriggers")
    @runtimeProperty("ModSettings.category.order", "20")
    @runtimeProperty("ModSettings.displayName", "GR-SetFleeHealth")
    @runtimeProperty("ModSettings.description", "GR-SetFleeHealthDesc")
    @runtimeProperty("ModSettings.step", "5")
    @runtimeProperty("ModSettings.min", "10")
    @runtimeProperty("ModSettings.max", "60")
    public let fleeHealthPercent: Int32 = 35;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatAmbush")
    @runtimeProperty("ModSettings.category.order", "30")
    @runtimeProperty("ModSettings.displayName", "GR-SetAmbushEnabled")
    @runtimeProperty("ModSettings.description", "GR-SetAmbushEnabledDesc")
    public let ambushEnabled: Bool = true;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatAmbush")
    @runtimeProperty("ModSettings.category.order", "30")
    @runtimeProperty("ModSettings.displayName", "GR-SetAmbushCooldown")
    @runtimeProperty("ModSettings.description", "GR-SetAmbushCooldownDesc")
    @runtimeProperty("ModSettings.step", "5")
    @runtimeProperty("ModSettings.min", "5")
    @runtimeProperty("ModSettings.max", "120")
    public let ambushCooldownMinutes: Int32 = 20;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatAmbush")
    @runtimeProperty("ModSettings.category.order", "30")
    @runtimeProperty("ModSettings.displayName", "GR-SetAmbushChance")
    @runtimeProperty("ModSettings.description", "GR-SetAmbushChanceDesc")
    @runtimeProperty("ModSettings.step", "5")
    @runtimeProperty("ModSettings.min", "5")
    @runtimeProperty("ModSettings.max", "100")
    public let ambushChancePercent: Int32 = 25;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatAmbush")
    @runtimeProperty("ModSettings.category.order", "30")
    @runtimeProperty("ModSettings.displayName", "GR-SetAmbushEscorts")
    @runtimeProperty("ModSettings.description", "GR-SetAmbushEscortsDesc")
    @runtimeProperty("ModSettings.step", "1")
    @runtimeProperty("ModSettings.min", "0")
    @runtimeProperty("ModSettings.max", "4")
    public let ambushMaxEscorts: Int32 = 2;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatAmbush")
    @runtimeProperty("ModSettings.category.order", "30")
    @runtimeProperty("ModSettings.displayName", "GR-SetAmbushSms")
    @runtimeProperty("ModSettings.description", "GR-SetAmbushSmsDesc")
    @runtimeProperty("ModSettings.step", "15")
    @runtimeProperty("ModSettings.min", "0")
    @runtimeProperty("ModSettings.max", "180")
    public let ambushSmsSeconds: Int32 = 60;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatGig")
    @runtimeProperty("ModSettings.category.order", "40")
    @runtimeProperty("ModSettings.displayName", "GR-SetGigEnabled")
    @runtimeProperty("ModSettings.description", "GR-SetGigEnabledDesc")
    public let gigEnabled: Bool = true;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatGig")
    @runtimeProperty("ModSettings.category.order", "40")
    @runtimeProperty("ModSettings.displayName", "GR-SetGigChance")
    @runtimeProperty("ModSettings.description", "GR-SetGigChanceDesc")
    @runtimeProperty("ModSettings.step", "5")
    @runtimeProperty("ModSettings.min", "5")
    @runtimeProperty("ModSettings.max", "100")
    public let gigChancePercent: Int32 = 50;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatHierarchy")
    @runtimeProperty("ModSettings.category.order", "50")
    @runtimeProperty("ModSettings.displayName", "GR-SetVacancyDays")
    @runtimeProperty("ModSettings.description", "GR-SetVacancyDaysDesc")
    @runtimeProperty("ModSettings.step", "1")
    @runtimeProperty("ModSettings.min", "1")
    @runtimeProperty("ModSettings.max", "7")
    public let vacancyDays: Int32 = 2;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatHierarchy")
    @runtimeProperty("ModSettings.category.order", "50")
    @runtimeProperty("ModSettings.displayName", "GR-SetFeudChance")
    @runtimeProperty("ModSettings.description", "GR-SetFeudChanceDesc")
    @runtimeProperty("ModSettings.step", "5")
    @runtimeProperty("ModSettings.min", "0")
    @runtimeProperty("ModSettings.max", "100")
    public let feudChancePercent: Int32 = 25;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatHierarchy")
    @runtimeProperty("ModSettings.category.order", "50")
    @runtimeProperty("ModSettings.displayName", "GR-SetPoliceChance")
    @runtimeProperty("ModSettings.description", "GR-SetPoliceChanceDesc")
    @runtimeProperty("ModSettings.step", "5")
    @runtimeProperty("ModSettings.min", "0")
    @runtimeProperty("ModSettings.max", "100")
    public let policeChancePercent: Int32 = 10;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatHierarchy")
    @runtimeProperty("ModSettings.category.order", "50")
    @runtimeProperty("ModSettings.displayName", "GR-SetRaidChance")
    @runtimeProperty("ModSettings.description", "GR-SetRaidChanceDesc")
    @runtimeProperty("ModSettings.step", "5")
    @runtimeProperty("ModSettings.min", "0")
    @runtimeProperty("ModSettings.max", "100")
    public let raidChancePercent: Int32 = 10;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatHierarchy")
    @runtimeProperty("ModSettings.category.order", "50")
    @runtimeProperty("ModSettings.displayName", "GR-SetReturnChance")
    @runtimeProperty("ModSettings.description", "GR-SetReturnChanceDesc")
    @runtimeProperty("ModSettings.step", "5")
    @runtimeProperty("ModSettings.min", "0")
    @runtimeProperty("ModSettings.max", "100")
    public let returnChancePercent: Int32 = 40;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatWar")
    @runtimeProperty("ModSettings.category.order", "60")
    @runtimeProperty("ModSettings.displayName", "GR-SetWarChance")
    @runtimeProperty("ModSettings.description", "GR-SetWarChanceDesc")
    @runtimeProperty("ModSettings.step", "5")
    @runtimeProperty("ModSettings.min", "0")
    @runtimeProperty("ModSettings.max", "100")
    public let warChancePercent: Int32 = 30;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatWar")
    @runtimeProperty("ModSettings.category.order", "60")
    @runtimeProperty("ModSettings.displayName", "GR-SetSkirmishChance")
    @runtimeProperty("ModSettings.description", "GR-SetSkirmishChanceDesc")
    @runtimeProperty("ModSettings.step", "5")
    @runtimeProperty("ModSettings.min", "0")
    @runtimeProperty("ModSettings.max", "100")
    public let skirmishChancePercent: Int32 = 35;

    @runtimeProperty("ModSettings.mod", "GR-ModName")
    @runtimeProperty("ModSettings.category", "GR-CatDebug")
    @runtimeProperty("ModSettings.category.order", "90")
    @runtimeProperty("ModSettings.displayName", "GR-SetDebugLog")
    @runtimeProperty("ModSettings.description", "GR-SetDebugLogDesc")
    public let debugLog: Bool = false;
}
