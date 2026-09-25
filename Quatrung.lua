--!strict

--//====================================================
--// CONFIGURATION
--//====================================================

local CONFIG = {
	MenuToggleKey = Enum.KeyCode.RightShift,

	WalkSpeed = {
		Min = 8,
		Max = 100,
		Default = 16,
	},

	Jump = {
		Min = 25,
		Max = 150,
		Default = 50,
	},

	FlySpeed = {
		Min = 10,
		Max = 120,
		Default = 50,
	},

	AutoFarmDelay = {
		Min = 0.10,
		Max = 2,
		Default = 0.35,
	},

	AntiAFKInterval = 300,

	EggTags = {
		"TrendingEgg",
		"SecretEgg",
		"LegendaryEgg",
	},

	EggFolderName = "Eggs",

	ESPUpdateInterval = 0.25,

	RarityColors = {
		TrendingEgg = Color3.fromRGB(80, 200, 255),
		SecretEgg = Color3.fromRGB(180, 80, 255),
		LegendaryEgg = Color3.fromRGB(255, 190, 40),
	},

	TeamColors = {
		Friendly = Color3.fromRGB(80, 255, 120),
		Enemy = Color3.fromRGB(255, 90, 90),
		Neutral = Color3.fromRGB(255, 255, 255),
	},
}

--//====================================================
--// SERVICES
--//====================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

--//====================================================
--// DUPLICATE PROTECTION
--//====================================================

local GUI_NAME = "MrDonEggUtility"

local oldGui = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild(GUI_NAME)
if oldGui then
	oldGui:Destroy()
end

--//====================================================
--// STATE
--//====================================================

local state = {
	MenuOpen = true,
	FixLag = false,
	FullBright = false,
	SpeedWalk = false,
	HighJump = false,
	Fly = false,
	AutoCatch = false,
	Noclip = false,
	PlayerESP = false,
	EggESP = false,
	AntiAFK = false,

	WalkSpeed = CONFIG.WalkSpeed.Default,
	Jump = CONFIG.Jump.Default,
	FlySpeed = CONFIG.FlySpeed.Default,
	AutoFarmDelay = CONFIG.AutoFarmDelay.Default,

	SelectedEggTag = "TrendingEgg",

	Character = nil :: Model?,
	Humanoid = nil :: Humanoid?,
	RootPart = nil :: BasePart?,
}

local connections: { RBXScriptConnection } = {}
local tasks: { thread } = {}
local original = {
	Lighting = {},
	Visuals = {},
	Character = {},
}

local flyVelocity: BodyVelocity? = nil
local flyGyro: BodyGyro? = nil
local noclipOwners: {[string]: boolean} = {}

--//====================================================
--// HELPERS
--//====================================================

local function connect(signal: RBXScriptSignal, fn: (...any) -> ())
	local connection = signal:Connect(fn)
	table.insert(connections, connection)
	return connection
end

local function spawnTask(fn: () -> ())
	local thread = task.spawn(fn)
	table.insert(tasks, thread)
	return thread
end

local function notify(message: string, duration: number?)
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	local gui = playerGui:FindFirstChild(GUI_NAME)
	if not gui then
		return
	end

	local notification = Instance.new("TextLabel")
	notification.Size = UDim2.fromOffset(260, 42)
	notification.Position = UDim2.new(1, -275, 1, -60)
	notification.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	notification.BackgroundTransparency = 0.08
	notification.TextColor3 = Color3.new(1, 1, 1)
	notification.Font = Enum.Font.GothamMedium
	notification.TextSize = 13
	notification.Text = message
	notification.Parent = gui

	Instance.new("UICorner", notification).CornerRadius = UDim.new(0, 8)

	TweenService:Create(
		notification,
		TweenInfo.new(0.2),
		{Position = UDim2.new(1, -275, 1, -115)}
	):Play()

	task.delay(duration or 2, function()
		if notification.Parent then
			local tween = TweenService:Create(
				notification,
				TweenInfo.new(0.2),
				{TextTransparency = 1, BackgroundTransparency = 1}
			)
			tween:Play()
			tween.Completed:Wait()
			notification:Destroy()
		end
	end)
