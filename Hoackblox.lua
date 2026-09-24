-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")

-- Initialization Barrier
if not game:IsLoaded() then game.Loaded:Wait() end

-- Configuration
local CONFIG = {
	MenuToggleKey = Enum.KeyCode.RightControl,
	IdleTimeout = 4, 
	AutoFarm = {
		Distance = 7,
		TweenSpeed = 150,
		SearchInterval = 0.1,
		ClickDelay = 0.05
	}
}

-- Target-Based Quest Database 
local EnemyToQuest = {
	["Bandit"] = {Quest = "BanditQuest1", Id = 1},
	["Monkey"] = {Quest = "JungleQuest", Id = 1},
	["Gorilla"] = {Quest = "JungleQuest", Id = 2},
	["Pirate"] = {Quest = "BuggyQuest1", Id = 1},
	["Brute"] = {Quest = "BuggyQuest1", Id = 2},
	["Desert Bandit"] = {Quest = "DesertQuest", Id = 1},
	["Desert Officer"] = {Quest = "DesertQuest", Id = 2},
	["Snow Bandit"] = {Quest = "SnowQuest", Id = 1},
	["Snowman"] = {Quest = "SnowQuest", Id = 2},
	["Chief Petty Officer"] = {Quest = "MarineQuest2", Id = 1}
}

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 15)

-- State Management
local State = {
	MenuOpen = true,
	Features = {
		AutoFarm = false,
		AutoQuest = false,
		AutoClick = false,
		AntiAFK = false,
		Noclip = false
	},
	FarmPosition = "Above",
	SelectedWeaponType = "Any Tool",
	NoclipRequests = 0,
	ActiveTween = nil,
	SelectedEnemyType = nil,
	Target = nil,
	QuestActive = false
}

-- ==========================================
-- UNIVERSAL SCANNING & TARGETING
-- ==========================================

local function getEnemyFolders(): table
	local folders = {}
	local commonNames = {"Enemies", "NPCs", "Mobs", "Spawns", "MobSpawns"}
	for _, name in ipairs(commonNames) do
		local folder = workspace:FindFirstChild(name)
		if folder then table.insert(folders, folder) end
	end
	if #folders == 0 then table.insert(folders, workspace) end
	return folders
end

local function getLiveEnemyNames(): table
	local uniqueNames = {}
	for _, folder in ipairs(getEnemyFolders()) do
		for _, obj in ipairs(folder:GetChildren()) do
			if obj:IsA("Model") and obj:FindFirstChild("Humanoid") then
				if not table.find(uniqueNames, obj.Name) then
					table.insert(uniqueNames, obj.Name)
				end
			end
		end
	end
	return uniqueNames
end

local function findNearest(targetName: string): Instance?
	local char = LocalPlayer.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
	local root = char.HumanoidRootPart
	
	local closestDist = math.huge
	local closestInst = nil
	
	for _, folder in ipairs(getEnemyFolders()) do
		for _, inst in ipairs(folder:GetChildren()) do
			if inst:IsA("Model") and inst.Name == targetName and inst:FindFirstChild("HumanoidRootPart") then
				local hum = inst:FindFirstChild("Humanoid")
				if hum and hum.Health > 0 then
					local dist = (inst.HumanoidRootPart.Position - root.Position).Magnitude
					if dist < closestDist then
						closestDist = dist
						closestInst = inst
					end
				end
			end
		end
	end
	return closestInst
end

local function isNearMonster(radius: number): boolean
	local char = LocalPlayer.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return false end
	local root = char.HumanoidRootPart
	
	for _, folder in ipairs(getEnemyFolders()) do
		for _, inst in ipairs(folder:GetChildren()) do
			if inst:IsA("Model") and inst:FindFirstChild("HumanoidRootPart") then
				local hum = inst:FindFirstChild("Humanoid")
				if hum and hum.Health > 0 then
					local dist = (inst.HumanoidRootPart.Position - root.Position).Magnitude
					if dist <= radius then
						return true
					end
				end
			end
		end
	end
	return false
end

-- ==========================================
-- WEAPON AUTO-EQUIPMENT LOGIC
-- ==========================================

local function equipSelectedWeapon()
	local char = LocalPlayer.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	
	-- Check if a tool is already equipped
	local currentTool = char:FindFirstChildOfClass("Tool")
	if currentTool then return currentTool end
	
	-- Scan backpack for selected weapon type
	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
	if not backpack then return nil end
	
	for _, tool in ipairs(backpack:GetChildren()) do
		if tool:IsA("Tool") then
			local toolTip = tool:FindFirstChild("ToolTip") and tool.ToolTip.Value or ""
			local name = tool.Name:lower()
			local matches = false
			
			if State.SelectedWeaponType == "Any Tool" then
				matches = true
			elseif State.SelectedWeaponType == "Melee" and (toolTip == "Melee" or name:find("combat") or name:find("vô tân binh") or name:find("style") or name:find("black leg")) then
				matches = true
			elseif State.SelectedWeaponType == "Sword" and (toolTip == "Sword" or name:find("katana") or name:find("sword") or name:find("blade") or name:find("cutlass")) then
				matches = true
			elseif State.SelectedWeaponType == "Blox Fruit" and (toolTip == "Blox Fruit" or name:find("fruit")) then
				matches = true
			elseif State.SelectedWeaponType == "Gun" and (toolTip == "Gun" or name:find("gun") or name:find("slingshot") or name:find("cannon")) then
				matches = true
			end
			
			if matches then
				hum:EquipTool(tool)
				return tool
			end
		end
	end
	
	-- Fallback to first available tool in backpack
	local fallback = backpack:FindFirstChildOfClass("Tool")
	if fallback then
		hum:EquipTool(fallback)
		return fallback
	end
	
	return nil
