local load_addon = require("spec.support.load_addon")

describe("SR session authority and message-sender validation (Comms.lua)", function()
    local SR, wow

    before_each(function()
        SR, wow = load_addon.load()
    end)

    describe("PlayerHasLeaderAuthority", function()
        it("is true for the raid leader (rank 2)", function()
            wow.addRaidMember("Leader", 2)
            wow.addRaidMember("Assist", 1)
            wow.addRaidMember("Grunt", 0)
            assert.is_true(SR:PlayerHasLeaderAuthority("Leader"))
        end)

        it("is false for a raid assistant (rank 1) — only the leader may host", function()
            wow.addRaidMember("Leader", 2)
            wow.addRaidMember("Assist", 1)
            assert.is_false(SR:PlayerHasLeaderAuthority("Assist"))
        end)

        it("is false for a regular raid member", function()
            wow.addRaidMember("Leader", 2)
            wow.addRaidMember("Grunt", 0)
            assert.is_false(SR:PlayerHasLeaderAuthority("Grunt"))
        end)

        it("is false for a name that isn't in the raid at all", function()
            wow.addRaidMember("Leader", 2)
            assert.is_false(SR:PlayerHasLeaderAuthority("Ghost"))
        end)

        it("recognizes the local player as party leader when leaderIndex is 0", function()
            wow.state.playerName = "Me"
            wow.state.party = { "Buddy" } -- party of 2, no raid
            wow.state.partyLeaderIndex = 0
            assert.is_true(SR:PlayerHasLeaderAuthority("Me"))
            assert.is_false(SR:PlayerHasLeaderAuthority("Buddy"))
        end)

        it("recognizes another party member as leader via GetPartyLeaderIndex", function()
            wow.state.playerName = "Me"
            wow.state.party = { "Buddy" }
            wow.state.partyLeaderIndex = 1
            assert.is_true(SR:PlayerHasLeaderAuthority("Buddy"))
            assert.is_false(SR:PlayerHasLeaderAuthority("Me"))
        end)

        it("solo (no group) only grants authority to the local player", function()
            wow.state.playerName = "Solo"
            assert.is_true(SR:PlayerHasLeaderAuthority("Solo"))
            assert.is_false(SR:PlayerHasLeaderAuthority("AnyoneElse"))
        end)
    end)

    describe("OnSessionStart (S|hostName message)", function()
        it("accepts a session start from the real raid leader", function()
            wow.addRaidMember("Leader", 2)
            SR:OnSessionStart("Leader", "Leader")
            assert.is_true(SR.sessionActive)
            assert.are.equal("Leader", SR.sessionHost)
        end)

        it("rejects a forged hostName from a non-leader sender", function()
            wow.addRaidMember("Leader", 2)
            wow.addRaidMember("Sneaky", 0)
            -- Sneaky whispers "S|Leader" claiming Leader started a session,
            -- but the real (unspoofable) sender is Sneaky, who has no authority.
            SR:OnSessionStart("Leader", "Sneaky")
            assert.is_false(SR.sessionActive)
            assert.is_nil(SR.sessionHost)
        end)

        it("ignores the hostName field and trusts only the real sender", function()
            wow.addRaidMember("Leader", 2)
            -- Leader announces themself, but a bogus hostName is embedded in the message.
            SR:OnSessionStart("SomeoneElse", "Leader")
            assert.are.equal("Leader", SR.sessionHost)
        end)

        it("a re-announcement from the already-known active host does not trigger a resync", function()
            -- This is exactly what happens when the host's game crashes and they
            -- relog: their own client re-broadcasts "S|host" (thinking it's
            -- starting fresh), but every other client already knew this host was
            -- active. Re-syncing here used to wipe everyone's local SR list the
            -- moment the (possibly now-empty, post-crash) host replied.
            wow.addRaidMember("Leader", 2)
            SR:OnSessionStart("Leader", "Leader") -- first, genuine start: fires RequestSessionSync
            local sentBefore = #wow.state.sentAddon

            SR:OnSessionStart("Leader", "Leader") -- host re-announces after a reload

            assert.are.equal(sentBefore, #wow.state.sentAddon) -- no new 'Q' sent
        end)

        it("a session start from a genuinely different host still triggers a resync", function()
            wow.addRaidMember("OldLeader", 2)
            SR:OnSessionStart("OldLeader", "OldLeader")
            wow.addRaidMember("NewLeader", 2)

            SR:OnSessionStart("NewLeader", "NewLeader")

            local msgs = {}
            for _, m in ipairs(wow.state.sentAddon) do
                if m.msg == "Q" and m.target == "NewLeader" then msgs[#msgs + 1] = m end
            end
            assert.are.equal(1, #msgs)
        end)
    end)

    describe("OnSessionEnd (E|hostName message)", function()
        before_each(function()
            wow.addRaidMember("Leader", 2)
            SR:OnSessionStart("Leader", "Leader")
        end)

        it("ends the session when the real sender is the current host", function()
            SR:OnSessionEnd("Leader", "Leader")
            assert.is_false(SR.sessionActive)
            assert.is_nil(SR.sessionHost)
        end)

        it("ignores an end request forged by a non-host sender", function()
            wow.addRaidMember("Sneaky", 0)
            SR:OnSessionEnd("Leader", "Sneaky") -- claims to be ending "Leader"'s session
            assert.is_true(SR.sessionActive)
            assert.are.equal("Leader", SR.sessionHost)
        end)
    end)

    describe("ProcessSRRegistration limit enforcement", function()
        local ITEM_LINK = "|cffa335ee|Hitem:49978:0:0:0:0:0:0:0|h[Crushing Coldwraith Belt]|h|r"
        local ITEM_LINK_2 = "|cffa335ee|Hitem:49979:0:0:0:0:0:0:0|h[Handguards of Winter's Respite]|h|r"

        before_each(function()
            SR.locked = false
            wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
            wow.addItem(49979, "Handguards of Winter's Respite", ITEM_LINK_2)
            wow.addRaidMember("Member", 0) -- DPS by default, classic ICC limit = 3
        end)

        it("allows registering up to the role limit", function()
            local ok = SR:ProcessSRRegistration("Member", ITEM_LINK, 3, true)
            assert.is_true(ok)
            assert.are.equal(3, SR:GetUsedSRCount("Member"))
        end)

        it("rejects a registration that would exceed the role limit", function()
            SR:ProcessSRRegistration("Member", ITEM_LINK, 3, true)
            local ok, err = SR:ProcessSRRegistration("Member", ITEM_LINK_2, 1, true)
            assert.is_false(ok)
            assert.is_not_nil(err)
        end)

        it("isSet only charges the delta against the remaining limit", function()
            SR:ProcessSRRegistration("Member", ITEM_LINK, 2, true)
            -- Raising the same item from x2 to x3 only needs 1 more free slot, not 3.
            local ok = SR:ProcessSRRegistration("Member", ITEM_LINK, 3, true, true)
            assert.is_true(ok)
            assert.are.equal(3, SR:GetUsedSRCount("Member"))
        end)

        it("rejects registration for a player outside the raid", function()
            local ok, err = SR:ProcessSRRegistration("NotInRaid", ITEM_LINK, 1, true)
            assert.is_false(ok)
            assert.is_not_nil(err)
        end)
    end)

    describe("Anti-spoofing for sync, lock, overrides and co-hosts", function()
        before_each(function()
            wow.addRaidMember("Leader", 2)
            wow.addRaidMember("Sneaky", 0)
            SR:OnSessionStart("Leader", "Leader")
            SR.db.reserves["Existing"] = { { itemID = 49978, count = 1 } }
        end)

        it("ignores Z from a non-host and does not wipe local reserves", function()
            SR:OnAddonMessage("Z", "RAID", "Sneaky")
            assert.is_not_nil(SR.db.reserves["Existing"])
        end)

        it("ignores Z when sync was not pending even if from host", function()
            SR._syncPending = false
            SR:OnAddonMessage("Z", "RAID", "Leader")
            assert.is_not_nil(SR.db.reserves["Existing"])
        end)

        it("ignores Y from a non-host", function()
            SR:OnAddonMessage("Y|Impostor|TANK|49978:2", "RAID", "Sneaky")
            assert.is_nil(SR.db.reserves["Impostor"])
        end)

        it("ignores L from a non-host", function()
            SR.locked = false
            SR.sessionLocked = false
            SR:OnAddonMessage("L|1", "RAID", "Sneaky")
            assert.is_false(SR.sessionLocked)
            assert.is_false(SR.locked)
        end)

        it("ignores P from a non-host/non-cohost", function()
            SR:OnAddonMessage("P|Sneaky|10", "RAID", "Sneaky")
            assert.is_nil(SR.db.playerOverrides["Sneaky"])
        end)

        it("ignores O from a non-host", function()
            SR:OnAddonMessage("O|Sneaky", "RAID", "Sneaky")
            assert.is_nil(SR.sessionCoHosts)
        end)

        it("ignores a forged K reply from a non-host", function()
            SR._pendingSRItemID = 49978
            SR:OnAddonMessage("K|1|Fake success from Sneaky", "RAID", "Sneaky")
            assert.are.equal(49978, SR._pendingSRItemID)
            for _, msg in ipairs(wow.state.printed) do
                assert.is_nil(msg:find("Fake success", 1, true))
            end
        end)

        it("accepts a genuine K reply from the real host", function()
            SR._pendingSRItemID = 49978
            SR:OnAddonMessage("K|1|SR зареєстровано", "RAID", "Leader")
            assert.is_nil(SR._pendingSRItemID)
        end)
    end)

    describe("Anti-spoofing before any host is known yet (fresh login, no 'S|' received)", function()
        -- sessionHost is still nil here — this is the narrow window right after
        -- logging in, before the host's whispered reply to our own 'H' arrives.
        -- Session messages must fall back to requiring real raid/party leader
        -- authority in this window, not trust whoever happens to speak first.
        before_each(function()
            SR:InitItemCache()
            wow.addRaidMember("RealLeader", 2)
            wow.addRaidMember("Impostor", 0)
        end)

        it("rejects a Y sync update from a random member", function()
            SR:OnAddonMessage("Y|Someone|TANK|49978:2", "RAID", "Impostor")
            assert.is_nil(SR.db.reserves["Someone"])
        end)

        it("accepts a Y sync update from the real raid leader", function()
            SR:OnAddonMessage("Y|Someone|TANK|49978:2", "RAID", "RealLeader")
            assert.is_not_nil(SR.db.reserves["Someone"])
        end)

        it("rejects an O co-host list from a random member", function()
            SR:OnAddonMessage("O|Impostor", "RAID", "Impostor")
            assert.is_nil(SR.sessionCoHosts)
        end)

        it("accepts an O co-host list from the real raid leader", function()
            SR:OnAddonMessage("O|RealLeader", "RAID", "RealLeader")
            assert.is_not_nil(SR.sessionCoHosts)
        end)

        it("rejects an L lock-state change from a random member", function()
            SR.locked = false
            SR:OnAddonMessage("L|1", "RAID", "Impostor")
            assert.is_false(SR.locked)
        end)

        it("accepts an L lock-state change from the real raid leader", function()
            SR.locked = false
            SR:OnAddonMessage("L|1", "RAID", "RealLeader")
            assert.is_true(SR.locked)
        end)

        it("rejects a W wipe-all from a random member", function()
            SR.db.reserves["Existing"] = { { itemID = 1, count = 1 } }
            SR:OnAddonMessage("W", "RAID", "Impostor")
            assert.is_not_nil(SR.db.reserves["Existing"])
        end)

        it("accepts a W wipe-all from the real raid leader", function()
            SR.db.reserves["Existing"] = { { itemID = 1, count = 1 } }
            SR:OnAddonMessage("W", "RAID", "RealLeader")
            assert.is_nil(SR.db.reserves["Existing"])
        end)
    end)
end)
