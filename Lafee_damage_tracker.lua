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
    matchPowerBarWidth = true,
    bcdmAnchor = "BCDM_PowerBar",
    anchorFrom = "BOTTOM",
    anchorParent = "BCDM_PowerBar",
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
local MIN_BCDM_OFFSET = -500
local MAX_BCDM_OFFSET = 500

local BCDM_ANCHORS = {
    { name = "BCDM_PowerBar", label = L.POWER_BAR },
    { name = "BCDM_SecondaryPowerBar", label = L.SECONDARY_POWER_BAR },
    { name = "BCDM_CastBar", label = L.CAST_BAR },
    { name = "BCDM_CustomCooldownViewer", label = L.CUSTOM_BAR },
    { name = "BCDM_AdditionalCustomCooldownViewer", label = L.SECONDARY_CUSTOM_BAR },
    { name = "BCDM_CustomItemBar", label = L.ITEM_BAR },
    { name = "BCDM_CustomItemSpellBar", label = L.ITEM_SPELL_BAR },
    { name = "BCDM_TrinketBar", label = L.TRINKET_BAR },
}

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
    { name = "BCDM_PowerBar", label = "|cFF8080FFBCDM|r: Power Bar" },
    { name = "BCDM_SecondaryPowerBar", label = "|cFF8080FFBCDM|r: Secondary Power Bar" },
    { name = "BCDM_CastBar", label = "|cFF8080FFBCDM|r: Cast Bar" },
    { name = "BCDM_CustomCooldownViewer", label = "|cFF8080FFBCDM|r: Custom Bar" },
    { name = "BCDM_AdditionalCustomCooldownViewer", label = "|cFF8080FFBCDM|r: Secondary Custom Bar" },
    { name = "BCDM_CustomItemBar", label = "|cFF8080FFBCDM|r: Item Bar" },
    { name = "BCDM_CustomItemSpellBar", label = "|cFF8080FFBCDM|r: Item/Spell Bar" },
    { name = "BCDM_TrinketBar", label = "|cFF8080FFBCDM|r: Trinket Bar" },
    { name = "ElvUF_Player", label = "|cff1784d1ElvUI|r: Player Frame" },
    { name = "ElvUF_Target", label = "|cff1784d1ElvUI|r: Target Frame" },
}

local db
local rootDB
local damageEvents = {}
local currentCharacterKey

local frame = CreateFrame("Frame", "LafeeDamageTrackerFrame", UIParent, "BackdropTemplate")
local minimapButton
local optionsFrame
local elapsedSinceUpdate = 0
local unpackFn = unpack or table.unpack
local isAnchoredToPowerBar = false
local pendingAnchorUpdate = false
local anchorRetryAttempts = 0
local anchorRetryScheduled = false
local ScheduleAnchorRetry

local function GetElvUI()
    local engine = _G.ElvUI
    if type(engine) == "table" then
        return unpackFn(engine)
    end
end

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
    db.matchPowerBarWidth = db.matchPowerBarWidth ~= false
    if type(db.bcdmAnchor) ~= "string" or db.bcdmAnchor == "" then
        db.bcdmAnchor = DEFAULTS.bcdmAnchor
    end
    if legacyAnchor then
        db.anchorParent = db.anchorMode == "ELVUI" and "ElvUF_Player" or db.bcdmAnchor
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
    db.bcdmOffsetX = Clamp(tonumber(db.bcdmOffsetX) or DEFAULTS.bcdmOffsetX, MIN_BCDM_OFFSET, MAX_BCDM_OFFSET)
    db.bcdmOffsetY = Clamp(tonumber(db.bcdmOffsetY) or DEFAULTS.bcdmOffsetY, MIN_BCDM_OFFSET, MAX_BCDM_OFFSET)
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

local function GetPowerBarAnchor()
    if db.anchorMode == "FREE" then return nil end
    if db.anchorParent == "UIParent" then return UIParent end
    return _G[db.anchorParent]
end

local function GetAnchorOffsets()
    return db.bcdmOffsetX, db.bcdmOffsetY
end

local function GetBCDMAnchorLabel(anchorName)
    for _, anchor in ipairs(BCDM_ANCHORS) do
        if anchor.name == anchorName then
            return anchor.label
        end
    end
    return anchorName
end

local function GetDropdownItemText(text, selected)
    if selected then
        return "|cff00ff98> |r" .. text
    end
    return "   " .. text
end

local function ApplyFreeFramePosition()
    frame:ClearAllPoints()
    frame:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
end

local function GetBarInset()
    return db.barStyle == "SQUARE" and 1 or BAR_INSET
end

