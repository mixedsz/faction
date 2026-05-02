-- Initialize ESX or QBCore
if GetResourceState(Config.ESXgetSharedObject) == "started" then
    ESX = exports[Config.ESXgetSharedObject]:getSharedObject()
else
    if GetResourceState(Config.QBCoreGetCoreObject) == "started" then
        QBCore = exports[Config.QBCoreGetCoreObject]:GetCoreObject()
    end
end

-- State variables
local isSelling = false
local canStartNewSale = true
local isInSaleProcess = false
local startLocation = nil
local currentBuyerPed = nil
local buyerSpawned = false
local interactedPeds = {}
local isSaleAnimating = false

-- Robbery state
local robberyPed = nil           -- the ped currently fleeing with stolen drugs
local stolenDrugItem = nil       -- which drug was stolen
local stolenDrugCount = 0        -- how many units were stolen
local isRobberyActive = false    -- is there an active robbery chase

-- ============================================================
-- UTILITY
-- ============================================================

local function markPedInteracted(ped)
    interactedPeds[ped] = true
end

local function wasPedInteracted(ped)
    return interactedPeds[ped] == true
end

local function removeTargetFromEntity(entity)
    if not DoesEntityExist(entity) then return end
    if Config.System == "ox_target" then
        exports.ox_target:removeLocalEntity(entity)
    elseif Config.System == "qb-target" then
        exports["qb-target"]:RemoveTargetEntity(entity)
    end
end

-- ============================================================
-- DESPAWN  (guaranteed hard delete — no dangling peds)
-- ============================================================

local function hardDeletePed(ped)
    if not ped or not DoesEntityExist(ped) then return end
    SetEntityAsMissionEntity(ped, false, true)
    DeleteEntity(ped)
end

-- Walk ped away then hard-delete; no lingering
local function despawnBuyerPed(ped)
    if not ped or not DoesEntityExist(ped) then return end

    -- Clear any current tasks and remove from mission entity pool immediately
    ClearPedTasks(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)

    local playerCoords = GetEntityCoords(PlayerPedId())
    local pedCoords    = GetEntityCoords(ped)
    local dir          = pedCoords - playerCoords
    local dist         = #dir

    if dist < 1.0 then
        local angle = math.random() * 6.28
        dir  = vector3(math.cos(angle), math.sin(angle), 0.0)
        dist = 1.0
    end

    local awayCoords = playerCoords + dir * (30.0 / dist)
    TaskGoStraightToCoord(ped, awayCoords.x, awayCoords.y, awayCoords.z, 1.5, 8000, 0.5, 0.0)

    -- Hard delete after 6 seconds regardless of whether the walk finished
    Citizen.SetTimeout(6000, function()
        hardDeletePed(ped)
        interactedPeds[ped] = nil
    end)
end

-- ============================================================
-- ROBBERY LOGIC
-- ============================================================

-- Roll the robbery chance (higher if AutoSell is on)
local function shouldRobPlayer()
    local chance = Config.RobberyChance and Config.RobberyChance.base or 8
    if Config.AutoSell and Config.AutoSell.enabled then
        chance = Config.RobberyChance and Config.RobberyChance.autoSellBonus or 20
    end
    return math.random(100) <= chance
end

