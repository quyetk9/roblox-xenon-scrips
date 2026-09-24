-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

-- Initialization Barrier: Prevent race conditions by waiting for the game to stream in
if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- Configuration
local CONFIG = {
	MenuToggleKey = Enum.KeyCode.RightControl,
	
	WalkSpeed = { Min = 16, Max = 100, Default = 16 },
	Jump = { Min = 50, Max = 250, Default = 50 },
	
	AutoFarm = {
		HeightAboveEnemy = 6,
		TweenSpeed = 150,
		SearchInterval = 0.1,
		FallbackFolderName = "Enemies" -- Resolved dynamically to prevent startup nil reference
	},
	
	AutoLoot = {
		StoppingDistance = 1,
		TweenSpeed = 150,
		SearchInterval = 0.1,
		Tags = {"LootChest", "DevilFruit"}
	},
	
	ESP = {
		AllyColor = Color3.fromRGB(0, 255, 0),
		EnemyColor = Color3.fromRGB(255, 0, 0),
		ShowNames = true,
		ShowHealth = true,
		ShowDistance = true,
		HideSameTeam = true
	}
}

-- Environment
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 15)

if not PlayerGui then
	error("[UtilityMenu] Initialization failed: PlayerGui did not load within the safe timeout.")
end

-- State Management
local State = {
	MenuOpen = true,
	Features = {
		FixLag = false,
		FullBright = false,
		SpeedWalk = false,
		HighJump = false,
		AutoFarm = false,
		AutoLoot = false,
		Noclip = false,
		ESP = false
	},
	NoclipRequests = 0,
	ActiveTween = nil,
	SelectedEnemyType = nil,
	SelectedLootType = nil,
	Target = nil,
	LootTarget = nil,
	Connections = {},
	OriginalLighting = {},
	OriginalMaterials = {},
	ESPObjects = {}
}

-- ==========================================
-- INTEGRATION
-- ==========================================

local function attackTarget(target: Model)
	local char = LocalPlayer.Character
	if not char or not char:FindFirstChild("Humanoid") then return end
	
	local tool = char:FindFirstChildOfClass("Tool") or LocalPlayer.Backpack:FindFirstChildOfClass("Tool")
	if tool then
		char.Humanoid:EquipTool(tool)
		tool:Activate()
	end
end

local function collectLoot(item: Instance)
	-- Built-in physical overlap handles standard Touch events.
	-- Add custom interaction logic here if required.
end

-- ==========================================
-- UI FACTORY
-- ==========================================

local function create(className: string, properties: table, children: table?): Instance
	local inst = Instance.new(className)
	for k, v in pairs(properties) do
		inst[k] = v
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	return inst
end

local Screen = create("ScreenGui", {
	Name = "UtilityMenu",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	Parent = PlayerGui
})

for _, gui in ipairs(PlayerGui:GetChildren()) do
	if gui.Name == "UtilityMenu" and gui ~= Screen then
		gui:Destroy()
	end
end

local MainFrame = create("Frame", {
	Size = UDim2.new(0, 300, 0, 450),
	Position = UDim2.new(0.5, -150, 0.5, -225),
	BackgroundColor3 = Color3.fromRGB(30, 30, 35),
	BorderSizePixel = 0,
	Active = true,
	Parent = Screen
}, {
	create("UICorner", {CornerRadius = UDim.new(0, 8)}),
	create("UIStroke", {Color = Color3.fromRGB(60, 60, 65), Thickness = 1})
})

local Topbar = create("Frame", {
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = Color3.fromRGB(40, 40, 45),
	BorderSizePixel = 0,
	Parent = MainFrame
}, {
	create("UICorner", {CornerRadius = UDim.new(0, 8)}),
	create("TextLabel", {
		Size = UDim2.new(1, -60, 1, 0),
		Position = UDim2.new(0, 10, 0, 0),
		BackgroundTransparency = 1,
		Text = "Utility Menu",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left
	})
})

create("Frame", {
	Size = UDim2.new(1, 0, 0, 8),
	Position = UDim2.new(0, 0, 1, -8),
	BackgroundColor3 = Color3.fromRGB(40, 40, 45),
	BorderSizePixel = 0,
	Parent = Topbar
})

