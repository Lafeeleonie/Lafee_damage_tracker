-- Lafee Damage Type Tracker
-- Tracks physical vs magical damage taken using UNIT_COMBAT.

local addonName, addon = ...
local L = addon.L

local DEFAULTS = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -180,
    width = 220,
    height = 18,
    shown = true,
    window = 5,
    anchorMode = "FREE",
    anchorPosition = "ABOVE",
    anchorSpacing = 4,
    inheritWidth = false,
    leftOffset = 0,
    rightOffset = 0,
    anchorOffsetX = 0,
    anchorOffsetY = 4,
    matchPowerBarWidth = false,
    anchorFrom = "BOTTOM",
    anchorParent = "UIParent",
    anchorTo = "TOP",
    bcdmOffsetX = 0,
    bcdmOffsetY = 4,
    barStyle = "SQUARE",
    minimap = {
        angle = 225,
        hide = false,
    },
}

local OUT_OF_COMBAT_ALPHA = 0.5
local IN_COMBAT_ALPHA = 1
local BAR_INSET = 3
local MIN_WINDOW = 2
local MAX_WINDOW = 10
local MIN_WIDTH = 140
local MAX_WIDTH = 420
local MIN_HEIGHT = 10
local MAX_HEIGHT = 32
local MIN_ANCHOR_SPACING = 0
local MAX_ANCHOR_SPACING = 40
local MIN_ANCHOR_OFFSET = -500
local MAX_ANCHOR_OFFSET = 500
local MAX_EDGE_OFFSET = 100

local ANCHOR_POINTS = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}

local VALID_ANCHOR_POINTS = {}
for _, point in ipairs(ANCHOR_POINTS) do VALID_ANCHOR_POINTS[point] = true end

local ANCHOR_PARENTS = {
    { name = "UIParent", label = "|cFF00AEF7Blizzard|r: UI Parent" },
    { name = "PlayerFrame", label = "|cFF00AEF7Blizzard|r: Player Frame" },
    { name = "TargetFrame", label = "|cFF00AEF7Blizzard|r: Target Frame" },
    { name = "EssentialCooldownViewer", label = "|cFF00AEF7Blizzard|r: Essential Cooldowns" },
    { name = "UtilityCooldownViewer", label = "|cFF00AEF7Blizzard|r: Utility Cooldowns" },
    { name = "BuffIconCooldownViewer", label = "|cFF00AEF7Blizzard|r: Tracked Buffs" },
}

local db
local rootDB
local damageEvents = {}
local currentCharacterKey

local eventFrame = CreateFrame("Frame")
local anchorFrame = CreateFrame("Frame", "LafeeDamageTrackerAnchorFrame", UIParent, "BackdropTemplate")
-- Deprecated global retained for addons that referenced the pre-1.2 root frame.
_G.LafeeDamageTrackerFrame = anchorFrame
local barFrame
local minimapButton
local optionsFrame
local elapsedSinceUpdate = 0
local externalAnchors = {}
local isExternallyAnchored = false
local pendingAnchorUpdate = false
local anchorRetryAttempts = 0
local anchorRetryScheduled = false
local ScheduleAnchorRetry

local function CopyDefaults(src, dst)
    for key, value in pairs(src) do
        if type(value) == "table" then
            dst[key] = dst[key] or {}
            CopyDefaults(value, dst[key])
        elseif dst[key] == nil then
            dst[key] = value
        end
    end
end

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, nestedValue in pairs(value) do
        copy[key] = DeepCopy(nestedValue)
    end
    return copy
end

local function Clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function GetAngleDegrees(x, y)
    if x == 0 then
        if y >= 0 then
            return 90
        end
        return 270
    end

    local angle = math.deg(math.atan(y / x))
    if x < 0 then
        angle = angle + 180
    elseif y < 0 then
        angle = angle + 360
    end
    return angle
end

local function GetCharacterKey()
    local name = UnitName("player") or UNKNOWNOBJECT
    local realm = GetRealmName() or UNKNOWNOBJECT
    return string.format("%s - %s", name, realm)
end

local function GetCharacterProfiles()
    return rootDB and rootDB.characters or {}
end

local function GetAvailableCharacterKeys()
    local keys = {}

    for characterKey in pairs(GetCharacterProfiles()) do
        if characterKey ~= currentCharacterKey then
            table.insert(keys, characterKey)
        end
    end

    table.sort(keys)
    return keys
end

local function RefreshActiveProfile()
    db = GetCharacterProfiles()[currentCharacterKey]
    local legacyAnchor = db.anchorFrom == nil or db.anchorParent == nil or db.anchorTo == nil
    local legacyOffsetY = db.bcdmOffsetY
    local legacyInheritWidth = db.inheritWidth == nil
    local legacyAnchorOffsetX = db.anchorOffsetX == nil
    local legacyAnchorOffsetY = db.anchorOffsetY == nil
    CopyDefaults(DEFAULTS, db)
    db.width = Clamp(db.width, MIN_WIDTH, MAX_WIDTH)
    db.height = Clamp(db.height, MIN_HEIGHT, MAX_HEIGHT)
    db.window = Clamp(db.window, MIN_WINDOW, MAX_WINDOW)
    if db.anchorMode ~= "FREE" and db.anchorMode ~= "ANCHORED"
        and db.anchorMode ~= "BETTER_COOLDOWN_MANAGER" and db.anchorMode ~= "ELVUI" then
        db.anchorMode = DEFAULTS.anchorMode
    end
    if db.anchorPosition ~= "ABOVE" and db.anchorPosition ~= "BELOW" then
        db.anchorPosition = DEFAULTS.anchorPosition
    end
    db.anchorSpacing = Clamp(tonumber(db.anchorSpacing) or DEFAULTS.anchorSpacing, MIN_ANCHOR_SPACING, MAX_ANCHOR_SPACING)
    if legacyInheritWidth then db.inheritWidth = db.matchPowerBarWidth ~= false end
    db.inheritWidth = db.inheritWidth ~= false
    db.matchPowerBarWidth = db.inheritWidth
    db.leftOffset = Clamp(tonumber(db.leftOffset) or DEFAULTS.leftOffset, 0, MAX_EDGE_OFFSET)
    db.rightOffset = Clamp(tonumber(db.rightOffset) or DEFAULTS.rightOffset, 0, MAX_EDGE_OFFSET)
    if legacyAnchor then
        db.anchorParent = db.anchorMode == "ELVUI" and "ElvUF_Player" or db.bcdmAnchor or DEFAULTS.anchorParent
        if db.anchorPosition == "BELOW" then
            db.anchorFrom, db.anchorTo = "TOP", "BOTTOM"
            db.bcdmOffsetY = (tonumber(legacyOffsetY) or 0) - db.anchorSpacing
        else
            db.anchorFrom, db.anchorTo = "BOTTOM", "TOP"
            db.bcdmOffsetY = (tonumber(legacyOffsetY) or 0) + db.anchorSpacing
        end
    end
    if db.anchorMode == "BETTER_COOLDOWN_MANAGER" or db.anchorMode == "ELVUI" then
        db.anchorMode = "ANCHORED"
    end
    if not VALID_ANCHOR_POINTS[db.anchorFrom] then db.anchorFrom = DEFAULTS.anchorFrom end
    if not VALID_ANCHOR_POINTS[db.anchorTo] then db.anchorTo = DEFAULTS.anchorTo end
    if type(db.anchorParent) ~= "string" or db.anchorParent == "" then
        db.anchorParent = DEFAULTS.anchorParent
    end
    if legacyAnchorOffsetX then db.anchorOffsetX = db.bcdmOffsetX end
    if legacyAnchorOffsetY then db.anchorOffsetY = db.bcdmOffsetY end
    db.anchorOffsetX = Clamp(tonumber(db.anchorOffsetX) or DEFAULTS.anchorOffsetX, MIN_ANCHOR_OFFSET, MAX_ANCHOR_OFFSET)
    db.anchorOffsetY = Clamp(tonumber(db.anchorOffsetY) or DEFAULTS.anchorOffsetY, MIN_ANCHOR_OFFSET, MAX_ANCHOR_OFFSET)
    db.bcdmOffsetX = db.anchorOffsetX
    db.bcdmOffsetY = db.anchorOffsetY
    db.minimap.angle = (tonumber(db.minimap.angle) or DEFAULTS.minimap.angle) % 360
    db.minimap.hide = db.minimap.hide == true
    if db.barStyle ~= "CLASSIC" and db.barStyle ~= "SQUARE" then
        db.barStyle = DEFAULTS.barStyle
    end
end

local function PurgeExpiredDamage()
    local now = GetTime()
    local cutoff = now - db.window

    while damageEvents[1] and damageEvents[1].timestamp < cutoff do
        table.remove(damageEvents, 1)
    end
end

local function GetDamageTotals()
    PurgeExpiredDamage()

    local physicalDamage = 0
    local magicalDamage = 0

    for _, eventData in ipairs(damageEvents) do
        if eventData.damageType == "physical" then
            physicalDamage = physicalDamage + eventData.amount
        else
            magicalDamage = magicalDamage + eventData.amount
        end
    end

    return physicalDamage, magicalDamage
