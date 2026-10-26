-- Bee Swarm Simulator all-in-one farm for Matcha
-- Features: fly-move to fields/hive, auto convert, token collector, auto dig,
-- anti-AFK (sends real input so Roblox never sees you as idle), HUD, manual-move pause.

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

pcall(function() setrobloxinput(true) end)

local S = {
    status = "Idle",
    fieldNames = {},
    fieldParts = {},
    angle = 0,
    pauseUntil = 0,
    goHive = false,
    startTime = tick(),
    startHoney = nil,
    lastAfk = tick(),
    afkPings = 0,
    badTokens = {},
}

-- ===== helpers =====
local function fmt(n)
    n = math.floor(n or 0)
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if out:sub(1, 1) == "," then out = out:sub(2) end
    return out
end

local function fmtTime(sec)
    sec = math.floor(sec)
    return string.format("%02d:%02d:%02d", math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60)
end

local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHivePos()
    local hive = LocalPlayer:FindFirstChild("Honeycomb")
    hive = hive and hive.Value
    if not hive then return nil end
    local spawn = hive:FindFirstChild("SpawnPos")
    if spawn then return spawn.Position end
    local arrow = hive:FindFirstChild("patharrow")
    local base = arrow and arrow:FindFirstChild("Base")
    if base then return base.Position end
    if hive.PrimaryPart then return hive.PrimaryPart.Position end
    return nil
end

local function getStat(name)
    local stats = LocalPlayer:FindFirstChild("CoreStats")
    local v = stats and stats:FindFirstChild(name)
    return v and v.Value or 0
end

local function getPollen()
    return getStat("Pollen"), math.max(getStat("Capacity"), 1)
end

local function loadFields()
    S.fieldNames, S.fieldParts = {}, {}
    local zones = workspace:FindFirstChild("FlowerZones")
    if not zones then return end
    for _, z in ipairs(zones:GetChildren()) do
        table.insert(S.fieldNames, z.Name)
        S.fieldParts[z.Name] = z
    end
    table.sort(S.fieldNames)
end
loadFields()

local function manualInput()
    return iskeypressed(0x57) or iskeypressed(0x41) or iskeypressed(0x53)
        or iskeypressed(0x44) or iskeypressed(0x20)
end

local function enabled()
    return UI.GetValue("bss_enabled")
end

-- ===== fly move =====
-- Rises to a cruise height, flies over, then lowers onto the target.
-- Returns true on arrival, false if aborted (farm turned off / you moved).
local function flyTo(target)
    local speed = UI.GetValue("bss_fly_speed") or 80
    local hrp = getHRP()
    if not hrp then return false end

    local cruise = math.max(hrp.Position.Y, target.Y) + 20
    local waypoints = {
        Vector3.new(hrp.Position.X, cruise, hrp.Position.Z),
        Vector3.new(target.X, cruise, target.Z),
        target,
    }

    for _, wp in ipairs(waypoints) do
        while true do
            hrp = getHRP()
            if not hrp then return false end
            if not enabled() and not S.goHive then return false end
            if manualInput() then
                S.pauseUntil = tick() + 1.5
                return false
            end
            local cur = hrp.Position
            local delta = wp - cur
            local dist = delta.Magnitude
            if dist < 2.5 then break end
            local step = math.min(dist, speed * 0.03)
            hrp.CFrame = CFrame.new(cur + delta * (step / dist))
            wait(0.03)
        end
    end
    return true
end

