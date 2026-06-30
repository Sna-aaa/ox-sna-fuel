# ox-sna-fuel

Fuel system covering all vehicles — fuel, electric, air, sea — with physical
nozzles & hoses and electric charging. ox-native rewrite of `sna-fuel`.
Framework-agnostic: **Qbox / QB-Core / ESX**, with **ox_lib** as the only hard dependency.

## Features

- Physical pump with nozzle + hose (pick it up, plug it into the fuel cap), server-synced for other players
- Works at **every** gas pump and supercharger on the map — no pump declaration, just `ox_target` on the models
- Out-of-fuel is handled by the script: the engine simply cuts, no GTA sparks / sputtering
- Tank size taken from each vehicle's handling (`fPetrolTankVolume`), overridable per vehicle
- Consumption handled by the game engine (RPM-aware), with a per-vehicle / per-class multiplier
- Electric vehicles: own **charge curve** (fast until 80%, then slower) and **automatic charging while parked in a garage**
- Energy in L or kWh, prices configurable
- Working fuel can (`WEAPON_PETROLCAN`): buy / refill at a pump, empty into a vehicle
- Admin command `/fuel [amount]` to refuel / charge the vehicle you're driving
- Exports `GetFuel` / `SetFuel` / `ApplyFuel` (also aliased under the legacy `sna-fuel` name)
- Everything is **by exception**: defaults come from the game, you only declare what differs

---

# Installation

Follow these steps in order. If you can copy/paste, you can install this.

### 1. Dependencies

