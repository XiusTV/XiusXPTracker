--[[
    Xius XP/Rep Tracker - Core.lua
    Unified HUD card: header + expanding stats (or separate stats box),
    session engine, Blizzard bar replacement.
]]

local ADDON, FBT = ...

local CARD_WIDTH = 720
local HEIGHT_COLLAPSED = 48
local HEIGHT_EXPANDED = 165
local PANEL_WIDTH = 340
local PANEL_HEIGHT = 282
local PANEL_MIN_WIDTH = 280
local PANEL_MAX_WIDTH = 520
local PAD = 8
local BADGE_SIZE = 32
local XP_BAR_H = 8
local REP_BAR_H = 6
local ANIM_SPEED = 12
local HOVER_HIDE_DELAY = 0.3
local KILL_SAMPLE_SIZE = 5
local QUEST_SAMPLE_SIZE = 5
local MIN_WIDTH = 660
local MAX_WIDTH = 1200
local NUM_COLUMNS = 7
local PANEL_COLUMNS = 3
local LEFT_MARGIN = 10
local RIGHT_MARGIN = 10

local COLOR = {
    -- Soft meter-style chrome (closer to Details / default addon panels).
    bg = { 0.04, 0.04, 0.04, 0.82 },
    border = { 0.78, 0.62, 0.18, 0.55 },
    header = { 0.10, 0.10, 0.10, 0.92 },
    gold = { 0.95, 0.82, 0.28 },
    goldDim = { 0.55, 0.45, 0.22 },
    muted = { 0.70, 0.68, 0.64 },
    label = { 0.62, 0.55, 0.35 },
    value = { 0.95, 0.95, 0.95 },
    xp = { 0.541, 0.169, 0.886 }, -- #8A2BE2
    rest = { 0.898, 0.663, 0.235 }, -- #E5A93C
    rep = { 0.36, 0.70, 0.92 },
    trough = { 0.08, 0.08, 0.08, 1 },
    footer = { 0.50, 0.50, 0.50 },
    good = { 0.45, 0.85, 0.50 },
    bad = { 0.90, 0.35, 0.32 },
    btn = { 0.08, 0.08, 0.08, 0.95 },
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

local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local ui = {}
local session = {
    killXP = {},
    questXP = {},
    xpEarned = 0,
    startingRep = 0,
    startMoney = 0,
}
local hideToken = 0
local ticker
local watchedCache
local watchedCacheValid = false
local watchedCacheTime = 0
local watchedInfoTable = {}
local LayoutStatsGrid
local OnXPUpdate
local OnCardEnter
local OnCardLeave
local OnCardDragStop
local OnPanelDragStop
local OpenSettingsFromUI
local refreshQueued = false
local refreshHeader = false
local refreshStats = false
local playedLastRequest = 0
local suppressedChatFrames = {}
local RequestPlayedTime
local RestorePlayedChatFrames

local function PublicNumber(v, fallback)
    if issecretvalue and issecretvalue(v) then
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
    if issecretvalue and issecretvalue(v) then
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

local function GetPlayerMaxLevel()
    if cachedMaxLevel then
        return cachedMaxLevel
    end
    -- Do not cache a fallback while the expansion API exists but is not ready yet.
    local result
    local apiReady = false
    if GetMaxLevelForPlayerExpansion then
        result = GetMaxLevelForPlayerExpansion()
        if not (issecretvalue and issecretvalue(result)) and type(result) == "number" then
            apiReady = true
        end
    elseif GetMaxLevelForLatestExpansion then
        result = GetMaxLevelForLatestExpansion()
        if not (issecretvalue and issecretvalue(result)) and type(result) == "number" then
            apiReady = true
        end
    end
    if not apiReady then
        return PublicNumber(MAX_PLAYER_LEVEL, 70)
    end
    result = PublicNumber(result, 70)
    if result > 0 then
        cachedMaxLevel = result
        return result
    end
    return 70
end

local function IsPlayerMaxLevel()
    return PublicNumber(UnitLevel("player"), 1) >= GetPlayerMaxLevel()
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

local function StandingName(reaction)
    local idx = PublicNumber(reaction, 4)
    local label = PublicString(_G["FACTION_STANDING_LABEL" .. tostring(idx)], nil)
    return label or STANDING_FALLBACK[idx] or "Unknown"
end

local function ApplyFriendship(info)
    if not info or not info.factionID or info.factionID <= 0 then
        return info
    end
    local friend
    local gossip = C_GossipInfo
    if gossip and gossip.GetFriendshipReputation then
        local ok, result = pcall(gossip.GetFriendshipReputation, info.factionID)
        if ok and not (issecretvalue and issecretvalue(result)) and type(result) == "table" then
            friend = result
        end
    end
    if not friend then
        local rep = C_Reputation
        if rep and rep.GetFriendshipReputation then
            local ok, result = pcall(rep.GetFriendshipReputation, info.factionID)
            if ok and not (issecretvalue and issecretvalue(result)) and type(result) == "table" then
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
        if okMajor and not (issecretvalue and issecretvalue(isMajor)) and not isMajor then
            return info
        end
    end
    local MF = C_MajorFactions
    if not (MF and MF.GetMajorFactionData) then
        return info
    end
    local okData, data = pcall(MF.GetMajorFactionData, info.factionID)
    if not okData or (issecretvalue and issecretvalue(data)) or type(data) ~= "table" then
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
        if okMax and not (issecretvalue and issecretvalue(maxed)) then
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
    if not okParagon or (issecretvalue and issecretvalue(isParagon)) or not isParagon then
        return info
    end
    local okInfo, currentValue, threshold = pcall(R.GetFactionParagonInfo, info.factionID)
    if not okInfo then
        return info
    end
    if issecretvalue and (issecretvalue(currentValue) or issecretvalue(threshold)) then
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
    info.isMaxRank = false
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
        if ok and not (issecretvalue and issecretvalue(data)) and type(data) == "table" then
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

local function AverageQuestXP()
    local list = session.questXP
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

local function AddQuestXP(amount)
    if not amount or amount <= 0 then
        return
    end
    session.questXP = session.questXP or {}
    session.questXP[#session.questXP + 1] = amount
    if #session.questXP > QUEST_SAMPLE_SIZE then
        table.remove(session.questXP, 1)
    end
end

local function ParseCombatXP(msg)
    -- In WoW Forever and Modern WoW 12.x, combat XP lines from mob deaths embed the
    -- enemy's secret name, making the message a secret string. Quest XP has no mob name.
    if issecretvalue and issecretvalue(msg) then
        return nil, true
    end
    if type(msg) ~= "string" or msg == "" then
        return nil, false
    end
    -- Skip quest/discovery XP lines ("You gain X experience.") so they never pollute KTL.
    if not string.find(msg, "dies", 1, true) and string.find(msg, "^You gain ") then
        return nil, false
    end
    local cleaned = msg:gsub(",", "")
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
    if not ok or (issecretvalue and issecretvalue(money)) or type(money) ~= "number" then
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

local function SuppressPlayedOnChatFrame(cf)
    if not cf or suppressedChatFrames[cf] or not cf.IsEventRegistered or not cf.UnregisterEvent then
        return
    end
    local ok, registered = pcall(cf.IsEventRegistered, cf, "TIME_PLAYED_MSG")
    if ok and not (issecretvalue and issecretvalue(registered)) and registered then
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
        if not okVis or (issecretvalue and issecretvalue(vis)) or not vis then
            return false
        end
    end
    if frame.IsMouseOver then
        local okOver, over = pcall(frame.IsMouseOver, frame)
        if okOver and not (issecretvalue and issecretvalue(over)) then
            return over and true or false
        end
    end
    local left, right, bottom, top = frame:GetLeft(), frame:GetRight(), frame:GetBottom(), frame:GetTop()
    if not left then
        return false
    end
    local scale = frame:GetEffectiveScale() or 1
    local x, y = GetCursorPosition()
    if issecretvalue and (issecretvalue(x) or issecretvalue(y) or issecretvalue(scale)) then
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
    if blizzBarCacheAt > 0 and (now - blizzBarCacheAt) < 5 then
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
        if not ok or (issecretvalue and issecretvalue(alpha)) or alpha ~= 0 then
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
        if not ok or (issecretvalue and issecretvalue(active)) then
            return false
        end
        return active and true or false
    end
    if not frame.IsShown then
        return false
    end
    local ok, shown = pcall(frame.IsShown, frame)
    if not ok or (issecretvalue and issecretvalue(shown)) then
        return false
    end
    return shown and true or false
end

function FBT:HideBlizzardTrackingBars(force)
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

local function StyleMeterButton(btn, hover)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
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
    local tip = CreateFrame("Frame", "XiusXPRepTrackerTooltip", UIParent, "BackdropTemplate")
    tip:SetFrameStrata("TOOLTIP")
    tip:SetFrameLevel(150)
    tip:SetClampedToScreen(true)
    tip:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    tip:SetBackdropColor(0.04, 0.04, 0.04, 0.96)
    tip:SetBackdropBorderColor(COLOR.border[1], COLOR.border[2], COLOR.border[3], 0.85)
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
        if centerY then
            if centerY < (GetScreenHeight() * 0.5) then
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
    end

    -- When stats live on the separate panel, never re-anchor them to the card.
    -- RestoreCardPosition / login /reload used to do that and piled every
    -- metric onto the collapsed XP bar while leaving the panel empty.
    local statsOnCard = (not IsSeparateStatsMode()) and stats:GetParent() == card

    header:ClearAllPoints()
    if statsOnCard then
        stats:ClearAllPoints()
        stats:SetHeight(HEIGHT_EXPANDED - 60)
    end
    if ui.growUp then
        header:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 8)
        header:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 8)
        if statsOnCard then
            stats:SetPoint("BOTTOMLEFT", header, "TOPLEFT", 0, 10)
            stats:SetPoint("BOTTOMRIGHT", header, "TOPRIGHT", 0, 10)
        end
    else
        header:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
        header:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -8)
        if statsOnCard then
            stats:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
            stats:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -10)
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
    db.point = point or "BOTTOM"
    db.relativePoint = relativePoint or "BOTTOMLEFT"
    db.x = x or 0
    db.y = y or 0
    db.width = math.max(MIN_WIDTH, Round(card:GetWidth()))