local function ApplyBarStyle()
    if not frame.bar then return end

    if db.barStyle == "CLASSIC" then
        frame.bar:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame.bar:SetBackdropColor(0.08, 0.08, 0.08, 0.35)
        frame.bar:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)
    else
        frame.bar:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        frame.bar:SetBackdropColor(0.03, 0.03, 0.03, 0.9)
        frame.bar:SetBackdropBorderColor(0.02, 0.02, 0.02, 1)
    end

    frame.bar.phys:ClearAllPoints()
    frame.bar.phys:SetPoint("LEFT", GetBarInset(), 0)
end

local function ApplyFramePosition()
    local powerBar = GetPowerBarAnchor()
    local offsetX, offsetY = GetAnchorOffsets()

    if powerBar then
        if InCombatLockdown() then
            pendingAnchorUpdate = true
            return
        end

        isAnchoredToPowerBar = true
        frame:ClearAllPoints()
        frame:SetPoint(db.anchorFrom, powerBar, db.anchorTo, offsetX, offsetY)
        return
    end

    isAnchoredToPowerBar = false
    ApplyFreeFramePosition()
    if db.anchorMode ~= "FREE" and ScheduleAnchorRetry then
        ScheduleAnchorRetry()
    end
end

local function ApplyFrameSize()
    if isAnchoredToPowerBar and db.matchPowerBarWidth then
        local anchorFrame = GetPowerBarAnchor()
        local anchorWidth = anchorFrame and anchorFrame:GetWidth()
        frame:SetWidth(type(anchorWidth) == "number" and anchorWidth > 0 and anchorWidth or (db.width + 20))
        frame:SetHeight(db.height + 12)
        frame.bar:ClearAllPoints()
        frame.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -4)
        frame.bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -4)
        frame.bar:SetHeight(db.height)
    else
        frame:SetSize(db.width + 20, db.height + 12)
        frame.bar:ClearAllPoints()
        frame.bar:SetPoint("TOP", 0, -4)
        frame.bar:SetSize(db.width, db.height)
    end
    local barInset = GetBarInset()
    frame.bar.phys:SetHeight(db.height - (barInset * 2))
    frame.bar.magic:SetHeight(db.height - (barInset * 2))
    frame.bar.separator:SetHeight(db.height - (barInset * 2))
end

local function UpdateMinimapButtonPosition()
    if not minimapButton then return end

    local angle = math.rad(db.minimap.angle or DEFAULTS.minimap.angle)
    local radius = 78
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function UpdateDisplay()
    if not frame.bar then return end

    local physicalDamage, magicalDamage = GetDamageTotals()
    local totalDamage = physicalDamage + magicalDamage
    local physicalRatio = 0.5
    local magicalRatio = 0.5
    local fillWidth = math.max(0, frame.bar:GetWidth() - (GetBarInset() * 2))

    frame:SetAlpha(UnitAffectingCombat("player") and IN_COMBAT_ALPHA or OUT_OF_COMBAT_ALPHA)

    if totalDamage > 0 then
        physicalRatio = physicalDamage / totalDamage
        magicalRatio = magicalDamage / totalDamage
    end

    frame.bar.phys:SetWidth(fillWidth * physicalRatio)
    frame.bar.magic:SetWidth(fillWidth * magicalRatio)
    frame.bar.magic:SetPoint("LEFT", frame.bar.phys, "RIGHT", 0, 0)
    frame.bar.separator:SetPoint("LEFT", frame.bar.phys, "RIGHT", 0, 0)
    frame:SetShown(db.shown)
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
    if not db or db.anchorMode == "FREE" or anchorRetryScheduled or anchorRetryAttempts >= 5 then return end

    anchorRetryAttempts = anchorRetryAttempts + 1
    anchorRetryScheduled = true
    C_Timer.After(1, function()
        anchorRetryScheduled = false
        if not db or db.anchorMode == "FREE" then return end
        RefreshLayout()
    end)
end

local function ReapplyPowerBarAnchor()
    if not db then return end
    if InCombatLockdown() and db.anchorMode ~= "FREE" then
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

local function SkinOptionsFrame()
    local E, _, _, _, _, _ = GetElvUI()
    if not E or not E.Skins or optionsFrame._isSkinned then return end

    local S = E.Skins

    if S.HandleFrame then
        pcall(S.HandleFrame, S, optionsFrame)
    end
    if S.HandleCheckBox then
        pcall(S.HandleCheckBox, S, optionsFrame.showCheck)
        pcall(S.HandleCheckBox, S, optionsFrame.matchPowerBarWidthCheck)
    end
    if S.HandleButton then
        pcall(S.HandleButton, S, optionsFrame.closeButton)
        pcall(S.HandleButton, S, optionsFrame.copyButton)
    end

    for _, slider in ipairs(optionsFrame.sliders or {}) do
        if S.HandleSliderFrame then
            pcall(S.HandleSliderFrame, S, slider)
        end
        if slider.input and S.HandleEditBox then
            pcall(S.HandleEditBox, S, slider.input)
        end
    end
    if S.HandleEditBox then
        pcall(S.HandleEditBox, S, optionsFrame.bcdmAnchorInput)
        pcall(S.HandleEditBox, S, optionsFrame.bcdmOffsetXInput)
        pcall(S.HandleEditBox, S, optionsFrame.bcdmOffsetYInput)
    end

    optionsFrame._isSkinned = true
