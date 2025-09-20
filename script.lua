-- LocalScript in StarterPlayerScripts
-- Enhanced Dungeon Quest script with advanced enemy avoidance, pathfinding, and combat systems
-- Features: Intelligent pathfinding, dynamic dodging, spellcasting, anti-stuck mechanisms, and state management

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")
local backpack = player:WaitForChild("Backpack")
local camera = workspace.CurrentCamera

-- Configuration variables
local config = {
    TargetDistance = 16, -- Preferred distance from enemy
    CloseEnemyThreshold = 20, -- Distance to use spells
    PathComputeInterval = 0.2, -- How often to recompute path
    AttackCooldown = 0.1, -- Cooldown between attacks
    SpellCooldown = 1, -- Cooldown between spells
    StuckCheckInterval = 1, -- How often to check if stuck
    StuckThreshold = 1, -- Distance moved to consider stuck
    DodgeDistance = 50, -- Dodge velocity multiplier
    DodgeDuration = 0.2, -- How long dodge lasts
    RaycastDistance = 100, -- Distance for obstacle detection
    MaxEnemySearchDistance = 200, -- Maximum distance to search for enemies
    WaypointReachThreshold = 3, -- Distance to consider waypoint reached
    StateUpdateInterval = 0.1, -- How often to update AI state
    AggressionLevel = 0.8, -- 0-1, how aggressive the AI is
    CautionLevel = 0.5, -- 0-1, how cautious the AI is
}

-- AI state management
local aiState = {
    Targeting = false,
    CurrentTarget = nil,
    CurrentPath = nil,
    CurrentWaypoint = 1,
    LastStateChange = tick(),
    Mode = "Patrol", -- Modes: Patrol, Combat, Flee, Rest
    Behavior = "Balanced" -- Behaviors: Aggressive, Defensive, Balanced
}

-- Performance optimization
local performance = {
    LastCleanup = tick(),
    CleanupInterval = 10, -- Seconds between cleanups
    MaxPathAttempts = 3,
    CurrentPathAttempts = 0,
    LastRaycast = tick(),
    RaycastInterval = 0.1,
}

-- Create control objects
local bodyGyro = Instance.new("BodyGyro")
bodyGyro.MaxTorque = Vector3.new(0, 400000, 0)
bodyGyro.P = 5000
bodyGyro.D = 500
bodyGyro.Parent = root

local bodyVelocity = Instance.new("BodyVelocity")
bodyVelocity.MaxForce = Vector3.new(4000, 4000, 4000)
bodyVelocity.Velocity = Vector3.new(0, 0, 0)
bodyVelocity.Parent = root

-- Create UI elements for debugging
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AIDebugUI"
screenGui.Parent = player.PlayerGui

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0, 200, 0, 30)
statusLabel.Position = UDim2.new(0, 10, 0, 10)
statusLabel.BackgroundTransparency = 0.5
statusLabel.Text = "State: Initializing"
statusLabel.Parent = screenGui

-- Enhanced enemy finding with multiple criteria
local function findBestEnemy()
    local enemies = CollectionService:GetTagged("Enemy")
    local bestEnemy = nil
    local bestScore = -math.huge
    
    for _, enemy in ipairs(enemies) do
        local enemyHumanoid = enemy:FindFirstChild("Humanoid")
        local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
        
        if enemyHumanoid and enemyRoot and enemyHumanoid.Health > 0 then
            -- Calculate distance
            local dist = (root.Position - enemyRoot.Position).Magnitude
            
            -- Only consider enemies within max distance
            if dist <= config.MaxEnemySearchDistance then
                -- Calculate score based on multiple factors
                local distanceScore = (config.MaxEnemySearchDistance - dist) / config.MaxEnemySearchDistance
                local healthScore = 1 - (enemyHumanoid.Health / enemyHumanoid.MaxHealth)
                local angleScore = 0
                
                -- Calculate angle between player's look direction and enemy
                local directionToEnemy = (enemyRoot.Position - root.Position).Unit
                local lookDirection = root.CFrame.LookVector
                local angle = math.acos(directionToEnemy:Dot(lookDirection))
                angleScore = 1 - (angle / math.pi) -- Normalize to 0-1
                
                -- Calculate threat level (enemies attacking or casting spells score higher)
                local threatScore = 0
                if enemy:FindFirstChild("Attacking") or enemy:FindFirstChild("Casting") then
                    threatScore = 0.5
                end
                
                -- Calculate final score with weights
                local totalScore = (distanceScore * 0.4) + (healthScore * 0.3) + 
                                  (angleScore * 0.2) + (threatScore * 0.1)
                
                if totalScore > bestScore then
                    bestScore = totalScore
                    bestEnemy = enemyRoot
                end
            end
        end
    end
    
    return bestEnemy, bestScore
