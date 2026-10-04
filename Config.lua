--[[
    Xius XP/Rep Tracker - Config.lua
    Defaults, saved variables, Blizzard Settings panel, and slash commands.
]]

local ADDON, FBT = ...
_G.XiusXPRepTracker = FBT
_G.ForeverBarTracker = FBT

FBT.ADDON = ADDON
FBT.TITLE = "Xius XP/Rep Tracker"
FBT.DB_VERSION = 4

FBT.defaults = {
    dbVersion = 4,
    expandTrigger = "HOVER",
    showXPBar = true,
    showRepBar = true,
    showSessionTime = true,
    showXPHour = true,
    showTTL = true,
    showKTL = true,
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
    width = 620,
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
    if db.expandTrigger ~= "CLICK" then
        db.expandTrigger = "HOVER"
    end
    if db.growthDirection ~= "UP" and db.growthDirection ~= "DOWN" then
        db.growthDirection = "AUTO"
    end
    if type(db.width) ~= "number" then
        db.width = self.defaults.width
    end

    local version = tonumber(db.dbVersion) or 1
    if version < 2 then
        if db.point == "BOTTOM" and db.relativePoint == "BOTTOM" and (db.x == 0 or db.x == nil) and db.y == 28 then
            db.y = 0
        end
    end
    if version < 4 then
        if (db.width or 0) < 600 then
            db.width = 620
        end
        db.dbVersion = 4
    end
    db.width = math.max(600, math.min(1200, db.width))
end

function FBT:NotifySettingsChanged()
    if self.ApplySettings then
        self:ApplySettings()
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
    FBT:NotifySettingsChanged()
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
            if key == "expandHover" then
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
    content:SetSize(540, 820)
    scroll:SetScrollChild(content)

    local y = -12
    MakeLabel(content, "Xius XP/Rep Tracker", "GameFontNormalLarge", 16, y)
    y = y - 28
    local sub = MakeLabel(
        content,
        "Replaces the default XP/rep bar with a single HUD card. Shift-drag to move when unlocked. Hover or click expands the card; it grows up or down to stay on screen.",
        "GameFontHighlightSmall",
        16,
        y
    )
    sub:SetWidth(500)
    sub:SetJustifyH("LEFT")
    y = y - 40

    MakeLabel(content, "Expansion", "GameFontNormal", 16, y)
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
        if FBT.UpdateFrameOrientation then
            FBT:UpdateFrameOrientation(FBT:ResolveGrowthDirection())
        end
    end)
    local growthHint = MakeLabel(content, "Click to cycle. Auto uses the card's position on screen.", "GameFontHighlightSmall", 244, y + 4)
    growthHint:SetWidth(260)

    y = y - 36
    MakeLabel(content, "Bars & Position", "GameFontNormal", 16, y)
    y = y - 28
    MakeCheck(content, "Lock card position (prevents Shift-drag and resizing)", "isLocked", 12, y)
    y = y - 28
    MakeCheck(content, "Show XP bar (hides at max level if reputation is shown)", "showXPBar", 12, y)
    y = y - 28
    MakeCheck(content, "Show reputation bar (watched faction; used at max level)", "showRepBar", 12, y)

    y = y - 36
    MakeLabel(content, "Card Stats", "GameFontNormal", 16, y)
    y = y - 22
    local note = MakeLabel(content, "Disabled metrics hide inside the expanded HUD card. All are on by default.", "GameFontHighlightSmall", 16, y)
    note:SetWidth(500)
    y = y - 28

    local rowToggles = {
        { "showSessionTime", "Session duration" },
        { "showXPHour", "XP / Hour" },
        { "showTTL", "Time to Level (TTL)" },
        { "showKTL", "Kills to Level (KTL)" },
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
        FBT:NotifySettingsChanged()
        FBT:Print("Bar restored to the default XP bar position.")
    end)

    panel:SetScript("OnShow", SyncOptionsPanel)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        optionsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(optionsCategory)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
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
    if InterfaceOptionsFrame_OpenToCategory and optionsPanel then
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
        return
    end
    self:Print("Options panel is not available on this client. Use /xt lock or /xt reset.")
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
    elseif msg == "reset" then
        if self.ResetSession then
            self:ResetSession()
        end
    elseif msg == "unlock" then
        if self.db then
            self.db.isLocked = false
            self:NotifySettingsChanged()
            self:Print("Bar unlocked. Shift-drag to move.")
        end
    else
        self:Print("Commands: /xt config  |  /xt lock  |  /xt reset")
        self:Print("Aliases: /xiusxp   /xt opt")
    end
end

SLASH_XIUSXPTRACKER1 = "/xt"
SLASH_XIUSXPTRACKER2 = "/xiusxp"
SlashCmdList.XIUSXPTRACKER = function(msg)
    FBT:HandleSlash(msg)
end
