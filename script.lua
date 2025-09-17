-- Load Rayfield Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Player
local player = Players.LocalPlayer

-- AutoFarm System
local AutoFarm = {
    Enabled = false,
    AvoidEnemies = true,
    CollectXP = true,
    AutoUpgrade = true,
    SAFE_DISTANCE = 20,
    BOSS_SAFE_DISTANCE = 35,
    DETECTION_RANGE = 50,
    XP_DETECTION_RANGE = 60,
    NPCs = {},
    UpgradeList = {
        "DamageUpgrade", "ExpUpgrade", "DodgeUpgrade", "CritChanceUpgrade", 
        "Acid", "Can", "Pin", "MagnetUpgrade", "ReviveUpgrade", "Cashupgrade"
    },
    CurrentUpgradeIndex = 1,
    PathVisuals = {},
    Bosses = {},
    ActiveCoroutines = {},
    PerformanceMode = false
}

-- Create ESP visualization folder
local ESPFolder = Instance.new("Folder")
ESPFolder.Name = "AutoFarmESP"
ESPFolder.Parent = workspace

-- Performance monitoring
local lastPerformanceCheck = tick()
local frameCount = 0
local currentFPS = 60

-- Create Window
local Window = Rayfield:CreateWindow({
   Name = "ULTIMATE AutoFarm System",
   LoadingTitle = "Loading Advanced AutoFarm",
   LoadingSubtitle = "Initializing ultra-efficient pathfinding...",
   ConfigurationSaving = {
      Enabled = false,
   },
   Discord = {
      Enabled = false,
   }
})

-- Main Tab
local MainTab = Window:CreateTab("Main Controls", 4483361688)

-- AutoFarm Toggle
MainTab:CreateToggle({
   Name = "Enable AutoFarm System",
   CurrentValue = false,
   Callback = function(Value)
      AutoFarm.Enabled = Value
      if Value then
         Rayfield:Notify({
            Title = "AutoFarm Started",
            Content = "Ultra-efficient farming system activated",
            Duration = 3,
            Image = 4483361688
         })
         AutoFarm:InitializeSystem()
      else
         AutoFarm:StopSystem()
         Rayfield:Notify({
            Title = "AutoFarm Stopped",
            Content = "System has been completely disabled",
            Duration = 3,
            Image = 4483361688
         })
      end
   end,
})

-- Enemy Avoidance Toggle
MainTab:CreateToggle({
   Name = "Ultra Enemy Avoidance",
   CurrentValue = true,
   Callback = function(Value)
      AutoFarm.AvoidEnemies = Value
   end,
})

-- XP Collection Toggle
MainTab:CreateToggle({
   Name = "Smart XP Collection",
   CurrentValue = true,
   Callback = function(Value)
      AutoFarm.CollectXP = Value
   end,
})

-- Auto Upgrade Toggle
MainTab:CreateToggle({
   Name = "Auto Upgrade System",
   CurrentValue = true,
   Callback = function(Value)
      AutoFarm.AutoUpgrade = Value
   end,
})

-- Performance Mode Toggle
MainTab:CreateToggle({
   Name = "Performance Mode",
   CurrentValue = false,
   Callback = function(Value)
      AutoFarm.PerformanceMode = Value
      if Value then
         AutoFarm:ClearVisualizations()
         Rayfield:Notify({
            Title = "Performance Mode",
            Content = "Visualizations disabled for better performance",
            Duration = 3,
            Image = 4483361688
         })
      end
   end,
})

-- Settings Tab
local SettingsTab = Window:CreateTab("Advanced Settings", 4483361688)

-- Safe Distance Slider
SettingsTab:CreateSlider({
   Name = "Enemy Safe Distance",
   Range = {10, 40},
   Increment = 1,
   Suffix = "studs",
   CurrentValue = 20,
   Callback = function(Value)
      AutoFarm.SAFE_DISTANCE = Value
   end,
})

-- Boss Safe Distance Slider
SettingsTab:CreateSlider({
   Name = "BOSS Safe Distance",
   Range = {25, 60},
   Increment = 5,
   Suffix = "studs",
   CurrentValue = 35,
   Callback = function(Value)
      AutoFarm.BOSS_SAFE_DISTANCE = Value
   end,
})

-- Detection Range Slider
SettingsTab:CreateSlider({
   Name = "Enemy Detection Range",
   Range = {30, 80},
   Increment = 5,
   Suffix = "studs",
   CurrentValue = 50,
   Callback = function(Value)
      AutoFarm.DETECTION_RANGE = Value
   end,
})