end

-- Enhanced path creation with obstacle avoidance 
local function createPath(targetPos)
    local pathParams = {
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 4,
        CostCalculator = nil, -- Could implement custom cost based on enemy positions
    }
    
    local path = PathfindingService:CreatePath(pathParams)
    
    -- Try to compute path
    local success, errorMsg = pcall(function()
        path:ComputeAsync(root.Position, targetPos)
    end)
    
    if not success then
        warn("Path computation error: " .. errorMsg)
        return nil
    end
    
    if path.Status == Enum.PathStatus.Success then
        performance.CurrentPathAttempts = 0
        return path
    else
        performance.CurrentPathAttempts = performance.CurrentPathAttempts + 1
        warn("Path failure: " .. tostring(path.Status))
        
        -- If path fails multiple times, try a direct approach
        if performance.CurrentPathAttempts >= performance.MaxPathAttempts then
            performance.CurrentPathAttempts = 0
            return "direct"
        end
        
        return nil
    end
end

-- Enhanced waypoint following with obstacle detection
local function followPath(path)
    if path == "direct" then
        -- Direct movement fallback
        humanoid:MoveTo(aiState.CurrentTarget.Position)
        return true
    end
    
    if path and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        aiState.CurrentPath = waypoints
        aiState.CurrentWaypoint = 2 -- Start from second waypoint (first is current position)
        
        while aiState.CurrentWaypoint <= #waypoints and aiState.Targeting do
            local waypoint = waypoints[aiState.CurrentWaypoint]
            
            -- Move to waypoint
            humanoid:MoveTo(waypoint.Position)
            
            -- Handle jumps
            if waypoint.Action == Enum.PathWaypointAction.Jump then
                humanoid.Jump = true
            end
            
            -- Wait until reached or timeout
            local startTime = tick()
            local reached = false
            
            while tick() - startTime < 5 and not reached do -- 5 second timeout
                reached = (root.Position - waypoint.Position).Magnitude < config.WaypointReachThreshold
                task.wait(0.1)
            end
            
            -- Check for obstacles using raycasting 
            if tick() - performance.LastRaycast >= performance.RaycastInterval then
                local raycastParams = RaycastParams.new()
                raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                raycastParams.FilterDescendantsInstances = {character}
                raycastParams.IgnoreWater = true
                
                local direction = (waypoint.Position - root.Position).Unit
                local raycastResult = workspace:Raycast(root.Position, direction * config.RaycastDistance, raycastParams)
                
                if raycastResult and raycastResult.Instance then
                    -- If obstacle detected, try to avoid using cross product 
                    local normal = raycastResult.Normal
                    local avoidanceDirection = normal:Cross(Vector3.new(0, 1, 0)).Unit
                    
                    -- Move perpendicular to obstacle normal
                    humanoid:MoveTo(root.Position + avoidanceDirection * 5)
                    task.wait(0.2)
                end
                
                performance.LastRaycast = tick()
            end
            
            aiState.CurrentWaypoint = aiState.CurrentWaypoint + 1
        end
        
        return true
    end
    
    return false
end

-- Enhanced dodging system with multiple dodge types 
local function performDodge(dodgeType, direction)
    -- Different dodge types based on situation
    if dodgeType == "quick" then
        -- Quick sidestep
        bodyVelocity.Velocity = direction * config.DodgeDistance
        task.wait(config.DodgeDuration)
        bodyVelocity.Velocity = Vector3.new(0, 0, 0)
        
    elseif dodgeType == "roll" then
        -- Forward roll with animation (would require animation loading)
        bodyVelocity.Velocity = direction * (config.DodgeDistance * 1.5)
        task.wait(config.DodgeDuration * 1.5)
        bodyVelocity.Velocity = Vector3.new(0, 0, 0)
        
    elseif dodgeType == "jump" then
        -- Jump back
        humanoid.Jump = true
        bodyVelocity.Velocity = direction * (config.DodgeDistance * 0.7) + Vector3.new(0, 50, 0)
        task.wait(config.DodgeDuration * 0.7)
        bodyVelocity.Velocity = Vector3.new(0, 0, 0)
    end
