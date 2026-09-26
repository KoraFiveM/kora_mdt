fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbmdt'
author 'qbcore2'
version '0.2.0'
description 'Role-gated police, court, and medical records terminal'

dependency 'qblib'
dependency 'qbsql'
dependency 'qbcore'
dependency 'qbinventory'
dependency 'qbpolice'
dependency 'qbtarget'
dependency 'qbdispatch'

shared_scripts {
    '@qblib/init.lua',
    '@qbsql/init.lua',
    'config.lua',
}

server_scripts { 'server/migrate.lua', 'server/main.lua' }
client_scripts { 'client/terminal.lua', 'client/main.lua' }
