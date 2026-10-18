-- +1 Stone Skipping: existing features confirmed by Jenson, 10 October 2026.
-- V1 release authorized by Jenson on 11 October 2026.
-- Evidence: Potassium save for place 111543903102439, inspected 10 October 2026.
-- Hud.bind exposes GameplayController.beginThrow through the Throw input callback.
-- Calling that existing function preserves request IDs, activity/launch-zone checks,
-- cooldowns, modal checks, timeout recovery and special-throw presentation.

local SCRIPT = { id = "StoneSkipping", name = "+1 Stone Skipping" }
local REVERB_J_URL =
    "https://raw.githubusercontent.com/rbxreverb/ReverbJ/refs/heads/main/source.lua?v=remember-settings-20260812"
local environment = (getgenv and getgenv()) or _G
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local token = {}
local destroyed = false
local autoThrow = false
local enabled = { Train = false, Stones = false, Trails = false, Gifts = false, Rebirth = false, Hatch = false, Pets = false }
local controls = {}
local hooks
local client
local balance, worlds, worldMap, launchZone, stoneCatalog
local network
local selectedEgg = "Cheapest in current world"
local trainingStand
local nextMove = 0
local nextRequest = 0
local nextUpgrade = 0
local nextTrail = 0
local nextGift = 0
local giftRewards
local giftCycle
local giftPending = {}
local nextRebirth = 0
local nextPets = 0
local petSignature
local hatchButton, requestHatch
local boundButton
local beginThrow
local Runtime = {}
local readUpvalues = getupvalues or (debug and debug.getupvalues)

-- ===== СИСТЕМА ФИДБЕКА =====
local function addFeedbackSystem(window, library, gameName)
    local Players = game:GetService("Players")
    local HttpService = game:GetService("HttpService")
    local LocalPlayer = Players.LocalPlayer
    local WEBHOOK_URL = "https://reverbhook.carlolarp333.workers.dev"
    local lastFeedbackTime = 0
    
    local FeedbackTab = window:Tab("Feedback", "message-square")
    local Section = FeedbackTab:Section("Feedback Sender")
    
    local anonymous = false
    local msgBox = nil

    local function notifyUser(title, text)
        window:Notify(title .. ": " .. text, 4)
    end

    local parentObj = Section.Frame or Section.Container or Section.InnerFrame
    
    if parentObj then
        local title = Instance.new("TextLabel")
        title.Text = "FEEDBACK SENDER"
        title.Size = UDim2.new(1, 0, 0, 30)
        title.BackgroundTransparency = 1
        title.TextColor3 = Color3.fromRGB(255, 255, 255)
        title.Font = Enum.Font.GothamBold
        title.TextSize = 16
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Position = UDim2.new(0, 10, 0, 5)
        title.Parent = parentObj
        
        msgBox = Instance.new("TextBox")
        msgBox.Size = UDim2.new(1, -20, 0, 80)
        msgBox.Position = UDim2.new(0, 10, 0, 40)
        msgBox.PlaceholderText = "Describe your issue or suggestion..."
        msgBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        msgBox.TextColor3 = Color3.fromRGB(255, 255, 255)
        msgBox.Font = Enum.Font.Gotham
        msgBox.TextSize = 14
        msgBox.TextWrapped = true
        msgBox.TextXAlignment = Enum.TextXAlignment.Left
        msgBox.TextYAlignment = Enum.TextYAlignment.Top
        msgBox.ClearTextOnFocus = false
        msgBox.Parent = parentObj
    end

    Section:Toggle("Send Anonymously", false, function(val) anonymous = val end)

    Section:Button("Submit Feedback", function()
        local message = msgBox and msgBox.Text or ""
        if message == "" then notifyUser("Feedback", "Please enter a message.") return end
        if string.find(message, "@everyone", 1, true) or string.find(message, "@here", 1, true) then notifyUser("Error", "Cannot send messages containing @everyone or @here.") return end
        local currentTime = os.clock()
        if currentTime - lastFeedbackTime < 15 then
            notifyUser("Cooldown", string.format("Please wait %d seconds before sending feedback again.", math.ceil(15 - (currentTime - lastFeedbackTime))))
            return
        end
        
        local avatarUrl = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. LocalPlayer.UserId .. "&width=420&height=420&format=png"
        local createdDate = os.date("%Y-%m-%d", os.time() - LocalPlayer.AccountAge * 86400)
        
        local embed = {
            title = "📬 New Feedback - " .. gameName,
            description = message,
            color = anonymous and 0x808080 or 0x00FF00,
            fields = {},
            timestamp = DateTime.now():ToIsoDate()
        }
        
        if not anonymous then
            table.insert(embed.fields, { name = "USER ID", value = tostring(LocalPlayer.UserId), inline = true })
            table.insert(embed.fields, { name = "USERNAME", value = LocalPlayer.Name, inline = true })
            table.insert(embed.fields, { name = "DISPLAY NAME", value = LocalPlayer.DisplayName, inline = true })
            table.insert(embed.fields, { name = "CREATED", value = createdDate, inline = true })
            table.insert(embed.fields, { name = "STATUS", value = LocalPlayer.MembershipType.Name, inline = true })
            embed.thumbnail = { url = avatarUrl }
        else
            embed.description = "**[ANONYMOUS]**\n" .. message
        end
        
        local payload = HttpService:JSONEncode({
            username = "Reverb Feedback",
            embeds = { embed }
        })
        
        task.spawn(function()
            local request = request or http_request or syn.request
            if request then
                local success, err = pcall(function()
                    request({
                        Url = WEBHOOK_URL,
                        Method = "POST",
                        Headers = { ["Content-Type"] = "application/json" },
                        Body = payload
                    })
                end)
                if success then
                    lastFeedbackTime = os.clock()
                    notifyUser("Success", "Feedback sent successfully!")
                    if msgBox then msgBox.Text = "" end
                else
                    notifyUser("Error", "Failed to send feedback: " .. tostring(err))
                end
            else
                notifyUser("Error", "HTTP requests are not supported by your executor.")
            end
        end)
    end)
