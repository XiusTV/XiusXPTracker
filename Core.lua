--[[
    Xius XP/Rep Tracker - Core.lua
    Unified HUD card: header + expanding stats, session engine, Blizzard bar replacement.
]]

local ADDON, FBT = ...

local CARD_WIDTH = 620
local HEIGHT_COLLAPSED = 48
local HEIGHT_EXPANDED = 165
local PAD = 8
local BADGE_SIZE = 32
local XP_BAR_H = 8
local REP_BAR_H = 6
local ANIM_SPEED = 12
local HOVER_HIDE_DELAY = 0.3
local KILL_SAMPLE_SIZE = 5
local MIN_WIDTH = 600
local MAX_WIDTH = 1200
local NUM_COLUMNS = 5
local LEFT_MARGIN = 12
local RIGHT_MARGIN = 12

local COLOR = {
    bg = { 0.07, 0.07, 0.08, 0.94 },
    border = { 0.65, 0.52, 0.28, 0.9 },
    gold = { 0.90, 0.78, 0.40 },
    goldDim = { 0.65, 0.52, 0.28 },
    muted = { 0.72, 0.70, 0.66 },
    label = { 0.55, 0.50, 0.38 },
    value = { 0.96, 0.96, 0.96 },
    xp = { 0.541, 0.169, 0.886 }, -- #8A2BE2
    rest = { 0.898, 0.663, 0.235 }, -- #E5A93C
    rep = { 0.36, 0.70, 0.92 },
    trough = { 0.10, 0.10, 0.11, 1 },
    footer = { 0.4, 0.4, 0.4 },
    good = { 0.45, 0.85, 0.50 },
    bad = { 0.90, 0.35, 0.32 },
}

local EXALTED_REMAINING_FROM_STANDING = {
    [1] = 36000 + 3000 + 3000 + 3000 + 6000 + 12000 + 21000,
    [2] = 3000 + 3000 + 3000 + 6000 + 12000 + 21000,
    [3] = 3000 + 3000 + 6000 + 12000 + 21000,
    [4] = 3000 + 6000 + 12000 + 21000,
    [5] = 6000 + 12000 + 21000,
    [6] = 12000 + 21000,
    [7] = 21000,
    [8] = 0,
}

local BLIZZARD_BAR_NAMES = {
    "StatusTrackingBarManager",
    "MainStatusTrackingBarManager",
    "MainStatusTrackingBarContainer",
    "SecondaryStatusTrackingBarContainer",
    "MainStatusTrackingBar",
    "MainMenuExpBar",
    "ReputationWatchBar",
    "HonorWatchBar",
    "ArtifactWatchBar",
    "ExhaustionTick",
    "ExhaustionLevelFillBar",
    "MainMenuBarExpText",
    "MainMenuBarMaxLevelBar",
    "MainMenuBarOverlayFrame",
}

local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local ui = {}
local session = {
    killXP = {},
    xpEarned = 0,
    startingRep = 0,
    startMoney = 0,
}
local hideToken = 0
local ticker
local watchedCache
local watchedCacheTime = 0
local LayoutStatsGrid

local function Clamp(v, minV, maxV)
    if v < minV then
        return minV
    end
    if v > maxV then
        return maxV
    end
    return v
end

local function Round(n)
    if not n then
        return 0
    end
    if n >= 0 then
        return math.floor(n + 0.5)
    end
    return math.ceil(n - 0.5)
end

local function FormatNumber(n)
    n = Round(n or 0)
    local sign = ""
    if n < 0 then
        sign = "-"
        n = -n
    end
    local s = tostring(n)
    while true do
        local k
        s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        if k == 0 then
            break
        end
    end
    return sign .. s
end

local function FormatCompact(n)
    n = n or 0
    local sign = n < 0 and "-" or ""
    n = math.abs(n)
    if n >= 1000000 then
        return sign .. string.format("%.1fm", n / 1000000)
    end
    if n >= 1000 then
        return sign .. string.format("%.1fk", n / 1000)
    end
    return sign .. tostring(Round(n))
end

