--!strict

--[[
    Client Utility Menu
    Intended placement:
        StarterPlayer > StarterPlayerScripts

    Client-only:
        - UI
        - local graphics changes
        - local lighting changes
        - local movement settings
        - camera aim assist
        - local fly controller
        - local cart speed presentation
        - local track anchor
        - local tween-based teleport
        - ESP

    Intentionally NOT included:
        - anti-cheat concealment
        - anti-kick bypass
        - Anti-AFK bypass
        - exploit/executor APIs
        - RemoteEvent/RemoteFunction creation
        - server security circumvention

    IMPORTANT:
        Server-authoritative movement, physics, damage, teleport validation,
        or anti-cheat systems may overwrite/reject client changes.
]]

----------------------------------------------------------------
-- CONFIGURATION
----------------------------------------------------------------

local Config = {

    GuiName = "CartRideClientUtility",

    MenuToggleKey = Enum.KeyCode.RightShift,

    WalkSpeed = {
        Min = 8,
        Max = 40,
        Default = 16,
    },

    Jump = {
        Min = 25,
        Max = 100,
        Default = 50,
    },

    FlySpeed = {
        Min = 10,
        Max = 120,
        Default = 60,
    },

    Aim = {
        FOVMin = 40,
        FOVMax = 500,
        FOVDefault = 220,

        SmoothMin = 1,
        SmoothMax = 20,
        SmoothDefault = 10,

        CircleColor = Color3.fromRGB(70, 190, 255),
        CircleTransparency = 0.15,
        CircleThickness = 2,
    },

    Cart = {
        MaxSpeedIncrease = 20,
        MaxSpeedCap = 100,
    },

    Humanization = {
        -- Kept as configuration metadata for the project.
        -- It is intentionally NOT used to evade anti-cheat detection.
        PositionJitterStrength = 0,
        UiBuildDelay = 0.1,
    },

    Folders = {
        Tracks = "Tracks",
        Rails = "Rails",
        Enemies = "Enemies",
        Carts = "Carts",
        Destination = "DestinationGates",
        Map = "Map",
    },

    ESP = {
        CartColor = Color3.fromRGB(80, 220, 120),
        EnemyColor = Color3.fromRGB(255, 90, 90),
        DestinationColor = Color3.fromRGB(255, 210, 70),

        HighlightTransparency = 0.55,
        UpdateInterval = 0.5,
    },

    Fly = {
        MaxForce = 1000000,
        BodyVelocityP = 10000,
        BodyGyroP = 10000,
        BodyGyroD = 500,
    },

    TrackAnchor = {
        MaxForce = 50000,
        Responsiveness = 8,
        RefreshInterval = 0.25,
    },

    Teleport = {
        Duration = 1.25,
        Offset = Vector3.new(0, 3, 0),
    },

    UI = {
        Width = 350,
        Height = 560,
        Background = Color3.fromRGB(20, 24, 32),
        Card = Color3.fromRGB(29, 34, 44),
        Accent = Color3.fromRGB(60, 170, 255),
        Text = Color3.fromRGB(240, 243, 248),
        MutedText = Color3.fromRGB(165, 172, 186),
        Border = Color3.fromRGB(55, 63, 78),
        ToggleOff = Color3.fromRGB(65, 70, 82),
        ToggleOn = Color3.fromRGB(55, 175, 105),
    },
}

----------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- DUPLICATE PREVENTION
----------------------------------------------------------------

local existingGui = PlayerGui:FindFirstChild(Config.GuiName)

if existingGui then
    existingGui:Destroy()
end

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------

local featureState = {
    FixLag = false,
    FullBright = false,
    Movement = false,
    Fly = false,
    Aim = false,
    AutoFastCart = false,
    TrackAnchor = false,
    Noclip = false,
    CartESP = false,
    EnemyESP = false,
    DestinationESP = false,
}

local settings = {
    WalkSpeed = Config.WalkSpeed.Default,
    Jump = Config.Jump.Default,
    FlySpeed = Config.FlySpeed.Default,
    AimFOV = Config.Aim.FOVDefault,
    AimSmoothness = Config.Aim.SmoothDefault,
}

local characterConnections: {RBXScriptConnection} = {}
local featureConnections: {[string]: {RBXScriptConnection}} = {}

local fullBrightOriginal: {[string]: any} = {}
local lagOriginal: {[Instance]: {[string]: any}} = {}

local movementOriginal: {
    WalkSpeed: number?,
    UseJumpPower: boolean?,
    JumpPower: number?,
    JumpHeight: number?,
} = {}

local noclipRequests: {[string]: boolean} = {}
local noclipOriginal: {[BasePart]: boolean} = {}
local noclipConnection: RBXScriptConnection? = nil

local flyVelocity: BodyVelocity? = nil
local flyGyro: BodyGyro? = nil
local flyRenderConnection: RBXScriptConnection? = nil
local flyVertical = 0
local flyButtons: {Instance} = {}
local flyButtonConnections: {RBXScriptConnection} = {}

local aimRenderName = "CartRideAimAssist"
local aimThread: thread? = nil
local aimTargets: {Model} = {}
local currentAimHead: BasePart? = nil

local selectedCategory = "Carts"
local selectedTarget: Instance? = nil

local espObjects: {[Instance]: {Highlight: Highlight, Billboard: BillboardGui}} = {}
local espThread: thread? = nil

local cartSpeedOriginal: {[Instance]: number} = {}
local activeCart: Model? = nil

local trackAnchorAttachment0: Attachment? = nil
local trackAnchorAttachment1: Attachment? = nil
local trackAnchorAlign: AlignPosition? = nil
local trackAnchorThread: thread? = nil

local activeTeleportTween: Tween? = nil

----------------------------------------------------------------
-- UI REFERENCES
----------------------------------------------------------------

local screenGui: ScreenGui
local mainFrame: Frame
local contentFrame: ScrollingFrame
local minimizeButton: TextButton
local restoreButton: TextButton
local statusLabel: TextLabel
local systemStatusLabel: TextLabel
local selectionLabel: TextLabel
local dropdownFrame: Frame
local dropdownSearch: TextBox
local dropdownList: ScrollingFrame

local connections: {RBXScriptConnection} = {}

----------------------------------------------------------------
-- UTILITIES
----------------------------------------------------------------

local function addConnection(connection: RBXScriptConnection)
    table.insert(connections, connection)
end

local function addFeatureConnection(
    featureName: string,
    connection: RBXScriptConnection
)
    featureConnections[featureName] = featureConnections[featureName] or {}
    table.insert(featureConnections[featureName], connection)
end

local function disconnectFeatureConnections(featureName: string)
    local list = featureConnections[featureName]

    if not list then
        return
    end

    for _, connection in ipairs(list) do
        connection:Disconnect()
    end

    featureConnections[featureName] = {}
end

local function reportError(context: string, err: any)
    warn(("[CartRideUtility] %s: %s"):format(context, tostring(err)))

    if statusLabel then
        statusLabel.Text = "Error: " .. context
    end
end

local function tryRun(context: string, callback: () -> ())
    local ok, err = xpcall(callback, debug.traceback)

    if not ok then
        reportError(context, err)
    end
end

local notifyToken = 0

local function notify(message: string, isError: boolean?)
    notifyToken += 1

    statusLabel.Text = message
    statusLabel.TextColor3 = if isError
        then Color3.fromRGB(255, 110, 110)
        else Config.UI.MutedText

    local token = notifyToken

    task.delay(2.2, function()
        if token == notifyToken and statusLabel then
            statusLabel.Text = "Ready."
            statusLabel.TextColor3 = Config.UI.MutedText
        end
    end)
end

local function clampNumber(
    value: number,
    minimum: number,
    maximum: number
): number
    return math.clamp(value, minimum, maximum)
end