end

-- Enhanced spell detection and prediction 
local function checkForSpellsAndDodge()
    local spells = CollectionService:GetTagged("Spell")
    local mostDangerousSpell = nil
    local highestDanger = 0
    
    for _, spell in ipairs(spells) do
        if spell:IsA("BasePart") then
            local spellPos = spell.Position
            local distToSpell = (root.Position - spellPos).Magnitude
            
            -- Calculate danger level (0-1)
            local danger = 0
            
            -- Check if spell is moving toward player
            local velocity = spell.AssemblyLinearVelocity
            if velocity.Magnitude > 0 then
                local directionToSpell = (spellPos - root.Position).Unit
                local movementSimilarity = velocity.Unit:Dot(directionToSpell)
                
                if movementSimilarity < -0.7 then -- Spell is moving toward player
                    danger = (1 - (distToSpell / 50)) * (1 + velocity.Magnitude / 50)
                end
                        else
                                                -- Stationary spell (like AoE)
                danger = (1 - (distToSpell / 25)) * 0.7
            end
            
            -- Track most dangerous spell
            if danger > highestDanger then
                highestDanger = danger
                mostDangerousSpell = spell
            end
        end
    end
    
    -- Dodge if danger is above threshold
    if mostDangerousSpell and highestDanger > 0.3 then
        local spellPos = mostDangerousSpell.Position
        local spellVel = mostDangerousSpell.AssemblyLinearVelocity
        
        -- Calculate dodge direction using cross product 
        local toSpell = (spellPos - root.Position).Unit
        local dodgeDirection = toSpell:Cross(Vector3.new(0, 1, 0)).Unit
        
        -- Randomize left/right dodge
        if math.random() > 0.5 then
            dodgeDirection = -dodgeDirection
        end
        
        -- Add upward component if spell is ground-based
        local dodgeType = "quick"
        if spellVel.Magnitude < 5 then -- Likely area effect
            dodgeType = "jump"
            dodgeDirection = dodgeDirection + Vector3.new(0, 0.5, 0)
        end
        
        performDodge(dodgeType, dodgeDirection)
        return true
    end
    
    return false
end

-- Enhanced spell casting system 
local function useSpells(dist, enemy)
    if dist > config.CloseEnemyThreshold then return end
    if tick() - lastSpellUseTime < config.SpellCooldown then return end
    
    local spells = backpack:GetChildren()
    local bestSpell = nil
    local bestScore = 0
    
    -- Select best spell for situation
    for _, spellTool in ipairs(spells) do
        if spellTool:IsA("Tool") then
            local spellScore = 0
            
            -- Score based on distance
            if spellTool.Name:match("Range") and dist > 10 then
                spellScore = spellScore + 0.7
            elseif spellTool.Name:match("Melee") and dist < 8 then
                spellScore = spellScore + 0.8
            elseif spellTool.Name:match("AoE") and dist < 15 then
                spellScore = spellScore + 0.9
            else
                spellScore = spellScore + 0.5 -- Default score
            end
            
            -- Prefer spells not on cooldown (would need cooldown tracking)
            
            if spellScore > bestScore then
                bestScore = spellScore
                bestSpell = spellTool
            end
        end
    end
    
    -- Cast best spell
    if bestSpell then
        local args = {
            {
                {["\t"] = bestSpell},
                "M"
            }
        }
        ReplicatedStorage:WaitForChild("dataRemoteEvent"):FireServer(unpack(args))
        lastSpellUseTime = tick()
        return true
    end
    
    return false
end

-- Enhanced attack system
local function useAttack()
    if tick() - lastAttackTime < config.AttackCooldown then return end
    
    local currentClock = os.clock()
    local sentAt = os.time() + (currentClock - math.floor(currentClock))
    
    local args = {
        {
            {
                animationIndex = 2,
                sentAt = sentAt
            },
            "\175"
        }
    }
    
    ReplicatedStorage:WaitForChild("dataRemoteEvent"):FireServer(unpack(args))
    lastAttackTime = tick()