local function FormatClock(seconds)
    if not seconds or seconds < 0 or seconds == math.huge then
        return "--"
    end
    seconds = Round(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h > 1 then
        return string.format("%d hrs %d Min", h, m)
    end
    if h == 1 then
        return string.format("1 hr %d Min", m)
    end
    if m > 0 then
        local s = seconds % 60
        if s > 0 and m < 3 then
            return string.format("%d Min %d sec", m, s)
        end
        return string.format("%d Min", m)
    end
    return string.format("%d sec", seconds % 60)
end

local function FormatPercent(current, maxValue)
    if not maxValue or maxValue <= 0 then
        return "0.0%"
    end
    return string.format("%.1f%%", (current / maxValue) * 100)
end

local function CoinString(copper)
    copper = math.abs(Round(copper or 0))
    if GetCoinTextureString then
        return GetCoinTextureString(copper, 12)
    end
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(copper, 12)
    end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return string.format("%dg %ds %dc", g, s, c)
end

local function FormatGoldValue(copper)
    local amount = Round(copper or 0)
    if amount > 0 then
        return "+" .. CoinString(amount)
    end
    if amount < 0 then
        return "-" .. CoinString(amount)
    end
    return CoinString(0)
end

local function GetPlayerMaxLevel()
    if GetMaxLevelForPlayerExpansion then
        return GetMaxLevelForPlayerExpansion()
    end
    if GetMaxLevelForLatestExpansion then
        return GetMaxLevelForLatestExpansion()
    end
    return MAX_PLAYER_LEVEL or 70
end

local function IsPlayerMaxLevel()
    return UnitLevel("player") >= GetPlayerMaxLevel()
end

local function StandingName(reaction)
    return _G["FACTION_STANDING_LABEL" .. tostring(reaction or 4)] or "Unknown"
end

local function ApplyFriendship(info)
    if not info or not info.factionID then
        return info
    end
    local gossip = C_GossipInfo
    if not (gossip and gossip.GetFriendshipReputation) then
        return info
    end
    local friend = gossip.GetFriendshipReputation(info.factionID)
    if not friend or (friend.friendshipFactionID or 0) == 0 then
        return info
    end
    info.isFriendship = true
    info.rankName = friend.reaction or info.rankName
    info.maxRep = friend.maxRep
    local standing = friend.standing or info.currentStanding
    local thresh = friend.reactionThreshold or 0
    local nextT = friend.nextThreshold or 0
    info.currentStanding = standing
    if nextT == 0 then
        info.currentReactionThreshold = thresh
        info.nextReactionThreshold = math.max(standing, thresh)
        info.isMaxRank = true
    else
        info.currentReactionThreshold = thresh
        info.nextReactionThreshold = nextT
        info.isMaxRank = false
    end
    return info
end

local function ApplyMajorFaction(info)
    if not info or not info.factionID then
        return info
    end
    local MF = C_MajorFactions
    if not (MF and MF.GetMajorFactionData) then
        return info
    end
    local data = MF.GetMajorFactionData(info.factionID)
    if not data then
        return info
    end
    info.isMajorFaction = true
    info.renownLevel = data.renownLevel or 0
    info.maxRenownLevel = data.maxRenownLevel or 0
    if MF.GetCurrentRenownLevel and info.renownLevel == 0 then
        info.renownLevel = MF.GetCurrentRenownLevel(info.factionID) or info.renownLevel
    end
    info.currentStanding = data.renownReputationEarned or 0
    info.currentReactionThreshold = 0
    info.nextReactionThreshold = data.renownLevelThreshold or 1
    info.rankName = "Renown " .. tostring(info.renownLevel)
    if MF.HasMaximumRenown then
        info.isMaxRank = MF.HasMaximumRenown(info.factionID) and true or false
    else
        info.isMaxRank = info.maxRenownLevel > 0 and info.renownLevel >= info.maxRenownLevel
    end
    return info
end

local function ApplyParagon(info)
    if not info or not info.factionID then
        return info
    end
    local R = C_Reputation
    if not (R and R.IsFactionParagon and R.GetFactionParagonInfo) then
        return info
    end
    if not R.IsFactionParagon(info.factionID) then
        return info
    end
    local currentValue, threshold = R.GetFactionParagonInfo(info.factionID)
    if not currentValue or not threshold or threshold <= 0 then
        return info
    end
    info.isParagon = true
    info.rankName = "Paragon"
    info.currentStanding = currentValue % threshold
    info.currentReactionThreshold = 0
    info.nextReactionThreshold = threshold
    info.isMaxRank = false
    return info
end

function FBT:GetWatchedFaction(force)
    local now = GetTime()
    if not force and watchedCache and (now - watchedCacheTime) < 0.2 then
        return watchedCache
    end
    local info
    local R = C_Reputation
    if R and R.GetWatchedFactionData then
        local data = R.GetWatchedFactionData()
        if data and data.name then
            info = {
                name = data.name,
                factionID = data.factionID,
                reaction = data.reaction or 4,
                currentStanding = data.currentStanding or 0,
                currentReactionThreshold = data.currentReactionThreshold or 0,
                nextReactionThreshold = data.nextReactionThreshold or 0,
            }
        end
    end
    if info then
        info.rankName = StandingName(info.reaction)
        ApplyFriendship(info)
        ApplyMajorFaction(info)
        ApplyParagon(info)
        if info.nextReactionThreshold <= info.currentReactionThreshold then
            info.nextReactionThreshold = info.currentReactionThreshold + 1
            info.isMaxRank = true
        end
    end
    watchedCache = info
    watchedCacheTime = now
    return info
end

local function RemainingToNextRank(info)
    if not info or info.isMaxRank then
        return 0
    end
    return math.max(0, (info.nextReactionThreshold or 0) - (info.currentStanding or 0))
end

local function RemainingToMax(info)
    if not info then
        return 0, "Max"
    end
    if info.isFriendship then
        if info.maxRep and info.maxRep > 0 then
            return math.max(0, info.maxRep - (info.currentStanding or 0)), "Best Friend"
        end
        return RemainingToNextRank(info), "Best Friend"
    end
    if info.isMajorFaction then
        local level = info.renownLevel or 0
        local maxLevel = info.maxRenownLevel or 0
        local thresh = info.nextReactionThreshold or 0
        local earned = info.currentStanding or 0
        if info.isMaxRank or (maxLevel > 0 and level >= maxLevel) then
            return 0, "Max Renown"
        end
        local remain = math.max(0, thresh - earned)
        if maxLevel > level then
            remain = remain + math.max(0, maxLevel - level - 1) * thresh
        end
        return remain, "Max Renown"
    end
    if info.isParagon then
        return RemainingToNextRank(info), "Paragon"
    end
    if (info.reaction or 4) >= 8 then
        return 0, "Exalted"
    end
    return RemainingToNextRank(info) + (EXALTED_REMAINING_FROM_STANDING[(info.reaction or 4) + 1] or 0), "Exalted"
end

local function RatePerHour(gained, elapsed)
    if not elapsed or elapsed <= 0 then
        return 0
    end
    return (gained / elapsed) * 3600
end

local function TimeFromRate(remaining, perHour)
    if not perHour or perHour <= 0 or not remaining or remaining <= 0 then
        return nil
    end
    return (remaining / perHour) * 3600
end

local function AverageKillXP()
    local list = session.killXP
    if not list or #list == 0 then
        return 0
    end
    local total = 0
    for i = 1, #list do
        total = total + list[i]
    end
    return total / #list
end

local function AddKillXP(amount)
    if not amount or amount <= 0 then
        return
    end
    session.killXP = session.killXP or {}
    session.killXP[#session.killXP + 1] = amount
    if #session.killXP > KILL_SAMPLE_SIZE then
        table.remove(session.killXP, 1)
    end
end

local function ParseCombatXP(msg)
    if type(msg) ~= "string" then
        return nil
    end
    local n = msg:gsub(",", ""):match("(%d+)")
    return n and tonumber(n) or nil
end

local function SnapshotXP()
    session.lastXP = UnitXP("player") or 0
    session.lastXPMax = UnitXPMax("player") or 1
    session.lastLevel = UnitLevel("player") or 1
end

local function CacheFactionBaseline(force)
    local info = FBT:GetWatchedFaction(true)
    if not info then
        session.factionID = nil
        session.startingRep = 0
        return
    end
    if force or session.factionID ~= info.factionID then
        session.factionID = info.factionID
        session.startingRep = info.currentStanding or 0
    end
end

local function SessionElapsed()
    if not session.startTime then
        return 0
    end
    return math.max(0, GetTime() - session.startTime)
end

local function ShouldShowXP(db)
    if not db.showXPBar then
        return false
    end
    if not IsPlayerMaxLevel() then
        return true
    end
    return not db.showRepBar
end

local function ShouldShowRep(db)
    return db.showRepBar and FBT:GetWatchedFaction() ~= nil
end

local function FrameIsMouseOver(frame)
    if not frame then
        return false
    end
    if frame.IsMouseOver then
        return frame:IsMouseOver()
    end
    local left, right, bottom, top = frame:GetLeft(), frame:GetRight(), frame:GetBottom(), frame:GetTop()
    if not left then
        return false
    end
    local scale = frame:GetEffectiveScale() or 1
    local x, y = GetCursorPosition()
    x, y = x / scale, y / scale
    return x >= left and x <= right and y >= bottom and y <= top
end

local function SuppressBlizzardFrame(frame)
    if not frame then
        return
    end
    if frame.UnregisterAllEvents then
        frame:UnregisterAllEvents()
    end
    frame:Hide()
    frame:SetAlpha(0)
    if frame.EnableMouse then
        frame:EnableMouse(false)
    end
    if frame.__fbtSuppressed then
        return
    end
    frame.__fbtSuppressed = true
    hooksecurefunc(frame, "Show", function(self)
        if self.__fbtHiding then
            return
        end
        self.__fbtHiding = true
        self:Hide()
        self.__fbtHiding = false
    end)
    if frame.SetShown then
        hooksecurefunc(frame, "SetShown", function(self, shown)
            if shown and not self.__fbtHiding then
                self.__fbtHiding = true
                self:Hide()
                self.__fbtHiding = false
            end
        end)
    end
end

function FBT:HideBlizzardTrackingBars()
    for i = 1, #BLIZZARD_BAR_NAMES do
        SuppressBlizzardFrame(_G[BLIZZARD_BAR_NAMES[i]])
    end
    local manager = _G.StatusTrackingBarManager or _G.MainStatusTrackingBarManager
    if manager then
        SuppressBlizzardFrame(manager)
        manager.UpdateBarsShown = function() end
        if manager.UpdateBarTicks then
            manager.UpdateBarTicks = function() end
        end
        if manager.bars then
            for _, bar in pairs(manager.bars) do
                SuppressBlizzardFrame(bar)
            end
        end
    end
    local containers = {
        _G.MainStatusTrackingBarContainer,
        _G.SecondaryStatusTrackingBarContainer,
    }
    for i = 1, #containers do
        local container = containers[i]
        if container then
            SuppressBlizzardFrame(container)
            if container.UpdateShownState then
                container.UpdateShownState = function() end
            end
            if container.bars then
                for _, bar in pairs(container.bars) do
                    SuppressBlizzardFrame(bar)
                end
            end
        end
    end
end

local function ApplyCardBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(COLOR.bg[1], COLOR.bg[2], COLOR.bg[3], COLOR.bg[4])
    frame:SetBackdropBorderColor(COLOR.border[1], COLOR.border[2], COLOR.border[3], COLOR.border[4])
end

local function SetFont(fs, template, size, flags)
    local font = template:GetFont()
    if font then
        fs:SetFont(font, size, flags or "")
    end
end

local function CircleTex(parent, layer, size, r, g, b, a)
    local t = parent:CreateTexture(nil, layer)
    t:SetSize(size, size)
    t:SetPoint("CENTER")
    if t.SetMask then
        t:SetColorTexture(r, g, b, a)
        t:SetMask(PORTRAIT_MASK)
    else
        t:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        t:SetVertexColor(r, g, b, a)
    end
    return t
end

local function CreateThinBar(parent, height)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetHeight(height)
    holder:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    holder:SetBackdropColor(COLOR.trough[1], COLOR.trough[2], COLOR.trough[3], 1)
    holder:SetBackdropBorderColor(0.12, 0.12, 0.13, 1)

    local rest = holder:CreateTexture(nil, "ARTWORK")
    rest:SetColorTexture(COLOR.rest[1], COLOR.rest[2], COLOR.rest[3], 0.95)
    rest:Hide()

    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetFrameLevel(holder:GetFrameLevel() + 1)

    holder.bar = bar
    holder.rest = rest
    return holder
end

local function LayoutRest(holder, current, extra, maxV)
    local rest = holder.rest
    if not extra or extra <= 0 or maxV <= 0 then
        rest:Hide()
        return
    end
    local width = holder:GetWidth() - 2
    if width <= 0 then
        rest:Hide()
        return
    end
    local from = Clamp(current / maxV, 0, 1)
    local to = Clamp((current + extra) / maxV, 0, 1)
    local w = (to - from) * width
    if w < 1 then
        rest:Hide()
        return
    end
    rest:ClearAllPoints()
    rest:SetPoint("TOPLEFT", holder, "TOPLEFT", 1 + from * width, -1)
    rest:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 1 + from * width, 1)
    rest:SetWidth(w)
    rest:Show()
end

local function MakeStat(parent)
    local f = CreateFrame("Frame", nil, parent)
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetWordWrap(false)
    if label.SetMaxLines then
        label:SetMaxLines(1)
    end
    label:SetTextColor(COLOR.label[1], COLOR.label[2], COLOR.label[3], 1)
    SetFont(label, GameFontNormalSmall, 10)
    local value = f:CreateFontString(nil, "OVERLAY")
    value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    value:SetJustifyH("LEFT")
    value:SetJustifyV("TOP")
    value:SetWordWrap(false)
    if value.SetMaxLines then
        value:SetMaxLines(1)
    end
    SetFont(value, GameFontHighlightSmall, 12, "OUTLINE")
    value:SetTextColor(COLOR.value[1], COLOR.value[2], COLOR.value[3], 1)
    f.label = label
    f.value = value
    f:SetHeight(30)
    return f
end

local function SetStat(stat, label, value, shown, color)
    if not shown then
        stat:Hide()
        return
    end
    stat.label:SetText(label)
    stat.value:SetText(value)
    if color then
        stat.value:SetTextColor(color[1], color[2], color[3], 1)
    else
        stat.value:SetTextColor(COLOR.value[1], COLOR.value[2], COLOR.value[3], 1)
    end
    stat:Show()
end

function FBT:ResolveGrowthDirection()
    local mode = self.db and self.db.growthDirection or "AUTO"
    if mode == "UP" or mode == "DOWN" then
        return mode
    end
    local card = ui.card
    if not card then
        return "UP"
    end
    local _, centerY = card:GetCenter()
    if not centerY then
        return "UP"
    end
    if centerY < (GetScreenHeight() * 0.5) then
        return "UP"
    end
    return "DOWN"
end

function FBT:UpdateFrameOrientation(resolvedDirection)
    local card = ui.card
    local header = ui.header
    local stats = ui.stats
    if not card or not header or not stats then
        return
    end
    resolvedDirection = resolvedDirection or self:ResolveGrowthDirection()
    ui.growUp = (resolvedDirection == "UP")
    ui.resolvedDirection = resolvedDirection

    local left, right, top, bottom = card:GetLeft(), card:GetRight(), card:GetTop(), card:GetBottom()
    if left and right and top and bottom then
        local currentCenterX = (left + right) / 2
        card:ClearAllPoints()
        if ui.growUp then
            card:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", currentCenterX, bottom)
        else
            card:SetPoint("TOP", UIParent, "BOTTOMLEFT", currentCenterX, top)
        end
    end

    header:ClearAllPoints()
    stats:ClearAllPoints()
    if ui.growUp then
        header:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 8)
        header:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 8)
        stats:SetPoint("BOTTOMLEFT", header, "TOPLEFT", 0, 10)
        stats:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -10)
    else
        header:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
        header:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -8)
        stats:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
        stats:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 10)
    end

    if ui.badge then
        ui.badge:ClearAllPoints()
        if ui.growUp then
            ui.badge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
        else
            ui.badge:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
        end
    end
    if ui.barColumn then
        ui.barColumn:ClearAllPoints()
        if ui.growUp then
            ui.barColumn:SetPoint("BOTTOMLEFT", ui.badge or header, "BOTTOMRIGHT", 10, 0)
        else
            ui.barColumn:SetPoint("TOPLEFT", ui.badge or header, "TOPRIGHT", 10, 0)
        end
        ui.barColumn:SetPoint("RIGHT", header, "RIGHT", 0, 0)
        ui.barColumn:SetPoint("TOP", header, "TOP", 0, 0)
        ui.barColumn:SetPoint("BOTTOM", header, "BOTTOM", 0, 0)
    end
    if ui.grip then
        ui.grip:ClearAllPoints()
        ui.grip:SetPoint("RIGHT", header, "RIGHT", 4, 0)
    end
    LayoutStatsGrid()