end

local function getCharacter()
	local character = LocalPlayer.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root then
		return nil
	end

	return character, humanoid, root
end

local function refreshCharacter()
	local character, humanoid, root = getCharacter()

	state.Character = character
	state.Humanoid = humanoid
	state.RootPart = root

	if humanoid then
		original.Character.WalkSpeed = humanoid.WalkSpeed
		original.Character.UseJumpPower = humanoid.UseJumpPower

		if humanoid.UseJumpPower then
			original.Character.JumpPower = humanoid.JumpPower
		else
			original.Character.JumpHeight = humanoid.JumpHeight
		end
	end
end

local function getEggPart(egg: Instance): BasePart?
	if not egg:IsA("Model") then
		return nil
	end

	if egg.PrimaryPart then
		return egg.PrimaryPart
	end

	return egg:FindFirstChildWhichIsA("BasePart", true)
end

local function isEggValid(egg: Instance): boolean
	local part = getEggPart(egg)
	if not part then
		return false
	end

	return egg:IsDescendantOf(workspace) and part.Transparency < 1
end

local function getEggs(): {Instance}
	local found = {}
	local seen: {[Instance]: boolean} = {}

	for _, tag in ipairs(CONFIG.EggTags) do
		for _, egg in ipairs(CollectionService:GetTagged(tag)) do
			if isEggValid(egg) and not seen[egg] then
				seen[egg] = true
				table.insert(found, egg)
			end
		end
	end

	local folder = workspace:FindFirstChild(CONFIG.EggFolderName)
	if folder then
		for _, egg in ipairs(folder:GetChildren()) do
			if isEggValid(egg) and not seen[egg] then
				table.insert(found, egg)
			end
		end
	end

	return found
end

local function nearestEgg(): Instance?
	local root = state.RootPart
	if not root then
		return nil
	end

	local nearest
	local distance = math.huge

	for _, egg in ipairs(getEggs()) do
		local part = getEggPart(egg)
		if part then
			local current = (part.Position - root.Position).Magnitude
			if current < distance then
				distance = current
				nearest = egg
			end
		end
	end

	return nearest
end

--//====================================================
--// LEGITIMATE EGG INTERACTION ADAPTER
--//====================================================

local function interactWithEgg(egg: Instance): boolean
	-- This intentionally does NOT use executor-only
	-- fireproximityprompt/fireclickdetector APIs.

	local prompt = egg:FindFirstChildWhichIsA("ProximityPrompt", true)

	if prompt and prompt.Enabled then
		notify("Egg prompt found — use the displayed interaction.", 1.5)
		return false
	end

	local clickDetector = egg:FindFirstChildWhichIsA("ClickDetector", true)

	if clickDetector then
		notify("Egg click interaction found — click the egg to collect.", 1.5)
		return false
	end

	local part = getEggPart(egg)

	if part and state.RootPart then
		notify("Reached egg target.", 1)
		return true
	end

	return false
end

--//====================================================
--// FIX LAG
--//====================================================

local visualClasses = {
	ParticleEmitter = "Enabled",
	Trail = "Enabled",
	Beam = "Enabled",
	Smoke = "Enabled",
	Fire = "Enabled",
	Sparkles = "Enabled",
	PointLight = "Enabled",
	SpotLight = "Enabled",
	SurfaceLight = "Enabled",
}

local function saveVisual(instance: Instance, property: string)
	original.Visuals[instance] = original.Visuals[instance] or {}

	if original.Visuals[instance][property] == nil then
		original.Visuals[instance][property] = instance[property]
	end
end

local function optimizeVisual(instance: Instance)
	local property = visualClasses[instance.ClassName]
	if property then
		saveVisual(instance, property)
		instance[property] = false
	end

	if instance:IsA("BasePart") then
		saveVisual(instance, "CastShadow")
		instance.CastShadow = false
	end
end

