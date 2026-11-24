local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local AssetService = game:GetService("AssetService")

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CatalogRemote = "ScriptFinderCatalog"
local PageSize = 20

local function thumbnailFor(entry)
    local info = type(entry.game) == "table" and entry.game or {}
    local image = type(entry.image) == "string" and entry.image or ""
    if image == "" and type(info.imageUrl) == "string" then
        image = info.imageUrl
    end
    if image:match("^rbxassetid://%d+$") then
        return image
    end
    local id = image:match("^https://www%.roblox%.com/asset/%?id=(%d+)$")
        or image:match("^https://assetdelivery%.roblox%.com/v1/asset/%?id=(%d+)$")
    if id then
        return "rbxassetid://" .. id
    end
    local place = tonumber(info.placeId or entry.placeId or info.gameId)
    if place and place > 0 and place < 9007199254740992 and place == math.floor(place) then
        return string.format("rbxthumb://type=GameThumbnail&id=%.0f&w=384&h=216", place)
    end
    return ""
end

local function counter(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        local n = tonumber(value)
        if n and n >= 0 and n < 9007199254740992 then
            return math.floor(n)
        end
    end
    return nil
end

local function fetchCatalogue(target)
    local url = string.format("https://scriptblox.com/api/script/fetch?page=%d&max=%d&sortBy=updatedAt&order=desc", target, PageSize)
    local body
    if RunService:IsServer() then
        body = HttpService:GetAsync(url, true, {Accept = "application/json"})
    else
        body = game:HttpGet(url)
    end
    if type(body) ~= "string" or body == "" then
        error("Empty ScriptBlox response", 0)
    end
    local decoded = HttpService:JSONDecode(body)
    if type(decoded) == "table" and type(decoded.message) == "string" and not decoded.result then
        error(decoded.message, 0)
    end
    local result = type(decoded) == "table" and decoded.result
    if type(result) ~= "table" or type(result.scripts) ~= "table" then
        error("Invalid catalogue response", 0)
    end
    local total = tonumber(result.totalPages)
    if not total or total ~= total or total < 0 or total > 1000000 then
        error("Invalid page count", 0)
    end
    local items = {}
    for _, item in ipairs(result.scripts) do
        if #items >= PageSize then
            break
        end
        if type(item) == "table" and type(item.title) == "string" then
            local title = item.title:gsub("[%c]", " ")
            local length = utf8.len(title)
            if length and length > 0 then
                if length > 180 then
                    title = title:sub(1, utf8.offset(title, 181) - 1)
                end
                local id = item._id or item.slug
                if type(id) == "string" and id ~= "" then
                    table.insert(items, {
                        id = id,
                        title = title,
                        thumbnail = thumbnailFor(item),
                        views = counter(item.views, item.viewCount),
                        executions = counter(item.executeCount, item.executionCount, item.executions, item.executes, item.totalExecutions),
                        likes = counter(item.likeCount, item.likes),
                    })
                end
            end
        end
    end
    return {totalPages = math.max(1, math.floor(total)), items = items}
end

if RunService:IsServer() then
    local remote = ReplicatedStorage:FindFirstChild(CatalogRemote)
    if not remote then
        remote = Instance.new("RemoteFunction")
        remote.Name = CatalogRemote
        remote.Parent = ReplicatedStorage
    end
    assert(remote:IsA("RemoteFunction"), "Invalid catalogue remote")
    local cache, order, recent, pending = {}, {}, {}, {}
    local windowStart, requests = os.clock(), 0
    remote.OnServerInvoke = function(player, target)
        if type(target) ~= "number" or target ~= target or target < 1 or target > 1000000 or target ~= math.floor(target) then
            return {error = "Invalid page"}
        end
        local now = os.clock()
        if now - (recent[player] or -math.huge) < 0.5 then
            return {error = "Please try again"}
        end
        recent[player] = now
        local entry = cache[target]
        if entry and now - entry.time < 2 then
            return entry.data
        end
        if pending[target] then
            return {error = "Page loading"}
        end
        if now - windowStart >= 60 then
            windowStart, requests = now, 0
        end
        if requests >= 45 then
            return {error = "Request limit reached"}
        end
        requests += 1
        pending[target] = true
        local ok, data = pcall(fetchCatalogue, target)
        pending[target] = nil
        if not ok then
            warn("ScriptFinder: " .. tostring(data))
            return {error = "Server HTTP request failed; see server output"}
        end
        if not cache[target] then
            table.insert(order, target)
        end
        cache[target] = {time = os.clock(), data = data}
        if #order > 24 then
            cache[table.remove(order, 1)] = nil
        end
        return data
    end
    Players.PlayerRemoving:Connect(function(player)
        recent[player] = nil
    end)
    return
end

local playersService = game:GetService("Players")
if not playersService then
    error("ScriptFinder: Players service unavailable in this runtime", 0)
end

local player = playersService.LocalPlayer
local deadline = os.clock() + 15
while not player and os.clock() < deadline do
    task.wait()
    player = playersService.LocalPlayer
end
if not player then
    error("ScriptFinder: LocalPlayer unavailable; run the UI on a connected Roblox client", 0)
end

local playerGui = player:WaitForChild("PlayerGui", 15)
if not playerGui then
    error("ScriptFinder: PlayerGui did not initialize", 0)
end

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

local Lucide48 = table.freeze({
    ["arrow-left"] = {Image = "rbxassetid://16898612629", Offset = Vector2.new(98, 918)},
    ["arrow-right"] = {Image = "rbxassetid://16898612629", Offset = Vector2.new(453, 820)},
    ["search"] = {Image = "rbxassetid://16898613699", Offset = Vector2.new(918, 857)},
    ["star"] = {Image = "rbxassetid://16898613777", Offset = Vector2.new(967, 147)},
    ["gamepad-2"] = {Image = "rbxassetid://16898613353", Offset = Vector2.new(710, 967)},
    ["eye"] = {Image = "rbxassetid://16898613353", Offset = Vector2.new(771, 563)},
    ["play"] = {Image = "rbxassetid://16898613699", Offset = Vector2.new(918, 257)},
    ["thumbs-up"] = {Image = "rbxassetid://16898613869", Offset = Vector2.new(771, 355)},
})

local function lucideIcon(parent, name, size, color, zIndex)
    local data = Lucide48[name]
    return create("ImageLabel", {
        Name = "Icon",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size, size),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = data and data.Image or "",
        ImageRectOffset = data and data.Offset or Vector2.zero,
        ImageRectSize = Vector2.new(48, 48),
        ImageColor3 = color or Theme.Text,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = zIndex or parent.ZIndex + 1,
    }, parent)
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

