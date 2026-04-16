-- Territory management

-- Get territory for player's faction
RegisterNetEvent('faction:getTerritory', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then
        TriggerClientEvent('faction:receiveTerritory', source, {})
        return
    end

    local territory = MySQL.query.await([[
        SELECT t.*, f.label AS faction_label
        FROM faction_territory t
        LEFT JOIN faction_factions f ON f.id = t.faction_id
        WHERE t.faction_id = ?
        ORDER BY t.name
    ]], { row.faction_id })

    -- Attach nearby faction info
    local enriched = {}
    for _, terr in ipairs(territory or {}) do
        -- Find nearby factions (other factions with territory within disputeRadius * 2)
        local nearby = MySQL.query.await([[
            SELECT t2.faction_id, f.label
            FROM faction_territory t2
            JOIN faction_factions f ON f.id = t2.faction_id
            WHERE t2.faction_id != ?
            AND SQRT(POW(t2.x - ?, 2) + POW(t2.y - ?, 2)) < ?
            LIMIT 3
        ]], { row.faction_id, terr.x, terr.y, Config.Territory.disputeRadius * 2 })

        local nearbyFactions = {}
        for _, nb in ipairs(nearby or {}) do
            table.insert(nearbyFactions, { faction = { label = nb.label } })
        end

        terr.nearby_factions = nearbyFactions
        table.insert(enriched, terr)
    end

    TriggerClientEvent('faction:receiveTerritory', source, enriched)
end)

-- Claim territory (boss/big_homie only)
RegisterNetEvent('faction:claimTerritory', function(data)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then
        lib.notify(source, { type = 'error', description = 'You are not in a faction.' })
        return
    end

    if row.rank ~= 'boss' and row.rank ~= 'big_homie' then
        lib.notify(source, { type = 'error', description = 'Only Boss or Big Homie can claim territory.' })
        return
    end

    -- Check claim cooldown
    local cooldown = MySQL.query.await([[
        SELECT expires_at FROM faction_cooldowns
        WHERE faction_id = ? AND type = 'territory_claim' AND expires_at > NOW()
        LIMIT 1
    ]], { row.faction_id })

    if cooldown and #cooldown > 0 then
        lib.notify(source, { type = 'error', description = 'Your faction is on territory claim cooldown.' })
        return
    end

    -- Check minimum active members
    local activeMemberCount = 0
    local members = MySQL.query.await('SELECT identifier FROM faction_members WHERE faction_id = ?', { row.faction_id })
    for _, m in ipairs(members or {}) do
        if ESX.GetPlayerFromIdentifier(m.identifier) then
            activeMemberCount = activeMemberCount + 1
        end
    end

    if activeMemberCount < Config.Territory.minMembers then
        lib.notify(source, { type = 'error', description = string.format('Need at least %d active members online to claim territory.', Config.Territory.minMembers) })
        return
    end

    -- Sanitise inputs
    local name    = tostring(data.name or ''):sub(1, 128)
    local ttype   = tostring(data.type or 'turf'):sub(1, 32)
    local x       = tonumber(data.x) or 0.0
    local y       = tonumber(data.y) or 0.0
    local z       = tonumber(data.z) or 0.0
    local radius  = tonumber(data.radius) or 50.0
    local stashId = data.stashId and tostring(data.stashId):sub(1, 128) or nil

    MySQL.insert([[
        INSERT INTO faction_territory (faction_id, name, type, x, y, z, radius, stash_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { row.faction_id, name, ttype, x, y, z, radius, stashId })

    -- Apply claim cooldown
    MySQL.query([[
        INSERT INTO faction_cooldowns (faction_id, type, expires_at)
        VALUES (?, 'territory_claim', DATE_ADD(NOW(), INTERVAL ? SECOND))
        ON DUPLICATE KEY UPDATE expires_at = DATE_ADD(NOW(), INTERVAL ? SECOND)
    ]], { row.faction_id, Config.Territory.claimCooldown, Config.Territory.claimCooldown })

    -- Reputation gain
    MySQL.update('UPDATE faction_factions SET reputation = reputation + ? WHERE id = ?', {
        Config.Reputation.territoryClaim, row.faction_id
    })

    lib.notify(source, { type = 'success', description = 'Territory "' .. name .. '" claimed!' })
end)

-- Check if player is in claimed territory (called periodically from client)
RegisterNetEvent('faction:checkTerritory', function(coords)
    local source = source
    -- Lightweight - just check if in any territory (no response needed unless wanted)
    -- Could be expanded to show territory zone name as a notification
end)

-- Admin: get factions for territory assignment
RegisterNetEvent('faction:adminGetFactionsForTerritory', function()
    local source = source
    if not IsAdminPlayer(source) then return end

    local factions = MySQL.query.await('SELECT id, name, label FROM faction_factions ORDER BY label')
    TriggerClientEvent('faction:adminReceiveFactionsForTerritory', source, factions or {})
end)

-- Admin: assign territory to a faction
RegisterNetEvent('faction:adminAssignTerritory', function(factionId, data)
    local source = source
    if not IsAdminPlayer(source) then return end

    local fid = tonumber(factionId)
    if not fid then return end

    local name    = tostring(data.name or ''):sub(1, 128)
    local ttype   = tostring(data.type or 'turf'):sub(1, 32)
    local x       = tonumber(data.x) or 0.0
    local y       = tonumber(data.y) or 0.0
    local z       = tonumber(data.z) or 0.0
    local radius  = tonumber(data.radius) or 50.0
    local stashId = data.stashId and tostring(data.stashId):sub(1, 128) or nil

    MySQL.insert([[
        INSERT INTO faction_territory (faction_id, name, type, x, y, z, radius, stash_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { fid, name, ttype, x, y, z, radius, stashId })

    lib.notify(source, { type = 'success', description = 'Territory assigned.' })
    TriggerClientEvent('faction:adminGetFactionsForTerritory', source)
end)
