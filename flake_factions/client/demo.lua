-- demo.lua — Production / showcase mode
-- Serves realistic fake data to every UI tab so potential buyers can
-- see the full feature set without a live database.
-- Only active when Config.ProductionMode = true.

local DEMO_FACTION = {
    id         = 1,
    name       = 'grove_street',
    label      = 'Grove Street Families',
    type       = 'gang',
    reputation = 847,
    active_wars = 1,
    max_wars   = 2
}

function GetDemoFaction()
    return DEMO_FACTION
end

local DEMO_MEMBERS = {
    { id = 1, player_name = 'Marcus Johnson',   rank = 'boss',        warnings = 0, last_warning_reason = '' },
    { id = 2, player_name = 'DeShawn Williams', rank = 'big_homie',   warnings = 1, last_warning_reason = 'Missed scheduled operation 28/04' },
    { id = 3, player_name = 'Tyrell Davis',     rank = 'big_homie',   warnings = 0, last_warning_reason = '' },
    { id = 4, player_name = 'Antoine Brooks',   rank = 'shot_caller', warnings = 0, last_warning_reason = '' },
    { id = 5, player_name = 'Darius Martin',    rank = 'shot_caller', warnings = 0, last_warning_reason = '' },
    { id = 6, player_name = 'Jamal Porter',     rank = 'member',      warnings = 0, last_warning_reason = '' },
    { id = 7, player_name = 'Kevin Barnes',     rank = 'member',      warnings = 2, last_warning_reason = 'Unauthorised weapon discharge' },
    { id = 8, player_name = 'Ray Tucker',       rank = 'runner',      warnings = 0, last_warning_reason = '' },
}

local DEMO_WEAPONS = {
    {
        weapon_name   = 'Pistol',
        serial_number = 'GSF-P-4521',
        logged_at     = '2026-04-22 14:30:00',
        possessed_by  = { { player_name = 'Marcus Johnson', rank = 'boss' } }
    },
    {
        weapon_name   = 'Micro SMG',
        serial_number = 'GSF-M-1183',
        logged_at     = '2026-04-22 14:32:00',
        possessed_by  = { { player_name = 'DeShawn Williams', rank = 'big_homie' } }
    },
    {
        weapon_name   = 'Assault Rifle',
        serial_number = 'GSF-A-8834',
        logged_at     = '2026-04-23 09:15:00',
        possessed_by  = { { player_name = 'Tyrell Davis', rank = 'big_homie' } }
    },
    {
        weapon_name   = 'Carbine Rifle',
        serial_number = 'GSF-C-9913',
        logged_at     = '2026-04-24 11:00:00',
        possessed_by  = { { player_name = 'Darius Martin', rank = 'shot_caller' } }
    },
    {
        weapon_name   = 'Pump Shotgun',
        serial_number = 'GSF-S-2267',
        logged_at     = '2026-04-25 16:45:00',
        possessed_by  = {}
    },
}

local DEMO_CONFLICTS = {
    conflicts = {
        {
            id             = 1,
            faction1_label = 'Grove Street Families',
            faction2_label = 'Ballas',
            type           = 'war',
            status         = 'active',
            reason         = 'Contested territory in Strawberry — escalated after unprovoked attack on 29/04.',
            started_at     = '2026-04-29 21:00:00'
        }
    },
    alliances = {}
}

local DEMO_TERRITORY = {
    territories = {
        {
            name            = 'Grove Street Turf',
            type            = 'turf',
            x               = -7.0,
            y               = -1617.0,
            z               = 29.3,
            radius          = 80,
            nearby_factions = {}
        },
        {
            name            = 'Davis Drug Corner',
            type            = 'corner',
            x               = 369.0,
            y               = -1681.0,
            z               = 29.3,
            radius          = 40,
            nearby_factions = { { faction = { label = 'Ballas' } } }
        },
        {
            name            = 'Strawberry Stash House',
            type            = 'stash',
            x               = -135.0,
            y               = -1708.0,
            z               = 29.3,
            radius          = 30,
            nearby_factions = {}
        },
    }
}

local DEMO_COOLDOWN_SECS = 5400 -- 90 min; ends_at computed fresh each call so countdown never loops

local DEMO_COOLDOWNS_CKHIST = {
    {
        target_name     = 'T-Bone Mendez',
        target_faction  = 'Ballas',
        submitted_by    = 'Antoine Brooks',
        status          = 'approved',
        reason          = 'Confirmed CK — hostile engagement on 27/04',
        created_at      = '2026-04-27 19:00:00'
    }
}