local function enableFixLag()
	for _, instance in ipairs(workspace:GetDescendants()) do
		optimizeVisual(instance)
	end

	for _, instance in ipairs(Lighting:GetChildren()) do
		if instance:IsA("PostEffect") then
			saveVisual(instance, "Enabled")
			instance.Enabled = false
		end
	end
end

local function disableFixLag()
	for instance, properties in pairs(original.Visuals) do
		if instance.Parent then
			for property, value in pairs(properties) do
				pcall(function()
					instance[property] = value
				end)
			end
		end
	end

	table.clear(original.Visuals)
end

local function setFixLag(enabled: boolean)
	state.FixLag = enabled

	if enabled then
		enableFixLag()
	else
		disableFixLag()
	end
end

connect(workspace.DescendantAdded, function(instance)
	if state.FixLag then
		task.defer(optimizeVisual, instance)
	end
end)

--//====================================================
--// FULL BRIGHT
--//====================================================

local function enableFullBright()
	original.Lighting.Brightness = Lighting.Brightness
	original.Lighting.Ambient = Lighting.Ambient
	original.Lighting.OutdoorAmbient = Lighting.OutdoorAmbient
	original.Lighting.ExposureCompensation = Lighting.ExposureCompensation
	original.Lighting.GlobalShadows = Lighting.GlobalShadows

	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(135, 135, 135)
	Lighting.OutdoorAmbient = Color3.fromRGB(170, 170, 170)
	Lighting.ExposureCompensation = 0.5
	Lighting.GlobalShadows = false
end

local function disableFullBright()
	for property, value in pairs(original.Lighting) do
		Lighting[property] = value
	end

	table.clear(original.Lighting)
end

local function setFullBright(enabled: boolean)
	state.FullBright = enabled

	if enabled then
		enableFullBright()
	else
		disableFullBright()
	end
end

--//====================================================
--// MOVEMENT
--//====================================================

local function applyWalk()
	if not state.Humanoid then
		return
	end

	if state.SpeedWalk then
		state.Humanoid.WalkSpeed = state.WalkSpeed
	else
		state.Humanoid.WalkSpeed = original.Character.WalkSpeed or 16
	end
end

local function applyJump()
	if not state.Humanoid then
		return
	end

	if state.Humanoid.UseJumpPower then
		state.Humanoid.JumpPower = state.HighJump
			and state.Jump
			or original.Character.JumpPower
			or 50
	else
		state.Humanoid.JumpHeight = state.HighJump
			and state.Jump
			or original.Character.JumpHeight
			or 7.2
	end
end

local function setSpeed(enabled: boolean)
	state.SpeedWalk = enabled
	applyWalk()
end

local function setJump(enabled: boolean)
	state.HighJump = enabled
	applyJump()
end

connect(RunService.Heartbeat, function()
	if state.SpeedWalk then
		applyWalk()
	end

	if state.HighJump then
		applyJump()
	end
end)

--//====================================================
--// FLY
--//====================================================

local function removeFlyForces()
	if flyVelocity then
		flyVelocity:Destroy()
		flyVelocity = nil
	end

	if flyGyro then
		flyGyro:Destroy()
		flyGyro = nil
	end
end

local function createFlyForces()
	local root = state.RootPart
	if not root then
		return
	end

	removeFlyForces()

	flyVelocity = Instance.new("BodyVelocity")
	flyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	flyVelocity.P = 5000
	flyVelocity.Velocity = Vector3.zero
	flyVelocity.Parent = root

	flyGyro = Instance.new("BodyGyro")
	flyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
	flyGyro.P = 5000
	flyGyro.CFrame = root.CFrame
	flyGyro.Parent = root
end

local function setFly(enabled: boolean)
	state.Fly = enabled

	if enabled then
		createFlyForces()
	else
		removeFlyForces()
	end
end

connect(RunService.RenderStepped, function()
	if not state.Fly or not flyVelocity or not flyGyro then
		return
	end

	local root = state.RootPart
	if not root then
		return
	end

	local camera = Camera
	local move = state.Humanoid and state.Humanoid.MoveDirection or Vector3.zero
	local velocity = move * state.FlySpeed

	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		velocity += Vector3.yAxis * state.FlySpeed
	elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
		velocity -= Vector3.yAxis * state.FlySpeed
	end

	flyVelocity.Velocity = velocity
	flyGyro.CFrame = camera.CFrame
end)

