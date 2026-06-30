local config    = require 'config.shared'
local overrides = require 'data.overrides'

local PUMP = config.pump

local isFueling
local nozzle               -- { prop, netId, pump, pumpCoords, mounted, vehicle }
local remoteRopes = {}     -- netId -> { rope, anchor } (ropes drawn for any nozzle, incl. ours)

local function getMoney()
    return exports.ox_inventory:GetItemCount('money') or 0
end

local function loadModel(model)
    if HasModelLoaded(model) then return true end
    RequestModel(model)
    local t = 0
    while not HasModelLoaded(model) and t < 200 do Wait(10); t = t + 1 end
    return HasModelLoaded(model)
end

--------------------------------------------------------------------------
-- Fuel cap detection (bone + per-model offset)
--------------------------------------------------------------------------

local function detectFuelCap(vehicle)
    local offset = overrides.fuelCaps[Fuel.modelName(vehicle)] or PUMP.defaultCapOffset

    for i = 1, #PUMP.capBones do
        local boneIndex = GetEntityBoneIndexByName(vehicle, PUMP.capBones[i])
        if boneIndex ~= -1 then
            local world = GetWorldPositionOfEntityBone(vehicle, boneIndex)
            local off = GetOffsetFromEntityGivenWorldCoords(vehicle, world.x, world.y, world.z)
            off = vec3(off.x + offset[1], off.y + offset[2], off.z + offset[3])
            return GetOffsetFromEntityInWorldCoords(vehicle, off.x, off.y, off.z)
        end
    end
    return nil
end

--------------------------------------------------------------------------
-- Rope drawing (every client builds its own rope from the pump to the nozzle
-- prop, which is a networked object resolved by its net id)
--------------------------------------------------------------------------

local function buildRope(netId, pumpCoords)
    if remoteRopes[netId] then return end
    if not loadModel(joaat(PUMP.anchorModel)) then return end

    local anchor = CreateObject(joaat(PUMP.anchorModel), pumpCoords.x, pumpCoords.y, pumpCoords.z, true, true, false)
    SetEntityRecordsCollisions(anchor, false)
    SetEntityLoadCollisionFlag(anchor, false)

    local prop, t = nil, 0
    while t < 50 do
        if NetworkDoesEntityExistWithNetworkId(netId) then
            prop = NetworkGetEntityFromNetworkId(netId)
            break
        end
        Wait(100); t = t + 1
    end

    if not prop or prop == 0 then
        if DoesEntityExist(anchor) then DeleteEntity(anchor) end
        return
    end

    RopeLoadTextures()
    while not RopeAreTexturesLoaded() do Wait(0) end

    local topX, topY, topZ = pumpCoords.x, pumpCoords.y, pumpCoords.z + PUMP.ropeZ
    local propCoords = GetOffsetFromEntityInWorldCoords(prop, 0.0, -0.019, -0.1749)

    local rope = AddRope(topX, topY, topZ, 0.0, 0.0, 0.0, PUMP.ropeLength, 1, 1000.0, 0.5, 1.0,
        false, false, false, 5.0, false, 0)
    AttachEntitiesToRope(rope, prop, anchor, propCoords.x, propCoords.y, propCoords.z,
        topX, topY, topZ, PUMP.ropeMaxLength, 0, 0)

    remoteRopes[netId] = { rope = rope, anchor = anchor }
end

local function destroyRope(netId)
    local r = remoteRopes[netId]
    if not r then return end
    if r.rope then DeleteRope(r.rope) end
    if r.anchor and DoesEntityExist(r.anchor) then DeleteEntity(r.anchor) end
    remoteRopes[netId] = nil
end

RegisterNetEvent('ox-sna-fuel:rope:attach', function(netId, pumpCoords)
    buildRope(netId, pumpCoords)
end)

RegisterNetEvent('ox-sna-fuel:rope:detach', function(netId)
    destroyRope(netId)
end)

