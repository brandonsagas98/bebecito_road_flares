fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Bebecito Development'
description 'Bebecito Road Flares: Professional FiveM road safety flares resource.'
version '1.0.17'
dependency '/onesync'
dependency 'bd_road_flare_assets'
ui_page 'web/index.html'
files { 'textures/combustion.png', 'textures/smoke.png', 'textures/glow.png', 'web/index.html', 'web/audio.js', 'web/presentation.js', 'web/audio/combustion.wav', 'web/audio/strike.wav', 'web/audio/tap.wav' }

shared_scripts {
    'config.lua',
    'shared/constants.lua',
    'shared/utils.lua',
    'shared/realism.lua',
    'locales/es.lua',
    'locales/en.lua'
}

client_scripts {
    'client/presentation.lua',
    'client/effects.lua',
    'client/combustion.lua',
    'client/remote_held.lua',
    'client/audio.lua',
    'client/animations.lua',
    'client/placement.lua',
    'client/placing.lua',
    'client/world_flares.lua',
    'client/ground_physics.lua',
    'client/traffic_lite.lua',
    'client/native_routes.lua',
    'client/ground_visuals.lua',
    'client/deployment.lua',
    'client/interaction.lua',
    'client/main.lua'
}

server_scripts {
    'server/validation.lua',
    'server/permissions.lua',
    'server/inventory.lua',
    'server/held.lua',
    'server/registry.lua',
    'server/lifecycle.lua',
    'server/main.lua'
}

