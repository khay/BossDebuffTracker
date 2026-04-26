-- BossDebuffTracker.lua
-- Tracks debuffs on boss1–boss5, displayed next to each boss frame.

local ADDON_NAME   = "BossDebuffTracker"
local MAX_BOSSES   = 5
local MAX_DEBUFFS  = 10   -- hard cap on icon pool; db.maxDebuffs controls display
local ICON_SPACING = 2
local UPDATE_INTERVAL = 0.1

-- Saved variable defaults
local DEFAULTS = {
    enabled    = true,
    iconSize   = 28,
    showTimer  = true,
    showStacks = true,
    testMode   = false,
    onlyMine   = false,   -- true = only show debuffs cast by the player
    maxDebuffs = 5,       -- how many icons to show per boss (1–10)
    anchor     = "RIGHT", -- which side of the boss frame: RIGHT, LEFT, TOP, BOTTOM
    offsetX    = 4,       -- horizontal fine-tune offset
    offsetY    = 0,       -- vertical fine-tune offset
    filter     = {},      -- optional spell-ID whitelist
}

-- Maps anchor name → which point on the container + which point on the boss frame
local ANCHOR_MAP = {
    RIGHT  = { containerPoint = "LEFT",   bossPoint = "RIGHT"  },
    LEFT   = { containerPoint = "RIGHT",  bossPoint = "LEFT"   },
    TOP    = { containerPoint = "BOTTOM", bossPoint = "TOP"    },
    BOTTOM = { containerPoint = "TOP",    bossPoint = "BOTTOM" },
}

BossDebuffTrackerDB = BossDebuffTrackerDB or {}

local function ApplyDefaults(db, defaults)
    for k, v in pairs(defaults) do
        if db[k] == nil then
            if type(v) == "table" then
                db[k] = {}
                ApplyDefaults(db[k], v)
            else
                db[k] = v
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Forward declarations
-------------------------------------------------------------------------------
local BossFrames = {}
local UpdateAll
local ApplyIconSize
local ApplyTimers
local ApplyAllOffsets
local OpenSettings

-------------------------------------------------------------------------------
-- Debuff icon factory
-------------------------------------------------------------------------------
local function CreateDebuffIcon(parent)
    local db = BossDebuffTrackerDB
    local sz = db.iconSize

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(sz, sz)

    f.icon = f:CreateTexture(nil, "BACKGROUND")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown:SetAllPoints()
    f.cooldown:SetDrawEdge(false)
    f.cooldown:SetHideCountdownNumbers(not db.showTimer)

    f.stacks = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    f.stacks:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, 1)

    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetAllPoints()
    f.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
    f.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    f.border:Hide()

    f:SetScript("OnEnter", function(self)
        if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Click to open Boss Debuff Tracker settings", 1, 1, 1)
            GameTooltip:Show()
        elseif self.unit and self.index then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local aura = C_UnitAuras.GetAuraDataByIndex(self.unit, self.index, "HARMFUL")
            if aura then
                GameTooltip:SetSpellByID(aura.spellId)
            end
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and EditModeManagerFrame and EditModeManagerFrame:IsShown() then
            OpenSettings()
        end
    end)

    f:Hide()
    return f
end

