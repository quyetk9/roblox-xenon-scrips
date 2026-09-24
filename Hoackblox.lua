-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local VirtualUser = game:GetService("VirtualUser")

-- Initialization Barrier
if not game:IsLoaded() then game.Loaded:Wait() end

-- Configuration
local CONFIG = {
	MenuToggleKey = Enum.KeyCode.RightControl,
	WalkSpeed = { Min = 16, Max = 100, Default = 16 },
	Jump = { Min = 50, Max = 250, Default = 50 },
	AutoFarm = {
		Distance = 7, -- Distance from enemy
		TweenSpeed = 150,
		SearchInterval = 0.1,
		FallbackFolderName = "Enemies"
	},
	AutoLoot = {
		StoppingDistance = 1,
		TweenSpeed = 150,
		SearchInterval = 0.1,
		Tags = {"LootChest", "DevilFruit"}
	},
	ESP = {
		AllyColor = Color3.fromRGB(0, 255, 0),
		EnemyColor = Color3.fromRGB(255, 0, 0)
	}
}

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 15)

if not PlayerGui then
	error("[UtilityMenu] Initialization failed: PlayerGui did not load.")
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
		ESP = false,
		AntiAFK = false
	},
	FarmPosition = "Above", -- Default position
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
-- ADVANCED MECHANICS (ANTI-AFK & COMBAT)
-- ==========================================

-- Prevent 20-minute disconnect
LocalPlayer.Idled:Connect(function()
	if State.Features.AntiAFK then
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end
end)

local function attackTarget(target: Model)
	local char = LocalPlayer.Character
	if not char or not char:FindFirstChild("Humanoid") then return end
	
	-- Strict Auto-Equip (Prevents stun/unequip mechanics from disarming you)
	local tool = char:FindFirstChildOfClass("Tool") or LocalPlayer.Backpack:FindFirstChildOfClass("Tool")
	if tool then
		if tool.Parent ~= char then
			char.Humanoid:EquipTool(tool)
		end
		tool:Activate()
	end
	
	-- Simulated Hardware Clicking
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton1(Vector2.new(0, 0))
	end)
end

local function calculateFarmCFrame(targetRoot: BasePart): CFrame
	local tCFrame = targetRoot.CFrame
	
	if State.FarmPosition == "Above" then
		-- Look down at the target
		return tCFrame * CFrame.new(0, CONFIG.AutoFarm.Distance, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	elseif State.FarmPosition == "Below" then
		-- Look up at the target
		return tCFrame * CFrame.new(0, -CONFIG.AutoFarm.Distance, 0) * CFrame.Angles(math.rad(90), 0, 0)
	elseif State.FarmPosition == "Behind" then
		-- Look forward at the target's back
		return tCFrame * CFrame.new(0, 0, CONFIG.AutoFarm.Distance)
	end
	
	return tCFrame * CFrame.new(0, CONFIG.AutoFarm.Distance, 0)
end

local function cancelActiveMovement()
	if State.ActiveTween then
		State.ActiveTween:Cancel()
		State.ActiveTween = nil
	end
end

local function requestNoclip() State.NoclipRequests += 1 end
local function releaseNoclip() State.NoclipRequests = math.max(0, State.NoclipRequests - 1) end

-- ==========================================
-- UI FACTORY
-- ==========================================

local function create(className: string, properties: table, children: table?): Instance
	local inst = Instance.new(className)
	for k, v in pairs(properties) do inst[k] = v end
	if children then for _, child in ipairs(children) do child.Parent = inst end end
	return inst
end

for _, gui in ipairs(PlayerGui:GetChildren()) do
	if gui.Name == "UtilityMenu" then gui:Destroy() end
end

local Screen = create("ScreenGui", {Name = "UtilityMenu", ResetOnSpawn = false, IgnoreGuiInset = true, Parent = PlayerGui})

local ToggleButton = create("TextButton", {
	Size = UDim2.new(0, 45, 0, 45), Position = UDim2.new(0, 15, 0.5, -22),
	BackgroundColor3 = Color3.fromRGB(30, 30, 35), Text = "☰",
	TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 24,
	Active = true, Draggable = true, Parent = Screen
}, {
	create("UICorner", {CornerRadius = UDim.new(0, 8)}),
	create("UIStroke", {Color = Color3.fromRGB(60, 60, 65), Thickness = 1})
})

local MainFrame = create("Frame", {
	Size = UDim2.new(0, 300, 0, 450), Position = UDim2.new(0.5, -150, 0.5, -225),
	BackgroundColor3 = Color3.fromRGB(30, 30, 35), BorderSizePixel = 0,
	Active = true, Visible = State.MenuOpen, Parent = Screen
}, {
	create("UICorner", {CornerRadius = UDim.new(0, 8)}),
	create("UIStroke", {Color = Color3.fromRGB(60, 60, 65), Thickness = 1})
})

ToggleButton.MouseButton1Click:Connect(function()
	State.MenuOpen = not State.MenuOpen
	MainFrame.Visible = State.MenuOpen
end)

local Topbar = create("Frame", {
	Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(40, 40, 45), Parent = MainFrame
}, {
	create("UICorner", {CornerRadius = UDim.new(0, 8)}),
	create("TextLabel", {
		Size = UDim2.new(1, -60, 1, 0), Position = UDim2.new(0, 10, 0, 0),
		BackgroundTransparency = 1, Text = "Utility Menu v2",
		TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold,
		TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left
	})
})

create("Frame", {Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0, 0, 1, -8), BackgroundColor3 = Color3.fromRGB(40, 40, 45), BorderSizePixel = 0, Parent = Topbar})

