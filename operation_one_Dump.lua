-- OPERATION ONE

local SCRIPT = {
    id = "operation_one",
    name = "Operation One",
    version = "V1.3",
    updated = "6th October 2026",
    author = "Reverb",
    changelog = {
        {
            Version = "V1.3",
            Date = "6th October 2026",
            Added = {
                "New UI",
            },
        },
        {
            Version = "V1.2",
            Date = "28th September 2026",
            Added = {
                "Added ESP Opacity",
                "Fixed Broken Features",
                "Improved Device & Executor Compatibility",
            },
        },
        {
            Version = "V1.1",
            Date = "10th August 2026",
            Added = {
                "Added Skeleton ESP",
                "Improved Triggerbot",
            },
        },
        {
            Version = "V1",
            Date = "30th July 2026",
            Title = "Script Release",
        },
    },
}

----------------------------------------------------------------------------------------------------------------

local REVERB_J_URL =
    "https://raw.githubusercontent.com/rbxreverb/ReverbJ/refs/heads/main/operation-one-v1.3.lua?v=operation-one-v1.3-20261006"
local UNIVERSE_ID = 8307114974

local environment = (getgenv and getgenv()) or _G
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

function Runtime.WarnFeatureError(featureId, featureError)
    warn("[Reverb] " .. tostring(featureId) .. " failed: " .. tostring(featureError))
end

local function protectedCallback(featureId, callback)
    return function(value)
        if type(callback) ~= "function" then
            return
        end

        local succeeded, callbackError = pcall(callback, value)
        if not succeeded then
            Runtime.WarnFeatureError(featureId, callbackError)
        end
    end
end

function Runtime.AddToggle(tab, settings)
    local featureId = settings.AnalyticsId or settings.Flag or settings.Name
    local callback = settings.Callback
    settings.AnalyticsId = nil
    settings.Callback = protectedCallback(featureId, callback)
    return tab:Toggle(
        settings.Name,
        settings.CurrentValue == true,
        settings.Callback,
        settings.Flag
    )
end

function Runtime.AddSettingsToggle(tab, settings)
    local featureId = settings.AnalyticsId or settings.Flag or settings.Name
    local callback = settings.Callback
    settings.AnalyticsId = nil
    settings.Callback = protectedCallback(featureId, callback)
    return tab:SettingsToggle(
        settings.Name,
        settings.CurrentValue == true,
        settings.Callback,
        settings.Flag
    )
end

function Runtime.AddDropdown(tab, settings)
    local featureId = settings.AnalyticsId or settings.Flag or settings.Name
    local callback = settings.Callback
    settings.AnalyticsId = nil
    settings.Callback = protectedCallback(featureId, callback)
    local dropdownMethod = settings.MultipleOptions == true
        and tab.MultiDropdown
        or tab.Dropdown

    settings.MultipleOptions = nil

    return dropdownMethod(
        tab,
        settings.Name,
        settings.Options or settings.Values or {},
        settings.CurrentOption or settings.CurrentValue,
        settings.Callback,
        settings.Flag
    )
end

function Runtime.AddButton(tab, settings)
    local featureId = settings.AnalyticsId or settings.Name
    local callback = settings.Callback
    settings.AnalyticsId = nil
    settings.Callback = function()
        if type(callback) ~= "function" then
            return
        end

        local succeeded, callbackError = pcall(callback)
        if not succeeded then
            Runtime.WarnFeatureError(featureId, callbackError)
        end
    end
    return tab:Button(settings.Name, settings.Callback)
end

function Runtime.AddSlider(tab, settings)
    local featureId = settings.AnalyticsId or settings.Flag or settings.Name
    local callback = settings.Callback
    settings.AnalyticsId = nil
    settings.Callback = protectedCallback(featureId, callback)
    return tab:Slider(
        settings.Name,
        settings.Range[1],
        settings.Range[2],
        settings.CurrentValue,
        settings.Callback,
        settings.Flag
    )
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
                Runtime.WarnFeatureError(featureId, loopError)
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

