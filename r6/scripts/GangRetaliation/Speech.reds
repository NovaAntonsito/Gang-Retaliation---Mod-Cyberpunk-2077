// Gang Retaliation - frases de NPC con el sistema de dialogo del juego
// Se muestran sobre la cabeza del NPC, igual que las frases normales de los NPC.
// El juego no siempre las quita al acabar su duracion, asi que se ocultan a mano (Tick desde CET).

module GangRetaliation

public class GRSpeech extends ScriptableSystem {
    private let m_ids: array<CRUID>;
    private let m_expires: array<Float>;

    public static func Get(gi: GameInstance) -> ref<GRSpeech> {
        return GameInstance.GetScriptableSystemsContainer(gi).Get(n"GangRetaliation.GRSpeech") as GRSpeech;
    }

    public static func Say(npc: ref<GameObject>, speakerName: String, text: String, duration: Float) {
        if !IsDefined(npc) {
            return;
        }
        let system: ref<GRSpeech> = GRSpeech.Get(npc.GetGame());
        if IsDefined(system) {
            system.Show(npc, speakerName, text, duration);
        }
    }

    private func Now() -> Float {
        return EngineTime.ToFloat(GameInstance.GetSimTime(this.GetGameInstance()));
    }

    public func Show(npc: ref<GameObject>, speakerName: String, text: String, duration: Float) {
        let line: scnDialogLineData;
        line.id = CreateCRUID(Cast<Uint64>(RandRange(1, 2000000000)));
        line.text = text;
        line.type = scnDialogLineType.OverHead;
        line.speaker = npc;
        line.speakerName = speakerName;
        line.isPersistent = false;
        line.duration = duration;

        let lines: array<scnDialogLineData>;
        ArrayPush(lines, line);
        let defs = GetAllBlackboardDefs();
        GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(defs.UIGameData).SetVariant(defs.UIGameData.ShowDialogLine, ToVariant(lines), true);

        ArrayPush(this.m_ids, line.id);
        ArrayPush(this.m_expires, this.Now() + duration);
    }

    private func Hide(id: CRUID) {
        let ids: array<CRUID>;
        ArrayPush(ids, id);
        let defs = GetAllBlackboardDefs();
        GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(defs.UIGameData).SetVariant(defs.UIGameData.HideDialogLine, ToVariant(ids), true);
    }

    // Lo llama CET cada segundo.
    public func Tick() {
        let now: Float = this.Now();
        let i: Int32 = ArraySize(this.m_ids) - 1;
        while i >= 0 {
            if now >= this.m_expires[i] {
                this.Hide(this.m_ids[i]);
                ArrayErase(this.m_ids, i);
                ArrayErase(this.m_expires, i);
            }
            i -= 1;
        }
    }

    // Por si acaso: quita todas las frases del mod (boton de debug).
    public func HideAll() {
        for id in this.m_ids {
            this.Hide(id);
        }
        ArrayClear(this.m_ids);
        ArrayClear(this.m_expires);
    }
}
