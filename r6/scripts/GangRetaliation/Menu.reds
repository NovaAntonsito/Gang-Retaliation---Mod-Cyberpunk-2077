// Gang Retaliation - fase 6: pantalla de Nemesis en el menu del juego
//
// - Boton "NEMESIS" en el menu principal (el mismo boton del juego que usa Dark Future).
// - Pantalla propia registrada en menu.inkmenu. El .inkwidget (GangRetaliation.archive) es solo
//   un lienzo vacio con GRNemesisMenuController; todo se dibuja aqui por script.
// - Estilo de la pantalla de ventajas: cabecera [A] BANDA [D] con una marca por banda y un arbol
//   Jefe -> Tenientes -> Soldados unido con lineas. Debajo, los caidos.
// Los datos los prepara CET (textos ya traducidos) y los deja en GRMenuData cada pocos segundos.

module GangRetaliation

public class GRMenuEntry {
    public let gangKey: String;
    public let gang: String;
    public let rank: Int32;
    public let dead: Bool;
    public let name: String;
    public let traits: String;
    public let stats: String;
}

public class GRMenuData extends ScriptableSystem {
    private let m_entries: array<ref<GRMenuEntry>>;
    // Bandas en el orden en que CET las envia.
    private let m_gangs: array<String>;
    // Ultima banda vista, para volver a ella al abrir la pantalla.
    private let m_page: Int32;

    public static func Get(gi: GameInstance) -> ref<GRMenuData> {
        return GameInstance.GetScriptableSystemsContainer(gi).Get(n"GangRetaliation.GRMenuData") as GRMenuData;
    }

    // API para CET
    public func Clear() {
        ArrayClear(this.m_entries);
        ArrayClear(this.m_gangs);
    }

    public func Add(gangKey: String, gang: String, rank: Int32, dead: Bool, name: String, traits: String, stats: String) {
        let entry: ref<GRMenuEntry> = new GRMenuEntry();
        entry.gangKey = gangKey;
        entry.gang = gang;
        entry.rank = rank;
        entry.dead = dead;
        entry.name = name;
        entry.traits = traits;
        entry.stats = stats;
        ArrayPush(this.m_entries, entry);
        if !ArrayContains(this.m_gangs, gangKey) {
            ArrayPush(this.m_gangs, gangKey);
        }
    }

    public func GetGangs() -> array<String> {
        return this.m_gangs;
    }

    public func GetEntries() -> array<ref<GRMenuEntry>> {
        return this.m_entries;
    }

    public func GetPage() -> Int32 {
        return this.m_page;
    }

    public func SetPage(page: Int32) {
        this.m_page = page;
    }

    public func Text(key: String) -> String {
        return GRSystem.Get(this.GetGameInstance()).GetText(key);
    }
}

// -----------------------------------------------------------------------------
// Pantalla
// -----------------------------------------------------------------------------
public class GRNemesisMenuController extends gameuiMenuGameController {
    private let m_data: ref<GRMenuData>;
    private let m_page: Int32;
    private let m_tree: wref<inkCanvas>;
    private let m_gangTitle: wref<inkText>;
    private let m_gangCount: wref<inkText>;
    private let m_marks: wref<inkHorizontalPanel>;
    private let m_summary: wref<inkText>;
    private let m_buttonHints: wref<ButtonHints>;

    // Colores de la interfaz del juego (los mismos que Custom Perk Framework).
    private func Red() -> HDRColor {
        return new HDRColor(1.1761, 0.3809, 0.3476, 1.0);
    }

    private func Cyan() -> HDRColor {
        return new HDRColor(0.368627, 0.964706, 1.0, 1.0);
    }

    private func Gold() -> HDRColor {
        return new HDRColor(1.1192, 0.8441, 0.2565, 1.0);
    }

    private func Grey() -> HDRColor {
        return new HDRColor(0.45, 0.45, 0.5, 1.0);
    }

