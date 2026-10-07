local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

-- TARGETS
local TARGETS = {
    Rocket = true,
    Spin = true,
    Blade = true,
    Spring = true,
    Bomb = true,
    Smoke = true,
    Spike = true,
    Flame = true,
    Ice = true,
    Sand = true,
    Dark = true,
    Eagle = true,
    Diamond = true,
    Light = true,
    Rubber = true,
    Ghost = true,
    Magma = true,
    Quake = true,
    Buddha = true,
    Love = true,
    Creation = true,
    Spider = true,
    Sound = true,
    Phoenix = true,
    Portal = true,
    Lightning = true,
    Pain = true,
    Blizzard = true,
    Gravity = true,
    ["T-Rex"] = true,
    Mammoth = true,
    Dough = true,
    Shadow = true,
    Venom = true,
    Gas = true,
    Spirit = true,
    Tiger = true,
    Yeti = true,
    Magnet = true,
    Kitsune = true,
    Control = true,
    Dragon = true,
}

local NORMAL_SIZE = 0.322
local COLLAPSED_SIZE = 0.20
local OWNED_IMAGE =
    "rbxassetid://82332807858397"
local tweenInfo =
    TweenInfo.new(
        0.12,
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out
    )

-- FIND SCROLLING FRAME
local function getScrolling()
    local shop =
        pg:FindFirstChild("FruitShopAndDealer")
    if not shop then
        return nil
    end

    local shopFrame =
        shop:FindFirstChild("Shop")
    if not shopFrame then
        return nil
    end

    local menu =
        shopFrame:FindFirstChild("Menu")
    if not menu then
        return nil
    end

    local content =
        menu:FindFirstChild("Content")
    if not content then
        return nil
    end

    local body =
        content:FindFirstChild("Body")
    if not body then
        return nil
    end
    return body:FindFirstChild(
        "ScrollingFrame"
    )
end

-- TOP INFO
local function getTopInfo(card)
    local cardButton =
        card:FindFirstChild("CardButton")
    if not cardButton then
        return nil
    end
    local profile =
        cardButton:FindFirstChild("Profile")
    if not profile then
        return nil
    end

    return profile:FindFirstChild(
        "TopInfo"
    )
end

-- FRUIT NAME
local function getFruitName(card)

    local topInfo =
        getTopInfo(card)
    if not topInfo then
        return nil
    end
    local fruitName =
        topInfo:FindFirstChild(
            "FruitName"
        )
    if fruitName
        and fruitName:IsA("TextLabel") then
        return fruitName.Text
    end
    local title =
        topInfo:FindFirstChild(
            "Title"
        )

    if title
        and title:IsA("TextLabel") then
        return title.Text
    end
    return nil
end

