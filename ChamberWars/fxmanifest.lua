fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Chamber wars'
author 'Patrick'
description 'Arena minigame'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/icons.js',
    'html/script.js',
    'html/img/heart.png',
    'html/img/pistol.png',
    'html/img/knife.png',
    'html/img/headshot.png',
    'html/img/weapon_pistol.png',
    'html/img/weapon_sniper.png',
    'html/img/weapon_shotgun.png'
}

client_scripts {
    '@PolyZone/client.lua',
    '@PolyZone/CircleZone.lua',
    'client/main.lua',
    'client/zones.lua',
    'client/npc.lua',
    'client/arena.lua'
}

server_scripts {
    'server/security.lua',
    'server/inventory.lua',
    'server/match.lua',
    'server/main.lua'
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
    'PolyZone'
}