end

local function SavePosition()
    local db, card = FBT.db, ui.card
    if not db or not card then
        return
    end
    local point, _, relativePoint, x, y = card:GetPoint(1)
    db.point = point or "BOTTOM"
    db.relativePoint = relativePoint or "BOTTOMLEFT"
    db.x = x or 0
    db.y = y or 0
    db.width = math.max(MIN_WIDTH, Round(card:GetWidth()))
end

local function ApplyPosition()
    local db, card = FBT.db, ui.card
    card:ClearAllPoints()
    card:SetPoint(db.point or "BOTTOM", UIParent, db.relativePoint or "BOTTOM", db.x or 0, db.y or 0)
    card:SetWidth(math.max(MIN_WIDTH, Clamp(db.width or CARD_WIDTH, MIN_WIDTH, MAX_WIDTH)))
end

function LayoutStatsGrid()
    local card, grid, cols = ui.card, ui.grid, ui.statCols
    if not card or not grid or not cols then
        return
    end
    local availWidth = math.max(1, card:GetWidth() - (LEFT_MARGIN + RIGHT_MARGIN))
    local colWidth = availWidth / NUM_COLUMNS
    local textWidth = math.max(8, colWidth - 8)
    for i = 0, NUM_COLUMNS - 1 do
        local col = cols[i + 1]
        if col then
            local x = (LEFT_MARGIN - PAD) + (i * colWidth)
            col:ClearAllPoints()
            col:SetPoint("TOPLEFT", grid, "TOPLEFT", x, 0)
            col:SetPoint("BOTTOM", grid, "BOTTOM", 0, 0)
            col:SetWidth(textWidth)
            local pair = { col.statTop, col.statBottom }
            for s = 1, #pair do
                local stat = pair[s]
                if stat then
                    stat:SetWidth(textWidth)
                    stat.label:SetWidth(textWidth)
                    stat.value:SetWidth(textWidth)
                    stat.label:SetJustifyH("LEFT")
                    stat.value:SetJustifyH("LEFT")
                    stat.label:SetWordWrap(false)
                    stat.value:SetWordWrap(false)
                end
            end
        end
    end
