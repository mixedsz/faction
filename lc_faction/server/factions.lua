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

    -- Build a fast lookup of online players by identifier
    local onlineMap = {}
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        if src then
            local p = ESX.GetPlayerFromId(src)
            if p and p.identifier then
                onlineMap[p.identifier] = { src = src, name = p.getName() }
            end
        end
    end

    local members = MySQL.query.await('SELECT identifier, player_name FROM faction_members WHERE faction_id = ?', { tonumber(factionId) })
    local allPlayers = {}

    for _, m in ipairs(members or {}) do
        local info = onlineMap[m.identifier]
        table.insert(allPlayers, {
            identifier = m.identifier,
            name       = (info and info.name) or m.player_name or m.identifier,
            serverId   = info and info.src or 0,
            online     = info ~= nil
        })
    end

    TriggerClientEvent('faction:receiveFactionPlayersForCK', source, allPlayers, faction.label)
end)

-- Submit a CK request
RegisterNetEvent('faction:requestCK', function(targetIdentifier, targetName, reason)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then
        Notify(source, 'error', 'You are not in a faction.')
        return
    end

    -- Rank check: shot_caller and above
    local rank = row.rank
    if rank ~= 'boss' and rank ~= 'big_homie' and rank ~= 'shot_caller' then
        Notify(source, 'error', 'Insufficient rank to submit CK requests.')
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
        Notify(source, 'error', string.format('CK cooldown active: %d minute(s) remaining.', mins))
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

    Notify(source, 'success', 'CK request submitted for admin review.')
end)
