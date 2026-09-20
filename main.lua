-- ============================================================
--  PRISON LIFE CHEAT | SOLAR/BETTER EXECUTOR COMPATIBLE
--  Tabs: Aim, Main, Rage, Settings
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- ============================================================
--  STATE
-- ============================================================
local Config = {
    -- AIM
    SilentAimEnabled   = true,
    SilentAimFOV       = 120,
    TeamCheck          = true,
    ShowCircle         = true,
    CircleColor        = Color3.fromRGB(255, 60, 60),
    OnetapEnabled      = true,
    HitsoundEnabled    = true,
    HitsoundId         = 139452805868562,

    -- MAIN
    FogEnabled         = false,
    FogStart           = 0,
    FogEnd             = 200,
    FogColor           = Color3.fromRGB(180, 200, 220),
    FogDensity         = 0.15,

    -- RAGE
    SpinEnabled        = false,
    SpinSpeed          = 20,

    -- SETTINGS
    MenuKey            = Enum.KeyCode.RightShift,
}

-- ============================================================
--  TEAM UTILITY
-- ============================================================
local function getLocalTeam()
    local char = LocalPlayer.Character
    if not char then return nil end
    -- Prison Life stores team in humanoid description or team property
    local team = LocalPlayer.Team
    if team then return team.Name end
    return nil
end

local function isEnemy(player)
    if player == LocalPlayer then return false end
    if not Config.TeamCheck then return true end
    local myTeam   = getLocalTeam()
    local theirTeam = player.Team and player.Team.Name or nil
    if not myTeam or not theirTeam then return true end
    -- Criminals shoot Guards, Guards shoot Criminals
    if myTeam == "Criminals" and theirTeam == "Guards"   then return true end
    if myTeam == "Guards"    and theirTeam == "Criminals" then return true end
    return false
end

-- ============================================================
--  CLOSEST ENEMY IN FOV
-- ============================================================
local function getClosestEnemy()
    local bestPlayer, bestDist = nil, Config.SilentAimFOV
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

    for _, plr in ipairs(Players:GetPlayers()) do
        if not isEnemy(plr) then continue end
        local char = plr.Character
        if not char then continue end
        local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
        local hum   = char:FindFirstChildOfClass("Humanoid")
        if not torso or not hum or hum.Health <= 0 then continue end

        local screenPos, onScreen = Camera:WorldToViewportPoint(torso.Position)
        if not onScreen then continue end

        -- distance from screen center (FOV circle logic)
        local dist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
        if dist < bestDist then
            bestDist   = dist
            bestPlayer = plr
        end
    end
    return bestPlayer
end

-- ============================================================
--  HITSOUND
-- ============================================================
local HitsoundSound = Instance.new("Sound")
HitsoundSound.SoundId = "rbxassetid://" .. Config.HitsoundId
HitsoundSound.Volume  = 0.6
HitsoundSound.Parent  = LocalPlayer.PlayerGui

local function playHitsound()
    if not Config.HitsoundEnabled then return end
    HitsoundSound:Stop()
    HitsoundSound.SoundId = "rbxassetid://" .. Config.HitsoundId
    HitsoundSound:Play()
end

-- ============================================================
--  ONETAP — SHOTGUN → AK47 CYCLE
--  Prison Life weapons: "Shotgun", "AK-47", "M4A1" etc.
-- ============================================================
local OnetapState   = { cycling = false }
local ONETAP_PRIMARY   = "Shotgun"
local ONETAP_SECONDARY = "AK-47"

local function equipWeaponByName(name)
    local char      = LocalPlayer.Character
    if not char then return end
    local backpack  = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not backpack then return end
    local tool = backpack:FindFirstChild(name) or char:FindFirstChild(name)
    if tool then
        LocalPlayer.Character.Humanoid:EquipTool(tool)
    end
end

local function onetapCycle()
    if not Config.OnetapEnabled or OnetapState.cycling then return end
    OnetapState.cycling = true
    equipWeaponByName(ONETAP_PRIMARY)
    task.wait(0.05)
    -- fire is triggered by silent aim redirect, swap immediately after
    task.wait(0.18)
    equipWeaponByName(ONETAP_SECONDARY)
    task.wait(0.5)
    OnetapState.cycling = false
end

-- ============================================================
--  SILENT AIM — redirect bullet origin via Camera CFrame
-- ============================================================
local OriginalIndex = nil

local function enableSilentAim()
    if not gethook then return end -- executor check
    local oldncf = newcclosure(function(self, ...)
        return OriginalIndex(self, ...)
    end)
    -- Hook MouseButton1Down to redirect aim
end

