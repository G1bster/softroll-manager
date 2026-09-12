--------------------------------------------------------------
-- SoftRollManager  —  ChatParser.lua  (v3.0)
-- Listens to CHAT_MSG_WHISPER / CHAT_MSG_RAID for !sr commands
-- Also accepts hidden <SRManager> ADD messages (fallback)
-- Compatible with WoW 3.3.5a (WotLK)
--
-- REPLACE your existing ChatParser.lua with this file.
--------------------------------------------------------------

local SR = SoftRoll

-- Прихований префікс для реєстрації без UI (резервний варіант)
local HIDDEN_PREFIX = "<SRManager>"

--------------------------------------------------------------
-- 1. РЕЄСТРАЦІЯ ПОДІЙ
--------------------------------------------------------------
function SR:InitChatParser()
    local f = CreateFrame("Frame", "SoftRollChatFrame", UIParent)
    f:RegisterEvent("CHAT_MSG_WHISPER")
    f:RegisterEvent("CHAT_MSG_RAID")
    f:RegisterEvent("CHAT_MSG_RAID_LEADER")
    f:RegisterEvent("CHAT_MSG_SYSTEM")

    f:SetScript("OnEvent", function(self, event, msg, sender, ...)
        if event == "CHAT_MSG_WHISPER" then
            SR:HandleIncoming(msg, sender, true)
        elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
            SR:HandleIncoming(msg, sender, false)
        elseif event == "CHAT_MSG_SYSTEM" then
            if SR.HandleSystemMsg then SR:HandleSystemMsg(msg) end
        end
    end)
end