local ContentScroll = create("ScrollingFrame", {
	Size = UDim2.new(1, -20, 1, -40),
	Position = UDim2.new(0, 10, 0, 35),
	BackgroundTransparency = 1,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = MainFrame
}, {
	create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8)})
})

local dragging, dragInput, dragStart, startPos
Topbar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = MainFrame.Position
		
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

Topbar.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end)

RunService.Heartbeat:Connect(function()
	if dragging and dragInput then
		local delta = dragInput.Position - dragStart
		MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end)

local function notify(message: string, isError: boolean)
	local notif = create("TextLabel", {
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.new(0, 10, 0, -40),
		BackgroundColor3 = isError and Color3.fromRGB(150, 50, 50) or Color3.fromRGB(50, 150, 50),
		Text = message,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamSemibold,
		TextSize = 12,
		Parent = MainFrame
	}, {
		create("UICorner", {CornerRadius = UDim.new(0, 4)})
	})
	
	TweenService:Create(notif, TweenInfo.new(0.3), {Position = UDim2.new(0, 10, 0, 10)}):Play()
	task.delay(2.5, function()
		local out = TweenService:Create(notif, TweenInfo.new(0.3), {Position = UDim2.new(0, 10, 0, -40), BackgroundTransparency = 1, TextTransparency = 1})
		out:Play()
		out.Completed:Wait()
		notif:Destroy()
	end)
end

-- ==========================================
-- CORE MECHANICS
-- ==========================================

local function requestNoclip()
	State.NoclipRequests += 1
end

local function releaseNoclip()
	State.NoclipRequests = math.max(0, State.NoclipRequests - 1)
end

local function applyCharacterModifications(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 3)
	if not humanoid then return end

	if State.Features.SpeedWalk then
		humanoid.WalkSpeed = State.SpeedWalkValue or CONFIG.WalkSpeed.Default
	end
	if State.Features.HighJump then
		if humanoid.UseJumpPower then
			humanoid.JumpPower = State.HighJumpValue or CONFIG.Jump.Default
		else
			humanoid.JumpHeight = State.HighJumpValue or CONFIG.Jump.Default
		end
	end
end

local function cancelActiveMovement()
	if State.ActiveTween then
		State.ActiveTween:Cancel()
		State.ActiveTween = nil
	end
end

-- ==========================================
-- FEATURE IMPLEMENTATIONS
-- ==========================================

local function toggleFixLag(enabled: boolean)
	local targetEffects = {ParticleEmitter=true, Trail=true, Beam=true, Smoke=true, Fire=true, Sparkles=true, PointLight=true, SpotLight=true, SurfaceLight=true, BloomEffect=true, BlurEffect=true, SunRaysEffect=true, ColorCorrectionEffect=true, DepthOfFieldEffect=true}
	
	if enabled then
		State.Connections.LagDescendant = workspace.DescendantAdded:Connect(function(desc)
			if targetEffects[desc.ClassName] then
				desc.Enabled = false
			elseif desc:IsA("BasePart") and desc.Material ~= Enum.Material.Plastic then
				State.OriginalMaterials[desc] = desc.Material
				desc.Material = Enum.Material.Plastic
			end
		end)
		
		for _, desc in ipairs(workspace:GetDescendants()) do
			if targetEffects[desc.ClassName] then
				State.OriginalMaterials[desc] = desc.Enabled
				desc.Enabled = false
			elseif desc:IsA("BasePart") and desc.Material ~= Enum.Material.Plastic then
				State.OriginalMaterials[desc] = desc.Material
				desc.Material = Enum.Material.Plastic
			end
		end
		
		State.OriginalMaterials.GlobalShadows = Lighting.GlobalShadows
		Lighting.GlobalShadows = false
	else
		if State.Connections.LagDescendant then
			State.Connections.LagDescendant:Disconnect()
			State.Connections.LagDescendant = nil
		end
		for inst, originalVal in pairs(State.OriginalMaterials) do
			if typeof(originalVal) == "boolean" then
				if inst:IsDescendantOf(game) then inst.Enabled = originalVal end
			elseif typeof(originalVal) == "EnumItem" then
				if inst:IsDescendantOf(workspace) then inst.Material = originalVal end
			end
		end
		Lighting.GlobalShadows = State.OriginalMaterials.GlobalShadows
		table.clear(State.OriginalMaterials)
	end
