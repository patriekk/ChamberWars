local spectator = {
    active = false,
    cam = nil,
    targetServerId = nil
}

local function destroySpectatorCam()
    if spectator.cam and DoesCamExist(spectator.cam) then
        RenderScriptCams(false, true, 250, true, true)
        DestroyCam(spectator.cam, false)
    end

    spectator.active = false
    spectator.cam = nil
    spectator.targetServerId = nil
    ClearFocus()
end

local function setSpectatorPedHidden(hidden)
    NetworkSetEntityInvisibleToNetwork(cache.ped, hidden)
    SetEntityVisible(cache.ped, not hidden, false)
    SetEntityCollision(cache.ped, not hidden, not hidden)

    if hidden then
        SetEntityAlpha(cache.ped, 0, false)
        FreezeEntityPosition(cache.ped, true)
    else
        ResetEntityAlpha(cache.ped)
        FreezeEntityPosition(cache.ped, false)
    end
end

local function leaveSpectator()
    NetworkSetInSpectatorMode(false, cache.ped)
    destroySpectatorCam()
    setSpectatorPedHidden(false)
end

local function startSpectating(targetServerId)
    local player = GetPlayerFromServerId(targetServerId)
    if player == -1 then
        return
    end

    local targetPed = GetPlayerPed(player)
    if not targetPed or targetPed == 0 or not DoesEntityExist(targetPed) then
        return
    end

    destroySpectatorCam()
    NetworkSetInSpectatorMode(false, cache.ped)

    spectator.active = true
    spectator.targetServerId = targetServerId
    spectator.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

    AttachCamToEntity(spectator.cam, targetPed, 0.0, -4.0, 1.35, true)
    PointCamAtEntity(spectator.cam, targetPed, 0.0, 0.0, 0.8, true)
    SetCamFov(spectator.cam, 55.0)
    SetCamActive(spectator.cam, true)
    RenderScriptCams(true, true, 250, true, true)
    SetFocusEntity(targetPed)

    setSpectatorPedHidden(true)

    CreateThread(function()
        while spectator.active and spectator.targetServerId == targetServerId do
            local targetPlayer = GetPlayerFromServerId(targetServerId)
            local currentTargetPed = targetPlayer ~= -1 and GetPlayerPed(targetPlayer) or 0

            if currentTargetPed == 0 or not DoesEntityExist(currentTargetPed) then
                destroySpectatorCam()
                break
            end

            AttachCamToEntity(spectator.cam, currentTargetPed, 0.0, -4.0, 1.35, true)
            PointCamAtEntity(spectator.cam, currentTargetPed, 0.0, 0.0, 0.8, true)
            SetFocusEntity(currentTargetPed)
            Wait(500)
        end
    end)
end

local function resurrectAt(coords, heading)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading or 0.0, true, false)
    SetEntityHealth(cache.ped, GetEntityMaxHealth(cache.ped))
    ClearPedTasksImmediately(cache.ped)
    ClearPedSecondaryTask(cache.ped)
    ClearPedBloodDamage(cache.ped)
    ResetPedVisibleDamage(cache.ped)
    ClearEntityLastDamageEntity(cache.ped)
end

local function clearDeathState()
    local esx = exports['es_extended']:getSharedObject()
    if esx and esx.SetPlayerData then
        esx.SetPlayerData('ped', cache.ped)
        esx.SetPlayerData('dead', false)
    end

    LocalPlayer.state:set('dead', false, true)
    TriggerEvent('esx:onPlayerSpawn')
end

local function setLivesUi(visible, lives, maxLives)
    SendNUIMessage({
        action = visible and 'showLives' or 'hideLives',
        lives = lives or 0,
        maxLives = maxLives or Config.Match.startLives
    })
end

local function updateLivesUi(lives, maxLives, gainedLife)
    SendNUIMessage({
        action = 'updateLives',
        lives = lives or 0,
        maxLives = maxLives or Config.Match.startLives,
        gainedLife = gainedLife == true
    })
end

