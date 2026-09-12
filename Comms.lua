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
--    Y|player|role|id:c,id:c Частина синхронізації від хоста (один гравець).
--                            Клієнт НЕ стирає свої резерви заздалегідь — кожен
--                            згаданий у поточному раунді (Q…Z) гравець
--                            запамʼятовується, а після Z видаляються лише ті,
--                            кого хост жодного разу не згадав (diff-синхронізація,
--                            без миттєвого "все зникло" між Q і Z).
--    Z                       Синхронізацію від хоста завершено (і межа раунду diff)
--    H                       Привітання клієнта — хост повторно анонсує сесію, якщо вона активна
--
--  ВІДНОВЛЕННЯ ДАНИХ ХОСТА З РЕЙДУ (напр. після краху хоста):
--    RP                      Хост → рейд: "хто має кешовані резерви?"
--    RA|name|count           Відповідь клієнта з кешем: скільки гравців у нього закешовано
--    RQ                      Хост → обраний клієнт: "надішли свою копію"
--    RY|player|role|id:c,.. Одна запис відновлення (той самий формат, що й Y,
--                            але окрема команда, щоб не змішувати з живою sync)
--    RZ                      Відновлення від цього клієнта завершено
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

--- Повертає true, якщо вказаний гравець (не обов'язково локальний) зараз має права
-- лідера рейду або лідера паті. Використовується для перевірки вхідних "S|hostName"
-- повідомлень — довіряти можна лише параметру senderName (його підставляє сам клієнт
-- WoW і підмінити неможливо), а не вмісту повідомлення.
function SR:PlayerHasLeaderAuthority(name)
    if not name then return false end

    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local rName, rank = GetRaidRosterInfo(i)
            if rName and self:StripRealm(rName) == name then
                return rank == 2
            end
        end
        return false
    end

    if GetNumPartyMembers() > 0 then
        local leaderIndex = GetPartyLeaderIndex and GetPartyLeaderIndex() or 0
        if leaderIndex == 0 then
            return name == self:GetLocalPlayerName()
        end
        local leaderName = self:StripRealm(GetUnitName("party" .. leaderIndex, true))
        return name == leaderName
    end

    return name == self:GetLocalPlayerName()
end

--- Повертає true, якщо гравець у списку Ко-Хостів і є помічником в рейді.
function SR:IsCoHost(name)
    if not name then return false end
    name = self:StripRealm(name)
    if not self.db.coHosts then return false end
    if not self.db.coHosts[name] then return false end
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local rName, rank = GetRaidRosterInfo(i)
            if rName and self:StripRealm(rName) == name then
                return rank and rank > 0
            end
        end
        return false
    end
    if GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do
            local pName = GetUnitName("party" .. i, true)
            if pName and self:StripRealm(pName) == name then
                return true
            end
        end
        return false
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
        self:Print(self.L.PRINT_SESSION_START_LEADER)
        return
    end
    if self.sessionActive and self.sessionHost ~= self:GetLocalPlayerName() then
        self:Print(format(self.L.PRINT_SESSION_ALREADY_ACTIVE, self.sessionHost))
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

    self:Print(self.L.PRINT_SESSION_STARTED_HOST)
    self:RefreshSessionUI()
    if self:ShouldPromptDataRecovery() and self.ShowDataRecoveryPrompt then
        self:ShowDataRecoveryPrompt()
    end
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

    self:Print(self.L.PRINT_SESSION_AUTO_STARTED)
    self:RefreshSessionUI()
    if self:ShouldPromptDataRecovery() and self.ShowDataRecoveryPrompt then
        self:ShowDataRecoveryPrompt()
    end
end

function SR:EndSession()
    if not self.sessionActive then
        self:Print(self.L.PRINT_SESSION_NO_ACTIVE)
        return
    end
    if not self:IsSessionHost() then
        self:Print(format(self.L.PRINT_SESSION_ONLY_HOST_END, (self.sessionHost or "?")))
        return
    end

    local host = self.sessionHost
    self:SendAddonMsg("E|" .. host, "RAID")

    self.sessionActive = false
    self.sessionHost   = nil
    self.sessionLocked = false
    self.locked        = false
    self.db.locked     = false  -- зберігаємо в db

    self:Print(self.L.PRINT_SESSION_ENDED)
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
        if not self.sessionHost or senderName == self.sessionHost then
            self:OnSessionLock(rest, senderName)
        end
    elseif cmd == "A" then
        self:OnSRAddRequest(rest, senderName)
    elseif cmd == "K" then
        self:OnSRAddReply(rest)
    elseif cmd == "Q" then
        self:OnSyncRequest(senderName)
    elseif cmd == "Y" then
        if not self.sessionHost or senderName == self.sessionHost then
            self:OnSyncPlayer(rest, senderName)
        end
    elseif cmd == "Z" then
        if not self.sessionHost or senderName == self.sessionHost then
            self:OnSyncComplete(senderName)
        end
    elseif cmd == "P" then
        if not self.sessionHost or senderName == self.sessionHost or self:IsCoHost(senderName) then
            self:OnPlayerOverrideSync(rest, senderName)
        end
    elseif cmd == "H" then
        self:OnHello(senderName)
    elseif cmd == "O" then
        if not self.sessionHost or senderName == self.sessionHost then
            self:OnCoHostsUpdate(rest, senderName)
        end
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
                    self:Print(format(self.L.PRINT_COHOST_CHANGED_DUNGEON, senderName))
                    self:SendAddonMsg("I|" .. inst .. "|" .. mode, "RAID")
                end
            elseif senderName == self.sessionHost then
                -- Клієнт: приймаємо зміни лише від поточного хоста сесії
                -- (інакше будь-хто в рейді міг би підмінити підземелля/режим).
                self.db.instance = inst
                self.db.srMode = mode
                if self.UpdateDashboard then self:UpdateDashboard() end
                if self.UpdateLedger then self:UpdateLedger() end
            end
        end
    elseif cmd == "T" then
        self:OnLockChangeRequest(rest, senderName)
    elseif cmd == "RP" then
        self:OnRecoveryPing(senderName)
    elseif cmd == "RA" then
        self:OnRecoveryAck(rest, senderName)
    elseif cmd == "RQ" then
        self:OnRecoveryQuery(senderName)
    elseif cmd == "RY" then
        self:OnRecoveryData(rest, senderName)
    elseif cmd == "RZ" then
        self:OnRecoveryComplete(senderName)
    end
end

function SR:OnPlayerOverrideSync(data, senderName)
    if senderName and self.sessionHost and senderName ~= self.sessionHost and not self:IsCoHost(senderName) then return end
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
        self:Print(format(self.L.PRINT_COHOST_CHANGED_ROLE, senderName, pName, role))
    end
end

function SR:OnOverrideChangeRequest(data, senderName)
    if not self:IsSessionHost() then return end
    if not self:IsCoHost(senderName) then return end
    local pName, limit = data:match("^([^|]+)|([^|]+)$")
    if pName and limit then
        limit = tonumber(limit)
        self:SetPlayerOverride(pName, limit)
        self:Print(format(self.L.PRINT_COHOST_CHANGED_LIMIT, senderName, pName, (limit > 0 and limit or "стандартний")))
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

    local chatType = self:GetAnnouncementChannel(true)
    if self.locked then
        self:Print(format(self.L.PRINT_COHOST_LOCKED, senderName))
        SendChatMessage(self.L.SESSION_LOCKED, chatType)
    else
        self:Print(format(self.L.PRINT_COHOST_UNLOCKED, senderName))
        SendChatMessage(self.L.SESSION_UNLOCKED, chatType)
    end
end

--- Обробка вхідного "S|hostName". Заявлене в тексті повідомлення ім'я ігнорується для
-- авторизації — довіряємо лише senderName (реальний відправник за версією клієнта WoW),
-- і вимагаємо, щоб він справді був лідером рейду/паті. Інакше будь-який учасник рейду
-- міг би оголосити себе (або когось іншого) новим хостом сесії.
function SR:OnSessionStart(_hostName, senderName)
    if not senderName then return end
    if not self:PlayerHasLeaderAuthority(senderName) then return end

    -- Якщо цей хост і так уже вважався активним локально, це просто повторне
    -- оголошення (напр. хост перезавантажив гру/перепідключився), а не справді
    -- нова сесія — не варто перезапитувати повну синхронізацію в такому разі.
    local alreadyKnownActive = (self.sessionActive and self.sessionHost == senderName)

    self.sessionActive = true
    self.sessionHost   = senderName

    if senderName == self:GetLocalPlayerName() then
        self:Print(self.L.PRINT_SESSION_HOST_IS_YOU)
        self:BroadcastCoHosts()
    elseif not alreadyKnownActive then
        self:Print(format(self.L.PRINT_SESSION_STARTED_BY, senderName))
        -- Отримуємо дані про резерви від хоста для перегляду
        self:RequestSessionSync(senderName)
    end
    self:RefreshSessionUI()
end

--- Обробка вхідного "E|hostName". Завершити сесію може лише її поточний хост —
-- перевіряємо реального відправника (senderName), а не заявлене в тілі повідомлення ім'я,
-- інакше будь-хто міг би підробити hostName і обірвати чужу сесію.
function SR:OnSessionEnd(_hostName, senderName)
    if senderName ~= self.sessionHost then return end

    self.sessionActive = false
    self.sessionHost   = nil
    self.sessionLocked = false

    self:Print(format(self.L.PRINT_SESSION_ENDED_BY, senderName))
    self:RefreshSessionUI()
end

function SR:OnSessionLock(state, senderName)
    if senderName and self.sessionHost and senderName ~= self.sessionHost then return end
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
        self:Print(format(self.L.PRINT_HOST_RELOADED, senderName))
        self.sessionActive = false
        self.sessionLocked = false
        self:RefreshSessionUI()
    end
end

--- Запит до хоста на знімок резервів (для офіцерів з правами на читання / гравців, що приєдналися пізніше).
-- Локальні резерви НЕ стираються заздалегідь — це diff-синхронізація: кожен
-- гравець, згаданий хостом у відповіді (Y), запамʼятовується, а після Z
-- видаляються лише ті, кого хост жодного разу не підтвердив у цьому раунді
-- (див. OnSyncPlayer / OnSyncComplete). Так локальні дані не зникають навіть
-- на мить, якщо цей запит спричинений, наприклад, гонкою чи повторним "S|".
function SR:RequestSessionSync(hostName)
    hostName = hostName or self.sessionHost
    if not hostName then return end
    self._syncPending = true

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

function SR:OnSyncPlayer(data, senderName)
    if senderName and self.sessionHost and senderName ~= self.sessionHost then return end
    if self:IsSessionHost() then return end -- хост локально має пріоритет

    local pName, role, itemStr = data:match("^([^|]+)|([^|]+)|(.*)$")
    if not pName then
        pName, itemStr = data:match("^([^|]+)|(.*)$")
    end
    if not pName then return end

    -- Diff-синхронізація: запамʼятовуємо, кого хост підтвердив у цьому раунді
    -- (між Q і Z), щоб після Z прибрати лише тих, кого хост НЕ згадав, а не
    -- стирати все наперед (див. RequestSessionSync / OnSyncComplete).
    self._syncSeenPlayers = self._syncSeenPlayers or {}
    self._syncSeenPlayers[pName] = true

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

function SR:OnSyncComplete(senderName)
    if senderName and self.sessionHost and senderName ~= self.sessionHost then return end
    if not self._syncPending then return end

    -- Прибираємо локально лише тих гравців, кого хост жодного разу не
    -- підтвердив у цьому раунді синхронізації (Q…Z) — тобто діагностуємо
    -- різницю (diff), а не стираємо все на самому початку.
    local seen = self._syncSeenPlayers or {}
    for pName in pairs(self.db.reserves) do
        if not seen[pName] then
            self.db.reserves[pName] = nil
        end
    end
    self._syncSeenPlayers = {}

    self._syncPending = false
    self:Print(self.L.PRINT_SYNC_COMPLETE)
    self:RefreshSessionUI()
end

function SR:OnCoHostsUpdate(data, senderName)
    if senderName and self.sessionHost and senderName ~= self.sessionHost then return end
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
function SR:RequestSRFromUI(itemID, count, targetPlayer, isSet)
    count = count or 1
    targetPlayer = targetPlayer or self:GetLocalPlayerName()

    if not itemID then
        self:Print(self.L.PRINT_NO_ITEM_SELECTED)
        return
    end

    if self.locked or self.sessionLocked then
        self:Print(self.L.WHISPER_CHANGES_LOCKED)
        return
    end

    if not self.sessionActive or not self.sessionHost then
        -- Адмін може реєструвати навіть без активної сесії — авто-стартуємо
        if self:IsAdmin() then
            self:AutoStartSession()
            -- AutoStartSession() завжди стартує ЗАБЛОКОВАНОЮ (це правильно для
            -- автостарту при вході в рейд), але тут адмін явно намагається щось
            -- зареєструвати прямо зараз — інакше ця ж реєстрація одразу
            -- провалиться з "ЗАБЛОКОВАНІ". Розблоковуємо, якщо старт вдався.
            if self:IsSessionHost() then
                self.locked        = false
                self.sessionLocked = false
                self.db.locked     = false
                self:BroadcastLockState()
            end
        else
            self:Print(self.L.PRINT_SESSION_NO_ACTIVE)
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
        local ok, err = self:ProcessSRRegistration(targetPlayer, link, count, false, isSet)
        if ok then
            if targetPlayer == self:GetLocalPlayerName() then
                self:Print(self.L.PRINT_SR_REGISTERED)
            else
                self:Print(format(self.L.PRINT_SR_REGISTERED_FOR, targetPlayer))
                -- Сповіщення цільовому гравцю
                self:SendAddonMsg("K|1|РЛ ("..self:GetLocalPlayerName()..") додав вам софт-рол: " .. link, "WHISPER", targetPlayer)
            end
            
            -- Оновлення UI хоста
            if self.UpdateLootBrowserItems then self:UpdateLootBrowserItems() end
            if self.UpdateLedger then self:UpdateLedger() end
            return true
        else
            self:Print(format(self.L.PRINT_SR_REG_ERROR, err or "Невідома помилка."))
            return false, err
        end
    end

    if not self.sessionHost then
        -- IsAdmin() був true, але AutoStartSession() все одно не стартував
        -- (наприклад, офіцер рейду без прав лідера) — сесії й досі немає.
        self:Print(self.L.PRINT_SESSION_NO_ACTIVE)
        return
    end

    -- Клієнт → хост через приватне повідомлення аддона
    local setFlag = isSet and "1" or "0"
    if self:CanEditSession() then
        self._pendingSRItemID = itemID
        self:SendAddonMsg("M|" .. targetPlayer .. "|" .. itemID .. "|" .. count .. "|" .. setFlag, "WHISPER", self.sessionHost)
        self:Print(self.L.PRINT_REG_REQUEST_COHOST)
        return "PENDING"
    else
        if targetPlayer ~= self:GetLocalPlayerName() then
            self:Print(self.L.PRINT_CANNOT_ADD_OTHERS)
            return
        end
        self._pendingSRItemID = itemID
        self:SendAddonMsg("A|" .. itemID .. "|" .. count .. "|" .. setFlag, "WHISPER", self.sessionHost)
        self:Print(format(self.L.PRINT_REG_REQUEST_SENT, self.sessionHost))
        return "PENDING"
    end
end

function SR:OnSRAddRequest(data, senderName)
    -- Тільки Активний Хост обробляє реєстрації
    if not self:IsSessionHost() then return end
    if not data or data == "" then return end
    if self.StripRealm then senderName = self:StripRealm(senderName) end

    local itemID, count, isSet = data:match("^(%d+)|(%d+)|?(%d*)$")
    if not itemID then
        itemID = data:match("^(%d+)$")
        count = 1
        isSet = false
    else
        itemID = tonumber(itemID)
        count  = tonumber(count) or 1
        isSet  = (isSet == "1")
    end
    itemID = tonumber(itemID)
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

    local ok, err = self:ProcessSRRegistration(senderName, link, count, true, isSet)
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
    if not data or data == "" then return end
    if self.StripRealm then senderName = self:StripRealm(senderName) end
    if not self:IsCoHost(senderName) then return end

    local targetPlayer, itemID, count, isSet = data:match("^([^|]+)|(%d+)|(%d+)|?(%d*)$")
    if not targetPlayer then
        targetPlayer, itemID = data:match("^([^|]+)|(%d+)$")
        count = 1
        isSet = false
    else
        itemID = tonumber(itemID)
        count  = tonumber(count) or 1
        isSet  = (isSet == "1")
    end
    itemID = tonumber(itemID)
    if not targetPlayer or not itemID then return end
    if self.StripRealm then targetPlayer = self:StripRealm(targetPlayer) end

    local _, link = GetItemInfo(itemID)
    if not link then
        self:ForceQueryItem(itemID)
        _, link = GetItemInfo(itemID)
    end
    link = self:GetSafeItemLink(itemID, link)

    local ok, err = self:ProcessSRRegistration(targetPlayer, link, count, false, isSet)
    if ok then
        self:Print(format(self.L.PRINT_COHOST_ADDED_FOR, senderName, targetPlayer, link))
        self:SendAddonMsg("K|1|SR для " .. targetPlayer .. " успішно зареєстровано.", "WHISPER", senderName)
        if self.UpdateLootBrowserItems then self:UpdateLootBrowserItems() end
        if self.UpdateLedger then self:UpdateLedger() end
        
        local chatType = (GetNumRaidMembers() > 0) and "RAID" or "PARTY"
        if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then chatType = "SAY" end
        SendChatMessage(format(self.L.SR_ADDED_FOR_PLAYER, link, targetPlayer), chatType)
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
    if not data or data == "" then return end
    if self.StripRealm then senderName = self:StripRealm(senderName) end
    
    local targetPlayer, itemID
    if data:find("|") then
        targetPlayer, itemID = data:match("^([^|]+)|(%d+)$")
    else
        targetPlayer = senderName
        itemID = data
    end
    
    itemID = tonumber(itemID)
    if not itemID or not targetPlayer then return end
    if self.StripRealm then targetPlayer = self:StripRealm(targetPlayer) end
    
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
        self:Print(senderName .. (targetPlayer ~= senderName and (" (помічник) видалив софт-рол у " .. targetPlayer) or " видалив(ла) свій софт-рол."))
        
        if targetPlayer ~= senderName then
            local _, link = GetItemInfo(itemID)
            link = link or self:GetSafeItemLink(itemID, nil)
            local chatType = (GetNumRaidMembers() > 0) and "RAID" or "PARTY"
            if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then chatType = "SAY" end
            SendChatMessage(format(self.L.SR_REMOVED_FOR_PLAYER, link, targetPlayer), chatType)
        end
    else
        self:SendAddonMsg("K|0|Предмет не знайдено.", "WHISPER", senderName)
    end
end

function SR:OnSRClearRequest(data, senderName)
    if not self:IsSessionHost() then return end
    if self.StripRealm then senderName = self:StripRealm(senderName) end
    
    local targetPlayer = (data and data ~= "") and data or senderName
    if self.StripRealm then targetPlayer = self:StripRealm(targetPlayer) end
    
    if targetPlayer ~= senderName and not self:IsCoHost(senderName) then return end
    
    if targetPlayer == senderName and not self:IsInRaid(senderName) then return end
    
    if self.locked and not self:IsCoHost(senderName) then
        self:SendAddonMsg("K|0|Софт-роли наразі ЗАБЛОКОВАНІ.", "WHISPER", senderName)
        return
    end

    self:ClearPlayerSR(targetPlayer)
    self:SendAddonMsg("K|1|Софт-роли очищено.", "WHISPER", senderName)
    self:Print(senderName .. (targetPlayer ~= senderName and (" (помічник) очистив софт-роли у " .. targetPlayer) or " очистив(ла) свої софт-роли."))
end

function SR:OnWipeAll(senderName)
    if self:IsSessionHost() then
        if self:IsCoHost(senderName) then
            self:ResetAllSR()
            self:Print(format(self.L.PRINT_COHOST_CLEARED_ALL, senderName))
        end
        return
    end
    -- Довіряємо лише поточному хосту сесії; якщо ж локально ще не зафіксовано
    -- жодного хоста (наприклад, одразу після /reload, до першого "S|"),
    -- підстраховуємось перевіркою реальних прав лідера рейду/паті — інакше
    -- будь-хто міг би підробити "W" і очистити дані клієнта.
    if self.sessionHost then
        if senderName ~= self.sessionHost then return end
    elseif not self:PlayerHasLeaderAuthority(senderName) then
        return
    end
    wipe(self.db.reserves)
    wipe(self.db.roles)
    self:RefreshSessionUI()
    self:Print(self.L.PRINT_HOST_CLEARED_ALL)
end

--- Спільна валідація + додавання SR (використовується ChatParser, Comms та інтерфейсом хоста).
-- @param notifyHost якщо true, хост виводить повідомлення в чат (віддалена реєстрація)
function SR:ProcessSRRegistration(senderName, itemLink, count, notifyHost, isSet)
    if not senderName or senderName == "" then
        return false, "Невідомий гравець."
    end
    if self.StripRealm then senderName = self:StripRealm(senderName) end

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

    count = math.floor(tonumber(count) or 1)
    if count < 1 then count = 1 end
    local limit     = self:GetSRLimit(senderName)
    local used      = self:GetUsedSRCount(senderName)
    local remaining = limit - used

    local requiredSlots = count
    if isSet then
        local itemID = self:GetItemIDFromLink(itemLink)
        if itemID and self.db.reserves[senderName] then
            local eq = self.GetEquivalentItemIDs and self:GetEquivalentItemIDs(itemID) or { [itemID] = true }
            for _, e in ipairs(self.db.reserves[senderName]) do
                if eq[e.itemID] then
                    requiredSlots = count - (e.count or 1)
                    if requiredSlots < 0 then requiredSlots = 0 end
                    break
                end
            end
        end
    end

    if requiredSlots > remaining then
        if remaining <= 0 then
            return false, "Не залишилось вільних слотів для SR (" .. used .. " з " .. limit .. ")."
        end
        return false, "У вас залишилось лише " .. remaining .. " SR (" .. used .. " з " .. limit .. " використано)."
    end

    local ok, err = self:AddSR(senderName, itemLink, count, isSet)
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

--------------------------------------------------------------
-- ВІДНОВЛЕННЯ ДАНИХ ХОСТА З РЕЙДУ
-- Кожен клієнт з аддоном, синхронізований у сесії, тримає в себе копію
-- db.reserves всього рейду (бо хост розсилає кожну зміну через Y|... в RAID).
-- Якщо хост втратив свою локальну копію (напр. SavedVariables не встигли
-- записатись на диск при краші), можна попросити конкретного гравця з
-- аддоном переслати те, що закешовано в нього — це відновить дані навіть
-- для тих, хто реєструвався через чат-команди, а не UI.
--------------------------------------------------------------

--- Евристика: чи схоже, що резерви хоста могли загубитись. Неточно (може
-- бути й справді щойно початий рейд), тому лише ПРОПОНУЄ відновлення —
-- ніколи не стирає й не змінює дані сама.
function SR:ShouldPromptDataRecovery()
    if self._dataLossPromptDismissed then return false end
    if next(self.db.reserves) then return false end
    return #self:GetRaidMembers() > 1
end

--- Хост розсилає "пінг" у рейд: хто має закешовані резерви?
function SR:StartRecoveryScan()
    if not self:IsSessionHost() then return end
    self._recoveryResponses = {}
    self:SendAddonMsg("RP", "RAID")
end

--- Відповідь на пінг: якщо в нас є закешовані резерви, повідомляємо хосту
-- скільки гравців у них закешовано (щоб хост міг обрати найповнішу копію).
-- Довіряємо лише поточному хосту (або, якщо сесія ще не зафіксована,
-- реальному лідеру рейду/паті) — так само, як і в OnWipeAll.
function SR:OnRecoveryPing(senderName)
    if self.sessionHost then
        if senderName ~= self.sessionHost then return end
    elseif not self:PlayerHasLeaderAuthority(senderName) then
        return
    end

    local count = 0
    for _, list in pairs(self.db.reserves) do
        if list and #list > 0 then count = count + 1 end
    end
    if count == 0 then return end

    self:SendAddonMsg("RA|" .. self:GetLocalPlayerName() .. "|" .. count, "WHISPER", senderName)
end

--- Хост збирає відповіді на пінг (для показу списку у попапі вибору джерела).
function SR:OnRecoveryAck(data, senderName)
    if not self:IsSessionHost() then return end
    if not self._recoveryResponses then return end -- сканування не запущено

    local name, count = data:match("^([^|]+)|(%d+)$")
    count = tonumber(count)
    if not name or not count then return end

    self._recoveryResponses[senderName] = { name = name, count = count }
    if self.UpdateRecoveryPopup then self:UpdateRecoveryPopup() end
end

--- Хост явно обирає конкретного гравця і просить у нього повну копію.
function SR:RequestRecoveryFrom(targetName)
    if not self:IsSessionHost() then return end
    if not targetName then return end

    self._recoveryPending = true
    self._recoveryFrom    = targetName
    self._recoveryData    = {}
    self:SendAddonMsg("RQ", "WHISPER", targetName)
end

--- Відповідаємо на запит відновлення, лише якщо він справді від поточного
-- хоста — інакше будь-хто міг би виманити повний список чужих резервів.
function SR:OnRecoveryQuery(senderName)
    if senderName ~= self.sessionHost then return end

    for pName, list in pairs(self.db.reserves) do
        if list and #list > 0 then
            local parts = {}
            for _, e in ipairs(list) do
                parts[#parts + 1] = (e.itemID or 0) .. ":" .. (e.count or 1)
            end
            local role = self:GetPlayerRole(pName)
            self:SendAddonMsg("RY|" .. pName .. "|" .. role .. "|" .. table.concat(parts, ","), "WHISPER", senderName)
        end
    end
    self:SendAddonMsg("RZ", "WHISPER", senderName)
end

--- Хост приймає один запис відновлення. Приймаємо дані лише від того самого
-- гравця, кого ми самі обрали й запитали — інакше хтось інший міг би
-- підсунути хосту довільні "відновлені" резерви.
function SR:OnRecoveryData(data, senderName)
    if not self._recoveryPending then return end
    if senderName ~= self._recoveryFrom then return end

    local pName, role, itemStr = data:match("^([^|]+)|([^|]+)|(.*)$")
    if not pName then return end

    local list = {}
    for chunk in (itemStr or ""):gmatch("[^,]+") do
        local id, cnt = chunk:match("^(%d+):(%d+)$")
        id, cnt = tonumber(id), tonumber(cnt)
        if id then
            list[#list + 1] = { itemID = id, itemLink = self:GetSafeItemLink(id, nil), count = cnt or 1 }
        end
    end

    self._recoveryData[pName] = { role = role, list = list }
end

--- Завершення відновлення: перезбираємо db.reserves з отриманого і розсилаємо
-- всьому рейду свіжий стан, щоб усі знову бачили однакові дані.
function SR:OnRecoveryComplete(senderName)
    if not self._recoveryPending then return end
    if senderName ~= self._recoveryFrom then return end

    local n = 0
    for pName, entry in pairs(self._recoveryData or {}) do
        self.db.reserves[pName] = entry.list
        if entry.role and self.db.roles then
            self.db.roles[pName] = entry.role
        end
        n = n + 1
    end

    self._recoveryPending = false
    self._recoveryFrom    = nil
    self._recoveryData    = nil

    self:Print(format(self.L.PRINT_RECOVERY_COMPLETE, n, (senderName or "?")))
    self:RefreshSessionUI()
    self:BroadcastFullSync()
    if self.HideRecoveryPopup then self:HideRecoveryPopup() end
end