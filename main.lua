-- ============================================================
--  PRISON LIFE | v1.2 — SOLARA NATIVE BUILD
--  Silent aim via __namecall FireServer hook
--  Hitsound: только от своих выстрелов
--  Onetap: Remington 870 → AK-47 / MP5
--  Spin: без машин, без Shift-краша
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
--  Prison Life реальные имена команд: "Criminals" и "Police"
-- ============================================================
local function isEnemy(player)
    if player == LocalPlayer then return false end
    if not Config.TeamCheck then return true end
    local mt  = LocalPlayer.Team
    local ot  = player.Team
    if not mt or not ot then return true end
    if mt == ot then return false end
    return true
end

-- ============================================================
--  CLOSEST TARGET IN FOV
-- ============================================================
local function getTarget()
    local best, bestDist = nil, Config.SilentAimFOV
    local cx = Camera.ViewportSize.X / 2
    local cy = Camera.ViewportSize.Y / 2
    for _, plr in ipairs(Players:GetPlayers()) do
        if not isEnemy(plr) then continue end
        local char = plr.Character
        if not char then continue end
        local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
        local hum   = char:FindFirstChildOfClass("Humanoid")
        if not torso or not hum or hum.Health <= 0 then continue end
        local sp, vis = Camera:WorldToViewportPoint(torso.Position)
        if not vis then continue end
        local d = math.sqrt((sp.X - cx)^2 + (sp.Y - cy)^2)
        if d < bestDist then
            bestDist = d
            best = plr
        end
    end
    return best
end

local function getTargetTorso()
    local t = getTarget()
    if not t or not t.Character then return nil end
    return t.Character:FindFirstChild("Torso") or t.Character:FindFirstChild("UpperTorso")
end

-- ============================================================
--  SILENT AIM — __namecall hook (Solara / Synapse / Electron)
--  
--  Как это работает:
--  Prison Life оружие стреляет через Tool:Activate() →
--  RemoteEvent:FireServer("shoot", mouseHit, ...)
--  Перехватываем :FireServer, подменяем mouseHit на торс врага
-- ============================================================
local namecallHooked = false

local function hookSilentAim()
    if not getrawmetatable then
        warn("[SA] getrawmetatable недоступен — silent aim не активен")
        return
    end

    local mt = getrawmetatable(game)
    if not mt then return end

    -- разблокируем таблицу
    local ok = pcall(setreadonly, mt, false)
    if not ok then
        -- Solara использует make_writeable на некоторых версиях
        pcall(function()
            if make_writeable then make_writeable(mt, true) end
        end)
    end

    local oldNamecall = mt.__namecall
    if not oldNamecall then
        pcall(setreadonly, mt, true)
        return
    end

    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args   = {...}

        -- Перехватываем только FireServer
        if method == "FireServer" and Config.SilentAimEnabled then
            -- Проверяем: это RemoteEvent внутри оружия LocalPlayer?
            if typeof(self) == "Instance" and self:IsA("RemoteEvent") then
                local char = LocalPlayer.Character
                local tool = char and char:FindFirstChildOfClass("Tool")
                -- RemoteEvent должен быть потомком Tool или его скриптов
                local isOurGun = false
                if tool then
                    -- Быстрая проверка: remote находится в Tool или workspace.Ignore
                    local p = self.Parent
                    while p and p ~= game do
                        if p == tool or p.Name == "Guns" or p.Name == "GunEvent" then
                            isOurGun = true
                            break
                        end
                        p = p.Parent
                    end
                    -- Prison Life использует один глобальный RemoteEvent "shoot" или "Fire"
                    if self.Name == "shoot" or self.Name == "Fire" or self.Name == "Shoot"
                        or self.Name == "GunEvent" or self.Name == "RemoteEvent" then
                        isOurGun = true
                    end
                end

                if isOurGun then
                    local torso = getTargetTorso()
                    if torso then
                        -- args[1] обычно это mouseHit (CFrame) или position (Vector3)
                        -- Prison Life передаёт CFrame позиции попадания
                        if args[1] and typeof(args[1]) == "CFrame" then
                            args[1] = CFrame.new(torso.Position)
                        elseif args[1] and typeof(args[1]) == "Vector3" then
                            args[1] = torso.Position
                        end
                        -- args[2] может быть Part (hit part) — ставим торс
                        if args[2] and typeof(args[2]) == "Instance" then
                            args[2] = torso
                        end
                    end
                end
            end
        end

        return oldNamecall(self, table.unpack(args))
    end)

    pcall(setreadonly, mt, true)
    namecallHooked = true
