--!strict
-- Place in: StarterPlayer > StarterPlayerScripts
-- Client-only utility menu for an experience you own.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

--==================================================
-- CONFIGURATION
--==================================================

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

	EnemyHeight = 6,
	LootStoppingDistance = 5,
	TweenSpeed = 70,
	TargetSearchInterval = 0.25,

	FallbackEnemyFolder = "Enemies",

	LootTags = {
		"LootChest",
		"DevilFruit",
	},

	ESP = {
		EnemyTeamOnly = false,
		Name = true,
		Health = true,
		Distance = true,

		FriendlyColor = Color3.fromRGB(80, 200, 120),
		EnemyColor = Color3.fromRGB(255, 90, 90),
	},

	FullBright = {
		Brightness = 2,
		Ambient = Color3.fromRGB(170, 170, 170),
		OutdoorAmbient = Color3.fromRGB(170, 170, 170),
		ExposureCompensation = 0.5,
		GlobalShadows = false,
	},
}

--==================================================
-- STATE
--==================================================

local State = {
	MenuOpen = true,

	FixLag = false,
	FullBright = false,
	SpeedWalk = false,
	HighJump = false,
	AutoFarm = false,
	AutoLoot = false,
	Noclip = false,
	PlayerESP = false,

	WalkSpeed = CONFIG.WalkSpeed.Default,
	JumpValue = CONFIG.Jump.Default,

	SelectedEnemy = nil,
	SelectedLoot = {},

	AutoMovementOwner = nil,

	NoclipRequests = {},
	Connections = {},
	FeatureConnections = {},
	ActiveTween = nil,

	Character = nil,
	Humanoid = nil,
	RootPart = nil,
}

--==================================================
-- CLEANUP
--==================================================

local function disconnect(connection)
	if connection and connection.Connected then
		connection:Disconnect()
	end
end

local function cleanupConnections(list)
	for _, connection in pairs(list) do
		disconnect(connection)
	end

	table.clear(list)
end

local function cancelTween()
	if State.ActiveTween then
		State.ActiveTween:Cancel()
		State.ActiveTween = nil
	end
end

--==================================================
-- CHARACTER
--==================================================

local function refreshCharacter(character)
	State.Character = character
	State.Humanoid = character:WaitForChild("Humanoid", 5)
	State.RootPart = character:WaitForChild("HumanoidRootPart", 5)

	if State.Humanoid then
		if State.SpeedWalk then
			State.Humanoid.WalkSpeed = State.WalkSpeed
		end

		if State.HighJump then
			if State.Humanoid.UseJumpPower then
				State.Humanoid.JumpPower = State.JumpValue
			else
				State.Humanoid.JumpHeight = State.JumpValue
			end
		end
	end

	if State.Noclip then
		State.NoclipRequests.Manual = true
	end
end

local function setupCharacter(character)
	cancelTween()
	refreshCharacter(character)

	table.insert(State.Connections, character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			cancelTween()
		end
	end))
end

if LocalPlayer.Character then
	task.spawn(setupCharacter, LocalPlayer.Character)
end

table.insert(
	State.Connections,
	LocalPlayer.CharacterAdded:Connect(setupCharacter)
)

--==================================================
-- NOTIFICATIONS
--==================================================

local notificationGui = Instance.new("ScreenGui")
notificationGui.Name = "UtilityNotifications"
notificationGui.ResetOnSpawn = false
notificationGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local notificationLayout = Instance.new("UIListLayout")
notificationLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
notificationLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
notificationLayout.Padding = UDim.new(0, 6)
notificationLayout.Parent = notificationGui

local function notify(message)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(280, 36)
	label.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	label.BackgroundTransparency = 0.05
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = 14
	label.Font = Enum.Font.Gotham
	label.Text = message
	label.Parent = notificationGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = label

	task.delay(2.5, function()
		if label.Parent then
			label:Destroy()
		end
	end)
end

--==================================================
-- NOCLIP
--==================================================

local noclipOriginals = {}

local function hasNoclipRequest()
	for _, requested in pairs(State.NoclipRequests) do
		if requested then
			return true
		end
	end

	return false
end

