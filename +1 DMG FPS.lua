-- +1 DMG FPS | Worlds 1 and 2 | Local development
-- Uses the game's existing crosshair targeting, firing cadence and reloads.
-- Core.CombatAssist normally restricts auto shoot to touch/controller input.

local SCRIPT_ID = "1DMGFPS"
local SUPPORTED_PLACES = {
    [100753254401525] = "+1 DMG FPS",
    [87299448877557] = "+1 DMG FPS · World 2",
}
local REVERB_J_URL =
    "https://raw.githubusercontent.com/rbxreverb/ReverbJ/refs/heads/main/source.lua?v=remember-settings-20260812"
local environment = (getgenv and getgenv()) or _G
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local player = Players.LocalPlayer
local Runtime = {}
local enabled = false
local farming = false
local autoWeapon = false
local autoEggs = false
local autoTrain = false
local trainExitPosition
local weaponBusy = false
local weaponBalance
local eggConfig
local capsuleReveal
local shopRemotes
local shopConnections = {}
local eggSnapshot
local eggRequest
local lastEggRequestId
local selectedEgg
local eggIdsByName = {}
local eggRefreshAt = 0
local UTILITY_BINDING = "Reverb1DMGFPSUtilities"
local autoRebirth = false
local rebirthRemote
local rebirthConnections = {}
local requestedRebirthCount
local rebirthCheckQueued = false
local lastFarmCallback
local lastFarmError
local lastNotificationError
local farmPhase = "idle"
local positioningTarget
local positioningOffset
local positioningCheckAt = 0
local blockageReported = false
local hoverHeight = 12
local moveSpeed = 100
local stageZones
local stageBalance
local damageMargin = 1
local lastClearedStage
local runEncounteredStages = {}
local runAliveSeen = {}
local claimPad
local claimReason
local claimMedalsBefore
local settlingClaim = false
local claimAttempt
local returningToStageOne = false
local target
local farmRoot
local returnCFrame
local scanAt = 0
local FARM_BINDING = "Reverb1DMGFPSFarm"
local destroyed = false
local combatAssist
local blasterFeature
local originalAutoShoot
local autoShootOverride
local currentStage
local collisionValues = {}
local hoverAttachment
local hoverForce
local physicsConnection
local setAutoFarm

local function notify(message, duration)
    local window = Runtime.Window
    if not window then return end
    local ok, err = pcall(function() window:Notify(message, duration) end)
    if not ok then
        lastNotificationError = tostring(err)
        warn("[Reverb/1DMGFPS] Notification: " .. tostring(err))
    end
end
local companionTransparency = {}
local companionTags = {}
local aimFilters = {}

local function restoreCompanions()
    for part, value in pairs(companionTransparency) do
        if part.Parent then part.LocalTransparencyModifier = value end
    end
    table.clear(companionTransparency)
    for folder in pairs(companionTags) do
        if folder.Parent then CollectionService:RemoveTag(folder, "RayExclude") end
    end
    table.clear(companionTags)
    for parameters, filter in pairs(aimFilters) do
        parameters.FilterDescendantsInstances = filter
    end
    table.clear(aimFilters)
end

local function excludeCompanions(controller)
    local companions = Workspace:FindFirstChild("AllyCompanions")
    if not companions then return end
    -- The game's castRays excludes instances with its existing RayExclude tag.
    if not CollectionService:HasTag(companions, "RayExclude") then
        CollectionService:AddTag(companions, "RayExclude")
        companionTags[companions] = true
    end
    local aim = controller.weaponAimController
    local parameters = aim and aim.sightRaycastParams
    if parameters then
        if not aimFilters[parameters] then
            aimFilters[parameters] = parameters.FilterDescendantsInstances
        end
        local filter = parameters.FilterDescendantsInstances
        if not table.find(filter, companions) then
            table.insert(filter, companions)
            parameters.FilterDescendantsInstances = filter
        end
    end
    for _, part in ipairs(companions:GetDescendants()) do
        if part:IsA("BasePart") then
            if companionTransparency[part] == nil then
                companionTransparency[part] = part.LocalTransparencyModifier
            end
            part.LocalTransparencyModifier = 1
        end
    end
end

local function stageNumber(id)
    return type(id) == "string" and tonumber(id:match("(%d+)$")) or nil
end

local function combatHealth(humanoid)
    local state = player:GetAttribute("CombatHealthState")
    local health = player:GetAttribute("CombatHealth")
    local maximum = player:GetAttribute("CombatMaxHealth")
    if typeof(state) == "Vector2" then health, maximum = state.X, state.Y end
    if type(health) ~= "number" then health = humanoid.Health end
    if type(maximum) ~= "number" or maximum <= 0 then maximum = humanoid.MaxHealth end
    return health, math.max(1, maximum)
end

local function isInLobby(position)
    local main = Workspace:FindFirstChild("Main")
    local lobby = main and main:FindFirstChild("Lobby")
    local floor = lobby and lobby:FindFirstChild("Floor")
    local base = floor and floor:FindFirstChild("MainBase")
    if not base or not base:IsA("BasePart") then return false end
    local point = base.CFrame:PointToObjectSpace(position)
    return math.abs(point.X) <= base.Size.X / 2
        and math.abs(point.Z) <= base.Size.Z / 2
        and point.Y >= -5 and point.Y <= base.Size.Y / 2 + 20
end

local function stageTooHard(id)
    local index = stageNumber(id)
    -- Stage 1 is the bootstrap path after rebirth, including at zero damage.
    if index == 1 then return false end
    local balance = stageBalance[id] or (index and stageBalance[string.format("Stage%02d", index)])
    local recommended = balance and balance.RecommendedDamage
    local damage = player:GetAttribute("Damage")
    return type(recommended) == "number" and type(damage) == "number"
        and damage < recommended * damageMargin
