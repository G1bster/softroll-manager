local load_addon = require("spec.support.load_addon")

local ITEM_LINK = "|cffa335ee|Hitem:49978:0:0:0:0:0:0:0|h[Crushing Coldwraith Belt]|h|r"

-- ChatParser only *acts* on "sr ..." messages when the local client is the
-- active session host (that's how a Raid Leader's own addon instance
-- receives everyone else's whispers/raid chat and registers SR on their
-- behalf), so these tests run as if the local player IS "Leader".
describe("SR chat command parsing (ChatParser.lua)", function()
    local SR, wow

    local function lastWhisperTo(target)
        for i = #wow.state.sentChat, 1, -1 do
            local c = wow.state.sentChat[i]
            if c.chatType == "WHISPER" and c.target == target then
                return c.msg
            end
        end
        return nil
    end

    --- Some replies (e.g. "sr list") are sent as several whisper lines;
    -- this checks whether ANY of them matches, not just the last one.
    local function anyWhisperTo(target, pattern)
        for _, c in ipairs(wow.state.sentChat) do
            if c.chatType == "WHISPER" and c.target == target and c.msg:match(pattern) then
                return true
            end
        end
        return false
    end

    before_each(function()
        SR, wow = load_addon.load()
        wow.state.playerName = "Leader"
        wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
        wow.addRaidMember("Leader", 2)
        wow.addRaidMember("Member", 0)

        SR.sessionActive = true
        SR.sessionHost = "Leader"
        SR.locked = false
    end)

    it("ignores chat messages that aren't an sr command", function()
        SR:HandleIncoming("just chatting", "Member", false)
        assert.are.equal(0, #wow.state.sentChat)
    end)

    it("tells whoever asks that no session has started yet (host client only)", function()
        SR.sessionActive = false
        wow.state.isRaidLeader = true -- local player (Leader) is the raid leader
        SR:HandleIncoming("sr help", "Member", false)
        local reply = lastWhisperTo("Member")
        assert.is_not_nil(reply)
        assert.matches("ще не розпочалась", reply)
    end)

    it("does nothing when the local client is not the session host", function()
        wow.state.playerName = "SomeoneElse"
        SR:HandleIncoming("sr " .. ITEM_LINK, "Member", false)
        assert.are.equal(0, SR:GetUsedSRCount("Member"))
        assert.are.equal(0, #wow.state.sentChat)
    end)

    it("registers a soft-reserve for the sender via 'sr [link]'", function()
        SR:HandleIncoming("sr " .. ITEM_LINK, "Member", false)
        assert.are.equal(1, SR:GetUsedSRCount("Member"))
        local reply = lastWhisperTo("Member")
        assert.matches("зареєстровано", reply)
    end)

    it("honors an 'x2' multiplier", function()
        SR:HandleIncoming("sr " .. ITEM_LINK .. " x2", "Member", false)
        assert.are.equal(2, SR:GetUsedSRCount("Member"))
    end)

    it("rejects registration while soft-reserves are locked", function()
        SR.locked = true
        SR:HandleIncoming("sr " .. ITEM_LINK, "Member", false)
        assert.are.equal(0, SR:GetUsedSRCount("Member"))
        local reply = lastWhisperTo("Member")
        assert.matches("ЗАБЛОКОВАНА", reply)
    end)

    it("'sr list' reports the sender's current reserves", function()
        SR:AddSR("Member", ITEM_LINK, 1)
        SR:HandleIncoming("sr list", "Member", false)
        assert.is_true(anyWhisperTo("Member", "1 з 3"))
    end)

    it("'sr clear' removes all of the sender's reserves", function()
        SR:AddSR("Member", ITEM_LINK, 1)
        SR:HandleIncoming("sr clear", "Member", false)
        assert.are.equal(0, SR:GetUsedSRCount("Member"))
    end)
end)