end

pcall(hookSilentAim)

-- ============================================================
--  HITSOUND — только от LocalPlayer
--  Отслеживаем: LocalPlayer активировал Tool → засекаем время
--  HP врага упал в течении FIRE_WINDOW → хитсаунд
-- ============================================================
local HitSound = Instance.new("Sound")
HitSound.SoundId = "rbxassetid://" .. Config.HitsoundId
HitSound.Volume  = 0.7
HitSound.Parent  = LocalPlayer.PlayerGui  -- PlayerGui стабильнее на Solara

local lastFired   = 0
local FIRE_WINDOW = 0.75

local function trackLocalWeapons()
    local function hookTool(tool)
        if not tool:IsA("Tool") then return end
        tool.Activated:Connect(function()
            lastFired = tick()
        end)
    end
    local function hookChar(char)
        for _, c in ipairs(char:GetChildren()) do hookTool(c) end
        char.ChildAdded:Connect(hookTool)
    end
    if LocalPlayer.Character then hookChar(LocalPlayer.Character) end
    LocalPlayer.CharacterAdded:Connect(hookChar)
end
trackLocalWeapons()

local hpCache = {}
local function watchEnemy(plr)
    local function onChar(char)
        local hum = char:WaitForChild("Humanoid", 5)
        if not hum then return end
        hpCache[plr] = hum.Health
        hum.HealthChanged:Connect(function(hp)
            local prev = hpCache[plr] or hp
            if hp < prev then
                if (tick() - lastFired) <= FIRE_WINDOW and Config.HitsoundEnabled then
                    HitSound:Stop()
                    HitSound.SoundId = "rbxassetid://" .. Config.HitsoundId
                    HitSound:Play()
                end
            end
            hpCache[plr] = hp
        end)
    end
    if plr.Character then onChar(plr.Character) end
    plr.CharacterAdded:Connect(onChar)
end

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then watchEnemy(p) end
end
Players.PlayerAdded:Connect(function(p) watchEnemy(p) end)

-- ============================================================
--  ONETAP — Remington 870 → AK-47 / MP5 fallback
-- ============================================================
local SHOTGUN    = "Remington 870"
local SECONDARIES = {"AK-47", "MP5"}
local otBusy = false

local function equipByName(name)
    local char     = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not char or not backpack then return false end
    local t = char:FindFirstChild(name) or backpack:FindFirstChild(name)
    if t and char:FindFirstChildOfClass("Humanoid") then
        char:FindFirstChildOfClass("Humanoid"):EquipTool(t)
        return true
    end
    return false
end

local function runOnetap()
    if otBusy or not Config.OnetapEnabled then return end
    if not getTarget() then return end
    otBusy = true
    equipByName(SHOTGUN)
    task.wait(0.05)
    task.wait(0.17)
    if not equipByName(SECONDARIES[1]) then
        equipByName(SECONDARIES[2])
    end
    task.wait(0.5)
    otBusy = false
end

UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        if Config.SilentAimEnabled and Config.OnetapEnabled and getTarget() then
            task.spawn(runOnetap)
        end
    end
end)

-- ============================================================
--  SPIN — изолирован от машины + Shift fix
-- ============================================================
local spinConn = nil

local function inVehicle()
    local char = LocalPlayer.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then return true end
    if char:FindFirstChildOfClass("VehicleSeat") then return true end
    return false
end

local function startSpin()
    if spinConn then spinConn:Disconnect() end
    spinConn = RunService.Heartbeat:Connect(function()
        if inVehicle() then return end
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        -- Используем CFrame напрямую, игнорируя camera offset (Shift Lock fix)
        hrp.CFrame = CFrame.new(hrp.Position)
            * CFrame.Angles(0, math.rad(Config.SpinSpeed), 0)
            * CFrame.new(0, 0, 0)
    end)
