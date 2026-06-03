CHWClient = {
    activeMatch = nil,
    npc = nil
}

local function notify(description, kind)
    CHWClient.Notify({
        title = Config.ArenaName,
        description = description,
        type = kind or 'inform'
    })
end

function CHWClient.Notify(options)
    options = options or {}
    lib.notify({
        id = options.id,
        title = options.title or Config.ArenaName,
        description = options.description or '',
        type = options.type or 'inform',
        position = options.position or 'top',
        icon = options.icon or (options.type == 'error' and 'circle-x' or options.type == 'success' and 'circle-check' or 'circle-check'),
        duration = options.duration or 4500,
        style = {
            backgroundColor = '#08090e',
            color = '#ffffff',
            border = '1px solid #2a1a1a',
            borderLeft = '4px solid #e03030',
            borderRadius = '8px',
            boxShadow = '0 12px 24px rgba(0, 0, 0, 0.38), 0 0 18px rgba(224, 48, 48, 0.22)',
            ['.title'] = {
                color = '#7a5555',
                letterSpacing = '2px',
                textTransform = 'uppercase',
                fontSize = '10px',
                fontWeight = '400'
            },
            ['.description'] = {
                color = '#f4f4f6',
                fontSize = '13px',
                fontWeight = '700'
            },
            ['.icon'] = {
                color = '#e03030',
                filter = 'drop-shadow(0 0 7px rgba(224, 48, 48, 0.85))'
            }
        }
    })
end

function CHWClient.OpenMenu()
    local info = lib.callback.await('CHW:server:getInfo', false)
    if not info then
        notify('Wacht even voordat je het menu opnieuw opent.', 'error')
        return
    end

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'showChamberMenu',
        data = info
    })
end

RegisterNetEvent('CHW:client:openMenu', CHWClient.OpenMenu)

RegisterNetEvent('CHW:client:notify', function(description, kind)
    notify(description, kind)
end)

RegisterNetEvent('CHW:client:lobbyUpdate', function(data)
    SendNUIMessage({
        action = 'showLobby',
        data = data
    })
end)

RegisterNetEvent('CHW:client:lobbyListUpdate', function(lobbies)
    SendNUIMessage({
        action = 'updateChamberLobbies',
        lobbies = lobbies or {}
    })
end)

RegisterNUICallback('chamberAction', function(data, cb)
    local action = data and data.type

    if action == 'start' then
        TriggerServerEvent('CHW:server:startLobby')
    elseif action == 'join' then
        TriggerServerEvent('CHW:server:joinQueue', data and data.lobbyId)
    elseif action == 'leave' then
        TriggerServerEvent('CHW:server:leaveQueue')
    elseif action == 'cleanup' then
        TriggerServerEvent('CHW:server:requestCleanup')
    end

    cb({ ok = true })
end)

RegisterNUICallback('voteWeapon', function(data, cb)
    if data and data.weapon then
        TriggerServerEvent('CHW:server:voteWeapon', data.weapon)
    end

    cb({ ok = true })
end)

RegisterNUICallback('closeChamberMenu', function(_, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideChamberMenu' })
    cb({ ok = true })
end)

RegisterNetEvent('CHW:client:countdown', function(seconds)
    -- Countdown is shown in the lobby overlay.
end)