end

local function ResetDamageTotals()
    wipe(damageEvents)
end

local function GetAnchorLabel(anchorName)
    for _, anchor in ipairs(ANCHOR_PARENTS) do
        if anchor.name == anchorName then
            return anchor.label
        end
    end
    if type(anchorName) == "string" and anchorName:find("^BCDM_") then
        return "|cFF8080FFBCM|r: " .. anchorName
    end
    if type(anchorName) == "string" and (anchorName:find("^ElvUF_") or anchorName:find("^ElvUI_Bar%d+$")) then
        return "|cff1784d1ElvUI|r: " .. anchorName
    end
    return anchorName
end

local function ApplyFreeFramePosition()
    anchorFrame:ClearAllPoints()
    anchorFrame:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
end

local function GetBarInset()
    return db.barStyle == "SQUARE" and 1 or BAR_INSET
end

local function ApplyBarStyle()
    if not barFrame then return end

    if db.barStyle == "CLASSIC" then
        barFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        barFrame:SetBackdropColor(0.08, 0.08, 0.08, 0.35)
        barFrame:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)
    else
        barFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        barFrame:SetBackdropColor(0.03, 0.03, 0.03, 0.9)
        barFrame:SetBackdropBorderColor(0.02, 0.02, 0.02, 1)
    end

    barFrame.phys:ClearAllPoints()
    barFrame.phys:SetPoint("LEFT", GetBarInset(), 0)
end

local function IsFrameObject(value)
    if value == nil then return false end
    local ok, isFrame = pcall(function()
        return type(value.SetPoint) == "function"
            and type(value.IsObjectType) == "function"
            and value:IsObjectType("Frame")
    end)
    return ok and isFrame == true
end

local function GetAvailableAnchorParents()
    local anchors = {}
    local seen = {}
    for _, anchor in ipairs(ANCHOR_PARENTS) do
        anchors[#anchors + 1] = { name = anchor.name, label = anchor.label }
        seen[anchor.name] = true
    end

    local detected = {}
    for globalName, value in pairs(_G) do
        if type(globalName) == "string" and not seen[globalName] then
            local addonLabel
            if globalName:find("^BCDM_") then
                addonLabel = "|cFF8080FFBCM|r"
            elseif globalName == "ElvUF_Player"
                or globalName == "ElvUF_Player_HealthBar"
                or globalName == "ElvUF_Player_PowerBar"
                or globalName == "ElvUF_Player_CastBar"
                or globalName == "ElvUF_Player_ClassBar"
                or globalName == "ElvUF_Player_AdditionalPower"
                or globalName:find("^ElvUI_Bar%d+$") then
                addonLabel = "|cff1784d1ElvUI|r"
            end
            if addonLabel and IsFrameObject(value) then
                detected[#detected + 1] = { name = globalName, label = addonLabel .. ": " .. globalName }
                seen[globalName] = true
            end
        end
    end

    table.sort(detected, function(left, right) return left.name < right.name end)
    for _, anchor in ipairs(detected) do anchors[#anchors + 1] = anchor end
    return anchors
end

local function GetConfiguredAnchor()
    if db.anchorMode == "FREE" then return nil end
    if db.anchorParent == "UIParent" then return UIParent end
    local candidate = _G[db.anchorParent]
    if IsFrameObject(candidate) then return candidate end
end

local function GetActiveExternalAnchor()
    local binding = externalAnchors.Main
    if binding and IsFrameObject(binding.frame) then
        return binding.frame, binding.options
    end

    local configuredAnchor = GetConfiguredAnchor()
    if not configuredAnchor then return nil end
    return configuredAnchor, {
        point = db.anchorFrom,
        relativePoint = db.anchorTo,
        x = db.anchorOffsetX,
        y = db.anchorOffsetY,
        inheritWidth = db.inheritWidth,
        leftOffset = db.leftOffset,
        rightOffset = db.rightOffset,
    }
end

local function GetVerticalPoint(point)
    if point and point:find("TOP", 1, true) then return "TOP" end
    if point and point:find("BOTTOM", 1, true) then return "BOTTOM" end
    return "CENTER"
end

local function GetHorizontalConstraintPoint(verticalPoint, side)
    if verticalPoint == "CENTER" then return side end
    return verticalPoint .. side
end

local function SetInheritedWidthPoints(target, options)
    local point = GetVerticalPoint(options.point)
    local relativePoint = GetVerticalPoint(options.relativePoint)
    local x = options.x or 0
    local y = options.y or 0
    local leftOffset = options.leftOffset or 0
    local rightOffset = options.rightOffset or 0

    anchorFrame:SetPoint(GetHorizontalConstraintPoint(point, "LEFT"), target,
        GetHorizontalConstraintPoint(relativePoint, "LEFT"), x + leftOffset, y)
    anchorFrame:SetPoint(GetHorizontalConstraintPoint(point, "RIGHT"), target,
        GetHorizontalConstraintPoint(relativePoint, "RIGHT"), x - rightOffset, y)
end

local function ApplyFramePosition()
    local externalFrame, options = GetActiveExternalAnchor()

    if externalFrame then
        if InCombatLockdown() then
            pendingAnchorUpdate = true
            return
        end

        anchorFrame:ClearAllPoints()
        local ok = pcall(function()
            if options.inheritWidth then
                SetInheritedWidthPoints(externalFrame, options)
            else
                anchorFrame:SetPoint(options.point, externalFrame, options.relativePoint, options.x, options.y)
            end
        end)
        if ok then
            isExternallyAnchored = true
            return
        end
    end

    isExternallyAnchored = false
    ApplyFreeFramePosition()
    if (externalAnchors.Main or db.anchorMode ~= "FREE") and ScheduleAnchorRetry then
        ScheduleAnchorRetry()
    end
end

local function ApplyFrameSize()
    local _, options = GetActiveExternalAnchor()
    anchorFrame:SetHeight(db.height)
    if not (isExternallyAnchored and options and options.inheritWidth) then
        anchorFrame:SetWidth(db.width)
    end
    local barInset = GetBarInset()
    barFrame.phys:SetHeight(db.height - (barInset * 2))
    barFrame.magic:SetHeight(db.height - (barInset * 2))
    barFrame.separator:SetHeight(db.height - (barInset * 2))
end

local function UpdateMinimapButtonPosition()
    if not minimapButton then return end

    local angle = math.rad(db.minimap.angle or DEFAULTS.minimap.angle)
    local radius = (Minimap:GetWidth() * 0.5) + 5
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function UpdateDisplay()
    if not barFrame then return end

    local physicalDamage, magicalDamage = GetDamageTotals()
    local totalDamage = physicalDamage + magicalDamage
    local physicalRatio = 0.5
    local magicalRatio = 0.5
    local fillWidth = math.max(0, barFrame:GetWidth() - (GetBarInset() * 2))

    anchorFrame:SetAlpha(UnitAffectingCombat("player") and IN_COMBAT_ALPHA or OUT_OF_COMBAT_ALPHA)

    if totalDamage > 0 then
        physicalRatio = physicalDamage / totalDamage
        magicalRatio = magicalDamage / totalDamage
    end

    barFrame.phys:SetWidth(fillWidth * physicalRatio)
    barFrame.magic:SetWidth(fillWidth * magicalRatio)
    barFrame.magic:SetPoint("LEFT", barFrame.phys, "RIGHT", 0, 0)
    barFrame.separator:SetPoint("LEFT", barFrame.phys, "RIGHT", 0, 0)
    anchorFrame:SetShown(db.shown)
end

local function AddDamageTaken(amount, schoolMask)
    amount = tonumber(amount) or 0
    if amount <= 0 then return end

    table.insert(damageEvents, {
        timestamp = GetTime(),
        amount = amount,
        damageType = schoolMask == 1 and "physical" or "magical",
    })
end

local function RefreshLayout()
    ApplyBarStyle()
    ApplyFramePosition()
    ApplyFrameSize()
    UpdateDisplay()
end

ScheduleAnchorRetry = function()
    if not db or (db.anchorMode == "FREE" and not externalAnchors.Main)
        or anchorRetryScheduled or anchorRetryAttempts >= 5 then return end

    anchorRetryAttempts = anchorRetryAttempts + 1
    anchorRetryScheduled = true
    C_Timer.After(1, function()
        anchorRetryScheduled = false
        if not db or (db.anchorMode == "FREE" and not externalAnchors.Main) then return end
        RefreshLayout()
    end)
end

local function ReapplyAnchor()
    if not db then return end
    if InCombatLockdown() and (db.anchorMode ~= "FREE" or externalAnchors.Main) then
        pendingAnchorUpdate = true
        return
    end

    pendingAnchorUpdate = false
    anchorRetryAttempts = 0
    RefreshLayout()
end

local function CreateSlider(parent, name, label, minValue, maxValue, stepValue, width)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(stepValue)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(width)
    slider.minValue = minValue
    slider.maxValue = maxValue
    slider.stepValue = stepValue

    _G[name .. "Text"]:SetText(label)
    _G[name .. "Low"]:SetText(tostring(minValue))
    _G[name .. "High"]:SetText(tostring(maxValue))

    slider.input = CreateFrame("EditBox", name .. "Input", parent, "InputBoxTemplate")
    slider.input:SetAutoFocus(false)
    slider.input:SetNumeric(false)
    slider.input:SetMaxLetters(6)
    slider.input:SetSize(52, 20)
    slider.input:SetJustifyH("CENTER")
    slider.input:SetPoint("LEFT", slider, "RIGHT", 12, 0)

    slider.input:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        if not value then
            self:SetText(tostring(math.floor(slider:GetValue() + 0.5)))
            self:ClearFocus()
            return
        end

        value = Clamp(value, slider.minValue, slider.maxValue)
        if slider.stepValue and slider.stepValue > 0 then
            value = math.floor((value / slider.stepValue) + 0.5) * slider.stepValue
            value = Clamp(value, slider.minValue, slider.maxValue)
        end

        slider:SetValue(value)
        self:SetText(tostring(math.floor(value + 0.5)))
        self:ClearFocus()
    end)

    slider.input:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(math.floor(slider:GetValue() + 0.5)))
        self:ClearFocus()
    end)

    slider:SetScript("OnValueChanged", function(self, value)
        if self.input then
            self.input:SetText(tostring(math.floor(value + 0.5)))
        end
    end)

    return slider
