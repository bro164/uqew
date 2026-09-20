-- ============================================================
--  PRISON LIFE | FIXED BUILD
--  Solar/Solara/Synapse X/Electron compatible
--  Fixes: silent aim, hitsound (own hits only), onetap names,
--         spin (vehicle isolation + shift fix)
-- ============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Camera           = workspace.CurrentCamera
local LocalPlayer      = Players.LocalPlayer
local Mouse            = LocalPlayer:GetMouse()

-- ============================================================
--  CONFIG
-- ============================================================
local Config = {
    SilentAimEnabled  = true,
    SilentAimFOV      = 120,
    TeamCheck         = true,
    ShowCircle        = true,
    CircleColor       = Color3.fromRGB(255, 60, 60),

    OnetapEnabled     = true,

    HitsoundEnabled   = true,
    HitsoundId        = 139452805868562,

    FogEnabled        = false,
    FogStart          = 0,
    FogEnd            = 200,
    FogColor          = Color3.fromRGB(180, 200, 220),
    FogDensity        = 0.15,

    SpinEnabled       = false,
    SpinSpeed         = 20,

    MenuKey           = Enum.KeyCode.RightShift,
}

-- ============================================================
--  TEAM CHECK
-- ============================================================
local function isEnemy(player)
    if player == LocalPlayer then return false end
    if not Config.TeamCheck then return true end
    local myTeam    = LocalPlayer.Team
    local theirTeam = player.Team
    if not myTeam or not theirTeam then return true end
    if myTeam.Name == "Criminals" and theirTeam.Name == "Police" then return true end
    if myTeam.Name == "Police"    and theirTeam.Name == "Criminals" then return true end
    return false
end

-- ============================================================
--  CLOSEST ENEMY IN FOV
-- ============================================================
local function getTarget()
    local best, bestDist = nil, Config.SilentAimFOV
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    for _, plr in ipairs(Players:GetPlayers()) do
        if not isEnemy(plr) then continue end
        local char = plr.Character
        if not char then continue end
        local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
        local hum   = char:FindFirstChildOfClass("Humanoid")
        if not torso or not hum or hum.Health <= 0 then continue end
        local sp, onScreen = Camera:WorldToViewportPoint(torso.Position)
        if not onScreen then continue end
        local dist = (Vector2.new(sp.X, sp.Y) - center).Magnitude
        if dist < bestDist then
            bestDist = dist
            best     = plr
        end
    end
    return best
end

-- ============================================================
--  SILENT AIM — proper method for Solar/Solara/Synapse/Electron
--  Hooks the WorldRoot raycast that tools use for hit detection
-- ============================================================
local silentTarget = nil  -- the torso Part we redirect to

-- Keep target fresh every frame
RunService.RenderStepped:Connect(function()
    if not Config.SilentAimEnabled then
        silentTarget = nil
        return
    end
    local enemy = getTarget()
    if enemy and enemy.Character then
        silentTarget = enemy.Character:FindFirstChild("Torso")
                    or enemy.Character:FindFirstChild("UpperTorso")
    else
        silentTarget = nil
    end
end)

-- Hook FindPartOnRayWithWhitelist / FindPartOnRay / Raycast
-- Solar and Synapse both expose hookfunction / hookmetamethod
local function hookRaycast()
    local wsmt = getrawmetatable(workspace)
    if not wsmt then return end

    local oldIndex = wsmt.__index
    setreadonly(wsmt, false)

    wsmt.__index = newcclosure(function(self, key)
        -- intercept :FindPartOnRay and :FindPartOnRayWithWhitelist
        if (key == "FindPartOnRay" or key == "FindPartOnRayWithWhitelist") then
            return newcclosure(function(ws, ray, ...)
                if Config.SilentAimEnabled and silentTarget then
                    -- redirect origin + direction toward the torso
                    local newDir = (silentTarget.Position - ray.Origin).Unit * ray.Direction.Magnitude
                    ray = Ray.new(ray.Origin, newDir)
                end
                return oldIndex(ws, key)(ws, ray, ...)
            end)
        end
        return oldIndex(self, key)
    end)

    setreadonly(wsmt, true)
end

