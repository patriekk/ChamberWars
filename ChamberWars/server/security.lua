CHW = CHW or {}
CHW.Security = {}

local cooldowns = {}

function CHW.Security.RateLimit(source, action, cooldown)
    local now = GetGameTimer()
    cooldowns[source] = cooldowns[source] or {}

    if now - (cooldowns[source][action] or 0) < cooldown then
        return false
    end

    cooldowns[source][action] = now
    return true
end

function CHW.Security.IsNearNPC(source)
    local ped = GetPlayerPed(source)
    if ped <= 0 then
        return false
    end

    local position = GetEntityCoords(ped)
    local npcPosition = Config.NPC.coords.xyz
    return #(position - npcPosition) <= Config.NPC.serverValidationDistance
end

function CHW.Security.WeaponType(weaponHash)
    weaponHash = tonumber(weaponHash)
    if not weaponHash then
        return nil
    end

    if Config.AllowedWeapons.pistol[weaponHash] then
        return 'pistol'
    end

    if Config.AllowedWeapons.sniper[weaponHash] then
        return 'sniper'
    end

    if Config.AllowedWeapons.shotgun[weaponHash] then
        return 'shotgun'
    end

    if Config.AllowedWeapons.knife[weaponHash] then
        return 'knife'
    end

    return nil
end

function CHW.Security.IsDead(source)
    local ped = GetPlayerPed(source)
    return ped > 0 and GetEntityHealth(ped) <= 0
end

function CHW.Security.Identifier(source)
    return GetPlayerIdentifierByType(source, 'license') or ('source:%s'):format(source)
end

function CHW.Security.ClearPlayer(source)
    cooldowns[source] = nil
end

function CHW.Security.Debug(message)
    if Config.Debug then
        print(('[CHW] %s'):format(message))
    end
end

function CHW.Security.Log(source, reason)
    if not Config.SecurityLog then
        return
    end

    local name = source and GetPlayerName(source) or 'unknown'
    print(('[CHW SECURITY] %s (%s) | %s'):format(name, source or 'unknown', reason))
end