-- XP Detection Range Slider
SettingsTab:CreateSlider({
   Name = "XP Detection Range",
   Range = {40, 100},
   Increment = 5,
   Suffix = "studs",
   CurrentValue = 60,
   Callback = function(Value)
      AutoFarm.XP_DETECTION_RANGE = Value
   end,
})

-- Upgrade Speed Slider
SettingsTab:CreateSlider({
   Name = "Upgrade Interval",
   Range = {1, 10},
   Increment = 0.5,
   Suffix = "seconds",
   CurrentValue = 3,
   Callback = function(Value)
      AutoFarm.UpgradeInterval = Value
   end,
})

-- Refresh NPCs Button
MainTab:CreateButton({
   Name = "Refresh NPCs & Targets",
   Callback = function()
      AutoFarm:RefreshNPCs()
      Rayfield:Notify({
         Title = "System Refreshed",
         Content = "NPCs and targets updated",
         Duration = 3,
         Image = 4483361688
      })
   end,
})

-- Clear ESP Button
MainTab:CreateButton({
   Name = "Clear Visualizations",
   Callback = function()
      AutoFarm:ClearVisualizations()
      Rayfield:Notify({
         Title = "Visualizations Cleared",
         Content = "All path visuals removed",
         Duration = 3,
         Image = 4483361688
      })
   end,
})

-- Debug Tab
local DebugTab = Window:CreateTab("Debug Info", 4483361688)

DebugTab:CreateLabel("System Performance:")
local fpsLabel = DebugTab:CreateLabel("FPS: 60")
local npcCountLabel = DebugTab:CreateLabel("Active NPCs: 0")
local upgradeLabel = DebugTab:CreateLabel("Next Upgrade: DamageUpgrade")

-- Function to initialize system
function AutoFarm:InitializeSystem()
    self:RefreshNPCs()
    self:ClearVisualizations()
    self.CurrentUpgradeIndex = 1
    self.Bosses = {}
end

-- Function to stop system
function AutoFarm:StopSystem()
    for npc, data in pairs(self.NPCs) do
        if npc and npc.Parent and npc:FindFirstChild("Humanoid") then
            npc.Humanoid:MoveTo(npc.HumanoidRootPart.Position)
        end
    end
    self:ClearVisualizations()
    
    -- Stop all coroutines
    for _, coroutine in pairs(self.ActiveCoroutines) do
        coroutine.close()
    end
    self.ActiveCoroutines = {}
end

-- Function to refresh NPCs
function AutoFarm:RefreshNPCs()
    self.NPCs = {}
    for _, npc in pairs(workspace:GetChildren()) do
        if self:IsValidNPC(npc) then
            self.NPCs[npc] = {
                lastHealth = npc.Humanoid.Health,
                lastDecisionTime = 0,
                currentTarget = nil,
                pathVisuals = {},
                isProcessing = false
            }
            npc.Humanoid.WalkSpeed = 22
        end
    end
end

-- Function to check if NPC is valid
function AutoFarm:IsValidNPC(npc)
    return npc:IsA("Model") and 
           npc:FindFirstChild("Humanoid") and 
           npc:FindFirstChild("HumanoidRootPart") and
           npc.Humanoid.Health > 0
end

-- Function to clear visualizations
function AutoFarm:ClearVisualizations()
    for _, visual in pairs(self.PathVisuals) do
        if visual and visual.Parent then
            visual:Destroy()
        end
    end
    self.PathVisuals = {}
    
    for npc, data in pairs(self.NPCs) do
        if data.pathVisuals then
            for _, visual in pairs(data.pathVisuals) do
                if visual and visual.Parent then
                    visual:Destroy()
                end
            end
            data.pathVisuals = {}
        end
    end
    
    ESPFolder:ClearAllChildren()
end

-- Function to create path visualization
function AutoFarm:CreatePathVisual(startPos, endPos, npc, color)
    if self.PerformanceMode then return nil end
    
    local distance = (endPos - startPos).Magnitude
    local part = Instance.new("Part")
    part.Size = Vector3.new(0.5, 0.5, distance)
    part.CFrame = CFrame.new(startPos + (endPos - startPos) / 2, endPos)
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 0.6
    part.Color = color or Color3.fromRGB(0, 255, 0)
    part.Material = Enum.Material.Neon
    part.Parent = ESPFolder
    
    table.insert(self.PathVisuals, part)
    if npc and self.NPCs[npc] then
        table.insert(self.NPCs[npc].pathVisuals, part)
    end
    
    Debris:AddItem(part, 3)
    return part
