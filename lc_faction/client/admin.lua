-- Admin panel: factions, members, wars, CK (ox_lib)

local adminFactions = {}
local adminWars = {}
local adminCKs = {}
local adminMembers = {}

-- Admin command - opens admin panel (NUI)
RegisterCommand('factionadmin', function()
    -- Verify admin status server-side before opening
    TriggerServerEvent('faction:checkAdminAndOpenPanel')
end, false)

-- Receive admin panel open event from server (after verification)
RegisterNetEvent('faction:openAdminPanel', function()
    OpenAdminPanel()
end)

-- Open admin NUI panel
function OpenAdminPanel()
    SetNuiFocus(true, true)
    SendNUIMessage({ 
        action = 'open', 
        factions = {}, 
        isAdmin = true 
    })
end

function OpenAdminMenu()
    lib.registerContext({
        id = 'faction_admin_main',
        title = 'Faction Management Admin',
        options = {
            {
                title = 'Conflicts',
                description = 'Manage active wars and conflicts',
                icon = 'sword',
                onSelect = function()
                    TriggerServerEvent('faction:adminGetActiveWars')
                end
            },
            {
                title = 'Weapon Registration',
                description = 'Log guns to specific factions',
                icon = 'gun',
                onSelect = function()
                    AdminWeaponRegistration()
                end
            },
            {
                title = 'Cooldowns',
                description = 'View and manage faction cooldowns',
                icon = 'clock',
                onSelect = function()
                    AdminCooldowns()
                end
            },
            {
                title = 'Violations',
                description = 'View all faction violations',
                icon = 'triangle-exclamation',
                onSelect = function()
                    AdminViolations()
                end
            },
            {
                title = 'Factions',
                description = 'Edit faction names, reputation, members, etc.',
                icon = 'users',
                onSelect = function()
                    TriggerServerEvent('faction:adminGetFactions')
                end
            },
            {
                title = 'Reports',
                description = 'View faction reports for admin review',
                icon = 'file-lines',
                onSelect = function()
                    -- Ensure NUI is closed before opening reports menu
                    SetNuiFocus(false, false)
                    SendNUIMessage({ action = 'close' })
                    Wait(50)
                    TriggerServerEvent('faction:adminGetReports')
                end
            },
            {
                title = 'CK Requests',
                description = 'View and manage CK requests',
                icon = 'user-xmark',
                onSelect = function()
                    TriggerServerEvent('faction:adminGetPendingCKs', nil)
                end
            },
            {
                title = 'Territory',
                description = 'Assign and manage faction territory',
                icon = 'map',
                onSelect = function()
                    AdminTerritory()
                end
            }
        }
    })
    lib.showContext('faction_admin_main')
end

-- Admin weapon registration
function AdminWeaponRegistration()
    -- Get list of factions to select from
    TriggerServerEvent('faction:adminGetFactionsForWeapon')
end

-- Handle faction selection for weapon registration
RegisterNetEvent('faction:adminReceiveFactionsForWeapon', function(factions)
    -- Send faction list to NUI instead of opening ox_lib menu
    SendNUIMessage({
        action = 'updateTab',
        tab = 'weapons',
        content = {
            step = 'select_faction',
            factions = factions or {}
        }
    })
end)

-- Handle receiving weapons list for a faction
RegisterNetEvent('faction:adminReceiveFactionWeapons', function(factionId, factionLabel, weapons)
    -- Send weapons list to NUI (faction label is passed from server)
    SendNUIMessage({
        action = 'updateTab',
        tab = 'weapons',
        content = {
            step = 'view_weapons',
            factionId = factionId,
            factionLabel = factionLabel or 'Unknown Faction',
            weapons = weapons or {}
        }
    })
end)

