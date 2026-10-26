--========================================================
-- Matcha | Bee Swarm Simulator Auto Farm
--========================================================
local Players = game:GetService("Players")
local LP = Players.LocalPlayer

-- Windows VK codes
local K = { W = 0x57, A = 0x41, S = 0x53, D = 0x44, E = 0x45, SPACE = 0x20 }

local FIELDS = {
    "Sunflower Field", "Dandelion Field", "Mushroom Field", "Blue Flower Field",
    "Clover Field", "Spider Field", "Bamboo Field", "Strawberry Field",
    "Pineapple Patch", "Stump Field", "Cactus Field", "Pumpkin Patch",
    "Pine Tree Forest", "Rose Field", "Mountain Top Field", "Coconut Field",
    "Pepper Patch"
}
local PATTERNS = { "Zigzag", "Circle", "Spiral", "Corners", "Random" }

--========================================================
-- Helpers
--========================================================
local function val(id, def)
    local ok, v = pcall(UI.GetValue, id)
    if ok and v ~= nil then return v end
    return def
end

local function getHRP()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    local c = LP.Character
    return c and c:FindFirstChild("Humanoid")
end

local function alive()
    local h, hrp = getHum(), getHRP()
    return h and hrp and h.Health > 0
end

local function getStats()
    local cs = LP:FindFirstChild("CoreStats")
    if not cs then return 0, 1 end
    local p, c = cs:FindFirstChild("Pollen"), cs:FindFirstChild("Capacity")
    if not p or not c then return 0, 1 end
    return p.Value, math.max(c.Value, 1)
end

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

--========================================================
-- Input / movement
--========================================================
local held = { [K.W] = false, [K.A] = false, [K.S] = false, [K.D] = false }

local function setKey(code, state)
    if held[code] == state then return end
    held[code] = state
    if state then keypress(code) else keyrelease(code) end
end

local function releaseAll()
    for code, _ in pairs(held) do setKey(code, false) end
end

local running = true
local state = "Idle"
local lastJump = 0

-- Camera-relative walking using WASD
local function walkTo(target, timeout, stopDist, abort)
    local startT = tick()
    while running and tick() - startT < timeout do
        if not alive() then break end
        if abort and abort() then break end

        local hrp = getHRP()
        local delta = flat(target - hrp.Position)
        local mag = delta.Magnitude
        if mag < stopDist then releaseAll() return true end

        local cam = workspace.CurrentCamera.CFrame
        local look = flat(cam.LookVector)
        local right = flat(cam.RightVector)
        if look.Magnitude < 0.01 then look = Vector3.new(0, 0, -1) else look = look.Unit end
        if right.Magnitude < 0.01 then right = Vector3.new(1, 0, 0) else right = right.Unit end

        local dir = delta / mag
        local f, r = dir:Dot(look), dir:Dot(right)
        setKey(K.W, f > 0.35)
        setKey(K.S, f < -0.35)
        setKey(K.D, r > 0.35)
        setKey(K.A, r < -0.35)

        -- periodic hop to get over small obstacles
        if tick() - lastJump > 1.5 then
            lastJump = tick()
            keypress(K.SPACE) wait(0.05) keyrelease(K.SPACE)
        end
        wait(0.03)
    end
    releaseAll()
    return false
end

--========================================================
-- Field / hive lookup
--========================================================
local function getField()
    local name = FIELDS[val("field", 1)] or FIELDS[1]
    local zones = workspace:FindFirstChild("FlowerZones")
    local zone = zones and zones:FindFirstChild(name)
    if not zone then return nil end
    local center = zone.Position
    local radius = 40
    pcall(function() radius = math.min(zone.Size.X, zone.Size.Z) / 2 end)
    return zone, center, radius
end

local function getHivePos()
    local hives = workspace:FindFirstChild("Honeycombs")
    if not hives then return nil end
    for _, hive in ipairs(hives:GetChildren()) do
        local owner = hive:FindFirstChild("Owner")
        if owner and owner.Value == LP then
            local sp = hive:FindFirstChild("SpawnPos")
            if sp then return sp.Value.Position end
            local part = hive.PrimaryPart or hive:FindFirstChildWhichIsA("BasePart")
            if part then return part.Position end
        end
    end
    return nil
end

--========================================================
-- Field movement patterns
--========================================================
local pIndex, pAngle, pRad = 0, 0, 0.1

