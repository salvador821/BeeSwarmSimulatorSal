-- Load Orion Library
local OrionLib = loadstring(game:HttpGet('https://raw.githubusercontent.com/shlexware/Orion/main/source'))()

-- Create Orion Window
local Window = OrionLib:MakeWindow({
    Name = "Speed Control",
    HidePremium = false,
    SaveConfig = false,
    IntroEnabled = true,
    IntroText = "WalkSpeed Controller"
})

-- Create a tab
local Tab = Window:MakeTab({
    Name = "Main",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

-- Show notification when UI loads
OrionLib:MakeNotification({
    Name = "UI Loaded!",
    Content = "WalkSpeed controller is ready to use.",
    Image = "rbxassetid://4483345998",
    Time = 5
})

-- Add button to change walkspeed
Tab:AddButton({
    Name = "Set WalkSpeed to 60",
    Callback = function()
        -- Get player character
        local player = game.Players.LocalPlayer
        if player.Character then
            local humanoid = player.Character:FindFirstChild("Humanoid")
            if humanoid then
                humanoid.WalkSpeed = 60
                OrionLib:MakeNotification({
                    Name = "Success!",
                    Content = "Your WalkSpeed has been set to 60.",
                    Time = 3
                })
            else
                OrionLib:MakeNotification({
                    Name = "Error",
                    Content = "No Humanoid found in your character.",
                    Time = 3
                })
            end
        else
            OrionLib:MakeNotification({
                Name = "Error",
                Content = "No character found. Please wait for your character to load.",
                Time = 3
            })
        end
    end    
})

-- Add a label for instructions
Tab:AddLabel("Click the button to set your WalkSpeed to 60")

-- Initialize Orion UI
OrionLib:Init()
