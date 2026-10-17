-- MM2

local SCRIPT = {
    id = "MM2",
    name = "MM2",
    version = "V1.1",
    updated = "28 September 2026",
    author = "Reverb",
}

local REVERB_J_URL =
    "https://raw.githubusercontent.com/rbxreverb/ReverbJ/refs/heads/main/source.lua?v=remember-settings-20260812"

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local environment = (getgenv and getgenv()) or _G
local CONFIG_FILE = "ReverbMM2_Config.json"
local REJOIN_LOADER =
    "https://loader.rbxreverb.com/api/loader?source=mm2-rejoin"

local savedConfig = {
    auto_collect = false,
    auto_reset_full = false,
    tween_speed = 25,
    auto_rejoin = true,
    webhook_url = "",
    webhook_enabled = false,
    webhook_overall = false,
    webhook_interval_minutes = 30,
    webhook_box_rewards = false,
    auto_open_box = false,
    selected_box = "Mystery Case #1",
    box_open_delay = 6,
    remember_settings = false,
    last_coin_balance = -1,
}

local function loadConfig()
    if type(isfile) ~= "function"
        or type(readfile) ~= "function"
        or not isfile(CONFIG_FILE)
    then
        return
    end

    local succeeded, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(CONFIG_FILE))
    end)

    if succeeded and type(decoded) == "table" then
        savedConfig.webhook_url = type(decoded.webhook_url) == "string"
            and decoded.webhook_url
            or ""
        savedConfig.last_coin_balance =
            type(decoded.last_coin_balance) == "number"
            and decoded.last_coin_balance
            or -1
        savedConfig.remember_settings = decoded.remember_settings == true

        if not savedConfig.remember_settings then
            return
        end

        for key, defaultValue in pairs(savedConfig) do
            if type(decoded[key]) == type(defaultValue) then
                savedConfig[key] = decoded[key]
            end
        end

        if type(savedConfig.selected_box) == "string" then
            savedConfig.selected_box =
                savedConfig.selected_box:gsub(" Box", " Case")

            if savedConfig.selected_box == "Summer Case '26" then
                savedConfig.selected_box = "Mystery Case #1"
            end
        end
    end
end

local function saveConfig()
    if type(writefile) ~= "function" then
        return
    end

    pcall(function()
        local configToWrite = savedConfig.remember_settings
            and savedConfig
            or {
                remember_settings = false,
                webhook_url = savedConfig.webhook_url,
                last_coin_balance = savedConfig.last_coin_balance,
            }

        writefile(CONFIG_FILE, HttpService:JSONEncode(configToWrite))
    end)
end

loadConfig()

local autoCollectEnabled = savedConfig.auto_collect
local autoResetWhenFull = savedConfig.auto_reset_full
local bagIsFull = false
local resetRequested = false
local activeTween = nil
local runToken = 0
local coinCooldowns = setmetatable({}, { __mode = "k" })
local countedCoins = setmetatable({}, { __mode = "k" })
-- Keep strong references while coins are in Workspace. Weak Instance keys can
-- be garbage-collected even while Roblox still has them parented in the map.
local trackedCoins = {}
local originalCoinCollision = {}
local coinConnections = {}
local stateConnections = {}
local notifyUser = function() end
local activeTargetCoin = nil

local COIN_NAME = "Coin_Server"
local ARRIVAL_DISTANCE = 0.75
local ROOT_HEIGHT_ABOVE_COIN = 1.35
local CONTACT_HOLD_TIME = 0.15
local COLLECTED_COIN_COOLDOWN = 2
local STUCK_TIMEOUT = 2
local STUCK_PROGRESS_DISTANCE = 0.5
local STUCK_COIN_COOLDOWN = 4
local tweenSpeed = math.clamp(savedConfig.tween_speed, 18, 35)
local DEBUG_MAX_LINES = 600
local DEBUG_SAMPLE_INTERVAL = 0.5
local DEBUG_CONSOLE_OUTPUT = false

local debugLines = {}
local debugStartedAt = os.clock()
local lastDebugSampleAt = 0
local lastDebugPosition = nil

local function debugTrace(eventName, details)
    local line = string.format(
        "[%.3f] %s | %s",
        os.clock() - debugStartedAt,
        tostring(eventName),
        tostring(details or "")
    )

    table.insert(debugLines, line)

    if #debugLines > DEBUG_MAX_LINES then
        table.remove(debugLines, 1)
    end

    if DEBUG_CONSOLE_OUTPUT then
        print("[MM2 Debug] " .. line)
    end
end

local function debugMovement(rootPart, coinPart, force)
    local now = os.clock()

    if not force and now - lastDebugSampleAt < DEBUG_SAMPLE_INTERVAL then
        return
    end

    local deltaTime = lastDebugSampleAt > 0 and now - lastDebugSampleAt or 0
    local displacement = lastDebugPosition
        and (rootPart.Position - lastDebugPosition).Magnitude
        or 0
    local measuredSpeed = deltaTime > 0 and displacement / deltaTime or 0
    local coinDistance = coinPart
        and coinPart.Parent
        and (rootPart.Position - coinPart.Position).Magnitude
        or -1

    debugTrace("MOVEMENT", string.format(
        "pos=(%.2f,%.2f,%.2f) moved=%.2f dt=%.3f speed=%.2f"
            .. " verticalVelocity=%.2f coinDistance=%.2f tween=%s",
        rootPart.Position.X,
        rootPart.Position.Y,
        rootPart.Position.Z,
        displacement,
        deltaTime,
        measuredSpeed,
        rootPart.AssemblyLinearVelocity.Y,
        coinDistance,
        activeTween and tostring(activeTween.PlaybackState) or "none"
    ))

    lastDebugSampleAt = now
    lastDebugPosition = rootPart.Position
end

local function buildDebugReport()
    local header = {
        "=== MM2 AUTO COLLECT DEBUG ===",
        "Version=" .. SCRIPT.version,
        "PlaceId=" .. tostring(game.PlaceId),
        "GameId=" .. tostring(game.GameId),
        "TweenSpeed=" .. tostring(tweenSpeed),
        "TrackedCoins=" .. tostring((function()
            local count = 0
            for _ in pairs(trackedCoins) do
                count += 1
            end
            return count
        end)()),
        "AutoCollectEnabled=" .. tostring(autoCollectEnabled),
        "",
    }

    return table.concat(header, "\n")
        .. table.concat(debugLines, "\n")
        .. "\n=== END ==="
end

local function copyDebugReport()
    local output = buildDebugReport()
    local clipboard = setclipboard
        or toclipboard
        or (syn and syn.write_clipboard)

    if type(clipboard) == "function" then
        local succeeded = pcall(clipboard, output)

        if succeeded then
            return true
        end
    end

    print(output)
    return false
end

local httpRequest = request
    or http_request
    or (http and http.request)
    or (syn and syn.request)
    or (fluxus and fluxus.request)

