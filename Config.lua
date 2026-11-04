--[[
    Xius XP/Rep Tracker - Config.lua
    Defaults, saved variables, Blizzard Settings panel, and slash commands.
]]

local ADDON, FBT = ...
_G.XiusXPRepTracker = FBT
_G.ForeverBarTracker = FBT

FBT.ADDON = ADDON
FBT.TITLE = "Xius XP/Rep Tracker"
FBT.DB_VERSION = 12

FBT.defaults = {
    dbVersion = 12,
    -- EMBEDDED = stats expand on the XP/rep card (hover/click).
    -- SEPARATE = always-on movable stats box; card stays collapsed.
    statsDisplayMode = "EMBEDDED",
    expandTrigger = "HOVER",
    showXPBar = true,
    showRepBar = true,
    showSessionTime = true,
    showTimeLevel = true,
    showTimePlayed = true,
    showXPHour = true,
    showTTL = true,
    showKTL = true,
    showQTL = true,
    showGoldSession = true,
    showGoldHour = true,
    showRested = true,
    showRepSession = true,
    showRepHour = true,
    showRepNextRank = true,
    showRepExalted = true,
    growthDirection = "AUTO",
    isLocked = false,
    point = "BOTTOM",
    relativePoint = "BOTTOM",
    x = 0,
    y = 0,
    width = 720,
    panelPoint = "CENTER",
    panelRelativePoint = "CENTER",
    panelX = 0,
    panelY = 80,
    panelWidth = 340,
    panelLocked = false,
    fasterLoot = true,
    autoSellJunk = true,
    autoRepair = true,
    trainAllButton = true,
    maxRankActionBars = true,
}

local optionWidgets = {}
local optionsCategory
local optionsPanel
local optionsDialog
local optionsScroll
local syncingOptions = false

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then
        dst = {}
    end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function FBT:GetDB()
    return self.db
end

function FBT:InitDB()
    ForeverBarTrackerDB = CopyDefaults(self.defaults, ForeverBarTrackerDB)
    self.db = ForeverBarTrackerDB
    local db = self.db
    if db.statsDisplayMode ~= "SEPARATE" then
        db.statsDisplayMode = "EMBEDDED"
    end
    if db.expandTrigger ~= "CLICK" then
        db.expandTrigger = "HOVER"
    end
    if db.growthDirection ~= "UP" and db.growthDirection ~= "DOWN" then
        db.growthDirection = "AUTO"
    end
    if type(db.width) ~= "number" then
        db.width = self.defaults.width
    end
    if type(db.panelWidth) ~= "number" then
        db.panelWidth = self.defaults.panelWidth
    end
    if type(db.panelX) ~= "number" then
        db.panelX = self.defaults.panelX
    end
    if type(db.panelY) ~= "number" then
        db.panelY = self.defaults.panelY
    end
    if db.panelPoint == nil then
        db.panelPoint = self.defaults.panelPoint
    end
    if db.panelRelativePoint == nil then
        db.panelRelativePoint = self.defaults.panelRelativePoint
    end
    if db.panelLocked == nil then
        db.panelLocked = false
    end
    if db.showQTL == nil then
        db.showQTL = true
    end
    if db.fasterLoot == nil then
        db.fasterLoot = true
    end
    if db.autoSellJunk == nil then
        db.autoSellJunk = true
    end
    if db.autoRepair == nil then
        db.autoRepair = true
    end
    if db.trainAllButton == nil then
        db.trainAllButton = true
    end
    if db.showTimeLevel == nil then
        db.showTimeLevel = true
    end
    if db.showTimePlayed == nil then
        db.showTimePlayed = true
    end
    if db.maxRankActionBars == nil then
        db.maxRankActionBars = true
    end

    local version = tonumber(db.dbVersion) or 1
    if version < 2 then
        if db.point == "BOTTOM" and db.relativePoint == "BOTTOM" and (db.x == 0 or db.x == nil) and db.y == 28 then
            db.y = 0
        end
    end
    if version < 4 then
        if (db.width or 0) < 600 then
            db.width = 720
        end
    end
    if version < 5 then
        db.statsDisplayMode = db.statsDisplayMode or "EMBEDDED"
        if db.showQTL == nil then
            db.showQTL = true
        end
        if (db.width or 0) < 660 then
            db.width = 720
        end
    end
    if version < 6 then
        -- Older builds used a full-width empty panel; shrink to the compact box.
        db.panelWidth = 340
        db.panelY = db.panelY or 80
    end
    if version < 7 then
        if db.fasterLoot == nil then
            db.fasterLoot = true
        end
        if db.autoSellJunk == nil then
            db.autoSellJunk = true
        end
        db.dbVersion = 7
    end
    if version < 8 then
        if db.trainAllButton == nil then
            db.trainAllButton = true
        end
        db.dbVersion = 8
    end
    if version < 9 then
        if db.showTimeLevel == nil then
            db.showTimeLevel = true
        end
        if db.showTimePlayed == nil then
            db.showTimePlayed = true
        end
        db.dbVersion = 9
    end
    if version < 10 then
        if db.maxRankActionBars == nil then
            db.maxRankActionBars = true
        end
        db.dbVersion = 10
    end
    if version < 11 then
        if db.autoRepair == nil then
            db.autoRepair = true
        end
        db.dbVersion = 11
    end
    if version < 12 then
        if db.panelPoint == "TOPLEFT" and db.panelRelativePoint == "TOPLEFT" and db.panelX == 0 and db.panelY == 0 then
            db.panelPoint = self.defaults.panelPoint
            db.panelRelativePoint = self.defaults.panelRelativePoint
            db.panelX = self.defaults.panelX
            db.panelY = self.defaults.panelY
        end
        db.dbVersion = 12
    end
    db.width = math.max(660, math.min(1200, db.width))
    db.panelWidth = math.max(280, math.min(520, db.panelWidth))
