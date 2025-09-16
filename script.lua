-- Load Orion Library FIRST
local OrionLib = loadstring(game:HttpGet(('https://raw.githubusercontent.com/shlexware/Orion/main/source')))()

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Get local player
local localPlayer = Players.LocalPlayer

-- Create NPC system
local NPCSystem = {
    Enabled = true,
    AutoUpgradeEnabled = true,
    SAFE_DISTANCE = 5,
    TELEPORT_DISTANCE = 8,
    DETECTION_RANGE = 30,
    XPDETECTION_RANGE = 50,
    NPCs = {},
    XPItems = {},
    UpgradePriority = {"DamageUpgrade", "ExpUpgrade", "DodgeUpgrade", "CritChanceUpgrade", "Acid", "Can", "Pin", "MagnetUpgrade", "ReviveUpgrade", "Cashupgrade"},
}

-- Try to get the upgrade remote safely
local upgradeRemote
pcall(function()
    upgradeRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LevelUp")
end)

if not upgradeRemote then
    warn("Upgrade remote not found! Auto-upgrade will not work.")
end

NPCSystem.UpgradeRemote = upgradeRemote

-- Create Orion UI
local Window = OrionLib:MakeWindow({
    Name = "NPC System",
    HidePremium = false,
    SaveConfig = true,
    ConfigFolder = "NPCSystemConfig",
    IntroEnabled = true,
    IntroText = "NPC Control System"
})