-------------------------------------------------------------------------------
-- Per-boss container
-- Anchored to the configured side of the boss frame; icons flow left-to-right.
-------------------------------------------------------------------------------
local function CreateBossTracker(bossIndex)
    local db = BossDebuffTrackerDB
    local sz = db.iconSize

    local container = CreateFrame("Frame", ADDON_NAME .. "Boss" .. bossIndex, UIParent)
    container:SetHeight(sz + 4)
    container:SetWidth((sz + ICON_SPACING) * MAX_DEBUFFS)

    local bossFrame = _G["Boss" .. bossIndex .. "TargetFrame"]
    local anchorInfo = ANCHOR_MAP[db.anchor] or ANCHOR_MAP["RIGHT"]
    if bossFrame then
        container:SetPoint(anchorInfo.containerPoint, bossFrame, anchorInfo.bossPoint,
            db.offsetX, db.offsetY)
    else
        container:SetPoint("CENTER", UIParent, "CENTER", 200, 150 - (bossIndex * 36))
    end

    container:Show()

    local icons = {}
    for i = 1, MAX_DEBUFFS do
        local icon = CreateDebuffIcon(container)
        icon:SetPoint("LEFT", container, "LEFT", (i - 1) * (sz + ICON_SPACING), 0)
        icons[i] = icon
    end

    -- ── Edit Mode handle ──────────────────────────────────────────────────────
    -- Visible only in Edit Mode; click opens the settings panel.
    local handle = CreateFrame("Button", nil, container, "BackdropTemplate")
    handle:SetSize(180, 28)
    handle:SetPoint("LEFT", container, "LEFT", 0, 0)
    handle:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    handle:SetBackdropColor(0.05, 0.05, 0.20, 0.92)
    handle:SetBackdropBorderColor(0.30, 0.55, 1.00, 1.00)

    local handleLabel = handle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    handleLabel:SetAllPoints()
    handleLabel:SetText("Boss Debuff Tracker")
    handleLabel:SetJustifyH("CENTER")

    handle:SetScript("OnClick", OpenSettings)
    handle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Click to open Boss Debuff Tracker settings", 1, 1, 1)
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    handle:Hide()

    return {
        frame  = container,
        icons  = icons,
        unit   = "boss" .. bossIndex,
        index  = bossIndex,
        handle = handle,
    }
end

-------------------------------------------------------------------------------
-- Debuff colours by type
-------------------------------------------------------------------------------
local debuffTypeColors = {
    Magic   = { r = 0.20, g = 0.60, b = 1.00 },
    Curse   = { r = 0.60, g = 0.00, b = 1.00 },
    Disease = { r = 0.60, g = 0.40, b = 0.00 },
    Poison  = { r = 0.00, g = 0.60, b = 0.00 },
}

local TEST_SPELLS = {
    { icon = 136200, dur = 30, stacks = 0, debuffType = "Magic",   mine = true  },
    { icon = 136201, dur = 15, stacks = 3, debuffType = "Poison",  mine = false },
    { icon = 136202, dur = 60, stacks = 0, debuffType = "Curse",   mine = true  },
    { icon = 136203, dur = 10, stacks = 5, debuffType = "Disease", mine = false },
    { icon = 136204, dur = 45, stacks = 2, debuffType = "Magic",   mine = true  },
}

local function UpdateBossDebuffs(tracker)
    local db        = BossDebuffTrackerDB
    local unit      = tracker.unit
    local icons     = tracker.icons
    local filter    = db.filter
    local hasFilter = next(filter) ~= nil
    local limit     = math.min(db.maxDebuffs, MAX_DEBUFFS)
    local shown     = 0

    -- Hide everything if the boss frame itself isn't visible (e.g. outside an
    -- encounter and not in Edit Mode). Prevents test icons floating on screen.
    local bossFrame = _G["Boss" .. tracker.index .. "TargetFrame"]
    if bossFrame and not bossFrame:IsShown() then
        for i = 1, MAX_DEBUFFS do icons[i]:Hide() end
        return
    end

    -- ── TEST MODE ────────────────────────────────────────────────────────────
    if db.testMode and not playerInCombat then
        for i, spell in ipairs(TEST_SPELLS) do
            if shown >= limit then break end
            if not db.onlyMine or spell.mine then
                shown = shown + 1
                local slot = icons[shown]
                slot.icon:SetTexture(spell.icon)
                slot.unit  = nil
                slot.index = nil
                slot.cooldown:SetCooldown(GetTime(), spell.dur)
                if db.showTimer then slot.cooldown:Show() else slot.cooldown:Hide() end
                if spell.stacks > 0 and db.showStacks then
                    slot.stacks:SetText(spell.stacks)
                    slot.stacks:Show()
                else
                    slot.stacks:Hide()
                end
                local c = debuffTypeColors[spell.debuffType]
                if c then slot.border:SetVertexColor(c.r, c.g, c.b); slot.border:Show()
                else slot.border:Hide() end
                slot:Show()
            end
        end
        for j = shown + 1, MAX_DEBUFFS do icons[j]:Hide() end
        return
    end

    -- ── LIVE MODE ────────────────────────────────────────────────────────────
    if not UnitExists(unit) then
        for i = 1, MAX_DEBUFFS do icons[i]:Hide() end
        return
    end

    local i = 1
    while shown < limit do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL")
        if not aura then break end

        -- onlyMine filter: caster must be the player
        local passOwner = not db.onlyMine or (aura.sourceUnit == "player")
        -- optional spell whitelist
        local passFilter = not hasFilter or filter[aura.spellId]

        if passOwner and passFilter then
            shown = shown + 1
            local slot = icons[shown]
            slot.icon:SetTexture(aura.icon)
            slot.unit  = unit
            slot.index = i

            if aura.duration and aura.duration > 0 then
                slot.cooldown:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
                if db.showTimer then slot.cooldown:Show() else slot.cooldown:Hide() end
            else
                slot.cooldown:Hide()
            end

            if aura.applications and aura.applications > 1 and db.showStacks then
                slot.stacks:SetText(aura.applications)
                slot.stacks:Show()
            else
                slot.stacks:Hide()
            end

            local c = debuffTypeColors[aura.dispelName]
            if c then slot.border:SetVertexColor(c.r, c.g, c.b); slot.border:Show()
            else slot.border:Hide() end

            slot:Show()
        end
        i = i + 1
    end

    for j = shown + 1, MAX_DEBUFFS do icons[j]:Hide() end