-- Raycast() hook (newer executor / game path)
local function hookRaycastMethod()
    if not hookfunction then return end
    local oldRaycast = workspace.Raycast
    hookfunction(workspace.Raycast, newcclosure(function(ws, origin, direction, params)
        if Config.SilentAimEnabled and silentTarget then
            direction = (silentTarget.Position - origin).Unit * direction.Magnitude
        end
        return oldRaycast(ws, origin, direction, params)
    end))
end

pcall(hookRaycast)
pcall(hookRaycastMethod)

-- ============================================================
--  HITSOUND — fires ONLY when LocalPlayer's tool deals damage
--  Tracks health of enemies; compares against last known value
--  but gates on: did LocalPlayer fire in the last 0.8s?
-- ============================================================
local HitSound = Instance.new("Sound")
HitSound.SoundId = "rbxassetid://" .. Config.HitsoundId
HitSound.Volume  = 0.7
HitSound.Parent  = game:GetService("SoundService")

local lastFiredAt  = 0  -- tick() when LocalPlayer last fired a tool
local FIRE_WINDOW  = 0.8 -- seconds; hits within this window count as ours

-- Detect when LocalPlayer fires (tool Activated)
local function watchLocalTools()
    local function connectTool(tool)
        if not tool:IsA("Tool") then return end
        tool.Activated:Connect(function()
            lastFiredAt = tick()
        end)
    end
    local char = LocalPlayer.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do connectTool(t) end
        char.ChildAdded:Connect(connectTool)
    end
    LocalPlayer.CharacterAdded:Connect(function(c)
        for _, t in ipairs(c:GetChildren()) do connectTool(t) end
        c.ChildAdded:Connect(connectTool)
    end)
end
watchLocalTools()

-- Watch enemy health; play hitsound only if we fired recently
local enemyHealthCache = {}

local function watchEnemy(player)
    local function connectHum()
        local char = player.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        enemyHealthCache[player] = hum.Health
        hum.HealthChanged:Connect(function(newHp)
            local prev = enemyHealthCache[player] or newHp
            if newHp < prev then
                -- only play if LocalPlayer fired within the window
                if (tick() - lastFiredAt) <= FIRE_WINDOW then
                    HitSound:Stop()
                    HitSound.SoundId = "rbxassetid://" .. Config.HitsoundId
                    HitSound:Play()
                end
            end
            enemyHealthCache[player] = newHp
        end)
    end
    connectHum()
    player.CharacterAdded:Connect(connectHum)
end

for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer then watchEnemy(plr) end
end
Players.PlayerAdded:Connect(function(plr)
    watchEnemy(plr)
end)

-- ============================================================
--  ONETAP — Remington 870 → AK-47 / MP5 fallback
-- ============================================================
local ONETAP_SHOTGUN    = "Remington 870"
local ONETAP_SECONDARY  = {"AK-47", "MP5"}  -- tries AK first, MP5 fallback
local otBusy = false

local function equipTool(name)
    local char     = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not char or not backpack then return false end
    local tool = char:FindFirstChild(name) or backpack:FindFirstChild(name)
    if tool then
        LocalPlayer.Character.Humanoid:EquipTool(tool)
        return true
    end
    return false
end

local function onetap()
    if otBusy or not Config.OnetapEnabled then return end
    if not getTarget() then return end
    otBusy = true
    equipTool(ONETAP_SHOTGUN)
    task.wait(0.06)
    -- fire moment handled by mouse click; swap immediately after
    task.wait(0.16)
    local swapped = equipTool(ONETAP_SECONDARY[1])
    if not swapped then equipTool(ONETAP_SECONDARY[2]) end
    task.wait(0.45)
    otBusy = false
end

UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        if Config.OnetapEnabled and Config.SilentAimEnabled and getTarget() then
            task.spawn(onetap)
        end
    end
end)

-- ============================================================
--  SPIN — isolated from vehicle + Shift key fix
-- ============================================================
local spinConn = nil

local function isInVehicle()
    local char = LocalPlayer.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    -- If HRP's parent is a VehicleSeat or we have a VehicleSeat as an ancestor
    local seat = char:FindFirstChildOfClass("VehicleSeat")
    if seat then return true end
    -- Check if seated in any external vehicle
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then return true end
    return false
end

