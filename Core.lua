--[[
    Xius XP/Rep Tracker - Core.lua
    Unified HUD card: header + expanding stats (or separate stats box),
    session engine, Blizzard bar replacement.
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

local CARD_WIDTH = 720
local HEIGHT_COLLAPSED = 64
local HEIGHT_EXPANDED = 181
local PANEL_WIDTH = 340
local PANEL_HEIGHT = 282
local PANEL_MIN_WIDTH = 280
local PANEL_MAX_WIDTH = 520
local PAD = 8
local BADGE_SIZE = 36
local HEADER_H = 46
local XP_BAR_H = 14
local REP_BAR_H = 12
local ANIM_SPEED = 12
local HOVER_HIDE_DELAY = 0.3
local KILL_SAMPLE_SIZE = 5
local QUEST_SAMPLE_SIZE = 5
local MIN_WIDTH = 660
local MAX_WIDTH = 1200
local STATS_EXTRA = HEIGHT_EXPANDED - HEIGHT_COLLAPSED

local function CardCollapsedHeight()
    local h = HEIGHT_COLLAPSED
    if FBT.db and type(FBT.db.cardHeight) == "number" then
        h = FBT.db.cardHeight
    end
    if h < 62 then
        return 62
    end
    if h > 80 then
        return 80
    end
    return h
end

local function CardExpandedHeight()
    return CardCollapsedHeight() + STATS_EXTRA
end

local function SavedColor(saved, fallback)
    if type(saved) ~= "table" then
        return fallback[1], fallback[2], fallback[3]
    end
    local r = tonumber(saved[1])
    local g = tonumber(saved[2])
    local b = tonumber(saved[3])
    if not r or not g or not b then
        return fallback[1], fallback[2], fallback[3]
    end
    return r, g, b
end
local NUM_COLUMNS = 8
local PANEL_COLUMNS = 3
local LEFT_MARGIN = 10
local RIGHT_MARGIN = 10
local CAREER_IDLE_THRESHOLD = 120

local COLOR = {
    bg = { 0.06, 0.06, 0.08, 0.92 },
    border = { 1.0, 0.82, 0.35, 1 },
    gold = { 1, 209 / 255, 0 },
    label = { 154 / 255, 161 / 255, 178 / 255 },
    value = { 1, 1, 1 },
    xp = { 122 / 255, 50 / 255, 201 / 255 },
    rest = { 31 / 255, 139 / 255, 255 },
    rep = { 0.36, 0.70, 0.92 },
    trough = { 9 / 255, 10 / 255, 12 / 255, 0.85 },
    trim = { 122 / 255, 99 / 255, 50 / 255, 1 },
    bad = { 0.90, 0.35, 0.32 },
    btn = { 24 / 255, 25 / 255, 29 / 255, 1 },
    btnHover = { 0.16, 0.14, 0.08, 1 },
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

-- Only the dedicated XP/rep tracking bars. Do not touch MainMenuBar overlay
-- frames or Edit Mode systems (PlayerFrame, Damage Meter) or taint spreads.
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
}

local ui = {}
local session = {
    killXP = {},
    questXP = {},
    avgKillXP = 0,
    avgQuestXP = 0,
    xpEarned = 0,
    startingRep = 0,
    startMoney = 0,
    lastInstanceID = nil,
    instanceStartTime = nil,
    inInstance = false,
}
local hideToken = 0
local factionStanding = {}
local factionScanReady = false
local ticker
local watchedCache
local watchedCacheValid = false
local watchedCacheTime = 0
local watchedInfoTable = {}
local LayoutStatsGrid
local EnsureAnim
local OnXPUpdate
local FactionBarValues
local OnCardEnter
local OnCardLeave
local OnCardDragStop
local OnPanelDragStop
local OpenSettingsFromUI
local refreshQueued = false
local pendingLayout = false
local refreshHeader = false
local refreshStats = false
local playedLastRequest = 0
local suppressedChatFrames = {}
local RequestPlayedTime
local RestorePlayedChatFrames
local careerLastTickAt = 0
local careerLastActivityAt = 0
local careerPaceDirty = true
local cachedCareerRate = 0
local cachedCareerLevels = 0

local function ValueHidden(v)
    if v == nil then
        return false
    end
    -- Forever can throw from secret APIs; treat failure as hidden so XP/rep
    -- math never operates on restricted combat numbers.
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then
            return true
        end
    end
    if canaccessvalue then
        local ok, allowed = pcall(canaccessvalue, v)
        if not ok or not allowed then
            return true
        end
    end
    return false
end

local function PublicNumber(v, fallback)
    if ValueHidden(v) then
        if fallback == nil then
            return 0
        end
        return fallback
    end
    if type(v) ~= "number" then
        if fallback == nil then
            return 0
        end
        return fallback
    end
    return v
end

local function PublicString(v, fallback)
    if ValueHidden(v) then
        return fallback
    end
    if type(v) ~= "string" then
        return fallback
    end
    return v
end

local function Clamp(v, minV, maxV)
    v = PublicNumber(v, minV)
    if v < minV then
        return minV
    end
    if v > maxV then
        return maxV
    end
    return v
end

local function Round(n)
    n = PublicNumber(n, 0)
    if n >= 0 then
        return math.floor(n + 0.5)
    end
    return math.ceil(n - 0.5)
end

local function FormatNumber(n)
    n = Round(n)
    if n == 0 then
        return "0"
    end
    local sign = ""
    if n < 0 then
        sign = "-"
        n = -n
    end
    if n < 1000 then
        return sign .. tostring(n)
    end
    if n < 1000000 then
        return string.format("%s%d,%03d", sign, math.floor(n / 1000), n % 1000)
    end
    if n < 1000000000 then
        return string.format(
            "%s%d,%03d,%03d",
            sign,
            math.floor(n / 1000000),
            math.floor((n % 1000000) / 1000),
            n % 1000
        )
    end
    return sign .. tostring(n)
end

local function FormatCompact(n)
    n = PublicNumber(n, 0)
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

local function FormatPlayedClock(seconds)
    if not seconds or seconds < 0 or seconds == math.huge then
        return "--"
    end
    seconds = Round(seconds)
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if d > 1 then
        return string.format("%dd %d hr", d, h)
    end
    if d == 1 then
        return string.format("1d %d hr", h)
    end
    return FormatClock(seconds)
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

local cachedMaxLevel

local function SafeUnitLevel(unit)
    if not UnitLevel or unit == nil then
        return nil
    end
    local ok, level = pcall(UnitLevel, unit)
    if not ok then
        return nil
    end
    return level
end

local function GetPlayerMaxLevel()
    if cachedMaxLevel then
        return cachedMaxLevel
    end
    -- Forever can expose retail expansion helpers that return 70/80 while
    -- MAX_PLAYER_LEVEL / GetMaxPlayerLevel stay at the real Forever cap (60).
    -- Prefer the smallest positive candidate so max-level rep fallback still runs.
    local fallback = PublicNumber(MAX_PLAYER_LEVEL, 60)
    local best = nil
    local function consider(raw)
        if ValueHidden(raw) or type(raw) ~= "number" then
            return
        end
        local n = PublicNumber(raw, 0)
        if n > 0 and (not best or n < best) then
            best = n
        end
    end
    if GetMaxPlayerLevel then
        local ok, value = pcall(GetMaxPlayerLevel)
        if ok then
            consider(value)
        end
    end
    consider(fallback)
    if GetMaxLevelForPlayerExpansion then
        local ok, value = pcall(GetMaxLevelForPlayerExpansion)
        if ok then
            consider(value)
        end
    end
    if GetMaxLevelForLatestExpansion then
        local ok, value = pcall(GetMaxLevelForLatestExpansion)
        if ok then
            consider(value)
        end
    end
    if best and best > 0 then
        -- Only cache once the player is already at the candidate, or when
        -- GetMaxPlayerLevel / MAX_PLAYER_LEVEL agreed on a Forever-scale cap.
        local playerLevel = PublicNumber(SafeUnitLevel("player"), 1)
        if best <= 70 or playerLevel >= best or best == fallback then
            cachedMaxLevel = best
        end
        return best
    end
    return fallback
end

local function IsPlayerMaxLevel()
    return PublicNumber(SafeUnitLevel("player"), 1) >= GetPlayerMaxLevel()
end

local function InvalidateMaxLevelCache()
    cachedMaxLevel = nil
end

local function IsSeparateStatsMode()
    return FBT.db and FBT.db.statsDisplayMode == "SEPARATE"
end

local STANDING_FALLBACK = {
    [1] = "Hated",
    [2] = "Hostile",
    [3] = "Unfriendly",
    [4] = "Neutral",
    [5] = "Friendly",
    [6] = "Honored",
    [7] = "Revered",
    [8] = "Exalted",
}

local STANDING_CODES = {
    [1] = "HAT",
    [2] = "HOS",
    [3] = "UNF",
    [4] = "NEU",
    [5] = "FRD",
    [6] = "HON",
    [7] = "REV",
    [8] = "EXA",
}

local STANDING_COLOR_FALLBACK = {
    [1] = { 0.80, 0.13, 0.13 },
    [2] = { 1.00, 0.00, 0.00 },
    [3] = { 0.93, 0.40, 0.13 },
    [4] = { 1.00, 1.00, 0.00 },
    [5] = { 0.00, 0.60, 0.00 },
    [6] = { 0.00, 0.60, 0.00 },
    [7] = { 0.00, 0.60, 0.00 },
    [8] = { 0.00, 0.60, 0.80 },
}

local function StandingName(reaction)
    local idx = PublicNumber(reaction, 4)
    local label = PublicString(_G["FACTION_STANDING_LABEL" .. tostring(idx)], nil)
    return label or STANDING_FALLBACK[idx] or "Unknown"
end

local function StandingCode(info)
    if not info then
        return "REP"
    end
    if info.isParagon then
        return "PAR"
    end
    if info.isMajorFaction and info.renownLevel then
        return "R" .. tostring(info.renownLevel)
    end
    local idx = Clamp(PublicNumber(info.reaction, 4), 1, 8)
    return STANDING_CODES[idx] or "NEU"
end

local function StandingColor(reaction)
    local idx = Clamp(PublicNumber(reaction, 4), 1, 8)
    local colors = _G.FACTION_BAR_COLORS
    if type(colors) == "table" and type(colors[idx]) == "table" then
        local c = colors[idx]
        local r = PublicNumber(c.r, nil)
        local g = PublicNumber(c.g, nil)
        local b = PublicNumber(c.b, nil)
        if r and g and b then
            return r, g, b
        end
    end
    local fb = STANDING_COLOR_FALLBACK[idx] or STANDING_COLOR_FALLBACK[4]
    return fb[1], fb[2], fb[3]
end

local function ApplyFriendship(info)
    if not info or not info.factionID or info.factionID <= 0 then
        return info
    end
    local friend
    local gossip = C_GossipInfo
    if gossip and gossip.GetFriendshipReputation then
        local ok, result = pcall(gossip.GetFriendshipReputation, info.factionID)
        if ok and not (ValueHidden(result)) and type(result) == "table" then
            friend = result
        end
    end
    if not friend then
        local rep = C_Reputation
        if rep and rep.GetFriendshipReputation then
            local ok, result = pcall(rep.GetFriendshipReputation, info.factionID)
            if ok and not (ValueHidden(result)) and type(result) == "table" then
                friend = result
            end
        end
    end
    if not friend then
        return info
    end
    if PublicNumber(friend.friendshipFactionID, 0) == 0 then
        return info
    end
    info.isFriendship = true
    local friendReaction = PublicString(friend.reaction, nil)
    if friendReaction and friendReaction ~= "" then
        info.rankName = friendReaction
    end
    info.maxRep = PublicNumber(friend.maxRep, info.maxRep or 0)
    local standing = PublicNumber(friend.standing, info.currentStanding)
    local thresh = PublicNumber(friend.reactionThreshold, 0)
    local nextT = PublicNumber(friend.nextThreshold, 0)
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
    if not info or not info.factionID or info.factionID <= 0 then
        return info
    end
    if C_Reputation and C_Reputation.IsMajorFaction then
        local okMajor, isMajor = pcall(C_Reputation.IsMajorFaction, info.factionID)
        if okMajor and not (ValueHidden(isMajor)) and not isMajor then
            return info
        end
    end
    local MF = C_MajorFactions
    if not (MF and MF.GetMajorFactionData) then
        return info
    end
    local okData, data = pcall(MF.GetMajorFactionData, info.factionID)
    if not okData or (ValueHidden(data)) or type(data) ~= "table" then
        return info
    end
    info.isMajorFaction = true
    info.renownLevel = PublicNumber(data.renownLevel, 0)
    info.maxRenownLevel = PublicNumber(data.maxRenownLevel, 0)
    if MF.GetCurrentRenownLevel and info.renownLevel == 0 then
        local okLevel, lvl = pcall(MF.GetCurrentRenownLevel, info.factionID)
        if okLevel then
            info.renownLevel = PublicNumber(lvl, info.renownLevel)
        end
    end
    local earned = PublicNumber(data.renownReputationEarned, 0)
    local thresh = PublicNumber(data.renownLevelThreshold, 1)
    if thresh <= 0 then
        thresh = 1
    end
    info.currentStanding = earned
    -- Renown earned resets each level. Keep a monotonic value for session delta.
    info.absoluteStanding = (info.renownLevel * thresh) + earned
    info.currentReactionThreshold = 0
    info.nextReactionThreshold = thresh
    info.rankName = "Renown " .. tostring(info.renownLevel)
    if MF.HasMaximumRenown then
        local okMax, maxed = pcall(MF.HasMaximumRenown, info.factionID)
        if okMax and not (ValueHidden(maxed)) then
            info.isMaxRank = maxed and true or false
        else
            info.isMaxRank = info.maxRenownLevel > 0 and info.renownLevel >= info.maxRenownLevel
        end
    else
        info.isMaxRank = info.maxRenownLevel > 0 and info.renownLevel >= info.maxRenownLevel
    end
    return info
end

local function ApplyParagon(info)
    if not info or not info.factionID or info.factionID <= 0 then
        return info
    end
    local R = C_Reputation
    if not (R and R.IsFactionParagon and R.GetFactionParagonInfo) then
        return info
    end
    local okParagon, isParagon = pcall(R.IsFactionParagon, info.factionID)
    if not okParagon or (ValueHidden(isParagon)) or not isParagon then
        return info
    end
    local okInfo, currentValue, threshold = pcall(R.GetFactionParagonInfo, info.factionID)
    if not okInfo then
        return info
    end
    if ValueHidden(currentValue) or ValueHidden(threshold) then
        return info
    end
    if type(currentValue) ~= "number" or type(threshold) ~= "number" or threshold <= 0 then
        return info
    end
    info.isParagon = true
    info.rankName = "Paragon"
    info.absoluteStanding = currentValue
    info.currentStanding = currentValue % threshold
    info.currentReactionThreshold = 0
    info.nextReactionThreshold = threshold
    -- Paragon is post-Exalted: treat as max standing so AUTO can pick another faction.
    info.isMaxRank = true
    return info
end

local function RepTrackMode(info)
    if not info then
        return nil
    end
    if info.isParagon then
        return "paragon"
    end
    if info.isMajorFaction then
        return "major"
    end
    if info.isFriendship then
        return "friend"
    end
    return "standard"
end

local function RepTrackValue(info)
    if not info then
        return 0
    end
    return info.absoluteStanding or info.currentStanding or 0
end

local function PopulateWatchedTable(name, factionID, reaction, standing, minThreshold, maxThreshold)
    local t = watchedInfoTable
    t.name = name
    t.factionID = factionID
    t.reaction = reaction
    t.currentStanding = standing
    t.currentReactionThreshold = minThreshold
    t.nextReactionThreshold = maxThreshold
    t.rankName = StandingName(reaction)
    t.isFriendship = false
    t.isMajorFaction = false
    t.isParagon = false
    t.isMaxRank = false
    t.maxRep = nil
    t.renownLevel = nil
    t.maxRenownLevel = nil
    t.absoluteStanding = nil
    return t
end

function FBT:GetWatchedFaction(force)
    local now = GetTime()
    if not force and watchedCacheValid and (now - watchedCacheTime) < 3.0 then
        return watchedCache
    end
    local info
    local R = C_Reputation
    if R and R.GetWatchedFactionData then
        local ok, data = pcall(R.GetWatchedFactionData)
        if ok and not (ValueHidden(data)) and type(data) == "table" then
            local name = PublicString(data.name, nil)
            local factionID = PublicNumber(data.factionID, 0)
            local maxT = PublicNumber(data.nextReactionThreshold, 0)
            if name and name ~= "" and (factionID > 0 or maxT > 0) then
                info = PopulateWatchedTable(
                    name,
                    factionID,
                    PublicNumber(data.reaction, 4),
                    PublicNumber(data.currentStanding, 0),
                    PublicNumber(data.currentReactionThreshold, 0),
                    maxT
                )
            end
        end
    end
    if not info and GetWatchedFactionInfo then
        local ok, name, reaction, minBar, maxBar, value, factionID = pcall(GetWatchedFactionInfo)
        if ok then
            name = PublicString(name, nil)
            if name and name ~= "" then
                info = PopulateWatchedTable(
                    name,
                    PublicNumber(factionID, 0),
                    PublicNumber(reaction, 4),
                    PublicNumber(value, 0),
                    PublicNumber(minBar, 0),
                    PublicNumber(maxBar, 0)
                )
            end
        end
    end
    if info then
        ApplyFriendship(info)
        ApplyMajorFaction(info)
        ApplyParagon(info)
        if info.nextReactionThreshold <= info.currentReactionThreshold then
            info.nextReactionThreshold = info.currentReactionThreshold + 1
            info.isMaxRank = true
        elseif not info.isParagon and not info.isFriendship and not info.isMajorFaction and (info.reaction or 4) >= 8 and info.currentStanding >= info.nextReactionThreshold then
            info.isMaxRank = true
        end
    end
    watchedCache = info
    watchedCacheValid = true
    watchedCacheTime = now
    return info
end

local factionScanPool = {}
local factionScanCount = 0

local function GetFactionCount()
    if C_Reputation and C_Reputation.GetNumFactions then
        local ok, count = pcall(C_Reputation.GetNumFactions)
        if ok and type(count) == "number" and not ValueHidden(count) then
            return count
        end
    end
    if GetNumFactions then
        local ok, count = pcall(GetNumFactions)
        if ok and type(count) == "number" and not ValueHidden(count) then
            return count
        end
    end
    return 0
end

local function IsFactionRowInactive(index)
    if C_Reputation and C_Reputation.IsFactionInactive then
        local ok, inactive = pcall(C_Reputation.IsFactionInactive, index)
        if ok and not ValueHidden(inactive) and inactive then
            return true
        end
    elseif IsFactionInactive then
        local ok, inactive = pcall(IsFactionInactive, index)
        if ok and not ValueHidden(inactive) and inactive then
            return true
        end
    end
    return false
end

local function SetWatchedFactionSafe(index, factionID)
    if factionID and factionID > 0 and C_Reputation and C_Reputation.SetWatchedFactionByID then
        if pcall(C_Reputation.SetWatchedFactionByID, factionID) then
            return true
        end
    end
    if SetWatchedFactionIndex and index then
        if pcall(SetWatchedFactionIndex, index) then
            return true
        end
    end
    return false
end

local function ScanActiveFactions()
    factionScanCount = 0
    local count = GetFactionCount()
    local useModern = C_Reputation and C_Reputation.GetFactionDataByIndex
    for i = 1, count do
        local name, factionID, reaction, standing, minT, maxT, isHeader, hasRep, isWatched
        if useModern then
            local okRow, data = pcall(C_Reputation.GetFactionDataByIndex, i)
            if not okRow then
                data = nil
            end
            if type(data) == "table" and not ValueHidden(data) then
                name = PublicString(data.name, nil)
                factionID = PublicNumber(data.factionID, 0)
                reaction = PublicNumber(data.reaction, 4)
                standing = PublicNumber(data.currentStanding, 0)
                minT = PublicNumber(data.currentReactionThreshold, 0)
                maxT = PublicNumber(data.nextReactionThreshold, 0)
                isHeader = (not ValueHidden(data.isHeader)) and data.isHeader and true or false
                hasRep = (not ValueHidden(data.isHeaderWithRep)) and data.isHeaderWithRep and true or false
                isWatched = (not ValueHidden(data.isWatched)) and data.isWatched and true or false
            end
        elseif GetFactionInfo then
            local n, _, standingID, barMin, barMax, barValue, _, _, hdr, _, hRep, watched, _, fID = GetFactionInfo(i)
            name = PublicString(n, nil)
            factionID = PublicNumber(fID, 0)
            reaction = PublicNumber(standingID, 4)
            standing = PublicNumber(barValue, 0)
            minT = PublicNumber(barMin, 0)
            maxT = PublicNumber(barMax, 0)
            isHeader = (not ValueHidden(hdr)) and hdr and true or false
            hasRep = (not ValueHidden(hRep)) and hRep and true or false
            isWatched = (not ValueHidden(watched)) and watched and true or false
        end
        if name and name ~= "" and (not isHeader or hasRep) and not IsFactionRowInactive(i) then
            factionScanCount = factionScanCount + 1
            local entry = factionScanPool[factionScanCount]
            if not entry then
                entry = {}
                factionScanPool[factionScanCount] = entry
            end
            entry.index = i
            entry.name = name
            entry.factionID = factionID
            entry.reaction = reaction
            entry.currentStanding = standing
            entry.currentReactionThreshold = minT
            entry.nextReactionThreshold = maxT
            entry.isWatched = isWatched
            entry.isExalted = reaction >= 8
        end
    end
    for i = factionScanCount + 1, #factionScanPool do
        factionScanPool[i] = nil
    end
    return factionScanPool, factionScanCount
end

local function FindBestNonExaltedFaction()
    local list, count = ScanActiveFactions()
    local bestNonExalted
    local bestAny
    for i = 1, count do
        local entry = list[i]
        if not bestAny or entry.reaction > bestAny.reaction or (entry.reaction == bestAny.reaction and entry.currentStanding > bestAny.currentStanding) then
            bestAny = entry
        end
        if not entry.isExalted then
            if not bestNonExalted or entry.reaction > bestNonExalted.reaction or (entry.reaction == bestNonExalted.reaction and entry.currentStanding > bestNonExalted.currentStanding) then
                bestNonExalted = entry
            end
        end
    end
    return bestNonExalted or bestAny
end

function FBT:EnsureMaxLevelReputation(forceScan)
    if not self.db then
        return nil
    end
    local atMax = IsPlayerMaxLevel()
    if not atMax and (self.db.showXPBar or not self.db.showRepBar) then
        return self:GetWatchedFaction(forceScan)
    end
    local watched = self:GetWatchedFaction(forceScan)
    local autoMode = self.db.repPickerMode ~= "MANUAL"
    local watchedExalted = watched and ((watched.reaction or 0) >= 8 or watched.isParagon)
    local needAutoPick = (watched == nil) or (autoMode and (watched.isMaxRank or watchedExalted))
    if not needAutoPick then
        return watched
    end
    local best = FindBestNonExaltedFaction()
    if not best then
        return watched
    end
    if watched and watched.factionID == best.factionID and watched.name == best.name then
        return watched
    end
    local setOk = SetWatchedFactionSafe(best.index, best.factionID)
    watchedCache = nil
    watchedCacheValid = false
    local updated = self:GetWatchedFaction(true)
    -- Only trust the watched API when the write succeeded AND the watched
    -- faction is the one we just picked (combat/API rejects leave the old Exalted watched).
    if setOk and updated and updated.factionID == best.factionID then
        return updated
    end
    -- Fallback if SetWatchedFaction was blocked or delayed: display scanned faction directly.
    local info = PopulateWatchedTable(
        best.name,
        best.factionID,
        best.reaction,
        best.currentStanding,
        best.currentReactionThreshold,
        best.nextReactionThreshold
    )
    ApplyFriendship(info)
    ApplyMajorFaction(info)
    ApplyParagon(info)
    if info.nextReactionThreshold <= info.currentReactionThreshold then
        info.nextReactionThreshold = info.currentReactionThreshold + 1
        info.isMaxRank = true
    elseif not info.isParagon and not info.isFriendship and not info.isMajorFaction
        and (info.reaction or 4) >= 8 and info.currentStanding >= info.nextReactionThreshold then
        info.isMaxRank = true
    end
    watchedCache = info
    watchedCacheValid = true
    watchedCacheTime = GetTime()
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

local function EnsureCareerTable()
    if type(ForeverBarTrackerCharDB) ~= "table" then
        ForeverBarTrackerCharDB = {}
    end
    if type(ForeverBarTrackerCharDB.careerLevelStats) ~= "table" then
        ForeverBarTrackerCharDB.careerLevelStats = {}
    end
    FBT.charDB = ForeverBarTrackerCharDB
    FBT.careerLevelStats = ForeverBarTrackerCharDB.careerLevelStats
    return ForeverBarTrackerCharDB.careerLevelStats
end

local function MarkCareerActivity()
    careerLastActivityAt = GetTime()
end

local function IsPlayerAFKOrIdle(now)
    if UnitIsAFK then
        local ok, afk = pcall(UnitIsAFK, "player")
        if ok and not ValueHidden(afk) and afk then
            return true
        end
    end
    if GetUnitSpeed then
        local ok, speed = pcall(GetUnitSpeed, "player")
        if ok and not ValueHidden(speed) and type(speed) == "number" and speed > 0 then
            careerLastActivityAt = now
            return false
        end
    end
    if IsPlayerMoving then
        local ok, moving = pcall(IsPlayerMoving)
        if ok and not ValueHidden(moving) and moving then
            careerLastActivityAt = now
            return false
        end
    end
    if careerLastActivityAt <= 0 then
        careerLastActivityAt = now
        return false
    end
    return (now - careerLastActivityAt) > CAREER_IDLE_THRESHOLD
end

local function RecordCareerXP(level, xpAmount, xpRequired)
    if not level or level <= 0 or not xpAmount or xpAmount <= 0 then
        return
    end
    local stats = EnsureCareerTable()
    local entry = stats[level]
    if type(entry) ~= "table" then
        entry = { activeTime = 0, xpGained = 0, xpRequired = xpRequired or 1 }
        stats[level] = entry
    end
    entry.xpGained = (entry.xpGained or 0) + xpAmount
    if xpRequired and xpRequired > 0 then
        entry.xpRequired = xpRequired
    end
    careerPaceDirty = true
    MarkCareerActivity()
end

local function TickCareerActiveTime()
    if not session.active or (FBT.db and FBT.db.enabled == false) or IsPlayerMaxLevel() then
        careerLastTickAt = GetTime()
        return
    end
    local now = GetTime()
    if careerLastTickAt <= 0 then
        careerLastTickAt = now
        if careerLastActivityAt <= 0 then
            careerLastActivityAt = now
        end
        return
    end
    local dt = now - careerLastTickAt
    careerLastTickAt = now
    if dt <= 0 or dt > 5 then
        return
    end
    if IsPlayerAFKOrIdle(now) then
        return
    end
    local level = PublicNumber(UnitLevel("player"), session.lastLevel or 1)
    if level <= 0 then
        return
    end
    local maxXP = PublicNumber(UnitXPMax("player"), session.lastXPMax or 1)
    if maxXP <= 0 then
        maxXP = 1
    end
    local stats = EnsureCareerTable()
    local entry = stats[level]
    if type(entry) ~= "table" then
        entry = { activeTime = 0, xpGained = 0, xpRequired = maxXP }
        stats[level] = entry
    end
    entry.activeTime = (entry.activeTime or 0) + dt
    entry.xpRequired = maxXP
    careerPaceDirty = true
end

local function ComputeCareerPace()
    if not careerPaceDirty then
        return cachedCareerRate, cachedCareerLevels
    end
    local stats = EnsureCareerTable()
    local weightedRateSum = 0
    local weightSum = 0
    local levelsCount = 0
    for _, entry in pairs(stats) do
        if type(entry) == "table" and (entry.activeTime or 0) > 0 and (entry.xpGained or 0) > 0 and (entry.xpRequired or 0) > 0 then
            local levelRatePerHour = (entry.xpGained / entry.activeTime) * 3600
            local weight = entry.xpRequired
            weightedRateSum = weightedRateSum + (levelRatePerHour * weight)
            weightSum = weightSum + weight
            levelsCount = levelsCount + 1
        end
    end
    cachedCareerLevels = levelsCount
    cachedCareerRate = weightSum > 0 and (weightedRateSum / weightSum) or 0
    careerPaceDirty = false
    return cachedCareerRate, cachedCareerLevels
end

local function ComputeOverallTTL(xpLeft, sessionXPPerHour, elapsed)
    local careerRate, levelsCount = ComputeCareerPace()
    local sessionRate = sessionXPPerHour or 0
    local blendedRate = 0
    if careerRate > 0 and sessionRate > 0 then
        local sessionWeight = Clamp((elapsed / 600) * 0.40, 0.10, 0.40)
        blendedRate = ((1 - sessionWeight) * careerRate) + (sessionWeight * sessionRate)
    elseif careerRate > 0 then
        blendedRate = careerRate
    elseif sessionRate > 0 then
        blendedRate = sessionRate
    end
    local ttl = TimeFromRate(xpLeft, blendedRate)
    return ttl, careerRate, blendedRate, levelsCount
end

function FBT:OnCareerStatsReset()
    careerLastTickAt = GetTime()
    careerLastActivityAt = GetTime()
    careerPaceDirty = true
    cachedCareerRate = 0
    cachedCareerLevels = 0
    self:RefreshStats()
end

local function RecomputeSampleAverage(list)
    if not list or #list == 0 then
        return 0
    end
    local total = 0
    for i = 1, #list do
        total = total + list[i]
    end
    return total / #list
end

local function AverageKillXP()
    return session.avgKillXP or 0
end

local function AverageQuestXP()
    return session.avgQuestXP or 0
end

local function AddKillXP(amount)
    if not amount or amount <= 0 then
        return
    end
    local list = session.killXP
    if not list then
        list = {}
        session.killXP = list
    end
    list[#list + 1] = amount
    if #list > KILL_SAMPLE_SIZE then
        table.remove(list, 1)
    end
    session.avgKillXP = RecomputeSampleAverage(list)
end

local function AddQuestXP(amount)
    if not amount or amount <= 0 then
        return
    end
    local list = session.questXP
    if not list then
        list = {}
        session.questXP = list
    end
    list[#list + 1] = amount
    if #list > QUEST_SAMPLE_SIZE then
        table.remove(list, 1)
    end
    session.avgQuestXP = RecomputeSampleAverage(list)
end

local function ParseCombatXP(msg)
    -- In WoW Forever and Modern WoW 12.x, combat XP lines from mob deaths embed the
    -- enemy's secret name, making the message a secret string. Quest XP has no mob name.
    if ValueHidden(msg) then
        return nil, true
    end
    if type(msg) ~= "string" or msg == "" then
        return nil, false
    end
    -- Skip quest/discovery XP lines ("You gain X experience.") so they never pollute KTL.
    if not string.find(msg, "dies", 1, true) and string.find(msg, "^You gain ") then
        return nil, false
    end
    local cleaned = string.find(msg, ",", 1, true) and msg:gsub(",", "") or msg
    -- Match the number preceding "experience" first so numbered mob names (e.g. "SI:7 Agent") are skipped.
    local n = cleaned:match("(%d+)%s+[Ee]xperience") or cleaned:match("(%d+)")
    return (n and tonumber(n) or nil), false
end

local function SnapshotXP()
    session.lastXP = PublicNumber(UnitXP("player"), session.lastXP or 0)
    session.lastXPMax = PublicNumber(UnitXPMax("player"), session.lastXPMax or 1)
    session.lastLevel = PublicNumber(UnitLevel("player"), session.lastLevel or 1)
end

local function CacheFactionBaseline(force)
    local info = FBT:GetWatchedFaction(true)
    -- A nil blip (loading, unwatch flicker) must not wipe the baseline.
    -- The next real read would otherwise treat current standing as the start
    -- and zero out session reputation.
    if not info then
        return
    end
    local mode = RepTrackMode(info)
    if force or session.factionID ~= info.factionID or session.repMode ~= mode then
        session.factionID = info.factionID
        session.repMode = mode
        session.startingRep = RepTrackValue(info)
    end
end

local function CurrentMoney()
    if not GetMoney then
        return nil
    end
    local ok, money = pcall(GetMoney)
    if not ok or (ValueHidden(money)) or type(money) ~= "number" then
        return nil
    end
    return money
end

local function EnsureMoneyBaseline()
    if session.moneyReady then
        return
    end
    local money = CurrentMoney()
    if money == nil then
        return
    end
    session.startMoney = money
    session.moneyReady = true
end

local function SessionElapsed()
    if not session.startTime then
        return 0
    end
    return math.max(0, GetTime() - session.startTime)
end

local function InstanceElapsed()
    if not session.instanceStartTime then
        return 0
    end
    local start = session.instanceStartTime
    if ValueHidden(start) or type(start) ~= "number" then
        return 0
    end
    return math.max(0, GetTime() - start)
end

local function SyncInstanceRunTimer()
    local db = FBT.db
    local allowRestart = not db or db.resetInstanceTimerOnEnter ~= false
    local inInstance = false
    local instType
    if IsInInstance then
        local ok, inside, itype = pcall(IsInInstance)
        -- Secret instance flags: leave the live run timer alone (do not wipe on /reload).
        if not ok or ValueHidden(inside) or ValueHidden(itype) then
            return
        end
        inInstance = inside and true or false
        instType = itype
    end
    -- Ignore open-world / none; track dungeon, raid, arena, pvp.
    if type(instType) ~= "string" then
        instType = nil
    end
    if not inInstance or instType == nil or instType == "none" then
        -- PLAYER_ENTERING_WORLD often reports outdoors during the load screen.
        -- Keep the live run clock until a delayed / instance-info confirm clears it.
        if session.instanceStartTime and not session._instanceOutdoorsConfirm then
            session._instanceOutdoorsConfirm = true
            if C_Timer and C_Timer.After then
                C_Timer.After(1.25, function()
                    session._instanceOutdoorsConfirm = nil
                    SyncInstanceRunTimer()
                end)
            end
            return
        end
        session.inInstance = false
        session.lastInstanceID = nil
        session.instanceStartTime = nil
        session._instanceOutdoorsConfirm = nil
        return
    end
    session._instanceOutdoorsConfirm = nil

    local mapID, difficultyID, name = 0, 0, nil
    if GetInstanceInfo then
        -- GetInstanceInfo: name, type, difficultyID, difficultyName, maxPlayers,
        -- dynamicDifficulty, isDynamic, instanceMapID, ...
        local ok, n, _, diff, _, _, _, _, mid = pcall(GetInstanceInfo)
        if ok then
            if not ValueHidden(n) and type(n) == "string" and n ~= "" then
                name = n
            end
            if not ValueHidden(diff) and type(diff) == "number" then
                difficultyID = diff
            end
            if not ValueHidden(mid) and type(mid) == "number" and mid > 0 then
                mapID = mid
            end
        end
    end

    -- Prefer a unique instance GUID fragment so soft-resets and chained runs get a fresh clock.
    local guidFragment
    if UnitGUID then
        local okGuid, raw = pcall(UnitGUID, "player")
        if okGuid and not ValueHidden(raw) and type(raw) == "string" then
            guidFragment = raw:match("^[^%-]+%-%d+%-%d+%-%d+%-%d+%-(%d+)")
        end
    end

    local instID
    if mapID > 0 then
        instID = tostring(mapID) .. ":" .. tostring(difficultyID)
        if guidFragment then
            instID = instID .. ":" .. guidFragment
        end
    elseif name then
        instID = name .. ":" .. tostring(difficultyID)
        if guidFragment then
            instID = instID .. ":" .. guidFragment
        end
    else
        instID = guidFragment or (tostring(instType or "instance") .. ":" .. tostring(GetTime()))
    end

    session.inInstance = true
    if allowRestart and session.lastInstanceID ~= instID then
        session.lastInstanceID = instID
        session.instanceStartTime = GetTime()
    elseif not session.instanceStartTime then
        session.lastInstanceID = instID
        session.instanceStartTime = GetTime()
    elseif not session.lastInstanceID then
        session.lastInstanceID = instID
    end
end

local function SuppressPlayedOnChatFrame(cf)
    if not cf or suppressedChatFrames[cf] or not cf.IsEventRegistered or not cf.UnregisterEvent then
        return
    end
    local ok, registered = pcall(cf.IsEventRegistered, cf, "TIME_PLAYED_MSG")
    if ok and not (ValueHidden(registered)) and registered then
        suppressedChatFrames[cf] = true
        pcall(cf.UnregisterEvent, cf, "TIME_PLAYED_MSG")
    end
end

RestorePlayedChatFrames = function()
    for cf in pairs(suppressedChatFrames) do
        suppressedChatFrames[cf] = nil
        if cf and cf.RegisterEvent then
            pcall(cf.RegisterEvent, cf, "TIME_PLAYED_MSG")
        end
    end
end

RequestPlayedTime = function(force)
    if not RequestTimePlayed then
        return
    end
    -- Only login and level-up should hit the server. Anything else ticks locally.
    if not force then
        return
    end
    local now = GetTime()
    if (now - playedLastRequest) < 2.0 then
        return
    end
    playedLastRequest = now
    -- Temporarily unregister TIME_PLAYED_MSG on chat frames rather than hooking
    -- ChatFrame_DisplayTimePlayed or modifying ChatFrameUtil (which taints SecureCmdUseItem).
    local maxWindows = PublicNumber(NUM_CHAT_WINDOWS, 10)
    for i = 1, maxWindows do
        SuppressPlayedOnChatFrame(_G["ChatFrame" .. i])
    end
    SuppressPlayedOnChatFrame(DEFAULT_CHAT_FRAME)
    if C_Timer and C_Timer.After then
        C_Timer.After(3.0, RestorePlayedChatFrames)
    end
    pcall(RequestTimePlayed)
end

local function PlayedSinceSnapshot(base)
    if base == nil or not session.playedStamp then
        return nil
    end
    return base + math.max(0, GetTime() - session.playedStamp)
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

local function FrameIsMouseOver(frame)
    if not frame then
        return false
    end
    if frame.IsVisible then
        local okVis, vis = pcall(frame.IsVisible, frame)
        if not okVis or (ValueHidden(vis)) or not vis then
            return false
        end
    end
    if frame.IsMouseOver then
        local okOver, over = pcall(frame.IsMouseOver, frame)
        if okOver and not (ValueHidden(over)) then
            return over and true or false
        end
    end
    local left, right, bottom, top = frame:GetLeft(), frame:GetRight(), frame:GetBottom(), frame:GetTop()
    if ValueHidden(left) or ValueHidden(right) or ValueHidden(bottom) or ValueHidden(top) or not left then
        return false
    end
    local scale = frame:GetEffectiveScale() or 1
    local x, y = GetCursorPosition()
    if ValueHidden(x) or ValueHidden(y) or ValueHidden(scale) or scale == 0 then
        return false
    end
    x, y = x / scale, y / scale
    return x >= left and x <= right and y >= bottom and y <= top
end

-- Make default XP/rep bars invisible and click-through using pure C++ region methods
-- (SetAlpha(0) and EnableMouse(false)). Never call frame:Hide() or frame:SetShown() on
-- StatusTrackingBarManager or EditMode containers, as their <OnHide> scripts invoke
-- UIParentBottomManagedFrameMixin:OnHide -> EditModeManagerFrame layout updates on our stack.
local blizzBarList = {}
local blizzBarSeen = {}
local suppressedFrames = {}
local blizzBarCacheAt = 0

local function RememberChildren(list, seen, selection, ok, ...)
    if not ok then
        return
    end
    local n = select("#", ...)
    for i = 1, n do
        local child = select(i, ...)
        if child and child ~= selection and not seen[child] then
            seen[child] = true
            list[#list + 1] = child
        end
    end
end

local function RememberBar(list, seen, frame)
    if not frame or seen[frame] then
        return
    end
    seen[frame] = true
    list[#list + 1] = frame
    if type(frame.bars) == "table" then
        for _, bar in pairs(frame.bars) do
            if bar and not seen[bar] then
                seen[bar] = true
                list[#list + 1] = bar
            end
        end
    end
    if frame.GetChildren then
        RememberChildren(list, seen, frame.Selection, pcall(frame.GetChildren, frame))
    end
end

local function GetBlizzardBars()
    local now = GetTime()
    if blizzBarCacheAt > 0 and (now - blizzBarCacheAt) < 30 then
        return blizzBarList
    end
    for i = #blizzBarList, 1, -1 do
        blizzBarSeen[blizzBarList[i]] = nil
        blizzBarList[i] = nil
    end
    for i = 1, #BLIZZARD_BAR_NAMES do
        RememberBar(blizzBarList, blizzBarSeen, _G[BLIZZARD_BAR_NAMES[i]])
    end
    blizzBarCacheAt = now
    return blizzBarList
end

local function SuppressBlizzardFrame(frame)
    if not frame or not frame.SetAlpha then
        return
    end
    if frame.GetAlpha then
        local ok, alpha = pcall(frame.GetAlpha, frame)
        if not ok or (ValueHidden(alpha)) or alpha ~= 0 then
            pcall(frame.SetAlpha, frame, 0)
        end
    else
        pcall(frame.SetAlpha, frame, 0)
    end
    if not suppressedFrames[frame] and not (InCombatLockdown and InCombatLockdown()) then
        suppressedFrames[frame] = true
        if frame.EnableMouse then
            pcall(frame.EnableMouse, frame, false)
        end
        if frame.EnableMouseWheel then
            pcall(frame.EnableMouseWheel, frame, false)
        end
    end
end

local function EditModeActive()
    local frame = EditModeManagerFrame
    if not frame then
        return false
    end
    if frame.IsEditModeActive then
        local ok, active = pcall(frame.IsEditModeActive, frame)
        if not ok or (ValueHidden(active)) then
            return false
        end
        return active and true or false
    end
    if not frame.IsShown then
        return false
    end
    local ok, shown = pcall(frame.IsShown, frame)
    if not ok or (ValueHidden(shown)) then
        return false
    end
    return shown and true or false
end

local function RestoreBlizzardFrame(frame)
    if not frame then
        return
    end
    suppressedFrames[frame] = nil
    if frame.SetAlpha then
        pcall(frame.SetAlpha, frame, 1)
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    if frame.EnableMouse then
        pcall(frame.EnableMouse, frame, true)
    end
    if frame.EnableMouseWheel then
        pcall(frame.EnableMouseWheel, frame, true)
    end
end

function FBT:HideBlizzardTrackingBars(force)
    if self.db and self.db.enabled == false then
        return
    end
    if EditModeActive() then
        return
    end
    if force then
        blizzBarCacheAt = 0
    end
    local bars = GetBlizzardBars()
    for i = 1, #bars do
        SuppressBlizzardFrame(bars[i])
    end
end

function FBT:RestoreBlizzardTrackingBars()
    blizzBarCacheAt = 0
    local bars = GetBlizzardBars()
    for i = 1, #bars do
        RestoreBlizzardFrame(bars[i])
    end
end

function FBT:ApplyVisibility()
    if not ui.card or not self.db then
        return
    end
    if self.db.enabled == false then
        ui.card:Hide()
        if ui.panel then
            ui.panel:Hide()
        end
        self:RestoreBlizzardTrackingBars()
        return
    end
    if not ui.card:IsShown() then
        ui.card:Show()
    end
    self:HideBlizzardTrackingBars(true)
    self:ApplyStatsDisplayMode()
end

function FBT:ApplyCardHeight()
    if not ui.card then
        return
    end
    local collapsed = CardCollapsedHeight()
    if ui.card.SetResizeBounds then
        ui.card:SetResizeBounds(MIN_WIDTH, collapsed, MAX_WIDTH, 220)
    elseif ui.card.SetMinResize then
        ui.card:SetMinResize(MIN_WIDTH, collapsed)
    end
    if IsSeparateStatsMode() or not ui.expanded then
        ui.currentHeight = collapsed
        ui.targetHeight = collapsed
        ui.card:SetHeight(collapsed)
        return
    end
    ui.targetHeight = CardExpandedHeight()
    if EnsureAnim then
        EnsureAnim()
    end
end

function FBT:ApplyScale()
    if not self.db then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        pendingLayout = true
        return
    end
    local scale = Clamp(self.db.scale or 1, 0.75, 1.5)
    if ui.card and ui.card.SetScale then
        ui.card:SetScale(scale)
    end
    if ui.panel and ui.panel.SetScale then
        ui.panel:SetScale(scale)
    end
end

local SHADOW_SPECS = {
    { "TOPLEFT", "TOPRIGHT", true, 4, -4 },
    { "BOTTOMLEFT", "BOTTOMRIGHT", true, 4, 4 },
    { "TOPLEFT", "BOTTOMLEFT", false, 4, -4 },
    { "TOPRIGHT", "BOTTOMRIGHT", false, -4, -4 },
}

local CARD_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local MINIMAL_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local TOOLTIP_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local BADGE_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function EnsureInnerShadow(frame)
    if not frame or frame.xiusShadow then
        return
    end
    local shadow = {}
    for i = 1, 4 do
        local spec = SHADOW_SPECS[i]
        local line = frame:CreateTexture(nil, "BORDER", nil, 1)
        line:SetColorTexture(0, 0, 0, 0.65)
        if spec[3] then
            line:SetPoint(spec[1], frame, spec[1], spec[4], spec[5])
            line:SetPoint(spec[2], frame, spec[2], -spec[4], spec[5])
            line:SetHeight(1)
        else
            line:SetPoint(spec[1], frame, spec[1], spec[4], spec[5])
            line:SetPoint(spec[2], frame, spec[2], spec[4], -spec[5])
            line:SetWidth(1)
        end
        shadow[i] = line
    end
    frame.xiusShadow = shadow
end

local function ApplyCardBackdrop(frame)
    if not frame or not frame.SetBackdrop then
        return
    end
    EnsureInnerShadow(frame)
    frame:SetBackdrop(CARD_BACKDROP)
    frame:SetBackdropColor(0.06, 0.06, 0.08, 0.92)
    frame:SetBackdropBorderColor(1.0, 0.82, 0.35, 1.0)
end

function FBT:ApplyBarColors()
    local xr, xg, xb = SavedColor(self.db and self.db.xpColor, COLOR.xp)
    local rsr, rsg, rsb = SavedColor(self.db and self.db.restedColor, COLOR.rest)
    local rr, rg, rb = SavedColor(self.db and self.db.repColor, COLOR.rep)
    if COLOR.xp[1] ~= xr or COLOR.xp[2] ~= xg or COLOR.xp[3] ~= xb then
        COLOR.xp[1], COLOR.xp[2], COLOR.xp[3] = xr, xg, xb
        if ui.xpBar and ui.xpBar.bar then
            ui.xpBar.bar._r = nil
        end
    end
    if COLOR.rest[1] ~= rsr or COLOR.rest[2] ~= rsg or COLOR.rest[3] ~= rsb then
        COLOR.rest[1], COLOR.rest[2], COLOR.rest[3] = rsr, rsg, rsb
    end
    if ui.xpBar and ui.xpBar.rest then
        ui.xpBar.rest:SetVertexColor(COLOR.rest[1], COLOR.rest[2], COLOR.rest[3], 0.45)
    end
    if COLOR.rep[1] ~= rr or COLOR.rep[2] ~= rg or COLOR.rep[3] ~= rb then
        COLOR.rep[1], COLOR.rep[2], COLOR.rep[3] = rr, rg, rb
        if ui.repBar and ui.repBar.bar then
            ui.repBar.bar._r = nil
        end
        if ui.xpBar and ui.xpBar.bar and ui.barKind == "rep" then
            ui.xpBar.bar._r = nil
        end
    end
end

local function PaintFrameChrome(frame, minimal)
    if not frame or not frame.SetBackdrop then
        return
    end
    if minimal then
        frame:SetBackdrop(MINIMAL_BACKDROP)
        frame:SetBackdropColor(0.07, 0.07, 0.08, 0.9)
        frame:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
    else
        ApplyCardBackdrop(frame)
    end
end

local function ShowFrameShadow(frame, shown)
    local shadow = frame and frame.xiusShadow
    if not shadow then
        return
    end
    for i = 1, #shadow do
        shadow[i]:SetShown(shown)
    end
end

function FBT:ApplyChrome()
    local minimal = self.db and self.db.barStyle == "minimal"
    PaintFrameChrome(ui.card, minimal)
    PaintFrameChrome(ui.panel, minimal)
    ShowFrameShadow(ui.card, not minimal)
    ShowFrameShadow(ui.panel, not minimal)
    self:ApplyBarColors()
    if ui.xpBar and ui.xpBar.LayoutTicks then
        ui.xpBar:LayoutTicks()
    end
    if ui.repBar and ui.repBar.LayoutTicks then
        ui.repBar:LayoutTicks()
    end
end

local function SetFont(fs, template, size, flags)
    local font = template:GetFont()
    if font then
        fs:SetFont(font, size, flags or "")
    end
end

local function StyleMeterButton(btn, hover)
    btn:SetBackdrop(MINIMAL_BACKDROP)
    btn:SetBackdropColor(COLOR.btn[1], COLOR.btn[2], COLOR.btn[3], COLOR.btn[4])
    btn:SetBackdropBorderColor(COLOR.border[1], COLOR.border[2], COLOR.border[3], 0.7)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(COLOR.btnHover[1], COLOR.btnHover[2], COLOR.btnHover[3], 1)
        if hover then
            hover(self, true)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(COLOR.btn[1], COLOR.btn[2], COLOR.btn[3], COLOR.btn[4])
        if hover then
            hover(self, false)
        end
    end)
end

local privateTip

local function EnsurePrivateTooltip()
    if privateTip then
        return privateTip
    end
    local tip = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    tip:SetFrameStrata("TOOLTIP")
    tip:SetFrameLevel(150)
    tip:SetClampedToScreen(true)
    tip:SetBackdrop(TOOLTIP_BACKDROP)
    tip:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
    tip:SetBackdropBorderColor(1.0, 0.82, 0.35, 1)
    tip:Hide()

    local title = tip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -7)
    title:SetJustifyH("LEFT")
    title:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3], 1)
    tip.title = title

    local body = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    body:SetJustifyH("LEFT")
    body:SetWidth(220)
    body:SetTextColor(0.82, 0.82, 0.82, 1)
    tip.body = body

    privateTip = tip
    return tip
end

function FBT:ShowTooltip(owner, titleText, bodyText)
    if not owner then
        return
    end
    local tip = EnsurePrivateTooltip()
    tip.title:SetText(titleText or "")
    tip.body:SetText(bodyText or "")
    local w = math.max(tip.title:GetStringWidth() or 120, math.min(220, tip.body:GetStringWidth() or 180)) + 16
    local h = (tip.title:GetStringHeight() or 14) + (tip.body:GetStringHeight() or 14) + 18
    tip:SetSize(math.max(140, w), math.max(38, h))
    tip:ClearAllPoints()
    tip:SetPoint("BOTTOM", owner, "TOP", 0, 6)
    tip:Show()
end

local factionMenu
local factionCatcher
local factionSortList = {}

local function CloseFactionPicker()
    if factionCatcher then
        factionCatcher:Hide()
    end
    if factionMenu then
        factionMenu:Hide()
    end
end

local function UpdateBadgeDisplay(isRepMode, info, level)
    if not ui.badge or not ui.levelText then
        return
    end
    if isRepMode and info then
        local code = StandingCode(info)
        local r, g, b = StandingColor(info.reaction)
        local key = "rep:" .. code .. ":" .. math.floor(r * 100) .. ":" .. math.floor(g * 100) .. ":" .. math.floor(b * 100)
        if ui.badgeKey ~= key then
            ui.badgeKey = key
            ui.badgeIsRep = true
            SetFont(ui.levelText, GameFontNormal, 11, "OUTLINE")
            ui.levelText:SetText(code)
            ui.levelText:SetTextColor(r, g, b, 1)
            if ui.badge.SetBackdropBorderColor then
                ui.badge:SetBackdropBorderColor(r, g, b, 1)
            end
        end
    else
        local key = "lvl:" .. tostring(level or 0)
        if ui.badgeKey ~= key then
            ui.badgeKey = key
            ui.badgeIsRep = false
            SetFont(ui.levelText, GameFontNormalLarge, 16, "OUTLINE")
            ui.levelText:SetText(tostring(level or 0))
            ui.levelText:SetTextColor(1, 209 / 255, 0, 1)
            if ui.badge.SetBackdropBorderColor then
                ui.badge:SetBackdropBorderColor(212 / 255, 175 / 255, 55 / 255, 1)
            end
        end
    end
end

local function ShowBadgeTooltip(owner)
    if ui.barKind ~= "rep" then
        return
    end
    local info = FBT:GetWatchedFaction()
    if not info then
        return
    end
    local cur, maxV = FactionBarValues(info)
    local nextRem = RemainingToNextRank(info)
    local maxRem, maxLabel = RemainingToMax(info)
    local body = string.format(
        "%s  (%s / %s · %s)\nRemaining to next tier: %s\nRemaining to %s: %s\nClick to switch tracked faction",
        info.rankName or StandingName(info.reaction),
        FormatNumber(cur),
        FormatNumber(maxV),
        FormatPercent(cur, maxV),
        info.isMaxRank and "Max" or FormatNumber(nextRem),
        maxLabel or "Exalted",
        (info.isMaxRank or maxRem <= 0) and "Max" or FormatNumber(maxRem)
    )
    FBT:ShowTooltip(owner, info.name or "Reputation", body)
end

local function SortFactionsDesc(a, b)
    if a.reaction ~= b.reaction then
        return a.reaction > b.reaction
    end
    if a.currentStanding ~= b.currentStanding then
        return a.currentStanding > b.currentStanding
    end
    return (a.name or "") < (b.name or "")
end

local function EnsureFactionPicker()
    if factionMenu then
        return factionMenu
    end
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetToplevel(true)
    menu:SetClampedToScreen(true)
    menu:SetBackdrop(TOOLTIP_BACKDROP)
    menu:SetBackdropColor(0.05, 0.05, 0.07, 0.98)
    menu:SetBackdropBorderColor(1.0, 0.82, 0.35, 0.95)
    menu:EnableMouse(true)
    menu:EnableMouseWheel(true)
    menu:Hide()

    local scroll = CreateFrame("ScrollFrame", nil, menu)
    scroll:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -6, 6)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(256, 20)
    scroll:SetScrollChild(content)

    menu.scroll = scroll
    menu.content = content
    menu.rows = {}
    menu.scrollOffset = 0
    menu.maxScroll = 0

    menu:SetScript("OnMouseWheel", function(self, delta)
        if self.maxScroll <= 0 then
            return
        end
        local nextOffset = Clamp(self.scrollOffset - (delta * 22 * 2), 0, self.maxScroll)
        self.scrollOffset = nextOffset
        self.scroll:SetVerticalScroll(nextOffset)
    end)

    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("TOOLTIP")
    catcher:EnableMouse(true)
    catcher:EnableMouseWheel(true)
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnMouseDown", function()
        if factionMenu and factionMenu:IsShown() and factionMenu:IsMouseOver() then
            return
        end
        CloseFactionPicker()
    end)
    catcher:SetScript("OnMouseWheel", function()
        CloseFactionPicker()
    end)
    catcher:Hide()

    factionMenu = menu
    factionCatcher = catcher
    return menu
end

local function GetPickerRow(menu, idx)
    local row = menu.rows[idx]
    if row then
        return row
    end
    row = CreateFrame("Button", nil, menu.content)
    row:SetSize(252, 20)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.07, 0)
    row.bg = bg

    local tag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tag:SetPoint("LEFT", row, "LEFT", 4, 0)
    tag:SetWidth(30)
    tag:SetJustifyH("LEFT")
    SetFont(tag, GameFontNormalSmall, 10, "OUTLINE")
    row.tag = tag

    local right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    right:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    right:SetWidth(76)
    right:SetJustifyH("RIGHT")
    SetFont(right, GameFontHighlightSmall, 10)
    row.right = right

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", tag, "RIGHT", 4, 0)
    name:SetPoint("RIGHT", right, "LEFT", -4, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    SetFont(name, GameFontHighlightSmall, 11)
    row.name = name

    row:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(0.32, 0.24, 0.08, 0.9)
    end)
    row:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(0.05, 0.05, 0.07, 0)
    end)
    -- Rows cover the menu, so wheel must forward from each row to the menu scroll.
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta)
        local handler = menu:GetScript("OnMouseWheel")
        if handler then
            handler(menu, delta)
        end
    end)

    menu.rows[idx] = row
    return row
