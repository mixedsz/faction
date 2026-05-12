-- Territory management

-- ============================================================
-- RE-REGISTER ALL STASHES ON RESOURCE START
-- ============================================================
CreateThread(function()
    Wait(2000) -- allow database.lua to finish its CREATE TABLE queries
    if not exports.ox_inventory then return end
    local stashes = MySQL.query.await([[
        SELECT id, name, stash_id, faction_id
        FROM faction_territory
        WHERE type = 'stash' AND stash_id IS NOT NULL AND stash_id != ''
    ]])
    local count = 0
    for _, s in ipairs(stashes or {}) do
        pcall(function()
            exports.ox_inventory:RegisterStash(s.stash_id, s.name, 50, 100000)
            count = count + 1
        end)
    end
    if count > 0 then
        print(string.format('^2[flake_factions] Re-registered %d faction stash(es) with ox_inventory.^7', count))
    end
end)

-- ============================================================
-- ALL-TERRITORIES BROADCAST (for client visual rendering)
-- ============================================================

-- Send every territory to a single player (called on spawn)
RegisterNetEvent('faction:getAllTerritories', function()
    local source = source
    local territories = MySQL.query.await([[
        SELECT t.id, t.faction_id, t.name, t.type, t.x, t.y, t.z, t.radius,
               t.stash_id, t.stash_access,
               f.label AS faction_label
        FROM faction_territory t
        JOIN faction_factions f ON f.id = t.faction_id
    ]])
    TriggerClientEvent('faction:receiveAllTerritories', source, territories or {})
end)

-- Broadcast territory visuals refresh to ALL online players (called after any territory add/remove)
local function BroadcastTerritoryRefresh()
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        if src then
            TriggerClientEvent('faction:refreshTerritoryVisuals', src)
        end
    end
end

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

-- Lightweight tracking events fired by client-side ox_lib zone callbacks.
-- These replace the old coord-polling approach and keep server-side
-- playerCurrentTerritory accurate without any per-second overhead.
RegisterNetEvent('faction:playerEnteredTerritory', function(territoryId)
    local source = source
    playerCurrentTerritory[source] = tonumber(territoryId)
end)

