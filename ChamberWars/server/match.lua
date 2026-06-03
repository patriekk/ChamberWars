CHW.Match = {}
CHW.State = {
    queue = {},
    queued = {},
    openLobby = nil,
    lobbies = {},
    playerLobby = {},
    nextLobbyId = 0,
    players = {},
    current = nil,
    matches = {},
    nextMatchId = 0,
    countdownToken = 0,
    countdownSeconds = nil,
    countdownLobbyId = nil,
    countdownPending = false,
    pendingRestores = {}
}

local function notify(source, description, kind)
    TriggerClientEvent('CHW:client:notify', source, description, kind or 'inform')
end

local function isOutsideArena(coords)
    if coords == nil then
        return true
    end

    if not Config.Arena.center or not Config.Arena.radius or Config.Arena.radius <= 0.0 then
        return true
    end

    if coords.z < Config.Arena.minZ or coords.z > Config.Arena.maxZ then
        return true
    end

    local playerPosition = vec2(coords.x, coords.y)
    local arenaPosition = vec2(Config.Arena.center.x, Config.Arena.center.y)
    return #(playerPosition - arenaPosition) > Config.Arena.radius
end

local function lobbyById(lobbyId)
    return CHW.State.lobbies[tonumber(lobbyId)]
end

local function matchById(matchId)
    return CHW.State.matches[tonumber(matchId)]
end

local function matchForPlayer(source)
    local player = CHW.State.players[source]
    return player and player.matchId and matchById(player.matchId) or nil
end

local function isMatchActive(match)
    return match and CHW.State.matches[match.id] == match
end

local function activeMatchCount()
    local count = 0
    for _ in pairs(CHW.State.matches) do
        count = count + 1
    end
    return count
end

local function matchBucket(matchId)
    return (Config.Arena.routingBucket or 7100) + tonumber(matchId or 0)
end

local function lobbyCount(lobby)
    return lobby and #lobby.players or 0
end

local function queueCount()
    local lobby = lobbyById(CHW.State.countdownLobbyId)
    return lobbyCount(lobby)
end

local function lobbyPlayers(lobby)
    local players = {}

    if not lobby then
        return players
    end

    for index, source in ipairs(lobby.players) do
        local name = GetPlayerName(source)
        if name then
            players[#players + 1] = {
                id = source,
                name = name,
                host = source == lobby.host or index == 1
            }
        end
    end

    return players
end

local function queuePlayers()
    return lobbyPlayers(lobbyById(CHW.State.countdownLobbyId))
end

local function activeLobbies()
    local lobbies = {}

    for _, lobby in pairs(CHW.State.lobbies) do
        if lobbyCount(lobby) > 0 then
            local hostName = GetPlayerName(lobby.host) or lobby.hostName or 'Unknown'
            lobbies[#lobbies + 1] = {
                id = lobby.id,
                name = ("%s's Lobby"):format(hostName),
                host = lobby.host,
                hostName = hostName,
                players = lobbyCount(lobby),
                maximumPlayers = Config.Match.maximumPlayers,
                countdown = CHW.State.countdownActive == true and CHW.State.countdownLobbyId == lobby.id,
                countdownPending = CHW.State.countdownPending == true and CHW.State.countdownLobbyId == lobby.id,
                countdownSeconds = CHW.State.countdownLobbyId == lobby.id and CHW.State.countdownSeconds or nil
            }
        end
    end

    table.sort(lobbies, function(a, b)
        return a.id < b.id
    end)

    return lobbies
end

local function broadcastLobbyList()
    TriggerClientEvent('CHW:client:lobbyListUpdate', -1, activeLobbies())
end

local function lobbySnapshot(lobby)
    return {
        title = 'Chamber Wars',
        queued = lobbyCount(lobby),
        minimumPlayers = Config.Match.minimumPlayers,
        maximumPlayers = Config.Match.maximumPlayers,
        countdown = CHW.State.countdownActive == true and lobby and CHW.State.countdownLobbyId == lobby.id,
        countdownPending = CHW.State.countdownPending == true and lobby and CHW.State.countdownLobbyId == lobby.id,
        countdownSeconds = lobby and CHW.State.countdownLobbyId == lobby.id and CHW.State.countdownSeconds or nil,
        active = activeMatchCount() > 0,
        lobby = lobby,
        lobbies = activeLobbies(),
        players = lobbyPlayers(lobby)
    }
end

local function broadcastLobby(lobby)
    if not lobby then
        return
    end

    local snapshot = lobbySnapshot(lobby)

    for _, source in ipairs(lobby.players) do
        if GetPlayerName(source) then
            TriggerClientEvent('CHW:client:lobbyUpdate', source, snapshot)
        end
    end
end

local function removeFromQueue(source)
    if not CHW.State.queued[source] then
        return false
    end

    local lobbyId = CHW.State.playerLobby[source]
    local lobby = lobbyById(lobbyId)
    CHW.State.queued[source] = nil
    CHW.State.playerLobby[source] = nil

    if lobby then
        for i = #lobby.players, 1, -1 do
            if lobby.players[i] == source then
                table.remove(lobby.players, i)
                break
            end
        end
    end

    return true, lobby
end

local function refreshOpenLobby(lobby)
    if not lobby then
        return
    end

    if lobbyCount(lobby) <= 0 then
        CHW.State.lobbies[lobby.id] = nil
        if CHW.State.openLobby == lobby then
            CHW.State.openLobby = nil
        end
        if CHW.State.countdownLobbyId == lobby.id then
            CHW.State.countdownLobbyId = nil
            CHW.State.countdownActive = false
            CHW.State.countdownPending = false
            CHW.State.countdownSeconds = nil
            CHW.State.countdownToken = CHW.State.countdownToken + 1
        end
        return
    end

    local host = lobby.players[1]
    lobby.host = host
    lobby.hostName = GetPlayerName(host) or lobby.hostName
end

local function refreshAllLobbies()
    for _, lobby in pairs(CHW.State.lobbies) do
        refreshOpenLobby(lobby)
    end
end