local function resetArenaPed()
    SetEntityInvincible(cache.ped, false)
    FreezeEntityPosition(cache.ped, false)
    SetPlayerControl(PlayerId(), true, 0)
    DisablePlayerFiring(PlayerId(), false)
    SetPedCanSwitchWeapon(cache.ped, true)
    SetPedCurrentWeaponVisible(cache.ped, true, true, true, true)
end

local function lockArenaPed()
    SetEntityInvincible(cache.ped, true)
    FreezeEntityPosition(cache.ped, true)
    SetPlayerControl(PlayerId(), false, 0)
    DisablePlayerFiring(PlayerId(), true)
end

local function prepareArenaPed()
    SetEntityInvincible(cache.ped, true)
    FreezeEntityPosition(cache.ped, false)
    SetPlayerControl(PlayerId(), true, 0)
    DisablePlayerFiring(PlayerId(), true)
end

local weaponVoteOpening = false
local pendingWeaponVoteData = nil

local function waitForArenaPedLanded()
    local timeout = GetGameTimer() + (Config.Match.preVoteLoadMs or 2500)

    while GetGameTimer() < timeout do
        if not IsEntityInAir(cache.ped) and not IsPedFalling(cache.ped) then
            Wait(250)
            return
        end

        Wait(100)
    end
end

local function weaponHashFromItem(itemName)
    return joaat(itemName or Config.Items.pistol)
end

local function equipArenaWeapon(weapon, ammo, slot)
    local itemName = weapon and weapon.item or Config.Items.pistol
    local weaponHash = weaponHashFromItem(itemName)
    local weaponAmmo = ammo or (weapon and weapon.ammo) or Config.Match.startAmmo

    if not HasPedGotWeapon(cache.ped, weaponHash, false) then
        GiveWeaponToPed(cache.ped, weaponHash, weaponAmmo, false, true)
    end

    SetPedAmmo(cache.ped, weaponHash, weaponAmmo)
    SetCurrentPedWeapon(cache.ped, weaponHash, true)
    SetPedCurrentWeaponVisible(cache.ped, true, true, true, true)
    SetPedCanSwitchWeapon(cache.ped, true)
end

local function equipArenaKnife()
    local knife = weaponHashFromItem(Config.Items.knife)
    if not HasPedGotWeapon(cache.ped, knife, false) then
        GiveWeaponToPed(cache.ped, knife, 0, false, false)
    end
end

local function confirmArenaWeaponEquipped(matchId, weapon, ammo, slot, allowIntro)
    CreateThread(function()
        Wait(650)

        local match = CHWClient.activeMatch
        if not match or match.id ~= matchId or not match.alive then
            return
        end

        if match.introActive and not allowIntro then
            return
        end

        local weaponHash = weaponHashFromItem(weapon and weapon.item)
        if not HasPedGotWeapon(cache.ped, weaponHash, false) and slot then
            exports.ox_inventory:useSlot(slot, true)
            Wait(250)
        end

        if not HasPedGotWeapon(cache.ped, weaponHash, false) or GetSelectedPedWeapon(cache.ped) ~= weaponHash then
            equipArenaWeapon(weapon, ammo, slot)
            Wait(60)
        end

        SetCurrentPedWeapon(cache.ped, weaponHash, true)
        SetPedCurrentWeaponVisible(cache.ped, true, true, true, true)
        SetPedCanSwitchWeapon(cache.ped, true)
    end)
end

local headBones = {
    [1356] = true,
    [11174] = true,
    [12844] = true,
    [17719] = true,
    [19336] = true,
    [20279] = true,
    [20623] = true,
    [21550] = true,
    [25260] = true,
    [27474] = true,
    [31086] = true,
    [35731] = true,
    [37119] = true,
    [39317] = true,
    [45750] = true,
    [46240] = true,
    [47419] = true,
    [49979] = true,
    [58331] = true,
    [61839] = true,
    [65068] = true
}

local function wasHeadshot(victimPed)
    local hit, bone = GetPedLastDamageBone(victimPed)
    return hit == true and headBones[bone] == true
end

