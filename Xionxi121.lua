--!strict
--============================================================
-- MrDon Client Utility - Xionxi 1.2
-- Place in:
-- StarterPlayer > StarterPlayerScripts > LocalScript
--
-- Client-side only.
-- Optional RemoteEvent/RemoteFunction support is provided through the
-- explicit quest-remote configuration below for experiences you own.
-- No executor API or exploit API is required.
--============================================================

--// Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--============================================================
-- CONFIGURATION
--============================================================

local CONFIG = {
	Version = "xionxi1.2.1",

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

	-- Quest givers are discovered by the QuestGiver tag or the
	-- workspace.QuestGivers folder. Each giver may expose:
	-- MinLevel (number), MaxLevel (number), QuestName (string),
	-- and TargetEnemy/EnemyName (string) attributes.
	Automation = {
		AutoClickMin = 1,
		AutoClickMax = 30,
		AutoClickDefault = 8,

		QuestCheckInterval = 0.75,
		QuestAcceptCooldown = 3,
		QuestInteractionDistance = 8,
		QuestVerifyDelay = 0.35,

		QuestGiverFolder = "QuestGivers",
		QuestGiverTag = "QuestGiver",
		QuestMinLevelAttributeNames = {
			"MinLevel",
			"RequiredLevel",
			"LevelMin",
		},
		QuestMaxLevelAttributeNames = {
			"MaxLevel",
			"LevelMax",
		},
		QuestTargetAttributeNames = {
			"TargetEnemy",
			"EnemyName",
			"Target",
		},
		QuestNameAttributeNames = {
			"QuestName",
			"Name",
		},
		QuestIdAttributeNames = {
			"QuestId",
			"QuestID",
			"Id",
		},
		QuestPromptNames = {
			"AcceptQuest",
			"Accept",
			"Quest",
		},

		-- Explicit remote names only. This intentionally does not sniff
		-- arbitrary remotes. For an owned experience, put the actual
		-- quest remote in this allow-list or set QuestRemotePath on the
		-- quest giver (ReplicatedStorage./Workspace./Character. supported).
		QuestRemote = {
			Enabled = true,
			RootName = "Remotes",
			RemotePath = "",
			EventNames = {
				"AcceptQuest",
				"StartQuest",
				"TakeQuest",
				"QuestAccept",
			},
			FunctionNames = {
				"AcceptQuest",
				"StartQuest",
				"TakeQuest",
				"QuestAccept",
			},
			ArgumentMode = "Auto",
		},

		QuestStateAttributeNames = {
			"CurrentQuest",
			"QuestName",
			"Quest",
		},
		QuestStateValueNames = {
			"CurrentQuest",
			"QuestName",
			"Quest",
		},

		EnemyGatherRadius = 70,
		MaxGatheredEnemies = 6,
	},

	FallbackEnemyFolder = "Enemies",

	LootTags = {
		"LootChest",
		"DevilFruit",
	},

	ESP = {
		ShowNames = true,
		ShowHealth = true,
		ShowDistance = true,
		HideSameTeam = false,

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

--============================================================
-- STATE
--============================================================

local State = {
	Running = true,

	MenuOpen = true,
	Minimized = false,

	FixLag = false,
	FullBright = false,
	SpeedWalk = false,
	HighJump = false,
	Noclip = false,
	PlayerESP = false,
	AutoFarm = false,
	AutoLoot = false,

	WalkSpeed = CONFIG.WalkSpeed.Default,
	JumpValue = CONFIG.Jump.Default,

	AutoQuest = true,
	AutoClickRate = CONFIG.Automation.AutoClickDefault,
	NextAttackAt = 0,
	NextQuestCheckAt = 0,

	SelectedEnemy = nil :: string?,
	SelectedLoot = {} :: {[string]: boolean},

	CurrentPlayerLevel = 0,
	ActiveQuestName = nil :: string?,
	ActiveQuestTarget = nil :: string?,
	FarmTarget = nil :: Model?,
	FarmTargets = {} :: {Model},
	LastAcceptedQuestAt = 0,
	LastQuestGiver = nil :: Instance?,
	QuestRemoteStatus = "idle",

	MovementOwner = nil :: string?,

	NoclipRequests = {} :: {[string]: boolean},

	Character = nil :: Model?,
	Humanoid = nil :: Humanoid?,
	RootPart = nil :: BasePart?,

	Connections = {} :: {RBXScriptConnection},
	FeatureConnections = {} :: {[string]: RBXScriptConnection},
	ActiveTween = nil :: Tween?,

	AutoFarmGeneration = 0,
	AutoLootGeneration = 0,
}

--============================================================
-- EXISTING GUI PROTECTION
--============================================================

local existingGui = PlayerGui:FindFirstChild("MrDonUtilityMenu")

if existingGui then
	existingGui:Destroy()
end

--============================================================
-- CONNECTION CLEANUP
--============================================================

local function disconnect(connection: RBXScriptConnection?)
	if connection and connection.Connected then
		connection:Disconnect()
	end
end

local function disconnectFeature(name: string)
	local connection = State.FeatureConnections[name]

	if connection then
		disconnect(connection)
		State.FeatureConnections[name] = nil
	end
end

local function cancelTween()
	if State.ActiveTween then
		State.ActiveTween:Cancel()
		State.ActiveTween = nil
	end
end

--============================================================
-- NOTIFICATION UI
--============================================================

local NotificationGui = Instance.new("ScreenGui")
NotificationGui.Name = "MrDonNotifications"
NotificationGui.ResetOnSpawn = false
NotificationGui.IgnoreGuiInset = true
NotificationGui.Parent = PlayerGui

local NotificationLayout = Instance.new("UIListLayout")
NotificationLayout.Padding = UDim.new(0, 6)
NotificationLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
NotificationLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
NotificationLayout.Parent = NotificationGui

local function notify(message: string)
	local label = Instance.new("TextLabel")

	label.Size = UDim2.fromOffset(280, 34)
	label.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	label.BackgroundTransparency = 0.05
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Gotham
	label.TextSize = 13
	label.Text = message
	label.Parent = NotificationGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = label

	task.delay(2.5, function()
		if label.Parent then
			label:Destroy()
		end
	end)
end

--============================================================
-- CHARACTER MANAGEMENT
--============================================================

local function updateCharacter(character: Model)
	State.Character = character

	State.Humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", 5) :: Humanoid?

	State.RootPart = character:FindFirstChild("HumanoidRootPart")
		or character:WaitForChild("HumanoidRootPart", 5) :: BasePart?

	if State.SpeedWalk and State.Humanoid then
		State.Humanoid.WalkSpeed = State.WalkSpeed
	end

	if State.HighJump and State.Humanoid then
		if State.Humanoid.UseJumpPower then
			State.Humanoid.JumpPower = State.JumpValue
		else
			State.Humanoid.JumpHeight = State.JumpValue
		end
	end
end

local function onCharacterAdded(character: Model)
	cancelTween()

	State.MovementOwner = nil
	State.NoclipRequests.AutoFarm = nil
	State.NoclipRequests.AutoLoot = nil
	State.FarmTarget = nil

	updateCharacter(character)
end

if LocalPlayer.Character then
	task.spawn(updateCharacter, LocalPlayer.Character)
end

table.insert(
	State.Connections,
	LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
)

--============================================================
-- NOCLIP
--============================================================

local OriginalCollision = {} :: {[BasePart]: boolean}

local function noclipRequested(): boolean
	for _, requested in pairs(State.NoclipRequests) do
		if requested then
			return true
		end
	end

	return false
end

local function restoreCollision()
	for part, original in pairs(OriginalCollision) do
		if part.Parent then
			part.CanCollide = original
		end
	end

	table.clear(OriginalCollision)
end

local function applyNoclip()
	local character = State.Character

	if not character then
		return
	end

	for _, object in ipairs(character:GetDescendants()) do
		if object:IsA("BasePart") then
			if OriginalCollision[object] == nil then
				OriginalCollision[object] = object.CanCollide
			end

			object.CanCollide = false
		end
	end
end

local function updateNoclip()
	if noclipRequested() then
		applyNoclip()
	else
		restoreCollision()
	end
end

local function requestNoclip(owner: string, enabled: boolean)
	if enabled then
		State.NoclipRequests[owner] = true
	else
		State.NoclipRequests[owner] = nil
	end

	updateNoclip()
end

-- One shared physics connection.
table.insert(
	State.Connections,
	RunService.Stepped:Connect(function()
		if State.Running and noclipRequested() then
			applyNoclip()
		end
	end)
)

--============================================================
-- FIX LAG
--============================================================

local VisualOriginals = {} :: {
	[Instance]: {[string]: any}
}

local function rememberVisual(instance: Instance, property: string)
	if not VisualOriginals[instance] then
		VisualOriginals[instance] = {}
	end

	if VisualOriginals[instance][property] == nil then
		VisualOriginals[instance][property] = instance[property]
	end
end

local function simplifyVisual(instance: Instance)
	if instance:IsA("ParticleEmitter")
		or instance:IsA("Trail")
		or instance:IsA("Beam")
		or instance:IsA("Smoke")
		or instance:IsA("Fire")
		or instance:IsA("Sparkles") then

		rememberVisual(instance, "Enabled")
		instance.Enabled = false

	elseif instance:IsA("PointLight")
		or instance:IsA("SpotLight")
		or instance:IsA("SurfaceLight") then

		rememberVisual(instance, "Enabled")
		instance.Enabled = false
	end
end

local function enableFixLag()
	for _, object in ipairs(game:GetDescendants()) do
		simplifyVisual(object)
	end
end

local function disableFixLag()
	for instance, properties in pairs(VisualOriginals) do
		if instance.Parent then
			for property, value in pairs(properties) do
				instance[property] = value
			end
		end
	end

	table.clear(VisualOriginals)
end

local function setFixLag(enabled: boolean)
	State.FixLag = enabled

	if enabled then
		enableFixLag()
		notify("Fix Lag enabled")
	else
		disableFixLag()
		notify("Fix Lag disabled")
	end
end

-- Process new visual objects without rescanning Workspace.
table.insert(
	State.Connections,
	game.DescendantAdded:Connect(function(object)
		if State.FixLag then
			simplifyVisual(object)
		end
	end)
)

--============================================================
-- FULL BRIGHT
--============================================================

local LightingOriginals = {} :: {[string]: any}

local function enableFullBright()
	LightingOriginals.Brightness = Lighting.Brightness
	LightingOriginals.Ambient = Lighting.Ambient
	LightingOriginals.OutdoorAmbient = Lighting.OutdoorAmbient
	LightingOriginals.ExposureCompensation = Lighting.ExposureCompensation
	LightingOriginals.GlobalShadows = Lighting.GlobalShadows

	Lighting.Brightness = CONFIG.FullBright.Brightness
	Lighting.Ambient = CONFIG.FullBright.Ambient
	Lighting.OutdoorAmbient = CONFIG.FullBright.OutdoorAmbient
	Lighting.ExposureCompensation = CONFIG.FullBright.ExposureCompensation
	Lighting.GlobalShadows = CONFIG.FullBright.GlobalShadows
end

local function disableFullBright()
	for property, value in pairs(LightingOriginals) do
		Lighting[property] = value
	end

	table.clear(LightingOriginals)
end

local function setFullBright(enabled: boolean)
	State.FullBright = enabled

	if enabled then
		enableFullBright()
		notify("Full Bright enabled")
	else
		disableFullBright()
		notify("Full Bright disabled")
	end
end

--============================================================
-- MOVEMENT SETTINGS
--============================================================

local function applyWalkSpeed()
	if State.Humanoid and State.SpeedWalk then
		State.Humanoid.WalkSpeed = State.WalkSpeed
	end
end

local function disableWalkSpeed()
	if State.Humanoid then
		State.Humanoid.WalkSpeed = CONFIG.WalkSpeed.Default
	end
end

local function applyJump()
	local humanoid = State.Humanoid

	if not humanoid or not State.HighJump then
		return
	end

	if humanoid.UseJumpPower then
		humanoid.JumpPower = State.JumpValue
	else
		humanoid.JumpHeight = State.JumpValue
	end
end

local function disableJump()
	local humanoid = State.Humanoid

	if not humanoid then
		return
	end

	if humanoid.UseJumpPower then
		humanoid.JumpPower = CONFIG.Jump.Default
	else
		humanoid.JumpHeight = CONFIG.Jump.Default
	end
end

--============================================================
-- TARGET HELPERS
--============================================================

local function getRoot(object: Instance): BasePart?
	if object:IsA("BasePart") then
		return object
	end

	if object:IsA("Model") then
		if object.PrimaryPart then
			return object.PrimaryPart
		end

		local root = object:FindFirstChild("HumanoidRootPart")

		if root and root:IsA("BasePart") then
			return root
		end

		local part = object:FindFirstChildWhichIsA("BasePart", true)

		if part then
			return part
		end
	end

	return nil
end

local function isLivingEnemy(object: Instance): boolean
	if not object:IsA("Model") then
		return false
	end

	if not object:IsDescendantOf(workspace) then
		return false
	end

	local humanoid = object:FindFirstChildOfClass("Humanoid")

	return humanoid ~= nil and humanoid.Health > 0
end

local function getEnemies(): {Model}
	local enemies = {}
	local seen = {} :: {[Model]: boolean}

	local function addEnemy(object: Instance)
		if isLivingEnemy(object) and not seen[object] then
			seen[object] = true
			table.insert(enemies, object :: Model)
		end
	end

	for _, object in ipairs(CollectionService:GetTagged("FarmableEnemy")) do
		addEnemy(object)
	end

	local folder = workspace:FindFirstChild(CONFIG.FallbackEnemyFolder)

	if folder then
		for _, object in ipairs(folder:GetDescendants()) do
			if object:IsA("Model") then
				addEnemy(object)
			end
		end
	end

	return enemies
end

local function enemyDistance(enemy: Model): number
	local root = getRoot(enemy)

	if not root or not State.RootPart then
		return math.huge
	end

	return (root.Position - State.RootPart.Position).Magnitude
end

local function findNearestEnemy(name: string?): Model?
	if not State.RootPart then
		return nil
	end

	local nearest: Model?
	local nearestDistance = math.huge

	for _, enemy in ipairs(getEnemies()) do
		if not name or enemy.Name == name then
			local distance = enemyDistance(enemy)

			if distance < nearestDistance then
				nearest = enemy
				nearestDistance = distance
			end
		end
	end

	return nearest
end

local function findGatheredEnemies(
	name: string?,
	anchor: Model
): {Model}
	local anchorRoot = getRoot(anchor)

	if not anchorRoot then
		return {}
	end

	local candidates = {}

	for _, enemy in ipairs(getEnemies()) do
		if (not name or enemy.Name == name) then
			local root = getRoot(enemy)

			if root then
				local distance =
					(root.Position - anchorRoot.Position).Magnitude

				if distance <= CONFIG.Automation.EnemyGatherRadius then
					table.insert(candidates, {
						Enemy = enemy,
						Distance = distance,
					})
				end
			end
		end
	end

	table.sort(candidates, function(a, b)
		return a.Distance < b.Distance
	end)

	local gathered = {}
	local limit = math.min(
		#candidates,
		CONFIG.Automation.MaxGatheredEnemies
	)

	for index = 1, limit do
		table.insert(gathered, candidates[index].Enemy)
	end

	return gathered
end

local function getEnemyNames(): {string}
	local names = {}
	local seen = {}

	for _, enemy in ipairs(getEnemies()) do
		if not seen[enemy.Name] then
			seen[enemy.Name] = true
			table.insert(names, enemy.Name)
		end
	end

	table.sort(names)

	return names
end

--============================================================
-- LOOT
--============================================================

local function isLootSelected(item: Instance): boolean
	for _, tag in ipairs(CONFIG.LootTags) do
		if State.SelectedLoot[tag]
			and CollectionService:HasTag(item, tag) then
			return true
		end
	end

	return false
end

local function findNearestLoot(): Instance?
	if not State.RootPart then
		return nil
	end

	local nearest
	local nearestDistance = math.huge

	for _, tag in ipairs(CONFIG.LootTags) do
		if State.SelectedLoot[tag] then
			for _, item in ipairs(CollectionService:GetTagged(tag)) do
				if item:IsDescendantOf(workspace)
					and isLootSelected(item) then

					local root = getRoot(item)

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
	end

	return nearest
end

--============================================================
-- MOVEMENT OWNER
--============================================================

local function releaseMovement(owner: string)
	if State.MovementOwner == owner then
		State.MovementOwner = nil
		cancelTween()
		requestNoclip(owner, false)
	end
end

local function claimMovement(owner: string): boolean
	if State.MovementOwner
		and State.MovementOwner ~= owner then
		return false
	end

	State.MovementOwner = owner
	requestNoclip(owner, true)

	return true
end

local function moveTo(position: Vector3): boolean
	local root = State.RootPart

	if not root then
		return false
	end

	cancelTween()

	local distance = (position - root.Position).Magnitude

	if distance <= 2 then
		return true
	end

	local duration =
		math.max(distance / CONFIG.TweenSpeed, 0.05)

	local tween = TweenService:Create(
		root,
		TweenInfo.new(
			duration,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.Out
		),
		{
			CFrame = CFrame.new(position),
		}
	)

	State.ActiveTween = tween

	local finished = false

	local connection = tween.Completed:Connect(function()
		finished = true
	end)

	tween:Play()

	while State.Running
		and State.ActiveTween == tween
		and not finished do

		task.wait()
	end

	disconnect(connection)

	if State.ActiveTween == tween then
		State.ActiveTween = nil
	end

	return finished
end

--============================================================
-- SAFE INTEGRATION POINTS
--============================================================

local function getEquippedTool(): Tool?
	local character = State.Character

	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			return child
		end
	end

	return nil
end

local function getNumberValue(instance: Instance): number?
	if instance:IsA("IntValue") or instance:IsA("NumberValue") then
		return instance.Value
	end

	if instance:IsA("StringValue") then
		return tonumber(instance.Value)
	end

	return nil
end

local function getNumberAttribute(
	instance: Instance,
	names: {string}
): number?
	for _, name in ipairs(names) do
		local value = instance:GetAttribute(name)

		if typeof(value) == "number" then
			return value
		end
	end

	return nil
end

local function getValueObject(instance: Instance, name: string): Instance?
	local direct = instance:FindFirstChild(name)

	if direct then
		return direct
	end

	return instance:FindFirstChild(name, true)
end

local function getNumberField(
	instance: Instance,
	names: {string}
): number?
	local attributeValue = getNumberAttribute(instance, names)

	if attributeValue ~= nil then
		return attributeValue
	end

	for _, name in ipairs(names) do
		local valueObject = getValueObject(instance, name)

		if valueObject then
			local value = getNumberValue(valueObject)

			if value ~= nil then
				return value
			end
		end
	end

	return nil
end

local function getStringField(
	instance: Instance,
	names: {string}
): string?
	for _, name in ipairs(names) do
		local attributeValue = instance:GetAttribute(name)

		if typeof(attributeValue) == "string" and attributeValue ~= "" then
			return attributeValue
		end
	end

	for _, name in ipairs(names) do
		local valueObject = getValueObject(instance, name)

		if valueObject and valueObject:IsA("StringValue") then
			if valueObject.Value ~= "" then
				return valueObject.Value
			end
		end
	end

	return nil
end

local function activateQuestPrompt(giver: Instance): boolean
	local prompt: ProximityPrompt?

	for _, preferredName in ipairs(CONFIG.Automation.QuestPromptNames) do
		for _, descendant in ipairs(giver:GetDescendants()) do
			if descendant:IsA("ProximityPrompt")
				and descendant.Name == preferredName
				and descendant.Enabled then

				prompt = descendant
				break
			end
		end

		if prompt then
			break
		end
	end

	if not prompt then
		for _, descendant in ipairs(giver:GetDescendants()) do
			if descendant:IsA("ProximityPrompt")
				and descendant.Enabled then

				prompt = descendant
				break
			end
		end
	end

	if not prompt then
		return false
	end

	if State.RootPart and prompt.Parent then
		local promptRoot = getRoot(prompt.Parent)

		if promptRoot then
			local distance =
				(State.RootPart.Position - promptRoot.Position).Magnitude

			if distance > CONFIG.Automation.QuestInteractionDistance then
				return false
			end
		end
	end

	local ok = pcall(function()
		prompt:InputHoldBegin()

		if prompt.HoldDuration > 0 then
			task.wait(prompt.HoldDuration + 0.05)
		else
			task.wait()
		end

		prompt:InputHoldEnd()
	end)

	return ok
end

local function getPlayerLevel(): number?
	local function readNamedValue(container: Instance?, names: {string}): number?
		if not container then
			return nil
		end

		for _, name in ipairs(names) do
			local child = container:FindFirstChild(name)

			if child then
				local value = getNumberValue(child)

				if value ~= nil then
					return value
				end
			end
		end

		for _, name in ipairs(names) do
			local child = container:FindFirstChild(name, true)

			if child then
				local value = getNumberValue(child)

				if value ~= nil then
					return value
				end
			end
		end

		return nil
	end

	local attributeNames = {"Level", "Lvl", "PlayerLevel"}

	for _, name in ipairs(attributeNames) do
		local value = LocalPlayer:GetAttribute(name)

		if typeof(value) == "number" then
			return value
		end
	end

	local containers = {
		LocalPlayer:FindFirstChild("leaderstats"),
		LocalPlayer:FindFirstChild("Data"),
		LocalPlayer:FindFirstChild("PlayerData"),
		LocalPlayer,
	}

	for _, container in ipairs(containers) do
		local value = readNamedValue(container, attributeNames)

		if value ~= nil then
			return value
		end
	end

	return nil
end

local function getQuestGivers(): {Instance}
	local result = {}
	local seen = {} :: {[Instance]: boolean}

	for _, object in ipairs(
		CollectionService:GetTagged(CONFIG.Automation.QuestGiverTag)
	) do
		if object:IsDescendantOf(workspace)
			and not seen[object] then

			seen[object] = true
			table.insert(result, object)
		end
	end

	local folder = workspace:FindFirstChild(
		CONFIG.Automation.QuestGiverFolder
	)

	if folder then
		for _, object in ipairs(folder:GetDescendants()) do
			if (object:IsA("Model") or object:IsA("BasePart"))
				and not seen[object] then

				seen[object] = true
				table.insert(result, object)
			end
		end
	end

	return result
end

local function isQuestEligible(
	giver: Instance,
	level: number
): boolean
	local minLevel =
		getNumberField(
			giver,
			CONFIG.Automation.QuestMinLevelAttributeNames
		)

	local maxLevel =
		getNumberField(
			giver,
			CONFIG.Automation.QuestMaxLevelAttributeNames
		)

	if minLevel ~= nil and level < minLevel then
		return false
	end

	if maxLevel ~= nil and level > maxLevel then
		return false
	end

	return true
end

local function getQuestTarget(giver: Instance): string?
	return getStringField(
		giver,
		CONFIG.Automation.QuestTargetAttributeNames
	)
end

local function getQuestName(giver: Instance): string
	return getStringField(
		giver,
		CONFIG.Automation.QuestNameAttributeNames
	) or giver.Name
end

local function getQuestId(giver: Instance): any
	for _, name in ipairs(CONFIG.Automation.QuestIdAttributeNames) do
		local value = giver:GetAttribute(name)

		if value ~= nil then
			return value
		end

		local valueObject = getValueObject(giver, name)

		if valueObject then
			local numericValue = getNumberValue(valueObject)

			if numericValue ~= nil then
				return numericValue
			end

			if valueObject:IsA("StringValue") then
				return valueObject.Value
			end
		end
	end

	return nil
end

local function readActiveQuest(): (string?, boolean)
	for _, name in ipairs(CONFIG.Automation.QuestStateAttributeNames) do
		local value = LocalPlayer:GetAttribute(name)

		if value ~= nil then
			if typeof(value) == "string" and value ~= "" then
				return value, true
			end

			return nil, true
		end
	end

	local containers = {
		LocalPlayer:FindFirstChild("QuestData"),
		LocalPlayer:FindFirstChild("Data"),
		LocalPlayer,
	}

	for _, container in ipairs(containers) do
		if container then
			for _, name in ipairs(CONFIG.Automation.QuestStateValueNames) do
				local valueObject = container:FindFirstChild(name)

				if valueObject then
					if valueObject:IsA("StringValue") then
						if valueObject.Value ~= "" then
							return valueObject.Value, true
						end

						return nil, true
					elseif valueObject:IsA("ObjectValue") then
						if valueObject.Value then
							return valueObject.Value.Name, true
						end

						return nil, true
					end
				end
			end
		end
	end

	return nil, false
end

local function resolvePath(root: Instance, path: string): Instance?
	if path == "" then
		return nil
	end

	local current: Instance? = root

	for segment in string.gmatch(path, "[^%.]+") do
		if not current then
			return nil
		end

		current = current:FindFirstChild(segment)
	end

	return current
end

local function resolveConfiguredRemotePath(path: string, giver: Instance): Instance?
	local replicatedStorage = game:GetService("ReplicatedStorage")

	if path == "" then
		return nil
	end

	if string.sub(path, 1, 16) == "ReplicatedStorage." then
		return resolvePath(
			replicatedStorage,
			string.sub(path, 17)
		)
	end

	if string.sub(path, 1, 10) == "Workspace." then
		return resolvePath(
			workspace,
			string.sub(path, 11)
		)
	end

	if string.sub(path, 1, 10) == "Character." then
		local character = State.Character
		return character and resolvePath(character, string.sub(path, 11))
	end

	return resolvePath(replicatedStorage, path)
end

local function findQuestRemote(giver: Instance): RemoteEvent | RemoteFunction?
	if not CONFIG.Automation.QuestRemote.Enabled then
		return nil
	end

	local replicatedStorage = game:GetService("ReplicatedStorage")
	local attributePath = giver:GetAttribute("QuestRemotePath")

	if typeof(attributePath) == "string" and attributePath ~= "" then
		local configured = resolveConfiguredRemotePath(attributePath, giver)

		if configured
			and (
				configured:IsA("RemoteEvent")
				or configured:IsA("RemoteFunction")
			) then
			return configured
		end
	end

	local configuredPath = CONFIG.Automation.QuestRemote.RemotePath

	if configuredPath ~= "" then
		local configured = resolveConfiguredRemotePath(configuredPath, giver)

		if configured
			and (
				configured:IsA("RemoteEvent")
				or configured:IsA("RemoteFunction")
			) then
			return configured
		end
	end

	local root = replicatedStorage

	if CONFIG.Automation.QuestRemote.RootName ~= "" then
		root = replicatedStorage:FindFirstChild(
			CONFIG.Automation.QuestRemote.RootName
		) or replicatedStorage
	end

	for _, name in ipairs(CONFIG.Automation.QuestRemote.EventNames) do
		local object = root:FindFirstChild(name, true)

		if object and object:IsA("RemoteEvent") then
			return object
		end
	end

	for _, name in ipairs(CONFIG.Automation.QuestRemote.FunctionNames) do
		local object = root:FindFirstChild(name, true)

		if object and object:IsA("RemoteFunction") then
			return object
		end
	end

	return nil
end

local function buildQuestRemoteArguments(giver: Instance): {any}
	local mode = CONFIG.Automation.QuestRemote.ArgumentMode
	local questId = getQuestId(giver)
	local questName = getQuestName(giver)
	local target = getQuestTarget(giver)

	if mode == "QuestId" and questId ~= nil then
		return {questId}
	end

	if mode == "QuestName" then
		return {questName}
	end

	if mode == "Giver" then
		return {giver}
	end

	if questId ~= nil then
		return {questId}
	end

	if target then
		return {questName, target}
	end

	return {questName}
end

local function acceptQuestRemotely(giver: Instance): boolean
	local remote = findQuestRemote(giver)

	if not remote then
		State.QuestRemoteStatus = "remote not found"
		return false
	end

	local args = buildQuestRemoteArguments(giver)

	local ok, result = pcall(function()
		if remote:IsA("RemoteFunction") then
			return remote:InvokeServer(table.unpack(args))
		end

		remote:FireServer(table.unpack(args))
		return true
	end)

	if not ok then
		State.QuestRemoteStatus = "remote error"
		return false
	end

	if remote:IsA("RemoteFunction") then
		if typeof(result) == "boolean" then
			State.QuestRemoteStatus = result and "accepted" or "rejected"
			return result
		end

		if typeof(result) == "table" then
			local success =
				result.Accepted
				or result.Success
				or result.success

			if typeof(success) == "boolean" then
				State.QuestRemoteStatus = success and "accepted" or "rejected"
				return success
			end
		end
	end

	State.QuestRemoteStatus = "sent"
	return true
end

local function findBestQuestGiver(level: number): Instance?
	if not State.RootPart then
		return nil
	end

	local best: Instance?
	local bestMinLevel = -math.huge
	local bestDistance = math.huge

	for _, giver in ipairs(getQuestGivers()) do
		if isQuestEligible(giver, level) then
			local minLevel =
				getNumberField(
					giver,
					CONFIG.Automation.QuestMinLevelAttributeNames
				)
				or 0

			local root = getRoot(giver)

			if root then
				local distance =
					(root.Position - State.RootPart.Position).Magnitude

				if minLevel > bestMinLevel
					or (
						minLevel == bestMinLevel
						and distance < bestDistance
					) then

					best = giver
					bestMinLevel = minLevel
					bestDistance = distance
				end
			end
		end
	end

	return best
end

local function questTargetMatchesActiveQuest(
	giver: Instance,
	activeQuest: string?
): boolean
	if not activeQuest then
		return true
	end

	local name = getQuestName(giver)
	return string.lower(name) == string.lower(activeQuest)
end

local function autoQuestStep(): boolean
	if not State.AutoFarm or not State.AutoQuest then
		return false
	end

	local now = os.clock()

	if now < State.NextQuestCheckAt then
		return false
	end

	State.NextQuestCheckAt =
		now + CONFIG.Automation.QuestCheckInterval

	local level = getPlayerLevel()

	if level == nil then
		State.QuestRemoteStatus = "level unavailable"
		return false
	end

	if State.CurrentPlayerLevel ~= level then
		State.ActiveQuestName = nil
		State.ActiveQuestTarget = nil
		State.FarmTarget = nil
		State.FarmTargets = {}
		State.NextAttackAt = 0
	end

	State.CurrentPlayerLevel = level

	local activeQuest, exposed = readActiveQuest()

	if activeQuest then
		State.ActiveQuestName = activeQuest
		return false
	end

	if exposed then
		State.ActiveQuestName = nil
		State.ActiveQuestTarget = nil
	end

	if now - State.LastAcceptedQuestAt
		< CONFIG.Automation.QuestAcceptCooldown then
		return false
	end

	local giver = findBestQuestGiver(level)

	if not giver then
		State.QuestRemoteStatus = "no eligible quest"
		return false
	end

	if not questTargetMatchesActiveQuest(giver, State.ActiveQuestName) then
		return false
	end

	if not claimMovement("AutoFarm") then
		return false
	end

	local giverRoot = getRoot(giver)

	if not giverRoot then
		return false
	end

	local destination =
		giverRoot.Position + Vector3.new(0, 2, 0)

	local distance =
		(State.RootPart and
			(State.RootPart.Position - giverRoot.Position).Magnitude)
		or math.huge

	if distance > CONFIG.Automation.QuestInteractionDistance then
		moveTo(destination)
	end

	if not State.AutoFarm or not State.AutoQuest then
		return false
	end

	if not giver.Parent then
		return false
	end

	local remoteAccepted = acceptQuestRemotely(giver)
	local promptAccepted = false

	if not remoteAccepted then
		promptAccepted = activateQuestPrompt(giver)

		if promptAccepted then
			State.QuestRemoteStatus = "prompt"
		end
	end

	if not remoteAccepted and not promptAccepted then
		return false
	end

	local questName = getQuestName(giver)
	local targetEnemy = getQuestTarget(giver)

	if targetEnemy then
		State.ActiveQuestTarget = targetEnemy
		State.SelectedEnemy = targetEnemy
	else
		State.ActiveQuestTarget = nil
	end

	State.LastAcceptedQuestAt = os.clock()
	State.LastQuestGiver = giver
	State.ActiveQuestName = questName

	-- Give a server-backed quest state time to replicate. If the
	-- experience does not expose one, the short cooldown still prevents
	-- hot-looping and the farm can continue from the giver metadata.
	task.delay(CONFIG.Automation.QuestVerifyDelay, function()
		if not State.Running or not State.AutoFarm then
			return
		end

		local replicatedQuest = select(1, readActiveQuest())

		if replicatedQuest then
			State.ActiveQuestName = replicatedQuest
		end

		State.NextQuestCheckAt = 0
	end)

	notify(
		string.format(
			"Quest: %s | Lv %d | %s",
			questName,
			level,
			State.QuestRemoteStatus
		)
	)

	return true
end

local function equipAutoFarmTool(): Tool?
	local character = State.Character
	local humanoid = State.Humanoid

	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			return child
		end
	end

	if not humanoid then
		return nil
	end

	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

	if not backpack then
		return nil
	end

	for _, child in ipairs(backpack:GetChildren()) do
		if child:IsA("Tool") then
			local ok = pcall(function()
				humanoid:EquipTool(child)
			end)

			if ok then
				return child
			end
		end
	end

	return nil
end

local function shouldAutoClick(): boolean
	return os.clock() >= State.NextAttackAt
end

local function performAutoClick(): boolean
	local now = os.clock()

	if now < State.NextAttackAt then
		return false
	end

	local clicksPerSecond =
		math.clamp(
			State.AutoClickRate,
			CONFIG.Automation.AutoClickMin,
			CONFIG.Automation.AutoClickMax
		)

	State.NextAttackAt = now + (1 / clicksPerSecond)

	local tool = equipAutoFarmTool()

	if not tool then
		return false
	end

	local ok = pcall(function()
		tool:Activate()
	end)

	return ok
end

local function attackTarget(target: Model): boolean
	if not target.Parent then
		return false
	end

	local humanoid = target:FindFirstChildOfClass("Humanoid")

	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	if shouldAutoClick() then
		performAutoClick()
	end

	return true
end

--============================================================
-- AUTO FARM
--============================================================

local function autoFarmStep()
	State.FarmTargets = {}
	State.FarmTarget = nil

	if not State.AutoFarm then
		return
	end

	if not claimMovement("AutoFarm") then
		return
	end

	autoQuestStep()

	local targetName =
		State.ActiveQuestTarget
		or State.SelectedEnemy

	local anchor = findNearestEnemy(targetName)

	if not anchor then
		-- A quest may not expose a TargetEnemy. Falling back to the
		-- nearest living enemy keeps Auto Farm useful while still
		-- respecting an explicit manual enemy selection when present.
		if State.ActiveQuestTarget then
			State.ActiveQuestTarget = nil
		end

		anchor = findNearestEnemy(State.SelectedEnemy)
	end

	if not anchor then
		anchor = findNearestEnemy(nil)
	end

	if not anchor then
		return
	end

	local gathered = findGatheredEnemies(targetName, anchor)

	if #gathered == 0 then
		gathered = {anchor}
	end

	State.FarmTargets = gathered
	State.FarmTarget = gathered[1]

	local anchorRoot = getRoot(anchor)

	if not anchorRoot then
		return
	end

	-- Move to the center of the selected mob group rather than repeatedly
	-- moving from mob to mob. This reduces tween churn and lets normal
	-- aggro/AI pull the group together around the player.
	local center = anchorRoot.Position
	local count = 1

	for index = 2, #gathered do
		local root = getRoot(gathered[index])

		if root then
			center += root.Position
			count += 1
		end
	end

	center /= count

	local destination =
		center + Vector3.new(0, CONFIG.EnemyHeight, 0)

	if State.RootPart then
		local targetLook = anchorRoot.Position
		State.RootPart.CFrame =
			CFrame.lookAt(destination, targetLook)
	end

	moveTo(destination)

	-- Keep only live targets in the pool after movement.
	for index = #State.FarmTargets, 1, -1 do
		if not isLivingEnemy(State.FarmTargets[index]) then
			table.remove(State.FarmTargets, index)
		end
	end

	State.FarmTarget = State.FarmTargets[1]
end

--============================================================
-- AUTO LOOT
--============================================================

local function autoLootStep()
	if not State.AutoLoot or State.AutoFarm then
		return
	end

	if not claimMovement("AutoLoot") then
		return
	end

	local item = findNearestLoot()

	if not item then
		return
	end

	local root = getRoot(item)

	if not root then
		return
	end

	local direction =
		State.RootPart
		and (State.RootPart.Position - root.Position).Unit
		or Vector3.new(0, 0, 1)

	local destination =
		root.Position
		+ direction * CONFIG.LootStoppingDistance

	moveTo(destination)

	if State.AutoLoot and item.Parent then
		collectLoot(item)
	end
end

--============================================================
-- AUTOMATION CONTROL
--============================================================

local function setAutoFarm(enabled: boolean)
	State.AutoFarm = enabled

	if enabled then
		State.AutoLoot = false
		releaseMovement("AutoLoot")

		State.AutoFarmGeneration += 1
		State.NextAttackAt = 0
		State.NextQuestCheckAt = 0
		State.LastAcceptedQuestAt = 0

		local level = getPlayerLevel()

		if level ~= nil then
			State.CurrentPlayerLevel = level
		end

		notify(
			State.AutoQuest
				and "Auto Farm enabled | Auto Quest ready"
				or "Auto Farm enabled"
		)
	else
		State.AutoFarmGeneration += 1
		releaseMovement("AutoFarm")
		State.ActiveQuestName = nil
		State.ActiveQuestTarget = nil
		State.FarmTarget = nil
		State.FarmTargets = {}
		State.QuestRemoteStatus = "idle"
		State.NextAttackAt = 0
		notify("Auto Farm disabled")
	end
end

local function setAutoLoot(enabled: boolean)
	State.AutoLoot = enabled

	if enabled then
		State.AutoFarm = false
		releaseMovement("AutoFarm")

		if next(State.SelectedLoot) == nil then
			State.AutoLoot = false
			notify("Select a loot type first")
			return
		end

		State.AutoLootGeneration += 1
		notify("Auto Loot enabled")
	else
		State.AutoLootGeneration += 1
		releaseMovement("AutoLoot")
		notify("Auto Loot disabled")
	end
end

--============================================================
-- PLAYER ESP
--============================================================

type ESPData = {
	Objects: {Instance},
	Connections: {RBXScriptConnection},
}

local ESPObjects: {[Player]: ESPData} = {}

local function destroyESP(player: Player)
	local data = ESPObjects[player]

	if not data then
		return
	end

	for _, connection in ipairs(data.Connections) do
		disconnect(connection)
	end

	for _, object in ipairs(data.Objects) do
		if object.Parent then
			object:Destroy()
		end
	end

	ESPObjects[player] = nil
end

local function attachESP(player: Player, character: Model)
	destroyESP(player)

	if not State.PlayerESP
		or player == LocalPlayer then
		return
	end

	local data: ESPData = {
		Objects = {},
		Connections = {},
	}

	ESPObjects[player] = data

	local highlight = Instance.new("Highlight")
	highlight.Name = "MrDonESP"
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0
	highlight.Parent = character

	table.insert(data.Objects, highlight)

	local head = character:FindFirstChild("Head")

	if not head then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MrDonESPInfo"
	billboard.Size = UDim2.fromOffset(170, 80)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = head

	table.insert(data.Objects, billboard)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.Font = Enum.Font.Gotham
	label.TextSize = 12
	label.TextWrapped = true
	label.Parent = billboard

	table.insert(data.Objects, label)

	local accumulator = 0

	local connection = RunService.Heartbeat:Connect(function(delta)
		if not State.PlayerESP or not character.Parent then
			return
		end

		accumulator += delta

		if accumulator < 0.2 then
			return
		end

		accumulator = 0

		local humanoid =
			character:FindFirstChildOfClass("Humanoid")

		local root =
			character:FindFirstChild("HumanoidRootPart")

		if not humanoid or not root then
			return
		end

		local sameTeam =
			LocalPlayer.Team ~= nil
			and player.Team == LocalPlayer.Team

		if CONFIG.ESP.HideSameTeam and sameTeam then
			highlight.Enabled = false
			billboard.Enabled = false
			return
		end

		highlight.Enabled = true
		billboard.Enabled = true

		highlight.OutlineColor =
			sameTeam
			and CONFIG.ESP.FriendlyColor
			or CONFIG.ESP.EnemyColor

		local lines = {}

		if CONFIG.ESP.ShowNames then
			table.insert(lines, player.Name)
		end

		if CONFIG.ESP.ShowHealth then
			table.insert(
				lines,
				string.format(
					"HP: %.0f / %.0f",
					humanoid.Health,
					humanoid.MaxHealth
				)
			)
		end

		if CONFIG.ESP.ShowDistance and State.RootPart then
			local distance =
				(root.Position - State.RootPart.Position).Magnitude

			table.insert(
				lines,
				string.format("%.0f studs", distance)
			)
		end

		label.Text = table.concat(lines, "\n")
	end)

	table.insert(data.Connections, connection)
end

local function createESP(player: Player)
	if player == LocalPlayer then
		return
	end

	if player.Character then
		attachESP(player, player.Character)
	end
end

local function setPlayerESP(enabled: boolean)
	State.PlayerESP = enabled

	if enabled then
		for _, player in ipairs(Players:GetPlayers()) do
			createESP(player)
		end

		notify("Player ESP enabled")
	else
		for player in pairs(ESPObjects) do
			destroyESP(player)
		end

		notify("Player ESP disabled")
	end
end

table.insert(
	State.Connections,
	Players.PlayerAdded:Connect(function(player)
		if State.PlayerESP then
			player.CharacterAdded:Connect(function(character)
				attachESP(player, character)
			end)

			createESP(player)
		end
	end)
)

table.insert(
	State.Connections,
	Players.PlayerRemoving:Connect(destroyESP)
)

--============================================================
-- GUI CREATION
--============================================================

local Gui = Instance.new("ScreenGui")
Gui.Name = "MrDonUtilityMenu"
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(350, 450)
Main.Position = UDim2.new(0.5, -175, 0.5, -225)
Main.BackgroundColor3 = Color3.fromRGB(23, 23, 28)
Main.BorderSizePixel = 0
Main.Parent = Gui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = Main

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 44)
Header.BackgroundTransparency = 1
Header.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -90, 1, 0)
Title.Position = UDim2.fromOffset(12, 0)
Title.BackgroundTransparency = 1
Title.Text = "Xionxi 1.2.1 • Fruit Utility"
Title.TextColor3 = Color3.new(1, 1, 1)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 16
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local Minimize = Instance.new("TextButton")
Minimize.Size = UDim2.fromOffset(34, 34)
Minimize.Position = UDim2.new(1, -72, 0, 5)
Minimize.BackgroundTransparency = 1
Minimize.Text = "−"
Minimize.TextColor3 = Color3.new(1, 1, 1)
Minimize.TextSize = 20
Minimize.Parent = Header

