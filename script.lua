-- Advanced Combat Script Part 1/3
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")
local backpack = player:WaitForChild("Backpack")

local bodyGyro = Instance.new("BodyGyro")
bodyGyro.Name = "CombatLockGyro"
bodyGyro.MaxTorque = Vector3.new(0, 400000, 0)
bodyGyro.P = 15000
bodyGyro.D = 1200
bodyGyro.Parent = root

local isTargeting = false
local lastSpellUseTime = 0
local spellUseCooldown = 1
local lastAttackTime = 0
local attackCooldown = 0.1
local lastPosition = root.Position
local stuckCheckInterval = 1
local lastStuckCheckTime = 0
local stuckThreshold = 1
local closeEnemyThreshold = 20
local optimalCombatDistance = 16
local dodgeDistance = 15
local pathUpdateInterval = 0.5
local lastPathUpdate = 0
local currentPath = nil
local currentWaypointIndex = 1
local dodgeCooldown = 0.5
local lastDodgeTime = 0
local isDodging = false
local dodgeDuration = 0.3
local dodgeStartTime = 0
local dodgeDirection = Vector3.new()
local spellDetectionRange = 50
local enemyDetectionRange = 100
local pathfindingAttempts = 0
local maxPathfindingAttempts = 3
local recentSpells = {}
local spellMemoryDuration = 5

local pathParams = {
    AgentRadius = 3,
    AgentHeight = 6,
    AgentCanJump = true,
    AgentCanClimb = true,
    AgentCanSwim = false,
    WaypointSpacing = 4,
    Costs = {
        Water = 100,
        Lava = math.huge,
        Neon = 50,
        Grass = 10,
        Ground = 5,
    }
}

local function findNearestEnemy()
    local enemies = CollectionService:GetTagged("Enemy")
    local nearest = nil
    local minDist = math.huge
    
    for _, enemy in ipairs(enemies) do
        local enemyHumanoid = enemy:FindFirstChild("Humanoid")
        local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
        if enemyHumanoid and enemyRoot and enemyHumanoid.Health > 0 then
            local dist = (root.Position - enemyRoot.Position).Magnitude
            if dist < enemyDetectionRange and dist < minDist then
                minDist = dist
                nearest = enemyRoot
            end
        end
    end
    
    return nearest, minDist
end

local function getTargetPosition(enemyRoot, currentDist)
    local directionToEnemy = (enemyRoot.Position - root.Position).Unit
    local directionFromEnemy = -directionToEnemy

    if currentDist < optimalCombatDistance - 2 then
        local randomOffset = Vector3.new(
            math.random() * 2 - 1,
            0,
            math.random() * 2 - 1
        ).Unit * 0.5
        return enemyRoot.Position + (directionFromEnemy + randomOffset) * optimalCombatDistance
    elseif currentDist > optimalCombatDistance + 2 then
        local tangent = Vector3.new(directionToEnemy.Z, 0, -directionToEnemy.X).Unit
        local tacticalOffset = tangent * (math.random() * 4 - 2)
        return enemyRoot.Position + (directionFromEnemy * optimalCombatDistance) + tacticalOffset
    else
        local tangent = Vector3.new(directionToEnemy.Z, 0, -directionToEnemy.X).Unit
        local circleDirection = math.random() > 0.5 and tangent or -tangent
        return root.Position + circleDirection * 3
    end
end

