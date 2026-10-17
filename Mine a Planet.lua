-- SCRIPT TEMPLATE

local SCRIPT = {
    id = "mine_a_planet",
    name = "Mine a Planet",
    version = "V1",
    updated = "21/07/2026",
    author = "Reverb",
    changelog = {
        {
            Version = "V1",
            Date = "21/07/2026",
            Title = "Initial Release",
            Added = {
                "Initial release with 15 features",
            },
        },
    },
}

----------------------------------------------------------------------------------------------------------------

local REVERB_UI_URL =
    "https://raw.githubusercontent.com/rbxreverb/ReverbUI/refs/heads/main/source.lua"

local environment = (getgenv and getgenv()) or _G
local Analytics = environment.ReverbAnalytics or rawget(_G, "ReverbAnalytics")

local function track(eventName, extra)
    if type(Analytics) ~= "table" or type(Analytics.track) ~= "function" then
        return false
    end

    local succeeded, result = pcall(Analytics.track, eventName, extra or {})
    return succeeded and result == true
end

local function featurePayload(featureId, extra)
    local payload = {
        script_id = SCRIPT.id,
        script_version = SCRIPT.version,
        feature_id = tostring(featureId),
    }
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            payload[key] = value
        end
    end
    return payload
end

local Runtime = {
    Script = SCRIPT,
    Environment = environment,
}
local instanceToken = {}
local cleanupCallbacks = {}
local destroyed = false
local featureStates = {}
local reportedFeatureErrors = {}

function Runtime.IsActive()
    return not destroyed
        and type(environment.ReverbLoadedScripts) == "table"
        and environment.ReverbLoadedScripts[SCRIPT.id] == instanceToken
end

function Runtime.AddCleanup(callback)
    if type(callback) == "function" then
        table.insert(cleanupCallbacks, callback)
    end
    return callback
end

function Runtime.Destroy()
    if destroyed then
        return
    end
    destroyed = true

    for index = #cleanupCallbacks, 1, -1 do
        local succeeded, cleanupError = pcall(cleanupCallbacks[index])
        if not succeeded then
            warn("[Reverb] Cleanup failed: " .. tostring(cleanupError))
        end
    end
    table.clear(cleanupCallbacks)

    if environment.ReverbLoadedScripts
        and environment.ReverbLoadedScripts[SCRIPT.id] == instanceToken
    then
        environment.ReverbLoadedScripts[SCRIPT.id] = nil
    end

    if environment.ReverbScriptInstances
        and environment.ReverbScriptInstances[SCRIPT.id] == Runtime
    then
        environment.ReverbScriptInstances[SCRIPT.id] = nil
    end

    if environment.ReverbCurrentScript
        and environment.ReverbCurrentScript.runtime == Runtime
    then
        environment.ReverbCurrentScript = nil
    end

    local library = Runtime.Library
    Runtime.Library = nil
    Runtime.Window = nil
    if type(library) == "table" and type(library.Destroy) == "function" then
        local succeeded, destroyError = pcall(function()
            library:Destroy()
        end)
        if not succeeded then
            warn("[Reverb] UI cleanup failed: " .. tostring(destroyError))
        end
    end
end

function Runtime.Track(eventName, extra)
    return track(eventName, extra)
end

function Runtime.TrackFeature(featureId, extra)
    return track("feature_used", featurePayload(featureId, extra))
end

function Runtime.ReportFeatureError(featureId, featureError)
    local errorText = tostring(featureError)
    local fingerprint = tostring(featureId) .. "\0" .. errorText
    if reportedFeatureErrors[fingerprint] then
        return false
    end
    reportedFeatureErrors[fingerprint] = true

    track("feature_error", featurePayload(featureId, {
        error = errorText,
    }))
    warn("[Reverb] " .. tostring(featureId) .. " failed: " .. errorText)
    return true
end

local function protectedCallback(featureId, callback, analyticsData)
    return function(value)
        Runtime.TrackFeature(featureId, analyticsData(value))
        if type(callback) ~= "function" then
            return
        end

        local succeeded, callbackError = pcall(callback, value)
        if not succeeded then
            Runtime.ReportFeatureError(featureId, callbackError)
        end
    end
end

function Runtime.CreateToggle(tab, settings)
    local featureId = settings.AnalyticsId or settings.Flag or settings.Name
    local callback = settings.Callback
    settings.AnalyticsId = nil
    featureStates[featureId] = featureStates[featureId] or {
        enabled = false,
        generation = 0,
    }
    settings.Callback = protectedCallback(featureId, function(value)
        local enabled = value == true
        local state = featureStates[featureId]
        state.enabled = enabled
        state.generation += 1

        if type(callback) == "function" then
            callback(enabled)
        end
    end, function(value)
        return { enabled = value == true }
    end)
    return tab:CreateToggle(settings)
end

function Runtime.CreateDropdown(tab, settings)
    local featureId = settings.AnalyticsId or settings.Flag or settings.Name
    local callback = settings.Callback
    settings.AnalyticsId = nil
    settings.Callback = protectedCallback(featureId, callback, function(value)
        return {
            metadata = {
                selection = type(value) == "table"
                    and table.concat(value, ",")
                    or tostring(value),
            },
        }
    end)
    return tab:CreateDropdown(settings)
end

function Runtime.CreateButton(tab, settings)
    local featureId = settings.AnalyticsId or settings.Name
    local callback = settings.Callback
    settings.AnalyticsId = nil
    settings.Callback = function()
        Runtime.TrackFeature(featureId, { action = "clicked" })
        if type(callback) ~= "function" then
            return
        end

        local succeeded, callbackError = pcall(callback)
        if not succeeded then
            Runtime.ReportFeatureError(featureId, callbackError)
        end
    end
    return tab:CreateButton(settings)
end

function Runtime.StartLoop(featureId, intervalSeconds, callback, isEnabled)
    local activeInterval = math.max(tonumber(intervalSeconds) or 0.1, 0.03)
    local idleInterval = math.max(activeInterval, 0.25)

    task.spawn(function()
        while Runtime.IsActive() do
            local state = featureStates[featureId]
            local enabled = state
                and state.enabled == true
                and (type(isEnabled) ~= "function" or isEnabled() == true)
            if not enabled then
                task.wait(idleInterval)
                continue
            end

            task.wait(activeInterval)
            if not Runtime.IsActive() then
                break
            end

            state = featureStates[featureId]
            enabled = state
                and state.enabled == true
                and (type(isEnabled) ~= "function" or isEnabled() == true)
            if not enabled then
                continue
            end

            local cycleGeneration = state.generation
            local function isCycleActive()
                local currentState = featureStates[featureId]
                return Runtime.IsActive()
                    and currentState == state
                    and currentState.enabled == true
                    and currentState.generation == cycleGeneration
                    and (type(isEnabled) ~= "function" or isEnabled() == true)
            end

            local succeeded, loopError = pcall(callback, isCycleActive)
            if not succeeded then
                Runtime.ReportFeatureError(featureId, loopError)
                task.wait(2)
            end
        end
    end)
end

----------------------------------------------------------------------------------------------------------------