    private func Dark() -> HDRColor {
        return new HDRColor(0.054902, 0.054902, 0.090196, 1.0);
    }

    private func T(key: String) -> String {
        return IsDefined(this.m_data) ? this.m_data.Text(key) : key;
    }

    protected cb func OnInitialize() -> Bool {
        this.m_data = GRMenuData.Get(this.GetPlayerControlledObject().GetGame());
        this.m_page = IsDefined(this.m_data) ? this.m_data.GetPage() : 0;
        let root: ref<inkCompoundWidget> = this.GetRootCompoundWidget();

        this.CreateBackground(root);
        this.CreateHeader(root);
        this.CreateRankLabels(root);

        let tree: ref<inkCanvas> = new inkCanvas();
        tree.SetName(n"tree");
        tree.SetAnchor(inkEAnchor.Fill);
        tree.Reparent(root);
        this.m_tree = tree;

        let hints: ref<inkCanvas> = new inkCanvas();
        hints.SetName(n"button_hints");
        hints.SetAnchor(inkEAnchor.BottomRight);
        hints.SetAnchorPoint(new Vector2(1.0, 1.0));
        hints.SetMargin(new inkMargin(0.0, 0.0, 100.0, 50.0));
        hints.Reparent(root);
        this.m_buttonHints = this.SpawnFromExternal(hints, r"base\\gameplay\\gui\\common\\buttonhints.inkwidget", n"Root").GetController() as ButtonHints;
        if IsDefined(this.m_buttonHints) {
            this.m_buttonHints.AddButtonHint(n"back", "Common-Access-Close");
        }

        this.RegisterToGlobalInputCallback(n"OnPostOnRelease", this, n"OnGRGlobalInput");
        this.Fill();
        super.OnInitialize();
    }

    protected cb func OnUninitialize() -> Bool {
        this.UnregisterFromGlobalInputCallback(n"OnPostOnRelease", this, n"OnGRGlobalInput");
        if IsDefined(this.m_data) {
            this.m_data.SetPage(this.m_page);
        }
    }

    // -------------------------------------------------------------------------
    // Piezas fijas
    // -------------------------------------------------------------------------
    private func CreateBackground(root: ref<inkCompoundWidget>) {
        let background: ref<inkRectangle> = new inkRectangle();
        background.SetName(n"background");
        background.SetAnchor(inkEAnchor.Fill);
        background.SetTintColor(this.Dark());
        background.SetOpacity(0.92);
        background.Reparent(root);

        let vignette: ref<inkImage> = new inkImage();
        vignette.SetName(n"vignette");
        vignette.SetAtlasResource(r"base\\gameplay\\gui\\widgets\\notifications\\vignette.inkatlas");
        vignette.SetTexturePart(n"vignette_1");
        vignette.SetNineSliceScale(true);
        vignette.SetAnchor(inkEAnchor.Fill);
        vignette.SetTintColor(this.Red());
        vignette.SetOpacity(0.6);
        vignette.Reparent(root);
    }

    private func NewText(text: String, size: Int32, color: HDRColor, style: CName) -> ref<inkText> {
        let label: ref<inkText> = new inkText();
        label.SetText(text);
        label.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        label.SetFontStyle(style);
        label.SetFontSize(size);
        label.SetTintColor(color);
        return label;
    }

    // Linea horizontal fina de lado a lado (como la franja de la pantalla de ventajas).
    private func AddFullLine(root: ref<inkCompoundWidget>, top: Float) {
        let line: ref<inkRectangle> = new inkRectangle();
        line.SetAnchor(inkEAnchor.TopFillHorizontaly);
        line.SetMargin(new inkMargin(0.0, top, 0.0, 0.0));
        line.SetHeight(3.0);
        line.SetTintColor(this.Red());
        line.SetOpacity(0.55);
        line.Reparent(root);
    }

