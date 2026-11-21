local addonName, ns = ...
local FBT = ns

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

local Lib = _G.XiusCoreSettingsLib
if not Lib or not Lib.RegisterModule then
    return
end

local SUB_TABS = {
    { id = "general", text = "General", width = 104 },
    { id = "xprep", text = "XP & Reputation", width = 148 },
}

local BAR_STYLE_ITEMS = {
    { value = "blizzard", text = "Blizzard Modern" },
    { value = "minimal", text = "Minimal Dark" },
}

local GROWTH_DIRECTION_ITEMS = {
    { value = "AUTO", text = "Auto (Screen Position)" },
    { value = "UP", text = "Always Expand Up" },
    { value = "DOWN", text = "Always Expand Down" },
}

local EXPAND_TRIGGER_ITEMS = {
    { value = "HOVER", text = "Hover" },
    { value = "CLICK", text = "Click" },
}

local TRACKED_STATS = {
    { "showSessionTime", "Session duration" },
    { "showInstanceTime", "Instance run timer (per dungeon/raid entry)" },
    { "showTimeLevel", "Time played this level" },
    { "showTimePlayed", "Total time played on this character" },
    { "showXPHour", "XP / Hour" },
    { "showTTL", "Time to Level (TTL)" },
    { "showOverallTTL", "Overall TTL (career + session blend)" },
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

local function RefreshPage()
    if not Lib.ShowPage or Lib._building then
        return
    end
    local function Go()
        if Lib.frame and Lib.frame:IsShown() and Lib.page == "XPRep" then
            Lib:ShowPage("XPRep")
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, Go)
    else
        Go()
    end
end

