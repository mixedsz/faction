-- Territory Client Logic

-- Client-side dedup: track the territory ID we last notified for
local clientCurrentTerritoryId = nil

-- Send player coordinates to server every 5 seconds for zone detection
CreateThread(function()
    while true do
        Wait(5000)
        local coords = GetEntityCoords(PlayerPedId())
        TriggerServerEvent('faction:checkTerritory', coords)
    end
end)

-- Notified by server when entering a faction's territory zone
RegisterNetEvent('faction:enterTerritory', function(data)
    if not data then return end
    -- Deduplicate: skip if we already showed this enter notification
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

-- Notified by server when leaving a faction's territory zone
RegisterNetEvent('faction:exitTerritory', function()
    -- Deduplicate: skip if we're already outside
    if clientCurrentTerritoryId == nil then return end
    clientCurrentTerritoryId = nil
    lib.notify({
        type        = 'info',
        description = 'You have left faction territory.',
        duration    = 3000
    })
end)