    private func NewKeyIcon(part: CName) -> ref<inkImage> {
        let icon: ref<inkImage> = new inkImage();
        icon.SetAtlasResource(r"base\\gameplay\\gui\\common\\input\\icons_keyboard.inkatlas");
        icon.SetTexturePart(part);
        icon.SetSize(new Vector2(64.0, 64.0));
        icon.SetVAlign(inkEVerticalAlign.Center);
        icon.SetTintColor(this.Cyan());
        icon.SetInteractive(true);
        return icon;
    }

    private func CreateHeader(root: ref<inkCompoundWidget>) {
        this.AddFullLine(root, 150.0);
        this.AddFullLine(root, 330.0);

        // Titulo a la izquierda y resumen a la derecha.
        let title: ref<inkText> = this.NewText(StrUpper(this.T("GR-MenuTitle")), 64, this.Red(), n"Medium");
        title.SetAnchor(inkEAnchor.TopLeft);
        title.SetMargin(new inkMargin(120.0, 205.0, 0.0, 0.0));
        title.Reparent(root);

        let summary: ref<inkText> = this.NewText("", 40, this.Gold(), n"Medium");
        summary.SetAnchor(inkEAnchor.TopRight);
        summary.SetAnchorPoint(new Vector2(1.0, 0.0));
        summary.SetMargin(new inkMargin(0.0, 220.0, 120.0, 0.0));
        summary.Reparent(root);
        this.m_summary = summary;

        // [A]  BANDA  N  [D]
        let header: ref<inkHorizontalPanel> = new inkHorizontalPanel();
        header.SetName(n"gang_switch");
        header.SetAnchor(inkEAnchor.TopCenter);
        header.SetAnchorPoint(new Vector2(0.5, 0.0));
        header.SetMargin(new inkMargin(0.0, 190.0, 0.0, 0.0));
        header.SetFitToContent(true);
        header.SetChildMargin(new inkMargin(40.0, 0.0, 40.0, 0.0));
        header.Reparent(root);

        let left: ref<inkImage> = this.NewKeyIcon(n"kb_a");
        left.Reparent(header);
        left.RegisterToCallback(n"OnRelease", this, n"OnGRPrevClick");

        let gangTitle: ref<inkText> = this.NewText("", 72, this.Cyan(), n"Medium");
        gangTitle.SetVAlign(inkEVerticalAlign.Center);
        gangTitle.Reparent(header);
        this.m_gangTitle = gangTitle;

        let gangCount: ref<inkText> = this.NewText("", 72, this.Cyan(), n"Bold");
        gangCount.SetVAlign(inkEVerticalAlign.Center);
        gangCount.Reparent(header);
        this.m_gangCount = gangCount;

        let right: ref<inkImage> = this.NewKeyIcon(n"kb_d");
        right.Reparent(header);
        right.RegisterToCallback(n"OnRelease", this, n"OnGRNextClick");

        // Una marca por banda debajo; la actual en cian.
        let marks: ref<inkHorizontalPanel> = new inkHorizontalPanel();
        marks.SetName(n"gang_marks");
        marks.SetAnchor(inkEAnchor.TopCenter);
        marks.SetAnchorPoint(new Vector2(0.5, 0.0));
        marks.SetMargin(new inkMargin(0.0, 300.0, 0.0, 0.0));
        marks.SetFitToContent(true);
        marks.SetChildMargin(new inkMargin(4.0, 0.0, 4.0, 0.0));
        marks.Reparent(root);
        this.m_marks = marks;
    }

    // Etiquetas de nivel a la derecha, como PRINCIPIANTE / PRO / PRODIGIO.
    private func CreateRankLabels(root: ref<inkCompoundWidget>) {
        let keys: array<String> = ["GR-MenuBoss", "GR-MenuLieutenants", "GR-MenuSoldiers"];
        let i: Int32 = 0;
        while i < 3 {
            let label: ref<inkText> = this.NewText(StrUpper(this.T(keys[i])), 40, this.Grey(), n"Medium");
            label.SetAnchor(inkEAnchor.TopRight);
            label.SetAnchorPoint(new Vector2(1.0, 0.5));
            label.SetMargin(new inkMargin(0.0, this.TierY(3 - i), 140.0, 0.0));
            label.Reparent(root);
            i += 1;
        }
    }

