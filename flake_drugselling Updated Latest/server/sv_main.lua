-- Initialize ESX or QBCore
if GetResourceState(Config.ESXgetSharedObject) == "started" then
    ESX = exports[Config.ESXgetSharedObject]:getSharedObject()
elseif GetResourceState(Config.QBCoreGetCoreObject) == "started" then
    QBCore = exports[Config.QBCoreGetCoreObject]:GetCoreObject()
end

-- Create database table if it doesn't exist
CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `flake_drugselling` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `identifier` varchar(60) NOT NULL,
            `levelpoints` int(11) NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            UNIQUE KEY `identifier` (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    print("^2[Drug Selling]^7 Database table checked/created successfully")
end)

-- Get player identifier
local function getPlayerIdentifier(source)
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        return xPlayer and xPlayer.identifier or nil
    elseif QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        return Player and Player.PlayerData.citizenid or nil
    end
    return nil
end

-- Get player from source
local function getPlayer(source)
    if ESX then
        return ESX.GetPlayerFromId(source)
    elseif QBCore then
        return QBCore.Functions.GetPlayer(source)
    end
    return nil
end

-- Add item to player
local function addItem(source, item, count)
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.addInventoryItem(item, count)
            return true
        end
    elseif QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            Player.Functions.AddItem(item, count)
            return true
        end
    end
    return false
end

-- Remove item from player
local function removeItem(source, item, count)
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.removeInventoryItem(item, count)
            return true
        end
    elseif QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            Player.Functions.RemoveItem(item, count)
            return true
        end
    end
    return false
end

-- Get item count
local function getItemCount(source, item)
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            local itemData = xPlayer.getInventoryItem(item)
            return itemData and itemData.count or 0
        end
    elseif QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            local itemData = Player.Functions.GetItemByName(item)
            return itemData and itemData.amount or 0
        end
    end
    return 0
end

-- Add money to player
local function addMoney(source, amount)
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if Config.Account.type == 'account' then
                xPlayer.addAccountMoney(Config.Account.payment, amount)
            else
                xPlayer.addInventoryItem(Config.Account.payment, amount)
            end
            return true
        end
    elseif QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            if Config.Account.type == 'account' then
                Player.Functions.AddMoney(Config.Account.payment, amount)
            else
                Player.Functions.AddItem(Config.Account.payment, amount)
            end
            return true
        end
    end
    return false
end

-- Initialize player in database
local function initializePlayer(identifier)
    local result = MySQL.scalar.await('SELECT identifier FROM flake_drugselling WHERE identifier = ?', {identifier})
    if not result then
        MySQL.insert.await('INSERT INTO flake_drugselling (identifier, levelpoints) VALUES (?, ?)', {identifier, 0})
    end
end

-- Get player level points
local function getPlayerLevel(identifier)
    local result = MySQL.scalar.await('SELECT levelpoints FROM flake_drugselling WHERE identifier = ?', {identifier})
    return result or 0
end

-- Update player level points
local function updatePlayerLevel(identifier, points)
    MySQL.update.await('UPDATE flake_drugselling SET levelpoints = ? WHERE identifier = ?', {points, identifier})
end

-- Add points to player
local function addPlayerPoints(identifier, points)
    local currentPoints = getPlayerLevel(identifier)
    local newPoints = currentPoints + points
    updatePlayerLevel(identifier, newPoints)
    return currentPoints, newPoints
end

-- Callback: Check if player has phone item
lib.callback.register('flake_drugselling:hasPhoneItem', function(source)
    if Config.SalesItem.enable then
        local phoneCount = getItemCount(source, Config.SalesItem.phoneitem)
        return phoneCount > 0
    end
    return true -- If phone check is disabled, always return true
end)

-- Callback: Get all available drugs
lib.callback.register('flake_drugselling:getallavailableDrugs', function(source)
    for drugName, drugConfig in pairs(Config.SellList) do
        local count = getItemCount(source, drugName)
        if count > 0 then
            return drugName, count
        end
    end
    return nil, 0
end)