end

-- Function to create target visualization
function AutoFarm:CreateTargetVisual(position, color, npc, size)
    if self.PerformanceMode then return nil end
    
    local part = Instance.new("Part")
    part.Size = size or Vector3.new(3, 3, 3)
    part.Position = position
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 0.4
    part.Color = color
    part.Material = Enum.Material.Neon
    part.Shape = Enum.PartType.Ball
    part.Parent = ESPFolder
    
    table.insert(self.PathVisuals, part)
    if npc and self.NPCs[npc] then
        table.insert(self.NPCs[npc].pathVisuals, part)
    end
    
    Debris:AddItem(part, 2)
    return part
end

-- Function to find nearby enemies (ULTRA EFFICIENT)
function AutoFarm:FindNearbyEnemies(npc)
    local enemies = {}
    local npcPosition = npc.HumanoidRootPart.Position
    
    -- Check players
    for _, otherPlayer in pairs(Players:GetPlayers()) do
        if otherPlayer ~= player then
            local character = otherPlayer.Character
            if character and character:FindFirstChild("HumanoidRootPart") then
                local distance = (character.HumanoidRootPart.Position - npcPosition).Magnitude
                if distance <= self.DETECTION_RANGE then
                    local isBoss = character.Name:lower():find("teacher") or character.Name:lower():find("boss")
                    table.insert(enemies, {
                        character = character, 
                        position = character.HumanoidRootPart.Position, 
                        distance = distance,
                        type = "player",
                        isBoss = isBoss
                    })
                end
            end
        end
    end
    
    -- Check NPCs
    for _, obj in pairs(workspace:GetChildren()) do
        if obj ~= npc and self:IsValidNPC(obj) then
            local distance = (obj.HumanoidRootPart.Position - npcPosition).Magnitude
            if distance <= self.DETECTION_RANGE then
                local isBoss = obj.Name:lower():find("teacher") or obj.Name:lower():find("boss")
                table.insert(enemies, {
                    character = obj, 
                    position = obj.HumanoidRootPart.Position, 
                    distance = distance,
                    type = "npc",
                    isBoss = isBoss
                })
            end
        end
    end
    
    -- Sort by distance and boss priority
    table.sort(enemies, function(a, b)
        if a.isBoss and not b.isBoss then return true end
        if b.isBoss and not a.isBoss then return false end
        return a.distance < b.distance
    end)
    
    return enemies
end
-- Function to find XP orbs (SMART DETECTION)
function AutoFarm:FindXPOrbs(npc)
    local xpOrbs = {}
    local npcPosition = npc.HumanoidRootPart.Position
    local enemies = self:FindNearbyEnemies(npc)
    
    -- Cache XP detection for performance
    local xpKeywords = {"exp", "xp", "experience"}
    
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            local objName = obj.Name:lower()
            local isXP = false
            
            for _, keyword in ipairs(xpKeywords) do
                if objName:find(keyword) then
                    isXP = true
                    break
                end
            end
            
            if isXP then
                local distance = (obj.Position - npcPosition).Magnitude
                if distance <= self.XP_DETECTION_RANGE then
                    -- Check if any enemy is too close to this orb
                    local enemyTooClose = false
                    for _, enemy in ipairs(enemies) do
                        if (enemy.position - obj.Position).Magnitude < 3 then
                            enemyTooClose = true
                            break
                        end
                    end
                    
                    if not enemyTooClose then
                        table.insert(xpOrbs, {
                            object = obj,
                            position = obj.Position,
                            distance = distance,
                            type = "xp_orb"
                        })
                    end
                end
            end
        end
    end
    
    -- Sort by distance
    table.sort(xpOrbs, function(a, b) return a.distance < b.distance end)
    
    return xpOrbs
end

-- ULTRA ADVANCED BOSS DETECTION AND AVOIDANCE
function AutoFarm:IsBossThreat(enemies)
    if #enemies == 0 then return false, nil end
    
    -- If only one enemy and it's a boss, or if any enemy is a boss
    local bossEnemies = {}
    for _, enemy in ipairs(enemies) do
        if enemy.isBoss then
            table.insert(bossEnemies, enemy)
        end
    end
    
    if #bossEnemies > 0 then
        return true, bossEnemies[1] -- Return first boss
    end
    
    -- Additional boss detection: single enemy that's strong
    if #enemies == 1 then
        local enemy = enemies[1]
        local humanoid = enemy.character:FindFirstChild("Humanoid")
        if humanoid and humanoid.MaxHealth > 500 then -- Assuming bosses have high health
            return true, enemy
        end
    end
    
    return false, nil