end

local function SetStatsInteractive(enabled)
    if ui.resetBtn then
        ui.resetBtn:EnableMouse(enabled)
    end
end

local function AnimOnUpdate(self, elapsed)
    if ui.sizing then
        if not IsMouseButtonDown("LeftButton") then
            ui.sizing = false
            SavePosition()
        else
            local x = GetCursorPosition()
            local width = Clamp(ui.sizeStartW + ((x - ui.sizeStartX) / ui.sizeScale), MIN_WIDTH, MAX_WIDTH)
            self:SetWidth(width)
            FBT.db.width = math.max(MIN_WIDTH, Round(width))
            FBT:RefreshHeader()
            LayoutStatsGrid()
        end
    end

    local current = ui.currentHeight
    local target = ui.targetHeight
    local factor = math.min(1, (elapsed or 0) * ANIM_SPEED)
    if math.abs(target - current) <= 0.35 then
        ui.currentHeight = target
        self:SetHeight(target)
    else
        ui.currentHeight = current + (target - current) * factor
        self:SetHeight(ui.currentHeight)
    end

    local progress = Clamp((ui.currentHeight - HEIGHT_COLLAPSED) / (HEIGHT_EXPANDED - HEIGHT_COLLAPSED), 0, 1)
    ui.stats:SetAlpha(progress)
    if progress <= 0.02 then
        if ui.stats:IsShown() then
            ui.stats:Hide()
        end
        SetStatsInteractive(false)
    else
        if not ui.stats:IsShown() then
            ui.stats:Show()
        end
        SetStatsInteractive(progress > 0.65)
    end

    if (not ui.sizing) and math.abs(ui.currentHeight - ui.targetHeight) <= 0.35 then
        ui.currentHeight = ui.targetHeight
        self:SetHeight(ui.targetHeight)
        self:SetScript("OnUpdate", nil)
    end