end

-------------------------------------------------------------------------------
-- Apply helpers (called when settings change at runtime)
-------------------------------------------------------------------------------
ApplyIconSize = function()
    local db = BossDebuffTrackerDB
    local sz = db.iconSize
    for bi = 1, MAX_BOSSES do
        local t = BossFrames[bi]
        if t then
            t.frame:SetHeight(sz + 4)
            t.frame:SetWidth((sz + ICON_SPACING) * MAX_DEBUFFS)
            for j = 1, MAX_DEBUFFS do
                t.icons[j]:SetSize(sz, sz)
                t.icons[j]:SetPoint("LEFT", t.frame, "LEFT",
                    (j - 1) * (sz + ICON_SPACING), 0)
            end
        end
    end
end

ApplyTimers = function()
    local db = BossDebuffTrackerDB
    for bi = 1, MAX_BOSSES do
        local t = BossFrames[bi]
        if t then
            for j = 1, MAX_DEBUFFS do
                t.icons[j].cooldown:SetHideCountdownNumbers(not db.showTimer)
            end
        end
    end
end

-- Re-anchor ALL boss containers using the current anchor side + offsets
ApplyAllOffsets = function()
    local db = BossDebuffTrackerDB
    local anchorInfo = ANCHOR_MAP[db.anchor] or ANCHOR_MAP["RIGHT"]
    for bi = 1, MAX_BOSSES do
        local t = BossFrames[bi]
        if t then
            local bossFrame = _G["Boss" .. bi .. "TargetFrame"]
            t.frame:ClearAllPoints()
            if bossFrame then
                t.frame:SetPoint(anchorInfo.containerPoint, bossFrame,
                    anchorInfo.bossPoint, db.offsetX, db.offsetY)
            else
                t.frame:SetPoint("CENTER", UIParent, "CENTER", 200, 150 - (bi * 36))
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Init & UpdateAll
-------------------------------------------------------------------------------
local function InitTrackers()
    for i = 1, MAX_BOSSES do
        if not BossFrames[i] then
            BossFrames[i] = CreateBossTracker(i)
        end
    end
end

UpdateAll = function()
    if not BossDebuffTrackerDB.enabled then return end
    for i = 1, MAX_BOSSES do
        if BossFrames[i] then UpdateBossDebuffs(BossFrames[i]) end
    end
end

-- Shows or hides the Edit Mode click handles on every tracker
local function SetEditModeHandles(show)
    for i = 1, MAX_BOSSES do
        if BossFrames[i] and BossFrames[i].handle then
            if show then BossFrames[i].handle:Show()
            else          BossFrames[i].handle:Hide() end
        end
    end
end

