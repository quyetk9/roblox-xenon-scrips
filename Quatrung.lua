--!strict
-- Place in StarterPlayer > StarterPlayerScripts

--========================================================
-- CONFIGURATION
--========================================================

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
		Max = 2.00,
		Default = 0.35,
	},

	UIBuildDelay = 0.10,
	ESPUpdateInterval = 0.25,
	AntiAFKInterval = 300,

	EggFolderName = "Eggs",

	EggTags = {
		"TrendingEgg",
		"SecretEgg",
		"LegendaryEgg",
	},

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

--========================================================
-- SERVICES
--========================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- IMPORTANT:
-- There is deliberately NO Character access here.
-- There are deliberately NO Workspace/Lighting scans here.
-- There are deliberately NO movement/ESP/physics connections here.

--========================================================
-- DUPLICATE MENU GUARD
--========================================================

local GUI_NAME = "MrDonEggUtility"

if PlayerGui:FindFirstChild(GUI_NAME) then
	return
end

--========================================================
-- STATE
--========================================================

local state = {
	FixLag = false,
	FullBright = false,
	SpeedWalk = false,
	HighJump = false,
	Fly = false,
	AutoCatch = false,
	Noclip = false,
	EggESP = false,
	PlayerESP = false,
	AntiAFK = false,

	WalkSpeed = CONFIG.WalkSpeed.Default,
	Jump = CONFIG.Jump.Default,
	FlySpeed = CONFIG.FlySpeed.Default,
	AutoFarmDelay = CONFIG.AutoFarmDelay.Default,

	SelectedEggTag = CONFIG.EggTags[1],

	MovementOwner = "None",
	MenuVisible = true,
	Collapsed = false,
}

--========================================================
-- FEATURE CONNECTION REGISTRIES
--========================================================

local featureConnections: {
	[string]: {RBXScriptConnection}
} = {}

local featureTasks: {
	[string]: {thread}
} = {}

local function addConnection(
	feature: string,
	connection: RBXScriptConnection
)
	featureConnections[feature] = featureConnections[feature] or {}
	table.insert(featureConnections[feature], connection)
end

local function disconnectFeature(feature: string)
	local connections = featureConnections[feature]

	if connections then
		for _, connection in ipairs(connections) do
			if connection.Connected then
				connection:Disconnect()
			end
		end
	end

	featureConnections[feature] = nil
end

local function addTask(feature: string, thread: thread)
	featureTasks[feature] = featureTasks[feature] or {}
	table.insert(featureTasks[feature], thread)
end

local function cancelFeatureTasks(feature: string)
	local tasks = featureTasks[feature]

	if tasks then
		for _, thread in ipairs(tasks) do
			if coroutine.status(thread) ~= "dead" then
				task.cancel(thread)
			end
		end
	end

	featureTasks[feature] = nil
end

local function cleanupFeature(feature: string)
	disconnectFeature(feature)
	cancelFeatureTasks(feature)
end

--========================================================
-- UI
--========================================================

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = PlayerGui

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.fromOffset(360, 430)
main.Position = UDim2.new(0, 24, 0.5, -215)
main.BackgroundColor3 = Color3.fromRGB(22, 23, 28)
main.BorderSizePixel = 0
main.Parent = gui

Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -105, 0, 42)
title.Position = UDim2.fromOffset(15, 0)
title.BackgroundTransparency = 1
title.Text = "MrDon • Egg Utility"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.Parent = main

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -30, 0, 26)
status.Position = UDim2.fromOffset(15, 39)
status.BackgroundTransparency = 1
status.Text = "Auto Catch: OFF   •   Anti-AFK: OFF"
status.TextColor3 = Color3.fromRGB(170, 175, 185)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Font = Enum.Font.Gotham
status.TextSize = 10
status.Parent = main

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromOffset(30, 30)
closeButton.Position = UDim2.new(1, -38, 0, 6)
closeButton.Text = "×"
closeButton.TextSize = 21
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.BackgroundTransparency = 1
closeButton.Parent = main

local minimizeButton = Instance.new("TextButton")
minimizeButton.Size = UDim2.fromOffset(30, 30)
minimizeButton.Position = UDim2.new(1, -72, 0, 6)
minimizeButton.Text = "—"
minimizeButton.TextSize = 18
minimizeButton.TextColor3 = Color3.new(1, 1, 1)
minimizeButton.BackgroundTransparency = 1
minimizeButton.Parent = main