local function disconnectList(list: {RBXScriptConnection})
    for index, connection in ipairs(list) do
        connection:Disconnect()
        list[index] = nil
    end
end

local function getCharacter(): Model?
    local character = LocalPlayer.Character

    if not character or not character.Parent then
        return nil
    end

    return character
end

local function getHumanoid(character: Model?): Humanoid?
    if not character then
        return nil
    end

    return character:FindFirstChildOfClass("Humanoid")
end

local function getRoot(character: Model?): BasePart?
    if not character then
        return nil
    end

    local root = character:FindFirstChild("HumanoidRootPart")

    if root and root:IsA("BasePart") then
        return root
    end

    return nil
end

local function getFolder(name: string): Instance?
    local folder = workspace:FindFirstChild(name)

    if folder then
        return folder
    end

    return nil
end

local function getModelRoot(target: Instance): BasePart?
    if target:IsA("BasePart") then
        return target
    end

    if target:IsA("Model") then
        if target.PrimaryPart then
            return target.PrimaryPart
        end

        local root = target:FindFirstChild("HumanoidRootPart")

        if root and root:IsA("BasePart") then
            return root
        end

        return target:FindFirstChildWhichIsA("BasePart", true)
    end

    return target:FindFirstChildWhichIsA("BasePart", true)
end

----------------------------------------------------------------
-- UI CREATION
----------------------------------------------------------------

local function createCorner(parent: Instance, radius: number)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
end

local function createStroke(parent: Instance)
    local stroke = Instance.new("UIStroke")
    stroke.Color = Config.UI.Border
    stroke.Thickness = 1
    stroke.Transparency = 0
    stroke.Parent = parent
end

local function createTextButton(
    parent: Instance,
    text: string,
    size: UDim2
): TextButton
    local button = Instance.new("TextButton")
    button.Size = size
    button.BackgroundColor3 = Config.UI.Card
    button.TextColor3 = Config.UI.Text
    button.Font = Enum.Font.GothamMedium
    button.TextSize = 13
    button.Text = text
    button.AutoButtonColor = true
    button.Parent = parent

    createCorner(button, 8)

    return button
end

local function buildBaseGui()
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = Config.GuiName
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = PlayerGui

    mainFrame = Instance.new("Frame")
    mainFrame.Name = "Main"
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mainFrame.Position = UDim2.fromScale(0.5, 0.5)
    mainFrame.Size = UDim2.fromOffset(Config.UI.Width, Config.UI.Height)
    mainFrame.BackgroundColor3 = Config.UI.Background
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui

    local constraint = Instance.new("UISizeConstraint")
    constraint.MinSize = Vector2.new(300, 430)
    constraint.MaxSize = Vector2.new(390, 650)
    constraint.Parent = mainFrame

    createCorner(mainFrame, 12)
    createStroke(mainFrame)

    task.wait(Config.Humanization.UiBuildDelay)
end

local function buildHeader(): Frame
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 46)
    header.BackgroundTransparency = 1
    header.Parent = mainFrame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -110, 1, 0)
    title.Position = UDim2.fromOffset(14, 0)
    title.BackgroundTransparency = 1
    title.Text = "Cart Ride Utility"
    title.TextColor3 = Config.UI.Text
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    minimizeButton = createTextButton(
        header,
        "—",
        UDim2.fromOffset(34, 30)
    )

    minimizeButton.Position = UDim2.new(1, -84, 0, 8)

    local closeButton = createTextButton(
        header,
        "×",
        UDim2.fromOffset(34, 30)
    )

    closeButton.Position = UDim2.new(1, -44, 0, 8)

    addConnection(minimizeButton.Activated:Connect(function()
        contentFrame.Visible = not contentFrame.Visible
        dropdownFrame.Visible = false
        minimizeButton.Text = if contentFrame.Visible then "—" else "+"
    end))

    addConnection(closeButton.Activated:Connect(function()
        mainFrame.Visible = false
        restoreButton.Visible = true
    end))

    return header
end

local function createSectionTitle(
    parent: Instance,
    text: string
): TextLabel
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 26)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Config.UI.Accent
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent

    return label
end

local function createRow(parent: Instance): Frame
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 42)
    row.BackgroundColor3 = Config.UI.Card
    row.BorderSizePixel = 0
    row.Parent = parent

    createCorner(row, 8)

    return row
end

local function createToggle(
    parent: Instance,
    labelText: string,
    initial: boolean,
    callback: (boolean) -> ()
): TextButton
    local row = createRow(parent)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -78, 1, 0)
    label.Position = UDim2.fromOffset(12, 0)
    label.BackgroundTransparency = 1
    label.Text = labelText
    label.TextColor3 = Config.UI.Text
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local button = createTextButton(
        row,
        "",
        UDim2.fromOffset(54, 27)
    )

    button.Position = UDim2.new(1, -64, 0.5, -13)

    local enabled = initial

    local function refresh()
        button.Text = if enabled then "ON" else "OFF"
        button.BackgroundColor3 = if enabled
            then Config.UI.ToggleOn
            else Config.UI.ToggleOff
    end

    refresh()

    addConnection(button.Activated:Connect(function()
        enabled = not enabled
        refresh()

        tryRun(labelText, function()
            callback(enabled)
        end)
    end))

    return button
end

local function createSlider(
    parent: Instance,
    labelText: string,
    minimum: number,
    maximum: number,
    value: number,
    formatter: (number) -> string,
    callback: (number) -> ()
)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 64)
    row.BackgroundColor3 = Config.UI.Card
    row.BorderSizePixel = 0
    row.Parent = parent

    createCorner(row, 8)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.5, 0, 0, 24)
    label.Position = UDim2.fromOffset(12, 5)
    label.BackgroundTransparency = 1
    label.Text = labelText
    label.TextColor3 = Config.UI.Text
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local entry = Instance.new("TextBox")
    entry.Size = UDim2.fromOffset(64, 25)
    entry.Position = UDim2.new(1, -76, 0, 5)
    entry.BackgroundColor3 = Config.UI.Background
    entry.TextColor3 = Config.UI.Text
    entry.Text = formatter(value)
    entry.ClearTextOnFocus = false
    entry.Font = Enum.Font.GothamMedium
    entry.TextSize = 12
    entry.Parent = row

    createCorner(entry, 6)

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -24, 0, 8)
    bar.Position = UDim2.fromOffset(12, 43)
    bar.BackgroundColor3 = Config.UI.ToggleOff
    bar.BorderSizePixel = 0
    bar.Parent = row

    createCorner(bar, 8)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(
        (value - minimum) / math.max(maximum - minimum, 1),
        1
    )
    fill.BackgroundColor3 = Config.UI.Accent
    fill.BorderSizePixel = 0
    fill.Parent = bar

    createCorner(fill, 8)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(14, 14)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.fromScale(
        (value - minimum) / math.max(maximum - minimum, 1),
        0.5
    )
    knob.BackgroundColor3 = Config.UI.Text
    knob.BorderSizePixel = 0
    knob.Parent = bar

    createCorner(knob, 14)

    local dragging = false

    local function setValue(newValue: number)
        local rounded = math.round(newValue)
        local clamped = clampNumber(rounded, minimum, maximum)
        local ratio = (clamped - minimum) / math.max(maximum - minimum, 1)

        fill.Size = UDim2.fromScale(ratio, 1)
        knob.Position = UDim2.fromScale(ratio, 0.5)
        entry.Text = formatter(clamped)

        callback(clamped)
    end

    local function updateFromX(x: number)
        local ratio = math.clamp(
            (x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X,
            0,
            1
        )

        setValue(minimum + (maximum - minimum) * ratio)
    end

    addConnection(bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = true
            updateFromX(input.Position.X)
        end
    end))

    addConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = false
        end
    end))

    addConnection(UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        then
            updateFromX(input.Position.X)
        end
    end))

    addConnection(entry.FocusLost:Connect(function()
        local number = tonumber(entry.Text)

        if not number then
            entry.Text = formatter(value)
            notify(labelText .. ": invalid value", true)
            return
        end

        setValue(number)
    end))
