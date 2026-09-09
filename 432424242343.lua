local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")

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
    Title = "KUSU",
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.15
})

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

            function section:NewButton(name, _, callback)
                groupbox:AddButton({
                    Text = name,
                    Func = callback
                })
            end

            function section:NewToggle(name, _, callback)
                groupbox:AddToggle(name, {
                    Text = name,
                    Default = false,
                    Callback = callback
                })
            end

            function section:NewSlider(name, _, maximum, minimum, callback, defaultValue)
                groupbox:AddSlider(name, {
                    Text = name,
                    Default = defaultValue or minimum,
                    Min = minimum,
                    Max = maximum,
                    Rounding = 0,
                    Callback = callback
                })
            end

            function section:NewTextBox(name, _, callback)
                groupbox:AddInput(name, {
                    Text = name,
                    Default = "",
                    Callback = callback
                })
            end

            function section:NewDropdown(name, _, options, callback)
                groupbox:AddDropdown(name, {
                    Text = name,
                    Values = options,
                    Default = options[1],
                    Callback = callback
                })
            end

            function section:NewKeybind(name, _, key, callback)
                if key == Enum.KeyCode.RightShift then
                    groupbox:AddLabel(name .. ": RightShift")
                    return
                end

                local toggle = groupbox:AddToggle(name, {
                    Text = name,
                    Default = false,
                    Callback = function() end
                })

                local toggleInner = toggle.TextLabel.Parent
                local toggleOuter = toggleInner.Parent
                toggle.TextLabel.Text = ""
                toggleInner.BackgroundTransparency = 1
                toggleInner.BorderSizePixel = 0
                toggleOuter.BackgroundTransparency = 1
                toggleOuter.BorderSizePixel = 0

                local keyPicker
                local keyState = false
                local previousMode

                toggle:AddKeyPicker(name, {
                    Text = name,
                    Default = key.Name,
                    Mode = "Toggle",
                    Modes = { "Toggle", "Hold", "Always" },
                    Callback = function() end
                })

                local optionStore = getgenv and getgenv().Options
                keyPicker = optionStore and optionStore[name]
                if not keyPicker then
                    warn("[KUSU] Could not create keybind:", name)
                    return toggle
                end

                previousMode = keyPicker.Mode

                function keyPicker:ResetState()
                    keyState = false
                end

                local function matchesKey(input)
                    if input.UserInputType == Enum.UserInputType.Keyboard then
                        return input.KeyCode.Name == keyPicker.Value
                    end

                    return false
                end

                Library:GiveSignal(UserInputService.InputBegan:Connect(function(input, processed)
                    if processed or not matchesKey(input) then
                        return
                    end

                    if keyPicker.Mode == "Hold" then
                        keyState = true
                        callback(true)
                    elseif keyPicker.Mode == "Always" then
                        return
                    else
                        keyState = not keyState
                        callback(keyState)
                    end
                end))

                Library:GiveSignal(UserInputService.InputEnded:Connect(function(input)
                    if keyPicker.Mode == "Hold" and matchesKey(input) then
                        keyState = false
                        callback(false)
                    end
                end))

                Library:GiveSignal(RunService.RenderStepped:Connect(function()
                    local mode = keyPicker.Mode
                    if mode == previousMode then
                        return
                    end

                    previousMode = mode
                    keyState = mode == "Always"
                    callback(keyState)
                end))

                return keyPicker
            end

            function section:NewColorPicker(name, _, default, callback)
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
    Speed = 70,
    Enabled = false
}

local player = Players.LocalPlayer
local inputState = {}
local flightHeartbeatConnection
local flightBeganConnection
local flightEndedConnection
local savedAutoRotate
local flightAttachment
local flightForce

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

    if flightForce then
        flightForce:Destroy()
        flightForce = nil
    end

    if flightAttachment then
        flightAttachment:Destroy()
        flightAttachment = nil
    end
end

local function setFlightInput(input, isDown)
    local key = input.KeyCode
    if key == Enum.KeyCode.W or key == Enum.KeyCode.A or key == Enum.KeyCode.S
        or key == Enum.KeyCode.D or key == Enum.KeyCode.Space or key == Enum.KeyCode.LeftControl then
        inputState[key] = isDown
    end
