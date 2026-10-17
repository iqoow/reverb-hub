-- +1 STRENGTH TO GROW YOUR ARM

local SCRIPT = {
    id = "1StrengthtoGrowYourArm",
    name = "+1STGYA",
    version = "V1.0.1",
    updated = "14th September 2026",
    author = "Reverb",
}

local TARGET_PLACE_ID = 86259628805375
local REVERB_J_URL =
    "https://cdn.jsdelivr.net/gh/rbxreverb/ReverbJ@80e356f5739100647d51710798eca38c960afe86/source.lua"
local AUTO_SAVE_CFRAME = CFrame.new(
    133.769363, 239.341721, -924.382568,
    -0.97525841, -7.89108157e-08, 0.221067891,
    -8.49045207e-08, 1, -1.76101231e-08,
    -0.221067891, -3.59440833e-08, -0.97525841
)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local environment = (getgenv and getgenv()) or _G
local instanceToken = {}
local destroyed = false
local cleanupCallbacks = {}

local Runtime = {
    Script = SCRIPT,
    Environment = environment,
}

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
        pcall(cleanupCallbacks[index])
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
        pcall(function()
            library:Destroy()
        end)
    end
end

local function start()
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end

    if game.PlaceId ~= TARGET_PLACE_ID then
        warn("[Reverb] This test script was built for place " .. tostring(TARGET_PLACE_ID))
    end

    environment.ReverbLoadedScripts = environment.ReverbLoadedScripts or {}
    environment.ReverbScriptInstances = environment.ReverbScriptInstances or {}

    local previous = environment.ReverbScriptInstances[SCRIPT.id]
    if previous and previous ~= Runtime and type(previous.Destroy) == "function" then
        pcall(previous.Destroy)
    end

    environment.ReverbLoadedScripts[SCRIPT.id] = instanceToken
    environment.ReverbScriptInstances[SCRIPT.id] = Runtime

    local loadLibrary, compileError = loadstring(game:HttpGet(REVERB_J_URL))
    if not loadLibrary then
        error("Reverb J failed to compile: " .. tostring(compileError))
    end

    local ReverbJ = loadLibrary()
    if type(ReverbJ) ~= "table" or type(ReverbJ.CreateWindow) ~= "function" then
        error("Reverb J did not return a valid library")
    end

    local access = environment.ReverbAccess or {}
    local accessTier = tostring(access.tier or environment.ReverbKeyTier or "free"):lower()
    local Window = ReverbJ:CreateWindow({
        Game = SCRIPT.name,
        Tier = accessTier == "premium" and "PREMIUM" or "FREE",
        RememberSettings = false,
        ConfigName = SCRIPT.id,
    })

    Runtime.Library = ReverbJ
    Runtime.Window = Window

    local Main = Window:Tab("Main")
    local PetSection = Main:Section("Main")
    local PurchaseSection = Main:Section("Auto Buy")
    local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent", 15)
    local selectedArea = "Best Area"
    local autoGetPets = false
    local autoTrain = false
    local autoCollectCash = false
    local autoUpgradePlacedPets = false
    local autoRebirth = false
    local resumeTrainingAfterPets = false
    local actionDelay = 0.15
    local pickupHoldDelay = 0.85
    local saveZoneDwell = 0.7
    local wallTriggerDwell = 0.55
    local busy = false
    local areaDropdown
    local autoPetsControl
    local autoTrainControl
    local attemptedPets = {}
    local changingToggleInternally = false
    local recoveringPets = false

    local function notify(message)
        if type(Window.Notify) == "function" then
            Window:Notify(message, 4)
        else
            warn("[Reverb] " .. tostring(message))
        end
    end

    local function setToggleControl(control, value)
        if not control or type(control.Set) ~= "function" then
            return
        end
        changingToggleInternally = true
        pcall(function()
            control:Set(value)
        end)
        changingToggleInternally = false
    end

    local function unequipTools()
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid:UnequipTools()
        end
    end

    local function suspendTrainingForPets()
        if autoTrain then
            resumeTrainingAfterPets = true
        end
        autoTrain = false
        setToggleControl(autoTrainControl, false)
        unequipTools()
    end

    local function restoreTrainingAfterPets()
        if not resumeTrainingAfterPets then
            return
        end
        resumeTrainingAfterPets = false
        autoTrain = true
        setToggleControl(autoTrainControl, true)
    end

    local function getDataFolder()
        local brainrotFolder = Workspace:FindFirstChild("BrainrotFolder")
        return brainrotFolder and brainrotFolder:FindFirstChild("data")
    end

    local function getAreaNumber(folder)
        if not folder then
            return nil
        end
        return tonumber(folder.Name:match("^Area(%d+)$"))
    end

    local function getAreas()
        local areas = {}
        local dataFolder = getDataFolder()
        if dataFolder then
            for _, child in ipairs(dataFolder:GetChildren()) do
                local number = getAreaNumber(child)
                if number then
                    table.insert(areas, {
                        folder = child,
                        name = child.Name,
                        number = number,
                    })
                end
            end
        end
        table.sort(areas, function(left, right)
            return left.number > right.number
        end)
        return areas
    end

    local function getAreaOptions()
        local options = { "Best Area" }
        for _, area in ipairs(getAreas()) do
            table.insert(options, area.name)
        end
        return options
    end

    local function getSelectedAreaFolder()
        local areas = getAreas()
        if selectedArea == "Best Area" then
            for _, area in ipairs(areas) do
                if #area.folder:GetChildren() > 0 then
                    return area.folder
                end
            end
            return nil
        end

        for _, area in ipairs(areas) do
            if area.name == selectedArea then
                return area.folder
            end
        end
        return nil
    end

    local function teleportTo(targetCFrame)
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then
            return false, "Character is not ready"
        end
        root.CFrame = targetCFrame
        return true
    end

    local function buildPetModelLookup()
        local lookup = {
            byUid = {},
            byKind = {},
        }
        for _, descendant in ipairs(Workspace:GetDescendants()) do
            if descendant:IsA("Model")
                and descendant:GetAttribute("area")
                and descendant:GetAttribute("name")
            then
                local area = tostring(descendant:GetAttribute("area"))
                local name = tostring(descendant:GetAttribute("name"))
                local uid = descendant:GetAttribute("uid")
                if uid then
                    lookup.byUid[tostring(uid)] = descendant
                end
                lookup.byUid[descendant.Name] = descendant
                lookup.byKind[area .. "\0" .. name] = descendant
            end
        end
        return lookup
    end

    local function getLabelText(model, labelName)
        if not model then
            return ""
        end
        for _, descendant in ipairs(model:GetDescendants()) do
            if descendant:IsA("TextLabel") and descendant.Name == labelName then
                return descendant.Text
            end
        end
        return ""
    end

    local function parseIncome(text)
        local cleaned = tostring(text):gsub("[$,%s/]", ""):lower()
        local number, suffix = cleaned:match("([%d%.]+)([kmbtq]*)")
        local multipliers = { k = 1e3, m = 1e6, b = 1e9, t = 1e12, q = 1e15 }
        return (tonumber(number) or 0) * (multipliers[suffix] or 1)
    end

    local function petDetails(entry, modelLookup)
        local area = tostring(entry:GetAttribute("area") or (entry.Parent and entry.Parent.Name) or "")
        local name = tostring(entry:GetAttribute("brainrot") or "")
        local model = modelLookup.byUid[entry.Name] or modelLookup.byKind[area .. "\0" .. name]
        local incomeText = getLabelText(model, "Income")
        return {
            entry = entry,
            model = model,
            income = parseIncome(incomeText),
        }
    end

    local function getWorldCFrame(instance)
        if not instance or not instance.Parent then
            return nil
        end
        if instance:IsA("BasePart") then
            return instance.CFrame
        end
        if instance:IsA("Model") then
            local succeeded, pivot = pcall(instance.GetPivot, instance)
            if succeeded then
                return pivot
            end
        end
        local part = instance:FindFirstChildWhichIsA("BasePart", true)
        return part and part.CFrame or nil
    end

    local function getWall(wallNumber)
        local expectedName = "BlockWall" .. tostring(wallNumber)
        for _, descendant in ipairs(Workspace:GetDescendants()) do
            if descendant.Name == expectedName
                and (descendant:IsA("Model") or descendant:IsA("BasePart"))
            then
                return descendant
            end
        end
        return nil
    end

    local function traverseToPetArea(pet)
        local areaNumber = getAreaNumber(pet and pet.Parent)
        if not areaNumber then
            return false, "Could not determine the selected pet's area"
        end

        -- A manual pickup advances through BlockWall1..N before the server
        -- accepts PickUpBrainrot. Visit the live wall objects in that same order
        -- and leave enough time for each client touch/progression trigger.
        for wallNumber = 1, areaNumber do
            if not Runtime.IsActive() or not autoGetPets then
                return false, "Pet collection was stopped"
            end
            local wall = getWall(wallNumber)
            local wallCFrame = getWorldCFrame(wall)
            if not wallCFrame then
                return false, "Could not find BlockWall" .. tostring(wallNumber)
            end
            local moved, moveError = teleportTo(wallCFrame + Vector3.new(0, 3, 0))
            if not moved then
                return false, moveError
            end
            task.wait(wallTriggerDwell)
        end
        return true
    end

    local function moveCloseToPet(model)
        local petCFrame = getWorldCFrame(model)
        if not petCFrame then
            return false, "The selected pet has no reachable world position"
        end

        -- Pickups are now proximity validated by the server. Keep the player a
        -- little above the moving pet so the character does not collide with it.
        local moved, moveError = teleportTo(petCFrame + Vector3.new(0, 3, 0))
        if not moved then
            return false, moveError
        end
        task.wait(0.18)

        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local currentPetCFrame = getWorldCFrame(model)
        if not root or not currentPetCFrame then
            return false, "The pet moved before pickup"
        end
        if (root.Position - currentPetCFrame.Position).Magnitude > 10 then
            return false, "Could not get close enough to the selected pet"
        end
        return true
    end

    local function fireRequest(commandByte, action, payload)
        RemoteEvent:FireServer({
            {
                commandByte,
                {
                    action,
                    payload,
                },
            },
        })
    end

    -- Plot actions have been observed on different command channels across
    -- accounts/server states. Dispatch both confirmed variants so switching
    -- accounts does not silently break cash collection or pet upgrades.
    local function firePlotRequest(action, slot)
        local slotId = tostring(slot)
        fireRequest("\n", action, slotId)
        fireRequest("\x05", action, slotId)
    end

    local function backpackBrainrotUids()
        local found = {}
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        for _, container in ipairs({ backpack, LocalPlayer.Character }) do
            if container then
                for _, child in ipairs(container:GetChildren()) do
                    if child:IsA("Tool")
                        and tostring(child:GetAttribute("class")):lower() == "brainrot"
                    then
                        found[tostring(child:GetAttribute("uid") or child.Name)] = true
                    end
                end
            end
        end
        return found
    end

    local function hasNewDepositedPet(before)
        local current = backpackBrainrotUids()
        for uid in pairs(current) do
            if not before[uid] then
                return true
            end
        end
        return false
    end

    local function collectPet(pet, petModel)
        if not pet or not pet.Parent then
            return false, "Pet disappeared"
        end

        local pickupUid = pet.Name
        local sourceArea = pet.Parent and pet.Parent.Name or "Unknown Area"
        local backpackBefore = backpackBrainrotUids()
        attemptedPets[pickupUid] = os.clock()

        local traversed, traverseError = traverseToPetArea(pet)
        if not traversed then
            return false, traverseError
        end

        for attempt = 1, 2 do
            local moved, moveError = moveCloseToPet(petModel)
            if not moved then
                return false, moveError
            end

            fireRequest("\r", "PickUpBrainrot", { uid = pickupUid })
            local pickupDeadline = os.clock() + 1.5
            repeat
                task.wait(0.05)
            until not pet.Parent or os.clock() >= pickupDeadline or not Runtime.IsActive()

            if not pet.Parent then
                break
            end
        end

        if pet.Parent then
            return false, "The server did not confirm the close-range pet pickup"
        end

        -- The world entry disappears before the held-pet state fully replicates.
        -- Stay at the pickup point briefly so the save-zone touch is not missed.
        task.wait(pickupHoldDelay)

        local saved, saveError = teleportTo(AUTO_SAVE_CFRAME)
        if not saved then
            attemptedPets[pickupUid] = nil
            return false, saveError
        end

        -- Remain inside the base trigger long enough for its touch/save cycle.
        task.wait(saveZoneDwell)
        if not hasNewDepositedPet(backpackBefore) then
            -- Retry the positional trigger once only; successful deposits take no extra time.
            teleportTo(AUTO_SAVE_CFRAME)
            task.wait(saveZoneDwell)
        end
        if not hasNewDepositedPet(backpackBefore) then
            attemptedPets[pickupUid] = nil
            return false, "The pet reached the save zone but no Backpack item appeared"
        end
        print("[Reverb Pets] Collected and deposited " .. pickupUid .. " from " .. sourceArea)
        return true
    end

    local function collectNextPet()
        if busy then
            return
        end
        busy = true

        local area = getSelectedAreaFolder()
        local pets = area and area:GetChildren() or {}
        local ranked = {}
        local modelLookup = buildPetModelLookup()
        for _, candidate in ipairs(pets) do
            local lastAttempt = attemptedPets[candidate.Name]
            if not lastAttempt or os.clock() - lastAttempt >= 5 then
                table.insert(ranked, petDetails(candidate, modelLookup))
            end
        end
        table.sort(ranked, function(left, right)
            if left.income == right.income then
                return left.entry.Name < right.entry.Name
            end
            return left.income > right.income
        end)
        local selectedPet = ranked[1]
        if not selectedPet then
            busy = false
            return
        end

        local succeeded, result, detail = pcall(collectPet, selectedPet.entry, selectedPet.model)
        busy = false
        if not succeeded then
            warn("[Reverb Pets] Auto Get Pets failed: " .. tostring(result))
            return false, tostring(result)
        elseif result == false then
            warn("[Reverb Pets] " .. tostring(detail))
            return
        end
        return true
    end

    local function recoverPetAutomation(reason)
        if recoveringPets then
            return
        end

        autoGetPets = false
        setToggleControl(autoPetsControl, false)
        suspendTrainingForPets()

        recoveringPets = true
        recoveringPets = false
        notify("Auto Get Pets stopped safely: " .. tostring(reason))
    end

    local function getBestDumbbell()
        local bestTool
        local best = 0
        for _, container in ipairs({ LocalPlayer.Backpack, LocalPlayer.Character }) do
            if container then
                for _, child in ipairs(container:GetChildren()) do
                    if child:IsA("Tool")
                        and tostring(child:GetAttribute("class")):lower() == "dumbbell"
                    then
                        local name = tostring(child:GetAttribute("name") or child.Name)
                        local number = tonumber(name:match("(%d+)$")) or 0
                        if number > best then
                            bestTool = child
                            best = number
                        end
                    end
                end
            end
        end
        return bestTool, best
    end

    local function trainOnce()
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local dumbbell = getBestDumbbell()
        if not humanoid or not dumbbell then
            return
        end
        if dumbbell.Parent ~= character then
            humanoid:EquipTool(dumbbell)
            task.wait(0.1)
        end
        dumbbell:Activate()
    end

    autoTrainControl = PetSection:Toggle(
        "Auto Train",
        false,
        function(enabled)
            if changingToggleInternally then
                return
            end
            if enabled == true and autoGetPets then
                resumeTrainingAfterPets = true
                autoTrain = false
                setToggleControl(autoTrainControl, false)
                notify("Auto Train will resume after Auto Get Pets is turned off.")
                return
            end
            autoTrain = enabled == true
            if not autoTrain then
                resumeTrainingAfterPets = false
                unequipTools()
            end
        end,
        "AutoTrainBestDumbbell"
    )

    PetSection:Toggle(
        "Auto Collect Cash",
        false,
        function(enabled)
            autoCollectCash = enabled == true
            if autoCollectCash then
                notify("Auto Collect Cash started for the available stands on your plot.")
            end
        end,
        "AutoCollectPlotCash"
    )

    PetSection:Toggle(
        "Auto Rebirth",
        false,
        function(enabled)
            autoRebirth = enabled == true
        end,
        "AutoRebirth"
    )

    task.spawn(function()
        while Runtime.IsActive() do
            if autoTrain then
                local succeeded, trainError = pcall(trainOnce)
                if not succeeded then
                    warn("[Reverb Training] " .. tostring(trainError))
                    task.wait(1)
                else
                    task.wait(0.12)
                end
            else
                task.wait(0.25)
            end
        end
    end)

    areaDropdown = PetSection:Dropdown(
        "Pet Area",
        getAreaOptions(),
        selectedArea,
        function(value)
            selectedArea = type(value) == "table" and value[1] or value
        end,
        "PetArea"
    )

    autoPetsControl = PetSection:Toggle(
        "Auto Get Best Pets",
        false,
        function(enabled)
            if changingToggleInternally then
                return
            end
            autoGetPets = enabled == true
            if autoGetPets then
                table.clear(attemptedPets)
                suspendTrainingForPets()
                notify("Auto Get Pets started in " .. tostring(selectedArea) .. ".")
            elseif not recoveringPets then
                restoreTrainingAfterPets()
            end
        end,
        "AutoGetPets"
    )

    PetSection:Button("Refresh Available Areas", function()
        local options = getAreaOptions()
        if areaDropdown and type(areaDropdown.Refresh) == "function" then
            areaDropdown:Refresh(options)
        end
        notify("Found " .. tostring(#options - 1) .. " pet areas.")
    end)

    task.spawn(function()
        while Runtime.IsActive() do
            if autoGetPets then
                local succeeded, failureReason = collectNextPet()
                if succeeded == false then
                    recoverPetAutomation(failureReason)
                end
                task.wait(actionDelay)
            else
                task.wait(0.25)
            end
        end
    end)

    local autoBuyDumbbell = false
    local autoBuyAura = false
    local ownedPlotCache

    local function getOwnedPlot()
        local plotName = tostring(LocalPlayer:GetAttribute("OwnTerritory") or "")
        if plotName == "" then
            return nil
        end
        if ownedPlotCache
            and ownedPlotCache.Parent
            and ownedPlotCache.Name == plotName
            and ownedPlotCache:FindFirstChild("PlotModel")
        then
            return ownedPlotCache
        end
        for _, descendant in ipairs(Workspace:GetDescendants()) do
            if descendant:IsA("Folder")
                and descendant.Name == plotName
                and descendant:FindFirstChild("PlotModel")
            then
                ownedPlotCache = descendant
                return descendant
            end
        end
        return nil
    end

    local function getPlotSlots()
        local plot = getOwnedPlot()
        local plotModel = plot and plot:FindFirstChild("PlotModel")
        local units = plotModel and plotModel:FindFirstChild("PlaceIUnitModel", true)
        local slots = {}
        local seen = {}
        if units then
            for _, place in ipairs(units:GetDescendants()) do
                local slot = tonumber(place.Name:match("^Place_(%d+)$"))
                if slot and not seen[slot] then
                    seen[slot] = true
                    table.insert(slots, slot)
                end
            end
        end
        table.sort(slots)
        return slots
    end

    local function getCurrentAuraNumber()
        local auraInfo = LocalPlayer:FindFirstChild("AuraInfo")
        local auraName = auraInfo and tostring(auraInfo.Value) or ""
        return tonumber(auraName:match("(%d+)$")) or 0
    end

    PurchaseSection:Toggle(
        "Auto Upgrade Placed Pets",
        false,
        function(enabled)
            autoUpgradePlacedPets = enabled == true
            if autoUpgradePlacedPets then
                notify("Auto Upgrade will check every available plot slot.")
            end
        end,
        "AutoUpgradePlacedPets"
    )

    PurchaseSection:Toggle(
        "Auto Buy Dumbbells",
        false,
        function(enabled)
            autoBuyDumbbell = enabled == true
        end,
        "AutoBuyNextDumbbell"
    )

    PurchaseSection:Toggle(
        "Auto Buy Auras",
        false,
        function(enabled)
            autoBuyAura = enabled == true
        end,
        "AutoBuyNextAura"
    )

    task.spawn(function()
        local lastRebirth = 0
        local lastDumbbell = 0
        local lastAura = 0
        local lastCash = 0
        local lastPetUpgrade = 0
        local lastPlotSlotRefresh = -math.huge
        local plotSlots = {}
        local cashCursor = 1
        local upgradeCursor = 1
        local cashSlotCountReported = false
        local upgradeSlotCountReported = false
        while Runtime.IsActive() do
            local now = os.clock()
            if (autoCollectCash or autoUpgradePlacedPets)
                and now - lastPlotSlotRefresh >= 5
            then
                lastPlotSlotRefresh = now
                local succeeded, slotsOrError = pcall(getPlotSlots)
                if succeeded then
                    plotSlots = slotsOrError
                else
                    warn("[Reverb Plot] Stand refresh error: " .. tostring(slotsOrError))
                end
            end
            if autoRebirth and now - lastRebirth >= 1 then
                lastRebirth = now
                fireRequest("\x10", "Rebirth")
            end
            if autoBuyDumbbell and now - lastDumbbell >= 1 then
                lastDumbbell = now
                local _, bestNumber = getBestDumbbell()
                local nextNumber = bestNumber + 1
                fireRequest("\x13", "BuyTool", "Dumbbell_" .. tostring(nextNumber))
            end
            if autoBuyAura and now - lastAura >= 1 then
                lastAura = now
                local nextAura = getCurrentAuraNumber() + 1
                if nextAura <= 10 then
                    fireRequest("\x14", "BuyAura", "aura_" .. tostring(nextAura))
                end
            end
            if autoCollectCash and not cashSlotCountReported then
                cashSlotCountReported = true
                print("[Reverb Plot] Cash collector found " .. tostring(#plotSlots) .. " stand IDs")
            end
            if autoCollectCash and #plotSlots > 0 and now - lastCash >= 0.1 then
                lastCash = now
                cashCursor = ((cashCursor - 1) % #plotSlots) + 1
                local slot = plotSlots[cashCursor]
                local succeeded, cashError = pcall(
                    firePlotRequest,
                    "GetGoldOfBrainrot",
                    slot
                )
                if not succeeded then
                    warn("[Reverb Plot] Cash collection error: " .. tostring(cashError))
                end
                cashCursor = (cashCursor % #plotSlots) + 1
            elseif not autoCollectCash then
                cashSlotCountReported = false
            end
            if autoUpgradePlacedPets and not upgradeSlotCountReported then
                upgradeSlotCountReported = true
                print("[Reverb Plot] Pet upgrader found " .. tostring(#plotSlots) .. " stand IDs")
            end
            if autoUpgradePlacedPets and #plotSlots > 0 and now - lastPetUpgrade >= 0.08 then
                lastPetUpgrade = now
                upgradeCursor = ((upgradeCursor - 1) % #plotSlots) + 1
                local slot = plotSlots[upgradeCursor]
                local succeeded, upgradeError = pcall(
                    firePlotRequest,
                    "BrainrotUpgradeLv",
                    slot
                )
                if not succeeded then
                    warn("[Reverb Plot] Pet upgrade error: " .. tostring(upgradeError))
                end
                upgradeCursor = (upgradeCursor % #plotSlots) + 1
            elseif not autoUpgradePlacedPets then
                upgradeSlotCountReported = false
            end
            task.wait(0.04)
        end
    end)

    local Settings = Window:Tab("Settings")
    Settings:Section("Script"):Button("Unload " .. SCRIPT.name, function()
        Runtime.Destroy()
    end)

    local Changelog = Window:Tab("Changelog")
    Changelog:Section("V1.0.1 - 14th September 2026"):Label(
        "Auto Get Best Pets now triggers each required area wall, uses the current pickup channel, and no longer respawns on pickup failures."
    )
    Changelog:Section("V1 - 2nd September 2026"):Label(
        "Initial release with 7 automation features."
    )

    environment.ReverbCurrentScript = {
        metadata = SCRIPT,
        library = ReverbJ,
        window = Window,
        runtime = Runtime,
    }

    print("[Reverb] " .. SCRIPT.name .. " test build is ready.")
end

local succeeded, startupError = xpcall(start, function(message)
    return debug.traceback(tostring(message), 2)
end)

if not succeeded then
    Runtime.Destroy()
    error(startupError, 0)
end
