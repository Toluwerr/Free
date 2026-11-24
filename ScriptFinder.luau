local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Theme = table.freeze({
    Accent = Color3.fromRGB(44, 103, 197),
    Window = Color3.fromRGB(24, 24, 24),
    Raised = Color3.fromRGB(36, 36, 36),
    Divider = Color3.fromRGB(56, 56, 56),
    Text = Color3.fromRGB(255, 255, 255),
    Font = Font.fromId(12187365364, Enum.FontWeight.SemiBold),
    Header = 46,
    Radius = 8,
    Minimum = Vector2.new(320, 200),
    Default = Vector2.new(760, 480),
    Dot = 32,
})

local function create(class, properties, parent)
    local object = Instance.new(class)
    for key, value in pairs(properties) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function round(parent, radius)
    return create("UICorner", {
        CornerRadius = UDim.new(0, radius),
    }, parent)
end

local previous = playerGui:FindFirstChild("ScriptFinderWindow")
if previous then
    previous:Destroy()
end

local gui = create("ScreenGui", {
    Name = "ScriptFinderWindow",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ClipToDeviceSafeArea = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 20,
}, playerGui)

gui.ScreenInsets = Enum.ScreenInsets.None
gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None

local root = create("Frame", {
    Name = "Viewport",
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    BorderSizePixel = 0,
}, gui)

local window = create("Frame", {
    Name = "Window",
    Active = true,
    BackgroundColor3 = Theme.Window,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Visible = false,
}, root)

local windowCorner = round(window, Theme.Radius)

local header = create("CanvasGroup", {
    Name = "Header",
    BackgroundTransparency = 1,
    GroupTransparency = 1,
    Visible = false,
    Size = UDim2.new(1, 0, 0, Theme.Header),
    BorderSizePixel = 0,
    ZIndex = 3,
}, window)

local dragRegion = create("Frame", {
    Name = "DragRegion",
    BackgroundTransparency = 1,
    Size = UDim2.new(1, -110, 1, 0),
    Active = true,
    ZIndex = 3,
}, header)

local divider = create("Frame", {
    Name = "Divider",
    BackgroundColor3 = Theme.Divider,
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, Theme.Header - 1),
    Size = UDim2.new(1, 0, 0, 1),
    ZIndex = 3,
}, header)

local content = create("Frame", {
    Name = "Content",
    Visible = false,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, Theme.Header),
    Size = UDim2.new(1, 0, 1, -Theme.Header),
    ClipsDescendants = true,
    ZIndex = 1,
}, window)

local controls = create("Frame", {
    Name = "Controls",
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -9, 0.5, 0),
    Size = UDim2.fromOffset(96, 30),
    ZIndex = 4,
}, header)

create("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Right,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 3),
}, controls)

local connections = {}
local hoverTweens = {}
local alive = true

local function bind(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function line(parent, x1, y1, x2, y2, thickness, transparency, color)
    local dx, dy = x2 - x1, y2 - y1
    return create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2),
        Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), thickness),
        Rotation = math.deg(math.atan2(dy, dx)),
        BackgroundColor3 = color or Theme.Text,
        BackgroundTransparency = transparency or 0.12,
        BorderSizePixel = 0,
        ZIndex = parent.ZIndex + 1,
    }, parent)
end

local function disc(parent, x, y, diameter, color, layer)
    local dot = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(diameter, diameter),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        ZIndex = parent.ZIndex + (layer or 1),
    }, parent)
    create("UICorner", {CornerRadius = UDim.new(0.5, 0)}, dot)
    return dot
end

local function strokePath(parent, points, thickness, color)
    for index = 1, #points - 1 do
        local a, b = points[index], points[index + 1]
        line(parent, a[1], a[2], b[1], b[2], thickness, 0, color)
    end
    for _, point in ipairs(points) do
        disc(parent, point[1], point[2], thickness, color)
    end
end

