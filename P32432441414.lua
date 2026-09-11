--// KUSU UI - Linoria version
--// KUSU UI - Linoria port with the requested legacy feature set.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")

local Library = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"
))()

local pink = Color3.fromRGB(255, 132, 193)
local theme = {
    SchemeColor = pink,
    Background = Color3.fromRGB(12, 12, 16),
    Header = Color3.fromRGB(20, 20, 27),
    TextColor = Color3.fromRGB(245, 245, 250),
    ElementColor = Color3.fromRGB(27, 27, 36)
}

local LinoriaWindow = Library:CreateWindow({
    Title = "kus-hook ProjectDelta",
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.15
})

-- Keep the original compact API while using Linoria's real controls underneath.
local SliderControls = {}
local ToggleControls = {}
local DropdownControls = {}

local function makeCompatWindow()
    local window = {}

    function window:NewTab(name)
        local tab = LinoriaWindow:AddTab(name)
        local compatTab = {}

        function compatTab:NewSection(sectionName)
            local groupbox = tab:AddLeftGroupbox(sectionName)
            local section = {}

            function section:NewLabel(text)
                groupbox:AddLabel(text)
            end

            function section:NewButton(name, description, callback)
                groupbox:AddButton({
                    Text = name,
                    Tooltip = description,
                    Func = callback
                })
            end

            function section:NewToggle(name, description, callback)
                local toggle = groupbox:AddToggle(name, {
                    Text = name,
                    Tooltip = description,
                    Default = false,
                    Callback = callback
                })
                ToggleControls[name] = toggle
                return toggle
            end

            function section:NewSlider(name, description, maximum, minimum, callback, defaultValue)
                local minValue = tonumber(minimum) or 0
                local maxValue = tonumber(maximum) or minValue
                local slider = groupbox:AddSlider(name, {
                    Text = name,
                    Tooltip = description,
                    Default = math.clamp(tonumber(defaultValue) or minValue, minValue, maxValue),
                    Min = minValue,
                    Max = maxValue,
                    -- Keep the actual numeric value instead of formatting every slider as 1.
                    Rounding = (minValue % 1 ~= 0 or maxValue % 1 ~= 0) and 1 or 0,
                    Callback = callback
                })
                SliderControls[name] = slider
                return slider
            end

            function section:NewTextBox(name, description, callback)
                groupbox:AddInput(name, {
                    Text = name,
                    Tooltip = description,
                    Default = "",
                    Callback = callback
                })
            end

            function section:NewDropdown(name, description, options, callback)
                local dropdown = groupbox:AddDropdown(name, {
                    Text = name,
                    Tooltip = description,
                    Values = options,
                    Default = options[1],
                    Callback = callback
                })
                DropdownControls[name] = dropdown
                return dropdown
            end

            function section:NewKeybind(name, description, key, callback, mode, changedCallback, noUI)
                local toggle = groupbox:AddToggle(name .. "_Toggle", {
                    Text = name,
                    Tooltip = description,
                    Default = false,
                    Callback = function() end
                })

                return toggle:AddKeyPicker(name, {
                    Text = name,
                    Default = key.Name,
                    Mode = mode or "Toggle",
                    NoUI = noUI == true,
                    Callback = callback,
                    ChangedCallback = changedCallback
                })
            end

            function section:NewKeyPicker(name, description, key, callback, mode, changedCallback)
                local label = groupbox:AddLabel(name)
                return label:AddKeyPicker(name, {
                    Text = name,
                    Default = key.Name,
                    Mode = mode or "Toggle",
                    Callback = callback,
                    ChangedCallback = changedCallback
                })
            end

            function section:NewColorPicker(name, description, default, callback)
                groupbox:AddLabel(name):AddColorPicker(name, {
                    Default = default,
                    Title = name,
                    Callback = callback
                })
            end

            return section
        end

        return compatTab
    end

    return window
end

local Window = makeCompatWindow()

local Flight = {
    Active = false,
    Speed = 70
}

local player = Players.LocalPlayer
local inputState = {}
local flightHeartbeatConnection
local flightBeganConnection
local flightEndedConnection
local savedAutoRotate

local function getFlightRoot()
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function getFlightHumanoid()
    local character = player.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function stopFlightConnections()
    if flightHeartbeatConnection then
        flightHeartbeatConnection:Disconnect()
        flightHeartbeatConnection = nil
    end

    if flightBeganConnection then
        flightBeganConnection:Disconnect()
        flightBeganConnection = nil
    end

    if flightEndedConnection then
        flightEndedConnection:Disconnect()
        flightEndedConnection = nil
    end
end

local function setFlightInput(input, isDown)
    local key = input.KeyCode
    if key == Enum.KeyCode.W or key == Enum.KeyCode.A or key == Enum.KeyCode.S
        or key == Enum.KeyCode.D or key == Enum.KeyCode.Space or key == Enum.KeyCode.LeftControl then
        inputState[key] = isDown
    end
end

local function getFlightDirection()
    local camera = workspace.CurrentCamera
    if not camera then
        return Vector3.zero
    end

    local direction = Vector3.zero
    if inputState[Enum.KeyCode.W] then
        direction += camera.CFrame.LookVector
    end
    if inputState[Enum.KeyCode.S] then
        direction -= camera.CFrame.LookVector
    end
    if inputState[Enum.KeyCode.D] then
        direction += camera.CFrame.RightVector
    end
    if inputState[Enum.KeyCode.A] then
        direction -= camera.CFrame.RightVector
    end
    if inputState[Enum.KeyCode.Space] then
        direction += Vector3.yAxis
    end
    if inputState[Enum.KeyCode.LeftControl] then
        direction -= Vector3.yAxis
    end

    return direction.Magnitude > 0 and direction.Unit or Vector3.zero
end

function Flight:SetSpeed(speed)
    self.Speed = math.clamp(tonumber(speed) or self.Speed, 10, 250)
end

function Flight:Stop()
    self.Active = false
    stopFlightConnections()
    table.clear(inputState)

    local humanoid = getFlightHumanoid()
    if humanoid and savedAutoRotate ~= nil then
        humanoid.AutoRotate = savedAutoRotate
    end
    savedAutoRotate = nil

    local root = getFlightRoot()
    if root then
        root.AssemblyLinearVelocity = Vector3.zero
    end
end

function Flight:Start()
    if self.Active then
        return
    end

    local humanoid = getFlightHumanoid()
    if not getFlightRoot() or not humanoid then
        return
    end

    self.Active = true
    savedAutoRotate = humanoid.AutoRotate
    humanoid.AutoRotate = false

    flightBeganConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if not gameProcessed then
            setFlightInput(input, true)
        end
    end)

    flightEndedConnection = UserInputService.InputEnded:Connect(function(input)
        setFlightInput(input, false)
    end)

    flightHeartbeatConnection = RunService.Heartbeat:Connect(function()
        local rootPart = getFlightRoot()
        local currentHumanoid = getFlightHumanoid()
        if not rootPart or not currentHumanoid or currentHumanoid.Health <= 0 then
            self:Stop()
            return
        end

        rootPart.AssemblyLinearVelocity = getFlightDirection() * self.Speed
    end)
end

function Flight:Toggle(state)
    if state == nil then
        state = not self.Active
    end

    if state then
        self:Start()
    else
        self:Stop()
    end
end

Library:GiveSignal(player.CharacterAdded:Connect(function()
    if Flight.Active then
        Flight:Stop()
    end
end))

Library:OnUnload(function()
    Flight:Stop()
end)

--==================================================
-- Menu controls
--==================================================

local menuScale = 1
local KusuRoot = LinoriaWindow.Holder

local function setMenuScale(value)
    menuScale = math.clamp(tonumber(value) or 100, 75, 150) / 100
    local scale = KusuRoot:FindFirstChild("KusuMenuScale")

    if not scale then
        scale = Instance.new("UIScale")
        scale.Name = "KusuMenuScale"
        scale.Parent = KusuRoot
    end

    scale.Scale = menuScale
end

local function toggleMenu()
    Library:Toggle()
end

local keybindOverlay = Instance.new("Frame")
keybindOverlay.Name = "KusuStatsAndKeybinds"
keybindOverlay.AnchorPoint = Vector2.new(1, 0)
keybindOverlay.Position = UDim2.new(1, -12, 0, 12)
keybindOverlay.Size = UDim2.fromOffset(220, 122)
keybindOverlay.BackgroundColor3 = theme.Background
keybindOverlay.BorderColor3 = pink
keybindOverlay.BorderSizePixel = 1
keybindOverlay.Visible = false
keybindOverlay.Parent = Library.ScreenGui

local keybindHeader = Instance.new("Frame")
keybindHeader.Active = true
keybindHeader.Size = UDim2.new(1, 0, 0, 25)
keybindHeader.BackgroundColor3 = theme.Header
keybindHeader.BorderSizePixel = 0
keybindHeader.Parent = keybindOverlay

local fpsLabel = Instance.new("TextLabel")
fpsLabel.Position = UDim2.fromOffset(8, 0)
fpsLabel.Size = UDim2.new(0.5, -8, 1, 0)
fpsLabel.BackgroundTransparency = 1
fpsLabel.Text = "FPS: --"
fpsLabel.TextColor3 = theme.TextColor
fpsLabel.TextSize = 13
fpsLabel.Font = Enum.Font.Code
fpsLabel.TextXAlignment = Enum.TextXAlignment.Left
fpsLabel.Parent = keybindHeader

local pingLabel = fpsLabel:Clone()
pingLabel.Position = UDim2.new(0.5, 0, 0, 0)
pingLabel.Size = UDim2.new(0.5, -8, 1, 0)
pingLabel.Text = "Ping: --"
pingLabel.TextXAlignment = Enum.TextXAlignment.Right
pingLabel.Parent = keybindHeader

local dragging = false
local dragInput
local dragStart
local startPosition

Library:GiveSignal(keybindHeader.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPosition = keybindOverlay.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end))

Library:GiveSignal(keybindHeader.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        dragInput = input
    end
end))

Library:GiveSignal(UserInputService.InputChanged:Connect(function(input)
    if dragging and input == dragInput then
        local delta = input.Position - dragStart
        keybindOverlay.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end))

-- Forward-declare feature states used by the keybind overlay refresh.
local flightEnabled = false
local cameraZoomEnabled = false
local AimbotConfig

local keybindTitle = Instance.new("TextLabel")
keybindTitle.Position = UDim2.fromOffset(8, 28)
keybindTitle.Size = UDim2.new(1, -16, 0, 18)
keybindTitle.BackgroundTransparency = 1
keybindTitle.Text = "KEYBINDS"
keybindTitle.TextColor3 = pink
keybindTitle.TextSize = 12
keybindTitle.Font = Enum.Font.Code
keybindTitle.TextXAlignment = Enum.TextXAlignment.Left
keybindTitle.Parent = keybindOverlay

local keybindLabel = Instance.new("TextLabel")
keybindLabel.Position = UDim2.fromOffset(8, 47)
keybindLabel.Size = UDim2.new(1, -16, 0, 18)
keybindLabel.BackgroundTransparency = 1
keybindLabel.Text = "Toggle Menu  [F1]  Toggle"
keybindLabel.TextColor3 = pink
keybindLabel.TextSize = 13
keybindLabel.Font = Enum.Font.Code
keybindLabel.TextXAlignment = Enum.TextXAlignment.Left
keybindLabel.Parent = keybindOverlay

local flightKeybindLabel = keybindLabel:Clone()
flightKeybindLabel.Position = UDim2.fromOffset(8, 65)
flightKeybindLabel.Text = "Flight  [P]  Toggle"
flightKeybindLabel.TextColor3 = theme.TextColor
flightKeybindLabel.Parent = keybindOverlay

local zoomKeybindLabel = keybindLabel:Clone()
zoomKeybindLabel.Position = UDim2.fromOffset(8, 83)
zoomKeybindLabel.Text = "Hold Zoom  [Z]  Hold"
zoomKeybindLabel.TextColor3 = theme.TextColor
zoomKeybindLabel.Parent = keybindOverlay

local aimbotKeybindLabel = keybindLabel:Clone()
aimbotKeybindLabel.Position = UDim2.fromOffset(8, 101)
aimbotKeybindLabel.Text = "Aimbot  [F]  Toggle"
aimbotKeybindLabel.TextColor3 = theme.TextColor
aimbotKeybindLabel.Parent = keybindOverlay

-- Only show keybinds for features that are currently active/usable.
-- The menu key is always available; feature keybinds appear when their
-- corresponding feature is enabled. The rows are packed together so there
-- are no empty gaps when a feature is disabled.
local function refreshKeybindRows()
    local rows = {
        { label = keybindLabel, visible = true },
        { label = flightKeybindLabel, visible = flightEnabled },
        { label = zoomKeybindLabel, visible = cameraZoomEnabled },
        { label = aimbotKeybindLabel, visible = AimbotConfig.Enabled },
    }

    local y = 47
    local visibleCount = 0

    for _, row in ipairs(rows) do
        row.label.Visible = row.visible
        if row.visible then
            row.label.Position = UDim2.fromOffset(8, y)
            y = y + 18
            visibleCount = visibleCount + 1
        end
    end

    -- Header (25) + title (18) + rows + small bottom padding.
    keybindOverlay.Size = UDim2.fromOffset(220, 25 + 18 + (visibleCount * 18) + 8)