end

local function toggleFullBright(enabled: boolean)
	if enabled then
		State.OriginalLighting.Brightness = Lighting.Brightness
		State.OriginalLighting.Ambient = Lighting.Ambient
		State.OriginalLighting.OutdoorAmbient = Lighting.OutdoorAmbient
		
		Lighting.Brightness = 2
		Lighting.Ambient = Color3.new(1, 1, 1)
		Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
	else
		for prop, val in pairs(State.OriginalLighting) do
			Lighting[prop] = val
		end
		table.clear(State.OriginalLighting)
	end
end

local function findNearest(list: table, targetClass: string): Instance?
	local char = LocalPlayer.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
	local root = char.HumanoidRootPart
	
	local closestDist = math.huge
	local closestInst = nil
	
	for _, inst in ipairs(list) do
		local pos = nil
		local valid = false
		
		if targetClass == "Enemy" then
			if inst:IsA("Model") and inst.Name == State.SelectedEnemyType and inst:FindFirstChild("HumanoidRootPart") then
				local hum = inst:FindFirstChild("Humanoid")
				if hum and hum.Health > 0 then
					pos = inst.HumanoidRootPart.Position
					valid = true
				end
			end
		elseif targetClass == "Loot" then
			if (inst:IsA("BasePart") or inst:IsA("Model")) and table.find(CONFIG.AutoLoot.Tags, State.SelectedLootType) then
				if inst:IsA("Model") and inst.PrimaryPart then
					pos = inst.PrimaryPart.Position
				elseif inst:IsA("BasePart") then
					pos = inst.Position
				end
				if inst:IsDescendantOf(workspace) then
					valid = true
				end
			end
		end
		
		if valid and pos then
			local dist = (pos - root.Position).Magnitude
			if dist < closestDist then
				closestDist = dist
				closestInst = inst
			end
		end
	end
	
	return closestInst
end

local function getEnemyList(): table
	local enemies = CollectionService:GetTagged("FarmableEnemy")
	local fallbackFolder = workspace:FindFirstChild(CONFIG.AutoFarm.FallbackFolderName)
	
	if #enemies == 0 and fallbackFolder then
		for _, child in ipairs(fallbackFolder:GetChildren()) do
			table.insert(enemies, child)
		end
	end
	return enemies
end

local function getLootList(): table
	local loot = {}
	for _, tag in ipairs(CONFIG.AutoLoot.Tags) do
		for _, item in ipairs(CollectionService:GetTagged(tag)) do
			table.insert(loot, item)
		end
	end
	return loot
end

local function toggleAutoFarm(enabled: boolean)
	if enabled then
		if State.Features.AutoLoot then
			notify("Auto Loot was disabled to prevent movement conflict.", false)
		end
		requestNoclip()
		
		State.Connections.AutoFarm = task.spawn(function()
			while State.Features.AutoFarm do
				task.wait(CONFIG.AutoFarm.SearchInterval)
				
				local char = LocalPlayer.Character
				if not char or not char:FindFirstChild("HumanoidRootPart") then continue end
				local root = char.HumanoidRootPart
				
				if not State.SelectedEnemyType then
					notify("Select an enemy type.", true)
					task.wait(2)
					continue
				end
				
				local target = findNearest(getEnemyList(), "Enemy")
				if target then
					local targetPos = target.HumanoidRootPart.Position + Vector3.new(0, CONFIG.AutoFarm.HeightAboveEnemy, 0)
					local dist = (root.Position - targetPos).Magnitude
					
					if State.Target ~= target or (State.ActiveTween and State.ActiveTween.PlaybackState ~= Enum.PlaybackState.Playing) or dist > (CONFIG.AutoFarm.HeightAboveEnemy + 2) then
						State.Target = target
						cancelActiveMovement()
						
						local timeToTarget = math.clamp(dist / CONFIG.AutoFarm.TweenSpeed, 0.1, 5)
						local tInfo = TweenInfo.new(timeToTarget, Enum.EasingStyle.Linear)
						State.ActiveTween = TweenService:Create(root, tInfo, {CFrame = CFrame.new(targetPos, target.HumanoidRootPart.Position)})
						State.ActiveTween:Play()
					end
					
					attackTarget(target)
				else
					State.Target = nil
					cancelActiveMovement()
				end
			end
		end)
	else
		if State.Connections.AutoFarm then
			task.cancel(State.Connections.AutoFarm)
			State.Connections.AutoFarm = nil
		end
		State.Target = nil
		releaseNoclip()
		cancelActiveMovement()
	end