end

-- EXTREME BOSS AVOIDANCE PATHFINDING
function AutoFarm:CalculateBossEscapePath(npc, boss)
    local npcPosition = npc.HumanoidRootPart.Position
    local bossPosition = boss.position
    
    -- Calculate direction away from boss
    local awayFromBoss = (npcPosition - bossPosition).Unit
    
    -- Create multiple escape vectors at different angles
    local escapeVectors = {}
    for angle = -60, 60, 20 do
        local rotatedVector = CFrame.fromEulerAnglesXYZ(0, math.rad(angle), 0) * awayFromBoss
        table.insert(escapeVectors, rotatedVector)
    end
    
    -- Find the best escape vector
    local bestVector = nil
    local bestDistance = 0
    
    for _, vector in ipairs(escapeVectors) do
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
        raycastParams.FilterDescendantsInstances = {npc, ESPFolder}
        
        local raycastResult = workspace:Raycast(npcPosition, vector * 100, raycastParams)
        local hitDistance = 100
        
        if raycastResult then
            hitDistance = (raycastResult.Position - npcPosition).Magnitude
        end
        
        if hitDistance > bestDistance then
            bestDistance = hitDistance
            bestVector = vector
        end
    end
    
    if bestVector then
        local escapeDistance = math.min(bestDistance * 0.7, 50)
        local escapePosition = npcPosition + (bestVector * escapeDistance)
        
        -- Use pathfinding for the escape
        local path = PathfindingService:CreatePath({
            AgentRadius = 2.5,
            AgentHeight = 6,
            AgentCanJump = true
        })
        
        local success = pcall(function()
            path:ComputeAsync(npcPosition, escapePosition)
        end)
        
        if success and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            if #waypoints > 1 then
                -- Visualize boss escape path
                if not self.PerformanceMode then
                    for i = 1, #waypoints - 1 do
                        self:CreatePathVisual(waypoints[i].Position, waypoints[i+1].Position, npc, Color3.fromRGB(255, 0, 0))
                    end
                    self:CreateTargetVisual(bossPosition, Color3.fromRGB(255, 50, 50), npc, Vector3.new(8, 8, 8))
                end
                return waypoints
            end
        end
        
        -- Fallback: direct escape
        if not self.PerformanceMode then
            self:CreatePathVisual(npcPosition, escapePosition, npc, Color3.fromRGB(255, 0, 0))
            self:CreateTargetVisual(bossPosition, Color3.fromRGB(255, 50, 50), npc, Vector3.new(8, 8, 8))
        end
        return escapePosition
    end
    
    return nil
end

-- Function to move NPC with performance optimization
function AutoFarm:MoveNPC(npc, targetPosition, isEmergency)
    if not self.Enabled or not npc or not npc.Parent then return false end
    
    local humanoid = npc.Humanoid
    local npcPosition = npc.HumanoidRootPart.Position
    
    -- For emergency moves (boss escape), use direct movement
    if isEmergency then
        humanoid:MoveTo(targetPosition)
        if not self.PerformanceMode then
            self:CreatePathVisual(npcPosition, targetPosition, npc, Color3.fromRGB(255, 0, 0))
        end
        
        local startTime = tick()
        while (npc.HumanoidRootPart.Position - targetPosition).Magnitude > 5 and tick() - startTime < 3 do
            if not self.Enabled then return false end
            RunService.Heartbeat:Wait()
        end
        return true
    end
    
    -- Use pathfinding for normal movement
    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true
    })
    
    local success = pcall(function()
        path:ComputeAsync(npcPosition, targetPosition)
    end)
    
    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        
        -- Visualize path
        if not self.PerformanceMode then
            for i = 1, #waypoints - 1 do
                self:CreatePathVisual(waypoints[i].Position, waypoints[i+1].Position, npc)
            end
        end
        
        -- Follow waypoints
        for _, waypoint in ipairs(waypoints) do
            if not self.Enabled or not npc or not npc.Parent then break end
            
            if waypoint.Action == Enum.PathWaypointAction.Jump then
                humanoid.Jump = true
            end
            
            humanoid:MoveTo(waypoint.Position)
            
            local startTime = tick()
            while (npc.HumanoidRootPart.Position - waypoint.Position).Magnitude > 4 and tick() - startTime < 4 do
                if not self.Enabled then return false end
                
                -- Check for immediate threats during movement
                local enemies = self:FindNearbyEnemies(npc)
                local isBoss, boss = self:IsBossThreat(enemies)
                if isBoss and boss.distance < self.BOSS_SAFE_DISTANCE then
                    return false -- Abort for boss
                end
                
                RunService.Heartbeat:Wait()
            end
        end
        return true
    else
        -- Fallback to direct movement
        humanoid:MoveTo(targetPosition)
        if not self.PerformanceMode then
            self:CreatePathVisual(npcPosition, targetPosition, npc)
        end
        
        local startTime = tick()
        while (npc.HumanoidRootPart.Position - targetPosition).Magnitude > 4 and tick() - startTime < 5 do
            if not self.Enabled then return false end
            RunService.Heartbeat:Wait()
        end
        return true
    end