local function paintIcon(icon, name)
    icon:ClearAllChildren()
    local function rectangle(x, y, width, height)
        return create("Frame", {
            Position = UDim2.fromOffset(x, y),
            Size = UDim2.fromOffset(width, height),
            BackgroundColor3 = Theme.Text,
            BorderSizePixel = 0,
            ZIndex = icon.ZIndex + 1,
        }, icon)
    end
    local function outline(x, y, width, height)
        local t = 2
        rectangle(x, y, width, t)
        rectangle(x, y + height - t, width, t)
        rectangle(x, y + t, t, height - 2 * t)
        rectangle(x + width - t, y + t, t, height - 2 * t)
    end
    if name == "Minimize" then
        rectangle(1, 8, 16, 2)
    elseif name == "Maximize" then
        outline(1, 1, 16, 16)
    elseif name == "Restore" then
        rectangle(5, 1, 12, 2)
        rectangle(15, 3, 2, 10)
        rectangle(5, 3, 2, 2)
        rectangle(13, 11, 2, 2)
        outline(1, 5, 12, 12)
    elseif name == "Close" then
        line(icon, 2, 2, 16, 16, 2, 0, Theme.Text)
        line(icon, 16, 2, 2, 16, 2, 0, Theme.Text)
    end
end

local function hover(button, transparency)
    local previousTween = hoverTweens[button]
    if previousTween then
        previousTween:Cancel()
    end
    local tween = TweenService:Create(button, TweenInfo.new(0.17, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        BackgroundTransparency = transparency,
    })
    hoverTweens[button] = tween
    tween:Play()
end

local function control(name, order)
    local button = create("TextButton", {
        Name = name,
        LayoutOrder = order,
        Size = UDim2.fromOffset(29, 28),
        BackgroundColor3 = Theme.Raised,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        ZIndex = 5,
    }, controls)
    round(button, 5)
    local icon = create("Frame", {
        Name = "Icon",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(18, 18),
        BackgroundTransparency = 1,
        ZIndex = 6,
    }, button)
    paintIcon(icon, name)
    bind(button.MouseEnter, function()
        hover(button, 0)
    end)
    bind(button.MouseLeave, function()
        hover(button, 1)
    end)
    bind(button.MouseButton1Down, function()
        hover(button, 0.24)
    end)
    bind(button.MouseButton1Up, function()
        hover(button, 0)
    end)
    return button, icon
end

local minimizeButton = control("Minimize", 1)
local maximizeButton, maximizeIcon = control("Maximize", 2)
local closeButton = control("Close", 3)

local resizeHandles = {}

local function resizeHandle(name, direction, anchor, position, size)
    local handle = create("Frame", {
        Name = name,
        Visible = false,
        AnchorPoint = anchor,
        Position = position,
        Size = size,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Active = true,
        ZIndex = 8,
    }, window)
    resizeHandles[handle] = direction
    return handle
end

resizeHandle("ResizeLeft", Vector2.new(-1, 0), Vector2.zero, UDim2.fromOffset(0, 12), UDim2.new(0, 6, 1, -24))
resizeHandle("ResizeRight", Vector2.new(1, 0), Vector2.new(1, 0), UDim2.new(1, 0, 0, 12), UDim2.new(0, 6, 1, -24))
resizeHandle("ResizeTop", Vector2.new(0, -1), Vector2.zero, UDim2.fromOffset(12, 0), UDim2.new(1, -24, 0, 6))
resizeHandle("ResizeBottom", Vector2.new(0, 1), Vector2.new(0, 1), UDim2.new(0, 12, 1, 0), UDim2.new(1, -24, 0, 6))
resizeHandle("ResizeTopLeft", Vector2.new(-1, -1), Vector2.zero, UDim2.fromScale(0, 0), UDim2.fromOffset(12, 12))
resizeHandle("ResizeTopRight", Vector2.new(1, -1), Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromOffset(12, 12))
resizeHandle("ResizeBottomLeft", Vector2.new(-1, 1), Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromOffset(12, 12))
local grip = resizeHandle("ResizeBottomRight", Vector2.new(1, 1), Vector2.one, UDim2.fromScale(1, 1), UDim2.fromOffset(24, 24))
line(grip, 8, 19, 19, 8, 1.3, 0.55)
line(grip, 13, 19, 19, 13, 1.3, 0.55)