-- Game-specific area.
local function buildGame(RuntimeContext)
    local MainTab = RuntimeContext.Window:Tab("Main")
    local VisualsTab = RuntimeContext.Window:Tab("Visuals")
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = Players.LocalPlayer

    local MainSection = MainTab:Section("Main")
    local VisualsSection = VisualsTab:Section("Visuals")

    local espEnabled = false
    local boxEspEnabled = true
    local nameEspEnabled = false
    local distanceEspEnabled = false
    local healthEspEnabled = false
    local tracerEspEnabled = false
    local headDotEspEnabled = false
    local skeletonEspEnabled = false
    local offscreenArrowEspEnabled = false
    local espOpacity = 1
    local playerConnections = {}
    local trackedPlayers = {}
    local characterConnections = {}
    local resolvedCharacters = {}
    local characterRetryAt = {}
    local resolvedVisualRigs = {}
    local visualRigRetryAt = {}
    local visualRigOwners = setmetatable({}, { __mode = "k" })
    local visualRigOwnerValues = setmetatable({}, { __mode = "k" })
    local localRaycastFilterCache = {}
    local localRaycastFilterDirty = true
    local cachedLocalCharacter = nil
    local drawings = {}
    local espGui
    -- Some mobile executors expose a partial Drawing API that passes a simple
    -- construction test but renders at the wrong viewport offset. Roblox GUI
    -- objects use the same viewport as WorldToViewportPoint, so prefer them on
    -- touch devices and retain Drawing for desktop executors.
    local useGuiEspRenderer = UserInputService.TouchEnabled
        or type(Drawing) ~= "table"
        or type(Drawing.new) ~= "function"

    local VISUAL_BODY_PART_NAMES = {
        "head",
        "torso",
        "shoulder1",
        "shoulder2",
        "arm1",
        "arm2",
        "hip1",
        "hip2",
        "leg1",
        "leg2",
    }
    local VISUAL_RIG_MATCH_DISTANCE = 7
    local VISUAL_RIG_CACHE_DISTANCE = 10

    local ENEMY_COLOR = Color3.fromRGB(255, 70, 70)
    local OUTLINE_COLOR = Color3.fromRGB(15, 15, 18)
    local wallbangClassification = setmetatable({}, {
        __mode = "k",
    })

    local function hasHumanoidAncestor(instance)
        local current = instance

        while current and current ~= Workspace do
            if current:IsA("Model")
                and current:FindFirstChildOfClass("Humanoid")
            then
                return true
            end
            current = current.Parent
        end

        return false
    end

    local function getNearbyAttribute(instance, attributeName)
        local current = instance
        local depth = 0

        while current and current ~= Workspace and depth <= 2 do
            local value = current:GetAttribute(attributeName)
            if value ~= nil then
                return value
            end
            current = current.Parent
            depth += 1
        end

        return nil
    end

    local function isWallbangablePart(instance)
        if not instance or not instance:IsA("BasePart") then
            return false
        end

        local cached = wallbangClassification[instance]
        if cached ~= nil then
            return cached
        end

        local viewmodels = Workspace:FindFirstChild("Viewmodels")
        if viewmodels and instance:IsDescendantOf(viewmodels) then
            wallbangClassification[instance] = false
            return false
        end

        if hasHumanoidAncestor(instance) then
            wallbangClassification[instance] = false
            return false
        end

        local soft = getNearbyAttribute(instance, "Soft")
        -- Health/Weak only mean that the object can be destroyed. Operation
        -- One also uses those attributes for reinforced or explosive-only
        -- surfaces. Only the explicit Soft flag identifies bullet-passable
        -- geometry for triggerbot line-of-sight.
        local result = soft == true
        wallbangClassification[instance] = result
        return result
    end

    local function anyEspEnabled()
        return espEnabled
            and (
                boxEspEnabled
                or nameEspEnabled
                or distanceEspEnabled
                or healthEspEnabled
                or tracerEspEnabled
                or headDotEspEnabled
                or skeletonEspEnabled
                or offscreenArrowEspEnabled
            )
    end

    local function disconnect(connection)
        if connection then
            connection:Disconnect()
        end
    end

    local function clearPlayerConnections(player)
        local connections = trackedPlayers[player]
        if not connections then
            return
        end

        for _, connection in ipairs(connections) do
            disconnect(connection)
        end

        trackedPlayers[player] = nil
    end

    local function clearCharacterConnection(player)
        disconnect(characterConnections[player])
        characterConnections[player] = nil
    end

    local function removeDrawing(player)
        local entry = drawings[player]
        if entry then
            for _, object in pairs(entry) do
                if type(object) == "table" and object.Remove == nil then
                    for _, nestedObject in ipairs(object) do
                        pcall(function()
                            nestedObject:Remove()
                        end)
                    end
                else
                    pcall(function()
                        object:Remove()
                    end)
                end
            end
            drawings[player] = nil
        end
    end

    local function isEnemy(player)
        local localTeam = LocalPlayer.Team and LocalPlayer.Team.Name
            or LocalPlayer:GetAttribute("Team")
        local playerTeam = player.Team and player.Team.Name
            or player:GetAttribute("Team")

        if not localTeam or not playerTeam then
            return false
        end

        return playerTeam ~= localTeam
    end

    local function modelBelongsToPlayer(model, player)
        if not model or not model:IsA("Model") then
            return false
        end

        if model == player.Character then
            return true
        end

        if tonumber(model:GetAttribute("UserId")) == player.UserId then
            return true
        end

        local stateObject = model:FindFirstChild("StateObject")
        local owner = stateObject and stateObject:FindFirstChild("owner")
        if owner and owner:IsA("ObjectValue") and owner.Value == player then
            return true
        end

        return model.Name == player.Name
            or model.Name == player.DisplayName
    end

    local function isLiveWorkspaceCharacter(model)
        if not model or not model:IsDescendantOf(Workspace) then
            return false
        end

        local humanoid = model:FindFirstChildOfClass("Humanoid")
        local root = model:FindFirstChild("HumanoidRootPart")

        return humanoid ~= nil
            and humanoid.Health > 0
            and root ~= nil
            and root:IsA("BasePart")
    end

    local function findLiveCharacter(player)
        local expectedTeam = player.Team and player.Team.Name
            or player:GetAttribute("Team")
        local cachedCharacter = resolvedCharacters[player]

        if cachedCharacter
            and modelBelongsToPlayer(cachedCharacter, player)
            and isLiveWorkspaceCharacter(cachedCharacter)
            and (
                not expectedTeam
                or cachedCharacter:GetAttribute("Team") == expectedTeam
            )
        then
            return cachedCharacter
        end

        resolvedCharacters[player] = nil
        if (characterRetryAt[player] or 0) > os.clock() then
            return nil
        end
        local bestCharacter = nil
        local bestScore = -math.huge

        -- Operation One can keep several models with the same UserId in
        -- Workspace. Lobby/targeter clones have no Team or ID, while the real
        -- combat actor has both. Player.Character frequently points at a clone,
        -- so score every matching model rather than trusting that reference.
        for _, child in ipairs(Workspace:GetChildren()) do
            if child:IsA("Model")
                and modelBelongsToPlayer(child, player)
                and isLiveWorkspaceCharacter(child)
            then
                local modelTeam = child:GetAttribute("Team")
                local modelId = child:GetAttribute("ID")
                local score = 0

                if expectedTeam and modelTeam == expectedTeam then
                    score += 100
                elseif modelTeam ~= nil then
                    score += 10
                end

                if modelId ~= nil then
                    score += 50
                end

                if child.Name == player.Name then
                    score += 25
                elseif child.Name == player.DisplayName then
                    score += 15
                end

                if child == player.Character then
                    score += 5
                end

                if score > bestScore then
                    bestScore = score
                    bestCharacter = child
                end
            end
        end

        -- A model without the replicated combat Team is a lobby mannequin,
        -- spectator target, or stale clone. Do not draw it.
        if bestCharacter
            and expectedTeam
            and bestCharacter:GetAttribute("Team") ~= expectedTeam
        then
            characterRetryAt[player] = os.clock() + 0.15
            return nil
        end

        if not bestCharacter then
            characterRetryAt[player] = os.clock() + 0.15
            return nil
        end

        characterRetryAt[player] = nil
        resolvedCharacters[player] = bestCharacter
        return bestCharacter
    end

    local function buildLocalRaycastFilter()
        if cachedLocalCharacter ~= LocalPlayer.Character then
            localRaycastFilterDirty = true
        end

        if localRaycastFilterDirty then
            local filter = {}
            local included = {}
            local function include(instance)
                if instance and not included[instance] then
                    included[instance] = true
                    table.insert(filter, instance)
                end
            end

            -- Ignore only our first-person weapon/body. Enemy Viewmodels are
            -- the rendered player bodies and must remain queryable so a LOS
            -- ray can finish on the visible target instead of the wall behind
            -- them.
            local viewmodels = Workspace:FindFirstChild("Viewmodels")
            include(viewmodels and viewmodels:FindFirstChild("LocalViewmodel"))
            for _, child in ipairs(Workspace:GetChildren()) do
                if child:IsA("Model")
                    and modelBelongsToPlayer(child, LocalPlayer)
                then
                    include(child)
                end
            end
            include(LocalPlayer.Character)

            localRaycastFilterCache = filter
            cachedLocalCharacter = LocalPlayer.Character
            localRaycastFilterDirty = false
        end

        return table.clone(localRaycastFilterCache)
    end

    local function clearVisualRig(player)
        local visualRig = resolvedVisualRigs[player]
        if visualRig and visualRigOwners[visualRig] == player then
            visualRigOwners[visualRig] = nil
        end
        resolvedVisualRigs[player] = nil
    end

    local function getVisualRigCenter(visualRig)
        local torso = visualRig and visualRig:FindFirstChild("torso")
        if torso and torso:IsA("BasePart") then
            return torso.Position
        end
        return nil
    end

    local function isValidVisualRig(visualRig)
        local viewmodels = Workspace:FindFirstChild("Viewmodels")
        if not viewmodels
            or not visualRig
            or not visualRig:IsA("Model")
            or visualRig.Parent ~= viewmodels
            or visualRig.Name == "LocalViewmodel"
            or visualRig:GetAttribute("Viewmodels") ~= true
        then
            return false
        end

        local validPartCount = 0
        for _, partName in ipairs(VISUAL_BODY_PART_NAMES) do
            local part = visualRig:FindFirstChild(partName)
            if part and part:IsA("BasePart") then
                validPartCount += 1
            end
        end

        local head = visualRig:FindFirstChild("head")
        local torso = visualRig:FindFirstChild("torso")
        return validPartCount >= 8
            and head ~= nil
            and head:IsA("BasePart")
            and torso ~= nil
            and torso:IsA("BasePart")
    end

    local function getVisualRigOwnerCharacter(visualRig)
        if not visualRig then
            return nil
        end

        local cachedOwnerValue = visualRigOwnerValues[visualRig]
        if cachedOwnerValue
            and cachedOwnerValue.Parent
            and cachedOwnerValue:IsDescendantOf(visualRig)
        then
            local cachedOwner = cachedOwnerValue.Value
            return cachedOwner and cachedOwner:IsA("Model")
                and cachedOwner
                or nil
        end

        -- Operation One stores the authoritative combat-character reference at
        -- <equipped item>.StateObject.owner. This survives lean, crouch, prone,
        -- and camera motion, unlike matching the animated rig by proximity.
        for _, descendant in ipairs(visualRig:GetDescendants()) do
            if descendant:IsA("ObjectValue")
                and descendant.Name == "owner"
                and descendant.Parent
                and descendant.Parent.Name == "StateObject"
            then
                local owner = descendant.Value
                if owner and owner:IsA("Model") then
                    visualRigOwnerValues[visualRig] = descendant
                    return owner
                end
            end
        end

        return nil
    end

    local function visualRigMatchesPlayer(visualRig, player, character)
        local ownerCharacter = getVisualRigOwnerCharacter(visualRig)
        if ownerCharacter then
            return ownerCharacter == character
                or modelBelongsToPlayer(ownerCharacter, player)
        end
        return nil
    end

    local function findVisualRig(player, character)
        local root = character
            and character:FindFirstChild("HumanoidRootPart")
        if not root or not root:IsA("BasePart") then
            clearVisualRig(player)
            return nil
        end

        local cached = resolvedVisualRigs[player]
        if isValidVisualRig(cached) then
            local cachedMatch = visualRigMatchesPlayer(cached, player, character)
            local cachedCenter = getVisualRigCenter(cached)
            if cachedMatch == true
                or (
                    cachedMatch == nil
                    and cachedCenter
                    and (cachedCenter - root.Position).Magnitude
                        <= VISUAL_RIG_CACHE_DISTANCE
                )
            then
                return cached
            end
        end
        clearVisualRig(player)

        if (visualRigRetryAt[player] or 0) > os.clock() then
            return nil
        end

        local viewmodels = Workspace:FindFirstChild("Viewmodels")
        if not viewmodels then
            visualRigRetryAt[player] = os.clock() + 0.2
            return nil
        end

        local bestRig = nil
        local bestDistance = VISUAL_RIG_MATCH_DISTANCE
        for _, candidate in ipairs(viewmodels:GetChildren()) do
            if isValidVisualRig(candidate) then
                local ownerMatch = visualRigMatchesPlayer(
                    candidate,
                    player,
                    character
                )
                if ownerMatch == true then
                    bestRig = candidate
                    break
                end

                -- Never claim a rig whose replicated owner identifies another
                -- player. Distance is used only for temporarily ownerless rigs.
                if ownerMatch == nil
                    and visualRigOwners[candidate] == nil
                then
                    local center = getVisualRigCenter(candidate)
                    local distance = center
                        and (center - root.Position).Magnitude
                        or math.huge
                    if distance <= bestDistance then
                        bestDistance = distance
                        bestRig = candidate
                    end
                end
            end
        end

        if bestRig then
            resolvedVisualRigs[player] = bestRig
            visualRigOwners[bestRig] = player
            visualRigRetryAt[player] = nil
        else
            visualRigRetryAt[player] = os.clock() + 0.2
        end
        return bestRig
    end

    -- Mobile executors frequently omit the Drawing API. These small adapters
    -- expose the Drawing properties used below while rendering with Roblox UI.
    local function getEspGui()
        if espGui and espGui.Parent then
            return espGui
        end

        espGui = Instance.new("ScreenGui")
        espGui.Name = "ReverbOperationOneEsp"
        espGui.IgnoreGuiInset = true
        espGui.ResetOnSpawn = false
        espGui.DisplayOrder = 999
        espGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        espGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
        return espGui
    end

    local function createGuiDrawing(kind)
        local instance
        if kind == "Text" then
            instance = Instance.new("TextLabel")
            instance.AnchorPoint = Vector2.new(0.5, 0.5)
            instance.BackgroundTransparency = 1
            instance.Font = Enum.Font.SourceSansBold
            instance.TextStrokeTransparency = 0
            instance.Size = UDim2.fromOffset(200, 20)
        else
            instance = Instance.new("Frame")
            instance.AnchorPoint = Vector2.new(0.5, 0.5)
            instance.BorderSizePixel = 0
            if kind == "Circle" then
                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(1, 0)
                corner.Parent = instance
            end
        end
        instance.Visible = false
        instance.Parent = getEspGui()

        local properties = {}
        local object = {}
        function object:Remove()
            instance:Destroy()
        end

        return setmetatable(object, {
            __index = function(_, key)
                return properties[key]
            end,
            __newindex = function(_, key, value)
                properties[key] = value
                if key == "Visible" then
                    instance.Visible = value
                elseif key == "Color" then
                    if kind == "Text" then
                        instance.TextColor3 = value
                    else
                        instance.BackgroundColor3 = value
                    end
                elseif key == "Transparency" then
                    local transparency = 1 - math.clamp(value, 0, 1)
                    if kind == "Text" then
                        instance.TextTransparency = transparency
                    else
                        instance.BackgroundTransparency = transparency
                    end
                elseif key == "ZIndex" then
                    instance.ZIndex = value
                elseif key == "From" or key == "To" then
                    local from = key == "From" and value or properties.From
                    local to = key == "To" and value or properties.To
                    if from and to then
                        local delta = to - from
                        instance.Position = UDim2.fromOffset(
                            (from.X + to.X) * 0.5,
                            (from.Y + to.Y) * 0.5
                        )
                        instance.Size = UDim2.fromOffset(
                            delta.Magnitude,
                            properties.Thickness or 1
                        )
                        instance.Rotation = math.deg(math.atan2(delta.Y, delta.X))
                    end
                elseif key == "Thickness" and kind == "Line" then
                    instance.Size = UDim2.fromOffset(instance.AbsoluteSize.X, value)
                elseif key == "Position" then
                    instance.Position = UDim2.fromOffset(value.X, value.Y)
                elseif key == "Radius" and kind == "Circle" then
                    instance.Size = UDim2.fromOffset(value * 2, value * 2)
                elseif key == "Text" then
                    instance.Text = value
                elseif key == "Size" and kind == "Text" then
                    instance.TextSize = value
                    instance.Size = UDim2.fromOffset(240, value + 6)
                elseif key == "OutlineColor" and kind == "Text" then
                    instance.TextStrokeColor3 = value
                elseif key == "Outline" and kind == "Text" then
                    instance.TextStrokeTransparency = value and 0 or 1
                end
            end,
        })
    end

    local function createDrawingLine(color, thickness)
        if useGuiEspRenderer then
            local line = createGuiDrawing("Line")
            line.Color = color
            line.Thickness = thickness
            line.Transparency = espOpacity
            line.ZIndex = thickness >= 5 and 9 or 10
            line.Visible = false
            return line
        end

        local line = Drawing.new("Line")
        line.Color = color
        line.Thickness = thickness
        line.Transparency = espOpacity
        line.ZIndex = thickness >= 5 and 9 or 10
        line.Visible = false
        return line
    end

    local function createDrawingCircle(color)
        if useGuiEspRenderer then
            local circle = createGuiDrawing("Circle")
            circle.Color = color
            circle.Transparency = espOpacity
            circle.Radius = 4
            circle.ZIndex = 11
            circle.Visible = false
            return circle
        end

        local circle = Drawing.new("Circle")
        circle.Color = color
        circle.Thickness = 1
        circle.Filled = true
        circle.Transparency = espOpacity
        circle.Radius = 4
        circle.NumSides = 24
        circle.ZIndex = 11
        circle.Visible = false
        return circle
    end

    local function createDrawingText()
        if useGuiEspRenderer then
            local text = createGuiDrawing("Text")
            text.Color = Color3.fromRGB(245, 245, 245)
            text.Outline = true
            text.OutlineColor = OUTLINE_COLOR
            text.Size = 13
            text.Transparency = espOpacity
            text.ZIndex = 10
            text.Visible = false
            return text
        end

        local text = Drawing.new("Text")
        text.Color = Color3.fromRGB(245, 245, 245)
        text.Center = true
        text.Outline = true
        text.OutlineColor = OUTLINE_COLOR
        text.Size = 13
        text.Font = 2
        text.Transparency = espOpacity
        text.ZIndex = 10
        text.Visible = false
        return text
    end

    local function getOrCreateDrawing(player)
        local entry = drawings[player]
        if entry then
            return entry
        end

        local boxOutlineLines = {}
        local boxLines = {}
        for _ = 1, 4 do
            table.insert(boxOutlineLines, createDrawingLine(OUTLINE_COLOR, 4))
            table.insert(boxLines, createDrawingLine(ENEMY_COLOR, 2))
        end
        local healthOutline = createDrawingLine(OUTLINE_COLOR, 6)
        local healthBar = createDrawingLine(Color3.fromRGB(70, 255, 90), 3)
        local tracerOutline = createDrawingLine(OUTLINE_COLOR, 4)
        local tracer = createDrawingLine(ENEMY_COLOR, 2)
        local headDot = createDrawingCircle(ENEMY_COLOR)
        local arrowLeft = createDrawingLine(ENEMY_COLOR, 2)
        local arrowRight = createDrawingLine(ENEMY_COLOR, 2)
        local arrowBase = createDrawingLine(ENEMY_COLOR, 2)
        local label = createDrawingText()
        local skeletonLines = {}
        for _ = 1, 15 do
            table.insert(
                skeletonLines,
                createDrawingLine(ENEMY_COLOR, 2)
            )
        end

        entry = {
            boxOutlineLines = boxOutlineLines,
            boxLines = boxLines,
            healthOutline = healthOutline,
            healthBar = healthBar,
            tracerOutline = tracerOutline,
            tracer = tracer,
            headDot = headDot,
            arrowLeft = arrowLeft,
            arrowRight = arrowRight,
            arrowBase = arrowBase,
            label = label,
            skeletonLines = skeletonLines,
        }
        drawings[player] = entry
        return entry
    end

    local function refreshEspOpacity()
        for _, entry in pairs(drawings) do
            for _, object in pairs(entry) do
                if type(object) == "table" and object.Remove == nil then
                    for _, nestedObject in ipairs(object) do
                        nestedObject.Transparency = espOpacity
                    end
                else
                    object.Transparency = espOpacity
                end
            end
        end
    end

    local function hideDrawing(player)
        local entry = drawings[player]
        if entry then
            for _, object in pairs(entry) do
                if type(object) == "table" and object.Remove == nil then
                    for _, nestedObject in ipairs(object) do
                        nestedObject.Visible = false
                    end
                else
                    object.Visible = false
                end
            end
        end
    end

    local function updateBoxLines(lines, position, size, color, visible)
        local topLeft = position
        local topRight = position + Vector2.new(size.X, 0)
        local bottomRight = position + size
        local bottomLeft = position + Vector2.new(0, size.Y)
        local corners = {
            { topLeft, topRight },
            { topRight, bottomRight },
            { bottomRight, bottomLeft },
            { bottomLeft, topLeft },
        }

        for index, line in ipairs(lines) do
            line.From = corners[index][1]
            line.To = corners[index][2]
            line.Color = color
            line.Visible = visible
        end
    end

    local BODY_PART_NAMES = {
        "Head",
        "UpperTorso",
        "LowerTorso",
        "Torso",
        "HumanoidRootPart",
        "legs",
        "LeftUpperArm",
        "LeftLowerArm",
        "LeftHand",
        "RightUpperArm",
        "RightLowerArm",
        "RightHand",
        "Left Arm",
        "Right Arm",
        "LeftUpperLeg",
        "LeftLowerLeg",
        "LeftFoot",
        "RightUpperLeg",
        "RightLowerLeg",
        "RightFoot",
        "Left Leg",
        "Right Leg",
    }

    local function getBodyParts(character, visualRig)
        local parts = {}
        local seen = {}

        if isValidVisualRig(visualRig) then
            for _, name in ipairs(VISUAL_BODY_PART_NAMES) do
                local part = visualRig:FindFirstChild(name)
                if part and part:IsA("BasePart") then
                    seen[part] = true
                    table.insert(parts, part)
                end
            end
            if #parts >= 8 then
                return parts
            end
            table.clear(parts)
            table.clear(seen)
        end

        for _, name in ipairs(BODY_PART_NAMES) do
            local part = character:FindFirstChild(name)
            if part and part:IsA("BasePart") and not seen[part] then
                seen[part] = true
                table.insert(parts, part)
            end
        end

        return parts
    end

    local function getCharacterStateValue(character, valueName)
        local state = character:FindFirstChild("Character")
        local value = state and state:FindFirstChild(valueName)
        if value and value:IsA("ValueBase") then
            return value.Value
        end
        return nil
    end

    local function getOperationOneHeadPosition(character, root)
        local head = character:FindFirstChild("Head")
        if head and head:IsA("BasePart") then
            return head.Position
        end

        local walkState = getCharacterStateValue(character, "walk_state")
        local lean = tonumber(getCharacterStateValue(character, "lean")) or 0
        local heightScale = walkState == "crouch" and 0.72 or 1
        local verticalOffset = ((root.Size.Y * 0.5) - 0.25) * heightScale

        return root.Position
            + (root.CFrame.UpVector * verticalOffset)
            + (root.CFrame.RightVector * math.clamp(lean, -1, 1) * 0.38)
    end

    local function getPartScreenBounds(camera, part)
        local half = part.Size * 0.5
        local minimumX = math.huge
        local minimumY = math.huge
        local maximumX = -math.huge
        local maximumY = -math.huge
        local projectedCount = 0

        for x = -1, 1, 2 do
            for y = -1, 1, 2 do
                for z = -1, 1, 2 do
                    local worldPoint = part.CFrame:PointToWorldSpace(
                        Vector3.new(half.X * x, half.Y * y, half.Z * z)
                    )
                    local screenPoint = camera:WorldToViewportPoint(worldPoint)
                    if screenPoint.Z > 0 then
                        projectedCount += 1
                        minimumX = math.min(minimumX, screenPoint.X)
                        minimumY = math.min(minimumY, screenPoint.Y)
                        maximumX = math.max(maximumX, screenPoint.X)
                        maximumY = math.max(maximumY, screenPoint.Y)
                    end
                end
            end
        end

        if projectedCount == 0 then
            return nil
        end

        return minimumX, minimumY, maximumX, maximumY
    end

    local function getScreenBounds(
        character,
        visualRig,
        allowVisualFallbackExpansion
    )
        local camera = Workspace.CurrentCamera
        if not camera then
            return nil
        end

        local bodyParts = getBodyParts(character, visualRig)
        if #bodyParts == 0 then
            return nil
        end
        local minimumX = math.huge
        local minimumY = math.huge
        local maximumX = -math.huge
        local maximumY = -math.huge
        local projectedCount = 0

        for _, part in ipairs(bodyParts) do
            local partMinimumX, partMinimumY, partMaximumX, partMaximumY =
                getPartScreenBounds(camera, part)
            if partMinimumX then
                projectedCount += 1
                minimumX = math.min(minimumX, partMinimumX)
                minimumY = math.min(minimumY, partMinimumY)
                maximumX = math.max(maximumX, partMaximumX)
                maximumY = math.max(maximumY, partMaximumY)
            end
        end

        if projectedCount == 0 then
            return nil
        end

        local viewport = camera.ViewportSize
        minimumX = math.clamp(minimumX, 0, viewport.X)
        minimumY = math.clamp(minimumY, 0, viewport.Y)
        maximumX = math.clamp(maximumX, 0, viewport.X)
        maximumY = math.clamp(maximumY, 0, viewport.Y)

        local width = maximumX - minimumX
        local height = maximumY - minimumY
        if width < 2 or height < 2 then
            return nil
        end

        -- Operation One's replicated rig is an unusually narrow invisible
        -- hitbox (1.5 studs wide and 7 studs tall with `legs`). Give its 2D box
        -- a player-shaped minimum width instead of drawing a pencil-thin box.
        if allowVisualFallbackExpansion
            and not visualRig
            and character:FindFirstChild("legs")
            and not character:FindFirstChild("Head")
        then
            local desiredWidth = height * 0.42
            if width < desiredWidth then
                local centerX = (minimumX + maximumX) * 0.5
                minimumX = math.clamp(centerX - (desiredWidth * 0.5), 0, viewport.X)
                maximumX = math.clamp(centerX + (desiredWidth * 0.5), 0, viewport.X)
                width = maximumX - minimumX
            end
        end

        return Vector2.new(minimumX, minimumY), Vector2.new(width, height)
    end

    local SKELETON_CHAINS = {
        { "Head", "UpperTorso", "LowerTorso" },
        { "Head", "Torso" },
        { "UpperTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand" },
        { "UpperTorso", "RightUpperArm", "RightLowerArm", "RightHand" },
        { "Torso", "Left Arm" },
        { "Torso", "Right Arm" },
        { "LowerTorso", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" },
        { "LowerTorso", "RightUpperLeg", "RightLowerLeg", "RightFoot" },
        { "Torso", "Left Leg" },
        { "Torso", "Right Leg" },
    }

    local VISUAL_SKELETON_CHAINS = {
        { "head", "torso" },
        { "torso", "shoulder1", "arm1" },
        { "torso", "shoulder2", "arm2" },
        { "torso", "hip1", "leg1" },
        { "torso", "hip2", "leg2" },
    }

    local function updateSkeleton(entry, character, camera, visualRig)
        local lineIndex = 1

        local function drawSegment(fromPosition, toPosition)
            local line = entry.skeletonLines[lineIndex]
            if not line then
                return
            end

            local fromPoint, fromOnScreen =
                camera:WorldToViewportPoint(fromPosition)
            local toPoint, toOnScreen =
                camera:WorldToViewportPoint(toPosition)

            line.From = Vector2.new(fromPoint.X, fromPoint.Y)
            line.To = Vector2.new(toPoint.X, toPoint.Y)
            line.Color = ENEMY_COLOR
            line.Visible = skeletonEspEnabled
                and fromOnScreen
                and toOnScreen
                and fromPoint.Z > 0
                and toPoint.Z > 0
            lineIndex += 1
        end

        if isValidVisualRig(visualRig) then
            for _, chain in ipairs(VISUAL_SKELETON_CHAINS) do
                for index = 1, #chain - 1 do
                    local fromPart = visualRig:FindFirstChild(chain[index])
                    local toPart = visualRig:FindFirstChild(chain[index + 1])
                    if fromPart and toPart
                        and fromPart:IsA("BasePart")
                        and toPart:IsA("BasePart")
                    then
                        drawSegment(fromPart.Position, toPart.Position)
                    end
                end
            end

            for index = lineIndex, #entry.skeletonLines do
                entry.skeletonLines[index].Visible = false
            end
            return
        end

        for _, chain in ipairs(SKELETON_CHAINS) do
            for index = 1, #chain - 1 do
                local fromPart = character:FindFirstChild(chain[index])
                local toPart = character:FindFirstChild(chain[index + 1])
                local line = entry.skeletonLines[lineIndex]

                if line and fromPart and toPart
                    and fromPart:IsA("BasePart")
                    and toPart:IsA("BasePart")
                then
                    drawSegment(fromPart.Position, toPart.Position)
                end
            end
        end

        -- Operation One's replicated combat rig has no Head, arms, torso, or
        -- normal R6/R15 limbs. It exposes a five-stud HumanoidRootPart plus a
        -- lowercase `legs` hitbox. Draw the replicated hitbox orientation when
        -- no standard skeleton segments were available.
        if lineIndex == 1 then
            local root = character:FindFirstChild("HumanoidRootPart")
            local legs = character:FindFirstChild("legs")
            if root and root:IsA("BasePart") then
                local up = root.CFrame.UpVector
                local right = root.CFrame.RightVector
                local look = getCharacterStateValue(character, "look")
                local walkState = getCharacterStateValue(character, "walk_state")
                local lean = tonumber(getCharacterStateValue(character, "lean")) or 0
                local crouchScale = walkState == "crouch" and 0.72 or 1
                local leanOffset = right * math.clamp(lean, -1, 1) * 0.38
                local halfHeight = root.Size.Y * 0.5
                local halfWidth = math.max(root.Size.X * 0.48, 0.55)
                local head = getOperationOneHeadPosition(character, root)
                local neck = root.Position
                    + (up * (halfHeight - 0.9) * crouchScale)
                    + leanOffset
                local chest = root.Position
                    + (up * 0.55 * crouchScale)
                    + (leanOffset * 0.75)
                local pelvis = root.Position - (up * (halfHeight - 0.25))
                local leftShoulder = chest - (right * halfWidth)
                local rightShoulder = chest + (right * halfWidth)
                local aimDirection = typeof(look) == "Vector3"
                    and look.Magnitude > 0.01
                    and look.Unit
                    or root.CFrame.LookVector
                local leftHand = leftShoulder
                    + (aimDirection * 1.05)
                    - (up * 0.35)
                local rightHand = rightShoulder
                    + (aimDirection * 1.25)
                    - (up * 0.25)
                local legCenter = legs and legs:IsA("BasePart")
                    and legs.Position
                    or (pelvis - (up * 1.2))
                local leftFoot = legCenter - (up * 0.9) - (right * 0.38)
                local rightFoot = legCenter - (up * 0.9) + (right * 0.38)

                drawSegment(head, neck)
                drawSegment(neck, chest)
                drawSegment(chest, pelvis)
                drawSegment(leftShoulder, rightShoulder)
                drawSegment(leftShoulder, leftHand)
                drawSegment(rightShoulder, rightHand)
                drawSegment(pelvis, leftFoot)
                drawSegment(pelvis, rightFoot)
            end
        end

        for index = lineIndex, #entry.skeletonLines do
            entry.skeletonLines[index].Visible = false
        end
    end

    local function updatePlayerCham(player)
        if not anyEspEnabled()
            or player == LocalPlayer
            or player.Parent ~= Players
            or not isEnemy(player)
        then
            removeDrawing(player)
            return
        end

        local character = findLiveCharacter(player)

        if not character then
            hideDrawing(player)
            return
        end

        local camera = Workspace.CurrentCamera
        local root = character:FindFirstChild("HumanoidRootPart")
        if not camera or not root then
            hideDrawing(player)
            return
        end

        local rootPoint, rootOnScreen =
            camera:WorldToViewportPoint(root.Position)
        local visualRig = findVisualRig(player, character)
        local position, size = getScreenBounds(character, visualRig, true)
        if not position or not rootOnScreen then
            hideDrawing(player)

            if not offscreenArrowEspEnabled then
                return
            end

            local entry = getOrCreateDrawing(player)
            local viewport = camera.ViewportSize
            local center = viewport * 0.5
            local direction = Vector2.new(
                rootPoint.X - center.X,
                rootPoint.Y - center.Y
            )

            if rootPoint.Z < 0 then
                direction = -direction
            end
            if direction.Magnitude < 0.001 then
                direction = Vector2.new(0, -1)
            else
                direction = direction.Unit
            end

            local radius = math.min(viewport.X, viewport.Y) * 0.42
            local tip = center + (direction * radius)
            local baseCenter = tip - (direction * 15)
            local perpendicular = Vector2.new(-direction.Y, direction.X)
            local left = baseCenter + (perpendicular * 7)
            local right = baseCenter - (perpendicular * 7)

            entry.arrowLeft.From = tip
            entry.arrowLeft.To = left
            entry.arrowLeft.Visible = true
            entry.arrowRight.From = tip
            entry.arrowRight.To = right
            entry.arrowRight.Visible = true
            entry.arrowBase.From = left
            entry.arrowBase.To = right
            entry.arrowBase.Visible = true
            return true
        end

        local entry = getOrCreateDrawing(player)
        if not entry then
            return
        end

        updateBoxLines(
            entry.boxOutlineLines,
            position,
            size,
            OUTLINE_COLOR,
            boxEspEnabled
        )
        updateBoxLines(
            entry.boxLines,
            position,
            size,
            ENEMY_COLOR,
            boxEspEnabled
        )
        entry.arrowLeft.Visible = false
        entry.arrowRight.Visible = false
        entry.arrowBase.Visible = false

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local healthRatio = humanoid
            and math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
            or 0
        local barX = position.X - 6
        local barBottom = position.Y + size.Y
        local barTop = position.Y
        local filledTop = barBottom - (size.Y * healthRatio)

        entry.healthOutline.From = Vector2.new(barX, barBottom)
        entry.healthOutline.To = Vector2.new(barX, barTop)
        entry.healthOutline.Visible = healthEspEnabled

        entry.healthBar.From = Vector2.new(barX, barBottom)
        entry.healthBar.To = Vector2.new(barX, filledTop)
        entry.healthBar.Color = Color3.fromRGB(
            math.floor(255 * (1 - healthRatio)),
            math.floor(255 * healthRatio),
            70
        )
        entry.healthBar.Visible = healthEspEnabled

        local viewport = camera.ViewportSize
        local tracerFrom = Vector2.new(viewport.X * 0.5, viewport.Y - 2)
        local tracerTo = Vector2.new(
            position.X + (size.X * 0.5),
            position.Y + size.Y
        )

        entry.tracerOutline.From = tracerFrom
        entry.tracerOutline.To = tracerTo
        entry.tracerOutline.Visible = tracerEspEnabled

        entry.tracer.From = tracerFrom
        entry.tracer.To = tracerTo
        entry.tracer.Color = ENEMY_COLOR
        entry.tracer.Visible = tracerEspEnabled

        local visualHead = visualRig and visualRig:FindFirstChild("head")
        local headPosition = visualHead and visualHead:IsA("BasePart")
            and visualHead.Position
            or getOperationOneHeadPosition(character, root)
        if headDotEspEnabled then
            local headPoint, headOnScreen =
                camera:WorldToViewportPoint(headPosition)

            entry.headDot.Position = Vector2.new(
                headPoint.X,
                headPoint.Y
            )
            entry.headDot.Visible = headOnScreen and headPoint.Z > 0
        else
            entry.headDot.Visible = false
        end

        updateSkeleton(entry, character, camera, visualRig)

        local labelParts = {}
        if nameEspEnabled then
            table.insert(labelParts, player.DisplayName)
        end
        if distanceEspEnabled and camera then
            local root = character:FindFirstChild("HumanoidRootPart")
            if root then
                local distance = (root.Position - camera.CFrame.Position).Magnitude
                table.insert(labelParts, tostring(math.floor(distance + 0.5)) .. "m")
            end
        end

        entry.label.Text = table.concat(labelParts, " | ")
        entry.label.Position = Vector2.new(
            position.X + (size.X * 0.5),
            position.Y - 17
        )
        entry.label.Visible = #labelParts > 0
        return true
    end

    local function watchCharacter(player, character)
        clearCharacterConnection(player)
        resolvedCharacters[player] = nil
        characterRetryAt[player] = nil
        clearVisualRig(player)
        visualRigRetryAt[player] = nil

        if not character then
            return
        end

        characterConnections[player] = character.AncestryChanged:Connect(function()
            task.defer(function()
                if RuntimeContext.IsActive() and anyEspEnabled() then
                    updatePlayerCham(player)
                end
            end)
        end)

        task.defer(function()
            character:WaitForChild("Humanoid", 5)
            if RuntimeContext.IsActive() and anyEspEnabled() then
                updatePlayerCham(player)
            end
        end)
    end

    local function watchPlayer(player)
        if player == LocalPlayer or trackedPlayers[player] then
            return
        end

        trackedPlayers[player] = {
            player.CharacterAdded:Connect(function(character)
                watchCharacter(player, character)
            end),
            player.CharacterRemoving:Connect(function()
                clearCharacterConnection(player)
                resolvedCharacters[player] = nil
                characterRetryAt[player] = nil
                clearVisualRig(player)
                visualRigRetryAt[player] = nil
                removeDrawing(player)
            end),
            player:GetPropertyChangedSignal("Team"):Connect(function()
                updatePlayerCham(player)
            end),
            player:GetPropertyChangedSignal("Neutral"):Connect(function()
                updatePlayerCham(player)
            end),
        }

        watchCharacter(player, player.Character)
        updatePlayerCham(player)
    end

    local function clearAllChams()
        for player in pairs(drawings) do
            removeDrawing(player)
        end
    end

    local function refreshAllChams()
        local liveTargetCount = 0

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                watchPlayer(player)
                if updatePlayerCham(player) then
                    liveTargetCount += 1
                end
            end
        end

        return liveTargetCount
    end

    table.insert(playerConnections, Players.PlayerAdded:Connect(function(player)
        watchPlayer(player)
    end))

    table.insert(playerConnections, Players.PlayerRemoving:Connect(function(player)
        removeDrawing(player)
        resolvedCharacters[player] = nil
        characterRetryAt[player] = nil
        clearVisualRig(player)
        visualRigRetryAt[player] = nil
        clearCharacterConnection(player)
        clearPlayerConnections(player)
    end))

    table.insert(playerConnections, Workspace.ChildAdded:Connect(function(child)
        localRaycastFilterDirty = true
        if not anyEspEnabled() or not child:IsA("Model") then
            return
        end

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and modelBelongsToPlayer(child, player) then
                task.defer(function()
                    child:WaitForChild("Humanoid", 3)
                    if not RuntimeContext.IsActive() then
                        return
                    end
                    resolvedCharacters[player] = nil
                    characterRetryAt[player] = nil
                    visualRigRetryAt[player] = nil
                    updatePlayerCham(player)
                end)
                break
            end
        end
    end))

    table.insert(playerConnections, Workspace.ChildRemoved:Connect(function()
        localRaycastFilterDirty = true
    end))

    table.insert(playerConnections, LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function()
        refreshAllChams()
    end))

    table.insert(playerConnections, LocalPlayer:GetPropertyChangedSignal("Neutral"):Connect(function()
        refreshAllChams()
    end))

    for _, player in ipairs(Players:GetPlayers()) do
        watchPlayer(player)
    end

    local drawingWarningShown = false
    local drawingCapabilityChecked = false
    local drawingCapabilitySupported = false
    local drawingCapabilityReason = nil
    local espRenderErrorReported = false

    local function drawingSupported()
        if drawingCapabilityChecked then
            return drawingCapabilitySupported, drawingCapabilityReason
        end

        drawingCapabilityChecked = true
        if useGuiEspRenderer then
            local succeeded, failure = pcall(getEspGui)
            drawingCapabilitySupported = succeeded
            if not succeeded then
                drawingCapabilityReason = "Mobile GUI renderer failed: "
                    .. tostring(failure)
            end
            return drawingCapabilitySupported, drawingCapabilityReason
        end

        local testObjects = {}
        local succeeded, failure = pcall(function()
            table.insert(testObjects, Drawing.new("Line"))
            table.insert(testObjects, Drawing.new("Circle"))
            table.insert(testObjects, Drawing.new("Text"))

            testObjects[1].From = Vector2.new(0, 0)
            testObjects[1].To = Vector2.new(1, 1)
            testObjects[2].Radius = 1
            testObjects[3].Text = "Reverb"

        end)

        for _, object in ipairs(testObjects) do
            pcall(function()
                object.Visible = false
                object:Remove()
            end)
        end

        drawingCapabilitySupported = succeeded
        if not succeeded then
            useGuiEspRenderer = true
            local fallbackSucceeded, fallbackFailure = pcall(getEspGui)
            drawingCapabilitySupported = fallbackSucceeded
            if not fallbackSucceeded then
                drawingCapabilityReason = "Drawing primitives and mobile GUI renderer failed: "
                    .. tostring(failure)
                    .. " / "
                    .. tostring(fallbackFailure)
            end
        end

        return drawingCapabilitySupported, drawingCapabilityReason
    end

    local function refreshEspSettings()
        if anyEspEnabled() then
            refreshAllChams()
        else
            clearAllChams()
        end
    end

    local espControl
    local espSettingsPanel
    espControl, espSettingsPanel =
        RuntimeContext.AddSettingsToggle(VisualsSection, {
        Name = "Enemy ESP",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_enemy_esp",
        AnalyticsId = "enemy_esp",
        Callback = function(enabled)
            espEnabled = enabled
            espRenderErrorReported = false

            local supported, unsupportedReason = drawingSupported()
            if enabled and not supported then
                espEnabled = false
                if not drawingWarningShown then
                    drawingWarningShown = true
                    RuntimeContext.Notify(
                        "Enemy ESP",
                        unsupportedReason
                            or "Your executor does not support Drawing visuals."
                    )
                end
                task.defer(function()
                    if espControl then
                        espControl:Set(false)
                    end
                end)
                return
            end

            if anyEspEnabled() then
                refreshAllChams()
            else
                clearAllChams()
            end
        end,
        })

    RuntimeContext.AddToggle(espSettingsPanel, {
        Name = "Boxes",
        CurrentValue = true,
        Flag = SCRIPT.id .. "_esp_boxes",
        AnalyticsId = "esp_boxes",
        Callback = function(enabled)
            boxEspEnabled = enabled
            refreshEspSettings()
        end,
    })

    RuntimeContext.AddSlider(espSettingsPanel, {
        Name = "ESP Opacity",
        Range = { 10, 100 },
        CurrentValue = 100,
        Flag = SCRIPT.id .. "_esp_opacity",
        AnalyticsId = "esp_opacity",
        Callback = function(value)
            espOpacity = math.clamp((tonumber(value) or 100) / 100, 0.1, 1)
            refreshEspOpacity()
        end,
    })

    RuntimeContext.AddToggle(espSettingsPanel, {
        Name = "Names",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_esp_names",
        AnalyticsId = "esp_names",
        Callback = function(enabled)
            nameEspEnabled = enabled
            refreshEspSettings()
        end,
    })

    RuntimeContext.AddToggle(espSettingsPanel, {
        Name = "Health Bar",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_esp_health",
        AnalyticsId = "esp_health",
        Callback = function(enabled)
            healthEspEnabled = enabled
            refreshEspSettings()
        end,
    })

    RuntimeContext.AddToggle(espSettingsPanel, {
        Name = "Distance",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_esp_distance",
        AnalyticsId = "esp_distance",
        Callback = function(enabled)
            distanceEspEnabled = enabled
            refreshEspSettings()
        end,
    })

    RuntimeContext.AddToggle(espSettingsPanel, {
        Name = "Skeleton",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_esp_skeleton",
        AnalyticsId = "esp_skeleton",
        Callback = function(enabled)
            skeletonEspEnabled = enabled
            refreshEspSettings()
        end,
    })

    RuntimeContext.AddToggle(espSettingsPanel, {
        Name = "Head Dot",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_esp_head_dot",
        AnalyticsId = "esp_head_dot",
        Callback = function(enabled)
            headDotEspEnabled = enabled
            refreshEspSettings()
        end,
    })

    RuntimeContext.AddToggle(espSettingsPanel, {
        Name = "Tracers",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_esp_tracers",
        AnalyticsId = "esp_tracers",
        Callback = function(enabled)
            tracerEspEnabled = enabled
            refreshEspSettings()
        end,
    })

    RuntimeContext.AddToggle(espSettingsPanel, {
        Name = "Offscreen Arrows",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_esp_offscreen_arrows",
        AnalyticsId = "esp_offscreen_arrows",
        Callback = function(enabled)
            offscreenArrowEspEnabled = enabled
            refreshEspSettings()
        end,
    })

    local ESP_RENDER_STEP = "ReverbOperationOneEsp"
    RunService:BindToRenderStep(
        ESP_RENDER_STEP,
        Enum.RenderPriority.Camera.Value + 1,
        function()
            if anyEspEnabled() then
                local succeeded, espError = pcall(refreshAllChams)
                if not succeeded and not espRenderErrorReported then
                    espRenderErrorReported = true
                    RuntimeContext.WarnFeatureError("enemy_esp", espError)
                end
            end
        end
    )

    RuntimeContext.AddCleanup(function()
        espEnabled = false
        boxEspEnabled = false
        nameEspEnabled = false
        distanceEspEnabled = false
        healthEspEnabled = false
        tracerEspEnabled = false
        headDotEspEnabled = false
        skeletonEspEnabled = false
        offscreenArrowEspEnabled = false
        espRenderErrorReported = false
        RunService:UnbindFromRenderStep(ESP_RENDER_STEP)
        clearAllChams()
        if espGui then
            espGui:Destroy()
            espGui = nil
        end

        for player in pairs(trackedPlayers) do
            clearCharacterConnection(player)
            clearPlayerConnections(player)
        end

        for _, connection in ipairs(playerConnections) do
            disconnect(connection)
        end

        table.clear(playerConnections)
        table.clear(resolvedCharacters)
        table.clear(characterRetryAt)
        table.clear(resolvedVisualRigs)
        table.clear(visualRigRetryAt)
        table.clear(visualRigOwners)
    end)

    ----------------------------------------------------------------------------------------------------------------
    -- AIM

    local aimAssistEnabled = false
    local aimbotEnabled = false
    local aimActivation = "Always Active (PC/Mobile)"
    local aimTargetPart = "Closest"
    local aimVisibilityCheck = false
    local showAimFov = true
    local aimFov = 100
    local aimAssistStrength = 15
    local aimbotSpeed = 50
    local rightMouseHeld = false
    local aimRenderErrorReported = false
    local aimInputConnections = {}
    local aimFovCircle = nil
    local aimFovGui = nil
    local aimFovGuiCircle = nil
    local aimAssistControl = nil
    local aimbotControl = nil
    local AIM_RENDER_STEP = "ReverbOperationOneAim"

    local function aimIsActive()
        if not aimAssistEnabled and not aimbotEnabled then
            return false
        end

        return aimActivation == "Always Active (PC/Mobile)"
            or (
                aimActivation == "Hold Right Mouse (PC)"
                and rightMouseHeld
            )
    end

    local function getAimPoints(character, visualRig)
        local root = character:FindFirstChild("HumanoidRootPart")
        if not root then
            return {}
        end

        -- Captured successful shots register against lowercase animated body
        -- parts (for example `head`). Use the matched rendered rig so lean and
        -- peeking move the aim point with the body. Keep combat positions as a
        -- fallback while the visual rig is being created or remapped.
        local visualHead = visualRig and visualRig:FindFirstChild("head")
        local visualTorso = visualRig and visualRig:FindFirstChild("torso")
        local torsoPosition = visualTorso
            and visualTorso:IsA("BasePart")
            and visualTorso.Position
            or root.Position
        local headPosition = visualHead
            and visualHead:IsA("BasePart")
            and visualHead.Position
            or getOperationOneHeadPosition(character, root)

        if aimTargetPart == "Head" then
            return { headPosition }
        elseif aimTargetPart == "Torso" then
            return { torsoPosition }
        end

        return {
            headPosition,
            torsoPosition,
        }
    end

    local function hasAimLineOfSight(
        character,
        visualRig,
        targetPosition
    )
        if not aimVisibilityCheck then
            return true
        end

        local camera = Workspace.CurrentCamera
        if not camera or not targetPosition then
            return false
        end

        local origin = camera.CFrame.Position
        local direction = targetPosition - origin
        local filter = buildLocalRaycastFilter()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local softObstructionCount = 0

        for _ = 1, 8 do
            params.FilterDescendantsInstances = filter

            local result = Workspace:Raycast(origin, direction, params)
            if not result
                or result.Instance:IsDescendantOf(character)
                or (
                    visualRig
                    and result.Instance:IsDescendantOf(visualRig)
                )
            then
                return true
            end

            local hit = result.Instance
            local isSoftObstruction = isWallbangablePart(hit)
            local isHelper = hit:IsA("BasePart")
                and not isSoftObstruction
                and (
                    hit.Transparency >= 0.65
                    or not hit.CanCollide
                )

            if isSoftObstruction then
                softObstructionCount += 1
                -- The game's ray_damage path supports one Soft hit before the
                -- player. A second soft obstruction exhausts penetration.
                if softObstructionCount > 1 then
                    return false
                end
            elseif not isHelper then
                return false
            end

            table.insert(filter, hit)
        end

        return false
    end

    local function getPlayerAimCandidate(
        player,
        camera,
        crosshair,
        fovLimit
    )
        if player == LocalPlayer
            or player.Parent ~= Players
            or not isEnemy(player)
        then
            return nil
        end

        local character = findLiveCharacter(player)
        local root = character
            and character:FindFirstChild("HumanoidRootPart")
        if not root then
            return nil
        end
        local visualRig = findVisualRig(player, character)

        local bestPosition = nil
        local bestScreenDistance = math.huge
        for _, targetPosition in ipairs(getAimPoints(character, visualRig)) do
            local screenPoint, onScreen =
                camera:WorldToViewportPoint(targetPosition)

            if onScreen and screenPoint.Z > 0 then
                local screenDistance = (
                    Vector2.new(screenPoint.X, screenPoint.Y)
                    - crosshair
                ).Magnitude

                if screenDistance <= fovLimit
                    and screenDistance < bestScreenDistance
                    and hasAimLineOfSight(
                        character,
                        visualRig,
                        targetPosition
                    )
                then
                    bestScreenDistance = screenDistance
                    bestPosition = targetPosition
                end
            end
        end

        if not bestPosition then
            return nil
        end

        return bestPosition, bestScreenDistance
    end

    local function getBestAimTarget()
        local camera = Workspace.CurrentCamera
        if not camera then
            return nil
        end

        local viewport = camera.ViewportSize
        local crosshair = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)

        local bestPosition = nil
        local bestPlayer = nil
        local bestScore = math.huge

        for _, player in ipairs(Players:GetPlayers()) do
            local position, score = getPlayerAimCandidate(
                player,
                camera,
                crosshair,
                aimFov
            )
            if position and score < bestScore then
                bestScore = score
                bestPosition = position
                bestPlayer = player
            end
        end

        return bestPosition, bestPlayer
    end

    local function updateAimFovCircle()
        local camera = Workspace.CurrentCamera
        local visible = showAimFov
            and (aimAssistEnabled or aimbotEnabled)
            and camera ~= nil

        if aimFovCircle then
            aimFovCircle.Visible = visible and aimFovGuiCircle == nil
        end
        if aimFovGuiCircle then
            aimFovGuiCircle.Visible = visible
        end
        if visible then
            local viewport = camera.ViewportSize
            if aimFovCircle and not aimFovGuiCircle then
                aimFovCircle.Position = Vector2.new(
                    viewport.X * 0.5,
                    viewport.Y * 0.5
                )
                aimFovCircle.Radius = aimFov
            end
            if aimFovGuiCircle then
                aimFovGuiCircle.Position = UDim2.fromOffset(
                    viewport.X * 0.5,
                    viewport.Y * 0.5
                )
                aimFovGuiCircle.Size = UDim2.fromOffset(
                    aimFov * 2,
                    aimFov * 2
                )
            end
        end
    end

    if UserInputService.TouchEnabled then
        pcall(function()
            aimFovGui = Instance.new("ScreenGui")
            aimFovGui.Name = "ReverbOperationOneAimFov"
            aimFovGui.IgnoreGuiInset = true
            aimFovGui.ResetOnSpawn = false
            aimFovGui.DisplayOrder = 1000
            aimFovGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

            aimFovGuiCircle = Instance.new("Frame")
            aimFovGuiCircle.Name = "Circle"
            aimFovGuiCircle.AnchorPoint = Vector2.new(0.5, 0.5)
            aimFovGuiCircle.BackgroundTransparency = 1
            aimFovGuiCircle.Visible = false
            aimFovGuiCircle.Parent = aimFovGui

            local round = Instance.new("UICorner")
            round.CornerRadius = UDim.new(1, 0)
            round.Parent = aimFovGuiCircle

            local circleStroke = Instance.new("UIStroke")
            circleStroke.Color = Color3.fromRGB(0, 174, 255)
            circleStroke.Thickness = 1
            circleStroke.Transparency = 0.35
            circleStroke.Parent = aimFovGuiCircle
        end)
    end

    if type(Drawing) == "table" and type(Drawing.new) == "function" then
        local circle
        local succeeded = pcall(function()
            circle = Drawing.new("Circle")
            circle.Color = Color3.fromRGB(0, 174, 255)
            circle.Thickness = 1
            circle.Filled = false
            circle.Transparency = 0.65
            circle.NumSides = 64
            circle.Visible = false
        end)
        if succeeded then
            aimFovCircle = circle
        elseif circle then
            pcall(function()
                circle:Remove()
            end)
        end
    end

    table.insert(
        aimInputConnections,
        UserInputService.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton2 then
                rightMouseHeld = true
            end
        end)
    )
    table.insert(
        aimInputConnections,
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton2 then
                rightMouseHeld = false
            end
        end)
    )

    local aimbotSettingsPanel
    aimbotControl, aimbotSettingsPanel =
        RuntimeContext.AddSettingsToggle(MainSection, {
        Name = "Aimbot",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_aimbot",
        AnalyticsId = "aimbot",
        Callback = function(enabled)
            aimbotEnabled = enabled
            aimRenderErrorReported = false
            if enabled and aimAssistControl and aimAssistEnabled then
                aimAssistControl:Set(false)
            end
            updateAimFovCircle()
        end,
        })

    local aimAssistSettingsPanel
    aimAssistControl, aimAssistSettingsPanel =
        RuntimeContext.AddSettingsToggle(MainSection, {
        Name = "Aim Assist",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_aim_assist",
        AnalyticsId = "aim_assist",
        Callback = function(enabled)
            aimAssistEnabled = enabled
            aimRenderErrorReported = false
            if enabled and aimbotControl and aimbotEnabled then
                aimbotControl:Set(false)
            end
            updateAimFovCircle()
        end,
        })

    local aimSettingControls = {}
    local function registerSyncedAimControl(key, control)
        aimSettingControls[key] = aimSettingControls[key] or {}
        table.insert(aimSettingControls[key], control)
        return control
    end

    local function syncAimSetting(key, source, value)
        for _, control in ipairs(aimSettingControls[key] or {}) do
            if control ~= source then
                control:Set(value, true)
            end
        end
    end

    local function buildAimSettings(panel, prefix, mode)
        local control

        control = RuntimeContext.AddToggle(panel, {
            Name = "Wall Check",
            CurrentValue = false,
            Flag = SCRIPT.id .. "_" .. prefix .. "_wall_check",
            AnalyticsId = prefix .. "_wall_check",
            Callback = function(enabled)
                aimVisibilityCheck = enabled
                syncAimSetting("wall_check", nil, enabled)
            end,
        })
        registerSyncedAimControl("wall_check", control)

        control = RuntimeContext.AddToggle(panel, {
            Name = "Show Aim FOV",
            CurrentValue = true,
            Flag = SCRIPT.id .. "_" .. prefix .. "_show_fov",
            AnalyticsId = prefix .. "_show_fov",
            Callback = function(enabled)
                showAimFov = enabled
                syncAimSetting("show_fov", nil, enabled)
                updateAimFovCircle()
            end,
        })
        registerSyncedAimControl("show_fov", control)

        control = RuntimeContext.AddDropdown(panel, {
            Name = "Activation",
            Options = {
                "Always Active (PC/Mobile)",
                "Hold Right Mouse (PC)",
            },
            CurrentOption = "Always Active (PC/Mobile)",
            Flag = SCRIPT.id .. "_" .. prefix .. "_activation",
            AnalyticsId = prefix .. "_activation",
            Callback = function(value)
                aimActivation = value
                syncAimSetting("activation", nil, value)
            end,
        })
        registerSyncedAimControl("activation", control)

        control = RuntimeContext.AddDropdown(panel, {
            Name = "Aim Target",
            Options = {
                "Closest",
                "Head",
                "Torso",
            },
            CurrentOption = "Closest",
            Flag = SCRIPT.id .. "_" .. prefix .. "_target",
            AnalyticsId = prefix .. "_target",
            Callback = function(value)
                aimTargetPart = value
                syncAimSetting("target", nil, value)
            end,
        })
        registerSyncedAimControl("target", control)

        control = RuntimeContext.AddSlider(panel, {
            Name = "Aim FOV",
            Range = { 30, 300 },
            CurrentValue = 100,
            Flag = SCRIPT.id .. "_" .. prefix .. "_fov",
            AnalyticsId = prefix .. "_fov",
            Callback = function(value)
                aimFov = value
                syncAimSetting("fov", nil, value)
                updateAimFovCircle()
            end,
        })
        registerSyncedAimControl("fov", control)

        if mode == "assist" then
            RuntimeContext.AddSlider(panel, {
                Name = "Assist Strength",
                Range = { 1, 30 },
                CurrentValue = 15,
                Flag = SCRIPT.id .. "_aim_assist_strength",
                AnalyticsId = "aim_assist_strength",
                Callback = function(value)
                    aimAssistStrength = value
                end,
            })
        else
            RuntimeContext.AddSlider(panel, {
                Name = "Aimbot Speed",
                Range = { 10, 100 },
                CurrentValue = 50,
                Flag = SCRIPT.id .. "_aimbot_speed",
                AnalyticsId = "aimbot_speed",
                Callback = function(value)
                    aimbotSpeed = value
                end,
            })
        end
    end

    buildAimSettings(aimAssistSettingsPanel, "aim_assist", "assist")
    buildAimSettings(aimbotSettingsPanel, "aimbot", "aimbot")

    local function updateAim(deltaTime)
        updateAimFovCircle()
        if not aimIsActive() then
            return
        end

        local camera = Workspace.CurrentCamera
        local target = getBestAimTarget()
        if not camera or not target then
            return
        end

        local desired = CFrame.lookAt(
            camera.CFrame.Position,
            target,
            camera.CFrame.UpVector
        )
        local strength = aimbotEnabled
            and (aimbotSpeed / 100)
            or (aimAssistStrength / 100)
        local frameRateAdjustedStrength = 1 - math.pow(
            1 - math.clamp(strength, 0.01, 1),
            math.clamp(deltaTime or (1 / 60), 0, 0.1) * 60
        )

        camera.CFrame = camera.CFrame:Lerp(
            desired,
            frameRateAdjustedStrength
        )
    end

    RunService:BindToRenderStep(
        AIM_RENDER_STEP,
        Enum.RenderPriority.Last.Value,
        function(deltaTime)
            if aimAssistEnabled or aimbotEnabled then
                local succeeded, aimError = pcall(updateAim, deltaTime)
                if not succeeded and not aimRenderErrorReported then
                    aimRenderErrorReported = true
                    RuntimeContext.WarnFeatureError("aim", aimError)
                end
            else
                if aimFovCircle then
                    aimFovCircle.Visible = false
                end
                if aimFovGuiCircle then
                    aimFovGuiCircle.Visible = false
                end
            end
        end
    )

    RuntimeContext.AddCleanup(function()
        aimAssistEnabled = false
        aimbotEnabled = false
        rightMouseHeld = false
        aimRenderErrorReported = false
        RunService:UnbindFromRenderStep(AIM_RENDER_STEP)

        for _, connection in ipairs(aimInputConnections) do
            disconnect(connection)
        end
        table.clear(aimInputConnections)

        if aimFovCircle then
            pcall(function()
                aimFovCircle:Remove()
            end)
            aimFovCircle = nil
        end
        if aimFovGui then
            aimFovGui:Destroy()
            aimFovGui = nil
            aimFovGuiCircle = nil
        end
    end)

    ----------------------------------------------------------------------------------------------------------------
    -- TRIGGERBOT

    local triggerbotEnabled = false
    local triggerbotWallbangEnabled = false
    local lastTriggerShot = 0
    local TRIGGERBOT_RANGE = 5000
    local TRIGGERBOT_FALLBACK_DELAY = 0.08
    local function getCurrentGunConfiguration()
        local viewmodels = Workspace:FindFirstChild("Viewmodels")
        local localViewmodel = viewmodels
            and viewmodels:FindFirstChild("LocalViewmodel")
        if not localViewmodel then
            return nil
        end

        for _, child in ipairs(localViewmodel:GetChildren()) do
            if child:IsA("Model") then
                local gun = child:FindFirstChild("Gun")
                if gun and gun:IsA("Configuration") then
                    return gun
                end
            end
        end

        return localViewmodel:FindFirstChild("Gun", true)
    end

    local function getGunValue(gun, valueName)
        local value = gun and gun:FindFirstChild(valueName)
        if value and value:IsA("ValueBase") then
            return value.Value
        end
        return nil
    end

    local function getTriggerShotDelay()
        local gun = getCurrentGunConfiguration()
        local fireRate = tonumber(getGunValue(gun, "firerate"))
        if fireRate and fireRate > 0 then
            return math.clamp(60 / fireRate, 0.03, 1.5)
        end
        return TRIGGERBOT_FALLBACK_DELAY
    end

    local function currentGunCanFire()
        local gun = getCurrentGunConfiguration()
        if not gun then
            return true
        end

        local loaded = getGunValue(gun, "loaded")
        local chambered = getGunValue(gun, "chambered")
        local magazine = tonumber(getGunValue(gun, "mag"))
        local bullets = tonumber(getGunValue(gun, "bullets"))

        if loaded == false or chambered == false then
            return false
        end
        if magazine and magazine <= 0 then
            return false
        end
        if magazine == nil and bullets and bullets <= 0 then
            return false
        end
        return true
    end

    local function buildTriggerRaycastFilter()
        return buildLocalRaycastFilter()
    end

    local function hasTriggerLineOfSight(character, visualRig)
        local camera = Workspace.CurrentCamera
        if not camera or not character then
            return false
        end

        local origin = camera.CFrame.Position
        -- Triggerbot fires at the centre crosshair, so its visibility ray must
        -- use that exact direction. Rays aimed at estimated body centres can
        -- strike a window frame even while the real crosshair is through the
        -- Soft glass pane.
        local direction = camera.CFrame.LookVector * TRIGGERBOT_RANGE
        local filter = buildTriggerRaycastFilter()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local softObstructionCount = 0

        -- Operation One uses transparent, non-collidable helper parts
        -- throughout its maps. Skip those and explicit Soft surfaces while
        -- preserving the same crosshair sightline.
        for _ = 1, 12 do
            params.FilterDescendantsInstances = filter

            local result = Workspace:Raycast(origin, direction, params)
            if not result then
                return false
            end

            if result.Instance:IsDescendantOf(character)
                or (
                    visualRig
                    and result.Instance:IsDescendantOf(visualRig)
                )
            then
                return true
            end

            local hit = result.Instance
            local wallbangable = isWallbangablePart(hit)
            if wallbangable then
                softObstructionCount += 1
                if not triggerbotWallbangEnabled
                    or softObstructionCount > 1
                then
                    return false
                end
            end
            local canSkip = hit:IsA("BasePart")
                and (
                    wallbangable
                    or (
                        not wallbangable
                        and (
                            hit.Transparency >= 0.65
                            or not hit.CanCollide
                        )
                    )
                )

            if not canSkip then
                return false
            end

            table.insert(filter, hit)
        end

        return false
    end

    local function getCrosshairEnemy()
        local camera = Workspace.CurrentCamera
        if not camera then
            return nil
        end

        local viewport = camera.ViewportSize
        local crosshair = Vector2.new(
            viewport.X * 0.5,
            viewport.Y * 0.5
        )
        local bestPlayer = nil
        local bestCharacter = nil
        local bestDistance = math.huge

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and isEnemy(player) then
                local character = findLiveCharacter(player)
                local root = character
                    and character:FindFirstChild("HumanoidRootPart")

                if character and root then
                    local visualRig = findVisualRig(player, character)
                    local worldDistance = (
                        root.Position - camera.CFrame.Position
                    ).Magnitude

                    if worldDistance <= TRIGGERBOT_RANGE then
                        local position, size = getScreenBounds(
                            character,
                            visualRig,
                            true
                        )

                        if position and size then
                            local insideBounds =
                                crosshair.X >= position.X
                                and crosshair.X <= position.X + size.X
                                and crosshair.Y >= position.Y
                                and crosshair.Y <= position.Y + size.Y

                            if insideBounds
                                and hasTriggerLineOfSight(character, visualRig)
                            then
                                local center = position + (size * 0.5)
                                local screenDistance = (
                                    center - crosshair
                                ).Magnitude

                                if screenDistance < bestDistance then
                                    bestDistance = screenDistance
                                    bestPlayer = player
                                    bestCharacter = character
                                end
                            end
                        end
                    end
                end
            end
        end

        return bestPlayer, bestCharacter
    end

    local function clickPrimaryFire()
        if not UserInputService.TouchEnabled
            and type(mouse1click) == "function"
        then
            local succeeded = pcall(mouse1click)
            if succeeded then
                return true
            end
        end

        if not UserInputService.TouchEnabled
            and type(syn) == "table"
            and type(syn.mouse1click) == "function"
        then
            local succeeded = pcall(syn.mouse1click)
            if succeeded then
                return true
            end
        end

        local camera = Workspace.CurrentCamera
        if not camera then
            return false
        end

        local clickPosition = camera.ViewportSize * 0.5
        if UserInputService.TouchEnabled then
            local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if playerGui then
                for _, descendant in ipairs(playerGui:GetDescendants()) do
                    if descendant:IsA("GuiButton")
                        and descendant.Name == "ShootLeftButton"
                        and descendant.Visible
                        and descendant.AbsoluteSize.X > 0
                        and descendant.AbsoluteSize.Y > 0
                    then
                        clickPosition = descendant.AbsolutePosition
                            + (descendant.AbsoluteSize * 0.5)
                        break
                    end
                end
            end
        end
        local VirtualInputManager = game:GetService("VirtualInputManager")

        return pcall(function()
            VirtualInputManager:SendMouseButtonEvent(
                clickPosition.X,
                clickPosition.Y,
                0,
                true,
                game,
                0
            )
            task.wait()
            VirtualInputManager:SendMouseButtonEvent(
                clickPosition.X,
                clickPosition.Y,
                0,
                false,
                game,
                0
            )
        end)
    end

    local triggerbotControl
    local triggerSettingsPanel
    triggerbotControl, triggerSettingsPanel =
        RuntimeContext.AddSettingsToggle(MainSection, {
        Name = "Triggerbot",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_triggerbot",
        AnalyticsId = "triggerbot",
        Callback = function(enabled)
            triggerbotEnabled = enabled
            lastTriggerShot = 0
        end,
        })

    RuntimeContext.AddToggle(triggerSettingsPanel, {
        Name = "Shoot Through Soft Walls",
        CurrentValue = false,
        Flag = SCRIPT.id .. "_triggerbot_wallbang",
        AnalyticsId = "triggerbot_wallbang",
        Callback = function(enabled)
            triggerbotWallbangEnabled = enabled
        end,
    })

    RuntimeContext.StartLoop("triggerbot", 0.03, function()
        local now = os.clock()
        if now - lastTriggerShot < getTriggerShotDelay() then
            return
        end

        if not currentGunCanFire() then
            return
        end

        if not getCrosshairEnemy() then
            return
        end

        if clickPrimaryFire() then
            lastTriggerShot = now
        end
    end, function()
        return triggerbotEnabled
    end)

    RuntimeContext.AddCleanup(function()
        triggerbotEnabled = false
        triggerbotWallbangEnabled = false
    end)