end

local function ToggleFactionPicker(owner)
    if not owner or ui.barKind ~= "rep" then
        return
    end
    if factionMenu and factionMenu:IsShown() then
        CloseFactionPicker()
        return
    end
    FBT:HideTooltip()
    local menu = EnsureFactionPicker()
    local list, count = ScanActiveFactions()
    for i = 1, count do
        factionSortList[i] = list[i]
    end
    for i = count + 1, #factionSortList do
        factionSortList[i] = nil
    end
    table.sort(factionSortList, SortFactionsDesc)

    local db = FBT.db
    local watched = FBT:GetWatchedFaction()
    local watchedID = watched and watched.factionID or 0
    local watchedName = watched and watched.name or ""
    local autoMode = not db or db.repPickerMode ~= "MANUAL"

    local totalRows = count + 1
    local rowH = 22
    local visibleRows = math.min(12, math.max(1, totalRows))
    local menuW = 268
    local menuH = (visibleRows * rowH) + 12
    local contentH = totalRows * rowH

    menu:SetSize(menuW, menuH)
    menu.content:SetSize(menuW - 12, contentH)
    menu.scrollOffset = 0
    menu.maxScroll = math.max(0, contentH - (visibleRows * rowH))
    menu.scroll:SetVerticalScroll(0)

    -- Row 1: Auto (Highest Non-Exalted)
    local autoRow = GetPickerRow(menu, 1)
    autoRow:ClearAllPoints()
    autoRow:SetPoint("TOPLEFT", menu.content, "TOPLEFT", 0, 0)
    autoRow:SetWidth(menuW - 12)
    autoRow.tag:SetText("AUTO")
    autoRow.tag:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3], 1)
    autoRow.name:SetText("Auto (Highest Non-Exalted)")
    if autoMode then
        autoRow.name:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3], 1)
        autoRow.right:SetText("Active")
        autoRow.right:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3], 1)
    else
        autoRow.name:SetTextColor(0.92, 0.92, 0.94, 1)
        autoRow.right:SetText("")
    end
    autoRow:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then
            FBT:Print("Faction watch changes after combat.")
            return
        end
        if FBT.db then
            FBT.db.repPickerMode = "AUTO"
        end
        CloseFactionPicker()
        local best = FindBestNonExaltedFaction()
        if best then
            SetWatchedFactionSafe(best.index, best.factionID)
        end
        watchedCache = nil
        watchedCacheValid = false
        CacheFactionBaseline(true)
        FBT:Refresh()
    end)
    autoRow:Show()

    for i = 1, count do
        local entry = factionSortList[i]
        local row = GetPickerRow(menu, i + 1)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu.content, "TOPLEFT", 0, -i * rowH)
        row:SetWidth(menuW - 12)

        local r, g, b = StandingColor(entry.reaction)
        local code = STANDING_CODES[Clamp(entry.reaction or 4, 1, 8)] or "NEU"
        row.tag:SetText(code)
        row.tag:SetTextColor(r, g, b, 1)

        local isSelected = (not autoMode) and ((watchedID > 0 and entry.factionID == watchedID) or (entry.name == watchedName))
        row.name:SetText(entry.name or "")
        if isSelected then
            row.name:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3], 1)
        else
            row.name:SetTextColor(0.92, 0.92, 0.94, 1)
        end

        if entry.isExalted then
            row.right:SetText("Exalted")
            row.right:SetTextColor(r, g, b, 1)
        else
            local cur = math.max(0, (entry.currentStanding or 0) - (entry.currentReactionThreshold or 0))
            local maxV = math.max(1, (entry.nextReactionThreshold or 0) - (entry.currentReactionThreshold or 0))
            row.right:SetText(FormatPercent(cur, maxV))
            row.right:SetTextColor(0.76, 0.78, 0.84, 1)
        end

        local pickIndex = entry.index
        local pickID = entry.factionID
        row:SetScript("OnClick", function()
            if InCombatLockdown and InCombatLockdown() then
                FBT:Print("Faction watch changes after combat.")
                return
            end
            if FBT.db then
                FBT.db.repPickerMode = "MANUAL"
            end
            CloseFactionPicker()
            SetWatchedFactionSafe(pickIndex, pickID)
            watchedCache = nil
            watchedCacheValid = false
            CacheFactionBaseline(true)
            FBT:Refresh()
        end)
        row:Show()
    end

    for i = totalRows + 1, #menu.rows do
        menu.rows[i]:Hide()
    end

    menu:ClearAllPoints()
    if ui.growUp then
        menu:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 6)
    else
        menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -6)
    end
    local level = (owner:GetFrameLevel() or 80) + 60
    factionCatcher:SetFrameLevel(math.max(1, level - 1))
    menu:SetFrameLevel(level)
    factionCatcher:Show()
    menu:Show()