local function restoreNoclip()
	for part, original in pairs(noclipOriginals) do
		if part.Parent then
			part.CanCollide = original
		end
	end

	table.clear(noclipOriginals)
end

local function applyNoclip()
	if not State.Character then
		return
	end

	for _, object in ipairs(State.Character:GetDescendants()) do
		if object:IsA("BasePart") then
			if noclipOriginals[object] == nil then
				noclipOriginals[object] = object.CanCollide
			end

			object.CanCollide = false
		end
	end
end

local function updateNoclip()
	if hasNoclipRequest() then
		applyNoclip()
	else
		restoreNoclip()
	end
end

local function requestNoclip(owner, enabled)
	if enabled then
		State.NoclipRequests[owner] = true
	else
		State.NoclipRequests[owner] = nil
	end

	updateNoclip()
end

table.insert(
	State.Connections,
	RunService.Stepped:Connect(function()
		if hasNoclipRequest() then
			applyNoclip()
		end
	end)
)

--==================================================
-- FIX LAG
--==================================================

local visualOriginals = {}

local function rememberProperty(instance, property)
	if not visualOriginals[instance] then
		visualOriginals[instance] = {}
	end

	if visualOriginals[instance][property] == nil then
		visualOriginals[instance][property] = instance[property]
	end
end

local function simplifyVisual(instance)
	if instance:IsA("ParticleEmitter")
		or instance:IsA("Trail")
		or instance:IsA("Beam")
		or instance:IsA("Smoke")
		or instance:IsA("Fire")
		or instance:IsA("Sparkles") then

		rememberProperty(instance, "Enabled")
		instance.Enabled = false

	elseif instance:IsA("PointLight")
		or instance:IsA("SpotLight")
		or instance:IsA("SurfaceLight") then

		rememberProperty(instance, "Enabled")
		instance.Enabled = false
	end
end

local function enableFixLag()
	for _, object in ipairs(game:GetDescendants()) do
		simplifyVisual(object)
	end
end

local function disableFixLag()
	for instance, properties in pairs(visualOriginals) do
		if instance.Parent then
			for property, value in pairs(properties) do
				instance[property] = value
			end
		end
	end

	table.clear(visualOriginals)
end

local function setFixLag(enabled)
	State.FixLag = enabled

	if enabled then
		enableFixLag()
		notify("Fix Lag enabled")
	else
		disableFixLag()
		notify("Fix Lag disabled")
	end
end

--==================================================
-- FULL BRIGHT
--==================================================

local lightingOriginals = {}

local function enableFullBright()
	lightingOriginals.Brightness = Lighting.Brightness
	lightingOriginals.Ambient = Lighting.Ambient
	lightingOriginals.OutdoorAmbient = Lighting.OutdoorAmbient
	lightingOriginals.ExposureCompensation = Lighting.ExposureCompensation
	lightingOriginals.GlobalShadows = Lighting.GlobalShadows

	Lighting.Brightness = CONFIG.FullBright.Brightness
	Lighting.Ambient = CONFIG.FullBright.Ambient
	Lighting.OutdoorAmbient = CONFIG.FullBright.OutdoorAmbient
	Lighting.ExposureCompensation = CONFIG.FullBright.ExposureCompensation
	Lighting.GlobalShadows = CONFIG.FullBright.GlobalShadows
end

local function disableFullBright()
	for property, value in pairs(lightingOriginals) do
		Lighting[property] = value
	end

	table.clear(lightingOriginals)
end

local function setFullBright(enabled)
	State.FullBright = enabled

	if enabled then
		enableFullBright()
		notify("Full Bright enabled")
	else
		disableFullBright()
		notify("Full Bright disabled")
	end
end

--==================================================
-- MOVEMENT
--==================================================

local function applySpeed()
	if State.Humanoid and State.SpeedWalk then
		State.Humanoid.WalkSpeed = State.WalkSpeed
	end
end

local function disableSpeed()
	if State.Humanoid then
		State.Humanoid.WalkSpeed = CONFIG.WalkSpeed.Default
	end
end

local function applyJump()
	if not State.Humanoid or not State.HighJump then
		return
	end

	if State.Humanoid.UseJumpPower then
		State.Humanoid.JumpPower = State.JumpValue
	else
		State.Humanoid.JumpHeight = State.JumpValue
	end