local function showResizeHandles(visible)
    for handle in pairs(resizeHandles) do
        handle.Visible = visible
    end
end

local LogoAssets = table.freeze({
    RScripts = "",
    HaxHell = "",
    ScriptBlox = "",
})

local providers = table.freeze({
    {Name = "RScripts", AssetAttribute = "RScriptsLogo", Source = "https://rscripts.net/logo.svg"},
    {Name = "HaxHell", AssetAttribute = "HaxHellLogo", Source = "https://haxhell.com/images/logo/logo.webp"},
    {Name = "ScriptBlox", AssetAttribute = "ScriptBloxLogo", Source = "https://scriptblox.com/favicon.ico"},
})

local selector = create("Frame", {
    Name = "ProviderSelector",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -14, 0, 12),
    Size = UDim2.fromOffset(126, 38),
    BackgroundColor3 = Theme.Raised,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    ZIndex = 4,
}, content)
round(selector, 19)

local highlight = create("Frame", {
    Name = "Selection",
    Position = UDim2.fromOffset(3, 3),
    Size = UDim2.fromOffset(40, 32),
    BackgroundColor3 = Theme.Accent,
    BorderSizePixel = 0,
    ZIndex = 5,
}, selector)
round(highlight, 16)

local function assetUri(value)
    if typeof(value) == "number" and value > 0 then
        return "rbxassetid://" .. string.format("%.0f", value)
    end
    if typeof(value) == "string" then
        if string.match(value, "^%d+$") then
            return "rbxassetid://" .. value
        end
        if string.match(value, "^rbxassetid://%d+$") then
            return value
        end
    end
    return ""
end

local function providerImage(provider)
    local configured = script and assetUri(script:GetAttribute(provider.AssetAttribute)) or ""
    if configured ~= "" then
        return configured
    end
    return assetUri(LogoAssets[provider.Name])
end

for index, provider in ipairs(providers) do
    local logo = create("ImageLabel", {
        Name = provider.Name,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(3 + (index - 1) * 40 + 9, 8),
        Size = UDim2.fromOffset(22, 22),
        Image = providerImage(provider),
        ScaleType = Enum.ScaleType.Fit,
        BorderSizePixel = 0,
        ZIndex = 6,
    }, selector)
    logo:SetAttribute("OfficialSource", provider.Source)
    if script then
        bind(script:GetAttributeChangedSignal(provider.AssetAttribute), function()
            logo.Image = providerImage(provider)
        end)
    end
end

local selectorInput = create("TextButton", {
    Name = "Input",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    Text = "",
    AutoButtonColor = false,
    ZIndex = 7,
}, selector)

local selectedProvider = 1
local selectorGesture = nil
local selectorTween = nil
local page = 1

gui:SetAttribute("Provider", providers[selectedProvider].Name)
gui:SetAttribute("Page", page)

local navigation = create("Frame", {
    Name = "PageNavigation",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -148, 0, 12),
    Size = UDim2.fromOffset(116, 38),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 4,
}, content)

local function pageControl(name, x, direction)
    local button = create("TextButton", {
        Name = name,
        Position = UDim2.fromOffset(x, 3),
        Size = UDim2.fromOffset(30, 32),
        BackgroundColor3 = Theme.Raised,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        ZIndex = 5,
    }, navigation)
    round(button, 7)
    local icon = create("Frame", {
        Name = "Icon",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(18, 18),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 6,
    }, button)
    local function x(value)
        return 9 + direction * value
    end
    strokePath(icon, {{x(-6), 9}, {x(6), 9}}, 1.8, Theme.Text)
    strokePath(icon, {{x(0), 3}, {x(6), 9}, {x(0), 15}}, 1.8, Theme.Text)
    bind(button.MouseEnter, function()
        hover(button, 0)
    end)
    bind(button.MouseLeave, function()
        hover(button, 1)
    end)
    bind(button.MouseButton1Down, function()
        hover(button, 0.24)
    end)
    bind(button.MouseButton1Up, function()
        hover(button, 0)
    end)
    bind(button.Activated, function()
        page = math.max(1, page + direction)
        gui:SetAttribute("Page", page)
    end)
    return button