end

function FBT:HideTooltip()
    if privateTip then
        privateTip:Hide()
    end
end

local function MakeGearButton(parent, size, keepExpanded)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(size, size)
    StyleMeterButton(btn, function(_, entering)
        if entering then
            FBT:ShowTooltip(btn, "Settings", "Open options. Right-click the bar also works.")
        else
            FBT:HideTooltip()
        end
        if keepExpanded then
            if entering and OnCardEnter then
                OnCardEnter()
            elseif (not entering) and OnCardLeave then
                OnCardLeave()
            end
        end
    end)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp")
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetSize(math.max(10, size - 6), math.max(10, size - 6))
    tex:SetPoint("CENTER", 0, 0)
    tex:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    tex:SetVertexColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3], 1)
    local fallback = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fallback:SetPoint("CENTER", 0, 0)
    SetFont(fallback, GameFontNormalSmall, math.max(9, size - 8), "OUTLINE")
    fallback:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3], 1)
    fallback:SetText("S")
    -- Prefer the options icon when the client provides it.
    if tex.GetTexture and tex:GetTexture() then
        fallback:Hide()
    else
        tex:Hide()
    end
    btn:SetScript("OnClick", function()
        if OpenSettingsFromUI then
            OpenSettingsFromUI()
        end
    end)
    return btn
