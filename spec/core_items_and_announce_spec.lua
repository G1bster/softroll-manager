local load_addon = require("spec.support.load_addon")

local ITEM_LINK = "|cffa335ee|Hitem:49978:0:0:0:0:0:0:0|h[Crushing Coldwraith Belt]|h|r"
local ITEM_LINK_2 = "|cffa335ee|Hitem:49979:0:0:0:0:0:0:0|h[Handguards of Winter's Respite]|h|r"

describe("SR item cache, announcements, roll tracker, and slash handler (Core.lua)", function()
    local SR, wow

    before_each(function()
        SR, wow = load_addon.load()
    end)

    describe("CopyTable", function()
        it("passes through non-table values unchanged", function()
            assert.are.equal(5, SR:CopyTable(5))
            assert.are.equal("x", SR:CopyTable("x"))
        end)

        it("deep-copies nested tables so mutating the copy doesn't affect the original", function()
            local src = { a = 1, nested = { b = 2 } }
            local copy = SR:CopyTable(src)
            copy.a = 99
            copy.nested.b = 99
            assert.are.equal(1, src.a)
            assert.are.equal(2, src.nested.b)
        end)
    end)

    describe("GetClassColor / ColorText", function()
        it("returns the known color table for a valid class", function()
            local c = SR:GetClassColor("MAGE")
            assert.are.equal(SR.CLASS_COLORS.MAGE, c)
        end)

        it("returns a neutral grey for an unknown class", function()
            local c = SR:GetClassColor("NOT_A_CLASS")
            assert.same({ r = 0.5, g = 0.5, b = 0.5 }, c)
        end)

        it("formats text with an RGB hex color code", function()
            assert.are.equal("|cffff0000red|r", SR:ColorText("red", 1, 0, 0))
        end)
    end)

    describe("GetItemIDFromLink", function()
        it("extracts the numeric item ID from a full item link", function()
            assert.are.equal(49978, SR:GetItemIDFromLink(ITEM_LINK))
        end)

        it("returns nil for a nil link", function()
            assert.is_nil(SR:GetItemIDFromLink(nil))
        end)

        it("returns nil for a string with no item: pattern", function()
            assert.is_nil(SR:GetItemIDFromLink("not a link"))
        end)
    end)

    describe("GetSafeItemLink", function()
        it("returns an existing, well-formed link unchanged", function()
            assert.are.equal(ITEM_LINK, SR:GetSafeItemLink(49978, ITEM_LINK))
        end)

        it("ignores an existing link that's just a placeholder ('Item #')", function()
            wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
            local link = SR:GetSafeItemLink(49978, "[Item #49978]")
            assert.are.equal(ITEM_LINK, link)
        end)

        it("resolves a real link from the item cache when no existing link is given", function()
            wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
            assert.are.equal(ITEM_LINK, SR:GetSafeItemLink(49978, nil))
        end)

        it("falls back to a raw item: stub when the item isn't cached yet", function()
            assert.are.equal("item:49978:0:0:0:0:0:0:0", SR:GetSafeItemLink(49978, nil))
        end)

        it("returns the existing link as-is when there's no itemID and it isn't a full link", function()
            assert.are.equal("some text", SR:GetSafeItemLink(nil, "some text"))
        end)
    end)

    describe("ForceQueryItem", function()
        it("returns false for a non-numeric itemID", function()
            assert.is_false(SR:ForceQueryItem("not-a-number"))
        end)

        it("returns true immediately when the item is already cached", function()
            wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
            assert.is_true(SR:ForceQueryItem(49978))
        end)

        it("returns false when the item can't be resolved at all", function()
            assert.is_false(SR:ForceQueryItem(999999))
        end)
    end)

    describe("QueueItemCache / QueueAllKnownItems", function()
        before_each(function()
            SR:InitItemCache()
        end)

        it("does not queue an item that's already cached", function()
            wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
            SR:QueueItemCache(49978)
            assert.is_nil(SR.pendingItems[49978])
        end)

        it("queues an uncached item for background polling", function()
            SR:QueueItemCache(49978)
            assert.are.equal(0, SR.pendingItems[49978])
        end)

        it("silently ignores a nil itemID", function()
            assert.has_no.errors(function() SR:QueueItemCache(nil) end)
        end)

        it("queues every reserved item plus every item in the current instance's loot tables", function()
            SR.db.instance = "RS" -- small loot table, keeps this test's assertions tractable
            SR.db.lootDifficulty = "25N"
            SR:AddSR("Player1", "item:53489:0:0:0:0:0:0:0", 1) -- Halion cloak, uncached

            SR:QueueAllKnownItems()

            assert.is_not_nil(SR.pendingItems[53489]) -- from reserves
            assert.is_not_nil(SR.pendingItems[53126]) -- Umbrage Armbands, from RS 25N loot table
        end)
    end)

    describe("RefreshReserveItemLinks / OnItemsCached", function()
        it("leaves a reserve's link untouched while the item is still uncached", function()
            SR.db.reserves["Player1"] = { { itemID = 49978, itemLink = "item:49978:0:0:0:0:0:0:0", count = 1 } }
            SR:RefreshReserveItemLinks()
            assert.are.equal("item:49978:0:0:0:0:0:0:0", SR.db.reserves["Player1"][1].itemLink)
        end)

        it("updates a reserve's stored link once the item resolves in the cache", function()
            SR.db.reserves["Player1"] = { { itemID = 49978, itemLink = "item:49978:0:0:0:0:0:0:0", count = 1 } }
            wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
            SR:OnItemsCached()
            assert.are.equal(ITEM_LINK, SR.db.reserves["Player1"][1].itemLink)
        end)
    end)

    describe("GetPlayersWithSR", function()
        before_each(function()
            wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
            wow.addRaidMember("Ann", 2)
            wow.addRaidMember("Boris", 0)
            wow.addRaidMember("Cara", 0)
        end)

        it("lists only in-raid players who reserved the item, sorted by count then role", function()
            SR:AddSR("Ann", ITEM_LINK, 1)
            SR:AddSR("Boris", ITEM_LINK, 2)
            SR:AddSR("NotInRaid", ITEM_LINK, 5)

            local players = SR:GetPlayersWithSR(49978)
            local names = {}
            for _, p in ipairs(players) do names[#names + 1] = p.name end

            assert.same({ "Boris", "Ann" }, names) -- count 2 beats count 1; NotInRaid excluded
        end)

        it("matches via equivalent (normal/heroic) item IDs", function()
            -- 49978 (N) and 50613 (H) are the same drop at different difficulties.
            SR:AddSR("Cara", ITEM_LINK, 1)
            local players = SR:GetPlayersWithSR(50613)
            assert.are.equal(1, #players)
            assert.are.equal("Cara", players[1].name)
        end)

        it("returns an empty list when nobody has reserved the item", function()
            assert.same({}, SR:GetPlayersWithSR(49978))
        end)
    end)

    describe("AnnouncePlayer", function()
        before_each(function()
            wow.addRaidMember("Ann", 0)
        end)

        it("announces a players's missing-SR count when they have none", function()
            SR:AnnouncePlayer("Ann", "RAID")
            assert.are.equal(1, #wow.state.sentChat)
            assert.matches("немає софтів", wow.state.sentChat[1].msg)
            assert.matches("бракує 3", wow.state.sentChat[1].msg)
        end)

        it("announces a header followed by one line per reserved item", function()
            wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
            wow.addItem(49979, "Handguards of Winter's Respite", ITEM_LINK_2)
            SR:AddSR("Ann", ITEM_LINK, 1)
            SR:AddSR("Ann", ITEM_LINK_2, 2)

            SR:AnnouncePlayer("Ann", "RAID")

            assert.are.equal(3, #wow.state.sentChat) -- header + 2 items
            assert.matches("софти", wow.state.sentChat[1].msg)
            assert.matches(ITEM_LINK:gsub("%p", "%%%1"), wow.state.sentChat[2].msg)
            assert.matches("x2", wow.state.sentChat[3].msg)
        end)
    end)

    describe("AnnounceAllSR / AnnounceMissingSR", function()
        before_each(function()
            wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
            wow.addRaidMember("Ann", 2)
            wow.addRaidMember("Boris", 0)
        end)

        it("AnnounceAllSR only announces players who reserved something", function()
            SR:AddSR("Ann", ITEM_LINK, 1)
            SR:AnnounceAllSR()

            local combined = {}
            for _, c in ipairs(wow.state.sentChat) do combined[#combined + 1] = c.msg end
            local text = table.concat(combined, "\n")
            assert.matches("Ann", text)
            assert.is_nil(text:match("Boris"))
        end)

        it("AnnounceAllSR reports an empty list when nobody has reserved anything", function()
            SR:AnnounceAllSR()
            local last = wow.state.sentChat[#wow.state.sentChat]
            assert.matches("порожній", last.msg)
        end)

        it("AnnounceMissingSR only announces players under their limit", function()
            SR:AddSR("Ann", ITEM_LINK, 3) -- Ann is now full (classic DPS/RL limit = 3)
            SR:AnnounceMissingSR()

            local combined = {}
            for _, c in ipairs(wow.state.sentChat) do combined[#combined + 1] = c.msg end
            local text = table.concat(combined, "\n")
            assert.matches("Boris", text) -- Boris has 0/3, still missing
            assert.is_nil(text:match("Ann %u"))
        end)

        it("AnnounceMissingSR reports everyone full when nobody is missing anything", function()
            SR:AddSR("Ann", ITEM_LINK, 3)
            SR:AddSR("Boris", ITEM_LINK, 3)
            SR:AnnounceMissingSR()
            local last = wow.state.sentChat[#wow.state.sentChat]
            assert.matches("повністю", last.msg)
        end)

        it("uses SAY instead of RAID when there is no raid", function()
            wow.state.raid = {}
            SR:AnnounceAllSR()
            assert.are.equal("SAY", wow.state.sentChat[1].chatType)
        end)
    end)

    describe("AnnounceBossItems", function()
        it("reports when nobody reserved anything from this boss", function()
            SR:AnnounceBossItems("Test Boss", {})
            assert.matches("немає зареєстрованих", wow.state.sentChat[1].msg)
        end)

        it("lists each item with its reservers, handling both plain names and {name,count} entries", function()
            SR:AnnounceBossItems("Test Boss", {
                {
                    itemLink = ITEM_LINK,
                    itemID = 49978,
                    count = 2,
                    reservers = { "Ann", { name = "Boris", count = 3 } },
                },
            })

            assert.are.equal(2, #wow.state.sentChat)
            local line = wow.state.sentChat[2].msg
            assert.matches("Ann", line)
            assert.matches("Boris x3", line)
            assert.matches("%(x2%)", line)
        end)

        it("keeps the first reserver on the same chat line even when the item prefix alone is already very long", function()
            -- Before the fix, the 220-byte chunking check could trip on the very
            -- first reserver name, sending a dangling "...: " line with nobody
            -- listed and pushing the first name onto its own separate line.
            local longLink = string.rep("X", 230)
            SR:AnnounceBossItems("Test Boss", {
                { itemLink = longLink, itemID = 1, count = 1, reservers = { "Ann" } },
            })

            local itemLine = nil
            for _, c in ipairs(wow.state.sentChat) do
                if c.msg:find(longLink, 1, true) then itemLine = c.msg end
            end
            assert.is_not_nil(itemLine)
            assert.matches("Ann", itemLine)
        end)
    end)

    describe("ProcessRoll / EndLootRoll", function()
        before_each(function()
            wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
            wow.addRaidMember("Ann", 0)
            wow.addRaidMember("Boris", 0)
        end)

        it("ProcessRoll does nothing when there is no active roll item", function()
            SR:ProcessRoll("Ann", 55)
            assert.same({}, SR.activeRolls)
        end)

        it("ProcessRoll caps recorded rolls at the player's SR count on that item", function()
            SR:AddSR("Ann", ITEM_LINK, 2)
            SR.activeRollItem = 49978

            SR:ProcessRoll("Ann", 10)
            SR:ProcessRoll("Ann", 20)
            SR:ProcessRoll("Ann", 30) -- third roll should be dropped, only x2 SR

            assert.same({ 10, 20 }, SR.activeRolls["Ann"])
        end)

        it("ProcessRoll allows exactly one roll for a player without an SR on the item", function()
            SR.activeRollItem = 49978
            SR:ProcessRoll("Boris", 42)
            SR:ProcessRoll("Boris", 43)
            assert.same({ 42 }, SR.activeRolls["Boris"])
        end)

        it("EndLootRoll does nothing when there is no active roll", function()
            SR:EndLootRoll()
            assert.are.equal(0, #wow.state.sentChat)
        end)

        it("EndLootRoll announces no-winner when nobody rolled", function()
            SR.activeRollItem = 49978
            SR:EndLootRoll()
            assert.matches("Ніхто не кинув", wow.state.sentChat[1].msg)
            assert.is_nil(SR.activeRollItem)
        end)

        it("EndLootRoll announces the single highest roller as the winner", function()
            SR:AddSR("Ann", ITEM_LINK, 1)
            SR:AddSR("Boris", ITEM_LINK, 1)
            SR.activeRollItem = 49978
            SR:ProcessRoll("Ann", 80)
            SR:ProcessRoll("Boris", 40)

            SR:EndLootRoll()

            assert.matches("Переможець: Ann", wow.state.sentChat[#wow.state.sentChat].msg)
        end)

        it("EndLootRoll announces a tie and asks for a reroll", function()
            SR:AddSR("Ann", ITEM_LINK, 1)
            SR:AddSR("Boris", ITEM_LINK, 1)
            SR.activeRollItem = 49978
            SR:ProcessRoll("Ann", 77)
            SR:ProcessRoll("Boris", 77)

            SR:EndLootRoll()

            local msg = wow.state.sentChat[#wow.state.sentChat].msg
            assert.matches("Нічия", msg)
            assert.matches("Ann", msg)
            assert.matches("Boris", msg)
        end)

        it("EndLootRoll does not cause a player rolling identical numbers on multiple SRs to tie with themselves", function()
            SR:AddSR("Ann", ITEM_LINK, 2)
            SR.activeRollItem = 49978
            SR:ProcessRoll("Ann", 90)
            SR:ProcessRoll("Ann", 90)

            SR:EndLootRoll()

            local msg = wow.state.sentChat[#wow.state.sentChat].msg
            assert.matches("Переможець: Ann", msg)
            assert.is_nil(msg:match("Нічия"))
        end)

        it("EndLootRoll only allows players with SR to win when reservations exist", function()
            SR:AddSR("Ann", ITEM_LINK, 1)
            -- Boris does not have an SR on ITEM_LINK
            SR.activeRollItem = 49978
            SR:ProcessRoll("Ann", 50)
            SR:ProcessRoll("Boris", 100) -- Boris rolls higher but has no SR

            SR:EndLootRoll()

            local msg = wow.state.sentChat[#wow.state.sentChat].msg
            assert.matches("Переможець: Ann", msg)
            assert.is_nil(msg:match("Boris"))
        end)

        it("EndLootRoll allows any roller to win when no SRs exist on the item (MS roll)", function()
            -- No SR added for ITEM_LINK
            SR.activeRollItem = 49978
            SR:ProcessRoll("Ann", 50)
            SR:ProcessRoll("Boris", 85)

            SR:EndLootRoll()

            local msg = wow.state.sentChat[#wow.state.sentChat].msg
            assert.matches("Переможець: Boris", msg)
        end)

        it("EndLootRoll stores lastRollItem and lastRolls to preserve results in the UI", function()
            SR:AddSR("Ann", ITEM_LINK, 1)
            SR.activeRollItem = 49978
            SR:ProcessRoll("Ann", 95)

            SR:EndLootRoll()

            assert.are.equal(49978, SR.lastRollItem)
            assert.same({ 95 }, SR.lastRolls["Ann"])
            assert.is_nil(SR.activeRollItem)
            assert.same({}, SR.activeRolls)
        end)
    end)

    describe("SlashHandler", function()
        it("'reset' asks for confirmation (does not clear immediately) when authorized", function()
            wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
            SR:AddSR("Ann", ITEM_LINK, 1)
            SR:SlashHandler("reset")
            -- Не має очищати одразу без підтвердження — інакше випадковий
            -- набір "/sr reset" ким завгодно з правами хоста миттєво стирає
            -- весь рейд без жодного запобіжника.
            assert.are.equal(1, SR:GetUsedSRCount("Ann"))
            assert.are.equal("SOFTROLL_CONFIRM_CLEAR", wow.state.popupsShown[#wow.state.popupsShown])
        end)

        it("'reset' is refused for a non-host during an active session", function()
            wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
            SR:AddSR("Ann", ITEM_LINK, 1)
            wow.addRaidMember("Leader", 2)
            SR.sessionActive = true
            SR.sessionHost = "Leader" -- local player ("TestPlayer") is not the host

            SR:SlashHandler("reset")

            assert.are.equal(1, SR:GetUsedSRCount("Ann")) -- untouched
            assert.matches("Лише активний хост", wow.state.printed[#wow.state.printed])
        end)

        it("'reset' is refused for a regular raid member even when sessionActive is locally false", function()
            -- Регресія: раніше умова була "sessionActive AND not host", тож
            -- будь-хто без прав лідера, чий локальний sessionActive ще не
            -- встиг стати true (напр. одразу після входу/релоду, поки не
            -- прийшло "S|host"), міг обнулити софти ВСЬОГО рейду через
            -- /sr reset — воно транслює "W" і стирає резерви в усіх клієнтів.
            wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
            SR:AddSR("Ann", ITEM_LINK, 1)
            wow.addRaidMember("Leader", 2)
            SR.sessionActive = false -- ще не отримали підтвердження сесії

            SR:SlashHandler("reset")

            assert.are.equal(1, SR:GetUsedSRCount("Ann")) -- untouched
            assert.same({}, wow.state.popupsShown)
            assert.matches("Лише активний хост", wow.state.printed[#wow.state.printed])
        end)

        it("'lock' / 'unlock' toggle SR.locked", function()
            SR:SlashHandler("lock")
            assert.is_true(SR.locked)
            SR:SlashHandler("unlock")
            assert.is_false(SR.locked)
        end)

        it("'announce' delegates to AnnounceAllSR", function()
            SR:SlashHandler("announce")
            assert.is_true(#wow.state.sentChat > 0)
        end)

        it("'help' prints usage information", function()
            SR:SlashHandler("help")
            local combined = table.concat(wow.state.printed, "\n")
            assert.matches("Команди", combined)
        end)

        it("is case-insensitive and trims whitespace", function()
            SR:SlashHandler("  LOCK  ")
            assert.is_true(SR.locked)
        end)

        it("syncs sessionLocked and broadcasts lock state on /sr lock and unlock", function()
            local broadcasted = false
            SR.BroadcastLockState = function() broadcasted = true end

            SR:SlashHandler("lock")
            assert.is_true(SR.locked)
            assert.is_true(SR.sessionLocked)
            assert.is_true(broadcasted)

            broadcasted = false
            SR:SlashHandler("unlock")
            assert.is_false(SR.locked)
            assert.is_false(SR.sessionLocked)
            assert.is_true(broadcasted)
        end)

        it("delegates anything else to ToggleUI", function()
            local called = false
            SR.ToggleUI = function() called = true end
            SR:SlashHandler("whatever")
            assert.is_true(called)
        end)
    end)

    describe("Channel resolution and long message chunking", function()
        it("GetAnnouncementChannel chooses correct channel depending on group state", function()
            -- Solo
            assert.are.equal("SAY", SR:GetAnnouncementChannel(false))
            assert.are.equal("SAY", SR:GetAnnouncementChannel(true))

            -- 5-man Party
            wow.state.party = { "P1", "P2" }
            assert.are.equal("PARTY", SR:GetAnnouncementChannel(false))
            assert.are.equal("PARTY", SR:GetAnnouncementChannel(true))
            wow.state.party = {}

            -- Raid (normal member)
            wow.addRaidMember("TestPlayer", 0)
            assert.are.equal("RAID", SR:GetAnnouncementChannel(false))
            assert.are.equal("RAID", SR:GetAnnouncementChannel(true))

            -- Raid (leader/admin)
            wow.state.raid[1].rank = 2
            assert.are.equal("RAID", SR:GetAnnouncementChannel(false))
            assert.are.equal("RAID_WARNING", SR:GetAnnouncementChannel(true))
        end)

        it("AnnounceBossItems chunks long candidate lists into messages <= 220 bytes", function()
            local reservers = {}
            for i = 1, 15 do
                table.insert(reservers, { name = "LongPlayerName" .. i, count = 2 })
            end

            wow.state.sentChat = {}
            SR:AnnounceBossItems("Saurfang", {
                {
                    itemLink = ITEM_LINK,
                    itemID = 49978,
                    reservers = reservers,
                }
            })

            -- Header + multiple chunked lines
            assert.is_true(#wow.state.sentChat >= 2)
            for _, entry in ipairs(wow.state.sentChat) do
                assert.is_true(#entry.msg <= 220)
            end
        end)
    end)

    describe("Comprehensive Edge Cases", function()
        before_each(function()
            wow.addItem(49978, "Crushing Coldwraith Belt", ITEM_LINK)
            wow.addRaidMember("Leader", 2)
            wow.addRaidMember("Member", 0)
        end)

        describe("GetItemIDFromLink", function()
            it("handles nil, empty string, invalid strings safely", function()
                assert.is_nil(SR:GetItemIDFromLink(nil))
                assert.is_nil(SR:GetItemIDFromLink(""))
                assert.is_nil(SR:GetItemIDFromLink("some random string"))
            end)

            it("rejects non-item hyperlinks (spells, quests, etc.)", function()
                assert.is_nil(SR:GetItemIDFromLink("|cff71d5ff|Hspell:53042|h[Mortal Strike]|h|r"))
                assert.is_nil(SR:GetItemIDFromLink("|cffffff00|Hquest:12345:80|h[Some Quest]|h|r"))
            end)

            it("accepts raw numbers and numeric strings", function()
                assert.are.equal(49978, SR:GetItemIDFromLink(49978))
                assert.are.equal(49978, SR:GetItemIDFromLink("49978"))
            end)

            it("extracts ID from complex item links with gems and enchants", function()
                local complexLink = "|cffa335ee|Hitem:49978:3834:3834:3834:0:0:0:0|h[Crushing Coldwraith Belt]|h|r"
                assert.are.equal(49978, SR:GetItemIDFromLink(complexLink))
            end)
        end)

        describe("GetPlayersWithSR", function()
            it("returns empty table for nil or invalid input", function()
                assert.are.same({}, SR:GetPlayersWithSR(nil))
                assert.are.same({}, SR:GetPlayersWithSR(""))
                assert.are.same({}, SR:GetPlayersWithSR("invalid"))
                assert.are.same({}, SR:GetPlayersWithSR(999999))
            end)

            it("accepts number, string ID, or item link", function()
                SR:AddSR("Member", ITEM_LINK, 1)
                assert.are.equal(1, #SR:GetPlayersWithSR(49978))
                assert.are.equal(1, #SR:GetPlayersWithSR("49978"))
                assert.are.equal(1, #SR:GetPlayersWithSR(ITEM_LINK))
            end)

            it("sorts players by count descending then name ascending", function()
                wow.addRaidMember("Zara", 0)
                wow.addRaidMember("Alice", 0)
                wow.addRaidMember("Bob", 0)

                SR:AddSR("Zara", ITEM_LINK, 1)
                SR:AddSR("Alice", ITEM_LINK, 2)
                SR:AddSR("Bob", ITEM_LINK, 2)

                local players = SR:GetPlayersWithSR(49978)
                assert.are.equal(3, #players)
                assert.are.equal("Alice", players[1].name)
                assert.are.equal(2, players[1].count)
                assert.are.equal("Bob", players[2].name)
                assert.are.equal(2, players[2].count)
                assert.are.equal("Zara", players[3].name)
                assert.are.equal(1, players[3].count)
            end)
        end)

        describe("AddSR, RemoveSR, ClearPlayerSR edge cases", function()
            it("rejects nil or empty playerName in AddSR", function()
                local ok, err = SR:AddSR(nil, ITEM_LINK, 1)
                assert.is_false(ok)
                assert.matches("Невідомий гравець", err)

                local ok2, err2 = SR:AddSR("", ITEM_LINK, 1)
                assert.is_false(ok2)
                assert.matches("Невідомий гравець", err2)
            end)

            it("strips realm suffix when registering and retrieving SR", function()
                local ok = SR:AddSR("Member-Icecrown", ITEM_LINK, 1)
                assert.is_true(ok)
                assert.are.equal(1, SR:GetUsedSRCount("Member"))
                assert.are.equal(1, SR:GetUsedSRCount("Member-Icecrown"))
                assert.is_nil(SR.db.reserves["Member-Icecrown"])
                assert.is_not_nil(SR.db.reserves["Member"])
            end)

            it("sanitizes float, string, and negative counts in AddSR", function()
                SR:AddSR("Member", ITEM_LINK, "2")
                assert.are.equal(2, SR:GetUsedSRCount("Member"))

                SR:ClearPlayerSR("Member")
                SR:AddSR("Member", ITEM_LINK, 1.8)
                assert.are.equal(1, SR:GetUsedSRCount("Member"))

                SR:ClearPlayerSR("Member")
                SR:AddSR("Member", ITEM_LINK, -5)
                assert.are.equal(1, SR:GetUsedSRCount("Member"))
            end)

            it("RemoveSR accepts itemLink and strips realm from playerName", function()
                SR:AddSR("Member", ITEM_LINK, 1)
                local removed = SR:RemoveSR("Member-Icecrown", ITEM_LINK)
                assert.is_true(removed)
                assert.are.equal(0, SR:GetUsedSRCount("Member"))
            end)

            it("ClearPlayerSR strips realm from playerName", function()
                SR:AddSR("Member", ITEM_LINK, 2)
                SR:ClearPlayerSR("Member-Icecrown")
                assert.are.equal(0, SR:GetUsedSRCount("Member"))
            end)
        end)

        describe("Roles and Limits edge cases", function()
            it("defaults unknown or nil role to DPS", function()
                SR:SetPlayerRole("Member", "INVALID_ROLE")
                assert.are.equal("DPS", SR:GetPlayerRole("Member"))

                SR:SetPlayerRole("Member", nil)
                assert.are.equal("DPS", SR:GetPlayerRole("Member"))

                assert.are.equal("DPS", SR:GetPlayerRole(nil))
                assert.are.equal("DPS", SR:GetPlayerRole(""))
            end)

            it("SetPlayerRole and GetPlayerRole normalize realm suffix", function()
                SR:SetPlayerRole("Member-Icecrown", "TANK")
                assert.are.equal("TANK", SR:GetPlayerRole("Member"))
                assert.are.equal("TANK", SR:GetPlayerRole("Member-Icecrown"))
            end)

            it("GetSRLimit returns safe default for nil or empty name", function()
                assert.are.equal(3, SR:GetSRLimit(nil))
                assert.are.equal(3, SR:GetSRLimit(""))
                assert.are.equal(3, SR:GetBaseSRLimit(nil))
            end)

            it("GetRemainingSR clamps to 0 even if reserves exceed limit", function()
                SR:AddSR("Member", ITEM_LINK, 3)
                SR:SetPlayerOverride("Member", 1) -- override limit down to 1
                assert.are.equal(0, SR:GetRemainingSR("Member"))
            end)

            it("StripRealm handles various inputs", function()
                assert.are.equal("Player", SR:StripRealm("Player-Icecrown"))
                assert.are.equal("Player", SR:StripRealm("Player"))
                assert.are.equal("", SR:StripRealm(""))
                assert.is_nil(SR:StripRealm(nil))
            end)
        end)
    end)
end)
