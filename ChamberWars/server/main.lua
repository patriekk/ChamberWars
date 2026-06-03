CHW.ESX = exports['es_extended']:getSharedObject()

RegisterNetEvent('CHW:server:startLobby', function()
    local source = source
    if not CHW.Security.RateLimit(source, 'join', Config.Security.joinCooldownMs) then
        return
    end
    if not CHW.Security.IsNearNPC(source) then
        CHW.Security.Log(source, 'startLobby rejected: not near NPC')
        TriggerClientEvent('CHW:client:notify', source, 'Je moet bij de arena-host staan om een lobby te starten.', 'error')
        return
    end

    local success, reason = CHW.Match.StartLobby(source)
    if not success then
        TriggerClientEvent('CHW:client:notify', source, reason, 'error')
    end
end)

RegisterNetEvent('CHW:server:joinQueue', function(lobbyId)
    local source = source
    if not CHW.Security.RateLimit(source, 'join', Config.Security.joinCooldownMs) then
        return
    end
    if not CHW.Security.IsNearNPC(source) then
        CHW.Security.Log(source, ('joinQueue rejected: not near NPC lobby=%s'):format(tostring(lobbyId)))
        TriggerClientEvent('CHW:client:notify', source, 'Je moet bij de arena-host staan om te joinen.', 'error')
        return
    end

    local success, reason = CHW.Match.JoinQueue(source, lobbyId)
    if not success then
        TriggerClientEvent('CHW:client:notify', source, reason, 'error')
    end
end)

RegisterNetEvent('CHW:server:leaveQueue', function()
    local source = source
    if not CHW.Security.RateLimit(source, 'leave', Config.Security.leaveCooldownMs) then
        return
    end

    local success, reason = CHW.Match.Leave(source)
    if not success then
        TriggerClientEvent('CHW:client:notify', source, reason, 'error')
    end
end)

RegisterNetEvent('CHW:server:voteWeapon', function(weaponType)
    local source = source
    if not CHW.Security.RateLimit(source, 'vote', Config.Security.voteCooldownMs) then
        return
    end

    local success, reason = CHW.Match.CastWeaponVote(source, weaponType)
    if not success then
        TriggerClientEvent('CHW:client:notify', source, reason, 'error')
    end
end)

RegisterNetEvent('CHW:server:reportKill', function(killer, weaponHash)
    local victim = source
    if not CHW.Security.RateLimit(victim, 'death', Config.Security.deathReportCooldownMs) then
        return
    end

    CHW.Match.ReportKill(victim, tonumber(killer), weaponHash)
end)

RegisterNetEvent('CHW:server:reportHit', function(shooter, target, weaponHash, headshot)
    local source = source
    if source ~= tonumber(target) then
        CHW.Security.Log(source, ('reportHit rejected: source target mismatch target=%s shooter=%s weapon=%s'):format(
            tostring(target), tostring(shooter), tostring(weaponHash)))
        return
    end

    if CHW.Security.RateLimit(source, 'hit', Config.Security.hitReportCooldownMs) then
        CHW.Match.ReportHit(shooter, target, weaponHash, headshot == true)
    end
end)

AddEventHandler('weaponDamageEvent', function(sender, data)
    CHW.Match.MarkWeaponDamage(sender, data)
end)

RegisterNetEvent('CHW:server:reportDeath', function()
    local source = source
    if CHW.Security.RateLimit(source, 'death', Config.Security.deathReportCooldownMs) then
        CHW.Match.ReportDeath(source)
    end
end)

RegisterNetEvent('CHW:server:reportTestBotKill', function(botIndex, weaponHash)
    local source = source
    if CHW.Security.RateLimit(source, 'testBotKill', Config.Security.testBotKillCooldownMs) then
        CHW.Match.ReportTestBotKill(source, botIndex, weaponHash)
    end
end)

RegisterNetEvent('CHW:server:requestCleanup', function()
    local source = source
    if not CHW.Security.RateLimit(source, 'cleanup', Config.Security.cleanupCooldownMs) then
        return
    end
    if not CHW.Security.IsNearNPC(source) or (CHW.State.players[source] and CHW.State.players[source].matchId) then
        CHW.Security.Log(source, 'requestCleanup rejected: not near NPC or in active match')
        return
    end

    local success = CHW.Match.RecoverPlayer(source)
    TriggerClientEvent('CHW:client:notify', source,
        success and 'Arena-items zijn opgeschoond en persoonlijke wapens zijn hersteld.' or 'Cleanup kon niet worden afgerond.',
        success and 'success' or 'error')
end)

lib.callback.register('CHW:server:getInfo', function(source)
    if not CHW.Security.RateLimit(source, 'info', Config.Security.infoCooldownMs) then
        return nil
    end

    return CHW.Match.GetInfo(source)
end)

AddEventHandler('playerDropped', function()
    local source = source
    CHW.Match.DropPlayer(source)
    CHW.Security.ClearPlayer(source)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    local matches = {}
    for _, match in pairs(CHW.State.matches or {}) do
        matches[#matches + 1] = match
    end

    for _, match in ipairs(matches) do
        CHW.Match.Finish(nil, 'De arena-resource is gestopt.', match)
    end
end)