end

local function EnsureAnim()
    ui.card:SetScript("OnUpdate", AnimOnUpdate)
end

function FBT:SetExpanded(expanded)
    ui.expanded = expanded and true or false
    ui.targetHeight = ui.expanded and HEIGHT_EXPANDED or HEIGHT_COLLAPSED
    if ui.expanded then
        ui.stats:Show()
        self:RefreshStats()
    end
    EnsureAnim()
end

function FBT:ToggleExpanded()
    self:SetExpanded(not ui.expanded)
end

function FBT:IsHoverOverUI()
    return ui.card and FrameIsMouseOver(ui.card)
end

function FBT:ScheduleCollapse()
    hideToken = hideToken + 1
    local token = hideToken
    C_Timer.After(HOVER_HIDE_DELAY, function()
        if token ~= hideToken then
            return
        end
        if not self.db or self.db.expandTrigger ~= "HOVER" then
            return
        end
        if self:IsHoverOverUI() then
            return
        end
        self:SetExpanded(false)
    end)
end

function FBT:RefreshHeader()
    if not ui.card or not self.db then
        return
    end
    local db = self.db
    ui.levelText:SetText(tostring(UnitLevel("player") or 0))

    local showXP = ShouldShowXP(db)
    local info = self:GetWatchedFaction()
    local showRep = ShouldShowRep(db)

    if showXP then
        local current = UnitXP("player") or 0
        local maxXP = UnitXPMax("player") or 1
        if maxXP <= 0 then
            maxXP = 1
        end
        ui.leftLabel:SetFormattedText("Experience  %s / %s", FormatNumber(current), FormatNumber(maxXP))
        ui.rightPct:SetText(FormatPercent(current, maxXP))
        ui.xpBar:Show()
        ui.xpBar.bar:SetMinMaxValues(0, maxXP)
        ui.xpBar.bar:SetValue(IsPlayerMaxLevel() and maxXP or current)
        ui.xpBar.bar:SetStatusBarColor(COLOR.xp[1], COLOR.xp[2], COLOR.xp[3], 1)
        if IsPlayerMaxLevel() then
            ui.xpBar.rest:Hide()
            ui.leftLabel:SetText("Experience  Max Level")
            ui.rightPct:SetText("100%")
        else
            LayoutRest(ui.xpBar, current, GetXPExhaustion and GetXPExhaustion() or 0, maxXP)
        end
    elseif showRep and info then
        local cur = (info.currentStanding or 0) - (info.currentReactionThreshold or 0)
        local maxV = (info.nextReactionThreshold or 0) - (info.currentReactionThreshold or 0)
        if maxV <= 0 then
            maxV = 1
            cur = 1
        end
        cur = Clamp(cur, 0, maxV)
        ui.leftLabel:SetFormattedText("%s  %s / %s", info.name or "Reputation", FormatNumber(cur), FormatNumber(maxV))
        ui.rightPct:SetText(FormatPercent(cur, maxV))
        ui.xpBar:Show()
        ui.xpBar.bar:SetMinMaxValues(0, maxV)
        ui.xpBar.bar:SetValue(cur)
        ui.xpBar.bar:SetStatusBarColor(COLOR.rep[1], COLOR.rep[2], COLOR.rep[3], 1)
        ui.xpBar.rest:Hide()
        showRep = false
    else
        ui.leftLabel:SetText("Experience")
        ui.rightPct:SetText("--")
        ui.xpBar.bar:SetValue(0)
        ui.xpBar.rest:Hide()
    end

    if showRep and info and showXP then
        local cur = (info.currentStanding or 0) - (info.currentReactionThreshold or 0)
        local maxV = (info.nextReactionThreshold or 0) - (info.currentReactionThreshold or 0)
        if maxV <= 0 then
            maxV = 1
            cur = 1
        end
        cur = Clamp(cur, 0, maxV)
        ui.repBar:Show()
        ui.repBar.bar:SetMinMaxValues(0, maxV)
        ui.repBar.bar:SetValue(cur)
        ui.repBar.bar:SetStatusBarColor(COLOR.rep[1], COLOR.rep[2], COLOR.rep[3], 1)
        ui.xpBar:ClearAllPoints()
        ui.xpBar:SetPoint("TOPLEFT", ui.leftLabel, "BOTTOMLEFT", 0, -3)
        ui.xpBar:SetPoint("RIGHT", ui.barColumn, "RIGHT", 0, 0)
        ui.repBar:ClearAllPoints()
        ui.repBar:SetPoint("TOPLEFT", ui.xpBar, "BOTTOMLEFT", 0, -3)
        ui.repBar:SetPoint("RIGHT", ui.barColumn, "RIGHT", 0, 0)
    else
        ui.repBar:Hide()
        ui.xpBar:ClearAllPoints()
        ui.xpBar:SetPoint("TOPLEFT", ui.leftLabel, "BOTTOMLEFT", 0, -4)
        ui.xpBar:SetPoint("RIGHT", ui.barColumn, "RIGHT", 0, 0)
    end
end