-- ============================================================
-- V7.6 OWNED LABEL
-- BASED ON WORKING V7.5
-- FIX: COLOR + SIZE
-- ============================================================
local function createOwnedLabel(topInfo)
    local existing =
        topInfo:FindFirstChild("V75_OwnedLabel")
    if existing then
        return existing
    end

    -- MAIN OWNED LABEL
    local owned =
        Instance.new("Frame")
    owned.Name =
        "V75_OwnedLabel"
    owned.BackgroundTransparency = 1
    owned.BorderSizePixel = 0
    owned.Size =
        UDim2.new(
            0,
            190,
            0.322,
            0
        )
    owned.Position =
        UDim2.new(
            -7.95999995e-08,
            0,
            0.308,
            0
        )
    owned.AnchorPoint =
        Vector2.new(
            0.5,
            0.5
        )
    owned.Rotation = 0
    owned.ZIndex = 2
    owned.Visible = true

    -- MAIN LIST
    local layout =
        Instance.new("UIListLayout")
    layout.Name =
        "UIListLayout"
    layout.FillDirection =
        Enum.FillDirection.Vertical
    layout.HorizontalAlignment =
        Enum.HorizontalAlignment.Left
    layout.VerticalAlignment =
        Enum.VerticalAlignment.Center
    layout.Padding =
        UDim.new(0, 0)
    layout.SortOrder =
        Enum.SortOrder.LayoutOrder
    layout.Parent = owned

    -- BACKGROUND
    local background =
        Instance.new("ImageLabel")
    background.Name =
        "Background"
    background.BackgroundTransparency = 1
    background.BorderSizePixel = 0
    background.Image =
        "rbxassetid://82332807858397"
    background.ImageColor3 =
        Color3.fromRGB(
            0,
            0,
            0
        )
    background.ImageTransparency = 0
    background.ScaleType =
        Enum.ScaleType.Stretch
    background.SliceCenter =
        Rect.new(
            0,
            0,
            0,
            0
        )
    background.SliceScale = 1
    background.TileSize =
        UDim2.new(
            1,
            0,
            1,
            0
        )
    background.Size =
        UDim2.new(
            1.48,
            0,
            1.10,
            0
        )
    background.Position =
        UDim2.new(
            0.5,
            0,
            0.5,
            0
        )

    background.ZIndex = 2
    background.Visible = true
    background.Parent = owned

    -- BACKGROUND LIST
    local bgLayout =
        Instance.new("UIListLayout")
    bgLayout.Name =
        "UIListLayout"
    bgLayout.FillDirection =
        Enum.FillDirection.Vertical
    bgLayout.HorizontalAlignment =
        Enum.HorizontalAlignment.Left
    bgLayout.VerticalAlignment =
        Enum.VerticalAlignment.Center
    bgLayout.Padding =
        UDim.new(0, 0)
    bgLayout.SortOrder =
        Enum.SortOrder.LayoutOrder
    bgLayout.Parent = background

    local text =
        Instance.new("TextLabel")
    text.Name =
        "TextLabel"
    text.BackgroundTransparency = 1
    text.BorderSizePixel = 0
    text.Size =
        UDim2.new(
            0.9,
            0,
            1,
            0
        )

    text.Position =
        UDim2.new(
            0.5,
            0,
            0.5,
            0
        )

    text.Text =
        "(Owned)"
    text.Font =
        Enum.Font.PermanentMarker
    text.TextSize = 8
    text.TextColor3 =
        Color3.fromRGB(
            255,
            209,
            41
        )

    text.TextTransparency = 0
    text.TextStrokeTransparency = 0
    text.TextStrokeColor3 =
        Color3.fromRGB(
            0,
            0,
            0
        )

    text.TextScaled = true
    text.TextWrapped = true
    text.TextXAlignment =
        Enum.TextXAlignment.Center
    text.TextYAlignment =
        Enum.TextYAlignment.Center
    text.ZIndex = 3
    text.Visible = true
    text.Parent = background
    owned.Parent = topInfo

    return owned
end

-- HIDE PRICE
local function hidePrice(card)
    local topInfo =
        getTopInfo(card)

    if not topInfo then
        return
    end

    local price =
        topInfo:FindFirstChild(
            "Price"
        )

    if price then
        price.Visible = false
    end
end

-- EQUIP STATE
local function applyEquipState(card)
    local controlPanel =
        card:FindFirstChild(
            "ControlPanel"
        )

    if not controlPanel then
        return
    end

    local content =
        controlPanel:FindFirstChild(
            "Content"
        )

    if not content then
        return
    end

    local buttons =
        content:FindFirstChild(
            "Buttons"
        )

    if not buttons then
        return
    end

    local perm =
        buttons:FindFirstChild(
            "PermPurchaseButton"
        )

    if not perm then
        return
    end

    local textContainer =
        perm:FindFirstChild(
            "TextContainer"
        )

    local labelContainer =
        textContainer
        and textContainer:FindFirstChild(
            "LabelContainer"
        )

    local overLabel =
        labelContainer
        and labelContainer:FindFirstChild(
            "OverLabel"
        )

    if overLabel then
        overLabel.Text =
            "Equip"

        local underLabel =
            overLabel:FindFirstChild(
                "UnderLabel"
            )

        if underLabel then
            underLabel.Text =
                "Equip"
        end
    end

    local tooltip =
        perm:FindFirstChild(
            "ToolTip"
        )
        
    if tooltip then
        tooltip.Visible = false
    end
end

