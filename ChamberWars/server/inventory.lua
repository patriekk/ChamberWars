CHW.Inventory = {}

local trackedItems = {
    Config.Items.pistol,
    Config.Items.sniper,
    Config.Items.shotgun,
    Config.Items.knife,
    Config.Items.ammo
}

local primaryItems = {
    Config.Items.pistol,
    Config.Items.sniper,
    Config.Items.shotgun
}

local function callInventory(method, ...)
    local success, result, response = pcall(function(...)
        if method == 'Search' then
            return exports.ox_inventory:Search(...)
        elseif method == 'RemoveItem' then
            return exports.ox_inventory:RemoveItem(...)
        elseif method == 'AddItem' then
            return exports.ox_inventory:AddItem(...)
        elseif method == 'SetMetadata' then
            return exports.ox_inventory:SetMetadata(...)
        end

        error(('Unsupported ox_inventory method: %s'):format(method))
    end, ...)

    if not success then
        CHW.Security.Debug(('ox_inventory %s failed: %s'):format(method, result))
        return false, result
    end

    return result, response
end

local function taggedSlots(source, matchId)
    local results = {}

    for i = 1, #trackedItems do
        local slots = callInventory('Search', source, 'slots', trackedItems[i])
        if type(slots) == 'table' then
            for _, slot in pairs(slots) do
                local metadata = slot.metadata or {}
                if metadata.arena == true and (not matchId or metadata.matchId == matchId) then
                    results[#results + 1] = slot
                end
            end
        end
    end

    return results
end

function CHW.Inventory.GetArenaWeaponSlot(source, matchId, itemName)
    local slots = taggedSlots(source, matchId)

    for i = 1, #slots do
        local slot = slots[i]
        if slot.name == itemName then
            return slot.slot
        end
    end

    return nil
end

function CHW.Inventory.HasArenaItems(source)
    return #taggedSlots(source) > 0
end

local function conflictingWeaponSlots(source)
    local results = {}
    local weaponItems = { Config.Items.pistol, Config.Items.sniper, Config.Items.shotgun, Config.Items.knife }
    for i = 1, #weaponItems do
        local slots = callInventory('Search', source, 'slots', weaponItems[i])
        if type(slots) == 'table' then
            for _, slot in pairs(slots) do
                if not (slot.metadata and slot.metadata.arena == true) then
                    results[#results + 1] = {
                        name = slot.name,
                        count = slot.count,
                        metadata = slot.metadata,
                        slot = slot.slot
                    }
                end
            end
        end
    end

    return results
end

function CHW.Inventory.RestorePersonalWeapons(source, storedItems)
    local remaining = {}

    for i = 1, #(storedItems or {}) do
        local item = storedItems[i]
        local restored = callInventory('AddItem', source, item.name, item.count, item.metadata, item.slot)
        if not restored then
            restored = callInventory('AddItem', source, item.name, item.count, item.metadata)
        end

        if not restored then
            remaining[#remaining + 1] = item
        end
    end

    return #remaining == 0, remaining
end

function CHW.Inventory.StorePersonalWeapons(source)
    local slots = conflictingWeaponSlots(source)
    local storedItems = {}

    for i = 1, #slots do
        local item = slots[i]
        local removed = callInventory('RemoveItem', source, item.name, item.count, item.metadata, item.slot)
        if not removed then
            local restored, remaining = CHW.Inventory.RestorePersonalWeapons(source, storedItems)
            return false, restored and {} or remaining
        end

        storedItems[#storedItems + 1] = item
    end

    return true, storedItems
end

function CHW.Inventory.CleanupPlayer(source, matchId)
    for _ = 1, Config.Cleanup.retryAttempts do
        local slots = taggedSlots(source, matchId)
        if #slots == 0 then
            return true
        end

        for i = 1, #slots do
            local slot = slots[i]
            callInventory('RemoveItem', source, slot.name, slot.count, slot.metadata, slot.slot)
        end
    end

    return not CHW.Inventory.HasArenaItems(source)
end

function CHW.Inventory.PreparePlayer(source, matchId)
    if not CHW.Inventory.CleanupPlayer(source) then
        return false, 'Oude arena-items konden niet worden verwijderd.'
    end

    local stored, storedItems = CHW.Inventory.StorePersonalWeapons(source)
    if not stored then
        return false, 'Je persoonlijke arena-wapens konden niet veilig worden opgeborgen.', storedItems
    end

    local knifeMetadata = {
        arena = true,
        matchId = matchId,
        durability = 100,
        label = ('%s knife'):format(Config.ArenaName)
    }

    local knifeAdded = callInventory('AddItem', source, Config.Items.knife, 1, knifeMetadata)

    if not knifeAdded then
        CHW.Inventory.CleanupPlayer(source, matchId)
        local restored, remaining = CHW.Inventory.RestorePersonalWeapons(source, storedItems)
        if not restored then
            return false, 'Loadout mislukt; gebruik cleanup om persoonlijke wapens terug te halen.', remaining
        end

        return false, 'Je hebt onvoldoende inventoryruimte voor de arena-loadout.'
    end

    return true, nil, storedItems
end

function CHW.Inventory.HasArenaWeapon(source, matchId, itemName)
    local slots = taggedSlots(source, matchId)

    for i = 1, #slots do
        local slot = slots[i]
        if slot.name == itemName then
            return true
        end
    end

    return false
end

local function removeArenaPrimaryWeapons(source, matchId)
    local slots = taggedSlots(source, matchId)

    for i = 1, #slots do
        local slot = slots[i]
        for j = 1, #primaryItems do
            if slot.name == primaryItems[j] then
                callInventory('RemoveItem', source, slot.name, slot.count, slot.metadata, slot.slot)
                break
            end
        end
    end
end

function CHW.Inventory.GiveArenaPrimaryWeapon(source, matchId, weapon)
    if not weapon or not weapon.item then
        return nil
    end

    removeArenaPrimaryWeapons(source, matchId)

    local metadata = {
        arena = true,
        matchId = matchId,
        ammo = weapon.ammo or Config.Match.startAmmo,
        durability = 100,
        label = ('%s %s'):format(Config.ArenaName, weapon.label or weapon.type or 'weapon')
    }

    local added = callInventory('AddItem', source, weapon.item, 1, metadata)
    if not added then
        return nil
    end

    return CHW.Inventory.GetArenaWeaponSlot(source, matchId, weapon.item)
end

function CHW.Inventory.SetPistolAmmo(source, matchId, amount)
    return CHW.Inventory.SetPrimaryAmmo(source, matchId, Config.Items.pistol, amount)
end

function CHW.Inventory.SetPrimaryAmmo(source, matchId, itemName, amount)
    local slots = taggedSlots(source, matchId)

    for i = 1, #slots do
        local slot = slots[i]
        if slot.name == itemName then
            local metadata = {}
            for key, value in pairs(slot.metadata or {}) do
                metadata[key] = value
            end

            metadata.ammo = math.max(0, tonumber(amount) or 0)
            local updated = callInventory('SetMetadata', source, slot.slot, metadata)
            if updated ~= false then
                TriggerClientEvent('CHW:client:setPrimaryAmmo', source, itemName, metadata.ammo, slot.slot)
                return true
            end
        end
    end

    return false
end

function CHW.Inventory.AddPistolAmmo(source, matchId, amount, reason)
    return CHW.Inventory.AddPrimaryAmmo(source, matchId, Config.Items.pistol, amount, reason)
end

function CHW.Inventory.AddPrimaryAmmo(source, matchId, itemName, amount, reason)
    local slots = taggedSlots(source, matchId)

    for i = 1, #slots do
        local slot = slots[i]
        if slot.name == itemName then
            local metadata = {}
            for key, value in pairs(slot.metadata or {}) do
                metadata[key] = value
            end

            metadata.ammo = math.max(0, (tonumber(metadata.ammo) or 0) + amount)
            local updated = callInventory('SetMetadata', source, slot.slot, metadata)
            if updated ~= false then
                TriggerClientEvent('CHW:client:ammoAwarded', source, amount, reason, itemName)
                return true
            end
        end
    end

    return false
end