local EmbeddedLogos = table.freeze({
    RScripts = "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff02ffffff030000000000000000dedede5de9e9e997a3a3a3190000000000000000ffffff03000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff01ffffff030000000000000000d0d0d037efefefb6fefdfdfffffffffff7f5f5e2e9e7e76d5f5f5f0800000000ffffff03ffffff020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff01ffffff040000000000000000d6d6d626f0f0f0a1f9f8f8fbfffffffffffcfcfdfffbfbfcfffffffffffffffff3f2f2cfd8d8d84f0000000000000000ffffff03ffffff010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000aaaaaa03000000000000000093939313e9e7e783f8f7f7f4fffffffffffcfcfffffbfbfcfffcfcfffffcfcfffffbfbfefffcfcfbfffffffffffefefff1f0f0acd7d7d7330000000000000000bfbfbf040000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff01ffffff010000000033333305e3e3e367f4f4f4defffffffffffffffffffbfbfcfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdfffbfbfdfffffffff9f7f7fceae8e892999999140000000001010100ffffff030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000d7d7d74df2f2f2cdfffffffffffffffffffbfbfcfffbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfcfffdfdfffffffffff7f5f5e0e9e6e6695555550600000000ffffff03ffffff0200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7f7f0201010100dedede27f0f0f0befdfcfcfffffffffffffafafcfdfbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffefbfbfffffbfbfcfffffffffffffffff1f1f1cbdad7d74d0000000000000000ffffff03ffffff01000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff01ffffff01bfbfbf20efeeeea6fbf9f9fdfffffffffffbfbfdfffbfbfdfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffdfafafefffcfcfbfffffffffffdfdfff1f1f1add8d3d3350000000000000000ffffff04000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000dadada38f3f2f2b4fffefefffffffffffffcfcfbfffbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdfffcfcfdfffffffff8f6f6f9e9e7e78ca5a5a5140000000000000000ffffff030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff01ffffff020000000000000000dedede56f4f4f4d7fffffffffffffffffffbfbfcfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffdfafafcfffdfdfffffffffff7f5f5e1eae8e86f7171710900000000ffffff02ffffff0200000000000000000000000000000000ffffff01000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000aaaaaa03ffffff02000000008b8b8b0bf0f0f079f8f6f6e9fffffffffffcfcfefffbfbfcfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfefffafafcfffffffffffffffff2f2f2cbd9d9d94a0000000000000000ffffff03ffffff01000000000000000000000000ffffff03ffffff01000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff030000000000000000b2b2b21eebebeb9cfbfafafffffffffffffcfcfcfffbfbfdfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffdfbfbfefffcfcfbfffffffffffefefff4f3f3afcfcfcf300000000000000000aaaaaa03000000007f7f7f0e0000000000000000ffffff03000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff01ffffff040000000000000000e1e1e13df2f1f1bcfffffffffffffffffffbfbfbfffbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdfffcfcfdfffffffff7f7f7f7ebe9e991ada3a3190000000000000000eae8e8cfe8e8e8732424240700000000ffffff02ffffff02000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff01ffffff030000000000000000e1e1e15ff4f4f4ddfffffffffffefefffffbfbfcfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffdfbfbfcfffefefffffffffff7f6f6e5e2dfdf5900000000f6f5f5effffffffff2f1f1ccdadada4c0000000000000000ffffff03ffffff01000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000aaaaaa03ffffff01000000009f9f9f10e8eaea86f7f6f6f2fffffffffffcfcfdfffbfbfdfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfefffbfbf9ffffffffecebebb300000000f6f4f4e8fffdfdfcfffffffffffdfdfff3f2f2b2d7d7d7340000000000000000bfbfbf0400000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff030000000000000000c2c8c82aedededacfffffffffffffffffffbfbfcfdfbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffdfafafdfdfdfdfeebeaeaaa00000000f1eeeedffffffffffffbfbfcfffcfcfdfffffffff8f7f7fbebebeb93adadad190000000001010100ffffff03000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff01ffffff030000000000000000e1e1e145f2f2f2c5fffffffffffffffffdfafafcfffbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdffffffffebeaeaac00000000f1eeeedefffffffffffbfbfefffcfcfffffbfbfcfffcfcfffffffffff8f7f7e5e6e4e4685555550600000000ffffff037f7f7f02000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff02ffffff020000000000000006e2e2e26bf6f4f4e5fffffffffffdfdfffffbfbfcfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdffffffffebeaeaad00000000edebebd6fffffffffffbfbfefffcfcfffffcfcfffefbfbfffffbfbfcfffffffffffffffff3f2f2cad7d7d7470000000000000000ffffff03ffffff01000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff030101010000000000b6b6b615edebeb90f9f7f7f3fffffffffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdffffffffeae9e9ae00000000ecebebd4fffffffffffbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffbfbfefffcfcfbfffffffffdfcfcfff1f1f1a6c6bfbf240000000000000000ffffff0300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001ffffff030000000000000000d0d0d031f0f0f0b5fcfbfbfafffcfcfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdffffffffeaeaeaae00000000f0eeeedefffffffffffbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdfffbfbfdfffffffff6f5f5ece5e5e576a2a2a20b00000000ffffff01ffffff020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7f7f02ffffff070000000000000000d8d8d876fefcfcfffffbfbfdfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdffffffffeae9e9af00000000f2f0f0e4fffffffffffbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfbfffffffffffffffff7f5f5d9dfdfdf590000000000000000ffffff03ffffff01000000000000000000000000000000000000000000000000000000000000000000000000ffffff030101010000000000b6b6b615ebebeb84f9f8f8e4fdfbfbfefffbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdffffffffeae9e9af00000000ecececd4fffffffffffbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfefffbfbfcfffffffffffffffff0f0f0b3dddddd350000000000000000ffffff03ffffff010000000000000000000000000000000000000000ffffff02ffffff010000000024242407e0e0e06cf4f4f4e3fffffffffffffffffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdffffffffe9e9e9b000000000ebe9e9cefffffffffffbfbfdfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdfffcfcfcfffffffffaf8f8fcebe9e990b0baba1a0000000000000000ffaaaa030000000000000000ff7f7f02ffffff030000000000000000e2e2e251f3f2f2cdfffffffffffffffffffbfbfbfffbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdffffffffe9e9e9b000000000ebeaead0fffffffffffbfbfdfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfcfffdfdfffffffffff6f6f6e6e5e5e56d0000000400000000ffffff02ffffff040000000000000000d1d1d138efeeeeb8fffffffffffffffffffbfbfcfdfafafefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdffffffffeae9e9b000000000ecebebd4fffffffffffbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfefffbfbfbfffffffffffffffff2f2f2cbdcd8d8490000000000000000cccccc23ebebeb9df9f8f8fbfffffffffffbfbfdfffbfbfdfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdfdfdfdfee9e7e7ae00000000f1eeeedcfffffffffffbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfefffafafcfffffffffefdfdffedebeb9fe6e6e67ef9f7f7f0fffffffffffcfcfefffbfbfcfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfefffbfbf9ffffffffe9e9e9bd00000000eeededd7fffffffffdfbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdfffcfcfefffffffffffffffffffffffffffbfbfcfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfcfffefefffffffffff6f6f6e9e3e3e36700000000ebeaead0fffffffffdfafafefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfcfffbfbfcfffbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffdfafafdfffcfcfdfffffffff9f8f8f8ececec96b6b6b61c0000000000000000ecebebd2fffffffffdfbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdfffcfcfcfffffffffdfcfcffeeeeeeabd6d6d62c0000000000000000ffffff0300000000ebe9e9cdfffffffffdfafafefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfefffbfbfcfffffffffffffffff0f0f0c4d8dbdb480000000000000000ffffff03ffffff010000000000000000ecebebd1fffffffffdfafafefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfefffffffffffffffff5f4f4d2e7e4e4580000000100000000ffffff02ffffff0200000000000000000000000000000000eceaeacafffffffefffbfbfdfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfffffdfdfff7f7f7e3e3e3e3713f3f3f080000000001010100aaaaaa03000000000000000000000000000000000000000000000000eae9e9d6fffffffffdfafafbfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdfffffffff0efefd15555551200000000ffffff02cccccc050000000100000000000000000000000000000000000000000000000000000000e4e2e274f8f8f8f0fffffffffffcfcfefdfafafdfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffefbfbfffffcfcfefaf9f9f6f2f2f2b4dadada3f0000000000000000ffffff03ffffff0100000000000000000000000000000000000000000000000000000000bac0c025edededa2fefcfcfffffffffffffbfbfcfdfafafefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffdfdfffffffffffaf9f9feedececa2ccc4c4230000000000000000ffffff030000000000000000000000000000000000000000ffffff030000000000000000e3e3e340f3f3f3c2fffffffffffffffffdfafafcfffbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffdfafafdfffcfcfefffffffff7f6f6ece3e3e3785f5f5f0800000000ffffff01ffffff02000000000000000000000000000000007f7f7f02ffffff020000000000000002e3e3e366f6f4f4e3fffffffffffefefffffbfbfcfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffefcfcfffffbfbfbfffefefffffffffff6f6f6d4dfdfdf5a0000000000000000ffffff03ffffff0100000000000000000000000000000000ffffff030201010000000000b2b2b214e9e9e984f8f7f7f4fffffffffffbfbfefffbfbfdfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfefffbfbfcfffbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfefffafafcffffffffffffffffefefefb8c8cccc380000000000000000000000000000000000000000000000000000000000000000ffffff030000000000000000cecece2ff0efefb1fffdfdfffffffffffffbfbfcfdfbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffefefffffffffffffffffffffbfbfcfffbfbfefffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdfffbfbfcfffffffffcfafaffefefefa9bfbfbf1c00000000000000000000000000000000000000000000000000000000ffffff01ffffff030000000000000000dde1e144f2f2f2c7fffffffffffffffffffafafcfefbfbfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdfffffffff8f6f6cce6e6e689f9f7f7f5fffffffffffefefffffbfbfcfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffdfafafdfffdfdfffffffffff7f6f6f0e8e8e88687878711000000000000000000000000000000000000000000000000000000000000000000000000ffffff02ffffff020000000000000005e5e2e26cf8f6f6e4fffffffffffdfdfffffbfbfcfffcfcfffffcfcfffffcfcfffffcfcfffffbfbfcfffffffffaf7f7b400000000d2d2d228f1f1f198f8f7f7f3fffffffffffcfcfefdfafafcfffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffcfcfffffbfbfdfffbfbfcfffffffff9f8f8f8f1efef98cacaca2200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff030101010000000000bfb2b214e9e9e98df9f8f8f8fffffffffffbfbfdfffbfbfdfffcfcfffffcfcfffffbfbfcfffffffff8f5f5b8ffffff030000000000000000c2c2c22aedebeb9ff9f8f8fafffffffffffbfbfefffbfbfcfffcfcfffffcfcfffffcfcfffffcfcfffffbfbfefffbfbfbfffffffffffffffff1f0f0bfcdcdcd390000000000000000ffffff030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff030000000000000000cdcdcd33f0f0f0b3fffffffffffffffffffbfbfcfffbfbfefffbfbfcfffffffff7f5f5b500000000cccccc05ffffff030000000000000000d1d1d138eeeeeeaefcfafafffffffffffffcfcfdfffbfbfdfefbfbfffffafafcfffffffffffffffff4f4f4d7e9e9e95d0000000000000000ffffff047f7f7f0200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff01ffffff030000000000000000dddddd53f2f2f2d3fffffffffffffffffdfafaf9fffffffff6f5f5b500000000ffffff0300000000ffffff02ffffff030000000000000000dde1e13cf0f0f0b2fefcfcfffffffffffffdfdfffffffffff8f7f7f2e8e6e67e7777770f0000000001010100ffffff020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff02ffffff02000000005c5c5c0be9e7e776f8f7f7edfffffffffffffffff6f5f5b400000000ffffff03000000000000000000000000ffffff02ffffff020000000000000000d7d3d347f0eeeebdf6f4f4f2ededed9dcecece250000000000000000bfbfbf04000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff030000000000000000cfc6c61beaeaea95fcfbfbfff6f3f3b500000000ffffff030000000000000000000000000000000000000000aaaaaa03ffffff020000000000000000cdcdcd240000000000000000ffffff03ffffff01000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001bfbfbf040000000000000000d9d9d94be3e1e17800000000ffffff0200000000000000000000000000000000000000000000000000000000ffffff030101010000000000ffffff02ffffff0200000000000000000000000000000000000000000000000000000000000000000000000000000000",
    HaxHell = "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000008888550fb5b5665a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffff000100000000aeae5d13e1e14caeb6b648070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000550300007f020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff7f7f0200000000dfd74f20ede132e9b8b15524000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7f7f0200000000e3d8742ec1be655300000000ffff7f02000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffff3f04ffff0001dfc83b62f5d927ffb6ae5e2300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffaa5503ff7f0002dfdf4950ddd84c9000000000ffff5503000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001ffff000300000200eec433c7f2c723ee6677770f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffff3f0400000000e8cb3ba7dec7378600000000ffff55030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffcc330500000000dfb85062ffcf27ffecbd31b600000100ffff00020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000bf7f3f0400000000cfaf5a30f6b634fedca63d4200000000ffaa550300000000000000000000000000000000000000000000000000000000000000000000000000000001ffbf3f0400000000c5a75c3af6b72deffebf26ffd7b04e54ffff0001ffaa550300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cc66330500000000a5998c14f1aa2eddf2ac2cdb3366cc05ffff0001000000010000000000000000000000000000000000000000000000000000000000000000ff7f7f02ffff000100000000dba85950f5ab2ce9ffb925ffeaaf39b10000020000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff7f00020200000000000000a27b5521eb9d34c2ffac28ffd89b465700000000ffaa550300000000000000000000000000000000000000000000000000000000ffff0001ff7f3f040000000000ffff02e5a24b77f8a031ffffa91effeca63cbea3a37f0ec5a26816b69d6d15000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f000002ff0000030000000000ffff03c832286bed742be5ffa72cffe6983ba400ffff01ffaa550300000000000000000000000000000000000000000000000000000000000000010000000000000000cd935039ef9633c5ff9a2cffff9a26ffea9938b88b8b8b0b00000000d6a54b5eda9e4c6a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff000001ff5555030000000000000000bd523d3edf352bc2f44824ffff8b24fff28e32e9b6857915000000007f7f7f02000000000000000000000000000000000000000000000000ff00000100000000b2997214e8904388f78e30f8ff8d24fffc8922fbf38e2cf4b6734e2a0200000000000100e58236c9db97418f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000aa0055030000000000000000ae444429d93729a5ec3324fdf43422fff6722af8ff8b2fffe27e3d7d9fbf9f08bba17226000000007f7f7f020000000000000000000000000000000000000001000000016d5b6d0eed8835d1ff8e2bfffc8027fef98026fcfe8428ffe74f22ec580b2c1700000000c72e2c7dff732effd9a6435f7f7f7f02000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000003f7f5f08d2393578e62d26f0f62a1effe72219feeb4123fcff7c2efef57c32f7b87b571deeac5a1fe09953a500000000ff7f7f0200000000000000000000000000000000aaaa550300000000c67d493bf97c29fffd7823fafa7928fefe7f28fff36525feef2b22ffe2332abbdd3a2da9ef2f22fff36b2bfdd4af4f300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff00000100555503bf333650d92f29d3f8302cffed281fffe7251efbe3221bfff05427fdff762affee7233cf7f3f7f04de7b391fee8439e58b5c391600000000ffff0001000000000000000000000000ff7f3f0400000000e580435bff7c2dfffb7024fbfb7226fffe772bffec421fffe6271dfff52e21fff62b1ffffb3a26ffe3773fb1007fff028e6a582b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f000002000000009c443a1ad52323faf21e1bffc9332ccde42d26efec2320ffe6281ffff8612dfdff6c2afff16d36ca00000000d67d404bf98036fed77b4a3a00000000aa555503000000000000000000000000ffaa550300000000da703b84ff742cfffb6b26fcfd6e28fff86429ffe62c1cffea271effe8271dfbed251efbe33a29debd7b621fff000001cb754ea9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff00000200000000a3262b35e1201dfcd82420ec9b373733e82d2be4ed2220ffed3a26fef9642dfefb622cfff46531f3ce6c4d63ee6c38cbf97031fec6714b3600000000aa555503000000000000000000000000ff7f000200000000ed6a33bdff6929fffa6528fcfd692bfff34e25ffe4211dffe72520ffe7231efaf82a23ffd1342f8200000000c0603025ee7340f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff3f3f0400000000c73e326aee5035feb75333406d486d07e12828f1e81c20fff1482afefc622ffff75b2cfffd5e2ffffd6233ffff6430ffef5b34e46f4f4f10000000000000000100000000000000000000000000000000002a5506f0632dd5ff6128fff95e29fdfd632bffeb3a23ffe41e1fffe52320ffe4211ffced2623ffcc33305a00000000e8663ea0ea6436ef000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001ff0000016d486d07e13c2fd8d948348d00000000a22e342cdc1f24f6e41c1efff64d2bfefc5a2efffa562cfffa572dfff9562ef9fe4428ffd535329800000000ff000003000000000000000000000000ff7f7f0200000000b2664c28f05b2ff5fc592afff9572afefa582dffe52921ffe11c1effe31f1ffee51e20ffdd1f21f88c3e4331dd66407afd6635ffe1603b9e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000bf3f3f0400000000c92d3055ef2625ffb42b303a00000000c72b3569eb1d23ffe22221fcfc4e30fffa502cfffb532efff84f2efef13125fedf2529eaaf3d461dff0000017f000002000000000000000000000000ff55550300000000d8644142ff5c32fff8522afdfa542bfff54b2bffdf1c20ffe21c21ffdf1b20ffe2201fffee3c2cfaf15536e1ff542ffff75830fac5654c350000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff00000300000000cc292b8df92229fec92a3078a836412fdb222ddfe71822fee82925fefc4a2ffffb4c2ffff5432efee72725fde5272afdbc38385100000000ff00000200000000000000000000000000000000bf3f3f0400000000d2593b6cff542efff74d2afcfb512dffec3c28ffd9171fffde1a23ffdf1e22fff6432cffff5132fffe492cffff4d2fffe0523797000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff00000300000000c9262d93f21d28ffe21d25fbe01e28f9e71b24ffde1522ffef302afffc4830fff33b2dffe01f23fcef1f2affc72d338000000000cc003305ff000001ff000001ff000001ff000001ff000001ff333305ff000001e6593ba8ff5030fff7482bfcfd4d30ffe42d27ffd61520ffd9171ffff2392dfffd4832fff9442efcff4f35ffe14f39ae754e620dff7f7f020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000bf3f3f04ff000001c6283364ee1b28ffe31622fbe31722ffe01924fede1722fff5392efff73e2effdd1c26fde61926ffd3232bce00ff0001010000000000000000000000000000000000000000000000000000000000000000000000e94c34c1ff482ffff7442cfdf6422fffd91e25ffd41321ffe62a29fff84330fff53d2cfcfd4832ffe15541890001010001000000ff0000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000099333a23dd1c28f4e21722fede1724fedd1624ffe11a23fff93a32ffe32227ffd81524fce61825ffb82127825c3939167b1a231d6b31311a753a3a1a753a3a1a7f3a3a1a7f443a1a8442381b70333d1992514b2feb4833ecfa3f2dfff6422efeea332affd01322ffd81a23fff33b30fff63c2ffcff3e31ffdd47389900000000ff550003ff00000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000079484815713f462400000000cc1e29c0e61522ffdc1524fcd91324ffe41f29ffef2d2dffd71322ffd91525ffda1525ffd31725f1d11725e8dc1f28eaef3736eaee3a37eaee3a35eaee3a32eaed3a34eaed3a35eaec3b30e9ed3c30eff63e2ffff23c2efff33c2fffd71d27ffce1222ffe4282afff63b30fef8372dffec3c35f0904c441eff550003ff7f7f0200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000552a2a0cba2f3c9d00996605bc1e2f6be11526ffd91225fcd61023ffe7222cffe11f28ffd61025ffd61124ffd51123ffda1324ffe31b27fff63032fffb3633fff93430fff83630fff7362ffff7342ffff83530fff7362efff5332cfff2332efef73c32ffde2626ffc90e22ffcf1524fff0322ffff43531fefa342fffe83835e000ffcc0500000000ff000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff00000200000000d41c2ecbcd1e2ea573394a1fd2152cfdd61024ffd51023ffe4212effd51525ffd30f23ffdc1726ffe31f2affeb292efef13031fef0312dfef1302ffef13130fef0322ffef0312ffef0302ffef1302ffef2302ffef3312ffef13232ffdb212affc70d20ffc81024ffd31927fff33331fff23030fff53432fee32931ffa41a2690902a331eff000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff00000300000000cb1f2fb2f2172effb62b3b74c6192cd4d90f25ffd21326fee11d2effd20f21ffe4222bffee2d30fff12d31fff52e30fff42f30fff23031fff32f32fff13032fff12f32fff22e32ffef2e2fffec2c2fffe8292effdf242cffcc1421ffbe081fffc50f25ffc70f25ffdd1f2afff03030fff33032ffe32730fdb5091cfda20f23f27f2e342cff00000166373c376d36360e000000000000000000000000000000000000000000000000000000000000000000000000ff000001ff00000100000000c42230a9e81428fdcd1d33f3c6182ff2cf0c25ffd21429ffdd1c29ffe5212dffed2831ffee2a2fffe92730ffd71d2bffc81828ffc41627ffc21525ffc21524ffbf1525ffbc1325ffbc1326ffbe1126ffb90d21ffb90a21ffbf0b23ffc40e26ffc20e26ffc40e26ffe3252effef2d2fffe4262fffaf0c1ffdb30a23ff99182e690000000000000000b62d3f8c792c2c1700000000000000000000000000000000000000000000000000000000000000000000000100000000732e450b00000000bd152a8fe0152bffcf112afec50d27ffc60c26ffd61529ffe6222cffea252fffec242effcf1829ffb30b22ffaa0823ffa90924ffa80b24ffab0c24ffac0b25ffab0924ffad0a23ffb40c24ffbb0d25ffbf0e25ffc30e27ffc20d27ffc10e27ffbd0d25ffc20e26ffe52531ffed2a31ffbc1325fea40a21ffa01026e9003f5f0800020200c32a366bd12331c83f3f3f04000000000000000000000000000000000000000000000000000000007f007f020000000087303f447f30413a00000000b0172fa2db132bffcf112afbb50b24ffc10a24ffd7162affe7212fffe8212dffc91427ffa50622ffa70924feac0923ffad0b23feae0c24feac0b23feae0923feb90c26febf0d27febe0d26febf0c26ffc00e27ffbe0e28ffbd0c25ffbc0d26ffb70d24ffc31228ffe72531ffda1d2dffa80923fdab0924ffa21228ccc22c3a6dd42236bff11f35ffca27328d0000000000000000000000000000000000000000000000000000000000000000ff00000189133a0d9a1b379d8d1c2a12000000009e1228b6d5102bffd0112bfcb10a24ffba0a26ffd7182affe61f2effcf172affa70824ffac0924ffaa0c25ffa70d26feab0e27ffad0d27ffae0e27ffb51228ffbe1128ffbf1129ffbe112affba0f28febb0e26ffbb0d28ffba0c25ffb80e27ffaf0b24ffc51328ffe72130ffba1127ffa10825ffb30c24ffda192dffe01b2affef172affd71f33ea9c3a4e1aff00000100000000000000000000000000000000000000000000000000000000000000008d122e5396102bba00000000484848078f0824d3c40d29ffcf112cfdae0824ffb50b28ffda192dffda1b2fffae0b24ffa50923ffa60b26f98e182d548d222d2d91192d33911a2e31961f3431a1243431a11f2e31a11f3431a62235349a232f2ba6182e90c00c29ffb90e26fbb40d27ffa50824ffc9142affe01d2effa40925ffa30724ffd6172dffdd172afddf1628ffd31d2de1bc32423d00000000ff0000020000000000000000000000000000000000000000000000000000000000000000870f2980980929ed006d48077f163044990626ffb40a27fec8102cffa50725ffb70a27ffe01a32ffc4122affa00723feaa0925ffa30e2ce933669905000000000000000000000000000000000000000000000000000000000000000000000000a8122dc0ba0b26ffb70d28fca40822ffa60825ffcc152bffd2172cff9b0523ffbe112bffd6172dfdde172dffcd1e31c78b39411f00000000ff007f02000000000000000000000000000000000000000000000000000000000000000000000000860b2883a50628ff8f0828cb950727e49c0423ffb10927febf0d2aff960525ffbb0b2affde1731ffaf0925ff9e0623fcac0726ff9a0f29b77f7f7f02ff000003550000037f0000027f000002ff0000027f000002cc00330500000000931a2f6bb80c2cffb40b27fda50823ff950720ffa80927ffd2142dffc6122bffa50823ffcf162efed5142cfecb1b32e574354a1800000000bf003f040000000000000000000000000000000000000000000000000000000000000000000000000000000083122e6d9c0524ff980321ff990422ff950423ffb00928ffb40b2bff8d0324ffbc0e2affce132bffa00524ff9e0623fba80928ff95112b9300000000bf003f04000000000000000000000000000000007f000002000000008b22392ca80e2cf2af0a26fda30a26fe900620ff9c0825ffa80928ffd0142dffbe0e28ffb40c26ffd1132dfcd8142fffb322367600000000cc003305000000000000000000000000000000000000000000000000000000000000000000000000000000000000000074162c2e900725fa930322fc920424fd910324ffaf0a29ffa7092aff8b0123ffbf102bffb60e27ff990522ff9c0523fca00726ff86152f6c000000007f003f04000000000000000000000000000000007f007f026d4848079f1430c6b70a2bff9e0825fe8b0620ff900623ffa10a28ffaa0927ffcc152effb80f28ffbd0f2cffd0112dfec7152ef59b2b3e29ff000001aa005503000000000000000000000000000000000000000000000000000000000000000000000000000000007f00000200010000880a28bc970426ff8f0425fc8f0321ffaa0a2bff980625ff8f0422ffc1102effa10824ff940522ff9a0423ff9a0728ff7d133035000000007f000002000000000000000000000000aa00550300000000901a3758af0c2dff99152fe2880823f98a0421ff970725ff9e0925ffae0a27ffcd142effb70f2affbd102dfdd0102fffbf1732d500aa5503ff00000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f003f040000000083112b6998062aff8e0423fb910524ff9f092aff8b0322ff9e0827ffbd102eff930321ff910422fe980323ff920926f070283319000000007f000002000000000000000000000000ff00550300000000991031aaa10f30d775213355890725fa8c0422fd9a0827ff9b0725ffb00b29ffc9112effbd0f29ffbc0f2afccb0f2ffeaf1735ab00000000ff0000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000aa00550300000000781630448e0628fe8f0124fd930527ff910727ff840221ffa9092affb10b2bff8c0222ff900423fd980325ff8d0a25c500aa5503ff000001000000010000000000000000000000010000000000020000941230d79217345774122b5e950528ff910525fc980726ff960723ffb20d2affc10f2dffbd0e2dffbc0c2cf8c90e30ffa916337d00000000bf003f04000000000000000000000000000000000000000000000000000000000000000000000000000000000000000055000003000000006d132f41880525fe8c0223fe8f0526ff870425ff850323ffb10b2effa00527ff8b0223ff8d0324fa970326fc870e29ad000000007f0000040000000000000000000000000000000100000000007f7f028a1632b562273a0d7f0d29a4970427ff940625fc940524ff940723ffb10c2cffb80c2efdb70b2cfdc10d2dffb61232f39d213f4400000000aa00550300000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f003f04000000007f1731588e0528ff890323fb890423ff840324ff920527ffab0b2eff900323ff8a0323fc8f0124ff970428ff78122c79000000007f003f0400000000000000000000000000000000ff0000010000000076253d673f3f550c830925c4990427ff950626fc920524ff970626feae0b2efbb6092dffb60d2fffa81531aa8c26392800000000ff000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000aa005503000000007e0d2b818f0228ff850223fb840223ff850122ffa6082cff9d072afd84001ffc900121ff8b0626f37f0f2b8062273a0dff000001000000010000000000000000000000000000000000000000ff00000138383809512d361c870827e7920326ff900426fe8f0425fca10729ffb70c30ffa3102dd9961e36550001000000000000ff000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f000002005555037e0b29d08a0226ff850324fd830123ff920427feaf092ffc940425ff870523ff7e0b26b1691f312900000000000000000000000000000000000000000000000000000000000000000000000055000003000000007f1331348e0628ff890223fc880321fc960226ffa60c32f49f1936835b36360e00000000aa0055037f000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000720f2d43870327ff830324fd830325ff850325fda4072cffa8072fff850728d878142b5700010000000000007f0000040000000100000000000000000000000000000000000000000000000000000000aa0000030000000175122d558f0426fb8c0122ff8b0424ff850c2ab684253f300000000000000000aa00550300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000710e3812810f30c385092ceb820224fb820124fca0062effa00b30fa8512308d3f2f2f1000000000ff0000017f0000020000000000000000000000000000000000000000000000000000000000000000000000007f003f04000000007b0e278f970427ff870828d878142b570001000000000000ff0055030000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006d20395d761f37497c0f30aa8e022aff94092dff9b1133bb821e3c3300000000000000007f003f040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000aa00000355555503760c26b27f0d27964b2d3c11000000007f0000027f007f02000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000055000300000000820629e4930b32e28b1a39610002000000000000aa00000300000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a2a2a06572433230000000000000000aa000003000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006822392c7814309870283d1900000000ff0000017f007f020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000aa000003ff00000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
    ScriptBlox = "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000585879170000000000000000000000000000000000000000000000000000000000000000000000000000ff01aa55aa037f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff047f7fff02000000000000000000000000000000000000000000000000000000000000000000000000aaaaff030000ff01897ed55700000000000000000000000000000000000000000000000000000000000000017f7fbf04000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff00ff017f7fff0200000000000000000000000000000000000000000000000000000000ffffff01000000008c80edac00000000000000000000000000000000000000000000000000000001000000000000000091916d078a7fce449688e8709488e76c938ae76d938ae76d938ae76d938ae76d9387e76d9385e76d9185e76d9185e76d9183e76d8e83e76d8e83e76d8e80e76d8e80e76d8e80e76d8e80e76d8e80e76d8e80e76d8e80e76d8e80e76d8e83e76d9385e96d9084e26c857fc72e0000000000000000aa55aa0300000000000000000000000000000000000000007f7fff020000ff017b74b6238e7ff5f40000000000000000000000000000000000000000ffffff01ffffff017f7f3f049286ec6c9183f2d38e7ff9fe9586ffff9787ffff9686ffff9686ffff9686ffff9686ffff9686ffff9685ffff9685ffff9685ffff9685ffff9685ffff9585ffff9685ffff9685ffff9685ffff9685ffff9685ffff9685ffff9685ffff9685ffff9685ffff9586ffff9586ffff8f7ffbfe9082eeb8857fca2c000000007f7fff0200000000000000000000000000000000aaaaff03000000008a7de6889585ffff000000000000000000000000000000000000ff017f7fff02666633058f82e9b29485ffff9384ffff9182ffff8a7bf6f68879f3ef8a7bf4f08a7cf4f08b7df4f08c7df4f08c7df4f08d7ef4f08c7ef5f08d7ef5f08d7ef5f08d7ef5f08e7ff5f08d7ff4f08d7ff4f08d7ff4f08d7ff4f08d7ff4f08d7ff4f08d7ff4f08e7ff4f08d7ef5ef8d7ef5f08b7df5eb8b7cf8f59383ffff8f81f5f19185de3f000000007f7fff0200000000000000007f7f7f02ffffff017a7ab31b8f80f7ed8c7efdfe000000000000000000000000000000007f7fff02000000008d7fe4909484ffff907fffff8d7ef0c88d81dd53867fdd267767c7207f6fc7207f77cf20877fc720877fc7208f7fc7208f87c7208f87cf208f87cf208f87c720978fc720978fc720978fc720978fc720978fc720978fc720978fc720978fc720978fc720978fc7209292c8218f87cf208681c7378f81f3e38d7dfdfb8f80ffff8e80f2e78579aa15ffffff01ffffff01000000007f7fff04000000008d7fe7a49484ffff8b7cfdfc0000000000000000000000007f7fff02000000008b7dca358f80f9fe9080ffff9081efb1484800070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008c7eeaab9383ffff8b7bfcfd8b7bfcfb9585ffff897de284000000007f7fbf047f7fff0400000000897fd74e9282fcff8b7bfcfd8b7cfcfe0000000000000000000000007f7fff04000000008c81eb9a9585ffff8c7ef4ee7f74aa18000000009999cc057f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff029999cc05ffffff01867fd54a9383ffff8c7bfcfd8c7dfdff8d7cfdfd8e7efffe8d7ef4e87575890d0000ff0100000100887fc31e8f81f2e58e7efffe8b7bfcfd8e7fffff0000000000000000000000010000ff01000000018d7fefc29988feff8b7feba600000000aa55ff030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7fff02000000018d7fefb09282fffe8b7cfdfc8c7dfeff8c7dfeff8c7cfffd9181fbfd847ad04d000001005f5f3f088f81efcb9281ffff8c7cfcfb8f80fffe8d80efd500000000000000000000000100000100000000028d7eeac59a89ffff9184f290ff00ff01bf7fff040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff00ff010000000073735c0b8b7eeddb8f7fffff8b7cfbfe8c7dfeff8c7dffff8a7cfdf89c8bffff9182f47700000002897be6b09282ffff8b7cfdfc8b7bfdfd9283feff887bd56300000000000000000000000100000100000000028c7febc49a89ffff9284f29400000000bf7fff040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff01000000006a6a550c8c7feed88f7fffff8c7cfcfb8c7cfdfb8a7cfdfc9384ffff9383fae48b7fd3529082f0bb9485ffff8b7cfffc8c7cfcfd9080fffe8c7df0d47f7fb20a00000000000000000000000100000100000000028c7eebc49a89ffff9587f29300000000bf7fff040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff01000000006a6a550c8d7eedd98f7efffd8d7dffff9586ffff9685ffff9081f0bd887bc8638e82f4d19585ffff8b7cfdfb8c7dfeff8a7cfdfc9584ffff8a7fdf600000000000000000000000000000000100000100000000028c7eebc49a89ffff9589f29300000000bf7fff040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff010000000075754e0d8d80eed79987ffff9285f8e29d8dfd92887ad47f877bdb959181faee9081ffff8b7cfcfc8c7dfeff8b7cfdfd9180ffff8c7fefd26d6d91077f7fff0200000000000000000000000100000100000000028c7cebc49b89ffff9589f29300000000bf7fff0400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff01aa55ff037373730b8d80ead59686f5cf978ade4f9589eb508f80f3cd9483ffff8d7effff8c7cfdfd8c7dfeff8c7cfdfe8c7cfffb9282f9fe8a7fd34600000000aa55ff0300000000000000000000000100000100000000028c7cebc49b89ffff9689f29300000000bf7fff0400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff0100000000000000008077c271867ad88c8f7ff2ce9887ffff9181ffff8b7bfdfc8c7dfdfe8c7dfeff8c7dfeff8b7bfcfc9584ffff8c7ee799000000005555ff030000000000000000000000000000000100000100000000028b7cebc49b89ffff9689f29300000000bf7fff0400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff01000000008d7fe06c9083f4c48d7df8ec9483ffff9182ffff8b7cfdfc8b7cfcfe8c7dfdff8c7dfeff8c7dfeff8b7cfdfd8f80ffff8d7ef2dd877896117f7fff027f007f020000000000000000000000000000000100000100000000028b7cebc49b89ffff9689f29300000000bf7fff04000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7f7f02000000000000ff01000000006d6d91158e7ff5f49484ffff8d7effff8b7bfcfd8c7cfdfd8c7dfeff8c7dfeff8c7dfeff8c7dfeff8b7dfdfe8c7dfffc9081f8fb837bc73c00000000ff7fff02000000000000000000000000000000000000000100000100000000028b7bebc49b89ffff9889f29300000000bf7fff04000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffff0100000000000000007f7fbf0400000000887ddc499181fafd8b7cfcfa8b7dfdfe8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfdff8b7bfdfb9585ffff8d80e273000000007f7fff0400000000000000000000000000000000000000000000000100000100000000028b7bebc49b89ffff9889f29300000000bf7fff04000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007b74a02366667f0a7f7fff0200000100877be07e9585ffff8c7cfdfb8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfeff8b7bfcfb9686ffff8b7ee59d00000000aaaaff03000000000000000000000000000000000000000000000000000000010100010000000002897aeac49c8affff9688f49200000000bf7fff04000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7fff02000000008579ce2a8f82eae07f75c41a00000000000000008d80f0bf9282ffff8c7dfdfc8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfeff8b7bfdfb9483ffff8f80f1ba9f9f9f087f7fff02ffffff01000000000000000000000000000000000000000000000000000000010100010000000002897aeac49c8bffff9185f29100000000bf7fff04000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7fff02000000008b7deab19987ffff8377cf40000000007a7aa3198c7cf1e78e7effff8b7cfdfe8c7dfeff8c7dfeff8c7dfeff8c7dfeff8b7bfdfb9483ffff8d7eeebc66667f0a000001007f7f7f02000000000000000000000000000000000000000000000000000000000000000101000100000000028878eac49b8affff9183ee8e00000000bf7fff040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005555aa03000000007f7ac6368c7ef8fc9483fdfe8f81e694000000008a7fd9449182fdff8b7bfffd8c7dfeff8c7dfeff8c7dfeff8c7dfeff8a7cfcfc9283ffff9080f1d28778b411000000007f7fff0200000000000000000000000000000000000000000000000000000000000000000000000101010100000000028878eac49b8affff8f80ee8b00000000bf7fff04000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000bf7fff04000000008c7fe78c9384ffff8c7dfffe8d7ff2e83f3f0004897be27c9485fffe8b7cfcfc8c7dfeff8c7dfdff8c7dfdff8b7cfdfb9383ffff8e82f2cf7a70a319000000007f7fff020000000000000000000000000000000000000000000000000000000000000000000000000000000101010100000000028878eac49b8bffff9082ee8f00000000bf7fff04000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000001007f7fbf048b7defd09180ffff8a7cfcfa9786ffff8378cd5d8e81f1a69685ffff8b7cfdfc8c7dfeff8c7dfdff8b7bfcfb9484ffff9081f1ce7a70a31900000000ffffff02000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101010100000000028878eac49c8bffff9185f29100000000bf7fff0400000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7f7f02000000007b74ae238e80f8f58c7dffff8c7cfcfe8d7efffe897cf3ed8b7cf4ed8d7fffff8c7dfdfe8c7dfeff8a7bfbfc9686ffff9183f3c97f74aa1800000000aa55aa0300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101010100000000028878eac49c8affff9688f49200000000bf7fff040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000aaaaff03000000008177cf519080fffe8c7cfffd8c7dfeff8b7dfdff8d7effff8e7effff8c7dfeff8c7cfdff8b7cfdfb9484ffff8f81f2b57f79ac2800000000aaaaaa030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101000100000000028979eac59c8affff9689f29300000000bf7fff040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000bf7fff04000000009186ef709685ffff8b7cfdfb8c7dfeff8c7dfeff8b7dfdfe8c7dfdfe8c7cfcfe8b7cfdfc9685ffff887be2998a7cdf819a8af48e7f7f7f02bf7fff040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000100000000038979e9c79b89ffff9889f29300000000bf7fff040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000bf7fff04000000008b7fee7e9686ffff8c7cfdfb8c7dfeff8c7dfeff8c7dfeff8b7cfcfe8b7cfffe9282ffff897ddd9a887cd8929d8cffff9688f49500000000bf7fff040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff0100000000000000068779e9cc9b88ffff9689f29300000000bf7fff0400000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7fff0200000000897ee2a19383ffff8b7cfdfc8c7dfeff8c7dfdff8b7bfcfd8c7dffff9384ffff8e7fe17a000000008a7cf0de9a8afffe968cf48e00000000bf7fff040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff010000000038380009887bead19a88ffff9689f29300000000bf7fff040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff7fff02000000008478e1a39483ffff8b7cfdfc8c7dfeff8b7cfcfc8f7fffff9283f8f58f82e35e000000006d5b7f0e8a7ceed39a8affff978bf48f00000000bf7fff0400000000000000000000000000000000000000000000000000000000000000000000000000000000ff00ff017f7fff02aa55ff037f7fff025b5b5b0e897bebd69988ffff9487f1957f7fff02aa7fff067f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff027f7fff02ffffff02ffffff018477e3a79484ffff8c7cfcfb8c7cfdfb9585ffff9081f3d78b7dcc37000000007f7fff025555550c8b7beed49a8affff978bf48f00000000bf7fff04000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000048480007897cecdc9988ffff9688f0900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009181f3da8e7efdfc8d7dffff9384ffff8f83eaa57f729914000000006666ff05000000005555550c8a7befd49a8affff978bf48f00000000bf7fff04000000000000000000000000000000000000000000000000000000000000000000000000000000007f7f7f0aa19be629a195e6299689eb278f81cd398b7df0e89584ffff9486f1a7a294ff24968be72c9588e629958fe6299b8fdf299b8fe6299b8fe6299b8fe6299b95e629a195e629a396e4279d97ec2a968cea31666600058577d76d8d7ffbfc9484ffff8f81f5e78d7fdb5e00000000000000007f7fff020000ff01000000003f55550c897befd49a8affff978bf48f00000000bf7fff04000000000000000000000000000000000000000000000000000000000000000000000000000000008c7febc89484ffff9082fcff9081fcff8e7ffcff8c7dfeff8b7cfeff8d7ffeff9080fcff9081fcff9081fdff9081fdff9182fdff9182fdff9182fcff9182fbff9081fafe9181fcff9889ffff9686faf88c81d7a08b7ddfa39786ffff9182ffff9082eca6887fc31e000000007f7fff02ffffff01000000000000ff01000000003f3f3f0c897beed49a8affff978bf48f00000000bf7fff04000000000000000000000000000000000000000000000000000000000000000000000000000000009585ffff8a7afeff8a7cfeff8b7cfeff8b7dfeff8c7dfeff8c7dfeff8b7dfeff8b7cfeff8b7cfeff8b7cfdff8b7cfeff8b7cfeff8a7bfcfe8b7afcfd8c7cffff9181ffff8d7dfbfc8b7ceec78278d2898f81efc59080faf98779e2b6887dd2450000000000000000aaaaff030000000000000000000000000000ff01000000003f3f550c897aeed49a8affff978bf48f00000000bf7fff04000000000000000000000000000000000000000000000000000000000000000000000000000000008e80f0e28e7effff8c7cfdfe8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfeff8b7dfcfe8c7cfdfd8e7effff9182ffff8e81faef8e7feabe8a7fdb9c8d7fe1b68e80f2d38b7ee5bb867cd39a8a7edeb68f7fbf10ff7fff02aaaaff03000000000000000000000000000000000000ff01000000004e4e620d897aecd49a8affff988cf48e00000000bf7fff0400000000000000000000000000000000000000000000000000000000000000000000000000000000897be8ac9283fffe8b7dfdfc8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfeff8b7cfeff8e7fffff9180ffff8c7ef1ea8c7fdcb2847ac48b8c7fd288897bd8a5877cdb9e857bd3978d7febc48d7efcfa9988ffff897cd250ff00ff01aaaaff03000000000000000000000000000000000000ff010000ff011f1f00088678ebd49b8bfffe9789f29200000000bf7fff04000000000000000000000000000000000000000000000000000000000000000000000000000000008879d5699182ffff8b7bfcfd8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfeff8b7cfcfe907ffeff8a7beed6887fc28c7d77a77e7d74ba8a887ddba48577d8a68a7cebc08a7df3e09181ffff9282ffff8b7cfdfc9282fffd8d7fecb8000000009999ff05ffffff010000000000000000000000007f7fff0400000000877dcd338c7ef8f69283ffff8a7ed465000000007f7fbf04000000000000000000000000000000000000000000000000000000000000000000000000000000008b7fb9168d7ef2e58e7efffe8c7cfdfd8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfdff8e7efeff8b7df8ef8a7df3db8b7cf6ed8c7cfbf98d7effff9180ffff9383ffff8f80ffff8a7cfdfe8c7cfdfd8c7dfdff8b7bfffd9182fdff877ad56200000000000000007f7fff047f7fff04ffaaff0300000000555500038e82f0be9383ffff8c7df3ea7979b61500000100007f7f0200000000000000000000000000000000000000000000000000000000000000000000000000000000000000008f82e15e9888ffff8b7cfdfb8b7cfcfe8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfeff8c7dfdff8e7effff9080ffff8e7effff8d7dffff8c7cfdff8b7bfdfd8c7cfcfd8c7dfdfe8c7dfeff8c7dfeff8c7dfdff8c7cfdfe8c7dfdfe8d7ff7fa8d80e1798888aa0f000000000000000000000000837baf1d8e80eeae9080ffff9585ffff8c80e07f00000000aaaaff030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000aaaaff0300000000897be57a9687ffff8d7dffff8b7cfdfc8b7cfcfe8c7cfeff8c7dfdfe8c7dfdfe8c7dfdfe8c7dfcfe8c7cfdfd8b7dfcfe8c7dfcfe8c7dfcfe8c7dfdfe8c7dfdfe8c7dfdfe8c7dfdfe8c7dfdfe8c7dfdfe8c7dfdff8b7dfcfe8c7dfdfe9384ffff8f80f2e08e7fed9e8577e58b8e80f0ad8c7ff4ea9282ffff9584ffff9081eebf9999b20a7f7fff020000ff01000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000aa55ff03000000009183e96b9283f8ec9283ffff9080ffff8d7dffff8d7effff8d7dffff8d7dffff8c7dffff8c7dffff8c7dffff8c7dffff8d7dffff8d7dffff8d7dffff8d7dffff8d7dffff8d7dffff8d7dffff8c7dffff8d7effff8d7dffff8b7bffff8f7fffff9685ffff9988ffff9888ffff9283ffff9081f8f68d81e78e7f7f990a00000100ffffff0100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7fff0200000000877fb7209082e27f8d7feac88e80eeeb8e81edea8e81eeeb8e81eeeb8e81eeeb8e81eeeb8e81eeeb8e81eeeb8e81eeeb8e81eeeb8e81eeeb8e81eeeb8e81eeeb8e81eeeb8e81eeeb8e81eeeb8e81efea8e81eee98e81eeeb8e81edea8d7fece08678e5bc8b7de6b98d7fea94847ac4340000000000000000ffffff0100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
})