local function waitForHeadshotBone(victimPed)
    for _ = 1, 8 do
        if wasHeadshot(victimPed) then
            return true
        end

        Wait(25)
    end

    return false
end

local killEffectRunning = false
local deathAnimPlaying = false
local deathImpactCooldownUntil = 0

local function playDeathAnimation()
    if deathAnimPlaying or not Config.DeathAnimation or Config.DeathAnimation.enabled ~= true then
        return
    end

    deathAnimPlaying = true

    CreateThread(function()
        local ped = cache.ped
        local ragdollDuration = Config.DeathAnimation.ragdollDurationMs or 4500

        FreezeEntityPosition(ped, false)
        SetPedCanRagdoll(ped, true)
        ClearPedTasksImmediately(ped)
        ClearPedSecondaryTask(ped)
        SetPedToRagdoll(ped, ragdollDuration, ragdollDuration, 0, true, true, false)

        deathAnimPlaying = false
    end)
end

local function playKillEffect()
    if killEffectRunning or not Config.KillEffect or Config.KillEffect.enabled ~= true then
        return
    end

    killEffectRunning = true

    CreateThread(function()
        playDeathAnimation()
        ShakeGameplayCam(Config.KillEffect.shake or 'SMALL_EXPLOSION_SHAKE', Config.KillEffect.shakeIntensity or 0.28)
        SetTimeScale(Config.KillEffect.timeScale or 0.82)
        Wait(Config.KillEffect.durationMs or 260)
        SetTimeScale(1.0)
        killEffectRunning = false
    end)
end

local function playVictimDeathImpact()
    local now = GetGameTimer()
    if now < deathImpactCooldownUntil then
        return
    end

    deathImpactCooldownUntil = now + 1200
    playKillEffect()
end

local function prepareDeathcamBody()
    local ped = cache.ped
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    if IsEntityDead(ped) or IsPedFatallyInjured(ped) then
        resurrectAt(coords, heading)
        clearDeathState()
    end

    SetEntityInvincible(cache.ped, true)
    SetPlayerControl(PlayerId(), false, 0)
    FreezeEntityPosition(cache.ped, false)
    playVictimDeathImpact()
end

local function removeTestBots()
    local match = CHWClient.activeMatch
    local bots = match and match.testBots
    for _, bot in pairs(bots or {}) do
        if bot.ped and DoesEntityExist(bot.ped) then
            DeleteEntity(bot.ped)
        end
    end
    if match then
        match.testBots = nil
    end
end

