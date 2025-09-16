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
    SAFE_DISTANCE = 10,
    DETECTION_RANGE = 30,
    NPCs = {},
    Priority = {"DamageUpgrade", "ExpUpgrade", "DodgeUpgrade", "CritChanceUpgrade"},
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

-- Priority System Tab
local PriorityTab = Window:CreateTab("Priority", 4483361688)

-- Priority Dropdown
PriorityTab:CreateDropdown({
   Name = "Set Priority Target",
   Options = {"DamageUpgrade", "ExpUpgrade", "DodgeUpgrade", "CritChanceUpgrade", "Acid", "Can", "Pin"},
   CurrentOption = "DamageUpgrade",
   Callback = function(Option)
      table.insert(AutoFarm.Priority, 1, Option)
      Rayfield:Notify({
         Title = "Priority Set",
         Content = Option .. " is now top priority",
         Duration = 3,
         Image = 4483361688
      })
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

-- Show current priority
PriorityTab:CreateLabel("Current Priority Order:")
for i, priority in ipairs(AutoFarm.Priority) do
   PriorityTab:CreateLabel(i .. ". " .. priority)
end

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

-- Function to find priority targets
function AutoFarm:FindPriorityTargets(npc)
    local npcPosition = npc.HumanoidRootPart.Position
    local targets = {}
    
    -- Look for priority items in workspace
    for _, obj in pairs(workspace:GetDescendants()) do
        for _, priority in ipairs(self.Priority) do
            if obj.Name:lower():find(priority:lower()) and obj:IsA("BasePart") then
                local distance = (obj.Position - npcPosition).Magnitude
                if distance <= 50 then
                    table.insert(targets, {
                        object = obj,
                        position = obj.Position,
                        distance = distance,
                        priority = priority
                    })
                end
            end
        end
    end
    
    -- Sort by priority and distance
    table.sort(targets, function(a, b)
        local aIndex = table.find(self.Priority, a.priority) or 99
        local bIndex = table.find(self.Priority, b.priority) or 99
        if aIndex == bIndex then
            return a.distance < b.distance
        end
        return aIndex < bIndex
    end)
    
    return targets
end
-- Function to calculate escape path
function AutoFarm:CalculateEscapePath(npc, enemies)
    if #enemies == 0 then return nil end
    
    local npcPosition = npc.HumanoidRootPart.Position
    local escapeVector = Vector3.new(0, 0, 0)
    
    for _, enemy in ipairs(enemies) do
        local direction = (npcPosition - enemy.position).Unit
        local weight = 2 / (enemy.distance + 0.1)
        escapeVector = escapeVector + (direction * weight)
    end
    
    if escapeVector.Magnitude > 0 then
        escapeVector = escapeVector.Unit
    end
    
    return escapeVector
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
        RunService.Heartbeat:Wait()
    end
    
    return true
end

-- Main decision function
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
    
    -- Avoid enemies if enabled and they're too close
    if self.AvoidEnemies and #enemies > 0 and enemies[1].distance < self.SAFE_DISTANCE then
        local escapeVector = self:CalculateEscapePath(npc, enemies)
        if escapeVector then
            local escapePosition = npc.HumanoidRootPart.Position + (escapeVector * 20)
            self:MoveToTarget(npc, escapePosition)
            return
        end
    end
    
    -- Find and move to priority targets
    local priorityTargets = self:FindPriorityTargets(npc)
    if #priorityTargets > 0 then
        self:MoveToTarget(npc, priorityTargets[1].position)
        return
    end
    
    -- Wander randomly if no targets found
    local randomDirection = Vector3.new(math.random(-1, 1), 0, math.random(-1, 1)).Unit
    local wanderPosition = npc.HumanoidRootPart.Position + (randomDirection * 15)
    self:MoveToTarget(npc, wanderPosition)
end

-- Auto-upgrade function
function AutoFarm:AttemptUpgrade()
    for _, upgrade in ipairs(self.Priority) do
        local args = {upgrade}
        pcall(function()
            game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("LevelUp"):FireServer(unpack(args))
        end)
        wait(0.5)
    end
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
RunService.Heartbeat:Connect(function()
    if not AutoFarm.Enabled then return end
    
    -- Attempt upgrades every 10 seconds
    if tick() - lastUpgradeTime > 10 then
        lastUpgradeTime = tick()
        AutoFarm:AttemptUpgrade()
    end
    
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