end

local function SavePanelPosition()
    local db, panel = FBT.db, ui.panel
    if not db or not panel then
        return
    end
    local point, _, relativePoint, x, y = panel:GetPoint(1)
    db.panelPoint = point or "CENTER"
    db.panelRelativePoint = relativePoint or "CENTER"
    db.panelX = x or 0
    db.panelY = y or 0
    db.panelWidth = math.max(PANEL_MIN_WIDTH, Round(panel:GetWidth()))
end

local VALID_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

function FBT:RestoreCardPosition()
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
    local layoutKey = availWidth + (compact and 100000 or 0)
    if ui.gridLayoutWidth and math.abs(ui.gridLayoutWidth - layoutKey) < 0.25 then
        return
    end
    ui.gridLayoutWidth = layoutKey

    if compact then
        local stats = CollectStatWidgets()
        local visibleCount = 0
        for i = 1, #stats do
            if stats[i] and stats[i]._shown ~= false then
                visibleCount = visibleCount + 1
            end
        end
        local colCount = PANEL_COLUMNS
        local perCol = math.max(1, math.ceil(visibleCount / colCount))
        local colWidth = availWidth / colCount
        local textWidth = math.max(8, colWidth - 6)
        local rowHeight = 34
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
                    local col = math.floor(visIdx / perCol)
                    local row = visIdx % perCol
                    local x = (LEFT_MARGIN - PAD) + (col * colWidth)
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

    local colWidth = availWidth / NUM_COLUMNS
    local textWidth = math.max(8, colWidth - 8)
    for i = 0, NUM_COLUMNS - 1 do
        local col = cols[i + 1]
        if col then
            col:Show()
            local x = (LEFT_MARGIN - PAD) + (i * colWidth)
            col:ClearAllPoints()
            col:SetPoint("TOPLEFT", grid, "TOPLEFT", x, 0)
            col:SetPoint("BOTTOM", grid, "BOTTOM", 0, 0)
            col:SetWidth(textWidth)
            local topStat = col.statTop
            local bottomStat = col.statBottom
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
                if topStat and topStat._shown ~= false then
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
            if issecretvalue and issecretvalue(x) then
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
        ui.currentHeight = HEIGHT_COLLAPSED
        ui.targetHeight = HEIGHT_COLLAPSED
        self:SetHeight(HEIGHT_COLLAPSED)
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
    if issecretvalue and issecretvalue(x) then
        return
    end
    local width = Clamp(ui.panelSizeStartW + ((x - ui.panelSizeStartX) / ui.panelSizeScale), PANEL_MIN_WIDTH, PANEL_MAX_WIDTH)
    self:SetWidth(width)
    if FBT.db then
        FBT.db.panelWidth = math.max(PANEL_MIN_WIDTH, Round(width))
    end
    ui.gridLayoutWidth = nil
    LayoutStatsGrid()