local content = Instance.new("ScrollingFrame")
content.Name = "Content"
content.Size = UDim2.new(1, -20, 1, -77)
content.Position = UDim2.fromOffset(10, 72)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 4
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.CanvasSize = UDim2.new()
content.Parent = main

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6)
list.Parent = content

local function uiPause()
	task.wait(CONFIG.UIBuildDelay)
end

local function notify(message: string)
	local label = Instance.new("TextLabel")

	label.Size = UDim2.fromOffset(255, 38)
	label.Position = UDim2.new(1, -270, 1, -60)
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	label.BackgroundTransparency = 0.08
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 11
	label.Text = message
	label.Parent = gui

	Instance.new("UICorner", label).CornerRadius = UDim.new(0, 8)

	task.delay(1.8, function()
		if label.Parent then
			label:Destroy()
		end
	end)
end

local function updateStatus()
	local antiAfkText = state.AntiAFK and "ON" or "OFF"
	local autoText = state.AutoCatch and "ON" or "OFF"

	status.Text = string.format(
		"Auto Catch: %s   •   Anti-AFK: %s",
		autoText,
		antiAfkText
	)
end

--========================================================
-- CHARACTER ACCESS — ONLY CALLED BY ACTIVE FEATURES
--========================================================

local function getCharacterObjects()
	local character = LocalPlayer.Character

	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root then
		return character, nil, nil
	end

	return character, humanoid, root
end

local function featureNeedsCharacter()
	return state.SpeedWalk
		or state.HighJump
		or state.Fly
		or state.AutoCatch
		or state.Noclip
end

local function bindCharacterLifecycle()
	if featureConnections.CharacterLifecycle then
		return
	end

	addConnection(
		"CharacterLifecycle",
		LocalPlayer.CharacterAdded:Connect(function()
			task.wait(0.15)

			if state.SpeedWalk then
				applyWalkSpeed()
			end

			if state.HighJump then
				applyJump()
			end

			if state.Fly then
				enableFlyPhysics()
			end

			if state.Noclip then
				updateNoclipController()
			end
		end)
	)
end

local function unbindCharacterLifecycle()
	if featureNeedsCharacter() then
		return
	end

	cleanupFeature("CharacterLifecycle")
end

--========================================================
-- MOVEMENT OWNERSHIP
--========================================================

local function stopAutoCatch()
	if not state.AutoCatch then
		return
	end

	state.AutoCatch = false
	cleanupFeature("AutoCatch")

	if state.MovementOwner == "AutoCatch" then
		state.MovementOwner = "None"
	end
end

local function stopFly()
	if not state.Fly then
		return
	end

	state.Fly = false
	cleanupFeature("FlyPhysics")

	if state.MovementOwner == "Fly" then
		state.MovementOwner = "None"
	end

	updateFlightControls()
end

local function claimMovement(owner: string)
	if owner == "Fly" then
		stopAutoCatch()
	elseif owner == "AutoCatch" then
		stopFly()
	end

	state.MovementOwner = owner
end

--========================================================
-- FIX LAG — ZERO INITIALIZATION UNTIL ENABLED
--========================================================

local visualOriginals: {
	[Instance]: {[string]: any}
} = {}

local function saveVisualProperty(
	instance: Instance,
	property: string
)
	local values = visualOriginals[instance]

	if not values then
		values = {}
		visualOriginals[instance] = values
	end

	if values[property] == nil then
		values[property] = instance[property]
	end
end