end

pageControl("PreviousPage", 0, -1)
pageControl("NextPage", 86, 1)

local searchPill = create("Frame", {
    Name = "Search",
    Position = UDim2.fromOffset(14, 12),
    Size = UDim2.fromOffset(280, 38),
    BackgroundColor3 = Theme.Raised,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    ZIndex = 4,
}, content)
round(searchPill, 19)

local searchIconButton = create("TextButton", {
    Name = "SearchIconButton",
    Position = UDim2.fromOffset(4, 0),
    Size = UDim2.fromOffset(34, 38),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "",
    ZIndex = 5,
}, searchPill)

local searchIcon = create("Frame", {
    Name = "Icon",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(18, 18),
    BackgroundTransparency = 1,
    ZIndex = 6,
}, searchIconButton)

strokePath(searchIcon, {{11.6, 11.6}, {16, 16}}, 2, Theme.Accent)
disc(searchIcon, 7.5, 7.5, 12, Theme.Accent, 2)
disc(searchIcon, 7.5, 7.5, 8, Theme.Raised, 3)

local textViewport = create("Frame", {
    Name = "TextViewport",
    Position = UDim2.fromOffset(38, 0),
    Size = UDim2.new(1, -52, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    ZIndex = 5,
}, searchPill)

local searchInput = create("TextBox", {
    Name = "Input",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
    MultiLine = false,
    Text = "",
    PlaceholderText = "Search",
    PlaceholderColor3 = Theme.Text:Lerp(Theme.Raised, 0.45),
    TextColor3 = Theme.Text,
    FontFace = Theme.Font,
    TextSize = 13,
    TextScaled = false,
    TextWrapped = false,
    TextTruncate = Enum.TextTruncate.None,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
    ZIndex = 6,
}, textViewport)

bind(searchIconButton.Activated, function()
    searchInput:CaptureFocus()
end)

local shortcuts = create("Frame", {
    Name = "Shortcuts",
    Position = UDim2.fromOffset(302, 12),
    Size = UDim2.fromOffset(136, 38),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 4,
}, content)

local function shortcut(name, labelWidth, draw)
    local button = create("TextButton", {
        Name = name,
        Size = UDim2.fromOffset(labelWidth, 38),
        BackgroundColor3 = Theme.Raised,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        FontFace = Theme.Font,
        Text = name,
        TextColor3 = Theme.Text,
        TextSize = 13,
        ZIndex = 5,
    }, shortcuts)
    round(button, 7)
    local icon = create("Frame", {
        Name = "Icon",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 6,
    }, button)
    draw(icon)
    bind(button.MouseEnter, function()
        hover(button, 0)
    end)
    bind(button.MouseLeave, function()
        hover(button, 1)
    end)
    return function(x, compact)
        local width = compact and 32 or labelWidth
        button.Position = UDim2.fromOffset(x, 0)
        button.Size = UDim2.fromOffset(width, 38)
        button.Text = compact and "" or name
        icon.Visible = compact
        return width
    end
end

local favoriteShortcut = shortcut("Favorites", 74, function(icon)
    local points = {}
    for index = 0, 9 do
        local angle = math.rad(-90 + index * 36)
        local radius = index % 2 == 0 and 8 or 3.7
        table.insert(points, {10 + math.cos(angle) * radius, 10 + math.sin(angle) * radius})
    end
    table.insert(points, points[1])
    strokePath(icon, points, 1.5, Theme.Text)
end)

local gameShortcut = shortcut("Game", 50, function(icon)
    local outline = {{5, 5.5}, {15, 5.5}, {17, 7}, {18.5, 13}, {17, 15.5}, {15, 15.5}, {12.5, 13}, {7.5, 13}, {5, 15.5}, {3, 15.5}, {1.5, 13}, {3, 7}, {5, 5.5}}
    strokePath(icon, outline, 1.5, Theme.Text)
    strokePath(icon, {{5.5, 9.5}, {9, 9.5}}, 1.5, Theme.Text)
    strokePath(icon, {{7.25, 7.75}, {7.25, 11.25}}, 1.5, Theme.Text)
    disc(icon, 13, 9.5, 1.7, Theme.Text)
    disc(icon, 15.5, 11, 1.7, Theme.Text)
end)

local function layoutSearchBar()
    local width = content.AbsoluteSize.X
    local stacked = width < 470
    local available = math.max(0, width - (stacked and 28 or 286))
    local iconsOnly = available < 280 + 8 + 74 + 6 + 50
    local shortcutsWidth = iconsOnly and 70 or 130
    local searchWidth = math.max(0, math.min(280, available - 8 - shortcutsWidth))
    searchPill.Size = UDim2.fromOffset(searchWidth, 38)
    searchPill.Visible = searchWidth >= 64
    shortcuts.Position = UDim2.fromOffset(14 + searchWidth + 8, 12)
    shortcuts.Size = UDim2.fromOffset(shortcutsWidth, 38)
    shortcuts.Visible = searchWidth >= 64
    local favoriteWidth = favoriteShortcut(0, iconsOnly)
    gameShortcut(favoriteWidth + 6, iconsOnly)
    local row = stacked and 60 or 12
    selector.Position = UDim2.new(1, -14, 0, row)
    navigation.Position = UDim2.new(1, -148, 0, row)
end

bind(content:GetPropertyChangedSignal("AbsoluteSize"), layoutSearchBar)
layoutSearchBar()

local function stopSelectorTween()
    if selectorTween then
        selectorTween:Cancel()
        selectorTween = nil
    end
end

local function selectProvider(index, animated)
    local nextProvider = math.clamp(index, 1, #providers)
    if selectedProvider ~= nextProvider then
        page = 1
        gui:SetAttribute("Page", page)
    end
    selectedProvider = nextProvider
    gui:SetAttribute("Provider", providers[selectedProvider].Name)
    stopSelectorTween()
    local target = UDim2.fromOffset(3 + (selectedProvider - 1) * 40, 3)
    if animated then
        selectorTween = TweenService:Create(highlight, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Position = target,
        })
        selectorTween:Play()
    else
        highlight.Position = target
    end
end

local function selectorIndex(x)
    return math.clamp(math.floor((x - selector.AbsolutePosition.X - 3) / 40) + 1, 1, #providers)
end

local function selectorPosition(x)
    return math.clamp(x - selector.AbsolutePosition.X - 20, 3, 83)
end

local dotButton = create("TextButton", {
    Name = "Open",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "",
    Size = UDim2.fromScale(1, 1),
    ZIndex = 10,
    Visible = false,
}, window)

local mode = "dot"
local restoreMode = "normal"
local position = Vector2.zero
local size = Theme.Default
local initialized = false
local gesture = nil
local margin = 12
local transition = 0
local moving = false
local motionTweens = {}
local completion = nil
local dotTween = nil

local function viewport()
    return root.AbsoluteSize
end

local function insets(view)
    local topLeft, bottomRight = GuiService:GetGuiInset()
    local safeLeft = Vector2.zero
    local safeRight = Vector2.zero
    local ok, area = pcall(function()
        return GuiService:GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets)
    end)
    if ok then
        safeLeft = Vector2.new(math.max(0, area.Min.X), math.max(0, area.Min.Y))
        safeRight = Vector2.new(math.max(0, view.X - area.Max.X), math.max(0, view.Y - area.Max.Y))
    end
    return Vector2.new(math.max(topLeft.X, safeLeft.X), math.max(topLeft.Y, safeLeft.Y)),
        Vector2.new(math.max(bottomRight.X, safeRight.X), math.max(bottomRight.Y, safeRight.Y)),
        safeLeft, safeRight
end

local function bounds(view)
    return Vector2.zero, view
end

local function clampSize(value, view)
    local low, high = bounds(view)
    local maximum = high - low
    return Vector2.new(
        math.clamp(value.X, math.min(Theme.Minimum.X, maximum.X), maximum.X),
        math.clamp(value.Y, math.min(Theme.Minimum.Y, maximum.Y), maximum.Y)
    )
end

local function clampPosition(value, dimensions, view)
    local low, high = bounds(view)
    return Vector2.new(
        math.clamp(value.X, low.X, math.max(low.X, high.X - dimensions.X)),
        math.clamp(value.Y, low.Y, math.max(low.Y, high.Y - dimensions.Y))
    )
end

local function offset(value)
    return UDim2.fromOffset(math.round(value.X), math.round(value.Y))
end

local function dotBounds(view)
    local low = Vector2.new(math.min(margin, view.X / 4), math.min(margin, view.Y / 4))
    local high = view - low
    local diameter = math.min(Theme.Dot, high.X - low.X, high.Y - low.Y)
    local dimensions = Vector2.new(diameter, diameter)
    local origin = Vector2.new(high.X - diameter, math.clamp((view.Y - diameter) / 2, low.Y, math.max(low.Y, high.Y - diameter)))
    return origin, dimensions
end

local function target(nextMode, view)
    if nextMode == "dot" then
        return dotBounds(view)
    elseif nextMode == "fullscreen" then
        return Vector2.zero, view
    end
    return position, size
end

local function prepare(view)
    size = clampSize(size, view)
    if not initialized then
        local low, high = bounds(view)
        position = (low + high - size) / 2
        initialized = true
    end
    position = clampPosition(position, size, view)
end

local function layout(nextMode, view)
    local headerTop = 0
    local right = 9
    local left = 0
    if nextMode == "fullscreen" then
        local core, _, safeLeft, safeRight = insets(view)
        headerTop = safeLeft.Y
        if view.X < 700 then
            headerTop = math.max(headerTop, core.Y)
        end
        right += safeRight.X
        left = safeLeft.X
    end
    header.Position = UDim2.fromOffset(0, headerTop)
    controls.Position = UDim2.new(1, -right, 0.5, 0)
    dragRegion.Position = UDim2.fromOffset(left, 0)
    dragRegion.Size = UDim2.new(1, -110 - right - left, 1, 0)
    content.Position = UDim2.fromOffset(0, Theme.Header + headerTop)
    content.Size = UDim2.new(1, 0, 1, -Theme.Header - headerTop)
end

local function stopDotTween()
    if dotTween then
        dotTween:Cancel()
        dotTween = nil
    end
end

local function cancelMotion()
    transition += 1
    if completion then
        completion:Disconnect()
        completion = nil
    end
    for _, tween in ipairs(motionTweens) do
        tween:Cancel()
    end
    table.clear(motionTweens)
    moving = false
end

local function animate(object, info, properties)
    local tween = TweenService:Create(object, info, properties)
    table.insert(motionTweens, tween)
    return tween
end

local function updateIcon()
    paintIcon(maximizeIcon, mode == "fullscreen" and "Restore" or "Maximize")
end

local function settle(view)
    if not alive or view.X <= 0 or view.Y <= 0 then
        return
    end
    if mode == "closed" then
        gui:Destroy()
        return
    end
    local origin, dimensions = target(mode, view)
    local isDot = mode == "dot"
    window.Position = offset(origin)
    window.Size = mode == "fullscreen" and UDim2.fromScale(1, 1) or offset(dimensions)
    window.BackgroundColor3 = isDot and Theme.Accent or Theme.Window
    windowCorner.CornerRadius = UDim.new(0, isDot and dimensions.X / 2 or (mode == "fullscreen" and 0 or Theme.Radius))
    layout(mode, view)
    header.GroupTransparency = isDot and 1 or 0
    header.Visible = not isDot
    content.Visible = not isDot
    showResizeHandles(mode == "normal")
    dotButton.Visible = isDot
    window.Visible = true
    moving = false
end

local function render()
    if not alive then
        return
    end
    local view = viewport()
    if view.X <= 0 or view.Y <= 0 then
        return
    end
    prepare(view)
    settle(view)
end

local function setMode(nextMode)
    if not alive or moving or mode == nextMode then
        return
    end
    local view = viewport()
    if view.X <= 0 or view.Y <= 0 then
        return
    end
    gesture = nil
    selectorGesture = nil
    if searchInput:IsFocused() then
        searchInput:ReleaseFocus()
    end
    selectProvider(selectedProvider, false)
    cancelMotion()
    stopDotTween()
    prepare(view)
    local previousMode = mode
    mode = nextMode
    if nextMode == "dot" then
        restoreMode = previousMode
    end
    moving = true
    dotButton.Visible = false
    showResizeHandles(false)
    local closing = nextMode == "closed"
    local collapsing = nextMode == "dot"
    local opening = previousMode == "dot"
    local origin, dimensions
    if closing then
        local current = window.AbsoluteSize
        dimensions = current * 0.9
        origin = window.AbsolutePosition - root.AbsolutePosition + (current - dimensions) / 2
    else
        origin, dimensions = target(nextMode, view)
    end
    local duration = closing and 0.22 or ((opening or collapsing) and 0.38 or 0.3)
    local info = TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    if not closing and not collapsing then
        layout(nextMode, view)
        updateIcon()
        header.Visible = true
        content.Visible = true
        if opening then
            header.GroupTransparency = 1
            animate(header, TweenInfo.new(0.21, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.08), {
                GroupTransparency = 0,
            })
        end
    else
        content.Visible = false
        animate(header, TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            GroupTransparency = 1,
        })
    end
    local windowProperties = {
        Position = offset(origin),
        Size = offset(dimensions),
        BackgroundColor3 = collapsing and Theme.Accent or Theme.Window,
        BackgroundTransparency = closing and 1 or 0,
    }
    local motion = animate(window, info, windowProperties)
    animate(windowCorner, info, {
        CornerRadius = UDim.new(0, collapsing and dimensions.X / 2 or (nextMode == "fullscreen" and 0 or Theme.Radius)),
    })
    local token = transition
    completion = motion.Completed:Connect(function(state)
        if not alive or token ~= transition or state ~= Enum.PlaybackState.Completed then
            return
        end
        if completion then
            completion:Disconnect()
            completion = nil
        end
        table.clear(motionTweens)
        if closing then
            gui:Destroy()
        else
            settle(viewport())
        end
    end)
    for _, tween in ipairs(motionTweens) do
        tween:Play()
    end
