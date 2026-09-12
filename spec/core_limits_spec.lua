local load_addon = require("spec.support.load_addon")

local ITEM_LINK = "|cffa335ee|Hitem:49978:0:0:0:0:0:0:0|h[Crushing Coldwraith Belt]|h|r"
local ITEM_LINK_2 = "|cffa335ee|Hitem:49979:0:0:0:0:0:0:0|h[Handguards of Winter's Respite]|h|r"

describe("SR SR limits and reserve bookkeeping (Core.lua)", function()
    local SR, wow

    before_each(function()
        SR, wow = load_addon.load()
        wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
        wow.addItem(49979, "Handguards of Winter's Respite", ITEM_LINK_2)
    end)

    describe("GetSRLimit", function()
        it("returns the classic-mode ICC limit for the player's role", function()
            SR.db.roles["Tanky"] = "TANK"
            assert.are.equal(3, SR:GetSRLimit("Tanky"))
        end)

        it("returns the dynamic-mode limit which differs per role", function()
            SR.db.srMode = "dynamic"
            SR.db.roles["Tanky"] = "TANK"
            SR.db.roles["Dps1"] = "DPS"
            assert.are.equal(4, SR:GetSRLimit("Tanky"))
            assert.are.equal(3, SR:GetSRLimit("Dps1"))
        end)

        it("uses RS limits when the active instance is RS", function()
            SR.db.instance = "RS"
            SR.db.roles["Healy"] = "HEAL"
            assert.are.equal(1, SR:GetSRLimit("Healy"))
        end)

        it("defaults unknown players to the DPS role", function()
            assert.are.equal("DPS", SR:GetPlayerRole("NeverSeen"))
            assert.are.equal(3, SR:GetSRLimit("NeverSeen"))
        end)

        it("lets a personal override take priority over the role limit", function()
            SR.db.roles["Tanky"] = "TANK"
            SR:SetPlayerOverride("Tanky", 5)
            assert.are.equal(5, SR:GetSRLimit("Tanky"))
            -- the un-overridden base limit is still reported separately
            assert.are.equal(3, SR:GetBaseSRLimit("Tanky"))
        end)

        it("clearing an override (0 or nil) falls back to the role limit", function()
            SR.db.roles["Tanky"] = "TANK"
            SR:SetPlayerOverride("Tanky", 5)
            SR:SetPlayerOverride("Tanky", 0)
            assert.is_false(SR:HasOverride("Tanky"))
            assert.are.equal(3, SR:GetSRLimit("Tanky"))
        end)
    end)

    describe("AddSR / GetUsedSRCount / GetRemainingSR", function()
        it("adds a new reservation and counts it", function()
            local ok = SR:AddSR("Player1", ITEM_LINK, 1)
            assert.is_true(ok)
            assert.are.equal(1, SR:GetUsedSRCount("Player1"))
            assert.are.equal(2, SR:GetRemainingSR("Player1")) -- 3 - 1, default DPS limit
        end)

        it("accumulates count when the same item is soft-reserved again", function()
            SR:AddSR("Player1", ITEM_LINK, 1)
            SR:AddSR("Player1", ITEM_LINK, 1)
            assert.are.equal(2, SR:GetUsedSRCount("Player1"))
            assert.are.equal(1, #SR.db.reserves["Player1"]) -- merged into one entry
        end)

        it("keeps distinct items as separate entries", function()
            SR:AddSR("Player1", ITEM_LINK, 1)
            SR:AddSR("Player1", ITEM_LINK_2, 1)
            assert.are.equal(2, SR:GetUsedSRCount("Player1"))
            assert.are.equal(2, #SR.db.reserves["Player1"])
        end)

        it("isSet=true replaces the count instead of adding to it", function()
            SR:AddSR("Player1", ITEM_LINK, 1)
            SR:AddSR("Player1", ITEM_LINK, 2, true)
            assert.are.equal(2, SR:GetUsedSRCount("Player1"))
        end)

        it("rejects an unparseable item link", function()
            local ok, err = SR:AddSR("Player1", "not a real link", 1)
            assert.is_false(ok)
            assert.is_not_nil(err)
        end)
    end)

    describe("RemoveSR / ClearPlayerSR / ResetAllSR", function()
        it("removes a single reservation and cleans up an emptied list", function()
            SR:AddSR("Player1", ITEM_LINK, 1)
            local removed = SR:RemoveSR("Player1", 49978)
            assert.is_true(removed)
            assert.is_nil(SR.db.reserves["Player1"])
        end)

        it("returns false when removing an item the player never reserved", function()
            SR:AddSR("Player1", ITEM_LINK, 1)
            local removed = SR:RemoveSR("Player1", 99999)
            assert.is_false(removed)
        end)

        it("ClearPlayerSR wipes only that player's reserves", function()
            SR:AddSR("Player1", ITEM_LINK, 1)
            SR:AddSR("Player2", ITEM_LINK_2, 1)
            SR:ClearPlayerSR("Player1")
            assert.is_nil(SR.db.reserves["Player1"])
            assert.are.equal(1, SR:GetUsedSRCount("Player2"))
        end)

        it("ResetAllSR wipes every player's reserves", function()
            SR:AddSR("Player1", ITEM_LINK, 1)
            SR:AddSR("Player2", ITEM_LINK_2, 1)
            SR:ResetAllSR()
            assert.are.equal(0, SR:GetUsedSRCount("Player1"))
            assert.are.equal(0, SR:GetUsedSRCount("Player2"))
        end)
    end)
end)
