-- Initialize ESX or QBCore
if GetResourceState(Config.ESXgetSharedObject) == "started" then
    ESX = exports[Config.ESXgetSharedObject]:getSharedObject()
else
    if GetResourceState(Config.QBCoreGetCoreObject) == "started" then
        QBCore = exports[Config.QBCoreGetCoreObject]:GetCoreObject()
    end
end

local isLeaderboardOpen = false

-- Register leaderboard command
if Config.Commands.leaderboard then
    RegisterCommand(Config.Commands.leaderboard, function()
        openLeaderboard()
    end, false)
    
    TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.leaderboard, 'View the top drug dealers leaderboard')
end

-- Open leaderboard
function openLeaderboard()
    if isLeaderboardOpen then
        return
    end

    -- Get leaderboard data from server
    local leaderboardData = lib.callback.await('flake_drugselling:getLeaderboard', false, 10)

    if not leaderboardData then
        Config.Notify("Failed to load leaderboard", "error")
        return
    end

    -- Show leaderboard UI with config
    SendNUIMessage({
        action = "showLeaderboard",
        leaderboard = leaderboardData,
        config = {
            title = Config.Leaderboard.title,
            subtitle = Config.Leaderboard.subtitle,
            headerImage = Config.Leaderboard.headerImage,
            seasonText = Config.Leaderboard.seasonText,
            uiColor = Config.UIcolor
        }
    })

    -- Set NUI focus
    SetNuiFocus(true, true)
    isLeaderboardOpen = true
end

-- Close leaderboard
function closeLeaderboard()
    if not isLeaderboardOpen then
        return
    end
    
    SendNUIMessage({
        action = "hideLeaderboard"
    })
    
    SetNuiFocus(false, false)
    isLeaderboardOpen = false
end

-- NUI Callback: Close leaderboard
RegisterNUICallback('closeLeaderboard', function(data, cb)
    closeLeaderboard()
    cb('ok')
end)

-- Close on ESC (backup)
CreateThread(function()
    while true do
        Wait(0)
        if isLeaderboardOpen then
            if IsControlJustPressed(0, 322) then -- ESC key
                closeLeaderboard()
            end
        else
            Wait(500)
        end
    end
end)