end

local function queueRebirthCheck()
    if destroyed or not autoRebirth or rebirthCheckQueued then return end
    rebirthCheckQueued = true
    task.defer(function()
        rebirthCheckQueued = false
        if destroyed or not autoRebirth then return end
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root or not isInLobby(root.Position) then return end
        local damage = player:GetAttribute("Damage")
        local requirement = player:GetAttribute("RebirthDamageRequirement")
        local count = player:GetAttribute("Rebirths")
        if type(damage) ~= "number" or type(requirement) ~= "number" or requirement <= 0
            or type(count) ~= "number" or damage < requirement or requestedRebirthCount == count then
            return
        end
        local ok, err = pcall(function() rebirthRemote:FireServer() end)
        if ok then
            requestedRebirthCount = count
        else
            warn("[Reverb/1DMGFPS] Auto Rebirth: " .. tostring(err))
        end
    end)
end

local function rebirthReady()
    local damage = player:GetAttribute("Damage")
    local requirement = player:GetAttribute("RebirthDamageRequirement")
    return autoRebirth and type(damage) == "number" and type(requirement) == "number"
        and requirement > 0 and damage >= requirement
end

local function nextWeapon()
    local progression = player:FindFirstChild("ProgressionState")
    local owned = progression and progression:FindFirstChild("OwnedGuns")
    if not owned then return nil end
    local bestPad
    local bestPrice = math.huge
    for _, pad in ipairs(CollectionService:GetTagged("GunPad")) do
        local id = pad:GetAttribute("GunId")
        local price = type(id) == "string" and weaponBalance.GetShopPrice(id)
        if pad:IsA("BasePart") and pad:IsDescendantOf(Workspace)
            and type(price) == "number" and price >= 0 and price < bestPrice
            and not owned:FindFirstChild(id) and pad:GetAttribute("PurchaseCurrency") ~= "Robux" then
            bestPad, bestPrice = pad, price
        end
    end
    return bestPad, bestPrice
end

local function bestTrainer()
    local main = Workspace:FindFirstChild("Main")
    local lobby = main and main:FindFirstChild("Lobby")
    local progression = player:FindFirstChild("ProgressionState")
    local owned = progression and progression:FindFirstChild("OwnedBooths")
    local rebirths = player:GetAttribute("Rebirths") or 0
    local bestZone
    local bestGain = -1
    for _, booth in ipairs(CollectionService:GetTagged("AFKBooth")) do
        local zone = booth:FindFirstChild("StandZone", true)
        local id = booth:GetAttribute("BoothId")
        local premium = booth:GetAttribute("IsPremium") == true or booth.Name:find("Premium") ~= nil
        local requirement = booth:GetAttribute("RequirementRebirths") or booth:GetAttribute("PriceRebirths") or 0
        local gain = booth:GetAttribute("GainMultiplier")
        local available = premium and owned and type(id) == "string" and owned:FindFirstChild(id)
            or (not premium and type(requirement) == "number" and rebirths >= requirement)
        if lobby and booth:IsDescendantOf(lobby) and zone and zone:IsA("BasePart")
            and available and type(gain) == "number" and gain > bestGain then
            bestZone, bestGain = zone, gain
        end
    end
    return bestZone
end

local function utilityGlide(root, position, deltaTime)
    local offset = position - root.Position
    if offset.Magnitude <= 0.75 then return end
    local step = moveSpeed * math.min(deltaTime, 0.05)
    local nextPosition = offset.Magnitude > step and root.Position + offset.Unit * step or position
    root.CFrame = CFrame.new(nextPosition) * root.CFrame.Rotation
    root.AssemblyLinearVelocity = Vector3.zero
end

local function utilityStep(deltaTime)
    weaponBusy = false
    if destroyed or (not autoWeapon and not autoTrain and not trainExitPosition) then return end
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then return end
    if trainExitPosition then
        utilityGlide(root, trainExitPosition, deltaTime)
        if (root.Position - trainExitPosition).Magnitude <= 0.75 then trainExitPosition = nil end
        return
    end
    if isInLobby(root.Position) and rebirthReady() then queueRebirthCheck(); return end
    if autoWeapon and isInLobby(root.Position) then
        local pad, price = nextWeapon()
        if pad and (player:GetAttribute("Medals") or 0) >= price then
            weaponBusy = true
            local height = pad.Size.Y / 2 + humanoid.HipHeight + root.Size.Y / 2
            utilityGlide(root, pad.Position + Vector3.new(0, height, 0), deltaTime)
            return
        end
    end
    if autoTrain then
        local zone = bestTrainer()
        if zone then
            -- Stand inside the normal training trigger; the native AFK controller
            -- equips/aims/fires at the dummy when the server sets AFKTraining.
            utilityGlide(root, Vector3.new(zone.Position.X,
                zone.Position.Y - zone.Size.Y / 2 + humanoid.HipHeight + root.Size.Y / 2,
                zone.Position.Z), deltaTime)
        end
    end
end

