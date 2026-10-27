module GangRetaliation

import Codeware.Localization.*

public func GRLog(msg: String) {
    FTLog("[GangRetaliation] " + msg);
}

public class GRSystem extends ScriptableSystem {
    private persistent let m_campaignId: Int32;

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

    // En el menu principal tambien llega un jugador: ahi no se crea campana (dejaba campanas basura).
    private func OnPlayerAttach(request: ref<PlayerAttachRequest>) {
        if this.IsInGame() {
            this.EnsureCampaignId();
        }
    }

    public func IsInGame() -> Bool {
        let requests: wref<inkISystemRequestsHandler> = GameInstance.GetSystemRequestsHandler();
        return IsDefined(requests) && !requests.IsPreGame();
    }

    public func EnsureCampaignId() {
        if this.m_campaignId == 0 {
            this.m_campaignId = RandRange(100000, 999999999);
            GRLog("Nueva campana: " + IntToString(this.m_campaignId));
        }
    }

    // No genera id: CET la pide durante la carga, antes de que la partida restaure el suyo.
    public func GetCampaignId() -> Int32 {
        return this.m_campaignId;
    }

    public func GetText(key: String) -> String {
        return LocalizationSystem.GetInstance(this.GetGameInstance()).GetText(key);
    }
}
