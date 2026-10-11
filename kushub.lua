--[[
    kus;hub  ·  UI library  ·  v1.0.0
    1:1 rebuild of the kus;hub mockup for Roblox executors.

    Everything is laid out in the mockup's own pixel space (1671 x 941) and then
    scaled with a UIScale, so the proportions always match the screenshot.
    Pass `Scale = 0.6` (default) to CreateWindow to make it bigger / smaller.
    The window auto-shrinks if it would not fit on your screen (phones).

    All icons are drawn out of frames, so no asset ids are needed.
    You can still pass "rbxassetid://123" as an icon to AddTab to use your own.
]]

local cloneref = cloneref or function(o) return o end
local function Service(name) return cloneref(game:GetService(name)) end

local Players      = Service("Players")
local UIS          = Service("UserInputService")
local TweenService = Service("TweenService")
local CoreGui      = Service("CoreGui")
local Workspace    = Service("Workspace")

local Library = {
    Version = "1.0.0",
    Flags   = {},
    Options = {},
    Icons   = {},
    Windows = {},
}

--// ───────────────────────────── theme ─────────────────────────────
local Theme = {
    Window        = Color3.fromRGB(10, 10, 18),
    Topbar        = Color3.fromRGB(12, 12, 21),
    Sidebar       = Color3.fromRGB(11, 11, 19),
    Section       = Color3.fromRGB(13, 13, 22),
    Control       = Color3.fromRGB(10, 10, 17),
    Border        = Color3.fromRGB(28, 28, 43),
    ControlBorder = Color3.fromRGB(42, 42, 60),
    Divider       = Color3.fromRGB(21, 21, 33),
    Accent        = Color3.fromRGB(236, 72, 153),
    AccentLight   = Color3.fromRGB(248, 128, 190),
    Text          = Color3.fromRGB(214, 214, 228),
    TextBright    = Color3.fromRGB(255, 255, 255),
    TextDim       = Color3.fromRGB(150, 150, 172),
    TextTab       = Color3.fromRGB(178, 178, 198),
    Muted         = Color3.fromRGB(104, 104, 128),
    ToggleOff     = Color3.fromRGB(38, 38, 56),
    KnobOff       = Color3.fromRGB(146, 146, 168),
    Track         = Color3.fromRGB(38, 38, 56),
    IconIdle      = Color3.fromRGB(214, 82, 148),
    IconActive    = Color3.fromRGB(248, 168, 205),
    Blue          = Color3.fromRGB(125, 190, 255),
}
Library.Theme = Theme

local LogoSeq = ColorSequence.new({
    ColorSequenceKeypoint.new(0,    Color3.fromRGB(245, 105, 175)),
    ColorSequenceKeypoint.new(0.55, Color3.fromRGB(196, 150, 255)),
    ColorSequenceKeypoint.new(1,    Color3.fromRGB(120, 195, 255)),
})

local COLUMN_WIDTHS = { 641, 668 } -- left / right column (mockup px)
local ROW_H, HEAD_H = 52, 46
local FULL = UDim.new(1, 0)

--// ───────────────────────────── helpers ─────────────────────────────
local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }

local function New(class, props)
    local inst = Instance.new(class)
    if inst:IsA("GuiObject") then
        inst.BorderSizePixel = 0
        if inst:IsA("GuiButton") then inst.AutoButtonColor = false end
        if TEXT_CLASSES[class] then
            inst.BackgroundTransparency = 1
            inst.Font = Enum.Font.GothamMedium
            inst.TextSize = 19
            inst.TextColor3 = Theme.Text
            inst.Text = ""
        end
    end
    local parent
    for k, v in pairs(props) do
        if k == "Parent" then parent = v else inst[k] = v end
    end
    inst.Parent = parent
    return inst
end

local function Corner(inst, r)
    return New("UICorner", { CornerRadius = (typeof(r) == "UDim") and r or UDim.new(0, r), Parent = inst })
end

local function Stroke(inst, color, thickness, transparency)
    return New("UIStroke", {
        Color = color, Thickness = thickness or 1, Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = inst,
    })
end

