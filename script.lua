-- LocalScript in StarterPlayerScripts
-- This script makes the player's character pathfind to a position ~7 studs from the nearest enemy (approaches if far, maintains if close),
-- face the enemy (like shift lock), dodge spells/attacks, auto-use all spells in Backpack, and auto-attack every 0.1s.
-- Pathfinding: Computes every heartbeat for responsiveness, fallback to direct MoveTo for edges/drops/stuck situations.
-- Dodging: Detects moving projectiles and static line attacks; dodges perpendicular if close/aligned.
-- Spells: Fires remote for all tools in Backpack simultaneously when targeting, with 1s cooldown (adjustable).
-- Auto-Attack: Fires specific attack remote every 0.1s when targeting.
-- Assumptions:
-- - Enemies are character models tagged with "Enemy" (use CollectionService to tag them).
-- - Enemies have a Humanoid for health checking.
-- - Attacks/Spells are parts with names matching "Attack" or "Spell", with Velocity, LinearVelocity, or BodyVelocity.
-- - For line attacks: Dodges if player is aligned and within 10 studs.
-- - Improved anti-stuck: If no movement progress, fallback to direct MoveTo more often.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")
local backpack = player:WaitForChild("Backpack")

-- Create BodyGyro for facing
local bodyGyro = Instance.new("BodyGyro")
bodyGyro.MaxTorque = Vector3.new(0, 400000, 0)
bodyGyro.P = 3000
bodyGyro.D = 500
bodyGyro.Parent = root

-- Variables
local isTargeting = false
local lastSpellUseTime = 0
local spellUseCooldown = 1  -- Cooldown for spells (adjust as needed)
local lastAttackTime = 0
local attackCooldown = 0.1  -- Auto-attack every 0.1s
local lastPosition = root.Position
local stuckCheckInterval = 1  -- Check if stuck every 1s
local lastStuckCheckTime = 0
local stuckThreshold = 1  -- If moved less than 1 stud in interval, consider stuck

-- Function to find nearest living enemy
local function findNearestEnemy()
    local enemies = CollectionService:GetTagged("Enemy")
    local nearest = nil
    local minDist = math.huge
    for _, enemy in ipairs(enemies) do
        local enemyHumanoid = enemy:FindFirstChild("Humanoid")
        local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
        if enemyHumanoid and enemyRoot and enemyHumanoid.Health > 0 then
            local dist = (root.Position - enemyRoot.Position).Magnitude
            if dist < minDist then
                minDist = dist
                nearest = enemyRoot
            end
        end
    end
    return nearest, minDist
end

-- Function to compute target position ~7 studs from enemy
local function getTargetPosition(enemyRoot, currentDist)
    local directionToEnemy = (enemyRoot.Position - root.Position).Unit
    local directionFromEnemy = -directionToEnemy

    if currentDist < 6 then
        -- Too close: move away to ~8 studs
        return enemyRoot.Position + directionFromEnemy * 8
    elseif currentDist > 8 then
        -- Too far: move to a point 7 studs from enemy along the line
        return enemyRoot.Position + directionFromEnemy * 7
    else
        -- At ~7 studs: circle around
        local tangent = Vector3.new(directionToEnemy.Z, 0, -directionToEnemy.X).Unit  -- Perpendicular in XZ plane
        return root.Position + tangent * 2  -- Move sideways to circle
    end
end

