--------------------------------------------------------------
-- SoftRollManager  —  Comms.lua  (v3.0)
-- Синхронізація сесії Хост/Клієнт через SendAddonMessage (WotLK 3.3.5a)
--
-- Префікс протоколу: "SRM"  (макс. 16 символів у 3.3.5)
-- Повідомлення розділяються символом "|"; лінки на предмети НІКОЛИ не надсилаються — використовується itemID.
--
--  Трансляція в РЕЙД (хост → рейд):
--    S|hostName              Сесію розпочато
--    E|hostName              Сесію завершено
--    L|0|1                   Стан блокування (0=розблоковано, 1=заблоковано)
--
--  ПРИВАТНІ ПОВІДОМЛЕННЯ (клієнт ↔ хост):
--    A|itemID|count          Запит клієнта на реєстрацію SR
--    K|1|text  /  K|0|text    Відповідь хоста (1=ок, 0=помилка)
--    Q                       Запит клієнта на повну синхронізацію резервів
--    Y|player|id:c,id:c      Частина синхронізації від хоста (один гравець)
--    Z                       Синхронізацію від хоста завершено
--    H                       Привітання клієнта — хост повторно анонсує сесію, якщо вона активна
--------------------------------------------------------------

local SR = SoftRoll

SR.ADDON_PREFIX = "SRM"

-- Стан сесії під час роботи (не зберігається між сесіями)
SR.sessionActive = false
SR.sessionHost   = nil   -- ім'я активного хоста (без вказівки ігрового світу)
SR.sessionLocked = false -- віддзеркалення стану блокування хоста для клієнтів (тільки читання)

--------------------------------------------------------------
-- ІНІЦІАЛІЗАЦІЯ
--------------------------------------------------------------
function SR:InitComms()
    if self.commsFrame then return end

    if RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(self.ADDON_PREFIX)
    end

    local f = CreateFrame("Frame", "SoftRollCommsFrame", UIParent)
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
        if event == "CHAT_MSG_ADDON" and prefix == SR.ADDON_PREFIX then
            SR:OnAddonMessage(message, channel, sender)
        end
    end)
    self.commsFrame = f
end

--------------------------------------------------------------
-- ДОПОМІЖНІ ФУНКЦІЇ СЕСІЇ
--------------------------------------------------------------

--- Видаляє суфікс ігрового світу з імені персонажа.
function SR:StripRealm(name)
    if not name then return nil end
    local base = name:match("^([^%-]+)")
    return base or name
end

function SR:GetLocalPlayerName()
    return self:StripRealm(UnitName("player"))
end

function SR:IsSessionHost()
    if not self.sessionActive or not self.sessionHost then return false end
    return self.sessionHost == self:GetLocalPlayerName()
end

--- Повертає true, якщо гравець у списку Ко-Хостів і є помічником в рейді.
function SR:IsCoHost(name)
    if not self.db.coHosts then return false end
    if not self.db.coHosts[name] then return false end
    if not name then return false end
    for i = 1, GetNumRaidMembers() do
        local rName, rank = GetRaidRosterInfo(i)
        if rName == name then
            return rank and rank > 0
        end
    end
    return false
end

--- Повертає true, якщо клієнт може редагувати резерви / обробляти реєстрації.
function SR:CanEditSession()
    if self:IsSessionHost() then return true end
    -- Ко-хост активної сесії
    if self.sessionActive then
        local myName = self:GetLocalPlayerName()
        if self.sessionCoHosts and self.sessionCoHosts[myName] then
            return true
        end
    end
    return false
end

--- Повертає true, коли інтерфейс адміністратора повинен бути тільки для читання (сесію хостить хтось інший).
function SR:IsSessionReadOnly()
    if not self.sessionActive then return false end
    return not self:CanEditSession()
end

function SR:GetAddonChannel()
    if GetNumRaidMembers() > 0 then return "RAID" end
    if GetNumPartyMembers() > 0 then return "PARTY" end
    return nil
end

function SR:SendAddonMsg(msg, distribution, target)
    if not SendAddonMessage then return end
    
    if distribution == "RAID" or distribution == "PARTY" then
        distribution = self:GetAddonChannel()
    end
    
    if not distribution then return end
    SendAddonMessage(self.ADDON_PREFIX, msg, distribution, target)