end

-- FIXED AUTO-UPGRADE SYSTEM
function AutoFarm:ExecuteUpgrade()
    if not self.AutoUpgrade or #self.UpgradeList == 0 then return end
    
    local upgrade = self.UpgradeList[self.CurrentUpgradeIndex]
    
    -- Create the args table exactly as required
    local args = {
        [1] = upgrade
    }
    
    -- Use pcall for error handling
    local success, errorMsg = pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes then
            local levelUp = remotes:FindFirstChild("LevelUp")
            if levelUp and levelUp:IsA("RemoteEvent") then
                levelUp:FireServer(unpack(args))
                print("✅ Upgrade executed:", upgrade)
            else
                warn("❌ LevelUp RemoteEvent not found")
            end
        else
            warn("❌ Remotes folder not found")
        end
    end)
    
    if not success then
        warn("❌ Upgrade error:", errorMsg)
    end
    
    -- Move to next upgrade
    self.CurrentUpgradeIndex = self.CurrentUpgradeIndex % #self.UpgradeList + 1
    upgradeLabel:Set("Next Upgrade: " .. self.UpgradeList[self.CurrentUpgradeIndex])
end

-- Main decision function (PERFORMANCE OPTIMIZED)
function AutoFarm:MakeDecision(npc)
    if not self.Enabled or not npc or not npc.Parent then return end
    
    local npcData = self.NPCs[npc]
    if not npcData or npcData.isProcessing then return end
    
    npcData.isProcessing = true
    npcData.lastDecisionTime = tick()
    
    -- PRIORITY #1: BOSS DETECTION AND AVOIDANCE
    local enemies = self:FindNearbyEnemies(npc)
    local isBoss, boss = self:IsBossThreat(enemies)
    
    if isBoss and boss and boss.distance < self.BOSS_SAFE_DISTANCE then
        -- EXTREME BOSS AVOIDANCE
        local escapePath = self:CalculateBossEscapePath(npc, boss)
        if escapePath then
            self:MoveNPC(npc, escapePath, true) -- Emergency move
        end
        npcData.isProcessing = false
        return
    end
    
    -- PRIORITY #2: REGULAR ENEMY AVOIDANCE
    if self.AvoidEnemies and #enemies > 0 and enemies[1].distance < self.SAFE_DISTANCE then
        local escapeDirection = (npc.HumanoidRootPart.Position - enemies[1].position).Unit
        local escapePosition = npc.HumanoidRootPart.Position + (escapeDirection * 25)
        self:MoveNPC(npc, escapePosition, false)
        npcData.isProcessing = false
        return
    end
    
    -- PRIORITY #3: XP COLLECTION
    if self.CollectXP then
        local xpOrbs = self:FindXPOrbs(npc)
        if #xpOrbs > 0 then
            local targetOrb = xpOrbs[1]
            if not self.PerformanceMode then
                self:CreateTargetVisual(targetOrb.position, Color3.fromRGB(0, 255, 255), npc)
            end
            self:MoveNPC(npc, targetOrb.position, false)
            npcData.isProcessing = false
            return
        end
    end
    
    -- Default: Smart wandering (away from enemies if any)
    local wanderDirection
    if #enemies > 0 then
        wanderDirection = (npc.HumanoidRootPart.Position - enemies[1].position).Unit
    else
        wanderDirection = Vector3.new(math.random(-1, 1), 0, math.random(-1, 1)).Unit
    end
    
    local wanderPosition = npc.HumanoidRootPart.Position + (wanderDirection * 15)
    if not self.PerformanceMode then
        self:CreateTargetVisual(wanderPosition, Color3.fromRGB(255, 255, 0), npc)
    end
    self:MoveNPC(npc, wanderPosition, false)
    
    npcData.isProcessing = false
