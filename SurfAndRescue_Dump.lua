-- Surf And Rescue

local SCRIPT = {
    id = "SurfAndRescue",
    name = "Surf And Rescue",
}

local REVERB_J_URL =
    "https://raw.githubusercontent.com/rbxreverb/ReverbJ/refs/heads/main/source.lua?v=remember-settings-20260812"

local environment = (getgenv and getgenv()) or _G
local instanceToken = {}
local destroyed = false
local autoPetsEnabled = false
local backpackBlocked = false
local cleaningInProgress = false
local cleaningHandled = false
local cleanDoneReceived = false
local cleanEndReceived = false
local grabEnded = false
local grabWon = false
local grabLostReceived = false
local selectedWater = "Any Water"
local autoTrainEnabled = false
local autoUpgradeEnabled = false
local selectedUpgrades = {
    Tank = true,
    Hose = true,
    Pool = true,
}

local Runtime = {}

local function isActive()
    return not destroyed
        and type(environment.ReverbLoadedScripts) == "table"
        and environment.ReverbLoadedScripts[SCRIPT.id] == instanceToken
end

local function getCharacter()
    return game:GetService("Players").LocalPlayer.Character
end

local function getRoot()
    local character = getCharacter()
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function moveNear(part)
    local character = getCharacter()
    local root = getRoot()
    if not character or not root or not part or not part:IsA("BasePart") then
        return false
    end

    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    local position = part.Position + Vector3.new(0, 3, 0)
    local forward = Vector3.new(
        root.CFrame.LookVector.X,
        0,
        root.CFrame.LookVector.Z
    )
    if forward.Magnitude < 0.01 then
        forward = Vector3.new(0, 0, -1)
    else
        forward = forward.Unit
    end
    character:PivotTo(CFrame.lookAt(position, position + forward))
    return true
end

local function promptPart(prompt)
    local parent = prompt and prompt.Parent
    if parent and parent:IsA("BasePart") then
        return parent
    end

    local ancestorPart = prompt and prompt:FindFirstAncestorWhichIsA("BasePart")
    if ancestorPart then
        return ancestorPart
    end

    local model = prompt and prompt:FindFirstAncestorOfClass("Model")
    return model and model:FindFirstChildWhichIsA("BasePart", true) or nil
end

function Runtime.Destroy()
    if destroyed then
        return
    end

    destroyed = true
    autoPetsEnabled = false
    backpackBlocked = false
    cleaningInProgress = false
    cleaningHandled = false
    cleanDoneReceived = false
    cleanEndReceived = false
    autoTrainEnabled = false
    autoUpgradeEnabled = false

    for _, connection in ipairs(Runtime.Connections or {}) do
        connection:Disconnect()
    end
    Runtime.Connections = {}

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