local function startSpin()
    if spinConn then spinConn:Disconnect() end
    spinConn = RunService.Heartbeat:Connect(function()
        -- pause while in vehicle
        if isInVehicle() then return end
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        -- Shift lock fix: detach from camera direction, apply absolute rotation
        hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(Config.SpinSpeed), 0)
    end)
end

local function stopSpin()
    if spinConn then
        spinConn:Disconnect()
        spinConn = nil
    end
end

-- ============================================================
--  FOG
-- ============================================================
local function applyFog()
    local L    = game:GetService("Lighting")
    local atmo = L:FindFirstChildOfClass("Atmosphere")
    if Config.FogEnabled then
        L.FogStart  = Config.FogStart
        L.FogEnd    = Config.FogEnd
        L.FogColor  = Config.FogColor
        if atmo then atmo.Density = Config.FogDensity end
    else
        L.FogEnd = 100000
        L.FogStart = 0
        if atmo then atmo.Density = 0.395 end
    end
end

-- ============================================================
--  DRAWING — FOV circle + target circle
-- ============================================================
local fovCircle, targetCircle

if Drawing then
    fovCircle = Drawing.new("Circle")
    fovCircle.Radius    = Config.SilentAimFOV
    fovCircle.Color     = Color3.fromRGB(255, 255, 255)
    fovCircle.Thickness = 1
    fovCircle.Filled    = false
    fovCircle.NumSides  = 64
    fovCircle.Visible   = true

    targetCircle = Drawing.new("Circle")
    targetCircle.Radius    = 18
    targetCircle.Color     = Config.CircleColor
    targetCircle.Thickness = 2
    targetCircle.Filled    = false
    targetCircle.NumSides  = 48
    targetCircle.Visible   = false
end

RunService.RenderStepped:Connect(function()
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    if fovCircle then
        fovCircle.Position = center
        fovCircle.Radius   = Config.SilentAimFOV
        fovCircle.Visible  = Config.SilentAimEnabled
    end
    if targetCircle then
        if silentTarget and silentTarget.Parent then
            local sp, onScreen = Camera:WorldToViewportPoint(silentTarget.Position)
            targetCircle.Visible  = onScreen and Config.ShowCircle
            targetCircle.Position = Vector2.new(sp.X, sp.Y)
        else
            targetCircle.Visible = false
        end
    end
end)

-- ============================================================
--  NEVERLOSE-STYLE GUI  (same structure, kept intact)
-- ============================================================
local TweenService = game:GetService("TweenService")

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "PrisonLifeMenu"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true

if syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
    ScreenGui.Parent = game:GetService("CoreGui")
elseif gethui then
    ScreenGui.Parent = gethui()
else
    ScreenGui.Parent = game:GetService("CoreGui")
end

local C = {
    bg        = Color3.fromRGB(12,  12,  16),
    surface   = Color3.fromRGB(18,  18,  24),
    panel     = Color3.fromRGB(22,  22,  30),
    border    = Color3.fromRGB(40,  40,  58),
    accent    = Color3.fromRGB(108, 92,  231),
    accentDim = Color3.fromRGB(60,  50,  130),
    text      = Color3.fromRGB(230, 230, 240),
    textDim   = Color3.fromRGB(120, 118, 140),
    tog_on    = Color3.fromRGB(108, 92,  231),
    tog_off   = Color3.fromRGB(38,  38,  52),
    slider_bg = Color3.fromRGB(28,  28,  40),
    input_bg  = Color3.fromRGB(20,  20,  28),
}

local function tw(obj, props, t, s, d)
    return TweenService:Create(obj, TweenInfo.new(t or 0.18,
        s or Enum.EasingStyle.Quart, d or Enum.EasingDirection.Out), props)
end
local function rnd(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 6); c.Parent = p end
local function stk(p, col, th) local s = Instance.new("UIStroke"); s.Color = col or C.border; s.Thickness = th or 1; s.Parent = p end
local function pad(p, x, y) local u = Instance.new("UIPadding"); u.PaddingLeft=UDim.new(0,x or 8); u.PaddingRight=UDim.new(0,x or 8); u.PaddingTop=UDim.new(0,y or 6); u.PaddingBottom=UDim.new(0,y or 6); u.Parent=p end
local function lbl(parent, text, sz, col, fnt, xa)
    local l = Instance.new("TextLabel")
    l.Text=text; l.TextSize=sz or 13; l.TextColor3=col or C.text
    l.Font=fnt or Enum.Font.GothamMedium
    l.TextXAlignment=xa or Enum.TextXAlignment.Left
    l.BackgroundTransparency=1
    l.Size=UDim2.new(1,0,0,(sz or 13)+6)
    l.Parent=parent; return l