end

--------------------------------------------------------------
-- ПОЧАТОК / КІНЕЦЬ СЕСІЇ (тільки хост)
--------------------------------------------------------------

function SR:StartSession()
    if not self:IsSessionLeader() then
        self:Print("Лише лідер групи або рейду може почати сесію SR.")
        return
    end
    if self.sessionActive and self.sessionHost ~= self:GetLocalPlayerName() then
        self:Print("Сесія вже активна — хост: |cffffcc00" .. self.sessionHost .. "|r.")
        return
    end

    local host = self:GetLocalPlayerName()
    self.sessionActive = true
    self.sessionHost   = host
    self.sessionLocked = self.locked
    wipe(self.db.coHosts)

    self:SendAddonMsg("S|" .. host, "RAID")
    self:SendAddonMsg("L|" .. (self.locked and "1" or "0"), "RAID")
    if self.db.instance then
        self:SendAddonMsg("I|" .. self.db.instance .. "|" .. self.db.srMode, "RAID")
    end

    self:Print("Сесію SR |cff44ff44РОЗПОЧАТО|r — ви активний хост.")
    self:RefreshSessionUI()
end

--- Автоматичний старт сесії при вході в рейд — починає із заблокованими софтами.
function SR:AutoStartSession()
    if not self:IsSessionLeader() then return end
    if self.sessionActive and self.sessionHost == self:GetLocalPlayerName() then return end

    local host = self:GetLocalPlayerName()
    if not host or host == "Unknown" or host == "Невідомо" then return end
    
    self.sessionActive = true
    self.sessionHost   = host
    -- Авто-старт завжди починається з ЗАБЛОКОВАНИМИ реєстраціями
    self.locked        = true
    self.sessionLocked = true
    self.db.locked     = true  -- зберігаємо в db
    wipe(self.db.coHosts)

    self:SendAddonMsg("S|" .. host, "RAID")
    self:SendAddonMsg("L|1", "RAID")
    if self.db.instance then
        self:SendAddonMsg("I|" .. self.db.instance .. "|" .. self.db.srMode, "RAID")
    end

    self:Print("Сесію SR |cff44ff44авто-розпочато|r. Реєстрації |cffff4444ЗАБЛОКОВАНІ|r — розблокуйте коли готові.")
    self:RefreshSessionUI()
end

function SR:EndSession()
    if not self.sessionActive then
        self:Print("Немає активної сесії SR.")
        return
    end
    if not self:IsSessionHost() then
        self:Print("Тільки активний хост (|cffffcc00" .. (self.sessionHost or "?") .. "|r) може завершити сесію.")
        return
    end

    local host = self.sessionHost
    self:SendAddonMsg("E|" .. host, "RAID")

    self.sessionActive = false
    self.sessionHost   = nil
    self.sessionLocked = false
    self.locked        = false
    self.db.locked     = false  -- зберігаємо в db

    self:Print("Сесію SR |cffff4444ЗАВЕРШЕНО|r.")
    self:RefreshSessionUI()
end

--- Автоматичне завершення сесії при виході з рейду (тихе, без повідомлень в чат).
function SR:AutoEndSession()
    if not self.sessionActive then return end
    local host = self.sessionHost
    self:SendAddonMsg("E|" .. (host or ""), "RAID")
    self.sessionActive = false
    self.sessionHost   = nil
    self.sessionLocked = false
    self.locked        = false
    self.db.locked     = false  -- зберігаємо в db
    self:RefreshSessionUI()
end

--- Відправляє стан блокування клієнтам у рейді, коли хост його змінює.
function SR:BroadcastLockState()
    if self:IsSessionHost() then
        self:SendAddonMsg("L|" .. (self.locked and "1" or "0"), "RAID")
    end
end