end

local function setKeybindDisplay(enabled)
    -- The keybind display is intentionally part of the same FPS/ping box.
    -- Do not show Linoria's separate KeybindFrame.
    keybindOverlay.Visible = enabled
    refreshKeybindRows()
    if Library.KeybindFrame then
        Library.KeybindFrame.Visible = false
    end
end

local frameCount = 0
local frameTimer = 0
local statsTimer = 0
Library:GiveSignal(RunService.RenderStepped:Connect(function(deltaTime)
    frameCount = frameCount + 1
    frameTimer = frameTimer + deltaTime
    statsTimer = statsTimer + deltaTime

    if frameTimer >= 0.5 then
        fpsLabel.Text = string.format("FPS: %d", math.floor(frameCount / frameTimer + 0.5))
        frameCount = 0
        frameTimer = 0
    end

    if statsTimer >= 1 then
        local ping = "--"
        pcall(function()
            ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValueString()
        end)
        pingLabel.Text = "Ping: " .. ping
        statsTimer = 0
    end
end))

local function rejoinServer()
    local player = Players.LocalPlayer

    if not player then
        warn("[KUSU] Could not rejoin: local player is unavailable.")
        return
    end

    local success, errorMessage = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
    end)

    if not success then
        warn("[KUSU] Rejoin failed:", errorMessage)
    end
end

local function destroyMenu()
    Library:Unload()
end

--==================================================
-- KUSU CONFIG
--==================================================

local VisualConfig = {
    PlayerESP = false,

    ESPBoxes = false,
    ESPHealthBar = false,
    ESPNames = false,
    ESPDistance = false,
    ESPTracers = false,
    PlayerMaxDist = 2000,

    NPC_ESP = false,
    NPCMaxDist = 1500,

    Vehicle_ESP = false,
    VehicleMaxDist = 2000,

    DroppedItemESP = false,
    DroppedItemMaxDist = 300,

    ExtractionESP = false,
    ExtractionMaxDist = 5000,

    TrapESP = false,
    TrapMaxDist = 1000,

    Colors = {
        Boxes = pink,
        HealthBar = Color3.fromRGB(80, 255, 120),
        Names = theme.TextColor,
        Distance = Color3.fromRGB(200, 200, 200),
        Tracers = pink,

        NPC = Color3.fromRGB(255, 180, 80),
        Vehicle = Color3.fromRGB(100, 180, 255),
        DroppedItem = Color3.fromRGB(255, 220, 80),
        Extraction = Color3.fromRGB(120, 255, 180),
        Trap = Color3.fromRGB(255, 80, 100),
    }
}

local CombatVisualConfig = {
    BulletTracers = false,
    TracerColor = pink,
    HitMarkers = false,
    HitmarkerColor = Color3.fromRGB(255, 255, 255),
    HitSound = false,
    SelectedHitSound = "Skeet",
    HitSoundVolume = 3,
    HitLogsEnabled = false,
    HitLogsLifetime = 5,
    HitLogsSize = 13,
}

--==================================================
-- AIMBOT CONFIG
-- Imported from the old KUSU menu.
--==================================================

AimbotConfig = {
    Enabled = false,
    Key = Enum.KeyCode.F2,
    AimHoldKey = Enum.UserInputType.MouseButton2,
    Bone = "Head",
    Smoothness = 1.0,
    FOV = 120,
    DrawFOV = false,
    FOVColor = pink,
    TargetNPCs = false,
    WallCheck = false,
    Prediction = false,
    BulletVelocity = 850,
}

-- Set the initial overlay rows now that all feature state tables exist.
refreshKeybindRows()

--==================================================
-- GUN MODS
-- Imported from the old KUSU menu.
--==================================================

local GunModsConfig = {
    NoRecoil = false,
    NoDrop = false,
    NoDrag = false,
    InstantAim = false,
}

local cachedAmmoAttributes = {}

local function ApplyAmmoMods()
    local ammoTypes = ReplicatedStorage:FindFirstChild("AmmoTypes")
    if not ammoTypes then return end

    for _, ammo in ipairs(ammoTypes:GetChildren()) do
        if not cachedAmmoAttributes[ammo] then
            cachedAmmoAttributes[ammo] = {
                Recoil = ammo:GetAttribute("RecoilStrength"),
                Drop = ammo:GetAttribute("ProjectileDrop"),
                Drag = ammo:GetAttribute("Drag")
            }
        end

        local original = cachedAmmoAttributes[ammo]

        if GunModsConfig.NoRecoil then
            ammo:SetAttribute("RecoilStrength", 0)
        elseif original.Recoil ~= nil then
            ammo:SetAttribute("RecoilStrength", original.Recoil)
        end

        if GunModsConfig.NoDrop then
            ammo:SetAttribute("ProjectileDrop", 0)
        elseif original.Drop ~= nil then
            ammo:SetAttribute("ProjectileDrop", original.Drop)
        end

        if GunModsConfig.NoDrag then
            ammo:SetAttribute("Drag", 0)
        elseif original.Drag ~= nil then
            ammo:SetAttribute("Drag", original.Drag)
        end
    end
end

local function RestoreAmmoMods()
    for ammo, original in pairs(cachedAmmoAttributes) do
        if ammo and ammo.Parent then
            if original.Recoil ~= nil then ammo:SetAttribute("RecoilStrength", original.Recoil) end
            if original.Drop ~= nil then ammo:SetAttribute("ProjectileDrop", original.Drop) end
            if original.Drag ~= nil then ammo:SetAttribute("Drag", original.Drag) end
        end
    end
end

local ammoTypesFolder = ReplicatedStorage:FindFirstChild("AmmoTypes")
if ammoTypesFolder then
    Library:GiveSignal(ammoTypesFolder.ChildAdded:Connect(function()
        task.defer(ApplyAmmoMods)
    end))
end

--==================================================
-- PLAYER ESP
--==================================================

local playerEspDrawings = {}

local function hidePlayerESP(esp)
    if not esp then return end
    esp.Box.Visible = false
    esp.HealthBar.Visible = false
    esp.NameText.Visible = false
    esp.DistText.Visible = false
    esp.Tracer.Visible = false
end

local function createPlayerESP(p)
    if not Drawing or playerEspDrawings[p] then
        return
    end

    local box = Drawing.new("Square")
    box.Thickness = 1
    box.Filled = false
    box.Color = VisualConfig.Colors.Boxes
    box.Visible = false

    local hpBar = Drawing.new("Line")
    hpBar.Thickness = 2
    hpBar.Color = VisualConfig.Colors.HealthBar
    hpBar.Visible = false

    local nameText = Drawing.new("Text")
    nameText.Size = 12
    nameText.Font = 2
    nameText.Center = true
    nameText.Outline = true
    nameText.Color = VisualConfig.Colors.Names
    nameText.Visible = false

    local distText = Drawing.new("Text")
    distText.Size = 11
    distText.Font = 2
    distText.Center = true
    distText.Outline = true
    distText.Color = VisualConfig.Colors.Distance
    distText.Visible = false

    local tracer = Drawing.new("Line")
    tracer.Thickness = 1
    tracer.Color = VisualConfig.Colors.Tracers
    tracer.Visible = false

    playerEspDrawings[p] = {
        Box = box,
        HealthBar = hpBar,
        NameText = nameText,
        DistText = distText,
        Tracer = tracer
    }
end

local function removePlayerESP(p)
    local esp = playerEspDrawings[p]
    if not esp then
        return
    end

    pcall(function() esp.Box:Remove() end)
    pcall(function() esp.HealthBar:Remove() end)
    pcall(function() esp.NameText:Remove() end)
    pcall(function() esp.DistText:Remove() end)
    pcall(function() esp.Tracer:Remove() end)

    playerEspDrawings[p] = nil
end

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= player then
        createPlayerESP(p)
    end
end

Library:GiveSignal(Players.PlayerAdded:Connect(function(p)
    if p ~= player then
        createPlayerESP(p)
    end
end))

Library:GiveSignal(Players.PlayerRemoving:Connect(removePlayerESP))

Library:GiveSignal(RunService.RenderStepped:Connect(function()
    if not VisualConfig.PlayerESP then
        for _, esp in pairs(playerEspDrawings) do
            hidePlayerESP(esp)
        end
        return
    end

    local camera = workspace.CurrentCamera
    local myCharacter = player.Character
    local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")

    if not camera or not myRoot then
        for _, esp in pairs(playerEspDrawings) do
            hidePlayerESP(esp)
        end
        return
    end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and not playerEspDrawings[p] then
            createPlayerESP(p)
        end
    end

    for p, esp in pairs(playerEspDrawings) do
        local char = p.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")

        if not char or not root or not hum or hum.Health <= 0 then
            hidePlayerESP(esp)
            continue
        end

        local distance = (root.Position - myRoot.Position).Magnitude
        if distance > VisualConfig.PlayerMaxDist then
            hidePlayerESP(esp)
            continue
        end

        local rootPos, onScreen = camera:WorldToViewportPoint(root.Position)
        if not onScreen or rootPos.Z <= 0 then
            hidePlayerESP(esp)
            continue
        end

        local head = char:FindFirstChild("Head")
        local headWorld = head and (head.Position + Vector3.new(0, 0.6, 0))
            or (root.Position + Vector3.new(0, 2.5, 0))
        local legWorld = root.Position - Vector3.new(0, 3, 0)

        local headPos = camera:WorldToViewportPoint(headWorld)
        local legPos = camera:WorldToViewportPoint(legWorld)

        local height = math.abs(legPos.Y - headPos.Y)
        local width = height * 0.55

        if height <= 1 then
            hidePlayerESP(esp)
            continue
        end

        local topY = math.min(headPos.Y, legPos.Y)
        local topLeft = Vector2.new(rootPos.X - width * 0.5, topY)

        if VisualConfig.ESPBoxes then
            esp.Box.Visible = true
            esp.Box.Size = Vector2.new(width, height)
            esp.Box.Position = topLeft
            esp.Box.Color = VisualConfig.Colors.Boxes
        else
            esp.Box.Visible = false
        end

        if VisualConfig.ESPHealthBar then
            local hpRatio = math.clamp(
                hum.Health / math.max(hum.MaxHealth, 1),
                0,
                1
            )

            esp.HealthBar.Visible = true
            esp.HealthBar.From = Vector2.new(topLeft.X - 4, topY + height)
            esp.HealthBar.To = Vector2.new(
                topLeft.X - 4,
                topY + (height * (1 - hpRatio))
            )
            esp.HealthBar.Color = VisualConfig.Colors.HealthBar
        else
            esp.HealthBar.Visible = false
        end

        if VisualConfig.ESPNames then
            esp.NameText.Visible = true
            esp.NameText.Text = p.Name
            esp.NameText.Position = Vector2.new(rootPos.X, topY - 14)
            esp.NameText.Color = VisualConfig.Colors.Names
        else
            esp.NameText.Visible = false
        end

        if VisualConfig.ESPDistance then
            esp.DistText.Visible = true
            esp.DistText.Text = string.format("%d studs", math.round(distance))
            esp.DistText.Position = Vector2.new(
                rootPos.X,
                topY + height + 2
            )
            esp.DistText.Color = VisualConfig.Colors.Distance
        else
            esp.DistText.Visible = false
        end

        if VisualConfig.ESPTracers then
            esp.Tracer.Visible = true
            esp.Tracer.From = Vector2.new(
                camera.ViewportSize.X * 0.5,
                camera.ViewportSize.Y
            )
            esp.Tracer.To = Vector2.new(rootPos.X, topY + height)
            esp.Tracer.Color = VisualConfig.Colors.Tracers
        else
            esp.Tracer.Visible = false
        end
    end
end))

Library:OnUnload(function()
    for p in pairs(playerEspDrawings) do
        removePlayerESP(p)
    end
end)

--==================================================
-- AIMBOT
--==================================================

local aimbotActive = false
local aimbotTargetModel = nil
local aimbotTargetPart = nil
local aimbotFovCircle

local function getAimPart(model)
    if not model then return nil end
    local part = model:FindFirstChild(AimbotConfig.Bone)
        or model:FindFirstChild("Head")
        or model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
    return part and part:IsA("BasePart") and part or nil
end

local function isVisible(part)
    local camera = workspace.CurrentCamera
    if not camera or not part then return false end

    local origin = camera.CFrame.Position
    local direction = part.Position - origin
    if direction.Magnitude < 0.5 then return true end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {player.Character, camera}
    params.IgnoreWater = true

    local hit = workspace:Raycast(origin, direction, params)
    if not hit then return true end
    return hit.Instance == part or hit.Instance:IsDescendantOf(part.Parent)
        or hit.Instance.Transparency >= 0.85
        or not hit.Instance.CanCollide
