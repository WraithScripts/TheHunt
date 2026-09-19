-- The Hunt 2.0 | Universal Script
-- Wraith Scripts
-- Works across all Hunt event games

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local BadgeService     = game:GetService("BadgeService")
local Workspace        = game:GetService("Workspace")
local CoreGui          = game:GetService("CoreGui")

local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

local function getChar() return lp.Character end
local function getRoot()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local c = getChar()
    return c and c:FindFirstChildWhichIsA("Humanoid")
end

-- ============================================================
-- CONFIG
-- ============================================================
local CFG = {
    -- Toggles (all true by default for max automation)
    AutoBadge       = true,   -- touch/interact all badge objects
    AutoProximity   = true,   -- auto-fire all ProximityPrompts
    AutoClick       = true,   -- auto-fire all ClickDetectors
    AutoRemote      = true,   -- fire suspicious remotes
    AutoDialogue    = true,   -- auto-advance NPC dialogue
    AutoObby        = false,  -- teleport to obby end (risky, off by default)
    ESP             = true,   -- highlight hunt items
    SpeedHack       = true,
    NoClip          = false,

    WalkSpeed       = 32,
    JumpPower       = 50,
    ScanInterval    = 0.2,    -- seconds between full scans

    -- Keywords that identify Hunt badge objects/parts
    BadgeKeywords = {
        "hunt", "badge", "trophy", "collectible", "orb", "star", "gem",
        "coin", "reward", "prize", "token", "chest", "crystal", "relic",
        "artifact", "totem", "seal", "emblem", "crest", "mark",
    },

    -- Remote names that trigger badge/reward
    RemoteKeywords = {
        "badge", "award", "give", "claim", "collect", "reward",
        "complete", "finish", "trigger", "unlock", "grant",
        "hunt", "event", "obtain", "redeem",
    },

    -- ProximityPrompt action text that suggests badge award
    PromptKeywords = {
        "collect", "claim", "badge", "hunt", "trophy", "pick up",
        "grab", "take", "interact", "examine", "activate", "use",
        "touch", "open", "press", "", -- empty string = fire ALL prompts
    },
}

-- ============================================================
-- STATE
-- ============================================================
local done      = {}  -- deduplication
local espAdded  = {}
local _conns    = {}

-- ============================================================
-- HELPERS
-- ============================================================
local function safe(fn, ...)
    local ok, e = pcall(fn, ...)
    if not ok then end -- silent
end

local function nameMatch(name, keywords)
    name = name:lower()
    for _, kw in ipairs(keywords) do
        if kw == "" or name:find(kw, 1, true) then return true end
    end
    return false
end

local function tagMatch(obj, keywords)
    local ok, tags = pcall(function() return CollectionService:GetTags(obj) end)
    if not ok then return false end
    for _, t in ipairs(tags) do
        if nameMatch(t, keywords) then return true end
    end
    return false
end

local function isBadgeObj(obj)
    return nameMatch(obj.Name, CFG.BadgeKeywords)
        or tagMatch(obj, CFG.BadgeKeywords)
end

-- ============================================================
-- ESP
-- ============================================================
local function addESP(obj)
    if espAdded[obj] then return end
    espAdded[obj] = true
    safe(function()
        local target = obj:IsA("Model") and obj or obj.Parent
        local sb = Instance.new("SelectionBox")
        sb.Adornee       = obj
        sb.Color3        = Color3.fromRGB(255, 210, 0)
        sb.SurfaceColor3 = Color3.fromRGB(255, 230, 80)
        sb.SurfaceTransparency = 0.55
        sb.LineThickness = 0.055
        sb.Parent        = CoreGui

        obj.AncestryChanged:Connect(function()
            if not obj:IsDescendantOf(game) then
                sb:Destroy()
                espAdded[obj] = nil
            end
        end)
    end)
end

local function clearAllESP()
    for obj, _ in pairs(espAdded) do
        safe(function()
            for _, sb in ipairs(CoreGui:GetChildren()) do
                if sb:IsA("SelectionBox") and sb.Adornee == obj then
                    sb:Destroy()
                end
            end
        end)
    end
    espAdded = {}
end

-- ============================================================
-- TELEPORT UTIL
-- ============================================================
local function tp(pos)
    local root = getRoot()
    if root then
        root.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0))
    end
end