--//====================================================
--// MOBILE FLY BUTTONS
--//====================================================

local flightGui = Instance.new("ScreenGui")
flightGui.Name = "MrDonFlightControls"
flightGui.ResetOnSpawn = false
flightGui.IgnoreGuiInset = false
flightGui.Parent = LocalPlayer.PlayerGui

local function makeFlightButton(text: string, position: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(48, 48)
	button.Position = position
	button.AnchorPoint = Vector2.new(1, 1)
	button.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	button.BackgroundTransparency = 0.35
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = text
	button.TextSize = 20
	button.Font = Enum.Font.GothamBold
	button.Visible = false
	button.Parent = flightGui

	Instance.new("UICorner", button).CornerRadius = UDim.new(1, 0)

	return button
end

local upButton = makeFlightButton("▲", UDim2.new(1, -24, 1, -150))
local downButton = makeFlightButton("▼", UDim2.new(1, -24, 1, -94))

local upHeld = false
local downHeld = false

connect(upButton.InputBegan, function(input)
	if input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1 then
		upHeld = true
	end
end)

connect(upButton.InputEnded, function()
	upHeld = false
end)

connect(downButton.InputBegan, function(input)
	if input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1 then
		downHeld = true
	end
end)

connect(downButton.InputEnded, function()
	downHeld = false
end)

connect(RunService.RenderStepped, function()
	if not state.Fly or not flyVelocity then
		return
	end

	local velocity = flyVelocity.Velocity

	if upHeld then
		velocity += Vector3.yAxis * state.FlySpeed
	end

	if downHeld then
		velocity -= Vector3.yAxis * state.FlySpeed
	end

	flyVelocity.Velocity = velocity
end)

local function updateFlightButtons()
	upButton.Visible = state.Fly
	downButton.Visible = state.Fly
end

--//====================================================
--// NOCLIP
--//====================================================

local function noclipEnabled()
	for _, enabled in pairs(noclipOwners) do
		if enabled then
			return true
		end
	end

	return false
end

local function setNoclipOwner(owner: string, enabled: boolean)
	noclipOwners[owner] = enabled
	state.Noclip = noclipEnabled()
end

local function applyNoclip()
	local character = state.Character
	if not character then
		return
	end

	for _, instance in ipairs(character:GetDescendants()) do
		if instance:IsA("BasePart") then
			instance.CanCollide = not state.Noclip
		end
	end
end

local function setNoclip(enabled: boolean)
	setNoclipOwner("Manual", enabled)
	applyNoclip()
end

connect(RunService.Stepped, function()
	if state.Noclip then
		applyNoclip()
	end
end)

--//====================================================
--// AUTO CATCH ASSIST
--//====================================================

local autoCatchRunning = false

local function moveToEgg(egg: Instance): boolean
	local root = state.RootPart
	local part = getEggPart(egg)

	if not root or not part or not isEggValid(egg) then
		return false
	end

	local distance = (part.Position - root.Position).Magnitude
	local duration = math.clamp(distance / 80, 0.15, 1.5)

	local target = part.Position
	local tween = TweenService:Create(
		root,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{CFrame = CFrame.new(target + Vector3.new(0, 2, 0))}
	)

	tween:Play()
	tween.Completed:Wait()

	return isEggValid(egg)
end

local function autoCatchLoop()
	if autoCatchRunning then
		return
	end

	autoCatchRunning = true

	while state.AutoCatch do
		local egg = nearestEgg()

		if egg then
			local reached = moveToEgg(egg)

			if reached then
				interactWithEgg(egg)
			end
		else
			task.wait(0.25)
		end

		task.wait(state.AutoFarmDelay)
	end

	autoCatchRunning = false
end

local function setAutoCatch(enabled: boolean)
	state.AutoCatch = enabled

	if enabled then
		spawnTask(autoCatchLoop)
	end
end

--//====================================================
--// ANTI-AFK
--//====================================================

local antiAfkRunning = false

local function antiAfkLoop()
	if antiAfkRunning then
		return
	end

	antiAfkRunning = true

	while state.AntiAFK do
		task.wait(CONFIG.AntiAFKInterval)

		if not state.AntiAFK then
			break
		end

		local camera = workspace.CurrentCamera
		if camera then
			local originalCFrame = camera.CFrame
			camera.CFrame = originalCFrame * CFrame.Angles(0, math.rad(1), 0)

			task.wait(0.15)

			if camera then
				camera.CFrame = originalCFrame
			end
		end

		-- VirtualUser is only used for Roblox's local idle signal.
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
	end

	antiAfkRunning = false
end

local function setAntiAFK(enabled: boolean)
	state.AntiAFK = enabled

	if enabled then
		spawnTask(antiAfkLoop)
	end
end

--//====================================================
--// ESP
--//====================================================

local espFolder = Instance.new("Folder")
espFolder.Name = "MrDonESP"
espFolder.Parent = workspace

local function clearESP()
	espFolder:ClearAllChildren()
end

local function makeEggESP(egg: Instance)
	local part = getEggPart(egg)
	if not part then
		return
	end

	local tag
	for _, candidate in ipairs(CONFIG.EggTags) do
		if CollectionService:HasTag(egg, candidate) then
			tag = candidate
			break
		end
	end

	if not tag then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Adornee = egg
	highlight.FillColor = CONFIG.RarityColors[tag]
	highlight.OutlineColor = CONFIG.RarityColors[tag]
	highlight.FillTransparency = 0.75
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = espFolder
end

local function makePlayerESP(player: Player)
	if player == LocalPlayer then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not root or not humanoid then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Adornee = character
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

	if player.Team == LocalPlayer.Team then
		highlight.FillColor = CONFIG.TeamColors.Friendly
	elseif player.Team then
		highlight.FillColor = CONFIG.TeamColors.Enemy
	else
		highlight.FillColor = CONFIG.TeamColors.Neutral
	end

	highlight.FillTransparency = 0.8
	highlight.Parent = espFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = root
	billboard.Size = UDim2.fromOffset(150, 45)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = espFolder

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = highlight.FillColor
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 11

	local distance = state.RootPart
		and math.floor((root.Position - state.RootPart.Position).Magnitude)
		or 0

	label.Text = string.format(
		"%s\n%d studs | HP %d",
		player.DisplayName,
		distance,
		math.floor(humanoid.Health)
	)

	label.Parent = billboard
end

local function updateESP()
	clearESP()

	if state.EggESP then
		for _, egg in ipairs(getEggs()) do
			makeEggESP(egg)
		end
	end

	if state.PlayerESP then
		for _, player in ipairs(Players:GetPlayers()) do
			makePlayerESP(player)
		end
	end
end

spawnTask(function()
	while true do
		task.wait(CONFIG.ESPUpdateInterval)

		if state.EggESP or state.PlayerESP then
			updateESP()
		end
	end
end)

local function setEggESP(enabled: boolean)
	state.EggESP = enabled

	if enabled then
		updateESP()
	else
		clearESP()
	end
end

local function setPlayerESP(enabled: boolean)
	state.PlayerESP = enabled

	if enabled then
		updateESP()
	elseif not state.EggESP then
		clearESP()
	end
end

--//====================================================
--// CHARACTER RESPAWN
--//====================================================

connect(LocalPlayer.CharacterAdded, function()
	task.wait(0.25)
	refreshCharacter()

	if state.Fly then
		createFlyForces()
	end

	applyWalk()
	applyJump()
	applyNoclip()
end)

refreshCharacter()

--//====================================================
--// UI
--//====================================================

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = LocalPlayer.PlayerGui

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(360, 430)
main.Position = UDim2.new(0, 25, 0.5, -215)
main.BackgroundColor3 = Color3.fromRGB(22, 23, 28)
main.BorderSizePixel = 0
main.Parent = gui

Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -90, 0, 42)
title.Position = UDim2.fromOffset(15, 0)
title.BackgroundTransparency = 1
title.Text = "MrDon • Egg Utility"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.Parent = main

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(32, 30)
close.Position = UDim2.new(1, -38, 0, 6)
close.Text = "×"
close.TextSize = 22
close.TextColor3 = Color3.new(1, 1, 1)
close.BackgroundTransparency = 1
close.Parent = main