end

local function UpdateOptionsControls()
    if not optionsFrame then return end

    optionsFrame.characterValue:SetText(currentCharacterKey or "-")
    optionsFrame.showCheck:SetChecked(db.shown)
    UIDropDownMenu_SetText(optionsFrame.barStyleDropdown, optionsFrame.barStyleLabels[db.barStyle])
    UIDropDownMenu_SetText(optionsFrame.anchorModeDropdown, optionsFrame.anchorModeLabels[db.anchorMode])
    UIDropDownMenu_SetText(optionsFrame.anchorPositionDropdown, optionsFrame.anchorPositionLabels[db.anchorPosition])
    UIDropDownMenu_SetText(optionsFrame.bcdmAnchorDropdown, GetBCDMAnchorLabel(db.anchorParent))
    optionsFrame.bcdmAnchorInput:SetText(db.anchorParent)
    optionsFrame.bcdmOffsetXInput:SetText(tostring(db.bcdmOffsetX))
    optionsFrame.bcdmOffsetYInput:SetText(tostring(db.bcdmOffsetY))
    optionsFrame.matchPowerBarWidthCheck:SetChecked(db.matchPowerBarWidth)
    SetSliderValue(optionsFrame.anchorSpacingSlider, db.anchorSpacing)
    SetSliderValue(optionsFrame.widthSlider, db.width)
    SetSliderValue(optionsFrame.heightSlider, db.height)
    SetSliderValue(optionsFrame.offsetXSlider, db.x)
    SetSliderValue(optionsFrame.offsetYSlider, db.y)
    SetSliderValue(optionsFrame.windowSlider, db.window)

    local bcdmActive = db.anchorMode ~= "FREE"
    for _, control in ipairs(optionsFrame.bcdmControls) do
        control:SetAlpha(bcdmActive and 1 or 0.45)
        if control.SetEnabled then
            control:SetEnabled(bcdmActive)
        end
    end
    if bcdmActive then
        UIDropDownMenu_EnableDropDown(optionsFrame.bcdmAnchorDropdown)
    else
        UIDropDownMenu_DisableDropDown(optionsFrame.bcdmAnchorDropdown)
    end

    local availableKeys = GetAvailableCharacterKeys()
    local hasProfiles = #availableKeys > 0

    if hasProfiles then
        if not optionsFrame.selectedCopyCharacterKey or not GetCharacterProfiles()[optionsFrame.selectedCopyCharacterKey] then
            optionsFrame.selectedCopyCharacterKey = availableKeys[1]
        end
        UIDropDownMenu_EnableDropDown(optionsFrame.copySourceDropdown)
        optionsFrame.copyButton:Enable()
        UIDropDownMenu_SetText(optionsFrame.copySourceDropdown, optionsFrame.selectedCopyCharacterKey)
    else
        optionsFrame.selectedCopyCharacterKey = nil
        UIDropDownMenu_DisableDropDown(optionsFrame.copySourceDropdown)
        optionsFrame.copyButton:Disable()
        UIDropDownMenu_SetText(optionsFrame.copySourceDropdown, L.NO_OTHER_CHARACTER)
    end
end