function RegisterWeaponToFaction(factionId, factionLabel)
    local input = lib.inputDialog('Register Weapon', {
        {
            type = 'input',
            label = 'Weapon Name',
            placeholder = 'e.g. AK-47',
            required = true
        },
        {
            type = 'input',
            label = 'Serial Number',
            placeholder = 'e.g. SN-123456',
            required = true
        },
        {
            type = 'input',
            label = 'Weapon Hash',
            placeholder = 'Weapon hash (optional)',
            required = false
        }
    })
    
    if input and input[1] and input[2] then
        TriggerServerEvent('faction:adminRegisterWeapon', factionId, input[1], input[2], input[3])
        -- Restore NUI focus after submitting
        Wait(50)
        SetNuiFocus(true, true)
    else
        -- User cancelled - restore NUI focus
        Wait(50)
        SetNuiFocus(true, true)
    end
end

-- Admin cooldowns view - fetches and displays in NUI
function AdminCooldowns()
    TriggerServerEvent('faction:adminGetCooldowns')
end

-- Admin violations view - handled by NUI now
RegisterNetEvent('faction:adminReceiveViolations', function(violations)
    -- Send violations list to NUI instead of opening ox_lib menu
    SendNUIMessage({
        action = 'updateTab',
        tab = 'violations',
        content = {
            items = violations or {},
            isAdmin = true
        }
    })
end)

-- Admin territory management
function AdminTerritory()
    -- Get list of factions to assign territory to
    TriggerServerEvent('faction:adminGetFactionsForTerritory')
end

-- Handle faction selection for territory assignment
RegisterNetEvent('faction:adminReceiveFactionsForTerritory', function(factions)
    -- Send faction list to NUI instead of opening ox_lib menu
    SendNUIMessage({
        action = 'updateTab',
        tab = 'territory',
        content = {
            step = 'select_faction',
            factions = factions or {}
        }
    })
end)

function AssignTerritoryToFaction(factionId, factionLabel)
    local input = lib.inputDialog('Assign Territory', {
        {
            type = 'input',
            label = 'Territory Name',
            placeholder = 'e.g. Grove Street',
            required = true
        },
        {
            type = 'select',
            label = 'Territory Type',
            options = {
                { value = 'turf', label = 'Turf' },
                { value = 'stash', label = 'Stash' },
                { value = 'shop', label = 'Shop' }
            },
            default = 'turf',
            required = true
        },
        {
            type = 'input',
            label = 'X Coordinate',
            placeholder = 'X coordinate',
            required = true
        },
        {
            type = 'input',
            label = 'Y Coordinate',
            placeholder = 'Y coordinate',
            required = true
        },
        {
            type = 'input',
            label = 'Z Coordinate',
            placeholder = 'Z coordinate',
            required = true
        },
        {
            type = 'input',
            label = 'Radius (meters)',
            placeholder = '50.0',
            default = '50.0',
            required = false
        },
        {
            type = 'input',
            label = 'Stash ID (optional)',
            placeholder = 'Leave empty if not applicable',
            required = false
        }
    })
    
    -- Restore NUI focus after dialog (whether cancelled or completed)
    Wait(100)
    SetNuiFocus(true, true)
    
    if input and input[1] and input[3] and input[4] and input[5] then
        local coords = {
            x = tonumber(input[3]),
            y = tonumber(input[4]),
            z = tonumber(input[5])
        }
        
        if not coords.x or not coords.y or not coords.z then
            lib.notify({
                type = 'error',
                description = 'Invalid coordinates'
            })
            return
        end
        
        TriggerServerEvent('faction:adminAssignTerritory', factionId, {
            name = input[1],
            type = input[2] or 'turf',
            x = coords.x,
            y = coords.y,
            z = coords.z,
            radius = tonumber(input[6]) or 50.0,
            stashId = input[7] or nil
        })
    end
end

