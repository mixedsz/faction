-- Weapon Tracking Client Logic

local lastWeapon = nil
local lastShotTime = 0

-- Check if player is in an altercation (shooting at another player)
local function IsInAltercation()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    local players = GetActivePlayers()
    for _, playerId in ipairs(players) do
        local targetPed = GetPlayerPed(playerId)
        if targetPed ~= ped and DoesEntityExist(targetPed) then
            local targetCoords = GetEntityCoords(targetPed)
            local distance = #(coords - targetCoords)
            if distance < 100.0 then
                if IsPedInCombat(ped, targetPed) or IsPedInCombat(targetPed, ped) then
                    return true
                end
            end
        end
    end

    return false
end

-- Track weapon usage and report shots to server
CreateThread(function()
    while true do
        Wait(100)

        local ped = PlayerPedId()
        local weaponHash = GetSelectedPedWeapon(ped)

        if weaponHash ~= GetHashKey('WEAPON_UNARMED') then
            if weaponHash ~= lastWeapon then
                lastWeapon = weaponHash
            end

            if IsPedShooting(ped) then
                local currentTime = GetGameTimer()
                if currentTime - lastShotTime > 1000 then
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

-- ============================================================
-- GUN DROP RECEIVER
-- Delivers registered faction weapons to the player's ped via GTA native.
-- The server sends the list of faction_weapons rows (weapon_hash + serial_number).
-- ============================================================
RegisterNetEvent('faction:receiveGunDrop', function(weapons)
    if not weapons or #weapons == 0 then
        lib.notify({ type = 'warning', description = 'Gun drop received but no weapons found. Contact an admin.' })
        return
    end

    local ped   = PlayerPedId()
    local count = 0

    for _, w in ipairs(weapons) do
        local hash = nil

        if w.weapon_hash and w.weapon_hash ~= '' then
            local numHash = tonumber(w.weapon_hash)
            if numHash then
                -- Stored as a raw GTA hash integer
                hash = numHash
            else
                -- Stored as a weapon name string like "WEAPON_AK47" or "weapon_ak47"
                hash = GetHashKey(tostring(w.weapon_hash):upper())
            end
        end

        if hash and hash ~= 0 then
            GiveWeaponToPed(ped, hash, 250, false, false)
            count = count + 1
        end
    end

    if count > 0 then
        lib.notify({
            type        = 'success',
            title       = 'Gun Drop',
            description = string.format('%d weapon(s) added to your inventory.', count),
            duration    = 8000
        })
    else
        lib.notify({
            type        = 'warning',
            description = 'Gun drop received but no valid weapon hashes were found. Ensure weapons are registered with their weapon hash.'
        })
    end
end)

-- ============================================================
-- FACTION NOTIFICATION BROADCAST
-- Used by server to notify all online faction members of events
-- (e.g. gun drop collected, weapons logged, etc.)
-- ============================================================
RegisterNetEvent('faction:receiveNotification', function(data)
    if not data then return end
    SendNUIMessage({
        action      = 'showNotification',
        type        = data.type or 'info',
        title       = data.title or nil,
        description = data.description or ''
    })
end)