-- ============================================================
-- TOUCH TRIGGER
-- ============================================================
-- Physically moves the character onto the part to fire Touched events
local function touchPart(part)
    local root = getRoot()
    if not root or not part:IsA("BasePart") then return end
    local old = root.CFrame
    root.CFrame = part.CFrame * CFrame.new(0, part.Size.Y / 2 + 2, 0)
    task.wait(0.08)
    root.CFrame = old
end

-- ============================================================
-- PROXIMITY PROMPTS
-- ============================================================
local function fireAllPrompts()
    if not CFG.AutoProximity then return end
    for _, pp in ipairs(Workspace:GetDescendants()) do
        if pp:IsA("ProximityPrompt") then
            local actionText = pp.ActionText:lower()
            local objText    = pp.ObjectText:lower()
            local parent     = pp.Parent

            local isHunt = nameMatch(pp.ActionText, CFG.PromptKeywords)
                        or nameMatch(pp.ObjectText,  CFG.BadgeKeywords)
                        or (parent and isBadgeObj(parent))

            if isHunt then
                local key = "pp_" .. tostring(pp)
                if not done[key] then
                    done[key] = true
                    safe(function()
                        -- get close first
                        local adornee = pp.Parent
                        if adornee and adornee:IsA("BasePart") then
                            tp(adornee.Position)
                            task.wait(0.05)
                        elseif adornee and adornee:IsA("Model") and adornee.PrimaryPart then
                            tp(adornee.PrimaryPart.Position)
                            task.wait(0.05)
                        end
                        fireproximityprompt(pp)
                    end)
                end
            end
        end
    end
end

-- ============================================================
-- CLICK DETECTORS
-- ============================================================
local function fireAllClickers()
    if not CFG.AutoClick then return end
    for _, cd in ipairs(Workspace:GetDescendants()) do
        if cd:IsA("ClickDetector") then
            local parent = cd.Parent
            if parent and isBadgeObj(parent) then
                local key = "cd_" .. tostring(cd)
                if not done[key] then
                    done[key] = true
                    safe(function()
                        if parent:IsA("BasePart") then
                            tp(parent.Position)
                            task.wait(0.05)
                        end
                        fireclickdetector(cd)
                    end)
                end
            end
        end
    end
end

-- ============================================================
-- REMOTE EVENTS / FUNCTIONS
-- ============================================================
local function fireAllRemotes()
    if not CFG.AutoRemote then return end

    local function scanParent(container)
        for _, obj in ipairs(container:GetDescendants()) do
            if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) and nameMatch(obj.Name, CFG.RemoteKeywords) then
                local key = "re_" .. tostring(obj)
                if not done[key] then
                    done[key] = true
                    safe(function()
                        if obj:IsA("RemoteEvent") then
                            obj:FireServer()
                            obj:FireServer(lp)
                            obj:FireServer(lp.Character)
                        else
                            obj:InvokeServer()
                        end
                    end)
                end
            end
        end
    end

    scanParent(ReplicatedStorage)
    safe(function() scanParent(game:GetService("Players").LocalPlayer.PlayerGui) end)
    -- Also scan workspace folder remotes
    safe(function()
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) and nameMatch(obj.Name, CFG.RemoteKeywords) then
                local key = "re_" .. tostring(obj)
                if not done[key] then
                    done[key] = true
                    safe(function()
                        if obj:IsA("RemoteEvent") then
                            obj:FireServer()
                        end
                    end)
                end
            end
        end
    end)
end

-- ============================================================
-- BADGE OBJECT INTERACTION
-- ============================================================
local function interactBadgeObjects()
    if not CFG.AutoBadge then return end

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if (obj:IsA("BasePart") or obj:IsA("MeshPart") or obj:IsA("SpecialMesh") or obj:IsA("Model")) and isBadgeObj(obj) then
            local key = "bo_" .. tostring(obj)
            if not done[key] then
                done[key] = true
                if CFG.ESP then addESP(obj) end

                safe(function()
                    local part = obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")) or obj

                    if part and part:IsA("BasePart") then
                        tp(part.Position)
                        task.wait(0.05)
                        touchPart(part)
                    end

                    -- also fire any cd/pp on this object
                    for _, child in ipairs(obj:GetDescendants()) do
                        if child:IsA("ClickDetector") then
                            safe(function() fireclickdetector(child) end)
                        elseif child:IsA("ProximityPrompt") then
                            safe(function() fireproximityprompt(child) end)
                        end
                    end
                end)
            end
        end
    end
end

