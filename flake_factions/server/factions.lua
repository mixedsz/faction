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

    -- Show ALL factions (including own) so a boss can CK any member regardless of faction
    local factions = MySQL.query.await([[
        SELECT DISTINCT f.id, f.name, f.label
        FROM faction_factions f
        JOIN faction_members fm ON fm.faction_id = f.id
        ORDER BY f.label
    ]])

    TriggerClientEvent('faction:receiveFactionListForCK', source, factions or {})
end)

-- Get all players from a specific faction for CK selection (online and offline)
RegisterNetEvent('faction:getFactionPlayersForCK', function(factionId)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local faction = GetFactionById(tonumber(factionId))
    if not faction then
        TriggerClientEvent('faction:receiveFactionPlayersForCK', source, {}, 'Unknown')
        return
    end

    local members = MySQL.query.await([[
        SELECT identifier, player_name, rank, last_active
        FROM faction_members
        WHERE faction_id = ?
        ORDER BY player_name
    ]], { tonumber(factionId) })

    local allPlayers = {}
    for _, m in ipairs(members or {}) do
        -- Use ESX.GetPlayerFromIdentifier for reliable online check
        local p = ESX.GetPlayerFromIdentifier(m.identifier)
        local isOnline = p ~= nil
        table.insert(allPlayers, {
            identifier = m.identifier,
            name       = (p and p.getName()) or m.player_name or m.identifier,
            serverId   = p and p.source or 0,
            online     = isOnline,
            rank       = m.rank,
            last_active = m.last_active
        })
    end

    -- Sort: online members first
    table.sort(allPlayers, function(a, b)
        if a.online ~= b.online then return a.online end
        return (a.name or '') < (b.name or '')
    end)

    TriggerClientEvent('faction:receiveFactionPlayersForCK', source, allPlayers, faction.label)
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

    -- Webhook notification
    if Config.Webhooks.enabled and Config.Webhooks.reportSubmitted ~= '' then
        PerformHttpRequest(Config.Webhooks.reportSubmitted, function() end, 'POST',
            json.encode({ content = string.format(
                '**CK Request Submitted** | Faction: %s | By: %s | Target: %s | Reason: %s',
                row.faction_label, xPlayer.getName(), safeName, safeReason:sub(1, 200)) }),
            { ['Content-Type'] = 'application/json' })
    end
end)
