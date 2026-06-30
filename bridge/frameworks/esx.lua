-- ESX contract. Same shape, identity = plate. To refine + test later.
return {
    vehicleTable  = 'owned_vehicles',
    vehicleColumn = 'plate',

    getVehicleId = function(vehicle)
        return GetVehicleNumberPlateText(vehicle)
    end,
}