local ContentScroll = create("ScrollingFrame", {
	Size = UDim2.new(1, -20, 1, -40), Position = UDim2.new(0, 10, 0, 35),
	BackgroundTransparency = 1, ScrollBarThickness = 4,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = MainFrame
}, {
	create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8)})
})

local dragging, dragInput, dragStart, startPos
Topbar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true; dragStart = input.Position; startPos = MainFrame.Position
		input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
	end
end)
Topbar.InputChanged:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end end)
RunService.Heartbeat:Connect(function()
	if dragging and dragInput then
		local delta = dragInput.Position - dragStart
		MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end)

local function notify(message: string, isError: boolean)
	local notif = create("TextLabel", {
		Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, -40),
		BackgroundColor3 = isError and Color3.fromRGB(150, 50, 50) or Color3.fromRGB(50, 150, 50),
		Text = message, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamSemibold, TextSize = 12, Parent = MainFrame
	}, {create("UICorner", {CornerRadius = UDim.new(0, 4)})})
	
	TweenService:Create(notif, TweenInfo.new(0.3), {Position = UDim2.new(0, 10, 0, 10)}):Play()
	task.delay(2.5, function()
		local out = TweenService:Create(notif, TweenInfo.new(0.3), {Position = UDim2.new(0, 10, 0, -40), BackgroundTransparency = 1, TextTransparency = 1})
		out:Play(); out.Completed:Wait(); notif:Destroy()
	end)
end

-- ==========================================
-- CORE SCRIPTS & FARMING LOGIC
-- ==========================================

local function findNearest(list: table, targetClass: string): Instance?
	local char = LocalPlayer.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
	local root = char.HumanoidRootPart
	
	local closestDist = math.huge
	local closestInst = nil
	
	for _, inst in ipairs(list) do
		local pos, valid = nil, false
		
		if targetClass == "Enemy" then
			if inst:IsA("Model") and inst.Name == State.SelectedEnemyType and inst:FindFirstChild("HumanoidRootPart") then
				local hum = inst:FindFirstChild("Humanoid")
				if hum and hum.Health > 0 then
					pos = inst.HumanoidRootPart.Position
					valid = true
				end
			end
		end
		
		if valid and pos then
			local dist = (pos - root.Position).Magnitude
			if dist < closestDist then
				closestDist = dist; closestInst = inst
			end
		end
	end
	return closestInst
end

local function getEnemyList(): table
	local enemies = CollectionService:GetTagged("FarmableEnemy")
	local fallbackFolder = workspace:FindFirstChild(CONFIG.AutoFarm.FallbackFolderName)
	if #enemies == 0 and fallbackFolder then
		for _, child in ipairs(fallbackFolder:GetChildren()) do table.insert(enemies, child) end
	end
	return enemies