end

local aimNPCs = {}

local function registerAimNPC(inst)
    if not AimbotConfig.TargetNPCs then return end
    if not inst:IsA("Model") or inst == player.Character then return end
    if Players:GetPlayerFromCharacter(inst) then return end
    if inst:FindFirstChildOfClass("Humanoid") then
        aimNPCs[inst] = true
    end
end

-- Cache NPC models instead of calling Workspace:GetDescendants() every render frame.
for _, inst in ipairs(workspace:GetDescendants()) do
    registerAimNPC(inst)
end
Library:GiveSignal(workspace.DescendantAdded:Connect(registerAimNPC))
Library:GiveSignal(workspace.DescendantRemoving:Connect(function(inst)
    aimNPCs[inst] = nil
end))

local function findClosestAimTarget()
    local camera = workspace.CurrentCamera
    if not camera then return nil, nil end

    local mousePos = UserInputService:GetMouseLocation()
    local closestDistance = AimbotConfig.FOV
    local closestModel = nil
    local closestPart = nil

    local function consider(model)
        if not model or model == player.Character or not model:IsA("Model") then return end
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return end

        local part = getAimPart(model)
        if not part then return end
        if AimbotConfig.WallCheck and not isVisible(part) then return end

        local screenPos, onScreen = camera:WorldToViewportPoint(part.Position)
        if not onScreen or screenPos.Z <= 0 then return end

        local distance = (mousePos - Vector2.new(screenPos.X, screenPos.Y)).Magnitude
        if distance < closestDistance then
            closestDistance = distance
            closestModel = model
            closestPart = part
        end
    end

    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= player then
            consider(targetPlayer.Character)
        end
    end

    if AimbotConfig.TargetNPCs then
        for instance in pairs(aimNPCs) do
            if instance and instance.Parent then
                local isVendor = instance:GetAttribute("Interaction") ~= nil
                    or instance:FindFirstChild("faceTarget") ~= nil
                if not isVendor then
                    consider(instance)
                end
            else
                aimNPCs[instance] = nil
            end
        end
    end

    return closestModel, closestPart
end

Library:GiveSignal(UserInputService.InputBegan:Connect(function(input)
    if UserInputService:GetFocusedTextBox() then return end
    if input.UserInputType == AimbotConfig.AimHoldKey or input.KeyCode == AimbotConfig.AimHoldKey then
        aimbotActive = true
        aimbotTargetModel = nil
        aimbotTargetPart = nil
    end
end))

Library:GiveSignal(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == AimbotConfig.AimHoldKey or input.KeyCode == AimbotConfig.AimHoldKey then
        aimbotActive = false
        aimbotTargetModel = nil
        aimbotTargetPart = nil
    end
end))

if Drawing then
    aimbotFovCircle = Drawing.new("Circle")
    aimbotFovCircle.Thickness = 1
    aimbotFovCircle.NumSides = 48
    aimbotFovCircle.Filled = false
    aimbotFovCircle.Transparency = 0.8
    aimbotFovCircle.Color = AimbotConfig.FOVColor
    aimbotFovCircle.Visible = false
end

Library:GiveSignal(RunService.RenderStepped:Connect(function()
    local camera = workspace.CurrentCamera

    if aimbotFovCircle then
        if camera and AimbotConfig.Enabled and AimbotConfig.DrawFOV then
            aimbotFovCircle.Visible = true
            aimbotFovCircle.Position = UserInputService:GetMouseLocation()
            aimbotFovCircle.Radius = AimbotConfig.FOV * (70 / math.max(camera.FieldOfView, 1))
            aimbotFovCircle.Color = AimbotConfig.FOVColor
        else
            aimbotFovCircle.Visible = false
        end
    end

    if not camera or not AimbotConfig.Enabled or not aimbotActive then return end

    -- Keep the same target while RMB is held instead of reacquiring a new
    -- target every frame. This makes the aimbot actually "lock" onto the
    -- selected player until the aim key is released.
    if not aimbotTargetModel or not aimbotTargetPart
        or not aimbotTargetModel.Parent
        or not aimbotTargetPart.Parent then
        aimbotTargetModel, aimbotTargetPart = findClosestAimTarget()
    end

    if not aimbotTargetModel or not aimbotTargetPart then return end

    local targetHumanoid = aimbotTargetModel:FindFirstChildOfClass("Humanoid")
    if not targetHumanoid or targetHumanoid.Health <= 0 then
        aimbotTargetModel = nil
        aimbotTargetPart = nil
        return
    end

    local aimPosition = aimbotTargetPart.Position
    if AimbotConfig.Prediction then
        local root = targetModel:FindFirstChild("HumanoidRootPart") or targetModel.PrimaryPart
        if root and root:IsA("BasePart") then
            local distance = (camera.CFrame.Position - aimPosition).Magnitude
            local travelTime = distance / math.max(tonumber(AimbotConfig.BulletVelocity) or 850, 1)
            aimPosition += root.AssemblyLinearVelocity * travelTime
        end
    end

    local current = camera.CFrame
    local target = CFrame.new(current.Position, aimPosition)
    local smoothFactor = math.clamp(0.2 / math.max(AimbotConfig.Smoothness, 0.05), 0.02, 1)
    camera.CFrame = current:Lerp(target, smoothFactor)
end))

Library:OnUnload(function()
    aimbotActive = false
    aimbotTargetModel = nil
    aimbotTargetPart = nil
    if aimbotFovCircle then
        pcall(function() aimbotFovCircle:Remove() end)
        aimbotFovCircle = nil
    end
end)

Library:OnUnload(function()
    pcall(RestoreAmmoMods)
end)

--==================================================
-- COMBAT VISUALS
--==================================================

local SoundIds = {
    Skeet = "rbxassetid://4817809188",
    Rust = "rbxassetid://5043539486",
    Bell = "rbxassetid://6534947240",
    Ding = "rbxassetid://2868798606",
}

local function PlayHitSound()
    if not CombatVisualConfig.HitSound then return end
    local sound = Instance.new("Sound")
    sound.SoundId = SoundIds[CombatVisualConfig.SelectedHitSound] or SoundIds.Skeet
    sound.Volume = tonumber(CombatVisualConfig.HitSoundVolume) or 3
    sound.Parent = SoundService
    sound:Play()
    Debris:AddItem(sound, 2)
end

local function CreateBulletTracer(origin, endPos)
    if not CombatVisualConfig.BulletTracers then return end

    task.spawn(function()
        local distance = (origin - endPos).Magnitude
        local travelTime = 0.05
        local lifetime = 0.35

        local core = Instance.new("Part")
        core.Name = "KusuTracerCore"
        core.Anchored = true
        core.CanCollide = false
        core.CanQuery = false
        core.CastShadow = false
        core.Material = Enum.Material.Neon
        core.Color = Color3.new(1, 1, 1)
        core.Size = Vector3.new(0.05, 0.05, 0)
        core.CFrame = CFrame.new(origin, endPos)
        core.Parent = workspace

        local glow = core:Clone()
        glow.Name = "KusuTracerGlow"
        glow.Color = CombatVisualConfig.TracerColor
        glow.Size = Vector3.new(0.18, 0.18, 0)
        glow.Transparency = 0.4
        glow.Parent = workspace

        local endCF = CFrame.new(origin:Lerp(endPos, 0.5), endPos)
        local coreTween = TweenService:Create(core, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), {
            Size = Vector3.new(0.05, 0.05, distance),
            CFrame = endCF,
        })
        local glowTween = TweenService:Create(glow, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), {
            Size = Vector3.new(0.18, 0.18, distance),
            CFrame = endCF,
        })

        coreTween:Play()
        glowTween:Play()

        task.delay(travelTime, function()
            if not core.Parent or not glow.Parent then return end
            TweenService:Create(core, TweenInfo.new(lifetime), {Transparency = 1}):Play()
            TweenService:Create(glow, TweenInfo.new(lifetime), {Transparency = 1}):Play()
            task.delay(lifetime, function()
                pcall(function() core:Destroy() end)
                pcall(function() glow:Destroy() end)
            end)
        end)
    end)
end

local hitLogs = {}

local function CreateHitMarker(hitPart, hitPosition)
    if not CombatVisualConfig.HitMarkers or not hitPart or not Drawing then return end

    task.spawn(function()
        local line1 = Drawing.new("Line")
        local line2 = Drawing.new("Line")
        line1.Thickness = 1.5
        line2.Thickness = 1.5
        line1.Color = CombatVisualConfig.HitmarkerColor
        line2.Color = CombatVisualConfig.HitmarkerColor
        line1.Visible = false
        line2.Visible = false

        local startTime = tick()
        local lifetime = 0.35
        local size = 6
        local offset = hitPart.CFrame:PointToObjectSpace(hitPosition)

        while tick() - startTime < lifetime do
            if not hitPart.Parent then break end
            local currentPos = hitPart.CFrame:PointToWorldSpace(offset)
            local screenPos, onScreen = workspace.CurrentCamera:WorldToViewportPoint(currentPos)
            local alpha = 1 - ((tick() - startTime) / lifetime)

            if onScreen and screenPos.Z > 0 then
                line1.Visible = true
                line2.Visible = true
                line1.Transparency = alpha
                line2.Transparency = alpha
                line1.From = Vector2.new(screenPos.X - size, screenPos.Y - size)
                line1.To = Vector2.new(screenPos.X + size, screenPos.Y + size)
                line2.From = Vector2.new(screenPos.X + size, screenPos.Y - size)
                line2.To = Vector2.new(screenPos.X - size, screenPos.Y + size)
            else
                line1.Visible = false
                line2.Visible = false
            end
            RunService.RenderStepped:Wait()
        end

        pcall(function() line1:Remove() end)
        pcall(function() line2:Remove() end)
    end)
end

local function CreateHitLog(partName, targetName)
    if not CombatVisualConfig.HitLogsEnabled or not Drawing then return end

    local text = Drawing.new("Text")
    text.Size = CombatVisualConfig.HitLogsSize
    text.Font = 2
    text.Center = true
    text.Outline = true
    text.Color = CombatVisualConfig.TracerColor
    text.Text = string.format("[%s] hit %s in %s", os.date("%H:%M:%S"), tostring(targetName):lower(), tostring(partName):lower())
    text.Visible = true

    table.insert(hitLogs, text)
    local camera = workspace.CurrentCamera
    if camera then
        local center = camera.ViewportSize * 0.5
        for i, item in ipairs(hitLogs) do
            item.Position = Vector2.new(center.X, center.Y + 120 + (i * 16))
        end
    end

    task.delay(CombatVisualConfig.HitLogsLifetime, function()
        local index = table.find(hitLogs, text)
        if index then table.remove(hitLogs, index) end
        pcall(function() text:Remove() end)
    end)
end

-- Port the old bullet hook when the executor exposes hookfunction/newcclosure.
pcall(function()
    local fpsMods = ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("FPS")
    local bulletMod = fpsMods and fpsMods:FindFirstChild("Bullet")
    if not bulletMod or not hookfunction or not newcclosure then return end

    local bulletTable = require(bulletMod)
    if type(bulletTable) ~= "table" or type(bulletTable.CreateBullet) ~= "function" then return end

    local original = bulletTable.CreateBullet
    local oldCreateBullet

    local function hookedCreateBullet(...)
        local args = {...}
        if args[5] and typeof(args[5]) == "Instance" and args[5]:IsA("BasePart") then
            local muzzleCF = args[5].CFrame
            task.spawn(function()
                local origin = muzzleCF.Position
                local direction = muzzleCF.LookVector * 1500
                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = {player.Character, workspace.CurrentCamera}
                params.IgnoreWater = true

                local result = workspace:Raycast(origin, direction, params)
                local endPos = result and result.Position or (origin + direction)
                CreateBulletTracer(origin, endPos)

                if result and result.Instance then
                    local model = result.Instance:FindFirstAncestorOfClass("Model")
                    local hitPlayer = model and Players:GetPlayerFromCharacter(model)
                    local isNPC = model and not hitPlayer and model:FindFirstChildOfClass("Humanoid")
                    if (hitPlayer and hitPlayer ~= player) or isNPC then
                        PlayHitSound()
                        CreateHitMarker(result.Instance, result.Position)
                        CreateHitLog(result.Instance.Name, hitPlayer and hitPlayer.Name or model.Name)
                    end
                end
            end)
        end

        if oldCreateBullet then
            return oldCreateBullet(...)
        end
        return original(...)
    end

    oldCreateBullet = hookfunction(original, newcclosure(hookedCreateBullet))
end)

Library:OnUnload(function()
    for _, text in ipairs(hitLogs) do
        pcall(function() text:Remove() end)
    end
    table.clear(hitLogs)
end)

--==================================================
-- PLAYER / INVENTORY VIEWER
--==================================================

local PlayerViewerConfig = {
    InventoryViewerEnabled = false,
    TargetHUDEnabled = false,
}

local ValidItemNames = {}
local ItemIcons = {}

