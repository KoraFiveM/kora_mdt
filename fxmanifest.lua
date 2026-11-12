fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_mdt'
author 'qbcore2'
version '0.2.1'
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
    'config.lua',
    'shared/required.lua',
}

server_scripts { '@kora_sql/init.lua', 'server/schema.lua', 'server/boot.lua', 'server/main.lua' }
client_scripts { 'client/terminal.lua', 'client/main.lua' }

-- kora_qa: Gherkin test scenarios (converted legacy tests), see [kora]/kora_qa/README.md
qa_feature 'tests/*.feature'
