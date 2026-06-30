-- QB-Core contract. Same shape as qbx, identity = plate. To refine + test later.
return {
    vehicleTable  = 'player_vehicles',
    vehicleColumn = 'plate',

    getVehicleId = function(vehicle)
        return GetVehicleNumberPlateText(vehicle)
    end,
}