local visualProperties = {
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

local function reduceVisual(instance: Instance)
	local property = visualProperties[instance.ClassName]

	if property then
		saveVisualProperty(instance, property)
		instance[property] = false
	end

	if instance:IsA("BasePart") then
		saveVisualProperty(instance, "CastShadow")
		instance.CastShadow = false
	end
end

local function enableFixLag()
	-- First Workspace scan happens HERE, never at startup.
	for _, instance in ipairs(workspace:GetDescendants()) do
		reduceVisual(instance)
	end

	for _, instance in ipairs(Lighting:GetChildren()) do
		if instance:IsA("BloomEffect")
			or instance:IsA("BlurEffect")
			or instance:IsA("SunRaysEffect")
			or instance:IsA("ColorCorrectionEffect")
			or instance:IsA("DepthOfFieldEffect") then

			saveVisualProperty(instance, "Enabled")
			instance.Enabled = false
		end
	end

	addConnection(
		"FixLag",
		workspace.DescendantAdded:Connect(function(instance)
			if state.FixLag then
				reduceVisual(instance)
			end
		end)
	)
end

local function disableFixLag()
	cleanupFeature("FixLag")

	for instance, values in pairs(visualOriginals) do
		if instance.Parent then
			for property, value in pairs(values) do
				instance[property] = value
			end
		end
	end

	table.clear(visualOriginals)
end

local function setFixLag(enabled: boolean)
	state.FixLag = enabled

	if enabled then
		enableFixLag()
		notify("Fix Lag enabled.")
	else
		disableFixLag()
		notify("Fix Lag restored.")
	end
end

--========================================================
-- FULL BRIGHT — DORMANT UNTIL ENABLED
--========================================================

local lightingOriginals: {[string]: any} = {}

local function enableFullBright()
	lightingOriginals.Brightness = Lighting.Brightness
	lightingOriginals.Ambient = Lighting.Ambient
	lightingOriginals.OutdoorAmbient = Lighting.OutdoorAmbient
	lightingOriginals.ExposureCompensation =
		Lighting.ExposureCompensation
	lightingOriginals.GlobalShadows = Lighting.GlobalShadows

	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(135, 135, 135)
	Lighting.OutdoorAmbient = Color3.fromRGB(170, 170, 170)
	Lighting.ExposureCompensation = 0.5
	Lighting.GlobalShadows = false
end

local function disableFullBright()
	for property, value in pairs(lightingOriginals) do
		Lighting[property] = value
	end

	table.clear(lightingOriginals)
end

local function setFullBright(enabled: boolean)
	state.FullBright = enabled

	if enabled then
		enableFullBright()
		notify("Full Bright enabled.")
	else
		disableFullBright()
		notify("Lighting restored.")
	end
end

--========================================================
-- WALK / JUMP — CHARACTER ACCESS ONLY AFTER TOGGLE
--========================================================

local characterOriginals = {
	WalkSpeed = nil :: number?,
	UseJumpPower = nil :: boolean?,
	JumpPower = nil :: number?,
	JumpHeight = nil :: number?,
}

local function cacheCharacterMovement()
	local _, humanoid = getCharacterObjects()

	if not humanoid then
		return
	end

	characterOriginals.WalkSpeed = humanoid.WalkSpeed
	characterOriginals.UseJumpPower = humanoid.UseJumpPower

	if humanoid.UseJumpPower then
		characterOriginals.JumpPower = humanoid.JumpPower
	else
		characterOriginals.JumpHeight = humanoid.JumpHeight
	end
end

function applyWalkSpeed()
	local _, humanoid = getCharacterObjects()

	if not humanoid then
		return
	end

	if state.SpeedWalk then
		humanoid.WalkSpeed = state.WalkSpeed
	elseif characterOriginals.WalkSpeed then
		humanoid.WalkSpeed = characterOriginals.WalkSpeed
	end
end

function applyJump()
	local _, humanoid = getCharacterObjects()

	if not humanoid then
		return
	end

	if humanoid.UseJumpPower then
		if state.HighJump then
			humanoid.JumpPower = state.Jump
		elseif characterOriginals.JumpPower then
			humanoid.JumpPower = characterOriginals.JumpPower
		end
	else
		if state.HighJump then
			humanoid.JumpHeight = state.Jump
		elseif characterOriginals.JumpHeight then
			humanoid.JumpHeight = characterOriginals.JumpHeight
		end
	end
end

local function setSpeedWalk(enabled: boolean)
	if enabled then
		cacheCharacterMovement()
		bindCharacterLifecycle()

		state.SpeedWalk = true
		applyWalkSpeed()
		notify("Walk Speed enabled.")
	else
		state.SpeedWalk = false
		applyWalkSpeed()
		notify("Walk Speed restored.")
		unbindCharacterLifecycle()
	end
end

local function setHighJump(enabled: boolean)
	if enabled then
		cacheCharacterMovement()
		bindCharacterLifecycle()

		state.HighJump = true
		applyJump()
		notify("Jump enabled.")
	else
		state.HighJump = false
		applyJump()
		notify("Jump restored.")
		unbindCharacterLifecycle()
	end
end

--========================================================
-- FLY — NO PHYSICS OBJECTS EXIST BEFORE ENABLE
--========================================================

local flyVelocity = nil
local flyGyro = nil

function enableFlyPhysics()
	-- Body movers are created only here, after Fly is enabled.
	local _, humanoid, root = getCharacterObjects()

	if not humanoid or not root then
		notify("Fly unavailable until the character is ready.")
		return
	end

	if flyVelocity then
		flyVelocity:Destroy()
	end

	if flyGyro then
		flyGyro:Destroy()
	end

	flyVelocity = Instance.new("BodyVelocity")
	flyVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
	flyVelocity.P = 5000
	flyVelocity.Velocity = Vector3.zero
	flyVelocity.Parent = root

	flyGyro = Instance.new("BodyGyro")
	flyGyro.MaxTorque = Vector3.new(100000, 100000, 100000)
	flyGyro.P = 5000
	flyGyro.CFrame = root.CFrame
	flyGyro.Parent = root

	disconnectFeature("FlyPhysics")

	addConnection(
		"FlyPhysics",
		RunService.RenderStepped:Connect(function()
			if not state.Fly then
				return
			end

			if not flyVelocity or not flyVelocity.Parent then
				enableFlyPhysics()
				return
			end

			if not flyGyro or not flyGyro.Parent then
				enableFlyPhysics()
				return
			end

			local camera = workspace.CurrentCamera
			local _, currentHumanoid, currentRoot =
				getCharacterObjects()

			if not camera or not currentHumanoid or not currentRoot then
				return
			end

			local velocity =
				currentHumanoid.MoveDirection * state.FlySpeed

			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
				velocity += Vector3.yAxis * state.FlySpeed
			end

			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
				velocity -= Vector3.yAxis * state.FlySpeed
			end

			if upHeld then
				velocity += Vector3.yAxis * state.FlySpeed
			end

			if downHeld then
				velocity -= Vector3.yAxis * state.FlySpeed
			end

			flyVelocity.Velocity = velocity
			flyGyro.CFrame = camera.CFrame
		end)
	)
end

function updateFlightControls()
	upButton.Visible = state.Fly
	downButton.Visible = state.Fly
end

local function setFly(enabled: boolean)
	if enabled then
		claimMovement("Fly")
		state.Fly = true
		bindCharacterLifecycle()
		enableFlyPhysics()
		enableNoclipOwner("Fly")
		updateFlightControls()
		notify("Fly enabled.")
	else
		stopFly()
		disableNoclipOwner("Fly")
		applyNoclipState()
		notify("Fly disabled.")
	end
end

--========================================================
-- NOCLIP REFERENCE COUNTING
--========================================================

local noclipOwners: {[string]: boolean} = {}
local noclipStepped: RBXScriptConnection? = nil

function applyNoclipState()
	local enabled = false

	for _, ownerEnabled in pairs(noclipOwners) do
		if ownerEnabled then
			enabled = true
			break
		end
	end

	local character = LocalPlayer.Character

	if not character then
		return
	end

	for _, instance in ipairs(character:GetDescendants()) do
		if instance:IsA("BasePart") then
			instance.CanCollide = not enabled
		end
	end
end

function updateNoclipController()
	local shouldRun = false

	for _, ownerEnabled in pairs(noclipOwners) do
		if ownerEnabled then
			shouldRun = true
			break
		end
	end

	if shouldRun and not noclipStepped then
		noclipStepped = RunService.Stepped:Connect(function()
			applyNoclipState()
		end)
	elseif not shouldRun and noclipStepped then
		noclipStepped:Disconnect()
		noclipStepped = nil
	end

	applyNoclipState()
end

function enableNoclipOwner(owner: string)
	noclipOwners[owner] = true
	updateNoclipController()
end

function disableNoclipOwner(owner: string)
	noclipOwners[owner] = nil
	updateNoclipController()
end

local function setManualNoclip(enabled: boolean)
	state.Noclip = enabled

	if enabled then
		enableNoclipOwner("Manual")
	else
		disableNoclipOwner("Manual")
	end

	if featureNeedsCharacter() then
		bindCharacterLifecycle()
	else
		unbindCharacterLifecycle()
	end
end

--========================================================
-- EGG TARGETING
--========================================================

local function getEggPart(egg: Instance): BasePart?
	if not egg:IsA("Model") then
		return nil
	end

	if egg.PrimaryPart then
		return egg.PrimaryPart
	end

	return egg:FindFirstChildWhichIsA("BasePart", true)
end

local function isValidEgg(egg: Instance): boolean
	local part = getEggPart(egg)

	if not part then
		return false
	end

	return egg:IsDescendantOf(workspace)
		and part.Transparency < 1
end

local function isTaggedTarget(egg: Instance): boolean
	for _, tag in ipairs(CONFIG.EggTags) do
		if tag == state.SelectedEggTag
			and CollectionService:HasTag(egg, tag) then
			return true
		end
	end

	return false
end

local function getEggTargets(): {Instance}
	local results = {}
	local seen: {[Instance]: boolean} = {}

	for _, tag in ipairs(CONFIG.EggTags) do
		if tag == state.SelectedEggTag then
			for _, egg in ipairs(CollectionService:GetTagged(tag)) do
				if isValidEgg(egg) and not seen[egg] then
					seen[egg] = true
					table.insert(results, egg)
				end
			end
		end
	end

	local folder = workspace:FindFirstChild(CONFIG.EggFolderName)

	if folder then
		for _, egg in ipairs(folder:GetChildren()) do
			if isValidEgg(egg) and not seen[egg] then
				table.insert(results, egg)
			end
		end
	end

	return results
end

local function findNearestEgg(): Instance?
	local _, _, root = getCharacterObjects()

	if not root then
		return nil
	end

	local nearest: Instance? = nil
	local nearestDistance = math.huge

	for _, egg in ipairs(getEggTargets()) do
				local part = getEggPart(egg)

		if part then
			local distance =
				(part.Position - root.Position).Magnitude

			if distance < nearestDistance then
				nearestDistance = distance
				nearest = egg
			end
		end
	end

	return nearest
end

--========================================================
-- LEGITIMATE INTERACTION ADAPTER
--========================================================

local function interactWithEgg(egg: Instance): boolean
	local prompt =
		egg:FindFirstChildWhichIsA("ProximityPrompt", true)

	if prompt and prompt.Enabled then
		notify("ProximityPrompt detected; use the game's normal interaction.")
		return false
	end

	local clickDetector =
		egg:FindFirstChildWhichIsA("ClickDetector", true)

	if clickDetector then
		notify("ClickDetector detected; use the game's normal interaction.")
		return false
	end

	return getEggPart(egg) ~= nil
end

--========================================================
-- AUTO CATCH
--========================================================

local function moveToEgg(egg: Instance): boolean
	local _, _, root = getCharacterObjects()
	local part = getEggPart(egg)

	if not root or not part or not isValidEgg(egg) then
		return false
	end

	local distance =
		(part.Position - root.Position).Magnitude

	local duration = math.clamp(distance / 80, 0.15, 1.5)
	local destination = part.Position + Vector3.new(0, 2, 0)

	local tween = TweenService:Create(
		root,
		TweenInfo.new(
			duration,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.Out
		),
		{
			CFrame = CFrame.new(destination)
		}
	)

	tween:Play()
	tween.Completed:Wait()

	return isValidEgg(egg)
end

local function autoCatchLoop()
	local feature = "AutoCatch"

	while state.AutoCatch do
		local egg = findNearestEgg()

		if egg then
			enableNoclipOwner("AutoCatch")

			if moveToEgg(egg) and isValidEgg(egg) then
				interactWithEgg(egg)
			end

			disableNoclipOwner("AutoCatch")
		else
			task.wait(0.25)
		end

		task.wait(state.AutoFarmDelay)
	end

	disableNoclipOwner("AutoCatch")
	cleanupFeature(feature)
end

local function setAutoCatch(enabled: boolean)
	if enabled then
		claimMovement("AutoCatch")
		state.AutoCatch = true
		bindCharacterLifecycle()

		local thread = task.spawn(autoCatchLoop)
		addTask("AutoCatch", thread)

		notify("Auto Catch enabled.")
	else
		stopAutoCatch()
		disableNoclipOwner("AutoCatch")
		notify("Auto Catch disabled.")
		unbindCharacterLifecycle()
	end

	updateStatus()
end

--========================================================
-- ANTI-AFK
--========================================================

local function setAntiAFK(enabled: boolean)
	state.AntiAFK = enabled
	cleanupFeature("AntiAFK")

	if not enabled then
		updateStatus()
		notify("Anti-AFK disabled.")
		return
	end

	local VirtualUser = game:GetService("VirtualUser")

	addConnection(
		"AntiAFK",
		LocalPlayer.Idled:Connect(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
	)

	updateStatus()
	notify("Anti-AFK enabled.")
end

--========================================================
-- ESP
--========================================================

local espFolder: Folder? = nil

local function ensureESPFolder()
	if not espFolder then
		espFolder = Instance.new("Folder")
		espFolder.Name = "MrDonESP"
		espFolder.Parent = gui
	end

	return espFolder
end

local function clearESP()
	if espFolder then
		espFolder:ClearAllChildren()
	end
end

local function createEggESP(egg: Instance)
	local part = getEggPart(egg)

	if not part then
		return
	end

	local folder = ensureESPFolder()
	local rarity = state.SelectedEggTag
	local color = CONFIG.RarityColors[rarity]

	local highlight = Instance.new("Highlight")
	highlight.Adornee = egg
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 0.75
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = folder

	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = part
	billboard.Size = UDim2.fromOffset(120, 25)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = folder

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = rarity
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBold
	label.TextSize = 10
	label.Parent = billboard
end

local function getPlayerColor(player: Player): Color3
	if player.Team == LocalPlayer.Team then
		return CONFIG.TeamColors.Friendly
	end

	if player.Team then
		return CONFIG.TeamColors.Enemy
	end

	return CONFIG.TeamColors.Neutral
end

local function createPlayerESP(player: Player)
	if player == LocalPlayer then
		return
	end

	local character = player.Character

	if not character then
		return
	end

	local root =
		character:FindFirstChild("HumanoidRootPart")

	local humanoid =
		character:FindFirstChildOfClass("Humanoid")

	if not root or not humanoid then
		return
	end

	local folder = ensureESPFolder()
	local color = getPlayerColor(player)

	local highlight = Instance.new("Highlight")
	highlight.Adornee = character
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 0.8
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = folder

	local distance = 0
	local _, _, localRoot = getCharacterObjects()

	if localRoot then
		distance =
			math.floor((root.Position - localRoot.Position).Magnitude)
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = root
	billboard.Size = UDim2.fromOffset(150, 42)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = folder

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 10
	label.Text = string.format(
		"%s\n%d studs • HP %d",
		player.DisplayName,
		distance,
		math.floor(humanoid.Health)
	)
	label.Parent = billboard
end

local function updateESP()
	clearESP()

	if state.EggESP then
		for _, egg in ipairs(getEggTargets()) do
			createEggESP(egg)
		end
	end

	if state.PlayerESP then
		for _, player in ipairs(Players:GetPlayers()) do
			createPlayerESP(player)
		end
	end
end

local function setESP(enabled: boolean, playerMode: boolean)
	if playerMode then
		state.PlayerESP = enabled
	else
		state.EggESP = enabled
	end

	cleanupFeature("ESP")

	if not state.PlayerESP and not state.EggESP then
		clearESP()
		return
	end

	local thread = task.spawn(function()
		while state.PlayerESP or state.EggESP do
			updateESP()
			task.wait(CONFIG.ESPUpdateInterval)
		end
	end)

	addTask("ESP", thread)

	notify(
		playerMode
			and "Player ESP updated."
			or "Egg ESP updated."
	)
end

--========================================================
-- MOBILE FLY CONTROLS
--========================================================

local flightGui = Instance.new("ScreenGui")
flightGui.Name = "MrDonFlightControls"
flightGui.ResetOnSpawn = false
flightGui.Parent = PlayerGui

local function makeFlightButton(
	textValue: string,
	position: UDim2
): TextButton
	local button = Instance.new("TextButton")

	button.Size = UDim2.fromOffset(48, 48)
	button.Position = position
	button.AnchorPoint = Vector2.new(1, 1)
	button.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	button.BackgroundTransparency = 0.35
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = textValue
	button.TextSize = 19
	button.Font = Enum.Font.GothamBold
	button.Visible = false
	button.Parent = flightGui

	Instance.new("UICorner", button).CornerRadius =
		UDim.new(1, 0)

	return button
end

local upButton = makeFlightButton(
	"▲",
	UDim2.new(1, -24, 1, -150)
)

local downButton = makeFlightButton(
	"▼",
	UDim2.new(1, -24, 1, -94)
)

upHeld = false
downHeld = false

upButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1 then
		upHeld = true
	end
end)

upButton.InputEnded:Connect(function()
	upHeld = false
end)

downButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1 then
		downHeld = true
	end
end)

