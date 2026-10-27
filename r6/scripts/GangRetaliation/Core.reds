// Gang Retaliation - nucleo
// Fase 0: identificador de campana guardado en la partida y acceso a textos.
// Los datos de los Nemesis viven en un JSON propio que gestiona la capa CET.

module GangRetaliation

import Codeware.Localization.*

public func GRLog(msg: String) {
    FTLog("[GangRetaliation] " + msg);
}

public class GRSystem extends ScriptableSystem {
    // Se guarda en la partida: identifica a que campana del JSON pertenece este save.
    private persistent let m_campaignId: Int32;
    // No se guarda: cambia en cada carga de partida, para que CET detecte recargas.
    private let m_sessionToken: Int32;

    public static func Get(gi: GameInstance) -> ref<GRSystem> {
        return GameInstance.GetScriptableSystemsContainer(gi).Get(n"GangRetaliation.GRSystem") as GRSystem;
    }

    private func OnAttach() {
        this.m_sessionToken = RandRange(1, 999999999);
        GRLog("Sistema cargado");
    }

    public func GetSessionToken() -> Int32 {
        return this.m_sessionToken;
    }

    private func OnPlayerAttach(request: ref<PlayerAttachRequest>) {
        // En el menu principal tambien llega un jugador: ahi no se crea nada (dejaba campanas basura en el JSON).
        if this.IsInGame() {
            this.EnsureCampaignId();
        }
    }

    // false en el menu principal (antes de cargar una partida).
    public func IsInGame() -> Bool {
        let requests: wref<inkISystemRequestsHandler> = GameInstance.GetSystemRequestsHandler();
        return IsDefined(requests) && !requests.IsPreGame();
    }

    // CET lo pide si una partida ya cargada sigue sin id (save de antes del mod sin OnPlayerAttach en juego).
    public func EnsureCampaignId() {
        if this.m_campaignId == 0 {
            this.m_campaignId = RandRange(100000, 999999999);
            GRLog("Nueva campana: " + IntToString(this.m_campaignId));
        }
    }

    // 0 hasta que V aparece (OnPlayerAttach): durante la carga la partida aun no ha restaurado su id
    // y generar uno aqui creaba una campana nueva en cada carga.
    public func GetCampaignId() -> Int32 {
        return this.m_campaignId;
    }

    public func GetText(key: String) -> String {
        return LocalizationSystem.GetInstance(this.GetGameInstance()).GetText(key);
    }
}
