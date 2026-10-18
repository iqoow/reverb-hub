-- +1 Mog Evolution

local SCRIPT = {
    id = "1MogEvolution",
    name = "+1 Mog Evolution",
}

local REVERB_J_URL =
    "https://raw.githubusercontent.com/rbxreverb/ReverbJ/refs/heads/main/source.lua?v=remember-settings-20260812"

local environment = (getgenv and getgenv()) or _G
local instanceToken = {}
local destroyed = false
local autoGetAppealEnabled = false
local autoRebirthEnabled = false
local autoAscendEnabled = false
local autoTreadmillEnabled = false
local autoWinsEnabled = false
local autoUnlockEnabled = false
local activeWinTween = nil

local Runtime = {}

local function isActive()
    return not destroyed
        and type(environment.ReverbLoadedScripts) == "table"
        and environment.ReverbLoadedScripts[SCRIPT.id] == instanceToken
end

function Runtime.Destroy()
    if destroyed then
        return
    end

    destroyed = true
    autoGetAppealEnabled = false
    autoRebirthEnabled = false
    autoAscendEnabled = false
    autoTreadmillEnabled = false
    autoWinsEnabled = false
    autoUnlockEnabled = false

    if activeWinTween then
        activeWinTween:Cancel()
        activeWinTween = nil
    end

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

    local window = Runtime.Window
    Runtime.Window = nil
    if type(window) == "table" and type(window.Destroy) == "function" then
        pcall(function()
            window:Destroy()
        end)
    end
end

local function findAppealRemote()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local powerRemotes = ReplicatedStorage:WaitForChild("PowerRemotes", 10)
    local remote = powerRemotes and powerRemotes:WaitForChild("ClickPower", 10)

    if not remote or not remote:IsA("RemoteEvent") then
        error("PowerRemotes.ClickPower RemoteEvent was not found")
    end

    return remote
end

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

