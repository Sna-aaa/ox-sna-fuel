fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'ox-sna-fuel'
author 'Sna'
version '0.1.0'
description 'Framework-agnostic fuel (ox-native) - ex sna-fuel'
repository ''

-- Keep legacy resource name references working (events). NOTE: provide does NOT
-- redirect runtime exports -> exports are aliased manually (client/main.lua).
provide 'sna-fuel'

dependencies {
    'ox_lib',
    'ox_inventory',
    'ox_target',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config/shared.lua',
}

client_scripts {
    'bridge/init.lua',
    'client/main.lua',
    'client/pump.lua',
    'client/can.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config/server.lua',
    'bridge/init.lua',
    'server/main.lua',
}

files {
    'locales/*.json',
    'data/*.lua',
    'bridge/frameworks/*.lua',
}

ox_libs {
    'locale',
    'math',
}
