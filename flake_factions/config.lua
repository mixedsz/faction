Config = {}

-- Faction Ranks
Config.Ranks = {
    ['boss'] = { label = 'Boss', level = 5, permissions = { 'all' } },
    ['big_homie'] = { label = 'Big Homie', level = 4, permissions = { 'all', 'territory_claim', 'manage_members' } },
    ['shot_caller'] = { label = 'Shot Caller', level = 3, permissions = { 'war', 'territory', 'ck_request' } },
    ['member'] = { label = 'Member', level = 2, permissions = { 'sell' } },
    ['runner'] = { label = 'Runner', level = 1, permissions = { 'sell' } }
}

-- Territory Requirements
Config.Territory = {
    minMembers = 3, -- Minimum active members to claim territory
    minSellTime = 300, -- Minimum time selling in seconds (5 minutes)
    claimCooldown = 3600, -- Cooldown between territory claims (1 hour)
    disputeRadius = 50.0, -- Radius in meters for territory disputes
    autoLogDisputes = true -- Automatically log disputes when factions overlap
}

-- War/Conflict Settings
Config.Conflict = {
    minCooldown = 7200, -- Minimum cooldown between wars (2 hours)
    maxActiveWars = 2, -- Maximum active wars per faction
    warDuration = 3600, -- Default war duration (1 hour)
    ckCooldown = 1800 -- Cooldown between CK requests (30 minutes)
}

-- Gun Drop Settings
Config.GunDrops = {
    enabled = true,
    cooldown = 86400, -- 24 hours
    minReputation = 50, -- Minimum reputation required
    maxPerFaction = 1 -- Max gun drops per faction at once
}

-- Reputation System
Config.Reputation = {
    killEnemy = 5, -- Reputation gained per enemy kill
    loseMember = -10, -- Reputation lost per member death
    winWar = 50, -- Reputation gained for winning war
    loseWar = -25, -- Reputation lost for losing war
    territoryClaim = 20, -- Reputation gained for claiming territory
    territoryLost = -15 -- Reputation lost for losing territory
}

-- Weapon Logging
Config.Weapons = {
    enforceLogging = true, -- Enforce weapon logging
    illegalPenalty = true, -- Penalty for using unlogged weapons
    logOnShoot = true, -- Log weapon usage on shoot
    violationCooldown = 300, -- Cooldown between violation checks (5 minutes)
    -- Silent background scan: updates who has registered guns so the panel stays accurate
    possessionScanInterval = 120, -- Seconds between full scans of faction members' ox_inv (2 min)
    possessionCacheMaxAge = 90 -- Use cached possession if updated within this many seconds (1.5 min)
}

-- UI Settings
Config.UI = {
    keybind = 'F6', -- Key to open faction menu
    updateInterval = 5000, -- Update interval in ms

    -- Phone UI option: set to true to use a useable phone item instead of the keybind.
    -- Players must have the item in their inventory to open the faction panel.
    -- The panel is displayed inside a phone frame instead of as a floating window.
    usePhoneUI = false,
    phoneItem = 'faction_phone' -- Inventory item name that opens the phone UI
}

-- Database Settings
Config.Database = {
    tablePrefix = 'faction_' -- Prefix for database tables
}

-- Production / Demo Mode
-- When true, ALL tabs in the faction UI are populated with realistic fake data.
-- Use this to showcase the script to potential buyers without needing a live server.
-- Set to false on your live server.
Config.ProductionMode = false

-- Admin: ESX groups that can use admin commands and panel
Config.AdminGroups = { 'management', 'lead' }

-- Webhook Settings
Config.Webhooks = {
    enabled = false, -- Set to true to enable webhooks
    weaponLogging = '', -- Webhook URL for weapon logging
    invalidShootout = '', -- Webhook URL for invalid shootout alerts
    reportSubmitted = '' -- Webhook URL for report submissions
}