end

-- Window
local Win = Instance.new("Frame")
Win.Size=UDim2.new(0,560,0,380); Win.Position=UDim2.new(0.5,-280,0.5,-190)
Win.BackgroundColor3=C.bg; Win.ClipsDescendants=true; Win.Parent=ScreenGui
rnd(Win,10); stk(Win,C.border,1)

local wGrad=Instance.new("UIGradient")
wGrad.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(22,22,32)),ColorSequenceKeypoint.new(1,Color3.fromRGB(10,10,14))})
wGrad.Rotation=120; wGrad.Parent=Win

-- Title bar
local TBar=Instance.new("Frame")
TBar.Size=UDim2.new(1,0,0,42); TBar.BackgroundColor3=C.surface; TBar.ZIndex=3; TBar.Parent=Win
rnd(TBar,10); stk(TBar,C.border,1)

local TBarFix=Instance.new("Frame")
TBarFix.Size=UDim2.new(1,0,0,10); TBarFix.Position=UDim2.new(0,0,1,-10)
TBarFix.BackgroundColor3=C.surface; TBarFix.BorderSizePixel=0; TBarFix.ZIndex=3; TBarFix.Parent=TBar

local AccLine=Instance.new("Frame")
AccLine.Size=UDim2.new(0,80,0,2); AccLine.Position=UDim2.new(0,14,1,-1)
AccLine.BackgroundColor3=C.accent; AccLine.BorderSizePixel=0; AccLine.ZIndex=4; AccLine.Parent=TBar
rnd(AccLine,2)

local function tbLabel(text,size,col,font,x,w,pos,zi)
    local t=Instance.new("TextLabel")
    t.Text=text;t.TextSize=size;t.TextColor3=col;t.Font=font or Enum.Font.Gotham
    t.BackgroundTransparency=1;t.Size=UDim2.new(0,w,1,0)
    t.Position=pos;t.TextXAlignment=x or Enum.TextXAlignment.Left
    t.ZIndex=zi or 4;t.Parent=TBar;return t
end
tbLabel("⚡",15,C.accent,Enum.Font.GothamBold,Enum.TextXAlignment.Center,24,UDim2.new(0,12,0,9),4)
tbLabel("Prison Life",14,C.text,Enum.Font.GothamBold,Enum.TextXAlignment.Left,120,UDim2.new(0,38,0,0),4)
tbLabel("v1.1  |  Solar",11,C.textDim,Enum.Font.Gotham,Enum.TextXAlignment.Left,100,UDim2.new(0,150,0,0),4)

local dragging,dragStart,startPos=false,nil,nil
TBar.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true;dragStart=i.Position;startPos=Win.Position end end)
TBar.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
UserInputService.InputChanged:Connect(function(i) if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then local d=i.Position-dragStart;Win.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y) end end)

-- Tab sidebar
local TBSide=Instance.new("Frame")
TBSide.Size=UDim2.new(0,110,1,-42);TBSide.Position=UDim2.new(0,0,0,42)
TBSide.BackgroundColor3=C.surface;TBSide.ZIndex=2;TBSide.Parent=Win

local Divider=Instance.new("Frame")
Divider.Size=UDim2.new(0,1,1,0);Divider.Position=UDim2.new(1,-1,0,0)
Divider.BackgroundColor3=C.border;Divider.BorderSizePixel=0;Divider.ZIndex=2;Divider.Parent=TBSide

local TBList=Instance.new("Frame")
TBList.Size=UDim2.new(1,0,1,0);TBList.BackgroundTransparency=1;TBList.ZIndex=3;TBList.Parent=TBSide
local TBListL=Instance.new("UIListLayout");TBListL.SortOrder=Enum.SortOrder.LayoutOrder;TBListL.Padding=UDim.new(0,2);TBListL.Parent=TBList
pad(TBList,6,8)