local Close = Instance.new("TextButton")
Close.Size = UDim2.fromOffset(34, 34)
Close.Position = UDim2.new(1, -38, 0, 5)
Close.BackgroundTransparency = 1
Close.Text = "×"
Close.TextColor3 = Color3.new(1, 1, 1)
Close.TextSize = 20
Close.Parent = Header

local Content = Instance.new("ScrollingFrame")
Content.Size = UDim2.new(1, -20, 1, -54)
Content.Position = UDim2.fromOffset(10, 48)
Content.BackgroundTransparency = 1
Content.BorderSizePixel = 0
Content.ScrollBarThickness = 4
Content.CanvasSize = UDim2.fromOffset(0, 0)
Content.Parent = Main

local ContentLayout = Instance.new("UIListLayout")
ContentLayout.Padding = UDim.new(0, 6)
ContentLayout.Parent = Content

ContentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(
	function()
		Content.CanvasSize = UDim2.fromOffset(
			0,
			ContentLayout.AbsoluteContentSize.Y + 10
		)
	end
)

--============================================================
-- GUI HELPERS
--============================================================

local function createButton(text: string): TextButton
	local button = Instance.new("TextButton")

	button.Size = UDim2.new(1, -4, 0, 34)
	button.BackgroundColor3 = Color3.fromRGB(38, 38, 45)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.Gotham
	button.TextSize = 13
	button.Text = text
	button.AutoButtonColor = true
	button.Parent = Content

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	return button
end

