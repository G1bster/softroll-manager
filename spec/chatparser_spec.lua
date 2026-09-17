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
        SR:HandleIncoming("срака", "Member", false)
        SR:HandleIncoming("срака " .. ITEM_LINK, "Member", false)
        SR:HandleIncoming("справа", "Member", false)
        SR:HandleIncoming("срібло", "Member", false)
        assert.are.equal(0, #wow.state.sentChat)
        assert.are.equal(0, SR:GetUsedSRCount("Member"))
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

    describe("CmdClear with a specific item link", function()
        it("removes just that item and confirms it", function()
            SR:AddSR("Member", ITEM_LINK, 1)
            SR:CmdClear(ITEM_LINK, "Member", false)
            assert.are.equal(0, SR:GetUsedSRCount("Member"))
            assert.matches("успішно видалено", lastWhisperTo("Member"))
        end)

        it("reports when the sender never reserved that item", function()
            SR:AddSR("Member", ITEM_LINK, 1)
            local otherLink = "|cffa335ee|Hitem:99999:0:0:0:0:0:0:0|h[Other]|h|r"
            SR:CmdClear(otherLink, "Member", false)
            assert.are.equal(1, SR:GetUsedSRCount("Member")) -- untouched
            assert.matches("Ви не резервували", lastWhisperTo("Member"))
        end)

        it("reports when the sender has no reserves at all", function()
            SR:CmdClear(ITEM_LINK, "Member", false)
            assert.matches("немає зареєстрованих софтів", lastWhisperTo("Member"))
        end)

        it("reports nothing-to-clear for a bare 'clear' with no reserves", function()
            SR:CmdClear("", "Member", false)
            assert.matches("Немає що очищати", lastWhisperTo("Member"))
        end)
    end)

    describe("CmdRegister targeting another player", function()
        -- Note: HandleIncoming only ever reaches CmdRegister on the ACTIVE HOST's own
        -- client (it returns early for everyone else), and the host's CanEditSession()
        -- is always true on its own client — so the "unauthorized" branch below can't
        -- actually be triggered through chat as any particular sender; it's tested by
        -- calling CmdRegister directly with the local client put in a non-editing state.
        before_each(function()
            wow.addRaidMember("Target", 0)
        end)

        it("the host can register SR for a named target in the raid, notifying both", function()
            SR:HandleIncoming("sr " .. ITEM_LINK .. " Target", "Leader", false)
            assert.are.equal(1, SR:GetUsedSRCount("Target"))
            assert.matches("ДЛЯ Target", lastWhisperTo("Leader"))
            assert.matches("додав вам софт%-рол", lastWhisperTo("Target"))
        end)

        it("capitalizes the target name from lowercase input", function()
            SR:HandleIncoming("sr " .. ITEM_LINK .. " target", "Leader", false)
            assert.are.equal(1, SR:GetUsedSRCount("Target"))
        end)

        it("correctly handles Cyrillic target names without breaking UTF-8 bytes", function()
            wow.addRaidMember("Тарас", 0)
            SR:HandleIncoming("sr " .. ITEM_LINK .. " Тарас", "Leader", false)
            assert.are.equal(1, SR:GetUsedSRCount("Тарас"))
        end)

        it("refuses a non-leader/non-co-host attempting to register SR for someone else", function()
            SR:HandleIncoming("sr " .. ITEM_LINK .. " Target", "Member", false)
            assert.are.equal(0, SR:GetUsedSRCount("Target"))
            assert.matches("Тільки РЛ або помічник", lastWhisperTo("Member"))
        end)

        it("refuses a target that isn't in the raid", function()
            SR:HandleIncoming("sr " .. ITEM_LINK .. " NoSuchPlayer", "Leader", false)
            assert.are.equal(0, SR:GetUsedSRCount("NoSuchPlayer"))
            assert.matches("немає у рейді", lastWhisperTo("Leader"))
        end)

        it("refuses registration when session is locked even with a target player", function()
            SR.locked = true
            SR:HandleIncoming("sr " .. ITEM_LINK .. " Target", "Leader", false)
            assert.are.equal(0, SR:GetUsedSRCount("Target"))
            assert.matches("ЗАБЛОКОВАНА", lastWhisperTo("Leader"))
        end)

        it("refuses CmdClear when session is locked for non-host member", function()
            SR:AddSR("Member", ITEM_LINK, 1)
            SR.locked = true
            SR:HandleIncoming("sr clear", "Member", false)
            assert.are.equal(1, SR:GetUsedSRCount("Member"))
            assert.matches("ЗАБЛОКОВАНІ", lastWhisperTo("Member"))
        end)

        it("allows leader to clear another player's SR via chat command", function()
            SR:AddSR("Target", ITEM_LINK, 1)
            SR:HandleIncoming("sr clear " .. ITEM_LINK .. " Target", "Leader", false)
            assert.are.equal(0, SR:GetUsedSRCount("Target"))
            assert.matches("для Target було видалено", lastWhisperTo("Leader"))
        end)

        it("CmdRegister itself refuses a named target when the local client can't edit the session", function()
            SR.sessionHost = "SomeoneElse" -- local player is no longer the host/co-host
            SR:CmdRegister(ITEM_LINK .. " Target", "Whoever", false)
            assert.are.equal(0, SR:GetUsedSRCount("Target"))
            assert.matches("Тільки РЛ або помічник", lastWhisperTo("Whoever"))
        end)
    end)

    describe("HandleHiddenSR (<SRManager> ADD protocol)", function()
        it("is reachable via a whisper through HandleIncoming while the local client is the active host", function()
            SR:HandleIncoming("<SRManager>ADD " .. ITEM_LINK, "Member", true)
            assert.are.equal(1, SR:GetUsedSRCount("Member"))
        end)

        it("ignores any command other than ADD", function()
            SR:HandleHiddenSR("REMOVE " .. ITEM_LINK, "Member", true)
            assert.are.equal(0, #wow.state.sentChat)
        end)

        it("replies with an error when no valid item link is present", function()
            SR:HandleHiddenSR("ADD not a link", "Member", true)
            assert.matches("Не знайдено дійсного посилання", lastWhisperTo("Member"))
        end)

        it("honors an 'x3' multiplier", function()
            SR:HandleHiddenSR("ADD " .. ITEM_LINK .. " x3", "Member", true)
            assert.are.equal(3, SR:GetUsedSRCount("Member"))
        end)

        it("relays a registration failure as an error reply", function()
            SR.locked = true
            SR:HandleHiddenSR("ADD " .. ITEM_LINK, "Member", true)
            assert.matches("Помилка:", lastWhisperTo("Member"))
        end)
    end)

    describe("HandleSystemMsg / ProcessRoll integration", function()
        before_each(function()
            SR.activeRollItem = 49978
        end)

        it("does nothing when there's no active roll item", function()
            SR.activeRollItem = nil
            SR:HandleSystemMsg("Member rolls 55 (1-100)")
            assert.same({}, SR.activeRolls)
        end)

        it("parses the English 'rolls' pattern", function()
            SR:HandleSystemMsg("Member rolls 55 (1-100)")
            assert.same({ 55 }, SR.activeRolls["Member"])
        end)

        it("parses the Ukrainian 'викидає' pattern", function()
            SR:HandleSystemMsg("Member викидає 42 (1-100)")
            assert.same({ 42 }, SR.activeRolls["Member"])
        end)

        it("parses the Russian 'выбрасывает' pattern", function()
            SR:HandleSystemMsg("Member выбрасывает 10 (1-100)")
            assert.same({ 10 }, SR.activeRolls["Member"])
        end)

        it("ignores a roll that isn't out of 1-100", function()
            SR:HandleSystemMsg("Member rolls 25 (1-50)")
            assert.is_nil(SR.activeRolls["Member"])
        end)

        it("strips realm from roller name", function()
            SR:HandleSystemMsg("Member-Icecrown rolls 95 (1-100)")
            assert.same({ 95 }, SR.activeRolls["Member"])
        end)

        it("parses German client roll format", function()
            SR:HandleSystemMsg("Member würfelt. Ergebnis: 88 (1-100)")
            assert.same({ 88 }, SR.activeRolls["Member"])
        end)

        it("parses French client roll format", function()
            SR:HandleSystemMsg("Member obtient 72 (1-100)")
            assert.same({ 72 }, SR.activeRolls["Member"])
        end)

        it("parses rolls dynamically using _G.RANDOM_ROLL_RESULT if set", function()
            _G.RANDOM_ROLL_RESULT = "%s has rolled %d (%d-%d)"
            SR:HandleSystemMsg("Member has rolled 99 (1-100)")
            assert.same({ 99 }, SR.activeRolls["Member"])
            _G.RANDOM_ROLL_RESULT = nil
        end)
    end)

    describe("Extended command parsing (Cyrillic, no-space, realm stripping)", function()
        it("accepts Cyrillic 'ср [link]' command", function()
            SR:HandleIncoming("ср " .. ITEM_LINK, "Member", false)
            assert.are.equal(1, SR:GetUsedSRCount("Member"))
        end)

        it("accepts link without space 'sr[link]'", function()
            SR:HandleIncoming("sr" .. ITEM_LINK, "Member", false)
            assert.are.equal(1, SR:GetUsedSRCount("Member"))
        end)

        it("accepts Cyrillic link without space 'ср[link]'", function()
            SR:HandleIncoming("ср" .. ITEM_LINK, "Member", false)
            assert.are.equal(1, SR:GetUsedSRCount("Member"))
        end)

        it("strips realm name from incoming chat sender", function()
            SR:HandleIncoming("sr " .. ITEM_LINK, "Member-RealmName", false)
            assert.are.equal(1, SR:GetUsedSRCount("Member"))
        end)

        it("parses multiplier with space 'sr [link] x 2'", function()
            SR:HandleIncoming("sr " .. ITEM_LINK .. " x 2", "Member", false)
            assert.are.equal(2, SR:GetUsedSRCount("Member"))
        end)

        it("parses Cyrillic lowercase multiplier 'sr [link] х2'", function()
            SR:HandleIncoming("sr " .. ITEM_LINK .. " х2", "Member", false)
            assert.are.equal(2, SR:GetUsedSRCount("Member"))
        end)

        it("parses Cyrillic uppercase multiplier 'sr [link] Х2'", function()
            SR:HandleIncoming("sr " .. ITEM_LINK .. " Х2", "Member", false)
            assert.are.equal(2, SR:GetUsedSRCount("Member"))
        end)

        it("parses leading multiplier 'sr 2x [link]'", function()
            SR:HandleIncoming("sr 2x " .. ITEM_LINK, "Member", false)
            assert.are.equal(2, SR:GetUsedSRCount("Member"))
        end)

        it("parses leading Cyrillic multiplier 'sr 2х [link]'", function()
            SR:HandleIncoming("sr 2х " .. ITEM_LINK, "Member", false)
            assert.are.equal(2, SR:GetUsedSRCount("Member"))
        end)

        it("recognizes Cyrillic list aliases 'список', 'лист', 'софти'", function()
            SR:AddSR("Member", ITEM_LINK, 1)
            SR:HandleIncoming("sr список", "Member", false)
            assert.is_true(anyWhisperTo("Member", "Ваші софт%-роли"))

            SR:HandleIncoming("sr лист", "Member", false)
            assert.is_true(anyWhisperTo("Member", "Ваші софт%-роли"))

            SR:HandleIncoming("sr софти", "Member", false)
            assert.is_true(anyWhisperTo("Member", "Ваші софт%-роли"))
        end)

        it("recognizes removal aliases 'видалити [link]', 'очистити [link]', 'remove [link]'", function()
            SR:AddSR("Member", ITEM_LINK, 1)
            SR:HandleIncoming("sr видалити " .. ITEM_LINK, "Member", false)
            assert.are.equal(0, SR:GetUsedSRCount("Member"))

            SR:AddSR("Member", ITEM_LINK, 1)
            SR:HandleIncoming("sr очистити " .. ITEM_LINK, "Member", false)
            assert.are.equal(0, SR:GetUsedSRCount("Member"))

            SR:AddSR("Member", ITEM_LINK, 1)
            SR:HandleIncoming("sr remove " .. ITEM_LINK, "Member", false)
            assert.are.equal(0, SR:GetUsedSRCount("Member"))
        end)

        it("recognizes full clear aliases without links 'sr очистити', 'sr видалити'", function()
            SR:AddSR("Member", ITEM_LINK, 2)
            SR:HandleIncoming("sr очистити", "Member", false)
            assert.are.equal(0, SR:GetUsedSRCount("Member"))

            SR:AddSR("Member", ITEM_LINK, 2)
            SR:HandleIncoming("sr видалити", "Member", false)
            assert.are.equal(0, SR:GetUsedSRCount("Member"))
        end)

        it("recognizes help aliases 'sr допомога', 'sr ?'", function()
            SR:HandleIncoming("sr допомога", "Member", false)
            assert.is_true(anyWhisperTo("Member", "Довідка"))

            SR:HandleIncoming("sr ?", "Member", false)
            assert.is_true(anyWhisperTo("Member", "Довідка"))
        end)

        it("handles shift-clicks without spaces 'sr[link]', '!sr[link]', 'ср[link]', '!ср[link]'", function()
            SR:HandleIncoming("sr" .. ITEM_LINK, "Member", false)
            assert.are.equal(1, SR:GetUsedSRCount("Member"))

            SR:ClearPlayerSR("Member")
            SR:HandleIncoming("!sr" .. ITEM_LINK, "Member", false)
            assert.are.equal(1, SR:GetUsedSRCount("Member"))

            SR:ClearPlayerSR("Member")
            SR:HandleIncoming("ср" .. ITEM_LINK, "Member", false)
            assert.are.equal(1, SR:GetUsedSRCount("Member"))

            SR:ClearPlayerSR("Member")
            SR:HandleIncoming("!ср" .. ITEM_LINK, "Member", false)
            assert.are.equal(1, SR:GetUsedSRCount("Member"))
        end)

        it("clamps zero multiplier 'sr [link] x0' to 1", function()
            SR:HandleIncoming("sr " .. ITEM_LINK .. " x0", "Member", false)
            assert.are.equal(1, SR:GetUsedSRCount("Member"))
        end)
    end)
end)
