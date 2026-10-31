module GangRetaliation

import Codeware.UI.VirtualResolutionWatcher

// HUD de combate: barra del enemigo mas grande con la linea de huida, y panel AMENAZAS con los hostiles
// que tienen a V como objetivo. No toca healthbarWidgetGameController (vida de V; Cyberware-EX y Dark
// Future lo modifican).

// --- Barra sobre la cabeza del enemigo (npcnameplate.inkwidget: healthBar > wrapper > bg_black 150x7) ---

@addField(NameplateBarLogicController)
private let m_grFleeMark: wref<inkRectangle>;

@addMethod(NameplateBarLogicController)
public func GRSetFleeMark(fraction: Float, show: Bool) {
    if !IsDefined(this.m_grFleeMark) {
        if !show {
            return;
        }
        let wrapper: ref<inkCompoundWidget> = this.m_rootWidget.GetWidgetByPathName(n"wrapper") as inkCompoundWidget;
        if !IsDefined(wrapper) {
            return;
        }
        let mark: ref<inkRectangle> = new inkRectangle();
        mark.SetName(n"gr_flee_mark");
        mark.SetSize(new Vector2(2.0, 13.0));
        mark.SetHAlign(inkEHorizontalAlign.Left);
        mark.SetVAlign(inkEVerticalAlign.Center);
        mark.SetTintColor(GRHud.Yellow());
        mark.Reparent(wrapper);
        this.m_grFleeMark = mark;
    }
    let width: Float = 150.0;
    let bg: ref<inkWidget> = this.m_rootWidget.GetWidgetByPathName(n"wrapper/bg_black");
    if IsDefined(bg) && bg.GetWidth() > 0.0 {
        width = bg.GetWidth();
    }
    this.m_grFleeMark.SetMargin(new inkMargin(width * fraction - 1.0, 0.0, 0.0, 0.0));
    this.m_grFleeMark.SetVisible(show);
}

@addField(NameplateVisualsLogicController)
private let m_grCheckedID: EntityID;

@addField(NameplateVisualsLogicController)
private let m_grCheckedAt: Float;

@addField(NameplateVisualsLogicController)
private let m_grCanFlee: Bool;

@wrapMethod(NameplateVisualsLogicController)
public final func SetVisualData(puppet: ref<GameObject>, const incomingData: script_ref<NPCNextToTheCrosshair>, opt isNewNpc: Bool) -> Void {
    wrappedMethod(puppet, incomingData, isNewNpc);
    this.GRUpdateNameplate(this.m_cachedPuppet as ScriptedPuppet);
}

@addMethod(NameplateVisualsLogicController)
private func GRUpdateNameplate(npc: ref<ScriptedPuppet>) {
    if !IsDefined(npc) {
        if IsDefined(this.m_healthController) {
            this.m_healthController.GRSetFleeMark(0.0, false);
        }
        return;
    }
    let gi: GameInstance = npc.GetGame();
    let settings: ref<GRSettings> = GRSettings.Get(gi);
    if !IsDefined(settings) {
        return;
    }
    let scale: Float = ClampF(settings.nameplateScale, 1.0, 2.0);
    inkWidgetRef.SetScale(this.m_healthbarWidget, new Vector2(scale, scale));

    // SetVisualData llega muy seguido: el bloqueo de huida se recalcula al cambiar de NPC o cada 0.5 s.
    let now: Float = EngineTime.ToFloat(GameInstance.GetSimTime(gi));
    if npc.GetEntityID() != this.m_grCheckedID || now - this.m_grCheckedAt > 0.5 {
        let det: ref<GRDetection> = GRDetection.Get(gi);
        this.m_grCanFlee = IsDefined(det) && StrLen(det.GetFleeBlocker(npc)) == 0;
        this.m_grCheckedID = npc.GetEntityID();
        this.m_grCheckedAt = now;
    }
    if IsDefined(this.m_healthController) {
        this.m_healthController.GRSetFleeMark(Cast<Float>(settings.fleeHealthPercent) / 100.0, settings.fleeMarkEnabled && this.m_grCanFlee);
    }
}

// --- Panel AMENAZAS (capa inkHUDLayer, coordenadas de 3840x2160) ---