local function nextWaypoint(center, radius)
    local mode = PATTERNS[val("pattern", 1)] or "Zigzag"
    local R = radius * (val("radius_pct", 80) / 100)
    pIndex = pIndex + 1

    if mode == "Zigzag" then
        local rows = 6
        local row = (pIndex - 1) % (rows * 2)
        local z = -R + (math.floor(row / 2) / (rows - 1)) * 2 * R
        local x = (row % 2 == 0) and -R or R
        return center + Vector3.new(x, 0, z)
    elseif mode == "Circle" then
        pAngle = pAngle + math.rad(30)
        return center + Vector3.new(math.cos(pAngle) * R, 0, math.sin(pAngle) * R)
    elseif mode == "Spiral" then
        pAngle = pAngle + math.rad(35)
        pRad = pRad + 0.04
        if pRad > 1 then pRad = 0.1 end
        return center + Vector3.new(math.cos(pAngle) * R * pRad, 0, math.sin(pAngle) * R * pRad)
    elseif mode == "Corners" then
        local c = { {-1,-1}, {1,-1}, {1,1}, {-1,1}, {0,0} }
        local p = c[(pIndex - 1) % #c + 1]
        return center + Vector3.new(p[1] * R, 0, p[2] * R)
    else
        return center + Vector3.new((math.random() * 2 - 1) * R, 0, (math.random() * 2 - 1) * R)
    end
end

--========================================================
-- Tokens
--========================================================
local blacklist = {}

local function findToken(center, radius)
    local folder = workspace:FindFirstChild("Collectibles")
    if not folder then return nil end
    local hrp = getHRP()
    if not hrp then return nil end

    local best, bestDist = nil, math.huge
    local maxRange = radius * 1.3
    for _, t in ipairs(folder:GetChildren()) do
        local ok, pos = pcall(function() return t.Position end)
        if ok and pos and (not blacklist[t] or tick() > blacklist[t]) then
            if flat(pos - center).Magnitude <= maxRange then
                local d = flat(pos - hrp.Position).Magnitude
                if d < bestDist and d <= val("token_range", 60) then
                    best, bestDist = t, d
                end
            end
        end
    end
    return best
end

--========================================================
-- Honey conversion
--========================================================
local function convertHoney()
    state = "Going to hive"
    local hivePos = getHivePos()
    if not hivePos then state = "Hive not found" wait(2) return end

    walkTo(hivePos, 45, 4)
    state = "Converting"

    -- optional remote (ignored if the executor can't fire it)
    pcall(function()
        game:GetService("ReplicatedStorage").Events.PlayerHiveCommand:FireServer("ToggleHoneyMaking")
    end)

    local t0 = tick()
    local last = getStats()
    keypress(K.E) wait(0.1) keyrelease(K.E)
    while running and tick() - t0 < 120 do
        wait(2)
        local p = getStats()
        if p <= 0 then break end
        -- not dropping => honey making was toggled off, press E again
        if p >= last then
            keypress(K.E) wait(0.1) keyrelease(K.E)
        end
        last = p
    end
    wait(1)
end

--========================================================
-- Auto dig (own thread)
--========================================================
task.spawn(function()
    while running do
        if val("autofarm", false) and val("autodig", true) and state == "Farming" and isrbxactive() then
            mouse1click()
        end
        wait(0.1)
    end
end)

--========================================================
-- Status overlay
--========================================================
local statusText = Drawing.new("Text")
statusText.Outline = true
statusText.Size = 16
statusText.Color = Color3.fromRGB(255, 220, 90)
statusText.Position = Vector2.new(20, 20)
statusText.Visible = true

task.spawn(function()
    while running do
        local p, c = getStats()
        statusText.Text = string.format("State: %s\nPollen: %d / %d (%d%%)",
            state, p, c, math.floor(p / c * 100))
        wait(0.25)
    end
end)

--========================================================
-- Main farm loop (non-stop)
--========================================================
task.spawn(function()
    pcall(function() setrobloxinput(true) end)
    while running do
        local ok, err = pcall(function()
            if not val("autofarm", false) or not alive() then
                releaseAll()
                state = "Idle"
                wait(0.5)
                return
            end

            local zone, center, radius = getField()
            if not zone then state = "Field not found" wait(1) return end

            local pollen, cap = getStats()

            -- 1) bag full -> hive -> back to field
            if pollen / cap >= val("convert_pct", 98) / 100 then
                convertHoney()
                state = "Returning"
                walkTo(center, 45, 6)
                return
            end

            -- 2) too far from field -> walk back
            local hrp = getHRP()
            if flat(hrp.Position - center).Magnitude > radius * 1.8 then
                state = "Going to field"
                walkTo(center, 45, 6)
                return
            end

            state = "Farming"

            -- 3) follow tokens
            if val("tokens", true) then
                local token = findToken(center, radius)
                if token then
                    state = "Token"
                    local ok2, pos = pcall(function() return token.Position end)
                    if ok2 then
                        local reached = walkTo(pos, 3, 2.5, function()
                            local p, c = getStats()
                            return p / c >= val("convert_pct", 98) / 100
                        end)
                        if not reached then blacklist[token] = tick() + 5 end
                    end
                    return
                end
            end

            -- 4) field pattern
            walkTo(nextWaypoint(center, radius), 6, 3, function()
                local p, c = getStats()
                return p / c >= val("convert_pct", 98) / 100
            end)
        end)
        if not ok then warn("[BSS] " .. tostring(err)) wait(0.5) end
        wait(0.03)
    end
end)

--========================================================
-- Menu
--========================================================
UI.AddTab("Bee Swarm", function(tab)
    local farm = tab:Section("Auto Farm", "Left")
    farm:Toggle("autofarm", "Auto Farm", false)
    farm:Combo("field", "Field", FIELDS, 1)
    farm:Combo("pattern", "Movement Pattern", PATTERNS, 1)
    farm:SliderInt("radius_pct", "Field Coverage %", 20, 100, 80)
    farm:SliderInt("convert_pct", "Convert at Capacity %", 50, 100, 98)

    local opt = tab:Section("Options", "Right")
    opt:Toggle("autodig", "Auto Dig", true)
    opt:Toggle("tokens", "Follow Tokens", true)
    opt:SliderInt("token_range", "Token Range", 10, 150, 60)
    opt:Button("Unload", function()
        running = false
        releaseAll()
        statusText:Remove()
    end)
end)

notify("Bee Swarm farm loaded", "Matcha", 4)
