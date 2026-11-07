-- Safe Cross-Platform Rayfield Loader
local Success, Rayfield = pcall(function()
    return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
end)

if not Success or not Rayfield then
    Rayfield = loadstring(game:HttpGet('https://raw.githubusercontent.com/shlexware/Rayfield/main/source'))()
end

-- Services
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer

-- Executor Function Polyfills for PC
local safeFireProximityPrompt = fireproximityprompt or function(Prompt)
    if Prompt and Prompt:IsA("ProximityPrompt") then
        local hold = Prompt.HoldDuration
        Prompt.HoldDuration = 0
        Prompt:InputHoldBegin()
        task.wait(0.01)
        Prompt:InputHoldEnd()
        Prompt.HoldDuration = hold
    end
end

local safeFireTouchInterest = firetouchinterest or function(PartToTouch, TouchWith, Toggle)
    if PartToTouch and TouchWith and TouchWith:IsA("BasePart") then
        if Toggle == 0 then
            TouchWith.CFrame = PartToTouch.CFrame
        end
    end
end

-- Shared Utility Function: General Teleport & Collection Loop (Оптимизировано по задержкам)
local function runFarmLoop(stateTable, useItemFunc)
    task.spawn(function()
        while true do
            if stateTable.Enabled then
                pcall(function()
                    local char = LocalPlayer.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")

                    if root and #stateTable.Queue > 0 then
                        for _, data in ipairs(stateTable.Queue) do
                            if not stateTable.Enabled then break end

                            local targetPart = data.Part
                            local prompt = data.Prompt
                            local sourceNode = data.Source

                            if targetPart and targetPart.Parent then
                                if not stateTable.Attempts[targetPart] then
                                    stateTable.Attempts[targetPart] = 0
                                end

                                if stateTable.Attempts[targetPart] >= 4 then
                                    stateTable.Blacklist[targetPart] = true
                                    if sourceNode then stateTable.Blacklist[sourceNode] = true end
                                    local hl = targetPart:FindFirstChild("FarmHighlight")
                                    if hl then hl:Destroy() end
                                    continue
                                end

                                root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                                root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                                root.CFrame = targetPart.CFrame + Vector3.new(0, 0.5, 0)

                                RunService.Heartbeat:Wait()

                                local collected = false
                                for step = 1, 3 do
                                    if not targetPart or not targetPart.Parent then
                                        collected = true
                                        break
                                    end

                                    if prompt then
                                        pcall(function()
                                            prompt.MaxActivationDistance = 999999
                                            prompt.RequiresLineOfSight = false
                                            safeFireProximityPrompt(prompt)
                                        end)
                                    end

                                    pcall(function()
                                        safeFireTouchInterest(targetPart, root, 0)
                                        safeFireTouchInterest(targetPart, root, 1)
                                    end)

                                    task.wait(0.02)
                                end

                                if sourceNode and (sourceNode.Name == "LBChest" or sourceNode.Name:lower():find("chest")) then
                                    task.wait(0.2)
                                    pcall(function()
                                        for _, item in ipairs(Workspace:GetDescendants()) do
                                            if item:IsA("BasePart") and (item.Name:lower():find("lb") or item.Name:lower():find("potion") or item.Name:lower():find("bottle")) then
                                                if (item.Position - root.Position).Magnitude <= 15 then
                                                    safeFireTouchInterest(item, root, 0)
                                                    safeFireTouchInterest(item, root, 1)
                                                end
                                            end
                                        end
                                    end)
                                end

                                if useItemFunc then
                                    useItemFunc()
                                end

                                if targetPart and targetPart.Parent and not collected then
                                    stateTable.Attempts[targetPart] = stateTable.Attempts[targetPart] + 1
                                else
                                    stateTable.Attempts[targetPart] = nil
                                    local hl = targetPart:FindFirstChild("FarmHighlight")
                                    if hl then hl:Destroy() end
                                end

                                task.wait(stateTable.TPDelay)
                            end
                        end
                    end
                end)
            end
            task.wait(0.12) -- Убраны лишние микрофризы
        end
    end)
end

