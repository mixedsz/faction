fx_version 'cerulean'
game 'gta5'

lua54 'yes'

author 'Flake Development'
description 'Drug Selling Script'


shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'config/edits.lua',
}

client_scripts{
    'client/*.lua',
}

server_scripts{
    '@oxmysql/lib/MySQL.lua',
    'config/logs.lua',
    'server/*.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/leaderboard.css',
    'html/leaderboard.js',
    'html/color-manager.js',
    'html/color-handler.js',
    'html/*.png'
}

escrow_ignore {
    'client/cl_notifications.lua',
    'server/sv_notifications.lua',
    'server/sv_robbery.lua',
    'config/*.lua',
}
dependency '/assetpacks'