local sessionCoins = 0
local sessionStartedAt = os.clock()
local completedRoundCoins = 0
local currentRoundBag = 0
local roundsCompleted = 0
local roundWasAlive = false
local roundInProgress = false
local cachedPlayerData = nil
local cachedPlayerDataAt = -math.huge
local playerDataRefreshInFlight = false
local playerDataRefreshGeneration = 0
local rejoinStarted = false
local scriptActive = true
local lastStatusWebhookAt = os.clock()
local autoOpenBoxEnabled = savedConfig.auto_open_box
local autoOpenToken = 0
local boxToggleControl = nil
local sessionBoxesOpened = 0
local waitingForBoxFunds = false
local farmStatus = "Idle"
local farmStatusLabel = nil
local sessionStatsLabel = nil
local lastWebhookFailureNoticeAt = -math.huge
local formatDuration

local function refreshFarmDisplay()
    if farmStatusLabel then
        farmStatusLabel.Text = "Status: " .. farmStatus
    end

    if sessionStatsLabel then
        sessionStatsLabel.Text = string.format(
            "Coins: %d  |  Rounds: %d  |  Cases: %d  |  Time: %s",
            sessionCoins,
            roundsCompleted,
            sessionBoxesOpened,
            formatDuration(os.clock() - sessionStartedAt)
        )
    end
end

local function setFarmStatus(status)
    status = tostring(status or "Idle")
    if farmStatus ~= status then
        farmStatus = status
        refreshFarmDisplay()
    end
end

local CASES = {
    ["Mystery Case #1"] = { id = "MysteryBox1", currency = "Coins" },
    ["Mystery Case #2"] = { id = "MysteryBox2", currency = "Coins" },
    ["Knife Case #1"] = { id = "KnifeBox1", currency = "Coins" },
    ["Knife Case #2"] = { id = "KnifeBox2", currency = "Coins" },
    ["Knife Case #3"] = { id = "KnifeBox3", currency = "Coins" },
    ["Knife Case #4"] = { id = "KnifeBox4", currency = "Coins" },
    ["Knife Case #5"] = { id = "KnifeBox5", currency = "Coins" },
    ["Gun Case #1"] = { id = "GunBox1", currency = "Coins" },
    ["Gun Case #2"] = { id = "GunBox2", currency = "Coins" },
    ["Gun Case #3"] = { id = "GunBox3", currency = "Coins" },
    ["Rainbow Case"] = { id = "MLG Box", currency = "Coins" },
}

local CASE_NAMES = {
    "Mystery Case #1",
    "Mystery Case #2",
    "Knife Case #1",
    "Knife Case #2",
    "Knife Case #3",
    "Knife Case #4",
    "Knife Case #5",
    "Gun Case #1",
    "Gun Case #2",
    "Gun Case #3",
    "Rainbow Case",
}

formatDuration = function(seconds)
    if not seconds or seconds == math.huge or seconds < 0 then
        return "calculating..."
    end

    seconds = math.floor(seconds + 0.5)
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remainingSeconds = seconds % 60

    if days > 0 then
        return string.format("%dd %dh %dm", days, hours, minutes)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    end

    return string.format(
        "%dm %ds",
        math.max(minutes, 0),
        math.max(remainingSeconds, 0)
    )
end

local function normalizeWebhookUrl(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function isDiscordWebhookUrl(value)
    local url = normalizeWebhookUrl(value)
    return url:match("^https://discord%.com/api/webhooks/%d+/[%w_%-]+") ~= nil
        or url:match("^https://discordapp%.com/api/webhooks/%d+/[%w_%-]+") ~= nil
end

local function sendWebhook(kind, title, description, fields, force)
    if not savedConfig.webhook_enabled
        or not isDiscordWebhookUrl(savedConfig.webhook_url)
        or type(httpRequest) ~= "function"
    then
        return false
    end

    local allowed = {
        overall = savedConfig.webhook_overall,
        box = savedConfig.webhook_box_rewards,
        test = true,
    }

    if allowed[kind] ~= true and force ~= true then
        return false
    end

    local embedFields = {}

    for _, field in ipairs(fields or {}) do
        table.insert(embedFields, {
            name = tostring(field.name or "Info"),
            value = tostring(field.value or "-"),
            inline = field.inline ~= false,
        })
    end

    local body = HttpService:JSONEncode({
        username = "Reverb MM2",
        embeds = {
            {
                title = tostring(title or "MM2 Update"),
                description = tostring(description or ""),
                color = kind == "overall" and 45055
                    or 5763719,
                author = {
                    name = LocalPlayer.Name .. " • Reverb MM2",
                },
                fields = embedFields,
                footer = {
                    text = string.format(
                        "Reverb MM2 • %s • Session %s",
                        SCRIPT.version,
                        formatDuration(os.clock() - sessionStartedAt)
                    ),
                },
                timestamp = DateTime.now():ToIsoDate(),
            },
        },
    })

    task.spawn(function()
        local succeeded, response = pcall(httpRequest, {
            Url = savedConfig.webhook_url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
            },
            Body = body,
        })

        debugTrace("WEBHOOK", string.format(
            "kind=%s success=%s status=%s",
            tostring(kind),
            tostring(succeeded),
            tostring(response and (response.StatusCode or response.Status) or "none")
        ))

        local statusCode = tonumber(
            response and (response.StatusCode or response.status_code or response.Status)
        ) or 0
        if not succeeded or statusCode < 200 or statusCode >= 300 then
            local now = os.clock()
            if now - lastWebhookFailureNoticeAt >= 30 then
                lastWebhookFailureNoticeAt = now
                notifyUser(
                    statusCode == 429
                        and "Discord is rate limiting webhook updates. Reverb will keep trying normally."
                        or "A webhook update failed. Check the URL and executor HTTP support.",
                    6
                )
            end
        end
    end)

    return true
end

local function parseDisplayedNumber(value)
    local digits = tostring(value or ""):gsub("[^%d]", "")
    return tonumber(digits)
end

local function findPath(root, names)
    local current = root

    for _, name in ipairs(names) do
        current = current and current:FindFirstChild(name)
    end

    return current
end

local function isEffectivelyVisible(instance)
    local current = instance
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")

    while current and current ~= playerGui do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end

        if current:IsA("LayerCollector") and not current.Enabled then
            return false
        end

        current = current.Parent
    end

    return current == playerGui
end

local function requestPlayerDataRefresh()
    if playerDataRefreshInFlight then
        return
    end

    playerDataRefreshInFlight = true
    playerDataRefreshGeneration += 1
    local generation = playerDataRefreshGeneration

    local dataSources = {
        ReplicatedStorage:FindFirstChild("GetSyncDataServer"),
        ReplicatedStorage:FindFirstChild("GetDataServer"),
        ReplicatedStorage:FindFirstChild("GetPlayerData_REMOTE"),
        ReplicatedStorage:FindFirstChild("GetSyncData"),
    }

    for _, dataSource in ipairs(dataSources) do
        if dataSource then
            task.spawn(function()
                local succeeded, playerData = pcall(function()
                    if dataSource:IsA("BindableFunction") then
                        return dataSource:Invoke()
                    end

                    if dataSource:IsA("RemoteFunction") then
                        return dataSource:InvokeServer()
                    end
                end)

                if generation == playerDataRefreshGeneration
                    and playerDataRefreshInFlight
                    and succeeded
                    and type(playerData) == "table"
                then
                    cachedPlayerData = playerData
                    cachedPlayerDataAt = os.clock()
                    playerDataRefreshInFlight = false
                end
            end)
        end
    end

    -- A broken RemoteFunction must not leave refreshes permanently locked.
    task.delay(2.5, function()
        if generation == playerDataRefreshGeneration then
            playerDataRefreshInFlight = false
        end
    end)
