-- Main Server File: player session management, shared helpers, and misc events

ESX = exports['es_extended']:getSharedObject()

-- Helper: check if a player is an admin (by ESX group)
function IsAdminPlayer(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false end
    local group = xPlayer.getGroup()
    for _, g in ipairs(Config.AdminGroups) do
        if group == g then return true end
    end
    return false
end

-- Helper: get the faction membership record for a player identifier
function GetPlayerFactionData(identifier)
    local result = MySQL.query.await([[
        SELECT fm.*, f.name AS faction_name, f.label AS faction_label, f.type AS faction_type,
               f.reputation, f.active_wars, f.max_wars, f.gun_drop_eligible
        FROM faction_members fm
        JOIN faction_factions f ON f.id = fm.faction_id
        WHERE fm.identifier = ?
        LIMIT 1
    ]], { identifier })

    if not result or #result == 0 then return nil end
    return result[1]
end

-- Helper: get the raw faction row by id
function GetFactionById(factionId)
    local result = MySQL.query.await('SELECT * FROM faction_factions WHERE id = ? LIMIT 1', { factionId })
    if not result or #result == 0 then return nil end
    return result[1]
end

-- Helper: update active_wars count on a faction
function RefreshFactionWarCount(factionId)
    local result = MySQL.query.await([[
        SELECT COUNT(*) AS cnt FROM faction_conflicts
        WHERE (faction1_id = ? OR faction2_id = ?) AND status = 'active'
    ]], { factionId, factionId })
    local cnt = result and result[1] and result[1].cnt or 0
    MySQL.update('UPDATE faction_factions SET active_wars = ? WHERE id = ?', { cnt, factionId })
end

-- Send faction data to a specific player
function SendFactionDataToPlayer(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    local identifier = xPlayer.identifier

    local row = GetPlayerFactionData(identifier)
    if not row then
        TriggerClientEvent('faction:receiveFactionData', source, { faction = nil, rank = nil })
        return
    end

    -- Update player name in members table
    MySQL.update('UPDATE faction_members SET player_name = ?, last_active = ? WHERE identifier = ? AND faction_id = ?', {
        xPlayer.getName(), os.time(), identifier, row.faction_id
    })

    local factionData = {
        id         = row.faction_id,
        name       = row.faction_name,
        label      = row.faction_label,
        type       = row.faction_type,
        reputation = row.reputation,
        active_wars = row.active_wars,
        max_wars   = row.max_wars,
        gun_drop_eligible = row.gun_drop_eligible == 1 or row.gun_drop_eligible == true
    }

    -- Include gun drop cooldown so clients can show a countdown
    local cdResult = MySQL.query.await([[
        SELECT GREATEST(0, TIMESTAMPDIFF(SECOND, NOW(), expires_at)) AS secs
        FROM faction_cooldowns
        WHERE faction_id = ? AND type = 'gun_drop' AND expires_at > NOW()
        LIMIT 1
    ]], { row.faction_id })
    factionData.gun_drop_cooldown_secs = cdResult and #cdResult > 0 and cdResult[1].secs or 0

    TriggerClientEvent('faction:receiveFactionData', source, {
        faction = factionData,
        rank    = row.rank
    })
end

-- Player requests their own faction data
RegisterNetEvent('faction:getFactionData', function()
    local source = source
    SendFactionDataToPlayer(source)
end)

-- Admin check before opening admin panel
RegisterNetEvent('faction:checkAdminAndOpenPanel', function()
    local source = source
    if IsAdminPlayer(source) then
        TriggerClientEvent('faction:openAdminPanel', source)
    else
        Notify(source, 'error', 'You do not have permission to access the admin panel.')
    end
end)

-- Player responds to a faction invite
RegisterNetEvent('faction:respondToInvite', function(factionId, accepted, rank)
    local source = source
    if not accepted then return end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    local identifier = xPlayer.identifier

    -- Verify no existing membership
    local existing = MySQL.query.await('SELECT id FROM faction_members WHERE identifier = ? LIMIT 1', { identifier })
    if existing and #existing > 0 then
        Notify(source, 'error', 'You are already in a faction.')
        return
    end

    local faction = GetFactionById(factionId)
    if not faction then
        Notify(source, 'error', 'Faction no longer exists.')
        return
    end

    local safeRank = (Config.Ranks[rank] and rank) or 'runner'

    MySQL.insert('INSERT INTO faction_members (faction_id, identifier, player_name, rank) VALUES (?, ?, ?, ?)', {
        factionId, identifier, xPlayer.getName(), safeRank
    })

    Notify(source, 'success', 'You have joined ' .. faction.label .. '!')
    TriggerClientEvent('faction:requestFactionData', source)
end)

-- Notify all members of a faction (online only)
function NotifyFactionMembers(factionId, eventName, data)
    local members = MySQL.query.await('SELECT identifier FROM faction_members WHERE faction_id = ?', { factionId })
    if not members then return end
    local onlineMap = {}
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        if src then
            local p = ESX.GetPlayerFromId(src)
            if p and p.identifier then onlineMap[p.identifier] = src end
        end
    end
    for _, m in ipairs(members) do
        local src = onlineMap[m.identifier]
        if src then TriggerClientEvent(eventName, src, data) end
    end
end

-- Send a custom notification to a specific player (uses NUI toast, no ox_lib)
function Notify(src, ntype, message, title)
    TriggerClientEvent('faction:receiveNotification', src, {
        type        = ntype or 'info',
        description = message or '',
        title       = title or nil
    })
end

-- Submit a report
RegisterNetEvent('faction:submitReport', function(reportType, details, targetFactionId)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then
        Notify(source, 'error', 'You are not in a faction.')
        return
    end

    local safeType = tostring(reportType):sub(1, 64)
    local safeDetails = tostring(details):sub(1, 2000)
    local targetId = tonumber(targetFactionId) or nil

    MySQL.insert([[
        INSERT INTO faction_reports (faction_id, target_faction_id, reporter_identifier, reporter_name, report_type, details)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { row.faction_id, targetId, xPlayer.identifier, xPlayer.getName(), safeType, safeDetails })

    Notify(source, 'success', 'Report submitted successfully.')

    -- Notify webhooks if configured
    if Config.Webhooks.enabled and Config.Webhooks.reportSubmitted ~= '' then
        PerformHttpRequest(Config.Webhooks.reportSubmitted, function() end, 'POST',
            json.encode({ content = string.format('**Report Submitted** by %s | Type: %s | Details: %s', xPlayer.getName(), safeType, safeDetails:sub(1, 200)) }),
            { ['Content-Type'] = 'application/json' })
    end
end)

-- Get faction list for report (other factions)
RegisterNetEvent('faction:getFactionListForReport', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    local myFactionId = row and row.faction_id or 0

    local factions = MySQL.query.await('SELECT id, name, label FROM faction_factions WHERE id != ? ORDER BY label', { myFactionId })
    TriggerClientEvent('faction:receiveFactionListForReport', source, factions or {})
end)

-- Get warnings for current faction members
RegisterNetEvent('faction:getWarnings', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then
        TriggerClientEvent('faction:receiveWarnings', source, {})
        return
    end

    local warnings = MySQL.query.await([[
        SELECT player_name AS member_name, warnings, last_warning_reason
        FROM faction_members
        WHERE faction_id = ? AND warnings > 0
        ORDER BY warnings DESC
    ]], { row.faction_id })

    TriggerClientEvent('faction:receiveWarnings', source, warnings or {})
end)

-- Add warning to a member
RegisterNetEvent('faction:addWarning', function(memberId, reason)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then return end

    -- Only boss/big_homie can add warnings
    if row.rank ~= 'boss' and row.rank ~= 'big_homie' then
        Notify(source, 'error', 'Insufficient rank to add warnings.')
        return
    end

    local safeReason = tostring(reason):sub(1, 500)
    local membIdInt = tonumber(memberId)

    if membIdInt then
        MySQL.update('UPDATE faction_members SET warnings = warnings + 1, last_warning_reason = ? WHERE id = ? AND faction_id = ?', {
            safeReason, membIdInt, row.faction_id
        })
    end

    Notify(source, 'success', 'Warning added.')
end)

-- Get faction rules (member side)
RegisterNetEvent('faction:getRules', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then
        TriggerClientEvent('faction:receiveRules', source, {})
        return
    end

    local rules = MySQL.query.await([[
        SELECT id, faction_id, is_global, `order`,
               title AS rule_title,
               content AS rule_content
        FROM faction_rules
        WHERE is_global = 1 OR faction_id = ?
        ORDER BY is_global DESC, `order` ASC, id ASC
    ]], { row.faction_id })

    TriggerClientEvent('faction:receiveRules', source, rules or {})
end)