end

local function stopSpin()
    if spinConn then spinConn:Disconnect(); spinConn = nil end
end

-- ============================================================
--  FOG
-- ============================================================
local function applyFog()
    local L    = game:GetService("Lighting")
    local atmo = L:FindFirstChildOfClass("Atmosphere")
    if Config.FogEnabled then
        L.FogStart = Config.FogStart
        L.FogEnd   = Config.FogEnd
        L.FogColor = Config.FogColor
        if atmo then atmo.Density = Config.FogDensity end
    else
        L.FogEnd   = 100000
        L.FogStart = 0
        if atmo then atmo.Density = 0.395 end
    end
end

-- ============================================================
--  DRAWING — FOV + target circle
-- ============================================================
local fovCircle, targetCircle
local silentTorso = nil

RunService.RenderStepped:Connect(function()
    if Config.SilentAimEnabled then
        silentTorso = getTargetTorso()
    else
        silentTorso = nil
    end
end)

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

    RunService.RenderStepped:Connect(function()
        local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
        if fovCircle then
            fovCircle.Position = center
            fovCircle.Radius   = Config.SilentAimFOV
            fovCircle.Visible  = Config.SilentAimEnabled
        end
        if targetCircle then
            if silentTorso and silentTorso.Parent then
                local sp, vis = Camera:WorldToViewportPoint(silentTorso.Position)
                targetCircle.Visible  = vis and Config.ShowCircle
                targetCircle.Position = Vector2.new(sp.X, sp.Y)
                targetCircle.Color    = Config.CircleColor
            else
                targetCircle.Visible = false
            end
        end
    end)
end

-- ============================================================
--  GUI (neverlose style — полная копия v1.1, без изменений UI)
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "PrisonLifeMenu"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true

-- Solara: gethui() — правильный способ
if gethui then
    ScreenGui.Parent = gethui()
elseif syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
    ScreenGui.Parent = game:GetService("CoreGui")
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

local function tw(o,p,t,s,d) return TweenService:Create(o,TweenInfo.new(t or .18,s or Enum.EasingStyle.Quart,d or Enum.EasingDirection.Out),p) end
local function rnd(p,r) local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,r or 6);c.Parent=p end
local function stk(p,col,th) local s=Instance.new("UIStroke");s.Color=col or C.border;s.Thickness=th or 1;s.Parent=p end
local function pad(p,x,y) local u=Instance.new("UIPadding");u.PaddingLeft=UDim.new(0,x or 8);u.PaddingRight=UDim.new(0,x or 8);u.PaddingTop=UDim.new(0,y or 6);u.PaddingBottom=UDim.new(0,y or 6);u.Parent=p end
local function lbl(parent,text,sz,col,fnt,xa) local l=Instance.new("TextLabel");l.Text=text;l.TextSize=sz or 13;l.TextColor3=col or C.text;l.Font=fnt or Enum.Font.GothamMedium;l.TextXAlignment=xa or Enum.TextXAlignment.Left;l.BackgroundTransparency=1;l.Size=UDim2.new(1,0,0,(sz or 13)+6);l.Parent=parent;return l end

local Win=Instance.new("Frame")
Win.Size=UDim2.new(0,560,0,380);Win.Position=UDim2.new(0.5,-280,0.5,-190)
Win.BackgroundColor3=C.bg;Win.ClipsDescendants=true;Win.Parent=ScreenGui
rnd(Win,10);stk(Win,C.border,1)
local wg=Instance.new("UIGradient");wg.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(22,22,32)),ColorSequenceKeypoint.new(1,Color3.fromRGB(10,10,14))});wg.Rotation=120;wg.Parent=Win

local TBar=Instance.new("Frame");TBar.Size=UDim2.new(1,0,0,42);TBar.BackgroundColor3=C.surface;TBar.ZIndex=3;TBar.Parent=Win;rnd(TBar,10);stk(TBar,C.border,1)
local TBF=Instance.new("Frame");TBF.Size=UDim2.new(1,0,0,10);TBF.Position=UDim2.new(0,0,1,-10);TBF.BackgroundColor3=C.surface;TBF.BorderSizePixel=0;TBF.ZIndex=3;TBF.Parent=TBar
local AL=Instance.new("Frame");AL.Size=UDim2.new(0,80,0,2);AL.Position=UDim2.new(0,14,1,-1);AL.BackgroundColor3=C.accent;AL.BorderSizePixel=0;AL.ZIndex=4;AL.Parent=TBar;rnd(AL,2)

