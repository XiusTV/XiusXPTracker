--[[
    Xius XP/Rep Tracker - LootVendor.lua
    Faster corpse looting, auto-sell grey junk, and auto-repair at vendors.
]]

local ADDON, FBT = ...

local SELL_BATCH_LIMIT = 12
local lootBusy = false
local lastLootAt = 0
local merchantQueued = false
local sellingJunk = false
local pendingCvarUpdate = false

local function OptionOn(key)
    return FBT.db and FBT.db[key] and true or false
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

local function Blocked(v)
    if issecretvalue and issecretvalue(v) then
        return true
    end
    return v and true or false
end

local function CoinString(copper)
    copper = math.max(0, math.floor((copper or 0) + 0.5))
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

local function BagSlotCount()
    local total = PlainNumber(NUM_TOTAL_EQUIPPED_BAG_SLOTS) or PlainNumber(NUM_BAG_SLOTS)
    return total or 4
end

local function ContainerSlots(bag)
    local count
    if C_Container and C_Container.GetContainerNumSlots then
        local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
        if ok then
            count = n
        end
    elseif GetContainerNumSlots then
        local ok, n = pcall(GetContainerNumSlots, bag)
        if ok then
            count = n
        end
    end
    return PlainNumber(count) or 0
end

local function IsPoorQuality(quality)
    if (issecretvalue and issecretvalue(quality)) or quality == nil then
        return false
    end
    if Enum and Enum.ItemQuality and Enum.ItemQuality.Poor then
        return quality == Enum.ItemQuality.Poor
    end
    return quality == 0
end

local function ItemSellPrice(itemID, link, stackCount)
    itemID = PlainNumber(itemID)
    if not itemID and link and not (issecretvalue and issecretvalue(link)) and type(link) == "string" then
        itemID = tonumber(string.match(link, "item:(%d+)"))
    end
    if not itemID then
        return 0
    end
    local sell
    if C_Item and C_Item.GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, vendorPrice = pcall(C_Item.GetItemInfo, itemID)
        if ok then
            sell = vendorPrice
        end
    elseif GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, vendorPrice = pcall(GetItemInfo, itemID)
        if ok then
            sell = vendorPrice
        end
    end
    sell = PlainNumber(sell) or 0
    local count = PlainNumber(stackCount) or 1
    return sell * count
end