function FBT:RefreshStats()
    if not ui.stats or not self.db then
        return
    end
    LayoutStatsGrid()
    local db = self.db
    local elapsed = SessionElapsed()
    local xpPerHour = RatePerHour(session.xpEarned or 0, elapsed)
    local goldDelta = (GetMoney() or 0) - (session.startMoney or 0)
    local goldPerHour = RatePerHour(goldDelta, elapsed)
    local currentXP = UnitXP("player") or 0
    local maxXP = UnitXPMax("player") or 1
    local xpLeft = math.max(0, maxXP - currentXP)
    local ttl = TimeFromRate(xpLeft, xpPerHour)
    local avgKill = AverageKillXP()
    local ktl = "--"
    if not IsPlayerMaxLevel() and avgKill > 0 and xpLeft > 0 then
        ktl = tostring(math.ceil(xpLeft / avgKill))
    elseif IsPlayerMaxLevel() then
        ktl = "Max"
    end
    local restXP = GetXPExhaustion and GetXPExhaustion() or 0
    local restText = "0 (0%)"
    if restXP and restXP > 0 and maxXP > 0 then
        restText = string.format("%s (%s)", FormatCompact(restXP), FormatPercent(restXP, maxXP))
    end
    local sessionXPText = string.format("%s / %s", FormatCompact(session.xpEarned or 0), FormatCompact(xpLeft))

    SetStat(ui.statSessionXP, "SESSION XP", sessionXPText, true, COLOR.value)
    SetStat(ui.statSessionTime, "SESSION TIME", FormatClock(elapsed), db.showSessionTime, COLOR.value)
    SetStat(ui.statRested, "RESTED", IsPlayerMaxLevel() and "Max" or restText, db.showRested, COLOR.rest)
    SetStat(ui.statTTL, "TIME TO LEVEL", IsPlayerMaxLevel() and "Max" or FormatClock(ttl), db.showTTL, COLOR.gold)
    SetStat(ui.statXPHour, "XP / HOUR", IsPlayerMaxLevel() and "--" or FormatCompact(xpPerHour), db.showXPHour, COLOR.value)
    SetStat(ui.statKTL, "KILLS TO LEVEL", ktl, db.showKTL, COLOR.value)

    SetStat(ui.statGoldHour, "GOLD / HOUR", FormatGoldValue(goldPerHour), db.showGoldHour, goldPerHour < 0 and COLOR.bad or COLOR.gold)
    SetStat(ui.statGoldSess, "SESSION GOLD", FormatGoldValue(goldDelta), db.showGoldSession, goldDelta < 0 and COLOR.bad or COLOR.gold)

    local info = self:GetWatchedFaction()
    if info then
        local sessionRep = (info.currentStanding or 0) - (session.startingRep or 0)
        local repPerHour = RatePerHour(sessionRep, elapsed)
        local nextRemain = RemainingToNextRank(info)
        SetStat(ui.statRepHour, "REP / HOUR", sessionRep > 0 and FormatCompact(repPerHour) or "--", db.showRepHour, COLOR.rep)
        SetStat(ui.statNextRank, "NEXT RANK", info.isMaxRank and "Max" or FormatClock(TimeFromRate(nextRemain, repPerHour)), db.showRepNextRank, COLOR.rep)
    else
        SetStat(ui.statRepHour, "REP / HOUR", "--", db.showRepHour, COLOR.rep)
        SetStat(ui.statNextRank, "NEXT RANK", "--", db.showRepNextRank, COLOR.rep)
    end

    if db.expandTrigger == "CLICK" then
        ui.footer:SetText("[Shift + Drag to Move | Click to Toggle]")
    else
        ui.footer:SetText("[Shift + Drag to Move | Hover to Expand]")
    end
end

function FBT:Refresh()
    self:HideBlizzardTrackingBars()
    self:RefreshHeader()
    if ui.expanded or (ui.stats and ui.stats:IsShown()) then
        self:RefreshStats()
    end
end

function FBT:ApplySettings()
    if not ui.card or not self.db then
        return
    end
    ApplyPosition()
    self:UpdateFrameOrientation(self:ResolveGrowthDirection())
    if self.db.expandTrigger == "HOVER" and not self:IsHoverOverUI() then
        self:SetExpanded(false)
    end
    self:Refresh()
end

function FBT:ToggleLock()
    local db = self.db
    if not db then
        return
    end
    db.isLocked = not db.isLocked
    if ui.grip then
        ui.grip:SetShown(not db.isLocked)
    end
    self:ApplySettings()
    if db.isLocked then
        self:Print("Card locked.")
    else
        self:Print("Card unlocked. Shift-drag to move.")
    end
end

function FBT:ResetSession()
    session.startTime = GetTime()
    session.xpEarned = 0
    session.killXP = {}
    session.startMoney = GetMoney() or 0
    SnapshotXP()
    CacheFactionBaseline(true)
    self:Print("Session timers, XP, gold, and reputation baselines have been reset.")
    self:Refresh()
end

function FBT:StartSession()
    self:HideBlizzardTrackingBars()
    if session.active then
        CacheFactionBaseline(false)
        SnapshotXP()
        self:Refresh()
        return
    end
    session.active = true
    session.startTime = GetTime()
    session.xpEarned = 0
    session.killXP = {}
    session.startMoney = GetMoney() or 0
    SnapshotXP()
    CacheFactionBaseline(true)
    if ticker then
        ticker:Cancel()
    end
    ticker = C_Timer.NewTicker(1.0, function()
        if ui.expanded then
            FBT:RefreshStats()
        end
    end)
    self:Refresh()
end

local function OnCardEnter()
    local db = FBT.db
    if not db or db.expandTrigger ~= "HOVER" then
        return
    end
    hideToken = hideToken + 1
    FBT:SetExpanded(true)
end

local function OnCardLeave()
    local db = FBT.db
    if not db or db.expandTrigger ~= "HOVER" then
        return
    end
    FBT:ScheduleCollapse()
end

local function OnCardMouseDown(_, button)
    local db = FBT.db
    if not db or button ~= "LeftButton" then
        return
    end
    if ui.resetBtn and FrameIsMouseOver(ui.resetBtn) then
        return
    end
    if ui.grip and ui.grip:IsShown() and FrameIsMouseOver(ui.grip) then
        return
    end
    if not db.isLocked and IsShiftKeyDown() then
        ui.moving = true
        ui.card:StartMoving()
        return
    end
    if db.expandTrigger == "CLICK" then
        FBT:ToggleExpanded()
    end
end

local function OnCardDragStop()
    if not ui.moving then
        return
    end
    ui.moving = false
    ui.card:StopMovingOrSizing()
    FBT:UpdateFrameOrientation(FBT:ResolveGrowthDirection())
    SavePosition()
end

local function OnCardMouseUp(_, button)
    if button == "LeftButton" then
        OnCardDragStop()
    end
