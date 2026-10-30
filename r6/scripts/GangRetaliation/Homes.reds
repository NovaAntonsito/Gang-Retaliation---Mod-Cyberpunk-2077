module GangRetaliation

// Detecta cuando V duerme en una cama propia (opcion "Dormir" con icono Wait, como Dark Future).
// Dormir en misiones no pasa por esa opcion, asi que esas ubicaciones nunca cuentan.
// Solo anota posicion y dia; Lua decide si el sitio pasa a ser casa (2 noches distintas).
public class GRHomes extends ScriptableSystem {
    private let m_choiceListener: ref<CallbackHandle>;

    private let m_sleepX: array<Float>;
    private let m_sleepY: array<Float>;
    private let m_sleepDay: array<Float>;

    public static func Get(gi: GameInstance) -> ref<GRHomes> {
        return GameInstance.GetScriptableSystemsContainer(gi).Get(n"GangRetaliation.GRHomes") as GRHomes;
    }

    private func OnPlayerAttach(request: ref<PlayerAttachRequest>) {
        if IsDefined(this.m_choiceListener) {
            return;
        }
        let blackboard: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UIInteractions);
        if IsDefined(blackboard) {
            this.m_choiceListener = blackboard.RegisterListenerVariant(GetAllBlackboardDefs().UIInteractions.LastAttemptedChoice, this, n"OnLastAttemptedChoice");
        }
    }

    private func OnDetach() {
        if IsDefined(this.m_choiceListener) {
            let blackboard: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UIInteractions);
            if IsDefined(blackboard) {
                blackboard.UnregisterListenerVariant(GetAllBlackboardDefs().UIInteractions.LastAttemptedChoice, this.m_choiceListener);
            }
            this.m_choiceListener = null;
        }
    }

    public final func OnLastAttemptedChoice(value: Variant) -> Void {
        let choiceData: InteractionAttemptedChoice = FromVariant<InteractionAttemptedChoice>(value);
        let parts: array<ref<InteractionChoiceCaptionPart>> = choiceData.choice.captionParts.parts;
        let isSleep: Bool = false;
        for part in parts {
            let icon: wref<ChoiceCaptionIconPart_Record> = (part as InteractionChoiceCaptionIconPart).iconRecord;
            if IsDefined(icon) && Equals(icon.EnumName(), n"Wait") {
                isSleep = true;
            }
        }
        if !isSleep {
            return;
        }
        let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return;
        }
        let pos: Vector4 = player.GetWorldPosition();
        ArrayPush(this.m_sleepX, pos.X);
        ArrayPush(this.m_sleepY, pos.Y);
        ArrayPush(this.m_sleepDay, GameInstance.GetTimeSystem(this.GetGameInstance()).GetGameTimeStamp() / 86400.0);
        GRLog("V duerme en " + FloatToString(pos.X) + ", " + FloatToString(pos.Y));
    }

    public func GetSleepCount() -> Int32 {
        return ArraySize(this.m_sleepX);
    }

    public func GetSleepX(index: Int32) -> Float {
        return this.m_sleepX[index];
    }

    public func GetSleepY(index: Int32) -> Float {
        return this.m_sleepY[index];
    }

    public func GetSleepDay(index: Int32) -> Float {
        return this.m_sleepDay[index];
    }

    public func ClearSleeps() {
        ArrayClear(this.m_sleepX);
        ArrayClear(this.m_sleepY);
        ArrayClear(this.m_sleepDay);
    }
}