end

local function buildContent()
    contentFrame = Instance.new("ScrollingFrame")
    contentFrame.Name = "Content"
    contentFrame.Position = UDim2.fromOffset(10, 50)
    contentFrame.Size = UDim2.new(1, -20, 1, -94)
    contentFrame.BackgroundTransparency = 1
    contentFrame.BorderSizePixel = 0
    contentFrame.ScrollBarThickness = 4
    contentFrame.CanvasSize = UDim2.new()
    contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    contentFrame.Parent = mainFrame

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = contentFrame

    task.wait(Config.Humanization.UiBuildDelay)

    createSectionTitle(contentFrame, "Movement")

    createToggle(contentFrame, "Speed Walk & High Jump", false, function(enabled)
        featureState.Movement = enabled

        if enabled then
            enableMovement()
        else
            disableMovement()
        end

        updateSystemStatus()
    end)

    createSlider(
        contentFrame,
        "Walk Speed",
        Config.WalkSpeed.Min,
        Config.WalkSpeed.Max,
        settings.WalkSpeed,
        function(v) return tostring(v) end,
        function(v)
              settings.WalkSpeed = v
            if featureState.Movement then
                applyMovementSettings()
            end
        end
    )

    createSlider(
        contentFrame,
        "Jump",
        Config.Jump.Min,
        Config.Jump.Max,
        settings.Jump,
        function(v) return tostring(v) end,
        function(v)
            settings.Jump = v
            if featureState.Movement then
                applyMovementSettings()
            end
        end
    )

    createSectionTitle(contentFrame, "Graphics")

    createToggle(contentFrame, "Fix Lag", false, function(enabled)
        featureState.FixLag = enabled

        if enabled then
            enableFixLag()
        else
            disableFixLag()
        end
    end)

    createToggle(contentFrame, "Full Bright", false, function(enabled)
        featureState.FullBright = enabled

        if enabled then
            enableFullBright()
        else
            disableFullBright()
        end
    end)

    createSectionTitle(contentFrame, "Flight")

    createToggle(contentFrame, "Fly", false, function(enabled)
        if enabled and featureState.TrackAnchor then
            notify("Fly stopped Track Anchor first")
            featureState.TrackAnchor = false
            disableTrackAnchor()
        end

        if enabled then
            featureState.Fly = true
            featureState.AutoFastCart = false
            disableAutoFastCart()
            enableFly()
        else
            featureState.Fly = false
            disableFly()
        end

        updateSystemStatus()
    end)

    createSlider(
        contentFrame,
        "Fly Speed",
        Config.FlySpeed.Min,
        Config.FlySpeed.Max,
        settings.FlySpeed,
        function(v) return tostring(v) end,
        function(v)
            settings.FlySpeed = v
        end
    )

    createSectionTitle(contentFrame, "Aim Assist")

    createToggle(contentFrame, "Auto Lock Head", false, function(enabled)
        featureState.Aim = enabled

        if enabled then
            enableAimAssist()
        else
            disableAimAssist()
        end

        updateSystemStatus()
    end)

    createSlider(
        contentFrame,
        "Aim FOV Radius",
        Config.Aim.FOVMin,
        Config.Aim.FOVMax,
        settings.AimFOV,
        function(v) return tostring(v) end,
        function(v)
            settings.AimFOV = v
            updateFOVCircle()
        end
    )

    createSlider(
        contentFrame,
        "Aim Smoothness",
        Config.Aim.SmoothMin,
        Config.Aim.SmoothMax,
        settings.AimSmoothness,
        function(v) return tostring(v) end,
        function(v)
            settings.AimSmoothness = v
        end
    )

    createSectionTitle(contentFrame, "Cart Ride")

    createToggle(contentFrame, "Auto Fast Cart", false, function(enabled)
        featureState.AutoFastCart = enabled

        if enabled and featureState.Fly then
            featureState.Fly = false
            disableFly()
        end

        if enabled then
            enableAutoFastCart()
        else
            disableAutoFastCart()
        end
    end)

    createToggle(contentFrame, "Track Anchor", false, function(enabled)
        featureState.TrackAnchor = enabled

        if enabled and featureState.Fly then
            featureState.Fly = false
            disableFly()
        end

        if enabled then
            enableTrackAnchor()
        else
            disableTrackAnchor()
        end
    end)

    local teleportButton = createTextButton(
        contentFrame,
        "Teleport to Selected Destination",
        UDim2.new(1, 0, 0, 42)
    )

    addConnection(teleportButton.Activated:Connect(function()
        teleportToDestination()
    end))

    local speedUpButton = createTextButton(
        contentFrame,
        "Cart Control: Speed Up",
        UDim2.new(1, 0, 0, 38)
    )

    addConnection(speedUpButton.Activated:Connect(function()
        interactWithCartControls("SpeedUp")
    end))

    local speedDownButton = createTextButton(
        contentFrame,
        "Cart Control: Speed Down",
        UDim2.new(1, 0, 0, 38)
    )

    addConnection(speedDownButton.Activated:Connect(function()
        interactWithCartControls("SpeedDown")
    end))

    createSectionTitle(contentFrame, "Noclip")

    createToggle(contentFrame, "Noclip", false, function(enabled)
        featureState.Noclip = enabled
        requestNoclip("Manual", enabled)
    end)

    createSectionTitle(contentFrame, "ESP")

    createToggle(contentFrame, "Cart ESP", false, function(enabled)
        featureState.CartESP = enabled
        refreshESPState()
    end)

    createToggle(contentFrame, "Enemy ESP", false, function(enabled)
        featureState.EnemyESP = enabled
        refreshESPState()
    end)

    createToggle(contentFrame, "Destination ESP", false, function(enabled)
        featureState.DestinationESP = enabled
        refreshESPState()
    end)

    createSectionTitle(contentFrame, "Target Selector")
    buildTargetSelector()
end

----------------------------------------------------------------
-- TARGET SELECTOR
----------------------------------------------------------------

local function getTaggedOrFolderTargets(
    tagName: string,
    folderName: string
): {Instance}
    local result = {}

    for _, object in ipairs(CollectionService:GetTagged(tagName)) do
        table.insert(result, object)
    end

    local folder = getFolder(folderName)

    if folder then
        for _, object in ipairs(folder:GetChildren()) do
            table.insert(result, object)
        end
    end

    return result
end

local function getSelectionTargets(category: string): {Instance}
    if category == "Carts" then
        return getTaggedOrFolderTargets("Cart", Config.Folders.Carts)
    end

    if category == "Enemies" then
        return getTaggedOrFolderTargets(
            "FarmableEnemy",
            Config.Folders.Enemies
        )
    end

    return getTaggedOrFolderTargets(
        "WinnerGate",
        Config.Folders.Destination
    )
end

local function createTargetButton(target: Instance)
    local button = createTextButton(
        dropdownList,
        target.Name,
        UDim2.new(1, -6, 0, 34)
    )

    addConnection(button.Activated:Connect(function()
        selectedTarget = target
        selectionLabel.Text = "Selected: " .. target:GetFullName()
        dropdownFrame.Visible = false
        notify("Target selected: " .. target.Name)
    end))
end

local function refreshDropdown()
    for _, child in ipairs(dropdownList:GetChildren()) do
        if child:IsA("GuiButton") then
            child:Destroy()
        end
    end

    local searchText = string.lower(dropdownSearch.Text)
    local targets = getSelectionTargets(selectedCategory)

    for _, target in ipairs(targets) do
        if string.find(string.lower(target.Name), searchText, 1, true) then
            createTargetButton(target)
        end
    end
end

