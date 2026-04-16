-- Territory Client Logic

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
    lib.notify({
        type        = 'info',
        title       = (data.faction_label or 'Unknown') .. ' Territory',
        description = string.format('Entering %s (%s)', data.name or 'Unknown', data.type or 'zone'),
        duration    = 5000
    })
end)

-- Notified by server when leaving a faction's territory zone
RegisterNetEvent('faction:exitTerritory', function()
    lib.notify({
        type        = 'info',
        description = 'You have left faction territory.',
        duration    = 3000
    })
end)