end

local function toggleAutoFarm(enabled: boolean)
	if enabled then
		requestNoclip()
		
		State.Connections.AutoFarm = task.spawn(function()
			while State.Features.AutoFarm do
				task.wait(CONFIG.AutoFarm.SearchInterval)
				
				local char = LocalPlayer.Character
				if not char or not char:FindFirstChild("HumanoidRootPart") then continue end
				local root = char.HumanoidRootPart
				
				if not State.SelectedEnemyType then continue end
				
				local target = findNearest(getEnemyList(), "Enemy")
				if target then
					local targetRoot = target.HumanoidRootPart
					local targetPos = targetRoot.Position
					local dist = (root.Position - targetPos).Magnitude
					
					-- Reset physical velocity to prevent getting flung when teleporting fast
					root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
					root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
					
					local desiredCFrame = calculateFarmCFrame(targetRoot)
					
					if State.Target ~= target or (State.ActiveTween and State.ActiveTween.PlaybackState ~= Enum.PlaybackState.Playing) or dist > (CONFIG.AutoFarm.Distance + 2) then
						State.Target = target
						cancelActiveMovement()
						
						local timeToTarget = math.clamp(dist / CONFIG.AutoFarm.TweenSpeed, 0.1, 5)
						State.ActiveTween = TweenService:Create(root, TweenInfo.new(timeToTarget, Enum.EasingStyle.Linear), {CFrame = desiredCFrame})
						State.ActiveTween:Play()
					else
						-- Stick perfectly to the target if we are close enough
						root.CFrame = desiredCFrame
					end
					
					attackTarget(target)
				else
					State.Target = nil
					cancelActiveMovement()
				end
			end
		end)
	else
		if State.Connections.AutoFarm then task.cancel(State.Connections.AutoFarm); State.Connections.AutoFarm = nil end
		State.Target = nil
		releaseNoclip()
		cancelActiveMovement()
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
		if callback then callback(isActive) end
	end)
end

local function createDropdown(name: string, itemsFn, callback)
	local frame = create("Frame", {Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, Parent = ContentScroll})
	create("TextLabel", {Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = name, TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame})
	local btn = create("TextButton", {Size = UDim2.new(1, 0, 0, 25), Position = UDim2.new(0, 0, 0, 25), BackgroundColor3 = Color3.fromRGB(50,50,55), Text = "Select...", TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 12, Parent = frame}, {create("UICorner", {CornerRadius = UDim.new(0, 4)})})
	
	btn.MouseButton1Click:Connect(function()
		for _, child in ipairs(Screen:GetChildren()) do if child.Name == "DropdownList" then child:Destroy() end end
		
		local items = type(itemsFn) == "function" and itemsFn() or itemsFn
		local unique = {}
		for _, v in ipairs(items) do
			local n = typeof(v) == "Instance" and v.Name or v
			if not table.find(unique, n) then table.insert(unique, n) end
		end
		
		local list = create("ScrollingFrame", {Name = "DropdownList", Size = UDim2.new(0, 200, 0, math.min(#unique * 25, 150)), Position = UDim2.new(0, btn.AbsolutePosition.X, 0, btn.AbsolutePosition.Y + 30), BackgroundColor3 = Color3.fromRGB(40,40,45), CanvasSize = UDim2.new(0,0,0,#unique*25), ScrollBarThickness = 2, Parent = Screen}, {create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder}), create("UICorner", {CornerRadius = UDim.new(0,4)})})
		for i, n in ipairs(unique) do
			local iBtn = create("TextButton", {Size = UDim2.new(1, 0, 0, 25), BackgroundTransparency = 1, Text = n, TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 12, LayoutOrder = i, Parent = list})
			iBtn.MouseButton1Click:Connect(function()
				btn.Text = n; list:Destroy(); callback(n)
			end)
		end
	end)
end

-- POPULATE UI
createToggle("Anti AFK", nil)
createToggle("Noclip", function(val) State.Features.Noclip = val end)

createDropdown("Select Enemy", getEnemyList, function(val) State.SelectedEnemyType = val end)
createDropdown("Farm Position", {"Above", "Below", "Behind"}, function(val) State.FarmPosition = val end)
createToggle("Auto Farm", toggleAutoFarm)

-- Keybind hook
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == CONFIG.MenuToggleKey then
		State.MenuOpen = not State.MenuOpen
		MainFrame.Visible = State.MenuOpen
	end
end)

local Topbar = create("Frame", {
	Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(40, 40, 45), Parent = MainFrame
}, {
	create("UICorner", {CornerRadius = UDim.new(0, 8)}),
	create("TextLabel", {
		Size = UDim2.new(1, -60, 1, 0), Position = UDim2.new(0, 10, 0, 0),
		BackgroundTransparency = 1, Text = "Utility Menu v2",
		TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold,
		TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left
	})
})

create("Frame", {Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0, 0, 1, -8), BackgroundColor3 = Color3.fromRGB(40, 40, 45), BorderSizePixel = 0, Parent = Topbar})

local ContentScroll = create("ScrollingFrame", {
	Size = UDim2.new(1, -20, 1, -40), Position = UDim2.new(0, 10, 0, 35),
	BackgroundTransparency = 1, ScrollBarThickness = 4,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = MainFrame
}, {
	create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8)})
})