local function tbL(t,sz,col,fnt,xa,w,pos,zi) local l=Instance.new("TextLabel");l.Text=t;l.TextSize=sz;l.TextColor3=col;l.Font=fnt;l.BackgroundTransparency=1;l.Size=UDim2.new(0,w,1,0);l.Position=pos;l.TextXAlignment=xa;l.ZIndex=zi;l.Parent=TBar;return l end
tbL("⚡",15,C.accent,Enum.Font.GothamBold,Enum.TextXAlignment.Center,24,UDim2.new(0,12,0,9),4)
tbL("Prison Life",14,C.text,Enum.Font.GothamBold,Enum.TextXAlignment.Left,130,UDim2.new(0,38,0,0),4)
tbL("v1.2  |  Solara",11,C.textDim,Enum.Font.Gotham,Enum.TextXAlignment.Left,110,UDim2.new(0,162,0,0),4)

local drag,ds,sp2=false,nil,nil
TBar.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=true;ds=i.Position;sp2=Win.Position end end)
TBar.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end end)
UserInputService.InputChanged:Connect(function(i) if drag and i.UserInputType==Enum.UserInputType.MouseMovement then local d=i.Position-ds;Win.Position=UDim2.new(sp2.X.Scale,sp2.X.Offset+d.X,sp2.Y.Scale,sp2.Y.Offset+d.Y) end end)

local Side=Instance.new("Frame");Side.Size=UDim2.new(0,110,1,-42);Side.Position=UDim2.new(0,0,0,42);Side.BackgroundColor3=C.surface;Side.ZIndex=2;Side.Parent=Win
local Div=Instance.new("Frame");Div.Size=UDim2.new(0,1,1,0);Div.Position=UDim2.new(1,-1,0,0);Div.BackgroundColor3=C.border;Div.BorderSizePixel=0;Div.ZIndex=2;Div.Parent=Side
local SL=Instance.new("Frame");SL.Size=UDim2.new(1,0,1,0);SL.BackgroundTransparency=1;SL.ZIndex=3;SL.Parent=Side
local SLL=Instance.new("UIListLayout");SLL.SortOrder=Enum.SortOrder.LayoutOrder;SLL.Padding=UDim.new(0,2);SLL.Parent=SL;pad(SL,6,8)

local Content=Instance.new("Frame");Content.Size=UDim2.new(1,-110,1,-42);Content.Position=UDim2.new(0,110,0,42);Content.BackgroundColor3=C.panel;Content.ZIndex=2;Content.Parent=Win

local Tabs,TBtns,Active={},{},nil
local TABS={"Aim","Main","Rage","Settings"}
local ICONS={"🎯","🌫️","💀","⚙️"}

local function setTab(n)
    Active=n
    for k,p in pairs(Tabs) do p.Visible=(k==n) end
    for k,b in pairs(TBtns) do
        local on=(k==n)
        tw(b,{BackgroundColor3=on and C.accentDim or Color3.fromRGB(0,0,0),BackgroundTransparency=on and 0 or 1},.15):Play()
        b.TextColor3=on and C.text or C.textDim
    end
end