downButton.InputEnded:Connect(function()
	downHeld = false
end)

--========================================================
-- UI FACTORIES
--========================================================

local function makeToggle(
	name: string,
	initial: boolean,
	callback: (boolean) -> ()
)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, 38)
	row.BackgroundColor3 = Color3.fromRGB(30, 31, 37)
	row.Parent = content

	Instance.new("UICorner", row).CornerRadius =
		UDim.new(0, 7)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -65, 1, 0)
	label.Position = UDim2.fromOffset(10, 0)
	label.BackgroundTransparency = 1
	label.Text = name
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 11
	label.Parent = row

	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(45, 25)
	button.Position = UDim2.new(1, -52, 0.5, -12)
	button.Text = initial and "ON" or "OFF"
	button.TextColor3 = Color3.new(1, 1, 1)
	button.BackgroundColor3 =
		initial
			and Color3.fromRGB(45, 130, 80)
			or Color3.fromRGB(65, 65, 72)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 10
	button.Parent = row

	Instance.new("UICorner", button).CornerRadius =
		UDim.new(0, 6)

	local enabled = initial

	button.Activated:Connect(function()
		enabled = not enabled

		button.Text = enabled and "ON" or "OFF"
		button.BackgroundColor3 =
			enabled
				and Color3.fromRGB(45, 130, 80)
				or Color3.fromRGB(65, 65, 72)

		callback(enabled)
	end)

	return row