    // -------------------------------------------------------------------------
    // Arbol
    // -------------------------------------------------------------------------
    private func TierY(rank: Int32) -> Float {
        if rank == 3 {
            return 600.0;
        }
        if rank == 2 {
            return 1100.0;
        }
        return 1600.0;
    }

    private func CenterX() -> Float {
        return 1820.0;
    }

    // Linea recta horizontal o vertical entre dos puntos (las del arbol siempre lo son).
    private func AddLine(x1: Float, y1: Float, x2: Float, y2: Float, color: HDRColor) {
        let line: ref<inkRectangle> = new inkRectangle();
        line.SetAnchor(inkEAnchor.TopLeft);
        let thickness: Float = 5.0;
        line.SetMargin(new inkMargin(MinF(x1, x2) - thickness / 2.0, MinF(y1, y2) - thickness / 2.0, 0.0, 0.0));
        line.SetSize(new Vector2(AbsF(x2 - x1) + thickness, AbsF(y2 - y1) + thickness));
        line.SetTintColor(color);
        line.SetOpacity(0.8);
        line.Reparent(this.m_tree);
    }

    // Codo de arriba a abajo: baja desde el padre, cruza y baja hasta el hijo.
    private func Connect(px: Float, py: Float, cx: Float, cy: Float, color: HDRColor) {
        let mid: Float = (py + cy) / 2.0;
        this.AddLine(px, py, px, mid, color);
        this.AddLine(px, mid, cx, mid, color);
        this.AddLine(cx, mid, cx, cy, color);
    }

    // Tarjeta de un Nemesis centrada en (x, y).
    private func AddCard(entry: ref<GRMenuEntry>, x: Float, y: Float, w: Float, h: Float, color: HDRColor) {
        let card: ref<inkCanvas> = new inkCanvas();
        card.SetAnchor(inkEAnchor.TopLeft);
        card.SetMargin(new inkMargin(x - w / 2.0, y - h / 2.0, 0.0, 0.0));
        card.SetSize(new Vector2(w, h));
        card.Reparent(this.m_tree);

        let bg: ref<inkImage> = new inkImage();
        bg.SetAtlasResource(r"base\\gameplay\\gui\\common\\shapes\\atlas_shapes_sync.inkatlas");
        bg.SetTexturePart(n"cell_bg");
        bg.SetNineSliceScale(true);
        bg.SetAnchor(inkEAnchor.Fill);
        bg.SetTintColor(this.Dark());
        bg.SetOpacity(0.95);
        bg.Reparent(card);

        let frame: ref<inkImage> = new inkImage();
        frame.SetAtlasResource(r"base\\gameplay\\gui\\common\\shapes\\atlas_shapes_sync.inkatlas");
        frame.SetTexturePart(n"cell_fg");
        frame.SetNineSliceScale(true);
        frame.SetAnchor(inkEAnchor.Fill);
        frame.SetTintColor(color);
        frame.SetOpacity(0.9);
        frame.Reparent(card);

        let content: ref<inkVerticalPanel> = new inkVerticalPanel();
        content.SetAnchor(inkEAnchor.Fill);
        content.SetMargin(new inkMargin(28.0, 18.0, 20.0, 12.0));
        content.Reparent(card);

        let name: ref<inkText> = this.NewText(entry.name, 38, color, n"Medium");
        name.Reparent(content);
        if StrLen(entry.traits) > 0 {
            let traits: ref<inkText> = this.NewText(entry.traits, 26, this.Cyan(), n"Regular");
            traits.SetMargin(new inkMargin(0.0, 6.0, 0.0, 0.0));
            traits.Reparent(content);
        }
        let stats: ref<inkText> = this.NewText(entry.stats, 24, this.Grey(), n"Regular");
        stats.SetMargin(new inkMargin(0.0, 6.0, 0.0, 0.0));
        stats.Reparent(content);
    }