end

local function toggleAutoLoot(enabled: boolean)
	if enabled then
		if State.Features.AutoFarm then
			notify("Auto Farm was disabled to prevent movement conflict.", false)
		end
		requestNoclip()
		
		State.Connections.AutoLoot = task.spawn(function()
			while State.Features.AutoLoot do
				task.wait(CONFIG.AutoLoot.SearchInterval)
				
				local char = LocalPlayer.Character
				if not char or not char:FindFirstChild("HumanoidRootPart") then continue end
				local root = char.HumanoidRootPart
				
				if not State.SelectedLootType then
					notify("Select a loot type.", true)
					task.wait(2)
					continue
				end
				
				local item = findNearest(getLootList(), "Loot")
				if item then
					local pos = item:IsA("Model") and item.PrimaryPart.Position or item.Position
					local dist = (root.Position - pos).Magnitude
					
					if dist > CONFIG.AutoLoot.StoppingDistance then
						if State.LootTarget ~= item or (State.ActiveTween and State.ActiveTween.PlaybackState ~= Enum.PlaybackState.Playing) then
							State.LootTarget = item
							cancelActiveMovement()
							
							local timeToTarget = math.clamp(dist / CONFIG.AutoLoot.TweenSpeed, 0.1, 5)
							local tInfo = TweenInfo.new(timeToTarget, Enum.EasingStyle.Linear)
							State.ActiveTween = TweenService:Create(root, tInfo, {CFrame = CFrame.new(pos)})
							State.ActiveTween:Play()
						end
					else
						State.LootTarget = nil
						cancelActiveMovement()
						collectLoot(item)
					end
				else
					State.LootTarget = nil
				end
			end
		end)
	else
		if State.Connections.AutoLoot then
			task.cancel(State.Connections.AutoLoot)
			State.Connections.AutoLoot = nil
		end
		State.LootTarget = nil
		releaseNoclip()
		cancelActiveMovement()
	end
end

local function buildESP(player: Player)
	if player == LocalPlayer or not State.Features.ESP then return end
	if CONFIG.ESP.HideSameTeam and player.Team == LocalPlayer.Team then return end
	
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end
	
	local color = (player.Team == LocalPlayer.Team) and CONFIG.ESP.AllyColor or CONFIG.ESP.EnemyColor
	
	local hl = Instance.new("Highlight")
	hl.Adornee = char
	hl.FillColor = color
	hl.FillTransparency = 0.5
	hl.OutlineColor = color
	hl.Parent = Screen -- Secured: CoreGui reference removed
	
	local bg = Instance.new("BillboardGui")
	bg.Adornee = char.HumanoidRootPart
	bg.Size = UDim2.new(0, 100, 0, 40)
	bg.StudsOffset = Vector3.new(0, 3, 0)
	bg.AlwaysOnTop = true
	
	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.new(1, 0, 0.5, 0)
	txt.BackgroundTransparency = 1
	txt.Text = player.Name
	txt.TextColor3 = color
	txt.TextStrokeTransparency = 0
	txt.Font = Enum.Font.GothamBold
	txt.TextSize = 12
	txt.Parent = bg
	
	local distTxt = txt:Clone()
	distTxt.Position = UDim2.new(0, 0, 0.5, 0)
	distTxt.Parent = bg
	
	bg.Parent = Screen
	
	State.ESPObjects[player] = {Highlight = hl, Billboard = bg, DistText = distTxt}