-- ===== hive actions =====
local function goHomeAndConvert()
    local hivePos = getHivePos()
    if not hivePos then return end
    S.status = "Flying to hive"
    if not flyTo(hivePos + Vector3.new(0, 4, 0)) then return end
    wait(0.8)

    if UI.GetValue("bss_convert") then
        S.status = "Converting honey"
        -- E toggles honey making, so only press it when pollen is actually still there,
        -- and re-check after a few seconds that the pollen is really dropping.
        local function pressE()
            if isrbxactive() then keypress(0x45) wait(0.05) keyrelease(0x45) end
        end
        local before = getStat("Pollen")
        if before > 0 then pressE() end
        local checkAt = tick() + 4
        local timeout = tick() + 150
        while tick() < timeout and (enabled() or S.goHive) do
            local p = getStat("Pollen")
            if p <= 0 then break end
            if manualInput() then S.pauseUntil = tick() + 1.5 return end
            if tick() >= checkAt then
                if p >= before then pressE() end -- not converting yet, toggle it on
                before = p
                checkAt = tick() + 4
            end
            wait(1)
        end
        wait(1)
    end
end

-- ===== token collection =====
local function findToken(fieldPart)
    local folder = workspace:FindFirstChild("Collectibles")
    local hrp = getHRP()
    if not folder or not hrp then return nil end
    local half = math.min(fieldPart.Size.X, fieldPart.Size.Z) / 2 + 6
    local best, bestDist = nil, 1e9
    for _, c in ipairs(folder:GetChildren()) do
        local ok, pos = pcall(function() return c.Position end)
        if ok and pos and not (S.badTokens[c] and tick() < S.badTokens[c]) then
            local flat = Vector3.new(pos.X - fieldPart.Position.X, 0, pos.Z - fieldPart.Position.Z)
            if flat.Magnitude < half then
                local d = (pos - hrp.Position).Magnitude
                if d < bestDist then best, bestDist = c, d end
            end
        end
    end
    return best
end

-- ===== menu =====
UI.AddTab("BSS Farm", function(tab)
    local sec = tab:Section("Auto Farm", "Left")
    sec:Toggle("bss_enabled", "Auto Farm", false)
    if #S.fieldNames > 0 then
        sec:Combo("bss_field", "Field", S.fieldNames, 1)
    else
        sec:Text("No fields found - rejoin and reload")
    end
    sec:SliderInt("bss_return_pct", "Return to hive at % full", 50, 100, 100)
    sec:SliderInt("bss_radius", "Walk radius (studs)", 5, 40, 18)
    sec:SliderInt("bss_fly_speed", "Fly speed (studs/sec)", 20, 200, 80)
    sec:Toggle("bss_convert", "Convert honey at hive", true)
    sec:Toggle("bss_dig", "Auto dig (click)", true)
    sec:Toggle("bss_tokens", "Collect tokens in field", true)
    sec:Button("Fly to hive now", function() S.goHive = true end)
    sec:Button("Reload fields", loadFields)

    local afk = tab:Section("Anti-AFK", "Right")
    afk:Toggle("bss_antiafk", "Anti-AFK (stay active)", true)
    afk:SliderInt("bss_afk_interval", "Ping every (sec)", 15, 300, 45)
    afk:Tip("Sends tiny real mouse input so Roblox never marks you idle. Needs the Roblox window active.")

    local hud = tab:Section("Display", "Right")
    hud:Toggle("bss_hud", "Show on-screen HUD", true)
    hud:Text("State: " .. S.status)
    local pollen, cap = getPollen()
    hud:Text(string.format("Pollen: %s / %s", fmt(pollen), fmt(cap)))
    hud:Text("Uptime: " .. fmtTime(tick() - S.startTime))
end)

