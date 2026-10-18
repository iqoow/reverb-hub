-- ONE TAP
-- Local update draft: runtime and executor testing is still required.

local SCRIPT = {
    id = "OneTap",
    name = "One Tap",
    version = "V1",
    updated = "24 July 2026",
    author = "Reverb",
    changelog = {
        {
            Version = "V1",
            Date = "24th July 2026",
            Title = "Initial release with 7 features",
            Added = {},
        },
    },
}

----------------------------------------------------------------------------------------------------------------

local REVERB_J_URL =
    "https://raw.githubusercontent.com/rbxreverb/ReverbJ/refs/heads/main/source.lua?v=remember-settings-20260812"

local environment = (getgenv and getgenv()) or _G
local Runtime = {}

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

local function protectedCallback(name, callback)
    return function(...)
        local succeeded, callbackError = pcall(callback, ...)
        if not succeeded then
            warn("[Reverb] " .. name .. " failed: " .. tostring(callbackError))
        end
    end
end

function Runtime.Toggle(section, settings)
    return section:Toggle(settings.Name, settings.CurrentValue == true,
        protectedCallback(settings.Name, settings.Callback), settings.Flag)
end

function Runtime.Dropdown(section, settings)
    return section:Dropdown(settings.Name, settings.Options,
        settings.CurrentOption, protectedCallback(settings.Name, settings.Callback), settings.Flag)
end

function Runtime.Slider(section, settings)
    return section:Slider(settings.Name, settings.Range[1], settings.Range[2],
        settings.CurrentValue, protectedCallback(settings.Name, settings.Callback), settings.Flag)
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
                warn("[Reverb] " .. featureId .. " failed: " .. tostring(loopError))
                task.wait(2)
            end
        end
    end)
end

-- ===== СИСТЕМА ФИДБЕКА =====
local function addFeedbackSystem(window, library, gameName)
    local HttpService = game:GetService("HttpService")
    local WEBHOOK_URL = "https://reverbhook.carlolarp333.workers.dev"
    local lastFeedbackTime = 0
    
    local FeedbackTab = window:Tab("Feedback", "message-square")
    local Section = FeedbackTab:Section("Feedback Sender")
    
    local anonymous = false
    local messageText = ""

    Section:Input("Message", "Describe your issue or suggestion...", function(text)
        messageText = text
    end)

    Section:Toggle("Send Anonymously", false, function(val) 
        anonymous = val 
    end)

    Section:Button("Submit Feedback", function()
        if messageText == "" then 
            window:Notify("Please enter a message.", 4) 
            return 
        end
        
        if string.find(messageText, "@everyone", 1, true) or string.find(messageText, "@here", 1, true) then 
            window:Notify("Error: Cannot send messages containing @everyone or @here.", 4) 
            return 
        end
        
        local currentTime = os.clock()
        if currentTime - lastFeedbackTime < 15 then
            window:Notify(string.format("Please wait %d seconds before sending feedback again.", math.ceil(15 - (currentTime - lastFeedbackTime))), 4)
            return
        end
        
        local embed = {
            title = "📬 New Feedback - " .. gameName,
            description = messageText,
            color = anonymous and 0x808080 or 0x00FF00,
            timestamp = DateTime.now():ToIsoDate()
        }
        
        if not anonymous then
            local LocalPlayer = game:GetService("Players").LocalPlayer
            local avatarUrl = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. LocalPlayer.UserId .. "&width=420&height=420&format=png"
            local createdDate = os.date("%Y-%m-%d", os.time() - LocalPlayer.AccountAge * 86400)
            embed.fields = {
                { name = "USER ID", value = tostring(LocalPlayer.UserId), inline = true },
                { name = "USERNAME", value = LocalPlayer.Name, inline = true },
                { name = "DISPLAY NAME", value = LocalPlayer.DisplayName, inline = true },
                { name = "CREATED", value = createdDate, inline = true },
                { name = "STATUS", value = LocalPlayer.MembershipType.Name, inline = true }
            }
            embed.thumbnail = { url = avatarUrl }
        else
            embed.description = "**[ANONYMOUS]**\n" .. messageText
        end
        
        local payload = HttpService:JSONEncode({
            username = "Reverb Feedback",
            embeds = { embed }
        })
        
        window:Notify("Sending feedback...", 3)

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
                    window:Notify("Feedback sent successfully!", 3)
                    messageText = ""
                else
                    window:Notify("Failed to send feedback: " .. tostring(err), 4)
                end
            else
                window:Notify("HTTP requests are not supported by your executor.", 4)
            end
        end)
    end)
end
-- ===== КОНЕЦ СИСТЕМЫ ФИДБЕКА =====

----------------------------------------------------------------------------------------------------------------