RegisterNetEvent('faction:playerExitedTerritory', function(territoryId)
    local source = source
    if playerCurrentTerritory[source] == tonumber(territoryId) then
        playerCurrentTerritory[source] = nil
    end
end)

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
    -- Stash type doesn't need a spatial radius; default to 1.0 so the DB is non-null
    local radius  = (ttype == 'stash') and 1.0 or (tonumber(data.radius) or 50.0)
    -- Auto-generate a stash ID if type is stash and none was supplied
    local stashId = data.stashId and tostring(data.stashId):sub(1, 128) or nil
    if ttype == 'stash' and (not stashId or stashId == '') then
        stashId = string.format('faction_stash_%d_%d', row.faction_id, os.time())
    end

    MySQL.insert([[
        INSERT INTO faction_territory (faction_id, name, type, x, y, z, radius, stash_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { row.faction_id, name, ttype, x, y, z, radius, stashId })

    -- Register the ox_inventory stash so it becomes usable immediately
    if ttype == 'stash' and stashId and exports.ox_inventory then
        pcall(function()
            exports.ox_inventory:RegisterStash(stashId, name, 50, 100000, false, nil, vector3(x, y, z))
        end)
    end

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
    BroadcastTerritoryRefresh()
    lib.notify(source, { type = 'success', description = 'Territory "' .. name .. '" claimed!' })

    -- Notify faction members
    NotifyFactionMembers(row.faction_id, 'faction:receiveNotification', {
        type = 'success', title = 'Territory Claimed',
        description = xPlayer.getName() .. ' claimed territory "' .. name .. '"! +' .. Config.Reputation.territoryClaim .. ' rep.'
    })

    -- Webhook
    if Config.Webhooks.enabled and Config.Webhooks.weaponLogging ~= '' then
        PerformHttpRequest(Config.Webhooks.weaponLogging, function() end, 'POST',
            json.encode({ content = string.format(
                '**Territory Claimed** | Faction: %s | Territory: %s | By: %s | +%d Rep',
                row.faction_label, name, xPlayer.getName(), Config.Reputation.territoryClaim) }),
            { ['Content-Type'] = 'application/json' })
    end
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
    local radius  = (ttype == 'stash') and 1.0 or (tonumber(data.radius) or 50.0)
    local stashId = data.stashId and tostring(data.stashId):sub(1, 128) or nil
    if ttype == 'stash' and (not stashId or stashId == '') then
        stashId = string.format('faction_stash_%d_%d', fid, os.time())
    end

    MySQL.insert([[
        INSERT INTO faction_territory (faction_id, name, type, x, y, z, radius, stash_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { fid, name, ttype, x, y, z, radius, stashId })

    -- Register ox_inventory stash so it is immediately accessible
    if ttype == 'stash' and stashId and exports.ox_inventory then
        pcall(function()
            exports.ox_inventory:RegisterStash(stashId, name, 50, 100000, false, nil, vector3(x, y, z))
        end)
    end

    InvalidateTerritoryCache()
    BroadcastTerritoryRefresh()
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

    -- Fetch territory info before deleting for reputation / notification
    local terrInfo = MySQL.query.await('SELECT t.name, t.faction_id, f.label AS faction_label FROM faction_territory t JOIN faction_factions f ON f.id = t.faction_id WHERE t.id = ? LIMIT 1', { tid })
    local terr = terrInfo and terrInfo[1] or nil

    MySQL.update('DELETE FROM faction_territory WHERE id = ?', { tid })
    InvalidateTerritoryCache()
    BroadcastTerritoryRefresh()

    -- Apply reputation loss for losing territory
    if terr and terr.faction_id then
        local repLoss = math.abs(Config.Reputation.territoryLost or 15)
        MySQL.update('UPDATE faction_factions SET reputation = GREATEST(0, reputation - ?) WHERE id = ?', { repLoss, terr.faction_id })

        NotifyFactionMembers(terr.faction_id, 'faction:receiveNotification', {
            type = 'error', title = 'Territory Lost',
            description = 'Territory "' .. (terr.name or 'Unknown') .. '" was removed. -' .. repLoss .. ' rep.'
        })

        if Config.Webhooks.enabled and Config.Webhooks.weaponLogging ~= '' then
            PerformHttpRequest(Config.Webhooks.weaponLogging, function() end, 'POST',
                json.encode({ content = string.format(
                    '**Territory Removed** | Faction: %s | Territory: %s | -%d Rep',
                    terr.faction_label, terr.name or 'Unknown', repLoss) }),
                { ['Content-Type'] = 'application/json' })
        end
    end

    lib.notify(source, { type = 'success', description = 'Territory deleted.' })

    -- Refresh the manage view for the faction
    local fid = tonumber(factionId)
    if fid then
        local faction = GetFactionById(fid)
        local territories = MySQL.query.await('SELECT id, faction_id, name, type, x, y, z, radius, stash_id FROM faction_territory WHERE faction_id = ? ORDER BY name', { fid })
        TriggerClientEvent('faction:adminReceiveFactionTerritory', source, fid, faction and faction.label or 'Unknown', territories or {})
    end
end)

-- ============================================================
-- STASH: Open / Access Management
-- ============================================================

-- Player requests to open a faction stash (server validates, then unlocks for client)
RegisterNetEvent('faction:requestOpenStash', function(territoryId)
    local source   = source
    local xPlayer  = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local pData = GetPlayerFactionData(xPlayer.identifier)
    if not pData then
        lib.notify(source, { type = 'error', description = 'You are not in a faction.' })
        return
    end

    local rows = MySQL.query.await([[
        SELECT id, faction_id, stash_id, name, stash_access
        FROM faction_territory
        WHERE id = ? AND type = 'stash' AND stash_id IS NOT NULL
        LIMIT 1
    ]], { tonumber(territoryId) })

    if not rows or #rows == 0 then
        lib.notify(source, { type = 'error', description = 'Stash not found.' })
        return
    end

    local terr = rows[1]

    -- Must belong to the player's faction
    if terr.faction_id ~= pData.faction_id then
        lib.notify(source, { type = 'error', description = 'This stash belongs to another faction.' })
        return
    end

    -- Whitelist check — if stash_access is set, only listed members (+ boss) can open it
    if terr.stash_access and terr.stash_access ~= '' then
        local whitelist = json.decode(terr.stash_access) or {}
        local allowed   = (pData.rank == 'boss') -- boss always has access
        if not allowed then
            for _, ident in ipairs(whitelist) do
                if ident == xPlayer.identifier then
                    allowed = true
                    break
                end
            end
        end
        if not allowed then
            lib.notify(source, { type = 'error', description = 'You are not whitelisted for this stash.' })
            return
        end
    end

    -- Tell client to open the ox_inventory stash
    TriggerClientEvent('faction:doOpenStash', source, terr.stash_id)
end)

-- Boss: set which members can access the stash (pass an array of identifiers, or empty/nil for all)
RegisterNetEvent('faction:setStashAccess', function(territoryId, whitelist)
    local source  = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local pData = GetPlayerFactionData(xPlayer.identifier)
    if not pData or pData.rank ~= 'boss' then
        lib.notify(source, { type = 'error', description = 'Only the Boss can manage stash access.' })
        return
    end

    local tid = tonumber(territoryId)
    if not tid then return end

    -- Confirm faction ownership
    local rows = MySQL.query.await([[
        SELECT id, faction_id FROM faction_territory
        WHERE id = ? AND type = 'stash' LIMIT 1
    ]], { tid })

    if not rows or #rows == 0 then
        lib.notify(source, { type = 'error', description = 'Stash territory not found.' })
        return
    end
    if rows[1].faction_id ~= pData.faction_id then
        lib.notify(source, { type = 'error', description = 'That stash is not owned by your faction.' })
        return
    end

    -- nil or empty table = open to all faction members (no whitelist)
    local accessJson = nil
    if type(whitelist) == 'table' and #whitelist > 0 then
        accessJson = json.encode(whitelist)
    end

    MySQL.update('UPDATE faction_territory SET stash_access = ? WHERE id = ?', { accessJson, tid })
    lib.notify(source, { type = 'success', description = 'Stash access list updated.' })

    -- Refresh territories for all faction members so their UI stays current
    BroadcastTerritoryRefresh()
end)

-- Fetch current stash whitelist for the boss management UI
RegisterNetEvent('faction:getStashAccess', function(territoryId)
    local source  = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local pData = GetPlayerFactionData(xPlayer.identifier)
    if not pData or pData.rank ~= 'boss' then return end

    local tid = tonumber(territoryId)
    local rows = MySQL.query.await([[
        SELECT stash_access FROM faction_territory
        WHERE id = ? AND faction_id = ? AND type = 'stash' LIMIT 1
    ]], { tid, pData.faction_id })

    if not rows or #rows == 0 then return end

    local whitelist = {}
    if rows[1].stash_access and rows[1].stash_access ~= '' then
        whitelist = json.decode(rows[1].stash_access) or {}
    end

    -- Fetch member list so boss can pick from them
    local members = MySQL.query.await([[
        SELECT identifier, player_name, rank
        FROM faction_members
        WHERE faction_id = ?
        ORDER BY rank DESC, player_name ASC
    ]], { pData.faction_id })

    TriggerClientEvent('faction:receiveStashAccess', source, {
        territory_id = tid,
        whitelist    = whitelist,
        members      = members or {}
    })
end)