end

local function disableJump()
	if not State.Humanoid then
		return
	end

	if State.Humanoid.UseJumpPower then
		State.Humanoid.JumpPower = CONFIG.Jump.Default
	else
		State.Humanoid.JumpHeight = CONFIG.Jump.Default
	end
end

--==================================================
-- TARGET HELPERS
--==================================================

local function getModelRoot(model)
	if model:IsA("BasePart") then
		return model
	end

	if model:IsA("Model") then
		if model.PrimaryPart then
			return model.PrimaryPart
		end

		return model:FindFirstChild("HumanoidRootPart")
			or model:FindFirstChildWhichIsA("BasePart")
	end

	return nil
end

local function isLivingEnemy(model)
	if not model:IsA("Model") then
		return false
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function collectEnemies()
	local results = {}

	for _, enemy in ipairs(CollectionService:GetTagged("FarmableEnemy")) do
		if isLivingEnemy(enemy) then
			table.insert(results, enemy)
		end
	end

	if #results > 0 then
		return results
	end

	local folder = workspace:FindFirstChild(CONFIG.FallbackEnemyFolder)

	if folder then
		for _, object in ipairs(folder:GetChildren()) do
			if isLivingEnemy(object) then
				table.insert(results, object)
			end
		end
	end

	return results
end

local function findNearestEnemy(enemyName)
	if not State.RootPart then
		return nil
	end

	local nearest
	local nearestDistance = math.huge

	for _, enemy in ipairs(collectEnemies()) do
		if enemy.Name == enemyName then
			local root = getModelRoot(enemy)

			if root then
				local distance = (root.Position - State.RootPart.Position).Magnitude

				if distance < nearestDistance then
					nearest = enemy
					nearestDistance = distance
				end
			end
		end
	end

	return nearest
end

--==================================================
-- AUTOMATIC MOVEMENT
--==================================================

local function stopAutomaticMovement()
	cancelTween()
	requestNoclip("AutoMovement", false)
	State.AutoMovementOwner = nil
end

local function claimAutomaticMovement(owner)
	if State.AutoMovementOwner == owner then
		return true
	end

	if State.AutoMovementOwner then
		return false
	end

	State.AutoMovementOwner = owner
	requestNoclip("AutoMovement", true)

	return true
end

local function moveNear(position)
	if not State.RootPart then
		return false
	end

	cancelTween()

	local distance = (position - State.RootPart.Position).Magnitude

	if distance < 2 then
		return true
	end

	local duration = math.max(distance / CONFIG.TweenSpeed, 0.05)

	local tween = TweenService:Create(
		State.RootPart,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{CFrame = CFrame.new(position)}
	)

	State.ActiveTween = tween
	tween:Play()

	local completed = tween.Completed:Wait()

	if State.ActiveTween == tween then
		State.ActiveTween = nil
	end

	return completed == Enum.PlaybackState.Completed
end

--==================================================
-- COMBAT INTEGRATION POINT
--==================================================

local function attackTarget(target)
	-- Intentionally does not fabricate combat calls.
	--
	-- Connect your experience's legitimate combat mechanism here.
	-- Example:
	-- CombatController:Attack(target)
	--
	-- No undocumented RemoteEvent or Blox Fruits-specific
	-- exploit interface is used.
	if not target or not target.Parent then
		return false
	end

	return true
end

--==================================================
-- AUTO FARM
--==================================================

local function autoFarmStep()
	if not State.AutoFarm or State.AutoLoot then
		return
	end

	if not State.SelectedEnemy then
		return
	end

	if not claimAutomaticMovement("AutoFarm") then
		return
	end

	local target = findNearestEnemy(State.SelectedEnemy)

	if not target then
		return
	end

	local targetRoot = getModelRoot(target)

	if not targetRoot then
		return
	end

	local destination =
		targetRoot.Position + Vector3.new(0, CONFIG.EnemyHeight, 0)

	local lookAt = CFrame.lookAt(destination, targetRoot.Position)

	if State.RootPart then
		State.RootPart.CFrame = lookAt
	end

	moveNear(destination)

	if State.AutoFarm and target.Parent and isLivingEnemy(target) then
		attackTarget(target)
	end
