-- Load Orion Library
local OrionLib = loadstring(game:HttpGet('https://raw.githubusercontent.com/shlexware/Orion/main/source'))()

-- Create Orion Window
local Window = OrionLib:MakeWindow({
    Name = "Speed Control",
    HidePremium = false,
    SaveConfig = false,
    IntroEnabled = false
})

-- Create button to change walkspeed
Window:AddButton({
    Name = "Set WalkSpeed to 60",
    Callback = function()
        -- Fire remote event to change walkspeed on server
        game.ReplicatedStorage.ChangeWalkSpeed:FireServer(60)
        OrionLib:MakeNotification({
            Name = "Speed Changed",
            Content = "WalkSpeed set to 60!",
            Time = 3
        })
    end
})

-- Initialize Orion UI
OrionLib:Init()