local providers = table.freeze({
    {Name = "RScripts", AssetAttribute = "RScriptsLogo", Source = "upload:rscripts"},
    {Name = "HaxHell", AssetAttribute = "HaxHellLogo", Source = "upload:haxhell"},
    {Name = "ScriptBlox", AssetAttribute = "ScriptBloxLogo", Source = "upload:scriptblox"},
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

local embeddedLogoCache = {}
local logoSize = Vector2.new(48, 48)

local function applyProviderImage(label, provider)
    local configured = script and assetUri(script:GetAttribute(provider.AssetAttribute)) or ""
    local direct = configured ~= "" and configured or assetUri(LogoAssets[provider.Name])
    if direct ~= "" then
        label.Image = direct
        return
    end
    local image = embeddedLogoCache[provider.Name]
    local ok, err = pcall(function()
        if not image then
            local pixels = buffer.create(48 * 48 * 4)
            local encoded = EmbeddedLogos[provider.Name]
            for i = 0, buffer.len(pixels) - 1 do
                buffer.writeu8(pixels, i, tonumber(string.sub(encoded, i * 2 + 1, i * 2 + 2), 16))
            end
            image = AssetService:CreateEditableImage({Size = logoSize})
            assert(image, "EditableImage memory budget exceeded")
            embeddedLogoCache[provider.Name] = image
            image:WritePixelsBuffer(Vector2.zero, logoSize, pixels)
        end
        label.ImageContent = Content.fromObject(image)
    end)
    if not ok then
        if image then
            image:Destroy()
            embeddedLogoCache[provider.Name] = nil
        end
        warn("ScriptFinder: " .. provider.Name .. " logo: " .. tostring(err))
    end
end

for index, provider in ipairs(providers) do
    local logo = create("ImageLabel", {
        Name = provider.Name,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(3 + (index - 1) * 40 + 9, 8),
        Size = UDim2.fromOffset(22, 22),
        ScaleType = Enum.ScaleType.Fit,
        BorderSizePixel = 0,
        ZIndex = 6,
    }, selector)
    applyProviderImage(logo, provider)
    if script then
        bind(script:GetAttributeChangedSignal(provider.AssetAttribute), function()
            applyProviderImage(logo, provider)
        end)
    end
end

bind(gui.Destroying, function()
    for _, image in pairs(embeddedLogoCache) do
        image:Destroy()
    end
    table.clear(embeddedLogoCache)
end)

local selectorInput = create("TextButton", {
    Name = "Input",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    Text = "",
    AutoButtonColor = false,
    ZIndex = 7,
}, selector)

local selectedProvider = 3
local selectorGesture = nil
local selectorTween = nil
local page = 1
local totalPages
local changePage

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
    lucideIcon(button, direction < 0 and "arrow-left" or "arrow-right", 18, Theme.Text, 6)
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
        if changePage then
            changePage(direction)
        end
    end)
    return button
end

local previousPageButton = pageControl("PreviousPage", 0, -1)
local nextPageButton = pageControl("NextPage", 86, 1)

local pageLabel = create("TextLabel", {
    Name = "PageNumber",
    Position = UDim2.fromOffset(30, 0),
    Size = UDim2.fromOffset(56, 38),
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = Theme.Text,
    FontFace = Theme.Font,
    TextSize = 11,
    TextScaled = true,
    ZIndex = 5,
}, navigation)
create("UITextSizeConstraint", {MinTextSize = 7, MaxTextSize = 11}, pageLabel)

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

local searchIcon = lucideIcon(searchIconButton, "search", 18, Theme.Accent, 6)

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

local function shortcut(name, labelWidth, iconName)
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
    local icon = lucideIcon(button, iconName, 18, Theme.Text, 6)
    icon.Visible = false
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

local favoriteShortcut = shortcut("Favorites", 74, "star")
local gameShortcut = shortcut("Game", 50, "gamepad-2")

local results = create("Frame", {
    Name = "Results",
    Position = UDim2.fromOffset(14, 62),
    Size = UDim2.new(1, -28, 1, -88),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
    BorderSizePixel = 0,
    ZIndex = 2,
}, content)

local attribution = create("TextLabel", {
    Name = "Attribution",
    Position = UDim2.new(0, 14, 1, -22),
    Size = UDim2.new(1, -28, 0, 16),
    BackgroundTransparency = 1,
    Text = "Powered by ScriptBlox.com",
    TextColor3 = Theme.Text:Lerp(Theme.Window, 0.46),
    FontFace = Theme.Font,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Right,
    ZIndex = 3,
}, content)

local feedback = create("TextButton", {
    Name = "CatalogueFeedback",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.new(1, -24, 0, 44),
    BackgroundColor3 = Theme.Window,
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = Theme.Text:Lerp(Theme.Window, 0.3),
    FontFace = Theme.Font,
    TextSize = 12,
    TextWrapped = true,
    AutoButtonColor = false,
    Visible = false,
    ZIndex = 5,
}, results)
round(feedback, 8)

local activePageView, outgoingPageView, retryPage
local generation, loading, hasLoaded = 0, false, false
local pageMotion = {}
local activeCards = {}
local displayedPage
local lastCatalogueRequest = -math.huge

local function clearPageMotion()
    for _, tween in ipairs(pageMotion) do
        tween:Cancel()
    end
    table.clear(pageMotion)
    if outgoingPageView then
        outgoingPageView:Destroy()
        outgoingPageView = nil
    end
    if activePageView then
        activePageView.Position = UDim2.fromOffset(0, 0)
    end
end

local function updatePagination()
    local enabled = selectedProvider == 3
    pageLabel.Visible = enabled
    attribution.Visible = enabled
    results.Visible = enabled
    pageLabel.Text = totalPages and (tostring(page) .. "/" .. tostring(totalPages)) or ""
    local previousEnabled = enabled and not loading and page > 1
    local nextEnabled = enabled and not loading and totalPages ~= nil and page < totalPages
    for _, item in ipairs({{previousPageButton, previousEnabled}, {nextPageButton, nextEnabled}}) do
        local button, available = item[1], item[2]
        button.Active = available
        local icon = button:FindFirstChild("Icon")
        if icon then
            icon.ImageTransparency = available and 0 or 0.6
        end
    end
end

local function formatCounter(n)
    if n == nil then
        return "—"
    end
    local scales = {{1e12, "T"}, {1e9, "B"}, {1e6, "M"}, {1e3, "K"}}
    for _, scale in ipairs(scales) do
        if n >= scale[1] then
            local value = n / scale[1]
            if value >= 100 then
                return string.format("%d%s", math.floor(value + 0.5), scale[2])
            end
            return string.format("%.1f", value):gsub("%.0$", "") .. scale[2]
        end
    end
    return tostring(n)
end

local function makeCard(scroller, item, index)
    local card = create("Frame", {
        Name = "ScriptCard",
        LayoutOrder = index,
        BackgroundColor3 = Theme.Raised,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 3,
    }, scroller)
    round(card, 8)
    local image = create("ImageLabel", {
        Name = "Thumbnail",
        Size = UDim2.new(1, 0, 1, -48),
        BackgroundColor3 = Theme.Window,
        BorderSizePixel = 0,
        Image = item.thumbnail,
        ScaleType = Enum.ScaleType.Crop,
        ZIndex = 4,
    }, card)
    round(image, 8)
    local pill = create("Frame", {
        Name = "Metrics",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 6, 1, -6),
        Size = UDim2.fromOffset(0, 22),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Window,
        BackgroundTransparency = 0.12,
        BorderSizePixel = 0,
        ZIndex = 5,
    }, image)
    round(pill, 11)
    create("UIPadding", {PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6)}, pill)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
    }, pill)
    local counters = {}
    for i, metric in ipairs({{"views", "eye"}, {"executions", "play"}, {"likes", "thumbs-up"}}) do
        local cell = create("Frame", {
            Name = metric[1],
            Size = UDim2.fromOffset(0, 22),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            LayoutOrder = i,
            ZIndex = 6,
        }, pill)
        local icon = lucideIcon(cell, metric[2], 12, Theme.Text, 7)
        icon.AnchorPoint = Vector2.new(0, 0.5)
        icon.Position = UDim2.new(0, 0, 0.5, 0)
        local label = create("TextLabel", {
            Name = "Count",
            Position = UDim2.fromOffset(15, 0),
            Size = UDim2.fromOffset(0, 22),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            TextColor3 = Theme.Text,
            FontFace = Theme.Font,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = formatCounter(item[metric[1]]),
            ZIndex = 7,
        }, cell)
        counters[metric[1]] = label
    end
    local title = create("TextLabel", {
        Name = "Title",
        Position = UDim2.new(0, 10, 1, -44),
        Size = UDim2.new(1, -20, 0, 40),
        BackgroundTransparency = 1,
        Text = item.title,
        TextColor3 = Theme.Text,
        FontFace = Theme.Font,
        TextSize = 13,
        TextScaled = false,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        BorderSizePixel = 0,
        ZIndex = 4,
    }, card)
    return {card = card, image = image, title = title, counters = counters}