local function spawnTestBots()
    local hash = joaat(Config.TestBot.model)
    lib.requestModel(hash, 10000)
    local bots = {}

    for index, coords in ipairs(Config.TestBot.spawns) do
        local ped = CreatePed(4, hash, coords.x, coords.y, coords.z - 1.0, coords.w, false, false)
        SetEntityAsMissionEntity(ped, true, true)
        RemoveAllPedWeapons(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedDropsWeaponsWhenDead(ped, false)
        SetPedCanSwitchWeapon(ped, false)
        SetPedFleeAttributes(ped, 0, false)
        if Config.TestBot.scenario and Config.TestBot.scenario ~= '' then
            TaskStartScenarioInPlace(ped, Config.TestBot.scenario, 0, true)
        end
        bots[index] = { ped = ped, nextReport = 0 }
    end

    SetModelAsNoLongerNeeded(hash)
    return bots
end

RegisterNetEvent('CHW:client:startMatch', function(data)
    weaponVoteOpening = false
    pendingWeaponVoteData = nil
    leaveSpectator()
    resetArenaPed()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideChamberMenu' })
    SendNUIMessage({ action = 'hideLobby' })
    SendNUIMessage({ action = 'hideWeaponVote' })
    SendNUIMessage({ action = 'clearKillfeed' })
    DoScreenFadeOut(300)
    Wait(350)

    RemoveAllPedWeapons(cache.ped, true)
    if IsEntityDead(cache.ped) then
        resurrectAt(data.spawn.xyz, data.spawn.w)
    else
        SetEntityCoords(cache.ped, data.spawn.x, data.spawn.y, data.spawn.z, false, false, false, false)
        SetEntityHeading(cache.ped, data.spawn.w)
        SetEntityHealth(cache.ped, GetEntityMaxHealth(cache.ped))
    end
    clearDeathState()

    CHWClient.activeMatch = {
        id = data.matchId,
        alive = true,
        introActive = data.introActive == true,
        lives = data.lives or Config.Match.startLives,
        maxLives = data.maxLives or Config.Match.startLives,
        weapon = nil,
        primarySlot = nil,
        nextDeathReport = 0,
        nextHitReport = 0,
        restrictedWeaponWarning = false,
        testBots = nil
    }
    setLivesUi(true, CHWClient.activeMatch.lives, CHWClient.activeMatch.maxLives)
    if data.leaderboard then
        SendNUIMessage({
            action = 'leaderboard',
            rows = data.leaderboard.rows or {},
            maxRows = data.leaderboard.maxRows or Config.Leaderboard.maxRows
        })
    end
    prepareArenaPed()

    if data.spawnTestBots then
        CHWClient.activeMatch.testBots = spawnTestBots()
        CHWClient.Notify({
            title = Config.ArenaName,
            description = ('Testmodus: schakel %d ongewapende arena-NPCs uit om te winnen.'):format(#Config.TestBot.spawns),
            type = 'inform'
        })
    end

    DoScreenFadeIn(300)

    CHWClient.Notify({
        title = Config.ArenaName,
        description = 'Ronde geladen. Stem op het primary weapon voor deze ronde.',
        type = 'success'
    })
end)

RegisterNetEvent('CHW:client:weaponVoteUpdate', function(data)
    local match = CHWClient.activeMatch
    if not match then
        return
    end

    pendingWeaponVoteData = data
    if weaponVoteOpening then
        return
    end

    weaponVoteOpening = true
    match.introActive = true
    waitForArenaPedLanded()
    lockArenaPed()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'showWeaponVote',
        data = pendingWeaponVoteData
    })
    pendingWeaponVoteData = nil
    weaponVoteOpening = false
end)

RegisterNetEvent('CHW:client:weaponVoteTiebreak', function(data)
    local match = CHWClient.activeMatch
    if not match then
        return
    end

    match.introActive = true
    lockArenaPed()
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'showWeaponTiebreak',
        data = data
    })
end)

RegisterNetEvent('CHW:client:weaponSelected', function(data)
    local match = CHWClient.activeMatch
    if not match then
        return
    end

    local weapon = data and data.weapon or nil
    match.weapon = weapon
    match.primarySlot = data and data.slot or nil

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideWeaponVote' })
    pendingWeaponVoteData = nil
    weaponVoteOpening = false

    if match.primarySlot then
        exports.ox_inventory:useSlot(match.primarySlot, true)
        Wait(350)
    end

    equipArenaKnife()
    equipArenaWeapon(weapon, weapon and weapon.ammo or Config.Match.startAmmo, match.primarySlot)
    Wait(60)
    SetCurrentPedWeapon(cache.ped, weaponHashFromItem(weapon and weapon.item), true)
    SetPedCurrentWeaponVisible(cache.ped, true, true, true, true)
    confirmArenaWeaponEquipped(match.id, weapon, weapon and weapon.ammo or Config.Match.startAmmo, match.primarySlot, true)
end)

RegisterNetEvent('CHW:client:startIntro', function(data)
    local match = CHWClient.activeMatch
    if not match then
        return
    end

    match.introActive = true
    lockArenaPed()
    SendNUIMessage({
        action = 'showIntro',
        duration = data and data.duration or Config.Match.introDurationMs
    })
end)

