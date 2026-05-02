-- Weapon tracking, logging, violation enforcement, and gun drop system

-- Possession scan cache: identifier -> { lastScan = timestamp, weapons = {} }
local possessionCache = {}

-- Violation cooldown cache: identifier -> last violation log timestamp (os.time)
local violationTimestamps = {}

-- Helper: get current weapon inventory for a player from ox_inventory
-- Pass the player's server source ID (number) for online players.
local function GetPlayerWeaponInventory(source)
    if not exports.ox_inventory then return {} end
    -- ox_inventory:GetInventoryItems(id) where id is the player source number
    local items = exports.ox_inventory:GetInventoryItems(source)
    local weapons = {}
    if type(items) == 'table' then
        for _, item in ipairs(items) do
            if item and item.name then
                local name = tostring(item.name):lower()
                if name:sub(1, 7) == 'weapon_' then
                    local serial = item.metadata and item.metadata.serial or nil
                    table.insert(weapons, {
                        name   = name,
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

    -- For each weapon, determine live possession status using DB holder_identifier
    -- and check if that player is currently online with the weapon in their inventory
    local now = os.time()
    for _, w in ipairs(weapons or {}) do
        w.inPossession = false
        if w.holder_identifier and w.holder_identifier ~= '' then
            -- Check cache first
            local cached = possessionCache[w.holder_identifier]
            if cached and (now - cached.lastScan) < Config.Weapons.possessionCacheMaxAge then
                for _, cw in ipairs(cached.weapons) do
                    if cw.serial and w.serial_number and cw.serial == w.serial_number then
                        w.inPossession = true
                        break
                    end
                end
            else
                -- Live check: is that player online with the weapon?
                local holder = ESX.GetPlayerFromIdentifier(w.holder_identifier)
                if holder then
                    local inv = GetPlayerWeaponInventory(holder.source)
                    possessionCache[w.holder_identifier] = { lastScan = now, weapons = inv }
                    for _, cw in ipairs(inv) do
                        if cw.serial and w.serial_number and cw.serial == w.serial_number then
                            w.inPossession = true
                            break
                        end
                    end
                end
            end
        end
    end

    TriggerClientEvent('faction:receiveWeapons', source, weapons or {})
end)

-- Log weapon usage (called from client when shooting)
-- weaponItemName is the ox_inventory item name (e.g. 'weapon_custom75arp'), weaponHash is the GTA numeric hash
RegisterNetEvent('faction:logWeaponUsage', function(weaponHash, coords, isAltercation, weaponItemName)
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

    -- Determine if shot weapon is a violation:
    -- A violation occurs when the player fires a weapon that is NOT registered to their faction.
    -- We check by: 1) matching the weapon's serial from ox_inventory against registered serials,
    -- or 2) matching the weapon item name against registered weapon_hash (spawn name).
    local isViolation = false
    if Config.Weapons.enforceLogging and factionId then
        local playerWeapons = GetPlayerWeaponInventory(source)
        local registeredWeapons = MySQL.query.await([[
            SELECT serial_number, LOWER(weapon_hash) AS weapon_hash_lower, LOWER(weapon_name) AS weapon_name_lower
            FROM faction_weapons WHERE faction_id = ?
        ]], { factionId })

        local registeredSerials = {}
        local registeredNames   = {}
        for _, rw in ipairs(registeredWeapons or {}) do
            if rw.serial_number and rw.serial_number ~= '' then
                registeredSerials[rw.serial_number] = true
            end
            if rw.weapon_hash_lower and rw.weapon_hash_lower ~= '' then
                registeredNames[rw.weapon_hash_lower] = true
            end
            if rw.weapon_name_lower and rw.weapon_name_lower ~= '' then
                -- weapon_name without 'weapon_' prefix
                registeredNames[rw.weapon_name_lower] = true
            end
        end

        -- Find the currently fired weapon in the player's ox_inventory
        local firedItemName = weaponItemName and weaponItemName:lower() or nil
        local firedWeapon   = nil
        for _, pw in ipairs(playerWeapons) do
            if firedItemName and pw.name:lower() == firedItemName then
                firedWeapon = pw
                break
            end
        end

        -- Check by serial first (most accurate), then by item name
        if firedWeapon and firedWeapon.serial and registeredSerials[firedWeapon.serial] then
            isViolation = false -- weapon serial registered
        elseif firedItemName and (registeredNames[firedItemName] or registeredNames[firedItemName:gsub('^weapon_', '')]) then
            isViolation = false -- weapon type registered by name
        elseif #playerWeapons == 0 and not firedItemName then
            isViolation = false -- can't determine, skip
        else
            isViolation = true -- weapon is not in registered list
        end
    end

    -- Enforce violation cooldown — suppress duplicate logs within the cooldown window
    local violationToLog = isViolation
    if isViolation then
        local now      = os.time()
        local lastTime = violationTimestamps[xPlayer.identifier] or 0
        if (now - lastTime) < Config.Weapons.violationCooldown then
            violationToLog = false -- already logged recently, suppress DB write but keep flag for webhook
        else
            violationTimestamps[xPlayer.identifier] = now
        end
    end

    MySQL.insert([[
        INSERT INTO faction_weapon_logs (faction_id, member_identifier, weapon_hash, is_altercation, is_violation, x, y, z)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { factionId, xPlayer.identifier, weaponItemName or hashStr, isAltercation and 1 or 0, violationToLog and 1 or 0, cx, cy, cz })

    -- Webhook: general weapon shot log (fires for every shot during an altercation)
    if isAltercation and Config.Webhooks.enabled and Config.Webhooks.weaponLogging ~= '' then
        PerformHttpRequest(Config.Webhooks.weaponLogging, function() end, 'POST',
            json.encode({ content = string.format(
                '**Weapon Shot** | Player: %s | Faction: %s | Weapon: %s | Location: %.1f, %.1f, %.1f | Violation: %s',
                xPlayer.getName(), row and row.faction_label or 'Unknown',
                weaponItemName or hashStr, cx, cy, cz,
                isViolation and 'YES (unregistered)' or 'No') }),
            { ['Content-Type'] = 'application/json' })
    end

    -- Webhook: illegal weapon in altercation (invalidShootout URL)
    if isViolation and isAltercation and Config.Weapons.illegalPenalty then
        -- Insert violation record
        if violationToLog and factionId then
            MySQL.insert([[
                INSERT INTO faction_violations (faction_id, member_identifier, type, details)
                VALUES (?, ?, 'unregistered_weapon', ?)
            ]], { factionId, xPlayer.identifier,
                  string.format('Fired unregistered weapon %s at %.0f,%.0f,%.0f during altercation', weaponItemName or hashStr, cx, cy, cz) })
        end

        if Config.Webhooks.enabled and Config.Webhooks.invalidShootout ~= '' then
            PerformHttpRequest(Config.Webhooks.invalidShootout, function() end, 'POST',
                json.encode({ content = string.format(
                    '**Illegal Weapon Used in Altercation** | Player: %s | Faction: %s | Weapon: %s | Location: %.1f, %.1f, %.1f',
                    xPlayer.getName(), row and row.faction_label or 'Unknown', weaponItemName or hashStr, cx, cy, cz) }),
                { ['Content-Type'] = 'application/json' })
        end
    end
end)

-- ============================================================
-- GUN DROP SYSTEM
-- ============================================================

-- Give faction weapons to a player via ox_inventory (with serial metadata) or ESX fallback.
local function GiveWeaponsViaESX(xPlayer, weapons)
    local src   = xPlayer.source
    local count = 0

    for _, w in ipairs(weapons) do
        local raw = tostring(w.weapon_hash or ''):gsub('%s+', '')
        if raw ~= '' then
            if exports.ox_inventory then
                local serial   = w.serial_number and tostring(w.serial_number) or nil
                local metadata = serial and { serial = serial } or nil
                local ok, err  = pcall(function()
                    local success = exports.ox_inventory:AddItem(src, raw:lower(), 1, metadata)
                    if success then count = count + 1 end
                end)
                if not ok then
                    print(string.format('[faction:gunDrop] ox_inventory:AddItem error for %s: %s', raw, tostring(err)))
                end
            else
                local ok = pcall(function() xPlayer.addWeapon(raw:upper(), 250) end)
                if ok then count = count + 1 end
            end
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

    -- Run possession scan shortly after so new serials are tracked immediately
    SetTimeout(3000, function() RunPossessionScan() end)

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
local function RunPossessionScan()
    local weapons = MySQL.query.await('SELECT id, faction_id, serial_number FROM faction_weapons WHERE serial_number IS NOT NULL AND serial_number != \'\'')
    if not weapons or #weapons == 0 then return end

    -- Build online player map: identifier -> { src, player }
    local onlineMap = {}
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        if src then
            local p = ESX.GetPlayerFromId(src)
            if p and p.identifier then onlineMap[p.identifier] = { src = src, player = p } end
        end
    end

    local allMembers = MySQL.query.await('SELECT DISTINCT identifier, faction_id FROM faction_members')
    if not allMembers then return end

    local now = os.time()

    -- Track which weapon IDs have been matched so we can clear unmatched holders
    local matchedWeaponIds = {}

    for _, member in ipairs(allMembers) do
        local info = onlineMap[member.identifier]
        if info then
            -- FIXED: pass the player source (number), not the identifier (string)
            local inv = GetPlayerWeaponInventory(info.src)
            possessionCache[member.identifier] = { lastScan = now, weapons = inv }

            for _, w in ipairs(weapons) do
                if w.faction_id == member.faction_id then
                    for _, iw in ipairs(inv) do
                        if iw.serial and w.serial_number and iw.serial == w.serial_number then
                            MySQL.update('UPDATE faction_weapons SET holder_identifier = ?, holder_name = ? WHERE id = ?', {
                                member.identifier, info.player.getName(), w.id
                            })
                            matchedWeaponIds[w.id] = true
                            break
                        end
                    end
                end
            end
        end
    end

    -- Clear holder for weapons whose holder is online but no longer has the weapon
    for _, w in ipairs(weapons) do
        if not matchedWeaponIds[w.id] then
            -- Only clear if the recorded holder is currently online (if offline, leave last known)
            local result = MySQL.query.await('SELECT holder_identifier FROM faction_weapons WHERE id = ? LIMIT 1', { w.id })
            if result and result[1] and result[1].holder_identifier then
                local holderOnline = onlineMap[result[1].holder_identifier]
                if holderOnline then
                    -- Holder is online but doesn't have the weapon anymore - clear it
                    MySQL.update('UPDATE faction_weapons SET holder_identifier = NULL, holder_name = NULL WHERE id = ?', { w.id })
                end
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(Config.Weapons.possessionScanInterval * 1000)
        RunPossessionScan()
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

    SetTimeout(3000, function() RunPossessionScan() end)

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

-- ============================================================
-- KILL / DEATH REPUTATION TRACKING
-- ============================================================

-- Per-player cooldown to prevent reputation spam from rapid kills/deaths (os.time, seconds)
local killRepCooldowns  = {}
local deathRepCooldowns = {}
local REP_KILL_COOLDOWN  = 30  -- seconds between rep grants per killer
local REP_DEATH_COOLDOWN = 60  -- seconds between rep losses per dead member

-- Called when the local player kills another player
RegisterNetEvent('faction:playerKilledPlayer', function(victimServerId)
    local source  = source
    local killer  = ESX.GetPlayerFromId(source)
    if not killer then return end

    local killerRow = GetPlayerFactionData(killer.identifier)
    if not killerRow then return end -- killer not in a faction

    -- Victim must be in a DIFFERENT faction (enemy kill = rep gain)
    local victim = ESX.GetPlayerFromId(tonumber(victimServerId))
    if not victim then return end

    local victimRow = GetPlayerFactionData(victim.identifier)
    -- Friendly-fire check: no rep if same faction
    if victimRow and victimRow.faction_id == killerRow.faction_id then return end

    -- Cooldown check
    local now = os.time()
    if (now - (killRepCooldowns[killer.identifier] or 0)) < REP_KILL_COOLDOWN then return end
    killRepCooldowns[killer.identifier] = now

    local repGain = Config.Reputation.killEnemy or 5
    MySQL.update('UPDATE faction_factions SET reputation = reputation + ? WHERE id = ?', { repGain, killerRow.faction_id })
    MySQL.update('UPDATE faction_members SET reputation_contribution = reputation_contribution + ? WHERE identifier = ? AND faction_id = ?',
        { repGain, killer.identifier, killerRow.faction_id })

    lib.notify(source, { type = 'success', title = 'Reputation', description = string.format('+%d rep for your faction (enemy kill)', repGain) })

    -- Push updated faction data so the reputation tab shows the new value
    SendFactionDataToPlayer(source)

    if Config.Webhooks.enabled and Config.Webhooks.weaponLogging ~= '' then
        PerformHttpRequest(Config.Webhooks.weaponLogging, function() end, 'POST',
            json.encode({ content = string.format(
                '**Enemy Kill** | Killer: %s | Faction: %s | Victim: %s | +%d Rep',
                killer.getName(), killerRow.faction_label, victim.getName(), repGain) }),
            { ['Content-Type'] = 'application/json' })
    end
end)

-- Called when the local player dies
RegisterNetEvent('faction:playerDied', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then return end -- not in a faction

    -- Cooldown check
    local now = os.time()
    if (now - (deathRepCooldowns[xPlayer.identifier] or 0)) < REP_DEATH_COOLDOWN then return end
    deathRepCooldowns[xPlayer.identifier] = now

    local repLoss = math.abs(Config.Reputation.loseMember or 10)
    MySQL.update('UPDATE faction_factions SET reputation = GREATEST(0, reputation - ?) WHERE id = ?', { repLoss, row.faction_id })

    if Config.Webhooks.enabled and Config.Webhooks.weaponLogging ~= '' then
        PerformHttpRequest(Config.Webhooks.weaponLogging, function() end, 'POST',
            json.encode({ content = string.format(
                '**Member Death** | Member: %s | Faction: %s | -%d Rep',
                xPlayer.getName(), row.faction_label, repLoss) }),
            { ['Content-Type'] = 'application/json' })
    end
end)