end

local function waitForFreshPlayerData(timeoutSeconds)
    local requestedAt = os.clock()
    requestPlayerDataRefresh()

    while playerDataRefreshInFlight
        and os.clock() - requestedAt < timeoutSeconds
    do
        task.wait(0.05)
    end

    return cachedPlayerData
end

local function readShopBalances()
    if os.clock() - cachedPlayerDataAt >= 2 then
        requestPlayerDataRefresh()
    end

    local function directCurrencyValue(root, wantedKeys)
        if type(root) ~= "table" then
            return nil
        end

        local roots = { root }
        for _, key in ipairs({
            "Data",
            "PlayerData",
            "Currencies",
            "Currency",
        }) do
            if type(root[key]) == "table" then
                table.insert(roots, root[key])
            end
        end

        for _, currencyRoot in ipairs(roots) do
            if type(currencyRoot) == "table" then
                for key, value in pairs(currencyRoot) do
                    if wantedKeys[string.lower(tostring(key))]
                        and type(value) == "number"
                    then
                        return value
                    end
                end
            end
        end

        return nil
    end

    -- Round data also contains a bag field named Coins. Only accept persistent
    -- currencies at known sync-data roots so a bag value such as 14 cannot be
    -- reported as the account's 722-coin balance.
    local authoritativeCoins = directCurrencyValue(
        cachedPlayerData,
        { coins = true }
    )
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local crossPlatform = playerGui and playerGui:FindFirstChild("CrossPlatform")
    local shop = crossPlatform and crossPlatform:FindFirstChild("Shop")
    local medium = shop and shop:FindFirstChild("Medium")
    local mediumCoinLabel = findPath(medium, {
        "Title", "Coins", "Container", "Amount",
    })
    local small = shop and shop:FindFirstChild("Small")
    local smallCoinLabel = findPath(small, {
        "Container", "Title", "Container", "Coins", "Container", "Amount",
    })
    local large = shop and shop:FindFirstChild("Large")
    local largeCoinLabel = findPath(large, {
        "BottomBar", "Coins", "Amount",
    })
    -- MM2 keeps the Medium balance label current even when the Shop ancestor
    -- is closed. The inspector confirmed this exact label held the live 748
    -- balance while template labels elsewhere contained 0 and 43,000.
    local coinLabel = mediumCoinLabel

    if not coinLabel then
        for _, candidate in ipairs({ smallCoinLabel, largeCoinLabel }) do
            if candidate and isEffectivelyVisible(candidate) then
                coinLabel = candidate
                break
            end
        end
    end
    local displayedCoinBalance = coinLabel
        and parseDisplayedNumber(coinLabel.Text)
        or nil
    local coinBalance = authoritativeCoins or displayedCoinBalance

    if coinBalance and coinBalance ~= savedConfig.last_coin_balance then
        savedConfig.last_coin_balance = coinBalance
        saveConfig()
    end

    return {
        coins = coinBalance,
    }
end

local function sendOverallWebhook(force)
    if os.clock() - cachedPlayerDataAt >= 2 then
        waitForFreshPlayerData(2.5)
    end
    local balances = readShopBalances()

    local fields = {
        {
            name = "⏱️ Time Elapsed",
            value = formatDuration(os.clock() - sessionStartedAt),
        },
        { name = "🪙 Total Coins Collected", value = sessionCoins },
        { name = "🎮 Rounds Completed", value = roundsCompleted },
        { name = "🎁 Cases Opened", value = sessionBoxesOpened },
        { name = "💰 Current Bag", value = currentRoundBag },
        { name = "⚙️ Farm Status", value = farmStatus },
        { name = "🏃 Tween Speed", value = tweenSpeed },
        {
            name = "♻️ Reset When Full",
            value = autoResetWhenFull and "Enabled" or "Disabled",
        },
        {
            name = "🏦 MM2 Coin Balance",
            value = (function()
                local coins = balances.coins
                return coins and tostring(coins) or "N/A"
            end)(),
        },
    }

    return sendWebhook(
        "overall",
        force and "📊 MM2 Overall Report" or "📊 MM2 Timed Report",
        force
            and "Here is your requested farming progress snapshot."
            or string.format(
                "Your automatic farming report after another %d minutes.",
                savedConfig.webhook_interval_minutes
            ),
        fields,
        force
    )
end

local function updateTimedWebhook()
    local intervalSeconds = math.clamp(
        savedConfig.webhook_interval_minutes,
        5,
        180
    ) * 60

    if savedConfig.webhook_overall
        and os.clock() - lastStatusWebhookAt >= intervalSeconds
    then
        lastStatusWebhookAt = os.clock()
        sendOverallWebhook(false)
    end
end

local function rewardDisplayName(reward)
    return tostring(reward)
        :gsub("_K_2026$", " (Knife)")
        :gsub("_G_2026$", " (Gun)")
        :gsub("_", " ")
end

local function stopAutoOpenBox(message)
    autoOpenBoxEnabled = false
    waitingForBoxFunds = false
    savedConfig.auto_open_box = false
    autoOpenToken += 1
    saveConfig()

    if boxToggleControl then
        boxToggleControl:Set(false, true)
    end

    if message then
        notifyUser(message, 5)
    end
end

local function startAutoOpenBox()
    if not autoOpenBoxEnabled then
        return
    end

    autoOpenToken += 1
    local token = autoOpenToken
    local shopRemotes = ReplicatedStorage
        :WaitForChild("Remotes")
        :WaitForChild("Shop")
    local openCrate = shopRemotes:WaitForChild("OpenCrate")
    local crateComplete = shopRemotes:WaitForChild("CrateComplete")

    task.spawn(function()
        while scriptActive
            and autoOpenBoxEnabled
            and token == autoOpenToken
        do
            local selectedName = savedConfig.selected_box
            local selected = CASES[selectedName]

            if not selected then
                stopAutoOpenBox("Selected case is unavailable.")
                break
            end

            local succeeded, reward = pcall(function()
                return openCrate:InvokeServer(
                    selected.id,
                    "MysteryBox",
                    selected.currency
                )
            end)

            if not succeeded or type(reward) ~= "string" or reward == "" then
                debugTrace("BOX_OPEN_FAILED", string.format(
                    "box=%s success=%s result=%s",
                    selectedName,
                    tostring(succeeded),
                    tostring(reward)
                ))
                if not waitingForBoxFunds then
                    waitingForBoxFunds = true
                    notifyUser(
                        "Auto Open Case is waiting for enough coins or keys.",
                        5
                    )
                end

                task.wait(10)
                continue
            end

            if waitingForBoxFunds then
                waitingForBoxFunds = false
                notifyUser("Enough currency found. Auto Open Case resumed.", 4)
            end

            sessionBoxesOpened += 1
            debugTrace("BOX_OPENED", string.format(
                "box=%s reward=%s",
                selectedName,
                reward
            ))

            sendWebhook(
                "box",
                "🎁 Case Opened!",
                "A new MM2 reward was received.",
                {
                    { name = "📦 Case", value = selectedName },
                    { name = "✨ Reward", value = rewardDisplayName(reward) },
                    { name = "🔎 Reward ID", value = reward },
                    { name = "📊 Cases this session", value = sessionBoxesOpened },
                }
            )

            task.wait(3.5)

            pcall(function()
                crateComplete:FireServer(reward)
            end)

            if not scriptActive
                or not autoOpenBoxEnabled
                or token ~= autoOpenToken
            then
                break
            end

            task.wait(math.clamp(savedConfig.box_open_delay, 2, 30))
        end
    end)