function buildTargetSelector()
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 42)
    holder.BackgroundTransparency = 1
    holder.Parent = contentFrame

    local selectButton = createTextButton(
        holder,
        "Choose Cart / Enemy / Gate",
        UDim2.new(1, 0, 1, 0)
    )

    selectionLabel = selectButton

    addConnection(selectButton.Activated:Connect(function()
        dropdownFrame.Visible = not dropdownFrame.Visible

        if dropdownFrame.Visible then
            refreshDropdown()
        end
    end))

    dropdownFrame = Instance.new("Frame")
    dropdownFrame.Visible = false
    dropdownFrame.Size = UDim2.new(1, 0, 0, 210)
    dropdownFrame.BackgroundColor3 = Config.UI.Background
    dropdownFrame.BorderSizePixel = 0
    dropdownFrame.ZIndex = 20
    dropdownFrame.Parent = contentFrame

    createCorner(dropdownFrame, 8)
    createStroke(dropdownFrame)

    dropdownSearch = Instance.new("TextBox")
    dropdownSearch.Size = UDim2.new(1, -12, 0, 34)
    dropdownSearch.Position = UDim2.fromOffset(6, 6)
    dropdownSearch.BackgroundColor3 = Config.UI.Card
    dropdownSearch.TextColor3 = Config.UI.Text
    dropdownSearch.PlaceholderText = "Search..."
    dropdownSearch.PlaceholderColor3 = Config.UI.MutedText
    dropdownSearch.Text = ""
    dropdownSearch.ClearTextOnFocus = false
    dropdownSearch.Font = Enum.Font.Gotham
    dropdownSearch.TextSize = 12
    dropdownSearch.ZIndex = 21
    dropdownSearch.Parent = dropdownFrame

    createCorner(dropdownSearch, 6)

    local categories = {"Carts", "Enemies", "Gates"}

    for index, category in ipairs(categories) do
        local button = createTextButton(
            dropdownFrame,
            category,
            UDim2.fromOffset(94, 28)
        )

        button.Position = UDim2.fromOffset(6 + ((index - 1) * 100), 46)
        button.ZIndex = 21

        addConnection(button.Activated:Connect(function()
            selectedCategory = category
            refreshDropdown()
        end))
    end

    dropdownList = Instance.new("ScrollingFrame")
    dropdownList.Size = UDim2.new(1, -12, 1, -82)
    dropdownList.Position = UDim2.fromOffset(6, 78)
    dropdownList.BackgroundTransparency = 1
    dropdownList.BorderSizePixel = 0
    dropdownList.ScrollBarThickness = 3
    dropdownList.CanvasSize = UDim2.new()
    dropdownList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    dropdownList.ZIndex = 21
    dropdownList.Parent = dropdownFrame

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 4)
    listLayout.Parent = dropdownList

    addConnection(dropdownSearch:GetPropertyChangedSignal("Text"):Connect(function()
        if dropdownFrame.Visible then
            refreshDropdown()
        end
    end))
end

----------------------------------------------------------------
-- DRAGGING
----------------------------------------------------------------

local function enableDragging()
    local dragging = false
    local dragStart = Vector2.zero
    local startPosition = mainFrame.Position
    local activeInput: InputObject? = nil

    addConnection(mainFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = true
            dragStart = input.Position
            startPosition = mainFrame.Position
            activeInput = input
        end
    end))

    addConnection(UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end

        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch
        then
            return
        end

        local delta = input.Position - dragStart

        mainFrame.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end))

    addConnection(UserInputService.InputEnded:Connect(function(input)
        if input == activeInput then
            dragging = false
            activeInput = nil
        end
    end))
end

local function buildFooter()
    local footer = Instance.new("Frame")
    footer.Size = UDim2.new(1, -20, 0, 38)
    footer.Position = UDim2.new(0, 10, 1, -42)
    footer.BackgroundTransparency = 1
    footer.Parent = mainFrame

    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 1, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Ready."
    statusLabel.TextColor3 = Config.UI.MutedText
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 11
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = footer

    systemStatusLabel = statusLabel
end

local function buildRestoreButton()
    restoreButton = createTextButton(
        screenGui,
        "Open",
        UDim2.fromOffset(58, 34)
    )

    restoreButton.AnchorPoint = Vector2.new(1, 1)
    restoreButton.Position = UDim2.new(1, -12, 1, -12)
    restoreButton.Visible = false
    restoreButton.ZIndex = 100

    addConnection(restoreButton.Activated:Connect(function()
        mainFrame.Visible = true
        restoreButton.Visible = false
    end))
end

----------------------------------------------------------------
-- MOVEMENT
----------------------------------------------------------------

local function saveMovementOriginal(humanoid: Humanoid)
    movementOriginal.WalkSpeed = humanoid.WalkSpeed
    movementOriginal.UseJumpPower = humanoid.UseJumpPower
    movementOriginal.JumpPower = humanoid.JumpPower
    movementOriginal.JumpHeight = humanoid.JumpHeight
end

function applyMovementSettings()
    local character = getCharacter()
    local humanoid = getHumanoid(character)

    if not humanoid then
        notify("Humanoid unavailable", true)
        return
    end

    if movementOriginal.WalkSpeed == nil then
        saveMovementOriginal(humanoid)
    end

    humanoid.WalkSpeed = settings.WalkSpeed

    if humanoid.UseJumpPower then
        humanoid.JumpPower = settings.Jump
    else
        humanoid.JumpHeight = settings.Jump
    end
end

function enableMovement()
    local character = getCharacter()
    local humanoid = getHumanoid(character)

    if not humanoid then
        notify("Character not ready", true)
        return
    end

    saveMovementOriginal(humanoid)
    applyMovementSettings()

    disconnectFeatureConnections("Movement")

    addFeatureConnection(
        "Movement",
        humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if featureState.Movement and humanoid.WalkSpeed ~= settings.WalkSpeed then
                notify("Server/other script changed WalkSpeed")
            end
        end)
    )

    addFeatureConnection(
        "Movement",
        humanoid:GetPropertyChangedSignal("JumpPower"):Connect(function()
            if featureState.Movement and humanoid.UseJumpPower
                and math.abs(humanoid.JumpPower - settings.Jump) > 0.01
            then
                notify("JumpPower was overridden")
            end
        end)
    )

    addFeatureConnection(
        "Movement",
        humanoid:GetPropertyChangedSignal("JumpHeight"):Connect(function()
            if featureState.Movement and not humanoid.UseJumpPower
                and math.abs(humanoid.JumpHeight - settings.Jump) > 0.01
            then
                notify("JumpHeight was overridden")
            end
        end)
    )

    notify("Movement enabled")
end

function disableMovement()
    disconnectFeatureConnections("Movement")

    local character = getCharacter()
    local humanoid = getHumanoid(character)

    if not humanoid then
        movementOriginal = {}
        return
    end

    if movementOriginal.WalkSpeed then
        humanoid.WalkSpeed = movementOriginal.WalkSpeed
    end

    if movementOriginal.UseJumpPower ~= nil then
        if movementOriginal.UseJumpPower
            and movementOriginal.JumpPower
        then
            humanoid.JumpPower = movementOriginal.JumpPower
        elseif movementOriginal.JumpHeight then
            humanoid.JumpHeight = movementOriginal.JumpHeight
        end
    end

    movementOriginal = {}
    notify("Movement restored")
end

----------------------------------------------------------------
-- FIX LAG
----------------------------------------------------------------

local function cacheLagProperty(
    object: Instance,
    property: string,
    value: any
)
    lagOriginal[object] = lagOriginal[object] or {}

    if lagOriginal[object][property] == nil then
        lagOriginal[object][property] = value
    end
end