end

function FBT:CreateUI()
    if ui.card then
        return
    end

    local card = CreateFrame("Frame", "XiusXPRepTrackerFrame", UIParent, "BackdropTemplate")
    card:SetSize(CARD_WIDTH, HEIGHT_COLLAPSED)
    card:SetFrameStrata("MEDIUM")
    card:SetFrameLevel(80)
    card:SetClampedToScreen(true)
    card:SetMovable(true)
    card:SetResizable(true)
    if card.SetResizeBounds then
        card:SetResizeBounds(MIN_WIDTH, HEIGHT_COLLAPSED, MAX_WIDTH, 200)
    else
        if card.SetMinResize then
            card:SetMinResize(MIN_WIDTH, HEIGHT_COLLAPSED)
        end
        if card.SetMaxResize then
            card:SetMaxResize(MAX_WIDTH, 200)
        end
    end
    card:EnableMouse(true)
    if card.SetClipsChildren then
        card:SetClipsChildren(true)
    end
    if card.SetDontSavePosition then
        card:SetDontSavePosition(true)
    end
    ApplyCardBackdrop(card)

    local header = CreateFrame("Frame", nil, card)
    header:SetPoint("TOPLEFT", PAD, -PAD)
    header:SetPoint("TOPRIGHT", -PAD, -PAD)
    header:SetHeight(BADGE_SIZE)

    local badge = CreateFrame("Frame", nil, header)
    badge:SetSize(BADGE_SIZE, BADGE_SIZE)
    badge:SetPoint("LEFT", 0, 0)
    CircleTex(badge, "BACKGROUND", BADGE_SIZE, COLOR.goldDim[1], COLOR.goldDim[2], COLOR.goldDim[3], 1)
    CircleTex(badge, "BORDER", BADGE_SIZE - 3, 0.08, 0.08, 0.09, 1)
    CircleTex(badge, "ARTWORK", BADGE_SIZE - 7, COLOR.gold[1], COLOR.gold[2], COLOR.gold[3], 0.95)
    CircleTex(badge, "OVERLAY", BADGE_SIZE - 11, 0.09, 0.09, 0.10, 1)
    local levelText = badge:CreateFontString(nil, "OVERLAY")
    levelText:SetPoint("CENTER", 0, 0)
    SetFont(levelText, GameFontNormalLarge, 13, "OUTLINE")
    levelText:SetTextColor(1, 0.95, 0.75, 1)
    levelText:SetText("1")

    local barColumn = CreateFrame("Frame", nil, header)
    barColumn:SetPoint("LEFT", badge, "RIGHT", 10, 0)
    barColumn:SetPoint("RIGHT", header, "RIGHT", 0, 0)
    barColumn:SetPoint("TOP", header, "TOP", 0, 0)
    barColumn:SetPoint("BOTTOM", header, "BOTTOM", 0, 0)

    local leftLabel = barColumn:CreateFontString(nil, "OVERLAY")
    leftLabel:SetPoint("TOPLEFT", 0, -1)
    SetFont(leftLabel, GameFontHighlightSmall, 11)
    leftLabel:SetTextColor(COLOR.muted[1], COLOR.muted[2], COLOR.muted[3], 1)
    leftLabel:SetJustifyH("LEFT")
    leftLabel:SetText("Experience")

    local rightPct = barColumn:CreateFontString(nil, "OVERLAY")
    rightPct:SetPoint("TOPRIGHT", 0, -1)
    SetFont(rightPct, GameFontNormalSmall, 11, "OUTLINE")
    rightPct:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3], 1)
    rightPct:SetJustifyH("RIGHT")
    rightPct:SetText("0.0%")
    leftLabel:SetPoint("RIGHT", rightPct, "LEFT", -8, 0)

    local xpBar = CreateThinBar(barColumn, XP_BAR_H)
    xpBar:SetPoint("TOPLEFT", leftLabel, "BOTTOMLEFT", 0, -4)
    xpBar:SetPoint("RIGHT", barColumn, "RIGHT", 0, 0)
    xpBar.bar:SetStatusBarColor(COLOR.xp[1], COLOR.xp[2], COLOR.xp[3], 1)

    local repBar = CreateThinBar(barColumn, REP_BAR_H)
    repBar:SetPoint("TOPLEFT", xpBar, "BOTTOMLEFT", 0, -3)
    repBar:SetPoint("RIGHT", barColumn, "RIGHT", 0, 0)
    repBar.bar:SetStatusBarColor(COLOR.rep[1], COLOR.rep[2], COLOR.rep[3], 1)
    repBar:Hide()

    local stats = CreateFrame("Frame", "XiusXPRepTrackerStats", card)
    stats:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    stats:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -PAD, PAD)
    stats:SetAlpha(0)
    stats:Hide()

    local resetBtn = CreateFrame("Button", nil, stats, "BackdropTemplate")
    resetBtn:SetSize(108, 18)
    resetBtn:SetPoint("TOPLEFT", 0, 0)
    resetBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    resetBtn:SetBackdropColor(0.12, 0.10, 0.07, 0.95)
    resetBtn:SetBackdropBorderColor(COLOR.border[1], COLOR.border[2], COLOR.border[3], 0.95)
    local resetText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetText:SetPoint("CENTER", 0, 0)
    SetFont(resetText, GameFontNormalSmall, 10)
    resetText:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3], 1)
    resetText:SetText("Reset Session")
    resetBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.16, 0.08, 1)
        OnCardEnter()
    end)
    resetBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.10, 0.07, 0.95)
        OnCardLeave()
    end)
    resetBtn:SetScript("OnClick", function()
        FBT:ResetSession()
    end)
    resetBtn:EnableMouse(false)

    local grid = CreateFrame("Frame", nil, stats)
    grid:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 0, -8)
    grid:SetPoint("BOTTOMRIGHT", stats, "BOTTOMRIGHT", 0, 16)

    local cols = {}
    for i = 1, NUM_COLUMNS do
        cols[i] = CreateFrame("Frame", nil, grid)
        cols[i]:SetHeight(64)
    end
    ui.grid = grid
    ui.statCols = cols
    grid:SetScript("OnSizeChanged", function()
        LayoutStatsGrid()
    end)

    local function PlacePair(col, top, bottom)
        top:SetParent(col)
        bottom:SetParent(col)
        top:ClearAllPoints()
        bottom:ClearAllPoints()
        top:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0)
        top:SetPoint("RIGHT", col, "RIGHT", 0, 0)
        bottom:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -6)
        bottom:SetPoint("RIGHT", col, "RIGHT", 0, 0)
        col.statTop = top
        col.statBottom = bottom
    end

    local statSessionXP = MakeStat(cols[1])
    local statSessionTime = MakeStat(cols[1])
    PlacePair(cols[1], statSessionXP, statSessionTime)

    local statRested = MakeStat(cols[2])
    local statTTL = MakeStat(cols[2])
    PlacePair(cols[2], statRested, statTTL)

    local statXPHour = MakeStat(cols[3])
    local statKTL = MakeStat(cols[3])
    PlacePair(cols[3], statXPHour, statKTL)

    local statGoldHour = MakeStat(cols[4])
    local statGoldSess = MakeStat(cols[4])
    PlacePair(cols[4], statGoldHour, statGoldSess)

    local statRepHour = MakeStat(cols[5])
    local statNextRank = MakeStat(cols[5])
    PlacePair(cols[5], statRepHour, statNextRank)

    local footer = stats:CreateFontString(nil, "OVERLAY")
    footer:SetPoint("BOTTOM", stats, "BOTTOM", 0, 0)
    SetFont(footer, GameFontDisableSmall, 9)
    footer:SetTextColor(COLOR.footer[1], COLOR.footer[2], COLOR.footer[3], 1)
    footer:SetText("[Shift + Drag to Move | Click to Toggle]")

    local grip = CreateFrame("Frame", nil, card)
    grip:SetSize(8, 20)
    grip:SetPoint("RIGHT", card, "RIGHT", 0, 0)
    grip:EnableMouse(true)
    grip:SetFrameLevel(card:GetFrameLevel() + 5)
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetColorTexture(COLOR.goldDim[1], COLOR.goldDim[2], COLOR.goldDim[3], 0.25)
    gripTex:SetAllPoints()
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or (FBT.db and FBT.db.isLocked) then
            return
        end
        ui.sizing = true
        ui.sizeStartX = GetCursorPosition()
        ui.sizeStartW = card:GetWidth()
        ui.sizeScale = card:GetEffectiveScale() or 1
        EnsureAnim()
    end)
    grip:SetScript("OnEnter", OnCardEnter)
    grip:SetScript("OnLeave", OnCardLeave)

    ui.card = card
    ui.header = header
    ui.badge = badge
    ui.levelText = levelText
    ui.barColumn = barColumn
    ui.leftLabel = leftLabel
    ui.rightPct = rightPct
    ui.xpBar = xpBar
    ui.repBar = repBar
    ui.stats = stats
    ui.resetBtn = resetBtn
    ui.statSessionXP = statSessionXP
    ui.statSessionTime = statSessionTime
    ui.statRested = statRested
    ui.statTTL = statTTL
    ui.statXPHour = statXPHour
    ui.statKTL = statKTL
    ui.statGoldHour = statGoldHour
    ui.statGoldSess = statGoldSess
    ui.statRepHour = statRepHour
    ui.statNextRank = statNextRank
    ui.footer = footer
    ui.grip = grip
    ui.expanded = false
    ui.currentHeight = HEIGHT_COLLAPSED
    ui.targetHeight = HEIGHT_COLLAPSED
    ui.growUp = true

    card:SetScript("OnEnter", OnCardEnter)
    card:SetScript("OnLeave", OnCardLeave)
    card:SetScript("OnMouseDown", OnCardMouseDown)
    card:SetScript("OnMouseUp", OnCardMouseUp)
    stats:SetScript("OnEnter", OnCardEnter)
    stats:SetScript("OnLeave", OnCardLeave)

    ApplyPosition()
    self:UpdateFrameOrientation(self:ResolveGrowthDirection())
    LayoutStatsGrid()
    card:SetScript("OnSizeChanged", function()
        LayoutStatsGrid()
    end)
    if ui.grip then
        ui.grip:SetShown(not (self.db and self.db.isLocked))
    end
    self:HideBlizzardTrackingBars()
    self:Refresh()