function AdminCreateFaction()
    local input = lib.inputDialog('Create Faction', {
        { type = 'input', label = 'Name (id)', placeholder = 'e.g. ballas', required = true },
        { type = 'input', label = 'Display label', placeholder = 'e.g. Ballas', required = true },
        {
            type = 'select',
            label = 'Type',
            options = { { value = 'gang', label = 'Gang' }, { value = 'organization', label = 'Organization' } },
            default = 'gang'
        }
    })
    if input and input[1] and input[2] then
        TriggerServerEvent('faction:adminCreateFaction', input[1], input[2], input[3])
    end
end

RegisterNetEvent('faction:adminReceiveFactions', function(list)
    adminFactions = list or {}
    -- Always update the factions list in memory
    -- Send to NUI (NUI will handle gracefully if panel is not open)
    SendNUIMessage({
        action = 'updateTab',
        tab = 'overview',
        content = {
            isAdmin = true,
            factions = adminFactions
        }
    })
    SendNUIMessage({
        action = 'updateTab',
        tab = 'factions',
        content = {
            factions = adminFactions
        }
    })
end)

function AdminFactionSubmenu(faction)
    lib.registerContext({
        id = 'faction_admin_faction_sub',
        title = faction.label,
        menu = 'faction_admin_factions',
        options = {
            {
                title = 'Edit Faction',
                description = 'Name, label, type, reputation, gun drop',
                icon = 'pen',
                onSelect = function()
                    AdminEditFaction(faction)
                end
            },
            {
                title = 'Delete Faction',
                description = 'Permanently delete this faction',
                icon = 'trash',
                onSelect = function()
                    local confirm = lib.alertDialog({
                        header = 'Delete Faction',
                        content = 'Delete **' .. faction.label .. '**? This cannot be undone.',
                        centered = true,
                        cancel = true
                    })
                    if confirm == 'confirm' then
                        TriggerServerEvent('faction:adminDeleteFaction', faction.id)
                    end
                end
            },
            {
                title = 'Invite Member',
                description = 'By identifier or player server ID',
                icon = 'user-plus',
                onSelect = function()
                    AdminInviteMember(faction.id)
                end
            },
            {
                title = 'Kick Member',
                description = 'Remove a member',
                icon = 'user-minus',
                onSelect = function()
                    AdminKickMember(faction.id)
                end
            },
            {
                title = 'Transfer Leadership',
                description = 'Set a new boss',
                icon = 'crown',
                onSelect = function()
                    AdminTransferBoss(faction.id)
                end
            }
        }
    })
    lib.showContext('faction_admin_faction_sub')
end

function AdminEditFaction(faction)
    local input = lib.inputDialog('Edit Faction: ' .. faction.label, {
        { type = 'input', label = 'Name (id)', default = faction.name, required = true },
        { type = 'input', label = 'Display label', default = faction.label, required = true },
        {
            type = 'select',
            label = 'Type',
            options = { { value = 'gang', label = 'Gang' }, { value = 'organization', label = 'Organization' } },
            default = faction.type or 'gang'
        },
        { type = 'number', label = 'Reputation', default = faction.reputation or 0 },
        {
            type = 'checkbox',
            label = 'Gun drop eligible',
            checked = faction.gun_drop_eligible
        }
    })
    if input and input[1] and input[2] then
        TriggerServerEvent('faction:adminUpdateFaction', faction.id, {
            name = input[1],
            label = input[2],
            type = input[3],
            reputation = input[4],
            gun_drop_eligible = input[5]
        })
    end
end

function AdminInviteMember(factionId)
    local input = lib.inputDialog('Invite Member', {
        { type = 'input', label = 'Identifier or Server ID', placeholder = 'steam:xxx or player ID', required = true },
        {
            type = 'select',
            label = 'Rank',
            options = {
                { value = 'runner', label = 'Runner' },
                { value = 'member', label = 'Member' },
                { value = 'shot_caller', label = 'Shot Caller' },
                { value = 'boss', label = 'Boss' }
            },
            default = 'runner'
        }
    })
    if input and input[1] then
        local target = input[1]
        if tonumber(target) then
            TriggerServerEvent('faction:adminInviteMember', factionId, tonumber(target), input[2])
        else
            TriggerServerEvent('faction:adminInviteMember', factionId, target, input[2])
        end
    end