local function firstReadyLobby()
    local ready = {}

    for _, lobby in pairs(CHW.State.lobbies) do
        if lobbyCount(lobby) >= Config.Match.minimumPlayers then
            ready[#ready + 1] = lobby
        end
    end

    table.sort(ready, function(a, b)
        return a.id < b.id
    end)

    return ready[1]
end

local function clearCountdown()
    CHW.State.countdownLobbyId = nil
    CHW.State.countdownActive = false
    CHW.State.countdownPending = false
    CHW.State.countdownSeconds = nil
end

local function cancelCountdownForLobby(lobby)
    if lobby and CHW.State.countdownLobbyId == lobby.id then
        clearCountdown()
        CHW.State.countdownToken = CHW.State.countdownToken + 1
    end
end

local function addToOpenLobby(source, lobby)
    if not lobby then
        return false, 'Deze lobby bestaat niet meer.'
    end

    if CHW.State.queued[source] or (CHW.State.players[source] and CHW.State.players[source].matchId) then
        return false, 'Je zit al in een lobby of in een match.'
    end

    if lobbyCount(lobby) >= Config.Match.maximumPlayers then
        return false, 'Deze lobby zit vol.'
    end

    if CHW.State.players[source] and CHW.State.players[source].cleanupFailed then
        if not CHW.Match.RecoverPlayer(source) then
            return false, 'Cleanup is nog niet gelukt; joinen is geblokkeerd.'
        end
    end

    if not CHW.Match.RecoverPlayer(source) then
        CHW.State.players[source] = { cleanupFailed = true }
        return false, 'Arena-items van een vorige ronde konden niet worden opgeschoond.'
    end

    lobby.players[#lobby.players + 1] = source
    CHW.State.queued[source] = true
    CHW.State.playerLobby[source] = lobby.id
    refreshOpenLobby(lobby)
    return true
end

local function setLegacyQueueForLobby(lobby)
    CHW.State.queue = {}
    if not lobby then
        return
    end

    for i = 1, #lobby.players do
        CHW.State.queue[i] = lobby.players[i]
    end
end

local function removeLobby(lobby)
    if not lobby then
        return
    end

    for _, source in ipairs(lobby.players) do
        CHW.State.queued[source] = nil
        CHW.State.playerLobby[source] = nil
    end

    if CHW.State.openLobby == lobby then
        CHW.State.openLobby = nil
    end

    CHW.State.lobbies[lobby.id] = nil
    if CHW.State.countdownLobbyId == lobby.id then
        clearCountdown()
        CHW.State.countdownToken = CHW.State.countdownToken + 1
    end

    broadcastLobbyList()
end

local function resetLegacyQueue()
    CHW.State.queue = {}
end

local function ensureCountdownLobby()
    if CHW.State.countdownLobbyId then
        return lobbyById(CHW.State.countdownLobbyId)
    end

    return firstReadyLobby()
end

local function queueLobby()
    return ensureCountdownLobby()
end

local function legacyQueueCount()
    local lobby = queueLobby()
    return lobbyCount(lobby)
end

local function resetCountdownIfEmpty()
    local lobby = lobbyById(CHW.State.countdownLobbyId)
    if not lobby or lobbyCount(lobby) <= 0 then
        clearCountdown()
        CHW.State.countdownToken = CHW.State.countdownToken + 1
    end
end

local function refreshOpenLobbyLegacy()
    refreshAllLobbies()
    resetCountdownIfEmpty()
end

local function addToLegacyLobby(source)
    local lobby = queueLobby()
    return addToOpenLobby(source, lobby)
end

local function queuePlayerList()
    local lobby = queueLobby()
    return lobbyPlayers(lobby)
end

local function queueSnapshot()
    return lobbySnapshot(queueLobby())
end

local function broadcastQueuedLobby()
    broadcastLobby(queueLobby())
end

local function cancelCountdownIfNotEnough(lobby)
    if lobby and CHW.State.countdownLobbyId == lobby.id and lobbyCount(lobby) < Config.Match.minimumPlayers then
        CHW.State.countdownActive = false
        CHW.State.countdownPending = false
        CHW.State.countdownSeconds = nil
        CHW.State.countdownLobbyId = nil
        CHW.State.countdownToken = CHW.State.countdownToken + 1
    end
end

local function livingPlayers(match)
    local alive = {}
    for source, player in pairs(match.players) do
        if not player.eliminated and GetPlayerName(source) then
            alive[#alive + 1] = source
        end
    end
    return alive
end

local function randomSpawn()
    return Config.Arena.spawnpoints[math.random(#Config.Arena.spawnpoints)]
end

local function updateLives(source, player)
    TriggerClientEvent('CHW:client:updateLives', source, {
        lives = player.lives or 0,
        maxLives = player.maxLives or Config.Match.startLives
    })
end

local function addBonusLife(match, source, player)
    local streakTarget = Config.Match.bonusLifeKillStreak or 0
    if streakTarget <= 0 then
        return
    end

    player.killStreak = (player.killStreak or 0) + 1
    if player.killStreak < streakTarget then
        return
    end

    player.killStreak = 0
    player.lives = (player.lives or Config.Match.startLives) + 1
    player.maxLives = math.max(player.maxLives or Config.Match.startLives, player.lives)
    TriggerClientEvent('CHW:client:updateLives', source, {
        lives = player.lives,
        maxLives = player.maxLives,
        gainedLife = true
    })
    TriggerClientEvent('CHW:client:bonusLifeNotify', source, {
        kills = streakTarget,
        lives = player.lives
    })
end

local function leaderboardRows(match)
    local rows = {}

    for source, player in pairs(match.players) do
        local name = GetPlayerName(source)
        if name then
            rows[#rows + 1] = {
                id = source,
                name = name,
                kills = player.kills or 0,
                lives = player.lives or 0,
                eliminated = player.eliminated == true
            }
        end
    end

    table.sort(rows, function(a, b)
        if a.kills ~= b.kills then
            return a.kills > b.kills
        end

        if a.lives ~= b.lives then
            return a.lives > b.lives
        end

        return a.name:lower() < b.name:lower()
    end)

    return rows
end

local function broadcastLeaderboard(match)
    if not match then
        return
    end

    local payload = {
        rows = leaderboardRows(match),
        maxRows = Config.Leaderboard and Config.Leaderboard.maxRows or 5
    }

    for source in pairs(match.players) do
        if GetPlayerName(source) then
            TriggerClientEvent('CHW:client:leaderboard', source, payload)
        end
    end
end

local function giveStartAmmo(source, matchId)
    local match = matchById(matchId)
    local player = match and match.players[source]
    local weapon = match and match.weapon
    local itemName = weapon and weapon.item or Config.Items.pistol
    local ammo = weapon and weapon.ammo or Config.Match.startAmmo

    if player and player.primarySlot then
        player.primaryAmmo = ammo
    end

    if not CHW.Inventory.SetPrimaryAmmo(source, matchId, itemName, ammo) then
        notify(source, 'Startmunitie kon niet worden toegepast.', 'error')
    end
end

local function weaponOptions()
    return Config.WeaponVote and Config.WeaponVote.options or {}
end

local function weaponOption(weaponType)
    local options = weaponOptions()
    for i = 1, #options do
        if options[i].type == weaponType then
            return options[i]
        end
    end

    return nil
end

local function defaultWeaponOption()
    return weaponOption(Config.WeaponVote and Config.WeaponVote.defaultWeapon) or weaponOptions()[1]
end

local function weaponVoteSnapshot(match, seconds, viewer)
    local counts = {}
    local players = {}

    for source, player in pairs(match.players) do
        local name = GetPlayerName(source)
        if name then
            local vote = match.weaponVotes and match.weaponVotes[source] or nil
            players[#players + 1] = {
                id = source,
                name = name,
                voted = vote ~= nil,
                vote = vote
            }

            if vote then
                counts[vote] = (counts[vote] or 0) + 1
            end
        end
    end

    return {
        seconds = seconds,
        options = weaponOptions(),
        counts = counts,
        players = players,
        ownVote = viewer and match.weaponVotes and match.weaponVotes[viewer] or nil
    }
end

local function broadcastWeaponVote(match, seconds)
    for source in pairs(match.players) do
        if GetPlayerName(source) then
            local snapshot = weaponVoteSnapshot(match, seconds, source)
            TriggerClientEvent('CHW:client:weaponVoteUpdate', source, snapshot)
        end
    end
end

local function allPlayersVoted(match)
    for source in pairs(match.players) do
        if GetPlayerName(source) and not (match.weaponVotes and match.weaponVotes[source]) then
            return false
        end
    end

    return true
end

local function weaponVoteResult(match)
    local options = weaponOptions()
    local counts = {}
    local bestCount = -1
    local finalists = {}
    local eliminated = {}

    for _, weaponType in pairs(match.weaponVotes or {}) do
        counts[weaponType] = (counts[weaponType] or 0) + 1
    end

    for i = 1, #options do
        local option = options[i]
        local count = counts[option.type] or 0
        if count > bestCount then
            bestCount = count
            finalists = { option }
        elseif count == bestCount then
            finalists[#finalists + 1] = option
        end
    end

    if #finalists == 0 then
        finalists = { defaultWeaponOption() }
    end

    local finalistLookup = {}
    for i = 1, #finalists do
        finalistLookup[finalists[i].type] = true
    end

    for i = 1, #options do
        if not finalistLookup[options[i].type] then
            eliminated[#eliminated + 1] = options[i]
        end
    end

    return {
        winner = finalists[math.random(#finalists)],
        finalists = finalists,
        eliminated = eliminated,
        tied = #finalists > 1,
        counts = counts
    }
end

local function startCombatSequence(match)
    if not isMatchActive(match) then
        return
    end

    if Config.Match.introEnabled then
        for source in pairs(match.players) do
            if GetPlayerName(source) then
                TriggerClientEvent('CHW:client:startIntro', source, {
                    duration = Config.Match.introDurationMs
                })
            end
        end

        CreateThread(function()
            Wait((Config.Match.introDurationMs or 0) + (Config.Match.postIntroFreezeMs or 0))
            if not isMatchActive(match) then
                return
            end

            match.combatActive = true
            match.startedAt = os.time()
            for source in pairs(match.players) do
                if GetPlayerName(source) then
                    TriggerClientEvent('CHW:client:combatStart', source)
                end
            end
        end)
        return
    end

    match.combatActive = true
    match.startedAt = os.time()
    for source in pairs(match.players) do
        if GetPlayerName(source) then
            TriggerClientEvent('CHW:client:combatStart', source)
        end
    end
end

local function applyWeaponVoteResult(match, forcedWeapon)
    if match.weaponResolved then
        return
    end

    if not forcedWeapon and not match.weaponResolving then
        local result = weaponVoteResult(match)
        local revealDuration = result.tied and 7000 or 5000
        match.weaponResolving = true
        match.weaponVoteActive = false

        for source in pairs(match.players) do
            if GetPlayerName(source) then
                TriggerClientEvent('CHW:client:weaponVoteTiebreak', source, {
                    options = weaponOptions(),
                    finalists = result.tied and result.finalists or { result.winner },
                    eliminated = result.eliminated,
                    winner = result.winner,
                    counts = result.counts,
                    tied = result.tied,
                    duration = revealDuration
                })
            end
        end

        CreateThread(function()
            Wait(revealDuration)
            if isMatchActive(match) then
                applyWeaponVoteResult(match, result.winner)
            end
        end)
        return
    end

    match.weaponResolved = true
    match.weaponResolving = false
    match.weaponVoteActive = false
    local weapon = forcedWeapon or defaultWeaponOption()
    match.weapon = weapon
    match.weaponType = weapon and weapon.type or 'pistol'

    for source, player in pairs(match.players) do
        if GetPlayerName(source) then
            local slot = CHW.Inventory.GiveArenaPrimaryWeapon(source, match.id, weapon)
            player.primarySlot = slot
            player.primaryItem = weapon.item
            player.primaryWeaponType = weapon.type
            player.primaryAmmo = weapon.ammo or Config.Match.startAmmo

            if not slot then
                notify(source, 'Je gekozen arena-wapen kon niet worden gegeven.', 'error')
            end

            TriggerClientEvent('CHW:client:weaponSelected', source, {
                weapon = weapon,
                slot = slot
            })
        end
    end

    startCombatSequence(match)
end

local pendingHeadshots = {}
local headComponents = {
    [20] = true,
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

local function hitKey(shooter, target)
    return ('%s:%s'):format(shooter, target)
end

local isMatchPrimaryWeapon

local function playerFromEntity(match, entity)
    if not match or not entity or entity <= 0 then
        return nil
    end

    for source in pairs(match.players) do
        if GetPlayerPed(source) == entity then
            return source
        end
    end

    return nil
end

function CHW.Match.MarkWeaponDamage(shooter, data)
    local match = matchForPlayer(shooter)
    shooter = tonumber(shooter)
    if not match or not shooter or not data then
        return
    end

    local weaponType = CHW.Security.WeaponType(data.weaponType)
    if not isMatchPrimaryWeapon(match, weaponType) then
        return
    end

    local networkIds = data.hitGlobalIds
    if type(networkIds) ~= 'table' or #networkIds == 0 then
        networkIds = { data.hitGlobalId }
    end

    for i = 1, #networkIds do
        local entity = NetworkGetEntityFromNetworkId(tonumber(networkIds[i]) or 0)
        local target = playerFromEntity(match, entity)
        if target and target ~= shooter and match.players[shooter] and match.players[target] then
            local component = tonumber(data.hitComponent)
            local isHeadshot = data.willKill == true or headComponents[component] == true
            if isHeadshot then
                pendingHeadshots[hitKey(shooter, target)] = GetGameTimer() + 2000
                CHW.Security.Debug(('Headshot marked by weaponDamageEvent %s -> %s component=%s willKill=%s'):format(
                    shooter, target, tostring(component), tostring(data.willKill)))
            end
            return
        end
    end
end

local function consumeHeadshot(shooter, target)
    local key = hitKey(shooter, target)
    local expires = pendingHeadshots[key]
    pendingHeadshots[key] = nil
    return expires ~= nil and expires >= GetGameTimer()
end

local function unlockInvalidDamage(target)
    TriggerClientEvent('CHW:client:unlockInvalidDamage', target)

    if CHW.Security.IsDead(target) then
        TriggerClientEvent('CHW:client:restoreFromInvalidDamage', target)
    end
end

local avatarCache = {}

local function hexToDecimalString(hex)
    local digits = { 0 }

    for i = 1, #hex do
        local value = tonumber(hex:sub(i, i), 16)
        if not value then
            return nil
        end

        local carry = value
        for j = #digits, 1, -1 do
            local result = digits[j] * 16 + carry
            digits[j] = result % 10
            carry = math.floor(result / 10)
        end

        while carry > 0 do
            table.insert(digits, 1, carry % 10)
            carry = math.floor(carry / 10)
        end
    end

    return table.concat(digits)
end

local function steamIdentifier(source)
    return GetPlayerIdentifierByType(source, 'steam')
end

local function fetchSteamAvatar(source, cb)
    if not Config.Killfeed.useSteamAvatars then
        cb(nil)
        return
    end

    local identifier = steamIdentifier(source)
    if not identifier then
        cb(nil)
        return
    end

    if avatarCache[identifier] ~= nil then
        cb(avatarCache[identifier] or nil)
        return
    end

    local steamId = hexToDecimalString(identifier:gsub('steam:', ''))
    if not steamId then
        avatarCache[identifier] = false
        cb(nil)
        return
    end

    PerformHttpRequest(('https://steamcommunity.com/profiles/%s/?xml=1'):format(steamId), function(status, body)
        local avatar
        if status == 200 and body then
            avatar = body:match('<avatarMedium><!%[CDATA%[(.-)%]%]></avatarMedium>')
                or body:match('<avatarMedium>(.-)</avatarMedium>')
        end

        avatarCache[identifier] = avatar or false
        cb(avatar)
    end, 'GET')
end

local function broadcastKillfeed(match, victim, killer, weaponType, distance, headshot)
    if not Config.Killfeed.enabled or not killer or killer == victim then
        return
    end

    local killerName = GetPlayerName(killer)
    local victimName = GetPlayerName(victim)
    if not killerName or not victimName then
        return
    end

    local payload = {
        killer = {
            id = killer,
            name = killerName
        },
        victim = {
            id = victim,
            name = victimName
        },
        weapon = headshot and 'headshot' or weaponType,
        distance = distance and math.floor(distance + 0.5) or nil,
        duration = Config.Killfeed.durationMs,
        maxItems = Config.Killfeed.maxItems
    }

    for source in pairs(match.players) do
        if GetPlayerName(source) then
            TriggerClientEvent('CHW:client:killfeed', source, payload)
        end
    end
end

isMatchPrimaryWeapon = function(match, weaponType)
    return weaponType and weaponType ~= 'knife' and match and match.weaponType == weaponType
end

local function addPrimaryAmmoReward(match, source, weaponType)
    local weapon = match and match.weapon
    if not weapon or not weapon.item then
        return true
    end

    local amount = weaponType == 'knife'
        and (Config.Match.knifeKillAmmoReward or 0)
        or (weapon.killAmmoReward or Config.Match.pistolKillAmmoReward or 0)

    if amount <= 0 then
        return true
    end

    return CHW.Inventory.AddPrimaryAmmo(source, match.id, weapon.item, amount, weaponType)
end

local function shouldUseTestBot(playerCount)
    return Config.TestBot.enabled
        and (not Config.TestBot.soloOnly or playerCount == 1)
        and playerCount == 1
end

local function restoreHeldWeapons(source, player)
    local restored, remaining = CHW.Inventory.RestorePersonalWeapons(source, player.storedItems)
    local identifier = player.identifier or CHW.Security.Identifier(source)

    if restored then
        CHW.State.pendingRestores[identifier] = nil
    else
        CHW.State.pendingRestores[identifier] = remaining
    end

    player.storedItems = remaining
    return restored
end

local function restorePlayer(source, player, matchId)
    local cleaned = CHW.Inventory.CleanupPlayer(source, matchId)
    local restored = restoreHeldWeapons(source, player)
    if (not cleaned or not restored) and Config.Cleanup.blockOnFailure then
        player.cleanupFailed = true
    end

    if GetPlayerName(source) then
        SetPlayerRoutingBucket(source, player.previousBucket or 0)
        local ped = GetPlayerPed(source)
        if ped > 0 then
            SetEntityCoords(ped, player.returnCoords.x, player.returnCoords.y, player.returnCoords.z, false, false, false, false)
        end

        TriggerClientEvent('CHW:client:endMatch', source, {
            coords = player.returnCoords,
            heading = player.returnHeading,
            won = player.won == true,
            cleanupFailed = not cleaned or not restored
        })
    end

    CHW.State.players[source] = player.cleanupFailed and {
        cleanupFailed = true,
        identifier = player.identifier
    } or nil
end

local function startNextCountdown()
    if CHW.State.countdownActive or CHW.State.countdownPending then
        return
    end

    local lobby = firstReadyLobby()
    if lobby then
        CHW.Match.BeginCountdown(lobby.id)
    end
end

function CHW.Match.GetInfo(source)
    local membership = CHW.State.players[source]
    local ownLobby = lobbyById(CHW.State.playerLobby[source])
    local ownMatch = matchForPlayer(source)
    local info = {
        name = Config.ArenaName,
        title = 'Chamber Wars',
        queued = lobbyCount(ownLobby),
        minimumPlayers = Config.Match.minimumPlayers,
        maximumPlayers = Config.Match.maximumPlayers,
        countdown = CHW.State.countdownActive == true and ownLobby and CHW.State.countdownLobbyId == ownLobby.id,
        countdownPending = CHW.State.countdownPending == true and ownLobby and CHW.State.countdownLobbyId == ownLobby.id,
        active = activeMatchCount() > 0,
        alive = ownMatch and #livingPlayers(ownMatch) or 0,
        inQueue = CHW.State.queued[source] == true,
        inMatch = membership and membership.matchId ~= nil or false,
        activeLobbies = #activeLobbies(),
        countdownSeconds = ownLobby and CHW.State.countdownLobbyId == ownLobby.id and CHW.State.countdownSeconds or nil,
        lobbies = activeLobbies(),
        players = lobbyPlayers(ownLobby)
    }

    return info
end

function CHW.Match.RecoverPlayer(source)
    local cleaned = CHW.Inventory.CleanupPlayer(source)
    local identifier = CHW.Security.Identifier(source)
    local pending = CHW.State.pendingRestores[identifier]
    local restored = true

    if pending then
        restored, pending = CHW.Inventory.RestorePersonalWeapons(source, pending)
        CHW.State.pendingRestores[identifier] = restored and nil or pending
    end

    if cleaned and restored then
        local player = CHW.State.players[source]
        if player and not player.matchId then
            CHW.State.players[source] = nil
        end
    end

    return cleaned and restored
end

function CHW.Match.StartLobby(source)
    CHW.State.nextLobbyId = CHW.State.nextLobbyId + 1
    local lobby = {
        id = CHW.State.nextLobbyId,
        host = source,
        hostName = GetPlayerName(source) or 'Unknown',
        players = {}
    }
    CHW.State.lobbies[lobby.id] = lobby
    CHW.State.openLobby = lobby

    local success, reason = addToOpenLobby(source, lobby)
    if not success then
        CHW.State.lobbies[lobby.id] = nil
        if CHW.State.openLobby == lobby then
            CHW.State.openLobby = nil
        end
        return false, reason
    end

    notify(source, ("%s's Lobby aangemaakt."):format(lobby.hostName), 'success')
    broadcastLobby(lobby)
    broadcastLobbyList()
    startNextCountdown()
    return true
end

function CHW.Match.JoinQueue(source, lobbyId)
    local lobby = lobbyById(lobbyId)
    if not lobby or lobbyCount(lobby) <= 0 then
        return false, "Er zijn geen open lobby's."
    end

    local success, reason = addToOpenLobby(source, lobby)
    if not success then
        return false, reason
    end

    notify(source, ("%s's Lobby gejoind."):format(lobby.hostName or 'Host'), 'success')
    broadcastLobby(lobby)
    broadcastLobbyList()
    startNextCountdown()
    return true
end

function CHW.Match.Leave(source)
    local removed, lobby = removeFromQueue(source)
    if removed then
        notify(source, 'Je hebt de queue verlaten.', 'success')
        refreshOpenLobby(lobby)
        cancelCountdownIfNotEnough(lobby)
        broadcastLobby(lobby)
        broadcastLobbyList()
        startNextCountdown()
        return true
    end

    local match = matchForPlayer(source)
    local player = match and match.players[source]
    if not player then
        return false, 'Je zit niet in een queue of actieve match.'
    end

    if player.alive then
        player.alive = false
        notify(source, 'Je hebt de match verlaten en bent geëlimineerd.', 'error')
    end

    restorePlayer(source, player, match.id)
    match.players[source] = nil
    broadcastLeaderboard(match)
    CHW.Match.CheckWinner(match)
    return true
end

function CHW.Match.BeginCountdown(lobbyId)
    local lobby = lobbyById(lobbyId)
    if CHW.State.countdownActive or CHW.State.countdownPending or not lobby or lobbyCount(lobby) < Config.Match.minimumPlayers then
        return
    end

    CHW.State.countdownLobbyId = lobby.id
    CHW.State.countdownPending = true
    CHW.State.countdownToken = CHW.State.countdownToken + 1
    CHW.State.countdownSeconds = nil
    local token = CHW.State.countdownToken
    broadcastLobby(lobby)

    CreateThread(function()
        Wait(2000)

        lobby = lobbyById(lobbyId)
        if token ~= CHW.State.countdownToken or not lobby or lobbyCount(lobby) < Config.Match.minimumPlayers then
            clearCountdown()
            if lobby then
                for _, playerId in ipairs(lobby.players) do
                    notify(playerId, 'Countdown geannuleerd: onvoldoende spelers.', 'error')
                end
                broadcastLobby(lobby)
            end
            startNextCountdown()
            return
        end

        CHW.State.countdownPending = false
        CHW.State.countdownActive = true
        CHW.State.countdownSeconds = Config.Match.countdownSeconds

        for seconds = Config.Match.countdownSeconds, 1, -1 do
            lobby = lobbyById(lobbyId)
            if token ~= CHW.State.countdownToken or not lobby or lobbyCount(lobby) < Config.Match.minimumPlayers then
                clearCountdown()
                if lobby then
                    for _, playerId in ipairs(lobby.players) do
                        notify(playerId, 'Countdown geannuleerd: onvoldoende spelers.', 'error')
                    end
                    broadcastLobby(lobby)
                end
                startNextCountdown()
                return
            end

            CHW.State.countdownSeconds = seconds
            for _, playerId in ipairs(lobby.players) do
                TriggerClientEvent('CHW:client:countdown', playerId, seconds)
            end
            broadcastLobby(lobby)
            Wait(1000)
        end

        lobby = lobbyById(lobbyId)
        clearCountdown()
        if token == CHW.State.countdownToken and lobby and lobbyCount(lobby) >= Config.Match.minimumPlayers then
            CHW.Match.Start(lobby.id)
        end
    end)
end

function CHW.Match.BeginWeaponVote(match)
    if not isMatchActive(match) then
        return
    end

    if not Config.WeaponVote or Config.WeaponVote.enabled ~= true then
        applyWeaponVoteResult(match)
        return
    end

    match.weaponVoteActive = true
    match.weaponVotes = {}
    match.weaponVoteToken = (match.weaponVoteToken or 0) + 1
    local token = match.weaponVoteToken
    local duration = Config.WeaponVote.durationSeconds or 10

    CreateThread(function()
        Wait(700)

        for seconds = duration, 1, -1 do
            if not isMatchActive(match) or token ~= match.weaponVoteToken or not match.weaponVoteActive then
                return
            end

            match.weaponVoteSeconds = seconds
            broadcastWeaponVote(match, seconds)
            if allPlayersVoted(match) then
                break
            end

            Wait(1000)
        end

        if isMatchActive(match) and token == match.weaponVoteToken then
            applyWeaponVoteResult(match)
        end
    end)
end

function CHW.Match.CastWeaponVote(source, weaponType)
    local match = matchForPlayer(source)
    local player = match and match.players[source]
    if not match or not player or match.weaponVoteActive ~= true then
        return false, 'Er is nu geen weapon vote actief.'
    end

    local weapon = weaponOption(weaponType)
    if not weapon then
        return false, 'Ongeldige weapon vote.'
    end

    match.weaponVotes[source] = weapon.type
    broadcastWeaponVote(match, match.weaponVoteSeconds or Config.WeaponVote.durationSeconds or 10)

    if allPlayersVoted(match) then
        applyWeaponVoteResult(match)
    end

    return true
end

function CHW.Match.Start(lobbyId)
    local lobby = lobbyById(lobbyId)
    if not lobby or lobbyCount(lobby) < Config.Match.minimumPlayers then
        return
    end

    setLegacyQueueForLobby(lobby)
    removeLobby(lobby)
    CHW.State.nextMatchId = CHW.State.nextMatchId + 1
    local match = {
        id = CHW.State.nextMatchId,
        players = {},
        startedAt = os.time(),
        combatActive = false,
        weaponVoteActive = false,
        weaponVotes = {}
    }

    local selected = {}
    while #selected < Config.Match.maximumPlayers and #CHW.State.queue > 0 do
        local source = table.remove(CHW.State.queue, 1)
        if GetPlayerName(source) then
            selected[#selected + 1] = source
        end
    end

    for i = 1, #selected do
        local source = selected[i]
        local ped = GetPlayerPed(source)
        if ped > 0 then
            local prepared, reason, storedItems = CHW.Inventory.PreparePlayer(source, match.id)
            if prepared then
                local coords = GetEntityCoords(ped)
                local player = {
                    matchId = match.id,
                    alive = true,
                    lives = Config.Match.startLives,
                    maxLives = Config.Match.startLives,
                    eliminated = false,
                    kills = 0,
                    killStreak = 0,
                    returnCoords = vec3(coords.x, coords.y, coords.z),
                    returnHeading = GetEntityHeading(ped),
                    previousBucket = GetPlayerRoutingBucket(source),
                    identifier = CHW.Security.Identifier(source),
                    storedItems = storedItems
                }
                match.players[source] = player
                CHW.State.players[source] = player
            else
                if storedItems and #storedItems > 0 then
                    CHW.State.pendingRestores[CHW.Security.Identifier(source)] = storedItems
                    CHW.State.players[source] = { cleanupFailed = true }
                end
                notify(source, reason, 'error')
            end
        end
    end

    if #livingPlayers(match) < Config.Match.minimumPlayers then
        for source, player in pairs(match.players) do
            restorePlayer(source, player, match.id)
            notify(source, 'Match geannuleerd: onvoldoende geldige spelers.', 'error')
        end
        resetLegacyQueue()
        startNextCountdown()
        return
    end

    local playerCount = #livingPlayers(match)
    match.testBots = {}
    if shouldUseTestBot(playerCount) then
        for i = 1, #Config.TestBot.spawns do
            match.testBots[i] = true
        end
    end
    match.testMode = next(match.testBots) ~= nil
    CHW.State.matches[match.id] = match
    CHW.State.current = match
    local spawnOrder = {}
    for i = 1, #Config.Arena.spawnpoints do
        spawnOrder[i] = i
    end
    for i = #spawnOrder, 2, -1 do
        local j = math.random(i)
        spawnOrder[i], spawnOrder[j] = spawnOrder[j], spawnOrder[i]
    end

    local index = 1
    local initialLeaderboard = {
        rows = leaderboardRows(match),
        maxRows = Config.Leaderboard and Config.Leaderboard.maxRows or 5
    }
    for source, player in pairs(match.players) do
        local spawn = Config.Arena.spawnpoints[spawnOrder[index]]
        index = index + 1
        SetPlayerRoutingBucket(source, matchBucket(match.id))
        TriggerClientEvent('CHW:client:startMatch', source, {
            matchId = match.id,
            spawn = spawn,
            lives = player.lives,
            maxLives = player.maxLives or Config.Match.startLives,
            introActive = true,
            voteActive = Config.WeaponVote and Config.WeaponVote.enabled == true,
            spawnTestBots = next(match.testBots) ~= nil,
            leaderboard = initialLeaderboard
        })
    end
    broadcastLeaderboard(match)

    Wait(Config.Match.preVoteLoadMs or 2500)
    if not isMatchActive(match) then
        return
    end

    CHW.Match.BeginWeaponVote(match)

    CreateThread(function()
        while isMatchActive(match) do
            Wait(1000)
            if match.finishing then
                return
            end

            if os.time() - match.startedAt >= Config.Arena.maxDurationSeconds then
                CHW.Match.Finish(nil, 'De maximale matchduur is bereikt.', match)
                return
            end

            for source, player in pairs(match.players) do
                if match.combatActive and player.alive and GetPlayerName(source) then
                    local ped = GetPlayerPed(source)
                    local coords = ped > 0 and GetEntityCoords(ped) or nil
                    if coords and isOutsideArena(coords) then
                        if not player.outsideSince then
                            player.outsideSince = os.time()
                            notify(source, 'Keer terug naar de arena of je verliest een leven.', 'error')
                            TriggerClientEvent('chat:addMessage', source, {
                                args = { Config.ArenaName, 'Keer terug naar de arena of je verliest een leven.' }
                            })
                        elseif os.time() - player.outsideSince >= Config.Arena.boundaryGraceSeconds then
                            CHW.Match.ApplyHit(source, nil, 'boundary')
                        end
                    else
                        player.outsideSince = nil
                    end
                end
            end
        end
    end)

    startNextCountdown()
end

function CHW.Match.Eliminate(victim, killer, weaponType)
    local match = matchForPlayer(victim)
    local player = match and match.players[victim]
    if not player or player.eliminated then
        return false
    end

    player.alive = false
    player.eliminated = true
    local killerPlayer = killer and match.players[killer]
    if killerPlayer and killerPlayer.alive and not killerPlayer.eliminated and killer ~= victim then
        killerPlayer.kills = killerPlayer.kills + 1
        addBonusLife(match, killer, killerPlayer)
        if not addPrimaryAmmoReward(match, killer, weaponType) then
            notify(killer, 'Ammo reward kon niet worden toegepast.', 'error')
        end
    end
    broadcastLeaderboard(match)

    local alive = livingPlayers(match)
    player.spectateTarget = alive[1]
    TriggerClientEvent('CHW:client:eliminated', victim, alive[1])
    CHW.Match.CheckWinner(match)
    return true
end

function CHW.Match.ApplyHit(victim, killer, weaponType, distance, headshot)
    local match = matchForPlayer(victim)
    local player = match and match.players[victim]
    if not match or not match.combatActive or not player or not player.alive or player.eliminated then
        return false
    end

    player.alive = false
    player.lives = math.max(0, (player.lives or Config.Match.startLives) - 1)
    player.killStreak = 0
    TriggerClientEvent('CHW:client:deathImpact', victim)
    Wait(Config.DeathAnimation and Config.DeathAnimation.impactLeadMs or 250)
    updateLives(victim, player)

    local killerPlayer = killer and match.players[killer]
    if killerPlayer and killerPlayer.alive and not killerPlayer.eliminated and killer ~= victim then
        killerPlayer.kills = killerPlayer.kills + 1
        addBonusLife(match, killer, killerPlayer)
        broadcastKillfeed(match, victim, killer, weaponType, distance, headshot)
        if not addPrimaryAmmoReward(match, killer, weaponType) then
            notify(killer, 'Ammo reward kon niet worden toegepast.', 'error')
        end
    end
    broadcastLeaderboard(match)

    if player.lives <= 0 then
        player.eliminated = true
        local alive = livingPlayers(match)
        player.spectateTarget = alive[1]
        TriggerClientEvent('CHW:client:eliminated', victim, alive[1])
        CHW.Match.CheckWinner(match)
        return true
    end

    local deathcamEnabled = Config.Deathcam and Config.Deathcam.enabled == true and killer and match.players[killer] ~= nil
    local respawnDelay = deathcamEnabled
        and ((Config.Deathcam.bodyViewMs or 0) + (Config.Deathcam.spectateMs or 0) + (Config.Deathcam.fadeMs or 0))
        or (Config.Match.respawnDelayMs or 1000)
    local spawn = randomSpawn()
    TriggerClientEvent('CHW:client:respawn', victim, {
        spawn = spawn,
        lives = player.lives,
        maxLives = player.maxLives or Config.Match.startLives,
        weapon = match.weapon,
        startAmmo = match.weapon and match.weapon.ammo or Config.Match.startAmmo,
        primarySlot = match.weapon and CHW.Inventory.GetArenaWeaponSlot(victim, match.id, match.weapon.item) or nil,
        delay = respawnDelay,
        deathcam = deathcamEnabled and {
            bodyViewMs = Config.Deathcam.bodyViewMs,
            spectateMs = Config.Deathcam.spectateMs,
            fadeMs = Config.Deathcam.fadeMs,
            killer = {
                id = killer,
                name = GetPlayerName(killer),
                kills = killerPlayer and killerPlayer.kills or 0,
                lives = killerPlayer and killerPlayer.lives or 0
            },
            weapon = weaponType,
            distance = distance and math.floor(distance + 0.5) or nil
        } or nil
    })

    CreateThread(function()
        Wait(respawnDelay)
        if isMatchActive(match) and match.players[victim] == player and not player.eliminated then
            player.alive = true
            player.outsideSince = nil
            giveStartAmmo(victim, match.id)
            for source, spectatorPlayer in pairs(match.players) do
                if spectatorPlayer.eliminated and spectatorPlayer.spectateTarget == victim and GetPlayerName(source) then
                    TriggerClientEvent('CHW:client:refreshSpectateTarget', source, victim)
                end
            end
        end
    end)

    return true
end

function CHW.Match.ReportKill(victim, killer, weaponHash)
    local match = matchForPlayer(victim)
    local victimPlayer = match and match.players[victim]
    local killerPlayer = match and match.players[killer]
    local weaponType = CHW.Security.WeaponType(weaponHash)

    if not match or not match.combatActive or not victimPlayer or not killerPlayer or killer == victim then
        return
    end
    if not victimPlayer.alive or not killerPlayer.alive then
        return
    end
    if not CHW.Security.IsDead(victim) then
        return
    end
    if not weaponType then
        CHW.Security.Log(killer, ('reportKill rejected: invalid weapon victim=%s weapon=%s'):format(
            tostring(victim), tostring(weaponHash)))
        TriggerClientEvent('CHW:client:restoreFromInvalidDamage', victim)
        notify(killer, 'Alleen het gekozen arena-wapen en je mes tellen in deze ronde.', 'error')
        return
    end
    if weaponType ~= 'knife' and not isMatchPrimaryWeapon(match, weaponType) then
        CHW.Security.Log(killer, ('reportKill rejected: non-voted weapon=%s victim=%s selected=%s'):format(
            tostring(weaponType), tostring(victim), tostring(match.weaponType)))
        TriggerClientEvent('CHW:client:restoreFromInvalidDamage', victim)
        notify(killer, 'Dit wapen is deze ronde niet gekozen.', 'error')
        return
    end

    local distance
    local killerPed = GetPlayerPed(killer)
    local victimPed = GetPlayerPed(victim)
    if killerPed > 0 and victimPed > 0 then
        distance = #(GetEntityCoords(killerPed) - GetEntityCoords(victimPed))
    end

    if isMatchPrimaryWeapon(match, weaponType) then
        CreateThread(function()
            Wait(250)

            if not isMatchActive(match) then
                return
            end

            local victimPlayerNow = match.players[victim]
            local killerPlayerNow = match.players[killer]
            if not victimPlayerNow or not killerPlayerNow then
                return
            end
            if not victimPlayerNow.alive or victimPlayerNow.eliminated or not killerPlayerNow.alive or killerPlayerNow.eliminated then
                return
            end

            local serverHeadshot = consumeHeadshot(killer, victim)
            CHW.Security.Debug(('Pistol kill resolved %s -> %s headshot=%s'):format(
                killer, victim, tostring(serverHeadshot)))
            CHW.Match.ApplyHit(victim, killer, weaponType, distance, serverHeadshot == true)
        end)
        return
    end

    CHW.Match.ApplyHit(victim, killer, weaponType, distance, false)
end

function CHW.Match.ReportHit(shooter, target, weaponHash, headshot)
    local match = matchForPlayer(target)
    shooter = tonumber(shooter)
    target = tonumber(target)

    if not match or not match.combatActive or not shooter or not target or shooter == target or match.finishing then
        return
    end

    local shooterPlayer = match.players[shooter]
    local targetPlayer = match.players[target]
    local weaponType = CHW.Security.WeaponType(weaponHash)

    if not shooterPlayer or not targetPlayer then
        return
    end
    if shooterPlayer.matchId ~= match.id or targetPlayer.matchId ~= match.id then
        return
    end
    if not shooterPlayer.alive or shooterPlayer.eliminated or not targetPlayer.alive or targetPlayer.eliminated then
        return
    end
    if not weaponType then
        CHW.Security.Log(shooter, ('reportHit rejected: invalid weapon target=%s weapon=%s'):format(
            tostring(target), tostring(weaponHash)))
        unlockInvalidDamage(target)
        CHW.Security.Debug(('Invalid hit weapon from %s to %s: %s'):format(shooter, target, weaponHash))
        return
    end
    if weaponType ~= 'knife' and not isMatchPrimaryWeapon(match, weaponType) then
        CHW.Security.Log(shooter, ('reportHit rejected: non-voted weapon=%s target=%s selected=%s'):format(
            tostring(weaponType), tostring(target), tostring(match.weaponType)))
        unlockInvalidDamage(target)
        CHW.Security.Debug(('Hit rejected: %s used non-voted weapon %s'):format(shooter, weaponType))
        return
    end

    local weaponItem = weaponType == 'knife' and Config.Items.knife or (match.weapon and match.weapon.item)
    if not CHW.Inventory.HasArenaWeapon(shooter, match.id, weaponItem) then
        CHW.Security.Log(shooter, ('reportHit rejected: missing arena item=%s target=%s'):format(
            tostring(weaponItem), tostring(target)))
        unlockInvalidDamage(target)
        CHW.Security.Debug(('Hit rejected: %s has no arena %s'):format(shooter, weaponItem))
        return
    end

    local shooterPed = GetPlayerPed(shooter)
    local targetPed = GetPlayerPed(target)
    if shooterPed <= 0 or targetPed <= 0 then
        return
    end

    local distance = #(GetEntityCoords(shooterPed) - GetEntityCoords(targetPed))
    local maxDistance = weaponType == 'knife'
        and (Config.Match.knifeHitMaxDistance or 5.0)
        or (match.weapon and match.weapon.maxDistance or Config.Match.pistolHitMaxDistance or 170.0)
    if distance > maxDistance then
        CHW.Security.Log(shooter, ('reportHit rejected: distance %.2fm > %.2fm target=%s weapon=%s'):format(
            distance, maxDistance, tostring(target), tostring(weaponType)))
        unlockInvalidDamage(target)
        CHW.Security.Debug(('Suspicious hit rejected: %s -> %s at %.2fm'):format(shooter, target, distance))
        return
    end

    if isMatchPrimaryWeapon(match, weaponType) then
        CreateThread(function()
            Wait(250)

            if not isMatchActive(match) then
                return
            end

            local shooterPlayer = match.players[shooter]
            local targetPlayer = match.players[target]
            if not shooterPlayer or not targetPlayer then
                return
            end
            if not shooterPlayer.alive or shooterPlayer.eliminated or not targetPlayer.alive or targetPlayer.eliminated then
                return
            end

            local serverHeadshot = consumeHeadshot(shooter, target)
            CHW.Security.Debug(('Pistol hit resolved %s -> %s headshot=%s client=%s'):format(
                shooter, target, tostring(serverHeadshot), tostring(headshot == true)))
            CHW.Match.ApplyHit(target, shooter, weaponType, distance, headshot == true or serverHeadshot == true)
        end)
        return
    end

    CHW.Match.ApplyHit(target, shooter, weaponType, distance, false)
end

function CHW.Match.ReportDeath(source)
    local match = matchForPlayer(source)
    local player = match and match.players[source]
    if match and match.combatActive and player and player.alive and CHW.Security.IsDead(source) then
        CHW.Match.ApplyHit(source, nil, 'other')
    end
end

function CHW.Match.ReportTestBotKill(source, botIndex, weaponHash)
    local match = matchForPlayer(source)
    local player = match and match.players[source]
    local weaponType = CHW.Security.WeaponType(weaponHash)
    botIndex = tonumber(botIndex)

    if not Config.TestBot.enabled or not match or not match.combatActive or match.finishing or not botIndex or not match.testBots[botIndex] then
        return
    end
    if not player or not player.alive or not weaponType then
        return
    end
    if weaponType ~= 'knife' and not isMatchPrimaryWeapon(match, weaponType) then
        return
    end
    if #livingPlayers(match) ~= 1 then
        return
    end

    match.testBots[botIndex] = nil
    player.kills = player.kills + 1
    addBonusLife(match, source, player)
    addPrimaryAmmoReward(match, source, weaponType)
    TriggerClientEvent('CHW:client:removeTestBot', source, botIndex)
    broadcastLeaderboard(match)

    if next(match.testBots) then
        notify(source, 'Testbot uitgeschakeld. Er is nog een tegenstander over.', 'success')
        return
    end

    match.finishing = true
    CHW.Match.Finish(source, nil, match)
end

function CHW.Match.CheckWinner(match)
    if not isMatchActive(match) then
        return
    end

    local alive = livingPlayers(match)
    if #alive <= 1 then
        CHW.Match.Finish(alive[1], nil, match)
    end
end

function CHW.Match.Finish(winner, reason, match)
    match = match or (winner and matchForPlayer(winner)) or CHW.State.current
    if not isMatchActive(match) then
        return
    end

    match.finishing = true
    match.combatActive = false

    CHW.State.matches[match.id] = nil
    if CHW.State.current == match then
        CHW.State.current = nil
    end
    if winner and match.players[winner] then
        match.players[winner].won = true
        local xPlayer = CHW.ESX.GetPlayerFromId(winner)
        if not match.testMode and xPlayer and Config.Reward.enabled and Config.Reward.amount > 0 then
            if Config.Reward.account == 'money' then
                xPlayer.addMoney(Config.Reward.amount, Config.ArenaName .. ' winner reward')
            else
                xPlayer.addAccountMoney(Config.Reward.account, Config.Reward.amount, Config.ArenaName .. ' winner reward')
            end
        end
    end

    for source, player in pairs(match.players) do
        restorePlayer(source, player, match.id)
        if reason then
            notify(source, reason, 'inform')
        elseif source == winner then
            if match.testMode then
                notify(source, ('Je wint %s!'):format(Config.ArenaName), 'success')
            else
                notify(source, ('Je wint %s! Reward: $%d.'):format(Config.ArenaName, Config.Reward.amount), 'success')
            end
        else
            notify(source, 'De match is afgelopen.', 'inform')
        end
    end

    startNextCountdown()
end

function CHW.Match.DropPlayer(source)
    local removed, lobby = removeFromQueue(source)
    if removed then
        refreshOpenLobby(lobby)
        cancelCountdownIfNotEnough(lobby)
        broadcastLobby(lobby)
        broadcastLobbyList()
        startNextCountdown()
    end
    local match = matchForPlayer(source)
    if match and match.players[source] then
        local player = match.players[source]
        CHW.Inventory.CleanupPlayer(source, match.id)
        restoreHeldWeapons(source, player)
        match.players[source] = nil
        CHW.State.players[source] = nil
        broadcastLeaderboard(match)
        CHW.Match.CheckWinner(match)
    end
end