local function createToggle(
	name: string,
	callback: (boolean) -> (),
	defaultEnabled: boolean?
): TextButton

	local enabled = defaultEnabled == true
	local button = createButton(
		name .. (enabled and ": ON" or ": OFF")
	)

	button.Activated:Connect(function()
		enabled = not enabled
		button.Text = name .. (enabled and ": ON" or ": OFF")
		callback(enabled)
	end)

	return button
end

local function createNumberInput(
	name: string,
	defaultValue: number,
	minimum: number,
	maximum: number,
	callback: (number) -> ()
)
	local frame = Instance.new("Frame")

	frame.Size = UDim2.new(1, -4, 0, 38)
	frame.BackgroundColor3 = Color3.fromRGB(38, 38, 45)
	frame.Parent = Content

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.55, 0, 1, 0)
	label.Position = UDim2.fromOffset(10, 0)
	label.BackgroundTransparency = 1
	label.Text = name
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Gotham
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0.36, 0, 0, 28)
	box.Position = UDim2.new(0.6, 0, 0.5, -14)
	box.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
	box.TextColor3 = Color3.new(1, 1, 1)
	box.Font = Enum.Font.Gotham
	box.TextSize = 12
	box.Text = tostring(defaultValue)
	box.ClearTextOnFocus = false
	box.Parent = frame

	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 5)
	boxCorner.Parent = box

	box.FocusLost:Connect(function()
		local value = tonumber(box.Text)

		if not value then
			box.Text = tostring(defaultValue)
			notify("Invalid number")
			return
		end

		value = math.clamp(value, minimum, maximum)
		box.Text = tostring(value)

		callback(value)
	end)
