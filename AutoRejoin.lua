--[[
	AUTO REJOIN
	Detects the Roblox disconnect / kick window (error prompt) and rejoins automatically.
	If the internet is still down, it keeps retrying with a growing delay until it works.

	Needs an environment that can read CoreGui (most executors). Run it with
	loadstring(game:HttpGet("YOUR_RAW_URL"))()

	To keep it running after each rejoin, upload this file to GitHub and paste its
	raw link into CONFIG.ScriptUrl below.
]]

local CONFIG = {
	ScriptUrl = "", -- raw link to THIS script (optional, re-runs it after every rejoin)
	TrySameServerFirst = true, -- first 2 tries go back to the same server, then any server
	RetryDelay = 5, -- seconds before the 2nd attempt
	MaxDelay = 30, -- the delay doubles each try, up to this
	MaxAttempts = 0, -- 0 = keep trying forever
}

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer

-- Prevent running twice in one session
local env = (getgenv and getgenv()) or _G
if env.__AutoRejoinLoaded then
	return
end
env.__AutoRejoinLoaded = true

local function log(...)
	print("[AutoRejoin]", ...)
end

-- One small Roblox notification (no custom UI). Retries briefly in case the
-- notification system isn't ready yet at the moment the script starts.
local StarterGui = game:GetService("StarterGui")
local function notify(title, text, duration)
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCore("SendNotification", {
					Title = title,
					Text = text,
					Duration = duration,
				})
			end)
			if ok then
				return
			end
			task.wait(0.5)
		end
	end)
end

-- Make the script run again after the rejoin teleport
if CONFIG.ScriptUrl ~= "" then
	local queueFn = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
	if queueFn then
		pcall(queueFn, string.format('loadstring(game:HttpGet("%s"))()', CONFIG.ScriptUrl))
	end
end

----------------------------------------------------------------------
-- Rejoin loop
----------------------------------------------------------------------
local rejoining = false

local function startRejoin(reason)
	if rejoining then
		return
	end
	rejoining = true
	log("Disconnected (" .. tostring(reason) .. "), rejoining...")

	task.spawn(function()
		local attempt, delay = 0, CONFIG.RetryDelay

		while CONFIG.MaxAttempts == 0 or attempt < CONFIG.MaxAttempts do
			attempt += 1
			local sameServer = CONFIG.TrySameServerFirst and attempt <= 2 and game.JobId ~= ""

			local ok, err = pcall(function()
				if sameServer then
					TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
				else
					TeleportService:Teleport(game.PlaceId, player)
				end
			end)
			if not ok then
				log("Attempt " .. attempt .. " failed:", err)
			end

			-- If the teleport worked, the client closes. Still here = it failed, try again.
			task.wait(delay)
			delay = math.min(delay * 2, CONFIG.MaxDelay)
		end

		log("Gave up after " .. attempt .. " attempts")
		rejoining = false
	end)
end

TeleportService.TeleportInitFailed:Connect(function(_, result, message)
	log("Teleport failed:", tostring(result), tostring(message))
end)

----------------------------------------------------------------------
-- Detection 1: the error window (kick / disconnect popup)
----------------------------------------------------------------------
local function watchPromptOverlay()
	local ok, overlay = pcall(function()
		return CoreGui:WaitForChild("RobloxPromptGui", 30):WaitForChild("promptOverlay", 30)
	end)
	if not ok or not overlay then
		log("Could not read the error window, using backup detection only")
		return
	end

	overlay.ChildAdded:Connect(function(child)
		if child.Name == "ErrorPrompt" then
			startRejoin("error window")
		end
	end)

	if overlay:FindFirstChild("ErrorPrompt") then
		startRejoin("error window")
	end
end
task.spawn(watchPromptOverlay)

----------------------------------------------------------------------
-- Detection 2 (backup): Roblox's own error message signal
----------------------------------------------------------------------
pcall(function()
	GuiService.ErrorMessageChanged:Connect(function()
		local message = GuiService:GetErrorMessage()
		if message and message ~= "" then
			startRejoin(message)
		end
	end)
end)

log("Loaded - watching for disconnects")
notify("Auto Rejoin", "Loaded successfully! You'll rejoin automatically if you get disconnected.", 4)