end

local function autoEquipAndHaki()
	equipSelectedWeapon()
	
	local commF = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_")
	if commF then
		pcall(function() commF:InvokeServer("Buso") end)
	end
end

-- Pure Native Tool Activation (Air Swings)
local function executeClick()
	local char = LocalPlayer.Character
	if char then
		local tool = char:FindFirstChildOfClass("Tool")
		if tool then 
			tool:Activate() 
		end
	end
end

-- Standalone Auto Clicker
local function toggleStandaloneClicker(enabled: boolean)
	if enabled then
		task.spawn(function()
			while State.Features.AutoClick do
				if isNearMonster(45) then -- 45-stud detection radius
					equipSelectedWeapon()
					executeClick()
				end
				task.wait(CONFIG.AutoFarm.ClickDelay)
			end
		end)
	end
end

-- ==========================================
-- ADVANCED COMBAT & QUEST LOGIC
-- ==========================================

LocalPlayer.Idled:Connect(function()
	if State.Features.AntiAFK then
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end
end)

local function handleAutoQuest()
	if State.QuestActive or not State.Features.AutoQuest then return end
	State.QuestActive = true
	
	task.spawn(function()
		while State.Features.AutoQuest do
			local commF = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_")
			if commF and State.SelectedEnemyType then
				local questData = EnemyToQuest[State.SelectedEnemyType]
				if questData then
					pcall(function() commF:InvokeServer("StartQuest", questData.Quest, questData.Id) end)
				end
			end
			task.wait(5) 
		end
		State.QuestActive = false
	end)
end