local function Tween(inst, props, t)
    local tw = TweenService:Create(inst, TweenInfo.new(t or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function Safe(fn, ...)
    if type(fn) == "function" then task.spawn(fn, ...) end
end

--// ───────────────────────────── icons ─────────────────────────────
-- every icon is drawn in a 40x40 box out of frames / strokes
local function DefineIcon(name, draw)
    Library.Icons[name] = function(parent, size, color)
        local holder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), Parent = parent })
        local canvas = New("Frame", {
            BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(40, 40), Parent = holder,
        })
        New("UIScale", { Scale = size / 40, Parent = canvas })

        local parts = {}
        local d = {}

        -- cx, cy = centre; w, h = OUTER size (stroke included)
        function d.shape(cx, cy, w, h, o)
            o = o or {}
            local s = o.stroke or 0
            local f = New("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromOffset(cx, cy),
                Size = UDim2.fromOffset(math.max(w - 2 * s, 0), math.max(h - 2 * s, 0)),
                BackgroundTransparency = o.fill and 0 or 1,
                BackgroundColor3 = color,
                Rotation = o.rot or 0,
                ClipsDescendants = o.clip or false,
                Parent = o.parent or canvas,
            })
            if o.round then Corner(f, o.round == true and FULL or UDim.new(0, o.round)) end
            local part = { inst = f, fill = o.fill }
            if s > 0 then part.stroke = Stroke(f, color, s) end
            if o.fill or s > 0 then table.insert(parts, part) end
            return f
        end

        function d.line(x1, y1, x2, y2, t)
            local dx, dy = x2 - x1, y2 - y1
            return d.shape((x1 + x2) / 2, (y1 + y2) / 2, math.sqrt(dx * dx + dy * dy) + t, t, {
                fill = true, round = true, rot = math.deg(math.atan2(dy, dx)),
            })
        end

        function d.poly(pts, t, closed)
            local n = #pts
            for i = 1, closed and n or (n - 1) do
                local a, b = pts[i], pts[i % n + 1]
                d.line(a[1], a[2], b[1], b[2], t)
            end
        end

        draw(d)

        local icon = { Holder = holder }
        function icon:SetColor(c)
            for _, p in ipairs(parts) do
                if p.fill then p.inst.BackgroundColor3 = c end
                if p.stroke then p.stroke.Color = c end
            end
        end
        icon:SetColor(color)
        return icon
    end
end

DefineIcon("eye", function(d)
    d.shape(20, 20, 38, 22, { stroke = 3, round = true })
    d.shape(20, 20, 12, 12, { fill = true, round = true })
end)

DefineIcon("user", function(d)
    d.shape(20, 11, 15, 15, { stroke = 3, round = true })
    local clip = d.shape(20, 33, 40, 14, { clip = true })
    d.shape(20, 13, 30, 26, { stroke = 3, round = 10, parent = clip })
end)

DefineIcon("crosshair", function(d)
    d.shape(20, 20, 26, 26, { stroke = 3, round = true })
    d.shape(20, 20, 6, 6, { fill = true, round = true })
    d.line(20, 2, 20, 9, 3)
    d.line(20, 31, 20, 38, 3)
    d.line(2, 20, 9, 20, 3)
    d.line(31, 20, 38, 20, 3)
end)

DefineIcon("globe", function(d)
    d.shape(20, 20, 36, 36, { stroke = 3, round = true })
    d.shape(20, 20, 16, 36, { stroke = 3, round = true })
    d.shape(20, 20, 36, 3, { fill = true })
end)

DefineIcon("grid", function(d)
    for _, x in ipairs({ 9, 20, 31 }) do
        for _, y in ipairs({ 9, 20, 31 }) do
            d.shape(x, y, 8, 8, { fill = true, round = 2 })
        end
    end
end)

DefineIcon("shirt", function(d)
    d.poly({
        { 15, 5 }, { 5, 10 }, { 7.5, 18 }, { 12.5, 16 }, { 12.5, 35 }, { 27.5, 35 },
        { 27.5, 16 }, { 32.5, 18 }, { 35, 10 }, { 25, 5 }, { 22, 8 }, { 18, 8 },
    }, 3, true)
end)

DefineIcon("save", function(d)
    d.shape(20, 20, 32, 32, { stroke = 3, round = 5 })
    d.shape(18, 12, 12, 8, { stroke = 2.5 })
    d.shape(20, 27, 20, 10, { stroke = 2.5, round = 1 })
end)

DefineIcon("search", function(d)
    d.shape(17, 17, 24, 24, { stroke = 3.5, round = true })
    d.line(27, 27, 35, 35, 4)
end)

DefineIcon("chevron", function(d)
    d.line(9, 15, 20, 26, 3.5)
    d.line(31, 15, 20, 26, 3.5)
end)

DefineIcon("close", function(d)
    d.line(8, 8, 32, 32, 4)
    d.line(32, 8, 8, 32, 4)
end)

DefineIcon("minimize", function(d)
    d.line(6, 20, 34, 20, 4)
end)

local function MakeIcon(parent, icon, size, color)
    if type(icon) == "string" and Library.Icons[icon] then
        return Library.Icons[icon](parent, size, color)
    end
    if icon then
        local img = New("ImageLabel", {
            BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size),
            Image = tostring(icon), ImageColor3 = color, Parent = parent,
        })
        local obj = { Holder = img }
        function obj:SetColor(c) img.ImageColor3 = c end
        return obj
    end
    return Library.Icons.grid(parent, size, color)
end

-- the circular "K" logo
local function MakeLogo(parent, d)
    local holder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(d, d), Parent = parent })
    local t = math.max(3, d * 0.06)
    local ring = New("Frame", {
        BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(d - 2 * t, d - 2 * t), Parent = holder,
    })
    Corner(ring, FULL)
    local st = Stroke(ring, Color3.new(1, 1, 1), t)
    New("UIGradient", { Color = LogoSeq, Rotation = 45, Parent = st })
    local k = New("TextLabel", {
        Text = "K", Font = Enum.Font.GothamBold, TextSize = math.floor(d * 0.62),
        TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), Parent = holder,
    })
    New("UIGradient", { Color = LogoSeq, Rotation = 55, Parent = k })
    return holder