end

local pendingAdminAction = nil
local pendingFactionId = nil

function AdminKickMember(factionId)
    pendingAdminAction = 'kick'
    pendingFactionId = factionId
    TriggerServerEvent('faction:adminGetFactionMembers', factionId)
end

function AdminTransferBoss(factionId)
    pendingAdminAction = 'transfer'
    pendingFactionId = factionId
    TriggerServerEvent('faction:adminGetFactionMembers', factionId)
end

RegisterNetEvent('faction:adminReceiveFactionMembers', function(factionId, members)
    -- Send to NUI for display
    SendNUIMessage({
        action = 'updateTab',
        tab = 'members',
        content = {
            items = members or {},
            factionId = factionId,
            isAdmin = true
        }
    })
    
    factionId = factionId or pendingFactionId
    local action = pendingAdminAction
    pendingAdminAction = nil
    pendingFactionId = nil
    
    -- Only show ox_lib menu when explicitly doing kick/transfer from legacy menu - not when just viewing members
    if action == 'transfer' then
        local options = {}
        for _, m in ipairs(members or {}) do
            if m.rank ~= 'boss' then
                table.insert(options, {
                    title = (m.player_name or m.identifier) .. ' (' .. (Config.Ranks[m.rank] and Config.Ranks[m.rank].label or m.rank) .. ')',
                    description = 'Set as new boss',
                    icon = 'crown',
                    onSelect = function()
                        TriggerServerEvent('faction:adminTransferBoss', factionId, m.id)
                    end
                })
            end
        end
        if #options == 0 then
            lib.notify({ type = 'info', description = 'No other members to transfer to' })
            return
        end
        lib.registerContext({
            id = 'faction_admin_transfer',
            title = 'Transfer Leadership',
            menu = 'faction_admin_factions',
            options = options
        })
        lib.showContext('faction_admin_transfer')
    elseif action == 'kick' then
        local options = {}
        for _, m in ipairs(members or {}) do
            table.insert(options, {
                title = (m.player_name or m.identifier) .. ' (' .. (Config.Ranks[m.rank] and Config.Ranks[m.rank].label or m.rank) .. ')',
                description = 'Kick from faction',
                icon = 'user-minus',
                onSelect = function()
                    local confirm = lib.alertDialog({
                        header = 'Kick Member',
                        content = 'Remove **' .. (m.player_name or m.identifier) .. '** from the faction?',
                        centered = true,
                        cancel = true
                    })
                    if confirm == 'confirm' then
                        TriggerServerEvent('faction:adminKickMember', factionId, m.id)
                    end
                end
            })
        end
        if #options == 0 then
            lib.notify({ type = 'info', description = 'No members' })
            return
        end
        lib.registerContext({
            id = 'faction_admin_kick',
            title = 'Kick Member',
            menu = 'faction_admin_factions',
            options = options
        })
        lib.showContext('faction_admin_kick')
    end
    -- When action is nil: just viewing members - NUI already has the data, no ox_lib popup
end)

-- Active wars
RegisterNetEvent('faction:adminReceiveActiveWars', function(conflicts, factions)
    adminWars = conflicts or {}
    -- Send conflicts and factions list to NUI
    SendNUIMessage({
        action = 'updateTab',
        tab = 'conflicts',
        content = {
            conflicts = adminWars,
            factions = factions or {}
        }
    })
end)

-- Refresh conflicts list (triggered after status change)
RegisterNetEvent('faction:adminRefreshConflicts', function()
    TriggerServerEvent('faction:adminGetActiveWars')
end)