end

local function makeNumberInput(
	name: string,
	minimum: number,
	maximum: number,
	value: number,
	callback: (number) -> ()
)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, 46)
	row.BackgroundColor3 = Color3.fromRGB(30, 31, 37)
	row.Parent = content

	Instance.new("UICorner", row).CornerRadius =
		UDim.new(0, 7)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.44, 0, 1, 0)
	label.Position = UDim2.fromOffset(10, 0)
	label.BackgroundTransparency = 1
	label.Text = name
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 11
	label.Parent = row

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0.47, 0, 0, 27)
	box.Position = UDim2.new(0.48, 0, 0.5, -13)
	box.Text = tostring(value)
	box.ClearTextOnFocus = false
	box.TextColor3 = Color3.new(1, 1, 1)
	box.BackgroundColor3 = Color3.fromRGB(45, 46, 53)
	box.Font = Enum.Font.Gotham
	box.TextSize = 11
	box.Parent = row

	Instance.new("UICorner", box).CornerRadius =
		UDim.new(0, 6)

	box.FocusLost:Connect(function()
		local numberValue = tonumber(box.Text)

		if not numberValue then
			box.Text = tostring(value)
			notify(name .. ": invalid number.")
			return
		end

		numberValue = math.clamp(
			numberValue,
			minimum,
			maximum
		)

		value = numberValue
		box.Text = tostring(numberValue)
		callback(numberValue)
	end)
