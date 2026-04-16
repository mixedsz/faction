-- Weapon Tracking Client Logic

local lastWeapon = nil
local lastShotTime = 0

-- Check if player is in an altercation (shooting at another player)
local function IsInAltercation()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    
    -- Check for nearby players (potential targets)
    local players = GetActivePlayers()
    for _, playerId in ipairs(players) do
        local targetPed = GetPlayerPed(playerId)
        if targetPed ~= ped and DoesEntityExist(targetPed) then
            local targetCoords = GetEntityCoords(targetPed)
            local distance = #(coords - targetCoords)
            
            -- If within 100 meters and player is shooting, likely an altercation
            if distance < 100.0 then
                -- Check if we're aiming at this player or they're in combat
                if IsPedInCombat(ped, targetPed) or IsPedInCombat(targetPed, ped) then
                    return true
                end
            end
        end
    end
    
    return false
end

-- Track weapon usage
CreateThread(function()
    while true do
        Wait(100)
        
        local ped = PlayerPedId()
        local weaponHash = GetSelectedPedWeapon(ped)
        
        if weaponHash ~= GetHashKey('WEAPON_UNARMED') then
            if weaponHash ~= lastWeapon then
                lastWeapon = weaponHash
            end
            
            -- Detect shooting
            if IsPedShooting(ped) then
                local currentTime = GetGameTimer()
                if currentTime - lastShotTime > 1000 then -- Throttle to once per second
                    lastShotTime = currentTime
                    local coords = GetEntityCoords(ped)
                    local isAltercation = IsInAltercation()
                    TriggerServerEvent('faction:logWeaponUsage', weaponHash, coords, isAltercation)
                end
            end
        else
            lastWeapon = nil
        end
    end
end)

-- Note: Shootout validation is handled server-side on player death event
-- This ensures accurate validation without client-side exploits