for i,name in ipairs(TABS) do
    local pg=Instance.new("ScrollingFrame");pg.Name=name;pg.Size=UDim2.new(1,0,1,0);pg.BackgroundTransparency=1;pg.ScrollBarThickness=3;pg.ScrollBarImageColor3=C.accent;pg.CanvasSize=UDim2.new(0,0,0,0);pg.AutomaticCanvasSize=Enum.AutomaticSize.Y;pg.Visible=false;pg.ZIndex=3;pg.Parent=Content;pad(pg,12,10)
    local pl=Instance.new("UIListLayout");pl.SortOrder=Enum.SortOrder.LayoutOrder;pl.Padding=UDim.new(0,6);pl.Parent=pg
    Tabs[name]=pg
    local b=Instance.new("TextButton");b.Size=UDim2.new(1,0,0,32);b.BackgroundTransparency=1;b.Font=Enum.Font.GothamMedium;b.TextSize=13;b.TextColor3=C.textDim;b.TextXAlignment=Enum.TextXAlignment.Left;b.Text="  "..ICONS[i].."  "..name;b.ZIndex=4;b.LayoutOrder=i;b.Parent=SL;rnd(b,6)
    b.MouseEnter:Connect(function() if Active~=name then tw(b,{TextColor3=C.text},.1):Play() end end)
    b.MouseLeave:Connect(function() if Active~=name then tw(b,{TextColor3=C.textDim},.1):Play() end end)
    b.MouseButton1Click:Connect(function() setTab(name) end)
    TBtns[name]=b
end

local function sec(par,title,order)
    local w=Instance.new("Frame");w.Size=UDim2.new(1,0,0,0);w.BackgroundColor3=C.surface;w.AutomaticSize=Enum.AutomaticSize.Y;w.ZIndex=4;w.LayoutOrder=order or 1;w.Parent=par;rnd(w,8);stk(w,C.border,1);pad(w,10,8)
    local wl=Instance.new("UIListLayout");wl.SortOrder=Enum.SortOrder.LayoutOrder;wl.Padding=UDim.new(0,6);wl.Parent=w
    if title then
        local h=Instance.new("Frame");h.Size=UDim2.new(1,0,0,22);h.BackgroundTransparency=1;h.LayoutOrder=0;h.ZIndex=5;h.Parent=w
        local hl=Instance.new("Frame");hl.Size=UDim2.new(0,3,0,14);hl.Position=UDim2.new(0,0,0.5,-7);hl.BackgroundColor3=C.accent;hl.BorderSizePixel=0;hl.ZIndex=6;hl.Parent=h;rnd(hl,2)
        local ht=Instance.new("TextLabel");ht.Text=title;ht.TextSize=11;ht.Font=Enum.Font.GothamBold;ht.TextColor3=C.textDim;ht.BackgroundTransparency=1;ht.Size=UDim2.new(1,-14,1,0);ht.Position=UDim2.new(0,10,0,0);ht.TextXAlignment=Enum.TextXAlignment.Left;ht.ZIndex=6;ht.Parent=h
    end
    return w
end

local function tog(par,text,def,cb,order)
    local row=Instance.new("Frame");row.Size=UDim2.new(1,0,0,28);row.BackgroundTransparency=1;row.LayoutOrder=order or 1;row.ZIndex=5;row.Parent=par
    local l=Instance.new("TextLabel");l.Text=text;l.TextSize=13;l.Font=Enum.Font.GothamMedium;l.TextColor3=C.text;l.BackgroundTransparency=1;l.Size=UDim2.new(1,-48,1,0);l.TextXAlignment=Enum.TextXAlignment.Left;l.ZIndex=6;l.Parent=row
    local tr=Instance.new("Frame");tr.Size=UDim2.new(0,36,0,18);tr.Position=UDim2.new(1,-38,0.5,-9);tr.BackgroundColor3=def and C.tog_on or C.tog_off;tr.ZIndex=6;tr.Parent=row;rnd(tr,9);stk(tr,C.border,1)
    local kn=Instance.new("Frame");kn.Size=UDim2.new(0,12,0,12);kn.Position=def and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6);kn.BackgroundColor3=Color3.new(1,1,1);kn.ZIndex=7;kn.Parent=tr;rnd(kn,6)
    local st=def
    local btn=Instance.new("TextButton");btn.Size=UDim2.new(1,0,1,0);btn.BackgroundTransparency=1;btn.Text="";btn.ZIndex=8;btn.Parent=row
    btn.MouseButton1Click:Connect(function()
        st=not st
        tw(tr,{BackgroundColor3=st and C.tog_on or C.tog_off},.15):Play()
        tw(kn,{Position=st and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)},.15):Play()
        cb(st)
    end)
end