-- Shared Utility Function: Map Scanner (Редкий запуск сканирования для разгрузки процессора)
local function setupScanner(stateTable, checkFunc)
    task.spawn(function()
        while true do
            if stateTable.Enabled then
                local list = {}
                pcall(function()
                    for _, descendant in ipairs(Workspace:GetDescendants()) do
                        local data = checkFunc(descendant, stateTable)
                        if data and data.Part and not table.find(list, data.Part) then
                            table.insert(list, data)
                        end
                    end
                end)

                local char = LocalPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if root and #list > 1 then
                    table.sort(list, function(a, b)
                        return (root.Position - a.Part.Position).Magnitude < (root.Position - b.Part.Position).Magnitude
                    end)
                end

                stateTable.Queue = list
                task.wait(1.0) -- Сканирование обновляется реже, полностью убивая лаги
            else
                task.wait(1.5)
            end
        end
    end)
end

-- Shared Utility Function: ESP Handler (Оптимизирован тайминг отрисовки)
local function setupESP(stateTable, fillColor)
    task.spawn(function()
        while true do
            if stateTable.ESPEnabled and stateTable.Enabled then
                pcall(function()
                    for _, data in ipairs(stateTable.Queue) do
                        local part = data.Part
                        if part and part.Parent and not part:FindFirstChild("FarmHighlight") then
                            local highlight = Instance.new("Highlight")
                            highlight.Name = "FarmHighlight"
                            highlight.Adornee = part
                            highlight.FillColor = fillColor
                            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
                            highlight.FillTransparency = 0.3
                            highlight.OutlineTransparency = 0
                            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                            highlight.Parent = part
                        end
                    end
                end)
            else
                pcall(function()
                    for _, obj in ipairs(Workspace:GetDescendants()) do
                        if obj.Name == "FarmHighlight" then obj:Destroy() end
                    end
                end)
            end
            task.wait(2.0)
        end
    end)
end

-- ==================== CANDY, LOLIPOP & CHOCOLATE CONFIG ====================
local CandyState = {
    Enabled = false,
    ESPEnabled = true,
    AutoEat = true,
    TPDelay = 0.08,
    Blacklist = {},
    Attempts = {},
    Queue = {}
}

local function getCandyData(inst, state)
    if not inst or not inst.Parent or state.Blacklist[inst] then return nil end

    if inst:IsA("Model") and (inst:FindFirstChildOfClass("Humanoid") or Players:GetPlayerFromCharacter(inst)) then
        return nil
    end

    local name = inst.Name:lower()
    local parentName = inst.Parent.Name:lower()

    if name:find("candy") or parentName:find("candy") or 
       name:find("sweet") or parentName:find("sweet") or 
       name:find("treat") or parentName:find("treat") or 
       name:find("lolipop") or parentName:find("lolipop") or 
       name:find("lollipop") or parentName:find("lollipop") or
       name:find("chocolate") or parentName:find("chocolate") or
       name:find("choco") or parentName:find("choco") then
        
        local targetPart = nil
        local prompt = nil

        if inst:IsA("BasePart") then
            targetPart = inst
        elseif inst:IsA("Model") or inst:IsA("Folder") then
            targetPart = inst:FindFirstChildWhichIsA("BasePart", true)
        elseif inst:IsA("ProximityPrompt") then
            prompt = inst
            if prompt.Parent and prompt.Parent:IsA("BasePart") then
                targetPart = prompt.Parent
            end
        end

        if not prompt and targetPart then
            prompt = targetPart:FindFirstChildOfClass("ProximityPrompt") 
                  or (targetPart.Parent and targetPart.Parent:FindFirstChildOfClass("ProximityPrompt"))
        end

        if targetPart and targetPart:IsA("BasePart") and not state.Blacklist[targetPart] then
            return { Part = targetPart, Prompt = prompt, Source = inst }
        end
    end
    return nil
end

