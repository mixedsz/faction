-- Member management: list, invite, kick, rank, warnings

-- Get members of the player's faction
RegisterNetEvent('faction:getMembers', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then
        TriggerClientEvent('faction:receiveMembers', source, {})
        return
    end

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
    ]], { row.faction_id })

    TriggerClientEvent('faction:receiveMembers', source, members or {})
end)

-- Invite member (triggered from member's faction panel - boss/big_homie only)
RegisterNetEvent('faction:inviteMember', function(targetServerId, rank)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then return end

    if row.rank ~= 'boss' and row.rank ~= 'big_homie' then
        lib.notify(source, { type = 'error', description = 'Insufficient rank to invite members.' })
        return
    end

    local targetPlayer = ESX.GetPlayerFromId(tonumber(targetServerId))
    if not targetPlayer then
        lib.notify(source, { type = 'error', description = 'Player not found.' })
        return
    end

    -- Check target isn't already in a faction
    local existing = MySQL.query.await('SELECT id FROM faction_members WHERE identifier = ? LIMIT 1', { targetPlayer.identifier })
    if existing and #existing > 0 then
        lib.notify(source, { type = 'error', description = 'That player is already in a faction.' })
        return
    end

    local safeRank = (Config.Ranks[rank] and rank) or 'runner'
    local faction  = GetFactionById(row.faction_id)
    local rankLabel = Config.Ranks[safeRank] and Config.Ranks[safeRank].label or safeRank

    TriggerClientEvent('faction:receiveInvite', targetPlayer.source, {
        factionId    = row.faction_id,
        factionLabel = faction and faction.label or 'Unknown',
        rank         = safeRank,
        rankLabel    = rankLabel
    })

    lib.notify(source, { type = 'info', description = 'Invite sent to ' .. targetPlayer.getName() })
end)

-- Kick member (self-service by boss/big_homie)
RegisterNetEvent('faction:kickMember', function(memberId)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then return end

    if row.rank ~= 'boss' and row.rank ~= 'big_homie' then
        lib.notify(source, { type = 'error', description = 'Insufficient rank to kick members.' })
        return
    end

    local membIdInt = tonumber(memberId)
    if not membIdInt then return end

    -- Cannot kick self
    if membIdInt == row.id then
        lib.notify(source, { type = 'error', description = 'You cannot kick yourself.' })
        return
    end

    -- Verify member belongs to same faction and isn't boss
    local member = MySQL.query.await('SELECT id, rank, identifier FROM faction_members WHERE id = ? AND faction_id = ? LIMIT 1', {
        membIdInt, row.faction_id
    })
    if not member or #member == 0 then return end
    if member[1].rank == 'boss' then
        lib.notify(source, { type = 'error', description = 'Cannot kick the boss.' })
        return
    end

    MySQL.update('DELETE FROM faction_members WHERE id = ? AND faction_id = ?', { membIdInt, row.faction_id })

    -- Notify kicked player
    local kickedPlayer = ESX.GetPlayerFromIdentifier(member[1].identifier)
    if kickedPlayer then
        lib.notify(kickedPlayer.source, { type = 'error', description = 'You have been removed from your faction.' })
        TriggerClientEvent('faction:receiveFactionData', kickedPlayer.source, { faction = nil, rank = nil })
    end

    lib.notify(source, { type = 'success', description = 'Member kicked.' })
end)

-- Set member rank (self-service by boss/big_homie)
RegisterNetEvent('faction:setMemberRank', function(memberId, newRank)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then return end

    if row.rank ~= 'boss' and row.rank ~= 'big_homie' then
        lib.notify(source, { type = 'error', description = 'Insufficient rank.' })
        return
    end

    if not Config.Ranks[newRank] then
        lib.notify(source, { type = 'error', description = 'Invalid rank.' })
        return
    end

    local membIdInt = tonumber(memberId)
    if not membIdInt then return end

    MySQL.update('UPDATE faction_members SET rank = ? WHERE id = ? AND faction_id = ?', {
        newRank, membIdInt, row.faction_id
    })

    lib.notify(source, { type = 'success', description = 'Rank updated.' })
end)
