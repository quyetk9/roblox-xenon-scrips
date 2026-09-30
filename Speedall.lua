local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer

-- 1. Tạo Giao diện và Icon Menu Đóng/Mở
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "UltimateCompatibleHub"
ScreenGui.ResetOnSpawn = false

local success, targetGui = pcall(function() return CoreGui end)
if not success or not targetGui then targetGui = player:WaitForChild("PlayerGui") end
ScreenGui.Parent = targetGui

-- Biến cấu hình mặc định
local maxWalkSpeed = 60    -- Tốc độ chạy dưới đất
local maxFlySpeed = 120    -- Tốc độ bay nhanh (Dùng CFrame)
local targetJump = 120     -- Lực nhảy
local currentSpeed = 16    
local acceleration = 2.0   -- Gia tốc tăng lên từ từ

-- Tạo nút bấm Tròn ⚡ để Đóng / Mở Menu
local ToggleButton = Instance.new("TextButton")
ToggleButton.Name = "MenuToggle"
ToggleButton.Parent = ScreenGui
ToggleButton.Position = UDim2.new(0.02, 0, 0.2, 0)
ToggleButton.Size = UDim2.new(0, 45, 0, 45)
ToggleButton.BackgroundColor3 = Color3.fromRGB(150, 0, 255) -- Màu tím tương thích cao
ToggleButton.Text = "⚡"
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.TextSize = 22
ToggleButton.Font = Enum.Font.SourceSansBold
local UICornerIcon = Instance.new("UICorner")
UICornerIcon.CornerRadius = UDim.new(1, 0)
UICornerIcon.Parent = ToggleButton
pcall(function() ToggleButton.Draggable = true end)

-- 2. Tạo Bảng Điều Khiển
local MainFrame = Instance.new("Frame")
local Title = Instance.new("TextLabel")
local SpeedInput = Instance.new("TextBox")
local FlyInput = Instance.new("TextBox")
local JumpInput = Instance.new("TextBox")
local ApplyButton = Instance.new("TextButton")

MainFrame.Name = "MainFrame"
MainFrame.Parent = ScreenGui
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
MainFrame.Position = UDim2.new(0.08, 0, 0.2, 0)
MainFrame.Size = UDim2.new(0, 190, 0, 250)
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)
pcall(function() MainFrame.Draggable = true end)

Title.Parent = MainFrame
Title.Size = UDim2.new(1, 0, 0, 35)
Title.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
Title.Text = "COMPATIBLE SPEED HUB"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 11
Title.Font = Enum.Font.SourceSansBold
Instance.new("UICorner", Title).CornerRadius = UDim.new(0, 10)

SpeedInput.Parent = MainFrame
SpeedInput.Position = UDim2.new(0.1, 0, 0.2, 0)
SpeedInput.Size = UDim2.new(0.8, 0, 0, 30)
SpeedInput.Text = tostring(maxWalkSpeed)
SpeedInput.PlaceholderText = "Tốc độ chạy đất"
SpeedInput.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
SpeedInput.TextColor3 = Color3.fromRGB(255, 255, 255)
Instance.new("UICorner", SpeedInput).CornerRadius = UDim.new(0, 6)

FlyInput.Parent = MainFrame
FlyInput.Position = UDim2.new(0.1, 0, 0.38, 0)
FlyInput.Size = UDim2.new(0.8, 0, 0, 30)
FlyInput.Text = tostring(maxFlySpeed)
FlyInput.PlaceholderText = "Tốc độ bay nhanh"
FlyInput.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
FlyInput.TextColor3 = Color3.fromRGB(255, 255, 255)
Instance.new("UICorner", FlyInput).CornerRadius = UDim.new(0, 6)

