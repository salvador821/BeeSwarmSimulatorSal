-- Load Rayfield Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

-- Player
local player = Players.LocalPlayer

-- AutoFarm System
local AutoFarm = {
    Enabled = false,
    AvoidEnemies = true,
    AttackBosses = true,
    BossTeleportHeight = 25,
    SAFE_DISTANCE = 15,
    DETECTION_RANGE = 35,
    NPCs = {},
    UpgradeList = {"DamageUpgrade", "ExpUpgrade", "DodgeUpgrade", "CritChanceUpgrade", "Acid", "Can", "Pin", "MagnetUpgrade", "ReviveUpgrade", "Cashupgrade"},
    CurrentTarget = nil
}

-- Create Window
local Window = Rayfield:CreateWindow({
   Name = "AutoFarm System",
   LoadingTitle = "AutoFarm Controller",
   LoadingSubtitle = "Loading features...",
   ConfigurationSaving = {
      Enabled = false,
   },
   Discord = {
      Enabled = false,
   }
})

-- Main Tab
local MainTab = Window:CreateTab("Main", 4483361688)

-- AutoFarm Toggle
MainTab:CreateToggle({
   Name = "Enable AutoFarm",
   CurrentValue = false,
   Callback = function(Value)
      AutoFarm.Enabled = Value
      if Value then
         Rayfield:Notify({
            Title = "AutoFarm Started",
            Content = "Auto farming is now enabled",
            Duration = 3,
            Image = 4483361688
         })
      else
         -- Stop all movement when disabled
         for npc, data in pairs(AutoFarm.NPCs) do
            if npc and npc.Parent and npc:FindFirstChild("Humanoid") then
               npc.Humanoid:MoveTo(npc.HumanoidRootPart.Position)
            end
         end
         Rayfield:Notify({
            Title = "AutoFarm Stopped",
            Content = "Auto farming is now disabled",
            Duration = 3,
            Image = 4483361688
         })
      end
   end,
})

-- Enemy Avoidance Toggle
MainTab:CreateToggle({
   Name = "Avoid Enemies",
   CurrentValue = true,
   Callback = function(Value)
      AutoFarm.AvoidEnemies = Value
   end,
})

-- Boss Attack Toggle
MainTab:CreateToggle({
   Name = "Attack Bosses",
   CurrentValue = true,
   Callback = function(Value)
      AutoFarm.AttackBosses = Value
   end,
})

-- Boss Height Slider
MainTab:CreateSlider({
   Name = "Boss Teleport Height",
   Range = {10, 50},
   Increment = 5,
   Suffix = "studs",
   CurrentValue = 25,
   Callback = function(Value)
      AutoFarm.BossTeleportHeight = Value
   end,
})

-- Refresh NPCs Button
MainTab:CreateButton({
   Name = "Refresh NPCs",
   Callback = function()
      AutoFarm.NPCs = {}
      for _, npc in pairs(workspace:GetChildren()) do
         if npc:IsA("Model") and npc:FindFirstChild("Humanoid") and npc:FindFirstChild("HumanoidRootPart") then
            AutoFarm.NPCs[npc] = {
               lastHealth = npc.Humanoid.Health,
               currentPath = nil,
               lastDecisionTime = 0
            }
            npc.Humanoid.WalkSpeed = 22
         end
      end
      Rayfield:Notify({
         Title = "NPCs Refreshed",
         Content = "Found " .. table.count(AutoFarm.NPCs) .. " NPCs",
         Duration = 3,
         Image = 4483361688
      })
   end,
})