end

local function reconcileCards(scroller, items)
    local retained = {}
    for index, item in ipairs(items) do
        if not retained[item.id] then
            retained[item.id] = true
            local view = activeCards[item.id]
            if not view then
                view = makeCard(scroller, item, index)
                activeCards[item.id] = view
            else
                if view.card.LayoutOrder ~= index then
                    view.card.LayoutOrder = index
                end
                if view.image.Image ~= item.thumbnail then
                    view.image.Image = item.thumbnail
                end
                if view.title.Text ~= item.title then
                    view.title.Text = item.title
                end
                for name, label in pairs(view.counters) do
                    local value = formatCounter(item[name])
                    if label.Text ~= value then
                        label.Text = value
                    end
                end
            end
        end
    end
    for id, view in pairs(activeCards) do
        if not retained[id] then
            view.card:Destroy()
            activeCards[id] = nil
        end
    end
end

local function makePage(items)
    local group = create("Frame", {
        Name = "Page",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 2,
    }, results)
    local scroller = create("ScrollingFrame", {
        Name = "Cards",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Theme.Divider,
        VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
        ZIndex = 2,
    }, group)
    local grid = create("UIGridLayout", {
        CellPadding = UDim2.fromOffset(10, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        VerticalAlignment = Enum.VerticalAlignment.Top,
    }, scroller)
    local function layoutCards()
        local width = math.max(0, scroller.AbsoluteSize.X - 5)
        local columns = math.max(1, math.min(6, math.floor((width + 10) / 180)))
        local cellWidth = math.max(1, math.floor((width - (columns - 1) * 10) / columns))
        grid.CellSize = UDim2.fromOffset(cellWidth, math.floor(cellWidth * 9 / 16) + 48)
        grid.FillDirectionMaxCells = columns
    end
    scroller:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutCards)
    layoutCards()
    table.clear(activeCards)
    reconcileCards(scroller, items)
    return group