local function eggStep()
    if destroyed or not autoEggs then return end
    local now = os.clock()
    if now >= eggRefreshAt then
        eggRefreshAt = now + 5
        shopRemotes.AllyStoreRequest:FireServer()
    end
    if eggRequest then
        -- Match the native shop's five-second retry with the SAME request ID.
        if now - eggRequest.sentAt >= 5 then
            eggRequest.sentAt = now
            shopRemotes.AllyEggPurchase:FireServer(eggRequest.id, "Medals", eggRequest.requestId)
        end
        return
    end
    local snapshot = eggSnapshot
    local id = eggIdsByName[selectedEgg]
    local definition = id and eggConfig.GetDefinition(id)
    local data = snapshot and snapshot.Eggs and snapshot.Eggs[id]
    if not definition or not data or snapshot.Durable ~= true or snapshot.PendingRequestId
        or not snapshot.NextRequestId or snapshot.NextRequestId == lastEggRequestId
        or data.DisabledReason or not data.Odds or (data.Stock or 0) <= 0 or capsuleReveal.IsBusy() then return end
    local funds = player:GetAttribute("Medals") or 0
    if autoWeapon then
        local _, price = nextWeapon()
        if type(price) == "number" and price < math.huge then funds -= price end
    end
    local price = definition.CoinPrice
    if type(price) ~= "number" or funds < price then return end
    -- Native shop listeners receive the result and play the normal reveal.
    eggRequest = { id = id, requestId = snapshot.NextRequestId, sentAt = now }
    lastEggRequestId = snapshot.NextRequestId
    shopRemotes.AllyEggPurchase:FireServer(id, "Medals", eggRequest.requestId)
end

local function rememberClearedStage(id)
    if not runAliveSeen[id] then return end
    local index = stageNumber(id)
    if index and index > (stageNumber(lastClearedStage) or 0) then
        lastClearedStage = id
    end
end

local function refreshClearedStages()
    local states = player:FindFirstChild("EnemyStageState")
    for _, state in ipairs(states and states:GetChildren() or {}) do
        local total = state:GetAttribute("Total")
        if runEncounteredStages[state.Name] and type(total) == "number" and total > 0 then
            local alive = state:GetAttribute("Alive")
            if type(alive) == "number" and alive > 0 then
                runAliveSeen[state.Name] = true
            elseif alive == 0 then
                rememberClearedStage(state.Name)
            end
        end
    end
end

local function bestClaimPad()
    refreshClearedStages()
    if not lastClearedStage then return nil end
    local highest = stageNumber(lastClearedStage)
    local best
    local reward = 0
    local bestStage = -1
    for _, pad in ipairs(CollectionService:GetTagged("ClaimPad")) do
        local required = stageNumber(pad:GetAttribute("RequiredStageId"))
        local amount = pad:GetAttribute("MedalAmount")
        local pass = pad:GetAttribute("GamePassId")
        if pad:IsA("BasePart") and pad:IsDescendantOf(Workspace)
            and required and highest and required <= highest
            and type(amount) == "number" and amount > 0
            and (type(pass) ~= "number" or pass <= 0) then
            if required > bestStage or (required == bestStage and amount > reward) then
                best = pad
                bestStage = required
                reward = amount
            end
        end
    end
    return best
end

local function releaseHover()
    if physicsConnection then physicsConnection:Disconnect(); physicsConnection = nil end
    if hoverForce then hoverForce:Destroy(); hoverForce = nil end
    if hoverAttachment then hoverAttachment:Destroy(); hoverAttachment = nil end
    for part, value in pairs(collisionValues) do
        if part.Parent then part.CanCollide = value end
    end
    table.clear(collisionValues)
end

