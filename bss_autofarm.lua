-- Bee Swarm Simulator auto-farm for Matcha
-- Farms a chosen field, returns to your hive when the bag is full, converts, then goes back.
-- No Instance.new / HttpGet / WorldToViewportPoint used (Matcha limitations).

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local STATE = { status = "Idle", fieldNames = {}, fieldParts = {}, angle = 0 }

-- ===== helpers =====
local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHivePos()
    local hive = LocalPlayer:FindFirstChild("Honeycomb")
    hive = hive and hive.Value
    if not hive then return nil end
    -- try a few known spots inside the hive model
    local spawn = hive:FindFirstChild("SpawnPos")
    if spawn then return spawn.Position end
    local arrow = hive:FindFirstChild("patharrow")
    local base = arrow and arrow:FindFirstChild("Base")
    if base then return base.Position end
    if hive.PrimaryPart then return hive.PrimaryPart.Position end
    return nil
end

local function getPollen()
    local stats = LocalPlayer:FindFirstChild("CoreStats")
    if not stats then return 0, 1 end
    local p = stats:FindFirstChild("Pollen")
    local c = stats:FindFirstChild("Capacity")
    return (p and p.Value or 0), (c and c.Value or 1)
end

local function tp(pos)
    local hrp = getHRP()
    if hrp then hrp.CFrame = CFrame.new(pos) end
end

local function loadFields()
    STATE.fieldNames, STATE.fieldParts = {}, {}
    local zones = workspace:FindFirstChild("FlowerZones")
    if not zones then return end
    for _, z in ipairs(zones:GetChildren()) do
        table.insert(STATE.fieldNames, z.Name)
        STATE.fieldParts[z.Name] = z
    end
    table.sort(STATE.fieldNames)
end
loadFields()

-- ===== menu =====
UI.AddTab("BSS Farm", function(tab)
    local sec = tab:Section("Auto Farm", "Left")
    sec:Toggle("bss_enabled", "Auto Farm", false)
    if #STATE.fieldNames > 0 then
        sec:Combo("bss_field", "Field", STATE.fieldNames, 1)
    else
        sec:Text("No fields found - rejoin and reload")
    end
    sec:SliderInt("bss_return_pct", "Return to hive at % full", 50, 100, 100)
    sec:SliderInt("bss_radius", "Walk radius (studs)", 5, 40, 18)
    sec:Toggle("bss_convert", "Convert honey at hive", true)
    sec:Button("Go to hive now", function()
        local p = getHivePos()
        if p then tp(p + Vector3.new(0, 4, 0)) end
    end)
    sec:Button("Reload fields", loadFields)

    local info = tab:Section("Status", "Right")
    info:Text("State: " .. STATE.status)
    local pollen, cap = getPollen()
    info:Text(string.format("Pollen: %d / %d", pollen, cap))
end)

-- ===== main loop =====
task.spawn(function()
    while true do
        wait(0.1)
        if not UI.GetValue("bss_enabled") then
            STATE.status = "Idle"
        else
            local hrp = getHRP()
            local hivePos = getHivePos()
            local fieldName = STATE.fieldNames[UI.GetValue("bss_field") or 1]
            local field = fieldName and STATE.fieldParts[fieldName]

            if hrp and hivePos and field then
                local pollen, cap = getPollen()
                local threshold = (UI.GetValue("bss_return_pct") or 100) / 100

                if cap > 0 and pollen >= cap * threshold then
                    -- bag full: go home and convert
                    STATE.status = "Returning to hive"
                    tp(hivePos + Vector3.new(0, 4, 0))
                    wait(1)

                    if UI.GetValue("bss_convert") then
                        STATE.status = "Converting honey"
                        local timeout = tick() + 120
                        if isrbxactive() then keypress(0x45) wait(0.05) keyrelease(0x45) end -- E toggles honey making
                        while tick() < timeout and UI.GetValue("bss_enabled") do
                            local p = getPollen()
                            if p <= 0 then break end
                            wait(1)
                        end
                        wait(1)
                    end

                    STATE.status = "Back to " .. fieldName
                    tp(field.Position + Vector3.new(0, 4, 0))
                    wait(1)
                else
                    -- walk in a spiral over the field to collect pollen
                    STATE.status = "Farming " .. fieldName
                    local r = UI.GetValue("bss_radius") or 18
                    local half = math.min(field.Size.X, field.Size.Z) / 2 - 2
                    if r > half then r = half end
                    STATE.angle = STATE.angle + 0.45
                    local rr = r * (0.4 + 0.6 * math.abs(math.sin(STATE.angle / 6)))
                    local offset = Vector3.new(math.cos(STATE.angle) * rr, 4, math.sin(STATE.angle) * rr)
                    tp(field.Position + offset)
                end
            end
        end
    end
end)

notify("BSS auto farm loaded - open the 'BSS Farm' tab", "Matcha", 5)