end

local function queueConnectedPlaceLoader()
    if game.GameId ~= UNIVERSE_ID then
        return false, "wrong_universe"
    end

    local key = environment.script_key
    if type(key) ~= "string"
        or (
            key:match("^REVERB%-FREE%-[%w_-]+$") == nil
            and key:match("^REVERB%-PREM%-[%w_-]+$") == nil
        )
    then
        return false, "missing_key"
    end

    local queueTeleport
    pcall(function()
        queueTeleport = queue_on_teleport
            or queueonteleport
            or (syn and syn.queue_on_teleport)
            or (fluxus and fluxus.queue_on_teleport)
    end)
    if type(queueTeleport) ~= "function" then
        return false, "unsupported_executor"
    end

    local loaderConfig = environment.ReverbLoaderConfig
    local source = type(loaderConfig) == "table"
        and tostring(loaderConfig.source or "operation_one_teleport")
        or "operation_one_teleport"
    source = source:lower():gsub("[^%w_-]", ""):sub(1, 40)
    if source == "" then
        source = "operation_one_teleport"
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
if game.GameId == %d then
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
]], UNIVERSE_ID, key, loaderUrl)

    local queued, queueError = pcall(queueTeleport, queuedSource)
    if not queued then
        warn("[Reverb] Could not queue teleport loader: " .. tostring(queueError))
        return false, "queue_failed"
    end

    return true
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
        Version = SCRIPT.version,
        Tier = accountSettings().IsPremium and "PREMIUM" or "FREE",
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

    local teleportQueued, teleportQueueReason = queueConnectedPlaceLoader()
    if not teleportQueued and teleportQueueReason == "unsupported_executor" then
        Runtime.Notify(
            "Automatic Loading",
            "Your executor cannot automatically load Reverb after teleports."
        )
    end

    buildGame(Runtime)

    local SettingsTab = Window:Tab("Settings")
    SettingsTab:Section("Preferences"):Toggle(
        "Remember active settings",
        false,
        function(enabled)
            Window:SetRememberSettings(enabled)
        end
    )

    if type(Window.CreateChangelogTab) == "function" then
        Window:CreateChangelogTab({
            Name = "Changelog",
            ScriptName = SCRIPT.name,
            Entries = SCRIPT.changelog,
        })
    else
        -- Compatibility with older Reverb J builds without changelog helpers.
        local ChangelogTab = Window:Tab("Changelog")
        ChangelogTab:Section("V1.2 28th September 2026"):Label(
            "NEW FEATURES\n"
                .. "- ESP opacity control\n"
                .. "- Touch-safe GUI ESP renderer\n"
                .. "\n"
                .. "IMPROVEMENTS\n"
                .. "- Improved ESP\n"
                .. "- Improved compatibility\n"
                .. "- Improved triggerbot"
        )
        ChangelogTab:Section("V1.1 10th August 2026"):Label(
            "NEW FEATURES\n"
                .. "- Skeleton ESP\n"
                .. "\n"
                .. "IMPROVEMENTS\n"
                .. "- Improved all ESP features\n"
                .. "- Improved Triggerbot"
        )
        ChangelogTab:Section("V1 30th July 2026")
            :Label("Initial release with 11 features")
    end

    SettingsTab:Section("Script"):Button("Unload Operation One", function()
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
