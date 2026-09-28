-- Tạo Giao diện Người dùng (GUI) để dễ dàng chỉnh sửa trong game
local ScreenGui = Instance.new("ScreenGui")
local MainFrame = Instance.new("Frame")
local Title = Instance.new("TextLabel")
local SpeedInput = Instance.new("TextBox")
local JumpInput = Instance.new("TextBox")
local ApplyButton = Instance.new("TextButton")

-- Cấu hình Giao diện
ScreenGui.Parent = game.CoreGui
ScreenGui.ResetOnSpawn = false

MainFrame.Name = "SpeedJumpHub"
MainFrame.Parent = ScreenGui
MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
MainFrame.Position = UDim2.new(0.05, 0, 0.4, 0)
MainFrame.Size = UDim2.new(0, 180, 0, 200)
MainFrame.Active = true
MainFrame.Draggable = true -- Bạn có thể kéo giao diện đi mọi nơi trên màn hình

Title.Parent = MainFrame
Title.Size = UDim2.new(1, 0, 0, 30)
Title.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
Title.Text = "SPEED & JUMP HUB"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 14
Title.Font = Enum.Font.SourceSansBold

-- Ô nhập tốc độ (Mặc định của Roblox thông thường là 16)
SpeedInput.Parent = MainFrame
SpeedInput.Position = UDim2.new(0.1, 0, 0.25, 0)
SpeedInput.Size = UDim2.new(0.8, 0, 0, 30)
SpeedInput.PlaceholderText = "Tốc độ (Ví dụ: 50)"
SpeedInput.Text = "50"
SpeedInput.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
SpeedInput.TextColor3 = Color3.fromRGB(255, 255, 255)

-- Ô nhập lực nhảy (Mặc định của Roblox thông thường là 50)
JumpInput.Parent = MainFrame
JumpInput.Position = UDim2.new(0.1, 0, 0.45, 0)
JumpInput.Size = UDim2.new(0.8, 0, 0, 30)
JumpInput.PlaceholderText = "Lực nhảy (Ví dụ: 100)"
JumpInput.Text = "100"
JumpInput.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
JumpInput.TextColor3 = Color3.fromRGB(255, 255, 255)

-- Nút Áp dụng thay đổi
ApplyButton.Parent = MainFrame
ApplyButton.Position = UDim2.new(0.1, 0, 0.7, 0)
ApplyButton.Size = UDim2.new(0.8, 0, 0, 35)
ApplyButton.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
ApplyButton.Text = "ÁP DỤNG"
ApplyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ApplyButton.TextSize = 16
ApplyButton.Font = Enum.Font.SourceSansBold

-- Biến lưu thông số tùy chỉnh
local targetSpeed = 50
local targetJump = 100

-- Hàm cập nhật thuộc tính nhân vật liên tục
local player = game.Players.LocalPlayer
local function updateHumanoid(humanoid)
    if humanoid then
        -- Hỗ trợ cả 2 dạng nhảy phổ biến trong các game Roblox cũ và mới
        humanoid.UseJumpPower = true 
        humanoid.WalkSpeed = targetSpeed
        humanoid.JumpPower = targetJump
    end
end

-- Chạy vòng lặp để duy trì tốc độ ngay cả khi game cố tình reset hoặc khi bạn đổi map
task.spawn(function()
    while task.wait(0.5) do
        pcall(function()
            if player.Character and player.Character:FindFirstChildOfClass("Humanoid") then
                updateHumanoid(player.Character:FindFirstChildOfClass("Humanoid"))
            end
         pcall(function()
    end
end)

-- Sự kiện khi bấm nút Áp dụng
ApplyButton.MouseButton1Click:Connect(function()
    targetSpeed = tonumber(SpeedInput.Text) or 16
    targetJump = tonumber(JumpInput.Text) or 50
    
    if player.Character and player.Character:FindFirstChildOfClass("Humanoid") then
        updateHumanoid(player.Character:FindFirstChildOfClass("Humanoid"))
    end
end)
        