end
-- ===== КОНЕЦ СИСТЕМЫ ФИДБЕКА =====

local function isActive()
    return not destroyed
        and environment.ReverbLoadedScripts
        and environment.ReverbLoadedScripts[SCRIPT.id] == token
end

local function throwButton()
    local current = Players.LocalPlayer:FindFirstChild("PlayerGui")
    for _, name in ipairs({ "SkippingHUD", "HUD", "Bottom", "Progression", "Throw" }) do
        current = current and current:FindFirstChild(name)
    end
    return current and current:IsA("GuiButton") and current or nil
end

local function bindThrow(button)
    -- Inspect only the confirmed Throw signal; no global function scan or indices.
    for _, connection in ipairs(getconnections(button.InputBegan)) do
        local callback = connection.Function
        if type(callback) == "function" then
            for _, value in pairs(readUpvalues(callback)) do
                if type(value) == "table"
                    and type(rawget(value, "BeginThrow")) == "function"
                    and type(rawget(value, "ToggleAutoWins")) == "function"
                then
                    boundButton = button
                    beginThrow = value.BeginThrow
                    hooks = value
                    -- AutoWins' initialized callback table exposes a fresh GetState.
                    -- Read the closure; never toggle the game's paid AutoWins feature.
                    for _, runtime in pairs(readUpvalues(value.ToggleAutoWins)) do
                        if type(runtime) == "table" and type(rawget(runtime, "Toggle")) == "function" then
                            for _, callbacks in pairs(readUpvalues(runtime.Toggle)) do
                                if type(callbacks) == "table"
                                    and type(rawget(callbacks, "GetState")) == "function"
                                    and type(rawget(callbacks, "IsThrowBusy")) == "function"
                                    and type(rawget(callbacks, "IsModalOpen")) == "function" then
                                    client = callbacks
                                    return
                                end
                            end
                        end
                    end
                    error("The game's initialized state callbacks were not accessible. Wait for loading to finish.")
                end
            end
        end
    end
    error("The game's initialized Throw callback was not accessible. Wait for the game to finish loading and try again.")
end

local function characterParts()
    local character = Players.LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if root and humanoid and humanoid.Health > 0 then return root, humanoid end
end

local function sendAction(callback)
    if os.clock() < nextRequest then return false end
    nextRequest = os.clock() + balance.Network.RequestInterval
    callback()
    return true
end