-- Content
local Content=Instance.new("Frame")
Content.Size=UDim2.new(1,-110,1,-42);Content.Position=UDim2.new(0,110,0,42)
Content.BackgroundColor3=C.panel;Content.ZIndex=2;Content.Parent=Win

-- Tab builders
local Tabs,TabBtns,ActiveTab={},{},nil

local function setTab(name)
    ActiveTab=name
    for n,pg in pairs(Tabs) do pg.Visible=(n==name) end
    for n,b  in pairs(TabBtns) do
        local on=(n==name)
        tw(b,{BackgroundColor3=on and C.accentDim or Color3.fromRGB(0,0,0), BackgroundTransparency=on and 0 or 1},0.15):Play()
        b.TextColor3=on and C.text or C.textDim
    end
end

local TAB_NAMES={"Aim","Main","Rage","Settings"}
local TAB_ICONS={"🎯","🌫️","💀","⚙️"}

for i,tabName in ipairs(TAB_NAMES) do
    local pg=Instance.new("ScrollingFrame")
    pg.Name=tabName;pg.Size=UDim2.new(1,0,1,0);pg.BackgroundTransparency=1
    pg.ScrollBarThickness=3;pg.ScrollBarImageColor3=C.accent
    pg.CanvasSize=UDim2.new(0,0,0,0);pg.AutomaticCanvasSize=Enum.AutomaticSize.Y
    pg.Visible=false;pg.ZIndex=3;pg.Parent=Content
    pad(pg,12,10)
    local pL=Instance.new("UIListLayout");pL.SortOrder=Enum.SortOrder.LayoutOrder;pL.Padding=UDim.new(0,6);pL.Parent=pg
    Tabs[tabName]=pg

    local btn=Instance.new("TextButton")
    btn.Size=UDim2.new(1,0,0,32);btn.BackgroundTransparency=1
    btn.Font=Enum.Font.GothamMedium;btn.TextSize=13;btn.TextColor3=C.textDim
    btn.TextXAlignment=Enum.TextXAlignment.Left
    btn.Text="  "..TAB_ICONS[i].."  "..tabName
    btn.ZIndex=4;btn.LayoutOrder=i;btn.Parent=TBList
    rnd(btn,6)
    btn.MouseEnter:Connect(function() if ActiveTab~=tabName then tw(btn,{TextColor3=C.text},0.1):Play() end end)
    btn.MouseLeave:Connect(function() if ActiveTab~=tabName then tw(btn,{TextColor3=C.textDim},0.1):Play() end end)
    btn.MouseButton1Click:Connect(function() setTab(tabName) end)
    TabBtns[tabName]=btn
end

-- Component helpers
local function makeSection(parent,title,order)
    local w=Instance.new("Frame")
    w.Size=UDim2.new(1,0,0,0);w.BackgroundColor3=C.surface
    w.AutomaticSize=Enum.AutomaticSize.Y;w.ZIndex=4
    w.LayoutOrder=order or 1;w.Parent=parent
    rnd(w,8);stk(w,C.border,1);pad(w,10,8)
    local wL=Instance.new("UIListLayout");wL.SortOrder=Enum.SortOrder.LayoutOrder;wL.Padding=UDim.new(0,6);wL.Parent=w
    if title then
        local hdr=Instance.new("Frame");hdr.Size=UDim2.new(1,0,0,22);hdr.BackgroundTransparency=1;hdr.LayoutOrder=0;hdr.ZIndex=5;hdr.Parent=w
        local hl=Instance.new("Frame");hl.Size=UDim2.new(0,3,0,14);hl.Position=UDim2.new(0,0,0.5,-7);hl.BackgroundColor3=C.accent;hl.BorderSizePixel=0;hl.ZIndex=6;hl.Parent=hdr;rnd(hl,2)
        local ht=Instance.new("TextLabel");ht.Text=title;ht.TextSize=11;ht.Font=Enum.Font.GothamBold;ht.TextColor3=C.textDim;ht.BackgroundTransparency=1;ht.Size=UDim2.new(1,-14,1,0);ht.Position=UDim2.new(0,10,0,0);ht.TextXAlignment=Enum.TextXAlignment.Left;ht.ZIndex=6;ht.Parent=hdr
    end
    return w
end

