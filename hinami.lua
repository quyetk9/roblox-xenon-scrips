if not game:IsLoaded() then game.Loaded:Wait() end

-- =======================================================================
-- LỚP BẢO VỆ CHẠY NGẦM: ĐÓNG BĂNG LOG & DỌN RÁC RAM (LUÔN BẬT CHỐNG VĂNG)
-- =======================================================================
local LogService = game:GetService("LogService")
pcall(function()
    if LogService then
        LogService.MessageOut:Connect(function(message, messageType) return nil end)
    end
end)

if hookfunction then
    pcall(function()
        hookfunction(print, function(...) return nil end)
        hookfunction(warn, function(...) return nil end)
        hookfunction(error, function(...) return nil end)
    end)
end

task.spawn(function()
    while task.wait(5) do
        collectgarbage("collect")
    end
end)

-- Khởi tạo các dịch vụ hệ thống
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

-- ==========================================
-- CẤU HÌNH THÔNG SỐ CHUẨN
-- ==========================================
local WALK_SPEED = 35         -- Tốc độ chạy đất khi TẮT trạng thái tổng hợp
local FLY_SPEED = 90          -- Tốc độ chuyển động khi BẬT trạng thái tổng hợp
local ALL_IN_ONE_KEY = Enum.KeyCode.E -- PHÍM CỐT LÕI "E": BẬT/TẮT TẤT CẢ TÍNH NĂNG

local isActivated = false -- Biến trạng thái tổng hợp

local mainLoopConnection = nil
local speedConnection = nil