--- Відправляє список активних Ко-Хостів у рейд
function SR:BroadcastCoHosts()
    if self:IsSessionHost() and self.db.coHosts then
        local hostsList = {}
        for name, active in pairs(self.db.coHosts) do
            if active then
                hostsList[#hostsList + 1] = name
            end
        end
        local msg = "O|" .. table.concat(hostsList, ",")
        self:SendAddonMsg(msg, "RAID")
    end
end

--------------------------------------------------------------
-- МАРШРУТИЗАТОР ВХІДНИХ ПОВІДОМЛЕНЬ АДДОНА
--------------------------------------------------------------
function SR:OnAddonMessage(message, channel, sender)
    if not message or message == "" then return end

    local senderName = self:StripRealm(sender)
    local cmd, rest = message:match("^([^|]+)|(.*)$")
    if not cmd then cmd = message; rest = "" end

    if cmd == "S" then
        self:OnSessionStart(rest, senderName)
    elseif cmd == "E" then
        self:OnSessionEnd(rest, senderName)
    elseif cmd == "L" then
        self:OnSessionLock(rest)
    elseif cmd == "A" then
        self:OnSRAddRequest(rest, senderName)
    elseif cmd == "K" then
        self:OnSRAddReply(rest)
    elseif cmd == "Q" then
        self:OnSyncRequest(senderName)
    elseif cmd == "Y" then
        self:OnSyncPlayer(rest)
    elseif cmd == "Z" then
        self:OnSyncComplete()
    elseif cmd == "P" then
        self:OnPlayerOverrideSync(rest)
    elseif cmd == "H" then
        self:OnHello(senderName)
    elseif cmd == "O" then
        self:OnCoHostsUpdate(rest)
    elseif cmd == "V" then
        self:OnRoleChangeRequest(rest, senderName)
    elseif cmd == "U" then
        self:OnOverrideChangeRequest(rest, senderName)
    elseif cmd == "M" then
        self:OnSRManageRequest(rest, senderName)
    elseif cmd == "R" then
        self:OnSRRemoveRequest(rest, senderName)
    elseif cmd == "C" then
        self:OnSRClearRequest(rest, senderName)
    elseif cmd == "W" then
        self:OnWipeAll(senderName)
    elseif cmd == "I" then
        local inst, mode = rest:match("^([^|]+)|(.*)$")
        if inst and mode then
            if self:IsSessionHost() then
                -- Якщо ми хост, приймаємо зміни від ко-хостів і транслюємо в рейд
                if self:IsCoHost(senderName) then
                    self.db.instance = inst
                    self.db.srMode = mode
                    if self.UpdateDashboard then self:UpdateDashboard() end
                    if self.UpdateLedger then self:UpdateLedger() end
                    self:Print("Ко-хост " .. senderName .. " змінив налаштування підземелля.")
                    self:SendAddonMsg("I|" .. inst .. "|" .. mode, "RAID")
                end
            else
                -- Клієнт: приймаємо зміни від хоста
                self.db.instance = inst
                self.db.srMode = mode
                if self.UpdateDashboard then self:UpdateDashboard() end
                if self.UpdateLedger then self:UpdateLedger() end
            end
        end
    elseif cmd == "T" then
        self:OnLockChangeRequest(rest, senderName)
    end
end

function SR:OnPlayerOverrideSync(data)
    if self:IsSessionHost() then return end
    local pName, limit = data:match("^([^|]+)|(.*)$")
    if pName and limit then
        limit = tonumber(limit)
        if limit and limit > 0 then
            self.db.playerOverrides[pName] = limit
        else
            self.db.playerOverrides[pName] = nil
        end
        if not self._syncPending then
            if self.UpdateDashboard then self:UpdateDashboard() end
            if self.UpdateLedger then self:UpdateLedger() end
        end
    end
end

function SR:OnRoleChangeRequest(data, senderName)
    if not self:IsSessionHost() then return end
    if not self:IsCoHost(senderName) then return end
    local pName, role = data:match("^([^|]+)|([^|]+)$")
    if pName and role then
        self:SetPlayerRole(pName, role)
        self:Print("Ко-хост " .. senderName .. " змінив роль " .. pName .. " на " .. role)
    end
end

function SR:OnOverrideChangeRequest(data, senderName)
    if not self:IsSessionHost() then return end
    if not self:IsCoHost(senderName) then return end
    local pName, limit = data:match("^([^|]+)|([^|]+)$")
    if pName and limit then
        limit = tonumber(limit)
        self:SetPlayerOverride(pName, limit)
        self:Print("Ко-хост " .. senderName .. " змінив ліміт " .. pName .. " на " .. (limit > 0 and limit or "стандартний"))
    end
end

--- Обробка запиту на зміну блокування від ко-хоста
function SR:OnLockChangeRequest(data, senderName)
    if not self:IsSessionHost() then return end
    if not self:IsCoHost(senderName) then return end

    self.locked = (data == "1")
    self.sessionLocked = self.locked
    self.db.locked = self.locked
    self:RefreshSessionUI()
    self:BroadcastLockState()

    local chatType = (GetNumRaidMembers() > 0) and "RAID_WARNING" or "SAY"
    if self.locked then
        self:Print("Ко-хост " .. senderName .. " ЗАБЛОКУВАВ софт-роли.")
        SendChatMessage("Реєстрацію софт-ролів ЗАБЛОКОВАНО.", chatType)
    else
        self:Print("Ко-хост " .. senderName .. " РОЗБЛОКУВАВ софт-роли.")
        SendChatMessage("Реєстрацію софт-ролів РОЗБЛОКОВАНО.", chatType)
    end
end

function SR:OnSessionStart(hostName, senderName)
    hostName = self:StripRealm(hostName)
    if not hostName then return end

    self.sessionActive = true
    self.sessionHost   = hostName

    if hostName == self:GetLocalPlayerName() then
        self:Print("Ви хост сесії SR.")
        self:BroadcastCoHosts()
    else
        self:Print("Сесію SR розпочато — хост: |cffffcc00" .. hostName .. "|r.")
        -- Отримуємо дані про резерви від хоста для перегляду
        self:RequestSessionSync(hostName)
    end
    self:RefreshSessionUI()
end

function SR:OnSessionEnd(hostName, senderName)
    hostName = self:StripRealm(hostName)
    if hostName and self.sessionHost and hostName ~= self.sessionHost then
        return -- ігноруємо застаріле завершення з іншого рейду
    end

    self.sessionActive = false
    self.sessionHost   = nil
    self.sessionLocked = false

    self:Print("Сесію SR завершено" .. (hostName and (" гравцем |cffffcc00" .. hostName .. "|r") or "") .. ".")
    self:RefreshSessionUI()
end

function SR:OnSessionLock(state)
    self.sessionLocked = (state == "1")
    if not self:IsSessionHost() then
        self.locked = self.sessionLocked
    end
    self:RefreshSessionUI()
end

--- Клієнт просить хоста повторно анонсувати активну сесію (після перезавантаження інтерфейсу).
function SR:OnHello(senderName)
    if self:IsSessionHost() and self.sessionActive then
        self:SendAddonMsg("S|" .. self.sessionHost, "WHISPER", senderName)
        self:SendAddonMsg("L|" .. (self.locked and "1" or "0"), "WHISPER", senderName)
        -- Відправляємо список ко-хостів, щоб після /reload гравець знав свій статус
        if self.db.coHosts then
            local hostsList = {}
            for name, active in pairs(self.db.coHosts) do
                if active then hostsList[#hostsList + 1] = name end
            end
            if #hostsList > 0 then
                self:SendAddonMsg("O|" .. table.concat(hostsList, ","), "WHISPER", senderName)
            end
        end
        -- Відправляємо поточне підземелля/режим
        if self.db.instance then
            self:SendAddonMsg("I|" .. self.db.instance .. "|" .. self.db.srMode, "WHISPER", senderName)
        end
    end
    
    if self.sessionActive and self.sessionHost == senderName and not self:IsSessionHost() then
        self:Print("Хост " .. senderName .. " перезавантажив гру. Сесію призупинено (очікування відновлення).")
        self.sessionActive = false
        self.sessionLocked = false
        self:RefreshSessionUI()
    end
end

--- Запит до хоста на знімок резервів (для офіцерів з правами на читання / гравців, що приєдналися пізніше).
function SR:RequestSessionSync(hostName)
    hostName = hostName or self.sessionHost
    if not hostName then return end
    self._syncPending = true
    
    -- Очищаємо локальні резерви клієнта перед отриманням повного списку від хоста, 
    -- щоб не залишилось "старих" софтів (наприклад, якщо хост видалив їх, поки клієнт був офлайн).
    if not self:IsSessionHost() then
        wipe(self.db.reserves)
    end
    
    self:SendAddonMsg("Q", "WHISPER", hostName)
end

function SR:OnSyncRequest(senderName)
    if not self:IsSessionHost() then return end
    if not self:IsInRaid(senderName) then return end

    if self.db.instance then
        self:SendAddonMsg("I|" .. self.db.instance .. "|" .. self.db.srMode, "WHISPER", senderName)
    end

    if self.db.coHosts then
        local hostsList = {}
        for name, active in pairs(self.db.coHosts) do
            if active then hostsList[#hostsList + 1] = name end
        end
        if #hostsList > 0 then
            self:SendAddonMsg("O|" .. table.concat(hostsList, ","), "WHISPER", senderName)
        end
    end

    if self.db.playerOverrides then
        for pName, limit in pairs(self.db.playerOverrides) do
            self:SendAddonMsg("P|" .. pName .. "|" .. limit, "WHISPER", senderName)
        end
    end

    for pName, list in pairs(self.db.reserves) do
        if list and #list > 0 then
            local parts = {}
            for _, e in ipairs(list) do
                parts[#parts + 1] = (e.itemID or 0) .. ":" .. (e.count or 1)
            end
            local role = self:GetPlayerRole(pName)
            self:SendAddonMsg("Y|" .. pName .. "|" .. role .. "|" .. table.concat(parts, ","), "WHISPER", senderName)
        end
    end
    self:SendAddonMsg("Z", "WHISPER", senderName)
end

function SR:OnSyncPlayer(data)
    if self:IsSessionHost() then return end -- хост локально має пріоритет

    local pName, role, itemStr = data:match("^([^|]+)|([^|]+)|(.*)$")
    if not pName then 
        pName, itemStr = data:match("^([^|]+)|(.*)$")
    end
    if not pName then return end

    if role and self.db.roles then
        self.db.roles[pName] = role
    end

    if not itemStr or itemStr == "" then
        self.db.reserves[pName] = nil
        if self._syncPending then
            -- все ще чекаємо на Z
        else
            if self.UpdateDashboard then self:UpdateDashboard() end
            if self.UpdateLedger then self:UpdateLedger() end
            if self.UpdateLootBrowserItems then self:UpdateLootBrowserItems() end
        end
        return
    end

    local list = {}
    for chunk in itemStr:gmatch("[^,]+") do
        local id, cnt = chunk:match("^(%d+):(%d+)$")
        id, cnt = tonumber(id), tonumber(cnt)
            if id then
                SR:QueueItemCache(id)
                local _, link = GetItemInfo(id)
                list[#list + 1] = {
                    itemID   = id,
                    itemLink = link or SR:GetSafeItemLink(id, nil),
                    count    = cnt or 1,
                }
            end
    end
    self.db.reserves[pName] = (#list > 0) and list or nil
    if not self._syncPending then
        if self.UpdateDashboard then self:UpdateDashboard() end
        if self.UpdateLedger then self:UpdateLedger() end
        if self.UpdateLootBrowserItems then self:UpdateLootBrowserItems() end
    end
end

function SR:OnSyncComplete()
    self._syncPending = false
    self:Print("Синхронізацію завершено.")
    self:RefreshSessionUI()
end

function SR:OnCoHostsUpdate(data)
    if self:IsSessionHost() then return end
    self.sessionCoHosts = {}
    if data and data ~= "" then
        for name in string.gmatch(data, "[^,]+") do
            self.sessionCoHosts[name] = true
        end
    end
    self:RefreshSessionUI()
end

--------------------------------------------------------------
-- РЕЄСТРАЦІЯ SR ЧЕРЕЗ ПОВІДОМЛЕННЯ АДДОНА (клієнт → хост)
--------------------------------------------------------------

--- Викликається з кнопки "Зарезервувати предмет" в Оглядачі Здобичі.
function SR:RequestSRFromUI(itemID, count, targetPlayer)
    count = count or 1
    targetPlayer = targetPlayer or self:GetLocalPlayerName()

    if not itemID then
        self:Print("Предмет не вибрано.")
        return
    end

    if self.locked or self.sessionLocked then
        self:Print("Софт-роли наразі |cffff4444ЗАБЛОКОВАНІ|r.")
        return
    end

    if not self.sessionActive or not self.sessionHost then
        -- Адмін може реєструвати навіть без активної сесії — авто-стартуємо
        if self:IsAdmin() then
            self:AutoStartSession()
        else
            self:Print("Немає активної сесії SR.")
            return
        end
    end

    if self:IsSessionHost() then
        self:QueueItemCache(itemID)
        local _, link = GetItemInfo(itemID)
        if not link then
            self:ForceQueryItem(itemID)
            _, link = GetItemInfo(itemID)
        end
        link = self:GetSafeItemLink(itemID, link)
        local ok, err = self:ProcessSRRegistration(targetPlayer, link, count, false)
        if ok then
            if targetPlayer == self:GetLocalPlayerName() then
                self:Print("SR зареєстровано.")
            else
                self:Print("SR зареєстровано для " .. targetPlayer .. ".")
                -- Сповіщення цільовому гравцю
                self:SendAddonMsg("K|1|РЛ ("..self:GetLocalPlayerName()..") додав вам софт-рол: " .. link, "WHISPER", targetPlayer)
            end
            
            -- Оновлення UI хоста
            if self.UpdateLootBrowserItems then self:UpdateLootBrowserItems() end
            if self.UpdateLedger then self:UpdateLedger() end
            return true
        else
            self:Print("Помилка реєстрації SR: " .. (err or "Невідома помилка."))
            return false, err
        end
    end

    -- Клієнт → хост через приватне повідомлення аддона
    if self:CanEditSession() then
        self._pendingSRItemID = itemID
        self:SendAddonMsg("M|" .. targetPlayer .. "|" .. itemID .. "|" .. count, "WHISPER", self.sessionHost)
        self:Print("Запит на реєстрацію SR (Ко-Хост) надіслано хосту...")
        return "PENDING"
    else
        if targetPlayer ~= self:GetLocalPlayerName() then
            self:Print("Ви не можете додавати софт-роли іншим гравцям.")
            return
        end
        self._pendingSRItemID = itemID
        self:SendAddonMsg("A|" .. itemID .. "|" .. count, "WHISPER", self.sessionHost)
        self:Print("Запит на реєстрацію SR надіслано хосту |cffffcc00" .. self.sessionHost .. "|r…")
        return "PENDING"
    end
end

function SR:OnSRAddRequest(data, senderName)
    -- Тільки Активний Хост обробляє реєстрації
    if not self:IsSessionHost() then return end

    local itemID, count = data:match("^(%d+)|(%d+)$")
    itemID = tonumber(itemID)
    count  = tonumber(count) or 1
    if not itemID then return end

    if not self:IsInRaid(senderName) then
        self:SendAddonMsg("K|0|Ви не в рейді.", "WHISPER", senderName)
        return
    end

    local _, link = GetItemInfo(itemID)
    if not link then
        self:ForceQueryItem(itemID)
        _, link = GetItemInfo(itemID)
    end
    if not link then
        link = self:GetSafeItemLink(itemID, nil)
    end

    local ok, err = self:ProcessSRRegistration(senderName, link, count, true)
    if ok then
        local used  = self:GetUsedSRCount(senderName)
        local limit = self:GetSRLimit(senderName)
        local role  = self:GetPlayerRole(senderName)
        self:SendAddonMsg("K|1|SR зареєстровано (" .. used .. " з " .. limit .. "). Роль: " .. self.ROLE_LABELS[role], "WHISPER", senderName)
        self:Print(senderName .. " зареєстрував(ла) SR через інтерфейс: " .. link)
    else
        self:SendAddonMsg("K|0|" .. (err or "Невідома помилка."), "WHISPER", senderName)
    end
end

function SR:OnSRManageRequest(data, senderName)
    if not self:IsSessionHost() then return end
    if not self:IsCoHost(senderName) then return end

    local targetPlayer, itemID, count = data:match("^([^|]+)|(%d+)|(%d+)$")
    itemID = tonumber(itemID)
    count  = tonumber(count) or 1
    if not targetPlayer or not itemID then return end

    local _, link = GetItemInfo(itemID)
    if not link then
        self:ForceQueryItem(itemID)
        _, link = GetItemInfo(itemID)
    end
    link = self:GetSafeItemLink(itemID, link)

    local ok, err = self:ProcessSRRegistration(targetPlayer, link, count, false)
    if ok then
        self:Print(senderName .. " (Ко-Хост) додав софт-рол для " .. targetPlayer .. ": " .. link)
        self:SendAddonMsg("K|1|SR для " .. targetPlayer .. " успішно зареєстровано.", "WHISPER", senderName)
        if self.UpdateLootBrowserItems then self:UpdateLootBrowserItems() end
        if self.UpdateLedger then self:UpdateLedger() end
        
        local chatType = (GetNumRaidMembers() > 0) and "RAID" or "PARTY"
        if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then chatType = "SAY" end
        SendChatMessage("Додано " .. link .. " до софтів гравця " .. targetPlayer, chatType)
    else
        self:SendAddonMsg("K|0|" .. (err or "Невідома помилка."), "WHISPER", senderName)
    end
end

function SR:OnSRAddReply(data)
    local okFlag, text = data:match("^(%d)|(.*)$")
    if okFlag == "1" then
        self:Print("|cff44ff44" .. (text or "SR зареєстровано.") .. "|r")
        -- Оновлюємо лічильники SR в оглядачі здобичі
        if self.UpdateLootBrowserItems then self:UpdateLootBrowserItems() end
        if self.UpdateLedger then self:UpdateLedger() end
    else
        self:Print("|cffff4444" .. (text or "Помилка реєстрації SR.") .. "|r")
    end
    self._pendingSRItemID = nil
end

function SR:OnSRRemoveRequest(data, senderName)
    if not self:IsSessionHost() then return end
    
    local targetPlayer, itemID
    if data:find("|") then
        targetPlayer, itemID = data:match("^([^|]+)|(%d+)$")
    else
        targetPlayer = senderName
        itemID = data
    end
    
    itemID = tonumber(itemID)
    if not itemID or not targetPlayer then return end
    
    if targetPlayer ~= senderName and not self:IsCoHost(senderName) then
        return -- Неавторизований запит на видалення чужого SR
    end
    
    if targetPlayer == senderName and not self:IsInRaid(senderName) then return end
    
    if self.locked and not self:IsCoHost(senderName) then
        self:SendAddonMsg("K|0|Софт-роли наразі ЗАБЛОКОВАНІ.", "WHISPER", senderName)
        return
    end

    local removed = self:RemoveSR(targetPlayer, itemID)
    if removed then
        self:SendAddonMsg("K|1|Предмет успішно видалено.", "WHISPER", senderName)
        self:Print(senderName .. (targetPlayer ~= senderName and " (Ко-Хост) видалив SR у " .. targetPlayer or " видалив(ла) свій SR."))
        
        if targetPlayer ~= senderName then
            local _, link = GetItemInfo(itemID)
            link = link or self:GetSafeItemLink(itemID, nil)
            local chatType = (GetNumRaidMembers() > 0) and "RAID" or "PARTY"
            if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then chatType = "SAY" end
            SendChatMessage("Видалено " .. link .. " з софтів гравця " .. targetPlayer, chatType)
        end
    else
        self:SendAddonMsg("K|0|Предмет не знайдено.", "WHISPER", senderName)
    end
end

function SR:OnSRClearRequest(data, senderName)
    if not self:IsSessionHost() then return end
    
    local targetPlayer = (data and data ~= "") and data or senderName
    
    if targetPlayer ~= senderName and not self:IsCoHost(senderName) then return end
    
    if targetPlayer == senderName and not self:IsInRaid(senderName) then return end
    
    if self.locked and not self:IsCoHost(senderName) then
        self:SendAddonMsg("K|0|Софт-роли наразі ЗАБЛОКОВАНІ.", "WHISPER", senderName)
        return
    end

    self:ClearPlayerSR(targetPlayer)
    self:SendAddonMsg("K|1|Софт-роли очищено.", "WHISPER", senderName)
    self:Print(senderName .. (targetPlayer ~= senderName and " (Ко-Хост) очистив SR у " .. targetPlayer or " очистив(ла) свої SR."))
end

function SR:OnWipeAll(senderName)
    if self:IsSessionHost() then
        if self:IsCoHost(senderName) then
            self:ResetAllSR()
            self:Print(senderName .. " (Ко-Хост) очистив усі софт-роли.")
        end
        return
    end
    if self.sessionActive and self.sessionHost and senderName ~= self.sessionHost then return end
    wipe(self.db.reserves)
    wipe(self.db.roles)
    if self.db.limits then wipe(self.db.limits) end
    self:RefreshSessionUI()
    self:Print("Хост очистив усі софт-роли.")
end

--- Спільна валідація + додавання SR (використовується ChatParser, Comms та інтерфейсом хоста).
-- @param notifyHost якщо true, хост виводить повідомлення в чат (віддалена реєстрація)
function SR:ProcessSRRegistration(senderName, itemLink, count, notifyHost)
    if self.sessionActive and not self:IsSessionHost() then
        return false, "Хост сесії — " .. (self.sessionHost or "інший гравець") .. "."
    end

    if self:IsSessionHost() then
        if self.locked then
            return false, "Софт-роли наразі ЗАБЛОКОВАНІ."
        end
    elseif self.locked or self.sessionLocked then
        return false, "Софт-роли наразі ЗАБЛОКОВАНІ."
    end

    if not self:IsInRaid(senderName) then
        return false, "Ви не в рейді."
    end

    count = count or 1
    local limit     = self:GetSRLimit(senderName)
    local used      = self:GetUsedSRCount(senderName)
    local remaining = limit - used

    if count > remaining then
        if remaining <= 0 then
            return false, "Не залишилось вільних слотів для SR (" .. used .. " з " .. limit .. ")."
        end
        return false, "У вас залишилось лише " .. remaining .. " SR (" .. used .. " з " .. limit .. " використано)."
    end

    local ok, err = self:AddSR(senderName, itemLink, count)
    return ok, err
end

--- Хост надсилає резерви одного гравця клієнтам у режимі читання.
function SR:BroadcastPlayerSync(pName)
    if not self:IsSessionHost() then return end
    local list = self.db.reserves[pName]
    local parts = {}
    if list then
        for _, e in ipairs(list) do
            parts[#parts + 1] = (e.itemID or 0) .. ":" .. (e.count or 1)
        end
    end
    local role = self:GetPlayerRole(pName)
    self:SendAddonMsg("Y|" .. pName .. "|" .. role .. "|" .. table.concat(parts, ","), "RAID")
end

--- Після того, як хост редагує резерви, транслює повну синхронізацію в рейд.
function SR:BroadcastFullSync()
    if not self:IsSessionHost() then return end
    for pName, list in pairs(self.db.reserves) do
        if list and #list > 0 then
            local parts = {}
            for _, e in ipairs(list) do
                parts[#parts + 1] = (e.itemID or 0) .. ":" .. (e.count or 1)
            end
            local role = self:GetPlayerRole(pName)
            self:SendAddonMsg("Y|" .. pName .. "|" .. role .. "|" .. table.concat(parts, ","), "RAID")
        end
    end
    self:SendAddonMsg("Z", "RAID")
end

function SR:RefreshSessionUI()
    if self.UpdateDashboard  then self:UpdateDashboard()  end
    if self.UpdateLedger     then self:UpdateLedger()     end
    if self.UpdateSessionBanner then self:UpdateSessionBanner() end
    if self.UpdateAdminReadOnly then self:UpdateAdminReadOnly() end
    if self.UpdateLootBrowserItems then self:UpdateLootBrowserItems() end
    if self.UpdateLootSession then self:UpdateLootSession() end
end

--- Викликається один раз після завантаження інтерфейсу; запитує рейд/паті, чи сесія вже запущена.
function SR:AnnounceHello()
    if self:GetAddonChannel() then
        self:SendAddonMsg("H", "RAID") -- SendAddonMsg will automatically map "RAID" to "PARTY" if needed
    end
end