end

--// ───────────────────────────── sections ─────────────────────────────
local Section = {}
Section.__index = Section

function Section:_row(text)
    self._n = self._n + 1
    local row = New("Frame", {
        Name = text, Size = UDim2.new(1, 0, 0, ROW_H), BackgroundTransparency = 1,
        LayoutOrder = self._n, Parent = self.Frame,
    })
    if self._n > 1 then
        New("Frame", { Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = Theme.Divider, Parent = row })
    end
    New("TextLabel", {
        Name = "Label", Text = text, Position = UDim2.fromOffset(21, 0), Size = UDim2.new(0.5, 0, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left, Parent = row,
    })
    return row
end

function Section:_register(el, row, text)
    el.Row = row
    el.Search = string.lower(text or "")
    table.insert(self.Elements, el)
end

-- the "···" button next to every setting
function Section:_dots(row, fromRight, el, hasKey)
    local btn = New("TextButton", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -fromRight, 0.5, 0),
        Size = UDim2.fromOffset(44, 36), Parent = row,
    })
    local dots = {}
    for i = -1, 1 do
        local dot = New("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, i * 10, 0.5, 0),
            Size = UDim2.fromOffset(4, 4), BackgroundColor3 = Theme.Muted, Parent = btn,
        })
        Corner(dot, FULL)
        table.insert(dots, dot)
    end
    local function paint(c) for _, dot in ipairs(dots) do dot.BackgroundColor3 = c end end
    el._paintDots = paint
    btn.MouseEnter:Connect(function() paint(Theme.TextDim) end)
    btn.MouseLeave:Connect(function() paint(el._listening and Theme.Accent or Theme.Muted) end)
    btn.Activated:Connect(function()
        local items = {}
        if hasKey then
            table.insert(items, {
                Text = "Keybind: " .. (el.Key and el.Key.Name or "None"),
                Callback = function() el:ListenKey() end,
            })
        end
        table.insert(items, { Text = "Reset to default", Callback = function() el:Set(el.Default) end })
        self.Window._togglePopup(btn, items, { Width = 190, Center = true })
    end)
    return btn
end

function Section:AddToggle(flag, o)
    o = o or {}
    local text = o.Text or flag
    local row = self:_row(text)
    local el = {
        Type = "Toggle", Flag = flag, Value = o.Default == true, Default = o.Default == true,
        Callback = o.Callback, _changed = {},
    }

    local sw = New("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -22, 0.5, 0),
        Size = UDim2.fromOffset(52, 27), BackgroundTransparency = 0, BackgroundColor3 = Theme.ToggleOff, Parent = row,
    })
    Corner(sw, FULL)
    local knob = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(21, 21), BackgroundColor3 = Theme.KnobOff, Parent = sw,
    })
    Corner(knob, FULL)

    local function render(animate)
        local on = el.Value
        local bg = on and Theme.Accent or Theme.ToggleOff
        local kc = on and Color3.new(1, 1, 1) or Theme.KnobOff
        local pos = UDim2.new(0, on and 28 or 3, 0.5, 0)
        if animate then
            Tween(sw, { BackgroundColor3 = bg })
            Tween(knob, { Position = pos, BackgroundColor3 = kc })
        else
            sw.BackgroundColor3, knob.Position, knob.BackgroundColor3 = bg, pos, kc
        end
    end

    function el:Set(v, silent)
        v = v and true or false
        self.Value = v
        Library.Flags[flag] = v
        render(true)
        if not silent then
            Safe(self.Callback, v)
            for _, f in ipairs(self._changed) do Safe(f, v) end
        end
    end
    function el:OnChanged(f) table.insert(self._changed, f) end
    function el:SetKey(k)
        self.Key = k
        self._listening = false
        if self._paintDots then self._paintDots(Theme.Muted) end
    end
    function el:ListenKey()
        self._listening = true
        self.Window._listening = self
        if self._paintDots then self._paintDots(Theme.Accent) end
    end
    el.Window = self.Window

    sw.Activated:Connect(function() el:Set(not el.Value) end)
    self:_dots(row, 22 + 52 + 60, el, true)
    self:_register(el, row, text)

    render(false)
    Library.Flags[flag] = el.Value
    Library.Options[flag] = el
    table.insert(self.Window.Toggles, el)
    return el
end

