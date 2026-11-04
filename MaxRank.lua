--[[
    Xius XP/Rep Tracker - MaxRank.lua
    Replace lower-rank spells on action bars with the highest rank known.
    Scans on login, level-up, and after training at a trainer.
]]

local ADDON, FBT = ...

local MAX_ACTION_SLOTS = 180
local loginScanned = false
local trainerOpen = false
local waitingLevelSpells = false
local scanQueued = false
local scanToken = 0

local function OptionOn()
    return FBT.db and FBT.db.maxRankActionBars and true or false
end

local function PlainString(v)
    if issecretvalue and issecretvalue(v) then
        return nil
    end
    if type(v) ~= "string" or v == "" then
        return nil
    end
    return v
end

local function PlainNumber(v)
    if issecretvalue and issecretvalue(v) then
        return nil
    end
    if type(v) ~= "number" then
        return nil
    end
    return v
end

local function SpellBookBank()
    if Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player then
        return Enum.SpellBookSpellBank.Player
    end
    return BOOKTYPE_SPELL or "spell"
end

local function RankNumber(rankText)
    rankText = PlainString(rankText)
    if not rankText then
        return 0, false
    end
    local num = tonumber(string.match(rankText, "(%d+)"))
    if num then
        return num, false
    end
    -- Non-empty subtext without digits (e.g. "Turtle", "Cat", "Bear", "Passive") is a variant, not a numbered rank.
    return 0, true
end

local function SpellNameAndRank(spellID)
    spellID = PlainNumber(spellID)
    if not spellID then
        return nil, 0, false
    end
    if C_Spell and C_Spell.GetSpellName then
        local okName, name = pcall(C_Spell.GetSpellName, spellID)
        local sub
        if C_Spell.GetSpellSubtext then
            local okSub, subtext = pcall(C_Spell.GetSpellSubtext, spellID)
            if okSub then
                sub = subtext
            end
        end
        if not PlainString(sub) and GetSpellSubtext then
            local okSub, subtext = pcall(GetSpellSubtext, spellID)
            if okSub then
                sub = subtext
            end
        end
        if okName then
            local rank, isVariant = RankNumber(sub)
            return PlainString(name), rank, isVariant
        end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, spellInfo = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and not (issecretvalue and issecretvalue(spellInfo)) and type(spellInfo) == "table" then
            local rank, isVariant = RankNumber(spellInfo.subtext)
            return PlainString(spellInfo.name), rank, isVariant
        end
    end
    if GetSpellInfo then
        local ok, name, rankText = pcall(GetSpellInfo, spellID)
        if ok then
            local rank, isVariant = RankNumber(rankText)
            return PlainString(name), rank, isVariant
        end
    end
    return nil, 0, false
end

local function SpellIsKnown(spellID)
    spellID = PlainNumber(spellID)
    if not spellID then
        return false
    end
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, spellID)
        if ok and not (issecretvalue and issecretvalue(known)) and known then
            return true
        end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
        if ok and not (issecretvalue and issecretvalue(known)) and known then
            return true
        end
    end
    if IsSpellKnown then
        local ok, known = pcall(IsSpellKnown, spellID)
        if ok and not (issecretvalue and issecretvalue(known)) and known then
            return true
        end
    end
    if IsPlayerSpell or IsSpellKnown or (C_SpellBook and C_SpellBook.IsSpellKnown) then
        return false
    end
    return true
end

local function IsLearnedSpell(itemType)
    if issecretvalue and issecretvalue(itemType) then
        return false
    end
    if itemType == nil then
        return true
    end
    if itemType == "SPELL" or itemType == "spell" then
        return true
    end
    local types = Enum and Enum.SpellBookItemType
    return types and itemType == types.Spell or false
end

local function IsLowRank(index, book)
    if not (C_SpellBook and C_SpellBook.IsSpellBookItemLowRank) then
        return false
    end
    local ok, low = pcall(C_SpellBook.IsSpellBookItemLowRank, index, book)
    if not ok or (issecretvalue and issecretvalue(low)) then
        return false
    end
    return low and true or false