end

local function getTeleportQueue()
    local succeeded, queue = pcall(function()
        return queue_on_teleport
            or queueonteleport
            or (syn and syn.queue_on_teleport)
            or (fluxus and fluxus.queue_on_teleport)
    end)

    return succeeded and type(queue) == "function" and queue or nil
end

local function queueLoaderAfterTeleport()
    local queue = getTeleportQueue()
    if not queue then
        return false
    end

    local currentKey = type(environment.script_key) == "string"
        and environment.script_key
        or nil

    if (not currentKey or currentKey == "")
        and type(isfile) == "function"
        and type(readfile) == "function"
        and isfile("reverb_key.txt")
    then
        local readSucceeded, savedKey = pcall(readfile, "reverb_key.txt")
        if readSucceeded and type(savedKey) == "string" then
            currentKey = savedKey:match("^%s*(.-)%s*$")
        end
    end
    local queuedSource

    if currentKey and currentKey ~= "" then
        queuedSource = string.format([[
local environment = (getgenv and getgenv()) or _G
environment.script_key = %q
_G.script_key = %q
script_key = %q
loadstring(game:HttpGet(%q))()
]], currentKey, currentKey, currentKey, REJOIN_LOADER)
    else
        queuedSource = string.format(
            'loadstring(game:HttpGet(%q))()',
            REJOIN_LOADER
        )
    end

    return pcall(queue, queuedSource)
end

local function beginAutoRejoin(reason, manual)
    if rejoinStarted or (not manual and not savedConfig.auto_rejoin) then
        return
    end

    rejoinStarted = true
    saveConfig()
    setFarmStatus("Rejoining")
    debugTrace("AUTO_REJOIN", "reason=" .. tostring(reason))

    local loaderQueued = queueLoaderAfterTeleport()
    debugTrace("REJOIN_LOADER_QUEUE", "supported=" .. tostring(loaderQueued))

    -- A kicked client only remains active briefly after ErrorMessageChanged.
    -- Start teleporting immediately so Roblox receives the request before the
    -- client stops executing local tasks.
    local teleported, teleportError = pcall(function()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)

    if not teleported then
        rejoinStarted = false
        setFarmStatus(autoCollectEnabled and "Waiting for round" or "Idle")
        debugTrace("AUTO_REJOIN_FAILED", teleportError)
        notifyUser("Rejoin failed to start: " .. tostring(teleportError), 6)
    end
end

local function getRootPart()
    local character = LocalPlayer.Character

    if not character then
        return nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")

    if not humanoid or humanoid.Health <= 0 or not rootPart then
        return nil
    end

    return rootPart
end

local function isRoundActive()
    return LocalPlayer:GetAttribute("Alive") == true
end

local function getFullBagLabel()
    local mainGui = LocalPlayer
        :FindFirstChild("PlayerGui")
        and LocalPlayer.PlayerGui:FindFirstChild("MainGUI")
    local gameFrame = mainGui and mainGui:FindFirstChild("Game")
    local coinBags = gameFrame and gameFrame:FindFirstChild("CoinBags")
    if not coinBags then
        return nil
    end

    local candidates = {}
    local runtimeScript = coinBags:FindFirstChild("CoinBagContainerScript")
    local container = coinBags:FindFirstChild("Container")

    -- Container.Coin is the live round bag. CoinBagContainerScript.Coin is a
    -- template that can remain at 0 while the real bag displays 40 / Full.
    if container and container:FindFirstChild("Coin") then
        table.insert(candidates, container.Coin)
    end

    if runtimeScript and runtimeScript:FindFirstChild("Coin") then
        table.insert(candidates, runtimeScript.Coin)
    end

    for _, coinBag in ipairs(candidates) do
        local full = coinBag and coinBag:FindFirstChild("Full")

        if full
            and full:IsA("GuiObject")
            and full.Visible
            and isEffectivelyVisible(full)
        then
            return full
        end
    end

    for _, coinBag in ipairs(candidates) do
        local full = coinBag and coinBag:FindFirstChild("Full")

        if full and isEffectivelyVisible(coinBag) then
            return full
        end
    end

    for _, coinBag in ipairs(candidates) do
        local full = coinBag and coinBag:FindFirstChild("Full")

        if full then
            return full
        end
    end

    return nil
end

local function getCoinBagCount()
    local fullLabel = getFullBagLabel()
    local coinBag = fullLabel and fullLabel.Parent
    local currencyFrame = coinBag and coinBag:FindFirstChild("CurrencyFrame")
    local icon = currencyFrame and currencyFrame:FindFirstChild("Icon")
    local coins = icon and icon:FindFirstChild("Coins")

    return coins and coins.Text or "unknown"
end

local function readCoinBagNumber()
    -- The label is normally formatted as "10 / 40". Concatenating every
    -- digit turned that into 1040 and heavily inflated webhook totals.
    local current = tostring(getCoinBagCount()):match("(%d[%d,]*)")
    return tonumber(current and current:gsub(",", "")) or 0
end

local function coinBagIsFull()
    local fullLabel = getFullBagLabel()
    if fullLabel
        and fullLabel:IsA("GuiObject")
        and fullLabel.Visible
        and isEffectivelyVisible(fullLabel)
    then
        return true
    end

    local text = tostring(getCoinBagCount())
    local currentText, capacityText = text:match(
        "(%d[%d,]*)%s*/%s*(%d[%d,]*)"
    )
    local current = tonumber(currentText and currentText:gsub(",", ""))
    local capacity = tonumber(capacityText and capacityText:gsub(",", ""))

    return current ~= nil and capacity ~= nil
        and capacity > 0
        and current >= capacity
end

local function sampleCurrentBag()
    if not isRoundActive() then
        return currentRoundBag
    end

    roundInProgress = true
    roundWasAlive = true
    currentRoundBag = math.max(currentRoundBag, readCoinBagNumber())
    sessionCoins = completedRoundCoins + currentRoundBag
    return currentRoundBag
end

