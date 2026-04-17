-- War/Conflict management

-- Helper: push updated wars list to ALL online admins
local function PushConflictsToAdmins()
    local conflicts = MySQL.query.await([[
        SELECT c.*,
               f1.label AS faction1_label,
               f2.label AS faction2_label
        FROM faction_conflicts c
        JOIN faction_factions f1 ON f1.id = c.faction1_id
        JOIN faction_factions f2 ON f2.id = c.faction2_id
        ORDER BY c.status ASC, c.started_at DESC
    ]])
    local factions = MySQL.query.await('SELECT id, name, label FROM faction_factions ORDER BY label')

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        if src and IsAdminPlayer(src) then
            TriggerClientEvent('faction:adminReceiveActiveWars', src, conflicts or {}, factions or {})
        end
    end
end

-- Get conflicts for player's faction
RegisterNetEvent('faction:getConflicts', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then
        TriggerClientEvent('faction:receiveConflicts', source, { conflicts = {}, alliances = {} })
        return
    end

    local conflicts = MySQL.query.await([[
        SELECT c.*,
               f1.label AS faction1_label, f1.name AS faction1_name,
               f2.label AS faction2_label, f2.name AS faction2_name
        FROM faction_conflicts c
        JOIN faction_factions f1 ON f1.id = c.faction1_id
        JOIN faction_factions f2 ON f2.id = c.faction2_id
        WHERE (c.faction1_id = ? OR c.faction2_id = ?) AND c.status = 'active'
        ORDER BY c.started_at DESC
    ]], { row.faction_id, row.faction_id })

    TriggerClientEvent('faction:receiveConflicts', source, {
        conflicts = conflicts or {},
        alliances = {}
    })
end)

-- Admin: get active wars
RegisterNetEvent('faction:adminGetActiveWars', function()
    local source = source
    if not IsAdminPlayer(source) then return end

    local conflicts = MySQL.query.await([[
        SELECT c.*,
               f1.label AS faction1_label,
               f2.label AS faction2_label
        FROM faction_conflicts c
        JOIN faction_factions f1 ON f1.id = c.faction1_id
        JOIN faction_factions f2 ON f2.id = c.faction2_id
        ORDER BY c.status ASC, c.started_at DESC
    ]])
    local factions = MySQL.query.await('SELECT id, name, label FROM faction_factions ORDER BY label')

    TriggerClientEvent('faction:adminReceiveActiveWars', source, conflicts or {}, factions or {})
end)

-- Admin: set conflict status
RegisterNetEvent('faction:adminSetConflictStatus', function(conflictId, status)
    local source = source
    if not IsAdminPlayer(source) then return end

    local cid = tonumber(conflictId)
    if not cid then return end

    local allowedStatuses = { active = true, ended = true, pending = true }
    if not allowedStatuses[status] then return end

    MySQL.update("UPDATE faction_conflicts SET status = ?, ended_at = IF(? = 'ended', NOW(), NULL) WHERE id = ?", {
        status, status, cid
    })

    -- Refresh war counts for both factions
    local c = MySQL.query.await('SELECT faction1_id, faction2_id FROM faction_conflicts WHERE id = ? LIMIT 1', { cid })
    if c and #c > 0 then
        RefreshFactionWarCount(c[1].faction1_id)
        RefreshFactionWarCount(c[1].faction2_id)
    end

    Notify(source, 'success', 'Conflict status updated.')

    -- Push updated list to all online admins
    PushConflictsToAdmins()
end)

-- Admin: create a conflict between two factions
RegisterNetEvent('faction:adminCreateConflict', function(faction1Id, faction2Id, conflictType, reason)
    local source = source
    if not IsAdminPlayer(source) then return end

    local f1 = tonumber(faction1Id)
    local f2 = tonumber(faction2Id)
    if not f1 or not f2 or f1 == f2 then
        Notify(source, 'error', 'Invalid faction IDs.')
        return
    end

    local safeType   = tostring(conflictType or 'war'):sub(1, 32)
    local safeReason = reason and tostring(reason):sub(1, 500) or nil

    -- Check for existing active conflict
    local existing = MySQL.query.await([[
        SELECT id FROM faction_conflicts
        WHERE ((faction1_id = ? AND faction2_id = ?) OR (faction1_id = ? AND faction2_id = ?))
        AND status = 'active'
        LIMIT 1
    ]], { f1, f2, f2, f1 })

    if existing and #existing > 0 then
        Notify(source, 'error', 'These factions already have an active conflict.')
        return
    end

    MySQL.insert([[
        INSERT INTO faction_conflicts (faction1_id, faction2_id, type, status, reason)
        VALUES (?, ?, ?, 'active', ?)
    ]], { f1, f2, safeType, safeReason })

    RefreshFactionWarCount(f1)
    RefreshFactionWarCount(f2)

    Notify(source, 'success', 'Conflict created.')

    -- Push updated list to all online admins
    PushConflictsToAdmins()
end)

-- Admin: end war by ID
RegisterNetEvent('faction:adminEndWar', function(warId)
    local source = source
    if not IsAdminPlayer(source) then return end

    local wid = tonumber(warId)
    if not wid then return end

    local c = MySQL.query.await('SELECT faction1_id, faction2_id FROM faction_conflicts WHERE id = ? LIMIT 1', { wid })
    MySQL.update("UPDATE faction_conflicts SET status = 'ended', ended_at = NOW() WHERE id = ?", { wid })

    if c and #c > 0 then
        RefreshFactionWarCount(c[1].faction1_id)
        RefreshFactionWarCount(c[1].faction2_id)
    end

    Notify(source, 'success', 'War ended.')
    PushConflictsToAdmins()
end)

-- Admin: set war duration (ends at start + duration seconds)
RegisterNetEvent('faction:adminSetWarDuration', function(warId, durationSeconds)
    local source = source
    if not IsAdminPlayer(source) then return end

    local wid = tonumber(warId)
    local dur = tonumber(durationSeconds)
    if not wid or not dur or dur < 60 then return end

    MySQL.update([[
        UPDATE faction_conflicts SET ended_at = DATE_ADD(started_at, INTERVAL ? SECOND) WHERE id = ?
    ]], { dur, wid })

    Notify(source, 'success', 'War duration set.')
    PushConflictsToAdmins()
end)
