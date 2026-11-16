local _, FBT = ...

local XiusCore = _G.XiusCore or _G.XiusUI or _G.XiusCoreSettingsLib
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

local function RefreshPage()
    if not Lib.ShowPage or Lib._building then
        return
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            Lib:ShowPage("XPRep")
        end)
    else
        Lib:ShowPage("XPRep")
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

Lib:RegisterModule({
    id = "XPRep",
    title = "Xius XP/Rep Tracker",
    menuTitle = "XP & Rep",
    group = "HUD & Combat",
    order = 20,
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
    buildContent = function(_, api)
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

        local function Bool(key, label)
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
            end)
        end

        api:AddNote("Replaces the default XP/rep bar with a movable HUD card. Unlock Frames in /xius drags it. Shift-drag still works while the card lock is off.")

        api:AddSection("Card")
        Bool("enabled", "Enable XP and reputation card")
        api:AddDropdown("Bar style", {
            { value = "blizzard", text = "Blizzard Modern" },
            { value = "minimal", text = "Minimal Dark" },
        }, function()
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
        Bool("autoTrackRep", "Auto-track a faction when its reputation goes up")

        api:AddSection("Stats Display")
        api:AddCheckbox("Show stats on XP/rep card", function()
            return db.statsDisplayMode ~= "SEPARATE"
        end, function()
            db.statsDisplayMode = "EMBEDDED"
            Apply("statsDisplayMode")
            RefreshPage()
        end, "Displays detailed XP/rep stats on the main card on hover or click.")
        api:AddCheckbox("Show separate always-visible stats box", function()
            return db.statsDisplayMode == "SEPARATE"
        end, function()
            db.statsDisplayMode = "SEPARATE"
            Apply("statsDisplayMode")
            RefreshPage()
        end, "Detaches stats into a standalone movable box that stays visible.")

        api:AddSection("Card Expansion")
        api:AddCheckbox("Expand card on mouseover", function()
            return db.expandTrigger ~= "CLICK"
        end, function()
            db.expandTrigger = "HOVER"
            Apply("expandTrigger")
            RefreshPage()
        end, "Automatically expands the stats panel while hovering over the card.")
        api:AddCheckbox("Expand card on click", function()
            return db.expandTrigger == "CLICK"
        end, function()
            db.expandTrigger = "CLICK"
            Apply("expandTrigger")
            RefreshPage()
        end, "Toggles the expanded stats panel when clicking the card.")

        api:AddSection("Expansion Direction")
        api:AddDropdown("Expansion direction", {
            { value = "AUTO", text = "Auto (Screen Position)" },
            { value = "UP", text = "Always Expand Up" },
            { value = "DOWN", text = "Always Expand Down" },
        }, function()
            if db.growthDirection == "UP" or db.growthDirection == "DOWN" then
                return db.growthDirection
            end
            return "AUTO"
        end, function(value)
            db.growthDirection = value
            Apply("growthDirection")
        end)
        api:AddNote("Auto uses the card's position on screen.")

        api:AddSection("Bars & Position")
        Bool("isLocked", "Lock XP/rep card (prevents Shift-drag and resizing)")
        Bool("panelLocked", "Lock separate stats box")
        Bool("showXPBar", "Show XP bar (hides at max level if reputation is shown)")
        Bool("showRepBar", "Show reputation bar (watched faction; used at max level)")
        api:AddSlider("Card width", 660, 1200, 10, function()
            return db.width or 720
        end, function(value)
            db.width = math.floor((tonumber(value) or 720) + 0.5)
            if FBT.RestoreCardPosition then
                FBT:RestoreCardPosition()
            end
            Apply("width")
        end)
        api:AddSlider("Stats box width", 280, 520, 10, function()
            return db.panelWidth or 340
        end, function(value)
            db.panelWidth = math.floor((tonumber(value) or 340) + 0.5)
            if FBT.RestorePanelPosition then
                FBT:RestorePanelPosition()
            end
            Apply("panelWidth")
        end)

        api:AddSection("Loot, Vendors, and Training")
        api:AddNote("Faster loot, selling gray items, repair, Train All, and max-rank action bars are on the Quality of Life page. Xius Core runs them.")

        api:AddSection("Tracked Stats")
        api:AddNote("Disabled metrics hide in the stats area (card or separate box). All are on by default.")
        local tracked = {
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
        for i = 1, #tracked do
            Bool(tracked[i][1], tracked[i][2])
        end

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
    end,
})

function FBT:OpenOptions()
    if InCombatLockdown and InCombatLockdown() then
        if self.Print then
            self:Print("Cannot open settings during combat.")
        end
        return
    end
    if Lib.OpenModule then
        Lib:OpenModule("XPRep")
        if C_Timer and C_Timer.After and FBT.NudgePanelClearOfOptions then
            C_Timer.After(0, function()
                FBT:NudgePanelClearOfOptions()
            end)
        elseif FBT.NudgePanelClearOfOptions then
            FBT:NudgePanelClearOfOptions()
        end
        return
    end
    if Lib.Open then
        Lib:Open("XPRep")
    end
end