local minimize = Instance.new("TextButton")
minimize.Size = UDim2.fromOffset(32, 30)
minimize.Position = UDim2.new(1, -72, 0, 6)
minimize.Text = "—"
minimize.TextSize = 18
minimize.TextColor3 = Color3.new(1, 1, 1)
minimize.BackgroundTransparency = 1
minimize.Parent = main

local content = Instance.new("ScrollingFrame")
content.Size = UDim2.new(1, -20, 1, -55)
content.Position = UDim2.fromOffset(10, 48)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 4
content.CanvasSize = UDim2.new()
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.Parent = main

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6)
list.Parent = content

local function makeRow(name: string, callback: (boolean) -> ())
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, 38)
	row.BackgroundColor3 = Color3.fromRGB(30, 31, 37)
	row.Parent = content

	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -60, 1, 0)
	label.Position = UDim2.fromOffset(10, 0)
	label.BackgroundTransparency = 1
	label.Text = name
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 12
	label.Parent = row

	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(45, 25)
	button.Position = UDim2.new(1, -52, 0.5, -12)
	button.Text = "OFF"
	button.TextColor3 = Color3.new(1, 1, 1)
	button.BackgroundColor3 = Color3.fromRGB(65, 65, 72)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 10
	button.Parent = row

	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)

	local enabled = false

	connect(button.Activated, function()
		enabled = not enabled
		button.Text = enabled and "ON" or "OFF"
		callback(enabled)
	end)