local function makeToggle(parent,text,default,callback,order)
    local row=Instance.new("Frame");row.Size=UDim2.new(1,0,0,28);row.BackgroundTransparency=1;row.LayoutOrder=order or 1;row.ZIndex=5;row.Parent=parent
    local l=Instance.new("TextLabel");l.Text=text;l.TextSize=13;l.Font=Enum.Font.GothamMedium;l.TextColor3=C.text;l.BackgroundTransparency=1;l.Size=UDim2.new(1,-48,1,0);l.TextXAlignment=Enum.TextXAlignment.Left;l.ZIndex=6;l.Parent=row
    local track=Instance.new("Frame");track.Size=UDim2.new(0,36,0,18);track.Position=UDim2.new(1,-38,0.5,-9);track.BackgroundColor3=default and C.tog_on or C.tog_off;track.ZIndex=6;track.Parent=row;rnd(track,9);stk(track,C.border,1)
    local knob=Instance.new("Frame");knob.Size=UDim2.new(0,12,0,12);knob.Position=default and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6);knob.BackgroundColor3=Color3.new(1,1,1);knob.ZIndex=7;knob.Parent=track;rnd(knob,6)
    local state=default
    local btn=Instance.new("TextButton");btn.Size=UDim2.new(1,0,1,0);btn.BackgroundTransparency=1;btn.Text="";btn.ZIndex=8;btn.Parent=row
    btn.MouseButton1Click:Connect(function()
        state=not state
        tw(track,{BackgroundColor3=state and C.tog_on or C.tog_off},0.15):Play()
        tw(knob,{Position=state and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)},0.15):Play()
        callback(state)
    end)
    return row
end

local function makeSlider(parent,text,min,max,default,callback,order)
    local wrap=Instance.new("Frame");wrap.Size=UDim2.new(1,0,0,44);wrap.BackgroundTransparency=1;wrap.LayoutOrder=order or 1;wrap.ZIndex=5;wrap.Parent=parent
    local l=Instance.new("TextLabel");l.Text=text;l.TextSize=13;l.Font=Enum.Font.GothamMedium;l.TextColor3=C.text;l.BackgroundTransparency=1;l.Size=UDim2.new(0.7,0,0,18);l.TextXAlignment=Enum.TextXAlignment.Left;l.ZIndex=6;l.Parent=wrap
    local vl=Instance.new("TextLabel");vl.Text=tostring(default);vl.TextSize=12;vl.Font=Enum.Font.GothamMedium;vl.TextColor3=C.accent;vl.BackgroundTransparency=1;vl.Size=UDim2.new(0.3,0,0,18);vl.TextXAlignment=Enum.TextXAlignment.Right;vl.ZIndex=6;vl.Parent=wrap
    local track=Instance.new("Frame");track.Size=UDim2.new(1,0,0,6);track.Position=UDim2.new(0,0,0,26);track.BackgroundColor3=C.slider_bg;track.ZIndex=6;track.Parent=wrap;rnd(track,3);stk(track,C.border,1)
    local fill=Instance.new("Frame");fill.Size=UDim2.new((default-min)/(max-min),0,1,0);fill.BackgroundColor3=C.accent;fill.ZIndex=7;fill.Parent=track;rnd(fill,3)
    local handle=Instance.new("Frame");handle.Size=UDim2.new(0,12,0,12);handle.AnchorPoint=Vector2.new(0.5,0.5);handle.Position=UDim2.new((default-min)/(max-min),0,0.5,0);handle.BackgroundColor3=Color3.new(1,1,1);handle.ZIndex=8;handle.Parent=track;rnd(handle,6)
    local ds=false
    local function upd(inp)
        local rel=math.clamp((inp.Position.X-track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1)
        local val=math.floor(min+(max-min)*rel)
        fill.Size=UDim2.new(rel,0,1,0);handle.Position=UDim2.new(rel,0,0.5,0);vl.Text=tostring(val);callback(val)
    end
    track.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then ds=true;upd(i) end end)
    UserInputService.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then ds=false end end)
    UserInputService.InputChanged:Connect(function(i) if ds and i.UserInputType==Enum.UserInputType.MouseMovement then upd(i) end end)
    return wrap
end