end

local function SetSliderValue(slider, value)
    slider._internalUpdate = true
    slider:SetValue(value)
    if slider.input then
        slider.input:SetText(tostring(math.floor(value + 0.5)))
    end
    slider._internalUpdate = nil
end

local function CreateScrollableDropdown(parent, name, width, maxHeight, getEntries, onSelect, getSelectedValue)
    local rowHeight = 24
    local button = CreateFrame("Button", name, parent, "BackdropTemplate")
    button:SetSize(width, 26)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    button:SetBackdropColor(0.015, 0.015, 0.015, 0.95)
    button:SetBackdropBorderColor(0.28, 0.28, 0.28, 1)

    button.Text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    button.Text:SetPoint("LEFT", 10, 0)
    button.Text:SetPoint("RIGHT", -28, 0)
    button.Text:SetJustifyH("LEFT")
    button.Text:SetWordWrap(false)

    button.Arrow = button:CreateTexture(nil, "OVERLAY")
    button.Arrow:SetPoint("RIGHT", -3, 0)
    button.Arrow:SetSize(22, 22)
    button.Arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")

    button.Popup = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    button.Popup:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    button.Popup:SetFrameStrata("TOOLTIP")
    button.Popup:SetClampedToScreen(true)
    button.Popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    button.Popup:SetBackdropColor(0.01, 0.01, 0.01, 0.98)
    button.Popup:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    button.Popup:Hide()

    button.ScrollFrame = CreateFrame("ScrollFrame", nil, button.Popup, "UIPanelScrollFrameTemplate")
    button.ScrollFrame:SetPoint("TOPLEFT", 5, -5)
    button.ScrollFrame:SetPoint("BOTTOMRIGHT", -27, 5)
    button.ScrollFrame:EnableMouseWheel(true)

    button.ScrollChild = CreateFrame("Frame", nil, button.ScrollFrame)
    button.ScrollChild:SetSize(width - 34, 1)
    button.ScrollFrame:SetScrollChild(button.ScrollChild)
    button.Rows = {}
    parent.scrollableDropdowns = parent.scrollableDropdowns or {}
    parent.scrollableDropdowns[#parent.scrollableDropdowns + 1] = button

    function button:SetText(text)
        self.Text:SetText(text or "")
    end

    function button:RefreshEntries()
        local entries = getEntries() or {}
        for index, entryData in ipairs(entries) do
            local entry = entryData
            local row = self.Rows[index]
            if not row then
                row = CreateFrame("Button", nil, self.ScrollChild)
                row:SetHeight(rowHeight)
                row:SetPoint("LEFT", 0, 0)
                row:SetPoint("RIGHT", 0, 0)
                local highlight = row:CreateTexture(nil, "HIGHLIGHT")
                highlight:SetAllPoints()
                highlight:SetColorTexture(1, 1, 1, 0.08)
                row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.Text:SetPoint("LEFT", 8, 0)
                row.Text:SetPoint("RIGHT", -6, 0)
                row.Text:SetJustifyH("LEFT")
                row.Text:SetWordWrap(false)
                self.Rows[index] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -((index - 1) * rowHeight))
            row:SetPoint("RIGHT", 0, 0)
            local selectedValue = getSelectedValue and getSelectedValue()
            local selectedPrefix = selectedValue == entry.name and "|cff00ff98> |r" or "   "
            row.Text:SetText(selectedPrefix .. (entry.label or entry.name))
            row:SetScript("OnClick", function()
                onSelect(entry.name)
                button.Popup:Hide()
            end)
            row:Show()
        end
        for index = #entries + 1, #self.Rows do self.Rows[index]:Hide() end

        local contentHeight = math.max(1, #entries * rowHeight)
        local popupHeight = math.min(maxHeight, contentHeight + 10)
        self.ScrollChild:SetHeight(contentHeight)
        self.Popup:SetSize(width, popupHeight)
        self.ScrollFrame:SetVerticalScroll(0)
        self.ScrollFrame:UpdateScrollChildRect()
    end

    button.ScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local nextOffset = self:GetVerticalScroll() - (delta * rowHeight * 3)
        self:SetVerticalScroll(Clamp(nextOffset, 0, self:GetVerticalScrollRange()))
    end)
    button:SetScript("OnClick", function(self)
        if self.Popup:IsShown() then
            self.Popup:Hide()
        else
            for _, dropdown in ipairs(parent.scrollableDropdowns) do
                if dropdown ~= self then dropdown.Popup:Hide() end
            end
            self:RefreshEntries()
            self.Popup:Show()
        end
    end)
    button:SetScript("OnDisable", function(self)
        self.Popup:Hide()
        self.Text:SetTextColor(0.5, 0.5, 0.5)
        self.Arrow:SetAlpha(0.45)
    end)
    button:SetScript("OnEnable", function(self)
        self.Text:SetTextColor(1, 1, 1)
        self.Arrow:SetAlpha(1)
    end)
    return button
end

local function SetControlEnabled(control, enabled)
    if control.SetEnabled then
        control:SetEnabled(enabled)
    elseif enabled and control.Enable then
        control:Enable()
    elseif not enabled and control.Disable then
        control:Disable()
    end
end

local function UpdateOptionsControls()
    if not optionsFrame then return end

    optionsFrame.characterValue:SetText(currentCharacterKey or "-")
    optionsFrame.showCheck:SetChecked(db.shown)
    optionsFrame.minimapCheck:SetChecked(not db.minimap.hide)
    local anchored = db.anchorMode ~= "FREE"
    optionsFrame.barStyleDropdown:SetText(optionsFrame.barStyleLabels[db.barStyle])
    optionsFrame.anchorModeDropdown:SetText(optionsFrame.anchorModeLabels[db.anchorMode])
    optionsFrame.anchorPointDropdown:SetText(anchored and db.anchorFrom or db.point)
    optionsFrame.relativePointDropdown:SetText(anchored and db.anchorTo or db.relativePoint)
    optionsFrame.anchorFrameDropdown:SetText(GetAnchorLabel(db.anchorParent))
    optionsFrame.manualAnchorInput:SetText(db.anchorParent)
    optionsFrame.anchorOffsetXInput:SetText(tostring(db.anchorOffsetX))
    optionsFrame.anchorOffsetYInput:SetText(tostring(db.anchorOffsetY))
    optionsFrame.inheritWidthCheck:SetChecked(db.inheritWidth)
    SetSliderValue(optionsFrame.leftOffsetSlider, db.leftOffset)
    SetSliderValue(optionsFrame.rightOffsetSlider, db.rightOffset)
    SetSliderValue(optionsFrame.widthSlider, db.width)
    SetSliderValue(optionsFrame.heightSlider, db.height)
    SetSliderValue(optionsFrame.offsetXSlider, db.x)
    SetSliderValue(optionsFrame.offsetYSlider, db.y)
    SetSliderValue(optionsFrame.windowSlider, db.window)
    SetSliderValue(optionsFrame.minimapAngleSlider, db.minimap.angle)

    for _, control in ipairs(optionsFrame.externalAnchorControls) do
        control:SetAlpha(anchored and 1 or 0.45)
        SetControlEnabled(control, anchored)
    end
    if anchored then
        optionsFrame.anchorFrameDropdown:SetEnabled(true)
    else
        optionsFrame.anchorFrameDropdown:SetEnabled(false)
    end

    local edgeOffsetsEnabled = anchored and db.inheritWidth
    for _, slider in ipairs({ optionsFrame.leftOffsetSlider, optionsFrame.rightOffsetSlider }) do
        SetControlEnabled(slider, edgeOffsetsEnabled)
        SetControlEnabled(slider.input, edgeOffsetsEnabled)
        slider:SetAlpha(edgeOffsetsEnabled and 1 or 0.45)
    end

    local manualWidthEnabled = not (anchored and db.inheritWidth)
    SetControlEnabled(optionsFrame.widthSlider, manualWidthEnabled)
    SetControlEnabled(optionsFrame.widthSlider.input, manualWidthEnabled)
    optionsFrame.widthSlider:SetAlpha(manualWidthEnabled and 1 or 0.45)

    for _, slider in ipairs({ optionsFrame.offsetXSlider, optionsFrame.offsetYSlider }) do
        SetControlEnabled(slider, not anchored)
        SetControlEnabled(slider.input, not anchored)
        slider:SetAlpha(anchored and 0.45 or 1)
    end

    local availableKeys = GetAvailableCharacterKeys()
    local hasProfiles = #availableKeys > 0

    if hasProfiles then
        if not optionsFrame.selectedCopyCharacterKey or not GetCharacterProfiles()[optionsFrame.selectedCopyCharacterKey] then
            optionsFrame.selectedCopyCharacterKey = availableKeys[1]
        end
        optionsFrame.copySourceDropdown:SetEnabled(true)
        optionsFrame.copyButton:Enable()
        optionsFrame.copySourceDropdown:SetText(optionsFrame.selectedCopyCharacterKey)
    else
        optionsFrame.selectedCopyCharacterKey = nil
        optionsFrame.copySourceDropdown:SetEnabled(false)
        optionsFrame.copyButton:Disable()
        optionsFrame.copySourceDropdown:SetText(L.NO_OTHER_CHARACTER)
    end