end

local function toggleESP(enabled: boolean)
	if enabled then
		for _, p in ipairs(Players:GetPlayers()) do
			buildESP(p)
		end
		State.Connections.ESPAdd = Players.PlayerAdded:Connect(function(p)
			p.CharacterAdded:Connect(function() task.wait(1) buildESP(p) end)
		end)
		State.Connections.ESPChar = workspace.DescendantAdded:Connect(function(desc)
			local p = Players:GetPlayerFromCharacter(desc)
			if p and p ~= LocalPlayer then task.wait(1) buildESP(p) end
		end)
	else
		if State.Connections.ESPAdd then State.Connections.ESPAdd:Disconnect() end
		if State.Connections.ESPChar then State.Connections.ESPChar:Disconnect() end
		for _, objs in pairs(State.ESPObjects) do
			if objs.Highlight then objs.Highlight:Destroy() end
			if objs.Billboard then objs.Billboard:Destroy() end
		end
		table.clear(State.ESPObjects)
	end
end

RunService.Stepped:Connect(function()
	if State.Features.Noclip or State.NoclipRequests > 0 then
		local char = LocalPlayer.Character
		if char then
			for _, part in ipairs(char:GetDescendants()) do
				if part:IsA("BasePart") and part.CanCollide then
					part.CanCollide = false
				end
			end
		end
	end
	
	if State.Features.ESP then
		local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if root then
			for p, objs in pairs(State.ESPObjects) do
				if p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
					local dist = (root.Position - p.Character.HumanoidRootPart.Position).Magnitude
					objs.DistText.Text = string.format("[ %d studs ]", math.floor(dist))
				end
			end
		end
	end
end)

LocalPlayer.CharacterAdded:Connect(function(char)
	applyCharacterModifications(char)
end)

-- ==========================================
-- UI BUILDER LOGIC
-- ==========================================

local function createToggle(name: string, callback)
	local frame = create("Frame", {Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Parent = ContentScroll})
	create("TextLabel", {Size = UDim2.new(1, -50, 1, 0), BackgroundTransparency = 1, Text = name, TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame})
	local btn = create("TextButton", {Size = UDim2.new(0, 40, 0, 20), Position = UDim2.new(1, -40, 0.5, -10), BackgroundColor3 = Color3.fromRGB(80, 80, 80), Text = "", Parent = frame}, {create("UICorner", {CornerRadius = UDim.new(1, 0)})})
	local indicator = create("Frame", {Size = UDim2.new(0, 16, 0, 16), Position = UDim2.new(0, 2, 0.5, -8), BackgroundColor3 = Color3.new(1,1,1), Parent = btn}, {create("UICorner", {CornerRadius = UDim.new(1, 0)})})
	
	btn.MouseButton1Click:Connect(function()
		local isActive = not State.Features[name:gsub(" ", "")]
		State.Features[name:gsub(" ", "")] = isActive
		TweenService:Create(indicator, TweenInfo.new(0.2), {Position = isActive and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)}):Play()
		TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = isActive and Color3.fromRGB(50, 150, 50) or Color3.fromRGB(80, 80, 80)}):Play()
		callback(isActive)
	end)
	return btn
end