end

local function presentPage(items, direction, target)
    if activePageView and displayedPage == target then
        reconcileCards(activePageView.Cards, items)
        return
    end
    clearPageMotion()
    local old = activePageView
    local incoming = makePage(items)
    activePageView = incoming
    displayedPage = target
    if not old or direction == 0 then
        if old then
            old:Destroy()
        end
        incoming.Position = UDim2.fromOffset(0, 0)
        return
    end
    incoming.Position = UDim2.fromScale(direction, 0)
    local info = TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    local show = TweenService:Create(incoming, info, {Position = UDim2.fromOffset(0, 0)})
    table.insert(pageMotion, show)
    outgoingPageView = old
    local hide = TweenService:Create(old, info, {Position = UDim2.fromScale(-direction, 0)})
    table.insert(pageMotion, hide)
    hide.Completed:Once(function()
        if outgoingPageView == old then
            outgoingPageView = nil
            old:Destroy()
        end
    end)
    hide:Play()
    show:Play()
end

local function loadCatalogue(target, direction)
    if not alive or selectedProvider ~= 3 or loading or target < 1 or (totalPages and target > totalPages) then
        return
    end
    generation += 1
    local token = generation
    loading = true
    retryPage = nil
    feedback.Visible = not activePageView
    feedback.BackgroundTransparency = 1
    feedback.Text = "Loading..."
    updatePagination()
    task.spawn(function()
        lastCatalogueRequest = os.clock()
        local ok, data = pcall(function()
                local remote = ReplicatedStorage:FindFirstChild(CatalogRemote)
                if RunService:IsStudio() then
                    remote = remote or ReplicatedStorage:WaitForChild(CatalogRemote, 8)
                    if not remote or not remote:IsA("RemoteFunction") then
                        error("Studio requires the ScriptFinderCatalog server script and HTTP requests enabled", 0)
                    end
                    return remote:InvokeServer(target)
                end
                if remote and remote:IsA("RemoteFunction") then
                    return remote:InvokeServer(target)
                end
                return fetchCatalogue(target)
            end)
        if not alive or token ~= generation or selectedProvider ~= 3 then
            return
        end
        loading = false
        if not ok or type(data) ~= "table" or type(data.items) ~= "table" or type(data.totalPages) ~= "number" then
            retryPage = target
            local reason = not ok and tostring(data) or (type(data) == "table" and data.error or "Invalid catalogue response")
            reason = tostring(reason):gsub("[%c]", " ")
            warn("ScriptFinder catalogue: " .. reason)
            feedback.Text = "ScriptBlox: " .. string.sub(reason, 1, 180)
            feedback.Visible = true
            feedback.BackgroundTransparency = activePageView and 0.1 or 1
            updatePagination()
            return
        end
        totalPages = math.max(1, math.floor(data.totalPages))
        if target > totalPages then
            updatePagination()
            loadCatalogue(totalPages, -1)
            return
        end
        page = target
        hasLoaded = true
        gui:SetAttribute("Page", page)
        gui:SetAttribute("TotalPages", totalPages)
        feedback.Visible = #data.items == 0
        feedback.Text = #data.items == 0 and "No scripts on this page." or ""
        presentPage(data.items, direction, target)
        updatePagination()
    end)
