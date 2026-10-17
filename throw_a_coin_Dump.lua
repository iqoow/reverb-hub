-- V1.1 release authorized by Jenson, 11 October 2026.
-- Evidence: Potassium World 4 save and Jenson's in-game feature verification.
local SCRIPT = { id = "throw_a_coin", name = "Throw a Coin", version = "V1.1", updated = "11 October 2026", author = "Reverb" }
local REVERB_J_URL =
    "https://raw.githubusercontent.com/rbxreverb/ReverbJ/refs/heads/main/source.lua?v=remember-settings-20260812"
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local environment = (getgenv and getgenv()) or _G
local Runtime, token = {}, {}
local destroyed = false
local connections, controls = {}, {}
local enabled = {}
local events, progression, world
local owned, levels, quests = nil, nil, nil
local equipped
local pending = {}
local throwPending
local throwGeneration = 0
local throwWorker = false
local nativeThrowUntil = 0
local nextThrowAt = 0
local nextSell = 0
local purchaseState, equipState, upgradeState = nil, nil, {}
local questRequests = {}
local selectedUpgrades = { ["Luck Multiplier"] = true, ["Value Multiplier"] = true, ["Throw Speed"] = true }
local antiKickScript, antiKickWasEnabled

local function isActive()
    return not destroyed and environment.ReverbLoadedScripts
        and environment.ReverbLoadedScripts[SCRIPT.id] == token
end

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function fire(name, ...)
    if not isActive() then return false end
    local args = table.pack(...)
    local ok, message = pcall(function()
        if name == "EquipCoin" then
            -- CoinShopClient fires this local bindable; ThrowCoinClient owns equipping.
            events[name]:Fire(table.unpack(args, 1, args.n))
        else
            events[name]:FireServer(table.unpack(args, 1, args.n))
        end
    end)
    if not ok then warn("[Reverb] " .. name .. " failed: " .. tostring(message)) end
    return ok
end

local function disableGameRejoin()
    local playerScripts = player:WaitForChild("PlayerScripts", 10)
    local scripts = playerScripts and playerScripts:WaitForChild("Scripts", 10)
    local scriptInstance = scripts and scripts:WaitForChild("AntiKickScript", 10)
    if not scriptInstance or not scriptInstance:IsA("LocalScript") then
        warn("[Reverb] Game auto-rejoin script not found; its timer remains unchanged.")
        return
    end
    antiKickScript = scriptInstance
    antiKickWasEnabled = scriptInstance.Enabled
    scriptInstance.Enabled = false
    -- AntiKickScript's loop sends AntiKickReconnect after 900 idle seconds.
    -- Clear an already-entered AFK-safe state using its normal exit request.
    local remote = events.SetAFKSafe
    if remote then fire("SetAFKSafe", false) end
    local gui = player:FindFirstChildOfClass("PlayerGui")
    for _, name in ipairs({ "UiFolder", "Main", "HUD", "AFKSafe" }) do
        gui = gui and gui:FindFirstChild(name)
    end
    if gui and gui:IsA("GuiObject") then gui.Visible = false end
end

local function notify(message)
    warn("[Reverb] " .. message)
    if Runtime.Window then Runtime.Window:Notify(message, 5) end
end

local function balance(currency)
    local stats = player:FindFirstChild("leaderstats")
    local value = stats and stats:FindFirstChild(currency or "Cash")
    return value and tonumber(value.Value) or 0
end

local function bestOwnedCoin()
    local best, luck = nil, -math.huge
    for name, count in pairs(owned or {}) do
        local config = progression.Coins[name]
        if count > 0 and config and config.Luck > luck then
            best, luck = name, config.Luck
        end
    end
    return best, luck
end

local function activeCoin()
    if equipped and owned and (owned[equipped] or 0) > 0 then return equipped end
    return bestOwnedCoin()
end