local function eatCandy()
    if not CandyState.AutoEat then return end
    pcall(function()
        local char = LocalPlayer.Character
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        if not char then return end

        local tool = char:FindFirstChildOfClass("Tool")
        if not tool and backpack then
            for _, item in ipairs(backpack:GetChildren()) do
                if item:IsA("Tool") then
                    local tName = item.Name:lower()
                    if tName:find("candy") or tName:find("lolipop") or tName:find("lollipop") or tName:find("chocolate") or tName:find("choco") then
                        item.Parent = char
                        tool = item
                        break
                    end
                end
            end
        end

        if tool then tool:Activate() end
    end)
end

setupScanner(CandyState, getCandyData)
setupESP(CandyState, Color3.fromRGB(255, 120, 0))
runFarmLoop(CandyState, eatCandy)


-- ==================== LB POTION & CHEST CONFIG & SETUP ====================
local PotionState = {
    Enabled = false,
    ESPEnabled = true,
    AutoUse = true,
    TPDelay = 0.08,
    Blacklist = {},
    Attempts = {},
    Queue = {}
}

local function getPotionData(inst, state)
    if not inst or not inst.Parent or state.Blacklist[inst] then return nil end

    if inst:IsA("Model") and (inst:FindFirstChildOfClass("Humanoid") or Players:GetPlayerFromCharacter(inst)) then
        return nil
    end

    local name = inst.Name
    local parentName = inst.Parent.Name
    local lowerName = name:lower()
    local lowerParent = parentName:lower()

    local isMatch = (name == "LBbottleSpawn" or name == "XLLBbottleSpawn" or name == "LBChest" 
        or parentName == "LBbottleSpawn" or parentName == "XLLBbottleSpawn" or parentName == "LBChest"
        or lowerName:find("lb") or lowerParent:find("lb") 
        or lowerName:find("potion") or lowerParent:find("potion"))

    if isMatch then
        local targetPart = nil
        local prompt = nil

        if inst:IsA("BasePart") then
            targetPart = inst
        elseif inst:IsA("Model") or inst:IsA("Folder") then
            targetPart = inst:FindFirstChildWhichIsA("BasePart", true)
        elseif inst:IsA("ProximityPrompt") then
            prompt = inst
            if prompt.Parent and prompt.Parent:IsA("BasePart") then
                targetPart = prompt.Parent
            end
        end

        if not targetPart and inst:IsA("Model") and inst.PrimaryPart then
            targetPart = inst.PrimaryPart
        end

        if not prompt and targetPart then
            prompt = targetPart:FindFirstChildOfClass("ProximityPrompt") 
                  or (targetPart.Parent and targetPart.Parent:FindFirstChildOfClass("ProximityPrompt"))
        end

        if targetPart and targetPart:IsA("BasePart") and not state.Blacklist[targetPart] then
            return { Part = targetPart, Prompt = prompt, Source = inst }
        end
    end
    return nil
end

local function usePotion()
    if not PotionState.AutoUse then return end
    pcall(function()
        local char = LocalPlayer.Character
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        if not char then return end

        local tool = char:FindFirstChildOfClass("Tool")
        if not tool and backpack then
            for _, item in ipairs(backpack:GetChildren()) do
                if item:IsA("Tool") and (item.Name:find("LB") or item.Name:lower():find("potion")) then
                    item.Parent = char
                    tool = item
                    break
                end
            end
        end

        if tool then tool:Activate() end
    end)
end

setupScanner(PotionState, getPotionData)
setupESP(PotionState, Color3.fromRGB(0, 180, 255))
runFarmLoop(PotionState, usePotion)


-- ==================== BEWITCHED ENERGY CONFIG & SETUP (UPDATED & PRECISE) ====================
local BewitchedState = {
    Enabled = false,
    ESPEnabled = true,
    TPDelay = 0.08,
    Blacklist = {},
    Attempts = {},
    Queue = {}
}