local function CacheProjectDeltaItems()
    task.spawn(function()
        local blacklist = {
            "MeshPart", "Part", "UnionOperation", "Weld", "WeldConstraint", "Mesh", "SpecialMesh",
            "HelmetMask", "Harness", "UT", "Hood", "RL", "LU", "RU", "LL", "RA", "LA", "TR", "HD",
            "Handle", "Casing", "ItemProperties", "Folder", "Configuration", "Model", "SelectionBox",
            "SurfaceAppearance", "Texture", "Decal"
        }
        for _, containerName in ipairs({"ItemsList", "ItemsListModels"}) do
            local container = ReplicatedStorage:FindFirstChild(containerName)
            if container then
                for _, obj in ipairs(container:GetChildren()) do
                    if not table.find(blacklist, obj.Name) then
                        ValidItemNames[obj.Name] = true
                        local props = obj:FindFirstChild("ItemProperties")
                        local icon = props and props:FindFirstChild("ItemIcon")
                        if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
                            ItemIcons[obj.Name] = icon.Image
                            local callSign = props:GetAttribute("CallSign")
                            if callSign then ItemIcons[tostring(callSign)] = icon.Image end
                        end
                    end
                end
            end
        end
    end)
end

CacheProjectDeltaItems()

local function GetEquippedItem(character)
    if not character then return "None" end
    for _, obj in ipairs(character:GetChildren()) do
        if obj:IsA("Tool") then
            local props = obj:FindFirstChild("ItemProperties")
            return tostring((props and props:GetAttribute("CallSign")) or obj:GetAttribute("CallSign") or obj.Name)
        end
    end
    return "None"
end

local function ScanTargetInventory(target)
    local items = {}
    if not target then return items end
    local targetPlayer = target:IsA("Player") and target or Players:GetPlayerFromCharacter(target)

    if targetPlayer then
        local rsPlayers = ReplicatedStorage:FindFirstChild("Players")
        local playerFolder = rsPlayers and rsPlayers:FindFirstChild(targetPlayer.Name)
        local invFolder = playerFolder and playerFolder:FindFirstChild("Inventory")
        if invFolder then
            for _, itemObj in ipairs(invFolder:GetChildren()) do
                local itemName
                if itemObj:IsA("ObjectValue") and itemObj.Value then
                    local targetModel = itemObj.Value
                    local props = targetModel:FindFirstChild("ItemProperties")
                    itemName = tostring((props and (props:GetAttribute("CallSign") or props:GetAttribute("ItemName"))) or targetModel.Name)
                    local icon = props and props:FindFirstChild("ItemIcon")
                    if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
                        ItemIcons[itemName] = icon.Image
                    end
                else
                    local props = itemObj:FindFirstChild("ItemProperties")
                    itemName = tostring((props and props:GetAttribute("CallSign")) or itemObj:GetAttribute("CallSign") or itemObj.Name)
                end
                if itemName and not table.find(items, itemName) then table.insert(items, itemName) end
            end
        end
    end

    local character = targetPlayer and targetPlayer.Character or (target:IsA("Model") and target)
    local held = GetEquippedItem(character)
    if held ~= "None" and not table.find(items, held) then table.insert(items, held) end
    return items
end

local viewerGui = Instance.new("ScreenGui")
viewerGui.Name = "KusuTargetInfo"
viewerGui.ResetOnSpawn = false
viewerGui.Enabled = false
viewerGui.Parent = game:GetService("CoreGui")

local viewerFrame = Instance.new("Frame")
viewerFrame.Size = UDim2.fromOffset(185, 220)
viewerFrame.Position = UDim2.new(0.5, 200, 0.5, -110)
viewerFrame.BackgroundColor3 = theme.Background
viewerFrame.BorderColor3 = pink
viewerFrame.BorderSizePixel = 1
viewerFrame.Parent = viewerGui

local titleBar = Instance.new("TextLabel")
titleBar.Size = UDim2.new(1, 0, 0, 26)
titleBar.BackgroundColor3 = theme.Header
titleBar.TextColor3 = theme.TextColor
titleBar.TextSize = 12
titleBar.Font = Enum.Font.GothamBold
titleBar.TextXAlignment = Enum.TextXAlignment.Left
titleBar.Text = "  TARGET INFO"
titleBar.Parent = viewerFrame

local healthLabel = Instance.new("TextLabel")
healthLabel.Size = UDim2.new(1, -10, 0, 16)
healthLabel.Position = UDim2.fromOffset(5, 30)
healthLabel.BackgroundTransparency = 1
healthLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
healthLabel.TextSize = 12
healthLabel.TextXAlignment = Enum.TextXAlignment.Left
healthLabel.Text = "HP: --"
healthLabel.Parent = viewerFrame

local weaponLabel = healthLabel:Clone()
weaponLabel.Position = UDim2.fromOffset(5, 47)
weaponLabel.Text = "Tool: None"
weaponLabel.Parent = viewerFrame

local extraLabel = healthLabel:Clone()
extraLabel.Position = UDim2.fromOffset(5, 64)
extraLabel.Text = "SPD: 0 | DIST: 0 studs"
extraLabel.Parent = viewerFrame

local invScroll = Instance.new("ScrollingFrame")
invScroll.Size = UDim2.new(1, -10, 1, -88)
invScroll.Position = UDim2.fromOffset(5, 86)
invScroll.BackgroundTransparency = 1
invScroll.BorderSizePixel = 0
invScroll.ScrollBarThickness = 2
invScroll.ScrollBarImageColor3 = pink
invScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
invScroll.Parent = viewerFrame

local invGrid = Instance.new("UIGridLayout")
invGrid.CellPadding = UDim2.fromOffset(4, 4)
invGrid.CellSize = UDim2.fromOffset(36, 36)
invGrid.Parent = invScroll

local dragging, dragStart, frameStart = false, nil, nil
Library:GiveSignal(titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        frameStart = viewerFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end))
Library:GiveSignal(UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        viewerFrame.Position = UDim2.new(frameStart.X.Scale, frameStart.X.Offset + delta.X, frameStart.Y.Scale, frameStart.Y.Offset + delta.Y)
    end
end))

local function GetClosestViewerTarget(maxPixels)
    local camera = workspace.CurrentCamera
    if not camera then return nil end
    local mouse = UserInputService:GetMouseLocation()
    local closest, shortest = nil, maxPixels or 500

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            local root = p.Character:FindFirstChild("HumanoidRootPart")
            if hum and root and hum.Health > 0 then
                local pos, onScreen = camera:WorldToViewportPoint(root.Position)
                if onScreen and pos.Z > 0 then
                    local d = (Vector2.new(pos.X, pos.Y) - mouse).Magnitude
                    if d < shortest then
                        shortest = d
                        closest = p
                    end
                end
            end
        end
    end
    return closest
end

local lastViewerTarget, lastViewerItems = "", ""
local lastViewerPos, lastViewerTime = nil, 0
local viewerSpeed = 0
local viewerInventoryTimer = 0

Library:GiveSignal(RunService.Heartbeat:Connect(function(dt)
    if not PlayerViewerConfig.TargetHUDEnabled and not PlayerViewerConfig.InventoryViewerEnabled then
        viewerGui.Enabled = false
        return
    end

    viewerInventoryTimer += dt
    local target = GetClosestViewerTarget(500)
    if not target or not target.Character then
        viewerGui.Enabled = false
        return
    end

    local char = target.Character
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then
        viewerGui.Enabled = false
        return
    end

    viewerGui.Enabled = true
    local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local dist = myRoot and (root.Position - myRoot.Position).Magnitude or 0
    healthLabel.Text = string.format("HP: %d / %d", math.round(hum.Health), math.round(hum.MaxHealth))
    weaponLabel.Text = "Tool: " .. GetEquippedItem(char)

    local now = tick()
    if lastViewerTarget ~= target.Name then
        lastViewerTarget = target.Name
        lastViewerPos = root.Position
        lastViewerTime = now
        viewerSpeed = 0
    elseif lastViewerPos and now - lastViewerTime >= 0.08 then
        viewerSpeed = ((root.Position - lastViewerPos) * Vector3.new(1, 0, 1)).Magnitude / (now - lastViewerTime)
        lastViewerPos = root.Position
        lastViewerTime = now
    end
    extraLabel.Text = string.format("SPD: %d | DIST: %d studs", math.round(viewerSpeed), math.round(dist))
    titleBar.Text = "  TARGET: " .. target.Name:upper()

    if PlayerViewerConfig.InventoryViewerEnabled then
        invScroll.Visible = true
        viewerFrame.Size = UDim2.fromOffset(185, 220)
        -- Inventory contents do not need to be rescanned every frame.
        if viewerInventoryTimer >= 0.10 or lastViewerTarget ~= target.Name then
            viewerInventoryTimer = 0
            local items = ScanTargetInventory(target)
            local key = table.concat(items, ",")
            if key ~= lastViewerItems then
                lastViewerItems = key
                for _, child in ipairs(invScroll:GetChildren()) do
                    if child:IsA("Frame") then child:Destroy() end
                end
                for _, itemName in ipairs(items) do
                    local card = Instance.new("Frame")
                    card.BackgroundColor3 = theme.ElementColor
                    card.BorderColor3 = pink
                    card.BorderSizePixel = 1
                    card.Parent = invScroll
                    local icon = Instance.new("ImageLabel")
                    icon.Size = UDim2.new(1, -4, 1, -4)
                    icon.Position = UDim2.fromScale(0.5, 0.5)
                    icon.AnchorPoint = Vector2.new(0.5, 0.5)
                    icon.BackgroundTransparency = 1
                    icon.Image = ItemIcons[itemName] or "rbxassetid://1316045217"
                    icon.Parent = card
                end
            end
        end
    else
        invScroll.Visible = false
        viewerFrame.Size = UDim2.fromOffset(185, 85)
    end
end))

Library:OnUnload(function()
    pcall(function() viewerGui:Destroy() end)
end)


--==================================================
-- PORTED MISC / WORLD FEATURES
--==================================================

local MiscConfig = {
    ContainerESP = false,
    ContainerMaxDist = 200,
    ThirdPerson = false,
    ThirdPersonDist = 12,
    ZoomKey = Enum.KeyCode.Z,
    ZoomFOVStep = 5,
    ZoomFOVMin = 10,
    ZoomFOVMax = 120,
    FullBright = false,
    ClockTimeEnabled = false,
    ClockTime = 14,
    RemoveGrass = false,
    RemoveFoliage = false,
    HackerDetector = false,
    HackerSpeedThreshold = 35,
    HackerSpeedDuration = 0.8,
    AutoSave = false,
}

local cameraZoomHeld = false
local cameraZoomFOV = 70
local cameraZoomSavedFOV = nil

-- Third-person camera state.
local thirdPersonCameraActive = false
local thirdPersonSavedMinZoom = nil
local thirdPersonSavedMaxZoom = nil
local thirdPersonSavedCameraMode = nil
local thirdPersonRenderBound = false

local function applyThirdPersonCamera()
    pcall(function()
        local player = Players.LocalPlayer
        if not player or not MiscConfig.ThirdPerson then return end

        local distance = math.max(1, tonumber(MiscConfig.ThirdPersonDist) or 12)
        player.CameraMode = Enum.CameraMode.Classic
        player.CameraMinZoomDistance = distance
        player.CameraMaxZoomDistance = distance
    end)
end

local function setThirdPersonCamera(enabled)
    pcall(function()
        local player = Players.LocalPlayer
        if not player then return end

        if enabled then
            if not thirdPersonCameraActive then
                thirdPersonSavedMinZoom = player.CameraMinZoomDistance
                thirdPersonSavedMaxZoom = player.CameraMaxZoomDistance
                thirdPersonSavedCameraMode = player.CameraMode
                thirdPersonCameraActive = true
            end

            applyThirdPersonCamera()

            if not thirdPersonRenderBound then
                RunService:BindToRenderStep("KUSU_ThirdPersonCamera", Enum.RenderPriority.Camera.Value + 1, function()
                    applyThirdPersonCamera()
                end)
                thirdPersonRenderBound = true
            end
        elseif thirdPersonCameraActive then
            if thirdPersonRenderBound then
                RunService:UnbindFromRenderStep("KUSU_ThirdPersonCamera")
                thirdPersonRenderBound = false
            end

            player.CameraMinZoomDistance = thirdPersonSavedMinZoom or 0.5
            player.CameraMaxZoomDistance = thirdPersonSavedMaxZoom or 128
            player.CameraMode = thirdPersonSavedCameraMode or Enum.CameraMode.Classic

            thirdPersonSavedMinZoom = nil
            thirdPersonSavedMaxZoom = nil
            thirdPersonSavedCameraMode = nil
            thirdPersonCameraActive = false
        end
    end)
end

