-- Faction UI using ox_lib - Role-based system

local isMenuOpen = false

-- Check if player is boss or big homie
local function IsManagement()
    if not currentFaction then return false end
    local rank = currentFaction.rank
    return rank == 'boss' or rank == 'big_homie'
end

-- Check if player can claim territory
local function CanClaimTerritory()
    if not currentFaction then return false end
    local rank = currentFaction.rank
    return rank == 'boss' or rank == 'big_homie'
end

function OpenFactionMenu()
    if isMenuOpen then return end
    if not currentFaction then return end
    
    isMenuOpen = true
    
    local isManagement = IsManagement()
    local menuTitle = isManagement and 'Faction Management' or 'Faction Panel'
    
    local options = {}
    
    -- Regular member options
    -- Report tab is now handled in NUI, not in this menu
    
    table.insert(options, {
        title = 'Members',
        description = 'View faction members and confirm identities',
        icon = 'users',
        onSelect = function()
            OpenMembersTab()
        end
    })
    
    -- CK Request - available to all members (moved to prominent position)
    table.insert(options, {
        title = 'CK Request',
        description = 'Request a character kill on a player from another faction',
        icon = 'user-xmark',
        onSelect = function()
            OpenCKRequestTab()
        end
    })
    
    table.insert(options, {
        title = 'Territory',
        description = isManagement and 'View and claim faction territory' or 'View faction territory',
        icon = 'map',
        onSelect = function()
            OpenTerritoryTab()
        end
    })
    
    table.insert(options, {
        title = 'Reputation',
        description = 'View faction reputation and your rank',
        icon = 'star',
        onSelect = function()
            OpenReputationTab()
        end
    })
    
    table.insert(options, {
        title = 'Conflicts',
        description = 'View active wars and conflicts',
        icon = 'sword',
        onSelect = function()
            OpenConflictsTab()
        end
    })
    
    table.insert(options, {
        title = 'Cooldowns',
        description = 'View faction cooldowns and timers',
        icon = 'clock',
        onSelect = function()
            OpenCooldownsTab()
        end
    })
    
    table.insert(options, {
        title = 'Weapons',
        description = 'View logged faction weapons and serial numbers',
        icon = 'gun',
        onSelect = function()
            OpenWeaponsTab()
        end
    })
    
    table.insert(options, {
        title = 'Warnings',
        description = 'View member warnings in your faction',
        icon = 'exclamation-triangle',
        onSelect = function()
            OpenWarningsTab()
        end
    })
    
    -- Management-only options (added at end if management)
    if isManagement then
        -- Management options would go here if needed
    end
    
    lib.registerContext({
        id = 'faction_main_menu',
        title = menuTitle,
        options = options
    })
    
    lib.showContext('faction_main_menu')
    
    CreateThread(function()
        while isMenuOpen do
            Wait(50)
            if not lib.getOpenContextMenu() then
                isMenuOpen = false
                break
            end
        end
    end)
end

-- Faction Report Tab - now handled in NUI
function OpenFactionReportTab()
    -- This function is deprecated - Report tab now uses NUI
    -- Do nothing - the NUI handles everything
end

RegisterNetEvent('faction:receiveFactionListForReport', function(factions)
    -- Send faction list to NUI
    local factionList = {}
    for _, faction in ipairs(factions) do
        table.insert(factionList, {
            id = faction.id,
            label = faction.label,
            name = faction.name
        })
    end
    
    SendNUIMessage({
        action = 'updateTab',
        tab = 'report',
        content = {
            step = 'select_target_faction',
            factions = factionList
        }
    })
end)

function SubmitReportOnFaction(targetFactionId)
    local input = lib.inputDialog('Faction Report', {
        {
            type = 'select',
            label = 'Report Type',
            options = {
                { value = 'violation', label = 'Violation' },
                { value = 'dispute', label = 'Territory Dispute' },
                { value = 'member', label = 'Member Issue' },
                { value = 'other', label = 'Other' }
            },
            required = true
        },
        {
            type = 'textarea',
            label = 'Report Details',
            placeholder = 'Describe the issue...',
            required = true
        }
    })
    
    if input and input[1] and input[2] then
        TriggerServerEvent('faction:submitReport', input[1], input[2], targetFactionId)
    end
end

function OpenMembersTab()
    TriggerServerEvent('faction:getMembers')
end

RegisterNetEvent('faction:receiveMembers', function(members)
    -- Send to NUI - include raw members and isManagement for Boss/Big Homie to manage
    local items = {}
    for _, member in ipairs(members) do
        local lastActive = member.last_active > 0 and ('Last active: ' .. FormatTime(member.last_active)) or 'Never active'
        local memberText = string.format('<strong>%s</strong><br>Rank: %s | Warnings: %d | CKs: %d | Rep: %d | %s', 
            member.player_name or 'Unknown',
            Config.Ranks[member.rank] and Config.Ranks[member.rank].label or member.rank, 
            member.warnings or 0, 
            member.cks_involved or 0, 
            member.reputation_contribution or 0,
            lastActive)
        table.insert(items, memberText)
    end
    
    local isManagement = currentFaction and (currentFaction.rank == 'boss' or currentFaction.rank == 'big_homie')
    local factionId = currentFaction and currentFaction.faction and currentFaction.faction.id or nil
    
    SendNUIMessage({
        action = 'updateTab',
        tab = 'members',
        content = { 
            items = items, 
            members = members,
            isManagement = isManagement,
            factionId = factionId
        }
    })
end)