end

local function setAutoFarm(enabled)
	if enabled then
		State.AutoLoot = false
		State.AutoFarm = true
		stopAutomaticMovement()

		if not State.SelectedEnemy then
			State.AutoFarm = false
			notify("Select an enemy first")
			return
		end

		notify("Auto Farm enabled")
	else
		State.AutoFarm = false
		stopAutomaticMovement()
		notify("Auto Farm disabled")
	end
end

--==================================================
-- LOOT
--==================================================

local function collectLoot(item)
	if not item or not item.Parent then
		return false
	end

	local prompt = item:FindFirstChildWhichIsA(
		"ProximityPrompt",
		true
	)

	if prompt and prompt.Enabled then
		-- Legitimate interaction point.
		-- The actual collection behavior belongs to the game's
		-- existing interaction system.
		return true
	end

	local detector = item:FindFirstChildWhichIsA(
		"ClickDetector",
		true
	)

	if detector then
		return true
	end

	return false
end

local function isSelectedLoot(item)
	for tag, selected in pairs(State.SelectedLoot) do
		if selected and CollectionService:HasTag(item, tag) then
			return true
		end
	end

	return false
end

local function findNearestLoot()
	if not State.RootPart then
		return nil
	end

	local nearest
	local nearestDistance = math.huge

	for _, tag in ipairs(CONFIG.LootTags) do
		for _, item in ipairs(CollectionService:GetTagged(tag)) do
			if item:IsDescendantOf(workspace) and isSelectedLoot(item) then
				local root = getModelRoot(item)

				if root then
					local distance =
						(root.Position - State.RootPart.Position).Magnitude

					if distance < nearestDistance then
						nearest = item
						nearestDistance = distance
					end
				end
			end
		end
	end

	return nearest
end

local function autoLootStep()
	if not State.AutoLoot or State.AutoFarm then
		return
	end

	if not claimAutomaticMovement("AutoLoot") then
		return
	end

	local item = findNearestLoot()

	if not item then
		return
	end

	local root = getModelRoot(item)

	if not root then
		return
	end

	local offset = Vector3.new(0, 0, CONFIG.LootStoppingDistance)
	local destination = root.Position + offset

	moveNear(destination)

	if State.AutoLoot and item.Parent then
		collectLoot(item)
	end
end

local function setAutoLoot(enabled)
	if enabled then
		State.AutoFarm = false
		State.AutoLoot = true
		stopAutomaticMovement()

		if next(State.SelectedLoot) == nil then
			State.AutoLoot = false
			notify("Select at least one loot type")
			return
		end

		notify("Auto Loot enabled")
	else
		State.AutoLoot = false
		stopAutomaticMovement()
		notify("Auto Loot disabled")
	end
end

--==================================================
-- PLAYER ESP
--==================================================

local espObjects = {}

local function removeESP(player)
	local data = espObjects[player]

	if not data then
		return
	end

	for _, object in pairs(data.Objects) do
		if object and object.Parent then
			object:Destroy()
		end
	end

	for _, connection in pairs(data.Connections) do
		disconnect(connection)
	end

	espObjects[player] = nil
end