function Section:AddDropdown(flag, o)
    o = o or {}
    local text = o.Text or flag
    local values = o.Values or {}
    local row = self:_row(text)
    local el = {
        Type = "Dropdown", Flag = flag, Values = values, Value = o.Default or values[1],
        Callback = o.Callback, _changed = {},
    }
    el.Default = el.Value

    local width = math.floor(self.Width * 0.32)
    local btn = New("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.5, 0),
        Size = UDim2.fromOffset(width, 40), BackgroundTransparency = 0, BackgroundColor3 = Theme.Control, Parent = row,
    })
    Corner(btn, 4)
    local st = Stroke(btn, Theme.ControlBorder, 2)
    local valueLabel = New("TextLabel", {
        Text = tostring(el.Value or ""), Position = UDim2.fromOffset(15, 0), Size = UDim2.new(1, -46, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.TextBright, Parent = btn,
    })
    local chev = MakeIcon(btn, "chevron", 18, Theme.Text)
    chev.Holder.AnchorPoint = Vector2.new(0.5, 0.5)
    chev.Holder.Position = UDim2.new(1, -22, 0.5, 0)

    btn.MouseEnter:Connect(function() st.Color = Color3.fromRGB(78, 78, 108) end)
    btn.MouseLeave:Connect(function() st.Color = Theme.ControlBorder end)

    function el:Set(v, silent)
        self.Value = v
        valueLabel.Text = tostring(v or "")
        Library.Flags[flag] = v
        if not silent then
            Safe(self.Callback, v)
            for _, f in ipairs(self._changed) do Safe(f, v) end
        end
    end
    function el:OnChanged(f) table.insert(self._changed, f) end
    function el:SetValues(list, keep)
        self.Values = list
        if not keep then self:Set(list[1], true) end
    end

    btn.Activated:Connect(function()
        local items = {}
        for _, v in ipairs(el.Values) do
            table.insert(items, { Text = tostring(v), Selected = (v == el.Value), Callback = function() el:Set(v) end })
        end
        self.Window._togglePopup(btn, items)
    end)

    self:_dots(row, 20 + width + 41, el, false)
    self:_register(el, row, text)
    Library.Flags[flag] = el.Value
    Library.Options[flag] = el
    return el
end

function Section:AddSlider(flag, o)
    o = o or {}
    local text = o.Text or flag
    local min, max = o.Min or 0, o.Max or 1
    local step = o.Step
    local rounding = o.Rounding or 2
    local suffix = o.Suffix or ""
    local row = self:_row(text)
    local el = {
        Type = "Slider", Flag = flag, Min = min, Max = max, Default = o.Default or min,
        Callback = o.Callback, _changed = {},
    }

    local trackW = math.floor(self.Width * 0.225)
    local valueLbl = New("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -22, 0.5, 0), Size = UDim2.fromOffset(52, 30),
        TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.TextDim, Parent = row,
    })
    local track = New("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -79, 0.5, 0),
        Size = UDim2.fromOffset(trackW, 30), Parent = row,
    })
    local bar = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 6),
        BackgroundColor3 = Theme.Track, Parent = track,
    })
    Corner(bar, FULL)
    local fill = New("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = Color3.new(1, 1, 1), Parent = bar })
    Corner(fill, FULL)
    New("UIGradient", { Color = ColorSequence.new(Theme.Accent, Theme.AccentLight), Parent = fill })
    local knob = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Theme.AccentLight, Parent = track,
    })
    Corner(knob, FULL)
    Stroke(knob, Color3.fromRGB(255, 215, 235), 2, 0.25)

    function el:Set(v, silent)
        v = tonumber(v) or min
        if step then v = math.floor(v / step + 0.5) * step end
        local m = 10 ^ rounding
        v = math.clamp(math.floor(v * m + 0.5) / m, min, max)
        local changed = (v ~= self.Value)
        self.Value = v
        Library.Flags[flag] = v
        local r = (max == min) and 0 or (v - min) / (max - min)
        fill.Size = UDim2.fromScale(r, 1)
        knob.Position = UDim2.fromScale(r, 0.5)
        valueLbl.Text = string.format("%." .. rounding .. "f", v) .. suffix
        if changed and not silent then
            Safe(self.Callback, v)
            for _, f in ipairs(self._changed) do Safe(f, v) end
        end
    end
    function el:OnChanged(f) table.insert(self._changed, f) end

    local dragging = false
    local function fromX(x)
        local r = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        el:Set(min + (max - min) * r)
    end
    local function press(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            self.Page.ScrollingEnabled = false
            fromX(i.Position.X)
        end
    end
    track.InputBegan:Connect(press)
    self.Window._connect(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            fromX(i.Position.X)
        end
    end)
    self.Window._connect(UIS.InputEnded, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
            self.Page.ScrollingEnabled = true
        end
    end)

    el:Set(el.Default, true)
    self:_dots(row, 79 + trackW + 43, el, false)
    self:_register(el, row, text)
    Library.Options[flag] = el
    return el
end

function Section:AddButton(o)
    o = o or {}
    local text = o.Text or "Button"
    local row = self:_row(text)
    local btn = New("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -22, 0.5, 0), Size = UDim2.fromOffset(120, 36),
        BackgroundTransparency = 0, BackgroundColor3 = Theme.Control, Text = o.ButtonText or "Run",
        Font = Enum.Font.GothamBold, TextColor3 = Theme.Accent, Parent = row,
    })
    Corner(btn, 4)
    Stroke(btn, Theme.Accent, 2, 0.35)
    btn.Activated:Connect(function() Safe(o.Callback) end)
    local el = { Type = "Button" }
    self:_register(el, row, text)
    return el