local function makeInput(parent,text,default,callback,order)
    local wrap=Instance.new("Frame");wrap.Size=UDim2.new(1,0,0,52);wrap.BackgroundTransparency=1;wrap.LayoutOrder=order or 1;wrap.ZIndex=5;wrap.Parent=parent
    lbl(wrap,text,13,C.text,Enum.Font.GothamMedium).ZIndex=6
    local box=Instance.new("TextBox");box.Size=UDim2.new(1,0,0,26);box.Position=UDim2.new(0,0,0,22);box.BackgroundColor3=C.input_bg;box.TextColor3=C.text;box.PlaceholderColor3=C.textDim;box.Font=Enum.Font.Gotham;box.TextSize=12;box.Text=tostring(default);box.ClearTextOnFocus=false;box.ZIndex=6;box.Parent=wrap;rnd(box,5);stk(box,C.border,1);pad(box,8,0)
    box.FocusLost:Connect(function() callback(box.Text) end)
    return wrap
end

local function makeDropdown(parent,text,options,default,callback,order)
    local wrap=Instance.new("Frame");wrap.Size=UDim2.new(1,0,0,52);wrap.BackgroundTransparency=1;wrap.LayoutOrder=order or 1;wrap.ZIndex=5;wrap.ClipsDescendants=false;wrap.Parent=parent
    lbl(wrap,text,13,C.text,Enum.Font.GothamMedium).ZIndex=6
    local open=false
    local sel=Instance.new("TextButton");sel.Size=UDim2.new(1,0,0,26);sel.Position=UDim2.new(0,0,0,22);sel.BackgroundColor3=C.input_bg;sel.TextColor3=C.text;sel.Font=Enum.Font.GothamMedium;sel.TextSize=12;sel.Text="  "..default;sel.TextXAlignment=Enum.TextXAlignment.Left;sel.ZIndex=7;sel.Parent=wrap;rnd(sel,5);stk(sel,C.border,1)
    local arr=Instance.new("TextLabel");arr.Text="▾";arr.TextSize=12;arr.Font=Enum.Font.GothamBold;arr.TextColor3=C.textDim;arr.BackgroundTransparency=1;arr.Size=UDim2.new(0,20,1,0);arr.Position=UDim2.new(1,-22,0,0);arr.TextXAlignment=Enum.TextXAlignment.Center;arr.ZIndex=8;arr.Parent=sel
    local dd=Instance.new("Frame");dd.Size=UDim2.new(1,0,0,0);dd.Position=UDim2.new(0,0,1,2);dd.BackgroundColor3=C.surface;dd.ZIndex=20;dd.ClipsDescendants=true;dd.Parent=wrap;rnd(dd,5);stk(dd,C.border,1)
    local ddL=Instance.new("UIListLayout");ddL.SortOrder=Enum.SortOrder.LayoutOrder;ddL.Parent=dd
    local function closeDd() open=false;tw(dd,{Size=UDim2.new(1,0,0,0)},0.15):Play() end
    for _,opt in ipairs(options) do
        local item=Instance.new("TextButton");item.Size=UDim2.new(1,0,0,24);item.BackgroundTransparency=1;item.Font=Enum.Font.GothamMedium;item.TextSize=12;item.TextColor3=C.textDim;item.Text="  "..opt;item.TextXAlignment=Enum.TextXAlignment.Left;item.ZIndex=21;item.Parent=dd
        item.MouseEnter:Connect(function() tw(item,{TextColor3=C.text},0.1):Play() end)
        item.MouseLeave:Connect(function() tw(item,{TextColor3=C.textDim},0.1):Play() end)
        item.MouseButton1Click:Connect(function() sel.Text="  "..opt;callback(opt);closeDd() end)
    end
    sel.MouseButton1Click:Connect(function() open=not open;tw(dd,{Size=UDim2.new(1,0,0,open and #options*24 or 0)},0.15):Play() end)
    return wrap
end

-- ── BUILD CONTENT ──────────────────────────────────────────

-- AIM
do
    local p=Tabs["Aim"]
    local s1=makeSection(p,"SILENT AIM",1)
    makeToggle(s1,"Silent Aim",Config.SilentAimEnabled,function(v) Config.SilentAimEnabled=v end,1)
    makeToggle(s1,"Show Target Circle",Config.ShowCircle,function(v) Config.ShowCircle=v end,2)
    makeToggle(s1,"Team Check",Config.TeamCheck,function(v) Config.TeamCheck=v end,3)
    makeSlider(s1,"FOV Radius",10,400,Config.SilentAimFOV,function(v) Config.SilentAimFOV=v end,4)

    local s2=makeSection(p,"ONETAP",2)
    makeToggle(s2,"Onetap  (Remington 870 → AK-47 / MP5)",Config.OnetapEnabled,function(v) Config.OnetapEnabled=v end,1)

    local s3=makeSection(p,"HITSOUND",3)
    makeToggle(s3,"Hitsound",Config.HitsoundEnabled,function(v) Config.HitsoundEnabled=v end,1)
    makeInput(s3,"Sound ID",Config.HitsoundId,function(v)
        local id=tonumber(v)
        if id then Config.HitsoundId=id;HitSound.SoundId="rbxassetid://"..id end
    end,2)
end

-- MAIN
do
    local p=Tabs["Main"]
    local s1=makeSection(p,"FOG SHADER",1)
    makeToggle(s1,"Enable Fog",Config.FogEnabled,function(v) Config.FogEnabled=v;applyFog() end,1)
    makeSlider(s1,"Fog Start",0,500,Config.FogStart,function(v) Config.FogStart=v;applyFog() end,2)
    makeSlider(s1,"Fog End",10,2000,Config.FogEnd,function(v) Config.FogEnd=v;applyFog() end,3)
    makeSlider(s1,"Atmosphere Density",0,100,math.floor(Config.FogDensity*100),function(v) Config.FogDensity=v/100;applyFog() end,4)
    makeDropdown(s1,"Fog Preset",{"Default","Dense Fog","Light Haze","Night Ambiance","Crimson"},"Default",function(opt)
        local pr={
            ["Default"]       ={Color3.fromRGB(180,200,220),0,  200, 0.15},
            ["Dense Fog"]     ={Color3.fromRGB(160,160,160),0,  60,  0.6 },
            ["Light Haze"]    ={Color3.fromRGB(220,220,200),100,600, 0.08},
            ["Night Ambiance"]={Color3.fromRGB(20, 20, 60), 0,  150, 0.4 },
            ["Crimson"]       ={Color3.fromRGB(80, 10, 10), 0,  100, 0.3 },
        }
        local v=pr[opt]; if v then Config.FogColor=v[1];Config.FogStart=v[2];Config.FogEnd=v[3];Config.FogDensity=v[4];Config.FogEnabled=true;applyFog() end
    end,5)
end

-- RAGE
do
    local p=Tabs["Rage"]
    local s1=makeSection(p,"SPIN",1)
    makeToggle(s1,"Spin",Config.SpinEnabled,function(v)
        Config.SpinEnabled=v
        if v then startSpin() else stopSpin() end
    end,1)
    makeSlider(s1,"Spin Speed",1,60,Config.SpinSpeed,function(v) Config.SpinSpeed=v end,2)
end

-- SETTINGS
do
    local p=Tabs["Settings"]
    local s1=makeSection(p,"INTERFACE",1)
    makeDropdown(s1,"Menu Key",{"RightShift","Insert","F4","Delete","Home"},"RightShift",function(opt)
        local m={RightShift=Enum.KeyCode.RightShift,Insert=Enum.KeyCode.Insert,F4=Enum.KeyCode.F4,Delete=Enum.KeyCode.Delete,Home=Enum.KeyCode.Home}
        Config.MenuKey=m[opt] or Enum.KeyCode.RightShift
    end,1)
    local s2=makeSection(p,"INFO",2)
    lbl(s2,"Prison Life Script  •  v1.1",12,C.textDim)
    lbl(s2,"Solar / Solara / Synapse X / Electron",11,C.textDim)
end

setTab("Aim")

-- Toggle menu
local menuVisible=true
UserInputService.InputBegan:Connect(function(inp,gp)
    if gp then return end
    if inp.KeyCode==Config.MenuKey then
        menuVisible=not menuVisible
        tw(Win,{Size=menuVisible and UDim2.new(0,560,0,380) or UDim2.new(0,560,0,0)},
            0.2,Enum.EasingStyle.Back,menuVisible and Enum.EasingDirection.Out or Enum.EasingDirection.In):Play()
    end
end)

print("[PrisonLife v1.1] Loaded — toggle: "..Config.MenuKey.Name)