local function reduceVisualObject(object: Instance)
    if object:IsA("ParticleEmitter")
        or object:IsA("Trail")
        or object:IsA("Beam")
        or object:IsA("Smoke")
        or object:IsA("Fire")
        or object:IsA("Sparkles")
    then
        cacheLagProperty(object, "Enabled", object.Enabled)
        object.Enabled = false
        return
    end

    if object:IsA("PointLight")
        or object:IsA("SpotLight")
        or object:IsA("SurfaceLight")
    then
        cacheLagProperty(object, "Enabled", object.Enabled)
        object.Enabled = false
        return
    end

    if object:IsA("BasePart") then
        cacheLagProperty(object, "CastShadow", object.CastShadow)
        object.CastShadow = false
        return
    end

    if object:IsA("Texture") or object:IsA("Decal") then
        cacheLagProperty(object, "Transparency", object.Transparency)
        object.Transparency = math.max(object.Transparency, 0.65)
    end
end

local function reduceTrackMaterials(root: Instance)
    for _, object in ipairs(root:GetDescendants()) do
        reduceVisualObject(object)

        if object:IsA("BasePart") then
            cacheLagProperty(object, "Material", object.Material)
            object.Material = Enum.Material.SmoothPlastic
        end
    end
end

function enableFixLag()
    local roots = {
        getFolder(Config.Folders.Tracks),
        getFolder(Config.Folders.Carts),
        getFolder(Config.Folders.Map),
    }

    for _, root in ipairs(roots) do
        if root then
            reduceTrackMaterials(root)

            addFeatureConnection(
                "FixLag",
                root.DescendantAdded:Connect(function(object)
                    task.defer(function()
                        if featureState.FixLag then
                            reduceVisualObject(object)
                        end
                    end)
                end)
            )
        end
    end

    for _, object in ipairs(Lighting:GetChildren()) do
        if object:IsA("BloomEffect")
            or object:IsA("BlurEffect")
            or object:IsA("SunRaysEffect")
            or object:IsA("ColorCorrectionEffect")
            or object:IsA("DepthOfFieldEffect")
        then
            cacheLagProperty(object, "Enabled", object.Enabled)
            object.Enabled = false
        end
    end

    addFeatureConnection(
        "FixLag",
        Lighting.ChildAdded:Connect(function(object)
            if not featureState.FixLag then
                return
            end

            if object:IsA("BloomEffect")
                or object:IsA("BlurEffect")
                or object:IsA("SunRaysEffect")
                or object:IsA("ColorCorrectionEffect")
                or object:IsA("DepthOfFieldEffect")
            then
                cacheLagProperty(object, "Enabled", object.Enabled)
                object.Enabled = false
            end
        end)
    )

    notify("Fix Lag enabled")
end

function disableFixLag()
    disconnectFeatureConnections("FixLag")

    for object, properties in pairs(lagOriginal) do
        if object.Parent then
            for property, value in pairs(properties) do
                object[property] = value
            end
        end
    end

    table.clear(lagOriginal)
    notify("Graphics restored")
end

----------------------------------------------------------------
-- FULL BRIGHT
----------------------------------------------------------------

function enableFullBright()
    fullBrightOriginal = {
        Brightness = Lighting.Brightness,
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        ExposureCompensation = Lighting.ExposureCompensation,
        GlobalShadows = Lighting.GlobalShadows,
    }

    Lighting.Brightness = 2.2
    Lighting.Ambient = Color3.fromRGB(165, 165, 165)
    Lighting.OutdoorAmbient = Color3.fromRGB(185, 185, 185)
    Lighting.ExposureCompensation = 0.7
    Lighting.GlobalShadows = false

    notify("Full Bright enabled")
end

function disableFullBright()
    for property, value in pairs(fullBrightOriginal) do
        Lighting[property] = value
    end

    table.clear(fullBrightOriginal)
    notify("Lighting restored")
end

----------------------------------------------------------------
-- NOCLIP
----------------------------------------------------------------

local function restoreNoclip()
    for part, originalCanCollide in pairs(noclipOriginal) do
        if part.Parent then
            part.CanCollide = originalCanCollide
        end
    end

    table.clear(noclipOriginal)
end

local function enableNoclipConnection()
    if noclipConnection then
        return
    end

    noclipConnection = RunService.Stepped:Connect(function()
        local character = getCharacter()

        if not character then
            return
        end

        for _, object in ipairs(character:GetDescendants()) do
            if object:IsA("BasePart") then
                if noclipOriginal[object] == nil then
                    noclipOriginal[object] = object.CanCollide
                end

                object.CanCollide = false
            end
        end
    end)
end

local function updateNoclipConnection()
    local requested = false

    for _, enabled in pairs(noclipRequests) do
        if enabled then
            requested = true
            break
        end
    end

    if requested then
        enableNoclipConnection()
    else
        if noclipConnection then
            noclipConnection:Disconnect()
            noclipConnection = nil
        end

        restoreNoclip()
    end
end

function requestNoclip(owner: string, enabled: boolean)
    noclipRequests[owner] = enabled
    updateNoclipConnection()
end

----------------------------------------------------------------
-- FLY
----------------------------------------------------------------

local function cleanupFlyObjects()
    if flyRenderConnection then
        flyRenderConnection:Disconnect()
        flyRenderConnection = nil
    end

    if flyVelocity then
        flyVelocity:Destroy()
        flyVelocity = nil
    end

    if flyGyro then
        flyGyro:Destroy()
        flyGyro = nil
    end
end

local function clearFlyButtons()
    disconnectList(flyButtonConnections)

    for _, button in ipairs(flyButtons) do
        if button.Parent then
            button:Destroy()
        end
    end

    table.clear(flyButtons)
end

local function createFlyButton(
    text: string,
    position: UDim2,
    value: number
)
    local button = createTextButton(
        screenGui,
        text,
        UDim2.fromOffset(58, 58)
    )

    button.AnchorPoint = Vector2.new(1, 1)
    button.Position = position
    button.BackgroundTransparency = 0.2
    button.ZIndex = 80
    button.TextSize = 24

    createCorner(button, 29)

    table.insert(flyButtons, button)

    local pressed = false

    table.insert(
        flyButtonConnections,
        button.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.Touch
                and input.UserInputType ~= Enum.UserInputType.MouseButton1
            then
                return
            end

            pressed = true
            flyVertical = value
        end)
    )

    table.insert(
        flyButtonConnections,
        button.InputEnded:Connect(function(input)
            if not pressed then
                return
            end

            if input.UserInputType == Enum.UserInputType.Touch
                or input.UserInputType == Enum.UserInputType.MouseButton1
            then
                pressed = false
                flyVertical = 0
            end
        end)
    )
end

local function createFlyControls()
    clearFlyButtons()

    createFlyButton(
        "▲",
        UDim2.new(1, -84, 1, -150),
        1
    )

    createFlyButton(
        "▼",
        UDim2.new(1, -84, 1, -84),
        -1
    )
end

local function getCameraFlatLook(): Vector3
    local camera = workspace.CurrentCamera

    if not camera then
        return Vector3.new(0, 0, -1)
    end

    local look = camera.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)

    if flat.Magnitude < 0.01 then
        return Vector3.new(0, 0, -1)
    end

    return flat.Unit
end

local function flyStep()
    local character = getCharacter()
    local humanoid = getHumanoid(character)
    local root = getRoot(character)

    if not humanoid or not root or not flyVelocity or not flyGyro then
        return
    end

    local camera = workspace.CurrentCamera

    if not camera then
        return
    end

    local move = humanoid.MoveDirection
    local vertical = Vector3.new(0, flyVertical, 0)

    flyVelocity.Velocity = move * settings.FlySpeed
        + vertical * settings.FlySpeed

    local flatLook = getCameraFlatLook()

    flyGyro.CFrame = CFrame.lookAt(
        root.Position,
        root.Position + flatLook
    )
end

