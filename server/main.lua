local config       = require 'config.server'
local sharedConfig = require 'config.shared'
local overrides    = require 'data.overrides'
local ox_inventory = exports.ox_inventory

-- electric vehicle model hashes (kWh pricing + charge-over-time)
local electricHash = {}
for name in pairs(overrides.electric) do electricHash[joaat(name)] = true end

--------------------------------------------------------------------------
-- Admin command: /fuel [amount]  (set fuel of the vehicle you drive)
-- ace: group.admin
--------------------------------------------------------------------------

lib.addCommand('fuel', {
    help = 'Set the fuel level of the vehicle you are driving',
    restricted = 'group.admin',
    params = {
        { name = 'amount', type = 'number', help = '0-100 (default 100)', optional = true },
    },
}, function(source, args)
    local amount = args.amount or 100
    if amount < 0 then amount = 0 elseif amount > 100 then amount = 100 end
    TriggerClientEvent('ox-sna-fuel:setCurrentFuel', source, amount + 0.0)
end)

--------------------------------------------------------------------------
-- Pump payment (server-authoritative, per-litre). The client reports the litres
-- it dispensed; the server prices them (its own price, EV detected here) and bills
-- what the player can afford, returning the paid fraction. The client then applies
-- the matching fuel with its own tank size -> the server never needs the tank.
-- Drop your money mid-fill and you simply get less fuel, paid for what you got.
--------------------------------------------------------------------------

lib.callback.register('ox-sna-fuel:pay', function(src, netId, litres)
    if type(litres) ~= 'number' or litres <= 0 then return 0.0 end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    local elec    = vehicle and vehicle ~= 0 and electricHash[GetEntityModel(vehicle)]
    local price   = elec and sharedConfig.kwPrice or sharedConfig.literPrice
    local cost  = litres * price
    if cost <= 0 then return 1.0 end

    local money = ox_inventory:GetItemCount(src, 'money') or 0
    local frac, pay
    if money >= cost then
        frac, pay = 1.0, math.floor(cost + 0.5)   -- can afford the full amount
    else
        frac, pay = money / cost, money            -- only afford part of it
    end
    if pay > 0 then ox_inventory:RemoveItem(src, 'money', pay) end

    TriggerClientEvent('ox_lib:notify', src, {
        type        = frac >= 1.0 and 'success' or 'error',
        description = frac >= 1.0 and locale('fuel_success', pay) or locale('not_enough_money'),
    })
    return frac
end)

--------------------------------------------------------------------------
-- Physical pump: relay rope attach/detach to every client so others see it
--------------------------------------------------------------------------

RegisterNetEvent('ox-sna-fuel:rope:attach', function(netId, pumpCoords)
    if type(netId) ~= 'number' then return end
    TriggerClientEvent('ox-sna-fuel:rope:attach', -1, netId, pumpCoords)
end)

RegisterNetEvent('ox-sna-fuel:rope:detach', function(netId)
    if type(netId) ~= 'number' then return end
    TriggerClientEvent('ox-sna-fuel:rope:detach', -1, netId)
end)

--------------------------------------------------------------------------
-- Electric: charge-over-time while parked in a garage.
-- Consumption itself is handled by the game engine (no electric-specific code).
-- The garage resource calls these exports:
--   exports['ox-sna-fuel']:StoreVehicleCharge(netId)        -- on store (EVs only, auto-filtered)
--   local pct = exports['ox-sna-fuel']:GetGarageCharge(plate) -- on retrieve -> apply pct to fuel
--------------------------------------------------------------------------

CreateThread(function()
    if not sharedConfig.electric.garageCharge then return end
    -- auto-migration (MariaDB supports ADD COLUMN IF NOT EXISTS), same pattern as ox-sna-garages
    MySQL.query(('ALTER TABLE `%s` ADD COLUMN IF NOT EXISTS `fuel_datetimein` INT NULL')
        :format(Bridge.vehicleTable))
end)

-- Stamp the park time for an ELECTRIC vehicle (call on store). netId-based so we
-- can auto-filter to EVs only; non-EVs are never stamped and earn no charge.
exports('StoreVehicleCharge', function(netId)
    if not sharedConfig.electric.garageCharge or type(netId) ~= 'number' then return end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not electricHash[GetEntityModel(vehicle)] then return end
    local plate = GetVehicleNumberPlateText(vehicle)
    if not plate then return end
    MySQL.update(('UPDATE `%s` SET `fuel_datetimein` = ? WHERE `%s` = ?')
        :format(Bridge.vehicleTable, Bridge.vehicleColumn), { os.time(), plate })
end)

