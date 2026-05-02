-- Territory Client Logic

-- Client-side dedup: track the territory ID we last notified for
local clientCurrentTerritoryId = nil

-- All territories fetched from server (for visual rendering)
local allTerritories  = {}
local territoryBlips  = {}

-- ============================================================
-- ZONE DETECTION — send coords to server every 1 s
-- ============================================================
CreateThread(function()
    while true do
        Wait(1000)
        local coords = GetEntityCoords(PlayerPedId())
        TriggerServerEvent('faction:checkTerritory', coords)
    end
end)

-- ============================================================
-- TERRITORY DATA FETCH — request on spawn, refresh on change
-- ============================================================
CreateThread(function()
    while ESX.GetPlayerData().identifier == nil do
        Wait(100)
    end
    Wait(3000)
    TriggerServerEvent('faction:getAllTerritories')
end)

-- ============================================================
-- RECEIVE ALL TERRITORIES + BUILD BLIPS
-- ============================================================
local function BuildTerritoryBlips(territories)
    -- Remove old blips
    for _, blip in ipairs(territoryBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    territoryBlips = {}

    for _, terr in ipairs(territories) do
        if terr.type == 'turf' then
            -- Radius circle blip (filled area)
            local areaBlip = AddBlipForRadius(terr.x, terr.y, 0.0, (terr.radius or 50.0))
            SetBlipColour(areaBlip, 1) -- Red
            SetBlipAlpha(areaBlip, 64)
            table.insert(territoryBlips, areaBlip)

            -- Centre label blip
            local pinBlip = AddBlipForCoord(terr.x, terr.y, terr.z)
            SetBlipSprite(pinBlip, 84)  -- territory marker sprite
            SetBlipColour(pinBlip, 1)   -- Red
            SetBlipScale(pinBlip, 0.75)
            SetBlipAsShortRange(pinBlip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString((terr.faction_label or 'Unknown') .. ': ' .. (terr.name or 'Territory'))
            EndTextCommandSetBlipName(pinBlip)
            table.insert(territoryBlips, pinBlip)

        elseif terr.type == 'stash' then
            local pinBlip = AddBlipForCoord(terr.x, terr.y, terr.z)
            SetBlipSprite(pinBlip, 191) -- briefcase/stash sprite
            SetBlipColour(pinBlip, 5)   -- Yellow
            SetBlipScale(pinBlip, 0.65)
            SetBlipAsShortRange(pinBlip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString('Stash: ' .. (terr.name or 'Stash'))
            EndTextCommandSetBlipName(pinBlip)
            table.insert(territoryBlips, pinBlip)
        end
    end
end

RegisterNetEvent('faction:receiveAllTerritories', function(territories)
    allTerritories = territories or {}
    BuildTerritoryBlips(allTerritories)
end)

-- Invalidate and refresh when territory changes (server broadcasts this)
RegisterNetEvent('faction:refreshTerritoryVisuals', function()
    TriggerServerEvent('faction:getAllTerritories')
end)

-- ============================================================
-- DRAW MARKERS — cylinder at each nearby turf zone
-- ============================================================
CreateThread(function()
    while true do
        local ped       = PlayerPedId()
        local pedCoords = GetEntityCoords(ped)
        local anyNear   = false

        for _, terr in ipairs(allTerritories) do
            if terr.type == 'turf' then
                local r    = (terr.radius or 50.0)
                local dist = #(pedCoords - vector3(terr.x, terr.y, terr.z))

                if dist < r + 120.0 then
                    anyNear = true
                    -- Flat cylinder outline on the ground
                    DrawMarker(
                        1,                          -- TYPE_DASHED_CYLINDER
                        terr.x, terr.y, terr.z - 1.0,
                        0.0, 0.0, 0.0,              -- direction
                        0.0, 0.0, 0.0,              -- rotation
                        r * 2.0, r * 2.0, 1.5,      -- scale (diameter x2, short height)
                        200, 20, 20, 80,             -- RGBA — semi-transparent red
                        false, false, 2, false, nil, nil, false
                    )
                end
            end
        end

        if anyNear then Wait(0) else Wait(500) end
    end
end)

-- ============================================================
-- ENTER / EXIT NOTIFICATIONS
-- ============================================================
RegisterNetEvent('faction:enterTerritory', function(data)
    if not data then return end
    local newId = data.id or (data.name .. ':' .. (data.faction_label or ''))
    if clientCurrentTerritoryId == newId then return end
    clientCurrentTerritoryId = newId
    lib.notify({
        type        = 'info',
        title       = (data.faction_label or 'Unknown') .. ' Territory',
        description = string.format('Entering %s (%s)', data.name or 'Unknown', data.type or 'zone'),
        duration    = 5000
    })
end)

RegisterNetEvent('faction:exitTerritory', function()
    if clientCurrentTerritoryId == nil then return end
    clientCurrentTerritoryId = nil
    lib.notify({
        type        = 'info',
        description = 'You have left faction territory.',
        duration    = 3000
    })
end)
