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
            self:Reply(sender, isWhisper, "Сесія софт-ролів ще не розпочалась. Зачекайте, поки РЛ її почне.")
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
        self:Reply(sender, isWhisper,
            "Використання: sr [ЛінкНаПредмет], sr [ЛінкНаПредмет] x2, sr list, sr clear, sr help")
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
        self:Reply(sender, isWhisper, "Помилка: Не знайдено дійсного посилання на предмет у повідомленні SRManager.")
        return
    end

    local mul = rest:match("[x\209\133](%d+)")
    local count = mul and tonumber(mul) or 1

    local ok, err = self:ProcessSRRegistration(sender, itemLink, count, true)
    if ok then
        local used  = self:GetUsedSRCount(sender)
        local limit = self:GetSRLimit(sender)
        self:Reply(sender, isWhisper,
            "Софт-рол зареєстровано (" .. used .. " з " .. limit .. " використано).")
        self:Print(sender .. " зареєстрував софт-рол через SRManager: " .. itemLink)
    else
        self:Reply(sender, isWhisper, "Помилка: " .. (err or "Невідома помилка."))
    end
end

--------------------------------------------------------------
-- 3. !sr list (Список)
--------------------------------------------------------------
function SR:CmdList(sender, isWhisper)
    local reserves = self.db.reserves[sender]
    if not reserves or #reserves == 0 then
        self:Reply(sender, isWhisper, "У вас немає зареєстрованих софт-ролів.")
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
        self:Reply(sender, isWhisper, "Сесія софт-ролів ще не розпочалась.")
        return
    end

    local itemLink = args:match("(|c%x+|Hitem:.-%|h%[.-%]|h|r)")
    if itemLink then
        local itemID = self:GetItemIDFromLink(itemLink)
        if itemID then
            local removed = false
            local list = self.db.reserves[sender]
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
                    if #list == 0 then self.db.reserves[sender] = nil end
                    self:Reply(sender, isWhisper, "Ваш софт на " .. itemLink .. " було успішно видалено.")
                    self:Print(sender .. " скасував софт на " .. itemLink)
                    if self:IsSessionHost() or (self:IsSessionLeader() and not self.sessionActive) then
                        if self.BroadcastPlayerSync then self:BroadcastPlayerSync(sender) end
                    end
                    if self.RefreshSessionUI then self:RefreshSessionUI() end
                else
                    self:Reply(sender, isWhisper, "Ви не резервували " .. itemLink .. ".")
                end
            else
                self:Reply(sender, isWhisper, "У вас немає зареєстрованих софтів.")
            end
        else
            self:Reply(sender, isWhisper, "Помилка: неможливо розпізнати предмет.")
        end
        return
    end

    if not self.db.reserves[sender] or #self.db.reserves[sender] == 0 then
        self:Reply(sender, isWhisper, "Немає що очищати.")
        return
    end
    self:ClearPlayerSR(sender)
    self:Reply(sender, isWhisper, "Ваші софт-роли було успішно очищено.")
    self:Print(sender .. " очистив свої софт-роли.")
end

--------------------------------------------------------------
-- 5. !sr [ЛінкНаПредмет] (xN) — делегує до ProcessSRRegistration
--------------------------------------------------------------
function SR:CmdRegister(args, sender, isWhisper)
    if not self.sessionActive then
        self:Reply(sender, isWhisper, "Сесія софт-ролів ще не розпочалась.")
        return
    end

    if self.locked or self.sessionLocked then
        self:Reply(sender, isWhisper, "Реєстрація софт-ролів наразі ЗАБЛОКОВАНА. Спробуйте пізніше.")
        return
    end

    local itemLink = args:match("(|c%x+|Hitem:.-%|h%[.-%]|h|r)")
    if not itemLink then
        self:Reply(sender, isWhisper,
            "Помилка: Посилання на предмет не знайдено. Використання: sr [ЛінкНаПредмет] або sr [ЛінкНаПредмет] x2")
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
        if self:CanEditSession() then
            -- Форматуємо ім'я гравця (перша велика, інші малі)
            targetPlayer = possibleName:sub(1,1):upper() .. possibleName:sub(2):lower()
            if not self:IsInRaid(targetPlayer) then
                self:Reply(sender, isWhisper, "Помилка: Гравця '" .. targetPlayer .. "' немає у рейді.")
                return
            end
        else
            self:Reply(sender, isWhisper, "Помилка: Тільки РЛ або помічник може додавати софт-роли іншим гравцям.")
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
                "Софт-рол зареєстровано: " .. itemLink .. cx
                .. " (" .. newUsed .. " з " .. limit .. " використано). Роль: " .. self.ROLE_LABELS[role] .. overrideNote)
            self:Print(sender .. " зареєстрував софт-рол: " .. itemLink .. cx
                .. " (" .. newUsed .. "/" .. limit .. ")")
        else
            self:Reply(sender, isWhisper,
                "Софт-рол зареєстровано ДЛЯ " .. targetPlayer .. ": " .. itemLink .. cx
                .. " (" .. newUsed .. " з " .. limit .. ").")
            self:Reply(targetPlayer, true,
                "РЛ (" .. sender .. ") додав вам софт-рол: " .. itemLink .. cx
                .. " (" .. newUsed .. " з " .. limit .. ").")
            self:Print(sender .. " зареєстрував софт-рол для " .. targetPlayer .. ": " .. itemLink .. cx)
        end
    else
        self:Reply(sender, isWhisper, "Помилка: " .. (err or "Невідома помилка."))
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