local function getBewitchedData(inst, state)
    if not inst or not inst.Parent or state.Blacklist[inst] then return nil end

    local name = inst.Name
    local parent = inst.Parent
    local parentName = parent and parent.Name or ""
    local lowerName = name:lower()

    -- Точное обновление: поиск исключительно BewitchedEnergy и сопутствующей энергии без лишних камней
    local isMatch = (
        lowerName == "bewitchedenergy" or 
        parentName == "BewitchedEnergy" or 
        lowerName:find("bewitched") or
        lowerName:find("energy")
    ) and not lowerName:find("rock")

    if isMatch then
        local targetPart = nil
        local prompt = nil

        if inst:IsA("BasePart") then
            targetPart = inst
        elseif inst:IsA("Model") or inst:IsA("Folder") then
            targetPart = inst:FindFirstChildWhichIsA("BasePart", true)
        elseif inst:IsA("ProximityPrompt") then
            prompt = inst
            if prompt.Parent and prompt.Parent:IsA("BasePart") then
                targetPart = prompt.Parent
            end
        end

        if not targetPart and inst:IsA("Model") and inst.PrimaryPart then
            targetPart = inst.PrimaryPart
        end

        if not prompt and targetPart then
            prompt = targetPart:FindFirstChildOfClass("ProximityPrompt") 
                  or (targetPart.Parent and targetPart.Parent:FindFirstChildOfClass("ProximityPrompt"))
        end

        if targetPart and targetPart:IsA("BasePart") and not state.Blacklist[targetPart] then
            return { Part = targetPart, Prompt = prompt, Source = inst }
        end
    end
    return nil
end

local function checkBewitchedInventoryOrCompletion()
    pcall(function()
        local char = LocalPlayer.Character
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        local hasEnergy = false
        
        if char then
            for _, item in ipairs(char:GetChildren()) do
                if item:IsA("Tool") and (item.Name:lower():find("bewitched") or item.Name:lower():find("energy")) then
                    hasEnergy = true
                    break
                end
            end
        end
        
        if not hasEnergy and backpack then
            for _, item in ipairs(backpack:GetChildren()) do
                if item:IsA("Tool") and (item.Name:lower():find("bewitched") or item.Name:lower():find("energy")) then
                    hasEnergy = true
                    break
                end
            end
        end

        if hasEnergy or #BewitchedState.Queue == 0 then
            if BewitchedState.Enabled then
                BewitchedState.Enabled = false
                Rayfield:Notify({
                    Title = "Bewitched Energy",
                    Content = "Энергия собрана! Авто-фарм выключен.",
                    Duration = 4,
                    Image = 4483362458,
                })
            end
        end
    end)
end

setupScanner(BewitchedState, getBewitchedData)
setupESP(BewitchedState, Color3.fromRGB(138, 43, 226))
runFarmLoop(BewitchedState, checkBewitchedInventoryOrCompletion)


-- ==================== GLOBAL EXTRAS ====================
local GlobalState = {
    InstantPromptEnabled = false,
    FullbrightEnabled = false
}

-- Instant Proximity Prompts Handler
local originalHoldDurations = {}
task.spawn(function()
    while true do
        if GlobalState.InstantPromptEnabled then
            pcall(function()
                for _, desc in ipairs(Workspace:GetDescendants()) do
                    if desc:IsA("ProximityPrompt") then
                        if not originalHoldDurations[desc] then
                            originalHoldDurations[desc] = desc.HoldDuration
                        end
                        desc.HoldDuration = 0
                        desc.MaxActivationDistance = math.max(desc.MaxActivationDistance, 30)
                    end
                end
            end)
        else
            pcall(function()
                for prompt, originalDuration in pairs(originalHoldDurations) do
                    if prompt and prompt.Parent then
                        prompt.HoldDuration = originalDuration
                    end
                end
                table.clear(originalHoldDurations)
            end)
        end
        task.wait(3)
    end
end)

-- Fullbright Handler
local cachedLighting = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd,
    GlobalShadows = Lighting.GlobalShadows,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient
}

task.spawn(function()
    while true do
        if GlobalState.FullbrightEnabled then
            pcall(function()
                Lighting.Brightness = 2
                Lighting.ClockTime = 14
                Lighting.FogEnd = 100000
                Lighting.GlobalShadows = false
                Lighting.Ambient = Color3.fromRGB(255, 255, 255)
                Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
            end)
        else
            pcall(function()
                Lighting.Brig