local function DisableTestMode()
    local db = BossDebuffTrackerDB
    if not db.testMode then return end
    db.testMode = false
    for i = 1, MAX_BOSSES do
        if BossFrames[i] then
            for j = 1, MAX_DEBUFFS do BossFrames[i].icons[j]:Hide() end
        end
    end
    if testModeBtn then testModeBtn.Refresh() end
    UpdateAll()
end

-------------------------------------------------------------------------------
-- Throttled ticker
-------------------------------------------------------------------------------
local ticker        = 0
local playerInCombat = false   -- set by PLAYER_REGEN_DISABLED/ENABLED events
local eventFrame = CreateFrame("Frame", ADDON_NAME .. "EventFrame", UIParent)
eventFrame:SetScript("OnUpdate", function(self, elapsed)
    ticker = ticker + elapsed
    if ticker >= UPDATE_INTERVAL then ticker = 0; UpdateAll() end
end)

-------------------------------------------------------------------------------
-- Settings Panel  (floating, draggable — opened by /bdt and the Addons page)
-------------------------------------------------------------------------------
local SettingsPanel
local testModeBtn  -- forward ref; kept in sync by /bdt test slash command

local function MakeLabel(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    fs:SetText(text)
    return fs
end

local function MakeSectionLabel(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    fs:SetText(text)
    return fs
end

local function MakeSeparator(parent, x, y, width)
    local sep = parent:CreateTexture(nil, "BACKGROUND")
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    sep:SetSize(width, 1)
    sep:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
end

local function MakeCheckbox(parent, label, x, y, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    cb.text:SetText(label)
    cb:SetChecked(getter())
    cb:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
    return cb
end

-- Toggle button: displays labelOn when active, labelOff when inactive
local function MakeToggleButton(parent, labelOn, labelOff, x, y, width, getter, setter)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, 26)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    local function Refresh()
        btn:SetText(getter() and labelOn or labelOff)
    end
    Refresh()
    btn:SetScript("OnClick", function()
        setter(not getter())
        Refresh()
    end)
    btn.Refresh = Refresh
    return btn
end

local function MakeSlider(parent, label, minVal, maxVal, step, x, y, width, getter, setter, fmt)
    fmt = fmt or "%d"

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    title:SetText(label)

    local sl = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sl:SetWidth(width)
    sl:SetMinMaxValues(minVal, maxVal)
    sl:SetValueStep(step)
    sl:SetObeyStepOnDrag(true)
    sl:SetValue(getter())
    sl.Low:SetText(string.format(fmt, minVal))
    sl.High:SetText(string.format(fmt, maxVal))

    local valText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valText:SetPoint("TOP", sl, "BOTTOM", 0, -2)
    valText:SetText(string.format(fmt, getter()))

    sl:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val / step + 0.5) * step
        valText:SetText(string.format(fmt, val))
        setter(val)
    end)

    -- Return a group so the caller can Enable/Disable the whole widget together
    local group = {}
    function group:Enable()
        sl:Enable()
        title:SetAlpha(1); valText:SetAlpha(1)
        sl.Low:SetAlpha(1); sl.High:SetAlpha(1)
    end
    function group:Disable()
        sl:Disable()
        title:SetAlpha(0.4); valText:SetAlpha(0.4)
        sl.Low:SetAlpha(0.4); sl.High:SetAlpha(0.4)
    end
    return group
end