local function createSlider(name: string, min: number, max: number, default: number, callback)
	local frame = create("Frame", {Size = UDim2.new(1, 0, 0, 45), BackgroundTransparency = 1, Parent = ContentScroll})
	local title = create("TextLabel", {Size = UDim2.new(1, -50, 0, 20), BackgroundTransparency = 1, Text = name .. ": " .. default, TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame})
	local track = create("Frame", {Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(60, 60, 60), Parent = frame}, {create("UICorner", {CornerRadius = UDim.new(1, 0)})})
	local fill = create("Frame", {Size = UDim2.new((default-min)/(max-min), 0, 1, 0), BackgroundColor3 = Color3.fromRGB(100, 150, 255), Parent = track}, {create("UICorner", {CornerRadius = UDim.new(1, 0)})})
	local input = create("TextBox", {Size = UDim2.new(0, 40, 0, 20), Position = UDim2.new(1, -40, 0, 0), BackgroundColor3 = Color3.fromRGB(40,40,45), Text = tostring(default), TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 12, Parent = frame}, {create("UICorner", {CornerRadius = UDim.new(0, 4)})})
	
	local function update(val)
		val = math.clamp(tonumber(val) or default, min, max)
		fill.Size = UDim2.new((val-min)/(max-min), 0, 1, 0)
		title.Text = name .. ": " .. val
		input.Text = tostring(val)
		callback(val)
	end
	
	input.FocusLost:Connect(function() update(input.Text) end)
	
	local sliding = false
	track.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			sliding = true
		end
	end)
	UserInputService.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			sliding = false
		end
	end)
	RunService.Heartbeat:Connect(function()
		if sliding then
			local mouse = UserInputService:GetMouseLocation()
			local rel = math.clamp((mouse.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
			update(math.floor(min + (max - min) * rel))
		end
	end)
end

local function createDropdown(name: string, itemsFn, callback)
	local frame = create("Frame", {Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, Parent = ContentScroll})
	create("TextLabel", {Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = name, TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame})
	local btn = create("TextButton", {Size = UDim2.new(1, 0, 0, 25), Position = UDim2.new(0, 0, 0, 25), BackgroundColor3 = Color3.fromRGB(50,50,55), Text = "Select...", TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 12, Parent = frame}, {create("UICorner", {CornerRadius = UDim.new(0, 4)})})
	
	btn.MouseButton1Click:Connect(function()
		for _, child in ipairs(Screen:GetChildren()) do if child.Name == "DropdownList" then child:Destroy() end end
		
		local items = itemsFn()
		local unique = {}
		for _, v in ipairs(items) do
			local n = v:IsA("Instance") and v.Name or v
			if not table.find(unique, n) then table.insert(unique, n) end
		end
		
		local list = create("ScrollingFrame", {Name = "DropdownList", Size = UDim2.new(0, 200, 0, 150), Position = UDim2.new(0, btn.AbsolutePosition.X, 0, btn.AbsolutePosition.Y + 30), BackgroundColor3 = Color3.fromRGB(40,40,45), Parent = Screen}, {create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder}), create("UICorner", {CornerRadius = UDim.new(0,4)})})
		for i, n in ipairs(unique) do
			local iBtn = create("TextButton", {Size = UDim2.new(1, 0, 0, 25), BackgroundTransparency = 1, Text = n, TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 12, LayoutOrder = i, Parent = list})
			iBtn.MouseButton1Click:Connect(function()
				btn.Text = n
				list:Destroy()
				callback(n)
			end)
		end
	end)
end

-- Populate UI
createToggle("Fix Lag", toggleFixLag)
createToggle("Full Bright", toggleFullBright)
createToggle("Noclip", function(val) State.Features.Noclip = val end)
createToggle("ESP", toggleESP)

createSlider("Walk Speed", CONFIG.WalkSpeed.Min, CONFIG.WalkSpeed.Max, CONFIG.WalkSpeed.Default, function(val)
	State.SpeedWalkValue = val
	State.Features.SpeedWalk = true
	applyCharacterModifications(LocalPlayer.Character)
end)

createSlider("High Jump", CONFIG.Jump.Min, CONFIG.Jump.Max, CONFIG.Jump.Default, function(val)
	State.HighJumpValue = val
	State.Features.HighJump = true
	applyCharacterModifications(LocalPlayer.Character)
end)

createDropdown("Select Enemy", getEnemyList, function(val) State.SelectedEnemyType = val end)
local autoFarmBtn = createToggle("Auto Farm", toggleAutoFarm)

createDropdown("Select Loot", function() return CONFIG.AutoLoot.Tags end, function(val) State.SelectedLootType = val end)
local autoLootBtn = createToggle("Auto Loot", toggleAutoLoot)

-- Input Handling for Menu Toggle
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == CONFIG.MenuToggleKey then
		State.MenuOpen = not State.MenuOpen
		MainFrame.Visible = State.MenuOpen
	end
end)