local function finishTrackedRound(reason)
    if not roundInProgress then
        return false
    end

    local earnedCoins = math.max(currentRoundBag, readCoinBagNumber())
    completedRoundCoins += earnedCoins
    sessionCoins = completedRoundCoins
    roundsCompleted += 1
    currentRoundBag = 0
    roundInProgress = false
    roundWasAlive = false
    debugTrace("ROUND_COMPLETE", string.format(
        "reason=%s coins=%d rounds=%d",
        tostring(reason),
        earnedCoins,
        roundsCompleted
    ))
    return true
end

local function getCoinPart(coin)
    if not coin or not coin.Parent then
        return nil
    end

    if coin:IsA("BasePart") then
        return coin
    end

    if coin:IsA("Model") then
        return coin.PrimaryPart or coin:FindFirstChildWhichIsA("BasePart", true)
    end

    return coin:FindFirstChildWhichIsA("BasePart", true)
end

local function belongsToActiveMap(coin)
    local current = coin and coin.Parent

    while current and current ~= Workspace do
        if current.Name == "CoinContainer" then
            return current.Parent ~= nil
                and current.Parent ~= Workspace:FindFirstChild("Lobby")
        end

        current = current.Parent
    end

    return false
end

local function addCoin(instance)
    if instance
        and instance.Name == COIN_NAME
        and instance:IsDescendantOf(Workspace)
        and belongsToActiveMap(instance)
    then
        trackedCoins[instance] = true

        local coinPart = getCoinPart(instance)

        if coinPart and originalCoinCollision[coinPart] == nil then
            originalCoinCollision[coinPart] = coinPart.CanCollide
            coinPart.CanCollide = false
        end

        debugTrace("COIN_ADDED", string.format(
            "path=%s class=%s position=%s canTouch=%s wasCollidable=%s",
            instance:GetFullName(),
            instance.ClassName,
            coinPart and tostring(coinPart.Position) or "none",
            coinPart and tostring(coinPart.CanTouch) or "none",
            coinPart and tostring(originalCoinCollision[coinPart]) or "none"
        ))
    end
end

local function removeCoin(instance)
    if instance.Name == "TouchInterest" then
        local owner = instance.Parent

        if owner
            and owner.Name == COIN_NAME
            and trackedCoins[owner]
        then
            local rootPart = getRootPart()
            local ownerPart = getCoinPart(owner)
            local wasOurPickup = owner == activeTargetCoin
                and rootPart
                and ownerPart
                and (rootPart.Position - ownerPart.Position).Magnitude <= 5

            if wasOurPickup and not countedCoins[owner] then
                countedCoins[owner] = true
            end

            coinCooldowns[owner] =
                os.clock() + COLLECTED_COIN_COOLDOWN
            debugTrace("PICKUP_CONFIRMED", "TouchInterest removed from "
                .. owner:GetFullName()
                .. " ours=" .. tostring(wasOurPickup)
                .. " sessionCoins=" .. sessionCoins)
        end

        return
    end

    if not trackedCoins[instance] then
        return
    end

    local coinPart = getCoinPart(instance)

    debugTrace("COIN_REMOVED", string.format(
        "path=%s wasTracked=%s",
        instance:GetFullName(),
        tostring(trackedCoins[instance] == true)
    ))

    if coinPart then
        originalCoinCollision[coinPart] = nil
    end

    trackedCoins[instance] = nil
    coinCooldowns[instance] = nil
    countedCoins[instance] = nil
end

local function startCoinTracking()
    for _, connection in ipairs(coinConnections) do
        connection:Disconnect()
    end

    table.clear(coinConnections)
    table.clear(trackedCoins)

    -- One initial scan is cheap enough. After this, MM2's frequent coin
    -- spawns and removals are handled by events instead of full rescans.
    for _, instance in ipairs(Workspace:GetDescendants()) do
        addCoin(instance)
    end

    table.insert(coinConnections, Workspace.DescendantAdded:Connect(addCoin))
    table.insert(coinConnections, Workspace.DescendantRemoving:Connect(removeCoin))
end

local function stopCoinTracking()
    for _, connection in ipairs(coinConnections) do
        connection:Disconnect()
    end

    for coinPart, wasCollidable in pairs(originalCoinCollision) do
        if coinPart and coinPart.Parent then
            pcall(function()
                coinPart.CanCollide = wasCollidable
            end)
        end
    end

    table.clear(coinConnections)
    table.clear(trackedCoins)
    table.clear(coinCooldowns)
    table.clear(countedCoins)
    table.clear(originalCoinCollision)
end

local function findNearestCoin(rootPart)
    local nearestCoin = nil
    local nearestPart = nil
    local nearestDistance = math.huge

    for instance in pairs(trackedCoins) do
        if not instance.Parent or not instance:IsDescendantOf(Workspace) then
            removeCoin(instance)
            continue
        end

        local cooldownUntil = coinCooldowns[instance]

        if cooldownUntil and cooldownUntil <= os.clock() then
            coinCooldowns[instance] = nil
            cooldownUntil = nil
        end

        if not cooldownUntil then
            local coinPart = getCoinPart(instance)

            if coinPart then
                local distance = (rootPart.Position - coinPart.Position).Magnitude

                if distance < nearestDistance then
                    nearestCoin = instance
                    nearestPart = coinPart
                    nearestDistance = distance
                end
            end
        end
    end

    return nearestCoin, nearestPart, nearestDistance
end

local function stopCharacterMovement()
    if activeTween then
        activeTween:Cancel()
        activeTween = nil
    end

    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")

    if humanoid and rootPart then
        humanoid:MoveTo(rootPart.Position)
    end
end

local function requestCharacterReset()
    if resetRequested or not autoResetWhenFull then
        return
    end

    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if not character or not humanoid or humanoid.Health <= 0 then
        return
    end

    resetRequested = true
    sampleCurrentBag()
    finishTrackedRound("auto_reset_full")
    stopCharacterMovement()
    debugTrace("AUTO_RESET", "bagCount=" .. getCoinBagCount())
    notifyUser("Coin bag full. Auto Reset is preparing the next round.", 4)

    task.defer(function()
        pcall(function()
            humanoid.Health = 0
            character:BreakJoints()
        end)
    end)
end

local function refreshBagState()
    local isFull = coinBagIsFull()

    if isFull ~= bagIsFull then
        bagIsFull = isFull
        debugTrace("BAG_STATE", string.format(
            "full=%s count=%s alive=%s",
            tostring(bagIsFull),
            getCoinBagCount(),
            tostring(isRoundActive())
        ))

        if bagIsFull then
            stopCharacterMovement()
            notifyUser(
                autoResetWhenFull
                    and "Coin bag full. Auto Reset requested."
                    or "Coin bag full. Auto Collect paused until the next round.",
                4
            )
        else
            resetRequested = false
        end
    end

    if bagIsFull then
        requestCharacterReset()
    end

    return bagIsFull
end

local function disconnectStateMonitoring()
    for _, connection in ipairs(stateConnections) do
        connection:Disconnect()
    end

    table.clear(stateConnections)
end