end

local function SelectOptionsPage(pageName)
    for _, dropdown in ipairs(optionsFrame.scrollableDropdowns or {}) do dropdown.Popup:Hide() end
    optionsFrame.selectedPage = pageName
    for name, controls in pairs(optionsFrame.pageControls) do
        local selected = name == pageName
        for _, control in ipairs(controls) do control:SetShown(selected) end
        local button = optionsFrame.pageButtons[name]
        button.Selected:SetShown(selected)
        button.Text:SetTextColor(selected and 1 or 0.9, selected and 0.82 or 0.9, selected and 0 or 0.9)
    end
    optionsFrame.pageTitle:SetText(optionsFrame.pageLabels[pageName])
end

local function CreateOptionsFrame()
    optionsFrame = CreateFrame("Frame", "LafeeDamageTrackerOptionsFrame", UIParent, "BackdropTemplate")
    optionsFrame:SetSize(1020, 760)
    optionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    optionsFrame:SetFrameStrata("DIALOG")
    optionsFrame:SetClampedToScreen(true)
    optionsFrame:SetMovable(true)
    optionsFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    optionsFrame:SetBackdropColor(0.035, 0.035, 0.035, 0.82)
    optionsFrame:SetBackdropBorderColor(0.24, 0.24, 0.24, 0.95)
    optionsFrame:Hide()

    optionsFrame.titleBar = CreateFrame("Frame", nil, optionsFrame, "BackdropTemplate")
    optionsFrame.titleBar:SetPoint("TOPLEFT", 1, -1)
    optionsFrame.titleBar:SetPoint("TOPRIGHT", -1, -1)
    optionsFrame.titleBar:SetHeight(54)
    optionsFrame.titleBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    optionsFrame.titleBar:SetBackdropColor(0.01, 0.01, 0.01, 0.94)

    optionsFrame.logo = optionsFrame.titleBar:CreateTexture(nil, "ARTWORK")
    optionsFrame.logo:SetPoint("LEFT", 16, 0)
    optionsFrame.logo:SetSize(34, 34)
    optionsFrame.logo:SetTexture("Interface\\Icons\\INV_Shield_06")
    optionsFrame.logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    optionsFrame.title = optionsFrame.titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    optionsFrame.title:SetPoint("LEFT", optionsFrame.logo, "RIGHT", 10, 1)
    optionsFrame.title:SetText(L.ADDON_TITLE)
    optionsFrame.title:SetTextColor(1, 0.82, 0)

    optionsFrame.version = optionsFrame.titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    optionsFrame.version:SetPoint("LEFT", optionsFrame.title, "RIGHT", 12, -1)
    optionsFrame.version:SetText("1.2.0")
    optionsFrame.version:SetTextColor(0.58, 0.6, 0.68)

    optionsFrame.navigation = CreateFrame("Frame", nil, optionsFrame, "BackdropTemplate")
    optionsFrame.navigation:SetPoint("TOPLEFT", 12, -66)
    optionsFrame.navigation:SetPoint("BOTTOMLEFT", 12, 46)
    optionsFrame.navigation:SetWidth(220)
    optionsFrame.navigation:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    optionsFrame.navigation:SetBackdropColor(0.02, 0.02, 0.02, 0.62)
    optionsFrame.navigation:SetBackdropBorderColor(0.18, 0.18, 0.18, 0.9)

    optionsFrame.contentBackground = CreateFrame("Frame", nil, optionsFrame, "BackdropTemplate")
    optionsFrame.contentBackground:SetPoint("TOPLEFT", optionsFrame.navigation, "TOPRIGHT", 14, 0)
    optionsFrame.contentBackground:SetPoint("BOTTOMRIGHT", -14, 46)
    optionsFrame.contentBackground:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    optionsFrame.contentBackground:SetBackdropColor(0.015, 0.015, 0.015, 0.32)

    optionsFrame.pageTitle = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    optionsFrame.pageTitle:SetPoint("TOPLEFT", optionsFrame.contentBackground, "TOPLEFT", 18, -16)
    optionsFrame.pageTitle:SetTextColor(1, 0.82, 0)

    optionsFrame.pageButtons = {}
    optionsFrame.pageLabels = {}
    optionsFrame.pageControls = { GENERAL = {}, APPEARANCE = {}, POSITIONING = {} }
    local previousButton
    for _, pageInfo in ipairs({
        { key = "GENERAL", text = L.GENERAL },
        { key = "APPEARANCE", text = L.APPEARANCE },
        { key = "POSITIONING", text = L.POSITIONING },
    }) do
        local pageKey = pageInfo.key
        local button = CreateFrame("Button", nil, optionsFrame.navigation)
        button:SetSize(204, 38)
        if previousButton then
            button:SetPoint("TOP", previousButton, "BOTTOM", 0, -3)
        else
            button:SetPoint("TOP", 0, -12)
        end
        button.Selected = button:CreateTexture(nil, "BACKGROUND")
        button.Selected:SetAllPoints()
        button.Selected:SetColorTexture(1, 0.82, 0, 0.15)
        button.Selected:Hide()
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.07)
        button.Text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        button.Text:SetPoint("LEFT", 16, 0)
        button.Text:SetPoint("RIGHT", -10, 0)
        button.Text:SetJustifyH("LEFT")
        button.Text:SetText(pageInfo.text)
        button:SetScript("OnClick", function() SelectOptionsPage(pageKey) end)
        optionsFrame.pageButtons[pageKey] = button
        optionsFrame.pageLabels[pageKey] = pageInfo.text
        previousButton = button
    end

    optionsFrame.dragHandle = optionsFrame.titleBar
    optionsFrame.dragHandle:EnableMouse(true)
    optionsFrame.dragHandle:RegisterForDrag("LeftButton")
    optionsFrame.dragHandle:SetScript("OnDragStart", function()
        optionsFrame:StartMoving()
    end)
    optionsFrame.dragHandle:SetScript("OnDragStop", function()
        optionsFrame:StopMovingOrSizing()
    end)

    local function CreateSectionHeader(text, y)
        local section = CreateFrame("Frame", nil, optionsFrame, "BackdropTemplate")
        section:SetPoint("TOPLEFT", 252, y)
        section:SetPoint("TOPRIGHT", -24, y)
        section:SetHeight(38)
        section:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        section:SetBackdropColor(0.01, 0.01, 0.01, 0.78)
        section.text = section:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        section.text:SetPoint("LEFT", 14, 0)
        section.text:SetText(text)
        section.text:SetTextColor(1, 0.82, 0)
        return section
    end

    optionsFrame.generalSection = CreateSectionHeader(L.GENERAL_SETTINGS, -112)
    optionsFrame.profileSection = CreateSectionHeader(L.PROFILES_ACTIONS, -430)
    optionsFrame.appearanceSection = CreateSectionHeader(L.APPEARANCE, -112)
    optionsFrame.anchorSection = CreateSectionHeader(L.ANCHORING, -112)
    optionsFrame.freePositionSection = CreateSectionHeader(L.FREE_POSITION, -550)

    optionsFrame.characterLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.characterLabel:SetPoint("TOPLEFT", 270, -170)
    optionsFrame.characterLabel:SetText(L.ACTIVE_CHARACTER)

    optionsFrame.characterValue = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    optionsFrame.characterValue:SetPoint("TOPLEFT", optionsFrame.characterLabel, "BOTTOMLEFT", 0, -4)
    optionsFrame.characterValue:SetJustifyH("LEFT")
    optionsFrame.characterValue:SetWidth(680)

    optionsFrame.showCheck = CreateFrame("CheckButton", nil, optionsFrame, "UICheckButtonTemplate")
    optionsFrame.showCheck:SetPoint("TOPLEFT", 270, -220)
    optionsFrame.showCheck.text = optionsFrame.showCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.showCheck.text:SetPoint("LEFT", optionsFrame.showCheck, "RIGHT", 4, 1)
    optionsFrame.showCheck.text:SetText(L.SHOW_BAR)
    optionsFrame.showCheck:SetScript("OnClick", function(self)
        db.shown = self:GetChecked() and true or false
        UpdateDisplay()
    end)

    optionsFrame.minimapCheck = CreateFrame("CheckButton", nil, optionsFrame, "UICheckButtonTemplate")
    optionsFrame.minimapCheck:SetPoint("TOPLEFT", 270, -260)
    optionsFrame.minimapCheck.text = optionsFrame.minimapCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.minimapCheck.text:SetPoint("LEFT", optionsFrame.minimapCheck, "RIGHT", 4, 1)
    optionsFrame.minimapCheck.text:SetText(L.SHOW_MINIMAP_BUTTON)
    optionsFrame.minimapCheck:SetScript("OnClick", function(self)
        db.minimap.hide = not self:GetChecked()
        if minimapButton then minimapButton:SetShown(not db.minimap.hide) end
    end)

    optionsFrame.anchorModeLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.anchorModeLabel:SetPoint("TOPLEFT", 270, -170)
    optionsFrame.anchorModeLabel:SetText(L.ANCHOR_MODE)

    optionsFrame.anchorModeLabels = {
        FREE = L.FREE,
        ANCHORED = L.ANCHORED,
    }

    optionsFrame.barStyleLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.barStyleLabel:SetPoint("TOPLEFT", 270, -170)
    optionsFrame.barStyleLabel:SetText(L.STYLE)

    optionsFrame.barStyleLabels = {
        CLASSIC = L.CLASSIC,
        SQUARE = L.SQUARE,
    }
    optionsFrame.barStyleDropdown = CreateScrollableDropdown(optionsFrame, "LDTBarStyleDropdown", 300, 120,
        function()
            return {
                { name = "SQUARE", label = optionsFrame.barStyleLabels.SQUARE },
                { name = "CLASSIC", label = optionsFrame.barStyleLabels.CLASSIC },
            }
        end, function(style)
            db.barStyle = style
            ApplyBarStyle()
            ApplyFrameSize()
            UpdateDisplay()
            UpdateOptionsControls()
        end, function() return db.barStyle end)
    optionsFrame.barStyleDropdown:SetPoint("TOPLEFT", optionsFrame.barStyleLabel, "BOTTOMLEFT", 0, -6)

    optionsFrame.anchorModeDropdown = CreateScrollableDropdown(optionsFrame, "LDTAnchorModeDropdown", 300, 120,
        function()
            return {
                { name = "FREE", label = optionsFrame.anchorModeLabels.FREE },
                { name = "ANCHORED", label = optionsFrame.anchorModeLabels.ANCHORED },
            }
        end, function(mode)
            if db.anchorMode == mode then return end
            db.anchorMode = mode
            ReapplyAnchor()
            UpdateOptionsControls()
        end, function() return db.anchorMode end)
    optionsFrame.anchorModeDropdown:SetPoint("TOPLEFT", optionsFrame.anchorModeLabel, "BOTTOMLEFT", 0, -6)

    optionsFrame.anchorPointLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.anchorPointLabel:SetPoint("TOPLEFT", 270, -320)
    optionsFrame.anchorPointLabel:SetText(L.POINT)
    optionsFrame.anchorPointDropdown = CreateScrollableDropdown(optionsFrame, "LDTAnchorPointDropdown", 300, 250,
        function()
            local entries = {}
            for _, point in ipairs(ANCHOR_POINTS) do entries[#entries + 1] = { name = point, label = point } end
            return entries
        end, function(point)
            if db.anchorMode == "FREE" then db.point = point else db.anchorFrom = point end
            ReapplyAnchor()
            UpdateOptionsControls()
        end, function() return db.anchorMode == "FREE" and db.point or db.anchorFrom end)
    optionsFrame.anchorPointDropdown:SetPoint("TOPLEFT", optionsFrame.anchorPointLabel, "BOTTOMLEFT", 0, -6)

    optionsFrame.relativePointLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.relativePointLabel:SetPoint("TOPLEFT", 600, -320)
    optionsFrame.relativePointLabel:SetText(L.RELATIVE_POINT)
    optionsFrame.relativePointDropdown = CreateScrollableDropdown(optionsFrame, "LDTRelativePointDropdown", 300, 250,
        function()
            local entries = {}
            for _, point in ipairs(ANCHOR_POINTS) do entries[#entries + 1] = { name = point, label = point } end
            return entries
        end, function(point)
            if db.anchorMode == "FREE" then db.relativePoint = point else db.anchorTo = point end
            ReapplyAnchor()
            UpdateOptionsControls()
        end, function() return db.anchorMode == "FREE" and db.relativePoint or db.anchorTo end)
    optionsFrame.relativePointDropdown:SetPoint("TOPLEFT", optionsFrame.relativePointLabel, "BOTTOMLEFT", 0, -6)

    optionsFrame.anchorFrameLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.anchorFrameLabel:SetPoint("TOPLEFT", 270, -240)
    optionsFrame.anchorFrameLabel:SetText(L.ANCHOR_FRAME)

    optionsFrame.anchorFrameDropdown = CreateScrollableDropdown(optionsFrame, "LDTAnchorFrameDropdown", 300, 360,
        GetAvailableAnchorParents, function(anchorName)
            db.anchorParent = anchorName
            ReapplyAnchor()
            UpdateOptionsControls()
        end, function() return db.anchorParent end)
    optionsFrame.anchorFrameDropdown:SetPoint("TOPLEFT", optionsFrame.anchorFrameLabel, "BOTTOMLEFT", 0, -6)

    optionsFrame.manualAnchorLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.manualAnchorLabel:SetPoint("TOPLEFT", 600, -240)
    optionsFrame.manualAnchorLabel:SetText(L.MANUAL_FRAME)

    optionsFrame.manualAnchorInput = CreateFrame("EditBox", "LDTManualAnchorInput", optionsFrame, "InputBoxTemplate")
    optionsFrame.manualAnchorInput:SetAutoFocus(false)
    optionsFrame.manualAnchorInput:SetMaxLetters(80)
    optionsFrame.manualAnchorInput:SetSize(300, 26)
    optionsFrame.manualAnchorInput:SetPoint("TOPLEFT", optionsFrame.manualAnchorLabel, "BOTTOMLEFT", 0, -6)
    local function SaveAnchorName(self)
        local anchorName = (self:GetText() or ""):match("^%s*(.-)%s*$")
        if anchorName == "" then
            anchorName = DEFAULTS.anchorParent
        end
        local changed = db.anchorParent ~= anchorName
        db.anchorParent = anchorName
        self:SetText(anchorName)
        if changed then
            ReapplyAnchor()
            UpdateOptionsControls()
        end
    end
    optionsFrame.manualAnchorInput:SetScript("OnEnterPressed", function(self)
        SaveAnchorName(self)
        self:ClearFocus()
    end)
    optionsFrame.manualAnchorInput:SetScript("OnEscapePressed", function(self)
        self:SetText(db.anchorParent)
        self:ClearFocus()
    end)
    optionsFrame.manualAnchorInput:SetScript("OnEditFocusLost", SaveAnchorName)

    local function CreateAnchorOffsetInput(name, label, x, key)
        local labelFrame = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        labelFrame:SetPoint("TOPLEFT", x, -405)
        labelFrame:SetText(label)

        local input = CreateFrame("EditBox", name, optionsFrame, "InputBoxTemplate")
        input:SetAutoFocus(false)
        input:SetNumeric(false)
        input:SetMaxLetters(5)
        input:SetJustifyH("CENTER")
        input:SetSize(48, 20)
        input:SetPoint("LEFT", labelFrame, "RIGHT", 4, 0)

        local function SaveValue()
            local value = Clamp(tonumber(input:GetText()) or db[key], MIN_ANCHOR_OFFSET, MAX_ANCHOR_OFFSET)
            db[key] = math.floor(value + 0.5)
            db.bcdmOffsetX = db.anchorOffsetX
            db.bcdmOffsetY = db.anchorOffsetY
            input:SetText(tostring(db[key]))
            ReapplyAnchor()
        end

        input:SetScript("OnEnterPressed", function(self)
            SaveValue()
            self:ClearFocus()
        end)
        input:SetScript("OnEscapePressed", function(self)
            self:SetText(tostring(db[key]))
            self:ClearFocus()
        end)
        input:SetScript("OnEditFocusLost", SaveValue)
        input.label = labelFrame
        return input
    end

    optionsFrame.anchorOffsetXInput = CreateAnchorOffsetInput("LDTAnchorOffsetXInput", L.OFFSET_X, 270, "anchorOffsetX")
    optionsFrame.anchorOffsetYInput = CreateAnchorOffsetInput("LDTAnchorOffsetYInput", L.OFFSET_Y, 600, "anchorOffsetY")
    optionsFrame.externalAnchorControls = {
        optionsFrame.anchorFrameLabel,
        optionsFrame.anchorFrameDropdown,
        optionsFrame.manualAnchorLabel,
        optionsFrame.manualAnchorInput,
        optionsFrame.anchorOffsetXInput.label,
        optionsFrame.anchorOffsetXInput,
        optionsFrame.anchorOffsetYInput.label,
        optionsFrame.anchorOffsetYInput,
    }

    optionsFrame.inheritWidthCheck = CreateFrame("CheckButton", nil, optionsFrame, "UICheckButtonTemplate")
    optionsFrame.inheritWidthCheck:SetPoint("TOPLEFT", 270, -445)
    optionsFrame.inheritWidthCheck.text = optionsFrame.inheritWidthCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.inheritWidthCheck.text:SetPoint("LEFT", optionsFrame.inheritWidthCheck, "RIGHT", 4, 1)
    optionsFrame.inheritWidthCheck.text:SetText(L.INHERIT_WIDTH)
    optionsFrame.inheritWidthCheck:SetScript("OnClick", function(self)
        db.inheritWidth = self:GetChecked() and true or false
        db.matchPowerBarWidth = db.inheritWidth
        ReapplyAnchor()
        UpdateOptionsControls()
    end)

    optionsFrame.leftOffsetSlider = CreateSlider(optionsFrame, "LDTLeftOffsetSlider", L.LEFT_OFFSET, 0, MAX_EDGE_OFFSET, 1, 150)
    optionsFrame.leftOffsetSlider:SetPoint("TOPLEFT", 300, -495)
    optionsFrame.leftOffsetSlider:SetScript("OnValueChanged", function(self, value)
        if self._internalUpdate then return end
        db.leftOffset = math.floor(value + 0.5)
        ReapplyAnchor()
        self.input:SetText(tostring(db.leftOffset))
    end)

    optionsFrame.rightOffsetSlider = CreateSlider(optionsFrame, "LDTRightOffsetSlider", L.RIGHT_OFFSET, 0, MAX_EDGE_OFFSET, 1, 150)
    optionsFrame.rightOffsetSlider:SetPoint("TOPLEFT", 650, -495)
    optionsFrame.rightOffsetSlider:SetScript("OnValueChanged", function(self, value)
        if self._internalUpdate then return end
        db.rightOffset = math.floor(value + 0.5)
        ReapplyAnchor()
        self.input:SetText(tostring(db.rightOffset))
    end)
    table.insert(optionsFrame.externalAnchorControls, optionsFrame.inheritWidthCheck)
    table.insert(optionsFrame.externalAnchorControls, optionsFrame.leftOffsetSlider)
    table.insert(optionsFrame.externalAnchorControls, optionsFrame.leftOffsetSlider.input)
    table.insert(optionsFrame.externalAnchorControls, optionsFrame.rightOffsetSlider)
    table.insert(optionsFrame.externalAnchorControls, optionsFrame.rightOffsetSlider.input)

    optionsFrame.widthSlider = CreateSlider(optionsFrame, "LDTWidthSlider", L.WIDTH, MIN_WIDTH, MAX_WIDTH, 10, 220)
    optionsFrame.widthSlider:SetPoint("TOPLEFT", 300, -270)
    optionsFrame.widthSlider:SetScript("OnValueChanged", function(self, value)
        if self._internalUpdate then return end
        db.width = math.floor(value + 0.5)
        RefreshLayout()
        self.input:SetText(tostring(db.width))
    end)

    optionsFrame.heightSlider = CreateSlider(optionsFrame, "LDTHeightSlider", L.HEIGHT, MIN_HEIGHT, MAX_HEIGHT, 1, 220)
    optionsFrame.heightSlider:SetPoint("TOPLEFT", 650, -270)
    optionsFrame.heightSlider:SetScript("OnValueChanged", function(self, value)
        if self._internalUpdate then return end
        db.height = math.floor(value + 0.5)
        RefreshLayout()
        self.input:SetText(tostring(db.height))
    end)

    optionsFrame.offsetXSlider = CreateSlider(optionsFrame, "LDTOffsetXSlider", L.OFFSET_X, -600, 600, 5, 220)
    optionsFrame.offsetXSlider:SetPoint("TOPLEFT", 300, -620)
    optionsFrame.offsetXSlider:SetScript("OnValueChanged", function(self, value)
        if self._internalUpdate then return end
        db.x = math.floor(value + 0.5)
        ApplyFramePosition()
        self.input:SetText(tostring(db.x))
    end)

    optionsFrame.offsetYSlider = CreateSlider(optionsFrame, "LDTOffsetYSlider", L.OFFSET_Y, -400, 400, 5, 220)
    optionsFrame.offsetYSlider:SetPoint("TOPLEFT", 650, -620)
    optionsFrame.offsetYSlider:SetScript("OnValueChanged", function(self, value)
        if self._internalUpdate then return end
        db.y = math.floor(value + 0.5)
        ApplyFramePosition()
        self.input:SetText(tostring(db.y))
    end)

    optionsFrame.windowSlider = CreateSlider(optionsFrame, "LDTWindowSlider", L.WINDOW_SECONDS, MIN_WINDOW, MAX_WINDOW, 1, 220)
    optionsFrame.windowSlider:SetPoint("TOPLEFT", 300, -330)
    optionsFrame.windowSlider:SetScript("OnValueChanged", function(self, value)
        if self._internalUpdate then return end
        db.window = Clamp(math.floor(value + 0.5), MIN_WINDOW, MAX_WINDOW)
        UpdateDisplay()
        self.input:SetText(tostring(db.window))
    end)

    optionsFrame.minimapAngleSlider = CreateSlider(optionsFrame, "LDTMinimapAngleSlider", L.MINIMAP_ANGLE, 0, 359, 1, 220)
    optionsFrame.minimapAngleSlider:SetPoint("TOPLEFT", 650, -330)
    optionsFrame.minimapAngleSlider:SetScript("OnValueChanged", function(self, value)
        if self._internalUpdate then return end
        db.minimap.angle = math.floor(value + 0.5) % 360
        UpdateMinimapButtonPosition()
        self.input:SetText(tostring(db.minimap.angle))
    end)

    optionsFrame.copyLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.copyLabel:SetPoint("TOPLEFT", 270, -485)
    optionsFrame.copyLabel:SetText(L.COPY_FROM)

    optionsFrame.copySourceDropdown = CreateScrollableDropdown(optionsFrame, "LDTCopyProfileDropdown", 300, 300,
        function()
            local entries = {}
            for _, characterKey in ipairs(GetAvailableCharacterKeys()) do
                entries[#entries + 1] = { name = characterKey, label = characterKey }
            end
            return entries
        end, function(characterKey)
            optionsFrame.selectedCopyCharacterKey = characterKey
            optionsFrame.copySourceDropdown:SetText(characterKey)
        end, function() return optionsFrame.selectedCopyCharacterKey end)
    optionsFrame.copySourceDropdown:SetPoint("TOPLEFT", optionsFrame.copyLabel, "BOTTOMLEFT", 0, -6)

    optionsFrame.copyButton = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
    optionsFrame.copyButton:SetSize(110, 22)
    optionsFrame.copyButton:SetPoint("TOPLEFT", optionsFrame.copySourceDropdown, "BOTTOMLEFT", 0, -10)
    optionsFrame.copyButton:SetText(L.COPY)
    optionsFrame.copyButton:SetScript("OnClick", function()
        local sourceKey = optionsFrame.selectedCopyCharacterKey
        local sourceProfile = sourceKey and GetCharacterProfiles()[sourceKey]
        if not sourceProfile then
            print("|cffff7f50" .. L.ADDON_TITLE .. "|r : " .. L.NO_SOURCE_PROFILE)
            return
        end

        rootDB.characters[currentCharacterKey] = DeepCopy(sourceProfile)
        RefreshActiveProfile()
        ResetDamageTotals()
        ReapplyAnchor()
        UpdateMinimapButtonPosition()
        if minimapButton then
            minimapButton:SetShown(not db.minimap.hide)
        end
        UpdateOptionsControls()
        print("|cff00ff98" .. L.ADDON_TITLE .. "|r : " .. string.format(L.COPIED_FROM, sourceKey))
    end)

    optionsFrame.resetButton = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
    optionsFrame.resetButton:SetSize(180, 22)
    optionsFrame.resetButton:SetPoint("TOPLEFT", 650, -510)
    optionsFrame.resetButton:SetText(L.RESET_POSITION)
    optionsFrame.resetButton:SetScript("OnClick", function()
        db.point, db.relativePoint = DEFAULTS.point, DEFAULTS.relativePoint
        db.x, db.y = DEFAULTS.x, DEFAULTS.y
        RefreshLayout()
        UpdateOptionsControls()
    end)

    optionsFrame.clearButton = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
    optionsFrame.clearButton:SetSize(180, 22)
    optionsFrame.clearButton:SetPoint("TOP", optionsFrame.resetButton, "BOTTOM", 0, -10)
    optionsFrame.clearButton:SetText(L.CLEAR_DAMAGE)
    optionsFrame.clearButton:SetScript("OnClick", function()
        ResetDamageTotals()
        UpdateDisplay()
    end)

    optionsFrame.sliders = {
        optionsFrame.leftOffsetSlider,
        optionsFrame.rightOffsetSlider,
        optionsFrame.widthSlider,
        optionsFrame.heightSlider,
        optionsFrame.offsetXSlider,
        optionsFrame.offsetYSlider,
        optionsFrame.windowSlider,
        optionsFrame.minimapAngleSlider,
    }

    optionsFrame.footer = CreateFrame("Frame", nil, optionsFrame, "BackdropTemplate")
    optionsFrame.footer:SetPoint("BOTTOMLEFT", 1, 1)
    optionsFrame.footer:SetPoint("BOTTOMRIGHT", -1, 1)
    optionsFrame.footer:SetHeight(34)
    optionsFrame.footer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    optionsFrame.footer:SetBackdropColor(0.01, 0.01, 0.01, 0.92)
    optionsFrame.footer.text = optionsFrame.footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    optionsFrame.footer.text:SetPoint("LEFT", 14, 0)
    optionsFrame.footer.text:SetText("Lafee Damage Tracker API v1  •  /ldt config")
    optionsFrame.footer.text:SetTextColor(0.62, 0.64, 0.7)

    optionsFrame.closeButton = CreateFrame("Button", nil, optionsFrame.titleBar, "UIPanelCloseButton")
    optionsFrame.closeButton:SetPoint("RIGHT", -6, 0)
    optionsFrame.closeButton:SetScript("OnClick", function()
        if GetCurrentKeyBoardFocus() then
            GetCurrentKeyBoardFocus():ClearFocus()
        end
        optionsFrame:Hide()
    end)

    local function AddPageControls(pageName, ...)
        local controls = optionsFrame.pageControls[pageName]
        for index = 1, select("#", ...) do controls[#controls + 1] = select(index, ...) end
    end
    AddPageControls("GENERAL",
        optionsFrame.generalSection, optionsFrame.profileSection,
        optionsFrame.characterLabel, optionsFrame.characterValue, optionsFrame.showCheck,
        optionsFrame.minimapCheck, optionsFrame.windowSlider, optionsFrame.windowSlider.input,
        optionsFrame.minimapAngleSlider, optionsFrame.minimapAngleSlider.input,
        optionsFrame.copyLabel, optionsFrame.copySourceDropdown, optionsFrame.copyButton,
        optionsFrame.resetButton, optionsFrame.clearButton)
    AddPageControls("APPEARANCE",
        optionsFrame.appearanceSection,
        optionsFrame.barStyleLabel, optionsFrame.barStyleDropdown,
        optionsFrame.widthSlider, optionsFrame.widthSlider.input,
        optionsFrame.heightSlider, optionsFrame.heightSlider.input)
    AddPageControls("POSITIONING",
        optionsFrame.anchorSection, optionsFrame.freePositionSection,
        optionsFrame.anchorModeLabel, optionsFrame.anchorModeDropdown,
        optionsFrame.anchorFrameLabel, optionsFrame.anchorFrameDropdown,
        optionsFrame.manualAnchorLabel, optionsFrame.manualAnchorInput,
        optionsFrame.anchorPointLabel, optionsFrame.anchorPointDropdown,
        optionsFrame.relativePointLabel, optionsFrame.relativePointDropdown,
        optionsFrame.anchorOffsetXInput.label, optionsFrame.anchorOffsetXInput,
        optionsFrame.anchorOffsetYInput.label, optionsFrame.anchorOffsetYInput,
        optionsFrame.inheritWidthCheck,
        optionsFrame.leftOffsetSlider, optionsFrame.leftOffsetSlider.input,
        optionsFrame.rightOffsetSlider, optionsFrame.rightOffsetSlider.input,
        optionsFrame.offsetXSlider, optionsFrame.offsetXSlider.input,
        optionsFrame.offsetYSlider, optionsFrame.offsetYSlider.input)

    SelectOptionsPage("GENERAL")
end

local function ToggleOptionsFrame()
    if not optionsFrame then
        CreateOptionsFrame()
    end

    if optionsFrame:IsShown() then
        optionsFrame:Hide()
    else
        UpdateOptionsControls()
        optionsFrame:Show()
    end
end

local function CreateMinimapButton()
    if minimapButton then return end

    minimapButton = CreateFrame("Button", "LafeeDamageTrackerMinimapButton", Minimap)
    minimapButton:SetSize(32, 32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetMovable(true)
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")

    minimapButton.icon = minimapButton:CreateTexture(nil, "ARTWORK", nil, 1)
    minimapButton.icon:SetTexture("Interface\\Icons\\INV_Shield_06")
    minimapButton.icon:SetSize(22, 22)
    minimapButton.icon:SetPoint("CENTER")
    minimapButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L.ADDON_TITLE)
        GameTooltip:AddLine(L.TOOLTIP_LEFT_CLICK, 1, 1, 1)
        GameTooltip:AddLine(L.TOOLTIP_RIGHT_CLICK, 1, 1, 1)
        GameTooltip:AddLine(L.TOOLTIP_DRAG, 1, 1, 1)
        GameTooltip:Show()
    end)

    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    minimapButton:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            ToggleOptionsFrame()
        else
            db.shown = not db.shown
            UpdateDisplay()
            if optionsFrame and optionsFrame:IsShown() then
                UpdateOptionsControls()
            end
        end
    end)

    minimapButton:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local cursorX, cursorY = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local centerX, centerY = Minimap:GetCenter()
            local x = cursorX / scale - centerX
            local y = cursorY / scale - centerY
            db.minimap.angle = GetAngleDegrees(x, y)
            UpdateMinimapButtonPosition()
        end)
    end)

    minimapButton:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    minimapButton:SetShown(not db.minimap.hide)
    UpdateMinimapButtonPosition()
