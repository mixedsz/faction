-- Admin panel server-side events: factions, members, weapons, reports, CKs, rules, violations

-- ============================================================
-- FACTIONS
-- ============================================================

RegisterNetEvent('faction:adminGetFactions', function()
    local source = source
    if not IsAdminPlayer(source) then return end

    local factions = MySQL.query.await([[
        SELECT f.*,
               (SELECT COUNT(*) FROM faction_members WHERE faction_id = f.id) AS member_count
        FROM faction_factions f
        ORDER BY f.label
    ]])

    TriggerClientEvent('faction:adminReceiveFactions', source, factions or {})
end)

RegisterNetEvent('faction:adminCreateFaction', function(name, label, ftype)
    local source = source
    if not IsAdminPlayer(source) then return end

    local safeName  = tostring(name or ''):lower():gsub('%s+', '_'):sub(1, 64)
    local safeLabel = tostring(label or ''):sub(1, 128)
    local safeType  = tostring(ftype or 'gang'):sub(1, 32)

    if safeName == '' or safeLabel == '' then
        lib.notify(source, { type = 'error', description = 'Name and label are required.' })
        return
    end

    -- Check uniqueness
    local existing = MySQL.query.await('SELECT id FROM faction_factions WHERE name = ? LIMIT 1', { safeName })
    if existing and #existing > 0 then
        lib.notify(source, { type = 'error', description = 'A faction with that name already exists.' })
        return
    end

    MySQL.insert('INSERT INTO faction_factions (name, label, type) VALUES (?, ?, ?)', {
        safeName, safeLabel, safeType
    })

    lib.notify(source, { type = 'success', description = 'Faction "' .. safeLabel .. '" created.' })
    TriggerClientEvent('faction:refreshFactionList', source)
    -- Refresh admin overview
    TriggerEvent('faction:adminGetFactions')
end)

RegisterNetEvent('faction:adminDeleteFaction', function(factionId)
    local source = source
    if not IsAdminPlayer(source) then return end

    local fid = tonumber(factionId)
    if not fid then return end

    -- Remove members first
    MySQL.update('DELETE FROM faction_members WHERE faction_id = ?', { fid })
    MySQL.update('DELETE FROM faction_territory WHERE faction_id = ?', { fid })
    MySQL.update('DELETE FROM faction_weapons WHERE faction_id = ?', { fid })
    MySQL.update('DELETE FROM faction_cooldowns WHERE faction_id = ?', { fid })
    MySQL.update('DELETE FROM faction_violations WHERE faction_id = ?', { fid })
    MySQL.update('DELETE FROM faction_factions WHERE id = ?', { fid })

    lib.notify(source, { type = 'success', description = 'Faction deleted.' })
end)

RegisterNetEvent('faction:adminUpdateFaction', function(factionId, updates)
    local source = source
    if not IsAdminPlayer(source) then return end

    local fid = tonumber(factionId)
    if not fid then return end

    local sets = {}
    local vals = {}

    if updates.name then
        local n = tostring(updates.name):lower():gsub('%s+', '_'):sub(1, 64)
        table.insert(sets, 'name = ?')
        table.insert(vals, n)
    end
    if updates.label then
        table.insert(sets, 'label = ?')
        table.insert(vals, tostring(updates.label):sub(1, 128))
    end
    if updates.type then
        table.insert(sets, 'type = ?')
        table.insert(vals, tostring(updates.type):sub(1, 32))
    end
    if updates.reputation ~= nil then
        table.insert(sets, 'reputation = ?')
        table.insert(vals, tonumber(updates.reputation) or 0)
    end
    if updates.gun_drop_eligible ~= nil then
        table.insert(sets, 'gun_drop_eligible = ?')
        table.insert(vals, updates.gun_drop_eligible and 1 or 0)
    end

    if #sets == 0 then return end

    table.insert(vals, fid)
    MySQL.update('UPDATE faction_factions SET ' .. table.concat(sets, ', ') .. ' WHERE id = ?', vals)

    lib.notify(source, { type = 'success', description = 'Faction updated.' })
end)

-- ============================================================
-- MEMBERS
-- ============================================================