end

local function makeEggSelector()
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, 82)
	row.BackgroundColor3 = Color3.fromRGB(30, 31, 37)
	row.Parent = content

	Instance.new("UICorner", row).CornerRadius =
		UDim.new(0, 7)

	local search = Instance.new("TextBox")
	search.Size = UDim2.new(1, -20, 0, 27)
	search.Position = UDim2.fromOffset(10, 7)
	search.PlaceholderText = "Search egg type..."
	search.Text = ""
	search.TextColor3 = Color3.new(1, 1, 1)
	search.BackgroundColor3 = Color3.fromRGB(45, 46, 53)
	search.Font = Enum.Font.Gotham
	search.TextSize = 11
	search.Parent = row

	Instance.new("UICorner", search).CornerRadius =
		UDim.new(0, 6)

	local optionFrame = Instance.new("Frame")
	optionFrame.Size = UDim2.new(1, -20, 0, 34)
	optionFrame.Position = UDim2.fromOffset(10, 40)
	optionFrame.BackgroundTransparency = 1
	optionFrame.Parent = row

	local optionLayout = Instance.new("UIListLayout")
	optionLayout.FillDirection = Enum.FillDirection.Horizontal
	optionLayout.Padding = UDim.new(0, 5)
	optionLayout.Parent = optionFrame

	for _, tag in ipairs(CONFIG.EggTags) do
		local button = Instance.new("TextButton")

		button.Size = UDim2.fromOffset(98, 27)
		button.Text = tag:gsub("Egg", "")
		button.TextColor3 = Color3.new(1, 1, 1)
		button.BackgroundColor3 = CONFIG.RarityColors[tag]
		button.BackgroundTransparency = 0.25
		button.Font = Enum.Font.GothamBold
		button.TextSize = 9
		button.Parent = optionFrame

		Instance.new("UICorner", button).CornerRadius =
			UDim.new(0, 6)

		button.Activated:Connect(function()
			state.SelectedEggTag = tag
			search.Text = tag
			notify("Target: " .. tag)
		end)
	end

	search:GetPropertyChangedSignal("Text"):Connect(function()
		local filter = string.lower(search.Text)

		for _, button in ipairs(optionFrame:GetChildren()) do
			if button:IsA("TextButton") then
				button.Visible =
					filter == ""
					or string.find(
						string.lower(button.Text),
						filter,
						1,
						true
					) ~= nil
			end
		end
	end)