end

local function point(input)
    return Vector2.new(input.Position.X, input.Position.Y)
end

local function beginGesture(input, kind, direction)
    if gesture or selectorGesture or moving or mode ~= "normal" then
        return
    end
    local inputType = input.UserInputType
    if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
        return
    end
    gesture = {
        kind = kind,
        direction = direction,
        input = input,
        touch = inputType == Enum.UserInputType.Touch,
        start = point(input),
        position = position,
        size = size,
    }
end

bind(dragRegion.InputBegan, function(input)
    beginGesture(input, "drag")
end)

for handle, direction in pairs(resizeHandles) do
    bind(handle.InputBegan, function(input)
        beginGesture(input, "resize", direction)
    end)
end

bind(selectorInput.InputBegan, function(input)
    if gesture or selectorGesture or moving or mode == "dot" or mode == "closed" then
        return
    end
    local inputType = input.UserInputType
    if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
        return
    end
    selectorGesture = {
        input = input,
        touch = inputType == Enum.UserInputType.Touch,
        start = point(input),
        dragging = false,
    }
end)

local function matchesMovement(active, input)
    if active.touch then
        return input == active.input
    end
    return input.UserInputType == Enum.UserInputType.MouseMovement
end

local function matchesRelease(active, input)
    return input == active.input or (not active.touch and input.UserInputType == Enum.UserInputType.MouseButton1)