local function updateCameraZoom()
    pcall(function()
        if MiscConfig.ThirdPerson then
            applyThirdPersonCamera()
        elseif thirdPersonCameraActive then
            setThirdPersonCamera(false)
        end

        local camera = workspace.CurrentCamera
        if not camera then return end

        if cameraZoomHeld then
            camera.FieldOfView = cameraZoomFOV
        elseif cameraZoomSavedFOV ~= nil then
            camera.FieldOfView = cameraZoomSavedFOV
        end
    end)
end

-- Re-apply third person after character/camera scripts update their settings.
Library:GiveSignal(Players.LocalPlayer.CharacterAdded:Connect(function()
    if MiscConfig.ThirdPerson then
        task.defer(function()
            setThirdPersonCamera(true)
        end)
    end
end))

Library:GiveSignal(UserInputService.InputChanged:Connect(function(input)
    if not cameraZoomEnabled or not cameraZoomHeld or input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
    if UserInputService:GetFocusedTextBox() then return end

    -- Scrolling up lowers FOV (zooms in); scrolling down raises FOV (zooms out).
    cameraZoomFOV = math.clamp(
        cameraZoomFOV - (input.Position.Z * MiscConfig.ZoomFOVStep),
        MiscConfig.ZoomFOVMin,
        MiscConfig.ZoomFOVMax
    )
    updateCameraZoom()
end))

local originalLighting = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    GlobalShadows = Lighting.GlobalShadows,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
}

local originalFoliageTransparency = {}
local function restoreLighting()
    pcall(function()
        Lighting.Brightness = originalLighting.Brightness
        Lighting.ClockTime = originalLighting.ClockTime
        Lighting.GlobalShadows = originalLighting.GlobalShadows
        Lighting.Ambient = originalLighting.Ambient
        Lighting.OutdoorAmbient = originalLighting.OutdoorAmbient
        Lighting.FogEnd = originalLighting.FogEnd
        Lighting.FogStart = originalLighting.FogStart
    end)
end

local function enforceLighting()
    pcall(function()
        if MiscConfig.FullBright then
            Lighting.Brightness = 2.5
            Lighting.ClockTime = 14
            Lighting.GlobalShadows = false
            Lighting.Ambient = Color3.fromRGB(180,180,180)
            Lighting.OutdoorAmbient = Color3.fromRGB(180,180,180)
            Lighting.FogStart = 0
            Lighting.FogEnd = 100000
            local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
            if atmo then
                atmo.Density = 0
                atmo.Haze = 0
                atmo.Glare = 0
            end
        elseif MiscConfig.ClockTimeEnabled then
            Lighting.ClockTime = MiscConfig.ClockTime
        end
        if MiscConfig.RemoveGrass then
            pcall(function() workspace.Terrain.Decoration = false end)
        end
    end)
end

local function setFoliageRemoval(enabled)
    pcall(function()
        if not enabled then
            for part, transparency in pairs(originalFoliageTransparency) do
                if part and part.Parent then part.Transparency = transparency end
            end
            table.clear(originalFoliageTransparency)
            return
        end
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") then
                local n = obj.Name:lower()
                if n:find("leaf") or n:find("leaves") or n:find("foliage") or n:find("bush") then
                    if originalFoliageTransparency[obj] == nil then
                        originalFoliageTransparency[obj] = obj.Transparency
                    end
                    obj.Transparency = 1
                end
            end
        end
    end)
end

Library:GiveSignal(RunService.RenderStepped:Connect(function()
    if MiscConfig.FullBright or MiscConfig.ClockTimeEnabled or MiscConfig.RemoveGrass then
        enforceLighting()
    end
end))
Library:GiveSignal(player.CharacterAdded:Connect(function()
    task.wait(0.2)
    updateCameraZoom()
end))

-- Lightweight world ESP.
-- IMPORTANT: do not create a Drawing object for every Workspace descendant.
-- Large maps can contain thousands of instances; doing that every frame tanks FPS.
local worldLabels = {}
local worldCandidates = {}
local worldScanAccumulator = 0
local WORLD_UPDATE_INTERVAL = 0.10

local function removeWorldLabel(inst)
    local label = worldLabels[inst]
    if label then
        pcall(function() label:Remove() end)
        worldLabels[inst] = nil
    end
    worldCandidates[inst] = nil
end

local function ensureWorldLabel(inst)
    if not Drawing or worldLabels[inst] then return end
    local label = Drawing.new("Text")
    label.Center = true
    label.Font = 2
    label.Outline = true
    label.Size = 12
    label.Visible = false
    worldLabels[inst] = label
end

local function worldRoot(inst)
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then
        return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
    end
end

local TrapNames = {
    PMN2 = true,
    MON50 = true,
    GrenadeTrap = true,
    BigPropaneTank = true,
    SmallPropaneTank = true,
}

local function isTrapInstance(inst)
    if not (inst:IsA("Model") or inst:IsA("BasePart")) then return false end
    -- These are the actual trap/explosive names used by the old menu.
    if TrapNames[inst.Name] then return true end

    local n = inst.Name:lower()
    if n:find("pmn") or n:find("mon50") or n:find("claymore") then return true end
    if n:find("grenadetrap") or (n:find("grenade") and n:find("trap")) then return true end
    if n:find("landmine") or n:find("mine") or n:find("propane") then return true end

    -- Some grenade traps are identified by their child parts instead of their name.
    return inst:FindFirstChild("GrenadeBody") ~= nil
        and inst:FindFirstChild("Trigger") ~= nil
end

local function isWorldESPRelevant(inst)
    if not (inst:IsA("Model") or inst:IsA("BasePart")) then return false end
    if Players:GetPlayerFromCharacter(inst) then return false end

    if inst:IsA("Model") then
        if inst:FindFirstChildOfClass("Humanoid") then return true end
        if inst:FindFirstChild("DriveSeat") or inst:FindFirstChild("VehicleSeat") then return true end
        if inst:GetAttribute("CallSign") then return true end
        if inst:FindFirstChild("Inventory") then return true end
    end

    if isTrapInstance(inst) then return true end

    local n = inst.Name:lower()
    return n:find("extraction") ~= nil
        or n == "exit"
        or n:find("evac") ~= nil
        or n:find("crate") ~= nil
        or n:find("container") ~= nil
        or n:find("box") ~= nil
        or n:find("bag") ~= nil
end

local function registerWorldCandidate(inst)
    if not isWorldESPRelevant(inst) then return end
    worldCandidates[inst] = true
end

Library:GiveSignal(workspace.DescendantAdded:Connect(registerWorldCandidate))

-- One initial scan is fine; unlike the old implementation, it does not allocate
-- a Drawing object for every object in Workspace.
for _, inst in ipairs(workspace:GetDescendants()) do
    registerWorldCandidate(inst)
end

local function updateWorldLabel(inst, enabled, maxDist, text, color)
    if not enabled then
        local label = worldLabels[inst]
        if label then label.Visible = false end
        return
    end

    local root = worldRoot(inst)
    local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local cam = workspace.CurrentCamera
    if not root or not myRoot or not cam or not inst.Parent then
        local label = worldLabels[inst]
        if label then label.Visible = false end
        return
    end

    local dist = (root.Position - myRoot.Position).Magnitude
    if dist > maxDist then
        local label = worldLabels[inst]
        if label then label.Visible = false end
        return
    end

    local pos, onScreen = cam:WorldToViewportPoint(root.Position)
    if not onScreen or pos.Z <= 0 then
        local label = worldLabels[inst]
        if label then label.Visible = false end
        return
    end

    ensureWorldLabel(inst)
    local label = worldLabels[inst]
    if not label then return end

    label.Position = Vector2.new(pos.X, pos.Y)
    label.Text = string.format("%s\n%d studs", text, math.round(dist))
    label.Color = color
    label.Visible = true
end

Library:GiveSignal(RunService.RenderStepped:Connect(function(dt)
    worldScanAccumulator += dt
    if worldScanAccumulator < WORLD_UPDATE_INTERVAL then return end
    worldScanAccumulator = 0

    for inst in pairs(worldCandidates) do
        if not inst.Parent then
            removeWorldLabel(inst)
            continue
        end

        local n = inst.Name:lower()
        if VisualConfig.NPC_ESP and inst:IsA("Model")
            and inst:FindFirstChildOfClass("Humanoid")
            and not Players:GetPlayerFromCharacter(inst) then
            updateWorldLabel(inst, true, VisualConfig.NPCMaxDist,
                "[AI] " .. inst.Name, VisualConfig.Colors.NPC)
        elseif VisualConfig.Vehicle_ESP and inst:IsA("Model")
            and (inst:FindFirstChild("DriveSeat") or inst:FindFirstChild("VehicleSeat")) then
            updateWorldLabel(inst, true, VisualConfig.VehicleMaxDist,
                "[VEHICLE] " .. inst.Name, VisualConfig.Colors.Vehicle)
        elseif VisualConfig.DroppedItemESP and inst:IsA("Model")
            and inst.Parent == workspace and inst:GetAttribute("CallSign") then
            updateWorldLabel(inst, true, VisualConfig.DroppedItemMaxDist,
                "[ITEM] " .. tostring(inst:GetAttribute("CallSign")), VisualConfig.Colors.DroppedItem)
        elseif VisualConfig.ExtractionESP
            and (n:find("extraction") or n == "exit" or n:find("evac")) then
            updateWorldLabel(inst, true, VisualConfig.ExtractionMaxDist,
                "[EXTRACT] " .. inst.Name, VisualConfig.Colors.Extraction)
        elseif VisualConfig.TrapESP and isTrapInstance(inst) then
            local trapName = inst.Name
            local tag = "[TRAP]"
            if inst.Name == "BigPropaneTank" or inst.Name == "SmallPropaneTank" or n:find("propane") then
                tag = "[EXPLOSIVE]"
            elseif inst.Name == "PMN2" or n:find("pmn") or n:find("landmine") or n:find("mine") then
                trapName = "PMN-2 Landmine"
            elseif inst.Name == "MON50" or n:find("mon50") or n:find("claymore") then
                trapName = "MON-50 Claymore"
            elseif inst.Name == "GrenadeTrap" or n:find("grenadetrap") then
                trapName = "Tripwire Grenade"
            end
            updateWorldLabel(inst, true, VisualConfig.TrapMaxDist,
                tag .. " " .. trapName, VisualConfig.Colors.Trap)
        elseif MiscConfig.ContainerESP and inst:IsA("Model")
            and (n:find("crate") or n:find("container") or n:find("box") or n:find("bag") or inst:FindFirstChild("Inventory")) then
            updateWorldLabel(inst, true, MiscConfig.ContainerMaxDist,
                "[BOX] " .. inst.Name, pink)
        else
            local label = worldLabels[inst]
            if label then label.Visible = false end
        end
    end
end))

Library:OnUnload(function()
    for inst in pairs(worldLabels) do
        removeWorldLabel(inst)
    end
    table.clear(worldCandidates)
end)

local speedFlags = {}
Library:GiveSignal(RunService.Heartbeat:Connect(function()
    if not MiscConfig.HackerDetector then return end
    local now = tick()
    for _, target in ipairs(Players:GetPlayers()) do
        if target ~= player and target.Character then
            local root = target.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local data = speedFlags[target]
                if not data then data = {pos=root.Position,time=now,over=0}; speedFlags[target]=data end
                local dt = now-data.time
                if dt >= 0.25 then
                    local speed = ((root.Position-data.pos)*Vector3.new(1,0,1)).Magnitude/dt
                    data.pos, data.time = root.Position, now
                    if speed >= MiscConfig.HackerSpeedThreshold then data.over += dt else data.over = 0 end
                    if data.over >= MiscConfig.HackerSpeedDuration then
                        warn(string.format("[KUSU] Speedhack alert: %s (%.1f studs/s)", target.Name, speed))
                        data.over = 0
                    end
                end
            end
        end
    end
end))

--==================================================
-- MAIN
--==================================================

local MainTab = Window:NewTab("Main")
local General = MainTab:NewSection("General")
General:NewLabel("kus-hook ProjectDelta")
General:NewLabel("ProjectDelta configuration menu")

local Aimbot = MainTab:NewSection("Aimbot")
Aimbot:NewKeybind(
    "Aimbot Keybind",
    "Press this key to toggle the aimbot on or off. RMB still controls aiming.",
    Enum.KeyCode.F,
    function(state)
        AimbotConfig.Enabled = state
        refreshKeybindRows()
    end
)
Aimbot:NewToggle(
    "Enable Camera Aimbot",
    "Enable the camera aimbot. Hold RMB while enabled.",
    function(state)
        AimbotConfig.Enabled = state
        refreshKeybindRows()
    end
)
Aimbot:NewDropdown(
    "Target Bone",
    "Choose which body part the aimbot prefers.",
    {"Head", "Neck", "HumanoidRootPart"},
    function(value)
        AimbotConfig.Bone = value
    end
)
Aimbot:NewSlider(
    "Aimbot FOV",
    "Maximum distance from your mouse to a target, in screen pixels.",
    400,
    30,
    function(value)
        AimbotConfig.FOV = value
    end,
    AimbotConfig.FOV
)
Aimbot:NewSlider(
    "Smoothness",
    "Controls how quickly the camera moves toward the target.",
    5.0,
    0.1,
    function(value)
        AimbotConfig.Smoothness = value
    end,
    AimbotConfig.Smoothness
)
Aimbot:NewToggle(
    "Draw FOV Circle",
    "Show the current aimbot FOV around your mouse.",
    function(state)
        AimbotConfig.DrawFOV = state
    end
)
Aimbot:NewToggle(
    "Target NPCs / AI",
    "Allow the aimbot to consider humanoid NPCs as targets.",
    function(state)
        AimbotConfig.TargetNPCs = state
    end
)
Aimbot:NewToggle(
    "Wall Check (Visible Only)",
    "Only target players or NPCs that are directly visible.",
    function(state)
        AimbotConfig.WallCheck = state
    end
)
Aimbot:NewToggle(
    "Lead Target Prediction",
    "Predict moving targets using the configured projectile speed.",
    function(state)
        AimbotConfig.Prediction = state
    end
)