    // Hueco sin ocupar en el arbol.
    private func AddVacant(x: Float, y: Float, w: Float, h: Float) {
        let vacant: ref<GRMenuEntry> = new GRMenuEntry();
        vacant.name = this.T("GR-MenuVacant");
        vacant.stats = "";
        this.AddCard(vacant, x, y, w, h, this.Grey());
    }

    // x de cada elemento repartidos en [left, right].
    private func Spread(count: Int32, index: Int32, left: Float, right: Float) -> Float {
        if count <= 1 {
            return (left + right) / 2.0;
        }
        return left + (right - left) * Cast<Float>(index) / Cast<Float>(count - 1);
    }

    private func Fill() {
        this.m_tree.RemoveAllChildren();
        this.m_marks.RemoveAllChildren();

        let gangs: array<String> = IsDefined(this.m_data) ? this.m_data.GetGangs() : [];
        if ArraySize(gangs) == 0 {
            this.m_gangTitle.SetText(StrUpper(this.T("GR-MenuTitle")));
            this.m_gangCount.SetText("");
            this.m_summary.SetText("");
            let empty: ref<inkText> = this.NewText(this.T("GR-MenuEmpty"), 44, this.Grey(), n"Regular");
            empty.SetAnchor(inkEAnchor.Centered);
            empty.SetAnchorPoint(new Vector2(0.5, 0.5));
            empty.Reparent(this.m_tree);
            return;
        }
        let count: Int32 = ArraySize(gangs);
        this.m_page = ((this.m_page % count) + count) % count;
        let gangKey: String = gangs[this.m_page];

        // Marcas de banda.
        let i: Int32 = 0;
        while i < count {
            let mark: ref<inkRectangle> = new inkRectangle();
            mark.SetSize(new Vector2(150.0, i == this.m_page ? 8.0 : 5.0));
            mark.SetVAlign(inkEVerticalAlign.Bottom);
            mark.SetTintColor(i == this.m_page ? this.Cyan() : this.Red());
            mark.SetOpacity(i == this.m_page ? 1.0 : 0.6);
            mark.Reparent(this.m_marks);
            i += 1;
        }

        // Miembros de la banda.
        let boss: ref<GRMenuEntry>;
        let lieutenants: array<ref<GRMenuEntry>>;
        let soldiers: array<ref<GRMenuEntry>>;
        let fallen: array<ref<GRMenuEntry>>;
        let gangLabel: String = "";
        for entry in this.m_data.GetEntries() {
            if Equals(entry.gangKey, gangKey) {
                gangLabel = entry.gang;
                if entry.dead {
                    ArrayPush(fallen, entry);
                } else {
                    if entry.rank >= 3 && !IsDefined(boss) {
                        boss = entry;
                    } else {
                        if entry.rank == 2 {
                            ArrayPush(lieutenants, entry);
                        } else {
                            ArrayPush(soldiers, entry);
                        }
                    }
                }
            }
        }
        let alive: Int32 = ArraySize(lieutenants) + ArraySize(soldiers) + (IsDefined(boss) ? 1 : 0);
        this.m_gangTitle.SetText(StrUpper(gangLabel));
        this.m_gangCount.SetText(IntToString(alive));
        this.m_summary.SetText(this.T("GR-MenuAlive") + " " + IntToString(alive) + "   |   " + this.T("GR-MenuFallenShort") + " " + IntToString(ArraySize(fallen)));

        let cx: Float = this.CenterX();
        let bossY: Float = this.TierY(3);
        let ltY: Float = this.TierY(2);
        let soldierY: Float = this.TierY(1);
        let bigW: Float = 680.0;
        let bigH: Float = 250.0;

        // Jefe (o hueco libre).
        if IsDefined(boss) {
            this.AddCard(boss, cx, bossY, bigW, bigH, this.Gold());
        } else {
            this.AddVacant(cx, bossY, bigW, bigH);
        }

        // Tenientes: siempre 2 plazas; las vacias se ven como hueco.
        let ltXs: array<Float> = [cx - 760.0, cx + 760.0];
        let ltCount: Int32 = ArraySize(lieutenants);
        i = 0;
        while i < 2 {
            this.Connect(cx, bossY + bigH / 2.0, ltXs[i], ltY - bigH / 2.0, i < ltCount ? this.Cyan() : this.Grey());
            if i < ltCount {
                this.AddCard(lieutenants[i], ltXs[i], ltY, bigW, bigH, this.Red());
            } else {
                this.AddVacant(ltXs[i], ltY, bigW, bigH);
            }
            i += 1;
        }

        // Soldados: repartidos bajo sus tenientes (o bajo el jefe si no hay tenientes).
        let soldierCount: Int32 = ArraySize(soldiers);
        if soldierCount > 0 {
            let gap: Float = 40.0;
            let soldierW: Float = MinF(600.0, (3200.0 - gap * Cast<Float>(soldierCount - 1)) / Cast<Float>(soldierCount));
            let soldierH: Float = 230.0;
            let left: Float = cx - 1500.0 + soldierW / 2.0;
            let right: Float = cx + 1500.0 - soldierW / 2.0;
            // Primero los del teniente izquierdo y luego los del derecho, para que las lineas no se crucen.
            let ordered: array<ref<GRMenuEntry>>;
            let parents: array<Int32>;
            let p: Int32 = 0;
            while p < 2 {
                i = 0;
                while i < soldierCount {
                    if i % 2 == p {
                        ArrayPush(ordered, soldiers[i]);
                        ArrayPush(parents, p);
                    }
                    i += 1;
                }
                p += 1;
            }
            i = 0;
            while i < soldierCount {
                let sx: Float = this.Spread(soldierCount, i, left, right);
                let parentIndex: Int32 = parents[i];
                if ltCount > 0 {
                    let px: Float = ltXs[Min(parentIndex, ltCount - 1)];
                    this.Connect(px, ltY + bigH / 2.0, sx, soldierY - soldierH / 2.0, this.Red());
                } else {
                    this.Connect(cx, bossY + bigH / 2.0, sx, soldierY - soldierH / 2.0, this.Red());
                }
                this.AddCard(ordered[i], sx, soldierY, soldierW, soldierH, this.Red());
                i += 1;
            }
        }

        // Caidos, en una fila al pie.
        if ArraySize(fallen) > 0 {
            let names: String = "";
            for entry in fallen {
                names += (StrLen(names) > 0 ? "    " : "") + entry.name;
            }
            let fallenText: ref<inkText> = this.NewText(StrUpper(this.T("GR-MenuFallen")) + ":   " + names, 30, this.Grey(), n"Regular");
            fallenText.SetAnchor(inkEAnchor.TopLeft);
            fallenText.SetMargin(new inkMargin(120.0, 1900.0, 0.0, 0.0));
            fallenText.Reparent(this.m_tree);
        }
    }