end

-- State management functions
local function updateAIState(enemy, distance)
    -- Update state based on situation
    if enemy then
        if not aiState.Targeting or aiState.Mode ~= "Combat" then
            aiState.Mode = "Combat"
            aiState.LastStateChange = tick()
            statusLabel.Text = "State: Combat"
        end
        
        -- Adjust behavior based on health and situation
        if humanoid.Health < humanoid.MaxHealth * 0.3 then
            aiState.Behavior = "Defensive"
        elseif distance < 10 then
            aiState.Behavior = "Aggressive"
        else
            aiState.Behavior = "Balanced"
        end
    else
        if aiState.Mode ~= "Patrol" then
            aiState.Mode = "Patrol"
            aiState.LastStateChange = tick()
            statusLabel.Text = "State: Patrol"
        end
    end
end

local function getTargetPosition(enemyRoot, currentDist)
    local directionToEnemy = (enemyRoot.Position - root.Position).Unit
    local directionFromEnemy = -directionToEnemy
    
    -- Adjust position based on AI behavior
    if aiState.Behavior == "Defensive" then
        -- Keep more distance when defensive
        return enemyRoot.Position + directionFromEnemy * (config.TargetDistance + 5)
    elseif aiState.Behavior == "Aggressive" then
        -- Get closer when aggressive
        return enemyRoot.Position + directionFromEnemy * (config.TargetDistance - 3)
    else
        -- Balanced approach
        if currentDist < config.TargetDistance - 2 then
            return enemyRoot.Position + directionFromEnemy * config.TargetDistance
        elseif currentDist > config.TargetDistance + 2 then
            return enemyRoot.Position + directionFromEnemy * config.TargetDistance
        else
            -- Strafe around enemy
            local tangent = Vector3.new(directionToEnemy.Z, 0, -directionToEnemy.X).Unit
            return root.Position + tangent * 4
        end
    end
end

-- Anti-stuck system
local function handleStuck(targetPos)
    if tick() - lastStuckCheckTime >= config.StuckCheckInterval then
        local movedDist = (root.Position - lastPosition).Magnitude
        
        if movedDist < config.StuckThreshold then
            -- Try to jump over obstacle
            humanoid.Jump = true
            
            -- Try to move directly toward target briefly
            humanoid:MoveTo(targetPos)
            
            -- Inform user
            statusLabel.Text = "State: Stuck - Attempting recovery"
        end
        
        lastPosition = root.Position
        lastStuckCheckTime = tick()
    end
end

-- Cleanup function to prevent memory leaks
local function cleanup()
    if tick() - performance.LastCleanup > performance.CleanupInterval then
        -- Clean up old spells and effects
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA("BasePart") and (obj.Name:match("Effect") or obj.Name:match("Spell")) and 
               (root.Position - obj.Position).Magnitude > 100 then
                obj:Destroy()
            end
        end
        
        performance.LastCleanup = tick()
    end
end

-- Main loop
RunService.Heartbeat:Connect(function()
    -- Update debug UI
    statusLabel.Text = "State: " .. aiState.Mode .. " (" .. aiState.Behavior .. ")"
    
    -- Find best enemy
    local enemy, dist = findBestEnemy()
    aiState.CurrentTarget = enemy
    
    -- Update AI state
    updateAIState(enemy, dist)
    
    if enemy then
        aiState.Targeting = true
        
        -- Face enemy
        bodyGyro.CFrame = CFrame.new(root.Position, Vector3.new(enemy.Position.X, root.Position.Y, enemy.Position.Z))
        
        -- Check for spells and dodge if necessary
        local dodged = checkForSpellsAndDodge()
        
        -- Calculate target position
        local targetPos = getTargetPosition(enemy, dist)
        
        -- Recompute path if needed
        if tick() - lastPathComputeTime >= config.PathComputeInterval then
            local path = createPath(targetPos)
            if path then
                followPath(path)
            end
            lastPathComputeTime = tick()
        end
        
        -- Handle stuck detection
        handleStuck(targetPos)
        
        -- Use abilities
        useSpells(dist, enemy)
        useAttack()
    else
        aiState.Targeting = false
        
        -- Patrol behavior
        if aiState.Mode == "Patrol" then
            -- Simple patrol pattern (could be enhanced with waypoints)
            local patrolCenter = Vector3.new(0, 0, 0) -- Would need actual patrol center
            local patrolPoint = patrolCenter + Vector3.new(
                math.sin(tick()) * 20,
                0,
                math.cos(tick()) * 20
            )
            
            humanoid:MoveTo(patrolPoint)
        end
    end
    
    -- Perform cleanup
    cleanup()
end)