local function moveTo(part, offsetZ)
    local root, humanoid = characterParts()
    if not root or not part or not part:IsA("BasePart") or os.clock() < nextMove then return false end
    local height = part.Size.Y / 2 + launchZone.StandingHeight(root, humanoid)
    humanoid:MoveTo(root.Position)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    root.CFrame = part.CFrame * CFrame.new(0, height, offsetZ or 0)
    nextMove = os.clock() + 0.75
    return true
end

local function nearStand(part)
    local root = characterParts()
    if not root or not part or not part.Parent then return false end
    local offset = part.CFrame:PointToObjectSpace(root.Position)
    return math.abs(offset.X) <= 3 and math.abs(offset.Z) <= 3
        and offset.Y >= 0 and offset.Y <= 8
end

local function launchPart()
    local model = worldMap.GetModel(Players.LocalPlayer)
    return model and model:FindFirstChild("LaunchZone")
end

local function stopPractice()
    return sendAction(function() network:FireServer("StopPractice", nil) end)
end

local function leaveTraining()
    if not trainingStand then return end
    local state = client and client.GetState()
    -- Leave the magnet area too, so proximity does not restart training.
    if state and (state.Activity == "Practice" or nearStand(trainingStand)) then
        stopPractice()
        nextMove = 0
        moveTo(launchPart())
    end
    trainingStand = nil
end

local function setEnabled(name, value)
    if name == "Throw" then autoThrow = value else enabled[name] = value end
    local control = controls[name]
    if control and control.Value ~= value then
        -- UI instances may be inaccessible from a game callback's capability
        -- context. A redraw failure must never stop state changes or the loop.
        local ok, failure = pcall(function() control:Set(value, true) end)
        if not ok then
            control.Value = value
            warn("[Reverb/StoneSkipping/UI] " .. name .. " redraw failed: " .. tostring(failure))
        end
    end
end

local function selectMode(name, value)
    if value then
        for _, other in ipairs({ "Throw", "Train", "Hatch" }) do
            if other ~= name then
                if other == "Train" and enabled.Train then leaveTraining() end
                setEnabled(other, false)
            end
        end
    elseif name == "Train" then
        leaveTraining()
    end
    setEnabled(name, value)
    nextMove = 0
end

local function bestTraining(state, config, folder)
    local best, bestBonus = nil, -math.huge
    local rebirths = state.Rebirths + (state.BonusRebirths or 0)
    local function consider(name, bonus, unlocked)
        local model = folder and folder:FindFirstChild(name)
        local stand = model and model:FindFirstChild("TrainingStand")
        if unlocked and stand and stand:IsA("BasePart") and bonus > bestBonus then
            best, bestBonus = stand, bonus
        end
    end
    for name, bonus in pairs(config.Practice.ZoneBonuses) do
        local unlocked
        if balance.TrainingPasses[name] then
            unlocked = state.OwnedTrainingZones[name] == true
        else
            local requirement = config.Practice.ZoneRequiredRebirths[name]
            unlocked = type(requirement) == "number" and rebirths >= requirement
        end
        consider(name, bonus, unlocked)
    end
    local now = workspace:GetServerTimeNow()
    local weather = workspace:GetAttribute("WeatherEvent")
    local starts, ends = workspace:GetAttribute("WeatherStartsAt"), workspace:GetAttribute("WeatherEndsAt")
    for name, event in pairs(config.Practice.EventZones or {}) do
        local active = weather == event.Weather and type(starts) == "number"
            and type(ends) == "number" and starts <= now and now < ends
        consider(name, config.Practice.ZoneBonuses[event.BonusOf] or 0, active)
    end
    return best
end

local function bestStones(state, config)
    local owned = state.OwnedStones
    local all = stoneCatalog.All(balance.Stones, balance.PremiumStones)
    local bestOwned, ownedPower = nil, -math.huge
    for _, stone in ipairs(all) do
        if owned[stone.Id] then
            local power = stoneCatalog.Multiplier(stone, balance.Stones, owned)
            if power > ownedPower or (power == ownedPower and state.EquippedStone == stone.Id) then
                bestOwned, ownedPower = stone, power
            end
        end
    end
    local allowed = {}
    for _, id in ipairs(config.StoneIds) do allowed[id] = true end
    local buy, buyPower = nil, -math.huge
    for _, stone in ipairs(balance.Stones) do
        if allowed[stone.Id] and not owned[stone.Id] and not stone.ProductId
            and stone.Price <= state.Wins and stone.Multiplier > buyPower then
            buy, buyPower = stone, stone.Multiplier
        end
    end
    if buy then
        -- A normal upgrade may also strengthen an owned best-stone relic, even
        -- when the normal stone alone is weaker than that relic's current power.
        local prospective = table.clone(owned)
        prospective[buy.Id] = true
        local resultingPower = -math.huge
        for _, stone in ipairs(all) do
            if prospective[stone.Id] then
                local power = stoneCatalog.Multiplier(stone, balance.Stones, prospective)
                resultingPower = math.max(resultingPower, power)
            end
        end
        if resultingPower <= ownedPower then buy = nil end
    end
    return bestOwned, buy