local function sellableItem()
    for _, container in pairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") and item:GetAttribute("Favorited") ~= true
                and progression.Items[item:GetAttribute("ItemId") or item.Name] then
                return true
            end
        end
    end
    return false
end

local function autoSell()
    if enabled.Sell and os.clock() >= nextSell and sellableItem() then
        nextSell = os.clock() + 1
        -- Preserve the native SellAll policy; never remove favorites or sell individually.
        fire("SellAll")
    end
end

local function autoEquip()
    if not enabled.Equip or not owned or throwPending then return end
    local best = bestOwnedCoin()
    if not best or best == equipped then equipState = nil return end
    if equipState == best then return end
    if fire("EquipCoin", best) then equipState = best end
end

local function autoBuy()
    if not enabled.Buy or not owned then return end
    local cash = balance()
    local _, currentLuck = bestOwnedCoin()
    local best, bestLuck = nil, currentLuck
    for name, config in pairs(progression.Coins) do
        local cost = tonumber(config.Cost) or 0
        local lock = tonumber(ReplicatedStorage:GetAttribute(progression:CoinLockAttribute(name))) or 0
        if not owned[name] and cost > 0 and cost <= cash
            and (tonumber(config.World) or 1) <= world and lock <= os.time()
            and config.Luck > bestLuck then
            best, bestLuck = name, config.Luck
        end
    end
    if not best then return end
    local state = best .. ":" .. tostring(cash)
    if purchaseState == state then return end
    if pending.Buy then return end
    if fire("BuyCoin", best) then
        purchaseState = state
        pending.Buy = { name = best, at = os.clock() }
    end
end

local UPGRADE_NAMES = { "Luck Multiplier", "Value Multiplier", "Throw Speed" }
local function autoUpgrade(name)
    if not enabled.Upgrade or not selectedUpgrades[name] or not levels or pending[name] then return end
    local config = progression.Upgrades[name]
    local level = tonumber(levels[name])
    if not config or not level or world < (config.World or 1) then return end
    if name == "Luck Multiplier" and player:GetAttribute("PaidRandomRestricted") ~= false then return end
    local maximum = progression:GetUpgradeMaxLevel(name)
    if level >= maximum then return end
    local cash = balance(config.Currency)
    local cost = progression:GetUpgradeCost(name, level)
    if cost <= 0 or cash < cost then return end
    local quantity = 1
    -- The client exposes only these two bulk tiers; retain its tutorial restriction.
    if player:GetAttribute("tutorial") ~= true then
        for _, tier in ipairs({ 10, 100 }) do
            if level + tier > maximum then break end
            local total = 0
            for offset = 0, tier - 1 do total += progression:GetUpgradeCost(name, level + offset) end
            if total > cash then break end
            quantity = tier
        end
    end
    local state = tostring(level) .. ":" .. tostring(cash) .. ":" .. tostring(quantity)
    if upgradeState[name] == state then return end
    if fire("RequestUpgrade", name, quantity) then
        upgradeState[name] = state
        pending[name] = { level = level, at = os.clock() }
    end
end

local function autoClaim()
    if not enabled.Quests or type(quests) ~= "table" or type(quests.Kinds) ~= "table" then return end
    for _, kind in ipairs({ "Daily", "Weekly", "Monthly" }) do
        local tier = quests.Kinds[kind]
        for index, quest in ipairs(tier and tier.Tasks or {}) do
            local target = tonumber(quest.Target)
            if not quest.Claimed and target and target > 0
                and (tonumber(quest.Progress) or 0) >= target then
                local key = kind .. ":" .. tostring(tier.PeriodEnd) .. ":" .. tostring(index)
                if not questRequests[key] and fire("ClaimQuest", kind, index) then
                    questRequests[key] = true
                end
            end
        end
    end
end