RegisterNetEvent('CHW:client:combatStart', function()
    local match = CHWClient.activeMatch
    if not match then
        return
    end

    match.introActive = false
    SendNUIMessage({ action = 'hideIntro' })
    
    equipArenaKnife()
    equipArenaWeapon(match.weapon, match.weapon and match.weapon.ammo or Config.Match.startAmmo, match.primarySlot)
    Wait(50)
    SetCurrentPedWeapon(cache.ped, weaponHashFromItem(match.weapon and match.weapon.item), true)
    SetPedCurrentWeaponVisible(cache.ped, true, true, true, true)
    SetPedCanSwitchWeapon(cache.ped, true)
    confirmArenaWeaponEquipped(match.id, match.weapon, match.weapon and match.weapon.ammo or Config.Match.startAmmo, match.primarySlot, false)
    
    resetArenaPed()
end)

RegisterNetEvent('CHW:client:updateLives', function(data)
    local match = CHWClient.activeMatch
    if not match then
        return
    end

    match.lives = data.lives or match.lives or 0
    match.maxLives = data.maxLives or match.maxLives or Config.Match.startLives
    updateLivesUi(match.lives, match.maxLives, data.gainedLife == true)
end)

RegisterNetEvent('CHW:client:respawn', function(data)
    local match = CHWClient.activeMatch
    if not match then
        return
    end

    match.alive = false
    match.lives = data.lives or match.lives or 0
    match.maxLives = data.maxLives or match.maxLives or Config.Match.startLives
    updateLivesUi(match.lives, match.maxLives)

    SetEntityInvincible(cache.ped, true)
    SetPlayerControl(PlayerId(), false, 0)

    local deathcam = data.deathcam
    if deathcam and deathcam.killer and deathcam.killer.id then
        prepareDeathcamBody()
        Wait(deathcam.bodyViewMs or Config.Deathcam.bodyViewMs or 1400)

        startSpectating(deathcam.killer.id)
        SendNUIMessage({
            action = 'showDeathcam',
            data = deathcam
        })

        Wait(deathcam.spectateMs or Config.Deathcam.spectateMs or 5000)

        SendNUIMessage({ action = 'hideDeathcam' })
        DoScreenFadeOut(deathcam.fadeMs or Config.Deathcam.fadeMs or 350)
        Wait(deathcam.fadeMs or Config.Deathcam.fadeMs or 350)
        leaveSpectator()
    else
        DoScreenFadeOut(250)
        Wait(data.delay or Config.Match.respawnDelayMs or 1000)
    end

    RemoveAllPedWeapons(cache.ped, true)
    resurrectAt(data.spawn.xyz, data.spawn.w)
    clearDeathState()
    match.weapon = data.weapon or match.weapon
    match.primarySlot = data.primarySlot or match.primarySlot
    if match.primarySlot then
        exports.ox_inventory:useSlot(match.primarySlot, true)
        Wait(350)
    end
    equipArenaKnife()
    equipArenaWeapon(match.weapon, data.startAmmo or (match.weapon and match.weapon.ammo) or Config.Match.startAmmo, match.primarySlot)
    Wait(60)
    SetCurrentPedWeapon(cache.ped, weaponHashFromItem(match.weapon and match.weapon.item), true)
    SetPedCurrentWeaponVisible(cache.ped, true, true, true, true)
    resetArenaPed()
    match.alive = true
    confirmArenaWeaponEquipped(match.id, match.weapon, data.startAmmo or (match.weapon and match.weapon.ammo) or Config.Match.startAmmo, match.primarySlot, false)
    DoScreenFadeIn(250)
end)

RegisterNetEvent('CHW:client:removeTestBot', function(botIndex)
    local match = CHWClient.activeMatch
    local bot = match and match.testBots and match.testBots[botIndex]
    if bot and bot.ped and DoesEntityExist(bot.ped) then
        DeleteEntity(bot.ped)
    end
    if match and match.testBots then
        match.testBots[botIndex] = nil
    end
end)

RegisterNetEvent('CHW:client:unlockInvalidDamage', function()
    local match = CHWClient.activeMatch
    if not match or match.introActive then
        return
    end

    match.alive = true
    clearDeathState()
    resetArenaPed()
    SetPlayerControl(PlayerId(), true, 0)
end)