end

--========================================================
-- UI CREATION
--========================================================

makeToggle("Fix Lag", false, setFixLag)
uiPause()

makeToggle("Full Bright", false, setFullBright)
uiPause()

makeNumberInput(
	"Walk Speed",
	CONFIG.WalkSpeed.Min,
	CONFIG.WalkSpeed.Max,
	state.WalkSpeed,
	function(value)
		state.WalkSpeed = value

		if state.SpeedWalk then
			applyWalkSpeed()
		end
	end
)
uiPause()

makeNumberInput(
	"Jump",
	CONFIG.Jump.Min,
	CONFIG.Jump.Max,
	state.Jump,
	function(value)
		state.Jump = value

		if state.HighJump then
			applyJump()
		end
	end
)
uiPause()

makeNumberInput(
	"Fly Speed",
	CONFIG.FlySpeed.Min,
	CONFIG.FlySpeed.Max,
	state.FlySpeed,
	function(value)
		state.FlySpeed = value
	end
)
uiPause()

makeNumberInput(
	"Auto-Farm Delay",
	CONFIG.AutoFarmDelay.Min,
	CONFIG.AutoFarmDelay.Max,
	state.AutoFarmDelay,
	function(value)
		state.AutoFarmDelay = value
	end
)
uiPause()

makeEggSelector()
uiPause()