end

local function IsPassiveSlot(index, book, spellID, infoPassive)
    if infoPassive ~= nil then
        if issecretvalue and issecretvalue(infoPassive) then
            return true
        end
        if infoPassive then
            return true
        end
    end
    if C_SpellBook and C_SpellBook.IsSpellBookItemPassive then
        local ok, passive = pcall(C_SpellBook.IsSpellBookItemPassive, index, book)
        if ok and not (issecretvalue and issecretvalue(passive)) and passive then
            return true
        end
    end
    if spellID and C_Spell and C_Spell.IsSpellPassive then
        local ok, passive = pcall(C_Spell.IsSpellPassive, spellID)
        if ok and not (issecretvalue and issecretvalue(passive)) and passive then
            return true
        end
    end
    if IsPassiveSpell then
        local ok, passive = pcall(IsPassiveSpell, index, book)
        if ok and not (issecretvalue and issecretvalue(passive)) and passive then
            return true
        end
    end
    return false
end

local function IsOffSpecSlot(index, book, infoOffSpec)
    if infoOffSpec ~= nil then
        if issecretvalue and issecretvalue(infoOffSpec) then
            return true
        end
        if infoOffSpec then
            return true
        end
    end
    if not (C_SpellBook and C_SpellBook.IsSpellBookItemOffSpec) then
        return false
    end
    local ok, off = pcall(C_SpellBook.IsSpellBookItemOffSpec, index, book)
    if not ok or (issecretvalue and issecretvalue(off)) then
        return false
    end
    return off and true or false
end

local function ActionSpellIsLowRank(spellID)
    if not (C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell and C_SpellBook.IsSpellBookItemLowRank) then
        return false
    end
    local ok, slot, bank = pcall(C_SpellBook.FindSpellBookSlotForSpell, spellID)
    if not ok or not slot then
        return false
    end
    local okRank, low = pcall(C_SpellBook.IsSpellBookItemLowRank, slot, bank)
    if not okRank or (issecretvalue and issecretvalue(low)) then
        return false
    end
    return low and true or false
end

local function PickupBookSpell(index, book)
    if C_SpellBook and C_SpellBook.PickupSpellBookItem then
        C_SpellBook.PickupSpellBookItem(index, book)
        return
    end
    if PickupSpellBookItem then
        PickupSpellBookItem(index, book)
        return
    end
    local spellID
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, index, book)
        if ok and type(info) == "table" then
            spellID = info.spellID
        end
    elseif GetSpellBookItemInfo then
        local ok, _, id = pcall(GetSpellBookItemInfo, index, book)
        if ok then
            spellID = id
        end
    end
    spellID = PlainNumber(spellID)
    if spellID and C_Spell and C_Spell.PickupSpell then
        C_Spell.PickupSpell(spellID)
    elseif spellID and PickupSpell then
        PickupSpell(spellID)
    end
end

local function CursorBusy()
    if not GetCursorInfo then
        return false
    end
    local ok, cursor = pcall(GetCursorInfo)
    if not ok or (issecretvalue and issecretvalue(cursor)) or cursor == nil then
        return false
    end
    return true
end