JumpInput.Parent = MainFrame
JumpInput.Position = UDim2.new(0.1, 0, 0.56, 0)
JumpInput.Size = UDim2.new(0.8, 0, 0, 30)
JumpInput.Text = tostring(targetJump)
JumpInput.PlaceholderText = "Lực nhảy"
JumpInput.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
JumpInput.TextColor3 = Color3.fromRGB(255, 255, 255)
Instance.new("UICorner", JumpInput).CornerRadius = UDim.new(0, 6)

ApplyButton.Parent = MainFrame
ApplyButton.Position = UDim2.new(0.1, 0, 0.76, 0)
ApplyButton.Size = UDim2.new(0.8, 0, 0, 35)
ApplyButton.BackgroundColor3 = Color3.fromRGB(150, 0, 255)
ApplyButton.Text = "ÁP DỤNG"
ApplyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ApplyButton.TextSize = 14
ApplyButton.Font = Enum.Font.SourceSansBold
Instance.new("UICorner", ApplyButton).CornerRadius = UDim.new(0, 6)

ToggleButton.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- 3. CƠ CHẾ ĐẨY CFRAME TRỰC TIẾP (Bất chấp script khác đè lực)
RunService.RenderStepped:Connect(function(deltaTime)
    pcall(function()
        local character = player.Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            local camera = workspace.CurrentCamera
            
            if humanoid and rootPart and camera then
                local isAirborne = humanoid.FloorMaterial == Enum.Material.Air
                
                if humanoid.MoveDirection.Magnitude > 0 then
                    if isAirborne then
                        -- TRẠNG THÁI TRÊN KHÔNG/BAY: Sử dụng CFrame dịch chuyển liên tục theo góc camera nhìn
                        if currentSpeed < maxFlySpeed then
                            currentSpeed = currentSpeed + acceleration
                        else
                            currentSpeed = maxFlySpeed
                        end
                        
                        -- Lấy hướng di chuyển dựa trên góc quay của Camera
                        local moveDir = camera.CFrame:VectorToWorldSpace(Vector3.new(
                            humanoid.MoveDirection.X, 
                            0, 
                            humanoid.MoveDirection.Z
                        ))
                        if moveDir.Magnitude > 0 then
                            moveDir = moveDir.Unit
                        end
                        
                        -- Ép vị trí nhân vật tiến lên phía trước bất kể script kia đang làm gì
                        rootPart.CFrame = rootPart.CFrame + (moveDir * currentSpeed * deltaTime)
                        
                        -- Triệt tiêu bớt lực rơi tự do khi đang di chuyển trên không để bay mượt hơn
                        local vel = rootPart.AssemblyLinearVelocity
                        rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
                    else
                        -- TRẠNG THÁI DƯỚI ĐẤT: Dùng cơ chế tăng tốc vật lý mượt như cũ
                        if currentSpeed < maxWalkSpeed then
                            currentSpeed = currentSpeed + acceleration
                        else
                            currentSpeed = maxWalkSpeed
                        end
                        
                        local velocity = rootPart.AssemblyLinearVelocity
                        rootPart.AssemblyLinearVelocity = Vector3.new(
                            humanoid.MoveDirection.X * currentSpeed, 
                            velocity.Y, 
                            humanoid.MoveDirection.Z * currentSpeed
                        )
                    end
                else
                    -- Phanh lại ngay lập tức khi thả phím di chuyển
                    currentSpeed = 16
                end
                
                -- Duy trì chỉ số nhảy
                humanoid.UseJumpPower = true
                humanoid.JumpPower = targetJump
                humanoid.JumpHeight = targetJump / 7
            end
        end
    end)
end)

ApplyButton.MouseButton1Click:Connect(function()
    maxWalkSpeed = tonumber(SpeedInput.Text) or 16
    maxFlySpeed = tonumber(FlyInput.Text) or 16
    targetJump = tonumber(JumpInput.Text) or 50
    
    local originalColor = ApplyButton.BackgroundColor3
    ApplyButton.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
    task.wait(0.15)
    ApplyButton.BackgroundColor3 = originalColor
end)