-- APPLY
local function applyCard(card)
    local fruitName =
        getFruitName(card)
    if not fruitName then
        return
    end
    if not TARGETS[fruitName] then
        return
    end

    local topInfo =
        getTopInfo(card)
    if not topInfo then
        return
    end

    local owned =
    createOwnedLabel(topInfo)
    if owned then
        owned.Visible = true

        local background =
            owned:FindFirstChild(
                "Background"
            )

        if background then
            background.Visible = true
            local text =
                background:FindFirstChild(
                    "TextLabel"
                )
            if text then
                text.Visible = true
            end
        end
    end
    hidePrice(card)
    applyEquipState(card)
end

-- TOGGLE ANIMATION
local busy = {}
local function setOwnedState(card, expanded)
    local topInfo = getTopInfo(card)
    if not topInfo then
        return
    end

    local owned = topInfo:FindFirstChild("V75_OwnedLabel")
    if not owned then
        return
    end

    local scale = owned:FindFirstChild("OwnedScale")

    if not scale then
        scale = Instance.new("UIScale")
        scale.Name = "OwnedScale"
        scale.Scale = 1
        scale.Parent = owned
    end

    local target = expanded and 0.62 or 1

    if math.abs(scale.Scale - target) < 0.01 then
        return
    end

    if busy[card] then
        busy[card]:Cancel()
        busy[card] = nil
    end

    local tween = TweenService:Create(
        scale,
        tweenInfo,
        {
            Scale = target
        }
    )

    busy[card] = tween
    tween.Completed:Connect(function()
        if busy[card] == tween then
            busy[card] = nil
        end
    end)
    tween:Play()
end

local function isCardExpanded(card)
    local controlPanel = card:FindFirstChild("ControlPanel")

    if not controlPanel then
        return false
    end

    if controlPanel.Visible == false then
        return false
    end

    local height = controlPanel.AbsoluteSize.Y
    return height > 10
end

local function syncOwned(card)
    task.spawn(function()

        task.wait(0.08)
        for i = 1, 12 do
            local scrolling = getScrolling()
            if not scrolling then
                return
            end
            
            for _, otherCard in ipairs(scrolling:GetChildren()) do
                if otherCard:IsA("Frame") then
                    local fruitName = getFruitName(otherCard)

                    if fruitName and TARGETS[fruitName] then
                        local expanded = isCardExpanded(otherCard)
                        setOwnedState(otherCard, expanded)
                    end
                end
            end
            task.wait(0.04)
        end
    end)
end

-- CARD SETUP
local connected = {}
local function setupCard(card)
    if not card:IsA("Frame") then
        return
    end

    local fruitName = getFruitName(card)
    if not fruitName then
        return
    end
    if not TARGETS[fruitName] then
        return
    end

    applyCard(card)

    if connected[card] then
        return
    end

    connected[card] = true

    local cardButton = card:FindFirstChild("CardButton")
    if cardButton then
        cardButton.MouseButton1Click:Connect(function()
            task.defer(function()
                syncOwned(card)
            end)
        end)
    end

    card.ChildAdded:Connect(function(child)
        if child.Name == "ControlPanel" then
            task.wait(0.03)
            applyEquipState(card)
            syncOwned(card)
        end
    end)
end

-- SHOP WATCH
local watched = {}
local function watchScrolling(scrolling)
    if watched[scrolling] then
        return
    end

    watched[scrolling] = true

    for _, card in ipairs(
        scrolling:GetChildren()
    ) do
        setupCard(card)
    end

    scrolling.ChildAdded:Connect(
        function(card)
            task.wait()
            setupCard(card)
        end
    )

    task.spawn(
        function()
            while scrolling.Parent do
                for _, card in ipairs(
                    scrolling:GetChildren()
                ) do
                    local fruitName =
                        getFruitName(card)
                    if fruitName
                        and TARGETS[fruitName] then
                        applyCard(card)
                    end
                end
                task.wait(0.25)
            end
        end
    )
end

-- SHOP REBUILD WATCHER
task.spawn(
    function()
        while pg.Parent do
            local scrolling =
                getScrolling()

            if scrolling then
                watchScrolling(scrolling)
            end
            task.wait(0.2)
        end
    end
)

print("Yoshi Amaru")