local function RememberLine(list, seen, index)
    index = PlainNumber(index)
    if not index or index < 1 or seen[index] then
        return
    end
    seen[index] = true
    list[#list + 1] = index
end

local function SkillLineIndices()
    local list, seen = {}, {}
    local count = 0
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local ok, num = pcall(C_SpellBook.GetNumSpellBookSkillLines)
        count = (ok and PlainNumber(num)) or 0
    end
    if GetNumSpellTabs then
        local ok, tabs = pcall(GetNumSpellTabs)
        tabs = (ok and PlainNumber(tabs)) or 0
        if tabs > count then
            count = tabs
        end
    end
    if count > 64 then
        count = 64
    end
    for i = 1, count do
        RememberLine(list, seen, i)
    end
    if GetProfessions then
        local ok, first, second, archaeology, fishing, cooking = pcall(GetProfessions)
        if ok then
            RememberLine(list, seen, first)
            RememberLine(list, seen, second)
            RememberLine(list, seen, archaeology)
            RememberLine(list, seen, fishing)
            RememberLine(list, seen, cooking)
        end
    end
    return list
end

local function LineBounds(tab)
    if C_SpellBook and C_SpellBook.GetSpellBookSkillLineInfo then
        local ok, info = pcall(C_SpellBook.GetSpellBookSkillLineInfo, tab)
        if ok and not (issecretvalue and issecretvalue(info)) and type(info) == "table" then
            local offSpec = PlainNumber(info.offSpecID)
            local hidden = (issecretvalue and (issecretvalue(info.isOffSpec) or issecretvalue(info.isGuild)))
                or info.isOffSpec or info.isGuild or (offSpec and offSpec ~= 0)
            return PlainNumber(info.itemIndexOffset) or 0, PlainNumber(info.numSpellBookItems) or 0, hidden and true or false
        end
    end
    if GetSpellTabInfo then
        local okTab, _, _, offset, numSlots, isGuild, offSpecID = pcall(GetSpellTabInfo, tab)
        if okTab then
            local offSpec = PlainNumber(offSpecID)
            local hidden = (issecretvalue and issecretvalue(isGuild)) or isGuild or (offSpec and offSpec ~= 0)
            return PlainNumber(offset) or 0, PlainNumber(numSlots) or 0, hidden and true or false
        end
    end
    return nil, nil, true
end

local function BuildMaxRankMap()
    local map = {}
    local knownByID = {}
    local book = SpellBookBank()
    local lines = SkillLineIndices()

    for t = 1, #lines do
        local offset, numSlots, skip = LineBounds(lines[t])
        if not skip and offset and numSlots and numSlots > 0 then
            for i = offset + 1, offset + numSlots do
                local name, rankText, spellID, itemType, infoPassive, infoOffSpec
                if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
                    local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, book)
                    if ok and not (issecretvalue and issecretvalue(info)) and type(info) == "table" then
                        spellID = info.spellID
                        itemType = info.itemType
                        name = info.name
                        rankText = info.subName
                        infoPassive = info.isPassive
                        infoOffSpec = info.isOffSpec
                    end
                elseif GetSpellBookItemInfo then
                    local ok, iType, id = pcall(GetSpellBookItemInfo, i, book)
                    if ok then
                        itemType, spellID = iType, id
                    end
                end
                if not name or not rankText then
                    if C_SpellBook and C_SpellBook.GetSpellBookItemName then
                        local ok, bookName, bookRank = pcall(C_SpellBook.GetSpellBookItemName, i, book)
                        if ok then
                            name = name or bookName
                            rankText = rankText or bookRank
                        end
                    elseif GetSpellBookItemName then
                        local ok, bookName, bookRank = pcall(GetSpellBookItemName, i, book)
                        if ok then
                            name = name or bookName
                            rankText = rankText or bookRank
                        end
                    end
                end
                name = PlainString(name)
                spellID = PlainNumber(spellID)
                if name and spellID and IsLearnedSpell(itemType) and not IsOffSpecSlot(i, book, infoOffSpec) and not IsPassiveSlot(i, book, spellID, infoPassive) then
                    local rank, isVariant = RankNumber(rankText)
                    local low = IsLowRank(i, book)
                    if not isVariant and SpellIsKnown(spellID) then
                        knownByID[spellID] = {
                            name = name,
                            rank = rank,
                            lowRank = low,
                            index = i,
                        }
                        if not low then
                            local current = map[name]
                            if not current or rank > current.rank or (rank == current.rank and i > current.index) then
                                map[name] = {
                                    rank = rank,
                                    index = i,
                                    spellID = spellID,
                                }
                            end
                        end
                    end
                end
            end
        end
    end
    return map, knownByID
end

local function Flag(ok, value)
    if not ok or (issecretvalue and issecretvalue(value)) then
        return false
    end
    return value and true or false
end

local function SlotHasAction(slot)
    if C_ActionBar and C_ActionBar.HasAction then
        return Flag(pcall(C_ActionBar.HasAction, slot))
    end
    if HasAction then
        return Flag(pcall(HasAction, slot))
    end
    return false
