local load_addon = require("spec.support.load_addon")

describe("SR role management, raid roster, and admin checks (Core.lua)", function()
    local SR, wow

    before_each(function()
        SR, wow = load_addon.load()
    end)

    describe("GetPlayerRole / SetPlayerRole", function()
        it("defaults to DPS for a nil name", function()
            assert.are.equal("DPS", SR:GetPlayerRole(nil))
        end)

        it("sets the role directly when there's no active session", function()
            SR:SetPlayerRole("Tanky", "TANK")
            assert.are.equal("TANK", SR.db.roles["Tanky"])
        end)

        it("sets the role directly when the local player is the session host", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR:SetPlayerRole("Tanky", "TANK")
            assert.are.equal("TANK", SR.db.roles["Tanky"])
        end)

        it("a co-host without host status sends a request instead of editing locally", function()
            wow.addRaidMember("Leader", 2)
            SR.sessionActive = true
            SR.sessionHost = "Leader"
            SR.sessionCoHosts = { TestPlayer = true }

            SR:SetPlayerRole("Tanky", "TANK")

            assert.is_nil(SR.db.roles["Tanky"]) -- not applied locally
            assert.are.equal(1, #wow.state.sentAddon)
            local sent = wow.state.sentAddon[1]
            assert.are.equal("V|Tanky|TANK", sent.msg)
            assert.are.equal("WHISPER", sent.distribution)
            assert.are.equal("Leader", sent.target)
        end)

        it("a plain raid member with no edit rights sends nothing at all", function()
            wow.addRaidMember("Leader", 2)
            SR.sessionActive = true
            SR.sessionHost = "Leader"
            -- no sessionCoHosts entry for the local player

            SR:SetPlayerRole("Tanky", "TANK")

            assert.is_nil(SR.db.roles["Tanky"])
            assert.are.equal(0, #wow.state.sentAddon)
        end)
    end)

    describe("AutoDetectRole", function()
        it("detects TANK from the MAINTANK raid role flag", function()
            assert.are.equal("TANK", SR:AutoDetectRole({ raidRole = "MAINTANK", rank = 0 }))
        end)

        it("detects RL from raid rank 2, even without a raid role flag", function()
            assert.are.equal("RL", SR:AutoDetectRole({ rank = 2 }))
        end)

        it("prefers MAINTANK over the rank-2 RL rule", function()
            assert.are.equal("TANK", SR:AutoDetectRole({ raidRole = "MAINTANK", rank = 2 }))
        end)

        it("returns nil when nothing can be reliably detected", function()
            assert.is_nil(SR:AutoDetectRole({ rank = 0 }))
        end)
    end)

    describe("CanEditPlayerSR", function()
        it("is true for anyone when the local player can edit the session (host)", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()
            assert.is_true(SR:CanEditPlayerSR("SomeoneElse"))
        end)

        it("is true for your own name when soft-reserves aren't locked", function()
            SR.locked = false
            assert.is_true(SR:CanEditPlayerSR("TestPlayer"))
        end)

        it("is false for your own name when locked", function()
            SR.locked = true
            assert.is_false(SR:CanEditPlayerSR("TestPlayer"))
        end)

        it("is false for your own name when the session (not the local lock) is locked", function()
            SR.locked = false
            SR.sessionLocked = true
            assert.is_false(SR:CanEditPlayerSR("TestPlayer"))
        end)

        it("is false for someone else's name without edit rights", function()
            assert.is_false(SR:CanEditPlayerSR("SomeoneElse"))
        end)
    end)

    describe("Wishlist management", function()
        it("starts with an empty wishlist", function()
            assert.is_false(SR:IsInWishlist(1234))
            assert.same({}, SR:GetWishlistItems())
        end)

        it("adds an item on first toggle", function()
            SR:ToggleWishlistItem(1234)
            assert.is_true(SR:IsInWishlist(1234))
            assert.same({ 1234 }, SR:GetWishlistItems())
        end)

        it("removes the item again on a second toggle", function()
            SR:ToggleWishlistItem(1234)
            SR:ToggleWishlistItem(1234)
            assert.is_false(SR:IsInWishlist(1234))
            assert.same({}, SR:GetWishlistItems())
        end)

        it("returns items sorted by itemID", function()
            SR:ToggleWishlistItem(300)
            SR:ToggleWishlistItem(100)
            SR:ToggleWishlistItem(200)
            assert.same({ 100, 200, 300 }, SR:GetWishlistItems())
        end)

        it("keeps wishlists separate per local player", function()
            SR:ToggleWishlistItem(1234)
            wow.state.playerName = "OtherPlayer"
            assert.is_false(SR:IsInWishlist(1234))
        end)
    end)

    describe("GetRoleSortWeight", function()
        it("ranks the raid leader (rank 2) first regardless of role", function()
            SR.db.roles["Someone"] = "DPS"
            assert.are.equal(1, SR:GetRoleSortWeight("Someone", 2))
        end)

        it("ranks an RL-flagged player first even without raid rank 2", function()
            SR.db.roles["Someone"] = "RL"
            assert.are.equal(1, SR:GetRoleSortWeight("Someone", 0))
        end)

        it("orders TANK < HEAL < DPS < unknown", function()
            SR.db.roles["T"] = "TANK"
            SR.db.roles["H"] = "HEAL"
            SR.db.roles["D"] = "DPS"
            SR.db.roles["X"] = "SOMETHING_ELSE"
            assert.are.equal(2, SR:GetRoleSortWeight("T", 0))
            assert.are.equal(3, SR:GetRoleSortWeight("H", 0))
            assert.are.equal(4, SR:GetRoleSortWeight("D", 0))
            assert.are.equal(5, SR:GetRoleSortWeight("X", 0))
        end)
    end)

    describe("IsInRaid", function()
        it("is true for a member present in the raid roster", function()
            wow.addRaidMember("Member", 0)
            assert.is_true(SR:IsInRaid("Member"))
        end)

        it("is false for a name not in the raid roster", function()
            wow.addRaidMember("Member", 0)
            assert.is_false(SR:IsInRaid("Ghost"))
        end)

        it("falls back to party/solo membership when there is no raid formed", function()
            wow.state.party = { "Buddy" }
            assert.is_true(SR:IsInRaid("TestPlayer")) -- local player
            assert.is_true(SR:IsInRaid("Buddy"))      -- party member
            assert.is_false(SR:IsInRaid("Ghost"))
        end)

        it("recognizes the solo local player with no group at all", function()
            assert.is_true(SR:IsInRaid("TestPlayer"))
        end)
    end)

    describe("IsAdmin", function()
        it("in a raid: true only for the raid leader or officer", function()
            wow.addRaidMember("TestPlayer", 0)
            wow.state.isRaidLeader = false
            wow.state.isRaidOfficer = false
            assert.is_false(SR:IsAdmin())

            wow.state.isRaidOfficer = true
            assert.is_true(SR:IsAdmin())
        end)

        it("in a party (no raid): true only for the party leader", function()
            wow.state.party = { "Buddy" }
            wow.state.isPartyLeader = false
            assert.is_false(SR:IsAdmin())

            wow.state.isPartyLeader = true
            assert.is_true(SR:IsAdmin())
        end)

        it("solo (no group at all): always true", function()
            assert.is_true(SR:IsAdmin())
        end)
    end)

    describe("IsSessionLeader", function()
        it("in a raid: mirrors IsRaidLeader", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            assert.is_true(SR:IsSessionLeader())
            wow.state.isRaidLeader = false
            assert.is_false(SR:IsSessionLeader())
        end)

        it("in a party: mirrors IsPartyLeader (raid officer doesn't count)", function()
            wow.state.party = { "Buddy" }
            wow.state.isRaidOfficer = true
            wow.state.isPartyLeader = false
            assert.is_false(SR:IsSessionLeader())
        end)

        it("solo: always true", function()
            assert.is_true(SR:IsSessionLeader())
        end)
    end)

    describe("GetRaidMembers", function()
        it("builds and sorts the list from the raid roster (leader/tank/heal/dps, then name)", function()
            wow.addRaidMember("Zed", 0, { class = "MAGE" })       -- DPS
            wow.addRaidMember("Ann", 2)                           -- leader
            wow.addRaidMember("Boris", 0, { class = "WARRIOR" })  -- DPS
            SR.db.roles["Boris"] = "TANK"

            local members = SR:GetRaidMembers()
            local names = {}
            for _, m in ipairs(members) do names[#names + 1] = m.name end

            assert.same({ "Ann", "Boris", "Zed" }, names) -- leader, tank, then dps alphabetically
        end)

        it("falls back to the local player alone when solo (no raid, no party)", function()
            local members = SR:GetRaidMembers()
            assert.are.equal(1, #members)
            assert.are.equal("TestPlayer", members[1].name)
            assert.are.equal(2, members[1].rank) -- solo counts as your own leader
        end)

        it("in a party (not leader): includes the player and party members with rank 0", function()
            wow.state.party = { "Buddy" }
            wow.state.isPartyLeader = false

            local members = SR:GetRaidMembers()
            local byName = {}
            for _, m in ipairs(members) do byName[m.name] = m end

            assert.is_not_nil(byName["TestPlayer"])
            assert.is_not_nil(byName["Buddy"])
            assert.are.equal(0, byName["TestPlayer"].rank)
            assert.are.equal(0, byName["Buddy"].rank)
        end)

        it("in a party where the local player is the leader: player gets rank 2", function()
            wow.state.party = { "Buddy" }
            wow.state.isPartyLeader = true

            local members = SR:GetRaidMembers()
            local byName = {}
            for _, m in ipairs(members) do byName[m.name] = m end

            assert.are.equal(2, byName["TestPlayer"].rank)
        end)
    end)
end)