local function CreateOptionsFrame()
    optionsFrame = CreateFrame("Frame", "LafeeDamageTrackerOptionsFrame", UIParent, "BackdropTemplate")
    optionsFrame:SetSize(410, 790)
    optionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    optionsFrame:SetClampedToScreen(true)
    optionsFrame:SetMovable(true)
    optionsFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    optionsFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    optionsFrame:Hide()

    optionsFrame.title = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    optionsFrame.title:SetPoint("TOP", 0, -14)
    optionsFrame.title:SetText(L.ADDON_TITLE)

    optionsFrame.dragHandle = CreateFrame("Button", nil, optionsFrame)
    optionsFrame.dragHandle:SetPoint("TOPLEFT", 10, -8)
    optionsFrame.dragHandle:SetPoint("TOPRIGHT", -10, -8)
    optionsFrame.dragHandle:SetHeight(26)
    optionsFrame.dragHandle:RegisterForDrag("LeftButton")
    optionsFrame.dragHandle:SetScript("OnDragStart", function()
        optionsFrame:StartMoving()
    end)
    optionsFrame.dragHandle:SetScript("OnDragStop", function()
        optionsFrame:StopMovingOrSizing()
    end)

    optionsFrame.characterLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.characterLabel:SetPoint("TOPLEFT", 18, -42)
    optionsFrame.characterLabel:SetText(L.ACTIVE_CHARACTER)

    optionsFrame.characterValue = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    optionsFrame.characterValue:SetPoint("TOPLEFT", optionsFrame.characterLabel, "BOTTOMLEFT", 0, -4)
    optionsFrame.characterValue:SetJustifyH("LEFT")
    optionsFrame.characterValue:SetWidth(370)

    optionsFrame.showCheck = CreateFrame("CheckButton", nil, optionsFrame, "UICheckButtonTemplate")
    optionsFrame.showCheck:SetPoint("TOPLEFT", 18, -86)
    optionsFrame.showCheck.text = optionsFrame.showCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.showCheck.text:SetPoint("LEFT", optionsFrame.showCheck, "RIGHT", 4, 1)
    optionsFrame.showCheck.text:SetText(L.SHOW_BAR)
    optionsFrame.showCheck:SetScript("OnClick", function(self)
        db.shown = self:GetChecked() and true or false
        UpdateDisplay()
    end)

    optionsFrame.anchorModeLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.anchorModeLabel:SetPoint("TOPLEFT", 18, -120)
    optionsFrame.anchorModeLabel:SetText(L.ANCHOR_MODE)

    optionsFrame.anchorModeLabels = {
        FREE = L.FREE,
        ANCHORED = "Anchored",
        BETTER_COOLDOWN_MANAGER = "BetterCooldownManager",
        ELVUI = "ElvUI",
    }

    optionsFrame.barStyleLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.barStyleLabel:SetPoint("TOPLEFT", 260, -120)
    optionsFrame.barStyleLabel:SetText(L.STYLE)

    optionsFrame.barStyleLabels = {
        CLASSIC = L.CLASSIC,
        SQUARE = L.SQUARE,
    }
    optionsFrame.barStyleDropdown = CreateFrame("Frame", "LDTBarStyleDropdown", optionsFrame, "UIDropDownMenuTemplate")
    optionsFrame.barStyleDropdown:SetPoint("TOPLEFT", optionsFrame.barStyleLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(optionsFrame.barStyleDropdown, 120)
    UIDropDownMenu_Initialize(optionsFrame.barStyleDropdown, function(_, level)
        for _, style in ipairs({ "CLASSIC", "SQUARE" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.notCheckable = true
            info.text = GetDropdownItemText(optionsFrame.barStyleLabels[style], db.barStyle == style)
            info.func = function()
                db.barStyle = style
                ApplyBarStyle()
                ApplyFrameSize()
                UpdateDisplay()
                UpdateOptionsControls()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    optionsFrame.anchorModeDropdown = CreateFrame("Frame", "LDTAnchorModeDropdown", optionsFrame, "UIDropDownMenuTemplate")
    optionsFrame.anchorModeDropdown:SetPoint("TOPLEFT", optionsFrame.anchorModeLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(optionsFrame.anchorModeDropdown, 220)
    UIDropDownMenu_Initialize(optionsFrame.anchorModeDropdown, function(_, level)
        for _, mode in ipairs({ "FREE", "ANCHORED" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.notCheckable = true
            info.text = GetDropdownItemText(optionsFrame.anchorModeLabels[mode], db.anchorMode == mode)
            info.func = function()
                if db.anchorMode == mode then return end
                db.anchorMode = mode
                if mode == "BETTER_COOLDOWN_MANAGER" then
                    db.anchorParent = db.bcdmAnchor
                elseif mode == "ELVUI" then
                    db.anchorParent = "ElvUF_Player"
                end
                ReapplyPowerBarAnchor()
                UpdateOptionsControls()
                print("|cffffd100" .. L.ADDON_TITLE .. "|r : " .. L.INTEGRATION_CHANGED)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    optionsFrame.anchorPositionLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.anchorPositionLabel:SetPoint("TOPLEFT", optionsFrame.anchorModeDropdown, "BOTTOMLEFT", 16, -6)
    optionsFrame.anchorPositionLabel:SetText(L.POSITION)

    optionsFrame.anchorPositionLabels = {
        ABOVE = L.ABOVE,
        BELOW = L.BELOW,
    }
    optionsFrame.anchorPositionDropdown = CreateFrame("Frame", "LDTAnchorPositionDropdown", optionsFrame, "UIDropDownMenuTemplate")
    optionsFrame.anchorPositionDropdown:SetPoint("TOPLEFT", optionsFrame.anchorPositionLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(optionsFrame.anchorPositionDropdown, 180)
    UIDropDownMenu_Initialize(optionsFrame.anchorPositionDropdown, function(_, level)
        for _, position in ipairs({ "ABOVE", "BELOW" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.notCheckable = true
            info.text = GetDropdownItemText(optionsFrame.anchorPositionLabels[position], db.anchorPosition == position)
            info.func = function()
                db.anchorPosition = position
                if position == "BELOW" then
                    db.anchorFrom, db.anchorTo = "TOP", "BOTTOM"
                else
                    db.anchorFrom, db.anchorTo = "BOTTOM", "TOP"
                end
                ReapplyPowerBarAnchor()
                UpdateOptionsControls()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    optionsFrame.bcdmAnchorLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.bcdmAnchorLabel:SetPoint("TOPLEFT", 18, -230)
    optionsFrame.bcdmAnchorLabel:SetText(L.BCDM_ANCHOR)

    optionsFrame.bcdmAnchorDropdown = CreateFrame("Frame", "LDTBCDAnchorDropdown", optionsFrame, "UIDropDownMenuTemplate")
    optionsFrame.bcdmAnchorDropdown:SetPoint("TOPLEFT", optionsFrame.bcdmAnchorLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(optionsFrame.bcdmAnchorDropdown, 200)
    UIDropDownMenu_Initialize(optionsFrame.bcdmAnchorDropdown, function(_, level)
        for _, anchor in ipairs(BCDM_ANCHORS) do
            local info = UIDropDownMenu_CreateInfo()
            info.notCheckable = true
            info.text = GetDropdownItemText(anchor.label, db.anchorParent == anchor.name)
            info.func = function()
                db.bcdmAnchor = anchor.name
                db.anchorParent = anchor.name
                ReapplyPowerBarAnchor()
                UpdateOptionsControls()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    optionsFrame.bcdmAnchorInputLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.bcdmAnchorInputLabel:SetPoint("TOPLEFT", 260, -230)
    optionsFrame.bcdmAnchorInputLabel:SetText(L.MANUAL_FRAME)

    optionsFrame.bcdmAnchorInput = CreateFrame("EditBox", "LDTBCDAnchorInput", optionsFrame, "InputBoxTemplate")
    optionsFrame.bcdmAnchorInput:SetAutoFocus(false)
    optionsFrame.bcdmAnchorInput:SetMaxLetters(80)
    optionsFrame.bcdmAnchorInput:SetSize(112, 20)
    optionsFrame.bcdmAnchorInput:SetPoint("TOPLEFT", optionsFrame.bcdmAnchorInputLabel, "BOTTOMLEFT", 0, -4)
    local function SaveBCDMAnchorName(self)
        local anchorName = (self:GetText() or ""):match("^%s*(.-)%s*$")
        if anchorName == "" then
            anchorName = DEFAULTS.bcdmAnchor
        end
        local changed = db.anchorParent ~= anchorName
        db.bcdmAnchor = anchorName
        db.anchorParent = anchorName
        self:SetText(anchorName)
        if changed then
            ReapplyPowerBarAnchor()
            UpdateOptionsControls()
        end
    end
    optionsFrame.bcdmAnchorInput:SetScript("OnEnterPressed", function(self)
        SaveBCDMAnchorName(self)
        self:ClearFocus()
    end)
    optionsFrame.bcdmAnchorInput:SetScript("OnEscapePressed", function(self)
        self:SetText(db.anchorParent)
        self:ClearFocus()
    end)
    optionsFrame.bcdmAnchorInput:SetScript("OnEditFocusLost", SaveBCDMAnchorName)

    local function CreateBCDMOffsetInput(name, label, x, key)
        local labelFrame = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        labelFrame:SetPoint("TOPLEFT", x, -294)
        labelFrame:SetText(label)

        local input = CreateFrame("EditBox", name, optionsFrame, "InputBoxTemplate")
        input:SetAutoFocus(false)
        input:SetNumeric(false)
        input:SetMaxLetters(5)
        input:SetJustifyH("CENTER")
        input:SetSize(48, 20)
        input:SetPoint("LEFT", labelFrame, "RIGHT", 4, 0)

        local function SaveValue()
            local value = Clamp(tonumber(input:GetText()) or db[key], MIN_BCDM_OFFSET, MAX_BCDM_OFFSET)
            db[key] = math.floor(value + 0.5)
            input:SetText(tostring(db[key]))
            ReapplyPowerBarAnchor()
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

    optionsFrame.bcdmOffsetXInput = CreateBCDMOffsetInput("LDTBCDOffsetXInput", L.OFFSET_X, 18, "bcdmOffsetX")
    optionsFrame.bcdmOffsetYInput = CreateBCDMOffsetInput("LDTBCDOffsetYInput", L.OFFSET_Y, 190, "bcdmOffsetY")
    optionsFrame.bcdmControls = {
        optionsFrame.bcdmAnchorLabel,
        optionsFrame.bcdmAnchorDropdown,
        optionsFrame.bcdmAnchorInputLabel,
        optionsFrame.bcdmAnchorInput,
        optionsFrame.bcdmOffsetXInput.label,
        optionsFrame.bcdmOffsetXInput,
        optionsFrame.bcdmOffsetYInput.label,
        optionsFrame.bcdmOffsetYInput,
    }

    optionsFrame.anchorSpacingSlider = CreateSlider(optionsFrame, "LDTAnchorSpacingSlider", L.SPACING_PX, MIN_ANCHOR_SPACING, MAX_ANCHOR_SPACING, 1, 220)
    optionsFrame.anchorSpacingSlider:SetPoint("TOPLEFT", 32, -340)
    optionsFrame.anchorSpacingSlider:SetScript("OnValueChanged", function(self, value)
        if self._internalUpdate then return end
        db.anchorSpacing = math.floor(value + 0.5)
        ReapplyPowerBarAnchor()
        self.input:SetText(tostring(db.anchorSpacing))
    end)

    optionsFrame.matchPowerBarWidthCheck = CreateFrame("CheckButton", nil, optionsFrame, "UICheckButtonTemplate")
    optionsFrame.matchPowerBarWidthCheck:SetPoint("TOPLEFT", 18, -380)
    optionsFrame.matchPowerBarWidthCheck.text = optionsFrame.matchPowerBarWidthCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.matchPowerBarWidthCheck.text:SetPoint("LEFT", optionsFrame.matchPowerBarWidthCheck, "RIGHT", 4, 1)
    optionsFrame.matchPowerBarWidthCheck.text:SetText(L.MATCH_BAR_WIDTH)
    optionsFrame.matchPowerBarWidthCheck:SetScript("OnClick", function(self)
        db.matchPowerBarWidth = self:GetChecked() and true or false
        ReapplyPowerBarAnchor()
    end)

    optionsFrame.widthSlider = CreateSlider(optionsFrame, "LDTWidthSlider", L.WIDTH, MIN_WIDTH, MAX_WIDTH, 10, 220)
    optionsFrame.widthSlider:SetPoint("TOPLEFT", 32, -420)
    optionsFrame.widthSlider:SetScript("OnValueChanged", function(self, value)
        if self._internalUpdate then return end
        db.width = math.floor(value + 0.5)
        RefreshLayout()
        self.input:SetText(tostring(db.width))
    end)

    optionsFrame.heightSlider = CreateSlider(optionsFrame, "LDTHeightSlider", L.HEIGHT, MIN_HEIGHT, MAX_HEIGHT, 1, 220)
    optionsFrame.heightSlider:SetPoint("TOP", optionsFrame.widthSlider, "BOTTOM", 0, -34)
    optionsFrame.heightSlider:SetScript("OnValueChanged", function(self, value)
        if self._internalUpdate then return end
        db.height = math.floor(value + 0.5)
        RefreshLayout()
        self.input:SetText(tostring(db.height))
    end)

    optionsFrame.offsetXSlider = CreateSlider(optionsFrame, "LDTOffsetXSlider", L.OFFSET_X, -600, 600, 5, 220)
    optionsFrame.offsetXSlider:SetPoint("TOP", optionsFrame.heightSlider, "BOTTOM", 0, -34)
    optionsFrame.offsetXSlider:SetScript("OnValueChanged", function(self, value)
        if self._internalUpdate then return end
        db.x = math.floor(value + 0.5)
        ApplyFramePosition()
        self.input:SetText(tostring(db.x))
    end)

    optionsFrame.offsetYSlider = CreateSlider(optionsFrame, "LDTOffsetYSlider", L.OFFSET_Y, -400, 400, 5, 220)
    optionsFrame.offsetYSlider:SetPoint("TOP", optionsFrame.offsetXSlider, "BOTTOM", 0, -34)
    optionsFrame.offsetYSlider:SetScript("OnValueChanged", function(self, value)
        if self._internalUpdate then return end
        db.y = math.floor(value + 0.5)
        ApplyFramePosition()
        self.input:SetText(tostring(db.y))
    end)

    optionsFrame.windowSlider = CreateSlider(optionsFrame, "LDTWindowSlider", L.WINDOW_SECONDS, MIN_WINDOW, MAX_WINDOW, 1, 220)
    optionsFrame.windowSlider:SetPoint("TOP", optionsFrame.offsetYSlider, "BOTTOM", 0, -34)
    optionsFrame.windowSlider:SetScript("OnValueChanged", function(self, value)
        if self._internalUpdate then return end
        db.window = Clamp(math.floor(value + 0.5), MIN_WINDOW, MAX_WINDOW)
        UpdateDisplay()
        self.input:SetText(tostring(db.window))
    end)

    optionsFrame.copyLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.copyLabel:SetPoint("TOPLEFT", optionsFrame.windowSlider, "BOTTOMLEFT", -14, -32)
    optionsFrame.copyLabel:SetText(L.COPY_FROM)

    optionsFrame.copySourceDropdown = CreateFrame("Frame", "LDTCopyProfileDropdown", optionsFrame, "UIDropDownMenuTemplate")
    optionsFrame.copySourceDropdown:SetPoint("TOPLEFT", optionsFrame.copyLabel, "BOTTOMLEFT", -16, -6)

    UIDropDownMenu_SetWidth(optionsFrame.copySourceDropdown, 210)
    UIDropDownMenu_Initialize(optionsFrame.copySourceDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()

        for _, characterKey in ipairs(GetAvailableCharacterKeys()) do
            info.notCheckable = true
            info.text = GetDropdownItemText(characterKey, optionsFrame.selectedCopyCharacterKey == characterKey)
            info.func = function()
                optionsFrame.selectedCopyCharacterKey = characterKey
                UIDropDownMenu_SetText(optionsFrame.copySourceDropdown, characterKey)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    optionsFrame.copyButton = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
    optionsFrame.copyButton:SetSize(110, 22)
    optionsFrame.copyButton:SetPoint("TOPLEFT", optionsFrame.copySourceDropdown, "BOTTOMLEFT", 20, -8)
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
        ReapplyPowerBarAnchor()
        UpdateMinimapButtonPosition()
        if minimapButton then
            minimapButton:SetShown(not db.minimap.hide)
        end
        UpdateOptionsControls()
        print("|cff00ff98" .. L.ADDON_TITLE .. "|r : " .. string.format(L.COPIED_FROM, sourceKey))
    end)

    optionsFrame.sliders = {
        optionsFrame.anchorSpacingSlider,
        optionsFrame.widthSlider,
        optionsFrame.heightSlider,
        optionsFrame.offsetXSlider,
        optionsFrame.offsetYSlider,
        optionsFrame.windowSlider,
    }

    optionsFrame.closeButton = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
    optionsFrame.closeButton:SetSize(80, 22)
    optionsFrame.closeButton:SetPoint("BOTTOM", 0, 18)
    optionsFrame.closeButton:SetFrameStrata("DIALOG")
    optionsFrame.closeButton:SetFrameLevel(optionsFrame:GetFrameLevel() + 10)
    optionsFrame.closeButton:SetText(L.CLOSE)
    optionsFrame.closeButton:SetScript("OnClick", function()
        if GetCurrentKeyBoardFocus() then
            GetCurrentKeyBoardFocus():ClearFocus()
        end
        optionsFrame:Hide()
    end)

    SkinOptionsFrame()
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
    minimapButton = CreateFrame("Button", "LafeeDamageTrackerMinimapButton", Minimap)
    minimapButton:SetSize(32, 32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    minimapButton:SetMovable(true)
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")

    minimapButton.background = minimapButton:CreateTexture(nil, "BACKGROUND")
    minimapButton.background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    minimapButton.background:SetSize(24, 24)
    minimapButton.background:SetPoint("CENTER")

    minimapButton.icon = minimapButton:CreateTexture(nil, "ARTWORK", nil, 1)
    minimapButton.icon:SetTexture("Interface\\Icons\\INV_Shield_06")
    minimapButton.icon:SetSize(22, 22)
    minimapButton.icon:SetPoint("CENTER")
    minimapButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    minimapButton.border = minimapButton:CreateTexture(nil, "OVERLAY")
    minimapButton.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    minimapButton.border:SetSize(54, 54)
    minimapButton.border:SetPoint("TOPLEFT", -11, 11)

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
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    frame:SetBackdropColor(0, 0, 0, 0)

    frame:SetScript("OnDragStart", function(self)
        if db.anchorMode == "FREE" then
            self:StartMoving()
        end
    end)

    frame:SetScript("OnDragStop", function(self)
        if db.anchorMode ~= "FREE" then return end
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

    frame.bar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.bar:SetPoint("TOP", 0, -4)

    frame.bar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame.bar:SetBackdropColor(0.08, 0.08, 0.08, 0.35)
    frame.bar:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)

    frame.bar.phys = frame.bar:CreateTexture(nil, "ARTWORK")
    frame.bar.phys:SetPoint("LEFT", BAR_INSET, 0)
    frame.bar.phys:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.bar.phys:SetColorTexture(0.82, 0.82, 0.82, 0.95)

    frame.bar.magic = frame.bar:CreateTexture(nil, "ARTWORK")
    frame.bar.magic:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.bar.magic:SetColorTexture(0.55, 0.20, 0.85, 0.95)

    frame.bar.separator = frame.bar:CreateTexture(nil, "OVERLAY")
    frame.bar.separator:SetWidth(1)
    frame.bar.separator:SetColorTexture(1, 1, 1, 0.9)

    RefreshLayout()
    CreateMinimapButton()
end

local function OnUnitCombat(unitTarget, action, _, amount, schoolMask)
    if unitTarget ~= "player" then return end
    if action ~= "WOUND" then return end

    AddDamageTaken(amount, schoolMask)
    UpdateDisplay()
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= addonName then
            if db and (loadedAddon == "BetterCooldownManager" or loadedAddon == "ElvUI") then
                ReapplyPowerBarAnchor()
            end
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
    elseif event == "PLAYER_ENTERING_WORLD" then
        ResetDamageTotals()
        ReapplyPowerBarAnchor()
        UpdateDisplay()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit == "player" then
            ReapplyPowerBarAnchor()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        UpdateDisplay()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ResetDamageTotals()
        if pendingAnchorUpdate then
            ReapplyPowerBarAnchor()
        end
        UpdateDisplay()
    elseif event == "UNIT_COMBAT" then
        OnUnitCombat(...)
    end
end)

frame:SetScript("OnUpdate", function(_, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate >= 0.1 then
        elapsedSinceUpdate = 0
        if db and db.shown then
            UpdateDisplay()
        end
    end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("UNIT_COMBAT")

-- Public integration API. Consumers such as BetterCooldownManager should use
-- this table instead of reading LafeeDamageTrackerDB or calling local UI
-- helpers directly. API methods intentionally validate through the same
-- profile normalization path as the native LDT options window.
local API = _G.LafeeDamageTrackerAPI or {}
_G.LafeeDamageTrackerAPI = API
API.version = 1

local PUBLIC_OPTIONS = {
    point = true, relativePoint = true, x = true, y = true,
    width = true, height = true, shown = true, window = true,
    anchorMode = true, anchorPosition = true, anchorSpacing = true,
    anchorFrom = true, anchorParent = true, anchorTo = true,
    matchPowerBarWidth = true, bcdmAnchor = true,
    bcdmOffsetX = true, bcdmOffsetY = true, barStyle = true,
}

local function RefreshAfterPublicOptionChange(option)
    RefreshActiveProfile()
    if option == "minimap.hide" then
        if minimapButton then minimapButton:SetShown(not db.minimap.hide) end
    elseif option == "minimap.angle" then
        UpdateMinimapButtonPosition()
    else
        ReapplyPowerBarAnchor()
        UpdateDisplay()
    end
    if optionsFrame and optionsFrame:IsShown() then UpdateOptionsControls() end
end

function API:IsReady()
    return db ~= nil and rootDB ~= nil
end

function API:GetOption(option)
    if not db then return nil end
    if option == "minimap.hide" then return db.minimap.hide end
    if option == "minimap.angle" then return db.minimap.angle end
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
        db.bcdmAnchor = value
    elseif option == "anchorMode" then
        if value ~= "FREE" and value ~= "ANCHORED"
            and value ~= "BETTER_COOLDOWN_MANAGER" and value ~= "ELVUI" then
            return false, "invalid-value"
        end
        db.anchorMode = value
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
    ReapplyPowerBarAnchor()
    UpdateMinimapButtonPosition()
    if minimapButton then minimapButton:SetShown(not db.minimap.hide) end
    if optionsFrame and optionsFrame:IsShown() then UpdateOptionsControls() end
    return true
end

function API:GetBCDMAnchors()
    local anchors = {}
    for _, anchor in ipairs(BCDM_ANCHORS) do
        anchors[#anchors + 1] = { name = anchor.name, label = anchor.label }
    end
    return anchors
end

function API:GetAnchorPoints()
    local points = {}
    for _, point in ipairs(ANCHOR_POINTS) do
        points[#points + 1] = { name = point, label = point }
    end
    return points
end

function API:GetAnchorParents()
    local parents = {}
    for _, anchor in ipairs(ANCHOR_PARENTS) do
        if anchor.name ~= "ElvUF_Player" and anchor.name ~= "ElvUF_Target"
            or C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ElvUI") then
            parents[#parents + 1] = { name = anchor.name, label = anchor.label }
        end
    end
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
    return frame
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