-- HÀM DỌN SẠCH VÀ TẮT TẤT CẢ TRẠNG THÁI
local function DisableAllFeatures(humanoid)
    isActivated = false
    if mainLoopConnection then
        mainLoopConnection:Disconnect()
        mainLoopConnection = nil
    end
    if humanoid then
        humanoid.PlatformStand = false
    end
    -- Khôi phục va chạm tuyệt đối cho nhân vật khi tắt E
    local character = LocalPlayer.Character
    if character then
        for _, part in ipairs(character:GetChildren()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end
end

-- ==========================================
-- VÒNG LẶP CORE: CHẠY ĐỒNG THỜI BAY + ĐÁNH NHANH + XUYÊN TƯỜNG (KHÔNG XUYÊN SÀN)
-- ==========================================
local function StartAllFeatures(character)
    if not character then return end
    local rootPart = character:WaitForChild("HumanoidRootPart", 5)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if not rootPart or not humanoid then return end

    if not isActivated then
        DisableAllFeatures(humanoid)
        return
    end

    humanoid.PlatformStand = true 
    local camera = Workspace.CurrentCamera

    mainLoopConnection = RunService.RenderStepped:Connect(function()
        if not character or not character.Parent or not rootPart or not isActivated then
            DisableAllFeatures(humanoid)
            return
        end

        -------------------------------------------------------
        -- CHỨC NĂNG 1: BAY 3D CHUẨN HƯỚNG CAMERA (FLY)
        -------------------------------------------------------
        rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

        local cameraCFrame = camera.CFrame
        local moveDirection = Vector3.new(0, 0, 0)

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDirection = moveDirection + cameraCFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDirection = moveDirection - cameraCFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDirection = moveDirection - cameraCFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDirection = moveDirection + cameraCFrame.RightVector end

        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDirection = moveDirection + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then moveDirection = moveDirection - Vector3.new(0, 1, 0) end

        if moveDirection.Magnitude > 0 then
            rootPart.CFrame = rootPart.CFrame + (moveDirection.Unit * FLY_SPEED * 0.016)
        end

        local lookPos = cameraCFrame.Position + cameraCFrame.LookVector * 20
        rootPart.CFrame = CFrame.new(rootPart.CFrame.Position, Vector3.new(lookPos.X, rootPart.CFrame.Position.Y, lookPos.Z))

        -------------------------------------------------------
        -- CHỨC NĂNG 2: TỰ ĐỘNG ĐÁNH NHANH (FAST ATTACK)
        -------------------------------------------------------
        local tool = character:FindFirstChildOfClass("Tool")
        if tool then
            VirtualUser:CaptureController()
            VirtualUser:Button1Down(Vector2.new(0, 0))
            
            local animator = humanoid:FindFirstChildOfClass("Animator")
            if animator then
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    if track.Name:lower():find("attack") or track.Name:lower():find("slash") or track.Name:lower():find("swing") then
                        track:AdjustSpeed(100)
                    end
                end
            end
        end

        -------------------------------------------------------
        -- CHỨC NĂNG 3: RAYCAST NOCLIP CHUẨN XÁC (KHÔNG XUYÊN MẶT ĐẤT)
        -------------------------------------------------------
        -- GIẢI PHÁP TRIỆT ĐỂ: Chỉ tắt va chạm nhân vật khi phía trước có tường, KHÔNG tắt CanCollide của Map bừa bãi.
        -- Tạo 1 tia Raycast bắn thẳng về hướng nhân vật đang di chuyển/nhìn để check tường thành trước mặt.
        local lookVector = rootPart.CFrame.LookVector
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.FilterDescendantsInstances = {character}
        
        -- Bắn tia dài 6 stud ra phía trước mặt
        local raycastResult = Workspace:Raycast(rootPart.Position, lookVector * 6, raycastParams)
        
        if raycastResult and raycastResult.Instance then
            local targetInstance = raycastResult.Instance
            local targetName = targetInstance.Name:lower()
            local normal = raycastResult.Normal
            
            -- Kiểm tra xem vật thể trước mặt là TƯỜNG ĐỨNG hay SÀN NGANG bằng Vector Pháp Tuyến (Normal.Y < 0.7 nghĩa là dốc đứng hoặc tường)
            if math.abs(normal.Y) < 0.7 and not targetName:find("floor") and not targetName:find("ground") and not targetName:find("island") then
                -- Nếu là tường dốc đứng hoặc rào chắn, cho phép nhân vật đi xuyên qua
                for _, part in ipairs(character:GetChildren()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            else
                -- Nếu là sàn nhà hoặc đất bằng phẳng, khóa chặt va chạm nhân vật để KHÔNG bị lọt hố
                for _, part in ipairs(character:GetChildren()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = (part.Name == "HumanoidRootPart" or part.Name == "UpperTorso" or part.Name == "LowerTorso")
                    end
                end
            end
        else
            -- Khi không có tường cản phía trước, giữ nguyên va chạm phần thân để đứng trên đất mượt mà
            for _, part in ipairs(character:GetChildren()) do
                if part:IsA("BasePart") then
                    part.CanCollide = (part.Name == "HumanoidRootPart" or part.Name == "UpperTorso" or part.Name == "LowerTorso")
                end
            end
        end
    end)
end

-- Hệ thống lắng nghe duy nhất phím E để kiểm soát vòng lặp Core
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == ALL_IN_ONE_KEY then
        isActivated = not isActivated
        if LocalPlayer.Character then 
            StartAllFeatures(LocalPlayer.Character) 
        end
    end
end)

-- ==========================================
-- TỐC ĐỘ ĐẤT & ẨN TÊN & KHỞI CHẠY LẠI KHI CHẾT
-- ==========================================
local function ApplySpeed(character)
    if not character then return end
    local humanoid = character:WaitForChild("Humanoid", 5)
    if not humanoid then return end
    
    if speedConnection then speedConnection:Disconnect() end
    
    speedConnection = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if not isActivated and humanoid.WalkSpeed ~= WALK_SPEED then
            humanoid.WalkSpeed = WALK_SPEED
        end
    end)
    if not isActivated then humanoid.WalkSpeed = WALK_SPEED end
end

local function HideIdentity(character)
    if not character then return end
    local head = character:WaitForChild("Head", 5)
    if head then
        for _, child in ipairs(head:GetChildren()) do
            if child:IsA("BillboardGui") or child:IsA("SurfaceGui") then child:Destroy() end
        end
    end
    local humanoid = character:WaitForChild("Humanoid", 5)
    if humanoid then
        humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
    end
end

LocalPlayer.CharacterAdded:Connect(function(char)
    isActivated = false
    if mainLoopConnection then mainLoopConnection:Disconnect() mainLoopConnection = nil end
    task.wait(0.5)
    ApplySpeed(char)
    HideIdentity(char)
end)

if LocalPlayer.Character then ApplySpeed(LocalPlayer.Character) HideIdentity(LocalPlayer.Character) end

-- Anti-Ban Bypass Gốc
pcall(function()
    local gmt = getrawmetatable(game)
    if setreadonly and gmt then
        setreadonly(gmt, false)
        local oldNamecall = gmt.__namecall
        gmt.__namecall = newcclosure(function(self, ...)
            if getnamecallmethod() == "FireServer" and tostring(self) == "WalkSpeedReport" then return nil end
            return oldNamecall(self, ...)
        end)
        setreadonly(gmt, true)
    end
end)

-- ==========================================
-- SIÊU TỐI ƯU ĐỒ HỌA CHỐNG VĂNG APP
-- ==========================================
pcall(function()
    if settings and settings().Rendering then settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end
    Lighting.GlobalShadows = false
    Lighting.FogEnd = 9e9
    for _, v in ipairs(Lighting:GetChildren()) do
        if v:IsA("PostEffect") or v:IsA("BlurEffect") or v:IsA("SunRaysEffect") or v:IsA("BloomEffect") then v.Enabled = false end
    end
end)

local blacklisted_classes = {
    ["ParticleEmitter"] = true, ["Smoke"] = true, ["Fire"] = true, 
    ["Sparkles"] = true, ["Trail"] = true, ["Beam"] = true
}

Workspace.DescendantAdded:Connect(function(child)
    task.wait(0.02)
    if not child or not child.Parent then return end
    local class = child.ClassName
    local name = child.Name:lower()
    
    if blacklisted_classes[class] or name:find("hit") or name:find("slash") or name:find("damage") or name:find("expl") then
        child:Destroy()
    elseif child:IsA("BasePart") and (child.Material == Enum.Material.Neon or child.Transparency > 0.2) then
        child.Material = Enum.Material.SmoothPlastic
        child.Transparency = 1
        child.CastShadow = false
    end
end)

local function SafePrint(msg)
    local printRaw = printraw or print
    printRaw(msg)
end
SafePrint("[Xenon Hub]: Da khac phuc triet de loi xuyen mat dat bang Raycast!")