-- Exact spread and hand order from ThrowCoinClient.spreadEndPositions,
-- assignSpotsToHands and extraSpotList. Cosmetic arcs are not reproduced.
local function landingSpots(center, direction, count)
    if count == 1 then return center, nil end
    local perpendicular = Vector3.new(-direction.Z, 0, direction.X)
    local spots = {}
    local function lane(row, size)
        local result = {}
        local step = size > 1 and math.min(4, 4 / (size - 1)) or 4
        for i = 1, size do
            result[i] = center + perpendicular * (row * 3)
                + direction * (size > 1 and (i - (size + 1) / 2) * step or 0)
        end
        return result
    end
    local function append(values, first, last)
        for i = first or 1, last or #values do table.insert(spots, values[i]) end
    end
    if count == 8 then
        for _, row in ipairs({ 1, 1 / 3, -1 / 3, -1 }) do append(lane(row, 2)) end
    elseif count % 3 == 0 then
        local size = count // 3
        local middle = lane(0, size)
        local split = math.ceil(count / 2) - size
        append(lane(1, size))
        append(middle, 1, split)
        append(lane(-1, size))
        append(middle, split + 1)
    else
        append(lane(1, math.ceil(count / 2)))
        append(lane(-1, count - math.ceil(count / 2)))
    end
    local halfway = math.ceil(count / 2)
    local extra = { spots[1] }
    for i = 2, halfway do table.insert(extra, spots[i]) end
    for i = halfway + 2, count do table.insert(extra, spots[i]) end
    return spots[halfway + 1], extra
end

local function pauseThrow(message)
    enabled.Throw = false
    throwGeneration += 1
    notify(message .. " Toggle Auto Throw Coin on to retry.")
    if controls.Throw and type(controls.Throw.Set) == "function" then controls.Throw:Set(false) end
end

local function recoverThrow()
    throwPending = nil
    local config = progression.Upgrades["Throw Speed"]
    local speed = tonumber(player:GetAttribute("ThrowSpeedLevel")) or 0
    -- The native client's cooldown calculation uses this 3-second baseline.
    -- Rejection does not identify its cause; allow busy state to clear before retrying.
    nextThrowAt = os.clock() + math.max(0.5, 3 - (config.ServerDebounceReduction or 0) * speed)
end

local function throwCoin(generation)
    if throwPending or os.clock() < math.max(nativeThrowUntil, nextThrowAt) or not owned then return end
    local name = activeCoin()
    if not name then return end
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local waypoints = workspace:FindFirstChild("Waypoints")
    local target = waypoints and waypoints:FindFirstChild("CoinTarget")
    if not root or not humanoid or humanoid.Health <= 0 or humanoid.Sit
        or not target or not target:IsA("BasePart") then return end
    if character:FindFirstChildOfClass("Tool") then return end
    if (root.Position - target.Position).Magnitude > 40 then
        -- ThrowCoinClient.teleportIntoThrowRange uses a 35-stud sphere.
        local horizontal = Vector3.new(root.Position.X - target.Position.X, 0, root.Position.Z - target.Position.Z)
        local direction = horizontal.Magnitude > 0.05 and horizontal.Unit or Vector3.new(0, 0, 1)
        local height = root.Position.Y - target.Position.Y
        local radiusSquared = 1225 - height * height
        local radius = radiusSquared > 1 and math.sqrt(radiusSquared) or 1
        local position = target.Position + direction * radius + Vector3.new(0, height, 0)
        character:PivotTo(CFrame.lookAt(position, Vector3.new(target.Position.X, position.Y, target.Position.Z)))
        return -- Let the character position settle before starting the next throw.
    end
    local delta = Vector3.new(root.Position.X, target.Position.Y, root.Position.Z) - target.Position
    local direction = delta.Magnitude > 0 and delta.Unit or Vector3.new(0, 0, 1)
    local center = target.Position + direction * progression:GetLandOffset(world, false)
    local count = math.max(1, math.floor(progression:GetThrowCoinCount(player)))
    local position, extra = landingSpots(center, direction, count)
    environment.ReverbThrowACoinSequence = (environment.ReverbThrowACoinSequence or 0) + 1
    local id = environment.ReverbThrowACoinSequence
    local request = { id = id, at = os.clock(), generation = generation }
    throwPending = request
    if not fire("CoinThrow", name, position, extra) then
        throwPending = nil
        pauseThrow("CoinThrow failed.")
        return
    end
    local config = progression.Upgrades["Throw Speed"]
    local speed = tonumber(player:GetAttribute("ThrowSpeedLevel")) or 0
    local arc = math.max(config.ArcFloor, config.ArcBaseline - config.ArcReduction * speed)
    task.wait(arc)
    if not isActive() or not enabled.Throw or generation ~= throwGeneration or throwPending ~= request then return end
    -- 3 is the current manual timing bar's maximum (ratioToLuck), replacing old 2.
    if not fire("CoinLanded", 3, position, name, extra, tonumber(player:GetAttribute("DesiredLuck")), id) then
        throwPending = nil
        pauseThrow("CoinLanded failed.")
    end