end

local function CreateThinBar(parent, height)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetHeight(height)
    holder:SetBackdrop(MINIMAL_BACKDROP)
    holder:SetBackdropColor(COLOR.trough[1], COLOR.trough[2], COLOR.trough[3], COLOR.trough[4] or 0.85)
    holder:SetBackdropBorderColor(COLOR.trim[1], COLOR.trim[2], COLOR.trim[3], 1)

    local rest = holder:CreateTexture(nil, "ARTWORK")
    rest:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    rest:SetVertexColor(COLOR.rest[1], COLOR.rest[2], COLOR.rest[3], 0.45)
    rest:Hide()

    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetFrameLevel(holder:GetFrameLevel() + 1)

    local gloss = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    gloss:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    gloss:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    gloss:SetHeight(math.max(4, math.floor(height * 0.5)))
    gloss:SetColorTexture(1, 1, 1, 0.16)
    if gloss.SetGradientAlpha then
        pcall(gloss.SetGradientAlpha, gloss, "VERTICAL", 1, 1, 1, 0.02, 1, 1, 1, 0.30)
    elseif gloss.SetGradient and CreateColor then
        pcall(gloss.SetGradient, gloss, "VERTICAL", CreateColor(1, 1, 1, 0.02), CreateColor(1, 1, 1, 0.30))
    end

    local overlay = CreateFrame("Frame", nil, holder)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(bar:GetFrameLevel() + 2)

    local ticks = {}
    for i = 1, 19 do
        local tick = overlay:CreateTexture(nil, "OVERLAY")
        tick:SetColorTexture(0, 0, 0, 0.45)
        tick:SetWidth(1)
        tick:Hide()
        ticks[i] = tick
    end
    holder.ticks = ticks
    function holder:LayoutTicks()
        local width = self:GetWidth()
        local minimal = FBT.db and FBT.db.barStyle == "minimal"
        local show = width > 40 and not minimal
        if minimal then
            self:SetBackdropBorderColor(0.2, 0.2, 0.22, 1)
        else
            self:SetBackdropBorderColor(COLOR.trim[1], COLOR.trim[2], COLOR.trim[3], 1)
        end
        for i = 1, #ticks do
            local tick = ticks[i]
            if show then
                local x = width * (i / 20)
                tick:ClearAllPoints()
                tick:SetPoint("TOP", self, "TOPLEFT", x, -1)
                tick:SetPoint("BOTTOM", self, "BOTTOMLEFT", x, 1)
                tick:Show()
            else
                tick:Hide()
            end
        end
    end
    holder:SetScript("OnSizeChanged", function(self)
        self:LayoutTicks()
    end)
    holder:LayoutTicks()

    holder.bar = bar
    holder.rest = rest
    return holder
end

local function HideRest(holder)
    if holder.rest:IsShown() then
        holder.rest:Hide()
    end
    holder.restKey = nil
end

local function LayoutRest(holder, current, extra, maxV)
    local rest = holder.rest
    if not extra or extra <= 0 or not maxV or maxV <= 0 then
        HideRest(holder)
        return
    end
    local width = holder:GetWidth() - 2
    if width <= 0 then
        HideRest(holder)
        return
    end
    local from = Clamp(current / maxV, 0, 1)
    local to = Clamp((current + extra) / maxV, 0, 1)
    local w = (to - from) * width
    if w < 1 then
        HideRest(holder)
        return
    end
    local key = math.floor(width + 0.5) * 1000000
        + math.floor(from * 1000 + 0.5) * 1000
        + math.floor(w + 0.5)
    if holder.restKey == key and rest:IsShown() then
        return
    end
    holder.restKey = key
    rest:ClearAllPoints()
    rest:SetPoint("TOPLEFT", holder, "TOPLEFT", 1 + from * width, -1)
    rest:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 1 + from * width, 1)
    rest:SetWidth(w)
    if not rest:IsShown() then
        rest:Show()
    end
end

local function SetStatusBar(bar, minV, maxV, value, r, g, b)
    if bar._min ~= minV or bar._max ~= maxV then
        bar._min = minV
        bar._max = maxV
        bar:SetMinMaxValues(minV, maxV)
    end
    if bar._val ~= value then
        bar._val = value
        bar:SetValue(value)
    end
    if bar._r ~= r or bar._g ~= g or bar._b ~= b then
        bar._r, bar._g, bar._b = r, g, b
        bar:SetStatusBarColor(r, g, b, 1)
    end
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
    local wantShown = shown and true or false
    if stat._shown ~= wantShown then
        stat._shown = wantShown
        ui.statsVisibilityDirty = true
    end
    if not wantShown then
        if stat:IsShown() then
            stat:Hide()
        end
        return
    end
    if stat._label ~= label then
        stat._label = label
        stat.label:SetText(label)
    end
    if stat._value ~= value then
        stat._value = value
        stat.value:SetText(value)
    end
    local r, g, b = COLOR.value[1], COLOR.value[2], COLOR.value[3]
    if color then
        r, g, b = color[1], color[2], color[3]
    end
    if stat._r ~= r or stat._g ~= g or stat._b ~= b then
        stat._r, stat._g, stat._b = r, g, b
        stat.value:SetTextColor(r, g, b, 1)
    end
    if not stat:IsShown() then
        stat:Show()
    end
end

function FBT:ResolveGrowthDirection(useLivePosition)
    local mode = self.db and self.db.growthDirection or "AUTO"
    if mode == "UP" or mode == "DOWN" then
        return mode
    end
    -- After a real drag, layout coords are valid. On restore/login they are
    -- not: CreateFrame defaults to CENTER, so GetCenter would pin AUTO to
    -- the middle of the screen until the lock checkbox reapplied saved points.
    if useLivePosition and ui.card then
        local _, centerY = ui.card:GetCenter()
        local screenH = GetScreenHeight()
        if not ValueHidden(centerY) and not ValueHidden(screenH) and type(centerY) == "number" and type(screenH) == "number" then
            if centerY < (screenH * 0.5) then
                return "UP"
            end
            return "DOWN"
        end
    end
    local point = self.db and self.db.point
    if type(point) == "string" then
        if string.find(point, "BOTTOM", 1, true) then
            return "UP"
        end
        if string.find(point, "TOP", 1, true) then
            return "DOWN"
        end
    end
    return "UP"
end

-- reanchorCard: true after a real drag (layout coords are valid).
-- false when restoring saved points so stale GetLeft/GetCenter cannot
-- overwrite the saved UIParent anchor (the /reload center-screen bug).
function FBT:UpdateFrameOrientation(resolvedDirection, reanchorCard)
    local card = ui.card
    local header = ui.header
    local stats = ui.stats
    if not card or not header or not stats then
        return
    end
    resolvedDirection = resolvedDirection or self:ResolveGrowthDirection(reanchorCard and true or false)
    if resolvedDirection == "AUTO" then
        resolvedDirection = self:ResolveGrowthDirection(reanchorCard and true or false)
    end
    ui.growUp = (resolvedDirection == "UP")
    ui.resolvedDirection = resolvedDirection

    if reanchorCard then
        if InCombatLockdown and InCombatLockdown() then
            pendingLayout = true
        else
            local left, right, top, bottom = card:GetLeft(), card:GetRight(), card:GetTop(), card:GetBottom()
            if ValueHidden(left) or ValueHidden(right) or ValueHidden(top) or ValueHidden(bottom) then
                pendingLayout = true
            elseif left and right and top and bottom then
                local currentCenterX = (left + right) / 2
                card:ClearAllPoints()
                if ui.growUp then
                    card:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", currentCenterX, bottom)
                else
                    card:SetPoint("TOP", UIParent, "BOTTOMLEFT", currentCenterX, top)
                end
            end
        end
    end

    -- When stats live on the separate panel, never re-anchor them to the card.
    -- RestoreCardPosition / login /reload used to do that and piled every
    -- metric onto the collapsed XP bar while leaving the panel empty.
    local statsOnCard = (not IsSeparateStatsMode()) and stats:GetParent() == card

    header:ClearAllPoints()
    if statsOnCard then
        stats:ClearAllPoints()
        stats:SetHeight(STATS_EXTRA - 12)
    end
    -- Keep the drawer seam flush with the collapsed card height (8 + HEADER_H + gap).
    local drawerGap = CardCollapsedHeight() - 8 - HEADER_H
    if drawerGap < 0 then
        drawerGap = 0
    end
    if ui.growUp then
        header:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 8)
        header:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 8)
        if statsOnCard then
            stats:SetPoint("BOTTOMLEFT", header, "TOPLEFT", 0, drawerGap)
            stats:SetPoint("BOTTOMRIGHT", header, "TOPRIGHT", 0, drawerGap)
        end
    else
        header:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
        header:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -8)
        if statsOnCard then
            stats:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -drawerGap)
            stats:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -drawerGap)
        end
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
        ui.barColumn:SetPoint("RIGHT", header, "RIGHT", -4, 0)
        ui.barColumn:SetPoint("TOP", header, "TOP", 0, 0)
        ui.barColumn:SetPoint("BOTTOM", header, "BOTTOM", 0, 0)
    end
    if ui.grip then
        ui.grip:ClearAllPoints()
        ui.grip:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
    end
    if statsOnCard then
        LayoutStatsGrid()
    end
end

local function EnsureSeparateStatsAnchored()
    if not IsSeparateStatsMode() then
        return
    end
    if ui.panel and ui.stats and ui.stats:GetParent() == ui.panel and ui.panel:IsShown() then
        return
    end
    if FBT.ApplyStatsDisplayMode then
        FBT:ApplyStatsDisplayMode()
    end
end

local function SavePosition()
    local db, card = FBT.db, ui.card
    if not db or not card then
        return
    end
    local point, _, relativePoint, x, y = card:GetPoint(1)
    if ValueHidden(point) then
        point = nil
    end
    if ValueHidden(relativePoint) then
        relativePoint = nil
    end
    db.point = point or "BOTTOM"
    db.relativePoint = relativePoint or "BOTTOMLEFT"
    db.x = PublicNumber(x, db.x or 0)
    db.y = PublicNumber(y, db.y or 0)
    db.width = math.max(MIN_WIDTH, Round(PublicNumber(card:GetWidth(), db.width or MIN_WIDTH)))
end

local function SavePanelPosition()
    local db, panel = FBT.db, ui.panel
    if not db or not panel then
        return
    end
    local point, _, relativePoint, x, y = panel:GetPoint(1)
    if ValueHidden(point) then
        point = nil
    end
    if ValueHidden(relativePoint) then
        relativePoint = nil
    end
    db.panelPoint = point or "CENTER"
    db.panelRelativePoint = relativePoint or "CENTER"
    db.panelX = PublicNumber(x, db.panelX or 0)
    db.panelY = PublicNumber(y, db.panelY or 0)
    db.panelWidth = math.max(PANEL_MIN_WIDTH, Round(PublicNumber(panel:GetWidth(), db.panelWidth or PANEL_MIN_WIDTH)))
end