--==================================================
-- PLAYER
--==================================================

local PlayerTab = Window:NewTab("Player")
local Movement = PlayerTab:NewSection("Movement")

flightEnabled = false
local flightSpeed = 100
Flight:Stop()

Movement:NewToggle(
    "Flight",
    "Toggle the existing flight system",
    function(state)
        flightEnabled = state
        Flight:Toggle(state)
        refreshKeybindRows()
    end
)

Movement:NewSlider(
    "Flight Speed",
    "Flight movement speed",
    250,
    10,
    function(value)
        flightSpeed = value
        Flight:SetSpeed(value)
    end,
    flightSpeed
)

Movement:NewKeybind(
    "Flight Keybind",
    "Key used to toggle flight",
    Enum.KeyCode.P,
    function()
        flightEnabled = not flightEnabled
        Flight:Toggle(flightEnabled)
        refreshKeybindRows()
    end
)

--==================================================
-- VISUALS
--==================================================

local VisualsTab = Window:NewTab("Visuals")

local PlayerESPSection = VisualsTab:NewSection("Player ESP")

PlayerESPSection:NewToggle(
    "Player ESP",
    "Enable the existing player ESP renderer",
    function(state)
        VisualConfig.PlayerESP = state
    end
)

PlayerESPSection:NewToggle(
    "Boxes",
    "Show bounding boxes",
    function(state)
        VisualConfig.ESPBoxes = state
    end
)

PlayerESPSection:NewColorPicker(
    "Box Color",
    "Color used for player boxes",
    VisualConfig.Colors.Boxes,
    function(color)
        VisualConfig.Colors.Boxes = color
    end
)

PlayerESPSection:NewToggle(
    "Health Bar",
    "Show the player's health bar",
    function(state)
        VisualConfig.ESPHealthBar = state
    end
)

PlayerESPSection:NewColorPicker(
    "Health Bar Color",
    "Color used for health bars",
    VisualConfig.Colors.HealthBar,
    function(color)
        VisualConfig.Colors.HealthBar = color
    end
)

PlayerESPSection:NewToggle(
    "Names",
    "Show player names",
    function(state)
        VisualConfig.ESPNames = state
    end
)

PlayerESPSection:NewColorPicker(
    "Name Color",
    "Color used for player names",
    VisualConfig.Colors.Names,
    function(color)
        VisualConfig.Colors.Names = color
    end
)

PlayerESPSection:NewToggle(
    "Distance",
    "Show distance in studs",
    function(state)
        VisualConfig.ESPDistance = state
    end
)

PlayerESPSection:NewColorPicker(
    "Distance Color",
    "Color used for distance text",
    VisualConfig.Colors.Distance,
    function(color)
        VisualConfig.Colors.Distance = color
    end
)

PlayerESPSection:NewToggle(
    "Tracers",
    "Draw a line from the bottom of the screen",
    function(state)
        VisualConfig.ESPTracers = state
    end
)

PlayerESPSection:NewColorPicker(
    "Tracer Color",
    "Color used for tracers",
    VisualConfig.Colors.Tracers,
    function(color)
        VisualConfig.Colors.Tracers = color
    end
)

PlayerESPSection:NewSlider(
    "Player Max Distance",
    "Maximum player ESP distance",
    5000,
    50,
    function(value)
        VisualConfig.PlayerMaxDist = value
    end,
    VisualConfig.PlayerMaxDist
)

local WorldESP = VisualsTab:NewSection("World ESP")

WorldESP:NewToggle(
    "NPC ESP",
    "Enable NPC ESP settings",
    function(state)
        VisualConfig.NPC_ESP = state
    end
)

WorldESP:NewColorPicker(
    "NPC Color",
    "Color assigned to NPC ESP",
    VisualConfig.Colors.NPC,
    function(color)
        VisualConfig.Colors.NPC = color
    end
)

WorldESP:NewSlider(
    "NPC Max Distance",
    "Maximum NPC ESP distance",
    5000,
    50,
    function(value)
        VisualConfig.NPCMaxDist = value
    end,
    VisualConfig.NPCMaxDist
)

WorldESP:NewToggle(
    "Vehicle ESP",
    "Enable vehicle ESP settings",
    function(state)
        VisualConfig.Vehicle_ESP = state
    end
)

WorldESP:NewColorPicker(
    "Vehicle Color",
    "Color assigned to vehicle ESP",
    VisualConfig.Colors.Vehicle,
    function(color)
        VisualConfig.Colors.Vehicle = color
    end
)

WorldESP:NewSlider(
    "Vehicle Max Distance",
    "Maximum vehicle ESP distance",
    5000,
    50,
    function(value)
        VisualConfig.VehicleMaxDist = value
    end,
    VisualConfig.VehicleMaxDist
)

WorldESP:NewToggle(
    "Dropped Item ESP",
    "Enable dropped item ESP settings",
    function(state)
        VisualConfig.DroppedItemESP = state
    end
)

WorldESP:NewColorPicker(
    "Dropped Item Color",
    "Color assigned to dropped items",
    VisualConfig.Colors.DroppedItem,
    function(color)
        VisualConfig.Colors.DroppedItem = color
    end
)

WorldESP:NewSlider(
    "Dropped Item Max Distance",
    "Maximum dropped item ESP distance",
    2000,
    25,
    function(value)
        VisualConfig.DroppedItemMaxDist = value
    end,
    VisualConfig.DroppedItemMaxDist
)

WorldESP:NewToggle(
    "Extraction ESP",
    "Enable extraction ESP settings",
    function(state)
        VisualConfig.ExtractionESP = state
    end
)

WorldESP:NewColorPicker(
    "Extraction Color",
    "Color assigned to extraction ESP",
    VisualConfig.Colors.Extraction,
    function(color)
        VisualConfig.Colors.Extraction = color
    end
)

WorldESP:NewSlider(
    "Extraction Max Distance",
    "Maximum extraction ESP distance",
    10000,
    100,
    function(value)
        VisualConfig.ExtractionMaxDist = value
    end,
    VisualConfig.ExtractionMaxDist
)

WorldESP:NewToggle(
    "Trap ESP",
    "Enable trap ESP settings",
    function(state)
        VisualConfig.TrapESP = state
    end
)

WorldESP:NewColorPicker(
    "Trap Color",
    "Color assigned to trap ESP",
    VisualConfig.Colors.Trap,
    function(color)
        VisualConfig.Colors.Trap = color
    end
)

WorldESP:NewSlider(
    "Trap Max Distance",
    "Maximum trap ESP distance",
    3000,
    50,
    function(value)
        VisualConfig.TrapMaxDist = value
    end,
    VisualConfig.TrapMaxDist
)

--==================================================
-- COMBAT VISUALS UI
--==================================================

local CombatVisuals = VisualsTab:NewSection("Combat Visuals")
CombatVisuals:NewToggle("Bullet Tracers", "Draw a short-lived tracer from the muzzle to the bullet hit point.", function(state)
    CombatVisualConfig.BulletTracers = state
end)
CombatVisuals:NewColorPicker("Tracer Color", "Color used for bullet tracers.", CombatVisualConfig.TracerColor, function(color)
    CombatVisualConfig.TracerColor = color
end)
CombatVisuals:NewToggle("Hit Markers", "Show an X marker where a player or NPC is hit.", function(state)
    CombatVisualConfig.HitMarkers = state
end)
CombatVisuals:NewColorPicker("Hitmarker Color", "Color used for hit markers.", CombatVisualConfig.HitmarkerColor, function(color)
    CombatVisualConfig.HitmarkerColor = color
end)
CombatVisuals:NewToggle("Hit Sound", "Play a sound when a player or NPC is hit.", function(state)
    CombatVisualConfig.HitSound = state
end)
CombatVisuals:NewDropdown("Sound Style", "Choose the hit sound style.", {"Skeet", "Rust", "Bell", "Ding"}, function(value)
    CombatVisualConfig.SelectedHitSound = value
end)
CombatVisuals:NewSlider("Sound Volume", "Hit sound volume.", 10, 1, function(value)
    CombatVisualConfig.HitSoundVolume = value
end, CombatVisualConfig.HitSoundVolume)
CombatVisuals:NewToggle("Hit Logs", "Show recent hit information near the center of the screen.", function(state)
    CombatVisualConfig.HitLogsEnabled = state
end)
CombatVisuals:NewSlider("Log Lifetime", "How long hit logs remain visible.", 30, 1, function(value)
    CombatVisualConfig.HitLogsLifetime = value
end, CombatVisualConfig.HitLogsLifetime)
CombatVisuals:NewSlider("Log Text Size", "Hit log text size.", 30, 10, function(value)
    CombatVisualConfig.HitLogsSize = value
end, CombatVisualConfig.HitLogsSize)

--==================================================
-- MISC
--==================================================

local MiscTab = Window:NewTab("Misc")

local GunMods = MiscTab:NewSection("Gun Mods")
GunMods:NewToggle("No Recoil", "Removes recoil by setting ammo recoil strength to zero.", function(state)
    GunModsConfig.NoRecoil = state
    ApplyAmmoMods()
end)
GunMods:NewToggle("No Bullet Drop", "Removes projectile drop by setting bullet drop to zero.", function(state)
    GunModsConfig.NoDrop = state
    ApplyAmmoMods()
end)
GunMods:NewToggle("No Drag", "Removes projectile drag by setting drag to zero.", function(state)
    GunModsConfig.NoDrag = state
    ApplyAmmoMods()
end)
GunMods:NewToggle("Instant Aim / Zoom", "Ported from the old menu. The original menu exposed the setting but did not contain a separate implementation.", function(state)
    GunModsConfig.InstantAim = state
end)

local CameraSection = MiscTab:NewSection("Camera")
CameraSection:NewToggle("Third Person Mode", "Force the camera into third person at the selected distance.", function(state)
    MiscConfig.ThirdPerson = state
    setThirdPersonCamera(state)
end)
CameraSection:NewSlider("Camera Distance", "Third-person camera distance in studs.", 30, 5, function(value)
    MiscConfig.ThirdPersonDist = value
    if MiscConfig.ThirdPerson then
        applyThirdPersonCamera()
    end
end, MiscConfig.ThirdPersonDist)

cameraZoomEnabled = false

local cameraZoomToggle = CameraSection:NewToggle(
    "Hold Zoom Enabled",
    "Turn hold-to-zoom on or off. When enabled, hold the selected key and use the mouse wheel to change FOV.",
    function(state)
        cameraZoomEnabled = state
        refreshKeybindRows()

        if not state and cameraZoomHeld then
            cameraZoomHeld = false
            if cameraZoomSavedFOV ~= nil and workspace.CurrentCamera then
                workspace.CurrentCamera.FieldOfView = cameraZoomSavedFOV
            end
            cameraZoomSavedFOV = nil
        end
    end
)

local cameraZoomKeybind = CameraSection:NewKeyPicker(
    "Hold Zoom",
    "Hold this key while using the mouse wheel to zoom.",
    MiscConfig.ZoomKey,
    function() end,
    "Hold",
    function(newKey)
        if typeof(newKey) == "EnumItem" then
            if newKey.EnumType == Enum.KeyCode then
                MiscConfig.ZoomKey = newKey
                zoomKeybindLabel.Text = "Hold Zoom  [" .. newKey.Name .. "]  Hold"
                refreshKeybindRows()
            end
        end
    end
)

-- Zoom is ready to use by default; it still has a UI toggle if you want to disable it.
if cameraZoomToggle and type(cameraZoomToggle.SetValue) == "function" then
    cameraZoomToggle:SetValue(true)
end

-- Read the actual Linoria Hold key state. This follows the library's
-- documented KeyPicker behavior, including rebinding the key at runtime.
local function isZoomKeyDown()
    if not cameraZoomEnabled then return false end
    if UserInputService:GetFocusedTextBox() then return false end

    if cameraZoomKeybind and type(cameraZoomKeybind.GetState) == "function" then
        return cameraZoomKeybind:GetState()
    end

    return UserInputService:IsKeyDown(MiscConfig.ZoomKey)
