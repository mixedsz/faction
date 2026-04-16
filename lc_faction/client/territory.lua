-- Territory Client Logic

-- Track player location for territory claiming
CreateThread(function()
    while true do
        Wait(5000) -- Check every 5 seconds
        
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        
        -- Check if player is in claimed territory
        TriggerServerEvent('faction:checkTerritory', coords)
    end
end)
