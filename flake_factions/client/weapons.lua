-- Weapon Tracking Client Logic

local lastWeapon   = nil
local lastShotTime = 0

local function IsInAltercation()
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    for _, playerId in ipairs(GetActivePlayers()) do
        local targetPed = GetPlayerPed(playerId)
        if targetPed ~= ped and DoesEntityExist(targetPed) then
            if #(coords - GetEntityCoords(targetPed)) < 100.0 then
                return true
            end
        end
    end
    return false
end

-- Weapon usage logging thread
CreateThread(function()
    while true do
        Wait(100)
        local ped        = PlayerPedId()
        local weaponHash = GetSelectedPedWeapon(ped)

        if weaponHash ~= GetHashKey('WEAPON_UNARMED') then
            if weaponHash ~= lastWeapon then lastWeapon = weaponHash end

            if IsPedShooting(ped) then
                local now = GetGameTimer()
                if now - lastShotTime > 1000 then
                    lastShotTime = now
                    local coords        = GetEntityCoords(ped)
                    local isAltercation = IsInAltercation()

                    local weaponItemName = nil
                    if exports.ox_inventory then
                        local ok, items = pcall(function() return exports.ox_inventory:GetPlayerItems() end)
                        if ok and type(items) == 'table' then
                            for _, item in ipairs(items) do
                                if item and item.name and item.name:sub(1, 7) == 'weapon_' then
                                    if GetHashKey(item.name:upper()) == weaponHash then
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
-- KILL / DEATH TRACKING — HEALTH WATCHER
-- ============================================================
-- Avoids ALL CEventNetworkEntityDamage arg-layout ambiguity.
-- IsEntityDead(PlayerPedId()) is 100% reliable on the local client.
-- GetPedSourceOfDeath gives us the killer entity; the killer is still
-- alive so GetActivePlayers() always finds them.
-- ============================================================

-- Hashes that represent non-weapon deaths (vehicles, environment, etc.)
-- GetDisplayNameFromWeapon returns 'WT_INVALID' for these, but we also
-- explicitly block the most common ones as a belt-and-suspenders guard.
local BLOCKED_DAMAGE_HASHES = {
    [GetHashKey('WEAPON_RAMMED_BY_CAR')]          = true,
    [GetHashKey('WEAPON_RUN_OVER_BY_CAR')]         = true,
    [GetHashKey('WEAPON_FALL')]                    = true,
    [GetHashKey('WEAPON_DROWNING')]                = true,
    [GetHashKey('WEAPON_DROWNING_IN_VEHICLE')]     = true,
    [GetHashKey('WEAPON_ELECTRIC_FENCE')]          = true,
    [GetHashKey('WEAPON_HIT_BY_WATER_CANNON')]     = true,
    [GetHashKey('WEAPON_EXHAUSTION')]              = true,
    [GetHashKey('WEAPON_EXPLOSION')]               = false,  -- explosives ARE weapons
}

local function IsValidWeaponKill(weaponHash)
    local unarmedHash = GetHashKey('WEAPON_UNARMED')

    -- Block fists
    if weaponHash == unarmedHash or weaponHash == 0 then return false end

    -- Block known vehicle / environment hashes
    if BLOCKED_DAMAGE_HASHES[weaponHash] == true then return false end

    -- Primary filter: GetDisplayNameFromWeapon returns 'WT_INVALID' for
    -- anything that is not a real GTA weapon (vehicle kills, fire, explosions
    -- from the environment, etc.).  Guns, SMGs, rifles, shotguns, snipers,
    -- heavy weapons, melee and knives all return a real label.
    local label = GetDisplayNameFromWeapon(weaponHash)
    if not label or label == '' or label == 'WT_INVALID' then return false end

    return true
end

local wasDead = false

CreateThread(function()
    while true do
        Wait(100)

        local ped = PlayerPedId()

        if not IsEntityDead(ped) then
            wasDead = false
        elseif not wasDead then
            wasDead = true

            -- Give GTA ~200 ms to populate source / cause-of-death
            Wait(200)

            local killerEntity = GetPedSourceOfDeath(ped)
            local weaponHash   = GetPedCauseOfDeath(ped)

            -- Death rep loss (server handles cooldown + faction check)
            if IsValidWeaponKill(weaponHash) then
                TriggerServerEvent('faction:playerDied')
            end

            -- Killed by another player with a real weapon → award rep to killer
            if killerEntity and killerEntity ~= 0
                and IsPedAPlayer(killerEntity)
                and killerEntity ~= ped
                and IsValidWeaponKill(weaponHash)
            then
                -- Killer is alive → reliably in GetActivePlayers()
                local killerServerId = nil
                for _, pid in ipairs(GetActivePlayers()) do
                    if GetPlayerPed(pid) == killerEntity then
                        killerServerId = GetPlayerServerId(pid)
                        break
                    end
                end

                if killerServerId and killerServerId > 0 then
                    TriggerServerEvent('faction:victimReportsKiller', killerServerId, weaponHash)
                end
            end
        end
    end
end)

-- ============================================================
-- GUN DROP RECEIVER
-- ============================================================
RegisterNetEvent('faction:receiveGunDrop', function(weapons)
    if not weapons or #weapons == 0 then
        lib.notify({ type = 'warning', description = 'Gun drop received but no weapons found.' })
        return
    end

    local ped   = PlayerPedId()
    local count = 0

    for _, w in ipairs(weapons) do
        local hash = nil
        if w.weapon_hash and w.weapon_hash ~= '' then
            local numHash = tonumber(w.weapon_hash)
            if numHash then
                hash = numHash
            else
                hash = GetHashKey(tostring(w.weapon_hash):upper())
            end
        end
        if hash and hash ~= 0 then
            GiveWeaponToPed(ped, hash, 250, false, false)
            count = count + 1
        end
    end

    if count > 0 then
        lib.notify({ type = 'success', title = 'Gun Drop',
            description = string.format('%d weapon(s) added to your inventory.', count), duration = 8000 })
    else
        lib.notify({ type = 'warning', description = 'Gun drop: no valid weapon hashes found.' })
    end
end)

-- ============================================================
-- FACTION NOTIFICATION BROADCAST
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
            duration    = data.duration or 5000,
        })
    end
end)