public class GRThreatRow {
    public let root: ref<inkVerticalPanel>;
    public let gang: ref<inkRectangle>;
    public let tag: ref<inkText>;
    public let name: ref<inkText>;
    public let distance: ref<inkText>;
    public let fill: ref<inkRectangle>;
    public let mark: ref<inkRectangle>;
}

public class GRThreat {
    public let npc: wref<ScriptedPuppet>;
    public let health: Float;
    public let distance: Float;
    public let nemesisName: String;
    public let isTarget: Bool;
    public let canFlee: Bool;
}

public class GRHudTick extends DelayCallback {
    public let hud: wref<GRHud>;

    public func Call() -> Void {
        if IsDefined(this.hud) {
            this.hud.Tick();
        }
    }
}

// Modo dios de debug: el GodModeSystem registra la entrada GRDebug pero HasGodMode da false para V (algo lo
// anula), asi que el dano no la respeta. Se corta el golpe aca, en el mismo punto donde el juego marca a los
// invulnerables.
@wrapMethod(DamageSystem)
private final func InvulnerabilityCheck(hitEvent: ref<gameHitEvent>, cache: ref<CacheData>) -> Void {
    wrappedMethod(hitEvent, cache);
    if IsDefined(hitEvent.target) && hitEvent.target.IsPlayer() {
        let hud: ref<GRHud> = GRHud.Get(hitEvent.target.GetGame());
        if IsDefined(hud) && hud.IsGodMode() {
            hitEvent.attackData.AddFlag(hitFlag.DealNoDamage, n"GRDebug");
        }
    }
}

public class GRHud extends ScriptableSystem {
    public static func Get(gi: GameInstance) -> ref<GRHud> {
        return GameInstance.GetScriptableSystemsContainer(gi).Get(n"GangRetaliation.GRHud") as GRHud;
    }

    private let m_box: ref<inkCanvas>;
    private let m_bg: ref<inkRectangle>;
    private let m_panel: ref<inkVerticalPanel>;
    private let m_watcher: ref<VirtualResolutionWatcher>;
    private let m_header: ref<inkHorizontalPanel>;
    // Medidas guardadas la primera vez que se obtienen: oculto, GetDesiredSize da 0.
    private let m_headerH: Float;
    private let m_rowH: Float;
    private let m_moreH: Float;
    private let m_count: ref<inkText>;
    private let m_more: ref<inkText>;
    private let m_rows: array<ref<GRThreatRow>>;
    private let m_lastThreatAt: Float;
    private let m_session: Int32;
    private let m_radialListener: ref<CallbackHandle>;
    private let m_debugInfo: String;
    private let m_godAdd: String;

    // Filas creadas; cuantas se muestran lo decide threatPanelRows (Mod Settings).
    private let c_maxRows: Int32 = 10;
    private let c_barWidth: Float = 380.0;
    private let c_padX: Float = 24.0;
    private let c_padY: Float = 18.0;

    public static func Yellow() -> HDRColor {
        return new HDRColor(1.0, 0.82, 0.4, 1.0);
    }

    private static func White() -> HDRColor {
        return new HDRColor(0.91, 0.93, 0.95, 1.0);
    }

    private static func Grey() -> HDRColor {
        return new HDRColor(0.6, 0.64, 0.7, 1.0);
    }

    private static func HealthRed() -> HDRColor {
        return new HDRColor(1.1761, 0.3809, 0.3476, 1.0);
    }

    private static func Amber() -> HDRColor {
        return new HDRColor(0.96, 0.65, 0.14, 1.0);
    }

    private static func Gold() -> HDRColor {
        return new HDRColor(0.89, 0.69, 0.29, 1.0);
    }