local function CopyDefault(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, inner in pairs(value) do
        copy[key] = CopyDefault(inner)
    end
    return copy
end

local function BuildGeneralTab(api, db, Apply, Bool)
    api:AddNote("Replaces the default XP/rep bar with a movable HUD card. Use Unlock Frames in /xius to move it.")

    api:AddSection("Card")
    Bool("enabled", "Enable XP and reputation card", "Shows or hides the XP/rep card and the separate stats box.")
    api:AddDropdown("Bar style", BAR_STYLE_ITEMS, function()
        return db.barStyle == "minimal" and "minimal" or "blizzard"
    end, function(value)
        db.barStyle = value == "minimal" and "minimal" or "blizzard"
        Apply("barStyle")
    end, "Blizzard Modern uses the gold border and experience ticks. Minimal Dark is a flat charcoal bar.")
    api:AddSlider("Card height", 62, 80, 1, function()
        return db.cardHeight or 64
    end, function(value)
        db.cardHeight = math.floor((tonumber(value) or 64) + 0.5)
        Apply("cardHeight")
    end)
    api:AddSlider("Card scale", 0.75, 1.5, 0.05, function()
        return db.scale or 1
    end, function(value)
        local n = tonumber(value) or 1
        db.scale = math.floor((n * 100) + 0.5) / 100
        Apply("scale")
    end, "Scales the XP/rep card and the separate stats box.")
    api:AddSlider("Card width", 660, 1200, 10, function()
        return db.width or 720
    end, function(value)
        db.width = math.floor((tonumber(value) or 720) + 0.5)
        if FBT.RestoreCardPosition then
            FBT:RestoreCardPosition()
        end
        Apply("width")
    end)

    api:AddSection("Lock & Expansion")
    Bool("isLocked", "Lock XP/rep card", "Prevents resizing. Unlock Frames in /xius still moves it.")
    Bool("panelLocked", "Lock separate stats box", "Prevents resizing on the detached stats box.")
    api:AddDropdown("Expansion direction", GROWTH_DIRECTION_ITEMS, function()
        if db.growthDirection == "UP" or db.growthDirection == "DOWN" then
            return db.growthDirection
        end
        return "AUTO"
    end, function(value)
        db.growthDirection = value
        Apply("growthDirection")
    end, "Auto chooses up or down based on the card's position on screen.")

    api:AddSection("Separate Stats Box")
    api:AddCheckbox("Use separate always-visible stats box", function()
        return db.statsDisplayMode == "SEPARATE"
    end, function(value)
        db.statsDisplayMode = value and "SEPARATE" or "EMBEDDED"
        Apply("statsDisplayMode")
        RefreshPage()
    end, "Detaches session stats into a standalone movable box instead of expanding on the card.")
    api:AddDropdown("Embedded expand trigger", EXPAND_TRIGGER_ITEMS, function()
        return db.expandTrigger == "CLICK" and "CLICK" or "HOVER"
    end, function(value)
        db.expandTrigger = value == "CLICK" and "CLICK" or "HOVER"
        Apply("expandTrigger")
    end, "Used when stats expand on the main card rather than in the separate box.")
    api:AddSlider("Stats box width", 280, 520, 10, function()
        return db.panelWidth or 340
    end, function(value)
        db.panelWidth = math.floor((tonumber(value) or 340) + 0.5)
        if FBT.RestorePanelPosition then
            FBT:RestorePanelPosition()
        end
        Apply("panelWidth")
    end)

    api:AddButtonGroup({
        type = "buttonGroup",
        width = 130,
        spacing = 8,
        align = "RIGHT",
        buttons = {
            {
                text = "Reset Session",
                width = 130,
                onClick = function()
                    if FBT.ResetSession then
                        FBT:ResetSession()
                    end
                end,
            },
            {
                text = "Reset Position",
                width = 130,
                onClick = function()
                    local saved = FBT.db
                    local defaults = FBT.defaults
                    if not saved or not defaults then
                        return
                    end
                    saved.point = defaults.point
                    saved.relativePoint = defaults.relativePoint
                    saved.x = defaults.x
                    saved.y = defaults.y
                    saved.width = defaults.width
                    saved.panelPoint = defaults.panelPoint
                    saved.panelRelativePoint = defaults.panelRelativePoint
                    saved.panelX = defaults.panelX
                    saved.panelY = defaults.panelY
                    saved.panelWidth = defaults.panelWidth
                    Apply()
                    if FBT.Print then
                        FBT:Print("Card and stats box restored to default positions.")
                    end
                    RefreshPage()
                end,
            },
        },
    })
end

local function BuildXPRepTab(api, db, Apply, Bool)
    local function ColorRow(label, key, fallback, tip)
        api:AddColorPicker(label, function()
            local color = db[key]
            if type(color) ~= "table" then
                return fallback[1], fallback[2], fallback[3]
            end
            return color[1] or fallback[1], color[2] or fallback[2], color[3] or fallback[3]
        end, function(r, g, b)
            local color = db[key]
            if type(color) == "table" then
                color[1], color[2], color[3] = r, g, b
            else
                db[key] = { r, g, b }
            end
            Apply(key)
        end, tip)
    end

    api:AddSection("Bars & Colors")
    Bool("showXPBar", "Show XP bar", "Hides at max level when the reputation bar is shown.")
    Bool("showRepBar", "Show reputation bar", "Displays your watched faction; used as the main bar at max level.")
    ColorRow("Experience bar color", "xpColor", FBT.defaults.xpColor)
    ColorRow("Rested XP bar color", "restedColor", FBT.defaults.restedColor)
    ColorRow("Reputation bar color", "repColor", FBT.defaults.repColor)

    api:AddSection("Automatic Faction Reputation Tracking")
    Bool("autoTrackRep", "Auto-track a faction when its reputation goes up", "Automatically switches your watched reputation bar to whichever faction just gained reputation.")
    Bool("autoTrackRepIgnoreExalted", "Ignore factions already at Exalted / Max", "Keeps your current watched bar instead of switching to an already-capped faction.")
    Bool("autoTrackRepOnlyOutOfCombat", "Only switch watched faction out of combat", "Waits until combat ends before auto-switching your watched reputation bar.")

    api:AddSection("Instance Run Timer")
    Bool("resetInstanceTimerOnEnter", "Restart instance timer on each new entry / reset", "Starts a fresh INSTANCE TIME clock whenever you enter a different dungeon, raid, or soft-reset instance.")

    api:AddSection("Session Stats Display")
    api:AddNote("Disabled metrics hide in the stats area (card or separate box). All are on by default.")
    for i = 1, #TRACKED_STATS do
        Bool(TRACKED_STATS[i][1], TRACKED_STATS[i][2])
    end

    api:AddButtonGroup({
        type = "buttonGroup",
        width = 150,
        spacing = 8,
        align = "RIGHT",
        buttons = {
            {
                text = "Reset Session",
                width = 130,
                onClick = function()
                    if FBT.ResetSession then
                        FBT:ResetSession()
                    end
                end,
            },
            {
                text = "Reset Career History",
                width = 160,
                onClick = function()
                    if FBT.ResetCareerStats then
                        FBT:ResetCareerStats()
                    end
                end,
            },
        },
    })
end

Lib:RegisterModule({
    id = "XPRep",
    title = "Xius XP/Rep Tracker",
    menuTitle = "XP & Rep",
    group = "HUD & Combat",
    order = 20,
    noCache = true,
    hidePageTitle = true,
    activeSubTab = "general",
    subTabs = SUB_TABS,
    slashCommands = { "/xt", "/xiusxp", "/xxp", "/xrep", "/xxr" },
    defaults = FBT.defaults,
    getDB = function()
        return FBT.db
    end,
    onResetDefaults = function()
        local db = FBT.db
        local defaults = FBT.defaults
        if type(db) ~= "table" or type(defaults) ~= "table" then
            return
        end
        for key, value in pairs(defaults) do
            db[key] = CopyDefault(value)
        end
        if FBT.NotifySettingsChanged then
            FBT:NotifySettingsChanged()
        end
        if FBT.Print then
            FBT:Print("Settings restored to defaults.")
        end
    end,
    onUnlock = function(unlocked)
        if FBT.SetFrameMovers then
            FBT:SetFrameMovers(unlocked and true or false)
        end
    end,
    onUnlockFrames = function()
        if FBT.SetFrameMovers then
            FBT:SetFrameMovers(true)
        end
    end,
    buildContent = function(_, api, spec)
        local db = FBT.db
        if not db then
            api:AddNote("XP and reputation is still loading. Close this window and open it again.")
            return
        end

        local function Apply(key)
            if FBT.NotifySettingsChanged then
                FBT:NotifySettingsChanged(key)
            elseif FBT.ApplySettings then
                FBT:ApplySettings(key)
            end
        end

        local function Bool(key, label, tip)
            api:AddCheckbox(label, function()
                return db[key] and true or false
            end, function(value)
                db[key] = value and true or false
                Apply(key)
                if value and (key == "isLocked" or key == "panelLocked") then
                    if FBT.SetFrameMovers then
                        FBT:SetFrameMovers(false)
                    end
                    if Lib.NoteFramesLocked then
                        Lib:NoteFramesLocked()
                    end
                end
            end, tip)
        end

        local subTab = (spec and spec.activeSubTab) or "general"
        if subTab == "xprep" then
            BuildXPRepTab(api, db, Apply, Bool)
        else
            BuildGeneralTab(api, db, Apply, Bool)
        end
    end,
})
