-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local VirtualUser = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Initialization Barrier
if not game:IsLoaded() then game.Loaded:Wait() end

-- Configuration
local CONFIG = {
	MenuToggleKey = Enum.KeyCode.RightControl,
	AutoFarm = {
		Distance = 7,
		TweenSpeed = 150,
		SearchInterval = 0.1,
		ClickDelay = 0.05 -- Hyper-fast click rate
	}
}

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 15)

-- State Management
local State = {
	MenuOpen = true,
	Features = {
		AutoFarm = false,
		AutoQuest = false,
		AntiAFK = false,
		Noclip = false
	},
	FarmPosition = "Above",
	NoclipRequests = 0,
	ActiveTween = nil,
	SelectedEnemyType = nil,
	Target = nil,
	ClickerActive = false,
	QuestActive = false
}

-- ==========================================
-- ADVANCED COMBAT & QUEST LOGIC
-- ==========================================

-- Anti-AFK
LocalPlayer.Idled:Connect(function()
	if State.Features.AntiAFK then
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end
end)

-- Continuous Combat Clicker
local function startClicker()
	if State.ClickerActive then return end
	State.ClickerActive = true
	
	task.spawn(function()
		while State.Features.AutoFarm and State.Target do
			local char = LocalPlayer.Character
			if char then
				-- 1. Force Equip Tool
				local tool = char:FindFirstChildOfClass("Tool") or LocalPlayer.Backpack:FindFirstChildOfClass("Tool")
				if tool then
					if tool.Parent ~= char then
						local hum = char:FindFirstChild("Humanoid")
						if hum then hum:EquipTool(tool) end
					end
					-- 2. Standard Activation
					tool:Activate()
				end
				
				-- 3. Hardware Click Simulation (Bypasses custom combat remotes)
				pcall(function()
					VirtualUser:CaptureController()
					VirtualUser:ClickButton1(Vector2.new(0, 0))
				end)
				
				-- 4. Executor Level Click (If supported by your injector)
				if mouse1click then pcall(mouse1click) end
			end
			task.wait(CONFIG.AutoFarm.ClickDelay)
		end
		State.ClickerActive = false
	end)
end

-- Level Detection (Adapts to common stats folders)
local function getPlayerLevel()
	local data = LocalPlayer:FindFirstChild("Data")
	if data and data:FindFirstChild("Level") then return data.Level.Value end
	
	local stats = LocalPlayer:FindFirstChild("leaderstats")
	if stats and stats:FindFirstChild("Level") then return stats.Level.Value end
	
	return 1
end

-- Auto Quest Handler
local function handleAutoQuest()
	if State.QuestActive or not State.Features.AutoQuest then return end
	State.QuestActive = true
	
	task.spawn(function()
		while State.Features.AutoQuest do
			local level = getPlayerLevel()
			
			-- Example standard Quest Remote injection (Common in games like Blox Fruits)
			local commF = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_")
			if commF then
				-- This is a generic blueprint. The exact strings depend on the game's specific quest database.
				-- For Level 29 (Gorilla/Jungle), it typically looks like this:
				if level >= 20 and level < 30 then
					pcall(function()
						commF:InvokeServer("StartQuest", "JungleQuest", 2) -- Gorilla Quest
					end)
				end
			end
			
			task.wait(5) -- Check for new quests every 5 seconds
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

local function findNearest(list: table): Instance?
	local char = LocalPlayer.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
	local root = char.HumanoidRootPart
	
	local closestDist = math.huge
	local closestInst = nil
	
	for _, inst in ipairs(list) do
		if inst:IsA("Model") and inst.Name == State.SelectedEnemyType and inst:FindFirstChild("HumanoidRootPart") then
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
	return closestInst
end

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
				
				-- Automatically pull active enemies from workspace
				local enemies = workspace.Enemies:GetChildren() 
				local target = findNearest(enemies)
				
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
					
					-- Fire the continuous clicker
					startClicker()
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
				if part:IsA("BasePart") and part.CanCollide then
					part.CanCollide = false
				end
			end
		end
	end
end)

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

local MainFrame = create("Frame", {
	Size = UDim2.new(0, 300, 0, 450), Position = UDim2.new(0.5, -150, 0.5, -225),
	BackgroundColor3 = Color3.fromRGB(30, 30, 35), BorderSizePixel = 0, Active = true, Parent = Screen
}, {
	create("UICorner", {CornerRadius = UDim.new(0, 8)})
})

local ContentScroll = create("ScrollingFrame", {
	Size = UDim2.new(1, -20, 1, -40), Position = UDim2.new(0, 10, 0, 35),
	BackgroundTransparency = 1, ScrollBarThickness = 4,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = MainFrame
}, {
	create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8)})
})

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

local function createDropdown(name: string, items, callback)
	local frame = create("Frame", {Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, Parent = ContentScroll})
	create("TextLabel", {Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = name, TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame})
	local btn = create("TextButton", {Size = UDim2.new(1, 0, 0, 25), Position = UDim2.new(0, 0, 0, 25), BackgroundColor3 = Color3.fromRGB(50,50,55), Text = "Select...", TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 12, Parent = frame}, {create("UICorner", {CornerRadius = UDim.new(0, 4)})})
	
	btn.MouseButton1Click:Connect(function()
		for _, child in ipairs(Screen:GetChildren()) do if child.Name == "DropdownList" then child:Destroy() end end
		local list = create("ScrollingFrame", {Name = "DropdownList", Size = UDim2.new(0, 200, 0, 100), Position = UDim2.new(0, btn.AbsolutePosition.X, 0, btn.AbsolutePosition.Y + 30), BackgroundColor3 = Color3.fromRGB(40,40,45), Parent = Screen}, {create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder})})
		for i, n in ipairs(items) do
			local iBtn = create("TextButton", {Size = UDim2.new(1, 0, 0, 25), BackgroundTransparency = 1, Text = n, TextColor3 = Color3.new(1,1,1), Font = Enum.Font.Gotham, TextSize = 12, LayoutOrder = i, Parent = list})
			iBtn.MouseButton1Click:Connect(function() btn.Text = n; list:Destroy(); callback(n) end)
		end
	end)
end

-- POPULATE UI
createToggle("Auto Quest", handleAutoQuest)
createToggle("Anti AFK", nil)
createToggle("Noclip", function(val) State.Features.Noclip = val end)
createDropdown("Select Enemy", {"The Gorilla King", "Gorilla", "Monkey"}, function(val) State.SelectedEnemyType = val end)
createDropdown("Farm Position", {"Above", "Below", "Behind"}, function(val) State.FarmPosition = val end)
createToggle("Auto Farm", toggleAutoFarm)
