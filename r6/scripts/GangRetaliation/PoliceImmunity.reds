module GangRetaliation

@wrapMethod(PreventionSystem)
private final func CalculateCrimeScoreForNPC(request: ref<PreventionDamageRequest>) -> Void {
    let spawner: ref<GRSpawner> = GRSpawner.Get(this.GetGameInstance());
    // En una emboscada V se defiende: sin crimen por herir a los atacantes (ni a nadie mientras dure).
    if IsDefined(spawner) && (spawner.IsPoliceImmune() || spawner.IsAmbushActive()) {
        return;
    }
    wrappedMethod(request);
}
