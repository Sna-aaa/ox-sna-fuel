-- EVERYTHING BY EXCEPTION.
-- Tank size defaults to the vehicle's handling fPetrolTankVolume (clamped).
-- Consumption factor defaults to 1.0 (or the class factor below).
-- Only list what should differ from the native/default behaviour.

return {
    -- Tank size overrides in litres. Only exceptions.
    -- (handling has tug=2, jetski=2, etc. - fix the ones that matter to you)
    tank = {
        ['tug'] = 1000.0,
        -- ['jetmax'] = 40.0,
        -- ['dinghy'] = 40.0,
    },

    -- Per-model consumption factor. 1.0 = default. Only exceptions.
    consumption = {
        ['tug'] = 2.0,   -- big tank, drinks twice as much -> pricey fill, long range
    },

    -- Per-class consumption factor (vehicle class id -> factor). Absent = 1.0.
    -- Class ids: https://docs.fivem.net/natives/?_0x29439776AAA00A62
    class = {
        [8] = 0.6,   -- motorcycles sip fuel (same 65L tank as cars, longer range)
    },

    -- Models (or set true) with no fuel system. A handling value of 0 is also
    -- treated as no-fuel automatically (bicycles, trains, trailers).
    noFuel = {
        -- ['bmx'] = true,
    },

    -- Per-model fuel-cap offset for the physical pump nozzle {x, y, z} relative to
    -- the detected bone. Only exceptions; everything else uses pump.defaultCapOffset.
    fuelCaps = {
        ['kamacho'] = { -0.0, 0.55, 0.8 },
        ['winky']   = { -0.30, 0.25, 0.65 },
    },

    -- Electric vehicles. handling fPetrolTankVolume is unreliable for them
    -- (voltic/surge = 0 but tezeract/cyclone = 65), so battery capacity is set
    -- explicitly here. Value acts as the "tank" used for range/pricing (kWh-ish).
    electric = {
        ['cyclone']    = 65.0, ['cyclone2'] = 65.0, ['dilettante'] = 65.0,
        ['iwagen']     = 65.0, ['imorgon']  = 65.0, ['khamelion']  = 65.0,
        ['neon']       = 65.0, ['omnisegt'] = 65.0, ['raiden']     = 65.0,
        ['surge']      = 65.0, ['tezeract'] = 65.0, ['virtue']     = 65.0,
        ['voltic']     = 65.0,
    },
}
