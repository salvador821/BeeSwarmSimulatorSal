-- Load Rayfield Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Create Window
local Window = Rayfield:CreateWindow({
   Name = "Speed Control",
   LoadingTitle = "WalkSpeed Controller",
   LoadingSubtitle = "Ready to use",
   ConfigurationSaving = {
      Enabled = false,
   },
   Discord = {
      Enabled = false,
   }
})

-- Create Tab
local MainTab = Window:CreateTab("Main", 4483361688)

-- Create Button Section
local ButtonSection = MainTab:CreateSection("WalkSpeed Controls")

-- Create the button
MainTab:CreateButton({
   Name = "Set WalkSpeed to 60",
   Callback = function()
      local player = game.Players.LocalPlayer
      local character = player.Character or player.CharacterAdded:Wait()
      local humanoid = character:WaitForChild("Humanoid")
      
      humanoid.WalkSpeed = 60
      
      Rayfield:Notify({
         Title = "Success!",
         Content = "WalkSpeed set to 60",
         Duration = 3,
         Image = 4483361688
      })
   end,
})

-- Load the UI
Rayfield:LoadConfiguration()