-- Lightweight silent aim via WorldRoot:FindPartOnRay redirect
local silentConnection
local function connectSilentAim()
    if silentConnection then silentConnection:Disconnect() end
    silentConnection = RunService.RenderStepped:Connect(function()
        if not Config.SilentAimEnabled then return end
        local enemy = getClosestEnemy()
        if not enemy then return end
        local char  = enemy.Character
        if not char then return end
        local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
        if not torso then return end
        -- Redirect mouse hit to torso position
        -- Compatible with Solar/Solara/Synapse X / Electron
        if Mouse then
            local cf = CFrame.new(torso.Position)
            -- Some executors expose mouse:SetTarget — use if available
            if Mouse["SetTarget"] then
                Mouse:SetTarget(torso, torso.Position)
            else
                -- Universal: override mouse.Hit via __newindex hook where supported
                pcall(function()
                    Mouse.Hit = cf
                end)
            end
        end
    end)
end
connectSilentAim()

-- ============================================================
--  FOV / TARGET CIRCLE (Drawing API — Solar/Synapse/Electron)
-- ============================================================
local fovCircle, targetCircle

if Drawing then
    fovCircle = Drawing.new("Circle")
    fovCircle.Radius    = Config.SilentAimFOV
    fovCircle.Color     = Color3.fromRGB(255, 255, 255)
    fovCircle.Thickness = 1
    fovCircle.Filled    = false
    fovCircle.Visible   = true
    fovCircle.NumSides  = 64

    targetCircle = Drawing.new("Circle")
    targetCircle.Radius    = 18
    targetCircle.Color     = Config.CircleColor
    targetCircle.Thickness = 2
    targetCircle.Filled    = false
    targetCircle.Visible   = false
    targetCircle.NumSides  = 48
end

RunService.RenderStepped:Connect(function()
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

    if fovCircle then
        fovCircle.Position = center
        fovCircle.Radius   = Config.SilentAimFOV
        fovCircle.Visible  = Config.SilentAimEnabled
    end

    if targetCircle then
        local enemy = Config.SilentAimEnabled and getClosestEnemy() or nil
        if enemy and enemy.Character then
            local torso = enemy.Character:FindFirstChild("Torso")
                       or enemy.Character:FindFirstChild("UpperTorso")
            if torso then
                local sp, onScreen = Camera:WorldToViewportPoint(torso.Position)
                targetCircle.Visible  = onScreen and Config.ShowCircle
                targetCircle.Position = Vector2.new(sp.X, sp.Y)
                targetCircle.Color    = Config.CircleColor
            else
                targetCircle.Visible = false
            end
        else
            targetCircle.Visible = false
        end
    end
end)

-- ============================================================
--  HITSOUND TRIGGER — detect HP drop on enemies
-- ============================================================
local function watchEnemyHealth(player)
    local function connectHum()
        local char = player.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        hum.HealthChanged:Connect(function(newHp)
            if newHp < hum.MaxHealth then
                playHitsound()
            end
        end)
    end
    connectHum()
    player.CharacterAdded:Connect(connectHum)
end

for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer then watchEnemyHealth(plr) end
end
Players.PlayerAdded:Connect(function(plr)
    watchEnemyHealth(plr)
end)

-- ============================================================
--  SPIN (Rage Tab)
-- ============================================================
local spinConnection
local function updateSpin()
    if spinConnection then spinConnection:Disconnect(); spinConnection = nil end
    if not Config.SpinEnabled then return end
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local baseAngle = 0
    spinConnection = RunService.RenderStepped:Connect(function(dt)
        baseAngle = (baseAngle + Config.SpinSpeed) % 360
        hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(Config.SpinSpeed), 0)
    end)
end

-- ============================================================
--  FOG SHADERS (Main Tab)
-- ============================================================
local function applyFog()
    local lighting = game:GetService("Lighting")
    local atmo = lighting:FindFirstChildOfClass("Atmosphere")
    if Config.FogEnabled then
        lighting.FogEnd    = Config.FogEnd
        lighting.FogStart  = Config.FogStart
        lighting.FogColor  = Config.FogColor
        if atmo then
            atmo.Density   = Config.FogDensity
        end
    else
        lighting.FogEnd    = 100000
        lighting.FogStart  = 0
        if atmo then
            atmo.Density   = 0.395
        end
    end
end

-- ============================================================
--  NEVERLOSE-STYLE GUI
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name            = "PrisonLifeMenu"
ScreenGui.ResetOnSpawn    = false
ScreenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset  = true

if syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
    ScreenGui.Parent = game:GetService("CoreGui")
elseif gethui then
    ScreenGui.Parent = gethui()
else
    ScreenGui.Parent = game:GetService("CoreGui")
end