end

--============================================================
-- SEARCHABLE DROPDOWN
--============================================================

local function createDropdown(
	titleText: string,
	getItems: () -> {string},
	selectCallback: (string) -> ()
)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, -4, 0, 38)
	container.BackgroundColor3 = Color3.fromRGB(38, 38, 45)
	container.ClipsDescendants = true
	container.Parent = Content

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = container

	local search = Instance.new("TextBox")
	search.Size = UDim2.new(1, -10, 0, 32)
	search.Position = UDim2.fromOffset(5, 3)
	search.BackgroundColor3 = Color3.fromRGB(48, 48, 57)
	search.TextColor3 = Color3.new(1, 1, 1)
	search.PlaceholderColor3 = Color3.fromRGB(160, 160, 160)
	search.PlaceholderText = titleText
	search.ClearTextOnFocus = false
	search.Font = Enum.Font.Gotham
	search.TextSize = 12
	search.Parent = container

	local list = Instance.new("Frame")
	list.Size = UDim2.new(1, -10, 0, 0)
	list.Position = UDim2.fromOffset(5, 38)
	list.BackgroundTransparency = 1
	list.Parent = container

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 3)
	listLayout.Parent = list

	local expanded = false

	local function refresh()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end

		local filter = string.lower(search.Text)

		for _, item in ipairs(getItems()) do
			if filter == ""
				or string.find(
					string.lower(item),
					filter,
					1,
					true
				) then

				local button = Instance.new("TextButton")
				button.Size = UDim2.new(1, 0, 0, 28)
				button.BackgroundColor3 =
					Color3.fromRGB(48, 48, 57)
				button.TextColor3 = Color3.new(1, 1, 1)
				button.Font = Enum.Font.Gotham
				button.TextSize = 11
				button.Text = item
				button.Parent = list

				button.Activated:Connect(function()
					search.Text = item
					selectCallback(item)

					expanded = false
					container.Size =
						UDim2.new(1, -4, 0, 38)
				end)
			end
		end

		local height =
			math.min(
				listLayout.AbsoluteContentSize.Y + 8,
				180
			)

		list.Size = UDim2.new(1, -10, 0, height)

		if expanded then
			container.Size =
				UDim2.new(1, -4, 0, 44 + height)
		end
	end

	search.Focused:Connect(function()
		expanded = true
		refresh()
	end)

	search:GetPropertyChangedSignal("Text"):Connect(refresh)

	return container
