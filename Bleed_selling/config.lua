LANGUAGE = "en"

REQUIRED_POLICE = 0

MAX_SELL = 7    -- MAX AMOUNT OF DRUG SOLD AT ONCE

REPUTATION_LOSS = 2 -- AMOUNT OF REPUTATION POINTS LOST
REPUTATION_LOSS_TIMER = 60*60000 -- DELAY BETWEEN 2 REPUTATION POINTS LOST

POL_ALERT_TIME = 30 * 1000  -- 30 seconds
POL_ALERT_SPRITE = 51      -- radar_crim_drugs
POL_ALERT_COLOR = 1         -- Red
POL_ALERT_WAVE = true       -- Enables the blip wave.

PERCENTAGES_ADV = { -- BE SURE TO NEVER GO OVER A TOTAL OF 100
    COPS = 20,
    GANG = 30,
    DENY = 0
}

PERCENTAGES_OWN = { -- BE SURE TO NEVER GO OVER A TOTAL OF 100
    COPS = 20,
    DENY = 20
}

local QBCore = exports['qb-core']:GetCoreObject()

-- =========================================
-- CONFIGURATION
-- =========================================

local Config = {}

Config.Zones = {
    {
        name = "GroveStreet",
        coords = vector3(105.0, -1940.0, 20.0),
        radius = 150.0,
        blip = true,
        label = "Grove Street"
    },
    {
        name = "SandyShores",
        coords = vector3(1385.0, 3605.0, 34.0),
        radius = 60.0,
        blip = true,
        label = "Sandy Shores"
    }
}

Config.Items = {
    { label = "Weed", item = "weed", price = 200 },
    { label = "Cocaine", item = "coke", price = 400 },
    { label = "Sandwich", item = "sandwich", price = 400 }
}

Config.RewardChance = {
    giveWeapon = { chance = 5, weapon = 'weapon_pistol' },
    giveAmmo = { chance = 15, item = 'pistol_ammo', amount = 15 }
}

Config.TakeoverAnnouncement = {
    duration = 7000,
    color = { r = 255, g = 0, b = 0 },
    scale = 0.8,
    position = { x = 0.5, y = 0.1 }
}

-- =========================================
-- CLIENT SIDE
-- =========================================

if not IsDuplicityVersion() then

local inZone = false
local currentZone = nil
local playerGang = nil
local gangOwnership = {}