-- ── PALETTE ────────────────────────────────────────────────
local C = {
    bg         = Color3.fromRGB(12,  12,  16 ),
    surface    = Color3.fromRGB(18,  18,  24 ),
    panel      = Color3.fromRGB(22,  22,  30 ),
    border     = Color3.fromRGB(40,  40,  58 ),
    accent     = Color3.fromRGB(108, 92,  231),
    accentHov  = Color3.fromRGB(130, 116, 255),
    accentDim  = Color3.fromRGB(60,  50,  130),
    text       = Color3.fromRGB(230, 230, 240),
    textDim    = Color3.fromRGB(120, 118, 140),
    red        = Color3.fromRGB(255, 60,  80 ),
    green      = Color3.fromRGB(60,  210, 130),
    tabActive  = Color3.fromRGB(108, 92,  231),
    tabInact   = Color3.fromRGB(28,  28,  38 ),
    toggle_on  = Color3.fromRGB(108, 92,  231),
    toggle_off = Color3.fromRGB(38,  38,  52 ),
    slider_bg  = Color3.fromRGB(28,  28,  40 ),
    slider_fill= Color3.fromRGB(108, 92,  231),
    input_bg   = Color3.fromRGB(20,  20,  28 ),
}

-- ── HELPERS ────────────────────────────────────────────────
local function makeTween(obj, props, t, style, dir)
    style = style or Enum.EasingStyle.Quart
    dir   = dir   or Enum.EasingDirection.Out
    return TweenService:Create(obj, TweenInfo.new(t or 0.18, style, dir), props)
end

local function addRound(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 6)
    c.Parent = parent
    return c
end

local function addStroke(parent, color, thick)
    local s = Instance.new("UIStroke")
    s.Color     = color or C.border
    s.Thickness = thick or 1
    s.Parent    = parent
    return s
end

local function addPadding(parent, px, py)
    local p = Instance.new("UIPadding")
    p.PaddingLeft   = UDim.new(0, px or 8)
    p.PaddingRight  = UDim.new(0, px or 8)
    p.PaddingTop    = UDim.new(0, py or 6)
    p.PaddingBottom = UDim.new(0, py or 6)
    p.Parent = parent
    return p
end

local function label(parent, text, size, color, font, xalign)
    local l = Instance.new("TextLabel")
    l.Text              = text
    l.TextSize          = size  or 13
    l.TextColor3        = color or C.text
    l.Font              = font  or Enum.Font.GothamMedium
    l.TextXAlignment    = xalign or Enum.TextXAlignment.Left
    l.BackgroundTransparency = 1
    l.Size              = UDim2.new(1, 0, 0, size and size + 6 or 19)
    l.Parent            = parent
    return l
end

-- ── MAIN WINDOW ────────────────────────────────────────────
local Window = Instance.new("Frame")
Window.Name             = "Window"
Window.Size             = UDim2.new(0, 560, 0, 380)
Window.Position         = UDim2.new(0.5, -280, 0.5, -190)
Window.BackgroundColor3 = C.bg
Window.ClipsDescendants = true
Window.Parent           = ScreenGui
addRound(Window, 10)
addStroke(Window, C.border, 1)

-- subtle gradient on window
local winGrad = Instance.new("UIGradient")
winGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(22, 22, 32)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(10, 10, 14)),
})
winGrad.Rotation = 120
winGrad.Parent   = Window

-- ── TITLE BAR ──────────────────────────────────────────────
local TitleBar = Instance.new("Frame")
TitleBar.Size             = UDim2.new(1, 0, 0, 42)
TitleBar.BackgroundColor3 = C.surface
TitleBar.ZIndex           = 3
TitleBar.Parent           = Window
addRound(TitleBar, 10)

-- bottom corners square so it merges with body
local TitleBarFix = Instance.new("Frame")
TitleBarFix.Size             = UDim2.new(1, 0, 0, 10)
TitleBarFix.Position         = UDim2.new(0, 0, 1, -10)
TitleBarFix.BackgroundColor3 = C.surface
TitleBarFix.BorderSizePixel  = 0
TitleBarFix.ZIndex           = 3
TitleBarFix.Parent           = TitleBar

addStroke(TitleBar, C.border, 1)

-- accent line under title
local AccentLine = Instance.new("Frame")
AccentLine.Size             = UDim2.new(0, 80, 0, 2)
AccentLine.Position         = UDim2.new(0, 14, 1, -1)
AccentLine.BackgroundColor3 = C.accent
AccentLine.BorderSizePixel  = 0
AccentLine.ZIndex           = 4
AccentLine.Parent           = TitleBar
addRound(AccentLine, 2)