-- Refresh rules list (triggered after rule change)
RegisterNetEvent('faction:adminRefreshRules', function()
    TriggerServerEvent('faction:adminGetRules')
end)

-- Receive cooldowns for admin
RegisterNetEvent('faction:adminReceiveCooldowns', function(cooldowns, factions)
    SendNUIMessage({
        action = 'updateTab',
        tab = 'cooldowns',
        content = {
            cooldowns = cooldowns or {},
            factions = factions or {}
        }
    })
end)

-- Refresh cooldowns list (triggered after cooldown change)
RegisterNetEvent('faction:adminRefreshCooldowns', function()
    TriggerServerEvent('faction:adminGetCooldowns')
end)

function AdminWarSubmenu(war)
    lib.registerContext({
        id = 'faction_admin_war_sub',
        title = war.faction1_label .. ' vs ' .. war.faction2_label,
        menu = 'faction_admin_wars',
        options = {
            {
                title = 'End War',
                description = 'End this war now',
                icon = 'flag-checkered',
                onSelect = function()
                    TriggerServerEvent('faction:adminEndWar', war.id)
                end
            },
            {
                title = 'Set Duration',
                description = 'Set end time from start (seconds)',
                icon = 'clock',
                onSelect = function()
                    local input = lib.inputDialog('War Duration', {
                        { type = 'number', label = 'Duration (seconds)', default = Config.Conflict.warDuration or 3600, min = 60 }
                    })
                    if input and input[1] then
                        TriggerServerEvent('faction:adminSetWarDuration', war.id, input[1])
                    end
                end
            }
        }
    })
    lib.showContext('faction_admin_war_sub')
end

-- Return the admin player's current world coords so NUI can fill the territory form
RegisterNUICallback('getPlayerCoords', function(_, cb)
    local coords = GetEntityCoords(PlayerPedId())
    cb({ x = coords.x, y = coords.y, z = coords.z })
end)

-- Admin CK action callback (approve / reject / execute from NUI)
RegisterNUICallback('adminUpdateCK', function(data, cb)
    cb('ok')
    local ckId  = tonumber(data.ckId)
    local status = type(data.status) == 'string' and data.status or nil
    local allowed = { pending = true, approved = true, rejected = true, executed = true }
    if not ckId or not status or not allowed[status] then return end
    TriggerServerEvent('faction:adminUpdateCK', ckId, status)
    CreateThread(function()
        Wait(250)
        TriggerServerEvent('faction:adminGetPendingCKs', nil)
    end)
end)

-- CK requests
RegisterNetEvent('faction:adminReceivePendingCKs', function(list)
    adminCKs = list or {}
    -- Send CK requests list to NUI instead of opening ox_lib menu
    SendNUIMessage({
        action = 'updateTab',
        tab = 'ck',
        content = {
            items = adminCKs,
            isAdmin = true
        }
    })
end)

function AdminCKSubmenu(ck)
    lib.registerContext({
        id = 'faction_admin_ck_sub',
        title = ck.target_name,
        menu = 'faction_admin_cks',
        options = {
            {
                title = 'Approve',
                description = 'Approve this CK request',
                icon = 'check',
                onSelect = function()
                    TriggerServerEvent('faction:adminUpdateCK', ck.id, 'approved')
                end
            },
            {
                title = 'Reject',
                description = 'Reject this CK request',
                icon = 'xmark',
                onSelect = function()
                    TriggerServerEvent('faction:adminUpdateCK', ck.id, 'rejected')
                end
            },
            {
                title = 'Mark Executed',
                description = 'Mark as executed (triggers character deletion hook)',
                icon = 'skull',
                onSelect = function()
                    TriggerServerEvent('faction:adminUpdateCK', ck.id, 'executed')
                end
            }
        }
    })
    lib.showContext('faction_admin_ck_sub')
end