end

--============================================================
-- UI FEATURES
--============================================================

createToggle("Fix Lag", setFixLag)
createToggle("Full Bright", setFullBright)

createNumberInput(
	"Walk Speed",
	State.WalkSpeed,
	CONFIG.WalkSpeed.Min,
	CONFIG.WalkSpeed.Max,
	function(value)
		State.WalkSpeed = value
		applyWalkSpeed()
	end
)

createToggle("Speed Walk", function(enabled)
	State.SpeedWalk = enabled

	if enabled then
		applyWalkSpeed()
	else
		disableWalkSpeed()
	end
end)

createNumberInput(
	"Jump",
	State.JumpValue,
	CONFIG.Jump.Min,
	CONFIG.Jump.Max,
	function(value)
		State.JumpValue = value
		applyJump()
	end
)

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

createDropdown(
	"Search enemy...",
	getEnemyNames,
	function(enemyName)
		State.SelectedEnemy = enemyName
		notify("Enemy selected: " .. enemyName)
	end
)

createDropdown(
	"Search loot tag...",
	function()
		local result = {}

		for _, tag in ipairs(CONFIG.LootTags) do
			table.insert(result, tag)
		end

		return result
	end,
	function(tag)
		State.SelectedLoot[tag] = true
		notify("Loot selected: " .. tag)
	end
)