local function startStateMonitoring()
    disconnectStateMonitoring()
    roundWasAlive = isRoundActive()
    roundInProgress = roundWasAlive

    if roundWasAlive then
        currentRoundBag = math.max(currentRoundBag, readCoinBagNumber())
        sessionCoins = completedRoundCoins + currentRoundBag
    end

    local fullLabel = getFullBagLabel()

    if fullLabel then
        table.insert(
            stateConnections,
            fullLabel:GetPropertyChangedSignal("Visible"):Connect(refreshBagState)
        )
    end

    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")

    if playerGui then
        table.insert(stateConnections, playerGui.DescendantAdded:Connect(function(instance)
            if instance.Name == "Full"
                and instance.Parent
                and instance.Parent.Name == "Coin"
            then
                task.defer(startStateMonitoring)
            end
        end))
    end

    table.insert(
        stateConnections,
        LocalPlayer:GetAttributeChangedSignal("Alive"):Connect(function()
            local alive = isRoundActive()
            debugTrace("ROUND_STATE", "alive=" .. tostring(alive))

            if not alive then
                -- A player can die before filling the bag. MM2 may clear the
                -- bag UI before GameOver fires, so commit our sampled amount
                -- as soon as the Alive attribute changes. finishTrackedRound
                -- makes any later GameOver notification a no-op.
                finishTrackedRound("player_died")
                roundWasAlive = false
                stopCharacterMovement()
            elseif not bagIsFull then
                if not roundWasAlive then
                    currentRoundBag = readCoinBagNumber()
                end

                roundWasAlive = true
                roundInProgress = true
                resetRequested = false
            end
        end)
    )

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local gameplay = remotes and remotes:FindFirstChild("Gameplay")
    local coinCollected = gameplay and gameplay:FindFirstChild("CoinCollected")
    local roundStart = gameplay and gameplay:FindFirstChild("RoundStart")
    local gameOver = gameplay and gameplay:FindFirstChild("GameOver")
    local playerDataChanged = gameplay
        and gameplay:FindFirstChild("PlayerDataChanged")

    if playerDataChanged and playerDataChanged:IsA("RemoteEvent") then
        table.insert(stateConnections, playerDataChanged.OnClientEvent:Connect(function()
            cachedPlayerDataAt = -math.huge
        end))
    end

    if coinCollected and coinCollected:IsA("RemoteEvent") then
        table.insert(stateConnections, coinCollected.OnClientEvent:Connect(function()
            if roundInProgress then
                currentRoundBag += 1
                sessionCoins = completedRoundCoins + currentRoundBag
            end
        end))
    end

    if roundStart and roundStart:IsA("RemoteEvent") then
        table.insert(stateConnections, roundStart.OnClientEvent:Connect(function()
            roundInProgress = true
            roundWasAlive = isRoundActive()
            currentRoundBag = 0
            bagIsFull = false
            resetRequested = false
        end))
    end

    if gameOver and gameOver:IsA("RemoteEvent") then
        table.insert(stateConnections, gameOver.OnClientEvent:Connect(function()
            finishTrackedRound("game_over")
        end))
    end

    pcall(function()
        table.insert(
            stateConnections,
            GuiService.ErrorMessageChanged:Connect(function()
                local message = GuiService:GetErrorMessage()

                if type(message) == "string" and message ~= "" then
                    beginAutoRejoin(message)
                end
            end)
        )
    end)

    refreshBagState()
end

local function coinIsCollectible(coin, coinPart)
    return coin
        and coin.Parent
        and coinPart
        and coinPart.Parent
        and coinPart:IsDescendantOf(Workspace)
end

local function getCoinTargetPosition(coinPart)
    return coinPart.Position + Vector3.new(0, ROOT_HEIGHT_ABOVE_COIN, 0)
end

local function contactCoin(rootPart, coin, coinPart, token)
    local character = rootPart.Parent
    local touchedByCharacter = false
    local simulatedTouchSucceeded = false
    local touchConnection = coinPart.Touched:Connect(function(otherPart)
        if character and otherPart:IsDescendantOf(character) then
            touchedByCharacter = true
            debugTrace("TOUCH_EVENT", "characterPart=" .. otherPart.Name)
        end
    end)

    debugTrace("CONTACT_BEGIN", string.format(
        "coin=%s distance=%.3f rootY=%.2f coinY=%.2f",
        coin:GetFullName(),
        (rootPart.Position - coinPart.Position).Magnitude,
        rootPart.Position.Y,
        coinPart.Position.Y
    ))

    -- Keep the root above the floor while its lower body overlaps the coin.
    -- Targeting the coin's center makes character physics push upward.
    local targetPosition = getCoinTargetPosition(coinPart)
    rootPart.CFrame =
        CFrame.new(targetPosition) * rootPart.CFrame.Rotation

    -- Executors that expose touch simulation can notify the hitbox
    -- immediately; ordinary Touched detection remains the main fallback.
    if type(firetouchinterest) == "function" then
        simulatedTouchSucceeded = pcall(function()
            firetouchinterest(rootPart, coinPart, 0)
            firetouchinterest(rootPart, coinPart, 1)
        end)
    end

    local contactUntil = os.clock() + CONTACT_HOLD_TIME

    while autoCollectEnabled
        and runToken == token
        and coinIsCollectible(coin, coinPart)
        and not touchedByCharacter
        and os.clock() < contactUntil
    do
        task.wait()
    end

    touchConnection:Disconnect()

    local confirmed = touchedByCharacter
        or simulatedTouchSucceeded
        or not coinIsCollectible(coin, coinPart)

    if confirmed and not countedCoins[coin] then
        countedCoins[coin] = true
    end

    debugMovement(rootPart, coinPart, true)
    debugTrace("CONTACT_END", string.format(
        "confirmed=%s touched=%s simulated=%s removed=%s",
        tostring(confirmed),
        tostring(touchedByCharacter),
        tostring(simulatedTouchSucceeded),
        tostring(not coinIsCollectible(coin, coinPart))
    ))

    return confirmed
end

