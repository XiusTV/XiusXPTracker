--[[
    Xius XP/Rep Tracker - Config.lua
    Defaults, saved variables, Blizzard Settings panel, and slash commands.
]]

local ADDON, FBT = ...
_G.XiusXPRepTracker = FBT
_G.ForeverBarTracker = FBT

FBT.ADDON = ADDON
FBT.TITLE = "Xius XP/Rep Tracker"
FBT.DB_VERSION = 6

FBT.defaults = {
    dbVersion = 6,
    -- EMBEDDED = stats expand on the XP/rep card (hover/click).
    -- SEPARATE = always-on movable stats box; card stays collapsed.
    statsDisplayMode = "EMBEDDED",
    expandTrigger = "HOVER",
    showXPBar = true,
    showRepBar = true,
    showSessionTime = true,
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
}

local optionWidgets = {}
local optionsCategory
local optionsPanel
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
        db.dbVersion = 6
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
        SetDBValue(key, self:GetChecked() and true or false)
    end)
    optionWidgets[key] = cb
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
            widget:SetText(labels[db.growthDirection or "AUTO"] or labels.AUTO)
        elseif widget.IsObjectType and widget:IsObjectType("CheckButton") then
            if key == "modeEmbedded" then
                widget:SetChecked(db.statsDisplayMode ~= "SEPARATE")
            elseif key == "modeSeparate" then
                widget:SetChecked(db.statsDisplayMode == "SEPARATE")
            elseif key == "expandHover" then
                widget:SetChecked(db.expandTrigger ~= "CLICK")
            elseif key == "expandClick" then
                widget:SetChecked(db.expandTrigger == "CLICK")
            else
                widget:SetChecked(db[key] and true or false)
            end
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
    optionsPanel = panel

    local scroll = CreateFrame("ScrollFrame", "XiusXPRepTrackerOptionsScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(540, 980)
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
    local modeEmbeddedText = modeEmbedded.Text or modeEmbedded:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    modeEmbedded.Text = modeEmbeddedText
    modeEmbeddedText:ClearAllPoints()
    modeEmbeddedText:SetPoint("LEFT", modeEmbedded, "RIGHT", 4, 0)
    modeEmbeddedText:SetText("On XP/rep card (hover or click)")
    optionWidgets.modeEmbedded = modeEmbedded

    y = y - 26
    local modeSeparate = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    modeSeparate:SetPoint("TOPLEFT", 12, y)
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
    local hoverText = hover.Text or hover:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    hover.Text = hoverText
    hoverText:ClearAllPoints()
    hoverText:SetPoint("LEFT", hover, "RIGHT", 4, 0)
    hoverText:SetText("Hover to expand stats")
    optionWidgets.expandHover = hover

    local click = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    click:SetPoint("LEFT", hoverText, "RIGHT", 24, 0)
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
    MakeLabel(content, "Tracked Stats", "GameFontNormal", 16, y)
    y = y - 22
    local note = MakeLabel(content, "Disabled metrics hide in the stats area (card or separate box). All are on by default.", "GameFontHighlightSmall", 16, y)
    note:SetWidth(500)
    y = y - 28

    local rowToggles = {
        { "showSessionTime", "Session duration" },
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

    panel:SetScript("OnShow", SyncOptionsPanel)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        optionsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(optionsCategory)
    end
end

function FBT:OpenOptions()
    self:CreateOptions()
    if Settings and Settings.OpenToCategory then
        if optionsCategory then
            local id = optionsCategory.GetID and optionsCategory:GetID() or optionsCategory
            Settings.OpenToCategory(id)
            return
        end
        Settings.OpenToCategory(FBT.TITLE)
        return
    end
    self:Print("Options panel is not available. Use /xt lock or /xt reset.")
end

function FBT:HandleSlash(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$") or ""
    msg = string.lower(msg)
    if msg == "config" or msg == "opt" or msg == "options" or msg == "settings" then
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
        self:Print("Aliases: /xiusxp   /xt opt")
    end
end

SLASH_XIUSXPTRACKER1 = "/xt"
SLASH_XIUSXPTRACKER2 = "/xiusxp"
SlashCmdList.XIUSXPTRACKER = function(msg)
    FBT:HandleSlash(msg)
end
