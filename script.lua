-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Get local player
local localPlayer = Players.LocalPlayer

-- Load Orion Library
local success, OrionLib = pcall(function()
    return loadstring(game:HttpGet('https://raw.githubusercontent.com/shlexware/Orion/main/source'))()
end)

if not success or not OrionLib then
    warn("Failed to load Orion Library!")
    return
end

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

-- Wait for player to load
localPlayer:WaitForChild("PlayerGui")

-- Create Orion UI
local Window = OrionLib:MakeWindow({
    Name = "NPC System",
    HidePremium = false,
    SaveConfig = false,
    IntroEnabled = false,
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
    Callback = function(Value)
        NPCSystem.XPCollection = Value
    end
})

MainTab:AddToggle({
    Name = "Boss Handling",
    Default = NPCSystem.BossHandling,
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
    Callback = function(Value)
        NPCSystem.AutoUpgradeEnabled = Value
    end
})

-- Create dropdown for upgrade priority
UpgradeTab:AddDropdown({
    Name = "Upgrade Priority",
    Default = NPCSystem.UpgradePriority[1],
    Options = NPCSystem.UpgradePriority,
    Callback = function(Value)
        for i, upgrade in ipairs(NPCSystem.UpgradePriority) do
            if upgrade == Value then
                table.remove(NPCSystem.UpgradePriority, i)
                table.insert(NPCSystem.UpgradePriority, 1, Value)
                break
            end
        end
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
    Callback = function(Value)
        NPCSystem.BossTeleportHeight = Value
    end
})

BossTab:AddToggle({
    Name = "Focus Bosses First",
    Default = NPCSystem.FocusBossesFirst,
    Callback = function(Value)
        NPCSystem.FocusBossesFirst = Value
    end
})