end

local function resizeAxis(origin, extent, delta, direction, limit, minimum)
    if direction == 0 then
        return origin, extent
    end
    if direction < 0 then
        local far = origin + extent
        local near = math.clamp(origin + delta, 0, math.max(0, far - math.min(minimum, far)))
        return near, far - near
    end
    local available = math.max(0, limit - origin)
    return origin, math.clamp(extent + delta, math.min(minimum, available), available)
end

bind(UserInputService.InputChanged, function(input)
    local activeSelector = selectorGesture
    if activeSelector and matchesMovement(activeSelector, input) then
        local cursor = point(input)
        if not activeSelector.dragging and math.abs(cursor.X - activeSelector.start.X) >= 3 then
            activeSelector.dragging = true
            stopSelectorTween()
        end
        if activeSelector.dragging then
            highlight.Position = UDim2.fromOffset(selectorPosition(cursor.X), 3)
        end
        return
    end
    local active = gesture
    if not active or not matchesMovement(active, input) then
        return
    end
    local delta = point(input) - active.start
    if active.kind == "drag" then
        position = active.position + delta
    else
        local view = viewport()
        local x, width = resizeAxis(active.position.X, active.size.X, delta.X, active.direction.X, view.X, Theme.Minimum.X)
        local y, height = resizeAxis(active.position.Y, active.size.Y, delta.Y, active.direction.Y, view.Y, Theme.Minimum.Y)
        position = Vector2.new(x, y)
        size = Vector2.new(width, height)
    end
    render()
end)