Make sure these are already running on your server (they're standard on Qbox):

- `ox_lib`
- `ox_inventory`
- `ox_target`

You also need one framework, detected automatically: `qbx_core`, `qb-core`, or `es_extended`.

### 2. Remove your old fuel script

Delete / stop **any** other fuel or electricity script (`LegacyFuel`, `ps-fuel`,
`cdn-fuel`, `ox_fuel`, …). Running two fuel scripts at once **will** break things.

> Qbox ships `ox_fuel` by default — stop it (remove its `ensure`, or move it out of
> your resources folder) before using this one.

### 3. Install the resource

1. Put the `ox-sna-fuel` folder in your `resources` (anywhere, e.g. `[scripts]`).
2. Add it to your `server.cfg`:

```cfg
ensure ox-sna-fuel
```

3. Restart the server (a full restart the first time — it creates a database column automatically).

That's it for basic fuel. Start a car, drive, refuel at any pump. ✅

### 4. Make your HUD show the fuel

This script stores fuel in a **statebag**, not the native GTA fuel level. Most Qbox
HUDs already read it and need nothing. If your fuel gauge is stuck or empty:

- The fuel value lives in `Entity(vehicle).state.fuel` (a number 0–100).
- If your HUD reads an export instead, point it at:

```lua
exports['ox-sna-fuel']:GetFuel(vehicle)
```

(See **Troubleshooting → My fuel gauge doesn't move** below.)

### 5. (Optional) Electric charging in garages

Electric cars recharge while parked. This needs **two lines** added to your garage
script. If you use **ox-sna-garages it's already done** — skip this.
See **Garage integration** below for qbx_garages and others.

---

# Configuration

Three files, all commented:

| File | What's in it |
|---|---|
| `config/shared.lua` | Prices, fill speed, empty point, pump models, blips, fuel can, electric |
| `data/overrides.lua` | Per-vehicle exceptions (tank size, consumption, fuel-cap position, electric list) |
| `config/server.lua` | Server-side prices (anti-cheat) |

### The most common things you'll change

| I want to… | Change this |
|---|---|
| Make fuel cost more/less | `literPrice` / `kwPrice` in `config/shared.lua` |
| Make cars drain faster/slower | `baseRate` in `config/shared.lua` |
| Change where the engine dies (low fuel) | `lowFuelFloor` in `config/shared.lua` |
| Give one vehicle a bigger tank | add it to `tank` in `data/overrides.lua` |
| Make one vehicle/class thirstier | add it to `consumption` / `class` in `data/overrides.lua` |
| Mark a vehicle as electric | add it to `electric` in `data/overrides.lua` |

**Everything is by exception** — you don't list every vehicle. The game's own values
are used by default; you only add the ones that should differ.

Example `data/overrides.lua`:

```lua
tank        = { ['tug'] = 1000.0 },          -- the tug carries 1000 L
consumption = { ['tug'] = 2.0 },             -- and drinks twice as fast
class       = { [8] = 0.6 },                  -- all motorcycles sip fuel
electric    = { ['voltic'] = 65.0 },          -- voltic is electric, 65 kWh battery
```

---

# Garage integration (electric charge-over-time)

Electric vehicles recharge while parked, based on how long they sat. Driving
consumption is handled by the engine; only this charging feature needs the garage
to call into `ox-sna-fuel`. The database column is created automatically — **nothing
to import**.

Toggle in `config/shared.lua`:

```lua
electric = {
    garageCharge          = true,
    timeForCompleteCharge = 40,  -- minutes parked for a full 0 -> 100% charge
},
```

Add **two hooks** to the server side of your garage script:

**A. When a vehicle is stored / parked** — just before it gets deleted:

```lua
if GetResourceState('ox-sna-fuel') == 'started' then
    exports['ox-sna-fuel']:StoreVehicleCharge(netId)   -- non-EVs are ignored automatically
end
```

**B. When a vehicle is taken out / spawned** — once it exists:

```lua
if GetResourceState('ox-sna-fuel') == 'started' then
    local charge = exports['ox-sna-fuel']:GetGarageCharge(plate)   -- 0 for non-EVs
    if charge and charge > 0 then
        TriggerClientEvent('ox-sna-fuel:applyCharge', source, netId, charge)
    end
end
```

> `StoreVehicleCharge` takes the **netId** (the vehicle still exists when parking).
> `GetGarageCharge` takes the **plate** (the vehicle is freshly respawned when retrieving).

### ox-sna-garages — already wired

Nothing to do. (For reference: `server/main.lua`, hook A before `Bridge.DeleteVehicle`
in `parkVehicle`, hook B before `return netId, props` in `spawnVehicle`.)

### qbx_garages

- `server/main.lua` → `parkVehicle`: hook A before `exports.qbx_core:DeleteVehicle(vehicle)`.
- `server/spawn-vehicle.lua` → `spawnVehicle`: hook B before `return netId`, using `playerVehicle.props.plate` as the plate.

### Any other garage

Put hook A wherever it deletes the vehicle on park, and hook B wherever it spawns
the vehicle on retrieve (you need the spawned `netId`, the `source`, and the `plate`).

---

# Using it in-game

- **Refuel:** on foot, walk to any pump → target it (gas pump icon). With the physical
  pump on, you pick up the nozzle, walk to the car, and target the car to plug in.
- **Fuel can:** target a pump → *Buy a fuel can* / *Refill the can*. To use it, equip
  the can (like a weapon), target a vehicle → *Empty the can into the tank*.
- **Admin:** `/fuel [0-100]` sets the fuel of the car you're driving (needs `group.admin`).

---

# Exports

| Export | Side | Description |
|---|---|---|
| `exports['ox-sna-fuel']:GetFuel(vehicle)` | client | Current fuel, 0–100 |
| `exports['ox-sna-fuel']:SetFuel(vehicle, value)` | client | Set fuel, 0–100 |
| `exports['ox-sna-fuel']:ApplyFuel(vehicle, value)` | client | Alias of `SetFuel` (for persistence scripts) |
| `exports['ox-sna-fuel']:StoreVehicleCharge(netId)` | server | Stamp park time (EVs only) |
| `exports['ox-sna-fuel']:GetGarageCharge(plate)` | server | % charge gained while parked; clears the stamp |

The first three are also exported under the `sna-fuel` name for drop-in compatibility.

---

# Troubleshooting

**My fuel gauge doesn't move / is empty / is stuck.**
Your HUD isn't reading this script's fuel. The value is `Entity(vehicle).state.fuel`
(0–100). Either configure your HUD to read that statebag, or replace its
`GetVehicleFuelLevel(vehicle)` call with `exports['ox-sna-fuel']:GetFuel(vehicle)`.
Also make sure you removed your old fuel script (step 2).

**There's no option when I target a pump.**
`ox_target` isn't running, or your pump prop isn't in `config.pumpModels`. Add the
prop model name to that list.

**The engine dies too early / too late on low fuel.**
Raise or lower `lowFuelFloor` in `config/shared.lua`. Higher = the car stops with
more "real" fuel left; lower = it runs closer to empty (too low and GTA's ugly
sputter comes back).

**Fuel drains too fast or too slow for everything.**
Adjust `baseRate` in `config/shared.lua`. For a single vehicle/class, use
`consumption` / `class` in `data/overrides.lua` instead.

**One vehicle has a silly tank size (e.g. a boat empties instantly).**
Some vanilla handling values are odd. Override it in `data/overrides.lua` → `tank`.

**An electric car loses no charge while driving.**
Tell me — depending on the model the engine may not drain it; the fix is a small
EV-only decrement. (Charging and pricing already work.)

**My electric car doesn't recharge in the garage.**
Check `electric.garageCharge = true`, that the car is listed in `overrides.electric`,
and that your garage has the two hooks (step 5 / Garage integration). ox-sna-garages
has them already.

**The nozzle/hose looks wrong (floating, wrong spot).**
Cosmetics are tunable: `pump.ropeZ` and `pump.handBone` in `config/shared.lua`,
and per-model cap positions in `overrides.fuelCaps`.

**I can't buy / use the fuel can.**
The can is the `WEAPON_PETROLCAN` weapon item (default in ox_inventory). Buy it at a
pump, then **equip it like a weapon** before targeting a vehicle to empty it.