RegisterNetEvent('faction:adminGetFactionMembers', function(factionId)
    local source = source
    if not IsAdminPlayer(source) then return end

    local fid = tonumber(factionId)
    if not fid then return end

    local members = MySQL.query.await([[
        SELECT id, identifier, player_name, rank, warnings, last_warning_reason,
               cks_involved, reputation_contribution, last_active
        FROM faction_members
        WHERE faction_id = ?
        ORDER BY
            CASE rank
                WHEN 'boss' THEN 1
                WHEN 'big_homie' THEN 2
                WHEN 'shot_caller' THEN 3
                WHEN 'member' THEN 4
                WHEN 'runner' THEN 5
                ELSE 6
            END, player_name
    ]], { fid })

    TriggerClientEvent('faction:adminReceiveFactionMembers', source, fid, members or {})
end)

RegisterNetEvent('faction:adminInviteMember', function(factionId, targetIdentifierOrServerId, rank)
    local source = source
    if not IsAdminPlayer(source) then return end

    local fid = tonumber(factionId)
    if not fid then return end

    local faction = GetFactionById(fid)
    if not faction then
        lib.notify(source, { type = 'error', description = 'Faction not found.' })
        return
    end

    local safeRank = (Config.Ranks[rank] and rank) or 'runner'
    local rankLabel = Config.Ranks[safeRank] and Config.Ranks[safeRank].label or safeRank

    -- Resolve target: numeric = server ID, string = identifier
    local targetPlayer = nil
    local targetId = tonumber(targetIdentifierOrServerId)
    if targetId then
        targetPlayer = ESX.GetPlayerFromId(targetId)
    else
        targetPlayer = ESX.GetPlayerFromIdentifier(tostring(targetIdentifierOrServerId))
    end

    if not targetPlayer then
        lib.notify(source, { type = 'error', description = 'Player not found or not online.' })
        return
    end

    -- Check not already in a faction
    local existing = MySQL.query.await('SELECT id FROM faction_members WHERE identifier = ? LIMIT 1', { targetPlayer.identifier })
    if existing and #existing > 0 then
        lib.notify(source, { type = 'error', description = 'That player is already in a faction.' })
        return
    end

    TriggerClientEvent('faction:receiveInvite', targetPlayer.source, {
        factionId    = fid,
        factionLabel = faction.label,
        rank         = safeRank,
        rankLabel    = rankLabel
    })

    lib.notify(source, { type = 'info', description = 'Invite sent to ' .. targetPlayer.getName() })
end)

RegisterNetEvent('faction:adminKickMember', function(factionId, memberIdOrIdentifier)
    local source = source
    if not IsAdminPlayer(source) then return end

    local fid = tonumber(factionId)
    if not fid then return end

    local member = nil
    local membIdInt = tonumber(memberIdOrIdentifier)
    if membIdInt then
        local rows = MySQL.query.await('SELECT id, identifier FROM faction_members WHERE id = ? AND faction_id = ? LIMIT 1', { membIdInt, fid })
        member = rows and rows[1] or nil
    else
        local rows = MySQL.query.await('SELECT id, identifier FROM faction_members WHERE identifier = ? AND faction_id = ? LIMIT 1', { tostring(memberIdOrIdentifier), fid })
        member = rows and rows[1] or nil
    end

    if not member then
        lib.notify(source, { type = 'error', description = 'Member not found in that faction.' })
        return
    end

    MySQL.update('DELETE FROM faction_members WHERE id = ?', { member.id })

    local kicked = ESX.GetPlayerFromIdentifier(member.identifier)
    if kicked then
        lib.notify(kicked.source, { type = 'error', description = 'You have been removed from your faction.' })
        TriggerClientEvent('faction:receiveFactionData', kicked.source, { faction = nil, rank = nil })
    end

    lib.notify(source, { type = 'success', description = 'Member kicked.' })
end)

RegisterNetEvent('faction:adminSetMemberRank', function(factionId, memberIdOrIdentifier, rank)
    local source = source
    if not IsAdminPlayer(source) then return end

    local fid = tonumber(factionId)
    if not fid or not Config.Ranks[rank] then return end

    local membIdInt = tonumber(memberIdOrIdentifier)
    if membIdInt then
        MySQL.update('UPDATE faction_members SET rank = ? WHERE id = ? AND faction_id = ?', { rank, membIdInt, fid })
    else
        MySQL.update('UPDATE faction_members SET rank = ? WHERE identifier = ? AND faction_id = ?', { rank, tostring(memberIdOrIdentifier), fid })
    end

    lib.notify(source, { type = 'success', description = 'Rank updated.' })
end)