-- Zero-allocation check: returns true, stackSellPrice if the slot holds unlocked sellable poor-quality junk.
local function CheckJunkSlot(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if not ok or (issecretvalue and issecretvalue(info)) or type(info) ~= "table" then
            return false, 0
        end
        if not IsPoorQuality(info.quality) or Blocked(info.isLocked) or Blocked(info.hasNoValue) then
            return false, 0
        end
        return true, ItemSellPrice(info.itemID, info.hyperlink, info.stackCount)
    end
    if not GetContainerItemInfo then
        return false, 0
    end
    local ok, icon, count, locked, quality, _, _, link, _, noValue, itemID = pcall(GetContainerItemInfo, bag, slot)
    if not ok then
        return false, 0
    end
    local iconHidden = issecretvalue and issecretvalue(icon)
    local linkHidden = issecretvalue and issecretvalue(link)
    if not iconHidden and not linkHidden and not icon and not link then
        return false, 0
    end
    if not IsPoorQuality(quality) or Blocked(locked) or Blocked(noValue) then
        return false, 0
    end
    return true, ItemSellPrice(itemID, link, count)
end

local function UseBagItem(bag, slot)
    if C_Container and C_Container.UseContainerItem then
        C_Container.UseContainerItem(bag, slot)
        return
    end
    if UseContainerItem then
        UseContainerItem(bag, slot)
    end
end

local function MerchantIsOpen()
    if not (MerchantFrame and MerchantFrame.IsShown) then
        return false
    end
    local ok, shown = pcall(MerchantFrame.IsShown, MerchantFrame)
    if not ok or (issecretvalue and issecretvalue(shown)) then
        return false
    end
    return shown and true or false
end

local function ShouldAutoLoot()
    if not OptionOn("fasterLoot") then
        return false
    end
    -- Shift opens the loot window for this corpse.
    if IsModifiedClick then
        local ok, held = pcall(IsModifiedClick, "AUTOLOOTTOGGLE")
        if ok and not (issecretvalue and issecretvalue(held)) and held then
            return false
        end
    end
    return true
end

local function FastLoot()
    if lootBusy or not ShouldAutoLoot() then
        return
    end
    local now = GetTime and GetTime() or 0
    if lastLootAt > 0 and (now - lastLootAt) < 0.15 then
        return
    end
    local n = 0
    if GetNumLootItems then
        local okCount, count = pcall(GetNumLootItems)
        n = (okCount and PlainNumber(count)) or 0
    end
    if n <= 0 then
        return
    end
    lootBusy = true
    local lootedAny = false
    for i = n, 1, -1 do
        local hasItem = true
        if LootSlotHasItem then
            local ok, has = pcall(LootSlotHasItem, i)
            if ok and not (issecretvalue and issecretvalue(has)) then
                hasItem = has and true or false
            end
        end
        if hasItem and GetLootSlotInfo then
            local ok, _, _, _, _, _, locked = pcall(GetLootSlotInfo, i)
            if ok and Blocked(locked) then
                hasItem = false
            end
        end
        if hasItem then
            if pcall(LootSlot, i) then
                lootedAny = true
            else
                break
            end
        end
    end
    if lootedAny then
        lastLootAt = now
    end
    lootBusy = false
end

local function AutoRepair()
    if not OptionOn("autoRepair") then
        return
    end
    if not MerchantIsOpen() then
        return
    end
    if not CanMerchantRepair then
        return
    end
    local repairOk, canRepairMerchant = pcall(CanMerchantRepair)
    if not repairOk or (issecretvalue and issecretvalue(canRepairMerchant)) or not canRepairMerchant then
        return
    end
    if not GetRepairAllCost or not RepairAllItems then
        return
    end

    -- One return value is the copper cost. A missing second value still means repair is allowed.
    local costOk, cost, canRepair = pcall(GetRepairAllCost)
    if not costOk then
        return
    end
    if issecretvalue and issecretvalue(canRepair) then
        canRepair = nil
    end
    cost = PlainNumber(cost)
    if not cost or canRepair == false or cost <= 0 then
        return
    end

    local money = PlainNumber(GetMoney and GetMoney())
    if not money then
        return
    end
    if money < cost then
        FBT:Print("Not enough gold to repair (" .. CoinString(cost) .. ").")
        return
    end
    if pcall(RepairAllItems) then
        FBT:Print("Repaired for " .. CoinString(cost) .. ".")
    end
end

local function SellJunkAndRepair()
    if sellingJunk or not MerchantIsOpen() then
        return
    end
    if not OptionOn("autoSellJunk") then
        AutoRepair()
        return
    end

    sellingJunk = true
    local totalSold = 0
    local totalValue = 0
    local seenSlots = {}

    local function SellBatch(pass)
        if not MerchantIsOpen() or (InCombatLockdown and InCombatLockdown()) then
            sellingJunk = false
            if totalSold > 0 then
                FBT:Print(string.format("Sold %d junk item%s for %s.", totalSold, totalSold == 1 and "" or "s", CoinString(totalValue)))
            end
            return
        end

        local batchSold = 0
        local moreRemain = false
        local lastBag = BagSlotCount()

        for bag = 0, lastBag do
            local slots = ContainerSlots(bag)
            for slot = 1, slots do
                local slotKey = bag * 100 + slot
                if not seenSlots[slotKey] then
                    local isJunk, price = CheckJunkSlot(bag, slot)
                    if isJunk then
                        if batchSold < SELL_BATCH_LIMIT then
                            seenSlots[slotKey] = true
                            if pcall(UseBagItem, bag, slot) then
                                batchSold = batchSold + 1
                                totalSold = totalSold + 1
                                totalValue = totalValue + price
                            end
                        else
                            moreRemain = true
                            break
                        end
                    end
                end
            end
            if moreRemain then
                break
            end
        end

        if moreRemain and pass < 15 and C_Timer and C_Timer.After then
            C_Timer.After(0.18, function()
                SellBatch(pass + 1)
            end)
            return
        end

        sellingJunk = false
        if totalSold > 0 then
            FBT:Print(string.format("Sold %d junk item%s for %s.", totalSold, totalSold == 1 and "" or "s", CoinString(totalValue)))
            if C_Timer and C_Timer.After then
                C_Timer.After(0.15, AutoRepair)
            else
                AutoRepair()
            end
        else
            AutoRepair()
        end
    end

    SellBatch(1)
end

local function HandleMerchantVisit()
    merchantQueued = false
    if InCombatLockdown and InCombatLockdown() then
        merchantQueued = true
        return
    end
    if not MerchantIsOpen() then
        return
    end
    -- Sell first so junk gold can help pay for repairs.
    SellJunkAndRepair()
end

function FBT:ApplyLootVendorSettings(key)
    if not self.db then
        return
    end
    local setCVar = (C_CVar and C_CVar.SetCVar) or SetCVar
    local getCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
    if (key == nil or key == "fasterLoot") and setCVar then
        if InCombatLockdown and InCombatLockdown() then
            pendingCvarUpdate = true
            return
        end
        pendingCvarUpdate = false
        local desired = self.db.fasterLoot and "1" or "0"
        local current
        if getCVar then
            local ok, val = pcall(getCVar, "autoLootDefault")
            if ok and not (issecretvalue and issecretvalue(val)) then
                current = val
            end
        end
        if current ~= desired then
            pcall(setCVar, "autoLootDefault", desired)
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("LOOT_READY")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("LOOT_CLOSED")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if FBT.ApplyLootVendorSettings then
            FBT:ApplyLootVendorSettings("fasterLoot")
        end
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        FastLoot()
    elseif event == "LOOT_CLOSED" then
        lastLootAt = 0
        lootBusy = false
    elseif event == "MERCHANT_SHOW" then
        if C_Timer and C_Timer.After then
            C_Timer.After(0.15, HandleMerchantVisit)
        else
            HandleMerchantVisit()
        end
    elseif event == "MERCHANT_CLOSED" then
        merchantQueued = false
        sellingJunk = false
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingCvarUpdate and FBT.ApplyLootVendorSettings then
            FBT:ApplyLootVendorSettings("fasterLoot")
        end
        if merchantQueued then
            HandleMerchantVisit()
        end
    end
end)