function OpenTerritoryTab()
    TriggerServerEvent('faction:getTerritory')
end

RegisterNetEvent('faction:receiveTerritory', function(territory)
    local items = {}
    
    if #territory == 0 then
        table.insert(items, 'No Territory Claimed - Claim territory to get started')
    else
        for _, terr in ipairs(territory) do
            local nearbyText = ''
            if terr.nearby_factions and #terr.nearby_factions > 0 then
                nearbyText = ' | Nearby: ' .. terr.nearby_factions[1].faction.label
            end
            
            table.insert(items, string.format('<strong>%s</strong><br>Type: %s | Members: %d | Sell Time: %ds%s', 
                terr.name,
                terr.type, 
                terr.active_members or 0, 
                terr.sell_time or 0,
                nearbyText))
        end
    end
    
    SendNUIMessage({
        action = 'updateTab',
        tab = 'territory',
        content = { items = items }
    })
    
    -- If management, show claim option via notification
    if CanClaimTerritory() then
        lib.notify({
            type = 'info',
            description = 'Use the menu to claim new territory'
        })
    end
end)

function ClaimTerritory()
    if not CanClaimTerritory() then
        lib.notify({
            type = 'error',
            description = 'Only Big Homie and Boss can claim territory'
        })
        return
    end
    
    local coords = GetEntityCoords(PlayerPedId())
    
    local input = lib.inputDialog('Claim Territory', {
        {
            type = 'input',
            label = 'Territory Name',
            required = true
        },
        {
            type = 'select',
            label = 'Type',
            options = {
                { value = 'corner', label = 'Corner' },
                { value = 'trap_house', label = 'Trap House' },
                { value = 'stash', label = 'Stash Location' }
            },
            required = true
        },
        {
            type = 'number',
            label = 'Radius (meters)',
            default = 50,
            required = true
        },
        {
            type = 'input',
            label = 'Stash ID (optional)',
            required = false
        }
    })
    
    if input and input[1] and input[2] and input[3] then
        TriggerServerEvent('faction:claimTerritory', {
            x = coords.x,
            y = coords.y,
            z = coords.z,
            name = input[1],
            type = input[2],
            radius = input[3],
            stashId = input[4] or nil
        })
    end
end

function OpenReputationTab()
    if not currentFaction then return end
    
    local faction = currentFaction.faction
    local playerRank = currentFaction.rank
    local rankLabel = Config.Ranks[playerRank] and Config.Ranks[playerRank].label or playerRank
    
    -- Send to NUI
    SendNUIMessage({
        action = 'updateTab',
        tab = 'reputation',
        content = {
            reputation = faction.reputation or 0,
            rank = rankLabel,
            activeWars = (faction.active_wars or 0) .. ' / ' .. (faction.max_wars or 2),
            gunDropEligible = faction.gun_drop_eligible and 'Yes' or 'No'
        }
    })
end

function OpenConflictsTab()
    TriggerServerEvent('faction:getConflicts')
end

RegisterNetEvent('faction:receiveConflicts', function(data)
    -- Send conflicts data to NUI - it will determine which tab to update based on current tab
    -- Don't force update conflicts tab - only update if conflicts tab is active
    -- For overview tab, send conflicts separately
    SendNUIMessage({
        action = 'updateConflictsData',
        conflicts = data.conflicts or {},
        alliances = data.alliances or {}
    })
end)

function OpenCooldownsTab()
    TriggerServerEvent('faction:getCooldowns')
end

RegisterNetEvent('faction:receiveCooldowns', function(data)
    -- Send cooldowns data directly to NUI for proper rendering
    SendNUIMessage({
        action = 'updateTab',
        tab = 'cooldowns',
        content = {
            cooldowns = data.cooldowns or {},
            ckHistory = data.ckHistory or {}
        }
    })
end)

function ShowCKHistory(history)
    local options = {}
    
    for _, ck in ipairs(history) do
        table.insert(options, {
            title = ck.target_name,
            description = 'Status: ' .. ck.status .. ' | Reason: ' .. (ck.reason or 'None'),
            icon = 'user-xmark'
        })
    end
    
    lib.registerContext({
        id = 'ck_history',
        title = 'CK History',
        menu = 'faction_cooldowns',
        options = options
    })
    
    lib.showContext('ck_history')
end

function OpenWeaponsTab()
    TriggerServerEvent('faction:getWeapons')
end