local function calculateFarmCFrame(targetRoot: BasePart): CFrame
	local tCFrame = targetRoot.CFrame
	if State.FarmPosition == "Above" then return tCFrame * CFrame.new(0, CONFIG.AutoFarm.Distance, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	elseif State.FarmPosition == "Below" then return tCFrame * CFrame.new(0, -CONFIG.AutoFarm.Distance, 0) * CFrame.Angles(math.rad(90), 0, 0)
	elseif State.FarmPosition == "Behind" then return tCFrame * CFrame.new(0, 0, CONFIG.AutoFarm.Distance) end
	return tCFrame * CFrame.new(0, CONFIG.AutoFarm.Distance, 0)
end

local function cancelActiveMovement()
	if State.ActiveTween then State.ActiveTween:Cancel(); State.ActiveTween = nil end
end

-- ==========================================
-- FARMING LOOP
-- ==========================================

local function toggleAutoFarm(enabled: boolean)
	if enabled then
		State.NoclipRequests += 1
		task.spawn(function()
			while State.Features.AutoFarm do
				task.wait(CONFIG.AutoFarm.SearchInterval)
				
				local char = LocalPlayer.Character
				if not char or not char:FindFirstChild("HumanoidRootPart") then continue end
				local root = char.HumanoidRootPart
				
				if not State.SelectedEnemyType then continue end
				local target = findNearest(State.SelectedEnemyType)
				
				if target then
					local targetRoot = target.HumanoidRootPart
					local dist = (root.Position - targetRoot.Position).Magnitude
					
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
						root.CFrame = desiredCFrame
					end
					
					autoEquipAndHaki()
				else
					State.Target = nil
					cancelActiveMovement()
				end
			end
		end)
	else
		State.Target = nil
		State.NoclipRequests = math.max(0, State.NoclipRequests - 1)
		cancelActiveMovement()
	end
end

RunService.Stepped:Connect(function()
	if State.Features.Noclip or State.NoclipRequests > 0 then
		local char = LocalPlayer.Character
		if char then
			for _, part in ipairs(char:GetDescendants()) do
				if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
			end
		end
	end
end)

-- ==========================================
-- UI FACTORY & IDLE HIDING LOGIC
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

local MasterGroup = create("CanvasGroup", {
	Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, GroupTransparency = 0, Parent = Screen
})

local ToggleButton = create("TextButton", {
	Size = UDim2.new(0, 45, 0, 45), Position = UDim2.new(0, 15, 0.5, -22),
	BackgroundColor3 = Color3.fromRGB(30, 30, 35), Text = "☰",
	TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 24,
	Active = true, Draggable = true, Parent = MasterGroup
}, {
	create("UICorner", {CornerRadius = UDim.new(0, 8)}),
	create("UIStroke", {Color = Color3.fromRGB(60, 60, 65), Thickness = 1})
})

local MainFrame = create("Frame", {
	Size = UDim2.new(0, 300, 0, 480), Position = UDim2.new(0.5, -150, 0.5, -240),
	BackgroundColor3 = Color3.fromRGB(30, 30, 35), BorderSizePixel = 0,
	Active = true, Visible = State.MenuOpen, Parent = MasterGroup
}, {
	create("UICorner", {CornerRadius = UDim.new(0, 8)}),
	create("UIStroke", {Color = Color3.fromRGB(60, 60, 65), Thickness = 1})
})

local Topbar = create("Frame", {
	Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(40, 40, 45), Parent = MainFrame
}, {
	create("UICorner", {CornerRadius = UDim.new(0, 8)}),
	create("TextLabel", {
		Size = UDim2.new(1, -60, 1, 0), Position = UDim2.new(0, 10, 0, 0),
		BackgroundTransparency = 1, Text = "Utility Menu v7",
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

ToggleButton.MouseButton1Click:Connect(function()
	State.MenuOpen = not State.MenuOpen
	MainFrame.Visible = State.MenuOpen
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == CONFIG.MenuToggleKey then
		State.MenuOpen = not State.MenuOpen
		MainFrame.Visible = State.MenuOpen
	end
end)

local lastInteraction = tick()
local uiIsVisible = true

local function wakeUpUI()
	lastInteraction = tick()
	if not uiIsVisible then
		uiIsVisible = true
		MasterGroup.Visible = true
		TweenService:Create(MasterGroup, TweenInfo.new(0.3), {GroupTransparency = 0}):Play()
	end
end

UserInputService.InputBegan:Connect(wakeUpUI)
UserInputService.InputChanged:Connect(wakeUpUI)

task.spawn(function()
	while true do
		task.wait(0.5)
		if uiIsVisible and (tick() - lastInteraction > CONFIG.IdleTimeout) then
			uiIsVisible = false
			local fadeOut = TweenService:Create(MasterGroup, TweenInfo.new(0.5), {GroupTransparency = 1})
			fadeOut:Play()
			fadeOut.Completed:Wait()
			if not uiIsVisible then MasterGroup.Visible = false end 
		end
	end
end)

-- ==========================================
-- POPULATE UI
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

local function createDynamicDropdown(name: string, getItemsFunc, callback)
	local frame = create("Frame", {Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, Parent = ContentScroll})
	create("TextLabel", {Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = name, TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame})
	local btn = create("TextButton", {Size = UDim2.new(1, 0, 0, 25), Position = UDim2.new(0, 0, 0, 25), BackgroundColor3 = Color3.fromRGB(50,50,55), Text = "Select Option...", TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 12, Parent = frame}, {create("UICorner", {CornerRadius = UDim.new(0, 4)})})
	
	btn.MouseButton1Click:Connect(function()
		for _, child in ipairs(MasterGroup:GetChildren()) do if child.Name == "DropdownList" then child:Destroy() end end
		
		local items = type(getItemsFunc) == "function" and getItemsFunc() or getItemsFunc
		if #items == 0 then btn.Text = "No options found!"; task.wait(1); btn.Text = "Select Option..."; return end
		
		local list = create("ScrollingFrame", {Name = "DropdownList", Size = UDim2.new(0, 200, 0, math.min(#items * 25, 150)), Position = UDim2.new(0, btn.AbsolutePosition.X, 0, btn.AbsolutePosition.Y + 30), BackgroundColor3 = Color3.fromRGB(40,40,45), CanvasSize = UDim2.new(0,0,0,#items*25), ScrollBarThickness = 2, Parent = MasterGroup}, {create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder}), create("UICorner", {CornerRadius = UDim.new(0,4)})})
		for i, n in ipairs(items) do
			local iBtn = create("TextButton", {Size = UDim2.new(1, 0, 0, 25), BackgroundTransparency = 1, Text = n, TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 12, LayoutOrder = i, Parent = list})
			iBtn.MouseButton1Click:Connect(function() btn.Text = n; list:Destroy(); callback(n) end)
		end
	end)
end

createToggle("Auto Click", toggleStandaloneClicker)
createDynamicDropdown("Select Weapon", {"Any Tool", "Melee", "Sword", "Blox Fruit", "Gun"}, function(val) State.SelectedWeaponType = val end)
createToggle("Auto Quest", handleAutoQuest)
createToggle("Anti AFK", nil)
createToggle("Noclip", function(val) State.Features.Noclip = val end)
createDynamicDropdown("Select Enemy", getLiveEnemyNames, function(val) State.SelectedEnemyType = val end)
createDynamicDropdown("Farm Position", {"Above", "Below", "Behind"}, function(val) State.FarmPosition = val end)
createToggle("Auto Farm", toggleAutoFarm)