local function buildGame(window)
    local MainTab = window:Tab("Main")
    local MainSection = MainTab:Section("Main")
    local UpgradesSection = MainTab:Section("Upgrades")

    local appealRemote = findAppealRemote()
    local RebirthRemotes = game:GetService("ReplicatedStorage")
        :WaitForChild("RebirthRemotes", 10)
    local rebirthRemote = RebirthRemotes
        and RebirthRemotes:WaitForChild("DoRebirth", 10)

    if not rebirthRemote or not rebirthRemote:IsA("RemoteEvent") then
        error("RebirthRemotes.DoRebirth RemoteEvent was not found")
    end

    local packet = game:GetService("ReplicatedStorage")
        :WaitForChild("Packet", 10)
    local ascendRemote = packet and packet:WaitForChild("RemoteEvent", 10)
    if not ascendRemote or not ascendRemote:IsA("RemoteEvent") then
        error("Packet.RemoteEvent RemoteEvent was not found")
    end

    local ascendPacket = buffer.create(1)
    buffer.writeu8(ascendPacket, 0, 10)

    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local mogFolder = ReplicatedStorage:WaitForChild("Mog", 10)
    local MogConfig = require(mogFolder:WaitForChild("MogConfig", 10))
    local MogLadder = require(mogFolder:WaitForChild("MogLadder", 10))
    local MogPackets = require(mogFolder:WaitForChild("MogPackets", 10))

    local Players = game:GetService("Players")
    local TweenService = game:GetService("TweenService")
    local LocalPlayer = Players.LocalPlayer

    local function getActiveWorldName()
        local worldTwoPortal = workspace:FindFirstChild("World2Portal", true)
        local worldOnePortal = workspace:FindFirstChild("World1Portal", true)

        if worldTwoPortal and not worldOnePortal then
            return "World1"
        end
        if worldOnePortal and not worldTwoPortal then
            return "World2"
        end
        return nil
    end

    local function findParticleBase(scope)
        if scope:IsA("BasePart")
            and scope.Name == "Part"
            and scope:FindFirstChildWhichIsA("ParticleEmitter", true)
        then
            return scope
        end

        for _, candidate in ipairs(scope:GetDescendants()) do
            if candidate:IsA("BasePart")
                and candidate.Name == "Part"
                and candidate:FindFirstChildWhichIsA("ParticleEmitter", true)
            then
                return candidate
            end
        end

        return nil
    end

    local treadmillBasesByWorld = {}
    local treadmillOptionsByWorld = {}
    local treadmillOptions = {}
    local knownOptions = {}

    local function scanWorldTreadmills(worldName)
        local world = workspace:FindFirstChild(worldName)
        local treadmillFolder = world and world:FindFirstChild("TreadmillFolder")
        local treadmills = treadmillFolder
            and treadmillFolder:FindFirstChild("Treadmills")
        local worldBases = {}
        local worldOptions = {}
        treadmillBasesByWorld[worldName] = worldBases
        treadmillOptionsByWorld[worldName] = worldOptions

        if treadmills then
            for _, group in ipairs(treadmills:GetChildren()) do
                local base = findParticleBase(group)
                if base then
                    worldBases[group.Name] = base
                    table.insert(worldOptions, group.Name)
                    if not knownOptions[group.Name] then
                        knownOptions[group.Name] = true
                        table.insert(treadmillOptions, group.Name)
                    end
                end
            end
        end
    end

    for _, worldName in ipairs({ "World1", "World2" }) do
        scanWorldTreadmills(worldName)
    end

    local function sortTreadmills(options)
        table.sort(options, function(left, right)
            local leftMultiplier = tonumber(left:match("[xX]([%d%.]+)"))
            local rightMultiplier = tonumber(right:match("[xX]([%d%.]+)"))
            if leftMultiplier ~= rightMultiplier then
                if not leftMultiplier then
                    return true
                end
                if not rightMultiplier then
                    return false
                end
                return leftMultiplier < rightMultiplier
            end
            return left:lower() < right:lower()
        end)
    end

    sortTreadmills(treadmillOptions)
    for _, worldOptions in pairs(treadmillOptionsByWorld) do
        sortTreadmills(worldOptions)
    end

    if #treadmillOptions == 0 then
        table.insert(treadmillOptions, "No treadmills found")
    end

    local selectedTreadmill = treadmillOptions[1]
    local treadmillBase = nil
    local activeWorldName = nil
    local missingTreadmillNotified = false
    local treadmillDropdown = nil
    local lastTreadmillScan = 0
    local activeWorldChangedAt = 0
    local autoTreadmillToggle = nil
    local autoWinsToggle = nil
    local autoUnlockToggle = nil

    local function resolveTreadmillBase()
        local detectedWorld = getActiveWorldName()
        if detectedWorld ~= activeWorldName then
            activeWorldName = detectedWorld
            treadmillBase = nil
            missingTreadmillNotified = false
            activeWorldChangedAt = os.clock()

            if activeWorldName then
                scanWorldTreadmills(activeWorldName)
                sortTreadmills(treadmillOptionsByWorld[activeWorldName])
                lastTreadmillScan = os.clock()
            end

            local worldBases = activeWorldName
                and treadmillBasesByWorld[activeWorldName]
            if worldBases and not worldBases[selectedTreadmill] then
                local worldOptions = treadmillOptionsByWorld[activeWorldName]
                local replacement = worldOptions and worldOptions[1]
                if replacement then
                    selectedTreadmill = replacement
                    if treadmillDropdown then
                        treadmillDropdown:Set(replacement, true)
                    end
                end
            end
        end

        local worldBases = activeWorldName
            and treadmillBasesByWorld[activeWorldName]
        treadmillBase = worldBases and worldBases[selectedTreadmill] or nil

        if activeWorldName
            and not treadmillBase
            and os.clock() - lastTreadmillScan >= 1
        then
            scanWorldTreadmills(activeWorldName)
            sortTreadmills(treadmillOptionsByWorld[activeWorldName])
            lastTreadmillScan = os.clock()
            worldBases = treadmillBasesByWorld[activeWorldName]
            treadmillBase = worldBases and worldBases[selectedTreadmill] or nil
        end

        return treadmillBase
    end

    local function isStandingOnTreadmill(rootPart, base)
        local localPosition = base.CFrame:PointToObjectSpace(rootPart.Position)
        local horizontalPadding = 1
        local surfaceHeight = base.Size.Y / 2

        return math.abs(localPosition.X) <= base.Size.X / 2 + horizontalPadding
            and math.abs(localPosition.Z) <= base.Size.Z / 2 + horizontalPadding
            and localPosition.Y >= surfaceHeight
            and localPosition.Y <= surfaceHeight + 6
    end

    autoWinsToggle = MainSection:Toggle(
        "Auto Wins",
        false,
        function(enabled)
            autoWinsEnabled = enabled == true
            if autoWinsEnabled then
                autoTreadmillEnabled = false
                autoUnlockEnabled = false
                if autoTreadmillToggle then
                    autoTreadmillToggle:Set(false, true)
                end
                if autoUnlockToggle then
                    autoUnlockToggle:Set(false, true)
                end
            elseif activeWinTween then
                activeWinTween:Cancel()
                activeWinTween = nil
            end
        end,
        SCRIPT.id .. "_auto_wins"
    )

    MainSection:Toggle(
        "Auto Get Appeal",
        false,
        function(enabled)
            autoGetAppealEnabled = enabled == true
        end,
        SCRIPT.id .. "_auto_get_appeal"
    )

    autoUnlockToggle = MainSection:Toggle(
        "Auto Unlock Next Stage",
        false,
        function(enabled)
            autoUnlockEnabled = enabled == true
            if autoUnlockEnabled then
                autoWinsEnabled = false
                autoTreadmillEnabled = false
                if autoWinsToggle then
                    autoWinsToggle:Set(false, true)
                end
                if autoTreadmillToggle then
                    autoTreadmillToggle:Set(false, true)
                end
                if activeWinTween then
                    activeWinTween:Cancel()
                    activeWinTween = nil
                end
            end
        end,
        SCRIPT.id .. "_auto_unlock_next_stage"
    )

    treadmillDropdown = MainSection:Dropdown(
        "Treadmill",
        treadmillOptions,
        selectedTreadmill,
        function(selection)
            selectedTreadmill = selection
            missingTreadmillNotified = false
            resolveTreadmillBase()
        end,
        SCRIPT.id .. "_treadmill"
    )

    autoTreadmillToggle = MainSection:Toggle(
        "Auto Treadmill",
        false,
        function(enabled)
            autoTreadmillEnabled = enabled == true
            if autoTreadmillEnabled then
                autoWinsEnabled = false
                autoUnlockEnabled = false
                if autoWinsToggle then
                    autoWinsToggle:Set(false, true)
                end
                if autoUnlockToggle then
                    autoUnlockToggle:Set(false, true)
                end
            end
            resolveTreadmillBase()
            if autoTreadmillEnabled and not treadmillBase then
                window:Notify(
                    "The selected treadmill is not available in the active world.",
                    5
                )
                missingTreadmillNotified = true
            end
        end,
        SCRIPT.id .. "_auto_treadmill"
    )

    UpgradesSection:Toggle(
        "Auto Rebirth",
        false,
        function(enabled)
            autoRebirthEnabled = enabled == true
        end,
        SCRIPT.id .. "_auto_rebirth"
    )

    UpgradesSection:Toggle(
        "Auto Ascend",
        false,
        function(enabled)
            autoAscendEnabled = enabled == true
        end,
        SCRIPT.id .. "_auto_ascend"
    )

    task.spawn(function()
        while isActive() do
            if autoRebirthEnabled then
                local succeeded, rebirthError = pcall(function()
                    rebirthRemote:FireServer()
                end)
                if not succeeded then
                    warn("[Reverb] Auto Rebirth failed: " .. tostring(rebirthError))
                end
            end
            task.wait(0.75)
        end
    end)

    local lastUnlockNotice = nil

    local function notifyUnlockOnce(key, message)
        if lastUnlockNotice == key then
            return
        end
        lastUnlockNotice = key
        window:Notify(message, 5)
    end

    local function nextUndefeatedZone()
        for zoneNumber = 0, 14 do
            if not LocalPlayer:GetAttribute("Beat_Zone" .. zoneNumber) then
                return zoneNumber
            end
        end
        return nil
    end

    local function moveNearMogger(world, zoneName)
        local moggers = world:FindFirstChild(MogConfig.MoggersFolder)
        local zoneFolder = moggers and moggers:FindFirstChild(zoneName)
        local mogger = zoneFolder and zoneFolder:FindFirstChild(MogConfig.MoggerName)
        local moggerRoot = mogger and mogger:FindFirstChild("HumanoidRootPart")
        local character = LocalPlayer.Character
        local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
        if not moggerRoot or not playerRoot then
            return false
        end

        local zone = world:FindFirstChild(zoneName)
        local decor = zone and zone:FindFirstChild(MogConfig.DecorFolder)
        local playerPedestal = decor
            and decor:FindFirstChild(MogConfig.PlayerPedestalName)
        local towardPlayerSide = playerPedestal
            and (playerPedestal.Position - moggerRoot.Position) * Vector3.new(1, 0, 1)
            or Vector3.new(1, 0, 0)
        if towardPlayerSide.Magnitude < 0.1 then
            towardPlayerSide = Vector3.new(1, 0, 0)
        end

        local position = moggerRoot.Position + towardPlayerSide.Unit * 4
        playerRoot.AssemblyLinearVelocity = Vector3.zero
        playerRoot.AssemblyAngularVelocity = Vector3.zero
        playerRoot.CFrame = CFrame.lookAt(position, moggerRoot.Position)
        return true
    end

    local function runAutoUnlock()
        local zoneNumber = nextUndefeatedZone()
        if zoneNumber == nil then
            notifyUnlockOnce("complete", "Every stage in this world is already unlocked.")
            return
        end

        local worldNumber = tonumber(LocalPlayer:GetAttribute("World"))
        local worldName = worldNumber and ("World" .. worldNumber)
            or getActiveWorldName()
        local world = worldName and workspace:FindFirstChild(worldName)
        if not world then
            return
        end

        local zoneName = "Zone" .. zoneNumber
        local zoneConfig = MogConfig.GetZone(zoneName, worldNumber)
        if not zoneConfig then
            return
        end

        local npcTier = MogLadder.ByBody(zoneConfig.MoggerAsset, worldNumber)
        local requiredTier = npcTier and npcTier.Tier or 1
        local playerTier = tonumber(LocalPlayer:GetAttribute("BodyTier")) or 1
        local playerAppeal = tonumber(LocalPlayer:GetAttribute("AppealTotal")) or 0
        local requiredAppeal = tonumber(zoneConfig.AppealReq) or math.huge

        if playerTier < requiredTier or playerAppeal < requiredAppeal then
            notifyUnlockOnce(
                worldName .. ":" .. zoneName .. ":waiting",
                "Waiting until you are strong enough for Stage "
                    .. (zoneNumber + 1) .. "."
            )
            return
        end

        lastUnlockNotice = nil
        if not moveNearMogger(world, zoneName) then
            return
        end

        task.wait(0.2)
        MogPackets.Challenge:Fire(zoneName)

        local beginDeadline = os.clock() + 8
        while autoUnlockEnabled
            and isActive()
            and not LocalPlayer:GetAttribute(MogConfig.BattleAttribute)
            and os.clock() < beginDeadline
        do
            task.wait(0.1)
        end

        if not LocalPlayer:GetAttribute(MogConfig.BattleAttribute) then
            return
        end

        local countdownDeadline = os.clock()
            + MogConfig.CountdownStep * #MogConfig.CountdownSteps
        while autoUnlockEnabled
            and isActive()
            and LocalPlayer:GetAttribute(MogConfig.BattleAttribute)
            and os.clock() < countdownDeadline
        do
            task.wait(0.1)
        end

        while autoUnlockEnabled
            and isActive()
            and LocalPlayer:GetAttribute(MogConfig.BattleAttribute)
        do
            MogPackets.Click:Fire()
            task.wait(0.36)
        end

        task.wait(MogConfig.Cooldown)
    end

    task.spawn(function()
        while isActive() do
            if autoUnlockEnabled then
                local succeeded, unlockError = pcall(runAutoUnlock)
                if not succeeded then
                    warn("[Reverb] Auto Unlock Next Stage failed: " .. tostring(unlockError))
                    task.wait(1)
                else
                    task.wait(0.25)
                end
            else
                lastUnlockNotice = nil
                task.wait(0.25)
            end
        end
    end)

    task.spawn(function()
        while isActive() do
            if autoTreadmillEnabled then
                resolveTreadmillBase()
                if not treadmillBase
                    and not missingTreadmillNotified
                    and os.clock() - activeWorldChangedAt >= 2
                then
                    window:Notify(
                        "The selected treadmill is not available in the active world.",
                        5
                    )
                    missingTreadmillNotified = true
                elseif treadmillBase then
                    missingTreadmillNotified = false
                end

                local character = LocalPlayer.Character
                local rootPart = character
                    and character:FindFirstChild("HumanoidRootPart")
                if rootPart
                    and treadmillBase
                    and not isStandingOnTreadmill(rootPart, treadmillBase)
                then
                    rootPart.AssemblyLinearVelocity = Vector3.zero
                    rootPart.AssemblyAngularVelocity = Vector3.zero
                    rootPart.CFrame = treadmillBase.CFrame
                        * CFrame.new(0, treadmillBase.Size.Y / 2 + 3, 0)
                end
            end
            task.wait(0.25)
        end
    end)

    local function highestDefeatedZone()
        local highest = -1
        for zoneNumber = 0, 14 do
            local defeated = LocalPlayer:GetAttribute("Beat_Zone" .. zoneNumber)
            if not defeated then
                break
            end
            highest = zoneNumber
        end
        return highest
    end

    local function currentRootPart()
        local character = LocalPlayer.Character
        return character and character:FindFirstChild("HumanoidRootPart")
    end

    local WIN_MOVE_SPEED = 160
    local DOOR_OPEN_TIMEOUT = 2
    local DOOR_CHECK_DELAY = 0.05
    local CLAIM_COOLDOWN = 3.05

    local function moveRootTo(destination)
        local rootPart = currentRootPart()
        if not rootPart then
            return false
        end

        local distance = (rootPart.Position - destination.Position).Magnitude
        local duration = math.clamp(distance / WIN_MOVE_SPEED, 0.08, 1.5)

        activeWinTween = TweenService:Create(
            rootPart,
            TweenInfo.new(duration, Enum.EasingStyle.Linear),
            { CFrame = destination }
        )
        activeWinTween:Play()
        activeWinTween.Completed:Wait()
        activeWinTween = nil
        return autoWinsEnabled and isActive()
    end

    local function moveForWins(targetPart)
        if not targetPart or not targetPart.Parent then
            return false
        end

        local destination = targetPart.CFrame
            * CFrame.new(0, targetPart.Size.Y / 2 + 3, 0)
        return moveRootTo(destination)
    end

    local function doorIsOpen(door)
        if not door then
            return true
        end

        for _, descendant in ipairs(door:GetDescendants()) do
            if descendant:IsA("BasePart") and descendant.CanCollide then
                return false
            end
        end
        return true
    end

    local function retreatFromZone(zone, distance)
        local decor = zone and zone:FindFirstChild("Decor")
        local playerPedestal = decor
            and (
                decor:FindFirstChild("PlayerPedastal")
                or decor:FindFirstChild("PlayerPedestal")
            )
        local moggerPedestal = decor
            and (
                decor:FindFirstChild("MoggerPedastal")
                or decor:FindFirstChild("MoggerPedestal")
            )

        if not playerPedestal
            or not playerPedestal:IsA("BasePart")
            or not moggerPedestal
            or not moggerPedestal:IsA("BasePart")
        then
            warn("[Reverb] Auto Wins could not find the arena reset position")
            return false
        end

        local away = (playerPedestal.Position - moggerPedestal.Position)
            * Vector3.new(1, 0, 1)
        if away.Magnitude < 0.1 then
            return false
        end

        local resetPosition = playerPedestal.Position
            + away.Unit * distance
            + Vector3.new(0, playerPedestal.Size.Y / 2 + 3, 0)
        return moveRootTo(CFrame.lookAt(resetPosition, playerPedestal.Position))
    end

    local function runWinRoute()
        local worldName = getActiveWorldName()
        local highestZone = highestDefeatedZone()
        if not worldName then
            return false
        end

        local world = workspace:FindFirstChild(worldName)
        if not world then
            return false
        end

        local padNumber = 1

        for zoneNumber = 0, highestZone do
            if not autoWinsEnabled or getActiveWorldName() ~= worldName then
                return false
            end

            local zone = world:FindFirstChild("Zone" .. zoneNumber)
            local decor = zone and zone:FindFirstChild("Decor")
            local pedestal = decor
                and (
                    decor:FindFirstChild("PlayerPedastal")
                    or decor:FindFirstChild("PlayerPedestal")
                )
            if not pedestal or not pedestal:IsA("BasePart") then
                warn(
                    "[Reverb] Auto Wins could not find the player pedestal for Zone"
                        .. zoneNumber
                )
                return false
            end

            if not moveForWins(pedestal) then
                return false
            end

            local nextZone = world:FindFirstChild("Zone" .. (zoneNumber + 1))
            if nextZone then
                local door = zone:FindFirstChild("Door")
                local deadline = os.clock() + DOOR_OPEN_TIMEOUT
                while autoWinsEnabled
                    and not doorIsOpen(door)
                    and os.clock() < deadline
                do
                    task.wait(DOOR_CHECK_DELAY)
                end

                if not doorIsOpen(door) then
                    break
                end
            end

            padNumber = math.clamp(zoneNumber + 2, 1, 15)
        end

        local winPads = world:FindFirstChild("WinPads")
        local normalLane = winPads and winPads:FindFirstChild("Normal")
        local pad = normalLane
            and normalLane:FindFirstChild(tostring(padNumber))
        local hitbox = pad and pad:FindFirstChild("Hitbox")
        if not hitbox or not hitbox:IsA("BasePart") then
            return false
        end

        if not moveForWins(hitbox) then
            return false
        end

        local claimedAt = os.clock()

        task.wait(0.3)
        local firstZone = world:FindFirstChild("Zone0")
        if not retreatFromZone(firstZone, 40) then
            return false
        end

        local firstDoor = firstZone and firstZone:FindFirstChild("Door")
        local resetDeadline = os.clock() + 2
        while autoWinsEnabled
            and doorIsOpen(firstDoor)
            and os.clock() < resetDeadline
        do
            task.wait(DOOR_CHECK_DELAY)
        end

        local cooldownRemaining = claimedAt + CLAIM_COOLDOWN - os.clock()
        if cooldownRemaining > 0 then
            task.wait(cooldownRemaining)
        end
        return true
    end

    task.spawn(function()
        while isActive() do
            if autoWinsEnabled then
                local succeeded, routeError = pcall(runWinRoute)
                if not succeeded then
                    warn("[Reverb] Auto Wins failed: " .. tostring(routeError))
                    task.wait(0.5)
                else
                    task.wait(0.2)
                end
            else
                task.wait(0.25)
            end
        end
    end)

    task.spawn(function()
        while isActive() do
            if autoAscendEnabled then
                local succeeded, ascendError = pcall(function()
                    ascendRemote:FireServer(ascendPacket)
                end)
                if not succeeded then
                    warn("[Reverb] Auto Ascend failed: " .. tostring(ascendError))
                end
            end
            task.wait(0.75)
        end
    end)

    task.spawn(function()
        while isActive() do
            if not autoGetAppealEnabled then
                task.wait(0.25)
                continue
            end

            local succeeded, appealError = pcall(function()
                appealRemote:FireServer()
            end)

            if succeeded then
                task.wait()
            else
                warn("[Reverb] Auto Get Appeal failed: " .. tostring(appealError))
                autoGetAppealEnabled = false
                window:Notify(
                    "Auto Get Appeal stopped: the appeal remote changed or became unavailable.",
                    5
                )
                task.wait(2)
            end
        end
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
            "Loader routed " .. tostring(routedScript.id)
                .. " but this script is " .. SCRIPT.id
        )
    end

    environment.ReverbLoadedScripts = environment.ReverbLoadedScripts or {}
    environment.ReverbScriptInstances = environment.ReverbScriptInstances or {}

    local previousInstance = environment.ReverbScriptInstances[SCRIPT.id]
    if previousInstance and previousInstance ~= Runtime
        and type(previousInstance.Destroy) == "function"
    then
        pcall(previousInstance.Destroy)
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

    local access = environment.ReverbAccess or {}
    local tier = access.tier or environment.ReverbKeyTier or "free"
    local Window = ReverbLib:CreateWindow({
        Game = SCRIPT.name,
        Tier = tier == "premium" and "PREMIUM" or "FREE",
        RememberSettings = false,
        ConfigName = SCRIPT.id,
    })

    Runtime.Window = Window
    -- ВЫЗОВ СИСТЕМЫ ФИДБЕКА
    addFeedbackSystem(Window, ReverbLib, SCRIPT.name)
    
    buildGame(Window)

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
    local ChangelogSection = ChangelogTab:Section("V1 15 September 2026")
    ChangelogSection:Label(
        "Initial release with 6 features"
    )

    SettingsTab:Section("Script"):Button("Unload +1 Mog Evolution", function()
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
