-- Load Rayfield Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Player
local player = Players.LocalPlayer

-- AutoFarm System
local AutoFarm = {
    Enabled = false,
    AvoidEnemies = true,
    CollectXP = true,
    AutoUpgrade = true,
    SAFE_DISTANCE = 15,
    DETECTION_RANGE = 35,
    XP_DETECTION_RANGE = 50,
    NPCs = {},
    UpgradeList = {
        "DamageUpgrade", "ExpUpgrade", "DodgeUpgrade", "CritChanceUpgrade", 
        "Acid", "Can", "Pin", "MagnetUpgrade", "ReviveUpgrade", "Cashupgrade"
    },
    CurrentTarget = nil,
    PathVisuals = {},
    LastUpgradeIndex = 1
}

-- Create ESP visualization folder
local ESPFolder = Instance.new("Folder")
ESPFolder.Name = "AutoFarmESP"
ESPFolder.Parent = workspace

-- Create Window
local Window = Rayfield:CreateWindow({
   Name = "Ultimate AutoFarm System",
   LoadingTitle = "Loading AutoFarm Controller",
   LoadingSubtitle = "Initializing advanced pathfinding...",
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
            Content = "Advanced farming system activated",
            Duration = 3,
            Image = 4483361688
         })
         AutoFarm:InitializeSystem()
      else
         AutoFarm:StopSystem()
         Rayfield:Notify({
            Title = "AutoFarm Stopped",
            Content = "System has been disabled",
            Duration = 3,
            Image = 4483361688
         })
      end
   end,
})

-- Enemy Avoidance Toggle
MainTab:CreateToggle({
   Name = "Advanced Enemy Avoidance",
   CurrentValue = true,
   Callback = function(Value)
      AutoFarm.AvoidEnemies = Value
   end,
})