local function createESP(player)
	if player == LocalPlayer then
		return
	end

	removeESP(player)

	local data = {
		Objects = {},
		Connections = {},
	}

	espObjects[player] = data

	local function attach(character)
		removeESP(player)
		espObjects[player] = data

		local highlight = Instance.new("Highlight")
		highlight.Name = "UtilityESP"
		highlight.FillTransparency = 1
		highlight.OutlineTransparency = 0
		highlight.Parent = character

		table.insert(data.Objects, highlight)

		local head = character:FindFirstChild("Head")

		if not head then
			return
		end

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "UtilityESPInfo"
		billboard.Size = UDim2.fromOffset(160, 70)
		billboard.StudsOffset = Vector3.new(0, 3, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = head

		table.insert(data.Objects, billboard)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Font = Enum.Font.Gotham
		label.TextSize = 12
		label.TextWrapped = true
		label.Parent = billboard

		table.insert(data.Objects, label)

		table.insert(data.Connections, RunService.Heartbeat:Connect(function()
			if not State.PlayerESP or not character.Parent then
				return
			end

			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart")

			if not humanoid or not root then
				return
			end

			local localRoot = State.RootPart

			if localRoot then
				local distance =
					(root.Position - localRoot.Position).Magnitude

				local healthText = ""

				if CONFIG.ESP.Health then
					healthText = string.format(
						"\nHP: %.0f/%.0f",
						humanoid.Health,
						humanoid.MaxHealth
					)
				end

				local distanceText = ""

				if CONFIG.ESP.Distance then
					distanceText = string.format(
						"\n%.0f studs",
						distance
					)
				end

				label.Text = player.Name .. healthText .. distanceText
			end

			local sameTeam =
				LocalPlayer.Team ~= nil
				and player.Team == LocalPlayer.Team

			if sameTeam then
				highlight.OutlineColor = CONFIG.ESP.FriendlyColor
			else
				highlight.OutlineColor = CONFIG.ESP.EnemyColor
			end

			if CONFIG.ESP.EnemyTeamOnly and sameTeam then
				highlight.Enabled = false
				billboard.Enabled = false
			else
				highlight.Enabled = true
				billboard.Enabled = true
			end
		end))
	end

	if player.Character then
		task.spawn(attach, player.Character)
	end

	table.insert(
		State.Connections,
		player.CharacterAdded:Connect(attach)
	)
end

local function setPlayerESP(enabled)
	State.PlayerESP = enabled

	if enabled then
		for _, player in ipairs(Players:GetPlayers()) do
			createESP(player)
		end

		notify("Player ESP enabled")
	else
		for player in pairs(espObjects) do
			removeESP(player)
		end

		notify("Player ESP disabled")
	end
end

table.insert(
	State.Connections,
	Players.PlayerAdded:Connect(function(player)
		if State.PlayerESP then
			createESP(player)
		end
	end)
)

table.insert(
	State.Connections,
	Players.PlayerRemoving:Connect(removeESP)
)

--==================================================
-- GUI
--==================================================

local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local oldGui = playerGui:FindFirstChild("MrDonUtilityMenu")

if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "MrDonUtilityMenu"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(340, 430)
main.Position = UDim2.new(0.5, -170, 0.5, -215)
main.BackgroundColor3 = Color3.fromRGB(24, 24, 29)
main.BorderSizePixel = 0
main.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = main

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -90, 0, 40)
title.Position = UDim2.fromOffset(12, 0)
title.BackgroundTransparency = 1
title.Text = "Fruit Utility"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = main

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromOffset(32, 30)
closeButton.Position = UDim2.new(1, -38, 0, 5)
closeButton.Text = "×"
closeButton.TextSize = 20
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.BackgroundTransparency = 1
closeButton.Parent = main

local minimizeButton = Instance.new("TextButton")
minimizeButton.Size = UDim2.fromOffset(32, 30)
minimizeButton.Position = UDim2.new(1, -72, 0, 5)
minimizeButton.Text = "−"
minimizeButton.TextSize = 20
minimizeButton.TextColor3 = Color3.new(1, 1, 1)
minimizeButton.BackgroundTransparency = 1
minimizeButton.Parent = main

local content = Instance.new("ScrollingFrame")
content.Size = UDim2.new(1, -20, 1, -55)
content.Position = UDim2.fromOffset(10, 45)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 4
content.CanvasSize = UDim2.fromOffset(0, 0)
content.Parent = main

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = content

layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	content.CanvasSize = UDim2.fromOffset(
		0,
		layout.AbsoluteContentSize.Y + 10
	)
end)

local function createToggle(text, callback)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, -4, 0, 34)
	button.BackgroundColor3 = Color3.fromRGB(38, 38, 45)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.Gotham
	button.TextSize = 13
	button.Text = text .. ": OFF"
	button.Parent = content

	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)

	local enabled = false

	button.Activated:Connect(function()
		enabled = not enabled
		button.Text = text .. (enabled and ": ON" or ": OFF")
		callback(enabled)
	end)

	return button
end