end

function FBT:NotifySettingsChanged(key)
    if self.ApplySettings then
        self:ApplySettings(key)
    end
end

function FBT:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffXius XP/Rep Tracker|r: " .. tostring(msg))
end

local function SetDBValue(key, value)
    local db = FBT.db
    if not db then
        return
    end
    db[key] = value
    FBT:NotifySettingsChanged(key)
end

local function PaintCheck(cb, checked)
    if not cb then
        return
    end
    if checked == nil then
        checked = cb._wantChecked
    end
    checked = checked and true or false
    cb._wantChecked = checked
    -- This client often ignores SetChecked until a real click, so the mark
    -- is drawn ourselves and the template check texture is hidden.
    if cb.SetChecked and cb.GetChecked then
        local current = cb:GetChecked() and true or false
        if current ~= checked then
            cb:SetChecked(checked)
        end
    end
    if not cb._mark then
        if cb.GetCheckedTexture then
            local stock = cb:GetCheckedTexture()
            if stock then
                stock:SetAlpha(0)
            end
        end
        local mark = cb:CreateTexture(nil, "OVERLAY", nil, 7)
        mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        mark:SetSize(24, 24)
        mark:SetPoint("CENTER", cb, "CENTER", 0, 0)
        cb._mark = mark
        cb:HookScript("OnShow", function(self)
            PaintCheck(self, self._wantChecked)
        end)
    end
    if checked then
        cb._mark:Show()
    else
        cb._mark:Hide()
    end
end

local function MakeCheck(parent, label, key, x, y)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetHitRectInsets(0, -280, 0, 0)
    local text = cb.Text or cb.text
    if not text then
        text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        cb.Text = text
    end
    text:ClearAllPoints()
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(label)
    cb:SetScript("OnClick", function(self)
        if syncingOptions then
            return
        end
        local on = self:GetChecked() and true or false
        self._wantChecked = on
        if self._mark then
            if on then
                self._mark:Show()
            else
                self._mark:Hide()
            end
        end
        SetDBValue(key, on)
    end)
    optionWidgets[key] = cb
    PaintCheck(cb, FBT.db and FBT.db[key])
    return cb
end

