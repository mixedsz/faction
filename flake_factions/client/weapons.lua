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

-- GTA weapon hashes that count as valid weapon kills (guns, knives, melee).
-- Everything else (vehicles, fire, drowning, falling, etc.) is blocked.
local VALID_WEAPON_HASHES = {
    -- Melee / knives
    [GetHashKey('WEAPON_UNARMED')]              = false,
    [GetHashKey('WEAPON_KNIFE')]                = true,
    [GetHashKey('WEAPON_NIGHTSTICK')]           = true,
    [GetHashKey('WEAPON_HAMMER')]               = true,
    [GetHashKey('WEAPON_BAT')]                  = true,
    [GetHashKey('WEAPON_GOLFCLUB')]             = true,
    [GetHashKey('WEAPON_CROWBAR')]              = true,
    [GetHashKey('WEAPON_BOTTLE')]               = true,
    [GetHashKey('WEAPON_DAGGER')]               = true,
    [GetHashKey('WEAPON_HATCHET')]              = true,
    [GetHashKey('WEAPON_KNUCKLE')]              = true,
    [GetHashKey('WEAPON_MACHETE')]              = true,
    [GetHashKey('WEAPON_FLASHLIGHT')]           = true,
    [GetHashKey('WEAPON_SWITCHBLADE')]          = true,
    [GetHashKey('WEAPON_POOLCUE')]              = true,
    [GetHashKey('WEAPON_WRENCH')]               = true,
    [GetHashKey('WEAPON_BATTLEAXE')]            = true,
    -- Pistols
    [GetHashKey('WEAPON_PISTOL')]               = true,
    [GetHashKey('WEAPON_PISTOL_MK2')]           = true,
    [GetHashKey('WEAPON_COMBATPISTOL')]         = true,
    [GetHashKey('WEAPON_APPISTOL')]             = true,
    [GetHashKey('WEAPON_PISTOL50')]             = true,
    [GetHashKey('WEAPON_SNSPISTOL')]            = true,
    [GetHashKey('WEAPON_SNSPISTOL_MK2')]        = true,
    [GetHashKey('WEAPON_HEAVYPISTOL')]          = true,
    [GetHashKey('WEAPON_VINTAGEPISTOL')]        = true,
    [GetHashKey('WEAPON_MARKSMANPISTOL')]       = true,
    [GetHashKey('WEAPON_REVOLVER')]             = true,
    [GetHashKey('WEAPON_REVOLVER_MK2')]         = true,
    [GetHashKey('WEAPON_DOUBLEACTION')]         = true,
    [GetHashKey('WEAPON_RAYPISTOL')]            = true,
    [GetHashKey('WEAPON_CERAMICPISTOL')]        = true,
    [GetHashKey('WEAPON_NAVYREVOLVER')]         = true,
    [GetHashKey('WEAPON_GADGETPISTOL')]         = true,
    [GetHashKey('WEAPON_PISTOLXM3')]            = true,
    -- SMGs
    [GetHashKey('WEAPON_MICROSMG')]             = true,
    [GetHashKey('WEAPON_SMG')]                  = true,
    [GetHashKey('WEAPON_SMG_MK2')]              = true,
    [GetHashKey('WEAPON_ASSAULTSMG')]           = true,
    [GetHashKey('WEAPON_COMBATPDW')]            = true,
    [GetHashKey('WEAPON_MACHINEPISTOL')]        = true,
    [GetHashKey('WEAPON_MINISMG')]              = true,
    [GetHashKey('WEAPON_RAYCARBINE')]           = true,
    [GetHashKey('WEAPON_TECPISTOL')]            = true,
    -- Shotguns
    [GetHashKey('WEAPON_PUMPSHOTGUN')]          = true,
    [GetHashKey('WEAPON_PUMPSHOTGUN_MK2')]      = true,
    [GetHashKey('WEAPON_SAWNOFFSHOTGUN')]       = true,
    [GetHashKey('WEAPON_ASSAULTSHOTGUN')]       = true,
    [GetHashKey('WEAPON_BULLPUPSHOTGUN')]       = true,
    [GetHashKey('WEAPON_MUSKET')]               = true,
    [GetHashKey('WEAPON_HEAVYSHOTGUN')]         = true,
    [GetHashKey('WEAPON_DBSHOTGUN')]            = true,
    [GetHashKey('WEAPON_AUTOSHOTGUN')]          = true,
    [GetHashKey('WEAPON_COMBATSHOTGUN')]        = true,
    -- Rifles
    [GetHashKey('WEAPON_ASSAULTRIFLE')]         = true,
    [GetHashKey('WEAPON_ASSAULTRIFLE_MK2')]     = true,
    [GetHashKey('WEAPON_CARBINERIFLE')]         = true,
    [GetHashKey('WEAPON_CARBINERIFLE_MK2')]     = true,
    [GetHashKey('WEAPON_ADVANCEDRIFLE')]        = true,
    [GetHashKey('WEAPON_SPECIALCARBINE')]       = true,
    [GetHashKey('WEAPON_SPECIALCARBINE_MK2')]   = true,
    [GetHashKey('WEAPON_BULLPUPRIFLE')]         = true,
    [GetHashKey('WEAPON_BULLPUPRIFLE_MK2')]     = true,
    [GetHashKey('WEAPON_COMPACTRIFLE')]         = true,
    [GetHashKey('WEAPON_MILITARYRIFLE')]        = true,
    [GetHashKey('WEAPON_HEAVYRIFLE')]           = true,
    [GetHashKey('WEAPON_TACTICALRIFLE')]        = true,
    -- LMGs / Heavy
    [GetHashKey('WEAPON_MG')]                   = true,
    [GetHashKey('WEAPON_COMBATMG')]             = true,
    [GetHashKey('WEAPON_COMBATMG_MK2')]         = true,
    [GetHashKey('WEAPON_GUSENBERG')]            = true,
    -- Snipers
    [GetHashKey('WEAPON_SNIPERRIFLE')]          = true,
    [GetHashKey('WEAPON_HEAVYSNIPER')]          = true,
    [GetHashKey('WEAPON_HEAVYSNIPER_MK2')]      = true,
    [GetHashKey('WEAPON_MARKSMANRIFLE')]        = true,
    [GetHashKey('WEAPON_MARKSMANRIFLE_MK2')]    = true,
    [GetHashKey('WEAPON_PRECISIONRIFLE')]       = true,
    -- Explosives / launchers
    [GetHashKey('WEAPON_RPG')]                  = true,
    [GetHashKey('WEAPON_GRENADELAUNCHER')]      = true,
    [GetHashKey('WEAPON_GRENADELAUNCHER_SMOKE')] = true,
    [GetHashKey('WEAPON_MINIGUN')]              = true,
    [GetHashKey('WEAPON_FIREWORK')]             = true,
    [GetHashKey('WEAPON_RAILGUN')]              = true,
    [GetHashKey('WEAPON_HOMINGLAUNCHER')]       = true,
    [GetHashKey('WEAPON_COMPACTLAUNCHER')]      = true,
    [GetHashKey('WEAPON_RAYMINIGUN')]           = true,
    [GetHashKey('WEAPON_EMPLAUNCHER')]          = true,
    [GetHashKey('WEAPON_RAILGUNXM3')]           = true,
}

local function IsValidWeaponKill(weaponHash)
    if not weaponHash or weaponHash == 0 then return false end
    local result = VALID_WEAPON_HASHES[weaponHash]
    if result == true then return true end
    if result == false then return false end
    -- Unknown hash: block it (whitelist approach)
    return false
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