--------------------------------------------------------------------------
-- Owner: pick up / return the nozzle
--------------------------------------------------------------------------

local function attachToHand(prop)
    local bone = GetPedBoneIndex(cache.ped, PUMP.handBone)
    AttachEntityToEntity(prop, cache.ped, bone, 0.0549, 0.049, 0.0, -50.0, -90.0, -50.0,
        true, true, false, false, 0, true)
end

local function pickupNozzle(pumpEntity)
    if nozzle then return end
    if not loadModel(joaat(PUMP.nozzleModel)) then return end

    local prop = CreateObject(joaat(PUMP.nozzleModel), 1.0, 1.0, 1.0, true, true, false)
    attachToHand(prop)

    local netId = ObjToNet(prop)
    SetNetworkIdExistsOnAllMachines(netId, true)
    NetworkSetNetworkIdDynamic(netId, true)
    SetNetworkIdCanMigrate(netId, false)

    local pumpCoords = GetEntityCoords(pumpEntity)
    nozzle = { prop = prop, netId = netId, pump = pumpEntity, pumpCoords = pumpCoords, mounted = false }

    -- broadcast (server relays to everyone, including us, who build the rope)
    TriggerServerEvent('ox-sna-fuel:rope:attach', netId, pumpCoords)
    lib.notify({ description = locale('nozzle_taken') })
end

local function returnNozzle()
    if not nozzle then return end
    local netId = nozzle.netId

    TriggerServerEvent('ox-sna-fuel:rope:detach', netId)
    destroyRope(netId)

    if DoesEntityExist(nozzle.prop) then
        DetachEntity(nozzle.prop, true, true)
        DeleteEntity(nozzle.prop)
    end

    nozzle = nil
    lib.notify({ description = locale('nozzle_returned') })
end

--------------------------------------------------------------------------
-- Owner: plug the nozzle into the cap and refuel
--------------------------------------------------------------------------

local function mountAndFuel(vehicle)
    if not nozzle or isFueling then return end

    local tank = Fuel.getTankSize(vehicle)
    if tank <= 0.0 then
        return lib.notify({ type = 'error', description = locale('no_fuel_system') })
    end

    local current = Fuel.getFuel(vehicle)
    if current >= 99.5 then
        return lib.notify({ type = 'error', description = locale('tank_full') })
    end

    if getMoney() < config.literPrice then
        return lib.notify({ type = 'error', description = locale('not_enough_money') })
    end

    local capPos = detectFuelCap(vehicle)
    if not capPos then
        return lib.notify({ type = 'error', description = locale('no_fuel_cap') })
    end
    if #(GetEntityCoords(cache.ped) - capPos) > PUMP.plugDistance then
        return lib.notify({ type = 'error', description = locale('cap_far') })
    end

    -- plug the nozzle into the cap
    local off = GetOffsetFromEntityGivenWorldCoords(vehicle, capPos.x, capPos.y, capPos.z)
    DetachEntity(nozzle.prop, true, true)
    AttachEntityToEntity(nozzle.prop, vehicle, 0, off.x, off.y, off.z, -50.0, 0.0, -90.0,
        true, true, false, false, 0, true)
    nozzle.mounted = true
    nozzle.vehicle = vehicle

    local elec      = Fuel.isElectric(Fuel.modelName(vehicle))
    local price     = elec and config.kwPrice or config.literPrice
    local refill    = config.refill
    local cost      = 0.0
    local litres    = 0.0
    local startFuel = current
    isFueling = true

    -- the nozzle rests in the cap and fuel flows; the player is free to move.
    -- Stopping early = take the nozzle back (ox_target option below sets isFueling=false).
    while isFueling do
        current = Fuel.getFuel(vehicle)

        local step = Fuel.refillStep(current, elec, tank)

        local newFuel = current + step
        if newFuel > 100.0 then newFuel = 100.0 end

        local tickCost = (newFuel - current) / 100.0 * tank * price
        if getMoney() < cost + tickCost then
            lib.notify({ type = 'error', description = locale('not_enough_money') })
            break
        end

        -- hose yanked: stop if the player walked too far from the pump
        if #(GetEntityCoords(cache.ped) - nozzle.pumpCoords) > PUMP.ropeMaxLength then break end

        cost = cost + tickCost
        litres = litres + (newFuel - current) / 100.0 * tank
        Fuel.setFuelLocal(vehicle, newFuel)
        Fuel.showRefuelUI(litres, cost, elec)

        if newFuel >= 100.0 then break end
        Wait(refill.tickMs)
    end

    isFueling = false
    Fuel.hideRefuelUI()

    -- unplug -> back to hand
    if nozzle then
        if DoesEntityExist(nozzle.prop) then
            DetachEntity(nozzle.prop, true, true)
            attachToHand(nozzle.prop)
        end
        nozzle.mounted = false
        nozzle.vehicle = nil
    end

    -- server prices the litres we dispensed and bills what the player can afford;
    -- apply the fuel matching the fraction actually paid (no free fuel on drop-money).
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local frac  = lib.callback.await('ox-sna-fuel:pay', false, netId, litres)
    if type(frac) ~= 'number' then frac = 1.0 end

    local paidFuel = (frac >= 1.0) and Fuel.getFuel(vehicle)
        or (startFuel + (litres * frac) / tank * 100.0)
    if paidFuel < 0.0 then paidFuel = 0.0 elseif paidFuel > 100.0 then paidFuel = 100.0 end

    SetVehicleFuelLevel(vehicle, Fuel.nativeFromDisplayed(paidFuel))
    Entity(vehicle).state:set('fuel', paidFuel, true)
