-- Main Client File

local PlayerData = {}
currentFaction = nil -- Make it global so ui.lua can access it
local awaitingReputationRefresh = false

-- Import functions from ui.lua (deprecated - now handled in NUI)
function OpenFactionReportTab()
    -- Deprecated - Report tab now uses NUI directly
end

function OpenCKRequestTab()
    -- Deprecated - CK Request tab now uses NUI directly
end

ESX = exports['es_extended']:getSharedObject()

RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    PlayerData = xPlayer
end)

RegisterNetEvent('esx:setJob', function(job)
    PlayerData.job = job
end)

-- Faction command - opens NUI panel for members only
-- When usePhoneUI is true the player must use the phone item; keybind/command is blocked.
RegisterCommand('faction', function()
    if Config.UI.usePhoneUI then
        lib.notify({ type = 'error', description = 'Use your faction phone to access the panel.' })
        return
    end
    OpenFactionPanel()
end, false)

RegisterKeyMapping('faction', 'Open Faction Menu', 'keyboard', Config.UI.keybind)

-- Receive faction data
RegisterNetEvent('faction:receiveFactionData', function(data)
    currentFaction = data
    -- Update the top-screen faction HUD badge when phone UI mode is active
    if Config.UI.usePhoneUI then
        if data and data.faction then
            local rankLabel = Config.Ranks[data.rank] and Config.Ranks[data.rank].label or (data.rank or 'Member')
            SendNUIMessage({
                action = 'updateFactionHUD',
                show = true,
                factionLabel = data.faction.label or data.faction.name or 'Faction',
                rank = rankLabel
            })
        else
            SendNUIMessage({ action = 'updateFactionHUD', show = false })
        end
    end
    -- If the reputation tab is waiting for fresh data, push it now
    if awaitingReputationRefresh and data and data.faction then
        awaitingReputationRefresh = false
        local faction   = data.faction
        local rankLabel = Config.Ranks[data.rank] and Config.Ranks[data.rank].label or data.rank
        SendNUIMessage({
            action  = 'updateTab',
            tab     = 'reputation',
            content = {
                reputation          = faction.reputation or 0,
                rank                = rankLabel,
                activeWars          = (faction.active_wars or 0) .. ' / ' .. (faction.max_wars or 2),
                gunDropEligible     = faction.gun_drop_eligible and 'Yes' or 'No',
                gunDropCooldownSecs = faction.gun_drop_cooldown_secs or 0
            }
        })
    end
end)

-- Open faction menu (called after server verifies permissions)
RegisterNetEvent('faction:openFactionMenu', function(factionId)
    -- Ensure NUI is fully closed before opening ox_lib menu
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    -- Wait a bit to ensure NUI is closed
    Wait(200)
    -- Server already sent the faction data, just open the menu
    OpenFactionMenu()
end)

-- Request faction data on spawn
CreateThread(function()
    while ESX.GetPlayerData().identifier == nil do
        Wait(100)
    end
    
    Wait(2000)
    TriggerServerEvent('faction:getFactionData')
end)

-- Request faction data (called after accepting invite)
RegisterNetEvent('faction:requestFactionData', function()
    TriggerServerEvent('faction:getFactionData')
end)

-- Open the Faction Member NUI panel (for regular players)
function OpenFactionPanel()
    local usePhoneUI = Config.UI.usePhoneUI == true
    -- Only show player's own faction, not all factions
    if not currentFaction or not currentFaction.faction then
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'open', factions = {}, isAdmin = false, usePhoneUI = usePhoneUI })
        -- Request faction data to check if player is in a faction
        TriggerServerEvent('faction:getFactionData')
        return
    end

    -- Player is in a faction, show it in NUI
    SetNuiFocus(true, true)
    local factionList = {
        {
            id = currentFaction.faction.id,
            name = currentFaction.faction.name,
            label = currentFaction.faction.label,
            type = currentFaction.faction.type,
            reputation = currentFaction.faction.reputation,
            active_wars = currentFaction.faction.active_wars,
            max_wars = currentFaction.faction.max_wars
        }
    }
    SendNUIMessage({ action = 'open', factions = factionList, isAdmin = false, usePhoneUI = usePhoneUI })