RegisterNetEvent('CHW:client:restoreFromInvalidDamage', function()
    local match = CHWClient.activeMatch
    if not match or match.introActive then
        return
    end

    match.alive = true

    local coords = GetEntityCoords(cache.ped)
    local heading = GetEntityHeading(cache.ped)

    if IsEntityDead(cache.ped) or IsPedFatallyInjured(cache.ped) then
        resurrectAt(coords, heading)
    else
        SetEntityHealth(cache.ped, GetEntityMaxHealth(cache.ped))
    end

    clearDeathState()
    resetArenaPed()
    SetPlayerControl(PlayerId(), true, 0)

    CHWClient.Notify({
        title = Config.ArenaName,
        description = 'Ongeldige arena-schade genegeerd.',
        type = 'inform'
    })
end)

RegisterNetEvent('CHW:client:ammoAwarded', function(amount, reason, itemName)
    local match = CHWClient.activeMatch
    if not match or not match.alive or match.introActive then
        return
    end

    local weaponHash = weaponHashFromItem(itemName or (match.weapon and match.weapon.item))
    AddAmmoToPed(cache.ped, weaponHash, amount)
    SetCurrentPedWeapon(cache.ped, weaponHash, true)
    local rewardText = reason == 'knife'
        and ('Knife reward: +%d primary ammo.'):format(amount)
        or ('Kill reward: +%d primary ammo.'):format(amount)

    CHWClient.Notify({
        id = 'chw_ammo_reward',
        title = Config.ArenaName,
        description = rewardText,
        type = 'success',
        icon = 'gun',
        duration = 3500
    })
end)

RegisterNetEvent('CHW:client:setPistolAmmo', function(amount, slot)
    TriggerEvent('CHW:client:setPrimaryAmmo', Config.Items.pistol, amount, slot)
end)

RegisterNetEvent('CHW:client:setPrimaryAmmo', function(itemName, amount, slot)
    local match = CHWClient.activeMatch
    if not match then
        return
    end

    match.primarySlot = slot or match.primarySlot
    if match.weapon then
        match.weapon.item = itemName or match.weapon.item
    end
    equipArenaWeapon(match.weapon, amount or (match.weapon and match.weapon.ammo) or Config.Match.startAmmo, match.primarySlot)
end)

RegisterNetEvent('CHW:client:killfeed', function(data)
    if not CHWClient.activeMatch then
        return
    end

    SendNUIMessage({
        action = 'killfeed',
        data = data
    })
end)

RegisterNetEvent('CHW:client:deathImpact', function()
    local match = CHWClient.activeMatch
    if not match then
        return
    end

    match.alive = false
    SetEntityInvincible(cache.ped, true)
    SetPlayerControl(PlayerId(), false, 0)
    playVictimDeathImpact()
end)

RegisterNetEvent('CHW:client:leaderboard', function(data)
    if not CHWClient.activeMatch then
        return
    end

    SendNUIMessage({
        action = 'leaderboard',
        rows = data and data.rows or {},
        maxRows = data and data.maxRows or Config.Leaderboard.maxRows
    })
end)

RegisterNetEvent('CHW:client:bonusLifeNotify', function(data)
    CHWClient.Notify({
        id = 'chw_bonus_life',
        title = Config.ArenaName,
        description = ('%d killstreak: +1 extra leven gekregen.'):format(data and data.kills or Config.Match.bonusLifeKillStreak or 5),
        type = 'success',
        icon = 'heart-pulse',
        duration = 4500
    })
end)

RegisterNetEvent('CHW:client:eliminated', function(spectateTarget)
    local match = CHWClient.activeMatch
    if not match then
        return
    end

    match.alive = false
    match.lives = 0
    updateLivesUi(0, match.maxLives or Config.Match.startLives)
    if IsEntityDead(cache.ped) or IsPedFatallyInjured(cache.ped) then
        local coords = GetEntityCoords(cache.ped)
        resurrectAt(coords, GetEntityHeading(cache.ped))
    else
        SetEntityHealth(cache.ped, GetEntityMaxHealth(cache.ped))
        ClearPedTasksImmediately(cache.ped)
        ClearPedSecondaryTask(cache.ped)
        ClearPedBloodDamage(cache.ped)
        ResetPedVisibleDamage(cache.ped)
        ClearEntityLastDamageEntity(cache.ped)
    end
    clearDeathState()
    RemoveAllPedWeapons(cache.ped, true)
    SetEntityInvincible(cache.ped, true)
    CHWClient.Notify({
        title = Config.ArenaName,
        description = 'Je bent geëlimineerd. Wacht tot de ronde eindigt.',
        type = 'error'
    })

    if spectateTarget then
        startSpectating(spectateTarget)
    end
end)