local function createNumberBox(text, defaultValue, callback)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -4, 0, 38)
	frame.BackgroundColor3 = Color3.fromRGB(38, 38, 45)
	frame.Parent = content

	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.55, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Gotham
	label.TextSize = 12
	label.Parent = frame

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0.4, 0, 0, 28)
	box.Position = UDim2.new(0.58, 0, 0.5, -14)
	box.Text = tostring(defaultValue)
	box.ClearTextOnFocus = false
	box.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
	box.TextColor3 = Color3.new(1, 1, 1)
	box.Font = Enum.Font.Gotham
	box.TextSize = 12
	box.Parent = frame

	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 5)

	box.FocusLost:Connect(function()
		local value = tonumber(box.Text)

		if not value then
			box.Text = tostring(defaultValue)
			notify("Invalid number")
			return
		end

		callback(value)
	end)
end

createToggle("Fix Lag", setFixLag)
createToggle("Full Bright", setFullBright)

createNumberBox(
	"Walk Speed",
	State.WalkSpeed,
	function(value)
		value = math.clamp(
			value,
			CONFIG.WalkSpeed.Min,
			CONFIG.WalkSpeed.Max
		)

		State.WalkSpeed = value
		applySpeed()
	end
)

createNumberBox(
	"Jump",
	State.JumpValue,
	function(value)
		value = math.clamp(
			value,
			CONFIG.Jump.Min,
			CONFIG.Jump.Max
		)

		State.JumpValue = value
		applyJump()
	end
)

createToggle("Speed Walk", function(enabled)
	State.SpeedWalk = enabled

	if enabled then
		applySpeed()
	else
		disableSpeed()
	end
end)

createToggle("High Jump", function(enabled)
	State.HighJump = enabled

	if enabled then
		applyJump()
	else
		disableJump()
	end
end)

createToggle("Noclip", function(enabled)
	State.Noclip = enabled
	requestNoclip("Manual", enabled)
end)

createToggle("Player ESP", setPlayerESP)

createToggle("Auto Farm", setAutoFarm)
createToggle("Auto Loot", setAutoLoot)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -4, 0, 32)
status.BackgroundTransparency = 1
status.TextColor3 = Color3.fromRGB(180, 180, 180)
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextWrapped = true
status.Text = "Auto Farm: OFF | Auto Loot: OFF"
status.Parent = content

--==================================================
-- DRAGGING
--==================================================

local dragging = false
local dragStart
local startPosition

local function updateDrag(input)
	local delta = input.Position - dragStart

	main.Position = UDim2.new(
		startPosition.X.Scale,
		startPosition.X.Offset + delta.X,
		startPosition.Y.Scale,
		startPosition.Y.Offset + delta.Y
	)
end

title.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		dragging = true
		dragStart = input.Position
		startPosition = main.Position
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging
		and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then

		updateDrag(input)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		dragging = false
	end
end)

--==================================================
-- MENU CONTROLS
--==================================================

local function setMenuVisible(visible)
	State.MenuOpen = visible
	main.Visible = visible
end

closeButton.Activated:Connect(function()
	setMenuVisible(false)
end)

minimizeButton.Activated:Connect(function()
	content.Visible = not content.Visible
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.KeyCode == CONFIG.MenuToggleKey then
		setMenuVisible(not State.MenuOpen)
	end
end)

--==================================================
-- AUTOMATION LOOP
--==================================================

local automationRunning = true

task.spawn(function()
	while automationRunning do
		if State.AutoFarm then
			autoFarmStep()
		elseif State.AutoLoot then
			autoLootStep()
		else
			stopAutomaticMovement()
		end

		status.Text =
			"Auto Farm: "
			.. (State.AutoFarm and "ON" or "OFF")
			.. " | Auto Loot: "
			.. (State.AutoLoot and "ON" or "OFF")

		task.wait(CONFIG.TargetSearchInterval)
	end
end)

--==================================================
-- NEW VISUAL EFFECTS
--==================================================

table.insert(
	State.Connections,
	game.DescendantAdded:Connect(function(object)
		if State.FixLag then
			simplifyVisual(object)
		end
	end)
)

notify("Utility menu loaded")