-- ============================================================
-- AUTO DIALOGUE
-- Skip NPC conversations: click through all dialogue GUI buttons
-- ============================================================
local function autoDialogue()
    if not CFG.AutoDialogue then return end
    safe(function()
        local pg = lp.PlayerGui
        for _, gui in ipairs(pg:GetDescendants()) do
            if gui:IsA("TextButton") or gui:IsA("ImageButton") then
                local n = gui.Name:lower()
                local t = gui.Text and gui.Text:lower() or ""
                if nameMatch(n, {"next", "continue", "skip", "accept", "ok", "yes", "claim", "collect", "confirm", "done", "close"})
                or nameMatch(t, {"next", "continue", "skip", "accept", "ok", "yes", "claim", "collect", "confirm", "done"}) then
                    if gui.Visible and gui.Active ~= false then
                        safe(function() gui.MouseButton1Click:Fire() end)
                    end
                end
            end
        end
    end)
end

-- ============================================================
-- AUTO OBBY  (disabled by default — tp to last checkpoint)
-- ============================================================
local function autoObby()
    if not CFG.AutoObby then return end
    safe(function()
        -- Find the furthest checkpoint / finish line
        local best = nil
        local bestNum = -1

        for _, obj in ipairs(Workspace:GetDescendants()) do
            local n = obj.Name:lower()
            if n:find("checkpoint") or n:find("finish") or n:find("end") or n:find("stage") then
                local num = tonumber(n:match("%d+")) or 0
                if num > bestNum then
                    bestNum = num
                    best = obj
                end
            end
        end

        if best then
            local part = best:IsA("BasePart") and best
                      or (best:IsA("Model") and (best.PrimaryPart or best:FindFirstChildWhichIsA("BasePart")))
            if part then
                tp(part.Position)
            end
        end
    end)
end