    private static func GangColor(gang: String) -> HDRColor {
        switch gang {
            case "Maelstrom": return new HDRColor(0.9, 0.28, 0.3, 1.0);
            case "TygerClaws": return new HDRColor(0.2, 0.85, 0.75, 1.0);
            case "Valentinos": return new HDRColor(0.95, 0.75, 0.25, 1.0);
            case "SixthStreet": return new HDRColor(0.35, 0.55, 1.0, 1.0);
            case "Animals": return new HDRColor(0.6, 0.85, 0.3, 1.0);
            case "VoodooBoys": return new HDRColor(0.55, 0.45, 1.0, 1.0);
            case "Wraiths": return new HDRColor(0.9, 0.55, 0.3, 1.0);
            case "Scavengers": return new HDRColor(0.75, 0.75, 0.75, 1.0);
            case "Barghest": return new HDRColor(0.65, 0.7, 0.45, 1.0);
            default: return new HDRColor(0.45, 0.5, 0.58, 1.0);
        }
    }

    private func OnPlayerAttach(request: ref<PlayerAttachRequest>) {
        // Al cargar otra partida el HUD se rehace: se vuelve a crear el panel y se corta el tick anterior.
        this.m_session += 1;
        this.m_box = null;
        this.m_panel = null;
        ArrayClear(this.m_rows);
        // Rueda de armas (y otros menus radiales): el panel se oculta al instante mientras este abierta.
        let quickSlots: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UI_QuickSlotsData);
        if IsDefined(quickSlots) && !IsDefined(this.m_radialListener) {
            this.m_radialListener = quickSlots.RegisterListenerBool(GetAllBlackboardDefs().UI_QuickSlotsData.UIRadialContextRequest, this, n"OnRadialContextChange");
        }
        this.ScheduleTick();
    }

    protected cb func OnRadialContextChange(open: Bool) -> Bool {
        if open && IsDefined(this.m_box) {
            this.m_box.SetVisible(false);
        }
    }

    private func IsRadialOpen() -> Bool {
        let quickSlots: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UI_QuickSlotsData);
        return IsDefined(quickSlots) && quickSlots.GetBool(GetAllBlackboardDefs().UI_QuickSlotsData.UIRadialContextRequest);
    }

    private func ScheduleTick() {
        let tick: ref<GRHudTick> = new GRHudTick();
        tick.hud = this;
        // Con el panel a la vista, mas seguido para que las amenazas nuevas entren rapido.
        let visible: Bool = IsDefined(this.m_box) && this.m_box.IsVisible();
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(tick, visible ? 0.1 : 0.25, false);
    }

    public func Tick() {
        let session: Int32 = this.m_session;
        this.Update();
        if session == this.m_session {
            this.ScheduleTick();
        }
    }

    private func NewText(size: Int32, color: HDRColor, style: CName) -> ref<inkText> {
        let label: ref<inkText> = new inkText();
        label.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        label.SetFontStyle(style);
        label.SetFontSize(size);
        label.SetTintColor(color);
        return label;
    }

    private func T(key: String) -> String {
        let loc: ref<GRSystem> = GRSystem.Get(this.GetGameInstance());
        return IsDefined(loc) ? loc.GetText(key) : key;
    }

    // Como hace Dark Future: un slot de 3840x2160 que Codeware escala a la resolucion real, asi todo se
    // posiciona en coordenadas 4K y se ve del mismo tamano en cualquier pantalla.
    private func EnsurePanel() -> Bool {
        if IsDefined(this.m_panel) {
            return true;
        }
        let window: ref<inkCompoundWidget> = GameInstance.GetInkSystem().GetLayer(n"inkHUDLayer").GetVirtualWindow();
        let hudRoot: ref<inkCompoundWidget> = IsDefined(window) ? window.GetWidgetByPathName(n"Root") as inkCompoundWidget : null;
        if !IsDefined(hudRoot) {
            return false;
        }
        let slot: ref<inkCanvas> = new inkCanvas();
        slot.SetName(n"GangRetaliationFullScreenSlot");
        slot.SetSize(new Vector2(3840.0, 2160.0));
        slot.SetRenderTransformPivot(new Vector2(0.0, 0.0));
        slot.Reparent(hudRoot);
        this.m_watcher = new VirtualResolutionWatcher();
        this.m_watcher.Initialize(this.GetGameInstance());
        this.m_watcher.ScaleWidget(slot);

        // Recuadro: canvas con el tamano del contenido, que se le pone en cada tick (PlaceBox). inkFlex no
        // ajustaba y el contenido se montaba (mismo problema que en Menu.reds).
        let box: ref<inkCanvas> = new inkCanvas();
        box.SetName(n"gr_threats");
        box.SetAnchor(inkEAnchor.TopLeft);
        box.SetRenderTransformPivot(new Vector2(0.0, 0.0));
        box.SetSize(new Vector2(this.c_barWidth + 2.0 * this.c_padX, 200.0));
        box.SetVisible(false);
        let bg: ref<inkRectangle> = new inkRectangle();
        bg.SetAnchor(inkEAnchor.Fill);
        bg.SetTintColor(new HDRColor(0.043, 0.055, 0.075, 1.0));
        bg.Reparent(box);
        this.m_bg = bg;
        let border: ref<GRBorder> = new GRBorder();
        border.SetAnchor(inkEAnchor.Fill);
        border.SetThickness(2.0);
        border.SetTintColor(new HDRColor(0.145, 0.176, 0.224, 1.0));
        border.Reparent(box);

        let panel: ref<inkVerticalPanel> = new inkVerticalPanel();
        panel.SetAnchor(inkEAnchor.TopLeft);
        panel.SetFitToContent(true);
        panel.SetMargin(new inkMargin(this.c_padX, this.c_padY, 0.0, 0.0));
        panel.SetChildMargin(new inkMargin(0.0, 0.0, 0.0, 12.0));

        let header: ref<inkHorizontalPanel> = new inkHorizontalPanel();
        header.SetFitToContent(true);
        let title: ref<inkText> = this.NewText(30, GRHud.White(), n"Bold");
        title.SetText(this.T("GR-HudThreats"));
        title.SetMargin(new inkMargin(0.0, 0.0, 14.0, 0.0));
        title.Reparent(header);
        this.m_count = this.NewText(30, GRHud.HealthRed(), n"Bold");
        this.m_count.Reparent(header);
        header.Reparent(panel);
        this.m_header = header;

        let i: Int32 = 0;
        while i < this.c_maxRows {
            ArrayPush(this.m_rows, this.NewRow(panel));
            i += 1;
        }
        this.m_more = this.NewText(22, GRHud.Grey(), n"Medium");
        this.m_more.Reparent(panel);

        panel.Reparent(box);
        box.Reparent(slot);
        this.m_box = box;
        this.m_panel = panel;
        return true;
    }

    // Posicion en coordenadas 4K (threatPanelX/Y de Mod Settings), se lee en cada tick.
    private func PlaceBox(settings: ref<GRSettings>) {
        let x: Float = settings.threatPanelX;
        let y: Float = settings.threatPanelY;
        this.m_box.SetTranslation(x, y);
        this.m_box.SetScale(new Vector2(settings.threatPanelScale, settings.threatPanelScale));
        this.m_bg.SetOpacity(settings.threatPanelOpacity);
        this.m_debugInfo = "panel: x=" + FloatToStringPrec(x, 0) + " y=" + FloatToStringPrec(y, 0)
            + " scale=" + FloatToStringPrec(settings.threatPanelScale, 2)
            + " opacity=" + FloatToStringPrec(settings.threatPanelOpacity, 2) + " rows=" + IntToString(settings.threatPanelRows);
    }

    // Para el panel dev de CET: lo que el HUD esta usando de verdad en el ultimo tick visible.
    public func GetDebugInfo() -> String {
        return StrLen(this.m_debugInfo) > 0 ? this.m_debugInfo : "panel: not shown yet";
    }

    public func ToggleGodMode() -> Bool {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return false;
        }
        // Los dos tipos: Invulnerable corta el golpe, Immortal deja la vida en 1 si algo (otro mod) igual hace dano.
        let god: ref<GodModeSystem> = GameInstance.GetGodModeSystem(this.GetGameInstance());
        let id: EntityID = player.GetEntityID();
        if this.IsGodMode() {
            // Borra todas las entradas GRDebug (cada AddGodMode suma una).
            god.ClearGodMode(id, n"GRDebug");
            this.m_godAdd = "cleared";
        } else {
            let inv: Bool = god.AddGodMode(id, gameGodModeType.Invulnerable, n"GRDebug");
            let imm: Bool = god.AddGodMode(id, gameGodModeType.Immortal, n"GRDebug");
            this.m_godAdd = "add inv=" + ToString(inv) + " imm=" + ToString(imm);
        }
        GRLog("Debug: modo dios " + (this.IsGodMode() ? "ON" : "OFF") + " (" + this.GetGodModeInfo() + ")");
        return this.IsGodMode();
    }

    // Para el panel dev: fuentes de modo dios que el juego tiene registradas para V.
    public func GetGodModeInfo() -> String {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return "god: no player";
        }
        let god: ref<GodModeSystem> = GameInstance.GetGodModeSystem(this.GetGameInstance());
        let id: EntityID = player.GetEntityID();
        let sources: String = "";
        let inv: array<CName> = god.GetGodModeSources(id, gameGodModeType.Invulnerable);
        for source in inv {
            sources += NameToString(source) + " ";
        }
        return "god: inv=" + IntToString(Cast<Int32>(god.GetGodModeCount(id, gameGodModeType.Invulnerable)))
            + " imm=" + IntToString(Cast<Int32>(god.GetGodModeCount(id, gameGodModeType.Immortal)))
            + " src=[" + sources + "] on=" + ToString(this.IsGodMode()) + " | " + this.m_godAdd;
    }

    // Estado real en el GodModeSystem: si alguna fuente es la nuestra. HasGodMode daba false con
    // entradas registradas (probado en el juego), por eso se miran las fuentes.
    public func IsGodMode() -> Bool {
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return false;
        }
        let god: ref<GodModeSystem> = GameInstance.GetGodModeSystem(this.GetGameInstance());
        let inv: array<CName> = god.GetGodModeSources(player.GetEntityID(), gameGodModeType.Invulnerable);
        let imm: array<CName> = god.GetGodModeSources(player.GetEntityID(), gameGodModeType.Immortal);
        return ArrayContains(inv, n"GRDebug") || ArrayContains(imm, n"GRDebug");
    }

    private func NewRow(parent: ref<inkCompoundWidget>) -> ref<GRThreatRow> {
        let row: ref<GRThreatRow> = new GRThreatRow();
        row.root = new inkVerticalPanel();
        row.root.SetFitToContent(true);
        row.root.SetChildMargin(new inkMargin(0.0, 0.0, 0.0, 5.0));

        let line: ref<inkHorizontalPanel> = new inkHorizontalPanel();
        line.SetFitToContent(true);
        row.gang = new inkRectangle();
        row.gang.SetSize(new Vector2(12.0, 12.0));
        row.gang.SetVAlign(inkEVerticalAlign.Center);
        row.gang.SetMargin(new inkMargin(0.0, 0.0, 10.0, 0.0));
        row.gang.Reparent(line);
        row.tag = this.NewText(20, GRHud.Gold(), n"Bold");
        row.tag.SetText(this.T("GR-HudNemesis"));
        row.tag.SetVAlign(inkEVerticalAlign.Center);
        row.tag.SetMargin(new inkMargin(0.0, 0.0, 10.0, 0.0));
        row.tag.Reparent(line);
        row.name = this.NewText(26, GRHud.White(), n"Medium");
        row.name.SetVAlign(inkEVerticalAlign.Center);
        row.name.SetMargin(new inkMargin(0.0, 0.0, 14.0, 0.0));
        row.name.Reparent(line);
        row.distance = this.NewText(22, GRHud.Grey(), n"Medium");
        row.distance.SetVAlign(inkEVerticalAlign.Center);
        row.distance.Reparent(line);
        line.Reparent(row.root);

        let bar: ref<inkCanvas> = new inkCanvas();
        bar.SetSize(new Vector2(this.c_barWidth, 8.0));
        let bg: ref<inkRectangle> = new inkRectangle();
        bg.SetSize(new Vector2(this.c_barWidth, 8.0));
        bg.SetTintColor(new HDRColor(0.16, 0.08, 0.09, 1.0));
        bg.Reparent(bar);
        row.fill = new inkRectangle();
        row.fill.SetSize(new Vector2(this.c_barWidth, 8.0));
        row.fill.Reparent(bar);
        row.mark = new inkRectangle();
        row.mark.SetSize(new Vector2(3.0, 16.0));
        row.mark.SetAnchor(inkEAnchor.CenterLeft);
        row.mark.SetAnchorPoint(new Vector2(0.5, 0.5));
        row.mark.SetTintColor(GRHud.Yellow());
        row.mark.Reparent(bar);
        bar.Reparent(row.root);

        row.root.SetVisible(false);
        row.root.Reparent(parent);
        return row;
    }

    private func Update() {
        let gi: GameInstance = this.GetGameInstance();
        let settings: ref<GRSettings> = GRSettings.Get(gi);
        let player: ref<PlayerPuppet> = GetPlayer(gi);
        if !IsDefined(settings) || !IsDefined(player) || !settings.enabled || !settings.threatPanelEnabled || this.IsRadialOpen() {
            if IsDefined(this.m_box) {
                this.m_box.SetVisible(false);
            }
            return;
        }
        let threats: array<ref<GRThreat>> = this.CollectThreats(player);
        let now: Float = EngineTime.ToFloat(GameInstance.GetSimTime(gi));
        if ArraySize(threats) > 0 {
            this.m_lastThreatAt = now;
        }
        // Se oculta 3 s despues de que no quede nadie.
        if ArraySize(threats) == 0 && now - this.m_lastThreatAt > 3.0 {
            if IsDefined(this.m_box) {
                this.m_box.SetVisible(false);
            }
            return;
        }
        if ArraySize(threats) == 0 || !this.EnsurePanel() {
            return;
        }
        this.PlaceBox(settings);
        this.m_box.SetVisible(true);
        this.m_count.SetText(IntToString(ArraySize(threats)));
        let flee: Float = Cast<Float>(settings.fleeHealthPercent);
        let shown: Int32 = Min(settings.threatPanelRows, ArraySize(this.m_rows));
        let i: Int32 = 0;
        while i < ArraySize(this.m_rows) {
            let row: ref<GRThreatRow> = this.m_rows[i];
            if i < shown && i < ArraySize(threats) {
                this.FillRow(row, threats[i], flee, settings.fleeMarkEnabled);
            } else {
                row.root.SetVisible(false);
            }
            i += 1;
        }
        let hidden: Int32 = ArraySize(threats) - shown;
        this.m_more.SetVisible(hidden > 0);
        if hidden > 0 {
            this.m_more.SetText(StrReplace(this.T("GR-HudMore"), "%d", IntToString(hidden)));
        }
        this.FitBox(Min(shown, ArraySize(threats)), hidden > 0);
    }

    // Tamano del recuadro en este mismo tick: GetDesiredSize del panel llega un frame tarde y una fila nueva
    // quedaba fuera. Las filas miden todas lo mismo, asi que se suma con medidas de widgets ya dibujados.
    private func FitBox(rows: Int32, more: Bool) {
        let gap: Float = 12.0;
        if this.m_header.GetDesiredSize().Y > 0.0 {
            this.m_headerH = this.m_header.GetDesiredSize().Y;
        }
        if this.m_rows[0].root.GetDesiredSize().Y > 0.0 {
            this.m_rowH = this.m_rows[0].root.GetDesiredSize().Y;
        }
        if this.m_more.GetDesiredSize().Y > 0.0 {
            this.m_moreH = this.m_more.GetDesiredSize().Y;
        }
        let headerH: Float = this.m_headerH;
        let rowH: Float = this.m_rowH;
        let content: Vector2 = this.m_panel.GetDesiredSize();
        if headerH <= 0.0 || rowH <= 0.0 {
            // Primer tick visible: todavia no hay medidas, se usa lo que haya.
            if content.X > 0.0 && content.Y > 0.0 {
                this.m_box.SetSize(new Vector2(content.X + 2.0 * this.c_padX, content.Y + 2.0 * this.c_padY));
            }
            return;
        }
        let moreH: Float = this.m_moreH > 0.0 ? this.m_moreH : 28.0;
        let height: Float = headerH + gap + Cast<Float>(rows) * (rowH + gap) + (more ? moreH + gap : 0.0);
        let width: Float = MaxF(content.X, this.c_barWidth);
        this.m_box.SetSize(new Vector2(width + 2.0 * this.c_padX, height + 2.0 * this.c_padY));
    }

    private func FillRow(row: ref<GRThreatRow>, threat: ref<GRThreat>, flee: Float, markEnabled: Bool) {
        let npc: ref<ScriptedPuppet> = threat.npc;
        let isNemesis: Bool = StrLen(threat.nemesisName) > 0;
        row.root.SetVisible(true);
        row.root.SetOpacity(threat.isTarget ? 1.0 : 0.8);
        row.gang.SetTintColor(GRHud.GangColor(GRDetection.GetGang(npc)));
        row.tag.SetVisible(isNemesis);
        // Sin Nemesis: el nombre de la banda (el juego da nombres genericos como "Habitante de NC").
        let gang: String = GRDetection.GetGang(npc);
        let label: String = StrLen(gang) > 0 ? this.T("GR-Gang-" + gang) : GetLocalizedText(npc.GetDisplayName());
        row.name.SetText(isNemesis ? threat.nemesisName : label);
        row.name.SetTintColor(threat.isTarget ? GRHud.Yellow() : GRHud.White());
        row.distance.SetText(IntToString(Cast<Int32>(threat.distance)) + " m");
        let below: Bool = threat.canFlee && threat.health <= flee;
        row.fill.SetSize(new Vector2(this.c_barWidth * ClampF(threat.health, 0.0, 100.0) / 100.0, 8.0));
        row.fill.SetTintColor(below ? GRHud.Amber() : GRHud.HealthRed());
        row.mark.SetVisible(markEnabled && threat.canFlee);
        row.mark.SetMargin(new inkMargin(this.c_barWidth * flee / 100.0, 0.0, 0.0, 0.0));
    }

    // Hostiles que tienen a V como objetivo. Orden: el que mira V, Nemesis, luego por distancia.
    private func CollectThreats(player: ref<PlayerPuppet>) -> array<ref<GRThreat>> {
        let result: array<ref<GRThreat>>;
        let gi: GameInstance = this.GetGameInstance();
        let tracker: ref<TargetTrackerComponent> = player.GetTargetTrackerComponent();
        if !IsDefined(tracker) {
            return result;
        }
        let tracked: array<TrackedLocation> = tracker.GetHostileThreats(true);
        let spawner: ref<GRSpawner> = GRSpawner.Get(gi);
        let det: ref<GRDetection> = GRDetection.Get(gi);
        let stats: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(gi);
        let lookAt: ref<GameObject> = GameInstance.GetTargetingSystem(gi).GetLookAtObject(player, false, false);
        for location in tracked {
            let npc: ref<ScriptedPuppet> = location.entity as ScriptedPuppet;
            if IsDefined(npc) && !GRDetection.IsNeutralized(npc) {
                let threat: ref<GRThreat> = new GRThreat();
                threat.npc = npc;
                threat.health = stats.GetStatPoolValue(Cast<StatsObjectID>(npc.GetEntityID()), gamedataStatPoolType.Health, true);
                threat.distance = Vector4.Distance(npc.GetWorldPosition(), player.GetWorldPosition());
                threat.nemesisName = IsDefined(spawner) ? spawner.GetNemesisName(npc.GetEntityID()) : "";
                threat.isTarget = IsDefined(lookAt) && lookAt.GetEntityID() == npc.GetEntityID();
                threat.canFlee = IsDefined(det) && StrLen(det.GetFleeBlocker(npc)) == 0;
                let i: Int32 = 0;
                while i < ArraySize(result) && !this.Before(threat, result[i]) {
                    i += 1;
                }
                ArrayInsert(result, i, threat);
            }
        }
        return result;
    }

    private func Before(a: ref<GRThreat>, b: ref<GRThreat>) -> Bool {
        if NotEquals(a.isTarget, b.isTarget) {
            return a.isTarget;
        }
        let aNemesis: Bool = StrLen(a.nemesisName) > 0;
        let bNemesis: Bool = StrLen(b.nemesisName) > 0;
        if NotEquals(aNemesis, bNemesis) {
            return aNemesis;
        }
        return a.distance < b.distance;
    }
}
