-- Auto-detect framework and load the matching contract into the global `Bridge`.
-- All framework-specific logic lives in bridge/frameworks/<name>.lua.
-- Loaded on both client and server.

local frameworks = {
    { resource = 'qbx_core',    name = 'qbx' },
    { resource = 'qb-core',     name = 'qb'  },
    { resource = 'es_extended', name = 'esx' },
}

local detected
for i = 1, #frameworks do
    if GetResourceState(frameworks[i].resource) == 'started' then
        detected = frameworks[i].name
        break
    end
end

if not detected then
    detected = 'qbx'
    lib.print.warn('No supported framework detected (qbx_core/qb-core/es_extended); defaulting to qbx contract.')
end

Bridge = lib.require(('bridge.frameworks.%s'):format(detected))
Bridge.framework = detected