function enableFly()
    local character = getCharacter()
    local root = getRoot(character)

    if not root then
        notify("Fly: character not ready", true)
        return
    end

    cleanupFlyObjects()

    -- These are instantiated only after Fly is explicitly enabled.
    flyVelocity = Instance.new("BodyVelocity")
    flyVelocity.Name = "ClientFlyVelocity"
    flyVelocity.MaxForce = Vector3.new(
        Config.Fly.MaxForce,
        Config.Fly.MaxForce,
        Config.Fly.MaxForce
    )
    flyVelocity.P = Config.Fly.BodyVelocityP
    flyVelocity.Velocity = Vector3.zero
    flyVelocity.Parent = root

    flyGyro = Instance.new("BodyGyro")
    flyGyro.Name = "ClientFlyGyro"
    flyGyro.MaxTorque = Vector3.new(
        Config.Fly.MaxForce,
        Config.Fly.MaxForce,
        Config.Fly.MaxForce
    )
    flyGyro.P = Config.Fly.BodyGyroP
    flyGyro.D = Config.Fly.BodyGyroD
    flyGyro.CFrame = root.CFrame
    flyGyro.Parent = root

    requestNoclip("Fly", true)
    createFlyControls()

    flyRenderConnection = RunService.RenderStepped:Connect(flyStep)

    notify("Fly enabled")
end

function disableFly()
    requestNoclip("Fly", false)
    clearFlyButtons()
    cleanupFlyObjects()
    flyVertical = 0
    notify("Fly disabled")
end

----------------------------------------------------------------
-- AIM ASSIST
----------------------------------------------------------------

local fovCircle: Frame? = nil

local function getAimScreenPosition(): Vector2
    local camera = workspace.CurrentCamera

    if not camera then
        return Vector2.zero
    end

    if UserInputService.TouchEnabled
        and not UserInputService.KeyboardEnabled
    then
        local viewport = camera.ViewportSize
        return Vector2.new(viewport.X / 2, viewport.Y / 2)
    end

    return UserInputService:GetMouseLocation()
end

local function getEnemyData(model: Model): (
    Humanoid?,
    BasePart?
)
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local head = model:FindFirstChild("Head", true)

    if not humanoid or not head or not head:IsA("BasePart") then
        return nil, nil
    end

    return humanoid, head
end

local function targetIsValid(model: Model): boolean
    if model == getCharacter() then
        return false
    end

    local humanoid, head = getEnemyData(model)

    if not humanoid or not head then
        return false
    end

    return humanoid.Health > 0
end

local function refreshAimTargets()
    table.clear(aimTargets)

    for _, object in ipairs(CollectionService:GetTagged("FarmableEnemy")) do
        if object:IsA("Model") and targetIsValid(object) then
            table.insert(aimTargets, object)
        end
    end

    local fallback = getFolder(Config.Folders.Enemies)

    if fallback then
        for _, object in ipairs(fallback:GetChildren()) do
            if object:IsA("Model") and targetIsValid(object) then
                table.insert(aimTargets, object)
            end
        end
    end
end

local function chooseAimTarget(): BasePart?
    local camera = workspace.CurrentCamera

    if not camera then
        return nil
    end

    local cursor = getAimScreenPosition()
    local closest: BasePart? = nil
    local closestDistance = math.huge

    for _, model in ipairs(aimTargets) do
        if targetIsValid(model) then
            local _, head = getEnemyData(model)

            if head then
                local screenPosition, visible =
                    camera:WorldToViewportPoint(head.Position)

                if visible and screenPosition.Z > 0 then
                    local distance = (
                        Vector2.new(screenPosition.X, screenPosition.Y)
                        - cursor
                    ).Magnitude

                    if distance <= settings.AimFOV
                        and distance < closestDistance
                    then
                        closestDistance = distance
                        closest = head
                    end
                end
            end
        end
    end

    return closest
end

local function buildFOVCircle()
    if fovCircle then
        fovCircle:Destroy()
    end

    local circle = Instance.new("Frame")
    circle.Name = "FOVCircle"
    circle.AnchorPoint = Vector2.new(0.5, 0.5)
    circle.Position = UDim2.fromScale(0.5, 0.5)
    circle.Size = UDim2.fromOffset(
        settings.AimFOV * 2,
        settings.AimFOV * 2
    )
    circle.BackgroundTransparency = 1
    circle.BorderSizePixel = 0
    circle.ZIndex = 50
    circle.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = circle

    local stroke = Instance.new("UIStroke")
    stroke.Color = Config.Aim.CircleColor
    stroke.Transparency = Config.Aim.CircleTransparency
    stroke.Thickness = Config.Aim.CircleThickness
    stroke.Parent = circle

    fovCircle = circle
end

function updateFOVCircle()
    if not fovCircle then
        return
    end

    fovCircle.Size = UDim2.fromOffset(
        settings.AimFOV * 2,
        settings.AimFOV * 2
    )
end

local function aimRenderStep(deltaTime: number)
    if not featureState.Aim then
        return
    end

    local camera = workspace.CurrentCamera
    local target = chooseAimTarget()

    currentAimHead = target

    if not camera or not target then
        return
    end

    local goal = CFrame.lookAt(
        camera.CFrame.Position,
        target.Position
    )

    local alpha = 1 - math.exp(
        -settings.AimSmoothness * deltaTime
    )

    camera.CFrame = camera.CFrame:Lerp(goal, alpha)
end

function enableAimAssist()
    buildFOVCircle()

    if aimThread then
        task.cancel(aimThread)
    end

    aimThread = task.spawn(function()
        while featureState.Aim do
            local ok, err = xpcall(refreshAimTargets, debug.traceback)

            if not ok then
                reportError("Aim target refresh", err)
            end

            task.wait(0.25)
        end
    end)

    RunService:BindToRenderStep(
        aimRenderName,
        Enum.RenderPriority.Last.Value,
        aimRenderStep
    )

    notify("Auto Lock Head enabled")
end

function disableAimAssist()
    featureState.Aim = false

    if aimThread then
        task.cancel(aimThread)
        aimThread = nil
    end

    RunService:UnbindFromRenderStep(aimRenderName)

    if fovCircle then
        fovCircle:Destroy()
        fovCircle = nil
    end

    table.clear(aimTargets)
    currentAimHead = nil

    notify("Auto Lock Head disabled")
end

function getCurrentAimHead(): BasePart?
    return currentAimHead
end

----------------------------------------------------------------
-- CART HELPERS
----------------------------------------------------------------

local function getCurrentCart(): Model?
    local character = getCharacter()
    local humanoid = getHumanoid(character)

    if not humanoid then
        return nil
    end

    local seat = humanoid.SeatPart

    if not seat or not seat:IsA("VehicleSeat") then
        return nil
    end

    local model = seat:FindFirstAncestorOfClass("Model")

    if model then
        return model
    end

    return nil
end

local function getCartSeat(cart: Model): VehicleSeat?
    local seat = cart:FindFirstChildWhichIsA("VehicleSeat", true)

    if seat then
        return seat
    end

    return nil
end

local function adjustCartValues(cart: Model)
    local speedNames = {
        MaxSpeed = true,
        Speed = true,
        MaxVelocity = true,
    }

    for _, object in ipairs(cart:GetDescendants()) do
        if object:IsA("NumberValue") and speedNames[object.Name] then
            if cartSpeedOriginal[object] == nil then
                cartSpeedOriginal[object] = object.Value
            end

            local desired = math.min(
                cartSpeedOriginal[object] + Config.Cart.MaxSpeedIncrease,
                Config.Cart.MaxSpeedCap
            )

            object.Value = desired
        end
    end
end