end

local function CreateUI()
    anchorFrame:SetClampedToScreen(true)
    anchorFrame:SetMovable(true)
    anchorFrame:EnableMouse(true)
    anchorFrame:RegisterForDrag("LeftButton")

    anchorFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    anchorFrame:SetBackdropColor(0, 0, 0, 0)

    anchorFrame:SetScript("OnDragStart", function(self)
        if db.anchorMode == "FREE" and not externalAnchors.Main then
            self:StartMoving()
        end
    end)

    anchorFrame:SetScript("OnDragStop", function(self)
        if db.anchorMode ~= "FREE" or externalAnchors.Main then return end
        self:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
        db.point = point
        db.relativePoint = relativePoint
        db.x = math.floor(xOfs + 0.5)
        db.y = math.floor(yOfs + 0.5)
        if optionsFrame and optionsFrame:IsShown() then
            UpdateOptionsControls()
        end
    end)

    barFrame = CreateFrame("Frame", "LafeeDamageTrackerBarFrame", anchorFrame, "BackdropTemplate")
    barFrame:SetAllPoints(anchorFrame)

    barFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    barFrame:SetBackdropColor(0.08, 0.08, 0.08, 0.35)
    barFrame:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)

    barFrame.phys = barFrame:CreateTexture(nil, "ARTWORK")
    barFrame.phys:SetPoint("LEFT", BAR_INSET, 0)
    barFrame.phys:SetTexture("Interface\\Buttons\\WHITE8X8")
    barFrame.phys:SetColorTexture(0.82, 0.82, 0.82, 0.95)

    barFrame.magic = barFrame:CreateTexture(nil, "ARTWORK")
    barFrame.magic:SetTexture("Interface\\Buttons\\WHITE8X8")
    barFrame.magic:SetColorTexture(0.55, 0.20, 0.85, 0.95)

    barFrame.separator = barFrame:CreateTexture(nil, "OVERLAY")
    barFrame.separator:SetWidth(1)
    barFrame.separator:SetColorTexture(1, 1, 1, 0.9)

    RefreshLayout()
