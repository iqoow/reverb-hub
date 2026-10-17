-- Build the Pyramid

local SCRIPT = {
    id = "BuildThePyramid",
    name = "Build the Pyramid",
}

local REVERB_J_URL =
    "https://raw.githubusercontent.com/rbxreverb/ReverbJ/refs/heads/main/source.lua?v=remember-settings-20260812"

local environment = (getgenv and getgenv()) or _G
local instanceToken = {}
local destroyed = false
local autoBuildEnabled = false
local autoCollectEnabled = false
local autoWatersEnabled = false
local autoStrengthEnabled = false
local autoSpeedEnabled = false
local autoUpgradeEnabled = false
local autoHatchEnabled = false
local hatchBetweenEnabled = false
local selectedUpgradeId = "All"
local selectedTrainingArea = nil
local lastSafeCFrame = nil

local Runtime = {}

local graphicsOriginals = {}
local graphicsConnection
local graphicsSettings = {}

local function overrideGraphics(instance, property, value)
    pcall(function()
        local originals = graphicsOriginals[instance]
        if not originals then
            originals = {}
            graphicsOriginals[instance] = originals
        end
        if originals[property] == nil then
            originals[property] = instance[property]
        end
        instance[property] = value
    end)
end

local function reduceGraphics(instance)
    local Workspace = game:GetService("Workspace")
    local Lighting = game:GetService("Lighting")
    if instance ~= Lighting and not instance:IsDescendantOf(Workspace)
        and not instance:IsDescendantOf(Lighting) then
        return
    end
    if instance:IsA("BasePart") then
        overrideGraphics(instance, "CastShadow", false)
        overrideGraphics(instance, "Material", Enum.Material.SmoothPlastic)
        overrideGraphics(instance, "MaterialVariant", "")
        overrideGraphics(instance, "Reflectance", 0)
        if instance:IsA("MeshPart") then
            overrideGraphics(instance, "TextureID", "")
        end
    elseif instance:IsA("Decal") or instance:IsA("Texture") then
        -- Keep signs and gameplay information readable; hide repeating textures.
        if instance:IsA("Texture") then
            overrideGraphics(instance, "Transparency", 1)
        end
    elseif instance:IsA("SpecialMesh") then
        overrideGraphics(instance, "TextureId", "")
    elseif instance:IsA("ParticleEmitter") or instance:IsA("Trail")
        or instance:IsA("Beam") or instance:IsA("Smoke")
        or instance:IsA("Fire") or instance:IsA("Sparkles")
        or instance:IsA("PostEffect") then
        overrideGraphics(instance, "Enabled", false)
    elseif instance:IsA("Lighting") then
        overrideGraphics(instance, "GlobalShadows", false)
    end
end

local function setLowGraphics(enabled)
    if graphicsConnection then
        graphicsConnection:Disconnect()
        graphicsConnection = nil
    end
    if enabled then
        local settings = Runtime.SettingsState
        local performance = Runtime.PerformanceState
        if settings and performance then
            local values = {
                petVisibility = "off", petNameTags = false, hatchAnimations = "off",
                [performance.getSettingKey("BlockVisibility")] = "self",
                [performance.getSettingKey("DroppedBlockVisibility")] = "self",
                [performance.getSettingKey("BlockRenderDistance")] = 60,
                [performance.getSettingKey("BlockHeight")] = 1,
                [performance.getSettingKey("BlockHeightAudience")] = "others",
            }
            for key, value in pairs(values) do
                local source = settings.getSource(key)
                if source then
                    if not graphicsSettings[key] then
                        graphicsSettings[key] = { source = source, original = source(), applied = value }
                    end
                    -- Temporary local visual override, without persisting game settings.
                    source(value)
                end
            end
        end
        graphicsConnection = game.DescendantAdded:Connect(reduceGraphics)
        reduceGraphics(game:GetService("Lighting"))
        for _, instance in ipairs(game:GetDescendants()) do
            reduceGraphics(instance)
        end
    else
        for instance, originals in pairs(graphicsOriginals) do
            for property, value in pairs(originals) do
                pcall(function() instance[property] = value end)
            end
        end
        for _, setting in pairs(graphicsSettings) do
            if setting.source() == setting.applied then
                setting.source(setting.original)
            end
        end
        table.clear(graphicsOriginals)
        table.clear(graphicsSettings)
    end
end

local function isActive()
    return not destroyed
        and type(environment.ReverbLoadedScripts) == "table"
        and environment.ReverbLoadedScripts[SCRIPT.id] == instanceToken
end

local function getRoot()
    local Players = game:GetService("Players")
    local character = Players.LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function moveTo(cframe)
    local root = getRoot()
    if not root or typeof(cframe) ~= "CFrame" then
        return false
    end
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    root.CFrame = cframe
    return true
end