-- Function to find nearby enemies
function AutoFarm:FindNearbyEnemies(npc)
    local enemies = {}
    local bosses = {}
    local npcPosition = npc.HumanoidRootPart.Position
    
    -- Check players
    for _, otherPlayer in pairs(Players:GetPlayers()) do
        if otherPlayer ~= player then
            local character = otherPlayer.Character
            if character and character:FindFirstChild("HumanoidRootPart") then
                local distance = (character.HumanoidRootPart.Position - npcPosition).Magnitude
                if distance <= self.DETECTION_RANGE then
                    local enemyData = {
                        character = character, 
                        position = character.HumanoidRootPart.Position, 
                        distance = distance
                    }
                    
                    if character.Name:lower():find("teacher") or character.Name:lower():find("boss") then
                        table.insert(bosses, enemyData)
                    else
                        table.insert(enemies, enemyData)
                    end
                end
            end
        end
    end
    
    -- Check NPCs
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj ~= npc and obj:FindFirstChild("Humanoid") and obj:FindFirstChild("HumanoidRootPart") then
            local distance = (obj.HumanoidRootPart.Position - npcPosition).Magnitude
            if distance <= self.DETECTION_RANGE then
                local enemyData = {
                    character = obj, 
                    position = obj.HumanoidRootPart.Position, 
                    distance = distance
                }
                
                if obj.Name:lower():find("teacher") or obj.Name:lower():find("boss") then
                    table.insert(bosses, enemyData)
                else
                    table.insert(enemies, enemyData)
                end
            end
        end
    end
    
    -- Sort by distance
    table.sort(enemies, function(a, b) return a.distance < b.distance end)
    table.sort(bosses, function(a, b) return a.distance < b.distance end)
    
    return enemies, bosses
end
-- Function to find XP and items
function AutoFarm:FindTargets(npc)
    local npcPosition = npc.HumanoidRootPart.Position
    local targets = {}
    
    -- Look for XP items
    for _, obj in pairs(workspace:GetDescendants()) do
        if (obj.Name:lower():find("experience") or obj.Name:lower():find("xp")) and obj:IsA("BasePart") then
            local distance = (obj.Position - npcPosition).Magnitude
            if distance <= 50 then
                table.insert(targets, {
                    object = obj,
                    position = obj.Position,
                    distance = distance,
                    type = "xp"
                })
            end
        end
    end
    
    -- Look for coins or collectibles
    for _, obj in pairs(workspace:GetDescendants()) do
        if (obj.Name:lower():find("coin") or obj.Name:lower():find("money") or obj.Name:lower():find("collect")) and obj:IsA("BasePart") then
            local distance = (obj.Position - npcPosition).Magnitude
            if distance <= 50 then
                table.insert(targets, {
                    object = obj,
                    position = obj.Position,
                    distance = distance,
                    type = "coin"
                })
            end
        end
    end
    
    -- Sort by distance
    table.sort(targets, function(a, b) return a.distance < b.distance end)
    
    return targets
end

-- Function to calculate escape path (IMPROVED)
function AutoFarm:CalculateEscapePath(npc, enemies)
    if #enemies == 0 then return nil end
    
    local npcPosition = npc.HumanoidRootPart.Position
    local escapeVector = Vector3.new(0, 0, 0)
    local closestEnemy = enemies[1]
    
    -- Calculate direction away from closest enemy
    local awayFromEnemy = (npcPosition - closestEnemy.position).Unit
    
    -- Add some randomness to avoid predictable patterns
    local randomAngle = math.random(-45, 45)
    local randomDirection = CFrame.fromEulerAnglesXYZ(0, math.rad(randomAngle), 0) * awayFromEnemy
    
    -- Use pathfinding to find a safe path
    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true
    })
    
    local targetPosition = npcPosition + (randomDirection * 25)
    
    -- Try to compute path
    local success, errorMessage = pcall(function()
        path:ComputeAsync(npcPosition, targetPosition)
    end)
    
    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        if #waypoints > 1 then
            return waypoints[2].Position -- Return the first waypoint position
        end
    end
    
    -- Fallback: move directly away from enemy
    return npcPosition + (awayFromEnemy * 20)
end

-- Function to handle boss enemies
function AutoFarm:HandleBoss(npc, boss)
    if not boss or not npc or not npc.Parent then return end
    
    local teleportPosition = boss.position + Vector3.new(0, self.BossTeleportHeight, 0)
    npc.HumanoidRootPart.CFrame = CFrame.new(teleportPosition)
    return true
end

-- Function to move to target
function AutoFarm:MoveToTarget(npc, targetPosition)
    local humanoid = npc.Humanoid
    humanoid:MoveTo(targetPosition)
    
    local startTime = tick()
    while (npc.HumanoidRootPart.Position - targetPosition).Magnitude > 5 and tick() - startTime < 8 do
        if not AutoFarm.Enabled then return false end
        
        -- Check if we need to escape enemies during movement
        local enemies, bosses = AutoFarm:FindNearbyEnemies(npc)
        if AutoFarm.AvoidEnemies and #enemies > 0 and enemies[1].distance < AutoFarm.SAFE_DISTANCE then
            return false -- Interrupt movement to escape
        end
        
        RunService.Heartbeat:Wait()
    end
    
    return true