local function MakeLabel(parent, text, template, x, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function SyncOptionsPanel()
    local db = FBT.db
    if not db then
        return
    end
    syncingOptions = true
    for key, widget in pairs(optionWidgets) do
        if key == "growthDirection" then
            local labels = {
                AUTO = "Auto (Screen Position)",
                UP = "Always Expand Up",
                DOWN = "Always Expand Down",
            }
            if widget.SetText then
                widget:SetText(labels[db.growthDirection or "AUTO"] or labels.AUTO)
            end
        elseif widget.SetChecked then
            local checked
            if key == "modeEmbedded" then
                checked = db.statsDisplayMode ~= "SEPARATE"
            elseif key == "modeSeparate" then
                checked = db.statsDisplayMode == "SEPARATE"
            elseif key == "expandHover" then
                checked = db.expandTrigger ~= "CLICK"
            elseif key == "expandClick" then
                checked = db.expandTrigger == "CLICK"
            else
                checked = db[key] and true or false
            end
            PaintCheck(widget, checked)
        end
    end
    syncingOptions = false
end

function FBT:CreateOptions()
    if optionsPanel then
        return
    end

    local panel = CreateFrame("Frame")
    panel.name = FBT.TITLE
    if panel.SetClipsChildren then
        panel:SetClipsChildren(true)
    end
    optionsPanel = panel

    local scroll = CreateFrame("ScrollFrame", "XiusXPRepTrackerOptionsScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    if scroll.SetClipsChildren then
        scroll:SetClipsChildren(true)
    end

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(540, 1400)
    scroll:SetScrollChild(content)

    local y = -12
    MakeLabel(content, "Xius XP/Rep Tracker", "GameFontNormalLarge", 16, y)
    y = y - 28
    local sub = MakeLabel(
        content,
        "Replaces the default XP/rep bar with a HUD card. Stats can expand on the card (default) or live in a separate movable box. Shift-drag to move when unlocked.",
        "GameFontHighlightSmall",
        16,
        y
    )
    sub:SetWidth(500)
    sub:SetJustifyH("LEFT")
    y = y - 44

    MakeLabel(content, "Stats Display", "GameFontNormal", 16, y)
    y = y - 22

    local modeEmbedded = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    modeEmbedded:SetPoint("TOPLEFT", 12, y)
    modeEmbedded:SetHitRectInsets(0, -240, 0, 0)
    local modeEmbeddedText = modeEmbedded.Text or modeEmbedded:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    modeEmbedded.Text = modeEmbeddedText
    modeEmbeddedText:ClearAllPoints()
    modeEmbeddedText:SetPoint("LEFT", modeEmbedded, "RIGHT", 4, 0)
    modeEmbeddedText:SetText("On XP/rep card (hover or click)")
    optionWidgets.modeEmbedded = modeEmbedded

    y = y - 26
    local modeSeparate = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    modeSeparate:SetPoint("TOPLEFT", 12, y)
    modeSeparate:SetHitRectInsets(0, -240, 0, 0)
    local modeSeparateText = modeSeparate.Text or modeSeparate:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    modeSeparate.Text = modeSeparateText
    modeSeparateText:ClearAllPoints()
    modeSeparateText:SetPoint("LEFT", modeSeparate, "RIGHT", 4, 0)
    modeSeparateText:SetText("Separate stats box (always visible)")
    optionWidgets.modeSeparate = modeSeparate

    local function SetStatsDisplayMode(mode)
        if syncingOptions then
            return
        end
        SetDBValue("statsDisplayMode", mode)
        SyncOptionsPanel()
    end
    modeEmbedded:SetScript("OnClick", function()
        SetStatsDisplayMode("EMBEDDED")
    end)
    modeSeparate:SetScript("OnClick", function()
        SetStatsDisplayMode("SEPARATE")
    end)

    y = y - 36
    MakeLabel(content, "Card Expansion (when stats are on the XP/rep card)", "GameFontNormal", 16, y)
    y = y - 22

    local hover = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    hover:SetPoint("TOPLEFT", 12, y)
    hover:SetHitRectInsets(0, -140, 0, 0)
    local hoverText = hover.Text or hover:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    hover.Text = hoverText
    hoverText:ClearAllPoints()
    hoverText:SetPoint("LEFT", hover, "RIGHT", 4, 0)
    hoverText:SetText("Hover to expand stats")
    optionWidgets.expandHover = hover

    local click = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    click:SetPoint("LEFT", hoverText, "RIGHT", 24, 0)
    click:SetHitRectInsets(0, -140, 0, 0)
    local clickText = click.Text or click:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    click.Text = clickText
    clickText:ClearAllPoints()
    clickText:SetPoint("LEFT", click, "RIGHT", 4, 0)
    clickText:SetText("Click to expand stats")
    optionWidgets.expandClick = click

    local function SetExpandTrigger(mode)
        if syncingOptions then
            return
        end
        SetDBValue("expandTrigger", mode)
        SyncOptionsPanel()
    end
    hover:SetScript("OnClick", function()
        SetExpandTrigger("HOVER")
    end)
    click:SetScript("OnClick", function()
        SetExpandTrigger("CLICK")
    end)

    y = y - 36
    MakeLabel(content, "Expansion Direction", "GameFontNormal", 16, y)
    y = y - 24
    local growthLabels = {
        AUTO = "Auto (Screen Position)",
        UP = "Always Expand Up",
        DOWN = "Always Expand Down",
    }
    local growthOrder = { "AUTO", "UP", "DOWN" }
    local growthBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    growthBtn:SetSize(220, 24)
    growthBtn:SetPoint("TOPLEFT", 16, y)
    optionWidgets.growthDirection = growthBtn
    local function GrowthLabel()
        local mode = FBT.db and FBT.db.growthDirection or "AUTO"
        return growthLabels[mode] or growthLabels.AUTO
    end
    growthBtn:SetText(GrowthLabel())
    growthBtn:SetScript("OnClick", function()
        if syncingOptions or not FBT.db then
            return
        end
        local current = FBT.db.growthDirection or "AUTO"
        local nextMode = "AUTO"
        for i = 1, #growthOrder do
            if growthOrder[i] == current then
                nextMode = growthOrder[(i % #growthOrder) + 1]
                break
            end
        end
        SetDBValue("growthDirection", nextMode)
        growthBtn:SetText(GrowthLabel())
    end)
    local growthHint = MakeLabel(content, "Click to cycle. Auto uses the card's position on screen.", "GameFontHighlightSmall", 244, y + 4)
    growthHint:SetWidth(260)

    y = y - 36
    MakeLabel(content, "Bars & Position", "GameFontNormal", 16, y)
    y = y - 28
    MakeCheck(content, "Lock XP/rep card (prevents Shift-drag and resizing)", "isLocked", 12, y)
    y = y - 28
    MakeCheck(content, "Lock separate stats box", "panelLocked", 12, y)
    y = y - 28
    MakeCheck(content, "Show XP bar (hides at max level if reputation is shown)", "showXPBar", 12, y)
    y = y - 28
    MakeCheck(content, "Show reputation bar (watched faction; used at max level)", "showRepBar", 12, y)

    y = y - 36
    MakeLabel(content, "Loot & Vendor", "GameFontNormal", 16, y)
    y = y - 22
    local lootNote = MakeLabel(
        content,
        "Faster loot auto-loots corpses. Hold Shift to look at the loot window instead. Auto-sell only greys at vendors. Auto-repair uses your gold.",
        "GameFontHighlightSmall",
        16,
        y
    )
    lootNote:SetWidth(500)
    y = y - 34
    MakeCheck(content, "Faster loot (auto-loot corpses instantly)", "fasterLoot", 12, y)
    y = y - 28
    MakeCheck(content, "Auto-sell junk (grey items) at vendors", "autoSellJunk", 12, y)
    y = y - 28
    MakeCheck(content, "Auto-repair at vendors", "autoRepair", 12, y)
    y = y - 28
    MakeCheck(content, "Show Train All button at class and profession trainers", "trainAllButton", 12, y)
    y = y - 28
    MakeCheck(content, "Upgrade action bars to max-rank spells (login, level-up, trainer)", "maxRankActionBars", 12, y)

    y = y - 36
    MakeLabel(content, "Tracked Stats", "GameFontNormal", 16, y)
    y = y - 22
    local note = MakeLabel(content, "Disabled metrics hide in the stats area (card or separate box). All are on by default.", "GameFontHighlightSmall", 16, y)
    note:SetWidth(500)
    y = y - 28

    local rowToggles = {
        { "showSessionTime", "Session duration" },
        { "showTimeLevel", "Time played this level" },
        { "showTimePlayed", "Total time played on this character" },
        { "showXPHour", "XP / Hour" },
        { "showTTL", "Time to Level (TTL)" },
        { "showKTL", "Kills to Level (KTL)" },
        { "showQTL", "Quests to Level (QTL)" },
        { "showGoldSession", "Gold earned this session" },
        { "showGoldHour", "Gold / Hour" },
        { "showRested", "Rested XP / percent" },
        { "showRepSession", "Reputation earned this session" },
        { "showRepHour", "Reputation / Hour" },
        { "showRepNextRank", "Time until next rank" },
        { "showRepExalted", "Time until Exalted / Best Friend / Max" },
    }
    for i = 1, #rowToggles do
        MakeCheck(content, rowToggles[i][2], rowToggles[i][1], 12, y)
        y = y - 26
    end

    y = y - 12
    local resetSession = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetSession:SetSize(140, 24)
    resetSession:SetPoint("TOPLEFT", 16, y)
    resetSession:SetText("Reset Session")
    resetSession:SetScript("OnClick", function()
        if FBT.ResetSession then
            FBT:ResetSession()
        end
    end)

    local resetPos = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetPos:SetSize(140, 24)
    resetPos:SetPoint("LEFT", resetSession, "RIGHT", 8, 0)
    resetPos:SetText("Reset Position")
    resetPos:SetScript("OnClick", function()
        local db = FBT.db
        if not db then
            return
        end
        db.point = FBT.defaults.point
        db.relativePoint = FBT.defaults.relativePoint
        db.x = FBT.defaults.x
        db.y = FBT.defaults.y
        db.width = FBT.defaults.width
        db.panelPoint = FBT.defaults.panelPoint
        db.panelRelativePoint = FBT.defaults.panelRelativePoint
        db.panelX = FBT.defaults.panelX
        db.panelY = FBT.defaults.panelY
        db.panelWidth = FBT.defaults.panelWidth
        FBT:NotifySettingsChanged()
        FBT:Print("Card and stats box restored to default positions.")
    end)

    y = y - 40
    content:SetSize(540, math.max(960, -y))

    local function SyncSoon()
        SyncOptionsPanel()
    end

    local function AttachScrollToCanvas()
        if optionsDialog and optionsDialog:IsShown() then
            optionsDialog:Hide()
        end
        local parent = panel:GetParent()
        if parent and parent ~= UIParent then
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
            panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
        elseif (panel:GetHeight() or 0) < 50 then
            panel:SetSize(580, 480)
        end
        scroll:SetParent(panel)
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
        scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 8)
        scroll:Show()
        SyncOptionsPanel()
    end

    optionsScroll = scroll
    panel.refresh = SyncSoon
    panel.OnRefresh = SyncSoon
    panel.okay = SyncSoon
    panel.OnCommit = SyncSoon
    panel.cancel = SyncSoon
    panel:SetScript("OnShow", function()
        AttachScrollToCanvas()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, AttachScrollToCanvas)
        end
    end)
    scroll:SetScript("OnShow", SyncSoon)
    content:SetScript("OnShow", SyncSoon)
    SyncSoon()

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, panel.name)
        if ok and category then
            optionsCategory = category
            pcall(Settings.RegisterAddOnCategory, category)
        end
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

local function EnsureOptionsDialog()
    if optionsDialog then
        return optionsDialog
    end
    local dlg = CreateFrame("Frame", "XiusXPRepTrackerOptionsDialog", UIParent, "BackdropTemplate")
    dlg:SetSize(600, 540)
    dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    dlg:SetFrameStrata("DIALOG")
    dlg:SetFrameLevel(120)
    dlg:SetClampedToScreen(true)
    dlg:SetMovable(true)
    dlg:EnableMouse(true)
    dlg:RegisterForDrag("LeftButton")
    dlg:SetScript("OnDragStart", dlg.StartMoving)
    dlg:SetScript("OnDragStop", dlg.StopMovingOrSizing)
    dlg:SetScript("OnHide", dlg.StopMovingOrSizing)
    dlg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    dlg:SetBackdropColor(0.04, 0.04, 0.04, 0.96)
    dlg:SetBackdropBorderColor(0.78, 0.62, 0.18, 0.75)
    dlg:Hide()
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "XiusXPRepTrackerOptionsDialog"
    end

    local titleBar = CreateFrame("Frame", nil, dlg, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT", dlg, "TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", -1, -1)
    titleBar:SetHeight(26)
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    titleBar:SetBackdropColor(0.10, 0.10, 0.10, 0.98)
    titleBar:SetBackdropBorderColor(0.78, 0.62, 0.18, 0.45)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    title:SetTextColor(0.95, 0.82, 0.28, 1)
    title:SetText("Xius XP/Rep Tracker — Settings")

    local closeBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    closeBtn:SetSize(20, 18)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -5, 0)
    closeBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    closeBtn:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    closeBtn:SetBackdropBorderColor(0.78, 0.62, 0.18, 0.70)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeText:SetPoint("CENTER", 0, 0)
    closeText:SetTextColor(0.95, 0.82, 0.28, 1)
    closeText:SetText("X")
    closeBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.18, 0.15, 0.08, 1)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    end)
    closeBtn:SetScript("OnClick", function()
        dlg:Hide()
    end)

    dlg:SetScript("OnShow", function(self)
        if optionsScroll then
            optionsScroll:SetParent(self)
            optionsScroll:ClearAllPoints()
            optionsScroll:SetPoint("TOPLEFT", self, "TOPLEFT", 8, -32)
            optionsScroll:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -28, 10)
            optionsScroll:Show()
        end
        SyncOptionsPanel()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, SyncOptionsPanel)
        end
    end)

    optionsDialog = dlg
    return dlg