end

function Section:AddLabel(text)
    local row = self:_row(text)
    row.Label.Size = UDim2.new(1, -42, 1, 0)
    row.Label.TextColor3 = Theme.TextDim
    local el = { Type = "Label" }
    function el:SetText(t) row.Label.Text = t end
    self:_register(el, row, text)
    return el
end

--// ───────────────────────────── window ─────────────────────────────
function Library:CreateWindow(cfg)
    cfg = cfg or {}
    local W, H, TOP, SIDE = 1671, 941, 78, 299
    local profiles = cfg.Profiles or { "default" }

    local window = {
        Tabs = {}, Toggles = {}, Visible = true, _conns = {},
        Profile = cfg.Profile or profiles[1],
        ToggleKey = cfg.ToggleKey or Enum.KeyCode.RightShift,
        OnSave = cfg.OnSave, OnProfileChanged = cfg.OnProfileChanged,
    }
    local function connect(sig, fn)
        local c = sig:Connect(fn)
        table.insert(window._conns, c)
        return c
    end
    window._connect = connect

    -- gui root
    local gui = New("ScreenGui", {
        Name = "kushub_" .. tostring(math.random(100000, 999999)), ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
    })
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(gui) elseif protectgui then protectgui(gui) end
    end)
    local root
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then root = h end
    end
    if not root then
        local ok = pcall(function() return CoreGui:GetChildren() end)
        root = ok and CoreGui or Players.LocalPlayer:WaitForChild("PlayerGui")
    end
    gui.Parent = root

    local function fitScale()
        local want = cfg.Scale or 0.6
        local view = gui.AbsoluteSize
        if view.X < 10 then
            local cam = Workspace.CurrentCamera
            view = cam and cam.ViewportSize or Vector2.new(1280, 720)
        end
        return math.min(want, view.X * 0.96 / W, view.Y * 0.96 / H)
    end

    local main = New("Frame", {
        Name = "Main", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(W, H), BackgroundColor3 = Theme.Window, Parent = gui,
    })
    local uiscale = New("UIScale", { Scale = fitScale(), Parent = main })
    Corner(main, 8)
    Stroke(main, Theme.Border, 2)

    ----------------------------------------------------------------- topbar
    local topbar = New("Frame", { Name = "Topbar", Size = UDim2.fromOffset(W, TOP), BackgroundColor3 = Theme.Topbar, Parent = main })
    New("Frame", { Position = UDim2.fromOffset(0, TOP - 2), Size = UDim2.fromOffset(W, 2), BackgroundColor3 = Theme.Border, Parent = topbar })

    local logo = MakeLogo(topbar, 70)
    logo.Position = UDim2.fromOffset(28, 5)

    local title = New("TextLabel", {
        Text = cfg.Title or "kus;hub", Font = Enum.Font.GothamBold, TextSize = 42, TextColor3 = Color3.new(1, 1, 1),
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(121, 42), Size = UDim2.fromOffset(200, 56),
        TextXAlignment = Enum.TextXAlignment.Left, Parent = topbar,
    })
    New("UIGradient", { Color = LogoSeq, Parent = title })
    New("TextLabel", {
        Text = "✦", TextSize = 22, TextColor3 = Theme.Blue, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(313, 22), Size = UDim2.fromOffset(24, 24), Parent = topbar,
    })

    New("Frame", { Position = UDim2.fromOffset(368, 0), Size = UDim2.fromOffset(2, TOP - 2), BackgroundColor3 = Theme.Border, Parent = topbar })
    New("Frame", { Position = UDim2.fromOffset(452, 0), Size = UDim2.fromOffset(2, TOP - 2), BackgroundColor3 = Theme.Border, Parent = topbar })

    -- save
    local saveBtn = New("TextButton", { Position = UDim2.fromOffset(381, 0), Size = UDim2.fromOffset(58, TOP - 2), Parent = topbar })
    local saveIcon = MakeIcon(saveBtn, "save", 32, Theme.Accent)
    saveIcon.Holder.Position = UDim2.fromOffset(13, 23)
    saveBtn.MouseEnter:Connect(function() saveIcon:SetColor(Theme.AccentLight) end)
    saveBtn.MouseLeave:Connect(function() saveIcon:SetColor(Theme.Accent) end)
    saveBtn.Activated:Connect(function()
        saveIcon:SetColor(Color3.new(1, 1, 1))
        task.delay(0.15, function() saveIcon:SetColor(Theme.Accent) end)
        Safe(window.OnSave, window.Profile)
    end)

    -- profile dropdown
    local profileBtn = New("TextButton", {
        Position = UDim2.fromOffset(476, 14), Size = UDim2.fromOffset(282, 50),
        BackgroundTransparency = 0, BackgroundColor3 = Theme.Control, Parent = topbar,
    })
    Corner(profileBtn, 5)
    local pStroke = Stroke(profileBtn, Theme.ControlBorder, 2)
    local uIcon = MakeIcon(profileBtn, "user", 30, Theme.Text)
    uIcon.Holder.Position = UDim2.fromOffset(18, 10)
    local profileLabel = New("TextLabel", {
        Text = window.Profile, TextSize = 22, TextColor3 = Theme.TextBright, Position = UDim2.fromOffset(69, 0),
        Size = UDim2.new(1, -120, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = profileBtn,
    })
    local pChev = MakeIcon(profileBtn, "chevron", 20, Theme.TextBright)
    pChev.Holder.AnchorPoint = Vector2.new(0.5, 0.5)
    pChev.Holder.Position = UDim2.new(1, -25, 0.5, 0)
    profileBtn.MouseEnter:Connect(function() pStroke.Color = Color3.fromRGB(78, 78, 108) end)
    profileBtn.MouseLeave:Connect(function() pStroke.Color = Theme.ControlBorder end)

    -- search
    local searchFrame = New("Frame", {
        Position = UDim2.fromOffset(1217, 14), Size = UDim2.fromOffset(289, 50), BackgroundColor3 = Theme.Control, Parent = topbar,
    })
    Corner(searchFrame, 5)
    Stroke(searchFrame, Theme.ControlBorder, 2)
    local sIcon = MakeIcon(searchFrame, "search", 28, Theme.Accent)
    sIcon.Holder.Position = UDim2.fromOffset(14, 11)
    local searchBox = New("TextBox", {
        Position = UDim2.fromOffset(55, 0), Size = UDim2.new(1, -67, 1, 0), Text = "", PlaceholderText = "Search settings...",
        PlaceholderColor3 = Theme.Muted, ClearTextOnFocus = false, TextSize = 20, TextColor3 = Theme.TextBright,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = searchFrame,
    })

    -- minimize / close
    local function winButton(cx, iconName, size)
        local b = New("TextButton", { Position = UDim2.fromOffset(cx - 22, 17), Size = UDim2.fromOffset(44, 44), Parent = topbar })
        local ic = MakeIcon(b, iconName, size, Theme.Accent)
        ic.Holder.AnchorPoint = Vector2.new(0.5, 0.5)
        ic.Holder.Position = UDim2.fromScale(0.5, 0.5)
        b.MouseEnter:Connect(function() ic:SetColor(Theme.AccentLight) end)
        b.MouseLeave:Connect(function() ic:SetColor(Theme.Accent) end)
        return b
    end
    local minBtn = winButton(1577, "minimize", 22)
    local closeBtn = winButton(1630, "close", 24)

    ----------------------------------------------------------------- sidebar
    local sidebar = New("Frame", {
        Name = "Sidebar", Position = UDim2.fromOffset(0, TOP), Size = UDim2.fromOffset(SIDE, H - TOP),
        BackgroundColor3 = Theme.Sidebar, Parent = main,
    })
    New("Frame", { Position = UDim2.fromOffset(SIDE - 2, 0), Size = UDim2.fromOffset(2, H - TOP), BackgroundColor3 = Theme.Border, Parent = sidebar })

    local tabList = New("Frame", { Position = UDim2.fromOffset(15, 22), Size = UDim2.fromOffset(SIDE - 17, 600), BackgroundTransparency = 1, Parent = sidebar })
    New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1), Parent = tabList })

    -- footer
    local fLogo = MakeLogo(sidebar, 76)
    fLogo.Position = UDim2.fromOffset(34, 721)
    local fTitle = New("TextLabel", {
        Text = cfg.Title or "kus;hub", Font = Enum.Font.GothamBold, TextSize = 34, TextColor3 = Color3.new(1, 1, 1),
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(123, 751), Size = UDim2.fromOffset(160, 40),
        TextXAlignment = Enum.TextXAlignment.Left, Parent = sidebar,
    })
    New("UIGradient", { Color = LogoSeq, Parent = fTitle })
    New("TextLabel", {
        Text = cfg.Version or "v1.0.0", TextSize = 19, TextColor3 = Theme.Muted, AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromOffset(125, 790), Size = UDim2.fromOffset(120, 24), TextXAlignment = Enum.TextXAlignment.Left, Parent = sidebar,
    })
    New("TextLabel", { Text = "✦", TextSize = 18, TextColor3 = Theme.Blue, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(266, 727), Size = UDim2.fromOffset(20, 20), Parent = sidebar })
    New("TextLabel", { Text = "✦", TextSize = 10, TextColor3 = Theme.Blue, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(250, 723), Size = UDim2.fromOffset(12, 12), Parent = sidebar })

    ----------------------------------------------------------------- content + overlay
    local content = New("Frame", {
        Name = "Content", Position = UDim2.fromOffset(SIDE, TOP), Size = UDim2.fromOffset(W - SIDE, H - TOP),
        BackgroundTransparency = 1, ClipsDescendants = true, Parent = main,
    })
    local overlay = New("Frame", { Name = "Overlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = main })

    ----------------------------------------------------------------- popups
    local popup -- { Frame, Owner }
    local function closePopup()
        if popup then
            popup.Frame:Destroy()
            popup = nil
        end
    end

    local function openPopup(owner, items, opts)
        closePopup()
        opts = opts or {}
        local s = uiscale.Scale
        local ap = owner.AbsolutePosition - overlay.AbsolutePosition
        local x, y = ap.X / s, ap.Y / s
        local ow, oh = owner.AbsoluteSize.X / s, owner.AbsoluteSize.Y / s
        local w = opts.Width or ow
        local itemH, pad = 38, 4
        local h = math.min(#items, 8) * itemH + pad * 2
        local left = opts.Center and (x + ow / 2 - w / 2) or x
        left = math.clamp(left, 8, W - w - 8)
        local top = y + oh + 4
        if top + h > H - 8 then top = y - h - 4 end

        local frame = New("ScrollingFrame", {
            Position = UDim2.fromOffset(left, top), Size = UDim2.fromOffset(w, h), BackgroundColor3 = Theme.Section,
            CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
            ScrollBarImageColor3 = Theme.Accent, Parent = overlay,
        })
        Corner(frame, 5)
        Stroke(frame, Theme.ControlBorder, 2)
        New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })
        New("UIPadding", { PaddingTop = UDim.new(0, pad), PaddingBottom = UDim.new(0, pad), Parent = frame })

        for i, item in ipairs(items) do
            local b = New("TextButton", {
                Text = item.Text, Size = UDim2.new(1, 0, 0, itemH), LayoutOrder = i,
                TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = Color3.fromRGB(24, 24, 38),
                TextColor3 = item.Selected and Theme.Accent or Theme.Text, Parent = frame,
            })
            New("UIPadding", { PaddingLeft = UDim.new(0, 15), Parent = b })
            b.MouseEnter:Connect(function() b.BackgroundTransparency = 0 end)
            b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
            b.Activated:Connect(function()
                closePopup()
                Safe(item.Callback)
            end)
        end
        popup = { Frame = frame, Owner = owner }
    end

    window._openPopup = openPopup
    window._closePopup = closePopup
    window._togglePopup = function(owner, items, opts)
        if popup and popup.Owner == owner then closePopup() else openPopup(owner, items, opts) end
    end

    local function inside(obj, p)
        local a, s = obj.AbsolutePosition, obj.AbsoluteSize
        return p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
    end
    connect(UIS.InputBegan, function(input)
        if popup and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            if not inside(popup.Frame, input.Position) and not inside(popup.Owner, input.Position) then
                closePopup()
            end
        end
    end)

    ----------------------------------------------------------------- profile api
    function window:SetProfile(name, silent)
        self.Profile = name
        profileLabel.Text = tostring(name)
        if not silent then Safe(self.OnProfileChanged, name) end
    end
    function window:SetProfiles(list, selected)
        profiles = list
        self:SetProfile(selected or list[1], true)
    end
    profileBtn.Activated:Connect(function()
        local items = {}
        for _, name in ipairs(profiles) do
            table.insert(items, { Text = tostring(name), Selected = (name == window.Profile), Callback = function() window:SetProfile(name) end })
        end
        window._togglePopup(profileBtn, items)
    end)

    ----------------------------------------------------------------- tabs
    function window:SelectTab(tab)
        closePopup()
        self.ActiveTab = tab
        for _, t in ipairs(self.Tabs) do
            t.Page.Visible = (t == tab)
            t:SetActive(t == tab)
        end
    end

    function window:AddTab(name, icon)
        local tab = { Name = name, Sections = {}, Window = window, _order = { 0, 0 } }
        local idx = #self.Tabs + 1

        local btn = New("TextButton", { Size = UDim2.new(1, 0, 0, 66), LayoutOrder = idx, Parent = tabList })
        local hl = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Accent, Visible = false, Parent = btn })
        New("UIGradient", {
            Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) }),
            Parent = hl,
        })
        local bar = New("Frame", { Size = UDim2.fromOffset(5, 66), BackgroundColor3 = Theme.Accent, Visible = false, Parent = btn })
        Corner(bar, 2)
        local ic = MakeIcon(btn, icon, 40, Theme.IconIdle)
        ic.Holder.Position = UDim2.fromOffset(24, 13)
        local label = New("TextLabel", {
            Text = name, TextSize = 21, TextColor3 = Theme.TextTab, Position = UDim2.fromOffset(92, 0),
            Size = UDim2.new(1, -92, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = btn,
        })

        function tab:SetActive(on)
            hl.Visible, bar.Visible = on, on
            ic:SetColor(on and Theme.IconActive or Theme.IconIdle)
            label.TextColor3 = on and Theme.TextBright or Theme.TextTab
        end
        btn.MouseEnter:Connect(function()
            if window.ActiveTab ~= tab then label.TextColor3 = Theme.TextBright end
        end)
        btn.MouseLeave:Connect(function()
            if window.ActiveTab ~= tab then label.TextColor3 = Theme.TextTab end
        end)
        btn.Activated:Connect(function() window:SelectTab(tab) end)

        -- page: two columns side by side
        local page = New("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
            ScrollBarThickness = 6, ScrollBarImageColor3 = Theme.Accent, ScrollBarImageTransparency = 0.4, Parent = content,
        })
        New("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 21), Parent = page,
        })
        New("UIPadding", { PaddingLeft = UDim.new(0, 19), PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 20), PaddingRight = UDim.new(0, 23), Parent = page })
        local function column(i)
            local col = New("Frame", {
                Size = UDim2.fromOffset(COLUMN_WIDTHS[i], 0), AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1, LayoutOrder = i, Parent = page,
            })
            New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 18), Parent = col })
            return col
        end
        tab.Page, tab.Left, tab.Right = page, column(1), column(2)

        function tab:AddSection(titleText, side)
            local si = (side == "Right") and 2 or 1
            local col = (si == 2) and self.Right or self.Left
            self._order[si] = self._order[si] + 1

            local frame = New("Frame", {
                Name = titleText, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Theme.Section, LayoutOrder = self._order[si], Parent = col,
            })
            Corner(frame, 4)
            Stroke(frame, Theme.Border, 2)
            New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })

            local head = New("Frame", { Size = UDim2.new(1, 0, 0, HEAD_H), BackgroundTransparency = 1, LayoutOrder = 0, Parent = frame })
            local accent = New("Frame", { Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(5, 26), BackgroundColor3 = Theme.Accent, Parent = head })
            Corner(accent, 2)
            New("TextLabel", {
                Text = string.upper(titleText), Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = Theme.Accent,
                Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -40, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = head,
            })
            New("Frame", { Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = Theme.Divider, Parent = head })

            local sec = setmetatable({
                Window = window, Page = page, Frame = frame, Title = titleText,
                Width = COLUMN_WIDTHS[si], Elements = {}, _n = 0,
            }, Section)
            table.insert(self.Sections, sec)
            return sec
        end

        table.insert(self.Tabs, tab)
        tab:SetActive(false)
        if not self.ActiveTab then self:SelectTab(tab) end
        return tab
    end

    ----------------------------------------------------------------- search
    local function applySearch(q)
        q = string.lower(q or "")
        local firstHit, activeHas
        for _, tab in ipairs(window.Tabs) do
            local tabHas = false
            for _, sec in ipairs(tab.Sections) do
                local secMatch = (q == "") or (string.find(string.lower(sec.Title), q, 1, true) ~= nil)
                local any = secMatch
                for _, el in ipairs(sec.Elements) do
                    local m = secMatch or (string.find(el.Search, q, 1, true) ~= nil)
                    el.Row.Visible = m
                    if m then any = true end
                end
                sec.Frame.Visible = any
                if any then tabHas = true end
            end
            if tabHas then
                firstHit = firstHit or tab
                if tab == window.ActiveTab then activeHas = true end
            end
        end
        if q ~= "" and not activeHas and firstHit then window:SelectTab(firstHit) end
    end
    searchBox:GetPropertyChangedSignal("Text"):Connect(function() applySearch(searchBox.Text) end)

    ----------------------------------------------------------------- show / hide / destroy
    local chip = New("TextButton", {
        Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 0,
        BackgroundColor3 = Theme.Topbar, Visible = false, Parent = gui,
    })
    Corner(chip, FULL)
    local chipLogo = MakeLogo(chip, 38)
    chipLogo.Position = UDim2.fromOffset(4, 4)
    chip.Activated:Connect(function() window:Toggle(true) end)

    function window:Toggle(state)
        if state == nil then state = not self.Visible end
        self.Visible = state
        main.Visible = state
        chip.Visible = not state
        if not state then closePopup() end
    end
    function window:SetScale(n) uiscale.Scale = n end
    function window:Destroy()
        for _, c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
        gui:Destroy()
    end
    minBtn.Activated:Connect(function() window:Toggle(false) end)
    closeBtn.Activated:Connect(function() window:Destroy() end)

    ----------------------------------------------------------------- dragging
    local dragging, dragStart, startPos = false, nil, nil
    topbar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, i.Position, main.Position
        end
    end)
    connect(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    connect(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)

    ----------------------------------------------------------------- keys
    connect(UIS.InputBegan, function(input, processed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local listening = window._listening
        if listening then
            window._listening = nil
            if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
                listening:SetKey(nil)
            else
                listening:SetKey(input.KeyCode)
            end
            return
        end
        if processed then return end
        if input.KeyCode == window.ToggleKey then
            window:Toggle()
            return
        end
        for _, t in ipairs(window.Toggles) do
            if t.Key and t.Key == input.KeyCode then t:Set(not t.Value) end
        end
    end)

    table.insert(Library.Windows, window)
    return window
end

function Library:Unload()
    for _, w in ipairs(self.Windows) do pcall(function() w:Destroy() end) end
    self.Windows = {}
end

return Library