-- Start the robbery: ped grabs the item and flees
local function startRobbery(ped, drugItem, drugCount)
    if isRobberyActive then return end
    isRobberyActive  = true
    robberyPed       = ped
    stolenDrugItem   = drugItem
    stolenDrugCount  = drugCount

    -- Freeze ped briefly for dramatic effect then make it sprint away
    ClearPedTasks(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 17, true)  -- can flee

    Config.Notify("HE'S RUNNING WITH YOUR SHIT! CHASE HIM DOWN!", "error")

    Wait(400)

    -- Make the ped sprint away from the player
    local playerCoords = GetEntityCoords(PlayerPedId())
    local pedCoords    = GetEntityCoords(ped)
    local dir          = pedCoords - playerCoords
    if #dir < 0.5 then dir = vector3(1.0, 0.0, 0.0) end
    local fleeTarget   = pedCoords + (dir / #dir) * 60.0

    TaskGoStraightToCoord(ped, fleeTarget.x, fleeTarget.y, fleeTarget.z, 3.5, 30000, 0.5, 0.0)

    -- Add knockout/interact target on the fleeing ped
    if Config.System == "ox_target" then
        exports.ox_target:addLocalEntity(ped, {
            {
                name   = "flake_drugselling:knockoutRobber",
                icon   = "fa-solid fa-hand-fist",
                label  = "Knock Out",
                distance = 2.0,
                canInteract = function(entity, distance)
                    return isRobberyActive and distance < 2.0
                end,
                onSelect = function()
                    knockoutRobber(ped)
                end
            }
        })
    elseif Config.System == "qb-target" then
        exports["qb-target"]:AddTargetEntity(ped, {
            options = {
                {
                    icon   = "fa-solid fa-hand-fist",
                    label  = "Knock Out",
                    action = function()
                        knockoutRobber(ped)
                    end
                }
            },
            distance = 2.0
        })
    end

    -- Robbery chase thread
    Citizen.CreateThread(function()
        local startTime = GetGameTimer()
        local timeout   = 60000  -- 60 seconds to catch the ped

        while isRobberyActive and DoesEntityExist(ped) do
            Wait(500)

            -- Keep ped running if it stopped
            if not IsPedInAnyVehicle(ped) then
                local pp  = GetEntityCoords(PlayerPedId())
                local ep  = GetEntityCoords(ped)
                local d2  = ep - pp
                if #d2 < 0.5 then d2 = vector3(1.0, 0.0, 0.0) end
                local ft  = ep + (d2 / #d2) * 40.0
                -- re-task every 3 seconds to keep it moving
                if GetGameTimer() % 3000 < 600 then
                    TaskGoStraightToCoord(ped, ft.x, ft.y, ft.z, 3.5, 5000, 0.5, 0.0)
                end
            end

            -- TextUI hint when close enough
            if Config.System == "textui" then
                local pp   = GetEntityCoords(PlayerPedId())
                local ep   = GetEntityCoords(ped)
                if #(ep - pp) < 2.0 then
                    Config.showTextUI('[E] - Knock Out Robber')
                    if IsControlJustPressed(1, 38) then
                        Config.hideTextUI()
                        knockoutRobber(ped)
                        return
                    end
                else
                    Config.hideTextUI()
                end
            end

            -- Robbery escaped timeout
            if GetGameTimer() - startTime > timeout then
                Config.Notify("He got away with your drugs...", "error")
                Config.hideTextUI()
                removeTargetFromEntity(ped)
                isRobberyActive = false
                robberyPed      = nil
                stolenDrugItem  = nil
                stolenDrugCount = 0
                despawnBuyerPed(ped)
                -- Resume selling
                if isSelling then
                    Wait(5000)
                    TriggerEvent("flake_drugselling:spawnBuyer")
                end
                return
            end
        end

        -- Ped somehow died/deleted without knockout
        if not DoesEntityExist(ped) and isRobberyActive then
            isRobberyActive = false
            robberyPed      = nil
            stolenDrugItem  = nil
            stolenDrugCount = 0
        end
    end)
end

-- Player knocked out the robber
function knockoutRobber(ped)
    if not isRobberyActive or not ped or not DoesEntityExist(ped) then return end

    removeTargetFromEntity(ped)
    Config.hideTextUI()

    -- Knockout animation on ped
    ClearPedTasks(ped)
    SetPedToRagdoll(ped, 3000, 3000, 0, false, false, false)

    local playerPed = PlayerPedId()

    -- Play a quick punch anim
    RequestAnimDict("melee@unarmed@streamed_core_fps")
    while not HasAnimDictLoaded("melee@unarmed@streamed_core_fps") do
        Wait(0)
    end
    TaskPlayAnim(playerPed, "melee@unarmed@streamed_core_fps", "straight_right", 8.0, -8.0, 800, 0, 0, false, false, false)

    Wait(1200)

    -- Return stolen drugs to player via server
    TriggerServerEvent("flake_drugselling:server:returnStolenDrugs", stolenDrugItem, stolenDrugCount)
    Config.Notify(string.format("You knocked him out and got your %s x%d back!", stolenDrugItem, stolenDrugCount), "success")

    -- Clear robbery state
    isRobberyActive = false
    local savedPed  = robberyPed
    robberyPed      = nil
    stolenDrugItem  = nil
    stolenDrugCount = 0

    -- Delete the ped after a short delay (player sees it lying there)
    Citizen.SetTimeout(3000, function()
        hardDeletePed(savedPed)
    end)

    -- Continue selling
    if isSelling then
        Wait(5000)
        if not isSaleAnimating then
            TriggerEvent("flake_drugselling:spawnBuyer")
        end
    end
end

-- ============================================================
-- COMMANDS
-- ============================================================

if Config.Commands.enable then
    for _, command in ipairs(Config.Commands.startcommands) do
        RegisterCommand(command, function()
            TriggerEvent("flake_drugselling:startSelling")
        end)
        TriggerEvent('chat:addSuggestion', '/' .. command, 'Start selling', {})
    end
end

RegisterCommand(Config.Commands.stopcommand, function()
    if not isSelling then
        Config.Notify(Config.Notifications.notsellinganything, "error")
        return
    end
    resetSellState()
    Config.Notify(Config.Notifications.stoppedSelling, "inform")
end)
TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.stopcommand, 'Stop selling', {})

-- ============================================================
-- SPAWN BUYER
-- ============================================================

RegisterNetEvent('flake_drugselling:spawnBuyer', function()
    if buyerSpawned or not isSelling then return end

    local playerPed = PlayerPedId()

    if IsPedInAnyVehicle(playerPed) then
        Config.Notify(Config.Notifications.cannotSellFromVehicle, "error")
        resetSellState()
        return
    end

    local drugItem, drugCount = getDrugs()
    if not drugItem or drugCount == 0 then
        Config.Notify(Config.Notifications.nothingtosell, "error")
        resetSellState()
        return
    end

    local currentCoords = GetEntityCoords(playerPed)
    local maxDistance   = Config.Movement and Config.Movement.maxdistance or 100.0
    if #(currentCoords - startLocation) > maxDistance then
        Config.Notify(Config.Notifications.movedTooFar, "error")
        resetSellState()
        return
    end

    buyerSpawned = true

    local buyerData = {}
    buyerData.hash  = GetHashKey(Config.PedList[math.random(1, #Config.PedList)])

    RequestModel(buyerData.hash)
    while not HasModelLoaded(buyerData.hash) do Wait(0) end

    buyerData.offset = Config.Offsets[math.random(1, #Config.Offsets)]
    buyerData.coords = GetOffsetFromEntityInWorldCoords(playerPed, buyerData.offset.x, buyerData.offset.y, buyerData.offset.z or 0.0)

    local found, groundZ = GetGroundZFor_3dCoord(buyerData.coords.x, buyerData.coords.y, buyerData.coords.z, 0)
    if not found then
        Config.Notify(Config.Notifications.buyerScared, "error")
        buyerSpawned = false
        Wait(5000)
        if isSelling then TriggerEvent("flake_drugselling:spawnBuyer") end
        return
    end

    buyerData.ped = CreatePed(4, buyerData.hash, buyerData.coords.x, buyerData.coords.y, groundZ, 0.0, true, false)
    SetEntityAsMissionEntity(buyerData.ped, true, true)
    SetBlockingOfNonTemporaryEvents(buyerData.ped, true) -- ignore ambient events so ped doesn't flee on its own
    PlaceObjectOnGroundProperly(buyerData.ped)

    local playerCoords = GetEntityCoords(playerPed)
    TaskGoToCoordAnyMeans(buyerData.ped, playerCoords.x, playerCoords.y, playerCoords.z, 2.0, 0, 0, 786603, 3212836864)

    currentBuyerPed = buyerData.ped

    -- Follow-player thread
    Citizen.CreateThread(function()
        local lastUpdate = GetGameTimer()
        while buyerSpawned and DoesEntityExist(buyerData.ped) and currentBuyerPed == buyerData.ped do
            if GetGameTimer() - lastUpdate > 2000 then
                local pp = GetEntityCoords(PlayerPedId())
                TaskGoToCoordAnyMeans(buyerData.ped, pp.x, pp.y, pp.z, 2.0, 0, 0, 786603, 3212836864)
                lastUpdate = GetGameTimer()
            end
            Wait(500)
        end
    end)

    -- Target setup
    if not (Config.AutoSell and Config.AutoSell.enabled) and Config.System == "ox_target" then
        exports.ox_target:addLocalEntity(buyerData.ped, {
            {
                name        = "flake_drugselling:attemptSale",
                icon        = "fa-solid fa-sack-dollar",
                label       = "Sell to Customer",
                distance    = 2.5,
                canInteract = function(entity, distance)
                    return isSelling and distance < 2.5
                end,
                onSelect    = function()
                    markPedInteracted(buyerData.ped)
                end
            }
        })
    elseif not (Config.AutoSell and Config.AutoSell.enabled) and Config.System == "qb-target" then
        exports["qb-target"]:AddTargetEntity(buyerData.ped, {
            options = {
                {
                    icon   = "fa-solid fa-sack-dollar",
                    label  = "Sell to Customer",
                    action = function()
                        markPedInteracted(buyerData.ped)
                    end
                }
            },
            distance = 2.5
        })
    end

    local spawnTime   = GetGameTimer()

    -- Main interaction thread
    Citizen.CreateThread(function()
        local autoSellTimer = 0

        while true do
            -- Bail out if buyer was replaced or selling stopped
            if not buyerSpawned or currentBuyerPed ~= buyerData.ped then break end

            -- Dead buyer
            if IsPedDeadOrDying(buyerData.ped, true) then
                Config.Notify("The buyer was killed!", "error")
                removeTargetFromEntity(buyerData.ped)
                hardDeletePed(buyerData.ped)
                buyerSpawned    = false
                currentBuyerPed = nil
                Wait(3000)
                if isSelling then TriggerEvent("flake_drugselling:spawnBuyer") end
                return
            end

            local buyerCoords    = GetEntityCoords(buyerData.ped)
            local playerCoords   = GetEntityCoords(playerPed)
            local distanceToBuyer = #(buyerCoords - playerCoords)
            local distanceFromStart = #(playerCoords - startLocation)

            local maxDistance = Config.Movement and Config.Movement.maxdistance or 100.0
            if distanceFromStart > maxDistance then
                Config.Notify(Config.Notifications.movedTooFar, "error")
                removeTargetFromEntity(buyerData.ped)
                hardDeletePed(buyerData.ped)  -- immediate delete, no linger
                buyerSpawned    = false
                currentBuyerPed = nil
                resetSellState()
                return
            end

            local shouldInteract = false

            if Config.AutoSell and Config.AutoSell.enabled then
                if distanceToBuyer < 2.5 and not isSaleAnimating then
                    if autoSellTimer == 0 then
                        autoSellTimer = GetGameTimer()
                    elseif GetGameTimer() - autoSellTimer >= (Config.AutoSell.delay or 1500) then
                        shouldInteract = true
                        autoSellTimer  = 0
                    end
                else
                    autoSellTimer = 0
                end
            elseif Config.System == "textui" then
                if distanceToBuyer < 1.5 then
                    Config.showTextUI()
                    if IsControlJustPressed(1, 38) then
                        if distanceToBuyer < 2.5 then
                            shouldInteract = true
                        end
                    end
                else
                    Config.hideTextUI()
                end
            else
                if wasPedInteracted(buyerData.ped) then
                    shouldInteract = true
                end
            end

            if shouldInteract then
                Config.hideTextUI()
                removeTargetFromEntity(buyerData.ped)

                local dItem, dCount = getDrugs()
                if not dItem or dCount == 0 then
                    Config.Notify(Config.Notifications.nothingtosell, "error")
                    hardDeletePed(buyerData.ped)
                    buyerSpawned    = false
                    currentBuyerPed = nil
                    resetSellState()
                    return
                end

                -- Skill check
                if Config.SkillCheck.enabled then
                    if math.random(100) <= Config.SkillCheck.chance then
                        local success = lib.skillCheck(Config.SkillCheck.difficulties, Config.SkillCheck.keys)
                        if not success then
                            Config.Notify("You fumbled the sale...", "error")
                            hardDeletePed(buyerData.ped)
                            buyerSpawned    = false
                            currentBuyerPed = nil
                            Wait(5000)
                            if isSelling then TriggerEvent("flake_drugselling:spawnBuyer") end
                            return
                        end
                    end
                end

                -- Rejection check
                local drugConfig = Config.SellList[dItem]
                if math.random(100) <= drugConfig.reject then
                    Config.Notify(Config.Notifications.saleRejected, "error")

                    -- ── ROBBERY CHECK on rejection ──────────────────────
                    if shouldRobPlayer() and not isRobberyActive then
                        Wait(600)
                        -- Remove target before robbery so it can be re-added as knockout
                        removeTargetFromEntity(buyerData.ped)
                        buyerSpawned    = false
                        currentBuyerPed = nil
                        -- Tell server to remove the drug first
                        TriggerServerEvent("flake_drugselling:server:robPlayer", dItem, 1)
                        startRobbery(buyerData.ped, dItem, 1)
                    else
                        hardDeletePed(buyerData.ped)
                        buyerSpawned    = false
                        currentBuyerPed = nil
                        Wait(5000)
                        if isSelling then TriggerEvent("flake_drugselling:spawnBuyer") end
                    end
                else
                    -- Normal sale path — robbery can also happen after a successful handoff
                    if shouldRobPlayer() and not isRobberyActive then
                        -- Ped takes the drugs but doesn't pay, then bolts
                        sell_ped_robbery(buyerData.ped, dItem, dCount)
                    else
                        sell_ped(buyerData.ped, dItem, dCount)
                    end
                end
                return
            end

            -- Timeout (30s)
            if GetGameTimer() - spawnTime > 30000 then
                Config.hideTextUI()
                Config.Notify(Config.Notifications.buyerSpooked, "error")
                removeTargetFromEntity(buyerData.ped)
                hardDeletePed(buyerData.ped)
                buyerSpawned    = false
                currentBuyerPed = nil
                Wait(5000)
                if isSelling then TriggerEvent("flake_drugselling:spawnBuyer") end
                return
            end

            Wait(0)
        end
    end)
end)

-- ============================================================
-- START SELLING
-- ============================================================

RegisterNetEvent('flake_drugselling:startSelling', function()
    if isInSaleProcess then
        Config.Notify("You are already in the middle of a sale. Finish it first before starting another.", "error")
        return
    end

    local playerJob = nil
    if ESX then
        playerJob = ESX.GetPlayerData().job.name
    elseif QBCore then
        playerJob = QBCore.Functions.GetPlayerData().job.name
    end

    for _, job in pairs(Config.BlacklistedJobs) do
        if playerJob == job then
            Config.Notify(Config.Notifications.notjob, "error")
            return
        end
    end

    if Config.CopRequired > 0 then
        local copCount = getOnlineCopCount()
        if copCount < Config.CopRequired then
            Config.Notify(string.format("You need at least %d cops online to sell drugs.", Config.CopRequired), "error")
            return
        end
    end

    if Config.RestrictedZones.enabled then
        local playerCoords = GetEntityCoords(PlayerPedId())
        local inZone       = false
        for _, zone in ipairs(Config.RestrictedZones.zones) do
            if #(playerCoords - zone.coords) <= zone.radius then
                inZone = true
                break
            end
        end
        if not inZone then
            Config.Notify("You must be in a selling zone to sell drugs!", "error")
            return
        end
    end

    if not canStartNewSale then
        Config.Notify(Config.Notifications.alreadySelling, "error")
        return
    end

    if Config.SalesItem.enable then
        local hasPhone = lib.callback.await('flake_drugselling:hasPhoneItem', false)
        if not hasPhone then
            Config.Notify(Config.Notifications.nophone, "error")
            return
        end
    end

    local drugItem, drugCount = getDrugs()
    if not drugItem or drugCount == 0 then
        Config.Notify(Config.Notifications.nothingtosell, "error")
        return
    end

    canStartNewSale  = false
    isSelling        = true
    isInSaleProcess  = true
    startLocation    = GetEntityCoords(PlayerPedId())

    Config.Notify(Config.Notifications.startedSelling, "success")

    -- Phone animation thread
    Citizen.CreateThread(function()
        local playerPed  = PlayerPedId()
        local animDict   = "anim@heists@heist_safehouse_intro@phone"
        local animName   = "phone_intro"

        RequestAnimDict(animDict)
        while not HasAnimDictLoaded(animDict) do Wait(0) end

        local phoneModel = "prop_amb_phone"
        RequestModel(phoneModel)
        while not HasModelLoaded(phoneModel) do Wait(0) end

        local phoneObj = CreateObject(phoneModel, 0.0, 0.0, 0.0, true, true, true)
        AttachEntityToEntity(phoneObj, playerPed, GetPedBoneIndex(playerPed, 57005), 0.15, 0.07, -0.03, -275.0, 75.0, 0.0, true, true, false, true, 1, true)
        TaskPlayAnim(playerPed, animDict, animName, 8.0, 8.0, -1, 50, 0, false, false, false)

        Citizen.Wait(5000)

        DeleteEntity(phoneObj)
        ClearPedTasks(playerPed)

        if isSelling then TriggerEvent("flake_drugselling:spawnBuyer") end
    end)
end)

-- ============================================================
-- SELL PED (normal)
-- ============================================================

function sell_ped(buyerPed, drugItem, drugCount)
    isSaleAnimating = true
    local playerPed = PlayerPedId()

    TaskTurnPedToFaceEntity(playerPed, buyerPed, -1)
    TaskTurnPedToFaceEntity(buyerPed, playerPed, -1)

    RequestAnimDict("mp_common")
    while not HasAnimDictLoaded("mp_common") do Wait(0) end

    local drugConfig = Config.SellList[drugItem]
    local propModel  = (drugConfig and drugConfig.prop) or "hei_prop_pill_bag_01"

    RequestModel(propModel)
    while not HasModelLoaded(propModel) do Wait(0) end

    local drugProp = CreateObject(propModel, 0, 0, 0, true, true, true)
    AttachEntityToEntity(drugProp, playerPed, GetPedBoneIndex(playerPed, 28422), 0.05, 0.01, -0.05, 0.0, 180.0, 0.0, true, true, false, true, 1, true)

    TaskPlayAnim(playerPed, "mp_common", "givetake1_a", 8.0, -8.0, -1, 50, 0, false, false, false)
    Wait(1000)

    AttachEntityToEntity(drugProp, buyerPed, GetPedBoneIndex(buyerPed, 60309), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)

    RequestModel(1597489407)
    while not HasModelLoaded(1597489407) do Wait(0) end

    local moneyProp = CreateObject(1597489407, 0, 0, 0, true, true, true)
    AttachEntityToEntity(moneyProp, buyerPed, GetPedBoneIndex(buyerPed, 60309), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)

    TaskPlayAnim(buyerPed, "mp_common", "givetake1_a", 8.0, -8.0, -1, 50, 0, false, false, false)
    Wait(500)

    AttachEntityToEntity(moneyProp, playerPed, GetPedBoneIndex(playerPed, 28422), 0.05, 0.01, -0.05, 0.0, 180.0, 0.0, true, true, false, true, 1, true)
    Wait(500)

    ClearPedTasks(playerPed)
    ClearPedTasks(buyerPed)

    DeleteEntity(moneyProp)
    DeleteEntity(drugProp)

    Wait(500)

    TriggerServerEvent("flake_drugselling:server:sellDrug", drugItem, drugCount)

    if Config.SaleAlerts.enable then
        if math.random(100) <= Config.SaleAlerts.chance then
            Config.Alerts(GetEntityCoords(playerPed))
        end
    end

    -- Guaranteed cleanup
    removeTargetFromEntity(buyerPed)
    buyerSpawned    = false
    currentBuyerPed = nil
    hardDeletePed(buyerPed)   -- instant hard delete after sale completes

    if isSelling then
        Wait(5000)
        isSaleAnimating = false
        TriggerEvent("flake_drugselling:spawnBuyer")
    else
        isSaleAnimating = false
        canStartNewSale = true
    end
end

-- ============================================================
-- SELL PED ROBBERY VARIANT
-- NPC takes the drug item then bolts without paying
-- ============================================================

function sell_ped_robbery(buyerPed, drugItem, drugCount)
    isSaleAnimating = true
    local playerPed = PlayerPedId()

    TaskTurnPedToFaceEntity(playerPed, buyerPed, -1)
    TaskTurnPedToFaceEntity(buyerPed, playerPed, -1)

    RequestAnimDict("mp_common")
    while not HasAnimDictLoaded("mp_common") do Wait(0) end

    local drugConfig = Config.SellList[drugItem]
    local propModel  = (drugConfig and drugConfig.prop) or "hei_prop_pill_bag_01"

    RequestModel(propModel)
    while not HasModelLoaded(propModel) do Wait(0) end

    local drugProp = CreateObject(propModel, 0, 0, 0, true, true, true)
    AttachEntityToEntity(drugProp, playerPed, GetPedBoneIndex(playerPed, 28422), 0.05, 0.01, -0.05, 0.0, 180.0, 0.0, true, true, false, true, 1, true)

    TaskPlayAnim(playerPed, "mp_common", "givetake1_a", 8.0, -8.0, -1, 50, 0, false, false, false)
    Wait(800)

    -- Ped snatches the item
    AttachEntityToEntity(drugProp, buyerPed, GetPedBoneIndex(buyerPed, 60309), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    Wait(400)

    ClearPedTasks(playerPed)
    ClearPedTasks(buyerPed)

    -- Clean up prop — it's gone with the runner
    Citizen.SetTimeout(2000, function() if DoesEntityExist(drugProp) then DeleteEntity(drugProp) end end)

    isSaleAnimating = false
    buyerSpawned    = false
    currentBuyerPed = nil

    -- Tell server to strip 1 unit (the stolen one)
    TriggerServerEvent("flake_drugselling:server:robPlayer", drugItem, 1)

    startRobbery(buyerPed, drugItem, 1)
end

-- ============================================================
-- RESET
-- ============================================================

function resetSellState()
    isSelling       = false
    canStartNewSale = true
    isInSaleProcess = false
    buyerSpawned    = false
    isSaleAnimating = false
    interactedPeds  = {}

    if currentBuyerPed then
        if DoesEntityExist(currentBuyerPed) then
            removeTargetFromEntity(currentBuyerPed)
            hardDeletePed(currentBuyerPed)
        end
        currentBuyerPed = nil
    end

    -- Cancel any active robbery too
    if robberyPed then
        if DoesEntityExist(robberyPed) then
            removeTargetFromEntity(robberyPed)
            hardDeletePed(robberyPed)
        end
        robberyPed      = nil
        isRobberyActive = false
        stolenDrugItem  = nil
        stolenDrugCount = 0
    end
end

-- ============================================================
-- PHONE ITEM EXPORT
-- ============================================================

exports('usePhone', function(data, slot)
    local options = {}

    if isSelling or isInSaleProcess then
        options[#options + 1] = {
            title       = 'Stop Selling',
            description = 'End your current drug selling session',
            icon        = 'ban',
            onSelect    = function()
                resetSellState()
                Config.Notify(Config.Notifications.stoppedSelling, "inform")
            end
        }
    else
        options[#options + 1] = {
            title       = 'Start Selling',
            description = 'Begin selling drugs to customers',
            icon        = 'sack-dollar',
            onSelect    = function()
                TriggerEvent('flake_drugselling:startSelling')
            end
        }
    end

    lib.registerContext({ id = 'drugselling_phone_menu', title = 'Drug Dealing', options = options })
    lib.showContext('drugselling_phone_menu')
end)

-- ============================================================
-- GET DRUGS
-- ============================================================

function getDrugs()
    local drugItem, drugCount = lib.callback.await("flake_drugselling:getallavailableDrugs", false)
    if drugItem and drugCount then return drugItem, drugCount end
    return nil, 0
end

-- ============================================================
-- JOB / COP HELPERS
-- ============================================================

function ClientJobCheck()
    if ESX then
        local job = ESX.GetPlayerData().job
        if job then
            for _, policeJob in ipairs(Config.PoliceJobs) do
                if job.name == policeJob then return true end
            end
        end
        return false
    elseif QBCore then
        local pd = QBCore.Functions.GetPlayerData()
        if pd and pd.job then
            for _, policeJob in ipairs(Config.PoliceJobs) do
                if pd.job.name == policeJob then return true end
            end
        end
        return false
    end
    return false
end

function getOnlineCopCount()
    local count   = 0
    local players = GetActivePlayers()
    for _, player in ipairs(players) do
        if ClientJobCheck() then count = count + 1 end
    end
    return count
end

-- ============================================================
-- RANK HELPERS (local copy to avoid cross-file dependency)
-- ============================================================

local function calculateProgressLocal(current, min, max)
    if max <= min then return 100 end
    return math.floor(((current - min) / (max - min)) * 100)
end

local function getRankInfoLocal(points)
    local currentRank      = 0
    local currentRankPoints = 0
    local nextRankPoints   = Config.Ranks[1].points
    local rankLabel        = "Beginner"

    for i, rank in ipairs(Config.Ranks) do
        if points >= rank.points then
            currentRank       = i
            currentRankPoints = rank.points
            rankLabel         = rank.label
        else
            break
        end
    end

    if currentRank == 0 then
        nextRankPoints = Config.Ranks[1].points
    elseif currentRank < #Config.Ranks then
        nextRankPoints = Config.Ranks[currentRank + 1].points
    else
        nextRankPoints = currentRankPoints + 1
    end

    return {
        currentRank = currentRank == 0 and 1 or currentRank,
        nextRank    = currentRank == 0 and 1 or math.min(currentRank + 1, #Config.Ranks),
        rankLabel   = rankLabel,
        progress    = calculateProgressLocal(points, currentRankPoints, nextRankPoints)
    }
end

-- ============================================================
-- RANK COMMAND
-- ============================================================

local rankCommandCooldown = true

RegisterCommand(Config.DealerRank, function()
    if rankCommandCooldown then
        local levelData = lib.callback.await("flake_drugselling:getLevel", false)
        if levelData and levelData.levelpoints then
            local points   = tonumber(levelData.levelpoints)
            local rankInfo = getRankInfoLocal(points)

            ShowRankProgressBar(points, 0)

            if rankInfo.currentRank < #Config.Ranks then
                local nextRankLabel = Config.Ranks[rankInfo.nextRank].label
                Config.Notify(string.format("Rank: %s (%d%% to %s)", rankInfo.rankLabel, rankInfo.progress, nextRankLabel), "inform")
            else
                Config.Notify(string.format("Rank: %s (Max Rank)", rankInfo.rankLabel), "inform")
            end

            Citizen.SetTimeout(5000, function()
                SendNUIMessage({ action = "hideRankBar" })
            end)
        else
            Config.Notify("Failed to retrieve player level.", "error")
        end

        rankCommandCooldown = false
        SetTimeout(2500, function() rankCommandCooldown = true end)
    else
        Config.Notify("Please wait a little before doing this again!", "error")
        SetTimeout(2500, function() rankCommandCooldown = true end)
    end
end)