end

local function startThrowWorker()
    if throwWorker then return end
    throwWorker = true
    task.spawn(function()
        while isActive() and enabled.Throw do
            local ok, message = pcall(throwCoin, throwGeneration)
            if not ok then pauseThrow("Auto Throw failed: " .. tostring(message)) end
            if throwPending and os.clock() - throwPending.at >= 12 then
                recoverThrow()
            end
            task.wait(0.1)
        end
        throwWorker = false
    end)
end

local function setFeature(key, value)
    enabled[key] = value == true
    if key == "Throw" then
        throwGeneration += 1
        if enabled.Throw then startThrowWorker() end
    elseif key == "Buy" then purchaseState = nil
    elseif key == "Equip" then equipState = nil
    elseif key == "Quests" then
        questRequests = {}
        if enabled.Quests then fire("SyncQuests") end
    elseif key == "Upgrade" then table.clear(upgradeState) end
end

local function queueLoaderAfterTeleport()
    local queueFunction
    pcall(function()
        queueFunction = queue_on_teleport or (syn and syn.queue_on_teleport)
            or (fluxus and fluxus.queue_on_teleport)
    end)
    if type(queueFunction) ~= "function" then return end
    pcall(queueFunction, [[
local environment = (getgenv and getgenv()) or _G
pcall(function()
    if readfile and isfile and isfile("reverb_key.txt") then
        environment.script_key = readfile("reverb_key.txt")
    end
end)
loadstring(game:HttpGet("https://loader.rbxreverb.com/api/loader?source=teleport"))()
]])
end

function Runtime.Destroy()
    if destroyed then return end
    destroyed = true
    throwGeneration += 1
    table.clear(enabled)
    for _, connection in ipairs(connections) do connection:Disconnect() end
    table.clear(connections)
    if antiKickScript and antiKickScript.Parent then
        pcall(function() antiKickScript.Enabled = antiKickWasEnabled end)
    end
    antiKickScript = nil
    if environment.ReverbLoadedScripts and environment.ReverbLoadedScripts[SCRIPT.id] == token then
        environment.ReverbLoadedScripts[SCRIPT.id] = nil
    end
    if environment.ReverbScriptInstances and environment.ReverbScriptInstances[SCRIPT.id] == Runtime then
        environment.ReverbScriptInstances[SCRIPT.id] = nil
    end
    if environment.ReverbCurrentScript and environment.ReverbCurrentScript.runtime == Runtime then
        environment.ReverbCurrentScript = nil
    end
    if Runtime.Library then pcall(function() Runtime.Library:Destroy() end) end
    Runtime.Library, Runtime.Window = nil, nil
end