end

-- Run after the game's camera work so its FOV cannot immediately overwrite
-- the temporary zoom value.
RunService:BindToRenderStep("KUSU_CameraZoom", Enum.RenderPriority.Last.Value, function()
    if not cameraZoomEnabled then
        if cameraZoomHeld then
            cameraZoomHeld = false
            if cameraZoomSavedFOV ~= nil and workspace.CurrentCamera then
                workspace.CurrentCamera.FieldOfView = cameraZoomSavedFOV
            end
            cameraZoomSavedFOV = nil
        end
        return
    end

    local keyDown = isZoomKeyDown()

    if keyDown and not cameraZoomHeld then
        local camera = workspace.CurrentCamera
        if camera then
            cameraZoomHeld = true
            cameraZoomSavedFOV = camera.FieldOfView
            cameraZoomFOV = math.clamp(
                cameraZoomSavedFOV,
                MiscConfig.ZoomFOVMin,
                MiscConfig.ZoomFOVMax
            )
        end
    elseif not keyDown and cameraZoomHeld then
        cameraZoomHeld = false
        if cameraZoomSavedFOV ~= nil and workspace.CurrentCamera then
            workspace.CurrentCamera.FieldOfView = cameraZoomSavedFOV
        end
        cameraZoomSavedFOV = nil
    end

    if cameraZoomHeld and workspace.CurrentCamera then
        workspace.CurrentCamera.FieldOfView = cameraZoomFOV
    end
end)

-- PointerAction gives us the wheel amount directly and avoids depending on
-- InputChanged being delivered to the same input path as the game camera.
Library:GiveSignal(UserInputService.PointerAction:Connect(function(wheel, pan, pinch, gameProcessed)
    if not cameraZoomEnabled or not cameraZoomHeld then return end
    if UserInputService:GetFocusedTextBox() then return end

    if wheel ~= 0 then
        cameraZoomFOV = math.clamp(
            cameraZoomFOV - (wheel * MiscConfig.ZoomFOVStep),
            MiscConfig.ZoomFOVMin,
            MiscConfig.ZoomFOVMax
        )
        if workspace.CurrentCamera then
            workspace.CurrentCamera.FieldOfView = cameraZoomFOV
        end
    end
end))

CameraSection:NewSlider("FOV Step", "How many FOV degrees each mouse-wheel notch changes while zooming.", 10, 1, function(value)
    MiscConfig.ZoomFOVStep = value
end, MiscConfig.ZoomFOVStep)
CameraSection:NewSlider("Minimum Zoom FOV", "Lowest FOV allowed while holding the zoom key. Lower means more zoomed in.", 60, 5, function(value)
    MiscConfig.ZoomFOVMin = value
end, MiscConfig.ZoomFOVMin)
CameraSection:NewSlider("Maximum Zoom FOV", "Highest FOV allowed while holding the zoom key.", 120, 30, function(value)
    MiscConfig.ZoomFOVMax = value
end, MiscConfig.ZoomFOVMax)

local LightingSection = MiscTab:NewSection("Lighting & Atmosphere")
LightingSection:NewToggle("Fullbright", "Brighten the map and remove most fog/shadow darkness.", function(state)
    MiscConfig.FullBright = state
    if state then enforceLighting() else restoreLighting() end
end)
LightingSection:NewToggle("Lock Clock Time", "Keep the game's clock at the selected time.", function(state)
    MiscConfig.ClockTimeEnabled = state
    if state then enforceLighting() else restoreLighting() end
end)
LightingSection:NewSlider("Clock Time", "Set the locked world time from 0 to 24 hours.", 24, 0, function(value)
    MiscConfig.ClockTime = value
    MiscConfig.ClockTimeEnabled = true
    enforceLighting()
end, MiscConfig.ClockTime)
LightingSection:NewToggle("Remove Grass", "Disable Terrain decoration/grass.", function(state)
    MiscConfig.RemoveGrass = state
    pcall(function() workspace.Terrain.Decoration = not state end)
end)
LightingSection:NewToggle("Remove Foliage", "Hide common leaf, foliage, and bush parts.", function(state)
    MiscConfig.RemoveFoliage = state
    setFoliageRemoval(state)
end)

local WorldExtras = MiscTab:NewSection("World ESP")
WorldExtras:NewToggle("Container ESP", "Show nearby crates, boxes, bags, and containers.", function(state)
    MiscConfig.ContainerESP = state
end)
WorldExtras:NewSlider("Container Render Distance", "Maximum container ESP distance.", 2000, 50, function(value)
    MiscConfig.ContainerMaxDist = value
end, MiscConfig.ContainerMaxDist)

local Keybinds = MiscTab:NewSection("Keybind Settings")

local menuKeyCode = Enum.KeyCode.F1

-- Linoria's menu handler checks Library.ToggleKeybind itself. Use a tiny
-- dedicated KeyPicker-compatible state table instead of replacing it with
-- the UI picker object. This keeps the menu toggle reliable while still
-- allowing the visible key picker to change the actual menu key.
Library.ToggleKeybind = {
    Type = "KeyPicker",
    Value = menuKeyCode.Name
}

local menuKeybind = Keybinds:NewKeybind(
    "Toggle Menu",
    "Key used to open or close kus-hook ProjectDelta.",
    menuKeyCode,
    function() end,
    "Toggle",
    function(newKey)
        if typeof(newKey) == "EnumItem" and newKey.EnumType == Enum.KeyCode then
            menuKeyCode = newKey
            Library.ToggleKeybind.Value = newKey.Name
            keybindLabel.Text = "Toggle Menu  [" .. newKey.Name .. "]  Toggle"
        end
    end,
    true
)

Keybinds:NewToggle(
    "Display Keybinds",
    "Show FPS, ping, and the keybinds inside the same overlay.",
    setKeybindDisplay
)

--==================================================
-- PLAYERS
--==================================================

local PlayersTab = Window:NewTab("Players")
local ViewerSection = PlayersTab:NewSection("Inventory Viewer")
ViewerSection:NewToggle("Inventory Viewer", "Show the selected player's inventory in the target HUD.", function(state)
    PlayerViewerConfig.InventoryViewerEnabled = state
end)
ViewerSection:NewToggle("Target HUD", "Show target health, weapon, speed, distance, and inventory.", function(state)
    PlayerViewerConfig.TargetHUDEnabled = state
end)
ViewerSection:NewButton("Reset Target HUD Position", "Move the target HUD back to its default position.", function()
    viewerFrame.Position = UDim2.new(0.5, 200, 0.5, -110)
end)

local HackerSection = PlayersTab:NewSection("Hacker Detector")
HackerSection:NewToggle("Speedhack Alert", "Warn when another player stays above the selected movement speed.", function(state)
    MiscConfig.HackerDetector = state
end)
HackerSection:NewSlider("Speed Threshold", "Movement speed threshold in studs per second.", 80, 25, function(value)
    MiscConfig.HackerSpeedThreshold = value
end, MiscConfig.HackerSpeedThreshold)
HackerSection:NewSlider("Min Duration", "How long the threshold must be exceeded before an alert.", 2.0, 0.5, function(value)
    MiscConfig.HackerSpeedDuration = value
end, MiscConfig.HackerSpeedDuration)

--==================================================
-- SETTINGS
--==================================================

local SettingsTab = Window:NewTab("Settings")
local Profiles = SettingsTab:NewSection("Profiles")

--==================================================
-- PROFILE / CONFIG SYSTEM
--==================================================

local CONFIG_ROOT = "KUSU"
local CONFIG_DIR = CONFIG_ROOT .. "/Configs"
local CONFIG_INDEX = CONFIG_DIR .. "/profiles.json"
local activeProfile = "Default"
local profileNames = { "Default" }
local profileDropdown
local profileNameInput = "Default"
local profileBusy = false

local function ensureConfigFolders()
    -- Executors differ here: some expose isfolder, some only makefolder.
    if not makefolder and not isfolder then
        return false
    end

    if isfolder and isfolder(CONFIG_ROOT) and isfolder(CONFIG_DIR) then
        return true
    end

    if makefolder then
        pcall(function() makefolder(CONFIG_ROOT) end)
        pcall(function() makefolder(CONFIG_DIR) end)
    end

    if isfolder then
        return isfolder(CONFIG_ROOT) and isfolder(CONFIG_DIR)
    end

    -- If the executor has no isfolder API, assume makefolder succeeded.
    return true
end

local function safeProfileName(name)
    name = tostring(name or ""):gsub("[%c%/%\\:%*%?%\"%<%>%|]", "_")
    name = name:gsub("%.%.+", ".")
    name = name:match("^%s*(.-)%s*$")
    if name == "" then name = "Default" end
    return name:sub(1, 48)
end

local function profilePath(name)
    return CONFIG_DIR .. "/" .. safeProfileName(name) .. ".json"
end

local function encodeValue(value)
    local kind = typeof(value)
    if kind == "Color3" then
        return { __type = "Color3", R = value.R, G = value.G, B = value.B }
    elseif kind == "EnumItem" then
        return { __type = "EnumItem", EnumType = tostring(value.EnumType), Name = value.Name }
    elseif kind == "table" then
        local out = {}
        for k, v in pairs(value) do
            local key = tostring(k)
            out[key] = encodeValue(v)
        end
        return out
    end
    return value
end

local function decodeValue(value)
    if type(value) ~= "table" then return value end

    if value.__type == "Color3" then
        return Color3.new(
            tonumber(value.R) or 1,
            tonumber(value.G) or 1,
            tonumber(value.B) or 1
        )
    elseif value.__type == "EnumItem" then
        local enumObject = Enum[value.EnumType]
        if enumObject then
            local ok, result = pcall(function()
                return enumObject[value.Name]
            end)
            if ok and result then return result end
        end
        return nil
    end

    local out = {}
    for k, v in pairs(value) do
        out[k] = decodeValue(v)
    end
    return out
end

local function copyInto(destination, source)
    if type(destination) ~= "table" or type(source) ~= "table" then return end
    for key in pairs(destination) do
        if source[key] == nil then
            -- Keep newly-added settings at their current/default values.
        end
    end
    for key, value in pairs(source) do
        if type(value) == "table" and type(destination[key]) == "table" then
            copyInto(destination[key], value)
        elseif destination[key] ~= nil then
            destination[key] = value
        end
    end
end

local function syncConfigUI()
    local function setToggle(name, value)
        local control = ToggleControls[name]
        if control and control.SetValue then
            pcall(function() control:SetValue(value == true) end)
        end
    end

    local function setSlider(name, value)
        local control = SliderControls[name]
        if control and control.SetValue and tonumber(value) ~= nil then
            pcall(function() control:SetValue(tonumber(value)) end)
        end
    end

    local function setDropdown(name, value)
        local control = DropdownControls[name]
        if control and control.SetValue and value ~= nil then
            pcall(function() control:SetValue(value) end)
        end
    end

    setToggle("Enable Camera Aimbot", AimbotConfig.Enabled)
    setDropdown("Target Bone", AimbotConfig.Bone)
    setSlider("Aimbot FOV", AimbotConfig.FOV)
    setSlider("Smoothness", AimbotConfig.Smoothness)
    setToggle("Draw FOV Circle", AimbotConfig.DrawFOV)
    setToggle("Target NPCs / AI", AimbotConfig.TargetNPCs)
    setToggle("Wall Check (Visible Only)", AimbotConfig.WallCheck)
    setToggle("Lead Target Prediction", AimbotConfig.Prediction)

    setToggle("Flight", flightEnabled)
    setSlider("Flight Speed", flightSpeed)

    setToggle("Player ESP", VisualConfig.PlayerESP)
    setToggle("Boxes", VisualConfig.ESPBoxes)
    setToggle("Health Bar", VisualConfig.ESPHealthBar)
    setToggle("Names", VisualConfig.ESPNames)
    setToggle("Distance", VisualConfig.ESPDistance)
    setToggle("Tracers", VisualConfig.ESPTracers)
    setSlider("Player Max Distance", VisualConfig.PlayerMaxDist)
    setToggle("NPC ESP", VisualConfig.NPC_ESP)
    setSlider("NPC Max Distance", VisualConfig.NPCMaxDist)
    setToggle("Vehicle ESP", VisualConfig.Vehicle_ESP)
    setSlider("Vehicle Max Distance", VisualConfig.VehicleMaxDist)
    setToggle("Dropped Item ESP", VisualConfig.DroppedItemESP)
    setSlider("Dropped Item Max Distance", VisualConfig.DroppedItemMaxDist)
    setToggle("Extraction ESP", VisualConfig.ExtractionESP)
    setSlider("Extraction Max Distance", VisualConfig.ExtractionMaxDist)
    setToggle("Trap ESP", VisualConfig.TrapESP)
    setSlider("Trap Max Distance", VisualConfig.TrapMaxDist)

    setToggle("Bullet Tracers", CombatVisualConfig.BulletTracers)
    setToggle("Hit Markers", CombatVisualConfig.HitMarkers)
    setToggle("Hit Sound", CombatVisualConfig.HitSound)
    setDropdown("Sound Style", CombatVisualConfig.SelectedHitSound)
    setSlider("Sound Volume", CombatVisualConfig.HitSoundVolume)
    setToggle("Hit Logs", CombatVisualConfig.HitLogsEnabled)
    setSlider("Log Lifetime", CombatVisualConfig.HitLogsLifetime)
    setSlider("Log Text Size", CombatVisualConfig.HitLogsSize)

    setToggle("No Recoil", GunModsConfig.NoRecoil)
    setToggle("No Bullet Drop", GunModsConfig.NoDrop)
    setToggle("No Drag", GunModsConfig.NoDrag)
    setToggle("Instant Aim / Zoom", GunModsConfig.InstantAim)

    setToggle("Third Person Mode", MiscConfig.ThirdPerson)
    setSlider("Camera Distance", MiscConfig.ThirdPersonDist)
    setSlider("FOV Step", MiscConfig.ZoomFOVStep)
    setSlider("Minimum Zoom FOV", MiscConfig.ZoomFOVMin)
    setSlider("Maximum Zoom FOV", MiscConfig.ZoomFOVMax)
    setToggle("Fullbright", MiscConfig.FullBright)
    setToggle("Lock Clock Time", MiscConfig.ClockTimeEnabled)
    setSlider("Clock Time", MiscConfig.ClockTime)
    setToggle("Remove Grass", MiscConfig.RemoveGrass)
    setToggle("Remove Foliage", MiscConfig.RemoveFoliage)
    setToggle("Container ESP", MiscConfig.ContainerESP)
    setSlider("Container Render Distance", MiscConfig.ContainerMaxDist)
    setToggle("Speedhack Alert", MiscConfig.HackerDetector)
    setSlider("Speed Threshold", MiscConfig.HackerSpeedThreshold)
    setSlider("Min Duration", MiscConfig.HackerSpeedDuration)

    setToggle("Inventory Viewer", PlayerViewerConfig.InventoryViewerEnabled)
    setToggle("Target HUD", PlayerViewerConfig.TargetHUDEnabled)
    setToggle("Automatic Save on Edit", MiscConfig.AutoSave)

    updateCameraZoom()
    enforceLighting()
    ApplyAmmoMods()
