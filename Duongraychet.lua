--[[
    Roblox Dev Utility Menu
    -----------------------
    Intended for a LocalScript in StarterPlayer > StarterPlayerScripts
    (or another client-run location) in an experience you own/control.

    This build intentionally does not include executor injection, anti-cheat bypass,
    remote-spam, server-authority bypasses, or idle-disconnect evasion.

    Live published use can be gated by the DEV_ATTRIBUTE on the DataModel.
    In Studio, the menu is enabled automatically.
]]

local CONFIG = {
    GUI_NAME = "DevUtilityMenu",
    RUNTIME_NAME = "DevUtilityRuntime",
    STOP_EVENT_NAME = "Stop",
    DEV_ATTRIBUTE = "DevUtilitiesEnabled",
    REQUIRE_STUDIO_OR_ATTRIBUTE = true,

    MENU_TOGGLE_KEY = Enum.KeyCode.RightShift,
    START_OPEN = true,

    WALK_SPEED = 16,
    WALK_SPEED_MIN = 8,
    WALK_SPEED_MAX = 80,
    JUMP_VALUE = 50,
    JUMP_MIN = 20,
    JUMP_MAX = 120,

    FLY_SPEED = 45,
    FLY_SPEED_MIN = 10,
    FLY_SPEED_MAX = 120,

    AIM_FOV_RADIUS = 220,
    AIM_FOV_MIN = 40,
    AIM_FOV_MAX = 500,
    AIM_SMOOTHNESS = 0.18,
    AIM_SMOOTH_MIN = 0.04,
    AIM_SMOOTH_MAX = 0.45,

    AUTO_CART_SPEED = 75,
    AUTO_CART_SPEED_MIN = 20,
    AUTO_CART_SPEED_MAX = 180,
    TRACK_ANCHOR_TAG = "DevTrackAnchor",

    ESP_UPDATE_INTERVAL = 0.35,
    AIM_SCAN_INTERVAL = 0.08,

    CART_FOLDER = "Carts",
    ENEMY_FOLDER = "Enemies",
    DESTINATION_FOLDER = "Destination",
    DESTINATION_PART_NAME = "FinalGate",

    NPC_TAG = "DevEnemy",
    CART_TAG = "DevCart",
    DESTINATION_TAG = "DevDestination",

    CART_ESP_COLOR = Color3.fromRGB(255, 210, 80),
    ENEMY_ESP_COLOR = Color3.fromRGB(255, 90, 90),
    DESTINATION_ESP_COLOR = Color3.fromRGB(100, 210, 255),
    AIM_FOV_COLOR = Color3.fromRGB(120, 200, 255),

    AUTO_DRIVE_TWEEN_TIME = 3.0,
    AUTO_DRIVE_ANCHOR_LERP = 0.16,
    TELEPORT_TWEEN_TIME = 4.0,
}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function clamp(n, low, high)
    return math.clamp(tonumber(n) or low, low, high)
end

local function notify(text, good)
    local gui = playerGui:FindFirstChild(CONFIG.GUI_NAME)
    local holder = gui and gui:FindFirstChild("Notifications")
    if not holder then
        return
    end
    local item = Instance.new("TextLabel")
    item.Size = UDim2.new(1, -16, 0, 30)
    item.BackgroundTransparency = 0.1
    item.BackgroundColor3 = good == false and Color3.fromRGB(110, 50, 55) or Color3.fromRGB(45, 65, 85)
    item.TextColor3 = Color3.fromRGB(240, 245, 250)
    item.Text = tostring(text)
    item.TextSize = 13
    item.Font = Enum.Font.GothamMedium
    item.Parent = holder
    Instance.new("UICorner", item).CornerRadius = UDim.new(0, 8)
    task.delay(2.4, function()
        if item.Parent then
            item:Destroy()
        end
    end)
end

local oldRuntime = playerGui:FindFirstChild(CONFIG.RUNTIME_NAME)
if oldRuntime then
    local oldStop = oldRuntime:FindFirstChild(CONFIG.STOP_EVENT_NAME)
    if oldStop and oldStop:IsA("BindableEvent") then
        oldStop:Fire()
    end
    oldRuntime:Destroy()
end

local runtime = Instance.new("Folder")
runtime.Name = CONFIG.RUNTIME_NAME
runtime.Parent = playerGui

local stopEvent = Instance.new("BindableEvent")
stopEvent.Name = CONFIG.STOP_EVENT_NAME
stopEvent.Parent = runtime

local stopped = false
local connections = {}
local featureConnections = {}
local fixLagConnection = nil
local aimConnection = nil
local originalCharacter = {}
local originalLighting = {}
local originalLag = {}
local originalCart = {}
local noclipRequests = {}
local espObjects = {}
local selectedTarget = nil

local state = {
    MenuOpen = CONFIG.START_OPEN,
    FixLag = false,
    FullBright = false,
    SpeedJump = false,
    Fly = false,
    AimLock = false,
    AutoDrive = false,
    Noclip = false,
    ESP = false,
}

local values = {
    WalkSpeed = CONFIG.WALK_SPEED,
    JumpValue = CONFIG.JUMP_VALUE,
    FlySpeed = CONFIG.FLY_SPEED,
    AimFOV = CONFIG.AIM_FOV_RADIUS,
    AimSmooth = CONFIG.AIM_SMOOTHNESS,
    CartSpeed = CONFIG.AUTO_CART_SPEED,
}

local character = nil
local humanoid = nil
local root = nil
local flyLinear = nil
local flyOrientation = nil
local flyAttachment = nil
local flyUp = false
local flyDown = false
local currentCart = nil
local autoDriveTween = nil

local function addConnection(conn, bucket)
    table.insert(bucket or connections, conn)
    return conn
end

local function disconnectBucket(bucket)
    for i = #bucket, 1, -1 do
        local conn = bucket[i]
        if conn and conn.Disconnect then
            pcall(function() conn:Disconnect() end)
        end
        bucket[i] = nil
    end
