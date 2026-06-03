local arenaZone = nil
local arenaZoneInside = true
local drawDebugSphere = false

local function validateArenaZoneConfig()
    if not Config.Arena or not Config.Arena.center or not Config.Arena.radius or Config.Arena.radius <= 0.0 then
        error('[Chamber Wars] Config.Arena.center en Config.Arena.radius zijn verplicht voor de CircleZone.')
    end
end

local function requirePolyZone()
    if type(CircleZone) ~= 'table' or type(CircleZone.Create) ~= 'function' then
        error('[Chamber Wars] CircleZone is niet geladen. Zorg dat PolyZone gestart is en @PolyZone/CircleZone.lua in fxmanifest.lua staat.')
    end
end

local function notifyBoundaryExit()
    CHWClient.Notify({
        title = Config.ArenaName,
        description = 'Je verlaat de arena. Keer terug of je verliest een leven.',
        type = 'error'
    })

    TriggerEvent('chat:addMessage', {
        args = { Config.ArenaName, 'Je verlaat de arena. Keer terug of je verliest een leven.' }
    })
end

local function createArenaPolyZone()
    validateArenaZoneConfig()
    requirePolyZone()

    arenaZone = CircleZone:Create(Config.Arena.center, Config.Arena.radius, {
        name = 'chamber_arena',
        debugPoly = false,
        useZ = false
    })
    drawDebugSphere = Config.DebugPoly == true

    arenaZone:onPlayerInOut(function(isPointInside)
        if not isPointInside and CHWClient.activeMatch and CHWClient.activeMatch.alive and arenaZoneInside then
            arenaZoneInside = false
            notifyBoundaryExit()
        elseif isPointInside then
            arenaZoneInside = true
        end
    end)

    if Config.Debug then
        print(('[CHW] CircleZone arena geladen. radius=%.1f debugSphere=%s'):format(Config.Arena.radius, tostring(drawDebugSphere)))
    end
end

CreateThread(function()
    Wait(1000)
    createArenaPolyZone()
end)

CreateThread(function()
    while true do
        if drawDebugSphere then
            local sphere = Config.Arena.debugSphere or {}
            local color = sphere.color or {}
            local size = Config.Arena.radius

            DrawMarker(
                28,
                Config.Arena.center.x,
                Config.Arena.center.y,
                Config.Arena.center.z + (sphere.zOffset or 0.0),
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                size, size, size,
                color.r or 255,
                color.g or 0,
                color.b or 0,
                color.a or 95,
                false, false, 2, false, nil, nil, false
            )

            Wait(0)
        else
            Wait(1000)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    if arenaZone and arenaZone.destroy then
        arenaZone:destroy()
    end
end)