-- Character reinitialization
player.CharacterAdded:Connect(function(newChar)
    character = newChar
    humanoid = character:WaitForChild("Humanoid")
    root = character:WaitForChild("HumanoidRootPart")
    
    -- Recreate control objects
    if bodyGyro then bodyGyro:Destroy() end
    if bodyVelocity then bodyVelocity:Destroy() end
    
    bodyGyro = Instance.new("BodyGyro")
    bodyGyro.MaxTorque = Vector3.new(0, 400000, 0)
    bodyGyro.P = 5000
    bodyGyro.D = 500
    bodyGyro.Parent = root
    
    bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.MaxForce = Vector3.new(4000, 4000, 4000)
    bodyVelocity.Velocity = Vector3.new(0, 0, 0)
    bodyVelocity.Parent = root
end)

-- Tag new spells and projectiles
workspace.ChildAdded:Connect(function(child)
    if child:IsA("BasePart") and (child.Name:match("Attack") or child.Name:match("Spell") or 
       child.Name:match("Line") or child.Name:match("Projectile")) then
        CollectionService:AddTag(child, "Spell")
        
        -- Auto-remove old spells
        Debris:AddItem(child, 10)
    end
end)

-- Toggle AI with F key
UserInputService.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.F then
        aiState.Targeting = not aiState.Targeting
        statusLabel.Text = "AI " .. (aiState.Targeting and "Enabled" or "Disabled")
    end
end)

-- Additional systems for expansion

-- Health monitoring system
local function monitorHealth()
    humanoid.HealthChanged:Connect(function()
        if humanoid.Health < humanoid.MaxHealth * 0.2 then
            -- Emergency behavior when health is critical
            aiState.Mode = "Flee"
            statusLabel.Text = "State: Flee (Low Health)"
        end
    end)
end

-- Enemy attack prediction
local function predictEnemyAttack(enemy)
    -- Placeholder for enemy attack prediction system
    -- Would analyze enemy animations and telegraphed attacks
    return false, Vector3.new(0, 0, 0)
end

-- Environmental interaction system
local function checkEnvironment()
    -- Check for traps, obstacles, and interactive elements
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {character}
    
    local results = {}
    
    -- Cast rays in multiple directions to detect environment
    for i = 0, 3 do
        local angle = math.rad(i * 90)
        local direction = Vector3.new(math.sin(angle), -0.5, math.cos(angle))
        local result = workspace:Raycast(root.Position, direction * 10, raycastParams)
        
        if result then
            table.insert(results, {
                Position = result.Position,
                Normal = result.Normal,
                Instance = result.Instance
            })
        end
    end
    
    return results
end

-- Advanced combat maneuvers
local function executeCombatManeuver(maneuverType, target)
    if maneuverType == "flank" then
        -- Attempt to flank the target
        local toTarget = (target.Position - root.Position).Unit
        local flankDirection = Vector3.new(toTarget.Z, 0, -toTarget.X).Unit
        
        if math.random() > 0.5 then
            flankDirection = -flankDirection
        end
        
        local flankPosition = target.Position + flankDirection * 8
        local path = createPath(flankPosition)
        
        if path then
            followPath(path)
        end
    elseif maneuverType == "retreat" then
        -- Retreat to a safer position
        local fromTarget = (root.Position - target.Position).Unit
        local retreatPosition = root.Position + fromTarget * 15
        
        humanoid:MoveTo(retreatPosition)
    end
end

-- Initialize systems
monitorHealth()
statusLabel.Text = "AI System Initialized"

print("Dungeon Quest AI Script Loaded Successfully")
print("Features: Pathfinding, Enemy Avoidance, Combat, Spellcasting, Dodging")
print("Press F to toggle AI behavior")