end

local function EnsureAnim()
    ui.card:SetScript("OnUpdate", AnimOnUpdate)
end

function FBT:SetExpanded(expanded)
    if IsSeparateStatsMode() then
        ui.expanded = false
        ui.targetHeight = HEIGHT_COLLAPSED
        ui.currentHeight = HEIGHT_COLLAPSED
        if ui.card then
            ui.card:SetHeight(HEIGHT_COLLAPSED)
        end
        -- Keep panel stats visible; do not hide ui.stats.
        return
    end
    ui.expanded = expanded and true or false
    ui.targetHeight = ui.expanded and HEIGHT_EXPANDED or HEIGHT_COLLAPSED
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

local function FactionBarValues(info)
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
    if ui.levelShown ~= level then
        ui.levelShown = level
        ui.levelText:SetText(tostring(level))
    end

    local atMax = IsPlayerMaxLevel()
    local info = self:GetWatchedFaction()
    local showRep = db.showRepBar and info ~= nil
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
    local ttl = TimeFromRate(xpLeft, xpPerHour)
    local avgKill = AverageKillXP()
    local avgQuest = AverageQuestXP()
    local atMax = IsPlayerMaxLevel()
    local ktl = "--"
    if not atMax and avgKill > 0 and xpLeft > 0 then
        ktl = tostring(math.ceil(xpLeft / avgKill))
    elseif atMax then
        ktl = "Max"
    end
    local qtl = "--"
    if not atMax and avgQuest > 0 and xpLeft > 0 then
        qtl = tostring(math.ceil(xpLeft / avgQuest))
    elseif atMax then
        qtl = "Max"
    end
    local restXP = CurrentRestXP()
    local restText = "0 (0%)"
    if restXP > 0 and maxXP > 0 then
        restText = string.format("%s (%s)", FormatCompact(restXP), FormatPercent(restXP, maxXP))
    end
    local sessionXPText = string.format("%s / %s", FormatCompact(session.xpEarned or 0), FormatCompact(xpLeft))

    local levelPlayed = PlayedSinceSnapshot(session.playedLevel)
    local totalPlayed = PlayedSinceSnapshot(session.playedTotal)

    SetStat(ui.statSessionXP, "SESSION XP", sessionXPText, true, COLOR.value)
    SetStat(ui.statSessionTime, "SESSION TIME", FormatClock(elapsed), db.showSessionTime, COLOR.value)
    SetStat(ui.statTimeLevel, "TIME THIS LEVEL", FormatPlayedClock(levelPlayed), db.showTimeLevel, COLOR.value)
    SetStat(ui.statTimePlayed, "TOTAL PLAYED", FormatPlayedClock(totalPlayed), db.showTimePlayed, COLOR.gold)
    SetStat(ui.statRested, "RESTED", atMax and "Max" or restText, db.showRested, COLOR.rest)
    SetStat(ui.statTTL, "TIME TO LEVEL", atMax and "Max" or FormatClock(ttl), db.showTTL, COLOR.gold)
    SetStat(ui.statXPHour, "XP / HOUR", atMax and "--" or FormatCompact(xpPerHour), db.showXPHour, COLOR.value)
    SetStat(ui.statKTL, "KILLS TO LEVEL", ktl, db.showKTL, COLOR.value)
    SetStat(ui.statQTL, "QUESTS TO LEVEL", qtl, db.showQTL, COLOR.gold)

    local goldColor = goldPerHour < 0 and COLOR.bad or COLOR.gold
    local sessGoldColor = goldDelta < 0 and COLOR.bad or COLOR.gold
    local goldHourRound = Round(goldPerHour)
    if ui.cachedGoldHourVal ~= goldHourRound then
        ui.cachedGoldHourVal = goldHourRound
        ui.cachedGoldHourText = FormatGoldValue(goldHourRound)
    end
    if ui.cachedGoldDeltaVal ~= goldDelta then
        ui.cachedGoldDeltaVal = goldDelta
        ui.cachedGoldDeltaText = FormatGoldValue(goldDelta)
    end
    SetStat(ui.statGoldHour, "GOLD / HOUR", ui.cachedGoldHourText or FormatGoldValue(goldPerHour), db.showGoldHour, goldColor)
    SetStat(ui.statGoldSess, "SESSION GOLD", ui.cachedGoldDeltaText or FormatGoldValue(goldDelta), db.showGoldSession, sessGoldColor)

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

    local hint = "Shift + Left-drag to move"
    if ui.footer then
        SetCachedText(ui.footer, "footerHint", hint)
    end
    if ui.panelMoveHint then
        SetCachedText(ui.panelMoveHint, "panelMoveHintCache", hint)
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
        if ui.footer then
            ui.footer:Hide()
        end
        if ui.panelMoveHint then
            ui.panelMoveHint:Show()
        end
    else
        if ui.panel then
            ui.panel:Hide()
        end
        if ui.footer then
            ui.footer:Show()
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
            ui.currentHeight = HEIGHT_COLLAPSED
            ui.targetHeight = HEIGHT_COLLAPSED
            ui.card:SetHeight(HEIGHT_COLLAPSED)
        end
    end
    ui.footerHint = nil
    self:RefreshStats()