-- Return the % charge gained since the vehicle was stored, then clear the stamp.
-- Call on retrieve and add the result to the vehicle's fuel.
exports('GetGarageCharge', function(identifier)
    if not sharedConfig.electric.garageCharge or not identifier then return 0.0 end

    local row = MySQL.single.await(('SELECT `fuel_datetimein` FROM `%s` WHERE `%s` = ?')
        :format(Bridge.vehicleTable, Bridge.vehicleColumn), { identifier })

    if not row or not row.fuel_datetimein or row.fuel_datetimein == 0 then return 0.0 end

    local elapsed = os.time() - row.fuel_datetimein
    if elapsed < 0 then elapsed = 0 end

    local pct = 100.0 / (sharedConfig.electric.timeForCompleteCharge * 60) * elapsed
    if pct > 100.0 then pct = 100.0 end

    MySQL.update(('UPDATE `%s` SET `fuel_datetimein` = NULL WHERE `%s` = ?')
        :format(Bridge.vehicleTable, Bridge.vehicleColumn), { identifier })

    return pct
end)

--------------------------------------------------------------------------
-- Fuel can (WEAPON_PETROLCAN): buy / refill at a pump, server-authoritative
--------------------------------------------------------------------------

RegisterNetEvent('ox-sna-fuel:can:buy', function()
    local src = source
    if not sharedConfig.fuelCan.enabled then return end

    if not ox_inventory:CanCarryItem(src, sharedConfig.fuelCan.item, 1) then
        return TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = locale('can_cannot_carry') })
    end
    if not ox_inventory:RemoveItem(src, 'money', sharedConfig.fuelCan.buyPrice) then
        return TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = locale('not_enough_money') })
    end

    ox_inventory:AddItem(src, sharedConfig.fuelCan.item, 1, { ammo = 100, durability = 100 })
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = locale('can_bought', sharedConfig.fuelCan.buyPrice) })
end)

RegisterNetEvent('ox-sna-fuel:can:refill', function(slot)
    local src = source
    if not sharedConfig.fuelCan.enabled or type(slot) ~= 'number' then return end

    local item = ox_inventory:GetSlot(src, slot)
    if not item or item.name ~= sharedConfig.fuelCan.item then return end

    local ammo = (item.metadata and item.metadata.ammo) or 0
    if ammo >= 100 then return end

    -- bill the litres added at the fuel price (a new can is bought at buyPrice instead)
    local litres = (100 - ammo) / 100 * sharedConfig.fuelCan.litres
    local cost   = math.floor(litres * sharedConfig.literPrice + 0.5)
    if cost < 1 then cost = 1 end
    if not ox_inventory:RemoveItem(src, 'money', cost) then
        return TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = locale('not_enough_money') })
    end

    local md = item.metadata or {}
    md.ammo = 100; md.durability = 100
    ox_inventory:SetMetadata(src, slot, md)
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = locale('can_refilled', cost) })
end)

-- Use the can on a vehicle: client runs the transfer, server commits both sides.
RegisterNetEvent('ox-sna-fuel:can:use', function(netId, fuel, canAmmo, slot)
    local src = source
    if not sharedConfig.fuelCan.enabled then return end
    if type(netId) ~= 'number' or type(fuel) ~= 'number' or type(canAmmo) ~= 'number' or type(slot) ~= 'number' then return end

    local item = ox_inventory:GetSlot(src, slot)
    if not item or item.name ~= sharedConfig.fuelCan.item then return end

    if fuel < 0 then fuel = 0.0 elseif fuel > 100 then fuel = 100.0 end
    if canAmmo < 0 then canAmmo = 0 elseif canAmmo > 100 then canAmmo = 100 end

    local md = item.metadata or {}
    md.ammo = math.floor(canAmmo); md.durability = math.floor(canAmmo)
    ox_inventory:SetMetadata(src, slot, md)

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle and vehicle ~= 0 and GetEntityType(vehicle) == 2 then
        Entity(vehicle).state:set('fuel', fuel, true)
    end
end)

--------------------------------------------------------------------------
-- TODO (next milestones):
--   * Refine + test qb/esx bridges
--------------------------------------------------------------------------
