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

-- Internal: end a war and apply reputation changes (winner = faction1 by convention, or nil for draw)
local function EndWar(conflictId, winnerId)
    local c = MySQL.query.await([[
        SELECT c.*, f1.label AS f1_label, f2.label AS f2_label
        FROM faction_conflicts c
        JOIN faction_factions f1 ON f1.id = c.faction1_id
        JOIN faction_factions f2 ON f2.id = c.faction2_id
        WHERE c.id = ? LIMIT 1
    ]], { conflictId })
    if not c or #c == 0 then return end
    local conflict = c[1]

    MySQL.update("UPDATE faction_conflicts SET status = 'ended', ended_at = NOW() WHERE id = ?", { conflictId })
    RefreshFactionWarCount(conflict.faction1_id)
    RefreshFactionWarCount(conflict.faction2_id)

    local repWin  = Config.Reputation.winWar  or 50
    local repLose = math.abs(Config.Reputation.loseWar or 25)

    if winnerId then
        local loserId = (winnerId == conflict.faction1_id) and conflict.faction2_id or conflict.faction1_id
        local winLabel = (winnerId == conflict.faction1_id) and conflict.f1_label or conflict.f2_label
        local loseLabel = (loserId == conflict.faction1_id) and conflict.f1_label or conflict.f2_label

        MySQL.update('UPDATE faction_factions SET reputation = reputation + ? WHERE id = ?', { repWin, winnerId })
        MySQL.update('UPDATE faction_factions SET reputation = GREATEST(0, reputation - ?) WHERE id = ?', { repLose, loserId })

        NotifyFactionMembers(winnerId, 'faction:receiveNotification', {
            type = 'success', title = 'War Over', description = 'Your faction won the war! +' .. repWin .. ' reputation.'
        })
        NotifyFactionMembers(loserId, 'faction:receiveNotification', {
            type = 'error', title = 'War Over', description = 'Your faction lost the war. -' .. repLose .. ' reputation.'
        })

        if Config.Webhooks.enabled and Config.Webhooks.weaponLogging ~= '' then
            PerformHttpRequest(Config.Webhooks.weaponLogging, function() end, 'POST',
                json.encode({ content = string.format(
                    '**War Ended** | Winner: %s (+%d rep) | Loser: %s (-%d rep)',
                    winLabel, repWin, loseLabel, repLose) }),
                { ['Content-Type'] = 'application/json' })
        end
    else
        -- Draw / auto-expiry: no winner
        NotifyFactionMembers(conflict.faction1_id, 'faction:receiveNotification', {
            type = 'info', title = 'War Over', description = 'The war with ' .. conflict.f2_label .. ' has ended (draw).'
        })
        NotifyFactionMembers(conflict.faction2_id, 'faction:receiveNotification', {
            type = 'info', title = 'War Over', description = 'The war with ' .. conflict.f1_label .. ' has ended (draw).'
        })

        if Config.Webhooks.enabled and Config.Webhooks.weaponLogging ~= '' then
            PerformHttpRequest(Config.Webhooks.weaponLogging, function() end, 'POST',
                json.encode({ content = string.format(
                    '**War Ended (Draw/Expired)** | %s vs %s',
                    conflict.f1_label, conflict.f2_label) }),
                { ['Content-Type'] = 'application/json' })
        end
    end

    PushConflictsToAdmins()
end

-- Auto-expiry thread: check every 60 s for wars that have passed their ended_at time
CreateThread(function()
    while true do
        Wait(60000)
        local expired = MySQL.query.await([[
            SELECT id FROM faction_conflicts
            WHERE status = 'active' AND ended_at IS NOT NULL AND ended_at <= NOW()
        ]])
        if expired then
            for _, row in ipairs(expired) do
                print('[flake_factions] Auto-ending expired war ID ' .. row.id)
                EndWar(row.id, nil)
            end
        end
    end
end)