local function setMovementMode(mode)
    local wasStrengthEnabled = autoStrengthEnabled
    if mode ~= "build" then
        if Runtime.StopCollectHold then
            Runtime.StopCollectHold()
        end
        autoBuildEnabled = false
        autoCollectEnabled = false
        autoWatersEnabled = false
    end
    if Runtime.StopPlacementHold then
        Runtime.StopPlacementHold()
    end
    if mode ~= "hatch" and Runtime.StopHatch then
        Runtime.StopHatch()
    end
    autoStrengthEnabled = mode == "strength"
    autoSpeedEnabled = mode == "speed"

    if wasStrengthEnabled and not autoStrengthEnabled and Runtime.GymService then
        pcall(function()
            Runtime.GymService:StopBench()
        end)
    end

    if Runtime.AutoBuildToggle then
        Runtime.AutoBuildToggle:Set(autoBuildEnabled, true)
    end
    if Runtime.AutoCollectToggle then
        Runtime.AutoCollectToggle:Set(autoCollectEnabled, true)
    end
    if Runtime.AutoWatersToggle then
        Runtime.AutoWatersToggle:Set(autoWatersEnabled, true)
    end
    if Runtime.AutoStrengthToggle then
        Runtime.AutoStrengthToggle:Set(autoStrengthEnabled, true)
    end
    if Runtime.AutoSpeedToggle then
        Runtime.AutoSpeedToggle:Set(autoSpeedEnabled, true)
    end
end

function Runtime.Destroy(restorePosition)
    if destroyed then
        return
    end

    destroyed = true
    setLowGraphics(false)
    autoBuildEnabled = false
    autoCollectEnabled = false
    autoWatersEnabled = false
    autoStrengthEnabled = false
    autoSpeedEnabled = false
    autoUpgradeEnabled = false
    if Runtime.StopHatch then
        pcall(Runtime.StopHatch)
    end

    if Runtime.GymService then
        pcall(function()
            Runtime.GymService:StopBench()
        end)
    end
    if Runtime.StopPlacementHold then
        pcall(Runtime.StopPlacementHold)
    end
    if Runtime.StopCollectHold then
        pcall(Runtime.StopCollectHold)
    end

    if restorePosition ~= false and lastSafeCFrame then
        pcall(moveTo, lastSafeCFrame)
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

local function checkCompatibility()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = game:GetService("Players").LocalPlayer
    local Knit = require(ReplicatedStorage.Packages.Knit)
    local ClientContracts = require(ReplicatedStorage.Shared.Contracts.ClientContracts)
    local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)
    local UpgradeCatalog = require(ReplicatedStorage.Shared.Config.UpgradeCatalog)
    local GymAccess = require(ReplicatedStorage.Shared.Gym.GymAccess)
    local PyramidConfig = require(ReplicatedStorage.Shared.Config.PyramidConfig)
    local PyramidRuntime = require(ReplicatedStorage.Shared.Placement.PyramidRuntime)
    local InteractionRuntime = require(LocalPlayer.PlayerScripts.Utils.Interaction.InteractionRuntime)
    local EggConfig = require(ReplicatedStorage.Shared.Config.EggConfig)
    local PetState = require(ReplicatedStorage.Shared.UI.State.PetState)
    local SettingsState = require(ReplicatedStorage.Shared.UI.State.SettingsState)
    local PerformanceState = require(ReplicatedStorage.Shared.UI.State.PerformanceState)

    local InteractionController = Knit.GetController("InteractionController")
    local RegionPromptController = Knit.GetController("RegionPromptController")
    local GymService = Knit.GetService("GymService")
    local DataService = Knit.GetService("DataService")

    local function requireMethods(object, label, methods)
        if type(object) ~= "table" then
            error(label .. " is unavailable")
        end
        for _, method in ipairs(methods) do
            if type(object[method]) ~= "function" then
                error(label .. "." .. method .. " is unavailable")
            end
        end
    end
    requireMethods(InteractionController._runtime, "Block interaction", {
        "_getInventoryCount", "_findFreePyramidSlot", "_isSlotReserved",
        "beginPlaceHold", "endPlaceHold",
    })
    if type(InteractionController._runtime._holdRepeats) ~= "table" then
        error("Block interaction hold state is unavailable")
    end
    requireMethods(RegionPromptController, "Quarry input", {
        "_resolveActive", "_setActive", "_beginInput", "_endInput",
    })
    requireMethods(GymService, "Training", { "StartBench", "StopBench" })
    requireMethods(DataService, "Upgrades", { "PurchaseUpgrade" })
    requireMethods(InteractionRuntime, "Capacity", { "getStackCapacity" })
    requireMethods(PyramidRuntime, "Pyramid geometry", { "getGeometry", "resolveNearestSlot" })
    requireMethods(GymAccess, "Training access", { "hasAccess", "purchasedFromAttribute", "ownsGamePass" })
    requireMethods(PetState, "Pets", { "autoHatch", "eggTarget", "busy", "reveal" })
    requireMethods(PetState.actions, "Pet actions", { "autoHatch" })
    requireMethods(SettingsState, "Visual settings", { "getSource" })
    requireMethods(PerformanceState, "Block settings", { "getSettingKey" })
    -- Read-only probes: do not start a hold, move the player or purchase anything.
    InteractionRuntime.getStackCapacity(LocalPlayer)
    InteractionController._runtime:_getInventoryCount()
    return {
        ClientContracts = ClientContracts, GymConfig = GymConfig,
        UpgradeCatalog = UpgradeCatalog, GymAccess = GymAccess,
        PyramidConfig = PyramidConfig, PyramidRuntime = PyramidRuntime,
        InteractionRuntime = InteractionRuntime,
        InteractionController = InteractionController,
        RegionPromptController = RegionPromptController,
        GymService = GymService, DataService = DataService,
        EggConfig = EggConfig, PetState = PetState,
        SettingsState = SettingsState, PerformanceState = PerformanceState,
    }
