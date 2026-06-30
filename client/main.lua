local config    = require 'config.shared'
local overrides = require 'data.overrides'

SetFuelConsumptionState(true)

local FLOOR = config.lowFuelFloor
local SPAN  = 100.0 - FLOOR

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function modelName(vehicle)
    return string.lower(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)))
end

local function isElectric(name)
    return overrides.electric[name] ~= nil
end

--- Tank size in litres, or 0 if the vehicle has no fuel system.
local function getTankSize(vehicle)
    local name = modelName(vehicle)

    if overrides.noFuel[name] then return 0.0 end
    if overrides.electric[name] then return overrides.electric[name] + 0.0 end

    local tank = overrides.tank[name]
    if tank then return tank + 0.0 end

    tank = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fPetrolTankVolume')
    if tank <= 0.0 then return 0.0 end -- 0 = no fuel (bikes/trains/trailers)
    if tank < config.tankClamp.min then tank = config.tankClamp.min end
    if tank > config.tankClamp.max then tank = config.tankClamp.max end
    return tank + 0.0
end

--- Per-vehicle consumption factor (model override > class > default).
local function getConsumptionFactor(vehicle)
    local name = modelName(vehicle)

    local f = overrides.consumption[name]
    if f then return f + 0.0 end

    f = overrides.class[GetVehicleClass(vehicle)]
    if f then return f + 0.0 end

    return 1.0
end

-- displayed fuel (0..100) <-> native gauge (FLOOR..100)
local function displayedFromNative(native)
    local d = (native - FLOOR) / SPAN * 100.0
    if d < 0.0 then return 0.0 end
    if d > 100.0 then return 100.0 end
    return d
end

local function nativeFromDisplayed(displayed)
    return FLOOR + (displayed / 100.0) * SPAN
end

--- Refill step (% per tick). Petrol and electric use different curves; the
--- electric one is OURS (fast then hard taper near full), not the game engine.
local function refillStep(current, electric, tank)
    if electric then
        -- electric: % curve, fast until the knee then crawls
        local r = config.refill.electric
        local step = r.percentPerTick
        if current > r.slowdownFrom then
            local t = (100.0 - current) / (100.0 - r.slowdownFrom)
            if t < 0.0 then t = 0.0 end
            step = step * (t ^ r.slowdownPow)
            if step < 0.05 then step = 0.05 end
        end
        return step
    end
    -- petrol: constant litres flow -> % per tick depends on tank size (big tank = slower)
    return config.refill.litresPerTick / tank * 100.0
end

--- Live refuel readout (litres/kWh dispensed + running cost). cost = nil hides price.
local function showRefuelUI(amount, cost, electric)
    local unit = electric and 'kWh' or 'L'
    local text = cost and ('%.1f %s  —  $%d'):format(amount, unit, math.floor(cost))
        or ('%.1f %s'):format(amount, unit)
    lib.showTextUI(text, { position = 'top-center', icon = electric and 'bolt' or 'gas-pump' })
end

local function hideRefuelUI()
    lib.hideTextUI()
end

--------------------------------------------------------------------------
-- Exports (+ legacy sna-fuel aliases; provide does NOT redirect exports)
--------------------------------------------------------------------------

local function getFuel(vehicle)
    local st = Entity(vehicle).state.fuel
    if st ~= nil then return st end
    return displayedFromNative(GetVehicleFuelLevel(vehicle))
end

local function setFuel(vehicle, value)
    if type(value) ~= 'number' then return end
    if getTankSize(vehicle) <= 0.0 then return end
    if value < 0.0 then value = 0.0 elseif value > 100.0 then value = 100.0 end
    SetVehicleFuelLevel(vehicle, nativeFromDisplayed(value))
    Entity(vehicle).state:set('fuel', value, true)
end

exports('GetFuel', getFuel)
exports('SetFuel', setFuel)
exports('ApplyFuel', setFuel) -- legacy name (old sna-fuel ApplyFuel took 0..100)

-- Alias the same exports under the old resource name so callers using
-- exports['sna-fuel']:GetFuel(...) keep working at runtime.
local function aliasExport(resource, name, fn)
    AddEventHandler(('__cfx_export_%s_%s'):format(resource, name), function(setCb)
        setCb(fn)
    end)
end
aliasExport('sna-fuel', 'GetFuel', getFuel)
aliasExport('sna-fuel', 'SetFuel', setFuel)
aliasExport('sna-fuel', 'ApplyFuel', setFuel)

--------------------------------------------------------------------------
-- Core loop: native engine consumes; we mirror to the statebag and run the
-- custom empty cut. No per-tick maths, just a light ~1s mirror + panne check.
--------------------------------------------------------------------------