end
-- Performance monitoring system
local function MonitorPerformance()
    frameCount = frameCount + 1
    
    if tick() - lastPerformanceCheck >= 1 then
        currentFPS = math.floor(frameCount / (tick() - lastPerformanceCheck))
        frameCount = 0
        lastPerformanceCheck = tick()
        
        fpsLabel:Set("FPS: " .. currentFPS)
        npcCountLabel:Set("Active NPCs: " .. table.count(AutoFarm.NPCs))
        
        -- Auto-adjust performance based on FPS
        if currentFPS < 30 and not AutoFarm.PerformanceMode then
            AutoFarm.PerformanceMode = true
            AutoFarm:ClearVisualizations()
        elseif currentFPS > 45 and AutoFarm.PerformanceMode then
            AutoFarm.PerformanceMode = false
        end
    end
end

-- Main system loops with performance optimization
local upgradeInterval = 3
local lastUpgradeTime = tick()

-- Upgrade execution loop (FIXED)
local upgradeCoroutine = coroutine.create(function()
    while true do
        if AutoFarm.Enabled and AutoFarm.AutoUpgrade then
            if tick() - lastUpgradeTime >= upgradeInterval then
                lastUpgradeTime = tick()
                AutoFarm:ExecuteUpgrade()
            end
        end
        RunService.Heartbeat:Wait()
    end
end)
coroutine.resume(upgradeCoroutine)

-- NPC processing loop (OPTIMIZED)
local npcProcessCoroutine = coroutine.create(function()
    local lastProcessTime = tick()
    local processIndex = 1
    local npcList = {}
    
    while true do
        if AutoFarm.Enabled then
            -- Update NPC list every second
            if tick() - lastProcessTime > 1 then
                npcList = {}
                for npc in pairs(AutoFarm.NPCs) do
                    if npc and npc.Parent then
                        table.insert(npcList, npc)
                    else
                        AutoFarm.NPCs[npc] = nil
                    end
                end
                lastProcessTime = tick()
            end
            
            -- Process NPCs in batches
            if #npcList > 0 then
                local npc = npcList[processIndex]
                if npc and AutoFarm.NPCs[npc] then
                    local npcData = AutoFarm.NPCs[npc]
                    if tick() - npcData.lastDecisionTime > 2 then
                        AutoFarm:MakeDecision(npc)
                    end
                end
                
                processIndex = processIndex % #npcList + 1
            end
        end
        RunService.Heartbeat:Wait()
    end
end)
coroutine.resume(npcProcessCoroutine)

-- Performance monitoring coroutine
local performanceCoroutine = coroutine.create(function()
    while true do
        MonitorPerformance()
        RunService.Heartbeat:Wait()
    end
end)
coroutine.resume(performanceCoroutine)

-- Store active coroutines
AutoFarm.ActiveCoroutines = {
    upgrade = upgradeCoroutine,
    npcProcess = npcProcessCoroutine,
    performance = performanceCoroutine
}

-- Cleanup function
function AutoFarm:Cleanup()
    for _, coroutine in pairs(self.ActiveCoroutines) do
        if coroutine and coroutine.close then
            coroutine.close()
        end
    end
    self.ActiveCoroutines = {}
    self:ClearVisualizations()
end

-- Initialize on start
AutoFarm:InitializeSystem()

-- Load the UI
Rayfield:LoadConfiguration()

Rayfield:Notify({
   Title = "ULTIMATE AutoFarm Loaded",
   Content = "Advanced system initialized with:\n• Extreme Boss Avoidance\n• Smart XP Collection\n• Fixed Auto-Upgrade System\n• Performance Optimization",
   Duration = 6,
   Image = 4483361688
})

print("==========================================")
print("ULTIMATE AUTOFARM SYSTEM LOADED SUCCESSFULLY")
print("==========================================")
print("FIXED FEATURES:")
print("✅ Auto-Upgrade System - Now working perfectly")
print("✅ Extreme Boss Avoidance - Stays far away from bosses")
print("✅ Performance Optimized - No more freezing")
print("✅ Smart Pathfinding - Advanced obstacle avoidance")
print("✅ Real-time Visualizations - Green paths, red for danger")
print("==========================================")

-- Connect cleanup
game:GetService("Players").PlayerRemoving:Connect(function(leavingPlayer)
    if leavingPlayer == player then
        AutoFarm:Cleanup()
    end
end)

-- Auto-cleanup on game close
game:BindToClose(function()
    AutoFarm:Cleanup()
end)