end

local function getConfigData()
    return encodeValue({
        Version = 2,
        FlightSpeed = flightSpeed,
        AimbotConfig = AimbotConfig,
        GunModsConfig = GunModsConfig,
        VisualConfig = VisualConfig,
        CombatVisualConfig = CombatVisualConfig,
        PlayerViewerConfig = PlayerViewerConfig,
        MiscConfig = MiscConfig,
        MenuScale = menuScale,
    })
end

local function refreshProfileList()
    profileNames = { "Default" }
    if isfile and readfile then
        local ok, raw = pcall(function()
            if isfile(CONFIG_INDEX) then return readfile(CONFIG_INDEX) end
            return nil
        end)
        if ok and raw then
            local okDecode, data = pcall(function()
                return HttpService:JSONDecode(raw)
            end)
            if okDecode and type(data) == "table" then
                profileNames = {}
                local seen = {}
                for _, name in ipairs(data) do
                    name = safeProfileName(name)
                    if not seen[name] then
                        seen[name] = true
                        table.insert(profileNames, name)
                    end
                end
                if not seen["Default"] then table.insert(profileNames, 1, "Default") end
            end
        end
    end
end

local function saveProfileIndex()
    if not writefile then return false end
    ensureConfigFolders()
    local ok = pcall(function()
        writefile(CONFIG_INDEX, HttpService:JSONEncode(profileNames))
    end)
    return ok
end

local function saveProfile(name, silent)
    if profileBusy or not writefile then return false end
    profileBusy = true

    name = safeProfileName(name)
    if not ensureConfigFolders() then
        profileBusy = false
        warn("[KUSU] Cannot create config folder. Your executor does not provide a working makefolder/isfolder API.")
        return false
    end

    local ok, err = pcall(function()
        writefile(profilePath(name), HttpService:JSONEncode(getConfigData()))
    end)

    if ok then
        local exists = false
        for _, existing in ipairs(profileNames) do
            if existing == name then exists = true break end
        end
        if not exists then table.insert(profileNames, name) end
        table.sort(profileNames, function(a, b)
            if a == "Default" then return true end
            if b == "Default" then return false end
            return a:lower() < b:lower()
        end)
        saveProfileIndex()
        activeProfile = name
        profileNameInput = name
        if profileDropdown then
            if profileDropdown.SetValues then
                pcall(function() profileDropdown:SetValues(profileNames) end)
            end
            if profileDropdown.SetValue then
                pcall(function() profileDropdown:SetValue(name) end)
            end
        end
        if not silent then print("[KUSU] Saved config: " .. name) end
    else
        warn("[KUSU] Failed to save config:", err)
    end

    profileBusy = false
    return ok
end

local function loadProfile(name, silent)
    if profileBusy or not readfile or not isfile then return false end
    profileBusy = true
    name = safeProfileName(name)
    local path = profilePath(name)

    local ok, decoded = pcall(function()
        if not isfile(path) then return nil end
        return decodeValue(HttpService:JSONDecode(readfile(path)))
    end)

    if ok and type(decoded) == "table" then
        if decoded.FlightSpeed ~= nil then
            flightSpeed = tonumber(decoded.FlightSpeed) or flightSpeed
            Flight:SetSpeed(flightSpeed)
        end
        if decoded.AimbotConfig then copyInto(AimbotConfig, decoded.AimbotConfig) end
        if decoded.GunModsConfig then copyInto(GunModsConfig, decoded.GunModsConfig) end
        if decoded.VisualConfig then copyInto(VisualConfig, decoded.VisualConfig) end
        if decoded.CombatVisualConfig then copyInto(CombatVisualConfig, decoded.CombatVisualConfig) end
        if decoded.PlayerViewerConfig then copyInto(PlayerViewerConfig, decoded.PlayerViewerConfig) end
        if decoded.MiscConfig then copyInto(MiscConfig, decoded.MiscConfig) end
        if decoded.MenuScale then
            menuScale = tonumber(decoded.MenuScale) or menuScale
            setMenuScale(menuScale * 100)
        end

        activeProfile = name
        profileNameInput = name
        if profileDropdown and profileDropdown.SetValue then
            pcall(function() profileDropdown:SetValue(name) end)
        end

        syncConfigUI()
        if not silent then print("[KUSU] Loaded config: " .. name) end
        profileBusy = false
        return true
    end

    if not silent then warn("[KUSU] Config not found or invalid: " .. name) end
    profileBusy = false
    return false
end

local function deleteProfile(name)
    if not delfile then return false end
    name = safeProfileName(name)
    if name == "Default" then
        warn("[KUSU] Default config cannot be deleted.")
        return false
    end

    local ok = pcall(function()
        local path = profilePath(name)
        if isfile and isfile(path) then delfile(path) end
    end)
    if not ok then return false end

    for i = #profileNames, 1, -1 do
        if profileNames[i] == name then table.remove(profileNames, i) end
    end
    saveProfileIndex()
    activeProfile = "Default"
    profileNameInput = "Default"
    if profileDropdown then
        if profileDropdown.SetValues then
            pcall(function() profileDropdown:SetValues(profileNames) end)
        end
        if profileDropdown.SetValue then
            pcall(function() profileDropdown:SetValue("Default") end)
        end
    end
    return true
end

refreshProfileList()

-- Create a clean Default profile the first time the profile system is used.
-- An existing Default is never overwritten automatically.
if writefile and not (isfile and isfile(profilePath("Default"))) then
    saveProfile("Default", true)
end

Profiles:NewTextBox(
    "Config Name",
    "Name used when saving a profile. Existing names are overwritten.",
    function(value)
        profileNameInput = safeProfileName(value)
    end
)

profileDropdown = Profiles:NewDropdown(
    "Saved Configs",
    "Choose one of your saved profiles.",
    profileNames,
    function(value)
        activeProfile = safeProfileName(value)
        profileNameInput = activeProfile
    end
)

Profiles:NewButton(
    "Save Config",
    "Save every kus-hook ProjectDelta setting into the selected config name.",
    function()
        saveProfile(profileNameInput ~= "" and profileNameInput or activeProfile)
    end
)

Profiles:NewButton(
    "Load Config",
    "Load every saved kus-hook ProjectDelta setting from the selected config.",
    function()
        loadProfile(activeProfile)
    end
)

Profiles:NewButton(
    "New Config",
    "Create a separate config using the name entered above and save the current settings into it.",
    function()
        local name = safeProfileName(profileNameInput)
        if name == "Default" and profileNameInput ~= "Default" then
            warn("[KUSU] Invalid config name.")
            return
        end

        -- Creating a config means actually writing the file.
        -- This also refreshes the dropdown so the new config appears immediately.
        if saveProfile(name) then
            print("[KUSU] Created config: " .. name)
        end
    end
)

Profiles:NewButton(
    "Delete Config",
    "Delete the selected saved config. Default is protected.",
    function()
        deleteProfile(activeProfile)
    end
)

Profiles:NewToggle(
    "Automatic Save on Edit",
    "Automatically update the active config after supported setting changes.",
    function(state)
        MiscConfig.AutoSave = state
        if state then
            saveProfile(activeProfile, true)
        end
    end
)

-- Keep the old single-file path working for people who already used it.
Profiles:NewButton(
    "Migrate Old Config",
    "Import the old ProjectDelta_Config.json into the Default profile.",
    function()
        local oldPath = CONFIG_ROOT .. "/ProjectDelta_Config.json"
        if not readfile or not isfile or not isfile(oldPath) then
            warn("[KUSU] No old config found.")
            return
        end
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(oldPath))
        end)
        if not ok or type(data) ~= "table" then
            warn("[KUSU] Old config is invalid.")
            return
        end
        if data.FlightSpeed then flightSpeed = tonumber(data.FlightSpeed) or flightSpeed; Flight:SetSpeed(flightSpeed) end
        if data.AimbotFOV then AimbotConfig.FOV = data.AimbotFOV end
        if data.AimbotSmoothness then AimbotConfig.Smoothness = data.AimbotSmoothness end
        if data.NoRecoil ~= nil then GunModsConfig.NoRecoil = data.NoRecoil end
        if data.NoDrop ~= nil then GunModsConfig.NoDrop = data.NoDrop end
        if data.NoDrag ~= nil then GunModsConfig.NoDrag = data.NoDrag end
        if data.ThirdPerson ~= nil then MiscConfig.ThirdPerson = data.ThirdPerson end
        if data.ThirdPersonDist then MiscConfig.ThirdPersonDist = data.ThirdPersonDist end
        if data.FullBright ~= nil then MiscConfig.FullBright = data.FullBright end
        if data.ClockTime then MiscConfig.ClockTime = data.ClockTime end
        if data.ContainerESP ~= nil then MiscConfig.ContainerESP = data.ContainerESP end
        if data.ContainerMaxDist then MiscConfig.ContainerMaxDist = data.ContainerMaxDist end
        saveProfile("Default")
        updateCameraZoom()
        enforceLighting()
        ApplyAmmoMods()
    end
)

--==================================================
-- UI
--==================================================

local UITab = Window:NewTab("UI")

local UIControls = UITab:NewSection("Menu Controls")

UIControls:NewSlider(
    "Menu Scale",
    "Resize the kus-hook ProjectDelta menu",
    150,
    75,
    setMenuScale,
    100
)

UIControls:NewButton(
    "Toggle Menu",
    "Show or hide the kus-hook ProjectDelta menu",
    toggleMenu
)

local ServerActions = UITab:NewSection("Server Actions")

ServerActions:NewButton(
    "Rejoin Server",
    "Reconnect to the current Roblox server",
    rejoinServer
)

ServerActions:NewButton(
    "Destroy Menu",
    "Remove the kus-hook ProjectDelta menu",
    destroyMenu
)

local Theme = UITab:NewSection("Theme")

Theme:NewColorPicker(
    "Scheme Color",
    "Change the kus-hook ProjectDelta accent color",
    pink,
    function(color)
        Library.AccentColor = color
        Library:UpdateColorsUsingRegistry()
    end
)

Theme:NewColorPicker(
    "Background Color",
    "Change the menu background color",
    theme.Background,
    function(color)
        Library.BackgroundColor = color
        Library:UpdateColorsUsingRegistry()
    end
)

Theme:NewColorPicker(
    "Header Color",
    "Change the menu header color",
    theme.Header,
    function(color)
        Library.MainColor = color
        Library:UpdateColorsUsingRegistry()
    end
)

Theme:NewColorPicker(
    "Element Color",
    "Change element colors",
    theme.ElementColor,
    function(color)
        Library.MainColor = color
        Library:UpdateColorsUsingRegistry()
    end
)

setMenuScale(menuScale * 100)
keybindLabel.Text = "Toggle Menu  [" .. menuKeyCode.Name .. "]"

print("[KUSU] Linoria menu loaded :3")
