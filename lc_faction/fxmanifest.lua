fx_version 'cerulean'
game 'gta5'

author 'Your Name'
description 'Advanced Faction Management System for ESX'
version '1.0.0'

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
    'config.lua'
}

server_scripts {
    'server/database.lua',
    'server/factions.lua',
    'server/members.lua',
    'server/territory.lua',
    'server/conflicts.lua',
    'server/weapons.lua',
    'server/cooldowns.lua',
    'server/admin.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

client_scripts {
    'client/main.lua',
    'client/ui.lua',
    'client/admin.lua',
    'client/territory.lua',
    'client/weapons.lua'
}

files {
    'html/index.html',
    'html/styles.css',
    'html/styles_ck_report.css',
    'html/script.js'
}

dependencies {
    'es_extended',
    'ox_lib'
}

lua54 'yes'