function FBT:NudgePanelClearOfOptions()
    if not IsSeparateStatsMode() or not ui.panel or not ui.panel:IsShown() or not self.db or self.db.panelLocked then
        return
    end
    -- XiusCore settings frame (legacy global name still used by XiusUISettingsLib).
    local window = _G.XiusCoreSettingsLibFrame or _G.XiusUISettingsLibFrame
    if not (window and window.IsShown and window:IsShown()) then
        window = _G.XiusUIOptionsFrame
    end
    if not (window and window.IsShown and window:IsShown()) then
        return
    end
    local pLeft, pRight = ui.panel:GetLeft(), ui.panel:GetRight()
    local pBottom, pTop = ui.panel:GetBottom(), ui.panel:GetTop()
    local wLeft, wRight = window:GetLeft(), window:GetRight()
    local wBottom, wTop = window:GetBottom(), window:GetTop()
    if not pLeft or not pRight or not wLeft or not wRight or ValueHidden(pLeft) or ValueHidden(pRight) or ValueHidden(wLeft) or ValueHidden(wRight) or ValueHidden(pTop) or ValueHidden(wTop) or ValueHidden(pBottom) or ValueHidden(wBottom) then
        return
    end
    local overlaps = pLeft < wRight and pRight > wLeft and pBottom < wTop and pTop > wBottom
    if not overlaps then
        return
    end
    local screenW = GetScreenWidth() or 0
    local width = ui.panel:GetWidth() or PANEL_WIDTH
    local x = wRight + 12
    if screenW > 0 and (x + width) > (screenW - 8) then
        x = wLeft - width - 12
    end
    ui.panel:ClearAllPoints()
    ui.panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, wTop)
    SavePanelPosition()
end

local VALID_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

function FBT:RestoreCardPosition()
    if InCombatLockdown and InCombatLockdown() then
        pendingLayout = true
        return
    end
    local db = self.db or ForeverBarTrackerDB
    local card = ui.card
    if not db or not card or not db.point then
        return
    end
    local point = db.point
    local relativePoint = db.relativePoint or point
    if not VALID_POINTS[point] or not VALID_POINTS[relativePoint] then
        point = self.defaults.point
        relativePoint = self.defaults.relativePoint
        db.point = point
        db.relativePoint = relativePoint
    end
    local x = type(db.x) == "number" and db.x or 0
    local y = type(db.y) == "number" and db.y or 0
    db.x = x
    db.y = y
    card:ClearAllPoints()
    card:SetPoint(point, UIParent, relativePoint, x, y)
    card:SetWidth(math.max(MIN_WIDTH, Clamp(db.width or CARD_WIDTH, MIN_WIDTH, MAX_WIDTH)))
    self:UpdateFrameOrientation(self:ResolveGrowthDirection(false), false)
end

function FBT:RestorePanelPosition()
    if InCombatLockdown and InCombatLockdown() then
        pendingLayout = true
        return
    end
    local db = self.db or ForeverBarTrackerDB
    local panel = ui.panel
    if not db or not panel then
        return
    end
    local point = db.panelPoint or self.defaults.panelPoint
    local relativePoint = db.panelRelativePoint or point
    if not VALID_POINTS[point] or not VALID_POINTS[relativePoint] then
        point = self.defaults.panelPoint
        relativePoint = self.defaults.panelRelativePoint
        db.panelPoint = point
        db.panelRelativePoint = relativePoint
    end
    local x = type(db.panelX) == "number" and db.panelX or 0
    local y = type(db.panelY) == "number" and db.panelY or 0
    db.panelX = x
    db.panelY = y
    panel:ClearAllPoints()
    panel:SetPoint(point, UIParent, relativePoint, x, y)
    panel:SetWidth(Clamp(db.panelWidth or PANEL_WIDTH, PANEL_MIN_WIDTH, PANEL_MAX_WIDTH))
    panel:SetHeight(PANEL_HEIGHT)
    LayoutStatsGrid()
end

local function CollectStatWidgets()
    if ui.allStats then
        return ui.allStats
    end
    ui.allStats = {
        ui.statSessionXP, ui.statSessionTime,
        ui.statRested, ui.statTTL,
        ui.statOverallTTL,
        ui.statXPHour, ui.statKTL,
        ui.statQTL, ui.statRepSess,
        ui.statGoldHour, ui.statGoldSess,
        ui.statRepHour, ui.statNextRank,
        ui.statTimeLevel, ui.statTimePlayed,
    }
    return ui.allStats
end

function LayoutStatsGrid()
    local host = ui.statsHost or ui.card
    local grid, cols = ui.grid, ui.statCols
    if not host or not grid or not cols then
        return
    end
    local availWidth = math.max(1, host:GetWidth() - (LEFT_MARGIN + RIGHT_MARGIN))
    local compact = (ui.panel and host == ui.panel) or IsSeparateStatsMode()
    local repMode = ui.repModeGrid and true or false
    local stats = CollectStatWidgets()
    local visibleBits = 0
    for i = 1, #stats do
        if stats[i] and stats[i]._shown ~= false then
            visibleBits = visibleBits + (2 ^ (i - 1))
        end
    end
    local layoutKey = availWidth + (compact and 100000 or 0) + (repMode and 200000 or 0) + visibleBits
    if ui.gridLayoutWidth and math.abs(ui.gridLayoutWidth - layoutKey) < 0.25 then
        return
    end
    ui.gridLayoutWidth = layoutKey

    if compact then
        local visibleCount = 0
        for i = 1, #stats do
            if stats[i] and stats[i]._shown ~= false then
                visibleCount = visibleCount + 1
            end
        end
        -- Pack left-to-right with only as many columns as visible stats need.
        local colCount = math.max(1, math.min(PANEL_COLUMNS, math.max(1, visibleCount)))
        local colWidth = availWidth / colCount
        local textWidth = math.max(8, colWidth - 4)
        local rowHeight = 30
        for i = 1, #cols do
            if cols[i] then
                cols[i]:Hide()
            end
        end
        local visIdx = 0
        for i = 1, #stats do
            local stat = stats[i]
            if stat then
                stat:SetParent(grid)
                stat:ClearAllPoints()
                stat:SetWidth(textWidth)
                stat.label:SetWidth(textWidth)
                stat.value:SetWidth(textWidth)
                if stat._shown ~= false then
                    local col = visIdx % colCount
                    local row = math.floor(visIdx / colCount)
                    local x = col * colWidth
                    local y = -row * rowHeight
                    stat:SetPoint("TOPLEFT", grid, "TOPLEFT", x, y)
                    visIdx = visIdx + 1
                else
                    stat:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, 0)
                end
            end
        end
        return
    end

    local activeCols
    if repMode then
        activeCols = 5
        cols[1].statTop, cols[1].statBottom = ui.statRepSess, ui.statRepHour
        cols[2].statTop, cols[2].statBottom = ui.statSessionXP, ui.statXPHour
        cols[3].statTop, cols[3].statBottom = ui.statQTL, ui.statNextRank
        cols[4].statTop, cols[4].statBottom = ui.statGoldSess, ui.statGoldHour
        cols[5].statTop, cols[5].statBottom = ui.statSessionTime, ui.statTimePlayed
        cols[6].statTop, cols[6].statBottom = nil, nil
        cols[7].statTop, cols[7].statBottom = nil, nil
        cols[8].statTop, cols[8].statBottom = nil, nil
    else
        cols[1].statTop, cols[1].statBottom = ui.statSessionXP, ui.statSessionTime
        cols[2].statTop, cols[2].statBottom = ui.statRested, ui.statTTL
        cols[3].statTop, cols[3].statBottom = ui.statXPHour, ui.statKTL
        cols[4].statTop, cols[4].statBottom = ui.statQTL, ui.statRepSess
        cols[5].statTop, cols[5].statBottom = ui.statGoldHour, ui.statGoldSess
        cols[6].statTop, cols[6].statBottom = ui.statRepHour, ui.statNextRank
        cols[7].statTop, cols[7].statBottom = ui.statTimeLevel, ui.statTimePlayed
        cols[8].statTop, cols[8].statBottom = ui.statOverallTTL, nil
        activeCols = NUM_COLUMNS
        if cols[8] and cols[8].statTop and cols[8].statTop._shown == false and not cols[8].statBottom then
            activeCols = NUM_COLUMNS - 1
        end
    end
    -- Pack only columns that still have at least one visible stat so toggling
    -- options never leaves empty gaps across the drawer.
    local packed = {}
    for i = 1, activeCols do
        local col = cols[i]
        if col then
            local topStat = col.statTop
            local bottomStat = col.statBottom
            local topShown = topStat and topStat._shown ~= false
            local bottomShown = bottomStat and bottomStat._shown ~= false
            if topShown or bottomShown then
                packed[#packed + 1] = col
            else
                col:Hide()
            end
        end
    end
    for i = activeCols + 1, NUM_COLUMNS do
        if cols[i] then
            cols[i]:Hide()
        end
    end
    local packedCount = math.max(1, #packed)
    local colWidth = availWidth / packedCount
    local textWidth = math.max(8, colWidth - 8)
    for i = 1, #packed do
        local col = packed[i]
        col:Show()
        local x = (LEFT_MARGIN - PAD) + ((i - 1) * colWidth)
        local topStat = col.statTop
        local bottomStat = col.statBottom
        local topShown = topStat and topStat._shown ~= false
        local bottomShown = bottomStat and bottomStat._shown ~= false
        local colH = 0
        if topShown then
            colH = colH + (topStat:GetHeight() or 30)
        end
        if bottomShown then
            if colH > 0 then
                colH = colH + 6
            end
            colH = colH + (bottomStat:GetHeight() or 30)
        end
        col:ClearAllPoints()
        col:SetPoint("TOPLEFT", grid, "TOPLEFT", x, 0)
        col:SetSize(textWidth, math.max(1, colH))
        if topStat then
            topStat:SetParent(col)
            topStat:ClearAllPoints()
            topStat:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0)
            topStat:SetPoint("RIGHT", col, "RIGHT", 0, 0)
            topStat:SetWidth(textWidth)
            topStat.label:SetWidth(textWidth)
            topStat.value:SetWidth(textWidth)
        end
        if bottomStat then
            bottomStat:SetParent(col)
            bottomStat:ClearAllPoints()
            if topShown then
                bottomStat:SetPoint("TOPLEFT", topStat, "BOTTOMLEFT", 0, -6)
            else
                bottomStat:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0)
            end
            bottomStat:SetPoint("RIGHT", col, "RIGHT", 0, 0)
            bottomStat:SetWidth(textWidth)
            bottomStat.label:SetWidth(textWidth)
            bottomStat.value:SetWidth(textWidth)
        end
    end
end

local function SetStatsInteractive(enabled)
    if ui.statsInteractive == enabled then
        return
    end
    ui.statsInteractive = enabled
    if ui.resetBtn then
        ui.resetBtn:EnableMouse(enabled)
    end
    if ui.settingsBtn then
        ui.settingsBtn:EnableMouse(enabled)
    end
    if ui.statOverallTTL then
        ui.statOverallTTL:EnableMouse(enabled)
    end
end

local function IsOverStatsButton()
    if not ui.statsInteractive then
        return false
    end
    if ui.resetBtn and FrameIsMouseOver(ui.resetBtn) then
        return true
    end
    if ui.settingsBtn and FrameIsMouseOver(ui.settingsBtn) then
        return true
    end
    return false
end

local function ShouldShowEmbeddedStats()
    if IsSeparateStatsMode() then
        return false
    end
    return ui.expanded or (ui.stats and ui.stats:IsShown() and (ui.stats:GetAlpha() or 0) > 0.02)
end

local function AnimOnUpdate(self, elapsed)
    if ui.moving and IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        OnCardDragStop()
    end

    if ui.sizing then
        if not IsMouseButtonDown("LeftButton") then
            ui.sizing = false
            SavePosition()
        else
            local x = GetCursorPosition()
            if ValueHidden(x) then
                return
            end
            local width = Clamp(ui.sizeStartW + ((x - ui.sizeStartX) / ui.sizeScale), MIN_WIDTH, MAX_WIDTH)
            self:SetWidth(width)
            FBT.db.width = math.max(MIN_WIDTH, Round(width))
            -- Anchors stretch the bars. Only the rested overlay uses a pixel width.
            if FBT.UpdateRestedOverlay then
                FBT:UpdateRestedOverlay()
            end
        end
    end

    if IsSeparateStatsMode() then
        -- Stats live on the separate panel; only collapse the XP/rep card.
        ui.currentHeight = CardCollapsedHeight()
        ui.targetHeight = CardCollapsedHeight()
        self:SetHeight(CardCollapsedHeight())
        if not ui.sizing and not ui.moving then
            self:SetScript("OnUpdate", nil)
        end
        return
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

    local progress = Clamp((ui.currentHeight - CardCollapsedHeight()) / STATS_EXTRA, 0, 1)
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

    if (not ui.sizing) and (not ui.moving) and math.abs(ui.currentHeight - ui.targetHeight) <= 0.35 then
        ui.currentHeight = ui.targetHeight
        self:SetHeight(ui.targetHeight)
        self:SetScript("OnUpdate", nil)
    end
end

local function PanelOnUpdate(self, elapsed)
    if ui.panelMoving and IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        OnPanelDragStop()
    end
    if not ui.panelSizing then
        if not ui.panelMoving then
            self:SetScript("OnUpdate", nil)
        end
        return
    end
    if not IsMouseButtonDown("LeftButton") then
        ui.panelSizing = false
        SavePanelPosition()
        self:SetScript("OnUpdate", nil)
        return
    end
    local x = GetCursorPosition()
    if ValueHidden(x) then
        return
    end
    local width = Clamp(ui.panelSizeStartW + ((x - ui.panelSizeStartX) / ui.panelSizeScale), PANEL_MIN_WIDTH, PANEL_MAX_WIDTH)
    self:SetWidth(width)
    if FBT.db then
        FBT.db.panelWidth = math.max(PANEL_MIN_WIDTH, Round(width))
    end
end

EnsureAnim = function()
    ui.card:SetScript("OnUpdate", AnimOnUpdate)
end

function FBT:SetExpanded(expanded)
    if IsSeparateStatsMode() then
        ui.expanded = false
        ui.targetHeight = CardCollapsedHeight()
        ui.currentHeight = CardCollapsedHeight()
        if ui.card then
            ui.card:SetHeight(CardCollapsedHeight())
        end
        -- Keep panel stats visible; do not hide ui.stats.
        return
    end
    ui.expanded = expanded and true or false
    ui.targetHeight = ui.expanded and CardExpandedHeight() or CardCollapsedHeight()
    if ui.expanded then
        ui.stats:Show()
        self:RefreshStats()
    end
    EnsureAnim()
end

function FBT:ToggleExpanded()
    if IsSeparateStatsMode() then
        return
    end
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
        if IsSeparateStatsMode() then
            return
        end
        if self:IsHoverOverUI() then
            return
        end
        self:SetExpanded(false)
    end)
end

FactionBarValues = function(info)
    local cur = (info.currentStanding or 0) - (info.currentReactionThreshold or 0)
    local maxV = (info.nextReactionThreshold or 0) - (info.currentReactionThreshold or 0)
    if maxV <= 0 then
        maxV = 1
        cur = 1
    end
    return Clamp(cur, 0, maxV), maxV
end

local function SetCachedText(widget, cacheKey, text)
    if ui[cacheKey] == text then
        return
    end
    ui[cacheKey] = text
    widget:SetText(text)
end

local function LayoutHeaderBars(mode)
    if ui.headerBarMode == mode then
        return
    end
    ui.headerBarMode = mode
    if mode == "dual" then
        if not ui.repBar:IsShown() then
            ui.repBar:Show()
        end
        ui.xpBar:ClearAllPoints()
        ui.xpBar:SetPoint("TOPLEFT", ui.leftLabel, "BOTTOMLEFT", 0, -3)
        ui.xpBar:SetPoint("RIGHT", ui.barColumn, "RIGHT", 0, 0)
        ui.repBar:ClearAllPoints()
        ui.repBar:SetPoint("TOPLEFT", ui.xpBar, "BOTTOMLEFT", 0, -3)
        ui.repBar:SetPoint("RIGHT", ui.barColumn, "RIGHT", 0, 0)
    else
        if ui.repBar:IsShown() then
            ui.repBar:Hide()
        end
        ui.xpBar:ClearAllPoints()
        ui.xpBar:SetPoint("TOPLEFT", ui.leftLabel, "BOTTOMLEFT", 0, -4)
        ui.xpBar:SetPoint("RIGHT", ui.barColumn, "RIGHT", 0, 0)
    end
end

local function CurrentRestXP()
    if not GetXPExhaustion then
        return 0
    end
    return PublicNumber(GetXPExhaustion(), 0)
end

function FBT:UpdateRestedOverlay()
    local holder = ui.xpBar
    if not holder or not self.db then
        return
    end
    if not ShouldShowXP(self.db) or IsPlayerMaxLevel() then
        HideRest(holder)
        return
    end
    local current = PublicNumber(UnitXP("player"), 0)
    local maxXP = PublicNumber(UnitXPMax("player"), 1)
    if maxXP <= 0 then
        maxXP = 1
    end
    LayoutRest(holder, current, CurrentRestXP(), maxXP)
end

function FBT:RefreshHeader()
    if not ui.card or not self.db then
        return
    end
    local db = self.db
    local level = PublicNumber(UnitLevel("player"), 0)
    local atMax = IsPlayerMaxLevel()
    local info
    if atMax or (not db.showXPBar and db.showRepBar) then
        info = self:EnsureMaxLevelReputation(false)
    else
        info = self:GetWatchedFaction()
    end
    local showRep = (atMax or db.showRepBar) and info ~= nil
    local showXP = db.showXPBar and (not atMax or not showRep)

    if showXP then
        local current = PublicNumber(UnitXP("player"), 0)
        local maxXP = PublicNumber(UnitXPMax("player"), 1)
        if maxXP <= 0 then
            maxXP = 1
        end
        if not ui.xpBar:IsShown() then
            ui.xpBar:Show()
        end
        if atMax then
            if ui.barKind ~= "max" or ui.barMax ~= maxXP then
                ui.barKind = "max"
                ui.barMax = maxXP
                SetCachedText(ui.leftLabel, "leftCache", "Experience  Max Level")
                SetCachedText(ui.rightPct, "pctCache", "100%")
                SetStatusBar(ui.xpBar.bar, 0, maxXP, maxXP, COLOR.xp[1], COLOR.xp[2], COLOR.xp[3])
            end
            HideRest(ui.xpBar)
        else
            if ui.barKind ~= "xp" or ui.barXP ~= current or ui.barMax ~= maxXP then
                ui.barKind = "xp"
                ui.barXP = current
                ui.barMax = maxXP
                SetCachedText(ui.leftLabel, "leftCache", string.format("Experience  %s / %s", FormatNumber(current), FormatNumber(maxXP)))
                SetCachedText(ui.rightPct, "pctCache", FormatPercent(current, maxXP))
                SetStatusBar(ui.xpBar.bar, 0, maxXP, current, COLOR.xp[1], COLOR.xp[2], COLOR.xp[3])
            end
            LayoutRest(ui.xpBar, current, CurrentRestXP(), maxXP)
        end
    elseif showRep and info then
        local cur, maxV = FactionBarValues(info)
        if ui.barKind ~= "rep" or ui.barXP ~= cur or ui.barMax ~= maxV or ui.barName ~= info.name then
            ui.barKind = "rep"
            ui.barXP = cur
            ui.barMax = maxV
            ui.barName = info.name
            SetCachedText(ui.leftLabel, "leftCache", string.format("%s  %s / %s", info.name or "Reputation", FormatNumber(cur), FormatNumber(maxV)))
            SetCachedText(ui.rightPct, "pctCache", FormatPercent(cur, maxV))
            SetStatusBar(ui.xpBar.bar, 0, maxV, cur, COLOR.rep[1], COLOR.rep[2], COLOR.rep[3])
        end
        if not ui.xpBar:IsShown() then
            ui.xpBar:Show()
        end
        HideRest(ui.xpBar)
        showRep = false
    else
        local emptyLabel = (not db.showXPBar and db.showRepBar) and "No Watched Faction" or "Experience"
        if ui.barKind ~= "empty" or ui.barName ~= emptyLabel then
            ui.barKind = "empty"
            ui.barName = emptyLabel
            SetCachedText(ui.leftLabel, "leftCache", emptyLabel)
            SetCachedText(ui.rightPct, "pctCache", "--")
            SetStatusBar(ui.xpBar.bar, 0, 1, 0, COLOR.xp[1], COLOR.xp[2], COLOR.xp[3])
        end
        HideRest(ui.xpBar)
    end

    UpdateBadgeDisplay(ui.barKind == "rep", info, level)

    if showRep and info and showXP then
        local cur, maxV = FactionBarValues(info)
        if ui.repCur ~= cur or ui.repMax ~= maxV then
            ui.repCur = cur
            ui.repMax = maxV
            SetStatusBar(ui.repBar.bar, 0, maxV, cur, COLOR.rep[1], COLOR.rep[2], COLOR.rep[3])
        end
        LayoutHeaderBars("dual")
    else
        LayoutHeaderBars("single")
    end

    local wantRepGrid = atMax and ui.barKind == "rep"
    if ui.repModeGrid ~= wantRepGrid then
        ui.repModeGrid = wantRepGrid
        ui.gridLayoutWidth = nil
        if IsSeparateStatsMode() or ShouldShowEmbeddedStats() then
            self:RefreshStats()
        end
    end