local TitleIcon = Instance.new("TextLabel")
TitleIcon.Text              = "⚡"
TitleIcon.TextSize          = 15
TitleIcon.Size              = UDim2.new(0, 24, 0, 24)
TitleIcon.Position          = UDim2.new(0, 12, 0.5, -12)
TitleIcon.BackgroundTransparency = 1
TitleIcon.Font              = Enum.Font.GothamBold
TitleIcon.TextColor3        = C.accent
TitleIcon.ZIndex            = 4
TitleIcon.Parent            = TitleBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Text             = "Prison Life"
TitleLabel.TextSize         = 14
TitleLabel.Font             = Enum.Font.GothamBold
TitleLabel.TextColor3       = C.text
TitleLabel.BackgroundTransparency = 1
TitleLabel.Size             = UDim2.new(0, 120, 1, 0)
TitleLabel.Position         = UDim2.new(0, 38, 0, 0)
TitleLabel.TextXAlignment   = Enum.TextXAlignment.Left
TitleLabel.ZIndex           = 4
TitleLabel.Parent           = TitleBar

local SubLabel = Instance.new("TextLabel")
SubLabel.Text               = "v1.0  |  Solar"
SubLabel.TextSize           = 11
SubLabel.Font               = Enum.Font.Gotham
SubLabel.TextColor3         = C.textDim
SubLabel.BackgroundTransparency = 1
SubLabel.Size               = UDim2.new(0, 100, 1, 0)
SubLabel.Position           = UDim2.new(0, 140, 0, 0)
SubLabel.TextXAlignment     = Enum.TextXAlignment.Left
SubLabel.ZIndex             = 4
SubLabel.Parent             = TitleBar

-- drag
local dragging, dragStart, startPos = false, nil, nil
TitleBar.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging  = true
        dragStart = inp.Position
        startPos  = Window.Position
    end