-- Callback: Get player level
lib.callback.register('flake_drugselling:getLevel', function(source)
    local identifier = getPlayerIdentifier(source)
    if not identifier then
        return nil
    end

    -- Initialize player in database if not exists
    initializePlayer(identifier)

    local levelpoints = getPlayerLevel(identifier)
    return {
        levelpoints = levelpoints
    }
end)

-- Event: Sell drug
RegisterNetEvent('flake_drugselling:server:sellDrug', function(drugItem, drugCount)
    local source = source
    local identifier = getPlayerIdentifier(source)

    if not identifier then
        return
    end

    -- Initialize player in database if not exists
    initializePlayer(identifier)
    
    -- Verify player has the drug
    local actualCount = getItemCount(source, drugItem)
    if actualCount <= 0 then
        TriggerClientEvent('flake_drugsellingCL:notify', source, Config.Notifications.nothingtosell, 'error')
        return
    end
    
    local drugConfig = Config.SellList[drugItem]
    if not drugConfig then
        return
    end
    
    -- Calculate quantity to sell
    local quantityToSell = math.random(drugConfig.quantity.min, drugConfig.quantity.max)
    quantityToSell = math.min(quantityToSell, actualCount)
    
    -- Calculate price
    local pricePerUnit = math.random(drugConfig.price.min, drugConfig.price.max)
    local totalPrice = pricePerUnit * quantityToSell
    
    -- Check for bonus areas
    local playerPed = GetPlayerPed(source)
    local playerCoords = GetEntityCoords(playerPed)
    
    for _, bonusArea in ipairs(Config.BonusAreas) do
        local distance = #(playerCoords - bonusArea.coords)
        if distance <= bonusArea.radius then
            -- Apply bonus
            quantityToSell = math.random(bonusArea.quantity.min, bonusArea.quantity.max)
            quantityToSell = math.min(quantityToSell, actualCount)
            
            local multiplier = math.random(bonusArea.multiplier.min * 100, bonusArea.multiplier.max * 100) / 100
            totalPrice = math.floor(totalPrice * multiplier)
            break
        end
    end
    
    -- Apply rank bonus
    local levelpoints = getPlayerLevel(identifier)
    local rankBonus = 0
    for i, rank in ipairs(Config.Ranks) do
        if levelpoints >= rank.points then
            rankBonus = rank.percentmore or 0
        end
    end
    
    if rankBonus > 0 then
        totalPrice = math.floor(totalPrice * (1 + (rankBonus / 100)))
    end
    
    -- Remove drug from inventory
    if not removeItem(source, drugItem, quantityToSell) then
        return
    end
    
    -- Add money
    addMoney(source, totalPrice)
    
    -- Add points
    local oldPoints, newPoints = addPlayerPoints(identifier, drugConfig.addpoints)

    -- Notify player
    local message = string.format(Config.Notifications.solditemsuccess, quantityToSell, drugConfig.label, totalPrice)
    TriggerClientEvent('flake_drugsellingCL:notify', source, message, 'success')

    -- Trigger rank progress update
    TriggerClientEvent('flake_drugselling:showRankProgress', source, newPoints, drugConfig.addpoints, oldPoints)

    -- Check for rank rewards
    checkRankRewards(source, oldPoints, newPoints)
end)