    // -------------------------------------------------------------------------
    // Cambiar de banda
    // -------------------------------------------------------------------------
    private func ChangePage(delta: Int32) {
        this.m_page += delta;
        this.Fill();
        this.PlaySound(n"Button", n"OnPress");
    }

    protected cb func OnGRPrevClick(evt: ref<inkPointerEvent>) -> Bool {
        if evt.IsAction(n"click") {
            this.ChangePage(-1);
        }
    }

    protected cb func OnGRNextClick(evt: ref<inkPointerEvent>) -> Bool {
        if evt.IsAction(n"click") {
            this.ChangePage(1);
        }
    }

    protected cb func OnGRGlobalInput(evt: ref<inkPointerEvent>) -> Bool {
        if evt.IsHandled() {
            return false;
        }
        if evt.IsAction(n"option_switch_prev") {
            this.ChangePage(-1);
            evt.Handle();
            return true;
        }
        if evt.IsAction(n"option_switch_next") {
            this.ChangePage(1);
            evt.Handle();
            return true;
        }
        return false;
    }
}

// -----------------------------------------------------------------------------
// Registro de la pantalla en el menu del juego (igual que Dark Future)
// -----------------------------------------------------------------------------
class GRInsertNemesisMenu extends ScriptableService {
    private cb func OnLoad() {
        GameInstance.GetCallbackSystem()
            .RegisterCallback(n"Resource/Ready", this, n"OnMenuResourceReady")
            .AddTarget(ResourceTarget.Path(r"base\\gameplay\\gui\\fullscreen\\menu.inkmenu"));
    }