local function start()
    if not game:IsLoaded() then game.Loaded:Wait() end
    local assets = ReplicatedStorage:WaitForChild("Assets", 10)
    assert(assets, "Throw a Coin Assets missing")
    local modules = assets:WaitForChild("Modules", 10)
    local source = modules and modules:WaitForChild("ProgressionModule", 10)
    assert(source, "Throw a Coin ProgressionModule missing")
    local ok, result = pcall(require, source)
    assert(ok and type(result) == "table", "Could not load Throw a Coin progression: " .. tostring(result))
    progression = result
    assert(progression:IsWorldPlaceId(game.PlaceId) and not progression:IsTradeWorld(game.PlaceId), "Join a Throw a Coin farming world")
    world = progression:GetWorldForPlaceId(game.PlaceId)
    events = {}
    local folder = assets:WaitForChild("Events", 10)
    assert(folder, "Throw a Coin Events missing")
    for _, name in ipairs({ "CoinThrow", "CoinLanded", "ThrowReady", "ThrowRejected", "SellAll", "BuyCoin", "EquipCoin", "SyncCoins", "SyncUpgrades", "RequestUpgrade", "SyncQuests", "ClaimQuest", "SyncLoadout" }) do
        local remote = folder:WaitForChild(name, 10)
        local class = name == "EquipCoin" and "BindableEvent" or "RemoteEvent"
        assert(remote and remote:IsA(class), name .. " " .. class .. " missing")
        events[name] = remote
    end
    environment.ReverbLoadedScripts = environment.ReverbLoadedScripts or {}
    environment.ReverbScriptInstances = environment.ReverbScriptInstances or {}
    local previous = environment.ReverbScriptInstances[SCRIPT.id]
    if previous and type(previous.Destroy) == "function" then pcall(previous.Destroy) end
    environment.ReverbLoadedScripts[SCRIPT.id] = token
    environment.ReverbScriptInstances[SCRIPT.id] = Runtime
    environment.ReverbScriptReadyReported = false
    queueLoaderAfterTeleport()

    connect(events.SyncCoins.OnClientEvent, function(names)
        if not isActive() or type(names) ~= "table" then return end
        owned = {}
        for _, name in ipairs(names) do owned[name] = (owned[name] or 0) + 1 end
        if pending.Buy and owned[pending.Buy.name] then pending.Buy = nil end
    end)
    connect(events.SyncLoadout.OnClientEvent, function(loadout)
        if isActive() and type(loadout) == "table" then equipped = loadout.coin end
    end)
    local luckChanged = folder:FindFirstChild("LuckChanged")
    if luckChanged and luckChanged:IsA("BindableEvent") then
        connect(luckChanged.Event, function(_, name) if isActive() then equipped = name end end)
    end
    connect(events.SyncUpgrades.OnClientEvent, function(values)
        if not isActive() or type(values) ~= "table" then return end
        levels = values
        for _, name in ipairs(UPGRADE_NAMES) do
            if pending[name] and tonumber(values[name]) ~= pending[name].level then pending[name] = nil end
        end
    end)
    connect(events.SyncQuests.OnClientEvent, function(state)
        if isActive() then quests = state end
    end)
    connect(events.ThrowReady.OnClientEvent, function(id)
        id = tonumber(id)
        if not isActive() or not id then return end
        environment.ReverbThrowACoinSequence = math.max(environment.ReverbThrowACoinSequence or 0, id)
        if throwPending and throwPending.id == id then
            throwPending = nil
            local config = progression.Upgrades["Throw Speed"]
            local speed = tonumber(player:GetAttribute("ThrowSpeedLevel")) or 0
            nextThrowAt = os.clock() + math.max(0, 0.5 - (config.ClientDebounceReduction or 0) * speed)
        end
        nativeThrowUntil = 0
    end)
    connect(events.ThrowRejected.OnClientEvent, function()
        if isActive() and throwPending then
            recoverThrow()
        end
    end)
    local committed = folder:FindFirstChild("ThrowCommitted")
    if committed and committed:IsA("BindableEvent") then
        connect(committed.Event, function()
            if isActive() then
                nativeThrowUntil = os.clock() + 12
                if enabled.Throw then pauseThrow("A native throw started. Turn off the game's Auto Throw before retrying.") end
            end
        end)
    end

    local loadLibrary, compileError = loadstring(game:HttpGet(REVERB_J_URL))
    assert(loadLibrary, "Reverb J failed to compile: " .. tostring(compileError))
    local library = loadLibrary()
    Runtime.Library = library
    local access = environment.ReverbAccess or {}
    local tier = tostring(access.tier or environment.ReverbKeyTier or "free"):lower()
    local Window = library:CreateWindow({ Game = SCRIPT.name, Tier = tier == "premium" and "PREMIUM" or "FREE", RememberSettings = false, ConfigName = "ThrowACoin" })
    Runtime.Window = Window
    local setAFKSafe = folder:FindFirstChild("SetAFKSafe")
    if setAFKSafe and setAFKSafe:IsA("RemoteEvent") then events.SetAFKSafe = setAFKSafe end
    disableGameRejoin()
    local Main = Window:Tab("Main"):Section("Autofarm")
    for _, feature in ipairs({
        { "Throw", "Auto Throw Coin", "AutoThrowCoin" },
        { "Sell", "Auto Sell All", "AutoSellAll" },
        { "Upgrade", "Auto Upgrade", "AutoUpgrade" },
        { "Buy", "Auto Buy Next Best Coin", "AutoBuyNextBestCoin" },
        { "Equip", "Auto Equip Best Coin", "AutoEquipBestCoin" },
        { "Quests", "Auto Claim Completed Quests", "AutoClaimCompletedQuests" },
    }) do
        local key = feature[1]
        if key == "Upgrade" then
            Main:MultiDropdown("Upgrades", UPGRADE_NAMES, UPGRADE_NAMES, function(values)
                table.clear(selectedUpgrades)
                for _, name in ipairs(values) do selectedUpgrades[name] = true end
                table.clear(upgradeState)
            end, "SelectedUpgrades")
        end
        controls[key] = Main:Toggle(feature[2], false, function(value) setFeature(key, value) end, feature[3])
    end
    local Settings = Window:Tab("Settings")
    Settings:Section("Preferences"):Toggle("Remember active settings", false, function(value)
        Window:SetRememberSettings(value)
    end, "RememberActiveSettings")
    Settings:Section("Script"):Button("Unload Throw a Coin", Runtime.Destroy)
    local Changelog = Window:Tab("Changelog")
    local Update = Changelog:Section("V1.1 11th October 2026")
    Update:Label("Improved Existing Features")
    Update:Label("Added Auto Equip Best Coin")
    Update:Label("Added Auto Claim Completed Quests")
    Changelog:Section("V1 1st August 2026"):Label("Script Release")
    environment.ReverbCurrentScript = { metadata = SCRIPT, library = library, window = Window, runtime = Runtime }
    for _, name in ipairs({ "SyncCoins", "SyncUpgrades", "SyncQuests", "SyncLoadout" }) do fire(name) end
    task.spawn(function()
        while isActive() do
            local succeeded, message = pcall(function()
                for name, request in pairs(pending) do
                    if os.clock() - request.at >= 5 then pending[name] = nil end
                end
                autoSell()
                autoEquip()
                -- Serialize spending until the purchase/upgrade state changes or times out.
                if next(pending) == nil then
                    autoBuy()
                    for _, name in ipairs(UPGRADE_NAMES) do
                        if next(pending) == nil then autoUpgrade(name) end
                    end
                end
                autoClaim()
            end)
            if not succeeded then warn("[Reverb] Automation failed: " .. tostring(message)) end
            task.wait(0.5)
        end
    end)
    print("[Reverb] Throw a Coin V1.1 ready; world " .. tostring(world))
end

local succeeded, startupError = xpcall(start, function(message) return debug.traceback(tostring(message), 2) end)
if not succeeded then Runtime.Destroy() error(startupError, 0) end