end

changePage = function(direction)
    if totalPages and not loading then
        loadCatalogue(page + direction, direction)
    end
end

bind(feedback.Activated, function()
    if retryPage then
        loadCatalogue(retryPage, retryPage > page and 1 or -1)
    end
end)

local function switchCatalogue()
    generation += 1
    loading, hasLoaded, retryPage = false, false, nil
    clearPageMotion()
    if activePageView then
        activePageView:Destroy()
        activePageView = nil
    end
    table.clear(activeCards)
    displayedPage = nil
    page, totalPages = 1, nil
    feedback.Visible = false
    gui:SetAttribute("Page", 1)
    gui:SetAttribute("TotalPages", nil)
    updatePagination()
    if selectedProvider == 3 then
        loadCatalogue(1, 0)
    end
end

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
    local top = row + 50
    results.Position = UDim2.fromOffset(14, top)
    results.Size = UDim2.new(1, -28, 1, -top - 26)
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
    local changed = selectedProvider ~= nextProvider
    selectedProvider = nextProvider
    gui:SetAttribute("Provider", providers[selectedProvider].Name)
    if changed then
        switchCatalogue()
    end
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
    if selectedProvider == 3 and not loading then
        loadCatalogue(page, 0)
    end
end)

bind(UserInputService.WindowFocused, function()
    if alive and mode ~= "dot" and mode ~= "closed" and selectedProvider == 3 and not loading and os.clock() - lastCatalogueRequest >= 2 then
        loadCatalogue(page, 0)
    end
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
    generation += 1
    for _, tween in ipairs(pageMotion) do
        tween:Cancel()
    end
    table.clear(pageMotion)
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

selectProvider(selectedProvider, false)
updatePagination()
render()
