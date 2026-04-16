-- Weapon tracking, logging, violation enforcement, and gun drop system

-- Possession scan cache: identifier -> { lastScan = timestamp, weapons = {} }
local possessionCache = {}

-- Violation cooldown cache: identifier -> last violation log timestamp (os.time)
local violationTimestamps = {}

-- Helper: get current weapon inventory for a player from ox_inventory
local function GetPlayerWeaponInventory(identifier)
    local items = exports.ox_inventory and exports.ox_inventory:GetInventoryItems('player', identifier) or {}
    local weapons = {}
    if type(items) == 'table' then
        for _, item in ipairs(items) do
            if item and item.name then
                local name = tostring(item.name):lower()
                if name:sub(1, 7) == 'weapon_' then
                    local serial = item.metadata and item.metadata.serial or nil
                    table.insert(weapons, {
                        name   = item.name,
                        label  = item.label or item.name,
                        serial = serial
                    })
                end
            end
        end
    end
    return weapons
end

-- Get weapons for player's faction
RegisterNetEvent('faction:getWeapons', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then
        TriggerClientEvent('faction:receiveWeapons', source, {})
        return
    end

    -- weapon_hash (spawn code) intentionally excluded from member view for security
    local weapons = MySQL.query.await([[
        SELECT w.id, w.weapon_name, w.serial_number,
               w.holder_identifier, w.holder_name, w.registered_at
        FROM faction_weapons w
        WHERE w.faction_id = ?
        ORDER BY w.weapon_name
    ]], { row.faction_id })

    -- Attach possession info from cache
    local now = os.time()
    for _, w in ipairs(weapons or {}) do
        if w.holder_identifier then
            local cached = possessionCache[w.holder_identifier]
            if cached and (now - cached.lastScan) < Config.Weapons.possessionCacheMaxAge then
                w.inPossession = false
                for _, cw in ipairs(cached.weapons) do
                    if cw.serial == w.serial_number then
                        w.inPossession = true
                        break
                    end
                end
            end
        end
    end

    TriggerClientEvent('faction:receiveWeapons', source, weapons or {})
end)