end

local function clearCharacterOriginals()
    table.clear(originalCharacter)
end

local function captureCharacter(char)
    character = char
    humanoid = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
    root = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5)
    if humanoid then
        originalCharacter.WalkSpeed = humanoid.WalkSpeed
        originalCharacter.AutoRotate = humanoid.AutoRotate
        if humanoid.UseJumpPower then
            originalCharacter.JumpValue = humanoid.JumpPower
            originalCharacter.JumpMode = "Power"
        else
            originalCharacter.JumpValue = humanoid.JumpHeight
            originalCharacter.JumpMode = "Height"
        end
    end
    clearCharacterOriginals()
    if humanoid then
        originalCharacter.WalkSpeed = humanoid.WalkSpeed
        originalCharacter.AutoRotate = humanoid.AutoRotate
        if humanoid.UseJumpPower then
            originalCharacter.JumpValue = humanoid.JumpPower
            originalCharacter.JumpMode = "Power"
        else
            originalCharacter.JumpValue = humanoid.JumpHeight
            originalCharacter.JumpMode = "Height"
        end
    end
    return char
end

local function getCharacter()
    local char = player.Character
    if char and char.Parent then
        if char ~= character then
            captureCharacter(char)
        end
    end
    return character, humanoid, root
end

local function setJumpValue(value)
    if not humanoid then
        return
    end
    local v = clamp(value, CONFIG.JUMP_MIN, CONFIG.JUMP_MAX)
    if humanoid.UseJumpPower then
        humanoid.JumpPower = v
    else
        humanoid.JumpHeight = v
    end
end

local function applySpeedJump()
    if not state.SpeedJump or not humanoid then
        return
    end
    humanoid.WalkSpeed = clamp(values.WalkSpeed, CONFIG.WALK_SPEED_MIN, CONFIG.WALK_SPEED_MAX)
    setJumpValue(values.JumpValue)
end

local function restoreSpeedJump()
    if not humanoid then
        return
    end
    if originalCharacter.WalkSpeed then
        humanoid.WalkSpeed = originalCharacter.WalkSpeed
    end
    if originalCharacter.JumpMode == "Power" and originalCharacter.JumpValue then
        humanoid.JumpPower = originalCharacter.JumpValue
    elseif originalCharacter.JumpMode == "Height" and originalCharacter.JumpValue then
        humanoid.JumpHeight = originalCharacter.JumpValue
    end
end

local function captureLighting()
    if next(originalLighting) then
        return
    end
    originalLighting.Brightness = Lighting.Brightness
    originalLighting.Ambient = Lighting.Ambient
    originalLighting.OutdoorAmbient = Lighting.OutdoorAmbient
    originalLighting.ExposureCompensation = Lighting.ExposureCompensation
    originalLighting.GlobalShadows = Lighting.GlobalShadows
    originalLighting.EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale
    originalLighting.EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale
end

local function setFullBright(enabled)
    if enabled then
        captureLighting()
        Lighting.Brightness = 3
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
        Lighting.ExposureCompensation = 0.75
        Lighting.GlobalShadows = false
        pcall(function() Lighting.EnvironmentDiffuseScale = 1 end)
        pcall(function() Lighting.EnvironmentSpecularScale = 0 end)
        return
    end
    for prop, value in pairs(originalLighting) do
        pcall(function() Lighting[prop] = value end)
    end
    table.clear(originalLighting)
end

local function isHeavyVisual(inst)
    return inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
        or inst:IsA("Smoke") or inst:IsA("Fire") or inst:IsA("Sparkles")
        or inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight")
end

local function captureLagInstance(inst)
    if originalLag[inst] then
        return
    end
    local data = {}
    if inst:IsA("BasePart") then
        data.Material = inst.Material
        data.CastShadow = inst.CastShadow
    elseif isHeavyVisual(inst) then
        data.Enabled = inst.Enabled
    elseif inst:IsA("PostEffect") then
        data.Enabled = inst.Enabled
    else
        return
    end
    originalLag[inst] = data
end

local function shouldProcessLag(inst)
    return inst:IsA("BasePart") or isHeavyVisual(inst) or inst:IsA("PostEffect")
end

local function applyLagToInstance(inst)
    if not shouldProcessLag(inst) then
        return
    end
    captureLagInstance(inst)
    if inst:IsA("BasePart") then
        inst.Material = Enum.Material.SmoothPlastic
        inst.CastShadow = false
    else
        inst.Enabled = false
    end
end

local function restoreLag()
    for inst, data in pairs(originalLag) do
        if inst and inst.Parent then
            if inst:IsA("BasePart") then
                pcall(function() inst.Material = data.Material end)
                pcall(function() inst.CastShadow = data.CastShadow end)
            else
                pcall(function() inst.Enabled = data.Enabled end)
            end
        end
    end
    table.clear(originalLag)
end

local function setFixLag(enabled)
    if fixLagConnection then
        fixLagConnection:Disconnect()
        fixLagConnection = nil
    end
    if enabled then
        for _, inst in ipairs(workspace:GetDescendants()) do
            applyLagToInstance(inst)
        end
        fixLagConnection = workspace.DescendantAdded:Connect(function(inst)
            if state.FixLag then
                task.defer(applyLagToInstance, inst)
            end
        end)
        return
    end
    restoreLag()
end

local function create(className, props, parent)
    local obj = Instance.new(className)
    for key, value in pairs(props or {}) do
        obj[key] = value
    end
    obj.Parent = parent
    return obj
end

local function round(obj, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 8)
    corner.Parent = obj
    return corner
end