-- Check and give rank rewards
function checkRankRewards(source, oldPoints, newPoints)
    local oldRank = 1
    local newRank = 1
    
    for i, rank in ipairs(Config.Ranks) do
        if oldPoints >= rank.points then
            oldRank = i
        end
        if newPoints >= rank.points then
            newRank = i
        end
    end
    
    if newRank > oldRank then
        local rankData = Config.Ranks[newRank]
        if rankData.rewards then
            if rankData.rewards.type == 'car' then
                -- Give vehicle reward
                if ESX then
                    local xPlayer = ESX.GetPlayerFromId(source)
                    if xPlayer then
                        local plate = GeneratePlate()
                        MySQL.insert.await('INSERT INTO owned_vehicles (owner, plate, vehicle) VALUES (?, ?, ?)', {
                            xPlayer.identifier,
                            plate,
                            json.encode({model = GetHashKey(rankData.rewards.reward), plate = plate})
                        })
                    end
                elseif QBCore then
                    local Player = QBCore.Functions.GetPlayer(source)
                    if Player then
                        local plate = GeneratePlate()
                        if Config.QBoxVehicleFix then
                            MySQL.insert.await('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (?, ?, ?, ?, ?, ?, ?)', {
                                Player.PlayerData.license,
                                Player.PlayerData.citizenid,
                                rankData.rewards.reward,
                                GetHashKey(rankData.rewards.reward),
                                '{}',
                                plate,
                                0
                            })
                        else
                            MySQL.insert.await('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage) VALUES (?, ?, ?, ?, ?, ?, ?)', {
                                Player.PlayerData.license,
                                Player.PlayerData.citizenid,
                                rankData.rewards.reward,
                                GetHashKey(rankData.rewards.reward),
                                '{}',
                                plate,
                                'pillboxgarage'
                            })
                        end
                    end
                end
            elseif rankData.rewards.type == 'item' then
                -- Give item reward
                addItem(source, rankData.rewards.reward[1], rankData.rewards.reward.amount or 1)
            end
            
            -- Show level up notification
            TriggerClientEvent('flake_drugselling:showLevelUpNotification', source, newRank, rankData.rewards.type)
        end

        -- Log rank up to Discord
        if Config.Logs and Config.Logs.enable then
            local playerName = GetPlayerName(source)
            TriggerEvent('flake_drugselling:server:logRankUp', playerName, newRank, rankData.label, newPoints)
        end
    end
end

-- Generate random plate
function GeneratePlate()
    local plate = ""
    for i = 1, 8 do
        if math.random(1, 2) == 1 then
            plate = plate .. string.char(math.random(65, 90)) -- A-Z
        else
            plate = plate .. math.random(0, 9) -- 0-9
        end
    end
    return plate
end

-- Player loaded event
if ESX then
    RegisterNetEvent('esx:playerLoaded', function(playerId, xPlayer)
        initializePlayer(xPlayer.identifier)
    end)
elseif QBCore then
    RegisterNetEvent('QBCore:Server:PlayerLoaded', function(Player)
        initializePlayer(Player.PlayerData.citizenid)
    end)
end

-- Get player name from identifier
local function getPlayerName(identifier)
    if ESX then
        -- ESX uses 'users' table with 'identifier' and 'firstname'/'lastname' or 'name'
        local result = MySQL.query.await('SELECT firstname, lastname FROM users WHERE identifier = ? LIMIT 1', {identifier})
        if result and result[1] then
            if result[1].firstname and result[1].lastname then
                return result[1].firstname .. ' ' .. result[1].lastname
            end
        end
        -- Fallback: try 'name' column
        local nameResult = MySQL.scalar.await('SELECT name FROM users WHERE identifier = ? LIMIT 1', {identifier})
        if nameResult then
            return nameResult
        end
    elseif QBCore then
        -- QBCore uses 'players' table with 'citizenid' and 'charinfo'
        local result = MySQL.scalar.await('SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', {identifier})
        if result then
            local charinfo = json.decode(result)
            if charinfo and charinfo.firstname and charinfo.lastname then
                return charinfo.firstname .. ' ' .. charinfo.lastname
            end
        end
    end
    return "Unknown"
end

-- Get rank title from XP
local function getRankTitle(xp)
    local title = "Beginner"
    for i, rank in ipairs(Config.Ranks) do
        if xp >= rank.points then
            title = rank.label
        end
    end
    return title
end