end)
TitleBar.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)
UserInputService.InputChanged:Connect(function(inp)
    if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = inp.Position - dragStart
        Window.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

-- ── TAB BAR ────────────────────────────────────────────────
local TabBar = Instance.new("Frame")
TabBar.Size             = UDim2.new(0, 110, 1, -42)
TabBar.Position         = UDim2.new(0, 0, 0, 42)
TabBar.BackgroundColor3 = C.surface
TabBar.ZIndex           = 2
TabBar.Parent           = Window

local TabBarFix = Instance.new("Frame")
TabBarFix.Size             = UDim2.new(0, 1, 1, 0)
TabBarFix.Position         = UDim2.new(1, -1, 0, 0)
TabBarFix.BackgroundColor3 = C.border
TabBarFix.BorderSizePixel  = 0
TabBarFix.ZIndex           = 2
TabBarFix.Parent           = TabBar

local TabList = Instance.new("Frame")
TabList.Size            = UDim2.new(1, 0, 1, 0)
TabList.BackgroundTransparency = 1
TabList.ZIndex          = 3
TabList.Parent          = TabBar

local TabListLayout = Instance.new("UIListLayout")
TabListLayout.SortOrder      = Enum.SortOrder.LayoutOrder
TabListLayout.Padding        = UDim.new(0, 2)
TabListLayout.Parent         = TabList
addPadding(TabList, 6, 8)

-- ── CONTENT AREA ───────────────────────────────────────────
local ContentArea = Instance.new("Frame")
ContentArea.Size             = UDim2.new(1, -110, 1, -42)
ContentArea.Position         = UDim2.new(0, 110, 0, 42)
ContentArea.BackgroundColor3 = C.panel
ContentArea.ZIndex           = 2
ContentArea.Parent           = Window

-- ── TAB SYSTEM ─────────────────────────────────────────────
local Tabs       = {}
local TabButtons = {}
local ActiveTab  = nil

local TAB_NAMES = {"Aim", "Main", "Rage", "Settings"}
local TAB_ICONS = {"🎯", "🌫️", "💀", "⚙️"}

local function setActiveTab(name)
    ActiveTab = name
    for tname, page in pairs(Tabs) do
        page.Visible = (tname == name)
    end
    for tname, btn in pairs(TabButtons) do
        local isActive = (tname == name)
        makeTween(btn, {
            BackgroundColor3 = isActive and C.accentDim or Color3.fromRGB(0,0,0),
            BackgroundTransparency = isActive and 0 or 1,
        }, 0.15):Play()
        btn.TextColor3 = isActive and C.text or C.textDim
    end
end

for i, tabName in ipairs(TAB_NAMES) do
    -- page
    local page = Instance.new("ScrollingFrame")
    page.Name                  = tabName
    page.Size                  = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency= 1
    page.ScrollBarThickness    = 3
    page.ScrollBarImageColor3  = C.accent
    page.CanvasSize            = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize   = Enum.AutomaticSize.Y
    page.Visible               = false
    page.ZIndex                = 3
    page.Parent                = ContentArea
    addPadding(page, 12, 10)

    local pageLayout = Instance.new("UIListLayout")
    pageLayout.SortOrder  = Enum.SortOrder.LayoutOrder
    pageLayout.Padding    = UDim.new(0, 6)
    pageLayout.Parent     = page

    Tabs[tabName] = page

    -- button
    local btn = Instance.new("TextButton")
    btn.Size                  = UDim2.new(1, 0, 0, 32)
    btn.BackgroundTransparency= 1
    btn.Font                  = Enum.Font.GothamMedium
    btn.TextSize              = 13
    btn.TextColor3            = C.textDim
    btn.TextXAlignment        = Enum.TextXAlignment.Left
    btn.Text                  = "  " .. TAB_ICONS[i] .. "  " .. tabName
    btn.ZIndex                = 4
    btn.LayoutOrder           = i
    btn.Parent                = TabList
    addRound(btn, 6)

    btn.MouseEnter:Connect(function()
        if ActiveTab ~= tabName then
            makeTween(btn, {TextColor3 = C.text}, 0.1):Play()
        end
    end)
    btn.MouseLeave:Connect(function()
        if ActiveTab ~= tabName then
            makeTween(btn, {TextColor3 = C.textDim}, 0.1):Play()
        end
    end)
    btn.MouseButton1Click:Connect(function()
        setActiveTab(tabName)
    end)
    TabButtons[tabName] = btn
end

-- ── COMPONENT BUILDERS ─────────────────────────────────────
local function makeSection(parent, title)
    local wrap = Instance.new("Frame")
    wrap.Size             = UDim2.new(1, 0, 0, 0)
    wrap.BackgroundColor3 = C.surface
    wrap.AutomaticSize    = Enum.AutomaticSize.Y
    wrap.ZIndex           = 4
    wrap.Parent           = parent
    addRound(wrap, 8)
    addStroke(wrap, C.border, 1)
    addPadding(wrap, 10, 8)

    local wLayout = Instance.new("UIListLayout")
    wLayout.SortOrder = Enum.SortOrder.LayoutOrder
    wLayout.Padding   = UDim.new(0, 6)
    wLayout.Parent    = wrap

    if title then
        local hdr = Instance.new("Frame")
        hdr.Size             = UDim2.new(1, 0, 0, 22)
        hdr.BackgroundTransparency = 1
        hdr.LayoutOrder      = 0
        hdr.ZIndex           = 5
        hdr.Parent           = wrap

        local hl = Instance.new("Frame")
        hl.Size             = UDim2.new(0, 3, 0, 14)
        hl.Position         = UDim2.new(0, 0, 0.5, -7)
        hl.BackgroundColor3 = C.accent
        hl.BorderSizePixel  = 0
        hl.ZIndex           = 6
        hl.Parent           = hdr
        addRound(hl, 2)

        local ht = Instance.new("TextLabel")
        ht.Text              = title
        ht.TextSize          = 11
        ht.Font              = Enum.Font.GothamBold
        ht.TextColor3        = C.textDim
        ht.BackgroundTransparency = 1
        ht.Size              = UDim2.new(1, -14, 1, 0)
        ht.Position          = UDim2.new(0, 10, 0, 0)
        ht.TextXAlignment    = Enum.TextXAlignment.Left
        ht.ZIndex            = 6
        ht.Parent            = hdr
    end
    return wrap
end

local function makeToggle(parent, text, default, callback, order)
    local row = Instance.new("Frame")
    row.Size             = UDim2.new(1, 0, 0, 28)
    row.BackgroundTransparency = 1
    row.LayoutOrder      = order or 1
    row.ZIndex           = 5
    row.Parent           = parent

    local lbl = Instance.new("TextLabel")
    lbl.Text             = text
    lbl.TextSize         = 13
    lbl.Font             = Enum.Font.GothamMedium
    lbl.TextColor3       = C.text
    lbl.BackgroundTransparency = 1
    lbl.Size             = UDim2.new(1, -48, 1, 0)
    lbl.TextXAlignment   = Enum.TextXAlignment.Left
    lbl.ZIndex           = 6
    lbl.Parent           = row

    local track = Instance.new("Frame")
    track.Size            = UDim2.new(0, 36, 0, 18)
    track.Position        = UDim2.new(1, -38, 0.5, -9)
    track.BackgroundColor3= default and C.toggle_on or C.toggle_off
    track.ZIndex          = 6
    track.Parent          = row
    addRound(track, 9)
    addStroke(track, C.border, 1)

    local knob = Instance.new("Frame")
    knob.Size             = UDim2.new(0, 12, 0, 12)
    knob.Position         = default and UDim2.new(1, -15, 0.5, -6) or UDim2.new(0, 3, 0.5, -6)
    knob.BackgroundColor3 = Color3.new(1,1,1)
    knob.ZIndex           = 7
    knob.Parent           = track
    addRound(knob, 6)

    local state = default
    local btn   = Instance.new("TextButton")
    btn.Size              = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text              = ""
    btn.ZIndex            = 8
    btn.Parent            = row

    btn.MouseButton1Click:Connect(function()
        state = not state
        makeTween(track, {BackgroundColor3 = state and C.toggle_on or C.toggle_off}, 0.15):Play()
        makeTween(knob,  {Position = state
            and UDim2.new(1, -15, 0.5, -6)
            or  UDim2.new(0, 3,   0.5, -6)}, 0.15):Play()
        callback(state)
    end)
    return row
end

local function makeSlider(parent, text, min, max, default, callback, order)
    local wrap = Instance.new("Frame")
    wrap.Size             = UDim2.new(1, 0, 0, 44)
    wrap.BackgroundTransparency = 1
    wrap.LayoutOrder      = order or 1
    wrap.ZIndex           = 5
    wrap.Parent           = parent

    local lbl = Instance.new("TextLabel")
    lbl.Text             = text
    lbl.TextSize         = 13
    lbl.Font             = Enum.Font.GothamMedium
    lbl.TextColor3       = C.text
    lbl.BackgroundTransparency = 1
    lbl.Size             = UDim2.new(0.7, 0, 0, 18)
    lbl.TextXAlignment   = Enum.TextXAlignment.Left
    lbl.ZIndex           = 6
    lbl.Parent           = wrap

    local valLbl = Instance.new("TextLabel")
    valLbl.Text          = tostring(default)
    valLbl.TextSize      = 12
    valLbl.Font          = Enum.Font.GothamMedium
    valLbl.TextColor3    = C.accent
    valLbl.BackgroundTransparency = 1
    valLbl.Size          = UDim2.new(0.3, 0, 0, 18)
    valLbl.TextXAlignment= Enum.TextXAlignment.Right
    valLbl.ZIndex        = 6
    valLbl.Parent        = wrap

    local track = Instance.new("Frame")
    track.Size            = UDim2.new(1, 0, 0, 6)
    track.Position        = UDim2.new(0, 0, 0, 26)
    track.BackgroundColor3= C.slider_bg
    track.ZIndex          = 6
    track.Parent          = wrap
    addRound(track, 3)
    addStroke(track, C.border, 1)

    local fill = Instance.new("Frame")
    fill.Size             = UDim2.new((default - min)/(max - min), 0, 1, 0)
    fill.BackgroundColor3 = C.slider_fill
    fill.ZIndex           = 7
    fill.Parent           = track
    addRound(fill, 3)

    local handle = Instance.new("Frame")
    handle.Size           = UDim2.new(0, 12, 0, 12)
    handle.AnchorPoint    = Vector2.new(0.5, 0.5)
    handle.Position       = UDim2.new((default - min)/(max - min), 0, 0.5, 0)
    handle.BackgroundColor3 = Color3.new(1,1,1)
    handle.ZIndex         = 8
    handle.Parent         = track
    addRound(handle, 6)

    local draggingSlider = false
    local function update(input)
        local rel  = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local val  = math.floor(min + (max - min) * rel)
        fill.Size         = UDim2.new(rel, 0, 1, 0)
        handle.Position   = UDim2.new(rel, 0, 0.5, 0)
        valLbl.Text       = tostring(val)
        callback(val)
    end

    track.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingSlider = true
            update(inp)
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingSlider = false
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if draggingSlider and inp.UserInputType == Enum.UserInputType.MouseMovement then
            update(inp)
        end
    end)
    return wrap