function enableAutoFastCart()
    local cart = getCurrentCart()

    if not cart then
        notify("Sit in a VehicleSeat first", true)
        featureState.AutoFastCart = false
        return
    end

    activeCart = cart

    local seat = getCartSeat(cart)

    if seat then
        if cartSpeedOriginal[seat] == nil then
            cartSpeedOriginal[seat] = seat.MaxSpeed
        end

        seat.MaxSpeed = math.min(
            cartSpeedOriginal[seat] + Config.Cart.MaxSpeedIncrease,
            Config.Cart.MaxSpeedCap
        )
    end

    adjustCartValues(cart)

    disconnectFeatureConnections("AutoFastCart")

    addFeatureConnection(
        "AutoFastCart",
        LocalPlayer.CharacterAdded:Connect(function()
            if featureState.AutoFastCart then
                task.wait(0.5)

                local newCart = getCurrentCart()

                if newCart then
                    activeCart = newCart
                    adjustCartValues(newCart)
                end
            end
        end)
    )

    notify("Auto Fast Cart enabled")
end

function disableAutoFastCart()
    disconnectFeatureConnections("AutoFastCart")

    for object, original in pairs(cartSpeedOriginal) do
        if object.Parent then
            if object:IsA("VehicleSeat") then
                object.MaxSpeed = original
            elseif object:IsA("NumberValue") then
                object.Value = original
            end
        end
    end

    table.clear(cartSpeedOriginal)
    activeCart = nil

    notify("Cart speed restored")
end

----------------------------------------------------------------
-- TRACK ANCHOR
----------------------------------------------------------------

local function buildRailCache(): {BasePart}
    local result = {}

    for _, rail in ipairs(CollectionService:GetTagged("Rail")) do
        if rail:IsA("BasePart") then
            table.insert(result, rail)
        end
    end

    local folder = getFolder(Config.Folders.Rails)

    if folder then
        for _, object in ipairs(folder:GetDescendants()) do
            if object:IsA("BasePart") then
                table.insert(result, object)
            end
        end
    end

    return result
end

local function findNearestRail(
    root: BasePart,
    rails: {BasePart}
): BasePart?
    local nearest: BasePart? = nil
    local nearestDistance = math.huge

    for _, rail in ipairs(rails) do
        if rail.Parent then
            local distance = (
                rail.Position - root.Position
            ).Magnitude

            if distance < nearestDistance then
                nearestDistance = distance
                nearest = rail
            end
        end
    end

    return nearest
end

local function cleanupTrackAnchor()
    if trackAnchorAlign then
        trackAnchorAlign:Destroy()
        trackAnchorAlign = nil
    end

    if trackAnchorAttachment0 then
        trackAnchorAttachment0:Destroy()
        trackAnchorAttachment0 = nil
    end

    if trackAnchorAttachment1 then
        trackAnchorAttachment1:Destroy()
        trackAnchorAttachment1 = nil
    end
end

local function createTrackAnchor(
    root: BasePart,
    rail: BasePart
)
    cleanupTrackAnchor()

    trackAnchorAttachment0 = Instance.new("Attachment")
    trackAnchorAttachment0.Name = "ClientTrackAnchor0"
    trackAnchorAttachment0.Parent = root

    trackAnchorAttachment1 = Instance.new("Attachment")
    trackAnchorAttachment1.Name = "ClientTrackAnchor1"
    trackAnchorAttachment1.Position =
        rail.CFrame:PointToObjectSpace(root.Position)
    trackAnchorAttachment1.Parent = rail

    trackAnchorAlign = Instance.new("AlignPosition")
    trackAnchorAlign.Name = "ClientTrackAnchor"
    trackAnchorAlign.Attachment0 = trackAnchorAttachment0
    trackAnchorAlign.Attachment1 = trackAnchorAttachment1
    trackAnchorAlign.MaxForce = Config.TrackAnchor.MaxForce
    trackAnchorAlign.Responsiveness =
        Config.TrackAnchor.Responsiveness
    trackAnchorAlign.RigidityEnabled = false
    trackAnchorAlign.Parent = root
end

function enableTrackAnchor()
    local cart = getCurrentCart()

    if not cart then
        notify("Track Anchor needs a seated cart", true)
        featureState.TrackAnchor = false
        return
    end

    local root = getModelRoot(cart)

    if not root then
        notify("Cart has no usable root", true)
        featureState.TrackAnchor = false
        return
    end

    requestNoclip("TrackAnchor", false)

    if trackAnchorThread then
        task.cancel(trackAnchorThread)
    end

    trackAnchorThread = task.spawn(function()
        local rails = buildRailCache()

        while featureState.TrackAnchor do
            local currentCart = getCurrentCart()
            local currentRoot = if currentCart
                then getModelRoot(currentCart)
                else nil

            if currentRoot then
                local nearest = findNearestRail(currentRoot, rails)

                if nearest then
                    createTrackAnchor(currentRoot, nearest)
                end
            end

            task.wait(Config.TrackAnchor.RefreshInterval)
        end
    end)

    notify("Track Anchor enabled")
end

function disableTrackAnchor()
    featureState.TrackAnchor = false

    if trackAnchorThread then
        task.cancel(trackAnchorThread)
        trackAnchorThread = nil
    end

    cleanupTrackAnchor()
    notify("Track Anchor disabled")
end

----------------------------------------------------------------
-- CART CONTROL HOOK
----------------------------------------------------------------

function interactWithCartControls(action: string): boolean
    local cart = getCurrentCart()

    if not cart then
        notify("No seated cart found", true)
        return false
    end

    local acceptedNames: {[string]: boolean} = {}

    if action == "SpeedUp" then
        acceptedNames = {
            SpeedUp = true,
            Faster = true,
            Accelerate = true,
            Plus = true,
        }
    elseif action == "SpeedDown" then
        acceptedNames = {
            SpeedDown = true,
            Slower = true,
            Brake = true,
            Minus = true,
        }
    else
        notify("Unknown cart action", true)
        return false
    end

    for _, object in ipairs(cart:GetDescendants()) do
        if object:IsA("GuiButton")
            and acceptedNames[object.Name]
        then
            object:Activate()
            notify("Cart control activated: " .. action)
            return true
        end
    end

    notify(
        "No local cart control named for " .. action,
        true
    )

    return false
end

----------------------------------------------------------------
-- TELEPORT
----------------------------------------------------------------

local function findDestinationTarget(): Instance?
    if selectedTarget then
        if CollectionService:HasTag(selectedTarget, "WinnerGate")
            or CollectionService:HasTag(selectedTarget, "EndGate")
        then
            return selectedTarget
        end

        if selectedTarget:IsA("BasePart")
            and selectedTarget.Name:lower():find("end")
        then
            return selectedTarget
        end
    end

    local winner = CollectionService:GetTagged("WinnerGate")[1]

    if winner then
        return winner
    end

    local endGate = CollectionService:GetTagged("EndGate")[1]

    if endGate then
        return endGate
    end

    local folder = getFolder(Config.Folders.Destination)

    if folder then
        return folder:FindFirstChildWhichIsA(
            "BasePart",
            true
        ) or folder:FindFirstChildWhichIsA(
            "Model",
            true
        )
    end

    return nil
end

function teleportToDestination()
    local target = findDestinationTarget()

    if not target then
        notify("No destination gate found", true)
        return
    end

    local destinationRoot = getModelRoot(target)

    if not destinationRoot then
        notify("Destination has no BasePart", true)
        return
    end

    local character = getCharacter()
    local root = getRoot(character)

    if not root then
        notify("Character root unavailable", true)
        return
    end

    if activeTeleportTween then
        activeTeleportTween:Cancel()
        activeTeleportTween = nil
    end

    local goal = destinationRoot.CFrame
        + Config.Teleport.Offset

    local tween = TweenService:Create(
        root,
        TweenInfo.new(
            Config.Teleport.Duration,
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out
        ),
        {
            CFrame = goal,
        }
    )

    activeTeleportTween = tween

    addConnection(tween.Completed:Connect(function()
        if activeTeleportTween == tween then
            activeTeleportTween = nil
        end
    end))

    tween:Play()
    notify("Teleport tween started")