end

--------------------------------------------------------------------------
-- Targets
--------------------------------------------------------------------------

CreateThread(function()
    exports.ox_target:addModel(config.pumpModels, {
        {
            name        = 'oxsnafuel:takeNozzle',
            icon        = 'fas fa-gas-pump',
            label       = locale('take_nozzle'),
            distance    = 2.5,
            canInteract = function() return not nozzle and not cache.vehicle end,
            onSelect    = function(data) pickupNozzle(data.entity) end,
        },
        {
            name        = 'oxsnafuel:returnNozzle',
            icon        = 'fas fa-rotate-left',
            label       = locale('return_nozzle'),
            distance    = 2.5,
            canInteract = function() return nozzle ~= nil and not isFueling end,
            onSelect    = returnNozzle,
        },
    })

    exports.ox_target:addGlobalVehicle({
        {
            name        = 'oxsnafuel:plug',
            icon        = 'fas fa-gas-pump',
            label       = locale('refuel'),
            distance    = 2.5,
            canInteract = function(entity)
                return nozzle ~= nil and not nozzle.mounted and not isFueling
                    and not cache.vehicle and Fuel.getTankSize(entity) > 0.0
            end,
            onSelect    = function(data) mountAndFuel(data.entity) end,
        },
        {
            name        = 'oxsnafuel:stopFueling',
            icon        = 'fas fa-hand',
            label       = locale('stop_fueling'),
            distance    = 2.5,
            canInteract = function() return isFueling end,
            onSelect    = function() isFueling = false end,
        },
    })
end)

-- Auto-return the nozzle if the player wanders too far while just holding it.
CreateThread(function()
    while true do
        if nozzle and not nozzle.mounted and not isFueling then
            if #(GetEntityCoords(cache.ped) - nozzle.pumpCoords) > PUMP.ropeMaxLength then
                lib.notify({ type = 'error', description = locale('too_far') })
                returnNozzle()
            end
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for netId in pairs(remoteRopes) do destroyRope(netId) end
    if nozzle and DoesEntityExist(nozzle.prop) then DeleteEntity(nozzle.prop) end
end)