local function holdCharacter(root)
    releaseHover()
    hoverAttachment = Instance.new("Attachment")
    hoverAttachment.Parent = root
    hoverForce = Instance.new("VectorForce")
    hoverForce.Attachment0 = hoverAttachment
    hoverForce.RelativeTo = Enum.ActuatorRelativeTo.World
    hoverForce.ApplyAtCenterOfMass = true
    hoverForce.Parent = root
    physicsConnection = RunService.PreSimulation:Connect(function()
        if not root.Parent then releaseHover(); return end
        for _, part in ipairs(root.Parent:GetDescendants()) do
            if part:IsA("BasePart") then
                if collisionValues[part] == nil then collisionValues[part] = part.CanCollide end
                part.CanCollide = false
            end
        end
        hoverForce.Force = Vector3.new(0, root.AssemblyMass * Workspace.Gravity, 0)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
end

local function stageConfirmedCleared(id)
    local states = player:FindFirstChild("EnemyStageState")
    local state = states and states:FindFirstChild(id)
    local total = state and state:GetAttribute("Total")
    return runAliveSeen[id] == true and type(total) == "number" and total > 0
        and state:GetAttribute("Alive") == 0
end

local function canTargetStage(id)
    local current = stageNumber(currentStage)
    local candidate = stageNumber(id)
    if not current then return candidate == 1 end
    return candidate == current
        or (candidate == current + 1 and stageConfirmedCleared(currentStage))
end

local function nextStagePosition()
    if not currentStage then return nil end
    if not stageConfirmedCleared(currentStage) then return nil end
    rememberClearedStage(currentStage)
    local index = tonumber(currentStage:match("(%d+)$"))
    if not index then return nil end
    for _, zone in ipairs(CollectionService:GetTagged("StageZone")) do
        local id = zone:GetAttribute("StageId")
        if zone:IsA("BasePart") and zone:IsDescendantOf(Workspace) and type(id) == "string"
            and tonumber(id:match("(%d+)$")) == index + 1 then
            if stageTooHard(id) then
                claimPad = bestClaimPad()
                claimReason = "Next stage needs more damage"
                return claimPad and claimPad.Position + Vector3.new(0, claimPad.Size.Y / 2 + 4, 0)
            end
            local desired = Vector3.new(zone.Position.X, farmRoot.Position.Y, zone.Position.Z)
            -- The previous stage is confirmed clear. Track the stage being
            -- approached so unloaded enemies are searched for within that stage.
            currentStage = id
            return stageZones.Clamp(id, desired, desired, 1.5)
        end
    end
end

local function currentStageSearchPosition(root)
    if not currentStage then return nil end
    local index = stageNumber(currentStage)
    local zone
    local nextZone
    local previousZone
    local nearest = math.huge
    for _, candidate in ipairs(CollectionService:GetTagged("StageZone")) do
        if candidate:IsA("BasePart") and candidate:IsDescendantOf(Workspace) then
            local id = candidate:GetAttribute("StageId")
            if id == currentStage then
                local distance = (candidate.Position - root.Position).Magnitude
                if distance < nearest then zone, nearest = candidate, distance end
            elseif index and stageNumber(id) == index + 1 then nextZone = candidate
            elseif index and stageNumber(id) == index - 1 then previousZone = candidate end
        end
    end
    if not zone then return nil end
    local direction = nextZone and (nextZone.Position - zone.Position)
        or (previousZone and (zone.Position - previousZone.Position)) or zone.CFrame.LookVector
    direction = Vector3.new(direction.X, 0, direction.Z)
    if direction.Magnitude < 0.01 then return stageZones.Clamp(currentStage, zone.Position, zone.Position, 1.5) end
    direction = zone.CFrame:VectorToObjectSpace(direction.Unit)
    local half = zone.Size * 0.5
    local distance = math.huge
    if math.abs(direction.X) > 0.001 then distance = math.min(distance, math.max(0, half.X - 4) / math.abs(direction.X)) end
    if math.abs(direction.Z) > 0.001 then distance = math.min(distance, math.max(0, half.Z - 4) / math.abs(direction.Z)) end
    local position = zone.CFrame:PointToWorldSpace(direction * distance)
    position = Vector3.new(position.X, root.Position.Y, position.Z)
    -- Approach the far end of THIS stage, never through its next locked gate.
    return stageZones.Clamp(currentStage, position, zone.Position, 1.5)
end

local function restorePosition()
    restoreCompanions()
    releaseHover()
    if farmRoot and farmRoot.Parent and player.Character
        and farmRoot.Parent == player.Character and returnCFrame then
        farmRoot.AssemblyLinearVelocity = Vector3.zero
        farmRoot.AssemblyAngularVelocity = Vector3.zero
    end
    farmRoot = nil
    returnCFrame = nil
end

local function validEnemy(model)
    local folder = Workspace:FindFirstChild("PrivateEnemies")
    if not model or not folder or model.Parent ~= folder
        or typeof(model:GetAttribute("PrivateEnemyId")) ~= "string" then
        return nil
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
    if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
        return root
    end
end

local FARM_OFFSETS = {
    Vector3.new(0, 0, 8), Vector3.new(8, 0, 0),
    Vector3.new(0, 0, -8), Vector3.new(-8, 0, 0),
}

local function chooseFarmPosition(model, enemyRoot, aimPosition, root)
    if positioningTarget ~= model then
        positioningTarget = model
        positioningOffset = FARM_OFFSETS[1]
        positioningCheckAt = 0
        blockageReported = false
    end
    local function positionFor(offset)
        local desired = enemyRoot.Position + Vector3.new(0, hoverHeight, 0) + offset
        return stageZones.Clamp(model:GetAttribute("StageId"), desired, enemyRoot.Position, 1.5)
    end
    local position = positionFor(positioningOffset)
    if os.clock() < positioningCheckAt then return position end
    positioningCheckAt = os.clock() + 0.25
    local parameters = RaycastParams.new()
    parameters.FilterType = Enum.RaycastFilterType.Exclude
    parameters.IgnoreWater = true
    local filter = CollectionService:GetTagged("RayExclude")
    table.insert(filter, model)
    if player.Character then table.insert(filter, player.Character) end
    if Workspace.CurrentCamera then table.insert(filter, Workspace.CurrentCamera) end
    parameters.FilterDescendantsInstances = filter
    local function clearShot(candidate)
        -- Check both the character-height path and camera-height path. Casting
        -- from the target also detects a candidate inside a wall or crate.
        for _, origin in ipairs({ candidate, candidate + Vector3.new(0, 1.5, 0) }) do
            if Workspace:Raycast(aimPosition, origin - aimPosition, parameters)
                or Workspace:Raycast(origin, aimPosition - origin, parameters) then
                return false
            end
        end
        return true
    end
    if clearShot(position) then
        blockageReported = false
        return position
    end
    local bestOffset
    local bestPosition
    local nearest = math.huge
    for _, offset in ipairs(FARM_OFFSETS) do
        local candidate = positionFor(offset)
        if clearShot(candidate) then
            local distance = (candidate - root.Position).Magnitude
            if distance < nearest then
                nearest = distance
                bestOffset = offset
                bestPosition = candidate
            end
        end
    end
    if bestPosition then
        positioningOffset = bestOffset
        blockageReported = false
        return bestPosition
    end
    if not blockageReported then
        blockageReported = true
        notify("Target is blocked from all four nearby positions.", 4)
    end
    return position
end

local function farmStep(deltaTime)
    if not farming or destroyed then return end
    if weaponBusy then return end
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local inLobby = root and isInLobby(root.Position)
    local controller = blasterFeature.getActiveController()
    local health, maxHealth
    if humanoid then health, maxHealth = combatHealth(humanoid) end
    if not root or not humanoid or humanoid.Health <= 0
        or (health <= 0 and not inLobby and player:GetAttribute("InFPSMode") == true) then
        target = nil
        currentStage = nil
        lastClearedStage = nil
        table.clear(runEncounteredStages)
        table.clear(runAliveSeen)
        claimPad = nil
        claimMedalsBefore = nil
        returningToStageOne = true
        restorePosition()
        return
    end
    -- Physical lobby position takes priority over claim and camera state.
    if inLobby then
        queueRebirthCheck()
        local damage = player:GetAttribute("Damage")
        local requirement = player:GetAttribute("RebirthDamageRequirement")
        if autoRebirth and type(damage) == "number" and type(requirement) == "number"
            and requirement > 0 and damage >= requirement then
            restorePosition()
            return
        end
        if not returningToStageOne or settlingClaim then
            restorePosition()
            target = nil
            currentStage = nil
            lastClearedStage = nil
            table.clear(runEncounteredStages)
            table.clear(runAliveSeen)
            claimPad = nil
            claimReason = nil
            claimMedalsBefore = nil
            scanAt = 0
        end
        settlingClaim = false
        claimAttempt = nil
        returningToStageOne = true
    end
    if settlingClaim then return end
    if returningToStageOne then
        for _, zone in ipairs(CollectionService:GetTagged("StageZone")) do
            local id = zone:GetAttribute("StageId")
            if zone:IsA("BasePart") and zone:IsDescendantOf(Workspace) and stageNumber(id) == 1 then
                if not inLobby and stageZones.Contains(id, root.Position)
                    and player:GetAttribute("InFPSMode") == true and controller then
                    returningToStageOne = false
                    break
                end
                if farmRoot ~= root then
                    farmRoot = root
                    returnCFrame = root.CFrame
                    holdCharacter(root)
                end
                local destination = stageZones.Clamp(id,
                    Vector3.new(zone.Position.X, root.Position.Y, zone.Position.Z), zone.Position, 1.5)
                local offset = destination - root.Position
                local step = moveSpeed * math.min(deltaTime, 0.05)
                local position = offset.Magnitude > step and root.Position + offset.Unit * step or destination
                local facing = Vector3.new(destination.X, position.Y, destination.Z)
                if (facing - position).Magnitude < 0.01 then facing = position + root.CFrame.LookVector end
                root.CFrame = CFrame.lookAt(position, facing)
                root.AssemblyLinearVelocity = Vector3.zero
                return
            end
        end
        if returningToStageOne then return end
    end
    if health / maxHealth <= 0.25 and not claimPad then
        claimPad = bestClaimPad()
        claimReason = "Low health"
    end
    if player:GetAttribute("InFPSMode") ~= true or not controller then
        if claimPad and player:GetAttribute("InFPSMode") ~= true then
            -- The pad may return the player before our landing check runs.
            -- Keep the farm armed rather than waiting for a late trophy delta.
            returningToStageOne = true
            target = nil
            currentStage = nil
            lastClearedStage = nil
            table.clear(runEncounteredStages)
            table.clear(runAliveSeen)
            claimPad = nil
            claimReason = nil
            claimMedalsBefore = nil
            scanAt = 0
        end
        target = nil
        restorePosition()
        return
    end
    excludeCompanions(controller)
    refreshClearedStages()
    local states = player:FindFirstChild("EnemyStageState")
    local currentState = currentStage and states and states:FindFirstChild(currentStage)
    if currentState and stageConfirmedCleared(currentStage) then
        rememberClearedStage(currentStage)
        local damage = player:GetAttribute("Damage")
        local requirement = player:GetAttribute("RebirthDamageRequirement")
        if autoRebirth and not claimPad and type(damage) == "number"
            and type(requirement) == "number" and requirement > 0 and damage >= requirement then
            claimPad = bestClaimPad()
            claimReason = "Rebirth ready"
        end
    end
    -- Allow enabling the farm in an already-cleared stage with no enemy models.
    if not currentStage then
        for _, zone in ipairs(CollectionService:GetTagged("StageZone")) do
            local id = zone:GetAttribute("StageId")
            if zone:IsA("BasePart") and zone:IsDescendantOf(Workspace)
                and type(id) == "string" and stageZones.Contains(id, root.Position) then
                currentStage = id
                break
            end
        end
    end
    local enemyRoot = validEnemy(target)
    if enemyRoot and not canTargetStage(target:GetAttribute("StageId")) then
        target = nil
        enemyRoot = nil
    end
    if not enemyRoot and os.clock() >= scanAt then
        scanAt = os.clock() + 0.25
        target = nil
        local folder = Workspace:FindFirstChild("PrivateEnemies")
        local nearest = math.huge
        local targetPriority = math.huge
        for _, model in ipairs(folder and folder:GetChildren() or {}) do
            local candidate = validEnemy(model)
            if candidate and canTargetStage(model:GetAttribute("StageId")) then
                local priority = model:GetAttribute("StageId") == currentStage and 0 or 1
                local distance = (candidate.Position - root.Position).Magnitude
                if priority < targetPriority or (priority == targetPriority and distance < nearest) then
                    targetPriority = priority
                    nearest = distance
                    target = model
                    enemyRoot = candidate
                end
            end
        end
    end
    local destination
    local aimPosition
    -- Apply the same cutoff when the next stage's models are already loaded.
    if enemyRoot and stageTooHard(target:GetAttribute("StageId")) and not claimPad then
        claimPad = bestClaimPad()
        claimReason = "Stage needs more damage"
        if not claimPad then
            farming = false
            RunService:UnbindFromRenderStep(FARM_BINDING)
            restorePosition()
            controller:updateAutoFire()
            notify("Stage exceeds your damage threshold; no cleared trophy pad is available.", 5)
            return
        end
    end
    if claimPad and claimPad.Parent then
        destination = claimPad.Position + Vector3.new(0, claimPad.Size.Y / 2 + 4, 0)
    elseif enemyRoot then
        currentStage = target:GetAttribute("StageId")
        runEncounteredStages[currentStage] = true
        refreshClearedStages()
        -- Torso targeting avoids the steep head/mask angle seen in stalled
        -- overhead aim locks. The character must stay inside the combat zone.
        local aimPart = target:FindFirstChild("UpperTorso") or target:FindFirstChild("Torso") or enemyRoot
        aimPosition = aimPart.Position
        destination = chooseFarmPosition(target, enemyRoot, aimPosition, root)
    elseif currentStage then
        if farmRoot ~= root then
            farmRoot = root
            returnCFrame = root.CFrame
            holdCharacter(root)
        end
        if stageConfirmedCleared(currentStage) then
            destination = nextStagePosition()
        else
            destination = currentStageSearchPosition(root)
        end
    end
    if not destination then return end
    if claimPad and claimMedalsBefore == nil then
        claimMedalsBefore = player:GetAttribute("Medals") or 0
    end
    if farmRoot ~= root then
        farmRoot = root
        returnCFrame = root.CFrame
        holdCharacter(root)
    end
    local position = destination
    -- Fast continuous glide for enemies, stage approaches and trophy pads.
    -- Follow moving targets without repeatedly cancelling TweenService tweens.
    local offset = position - root.Position
    local step = moveSpeed * math.min(deltaTime, 0.05)
    if offset.Magnitude > step then
        position = root.Position + offset.Unit * step
    end
    local facingPoint = aimPosition or destination
    local facing = Vector3.new(facingPoint.X, position.Y, facingPoint.Z)
    if (facing - position).Magnitude < 0.01 then facing = position + root.CFrame.LookVector end
    root.CFrame = CFrame.lookAt(position, facing)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    if claimPad and (root.Position - destination).Magnitude <= 1 then
        -- Release hover/noclip and land naturally on the pad's touch surface.
        -- Do not fake touch events or claim success before the server responds.
        settlingClaim = true
        local attempt = {}
        claimAttempt = attempt
        farmPhase = "claim_stop_fire"
        controller:setAutoFiring(false)
        local medalsBefore = claimMedalsBefore or (player:GetAttribute("Medals") or 0)
        farmPhase = "claim_cleanup"
        restorePosition()
        farmPhase = "claim_notification"
        notify((claimReason or "Run complete") .. ". Claiming trophies...", 4)
        farmPhase = "claim_wait"
        task.delay(4, function()
            if destroyed or not farming or not settlingClaim or claimAttempt ~= attempt then return end
            settlingClaim = false
            claimAttempt = nil
            local medalsAfter = player:GetAttribute("Medals") or 0
            local claimed = medalsAfter > medalsBefore
            local returnedToLobby = player:GetAttribute("InFPSMode") ~= true
            if not claimed and not returnedToLobby then
                return
            end
            target = nil
            currentStage = nil
            lastClearedStage = nil
            table.clear(runEncounteredStages)
            table.clear(runAliveSeen)
            claimPad = nil
            claimReason = nil
            claimMedalsBefore = nil
            scanAt = 0
            returningToStageOne = claimed or returnedToLobby
            local active = blasterFeature.getActiveController()
            if active then active:updateAutoFire() end
            notify(claimed
                and "Trophies claimed. Moving back into stage 1."
                or (returnedToLobby and "Back in the lobby. Starting the next run."
                    or "Claim not confirmed. Step onto the trophy pad manually."), 5)
        end)
    end
    local camera = Workspace.CurrentCamera
    if camera and aimPosition then
        camera.CFrame = CFrame.lookAt(camera.CFrame.Position, aimPosition)
    end
end

function Runtime.GetFarmDiagnostic()
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local health, maximum
    if humanoid then health, maximum = combatHealth(humanoid) end
    local controller = blasterFeature and blasterFeature.getActiveController()
    local stageOneCount = 0
    for _, zone in ipairs(CollectionService:GetTagged("StageZone")) do
        if stageNumber(zone:GetAttribute("StageId")) == 1 then stageOneCount += 1 end
    end
    return {
        farming = farming,
        destroyed = destroyed,
        callbackAgeSeconds = lastFarmCallback and (os.clock() - lastFarmCallback) or -1,
        lastError = lastFarmError or "none",
        farmPhase = farmPhase,
        lastNotificationError = lastNotificationError or "none",
        settlingClaim = settlingClaim,
        hasClaimAttempt = claimAttempt ~= nil,
        returningToStageOne = returningToStageOne,
        fpsMode = player:GetAttribute("InFPSMode") == true,
        inLobby = root and isInLobby(root.Position) or false,
        rootPosition = root and tostring(root.Position) or "missing",
        rootAnchored = root and root.Anchored or false,
        humanoidHealth = humanoid and humanoid.Health or -1,
        combatHealth = health or -1,
        combatMaxHealth = maximum or -1,
        hasActiveController = controller ~= nil,
        stageOneZones = stageOneCount,
        currentStage = currentStage or "none",
        currentStageConfirmedCleared = currentStage and stageConfirmedCleared(currentStage) or false,
        lastClearedStage = lastClearedStage or "none",
        claimPad = claimPad and claimPad:GetFullName() or "none",
        claimReason = claimReason or "none",
        trophies = player:GetAttribute("Medals") or -1,
        damage = player:GetAttribute("Damage") or -1,
        autoRebirth = autoRebirth,
        requestedRebirthCount = requestedRebirthCount or -1,
        target = target and target:GetFullName() or "none",
    }
end

setAutoFarm = function(value)
    if destroyed then return end
    farming = value == true
    if farming and autoTrain then
        autoTrain = false
        trainExitPosition = nil
        if Runtime.AutoTrainToggle then Runtime.AutoTrainToggle:Set(false, true) end
    end
    positioningTarget = nil
    positioningOffset = nil
    positioningCheckAt = 0
    blockageReported = false
    returningToStageOne = farming and player:GetAttribute("InFPSMode") ~= true
    target = nil
    currentStage = nil
    lastClearedStage = nil
    table.clear(runEncounteredStages)
    table.clear(runAliveSeen)
    claimPad = nil
    claimReason = nil
    claimMedalsBefore = nil
    settlingClaim = false
    claimAttempt = nil
    scanAt = 0
    RunService:UnbindFromRenderStep(FARM_BINDING)
    if farming then
        RunService:BindToRenderStep(FARM_BINDING, Enum.RenderPriority.Camera.Value + 2, function(deltaTime)
            lastFarmCallback = os.clock()
            local ok, err = xpcall(function() farmStep(deltaTime) end, debug.traceback)
            if not ok then
                lastFarmError = tostring(err)
                farming = false
                RunService:UnbindFromRenderStep(FARM_BINDING)
                restorePosition()
                warn("[Reverb/1DMGFPS] Auto Farm: " .. tostring(err))
                if Runtime.Window then notify("Auto Farm stopped. Check the console.", 4) end
            end
        end)
    else
        restorePosition()
    end
    local controller = blasterFeature.getActiveController()
    if controller then controller:updateAutoFire() end
end

local function setAutoShoot(value)
    if destroyed then
        return
    end
    enabled = value == true
    local controller = blasterFeature.getActiveController()
    if controller then
        controller:updateAutoFire()
    end
end

function Runtime.Destroy()
    if destroyed then
        return
    end
    enabled = false
    autoRebirth = false
    autoWeapon = false
    autoEggs = false
    autoTrain = false
    RunService:UnbindFromRenderStep(UTILITY_BINDING)
    for _, connection in ipairs(shopConnections) do connection:Disconnect() end
    table.clear(shopConnections)
    for _, connection in ipairs(rebirthConnections) do connection:Disconnect() end
    table.clear(rebirthConnections)
    farming = false
    returningToStageOne = false
    settlingClaim = false
    RunService:UnbindFromRenderStep(FARM_BINDING)
    restorePosition()
    if combatAssist and combatAssist.isAutoShootEnabled == autoShootOverride then
        combatAssist.isAutoShootEnabled = originalAutoShoot
    end
    if blasterFeature then
        pcall(function()
            local controller = blasterFeature.getActiveController()
            if controller then controller:updateAutoFire() end
        end)
    end
    destroyed = true
    if environment.ReverbScriptInstances[SCRIPT_ID] == Runtime then
        environment.ReverbScriptInstances[SCRIPT_ID] = nil
        environment.ReverbLoadedScripts[SCRIPT_ID] = nil
    end
    if environment.ReverbCurrentScript
        and environment.ReverbCurrentScript.runtime == Runtime then
        environment.ReverbCurrentScript = nil
    end
    if Runtime.Window then
        local window = Runtime.Window
        Runtime.Window = nil
        pcall(function() window:Destroy() end)
    end
end

local function start()
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end
    assert(SUPPORTED_PLACES[game.PlaceId], "Run this script in +1 DMG FPS World 1 or World 2.")
    environment.ReverbScriptInstances = environment.ReverbScriptInstances or {}
    environment.ReverbLoadedScripts = environment.ReverbLoadedScripts or {}
    local previous = environment.ReverbScriptInstances[SCRIPT_ID]
    if previous and type(previous.Destroy) == "function" then
        previous.Destroy()
    end
    environment.ReverbScriptInstances[SCRIPT_ID] = Runtime
    environment.ReverbLoadedScripts[SCRIPT_ID] = Runtime

    local playerScripts = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts")
    local core = playerScripts:FindFirstChild("Core")
    local features = playerScripts:FindFirstChild("Features")
    local combatModule = core and core:FindFirstChild("CombatAssist")
    local blasterModule = features and features:FindFirstChild("Blaster")
    assert(combatModule and blasterModule, "Game controllers not found. Join fully and try again.")
    combatAssist = require(combatModule)
    blasterFeature = require(blasterModule)
    local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
    local zoneModule = shared and shared:FindFirstChild("StageZoneIndex")
    assert(zoneModule, "StageZoneIndex not found.")
    stageZones = require(zoneModule)
    stageBalance = require(shared:WaitForChild("Config"):WaitForChild("StageBalance"))
    weaponBalance = require(shared.Config:WaitForChild("WeaponBalance"))
    eggConfig = require(shared.Config:WaitForChild("EggConfig"))
    capsuleReveal = require(features:WaitForChild("Menu"):WaitForChild("CapsuleReveal"))
    assert(type(stageZones.AllowsCombat) == "function" and type(stageZones.Clamp) == "function",
        "Stage zones no longer match the saved source.")
    assert(type(combatAssist.isAutoShootEnabled) == "function"
        and type(blasterFeature.getActiveController) == "function",
        "Game controllers no longer match the saved source.")
    originalAutoShoot = combatAssist.isAutoShootEnabled
    autoShootOverride = function() return (enabled or farming) and not destroyed and not settlingClaim end
    combatAssist.isAutoShootEnabled = autoShootOverride
    setAutoShoot(false)
    local network = game:GetService("ReplicatedStorage"):FindFirstChild("Network")
    local remotes = network and network:FindFirstChild("Remotes")
    shopRemotes = {
        AllyStoreRequest = remotes and remotes:FindFirstChild("AllyStoreRequest"),
        AllyEggPurchase = remotes and remotes:FindFirstChild("AllyEggPurchase"),
    }
    assert(shopRemotes.AllyStoreRequest and shopRemotes.AllyEggPurchase, "Egg shop requests not found.")
    table.insert(shopConnections, remotes:WaitForChild("AllyStoreSnapshot").OnClientEvent:Connect(function(snapshot)
        if type(snapshot) == "table" then eggSnapshot = snapshot end
    end))
    table.insert(shopConnections, remotes:WaitForChild("AllyEggResult").OnClientEvent:Connect(function(result)
        if type(result) == "table" and eggRequest and result.RequestId == eggRequest.requestId then
            -- A retryable save result retains the same transaction, as the game does.
            local retryable = not result.Success
                and (result.Reason == "SavePending" or result.Reason == "PurchasePending")
            if not retryable then eggRequest = nil end
        end
    end))
    RunService:BindToRenderStep(UTILITY_BINDING, Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
        local ok, err = xpcall(function() utilityStep(deltaTime) end, debug.traceback)
        if not ok then
            autoWeapon, autoTrain, weaponBusy = false, false, false
            warn("[Reverb/1DMGFPS] Utilities: " .. tostring(err))
        end
    end)
    task.spawn(function()
        while not destroyed do
            local ok, err = pcall(eggStep)
            if not ok then autoEggs = false; warn("[Reverb/1DMGFPS] Auto Open Eggs: " .. tostring(err)) end
            task.wait(1)
        end
    end)
    rebirthRemote = remotes and remotes:FindFirstChild("RebirthRequest")
    assert(rebirthRemote, "RebirthRequest not found.")
    for _, attribute in ipairs({ "Damage", "RebirthDamageRequirement", "InFPSMode" }) do
        table.insert(rebirthConnections, player:GetAttributeChangedSignal(attribute):Connect(queueRebirthCheck))
    end
    table.insert(rebirthConnections, player:GetAttributeChangedSignal("Rebirths"):Connect(function()
        if destroyed then return end
        if farming then
            restorePosition()
            setAutoFarm(true)
            returningToStageOne = true
        end
        queueRebirthCheck()
    end))

    local loadUi, compileError = loadstring(game:HttpGet(REVERB_J_URL))
    assert(loadUi, compileError)
    local library = loadUi()
    local access = environment.ReverbAccess or {}
    local tier = access.tier or environment.ReverbKeyTier or "free"
    local window = library:CreateWindow({
        Game = SUPPORTED_PLACES[game.PlaceId],
        Tier = tier == "premium" and "PREMIUM" or "FREE",
        ConfigName = SCRIPT_ID,
        RememberSettings = false,
    })
    Runtime.Window = window
    local weaponSection = window:Tab("Main"):Section("Main")
    local farmSection = weaponSection
    Runtime.AutoFarmToggle = farmSection:Toggle("Autofarm", false, function(value)
        local ok, err = pcall(setAutoFarm, value)
        if not ok then
            pcall(setAutoFarm, false)
            warn("[Reverb/1DMGFPS] Auto Farm: " .. tostring(err))
            window:Notify("Could not change Auto Farm. Check the console.", 4)
        end
    end)
    weaponSection:Toggle("Auto Rebirth", false, function(value)
        autoRebirth = value == true
        requestedRebirthCount = nil
        queueRebirthCheck()
    end)
    weaponSection:Toggle("Auto Get Next Weapon", false, function(value)
        autoWeapon = value == true
    end)
    Runtime.AutoTrainToggle = weaponSection:Toggle("Auto Train", false, function(value)
        autoTrain = value == true
        if autoTrain then
            trainExitPosition = nil
            if farming then setAutoFarm(false); Runtime.AutoFarmToggle:Set(false, true) end
        elseif player:GetAttribute("AFKTraining") == true then
            local zone = bestTrainer()
            local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if zone and root then
                local outside = zone.CFrame:PointToWorldSpace(Vector3.new(0, 0, zone.Size.Z / 2 + 4))
                trainExitPosition = Vector3.new(outside.X, root.Position.Y, outside.Z)
            end
        end
    end)
    local eggOptions = {}
    local definitions = {}
    for _, definition in pairs(eggConfig.GetAllDefinitions()) do table.insert(definitions, definition) end
    table.sort(definitions, function(a, b) return (a.LayoutOrder or 999) < (b.LayoutOrder or 999) end)
    for _, definition in ipairs(definitions) do
        if not definition.Hidden and type(definition.CoinPrice) == "number" then
            local name = definition.DisplayName or definition.Id
            table.insert(eggOptions, name)
            eggIdsByName[name] = definition.Id
        end
    end
    selectedEgg = eggOptions[1]
    weaponSection:Dropdown("Egg", eggOptions, selectedEgg, function(value) selectedEgg = value end)
    weaponSection:Toggle("Auto Open Eggs", false, function(value)
        autoEggs = value == true
        if autoEggs then eggRefreshAt = 0 end
    end)
    local settingsTab = window:Tab("Settings")
    settingsTab:Section("Preferences"):Toggle("Remember active settings", false, function(value)
        window:SetRememberSettings(value)
        window:Notify(value and "Settings will now be remembered." or "Settings will no longer be saved.", 3)
    end)
    settingsTab:Section("Script"):Button("Unload Script", Runtime.Destroy)
    local changelogTab = window:Tab("Changelog")
    changelogTab:Section("V1 · 10th October 2026"):Label("Script Release")
    environment.ReverbCurrentScript = { id = SCRIPT_ID, runtime = Runtime }
end

local ok, err = pcall(start)
if not ok then
    -- Startup may fail before the runtime tables exist.
    if environment.ReverbScriptInstances then
        Runtime.Destroy()
    end
    error(err)
end




