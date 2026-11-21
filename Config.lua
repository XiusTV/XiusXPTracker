--[[
    Xius XP/Rep Tracker - Config.lua
    Saved variables and slash commands. The options window is XiusCoreSettingsLib.
]]

local addonName, ns = ...
local ADDON, FBT = addonName, ns

local XiusCore = _G.XiusCore or _G.XiusCoreSettingsLib
if not XiusCore and C_AddOns and C_AddOns.IsAddOnLoaded then
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, "XiusCore")
    XiusCore = ok and loaded and true or false
end
if not XiusCore and IsAddOnLoaded then
    local ok, loaded = pcall(IsAddOnLoaded, "XiusCore")
    XiusCore = ok and loaded and true or false
end
if not XiusCore then
    return
end

FBT.ADDON = ADDON
FBT.TITLE = "Xius XP/Rep Tracker"
FBT.DB_VERSION = 14

FBT.defaults = {
    dbVersion = 14,
    enabled = true,
    barStyle = "blizzard",
    autoTrackRep = false,
    autoTrackRepIgnoreExalted = true,
    autoTrackRepOnlyOutOfCombat = false,
    repPickerMode = "AUTO",
    cardHeight = 64,
    scale = 1,
    xpColor = { 122 / 255, 50 / 255, 201 / 255 },
    restedColor = { 31 / 255, 139 / 255, 255 },
    repColor = { 0.36, 0.70, 0.92 },
    -- EMBEDDED = stats expand on the XP/rep card (hover/click).
    -- SEPARATE = always-on movable stats box; card stays collapsed.
    statsDisplayMode = "EMBEDDED",
    expandTrigger = "HOVER",
    showXPBar = true,
    showRepBar = true,
    showSessionTime = true,
    showInstanceTime = true,
    showTimeLevel = true,
    showTimePlayed = true,
    showXPHour = true,
    showTTL = true,
    showOverallTTL = true,
    showKTL = true,
    showQTL = true,
    showGoldSession = true,
    showGoldHour = true,
    showRested = true,
    showRepSession = true,
    showRepHour = true,
    showRepNextRank = true,
    showRepExalted = true,
    -- When true, entering a new instance starts a fresh instance run timer
    -- (shown as INSTANCE TIME while inside). Session time still tracks login.
    resetInstanceTimerOnEnter = true,
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
    if db.showTimeLevel == nil then
        db.showTimeLevel = true
    end
    if db.showTimePlayed == nil then
        db.showTimePlayed = true
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
        db.panelWidth = 340
        db.panelY = db.panelY or 80
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
    if version < 12 then
        if db.panelPoint == "TOPLEFT" and db.panelRelativePoint == "TOPLEFT" and db.panelX == 0 and db.panelY == 0 then
            db.panelPoint = self.defaults.panelPoint
            db.panelRelativePoint = self.defaults.panelRelativePoint
            db.panelX = self.defaults.panelX
            db.panelY = self.defaults.panelY
        end
        db.dbVersion = 12
    end
    -- Purge legacy QoL keys now owned by XiusCore
    db.fasterLoot = nil
    db.autoSellJunk = nil
    db.trainAllButton = nil
    db.maxRankActionBars = nil
    db.autoRepair = nil
    if version < 13 then
        if db.enabled == nil then
            db.enabled = true
        end
        if db.barStyle ~= "minimal" then
            db.barStyle = "blizzard"
        end
        if db.autoTrackRep == nil then
            db.autoTrackRep = false
        end
        if type(db.cardHeight) ~= "number" then
            db.cardHeight = 64
        end
        db.dbVersion = 13
    end
    if db.enabled == nil then
        db.enabled = true
    end
    if db.barStyle ~= "minimal" then
        db.barStyle = "blizzard"
    end
    if db.autoTrackRep == nil then
        db.autoTrackRep = false
    end
    if db.autoTrackRepIgnoreExalted == nil then
        db.autoTrackRepIgnoreExalted = true
    end
    if db.autoTrackRepOnlyOutOfCombat == nil then
        db.autoTrackRepOnlyOutOfCombat = false
    end
    if db.repPickerMode ~= "MANUAL" then
        db.repPickerMode = "AUTO"
    end
    if type(db.cardHeight) ~= "number" then
        db.cardHeight = self.defaults.cardHeight
    end
    if type(db.scale) ~= "number" then
        db.scale = self.defaults.scale
    end
    if type(ForeverBarTrackerCharDB) ~= "table" then
        ForeverBarTrackerCharDB = {}
    end
    if type(ForeverBarTrackerCharDB.careerLevelStats) ~= "table" then
        ForeverBarTrackerCharDB.careerLevelStats = {}
    end
    self.charDB = ForeverBarTrackerCharDB
    self.careerLevelStats = ForeverBarTrackerCharDB.careerLevelStats

    if db.showOverallTTL == nil then
        db.showOverallTTL = true
    end
    db.width = math.max(660, math.min(1200, db.width))
    db.panelWidth = math.max(280, math.min(520, db.panelWidth))
    db.cardHeight = math.max(62, math.min(80, db.cardHeight))
    db.scale = math.max(0.75, math.min(1.5, db.scale))

    -- Join XiusCore profile table so /xius profile switches keep XP/Rep settings.
    if type(XiusUIDB) ~= "table" then
        XiusUIDB = {}
    end
    if type(XiusUIDB.xprep) ~= "table" then
        XiusUIDB.xprep = self.db
    elseif XiusUIDB.xprep ~= self.db then
        for key, value in pairs(XiusUIDB.xprep) do
            if self.db[key] == nil then
                self.db[key] = value
            end
        end
        XiusUIDB.xprep = self.db
    end
    ForeverBarTrackerDB = self.db
end

-- Keep ForeverBarTrackerDB, XiusUIDB.xprep, and FBT.db aliased after profile switches.
function FBT:SyncProfileDB()
    if type(XiusUIDB) == "table" and type(XiusUIDB.xprep) == "table" then
        if self.db ~= XiusUIDB.xprep then
            self.db = XiusUIDB.xprep
        end
        if ForeverBarTrackerDB ~= XiusUIDB.xprep then
            ForeverBarTrackerDB = XiusUIDB.xprep
        end
    elseif type(ForeverBarTrackerDB) == "table" then
        self.db = ForeverBarTrackerDB
        if type(XiusUIDB) == "table" then
            XiusUIDB.xprep = ForeverBarTrackerDB
        end
    end
    if type(self.db) == "table" then
        CopyDefaults(self.defaults, self.db)
        local db = self.db
        db.width = math.max(660, math.min(1200, db.width or self.defaults.width))
        db.panelWidth = math.max(280, math.min(520, db.panelWidth or self.defaults.panelWidth))
        db.cardHeight = math.max(62, math.min(80, db.cardHeight or self.defaults.cardHeight))
        db.scale = math.max(0.75, math.min(1.5, db.scale or self.defaults.scale))
        if db.repPickerMode ~= "MANUAL" then
            db.repPickerMode = "AUTO"
        end
    end
end

function FBT:NotifySettingsChanged(key)
    if self.SyncProfileDB then
        self:SyncProfileDB()
    end
    if self.ApplySettings then
        self:ApplySettings(key)
    end
end

function FBT:ResetCareerStats()
    if type(ForeverBarTrackerCharDB) ~= "table" then
        ForeverBarTrackerCharDB = {}
    end
    ForeverBarTrackerCharDB.careerLevelStats = {}
    self.charDB = ForeverBarTrackerCharDB
    self.careerLevelStats = ForeverBarTrackerCharDB.careerLevelStats
    if self.OnCareerStatsReset then
        self:OnCareerStatsReset()
    end
    self:Print("Career leveling history reset.")
end

function FBT:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffXius XP/Rep Tracker|r: " .. tostring(msg))
end

function FBT:OpenOptions()
    if InCombatLockdown and InCombatLockdown() then
        self:Print("Cannot open settings during combat.")
        return
    end
    local Lib = _G.XiusCoreSettingsLib
    if not Lib then
        return
    end
    if Lib.OpenModule then
        Lib:OpenModule("XPRep")
        if C_Timer and C_Timer.After and self.NudgePanelClearOfOptions then
            C_Timer.After(0, function()
                FBT:NudgePanelClearOfOptions()
            end)
        elseif self.NudgePanelClearOfOptions then
            self:NudgePanelClearOfOptions()
        end
        return
    end
    if Lib.Open then
        Lib:Open("XPRep")
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
            self:NotifySettingsChanged("panelLocked")
            self:Print("Card and stats box unlocked. Use Unlock Frames in /xius to move.")
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
