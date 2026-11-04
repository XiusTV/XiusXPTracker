--[[
    Xius XP/Rep Tracker - TrainAll.lua
    Train All button on class and profession trainers (toggle in options).
]]

local ADDON, FBT = ...

local trainBtn
local training = false

local function OptionOn()
    return FBT.db and FBT.db.trainAllButton and true or false
end

local function TrainerParent()
    return _G.ClassTrainerFrame or _G.TradeSkillTrainerFrame
end

local function TrainButtonAnchor()
    return _G.ClassTrainerTrainButton
        or (_G.ClassTrainerFrame and _G.ClassTrainerFrame.TrainButton)
        or (_G.TradeSkillTrainerFrame and _G.TradeSkillTrainerFrame.TrainButton)
end

local function ServiceInfo(index)
    if not GetTrainerServiceInfo then
        return nil
    end
    local ok, name, rank, category, expanded = pcall(GetTrainerServiceInfo, index)
    if not ok then
        return nil
    end
    return name, rank, category, expanded
end

local function ServiceCategory(...)
    local n = select("#", ...)
    for i = 1, n do
        local value = select(i, ...)
        if not (issecretvalue and issecretvalue(value)) then
            if value == "available" or value == "unavailable" or value == "used" or value == "header" then
                return value
            end
        end
    end
    return nil
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

local function PlainString(v)
    if issecretvalue and issecretvalue(v) then
        return nil
    end
    if type(v) ~= "string" or v == "" then
        return nil
    end
    return v
end

local function FrameShown(frame)
    if not frame or not frame.IsShown then
        return false
    end
    local ok, shown = pcall(frame.IsShown, frame)
    if not ok or (issecretvalue and issecretvalue(shown)) then
        return false
    end
    return shown and true or false
end

local function ServiceCost(index)
    if not GetTrainerServiceCost then
        return nil
    end
    local ok, cost = pcall(GetTrainerServiceCost, index)
    if not ok then
        return nil
    end
    return PlainNumber(cost)
end

local function ServiceLevelReq(index)
    if not GetTrainerServiceLevelReq then
        return nil
    end
    local ok, req = pcall(GetTrainerServiceLevelReq, index)
    if not ok then
        return nil
    end
    return PlainNumber(req)
end

local function MeetsLevelReq(index)
    local req = ServiceLevelReq(index)
    if not req then
        return true
    end
    local level = PlainNumber(UnitLevel and UnitLevel("player"))
    if not level then
        return true
    end
    return level >= req
end

local function MeetsSkillReq(index)
    if not GetTrainerServiceSkillReq then
        return true
    end
    local ok, skillName, _, hasReq = pcall(GetTrainerServiceSkillReq, index)
    if not ok or (issecretvalue and (issecretvalue(skillName) or issecretvalue(hasReq))) then
        return true
    end
    if not skillName then
        return true
    end
    if hasReq == false then
        return false
    end
    return true
end

local function MeetsAbilityReq(index)
    if not GetTrainerServiceAbilityReq then
        return true
    end
    for reqIndex = 1, 8 do
        local ok, abilityName, hasReq = pcall(GetTrainerServiceAbilityReq, index, reqIndex)
        if not ok or (issecretvalue and (issecretvalue(abilityName) or issecretvalue(hasReq))) then
            break
        end
        if not abilityName then
            break
        end
        if hasReq == false then
            return false
        end
    end
    return true
end

local function ServiceSpellID(index)
    if not GetTrainerServiceItemLink then
        return nil
    end
    local ok, link = pcall(GetTrainerServiceItemLink, index)
    if not ok or (issecretvalue and issecretvalue(link)) or type(link) ~= "string" then
        return nil
    end
    return tonumber(string.match(link, "spell:(%d+)"))
end

local function AlreadyKnown(index)
    local spellID = ServiceSpellID(index)
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
    return false
end

-- Only skills the trainer would actually let you buy (green / trainable).
-- Red rows are unavailable (level, missing form, missing previous rank, etc.).
local function CanTrainService(index)
    local name, rank, category, expanded = ServiceInfo(index)
    name = PlainString(name)
    if not name then
        return false
    end
    category = ServiceCategory(name, rank, category, expanded)
    -- Red rows are "unavailable". Only the green trainable category counts.
    if category ~= "available" then
        return false
    end
    if AlreadyKnown(index) then
        return false
    end
    if not MeetsLevelReq(index) then
        return false
    end
    if not MeetsSkillReq(index) then
        return false
    end
    if not MeetsAbilityReq(index) then
        return false
    end
    return true
end

local function ServiceKey(index)
    local name, rank = ServiceInfo(index)
    name = PlainString(name)
    if not name then
        return nil
    end
    local spellID = ServiceSpellID(index)
    if spellID then
        return "id:" .. tostring(spellID)
    end
    rank = PlainString(rank) or ""
    local req = ServiceLevelReq(index) or 0
    local cost = ServiceCost(index) or 0
    return string.format("%s|%s|%d|%d", name, rank, req, cost)
end

local function NumTrainerServices()
    if not GetNumTrainerServices then
        return 0
    end
    local ok, n = pcall(GetNumTrainerServices)
    if not ok then
        return 0
    end
    return PlainNumber(n) or 0
end

local function HasUnavailableServices()
    local n = NumTrainerServices()
    for i = 1, n do
        local name, rank, category, expanded = ServiceInfo(i)
        if PlainString(name) and ServiceCategory(name, rank, category, expanded) == "unavailable" then
            return true
        end
    end
    return false
