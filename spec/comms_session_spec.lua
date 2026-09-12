local load_addon = require("spec.support.load_addon")

describe("SR session lifecycle, sync protocol, and co-host broadcast (Comms.lua)", function()
    local SR, wow

    local function lastAddonMsg()
        return wow.state.sentAddon[#wow.state.sentAddon]
    end

    local function addonMsgsMatching(pattern)
        local out = {}
        for _, m in ipairs(wow.state.sentAddon) do
            if m.msg:match(pattern) then out[#out + 1] = m end
        end
        return out
    end

    before_each(function()
        SR, wow = load_addon.load()
    end)

    describe("StripRealm / GetLocalPlayerName", function()
        it("strips a realm suffix", function()
            assert.are.equal("Ann", SR:StripRealm("Ann-Realmname"))
        end)

        it("returns the name unchanged when there's no realm suffix", function()
            assert.are.equal("Ann", SR:StripRealm("Ann"))
        end)

        it("returns nil for a nil name", function()
            assert.is_nil(SR:StripRealm(nil))
        end)

        it("GetLocalPlayerName strips the realm off the player's own name", function()
            wow.state.playerName = "TestPlayer-SomeRealm"
            assert.are.equal("TestPlayer", SR:GetLocalPlayerName())
        end)
    end)

    describe("IsSessionHost", function()
        it("is false when there is no active session", function()
            assert.is_false(SR:IsSessionHost())
        end)

        it("is true only when the local player is the recorded host", function()
            SR.sessionActive = true
            SR.sessionHost = "TestPlayer"
            assert.is_true(SR:IsSessionHost())
            SR.sessionHost = "SomeoneElse"
            assert.is_false(SR:IsSessionHost())
        end)
    end)

    describe("GetAddonChannel / SendAddonMsg", function()
        it("prefers RAID over PARTY when both a raid and a distribution request exist", function()
            wow.addRaidMember("TestPlayer", 0)
            assert.are.equal("RAID", SR:GetAddonChannel())
        end)

        it("falls back to PARTY when there's a party but no raid", function()
            wow.state.party = { "Buddy" }
            assert.are.equal("PARTY", SR:GetAddonChannel())
        end)

        it("is nil when solo", function()
            assert.is_nil(SR:GetAddonChannel())
        end)

        it("SendAddonMsg maps 'RAID' to the real channel", function()
            wow.state.party = { "Buddy" }
            SR:SendAddonMsg("X", "RAID")
            assert.are.equal("PARTY", lastAddonMsg().distribution)
        end)

        it("SendAddonMsg drops the message entirely when solo (no channel available)", function()
            SR:SendAddonMsg("X", "RAID")
            assert.are.equal(0, #wow.state.sentAddon)
        end)

        it("SendAddonMsg passes WHISPER through untouched with its target", function()
            SR:SendAddonMsg("X", "WHISPER", "Someone")
            assert.are.equal("WHISPER", lastAddonMsg().distribution)
            assert.are.equal("Someone", lastAddonMsg().target)
        end)
    end)

    describe("StartSession", function()
        it("refuses a non-leader", function()
            wow.addRaidMember("TestPlayer", 0)
            wow.state.isRaidLeader = false
            SR:StartSession()
            assert.is_false(SR.sessionActive)
            assert.are.equal(0, #wow.state.sentAddon)
        end)

        it("refuses to start when someone else is already hosting", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR.sessionActive = true
            SR.sessionHost = "SomeoneElse"
            SR:StartSession()
            assert.are.equal("SomeoneElse", SR.sessionHost)
        end)

        it("starts the session, locks/unlocks per SR.locked, and broadcasts S/L/I", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR.locked = false
            SR.db.instance = "ICC"
            SR.db.srMode = "classic"

            SR:StartSession()

            assert.is_true(SR.sessionActive)
            assert.are.equal("TestPlayer", SR.sessionHost)
            assert.is_false(SR.sessionLocked)
            assert.are.equal(1, #addonMsgsMatching("^S|TestPlayer$"))
            assert.are.equal(1, #addonMsgsMatching("^L|0$"))
            assert.are.equal(1, #addonMsgsMatching("^I|ICC|classic$"))
        end)

        it("wipes existing co-hosts on (re)start", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR.db.coHosts["OldCoHost"] = true
            SR:StartSession()
            assert.is_nil(next(SR.db.coHosts))
        end)
    end)

    describe("AutoStartSession", function()
        it("does nothing for a non-leader", function()
            wow.addRaidMember("TestPlayer", 0)
            SR:AutoStartSession()
            assert.is_false(SR.sessionActive)
        end)

        it("does nothing when already hosting", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR.sessionActive = true
            SR.sessionHost = "TestPlayer"
            SR:AutoStartSession()
            assert.are.equal(0, #wow.state.sentAddon) -- no re-announcement
        end)

        it("refuses to start with a placeholder/unresolved player name", function()
            wow.addRaidMember("Unknown", 2)
            wow.state.isRaidLeader = true
            wow.state.playerName = "Unknown"
            SR:AutoStartSession()
            assert.is_false(SR.sessionActive)
        end)

        it("always starts locked, regardless of SR.locked, and broadcasts L|1", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR.locked = false

            SR:AutoStartSession()

            assert.is_true(SR.sessionActive)
            assert.is_true(SR.locked)
            assert.is_true(SR.sessionLocked)
            assert.is_true(SR.db.locked)
            assert.are.equal(1, #addonMsgsMatching("^L|1$"))
        end)
    end)

    describe("EndSession / AutoEndSession", function()
        before_each(function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()
        end)

        it("EndSession refuses when there's no active session", function()
            SR.sessionActive = false
            SR:EndSession() -- would error if it dereferenced sessionHost blindly; just shouldn't crash
            assert.is_false(SR.sessionActive)
        end)

        it("EndSession refuses a non-host", function()
            SR.sessionHost = "SomeoneElse"
            SR:EndSession()
            assert.is_true(SR.sessionActive) -- untouched
        end)

        it("EndSession, as host, broadcasts E and clears all session/lock state", function()
            SR:EndSession()
            assert.is_false(SR.sessionActive)
            assert.is_nil(SR.sessionHost)
            assert.is_false(SR.sessionLocked)
            assert.is_false(SR.locked)
            assert.is_false(SR.db.locked)
            assert.are.equal(1, #addonMsgsMatching("^E|TestPlayer$"))
        end)

        it("AutoEndSession is a no-op when there's no active session", function()
            SR.sessionActive = false
            local before = #wow.state.sentAddon
            SR:AutoEndSession()
            assert.are.equal(before, #wow.state.sentAddon)
        end)

        it("AutoEndSession silently broadcasts E and resets state without printing", function()
            local printsBefore = #wow.state.printed
            SR:AutoEndSession()
            assert.is_false(SR.sessionActive)
            assert.are.equal(1, #addonMsgsMatching("^E|TestPlayer$"))
            assert.are.equal(printsBefore, #wow.state.printed) -- no extra chat spam
        end)
    end)

    describe("BroadcastLockState / BroadcastCoHosts", function()
        it("BroadcastLockState only sends when the local player is the host", function()
            SR:BroadcastLockState()
            assert.are.equal(0, #wow.state.sentAddon)

            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()
            local before = #addonMsgsMatching("^L|1$")
            SR:BroadcastLockState()
            assert.are.equal(before + 1, #addonMsgsMatching("^L|1$"))
        end)

        it("BroadcastCoHosts lists only currently-active co-hosts", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR.db.coHosts["Ann"] = true
            SR.db.coHosts["Removed"] = false

            SR:BroadcastCoHosts()

            local msg = addonMsgsMatching("^O|")[1].msg
            assert.matches("Ann", msg)
            assert.is_nil(msg:match("Removed"))
        end)
    end)

    describe("OnSessionLock", function()
        it("as a client, mirrors the host's lock state into SR.locked", function()
            SR:OnSessionLock("1")
            assert.is_true(SR.sessionLocked)
            assert.is_true(SR.locked)

            SR:OnSessionLock("0")
            assert.is_false(SR.sessionLocked)
            assert.is_false(SR.locked)
        end)

        it("as the host, updates sessionLocked but leaves the host's own SR.locked alone", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR.locked = false

            SR:OnSessionLock("1")

            assert.is_true(SR.sessionLocked)
            assert.is_false(SR.locked) -- host's own lock is authoritative, not overwritten
        end)
    end)

    describe("OnHello", function()
        it("as host with an active session, whispers session/lock/instance state back to the sender", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR.db.instance = "ICC"
            SR.locked = false
            SR:StartSession()

            SR:OnHello("Newcomer")

            local toNewcomer = {}
            for _, m in ipairs(wow.state.sentAddon) do
                if m.target == "Newcomer" then toNewcomer[#toNewcomer + 1] = m.msg end
            end
            local text = table.concat(toNewcomer, "\n")
            assert.matches("^S|TestPlayer", text)
            assert.matches("L|0", text)
            assert.matches("I|ICC", text)
        end)

        it("as a client, pauses the session when the host itself says hello (implying a reload)", function()
            wow.addRaidMember("Leader", 2)
            SR:OnSessionStart("Leader", "Leader")
            assert.is_true(SR.sessionActive)

            SR:OnHello("Leader")

            assert.is_false(SR.sessionActive)
        end)
    end)

    describe("RequestSessionSync / OnSyncRequest / OnSyncPlayer / OnSyncComplete", function()
        before_each(function()
            SR:InitItemCache()
        end)

        it("RequestSessionSync (client) does NOT wipe local reserves up front — it's a diff sync", function()
            -- Local data must survive the moment between sending Q and getting a
            -- reply; it's only pruned in OnSyncComplete, based on what the host
            -- actually confirms (see the diff-sync tests below).
            SR.db.reserves["Stale"] = { { itemID = 1, count = 1 } }
            SR.sessionHost = "Leader"

            SR:RequestSessionSync()

            assert.is_not_nil(SR.db.reserves["Stale"])
            assert.is_true(SR._syncPending)
            local msg = lastAddonMsg()
            assert.are.equal("Q", msg.msg)
            assert.are.equal("Leader", msg.target)
        end)

        it("diff sync: a full Q...Z round replaces the local list with exactly what the host confirms", function()
            SR.db.reserves["StalePlayer"] = { { itemID = 999, count = 1 } } -- host won't mention this one
            SR.sessionHost = "Leader"

            SR:RequestSessionSync()
            SR:OnSyncPlayer("KeptPlayer|TANK|49978:2")
            SR:OnSyncComplete()

            assert.is_nil(SR.db.reserves["StalePlayer"]) -- pruned: host never confirmed it
            assert.is_not_nil(SR.db.reserves["KeptPlayer"]) -- host did confirm it
        end)

        it("diff sync: a player the host explicitly reports as empty is still 'seen' and not left dangling", function()
            SR.sessionHost = "Leader"
            SR:RequestSessionSync()
            SR:OnSyncPlayer("SomePlayer|DPS|") -- host confirms: this player currently has zero SR
            SR:OnSyncComplete()
            assert.is_nil(SR.db.reserves["SomePlayer"])
        end)

        it("diff sync: local data isn't touched at all if the host's reply never arrives (Z never comes)", function()
            SR.db.reserves["StillHere"] = { { itemID = 1, count = 1 } }
            SR.sessionHost = "Leader"
            SR:RequestSessionSync()
            assert.is_not_nil(SR.db.reserves["StillHere"])
        end)

        it("OnSyncRequest (host) replies with instance, co-hosts, overrides, per-player reserves, then Z", function()
            wow.addItem(49978, "Crushing Coldwraith Belt", "|cffa335ee|Hitem:49978:0:0:0:0:0:0:0|h[Belt]|h|r")
            wow.addRaidMember("TestPlayer", 2)
            wow.addRaidMember("Asker", 0)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR.db.coHosts["Asker"] = true
            SR:SetPlayerOverride("Asker", 5)
            SR.db.reserves["Asker"] = { { itemID = 49978, itemLink = "x", count = 1 } }

            SR:OnSyncRequest("Asker")

            local toAsker = {}
            for _, m in ipairs(wow.state.sentAddon) do
                if m.target == "Asker" then toAsker[#toAsker + 1] = m.msg end
            end
            local text = table.concat(toAsker, "\n")
            assert.matches("I|ICC", text)
            assert.matches("O|Asker", text)
            assert.matches("P|Asker|5", text)
            assert.matches("Y|Asker|", text)
            assert.matches("\nZ$", "\n" .. text) -- Z is the final message sent
        end)

        it("OnSyncRequest refuses a sender who isn't in the raid", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()

            SR:OnSyncRequest("NotInRaid")

            for _, m in ipairs(wow.state.sentAddon) do
                assert.is_not.equal("NotInRaid", m.target)
            end
        end)

        it("OnSyncPlayer (client) applies role + reserves from the 'pName|role|id:c,id:c' format", function()
            SR:OnSyncPlayer("Asker|TANK|49978:2,49979:1")

            assert.are.equal("TANK", SR.db.roles["Asker"])
            assert.are.equal(2, #SR.db.reserves["Asker"])
            local total = 0
            for _, e in ipairs(SR.db.reserves["Asker"]) do total = total + e.count end
            assert.are.equal(3, total)
        end)

        it("OnSyncPlayer clears reserves when the item string is empty", function()
            SR.db.reserves["Asker"] = { { itemID = 1, count = 1 } }
            SR:OnSyncPlayer("Asker|TANK|")
            assert.is_nil(SR.db.reserves["Asker"])
        end)

        it("OnSyncPlayer is ignored by the host (host data takes priority)", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR:OnSyncPlayer("Asker|TANK|49978:2")
            assert.is_nil(SR.db.reserves["Asker"])
        end)

        it("OnSyncComplete clears the pending-sync flag", function()
            SR._syncPending = true
            SR:OnSyncComplete()
            assert.is_false(SR._syncPending)
        end)
    end)

    describe("OnCoHostsUpdate", function()
        it("as a client, records the announced co-host set", function()
            SR:OnCoHostsUpdate("Ann,Boris")
            assert.is_true(SR.sessionCoHosts["Ann"])
            assert.is_true(SR.sessionCoHosts["Boris"])
        end)

        it("is ignored by the host", function()
            wow.addRaidMember("TestPlayer", 2)
            wow.state.isRaidLeader = true
            SR:StartSession()
            SR.sessionCoHosts = nil
            SR:OnCoHostsUpdate("Ann")
            assert.is_nil(SR.sessionCoHosts)
        end)
    end)

    describe("AnnounceHello", function()
        it("sends H when in a group", function()
            wow.addRaidMember("TestPlayer", 0)
            SR:AnnounceHello()
            assert.are.equal(1, #addonMsgsMatching("^H$"))
        end)

        it("does nothing when solo", function()
            SR:AnnounceHello()
            assert.are.equal(0, #wow.state.sentAddon)
        end)
    end)
end)