end

local function syncFlightInputState()
    for _, key in ipairs({
        Enum.KeyCode.W,
        Enum.KeyCode.A,
        Enum.KeyCode.S,
        Enum.KeyCode.D,
        Enum.KeyCode.Space,
        Enum.KeyCode.LeftControl
    }) do
        inputState[key] = UserInputService:IsKeyDown(key)
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

end

function Flight:Start()
    if self.Active then
        return
    end

    local humanoid = getFlightHumanoid()
    local root = getFlightRoot()

    if not root or not humanoid then
        return
    end

    self.Active = true
    savedAutoRotate = humanoid.AutoRotate
    humanoid.AutoRotate = false

    flightAttachment = Instance.new("Attachment")
    flightAttachment.Name = "KusuFlightAttachment"
    flightAttachment.Parent = root

    flightForce = Instance.new("VectorForce")
    flightForce.Name = "KusuFlightGravityCompensation"
    flightForce.Attachment0 = flightAttachment
    flightForce.ApplyAtCenterOfMass = true
    flightForce.RelativeTo = Enum.ActuatorRelativeTo.World
    flightForce.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity, 0)
    flightForce.Parent = root

    flightBeganConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if not gameProcessed then
            setFlightInput(input, true)
        end
    end)

    flightEndedConnection = UserInputService.InputEnded:Connect(function(input)
        setFlightInput(input, false)
    end)

    syncFlightInputState()

    flightHeartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
        local rootPart = getFlightRoot()
        local currentHumanoid = getFlightHumanoid()

        if not rootPart
            or not currentHumanoid
            or currentHumanoid.Health <= 0 then
            self:Stop()
            return
        end

        local direction = getFlightDirection()

        if direction.Magnitude > 0 then
            rootPart.AssemblyLinearVelocity = direction * self.Speed

            local horizontalDirection = Vector3.new(direction.X, 0, direction.Z)
            if horizontalDirection.Magnitude > 0 then
                local targetCFrame = CFrame.lookAt(
                    rootPart.Position,
                    rootPart.Position + horizontalDirection.Unit
                )
                local turnAlpha = 1 - math.exp(-10 * deltaTime)
                rootPart.CFrame = rootPart.CFrame:Lerp(targetCFrame, turnAlpha)
            end
        else
            rootPart.AssemblyLinearVelocity = Vector3.zero
        end
    end)
end

function Flight:Toggle(state)
    if state == nil then
        state = not self.Active
    end

    if state and not self.Enabled then
        return
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
keybindOverlay.Name = "KusuKeybinds"
keybindOverlay.AnchorPoint = Vector2.new(1, 0)
keybindOverlay.Position = UDim2.new(1, -12, 0, 12)
keybindOverlay.Size = UDim2.fromOffset(220, 72)
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

local keybindLabel = Instance.new("TextLabel")
keybindLabel.Position = UDim2.fromOffset(8, 30)
keybindLabel.Size = UDim2.new(1, -16, 0, 22)
keybindLabel.BackgroundTransparency = 1
keybindLabel.Text = "Toggle Menu  [RightShift]"
keybindLabel.TextColor3 = pink
keybindLabel.TextSize = 13
keybindLabel.Font = Enum.Font.Code
keybindLabel.TextXAlignment = Enum.TextXAlignment.Left
keybindLabel.Parent = keybindOverlay

local function setKeybindDisplay(enabled)
    keybindOverlay.Visible = enabled
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

local MainTab = Window:NewTab("Main")
local General = MainTab:NewSection("General")
General:NewLabel("KUSU")
General:NewLabel("UI configuration menu")
General:NewButton("Print Status", "Prints current UI settings", function()
    print("[KUSU] UI is running.")
end)

local Profile = MainTab:NewSection("Profile")
Profile:NewTextBox("Profile Name", "Set a local profile name", function(value)
    print("[KUSU] Profile:", value)
end)
Profile:NewDropdown("Profile Preset", "Choose a UI preset", {
    "Default", "Soft Pink", "Dark", "Custom"
}, function(value)
    print("[KUSU] Preset:", value)
end)