-- Refresh weapons when notified (admin logged a weapon)
RegisterNetEvent('faction:refreshWeapons', function()
    -- Always refresh weapons data - members will see it next time they open the weapons tab
    -- The data is cached, so when they open the menu it will show the new weapon
    -- No need to force refresh if menu isn't open
end)

RegisterNetEvent('faction:receiveWeapons', function(weapons)
    -- Send weapons to NUI with possession info (full weapon objects, not just formatted strings)
    SendNUIMessage({
        action = 'updateTab',
        tab = 'weapons',
        content = {
            items = weapons,
            weapons = weapons
        }
    })
end)


function OpenWarningsTab()
    TriggerServerEvent('faction:getWarnings')
end

RegisterNetEvent('faction:receiveWarnings', function(warnings)
    local items = {}
    
    if #warnings == 0 then
        table.insert(items, 'No Warnings - No member warnings in your faction')
    else
        for _, warning in ipairs(warnings) do
            table.insert(items, string.format('<strong>%s</strong><br>Warnings: %d | Last: %s', 
                warning.member_name or 'Unknown',
                warning.warnings or 0,
                warning.last_warning_reason or 'N/A'))
        end
    end
    
    SendNUIMessage({
        action = 'updateTab',
        tab = 'warnings',
        content = { items = items }
    })
end)

-- CK Request Tab - now handled in NUI
function OpenCKRequestTab()
    -- This function is deprecated - CK request now uses NUI
    -- TriggerServerEvent('faction:getFactionListForCK')
end

RegisterNetEvent('faction:receiveFactionListForCK', function(factions)
    -- Send faction list to NUI
    local factionList = {}
    for _, faction in ipairs(factions) do
        table.insert(factionList, {
            id = faction.id,
            label = faction.label,
            name = faction.name
        })
    end
    
    SendNUIMessage({
        action = 'updateTab',
        tab = 'ck',
        content = {
            step = 'select_faction',
            factions = factionList
        }
    })
end)

function SelectPlayerForCK(factionId, factionLabel)
    -- Get online players from that faction
    TriggerServerEvent('faction:getFactionPlayersForCK', factionId)
end

RegisterNetEvent('faction:receiveFactionPlayersForCK', function(players, factionLabel)
    -- Send player list to NUI
    local playerList = {}
    for _, player in ipairs(players) do
        table.insert(playerList, {
            identifier = player.identifier,
            name = player.name,
            serverId = player.serverId
        })
    end
    
    SendNUIMessage({
        action = 'updateTab',
        tab = 'ck',
        content = {
            step = 'select_player',
            factionLabel = factionLabel,
            players = playerList
        }
    })
end)

function RequestCK(targetIdentifier, targetName, serverId)
    local input = lib.inputDialog('CK Request', {
        {
            type = 'input',
            label = 'Target Name',
            default = targetName .. ' (ID: ' .. serverId .. ')',
            disabled = true
        },
        {
            type = 'textarea',
            label = 'Reason',
            placeholder = 'Reason for CK request...',
            required = true
        }
    })
    
    -- Restore NUI after dialog closes (whether submitted or cancelled)
    Wait(100)
    SendNUIMessage({ action = 'show' })
    SetNuiFocus(true, true)
    
    if input and input[2] then
        TriggerServerEvent('faction:requestCK', targetIdentifier, targetName .. ' (ID: ' .. serverId .. ')', input[2])
    end
end

-- Helper functions
function FormatTime(seconds)
    if seconds < 60 then
        return seconds .. 's'
    elseif seconds < 3600 then
        return math.floor(seconds / 60) .. 'm ' .. (seconds % 60) .. 's'
    else
        local hours = math.floor(seconds / 3600)
        local minutes = math.floor((seconds % 3600) / 60)
        return hours .. 'h ' .. minutes .. 'm'
    end
end

function FormatDate(timestamp)
    -- Client-side date formatting (os is not available on client)
    if not timestamp then return 'Unknown' end
    
    -- Handle MySQL timestamp strings (YYYY-MM-DD HH:MM:SS)
    if type(timestamp) == 'string' then
        -- Extract date part from MySQL timestamp
        local datePart = timestamp:match('^(%d+%-%d+%-%d+)')
        if datePart then
            -- Format as MM/DD/YYYY for readability
            local year, month, day = datePart:match('(%d+)-(%d+)-(%d+)')
            if year and month and day then
                return string.format('%s/%s/%s', month, day, year)
            end
            return datePart
        end
    end
    
    -- Handle Unix timestamp (number) - MySQL usually sends strings, but handle numbers
    if type(timestamp) == 'number' then
        -- For Unix timestamps on client, we can't use os.date
        -- Just return a readable format
        return 'Recent'
    end
    
    -- Fallback: try to extract date from string
    local str = tostring(timestamp)
    local datePart = str:match('(%d+%-%d+%-%d+)')
    if datePart then
        local year, month, day = datePart:match('(%d+)-(%d+)-(%d+)')
        if year and month and day then
            return string.format('%s/%s/%s', month, day, year)
        end
        return datePart
    end
    
    return str:sub(1, 10) -- Take first 10 chars if it looks like a date
end