end

-- Phone item usage: triggers OpenFactionPanel when the player uses the faction phone item
if Config.UI.usePhoneUI then
    RegisterNetEvent('faction:openPhoneUI', function()
        OpenFactionPanel()
    end)
end

-- Receive faction list and update NUI (only if NUI is already open)
RegisterNetEvent('faction:receiveFactionList', function(list)
    -- Only update if NUI is already open (don't auto-open)
    -- Check if NUI focus is active before updating
    -- This event is deprecated but kept for compatibility
end)

-- Refresh faction list when a new faction is created
RegisterNetEvent('faction:refreshFactionList', function()
    -- If player is in a faction and NUI might be open, refresh their faction data
    if currentFaction then
        TriggerServerEvent('faction:getFactionData')
    end
    -- Always request updated admin factions list (server will verify admin status)
    -- This ensures admins viewing the panel get the update immediately
    TriggerServerEvent('faction:adminGetFactions')
end)

-- NUI callbacks
RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- CK Request NUI callbacks
RegisterNUICallback('selectCKFaction', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    if factionId then
        TriggerServerEvent('faction:getFactionPlayersForCK', factionId)
    end
end)

RegisterNUICallback('selectCKPlayer', function(data, cb)
    cb('ok')
    local identifier = data.identifier
    local name = data.name
    local serverId = data.serverId
    if identifier and name and serverId then
        SendNUIMessage({
            action = 'updateTab',
            tab = 'ck',
            content = {
                step = 'enter_reason',
                targetIdentifier = identifier,
                targetName = name,
                serverId = serverId
            }
        })
    end
end)

RegisterNUICallback('submitCKRequest', function(data, cb)
    cb('ok')
    local targetIdentifier = data.targetIdentifier
    local targetName = data.targetName
    local serverId = data.serverId
    local reason = data.reason
    if targetIdentifier and targetName and serverId and reason then
        TriggerServerEvent('faction:requestCK', targetIdentifier, targetName .. ' (ID: ' .. serverId .. ')', reason)
        -- Show success message and reset tab
        SendNUIMessage({
            action = 'updateTab',
            tab = 'ck',
            content = {
                step = 'select_faction',
                factions = {}
            }
        })
        TriggerServerEvent('faction:getFactionListForCK')
    end
end)

RegisterNUICallback('ckBack', function(_, cb)
    cb('ok')
    TriggerServerEvent('faction:getFactionListForCK')
end)

RegisterNUICallback('ckCancel', function(_, cb)
    cb('ok')
    TriggerServerEvent('faction:getFactionListForCK')
end)

-- Report NUI callbacks
RegisterNUICallback('reportSelectOwn', function(_, cb)
    cb('ok')
    SendNUIMessage({
        action = 'updateTab',
        tab = 'report',
        content = {
            step = 'enter_details',
            targetFactionId = nil
        }
    })
end)

RegisterNUICallback('reportSelectOther', function(_, cb)
    cb('ok')
    TriggerServerEvent('faction:getFactionListForReport')
end)

RegisterNUICallback('reportSelectFaction', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    if factionId then
        SendNUIMessage({
            action = 'updateTab',
            tab = 'report',
            content = {
                step = 'enter_details',
                targetFactionId = factionId
            }
        })
    end
end)

RegisterNUICallback('submitReport', function(data, cb)
    cb('ok')
    local reportType = data.reportType
    local details = data.details
    local targetFactionId = data.targetFactionId
    if reportType and details then
        TriggerServerEvent('faction:submitReport', reportType, details, targetFactionId)
        -- Reset report tab
        SendNUIMessage({
            action = 'updateTab',
            tab = 'report',
            content = {
                step = 'select_report_type'
            }
        })
    end
end)

RegisterNUICallback('reportBack', function(_, cb)
    cb('ok')
    SendNUIMessage({
        action = 'updateTab',
        tab = 'report',
        content = {
            step = 'select_report_type'
        }
    })
end)

RegisterNUICallback('reportCancel', function(_, cb)
    cb('ok')
    SendNUIMessage({
        action = 'updateTab',
        tab = 'report',
        content = {
            step = 'select_report_type'
        }
    })
end)

-- Admin NUI callbacks
RegisterNUICallback('adminSelectWeaponFaction', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    local factionLabel = data.factionLabel
    if factionId then
        -- Request weapons list for this faction
        TriggerServerEvent('faction:adminGetFactionWeapons', factionId)
    end
end)

RegisterNUICallback('adminSubmitWeapon', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    local weaponName = data.weaponName
    local serialNumber = data.serialNumber
    local weaponHash = data.weaponHash
    if factionId and weaponName and serialNumber then
        TriggerServerEvent('faction:adminRegisterWeapon', factionId, weaponName, serialNumber, weaponHash)
        lib.notify({
            type = 'success',
            description = 'Weapon registered successfully!'
        })
        -- Refresh weapons list for the faction
        Wait(200)
        TriggerServerEvent('faction:adminGetFactionWeapons', factionId)
    end
end)

RegisterNUICallback('adminDeleteWeapon', function(data, cb)
    cb('ok')
    local weaponId = data.weaponId
    if weaponId then
        TriggerServerEvent('faction:adminDeleteWeapon', weaponId)
    end
end)

RegisterNUICallback('requestDeleteWeaponConfirm', function(data, cb)
    cb('ok')
    local weaponId = tonumber(data.weaponId)
    if not weaponId or weaponId < 1 then return end
    local confirm = lib.alertDialog({
        header = 'Delete Weapon',
        content = 'Are you sure you want to delete this weapon? This action cannot be undone.',
        centered = true,
        cancel = true
    })
    if confirm == 'confirm' then
        TriggerServerEvent('faction:adminDeleteWeapon', weaponId)
    end
end)

RegisterNUICallback('adminViewWeapons', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    if factionId then
        TriggerServerEvent('faction:adminGetFactionWeapons', factionId)
    end
end)

RegisterNUICallback('adminSelectTerritoryFaction', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    if factionId then
        TriggerServerEvent('faction:adminGetFactionTerritory', factionId)
    end
end)

RegisterNUICallback('adminSubmitTerritory', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    local territoryData = data.territoryData
    if factionId and territoryData then
        TriggerServerEvent('faction:adminAssignTerritory', factionId, territoryData)
    end
end)

RegisterNUICallback('adminDeleteTerritory', function(data, cb)
    cb('ok')
    local territoryId = data.territoryId
    local factionId = data.factionId
    if territoryId then
        TriggerServerEvent('faction:adminDeleteTerritory', territoryId, factionId)
    end
end)

RegisterNUICallback('adminAddTerritory', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    local factionLabel = data.factionLabel
    if factionId then
        SendNUIMessage({
            action = 'updateTab',
            tab = 'territory',
            content = {
                step = 'assign_territory',
                factionId = factionId,
                factionLabel = factionLabel
            }
        })
    end
end)

local ALLOWED_TABS = { overview = true, members = true, weapons = true, conflicts = true, cooldowns = true, warnings = true, territory = true, report = true, ck = true, reputation = true, violations = true, factions = true, reports = true, rules = true }
RegisterNUICallback('requestTabData', function(data, cb)
    cb('ok')
    local tab = data and type(data.tab) == 'string' and data.tab:match('^%a[%a_]*$') and data.tab
    if not tab or not ALLOWED_TABS[tab] then return end

    local isAdmin = data.isAdmin == true

    -- Request data for the tab from server
    if tab == 'overview' then
        if isAdmin then
            -- Admin overview - get all factions
            TriggerServerEvent('faction:adminGetFactions')
        else
            -- Member overview - send current faction data immediately
            if currentFaction and currentFaction.faction then
                local f = currentFaction.faction
                -- Send overview data first
                SendNUIMessage({
                    action = 'updateTab',
                    tab = 'overview',
                    content = {
                        label = f.label or f.name or 'Faction',
                        type = f.type or 'Unknown',
                        reputation = f.reputation or 0,
                        active_wars = f.active_wars or 0,
                        max_wars = f.max_wars or 0
                    }
                })
                -- Then get conflicts separately (they will update via updateConflictsData)
                TriggerServerEvent('faction:getConflicts')
            end
        end
    elseif tab == 'members' then
        if isAdmin then
            -- Admin members are loaded only when clicking "View Members" on a faction (adminGetFactionMembers).
            -- Avoid calling getMembers here so we don't overwrite with player's own faction.
            SendNUIMessage({
                action = 'updateTab',
                tab = 'members',
                content = { selectFactionFirst = true, message = 'Select a faction from Overview and click View Members to view members.' }
            })
        else
            TriggerServerEvent('faction:getMembers')
        end
    elseif tab == 'weapons' then
        if isAdmin then
            -- Admin weapon registration - get faction list for NUI
            TriggerServerEvent('faction:adminGetFactionsForWeapon')
        else
            TriggerServerEvent('faction:getWeapons')
        end
    elseif tab == 'conflicts' then
        if isAdmin then
            TriggerServerEvent('faction:adminGetActiveWars')
        else
            TriggerServerEvent('faction:getConflicts')
        end
    elseif tab == 'cooldowns' then
        if isAdmin then
            -- Admin cooldowns - get all cooldowns
            TriggerServerEvent('faction:adminGetCooldowns')
        else
            TriggerServerEvent('faction:getCooldowns')
        end
    elseif tab == 'warnings' then
        TriggerServerEvent('faction:getWarnings')
    elseif tab == 'territory' then
        if isAdmin then
            -- Admin territory - get faction list for NUI
            TriggerServerEvent('faction:adminGetFactionsForTerritory')
        else
            TriggerServerEvent('faction:getTerritory')
        end
    elseif tab == 'report' then
        -- Report tab - show report form in NUI (no ox_lib)
        SendNUIMessage({
            action = 'updateTab',
            tab = 'report',
            content = {
                step = 'select_report_type'
            }
        })
    elseif tab == 'ck' then
        -- CK Request tab - get faction list for NUI
        if isAdmin then
            TriggerServerEvent('faction:adminGetPendingCKs', nil)
        else
            -- Request faction list for CK
            TriggerServerEvent('faction:getFactionListForCK')
        end
    elseif tab == 'reputation' then
        -- Always fetch fresh data from server so admin changes are reflected immediately
        awaitingReputationRefresh = true
        TriggerServerEvent('faction:getFactionData')
    elseif tab == 'violations' and isAdmin then
        TriggerServerEvent('faction:adminGetViolations')
    elseif tab == 'factions' and isAdmin then
        TriggerServerEvent('faction:adminGetFactions')
    elseif tab == 'reports' and isAdmin then
        -- Admin reports - get reports for NUI
        TriggerServerEvent('faction:adminGetReports')
    elseif tab == 'factions' and isAdmin then
        -- Admin factions - get factions for NUI
        TriggerServerEvent('faction:adminGetFactions')
    elseif tab == 'ck' and isAdmin then
        -- Admin CK requests - get pending CKs for NUI
        TriggerServerEvent('faction:adminGetPendingCKs', nil)
    elseif tab == 'rules' then
        if isAdmin then
            -- Admin rules - get all rules and factions
            TriggerServerEvent('faction:adminGetRules')
        else
            -- Member rules - get rules for their faction
            TriggerServerEvent('faction:getRules')
        end
    end
end)

-- Refresh cooldowns when notified (after admin sets cooldown)
RegisterNetEvent('faction:refreshCooldowns', function()
    if currentTab == 'cooldowns' then
        TriggerServerEvent('faction:getCooldowns')
    end
end)

RegisterNUICallback('createFaction', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
    lib.notify({
        type = 'info',
        description = 'Create faction is handled by server administrators'
    })
end)

-- Receive faction invite
RegisterNetEvent('faction:receiveInvite', function(data)
    local inviteData = data
    if not inviteData then return end
    
    -- Show confirmation dialog (like accepting a job)
    lib.registerContext({
        id = 'faction_invite',
        title = 'Faction Invitation',
        options = {
            {
                title = 'Accept Invitation',
                description = string.format('Join %s as %s', inviteData.factionLabel, inviteData.rankLabel),
                icon = 'check',
                onSelect = function()
                    TriggerServerEvent('faction:respondToInvite', inviteData.factionId, true, inviteData.rank)
                end
            },
            {
                title = 'Decline Invitation',
                description = 'Reject this faction invitation',
                icon = 'xmark',
                onSelect = function()
                    TriggerServerEvent('faction:respondToInvite', inviteData.factionId, false)
                end
            }
        }
    })
    
    lib.showContext('faction_invite')
    
    -- Also show a notification
    lib.notify({
        type = 'info',
        title = 'Faction Invitation',
        description = string.format('You have been invited to join %s as %s', inviteData.factionLabel, inviteData.rankLabel),
        duration = 10000
    })
end)

RegisterNUICallback('adminConfirmApproveReport', function(data, cb)
    cb('ok')
    local reportId = data.reportId
    if not reportId then return end
    
    -- Keep NUI visible but disable input temporarily
    SetNuiFocus(false, false)
    
    -- Show ox_lib input dialog with select for confirmation
    local input = lib.inputDialog('Approve Report', {
        {
            type = 'select',
            label = 'Approve this report? This will create a violation for the target faction.',
            description = 'Select an option below',
            options = {
                { value = 'yes', label = 'Yes, approve report' },
                { value = 'no', label = 'Cancel' }
            },
            required = true
        }
    })
    
    -- Re-enable NUI focus
    SetNuiFocus(true, true)
    
    if input and input[1] == 'yes' then
        TriggerServerEvent('faction:adminUpdateReport', reportId, 'approved')
        CreateThread(function()
            Wait(100)
            TriggerServerEvent('faction:adminGetReports')
        end)
    end
end)

RegisterNUICallback('adminConfirmRejectReport', function(data, cb)
    cb('ok')
    local reportId = data.reportId
    if not reportId then return end
    
    -- Keep NUI visible but disable input temporarily
    SetNuiFocus(false, false)
    
    -- Show ox_lib input dialog with select for confirmation
    local input = lib.inputDialog('Reject Report', {
        {
            type = 'select',
            label = 'Reject this report? The violation will not be created.',
            description = 'Select an option below',
            options = {
                { value = 'yes', label = 'Yes, reject report' },
                { value = 'no', label = 'Cancel' }
            },
            required = true
        }
    })
    
    -- Re-enable NUI focus
    SetNuiFocus(true, true)
    
    if input and input[1] == 'yes' then
        TriggerServerEvent('faction:adminUpdateReport', reportId, 'rejected')
        CreateThread(function()
            Wait(100)
            TriggerServerEvent('faction:adminGetReports')
        end)
    end
end)

RegisterNUICallback('adminConfirmDeleteReport', function(data, cb)
    cb('ok')
    local reportId = data.reportId
    if not reportId then return end
    
    -- Keep NUI visible but disable input temporarily
    SetNuiFocus(false, false)
    
    -- Show ox_lib input dialog with select for confirmation
    local input = lib.inputDialog('Delete Report', {
        {
            type = 'select',
            label = 'Are you sure you want to delete this handled report?',
            description = 'Select an option below',
            options = {
                { value = 'yes', label = 'Yes, delete report' },
                { value = 'no', label = 'Cancel' }
            },
            required = true
        }
    })
    
    -- Re-enable NUI focus
    SetNuiFocus(true, true)
    
    if input and input[1] == 'yes' then
        TriggerServerEvent('faction:adminDeleteReport', reportId)
        CreateThread(function()
            Wait(100)
            TriggerServerEvent('faction:adminGetReports')
        end)
    end
end)

RegisterNUICallback('adminDeleteReport', function(data, cb)
    cb('ok')
    local reportId = data.reportId
    if reportId then
        TriggerServerEvent('faction:adminDeleteReport', reportId)
        -- Refresh reports list
        Wait(100)
        TriggerServerEvent('faction:adminGetReports')
    end
end)

RegisterNUICallback('adminUpdateReport', function(data, cb)
    cb('ok')
    local reportId = data.reportId
    local status = data.status
    if reportId and status then
        TriggerServerEvent('faction:adminUpdateReport', reportId, status)
        -- Refresh reports list
        Wait(100)
        TriggerServerEvent('faction:adminGetReports')
    end
end)

RegisterNUICallback('adminCreateFaction', function(data, cb)
    cb('ok')
    -- Keep NUI visible but temporarily disable focus for dialog
    -- Don't hide the NUI, just disable input so ox_lib dialog can appear on top
    SetNuiFocus(false, false)
    -- Don't send 'hide' - keep NUI visible in background
    
    -- Open create faction dialog (will appear on top of NUI)
    local input = lib.inputDialog('Create New Faction', {
        {
            type = 'input',
            label = 'Faction Name (unique identifier)',
            description = 'Lowercase, no spaces (e.g., "ballas", "vagos")',
            required = true,
            min = 3,
            max = 30
        },
        {
            type = 'input',
            label = 'Faction Label (display name)',
            description = 'Display name for the faction (e.g., "Ballas", "Vagos")',
            required = true,
            min = 3,
            max = 50
        },
        {
            type = 'select',
            label = 'Faction Type',
            options = {
                { value = 'gang', label = 'Gang' },
                { value = 'mafia', label = 'Mafia' },
                { value = 'cartel', label = 'Cartel' },
                { value = 'organization', label = 'Organization' }
            },
            required = true
        }
    })
    
    -- Restore NUI focus after dialog closes (whether confirmed or cancelled)
    Wait(50)
    SetNuiFocus(true, true)
    -- NUI is already visible, no need to send 'show'
    
    if input and input[1] and input[2] and input[3] then
        TriggerServerEvent('faction:adminCreateFaction', input[1], input[2], input[3])
    end
end)

-- Admin faction management callbacks
RegisterNUICallback('adminDeleteFaction', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    if factionId then
        TriggerServerEvent('faction:adminDeleteFaction', factionId)
        -- Refresh factions list
        Wait(200)
        TriggerServerEvent('faction:adminGetFactions')
    end
end)

RegisterNUICallback('adminUpdateFaction', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    local updates = data.updates
    if factionId and updates then
        TriggerServerEvent('faction:adminUpdateFaction', factionId, updates)
        -- Refresh factions list
        Wait(200)
        TriggerServerEvent('faction:adminGetFactions')
    end
end)

local ALLOWED_INVITE_RANKS = { runner = true, member = true, shot_caller = true, big_homie = true, boss = true }
RegisterNUICallback('adminInviteMember', function(data, cb)
    cb('ok')
    local factionId = tonumber(data.factionId)
    local target = type(data.targetIdentifierOrServerId) == 'string' and data.targetIdentifierOrServerId:sub(1, 60) or nil
    local rank = type(data.rank) == 'string' and data.rank or 'runner'
    if not ALLOWED_INVITE_RANKS[rank] then rank = 'runner' end
    if factionId and factionId > 0 and target and target:len() > 0 then
        TriggerServerEvent('faction:adminInviteMember', factionId, target:gsub('^%s+', ''):gsub('%s+$', ''), rank)
    end
end)

RegisterNUICallback('adminGetFactionMembers', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    if factionId then
        TriggerServerEvent('faction:adminGetFactionMembers', factionId)
    end
end)

RegisterNUICallback('adminKickMember', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    local memberIdOrIdentifier = data.memberIdOrIdentifier
    if factionId and memberIdOrIdentifier then
        TriggerServerEvent('faction:adminKickMember', factionId, memberIdOrIdentifier)
        -- Refresh members list
        Wait(200)
        TriggerServerEvent('faction:adminGetFactionMembers', factionId)
    end
end)

RegisterNUICallback('adminSetMemberRank', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    local memberIdOrIdentifier = data.memberIdOrIdentifier
    local rank = data.rank
    if factionId and memberIdOrIdentifier and rank then
        TriggerServerEvent('faction:adminSetMemberRank', factionId, memberIdOrIdentifier, rank)
        -- Refresh members list
        Wait(200)
        TriggerServerEvent('faction:adminGetFactionMembers', factionId)
    end
end)

RegisterNUICallback('memberAddWarning', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    local memberId = data.memberId
    local reason = data.reason
    if memberId and reason then
        TriggerServerEvent('faction:addWarning', memberId, reason)
        -- Refresh members list
        Wait(200)
        if factionId then
            TriggerServerEvent('faction:adminGetFactionMembers', factionId)
        elseif currentFaction and currentFaction.faction then
            TriggerServerEvent('faction:getMembers')
        end
    end
end)

RegisterNUICallback('adminTransferBoss', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    local newBossMemberIdOrIdentifier = data.newBossMemberIdOrIdentifier
    if factionId and newBossMemberIdOrIdentifier then
        TriggerServerEvent('faction:adminTransferBoss', factionId, newBossMemberIdOrIdentifier)
        -- Refresh factions and members
        Wait(200)
        TriggerServerEvent('faction:adminGetFactions')
        TriggerServerEvent('faction:adminGetFactionMembers', factionId)
    end
end)

-- NUI requests ox_lib confirmation (replaces JS confirm/prompt)
RegisterNUICallback('requestTransferConfirm', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    local newBossMemberIdOrIdentifier = data.newBossMemberIdOrIdentifier
    local memberName = data.memberName or 'this member'
    if not factionId or not newBossMemberIdOrIdentifier then return end
    local confirm = lib.alertDialog({
        header = 'Transfer Leadership',
        content = 'Transfer leadership to **' .. (memberName:gsub('**', '')) .. '**? The current boss will become Shot Caller.',
        centered = true,
        cancel = true
    })
    if confirm == 'confirm' then
        TriggerServerEvent('faction:adminTransferBoss', factionId, newBossMemberIdOrIdentifier)
        Wait(200)
        TriggerServerEvent('faction:adminGetFactions')
        TriggerServerEvent('faction:adminGetFactionMembers', factionId)
    end
end)

RegisterNUICallback('requestKickConfirm', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    local memberIdOrIdentifier = data.memberIdOrIdentifier
    local memberName = data.memberName or 'this member'
    if not factionId or not memberIdOrIdentifier then return end
    local confirm = lib.alertDialog({
        header = 'Kick Member',
        content = 'Are you sure you want to kick **' .. (memberName:gsub('**', '')) .. '** from the faction?',
        centered = true,
        cancel = true
    })
    if confirm == 'confirm' then
        TriggerServerEvent('faction:adminKickMember', factionId, memberIdOrIdentifier)
        Wait(200)
        TriggerServerEvent('faction:adminGetFactionMembers', factionId)
    end
end)

RegisterNUICallback('requestAddWarning', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    local memberId = data.memberId
    local memberName = data.memberName or 'this member'
    if not memberId then return end
    local input = lib.inputDialog('Add Warning', {
        {
            type = 'textarea',
            label = 'Reason',
            description = 'Add a warning to **' .. (memberName:gsub('**', '')) .. '**. Enter the reason below.',
            placeholder = 'Enter reason for this warning...',
            required = true
        }
    })
    if input and input[1] and input[1]:len() > 0 then
        TriggerServerEvent('faction:addWarning', memberId, input[1])
        Wait(200)
        if factionId then
            TriggerServerEvent('faction:adminGetFactionMembers', factionId)
        elseif currentFaction and currentFaction.faction then
            TriggerServerEvent('faction:getMembers')
        end
    end
end)

-- Rules management callbacks
RegisterNUICallback('adminCreateRule', function(data, cb)
    cb('ok')
    local ruleData = {
        title = data.title,
        content = data.content,
        isGlobal = data.isGlobal,
        factionId = data.factionId,
        order = data.order
    }
    TriggerServerEvent('faction:adminCreateRule', ruleData)
    -- Refresh rules
    Wait(300)
    TriggerServerEvent('faction:adminGetRules')
end)

RegisterNUICallback('adminUpdateRule', function(data, cb)
    cb('ok')
    local ruleData = {
        ruleId = data.ruleId,
        title = data.title,
        content = data.content,
        isGlobal = data.isGlobal,
        factionId = data.factionId,
        order = data.order
    }
    TriggerServerEvent('faction:adminUpdateRule', ruleData)
    -- Refresh rules
    Wait(300)
    TriggerServerEvent('faction:adminGetRules')
end)

RegisterNUICallback('adminDeleteRule', function(data, cb)
    cb('ok')
    local ruleId = data.ruleId
    if ruleId then
        TriggerServerEvent('faction:adminDeleteRule', ruleId)
        -- Refresh rules
        Wait(100)
        TriggerServerEvent('faction:adminGetRules')
    end
end)

-- Receive rules for members
RegisterNetEvent('faction:receiveRules', function(rules)
    SendNUIMessage({
        action = 'updateTab',
        tab = 'rules',
        content = {
            rules = rules
        }
    })
end)

-- Receive rules for admins
RegisterNetEvent('faction:adminReceiveRules', function(rules, factions)
    SendNUIMessage({
        action = 'updateTab',
        tab = 'rules',
        content = {
            rules = rules,
            factions = factions
        }
    })
end)

-- Admin conflict management callbacks
RegisterNUICallback('adminSetConflictStatus', function(data, cb)
    cb('ok')
    local conflictId = data.conflictId
    local status = data.status
    if conflictId and status then
        TriggerServerEvent('faction:adminSetConflictStatus', conflictId, status)
    end
end)

RegisterNUICallback('adminCreateConflict', function(data, cb)
    cb('ok')
    local faction1Id = data.faction1Id
    local faction2Id = data.faction2Id
    local conflictType = data.conflictType
    local reason = data.reason
    if faction1Id and faction2Id then
        TriggerServerEvent('faction:adminCreateConflict', faction1Id, faction2Id, conflictType, reason)
    end
end)

-- Admin conflict status confirmation (using ox_lib dialog)
RegisterNUICallback('adminConfirmConflictStatus', function(data, cb)
    cb('ok')
    local conflictId = data.conflictId
    local status = data.status
    local actionText = data.actionText or 'change status'
    
    if not conflictId or not status then return end
    
    -- Keep NUI visible but disable input temporarily
    SetNuiFocus(false, false)
    
    -- Show ox_lib input dialog with select for confirmation
    local input = lib.inputDialog('Confirm Conflict Status Change', {
        {
            type = 'select',
            label = 'Are you sure you want to ' .. actionText .. ' this conflict?',
            description = 'Select an option below',
            options = {
                { value = 'yes', label = 'Yes, ' .. actionText .. ' this conflict' },
                { value = 'no', label = 'Cancel - Keep current status' }
            },
            required = true
        }
    })
    
    -- Re-enable NUI focus
    SetNuiFocus(true, true)
    
    if input and input[1] == 'yes' then
        TriggerServerEvent('faction:adminSetConflictStatus', conflictId, status)
    end
    -- If input is nil or 'no', user cancelled - NUI focus already restored
end)

-- Admin cooldown management callbacks
RegisterNUICallback('adminSetCooldown', function(data, cb)
    cb('ok')
    local factionId = data.factionId
    local cooldownType = data.cooldownType
    local durationSeconds = data.durationSeconds
    local reason = data.reason
    if factionId and cooldownType and durationSeconds then
        TriggerServerEvent('faction:adminSetCooldown', factionId, cooldownType, durationSeconds, reason)
    end
end)

RegisterNUICallback('adminConfirmRemoveCooldown', function(data, cb)
    cb('ok')
    local cooldownId = data.cooldownId
    
    if not cooldownId then return end
    
    -- Keep NUI visible but disable input temporarily
    SetNuiFocus(false, false)
    
    -- Show ox_lib input dialog with select for confirmation
    local input = lib.inputDialog('Confirm Remove Cooldown', {
        {
            type = 'select',
            label = 'Are you sure you want to remove this cooldown?',
            description = 'Select an option below',
            options = {
                { value = 'yes', label = 'Yes, remove cooldown' },
                { value = 'no', label = 'Cancel - Keep cooldown' }
            },
            required = true
        }
    })
    
    -- Re-enable NUI focus
    SetNuiFocus(true, true)
    
    if input and input[1] == 'yes' then
        TriggerServerEvent('faction:adminRemoveCooldown', cooldownId)
    end
end)
