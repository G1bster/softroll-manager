local load_addon = require("spec.support.load_addon")

local ITEM_LINK_BELT = "|cffa335ee|Hitem:49978:0:0:0:0:0:0:0|h[Crushing Coldwraith Belt]|h|r"
local ITEM_LINK_BOOTS = "|cffa335ee|Hitem:49983:0:0:0:0:0:0:0|h[Necrophotic Boots]|h|r"
local ITEM_LINK_POTION = "|cffffffff|Hitem:33447:0:0:0:0:0:0:0|h[Runic Healing Potion]|h|r"

describe("Bag Loot Scanner & 2-Hour Trade Timer Tracker (Core.lua & UI/LootSession.lua)", function()
    local SR, wow

    before_each(function()
        SR, wow = load_addon.load()
        wow.state.playerName = "Leader"
        wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK_BELT, 4)
        wow.addItem(49983, "Necrophotic Boots", ITEM_LINK_BOOTS, 4)
        wow.addItem(33447, "Runic Healing Potion", ITEM_LINK_POTION, 1)

        wow.addRaidMember("Leader", 2)
        wow.addRaidMember("Member", 0)
        SR.sessionActive = true
        SR.sessionHost = "Leader"
        SR.locked = false
    end)

    describe("GetContainerItemTradeTime", function()
        it("returns nil when item has no trade timer", function()
            wow.addBagItem(0, 1, 49978, 1, nil)
            local mins, text = SR:GetContainerItemTradeTime(0, 1)
            assert.is_nil(mins)
            assert.is_nil(text)
        end)

        it("parses hours and minutes (e.g. 1h 45m)", function()
            wow.addBagItem(0, 1, 49978, 1, "1h 45m")
            local mins, text = SR:GetContainerItemTradeTime(0, 1)
            assert.are.equal(105, mins)
            assert.are.equal("1г 45хв", text)
        end)

        it("parses minutes only (e.g. 24m)", function()
            wow.addBagItem(0, 1, 49978, 1, "24m")
            local mins, text = SR:GetContainerItemTradeTime(0, 1)
            assert.are.equal(24, mins)
            assert.are.equal("24 хв", text)
        end)

        it("parses seconds only as < 1 min", function()
            wow.addBagItem(0, 1, 49978, 1, "45s")
            local mins, text = SR:GetContainerItemTradeTime(0, 1)
            assert.are.equal(0, mins)
            assert.are.equal("< 1 хв", text)
        end)

        it("parses Cyrillic / Ukrainian and Russian timer strings", function()
            wow.addBagItem(0, 1, 49978, 1, "1ч 35мин")
            local mins1, text1 = SR:GetContainerItemTradeTime(0, 1)
            assert.are.equal(95, mins1)
            assert.are.equal("1г 35хв", text1)

            wow.addBagItem(0, 2, 49983, 1, "40 хв")
            local mins2, text2 = SR:GetContainerItemTradeTime(0, 2)
            assert.are.equal(40, mins2)
            assert.are.equal("40 хв", text2)
        end)

        it("does not crash when the client's BIND_TRADE_TIME_REMAINING string contains unescaped Lua pattern characters", function()
            -- A literal, unbalanced '(' here would blow up string.match with
            -- "unfinished capture" if the code builds a Lua pattern from this
            -- string without first escaping its magic characters. The mock's
            -- actual tooltip line still says "trade this item ... for 1h 20m.",
            -- so detection should still succeed via the hardcoded fallback text
            -- match even though this (deliberately mismatched) primary pattern
            -- doesn't match it.
            local original = _G.BIND_TRADE_TIME_REMAINING
            _G.BIND_TRADE_TIME_REMAINING = "You may trade this item (with restrictions for %s."
            wow.addBagItem(0, 1, 49978, 1, "1h 20m")

            local mins, text
            assert.has_no.errors(function()
                mins, text = SR:GetContainerItemTradeTime(0, 1)
            end)
            assert.are.equal(80, mins)
            assert.are.equal("1г 20хв", text)

            _G.BIND_TRADE_TIME_REMAINING = original
        end)

        it("detects soulbound status correctly", function()
            wow.addBagItem(0, 1, 49978, 1, nil, true) -- soulbound without trade timer
            local mins1, _, isSoulbound1 = SR:GetContainerItemTradeTime(0, 1)
            assert.is_nil(mins1)
            assert.is_true(isSoulbound1)

            wow.addBagItem(0, 2, 49978, 1, nil, false) -- unbound BoE item
            local _, _, isSoulbound2 = SR:GetContainerItemTradeTime(0, 2)
            assert.is_false(isSoulbound2)

            wow.addBagItem(0, 3, 49978, 1, "1h 30m", true) -- soulbound BoP with active trade timer
            local mins3, _, isSoulbound3 = SR:GetContainerItemTradeTime(0, 3)
            assert.are.equal(90, mins3)
            assert.is_true(isSoulbound3)
        end)
    end)

    describe("ScanBagsForLoot", function()
        it("returns empty list when bags have no raid or SR items", function()
            wow.addBagItem(0, 1, 33447, 5, nil) -- Healing potion
            local loot = SR:ScanBagsForLoot()
            assert.are.equal(0, #loot)
        end)

        it("scans across multiple bags (0 through 4) and ignores empty slots", function()
            wow.addBagItem(0, 1, 33447, 1, nil) -- ignored
            wow.addBagItem(1, 4, 49978, 1, "1h 10m")
            wow.addBagItem(4, 2, 49983, 2, "25m")

            local loot = SR:ScanBagsForLoot()
            assert.are.equal(2, #loot)
            -- Critical timer item in bag 4 comes first
            assert.are.equal(4, loot[1].bag)
            assert.are.equal(2, loot[1].slot)
            assert.are.equal(25, loot[1].tradeMins)
            assert.are.equal(2, loot[1].count)

            -- Bag 1 item comes second
            assert.are.equal(1, loot[2].bag)
            assert.are.equal(4, loot[2].slot)
            assert.are.equal(70, loot[2].tradeMins)
        end)

        it("includes items that have soft-reserves registered", function()
            wow.addBagItem(0, 1, 49978, 1, nil)
            SR:AddSR("Member", ITEM_LINK_BELT, 1)

            local loot = SR:ScanBagsForLoot()
            assert.are.equal(1, #loot)
            assert.are.equal(49978, loot[1].itemID)
            assert.are.equal(1, loot[1].srCount)
            assert.are.equal("Member", loot[1].reservers[1].name)
        end)

        it("includes items that have an active trade timer even without soft-reserves", function()
            wow.addBagItem(0, 1, 49983, 1, "1h 59m")

            local loot = SR:ScanBagsForLoot()
            assert.are.equal(1, #loot)
            assert.are.equal(49983, loot[1].itemID)
            assert.are.equal(0, loot[1].srCount)
            assert.are.equal(119, loot[1].tradeMins)
        end)

        it("sorts critical trade timers (<= 30 min) first, then SR items, then free items", function()
            -- Item 1: Boots with 15m remaining (critical!)
            wow.addBagItem(0, 1, 49983, 1, "15m")

            -- Item 2: Belt with 1h 45m and 1 SR
            wow.addBagItem(0, 2, 49978, 1, "1h 45m")
            SR:AddSR("Member", ITEM_LINK_BELT, 1)

            local loot = SR:ScanBagsForLoot()
            assert.are.equal(2, #loot)
            -- Critical timer boots should be first!
            assert.are.equal(49983, loot[1].itemID)
            assert.are.equal(15, loot[1].tradeMins)
            -- Belt should be second
            assert.are.equal(49978, loot[2].itemID)
            assert.are.equal(1, loot[2].srCount)
        end)

        it("excludes personal soulbound gear without trade timer (e.g. leader's own Deathbringer's Will in bag)", function()
            local ITEM_LINK_DBW = "|cffa335ee|Hitem:50362:0:0:0:0:0:0:0|h[Deathbringer's Will]|h|r"
            wow.addItem(50362, "Deathbringer's Will", ITEM_LINK_DBW, 4)

            -- Item in bag is soulbound and has no trade timer (leader's personal gear)
            wow.addBagItem(0, 1, 50362, 1, nil, true)

            -- Even if someone in the raid soft-reserved DBW, the leader's own personal soulbound DBW
            -- CANNOT be traded, so it must not appear in the loot scanner!
            SR:AddSR("Member", ITEM_LINK_DBW, 1)

            local loot = SR:ScanBagsForLoot()
            assert.are.equal(0, #loot)
        end)

        it("includes fresh boss drop Deathbringer's Will that has an active trade timer", function()
            local ITEM_LINK_DBW = "|cffa335ee|Hitem:50362:0:0:0:0:0:0:0|h[Deathbringer's Will]|h|r"
            wow.addItem(50362, "Deathbringer's Will", ITEM_LINK_DBW, 4)

            -- Slot 1: Leader's own soulbound DBW (no trade timer) -> EXCLUDED
            wow.addBagItem(0, 1, 50362, 1, nil, true)

            -- Slot 2: Fresh DBW looted from Deathbringer Saurfang with 1h 55m trade timer -> INCLUDED
            wow.addBagItem(0, 2, 50362, 1, "1h 55m", true)

            SR:AddSR("Member", ITEM_LINK_DBW, 1)

            local loot = SR:ScanBagsForLoot()
            assert.are.equal(1, #loot)
            assert.are.equal(0, loot[1].bag)
            assert.are.equal(2, loot[1].slot)
            assert.are.equal(50362, loot[1].itemID)
            assert.are.equal(115, loot[1].tradeMins)
            assert.are.equal(1, loot[1].srCount)
        end)

        it("includes unbound BoE items but excludes equipped soulbound BoE items", function()
            -- Slot 1: Unbound BoE belt (not soulbound, drops in ICC) -> INCLUDED
            wow.addBagItem(0, 1, 49978, 1, nil, false)

            -- Slot 2: Previously equipped BoE boots (now soulbound without timer) -> EXCLUDED
            wow.addBagItem(0, 2, 49983, 1, nil, true)

            local loot = SR:ScanBagsForLoot()
            assert.are.equal(1, #loot)
            assert.are.equal(49978, loot[1].itemID)
            assert.are.equal(1, loot[1].slot)
        end)
    end)

    describe("SetLootSessionMode and SetLootItem", function()
        it("switches modes cleanly", function()
            SR:SetLootSessionMode("bag")
            assert.are.equal("bag", SR.lootSessionMode)

            SR:SetLootSessionMode("roll")
            assert.are.equal("roll", SR.lootSessionMode)
        end)

        it("automatically switches to 'roll' mode when SetLootItem is called", function()
            SR:SetLootSessionMode("bag")
            assert.are.equal("bag", SR.lootSessionMode)

            SR:SetLootItem(ITEM_LINK_BELT)
            assert.are.equal("roll", SR.lootSessionMode)
            assert.are.equal(49978, SR.currentLootItemID)
        end)

        it("accepts plain item ID string and resolves link", function()
            SR:SetLootItem("49978")
            assert.are.equal("roll", SR.lootSessionMode)
            assert.are.equal(49978, SR.currentLootItemID)
            assert.are.equal(ITEM_LINK_BELT, SR.currentLootItemLink)
        end)

        it("ClearLootItem cleans up active and current item fields", function()
            SR:SetLootItem(ITEM_LINK_BELT)
            assert.are.equal(49978, SR.currentLootItemID)

            SR:ClearLootItem()
            assert.is_nil(SR.currentLootItemID)
            assert.is_nil(SR.currentLootItemLink)
            assert.is_nil(SR.activeRollItem)
            assert.are.equal(0, #SR.activeRolls)
        end)

        it("defaults to bag mode in UpdateLootSession when no roll is active", function()
            SR.lootSessionMode = nil
            SR.activeRollItem = nil
            SR:UpdateLootSession()
            assert.are.equal("bag", SR.lootSessionMode)
        end)

        it("stays in roll mode in UpdateLootSession when a roll is currently active", function()
            SR:SetLootSessionMode("roll")
            SR.activeRollItem = 49978
            SR:UpdateLootSession()
            assert.are.equal("roll", SR.lootSessionMode)
        end)
    end)

    describe("InitBagLootTicker (periodic trade-timer refresh)", function()
        it("does not refresh when the bag loot tab isn't visible", function()
            local called = false
            SR.RefreshBagLoot = function() called = true end

            SR:InitBagLootTicker()
            local onUpdate = SR.bagLootTickerFrame._script_OnUpdate
            onUpdate(SR.bagLootTickerFrame, 31) -- past the interval, but nothing is shown

            assert.is_false(called)
        end)

        it("refreshes once elapsed time crosses the interval while the tab is visible", function()
            local called = 0
            SR.RefreshBagLoot = function() called = called + 1 end
            SR.mainFrame = { IsShown = function() return true end }
            SR.panels = { [4] = { IsShown = function() return true end } }
            SR.lootSessionMode = "bag"

            SR:InitBagLootTicker()
            local onUpdate = SR.bagLootTickerFrame._script_OnUpdate

            onUpdate(SR.bagLootTickerFrame, 10)
            assert.are.equal(0, called) -- not yet past the 30s interval

            onUpdate(SR.bagLootTickerFrame, 21) -- accumulated 31s
            assert.are.equal(1, called)
        end)

        it("does not build a second ticker frame if called twice", function()
            SR:InitBagLootTicker()
            local first = SR.bagLootTickerFrame
            SR:InitBagLootTicker()
            assert.are.equal(first, SR.bagLootTickerFrame)
        end)
    end)

    describe("Locales string completeness", function()
        it("defines all required BAG_LOOT, TAB, and UI locale keys", function()
            assert.are.equal("string", type(SR.L.BAG_LOOT_TAB))
            assert.are.equal("string", type(SR.L.BAG_LOOT_ACTIVE_ROLL))
            assert.are.equal("string", type(SR.L.BAG_LOOT_BACK_TO_BAGS))
            assert.are.equal("string", type(SR.L.BAG_LOOT_REFRESH))
            assert.are.equal("string", type(SR.L.BAG_LOOT_DISTRIBUTE_BTN))
            assert.are.equal("string", type(SR.L.TAB_SESSION))
            assert.are.equal("string", type(SR.L.UI_START_ROLL_BTN))
            assert.are.equal("string", type(SR.L.UI_END_ROLL_BTN))
            assert.are.equal("string", type(SR.L.LOOT_RESERVED_SUMMARY))
        end)
    end)
end)
