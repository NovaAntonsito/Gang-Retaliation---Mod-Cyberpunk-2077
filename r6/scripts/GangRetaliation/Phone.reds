module GangRetaliation

public class GRPhone extends ScriptableSystem {
    private let m_queue: wref<JournalNotificationQueue>;

    public static func Get(gi: GameInstance) -> ref<GRPhone> {
        return GameInstance.GetScriptableSystemsContainer(gi).Get(n"GangRetaliation.GRPhone") as GRPhone;
    }

    public func SetQueue(queue: ref<JournalNotificationQueue>) {
        this.m_queue = queue;
    }

    public func SendThreat(from: String, fallbackText: String) -> Bool {
        let journal: ref<JournalManager> = GameInstance.GetJournalManager(this.GetGameInstance());
        let contact: String = "contacts/gr_unknown";
        let thread: String = contact + "/gr_threats/sms_";
        if !IsDefined(journal.GetEntryByString(contact, "gameJournalContact")) {
            GRLog("SMS: falta el journal del mod, solo aviso");
            return this.SendSms(from, fallbackText);
        }
        let next: Int32 = 0;
        let i: Int32 = 1;
        while i <= 12 && next == 0 {
            let entry: wref<JournalEntry> = journal.GetEntryByString(thread + GRPhone.Pad(i), "gameJournalPhoneMessage");
            if IsDefined(entry) && NotEquals(journal.GetEntryState(entry), gameJournalEntryState.Active) {
                next = i;
            }
            i += 1;
        }
        if next == 0 {
            i = 1;
            while i <= 12 {
                journal.ChangeEntryState(thread + GRPhone.Pad(i), "gameJournalPhoneMessage", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
                i += 1;
            }
            next = 1;
        }
        journal.ChangeEntryState(contact, "gameJournalContact", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        journal.ChangeEntryState(contact + "/gr_threats", "gameJournalPhoneConversation", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        journal.ChangeEntryState(thread + GRPhone.Pad(next), "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        GRLog("SMS al telefono: sms_" + GRPhone.Pad(next) + " (" + from + ")");
        return true;
    }

    private static func Pad(i: Int32) -> String {
        return (i < 10 ? "0" : "") + IntToString(i);
    }

    public func SendSms(from: String, text: String) -> Bool {
        if !IsDefined(this.m_queue) {
            GRLog("SMS: cola de avisos no disponible");
            return false;
        }
        let view: ref<PhoneMessageNotificationViewData> = new PhoneMessageNotificationViewData();
        view.title = from;
        view.SMSText = text;
        view.text = text;
        view.animation = n"notification_phone_MSG";
        view.soundEvent = n"PhoneSmsPopup";
        view.soundAction = n"OnOpen";
        let data: gameuiGenericNotificationData;
        data.time = 8.0;
        data.widgetLibraryItemName = n"notification_message";
        data.notificationData = view;
        this.m_queue.AddNewNotificationData(data);
        GRLog("SMS de " + from + ": " + text);
        return true;
    }
}

@wrapMethod(JournalNotificationQueue)
protected cb func OnPlayerAttach(playerPuppet: ref<GameObject>) -> Bool {
    let result: Bool = wrappedMethod(playerPuppet);
    if IsDefined(playerPuppet) {
        let phone: ref<GRPhone> = GRPhone.Get(playerPuppet.GetGame());
        if IsDefined(phone) {
            phone.SetQueue(this);
        }
    }
    return result;
}