end

local function OnUnitCombat(unitTarget, action, _, amount, schoolMask)
    if unitTarget ~= "player" then return end
    if action ~= "WOUND" then return end

    AddDamageTaken(amount, schoolMask)
    UpdateDisplay()
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= addonName then
            if db and (db.anchorMode ~= "FREE" or externalAnchors.Main) then ReapplyAnchor() end
            return
        end

        LafeeDamageTrackerDB = LafeeDamageTrackerDB or {}
        rootDB = LafeeDamageTrackerDB
        currentCharacterKey = GetCharacterKey()

        if not rootDB.characters then
            local migratedProfile = {}
            local hasLegacyData = false
            local legacyKeys = {}

            for key, value in pairs(rootDB) do
                if key ~= "characters" then
                    table.insert(legacyKeys, key)
                    migratedProfile[key] = DeepCopy(value)
                    hasLegacyData = true
                end
            end

            for _, key in ipairs(legacyKeys) do
                rootDB[key] = nil
            end

            rootDB.characters = {}
            if hasLegacyData then
                rootDB.characters[currentCharacterKey] = migratedProfile
            end
        end

        rootDB.characters[currentCharacterKey] = rootDB.characters[currentCharacterKey] or {}
        RefreshActiveProfile()

        CreateUI()
    elseif event == "PLAYER_LOGIN" then
        CreateMinimapButton()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ResetDamageTotals()
        ReapplyAnchor()
        UpdateDisplay()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit == "player" then
            ReapplyAnchor()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        UpdateDisplay()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ResetDamageTotals()
        if pendingAnchorUpdate then
            ReapplyAnchor()
        end
        UpdateDisplay()
    elseif event == "UNIT_COMBAT" then
        OnUnitCombat(...)
    end