makeToggle("Speed Walk", false, setSpeedWalk)
uiPause()

makeToggle("High Jump", false, setHighJump)
uiPause()

makeToggle("Fly", false, setFly)
uiPause()

makeToggle("Auto Catch", false, setAutoCatch)
uiPause()

makeToggle("Noclip", false, setManualNoclip)
uiPause()

makeToggle("Egg ESP", false, function(enabled)
	setESP(enabled, false)
end)
uiPause()

makeToggle("Player ESP", false, function(enabled)
	setESP(enabled, true)
end)
uiPause()

makeToggle("Anti-AFK", false, setAntiAFK)

--========================================================
-- DRAGGING
--========================================================

local dragging = false
local dragStart = Vector2.zero
local startPosition = main.Position

title.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		dragging = true
		dragStart = input.Position
		startPosition = main.Position
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not dragging then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local delta = input.Position - dragStart

	main.Position = UDim2.new(
		startPosition.X.Scale,
		startPosition.X.Offset + delta.X,
		startPosition.Y.Scale,
		startPosition.Y.Offset + delta.Y
	)
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

--========================================================
-- MENU CONTROLS
--========================================================

closeButton.Activated:Connect(function()
	main.Visible = false
	state.MenuVisible = false
end)

minimizeButton.Activated:Connect(function()
	state.Collapsed = not state.Collapsed
	content.Visible = not state.Collapsed
	status.Visible = not state.Collapsed

	main.Size =
		state.Collapsed
			and UDim2.fromOffset(360, 48)
			or UDim2.fromOffset(360, 430)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.KeyCode == CONFIG.MenuToggleKey then
		state.MenuVisible = not state.MenuVisible
		main.Visible = state.MenuVisible
	end
end)

--========================================================
-- CLEANUP
--========================================================

local shuttingDown = false

local function cleanup()
	if shuttingDown then
		return
	end

	shuttingDown = true

	state.FixLag = false
	state.FullBright = false
	state.SpeedWalk = false
	state.HighJump = false
	state.Fly = false
	state.AutoCatch = false
	state.Noclip = false
	state.EggESP = false
	state.PlayerESP = false
	state.AntiAFK = false

	cleanupFeature("FixLag")
	cleanupFeature("AntiAFK")
	cleanupFeature("ESP")
	cleanupFeature("AutoCatch")
	cleanupFeature("FlyPhysics")
	cleanupFeature("CharacterLifecycle")

	if noclipStepped then
		noclipStepped:Disconnect()
		noclipStepped = nil
	end

	if flyVelocity then
		flyVelocity:Destroy()
		flyVelocity = nil
	end

	if flyGyro then
		flyGyro:Destroy()
		flyGyro = nil
	end

	disableFixLag()
	disableFullBright()

	disconnectFeature("CharacterLifecycle")

	if gui.Parent then
		gui:Destroy()
	end

	if flightGui.Parent then
		flightGui:Destroy()
	end
end

script.Destroying:Connect(cleanup)

updateStatus()
notify("Menu loaded; features remain dormant until enabled.")