local DEMO_RULES = {
    rules = {
        {
            rule_title   = 'Respect & Hierarchy',
            rule_content = 'Always show respect to higher ranks. Direct orders from Boss or Big Homie are non-negotiable and must be followed immediately.'
        },
        {
            rule_title   = 'No Snitching',
            rule_content = 'Faction business stays internal. Any breach of confidentiality — to rival factions or authorities — is grounds for immediate removal and further consequences.'
        },
        {
            rule_title   = 'Weapon Accountability',
            rule_content = 'Every member is responsible for their registered weapon at all times. Loss, theft or misuse must be reported to a Big Homie within the hour.'
        },
        {
            rule_title   = 'Territory Defence',
            rule_content = 'When claimed territory is contested, all active on-duty members must respond when called. Failure to respond without prior notice will result in a formal warning.'
        },
        {
            rule_title   = 'Conflict Clearance',
            rule_content = 'No member below Shot Caller rank may initiate or escalate armed conflict with a rival faction without prior authorisation. Rogue engagements carry a two-warning penalty.'
        },
        {
            rule_title   = 'Recruitment Protocol',
            rule_content = 'Only Boss and Big Homie ranks may recruit new members. All recruits start at Runner and must complete a 7-day probationary period before promotion consideration.'
        },
    }
}

local DEMO_CK_FACTIONS = {
    factions = {
        { id = 2, name = 'ballas',           label = 'Ballas' },
        { id = 3, name = 'vagos',            label = 'Vagos' },
        { id = 4, name = 'marabunta',        label = 'Marabunta Grande' },
        { id = 5, name = 'lost_mc',          label = 'The Lost MC' },
        { id = 6, name = 'triads',           label = 'Wei Cheng Triads' },
    }
}

local DEMO_WARNINGS_ITEMS = {
    items = {
        'DeShawn Williams (Big Homie) — <span style="color:#f59e0b;">1 Warning</span>: Missed scheduled operation on 28/04',
        'Kevin Barnes (Member) — <span style="color:#ef4444;">2 Warnings</span>: Insubordination | Unauthorised weapon discharge on 25/04',
    }
}

-- Main entry point: called from requestTabData when ProductionMode = true
function SendDemoTabData(tab)
    if tab == 'overview' then
        SendNUIMessage({
            action  = 'updateTab',
            tab     = 'overview',
            content = {
                label       = DEMO_FACTION.label,
                type        = DEMO_FACTION.type,
                reputation  = DEMO_FACTION.reputation,
                active_wars = DEMO_FACTION.active_wars,
                max_wars    = DEMO_FACTION.max_wars
            }
        })
        -- Also push a fake active conflict to the overview conflicts section
        SendNUIMessage({
            action   = 'updateConflictsData',
            conflicts = DEMO_CONFLICTS.conflicts,
            alliances = {}
        })

    elseif tab == 'members' then
        SendNUIMessage({
            action  = 'updateTab',
            tab     = 'members',
            content = {
                members   = DEMO_MEMBERS,
                factionId = DEMO_FACTION.id,
                isAdmin   = false
            }
        })

    elseif tab == 'weapons' then
        SendNUIMessage({
            action  = 'updateTab',
            tab     = 'weapons',
            content = { weapons = DEMO_WEAPONS }
        })

    elseif tab == 'conflicts' then
        SendNUIMessage({
            action  = 'updateTab',
            tab     = 'conflicts',
            content = DEMO_CONFLICTS
        })

    elseif tab == 'cooldowns' then
        -- Compute ends_at fresh each time so the countdown always has time remaining
        local futureEndsAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + DEMO_COOLDOWN_SECS)
        SendNUIMessage({
            action  = 'updateTab',
            tab     = 'cooldowns',
            content = {
                cooldowns = {
                    {
                        id                = 1,
                        type              = 'war',
                        seconds_remaining = DEMO_COOLDOWN_SECS,
                        ends_at           = futureEndsAt,
                        reason            = 'Post-conflict cooldown — dispute with Ballas'
                    }
                },
                ckHistory = DEMO_COOLDOWNS_CKHIST
            }
        })

    elseif tab == 'warnings' then
        SendNUIMessage({
            action  = 'updateTab',
            tab     = 'warnings',
            content = DEMO_WARNINGS_ITEMS
        })

    elseif tab == 'territory' then
        SendNUIMessage({
            action  = 'updateTab',
            tab     = 'territory',
            content = DEMO_TERRITORY
        })

    elseif tab == 'reputation' then
        SendNUIMessage({
            action  = 'updateTab',
            tab     = 'reputation',
            content = {
                reputation          = DEMO_FACTION.reputation,
                rank                = 'Boss',
                activeWars          = DEMO_FACTION.active_wars .. ' / ' .. DEMO_FACTION.max_wars,
                gunDropEligible     = 'Yes',
                gunDropCooldownSecs = 0
            }
        })

    elseif tab == 'ck' then
        SendNUIMessage({
            action  = 'updateTab',
            tab     = 'ck',
            content = { step = 'select_faction', factions = DEMO_CK_FACTIONS.factions }
        })

    elseif tab == 'rules' then
        SendNUIMessage({
            action  = 'updateTab',
            tab     = 'rules',
            content = DEMO_RULES
        })

    elseif tab == 'report' then
        SendNUIMessage({
            action  = 'updateTab',
            tab     = 'report',
            content = { step = 'select_report_type' }
        })
    end
end
