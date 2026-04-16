-- Faction CRUD operations and player faction data delivery

-- Get the faction list for a CK request (other factions that have online members)
RegisterNetEvent('faction:getFactionListForCK', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then
        TriggerClientEvent('faction:receiveFactionListForCK', source, {})
        return
    end

    -- Only show factions that have at least one online player
    local factions = MySQL.query.await([[
        SELECT DISTINCT f.id, f.name, f.label
        FROM faction_factions f
        JOIN faction_members fm ON fm.faction_id = f.id
        WHERE f.id != ?
        ORDER BY f.label
    ]], { row.faction_id })

    -- Filter to factions with online players
    local result = {}
    for _, f in ipairs(factions or {}) do
        local members = MySQL.query.await('SELECT identifier FROM faction_members WHERE faction_id = ?', { f.id })
        for _, m in ipairs(members or {}) do
            if ESX.GetPlayerFromIdentifier(m.identifier) then
                table.insert(result, f)
                break
            end
        end
    end

    TriggerClientEvent('faction:receiveFactionListForCK', source, result)
end)

-- Get online players from a specific faction for CK selection
RegisterNetEvent('faction:getFactionPlayersForCK', function(factionId)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local faction = GetFactionById(tonumber(factionId))
    if not faction then
        TriggerClientEvent('faction:receiveFactionPlayersForCK', source, {}, 'Unknown')
        return
    end

    local members = MySQL.query.await('SELECT identifier, player_name FROM faction_members WHERE faction_id = ?', { tonumber(factionId) })
    local onlinePlayers = {}

    for _, m in ipairs(members or {}) do
        local target = ESX.GetPlayerFromIdentifier(m.identifier)
        if target then
            table.insert(onlinePlayers, {
                identifier = m.identifier,
                name       = target.getName(),
                serverId   = target.source
            })
        end
    end

    TriggerClientEvent('faction:receiveFactionPlayersForCK', source, onlinePlayers, faction.label)
end)

-- Submit a CK request
RegisterNetEvent('faction:requestCK', function(targetIdentifier, targetName, reason)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then
        lib.notify(source, { type = 'error', description = 'You are not in a faction.' })
        return
    end

    -- Rank check: shot_caller and above
    local rank = row.rank
    if rank ~= 'boss' and rank ~= 'big_homie' and rank ~= 'shot_caller' then
        lib.notify(source, { type = 'error', description = 'Insufficient rank to submit CK requests.' })
        return
    end

    -- CK cooldown check
    local cooldown = MySQL.query.await([[
        SELECT TIMESTAMPDIFF(SECOND, NOW(), expires_at) AS secs_remaining
        FROM faction_cooldowns
        WHERE faction_id = ? AND type = 'ck' AND expires_at > NOW()
        LIMIT 1
    ]], { row.faction_id })

    if cooldown and #cooldown > 0 then
        local mins = math.ceil(cooldown[1].secs_remaining / 60)
        lib.notify(source, { type = 'error', description = string.format('CK cooldown active: %d minute(s) remaining.', mins) })
        return
    end

    local safeTarget = tostring(targetIdentifier):sub(1, 64)
    local safeName   = tostring(targetName):sub(1, 128)
    local safeReason = tostring(reason):sub(1, 2000)

    MySQL.insert([[
        INSERT INTO faction_ck_requests (requesting_faction_id, requester_identifier, target_identifier, target_name, reason)
        VALUES (?, ?, ?, ?, ?)
    ]], { row.faction_id, xPlayer.identifier, safeTarget, safeName, safeReason })

    -- Apply CK cooldown
    MySQL.query([[
        INSERT INTO faction_cooldowns (faction_id, type, expires_at, reason)
        VALUES (?, 'ck', DATE_ADD(NOW(), INTERVAL ? SECOND), 'CK request submitted')
        ON DUPLICATE KEY UPDATE expires_at = DATE_ADD(NOW(), INTERVAL ? SECOND), reason = 'CK request submitted'
    ]], { row.faction_id, Config.Conflict.ckCooldown, Config.Conflict.ckCooldown })

    lib.notify(source, { type = 'success', description = 'CK request submitted for admin review.' })
end)
