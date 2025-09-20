ction()
        path:ComputeAsync(root.Position, targetPos)
    end)
    
    if not computeSuccess or path.Status ~= Enum.PathStatus.Success then
        humanoid:MoveTo(targetPos)
        return false
    end
    
    currentPath = path:GetWaypoints()
    currentWaypointIndex = 2
    lastPathUpdate = tick()
    pathfindingAttempts = 0
    
    return true
end

local function checkForStuck()
    if tick() - lastStuckCheckTime < stuckCheckInterval then
        return false
    end
    
    local movedDist = (root.Position - lastPosition).Magnitude
    local isMoving = humanoid.MoveDirection.Magnitude > 0.1
    
    if movedDist < stuckThreshold and isMoving then
        humanoid.Jump = true
        
        local randomDir = Vector3.new(
            math.random() * 2 - 1,
            0,
            math.random() * 2 - 1
        ).Unit
        
        humanoid:MoveTo(root.Position + randomDir * 5)
        
        currentPath = nil
        pathfindingAttempts = 0
        
        return true
    end
    
    lastPosition = root.Position
    lastStuckCheckTime = tick()
    return false
end

player.CharacterAdded:Connect(function(newChar)
    character = newChar
    humanoid = character:WaitForChild("Humanoid")
    root = character:WaitForChild("HumanoidRootPart")
    
    if bodyGyro then bodyGyro:Destroy() end
    bodyGyro = Instance.new("BodyGyro")
    bodyGyro.Name = "CombatLockGyro"
    bodyGyro.MaxTorque = Vector3.new(0, 400000, 0)
    bodyGyro.P = 15000
    bodyGyro.D = 1200
    bodyGyro.Parent = root
    
    isTargeting = false
    isDodging = false
    currentPath = nil
    pathfindingAttempts = 0
end)

workspace.ChildAdded:Connect(function(child)
    if child:IsA("BasePart") then
        local isSpell = false
        
        if child.Name:match("Attack") or child.Name:match("Spell") or 
           child.Name:match("Projectile") or child.Name:match("Missile") or
           child.Name:match("Bullet") or child.Name:match("Orb") or
           child.Name:match("Ball") or child.Name:match("Beam") then
            isSpell = true
        end
        
        if child:FindFirstChildOfClass("ParticleEmitter") or
           child:FindFirstChildOfClass("Trail") or
           child:FindFirstChildOfClass("Beam") then
            isSpell = true
        end
        
        if child.Velocity.Magnitude > 20 then
            isSpell = true
        end
        
        if isSpell and not CollectionService:HasTag(child, "Spell") then
            CollectionService:AddTag(child, "Spell")
            
            delay(10, function()
                if child.Parent then
                    CollectionService:RemoveTag(child, "Spell")
                end
            end)
        end
    end
end)

local function combatLoop()
    local enemyRoot, dist = findNearestEnemy()
    
    if enemyRoot and dist < enemyDetectionRange then
        isTargeting = true
        
        bodyGyro.CFrame = CFrame.new(root.Position, Vector3.new(
            enemyRoot.Position.X, 
            root.Position.Y,
            enemyRoot.Position.Z
        ))
        
        local dodgePos = checkForSpellsAndDodge()
        
        local targetPos
        if dodgePos then
            targetPos = dodgePos
        else
            targetPos = getTargetPosition(enemyRoot, dist)
        end
        
        if not isDodging then
            navigateToPosition(targetPos)
        end
        
        if tick() % 0.5 < 0.1 then
            checkForStuck()
        end
        
        useSpells(dist)
        useAttack()
    else
        isTargeting = false
        humanoid:MoveTo(root.Position)
        bodyGyro.CFrame = root.CFrame
        currentPath = nil
    end
end

local lastCombatUpdate = 0
local combatUpdateInterval = 0.05

RunService.Heartbeat:Connect(function(deltaTime)
    lastCombatUpdate = lastCombatUpdate + deltaTime
    
    if lastCombatUpdate >= combatUpdateInterval then
        combatLoop()
        lastCombatUpdate = 0
    end
end)
-- Advanced Combat Script Part 3/3
local currentEnemy = nil
local enemyTrackingTime = 0
local maxTrackingTime = 3

local function updateEnemyTracking(enemyRoot)
    if enemyRoot then
        currentEnemy = enemyRoot
        enemyTrackingTime = tick()
    elseif currentEnemy and tick() - enemyTrackingTime < maxTrackingTime then
        return currentEnemy, (root.Position - currentEnemy.Position).Magnitude
    else
        currentEnemy = nil
    end
    
    return enemyRoot, (enemyRoot and (root.Position - enemyRoot.Position).Magnitude or math.huge)
end

local function checkHealthStatus()
    if humanoid.Health < humanoid.MaxHealth * 0.3 then
        isTargeting = false
        
        local enemyRoot = findNearestEnemy()
        if enemyRoot then
            local fleeDirection = (root.Position - enemyRoot.Position).Unit
            humanoid:MoveTo(root.Position + fleeDirection * 20)
        end
        
        return true
    end
    
    return false
end

local function adjustCombatStyle()
    if humanoid.Health < humanoid.MaxHealth * 0.5 then
        optimalCombatDistance = 20
        spellUseCooldown = 1.5
    else
        optimalCombatDistance = 16
        spellUseCooldown = 1
    end
end

RunService.Heartbeat:Connect(function(deltaTime)
    if checkHealthStatus() then
        return
    end
    
    adjustCombatStyle()
    
    local enemyRoot, dist = findNearestEnemy()
    enemyRoot, dist = updateEnemyTracking(enemyRoot)
    
    if enemyRoot and dist < enemyDetectionRange then
        isTargeting = true
        
        bodyGyro.CFrame = CFrame.new(root.Position, Vector3.new(
            enemyRoot.Position.X, 
            root.Position.Y, 
            enemyRoot.Position.Z
        ))
        
        local dodgePos = checkForSpellsAndDodge()
        
        local targetPos = dodgePos or getTargetPosition(enemyRoot, dist)
        
        if not isDodging then
            navigateToPosition(targetPos)
        end
        
        if tick() - lastStuckCheckTime >= stuckCheckInterval then
            checkForStuck()
        end
        
        useSpells(dist)
        useAttack()
    else
        isTargeting = false
        humanoid:MoveTo(root.Position)
        bodyGyro.CFrame = root.CFrame
        currentPath = nil
    end
end)

local function displayStatus()
    print("=== Combat AI Status ===")
    print("Targeting: " .. tostring(isTargeting))
    print("Dodging: " .. tostring(isDodging))
    print("Health: " .. humanoid.Health .. "/" .. humanoid.MaxHealth)
    
    if currentPath then
        print("Path waypoints: " .. #currentPath)
        print("Current waypoint: " .. currentWaypointIndex)
    else
        print("No active path")
    end
    
    local enemy = findNearestEnemy()
    if enemy then
        print("Nearest enemy: " .. enemy.Parent.Name)
        print("Distance: " .. (root.Position - enemy.Position).Magnitude)
    else
        print("No enemies detected")
    end
end

local function handleChatMessage(message)
    if message == "/status" then
        displayStatus()
    elseif message == "/reset" then
        currentPath = nil
        isTargeting = false
        isDodging = false
        print("Combat AI reset")
    end
end

player.Chatted:Connect(handleChatMessage)

print("Advanced Combat AI initialized")