end

----------------------------------------------------------------
-- ESP
----------------------------------------------------------------

local function getESPPart(target: Instance): BasePart?
    if target:IsA("BasePart") then
        return target
    end

    if target:IsA("Model") then
        local head = target:FindFirstChild("Head", true)

        if head and head:IsA("BasePart") then
            return head
        end
    end

    return getModelRoot(target)
end

local function createESP(
    target: Instance,
    color: Color3,
    text: string
)
    if espObjects[target] then
        return
    end

    local adornee = getESPPart(target)

    if not adornee then
        return
    end

    local highlight = Instance.new("Highlight")
    highlight.Name = "ClientESPHighlight"
    highlight.Adornee = if target:IsA("Model")
        then target
        else adornee
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = color
    highlight.FillTransparency = Config.ESP.HighlightTransparency
    highlight.OutlineColor = color
    highlight.OutlineTransparency = 0.1
    highlight.Parent = screenGui

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ClientESPBillboard"
    billboard.Adornee = adornee
    billboard.Size = UDim2.fromOffset(180, 48)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = screenGui

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.TextColor3 = color
    label.TextStrokeTransparency = 0.35
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.Text = text
    label.Parent = billboard

    espObjects[target] = {
        Highlight = highlight,
        Billboard = billboard,
    }
end

local function removeESP(target: Instance)
    local data = espObjects[target]

    if not data then
        return
    end

    data.Highlight:Destroy()
    data.Billboard:Destroy()

    espObjects[target] = nil
end

local function refreshCartESP()
    if not featureState.CartESP then
        return
    end

    local targets = getTaggedOrFolderTargets(
        "Cart",
        Config.Folders.Carts
    )

    for _, target in ipairs(targets) do
        if target:IsA("Model") then
            local seat = getCartSeat(target)

            if seat and seat.Occupant == nil then
                createESP(
                    target,
                    Config.ESP.CartColor,
                    "Cart"
                )
            else
                removeESP(target)
            end
        end
    end
end

local function refreshEnemyESP()
    if not featureState.EnemyESP then
        return
    end

    local targets = getTaggedOrFolderTargets(
        "FarmableEnemy",
        Config.Folders.Enemies
    )

    for _, target in ipairs(targets) do
        if target:IsA("Model") and targetIsValid(target) then
            local humanoid = target:FindFirstChildOfClass("Humanoid")

            if humanoid then
                local text = string.format(
                    "%s\nHP %.0f / %.0f",
                    target.Name,
                    humanoid.Health,
                    humanoid.MaxHealth
                )

                createESP(
                    target,
                    Config.ESP.EnemyColor,
                    text
                )

                local data = espObjects[target]

                if data then
                    local label =
                        data.Billboard:FindFirstChildWhichIsA(
                            "TextLabel",
                            true
                        )

                    if label then
                        label.Text = text
                    end
                end
            end
        end
    end
end

local function refreshDestinationESP()
    if not featureState.DestinationESP then
        return
    end

    local targets = getTaggedOrFolderTargets(
        "WinnerGate",
        Config.Folders.Destination
    )

    for _, target in ipairs(targets) do
        local root = getModelRoot(target)

        if root then
            createESP(
                target,
                Config.ESP.DestinationColor,
                "Destination"
            )
        end
    end
end

local function updateESPDistances()
    local character = getCharacter()
    local root = getRoot(character)

    if not root then
        return
    end

    for target, data in pairs(espObjects) do
        if not target.Parent then
            removeESP(target)
            continue
        end

        local targetRoot = getModelRoot(target)

        if not targetRoot then
            continue
        end

        local distance = (
            targetRoot.Position - root.Position
        ).Magnitude

        local label = data.Billboard:FindFirstChildWhichIsA(
            "TextLabel",
            true
        )

        if label then
            if featureState.DestinationESP
                and CollectionService:HasTag(target, "WinnerGate")
            then
                label.Text = string.format(
                    "Destination\n%.0f studs",
                    distance
                )
            elseif featureState.CartESP
                and target:IsA("Model")
                and getCartSeat(target)
            then
                label.Text = string.format(
                    "Cart\n%.0f studs",
                    distance
                )
            end
        end
    end
end

local function clearAllESP()
    for target in pairs(espObjects) do
        removeESP(target)
    end
end

function refreshESPState()
    local anyESP =
        featureState.CartESP
        or featureState.EnemyESP
        or featureState.DestinationESP

    if not anyESP then
        if espThread then
            task.cancel(espThread)
            espThread = nil
        end

        clearAllESP()
        return
    end

    if espThread then
        return
    end

    espThread = task.spawn(function()
        while
            featureState.CartESP
            or featureState.EnemyESP
            or featureState.DestinationESP
        do
            local ok, err = xpcall(function()
                refreshCartESP()
                refreshEnemyESP()
                refreshDestinationESP()
                updateESPDistances()
            end, debug.traceback)

            if not ok then
                reportError("ESP refresh", err)
            end

            task.wait(Config.ESP.UpdateInterval)
        end

        clearAllESP()
        espThread = nil
    end)
end

----------------------------------------------------------------
-- SYSTEM STATUS
----------------------------------------------------------------

function updateSystemStatus()
    local aim = if featureState.Aim then "ON" else "OFF"
    local fly = if featureState.Fly then "ON" else "OFF"

    systemStatusLabel.Text = string.format(
        "Auto Lock Head: %s   Fly Mode: %s   Anti-Detection: Not implemented",
        aim,
        fly
    )
end

----------------------------------------------------------------
-- CHARACTER RESPAWN HANDLING
----------------------------------------------------------------

local function handleCharacterAdded(character: Model)
    task.wait(0.1)

    if featureState.Movement then
        local humanoid = getHumanoid(character)

        if humanoid then
            movementOriginal = {}
            saveMovementOriginal(humanoid)
            applyMovementSettings()
        end
    end

    if featureState.Noclip then
        requestNoclip("Manual", true)
    end
end

addConnection(LocalPlayer.CharacterAdded:Connect(handleCharacterAdded))

----------------------------------------------------------------
-- KEYBOARD TOGGLE
----------------------------------------------------------------

addConnection(
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then
            return
        end

        if input.KeyCode == Config.MenuToggleKey then
            mainFrame.Visible = not mainFrame.Visible
            restoreButton.Visible = not mainFrame.Visible
        end
    end)
)

----------------------------------------------------------------
-- INITIAL UI BUILD
----------------------------------------------------------------

tryRun("Build UI", function()
    buildBaseGui()
    buildHeader()
    buildContent()
    buildFooter()
    buildRestoreButton()
    enableDragging()
    updateSystemStatus()
end)

----------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------

addConnection(screenGui.Destroying:Connect(function()
    featureState.FixLag = false
    featureState.FullBright = false
    featureState.Movement = false
    featureState.Fly = false
    featureState.Aim = false
    featureState.AutoFastCart = false
    featureState.TrackAnchor = false
    featureState.Noclip = false
    featureState.CartESP = false
    featureState.EnemyESP = false
    featureState.DestinationESP = false

    disconnectFeatureConnections("Movement")
    disconnectFeatureConnections("FixLag")
    disconnectFeatureConnections("AutoFastCart")

    if aimThread then
        task.cancel(aimThread)
        aimThread = nil
    end

    if espThread then
        task.cancel(espThread)
        espThread = nil
    end

    if trackAnchorThread then
        task.cancel(trackAnchorThread)
        trackAnchorThread = nil
    end

    RunService:UnbindFromRenderStep(aimRenderName)

    cleanupFlyObjects()
    clearFlyButtons()
    cleanupTrackAnchor()

    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end

    restoreNoclip()

    if activeTeleportTween then
        activeTeleportTween:Cancel()
        activeTeleportTween = nil
    end

    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end

    table.clear(connections)
end)