-- Callback: Get leaderboard data
lib.callback.register('flake_drugselling:getLeaderboard', function(source, limit)
    limit = limit or 10

    -- Get top players from database
    local results = MySQL.query.await([[
        SELECT identifier, levelpoints
        FROM flake_drugselling
        WHERE levelpoints > 0
        ORDER BY levelpoints DESC
        LIMIT ?
    ]], {limit})

    if not results then
        return {}
    end

    local leaderboard = {}
    for i, row in ipairs(results) do
        local name = getPlayerName(row.identifier)
        local title = getRankTitle(row.levelpoints)

        table.insert(leaderboard, {
            rank = i,
            name = name,
            title = title,
            xp = row.levelpoints
        })
    end

    return leaderboard
end)

-- ============================================
-- DISCORD LOGGING & LEADERBOARD SYSTEM
-- ============================================

-- File to store the Discord message ID (in config folder)
local resourceName = GetCurrentResourceName()
local messageIdFile = GetResourcePath(resourceName) .. "/config/discord_id.txt"
local storedMessageId = nil

-- Load message ID from file
local function LoadMessageId()
    local file = io.open(messageIdFile, "r")
    if file then
        storedMessageId = file:read("*all")
        file:close()
        -- Trim whitespace
        if storedMessageId then
            storedMessageId = storedMessageId:match("^%s*(.-)%s*$")
        end
        if storedMessageId and storedMessageId ~= "" then
            return storedMessageId
        end
    end
    return nil
end

-- Save message ID to file
local function SaveMessageId(messageId)
    local file = io.open(messageIdFile, "w")
    if file then
        file:write(messageId)
        file:close()
        storedMessageId = messageId
    end
end

-- Delete message ID file
local function DeleteMessageId()
    os.remove(messageIdFile)
    storedMessageId = nil
end

-- Log rank ups
RegisterNetEvent('flake_drugselling:server:logRankUp', function(playerName, newRank, rankLabel, totalXP)
    if not Config.Logs or not Config.Logs.enable or not Config.Logs.webhook or Config.Logs.webhook == '' then
        return
    end

    local embed = {
        {
            ["title"] = "🏆 Rank Up!",
            ["description"] = "A player has ranked up!",
            ["color"] = 15844367,
            ["fields"] = {
                {
                    ["name"] = "Player",
                    ["value"] = playerName,
                    ["inline"] = true
                },
                {
                    ["name"] = "New Rank",
                    ["value"] = rankLabel,
                    ["inline"] = true
                },
                {
                    ["name"] = "Rank Level",
                    ["value"] = tostring(newRank),
                    ["inline"] = true
                },
                {
                    ["name"] = "Total XP",
                    ["value"] = tostring(totalXP),
                    ["inline"] = true
                }
            },
            ["footer"] = {
                ["text"] = os.date("%Y-%m-%d %H:%M:%S"),
            },
        }
    }

    PerformHttpRequest(Config.Logs.webhook, function(err, text, headers) end, 'POST', json.encode({
        username = 'Drug Selling Logs',
        embeds = embed
    }), { ['Content-Type'] = 'application/json' })
end)

-- Format number with commas
local function formatNumber(num)
    local formatted = tostring(num)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then
            break
        end
    end
    return formatted
end

-- Get medal emoji for rank position
local function getMedalEmoji(rank)
    if rank == 1 then
        return "🥇"
    elseif rank == 2 then
        return "🥈"
    elseif rank == 3 then
        return "🥉"
    else
        return "▫️"
    end
end

