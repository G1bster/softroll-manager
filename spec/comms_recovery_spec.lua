local load_addon = require("spec.support.load_addon")

local ITEM_LINK = "|cffa335ee|Hitem:49978:0:0:0:0:0:0:0|h[Crushing Coldwraith Belt]|h|r"

describe("SR data-recovery protocol: RP/RA/RQ/RY/RZ (Comms.lua)", function()
    local SR, wow

    local function addonMsgsMatching(pattern)
        local out = {}
        for _, m in ipairs(wow.state.sentAddon) do
            if m.msg:match(pattern) then out[#out + 1] = m end
        end
        return out
    end

    before_each(function()
        SR, wow = load_addon.load()
        wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
    end)

    describe("ShouldPromptDataRecovery", function()
        it("is false when reserves already has data", function()
            SR.db.reserves["Someone"] = { { itemID = 1, count = 1 } }
            wow.addRaidMember("Someone", 0)
            wow.addRaidMember("Other", 0)
            assert.is_false(SR:ShouldPromptDataRecovery())
        end)

        it("is false when solo (no one else to recover from anyway)", function()
            assert.is_false(SR:ShouldPromptDataRecovery())
        end)

        it("is true when reserves are empty but the raid already has other members", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.addRaidMember("Other", 0)
            assert.is_true(SR:ShouldPromptDataRecovery())
        end)
    end)

    describe("StartSession / AutoStartSession trigger the recovery prompt hook", function()
        it("StartSession calls ShowDataRecoveryPrompt when reserves look suspiciously empty", function()
            local called = false
            SR.ShowDataRecoveryPrompt = function() called = true end
            wow.addRaidMember("TestPlayer", 2)
            wow.addRaidMember("Other", 0)
            wow.state.isRaidLeader = true

            SR:StartSession()

            assert.is_true(called)
        end)

        it("StartSession does not prompt when reserves already have data", function()
            local called = false
            SR.ShowDataRecoveryPrompt = function() called = true end
            wow.addRaidMember("TestPlayer", 2)
            wow.addRaidMember("Other", 0)
            wow.state.isRaidLeader = true
            SR.db.reserves["Other"] = { { itemID = 1, count = 1 } }

            SR:StartSession()

            assert.is_false(called)
        end)

        it("AutoStartSession calls ShowDataRecoveryPrompt under the same condition", function()
            local called = false
            SR.ShowDataRecoveryPrompt = function() called = true end
            wow.addRaidMember("TestPlayer", 2)
            wow.addRaidMember("Other", 0)
            wow.state.isRaidLeader = true

            SR:AutoStartSession()

            assert.is_true(called)
        end)

        it("does nothing if no UI is loaded (hook absent) — no crash", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.addRaidMember("Other", 0)
            wow.state.isRaidLeader = true
            assert.has_no.errors(function() SR:StartSession() end)
        end)
    end)

    describe("StartRecoveryScan / OnRecoveryPing / OnRecoveryAck", function()
        before_each(function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()
        end)

        it("StartRecoveryScan (host) broadcasts RP and is a no-op for non-hosts", function()
            SR:StartRecoveryScan()
            assert.are.equal(1, #addonMsgsMatching("^RP$"))

            SR.sessionHost = "SomeoneElse"
            local before = #wow.state.sentAddon
            SR:StartRecoveryScan()
            assert.are.equal(before, #wow.state.sentAddon)
        end)

        it("OnRecoveryPing replies with a count only when there's cached data", function()
            SR:OnRecoveryPing("TestPlayer") -- self is host, trusted
            assert.are.equal(0, #addonMsgsMatching("^RA|"))

            SR.db.reserves["Someone"] = { { itemID = 49978, count = 2 } }
            SR:OnRecoveryPing("TestPlayer")
            local msgs = addonMsgsMatching("^RA|")
            assert.are.equal(1, #msgs)
            assert.are.equal("RA|TestPlayer|1", msgs[1].msg)
        end)

        it("OnRecoveryPing ignores a ping not from the current session host", function()
            SR.db.reserves["Someone"] = { { itemID = 49978, count = 1 } }
            SR:OnRecoveryPing("RandomImpostor")
            assert.are.equal(0, #addonMsgsMatching("^RA|"))
        end)

        it("OnRecoveryPing, with no session tracked, trusts a real leader instead", function()
            SR.sessionActive = false
            SR.sessionHost = nil
            SR.db.reserves["Someone"] = { { itemID = 49978, count = 1 } }
            wow.addRaidMember("RealLeader", 2)

            SR:OnRecoveryPing("RealLeader")
            assert.are.equal(1, #addonMsgsMatching("^RA|"))

            wow.addRaidMember("RandomMember", 0)
            SR:OnRecoveryPing("RandomMember")
            assert.are.equal(1, #addonMsgsMatching("^RA|")) -- still just the one from before
        end)

        it("OnRecoveryAck is ignored without an active scan, and ignored by non-hosts", function()
            SR:OnRecoveryAck("Someone|3", "Someone")
            assert.is_nil(SR._recoveryResponses)

            SR:StartRecoveryScan()
            SR.sessionHost = "SomeoneElse"
            SR:OnRecoveryAck("Someone|3", "Someone")
            assert.is_nil(SR._recoveryResponses["Someone"])
        end)

        it("OnRecoveryAck records a responder's reported cache size", function()
            SR:StartRecoveryScan()
            SR:OnRecoveryAck("Backup|7", "Backup")
            assert.are.same({ name = "Backup", count = 7 }, SR._recoveryResponses["Backup"])
        end)
    end)

    describe("RequestRecoveryFrom / OnRecoveryQuery (target side)", function()
        it("RequestRecoveryFrom (host) whispers RQ to the chosen target", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()

            SR:RequestRecoveryFrom("Backup")

            local msgs = addonMsgsMatching("^RQ$")
            assert.are.equal(1, #msgs)
            assert.are.equal("Backup", msgs[1].target)
            assert.is_true(SR._recoveryPending)
        end)

        it("is a no-op for a non-host", function()
            local before = #wow.state.sentAddon
            SR:RequestRecoveryFrom("Backup")
            assert.are.equal(before, #wow.state.sentAddon)
        end)

        it("OnRecoveryQuery (target) only replies to the real current session host", function()
            wow.addRaidMember("Leader", 2)
            SR:OnSessionStart("Leader", "Leader")
            SR.db.reserves["Cached1"] = { { itemID = 49978, itemLink = ITEM_LINK, count = 2 } }

            SR:OnRecoveryQuery("Impostor")
            assert.are.equal(0, #addonMsgsMatching("^RY|"))

            SR:OnRecoveryQuery("Leader")
            local ry = addonMsgsMatching("^RY|")
            assert.are.equal(1, #ry)
            assert.matches("^RY|Cached1|", ry[1].msg)
            assert.are.equal(1, #addonMsgsMatching("^RZ$"))
        end)
    end)

    describe("OnRecoveryData / OnRecoveryComplete (host applies the recovered snapshot)", function()
        before_each(function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR:RequestRecoveryFrom("Backup")
        end)

        it("ignores data/complete from anyone other than the client we actually queried", function()
            SR:OnRecoveryData("Someone|TANK|49978:2", "NotBackup")
            SR:OnRecoveryComplete("NotBackup")
            assert.is_nil(SR.db.reserves["Someone"])
            assert.is_true(SR._recoveryPending) -- still waiting on the real target
        end)

        it("ignores everything if no recovery is pending", function()
            SR._recoveryPending = false
            SR:OnRecoveryData("Someone|TANK|49978:2", "Backup")
            assert.is_nil(SR._recoveryData["Someone"])
        end)

        it("merges recovered entries into db.reserves and roles, then reports and re-broadcasts", function()
            SR:OnRecoveryData("Recovered1|TANK|49978:2", "Backup")
            SR:OnRecoveryData("Recovered2|HEAL|49978:1", "Backup")

            SR:OnRecoveryComplete("Backup")

            assert.are.equal(2, SR:GetUsedSRCount("Recovered1"))
            assert.are.equal("TANK", SR.db.roles["Recovered1"])
            assert.are.equal(1, SR:GetUsedSRCount("Recovered2"))
            assert.is_false(SR._recoveryPending)
            assert.matches("Відновлено", wow.state.printed[#wow.state.printed])

            -- re-broadcasts the freshly recovered state to the raid
            assert.is_true(#addonMsgsMatching("^Y|Recovered1|") > 0)
            assert.is_true(#addonMsgsMatching("^Z$") > 0)
        end)
    end)

    describe("End-to-end recovery round trip", function()
        it("host scans, picks the best responder, queries them, and rebuilds its own reserves", function()
            wow.addRaidMember("TestPlayer", 2) -- host
            wow.addRaidMember("Backup", 0)     -- has a cached copy
            wow.state.isRaidLeader = true
            SR:StartSession()

            -- 1) host scans the raid
            SR:StartRecoveryScan()
            -- 2) Backup (simulated as if we're now Backup's client reacting to RP) acks
            SR:OnRecoveryAck("Backup|1", "Backup")
            assert.is_not_nil(SR._recoveryResponses["Backup"])

            -- 3) host picks Backup
            SR:RequestRecoveryFrom("Backup")

            -- 4) Backup's client (simulated) replies to the RQ it "received"
            SR:OnRecoveryQuery("TestPlayer") -- host is sender from Backup's point of view
            -- (in reality this sends RY/RZ back to the host; here we just feed the
            -- same data straight into the host-side handlers to simulate delivery)
            SR:OnRecoveryData("Recovered|DPS|49978:3", "Backup")
            SR:OnRecoveryComplete("Backup")

            assert.are.equal(3, SR:GetUsedSRCount("Recovered"))
        end)
    end)
end)
