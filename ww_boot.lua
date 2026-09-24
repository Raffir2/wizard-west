-- used by the PC watchdog after a Roblox restart: load the farm script and start farming
repeat task.wait(1) until game:IsLoaded() and game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character.PrimaryPart
local W = loadstring(readfile("ww_script.lua"))()
W.cfg.bossFarm = true
print("booted", game.JobId)
