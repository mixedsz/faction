-- Weapon tracking and logging

-- Possession scan cache: identifier -> { lastScan = timestamp, weapons = {} }
local possessionCache = {}

-- Helper: get current weapon inventory for a player from ox_inventory
local function GetPlayerWeaponInventory(identifier)
    -- Use ox_inventory exports to get items for an offline or online player
    local items = exports.ox_inventory and exports.ox_inventory:GetInventoryItems('player', identifier) or {}
    local weapons = {}
    if type(items) == 'table' then
        for _, item in ipairs(items) do
            if item and item.name then
                -- ox_inventory weapon items typically start with 'weapon_'
                local name = tostring(item.name):lower()
                if name:sub(1, 7) == 'weapon_' then
                    local serial = item.metadata and item.metadata.serial or nil
                    table.insert(weapons, {
                        name   = item.name,
                        label  = item.label or item.name,
                        serial = serial
                    })
                end
            end
        end
    end
    return weapons
end

-- Get weapons for player's faction
RegisterNetEvent('faction:getWeapons', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then
        TriggerClientEvent('faction:receiveWeapons', source, {})
        return
    end

    local weapons = MySQL.query.await([[
        SELECT w.id, w.weapon_name, w.serial_number, w.weapon_hash,
               w.holder_identifier, w.holder_name, w.registered_at
        FROM faction_weapons w
        WHERE w.faction_id = ?
        ORDER BY w.weapon_name
    ]], { row.faction_id })

    -- Attach possession info from cache
    local now = os.time()
    for _, w in ipairs(weapons or {}) do
        if w.holder_identifier then
            local cached = possessionCache[w.holder_identifier]
            if cached and (now - cached.lastScan) < Config.Weapons.possessionCacheMaxAge then
                -- Check if holder still has the weapon by serial
                w.inPossession = false
                for _, cw in ipairs(cached.weapons) do
                    if cw.serial == w.serial_number then
                        w.inPossession = true
                        break
                    end
                end
            end
        end
    end

    TriggerClientEvent('faction:receiveWeapons', source, weapons or {})
end)

-- Log weapon usage (called from client when shooting)
RegisterNetEvent('faction:logWeaponUsage', function(weaponHash, coords, isAltercation)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    if not Config.Weapons.logOnShoot then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    local factionId = row and row.faction_id or nil

    local hashStr = tostring(weaponHash)
    local cx = tonumber(coords and coords.x) or 0
    local cy = tonumber(coords and coords.y) or 0
    local cz = tonumber(coords and coords.z) or 0

    -- Check if the weapon is registered to this faction
    local isViolation = false
    if Config.Weapons.enforceLogging and factionId then
        local registered = MySQL.query.await([[
            SELECT id FROM faction_weapons
            WHERE faction_id = ? AND (weapon_hash = ? OR weapon_hash IS NULL)
            LIMIT 1
        ]], { factionId, hashStr })
        isViolation = (not registered or #registered == 0)
    end

    MySQL.insert([[
        INSERT INTO faction_weapon_logs (faction_id, member_identifier, weapon_hash, is_altercation, is_violation, x, y, z)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { factionId, xPlayer.identifier, hashStr, isAltercation and 1 or 0, isViolation and 1 or 0, cx, cy, cz })

    -- Webhook for invalid shootout
    if isViolation and isAltercation and Config.Weapons.illegalPenalty then
        if Config.Webhooks.enabled and Config.Webhooks.invalidShootout ~= '' then
            PerformHttpRequest(Config.Webhooks.invalidShootout, function() end, 'POST',
                json.encode({ content = string.format('**Illegal Weapon Used in Altercation** by %s | WeaponHash: %s', xPlayer.getName(), hashStr) }),
                { ['Content-Type'] = 'application/json' })
        end
    end
end)

-- Background possession scan: update who holds each registered weapon
CreateThread(function()
    while true do
        Wait(Config.Weapons.possessionScanInterval * 1000)

        -- Get all registered weapons grouped by faction
        local weapons = MySQL.query.await('SELECT id, faction_id, serial_number, weapon_hash FROM faction_weapons')
        if not weapons then goto continue end

        -- Get all faction member identifiers
        local allMembers = MySQL.query.await('SELECT DISTINCT identifier, faction_id FROM faction_members')
        if not allMembers then goto continue end

        local now = os.time()

        for _, member in ipairs(allMembers) do
            -- Only scan online players (offline inventory scanning is slow)
            local xPlayer = ESX.GetPlayerFromIdentifier(member.identifier)
            if xPlayer then
                local inv = GetPlayerWeaponInventory(member.identifier)
                possessionCache[member.identifier] = { lastScan = now, weapons = inv }

                -- Update holder_name/identifier on matched weapons
                for _, w in ipairs(weapons) do
                    if w.faction_id == member.faction_id then
                        for _, iw in ipairs(inv) do
                            if iw.serial == w.serial_number then
                                MySQL.update('UPDATE faction_weapons SET holder_identifier = ?, holder_name = ? WHERE id = ?', {
                                    member.identifier, xPlayer.getName(), w.id
                                })
                                break
                            end
                        end
                    end
                end
            end
        end

        ::continue::
    end
end)