RegisterNetEvent('faction:adminTransferBoss', function(factionId, memberIdOrIdentifier)
    local source = source
    if not IsAdminPlayer(source) then return end

    local fid = tonumber(factionId)
    if not fid then return end

    -- Demote current boss to shot_caller
    MySQL.update("UPDATE faction_members SET rank = 'shot_caller' WHERE faction_id = ? AND rank = 'boss'", { fid })

    -- Promote new boss
    local membIdInt = tonumber(memberIdOrIdentifier)
    if membIdInt then
        MySQL.update("UPDATE faction_members SET rank = 'boss' WHERE id = ? AND faction_id = ?", { membIdInt, fid })
    else
        MySQL.update("UPDATE faction_members SET rank = 'boss' WHERE identifier = ? AND faction_id = ?", { tostring(memberIdOrIdentifier), fid })
    end

    lib.notify(source, { type = 'success', description = 'Leadership transferred.' })
end)

-- ============================================================
-- WEAPONS
-- ============================================================

RegisterNetEvent('faction:adminGetFactionsForWeapon', function()
    local source = source
    if not IsAdminPlayer(source) then return end

    local factions = MySQL.query.await('SELECT id, name, label FROM faction_factions ORDER BY label')
    TriggerClientEvent('faction:adminReceiveFactionsForWeapon', source, factions or {})
end)

RegisterNetEvent('faction:adminGetFactionWeapons', function(factionId)
    local source = source
    if not IsAdminPlayer(source) then return end

    local fid = tonumber(factionId)
    if not fid then return end

    local faction = GetFactionById(fid)
    local weapons = MySQL.query.await([[
        SELECT id, weapon_name, serial_number, weapon_hash, holder_identifier, holder_name, registered_at
        FROM faction_weapons
        WHERE faction_id = ?
        ORDER BY weapon_name
    ]], { fid })

    TriggerClientEvent('faction:adminReceiveFactionWeapons', source, fid, faction and faction.label or 'Unknown', weapons or {})
end)

RegisterNetEvent('faction:adminRegisterWeapon', function(factionId, weaponName, serialNumber, weaponHash)
    local source = source
    if not IsAdminPlayer(source) then return end

    local fid = tonumber(factionId)
    if not fid then return end

    local safeName   = tostring(weaponName or ''):sub(1, 128)
    local safeSerial = tostring(serialNumber or ''):sub(1, 128)
    local safeHash   = weaponHash and tostring(weaponHash):sub(1, 64) or nil

    if safeName == '' or safeSerial == '' then
        lib.notify(source, { type = 'error', description = 'Weapon name and serial number are required.' })
        return
    end

    -- Check serial uniqueness
    local existing = MySQL.query.await('SELECT id FROM faction_weapons WHERE serial_number = ? LIMIT 1', { safeSerial })
    if existing and #existing > 0 then
        lib.notify(source, { type = 'error', description = 'A weapon with that serial number already exists.' })
        return
    end

    MySQL.insert('INSERT INTO faction_weapons (faction_id, weapon_name, serial_number, weapon_hash) VALUES (?, ?, ?, ?)', {
        fid, safeName, safeSerial, safeHash
    })

    lib.notify(source, { type = 'success', description = 'Weapon registered.' })

    -- Notify faction members
    NotifyFactionMembers(fid, 'faction:refreshWeapons', {})

    -- Webhook
    if Config.Webhooks.enabled and Config.Webhooks.weaponLogging ~= '' then
        PerformHttpRequest(Config.Webhooks.weaponLogging, function() end, 'POST',
            json.encode({ content = string.format('**Weapon Registered** | Faction ID: %d | Weapon: %s | Serial: %s', fid, safeName, safeSerial) }),
            { ['Content-Type'] = 'application/json' })
    end
end)

