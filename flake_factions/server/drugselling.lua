-- Optional flake_drugselling integration
-- Enabled via Config.UsingFlakeDrugSelling = true in config.lua
--
-- Hooks into flake_drugselling:server:sellDrug (the net event fired by the client
-- when initiating a drug sale). Because FiveM routes net events to all resources,
-- we can listen here without touching flake_drugselling at all.
--
-- Set Config.UsingFlakeDrugSelling = false to disable with zero impact.

if not Config.UsingFlakeDrugSelling then return end

-- FiveM requires every resource that handles a net event to declare it,
-- even when just listening from a different resource.
RegisterNetEvent('flake_drugselling:server:sellDrug')

local sellCooldowns = {} -- per-player cooldown so rapid sales don't spam rep
local SELL_COOLDOWN  = 60 -- seconds between rep grants per player

-- flake_drugselling triggers TriggerServerEvent('flake_drugselling:server:sellDrug', drugItem, drugCount)
-- FiveM sets `source` automatically for net events, so it is valid inside AddEventHandler.
AddEventHandler('flake_drugselling:server:sellDrug', function(drugItem, drugCount)
    local src      = source
    local xPlayer  = ESX.GetPlayerFromId(tonumber(src))
    if not xPlayer then return end

    local row = GetPlayerFactionData(xPlayer.identifier)
    if not row then return end -- player is not in a faction

    local now = os.time()
    if (now - (sellCooldowns[xPlayer.identifier] or 0)) < SELL_COOLDOWN then return end
    sellCooldowns[xPlayer.identifier] = now

    local repGain = Config.DrugSelling.repPerSale or 2
    MySQL.update('UPDATE faction_factions SET reputation = reputation + ? WHERE id = ?',
        { repGain, row.faction_id })
    MySQL.update([[
        UPDATE faction_members SET reputation_contribution = reputation_contribution + ?
        WHERE identifier = ? AND faction_id = ?
    ]], { repGain, xPlayer.identifier, row.faction_id })

    lib.notify(src, {
        type        = 'success',
        description = string.format('+%d faction rep from drug sale!', repGain)
    })

    if Config.Webhooks.enabled and Config.Webhooks.weaponLogging ~= '' then
        PerformHttpRequest(Config.Webhooks.weaponLogging, function() end, 'POST',
            json.encode({ content = string.format(
                '**Drug Sale** | Player: %s | Faction: %s | Drug: %s | +%d Rep',
                xPlayer.getName(), row.faction_label, tostring(drugItem or 'unknown'), repGain) }),
            { ['Content-Type'] = 'application/json' })
    end
end)