RegisterNetEvent('CHW:client:refreshSpectateTarget', function(targetServerId)
    local match = CHWClient.activeMatch
    if not match or match.alive or not spectator.active or spectator.targetServerId ~= targetServerId then
        return
    end

    Wait(250)
    startSpectating(targetServerId)
end)

RegisterNetEvent('CHW:client:endMatch', function(data)
    removeTestBots()
    CHWClient.activeMatch = nil
    SetNuiFocus(false, false)
    setLivesUi(false)
    SendNUIMessage({ action = 'clearKillfeed' })
    SendNUIMessage({ action = 'hideLeaderboard' })
    SendNUIMessage({ action = 'hideLobby' })
    SendNUIMessage({ action = 'hideWeaponVote' })
    SendNUIMessage({ action = 'hideDeathcam' })
    SendNUIMessage({ action = 'hideIntro' })
    SetEntityInvincible(cache.ped, false)
    leaveSpectator()
    DoScreenFadeOut(300)
    Wait(350)

    RemoveAllPedWeapons(cache.ped, true)
    resurrectAt(data.coords, data.heading)
    clearDeathState()

    DoScreenFadeIn(300)
    if data.cleanupFailed then
        CHWClient.Notify({
            title = Config.ArenaName,
            description = 'Inventory cleanup faalde; opnieuw joinen is geblokkeerd tot cleanup lukt.',
            type = 'error'
        })
    end
end)

AddEventHandler('gameEventTriggered', function(eventName, args)
    if eventName ~= 'CEventNetworkEntityDamage' then
        return
    end

    local match = CHWClient.activeMatch
    if not match or not match.alive then
        return
    end

    local victim = args[1]
    local attacker = args[2]
    if not victim or not attacker or victim == attacker then
        return
    end

    local myPed = cache.ped
    if victim == myPed and IsEntityAPed(attacker) and IsPedAPlayer(attacker) then
        local shooterPlayer = NetworkGetPlayerIndexFromPed(attacker)
        if shooterPlayer == -1 then
            return
        end

        local shooterServerId = GetPlayerServerId(shooterPlayer)
        local targetServerId = GetPlayerServerId(PlayerId())
        local weaponHash = GetSelectedPedWeapon(attacker)
        if not shooterServerId or not targetServerId or shooterServerId == targetServerId then
            return
        end

        local now = GetGameTimer()
        if now < (match.nextHitReport or 0) then
            return
        end

        match.nextHitReport = now + Config.Security.hitReportCooldownMs
        local weaponType = Config.AllowedWeapons.pistol[weaponHash] and 'pistol'
            or Config.AllowedWeapons.sniper[weaponHash] and 'sniper'
            or Config.AllowedWeapons.shotgun[weaponHash] and 'shotgun'
            or Config.AllowedWeapons.knife[weaponHash] and 'knife'
            or nil
        local primaryAllowed = match.weapon and weaponType == match.weapon.type
        if weaponType == 'knife' or primaryAllowed then
            match.alive = false
            SetEntityInvincible(cache.ped, true)
            SetPlayerControl(PlayerId(), false, 0)
            playVictimDeathImpact()
        end

        CreateThread(function()
            TriggerServerEvent('CHW:server:reportHit', shooterServerId, targetServerId, weaponHash, waitForHeadshotBone(myPed))
        end)
    else
        return
    end
end)