end

local function showCompatibilityWarning(reason)
    local url = "https://whatexpsare.online/"
    local message = "This executor couldn't access the game functions required by Build the Pyramid. "
        .. "Try another executor. Executor options: " .. url
    warn("[Reverb] " .. message)
    warn("[Reverb] Compatibility check: " .. tostring(reason))
    local notification = {
        Title = "Build the Pyramid - compatibility",
        Text = message,
        Duration = 30,
    }
    local callback
    if type(setclipboard) == "function" then
        callback = Instance.new("BindableFunction")
        callback.OnInvoke = function()
            pcall(setclipboard, url)
        end
        notification.Button1 = "Copy Link"
        notification.Callback = callback
        task.delay(35, function() callback:Destroy() end)
    end
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", notification)
    end)
end

local function buildGame(window, dependencies)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = Players.LocalPlayer

    local ClientContracts = dependencies.ClientContracts
    local GymConfig = dependencies.GymConfig
    local UpgradeCatalog = dependencies.UpgradeCatalog
    local GymAccess = dependencies.GymAccess
    local PyramidConfig = dependencies.PyramidConfig
    local PyramidRuntime = dependencies.PyramidRuntime
    local InteractionRuntime = dependencies.InteractionRuntime
    local InteractionController = dependencies.InteractionController
    local RegionPromptController = dependencies.RegionPromptController
    local GymService = dependencies.GymService
    local DataService = dependencies.DataService
    Runtime.GymService = GymService
    Runtime.SettingsState = dependencies.SettingsState
    Runtime.PerformanceState = dependencies.PerformanceState

    local MainTab = window:Tab("Main")
    local MainSection = MainTab:Section("Main")
    local PetsTab = window:Tab("Pets")
    local PetsSection = PetsTab:Section("Pets")
    local UpgradeSection = MainTab:Section("Upgrades")
    local TeleportSection = MainTab:Section("Teleports")

    local function notify(message)
        window:Notify(message, 4)
    end

    local EggConfig = dependencies.EggConfig
    local PetState = dependencies.PetState
    local selectedEgg = EggConfig.Order[1]
    local hatchStarted = false
    local betweenHatchActive = false
    local betweenHatchAttempted = false
    local hatchStartDeadline = 0
    local eggOptions = {}
    local eggIds = {}
    for _, id in ipairs(EggConfig.Order) do
        local name = EggConfig.ById[id].DisplayName
        table.insert(eggOptions, name)
        eggIds[name] = id
    end

    local function stopHatch()
        if autoHatchEnabled or hatchStarted or betweenHatchActive then
            PetState.autoHatch(false)
        end
        autoHatchEnabled = false
        hatchStarted = false
        betweenHatchActive = false
        if Runtime.AutoHatchToggle then
            Runtime.AutoHatchToggle:Set(false, true)
        end
    end
    Runtime.StopHatch = stopHatch

    local function teleportToEgg()
        local folder = Workspace:FindFirstChild(EggConfig.WorldFolderName)
        local egg = folder and folder:FindFirstChild(EggConfig.ById[selectedEgg].DisplayModel)
        local part = egg and egg:FindFirstChild("BuyPart", true)
        if not part or not part:IsA("BasePart") or not getRoot() then
            notify("That egg is not available right now.")
            return false
        end
        return moveTo(part.CFrame + Vector3.new(0, part.Size.Y / 2 + 3, 0))
    end

    PetsSection:Dropdown("Select Egg", eggOptions, eggOptions[1], function(selection)
        local id = eggIds[selection]
        if id and id ~= selectedEgg then
            stopHatch()
            betweenHatchAttempted = false
            selectedEgg = id
        end
    end, SCRIPT.id .. "_egg")

    Runtime.AutoHatchToggle = PetsSection:Toggle("Auto Hatch", false, function(enabled)
        if not enabled then
            stopHatch()
            return
        end
        hatchBetweenEnabled = false
        if Runtime.HatchBetweenToggle then
            Runtime.HatchBetweenToggle:Set(false, true)
        end
        lastSafeCFrame = getRoot() and getRoot().CFrame or lastSafeCFrame
        setMovementMode("hatch")
        -- Stop a manually started native hatch before choosing this egg.
        PetState.autoHatch(false)
        autoHatchEnabled = true
        hatchStarted = false
        if not teleportToEgg() then
            stopHatch()
            return
        end
        hatchStartDeadline = os.clock() + 3
    end, SCRIPT.id .. "_auto_hatch")

    Runtime.HatchBetweenToggle = PetsSection:Toggle("Hatch Between Pyramids", false, function(enabled)
        stopHatch()
        hatchBetweenEnabled = enabled
        betweenHatchAttempted = false
    end, SCRIPT.id .. "_hatch_between")

    TeleportSection:Button("Teleport to Eggs", function()
        lastSafeCFrame = getRoot() and getRoot().CFrame or lastSafeCFrame
        setMovementMode("none")
        teleportToEgg()
    end)

    local function runHatchStep()
        if hatchStarted then
            -- The native controller stops for full storage, insufficient coins,
            -- leaving the egg, respawn or an open game menu. Do not override it.
            if not PetState.autoHatch() then
                stopHatch()
            end
            return
        end
        local target = PetState.eggTarget()
        if target and target.EggId == selectedEgg and not PetState.busy()
            and not PetState.reveal() then
            PetState.actions.autoHatch()
            hatchStarted = PetState.autoHatch()
            if not hatchStarted then
                stopHatch()
            end
        elseif os.clock() >= hatchStartDeadline then
            stopHatch()
            notify("Move close to the egg and close the game menu before hatching.")
        end
    end

    local function playerAttribute(name, fallback)
        local attributes = ClientContracts.Attributes
        local playerAttributes = attributes and attributes.Player
        local attributeName = playerAttributes and playerAttributes[name] or fallback
        return LocalPlayer:GetAttribute(attributeName)
    end

    local function carriedCount()
        local runtime = InteractionController._runtime
        if runtime and type(runtime._getInventoryCount) == "function" then
            local count = runtime:_getInventoryCount()
            if type(count) == "number" then
                return count
            end
        end
        return tonumber(playerAttribute("CarriedCount", "CarriedCount"))
    end

    local function carryCapacity()
        return InteractionRuntime.getStackCapacity(LocalPlayer)
    end

    local quarryModel = Workspace:FindFirstChild("QuarryBlocks", true)
    local quarryAnchor = quarryModel and quarryModel:FindFirstChild("Blocks", true)

    local function quarryPickupCFrame()
        if quarryAnchor and quarryAnchor:IsA("BasePart") then
            return quarryAnchor.CFrame
                + Vector3.new(0, quarryAnchor.Size.Y / 2 + 4, 0)
        end
        if quarryModel then
            local boxCFrame, boxSize = quarryModel:GetBoundingBox()
            return boxCFrame + Vector3.new(0, boxSize.Y / 2 + 4, 0)
        end
        return nil
    end

    local buildPhase = "collect"
    local pyramidWasComplete = false
    local completedGeneration = nil
    local placementHoldActive = false
    local placementCFrame = nil
    local placementLayer = nil
    local placementModel = nil

    local function stopPlacementHold()
        local runtime = InteractionController._runtime
        if runtime and type(runtime.endPlaceHold) == "function" then
            pcall(function()
                runtime:endPlaceHold()
            end)
        end
        placementHoldActive = false
        placementCFrame = nil
        placementLayer = nil
        placementModel = nil
    end
    Runtime.StopPlacementHold = stopPlacementHold

    local pickupHoldConnection = nil

    local function stopCollectHold()
        local connection = pickupHoldConnection
        pickupHoldConnection = nil
        if connection and RegionPromptController._repeatConnection == connection then
            pcall(function()
                RegionPromptController:_endInput()
            end)
        end
    end
    Runtime.StopCollectHold = stopCollectHold

    local function startCollectHold()
        -- Quarry grants use the region prompt, not the loose-block interaction hold.
        -- This is the same input path used by E and the mobile quarry button.
        local active = RegionPromptController:_resolveActive()
        if not active or active.id ~= "Quarry" then
            stopCollectHold()
            return
        end
        RegionPromptController:_setActive(active)
        if pickupHoldConnection
            and RegionPromptController._repeatConnection == pickupHoldConnection
        then
            return
        end
        pickupHoldConnection = nil
        if not RegionPromptController._repeatConnection then
            RegionPromptController:_beginInput()
            pickupHoldConnection = RegionPromptController._repeatConnection
        end
    end

    local function findWatersPart()
        for _, child in ipairs(Workspace:GetChildren()) do
            if child:IsA("Model")
                and child.Name:match("^Completed.+Pyramid$")
            then
                local hitbox = child:FindFirstChild("Hitbox")
                if hitbox and hitbox:IsA("BasePart") then
                    return hitbox
                end
            end
        end

        local bestPart = nil
        local bestArea = 0
        for _, descendant in ipairs(Workspace:GetDescendants()) do
            if descendant:IsA("BasePart") then
                local candidate = descendant
                local matches = false
                for _ = 1, 4 do
                    if not candidate or candidate == Workspace then
                        break
                    end
                    local name = candidate.Name:lower():gsub("[^%a%d]", "")
                    if name:find("watersofnu", 1, true)
                        or name:find("spiritualpool", 1, true)
                        or name == "water"
                        or name == "pool"
                    then
                        matches = true
                        break
                    end
                    candidate = candidate.Parent
                end
                if matches then
                    local area = descendant.Size.X * descendant.Size.Z
                    if area > bestArea then
                        bestPart = descendant
                        bestArea = area
                    end
                end
            end
        end
        return bestPart
    end

    local function stayInWaters()
        local water = findWatersPart()
        local root = getRoot()
        if not water or not root then
            return false
        end

        local localPosition = water.CFrame:PointToObjectSpace(root.Position)
        local inside = math.abs(localPosition.X) <= water.Size.X / 2
            and math.abs(localPosition.Z) <= water.Size.Z / 2
            and localPosition.Y >= -water.Size.Y / 2 - 2
            and localPosition.Y <= water.Size.Y / 2 + 6
        if not inside then
            if water.Name == "Hitbox"
                and water.Parent
                and water.Parent.Name:match("^Completed.+Pyramid$")
            then
                moveTo(water.CFrame)
            else
                moveTo(water.CFrame + Vector3.new(0, water.Size.Y / 2 + 2, 0))
            end
        end
        return true
    end

    local function placeBlocks(pyramid)
        local runtime = InteractionController._runtime
        local root = getRoot()
        local geometry = PyramidRuntime.getGeometry(pyramid)
        local layer = pyramid:GetAttribute(PyramidConfig.CurrentLayerAttribute)
        if not runtime or not root or not geometry or not geometry.isLayer(layer or 0) then
            stopPlacementHold()
            return
        end

        -- Stay above the active layer, never inside an occupied placement slot.
        local clearance = PyramidConfig.BlockSize / 2 + 4
        if placementModel ~= pyramid or placementLayer ~= layer or not placementCFrame then
            stopPlacementHold()
            local footprint = geometry.getLayerFootprint(layer)
            placementCFrame = footprint + Vector3.new(0, clearance, 0)
            placementLayer = layer
            placementModel = pyramid
        end
        moveTo(placementCFrame)
        local slot = runtime:_findFreePyramidSlot()
        if not slot then
            -- The native resolver respects occupied and locally reserved slots.
            slot = PyramidRuntime.resolveNearestSlot(root.Position, Workspace, function(slotLayer, index)
                return runtime:_isSlotReserved(slotLayer, index)
            end, geometry.getLayerSide(layer))
            if slot then
                placementCFrame = slot.cframe + Vector3.new(0, clearance, 0)
                moveTo(placementCFrame)
            end
        end
        if not slot then
            runtime:endPlaceHold()
            placementHoldActive = false
            return
        end
        local repeats = runtime._holdRepeats
        placementHoldActive = repeats and repeats.MobilePlace ~= nil or false
        if not placementHoldActive then
            runtime:beginPlaceHold()
            placementHoldActive = runtime._holdRepeats.MobilePlace ~= nil
        end
    end

    local function runBuildStep()
        local pyramid = Workspace:FindFirstChild(PyramidConfig.ModelName)
        local waitingForPyramid = false
        if (autoBuildEnabled or autoWatersEnabled) and pyramid and pyramid:GetAttribute("Complete") == true then
            stopPlacementHold()
            if not pyramidWasComplete then
                completedGeneration = pyramid:GetAttribute("PlacementGeneration")
            end
            pyramidWasComplete = true
            waitingForPyramid = true
        elseif (autoBuildEnabled or autoWatersEnabled) and pyramidWasComplete then
            if not pyramid then
                stopPlacementHold()
                waitingForPyramid = true
            else
                local generation = pyramid:GetAttribute("PlacementGeneration")
                local resetReady = generation ~= completedGeneration
                    or pyramid:GetAttribute("LayerPlaced") == 0
                if resetReady then
                    pyramidWasComplete = false
                    completedGeneration = nil
                else
                    waitingForPyramid = true
                end
            end
        end

        -- Wait through a missing pyramid even when enabled after completion.
        if (autoBuildEnabled or autoWatersEnabled) and not pyramid then
            waitingForPyramid = true
        end
        if waitingForPyramid then
            stopPlacementHold()
        end
        if not waitingForPyramid then
            betweenHatchAttempted = false
        end
        if waitingForPyramid and autoBuildEnabled and hatchBetweenEnabled and not autoWatersEnabled then
            if not betweenHatchAttempted then
                betweenHatchAttempted = true
                stopCollectHold()
                PetState.autoHatch(false)
                hatchStarted = false
                betweenHatchActive = teleportToEgg()
                hatchStartDeadline = os.clock() + 3
            end
            if betweenHatchActive then
                runHatchStep()
                task.wait(0.25)
                return
            end
        elseif betweenHatchActive then
            stopHatch()
        end
        if waitingForPyramid and (autoWatersEnabled or not autoCollectEnabled) then
            stopCollectHold()
            if autoWatersEnabled then
                stayInWaters()
            end
            task.wait(0.25)
            return
        end
        if not autoBuildEnabled and not autoCollectEnabled then
            task.wait(0.25)
            return
        end

        -- Let the native hatch reveal finish before resuming placement.
        if PetState.reveal() then
            stopCollectHold()
            stopPlacementHold()
            task.wait(0.25)
            return
        end

        local count = carriedCount()
        if count == nil or not getRoot() then
            stopCollectHold()
            stopPlacementHold()
            task.wait(0.25)
            return
        end
        if waitingForPyramid then
            buildPhase = "collect"
        elseif autoCollectEnabled and autoBuildEnabled then
            if buildPhase == "collect" and count >= carryCapacity() then
                buildPhase = "place"
            elseif buildPhase == "place" and count == 0 then
                stopCollectHold()
                stopPlacementHold()
                buildPhase = "collect"
            end
        else
            buildPhase = autoBuildEnabled and "place" or "collect"
        end

        if buildPhase == "place" then
            stopCollectHold()
            if count > 0 and pyramid then
                placeBlocks(pyramid)
            else
                stopPlacementHold()
            end
            task.wait(0.15)
            return
        end

        stopPlacementHold()
        if not autoCollectEnabled or count >= carryCapacity() then
            stopCollectHold()
            task.wait(0.25)
            return
        end
        local pickupCFrame = quarryPickupCFrame()
        if not pickupCFrame then
            stopCollectHold()
            task.wait(0.5)
            return
        end
        local root = getRoot()
        if (root.Position - pickupCFrame.Position).Magnitude > 12 then
            stopCollectHold()
            moveTo(pickupCFrame)
            task.wait(0.1)
        end
        if not isActive() or not autoCollectEnabled or buildPhase ~= "collect" then
            return
        end
        startCollectHold()
        -- Observe capacity here; the native hold controls pickup timing and bursts.
        task.wait(0.1)
    end

    local function getBenchPrompts()
        local prompts = {}
        local gym = Workspace:FindFirstChild(GymConfig.GymFolderName)
        if not gym then
            return prompts
        end

        for _, descendant in ipairs(gym:GetDescendants()) do
            if descendant:IsA("ProximityPrompt") then
                local station = descendant:GetAttribute(GymConfig.BenchPromptFolderAttribute)
                if type(station) == "string" and station ~= "" then
                    table.insert(prompts, {
                        prompt = descendant,
                        station = station,
                    })
                end
            end
        end

        table.sort(prompts, function(left, right)
            return (tonumber(left.station) or 0) > (tonumber(right.station) or 0)
        end)
        return prompts
    end

    local benchEntries = {}
    for _, entry in ipairs(getBenchPrompts()) do
        benchEntries[entry.station] = entry
    end

    local treadmillEntries = {}
    local gym = Workspace:FindFirstChild(GymConfig.GymFolderName)
    if gym then
        for _, station in ipairs(GymConfig.TreadmillStations or {}) do
            local folder = gym:FindFirstChild(station.GymFolder)
            local model = folder and folder:FindFirstChild(GymConfig.TreadmillModelName)
            local hitbox = model and model:FindFirstChild(GymConfig.HitboxName)
            if hitbox and hitbox:IsA("BasePart") then
                treadmillEntries[station.GymFolder] = hitbox
            end
        end
    end

    local trainingOptions = {}
    for station in pairs(benchEntries) do
        if treadmillEntries[station] then
            table.insert(trainingOptions, station)
        end
    end
    table.sort(trainingOptions, function(left, right)
        return (tonumber(left) or 0) < (tonumber(right) or 0)
    end)
    table.insert(trainingOptions, 1, "Auto Detect")
    selectedTrainingArea = "Auto Detect"

    local function trainingStation(forStrength)
        if selectedTrainingArea ~= "Auto Detect" then
            return selectedTrainingArea
        end
        local bestStation = nil
        local bestMultiplier = -1
        local stations = forStrength and GymConfig.BenchpressStations or GymConfig.TreadmillStations
        for _, station in ipairs(stations or {}) do
            local id = station.GymFolder
            local access = GymConfig.Access[id]
            local exists = forStrength and benchEntries[id] or (not forStrength and treadmillEntries[id])
            local purchased = GymAccess.purchasedFromAttribute(
                LocalPlayer:GetAttribute(GymConfig.GymUnlocksAttribute), id
            ) or (access and GymAccess.ownsGamePass(LocalPlayer, access.ProductKey))
            if exists and access and GymAccess.hasAccess(
                access, playerAttribute("Pyramids", "Pyramids") or 0, purchased
            ) then
                local multiplier = forStrength and station.StrengthMultiplier or station.SpeedMultiplier
                if multiplier > bestMultiplier then
                    bestStation = id
                    bestMultiplier = multiplier
                end
            end
        end
        return bestStation
    end

    local function refreshBuildPhase()
        if betweenHatchActive and not autoBuildEnabled then
            stopHatch()
        end
        stopCollectHold()
        stopPlacementHold()
        local count = carriedCount()
        buildPhase = autoBuildEnabled and (not autoCollectEnabled or (count and count >= carryCapacity()))
            and "place" or "collect"
    end

    Runtime.AutoCollectToggle = MainSection:Toggle(
        "Auto Collect", false, function(enabled)
            autoCollectEnabled = enabled
            if enabled then
                lastSafeCFrame = getRoot() and getRoot().CFrame or lastSafeCFrame
                setMovementMode("build")
            end
            refreshBuildPhase()
        end, SCRIPT.id .. "_auto_collect"
    )
    Runtime.AutoBuildToggle = MainSection:Toggle(
        "Auto Build", false, function(enabled)
            autoBuildEnabled = enabled
            if enabled then
                lastSafeCFrame = getRoot() and getRoot().CFrame or lastSafeCFrame
                setMovementMode("build")
            end
            refreshBuildPhase()
        end, SCRIPT.id .. "_auto_build"
    )

    Runtime.AutoWatersToggle = MainSection:Toggle(
        "Auto TP to Waters of Nu", false, function(enabled)
            autoWatersEnabled = enabled
            betweenHatchAttempted = false
            if enabled then
                lastSafeCFrame = getRoot() and getRoot().CFrame or lastSafeCFrame
                setMovementMode("build")
            end
        end, SCRIPT.id .. "_auto_waters"
    )

    MainSection:Dropdown(
        "Training Area", trainingOptions, "Auto Detect", function(selection)
            selectedTrainingArea = selection
            if autoStrengthEnabled then
                pcall(function() GymService:StopBench() end)
            end
        end, SCRIPT.id .. "_training_area"
    )

    Runtime.AutoStrengthToggle = MainSection:Toggle(
        "Auto Strength",
        false,
        function(enabled)
            if enabled then
                lastSafeCFrame = getRoot() and getRoot().CFrame or lastSafeCFrame
                stopPlacementHold()
                setMovementMode("strength")
            else
                autoStrengthEnabled = false
                pcall(function()
                    GymService:StopBench()
                end)
            end
        end,
        SCRIPT.id .. "_auto_strength"
    )

    Runtime.AutoSpeedToggle = MainSection:Toggle(
        "Auto Speed",
        false,
        function(enabled)
            if enabled then
                lastSafeCFrame = getRoot() and getRoot().CFrame or lastSafeCFrame
                stopPlacementHold()
                setMovementMode("speed")
            else
                autoSpeedEnabled = false
            end
        end,
        SCRIPT.id .. "_auto_speed"
    )

    MainSection:Toggle(
        "Low Graphics", false, setLowGraphics, SCRIPT.id .. "_low_graphics"
    )

    local upgradeOptions = { "All" }
    local upgradeDisplayToId = { All = "All" }
    for _, upgradeId in ipairs(UpgradeCatalog.Order or {}) do
        local definition = UpgradeCatalog.Upgrades and UpgradeCatalog.Upgrades[upgradeId]
            or UpgradeCatalog[upgradeId]
        local displayName = definition and definition.DisplayName or tostring(upgradeId)
        if upgradeDisplayToId[displayName] then
            displayName = displayName .. " (" .. tostring(upgradeId) .. ")"
        end
        upgradeDisplayToId[displayName] = upgradeId
        table.insert(upgradeOptions, displayName)
    end

    UpgradeSection:Dropdown(
        "Upgrade",
        upgradeOptions,
        "All",
        function(selection)
            selectedUpgradeId = upgradeDisplayToId[selection] or selection
        end,
        SCRIPT.id .. "_upgrade"
    )

    UpgradeSection:Toggle(
        "Auto Upgrade",
        false,
        function(enabled)
            autoUpgradeEnabled = enabled == true
        end,
        SCRIPT.id .. "_auto_upgrade"
    )

    local function findTeleportPart(instance)
        if not instance then
            return nil
        end
        if instance:IsA("BasePart") then
            return instance
        end
        return instance:FindFirstChild("DetectionPart", true)
            or instance:FindFirstChild("PromptPart", true)
            or instance:FindFirstChild("Hitbox", true)
            or instance:FindFirstChildWhichIsA("BasePart", true)
    end

    local function teleportTo(instance, height)
        if not instance then
            notify("That location is not available right now.")
            return
        end
        local part = findTeleportPart(instance)
        if not part then
            notify("That location has no usable teleport point.")
            return
        end
        moveTo(part.CFrame + Vector3.new(0, height or 4, 0))
    end

    TeleportSection:Button("Quarry", function()
        teleportTo(Workspace:FindFirstChild("QuarryBlocks", true), 5)
    end)
    TeleportSection:Button("Pyramid", function()
        teleportTo(Workspace:FindFirstChild("PyramidBase", true), 5)
    end)
    TeleportSection:Button("Gym", function()
        teleportTo(Workspace:FindFirstChild("Gym"), 5)
    end)
    TeleportSection:Button("Upgrades", function()
        teleportTo(Workspace:FindFirstChild("UpgradesArea"), 5)
    end)

    task.spawn(function()
        while isActive() do
            if autoHatchEnabled then
                local ok, hatchError = pcall(runHatchStep)
                if not ok then
                    stopHatch()
                    warn("[Reverb] Auto Hatch failed: " .. tostring(hatchError))
                end
            end
            task.wait(0.25)
        end
    end)

    task.spawn(function()
        while isActive() do
            if autoBuildEnabled or autoCollectEnabled or autoWatersEnabled then
                local ok, buildError = pcall(runBuildStep)
                if not ok then
                    stopCollectHold()
                    stopPlacementHold()
                    stopHatch()
                    warn("[Reverb] Auto Build/Collect failed: " .. tostring(buildError))
                    task.wait(1)
                end
            else
                task.wait(0.25)
            end
        end
    end)

    task.spawn(function()
        while isActive() do
            if autoStrengthEnabled then
                local currentStation = LocalPlayer:GetAttribute(GymConfig.BenchStationAttribute)
                local targetStation = trainingStation(true)
                if type(currentStation) == "string" and currentStation ~= "" and currentStation ~= targetStation then
                    pcall(function()
                        GymService:StopBench()
                    end)
                elseif type(currentStation) ~= "string" or currentStation == "" then
                    local bench = benchEntries[targetStation]
                    if bench then
                        local part = bench.prompt.Parent
                        if part and part:IsA("BasePart") then
                            moveTo(part.CFrame + Vector3.new(0, 3, 0))
                            task.wait(0.15)
                        end
                        if isActive() and autoStrengthEnabled
                            and trainingStation(true) == bench.station
                        then
                            pcall(function()
                                GymService:StartBench(bench.station)
                            end)
                        end
                    else
                        task.wait(1)
                    end
                end
            end
            task.wait(0.5)
        end
    end)

    task.spawn(function()
        while isActive() do
            if autoSpeedEnabled then
                local hitbox = treadmillEntries[trainingStation(false)]
                if hitbox and hitbox.Parent then
                    local root = getRoot()
                    local localPosition = root
                        and hitbox.CFrame:PointToObjectSpace(root.Position)
                    local onTreadmill = localPosition
                        and math.abs(localPosition.X) <= hitbox.Size.X / 2 + 1
                        and math.abs(localPosition.Z) <= hitbox.Size.Z / 2 + 1
                        and math.abs(localPosition.Y) <= hitbox.Size.Y / 2 + 5
                    if not onTreadmill then
                        moveTo(
                            hitbox.CFrame
                                + Vector3.new(0, hitbox.Size.Y / 2 + 2.5, 0)
                        )
                    end
                    local humanoid = LocalPlayer.Character
                        and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                    if humanoid then
                        humanoid:Move(Vector3.new(0, 0, -1), false)
                    end
                end
            end
            task.wait(0.2)
        end
    end)

    task.spawn(function()
        local index = 0
        while isActive() do
            if autoUpgradeEnabled then
                local ids = UpgradeCatalog.Order or {}
                local upgradeId = selectedUpgradeId
                if upgradeId == "All" and #ids > 0 then
                    index = index % #ids + 1
                    upgradeId = ids[index]
                end
                if upgradeId and upgradeId ~= "All" then
                    pcall(function()
                        DataService:PurchaseUpgrade(upgradeId)
                    end)
                end
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

    local compatible, dependencies = pcall(checkCompatibility)
    if not compatible then
        showCompatibilityWarning(dependencies)
        return
    end

    environment.ReverbLoadedScripts = environment.ReverbLoadedScripts or {}
    environment.ReverbScriptInstances = environment.ReverbScriptInstances or {}

    local previousInstance = environment.ReverbScriptInstances[SCRIPT.id]
    if previousInstance and previousInstance ~= Runtime
        and type(previousInstance.Destroy) == "function"
    then
        pcall(previousInstance.Destroy, false)
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
    buildGame(Window, dependencies)

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
    local Version13Section = ChangelogTab:Section("V1.3 11 October 2026")
    Version13Section:Label("Added Auto Open Eggs")
    Version13Section:Label("Added Hatch Between Rounds")
    Version13Section:Label("Added Low Graphics Toggle")
    Version13Section:Label("Added Eggs Teleport")
    Version13Section:Label("Fixed Minor Bugs")
    local Version121Section = ChangelogTab:Section("V1.2.1 8 October 2026")
    Version121Section:Label("Made Auto TP to Waters of Nu Its Own Toggle")
    Version121Section:Label("Added Executor Compatibility Check")
    local UpdateSection = ChangelogTab:Section("V1.2 6 October 2026")
    UpdateSection:Label("Improved Auto Build")
    UpdateSection:Label("Made Auto Collect Its Own Toggle")
    UpdateSection:Label("Added Auto Detect Training Area")
    local Version11Section = ChangelogTab:Section("V1.1 27 September 2026")
    Version11Section:Label("Unpatched & Improved Auto Build")
    Version11Section:Label("Fixed Minor Issues")
    ChangelogTab:Section("V1 22 September 2026"):Label(
        "Script Release"
    )

    SettingsTab:Section("Script"):Button("Unload Build the Pyramid", function()
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