local function slider(par,text,mn,mx,def,cb,order)
    local w=Instance.new("Frame");w.Size=UDim2.new(1,0,0,44);w.BackgroundTransparency=1;w.LayoutOrder=order or 1;w.ZIndex=5;w.Parent=par
    local l=Instance.new("TextLabel");l.Text=text;l.TextSize=13;l.Font=Enum.Font.GothamMedium;l.TextColor3=C.text;l.BackgroundTransparency=1;l.Size=UDim2.new(0.7,0,0,18);l.TextXAlignment=Enum.TextXAlignment.Left;l.ZIndex=6;l.Parent=w
    local vl=Instance.new("TextLabel");vl.Text=tostring(def);vl.TextSize=12;vl.Font=Enum.Font.GothamMedium;vl.TextColor3=C.accent;vl.BackgroundTransparency=1;vl.Size=UDim2.new(0.3,0,0,18);vl.TextXAlignment=Enum.TextXAlignment.Right;vl.ZIndex=6;vl.Parent=w
    local tr=Instance.new("Frame");tr.Size=UDim2.new(1,0,0,6);tr.Position=UDim2.new(0,0,0,26);tr.BackgroundColor3=C.slider_bg;tr.ZIndex=6;tr.Parent=w;rnd(tr,3);stk(tr,C.border,1)
    local fi=Instance.new("Frame");fi.Size=UDim2.new((def-mn)/(mx-mn),0,1,0);fi.BackgroundColor3=C.accent;fi.ZIndex=7;fi.Parent=tr;rnd(fi,3)
    local hd=Instance.new("Frame");hd.Size=UDim2.new(0,12,0,12);hd.AnchorPoint=Vector2.new(0.5,0.5);hd.Position=UDim2.new((def-mn)/(mx-mn),0,0.5,0);hd.BackgroundColor3=Color3.new(1,1,1);hd.ZIndex=8;hd.Parent=tr;rnd(hd,6)
    local ds2=false
    local function upd(i) local r=math.clamp((i.Position.X-tr.AbsolutePosition.X)/tr.AbsoluteSize.X,0,1);local v=math.floor(mn+(mx-mn)*r);fi.Size=UDim2.new(r,0,1,0);hd.Position=UDim2.new(r,0,0.5,0);vl.Text=tostring(v);cb(v) end
    tr.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then ds2=true;upd(i) end end)
    UserInputService.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then ds2=false end end)
    UserInputService.InputChanged:Connect(function(i) if ds2 and i.UserInputType==Enum.UserInputType.MouseMovement then upd(i) end end)
end

local function inp(par,text,def,cb,order)
    local w=Instance.new("Frame");w.Size=UDim2.new(1,0,0,52);w.BackgroundTransparency=1;w.LayoutOrder=order or 1;w.ZIndex=5;w.Parent=par
    lbl(w,text,13,C.text,Enum.Font.GothamMedium).ZIndex=6
    local b=Instance.new("TextBox");b.Size=UDim2.new(1,0,0,26);b.Position=UDim2.new(0,0,0,22);b.BackgroundColor3=C.input_bg;b.TextColor3=C.text;b.PlaceholderColor3=C.textDim;b.Font=Enum.Font.Gotham;b.TextSize=12;b.Text=tostring(def);b.ClearTextOnFocus=false;b.ZIndex=6;b.Parent=w;rnd(b,5);stk(b,C.border,1);pad(b,8,0)
    b.FocusLost:Connect(function() cb(b.Text) end)
end

-- AIM TAB
local p=Tabs["Aim"]
local s1=sec(p,"SILENT AIM",1)
tog(s1,"Silent Aim",Config.SilentAimEnabled,function(v) Config.SilentAimEnabled=v end,1)
tog(s1,"Show Target Circle",Config.ShowCircle,function(v) Config.ShowCircle=v end,2)
tog(s1,"Team Check",Config.TeamCheck,function(v) Config.TeamCheck=v end,3)
slider(s1,"FOV Radius",10,400,Config.SilentAimFOV,function(v) Config.SilentAimFOV=v end,4)
local s2=sec(p,"ONETAP",2)
tog(s2,"Onetap (Remington 870 → AK-47/MP5)",Config.OnetapEnabled,function(v) Config.OnetapEnabled=v end,1)
local s3=sec(p,"HITSOUND",3)
tog(s3,"Hitsound",Config.HitsoundEnabled,function(v) Config.HitsoundEnabled=v end,1)
inp(s3,"Sound ID",Config.HitsoundId,function(v) local id=tonumber(v);if id then Config.HitsoundId=id;HitSound.SoundId="rbxassetid://"..id end end,2)