end

local function petsChanged(state)
    local signature = { tostring(state.PetEquipLimit) }
    for _, pet in ipairs(state.Pets) do
        signature[#signature + 1] = pet.Id .. ":" .. pet.PetId .. ":" .. tostring(pet.Power)
    end
    for _, id in ipairs(state.EquippedPets) do signature[#signature + 1] = "equip:" .. id end
    return table.concat(signature, "|")
end

local function eggOptions()
    local options, seen, premium = { "Cheapest in current world" }, {}, {}
    for _, offer in ipairs(balance.PremiumEggs) do premium[offer.EggId] = true end
    for _, world in ipairs(worlds.Definitions) do
        for _, id in ipairs(world.EggIds) do
            if not premium[id] and not seen[id] then
                seen[id] = true
                options[#options + 1] = id
            end
        end
    end
    return options, premium
end

local function eggTarget(config, model, premium)
    local shop = model and model:FindFirstChild("EggShop")
    local displays = shop and shop:FindFirstChild("Displays")
    local best, price = nil, math.huge
    for _, id in ipairs(config.EggIds) do
        if not premium[id] and (selectedEgg == "Cheapest in current world" or selectedEgg == id) then
            local egg = displays and displays:FindFirstChild(id)
            local wins = egg and egg:GetAttribute("Wins")
            if type(wins) == "number" and wins >= 0 and wins < price then
                best, price = egg, wins
            end
        end
    end
    return best, price
end

local function nativeHatch(eggUI, button)
    if button == hatchButton and requestHatch then return requestHatch end
    -- The authored Hatch.Activated wrapper captures requestHatch directly.
    for _, connection in ipairs(getconnections(button.Activated)) do
        if type(connection.Function) == "function" then
            for _, callback in pairs(readUpvalues(connection.Function)) do
                if type(callback) == "function" then
                    for _, value in pairs(readUpvalues(callback)) do
                        if value == eggUI then
                            hatchButton, requestHatch = button, callback
                            return callback
                        end
                    end
                end
            end
        end
    end
    error("The game's initialized hatch callback is not accessible.")
end

local function runFeature(name, callback)
    local ok, result = pcall(callback)
    if not ok then
        Runtime.LastError = name .. ": " .. tostring(result)
        warn("[Reverb/StoneSkipping] " .. name .. " stopped: " .. tostring(result))
        setEnabled(name, false)
        if name == "Train" then pcall(leaveTraining) end
        if Runtime.Window then
            pcall(function() Runtime.Window:Notify(name .. " stopped: " .. tostring(result), 5) end)
        end
    end
    return ok and result
end

local function pauseTraining(state)
    if state.Activity ~= "Practice" then return false end
    stopPractice()
    moveTo(launchPart())
    trainingStand = nil
    return true
end

local function rebirthStep(state)
    if not enabled.Rebirth or state.Level < state.NextRebirthLevel
        or state.Rebirths >= balance.Rebirth.MaxRebirths then return false end
    if os.clock() >= nextRebirth then
        if sendAction(function() hooks.Rebirth(state.Rebirths) end) then
            nextRebirth = os.clock() + 2
        end
    end
    return true
end

local function stonesStep(state, config)
    if not enabled.Stones then return false end
    local owned, buy = bestStones(state, config)
    -- Equip an existing upgrade first; purchase only a stronger normal stone.
    if owned and owned.Id ~= state.EquippedStone then
        if pauseTraining(state) then return true end
        if os.clock() >= nextUpgrade and sendAction(function() hooks.Equip(owned.Id) end) then
            nextUpgrade = os.clock() + 1
        end
        return true
    end
    if buy then
        if pauseTraining(state) then return true end
        if os.clock() >= nextUpgrade and sendAction(function() hooks.Buy(buy.Id) end) then
            nextUpgrade = os.clock() + 1
        end
        return true
    end
    return false
end

local function petsStep(state)
    if not enabled.Pets or #state.Pets == 0 or state.PetEquipLimit <= 0 then return false end
    local signature = petsChanged(state)
    if signature == petSignature then return false end
    if pauseTraining(state) then return true end
    if os.clock() >= nextPets and sendAction(function() hooks.PetEquipment({ Kind = "Best" }) end) then
        petSignature = signature
        nextPets = os.clock() + 2
    end
    return true
end

local function trailsStep(state)
    if not enabled.Trails then return false end
    local best, bestPower = nil, 1
    for _, trail in ipairs(balance.Trails) do
        if state.OwnedTrails[trail.Id] == true
            and (trail.WinsMultiplier > bestPower
                or (trail.WinsMultiplier == bestPower and state.EquippedTrail == trail.Id)) then
            best, bestPower = trail, trail.WinsMultiplier
        end
    end
    if best and best.Id ~= state.EquippedTrail then
        if pauseTraining(state) then return true end
        if os.clock() >= nextTrail and sendAction(function() hooks.Trail("SetTrail", best.Id, true) end) then
            nextTrail = os.clock() + 1
        end
        return true
    end
    local nextUpgradeTrail
    for _, trail in ipairs(balance.Trails) do
        if state.OwnedTrails[trail.Id] ~= true and trail.Price > 0 and trail.ProductId == 0
            and trail.WinsMultiplier > bestPower
            and (not nextUpgradeTrail or trail.WinsMultiplier < nextUpgradeTrail.WinsMultiplier) then
            nextUpgradeTrail = trail
        end
    end
    if not nextUpgradeTrail or state.Wins < nextUpgradeTrail.Price then return false end
    if pauseTraining(state) then return true end
    if os.clock() >= nextTrail
        and sendAction(function() hooks.Trail("BuyTrail", nextUpgradeTrail.Id, nil) end) then
        nextTrail = os.clock() + 1
    end
    return true
end

local function giftsStep(state)
    if not enabled.Gifts or os.clock() < nextGift then return false end
    giftRewards = giftRewards or require(ReplicatedStorage.Shared.Util.GiftRewards)
    local now = workspace:GetServerTimeNow()
    if giftCycle ~= state.GiftStartedAt then
        giftCycle = state.GiftStartedAt
        table.clear(giftPending)
    end
    if state.GiftStartedAt <= 0 or giftRewards.InCooldown(state, now) then return false end
    for index in ipairs(balance.GiftRewards.UnlockSeconds) do
        if state.GiftClaimed[index] then
            giftPending[index] = nil
        elseif (not giftPending[index] or giftPending[index] <= now)
            and giftRewards.GetReward(state, index, now, balance.GiftRewards) == "Ready" then
            if sendAction(function() hooks.ClaimGift(index) end) then
                -- Match GiftsPage's five-second pending window while waiting
                -- for the existing client state to acknowledge the claim.
                giftPending[index] = now + 5
                nextGift = os.clock() + 1
                return true
            end
            return false
        end
    end
    return false
end

local function throwStep(state)
    if pauseTraining(state) then return end
    local character = Players.LocalPlayer.Character
    if not launchZone.Contains(character) then
        moveTo(launchPart())
        return
    end
    if boundButton.Active and boundButton.Interactable then sendAction(beginThrow) end
end

local function trainStep(state, config, model)
    local folder = model and model:FindFirstChild("TrainingZones")
    local best = bestTraining(state, config, folder)
    if not best then
        if trainingStand then leaveTraining() end
        return
    end
    if not nearStand(best) then
        if pauseTraining(state) then return end
        if moveTo(best) then trainingStand = best end
    else
        trainingStand = best
    end
    -- The saved client has no StartPractice request: training follows entry into
    -- the authored TrainingStand magnet area. Live testing must confirm entry.
end

local function hatchStep(state, config, model, premium)
    if pauseTraining(state) then return end
    local egg, cost = eggTarget(config, model, premium)
    if not egg then
        return
    end
    local base = egg:FindFirstChild("Base")
    local anchor = base and base:FindFirstChild("PromptAnchor")
    local prompt = anchor and anchor:FindFirstChild("EggPrompt")
    local root = characterParts()
    if not root or not prompt or not prompt.Enabled then return end
    if (root.Position - anchor.WorldPosition).Magnitude > math.min(6, prompt.MaxActivationDistance) then
        moveTo(base, 4)
        return
    end
    if state.Wins < cost then
        return
    end
    if #state.Pets >= state.PetCapacity then
        return
    end
    local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    local eggUI = gui and gui:FindFirstChild("EggShopUI")
    -- Require the normal game's prompt to select this exact non-premium egg.
    if not eggUI or not eggUI.Enabled or eggUI.Adornee ~= anchor then return end
    local content = eggUI:FindFirstChild("Content")
    local actions = content and content:FindFirstChild("Actions")
    local button = actions and actions:FindFirstChild("Hatch")
    assert(button, "The game's Hatch button is missing.")
    local hatch = nativeHatch(eggUI, button)
    -- One egg at a time; the native path owns IDs, request timeout and animation.
    sendAction(function() hatch(1, false) end)
end

function Runtime.Destroy()
    if destroyed then return end
    if enabled.Train then pcall(leaveTraining) end
    destroyed = true
    autoThrow = false
    for name in pairs(enabled) do enabled[name] = false end
    boundButton = nil
    beginThrow = nil
    hooks, client, hatchButton, requestHatch = nil, nil, nil, nil
    if environment.ReverbLoadedScripts
        and environment.ReverbLoadedScripts[SCRIPT.id] == token then
        environment.ReverbLoadedScripts[SCRIPT.id] = nil
    end
    if environment.ReverbScriptInstances
        and environment.ReverbScriptInstances[SCRIPT.id] == Runtime then
        environment.ReverbScriptInstances[SCRIPT.id] = nil
    end
    if environment.ReverbCurrentScript
        and environment.ReverbCurrentScript.runtime == Runtime then
        environment.ReverbCurrentScript = nil
    end
    local window = Runtime.Window
    Runtime.Window = nil
    if window and type(window.Destroy) == "function" then
        pcall(function() window:Destroy() end)
    end
end

local function start()
    if not game:IsLoaded() then game.Loaded:Wait() end
    assert(game.PlaceId == 111543903102439, "Run this script in +1 Stone Skipping.")
    assert(type(getconnections) == "function" and type(readUpvalues) == "function",
        "Auto Throw requires getconnections and getupvalues support from your executor.")
    local routed = environment.ReverbScript
    assert(type(routed) ~= "table" or not routed.id or routed.id == SCRIPT.id,
        "The loader routed a different game script.")

    local button = throwButton()
    assert(button, "The game's Throw button is missing. Finish loading the game before running this script.")
    bindThrow(button)

    local shared = ReplicatedStorage:FindFirstChild("Shared")
    assert(shared, "The game's Shared modules are missing.")
    -- Use shared rules, not copied progression formulas or client runtimes.
    balance = require(shared.Config.GameBalance)
    worlds = require(shared.Config.Worlds)
    worldMap = require(shared.Util.WorldMap)
    launchZone = require(shared.Util.LaunchZone)
    stoneCatalog = require(shared.Util.StoneCatalog)
    network = ReplicatedStorage:WaitForChild("SkippingNetwork", 10)
    network = network and network:WaitForChild("Request", 10)
    assert(network and network:IsA("RemoteEvent"), "The game's request remote is missing.")
    assert(client.GetState(), "The game has not received your player state yet.")

    environment.ReverbLoadedScripts = environment.ReverbLoadedScripts or {}
    environment.ReverbScriptInstances = environment.ReverbScriptInstances or {}
    local previous = environment.ReverbScriptInstances[SCRIPT.id]
    if previous and type(previous.Destroy) == "function" then previous.Destroy() end
    environment.ReverbLoadedScripts[SCRIPT.id] = token
    environment.ReverbScriptInstances[SCRIPT.id] = Runtime

    local compiled, compileError = loadstring(game:HttpGet(REVERB_J_URL))
    assert(compiled, tostring(compileError))
    local library = compiled()
    local access = environment.ReverbAccess or {}
    local tier = access.tier or environment.ReverbKeyTier or "free"
    local window = library:CreateWindow({
        Game = SCRIPT.name,
        Tier = tier == "premium" and "PREMIUM" or "FREE",
        RememberSettings = false,
        ConfigName = SCRIPT.id,
    })
    Runtime.Window = window

    -- ВЫЗОВ СИСТЕМЫ ФИДБЕКА
    addFeedbackSystem(window, library, SCRIPT.name)

    local mainTab = window:Tab("Main")
    local main = mainTab:Section("Main")
    controls.Throw = main:Toggle("Auto Throw", false, function(value)
        runFeature("Throw", function() selectMode("Throw", value) end)
    end)
    controls.Train = main:Toggle("Auto Train", false, function(value)
        runFeature("Train", function() selectMode("Train", value) end)
    end)
    controls.Stones = main:Toggle("Auto Buy and Equip Stones", false, function(value)
        enabled.Stones = value
        nextUpgrade = 0
    end)
    controls.Trails = main:Toggle("Auto Buy and Equip Next Trail", false, function(value)
        enabled.Trails = value
        nextTrail = 0
    end)
    controls.Gifts = main:Toggle("Auto Claim Timed Rewards", false, function(value)
        enabled.Gifts = value
        nextGift = 0
        table.clear(giftPending)
    end)
    controls.Rebirth = main:Toggle("Auto Rebirth", false, function(value)
        enabled.Rebirth = value
        nextRebirth = 0
    end)

    local options, premium = eggOptions()
    local pets = mainTab:Section("Pets")
    pets:Dropdown("Egg", options, selectedEgg, function(value) selectedEgg = value end)
    controls.Hatch = pets:Toggle("Auto Hatch", false, function(value)
        runFeature("Hatch", function() selectMode("Hatch", value) end)
    end)
    controls.Pets = pets:Toggle("Auto Equip Best Pets", false, function(value)
        enabled.Pets = value
        petSignature = nil
        nextPets = 0
    end)
    local settings = window:Tab("Settings")
    settings:Section("Preferences"):Toggle("Remember active settings", false, function(value)
        window:SetRememberSettings(value)
    end)
    settings:Section("Script"):Button("Unload Script", Runtime.Destroy)

    window:Tab("Changelog"):Section("V1 Â· 10th October 2026"):Label("Script Release")
    environment.ReverbCurrentScript = { id = SCRIPT.id, runtime = Runtime }

    task.spawn(function()
        while isActive() do
            local ok, failure = pcall(function()
                local current = throwButton()
                if not current then return end
                if current ~= boundButton then bindThrow(current) end
                local state = client.GetState()
                if not state or not characterParts() or client.IsThrowBusy() or client.IsModalOpen()
                    or (state.Activity ~= "Idle" and state.Activity ~= "Practice") then return end
                local config = worldMap.GetConfig(Players.LocalPlayer)
                local model = worldMap.GetModel(Players.LocalPlayer)
                if runFeature("Gifts", function() return giftsStep(state) end) then return end
                -- Finish pending upgrades before starting another farm action.
                if runFeature("Rebirth", function() return rebirthStep(state) end) then return end
                if runFeature("Stones", function() return stonesStep(state, config) end) then return end
                if runFeature("Trails", function() return trailsStep(state) end) then return end
                if runFeature("Pets", function() return petsStep(state) end) then return end
                if autoThrow then
                    runFeature("Throw", function() throwStep(state) end)
                elseif enabled.Train then
                    runFeature("Train", function() trainStep(state, config, model) end)
                elseif enabled.Hatch then
                    runFeature("Hatch", function() hatchStep(state, config, model, premium) end)
                end
            end)
            if not ok then
                Runtime.LastError = "Automation: " .. tostring(failure)
                warn("[Reverb/StoneSkipping] Automation stopped: " .. tostring(failure))
                if enabled.Train then pcall(leaveTraining) end
                for _, name in ipairs({ "Throw", "Train", "Stones", "Trails", "Gifts", "Rebirth", "Hatch", "Pets" }) do
                    setEnabled(name, false)
                end
                pcall(function() window:Notify("Automation stopped: " .. tostring(failure), 5) end)
            end
            -- Local availability checks only; beginThrow gates actual network requests.
            task.wait(0.2)
        end
    end)
end

local ok, failure = pcall(start)
if not ok then
    Runtime.Destroy()
    error("[Reverb/StoneSkipping] " .. tostring(failure), 0)
end