end)

eventFrame:SetScript("OnUpdate", function(_, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate >= 0.1 then
        elapsedSinceUpdate = 0
        if db and db.shown then
            UpdateDisplay()
        end
    end
end)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("UNIT_COMBAT")

-- Public integration API. See docs/API.md for the supported contract.
local API = _G.LafeeDamageTrackerAPI or {}
_G.LafeeDamageTrackerAPI = API
API.VERSION = 1
API.version = API.VERSION

local PUBLIC_OPTIONS = {
    point = true, relativePoint = true, x = true, y = true,
    width = true, height = true, shown = true, window = true,
    anchorMode = true, anchorPosition = true, anchorSpacing = true,
    anchorFrom = true, anchorParent = true, anchorTo = true,
    inheritWidth = true, leftOffset = true, rightOffset = true,
    anchorOffsetX = true, anchorOffsetY = true,
    matchPowerBarWidth = true,
    bcdmOffsetX = true, bcdmOffsetY = true, barStyle = true,
}

local function RefreshAfterPublicOptionChange(option)
    RefreshActiveProfile()
    if option == "minimap.hide" then
        if minimapButton then minimapButton:SetShown(not db.minimap.hide) end
    elseif option == "minimap.angle" then
        UpdateMinimapButtonPosition()
    else
        ReapplyAnchor()
        UpdateDisplay()
    end
    if optionsFrame and optionsFrame:IsShown() then UpdateOptionsControls() end
end

function API:IsReady()
    return db ~= nil and rootDB ~= nil
end

function API:GetVersion()
    return self.VERSION
end

function API:GetAnchor(anchorName)
    if anchorName == "Main" then return anchorFrame end
    return nil
end

local function NormalizeExternalAnchorOptions(options)
    options = type(options) == "table" and options or {}
    local point = options.point or "TOP"
    local relativePoint = options.relativePoint or "BOTTOM"
    if not VALID_ANCHOR_POINTS[point] or not VALID_ANCHOR_POINTS[relativePoint] then
        return nil, "invalid-point"
    end

    local x = tonumber(options.x) or 0
    local y = tonumber(options.y) or 0
    local leftOffset = tonumber(options.leftOffset) or 0
    local rightOffset = tonumber(options.rightOffset) or 0
    if leftOffset < 0 or rightOffset < 0 then return nil, "invalid-offset" end

    return {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
        inheritWidth = options.inheritWidth == true,
        leftOffset = leftOffset,
        rightOffset = rightOffset,
    }
end

function API:SetExternalAnchor(anchorName, externalFrame, options)
    if anchorName ~= "Main" then return false, "unknown-anchor" end
    if externalFrame == anchorFrame or not IsFrameObject(externalFrame) then return false, "invalid-frame" end
    local normalizedOptions, errorCode = NormalizeExternalAnchorOptions(options)
    if not normalizedOptions then return false, errorCode end

    externalAnchors.Main = { frame = externalFrame, options = normalizedOptions }
    if db then ReapplyAnchor() end
    return true
end

function API:ClearExternalAnchor(anchorName)
    if anchorName ~= "Main" then return false, "unknown-anchor" end
    externalAnchors.Main = nil
    if db then ReapplyAnchor() end
    return true
end

function API:GetOption(option)
    if not db then return nil end
    if option == "minimap.hide" then return db.minimap.hide end
    if option == "minimap.angle" then return db.minimap.angle end
    if option == "matchPowerBarWidth" then return db.inheritWidth end
    if option == "bcdmOffsetX" then return db.anchorOffsetX end
    if option == "bcdmOffsetY" then return db.anchorOffsetY end
    if not PUBLIC_OPTIONS[option] then return nil end
    return db[option]
end

function API:SetOption(option, value)
    if not db then return false, "not-ready" end
    if option == "minimap.hide" then
        db.minimap.hide = value == true
    elseif option == "minimap.angle" then
        local angle = tonumber(value)
        if not angle then return false, "invalid-value" end
        db.minimap.angle = angle % 360
    elseif option == "anchorFrom" or option == "anchorTo" then
        if not VALID_ANCHOR_POINTS[value] then return false, "invalid-value" end
        db[option] = value
    elseif option == "anchorParent" then
        if type(value) ~= "string" or value == "" then return false, "invalid-value" end
        db.anchorParent = value
    elseif option == "anchorMode" then
        if value == "BETTER_COOLDOWN_MANAGER" or value == "ELVUI" then value = "ANCHORED" end
        if value ~= "FREE" and value ~= "ANCHORED" then return false, "invalid-value" end
        db.anchorMode = value
    elseif option == "matchPowerBarWidth" or option == "inheritWidth" then
        db.inheritWidth = value == true
        db.matchPowerBarWidth = db.inheritWidth
    elseif option == "bcdmOffsetX" or option == "anchorOffsetX" then
        db.anchorOffsetX = value
        db.bcdmOffsetX = value
    elseif option == "bcdmOffsetY" or option == "anchorOffsetY" then
        db.anchorOffsetY = value
        db.bcdmOffsetY = value
    elseif PUBLIC_OPTIONS[option] then
        db[option] = value
    else
        return false, "unknown-option"
    end
    RefreshAfterPublicOptionChange(option)
    return true
end

function API:GetCurrentCharacterKey()
    return currentCharacterKey
end

function API:GetCharacterKeys()
    local keys = {}
    for characterKey in pairs(GetCharacterProfiles()) do keys[#keys + 1] = characterKey end
    table.sort(keys)
    return keys
end

function API:CopyProfile(sourceKey)
    if not db or type(sourceKey) ~= "string" then return false, "invalid-source" end
    local sourceProfile = GetCharacterProfiles()[sourceKey]
    if not sourceProfile or sourceKey == currentCharacterKey then return false, "invalid-source" end
    rootDB.characters[currentCharacterKey] = DeepCopy(sourceProfile)
    RefreshActiveProfile()
    ResetDamageTotals()
    ReapplyAnchor()
    UpdateMinimapButtonPosition()
    if minimapButton then minimapButton:SetShown(not db.minimap.hide) end
    if optionsFrame and optionsFrame:IsShown() then UpdateOptionsControls() end
    return true
end

function API:GetAnchorPoints()
    local points = {}
    for _, point in ipairs(ANCHOR_POINTS) do
        points[#points + 1] = { name = point, label = point }
    end
    return points
end

function API:GetAnchorParents()
    local parents = GetAvailableAnchorParents()
    local current = db and db.anchorParent
    if type(current) == "string" and current ~= "" then
        local found = false
        for _, anchor in ipairs(parents) do
            if anchor.name == current then found = true break end
        end
        if not found then parents[#parents + 1] = { name = current, label = current } end
    end
    return parents
end

function API:ResetPosition()
    if not db then return false, "not-ready" end
    db.point, db.relativePoint = DEFAULTS.point, DEFAULTS.relativePoint
    db.x, db.y = DEFAULTS.x, DEFAULTS.y
    RefreshLayout()
    if optionsFrame and optionsFrame:IsShown() then UpdateOptionsControls() end
    return true
end

function API:ClearDamage()
    if not db then return false, "not-ready" end
    ResetDamageTotals()
    UpdateDisplay()
    return true
end

function API:Refresh()
    if not db then return false, "not-ready" end
    RefreshLayout()
    UpdateMinimapButtonPosition()
    if minimapButton then minimapButton:SetShown(not db.minimap.hide) end
    if optionsFrame and optionsFrame:IsShown() then UpdateOptionsControls() end
    return true
end

function API:GetTrackerFrame()
    return anchorFrame
end

function API:OpenOptions()
    if not db then return false, "not-ready" end
    if not optionsFrame or not optionsFrame:IsShown() then ToggleOptionsFrame() end
    return true
end

SLASH_LAFEEDAMAGETRACKER1 = "/ldt"
SlashCmdList["LAFEEDAMAGETRACKER"] = function(msg)
    msg = (msg or ""):lower()

    if msg == "reset" then
        db.point = DEFAULTS.point
        db.relativePoint = DEFAULTS.relativePoint
        db.x = DEFAULTS.x
        db.y = DEFAULTS.y
        RefreshLayout()
        if optionsFrame and optionsFrame:IsShown() then
            UpdateOptionsControls()
        end
        print("|cff00ff98" .. L.ADDON_TITLE .. "|r : " .. L.POSITION_RESET)
        return
    end

    if msg == "clear" then
        ResetDamageTotals()
        UpdateDisplay()
        print("|cff00ff98" .. L.ADDON_TITLE .. "|r : " .. L.DAMAGE_RESET)
        return
    end

    if msg == "config" then
        ToggleOptionsFrame()
        return
    end

    db.shown = not db.shown
    UpdateDisplay()
    if optionsFrame and optionsFrame:IsShown() then
        UpdateOptionsControls()
    end
    print("|cff00ff98" .. L.ADDON_TITLE .. "|r : " .. (db.shown and L.BAR_SHOWN or L.BAR_HIDDEN))
end