end

-- Auto-upgrade function (FIXED)
function AutoFarm:AttemptUpgrade()
    for _, upgrade in ipairs(self.UpgradeList) do
        local args = {upgrade}
        pcall(function()
            local remote = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("LevelUp")
            remote:FireServer(unpack(args))
        end)
        wait(0.2) -- Small delay between upgrades
    end
end

-- Main decision function (IMPROVED)
function AutoFarm:MakeDecision(npc)
    if not self.Enabled or not npc or not npc.Parent or npc.Humanoid.Health <= 0 then return end
    
    -- Find enemies and bosses
    local enemies, bosses = self:FindNearbyEnemies(npc)
    
    -- Handle bosses first if enabled
    if self.AttackBosses and #bosses > 0 then
        if self:HandleBoss(npc, bosses[1]) then
            return
        end
    end
    
    -- AVOID ENEMIES (IMPROVED) - Run away if enemies are close
    if self.AvoidEnemies and #enemies > 0 and enemies[1].distance < self.SAFE_DISTANCE then
        local escapePosition = self:CalculateEscapePath(npc, enemies)
        if escapePosition then
            self:MoveToTarget(npc, escapePosition)
            return
        end
    end
    
    -- Find and move to targets (XP, coins, etc)
    local targets = self:FindTargets(npc)
    if #targets > 0 then
        self:MoveToTarget(npc, targets[1].position)
        return
    end
    
    -- Wander randomly if no targets found (away from enemies)
    local randomDirection
    if #enemies > 0 then
        -- Wander away from enemies
        randomDirection = (npc.HumanoidRootPart.Position - enemies[1].position).Unit
    else
        -- Random wander
        randomDirection = Vector3.new(math.random(-1, 1), 0, math.random(-1, 1)).Unit
    end
    
    local wanderPosition = npc.HumanoidRootPart.Position + (randomDirection * 20)
    self:MoveToTarget(npc, wanderPosition)
end
-- Initialize NPCs
function AutoFarm:InitNPCs()
    for _, npc in pairs(workspace:GetChildren()) do
        if npc:IsA("Model") and npc:FindFirstChild("Humanoid") and npc:FindFirstChild("HumanoidRootPart") then
            self.NPCs[npc] = {
                lastHealth = npc.Humanoid.Health,
                currentPath = nil,
                lastDecisionTime = 0
            }
            npc.Humanoid.WalkSpeed = 22
        end
    end
    
    -- Listen for new NPCs
    workspace.ChildAdded:Connect(function(child)
        if child:IsA("Model") and child:FindFirstChild("Humanoid") and child:FindFirstChild("HumanoidRootPart") then
            self.NPCs[child] = {
                lastHealth = child.Humanoid.Health,
                currentPath = nil,
                lastDecisionTime = 0
            }
            child.Humanoid.WalkSpeed = 22
        end
    end)
end

-- Main loop
local lastUpgradeTime = 0
local lastProcessTime = 0

RunService.Heartbeat:Connect(function()
    if not AutoFarm.Enabled then return end
    
    -- Attempt upgrades every 3 seconds
    if tick() - lastUpgradeTime > 3 then
        lastUpgradeTime = tick()
        AutoFarm:AttemptUpgrade()
    end
    
    -- Process NPCs at a controlled rate (every 0.5 seconds)
    if tick() - lastProcessTime > 0.5 then
        lastProcessTime = tick()
        
        -- Process each NPC
        for npc, data in pairs(AutoFarm.NPCs) do
            if npc and npc.Parent and npc:FindFirstChild("Humanoid") and npc:FindFirstChild("HumanoidRootPart") then
                if tick() - data.lastDecisionTime > 1 then
                    data.lastDecisionTime = tick()
                    AutoFarm:MakeDecision(npc)
                end
            else
                AutoFarm.NPCs[npc] = nil
            end
        end
    end
end)

-- Initialize the system
AutoFarm:InitNPCs()

-- Load the UI
Rayfield:LoadConfiguration()

Rayfield:Notify({
   Title = "AutoFarm Loaded",
   Content = "System initialized with " .. table.count(AutoFarm.NPCs) .. " NPCs",
   Duration = 5,
   Image = 4483361688
})

print("AutoFarm System successfully loaded!")
print("Upgrades will be purchased every 3 seconds")
print("NPCs will avoid enemies effectively")
