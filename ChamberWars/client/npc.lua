local showingPrompt = false
local usingTarget = false

local function loadModel(model)
    local hash = joaat(model)
    lib.requestModel(hash, 10000)
    return hash
end

local function createArenaHost()
    local model = loadModel(Config.NPC.model)
    local coords = Config.NPC.coords
    local ped = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, coords.w, false, false)

    SetEntityAsMissionEntity(ped, true, true)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedCanBeTargetted(ped, false)

    if Config.NPC.scenario and Config.NPC.scenario ~= '' then
        TaskStartScenarioInPlace(ped, Config.NPC.scenario, 0, true)
    end

    SetModelAsNoLongerNeeded(model)
    CHWClient.npc = ped
    return ped
end

local function setupTarget(ped)
    if GetResourceState('ox_target') ~= 'started' then
        return false
    end

    exports.ox_target:addLocalEntity(ped, {
        {
            name = 'chw_arena_host',
            label = 'Open menu',
            icon = Config.NPC.targetIcon,
            distance = Config.NPC.interactionDistance,
            onSelect = CHWClient.OpenMenu
        }
    })
    return true
end

CreateThread(function()
    local ped = createArenaHost()
    usingTarget = setupTarget(ped)
    if usingTarget then
        return
    end

    while DoesEntityExist(ped) do
        local distance = #(GetEntityCoords(cache.ped) - Config.NPC.coords.xyz)
        if distance <= Config.NPC.interactionDistance then
            if not showingPrompt then
                lib.showTextUI('[E] Open menu')
                showingPrompt = true
            end

            if IsControlJustReleased(0, 38) then
                CHWClient.OpenMenu()
            end
            Wait(0)
        else
            if showingPrompt then
                lib.hideTextUI()
                showingPrompt = false
            end
            Wait(distance < 20.0 and 250 or 1000)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    if showingPrompt then
        lib.hideTextUI()
    end

    if usingTarget and CHWClient.npc then
        exports.ox_target:removeLocalEntity(CHWClient.npc, 'chw_arena_host')
    end

    if CHWClient.npc and DoesEntityExist(CHWClient.npc) then
        DeleteEntity(CHWClient.npc)
    end
end)
