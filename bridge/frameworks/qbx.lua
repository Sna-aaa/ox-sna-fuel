-- Qbox contract (primary target).
return {
    -- Owned-vehicle table + lookup column (used later for electric charge-over-time).
    vehicleTable  = 'player_vehicles',
    vehicleColumn = 'plate',

    -- Persistent vehicle identity. qbx exposes a `vehicleid` statebag; fall back to plate.
    getVehicleId = function(vehicle)
        local id = Entity(vehicle).state.vehicleid
        if id then return id end
        return GetVehicleNumberPlateText(vehicle)
    end,
}