end

local function makeInput(parent, text, default, callback, order)
    local wrap = Instance.new("Frame")
    wrap.Size             = UDim2.new(1, 0, 0, 52)
    wrap.BackgroundTransparency = 1
    wrap.LayoutOrder      = order or 1
    wrap.ZIndex           = 5
    wrap.Parent           = parent

    local lbl = label(wrap, text, 13, C.text, Enum.Font.GothamMedium)
    lbl.ZIndex = 6

    local box = Instance.new("TextBox")
    box.Size              = UDim2.new(1, 0, 0, 26)
    box.Position          = UDim2.new(0, 0, 0, 22)
    box.BackgroundColor3  = C.input_bg
    box.TextColor3        = C.text
    box.PlaceholderColor3 = C.textDim
    box.Font              = Enum.Font.Gotham
    box.TextSize          = 12
    box.Text              = tostring(default)
    box.ClearTextOnFocus  = false
    box.ZIndex            = 6
    box.Parent            = wrap
    addRound(box, 5)
    addStroke(box, C.border, 1)
    addPadding(box, 8, 0)

    box.FocusLost:Connect(function()
        callback(box.Text)
    end)
    return wrap
end

local function makeDropdown(parent, text, options, default, callback, order)
    local wrap = Instance.new("Frame")
    wrap.Size             = UDim2.new(1, 0, 0, 52)
    wrap.BackgroundTransparency = 1
    wrap.LayoutOrder      = order or 1
    wrap.ZIndex           = 5
    wrap.ClipsDescendants = false
    wrap.Parent           = parent

    local lbl = label(wrap, text, 13, C.text, Enum.Font.GothamMedium)
    lbl.ZIndex = 6

    local current = default
    local open    = false

    local selected = Instance.new("TextButton")
    selected.Size             = UDim2.new(1, 0, 0, 26)
    selected.Position         = UDim2.new(0, 0, 0, 22)
    selected.BackgroundColor3 = C.input_bg
    selected.TextColor3       = C.text
    selected.Font             = Enum.Font.GothamMedium
    selected.TextSize         = 12
    selected.Text             = "  " .. current
    selected.TextXAlignment   = Enum.TextXAlignment.Left
    selected.ZIndex           = 7
    selected.Parent           = wrap
    addRound(selected, 5)
    addStroke(selected, C.border, 1)

    local arrow = Instance.new("TextLabel")
    arrow.Text            = "▾"
    arrow.TextSize        = 12
    arrow.Font            = Enum.Font.GothamBold
    arrow.TextColor3      = C.textDim
    arrow.BackgroundTransparency = 1
    arrow.Size            = UDim2.new(0, 20, 1, 0)
    arrow.Position        = UDim2.new(1, -22, 0, 0)
    arrow.TextXAlignment  = Enum.TextXAlignment.Center
    arrow.ZIndex          = 8
    arrow.Parent          = selected

    local dropdown = Instance.new("Frame")
    dropdown.Size            = UDim2.new(1, 0, 0, 0)
    dropdown.Position        = UDim2.new(0, 0, 1, 2)
    dropdown.BackgroundColor3= C.surface
    dropdown.ZIndex          = 20
    dropdown.ClipsDescendants= true
    dropdown.Parent          = wrap
    addRound(dropdown, 5)
    addStroke(dropdown, C.border, 1)

    local ddLayout = Instance.new("UIListLayout")
    ddLayout.SortOrder = Enum.SortOrder.LayoutOrder
    ddLayout.Parent    = dropdown

    local function closeDropdown()
        open = false
        makeTween(dropdown, {Size = UDim2.new(1, 0, 0, 0)}, 0.15):Play()
    end

    for _, opt in ipairs(options) do
        local item = Instance.new("TextButton")
        item.Size             = UDim2.new(1, 0, 0, 24)
        item.BackgroundTransparency = 1
        item.Font             = Enum.Font.GothamMedium
        item.TextSize         = 12
        item.TextColor3       = C.textDim
        item.Text             = "  " .. opt
        item.TextXAlignment   = Enum.TextXAlignment.Left
        item.ZIndex           = 21
        item.Parent           = dropdown

        item.MouseEnter:Connect(function()
            makeTween(item, {TextColor3 = C.text}, 0.1):Play()
        end)
        item.MouseLeave:Connect(function()
            makeTween(item, {TextColor3 = C.textDim}, 0.1):Play()
        end)
        item.MouseButton1Click:Connect(function()
            current = opt
            selected.Text = "  " .. opt
            callback(opt)
            closeDropdown()
        end)
    end

    selected.MouseButton1Click:Connect(function()
        open = not open
        local targetH = open and (#options * 24) or 0
        makeTween(dropdown, {Size = UDim2.new(1, 0, 0, targetH)}, 0.15):Play()
    end)
    return wrap
end

-- ── BUILD TABS ─────────────────────────────────────────────

-- AIM TAB
do
    local p = Tabs["Aim"]

    local aimSection = makeSection(p, "SILENT AIM")
    aimSection.LayoutOrder = 1

    makeToggle(aimSection, "Silent Aim", Config.SilentAimEnabled, function(v)
        Config.SilentAimEnabled = v
        connectSilentAim()
    end, 1)

    makeToggle(aimSection, "Show Target Circle", Config.ShowCircle, function(v)
        Config.ShowCircle = v
    end, 2)

    makeToggle(aimSection, "Team Check", Config.TeamCheck, function(v)
        Config.TeamCheck = v
    end, 3)

    makeSlider(aimSection, "FOV Radius", 10, 400, Config.SilentAimFOV, function(v)
        Config.SilentAimFOV = v
        if fovCircle then fovCircle.Radius = v end
    end, 4)

    local otSection = makeSection(p, "ONETAP")
    otSection.LayoutOrder = 2

    makeToggle(otSection, "Onetap  (Shotgun → AK-47)", Config.OnetapEnabled, function(v)
        Config.OnetapEnabled = v
    end, 1)

    local hsSection = makeSection(p, "HITSOUND")
    hsSection.LayoutOrder = 3

    makeToggle(hsSection, "Hitsound", Config.HitsoundEnabled, function(v)
        Config.HitsoundEnabled = v
    end, 1)

    makeInput(hsSection, "Sound ID", Config.HitsoundId, function(v)
        local id = tonumber(v)
        if id then
            Config.HitsoundId = id
            HitsoundSound.SoundId = "rbxassetid://" .. id
        end
    end, 2)
end

-- MAIN TAB (Fog / Shaders)
do
    local p = Tabs["Main"]

    local fogSection = makeSection(p, "FOG SHADER")
    fogSection.LayoutOrder = 1

    makeToggle(fogSection, "Enable Fog", Config.FogEnabled, function(v)
        Config.FogEnabled = v
        applyFog()
    end, 1)

    makeSlider(fogSection, "Fog Start", 0, 500, Config.FogStart, function(v)
        Config.FogStart = v
        applyFog()
    end, 2)

    makeSlider(fogSection, "Fog End", 10, 2000, Config.FogEnd, function(v)
        Config.FogEnd = v
        applyFog()
    end, 3)

    makeSlider(fogSection, "Atmosphere Density", 0, 100, math.floor(Config.FogDensity * 100), function(v)
        Config.FogDensity = v / 100
        applyFog()
    end, 4)

    makeDropdown(fogSection, "Fog Preset", {
        "Default", "Dense Fog", "Light Haze", "Night Ambiance", "Crimson"
    }, "Default", function(opt)
        local presets = {
            ["Default"]        = {Color3.fromRGB(180,200,220), 0,   200,  0.15},
            ["Dense Fog"]      = {Color3.fromRGB(160,160,160), 0,   60,   0.6 },
            ["Light Haze"]     = {Color3.fromRGB(220,220,200), 100, 600,  0.08},
            ["Night Ambiance"] = {Color3.fromRGB(20,  20, 60), 0,   150,  0.4 },
            ["Crimson"]        = {Color3.fromRGB(80,  10, 10), 0,   100,  0.3 },
        }
        local pr = presets[opt]
        if pr then
            Config.FogColor   = pr[1]
            Config.FogStart   = pr[2]
            Config.FogEnd     = pr[3]
            Config.FogDensity = pr[4]
            Config.FogEnabled = true
            applyFog()
        end
    end, 5)
end

-- RAGE TAB (Spin)
do
    local p = Tabs["Rage"]

    local spinSection = makeSection(p, "SPIN")
    spinSection.LayoutOrder = 1

    makeToggle(spinSection, "Spin", Config.SpinEnabled, function(v)
        Config.SpinEnabled = v
        updateSpin()
    end, 1)

    makeSlider(spinSection, "Spin Speed", 1, 60, Config.SpinSpeed, function(v)
        Config.SpinSpeed = v
    end, 2)
end

-- SETTINGS TAB
do
    local p = Tabs["Settings"]

    local uiSection = makeSection(p, "INTERFACE")
    uiSection.LayoutOrder = 1

    makeDropdown(uiSection, "Menu Key", {
        "RightShift", "Insert", "F4", "Delete", "Home"
    }, "RightShift", function(opt)
        local map = {
            RightShift = Enum.KeyCode.RightShift,
            Insert     = Enum.KeyCode.Insert,
            F4         = Enum.KeyCode.F4,
            Delete     = Enum.KeyCode.Delete,
            Home       = Enum.KeyCode.Home,
        }
        Config.MenuKey = map[opt] or Enum.KeyCode.RightShift
    end, 1)

    local infoSection = makeSection(p, "INFO")
    infoSection.LayoutOrder = 2
    label(infoSection, "Prison Life Script  •  v1.0", 12, C.textDim):Clone().Parent = infoSection
    label(infoSection, "Solar / Solara / Synapse X / Electron", 11, C.textDim):Clone().Parent = infoSection
end

-- ── OPEN / CLOSE ───────────────────────────────────────────
setActiveTab("Aim")

local menuVisible = true
UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == Config.MenuKey then
        menuVisible = not menuVisible
        makeTween(Window, {
            Size = menuVisible
                and UDim2.new(0, 560, 0, 380)
                or  UDim2.new(0, 560, 0, 0),
        }, 0.2, Enum.EasingStyle.Back, menuVisible
            and Enum.EasingDirection.Out
            or  Enum.EasingDirection.In):Play()
    end
end)

-- onetap fires on mouse click when silent aim has a target
UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        if Config.OnetapEnabled and Config.SilentAimEnabled then
            local enemy = getClosestEnemy()
            if enemy then
                task.spawn(onetapCycle)
            end
        end
    end
end)

print("[PrisonLife] Loaded. Toggle menu: " .. Config.MenuKey.Name)
