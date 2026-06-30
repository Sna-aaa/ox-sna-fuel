local config = require 'config.shared'

if not config.fuelCan.enabled then return end

local CAN = config.fuelCan
local ox_inventory = exports.ox_inventory
local isUsing = false

--- The currently equipped weapon, if it is the fuel can.
local function currentCan()
    local w = ox_inventory:getCurrentWeapon()
    if w and w.name == CAN.item then return w end
    return nil
end

local function canFuel(can)
    return (can and can.metadata and can.metadata.ammo) or 0
end

--- Empty the equipped can into a vehicle (no money; limited by what's in the can).
local function useCanOnVehicle(vehicle)
    if isUsing or cache.vehicle then return end

    local can = currentCan()
    if not can then return end
    if canFuel(can) <= 0 then
        return lib.notify({ type = 'error', description = locale('can_empty') })
    end

    local tank = Fuel.getTankSize(vehicle)
    if tank <= 0.0 then
        return lib.notify({ type = 'error', description = locale('no_fuel_system') })
    end

    local current = Fuel.getFuel(vehicle)
    if current >= 99.5 then
        return lib.notify({ type = 'error', description = locale('tank_full') })
    end

    local slot      = can.slot
    local canLitres = canFuel(can) / 100.0 * CAN.litres

    local headroom    = (100.0 - current) / 100.0 * tank
    local totalLitres = math.min(canLitres, headroom)
    local duration    = math.ceil(totalLitres / CAN.litresPerTick) * config.refill.tickMs + 500

    isUsing = true
    TaskTurnPedToFaceEntity(cache.ped, vehicle, duration)
    Wait(300)

    CreateThread(function()
        lib.progressCircle({
            duration  = duration,
            canCancel = true,
            label     = locale('use_can'),
            disable   = { move = true, car = true, combat = true },
            anim      = { dict = 'weapon@w_sp_jerrycan', clip = 'fire' },
        })
        isUsing = false
    end)

    local dispensed = 0.0

    while isUsing do
        current = Fuel.getFuel(vehicle)
        if current >= 100.0 or canLitres <= 0.0 then break end

        local stepL = CAN.litresPerTick
        if stepL > canLitres then stepL = canLitres end

        local newFuel = current + (stepL / tank * 100.0)
        if newFuel > 100.0 then
            newFuel = 100.0
            stepL = (newFuel - current) / 100.0 * tank
        end

        canLitres = canLitres - stepL
        dispensed = dispensed + stepL
        Fuel.setFuelLocal(vehicle, newFuel)
        Fuel.showRefuelUI(dispensed, nil, false)

        if newFuel >= 100.0 or canLitres <= 0.0 then break end
        Wait(config.refill.tickMs)
    end

    isUsing = false
    Fuel.hideRefuelUI()
    if lib.progressActive() then lib.cancelProgress() end
    ClearPedTasks(cache.ped)

    local newAmmo = canLitres / CAN.litres * 100.0
    if newAmmo < 0.0 then newAmmo = 0.0 end

    TriggerServerEvent('ox-sna-fuel:can:use',
        NetworkGetNetworkIdFromEntity(vehicle), Fuel.getFuel(vehicle), newAmmo, slot)
end

CreateThread(function()
    -- buy / refill the can at the pump
    exports.ox_target:addModel(config.pumpModels, {
        {
            name        = 'oxsnafuel:canBuy',
            icon        = 'fas fa-cart-shopping',
            label       = locale('buy_can'),
            distance    = 2.5,
            canInteract = function() return not cache.vehicle end,
            onSelect    = function() TriggerServerEvent('ox-sna-fuel:can:buy') end,
        },
        {
            name        = 'oxsnafuel:canRefill',
            icon        = 'fas fa-faucet',
            label       = locale('refill_can'),
            distance    = 2.5,
            canInteract = function()
                local can = currentCan()
                return can ~= nil and canFuel(can) < 100 and not cache.vehicle
            end,
            onSelect    = function()
                local can = currentCan()
                if can then TriggerServerEvent('ox-sna-fuel:can:refill', can.slot) end
            end,
        },
    })

    -- empty the can into a vehicle
    exports.ox_target:addGlobalVehicle({
        {
            name        = 'oxsnafuel:canUse',
            icon        = 'fas fa-gas-pump',
            label       = locale('use_can'),
            distance    = 2.5,
            canInteract = function(entity)
                local can = currentCan()
                return can ~= nil and canFuel(can) > 0 and not cache.vehicle and Fuel.getTankSize(entity) > 0.0
            end,
            onSelect    = function(data) useCanOnVehicle(data.entity) end,
        },
    })
end)