end

function FBT:ApplySettings(key)
    if self.ApplyLootVendorSettings and (key == nil or key == "fasterLoot" or key == "autoSellJunk" or key == "autoRepair") then
        self:ApplyLootVendorSettings(key)
    end
    if self.ApplyTrainAllSettings and (key == nil or key == "trainAllButton") then
        self:ApplyTrainAllSettings(key)
    end
    if self.ApplyMaxRankSettings and (key == nil or key == "maxRankActionBars") then
        self:ApplyMaxRankSettings(key)
    end
    if not ui.card or not self.db then
        return
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
        ui.grip:SetShown(not self.db.isLocked)
    end
    if ui.panelGrip and (key == nil or key == "panelLocked" or key == "statsDisplayMode") then
        ui.panelGrip:SetShown(not self.db.panelLocked and IsSeparateStatsMode())
    end
    if key == nil or key == "statsDisplayMode" then
        self:ApplyStatsDisplayMode()
    end
    if (key == nil or key == "expandTrigger") and self.db.expandTrigger == "HOVER" and not self:IsHoverOverUI() then
        if not IsSeparateStatsMode() then
            self:SetExpanded(false)
        end
    end
    if key == "expandTrigger" or key == "statsDisplayMode" then
        ui.footerHint = nil
    end
    if key == "showXPBar" or key == "showRepBar" then
        ui.headerBarMode = nil
        ui.barKind = nil
        ui.repCur = nil
        ui.repMax = nil
    end
    self:Refresh()