local PlayerTab = Window:NewTab("Player")
local flightEnabled = false
local flightActive = false
local flightSpeed = 70
local flightKeybind

local PlayerSection = PlayerTab:NewSection("Player")
PlayerSection:NewToggle("Example Toggle", "UI-only example toggle", function(state)
    print("[KUSU] Example Toggle:", state)
end)
PlayerSection:NewSlider("Example Slider", "UI-only example value", 100, 0, function(value)
    print("[KUSU] Example Slider:", value)
end)
local Movement = PlayerTab:NewSection("Movement")
Movement:NewToggle("Flight", "UI-only flight setting", function(state)
    flightEnabled = state
    Flight.Enabled = state

    if state and flightKeybind and flightKeybind.Mode == "Always" then
        flightActive = true
        Flight:SetSpeed(flightSpeed)
        Flight:Toggle(true)
    else
        flightActive = false
        if flightKeybind then
            flightKeybind:ResetState()
        end
        Flight:Toggle(false)
    end
end)
Movement:NewSlider("Flight Speed", "UI-only flight speed", 250, 10, function(value)
    flightSpeed = value
    Flight:SetSpeed(value)
end, 70)
flightKeybind = Movement:NewKeybind("Flight Keybind", "Right-click to choose Toggle or Hold", Enum.KeyCode.F, function(state)
    if not flightEnabled then
        return
    end

    flightActive = state
    Flight:SetSpeed(flightSpeed)
    Flight:Toggle(flightActive)
end)

local VisualsTab = Window:NewTab("Visuals")
local Visuals = VisualsTab:NewSection("Visuals")
Visuals:NewToggle("Visuals Enabled", "UI-only visual setting", function(state)
    print("[KUSU] Visuals Enabled:", state)
end)
Visuals:NewColorPicker("Accent Color", "Change the menu accent color", pink, function(color)
    Library.AccentColor = color
    Library:UpdateColorsUsingRegistry()
end)
local Effects = VisualsTab:NewSection("Effects")
Effects:NewToggle("UI Effects", "Toggle decorative UI effects", function(state)
    print("[KUSU] UI Effects:", state)
end)
Effects:NewSlider("Effect Intensity", "0-100", 100, 0, function(value)
    print("[KUSU] Effect Intensity:", value)
end)

local MiscTab = Window:NewTab("Misc")
local Keybinds = MiscTab:NewSection("Keybinds")
Keybinds:NewKeybind("Toggle Menu", "Toggle the KUSU menu", Enum.KeyCode.RightShift, toggleMenu)
Keybinds:NewButton("Toggle Menu", "Show or hide the KUSU menu", toggleMenu)
Keybinds:NewToggle("Display Keybinds", "Show FPS, ping, and active keybinds on screen", setKeybindDisplay)

local UITab = Window:NewTab("UI")
local UIControls = UITab:NewSection("Menu Controls")
UIControls:NewSlider("Menu Scale", "Resize the KUSU menu", 150, 75, setMenuScale)
UIControls:NewButton("Toggle Menu", "Show or hide the KUSU menu", toggleMenu)

local ServerActions = UITab:NewSection("Server Actions")
ServerActions:NewButton("Rejoin Server", "Reconnect to the current Roblox server", rejoinServer)
ServerActions:NewButton("Destroy Menu", "Remove the KUSU menu", destroyMenu)

local Theme = UITab:NewSection("Theme")
Theme:NewColorPicker("Scheme Color", "Change the KUSU accent color", pink, function(color)
    Library.AccentColor = color
    Library:UpdateColorsUsingRegistry()
end)
Theme:NewColorPicker("Background Color", "Change the menu background color", theme.Background, function(color)
    Library.BackgroundColor = color
    Library:UpdateColorsUsingRegistry()
end)
Theme:NewColorPicker("Header Color", "Change the menu header color", theme.Header, function(color)
    Library.MainColor = color
    Library:UpdateColorsUsingRegistry()
end)
Theme:NewColorPicker("Element Color", "Change element colors", theme.ElementColor, function(color)
    Library.MainColor = color
    Library:UpdateColorsUsingRegistry()
end)

setMenuScale(menuScale * 100)
print("[KUSU] Linoria menu loaded :3")