end

function FBT:RefreshStats()
    if not ui.statSessionXP or not self.db then
        return
    end
    local db = self.db
    local elapsed = SessionElapsed()
    local xpPerHour = RatePerHour(session.xpEarned or 0, elapsed)
    EnsureMoneyBaseline()
    local money = CurrentMoney()
    local goldDelta = 0
    if money ~= nil and session.moneyReady then
        goldDelta = money - (session.startMoney or 0)
    end
    local goldPerHour = RatePerHour(goldDelta, elapsed)
    local currentXP = PublicNumber(UnitXP("player"), session.lastXP or 0)
    local maxXP = PublicNumber(UnitXPMax("player"), session.lastXPMax or 1)
    if maxXP <= 0 then
        maxXP = 1
    end
    local xpLeft = math.max(0, maxXP - currentXP)
    local atMax = IsPlayerMaxLevel()
    local repModeGrid = atMax and ui.barKind == "rep"
    if ui.repModeGrid ~= repModeGrid then
        ui.repModeGrid = repModeGrid
        ui.statsVisibilityDirty = true
    end

    if repModeGrid then
        -- Hide dead max-level XP cells and repurpose the 5 wide columns for active Reputation & Session stats.
        SetStat(ui.statRested, "RESTED", "--", false, COLOR.rest)
        SetStat(ui.statTTL, "TIME TO LEVEL", "--", false, COLOR.gold)
        SetStat(ui.statOverallTTL, "OVERALL TTL", "--", false, COLOR.gold)
        SetStat(ui.statKTL, "KILLS TO LEVEL", "--", false, COLOR.value)
        SetStat(ui.statTimeLevel, "TIME THIS LEVEL", "--", false, COLOR.value)

        local goldColor = goldPerHour < 0 and COLOR.bad or COLOR.gold
        local sessGoldColor = goldDelta < 0 and COLOR.bad or COLOR.gold
        if db.showGoldHour then
            local goldHourRound = Round(goldPerHour)
            if ui.cachedGoldHourVal ~= goldHourRound then
                ui.cachedGoldHourVal = goldHourRound
                ui.cachedGoldHourText = FormatGoldValue(goldHourRound)
            end
        end
        if db.showGoldSession then
            if ui.cachedGoldDeltaVal ~= goldDelta then
                ui.cachedGoldDeltaVal = goldDelta
                ui.cachedGoldDeltaText = FormatGoldValue(goldDelta)
            end
        end
        SetStat(ui.statGoldSess, "SESSION GOLD", ui.cachedGoldDeltaText or "--", db.showGoldSession, sessGoldColor)
        SetStat(ui.statGoldHour, "GOLD / HOUR", ui.cachedGoldHourText or "--", db.showGoldHour, goldColor)
        local showInst = db.showInstanceTime ~= false and session.inInstance and session.instanceStartTime
        if showInst and not db.showSessionTime then
            SetStat(ui.statSessionTime, "INSTANCE TIME", FormatClock(InstanceElapsed()), true, COLOR.value)
            SetStat(ui.statTimePlayed, "TOTAL PLAYED", db.showTimePlayed and FormatPlayedClock(PlayedSinceSnapshot(session.playedTotal)) or "--", db.showTimePlayed, COLOR.gold)
        elseif showInst then
            -- Keep session visible; instance run uses the time-played slot while inside.
            SetStat(ui.statSessionTime, "SESSION TIME", FormatClock(elapsed), true, COLOR.value)
            SetStat(ui.statTimePlayed, "INSTANCE TIME", FormatClock(InstanceElapsed()), true, COLOR.gold)
        else
            SetStat(ui.statSessionTime, "SESSION TIME", db.showSessionTime and FormatClock(elapsed) or "--", db.showSessionTime, COLOR.value)
            SetStat(ui.statTimePlayed, "TOTAL PLAYED", db.showTimePlayed and FormatPlayedClock(PlayedSinceSnapshot(session.playedTotal)) or "--", db.showTimePlayed, COLOR.gold)
        end

        local info = self:GetWatchedFaction()
        if info then
            local sessionRep = RepTrackValue(info) - (session.startingRep or 0)
            local repPerHour = RatePerHour(sessionRep, elapsed)
            local nextRemain = RemainingToNextRank(info)
            local maxRemain, maxLabel = RemainingToMax(info)
            local maxName = string.upper(maxLabel or "EXALTED")

            local repToNextText = (info.isMaxRank or nextRemain <= 0) and "Max" or FormatNumber(nextRemain)
            local timeToNextText = (info.isMaxRank or nextRemain <= 0) and "Max" or FormatClock(TimeFromRate(nextRemain, repPerHour))
            local repToMaxText = (info.isMaxRank or maxRemain <= 0) and "Max" or FormatNumber(maxRemain)
            local timeToMaxText = (info.isMaxRank or maxRemain <= 0) and "Max" or FormatClock(TimeFromRate(maxRemain, repPerHour))

            SetStat(ui.statRepSess, "SESSION REP", sessionRep ~= 0 and FormatNumber(sessionRep) or "--", db.showRepSession, COLOR.rep)
            SetStat(ui.statRepHour, "REP / HOUR", sessionRep > 0 and FormatCompact(repPerHour) or "--", db.showRepHour, COLOR.rep)
            SetStat(ui.statSessionXP, "REP TO NEXT", repToNextText, db.showRepNextRank, COLOR.value)
            SetStat(ui.statXPHour, "TIME TO NEXT", timeToNextText, db.showRepNextRank, COLOR.gold)
            SetStat(ui.statQTL, "REP TO " .. maxName, repToMaxText, db.showRepExalted, COLOR.value)
            SetStat(ui.statNextRank, "TIME TO " .. maxName, timeToMaxText, db.showRepExalted, COLOR.gold)
        else
            SetStat(ui.statRepSess, "SESSION REP", "--", db.showRepSession, COLOR.rep)
            SetStat(ui.statRepHour, "REP / HOUR", "--", db.showRepHour, COLOR.rep)
            SetStat(ui.statSessionXP, "REP TO NEXT", "--", db.showRepNextRank, COLOR.value)
            SetStat(ui.statXPHour, "TIME TO NEXT", "--", db.showRepNextRank, COLOR.gold)
            SetStat(ui.statQTL, "REP TO EXALTED", "--", db.showRepExalted, COLOR.value)
            SetStat(ui.statNextRank, "TIME TO EXALTED", "--", db.showRepExalted, COLOR.gold)
        end

        if ui.statsVisibilityDirty then
            ui.statsVisibilityDirty = false
            ui.gridLayoutWidth = nil
            LayoutStatsGrid()
        end
        return
    end

    local sessionXPText = string.format("%s / %s", FormatCompact(session.xpEarned or 0), FormatCompact(xpLeft))

    SetStat(ui.statSessionXP, "SESSION XP", sessionXPText, true, COLOR.value)
    local showInst = db.showInstanceTime ~= false and session.inInstance and session.instanceStartTime
    if showInst and not db.showSessionTime then
        SetStat(ui.statSessionTime, "INSTANCE TIME", FormatClock(InstanceElapsed()), true, COLOR.value)
    else
        SetStat(ui.statSessionTime, "SESSION TIME", db.showSessionTime and FormatClock(elapsed) or "--", db.showSessionTime, COLOR.value)
    end
    SetStat(ui.statTimeLevel, "TIME THIS LEVEL", db.showTimeLevel and FormatPlayedClock(PlayedSinceSnapshot(session.playedLevel)) or "--", db.showTimeLevel, COLOR.value)
    if showInst and db.showSessionTime then
        SetStat(ui.statTimePlayed, "INSTANCE TIME", FormatClock(InstanceElapsed()), true, COLOR.gold)
    else
        SetStat(ui.statTimePlayed, "TOTAL PLAYED", db.showTimePlayed and FormatPlayedClock(PlayedSinceSnapshot(session.playedTotal)) or "--", db.showTimePlayed, COLOR.gold)
    end

    local restText = "0 (0%)"
    if db.showRested and not atMax then
        local restXP = CurrentRestXP()
        if restXP > 0 and maxXP > 0 then
            restText = string.format("%s (%s)", FormatCompact(restXP), FormatPercent(restXP, maxXP))
        end
    end
    SetStat(ui.statRested, "RESTED", atMax and "Max" or restText, db.showRested, COLOR.rest)
    SetStat(ui.statTTL, "TIME TO LEVEL", atMax and "Max" or (db.showTTL and FormatClock(TimeFromRate(xpLeft, xpPerHour)) or "--"), db.showTTL, COLOR.gold)

    if db.showOverallTTL then
        local overallTTL, careerRate, blendedRate, careerLevels = ComputeOverallTTL(xpLeft, xpPerHour, elapsed)
        ui.careerPaceRate = careerRate
        ui.careerBlendedRate = blendedRate
        ui.careerSessionRate = xpPerHour
        ui.careerLevelsCount = careerLevels
        SetStat(ui.statOverallTTL, "OVERALL TTL", atMax and "Max" or FormatClock(overallTTL), true, COLOR.gold)
    else
        SetStat(ui.statOverallTTL, "OVERALL TTL", "--", false, COLOR.gold)
    end

    SetStat(ui.statXPHour, "XP / HOUR", (atMax or not db.showXPHour) and "--" or FormatCompact(xpPerHour), db.showXPHour, COLOR.value)

    local ktl = "--"
    if db.showKTL then
        local avgKill = AverageKillXP()
        if not atMax and avgKill > 0 and xpLeft > 0 then
            ktl = tostring(math.ceil(xpLeft / avgKill))
        elseif atMax then
            ktl = "Max"
        end
    end
    SetStat(ui.statKTL, "KILLS TO LEVEL", ktl, db.showKTL, COLOR.value)

    local qtl = "--"
    if db.showQTL then
        local avgQuest = AverageQuestXP()
        if not atMax and avgQuest > 0 and xpLeft > 0 then
            qtl = tostring(math.ceil(xpLeft / avgQuest))
        elseif atMax then
            qtl = "Max"
        end
    end
    SetStat(ui.statQTL, "QUESTS TO LEVEL", qtl, db.showQTL, COLOR.gold)

    local goldColor = goldPerHour < 0 and COLOR.bad or COLOR.gold
    local sessGoldColor = goldDelta < 0 and COLOR.bad or COLOR.gold
    if db.showGoldHour then
        local goldHourRound = Round(goldPerHour)
        if ui.cachedGoldHourVal ~= goldHourRound then
            ui.cachedGoldHourVal = goldHourRound
            ui.cachedGoldHourText = FormatGoldValue(goldHourRound)
        end
    end
    if db.showGoldSession then
        if ui.cachedGoldDeltaVal ~= goldDelta then
            ui.cachedGoldDeltaVal = goldDelta
            ui.cachedGoldDeltaText = FormatGoldValue(goldDelta)
        end
    end
    SetStat(ui.statGoldHour, "GOLD / HOUR", ui.cachedGoldHourText or "--", db.showGoldHour, goldColor)
    SetStat(ui.statGoldSess, "SESSION GOLD", ui.cachedGoldDeltaText or "--", db.showGoldSession, sessGoldColor)

    local info = self:GetWatchedFaction()
    if info then
        local sessionRep = RepTrackValue(info) - (session.startingRep or 0)
        local repPerHour = RatePerHour(sessionRep, elapsed)
        local nextRemain = RemainingToNextRank(info)
        local maxRemain, maxLabel = RemainingToMax(info)
        SetStat(ui.statRepHour, "REP / HOUR", sessionRep > 0 and FormatCompact(repPerHour) or "--", db.showRepHour, COLOR.rep)
        SetStat(ui.statRepSess, "SESSION REP", sessionRep ~= 0 and FormatCompact(sessionRep) or "--", db.showRepSession, COLOR.rep)
        local nextText = (info.isMaxRank or nextRemain <= 0) and "Max" or FormatClock(TimeFromRate(nextRemain, repPerHour))
        local maxText = (info.isMaxRank or maxRemain <= 0) and "Max" or FormatClock(TimeFromRate(maxRemain, repPerHour))
        local maxName = string.upper(maxLabel or "MAX")
        if db.showRepNextRank and db.showRepExalted then
            SetStat(ui.statNextRank, "NEXT / " .. maxName, nextText .. " / " .. maxText, true, COLOR.rep)
        elseif db.showRepNextRank then
            SetStat(ui.statNextRank, "NEXT RANK", nextText, true, COLOR.rep)
        elseif db.showRepExalted then
            SetStat(ui.statNextRank, maxName, maxText, true, COLOR.rep)
        else
            SetStat(ui.statNextRank, "NEXT RANK", "--", false, COLOR.rep)
        end
    else
        SetStat(ui.statRepHour, "REP / HOUR", "--", db.showRepHour, COLOR.rep)
        SetStat(ui.statRepSess, "SESSION REP", "--", db.showRepSession, COLOR.rep)
        if db.showRepNextRank and db.showRepExalted then
            SetStat(ui.statNextRank, "NEXT / EXALTED", "-- / --", true, COLOR.rep)
        elseif db.showRepNextRank then
            SetStat(ui.statNextRank, "NEXT RANK", "--", true, COLOR.rep)
        elseif db.showRepExalted then
            SetStat(ui.statNextRank, "EXALTED", "--", true, COLOR.rep)
        else
            SetStat(ui.statNextRank, "NEXT RANK", "--", false, COLOR.rep)
        end
    end

    if ui.statsVisibilityDirty then
        ui.statsVisibilityDirty = false
        ui.gridLayoutWidth = nil
        LayoutStatsGrid()
    end
end

function FBT:Refresh()
    self:RefreshHeader()
    if IsSeparateStatsMode() or ShouldShowEmbeddedStats() then
        self:RefreshStats()
    end
end

function FBT:RequestRefresh(statsOnly)
    if statsOnly then
        refreshStats = true
    else
        refreshHeader = true
        refreshStats = true
    end
    if refreshQueued then
        return
    end
    refreshQueued = true
    if not (C_Timer and C_Timer.After) then
        refreshQueued = false
        refreshHeader = false
        refreshStats = false
        self:Refresh()
        return
    end
    C_Timer.After(0, function()
        refreshQueued = false
        local doHeader = refreshHeader
        local doStats = refreshStats
        refreshHeader = false
        refreshStats = false
        if not FBT.db or not ui.card then
            return
        end
        if doHeader then
            FBT:RefreshHeader()
        end
        if doStats and (IsSeparateStatsMode() or ShouldShowEmbeddedStats()) then
            FBT:RefreshStats()
        end
    end)
end

local function ReparentStatsTo(parent, hostFrame)
    if not ui.stats or not parent then
        return
    end
    ui.stats:SetParent(parent)
    ui.statsHost = hostFrame or parent
    ui.gridLayoutWidth = nil
    if ui.panel and parent == ui.panel then
        ui.stats:ClearAllPoints()
        ui.stats:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -28)
        ui.stats:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -PAD, 20)
        LayoutStatsGrid()
    end
end

function FBT:ApplyStatsDisplayMode()
    if not ui.card or not self.db then
        return
    end
    local separate = IsSeparateStatsMode()
    if separate then
        if not ui.panel then
            self:CreateStatsPanel()
        end
        self:SetExpanded(false)
        ReparentStatsTo(ui.panel, ui.panel)
        ui.stats:SetAlpha(1)
        ui.stats:Show()
        SetStatsInteractive(true)
        ui.panel:Show()
        self:RestorePanelPosition()
        if ui.panelGrip then
            ui.panelGrip:SetShown(not self.db.panelLocked)
        end
    else
        if ui.panel then
            ui.panel:Hide()
        end
        ReparentStatsTo(ui.card, ui.card)
        self:UpdateFrameOrientation(self:ResolveGrowthDirection(false), false)
        if self.db.expandTrigger == "HOVER" and not self:IsHoverOverUI() then
            self:SetExpanded(false)
        elseif ui.expanded then
            ui.stats:Show()
            self:RefreshStats()
            EnsureAnim()
        else
            ui.stats:Hide()
            ui.stats:SetAlpha(0)
            SetStatsInteractive(false)
            ui.currentHeight = CardCollapsedHeight()
            ui.targetHeight = CardCollapsedHeight()
            ui.card:SetHeight(CardCollapsedHeight())
        end
    end
    self:RefreshStats()
    if ui.moversUnlocked and self.ShowMoverChrome then
        self:ShowMoverChrome()
    end
end

