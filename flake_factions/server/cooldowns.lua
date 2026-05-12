-- Cooldown management

-- Helper: format seconds remaining until a timestamp
local function SecondsUntil(expiresAt)
    -- expiresAt may be a string like '2025-01-01 12:00:00'
    if not expiresAt then return 0 end
    -- Use MySQL to calculate difference
    local result = MySQL.query.await('SELECT GREATEST(0, TIMESTAMPDIFF(SECOND, NOW(), ?)) AS secs', { expiresAt })
    return result and result[1] and result[1].secs or 0
end

-- Get cooldowns for player's faction
RegisterNetEvent('faction:getCooldowns', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then
        TriggerClientEvent('faction:receiveCooldowns', source, { cooldowns = {}, ckHistory = {} })
        return
    end

    -- Active cooldowns
    local cooldowns = MySQL.query.await([[
        SELECT id, type, reason,
               DATE_FORMAT(expires_at, '%Y-%m-%d %H:%i:%s') AS ends_at,
               GREATEST(0, TIMESTAMPDIFF(SECOND, NOW(), expires_at)) AS seconds_remaining
        FROM faction_cooldowns
        WHERE faction_id = ? AND expires_at > NOW()
        ORDER BY expires_at ASC
    ]], { row.faction_id })

    -- CK history for this faction
    local ckHistory = MySQL.query.await([[
        SELECT id, target_name, reason, status, created_at
        FROM faction_ck_requests
        WHERE requesting_faction_id = ?
        ORDER BY created_at DESC
        LIMIT 20
    ]], { row.faction_id })

    TriggerClientEvent('faction:receiveCooldowns', source, {
        cooldowns = cooldowns or {},
        ckHistory = ckHistory or {}
    })
end)

-- Admin: get all cooldowns
RegisterNetEvent('faction:adminGetCooldowns', function()
    local source = source
    if not IsAdminPlayer(source) then return end

    local cooldowns = MySQL.query.await([[
        SELECT cd.id, cd.faction_id, cd.type, cd.reason,
               DATE_FORMAT(cd.expires_at, '%Y-%m-%d %H:%i:%s') AS ends_at,
               GREATEST(0, TIMESTAMPDIFF(SECOND, NOW(), cd.expires_at)) AS seconds_remaining,
               f.label AS faction_label
        FROM faction_cooldowns cd
        JOIN faction_factions f ON f.id = cd.faction_id
        WHERE cd.expires_at > NOW()
        ORDER BY cd.expires_at ASC
    ]])

    local factions = MySQL.query.await('SELECT id, name, label FROM faction_factions ORDER BY label')

    TriggerClientEvent('faction:adminReceiveCooldowns', source, cooldowns or {}, factions or {})
end)

-- Admin: set a cooldown on a faction
RegisterNetEvent('faction:adminSetCooldown', function(factionId, cooldownType, durationSeconds, reason)
    local source = source
    if not IsAdminPlayer(source) then return end

    local fid  = tonumber(factionId)
    local dur  = tonumber(durationSeconds)
    if not fid or not dur or dur < 1 then return end

    local safeType   = tostring(cooldownType or 'custom'):sub(1, 64)
    local safeReason = reason and tostring(reason):sub(1, 500) or 'Set by admin'

    MySQL.query([[
        INSERT INTO faction_cooldowns (faction_id, type, expires_at, reason)
        VALUES (?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND), ?)
        ON DUPLICATE KEY UPDATE expires_at = DATE_ADD(NOW(), INTERVAL ? SECOND), reason = ?
    ]], { fid, safeType, dur, safeReason, dur, safeReason })

    lib.notify(source, { type = 'success', description = 'Cooldown set.' })

    -- Notify affected faction members to refresh
    NotifyFactionMembers(fid, 'faction:refreshCooldowns', {})

    -- Refresh admin cooldown view
    TriggerClientEvent('faction:adminRefreshCooldowns', source)
end)

-- Admin: remove a cooldown
RegisterNetEvent('faction:adminRemoveCooldown', function(cooldownId)
    local source = source
    if not IsAdminPlayer(source) then return end

    local cid = tonumber(cooldownId)
    if not cid then return end

    local cd = MySQL.query.await('SELECT faction_id FROM faction_cooldowns WHERE id = ? LIMIT 1', { cid })
    MySQL.update('DELETE FROM faction_cooldowns WHERE id = ?', { cid })

    if cd and #cd > 0 then
        NotifyFactionMembers(cd[1].faction_id, 'faction:refreshCooldowns', {})
    end

    lib.notify(source, { type = 'success', description = 'Cooldown removed.' })
    TriggerClientEvent('faction:adminRefreshCooldowns', source)
end)
