local load_addon = require("spec.support.load_addon")

describe("SR loot tables and instance/equivalent-item helpers (LootData.lua)", function()
    local SR, wow

    before_each(function()
        SR, wow = load_addon.load()
    end)

    describe("GetCurrentLootData", function()
        it("returns ICC data by default", function()
            local data = SR:GetCurrentLootData()
            assert.are.equal(SR.LOOT_DATA.ICC, data)
        end)

        it("returns RS data when the active instance is RS", function()
            SR.db.instance = "RS"
            local data = SR:GetCurrentLootData()
            assert.are.equal(SR.LOOT_DATA.RS, data)
        end)

        it("falls back to ICC for an unrecognized instance key", function()
            SR.db.instance = "NAXX"
            local data = SR:GetCurrentLootData()
            assert.are.equal(SR.LOOT_DATA.ICC, data)
        end)
    end)

    describe("GetBossLoot", function()
        local boss

        before_each(function()
            boss = SR.LOOT_DATA.ICC[1] -- Lord Marrowgar
        end)

        it("returns the heroic list when difficulty is 25H", function()
            local loot = SR:GetBossLoot(boss, "25H")
            assert.are.equal(boss.loot25H, loot)
        end)

        it("returns the normal list when difficulty is 25N", function()
            local loot = SR:GetBossLoot(boss, "25N")
            assert.are.equal(boss.loot25N, loot)
        end)

        it("defaults to db.lootDifficulty when no difficulty argument is given", function()
            SR.db.lootDifficulty = "25N"
            local loot = SR:GetBossLoot(boss)
            assert.are.equal(boss.loot25N, loot)
        end)

        it("defaults to 25H when db.lootDifficulty is unset", function()
            SR.db.lootDifficulty = nil
            local loot = SR:GetBossLoot(boss)
            assert.are.equal(boss.loot25H, loot)
        end)

        it("returns an empty table for a difficulty list the boss doesn't define", function()
            local trashBoss = { name = "No loot25N boss", loot25H = { 1 } }
            local loot = SR:GetBossLoot(trashBoss, "25N")
            assert.are.same({}, loot)
        end)
    end)

    describe("GetEquivalentItemIDs / BuildEquivalentItemsMap", function()
        it("maps a normal-mode item to its heroic counterpart at the same list position", function()
            -- Lord Marrowgar, position 1: 49978 (N) <-> 50613 (H)
            local eq = SR:GetEquivalentItemIDs(49978)
            assert.is_true(eq[49978])
            assert.is_true(eq[50613])
        end)

        it("is symmetric: the heroic item maps back to the normal one", function()
            local eq = SR:GetEquivalentItemIDs(50613)
            assert.is_true(eq[49978])
        end)

        it("returns just itself for an item with no known equivalent", function()
            local eq = SR:GetEquivalentItemIDs(999999)
            assert.same({ [999999] = true }, eq)
        end)

        it("does not merge blacklisted T10 tier tokens even though they share a list position", function()
            -- Saurfang 25N and 25H both list the Conqueror's/Protector's/Vanquisher's
            -- Marks of Sanctification (52025-52027) at the same positions — these must
            -- NOT be treated as normal<->heroic equivalents of each other.
            local eq = SR:GetEquivalentItemIDs(52027)
            assert.same({ [52027] = true }, eq)
        end)

        it("does not map two items together when they're identical across N/H (no upgrade)", function()
            -- ICC trash (Precious's Ribbon) drops the exact same itemID in both lists.
            local eq = SR:GetEquivalentItemIDs(52019)
            assert.same({ [52019] = true }, eq)
        end)
    end)

    describe("IsValidItemForInstance", function()
        it("is true for an item that drops in the given instance", function()
            assert.is_true(SR:IsValidItemForInstance(49978, "ICC"))
        end)

        it("is true via an equivalent item ID (heroic item, checked against normal ID's instance)", function()
            -- 50613 only literally appears in the loot25H list, but resolving equivalents
            -- means checking for 49978's instance membership should also succeed for 50613.
            assert.is_true(SR:IsValidItemForInstance(50613, "ICC"))
        end)

        it("is false for an item that doesn't drop in the given instance", function()
            assert.is_false(SR:IsValidItemForInstance(53489, "ICC")) -- Halion (RS) item
        end)

        it("is false for an unknown instance name", function()
            assert.is_false(SR:IsValidItemForInstance(49978, "NAXX"))
        end)

        it("is false when itemID is nil", function()
            assert.is_false(SR:IsValidItemForInstance(nil, "ICC"))
        end)

        it("is false when instanceName is nil", function()
            assert.is_false(SR:IsValidItemForInstance(49978, nil))
        end)

        it("recognizes RS items against the RS instance", function()
            assert.is_true(SR:IsValidItemForInstance(53489, "RS"))
        end)
    end)
end)