-- Game-specific area. Create any tabs, sections, and features this game needs.
local function buildGame(RuntimeContext)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    local LocalPlayer = Players.LocalPlayer
    local CollectDockOre = ReplicatedStorage:WaitForChild("Net")
        :WaitForChild("RequestCollectDockOre")
    local UpgradeShopCashPurchase = ReplicatedStorage:WaitForChild("Net")
        :WaitForChild("RequestUpgradeShopCashPurchase")
    local AlienPetShopCashPurchase = ReplicatedStorage:WaitForChild("Net")
        :WaitForChild("RequestAlienPetShopCashPurchase")
    local GearShopCashPurchase = ReplicatedStorage:WaitForChild("Net")
        :WaitForChild("RequestGearShopCashPurchase")
    local UnlockDock = ReplicatedStorage:WaitForChild("Net")
        :WaitForChild("RequestUnlockDock")
    local RollDrones = ReplicatedStorage:WaitForChild("Net")
        :WaitForChild("RequestRollDrones")
    local RNGSync = ReplicatedStorage:WaitForChild("Net"):WaitForChild("RNGSync")
    local InventorySync = ReplicatedStorage:WaitForChild("Net")
        :WaitForChild("InventorySync")
    local UiPanel = ReplicatedStorage:WaitForChild("Net"):WaitForChild("UiPanel")
    local AssignHotbar = ReplicatedStorage:WaitForChild("Net")
        :WaitForChild("RequestAssignHotbar")
    local SelectHotbar = ReplicatedStorage:WaitForChild("Net")
        :WaitForChild("RequestSelectHotbar")
    local PlaceDrone = ReplicatedStorage:WaitForChild("Net")
        :WaitForChild("RequestPlaceDrone")
    local RemoveDrone = ReplicatedStorage:WaitForChild("Net")
        :WaitForChild("RequestRemoveDrone")
    local UpgradeDrone = ReplicatedStorage:WaitForChild("Net")
        :WaitForChild("RequestUpgradeDrone")
    local autoCollectOres = false
    local autoSell = false
    local sellWhenFull = false

    local function isProfileReady()
        return LocalPlayer:GetAttribute("FS_ProfileReady") == true
            and LocalPlayer:GetAttribute("FS_PlatformReady") == true
    end

    local function getPlayerBase()
        local farmStar = workspace:FindFirstChild("FarmStar")
        local platforms = farmStar and farmStar:FindFirstChild("Platforms")
        return platforms and platforms:FindFirstChild(tostring(LocalPlayer.UserId))
    end

    local function getDockIndices()
        local playerBase = getPlayerBase()
        local platform = playerBase and playerBase:FindFirstChild("Platform")
        if not platform then
            return {}
        end

        local floors = { { Number = 1, Container = platform } }
        for _, child in ipairs(platform:GetChildren()) do
            local floorNumber = tonumber(child.Name:match("^Platform(%d+)$"))
            if floorNumber then
                table.insert(floors, { Number = floorNumber, Container = child })
            end
        end
        table.sort(floors, function(left, right)
            return left.Number < right.Number
        end)

        local dockIndices = {}
        for _, floor in ipairs(floors) do
            local docks = floor.Container:FindFirstChild("Docks")
            if docks then
                local dockPlatforms = docks:GetChildren()
                table.sort(dockPlatforms, function(left, right)
                    local leftNumber = tonumber(left.Name:match("%d+$")) or math.huge
                    local rightNumber = tonumber(right.Name:match("%d+$")) or math.huge
                    return leftNumber < rightNumber
                end)

                local localDockIndex = 0
                for _, dockPlatform in ipairs(dockPlatforms) do
                    if dockPlatform.Name:match("^DockPlatform%d+$") then
                        local slots = dockPlatform:GetChildren()
                        table.sort(slots, function(left, right)
                            return (tonumber(left.Name) or math.huge)
                                < (tonumber(right.Name) or math.huge)
                        end)
                        for _, slot in ipairs(slots) do
                            if tonumber(slot.Name) and slot:IsA("BasePart") then
                                localDockIndex += 1
                                table.insert(
                                    dockIndices,
                                    ((floor.Number - 1) * 18) + localDockIndex
                                )
                            end
                        end
                    end
                end
            end
        end

        return dockIndices
    end

    local function getBackpackCapacity()
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local upgradePanel = playerGui and playerGui:FindFirstChild("FS_UpgradeShopPanel")
        local oreCapLabel = upgradePanel and upgradePanel:FindFirstChild("Stat_oreCap", true)
        if not oreCapLabel or not oreCapLabel:IsA("TextLabel") then
            return nil
        end

        local capacityText = oreCapLabel.Text:match("Ore cap%s+([%d,]+)")
        if not capacityText then
            return nil
        end

        return tonumber((capacityText:gsub(",", "")))
    end

    local function canUpgradeShopItem(itemId)
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local upgradePanel = playerGui and playerGui:FindFirstChild("FS_UpgradeShopPanel")
        local itemCard = upgradePanel
            and upgradePanel:FindFirstChild("ItemCard_" .. itemId, true)
        if not itemCard then
            return true
        end

        for _, object in ipairs(itemCard:GetDescendants()) do
            if (object:IsA("TextLabel") or object:IsA("TextButton"))
                and object.Text:upper():find("MAX", 1, true)
            then
                return false
            end
        end

        return true
    end

    local function findUpgradeButtons(boardName, upgradeName, includeAllFloors)
        local playerBase = getPlayerBase()
        if not playerBase then
            return {}
        end

        local matchingBoards = {}
        for _, object in ipairs(playerBase:GetDescendants()) do
            if object.Name == boardName
                and (includeAllFloors or object.Parent == playerBase)
            then
                table.insert(matchingBoards, object)
            end
        end

        local matchingButtons = {}
        for _, board in ipairs(matchingBoards) do
            local matchingLabels = {}
            for _, object in ipairs(board:GetDescendants()) do
                if (object:IsA("TextLabel") or object:IsA("TextButton"))
                    and object.Visible
                    and object.Text:lower():find(upgradeName:lower(), 1, true)
                then
                    table.insert(matchingLabels, object)
                end
            end

            local bestButton
            local bestScore = math.huge
            for _, object in ipairs(board:GetDescendants()) do
                if object:IsA("GuiButton")
                    and not object.Name:match("Stepper")
                    and object.Visible
                then
                    local buttonPosition = object.AbsolutePosition
                    local buttonSize = object.AbsoluteSize
                    local buttonCenter = buttonPosition + buttonSize / 2

                    for _, label in ipairs(matchingLabels) do
                        local labelCenter = label.AbsolutePosition + label.AbsoluteSize / 2
                        local insideButton = labelCenter.X >= buttonPosition.X
                            and labelCenter.X <= buttonPosition.X + buttonSize.X
                            and labelCenter.Y >= buttonPosition.Y
                            and labelCenter.Y <= buttonPosition.Y + buttonSize.Y
                        local score = (buttonCenter - labelCenter).Magnitude
                            + (insideButton and 0 or 100000)

                        if score < bestScore then
                            bestScore = score
                            bestButton = object
                        end
                    end
                end
            end

            if bestButton then
                table.insert(matchingButtons, bestButton)
            end
        end

        return matchingButtons
    end

    local function activateGuiButton(button)
        if type(firesignal) == "function" then
            firesignal(button.Activated)
            return
        end

        if type(getconnections) == "function" then
            local lastConnectionError
            for _, signal in ipairs({ button.Activated, button.MouseButton1Click }) do
                local connections = getconnections(signal)
                if #connections > 0 then
                    for _, connection in ipairs(connections) do
                        if type(connection.Fire) == "function" then
                            local fired, fireError = pcall(connection.Fire, connection)
                            if fired then
                                return
                            end
                            lastConnectionError = fireError
                        end
                    end
                end
            end
            if lastConnectionError then
                error(lastConnectionError, 0)
            end
        end

        error("This executor does not support getconnections or firesignal")
    end

    local FarmingTab = RuntimeContext.Window:CreateTab("Farming", "tractor")
    local UpgradesTab = RuntimeContext.Window:CreateTab("Upgrades", "arrow-up")
    local DronesTab = RuntimeContext.Window:CreateTab("Drones", "bot")
    local collectToggle
    local sellToggle
    local autoFarmToggle
    local syncingAutoFarm = false
    local sellInterval = 15
    local lastSellAt = 0

    local function syncAutoFarmToggle()
        if syncingAutoFarm or not autoFarmToggle then
            return
        end

        syncingAutoFarm = true
        autoFarmToggle:Set(autoCollectOres and autoSell)
        syncingAutoFarm = false
    end

    FarmingTab:CreateSection("Recommended")
    autoFarmToggle = RuntimeContext.CreateToggle(FarmingTab, {
        Name = "Auto Farm (Collect + Sell)",
        CurrentValue = false,
        Ext = true,
        AnalyticsId = "auto_farm",
        Callback = function(enabled)
            if syncingAutoFarm then
                return
            end

            syncingAutoFarm = true
            if collectToggle then
                collectToggle:Set(enabled)
            end
            if sellToggle then
                sellToggle:Set(enabled)
            end
            syncingAutoFarm = false
        end,
    })

    FarmingTab:CreateSection("Ore Collection")
    collectToggle = RuntimeContext.CreateToggle(FarmingTab, {
        Name = "Auto Collect Dock Ores",
        CurrentValue = false,
        Ext = true,
        AnalyticsId = "auto_collect_ores",
        Callback = function(enabled)
            autoCollectOres = enabled
            syncAutoFarmToggle()
        end,
    })

    RuntimeContext.StartLoop("auto_collect_ores", 0.75, function(isCycleActive)
        local dockIndices = getDockIndices()
        for _, dockIndex in ipairs(dockIndices) do
            if not isCycleActive() then
                break
            end
            CollectDockOre:FireServer({
                dockIndex = dockIndex,
            })
        end
    end, function()
        return autoCollectOres
            and isProfileReady()
    end)

    FarmingTab:CreateSection("Selling")
    sellToggle = RuntimeContext.CreateToggle(FarmingTab, {
        Name = "Auto Sell Cargo (Teleports)",
        CurrentValue = false,
        Ext = true,
        AnalyticsId = "auto_sell",
        Callback = function(enabled)
            autoSell = enabled
            if enabled then
                lastSellAt = 0
            end
            syncAutoFarmToggle()
        end,
    })

    RuntimeContext.CreateDropdown(FarmingTab, {
        Name = "Sell Trigger",
        Options = {
            "When Backpack Is Full",
            "Every 5 seconds",
            "Every 15 seconds",
            "Every 30 seconds",
            "Every 60 seconds",
        },
        CurrentOption = { "Every 15 seconds" },
        MultipleOptions = false,
        Flag = SCRIPT.id .. "_sell_trigger",
        AnalyticsId = "sell_trigger",
        Callback = function(selection)
            local selected = type(selection) == "table" and selection[1] or selection
            sellWhenFull = selected == "When Backpack Is Full"
            sellInterval = ({
                ["Every 5 seconds"] = 5,
                ["Every 15 seconds"] = 15,
                ["Every 30 seconds"] = 30,
                ["Every 60 seconds"] = 60,
            })[selected] or 15
        end,
    })

    RuntimeContext.StartLoop("auto_sell", 1, function(isCycleActive)
        local now = os.clock()
        local backpackOre = tonumber(LocalPlayer:GetAttribute("FS_BackpackOre")) or 0
        if backpackOre <= 0 then
            return
        end

        if sellWhenFull then
            local backpackCapacity = getBackpackCapacity()
            if backpackCapacity and backpackOre < backpackCapacity then
                return
            end
            if not backpackCapacity
                and lastSellAt > 0
                and now - lastSellAt < sellInterval
            then
                return
            end
        elseif lastSellAt > 0 and now - lastSellAt < sellInterval then
            return
        end

        local playerBase = getPlayerBase()
        local sellPrompt = playerBase and playerBase:FindFirstChild("FS_SellPrompt", true)
        local character = LocalPlayer.Character
        local promptAnchor = sellPrompt and sellPrompt.Parent
        if not sellPrompt
            or not sellPrompt:IsA("ProximityPrompt")
            or not character
            or not character:FindFirstChild("HumanoidRootPart")
            or not promptAnchor
            or not promptAnchor:IsA("BasePart")
        then
            return
        end

        lastSellAt = now
        local previousPivot = character:GetPivot()
        local sellPivot = promptAnchor.CFrame * CFrame.new(0, 3, 0)
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        character:PivotTo(sellPivot)
        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero

        local arrivalDeadline = os.clock() + 0.75
        while isCycleActive() and os.clock() < arrivalDeadline do
            task.wait(0.05)
        end

        local activated = true
        local activationError
        for attempt = 1, 2 do
            if not isCycleActive()
                or (tonumber(LocalPlayer:GetAttribute("FS_BackpackOre")) or 0) <= 0
            then
                break
            end

            character:PivotTo(sellPivot)
            rootPart.AssemblyLinearVelocity = Vector3.zero
            rootPart.AssemblyAngularVelocity = Vector3.zero
            activated, activationError = pcall(function()
                fireproximityprompt(sellPrompt)
            end)

            if not activated then
                break
            end

            local processingDeadline = os.clock() + 1.5
            while isCycleActive()
                and os.clock() < processingDeadline
                and (tonumber(LocalPlayer:GetAttribute("FS_BackpackOre")) or 0) > 0
            do
                task.wait(0.05)
            end
        end

        if character.Parent then
            character:PivotTo(previousPivot)
        end

        if not activated then
            error(activationError)
        end
    end, function()
        return autoSell
            and isProfileReady()
    end)

    local function makeSelectionSet(selection)
        local selected = {}
        if type(selection) == "table" then
            for _, name in ipairs(selection) do
                selected[name] = true
            end
        elseif selection then
            selected[tostring(selection)] = true
        end
        return selected
    end

    local baseUpgradeOptions = {
        "Dock Platforms",
        "Dock Storage",
        "Cargo",
        "Mining Speed",
        "Drone Luck",
        "Drone Rolls",
        "Expand Base",
        "Planet Upgrade",
    }
    local baseUpgradeSettings = {
        ["Dock Platforms"] = { Board = "Board1", AllFloors = true },
        ["Dock Storage"] = { Board = "Board1", AllFloors = true },
        ["Cargo"] = { Board = "Board2", AllFloors = true },
        ["Mining Speed"] = { Board = "Board2", AllFloors = true },
        ["Drone Luck"] = { Board = "Board3", AllFloors = false },
        ["Drone Rolls"] = { Board = "Board3", AllFloors = false },
        ["Expand Base"] = { Board = "Board4", AllFloors = false },
        ["Planet Upgrade"] = { Board = "Board7", AllFloors = false },
    }
    local selectedBaseUpgrades = {}
    local autoUpgradeBase = false

    UpgradesTab:CreateSection("Base Upgrades")
    RuntimeContext.CreateDropdown(UpgradesTab, {
        Name = "Select Base Upgrades",
        Options = baseUpgradeOptions,
        CurrentOption = {},
        MultipleOptions = true,
        Flag = SCRIPT.id .. "_selected_base_upgrades",
        AnalyticsId = "selected_base_upgrades",
        Callback = function(selection)
            selectedBaseUpgrades = makeSelectionSet(selection)
        end,
    })
    RuntimeContext.CreateToggle(UpgradesTab, {
        Name = "Auto Upgrade Selected Base Upgrades",
        CurrentValue = false,
        Ext = true,
        AnalyticsId = "auto_upgrade_selected_base",
        Callback = function(enabled)
            autoUpgradeBase = enabled
        end,
    })

    RuntimeContext.StartLoop("auto_upgrade_selected_base", 1, function(isCycleActive)
        for _, upgradeName in ipairs(baseUpgradeOptions) do
            if not isCycleActive() then
                break
            end
            if selectedBaseUpgrades[upgradeName] then
                local settings = baseUpgradeSettings[upgradeName]
                local buttons = findUpgradeButtons(
                    settings.Board,
                    upgradeName,
                    settings.AllFloors
                )
                for _, button in ipairs(buttons) do
                    if not isCycleActive() then
                        break
                    end
                    activateGuiButton(button)
                end
            end
        end
    end, function()
        return autoUpgradeBase and isProfileReady()
    end)

    local shopUpgradeOptions = { "Jetpack", "Gun", "Drone Kit" }
    local shopUpgradeItemIds = {
        Jetpack = "jetpack",
        Gun = "gun",
        ["Drone Kit"] = "dronekit",
    }
    local selectedShopUpgrades = {}
    local autoUpgradeShop = false

    UpgradesTab:CreateSection("Shop Upgrades")
    RuntimeContext.CreateDropdown(UpgradesTab, {
        Name = "Select Shop Upgrades",
        Options = shopUpgradeOptions,
        CurrentOption = {},
        MultipleOptions = true,
        Flag = SCRIPT.id .. "_selected_shop_upgrades",
        AnalyticsId = "selected_shop_upgrades",
        Callback = function(selection)
            selectedShopUpgrades = makeSelectionSet(selection)
        end,
    })
    RuntimeContext.CreateToggle(UpgradesTab, {
        Name = "Auto Upgrade Selected Shop Upgrades",
        CurrentValue = false,
        Ext = true,
        AnalyticsId = "auto_upgrade_selected_shop",
        Callback = function(enabled)
            autoUpgradeShop = enabled
        end,
    })

    RuntimeContext.StartLoop("auto_upgrade_selected_shop", 2.5, function(isCycleActive)
        for _, upgradeName in ipairs(shopUpgradeOptions) do
            local itemId = shopUpgradeItemIds[upgradeName]
            if isCycleActive()
                and selectedShopUpgrades[upgradeName]
                and canUpgradeShopItem(itemId)
            then
                UpgradeShopCashPurchase:FireServer({ itemId = itemId })
            end
        end
    end, function()
        return autoUpgradeShop and isProfileReady()
    end)

    local alienPurchaseOptions = {
        "Alien Ball 1", "Alien Ball 2", "Alien Ball 3", "Alien Ball 4",
        "Alien Treat 1", "Alien Treat 2", "Alien Treat 3", "Alien Treat 4",
    }
    local alienPurchaseIds = {
        ["Alien Ball 1"] = "AlienBall1", ["Alien Ball 2"] = "AlienBall2",
        ["Alien Ball 3"] = "AlienBall3", ["Alien Ball 4"] = "AlienBall4",
        ["Alien Treat 1"] = "AlienTreat1", ["Alien Treat 2"] = "AlienTreat2",
        ["Alien Treat 3"] = "AlienTreat3", ["Alien Treat 4"] = "AlienTreat4",
    }
    local selectedAlienPurchases = {}
    local autoBuyAlienItems = false

    UpgradesTab:CreateSection("Alien Pet Shop")
    RuntimeContext.CreateDropdown(UpgradesTab, {
        Name = "Select Alien Items",
        Options = alienPurchaseOptions,
        CurrentOption = {},
        MultipleOptions = true,
        Flag = SCRIPT.id .. "_selected_alien_items",
        AnalyticsId = "selected_alien_items",
        Callback = function(selection)
            selectedAlienPurchases = makeSelectionSet(selection)
        end,
    })
    RuntimeContext.CreateToggle(UpgradesTab, {
        Name = "Auto Buy Selected Alien Items",
        CurrentValue = false,
        Ext = true,
        AnalyticsId = "auto_buy_selected_alien_items",
        Callback = function(enabled)
            autoBuyAlienItems = enabled
        end,
    })

    RuntimeContext.StartLoop("auto_buy_selected_alien_items", 2.5, function(isCycleActive)
        for _, itemName in ipairs(alienPurchaseOptions) do
            if isCycleActive() and selectedAlienPurchases[itemName] then
                AlienPetShopCashPurchase:FireServer({
                    consumableId = alienPurchaseIds[itemName],
                })
            end
        end
    end, function()
        return autoBuyAlienItems and isProfileReady()
    end)

    local gearPurchaseOptions = {
        "Clean CPU", "Blizzard CPU", "Ion CPU", "Solar Flare CPU",
        "Radioactive CPU", "UFO CPU", "Jellyfish CPU",
        "Battery 1", "Battery 2", "Battery 3", "Battery 4",
    }
    local gearPurchaseIds = {
        ["Clean CPU"] = "CpuClean", ["Blizzard CPU"] = "CpuBlizzard",
        ["Ion CPU"] = "CpuIon", ["Solar Flare CPU"] = "CpuSolarFlare",
        ["Radioactive CPU"] = "CpuRadioActive", ["UFO CPU"] = "CpuUFO",
        ["Jellyfish CPU"] = "CpuJellyFish",
        ["Battery 1"] = "Battery1", ["Battery 2"] = "Battery2",
        ["Battery 3"] = "Battery3", ["Battery 4"] = "Battery4",
    }
    local selectedGearPurchases = {}
    local autoBuyGearItems = false

    UpgradesTab:CreateSection("Gear Shop")
    RuntimeContext.CreateDropdown(UpgradesTab, {
        Name = "Select Gear Items",
        Options = gearPurchaseOptions,
        CurrentOption = {},
        MultipleOptions = true,
        Flag = SCRIPT.id .. "_selected_gear_items",
        AnalyticsId = "selected_gear_items",
        Callback = function(selection)
            selectedGearPurchases = makeSelectionSet(selection)
        end,
    })
    RuntimeContext.CreateToggle(UpgradesTab, {
        Name = "Auto Buy Selected Gear Items",
        CurrentValue = false,
        Ext = true,
        AnalyticsId = "auto_buy_selected_gear_items",
        Callback = function(enabled)
            autoBuyGearItems = enabled
        end,
    })

    RuntimeContext.StartLoop("auto_buy_selected_gear_items", 2.5, function(isCycleActive)
        for _, itemName in ipairs(gearPurchaseOptions) do
            if isCycleActive() and selectedGearPurchases[itemName] then
                GearShopCashPurchase:FireServer({
                    consumableId = gearPurchaseIds[itemName],
                })
            end
        end
    end, function()
        return autoBuyGearItems and isProfileReady()
    end)

    local droneNames = {
        "ChooChooChip", "SplashySam", "EclipseEdgar", "VoidObsidian",
        "VoidOrbit", "VoidVanta", "TranscendentAstral", "TranscendentCosmo",
        "TranscendentEternal", "TranscendentRadiant", "VoidBeacon",
        "DoubleDigDoug", "LordRingo", "MobyDrill", "PharaohFunk",
        "SirSparklesalot", "Tankenstein", "TheDrillfather", "BulwarkBarry",
        "ExoticComet", "ExoticNebula", "ExoticOrbit", "ExoticZephyr",
        "AquanautAl", "BlazingBenny", "CaptainNemo", "KingMidas",
        "RainbowReginald", "MagmaMilo", "SecretCipher", "SecretCovert",
        "SecretMidnight", "SecretShade", "BunkerBruno", "DiggySmalls",
        "GildedGordon", "Honkenstein", "RustyRumbles", "AquaAugustus",
        "CaptainCosmo", "Drilliam", "RocketRoo", "TurboToby",
        "BumbleBuggy", "ChooTwins", "Drillon", "FrostyPhil", "SmileyRiley",
        "ChuckleChunk", "Cubert", "PixiePete", "SnippyMcSnap", "CyanCy",
        "Drillbert", "SirBuzzly",
    }
    local droneRarities = {
        "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine",
        "Prismatic", "Transcendent", "Secret", "Exotic", "Void",
    }
    local selectedDroneNames = {}
    local selectedDroneRarities = {}
    local currentRngSlots = {}
    local currentRollEpoch = 0
    local attemptedRngSlots = {}
    local autoUnlockDocks = false
    local autoRollDrones = false
    local autoBuyDroneMatches = false
    local stopRollAfterMatch = true
    local autoRollToggle
    local inventoryItems = {}
    local autoFillDocks = false
    local autoReplaceDocks = false
    local preserveFavoriteDrones = true
    local autoUpgradeDrones = false
    local droneUpgradeMode = "Best Docked"
    local selectedUpgradeDroneTypes = {}
    local droneManagementBusy = false
    local droneManagementBusySince = 0
    local lastInventoryWarningAt = 0
    local lastInventoryRequestAt = 0
    featureStates.drone_dock_management = featureStates.drone_dock_management or {
        enabled = false,
        generation = 0,
    }

    local function syncDroneManagementLoopState()
        local state = featureStates.drone_dock_management
        state.enabled = autoFillDocks or autoReplaceDocks
        state.generation += 1
    end

    local rarityRanks = {
        Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5,
        Mythic = 6, Divine = 7, Prismatic = 8, Transcendent = 9,
        Secret = 10, Exotic = 11, Void = 12,
    }
    local fallbackDroneRarities = {
        EclipseEdgar = "Void", VoidObsidian = "Void", VoidOrbit = "Void",
        VoidVanta = "Void", VoidBeacon = "Void",
        TranscendentAstral = "Transcendent", TranscendentCosmo = "Transcendent",
        TranscendentEternal = "Transcendent", TranscendentRadiant = "Transcendent",
        DoubleDigDoug = "Prismatic", LordRingo = "Prismatic",
        MobyDrill = "Prismatic", PharaohFunk = "Prismatic",
        SirSparklesalot = "Prismatic", Tankenstein = "Prismatic",
        TheDrillfather = "Prismatic",
        BulwarkBarry = "Exotic", ExoticComet = "Exotic",
        ExoticNebula = "Exotic", ExoticOrbit = "Exotic",
        ExoticZephyr = "Exotic",
        AquanautAl = "Divine", BlazingBenny = "Divine",
        CaptainNemo = "Divine", KingMidas = "Divine",
        RainbowReginald = "Divine",
        MagmaMilo = "Secret", SecretCipher = "Secret",
        SecretCovert = "Secret", SecretMidnight = "Secret",
        SecretShade = "Secret",
        BunkerBruno = "Mythic", DiggySmalls = "Mythic",
        GildedGordon = "Mythic", Honkenstein = "Mythic",
        RustyRumbles = "Mythic",
        AquaAugustus = "Legendary", CaptainCosmo = "Legendary",
        Drilliam = "Legendary", RocketRoo = "Legendary",
        TurboToby = "Legendary",
    }

    local function updateInventory(payload)
        if type(payload) ~= "table" then
            return
        end
        local items = payload.items or payload.inventory or payload
        if type(items) ~= "table" then
            return
        end

        local nextItems = {}
        for _, item in pairs(items) do
            if type(item) == "table" and item.uid then
                nextItems[tostring(item.uid)] = item
            end
        end
        if next(nextItems) then
            inventoryItems = nextItems
        end
    end

    local inventorySyncConnection = InventorySync.OnClientEvent:Connect(updateInventory)
    RuntimeContext.AddCleanup(function()
        inventorySyncConnection:Disconnect()
    end)

    local function tryHydrateInventoryFromClient()
        if next(inventoryItems) or type(getconnections) ~= "function" then
            return next(inventoryItems) ~= nil
        end

        local debugLibrary = debug
        local getUpvalues = debugLibrary and debugLibrary.getupvalues
        local getUpvalue = debugLibrary and debugLibrary.getupvalue
        if type(getUpvalues) ~= "function" and type(getUpvalue) ~= "function" then
            return false
        end

        local function readUpvalues(callback)
            if type(getUpvalues) == "function" then
                return getUpvalues(callback)
            end
            local values = {}
            for index = 1, 100 do
                local name, value = getUpvalue(callback, index)
                if name == nil then
                    break
                end
                values[name] = value
            end
            return values
        end

        local visited = {}
        local function findItems(value, depth)
            if type(value) ~= "table" or visited[value] or depth > 4 then
                return nil
            end
            visited[value] = true

            local droneCount = 0
            for _, item in pairs(value) do
                if type(item) == "table" and item.kind == "drone" and item.uid then
                    droneCount += 1
                end
            end
            if droneCount > 0 then
                return value
            end

            for _, child in pairs(value) do
                local found = findItems(child, depth + 1)
                if found then
                    return found
                end
            end
            return nil
        end

        for _, connection in ipairs(getconnections(InventorySync.OnClientEvent)) do
            local callback = connection.Function
            if type(callback) == "function" then
                local succeeded, upvalues = pcall(readUpvalues, callback)
                if succeeded and type(upvalues) == "table" then
                    local found = findItems(upvalues, 0)
                    if found then
                        updateInventory({ items = found })
                        return next(inventoryItems) ~= nil
                    end
                end
            end
        end
        return false
    end

    local function requestInventorySync()
        tryHydrateInventoryFromClient()
        if not next(inventoryItems) and os.clock() - lastInventoryRequestAt >= 5 then
            lastInventoryRequestAt = os.clock()
            UiPanel:FireServer({ panel_id = "bag", action = "open" })
        end
    end

    local function getDroneRarity(droneType)
        local models = ReplicatedStorage:FindFirstChild("FS_DroneModels")
        local model = models and models:FindFirstChild(tostring(droneType))
        local rarity = model and model:GetAttribute("FS_Tier") or nil
        if type(rarity) == "string" then
            return rarity
        end

        local name = tostring(droneType or "")
        if fallbackDroneRarities[name] then
            return fallbackDroneRarities[name]
        end
        for _, prefix in ipairs({
            "Transcendent", "Secret", "Exotic", "Void",
        }) do
            if name:sub(1, #prefix) == prefix then
                return prefix
            end
        end
        return nil
    end

    local function getDroneScore(drone)
        local level = type(drone.level) == "table" and drone.level or {}
        local mutations = type(drone.mutationIds) == "table"
            and #drone.mutationIds or 0
        return (rarityRanks[getDroneRarity(drone.droneType)] or 0) * 1000000000
            + mutations * 10000000
            + (tonumber(level.value) or 0) * 10000
            + (tonumber(level.power) or 0) * 100
            + (tonumber(level.speed) or 0) * 10
            + (tonumber(level.cargo) or 0)
    end

    local function getUnlockedDockIndices()
        local playerBase = getPlayerBase()
        local indices = {}
        local seen = {}
        if not playerBase then
            return indices
        end
        for _, object in ipairs(playerBase:GetDescendants()) do
            local index = object:IsA("BasePart")
                and object.Name == "Dock"
                and tonumber(object:GetAttribute("FS_DockIndex"))
            if index and not seen[index] and object.Parent
                and object.Parent:GetAttribute("FS_DockUnlocked") == true
            then
                seen[index] = true
                table.insert(indices, index)
            end
        end
        table.sort(indices)
        return indices
    end

    local function findDockPart(dockIndex)
        local playerBase = getPlayerBase()
        if not playerBase then
            return nil
        end
        for _, object in ipairs(playerBase:GetDescendants()) do
            if object:IsA("BasePart")
                and tonumber(object:GetAttribute("FS_DockIndex")) == dockIndex
            then
                return object
            end
        end
        return nil
    end

    local function getInventoryState()
        local docked, available, occupiedHotbar = {}, {}, {}
        for _, drone in pairs(inventoryItems) do
            local location = tostring(drone.location or "")
            local dockIndex = tonumber(location:match("^dock:(%d+)$"))
            local hotbarSlot = tonumber(location:match("^hotbar:(%d+)$"))
            if hotbarSlot then
                occupiedHotbar[hotbarSlot] = drone
            end
            if drone.kind == "drone" and dockIndex then
                docked[dockIndex] = drone
            elseif drone.kind == "drone" and (location == "bag" or hotbarSlot) then
                table.insert(available, drone)
            end
        end
        table.sort(available, function(left, right)
            return getDroneScore(left) > getDroneScore(right)
        end)
        return docked, available, occupiedHotbar
    end

    local function prepareAndPlaceDrone(drone, dockIndex, occupiedHotbar)
        local location = tostring(drone.location or "")
        local slot = tonumber(location:match("^hotbar:(%d+)$"))
        if not slot then
            local hotbarCapacity = 9
            for candidate = 1, hotbarCapacity do
                if not occupiedHotbar[candidate] then
                    slot = candidate
                    break
                end
            end
            slot = slot or 1
            AssignHotbar:FireServer({
                expectedLocation = "bag",
                uid = drone.uid,
                replaceOccupied = occupiedHotbar[slot] ~= nil,
                slot = slot,
            })
            task.wait(0.35)
        end
        SelectHotbar:FireServer({ slot = slot, uid = drone.uid })
        task.wait(0.3)

        local character = LocalPlayer.Character
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")
        local dockPart = findDockPart(dockIndex)
        local previousPivot = character and character:GetPivot()
        if character and rootPart and dockPart then
            character:PivotTo(dockPart.CFrame * CFrame.new(0, 3, 0))
            rootPart.AssemblyLinearVelocity = Vector3.zero
            rootPart.AssemblyAngularVelocity = Vector3.zero
            task.wait(0.6)
            character:PivotTo(dockPart.CFrame * CFrame.new(0, 3, 0))
        end

        PlaceDrone:FireServer({ dockIndex = dockIndex })
        task.wait(0.65)
        if character and character.Parent and previousPivot then
            character:PivotTo(previousPivot)
        end
    end

    local function recallDroneFromDock(drone, dockIndex, isCycleActive)
        local character = LocalPlayer.Character
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")
        local dockPart = findDockPart(dockIndex)
        if not character or not rootPart or not dockPart then
            return false
        end

        local previousPivot = character:GetPivot()
        local targetPivot = dockPart.CFrame * CFrame.new(0, 3, 0)
        character:PivotTo(targetPivot)
        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero
        task.wait(0.6)
        if not isCycleActive() then
            if character.Parent then
                character:PivotTo(previousPivot)
            end
            return false
        end

        character:PivotTo(targetPivot)
        RemoveDrone:FireServer({ droneId = drone.uid })

        local deadline = os.clock() + 2
        local cleared = false
        while isCycleActive() and os.clock() < deadline do
            local currentDrone = inventoryItems[tostring(drone.uid)]
            local location = currentDrone and tostring(currentDrone.location or "") or ""
            if location ~= "dock:" .. tostring(dockIndex)
                or dockPart:GetAttribute("FS_DockDronePresent") == false
            then
                cleared = true
                break
            end
            task.wait(0.1)
        end

        if character.Parent then
            character:PivotTo(previousPivot)
        end
        return cleared
    end

    local rngSyncConnection = RNGSync.OnClientEvent:Connect(function(payload)
        if type(payload) ~= "table" or type(payload.slots) ~= "table" then
            return
        end

        local nextEpoch = tonumber(payload.rollEpoch) or currentRollEpoch
        if nextEpoch ~= currentRollEpoch then
            currentRollEpoch = nextEpoch
            table.clear(attemptedRngSlots)
        end
        currentRngSlots = payload.slots
    end)
    RuntimeContext.AddCleanup(function()
        rngSyncConnection:Disconnect()
    end)

    local promptActionBusy = false
    local promptActionBusySince = 0
    local function runNearPrompt(prompt, isCycleActive, callback)
        if promptActionBusy then
            if os.clock() - promptActionBusySince < 5 then
                return false
            end
            promptActionBusy = false
        end

        local character = LocalPlayer.Character
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")
        local promptParent = prompt and prompt.Parent
        local anchor = promptParent
        if promptParent and promptParent:IsA("Attachment") then
            anchor = promptParent.Parent
        elseif promptParent and promptParent:IsA("Model") then
            anchor = promptParent:FindFirstChildWhichIsA("BasePart", true)
        end
        if not prompt
            or not prompt:IsA("ProximityPrompt")
            or not character
            or not rootPart
            or not anchor
            or not anchor:IsA("BasePart")
        then
            return false
        end

        promptActionBusy = true
        promptActionBusySince = os.clock()
        local previousPivot = character:GetPivot()
        local targetPivot = anchor.CFrame * CFrame.new(0, 3, 0)
        character:PivotTo(targetPivot)
        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero

        local arrivalDeadline = os.clock() + 0.6
        while isCycleActive() and os.clock() < arrivalDeadline do
            task.wait(0.05)
        end

        local succeeded = false
        local actionError
        if isCycleActive() then
            character:PivotTo(targetPivot)
            succeeded, actionError = pcall(callback)
        end

        local processingDeadline = os.clock() + 0.5
        while isCycleActive() and os.clock() < processingDeadline do
            task.wait(0.05)
        end
        if character.Parent then
            character:PivotTo(previousPivot)
        end
        promptActionBusy = false
        promptActionBusySince = 0

        if actionError then
            error(actionError)
        end
        return succeeded
    end

    local function getRngSlotRarity(_slotIndex, droneName)
        return getDroneRarity(droneName)
    end

    UpgradesTab:CreateSection("Dock Automation")
    RuntimeContext.CreateToggle(UpgradesTab, {
        Name = "Auto Unlock Docks",
        CurrentValue = false,
        Ext = true,
        AnalyticsId = "auto_unlock_docks",
        Callback = function(enabled)
            autoUnlockDocks = enabled
        end,
    })
    RuntimeContext.StartLoop("auto_unlock_docks", 0.75, function(isCycleActive)
        local playerBase = getPlayerBase()
        if not playerBase or not isCycleActive() then
            return
        end

        local lockedDocks = {}
        for _, object in ipairs(playerBase:GetDescendants()) do
            if object:IsA("BasePart")
                and object.Name == "Dock"
                and tonumber(object:GetAttribute("FS_DockIndex"))
                and object.Parent
                and object.Parent:GetAttribute("FS_DockRevealed") == true
                and object.Parent:GetAttribute("FS_DockUnlocked") == false
            then
                table.insert(lockedDocks, object)
            end
        end
        table.sort(lockedDocks, function(left, right)
            return left:GetAttribute("FS_DockIndex") < right:GetAttribute("FS_DockIndex")
        end)

        local dock = lockedDocks[1]
        local prompt = dock and dock:FindFirstChild("FS_DockUnlockPrompt")
        if dock and prompt then
            local dockIndex = dock:GetAttribute("FS_DockIndex")
            runNearPrompt(prompt, isCycleActive, function()
                UnlockDock:FireServer({ dockIndex = dockIndex })
            end)
        end
    end, function()
        return autoUnlockDocks and isProfileReady()
    end)

    DronesTab:CreateSection("Drone Rolling")
    RuntimeContext.CreateDropdown(DronesTab, {
        Name = "Desired Drones",
        Options = droneNames,
        CurrentOption = {},
        MultipleOptions = true,
        Flag = SCRIPT.id .. "_desired_drones",
        AnalyticsId = "desired_drones",
        Callback = function(selection)
            selectedDroneNames = makeSelectionSet(selection)
        end,
    })
    RuntimeContext.CreateDropdown(DronesTab, {
        Name = "Desired Rarities",
        Options = droneRarities,
        CurrentOption = {},
        MultipleOptions = true,
        Flag = SCRIPT.id .. "_desired_drone_rarities",
        AnalyticsId = "desired_drone_rarities",
        Callback = function(selection)
            selectedDroneRarities = makeSelectionSet(selection)
        end,
    })
    autoRollToggle = RuntimeContext.CreateToggle(DronesTab, {
        Name = "Auto Roll Drones",
        CurrentValue = false,
        Ext = true,
        AnalyticsId = "auto_roll_drones",
        Callback = function(enabled)
            autoRollDrones = enabled
            if enabled then
                task.spawn(function()
                    if not RuntimeContext.IsActive()
                        or not autoRollDrones
                        or not isProfileReady()
                    then
                        return
                    end

                    local playerBase = getPlayerBase()
                    local rng = playerBase and playerBase:FindFirstChild("RNG")
                    local rollPrompt = rng
                        and rng:FindFirstChild("FS_RollDronesPrompt", true)
                    if rollPrompt then
                        runNearPrompt(rollPrompt, function()
                            return RuntimeContext.IsActive()
                                and autoRollDrones
                                and isProfileReady()
                        end, function()
                            RollDrones:FireServer({})
                        end)
                    end
                end)
            end
        end,
    })
    RuntimeContext.CreateToggle(DronesTab, {
        Name = "Auto Buy Matching Drones",
        CurrentValue = false,
        Ext = true,
        AnalyticsId = "auto_buy_matching_drones",
        Callback = function(enabled)
            autoBuyDroneMatches = enabled
        end,
    })
    RuntimeContext.CreateToggle(DronesTab, {
        Name = "Stop Auto Roll After Match",
        CurrentValue = true,
        Ext = true,
        AnalyticsId = "stop_auto_roll_after_match",
        Callback = function(enabled)
            stopRollAfterMatch = enabled
        end,
    })

    RuntimeContext.StartLoop("auto_roll_drones", 4, function(isCycleActive)
        local playerBase = getPlayerBase()
        local rng = playerBase and playerBase:FindFirstChild("RNG")
        local rollPrompt = rng and rng:FindFirstChild("FS_RollDronesPrompt", true)
        if isCycleActive() and rollPrompt then
            runNearPrompt(rollPrompt, isCycleActive, function()
                RollDrones:FireServer({})
            end)
        end
    end, function()
        return autoRollDrones and isProfileReady()
    end)

    RuntimeContext.StartLoop("auto_buy_matching_drones", 0.25, function(isCycleActive)
        local purchasedMatch = false
        for slotIndex, droneName in ipairs(currentRngSlots) do
            if not isCycleActive() then
                break
            end
            if type(droneName) == "string" then
                local rarity = getRngSlotRarity(slotIndex, droneName)
                local isMatch = selectedDroneNames[droneName] == true
                    or (rarity and selectedDroneRarities[rarity] == true)
                local attemptKey = tostring(currentRollEpoch) .. ":" .. tostring(slotIndex)
                local lastAttempt = attemptedRngSlots[attemptKey]

                if isMatch and (not lastAttempt or os.clock() - lastAttempt >= 2) then
                    local playerBase = getPlayerBase()
                    local rng = playerBase and playerBase:FindFirstChild("RNG")
                    local slot = rng and rng:FindFirstChild("Slot" .. tostring(slotIndex))
                    local pickUpPrompt = slot
                        and slot:FindFirstChild("FS_PickUpDronePrompt", true)
                    local dispatched = runNearPrompt(pickUpPrompt, isCycleActive, function()
                        fireproximityprompt(pickUpPrompt)
                    end)
                    attemptedRngSlots[attemptKey] = os.clock()

                    if dispatched then
                        purchasedMatch = true
                        RuntimeContext.Notify(
                            "Drone Match Found",
                            droneName .. (rarity and " (" .. rarity .. ")" or "")
                        )
                    end
                end
            end
        end

        if purchasedMatch and stopRollAfterMatch then
            autoRollToggle:Set(false)
        end
    end, function()
        return autoBuyDroneMatches and isProfileReady()
    end)

    DronesTab:CreateSection("Dock Management")
    RuntimeContext.CreateToggle(DronesTab, {
        Name = "Auto Fill Empty Docks",
        CurrentValue = false,
        Ext = true,
        AnalyticsId = "auto_fill_empty_docks",
        Callback = function(enabled)
            autoFillDocks = enabled
            syncDroneManagementLoopState()
            if enabled then
                requestInventorySync()
            end
        end,
    })
    RuntimeContext.CreateToggle(DronesTab, {
        Name = "Auto Replace With Better Drones",
        CurrentValue = false,
        Ext = true,
        AnalyticsId = "auto_replace_docked_drones",
        Callback = function(enabled)
            autoReplaceDocks = enabled
            syncDroneManagementLoopState()
            if enabled then
                requestInventorySync()
            end
        end,
    })
    RuntimeContext.CreateToggle(DronesTab, {
        Name = "Protect Favorite Drones",
        CurrentValue = true,
        AnalyticsId = "protect_favorite_drones",
        Callback = function(enabled)
            preserveFavoriteDrones = enabled
        end,
    })

    RuntimeContext.StartLoop("drone_dock_management", 2, function(isCycleActive)
        if droneManagementBusy then
            if os.clock() - droneManagementBusySince < 10 then
                return
            end
            droneManagementBusy = false
        end
        droneManagementBusy = true
        droneManagementBusySince = os.clock()
        requestInventorySync()
        task.wait(0.35)

        if not next(inventoryItems) then
            if os.clock() - lastInventoryWarningAt >= 8 then
                lastInventoryWarningAt = os.clock()
                RuntimeContext.Notify(
                    "Waiting For Drone Inventory",
                    "Move one drone between your bag and hotbar once to sync it."
                )
            end
            droneManagementBusy = false
            droneManagementBusySince = 0
            return
        end

        local docked, available, occupiedHotbar = getInventoryState()
        local unlockedDocks = getUnlockedDockIndices()
        local targetDock

        if autoFillDocks then
            for _, dockIndex in ipairs(unlockedDocks) do
                if not docked[dockIndex] then
                    targetDock = dockIndex
                    break
                end
            end
        end

        local candidate = available[1]
        if targetDock and candidate and isCycleActive() then
            prepareAndPlaceDrone(candidate, targetDock, occupiedHotbar)
        elseif autoReplaceDocks and candidate then
            local weakestDockIndex
            local weakestDrone
            for _, dockIndex in ipairs(unlockedDocks) do
                local drone = docked[dockIndex]
                local knownRarity = drone and getDroneRarity(drone.droneType)
                if drone and knownRarity
                    and (not preserveFavoriteDrones or drone.favorite ~= true)
                    and (not weakestDrone
                        or getDroneScore(drone) < getDroneScore(weakestDrone))
                then
                    weakestDockIndex = dockIndex
                    weakestDrone = drone
                end
            end

            if weakestDrone
                and getDroneScore(candidate) > getDroneScore(weakestDrone)
                and isCycleActive()
            then
                local cleared = recallDroneFromDock(
                    weakestDrone,
                    weakestDockIndex,
                    isCycleActive
                )
                if cleared and isCycleActive() then
                    local inventoryDeadline = os.clock() + 1.25
                    while isCycleActive() and os.clock() < inventoryDeadline do
                        local removedDrone = inventoryItems[tostring(weakestDrone.uid)]
                        if removedDrone
                            and tostring(removedDrone.location or "")
                                ~= "dock:" .. tostring(weakestDockIndex)
                        then
                            break
                        end
                        task.wait(0.1)
                    end
                    local _, refreshedAvailable, refreshedHotbar = getInventoryState()
                    local refreshedCandidate = inventoryItems[tostring(candidate.uid)]
                    local candidateLocation = refreshedCandidate
                        and tostring(refreshedCandidate.location or "") or ""
                    if not refreshedCandidate
                        or (candidateLocation ~= "bag"
                            and not candidateLocation:match("^hotbar:%d+$"))
                    then
                        refreshedCandidate = refreshedAvailable[1]
                    end
                    if refreshedCandidate then
                        prepareAndPlaceDrone(
                            refreshedCandidate,
                            weakestDockIndex,
                            refreshedHotbar
                        )
                    end
                end
            end
        end

        task.wait(0.4)
        requestInventorySync()
        droneManagementBusy = false
        droneManagementBusySince = 0
    end, function()
        return (autoFillDocks or autoReplaceDocks) and isProfileReady()
    end)

    DronesTab:CreateSection("Drone Upgrades")
    RuntimeContext.CreateDropdown(DronesTab, {
        Name = "Upgrade Mode",
        Options = { "Best Docked", "All Docked", "Selected Drone Types" },
        CurrentOption = { "Best Docked" },
        Flag = SCRIPT.id .. "_drone_upgrade_mode",
        AnalyticsId = "drone_upgrade_mode",
        Callback = function(selection)
            droneUpgradeMode = type(selection) == "table" and selection[1]
                or tostring(selection)
        end,
    })
    RuntimeContext.CreateDropdown(DronesTab, {
        Name = "Upgrade Drone Types",
        Options = droneNames,
        CurrentOption = {},
        MultipleOptions = true,
        Flag = SCRIPT.id .. "_upgrade_drone_types",
        AnalyticsId = "upgrade_drone_types",
        Callback = function(selection)
            selectedUpgradeDroneTypes = makeSelectionSet(selection)
        end,
    })
    RuntimeContext.CreateToggle(DronesTab, {
        Name = "Auto Upgrade Drones",
        CurrentValue = false,
        Ext = true,
        AnalyticsId = "auto_upgrade_drones",
        Callback = function(enabled)
            autoUpgradeDrones = enabled
            if enabled then
                requestInventorySync()
            end
        end,
    })

    RuntimeContext.StartLoop("auto_upgrade_drones", 0.8, function(isCycleActive)
        requestInventorySync()
        task.wait(0.25)
        if not next(inventoryItems) then
            if os.clock() - lastInventoryWarningAt >= 8 then
                lastInventoryWarningAt = os.clock()
                RuntimeContext.Notify(
                    "Waiting For Drone Inventory",
                    "Move one drone between your bag and hotbar once to sync it."
                )
            end
            return
        end
        local docked = getInventoryState()
        local targets = {}
        for _, drone in pairs(docked) do
            if droneUpgradeMode == "All Docked"
                or (droneUpgradeMode == "Selected Drone Types"
                    and selectedUpgradeDroneTypes[drone.droneType] == true)
            then
                table.insert(targets, drone)
            end
        end

        if droneUpgradeMode == "Best Docked" then
            local best
            for _, drone in pairs(docked) do
                if not best or getDroneScore(drone) > getDroneScore(best) then
                    best = drone
                end
            end
            if best then
                targets = { best }
            end
        else
            table.sort(targets, function(left, right)
                return getDroneScore(left) > getDroneScore(right)
            end)
        end

        for _, drone in ipairs(targets) do
            if not isCycleActive() then
                break
            end
            UpgradeDrone:FireServer({ droneId = drone.uid })
            task.wait(0.15)
        end
    end, function()
        return autoUpgradeDrones and isProfileReady()
    end)

end

local function accountSettings()
    local access = environment.ReverbAccess or {}
    local tier = access.tier or environment.ReverbKeyTier or "free"
    local isPremium = tier == "premium"

    return {
        Enabled = true,
        IsPremium = isPremium,
        UserNote = isPremium and "Premium" or "Ad Reward",
        SecondsLeft = access.seconds_left or 0,
        TotalExecutions = access.execution_count or 0,
        ShowInTitle = true,
    }
end

local function start()
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end

    local routedScript = environment.ReverbScript
    if type(routedScript) == "table"
        and routedScript.id
        and routedScript.id ~= SCRIPT.id
    then
        error(
            "Loader routed " ..
            tostring(routedScript.id) ..
            " but this script is " ..
            SCRIPT.id
        )
    end

    environment.ReverbLoadedScripts = environment.ReverbLoadedScripts or {}
    environment.ReverbScriptInstances = environment.ReverbScriptInstances or {}

    local previousInstance = environment.ReverbScriptInstances[SCRIPT.id]
    if not previousInstance
        and environment.ReverbCurrentScript
        and environment.ReverbCurrentScript.metadata
        and environment.ReverbCurrentScript.metadata.id == SCRIPT.id
    then
        previousInstance = environment.ReverbCurrentScript.runtime
    end

    if previousInstance and previousInstance ~= Runtime then
        if type(previousInstance.Destroy) == "function" then
            local succeeded, reloadError = pcall(previousInstance.Destroy)
            if not succeeded then
                warn("[Reverb] Previous instance cleanup failed: " .. tostring(reloadError))
            end
        else
            local previousLibrary = previousInstance.Library
            if type(previousLibrary) == "table"
                and type(previousLibrary.Destroy) == "function"
            then
                pcall(function()
                    previousLibrary:Destroy()
                end)
            end
            environment.ReverbLoadedScripts[SCRIPT.id] = nil
            -- Old templates only watched this flag. Give their loops time to exit.
            task.wait(2.1)
        end
    end

    environment.ReverbScriptInstances[SCRIPT.id] = Runtime
    environment.ReverbLoadedScripts[SCRIPT.id] = instanceToken

    local uiSource = game:HttpGet(REVERB_UI_URL)
    local loadUi, compileError = loadstring(uiSource)
    if not loadUi then
        error("ReverbUI failed to compile: " .. tostring(compileError))
    end

    local ReverbLib = loadUi()
    if type(ReverbLib) ~= "table" or type(ReverbLib.CreateWindow) ~= "function" then
        error("ReverbUI did not return a valid library")
    end

    local Window = ReverbLib:CreateWindow({
        Name = SCRIPT.name,
        Icon = "reverb",
        LoadingTitle = "Reverb",
        LoadingSubtitle = "Loading " .. SCRIPT.name,
        Theme = "Reverb",
        ToggleUIKeybind = "K",
        DisableReverbLibPrompts = true,
        DisableBuildWarnings = false,
        Account = accountSettings(),
        ConfigurationSaving = {
            Enabled = true,
            FolderName = "Reverb Hub",
            FileName = SCRIPT.id,
        },
        ScriptName = SCRIPT.name,
        ScriptVersion = SCRIPT.version,
        Author = SCRIPT.author,
        LastUpdated = SCRIPT.updated,
    })

    Runtime.Library = ReverbLib
    Runtime.Window = Window
    Runtime.Notify = function(title, content)
        ReverbLib:Notify({
            Title = title or "Reverb",
            Content = content or "",
            Duration = 5,
            Image = "bell",
        })
    end

    buildGame(Runtime)

    Window:CreateChangelogTab({
        Name = "Changelog",
        Icon = "history",
        ScriptName = SCRIPT.name,
        Entries = SCRIPT.changelog,
    })

    environment.ReverbCurrentScript = {
        metadata = SCRIPT,
        library = ReverbLib,
        window = Window,
        runtime = Runtime,
    }

    ReverbLib:LoadConfiguration()

    track("script_ready", {
        script_id = SCRIPT.id,
        game_name = SCRIPT.name,
        script_name = SCRIPT.name,
        script_version = SCRIPT.version,
    })

    task.delay(600, function()
        if Runtime.IsActive() then
            track("session_heartbeat", {
                script_id = SCRIPT.id,
                game_name = SCRIPT.name,
                script_name = SCRIPT.name,
                script_version = SCRIPT.version,
                metadata = { uptime_seconds = 600 },
            })
        end
    end)

    print("[Reverb] " .. SCRIPT.name .. " is ready.")
end

local succeeded, startupError = xpcall(start, function(message)
    return debug.traceback(tostring(message), 2)
end)

if not succeeded then
    Runtime.Destroy()
    error(startupError, 0)
end
