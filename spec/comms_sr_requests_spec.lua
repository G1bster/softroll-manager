local load_addon = require("spec.support.load_addon")

local ITEM_LINK = "|cffa335ee|Hitem:49978:0:0:0:0:0:0:0|h[Crushing Coldwraith Belt]|h|r"

describe("SR remote SR-management protocol: requests, replies, co-host commands (Comms.lua)", function()
    local SR, wow

    local function whispersTo(target)
        local out = {}
        for _, m in ipairs(wow.state.sentAddon) do
            if m.target == target then out[#out + 1] = m.msg end
        end
        return out
    end

    before_each(function()
        SR, wow = load_addon.load()
        wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
    end)

    describe("IsCoHost", function()
        it("is true only when flagged AND currently holding assistant+ rank in the raid", function()
            wow.addRaidMember("Ann", 1)
            SR.db.coHosts["Ann"] = true
            assert.is_true(SR:IsCoHost("Ann"))
        end)

        it("is false once the player loses their assistant rank, even if still flagged", function()
            wow.addRaidMember("Ann", 0)
            SR.db.coHosts["Ann"] = true
            assert.is_false(SR:IsCoHost("Ann"))
        end)

        it("is false for a flagged name that's no longer in the raid at all", function()
            SR.db.coHosts["Ann"] = true
            assert.is_false(SR:IsCoHost("Ann"))
        end)

        it("is false when never flagged as a co-host", function()
            wow.addRaidMember("Ann", 2)
            assert.is_false(SR:IsCoHost("Ann"))
        end)

        it("strips realm suffix when verifying raid rank for co-host", function()
            wow.addRaidMember("Ann-Icecrown", 1)
            SR.db.coHosts["Ann"] = true
            assert.is_true(SR:IsCoHost("Ann"))
        end)

        it("PlayerHasLeaderAuthority strips realm suffix when checking raid leader rank", function()
            wow.addRaidMember("Leader-Icecrown", 2)
            assert.is_true(SR:PlayerHasLeaderAuthority("Leader"))
        end)
    end)

    describe("CanEditSession / IsSessionReadOnly", function()
        it("CanEditSession is true for the host", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()
            assert.is_true(SR:CanEditSession())
            assert.is_false(SR:IsSessionReadOnly())
        end)

        it("CanEditSession is true for an announced co-host of someone else's session", function()
            wow.addRaidMember("Leader", 2)
            SR:OnSessionStart("Leader", "Leader")
            SR:OnCoHostsUpdate("TestPlayer")
            assert.is_true(SR:CanEditSession())
            assert.is_false(SR:IsSessionReadOnly())
        end)

        it("CanEditSession is false for a regular member; IsSessionReadOnly is then true", function()
            wow.addRaidMember("Leader", 2)
            SR:OnSessionStart("Leader", "Leader")
            assert.is_false(SR:CanEditSession())
            assert.is_true(SR:IsSessionReadOnly())
        end)

        it("IsSessionReadOnly is false outside of any session", function()
            assert.is_false(SR:IsSessionReadOnly())
        end)
    end)

    describe("RequestSRFromUI", function()
        before_each(function()
            SR:InitItemCache()
        end)

        it("refuses with no itemID selected", function()
            SR:RequestSRFromUI(nil, 1, nil, false)
            assert.matches("не вибрано", wow.state.printed[#wow.state.printed])
        end)

        it("refuses while soft-reserves are locked", function()
            SR.locked = true
            SR:RequestSRFromUI(49978, 1, nil, false)
            assert.matches("ЗАБЛОКОВАНІ", wow.state.printed[#wow.state.printed])
            assert.are.equal(0, #wow.state.sentAddon)
        end)

        it("auto-starts a session for an admin and still registers in the same click (auto-unlocks after auto-start)", function()
            -- solo: IsAdmin() and IsSessionLeader() are both true, so RequestSRFromUI's
            -- "admin can register even with no session" branch calls AutoStartSession().
            -- AutoStartSession() itself always starts locked (correct for the auto-join
            -- case), but RequestSRFromUI unlocks right after since the admin is
            -- deliberately registering something right now.
            SR.locked = false
            local ok = SR:RequestSRFromUI(49978, 1, nil, false)
            assert.is_true(SR.sessionActive)
            assert.is_true(ok)
            assert.is_false(SR.locked)
            assert.are.equal(1, SR:GetUsedSRCount("TestPlayer"))
        end)

        it("does not crash and reports no session for a raid officer (admin but not leader) with none active", function()
            wow.addRaidMember("TestPlayer", 0)
            wow.state.isRaidOfficer = true -- IsAdmin() true, but IsSessionLeader() requires the actual leader
            SR.locked = false

            local result = SR:RequestSRFromUI(49978, 1, nil, false)

            assert.is_nil(result)
            assert.is_false(SR.sessionActive) -- AutoStartSession() silently declined
            assert.matches("Немає активної сесії", wow.state.printed[#wow.state.printed])
        end)

        it("refuses a non-admin when there's no active session", function()
            wow.addRaidMember("Leader", 2)
            wow.addRaidMember("TestPlayer", 0)
            SR.locked = false
            local result = SR:RequestSRFromUI(49978, 1, nil, false)
            assert.is_nil(result)
            assert.matches("Немає активної сесії", wow.state.printed[#wow.state.printed])
        end)

        it("as host: registers for yourself and reports success without naming yourself", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR.locked = false -- set before StartSession so it also captures sessionLocked=false
            SR:StartSession()

            local ok = SR:RequestSRFromUI(49978, 1, nil, false)

            assert.is_true(ok)
            assert.matches("SR зареєстровано%.$", wow.state.printed[#wow.state.printed])
        end)

        it("as host: registers for another player and whispers them a notice", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.addRaidMember("Other", 0)
            wow.state.isRaidLeader = true
            SR.locked = false
            SR:StartSession()

            local ok = SR:RequestSRFromUI(49978, 1, "Other", false)

            assert.is_true(ok)
            assert.matches("для Other", wow.state.printed[#wow.state.printed])
            assert.are.equal(1, #whispersTo("Other"))
        end)

        it("as host: a registration failure is reported and returned", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR.locked = false
            SR:StartSession()

            local ok, err = SR:RequestSRFromUI(49978, 1, "NotInRaid", false)

            assert.is_false(ok)
            assert.is_not_nil(err)
            assert.matches("Помилка реєстрації", wow.state.printed[#wow.state.printed])
        end)

        it("as an announced co-host: sends an 'M' request to the host instead of editing locally", function()
            wow.addRaidMember("Leader", 2)
            SR:OnSessionStart("Leader", "Leader") -- also fires an unrelated 'Q' sync-request to Leader
            SR:OnCoHostsUpdate("TestPlayer")
            SR.locked = false

            local result = SR:RequestSRFromUI(49978, 2, "Someone", true)

            assert.are.equal("PENDING", result)
            assert.are.equal(49978, SR._pendingSRItemID)
            local mMsgs = {}
            for _, m in ipairs(whispersTo("Leader")) do
                if m:match("^M|") then mMsgs[#mMsgs + 1] = m end
            end
            assert.are.equal(1, #mMsgs)
            assert.are.equal("M|Someone|49978|2|1", mMsgs[1])
        end)

        it("as a plain client: refuses to register on someone else's behalf", function()
            wow.addRaidMember("Leader", 2)
            wow.addRaidMember("TestPlayer", 0)
            SR:OnSessionStart("Leader", "Leader")
            SR.locked = false
            local before = #wow.state.sentAddon

            local result = SR:RequestSRFromUI(49978, 1, "SomeoneElse", false)

            assert.is_nil(result)
            assert.are.equal(before, #wow.state.sentAddon) -- no new message sent
        end)

        it("as a plain client: sends an 'A' request for yourself to the host", function()
            wow.addRaidMember("Leader", 2)
            wow.addRaidMember("TestPlayer", 0)
            SR:OnSessionStart("Leader", "Leader") -- also fires an unrelated 'Q' sync-request to Leader
            SR.locked = false

            local result = SR:RequestSRFromUI(49978, 2, nil, false)

            assert.are.equal("PENDING", result)
            local aMsgs = {}
            for _, m in ipairs(whispersTo("Leader")) do
                if m:match("^A|") then aMsgs[#aMsgs + 1] = m end
            end
            assert.are.equal(1, #aMsgs)
            assert.are.equal("A|49978|2|0", aMsgs[1])
        end)
    end)

    describe("OnSRAddRequest", function()
        before_each(function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR.locked = false
        end)

        it("is ignored entirely by a non-host", function()
            SR.sessionActive = false
            local before = #wow.state.sentAddon
            SR:OnSRAddRequest("49978|1", "Someone")
            assert.are.equal(before, #wow.state.sentAddon)
        end)

        it("rejects a sender who isn't in the raid", function()
            SR:OnSRAddRequest("49978|1", "Ghost")
            local msgs = whispersTo("Ghost")
            assert.are.equal(1, #msgs)
            assert.matches("^K|0|", msgs[1])
            assert.matches("не в рейді", msgs[1])
        end)

        it("registers on success and replies with the sender's used/limit/role", function()
            wow.addRaidMember("Asker", 0)
            SR:OnSRAddRequest("49978|2", "Asker")
            assert.are.equal(2, SR:GetUsedSRCount("Asker"))
            local msgs = whispersTo("Asker")
            assert.matches("^K|1|", msgs[1])
            assert.matches("2 з 3", msgs[1])
        end)

        it("parses the trailing isSet flag", function()
            wow.addRaidMember("Asker", 0)
            SR:OnSRAddRequest("49978|3|1", "Asker")
            SR:OnSRAddRequest("49978|1|1", "Asker") -- isSet: replaces 3 with 1, not additive
            assert.are.equal(1, SR:GetUsedSRCount("Asker"))
        end)

        it("replies with an error when the registration is refused (over limit)", function()
            wow.addRaidMember("Asker", 0)
            SR:OnSRAddRequest("49978|5", "Asker") -- classic DPS limit is 3
            local msgs = whispersTo("Asker")
            assert.matches("^K|0|", msgs[1])
        end)

        it("silently ignores unparseable data", function()
            wow.addRaidMember("Asker", 0)
            SR:OnSRAddRequest("garbage", "Asker")
            assert.are.equal(0, #whispersTo("Asker"))
        end)
    end)

    describe("OnSRManageRequest (co-host adds SR for someone else)", function()
        before_each(function()
            wow.addRaidMember("TestPlayer", 2)
            wow.addRaidMember("CoHost", 1)
            wow.addRaidMember("Target", 0)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR.locked = false
            SR.db.coHosts["CoHost"] = true
        end)

        it("is ignored when the sender isn't an authorized co-host", function()
            SR:OnSRManageRequest("Target|49978|1", "RandomMember")
            assert.are.equal(0, SR:GetUsedSRCount("Target"))
            assert.are.equal(0, #whispersTo("RandomMember"))
        end)

        it("registers for the target and notifies the co-host and the raid chat", function()
            SR:OnSRManageRequest("Target|49978|1", "CoHost")

            assert.are.equal(1, SR:GetUsedSRCount("Target"))
            assert.are.equal(1, #whispersTo("CoHost"))
            assert.matches("Target", wow.state.sentChat[#wow.state.sentChat].msg)
        end)

        it("replies with an error and sends no chat announcement on failure", function()
            local chatBefore = #wow.state.sentChat
            SR:OnSRManageRequest("NotInRaid|49978|1", "CoHost")

            local msgs = whispersTo("CoHost")
            assert.matches("^K|0|", msgs[1])
            assert.are.equal(chatBefore, #wow.state.sentChat)
        end)
    end)

    describe("OnSRAddReply", function()
        it("prints a success message and clears the pending item on '1'", function()
            SR._pendingSRItemID = 49978
            SR:OnSRAddReply("1|Все ок")
            assert.matches("Все ок", wow.state.printed[#wow.state.printed])
            assert.is_nil(SR._pendingSRItemID)
        end)

        it("prints an error message and clears the pending item on '0'", function()
            SR._pendingSRItemID = 49978
            SR:OnSRAddReply("0|Забагато")
            assert.matches("Забагато", wow.state.printed[#wow.state.printed])
            assert.is_nil(SR._pendingSRItemID)
        end)
    end)

    describe("OnSRRemoveRequest", function()
        before_each(function()
            wow.addRaidMember("TestPlayer", 2)
            wow.addRaidMember("CoHost", 1)
            wow.addRaidMember("Member", 0)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR.locked = false
            SR.db.coHosts["CoHost"] = true
            SR:AddSR("Member", ITEM_LINK, 1)
        end)

        it("is ignored entirely by a non-host", function()
            SR.sessionActive = false
            SR:OnSRRemoveRequest("Member|49978", "Member")
            assert.are.equal(1, SR:GetUsedSRCount("Member")) -- untouched
        end)

        it("silently refuses removing someone else's SR without co-host rights", function()
            SR:OnSRRemoveRequest("Member|49978", "RandomMember")
            assert.are.equal(1, SR:GetUsedSRCount("Member"))
            assert.are.equal(0, #whispersTo("RandomMember"))
        end)

        it("silently refuses a self-removal request from someone not in the raid", function()
            SR:OnSRRemoveRequest("49978", "Ghost")
            assert.are.equal(0, #whispersTo("Ghost"))
        end)

        it("blocks a member's own removal while locked", function()
            SR.locked = true
            SR:OnSRRemoveRequest("49978", "Member")
            assert.are.equal(1, SR:GetUsedSRCount("Member"))
            assert.matches("ЗАБЛОКОВАНІ", whispersTo("Member")[1])
        end)

        it("lets a co-host remove another player's SR even while locked", function()
            SR.locked = true
            SR:OnSRRemoveRequest("Member|49978", "CoHost")
            assert.are.equal(0, SR:GetUsedSRCount("Member"))
            assert.matches("^K|1|", whispersTo("CoHost")[1])
        end)

        it("removes your own item and confirms with K|1 (no chat broadcast for self-removal)", function()
            local chatBefore = #wow.state.sentChat
            SR:OnSRRemoveRequest("49978", "Member")
            assert.are.equal(0, SR:GetUsedSRCount("Member"))
            assert.matches("^K|1|", whispersTo("Member")[1])
            assert.are.equal(chatBefore, #wow.state.sentChat)
        end)

        it("announces to chat when a co-host removes someone else's item", function()
            SR:OnSRRemoveRequest("Member|49978", "CoHost")
            assert.matches("Member", wow.state.sentChat[#wow.state.sentChat].msg)
        end)

        it("replies K|0 when the item was never reserved", function()
            SR:OnSRRemoveRequest("99999", "Member")
            assert.matches("^K|0|", whispersTo("Member")[1])
        end)
    end)

    describe("OnSRClearRequest", function()
        before_each(function()
            wow.addRaidMember("TestPlayer", 2)
            wow.addRaidMember("CoHost", 1)
            wow.addRaidMember("Member", 0)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR.locked = false
            SR.db.coHosts["CoHost"] = true
            SR:AddSR("Member", ITEM_LINK, 1)
        end)

        it("clears your own reserves", function()
            SR:OnSRClearRequest("", "Member")
            assert.are.equal(0, SR:GetUsedSRCount("Member"))
            assert.matches("^K|1|", whispersTo("Member")[1])
        end)

        it("refuses clearing someone else's reserves without co-host rights", function()
            SR:OnSRClearRequest("Member", "RandomMember")
            assert.are.equal(1, SR:GetUsedSRCount("Member"))
        end)

        it("lets a co-host clear another player's reserves even while locked", function()
            SR.locked = true
            SR:OnSRClearRequest("Member", "CoHost")
            assert.are.equal(0, SR:GetUsedSRCount("Member"))
        end)

        it("blocks a member's own clear request while locked", function()
            SR.locked = true
            SR:OnSRClearRequest("", "Member")
            assert.are.equal(1, SR:GetUsedSRCount("Member"))
            assert.matches("ЗАБЛОКОВАНІ", whispersTo("Member")[1])
        end)
    end)

    describe("OnWipeAll", function()
        it("as host: a co-host's wipe request resets all SR", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.addRaidMember("CoHost", 1)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR.db.coHosts["CoHost"] = true
            SR:AddSR("TestPlayer", ITEM_LINK, 1)

            SR:OnWipeAll("CoHost")

            assert.are.equal(0, SR:GetUsedSRCount("TestPlayer"))
        end)

        it("as host: a non-co-host's wipe request is ignored", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR:AddSR("TestPlayer", ITEM_LINK, 1)

            SR:OnWipeAll("RandomMember")

            assert.are.equal(1, SR:GetUsedSRCount("TestPlayer"))
        end)

        it("as a client: wipes local data when the message really is from the current host", function()
            wow.addRaidMember("Leader", 2)
            SR:OnSessionStart("Leader", "Leader")
            SR.db.reserves["Someone"] = { { itemID = 1, count = 1 } }
            SR.db.roles["Someone"] = "TANK"

            SR:OnWipeAll("Leader")

            assert.is_nil(next(SR.db.reserves))
            assert.is_nil(next(SR.db.roles))
        end)

        it("as a client: refuses a wipe forged by someone other than the current host", function()
            wow.addRaidMember("Leader", 2)
            SR:OnSessionStart("Leader", "Leader")
            SR.db.reserves["Someone"] = { { itemID = 1, count = 1 } }

            SR:OnWipeAll("Impostor")

            assert.is_not_nil(SR.db.reserves["Someone"])
        end)

        it("with no session tracked locally yet, refuses a wipe from a random member", function()
            -- Before the client has heard any 'S|' broadcast, sessionHost is nil.
            wow.addRaidMember("Leader", 2)
            wow.addRaidMember("RandomMember", 0)
            SR.db.reserves["Someone"] = { { itemID = 1, count = 1 } }

            SR:OnWipeAll("RandomMember")

            assert.is_not_nil(SR.db.reserves["Someone"])
        end)

        it("with no session tracked locally yet, still accepts a wipe from the real raid leader", function()
            wow.addRaidMember("Leader", 2)
            SR.db.reserves["Someone"] = { { itemID = 1, count = 1 } }

            SR:OnWipeAll("Leader")

            assert.is_nil(next(SR.db.reserves))
        end)
    end)

    describe("ProcessSRRegistration edge cases beyond limit enforcement", function()
        it("as host, refuses any registration while locked", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR.locked = true

            local ok, err = SR:ProcessSRRegistration("TestPlayer", ITEM_LINK, 1)

            assert.is_false(ok)
            assert.matches("ЗАБЛОКОВАНІ", err)
        end)

        it("refuses any direct registration while a session is hosted by someone else", function()
            wow.addRaidMember("Leader", 2)
            SR:OnSessionStart("Leader", "Leader")

            local ok, err = SR:ProcessSRRegistration("TestPlayer", ITEM_LINK, 1)

            assert.is_false(ok)
            assert.matches("Хост сесії", err)
        end)

        it("refuses registration while locked outside of any session (solo/admin editing)", function()
            SR.locked = true
            local ok, err = SR:ProcessSRRegistration("TestPlayer", ITEM_LINK, 1)
            assert.is_false(ok)
            assert.matches("ЗАБЛОКОВАНІ", err)
        end)
    end)

    describe("BroadcastPlayerSync / BroadcastFullSync", function()
        before_each(function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()
        end)

        it("BroadcastPlayerSync sends a Y message with the player's role and reserves", function()
            -- Set reserves directly (bypassing AddSR, which would itself trigger an
            -- automatic BroadcastPlayerSync as a side effect) to isolate this call.
            SR.db.reserves["TestPlayer"] = { { itemID = 49978, itemLink = ITEM_LINK, count = 2 } }
            local before = #wow.state.sentAddon

            SR:BroadcastPlayerSync("TestPlayer")

            local msgs = {}
            for _, m in ipairs(wow.state.sentAddon) do
                if m.msg:match("^Y|TestPlayer|") then msgs[#msgs + 1] = m.msg end
            end
            assert.are.equal(before + 1, #wow.state.sentAddon)
            assert.are.equal(1, #msgs)
            assert.matches("49978:2", msgs[1])
        end)

        it("BroadcastPlayerSync sends an empty reserve list for a player with none", function()
            SR:BroadcastPlayerSync("NoSRPlayer")
            local found = false
            for _, m in ipairs(wow.state.sentAddon) do
                if m.msg == "Y|NoSRPlayer|DPS|" then found = true end
            end
            assert.is_true(found)
        end)

        it("BroadcastFullSync sends a Y per reserving player, then a final Z", function()
            wow.addRaidMember("Other", 0)
            SR.db.reserves["TestPlayer"] = { { itemID = 49978, itemLink = ITEM_LINK, count = 1 } }
            SR.db.reserves["Other"] = { { itemID = 49978, itemLink = ITEM_LINK, count = 1 } }

            SR:BroadcastFullSync()

            local ys, zSeenAt, lastIdx = 0, nil, #wow.state.sentAddon
            for i, m in ipairs(wow.state.sentAddon) do
                if m.msg:match("^Y|") then ys = ys + 1 end
                if m.msg == "Z" then zSeenAt = i end
            end
            assert.are.equal(2, ys)
            assert.are.equal(lastIdx, zSeenAt)
        end)
    end)

    describe("Co-host administrative requests", function()
        before_each(function()
            wow.addRaidMember("TestPlayer", 2)
            wow.addRaidMember("CoHost", 1)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR.db.coHosts["CoHost"] = true
        end)

        describe("OnRoleChangeRequest", function()
            it("applies the role change when the sender is an authorized co-host", function()
                SR:OnRoleChangeRequest("Member|TANK", "CoHost")
                assert.are.equal("TANK", SR.db.roles["Member"])
            end)

            it("is ignored for a sender without co-host rights", function()
                SR:OnRoleChangeRequest("Member|TANK", "RandomMember")
                assert.is_nil(SR.db.roles["Member"])
            end)
        end)

        describe("OnOverrideChangeRequest", function()
            it("applies the override change when the sender is an authorized co-host", function()
                SR:OnOverrideChangeRequest("Member|5", "CoHost")
                assert.are.equal(5, SR:GetPlayerOverride("Member"))
            end)

            it("is ignored for a sender without co-host rights", function()
                SR:OnOverrideChangeRequest("Member|5", "RandomMember")
                assert.is_nil(SR:GetPlayerOverride("Member"))
            end)
        end)

        describe("OnLockChangeRequest", function()
            it("locks, updates db.locked, and announces to raid chat", function()
                SR.locked = false
                SR:OnLockChangeRequest("1", "CoHost")
                assert.is_true(SR.locked)
                assert.is_true(SR.db.locked)
                assert.matches("ЗАБЛОКОВАНО", wow.state.sentChat[#wow.state.sentChat].msg)
            end)

            it("unlocks and announces to raid chat", function()
                SR.locked = true
                SR:OnLockChangeRequest("0", "CoHost")
                assert.is_false(SR.locked)
                assert.matches("РОЗБЛОКОВАНО", wow.state.sentChat[#wow.state.sentChat].msg)
            end)

            it("is ignored for a sender without co-host rights", function()
                SR.locked = false
                SR:OnLockChangeRequest("1", "RandomMember")
                assert.is_false(SR.locked)
            end)
        end)
    end)

    describe("OnPlayerOverrideSync (client applying a P broadcast)", function()
        it("sets an override with a positive limit", function()
            SR:OnPlayerOverrideSync("Member|5")
            assert.are.equal(5, SR.db.playerOverrides["Member"])
        end)

        it("clears the override when the limit is 0", function()
            SR.db.playerOverrides["Member"] = 5
            SR:OnPlayerOverrideSync("Member|0")
            assert.is_nil(SR.db.playerOverrides["Member"])
        end)

        it("is ignored by the host (host data is authoritative)", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR:OnPlayerOverrideSync("Member|5")
            assert.is_nil(SR.db.playerOverrides["Member"])
        end)
    end)

    describe("OnAddonMessage 'I' (instance/mode) routing", function()
        it("as a client, applies an instance/mode change from the current session host", function()
            wow.addRaidMember("Leader", 2)
            SR:OnSessionStart("Leader", "Leader")
            SR:OnAddonMessage("I|RS|dynamic", "RAID", "Leader")
            assert.are.equal("RS", SR.db.instance)
            assert.are.equal("dynamic", SR.db.srMode)
        end)

        it("as a client, ignores an instance/mode change forged by anyone other than the host", function()
            wow.addRaidMember("Leader", 2)
            SR:OnSessionStart("Leader", "Leader")
            SR.db.instance = "ICC"
            SR:OnAddonMessage("I|RS|dynamic", "RAID", "RandomMember")
            assert.are.equal("ICC", SR.db.instance)
        end)

        it("as host, applies and rebroadcasts an instance/mode change from a co-host", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.addRaidMember("CoHost", 1)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR.db.coHosts["CoHost"] = true

            SR:OnAddonMessage("I|RS|dynamic", "RAID", "CoHost")

            assert.are.equal("RS", SR.db.instance)
            local rebroadcast = false
            for _, m in ipairs(wow.state.sentAddon) do
                if m.msg == "I|RS|dynamic" and m.target == nil then rebroadcast = true end
            end
            assert.is_true(rebroadcast)
        end)

        it("as host, ignores an instance/mode change from a non-co-host", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR.db.instance = "ICC"

            SR:OnAddonMessage("I|RS|dynamic", "RAID", "RandomMember")

            assert.are.equal("ICC", SR.db.instance)
        end)
    end)

    describe("Malformed Network Packets & Edge Cases", function()
        before_each(function()
            wow.addRaidMember("TestPlayer", 2)
            wow.addRaidMember("CoHost", 1)
            wow.addRaidMember("Member", 0)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR.locked = false
            SR.sessionLocked = false
            SR.db.coHosts["CoHost"] = true
        end)

        it("OnAddonMessage safely ignores empty or nil messages", function()
            assert.has_no.errors(function()
                SR:OnAddonMessage(nil, "RAID", "Member")
                SR:OnAddonMessage("", "RAID", "Member")
            end)
        end)

        it("OnSRAddRequest handles malformed data gracefully", function()
            assert.has_no.errors(function()
                SR:OnSRAddRequest("", "Member")
                SR:OnSRAddRequest("invalid", "Member")
                SR:OnSRAddRequest("|bad|data", "Member")
            end)
            assert.are.equal(0, SR:GetUsedSRCount("Member"))
        end)

        it("OnSRAddRequest accepts itemID without count as count=1", function()
            SR:OnSRAddRequest("49978", "Member")
            assert.are.equal(1, SR:GetUsedSRCount("Member"))
        end)

        it("OnSRManageRequest strips realm and handles single itemID", function()
            SR:OnSRManageRequest("Member-Icecrown|49978", "CoHost")
            assert.are.equal(1, SR:GetUsedSRCount("Member"))
        end)

        it("OnSRRemoveRequest handles cross-realm names and itemLink", function()
            SR:AddSR("Member", ITEM_LINK, 1)
            SR:OnSRRemoveRequest("Member-Icecrown|49978", "CoHost")
            assert.are.equal(0, SR:GetUsedSRCount("Member"))
        end)

        it("OnSRClearRequest handles cross-realm names", function()
            SR:AddSR("Member", ITEM_LINK, 2)
            SR:OnSRClearRequest("Member-Icecrown", "CoHost")
            assert.are.equal(0, SR:GetUsedSRCount("Member"))
        end)

        it("ProcessSRRegistration rejects empty or nil senderName", function()
            local ok, err = SR:ProcessSRRegistration(nil, ITEM_LINK, 1)
            assert.is_false(ok)
            assert.matches("Невідомий гравець", err)

            local ok2, err2 = SR:ProcessSRRegistration("", ITEM_LINK, 1)
            assert.is_false(ok2)
            assert.matches("Невідомий гравець", err2)
        end)

        it("ProcessSRRegistration handles cross-realm senderName", function()
            local ok = SR:ProcessSRRegistration("Member-Icecrown", ITEM_LINK, 1)
            assert.is_true(ok)
            assert.are.equal(1, SR:GetUsedSRCount("Member"))
        end)
    end)
end)