-- Admin: set conflict status
RegisterNetEvent('faction:adminSetConflictStatus', function(conflictId, status)
    local source = source
    if not IsAdminPlayer(source) then return end

    local cid = tonumber(conflictId)
    if not cid then return end

    local allowedStatuses = { active = true, ended = true, pending = true }
    if not allowedStatuses[status] then return end

    if status == 'ended' then
        -- End with no winner (draw) — use our EndWar helper
        EndWar(cid, nil)
        lib.notify(source, { type = 'success', description = 'War ended (no winner assigned). Use adminEndWarWithWinner to set a winner.' })
    else
        MySQL.update("UPDATE faction_conflicts SET status = ?, ended_at = IF(? = 'ended', NOW(), ended_at) WHERE id = ?", {
            status, status, cid
        })
        local c = MySQL.query.await('SELECT faction1_id, faction2_id FROM faction_conflicts WHERE id = ? LIMIT 1', { cid })
        if c and #c > 0 then
            RefreshFactionWarCount(c[1].faction1_id)
            RefreshFactionWarCount(c[1].faction2_id)
        end
        lib.notify(source, { type = 'success', description = 'Conflict status updated.' })
        PushConflictsToAdmins()
    end
end)

-- Admin: end war and declare a winner
RegisterNetEvent('faction:adminEndWarWithWinner', function(conflictId, winnerFactionId)
    local source = source
    if not IsAdminPlayer(source) then return end
    local cid = tonumber(conflictId)
    local wid = tonumber(winnerFactionId)
    if not cid then return end
    EndWar(cid, wid)
    lib.notify(source, { type = 'success', description = 'War ended with winner assigned.' })
end)

