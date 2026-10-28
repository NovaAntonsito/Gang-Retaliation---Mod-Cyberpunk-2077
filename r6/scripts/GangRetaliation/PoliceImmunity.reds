module GangRetaliation

// Redadas de la NCPD: mientras V es inmune (GRSpawner.IsPoliceImmune), sus golpes y muertes
// no suman delito, asi que no hay busqueda aunque una bala perdida le de a un policia.
@wrapMethod(PreventionSystem)
private final func CalculateCrimeScoreForNPC(request: ref<PreventionDamageRequest>) -> Void {
    let spawner: ref<GRSpawner> = GRSpawner.Get(this.GetGameInstance());
    if IsDefined(spawner) && spawner.IsPoliceImmune() {
        return;
    }
    wrappedMethod(request);
}