local function buildGame(window)
    local CollectionService = game:GetService("CollectionService")
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")

    local LocalPlayer = Players.LocalPlayer
    local Remotes = ReplicatedStorage:WaitForChild("Remotes")
    local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
    local Waters = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Waters"))
    local AnimalCatalog = require(
        ReplicatedStorage:WaitForChild("Shared")
            :WaitForChild("Catalog")
            :WaitForChild("Animals")
    )
    local GrabTap = Remotes:WaitForChild("GrabTap")
    local GrabEnd = Remotes:WaitForChild("GrabEnd")
    local GrabLost = Remotes:WaitForChild("GrabLost")
    local GrabDismiss = Remotes:WaitForChild("GrabDismiss")
    local CleanRemove = Remotes:WaitForChild("CleanRemove")
    local CleanDone = Remotes:WaitForChild("CleanDone")
    local CleanEnd = Remotes:WaitForChild("CleanEnd")
    local BackpackFull = Remotes:WaitForChild("BackpackFull")
    local TankUpgrade = Remotes:WaitForChild("TankUpgrade")
    local HoseUpgrade = Remotes:WaitForChild("HoseUpgrade")
    local PoolUpgrade = Remotes:WaitForChild("PoolUpgrade")
    Runtime.Connections = Runtime.Connections or {}
    local fullTapRate = tonumber(Config.Grab.RateForFullSpeed) or 10
    local grabTapInterval = math.max(0.02, 1 / math.max(fullTapRate, 1))

    local MainTab = window:Tab("Main")
    local PetSection = MainTab:Section("Main")
    local UpgradeSection = MainTab:Section("Upgrades")
    local TeleportSection = MainTab:Section("Teleports")

    local waterOptions = { "Any Water" }
    local waterSpecies = {}
    local waterEntries = {}
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local indexWindow = playerGui:FindFirstChild("IndexWindow")
    local indexFrame = indexWindow and indexWindow:FindFirstChild("Window")
    local indexBody = indexFrame and indexFrame:FindFirstChild("Body")
    local watersFolder = indexBody and indexBody:FindFirstChild("Waters")

    if watersFolder then
        for _, waterFrame in ipairs(watersFolder:GetChildren()) do
            local petsFrame = waterFrame:FindFirstChild("Pets")
            if petsFrame then
                local speciesSet = {}
                for _, petButton in ipairs(petsFrame:GetChildren()) do
                    local species = string.match(petButton.Name, "^([^/]+)")
                    if species and AnimalCatalog[species] then
                        speciesSet[species] = true
                    end
                end

                if next(speciesSet) then
                    waterSpecies[waterFrame.Name] = speciesSet
                    table.insert(waterEntries, {
                        Name = waterFrame.Name,
                        LayoutOrder = waterFrame:IsA("GuiObject")
                            and waterFrame.LayoutOrder or 0,
                        Sequence = #waterEntries + 1,
                    })
                end
            end
        end

        table.sort(waterEntries, function(left, right)
            if left.LayoutOrder == right.LayoutOrder then
                return left.Sequence < right.Sequence
            end
            return left.LayoutOrder < right.LayoutOrder
        end)

        for _, entry in ipairs(waterEntries) do
            table.insert(waterOptions, entry.Name)
        end
    end

    local function notify(message)
        window:Notify(message, 4)
    end

    local function screenEnabled(name)
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local screen = playerGui and playerGui:FindFirstChild(name)
        return screen ~= nil
            and (not screen:IsA("ScreenGui") or screen.Enabled)
    end

    local function activatePromptSession(prompt, screenName, timeout)
        local part = promptPart(prompt)
        local deadline = os.clock() + timeout

        repeat
            if screenEnabled(screenName) then
                return true
            end

            if part then
                moveNear(part)
            end
            task.wait(0.2)

            if prompt and prompt.Parent and prompt.Enabled then
                pcall(fireproximityprompt, prompt)
            end

            local attemptDeadline = math.min(deadline, os.clock() + 0.75)
            repeat
                if screenEnabled(screenName) then
                    return true
                end
                task.wait(0.1)
            until os.clock() >= attemptDeadline
        until os.clock() >= deadline

        return false
    end

    local function dirtyPetTool()
        local character = getCharacter()
        if character then
            for _, child in ipairs(character:GetChildren()) do
                if child:IsA("Tool") and string.sub(child.Name, 1, 3) == "???" then
                    return child
                end
            end
        end

        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        if backpack then
            for _, child in ipairs(backpack:GetChildren()) do
                if child:IsA("Tool") and string.sub(child.Name, 1, 3) == "???" then
                    return child
                end
            end
        end

        return nil
    end

    local function equipDirtyPet()
        local tool = dirtyPetTool()
        if not tool then
            return false
        end

        local character = getCharacter()
        if tool.Parent == character then
            return true
        end

        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            return false
        end

        humanoid:EquipTool(tool)
        task.wait(0.2)
        return tool.Parent == character
    end

    local activeGrabAnimal = nil
    local waitingForZonePets = false

    local function animalBaseIncome(animal)
        local species = animal:GetAttribute("Species")
        local entry = type(species) == "string" and AnimalCatalog[species] or nil
        return entry and tonumber(entry.BaseIncome) or 0
    end

    local function animalMatchesWater(animal)
        if selectedWater == "Any Water" then
            return true
        end

        local speciesSet = waterSpecies[selectedWater]
        local species = animal:GetAttribute("Species")
        if speciesSet == nil or speciesSet[species] ~= true then
            return false
        end

        local position
        if animal:IsA("Model") then
            position = animal:GetPivot().Position
        elseif animal:IsA("BasePart") then
            position = animal.Position
        end

        local physicalWater = position and Waters.nameAt(position.X)
        return physicalWater ~= nil and physicalWater.Name == selectedWater
    end

    local function targetAnimalPrompt()
        local root = getRoot()
        if not root then
            return nil, nil, false
        end

        local bestPrompt = nil
        local bestAnimal = nil
        local bestScore = -math.huge
        local bestDistance = math.huge

        for _, animal in ipairs(CollectionService:GetTagged("LiveAnimal")) do
            if animal:IsDescendantOf(Workspace) and animalMatchesWater(animal) then
                local prompt = animal:FindFirstChildWhichIsA("ProximityPrompt", true)
                local part = promptPart(prompt)
                if prompt and prompt.Enabled and part then
                    local distance = (part.Position - root.Position).Magnitude
                    local score = animalBaseIncome(animal)
                    local better = score > bestScore
                        or score == bestScore and distance < bestDistance
                    if better then
                        bestPrompt = prompt
                        bestAnimal = animal
                        bestScore = score
                        bestDistance = distance
                    end
                end
            end
        end

        return bestPrompt, bestAnimal, true
    end

    local function playerPlot()
        local plots = Workspace:FindFirstChild("Plots")
        if not plots then
            return nil
        end

        for _, plot in ipairs(plots:GetChildren()) do
            local textParts = {}
            for _, descendant in ipairs(plot:GetDescendants()) do
                if descendant:IsA("TextLabel") then
                    table.insert(textParts, descendant.Text)
                end
            end

            local text = string.lower(table.concat(textParts))
            local playerName = string.lower(LocalPlayer.Name)
            local displayName = string.lower(LocalPlayer.DisplayName)
            if string.find(text, playerName, 1, true)
                or string.find(text, displayName, 1, true)
            then
                return plot
            end
        end

        for _, plot in ipairs(plots:GetChildren()) do
            local plotAnchor = plot:FindFirstChild("PlotAnchor")
            local prompt = plotAnchor
                and plotAnchor:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt and prompt.Enabled then
                return plot
            end
        end

        return nil
    end

    local function cleaningPrompt()
        local plot = playerPlot()
        if not plot then
            return nil
        end

        local stationAnchor = plot:FindFirstChild("StationAnchor")
        local prompt = stationAnchor
            and stationAnchor:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt
            and prompt.ActionText == "Place"
            and prompt.ObjectText == "Cleaning station"
        then
            return prompt
        end
        return nil
    end

    local function trainingPart()
        local plot = playerPlot()
        local pool = plot and plot:FindFirstChild("Pool")
        if not pool then
            return nil
        end

        local insidePool = pool:FindFirstChild("insidePool", true)
        return insidePool and insidePool:IsA("BasePart") and insidePool or nil
    end

    local function isOnTrainingPart(root, part)
        if not root or not part then
            return false
        end

        local localPosition = part.CFrame:PointToObjectSpace(root.Position)
        return math.abs(localPosition.X) <= part.Size.X / 2
            and math.abs(localPosition.Z) <= part.Size.Z / 2
            and localPosition.Y >= -part.Size.Y / 2 - 3
            and localPosition.Y <= part.Size.Y / 2 + 6
    end

    local function moveToTrainingPool()
        local character = getCharacter()
        local root = getRoot()
        local part = trainingPart()
        if not character or not root or not part then
            return false
        end

        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        local position = part.Position
            + part.CFrame.UpVector * (part.Size.Y / 2 + 3)
        local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
        if forward.Magnitude < 0.01 then
            forward = Vector3.new(0, 0, -1)
        else
            forward = forward.Unit
        end
        character:PivotTo(CFrame.lookAt(position, position + forward))
        return true
    end

    local function teleportTo(part, missingMessage)
        if part and part:IsA("BasePart") and moveNear(part) then
            return
        end
        notify(missingMessage)
    end

    local function waitForPromptEnabled(prompt, timeout)
        local deadline = os.clock() + timeout
        repeat
            if prompt and prompt.Parent and prompt.Enabled then
                return true
            end
            task.wait(0.1)
        until os.clock() >= deadline
        return false
    end

    local function currentDirtIds()
        local bestIds = nil
        local bestDistance = math.huge
        local root = getRoot()

        for _, container in ipairs(CollectionService:GetTagged("DirtTiles")) do
            if container:IsDescendantOf(Workspace)
                and container:GetAttribute("Local") ~= true
            then
                local ids = {}
                local distance = math.huge
                for _, child in ipairs(container:GetChildren()) do
                    if child:IsA("BasePart") then
                        local id = tonumber(child.Name)
                        if id then
                            table.insert(ids, id)
                            if root then
                                distance = math.min(
                                    distance,
                                    (child.Position - root.Position).Magnitude
                                )
                            end
                        end
                    end
                end

                if #ids > 0 and (not bestIds or distance < bestDistance) then
                    bestIds = ids
                    bestDistance = distance
                end
            end
        end

        if bestIds then
            table.sort(bestIds)
        end
        return bestIds
    end

    local function waitForDirtIds(timeout)
        local deadline = os.clock() + timeout
        repeat
            local ids = currentDirtIds()
            if ids and #ids > 0 then
                return ids
            end
            task.wait(0.1)
        until os.clock() >= deadline
        return nil
    end

    local function runGrab()
        if backpackBlocked or cleaningInProgress then
            return false
        end

        local prompt, animal, searchCompleted = targetAnimalPrompt()
        if not prompt then
            if searchCompleted
                and selectedWater ~= "Any Water"
                and not waitingForZonePets
            then
                waitingForZonePets = true
                notify(
                    "No pets are available in " .. selectedWater
                        .. ". Waiting for the next tsunami."
                )
            end
            return false
        end

        if waitingForZonePets then
            waitingForZonePets = false
            notify("New pets are available in " .. selectedWater .. ".")
        end

        activeGrabAnimal = animal
        grabEnded = false
        grabWon = false
        grabLostReceived = false
        local started = activatePromptSession(prompt, "GrabBar", 4)
        if not started then
            activeGrabAnimal = nil
            return false
        end

        local grabDeadline = os.clock() + 12
        while isActive()
            and autoPetsEnabled
            and not grabEnded
            and not dirtyPetTool()
            and os.clock() < grabDeadline
        do
            GrabTap:FireServer()
            task.wait(grabTapInterval)
        end

        local deadline = os.clock() + 2
        while isActive() and not dirtyPetTool() and os.clock() < deadline do
            task.wait(0.1)
        end

        if dirtyPetTool() then
            activeGrabAnimal = nil
            backpackBlocked = true
            cleaningHandled = false
            return true
        end

        if animal and grabEnded and not grabWon then
            local lostDeadline = os.clock() + 3
            while isActive()
                and not grabLostReceived
                and os.clock() < lostDeadline
            do
                task.wait(0.1)
            end
        end
        activeGrabAnimal = nil
        backpackBlocked = false
        return false
    end

    local function runClean()
        if cleaningInProgress or cleaningHandled or not dirtyPetTool() then
            return false
        end

        if not equipDirtyPet() then
            return false
        end

        local prompt = cleaningPrompt()
        if not prompt then
            return false
        end

        if not waitForPromptEnabled(prompt, 3) then
            return false
        end

        local started = activatePromptSession(prompt, "Cleaning", 4)
        if not started then
            cleaningHandled = true
            notify("The cleaning screen did not become ready.")
            return false
        end

        cleaningInProgress = true
        cleanDoneReceived = false
        cleanEndReceived = false

        local dirtIds = waitForDirtIds(3)
        if not dirtIds then
            cleaningInProgress = false
            cleaningHandled = true
            notify("No numbered dirt tiles were found for this pet.")
            return false
        end

        local batch = {}
        for _, dirtId in ipairs(dirtIds) do
            if not isActive() or not autoPetsEnabled then
                cleaningInProgress = false
                return false
            end

            table.insert(batch, dirtId)
            if #batch >= 40 then
                CleanRemove:FireServer(batch)
                batch = {}
                task.wait(0.15)
            end
        end

        if #batch > 0 then
            CleanRemove:FireServer(batch)
        end

        local deadline = os.clock() + 5
        while isActive() and not cleanDoneReceived and os.clock() < deadline do
            task.wait(0.1)
        end

        if not cleanDoneReceived then
            notify("The server did not confirm that cleaning completed.")
        else
            local endDeadline = os.clock() + 8
            while isActive() and not cleanEndReceived and os.clock() < endDeadline do
                task.wait(0.1)
            end
        end

        cleaningInProgress = false
        cleaningHandled = true
        task.wait(0.75)
        return true
    end

    table.insert(Runtime.Connections, BackpackFull.OnClientEvent:Connect(function()
        backpackBlocked = true
    end))
    table.insert(Runtime.Connections, GrabEnd.OnClientEvent:Connect(function(success)
        if activeGrabAnimal then
            grabWon = success == true
            grabEnded = true
        end
    end))
    table.insert(Runtime.Connections, GrabLost.OnClientEvent:Connect(function(info)
        if not autoPetsEnabled or not activeGrabAnimal then
            return
        end

        grabLostReceived = true
        GrabDismiss:FireServer()
    end))
    table.insert(Runtime.Connections, CleanDone.OnClientEvent:Connect(function()
        cleanDoneReceived = true
    end))
    table.insert(Runtime.Connections, CleanEnd.OnClientEvent:Connect(function()
        cleanEndReceived = true
        backpackBlocked = false
        cleaningInProgress = false
    end))

    PetSection:Dropdown(
        "Water Zone",
        waterOptions,
        selectedWater,
        function(selection)
            selectedWater = selection
            waitingForZonePets = false
        end,
        SCRIPT.id .. "_water_zone"
    )

    Runtime.AutoPetsToggle = PetSection:Toggle(
        "Auto Rescue Pets",
        false,
        function(enabled)
            autoPetsEnabled = enabled == true
            if enabled then
                autoTrainEnabled = false
                if Runtime.AutoTrainToggle then
                    Runtime.AutoTrainToggle:Set(false, true)
                end
                backpackBlocked = false
                cleaningHandled = false
            end
        end,
        SCRIPT.id .. "_auto_pets"
    )

    Runtime.AutoTrainToggle = PetSection:Toggle(
        "Auto Train",
        false,
        function(enabled)
            autoTrainEnabled = enabled == true
            if autoTrainEnabled then
                autoPetsEnabled = false
                Runtime.AutoPetsToggle:Set(false, true)
                if not moveToTrainingPool() then
                    notify("The local plot's insidePool part was not found.")
                end
            end
        end,
        SCRIPT.id .. "_auto_train"
    )

    local function runUpgradeRequests()
        if selectedUpgrades.Tank then
            TankUpgrade:FireServer()
        end
        if selectedUpgrades.Hose then
            HoseUpgrade:FireServer()
        end
        if selectedUpgrades.Pool then
            PoolUpgrade:FireServer()
        end
    end

    UpgradeSection:MultiDropdown(
        "Upgrade Targets",
        { "Tank", "Hose", "Pool" },
        { "Tank", "Hose", "Pool" },
        function(selections)
            table.clear(selectedUpgrades)
            for _, selection in ipairs(selections) do
                selectedUpgrades[selection] = true
            end
        end,
        SCRIPT.id .. "_upgrade_targets"
    )

    UpgradeSection:Toggle(
        "Auto Upgrade",
        false,
        function(enabled)
            autoUpgradeEnabled = enabled == true
            if autoUpgradeEnabled then
                runUpgradeRequests()
            end
        end,
        SCRIPT.id .. "_auto_upgrade"
    )

    TeleportSection:Button("My Plot", function()
        local plot = playerPlot()
        local spawnPart = plot and plot:FindFirstChild("Spawn", true)
        teleportTo(spawnPart, "Your plot spawn was not found.")
    end)

    TeleportSection:Button("Training Pool", function()
        teleportTo(trainingPart(), "Your plot's insidePool part was not found.")
    end)

    TeleportSection:Button("Sell Pets", function()
        local npcs = Workspace:FindFirstChild("Npcs")
        local maui = npcs and npcs:FindFirstChild("Maui")
        teleportTo(maui and maui:FindFirstChild("Head"), "The pet seller was not found.")
    end)

    TeleportSection:Button("Shovel Shop", function()
        local npcs = Workspace:FindFirstChild("Npcs")
        local nick = npcs and npcs:FindFirstChild("Nick")
        teleportTo(nick and nick:FindFirstChild("Head"), "The shovel shop was not found.")
    end)

    TeleportSection:Button("Surfboard Shop", function()
        local npcs = Workspace:FindFirstChild("Npcs")
        local luke = npcs and npcs:FindFirstChild("Luke")
        teleportTo(luke and luke:FindFirstChild("Head"), "The surfboard shop was not found.")
    end)

    if type(fireproximityprompt) ~= "function" then
        notify("Your executor does not support proximity prompts.")
    end

    task.spawn(function()
        while isActive() do
            if autoPetsEnabled and not cleaningInProgress then
                if dirtyPetTool() then
                    local ok, cleanError = pcall(runClean)
                    if not ok then
                        warn("[Reverb/SurfAndRescue] Auto Clean: " .. tostring(cleanError))
                        task.wait(1)
                    end
                elseif not backpackBlocked then
                    local ok, grabError = pcall(runGrab)
                    if not ok then
                        warn("[Reverb/SurfAndRescue] Auto Get: " .. tostring(grabError))
                        task.wait(1)
                    end
                end
            end
            task.wait(0.35)
        end
    end)

    task.spawn(function()
        while isActive() do
            if autoTrainEnabled then
                local root = getRoot()
                local part = trainingPart()
                if root and part and not isOnTrainingPart(root, part) then
                    moveToTrainingPool()
                end
            end
            task.wait(1)
        end
    end)

    task.spawn(function()
        while isActive() do
            if autoUpgradeEnabled then
                runUpgradeRequests()
            end
            task.wait(0.75)
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
    ChangelogTab:Section("V1 26 September 2026"):Label(
        "Initial release with 8 features"
    )

    environment.ReverbCurrentScript = {
        id = SCRIPT.id,
        runtime = Runtime,
    }
end

local ok, startError = pcall(start)
if not ok then
    Runtime.Destroy()
    error(startError)
end