CreateThread(function()
    for _, zone in ipairs(Config.Zones) do
        if zone.blip then
            local blip = AddBlipForRadius(zone.coords, zone.radius)
            SetBlipColour(blip, 1)
            SetBlipAlpha(blip, 128)

            local blipIcon = AddBlipForCoord(zone.coords)
            SetBlipSprite(blipIcon, 500)
            SetBlipDisplay(blipIcon, 4)
            SetBlipScale(blipIcon, 0.8)
            SetBlipColour(blipIcon, 1)
            SetBlipAsShortRange(blipIcon, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(zone.label or "Sell Zone")
            EndTextCommandSetBlipName(blipIcon)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        inZone = false
        for _, zone in pairs(Config.Zones) do
            local dist = #(pos - zone.coords)
            if dist <= zone.radius then
                inZone = true
                currentZone = zone.name
                break
            end
        end
    end
end)

RegisterNetEvent('zone_selling:updateOwnership', function(data)
    gangOwnership = data
end)

RegisterNetEvent('zone_selling:announceTakeover', function(message)
    CreateThread(function()
        local start = GetGameTimer()
        while GetGameTimer() - start < Config.TakeoverAnnouncement.duration do
            Wait(0)
            SetTextFont(4)
            SetTextScale(Config.TakeoverAnnouncement.scale, Config.TakeoverAnnouncement.scale)
            SetTextColour(Config.TakeoverAnnouncement.color.r, Config.TakeoverAnnouncement.color.g, Config.TakeoverAnnouncement.color.b, 255)
            SetTextCentre(true)
            BeginTextCommandDisplayText("STRING")
            AddTextComponentSubstringPlayerName(message)
            EndTextCommandDisplayText(Config.TakeoverAnnouncement.position.x, Config.TakeoverAnnouncement.position.y)
        end
    end)
end)

RegisterCommand("checkgang", function()
    QBCore.Functions.TriggerCallback("zone_selling:getGang", function(gang)
        QBCore.Functions.Notify("Your gang: " .. gang)
    end)
end)

RegisterNetEvent('zone_selling:sellItem', function(data)
    local item = data.item
    local basePrice = data.basePrice
    local bonus = 1

    if gangOwnership[currentZone] == playerGang then
        bonus = 2
    end

    local finalPrice = basePrice * bonus

    QBCore.Functions.Progressbar("selling_item", "Selling item...", 5000, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {}, {}, {}, function()
        TriggerServerEvent('zone_selling:processSale', item, finalPrice)
    end, function()
        QBCore.Functions.Notify("You stopped selling.", "error")
    end)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    QBCore.Functions.TriggerCallback("zone_selling:getGang", function(gang)
        playerGang = gang
    end)
end)

RegisterKeyMapping('+opensellmenu', 'Open Sell Menu in Zone', 'keyboard', 'G')

RegisterCommand('+opensellmenu', function()
    if not inZone then
        QBCore.Functions.Notify("You're not in a selling zone", "error")
        return
    end
    local menu = {}
    for _, item in ipairs(Config.Items) do
        table.insert(menu, {
            header = item.label .. " ($" .. item.price .. ")",
            params = {
                event = "zone_selling:sellItem",
                args = {
                    item = item.item,
                    basePrice = item.price
                }
            }
        })
    end
    exports['qb-menu']:openMenu(menu)
end, false)

RegisterCommand('-opensellmenu', function() end, false)

end -- end client

-- =========================================
-- SERVER SIDE
-- =========================================

if IsDuplicityVersion() then

local gangOwners = {}
local zoneOccupants = {}

RegisterNetEvent('zone_selling:processSale', function(item, price)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if Player.Functions.GetItemByName(item) then
        if Player.Functions.RemoveItem(item, 1) then
            Player.Functions.AddMoney('cash', price)
            TriggerClientEvent('QBCore:Notify', src, 'Sold 1x ' .. item .. ' for $' .. price, 'success')

            -- reward
            if math.random(1, 100) <= Config.RewardChance.giveWeapon.chance then
                Player.Functions.AddItem(Config.RewardChance.giveWeapon.weapon, 1)
                TriggerClientEvent('QBCore:Notify', src, "You found a weapon during the deal!", "success")
            end
            if math.random(1, 100) <= Config.RewardChance.giveAmmo.chance then
                Player.Functions.AddItem(Config.RewardChance.giveAmmo.item, Config.RewardChance.giveAmmo.amount)
                TriggerClientEvent('QBCore:Notify', src, "You found some ammo!", "success")
            end
        else
            TriggerClientEvent('QBCore:Notify', src, 'Item removal failed', 'error')
        end
    else
        TriggerClientEvent('QBCore:Notify', src, 'No ' .. item .. ' to sell', 'error')
    end
end)

QBCore.Functions.CreateCallback("zone_selling:getGang", function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb(nil) end
    cb(Player.PlayerData.gang.name)
end)

CreateThread(function()
    while true do
        Wait(5000)
        zoneOccupants = {}
        local players = QBCore.Functions.GetPlayers()

        for _, playerId in ipairs(players) do
            local Player = QBCore.Functions.GetPlayer(playerId)
            if Player then
                local gang = Player.PlayerData.gang.name
                local pos = GetEntityCoords(GetPlayerPed(playerId))

                for _, zone in ipairs(Config.Zones) do
                    if #(pos - zone.coords) < zone.radius then
                        zoneOccupants[zone.name] = zoneOccupants[zone.name] or {}
                        table.insert(zoneOccupants[zone.name], gang)
                    end
                end
            end
        end

        for _, zone in pairs(Config.Zones) do
            UpdateZoneOwner(zone.name)
        end
    end
end)

function UpdateZoneOwner(zoneName)
    local gangCount = {}

    for _, gang in pairs(zoneOccupants[zoneName] or {}) do
        gangCount[gang] = (gangCount[gang] or 0) + 1
    end

    local topGang, max = nil, 0
    for gang, count in pairs(gangCount) do
        if count > max then
            max = count
            topGang = gang
        end
    end

    local prevOwner = gangOwners[zoneName]
    gangOwners[zoneName] = topGang

    if topGang and topGang ~= prevOwner then
        local zoneLabel = zoneName:gsub("_", " ")
        local msg = ("~y~%s~s~ is taking control of ~r~%s~s~!"):format(string.upper(topGang), zoneLabel)
        TriggerClientEvent('zone_selling:announceTakeover', -1, msg)
    end

    TriggerClientEvent('zone_selling:updateOwnership', -1, gangOwners)
end

end -- end server