CreateThread(function()
    while true do
        local match = CHWClient.activeMatch
        if not match or not match.alive or match.introActive then
            Wait(1000)
        elseif IsEntityDead(cache.ped) then
            local now = GetGameTimer()
            if now >= match.nextDeathReport then
                match.nextDeathReport = now + Config.Security.deathReportCooldownMs + 100
                local killerPed = GetPedSourceOfDeath(cache.ped)
                local weaponHash = GetPedCauseOfDeath(cache.ped)
                local killerPlayer = killerPed ~= 0 and NetworkGetPlayerIndexFromPed(killerPed) or -1
                local killerServerId = killerPlayer ~= -1 and GetPlayerServerId(killerPlayer) or nil

                if killerServerId and killerServerId ~= GetPlayerServerId(PlayerId()) then
                    TriggerServerEvent('CHW:server:reportKill', killerServerId, weaponHash)
                else
                    TriggerServerEvent('CHW:server:reportDeath')
                end
            end
            Wait(250)
        else
            Wait(250)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        removeTestBots()
        SetNuiFocus(false, false)
        setLivesUi(false)
        SendNUIMessage({ action = 'clearKillfeed' })
        SendNUIMessage({ action = 'hideLeaderboard' })
        SendNUIMessage({ action = 'hideLobby' })
        SendNUIMessage({ action = 'hideWeaponVote' })
        SendNUIMessage({ action = 'hideDeathcam' })
        SendNUIMessage({ action = 'hideIntro' })
        leaveSpectator()
        SetTimeScale(1.0)
        FreezeEntityPosition(cache.ped, false)
        SetEntityInvincible(cache.ped, false)
        SetPlayerControl(PlayerId(), true, 0)
    end
end)

CreateThread(function()
    while true do
        local match = CHWClient.activeMatch
        local bots = match and match.testBots
    if match and match.alive and not match.introActive and bots then
            local now = GetGameTimer()
            for index, bot in pairs(bots) do
                if DoesEntityExist(bot.ped) and IsEntityDead(bot.ped) and now >= bot.nextReport then
                    bot.nextReport = now + 500
                    TriggerServerEvent('CHW:server:reportTestBotKill', index, GetPedCauseOfDeath(bot.ped))
                end
            end
            Wait(250)
        else
            Wait(1000)
        end
    end
end)

CreateThread(function()
    while true do
        local match = CHWClient.activeMatch
        if match and match.alive and not match.introActive and match.weapon then
            local primaryWeapon = weaponHashFromItem(match.weapon.item)
            if HasPedGotWeapon(cache.ped, primaryWeapon, false) then
                local selected = GetSelectedPedWeapon(cache.ped)
                if selected ~= primaryWeapon and not Config.AllowedWeapons.knife[selected] then
                    SetCurrentPedWeapon(cache.ped, primaryWeapon, true)
                    SetPedCurrentWeaponVisible(cache.ped, true, true, true, true)
                end
            end
            Wait(500)
        else
            Wait(1000)
        end
    end
end)

CreateThread(function()
    while true do
        local match = CHWClient.activeMatch
        if match and match.introActive then
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 32, true)
            DisableControlAction(0, 33, true)
            DisableControlAction(0, 34, true)
            DisableControlAction(0, 35, true)
            DisableControlAction(0, 257, true)
            Wait(0)
        elseif match and not match.alive then
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 257, true)
            Wait(0)
        elseif match and match.alive then
            local weapon = GetSelectedPedWeapon(cache.ped)
            local selectedPrimary = match.weapon and weapon == weaponHashFromItem(match.weapon.item)
            local allowed = weapon == joaat('WEAPON_UNARMED')
                or selectedPrimary
                or Config.AllowedWeapons.knife[weapon]

            if not allowed then
                DisablePlayerFiring(PlayerId(), true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 257, true)
                if not match.restrictedWeaponWarning then
                    match.restrictedWeaponWarning = true
                    CHWClient.Notify({
                        title = Config.ArenaName,
                        description = 'Dit wapen is niet toegestaan in de arena.',
                        type = 'error'
                    })
                end
            else
                match.restrictedWeaponWarning = false
            end
            Wait(0)
        else
            Wait(1000)
        end
    end
end)