local function checkForSpellsAndDodge()
    if isDodging then
        local dodgeProgress = (tick() - dodgeStartTime) / dodgeDuration
        if dodgeProgress < 1 then
            local dodgeVector = dodgeDirection * dodgeDistance * (1 - dodgeProgress)
            humanoid:MoveTo(root.Position + dodgeVector)
            return nil
        else
            isDodging = false
        end
    end
    
    if tick() - lastDodgeTime < dodgeCooldown then
        return nil
    end
    
    local spells = CollectionService:GetTagged("Spell")
    local mostDangerousSpell = nil
    local highestDangerScore = 0
    
    local currentTime = tick()
    for spellId, time in pairs(recentSpells) do
        if currentTime - time > spellMemoryDuration then
            recentSpells[spellId] = nil
        end
    end
    
    for _, spell in ipairs(spells) do
        local spellId = tostring(spell:GetDebugId())
        if recentSpells[spellId] then
            continue
        end
        
        if spell:IsA("BasePart") then
            local spellPos = spell.Position
            local distToSpell = (root.Position - spellPos).Magnitude
            
            if distToSpell < spellDetectionRange then
                local velocity = spell.Velocity
                local linearVel = spell:FindFirstChildOfClass("LinearVelocity")
                local bodyVel = spell:FindFirstChildOfClass("BodyVelocity")
                
                if linearVel then
                    velocity = linearVel.VectorVelocity or linearVel.Velocity
                elseif bodyVel then
                    velocity = bodyVel.Velocity
                end
                
                velocity = velocity or Vector3.new()
                
                local relativePos = root.Position - spellPos
                local relativeVel = velocity
                local relativeSpeed = relativeVel.Magnitude
                
                local dangerScore = 0
                local timeToImpact = math.huge
                
                if relativeSpeed > 0 then
                    timeToImpact = distToSpell / relativeSpeed
                    local futureSpellPos = spellPos + velocity * timeToImpact
                    local futureDist = (futureSpellPos - root.Position).Magnitude
                    dangerScore = (1 / math.max(0.1, distToSpell)) * (relativeSpeed / 10)
                    
                    if futureDist < 10 then
                        dangerScore = dangerScore * 2
                    end
                else
                    dangerScore = 1 / math.max(0.1, distToSpell)
                    timeToImpact = distToSpell / 10
                end
                
                if dangerScore > highestDangerScore and timeToImpact < 2 then
                    highestDangerScore = dangerScore
                    mostDangerousSpell = spell
                end
            end
        end
    end
    
    if mostDangerousSpell and highestDangerScore > 0.5 then
        local spellPos = mostDangerousSpell.Position
        local spellVel = mostDangerousSpell.Velocity
        
        local toSpell = (spellPos - root.Position).Unit
        local dodgeDir
        
        if spellVel.Magnitude > 0 then
            local perp = spellVel:Cross(Vector3.new(0, 1, 0)).Unit
            dodgeDir = (math.random() > 0.5) and perp or -perp
        else
            dodgeDir = -(spellPos - root.Position).Unit
        end
        
        dodgeDir = (dodgeDir + Vector3.new(0, 0.3, 0)).Unit
        
        recentSpells[tostring(mostDangerousSpell:GetDebugId())] = tick()
        
        isDodging = true
        dodgeStartTime = tick()
        dodgeDirection = dodgeDir
        lastDodgeTime = tick()
        
        humanoid.Jump = true
        
        return root.Position + dodgeDir * dodgeDistance
    end
    
    return nil
end

local function useSpells(dist)
    if dist > closeEnemyThreshold then return end
    if tick() - lastSpellUseTime < spellUseCooldown then return end
    
    local spells = backpack:GetChildren()
    for _, spellTool in ipairs(spells) do
        if spellTool:IsA("Tool") then
            local args = {
                {
                    {["\t"] = spellTool},
                    "M"
                }
            }
            
            local success, err = pcall(function()
                ReplicatedStorage:WaitForChild("dataRemoteEvent"):FireServer(unpack(args))
            end)
            
            if not success then
                warn("Spell casting error: " .. tostring(err))
            end
        end
    end
    lastSpellUseTime = tick()
end
-- Advanced Combat Script Part 2/3
local function useAttack()
    if tick() - lastAttackTime < attackCooldown then return end
    
    local currentTick = tick()
    local sentAt = os.time() + (currentTick - math.floor(currentTick))
    
    local args = {
        {
            {
                animationIndex = 2,
                sentAt = sentAt
            },
            "\175"
        }
    }
    
    local success, err = pcall(function()
        ReplicatedStorage:WaitForChild("dataRemoteEvent"):FireServer(unpack(args))
    end)
    
    if not success then
        warn("Attack error: " .. tostring(err))
    else
        lastAttackTime = tick()
    end
end

local function navigateToPosition(targetPos)
    if currentPath and tick() - lastPathUpdate < pathUpdateInterval then
        if currentWaypointIndex <= #currentPath then
            local nextWaypoint = currentPath[currentWaypointIndex]
            humanoid:MoveTo(nextWaypoint.Position)
            
            if (root.Position - nextWaypoint.Position).Magnitude < 4 then
                currentWaypointIndex = currentWaypointIndex + 1
            end
            
            if nextWaypoint.Action == Enum.PathWaypointAction.Jump then
                humanoid.Jump = true
            end
            
            return true
        end
    end
    
    pathfindingAttempts = pathfindingAttempts + 1
    
    if pathfindingAttempts > maxPathfindingAttempts then
        humanoid:MoveTo(targetPos)
        pathfindingAttempts = 0
        return false
    end
    
    local success, path = pcall(function()
        return PathfindingService:CreatePath(pathParams)
    end)
    
    if not success or not path then
        humanoid:MoveTo(targetPos)
        return false
    end
    
    local computeSuccess = pcall(function()
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