end

function FBT:ToggleLock()
    local db = self.db
    if not db then
        return
    end
    if IsSeparateStatsMode() then
        db.panelLocked = not db.panelLocked
        self:ApplySettings("panelLocked")
        if db.panelLocked then
            self:Print("Stats box locked.")
        else
            self:Print("Stats box unlocked. Shift-drag to move.")
        end
        return
    end
    db.isLocked = not db.isLocked
    self:ApplySettings("isLocked")
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
    session.questXP = {}
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
    self:HideBlizzardTrackingBars(true)
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
        ticker = C_Timer.NewTicker(1.0, function()
            FBT:HideBlizzardTrackingBars()
            FBT:UpdateRestedOverlay()
            if IsSeparateStatsMode() or ui.expanded then
                FBT:RequestRefresh(true)
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
    if not db.isLocked and IsShiftKeyDown() then
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
    if not db.panelLocked and IsShiftKeyDown() then
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
    local stats = CreateFrame("Frame", "XiusXPRepTrackerStats", parent)
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

    local footer = stats:CreateFontString(nil, "OVERLAY")
    footer:SetPoint("BOTTOM", stats, "BOTTOM", 0, 0)
    SetFont(footer, GameFontDisableSmall, 9)
    footer:SetTextColor(COLOR.footer[1], COLOR.footer[2], COLOR.footer[3], 1)
    footer:SetText("Shift + Left-drag to move")

    ui.stats = stats
    ui.resetBtn = resetBtn
    ui.settingsBtn = settingsBtn
    ui.statSessionXP = statSessionXP
    ui.statSessionTime = statSessionTime
    ui.statRested = statRested
    ui.statTTL = statTTL
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
    ui.footer = footer
    ui.allStats = {
        statSessionXP, statSessionTime,
        statRested, statTTL,
        statXPHour, statKTL,
        statQTL, statRepSess,
        statGoldHour, statGoldSess,
        statRepHour, statNextRank,
        statTimeLevel, statTimePlayed,
    }
    return stats
end

function FBT:CreateStatsPanel()
    if ui.panel then
        return
    end

    local panel = CreateFrame("Frame", "XiusXPRepTrackerStatsPanel", UIParent, "BackdropTemplate")
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

    local moveHint = panel:CreateFontString(nil, "OVERLAY")
    moveHint:SetPoint("BOTTOM", panel, "BOTTOM", 0, 6)
    SetFont(moveHint, GameFontDisableSmall, 9)
    moveHint:SetTextColor(COLOR.footer[1], COLOR.footer[2], COLOR.footer[3], 1)
    moveHint:SetText("Shift + Left-drag to move")
    ui.panelMoveHint = moveHint

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
        ui.panelSizing = true
        ui.panelSizeStartX = GetCursorPosition()
        ui.panelSizeStartW = panel:GetWidth()
        ui.panelSizeScale = panel:GetEffectiveScale() or 1
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
    -- Do not leave the card at CreateFrame's default CENTER of UIParent.
    -- RestoreCardPosition immediately overwrites this with SavedVariables.
    card:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)

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
    barColumn:SetPoint("RIGHT", header, "RIGHT", -2, 0)
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
    ui.currentHeight = HEIGHT_COLLAPSED
    ui.targetHeight = HEIGHT_COLLAPSED
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
        ui.sizing = true
        ui.sizeStartX = GetCursorPosition()
        ui.sizeStartW = card:GetWidth()
        ui.sizeScale = card:GetEffectiveScale() or 1
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
    card:SetScript("OnSizeChanged", function()
        LayoutStatsGrid()
    end)
    if ui.grip then
        ui.grip:SetShown(not (self.db and self.db.isLocked))
    end
    self:HideBlizzardTrackingBars()
    self:ApplyStatsDisplayMode()
    self:Refresh()
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
    elseif level < lastLevel then
        session.awaitNewLevelXP = nil
    elseif session.awaitNewLevelXP and (xp ~= lastXP or maxXP ~= lastMax) then
        deltaGained = math.max(0, xp)
        session.xpEarned = (session.xpEarned or 0) + deltaGained
        session.awaitNewLevelXP = nil
    elseif xp > lastXP then
        deltaGained = xp - lastXP
        session.xpEarned = (session.xpEarned or 0) + deltaGained
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
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("TIME_PLAYED_MSG")
    SafeRegisterEvent(f, "UPDATE_EXHAUSTION")
    SafeRegisterEvent(f, "MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
    SafeRegisterEvent(f, "EDIT_MODE_LAYOUT_UPDATED")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_XP_UPDATE" then
            OnXPUpdate()
        elseif event == "PLAYER_LEVEL_UP" then
            local newLevel = ...
            OnXPUpdate(newLevel)
            session.playedLevel = 0
            session.playedStamp = GetTime()
            RequestPlayedTime(true)
        elseif event == "TIME_PLAYED_MSG" then
            local total, levelTime = ...
            session.playedTotal = PublicNumber(total, 0)
            session.playedLevel = PublicNumber(levelTime, 0)
            session.playedStamp = GetTime()
            RestorePlayedChatFrames()
            FBT:RequestRefresh(true)
        elseif event == "UPDATE_FACTION" or event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" then
            watchedCache = nil
            watchedCacheValid = false
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
        elseif event == "PLAYER_ENTERING_WORLD" then
            watchedCache = nil
            watchedCacheValid = false
            FBT:RestoreCardPosition()
            if IsSeparateStatsMode() then
                FBT:RestorePanelPosition()
                EnsureSeparateStatsAnchored()
            end
            FBT:StartSession()
        elseif event == "PLAYER_REGEN_ENABLED" or event == "EDIT_MODE_LAYOUT_UPDATED" then
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
        if FBT.ApplyLootVendorSettings then
            FBT:ApplyLootVendorSettings("fasterLoot")
        end
        FBT:CreateOptions()
        FBT:CreateUI()
        FBT:RegisterTracking()
        FBT:HideBlizzardTrackingBars()
        FBT:RestoreCardPosition()
        if IsSeparateStatsMode() then
            EnsureSeparateStatsAnchored()
        end
        if IsLoggedIn and IsLoggedIn() then
            FBT:StartSession()
            if FBT.QueueMaxRankScan then
                FBT:QueueMaxRankScan("login")
            end
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