-- Send Discord leaderboard
local function SendDiscordLeaderboard()
    if not Config.Logs or not Config.Logs.enable or not Config.Logs.webhook or Config.Logs.webhook == '' then
        return
    end

    -- Get top 10 players from database
    local results = MySQL.query.await([[
        SELECT identifier, levelpoints
        FROM flake_drugselling
        WHERE levelpoints > 0
        ORDER BY levelpoints DESC
        LIMIT 10
    ]])

    if not results or #results == 0 then
        print("^3[Drug Selling]^7 No leaderboard data available")
        return
    end

    -- Build leaderboard description with all players on one line each
    local leaderboardText = Config.Discord.description .. "\n\n"

    for i, row in ipairs(results) do
        local name = getPlayerName(row.identifier)
        local title = getRankTitle(row.levelpoints)
        local xp = formatNumber(row.levelpoints)
        local medal = getMedalEmoji(i)

        -- Format: 🥇 #1 - Test Test | Trap Star | 6,900 XP
        leaderboardText = leaderboardText .. string.format(
            "%s **#%d - %s** | %s | `%s` XP\n",
            medal,
            i,
            name,
            title,
            xp
        )
    end

    -- Create embed
    local embed = {
        {
            ["title"] = Config.Discord.title,
            ["description"] = leaderboardText,
            ["color"] = Config.Discord.embedColor,
            ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            ["footer"] = {
                ["text"] = Config.Discord.footer,
            }
        }
    }

    -- Add thumbnail if configured
    if Config.Discord.thumbnail then
        embed[1]["thumbnail"] = {
            ["url"] = Config.Discord.thumbnail
        }
    end

    -- Add footer icon if configured
    if Config.Discord.footerIcon then
        embed[1]["footer"]["icon_url"] = Config.Discord.footerIcon
    end

    -- Prepare webhook payload
    local payload = {
        embeds = embed
    }

    -- Add bot name and avatar if configured
    if Config.Discord.botName then
        payload.username = Config.Discord.botName
    end
    if Config.Discord.botAvatar then
        payload.avatar_url = Config.Discord.botAvatar
    end

    -- Check if we have a message ID to edit
    local webhookUrl = Config.Logs.webhook
    local method = 'POST'
    local messageId = storedMessageId or LoadMessageId()

    if messageId and messageId ~= '' then
        -- Edit existing message
        local webhookId, webhookToken = webhookUrl:match("webhooks/(%d+)/([%w-_]+)")
        if webhookId and webhookToken then
            webhookUrl = string.format("https://discord.com/api/webhooks/%s/%s/messages/%s", webhookId, webhookToken, messageId)
            method = 'PATCH'
            payload.username = nil
            payload.avatar_url = nil
        end
    else
        -- Add ?wait=true to get the message data back when posting
        if not webhookUrl:find("?wait=true") then
            webhookUrl = webhookUrl .. "?wait=true"
        end
    end

    -- Send or update Discord message
    PerformHttpRequest(webhookUrl, function(err, text, headers)
        if err == 200 or err == 204 then
            -- If this was a POST (new message), save the message ID
            if method == 'POST' and text and text ~= "" then
                local success, response = pcall(json.decode, text)
                if success and response and response.id then
                    SaveMessageId(response.id)
                end
            end
        else
            -- If edit failed (message might have been deleted), delete stored ID and post new message
            if method == 'PATCH' then
                DeleteMessageId()
            end
        end
    end, method, json.encode(payload), { ['Content-Type'] = 'application/json' })
end

-- Auto-update leaderboard on interval
CreateThread(function()
    if not Config.Logs or not Config.Logs.enable or not Config.Discord or not Config.Discord.updateInterval or Config.Discord.updateInterval <= 0 then
        return
    end

    -- Wait a bit before first update
    Wait(60000) -- Wait 1 minute after server start

    while true do
        SendDiscordLeaderboard()
        Wait(Config.Discord.updateInterval)
    end
end)

-- Command to manually update leaderboard (console only)
RegisterCommand('updateleaderboard', function(source, args, rawCommand)
    if source == 0 then
        SendDiscordLeaderboard()
    end
end, false)

-- Command to reset the leaderboard message (console only)
RegisterCommand('resetleaderboard', function(source, args, rawCommand)
    if source == 0 then
        DeleteMessageId()
    end
end, false)

-- Export function for manual updates
exports('UpdateDiscordLeaderboard', SendDiscordLeaderboard)

-- Load the message ID and post initial leaderboard when server starts
CreateThread(function()
    Wait(5000) -- Wait 5 seconds for everything to load
    LoadMessageId()

    -- Auto-post leaderboard on startup if Discord is enabled
    if Config.Logs and Config.Logs.enable then
        Wait(5000) -- Wait another 5 seconds
        SendDiscordLeaderboard()
    end
end)