-- Admin: create a conflict between two factions
RegisterNetEvent('faction:adminCreateConflict', function(faction1Id, faction2Id, conflictType, reason)
    local source = source
    if not IsAdminPlayer(source) then return end

    local f1 = tonumber(faction1Id)
    local f2 = tonumber(faction2Id)
    if not f1 or not f2 or f1 == f2 then
        lib.notify(source, { type = 'error', description = 'Invalid faction IDs.' })
        return
    end

    local safeType   = tostring(conflictType or 'war'):sub(1, 32)
    local safeReason = reason and tostring(reason):sub(1, 500) or nil

    -- Check for existing active conflict between these two factions
    local existing = MySQL.query.await([[
        SELECT id FROM faction_conflicts
        WHERE ((faction1_id = ? AND faction2_id = ?) OR (faction1_id = ? AND faction2_id = ?))
        AND status = 'active'
        LIMIT 1
    ]], { f1, f2, f2, f1 })

    if existing and #existing > 0 then
        lib.notify(source, { type = 'error', description = 'These factions already have an active conflict.' })
        return
    end

    -- Enforce max active wars per faction
    local wars1 = MySQL.query.await('SELECT COUNT(*) AS cnt FROM faction_conflicts WHERE (faction1_id = ? OR faction2_id = ?) AND status = ?', { f1, f1, 'active' })
    local wars2 = MySQL.query.await('SELECT COUNT(*) AS cnt FROM faction_conflicts WHERE (faction1_id = ? OR faction2_id = ?) AND status = ?', { f2, f2, 'active' })
    local cnt1 = wars1 and wars1[1] and wars1[1].cnt or 0
    local cnt2 = wars2 and wars2[1] and wars2[1].cnt or 0
    if cnt1 >= Config.Conflict.maxActiveWars then
        lib.notify(source, { type = 'error', description = 'Faction 1 has reached the maximum number of active wars (' .. Config.Conflict.maxActiveWars .. ').' })
        return
    end
    if cnt2 >= Config.Conflict.maxActiveWars then
        lib.notify(source, { type = 'error', description = 'Faction 2 has reached the maximum number of active wars (' .. Config.Conflict.maxActiveWars .. ').' })
        return
    end

    -- Enforce minimum cooldown between wars for each faction
    local cooldown1 = MySQL.query.await([[
        SELECT TIMESTAMPDIFF(SECOND, NOW(), expires_at) AS secs_remaining
        FROM faction_cooldowns WHERE faction_id = ? AND type = 'war' AND expires_at > NOW() LIMIT 1
    ]], { f1 })
    local cooldown2 = MySQL.query.await([[
        SELECT TIMESTAMPDIFF(SECOND, NOW(), expires_at) AS secs_remaining
        FROM faction_cooldowns WHERE faction_id = ? AND type = 'war' AND expires_at > NOW() LIMIT 1
    ]], { f2 })

    if cooldown1 and #cooldown1 > 0 then
        local mins = math.ceil(cooldown1[1].secs_remaining / 60)
        lib.notify(source, { type = 'error', description = 'Faction 1 still has a war cooldown: ' .. mins .. ' minute(s) remaining.' })
        return
    end
    if cooldown2 and #cooldown2 > 0 then
        local mins = math.ceil(cooldown2[1].secs_remaining / 60)
        lib.notify(source, { type = 'error', description = 'Faction 2 still has a war cooldown: ' .. mins .. ' minute(s) remaining.' })
        return
    end

    -- Insert the conflict with auto-end time based on Config.Conflict.warDuration
    MySQL.insert([[
        INSERT INTO faction_conflicts (faction1_id, faction2_id, type, status, reason, ended_at)
        VALUES (?, ?, ?, 'active', ?, DATE_ADD(NOW(), INTERVAL ? SECOND))
    ]], { f1, f2, safeType, safeReason, Config.Conflict.warDuration })

    RefreshFactionWarCount(f1)
    RefreshFactionWarCount(f2)

    -- Apply war cooldowns so factions can't immediately start another war
    MySQL.query([[
        INSERT INTO faction_cooldowns (faction_id, type, expires_at, reason)
        VALUES (?, 'war', DATE_ADD(NOW(), INTERVAL ? SECOND), 'War started')
        ON DUPLICATE KEY UPDATE expires_at = DATE_ADD(NOW(), INTERVAL ? SECOND), reason = 'War started'
    ]], { f1, Config.Conflict.minCooldown, Config.Conflict.minCooldown })
    MySQL.query([[
        INSERT INTO faction_cooldowns (faction_id, type, expires_at, reason)
        VALUES (?, 'war', DATE_ADD(NOW(), INTERVAL ? SECOND), 'War started')
        ON DUPLICATE KEY UPDATE expires_at = DATE_ADD(NOW(), INTERVAL ? SECOND), reason = 'War started'
    ]], { f2, Config.Conflict.minCooldown, Config.Conflict.minCooldown })

    -- Notify all online members of both factions
    NotifyFactionMembers(f1, 'faction:receiveNotification', {
        type = 'error', title = 'War Declared',
        description = 'Your faction is now at war! Stay alert.'
    })
    NotifyFactionMembers(f2, 'faction:receiveNotification', {
        type = 'error', title = 'War Declared',
        description = 'Your faction is now at war! Stay alert.'
    })

    lib.notify(source, { type = 'success', description = 'Conflict created. War will auto-end in ' .. math.floor(Config.Conflict.warDuration / 60) .. ' minutes.' })

    -- Webhook
    if Config.Webhooks.enabled and Config.Webhooks.weaponLogging ~= '' then
        local f1data = GetFactionById(f1)
        local f2data = GetFactionById(f2)
        PerformHttpRequest(Config.Webhooks.weaponLogging, function() end, 'POST',
            json.encode({ content = string.format(
                '**War Declared** | %s vs %s | Type: %s | Reason: %s | Duration: %d mins',
                f1data and f1data.label or f1, f2data and f2data.label or f2, safeType,
                safeReason or 'None', math.floor(Config.Conflict.warDuration / 60)) }),
            { ['Content-Type'] = 'application/json' })
    end

    -- Push updated list to all online admins
    PushConflictsToAdmins()
end)

-- Admin: end war by ID (draw/no winner)
RegisterNetEvent('faction:adminEndWar', function(warId)
    local source = source
    if not IsAdminPlayer(source) then return end

    local wid = tonumber(warId)
    if not wid then return end

    EndWar(wid, nil)
    lib.notify(source, { type = 'success', description = 'War ended.' })
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

    lib.notify(source, { type = 'success', description = 'War duration set.' })
    PushConflictsToAdmins()
end)