RegisterNetEvent('faction:adminDeleteWeapon', function(weaponId)
    local source = source
    if not IsAdminPlayer(source) then return end

    local wid = tonumber(weaponId)
    if not wid then return end

    local weapon = MySQL.query.await('SELECT faction_id FROM faction_weapons WHERE id = ? LIMIT 1', { wid })
    MySQL.update('DELETE FROM faction_weapons WHERE id = ?', { wid })

    if weapon and #weapon > 0 then
        NotifyFactionMembers(weapon[1].faction_id, 'faction:refreshWeapons', {})
    end

    lib.notify(source, { type = 'success', description = 'Weapon deleted.' })
end)

-- ============================================================
-- VIOLATIONS
-- ============================================================

RegisterNetEvent('faction:adminGetViolations', function()
    local source = source
    if not IsAdminPlayer(source) then return end

    local violations = MySQL.query.await([[
        SELECT v.*, f.label AS faction_label
        FROM faction_violations v
        LEFT JOIN faction_factions f ON f.id = v.faction_id
        ORDER BY v.created_at DESC
        LIMIT 100
    ]])

    TriggerClientEvent('faction:adminReceiveViolations', source, violations or {})
end)

-- ============================================================
-- REPORTS
-- ============================================================

RegisterNetEvent('faction:adminGetReports', function()
    local source = source
    if not IsAdminPlayer(source) then return end

    local reports = MySQL.query.await([[
        SELECT r.*,
               f.label  AS faction_label,
               tf.label AS target_faction_label
        FROM faction_reports r
        LEFT JOIN faction_factions f  ON f.id  = r.faction_id
        LEFT JOIN faction_factions tf ON tf.id = r.target_faction_id
        ORDER BY
            CASE r.status WHEN 'pending' THEN 0 ELSE 1 END,
            r.created_at DESC
    ]])

    TriggerClientEvent('faction:adminReceiveReports', source, reports or {})
end)

RegisterNetEvent('faction:adminUpdateReport', function(reportId, status)
    local source = source
    if not IsAdminPlayer(source) then return end

    local rid = tonumber(reportId)
    if not rid then return end

    local allowed = { pending = true, approved = true, rejected = true }
    if not allowed[status] then return end

    MySQL.update('UPDATE faction_reports SET status = ? WHERE id = ?', { status, rid })

    -- If approved, create a violation for the target faction
    if status == 'approved' then
        local report = MySQL.query.await('SELECT * FROM faction_reports WHERE id = ? LIMIT 1', { rid })
        if report and #report > 0 then
            local r = report[1]
            local targetFid = r.target_faction_id or r.faction_id
            MySQL.insert([[
                INSERT INTO faction_violations (faction_id, member_identifier, type, details)
                VALUES (?, ?, ?, ?)
            ]], { targetFid, r.reporter_identifier, r.report_type, r.details })
        end
    end

    lib.notify(source, { type = 'success', description = 'Report updated.' })
end)

RegisterNetEvent('faction:adminDeleteReport', function(reportId)
    local source = source
    if not IsAdminPlayer(source) then return end

    local rid = tonumber(reportId)
    if not rid then return end

    MySQL.update('DELETE FROM faction_reports WHERE id = ?', { rid })
    lib.notify(source, { type = 'success', description = 'Report deleted.' })
end)

-- ============================================================
-- CK REQUESTS
-- ============================================================

RegisterNetEvent('faction:adminGetPendingCKs', function(statusFilter)
    local source = source
    if not IsAdminPlayer(source) then return end

    local query
    local params

    if statusFilter and statusFilter ~= '' then
        query  = [[
            SELECT ck.*, f.label AS faction_label
            FROM faction_ck_requests ck
            LEFT JOIN faction_factions f ON f.id = ck.requesting_faction_id
            WHERE ck.status = ?
            ORDER BY ck.created_at DESC
        ]]
        params = { statusFilter }
    else
        query  = [[
            SELECT ck.*, f.label AS faction_label
            FROM faction_ck_requests ck
            LEFT JOIN faction_factions f ON f.id = ck.requesting_faction_id
            ORDER BY
                CASE ck.status WHEN 'pending' THEN 0 ELSE 1 END,
                ck.created_at DESC
        ]]
        params = {}
    end

    local cks = MySQL.query.await(query, params)
    TriggerClientEvent('faction:adminReceivePendingCKs', source, cks or {})
end)