end

local function OnXPUpdate()
    if not session.active then
        return
    end
    local xp = UnitXP("player") or 0
    local level = UnitLevel("player") or 1
    local maxXP = UnitXPMax("player") or 1
    if level > (session.lastLevel or level) then
        session.xpEarned = (session.xpEarned or 0) + math.max(0, (session.lastXPMax or 0) - (session.lastXP or 0)) + xp
    elseif xp > (session.lastXP or 0) then
        session.xpEarned = (session.xpEarned or 0) + (xp - session.lastXP)
    end
    session.lastXP = xp
    session.lastLevel = level
    session.lastXPMax = maxXP
    FBT:Refresh()
end

function FBT:RegisterTracking()
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_XP_UPDATE")
    f:RegisterEvent("PLAYER_LEVEL_UP")
    f:RegisterEvent("UPDATE_FACTION")
    f:RegisterEvent("PLAYER_MONEY")
    f:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_UPDATE_RESTING")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
            OnXPUpdate()
        elseif event == "UPDATE_FACTION" then
            watchedCache = nil
            CacheFactionBaseline(false)
            FBT:Refresh()
        elseif event == "PLAYER_MONEY" then
            if ui.expanded then
                FBT:RefreshStats()
            end
        elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
            local amount = ParseCombatXP(...)
            if amount then
                AddKillXP(amount)
                if ui.expanded then
                    FBT:RefreshStats()
                end
            end
        elseif event == "PLAYER_UPDATE_RESTING" then
            FBT:Refresh()
        elseif event == "PLAYER_ENTERING_WORLD" then
            FBT:HideBlizzardTrackingBars()
            FBT:StartSession()
        end
    end)
    self.eventFrame = f
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        FBT:InitDB()
        FBT:CreateOptions()
        FBT:CreateUI()
        FBT:RegisterTracking()
        FBT:HideBlizzardTrackingBars()
        if IsLoggedIn and IsLoggedIn() then
            FBT:StartSession()
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