end

local function CountAvailable()
    local n = NumTrainerServices()
    local available = 0
    local affordable = 0
    local money = PlainNumber(GetMoney and GetMoney())
    for i = 1, n do
        if CanTrainService(i) then
            available = available + 1
            local cost = ServiceCost(i)
            if money and cost and cost <= money then
                affordable = affordable + 1
            end
        end
    end
    return available, affordable
end

local function TrainAvailablePass(attempted)
    if not BuyTrainerService then
        return 0
    end
    local money = PlainNumber(GetMoney and GetMoney())
    if not money then
        return 0
    end
    local bought = 0
    local n = NumTrainerServices()
    for i = n, 1, -1 do
        if CanTrainService(i) then
            local key = ServiceKey(i)
            if not (key and attempted[key]) then
                local cost = ServiceCost(i)
                if cost and cost <= money then
                    if key then
                        attempted[key] = true
                    end
                    if pcall(BuyTrainerService, i) then
                        money = money - cost
                        bought = bought + 1
                    end
                end
            end
        end
    end
    return bought
end

local function FinishTraining(total)
    training = false
    if total > 0 then
        FBT:Print(string.format("Trained %d skill%s.", total, total == 1 and "" or "s"))
        if FBT.QueueMaxRankScan then
            FBT:QueueMaxRankScan("trainer")
        end
    else
        local available = CountAvailable()
        if available > 0 then
            FBT:Print("Nothing you can afford right now.")
        else
            FBT:Print("Nothing available to train.")
        end
    end
    FBT:RefreshTrainAllButton()
end

local function TrainAll()
    if training then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        FBT:Print("Cannot train during combat.")
        return
    end
    if not PlainNumber(GetMoney and GetMoney()) then
        FBT:Print("Cannot read your gold right now.")
        return
    end
    training = true
    FBT:RefreshTrainAllButton()
    local total = 0
    local attempted = {}
    local emptyPolls = 0

    local function Step(pass)
        local parent = TrainerParent()
        if not FrameShown(parent) or (InCombatLockdown and InCombatLockdown()) then
            FinishTraining(total)
            return
        end
        local bought = TrainAvailablePass(attempted)
        total = total + bought
        if bought > 0 then
            emptyPolls = 0
        else
            emptyPolls = emptyPolls + 1
        end
        -- Stop immediately if nothing was bought on the first pass, or if no locked
        -- rows exist that could unlock after server confirmation, or after waiting ~0.6s.
        if pass >= 30 or (total == 0 and bought == 0) or emptyPolls >= 4 or (bought == 0 and not HasUnavailableServices()) then
            FinishTraining(total)
            return
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.15, function()
                Step(pass + 1)
            end)
        else
            FinishTraining(total)
        end
    end
    Step(1)
end

local function PlaceButton(parent)
    if not trainBtn then
        return
    end
    trainBtn:SetParent(parent)
    trainBtn:ClearAllPoints()
    local anchor = TrainButtonAnchor()
    if anchor then
        trainBtn:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
    else
        trainBtn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 14, 78)
    end
    trainBtn:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 10)
end

local function EnsureButton()
    local parent = TrainerParent()
    if not parent then
        return
    end
    if trainBtn then
        PlaceButton(parent)
        return
    end
    trainBtn = CreateFrame("Button", "XiusXPRepTrackerTrainAllButton", parent, "UIPanelButtonTemplate")
    trainBtn:SetSize(88, 22)
    trainBtn:SetText("Train All")
    trainBtn:SetScript("OnClick", TrainAll)
    trainBtn:SetScript("OnEnter", function(self)
        if FBT.ShowTooltip then
            FBT:ShowTooltip(self, "Train All", "Learns every available class or profession skill you can afford.")
        end
    end)
    trainBtn:SetScript("OnLeave", function()
        if FBT.HideTooltip then
            FBT:HideTooltip()
        end
    end)
    PlaceButton(parent)
end

function FBT:RefreshTrainAllButton()
    EnsureButton()
    if not trainBtn then
        return
    end
    if not OptionOn() then
        trainBtn:Hide()
        return
    end
    local parent = TrainerParent()
    if not FrameShown(parent) then
        trainBtn:Hide()
        return
    end
    trainBtn:Show()
    if training then
        trainBtn:Disable()
        return
    end
    local _, affordable = CountAvailable()
    if affordable > 0 then
        trainBtn:Enable()
    else
        trainBtn:Disable()
    end
end

function FBT:ApplyTrainAllSettings()
    self:RefreshTrainAllButton()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("TRAINER_SHOW")
events:RegisterEvent("TRAINER_UPDATE")
events:RegisterEvent("TRAINER_CLOSED")
events:RegisterEvent("PLAYER_MONEY")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == "Blizzard_TrainerUI" then
            EnsureButton()
            FBT:RefreshTrainAllButton()
        end
    elseif event == "PLAYER_LOGIN" then
        EnsureButton()
        FBT:RefreshTrainAllButton()
    elseif event == "TRAINER_SHOW" then
        EnsureButton()
        FBT:RefreshTrainAllButton()
    elseif event == "TRAINER_UPDATE" or event == "PLAYER_MONEY" then
        if not training then
            FBT:RefreshTrainAllButton()
        end
    elseif event == "TRAINER_CLOSED" then
        training = false
        if trainBtn then
            trainBtn:Hide()
        end
    end
end)