--------------------------------------------------------------
-- 2. ОБРОБНИК КОМАНД
--------------------------------------------------------------
function SR:HandleIncoming(msg, sender, isWhisper)
    if not msg or msg == "" then return end

    -- Обробка прихованого протоколу SRManager (тільки приватні, тільки хост)
    if isWhisper and msg:sub(1, #HIDDEN_PREFIX) == HIDDEN_PREFIX then
        if SR.sessionActive and not SR:IsSessionHost() then return end
        if not SR:CanEditSession() then return end
        SR:HandleHiddenSR(msg:sub(#HIDDEN_PREFIX + 1), sender, isWhisper)
        return
    end

    -- Реагуємо на повідомлення: !sr, +sr, #sr, ?sr або просто sr (через блок серверів)
    local msgTrimmed = strtrim(msg)
    local firstWord, restArgs = msgTrimmed:match("^(%S+)%s*(.*)$")
    if not firstWord then
        firstWord = msgTrimmed
        restArgs = ""
    end

    local cmd = firstWord:lower()
    if cmd ~= "!sr" and cmd ~= "+sr" and cmd ~= "?sr" and cmd ~= "#sr" and cmd ~= "sr" then
        return
    end

    -- Перевірка чи розпочата сесія
    if not SR.sessionActive then
        -- Щоб уникнути спаму від усіх офіцерів, відповідає лише лідер рейду/групи (або соло гравець)
        local shouldReply = false
        if GetNumRaidMembers() > 0 then
            shouldReply = IsRaidLeader()
        elseif GetNumPartyMembers() > 0 then
            shouldReply = IsPartyLeader()
        else
            shouldReply = true
        end
        
        if shouldReply then
            self:Reply(sender, isWhisper, self.L.WHISPER_SESSION_NOT_STARTED)
        end
        return
    end

    -- Команди обробляє лише Активний Хост
    if not SR:IsSessionHost() then return end

    -- Відкидаємо префікс і зайві пробіли
    local args      = restArgs
    local argsLower = args:lower()

    -- Підкоманди
    if argsLower == "" or argsLower == "help" then
        self:Reply(sender, isWhisper, self.L.WHISPER_HELP)
        return
    end

    if argsLower == "list" then
        self:CmdList(sender, isWhisper)
        return
    end

    if argsLower == "clear" or argsLower:match("^clear%s+") then
        self:CmdClear(args, sender, isWhisper)
        return
    end

    -- За замовчуванням: обробляємо як реєстрацію софт-ролу
    self:CmdRegister(args, sender, isWhisper)
end

--------------------------------------------------------------
-- 2b. Прихована команда <SRManager> ADD [ЛінкНаПредмет] (xN)
--------------------------------------------------------------
function SR:HandleHiddenSR(args, sender, isWhisper)
    args = strtrim(args or "")
    local cmd, rest = args:match("^(%S+)%s*(.*)$")
    if not cmd then return end

    cmd = cmd:upper()
    if cmd ~= "ADD" then return end

    local itemLink = rest:match("(|c%x+|Hitem:.-%|h%[.-%]|h|r)")
    if not itemLink then
        self:Reply(sender, isWhisper, self.L.WHISPER_ERR_NO_LINK)
        return
    end

    local mul = rest:match("[x\209\133](%d+)")
    local count = mul and tonumber(mul) or 1
    local cx = (count > 1) and (" x" .. count) or ""

    local ok, err = self:ProcessSRRegistration(sender, itemLink, count, true)
    if ok then
        local used  = self:GetUsedSRCount(sender)
        local limit = self:GetSRLimit(sender)
        self:Reply(sender, isWhisper,
            format(self.L.WHISPER_REGISTER_SUCCESS, itemLink, cx, used, limit))
        self:Print(format(self.L.PRINT_USER_REGISTERED, sender, itemLink .. cx))
    else
        self:Reply(sender, isWhisper, format(self.L.WHISPER_ERR_PREFIX, err or "Невідома помилка."))
    end
end

--------------------------------------------------------------
-- 3. !sr list (Список)
--------------------------------------------------------------
function SR:CmdList(sender, isWhisper)
    local reserves = self.db.reserves[sender]
    if not reserves or #reserves == 0 then
        self:Reply(sender, isWhisper, self.L.WHISPER_NO_SRS)
        return
    end

    local role  = self:GetPlayerRole(sender)
    local limit = self:GetSRLimit(sender)
    local used  = self:GetUsedSRCount(sender)

    local overrideNote = ""
    if self:HasOverride(sender) then
        overrideNote = " [ЗАМІНА]"
    end

    -- Виправлено баг із відсутньою дужкою в кінці рядка
    self:Reply(sender, isWhisper,
        "Ваші софт-роли (" .. used .. " з " .. limit .. " використано, Роль: " .. self.ROLE_LABELS[role] .. overrideNote .. "):")

    for _, e in ipairs(reserves) do
        local cx = (e.count > 1) and (" x" .. e.count) or ""
        self:Reply(sender, isWhisper, "  " .. e.itemLink .. cx)
    end
end

--------------------------------------------------------------
-- 4. !sr clear (Очистити)
--------------------------------------------------------------
function SR:CmdClear(args, sender, isWhisper)
    if not self.sessionActive then
        self:Reply(sender, isWhisper, self.L.WHISPER_SESSION_NOT_ACTIVE)
        return
    end

    if self.locked or self.sessionLocked then
        self:Reply(sender, isWhisper, self.L.WHISPER_CHANGES_LOCKED)
        return
    end

    local senderCanEdit = (sender == self.sessionHost or sender == self:GetLocalPlayerName() or self:IsCoHost(sender))
    local targetPlayer = sender
    local remaining = args:gsub("(|c%x+|Hitem:.-%|h%[.-%]|h|r)", "")
    remaining = remaining:gsub("^clear%s*", "")
    remaining = strtrim(remaining)
    local possibleTarget = remaining:match("^(%S+)")
    if possibleTarget and possibleTarget ~= "" then
        if senderCanEdit then
            local foundName = nil
            local lowerInput = possibleTarget:lower()
            for _, m in ipairs(self:GetRaidMembers()) do
                if m.name == possibleTarget or m.name:lower() == lowerInput then
                    foundName = m.name
                    break
                end
            end
            if not foundName and self:IsInRaid(possibleTarget) then
                foundName = possibleTarget
            end
            if foundName then
                targetPlayer = foundName
            else
                self:Reply(sender, isWhisper, format(self.L.WHISPER_ERR_NOT_IN_RAID, possibleTarget))
                return
            end
        else
            self:Reply(sender, isWhisper, self.L.WHISPER_ERR_NOT_AUTHORIZED_CLEAR)
            return
        end
    end

    local itemLink = args:match("(|c%x+|Hitem:.-%|h%[.-%]|h|r)")
    if itemLink then
        local itemID = self:GetItemIDFromLink(itemLink)
        if itemID then
            local removed = false
            local list = self.db.reserves[targetPlayer]
            if list then
                local eq = self.GetEquivalentItemIDs and self:GetEquivalentItemIDs(itemID) or { [itemID] = true }
                for i, entry in ipairs(list) do
                    if entry.itemID == tonumber(itemID) or eq[entry.itemID] then
                        table.remove(list, i)
                        removed = true
                        break
                    end
                end
                if removed then
                    if #list == 0 then self.db.reserves[targetPlayer] = nil end
                    if targetPlayer == sender then
                        self:Reply(sender, isWhisper, format(self.L.WHISPER_REMOVE_SUCCESS, itemLink))
                        self:Print(sender .. " скасував софт на " .. itemLink)
                    else
                        self:Reply(sender, isWhisper, format(self.L.WHISPER_REMOVE_FOR_TARGET, itemLink, targetPlayer))
                        self:Reply(targetPlayer, true, format(self.L.WHISPER_RL_REMOVED_SR, sender, itemLink))
                        self:Print(sender .. " скасував софт на " .. itemLink .. " для " .. targetPlayer)
                    end
                    if self:IsSessionHost() or (self:IsSessionLeader() and not self.sessionActive) then
                        if self.BroadcastPlayerSync then self:BroadcastPlayerSync(targetPlayer) end
                    end
                    if self.RefreshSessionUI then self:RefreshSessionUI() end
                else
                    if targetPlayer == sender then
                        self:Reply(sender, isWhisper, format(self.L.WHISPER_NOT_RESERVED, itemLink))
                    else
                        self:Reply(sender, isWhisper, format(self.L.WHISPER_TARGET_NOT_RESERVED, targetPlayer, itemLink))
                    end
                end
            else
                if targetPlayer == sender then
                    self:Reply(sender, isWhisper, self.L.WHISPER_NO_SRS_SHORT)
                else
                    self:Reply(sender, isWhisper, format(self.L.WHISPER_TARGET_NO_SRS, targetPlayer))
                end
            end
        else
            self:Reply(sender, isWhisper, self.L.WHISPER_ERR_UNKNOWN_ITEM)
        end
        return
    end

    if not self.db.reserves[targetPlayer] or #self.db.reserves[targetPlayer] == 0 then
        if targetPlayer == sender then
            self:Reply(sender, isWhisper, self.L.WHISPER_NOTHING_TO_CLEAR)
        else
            self:Reply(sender, isWhisper, format(self.L.WHISPER_TARGET_NO_SRS, targetPlayer))
        end
        return
    end
    self:ClearPlayerSR(targetPlayer)
    if targetPlayer == sender then
        self:Reply(sender, isWhisper, self.L.WHISPER_CLEAR_SUCCESS)
        self:Print(sender .. " очистив свої софт-роли.")
    else
        self:Reply(sender, isWhisper, format(self.L.WHISPER_CLEAR_FOR_TARGET, targetPlayer))
        self:Reply(targetPlayer, true, format(self.L.WHISPER_RL_CLEARED_ALL, sender))
        self:Print(sender .. " очистив софт-роли для " .. targetPlayer .. ".")
    end
end

--------------------------------------------------------------
-- 5. !sr [ЛінкНаПредмет] (xN) — делегує до ProcessSRRegistration
--------------------------------------------------------------
function SR:CmdRegister(args, sender, isWhisper)
    if not self.sessionActive then
        self:Reply(sender, isWhisper, self.L.WHISPER_SESSION_NOT_ACTIVE)
        return
    end

    if self.locked or self.sessionLocked then
        self:Reply(sender, isWhisper, self.L.WHISPER_REGISTER_LOCKED)
        return
    end

    local senderCanEdit = (sender == self.sessionHost or sender == self:GetLocalPlayerName() or self:IsCoHost(sender))

    local itemLink = args:match("(|c%x+|Hitem:.-%|h%[.-%]|h|r)")
    if not itemLink then
        self:Reply(sender, isWhisper,
            "Помилка: Посилання на предмет не знайдено. " .. self.L.WHISPER_USAGE_REGISTER)
        return
    end

    local mul = args:match("[x\209\133](%d+)")
    local count = mul and tonumber(mul) or 1
    if count < 1 then count = 1 end

    local targetPlayer = sender
    local remainingArgs = args:gsub("(|c%x+|Hitem:.-%|h%[.-%]|h|r)", "")
    remainingArgs = remainingArgs:gsub("[x\209\133]%d+", "")
    remainingArgs = strtrim(remainingArgs)
    local possibleName = remainingArgs:match("^(%S+)")
    
    if possibleName and possibleName ~= "" then
        if senderCanEdit then
            local foundName = nil
            local lowerInput = possibleName:lower()
            local members = self:GetRaidMembers()
            for _, m in ipairs(members) do
                if m.name == possibleName or m.name:lower() == lowerInput then
                    foundName = m.name
                    break
                end
            end
            if not foundName and self:IsInRaid(possibleName) then
                foundName = possibleName
            end
            if not foundName then
                local asciiCapitalized = possibleName:match("^%a+$") and (possibleName:sub(1,1):upper() .. possibleName:sub(2):lower())
                if asciiCapitalized and self:IsInRaid(asciiCapitalized) then
                    foundName = asciiCapitalized
                end
            end

            if foundName then
                targetPlayer = foundName
            else
                self:Reply(sender, isWhisper, format(self.L.WHISPER_ERR_NOT_IN_RAID, possibleName))
                return
            end
        else
            self:Reply(sender, isWhisper, self.L.WHISPER_ERR_NOT_AUTHORIZED_ADD)
            return
        end
    end

    local ok, err = self:ProcessSRRegistration(targetPlayer, itemLink, count, true)
    if ok then
        local newUsed = self:GetUsedSRCount(targetPlayer)
        local limit   = self:GetSRLimit(targetPlayer)
        local role    = self:GetPlayerRole(targetPlayer)
        local cx = (count > 1) and (" x" .. count) or ""
        local overrideNote = self:HasOverride(targetPlayer) and " [ЗАМІНА]" or ""
        
        if targetPlayer == sender then
            self:Reply(sender, isWhisper,
                format(self.L.WHISPER_REGISTER_ROLE, itemLink, cx, newUsed, limit, self.ROLE_LABELS[role], overrideNote))
            self:Print(sender .. " зареєстрував софт-рол: " .. itemLink .. cx
                .. " (" .. newUsed .. "/" .. limit .. ")")
        else
            self:Reply(sender, isWhisper,
                format(self.L.WHISPER_REGISTER_FOR_TARGET, targetPlayer, itemLink, cx, newUsed, limit))
            self:Reply(targetPlayer, true,
                format(self.L.WHISPER_RL_ADDED_SR, sender, itemLink, cx, newUsed, limit))
            self:Print(sender .. " зареєстрував софт-рол для " .. targetPlayer .. ": " .. itemLink .. cx)
        end
    else
        self:Reply(sender, isWhisper, format(self.L.WHISPER_ERR_PREFIX, err or "Невідома помилка."))
    end
end

--------------------------------------------------------------
-- 6. ДОПОМІЖНА ФУНКЦІЯ ДЛЯ ВІДПОВІДЕЙ
--------------------------------------------------------------
function SR:Reply(target, isWhisper, message)
    SendChatMessage(message, "WHISPER", nil, target)
end

--------------------------------------------------------------
-- 7. ОБРОБКА СИСТЕМНИХ ПОВІДОМЛЕНЬ (РОЛИ)
--------------------------------------------------------------
function SR:HandleSystemMsg(msg)
    if not self.activeRollItem then return end

    -- Підтримка англійської (rolls), російської (выбрасывает), української (викидає) локалізацій
    local name, roll, min, max = msg:match("^(%S+)%s+rolls%s+(%d+)%s+%((%d+)%-(%d+)%)")
    if not name then
        name, roll, min, max = msg:match("^(%S+)%s+выбрасывает%s+(%d+)%s+%((%d+)%-(%d+)%)")
    end
    if not name then
        name, roll, min, max = msg:match("^(%S+)%s+викидає%s+(%d+)%s+%((%d+)%-(%d+)%)")
    end

    if name and roll and min == "1" and max == "100" then
        self:ProcessRoll(name, tonumber(roll))
    end
end