-- Game-specific area. Create any tabs, sections, and features this game needs.
local function buildGame(RuntimeContext)
    local MainTab = RuntimeContext.Window:Tab("Main")
    local VisualsTab = RuntimeContext.Window:Tab("Visuals")
    local VisualsSection = VisualsTab:Section("Player ESP")

    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = Players.LocalPlayer

    -- Disable providers from both prior hook implementations before replacing them.
    for _, key in ipairs({ "ReverbOneTapSilentAim", "ReverbOneTapSilentAimV2" }) do
        local previousHook = environment[key]
        if type(previousHook) == "table" then
            previousHook.Provider = nil
            previousHook.RayProvider = nil
        end
    end

    ----------------------------------------------------------------------------------------------------------------
    -- PLAYER CHAMS

    local chamsEnabled = false
    local chamConnections = {}
    local activeChams = {}
    local chamDeathConnections = {}
    local pendingChamModels = setmetatable({}, {
        __mode = "k",
    })

    local CHAM_NAME = "Reverb_PlayerCham"
    local INCLUDE_LOCAL_PLAYER = false
    local CHAM_ALL_HUMANOIDS_IF_NO_MATCH = true

    local VISIBLE_COLOR = Color3.fromRGB(0, 255, 90)
    local HIDDEN_COLOR = Color3.fromRGB(255, 60, 60)
    local espStyle = "Both"
    local espFillOpacity = 55
    local espOutlineOpacity = 100
    local espThroughWalls = true
    local espTeamCheck = false
    local espMaxDistance = 0
    local espNames = false
    local espDistance = false
    local espHealth = false
    local espWeapons = false
    local espLabels = {}
    local ESP_COLORS = {
        Green = Color3.fromRGB(0, 255, 90),
        Red = Color3.fromRGB(255, 60, 60),
        Cyan = Color3.fromRGB(0, 226, 249),
        White = Color3.fromRGB(237, 241, 245),
        Purple = Color3.fromRGB(190, 125, 255),
        Yellow = Color3.fromRGB(255, 210, 75),
    }

    local USER_ID_ATTRIBUTES = {
        "UserId",
        "UserID",
        "PlayerUserId",
        "OwnerUserId",
        "OwnerId",
        "userId",
    }

    local NAME_ATTRIBUTES = {
        "PlayerName",
        "OwnerName",
        "Username",
        "UserName",
        "DisplayName",
    }

    local function shouldChamPlayer(player)
        return player
            and player.Parent == Players
            and (INCLUDE_LOCAL_PLAYER or player ~= LocalPlayer)
    end

    local function disconnectChamConnections()
        for _, connection in ipairs(chamConnections) do
            if connection then
                connection:Disconnect()
            end
        end

        table.clear(chamConnections)
    end

    local function isValidCharacterModel(model)
        if not model or not model:IsA("Model") or not model.Parent then
            return false
        end

        local humanoid = model:FindFirstChildOfClass("Humanoid")

        if not humanoid or humanoid.Health <= 0 then
            return false
        end

        local root =
            model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("Head")
            or model:FindFirstChild("Torso")
            or model:FindFirstChild("UpperTorso")

        return root and root:IsA("BasePart")
    end

    local function getChamTargetPart(model)
        if not model or not model.Parent then
            return nil
        end

        return model:FindFirstChild("Head")
            or model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("UpperTorso")
            or model:FindFirstChild("Torso")
    end

    local function hasLineOfSight(model)
        local camera = Workspace.CurrentCamera

        if not camera then
            return false
        end

        local targetPart = getChamTargetPart(model)

        if not targetPart or not targetPart:IsA("BasePart") then
            return false
        end

        local origin = camera.CFrame.Position
        local direction = targetPart.Position - origin

        if direction.Magnitude <= 0 then
            return true
        end

        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.FilterDescendantsInstances = {
            camera,
            LocalPlayer.Character,
        }

        local result = Workspace:Raycast(origin, direction, raycastParams)

        if not result then
            return true
        end

        return result.Instance and result.Instance:IsDescendantOf(model)
    end

    local findPlayerFromModel

    local function updateEspLabel(model, color, distance, visible)
        local details = espLabels[model]
        if not (espNames or espDistance or espHealth or espWeapons) then
            if details then
                details.gui.Enabled = false
            end
            return
        end
        local part = getChamTargetPart(model)
        if not part then
            return
        end
        if not details then
            local gui = Instance.new("BillboardGui")
            gui.Name = "Reverb_PlayerDetails"
            gui.Size = UDim2.fromOffset(200, 68)
            gui.StudsOffsetWorldSpace = Vector3.new(0, 2.3, 0)
            gui.ResetOnSpawn = false
            gui.Parent = model
            local label = Instance.new("TextLabel")
            label.Size = UDim2.fromScale(1, 1)
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.GothamMedium
            label.TextSize = 13
            label.TextStrokeTransparency = 0.25
            label.TextStrokeColor3 = Color3.new(0, 0, 0)
            label.Parent = gui
            details = { gui = gui, label = label }
            espLabels[model] = details
        end
        details.gui.Adornee = part
        details.gui.AlwaysOnTop = espThroughWalls
        details.gui.Enabled = visible
        local player = findPlayerFromModel(model)
        local lines = {}
        if espNames then
            table.insert(lines, player and player.DisplayName or model.Name)
        end
        local stats = {}
        if espDistance then
            table.insert(stats, tostring(math.floor(distance + 0.5)) .. " studs")
        end
        if espHealth then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            if humanoid then
                table.insert(stats, tostring(math.ceil(humanoid.Health)) .. "/"
                    .. tostring(math.ceil(humanoid.MaxHealth)) .. " HP")
            end
        end
        if #stats > 0 then
            table.insert(lines, table.concat(stats, "  ·  "))
        end
        if espWeapons then
            -- CharacterManager uses currentWeapon for self and currentWeaponServer for others.
            local slot = model:GetAttribute("currentWeaponServer")
            local weapon = slot == "Primary" and model:GetAttribute("primaryWeapon")
                or slot == "Secondary" and model:GetAttribute("secondaryWeapon")
                or slot == "Knife" and model:GetAttribute("knifeName")
            if weapon then
                table.insert(lines, tostring(weapon))
            end
        end
        details.label.Text = table.concat(lines, "\n")
        details.label.TextColor3 = color
    end

    local function updateChamColor(model, highlight)
        if not model or not model.Parent or not highlight or not highlight.Parent then
            return
        end

        local color = hasLineOfSight(model) and VISIBLE_COLOR or HIDDEN_COLOR

        highlight.FillColor = color
        highlight.OutlineColor = color
        highlight.FillTransparency = espStyle == "Outline" and 1 or 1 - espFillOpacity / 100
        highlight.OutlineTransparency = espStyle == "Filled" and 1 or 1 - espOutlineOpacity / 100
        highlight.DepthMode = espThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop
            or Enum.HighlightDepthMode.Occluded
        local camera = Workspace.CurrentCamera
        local part = getChamTargetPart(model)
        local distance = camera and part and (part.Position - camera.CFrame.Position).Magnitude or 0
        local player = espTeamCheck and findPlayerFromModel(model)
        local teammate = player and LocalPlayer.Team and player.Team == LocalPlayer.Team
        local visible = (espMaxDistance == 0 or distance <= espMaxDistance) and not teammate
        highlight.Enabled = visible
        updateEspLabel(model, color, distance, visible)
    end

    local function modelMatchesPlayer(model, player)
        if not isValidCharacterModel(model) or not shouldChamPlayer(player) then
            return false
        end

        if player.Character == model then
            return true
        end

        if model.Name == player.Name or model.Name == player.DisplayName then
            return true
        end

        for _, attributeName in ipairs(USER_ID_ATTRIBUTES) do
            local value = model:GetAttribute(attributeName)

            if tonumber(value) == player.UserId then
                return true
            end
        end

        for _, attributeName in ipairs(NAME_ATTRIBUTES) do
            local value = model:GetAttribute(attributeName)

            if value == player.Name or value == player.DisplayName then
                return true
            end
        end

        return false
    end

    findPlayerFromModel = function(model)
        if not model then
            return nil
        end

        local directPlayer = Players:GetPlayerFromCharacter(model)

        if directPlayer then
            return directPlayer
        end

        for _, player in ipairs(Players:GetPlayers()) do
            if modelMatchesPlayer(model, player) then
                return player
            end
        end

        return nil
    end

    local function removeChamFromModel(model)
        local details = espLabels[model]
        if details then
            details.gui:Destroy()
            espLabels[model] = nil
        end
        local deathConnection = chamDeathConnections[model]

        if deathConnection then
            deathConnection:Disconnect()
            chamDeathConnections[model] = nil
        end

        local highlight = activeChams[model]

        if highlight then
            highlight:Destroy()
            activeChams[model] = nil
        end

        if model and model.Parent then
            local oldHighlight = model:FindFirstChild(CHAM_NAME)

            if oldHighlight then
                oldHighlight:Destroy()
            end
        end
    end

    local function clearAllChams()
        for model in pairs(activeChams) do
            removeChamFromModel(model)
        end
        for model in pairs(espLabels) do
            removeChamFromModel(model)
        end

        for _, descendant in ipairs(Workspace:GetDescendants()) do
            if descendant:IsA("Highlight") and descendant.Name == CHAM_NAME then
                descendant:Destroy()
            end
        end
    end

    local function applyChamToModel(model)
        if not chamsEnabled or not isValidCharacterModel(model) then
            return
        end

        local existing = model:FindFirstChild(CHAM_NAME)

        if existing and existing:IsA("Highlight") then
            activeChams[model] = existing
            updateChamColor(model, existing)

            local humanoid = model:FindFirstChildOfClass("Humanoid")

            if humanoid and not chamDeathConnections[model] then
                chamDeathConnections[model] = humanoid.Died:Connect(function()
                    removeChamFromModel(model)
                end)
            end

            return
        end

        removeChamFromModel(model)

        local highlight = Instance.new("Highlight")
        highlight.Name = CHAM_NAME
        highlight.Adornee = model
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillTransparency = 0.45
        highlight.OutlineTransparency = 0
        highlight.Enabled = true
        highlight.Parent = model

        activeChams[model] = highlight
        updateChamColor(model, highlight)

        local humanoid = model:FindFirstChildOfClass("Humanoid")

        if humanoid and not chamDeathConnections[model] then
            chamDeathConnections[model] = humanoid.Died:Connect(function()
                removeChamFromModel(model)
            end)
        end
    end

    local function queueChamModel(model)
        if not chamsEnabled
            or not model
            or not model:IsA("Model")
            or pendingChamModels[model]
        then
            return
        end

        pendingChamModels[model] = true

        task.delay(0.2, function()
            pendingChamModels[model] = nil

            if not chamsEnabled
                or not model.Parent
                or (not INCLUDE_LOCAL_PLAYER and model == LocalPlayer.Character)
            then
                return
            end

            if isValidCharacterModel(model) then
                applyChamToModel(model)
            end
        end)
    end

    local function applyChamsForPlayer(player)
        if not chamsEnabled or not shouldChamPlayer(player) then
            return
        end

        local character = player.Character

        if character and isValidCharacterModel(character) then
            applyChamToModel(character)
        end
    end

    local function repairChams()
        local wantedModels = {}

        for _, player in ipairs(Players:GetPlayers()) do
            local character = player.Character

            if shouldChamPlayer(player)
                and character
                and isValidCharacterModel(character)
            then
                wantedModels[character] = true
                applyChamToModel(character)
            end
        end

        if CHAM_ALL_HUMANOIDS_IF_NO_MATCH then
            for _, descendant in ipairs(Workspace:GetDescendants()) do
                if descendant:IsA("Model") and isValidCharacterModel(descendant) then
                    if not LocalPlayer.Character
                        or descendant ~= LocalPlayer.Character
                        or INCLUDE_LOCAL_PLAYER
                    then
                        wantedModels[descendant] = true
                        applyChamToModel(descendant)
                    end
                end
            end
        end

        for model in pairs(activeChams) do
            if not wantedModels[model] or not model.Parent then
                removeChamFromModel(model)
            end
        end
    end

    local function updateAllChamColors()
        for model, highlight in pairs(activeChams) do
            if model and model.Parent and highlight and highlight.Parent then
                updateChamColor(model, highlight)
            else
                removeChamFromModel(model)
            end
        end
    end

    local function watchPlayer(player)
        if not shouldChamPlayer(player) then
            return
        end

        applyChamsForPlayer(player)

        table.insert(chamConnections, player.CharacterAdded:Connect(function()
            task.wait(0.5)
            applyChamsForPlayer(player)
        end))
    end

    RuntimeContext.Toggle(VisualsSection, {
        Name = "Player Chams",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_player_chams",

        Callback = function(enabled)
            chamsEnabled = enabled

            disconnectChamConnections()

            if enabled then
                for _, player in ipairs(Players:GetPlayers()) do
                    watchPlayer(player)
                end

                table.insert(chamConnections, Players.PlayerAdded:Connect(function(player)
                    watchPlayer(player)
                end))

                table.insert(chamConnections, Players.PlayerRemoving:Connect(function(player)
                    if player.Character then
                        removeChamFromModel(player.Character)
                    end
                end))

                table.insert(chamConnections, Workspace.DescendantAdded:Connect(function(descendant)
                    if descendant:IsA("Model") then
                        queueChamModel(descendant)
                    elseif descendant:IsA("Humanoid") then
                        queueChamModel(descendant.Parent)
                    end
                end))

                repairChams()
                updateAllChamColors()
            else
                clearAllChams()
            end
        end,
    })

    RuntimeContext.StartLoop("player_chams_repair", 2, function()
        repairChams()
    end, function()
        return chamsEnabled
    end)

    RuntimeContext.StartLoop("player_chams_visibility", 0.1, function()
        updateAllChamColors()
    end, function()
        return chamsEnabled
    end)

    RuntimeContext.AddCleanup(function()
        chamsEnabled = false
        disconnectChamConnections()
        clearAllChams()
        table.clear(pendingChamModels)
    end)

    RuntimeContext.Dropdown(VisualsSection, {
        Name = "ESP Style", Options = { "Both", "Filled", "Outline" },
        CurrentOption = espStyle, Flag = SCRIPT.id .. "_esp_style",
        Callback = function(value) espStyle = value; updateAllChamColors() end,
    })
    RuntimeContext.Slider(VisualsSection, {
        Name = "Fill Opacity (%)", Range = { 0, 100 }, CurrentValue = espFillOpacity,
        Flag = SCRIPT.id .. "_esp_fill_opacity",
        Callback = function(value) espFillOpacity = value; updateAllChamColors() end,
    })
    RuntimeContext.Slider(VisualsSection, {
        Name = "Outline Opacity (%)", Range = { 0, 100 }, CurrentValue = espOutlineOpacity,
        Flag = SCRIPT.id .. "_esp_outline_opacity",
        Callback = function(value) espOutlineOpacity = value; updateAllChamColors() end,
    })
    local colorOptions = { "Green", "Red", "Cyan", "White", "Purple", "Yellow" }
    RuntimeContext.Dropdown(VisualsSection, {
        Name = "Visible Color", Options = colorOptions, CurrentOption = "Green",
        Flag = SCRIPT.id .. "_esp_visible_color",
        Callback = function(value) VISIBLE_COLOR = ESP_COLORS[value]; updateAllChamColors() end,
    })
    RuntimeContext.Dropdown(VisualsSection, {
        Name = "Hidden Color", Options = colorOptions, CurrentOption = "Red",
        Flag = SCRIPT.id .. "_esp_hidden_color",
        Callback = function(value) HIDDEN_COLOR = ESP_COLORS[value]; updateAllChamColors() end,
    })
    RuntimeContext.Toggle(VisualsSection, {
        Name = "Show Through Walls", CurrentValue = espThroughWalls,
        Flag = SCRIPT.id .. "_esp_through_walls",
        Callback = function(value) espThroughWalls = value; updateAllChamColors() end,
    })
    RuntimeContext.Toggle(VisualsSection, {
        Name = "ESP Team Check", CurrentValue = espTeamCheck,
        Flag = SCRIPT.id .. "_esp_team_check",
        Callback = function(value) espTeamCheck = value; updateAllChamColors() end,
    })
    RuntimeContext.Slider(VisualsSection, {
        Name = "ESP Max Distance (0 = Unlimited)", Range = { 0, 3000 }, CurrentValue = 0,
        Flag = SCRIPT.id .. "_esp_max_distance",
        Callback = function(value) espMaxDistance = value; updateAllChamColors() end,
    })
    local DetailsSection = VisualsTab:Section("Player Details")
    RuntimeContext.Toggle(DetailsSection, {
        Name = "Show Names", CurrentValue = false, Flag = SCRIPT.id .. "_esp_names",
        Callback = function(value) espNames = value; updateAllChamColors() end,
    })
    RuntimeContext.Toggle(DetailsSection, {
        Name = "Show Distance", CurrentValue = false, Flag = SCRIPT.id .. "_esp_distance",
        Callback = function(value) espDistance = value; updateAllChamColors() end,
    })
    RuntimeContext.Toggle(DetailsSection, {
        Name = "Show Health", CurrentValue = false, Flag = SCRIPT.id .. "_esp_health",
        Callback = function(value) espHealth = value; updateAllChamColors() end,
    })
    RuntimeContext.Toggle(DetailsSection, {
        Name = "Show Weapon", CurrentValue = false, Flag = SCRIPT.id .. "_esp_weapon",
        Callback = function(value) espWeapons = value; updateAllChamColors() end,
    })

    ----------------------------------------------------------------------------------------------------------------
    -- TRIGGERBOT

    local CombatSection = MainTab:Section("Silent Aim")

    local triggerbotEnabled = false
    local lastTriggerShot = 0

    local TRIGGERBOT_RANGE = 1000
    local triggerbotDelay = 0.12
    local TRIGGERBOT_TEAM_CHECK = true

    local function getCharacterFromPart(part)
        if not part then
            return nil
        end

        local current = part

        while current and current ~= Workspace do
            if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
                return current
            end

            current = current.Parent
        end

        return nil
    end

    local function isAliveCharacter(character)
        if not character then
            return false
        end

        local humanoid = character:FindFirstChildOfClass("Humanoid")

        if not humanoid then
            return false
        end

        return humanoid.Health > 0
    end

    local function isEnemyPlayer(player)
        if not player then
            return false
        end

        if player == LocalPlayer then
            return false
        end

        if not TRIGGERBOT_TEAM_CHECK then
            return true
        end

        if LocalPlayer.Team ~= nil and player.Team ~= nil then
            return player.Team ~= LocalPlayer.Team
        end

        return true
    end

    ----------------------------------------------------------------------------------------------------------------
    -- SILENT AIM

    local silentAimEnabled = false
    local silentAimCandidates = {}
    local silentAimCandidateConnections = {}
    local silentAimTarget
    local silentAimHookToken = {}
    local silentAimTargetMode = "Root"
    local showSilentAimFov = true

    local silentAimFov = 250
    -- One Tap currently casts its firing ray with a short direction vector
    -- (roughly 3-4 studs); the old 50-stud guard rejected every real shot.
    local SILENT_AIM_MIN_RAY_LENGTH = 1
    local silentAimFovGui
    local silentAimFovCircle

    local function createSilentAimFovCircle()
        if silentAimFovCircle and silentAimFovCircle.Parent then
            return
        end

        local CoreGui = game:GetService("CoreGui")
        local parent = CoreGui
        local succeeded, hiddenParent = pcall(function()
            return gethui and gethui()
        end)

        if succeeded and hiddenParent then
            parent = hiddenParent
        end

        local oldGui = parent:FindFirstChild("ReverbOneTapFov")

        if oldGui then
            oldGui:Destroy()
        end

        silentAimFovGui = Instance.new("ScreenGui")
        silentAimFovGui.Name = "ReverbOneTapFov"
        silentAimFovGui.IgnoreGuiInset = true
        silentAimFovGui.ResetOnSpawn = false
        silentAimFovGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        silentAimFovGui.Parent = parent

        silentAimFovCircle = Instance.new("Frame")
        silentAimFovCircle.Name = "Circle"
        silentAimFovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
        silentAimFovCircle.BackgroundTransparency = 1
        silentAimFovCircle.Position = UDim2.fromScale(0.5, 0.5)
        silentAimFovCircle.Size = UDim2.fromOffset(
            silentAimFov * 2,
            silentAimFov * 2
        )
        silentAimFovCircle.Visible = silentAimEnabled and showSilentAimFov
        silentAimFovCircle.ZIndex = 100
        silentAimFovCircle.Parent = silentAimFovGui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = silentAimFovCircle

        local outline = Instance.new("UIStroke")
        outline.Color = Color3.fromRGB(0, 174, 255)
        outline.Thickness = 1.5
        outline.Transparency = 0.15
        outline.Parent = silentAimFovCircle
    end

    local function updateSilentAimFovCircle()
        if silentAimEnabled then
            createSilentAimFovCircle()
        end

        if silentAimFovCircle and silentAimFovCircle.Parent then
            silentAimFovCircle.Size = UDim2.fromOffset(
                silentAimFov * 2,
                silentAimFov * 2
            )
            silentAimFovCircle.Visible = silentAimEnabled
                and showSilentAimFov
        end
    end

    local function getSilentAimPart(character)
        if not character or not character.Parent then
            return nil
        end

        if silentAimTargetMode == "Head" then
            return character:FindFirstChild("Hitbox_Head", true)
                or character:FindFirstChild("Head", true)
                or character:FindFirstChild("HumanoidRootPart", true)
                or character:FindFirstChild("Hitbox_Torso", true)
        elseif silentAimTargetMode == "Torso" then
            return character:FindFirstChild("Hitbox_Torso", true)
                or character:FindFirstChild("UpperTorso", true)
                or character:FindFirstChild("Torso", true)
                or character:FindFirstChild("HumanoidRootPart", true)
        end

        return character:FindFirstChild("HumanoidRootPart", true)
            or character:FindFirstChild("Hitbox_Torso", true)
            or character:FindFirstChild("UpperTorso", true)
            or character:FindFirstChild("Torso", true)
            or character:FindFirstChild("Hitbox_Head", true)
            or character:FindFirstChild("Head", true)
    end

    local function rebuildSilentAimCandidates()
        table.clear(silentAimCandidates)

        for _, player in ipairs(Players:GetPlayers()) do
            if isEnemyPlayer(player) then
                local character = player.Character

                if character and isAliveCharacter(character) then
                    silentAimCandidates[character] = true
                end
            end
        end

        for _, descendant in ipairs(Workspace:GetDescendants()) do
            if descendant:IsA("Model") and isValidCharacterModel(descendant) then
                if not LocalPlayer.Character
                    or descendant ~= LocalPlayer.Character
                then
                    silentAimCandidates[descendant] = true
                end
            end
        end
    end

    local function disconnectSilentAimCandidateWatchers()
        for _, connection in ipairs(silentAimCandidateConnections) do
            connection:Disconnect()
        end

        table.clear(silentAimCandidateConnections)
    end

    local function indexSilentAimDescendant(descendant)
        local model = descendant:IsA("Model")
            and descendant
            or descendant:FindFirstAncestorOfClass("Model")

        if model
            and model.Parent
            and isValidCharacterModel(model)
            and (not LocalPlayer.Character or model ~= LocalPlayer.Character)
        then
            silentAimCandidates[model] = true
        end
    end

    local function watchSilentAimCandidates()
        disconnectSilentAimCandidateWatchers()

        table.insert(
            silentAimCandidateConnections,
            Workspace.DescendantAdded:Connect(function(descendant)
                task.defer(indexSilentAimDescendant, descendant)
            end)
        )

        table.insert(
            silentAimCandidateConnections,
            Workspace.DescendantRemoving:Connect(function(descendant)
                if descendant:IsA("Model") then
                    silentAimCandidates[descendant] = nil
                end
            end)
        )
    end

    local function updateSilentAimTarget()
        local camera = Workspace.CurrentCamera

        if not camera then
            silentAimTarget = nil
            return
        end

        local viewportCenter = camera.ViewportSize / 2
        local bestPart
        local bestDistance = silentAimFov

        for character in pairs(silentAimCandidates) do
            if not character.Parent or not isAliveCharacter(character) then
                silentAimCandidates[character] = nil
            else
                local targetPart = getSilentAimPart(character)

                if targetPart and targetPart:IsA("BasePart") then
                    local screenPosition, onScreen =
                        camera:WorldToViewportPoint(targetPart.Position)

                    if onScreen and screenPosition.Z > 0 then
                        local screenDistance = (
                            Vector2.new(screenPosition.X, screenPosition.Y)
                            - viewportCenter
                        ).Magnitude

                        if screenDistance < bestDistance then
                            bestDistance = screenDistance
                            bestPart = targetPart
                        end
                    end
                end
            end
        end

        silentAimTarget = bestPart
    end

    local function redirectShotRay(origin, direction)
        local targetPart = silentAimTarget

        if not silentAimEnabled
            or not targetPart
            or not targetPart.Parent
            or typeof(origin) ~= "Vector3"
            or typeof(direction) ~= "Vector3"
            or direction.Magnitude < SILENT_AIM_MIN_RAY_LENGTH
        then
            return nil
        end

        -- Raycast keeps the supplied origin, so the replacement direction must
        -- be calculated from that same point. Using the camera position makes
        -- the redirected ray diverge whenever the weapon fires from its muzzle.
        local targetDirection = targetPart.Position - origin

        if targetDirection.Magnitude <= 0 then
            return nil
        end

        return targetDirection.Unit * math.max(direction.Magnitude, 200)
    end

    local function installSilentAimHook()
        environment.ReverbOneTapSilentAimV3 = environment.ReverbOneTapSilentAimV3 or {}
        local hookState = environment.ReverbOneTapSilentAimV3

        hookState.Token = silentAimHookToken
        hookState.RayProvider = redirectShotRay

        if hookState.Installed then
            return true
        end

        if type(hookmetamethod) ~= "function"
            or type(getnamecallmethod) ~= "function"
        then
            hookState.RayProvider = nil
            return false
        end

        local wrapClosure = type(newcclosure) == "function"
            and newcclosure
            or function(callback)
                return callback
            end
        local unpackArguments = table.unpack or unpack
        local originalNamecall

        originalNamecall = hookmetamethod(game, "__namecall", wrapClosure(function(self, ...)
            local arguments = table.pack(...)
            local method = getnamecallmethod()

            local isExecutorCall = type(checkcaller) == "function" and checkcaller()
            if not isExecutorCall and method == "Raycast"
                and self == Workspace
                and hookState.RayProvider
            then
                local succeeded, direction = pcall(
                    hookState.RayProvider,
                    arguments[1],
                    arguments[2]
                )

                if succeeded and typeof(direction) == "Vector3" then
                    arguments[2] = direction
                end

            end

            return originalNamecall(self, unpackArguments(arguments, 1, arguments.n))
        end))

        hookState.Installed = true
        return true
    end

    RuntimeContext.Toggle(CombatSection, {
        Name = "Silent Aim",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_silent_aim",

        Callback = function(enabled)
            if enabled and not installSilentAimHook() then
                silentAimEnabled = false
                RuntimeContext.Notify(
                    "Silent Aim",
                    "This executor does not support the required hook functions."
                )
                return
            end

            silentAimEnabled = enabled
            updateSilentAimFovCircle()

            if enabled then
                rebuildSilentAimCandidates()
                watchSilentAimCandidates()
                updateSilentAimTarget()
            else
                silentAimTarget = nil
                disconnectSilentAimCandidateWatchers()
                table.clear(silentAimCandidates)

                if environment.ReverbOneTapSilentAimV3
                    and environment.ReverbOneTapSilentAimV3.Token
                        == silentAimHookToken
                then
                    environment.ReverbOneTapSilentAimV3.RayProvider = nil
                end
            end
        end,
    })

    RuntimeContext.Slider(CombatSection, {
        Name = "Silent Aim FOV",
        Range = { 50, 1000 },
        CurrentValue = silentAimFov,
        Flag = SCRIPT.id .. "_silent_aim_fov",

        Callback = function(value)
            silentAimFov = value
            updateSilentAimFovCircle()
        end,
    })

    RuntimeContext.Toggle(CombatSection, {
        Name = "Show FOV Circle",
        CurrentValue = true,
        Flag = SCRIPT.id .. "_show_silent_aim_fov",

        Callback = function(enabled)
            showSilentAimFov = enabled
            updateSilentAimFovCircle()
        end,
    })

    RuntimeContext.Dropdown(CombatSection, {
        Name = "Target Part",
        Options = {
            "Root",
            "Torso",
            "Head",
        },
        CurrentOption = silentAimTargetMode,
        Flag = SCRIPT.id .. "_silent_aim_target_part",

        Callback = function(value)
            silentAimTargetMode = value
            updateSilentAimTarget()
        end,
    })

    RuntimeContext.StartLoop("silent_aim_target", 0.05, function()
        updateSilentAimTarget()
    end, function()
        return silentAimEnabled
    end)

    RuntimeContext.AddCleanup(function()
        silentAimEnabled = false
        silentAimTarget = nil
        disconnectSilentAimCandidateWatchers()
        table.clear(silentAimCandidates)

        if silentAimFovGui then
            silentAimFovGui:Destroy()
            silentAimFovGui = nil
            silentAimFovCircle = nil
        end

        if environment.ReverbOneTapSilentAimV3
            and environment.ReverbOneTapSilentAimV3.Token == silentAimHookToken
        then
            environment.ReverbOneTapSilentAimV3.RayProvider = nil
        end
    end)

    local function getCameraCenterRay()
        local camera = Workspace.CurrentCamera

        if not camera then
            return nil, nil
        end

        local viewportSize = camera.ViewportSize
        local unitRay = camera:ViewportPointToRay(viewportSize.X / 2, viewportSize.Y / 2)

        return unitRay.Origin, unitRay.Direction * TRIGGERBOT_RANGE
    end

    local function getCameraRayTarget()
        local camera = Workspace.CurrentCamera
        local origin, direction = getCameraCenterRay()

        if not origin or not direction then
            return nil, nil, nil
        end

        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.FilterDescendantsInstances = {
            camera,
            LocalPlayer.Character,
        }

        local result = Workspace:Raycast(origin, direction, raycastParams)

        if not result then
            return nil, nil, nil
        end

        local hitPart = result.Instance
        local character = getCharacterFromPart(hitPart)

        if not character then
            return nil, nil, hitPart
        end

        local targetPlayer = findPlayerFromModel(character)

        return character, targetPlayer, hitPart
    end

    local function isValidTriggerTarget(character, targetPlayer, hitPart)
        if not character or not hitPart then
            return false
        end

        if LocalPlayer.Character and character == LocalPlayer.Character then
            return false
        end

        if not isAliveCharacter(character) then
            return false
        end

        if targetPlayer then
            if not isEnemyPlayer(targetPlayer) then
                return false
            end
        end

        return true
    end

    local function fireWeapon()
        local camera = Workspace.CurrentCamera
        if not camera then
            return false
        end
        if type(mouse1click) == "function" then
            local ok = pcall(mouse1click)
            if ok then
                return true
            end
        end
        if syn and type(syn.mouse1click) == "function" then
            local ok = pcall(syn.mouse1click)
            if ok then
                return true
            end
        end
        local viewport = camera.ViewportSize
        local input = game:GetService("VirtualInputManager")
        return pcall(function()
            input:SendMouseButtonEvent(viewport.X / 2, viewport.Y / 2, 0, true, game, 0)
            task.wait()
            input:SendMouseButtonEvent(viewport.X / 2, viewport.Y / 2, 0, false, game, 0)
        end)
    end

    local TriggerSection = MainTab:Section("Triggerbot")
    RuntimeContext.Toggle(TriggerSection, {
        Name = "Triggerbot",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_triggerbot",

        Callback = function(enabled)
            triggerbotEnabled = enabled

            if enabled then
                lastTriggerShot = 0
            end
        end,
    })

    RuntimeContext.StartLoop("triggerbot", 0.03, function()
        local now = os.clock()

        if now - lastTriggerShot < triggerbotDelay then
            return
        end

        local character, targetPlayer, hitPart = getCameraRayTarget()

        if not isValidTriggerTarget(character, targetPlayer, hitPart) then
            return
        end

        local fired = fireWeapon()

        if fired then
            lastTriggerShot = now
        end
    end, function()
        return triggerbotEnabled
    end)

    RuntimeContext.AddCleanup(function()
        triggerbotEnabled = false
    end)

    RuntimeContext.Slider(TriggerSection, {
        Name = "Trigger Delay (ms)",
        Range = { 30, 300 },
        CurrentValue = triggerbotDelay * 1000,
        Flag = SCRIPT.id .. "_triggerbot_delay",

        Callback = function(value)
            triggerbotDelay = value / 1000
        end,
    })


    -- AIMBOT: camera steering using the same Character tags as native AimAssistClient.
    local AimSection = MainTab:Section("Aimbot")
    local CollectionService = game:GetService("CollectionService")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local aimEnabled = false
    local aimActivation = UserInputService.TouchEnabled and "Touch Toggle" or "Hold RMB"
    local aimTouchActive = false
    local aimPartMode = "Head"
    local aimFov = 150
    local aimSmoothing = 45
    local aimWallCheck = true
    local aimTeamCheck = true
    local aimSticky = true
    local aimMaxDistance = 1000
    local aimShowCircle = true
    local aimPriority = "Crosshair"
    local aimModels = {}
    local aimConnections = {}
    local aimTargetModel
    local aimGui
    local aimCircle
    local aimTouchButton
    local aimTick = 0
    local aimBindingName = "Reverb_OneTap_Aimbot"
    local aimToggleControl

    local function updateAimOverlay()
        if not aimGui then return end
        aimCircle.Size = UDim2.fromOffset(aimFov * 2, aimFov * 2)
        aimCircle.Visible = aimEnabled and aimShowCircle
        aimTouchButton.Visible = aimEnabled and aimActivation == "Touch Toggle"
        aimTouchButton.Text = aimTouchActive and "Aim: ON" or "Aim: OFF"
        aimTouchButton.BackgroundColor3 = aimTouchActive
            and Color3.fromRGB(0, 226, 249) or Color3.fromRGB(13, 22, 29)
        aimTouchButton.TextColor3 = aimTouchActive
            and Color3.fromRGB(3, 9, 14) or Color3.fromRGB(237, 241, 245)
    end

    local function createAimOverlay()
        if aimGui then return end
        local parent = game:GetService("CoreGui")
        if type(gethui) == "function" then
            local ok, result = pcall(gethui)
            if ok and result then parent = result end
        end
        aimGui = Instance.new("ScreenGui")
        aimGui.Name = "ReverbOneTapAim"
        aimGui.IgnoreGuiInset = true
        aimGui.ResetOnSpawn = false
        aimGui.DisplayOrder = 20
        aimGui.Parent = parent
        aimCircle = Instance.new("Frame")
        aimCircle.AnchorPoint = Vector2.new(0.5, 0.5)
        aimCircle.Position = UDim2.fromScale(0.5, 0.5)
        aimCircle.BackgroundTransparency = 1
        aimCircle.Parent = aimGui
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = aimCircle
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(0, 226, 249)
        stroke.Thickness = 1
        stroke.Transparency = 0.25
        stroke.Parent = aimCircle
        aimTouchButton = Instance.new("TextButton")
        aimTouchButton.Size = UDim2.fromOffset(88, 44)
        aimTouchButton.AnchorPoint = Vector2.new(1, 0.5)
        aimTouchButton.Position = UDim2.new(1, -16, 0.4, 0)
        aimTouchButton.Font = Enum.Font.GothamMedium
        aimTouchButton.TextSize = 14
        aimTouchButton.Parent = aimGui
        local buttonCorner = Instance.new("UICorner")
        buttonCorner.CornerRadius = UDim.new(0, 8)
        buttonCorner.Parent = aimTouchButton
        aimTouchButton.Activated:Connect(function()
            aimTouchActive = not aimTouchActive
            aimTargetModel = nil
            updateAimOverlay()
        end)
        updateAimOverlay()
    end

    local function getAimPart(model)
        local part
        if aimPartMode == "Head" then
            part = model:FindFirstChild("Hitbox_Head") or model:FindFirstChild("Head")
        elseif aimPartMode == "Torso" then
            part = model:FindFirstChild("Hitbox_Torso") or model:FindFirstChild("Torso")
                or model:FindFirstChild("UpperTorso")
        else
            part = model:FindFirstChild("HumanoidRootPart")
        end
        return part and part:IsA("BasePart") and part or nil
    end

    local function scoreAimModel(model, camera)
        if not model.Parent or model == LocalPlayer.Character or not isAliveCharacter(model)
            or model:FindFirstChildOfClass("ForceField")
            or model:GetAttribute("deployed") == false
        then return nil end
        local player = findPlayerFromModel(model)
        if aimTeamCheck and player and LocalPlayer.Team and player.Team == LocalPlayer.Team then
            return nil
        end
        local part = getAimPart(model)
        if not part then return nil end
        local distance = (part.Position - camera.CFrame.Position).Magnitude
        if distance > aimMaxDistance or distance < 0.01 then return nil end
        local projected, onScreen = camera:WorldToViewportPoint(part.Position)
        if not onScreen or projected.Z <= 0 then return nil end
        local crosshairDistance = (Vector2.new(projected.X, projected.Y) - camera.ViewportSize / 2).Magnitude
        if crosshairDistance > aimFov then return nil end
        if aimWallCheck then
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = { camera, LocalPlayer.Character }
            local result = Workspace:Raycast(camera.CFrame.Position,
                part.Position - camera.CFrame.Position, params)
            if result and not result.Instance:IsDescendantOf(model) then return nil end
        end
        if aimPriority == "Distance" then return distance, part end
        if aimPriority == "Lowest Health" then
            return model:FindFirstChildOfClass("Humanoid").Health, part
        end
        return crosshairDistance, part
    end

    local function stopAimbot()
        aimEnabled = false
        aimTouchActive = false
        aimTargetModel = nil
        RunService:UnbindFromRenderStep(aimBindingName)
        for _, connection in ipairs(aimConnections) do connection:Disconnect() end
        table.clear(aimConnections)
        table.clear(aimModels)
        updateAimOverlay()
    end

    local function stepAimbot(delta)
        if not RuntimeContext.IsActive() or not aimEnabled then return end
        local camera = Workspace.CurrentCamera
        local character = LocalPlayer.Character
        local active = aimActivation == "Always"
            or (aimActivation == "Hold RMB" and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2))
            or (aimActivation == "Touch Toggle" and aimTouchActive)
        if not camera or not active or not character or not isAliveCharacter(character)
            or character:GetAttribute("deployed") ~= true or UserInputService:GetFocusedTextBox()
        then
            aimTargetModel = nil
            return
        end
        aimTick = aimTick + delta
        if aimTick >= 0.04 or not aimTargetModel then
            aimTick = 0
            local bestScore = math.huge
            local retained = aimSticky and aimTargetModel and scoreAimModel(aimTargetModel, camera)
            if not retained then
                aimTargetModel = nil
                for model in pairs(aimModels) do
                    if not model.Parent then
                        aimModels[model] = nil
                    else
                        local score = scoreAimModel(model, camera)
                        if score and score < bestScore then
                            bestScore = score
                            aimTargetModel = model
                        end
                    end
                end
            end
        end
        if not aimTargetModel then return end
        local score, part = scoreAimModel(aimTargetModel, camera)
        if not score or not part then aimTargetModel = nil; return end
        local alpha = aimSmoothing == 0 and 1
            or 1 - math.exp(-(2 + (100 - aimSmoothing) * 0.28) * delta)
        local desired = CFrame.lookAt(camera.CFrame.Position, part.Position)
        camera.CFrame = camera.CFrame:Lerp(desired, alpha)
    end

    aimToggleControl = RuntimeContext.Toggle(AimSection, {
        Name = "Aimbot", CurrentValue = false, Flag = SCRIPT.id .. "_aimbot",
        Callback = function(enabled)
            stopAimbot()
            if not enabled then return end
            createAimOverlay()
            for _, model in ipairs(CollectionService:GetTagged("Character")) do
                if model:IsA("Model") then aimModels[model] = true end
            end
            table.insert(aimConnections, CollectionService:GetInstanceAddedSignal("Character"):Connect(function(model)
                if model:IsA("Model") then aimModels[model] = true end
            end))
            table.insert(aimConnections, CollectionService:GetInstanceRemovedSignal("Character"):Connect(function(model)
                aimModels[model] = nil
                if aimTargetModel == model then aimTargetModel = nil end
            end))
            aimEnabled = true
            updateAimOverlay()
            RunService:BindToRenderStep(aimBindingName, Enum.RenderPriority.Camera.Value + 2, function(delta)
                local ok, err = pcall(stepAimbot, delta)
                if not ok then
                    stopAimbot()
                    if aimToggleControl then aimToggleControl:Set(false, true) end
                    RuntimeContext.Notify("Aimbot stopped", tostring(err))
                    warn("[Reverb] Aimbot failed: " .. tostring(err))
                end
            end)
        end,
    })
    RuntimeContext.Dropdown(AimSection, {
        Name = "Activation", Options = { "Hold RMB", "Always", "Touch Toggle" },
        CurrentOption = aimActivation, Flag = SCRIPT.id .. "_aim_activation",
        Callback = function(value)
            aimActivation = value; aimTouchActive = false; aimTargetModel = nil; updateAimOverlay()
        end,
    })
    RuntimeContext.Dropdown(AimSection, {
        Name = "Aim Target Part", Options = { "Head", "Torso", "Root" }, CurrentOption = aimPartMode,
        Flag = SCRIPT.id .. "_aim_part", Callback = function(value) aimPartMode = value; aimTargetModel = nil end,
    })
    RuntimeContext.Dropdown(AimSection, {
        Name = "Target Priority", Options = { "Crosshair", "Distance", "Lowest Health" },
        CurrentOption = aimPriority, Flag = SCRIPT.id .. "_aim_priority",
        Callback = function(value) aimPriority = value; aimTargetModel = nil end,
    })
    RuntimeContext.Slider(AimSection, {
        Name = "Aim FOV (px)", Range = { 25, 600 }, CurrentValue = aimFov,
        Flag = SCRIPT.id .. "_aim_fov", Callback = function(value) aimFov = value; updateAimOverlay() end,
    })
    RuntimeContext.Slider(AimSection, {
        Name = "Aim Smoothing (0 = Snap)", Range = { 0, 100 }, CurrentValue = aimSmoothing,
        Flag = SCRIPT.id .. "_aim_smoothing", Callback = function(value) aimSmoothing = value end,
    })
    RuntimeContext.Slider(AimSection, {
        Name = "Aim Max Distance", Range = { 50, 3000 }, CurrentValue = aimMaxDistance,
        Flag = SCRIPT.id .. "_aim_max_distance", Callback = function(value) aimMaxDistance = value end,
    })
    RuntimeContext.Toggle(AimSection, {
        Name = "Aim Wall Check", CurrentValue = aimWallCheck, Flag = SCRIPT.id .. "_aim_wall_check",
        Callback = function(value) aimWallCheck = value; aimTargetModel = nil end,
    })
    RuntimeContext.Toggle(AimSection, {
        Name = "Aim Team Check", CurrentValue = aimTeamCheck, Flag = SCRIPT.id .. "_aim_team_check",
        Callback = function(value) aimTeamCheck = value; aimTargetModel = nil end,
    })
    RuntimeContext.Toggle(AimSection, {
        Name = "Keep Current Target", CurrentValue = aimSticky, Flag = SCRIPT.id .. "_aim_sticky",
        Callback = function(value) aimSticky = value end,
    })
    RuntimeContext.Toggle(AimSection, {
        Name = "Show Aim FOV", CurrentValue = aimShowCircle, Flag = SCRIPT.id .. "_aim_show_fov",
        Callback = function(value) aimShowCircle = value; updateAimOverlay() end,
    })
    RuntimeContext.AddCleanup(function()
        stopAimbot()
        if aimGui then aimGui:Destroy(); aimGui = nil end
    end)
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
            "Loader routed "
                .. tostring(routedScript.id)
                .. " but this script is "
                .. SCRIPT.id
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

    local uiSource = game:HttpGet(REVERB_J_URL)
    local loadUi, compileError = loadstring(uiSource)

    if not loadUi then
        error("Reverb J failed to compile: " .. tostring(compileError))
    end

    local ReverbLib = loadUi()

    if type(ReverbLib) ~= "table" or type(ReverbLib.CreateWindow) ~= "function" then
        error("Reverb J did not return a valid library")
    end

    local Window = ReverbLib:CreateWindow({
        Game = SCRIPT.name,
        Tier = ((environment.ReverbAccess or {}).tier or environment.ReverbKeyTier)
            == "premium" and "PREMIUM" or "FREE",
        RememberSettings = false,
        ConfigName = SCRIPT.id,
    })

    Runtime.Library = ReverbLib
    Runtime.Window = Window

    Runtime.Notify = function(title, content)
        local message = content and content ~= ""
            and (tostring(title or "Reverb") .. ": " .. tostring(content))
            or tostring(title or "Reverb")
        Window:Notify(message, 5)
    end

    -- ВЫЗОВ СИСТЕМЫ ФИДБЕКА
    addFeedbackSystem(Window, ReverbLib, SCRIPT.name)

    buildGame(Runtime)

    -- Reverb J automatically adds its enabled-by-default Anti AFK toggle here.
    local SettingsTab = Window:Tab("Settings")
    SettingsTab:Section("Preferences"):Toggle(
        "Remember active settings",
        false,
        function(enabled)
            Window:SetRememberSettings(enabled)
            Window:Notify(
                enabled
                    and "Settings will now be remembered."
                    or "Settings will no longer be saved.",
                3
            )
        end
    )

    local ChangelogTab = Window:Tab("Changelog")
    local DraftSection = ChangelogTab:Section("Local Update — Testing")
    DraftSection:Label("Added Aimbot with desktop and touch activation")
    DraftSection:Label("Added ESP appearance settings and player details")
    DraftSection:Label("Silent Aim and Triggerbot retain the tested behavior")
    local ChangelogSection = ChangelogTab:Section("V1 24th July 2026")
    ChangelogSection:Label("Initial release with 7 features")

    SettingsTab:Section("Script"):Button("Unload One Tap", function()
        Runtime.Destroy()
    end)

    environment.ReverbCurrentScript = {
        metadata = SCRIPT,
        library = ReverbLib,
        window = Window,
        runtime = Runtime,
    }

    print("[Reverb] " .. SCRIPT.name .. " is ready.")
end

local succeeded, startupError = xpcall(start, function(message)
    return debug.traceback(tostring(message), 2)
end)

if not succeeded then
    Runtime.Destroy()
    error(startupError, 0)
end