local function stroke(obj, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.Parent = obj
    return s
end

local existingGui = playerGui:FindFirstChild(CONFIG.GUI_NAME)
if existingGui then
    existingGui:Destroy()
end

local gui = create("ScreenGui", {
    Name = CONFIG.GUI_NAME,
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 100,
}, playerGui)

local rootFrame = create("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(365, 470),
    Position = UDim2.new(0, 22, 0.5, -235),
    BackgroundColor3 = Color3.fromRGB(22, 25, 31),
    BorderSizePixel = 0,
    Visible = state.MenuOpen,
}, gui)
round(rootFrame, 12)
stroke(rootFrame, Color3.fromRGB(58, 66, 80), 1)

local header = create("Frame", {
    Size = UDim2.new(1, 0, 0, 46),
    BackgroundColor3 = Color3.fromRGB(29, 33, 41),
    BorderSizePixel = 0,
}, rootFrame)
round(header, 12)

local title = create("TextLabel", {
    Size = UDim2.new(1, -110, 1, 0),
    Position = UDim2.fromOffset(14, 0),
    BackgroundTransparency = 1,
    Text = "DEV UTILITY",
    TextColor3 = Color3.fromRGB(235, 240, 248),
    TextSize = 15,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local subtitle = create("TextLabel", {
    Size = UDim2.new(1, -110, 0, 15),
    Position = UDim2.fromOffset(14, 27),
    BackgroundTransparency = 1,
    Text = "Client developer / QA tools",
    TextColor3 = Color3.fromRGB(140, 150, 168),
    TextSize = 9,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local minimize = create("TextButton", {
    Size = UDim2.fromOffset(32, 30),
    Position = UDim2.new(1, -73, 0, 8),
    BackgroundColor3 = Color3.fromRGB(45, 51, 61),
    BorderSizePixel = 0,
    Text = "—",
    TextColor3 = Color3.fromRGB(220, 225, 232),
    TextSize = 16,
    Font = Enum.Font.GothamBold,
}, header)
round(minimize, 8)

local close = create("TextButton", {
    Size = UDim2.fromOffset(32, 30),
    Position = UDim2.new(1, -37, 0, 8),
    BackgroundColor3 = Color3.fromRGB(75, 45, 50),
    BorderSizePixel = 0,
    Text = "×",
    TextColor3 = Color3.fromRGB(245, 220, 220),
    TextSize = 18,
    Font = Enum.Font.GothamBold,
}, header)
round(close, 8)

local scroll = create("ScrollingFrame", {
    Name = "Content",
    Size = UDim2.new(1, -12, 1, -58),
    Position = UDim2.fromOffset(6, 52),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageTransparency = 0.35,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(),
}, rootFrame)

local contentLayout = create("UIListLayout", {
    Padding = UDim.new(0, 8),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, scroll)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 4),
    PaddingRight = UDim.new(0, 4),
    PaddingTop = UDim.new(0, 2),
    PaddingBottom = UDim.new(0, 10),
}, scroll)

local notifyHolder = create("Frame", {
    Name = "Notifications",
    Size = UDim2.fromOffset(255, 130),
    Position = UDim2.new(1, -265, 0, 16),
    BackgroundTransparency = 1,
}, gui)
create("UIListLayout", {
    Padding = UDim.new(0, 5),
    VerticalAlignment = Enum.VerticalAlignment.Top,
}, notifyHolder)

local miniButton = create("TextButton", {
    Name = "MiniButton",
    Size = UDim2.fromOffset(46, 46),
    Position = UDim2.new(0, 18, 1, -64),
    BackgroundColor3 = Color3.fromRGB(29, 33, 41),
    BorderSizePixel = 0,
    Text = "DEV",
    TextColor3 = Color3.fromRGB(220, 232, 245),
    TextSize = 11,
    Font = Enum.Font.GothamBold,
    Visible = false,
}, gui)
round(miniButton, 23)
stroke(miniButton, Color3.fromRGB(58, 66, 80), 1)

local function showMenu(show)
    state.MenuOpen = show
    rootFrame.Visible = show
    miniButton.Visible = not show
end

local function makeSection(text)
    local label = create("TextLabel", {
        Size = UDim2.new(1, -8, 0, 25),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = Color3.fromRGB(130, 174, 220),
        TextSize = 11,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, scroll)
    return label
end

local function makeToggle(labelText, callback)
    local row = create("Frame", {
        Size = UDim2.new(1, -8, 0, 39),
        BackgroundColor3 = Color3.fromRGB(29, 33, 41),
        BorderSizePixel = 0,
    }, scroll)
    round(row, 8)
    create("TextLabel", {
        Size = UDim2.new(1, -92, 1, 0),
        Position = UDim2.fromOffset(12, 0),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = Color3.fromRGB(220, 225, 234),
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local button = create("TextButton", {
        Size = UDim2.fromOffset(68, 27),
        Position = UDim2.new(1, -77, 0.5, -13),
        BackgroundColor3 = Color3.fromRGB(54, 60, 71),
        BorderSizePixel = 0,
        Text = "OFF",
        TextColor3 = Color3.fromRGB(165, 172, 185),
        TextSize = 10,
        Font = Enum.Font.GothamBold,
    }, row)
    round(button, 8)
    local value = false
    local function render(v)
        value = v
        button.Text = v and "ON" or "OFF"
        button.BackgroundColor3 = v and Color3.fromRGB(55, 105, 82) or Color3.fromRGB(54, 60, 71)
        button.TextColor3 = v and Color3.fromRGB(225, 250, 235) or Color3.fromRGB(165, 172, 185)
    end
    addConnection(button.Activated:Connect(function()
        render(not value)
        callback(value)
    end))
    render(false)
    return render, row
end

local function makeSlider(labelText, minValue, maxValue, getter, setter, decimals)
    local row = create("Frame", {
        Size = UDim2.new(1, -8, 0, 58),
        BackgroundColor3 = Color3.fromRGB(29, 33, 41),
        BorderSizePixel = 0,
    }, scroll)
    round(row, 8)
    create("TextLabel", {
        Size = UDim2.new(0.58, 0, 0, 24),
        Position = UDim2.fromOffset(12, 3),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = Color3.fromRGB(220, 225, 234),
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local valueLabel = create("TextLabel", {
        Size = UDim2.new(0.35, -8, 0, 24),
        Position = UDim2.new(0.65, 0, 0, 3),
        BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(145, 190, 235),
        TextSize = 11,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Right,
        Text = "",
    }, row)
    local bar = create("Frame", {
        Size = UDim2.new(1, -24, 0, 10),
        Position = UDim2.fromOffset(12, 37),
        BackgroundColor3 = Color3.fromRGB(52, 59, 71),
        BorderSizePixel = 0,
    }, row)
    round(bar, 5)
    local fill = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(90, 160, 220),
        BorderSizePixel = 0,
    }, bar)
    round(fill, 5)
    local knob = create("Frame", {
        Size = UDim2.fromOffset(14, 14),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundColor3 = Color3.fromRGB(230, 240, 250),
        BorderSizePixel = 0,
    }, bar)
    round(knob, 7)
    local function formatValue(v)
        if decimals and decimals > 0 then
            return string.format("%." .. decimals .. "f", v)
        end
        return tostring(math.floor(v + 0.5))
    end
    local function updateFromX(x)
        local alpha = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        local v = minValue + (maxValue - minValue) * alpha
        if not decimals or decimals == 0 then
            v = math.floor(v + 0.5)
        end
        setter(v)
        local a = (v - minValue) / (maxValue - minValue)
        fill.Size = UDim2.new(a, 0, 1, 0)
        knob.Position = UDim2.new(a, 0, 0.5, 0)
        valueLabel.Text = formatValue(v)
    end
    local dragging = false
    addConnection(bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateFromX(input.Position.X)
        end
    end))
    addConnection(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromX(input.Position.X)
        end
    end))
    addConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    local function refresh()
        updateFromX(bar.AbsolutePosition.X + bar.AbsoluteSize.X * ((getter() - minValue) / (maxValue - minValue)))
    end
    refresh()
    return refresh, row
end

local function makeNumberBox(labelText, getter, setter, minValue, maxValue)
    local row = create("Frame", {
        Size = UDim2.new(1, -8, 0, 39),
        BackgroundColor3 = Color3.fromRGB(29, 33, 41),
        BorderSizePixel = 0,
    }, scroll)
    round(row, 8)
    create("TextLabel", {
        Size = UDim2.new(1, -110, 1, 0),
        Position = UDim2.fromOffset(12, 0),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = Color3.fromRGB(220, 225, 234),
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local box = create("TextBox", {
        Size = UDim2.fromOffset(88, 27),
        Position = UDim2.new(1, -98, 0.5, -13),
        BackgroundColor3 = Color3.fromRGB(49, 55, 66),
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        TextColor3 = Color3.fromRGB(235, 240, 248),
        PlaceholderColor3 = Color3.fromRGB(130, 138, 150),
        TextSize = 11,
        Font = Enum.Font.GothamMedium,
        Text = tostring(getter()),
    }, row)
    round(box, 7)
    addConnection(box.FocusLost:Connect(function()
        local num = tonumber(box.Text)
        if not num then
            box.Text = tostring(getter())
            notify(labelText .. ": invalid number", false)
            return
        end
        num = clamp(num, minValue, maxValue)
        setter(num)
        box.Text = tostring(num)
    end))
    return box
end

local function setButtonState(renderers, key, enabled)
    local render = renderers[key]
    if render then
        render(enabled)
    end
end

local function findNamedFolder(name)
    if not name or name == "" then
        return nil
    end
    return workspace:FindFirstChild(name)
end

local function pushTarget(list, inst)
    if not inst or not inst.Parent then
        return
    end
    if not table.find(list, inst) then
        table.insert(list, inst)
    end
end

local function collectTargets(searchText)
    local list = {}
    local needle = string.lower(searchText or "")
    local carts = findNamedFolder(CONFIG.CART_FOLDER)
    local enemies = findNamedFolder(CONFIG.ENEMY_FOLDER)
    local destinations = findNamedFolder(CONFIG.DESTINATION_FOLDER)
    for _, folder in ipairs({carts, enemies, destinations}) do
        if folder then
            for _, inst in ipairs(folder:GetChildren()) do
                if string.find(string.lower(inst.Name), needle, 1, true) then
                    pushTarget(list, inst)
                end
            end
        end
    end
    for _, inst in ipairs(CollectionService:GetTagged(CONFIG.CART_TAG)) do
        if string.find(string.lower(inst.Name), needle, 1, true) then
            pushTarget(list, inst)
        end
    end
    for _, inst in ipairs(CollectionService:GetTagged(CONFIG.NPC_TAG)) do
        if string.find(string.lower(inst.Name), needle, 1, true) then
            pushTarget(list, inst)
        end
    end
    return list
end

makeSection("MOVEMENT")
local renderers = {}
renderers.SpeedJump = makeToggle("Speed / High Jump", function(enabled)
    state.SpeedJump = enabled
    if enabled then
        applySpeedJump()
        notify("Speed / Jump enabled")
    else
        restoreSpeedJump()
        notify("Speed / Jump restored")
    end
end)
makeSlider("Walk Speed", CONFIG.WALK_SPEED_MIN, CONFIG.WALK_SPEED_MAX,
    function() return values.WalkSpeed end,
    function(v) values.WalkSpeed = v; applySpeedJump() end, 0)
makeNumberBox("Jump Value", function() return values.JumpValue end,
    function(v) values.JumpValue = v; applySpeedJump() end,
    CONFIG.JUMP_MIN, CONFIG.JUMP_MAX)
makeSection("VISUALS")
renderers.FixLag = makeToggle("Fix Lag / Visual Trim", function(enabled)
    state.FixLag = enabled
    setFixLag(enabled)
    notify(enabled and "Performance mode enabled" or "Performance mode restored")
end)
renderers.FullBright = makeToggle("Full Bright", function(enabled)
    state.FullBright = enabled
    setFullBright(enabled)
    notify(enabled and "Full Bright enabled" or "Lighting restored")
end)

makeSection("FLY")
renderers.Fly = makeToggle("Fly Mode", function(enabled)
    state.Fly = enabled
    if enabled then
        setNoCollideRequester("Fly", true)
        local ok, err = pcall(function()
            getCharacter()
            if not root then error("character root unavailable") end
            if flyLinear then flyLinear:Destroy() end
            if flyOrientation then flyOrientation:Destroy() end
            if flyAttachment then flyAttachment:Destroy() end
            flyAttachment = Instance.new("Attachment")
            flyAttachment.Name = "DevFlyAttachment"
            flyAttachment.Parent = root
            flyLinear = Instance.new("LinearVelocity")
            flyLinear.Name = "DevFlyVelocity"
            flyLinear.Attachment0 = flyAttachment
            flyLinear.RelativeTo = Enum.ActuatorRelativeTo.World
            flyLinear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
            flyLinear.VectorVelocity = Vector3.zero
            flyLinear.ForceLimitsEnabled = false
            flyLinear.Parent = root
            flyOrientation = Instance.new("AlignOrientation")
            flyOrientation.Name = "DevFlyOrientation"
            flyOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
            flyOrientation.Attachment0 = flyAttachment
            flyOrientation.RigidityEnabled = false
            flyOrientation.Responsiveness = 25
            flyOrientation.MaxTorque = math.huge
            flyOrientation.Parent = root
            if humanoid then humanoid.AutoRotate = false end
        end)
        if not ok then
            state.Fly = false
            setNoCollideRequester("Fly", false)
            notify("Fly setup failed: " .. tostring(err), false)
        else
            notify("Fly enabled")
        end
    else
        stopFly()
        notify("Fly disabled")
    end
end)
makeSlider("Fly Speed", CONFIG.FLY_SPEED_MIN, CONFIG.FLY_SPEED_MAX,
    function() return values.FlySpeed end,
    function(v) values.FlySpeed = v end, 0)

local flyButtonHolder = create("Frame", {
    Name = "FlyButtons",
    Size = UDim2.fromOffset(120, 128),
    Position = UDim2.new(1, -134, 1, -150),
    BackgroundTransparency = 1,
    Visible = false,
}, gui)

local upButton = create("TextButton", {
    Size = UDim2.fromOffset(54, 54),
    Position = UDim2.fromOffset(60, 0),
    BackgroundColor3 = Color3.fromRGB(35, 44, 54),
    BorderSizePixel = 0,
    Text = "▲",
    TextColor3 = Color3.fromRGB(230, 240, 248),
    TextSize = 20,
    Font = Enum.Font.GothamBold,
}, flyButtonHolder)
round(upButton, 27)
stroke(upButton, Color3.fromRGB(75, 95, 120), 1)

local downButton = create("TextButton", {
    Size = UDim2.fromOffset(54, 54),
    Position = UDim2.fromOffset(60, 62),
    BackgroundColor3 = Color3.fromRGB(35, 44, 54),
    BorderSizePixel = 0,
    Text = "▼",
    TextColor3 = Color3.fromRGB(230, 240, 248),
    TextSize = 20,
    Font = Enum.Font.GothamBold,
}, flyButtonHolder)
round(downButton, 27)
stroke(downButton, Color3.fromRGB(75, 95, 120), 1)

local function setHeld(button, setter)
    addConnection(button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            setter(true)
        end
    end))
    addConnection(button.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            setter(false)
        end
    end))
end
setHeld(upButton, function(v) flyUp = v end)
setHeld(downButton, function(v) flyDown = v end)

makeSection("AIM TEST")
renderers.AimLock = makeToggle("NPC Aim Assist", function(enabled)
    state.AimLock = enabled
    startAimLoop(enabled)
    updateFovVisibility()
    notify(enabled and "Aim assist enabled" or "Aim assist disabled")
end)
makeSlider("Aim FOV Radius", CONFIG.AIM_FOV_MIN, CONFIG.AIM_FOV_MAX,
    function() return values.AimFOV end,
    function(v) values.AimFOV = v; updateFovCircle() end, 0)
makeSlider("Aim Smoothness", CONFIG.AIM_SMOOTH_MIN, CONFIG.AIM_SMOOTH_MAX,
    function() return values.AimSmooth end,
    function(v) values.AimSmooth = v end, 2)

makeSection("CART TEST")
renderers.AutoDrive = makeToggle("Auto Drive Cart", function(enabled)
    state.AutoDrive = enabled
    if enabled then
        setNoCollideRequester("AutoDrive", true)
        notify("Auto Drive enabled")
    else
        stopAutoDrive()
        notify("Auto Drive disabled")
    end
end)
makeSlider("Cart Speed", CONFIG.AUTO_CART_SPEED_MIN, CONFIG.AUTO_CART_SPEED_MAX,
    function() return values.CartSpeed end,
    function(v) values.CartSpeed = v end, 0)

local tpButton = create("TextButton", {
    Size = UDim2.new(1, -8, 0, 39),
    BackgroundColor3 = Color3.fromRGB(38, 65, 84),
    BorderSizePixel = 0,
    Text = "Teleport to Destination",
    TextColor3 = Color3.fromRGB(225, 240, 250),
    TextSize = 12,
    Font = Enum.Font.GothamBold,
}, scroll)
round(tpButton, 8)

makeSection("COLLISION")
renderers.Noclip = makeToggle("Noclip", function(enabled)
    state.Noclip = enabled
    setNoCollideRequester("Noclip", enabled)
    notify(enabled and "Noclip enabled" or "Collision restored")
end)

makeSection("ESP")
renderers.ESP = makeToggle("Target ESP", function(enabled)
    state.ESP = enabled
    if not enabled then
        clearEsp()
    end
    notify(enabled and "ESP enabled" or "ESP cleared")
end)

makeSection("TARGET SELECT")
local searchBox = create("TextBox", {
    Size = UDim2.new(1, -8, 0, 36),
    BackgroundColor3 = Color3.fromRGB(29, 33, 41),
    BorderSizePixel = 0,
    PlaceholderText = "Search carts / enemies / destinations...",
    PlaceholderColor3 = Color3.fromRGB(125, 134, 148),
    TextColor3 = Color3.fromRGB(230, 236, 244),
    TextSize = 11,
    Font = Enum.Font.Gotham,
    ClearTextOnFocus = false,
    Text = "",
}, scroll)
round(searchBox, 8)

local targetList = create("Frame", {
    Size = UDim2.new(1, -8, 0, 120),
    BackgroundColor3 = Color3.fromRGB(27, 31, 38),
    BorderSizePixel = 0,
}, scroll)
round(targetList, 8)
create("UIListLayout", {
    Padding = UDim.new(0, 3),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, targetList)

local selectedLabel = create("TextLabel", {
    Size = UDim2.new(1, -8, 0, 29),
    BackgroundTransparency = 1,
    Text = "Selected: none",
    TextColor3 = Color3.fromRGB(145, 190, 235),
    TextSize = 10,
    Font = Enum.Font.GothamMedium,
    TextXAlignment = Enum.TextXAlignment.Left,
}, scroll)

local function clearTargetButtons()
    for _, child in ipairs(targetList:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
end

local function refreshTargetList()
    clearTargetButtons()
    local targets = collectTargets(searchBox.Text)
    for i = 1, math.min(#targets, 8) do
        local target = targets[i]
        local button = create("TextButton", {
            Size = UDim2.new(1, -8, 0, 27),
            BackgroundColor3 = Color3.fromRGB(45, 51, 61),
            BorderSizePixel = 0,
            Text = target.Name,
            TextColor3 = Color3.fromRGB(220, 226, 235),
            TextSize = 10,
            Font = Enum.Font.GothamMedium,
        }, targetList)
        round(button, 6)
        addConnection(button.Activated:Connect(function()
            selectedTarget = target
            selectedLabel.Text = "Selected: " .. target.Name
            notify("Selected " .. target.Name)
        end))
    end
    targetList.Visible = #targets > 0
end

addConnection(searchBox:GetPropertyChangedSignal("Text"):Connect(refreshTargetList))

local fovCircle = create("Frame", {
    Name = "FOVCircle",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(values.AimFOV * 2, values.AimFOV * 2),
    BackgroundTransparency = 1,
    Visible = false,
}, gui)
round(fovCircle, 999)
stroke(fovCircle, CONFIG.AIM_FOV_COLOR, 2, 0.15)

local function updateFovCircle()
    if fovCircle then
        fovCircle.Size = UDim2.fromOffset(values.AimFOV * 2, values.AimFOV * 2)
    end
end

function updateFovVisibility()
    if fovCircle then
        fovCircle.Visible = state.AimLock and not stopped
    end
end

local function ensureTargetModel(inst)
    if not inst or not inst.Parent then
        return nil
    end
    if inst:IsA("Model") then
        return inst
    end
    return inst:FindFirstAncestorOfClass("Model")
end

local function getEnemyCandidates()
    local results = {}
    local seen = {}
    local folders = {findNamedFolder(CONFIG.ENEMY_FOLDER)}
    for _, folder in ipairs(folders) do
        if folder then
            for _, inst in ipairs(folder:GetDescendants()) do
                local model = ensureTargetModel(inst)
                if model and not seen[model] then
                    seen[model] = true
                    table.insert(results, model)
                end
            end
        end
    end
    for _, inst in ipairs(CollectionService:GetTagged(CONFIG.NPC_TAG)) do
        local model = ensureTargetModel(inst)
        if model and not seen[model] then
            seen[model] = true
            table.insert(results, model)
        end
    end
    return results
end

local function getValidHead(model)
    local h = model and model:FindFirstChildOfClass("Humanoid")
    local head = model and model:FindFirstChild("Head")
    if h and h.Health > 0 and head and head:IsA("BasePart") then
        return head
    end
    return nil
end

local function nearestAimHead()
    local camera = workspace.CurrentCamera
    if not camera then
        return nil
    end
    local center = camera.ViewportSize * 0.5
    local bestHead = nil
    local bestDist = values.AimFOV
    for _, model in ipairs(getEnemyCandidates()) do
        local head = getValidHead(model)
        if head then
            local point, onScreen = camera:WorldToViewportPoint(head.Position)
            if onScreen and point.Z > 0 then
                local dist = (Vector2.new(point.X, point.Y) - center).Magnitude
                if dist <= bestDist then
                    bestDist = dist
                    bestHead = head
                end
            end
        end
    end
    return bestHead
end

function startAimLoop(enabled)
    if aimConnection then
        aimConnection:Disconnect()
        aimConnection = nil
    end
    if not enabled then
        return
    end
    aimConnection = RunService.RenderStepped:Connect(function(dt)
        if stopped or not state.AimLock then
            return
        end
        local camera = workspace.CurrentCamera
        local head = nearestAimHead()
        if camera and head and head.Parent then
            local target = CFrame.lookAt(camera.CFrame.Position, head.Position)
            local alpha = math.clamp(values.AimSmooth * dt * 60, 0, 1)
            camera.CFrame = camera.CFrame:Lerp(target, alpha)
        end
    end)
end

local function refreshNoclipForCharacter()
    if not character or not character.Parent then
        return
    end
    local requests = next(noclipRequests) ~= nil
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            if part:GetAttribute("DevNoclipOriginal") == nil then
                part:SetAttribute("DevNoclipOriginal", part.CanCollide)
            end
            if requests then
                part.CanCollide = false
            else
                local original = part:GetAttribute("DevNoclipOriginal")
                if original ~= nil then
                    part.CanCollide = original
                    part:SetAttribute("DevNoclipOriginal", nil)
                end
            end
        end
    end
end

function setNoCollideRequester(name, enabled)
    noclipRequests[name] = enabled and true or nil
    refreshNoclipForCharacter()
end

function stopFly()
    state.Fly = false
    flyUp = false
    flyDown = false
    flyButtonHolder.Visible = false
    setNoCollideRequester("Fly", false)
    if flyLinear then flyLinear:Destroy(); flyLinear = nil end
    if flyOrientation then flyOrientation:Destroy(); flyOrientation = nil end
    if flyAttachment then flyAttachment:Destroy(); flyAttachment = nil end
    if humanoid and originalCharacter.AutoRotate ~= nil then
        humanoid.AutoRotate = originalCharacter.AutoRotate
    end
end

local function updateFly()
    if not state.Fly or not root then
        return
    end
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end
    local planar = humanoid and humanoid.MoveDirection or Vector3.zero
    local vertical = (flyUp and 1 or 0) - (flyDown and 1 or 0)
    local velocity = planar * values.FlySpeed + Vector3.new(0, vertical * values.FlySpeed, 0)
    if flyLinear then
        flyLinear.VectorVelocity = velocity
    end
    if flyOrientation then
        local look = camera.CFrame.LookVector
        flyOrientation.CFrame = CFrame.lookAt(root.Position, root.Position + look)
    end
end

local function findOccupiedSeat()
    getCharacter()
    if humanoid and humanoid.SeatPart and humanoid.SeatPart:IsA("VehicleSeat") then
        return humanoid.SeatPart
    end
    return nil
end

local function nearestAnchor(position)
    local best, bestDist
    for _, inst in ipairs(CollectionService:GetTagged(CONFIG.TRACK_ANCHOR_TAG)) do
        if inst:IsA("BasePart") then
            local dist = (inst.Position - position).Magnitude
            if not bestDist or dist < bestDist then
                best = inst
                bestDist = dist
            end
        end
    end
    return best
end

local function captureCartSeat(seat)
    if originalCart[seat] then
        return
    end
    originalCart[seat] = {
        MaxSpeed = seat.MaxSpeed,
        AssemblyLinearVelocity = seat.AssemblyLinearVelocity,
    }
end

local function restoreCart()
    for seat, data in pairs(originalCart) do
        if seat and seat.Parent then
            pcall(function() seat.MaxSpeed = data.MaxSpeed end)
            pcall(function() seat.AssemblyLinearVelocity = data.AssemblyLinearVelocity end)
        end
    end
    table.clear(originalCart)
end

local function stopAutoDrive()
    state.AutoDrive = false
    setNoCollideRequester("AutoDrive", false)
    if autoDriveTween then
        autoDriveTween:Cancel()
        autoDriveTween = nil
    end
    restoreCart()
    currentCart = nil
end

local function updateAutoDrive()
    if not state.AutoDrive then
        return
    end
    local seat = findOccupiedSeat()
    if not seat then
        return
    end
    currentCart = seat
    captureCartSeat(seat)
    pcall(function() seat.MaxSpeed = values.CartSpeed end)
    local anchor = nearestAnchor(seat.Position)
    if anchor then
        local desired = CFrame.lookAt(anchor.Position, anchor.Position + anchor.CFrame.LookVector)
        seat.CFrame = seat.CFrame:Lerp(desired, CONFIG.AUTO_DRIVE_ANCHOR_LERP)
    end
    seat.AssemblyLinearVelocity = seat.CFrame.LookVector * values.CartSpeed
end

local function findDestination()
    local folder = findNamedFolder(CONFIG.DESTINATION_FOLDER)
    if folder then
        local part = folder:FindFirstChild(CONFIG.DESTINATION_PART_NAME, true)
        if part and part:IsA("BasePart") then
            return part
        end
        local any = folder:FindFirstChildWhichIsA("BasePart", true)
        if any then return any end
    end
    local tagged = CollectionService:GetTagged(CONFIG.DESTINATION_TAG)
    for _, inst in ipairs(tagged) do
        if inst:IsA("BasePart") then
            return inst
        end
        local p = inst:FindFirstChildWhichIsA("BasePart", true)
        if p then return p end
    end
    return nil
end

local function teleportToDestination()
    getCharacter()
    if not root then
        notify("No character root available", false)
        return
    end
    local destination = findDestination()
    if not destination then
        notify("No destination part found", false)
        return
    end
    if autoDriveTween then autoDriveTween:Cancel() end
    local goal = destination.CFrame + Vector3.new(0, 4, 0)
    autoDriveTween = TweenService:Create(root,
        TweenInfo.new(CONFIG.TELEPORT_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {CFrame = goal})
    autoDriveTween:Play()
    notify("Teleport tween started")
end

local function removeEspObject(target)
    local data = espObjects[target]
    if not data then
        return
    end
    for _, obj in ipairs(data) do
        if obj and obj.Parent then
            obj:Destroy()
        end
    end
    espObjects[target] = nil
end

function clearEsp()
    for target in pairs(espObjects) do
        removeEspObject(target)
    end
end

local function targetRoot(model)
    if model:IsA("BasePart") then
        return model
    end
    return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function makeBillboard(model, labelText, color)
    local rootPart = targetRoot(model)
    if not rootPart then
        return nil
    end
    local guiObj = create("BillboardGui", {
        Name = "DevESPLabel",
        Adornee = rootPart,
        Size = UDim2.fromOffset(155, 38),
        StudsOffset = Vector3.new(0, 3, 0),
        AlwaysOnTop = true,
        MaxDistance = 10000,
    }, rootPart)
    local label = create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = color,
        TextStrokeTransparency = 0.5,
        TextSize = 11,
        Font = Enum.Font.GothamBold,
    }, guiObj)
    return guiObj
end

local function applyEsp(target, color, label)
    if espObjects[target] or not target.Parent then
        return
    end
    local objects = {}
    local highlight = create("Highlight", {
        Name = "DevESPHighlight",
        Adornee = target,
        FillColor = color,
        FillTransparency = 0.72,
        OutlineColor = color,
        OutlineTransparency = 0.15,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
    }, target)
    table.insert(objects, highlight)
    local bill = makeBillboard(target, label, color)
    if bill then table.insert(objects, bill) end
    espObjects[target] = objects
end

local function findEspTargets()
    local carts = findNamedFolder(CONFIG.CART_FOLDER)
    local enemies = findNamedFolder(CONFIG.ENEMY_FOLDER)
    local destination = findNamedFolder(CONFIG.DESTINATION_FOLDER)
    if carts then
        for _, inst in ipairs(carts:GetChildren()) do
            if inst:IsA("Model") then applyEsp(inst, CONFIG.CART_ESP_COLOR, "CART") end
        end
    end
    if enemies then
        for _, inst in ipairs(enemies:GetChildren()) do
            if inst:IsA("Model") then applyEsp(inst, CONFIG.ENEMY_ESP_COLOR, "ENEMY") end
        end
    end
    if destination then
        for _, inst in ipairs(destination:GetChildren()) do
            if inst:IsA("Model") or inst:IsA("BasePart") then
                applyEsp(inst, CONFIG.DESTINATION_ESP_COLOR, "DESTINATION")
            end
        end
    end
    for _, inst in ipairs(CollectionService:GetTagged(CONFIG.CART_TAG)) do
        applyEsp(ensureTargetModel(inst) or inst, CONFIG.CART_ESP_COLOR, "CART")
    end
    for _, inst in ipairs(CollectionService:GetTagged(CONFIG.NPC_TAG)) do
        applyEsp(ensureTargetModel(inst) or inst, CONFIG.ENEMY_ESP_COLOR, "ENEMY")
    end
    for _, inst in ipairs(CollectionService:GetTagged(CONFIG.DESTINATION_TAG)) do
        applyEsp(ensureTargetModel(inst) or inst, CONFIG.DESTINATION_ESP_COLOR, "DESTINATION")
    end
end

local lastEspUpdate = 0
local function updateEsp(dt)
    if not state.ESP then
        return
    end
    lastEspUpdate += dt
    if lastEspUpdate < CONFIG.ESP_UPDATE_INTERVAL then
        return
    end
    lastEspUpdate = 0
    findEspTargets()
    for target in pairs(espObjects) do
        if not target or not target.Parent then
            removeEspObject(target)
        end
    end
end

local lastAim = 0
local function updateFeatures(dt)
    if stopped then
        return
    end
    getCharacter()
    if state.SpeedJump then applySpeedJump() end
    if state.Noclip or state.Fly or state.AutoDrive then refreshNoclipForCharacter() end
    if state.Fly then updateFly() end
    if state.AutoDrive then updateAutoDrive() end
    updateEsp(dt)
    if state.AimLock then
        lastAim += dt
        if lastAim >= CONFIG.AIM_SCAN_INTERVAL then
            lastAim = 0
        end
    end
end

local function beginDrag()
    local dragging = false
    local dragStart = nil
    local startPos = nil
    addConnection(header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = rootFrame.Position
        end
    end))
    addConnection(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - dragStart
        rootFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end))
    addConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

local function cleanup()
    if stopped then
        return
    end
    stopped = true
    state.FixLag = false
    state.FullBright = false
    state.SpeedJump = false
    state.Fly = false
    state.AimLock = false
    state.AutoDrive = false
    state.Noclip = false
    state.ESP = false
    disconnectBucket(featureConnections)
    if fixLagConnection then fixLagConnection:Disconnect(); fixLagConnection = nil end
    if aimConnection then aimConnection:Disconnect(); aimConnection = nil end
    disconnectBucket(connections)
    stopFly()
    stopAutoDrive()
    setFullBright(false)
    restoreLag()
    clearEsp()
    noclipRequests = {}
    refreshNoclipForCharacter()
    if gui and gui.Parent then
        gui:Destroy()
    end
end

stopEvent.Event:Connect(cleanup)

addConnection(player.CharacterAdded:Connect(function(char)
    if stopped then return end
    task.defer(function()
        captureCharacter(char)
        if state.SpeedJump then applySpeedJump() end
        if state.Noclip or state.Fly or state.AutoDrive then refreshNoclipForCharacter() end
        if state.Fly then
            task.delay(0.2, function()
                if state.Fly and not stopped then
                    renderers.Fly(true)
                end
            end)
        end
    end)
end))

addConnection(minimize.Activated:Connect(function()
    showMenu(false)
end))

addConnection(close.Activated:Connect(function()
    cleanup()
end))

addConnection(miniButton.Activated:Connect(function()
    showMenu(true)
end))

addConnection(UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == CONFIG.MENU_TOGGLE_KEY then
        showMenu(not state.MenuOpen)
    end
end))

addConnection(tpButton.Activated:Connect(teleportToDestination))
beginDrag()

local function bootGate()
    if not CONFIG.REQUIRE_STUDIO_OR_ATTRIBUTE then
        return true
    end
    if RunService:IsStudio() then
        return true
    end
    return game:GetAttribute(CONFIG.DEV_ATTRIBUTE) == true
end

if not bootGate() then
    notify("Developer utility disabled: enable " .. CONFIG.DEV_ATTRIBUTE .. " in your game", false)
    task.delay(0.8, cleanup)
    return
end

captureCharacter(player.Character or player.CharacterAdded:Wait())
refreshTargetList()
updateFovCircle()
updateFovVisibility()

addConnection(RunService.RenderStepped:Connect(function(dt)
    if stopped then return end
    updateFeatures(dt)
end))

showMenu(CONFIG.START_OPEN)
notify("Dev Utility loaded")