end

function FBT:OpenOptions()
    if InCombatLockdown and InCombatLockdown() then
        self:Print("Cannot open settings during combat.")
        return
    end
    self:CreateOptions()
    SyncOptionsPanel()
    if Settings and Settings.OpenToCategory and optionsCategory then
        local id = optionsCategory
        if optionsCategory.GetID then
            local ok, catID = pcall(optionsCategory.GetID, optionsCategory)
            if ok and catID then
                id = catID
            end
        end
        pcall(Settings.OpenToCategory, id)
        if id ~= optionsCategory then
            pcall(Settings.OpenToCategory, optionsCategory)
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if not (InCombatLockdown and InCombatLockdown()) then
                    pcall(Settings.OpenToCategory, id)
                end
                SyncOptionsPanel()
            end)
            C_Timer.After(0.1, SyncOptionsPanel)
        end
        if not SettingsPanel or not SettingsPanel.IsShown or SettingsPanel:IsShown() then
            return
        end
    end
    if InterfaceOptionsFrame_OpenToCategory and optionsPanel then
        pcall(InterfaceOptionsFrame_OpenToCategory, optionsPanel)
        pcall(InterfaceOptionsFrame_OpenToCategory, optionsPanel)
        if not InterfaceOptionsFrame or not InterfaceOptionsFrame.IsShown or InterfaceOptionsFrame:IsShown() then
            return
        end
    end
    local dlg = EnsureOptionsDialog()
    if dlg:IsShown() then
        dlg:Hide()
    else
        dlg:Show()
    end