local dragging, dragInput, dragStart, startPos
Topbar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true; dragStart = input.Position; startPos = MainFrame.Position
		input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
	end
end)
Topbar.InputChanged:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end end)
RunService.Heartbeat:Connect(function()
	if dragging and dragInput then
		local delta = dragInput.Position - dragStart
		MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end)

local function notify(message: string, isError: boolean)
	local notif = create("TextLabel", {
		Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, -40),
		BackgroundColor3 = isError and Color3.fromRGB(150, 50, 50) or Color3.fromRGB(50, 150, 50),
		Text = message, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamSemibold, TextSize = 12, Parent = MainFrame
	}, {create("UICorner", {CornerRadius = UDim.new(0, 4)})})
	
	TweenService:Create(notif, TweenInfo.new(0.3), {Position = UDim2.new(0, 10, 0, 10)}):Play()
	task.delay(2.5, function()
		local out = TweenService:Create(notif, TweenInfo.new(0.3), {Position = UDim2.new(0, 10, 0, -40), BackgroundTransparency = 1, TextTransparency = 1})
		out:Play(); out.Completed:Wait(); notif:Destroy()
	end)
end

-- ==========================================
-- CORE SCRIPTS & FARMING LOGIC
-- ==========================================

local function findNearest(list: table, targetClass: string): Instance?
	local char = LocalPlayer.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
	local root = char.HumanoidRootPart
	
	local closestDist = math.huge
	local closestInst = nil
	
	for _, inst in ipairs(list) do
		local pos, valid = nil, false
		
		if targetClass == "Enemy" then
			if inst:IsA("Model") and inst.Name == State.SelectedEnemyType and inst:FindFirstChild("HumanoidRootPart") then
				local hum = inst:FindFirstChild("Humanoid")
				if hum and hum.Health > 0 then
					pos = inst.HumanoidRootPart.Position
					valid = true
				end
			end
		end
		
		if valid and pos then
			local dist = (pos - root.Position).Magnitude
			if dist < closestDist then
				closestDist = dist; closestInst = inst
			end
		end
	end
	return closestInst
end

local function getEnemyList(): table
	local enemies = CollectionService:GetTagged("FarmableEnemy")
	local fallbackFolder = workspace:FindFirstChild(CONFIG.AutoFarm.FallbackFolderName)
	if #enemies == 0 and fallbackFolder then
		for _, child in ipairs(fallbackFolder:GetChildren()) do table.insert(enemies, child) end
	end
	return enemies
end