-- ===== main farm loop =====
local function step()
    if not enabled() and not S.goHive then
        S.status = "Idle"
        return
    end
    if tick() < S.pauseUntil then
        S.status = "Paused (you are moving)"
        return
    end

    local hrp = getHRP()
    local hivePos = getHivePos()
    if not hrp or not hivePos then
        S.status = "Waiting for character / hive"
        return
    end

    -- manual "fly to hive" button
    if S.goHive then
        goHomeAndConvert()
        S.goHive = false
        return
    end

    local fieldName = S.fieldNames[UI.GetValue("bss_field") or 1]
    local field = fieldName and S.fieldParts[fieldName]
    if not field then
        S.status = "Pick a field"
        return
    end

    local pollen, cap = getPollen()
    local threshold = (UI.GetValue("bss_return_pct") or 100) / 100

    -- bag full -> go home, convert, come back
    if pollen >= cap * threshold then
        goHomeAndConvert()
        return
    end

    -- not in the field yet -> fly there
    local half = math.min(field.Size.X, field.Size.Z) / 2
    local flat = Vector3.new(hrp.Position.X - field.Position.X, 0, hrp.Position.Z - field.Position.Z)
    if flat.Magnitude > half + 12 then
        S.status = "Flying to " .. fieldName
        flyTo(field.Position + Vector3.new(0, 4, 0))
        return
    end

    S.status = "Farming " .. fieldName

    -- grab a token if one is nearby
    if UI.GetValue("bss_tokens") then
        local tok = findToken(field)
        if tok then
            local ok, pos = pcall(function() return tok.Position end)
            if ok and pos then
                S.badTokens[tok] = tick() + 4
                S.status = "Collecting token"
                local h = getHRP()
                if h then h.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) end
                wait(0.15)
                return
            end
        end
    end

    -- spiral over the flowers
    local r = math.min(UI.GetValue("bss_radius") or 18, half - 2)
    S.angle = S.angle + 0.45
    local rr = r * (0.4 + 0.6 * math.abs(math.sin(S.angle / 6)))
    local offset = Vector3.new(math.cos(S.angle) * rr, 4, math.sin(S.angle) * rr)
    hrp.CFrame = CFrame.new(field.Position + offset)

    if UI.GetValue("bss_dig") and isrbxactive() then mouse1click() end
end

task.spawn(function()
    while true do
        wait(0.25)
        if manualInput() then S.pauseUntil = tick() + 1.5 end
        local ok, err = pcall(step)
        if not ok then S.status = "Error: " .. tostring(err) end
    end
end)

-- ===== anti-AFK =====
task.spawn(function()
    while true do
        wait(1)
        if UI.GetValue("bss_antiafk") then
            local interval = UI.GetValue("bss_afk_interval") or 45
            if tick() - S.lastAfk >= interval then
                S.lastAfk = tick()
                if isrbxactive() then
                    mousemoverel(3, 0)
                    wait(0.05)
                    mousemoverel(-3, 0)
                    S.afkPings = S.afkPings + 1
                end
            end
        end
        -- real farming input also counts as activity
        if enabled() then S.lastAfk = math.max(S.lastAfk, tick() - 20) end
    end
end)

-- ===== HUD =====
local hud = Drawing.new("Text")
hud.Position = Vector2.new(20, 20)
hud.Outline = true
hud.Center = false
-- text size property name differs between Matcha builds, so try each safely
if not pcall(function() hud.Size = 16 end) then
    pcall(function() hud.FontSize = 16 end)
end
hud.Color = Color3.fromRGB(255, 220, 90)
hud.Visible = false

task.spawn(function()
    while true do
        wait(0.3)
        if UI.GetValue("bss_hud") then
            local honey = getStat("Honey")
            if not S.startHoney then S.startHoney = honey end
            local gained = honey - S.startHoney
            local hours = math.max((tick() - S.startTime) / 3600, 0.0001)
            local pollen, cap = getPollen()
            local afkLeft = math.max(0, (UI.GetValue("bss_afk_interval") or 45) - (tick() - S.lastAfk))
            hud.Text = table.concat({
                "BSS Farm  |  " .. S.status,
                "Pollen: " .. fmt(pollen) .. " / " .. fmt(cap),
                "Honey gained: " .. fmt(gained) .. "  (" .. fmt(gained / hours) .. "/hr)",
                "Uptime: " .. fmtTime(tick() - S.startTime),
                "Anti-AFK: " .. (UI.GetValue("bss_antiafk") and ("active, next ping " .. math.floor(afkLeft) .. "s") or "off"),
            }, "\n")
            hud.Visible = true
        else
            hud.Visible = false
        end
    end
end)

notify("BSS farm loaded - open the 'BSS Farm' tab", "Matcha", 5)