local function runFuelLoop()
    local vehicle = cache.vehicle
    if not vehicle or cache.seat ~= -1 then return end

    local tank = getTankSize(vehicle)
    if tank <= 0.0 then return end -- no fuel system: nothing to manage

    -- Per-vehicle consumption multiplier, set once on entry.
    -- Bigger tank -> lower %/sec -> longer range. Factor scales the feel.
    local rate = config.baseRate * getConsumptionFactor(vehicle) * (config.defaultTank / tank)

    local vehState = Entity(vehicle).state

    -- Initialise statebag fuel if this vehicle has never been seen.
    local displayed = vehState.fuel
    if displayed == nil then
        displayed = displayedFromNative(GetVehicleFuelLevel(vehicle))
        if displayed <= 0.0 then displayed = math.random(20, 80) + 0.0 end
        vehState:set('fuel', displayed, true)
    end

    -- Sync the native gauge to our displayed value.
    SetVehicleFuelLevel(vehicle, nativeFromDisplayed(displayed))

    local outOfFuel = false

    -- Per-frame guard: while empty, keep the engine OFF so the player can't restart
    -- and lurch forward between mirror ticks. The car still coasts, steers and brakes
    -- (engine off, no power) so you can pull over to the side of the road.
    CreateThread(function()
        while cache.seat == -1 and cache.vehicle == vehicle and DoesEntityExist(vehicle) do
            if outOfFuel then
                SetVehicleEngineOn(vehicle, false, true, true)
                Wait(0)
            else
                Wait(300)
            end
        end
    end)

    while cache.seat == -1 and DoesEntityExist(vehicle) do
        if GetIsVehicleEngineRunning(vehicle) then
            SetFuelConsumptionRateMultiplier(rate)
        else
            SetFuelConsumptionRateMultiplier(0.0)
        end

        displayed = displayedFromNative(GetVehicleFuelLevel(vehicle))

        if displayed <= 0.0 then
            displayed = 0.0
            SetVehicleFuelLevel(vehicle, FLOOR) -- pin above the ugly band
            outOfFuel = true                    -- the per-frame guard takes over
        else
            outOfFuel = false
        end

        vehState:set('fuel', displayed, true)
        Wait(1000)
    end
end

if cache.seat == -1 then CreateThread(runFuelLoop) end

lib.onCache('seat', function(seat)
    if seat == -1 then SetTimeout(0, runFuelLoop) end
end)

--------------------------------------------------------------------------
-- Admin: set the fuel of the vehicle you are driving (relayed from server)
--------------------------------------------------------------------------

RegisterNetEvent('ox-sna-fuel:setCurrentFuel', function(amount)
    local vehicle = cache.vehicle
    if not vehicle or cache.seat ~= -1 then
        return lib.notify({ type = 'error', description = locale('must_be_driver') })
    end
    if getTankSize(vehicle) <= 0.0 then
        return lib.notify({ type = 'error', description = locale('no_fuel_system') })
    end
    setFuel(vehicle, amount + 0.0)
    lib.notify({ type = 'success', description = locale('fuel_set', math.floor(amount)) })
end)

-- Electric: add the charge gained while parked in a garage (sent by the garage
-- resource after it spawns the vehicle; pct is computed server-side).
RegisterNetEvent('ox-sna-fuel:applyCharge', function(netId, pct)
    if type(pct) ~= 'number' or pct <= 0 then return end
    CreateThread(function()
        local veh, t = 0, 0
        repeat
            veh = NetworkGetEntityFromNetworkId(netId)
            if veh ~= 0 and DoesEntityExist(veh) then break end
            Wait(50); t = t + 1
        until t > 60
        if veh == 0 or not DoesEntityExist(veh) then return end
        if getTankSize(veh) <= 0.0 then return end
        setFuel(veh, math.min(100.0, getFuel(veh) + pct))
    end)
end)

--------------------------------------------------------------------------
-- Blips
--------------------------------------------------------------------------

local function makeBlip(coords, sprite, colour, label)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite)
    SetBlipScale(blip, 0.7)
    SetBlipColour(blip, colour)
    SetBlipDisplay(blip, 4)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
    return blip
end

CreateThread(function()
    if not config.showBlips then return end
    for i = 1, #config.gasStations do
        makeBlip(config.gasStations[i], 361, 4, locale('blip_fuel'))
    end
    for i = 1, #config.superchargerStations do
        makeBlip(config.superchargerStations[i], 354, 4, locale('blip_electric'))
    end
end)

--------------------------------------------------------------------------
-- Shared helpers exposed to client/pump.lua (the pump) and client/can.lua
--------------------------------------------------------------------------

Fuel = {
    modelName           = modelName,
    isElectric          = isElectric,
    getTankSize         = getTankSize,
    getFuel             = getFuel,
    nativeFromDisplayed = nativeFromDisplayed,
    refillStep          = refillStep,
    showRefuelUI        = showRefuelUI,
    hideRefuelUI        = hideRefuelUI,

    -- local-only fuel write (used during fill; server replicates the final value)
    setFuelLocal = function(vehicle, value)
        if value < 0.0 then value = 0.0 elseif value > 100.0 then value = 100.0 end
        SetVehicleFuelLevel(vehicle, nativeFromDisplayed(value))
        Entity(vehicle).state:set('fuel', value, false)
    end,
}