end

function FBT:HandleSlash(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$") or ""
    msg = string.lower(msg)
    if msg == "" or msg == "config" or msg == "opt" or msg == "options" or msg == "settings" then
        self:OpenOptions()
    elseif msg == "lock" then
        if self.ToggleLock then
            self:ToggleLock()
        end
    elseif msg == "panel" or msg == "box" or msg == "separate" then
        if self.db then
            if self.db.statsDisplayMode == "SEPARATE" then
                self.db.statsDisplayMode = "EMBEDDED"
                self:NotifySettingsChanged("statsDisplayMode")
                self:Print("Stats now expand on the XP/rep card.")
            else
                self.db.statsDisplayMode = "SEPARATE"
                self:NotifySettingsChanged("statsDisplayMode")
                self:Print("Stats moved to a separate box.")
            end
        end
    elseif msg == "reset" then
        if self.ResetSession then
            self:ResetSession()
        end
    elseif msg == "unlock" then
        if self.db then
            self.db.isLocked = false
            self.db.panelLocked = false
            self:NotifySettingsChanged("isLocked")
            self:Print("Card and stats box unlocked. Shift-drag to move.")
        end
    else
        self:Print("Commands: /xt config  |  /xt lock  |  /xt panel  |  /xt reset")
        self:Print("Aliases: /xiusxp   /xt opt   /xxp   /xrep   /xxr (options)")
    end
end

SLASH_XIUSXPTRACKER1 = "/xt"
SLASH_XIUSXPTRACKER2 = "/xiusxp"
SLASH_XIUSXPTRACKER3 = "/xxp"
SLASH_XIUSXPTRACKER4 = "/xrep"
SLASH_XIUSXPTRACKER5 = "/xxr"
SlashCmdList.XIUSXPTRACKER = function(msg)
    FBT:HandleSlash(msg)
end

SLASH_XIUSXP1 = "/xxp"
SlashCmdList.XIUSXP = function(msg)
    FBT:HandleSlash(msg)
end

SLASH_XIUSREP1 = "/xrep"
SlashCmdList.XIUSREP = function(msg)
    FBT:HandleSlash(msg)
end

SLASH_XIUSXPOPTIONS1 = "/xxr"
SlashCmdList.XIUSXPOPTIONS = function(msg)
    FBT:HandleSlash(msg)
end
