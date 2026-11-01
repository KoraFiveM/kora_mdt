fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_mdt'
-- Keep the legacy resource name resolvable for exports['qbmdt'] callers.
provide 'qbmdt'
author 'qbcore2'
version '0.2.0'
description 'Role-gated police, court, and medical records terminal'

dependency 'kora_lib'
dependency 'kora_sql'
dependency 'kora_core'
dependency 'kora_inventory'
dependency 'kora_police'
dependency 'kora_target'
dependency 'kora_dispatch'

shared_scripts {
    '@kora_lib/init.lua',
    '@kora_sql/init.lua',
    'config.lua',
    'shared/required.lua',
}

server_scripts { 'server/migrate.lua', 'server/main.lua' }
client_scripts { 'client/terminal.lua', 'client/main.lua' }
