-- Territory management

-- ============================================================
-- TERRITORY ZONE DETECTION
-- Cache territories in memory and notify players on enter/exit.
-- ============================================================

local territoryCache     = {}
local territoryCacheTime = 0
local TERRITORY_CACHE_TTL = 60 -- seconds between DB refreshes

-- Per-player: which territory ID they're currently standing in (nil = none)
local playerCurrentTerritory = {}

local function GetCachedTerritories()
    local now = os.time()
    if (now - territoryCacheTime) > TERRITORY_CACHE_TTL or #territoryCache == 0 then
        local result = MySQL.query.await([[
            SELECT t.id, t.faction_id, t.name, t.type, t.x, t.y, t.z, t.radius,
                   f.label AS faction_label
            FROM faction_territory t
            JOIN faction_factions f ON f.id = t.faction_id
        ]])
        territoryCache     = result or {}
        territoryCacheTime = now
    end
    return territoryCache
end

-- Invalidate cache when territory changes
local function InvalidateTerritoryCache()
    territoryCacheTime = 0
end

-- Clean up on player disconnect
AddEventHandler('playerDropped', function()
    local source = source
    playerCurrentTerritory[source] = nil
end)

-- Check if player is inside any territory zone (called every 5 s from client)
RegisterNetEvent('faction:checkTerritory', function(coords)
    local source = source
    if not coords then return end

    local x = tonumber(coords.x)
    local y = tonumber(coords.y)
    local z = tonumber(coords.z)
    if not x or not y or not z then return end

    local territories  = GetCachedTerritories()
    local inTerritory  = nil

    for _, terr in ipairs(territories) do
        local dist = math.sqrt((x - terr.x)^2 + (y - terr.y)^2 + (z - terr.z)^2)
        if dist <= (terr.radius or 50.0) then
            inTerritory = terr
            break
        end
    end

    local prevId = playerCurrentTerritory[source]
    local newId  = inTerritory and inTerritory.id or nil

    if newId ~= prevId then
        playerCurrentTerritory[source] = newId
        if inTerritory then
            TriggerClientEvent('faction:enterTerritory', source, {
                id            = inTerritory.id,
                name          = inTerritory.name,
                type          = inTerritory.type,
                faction_label = inTerritory.faction_label
            })
        else
            TriggerClientEvent('faction:exitTerritory', source)
        end
    end
end)

-- ============================================================
-- PLAYER-FACING TERRITORY EVENTS
-- ============================================================

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

    -- Claim cooldown check
    local cooldown = MySQL.query.await([[
        SELECT TIMESTAMPDIFF(SECOND, NOW(), expires_at) AS secs_remaining
        FROM faction_cooldowns
        WHERE faction_id = ? AND type = 'territory_claim' AND expires_at > NOW()
        LIMIT 1
    ]], { row.faction_id })

    if cooldown and #cooldown > 0 then
        local mins = math.ceil(cooldown[1].secs_remaining / 60)
        lib.notify(source, { type = 'error', description = string.format('Territory claim on cooldown: %d minute(s) remaining.', mins) })
        return
    end

    -- Minimum active members check
    local activeMemberCount = 0
    local members = MySQL.query.await('SELECT identifier FROM faction_members WHERE faction_id = ?', { row.faction_id })
    for _, m in ipairs(members or {}) do
        if ESX.GetPlayerFromIdentifier(m.identifier) then
            activeMemberCount = activeMemberCount + 1
        end
    end

    if activeMemberCount < Config.Territory.minMembers then
        lib.notify(source, { type = 'error', description = string.format(
            'Need at least %d active members online to claim territory (currently %d).',
            Config.Territory.minMembers, activeMemberCount) })
        return
    end

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

    InvalidateTerritoryCache()
    lib.notify(source, { type = 'success', description = 'Territory "' .. name .. '" claimed!' })
end)

-- ============================================================
-- ADMIN TERRITORY MANAGEMENT
-- ============================================================

RegisterNetEvent('faction:adminGetFactionsForTerritory', function()
    local source = source
    if not IsAdminPlayer(source) then return end

    local factions = MySQL.query.await([[
        SELECT f.id, f.name, f.label,
               (SELECT COUNT(*) FROM faction_territory WHERE faction_id = f.id) AS territory_count
        FROM faction_factions f
        ORDER BY f.label
    ]])
    TriggerClientEvent('faction:adminReceiveFactionsForTerritory', source, factions or {})
end)

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

    InvalidateTerritoryCache()
    lib.notify(source, { type = 'success', description = 'Territory assigned.' })

    -- Refresh manage view for this faction
    local faction = GetFactionById(fid)
    local territories = MySQL.query.await('SELECT id, faction_id, name, type, x, y, z, radius, stash_id FROM faction_territory WHERE faction_id = ? ORDER BY name', { fid })
    TriggerClientEvent('faction:adminReceiveFactionTerritory', source, fid, faction and faction.label or 'Unknown', territories or {})
end)

-- Get all territories for a specific faction (admin management view)
RegisterNetEvent('faction:adminGetFactionTerritory', function(factionId)
    local source = source
    if not IsAdminPlayer(source) then return end

    local fid = tonumber(factionId)
    if not fid then return end

    local faction = GetFactionById(fid)
    local territories = MySQL.query.await([[
        SELECT id, faction_id, name, type, x, y, z, radius, stash_id
        FROM faction_territory
        WHERE faction_id = ?
        ORDER BY name
    ]], { fid })

    TriggerClientEvent('faction:adminReceiveFactionTerritory', source, fid, faction and faction.label or 'Unknown', territories or {})
end)

-- Delete a territory (admin)
RegisterNetEvent('faction:adminDeleteTerritory', function(territoryId, factionId)
    local source = source
    if not IsAdminPlayer(source) then return end

    local tid = tonumber(territoryId)
    if not tid then return end

    MySQL.update('DELETE FROM faction_territory WHERE id = ?', { tid })
    InvalidateTerritoryCache()

    lib.notify(source, { type = 'success', description = 'Territory deleted.' })

    -- Refresh the manage view for the faction
    local fid = tonumber(factionId)
    if fid then
        local faction = GetFactionById(fid)
        local territories = MySQL.query.await('SELECT id, faction_id, name, type, x, y, z, radius, stash_id FROM faction_territory WHERE faction_id = ? ORDER BY name', { fid })
        TriggerClientEvent('faction:adminReceiveFactionTerritory', source, fid, faction and faction.label or 'Unknown', territories or {})
    end
end)