-- Receive admin reports
RegisterNetEvent('faction:adminReceiveReports', function(reports)
    -- Send reports list to NUI instead of opening ox_lib menu
    SendNUIMessage({
        action = 'updateTab',
        tab = 'reports',
        content = {
            items = reports or {},
            isAdmin = true
        }
    })
end)

function ViewReportDetails(report)
    local targetText = report.target_faction_label and (' → ' .. report.target_faction_label) or ''
    local options = {
        {
            title = 'Report Type',
            description = report.report_type or 'Unknown',
            icon = 'tag'
        },
        {
            title = 'Reporter',
            description = report.reporter_name or 'Unknown',
            icon = 'user'
        },
        {
            title = 'Faction',
            description = (report.faction_label or 'Unknown') .. targetText,
            icon = 'users'
        },
        {
            title = 'Status',
            description = report.status or 'pending',
            icon = 'circle-check'
        },
        {
            title = 'Details',
            description = report.details or 'No details',
            icon = 'file-lines'
        },
        {
            title = 'Date',
            description = FormatDateForReport(report.created_at),
            icon = 'calendar'
        }
    }
    
    -- Add approve/reject options if pending
    if report.status == 'pending' then
        table.insert(options, {
            title = 'Approve Report',
            description = 'Violation against reported gang is valid',
            icon = 'check',
            onSelect = function()
                TriggerServerEvent('faction:adminUpdateReport', report.id, 'approved')
            end
        })
        
        table.insert(options, {
            title = 'Reject Report',
            description = 'Violation does not have enough evidence to be valid',
            icon = 'xmark',
            onSelect = function()
                TriggerServerEvent('faction:adminUpdateReport', report.id, 'rejected')
            end
        })
    end
    
    lib.registerContext({
        id = 'faction_admin_report_details',
        title = 'Report Details',
        menu = 'faction_admin_reports',
        options = options,
        onExit = function()
            -- Restore NUI focus when menu is closed
            Wait(50)
            SetNuiFocus(true, true)
        end
    })
    
    lib.showContext('faction_admin_report_details')
end

-- Helper function to format dates for reports (client-side, no os library)
function FormatDateForReport(timestamp)
    if not timestamp then return 'Unknown' end
    
    -- Handle MySQL timestamp strings (YYYY-MM-DD HH:MM:SS)
    if type(timestamp) == 'string' then
        -- Extract date and time parts
        local dateTime = timestamp:match('^(%d+%-%d+%-%d+%s+%d+:%d+:%d+)')
        if dateTime then
            -- Format as MM/DD/YYYY HH:MM
            local year, month, day, hour, min = dateTime:match('(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):')
            if year and month and day and hour and min then
                return string.format('%s/%s/%s %s:%s', month, day, year, hour, min)
            end
            return dateTime
        end
        -- Just date part
        local datePart = timestamp:match('^(%d+%-%d+%-%d+)')
        if datePart then
            local year, month, day = datePart:match('(%d+)-(%d+)-(%d+)')
            if year and month and day then
                return string.format('%s/%s/%s', month, day, year)
            end
            return datePart
        end
    end
    
    -- Handle Unix timestamp (number)
    if type(timestamp) == 'number' then
        return 'Recent'
    end
    
    -- Fallback
    local str = tostring(timestamp)
    local dateTime = str:match('(%d+%-%d+%-%d+%s+%d+:%d+:%d+)')
    if dateTime then
        local year, month, day, hour, min = dateTime:match('(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):')
        if year and month and day and hour and min then
            return string.format('%s/%s/%s %s:%s', month, day, year, hour, min)
        end
        return dateTime
    end
    
    local datePart = str:match('(%d+%-%d+%-%d+)')
    if datePart then
        local year, month, day = datePart:match('(%d+)-(%d+)-(%d+)')
        if year and month and day then
            return string.format('%s/%s/%s', month, day, year)
        end
        return datePart
    end
    
    return str:sub(1, 19) -- Take first 19 chars (date + time)
end