-- Function to check for incoming attacks/spells and dodge
local function checkForSpellsAndDodge()
    local spells = CollectionService:GetTagged("Spell")
    for _, spell in ipairs(spells) do
        if spell:IsA("BasePart") then
            local spellPos = spell.Position
            local distToSpell = (root.Position - spellPos).Magnitude
            if distToSpell < 30 then  -- Increased range for better detection
                -- Get velocity from various sources
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
                local isIncoming = false
                
                if velocity.Magnitude > 0 then
                    -- Moving projectile
                    if relativePos:Dot(velocity.Unit) > 0.5 then  -- Loosened threshold
                        isIncoming = true
                    end
                else
                    -- Static/line attack: check if player is close and in line
                    local spellSize = spell.Size
                    local spellOrientation = spell.CFrame.LookVector
                    if (spellSize.X > spellSize.Z * 2 or spellSize.Z > spellSize.X * 2 or spellSize.Y > spellSize.X * 2) then  -- Long in any dimension
                        local dirToSpell = relativePos.Unit
                        local proj = dirToSpell:Dot(spellOrientation)
                        if math.abs(proj) > 0.7 and distToSpell < 15 then  -- Loosened alignment, increased distance
                            isIncoming = true
                        end
                    end
                end
                
                if isIncoming then
                    -- Dodge sideways
                    local refVector = (velocity.Magnitude > 0 and velocity or relativePos)
                    local perpDir = refVector:Cross(Vector3.new(0,1,0)).Unit
                    local dodgePos = root.Position + perpDir * 7  -- Increased dodge distance
                    return dodgePos
                end
            end
        end
    end
    return nil
end

-- Function to use all spells via remote (fires all at once)
local function useSpells()
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
            ReplicatedStorage:WaitForChild("dataRemoteEvent"):FireServer(unpack(args))
        end
    end
    lastSpellUseTime = tick()
end

-- Function for auto-attack
local function useAttack()
    if tick() - lastAttackTime < attackCooldown then return end
    
    local args = {
        {
            {
                animationIndex = 2,
                sentAt = tick()  -- Use current tick() for sentAt
            },
            "\175"
        }
    }
    ReplicatedStorage:WaitForChild("dataRemoteEvent"):FireServer(unpack(args))
    lastAttackTime = tick()
end

-- Main loop
RunService.Heartbeat:Connect(function()
    local enemyRoot, dist = findNearestEnemy()
    if enemyRoot then
        isTargeting = true
        -- Face the enemy
        bodyGyro.CFrame = CFrame.new(root.Position, Vector3.new(enemyRoot.Position.X, root.Position.Y, enemyRoot.Position.Z))  -- Face, ignore Y

        -- Check for dodge first
        local dodgePos = checkForSpellsAndDodge()
        local targetPos = dodgePos or getTargetPosition(enemyRoot, dist)

        -- Pathfinding every frame
        local path = PathfindingService:CreatePath({
            AgentRadius = 3,  -- Increased radius to avoid tight walls
            AgentHeight = 5,
            AgentCanJump = true,
            AgentCanClimb = true
        })
        path:ComputeAsync(root.Position, targetPos)
        if path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            if #waypoints > 1 then
                local nextWaypoint = waypoints[2]
                humanoid:MoveTo(nextWaypoint.Position)
                if nextWaypoint.Action == Enum.PathWaypointAction.Jump then
                    humanoid.Jump = true
                end
            end
        else
            -- Fallback: direct MoveTo
            humanoid:MoveTo(targetPos)
        end
        
        -- Check if stuck
        if tick() - lastStuckCheckTime >= stuckCheckInterval then
            local movedDist = (root.Position - lastPosition).Magnitude
            if movedDist < stuckThreshold then
                -- Stuck: force direct move and jump
                humanoid:MoveTo(targetPos)
                humanoid.Jump = true
            end
            lastPosition = root.Position
            lastStuckCheckTime = tick()
        end
        
        -- Use spells and attack when targeting
        useSpells()
        useAttack()
    else
        isTargeting = false
        -- No living enemies: stop moving
        humanoid:MoveTo(root.Position)
        bodyGyro.CFrame = root.CFrame
    end
end)

-- Handle character respawn
player.CharacterAdded:Connect(function(newChar)
    character = newChar
    humanoid = character:WaitForChild("Humanoid")
    root = character:WaitForChild("HumanoidRootPart")
    bodyGyro.Parent = root
end)

-- Monitor for new attacks
workspace.ChildAdded:Connect(function(child)
    if child:IsA("BasePart") and (child.Name:match("Attack") or child.Name:match("Spell")) then
        CollectionService:AddTag(child, "Spell")
    end
end)
