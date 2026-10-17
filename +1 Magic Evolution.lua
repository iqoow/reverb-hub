-- +1 Magic Evolution

local SCRIPT = {
    id = "1MagicEvolution",
    name = "+1 Magic Evolution",
    version = "V1",
    updated = "3rd July 2026",
    author = "Reverb",
    changelog = {
        {
            Version = "V1",
            Date = "3rd July 2026",
            Title = "Script Release",
            Summary = "Initial release of Reverb support for +1 Magic Evolution.",
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
    track("feature_error", featurePayload(featureId, {
        error = tostring(featureError),
    }))
    warn("[Reverb] " .. tostring(featureId) .. " failed: " .. tostring(featureError))
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
    settings.Callback = protectedCallback(featureId, callback, function(value)
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
            if type(isEnabled) == "function" and not isEnabled() then
                task.wait(idleInterval)
                continue
            end

            task.wait(activeInterval)
            if not Runtime.IsActive() then
                break
            end

            if type(isEnabled) == "function" and not isEnabled() then
                continue
            end

            local succeeded, loopError = pcall(callback)
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
    local MAIN_PLACE_ID = 116223724643557
    local DUNGEON_PLACE_ID = 140070560575882
    local isDungeon = game.PlaceId == DUNGEON_PLACE_ID
    local MainTab = RuntimeContext.Window:CreateTab("Main", "home")
    MainTab:CreateSection(isDungeon and "Dungeon" or "Main")

    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local player = Players.LocalPlayer
    environment.ReverbScriptCache = environment.ReverbScriptCache or {}
    environment.ReverbScriptCache[SCRIPT.id] =
        environment.ReverbScriptCache[SCRIPT.id] or {}
    local scriptCache = environment.ReverbScriptCache[SCRIPT.id]

    local function queueConnectedPlaceLoader()
        if game.PlaceId ~= MAIN_PLACE_ID and game.PlaceId ~= DUNGEON_PLACE_ID then
            return false
        end

        local key = environment.script_key
        if type(key) ~= "string"
            or (
                key:match("^REVERB%-FREE%-[%w_-]+$") == nil
                and key:match("^REVERB%-PREM%-[%w_-]+$") == nil
            )
        then
            return false
        end

        local queueTeleport
        pcall(function()
            queueTeleport = queue_on_teleport
                or queueonteleport
                or (syn and syn.queue_on_teleport)
                or (fluxus and fluxus.queue_on_teleport)
        end)
        if type(queueTeleport) ~= "function" then
            RuntimeContext.Notify(
                "Reverb",
                "Your executor cannot automatically load Reverb after teleports."
            )
            return false
        end

        local loaderConfig = environment.ReverbLoaderConfig
        local source = type(loaderConfig) == "table"
            and tostring(loaderConfig.source or "game_teleport")
            or "game_teleport"
        source = source:lower():gsub("[^%w_-]", ""):sub(1, 40)
        if source == "" then
            source = "game_teleport"
        end

        local channel = type(loaderConfig) == "table"
            and loaderConfig.channel == "testing"
            and "&channel=testing"
            or ""
        local loaderUrl = "https://loader.rbxreverb.com/api/loader?source="
            .. source
            .. channel
        local queuedSource = string.format([[
if not game:IsLoaded() then
    game.Loaded:Wait()
end
if game.PlaceId == %d or game.PlaceId == %d then
    local environment = (getgenv and getgenv()) or _G
    environment.script_key = %q
    local source = game:HttpGet(%q)
    local loader, compileError = loadstring(source)
    if loader then
        loader()
    else
        warn("[Reverb] Teleport loader failed: " .. tostring(compileError))
    end
end
]], MAIN_PLACE_ID, DUNGEON_PLACE_ID, key, loaderUrl)

        local queued, queueError = pcall(queueTeleport, queuedSource)
        if not queued then
            warn("[Reverb] Could not queue teleport loader: " .. tostring(queueError))
            return false
        end

        track("connected_place_loader_queued", {
            destination_type = isDungeon and "main" or "dungeon",
        })
        return true
    end

    queueConnectedPlaceLoader()

    if isDungeon then
        local damageRemote = ReplicatedStorage
            :WaitForChild("Remotes")
            :WaitForChild("DealMobDamage")
        local gainMagicPowerRemote = ReplicatedStorage
            :WaitForChild("Remotes")
            :WaitForChild("GainMagicPower")
        local dungeonMobs = workspace:WaitForChild("DungeonMobs")
        local killAuraEnabled = false
        local autoMagicPowerEnabled = false
        local safeModeEnabled = false
        local safeConnection = nil
        local safeCFrame = nil
        local returnCFrame = nil
        local mobCursor = 0

        MainTab:CreateParagraph({
            Title = "Dungeon Mode",
            Content = "These controls are only active inside the connected dungeon game. Turn on the game's Auto Pick Cards option so dungeon upgrades are selected automatically.",
        })

        RuntimeContext.CreateToggle(MainTab, {
            Name = "Auto Magic Power",
            CurrentValue = false,
            Flag = SCRIPT.id .. "_dungeon_auto_magic_power",
            AnalyticsId = "dungeon_auto_magic_power",
            Callback = function(enabled)
                autoMagicPowerEnabled = enabled
            end,
        })

        RuntimeContext.StartLoop("dungeon_auto_magic_power", 0.1, function()
            gainMagicPowerRemote:FireServer()
        end, function()
            return autoMagicPowerEnabled
        end)

        RuntimeContext.CreateToggle(MainTab, {
            Name = "Kill Aura",
            CurrentValue = false,
            Flag = SCRIPT.id .. "_dungeon_kill_aura",
            AnalyticsId = "dungeon_kill_aura",
            Callback = function(enabled)
                killAuraEnabled = enabled
            end,
        })

        RuntimeContext.StartLoop("dungeon_kill_aura", 0.12, function()
            local mobs = {}
            for _, mob in ipairs(dungeonMobs:GetChildren()) do
                if mob:IsA("Model") then
                    local humanoid = mob:FindFirstChildOfClass("Humanoid")
                    if not humanoid or humanoid.Health > 0 then
                        table.insert(mobs, mob)
                    end
                end
            end

            if #mobs == 0 then
                mobCursor = 0
                return
            end

            mobCursor = (mobCursor % #mobs) + 1
            damageRemote:FireServer(mobs[mobCursor], 135)
        end, function()
            return killAuraEnabled
        end)

        local function stopSafeMode(restorePosition)
            if safeConnection then
                safeConnection:Disconnect()
                safeConnection = nil
            end

            if restorePosition and returnCFrame then
                local character = player.Character
                local rootPart = character
                    and character:FindFirstChild("HumanoidRootPart")
                if rootPart then
                    rootPart.CFrame = returnCFrame
                end
            end

            safeCFrame = nil
            returnCFrame = nil
        end

        local function startSafeMode()
            stopSafeMode(false)

            local character = player.Character or player.CharacterAdded:Wait()
            local rootPart = character:WaitForChild("HumanoidRootPart")
            returnCFrame = rootPart.CFrame
            safeCFrame = rootPart.CFrame + Vector3.new(0, 60, 0)

            safeConnection = RunService.Heartbeat:Connect(function()
                if not safeModeEnabled or not RuntimeContext.IsActive() then
                    return
                end

                local activeCharacter = player.Character
                local activeRoot = activeCharacter
                    and activeCharacter:FindFirstChild("HumanoidRootPart")
                if activeRoot and safeCFrame then
                    activeRoot.AssemblyLinearVelocity = Vector3.zero
                    activeRoot.AssemblyAngularVelocity = Vector3.zero
                    activeRoot.CFrame = safeCFrame
                end
            end)
        end

        RuntimeContext.CreateToggle(MainTab, {
            Name = "Safe Mode",
            CurrentValue = false,
            Flag = SCRIPT.id .. "_dungeon_safe_mode",
            AnalyticsId = "dungeon_safe_mode",
            Callback = function(enabled)
                safeModeEnabled = enabled
                if enabled then
                    startSafeMode()
                    RuntimeContext.Notify(
                        "Reverb",
                        "Safe Mode is holding you above the dungeon."
                    )
                else
                    stopSafeMode(true)
                end
            end,
        })

        RuntimeContext.AddCleanup(function()
            killAuraEnabled = false
            autoMagicPowerEnabled = false
            safeModeEnabled = false
            stopSafeMode(false)
        end)
        return
    end

    local ItemsTab = RuntimeContext.Window:CreateTab("Items", "package")
    local staffRecoveryActive = false
    local autoTrainEnabled = false
    local autoOpenEggEnabled = false
    local autoMagicPowerEnabled = false
    local gainMagicPowerRemote = ReplicatedStorage
        :WaitForChild("Remotes")
        :WaitForChild("GainMagicPower")

    RuntimeContext.CreateToggle(MainTab, {
        Name = "Auto Magic Power",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_auto_magic_power",
        AnalyticsId = "auto_magic_power",
        Callback = function(enabled)
            autoMagicPowerEnabled = enabled
        end,
    })

    RuntimeContext.StartLoop("auto_magic_power", 0.1, function()
        gainMagicPowerRemote:FireServer()
    end, function()
        return autoMagicPowerEnabled or autoTrainEnabled
    end)


    -- ===== INF WINS TOGGLE =====
    local autoInfWinsEnabled = false
    local infWinsConnection = nil
    local winStage = nil
    local winTargetCFrame = scriptCache.winTargetCFrame
    local wallTargetCFrame = scriptCache.wallTargetCFrame

    local function getHighestStage()
        local stagesFolder = workspace:FindFirstChild("Stages")
        if not stagesFolder then return nil end

        local highestNumber = -1
        local highestStage = nil

        for _, child in ipairs(stagesFolder:GetChildren()) do
            local name = child.Name
            if name:match("^Stage%d+$") then
                local num = tonumber(name:sub(6))
                if num and num > highestNumber then
                    highestNumber = num
                    highestStage = child
                end
            end
        end

        return highestStage
    end

    local function getPositionCFrame(instance)
        if not instance then return nil end
        if instance:IsA("BasePart") then
            return instance.CFrame
        elseif instance:IsA("Model") then
            local success, result = pcall(instance.GetBoundingBox, instance)
            if success then
                return result
            else
                return instance:GetPivot()
            end
        elseif instance:IsA("Folder") then
            local part = instance:FindFirstChildWhichIsA("BasePart", true)
            if part then
                return part.CFrame
            end
        end
        return nil
    end

    local function getRootPart()
        local character = player.Character
        return character and character:FindFirstChild("HumanoidRootPart") or nil
    end

    local function refreshWinTarget()
        local stageFolder = getHighestStage()
        if not stageFolder then
            winStage = nil
            return winTargetCFrame ~= nil
        end

        local winButton = stageFolder:FindFirstChild("WinButton")
        local wall = stageFolder:FindFirstChild("Wall")
        local wallPart = wall
            and (
                wall:IsA("BasePart")
                    and wall
                    or wall:FindFirstChildWhichIsA("BasePart", true)
            )
        winStage = stageFolder
        winTargetCFrame = getPositionCFrame(winButton)
        wallTargetCFrame = getPositionCFrame(wallPart or wall)
        scriptCache.winTargetCFrame = winTargetCFrame
        scriptCache.wallTargetCFrame = wallTargetCFrame
        return winTargetCFrame ~= nil
    end

    local function stopInfWins()
        if infWinsConnection then
            infWinsConnection:Disconnect()
            infWinsConnection = nil
        end
    end

    local function pinToWinButton()
        stopInfWins()
        infWinsConnection = RunService.Heartbeat:Connect(function()
            if not autoInfWinsEnabled or not RuntimeContext.IsActive() then
                stopInfWins()
                return
            end

            if not winStage or not winStage.Parent or not winTargetCFrame then
                if not refreshWinTarget() then
                    return
                end
            end

            local rootPart = getRootPart()
            if not rootPart then return end

            rootPart.AssemblyLinearVelocity = Vector3.zero
            rootPart.AssemblyAngularVelocity = Vector3.zero
            rootPart.CFrame = winTargetCFrame + Vector3.new(0, 3, 0)
        end)
    end

    local function startInfWins()
        stopInfWins()
        if not refreshWinTarget() then
            RuntimeContext.Notify(
                "Reverb",
                "Could not find the final WinButton."
            )
            autoInfWinsEnabled = false
            return
        end

        local stageClearedReceived = false
        local stageClearedConnection = nil
        local stageClearedRemote = ReplicatedStorage
            :WaitForChild("Remotes")
            :FindFirstChild("StageCleared")

        if stageClearedRemote and stageClearedRemote:IsA("RemoteEvent") then
            stageClearedConnection = stageClearedRemote.OnClientEvent:Connect(function()
                stageClearedReceived = true
            end)
        end

        local function disconnectStageListener()
            if stageClearedConnection then
                stageClearedConnection:Disconnect()
                stageClearedConnection = nil
            end
        end

        -- Pin at the WinButton first so Roblox streams the rest of the stage.
        pinToWinButton()

        local streamDeadline = tick() + 5
        while autoInfWinsEnabled
            and RuntimeContext.IsActive()
            and not wallTargetCFrame
            and tick() < streamDeadline
        do
            task.wait(0.1)
            refreshWinTarget()
        end

        if not autoInfWinsEnabled or not RuntimeContext.IsActive() then
            stopInfWins()
            disconnectStageListener()
            return
        end

        if not wallTargetCFrame then
            disconnectStageListener()
            RuntimeContext.Notify("Reverb", "The final stage Wall did not load.")
            return
        end

        -- The instance appears before its physics are always ready.
        task.wait(1.5)
        if not autoInfWinsEnabled or not RuntimeContext.IsActive() then
            stopInfWins()
            disconnectStageListener()
            return
        end

        stopInfWins()
        for _ = 1, 3 do
            local rootPart = getRootPart()
            if not rootPart then
                task.wait(0.2)
                continue
            end

            rootPart.AssemblyLinearVelocity = Vector3.zero
            rootPart.AssemblyAngularVelocity = Vector3.zero

            -- Hold just beyond the Wall on the WinButton side.
            local wallDeadline = tick() + 0.6
            local towardWinButton =
                winTargetCFrame.Position - wallTargetCFrame.Position
            local wallOffset = towardWinButton.Magnitude > 0.01
                and towardWinButton.Unit * 2
                or wallTargetCFrame.LookVector * 2
            local wallClearCFrame = wallTargetCFrame + wallOffset
            repeat
                rootPart.AssemblyLinearVelocity = Vector3.zero
                rootPart.AssemblyAngularVelocity = Vector3.zero
                rootPart.CFrame = wallClearCFrame
                task.wait(0.05)

                if not autoInfWinsEnabled or not RuntimeContext.IsActive() then
                    disconnectStageListener()
                    return
                end
            until stageClearedReceived or tick() >= wallDeadline

            if stageClearedReceived then
                break
            end

            if not stageClearedConnection then
                break
            end
        end

        disconnectStageListener()

        local rootPart = getRootPart()
        if rootPart then
            rootPart.CFrame = winTargetCFrame + Vector3.new(0, 3, 0)
        end
        pinToWinButton()
    end

    RuntimeContext.CreateToggle(MainTab, {
        Name = "Inf Wins",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_inf_wins",
        AnalyticsId = "inf_wins",
        Callback = function(enabled)
            autoInfWinsEnabled = enabled
            if enabled then
                if autoTrainEnabled then
                    RuntimeContext.Notify(
                        "Reverb",
                        "Inf Wins will resume when Auto Train is disabled."
                    )
                elseif autoOpenEggEnabled then
                    RuntimeContext.Notify(
                        "Reverb",
                        "Inf Wins will resume when Auto Open Best Egg is disabled."
                    )
                else
                    startInfWins()
                end
            else
                stopInfWins()
            end
        end,
    })

    RuntimeContext.AddCleanup(function()
        autoInfWinsEnabled = false
        stopInfWins()
    end)


    -- ===== AUTO EQUIP BEST STAFF TOGGLE =====
    local autoEquipStaffEnabled = false
    local staffButtonName = "Staff Button20"  -- note the space
    local staffToolName = "Angelic Halo Staff"
    local fireTouchInterest = environment.firetouchinterest
        or rawget(_G, "firetouchinterest")
    local staffTouchWarningShown = false
    local staffButtonCFrame = scriptCache.staffButtonCFrame
    local lastStaffStreamRequest = 0
    local lastStaffRecovery = 0

    local function findStaffTouchPart()
        local staffButtons = workspace:FindFirstChild("StaffButtons")
        local staffButton = staffButtons
            and staffButtons:FindFirstChild(staffButtonName)
        local touchPart = staffButton
            and staffButton:FindFirstChild("TouchPart")

        if touchPart and touchPart:IsA("BasePart") then
            staffButtonCFrame = touchPart.CFrame
            scriptCache.staffButtonCFrame = staffButtonCFrame
            return touchPart
        end
        return nil
    end

    -- Cache this while the normal starting area is still streamed.
    findStaffTouchPart()

    local function equipStaffIfOwned()
        local character = player.Character
        if character and character:FindFirstChild(staffToolName) then
            return true
        end

        local backpack = player:FindFirstChild("Backpack")
        local staff = backpack and backpack:FindFirstChild(staffToolName)
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not staff or not staff:IsA("Tool") or not humanoid then
            return false
        end

        humanoid:EquipTool(staff)
        return true
    end

    local function touchStaffButton()
        local touchPart = findStaffTouchPart()
        if not touchPart and staffButtonCFrame
            and tick() - lastStaffStreamRequest >= 3
        then
            lastStaffStreamRequest = tick()
            pcall(function()
                player:RequestStreamAroundAsync(
                    staffButtonCFrame.Position,
                    3
                )
            end)
            touchPart = findStaffTouchPart()
        end

        if not touchPart then
            if not staffTouchWarningShown then
                staffTouchWarningShown = true
                RuntimeContext.Notify(
                    "Reverb",
                    "Equip the best staff once before travelling if its area was not cached."
                )
            end
            return false
        end

        local rootPart = getRootPart()
        if not rootPart or type(fireTouchInterest) ~= "function" then
            if not staffTouchWarningShown then
                staffTouchWarningShown = true
                RuntimeContext.Notify(
                    "Reverb",
                    "Your executor does not support touch activation."
                )
            end
            return false
        end

        local touchStarted = pcall(fireTouchInterest, rootPart, touchPart, 0)
        task.wait(0.05)
        local touchEnded = pcall(fireTouchInterest, rootPart, touchPart, 1)
        return touchStarted and touchEnded
    end

    local function recoverStaffAfterRebirth()
        if staffRecoveryActive or tick() - lastStaffRecovery < 2 then
            return
        end
        lastStaffRecovery = tick()
        staffRecoveryActive = true

        RuntimeContext.Notify(
            "Reverb",
            "Rebirth detected. Recovering wins and Best Staff."
        )

        local infWinsWasEnabled = autoInfWinsEnabled
        local recovered = false

        for _ = 1, 3 do
            if not autoTrainEnabled or not RuntimeContext.IsActive() then
                break
            end

            -- Keep Auto Train paused while the proven Inf Wins startup
            -- streams the stage, clears the Wall, and earns the needed win.
            autoInfWinsEnabled = true
            startInfWins()
            task.wait(0.7)
            stopInfWins()
            autoInfWinsEnabled = infWinsWasEnabled

            if not autoTrainEnabled or not RuntimeContext.IsActive() then
                break
            end

            touchStaffButton()
            task.wait(0.4)
            if equipStaffIfOwned() then
                recovered = true
                break
            end
        end

        stopInfWins()
        autoInfWinsEnabled = infWinsWasEnabled

        if not recovered
            and autoTrainEnabled
            and RuntimeContext.IsActive()
        then
            RuntimeContext.Notify(
                "Reverb",
                "Best Staff recovery will retry shortly."
            )
        end

        staffRecoveryActive = false
    end

    RuntimeContext.CreateToggle(MainTab, {
        Name = "Auto Equip Best Staff",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_auto_equip_staff",
        AnalyticsId = "auto_equip_staff",
        Callback = function(enabled)
            autoEquipStaffEnabled = enabled
        end,
    })

    RuntimeContext.StartLoop("auto_equip_staff", 0.5, function()
        if equipStaffIfOwned() then
            return
        end

        if autoTrainEnabled then
            recoverStaffAfterRebirth()
        else
            touchStaffButton()
        end
    end, function()
        return autoEquipStaffEnabled or autoTrainEnabled
    end)

    -- ===== AUTO OPEN BEST EGG TOGGLE =====
    local eggName = "Demonic Egg"
    local eggTargetCFrame = scriptCache.eggTargetCFrame
    local eggReturnCFrame = nil
    local lastEggStreamRequest = 0
    local openEggRemote = ReplicatedStorage
        :WaitForChild("Remotes")
        :WaitForChild("OpenEgg")

    local function findEggTarget()
        local eggs = workspace:FindFirstChild("Eggs")
        local egg = eggs and eggs:FindFirstChild(eggName)
        local eggCFrame = getPositionCFrame(egg)
        if eggCFrame then
            eggTargetCFrame = eggCFrame
            scriptCache.eggTargetCFrame = eggCFrame
        end
        return eggTargetCFrame
    end

    local function ensureEggArea()
        if findEggTarget() then
            return true
        end
        if not eggTargetCFrame then
            return false
        end

        if tick() - lastEggStreamRequest >= 3 then
            lastEggStreamRequest = tick()
            pcall(function()
                player:RequestStreamAroundAsync(
                    eggTargetCFrame.Position,
                    3
                )
            end)
            findEggTarget()
        end
        return eggTargetCFrame ~= nil
    end

    -- Cache the egg while the starting area is normally available.
    findEggTarget()

    RuntimeContext.CreateToggle(MainTab, {
        Name = "Auto Open Best Egg",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_auto_open_best_egg",
        AnalyticsId = "auto_open_best_egg",
        Callback = function(enabled)
            autoOpenEggEnabled = enabled

            if enabled then
                local rootPart = getRootPart()
                eggReturnCFrame = rootPart and rootPart.CFrame or nil
                if autoInfWinsEnabled then
                    stopInfWins()
                end

                if autoTrainEnabled then
                    RuntimeContext.Notify(
                        "Reverb",
                        "Auto Egg is paused while Auto Train controls your position."
                    )
                end

                if not ensureEggArea() then
                    RuntimeContext.Notify(
                        "Reverb",
                        "Demonic Egg was not cached. Visit it once and try again."
                    )
                end
                return
            end

            if autoTrainEnabled then
                return
            elseif autoInfWinsEnabled then
                startInfWins()
            elseif eggReturnCFrame then
                local rootPart = getRootPart()
                if rootPart then
                    rootPart.CFrame = eggReturnCFrame
                end
            end
        end,
    })

    RuntimeContext.StartLoop("auto_open_best_egg", 0, function()
        if not ensureEggArea() then
            return
        end

        local rootPart = getRootPart()
        if not rootPart then return end

        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero
        rootPart.CFrame = eggTargetCFrame + Vector3.new(0, 3, 0)

        -- Give the server a moment to receive the replicated position.
        task.wait(0.03)
        if not autoOpenEggEnabled or not RuntimeContext.IsActive() then
            return
        end
        openEggRemote:InvokeServer(eggName)
    end, function()
        return autoOpenEggEnabled and not autoTrainEnabled
    end)

    RuntimeContext.AddCleanup(function()
        autoOpenEggEnabled = false
    end)

    -- ===== AUTO TRAIN TOGGLE =====
    local BEST_TRAINING_OPTION = "Best Available (Free/Rebirth)"
    local trainingAreas = {}
    local trainingByOption = {}
    local selectedTrainingOption = BEST_TRAINING_OPTION
    local activeTrainingArea = nil
    local autoTrainConnection = nil
    local trainReturnCFrame = nil
    local lastTrainingRefresh = 0

    local function labelText(model, labelName)
        local label = model:FindFirstChild(labelName, true)
        if not label or not label:IsA("TextLabel") then
            return ""
        end
        return tostring(label.Text or ""):match("^%s*(.-)%s*$")
    end

    local function parseCompactNumber(text)
        local cleaned = tostring(text or ""):lower():gsub(",", "")
        local numberText, suffix = cleaned:match("([%d%.]+)%s*([kmbtq]?)")
        local number = tonumber(numberText)
        if not number then return 0 end

        local multipliers = {
            k = 1e3,
            m = 1e6,
            b = 1e9,
            t = 1e12,
            q = 1e15,
        }
        return number * (multipliers[suffix] or 1)
    end

    local function currentRebirths()
        local leaderstats = player:FindFirstChild("leaderstats")
        local value = leaderstats
            and (
                leaderstats:FindFirstChild("Rebirths")
                or leaderstats:FindFirstChild("Rebirth")
            )
        if not value then
            local data = player:FindFirstChild("Data")
            value = data
                and (
                    data:FindFirstChild("Rebirths")
                    or data:FindFirstChild("Rebirth")
                )
        end

        if value and value:IsA("ValueBase") then
            return tonumber(value.Value) or 0
        end
        return tonumber(player:GetAttribute("Rebirths")) or 0
    end

    local targetPractices = workspace:FindFirstChild("TargetPractices")
    if targetPractices then
        for _, model in ipairs(targetPractices:GetChildren()) do
            local index = tonumber(model.Name:match("^TargetPractice(%d+)$"))
            local hitPart = model:FindFirstChild("HitPart", true)
            if index and hitPart and hitPart:IsA("BasePart") then
                local powerText = labelText(model, "PowerLabel")
                local rebirthText = labelText(model, "RebirthLabel")
                local robuxText = labelText(model, "RobuxLabel")
                local robuxRequirement = parseCompactNumber(robuxText)
                local rebirthRequirement = parseCompactNumber(rebirthText)
                local isRobux = robuxText:lower():find("robux", 1, true) ~= nil
                    and robuxRequirement > 0
                local accessText = "Free"

                if isRobux then
                    accessText = robuxText
                elseif rebirthRequirement > 0 then
                    accessText = rebirthText
                end

                local option = string.format(
                    "%s - %s - %s",
                    model.Name,
                    powerText ~= "" and powerText or "Power boost",
                    accessText
                )
                local area = {
                    index = index,
                    option = option,
                    model = model,
                    hitPartCFrame = hitPart.CFrame,
                    power = parseCompactNumber(powerText),
                    rebirthRequirement = rebirthRequirement,
                    isRobux = isRobux,
                    accessText = accessText,
                }
                table.insert(trainingAreas, area)
                trainingByOption[option] = area
            end
        end
    end

    if #trainingAreas > 0 then
        scriptCache.trainingAreas = {}
        for _, area in ipairs(trainingAreas) do
            table.insert(scriptCache.trainingAreas, {
                index = area.index,
                option = area.option,
                hitPartCFrame = area.hitPartCFrame,
                power = area.power,
                rebirthRequirement = area.rebirthRequirement,
                isRobux = area.isRobux,
                accessText = area.accessText,
            })
        end
    elseif type(scriptCache.trainingAreas) == "table" then
        for _, cachedArea in ipairs(scriptCache.trainingAreas) do
            table.insert(trainingAreas, cachedArea)
            trainingByOption[cachedArea.option] = cachedArea
        end
    end

    table.sort(trainingAreas, function(left, right)
        if left.isRobux ~= right.isRobux then
            return not left.isRobux
        end
        if left.power ~= right.power then
            return left.power < right.power
        end
        return left.index < right.index
    end)

    local trainingOptions = { BEST_TRAINING_OPTION }
    for _, area in ipairs(trainingAreas) do
        table.insert(trainingOptions, area.option)
    end

    local function resolveTrainingArea()
        if selectedTrainingOption ~= BEST_TRAINING_OPTION then
            return trainingByOption[selectedTrainingOption]
        end

        local rebirths = currentRebirths()
        local best = nil
        for _, area in ipairs(trainingAreas) do
            if not area.isRobux and area.rebirthRequirement <= rebirths then
                best = area
            end
        end
        return best
    end

    local function stopAutoTrain()
        if autoTrainConnection then
            autoTrainConnection:Disconnect()
            autoTrainConnection = nil
        end
        activeTrainingArea = nil
    end

    local function startAutoTrain()
        stopAutoTrain()
        activeTrainingArea = resolveTrainingArea()
        if not activeTrainingArea then
            RuntimeContext.Notify(
                "Reverb",
                "No available Free/Rebirth training area was found."
            )
            return
        end

        if activeTrainingArea.isRobux then
            RuntimeContext.Notify(
                "Reverb",
                activeTrainingArea.accessText .. " access is required for this area."
            )
        elseif activeTrainingArea.rebirthRequirement > currentRebirths() then
            RuntimeContext.Notify(
                "Reverb",
                activeTrainingArea.accessText .. " is required for this area."
            )
        end

        pcall(function()
            player:RequestStreamAroundAsync(
                activeTrainingArea.hitPartCFrame.Position,
                3
            )
        end)

        autoTrainConnection = RunService.Heartbeat:Connect(function()
            if not autoTrainEnabled or not RuntimeContext.IsActive() then
                stopAutoTrain()
                return
            end

            if selectedTrainingOption == BEST_TRAINING_OPTION
                and tick() - lastTrainingRefresh >= 1
            then
                lastTrainingRefresh = tick()
                local upgradedArea = resolveTrainingArea()
                if upgradedArea and upgradedArea ~= activeTrainingArea then
                    activeTrainingArea = upgradedArea
                    RuntimeContext.Notify(
                        "Reverb",
                        "Auto Train upgraded to " .. upgradedArea.option
                    )
                end
            end

            local rootPart = getRootPart()
            if staffRecoveryActive
                or not rootPart
                or not activeTrainingArea
            then
                return
            end

            rootPart.AssemblyLinearVelocity = Vector3.zero
            rootPart.AssemblyAngularVelocity = Vector3.zero
            rootPart.CFrame =
                activeTrainingArea.hitPartCFrame + Vector3.new(0, 3, 0)
        end)
    end

    MainTab:CreateSection("Training")

    RuntimeContext.CreateDropdown(MainTab, {
        Name = "Training Area",
        Options = trainingOptions,
        CurrentOption = { selectedTrainingOption },
        MultipleOptions = false,
        Flag = SCRIPT.id .. "_training_area",
        AnalyticsId = "training_area",
        Callback = function(option)
            selectedTrainingOption =
                type(option) == "table" and option[1] or option
            if autoTrainEnabled then
                startAutoTrain()
            end
        end,
    })

    RuntimeContext.CreateToggle(MainTab, {
        Name = "Auto Train",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_auto_train",
        AnalyticsId = "auto_train",
        Callback = function(enabled)
            autoTrainEnabled = enabled

            if enabled then
                local rootPart = getRootPart()
                trainReturnCFrame = rootPart and rootPart.CFrame or nil
                stopInfWins()

                if autoOpenEggEnabled then
                    RuntimeContext.Notify(
                        "Reverb",
                        "Auto Egg is paused while Auto Train controls your position."
                    )
                elseif autoInfWinsEnabled then
                    RuntimeContext.Notify(
                        "Reverb",
                        "Inf Wins is paused while Auto Train controls your position."
                    )
                end

                RuntimeContext.Notify(
                    "Reverb",
                    "Auto Train includes Auto Magic Power and Best Staff."
                )
                startAutoTrain()
                return
            end

            stopAutoTrain()
            if autoOpenEggEnabled then
                RuntimeContext.Notify("Reverb", "Auto Egg resumed.")
            elseif autoInfWinsEnabled then
                startInfWins()
            elseif trainReturnCFrame then
                local rootPart = getRootPart()
                if rootPart then
                    rootPart.CFrame = trainReturnCFrame
                end
            end
        end,
    })

    RuntimeContext.AddCleanup(function()
        autoTrainEnabled = false
        stopAutoTrain()
    end)

    -- ===== ITEM SPAWNERS =====
    local armorFolder = ReplicatedStorage:WaitForChild("Armor")
    local runesFolder = ReplicatedStorage:WaitForChild("Runes")
    local armorPickedUpRemote = ReplicatedStorage
        :WaitForChild("Remotes")
        :WaitForChild("ArmorPickedUp")
    local runePickedUpRemote = ReplicatedStorage
        :WaitForChild("Remotes")
        :WaitForChild("RunePickedUp")

    local function selectedValue(value)
        if type(value) == "table" then
            return value[1]
        end
        return value
    end

    local function sortedNames(nameSet)
        local names = {}
        for name in pairs(nameSet) do
            table.insert(names, name)
        end
        table.sort(names, function(left, right)
            return string.lower(left) < string.lower(right)
        end)
        return names
    end

    local armorSetNames = {}
    for _, armorSet in ipairs(armorFolder:GetChildren()) do
        if armorSet:IsA("Folder") or armorSet:IsA("Model") then
            local setName = armorSet.Name:gsub("%s+Armor$", "")
            if setName ~= "" then
                armorSetNames[setName] = true
            end
        end
    end

    -- Also support games that store the individual pieces without set folders.
    for _, armorItem in ipairs(armorFolder:GetDescendants()) do
        local setName = armorItem.Name:match("^(.-)%s+Chestplate$")
            or armorItem.Name:match("^(.-)%s+Boots$")
        if setName and setName ~= "" then
            armorSetNames[setName] = true
        end
    end

    local armorOptions = sortedNames(armorSetNames)
    if #armorOptions == 0 then
        armorOptions = { "No armor sets found" }
    end

    local runeNames = {}
    for _, rune in ipairs(runesFolder:GetDescendants()) do
        if rune.Name:match("%sRune$") then
            runeNames[rune.Name] = true
        end
    end

    local runeOptions = sortedNames(runeNames)
    if #runeOptions == 0 then
        runeOptions = { "No runes found" }
    end

    local selectedArmorSet = armorOptions[1]
    local selectedArmorPiece = "Full Set"
    local selectedRune = runeOptions[1]

    local function spawnArmor(setName, piece)
        if not armorSetNames[setName] then
            RuntimeContext.Notify("Reverb", "That armor set is unavailable.")
            return false
        end

        if piece == "Full Set" or piece == "Chestplate" then
            armorPickedUpRemote:FireServer(setName .. " Chestplate")
        end
        if piece == "Full Set" or piece == "Boots" then
            if piece == "Full Set" then
                task.wait(0.25)
            end
            armorPickedUpRemote:FireServer(setName .. " Boots")
        end

        RuntimeContext.Notify(
            "Reverb",
            piece == "Full Set"
                and (setName .. " armor set spawned.")
                or (setName .. " " .. piece .. " spawned.")
        )
        return true
    end

    ItemsTab:CreateSection("Important")
    ItemsTab:CreateParagraph({
        Title = "Anti-Cheat Warning",
        Content = "Do not spam-spawn armor or runes. Spawning items too quickly may trigger the game's anti-cheat and could get you banned.",
    })

    ItemsTab:CreateSection("Armor Spawner")

    RuntimeContext.CreateDropdown(ItemsTab, {
        Name = "Armor Set",
        Options = armorOptions,
        CurrentOption = { selectedArmorSet },
        MultipleOptions = false,
        Flag = SCRIPT.id .. "_armor_set",
        AnalyticsId = "armor_set_selection",
        Callback = function(option)
            selectedArmorSet = selectedValue(option)
        end,
    })

    RuntimeContext.CreateDropdown(ItemsTab, {
        Name = "Armor Pieces",
        Options = { "Full Set", "Chestplate", "Boots" },
        CurrentOption = { selectedArmorPiece },
        MultipleOptions = false,
        Flag = SCRIPT.id .. "_armor_piece",
        AnalyticsId = "armor_piece_selection",
        Callback = function(option)
            selectedArmorPiece = selectedValue(option)
        end,
    })

    RuntimeContext.CreateButton(ItemsTab, {
        Name = "Spawn Selected Armor",
        AnalyticsId = "spawn_selected_armor",
        Callback = function()
            spawnArmor(selectedArmorSet, selectedArmorPiece)
        end,
    })

    RuntimeContext.CreateButton(ItemsTab, {
        Name = "Spawn Best Set (Lunar)",
        AnalyticsId = "spawn_best_armor",
        Callback = function()
            spawnArmor("Lunar", "Full Set")
        end,
    })

    ItemsTab:CreateSection("Rune Spawner")

    RuntimeContext.CreateDropdown(ItemsTab, {
        Name = "Rune",
        Options = runeOptions,
        CurrentOption = { selectedRune },
        MultipleOptions = false,
        Flag = SCRIPT.id .. "_rune",
        AnalyticsId = "rune_selection",
        Callback = function(option)
            selectedRune = selectedValue(option)
        end,
    })

    RuntimeContext.CreateButton(ItemsTab, {
        Name = "Spawn Selected Rune",
        AnalyticsId = "spawn_selected_rune",
        Callback = function()
            if not runeNames[selectedRune] then
                RuntimeContext.Notify("Reverb", "That rune is unavailable.")
                return
            end

            runePickedUpRemote:FireServer(selectedRune)
            RuntimeContext.Notify(
                "Reverb",
                selectedRune .. " spawned."
            )
        end,
    })

    local spawningAllRunes = false
    RuntimeContext.CreateButton(ItemsTab, {
        Name = "Spawn All Runes",
        AnalyticsId = "spawn_all_runes",
        Callback = function()
            if spawningAllRunes then
                RuntimeContext.Notify(
                    "Reverb",
                    "All runes are already being spawned."
                )
                return
            end

            if next(runeNames) == nil then
                RuntimeContext.Notify("Reverb", "No runes were found.")
                return
            end

            spawningAllRunes = true
            RuntimeContext.Notify(
                "Reverb",
                "Spawning one of each rune. Please do not click again."
            )

            for _, runeName in ipairs(runeOptions) do
                if not RuntimeContext.IsActive() then
                    break
                end
                runePickedUpRemote:FireServer(runeName)
                task.wait(0.25)
            end

            spawningAllRunes = false
            if RuntimeContext.IsActive() then
                RuntimeContext.Notify(
                    "Reverb",
                    "Finished spawning one of each rune."
                )
            end
        end,
    })


    -- Auto Rebirth Toggle
    local autoRebirthEnabled = false
    local rebirthRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Rebirth")

    RuntimeContext.CreateToggle(MainTab, {
        Name = "Auto Rebirth",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_auto_rebirth",
        AnalyticsId = "auto_rebirth",
        Callback = function(enabled)
            autoRebirthEnabled = enabled
        end,
    })

    RuntimeContext.StartLoop("auto_rebirth", 0.75, function()
        rebirthRemote:FireServer()
    end, function()
        return autoRebirthEnabled
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

    local antiCheatFolder = game.Workspace:FindFirstChild("AntiCheatZones")
    if antiCheatFolder then
        pcall(antiCheatFolder.Destroy, antiCheatFolder)
        print("[Reverb] AntiCheatZones deleted.") -- optional, remove if you want total silence
    end
end

local succeeded, startupError = xpcall(start, function(message)
    return debug.traceback(tostring(message), 2)
end)

if not succeeded then
    Runtime.Destroy()
    error(startupError, 0)
end