createToggle("Auto Quest", function(enabled)
	State.AutoQuest = enabled

	if enabled then
		State.NextQuestCheckAt = 0
		notify("Auto Quest enabled")
	else
		State.ActiveQuestName = nil
		State.ActiveQuestTarget = nil
		State.FarmTarget = nil
		State.FarmTargets = {}
		State.QuestRemoteStatus = "idle"
		notify("Auto Quest disabled")
	end
end, true)

createNumberInput(
	"Auto Clicks / Sec",
	State.AutoClickRate,
	CONFIG.Automation.AutoClickMin,
	CONFIG.Automation.AutoClickMax,
	function(value)
		State.AutoClickRate = value
		State.NextAttackAt = 0
		notify(string.format("Auto click rate: %.1f/s", value))
	end
)

createToggle("Auto Farm", setAutoFarm)
createToggle("Auto Loot", setAutoLoot)

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -4, 0, 56)
Status.BackgroundTransparency = 1
Status.TextColor3 = Color3.fromRGB(180, 180, 180)
Status.Font = Enum.Font.Gotham
Status.TextSize = 11
Status.TextWrapped = true
Status.TextYAlignment = Enum.TextYAlignment.Center
Status.Text =
	"Xionxi 1.2.1 | Level: -- | Quest: --\n"
	.. "Auto Quest: ON | Auto Farm: OFF | Auto Loot: OFF\n"
	.. "Clicks: "
	.. tostring(State.AutoClickRate)
	.. "/s | Remote: idle"