local function tweenToCoin(rootPart, coin, coinPart, distance, token)
    activeTargetCoin = coin
    setFarmStatus("Collecting coins")
    debugTrace("TARGET_SELECTED", string.format(
        "coin=%s distance=%.2f position=%s",
        coin:GetFullName(),
        distance,
        tostring(coinPart.Position)
    ))

    if distance <= ARRIVAL_DISTANCE then
        if contactCoin(rootPart, coin, coinPart, token) then
            coinCooldowns[coin] = os.clock() + COLLECTED_COIN_COOLDOWN
        end

        if activeTargetCoin == coin then
            activeTargetCoin = nil
        end

        return
    end

    local targetPosition = getCoinTargetPosition(coinPart)
    local targetDistance = (rootPart.Position - targetPosition).Magnitude
    local duration = math.max(targetDistance / tweenSpeed, 0.1)
    local targetCFrame = CFrame.new(targetPosition) * rootPart.CFrame.Rotation
    local tween = TweenService:Create(
        rootPart,
        TweenInfo.new(duration, Enum.EasingStyle.Linear),
        { CFrame = targetCFrame }
    )

    activeTween = tween
    debugTrace("TWEEN_BEGIN", string.format(
        "distance=%.2f duration=%.3f speedSetting=%.2f",
        distance,
        duration,
        tweenSpeed
    ))
    tween:Play()

    local reachedCoin = false
    local movementStuck = false
    local bestDistance = targetDistance
    local lastProgressAt = os.clock()

    while autoCollectEnabled
        and runToken == token
        and isRoundActive()
        and not bagIsFull
        and tween.PlaybackState == Enum.PlaybackState.Playing
        and rootPart.Parent
        and coinIsCollectible(coin, coinPart)
        and not coinCooldowns[coin]
    do
        debugMovement(rootPart, coinPart, false)

        local remainingDistance = (rootPart.Position - targetPosition).Magnitude
        if remainingDistance <= ARRIVAL_DISTANCE then
            reachedCoin = true
            break
        end

        if bestDistance - remainingDistance >= STUCK_PROGRESS_DISTANCE then
            bestDistance = remainingDistance
            lastProgressAt = os.clock()
        elseif os.clock() - lastProgressAt >= STUCK_TIMEOUT then
            movementStuck = true
            break
        end

        task.wait(0.05)
    end

    local coinWasRemoved = not coinIsCollectible(coin, coinPart)

    if movementStuck then
        coinCooldowns[coin] = os.clock() + STUCK_COIN_COOLDOWN
        setFarmStatus("Skipping unreachable coin")
        debugTrace("TWEEN_STUCK", "coin=" .. coin:GetFullName())
    end

    debugTrace("TWEEN_END", string.format(
        "state=%s reached=%s removed=%s remainingDistance=%.3f",
        tostring(tween.PlaybackState),
        tostring(reachedCoin),
        tostring(coinWasRemoved),
        coinPart and coinPart.Parent
            and (rootPart.Position - targetPosition).Magnitude
            or -1
    ))

    if activeTween == tween then
        if tween.PlaybackState == Enum.PlaybackState.Playing then
            tween:Cancel()
        end

        activeTween = nil
    end

    if reachedCoin
        and autoCollectEnabled
        and runToken == token
        and coinIsCollectible(coin, coinPart)
    then
        if contactCoin(rootPart, coin, coinPart, token) then
            coinCooldowns[coin] = os.clock() + COLLECTED_COIN_COOLDOWN
        end

        if activeTargetCoin == coin then
            activeTargetCoin = nil
        end

        return
    end

    -- Coins removed during travel no longer need to remain in the target list.
    if coinWasRemoved then
        coinCooldowns[coin] = os.clock() + COLLECTED_COIN_COOLDOWN
    end

    if activeTargetCoin == coin then
        activeTargetCoin = nil
    end
end

local function startAutoCollect()
    runToken += 1
    local token = runToken
    lastDebugSampleAt = 0
    lastDebugPosition = nil
    debugTrace("AUTO_COLLECT_START", "token=" .. token)

    task.spawn(function()
        while autoCollectEnabled and runToken == token do
            refreshBagState()

            if bagIsFull then
                setFarmStatus(autoResetWhenFull and "Resetting full bag" or "Bag full")
                task.wait(0.25)
                continue
            end

            if not isRoundActive() then
                setFarmStatus("Waiting for round")
                task.wait(0.25)
                continue
            end

            local rootPart = getRootPart()

            if not rootPart then
                setFarmStatus("Waiting for character")
                task.wait(0.5)
                continue
            end

            local coin, coinPart, distance = findNearestCoin(rootPart)

            if not coinPart then
                setFarmStatus("Waiting for coins")
                task.wait(0.35)
                continue
            end

            tweenToCoin(rootPart, coin, coinPart, distance, token)
            task.wait(0.05)
        end
    end)
end

local function stopAutoCollect()
    debugTrace("AUTO_COLLECT_STOP", "token=" .. runToken)
    autoCollectEnabled = false
    runToken += 1
    stopCharacterMovement()
    setFarmStatus("Idle")
end

local function cleanup()
    scriptActive = false
    autoOpenBoxEnabled = false
    autoOpenToken += 1
    stopAutoCollect()
    stopCoinTracking()
    disconnectStateMonitoring()
end

local function accountTier()
    local access = environment.ReverbAccess or {}
    local tier = access.tier or environment.ReverbKeyTier

    if tier == "premium" then
        return "PREMIUM"
    end

    return "FREE"
end