-- Create tabs
local MainTab = Window:MakeTab({
    Name = "Main Controls",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

local UpgradeTab = Window:MakeTab({
    Name = "Upgrade Settings",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

local BossTab = Window:MakeTab({
    Name = "Boss Settings",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

-- Initialize settings
NPCSystem.XPCollection = true
NPCSystem.BossHandling = true
NPCSystem.TeleportAboveBosses = true
NPCSystem.BossTeleportHeight = 25
NPCSystem.FocusBossesFirst = true

-- Main controls
MainTab:AddToggle({
    Name = "NPC Avoidance",
    Default = NPCSystem.Enabled,
    Flag = "AvoidanceToggle",
    Callback = function(Value)
        NPCSystem.Enabled = Value
        if not Value then
            for npc, data in pairs(NPCSystem.NPCs) do
                if npc and npc.Parent and npc:FindFirstChild("Humanoid") then
                    npc.Humanoid:MoveTo(npc.HumanoidRootPart.Position)
                    if data.currentPath then
                        data.currentPath:Stop()
                        data.currentPath = nil
                    end
                end
            end
        end
    end
})

MainTab:AddToggle({
    Name = "XP Collection",
    Default = NPCSystem.XPCollection,
    Flag = "XPToggle",
    Callback = function(Value)
        NPCSystem.XPCollection = Value
    end
})

MainTab:AddToggle({
    Name = "Boss Handling",
    Default = NPCSystem.BossHandling,
    Flag = "BossToggle",
    Callback = function(Value)
        NPCSystem.BossHandling = Value
    end
})

MainTab:AddButton({
    Name = "Refresh NPCs",
    Callback = function()
        for npc, data in pairs(NPCSystem.NPCs) do
            if npc and npc.Parent then
                NPCSystem.NPCs[npc] = nil
            end
        end
        
        for _, npc in pairs(workspace:GetChildren()) do
            if npc:IsA("Model") and npc:FindFirstChild("Humanoid") and npc:FindFirstChild("HumanoidRootPart") then
                NPCSystem.NPCs[npc] = {
                    lastHealth = npc.Humanoid.Health,
                    currentPath = nil,
                    lastDecisionTime = 0
                }
                npc.Humanoid.WalkSpeed = 16
            end
        end
        OrionLib:MakeNotification({
            Name = "NPCs Refreshed",
            Content = "All NPCs have been refreshed and updated.",
            Time = 5
        })
    end
})

-- Upgrade settings
UpgradeTab:AddToggle({
    Name = "Auto-Upgrade",
    Default = NPCSystem.AutoUpgradeEnabled,
    Flag = "UpgradeToggle",
    Callback = function(Value)
        NPCSystem.AutoUpgradeEnabled = Value
    end
})

-- Create dropdown for upgrade priority
local priorityDropdown = UpgradeTab:AddDropdown({
    Name = "Upgrade Priority",
    Default = NPCSystem.UpgradePriority[1],
    Options = NPCSystem.UpgradePriority,
    Flag = "PriorityDropdown",
    Callback = function(Value)
        for i, upgrade in ipairs(NPCSystem.UpgradePriority) do
            if upgrade == Value then
                table.remove(NPCSystem.UpgradePriority, i)
                table.insert(NPCSystem.UpgradePriority, 1, Value)
                break
            end
        end
        priorityDropdown:Refresh(NPCSystem.UpgradePriority, false)
    end
})

UpgradeTab:AddButton({
    Name = "Manual Upgrade",
    Callback = function()
        NPCSystem:AttemptUpgrade()
        OrionLib:MakeNotification({
            Name = "Upgrade Attempted",
            Content = "Attempted to purchase all available upgrades.",
            Time = 5
        })
    end
})

UpgradeTab:AddLabel("Current Upgrade Priority:")
for i, upgrade in ipairs(NPCSystem.UpgradePriority) do
    UpgradeTab:AddLabel(i .. ". " .. upgrade)
end

-- Boss settings
BossTab:AddToggle({
    Name = "Teleport Above Bosses",
    Default = NPCSystem.TeleportAboveBosses,
    Flag = "TeleportToggle",
    Callback = function(Value)
        NPCSystem.TeleportAboveBosses = Value
    end
})

BossTab:AddSlider({
    Name = "Boss Teleport Height",
    Min = 10,
    Max = 50,
    Default = NPCSystem.BossTeleportHeight,
    Color = Color3.fromRGB(255, 255, 255),
    Increment = 1,
    ValueName = "studs",
    Flag = "BossHeightSlider",
    Callback = function(Value)
        NPCSystem.BossTeleportHeight = Value
    end
})

BossTab:AddToggle({
    Name = "Focus Bosses First",
    Default = NPCSystem.FocusBossesFirst,
    Flag = "FocusBossToggle",
    Callback = function(Value)
        NPCSystem.FocusBossesFirst = Value
    end
})
-- Find nearby XP items
function NPCSystem:FindNearbyXP(npc)
    local xpItems = {}
    local npcPosition = npc.HumanoidRootPart.Position
    
    for _, item in pairs(self.XPItems) do
        if item and item.Parent then
            local distance = (item.Position - npcPosition).Magnitude
            if distance <= self.XPDETECTION_RANGE then
                table.insert(xpItems, {item = item, position = item.Position, distance = distance})
            end
        end
    end
    
    for _, obj in pairs(workspace:GetDescendants()) do
        if (obj.Name:lower():find("experience") or obj.Name:lower():find("xp")) and obj:IsA("BasePart") then
            local found = false
            for _, existing in pairs(self.XPItems) do
                if existing == obj then
                    found = true
                    break
                end
            end
            
            if not found then
                table.insert(self.XPItems, obj)
                local distance = (obj.Position - npcPosition).Magnitude
                if distance <= self.XPDETECTION_RANGE then
                    table.insert(xpItems, {item = obj, position = obj.Position, distance = distance})
                end
            end
        end
    end
    
    table.sort(xpItems, function(a, b) return a.distance < b.distance end)
    return xpItems
end

-- Find nearby enemies (with boss detection)
function NPCSystem:FindNearbyEnemies(npc)
    local enemies = {}
    local bosses = {}
    local npcPosition = npc.HumanoidRootPart.Position
    
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= localPlayer then
            local character = player.Character
            if character and character:FindFirstChild("HumanoidRootPart") then
                local distance = (character.HumanoidRootPart.Position - npcPosition).Magnitude
                if distance <= self.DETECTION_RANGE then
                    local enemyData = {character = character, position = character.HumanoidRootPart.Position, distance = distance}
                    
                    if character.Name:lower():find("teacher") or character.Name:lower():find("boss") then
                        table.insert(bosses, enemyData)
                    else
                        table.insert(enemies, enemyData)
                    end
                end
            end
        end
    end
    
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj ~= npc and obj:FindFirstChild("Humanoid") and obj:FindFirstChild("HumanoidRootPart") then
            local distance = (obj.HumanoidRootPart.Position - npcPosition).Magnitude
            if distance <= self.DETECTION_RANGE then
                local enemyData = {character = obj, position = obj.HumanoidRootPart.Position, distance = distance}
                
                if obj.Name:lower():find("teacher") or obj.Name:lower():find("boss") then
                    table.insert(bosses, enemyData)
                else
                    table.insert(enemies, enemyData)
                end
            end
        end
    end
    
    table.sort(enemies, function(a, b) return a.distance < b.distance end)
    table.sort(bosses, function(a, b) return a.distance < b.distance end)
    
    return enemies, bosses
end

-- Calculate escape direction with improved pathfinding
function NPCSystem:CalculateEscapePath(npc, enemies)
    if #enemies == 0 then return nil end
    
    local npcPosition = npc.HumanoidRootPart.Position
    local escapeVector = Vector3.new(0, 0, 0)
    local closestDistance = math.huge
    
    for _, enemy in pairs(enemies) do
        local direction = (npcPosition - enemy.position).Unit
        local weight = 2 / (enemy.distance + 0.1)
        escapeVector = escapeVector + (direction * weight)
        closestDistance = math.min(closestDistance, enemy.distance)
    end
    
    if escapeVector.Magnitude > 0 then
        escapeVector = escapeVector.Unit
    end
    
    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true
    })
    
    local targetPosition = npcPosition + (escapeVector * 25)
    
    local bestDirection = escapeVector
    local bestDistance = 25
    
    for angle = -45, 45, 15 do
        local testDirection = CFrame.fromEulerAnglesXYZ(0, math.rad(angle), 0) * escapeVector
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
        raycastParams.FilterDescendantsInstances = {npc}
        
        local raycastResult = workspace:Raycast(npcPosition, testDirection * 30, raycastParams)
        if raycastResult then
            local hitDistance = (raycastResult.Position - npcPosition).Magnitude
            if hitDistance > bestDistance then
                bestDistance = hitDistance
                bestDirection = testDirection
            end
        else
            bestDirection = testDirection
            bestDistance = 30
            break
        end
    end
    
    targetPosition = npcPosition + (bestDirection * bestDistance * 0.8)
    
    local success, errorMessage = pcall(function()
        path:ComputeAsync(npcPosition, targetPosition)
    end)
    
    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        if #waypoints > 1 then
            return waypoints
        end
    end
    
    return nil, escapeVector, closestDistance < self.SAFE_DISTANCE
end

-- Handle boss enemies (teleport above them)
function NPCSystem:HandleBoss(npc, boss)
    if not boss or not npc or not npc.Parent then return end
    
    local teleportPosition = boss.position + Vector3.new(0, NPCSystem.BossTeleportHeight, 0)
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {npc}
    
    local raycastResult = workspace:Raycast(boss.position, Vector3.new(0, NPCSystem.BossTeleportHeight, 0), raycastParams)
    if raycastResult and raycastResult.Position then
        teleportPosition = raycastResult.Position - Vector3.new(0, 2, 0)
    end
    
    npc.HumanoidRootPart.CFrame = CFrame.new(teleportPosition)
    return true
end

-- Calculate path to XP
function NPCSystem:CalculatePathToXP(npc, xpItem)
    if not xpItem then return nil end
    
    local npcPosition = npc.HumanoidRootPart.Position
    local targetPosition = xpItem.position
    
    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true
    })
    
    local success, errorMessage = pcall(function()
        path:ComputeAsync(npcPosition, targetPosition)
    end)
    
    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        if #waypoints > 1 then
            return waypoints
        end
    end
    
    return nil, (targetPosition - npcPosition).Unit
end

-- Health check and teleport
function NPCSystem:CheckHealthAndReact(npc)
    if not npc or not npc.Parent or not npc:FindFirstChild("Humanoid") then return end
    
    local currentHealth = npc.Humanoid.Health
    local npcData = self.NPCs[npc]
    
    if not npcData.lastHealth then
        npcData.lastHealth = currentHealth
        return
    end
    
    if currentHealth < npcData.lastHealth then
        local enemies, bosses = self:FindNearbyEnemies(npc)
        if #enemies > 0 or #bosses > 0 then
            local target = #bosses > 0 and bosses[1] or enemies[1]
            local escapeDirection = (npc.HumanoidRootPart.Position - target.position).Unit
            local teleportPosition = target.position + (escapeDirection * 5)
            
            local raycastParams = RaycastParams.new()
            raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
            raycastParams.FilterDescendantsInstances = {npc}
            
            local raycastResult = workspace:Raycast(target.position, escapeDirection * 6, raycastParams)
            if raycastResult and raycastResult.Position then
                teleportPosition = raycastResult.Position - (escapeDirection * 2)
            end
            
            npc.HumanoidRootPart.CFrame = CFrame.new(teleportPosition)
            wait(0.2)
        end
    end
    
    self.NPCs[npc].lastHealth = currentHealth
end

-- Auto-upgrade function
function NPCSystem:AttemptUpgrade()
    if not self.AutoUpgradeEnabled or not self.UpgradeRemote then return end
    
    for _, upgrade in ipairs(self.UpgradePriority) do
        local args = {upgrade}
        pcall(function()
            self.UpgradeRemote:FireServer(unpack(args))
        end)
        wait(0.1)
    end
end

-- Follow path waypoints
function NPCSystem:FollowPath(npc, waypoints)
    if not waypoints or #waypoints == 0 then return false end
    
    local npcData = self.NPCs[npc]
    if npcData.currentPath then
        npcData.currentPath:Stop()
    end
    
    npcData.currentPath = {
        Stop = function() end,
        waypoints = waypoints,
        currentWaypoint = 1
    }
    
    for i = 1, #waypoints do
        if not self.Enabled or not npc or not npc.Parent or npc.Humanoid.Health <= 0 then
            npcData.currentPath = nil
            return false
        end
        
        local waypoint = waypoints[i]
        
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            npc.Humanoid.Jump = true
        end
        
        npc.Humanoid:MoveTo(waypoint.Position)
        
        local startTime = tick()
        while (npc.HumanoidRootPart.Position - waypoint.Position).Magnitude > 3 and tick() - startTime < 5 do
            if not self.Enabled then 
                npcData.currentPath = nil
                return false 
            end
            
            local enemies, bosses = self:FindNearbyEnemies(npc)
            if (#enemies > 0 and enemies[1].distance < self.SAFE_DISTANCE) or (#bosses > 0 and NPCSystem.FocusBossesFirst) then
                npcData.currentPath = nil
                return false
            end
            
            wait(0.1)
        end
    end
    
    npcData.currentPath = nil
    return true
end

-- Wander to a random position
function NPCSystem:Wander(npc)
    if not npc or not npc.Parent or not npc:FindFirstChild("HumanoidRootPart") then return end
    
    local npcPosition = npc.HumanoidRootPart.Position
    local randomDirection = Vector3.new(math.random(-1, 1), 0, math.random(-1, 1)).Unit
    local targetPosition = npcPosition + (randomDirection * math.random(15, 30))
    
    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true
    })
    
    local success, errorMessage = pcall(function()
        path:ComputeAsync(npcPosition, targetPosition)
    end)
    
    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        if #waypoints > 1 then
            self:FollowPath(npc, waypoints)
            return
        end
    end
    
    npc.Humanoid:MoveTo(targetPosition)
    
    local startTime = tick()
    while (npc.HumanoidRootPart.Position - targetPosition).Magnitude > 5 and tick() - startTime < 8 do
        if not self.Enabled then return end
        wait(0.5)
    end
end

-- Main decision function
function NPCSystem:MakeDecision(npc)
    if not self.Enabled or not npc or not npc.Parent or npc.Humanoid.Health <= 0 then return end
    
    self:CheckHealthAndReact(npc)
    
    local enemies, bosses = self:FindNearbyEnemies(npc)
    if #bosses > 0 and NPCSystem.BossHandling and NPCSystem.TeleportAboveBosses then
        if self:HandleBoss(npc, bosses[1]) then
            return
        end
    end
    
    if #enemies > 0 and enemies[1].distance < self.DETECTION_RANGE then
        local waypoints, escapeDirection, tooClose = self:CalculateEscapePath(npc, enemies)
        
        if waypoints then
            self:FollowPath(npc, waypoints)
        elseif escapeDirection then
            npc.Humanoid.WalkSpeed = tooClose and 22 or 16
            local targetPosition = npc.HumanoidRootPart.Position + (escapeDirection * self.SAFE_DISTANCE * 3)
            npc.Humanoid:MoveTo(targetPosition)
            
            local startTime = tick()
            while (npc.HumanoidRootPart.Position - targetPosition).Magnitude > 3 and tick() - startTime < 3 do
                if not self.Enabled then return end
                wait(0.1)
            end
        end
        return
    end
    
    if NPCSystem.XPCollection then
        local xpItems = self:FindNearbyXP(npc)
        if #xpItems > 0 then
            local waypoints, direction = self:CalculatePathToXP(npc, xpItems[1])
            
            if waypoints then
                self:FollowPath(npc, waypoints)
            elseif direction then
                npc.Humanoid.WalkSpeed = 16
                npc.Humanoid:MoveTo(xpItems[1].position)
                
                local startTime = tick()
                while (npc.HumanoidRootPart.Position - xpItems[1].position).Magnitude > 3 and tick() - startTime < 5 do
                    if not self.Enabled then return end
                    wait(0.1)
                end
            end
            return
        end
    end
    
    self:Wander(npc)
end

-- Initialize system
function NPCSystem:Init()
    for _, obj in pairs(workspace:GetDescendants()) do
        if (obj.Name:lower():find("experience") or obj.Name:lower():find("xp")) and obj:IsA("BasePart") then
            table.insert(self.XPItems, obj)
        end
    end
    
    workspace.DescendantAdded:Connect(function(descendant)
        if (descendant.Name:lower():find("experience") or descendant.Name:lower():find("xp")) and descendant:IsA("BasePart") then
            table.insert(self.XPItems, descendant)
        end
    end)
    
    for _, npc in pairs(workspace:GetChildren()) do
        if npc:IsA("Model") and npc:FindFirstChild("Humanoid") and npc:FindFirstChild("HumanoidRootPart") then
            self.NPCs[npc] = {
                lastHealth = npc.Humanoid.Health,
                currentPath = nil,
                lastDecisionTime = 0
            }
            npc.Humanoid.WalkSpeed = 16
        end
    end
    
    workspace.ChildAdded:Connect(function(child)
        wait(0.5)
        if child:IsA("Model") and child:FindFirstChild("Humanoid") and child:FindFirstChild("HumanoidRootPart") then
            self.NPCs[child] = {
                lastHealth = child.Humanoid.Health,
                currentPath = nil,
                lastDecisionTime = 0
            }
            child.Humanoid.WalkSpeed = 16
        end
    end)
    
    workspace.ChildRemoved:Connect(function(child)
        if self.NPCs[child] then self.NPCs[child] = nil end
    end)
    
    local lastUpgradeTime = 0
    RunService.Heartbeat:Connect(function()
        if not self.Enabled then return end
        
        if tick() - lastUpgradeTime > 5 then
            lastUpgradeTime = tick()
            self:AttemptUpgrade()
        end
        
        for npc, data in pairs(self.NPCs) do
            if npc and npc.Parent and npc:FindFirstChild("Humanoid") and npc:FindFirstChild("HumanoidRootPart") then
                if tick() - data.lastDecisionTime > 0.5 then
                    data.lastDecisionTime = tick()
                    self:MakeDecision(npc)
                end
            else
                self.NPCs[npc] = nil
            end
        end
    end)
    
    OrionLib:MakeNotification({
        Name = "System Initialized",
        Content = "NPC System with Auto-Upgrades has been initialized!",
        Time = 5
    })
    
    print("Ultimate NPC System with Auto-Upgrades initialized!")
end

-- Start the system
spawn(function()
    wait(2)
    NPCSystem:Init()
end)

-- Initialize Orion UI at the end
OrionLib:Init()