-- MAIN TAB
local pm=Tabs["Main"]
local sm=sec(pm,"FOG SHADER",1)
tog(sm,"Enable Fog",Config.FogEnabled,function(v) Config.FogEnabled=v;applyFog() end,1)
slider(sm,"Fog Start",0,500,Config.FogStart,function(v) Config.FogStart=v;applyFog() end,2)
slider(sm,"Fog End",10,2000,Config.FogEnd,function(v) Config.FogEnd=v;applyFog() end,3)
slider(sm,"Atmosphere Density",0,100,math.floor(Config.FogDensity*100),function(v) Config.FogDensity=v/100;applyFog() end,4)

-- RAGE TAB
local pr=Tabs["Rage"]
local sr=sec(pr,"SPIN",1)
tog(sr,"Spin",Config.SpinEnabled,function(v) Config.SpinEnabled=v;if v then startSpin() else stopSpin() end end,1)
slider(sr,"Spin Speed",1,60,Config.SpinSpeed,function(v) Config.SpinSpeed=v end,2)

-- SETTINGS TAB
local ps=Tabs["Settings"]
local ss=sec(ps,"INTERFACE",1)
-- dropdown inline (упрощённый для Settings)
local keyOpts={"RightShift","Insert","F4","Delete","Home"}
local keyMap={RightShift=Enum.KeyCode.RightShift,Insert=Enum.KeyCode.Insert,F4=Enum.KeyCode.F4,Delete=Enum.KeyCode.Delete,Home=Enum.KeyCode.Home}
local keyRow=Instance.new("Frame");keyRow.Size=UDim2.new(1,0,0,52);keyRow.BackgroundTransparency=1;keyRow.LayoutOrder=1;keyRow.ZIndex=5;keyRow.Parent=ss
lbl(keyRow,"Menu Toggle Key",13,C.text,Enum.Font.GothamMedium).ZIndex=6
local keyInp=Instance.new("TextBox");keyInp.Size=UDim2.new(1,0,0,26);keyInp.Position=UDim2.new(0,0,0,22);keyInp.BackgroundColor3=C.input_bg;keyInp.TextColor3=C.text;keyInp.Font=Enum.Font.Gotham;keyInp.TextSize=12;keyInp.Text="RightShift";keyInp.ClearTextOnFocus=false;keyInp.ZIndex=6;keyInp.Parent=keyRow;rnd(keyInp,5);stk(keyInp,C.border,1);pad(keyInp,8,0)
keyInp.FocusLost:Connect(function() Config.MenuKey=keyMap[keyInp.Text] or Enum.KeyCode.RightShift end)

local sinfoSec=sec(ps,"INFO",2)
lbl(sinfoSec,"Prison Life Script  •  v1.2",12,C.textDim)
lbl(sinfoSec,"Solara / Synapse X / Electron",11,C.textDim)
if namecallHooked then
    lbl(sinfoSec,"✅ __namecall hook active",11,Color3.fromRGB(60,210,130))
else
    lbl(sinfoSec,"⚠️ hook failed — limited mode",11,Color3.fromRGB(255,180,60))
end

setTab("Aim")

-- toggle menu
local menuVis=true
UserInputService.InputBegan:Connect(function(i,gp)
    if gp then return end
    if i.KeyCode==Config.MenuKey then
        menuVis=not menuVis
        tw(Win,{Size=menuVis and UDim2.new(0,560,0,380) or UDim2.new(0,560,0,0)},.2,Enum.EasingStyle.Back,menuVis and Enum.EasingDirection.Out or Enum.EasingDirection.In):Play()
    end
end)

print("[PrisonLife v1.2] Loaded | hook: " .. tostring(namecallHooked) .. " | key: " .. Config.MenuKey.Name)