local function toggleAutoFarm(enabled: boolean)
	if enabled then
		requestNoclip()
		
		State.Connections.AutoFarm = task.spawn(function()
			while State.Features.AutoFarm do
				task.wait(CONFIG.AutoFarm.SearchInterval)
				
				local char = LocalPlayer.Character
				if not char or not char:FindFirstChild("HumanoidRootPart") then continue end
				local root = char.HumanoidRootPart
				
				if not State.SelectedEnemyType then continue end
				
				local target = findNearest(getEnemyList(), "Enemy")
				if target then
					local targetRoot = target.HumanoidRootPart
					local targetPos = targetRoot.Position
					local dist = (root.Position - targetPos).Magnitude
					
					-- Reset physical velocity to prevent getting flung when teleporting fast
					root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
					root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
					
					local desiredCFrame = calculateFarmCFrame(targetRoot)
					
					if State.Target ~= target or (State.ActiveTween and State.ActiveTween.PlaybackState ~= Enum.PlaybackState.Playing) or dist > (CONFIG.AutoFarm.Distance + 2) then
						State.Target = target
						cancelActiveMovement()
						
						local timeToTarget = math.clamp(dist / CONFIG.AutoFarm.TweenSpeed, 0.1, 5)
						State.ActiveTween = TweenService:Create(root, TweenInfo.new(timeToTarget, Enum.EasingStyle.Linear), {CFrame = desiredCFrame})
						State.ActiveTween:Play()
					else
						-- Stick perfectly to the target if we are close enough
						root.CFrame = desiredCFrame
					end
					
					attackTarget(target)
				else
					State.Target = nil
					cancelActiveMovement()
				end
			end
		end)
	else
		if State.Connections.AutoFarm then task.cancel(State.Connections.AutoFarm); State.Connections.AutoFarm = nil end
		State.Target = nil
		releaseNoclip()
		cancelActiveMovement()
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
		if callback then callback(isActive) end
	end)
end

local function createDropdown(name: string, itemsFn, callback)
	local frame = create("Frame", {Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, Parent = ContentScroll})
	create("TextLabel", {Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = name, TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame})
	local btn = create("TextButton", {Size = UDim2.new(1, 0, 0, 25), Position = UDim2.new(0, 0, 0, 25), BackgroundColor3 = Color3.fromRGB(50,50,55), Text = "Select...", TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 12, Parent = frame}, {create("UICorner", {CornerRadius = UDim.new(0, 4)})})
	
	btn.MouseButton1Click:Connect(function()
		for _, child in ipairs(Screen:GetChildren()) do if child.Name == "DropdownList" then child:Destroy() end end
		
		local items = type(itemsFn) == "function" and itemsFn() or itemsFn
		local unique = {}
		for _, v in ipairs(items) do
			local n = typeof(v) == "Instance" and v.Name or v
			if not table.find(unique, n) then table.insert(unique, n) end
		end
		
		local list = create("ScrollingFrame", {Name = "DropdownList", Size = UDim2.new(0, 200, 0, math.min(#unique * 25, 150)), Position = UDim2.new(0, btn.AbsolutePosition.X, 0, btn.AbsolutePosition.Y + 30), BackgroundColor3 = Color3.fromRGB(40,40,45), CanvasSize = UDim2.new(0,0,0,#unique*25), ScrollBarThickness = 2, Parent = Screen}, {create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder}), create("UICorner", {CornerRadius = UDim.new(0,4)})})
		for i, n in ipairs(unique) do
			local iBtn = create("TextButton", {Size = UDim2.new(1, 0, 0, 25), BackgroundTransparency = 1, Text = n, TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 12, LayoutOrder = i, Parent = list})
			iBtn.MouseButton1Click:Connect(function()
				btn.Text = n; list:Destroy(); callback(n)
			end)
		end
	end)
end

-- POPULATE UI
createToggle("Anti AFK", nil)
createToggle("Noclip", function(val) State.Features.Noclip = val end)

createDropdown("Select Enemy", getEnemyList, function(val) State.SelectedEnemyType = val end)
createDropdown("Farm Position", {"Above", "Below", "Behind"}, function(val) State.FarmPosition = val end)
createToggle("Auto Farm", toggleAutoFarm)

-- Keybind hook
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == CONFIG.MenuToggleKey then
		State.MenuOpen = not State.MenuOpen
		MainFrame.Visible = State.MenuOpen
	end
end)
