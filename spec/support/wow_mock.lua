--------------------------------------------------------------
-- Мінімальна заглушка WoW 3.3.5a API для юніт-тестів.
-- Покриває лише те, чим реально користуються Core.lua, Comms.lua
-- та ChatParser.lua (UI.lua сюди не входить — його логіка прив'язана
-- до реальних фреймів гри і в юніт-тестах не перевіряється).
--------------------------------------------------------------

local M = {}

M.state = {}

function M.reset()
    M.state.raid             = {}   -- список { name, rank, class, online, level, subgroup, raidRole }
    M.state.party            = {}   -- список імен party2..partyN (party1 = гравець)
    M.state.partyLeaderIndex = 0    -- 0 = гравець лідер, N = лідер у party N
    M.state.playerName       = "TestPlayer"
    M.state.playerClass      = "WARRIOR"
    M.state.playerLevel      = 80
    M.state.isRaidLeader     = false
    M.state.isRaidOfficer    = false
    M.state.isPartyLeader    = false
    M.state.items            = {}   -- [itemID] = { name=, link=, quality= }
    M.state.sentChat         = {}   -- захоплені виклики SendChatMessage
    M.state.sentAddon        = {}   -- захоплені виклики SendAddonMessage
    M.state.printed          = {}   -- захоплені DEFAULT_CHAT_FRAME:AddMessage
    M.state.bags             = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} }
end

--- Додає предмет у слот сумки для тестування сканера сумок.
function M.addBagItem(bag, slot, itemID, count, tradeText, isSoulbound)
    M.state.bags[bag] = M.state.bags[bag] or {}
    M.state.bags[bag][slot] = {
        itemID = itemID,
        count = count or 1,
        tradeText = tradeText,
        isSoulbound = isSoulbound,
    }
end

--- Реєструє гравця в тестовому рейді. rank: 0=учасник, 1=помічник, 2=лідер.
function M.addRaidMember(name, rank, opts)
    opts = opts or {}
    table.insert(M.state.raid, {
        name     = name,
        rank     = rank or 0,
        class    = opts.class or "WARRIOR",
        online   = opts.online ~= false,
        level    = opts.level or 80,
        subgroup = opts.subgroup or 1,
        raidRole = opts.raidRole,
    })
end

function M.addItem(itemID, name, link, quality)
    M.state.items[itemID] = { name = name, link = link or ("[" .. name .. "]"), quality = quality or 4 }
end

function M.install()
    _G.CreateFrame = function(_frameType, name, _parent, _template)
        local frame = {}
        frame._name = name
        frame._lines = {}
        function frame:RegisterEvent() end
        function frame:UnregisterEvent() end
        function frame:SetScript(event, fn) frame["_script_" .. event] = fn end
        function frame:GetScript(event) return frame["_script_" .. event] end
        function frame:Hide() end
        function frame:Show() end
        function frame:SetOwner() end
        function frame:ClearLines()
            frame._lines = {}
        end
        function frame:NumLines()
            return #frame._lines
        end
        function frame:SetHyperlink() end
        function frame:SetBagItem(bag, slot)
            frame._lines = {}
            local item = M.state.bags[bag] and M.state.bags[bag][slot]
            if item then
                local it = M.state.items[item.itemID]
                local itemName = it and it.name or ("Item " .. item.itemID)
                table.insert(frame._lines, itemName)
                if item.isSoulbound or item.tradeText then
                    table.insert(frame._lines, "Soulbound")
                end
                if item.tradeText then
                    local tradeLine = "You may trade this item with players that were also eligible to loot this item for " .. item.tradeText .. "."
                    table.insert(frame._lines, tradeLine)
                end
            end
            for i, line in ipairs(frame._lines) do
                local lineName = (name or "SRBagScanTooltip") .. "TextLeft" .. i
                _G[lineName] = {
                    GetText = function() return line end,
                }
            end
        end
        return frame
    end

    _G.UIParent = {}

    _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_self, msg) table.insert(M.state.printed, msg) end,
    }

    _G.GetNumRaidMembers = function() return #M.state.raid end

    _G.GetRaidRosterInfo = function(i)
        local m = M.state.raid[i]
        if not m then return nil end
        return m.name, m.rank, m.subgroup, m.level, m.class, m.class, nil, m.online, nil, m.raidRole
    end

    _G.GetNumPartyMembers = function() return #M.state.party end

    _G.GetPartyLeaderIndex = function() return M.state.partyLeaderIndex end

    _G.GetUnitName = function(unit)
        if unit == "player" then return M.state.playerName end
        local idx = tonumber(unit:match("^party(%d+)$"))
        if idx then return M.state.party[idx] end
        return nil
    end

    _G.UnitName = function(unit)
        if unit == "player" then return M.state.playerName end
        local idx = tonumber(unit:match("^party(%d+)$"))
        if idx then return M.state.party[idx] end
        return nil
    end

    _G.UnitClass = function(_unit) return M.state.playerClass, M.state.playerClass end
    _G.UnitLevel = function(_unit) return M.state.playerLevel end
    _G.UnitExists = function(unit)
        if unit == "player" then return true end
        local idx = tonumber(unit:match("^party(%d+)$"))
        return idx ~= nil and M.state.party[idx] ~= nil
    end
    _G.UnitIsConnected = function(_unit) return true end

    _G.IsRaidLeader  = function() return M.state.isRaidLeader end
    _G.IsRaidOfficer = function() return M.state.isRaidOfficer end
    _G.IsPartyLeader = function() return M.state.isPartyLeader end

    _G.GetItemInfo = function(itemID)
        local it = M.state.items[tonumber(itemID)]
        if not it then return nil end
        return it.name, it.link, it.quality
    end

    _G.GetContainerNumSlots = function(bag)
        local b = M.state.bags[bag]
        if not b then return 0 end
        local maxSlot = 0
        for slot in pairs(b) do
            if slot > maxSlot then maxSlot = slot end
        end
        return maxSlot
    end

    _G.GetContainerItemLink = function(bag, slot)
        local it = M.state.bags[bag] and M.state.bags[bag][slot]
        if not it then return nil end
        local itemInfo = M.state.items[it.itemID]
        return itemInfo and itemInfo.link or nil
    end

    _G.GetContainerItemInfo = function(bag, slot)
        local it = M.state.bags[bag] and M.state.bags[bag][slot]
        if not it then return nil end
        local itemInfo = M.state.items[it.itemID]
        local quality = itemInfo and itemInfo.quality or 4
        return "Interface\\Icons\\INV_Misc_QuestionMark", it.count or 1, false, quality
    end

    _G.BIND_TRADE_TIME_REMAINING = "You may trade this item with players that were also eligible to loot this item for %s."
    _G.ITEM_SOULBOUND = "Soulbound"

    _G.SendChatMessage = function(msg, chatType, _lang, target)
        table.insert(M.state.sentChat, { msg = msg, chatType = chatType, target = target })
    end

    _G.SendAddonMessage = function(prefix, msg, distribution, target)
        table.insert(M.state.sentAddon, { prefix = prefix, msg = msg, distribution = distribution, target = target })
    end

    _G.RegisterAddonMessagePrefix = function() end

    _G.format = string.format

    _G.strtrim = function(s)
        return (s:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    _G.wipe = function(t)
        for k in pairs(t) do t[k] = nil end
        return t
    end

    M.reset()
end

return M