    private cb func OnMenuResourceReady(event: ref<ResourceEvent>) {
        let resource: ref<inkMenuResource> = event.GetResource() as inkMenuResource;
        let entry: inkMenuEntry;
        entry.depth = 0u;
        entry.spawnMode = inkSpawnMode.SingleAndMultiplayer;
        entry.isAffectedByFadeout = true;
        entry.menuWidget *= r"gangretaliation\\gui\\nemesis.inkwidget";
        entry.name = n"gangretaliation_nemesis_menu";
        ArrayPush(resource.menusEntries, entry);
    }
}

// -----------------------------------------------------------------------------
// Boton en el menu principal: el boton del juego, bajo Personaje / Estadisticas
// -----------------------------------------------------------------------------
@wrapMethod(MenuHubLogicController)
protected cb func OnInitialize() -> Bool {
    let result: Bool = wrappedMethod();
    this.GRAddNemesisButton();
    return result;
}

@addMethod(MenuHubLogicController)
private final func GRAddNemesisButton() {
    let settings: ref<GRSettings> = GRSettings.Get(GetGameInstance());
    if IsDefined(settings) && !settings.enabled {
        return;
    }
    let container: ref<inkCompoundWidget> = this.GetRootCompoundWidget().GetWidgetByPathName(n"mainMenu/buttonsContainer/panel_character") as inkCompoundWidget;
    if !IsDefined(container) {
        GRLog("Menu: no se encontro el panel del menu principal");
        return;
    }
    let button: ref<inkWidget> = this.SpawnFromLocal(container, n"menu_button");
    button.SetName(n"GangRetaliation_Nemesis");
    // Dark Future pone su boton a 500 (670 con StealthRunner); este va justo debajo.
    let top: Float = 500.0;
    if GRHasDarkFuture() {
        top += 170.0;
    }
    if GRHasStealthRunner() {
        top += 170.0;
    }
    button.SetMargin(new inkMargin(0.0, top, 0.0, 0.0));

    let data: MenuData;
    data.disabled = false;
    data.fullscreenName = n"gangretaliation_nemesis_menu";
    data.identifier = 61;
    data.parentIdentifier = 2;
    data.label = GRSystem.Get(GetGameInstance()).GetText("GR-MenuButton");
    data.icon = n"ico_data_hub";
    let controller: ref<MenuItemController> = button.GetController() as MenuItemController;
    controller.Init(data);
}

@if(ModuleExists("DarkFuture.UI"))
public func GRHasDarkFuture() -> Bool {
    return true;
}

@if(!ModuleExists("DarkFuture.UI"))
public func GRHasDarkFuture() -> Bool {
    return false;
}

@if(ModuleExists("StealthRunner"))
public func GRHasStealthRunner() -> Bool {
    return true;
}

@if(!ModuleExists("StealthRunner"))
public func GRHasStealthRunner() -> Bool {
    return false;
}