-- Log weapon usage (called from client when shooting)
RegisterNetEvent('faction:logWeaponUsage', function(weaponHash, coords, isAltercation)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    if not Config.Weapons.logOnShoot then return end

    local row        = GetPlayerFactionData(xPlayer.identifier)
    local factionId  = row and row.faction_id or nil
    local hashStr    = tostring(weaponHash)
    local cx = tonumber(coords and coords.x) or 0
    local cy = tonumber(coords and coords.y) or 0
    local cz = tonumber(coords and coords.z) or 0

    -- Check if the weapon is registered to this faction
    local isViolation = false
    if Config.Weapons.enforceLogging and factionId then
        local registered = MySQL.query.await([[
            SELECT id FROM faction_weapons
            WHERE faction_id = ? AND (weapon_hash = ? OR weapon_hash IS NULL)
            LIMIT 1
        ]], { factionId, hashStr })
        isViolation = (not registered or #registered == 0)
    end

    -- Enforce violation cooldown — suppress duplicate logs within the cooldown window
    if isViolation then
        local now      = os.time()
        local lastTime = violationTimestamps[xPlayer.identifier] or 0
        if (now - lastTime) < Config.Weapons.violationCooldown then
            isViolation = false -- already logged recently, skip
        else
            violationTimestamps[xPlayer.identifier] = now
        end
    end

    MySQL.insert([[
        INSERT INTO faction_weapon_logs (faction_id, member_identifier, weapon_hash, is_altercation, is_violation, x, y, z)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { factionId, xPlayer.identifier, hashStr, isAltercation and 1 or 0, isViolation and 1 or 0, cx, cy, cz })

    -- Webhook for illegal weapon in altercation
    if isViolation and isAltercation and Config.Weapons.illegalPenalty then
        if Config.Webhooks.enabled and Config.Webhooks.invalidShootout ~= '' then
            PerformHttpRequest(Config.Webhooks.invalidShootout, function() end, 'POST',
                json.encode({ content = string.format(
                    '**Illegal Weapon Used in Altercation** | Player: %s | WeaponHash: %s | Location: %.1f, %.1f, %.1f',
                    xPlayer.getName(), hashStr, cx, cy, cz) }),
                { ['Content-Type'] = 'application/json' })
        end
    end
end)

-- ============================================================
-- GUN DROP SYSTEM
-- ============================================================

-- Give faction weapons to a player via ESX so they persist in inventory.
-- Returns the number of weapons successfully added.
local function GiveWeaponsViaESX(xPlayer, weapons)
    local count = 0
    for _, w in ipairs(weapons) do
        local raw = tostring(w.weapon_hash or ''):gsub('%s+', '')
        if raw ~= '' then
            local weaponName = raw:upper()
            local ok = pcall(function() xPlayer.addWeapon(weaponName, 250) end)
            if ok then count = count + 1 end
        end
    end
    return count
end

RegisterNetEvent('faction:requestGunDrop', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    if not Config.GunDrops.enabled then
        lib.notify(source, { type = 'error', description = 'Gun drops are currently disabled.' })
        return
    end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then
        lib.notify(source, { type = 'error', description = 'You are not in a faction.' })
        return
    end

    -- Rank check: boss or big_homie only
    if row.rank ~= 'boss' and row.rank ~= 'big_homie' then
        lib.notify(source, { type = 'error', description = 'Only Boss or Big Homie can collect gun drops.' })
        return
    end

    -- Eligibility flag check
    local faction = GetFactionById(row.faction_id)
    if not faction or (faction.gun_drop_eligible ~= 1 and faction.gun_drop_eligible ~= true) then
        lib.notify(source, { type = 'error', description = 'Your faction is not marked as gun drop eligible.' })
        return
    end

    -- Minimum reputation check
    if (faction.reputation or 0) < Config.GunDrops.minReputation then
        lib.notify(source, { type = 'error', description = string.format(
            'Need at least %d reputation for a gun drop (current: %d).',
            Config.GunDrops.minReputation, faction.reputation) })
        return
    end

    -- Cooldown check
    local cooldown = MySQL.query.await([[
        SELECT TIMESTAMPDIFF(SECOND, NOW(), expires_at) AS secs_remaining
        FROM faction_cooldowns
        WHERE faction_id = ? AND type = 'gun_drop' AND expires_at > NOW()
        LIMIT 1
    ]], { row.faction_id })

    if cooldown and #cooldown > 0 then
        local hrs  = math.floor(cooldown[1].secs_remaining / 3600)
        local mins = math.floor((cooldown[1].secs_remaining % 3600) / 60)
        lib.notify(source, { type = 'error', description = string.format(
            'Gun drop on cooldown: %dh %dm remaining.', hrs, mins) })
        return
    end

    -- Get faction's registered weapons that have a hash (so they can be given as GTA weapons)
    local weapons = MySQL.query.await([[
        SELECT weapon_name, serial_number, weapon_hash
        FROM faction_weapons
        WHERE faction_id = ? AND weapon_hash IS NOT NULL AND weapon_hash != ''
        ORDER BY weapon_name
    ]], { row.faction_id })

    if not weapons or #weapons == 0 then
        lib.notify(source, { type = 'error', description = 'No registered weapons with valid hashes found. Ask an admin to register weapons with their weapon hash.' })
        return
    end

    -- Apply cooldown BEFORE delivery to prevent double-claim on lag
    MySQL.query([[
        INSERT INTO faction_cooldowns (faction_id, type, expires_at, reason)
        VALUES (?, 'gun_drop', DATE_ADD(NOW(), INTERVAL ? SECOND), 'Gun drop collected')
        ON DUPLICATE KEY UPDATE expires_at = DATE_ADD(NOW(), INTERVAL ? SECOND), reason = 'Gun drop collected'
    ]], { row.faction_id, Config.GunDrops.cooldown, Config.GunDrops.cooldown })

    -- Deliver weapons to ALL currently online faction members via ESX inventory
    local factionMembers = MySQL.query.await('SELECT identifier FROM faction_members WHERE faction_id = ?', { row.faction_id })
    local onlineMap = {}
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        if src then
            local p = ESX.GetPlayerFromId(src)
            if p and p.identifier then onlineMap[p.identifier] = { src = src, player = p } end
        end
    end

    local recipients = {}
    if factionMembers then
        for _, m in ipairs(factionMembers) do
            local info = onlineMap[m.identifier]
            if info then
                local count = GiveWeaponsViaESX(info.player, weapons)
                if count > 0 then
                    lib.notify(info.src, {
                        type = 'success', title = 'Gun Drop',
                        description = string.format('%d weapon(s) added to your inventory.', count),
                        duration = 8000
                    })
                    table.insert(recipients, info.src)
                end
            end
        end
    end

    -- Fallback: deliver to requester if nobody received (shouldn't happen)
    if #recipients == 0 then
        local count = GiveWeaponsViaESX(xPlayer, weapons)
        if count > 0 then
            lib.notify(source, { type = 'success', title = 'Gun Drop',
                description = string.format('%d weapon(s) added to your inventory.', count), duration = 8000 })
        end
        table.insert(recipients, source)
    end

    -- Announce to the faction who initiated and how many received
    NotifyFactionMembers(row.faction_id, 'faction:receiveNotification', {
        type        = 'success',
        title       = 'Gun Drop',
        description = string.format('%s triggered a gun drop — %d online member(s) armed up.', xPlayer.getName(), #recipients)
    })

    -- Webhook
    if Config.Webhooks.enabled and Config.Webhooks.weaponLogging ~= '' then
        PerformHttpRequest(Config.Webhooks.weaponLogging, function() end, 'POST',
            json.encode({ content = string.format(
                '**Gun Drop** | Faction: %s | Triggered by: %s | Recipients: %d | Weapons per member: %d',
                faction.label, xPlayer.getName(), #recipients, #weapons) }),
            { ['Content-Type'] = 'application/json' })
    end
end)

-- Background possession scan: update who holds each registered weapon
CreateThread(function()
    while true do
        Wait(Config.Weapons.possessionScanInterval * 1000)

        local weapons = MySQL.query.await('SELECT id, faction_id, serial_number, weapon_hash FROM faction_weapons')
        if not weapons then goto continue end

        local allMembers = MySQL.query.await('SELECT DISTINCT identifier, faction_id FROM faction_members')
        if not allMembers then goto continue end

        local now = os.time()

        for _, member in ipairs(allMembers) do
            local xPlayer = ESX.GetPlayerFromIdentifier(member.identifier)
            if xPlayer then
                local inv = GetPlayerWeaponInventory(member.identifier)
                possessionCache[member.identifier] = { lastScan = now, weapons = inv }

                -- Update holder on matched weapons by serial number
                for _, w in ipairs(weapons) do
                    if w.faction_id == member.faction_id then
                        for _, iw in ipairs(inv) do
                            if iw.serial == w.serial_number then
                                MySQL.update('UPDATE faction_weapons SET holder_identifier = ?, holder_name = ? WHERE id = ?', {
                                    member.identifier, xPlayer.getName(), w.id
                                })
                                break
                            end
                        end
                    end
                end
            end
        end

        ::continue::
    end
end)

-- ============================================================
-- ADMIN: /factiondrop [faction_name]
-- Forces an immediate gun drop for a faction and resets the timer.
-- ============================================================
RegisterCommand('factiondrop', function(source, args)
    if source == 0 then return end
    if not IsAdminPlayer(source) then
        lib.notify(source, { type = 'error', description = 'No permission.' })
        return
    end

    local input = args[1] and tostring(args[1]):lower() or nil
    if not input then
        lib.notify(source, { type = 'error', description = 'Usage: /factiondrop [faction_name]' })
        return
    end

    local rows = MySQL.query.await('SELECT * FROM faction_factions WHERE LOWER(name) = ? OR LOWER(label) = ? LIMIT 1', { input, input })
    local faction = rows and rows[1] or nil
    if not faction then
        lib.notify(source, { type = 'error', description = 'Faction "' .. input .. '" not found. Use the faction name or label shown in /factionadmin.' })
        return
    end

    local fid = faction.id

    local weapons = MySQL.query.await([[
        SELECT weapon_name, serial_number, weapon_hash
        FROM faction_weapons
        WHERE faction_id = ? AND weapon_hash IS NOT NULL AND weapon_hash != ''
        ORDER BY weapon_name
    ]], { fid })

    if not weapons or #weapons == 0 then
        lib.notify(source, { type = 'error', description = 'No weapons with hashes registered for ' .. faction.label .. '.' })
        return
    end

    MySQL.update('DELETE FROM faction_cooldowns WHERE faction_id = ? AND type = ?', { fid, 'gun_drop' })

    local factionMembers = MySQL.query.await('SELECT identifier FROM faction_members WHERE faction_id = ?', { fid })
    local onlineMap = {}
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        if src then
            local p = ESX.GetPlayerFromId(src)
            if p and p.identifier then onlineMap[p.identifier] = { src = src, player = p } end
        end
    end

    local recipients = {}
    if factionMembers then
        for _, m in ipairs(factionMembers) do
            local info = onlineMap[m.identifier]
            if info then
                local count = GiveWeaponsViaESX(info.player, weapons)
                if count > 0 then
                    lib.notify(info.src, {
                        type = 'success', title = 'Gun Drop (Admin)',
                        description = string.format('%d weapon(s) added to your inventory.', count),
                        duration = 8000
                    })
                    table.insert(recipients, info.src)
                end
            end
        end
    end

    MySQL.query([[
        INSERT INTO faction_cooldowns (faction_id, type, expires_at, reason)
        VALUES (?, 'gun_drop', DATE_ADD(NOW(), INTERVAL ? SECOND), 'Admin forced gun drop')
        ON DUPLICATE KEY UPDATE expires_at = DATE_ADD(NOW(), INTERVAL ? SECOND), reason = 'Admin forced gun drop'
    ]], { fid, Config.GunDrops.cooldown, Config.GunDrops.cooldown })

    NotifyFactionMembers(fid, 'faction:receiveNotification', {
        type        = 'success',
        title       = 'Gun Drop (Admin)',
        description = string.format('Admin triggered a gun drop — %d online member(s) armed up.', #recipients)
    })

    local xPlayer = ESX.GetPlayerFromId(source)
    local adminName = xPlayer and xPlayer.getName() or 'Admin'
    lib.notify(source, { type = 'success', description = string.format(
        'Gun drop forced for %s — %d member(s) online received weapons. Timer reset.', faction.label, #recipients) })

    if Config.Webhooks.enabled and Config.Webhooks.weaponLogging ~= '' then
        PerformHttpRequest(Config.Webhooks.weaponLogging, function() end, 'POST',
            json.encode({ content = string.format(
                '**Admin Gun Drop** | Faction: %s | Admin: %s | Recipients: %d | Weapons: %d',
                faction.label, adminName, #recipients, #weapons) }),
            { ['Content-Type'] = 'application/json' })
    end
end, false)