bind(UserInputService.InputEnded, function(input)
    local activeSelector = selectorGesture
    if activeSelector and matchesRelease(activeSelector, input) then
        selectorGesture = nil
        local x = point(input).X
        if not activeSelector.touch then
            x = UserInputService:GetMouseLocation().X
        end
        selectProvider(selectorIndex(x), true)
    end
    local active = gesture
    if active and matchesRelease(active, input) then
        gesture = nil
    end
end)

bind(UserInputService.WindowFocusReleased, function()
    gesture = nil
    if selectorGesture then
        selectorGesture = nil
        selectProvider(selectedProvider, true)
    end
end)

bind(root:GetPropertyChangedSignal("AbsoluteSize"), function()
    gesture = nil
    selectorGesture = nil
    selectProvider(selectedProvider, false)
    cancelMotion()
    stopDotTween()
    render()
end)

local function dotHover(active)
    if moving or mode ~= "dot" then
        return
    end
    stopDotTween()
    dotTween = TweenService:Create(window, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundColor3 = active and Theme.Accent:Lerp(Theme.Text, 0.14) or Theme.Accent,
    })
    dotTween:Play()
end

bind(dotButton.MouseEnter, function()
    dotHover(true)
end)

bind(dotButton.MouseLeave, function()
    dotHover(false)
end)

bind(dotButton.Activated, function()
    setMode(restoreMode)
end)

bind(minimizeButton.Activated, function()
    setMode("dot")
end)

bind(maximizeButton.Activated, function()
    setMode(mode == "fullscreen" and "normal" or "fullscreen")
end)

bind(closeButton.Activated, function()
    setMode("closed")
end)

bind(gui.Destroying, function()
    alive = false
    gesture = nil
    selectorGesture = nil
    stopSelectorTween()
    cancelMotion()
    stopDotTween()
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    for _, tween in pairs(hoverTweens) do
        tween:Cancel()
    end
    table.clear(connections)
    table.clear(hoverTweens)
end)

render()
