-- Vehiculos de cada banda para las emboscadas en vehiculo (records base de la TweakDB, sin motos:
-- tienen que entrar el Nemesis y sus escoltas). Animals y 6th Street no tienen coches propios.
local generic = {
    "Vehicle.v_standard2_archer_hella",
    "Vehicle.v_standard25_villefort_columbus",
}

local Vehicles = {
    Maelstrom = {
        "Vehicle.v_standard2_chevalier_thrax_maelstrom",
        "Vehicle.v_standard2_thorton_galena_maelstrom",
    },
    TygerClaws = {
        "Vehicle.v_sport1_quadra_turbo_tyger_claw",
        "Vehicle.v_sport2_mizutani_shion_tyger",
        "Vehicle.v_standard25_villefort_columbus_tyger",
        "Vehicle.v_standard2_archer_quartz_tyger",
    },
    Valentinos = {
        "Vehicle.v_sport2_villefort_alvarado_valentinos",
        "Vehicle.v_standard2_chevalier_thrax_valentino",
        "Vehicle.v_standard2_thorton_colby_valentinos",
        "Vehicle.v_standard3_thorton_mackinaw_valentinos",
    },
    Barghest = {
        "Vehicle.v_standard2_archer_hella_kurtz",
        "Vehicle.v_standard3_mahir_supron_kurtz",
        "Vehicle.v_standard25_thorton_colby_pickup_kurtz",
        "Vehicle.v_utility4_kaukaz_zeya_kurtz",
    },
    Wraiths = {
        "Vehicle.v_sport2_mizutani_shion_nomad_wraith",
        "Vehicle.v_sport2_quadra_type66_nomad_wraith",
        "Vehicle.v_standard25_thorton_colby_nomad_wraith",
        "Vehicle.v_standard2_archer_quartz_nomad_wraith",
        "Vehicle.v_standard2_thorton_galena_nomad_wraith",
    },
    VoodooBoys = {
        "Vehicle.v_standard25_mahir_voodoo_boys",
        "Vehicle.v_standard2_thorton_galena_voodoo_boys",
    },
    Scavengers = {
        "Vehicle.v_standard25_villefort_columbus_scavengers",
        "Vehicle.v_standard2_archer_hella_scavengers",
        "Vehicle.v_standard2_chevalier_thrax_scavengers",
        "Vehicle.v_standard2_thorton_colby_scavengers",
    },
    Animals = generic,
    SixthStreet = generic,
}

-- Probabilidad de que una emboscada llegue en vehiculo (si falla, se intenta a pie).
Vehicles.chancePercent = 40

function Vehicles.pick(gang)
    local list = Vehicles[gang] or generic
    return list[math.random(#list)]
end

return Vehicles
