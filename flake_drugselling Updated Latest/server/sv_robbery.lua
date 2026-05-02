-- ============================================================
-- sv_robbery.lua  –  handles NPC robbery server events
-- ============================================================

-- Strip the stolen drug from the player when a robbery begins
RegisterNetEvent('flake_drugselling:server:robPlayer', function(drugItem, amount)
    local source = source

    -- Validate item exists in sell list
    if not Config.SellList[drugItem] then return end

    -- Use the shared helper to remove the item
    local removed = false

    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            local itemData = xPlayer.getInventoryItem(drugItem)
            if itemData and itemData.count >= amount then
                xPlayer.removeInventoryItem(drugItem, amount)
                removed = true
            end
        end
    elseif QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            local itemData = Player.Functions.GetItemByName(drugItem)
            if itemData and itemData.amount >= amount then
                Player.Functions.RemoveItem(drugItem, amount)
                removed = true
            end
        end
    end

    if not removed then
        -- Nothing to steal (edge case), tell the client to cancel
        TriggerClientEvent('flake_drugselling:cancelRobbery', source)
    end
end)

-- Return the stolen drug to the player after knockout
RegisterNetEvent('flake_drugselling:server:returnStolenDrugs', function(drugItem, amount)
    local source = source

    if not Config.SellList[drugItem] then return end

    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.addInventoryItem(drugItem, amount)
        end
    elseif QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            Player.Functions.AddItem(drugItem, amount)
        end
    end
end)