RegisterNetEvent('faction:adminUpdateCK', function(ckId, status)
    local source = source
    if not IsAdminPlayer(source) then return end

    local cid = tonumber(ckId)
    if not cid then return end

    local allowed = { pending = true, approved = true, rejected = true, executed = true }
    if not allowed[status] then return end

    MySQL.update('UPDATE faction_ck_requests SET status = ? WHERE id = ?', { status, cid })

    -- If executed: update member CK count and reputation
    if status == 'executed' then
        local ck = MySQL.query.await('SELECT * FROM faction_ck_requests WHERE id = ? LIMIT 1', { cid })
        if ck and #ck > 0 then
            local c = ck[1]
            -- Increment CKs involved for all members of requesting faction
            MySQL.update('UPDATE faction_members SET cks_involved = cks_involved + 1 WHERE faction_id = ?', { c.requesting_faction_id })
            -- Reputation gain for requesting faction
            MySQL.update('UPDATE faction_factions SET reputation = reputation + ? WHERE id = ?', { 10, c.requesting_faction_id })
        end
    end

    lib.notify(source, { type = 'success', description = 'CK request updated.' })
end)

-- ============================================================
-- RULES
-- ============================================================

RegisterNetEvent('faction:adminGetRules', function()
    local source = source
    if not IsAdminPlayer(source) then return end

    local rules = MySQL.query.await([[
        SELECT r.*, f.label AS faction_label
        FROM faction_rules r
        LEFT JOIN faction_factions f ON f.id = r.faction_id
        ORDER BY r.is_global DESC, r.faction_id ASC, r.`order` ASC, r.id ASC
    ]])

    local factions = MySQL.query.await('SELECT id, name, label FROM faction_factions ORDER BY label')

    TriggerClientEvent('faction:adminReceiveRules', source, rules or {}, factions or {})
end)

RegisterNetEvent('faction:adminCreateRule', function(data)
    local source = source
    if not IsAdminPlayer(source) then return end

    local title    = tostring(data.title or ''):sub(1, 256)
    local content  = tostring(data.content or ''):sub(1, 4000)
    local isGlobal = data.isGlobal and 1 or 0
    local fid      = not isGlobal and tonumber(data.factionId) or nil
    local order    = tonumber(data.order) or 0

    if title == '' or content == '' then
        lib.notify(source, { type = 'error', description = 'Title and content are required.' })
        return
    end

    MySQL.insert('INSERT INTO faction_rules (faction_id, title, content, is_global, `order`) VALUES (?, ?, ?, ?, ?)', {
        fid, title, content, isGlobal, order
    })

    lib.notify(source, { type = 'success', description = 'Rule created.' })
    TriggerClientEvent('faction:adminRefreshRules', source)
end)

RegisterNetEvent('faction:adminUpdateRule', function(data)
    local source = source
    if not IsAdminPlayer(source) then return end

    local rid      = tonumber(data.ruleId)
    if not rid then return end

    local title    = tostring(data.title or ''):sub(1, 256)
    local content  = tostring(data.content or ''):sub(1, 4000)
    local isGlobal = data.isGlobal and 1 or 0
    local fid      = not isGlobal and tonumber(data.factionId) or nil
    local order    = tonumber(data.order) or 0

    MySQL.update('UPDATE faction_rules SET title = ?, content = ?, is_global = ?, faction_id = ?, `order` = ? WHERE id = ?', {
        title, content, isGlobal, fid, order, rid
    })

    lib.notify(source, { type = 'success', description = 'Rule updated.' })
    TriggerClientEvent('faction:adminRefreshRules', source)
end)

RegisterNetEvent('faction:adminDeleteRule', function(ruleId)
    local source = source
    if not IsAdminPlayer(source) then return end

    local rid = tonumber(ruleId)
    if not rid then return end

    MySQL.update('DELETE FROM faction_rules WHERE id = ?', { rid })
    lib.notify(source, { type = 'success', description = 'Rule deleted.' })
    TriggerClientEvent('faction:adminRefreshRules', source)
end)
