-- Territory Client Logic
-- Uses ox_lib sphere zones for turf detection and stash interaction.
-- Turf territories are rendered as visible translucent spheres via DrawSphere each tick.

local allTerritories   = {}
local territoryBlips   = {}   -- map blip handles
local turfZones        = {}   -- ox_lib zone handles for turf spheres
local stashZones       = {}   -- ox_lib zone handles for stash interaction

-- Stash the player is currently standing next to (set by zone callbacks)
local nearbyStash      = nil  -- { territoryId, stashId }

-- Turf sphere draw data: list of { x, y, z, radius, r, g, b } — updated by RebuildTerritoryVisuals
local turfSphereDrawList = {}

-- ============================================================
-- HELPERS
-- ============================================================

local function ClearBlips()
    for _, blip in ipairs(territoryBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    territoryBlips = {}
end

local function ClearZones()
    for _, zone in ipairs(turfZones) do
        if zone and zone.remove then zone:remove() end
    end
    turfZones = {}

    for _, zone in ipairs(stashZones) do
        if zone and zone.remove then zone:remove() end
    end
    stashZones = {}

    -- Make sure any open stash textUI is cleared if zones are rebuilt
    if nearbyStash then
        nearbyStash = nil
        pcall(lib.hideTextUI)
    end

    turfSphereDrawList = {}
end

-- Returns the player's own faction ID (or nil if not in one)
local function GetMyFactionId()
    if currentFaction and currentFaction.faction then
        return currentFaction.faction.id
    end
    return nil
end

-- ============================================================
-- SPHERE COLOUR TABLE  (faction-agnostic; cycles by index)
-- Each turf gets a distinct colour so overlapping zones are distinguishable.
-- ============================================================
local SPHERE_COLOURS = {
    { r = 255, g =  60, b =  60 },  -- red
    { r =  60, g = 120, b = 255 },  -- blue
    { r = 255, g = 180, b =  30 },  -- gold
    { r =  60, g = 220, b =  60 },  -- green
    { r = 200, g =  60, b = 255 },  -- purple
    { r =  30, g = 220, b = 220 },  -- cyan
    { r = 255, g = 100, b = 200 },  -- pink
}

-- ============================================================
-- ZONE + BLIP + SPHERE BUILDER
-- ============================================================

local function RebuildTerritoryVisuals(territories)
    ClearBlips()
    ClearZones()

    allTerritories = territories or {}
    local myFactionId = GetMyFactionId()
    local turfCount   = 0

    for _, terr in ipairs(allTerritories) do
        local tx, ty, tz = terr.x, terr.y, terr.z
        local radius     = terr.radius or 50.0
        local fLabel     = terr.faction_label or 'Unknown'
        local tName      = terr.name or 'Territory'

        -- -------------------------------------------------------
        -- TURF — sphere zone + map blips + visible sphere
        -- -------------------------------------------------------
        if terr.type == 'turf' then
            turfCount = turfCount + 1
            local colour = SPHERE_COLOURS[((turfCount - 1) % #SPHERE_COLOURS) + 1]

            -- Translucent sphere draw entry (rendered every tick by the draw thread below)
            table.insert(turfSphereDrawList, {
                x      = tx,  y = ty,  z = tz,
                radius = radius,
                r = colour.r, g = colour.g, b = colour.b,
                alpha  = 35   -- 0–255; keep low for see-through effect
            })

            -- Radius area blip
            local areaBlip = AddBlipForRadius(tx, ty, 0.0, radius)
            SetBlipColour(areaBlip, 1)
            SetBlipAlpha(areaBlip, 60)
            table.insert(territoryBlips, areaBlip)

            -- Centre pin blip
            local pinBlip = AddBlipForCoord(tx, ty, tz)
            SetBlipSprite(pinBlip, 84)
            SetBlipColour(pinBlip, 1)
            SetBlipScale(pinBlip, 0.75)
            SetBlipAsShortRange(pinBlip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(fLabel .. ': ' .. tName)
            EndTextCommandSetBlipName(pinBlip)
            table.insert(territoryBlips, pinBlip)

            -- ox_lib sphere zone — handles enter/exit events without any tick polling
            local capturedTerr = terr
            local zone = lib.zones.sphere({
                coords  = vector3(tx, ty, tz),
                radius  = radius,
                debug   = false,
                onEnter = function(self)
                    lib.notify({
                        type        = 'info',
                        title       = fLabel .. ' Territory',
                        description = 'Entering ' .. tName,
                        duration    = 5000,
                    })
                    TriggerServerEvent('faction:playerEnteredTerritory', capturedTerr.id)
                end,
                onExit = function(self)
                    lib.notify({
                        type        = 'info',
                        description = 'Left faction territory.',
                        duration    = 3000,
                    })
                    TriggerServerEvent('faction:playerExitedTerritory', capturedTerr.id)
                end,
            })
            table.insert(turfZones, zone)

        -- -------------------------------------------------------
        -- STASH — only visible/accessible to the owning faction
        -- -------------------------------------------------------
        elseif terr.type == 'stash' then

            if myFactionId and terr.faction_id == myFactionId then

                -- Always-visible stash blip
                local stashBlip = AddBlipForCoord(tx, ty, tz)
                SetBlipSprite(stashBlip, 191)
                SetBlipColour(stashBlip, 5)
                SetBlipScale(stashBlip, 0.65)
                SetBlipAsShortRange(stashBlip, false)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString('Stash: ' .. tName)
                EndTextCommandSetBlipName(stashBlip)
                table.insert(territoryBlips, stashBlip)

                local terrId  = terr.id
                local stashId = terr.stash_id

                local sz = lib.zones.sphere({
                    coords  = vector3(tx, ty, tz),
                    radius  = 2.0,
                    debug   = false,
                    onEnter = function(self)
                        nearbyStash = { territoryId = terrId, stashId = stashId }
                        lib.showTextUI('[E] Open Faction Stash')
                    end,
                    onExit = function(self)
                        nearbyStash = nil
                        lib.hideTextUI()
                    end,
                })
                table.insert(stashZones, sz)
            end
        end
    end
end

-- ============================================================
-- SPHERE DRAW THREAD
-- DrawMarker type 28 = sphere (the actual 3D translucent sphere).
-- Scale values ARE the radius in GTA units — NOT diameter.
-- Called every frame so the sphere stays visible in the world.
-- ============================================================
CreateThread(function()
    while true do
        if #turfSphereDrawList > 0 then
            for _, s in ipairs(turfSphereDrawList) do
                DrawMarker(
                    28,                          -- type: sphere
                    s.x, s.y, s.z,               -- centre position
                    0.0, 0.0, 0.0,               -- direction
                    0.0, 0.0, 0.0,               -- rotation
                    s.radius, s.radius, s.radius, -- scale = radius, matches zone exactly
                    s.r, s.g, s.b, 55,           -- colour + alpha
                    false, false, 2, false, nil, nil, false
                )
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ============================================================
-- STASH KEY-PRESS THREAD
-- ============================================================
CreateThread(function()
    while true do
        if nearbyStash then
            Wait(0)
            if IsControlJustReleased(0, 38) then -- E key
                TriggerServerEvent('faction:requestOpenStash', nearbyStash.territoryId)
            end
        else
            Wait(500)
        end
    end
end)

-- ============================================================
-- NET EVENTS
-- ============================================================

RegisterNetEvent('faction:receiveAllTerritories', function(territories)
    RebuildTerritoryVisuals(territories)
end)

RegisterNetEvent('faction:refreshTerritoryVisuals', function()
    TriggerServerEvent('faction:getAllTerritories')
end)

RegisterNetEvent('faction:doOpenStash', function(stashId)
    if not stashId then return end
    pcall(function()
        exports['ox_inventory']:openInventory('stash', stashId)
    end)
end)

-- ============================================================
-- INITIAL DATA FETCH
-- ============================================================
CreateThread(function()
    while ESX.GetPlayerData().identifier == nil do
        Wait(100)
    end
    Wait(3000)
    TriggerServerEvent('faction:getAllTerritories')
end)

-- ============================================================
-- LEGACY COMPATIBILITY SHIMS
-- ============================================================
RegisterNetEvent('faction:enterTerritory', function(data) end)
RegisterNetEvent('faction:exitTerritory',  function()    end)
