-- Dispatch Options
Config.PoliceJobs = {
    'police',
    --'sheriff',
}

Config.SaleAlerts = {
    enable = true,
    alertsystem = 'cd_dispatch', -- 'cd_dispatch' | 'qs-dispatch'
    chance = 40
}


Config.Alerts = function(coords)

    if Config.SaleAlerts.alertsystem == 'cd_dispatch' then
        -- Check if cd_dispatch resource exists before calling export
        if GetResourceState('cd_dispatch') == 'started' then
            local success, data = pcall(function()
                return exports['cd_dispatch']:GetPlayerInfo()
            end)

            if success and data then
                TriggerServerEvent('cd_dispatch:AddNotification', {
                    job_table = Config.PoliceJobs,
                    coords = coords,
                    title = '10-17 - Suspicious Person',
                    message = 'A '..data.sex..' is selling drugs at '..data.street,
                    flash = 0,
                    unique_id = data.unique_id,
                    sound = 1,
                    blip = {
                        sprite  = 161,
                        scale   = 1.0,
                        colour  = 2,
                        flashes = false,
                        text    = '10-17 - Suspicious Person',
                        time    = 5,
                        radius  = 0,
                    }
                })
            end
        end
    elseif Config.SaleAlerts.alertsystem == 'qs-dispatch' then
        -- Check if qs-dispatch resource exists before calling
        if GetResourceState('qs-dispatch') == 'started' then
            TriggerServerEvent('qs-dispatch:server:CreateDispatchCall', {
                job = Config.PoliceJobs,
                callLocation = coords,
                callCode = { code = '10-17', snippet = 'Suspicious Activity' },
                message = "Suspicious Activity - Drug Sale.",
                flashes = true,
                blip = {
                    sprite = 488,
                    scale = 1.5,
                    colour = 1,
                    flashes = true,
                    text = 'Suspicious Activity - Drug Sale',
                    time = 20000,
                },
            })
        end
    end

end


--#Notifications
Config.Notify = function(message, type)
    lib.notify({
        title = 'Drug Selling',
        description = message,
        type = type,
        position = 'top',
        duration = 5000
    })
end

Config.Notifications = {
    alreadySelling = "You are already selling.",
    cannotSellFromVehicle = "You cannot sell from a vehicle!",
    nothingtosell = "You don't have anything to sell!",
    startedSelling = "You started selling!",
    buyerScared = "Customer got scared and ran away!",
    movedTooFar = "You moved too far away from the selling point!",
    notsellinganything = "You are not currently selling anything.",
    stoppedSelling = "You stopped selling.",
    buyerSpooked = "Customer got spooked and ran away!",
    solditemsuccess = "You sold %s x %s for $%s",
    attempt = "You\'re a fuckin goofy, stop doing that.",
    saleCanceled = "Customer got tired of waiting and left.",
    saleRejected = "Go get a job, go fill out an application.",
    notjob = "You cannot sell with this job, clock out.",
    nophone = "You need a phone to contact buyers!",
}



--TEXT UI
Config.showTextUI = function()
    lib.showTextUI('[E] - Sell to Customer', {
        iconAnimation = 'fade',
        icon = 'people-carry-box',
        iconColor = 'red',
    })
end

Config.hideTextUI = function()
    lib.hideTextUI()
end