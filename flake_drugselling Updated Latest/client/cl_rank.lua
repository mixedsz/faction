-- Initialize ESX or QBCore
if GetResourceState(Config.ESXgetSharedObject) == "started" then
    ESX = exports[Config.ESXgetSharedObject]:getSharedObject()
else
    if GetResourceState(Config.QBCoreGetCoreObject) == "started" then
        QBCore = exports[Config.QBCoreGetCoreObject]:GetCoreObject()
    end
end

local rankBarVisible = false

-- Calculate progress percentage between two points
local function calculateProgress(current, min, max)
    if max <= min then
        return 100
    end
    local range = max - min
    local progress = current - min
    return math.floor((progress / range) * 100)
end

-- Get rank information based on points
local function getRankInfo(points)
    local currentRank = 0
    local currentRankPoints = 0
    local nextRankPoints = Config.Ranks[1].points
    local rankLabel = "Beginner"

    -- Find current rank based on points
    for i, rank in ipairs(Config.Ranks) do
        if points >= rank.points then
            currentRank = i
            currentRankPoints = rank.points
            rankLabel = rank.label
        else
            break
        end
    end

    -- Determine next rank points
    if currentRank == 0 then
        -- Haven't reached first rank yet
        nextRankPoints = Config.Ranks[1].points
    elseif currentRank < #Config.Ranks then
        nextRankPoints = Config.Ranks[currentRank + 1].points
    else
        -- Max rank reached
        nextRankPoints = currentRankPoints + 1
    end

    return {
        currentRank = currentRank == 0 and 1 or currentRank,
        nextRank = currentRank == 0 and 1 or math.min(currentRank + 1, #Config.Ranks),
        rankLabel = rankLabel,
        progress = calculateProgress(points, currentRankPoints, nextRankPoints)
    }
end

-- Check if player leveled up and show notification
local function checkLevelUp(oldPoints, newPoints)
    local oldRankInfo = getRankInfo(oldPoints)
    local newRankInfo = getRankInfo(newPoints)

    if newRankInfo.currentRank > oldRankInfo.currentRank then
        local rewardType = Config.Ranks[newRankInfo.currentRank].rewards and Config.Ranks[newRankInfo.currentRank].rewards.type or nil

        if rewardType then
            SendNUIMessage({
                action = "showLevelUp",
                level = newRankInfo.currentRank,
                type = rewardType,
                uiColor = Config.UIcolor
            })
        end
    end
end

-- Show rank progress bar
function ShowRankProgressBar(currentPoints, addedPoints, previousPoints)
    local rankInfo = getRankInfo(currentPoints)
    local previousProgress = nil
    local isLevelUp = false
    local oldRank = nil
    local newRank = nil

    if addedPoints and addedPoints > 0 then
        if not previousPoints then
            previousPoints = currentPoints - addedPoints
        end

        local prevRankInfo = getRankInfo(previousPoints)
        previousProgress = prevRankInfo.progress

        if rankInfo.currentRank > prevRankInfo.currentRank then
            isLevelUp = true
            oldRank = prevRankInfo.currentRank
            newRank = rankInfo.currentRank
        end
    end

    SendNUIMessage({
        action = "showRankBar",
        rankName = rankInfo.rankLabel,
        currentRank = rankInfo.currentRank,
        nextRank = rankInfo.nextRank,
        progress = rankInfo.progress,
        addedPoints = addedPoints,
        previousProgress = previousProgress,
        isLevelUp = isLevelUp,
        oldRank = oldRank,
        newRank = newRank,
        oldRankName = isLevelUp and Config.Ranks[oldRank].label or rankInfo.rankLabel,
        uiColor = Config.UIcolor
    })

    rankBarVisible = true

    local hideDelay = isLevelUp and 8000 or 5000
    Citizen.SetTimeout(hideDelay, function()
        if rankBarVisible then
            SendNUIMessage({
                action = "hideRankBar"
            })
            rankBarVisible = false
        end
    end)
end

-- Event: Show rank progress
RegisterNetEvent('flake_drugselling:showRankProgress', function(currentPoints, addedPoints, previousPoints)
    if not previousPoints then
        previousPoints = currentPoints - addedPoints
    end

    checkLevelUp(previousPoints, currentPoints)
    ShowRankProgressBar(currentPoints, addedPoints, previousPoints)
end)

-- Event: Show level up notification
RegisterNetEvent('flake_drugselling:showLevelUpNotification', function(level, rewardType)
    SendNUIMessage({
        action = "showLevelUp",
        level = level,
        type = rewardType,
        uiColor = Config.UIcolor
    })
end)

-- Hide rank bar on resource start
Citizen.CreateThread(function()
    SendNUIMessage({
        action = "hideRankBar"
    })
end)

-- Debug commands
if Config.Debug then
    RegisterCommand("testcarlevelup", function(source, args)
        local level = tonumber(args[1]) or 2
        SendNUIMessage({
            action = "showLevelUp",
            level = level,
            type = "car",
            uiColor = Config.UIcolor
        })
    end, false)

    RegisterCommand("testitemlevelup", function(source, args)
        local level = tonumber(args[1]) or 3
        SendNUIMessage({
            action = "showLevelUp",
            level = level,
            type = "item",
            uiColor = Config.UIcolor
        })
    end, false)

    RegisterCommand("testrankup", function(source, args)
        local fromRank = tonumber(args[1]) or 1
        local toRank = tonumber(args[2]) or fromRank + 1

        if fromRank < 1 or fromRank >= #Config.Ranks or fromRank >= toRank or toRank > #Config.Ranks then
            return
        end

        local fromPoints = Config.Ranks[fromRank].points
        local toPoints = Config.Ranks[toRank].points
        local addedPoints = toPoints - fromPoints

        ShowRankProgressBar(toPoints, addedPoints, fromPoints)
    end, false)
end