Status.Parent = Content

--============================================================
-- DRAG SUPPORT
--============================================================

local dragging = false
local dragStart: Vector2
local startPosition: UDim2

local function updateDrag(input: InputObject)
	local delta = input.Position - dragStart

	Main.Position = UDim2.new(
		startPosition.X.Scale,
		startPosition.X.Offset + delta.X,
		startPosition.Y.Scale,
		startPosition.Y.Offset + delta.Y
	)
end

Header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		dragging = true
		dragStart = input.Position
		startPosition = Main.Position
	end
end)

table.insert(
	State.Connections,
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then

			updateDrag(input)
		end
	end)
)

table.insert(
	State.Connections,
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then

			dragging = false
		end
	end)
)

--============================================================
-- MENU CONTROL
--============================================================

local function setMenuVisible(visible: boolean)
	State.MenuOpen = visible
	Main.Visible = visible
end

Close.Activated:Connect(function()
	setMenuVisible(false)
end)

Minimize.Activated:Connect(function()
	State.Minimized = not State.Minimized

	Content.Visible = not State.Minimized

	if State.Minimized then
		Main.Size = UDim2.fromOffset(350, 44)
	else
		Main.Size = UDim2.fromOffset(350, 450)
	end
end)

table.insert(
	State.Connections,
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end

		if input.KeyCode == CONFIG.MenuToggleKey then
			setMenuVisible(not State.MenuOpen)
		end
	end)
)

