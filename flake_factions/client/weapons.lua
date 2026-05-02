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

                    -- Resolve weapon item name from ox_inventory so the server can
                    -- match by item name / serial instead of raw numeric hash
                    local weaponItemName = nil
                    if exports.ox_inventory then
                        local ok, items = pcall(function()
                            return exports.ox_inventory:GetPlayerItems()
                        end)
                        if ok and type(items) == 'table' then
                            for _, item in ipairs(items) do
                                if item and item.name and item.name:sub(1,7) == 'weapon_' then
                                    -- Match by checking if this item is the equipped weapon
                                    local h = GetHashKey(item.name:upper())
                                    if h == weaponHash then
                                        weaponItemName = item.name:lower()
                                        break
                                    end
                                end
                            end
                        end
                    end

                    TriggerServerEvent('faction:logWeaponUsage', weaponHash, coords, isAltercation, weaponItemName)
                end
            end
        else
            lastWeapon = nil
        end
    end
end)

-- ============================================================
-- KILL / DEATH TRACKING FOR REPUTATION
-- ============================================================

-- Track when the local player kills another player (enemy faction)
AddEventHandler('gameEventTriggered', function(name, args)
    if name == 'CEventNetworkEntityDamage' then
        local victim    = args[1]
        local attacker  = args[2]
        local isDead    = args[4]

        if not isDead then return end

        local localPed = PlayerPedId()

        -- We killed someone
        if attacker == localPed and victim ~= localPed then
            if IsEntityAPlayer(victim) then
                local victimServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(victim))
                TriggerServerEvent('faction:playerKilledPlayer', victimServerId)
            end
        end

        -- We died (killed by someone or something)
        if victim == localPed then
            TriggerServerEvent('faction:playerDied')
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
    if nuiOpen then
        SendNUIMessage({
            action      = 'phoneNotify',
            notifType   = data.type or 'info',
            title       = data.title or '',
            description = data.description or '',
        })
    else
        lib.notify({
            type        = data.type or 'info',
            title       = data.title or nil,
            description = data.description or '',
            duration    = data.duration or 5000
        })
    end
end)