function FBT:ApplySettings(key)
    if self.SyncProfileDB then
        self:SyncProfileDB()
    end
    if not ui.card or not self.db then
        return
    end
    if self.db.enabled == false and (key == nil or key == "enabled") then
        self:ApplyVisibility()
        return
    end
    if key == nil or key == "barStyle" or key == "xpColor" or key == "restedColor" or key == "repColor" then
        ui.barKind = nil
        self:ApplyChrome()
    end
    if key == nil or key == "cardHeight" then
        self:ApplyCardHeight()
    end
    if key == nil or key == "scale" then
        self:ApplyScale()
    end
    if key == "autoTrackRep" then
        factionScanReady = false
    end
    -- Visual toggles should not re-anchor the card. Position, lock, and
    -- growth still restore from saved points.
    if key == nil or key == "growthDirection" or key == "isLocked" then
        self:RestoreCardPosition()
    end
    if key == nil or key == "panelLocked" or key == "statsDisplayMode" then
        if ui.panel then
            self:RestorePanelPosition()
        end
    end
    if ui.grip and (key == nil or key == "isLocked") then
        ui.grip:SetShown(ui.moversUnlocked or not self.db.isLocked)
    end
    if ui.panelGrip and (key == nil or key == "panelLocked" or key == "statsDisplayMode") then
        ui.panelGrip:SetShown((ui.moversUnlocked or not self.db.panelLocked) and IsSeparateStatsMode())
    end
    if key == nil or key == "statsDisplayMode" then
        self:ApplyStatsDisplayMode()
    end
    if (key == nil or key == "expandTrigger") and self.db.expandTrigger == "HOVER" and not self:IsHoverOverUI() then
        if not IsSeparateStatsMode() then
            self:SetExpanded(false)
        end
    end
    if key == "showXPBar" or key == "showRepBar" then
        ui.headerBarMode = nil
        ui.barKind = nil
        ui.repCur = nil
        ui.repMax = nil
    end
    if key == nil or key == "enabled" then
        self:ApplyVisibility()
    end
    self:Refresh()
end

function FBT:ToggleLock()
    local db = self.db
    if not db then
        return
    end
    local Lib = _G.XiusCoreSettingsLib
    if IsSeparateStatsMode() then
        db.panelLocked = not db.panelLocked
        self:ApplySettings("panelLocked")
        if db.panelLocked then
            self:SetFrameMovers(false)
            if Lib and Lib.NoteFramesLocked then
                Lib:NoteFramesLocked()
            end
            self:Print("Stats box locked.")
        else
            self:Print("Stats box unlocked.")
        end
        return
    end
    db.isLocked = not db.isLocked
    self:ApplySettings("isLocked")
    if db.isLocked then
        self:SetFrameMovers(false)
        if Lib and Lib.NoteFramesLocked then
            Lib:NoteFramesLocked()
        end
        self:Print("Card locked.")
    else
        self:Print("Card unlocked.")
    end
end

function FBT:ResetSession()
    session.startTime = GetTime()
    session.xpEarned = 0
    session.killXP = {}
    session.questXP = {}
    session.avgKillXP = 0
    session.avgQuestXP = 0
    session.awaitNewLevelXP = nil
    session.moneyReady = false
    session.startMoney = 0
    EnsureMoneyBaseline()
    SnapshotXP()
    CacheFactionBaseline(true)
    self:Print("Session timers, XP, gold, quests, and reputation baselines have been reset.")
    self:Refresh()
end

function FBT:StartSession()
    if self.db and self.db.enabled == false then
        self:RestoreBlizzardTrackingBars()
    else
        self:HideBlizzardTrackingBars(true)
    end
    if session.active then
        CacheFactionBaseline(false)
        EnsureMoneyBaseline()
        if OnXPUpdate then
            OnXPUpdate()
        else
            SnapshotXP()
            self:Refresh()
        end
        return
    end
    session.startTime = GetTime()
    session.xpEarned = 0
    session.killXP = {}
    session.questXP = {}
    session.avgKillXP = 0
    session.avgQuestXP = 0
    session.awaitNewLevelXP = nil
    session.moneyReady = false
    session.startMoney = 0
    EnsureMoneyBaseline()
    SnapshotXP()
    session.active = true
    CacheFactionBaseline(true)
    RequestPlayedTime(true)
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if C_Timer and C_Timer.NewTicker then
        local sweep = 0
        ticker = C_Timer.NewTicker(1.0, function()
            TickCareerActiveTime()
            local cardShown = ui.card and ui.card:IsShown()
            if not ui.card or ValueHidden(cardShown) or not cardShown then
                return
            end
            sweep = sweep + 1
            if sweep >= 5 then
                sweep = 0
                FBT:HideBlizzardTrackingBars()
            end
            local xpShown = ui.xpBar and ui.xpBar:IsShown()
            if ui.xpBar and not ValueHidden(xpShown) and xpShown then
                local restNow = CurrentRestXP()
                if ui.restSeen ~= restNow then
                    ui.restSeen = restNow
                    FBT:UpdateRestedOverlay()
                end
            end
            if IsSeparateStatsMode() or ui.expanded then
                FBT:RefreshStats()
            end
        end)
    end
    self:Refresh()
end

OpenSettingsFromUI = function()
    if FBT.OpenOptions then
        FBT:OpenOptions()
    end
end

OnCardEnter = function()
    local db = FBT.db
    if not db or db.expandTrigger ~= "HOVER" or IsSeparateStatsMode() then
        return
    end
    hideToken = hideToken + 1
    FBT:SetExpanded(true)
end

OnCardLeave = function()
    local db = FBT.db
    if not db or db.expandTrigger ~= "HOVER" or IsSeparateStatsMode() then
        return
    end
    FBT:ScheduleCollapse()
end

local function OnCardMouseDown(_, button)
    local db = FBT.db
    if not db then
        return
    end
    if button == "RightButton" then
        if IsOverStatsButton() then
            return
        end
        OpenSettingsFromUI()
        return
    end
    if button ~= "LeftButton" then
        return
    end
    if IsOverStatsButton() then
        return
    end
    if ui.grip and ui.grip:IsShown() and FrameIsMouseOver(ui.grip) then
        return
    end
    if ui.moversUnlocked and not (InCombatLockdown and InCombatLockdown()) then
        ui.moving = true
        ui.card:StartMoving()
        EnsureAnim()
        return
    end
    if not IsSeparateStatsMode() and db.expandTrigger == "CLICK" then
        FBT:ToggleExpanded()
    end
end

OnCardDragStop = function()
    if not ui.moving then
        return
    end
    ui.moving = false
    ui.card:StopMovingOrSizing()
    FBT:UpdateFrameOrientation(FBT:ResolveGrowthDirection(true), true)
    SavePosition()
end

local function OnCardMouseUp(_, button)
    if button == "LeftButton" then
        OnCardDragStop()
    end
end

local function OnPanelMouseDown(_, button)
    local db = FBT.db
    if not db then
        return
    end
    if button == "RightButton" then
        if IsOverStatsButton() then
            return
        end
        OpenSettingsFromUI()
        return
    end
    if button ~= "LeftButton" then
        return
    end
    if IsOverStatsButton() then
        return
    end
    if ui.panelGrip and ui.panelGrip:IsShown() and FrameIsMouseOver(ui.panelGrip) then
        return
    end
    if ui.moversUnlocked and not (InCombatLockdown and InCombatLockdown()) then
        ui.panelMoving = true
        ui.panel:StartMoving()
        ui.panel:SetScript("OnUpdate", PanelOnUpdate)
    end
end

OnPanelDragStop = function()
    if not ui.panelMoving then
        return
    end
    ui.panelMoving = false
    ui.panel:StopMovingOrSizing()
    SavePanelPosition()
end

local function OnPanelMouseUp(_, button)
    if button == "LeftButton" then
        OnPanelDragStop()
    end
end

local function BuildStatsContent(parent)
    local stats = CreateFrame("Frame", nil, parent)
    stats:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -PAD)
    stats:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -PAD, PAD)
    stats:SetAlpha(0)
    stats:Hide()

    local function MakeActionButton(label, width)
        local btn = CreateFrame("Button", nil, stats, "BackdropTemplate")
        btn:SetSize(width, 18)
        StyleMeterButton(btn, function(_, entering)
            if entering then
                OnCardEnter()
            else
                OnCardLeave()
            end
        end)
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER", 0, 0)
        SetFont(text, GameFontNormalSmall, 10)
        text:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3], 1)
        text:SetText(label)
        btn:EnableMouse(false)
        return btn
    end

    local resetBtn = MakeActionButton("Reset Session", 108)
    resetBtn:SetPoint("TOPLEFT", 0, 0)
    resetBtn:RegisterForClicks("LeftButtonUp")
    resetBtn:SetScript("OnClick", function()
        FBT:ResetSession()
    end)

    local settingsBtn = MakeGearButton(stats, 18, true)
    settingsBtn:SetPoint("LEFT", resetBtn, "RIGHT", 6, 0)
    settingsBtn:EnableMouse(false)

    local grid = CreateFrame("Frame", nil, stats)
    grid:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 0, -8)
    grid:SetPoint("BOTTOMRIGHT", stats, "BOTTOMRIGHT", 0, 4)

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

    local statQTL = MakeStat(cols[4])
    local statRepSess = MakeStat(cols[4])
    PlacePair(cols[4], statQTL, statRepSess)

    local statGoldHour = MakeStat(cols[5])
    local statGoldSess = MakeStat(cols[5])
    PlacePair(cols[5], statGoldHour, statGoldSess)

    local statRepHour = MakeStat(cols[6])
    local statNextRank = MakeStat(cols[6])
    PlacePair(cols[6], statRepHour, statNextRank)

    local statTimeLevel = MakeStat(cols[7])
    local statTimePlayed = MakeStat(cols[7])
    PlacePair(cols[7], statTimeLevel, statTimePlayed)

    local statOverallTTL = MakeStat(cols[8])
    statOverallTTL:SetParent(cols[8])
    statOverallTTL:ClearAllPoints()
    statOverallTTL:SetPoint("TOPLEFT", cols[8], "TOPLEFT", 0, 0)
    statOverallTTL:SetPoint("RIGHT", cols[8], "RIGHT", 0, 0)
    cols[8].statTop = statOverallTTL
    cols[8].statBottom = nil
    statOverallTTL:EnableMouse(false)
    statOverallTTL:SetScript("OnEnter", function(self)
        if OnCardEnter then
            OnCardEnter()
        end
        if not ui.statsInteractive then
            return
        end
        local careerStr = (ui.careerPaceRate or 0) > 0 and (FormatCompact(ui.careerPaceRate) .. "/hr") or "--"
        local sessionStr = (ui.careerSessionRate or 0) > 0 and (FormatCompact(ui.careerSessionRate) .. "/hr") or "--"
        local blendStr = (ui.careerBlendedRate or 0) > 0 and (FormatCompact(ui.careerBlendedRate) .. "/hr") or "--"
        local body = string.format(
            "XP-weighted career pace blended with current session.\nCareer Pace: %s (%d lvl)\nSession Rate: %s\nBlended Pace: %s",
            careerStr,
            ui.careerLevelsCount or 0,
            sessionStr,
            blendStr
        )
        FBT:ShowTooltip(self, "Overall Pace / Career TTL", body)
    end)
    statOverallTTL:SetScript("OnLeave", function()
        FBT:HideTooltip()
        if OnCardLeave then
            OnCardLeave()
        end
    end)

    ui.stats = stats
    ui.resetBtn = resetBtn
    ui.settingsBtn = settingsBtn
    ui.statSessionXP = statSessionXP
    ui.statSessionTime = statSessionTime
    ui.statRested = statRested
    ui.statTTL = statTTL
    ui.statOverallTTL = statOverallTTL
    ui.statXPHour = statXPHour
    ui.statKTL = statKTL
    ui.statQTL = statQTL
    ui.statGoldHour = statGoldHour
    ui.statGoldSess = statGoldSess
    ui.statRepHour = statRepHour
    ui.statNextRank = statNextRank
    ui.statRepSess = statRepSess
    ui.statTimeLevel = statTimeLevel
    ui.statTimePlayed = statTimePlayed
    ui.allStats = {
        statSessionXP, statSessionTime,
        statRested, statTTL,
        statOverallTTL,
        statXPHour, statKTL,
        statQTL, statRepSess,
        statGoldHour, statGoldSess,
        statRepHour, statNextRank,
        statTimeLevel, statTimePlayed,
    }
    return stats
end

local function MoverColor()
    local core = _G.XiusCore
    local accent = core and core.Media and core.Media.accent
    if type(accent) == "table" then
        return accent[1] or 1, accent[2] or 0.82, accent[3] or 0
    end
    return 1, 0.82, 0
end

local function BindMoverOverlay(host, kind)
    if not host then
        return nil
    end
    if host.xiusMover then
        return host.xiusMover
    end
    local overlay = CreateFrame("Frame", nil, host, "BackdropTemplate")
    overlay:SetAllPoints(host)
    overlay:SetFrameLevel((host:GetFrameLevel() or 0) + 40)
    overlay:EnableMouse(true)
    overlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    overlay:SetBackdropColor(0.04, 0.03, 0.01, 0.28)
    local text = overlay:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    SetFont(text, GameFontHighlight, 12, "OUTLINE")
    overlay.label = text
    overlay:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or not ui.moversUnlocked then
            return
        end
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        if kind == "card" then
            ui.moving = true
            host:StartMoving()
            EnsureAnim()
        else
            ui.panelMoving = true
            host:StartMoving()
            host:SetScript("OnUpdate", PanelOnUpdate)
        end
    end)
    overlay:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then
            return
        end
        if kind == "card" then
            OnCardDragStop()
        else
            OnPanelDragStop()
        end
    end)
    overlay:Hide()
    host.xiusMover = overlay
    return overlay
end

function FBT:RefreshMoverChrome()
    local r, g, b = MoverColor()
    local function Paint(host, caption, kind)
        local overlay = BindMoverOverlay(host, kind)
        if not overlay then
            return
        end
        overlay.label:SetText(caption)
        overlay.label:SetTextColor(r, g, b, 1)
        overlay:SetBackdropBorderColor(r, g, b, 1)
    end
    Paint(ui.card, "XP / Rep\nDrag to move", "card")
    Paint(ui.panel, "XP Stats\nDrag to move", "panel")
end

function FBT:ShowMoverChrome()
    self:RefreshMoverChrome()
    if ui.card and ui.card.xiusMover then
        if not ui.card:IsShown() then
            ui.card:Show()
        end
        ui.card.xiusMover:Show()
        if ui.grip then
            ui.grip:SetFrameLevel(ui.card.xiusMover:GetFrameLevel() + 2)
            ui.grip:Show()
        end
    end
    if ui.panel and ui.panel.xiusMover then
        if IsSeparateStatsMode() then
            if not ui.panel:IsShown() then
                ui.panel:Show()
            end
            ui.panel.xiusMover:Show()
            if ui.panelGrip then
                ui.panelGrip:SetFrameLevel(ui.panel.xiusMover:GetFrameLevel() + 2)
                ui.panelGrip:Show()
            end
        else
            ui.panel.xiusMover:Hide()
        end
    end
end

function FBT:HideMoverChrome()
    if ui.card and ui.card.xiusMover then
        ui.card.xiusMover:Hide()
    end
    if ui.panel and ui.panel.xiusMover then
        ui.panel.xiusMover:Hide()
    end
end

function FBT:SetFrameMovers(unlocked)
    unlocked = unlocked and true or false
    if not ui.card then
        self.pendingMovers = unlocked
        return
    end
    local was = ui.moversUnlocked and true or false
    if was == unlocked then
        if unlocked then
            self:ShowMoverChrome()
        end
        return
    end
    ui.moversUnlocked = unlocked
    if unlocked then
        self:ShowMoverChrome()
        return
    end
    if ui.moving then
        OnCardDragStop()
    end
    if ui.panelMoving then
        OnPanelDragStop()
    end
    SavePosition()
    if ui.panel then
        SavePanelPosition()
    end
    self:HideMoverChrome()
    if self.db and self.db.enabled == false then
        self:ApplyVisibility()
    end
    if ui.grip then
        ui.grip:SetShown(not (self.db and self.db.isLocked))
    end
    if ui.panelGrip then
        ui.panelGrip:SetShown((not (self.db and self.db.panelLocked)) and IsSeparateStatsMode())
    end
end

function FBT:RegisterFrameMovers()
    local core = _G.XiusCore or _G.XiusCoreSettingsLib
    if not core or not core.RegisterMover or not ui.card then
        return
    end
    core:RegisterMover("xp", ui.card, "XP / Rep", function(isUnlocked)
        FBT:SetFrameMovers(isUnlocked and true or false)
    end)
    if ui.panel then
        core:RegisterMover("xpPanel", ui.panel, "XP Stats", function(isUnlocked)
            FBT:SetFrameMovers(isUnlocked and true or false)
        end)
    end
    if self.pendingMovers ~= nil then
        local pending = self.pendingMovers
        self.pendingMovers = nil
        self:SetFrameMovers(pending)
    end
end

function FBT:CreateStatsPanel()
    if ui.panel then
        return
    end

    local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetFrameStrata("MEDIUM")
    panel:SetFrameLevel(85)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:SetResizable(true)
    if panel.SetResizeBounds then
        panel:SetResizeBounds(PANEL_MIN_WIDTH, PANEL_HEIGHT, PANEL_MAX_WIDTH, PANEL_HEIGHT + 20)
    else
        if panel.SetMinResize then
            panel:SetMinResize(PANEL_MIN_WIDTH, PANEL_HEIGHT)
        end
        if panel.SetMaxResize then
            panel:SetMaxResize(PANEL_MAX_WIDTH, PANEL_HEIGHT + 20)
        end
    end
    panel:EnableMouse(true)
    if panel.SetDontSavePosition then
        panel:SetDontSavePosition(true)
    end
    ApplyCardBackdrop(panel)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    panel:Hide()

    local title = panel:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", 10, -7)
    SetFont(title, GameFontNormal, 12)
    title:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3], 1)
    title:SetText("Session Stats")
    ui.panelTitle = title

    local grip = CreateFrame("Frame", nil, panel)
    grip:SetSize(6, 14)
    grip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    grip:EnableMouse(true)
    grip:SetFrameLevel(panel:GetFrameLevel() + 5)
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetColorTexture(1, 1, 1, 0.12)
    gripTex:SetAllPoints()
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or (FBT.db and FBT.db.panelLocked) then
            return
        end
        local startX = GetCursorPosition()
        local startW = panel:GetWidth()
        local startScale = panel:GetEffectiveScale()
        if ValueHidden(startX) or ValueHidden(startW) or ValueHidden(startScale) then
            return
        end
        ui.panelSizing = true
        ui.panelSizeStartX = startX
        ui.panelSizeStartW = startW
        ui.panelSizeScale = startScale
        panel:SetScript("OnUpdate", PanelOnUpdate)
    end)

    panel:SetScript("OnMouseDown", OnPanelMouseDown)
    panel:SetScript("OnMouseUp", OnPanelMouseUp)
    panel:SetScript("OnHide", function()
        if ui.panelMoving then
            OnPanelDragStop()
        end
        if ui.panelSizing then
            ui.panelSizing = false
            SavePanelPosition()
            panel:SetScript("OnUpdate", nil)
        end
    end)
    panel:SetScript("OnSizeChanged", function()
        ui.gridLayoutWidth = nil
        LayoutStatsGrid()
    end)

    ui.panel = panel
    ui.panelGrip = grip