--============================================================
-- AUTO CLICK LOOP
--============================================================

-- Movement/world scanning stays on the coarse automation interval.
-- Clicking is independent so "Auto Clicks / Sec" remains effective.
table.insert(
	State.Connections,
	RunService.Heartbeat:Connect(function()
		if not State.Running
			or not State.AutoFarm
			or not State.FarmTarget then
			return
		end

		if isLivingEnemy(State.FarmTarget) then
			attackTarget(State.FarmTarget)
		else
			State.FarmTarget = nil
		end
	end)
)

--============================================================
-- AUTOMATION LOOP
--============================================================

task.spawn(function()
	while State.Running do
		if State.AutoFarm then
			autoFarmStep()
		elseif State.AutoLoot then
			autoLootStep()
		else
			releaseMovement("AutoFarm")
			releaseMovement("AutoLoot")
		end

		local level = getPlayerLevel()

		if level ~= nil then
			State.CurrentPlayerLevel = level
		end

		local questDisplay =
			State.ActiveQuestName
			or "none"

		Status.Text =
			"Xionxi 1.2.1 | Level: "
			.. tostring(State.CurrentPlayerLevel)
			.. " | Quest: "
			.. questDisplay
			.. "\nAuto Quest: "
			.. (State.AutoQuest and "ON" or "OFF")
			.. " | Auto Farm: "
			.. (State.AutoFarm and "ON" or "OFF")
			.. " | Auto Loot: "
			.. (State.AutoLoot and "ON" or "OFF")
			.. "\nClicks: "
			.. string.format("%.1f", State.AutoClickRate)
			.. "/s | Mobs: "
			.. tostring(#State.FarmTargets)
			.. " | Remote: "
			.. State.QuestRemoteStatus

		task.wait(CONFIG.TargetSearchInterval)
	end
end)

--============================================================
-- SHUTDOWN
--============================================================

local function shutdown()
	if not State.Running then
		return
	end

	State.Running = false

	State.AutoFarm = false
	State.AutoLoot = false
	State.AutoQuest = false
	State.ActiveQuestName = nil
	State.ActiveQuestTarget = nil
	State.FarmTarget = nil
	State.FarmTargets = {}

	cancelTween()

	releaseMovement("AutoFarm")
	releaseMovement("AutoLoot")

	State.NoclipRequests = {}
	restoreCollision()

	disableFixLag()
	disableFullBright()

	for player in pairs(ESPObjects) do
		destroyESP(player)
	end

	for _, connection in ipairs(State.Connections) do
		disconnect(connection)
	end

	table.clear(State.Connections)

	disconnectFeature("Automation")

	if Gui.Parent then
		Gui:Destroy()
	end

	if NotificationGui.Parent then
		NotificationGui:Destroy()
	end
end

-- Close the UI does not shut down the script.
-- Destroying the GUI externally can still leave the script alive,
-- so this explicit shutdown function remains available internally.

notify("Xionxi 1.2.1 loaded")