end

local function makeNumberRow(
	name: string,
	minimum: number,
	maximum: number,
	defaultValue: number,
	callback: (number) -> ()
)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, 48)
	row.BackgroundColor3 = Color3.fromRGB(30, 31, 37)
	row.Parent = content

	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.42, 0, 1, 0)
	label.Position = UDim2.fromOffset(10, 0)
	label.BackgroundTransparency = 1
	label.Text = name
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 11
	label.Parent = row

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0.48, 0, 0, 28)
	box.Position = UDim2.new(0.48, 0, 0.5, -14)
	box.Text = tostring(defaultValue)
	box.ClearTextOnFocus = false
	box.TextColor3 = Color3.new(1, 1, 1)
	box.BackgroundColor3 = Color3.fromRGB(45, 46, 53)
	box.Font = Enum.Font.Gotham
	box.TextSize = 11
	box.Parent = row

	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)

	connect(box.FocusLost, function()
		local value = tonumber(box.Text)

		if not value then
			box.Text = tostring(defaultValue)
			notify(name .. ": invalid number", 1.5)
			return
		end

		value = math.clamp(value, minimum, maximum)
		box.Text = tostring(value)
		callback(value)
	end)
end

local function makeEggSelector()
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, 74)
	row.BackgroundColor3 = Color3.fromRGB(30, 31, 37)
	row.Parent = content

	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

	local search = Instance.new("TextBox")
	search.Size = UDim2.new(1, -20, 0, 27)
	search.Position = UDim2.fromOffset(10, 8)
	search.PlaceholderText = "Search egg type..."
	search.Text = ""
	search.TextColor3 = Color3.new(1, 1, 1)
	search.BackgroundColor3 = Color3.fromRGB(45, 46, 53)
	search.Font = Enum.Font.Gotham
	search.TextSize = 11
	search.Parent = row

	Instance.new("UICorner", search).CornerRadius = UDim.new(0, 6)

	local selected = Instance.new("TextLabel")
	selected.Size = UDim2.new(1, -20, 0, 25)
	selected.Position = UDim2.fromOffset(10, 40)
	selected.BackgroundTransparency = 1
	selected.Text = "Target: " .. state.SelectedEggTag
	selected.TextColor3 = Color3.fromRGB(180, 200, 255)
	selected.TextXAlignment = Enum.TextXAlignment.Left
	selected.Font = Enum.Font.GothamMedium
	selected.TextSize = 11
	selected.Parent = row

	connect(search.FocusLost, function()
		local text = string.lower(search.Text)

		for _, tag in ipairs(CONFIG.EggTags) do
			if string.find(string.lower(tag), text, 1, true) then
				state.SelectedEggTag = tag
				selected.Text = "Target: " .. tag
				search.Text = ""
				return
			end
		end

		notify("No matching egg tag.", 1.5)
	end)