end

function FBT:CreateUI()
    if ui.card then
        return
    end

    local card = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    card:SetSize(self.db and self.db.width or CARD_WIDTH, CardCollapsedHeight())
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
    -- Do not leave the card at CreateFrame's default CENTER of UIParent.
    -- RestoreCardPosition immediately overwrites this with SavedVariables.
    card:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)

    local header = CreateFrame("Frame", nil, card)
    header:SetPoint("TOPLEFT", PAD, -PAD)
    header:SetPoint("TOPRIGHT", -PAD, -PAD)
    header:SetHeight(HEADER_H)

    local badge = CreateFrame("Button", nil, header, "BackdropTemplate")
    badge:SetSize(BADGE_SIZE, BADGE_SIZE)
    badge:SetPoint("LEFT", 0, 0)
    badge:SetBackdrop(BADGE_BACKDROP)
    badge:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    badge:SetBackdropBorderColor(212 / 255, 175 / 255, 55 / 255, 1)
    badge:EnableMouse(true)
    badge:RegisterForClicks("LeftButtonUp")
    badge:SetScript("OnEnter", function(self)
        if OnCardEnter then
            OnCardEnter()
        end
        ShowBadgeTooltip(self)
    end)
    badge:SetScript("OnLeave", function()
        FBT:HideTooltip()
        if OnCardLeave then
            OnCardLeave()
        end
    end)
    badge:SetScript("OnClick", function(self)
        if ui.barKind == "rep" then
            ToggleFactionPicker(self)
        elseif FBT.db and not IsSeparateStatsMode() and FBT.db.expandTrigger == "CLICK" then
            FBT:ToggleExpanded()
        end
    end)
    local gloss = badge:CreateTexture(nil, "ARTWORK")
    gloss:SetPoint("TOPLEFT", 4, -4)
    gloss:SetPoint("TOPRIGHT", -4, -4)
    gloss:SetHeight(1)
    gloss:SetColorTexture(1, 0.92, 0.7, 0.35)
    local levelText = badge:CreateFontString(nil, "OVERLAY")
    levelText:SetPoint("CENTER", 0, 0)
    SetFont(levelText, GameFontNormalLarge, 16, "OUTLINE")
    levelText:SetTextColor(1, 209 / 255, 0, 1)
    levelText:SetText("1")

    local barColumn = CreateFrame("Frame", nil, header)
    barColumn:SetPoint("LEFT", badge, "RIGHT", 10, 0)
    barColumn:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    barColumn:SetPoint("TOP", header, "TOP", 0, 0)
    barColumn:SetPoint("BOTTOM", header, "BOTTOM", 0, 0)

    local leftLabel = barColumn:CreateFontString(nil, "OVERLAY")
    leftLabel:SetPoint("TOPLEFT", 0, -1)
    SetFont(leftLabel, GameFontHighlightSmall, 11)
    leftLabel:SetTextColor(1, 1, 1, 1)
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

    ui.card = card
    ui.header = header
    ui.badge = badge
    ui.levelText = levelText
    ui.barColumn = barColumn
    ui.leftLabel = leftLabel
    ui.rightPct = rightPct
    ui.xpBar = xpBar
    ui.repBar = repBar
    ui.expanded = false
    ui.currentHeight = CardCollapsedHeight()
    ui.targetHeight = CardCollapsedHeight()
    ui.growUp = true
    ui.statsHost = card

    BuildStatsContent(card)
    self:CreateStatsPanel()

    local grip = CreateFrame("Frame", nil, card)
    grip:SetSize(6, 14)
    grip:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
    grip:EnableMouse(true)
    grip:SetFrameLevel(card:GetFrameLevel() + 5)
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetColorTexture(1, 1, 1, 0.12)
    gripTex:SetAllPoints()
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or (FBT.db and FBT.db.isLocked) then
            return
        end
        local startX = GetCursorPosition()
        local startW = card:GetWidth()
        local startScale = card:GetEffectiveScale()
        if ValueHidden(startX) or ValueHidden(startW) or ValueHidden(startScale) then
            return
        end
        ui.sizing = true
        ui.sizeStartX = startX
        ui.sizeStartW = startW
        ui.sizeScale = startScale
        EnsureAnim()
    end)
    grip:SetScript("OnEnter", OnCardEnter)
    grip:SetScript("OnLeave", OnCardLeave)
    ui.grip = grip

    card:SetScript("OnEnter", OnCardEnter)
    card:SetScript("OnLeave", OnCardLeave)
    card:SetScript("OnMouseDown", OnCardMouseDown)
    card:SetScript("OnMouseUp", OnCardMouseUp)
    card:SetScript("OnHide", function()
        CloseFactionPicker()
        if ui.moving then
            OnCardDragStop()
        end
        if ui.sizing then
            ui.sizing = false
            SavePosition()
        end
    end)
    ui.stats:SetScript("OnEnter", OnCardEnter)
    ui.stats:SetScript("OnLeave", OnCardLeave)

    self:RestoreCardPosition()
    LayoutStatsGrid()
    card:SetScript("OnSizeChanged", function(_, width)
        if ui.cardLayoutWidth == width then
            return
        end
        ui.cardLayoutWidth = width
        LayoutStatsGrid()
    end)
    if ui.grip then
        ui.grip:SetShown(not (self.db and self.db.isLocked))
    end
    self:ApplyChrome()
    self:ApplyCardHeight()
    self:ApplyScale()
    if self.db and self.db.enabled == false then
        self:ApplyVisibility()
    else
        self:HideBlizzardTrackingBars()
        self:ApplyStatsDisplayMode()
        self:Refresh()
    end
    self:RegisterFrameMovers()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            FBT:RestoreCardPosition()
            if IsSeparateStatsMode() then
                FBT:RestorePanelPosition()
                EnsureSeparateStatsAnchored()
            end
        end)
    end
end

function OnXPUpdate(overrideLevel)
    if not session.active then
        return
    end
    local xp = PublicNumber(UnitXP("player"), session.lastXP or 0)
    local level = PublicNumber(UnitLevel("player"), session.lastLevel or 1)
    overrideLevel = PublicNumber(overrideLevel, 0)
    if overrideLevel > level then
        level = overrideLevel
    end
    local maxXP = PublicNumber(UnitXPMax("player"), session.lastXPMax or 1)
    if maxXP <= 0 then
        maxXP = 1
    end
    local lastXP = session.lastXP or 0
    local lastLevel = session.lastLevel or level
    local lastMax = session.lastXPMax or maxXP

    -- If PLAYER_XP_UPDATE fires right as XP wraps around on level-up before UnitLevel increments,
    -- infer the level-up so lastXP/lastMax are not overwritten before PLAYER_LEVEL_UP arrives.
    if level == lastLevel and xp < lastXP and maxXP > lastMax then
        level = lastLevel + 1
    end

    local deltaGained = 0
    if level > lastLevel then
        local gained = math.max(0, lastMax - lastXP)
        -- Both XP and the bar max still match the pre-ding snapshot, so UnitXP
        -- has not moved to the new level yet. Count that XP on the next update.
        if xp == lastXP and maxXP == lastMax then
            session.awaitNewLevelXP = true
        else
            gained = gained + math.max(0, xp)
            session.awaitNewLevelXP = nil
        end
        deltaGained = gained
        session.xpEarned = (session.xpEarned or 0) + gained
        RecordCareerXP(lastLevel, math.max(0, lastMax - lastXP), lastMax)
        if not session.awaitNewLevelXP and xp > 0 then
            RecordCareerXP(level, xp, maxXP)
        end
    elseif level < lastLevel then
        session.awaitNewLevelXP = nil
    elseif session.awaitNewLevelXP and (xp ~= lastXP or maxXP ~= lastMax) then
        deltaGained = math.max(0, xp)
        session.xpEarned = (session.xpEarned or 0) + deltaGained
        session.awaitNewLevelXP = nil
        RecordCareerXP(level, deltaGained, maxXP)
    elseif xp > lastXP then
        deltaGained = xp - lastXP
        session.xpEarned = (session.xpEarned or 0) + deltaGained
        RecordCareerXP(level, deltaGained, maxXP)
    end

    if deltaGained > 0 then
        local now = GetTime()
        if session.pendingSecretKillAt and (now - session.pendingSecretKillAt) < 0.35 then
            session.pendingSecretKillAt = nil
            session.lastUnclaimedXPGain = nil
            AddKillXP(deltaGained)
        else
            session.lastUnclaimedXPGain = deltaGained
            session.lastUnclaimedXPAt = now
        end
    end

    session.lastXP = xp
    session.lastLevel = level
    session.lastXPMax = maxXP
    FBT:RequestRefresh()
end

local function FactionTotal()
    if C_Reputation and C_Reputation.GetNumFactions then
        local ok, count = pcall(C_Reputation.GetNumFactions)
        if ok and type(count) == "number" and not ValueHidden(count) then
            return count
        end
    end
    if GetNumFactions then
        local ok, count = pcall(GetNumFactions)
        if ok and type(count) == "number" and not ValueHidden(count) then
            return count
        end
    end
    return 0
end

local function FactionRow(index)
    if C_Reputation and C_Reputation.GetFactionDataByIndex then
        local data = C_Reputation.GetFactionDataByIndex(index)
        if type(data) == "table" and not ValueHidden(data) then
            local id = data.factionID
            local standing = data.currentStanding
            if ValueHidden(id) or type(id) ~= "number" then
                id = 0
            end
            if ValueHidden(standing) or type(standing) ~= "number" then
                standing = nil
            end
            local header = (not ValueHidden(data.isHeader)) and data.isHeader and true or false
            local watched = (not ValueHidden(data.isWatched)) and data.isWatched and true or false
            local reaction = (not ValueHidden(data.reaction)) and type(data.reaction) == "number" and data.reaction or 0
            local nextThreshold = (not ValueHidden(data.nextReactionThreshold)) and type(data.nextReactionThreshold) == "number" and data.nextReactionThreshold or nil
            local isMaxed = reaction >= 8 and standing ~= nil and nextThreshold ~= nil and standing >= nextThreshold
            return id, standing, header, watched, isMaxed
        end
    end
    if not GetFactionInfo then
        return nil
    end
    local _, _, standingID, _, barMax, barValue, _, _, isHeader, _, _, isWatched, _, factionID = GetFactionInfo(index)
    if ValueHidden(barValue) or ValueHidden(isHeader) or ValueHidden(factionID) then
        return nil
    end
    if type(factionID) ~= "number" then
        factionID = 0
    end
    if type(barValue) ~= "number" then
        barValue = nil
    end
    local reaction = (not ValueHidden(standingID)) and type(standingID) == "number" and standingID or 0
    local maxV = (not ValueHidden(barMax)) and type(barMax) == "number" and barMax or nil
    local isMaxed = reaction >= 8 and barValue ~= nil and maxV ~= nil and barValue >= maxV
    return factionID, barValue, isHeader and true or false, (not ValueHidden(isWatched)) and isWatched and true or false, isMaxed
end

local function WatchFaction(index, factionID)
    if factionID and factionID > 0 and C_Reputation and C_Reputation.SetWatchedFactionByID then
        if pcall(C_Reputation.SetWatchedFactionByID, factionID) then
            return
        end
    end
    if SetWatchedFactionIndex and index then
        pcall(SetWatchedFactionIndex, index)
    end
end

local function TrackReputationGain()
    if not FBT.db or not FBT.db.autoTrackRep then
        factionScanReady = false
        return
    end
    if FBT.db.autoTrackRepOnlyOutOfCombat and InCombatLockdown and InCombatLockdown() then
        return
    end
    local ignoreMaxed = FBT.db.autoTrackRepIgnoreExalted ~= false
    local bestIndex, bestID
    local count = FactionTotal()
    for i = 1, count do
        local id, standing, isHeader, isWatched, isMaxed = FactionRow(i)
        if id and id > 0 and not isHeader and type(standing) == "number" then
            local previous = factionStanding[id]
            factionStanding[id] = standing
            if factionScanReady and previous and standing > previous and not isWatched and not (ignoreMaxed and isMaxed) then
                bestIndex = i
                bestID = id
            end
        end
    end
    factionScanReady = true
    if not bestID then
        return
    end
    WatchFaction(bestIndex, bestID)
    watchedCache = nil
    watchedCacheValid = false
end

local function SafeRegisterEvent(frame, eventName)
    if C_EventUtils and C_EventUtils.IsEventValid then
        if C_EventUtils.IsEventValid(eventName) then
            frame:RegisterEvent(eventName)
        end
    else
        pcall(frame.RegisterEvent, frame, eventName)
    end
end

function FBT:RegisterTracking()
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_XP_UPDATE")
    f:RegisterEvent("PLAYER_LEVEL_UP")
    f:RegisterEvent("UPDATE_FACTION")
    f:RegisterEvent("PLAYER_MONEY")
    f:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
    f:RegisterEvent("QUEST_TURNED_IN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_UPDATE_RESTING")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("TIME_PLAYED_MSG")
    SafeRegisterEvent(f, "UPDATE_EXHAUSTION")
    SafeRegisterEvent(f, "MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
    SafeRegisterEvent(f, "EDIT_MODE_LAYOUT_UPDATED")
    SafeRegisterEvent(f, "UPDATE_INSTANCE_INFO")
    SafeRegisterEvent(f, "ZONE_CHANGED_NEW_AREA")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_XP_UPDATE" then
            OnXPUpdate()
        elseif event == "PLAYER_LEVEL_UP" then
            local newLevel = ...
            InvalidateMaxLevelCache()
            OnXPUpdate(newLevel)
            session.playedLevel = 0
            session.playedStamp = GetTime()
            RequestPlayedTime(true)
            FBT:EnsureMaxLevelReputation(true)
        elseif event == "TIME_PLAYED_MSG" then
            local total, levelTime = ...
            session.playedTotal = PublicNumber(total, 0)
            session.playedLevel = PublicNumber(levelTime, 0)
            session.playedStamp = GetTime()
            RestorePlayedChatFrames()
            FBT:RequestRefresh(true)
        elseif event == "UPDATE_FACTION" or event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" then
            TrackReputationGain()
            watchedCache = nil
            watchedCacheValid = false
            FBT:EnsureMaxLevelReputation(true)
            CacheFactionBaseline(false)
            FBT:RequestRefresh()
        elseif event == "PLAYER_MONEY" then
            EnsureMoneyBaseline()
            if IsSeparateStatsMode() or ui.expanded then
                FBT:RequestRefresh(true)
            end
        elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
            local amount, isSecret = ParseCombatXP(...)
            if amount then
                session.pendingSecretKillAt = nil
                session.lastUnclaimedXPGain = nil
                AddKillXP(amount)
                if IsSeparateStatsMode() or ui.expanded then
                    FBT:RequestRefresh(true)
                end
            elseif isSecret then
                local now = GetTime()
                local recentQuest = session.lastQuestAt and (now - session.lastQuestAt) < 0.5
                if not recentQuest then
                    if session.lastUnclaimedXPGain and session.lastUnclaimedXPAt and (now - session.lastUnclaimedXPAt) < 0.35 then
                        AddKillXP(session.lastUnclaimedXPGain)
                        session.lastUnclaimedXPGain = nil
                        if IsSeparateStatsMode() or ui.expanded then
                            FBT:RequestRefresh(true)
                        end
                    else
                        session.pendingSecretKillAt = now
                    end
                end
            end
        elseif event == "QUEST_TURNED_IN" then
            MarkCareerActivity()
            local _, xpReward = ...
            xpReward = PublicNumber(xpReward, 0)
            session.lastQuestAt = GetTime()
            session.pendingSecretKillAt = nil
            session.lastUnclaimedXPGain = nil
            if xpReward > 0 then
                AddQuestXP(xpReward)
                if IsSeparateStatsMode() or ui.expanded then
                    FBT:RequestRefresh(true)
                end
            end
        elseif event == "PLAYER_UPDATE_RESTING" or event == "UPDATE_EXHAUSTION" then
            FBT:RequestRefresh()
        elseif event == "PLAYER_ENTERING_WORLD" or event == "UPDATE_INSTANCE_INFO" or event == "ZONE_CHANGED_NEW_AREA" then
            if event ~= "ZONE_CHANGED_NEW_AREA" then
                watchedCache = nil
                watchedCacheValid = false
            end
            if event == "PLAYER_ENTERING_WORLD" then
                InvalidateMaxLevelCache()
                if FBT.SyncProfileDB then
                    FBT:SyncProfileDB()
                end
            end
            SyncInstanceRunTimer()
            if event == "UPDATE_INSTANCE_INFO" or event == "ZONE_CHANGED_NEW_AREA" then
                FBT:RequestRefresh(true)
                return
            end
            FBT:EnsureMaxLevelReputation(true)
            FBT:RestoreCardPosition()
            if IsSeparateStatsMode() then
                FBT:RestorePanelPosition()
                EnsureSeparateStatsAnchored()
            end
            FBT:StartSession()
        elseif event == "PLAYER_REGEN_DISABLED" then
            MarkCareerActivity()
        elseif event == "PLAYER_REGEN_ENABLED" or event == "EDIT_MODE_LAYOUT_UPDATED" then
            if event == "PLAYER_REGEN_ENABLED" then
                MarkCareerActivity()
            end
            if event == "PLAYER_REGEN_ENABLED" and pendingLayout then
                pendingLayout = false
                FBT:RestoreCardPosition()
                if IsSeparateStatsMode() then
                    FBT:RestorePanelPosition()
                end
            end
            FBT:HideBlizzardTrackingBars(true)
        end
    end)
    self.eventFrame = f
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        FBT:InitDB()
        FBT:CreateUI()
        FBT:RegisterTracking()
        FBT:HideBlizzardTrackingBars()
        FBT:RestoreCardPosition()
        if IsSeparateStatsMode() then
            EnsureSeparateStatsAnchored()
        end
        if IsLoggedIn and IsLoggedIn() then
            FBT:StartSession()
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        FBT:RestoreCardPosition()
        if IsSeparateStatsMode() then
            FBT:RestorePanelPosition()
            EnsureSeparateStatsAnchored()
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
