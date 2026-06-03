Config = {}

Config.ArenaName = 'Chamber Wars'
Config.Debug = false -- dit is handig voor fouten te kunnen vinden. 
Config.DebugPoly = false -- laat de polyzone zien van de arena handig als je het wilt instellen.
Config.SecurityLog = true -- false als je niet zoveel logs wilt.

Config.NPC = {
    model = 's_m_y_marine_01',
    coords = vec4(215.73, -810.09, 30.73, 159.0),
    scenario = 'WORLD_HUMAN_CLIPBOARD',
    interactionDistance = 2.0,
    serverValidationDistance = 4.0,
    targetIcon = 'fa-solid fa-crosshairs'
}

Config.Arena = {
    center = vec3(1366.6478, -578.5035, 74.3802),  
    radius = 101.0,
    debugSphere = {
        color = { r = 255, g = 0, b = 0, a = 95 },
        zOffset = 0.0
    },
    minZ = 69.0,
    maxZ = 90.0,
    boundaryGraceSeconds = 5,
    routingBucket = 7100,
    maxDurationSeconds = 600,
    spawnpoints = {
        vec4(1390.7542, -604.6699, 74.3378, 139.0144),   
        vec4(1386.7174, -539.1648, 74.3656, 163.9741), 
        vec4(1340.2468, -520.0311, 72.0657, 186.8351),
        vec4(1290.4852, -583.0341, 71.7442, 336.9441),
        vec4(1431.5316, -546.4120, 77.0370, 80.3415),
        vec4(1300.1204, -512.1649, 71.2532, 174.1542)
        
    }   
}

Config.Match = {
    minimumPlayers = 2,
    maximumPlayers = 6,
    countdownSeconds = 10,
    startLives = 3,
    bonusLifeKillStreak = 5,
    startAmmo = 3,
    pistolKillAmmoReward = 1,
    knifeKillAmmoReward = 1,
    pistolHitMaxDistance = 170.0,
    knifeHitMaxDistance = 5.0,
    respawnDelayMs = 1500,
    preVoteLoadMs = 0,
    introEnabled = true,
    introDurationMs = 5000,
    postIntroFreezeMs = 1000
}

Config.WeaponVote = {
    enabled = true,
    durationSeconds = 10,
    defaultWeapon = 'pistol',
    options = {
        {
            type = 'pistol',
            label = 'Pistol',
            item = 'WEAPON_PISTOL',
            image = 'img/weapon_pistol.png',
            ammo = 3,
            killAmmoReward = 1,
            maxDistance = 170.0
        },
        {
            type = 'sniper',
            label = 'Sniper',
            item = 'WEAPON_SNIPERRIFLE',
            image = 'img/weapon_sniper.png',
            ammo = 2,
            killAmmoReward = 1,
            maxDistance = 220.0
        },
        {
            type = 'shotgun',
            label = 'Shotgun',
            item = 'WEAPON_PUMPSHOTGUN',
            image = 'img/weapon_shotgun.png',
            ammo = 3,
            killAmmoReward = 1,
            maxDistance = 170.0
        }
    }
}

Config.Killfeed = {
    enabled = true,
    durationMs = 6000,
    maxItems = 5,
    useSteamAvatars = true
}

Config.KillEffect = {
    enabled = true,
    shake = 'SMALL_EXPLOSION_SHAKE',
    shakeIntensity = 0.28,
    timeScale = 0.82,
    durationMs = 260
}

Config.DeathAnimation = {
    enabled = true,
    ragdollDurationMs = 4500,
    impactLeadMs = 250
}

Config.Deathcam = {
    enabled = true,
    bodyViewMs = 1400,
    spectateMs = 5000,
    fadeMs = 350
}

Config.Leaderboard = {
    maxRows = 5
}

Config.TestBot = { 
    enabled = false, -- Toegevoegd om te testen als je alleen bent.
    soloOnly = true,
    model = 's_m_y_blackops_01',
    spawns = {
        vec4(1352.2833, -584.4617, 74.3653, 327.7341),
        vec4(1362.6129, -591.2761, 74.1768, 336.1417)
    },
    scenario = 'WORLD_HUMAN_GUARD_STAND',
    returnDelaySeconds = 5
}

Config.Items = {
    pistol = 'WEAPON_PISTOL',           
    sniper = 'WEAPON_SNIPERRIFLE',
    shotgun = 'WEAPON_PUMPSHOTGUN',
    knife = 'WEAPON_KNIFE',
    ammo = 'ammo-9',
    useAmmoItem = false
}

Config.AllowedWeapons = {
    pistol = {
        [joaat('WEAPON_PISTOL')] = true
    },
    sniper = {
        [joaat('WEAPON_SNIPERRIFLE')] = true
    },
    shotgun = {
        [joaat('WEAPON_PUMPSHOTGUN')] = true
    },
    knife = {
        [joaat('WEAPON_KNIFE')] = true
    }
}

Config.Reward = {
    enabled = true,
    account = 'money',
    amount = 500
}

Config.Cleanup = {
    blockOnFailure = true,
    retryAttempts = 2
}

Config.Security = {
    joinCooldownMs = 1500,
    leaveCooldownMs = 1000,
    infoCooldownMs = 750,
    hitReportCooldownMs = 250,
    deathReportCooldownMs = 2000,
    testBotKillCooldownMs = 250,
    voteCooldownMs = 500,
    cleanupCooldownMs = 3000
}