end

local function AssistedSlot(slot)
    if not (C_ActionBar and C_ActionBar.IsAssistedCombatAction) then
        return false
    end
    return Flag(pcall(C_ActionBar.IsAssistedCombatAction, slot))
end

local function UpgradeActionBars()
    if not OptionOn() then
        scanQueued = false
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        scanQueued = true
        return
    end
    if CursorBusy() then
        scanQueued = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0.75, function()
                if scanQueued then
                    FBT:QueueMaxRankScan("retry")
                end
            end)
        end
        return
    end
    if not GetActionInfo or not PlaceAction then
        return
    end

    local maxMap, knownByID = BuildMaxRankMap()
    local upgraded = 0
    local book = SpellBookBank()

    for slot = 1, MAX_ACTION_SLOTS do
        if SlotHasAction(slot) and not AssistedSlot(slot) then
            local ok, actionType, id = pcall(GetActionInfo, slot)
            id = ok and PlainNumber(id) or nil
            if ok and PlainString(actionType) == "spell" and id then
                local entry = knownByID[id]
                local name, rank, isVariant, lowRank
                if entry then
                    name = entry.name
                    rank = entry.rank
                    lowRank = entry.lowRank
                else
                    name, rank, isVariant = SpellNameAndRank(id)
                end
                if not isVariant and name then
                    local best = maxMap[name]
                    if best and best.index and best.spellID and best.spellID ~= id then
                        if lowRank == nil then
                            lowRank = ActionSpellIsLowRank(id)
                        end
                        if (rank > 0 and best.rank > rank) or lowRank then
                            if CursorBusy() then
                                pcall(ClearCursor)
                            end
                            pcall(PickupBookSpell, best.index, book)
                            if CursorBusy() then
                                local placed = pcall(PlaceAction, slot)
                                if CursorBusy() then
                                    pcall(ClearCursor)
                                end
                                local okAfter, newType, newID = pcall(GetActionInfo, slot)
                                newID = okAfter and PlainNumber(newID) or nil
                                if placed and PlainString(newType) == "spell" and newID and newID ~= id then
                                    upgraded = upgraded + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    scanQueued = false
    if upgraded > 0 and FBT.Print then
        FBT:Print(string.format("Upgraded %d action bar spell%s to max rank.", upgraded, upgraded == 1 and "" or "s"))
    end
end

function FBT:QueueMaxRankScan(reason)
    if not OptionOn() then
        return
    end
    scanQueued = true
    scanToken = scanToken + 1
    local token = scanToken
    local delay = 0.4
    if reason == "login" then
        delay = 1.5
    elseif reason == "level" then
        delay = 1.0
    elseif reason == "trainer" then
        delay = 0.5
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, function()
            if token ~= scanToken then
                return
            end
            UpgradeActionBars()
        end)
    else
        UpgradeActionBars()
    end
end

function FBT:ApplyMaxRankSettings(key)
    if key == "maxRankActionBars" and OptionOn() then
        self:QueueMaxRankScan("settings")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("TRAINER_SHOW")
events:RegisterEvent("TRAINER_CLOSED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if not loginScanned and FBT.db then
            loginScanned = true
            FBT:QueueMaxRankScan("login")
        end
    elseif event == "PLAYER_LEVEL_UP" then
        waitingLevelSpells = true
        FBT:QueueMaxRankScan("level")
    elseif event == "TRAINER_SHOW" then
        trainerOpen = true
    elseif event == "TRAINER_CLOSED" then
        if trainerOpen then
            FBT:QueueMaxRankScan("trainer")
        end
        trainerOpen = false
    elseif event == "SPELLS_CHANGED" then
        if waitingLevelSpells then
            waitingLevelSpells = false
            FBT:QueueMaxRankScan("level")
        elseif trainerOpen then
            FBT:QueueMaxRankScan("trainer")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if scanQueued then
            FBT:QueueMaxRankScan("retry")
        end
    end
end)