local function start()
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end

    -- Prevent two copies of this script from farming at the same time.
    if type(environment.ReverbMM2Cleanup) == "function" then
        pcall(environment.ReverbMM2Cleanup)
    end

    startCoinTracking()
    readShopBalances()
    environment.ReverbMM2Cleanup = cleanup

    local loadLibrary, compileError = loadstring(game:HttpGet(REVERB_J_URL))

    if not loadLibrary then
        error("Reverb J failed to compile: " .. tostring(compileError))
    end

    local ReverbJ = loadLibrary()
    local Window = ReverbJ:CreateWindow({
        Game = SCRIPT.name,
        Tier = accountTier(),
        RememberSettings = savedConfig.remember_settings,
        ConfigName = SCRIPT.id,
    })

    notifyUser = function(message, duration)
        Window:Notify(message, duration or 4)
    end

    startStateMonitoring()

    local MainTab = Window:Tab("Main")
    local FarmingSection = MainTab:Section("Farming")
    local StatusSection = MainTab:Section("Session Status")
    farmStatusLabel = StatusSection:Label("Status: " .. farmStatus)
    sessionStatsLabel = StatusSection:Label("")
    refreshFarmDisplay()

    FarmingSection:Toggle(
        "Auto Collect Coins",
        savedConfig.auto_collect,
        function(enabled)
            stopAutoCollect()
            autoCollectEnabled = enabled
            savedConfig.auto_collect = enabled
            saveConfig()

            if enabled then
                startAutoCollect()
                Window:Notify("Auto Collect Coins enabled.", 3)
            else
                Window:Notify("Auto Collect Coins disabled.", 3)
            end
        end,
        SCRIPT.id .. "_enabled"
    )

    FarmingSection:Toggle(
        "Auto Reset When Full",
        savedConfig.auto_reset_full,
        function(enabled)
            autoResetWhenFull = enabled
            savedConfig.auto_reset_full = enabled
            saveConfig()
            resetRequested = false
            debugTrace("AUTO_RESET_TOGGLE", "enabled=" .. tostring(enabled))

            if enabled then
                refreshBagState()
            end
        end,
        SCRIPT.id .. "_auto_reset_full"
    )

    FarmingSection:Slider(
        "Tween Speed",
        18,
        35,
        tweenSpeed,
        function(value)
            tweenSpeed = value
            savedConfig.tween_speed = value
            saveConfig()
            debugTrace("SPEED_CHANGED", "value=" .. tostring(value))
        end,
        SCRIPT.id .. "_tween_speed"
    )

    local BoxSection = MainTab:Section("Auto Open Case")
    BoxSection:Dropdown(
        "Case Selector",
        CASE_NAMES,
        savedConfig.selected_box,
        function(value)
            savedConfig.selected_box = value
            saveConfig()
        end,
        SCRIPT.id .. "_selected_box"
    )
    BoxSection:Slider(
        "Delay Between Cases",
        2,
        30,
        savedConfig.box_open_delay,
        function(value)
            savedConfig.box_open_delay = value
            saveConfig()
        end,
        SCRIPT.id .. "_box_delay"
    )
    boxToggleControl = BoxSection:Toggle(
        "Auto Open Case",
        savedConfig.auto_open_box,
        function(enabled)
            autoOpenBoxEnabled = enabled
            savedConfig.auto_open_box = enabled
            saveConfig()

            if enabled then
                startAutoOpenBox()
            else
                stopAutoOpenBox()
            end
        end,
        SCRIPT.id .. "_auto_open_box"
    )

    local WebhookTab = Window:Tab("Webhook")
    local WebhookSection = WebhookTab:Section("Webhook Settings")
    local webhookInput = WebhookSection:Input(
        "Webhook URL",
        "Paste Discord webhook URL",
        function(value)
            savedConfig.webhook_url = normalizeWebhookUrl(value)
            saveConfig()

            if savedConfig.webhook_url ~= ""
                and not isDiscordWebhookUrl(savedConfig.webhook_url)
            then
                Window:Notify("That does not look like a Discord webhook URL.", 5)
            end
        end,
        SCRIPT.id .. "_webhook_url"
    )
    webhookInput:Set(savedConfig.webhook_url, true)

    -- ReverbJ may be cached by the executor, so also apply truncation to the
    -- live webhook TextBox here. This changes presentation only; the complete
    -- URL remains in Text and in savedConfig.
    task.defer(function()
        if savedConfig.webhook_url == "" then
            return
        end

        local roots = { LocalPlayer:FindFirstChild("PlayerGui") }
        local getHiddenUI = gethui
        if type(getHiddenUI) == "function" then
            local succeeded, hiddenUI = pcall(getHiddenUI)
            if succeeded and hiddenUI then
                table.insert(roots, hiddenUI)
            end
        else
            table.insert(roots, game:GetService("CoreGui"))
        end

        for _, root in ipairs(roots) do
            if root then
                for _, instance in ipairs(root:GetDescendants()) do
                    if instance:IsA("TextBox")
                        and instance.Text == savedConfig.webhook_url
                    then
                        instance.ClipsDescendants = true
                        instance.TextTruncate = Enum.TextTruncate.AtEnd
                        instance.Focused:Connect(function()
                            instance.TextTruncate = Enum.TextTruncate.None
                        end)
                        instance.FocusLost:Connect(function()
                            instance.TextTruncate = Enum.TextTruncate.AtEnd
                        end)
                        return
                    end
                end
            end
        end
    end)

    WebhookSection:Toggle(
        "Enable Webhook",
        savedConfig.webhook_enabled,
        function(enabled)
            savedConfig.webhook_enabled = enabled
            saveConfig()
        end,
        SCRIPT.id .. "_webhook_enabled"
    )
    WebhookSection:Toggle(
        "Timed Overall Updates",
        savedConfig.webhook_overall,
        function(enabled)
            savedConfig.webhook_overall = enabled
            lastStatusWebhookAt = os.clock()
            saveConfig()
        end,
        SCRIPT.id .. "_webhook_overall"
    )
    WebhookSection:Slider(
        "Update Interval (Minutes)",
        5,
        180,
        savedConfig.webhook_interval_minutes,
        function(value)
            savedConfig.webhook_interval_minutes = value
            lastStatusWebhookAt = os.clock()
            saveConfig()
        end,
        SCRIPT.id .. "_webhook_interval"
    )
    WebhookSection:Toggle(
        "Case Reward Updates",
        savedConfig.webhook_box_rewards,
        function(enabled)
            savedConfig.webhook_box_rewards = enabled
            saveConfig()
        end,
        SCRIPT.id .. "_webhook_box_rewards"
    )
    WebhookSection:Button("Send Overall Update Now", function()
        pcall(sampleCurrentBag)
        local sent = sendOverallWebhook(true)

        Window:Notify(
            sent
                and "Overall webhook update queued."
                or "Enable webhook and enter a valid URL first.",
            4
        )
    end)
    WebhookSection:Button("Send Test Webhook", function()
        local sent = sendWebhook(
            "test",
            "Reverb MM2 webhook connected",
            "Webhook notifications are configured correctly.",
            {
                { name = "Player", value = LocalPlayer.Name },
                { name = "Version", value = SCRIPT.version },
            }
        )

        Window:Notify(
            sent
                and "Test webhook queued."
                or "Enable webhook and enter a valid URL first.",
            4
        )
    end)

    local SettingsTab = Window:Tab("Settings")
    local RejoinSection = SettingsTab:Section("Rejoin")
    RejoinSection:Label(
        getTeleportQueue()
            and "Loader restore after teleport: Supported"
            or "Loader restore after teleport: Unsupported by this executor"
    )
    RejoinSection:Toggle(
        "Auto Rejoin After Kick",
        savedConfig.auto_rejoin,
        function(enabled)
            savedConfig.auto_rejoin = enabled
            saveConfig()
        end,
        SCRIPT.id .. "_auto_rejoin"
    )
    RejoinSection:Button("Test Rejoin Now", function()
        Window:Notify("Starting a rejoin test now.", 3)
        beginAutoRejoin("manual rejoin test", true)
    end)

    SettingsTab:Section("Preferences"):Toggle(
        "Remember Active Settings",
        savedConfig.remember_settings,
        function(enabled)
            savedConfig.remember_settings = enabled
            saveConfig()
            Window:SetRememberSettings(enabled)
        end,
        SCRIPT.id .. "_remember_settings"
    )

    local ChangelogTab = Window:Tab("Changelog")
    local V11Changelog = ChangelogTab:Section("V1.1 28th September 2026")
    V11Changelog:Label("Improved Auto Farm")
    V11Changelog:Label("Improved Auto Rejoin")
    V11Changelog:Label("Added Live Farming Stats")
    V11Changelog:Label("Improved Webhooks")
    V11Changelog:Label("Removed Summer Event Features")
    ChangelogTab:Section("V1.0.1 31st July 2026"):Label(
        "Webhook bug fixes"
    )
    ChangelogTab:Section("V1 25th July 2026"):Label(
        "Initial release with 18 features"
    )

    task.spawn(function()
        while scriptActive do
            pcall(sampleCurrentBag)
            pcall(refreshBagState)
            pcall(refreshFarmDisplay)
            task.wait(1)
        end
    end)

    task.spawn(function()
        while scriptActive do
            pcall(updateTimedWebhook)
            task.wait(5)
        end
    end)

    if autoCollectEnabled then
        startAutoCollect()
        debugTrace("RESTORED_AUTO_START", "auto collect resumed from saved settings")
    end

    if autoOpenBoxEnabled then
        startAutoOpenBox()
    end

    print("[Reverb] " .. SCRIPT.name .. " is ready.")
end

local succeeded, startupError = xpcall(start, function(message)
    return debug.traceback(tostring(message), 2)
end)

if not succeeded then
    cleanup()
    error(startupError, 0)
end