local dropdownSeq = 0  -- unique name counter for UIDropDownMenu frames
local function MakeDropdown(parent, label, x, y, width, options, getter, setter)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    title:SetText(label)

    dropdownSeq = dropdownSeq + 1
    local dd = CreateFrame("Frame", ADDON_NAME .. "DD" .. dropdownSeq, parent,
        "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -15, -2)
    UIDropDownMenu_SetWidth(dd, width)

    local function RefreshText()
        local cur = getter()
        for _, opt in ipairs(options) do
            if opt.value == cur then
                UIDropDownMenu_SetText(dd, opt.label)
                break
            end
        end
    end

    UIDropDownMenu_Initialize(dd, function(self, level)
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = opt.label
            info.value   = opt.value
            info.checked = (getter() == opt.value)
            info.func    = function(btn)
                UIDropDownMenu_SetSelectedValue(dd, btn.value)
                setter(btn.value)
                RefreshText()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    RefreshText()

    local group = {}
    function group:Enable()  UIDropDownMenu_EnableDropDown(dd);  title:SetAlpha(1)   end
    function group:Disable() UIDropDownMenu_DisableDropDown(dd); title:SetAlpha(0.4) end
    return group
end

local function BuildSettingsPanel()
    local db = BossDebuffTrackerDB

    local PANEL_W = 440
    local SLIDER_W = PANEL_W - 80

    local panel = CreateFrame("Frame", ADDON_NAME .. "Settings", UIParent,
        "BasicFrameTemplateWithInset")
    panel:SetWidth(PANEL_W)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop",  panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    panel:SetFrameStrata("DIALOG")
    panel.TitleText:SetText("Boss Debuff Tracker — Settings")
    panel:Hide()

    -- All controls that should be disabled when the addon is turned off
    local dependentControls = {}

    -- Syncs every dependent control's enabled state to db.enabled
    local function RefreshControlStates()
        for _, ctrl in ipairs(dependentControls) do
            if db.enabled then ctrl:Enable() else ctrl:Disable() end
        end
    end

    local cx, cy = 16, 44

    -- ════════════════════════════════════════════════════════════════
    -- GENERAL
    -- ════════════════════════════════════════════════════════════════
    MakeSectionLabel(panel, "General", cx, cy); cy = cy + 24

    MakeCheckbox(panel, "Enable Boss Debuff Tracker", cx, cy,
        function() return db.enabled end,
        function(v)
            db.enabled = v
            if not v then
                for i = 1, MAX_BOSSES do
                    if BossFrames[i] then
                        for j = 1, MAX_DEBUFFS do BossFrames[i].icons[j]:Hide() end
                    end
                end
            end
            RefreshControlStates()
        end); cy = cy + 30

    testModeBtn = MakeToggleButton(panel,
        "Disable Test Debuffs", "Enable Test Debuffs",
        cx, cy, 180,
        function() return db.testMode end,
        function(v)
            db.testMode = v
            if not v then
                for i = 1, MAX_BOSSES do
                    if BossFrames[i] then
                        for j = 1, MAX_DEBUFFS do BossFrames[i].icons[j]:Hide() end
                    end
                end
            end
            UpdateAll()
        end)
    table.insert(dependentControls, testModeBtn); cy = cy + 36

    -- ════════════════════════════════════════════════════════════════
    -- DEBUFF FILTER
    -- ════════════════════════════════════════════════════════════════
    MakeSeparator(panel, cx, cy, PANEL_W - 32); cy = cy + 10
    MakeSectionLabel(panel, "Debuff Filter", cx, cy); cy = cy + 24

    table.insert(dependentControls,
        MakeCheckbox(panel, "Show only MY debuffs  (debuffs cast by you)", cx, cy,
            function() return db.onlyMine end,
            function(v) db.onlyMine = v; UpdateAll() end)); cy = cy + 30

    -- Max debuffs shown slider  (1–10)
    table.insert(dependentControls,
        MakeSlider(panel, "Max debuffs shown per boss", 1, 10, 1,
            cx, cy, SLIDER_W,
            function() return db.maxDebuffs end,
            function(v) db.maxDebuffs = v; UpdateAll() end)); cy = cy + 62

    -- ════════════════════════════════════════════════════════════════
    -- ICONS
    -- ════════════════════════════════════════════════════════════════
    MakeSeparator(panel, cx, cy, PANEL_W - 32); cy = cy + 10
    MakeSectionLabel(panel, "Icons", cx, cy); cy = cy + 24

    table.insert(dependentControls,
        MakeCheckbox(panel, "Show cooldown timer", cx, cy,
            function() return db.showTimer end,
            function(v) db.showTimer = v; ApplyTimers(); UpdateAll() end)); cy = cy + 30

    table.insert(dependentControls,
        MakeCheckbox(panel, "Show stack count", cx, cy,
            function() return db.showStacks end,
            function(v) db.showStacks = v; UpdateAll() end)); cy = cy + 30

    -- Icon size slider (16–48 px, step 2)
    table.insert(dependentControls,
        MakeSlider(panel, "Icon size  (px)", 16, 48, 2,
            cx, cy, SLIDER_W,
            function() return db.iconSize end,
            function(v) db.iconSize = v; ApplyIconSize(); UpdateAll() end)); cy = cy + 62

    -- ════════════════════════════════════════════════════════════════
    -- POSITION  (single shared offset for all boss frames)
    -- ════════════════════════════════════════════════════════════════
    MakeSeparator(panel, cx, cy, PANEL_W - 32); cy = cy + 10
    MakeSectionLabel(panel, "Position  (all boss frames)", cx, cy); cy = cy + 24

    -- Anchor side dropdown
    table.insert(dependentControls,
        MakeDropdown(panel, "Debuff anchor side", cx, cy, 160,
            {
                { label = "Right of boss frame",  value = "RIGHT"  },
                { label = "Left of boss frame",   value = "LEFT"   },
                { label = "Above boss frame",     value = "TOP"    },
                { label = "Below boss frame",     value = "BOTTOM" },
            },
            function() return db.anchor end,
            function(v) db.anchor = v; ApplyAllOffsets() end
        )); cy = cy + 56

    -- Horizontal fine-tune
    table.insert(dependentControls,
        MakeSlider(panel, "Horizontal offset  (X)", -80, 80, 1,
            cx, cy, SLIDER_W,
            function() return db.offsetX end,
            function(v) db.offsetX = v; ApplyAllOffsets() end,
            "%d px")); cy = cy + 62

    -- Vertical fine-tune
    table.insert(dependentControls,
        MakeSlider(panel, "Vertical offset  (Y)  — positive = up", -60, 60, 1,
            cx, cy, SLIDER_W,
            function() return db.offsetY end,
            function(v) db.offsetY = v; ApplyAllOffsets() end,
            "%d px")); cy = cy + 62

    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    closeBtn:SetSize(90, 26)
    closeBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 10)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() panel:Hide() end)

    -- Sync control states whenever the panel is opened
    panel:SetScript("OnShow", RefreshControlStates)
    -- Auto-disable test mode when the settings panel is closed
    panel:SetScript("OnHide", DisableTestMode)

    panel:SetHeight(cy + 40)
    return panel