-- ============================================================
-- NOCLIP
-- ============================================================
RunService.Stepped:Connect(function()
    if CFG.NoClip then
        safe(function()
            for _, p in ipairs(getChar():GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end)
    end
end)

-- ============================================================
-- MAIN SCAN LOOP
-- ============================================================
local function scan()
    interactBadgeObjects()
    fireAllPrompts()
    fireAllClickers()
    fireAllRemotes()
    autoDialogue()
    autoObby()

    -- Speed / jump
    safe(function()
        local h = getHum()
        if h then
            if CFG.SpeedHack then h.WalkSpeed = CFG.WalkSpeed end
            h.JumpPower = CFG.JumpPower
        end
    end)
end

task.spawn(function()
    while true do
        task.wait(CFG.ScanInterval)
        safe(scan)
    end
end)

-- Also hook DescendantAdded for instant reaction
Workspace.DescendantAdded:Connect(function(obj)
    task.wait(0.05) -- let it fully load
    if (obj:IsA("BasePart") or obj:IsA("Model")) and isBadgeObj(obj) then
        if CFG.ESP then safe(function() addESP(obj) end) end
        safe(function() interactBadgeObjects() end)
    end
    if obj:IsA("ProximityPrompt") then
        safe(function() fireAllPrompts() end)
    end
end)

ReplicatedStorage.DescendantAdded:Connect(function(obj)
    if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
        task.wait(0.1)
        safe(function() fireAllRemotes() end)
    end
end)

-- ============================================================
-- GUI
-- ============================================================
local function buildGUI()
    safe(function() lp.PlayerGui:FindFirstChild("YurevixHunt2"):Destroy() end)

    local sg = Instance.new("ScreenGui")
    sg.Name = "YurevixHunt2"
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.IgnoreGuiInset = true
    sg.Parent = lp.PlayerGui

    local W, H = 270, 348

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, W, 0, H)
    frame.Position = UDim2.new(0, 12, 0.5, -H/2)
    frame.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = sg

    local function corner(p, r) local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, r or 10) c.Parent = p end
    local function stroke(p, col, t) local s = Instance.new("UIStroke") s.Color = col s.Thickness = t s.Parent = p end

    corner(frame)
    stroke(frame, Color3.fromRGB(255, 200, 0), 1.5)

    -- header bar
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 38)
    header.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
    header.BorderSizePixel = 0
    header.Parent = frame
    corner(header)

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -50, 1, 0)
    titleLbl.Position = UDim2.new(0, 10, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = "🏆  THE HUNT 2.0  |  Yurevix"
    titleLbl.TextColor3 = Color3.fromRGB(255, 210, 0)
    titleLbl.TextSize = 13
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Parent = header

    -- divider
    local div = Instance.new("Frame")
    div.Size = UDim2.new(0.92, 0, 0, 1)
    div.Position = UDim2.new(0.04, 0, 0, 40)
    div.BackgroundColor3 = Color3.fromRGB(60, 55, 20)
    div.BorderSizePixel = 0
    div.Parent = frame

    -- Toggle factory
    local toggleY = 50
    local function makeToggle(label, state, onChange)
        local ROW_H = 38
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.88, 0, 0, 30)
        btn.Position = UDim2.new(0.06, 0, 0, toggleY)
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.GothamSemibold
        btn.TextSize = 12
        btn.Text = (state and "✔  " or "✘  ") .. label
        btn.BackgroundColor3 = state and Color3.fromRGB(255, 200, 0) or Color3.fromRGB(28, 28, 38)
        btn.TextColor3 = state and Color3.fromRGB(12, 12, 18) or Color3.fromRGB(190, 190, 190)
        btn.Parent = frame
        corner(btn, 6)
        toggleY = toggleY + ROW_H

        btn.MouseButton1Click:Connect(function()
            state = not state
            onChange(state)
            TweenService:Create(btn, TweenInfo.new(0.18), {
                BackgroundColor3 = state and Color3.fromRGB(255, 200, 0) or Color3.fromRGB(28, 28, 38),
                TextColor3 = state and Color3.fromRGB(12, 12, 18) or Color3.fromRGB(190, 190, 190),
            }):Play()
            btn.Text = (state and "✔  " or "✘  ") .. label
        end)
        return btn
    end

    makeToggle("Auto Badge Collect",    CFG.AutoBadge,     function(v) CFG.AutoBadge     = v end)
    makeToggle("Auto Proximity Prompt", CFG.AutoProximity, function(v) CFG.AutoProximity = v end)
    makeToggle("Auto Click Detector",   CFG.AutoClick,     function(v) CFG.AutoClick      = v end)
    makeToggle("Auto Remote Fire",      CFG.AutoRemote,    function(v) CFG.AutoRemote     = v end)
    makeToggle("Auto Dialogue Skip",    CFG.AutoDialogue,  function(v) CFG.AutoDialogue   = v end)
    makeToggle("Auto Obby Complete",    CFG.AutoObby,      function(v) CFG.AutoObby       = v end)
    makeToggle("Item ESP",              CFG.ESP,           function(v)
        CFG.ESP = v
        if not v then clearAllESP() end
    end)
    makeToggle("Speed Hack (32)",       CFG.SpeedHack,     function(v) CFG.SpeedHack      = v end)
    makeToggle("No Clip",               CFG.NoClip,        function(v) CFG.NoClip         = v end)

    -- status row
    local statusLbl = Instance.new("TextLabel")
    statusLbl.Size = UDim2.new(0.88, 0, 0, 18)
    statusLbl.Position = UDim2.new(0.06, 0, 1, -28)
    statusLbl.BackgroundTransparency = 1
    statusLbl.Text = "● Scanning..."
    statusLbl.TextColor3 = Color3.fromRGB(100, 255, 120)
    statusLbl.TextSize = 11
    statusLbl.Font = Enum.Font.Gotham
    statusLbl.TextXAlignment = Enum.TextXAlignment.Left
    statusLbl.Parent = frame

    -- live object count
    task.spawn(function()
        while sg.Parent do
            local n = 0
            for _ in pairs(done) do n = n + 1 end
            statusLbl.Text = "● Scanning  |  Triggered: " .. n
            task.wait(1)
        end
    end)

    -- minimize button
    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, 26, 0, 22)
    minBtn.Position = UDim2.new(1, -32, 0, 8)
    minBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
    minBtn.BorderSizePixel = 0
    minBtn.Text = "–"
    minBtn.TextColor3 = Color3.fromRGB(255, 210, 0)
    minBtn.TextSize = 16
    minBtn.Font = Enum.Font.GothamBold
    minBtn.Parent = header
    corner(minBtn, 5)

    local minimized = false
    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        TweenService:Create(frame, TweenInfo.new(0.2), {
            Size = minimized and UDim2.new(0, W, 0, 40) or UDim2.new(0, W, 0, H)
        }):Play()
        minBtn.Text = minimized and "+" or "–"
    end)
end

buildGUI()
print("[Wraith] The Hunt 2.0 Universal loaded")
