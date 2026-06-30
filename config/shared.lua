return {
    -- Notify the resource owner when a new version releases (placeholder for now)
    versionCheck = false,

    --------------------------------------------------------------------------
    -- CONSUMPTION
    -- The game engine burns fuel proportionally to RPM/load. We only set a
    -- per-vehicle multiplier ONCE when entering the driver seat. No per-tick maths.
    --------------------------------------------------------------------------
    baseRate    = 5.0,    -- global base multiplier fed to SetFuelConsumptionRateMultiplier
    defaultTank = 65.0,   -- reference tank (L) used to scale range vs. tank size

    --------------------------------------------------------------------------
    -- CUSTOM EMPTY (no ugly GTA sputter)
    -- The native gauge is never allowed into its low band. We reserve a floor:
    -- native level 100..F  ==  displayed fuel 100..0%.
    -- At F we cut the engine ourselves. Tune F in-game.
    --------------------------------------------------------------------------
    lowFuelFloor = 18.0,

    --------------------------------------------------------------------------
    -- PRICING (client side = estimate/display; server holds authoritative price)
    --------------------------------------------------------------------------
    literPrice = 1.7,
    kwPrice    = 0.3,

    -- Electric: charge-over-time while parked in a garage (Sna feature).
    -- The garage resource stamps the park time and applies the gained charge on
    -- retrieve (see exports StoreVehicleCharge / GetGarageCharge in server/main.lua).
    electric = {
        garageCharge          = true,
        timeForCompleteCharge = 40,   -- minutes parked for a full 0->100% charge
    },

    -- Clamp for handling-derived tank sizes (L). Values of 0 in handling mean
    -- "no fuel system" (bikes/trains/trailers) and are left untouched.
    tankClamp = { min = 20.0, max = 5000.0 },

    --------------------------------------------------------------------------
    -- PUMPS
    -- ox_target on pump MODELS -> every matching pump on the map works with no
    -- declaration. Station coords below are only used to draw blips.
    --------------------------------------------------------------------------
    pumpModels = {
        'prop_gas_pump_1a',
        'prop_gas_pump_1b',
        'prop_gas_pump_1c',
        'prop_gas_pump_1d',
        'prop_vintage_pump',
        'prop_gas_pump_old2',
        'prop_gas_pump_old3',
    },

    showBlips = true,

    fuelCan = {
        enabled       = true,
        item          = 'WEAPON_PETROLCAN',  -- default ox_inventory weapon item
        buyPrice      = 1000,   -- price for a full can
        refillPrice   = 800,    -- price to fully refill an empty can (billed pro-rata)
        litres        = 25,     -- how much fuel a full can holds
        litresPerTick = 1.0,    -- transfer speed when emptying the can into a vehicle
    },

    -- Refuelling at the pump (fuel added in % over time; cost billed per litre).
    refill = {
        tickMs        = 200,   -- time between fill ticks
        litresPerTick = 1.0,   -- petrol: CONSTANT flow (litres per tick). Bigger tank = longer fill.

        -- Electric charging is a % curve (fast until 80%, then crawls), not a flow.
        electric = {
            percentPerTick = 2.0,
            slowdownFrom   = 80.0,
            slowdownPow    = 3.0,
        },
    },

    --------------------------------------------------------------------------
    -- PUMP NOZZLE + ROPE. Pick up the nozzle, walk to the cap, plug in, refuel.
    -- Bone/offset/rope numbers ported from the original sna-fuel; tune in-game
    -- if the nozzle/rope sits wrong.
    --------------------------------------------------------------------------
    pump = {
        nozzleModel   = 'prop_cs_fuel_nozle',
        anchorModel   = 'bkr_prop_bkr_cash_roll_01',
        handBone      = 60309,
        ropeZ         = 1.6,    -- height on the pump where the hose starts
        ropeLength    = 5.0,
        ropeMaxLength = 30.0,   -- auto-return the nozzle past this distance from the pump
        plugDistance  = 2.5,    -- how close to the cap to plug in
        capBones      = { 'petrolcap', 'wheel_lr', 'petroltank', 'petroltank_l', 'engine', 'engine_l' },
        defaultCapOffset = { 0.0, 0.0, 0.65 },
    },

    -- Blips: petrol stations
    gasStations = {
        vec3(49.4187, 2778.793, 58.043),  vec3(263.894, 2606.463, 44.983),
        vec3(1039.958, 2671.134, 39.550), vec3(1207.260, 2660.175, 37.899),
        vec3(2539.685, 2594.192, 37.944), vec3(2679.858, 3263.946, 55.240),
        vec3(2005.055, 3773.887, 32.403), vec3(1687.156, 4929.392, 42.078),
        vec3(1701.314, 6416.028, 32.763), vec3(179.857, 6602.839, 31.868),
        vec3(-94.4619, 6419.594, 31.489), vec3(-2554.996, 2334.40, 33.078),
        vec3(-1800.375, 803.661, 138.651),vec3(-1437.622, -276.747, 46.207),
        vec3(-2096.243, -320.286, 13.168),vec3(-724.619, -935.1631, 19.213),
        vec3(-526.019, -1211.003, 18.184),vec3(-70.2148, -1761.792, 29.534),
        vec3(265.648, -1261.309, 29.292), vec3(819.653, -1028.846, 26.403),
        vec3(1208.951, -1402.567, 35.224),vec3(1181.381, -330.847, 69.316),
        vec3(620.843, 269.100, 103.089),  vec3(2581.321, 362.039, 108.468),
        vec3(176.631, -1562.025, 29.263), vec3(-319.292, -1471.715, 30.549),
        vec3(-66.48, -2532.57, 6.14),     vec3(1784.324, 3330.55, 41.253),
    },

    -- Blips: superchargers (electric)
    superchargerStations = {
        vec3(153.4138, 6592.721, 30.8449),
        vec3(2697.205, 3277.662, 54.24057),
        vec3(-2534.736, 2345.22, 32.05991),
        vec3(645.1025, 280.3252, 102.1716),
        vec3(-729.0958, -911.1166, 18.01393),
    },
}