end

OpenSettings = function()
    if not SettingsPanel then
        SettingsPanel = BuildSettingsPanel()
    end
    if SettingsPanel:IsShown() then
        SettingsPanel:Hide()
    else
        SettingsPanel:Show()
    end
end

-- Registers a minimal stub in Interface > Options > Addons with a single
-- launch button; all real settings live in the floating panel above.
local function RegisterInterfaceOptions()
    local stub = CreateFrame("Frame", ADDON_NAME .. "StubPanel")
    stub.name = ADDON_NAME

    local btn = CreateFrame("Button", nil, stub, "UIPanelButtonTemplate")
    btn:SetSize(220, 26)
    btn:SetPoint("TOPLEFT", stub, "TOPLEFT", 16, -16)
    btn:SetText("Open Boss Debuff Tracker")
    btn:SetScript("OnClick", OpenSettings)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(stub, stub.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(stub)
    end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then
            ApplyDefaults(BossDebuffTrackerDB, DEFAULTS)
            RegisterInterfaceOptions()
            -- Show handles when Edit Mode opens; hide + disable test mode when it closes
            if EditModeManagerFrame then
                EditModeManagerFrame:HookScript("OnShow", function()
                    SetEditModeHandles(true)
                end)
                EditModeManagerFrame:HookScript("OnHide", function()
                    SetEditModeHandles(false)
                    DisableTestMode()
                end)
            end
            print("|cff00ccff[BossDebuffTracker]|r loaded. " ..
                  "Type |cffffd700/bdt|r to open addon settings.")
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        InitTrackers()
        UpdateAll()

    elseif event == "PLAYER_REGEN_DISABLED" then
        playerInCombat = true
        -- Immediately clear any visible test icons before live debuffs take over
        for i = 1, MAX_BOSSES do
            if BossFrames[i] then
                for j = 1, MAX_DEBUFFS do BossFrames[i].icons[j]:Hide() end
            end
        end
        UpdateAll()

    elseif event == "PLAYER_REGEN_ENABLED" then
        playerInCombat = false
        UpdateAll()

    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit and unit:find("^boss%d") then UpdateAll() end

    elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        UpdateAll()
    end
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
SLASH_BOSSDEBUFFTRACKER1 = "/bdt"
SlashCmdList["BOSSDEBUFFTRACKER"] = function(msg)
    msg = (msg or ""):lower():trim()

    if msg == "" or msg == "config" or msg == "settings" then
        OpenSettings()

    elseif msg == "enable" then
        BossDebuffTrackerDB.enabled = true
        print("|cff00ccff[BossDebuffTracker]|r Enabled.")

    elseif msg == "disable" then
        BossDebuffTrackerDB.enabled = false
        print("|cff00ccff[BossDebuffTracker]|r Disabled.")

    elseif msg == "test" then
        local db = BossDebuffTrackerDB
        db.testMode = not db.testMode
        if not db.testMode then
            for i = 1, MAX_BOSSES do
                if BossFrames[i] then
                    for j = 1, MAX_DEBUFFS do BossFrames[i].icons[j]:Hide() end
                end
            end
        end
        UpdateAll()
        if testModeBtn then testModeBtn.Refresh() end
        print("|cff00ccff[BossDebuffTracker]|r Test mode: " ..
            (db.testMode and "|cff00ff00ON|r" or "|cffff4444OFF|r"))

    elseif msg == "mine" then
        BossDebuffTrackerDB.onlyMine = not BossDebuffTrackerDB.onlyMine
        UpdateAll()
        print("|cff00ccff[BossDebuffTracker]|r Only my debuffs: " ..
            (BossDebuffTrackerDB.onlyMine and "ON" or "OFF"))

    elseif msg == "timer" then
        BossDebuffTrackerDB.showTimer = not BossDebuffTrackerDB.showTimer
        ApplyTimers(); UpdateAll()
        print("|cff00ccff[BossDebuffTracker]|r Timers: " ..
            (BossDebuffTrackerDB.showTimer and "ON" or "OFF"))

    elseif msg:find("^size ") then
        local v = tonumber(msg:match("size (%S+)"))
        if v and v >= 16 and v <= 48 then
            BossDebuffTrackerDB.iconSize = v
            ApplyIconSize(); UpdateAll()
            print("|cff00ccff[BossDebuffTracker]|r Icon size: " .. v)
        else
            print("|cff00ccff[BossDebuffTracker]|r Usage: /bdt size <16–48>")
        end

    elseif msg:find("^max ") then
        local v = tonumber(msg:match("max (%S+)"))
        if v and v >= 1 and v <= 10 then
            BossDebuffTrackerDB.maxDebuffs = v
            UpdateAll()
            print("|cff00ccff[BossDebuffTracker]|r Max debuffs: " .. v)
        else
            print("|cff00ccff[BossDebuffTracker]|r Usage: /bdt max <1–10>")
        end

    elseif msg:find("^filter add ") then
        local id = tonumber(msg:match("filter add (%d+)"))
        if id then BossDebuffTrackerDB.filter[id] = true
            print("|cff00ccff[BossDebuffTracker]|r Added spell " .. id) end

    elseif msg:find("^filter remove ") then
        local id = tonumber(msg:match("filter remove (%d+)"))
        if id then BossDebuffTrackerDB.filter[id] = nil
            print("|cff00ccff[BossDebuffTracker]|r Removed spell " .. id) end

    elseif msg == "filter clear" then
        BossDebuffTrackerDB.filter = {}
        print("|cff00ccff[BossDebuffTracker]|r Filter cleared.")

    else
        print("|cff00ccff[BossDebuffTracker]|r Commands:")
        print("  /bdt                       — open settings panel")
        print("  /bdt test                  — toggle test mode")
        print("  /bdt mine                  — toggle only-my-debuffs")
        print("  /bdt timer                 — toggle cooldown timers")
        print("  /bdt size <16–48>          — set icon size")
        print("  /bdt max <1–10>            — max debuffs shown per boss")
        print("  /bdt enable / disable")
        print("  /bdt filter add/remove/clear <spellID>")
    end
end