end

makeRow("Fix Lag", setFixLag)
makeRow("Full Bright", setFullBright)

makeNumberRow(
	"Walk Speed",
	CONFIG.WalkSpeed.Min,
	CONFIG.WalkSpeed.Max,
	state.WalkSpeed,
	function(value)
		state.WalkSpeed = value
		applyWalk()
	end
)

makeNumberRow(
	"Jump",
	CONFIG.Jump.Min,
	CONFIG.Jump.Max,
	state.Jump,
	function(value)
		state.Jump = value
		applyJump()
	end
)

makeNumberRow(
	"Fly Speed",
	CONFIG.FlySpeed.Min,
	CONFIG.FlySpeed.Max,
	state.FlySpeed,
	function(value)
		state.FlySpeed = value
	end
)

makeNumberRow(
	"Auto-Farm Delay",
	CONFIG.AutoFarmDelay.Min,
	CONFIG.AutoFarmDelay.Max,
	state.AutoFarmDelay,
	function(value)
		state.AutoFarmDelay = value
	end
)

makeEggSelector()

makeRow("Speed Walk", setSpeed)
makeRow("High Jump", setJump)

makeRow("Fly", function(enabled)
	setFly(enabled)
	updateFlightButtons()
end)

makeRow("Auto Catch", setAutoCatch)
makeRow("Noclip", setNoclip)
makeRow("Egg ESP", setEggESP)
makeRow("Player ESP", setPlayerESP)
makeRow("Anti-AFK", setAntiAFK)

--//====================================================
--// DRAGGING
--//====================================================

local dragging = false
local dragStart = Vector2.zero
local startPosition = main.Position

local function updateDrag(input: InputObject)
	local delta = input.Position - dragStart

	main.Position = UDim2.new(
		startPosition.X.Scale,
		startPosition.X.Offset + delta.X,
		startPosition.Y.Scale,
		startPosition.Y.Offset + delta.Y
	)
end

connect(title.InputBegan, function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		dragging = true
		dragStart = input.Position
		startPosition = main.Position
	end
end)

connect(UserInputService.InputChanged, function(input)
	if dragging and (
		input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
	) then
		updateDrag(input)
	end
end)

connect(UserInputService.InputEnded, function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

--//====================================================
--// MENU CONTROLS
--//====================================================

local collapsed = false

local function toggleMenu()
	state.MenuOpen = not state.MenuOpen
	main.Visible = state.MenuOpen
end

connect(close.Activated, function()
	state.MenuOpen = false
	main.Visible = false
end)

connect(minimize.Activated, function()
	collapsed = not collapsed
	content.Visible = not collapsed
	main.Size = collapsed
		and UDim2.fromOffset(360, 48)
		or UDim2.fromOffset(360, 430)
end)

connect(UserInputService.InputBegan, function(input, processed)
	if processed then
		return
	end

	if input.KeyCode == CONFIG.MenuToggleKey then
		toggleMenu()
	end
end)

--//====================================================
--// CLEANUP
--//====================================================

local function cleanup()
	state.AutoCatch = false
	state.AntiAFK = false
	state.Fly = false

	removeFlyForces()
	clearESP()

	for _, connection in ipairs(connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end

	for _, thread in ipairs(tasks) do
		task.cancel(thread)
	end

	disableFixLag()
	disableFullBright()

	if flightGui then
		flightGui:Destroy()
	end

	if gui then
		gui:Destroy()
	end
end

script.Destroying:Connect(cleanup)

notify("MrDon utility menu loaded.", 2)