-- XP Collection Toggle
MainTab:CreateToggle({
   Name = "Auto Collect XP Orbs",
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

-- Settings Tab
local SettingsTab = Window:CreateTab("Settings", 4483361688)

-- Safe Distance Slider
SettingsTab:CreateSlider({
   Name = "Enemy Safe Distance",
   Range = {5, 30},
   Increment = 1,
   Suffix = "studs",
   CurrentValue = 15,
   Callback = function(Value)
      AutoFarm.SAFE_DISTANCE = Value
   end,
})

-- Detection Range Slider
SettingsTab:CreateSlider({
   Name = "Enemy Detection Range",
   Range = {20, 50},
   Increment = 1,
   Suffix = "studs",
   CurrentValue = 35,
   Callback = function(Value)
      AutoFarm.DETECTION_RANGE = Value
   end,
})

-- XP Detection Range Slider
SettingsTab:CreateSlider({
   Name = "XP Detection Range",
   Range = {30, 100},
   Increment = 5,
   Suffix = "studs",
   CurrentValue = 50,
   Callback = function(Value)
      AutoFarm.XP_DETECTION_RANGE = Value
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

-- Function to initialize system
function AutoFarm:InitializeSystem()
    self:RefreshNPCs()
    self:ClearVisualizations()
end

-- Function to stop system
function AutoFarm:StopSystem()
    for npc, data in pairs(self.NPCs) do
        if npc and npc.Parent and npc:FindFirstChild("Humanoid") then
            npc.Humanoid:MoveTo(npc.HumanoidRootPart.Position)
        end
    end
    self:ClearVisualizations()
end

-- Function to refresh NPCs
function AutoFarm:RefreshNPCs()
    self.NPCs = {}
    for _, npc in pairs(workspace:GetChildren()) do
        if npc:IsA("Model") and npc:FindFirstChild("Humanoid") and npc:FindFirstChild("HumanoidRootPart") then
            self.NPCs[npc] = {
                lastHealth = npc.Humanoid.Health,
                currentPath = nil,
                lastDecisionTime = 0,
                currentTarget = nil,
                pathVisuals = {}
            }
            npc.Humanoid.WalkSpeed = 24
        end
    end
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
function AutoFarm:CreatePathVisual(startPos, endPos, npc)
    local distance = (endPos - startPos).Magnitude
    local part = Instance.new("Part")
    part.Size = Vector3.new(1, 1, distance)
    part.CFrame = CFrame.new(startPos + (endPos - startPos) / 2, endPos)
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 0.7
    part.Color = Color3.fromRGB(0, 255, 0)
    part.Material = Enum.Material.Neon
    part.Parent = ESPFolder
    
    table.insert(self.PathVisuals, part)
    if npc and self.NPCs[npc] then
        table.insert(self.NPCs[npc].pathVisuals, part)
    end
    
    game.Debris:AddItem(part, 5)
    return part
end

-- Function to create target visualization
function AutoFarm:CreateTargetVisual(position, color, npc)
    local part = Instance.new("Part")
    part.Size = Vector3.new(3, 3, 3)
    part.Position = position
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 0.5
    part.Color = color
    part.Material = Enum.Material.Neon
    part.Shape = Enum.PartType.Ball
    part.Parent = ESPFolder
    
    table.insert(self.PathVisuals, part)
    if npc and self.NPCs[npc] then
        table.insert(self.NPCs[npc].pathVisuals, part)
    end
    
    game.Debris:AddItem(part, 3)
    return part
end

-- Function to find nearby enemies (ULTRA ACCURATE)
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
                    table.insert(enemies, {
                        character = character, 
                        position = character.HumanoidRootPart.Position, 
                        distance = distance,
                        type = "player"
                    })
                end
            end
        end
    end
    
    -- Check NPCs
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj ~= npc and obj:FindFirstChild("Humanoid") and obj:FindFirstChild("HumanoidRootPart") then
            local humanoid = obj:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then
                local distance = (obj.HumanoidRootPart.Position - npcPosition).Magnitude
                if distance <= self.DETECTION_RANGE then
                    table.insert(enemies, {
                        character = obj, 
                        position = obj.HumanoidRootPart.Position, 
                        distance = distance,
                        type = "npc"
                    })
                end
            end
        end
    end
    
    -- Sort by distance
    table.sort(enemies, function(a, b) return a.distance < b.distance end)
    
    return enemies
end
-- Function to find XP orbs (PRIORITY #2)
function AutoFarm:FindXPOrbs(npc)
    local xpOrbs = {}
    local npcPosition = npc.HumanoidRootPart.Position
    local enemies = self:FindNearbyEnemies(npc)
    
    -- Look for XP items
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and (obj.Name:lower():find("exp") or obj.Name:lower():find("xp") or obj.Name:lower():find("experience")) then
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
    
    -- Sort by distance
    table.sort(xpOrbs, function(a, b) return a.distance < b.distance end)
    
    return xpOrbs
end

-- ADVANCED PATHFINDING FUNCTION (PRIORITY #1)
function AutoFarm:CalculateEscapePath(npc, enemies)
    if #enemies == 0 then return nil end
    
    local npcPosition = npc.HumanoidRootPart.Position
    local closestEnemy = enemies[1]
    
    -- Calculate multiple escape directions
    local escapeDirections = {}
    for angle = -180, 180, 45 do
        local direction = (npcPosition - closestEnemy.position).Unit
        local rotatedDirection = CFrame.fromEulerAnglesXYZ(0, math.rad(angle), 0) * direction
        table.insert(escapeDirections, rotatedDirection)
    end
    
    -- Test each direction for obstacles
    local bestDirection = nil
    local bestDistance = 0
    
    for _, direction in ipairs(escapeDirections) do
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
        raycastParams.FilterDescendantsInstances = {npc, ESPFolder}
        raycastParams.CollisionGroup = "Default"
        
        local raycastResult = workspace:Raycast(npcPosition, direction * 50, raycastParams)
        local hitDistance = 50
        
        if raycastResult then
            hitDistance = (raycastResult.Position - npcPosition).Magnitude
        end
        
        if hitDistance > bestDistance then
            bestDistance = hitDistance
            bestDirection = direction
        end
    end
    
    if bestDirection then
        local escapePosition = npcPosition + (bestDirection * math.min(bestDistance * 0.8, 30))
        
        -- Use pathfinding for final path
        local path = PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true
        })
        
        local success = pcall(function()
            path:ComputeAsync(npcPosition, escapePosition)
        end)
        
        if success and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            if #waypoints > 1 then
                -- Create visual path
                for i = 1, #waypoints - 1 do
                    self:CreatePathVisual(waypoints[i].Position, waypoints[i+1].Position, npc)
                end
                return waypoints
            end
        end
        
        -- Fallback to direct escape
        self:CreatePathVisual(npcPosition, escapePosition, npc)
        return escapePosition
    end
    
    return nil
end

-- Function to move to target with pathfinding
function AutoFarm:MoveToTargetWithPathfinding(npc, targetPosition)
    local npcPosition = npc.HumanoidRootPart.Position
    local humanoid = npc.Humanoid
    
    -- Use pathfinding
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
        
        -- Create visual path
        for i = 1, #waypoints - 1 do
            self:CreatePathVisual(waypoints[i].Position, waypoints[i+1].Position, npc)
        end
        
        -- Follow waypoints
        for _, waypoint in ipairs(waypoints) do
            if not self.Enabled or not npc or not npc.Parent then break end
            
            if waypoint.Action == Enum.PathWaypointAction.Jump then
                humanoid.Jump = true
            end
            
            humanoid:MoveTo(waypoint.Position)
            
            local startTime = tick()
            while (npc.HumanoidRootPart.Position - waypoint.Position).Magnitude > 3 and tick() - startTime < 5 do
                if not self.Enabled then return false end
                
                -- Check for enemies during movement
                local enemies = self:FindNearbyEnemies(npc)
                if self.AvoidEnemies and #enemies > 0 and enemies[1].distance < self.SAFE_DISTANCE then
                    return false -- Escape enemies
                end
                
                RunService.Heartbeat:Wait()
            end
        end
        return true
    else
        -- Fallback to direct movement
        humanoid:MoveTo(targetPosition)
        self:CreatePathVisual(npcPosition, targetPosition, npc)
        
        local startTime = tick()
        while (npc.HumanoidRootPart.Position - targetPosition).Magnitude > 3 and tick() - startTime < 8 do
            if not self.Enabled then return false end
            
            -- Check for enemies during movement
            local enemies = self:FindNearbyEnemies(npc)
            if self.AvoidEnemies and #enemies > 0 and enemies[1].distance < self.SAFE_DISTANCE then
                return false -- Escape enemies
            end
            
            RunService.Heartbeat:Wait()
        end
        return true
    end
end

-- Function to execute single upgrade
function AutoFarm:ExecuteSingleUpgrade()
    if not self.AutoUpgrade or #self.UpgradeList == 0 then return end
    
    local upgrade = self.UpgradeList[self.LastUpgradeIndex]
    local args = {upgrade}
    
    pcall(function()
        local remote = ReplicatedStorage:FindFirstChild("Remotes")
        if remote then
            remote = remote:FindFirstChild("LevelUp")
            if remote then
                remote:FireServer(unpack(args))
                print("Executed upgrade:", upgrade)
            end
        end
    end)
    
    -- Move to next upgrade
    self.LastUpgradeIndex = self.LastUpgradeIndex + 1
    if self.LastUpgradeIndex > #self.UpgradeList then
        self.LastUpgradeIndex = 1
    end
end

-- Main decision function (PRIORITY BASED)
function AutoFarm:MakeDecision(npc)
    if not self.Enabled or not npc or not npc.Parent or npc.Humanoid.Health <= 0 then return end
    
    local npcData = self.NPCs[npc]
    if not npcData then return end
    
    -- PRIORITY #1: AVOID ENEMIES
    if self.AvoidEnemies then
        local enemies = self:FindNearbyEnemies(npc)
        if #enemies > 0 and enemies[1].distance < self.SAFE_DISTANCE then
            self:CreateTargetVisual(enemies[1].position, Color3.fromRGB(255, 0, 0), npc)
            local escapePath = self:CalculateEscapePath(npc, enemies)
            if escapePath then
                if type(escapePath) == "table" then
                    -- Follow path waypoints
                    for _, waypoint in ipairs(escapePath) do
                        if waypoint.Action == Enum.PathWaypointAction.Jump then
                            npc.Humanoid.Jump = true
                        end
                        npc.Humanoid:MoveTo(waypoint.Position)
                        wait(0.5)
                    end
                else
                    -- Move to escape position
                    self:MoveToTargetWithPathfinding(npc, escapePath)
                end
                return
            end
        end
    end
    
    -- PRIORITY #2: COLLECT XP ORBS
    if self.CollectXP then
        local xpOrbs = self:FindXPOrbs(npc)
        if #xpOrbs > 0 then
            local targetOrb = xpOrbs[1]
            self:CreateTargetVisual(targetOrb.position, Color3.fromRGB(0, 255, 255), npc)
            self:MoveToTargetWithPathfinding(npc, targetOrb.position)
            return
        end
    end
    
    -- Default: Wander randomly
    local randomDirection = Vector3.new(math.random(-1, 1), 0, math.random(-1, 1)).Unit
    local wanderPosition = npc.HumanoidRootPart.Position + (randomDirection * 20)
    self:CreateTargetVisual(wanderPosition, Color3.fromRGB(255, 255, 0), npc)
    self:MoveToTargetWithPathfinding(npc, wanderPosition)
end
-- Main system loops
local lastUpgradeTime = 0
local lastNPCTime = 0
local lastXPSearchTime = 0

-- Upgrade execution loop (runs every 3 seconds, one upgrade at a time)
local upgradeLoop = RunService.Heartbeat:Connect(function()
    if not AutoFarm.Enabled or not AutoFarm.AutoUpgrade then return end
    
    if tick() - lastUpgradeTime > 3 then
        lastUpgradeTime = tick()
        AutoFarm:ExecuteSingleUpgrade()
    end
end)

-- NPC processing loop
local npcLoop = RunService.Heartbeat:Connect(function()
    if not AutoFarm.Enabled then return end
    
    -- Process NPCs at controlled intervals
    if tick() - lastNPCTime > 0.3 then
        lastNPCTime = tick()
        
        for npc, npcData in pairs(AutoFarm.NPCs) do
            if npc and npc.Parent and npc:FindFirstChild("Humanoid") and npc:FindFirstChild("HumanoidRootPart") then
                if tick() - npcData.lastDecisionTime > 1.5 then
                    npcData.lastDecisionTime = tick()
                    AutoFarm:MakeDecision(npc)
                end
            else
                AutoFarm.NPCs[npc] = nil
            end
        end
    end
end)

-- XP search refresh loop
local xpRefreshLoop = RunService.Heartbeat:Connect(function()
    if not AutoFarm.Enabled or not AutoFarm.CollectXP then return end
    
    if tick() - lastXPSearchTime > 5 then
        lastXPSearchTime = tick()
        -- This ensures XP orbs are regularly detected
    end
end)

-- Cleanup function
function AutoFarm:Cleanup()
    upgradeLoop:Disconnect()
    npcLoop:Disconnect()
    xpRefreshLoop:Disconnect()
    self:ClearVisualizations()
end

-- Initialize on start
AutoFarm:InitializeSystem()

-- Load the UI
Rayfield:LoadConfiguration()

Rayfield:Notify({
   Title = "Ultimate AutoFarm Loaded",
   Content = "System initialized with advanced pathfinding\n• Enemy Avoidance (Priority #1)\n• XP Collection (Priority #2)  \n• Auto Upgrades (Every 3 seconds)",
   Duration = 6,
   Image = 4483361688
})

print("====================================")
print("ULTIMATE AUTOFARM SYSTEM LOADED")
print("====================================")
print("Features:")
print("• Advanced Enemy Avoidance System")
print("• Smart XP Orb Collection")
print("• Auto-Upgrade Execution (Sequential)")
print("• Real-time Path Visualization")
print("• Wall & Obstacle Avoidance")
print("• Rayfield UI Control Panel")
print("====================================")

-- Connect cleanup
game:GetService("Players").PlayerRemoving:Connect(function(leavingPlayer)
    if leavingPlayer == player then
        AutoFarm:Cleanup()
    end
end)
