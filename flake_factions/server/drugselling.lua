-- Optional flake_drugselling integration
-- Enabled via Config.UsingFlakeDrugSelling = true in config.lua
--
-- When enabled, listens for the event specified in Config.DrugSelling.eventName
-- (default: 'flake_drugselling:sold') and grants reputation to the selling player's faction.
--
-- This file does NOT modify flake_drugselling in any way — it only listens to its events.
-- Set Config.UsingFlakeDrugSelling = false to disable with zero impact on other systems.

if not Config.UsingFlakeDrugSelling then return end

local sellCooldowns = {} -- per-player sell rep cooldown (seconds)
local SELL_COOLDOWN = 60 -- minimum seconds between rep grants per player

AddEventHandler(Config.DrugSelling.eventName, function(sellerSource, ...)
    -- The source of the event is the player who made the sale.
    -- flake_drugselling typically triggers this as a server event so source is valid.
    local src = sellerSource or source
    local xPlayer = ESX.GetPlayerFromId(tonumber(src))
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then return end -- not in a faction, ignore

    -- Per-player cooldown to prevent rep spam from rapid sales
    local now = os.time()
    if (now - (sellCooldowns[xPlayer.identifier] or 0)) < SELL_COOLDOWN then return end
    sellCooldowns[xPlayer.identifier] = now

    local repGain = Config.DrugSelling.repPerSale or 2
    MySQL.update('UPDATE faction_factions SET reputation = reputation + ? WHERE id = ?', { repGain, row.faction_id })
    MySQL.update([[
        UPDATE faction_members SET reputation_contribution = reputation_contribution + ?
        WHERE identifier = ? AND faction_id = ?
    ]], { repGain, xPlayer.identifier, row.faction_id })

    lib.notify(tonumber(src), {
        type        = 'success',
        description = string.format('+%d faction rep from drug sale!', repGain)
    })

    if Config.Webhooks.enabled and Config.Webhooks.weaponLogging ~= '' then
        PerformHttpRequest(Config.Webhooks.weaponLogging, function() end, 'POST',
            json.encode({ content = string.format(
                '**Drug Sale** | Player: %s | Faction: %s | +%d Rep',
                xPlayer.getName(), row.faction_label, repGain) }),
            { ['Content-Type'] = 'application/json' })
    end
end)
