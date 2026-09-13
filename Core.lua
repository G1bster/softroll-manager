--------------------------------------------------------------
-- SoftRollManager  —  Core.lua  (v2.0)
-- Ініціалізація, константи, керування даними, допоміжні функції
-- Сумісно з WoW 3.3.5a (WotLK)
--------------------------------------------------------------

--------------------------------------------------------------
-- 1. ПРОСТІР ІМЕН АДДОНА
--------------------------------------------------------------
SoftRoll = {}
local SR = SoftRoll

SR.VERSION    = "4.2.2"
SR.ADDON_NAME = "SoftRollManager"

--------------------------------------------------------------
-- 2. КОНСТАНТИ
--------------------------------------------------------------

-- Підтримувані підземелля
SR.INSTANCES = { "ICC", "RS" }

SR.INSTANCE_LABELS = {
    ICC = "ЦЛК 25",
    RS  = "РС 25",
}

-- Доступні ролі
SR.ROLES = { "TANK", "HEAL", "DPS", "RL" }

SR.ROLE_LABELS = {
    TANK = "Танк",
    HEAL = "Хіл",
    DPS  = "ДПС",
    RL   = "Рейд Лідер",
}

SR.ROLE_SHORT = {
    TANK = "Танк",
    HEAL = "Хіл",
    DPS  = "ДПС",
    RL   = "РЛ",
}

-- Налаштування режимів SR
SR.SR_MODE_DEFS = {
    classic = {
        ICC = { TANK = 3, HEAL = 3, RL = 3, DPS = 3 },
        RS  = { TANK = 1, HEAL = 1, RL = 1, DPS = 1 },
    },
    dynamic = {
        ICC = { TANK = 4, HEAL = 4, RL = 4, DPS = 3 },
        RS  = { TANK = 1, HEAL = 1, RL = 1, DPS = 1 },
    },
    rs_x1 = {
        ICC = { TANK = 3, HEAL = 3, RL = 3, DPS = 3 },
        RS  = { TANK = 1, HEAL = 1, RL = 1, DPS = 1 },
    },
}

SR.SR_MODES = { "classic", "dynamic", "rs_x1" }

SR.SR_MODE_LABELS = {
    classic = "Стандарт(x3)",
    dynamic = "3/4",
    rs_x1 = "Софт x1",
}

-- Кольори для відображення ролей в інтерфейсі
SR.ROLE_COLORS = {
    TANK = { r = 0.20, g = 0.60, b = 1.00 },
    HEAL = { r = 0.00, g = 0.90, b = 0.40 },
    DPS  = { r = 1.00, g = 0.30, b = 0.30 },
    RL   = { r = 1.00, g = 0.50, b = 0.00 },
}

-- Стандартні кольори класів WoW (WotLK)
SR.CLASS_COLORS = {
    WARRIOR     = { r = 0.78, g = 0.61, b = 0.43 },
    PALADIN     = { r = 0.96, g = 0.55, b = 0.73 },
    HUNTER      = { r = 0.67, g = 0.83, b = 0.45 },
    ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },
    PRIEST      = { r = 1.00, g = 1.00, b = 1.00 },
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
    SHAMAN      = { r = 0.00, g = 0.44, b = 0.87 },
    MAGE        = { r = 0.25, g = 0.78, b = 0.92 },
    WARLOCK     = { r = 0.53, g = 0.53, b = 0.93 },
    DRUID       = { r = 1.00, g = 0.49, b = 0.04 },
}

--------------------------------------------------------------
-- 3. СТАН ПІД ЧАС ВИКОНАННЯ (не зберігається)
--------------------------------------------------------------
-- locked зберігається в db, тут тільки runtime-стан
-- SR.locked = false  — відновлюється з db при Initialize()

--------------------------------------------------------------
-- 4. СТАНДАРТНІ ЗНАЧЕННЯ ЗБЕРЕЖЕНИХ ЗМІННИХ
--------------------------------------------------------------
local DB_DEFAULTS = {
    instance        = "ICC",
    srMode          = "classic",       -- "x3" або "x4"
    lootDifficulty  = "25H",     -- "25N" або "25H" (фільтр в оглядачі здобичі)
    roles           = {},         -- [playerName] = "ROLE"
    reserves        = {},         -- [playerName] = { {itemLink=, itemID=, count=}, … }
    playerOverrides = {},         -- [playerName] = maxSRs (число або nil)
    wishlists       = {},         -- [playerName] = { [itemID] = true, ... }
    minimapPos      = 220,        -- кут у градусах для кнопки біля мінікарти
    coHosts         = {},         -- [playerName] = true (список дозволених ко-хостів)
    locked          = true,       -- стан блокування (зберігається між сесіями)
}

SR.activeRollItem = nil
SR.activeRolls = {}

--------------------------------------------------------------
-- 5. ПОСЛІДОВНІСТЬ ЗАВАНТАЖЕННЯ
--------------------------------------------------------------
local eventFrame = CreateFrame("Frame", "SoftRollEventFrame", UIParent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == SR.ADDON_NAME then
            SR:Initialize()
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        if SR.OnGroupRosterUpdate then
            SR:OnGroupRosterUpdate()
        end
    elseif event == "BAG_UPDATE" then
        if SR.OnBagUpdate then
            SR:OnBagUpdate()
        end
    end
end)

function SR:OnBagUpdate()
    if self.mainFrame and self.mainFrame:IsShown() and self.panels and self.panels[4] and self.panels[4]:IsShown() then
        if self.lootSessionMode == "bag" and self.RefreshBagLoot then
            self:RefreshBagLoot()
        end
    end
end

function SR:Initialize()
    -- Перевірка існування таблиці SavedVariables та заповнення відсутніх стандартних значень
    if not SoftRollDB then SoftRollDB = {} end
    for k, v in pairs(DB_DEFAULTS) do
        if SoftRollDB[k] == nil then
            SoftRollDB[k] = (type(v) == "table") and self:CopyTable(v) or v
        end
    end
    self.db = SoftRollDB
    -- Відновлюємо стан блокування з db
    self.locked = (self.db.locked == true)

    -- Міграція БД для старих ролей
    for pName, role in pairs(self.db.roles) do
        if role == "MELEE" or role == "RANGED" then
            self.db.roles[pName] = "DPS"
        elseif role == "HEALER" then
            self.db.roles[pName] = "HEAL"
        end
    end

    -- Слеш команди
    SLASH_SOFTROLL1 = "/sr"
    SLASH_SOFTROLL2 = "/softroll"
    SLASH_SOFTROLL3 = "/ср"
    SLASH_SOFTROLL4 = "/софтрол"
    SlashCmdList["SOFTROLL"] = function(msg) SR:SlashHandler(msg) end

    -- Створення UI, хуки для зв'язку та чату
    self:InitItemCache()
    self:InitComms()
    self:CreateUI()
    self:CreateMinimapButton()
    self:InitChatParser()

    -- Запит до рейду про активну сесію (обробляє перезавантаження UI під час рейду)
    if self.AnnounceHello then
        self:AnnounceHello()
    end

    -- Прогрів кешу предметів для резервів / таблиць здобичі
    self:QueueAllKnownItems()

    self:Print(format(self.L.PRINT_LOADED, self.VERSION))
end

--------------------------------------------------------------
-- 6. ОБРОБНИК СЛЕШ КОМАНД
--------------------------------------------------------------
function SR:SlashHandler(msg)
    msg = strtrim(msg or ""):lower()

    if msg == "reset" then
        if self.sessionActive and not self:IsSessionHost() then
            self:Print(self.L.PRINT_ONLY_HOST_RESET)
        else
            self:ResetAllSR()
        end
    elseif msg == "lock" then
        self.locked = true
        self.sessionLocked = true
        self.db.locked = true
        self:Print(self.L.PRINT_STATUS_LOCKED)
        if self.UpdateDashboard then self:UpdateDashboard() end
        if self.BroadcastLockState then self:BroadcastLockState() end
        local chatType = self:GetAnnouncementChannel(true)
        SendChatMessage(self.L.SESSION_LOCKED, chatType)
    elseif msg == "unlock" then
        self.locked = false
        self.sessionLocked = false
        self.db.locked = false
        self:Print(self.L.PRINT_STATUS_UNLOCKED)
        if self.UpdateDashboard then self:UpdateDashboard() end
        if self.BroadcastLockState then self:BroadcastLockState() end
        local chatType = self:GetAnnouncementChannel(true)
        SendChatMessage(self.L.SESSION_UNLOCKED, chatType)
    elseif msg == "announce" then
        self:AnnounceAllSR()
    elseif msg == "help" then
        self:Print(self.L.HELP_HEADER)
        self:Print(self.L.HELP_CMD_OPEN)
        self:Print(self.L.HELP_CMD_RESET)
        self:Print(self.L.HELP_CMD_LOCK)
        self:Print(self.L.HELP_CMD_ANNOUNCE)
        self:Print(self.L.HELP_CMD_HELP)
    else
        self:ToggleUI()
    end
end

--------------------------------------------------------------
-- 7. ДОПОМІЖНІ ФУНКЦІЇ РЕЙДОВОЇ ГРУПИ
--------------------------------------------------------------
function SR:OnGroupRosterUpdate()
    local currentlyInGroup = (GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0)
    local isLeader = IsRaidLeader() or IsPartyLeader()

    -- ── Авто-старт сесії при вході в рейд/паті (якщо ми лідер) ──
    if currentlyInGroup and not self.wasInGroup then
        self.wasInGroup = true
        if self.AnnounceHello then
            self:AnnounceHello()
        end
    end
    
    -- Автоматично стартуємо сесію як лідер (навіть якщо статус лідера прийшов із затримкою після логіну)
    if currentlyInGroup and isLeader and not self.sessionActive then
        self:AutoStartSession()
    end
    -- ── Авто-завершення сесії при виході з групи ──
    if not currentlyInGroup and self.wasInGroup then
        self.wasInGroup = false
        if self.sessionActive and self:IsSessionHost() then
            self:AutoEndSession()
        elseif self.sessionActive then
            -- Ми клієнт — хост покинув групу
            self.sessionActive = false
            self.sessionLocked = false
            self.locked = false
        end
    end

    -- Автоматичне перехоплення хоста, якщо нам передали лідера під час активної сесії
    local isLeader = IsRaidLeader() or IsPartyLeader()
    if self.sessionActive and currentlyInGroup and isLeader then
        local localName = self:GetLocalPlayerName()
        if self.sessionHost ~= localName then
            self.sessionHost = localName
            self.sessionLocked = self.locked
            self:Print(self.L.PRINT_RL_TRANSFERRED)
            
            -- Повідомляємо рейд, що ми тепер новий хост
            if self.SendAddonMsg then
                self:SendAddonMsg("S|" .. localName, "RAID")
                self:SendAddonMsg("L|" .. (self.locked and "1" or "0"), "RAID")
            end
            
            -- Оновлюємо UI, щоб розблокувати адмін-панель
            if self.RefreshSessionUI then self:RefreshSessionUI() end
        end
    end
    
    -- Перевірка чи Хост онлайн і в групі (якщо ми клієнт)
    if self.sessionActive and not self:IsSessionHost() and self.sessionHost then
        local hostOnline = false
        local hostInGroup = false
        
        if GetNumRaidMembers() > 0 then
            for i = 1, GetNumRaidMembers() do
                local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
                if name then name = self:StripRealm(name) end
                if name == self.sessionHost then
                    hostInGroup = true
                    hostOnline = online
                    break
                end
            end
        elseif GetNumPartyMembers() > 0 then
            for i = 1, GetNumPartyMembers() do
                local name = GetUnitName("party" .. i, true)
                if name then name = self:StripRealm(name) end
                if name == self.sessionHost then
                    hostInGroup = true
                    hostOnline = UnitIsConnected("party" .. i)
                    break
                end
            end
        end
        
        if not hostInGroup or not hostOnline then
            self:Print(format(self.L.PRINT_HOST_LEFT, self.sessionHost, not hostInGroup and "покинув групу" or "вийшов з гри"))
            self.sessionActive = false
            self.sessionLocked = false
            self:RefreshSessionUI()
        end
    end

    -- Перевірка Ко-хостів: якщо хтось втратив права асистента, видаляємо його з ко-хостів
    if self.sessionActive and self:IsSessionHost() and self.db.coHosts then
        local changed = false
        for name, active in pairs(self.db.coHosts) do
            if active then
                local found = false
                for _, m in ipairs(self:GetRaidMembers()) do
                    if m.name == name then
                        if m.rank and m.rank > 0 then
                            found = true
                        end
                        break
                    end
                end
                if not found then
                    self.db.coHosts[name] = false
                    changed = true
                    self:Print(format(self.L.PRINT_COHOST_DEMOTED, name))
                end
            end
        end
        if changed then
            self:BroadcastCoHosts()
            if self.RefreshSessionUI then self:RefreshSessionUI() end
        end
    end

    -- Оновлення панелі керування при зміні складу рейду
    if self.UpdateDashboard    then self:UpdateDashboard()    end
    if self.UpdateAdminReadOnly then self:UpdateAdminReadOnly() end
end

function SR:GetRoleSortWeight(playerName, rank)
    local role = self:GetPlayerRole(playerName)
    if rank == 2 or role == "RL" then return 1 end
    if role == "TANK" then return 2 end
    if role == "HEAL" then return 3 end
    if role == "DPS"  then return 4 end
    return 5
end

--- Повертає відсортовану таблицю поточних учасників рейду/групи.
function SR:GetRaidMembers()
    local members = {}
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do
            local name, rank, _, level, _, fileName, _, online, _, role = GetRaidRosterInfo(i)
            if name then
                members[#members + 1] = {
                    name     = self:StripRealm(name),
                    rank     = rank,
                    class    = fileName,
                    online   = online,
                    level    = level,
                    raidRole = role,
                }
            end
        end
    else
        local pName = UnitName("player")
        if pName then
            local _, classFileName = UnitClass("player")
            members[1] = {
                name = pName,
                rank = IsPartyLeader() and 2 or (GetNumPartyMembers() == 0 and 2 or 0),
                class = classFileName,
                online = true,
                level = UnitLevel("player"),
                raidRole = "NONE"
            }
            for i = 1, GetNumPartyMembers() do
                local unit = "party"..i
                if UnitExists(unit) then
                    local _, cFile = UnitClass(unit)
                    members[#members + 1] = {
                        name = UnitName(unit),
                        rank = 0,
                        class = cFile,
                        online = UnitIsConnected(unit),
                        level = UnitLevel(unit),
                        raidRole = "NONE"
                    }
                end
            end
        end
    end

    table.sort(members, function(a, b)
        local wa = SR:GetRoleSortWeight(a.name, a.rank)
        local wb = SR:GetRoleSortWeight(b.name, b.rank)
        if wa ~= wb then return wa < wb end
        return a.name < b.name
    end)
    return members
end

function SR:IsInRaid(playerName)
    if not playerName then return false end
    playerName = self:StripRealm(playerName)
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local rName = GetRaidRosterInfo(i)
            if rName and self:StripRealm(rName) == playerName then return true end
        end
        return false
    end

    -- Рейд не сформовано — рахуємо паті/соло гравця членом групи так само,
    -- як це вже робить GetRaidMembers(), інакше реєстрація SR (яка спирається
    -- на IsInRaid) ніколи не проходить для звичайної паті на 5 осіб.
    if playerName == self:GetLocalPlayerName() then return true end
    for i = 1, GetNumPartyMembers() do
        local name = GetUnitName("party" .. i, true)
        if name and self:StripRealm(name) == playerName then return true end
    end
    return false
end

function SR:IsAdmin()
    if GetNumRaidMembers() > 0 then
        if IsRaidLeader() then return true end
        if IsRaidOfficer and IsRaidOfficer() then return true end
        for i = 1, GetNumRaidMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if name and self:StripRealm(name) == self:GetLocalPlayerName() then
                return (rank or 0) > 0
            end
        end
        return false
    elseif GetNumPartyMembers() > 0 then
        return IsPartyLeader()
    end
    return true -- Для тестування соло поза групою
end

function SR:IsSessionLeader()
    if GetNumRaidMembers() > 0 then
        return IsRaidLeader()
    elseif GetNumPartyMembers() > 0 then
        return IsPartyLeader()
    end
    return true
end

--------------------------------------------------------------
-- 8. КЕРУВАННЯ РОЛЯМИ
--------------------------------------------------------------
function SR:GetPlayerRole(name)
    if not name or name == "" then return "DPS" end
    if self.StripRealm then name = self:StripRealm(name) end
    if self.db and self.db.roles and self.db.roles[name] then
        return self.db.roles[name]
    end
    return "DPS"
end

function SR:SetPlayerRole(name, role)
    if not name or name == "" then return end
    if self.StripRealm then name = self:StripRealm(name) end
    if not self.ROLE_LABELS[role] then role = "DPS" end
    if self.sessionActive and not self:IsSessionHost() then
        if self:CanEditSession() then
            self:SendAddonMsg("V|" .. name .. "|" .. role, "WHISPER", self.sessionHost)
            self:Print(self.L.PRINT_ROLE_REQUEST_SENT)
        end
        return
    end
    self.db.roles[name] = role
    if self.UpdateDashboard then self:UpdateDashboard() end
    if self.UpdateLedger   then self:UpdateLedger()   end
    if self.BroadcastPlayerSync then self:BroadcastPlayerSync(name) end
end
function SR:AutoDetectRole(info)
    if info.raidRole == "MAINTANK"   then return "TANK" end
    if info.rank == 2                then return "RL"   end
    return nil  -- надійно визначити неможливо
end

--------------------------------------------------------------
-- 9. РОЗРАХУНОК ЛІМІТІВ SR  (v2: режими + перевизначення)
--------------------------------------------------------------

--- Повертає дійсний ліміт SR для гравця.
-- Спочатку перевіряє персональні перевизначення, потім спирається на роль/режим/підземелля.
function SR:GetSRLimit(name)
    if not name or name == "" then return 3 end
    if self.StripRealm then name = self:StripRealm(name) end
    local override = self.db and self.db.playerOverrides and self.db.playerOverrides[name]
    if override and override > 0 then
        return override
    end

    local role    = self:GetPlayerRole(name)
    local inst    = (self.db and self.db.instance) or "ICC"
    local mode    = (self.db and self.db.srMode) or "classic"
    local modeDef = self.SR_MODE_DEFS[mode]

    if modeDef and modeDef[inst] and modeDef[inst][role] then
        return modeDef[inst][role]
    end
    return 3  -- безпечне резервне значення
end

--- Повертає "базовий" ліміт (без перевизначень) для відображення.
function SR:GetBaseSRLimit(name)
    if not name or name == "" then return 3 end
    if self.StripRealm then name = self:StripRealm(name) end
    local role    = self:GetPlayerRole(name)
    local inst    = (self.db and self.db.instance) or "ICC"
    local mode    = (self.db and self.db.srMode) or "classic"
    local modeDef = self.SR_MODE_DEFS[mode]
    if modeDef and modeDef[inst] and modeDef[inst][role] then
        return modeDef[inst][role]
    end
    return 3
end

function SR:GetUsedSRCount(name)
    if not name or name == "" then return 0 end
    if self.StripRealm then name = self:StripRealm(name) end
    local list = self.db and self.db.reserves and self.db.reserves[name]
    if not list then return 0 end
    local t = 0
    for _, e in ipairs(list) do t = t + (e.count or 1) end
    return t
end

function SR:GetRemainingSR(name)
    if not name or name == "" then return 0 end
    if self.StripRealm then name = self:StripRealm(name) end
    return math.max(0, self:GetSRLimit(name) - self:GetUsedSRCount(name))
end

--------------------------------------------------------------
-- 10. ПЕРСОНАЛЬНІ ПЕРЕВИЗНАЧЕННЯ  (v2)
--------------------------------------------------------------

--- Встановлює спеціальний ліміт SR для певного гравця (наприклад, для тих, хто приєднався пізніше).
-- Передайте nil або 0, щоб скасувати перевизначення.
function SR:SetPlayerOverride(name, maxSRs)
    if not name or name == "" then return end
    if self.StripRealm then name = self:StripRealm(name) end
    maxSRs = tonumber(maxSRs)
    if self.sessionActive and not self:IsSessionHost() then
        if self:CanEditSession() then
            self:SendAddonMsg("U|" .. name .. "|" .. (maxSRs or 0), "WHISPER", self.sessionHost)
            self:Print(self.L.PRINT_LIMIT_REQUEST_SENT)
        end
        return
    end
    if maxSRs and maxSRs > 0 then
        self.db.playerOverrides[name] = maxSRs
        self:Print(format(self.L.PRINT_LIMIT_CHANGED, name, maxSRs))
    else
        self.db.playerOverrides[name] = nil
        self:Print(format(self.L.PRINT_LIMIT_RESET, name))
    end
    if self.UpdateDashboard then self:UpdateDashboard() end
    if self.UpdateLedger    then self:UpdateLedger()    end
    
    if self.sessionActive and self:IsSessionHost() then
        self:SendAddonMsg("P|" .. name .. "|" .. (maxSRs or 0), "RAID")
    end
end

function SR:GetPlayerOverride(name)
    if not name or name == "" then return nil end
    if self.StripRealm then name = self:StripRealm(name) end
    return self.db and self.db.playerOverrides and self.db.playerOverrides[name]
end

function SR:HasOverride(name)
    if not name or name == "" then return false end
    if self.StripRealm then name = self:StripRealm(name) end
    return self.db and self.db.playerOverrides and self.db.playerOverrides[name] ~= nil
end

--------------------------------------------------------------
-- 11. КЕРУВАННЯ ДАНИМИ SR
--------------------------------------------------------------

--- Реєструє 'count' кількість SR на 'itemLink' для гравця 'playerName'.
-- @return успішність (bool), повідомлення про помилку (string|nil)
function SR:AddSR(playerName, itemLink, count, isSet)
    if not playerName or playerName == "" then
        return false, "Невідомий гравець."
    end
    if self.StripRealm then playerName = self:StripRealm(playerName) end
    count = math.floor(tonumber(count) or 1)
    if count < 1 then count = 1 end

    if self.sessionActive and not self:IsSessionHost() then
        return false, "Сесію створено гравцем " .. (self.sessionHost or "кимсь іншим") .. "."
    end

    -- Ліміти вже перевірені в ProcessSRRegistration


    local itemID = self:GetItemIDFromLink(itemLink)
    if not itemID then
        return false, "Неправильний лінк на предмет."
    end

    local currentInst = self.db.instance or "ICC"
    if self.IsValidItemForInstance and not self:IsValidItemForInstance(itemID, currentInst) then
        return false, "Цей предмет не випадає у вибраному підземеллі (" .. (self.INSTANCE_LABELS[currentInst] or currentInst) .. ")."
    end

    -- Надання переваги чистому закешованому лінку, якщо він доступний
    self:QueueItemCache(itemID)
    local _, cleanLink = GetItemInfo(itemID)
    if cleanLink then itemLink = cleanLink end

    -- Ініціалізація таблиці для цього гравця
    if not self.db.reserves[playerName] then
        self.db.reserves[playerName] = {}
    end

    -- Об'єднання з існуючим записом для того ж предмета (або його еквівалента), або створення нового
    local eq = self.GetEquivalentItemIDs and self:GetEquivalentItemIDs(itemID) or { [itemID] = true }
    local found = false
    for _, entry in ipairs(self.db.reserves[playerName]) do
        if eq[entry.itemID] then
            if isSet then
                entry.count = count
            else
                entry.count = (entry.count or 1) + count
            end
            entry.itemLink = itemLink
            entry.itemID   = itemID
            found = true
            break
        end
    end
    if not found then
        self.db.reserves[playerName][#self.db.reserves[playerName] + 1] = {
            itemLink = itemLink,
            itemID   = itemID,
            count    = count,
        }
    end

    if self.RefreshSessionUI then self:RefreshSessionUI() end
    if self.BroadcastPlayerSync then self:BroadcastPlayerSync(playerName) end
    return true, nil
end

function SR:CanEditPlayerSR(playerName)
    if not playerName or playerName == "" then return false end
    if self.StripRealm then playerName = self:StripRealm(playerName) end
    if self:CanEditSession() then return true end
    if playerName == self:GetLocalPlayerName() then
        if self.locked or self.sessionLocked then return false end
        return true
    end
    return false
end

function SR:RemoveSR(playerName, itemID)
    if not playerName or playerName == "" then return false end
    if self.StripRealm then playerName = self:StripRealm(playerName) end
    if not itemID then return false end
    local cleanID = tonumber(itemID) or (self.GetItemIDFromLink and self:GetItemIDFromLink(itemID))
    if not cleanID then return false end

    local list = self.db.reserves[playerName]
    if not list then return false end
    
    local eq = self.GetEquivalentItemIDs and self:GetEquivalentItemIDs(cleanID) or { [cleanID] = true }
    
    for i, entry in ipairs(list) do
        if entry.itemID == cleanID or eq[entry.itemID] then
            table.remove(list, i)
            if #list == 0 then
                self.db.reserves[playerName] = nil
            end
            if self:IsSessionHost() or (self:IsSessionLeader() and not self.sessionActive) then
                self:BroadcastPlayerSync(playerName)
            end
            if self.RefreshSessionUI then self:RefreshSessionUI() end
            return true
        end
    end
    return false
end

function SR:ClearPlayerSR(playerName)
    if not playerName or playerName == "" then return end
    if self.StripRealm then playerName = self:StripRealm(playerName) end
    if self.sessionActive and not self:IsSessionHost() then return end
    self.db.reserves[playerName] = nil
    if self:IsSessionHost() or (self:IsSessionLeader() and not self.sessionActive) then
        self:BroadcastPlayerSync(playerName)
    end
    if self.RefreshSessionUI then self:RefreshSessionUI() end
end

function SR:ResetAllSR()
    if self.sessionActive and not self:IsSessionHost() then return end
    self.db.reserves = {}
    self:Print(self.L.PRINT_ALL_CLEARED)
    if self.UpdateLedger    then self:UpdateLedger()    end
    if self.UpdateDashboard then self:UpdateDashboard() end
    if self:IsSessionHost() or (self:IsSessionLeader() and not self.sessionActive) then
        self:SendAddonMsg("W", "RAID")
    end
end

--------------------------------------------------------------
-- 11.5 WISHLIST MANAGEMENT
--------------------------------------------------------------

function SR:ToggleWishlistItem(itemID)
    local pName = self:GetLocalPlayerName()
    if not self.db.wishlists[pName] then self.db.wishlists[pName] = {} end
    
    if self.db.wishlists[pName][itemID] then
        self.db.wishlists[pName][itemID] = nil
    else
        self.db.wishlists[pName][itemID] = true
    end
end

function SR:IsInWishlist(itemID)
    local pName = self:GetLocalPlayerName()
    if not self.db.wishlists[pName] then return false end
    return self.db.wishlists[pName][itemID] or false
end

function SR:GetWishlistItems()
    local pName = self:GetLocalPlayerName()
    local items = {}
    if self.db.wishlists[pName] then
        for id in pairs(self.db.wishlists[pName]) do
            table.insert(items, id)
        end
    end
    table.sort(items)
    return items
end

--------------------------------------------------------------
-- 12. КЕШ ПРЕДМЕТІВ ТА ЗАПИТИ ДО СЕРВЕРА  (WotLK 3.3.5 — немає GET_ITEM_INFO_RECEIVED)
--------------------------------------------------------------

function SR:InitItemCache()
    if self.itemQueryFrame then return end

    self.pendingItems      = {}   -- [itemID] = attemptCount
    self.itemQueryFrame    = CreateFrame("Frame")
    self.itemQueryFrame:Hide()

    -- Прихована підказка — найнадійніший спосіб викликати запит до сервера у WotLK
    self.queryTooltip = CreateFrame("GameTooltip", "SRQueryTooltip", UIParent, "GameTooltipTemplate")
    self.queryTooltip:SetOwner(UIParent, "ANCHOR_NONE")

    self.itemQueryFrame:SetScript("OnUpdate", function(frame, elapsed)
        frame.elapsed = (frame.elapsed or 0) + elapsed
        if frame.elapsed < 0.25 then return end
        frame.elapsed = 0

        if not next(SR.pendingItems) then
            frame:Hide()
            return
        end

        local anyResolved = false
        for itemID, attempts in pairs(SR.pendingItems) do
            if GetItemInfo(itemID) then
                SR.pendingItems[itemID] = nil
                anyResolved = true
            else
                attempts = attempts + 1
                if attempts > 40 then
                    SR.pendingItems[itemID] = nil
                else
                    SR.pendingItems[itemID] = attempts
                    SR:ForceQueryItem(itemID)
                end
            end
        end

        if anyResolved then
            SR:OnItemsCached()
        end
    end)
end

--- Запит до клієнта / сервера WoW на завантаження предмета в кеш.
function SR:ForceQueryItem(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end

    if GetItemInfo(itemID) then return true end

    -- Формат гіперпосилання (працює на деяких клієнтах 3.3.5)
    GetItemInfo("item:" .. itemID .. ":0:0:0:0:0:0:0")

    if GetItemInfo(itemID) then return true end

    -- Прихована підказка — найнадійніший спосіб викликати запит до сервера у WotLK
    if self.queryTooltip then
        self.queryTooltip:ClearLines()
        self.queryTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        self.queryTooltip:SetHyperlink("item:" .. itemID .. ":0:0:0:0:0:0:0")
        self.queryTooltip:Hide()
    end

    return GetItemInfo(itemID) ~= nil
end

--- Додавання одного або декількох ID предметів у чергу для фонового опитування кешу.
function SR:QueueItemCache(itemID)
    if not itemID then return end
    itemID = tonumber(itemID)
    if not itemID then return end
    if GetItemInfo(itemID) then return end

    if not self.pendingItems[itemID] then
        self.pendingItems[itemID] = 0
        self:ForceQueryItem(itemID)
    end
    self.itemQueryFrame:Show()
end

function SR:QueueItemCacheList(ids)
    if not ids then return end
    for _, id in ipairs(ids) do
        self:QueueItemCache(id)
    end
end

--- Додавання всіх ID предметів, згаданих у резервах і таблицях здобичі, у чергу.
function SR:QueueAllKnownItems()
    local ids = {}

    for _, list in pairs(self.db.reserves or {}) do
        for _, e in ipairs(list) do
            if e.itemID then ids[e.itemID] = true end
        end
    end

    if self.GetCurrentLootData and self.GetBossLoot then
        local data = self:GetCurrentLootData()
        if data then
            for _, boss in ipairs(data) do
                local loot = self:GetBossLoot(boss)
                if loot then
                    for _, id in ipairs(loot) do
                        ids[id] = true
                    end
                end
            end
        end
    end

    for id in pairs(ids) do
        self:QueueItemCache(id)
    end
end

--- Повертає найкращий доступний лінк на предмет (закешований, збережений або заглушка для запиту).
function SR:GetSafeItemLink(itemID, existingLink)
    itemID = tonumber(itemID)
    if existingLink and existingLink:match("%[.-%]|h") and not existingLink:match("Item #") then
        return existingLink
    end
    if itemID then
        local _, link = GetItemInfo(itemID)
        if link then return link end
        return "item:" .. itemID .. ":0:0:0:0:0:0:0"
    end
    return existingLink
end

--- Оновлення збережених лінків резервів після завершення завантаження предметів.
function SR:RefreshReserveItemLinks()
    for _, list in pairs(self.db.reserves or {}) do
        for _, e in ipairs(list) do
            if e.itemID then
                local _, link = GetItemInfo(e.itemID)
                if link then e.itemLink = link end
            end
        end
    end
end

--- Викликається, коли сервер повертає дані принаймні про один предмет з черги.
function SR:OnItemsCached()
    self:RefreshReserveItemLinks()

    if self.UpdateLedger then self:UpdateLedger() end
    if self.UpdateLootBrowserItems then self:UpdateLootBrowserItems() end
    if self.UpdateLootSession then self:UpdateLootSession() end
    if self.UpdateDashboard then self:UpdateDashboard() end
end

function SR:GetItemIDFromLink(link)
    if not link then return nil end
    if type(link) == "number" then return link end
    local id = link:match("item:(%d+)")
    if id then return tonumber(id) end
    if link:match("^%d+$") then return tonumber(link) end
    return nil
end

--- Повертає відсортований список гравців, які зарезервували заданий itemID.
-- Кожен запис: { name, count, role, itemLink }
function SR:GetPlayersWithSR(itemID)
    if not itemID then return {} end
    itemID = tonumber(itemID) or self:GetItemIDFromLink(itemID)
    if not itemID then return {} end
    local eq = self.GetEquivalentItemIDs and self:GetEquivalentItemIDs(itemID) or { [itemID] = true }
    local out = {}
    for pName, list in pairs(self.db.reserves) do
        if self:IsInRaid(pName) then
            for _, e in ipairs(list) do
                if eq[e.itemID] then
                    out[#out + 1] = {
                        name     = pName,
                        count    = e.count or 1,
                        role     = self:GetPlayerRole(pName),
                        itemLink = e.itemLink,
                    }
                    break
                end
            end
        end
    end
    local ranks = {}
    for _, m in ipairs(self:GetRaidMembers()) do
        ranks[m.name] = m.rank
    end

    table.sort(out, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        local wa = SR:GetRoleSortWeight(a.name, ranks[a.name] or 0)
        local wb = SR:GetRoleSortWeight(b.name, ranks[b.name] or 0)
        if wa ~= wb then return wa < wb end
        return a.name < b.name
    end)
    return out
end

--------------------------------------------------------------
-- 13. АНОНС УСІХ SR У РЕЙД
--------------------------------------------------------------
function SR:AnnouncePlayer(pName, chatType)
    local used = self:GetUsedSRCount(pName)
    local limit = self:GetSRLimit(pName)
    local list = self.db.reserves[pName] or {}
    
    local missing = limit - used
    local missingStr = ""
    if missing > 0 then
        missingStr = " (бракує " .. missing .. ")"
    end

    if used == 0 then
        SendChatMessage(format(self.L.ANNOUNCE_PLAYER_NO_SR, pName, missingStr), chatType)
        return
    end

    -- Відправляємо заголовок гравця
    SendChatMessage(format(self.L.ANNOUNCE_PLAYER_HAS_SR, pName, missingStr), chatType)
    
    -- Кожен предмет окремим повідомленням, щоб обійти ліміт у 255 символів
    for _, e in ipairs(list) do
        local link = e.itemLink or ("[Item " .. e.itemID .. "]")
        local countStr = (e.count and e.count > 1) and (" x" .. e.count) or ""
        SendChatMessage(" - " .. link .. countStr, chatType)
    end
end

function SR:GetAnnouncementChannel(preferWarning)
    if GetNumRaidMembers() > 0 then
        if preferWarning and self:IsAdmin() then
            return "RAID_WARNING"
        end
        return "RAID"
    elseif GetNumPartyMembers() > 0 then
        return "PARTY"
    else
        return "SAY"
    end
end

function SR:AnnounceAllSR()
    local chatType = self:GetAnnouncementChannel(false)
    local inst = self.db.instance or "ICC"
    SendChatMessage(format(self.L.ANNOUNCE_ALL_HEADER, (self.INSTANCE_LABELS[inst] or inst)), chatType)
    
    local names = {}
    local members = self:GetRaidMembers()
    for _, m in ipairs(members) do
        names[#names+1] = m.name
    end
    if #names == 0 then names = {self:GetLocalPlayerName()} end
    table.sort(names)
    
    local count = 0
    for _, pName in ipairs(names) do
        local used = self:GetUsedSRCount(pName)
        if used > 0 then
            self:AnnouncePlayer(pName, chatType)
            count = count + 1
        end
    end
    if count == 0 then
        SendChatMessage(self.L.ANNOUNCE_ALL_EMPTY, chatType)
    end
end

function SR:AnnounceMissingSR()
    local chatType = self:GetAnnouncementChannel(false)
    SendChatMessage(self.L.ANNOUNCE_MISSING_HEADER, chatType)
    
    local names = {}
    local members = self:GetRaidMembers()
    for _, m in ipairs(members) do
        names[#names+1] = m.name
    end
    if #names == 0 then names = {self:GetLocalPlayerName()} end
    table.sort(names)
    
    local count = 0
    for _, pName in ipairs(names) do
        local used = self:GetUsedSRCount(pName)
        local limit = self:GetSRLimit(pName)
        if used < limit then
            self:AnnouncePlayer(pName, chatType)
            count = count + 1
        end
    end
    if count == 0 then
        SendChatMessage(self.L.ANNOUNCE_MISSING_NONE, chatType)
    end
end

function SR:AnnouncePlayerSR(pName)
    local chatType = self:GetAnnouncementChannel(false)
    self:AnnouncePlayer(pName, chatType)
end

function SR:AnnounceBossItems(bossName, items)
    local chatType = self:GetAnnouncementChannel(false)
    if not items or #items == 0 then
        SendChatMessage(format(self.L.ANNOUNCE_BOSS_EMPTY, bossName), chatType)
        return
    end

    SendChatMessage(format(self.L.ANNOUNCE_BOSS_HEADER, bossName), chatType)
    for _, e in ipairs(items) do
        local link = e.itemLink or ("[Item " .. (e.itemID or "?") .. "]")
        local countStr = (e.count and e.count > 1) and (" (x" .. e.count .. ")") or ""
        
        local playersList = {}
        for _, res in ipairs(e.reservers or {}) do
            if type(res) == "table" then
                if res.count > 1 then
                    table.insert(playersList, res.name .. " x" .. res.count)
                else
                    table.insert(playersList, res.name)
                end
            else
                table.insert(playersList, tostring(res))
            end
        end

        local prefix = " - " .. link .. countStr .. ": "
        if #playersList == 0 then
            SendChatMessage(prefix .. "немає", chatType)
        else
            local line = prefix
            for i, pStr in ipairs(playersList) do
                local sep = (i == 1) and "" or ", "
                if #line + #sep + #pStr > 220 then
                    SendChatMessage(line, chatType)
                    line = "   " .. pStr
                else
                    line = line .. sep .. pStr
                end
            end
            if line ~= "" then
                SendChatMessage(line, chatType)
            end
        end
    end
end

--------------------------------------------------------------
-- 14. ЗАГАЛЬНІ УТИЛІТИ
--------------------------------------------------------------
function SR:StripRealm(name)
    if not name then return nil end
    local base = name:match("^([^%-]+)")
    return base or name
end

function SR:CopyTable(src)
    if type(src) ~= "table" then return src end
    local t = {}
    for k, v in pairs(src) do t[k] = self:CopyTable(v) end
    return t
end

function SR:GetClassColor(class)
    return self.CLASS_COLORS[class] or { r = 0.5, g = 0.5, b = 0.5 }
end

function SR:ColorText(text, r, g, b)
    return format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end

function SR:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33bbff[SoftRoll]|r " .. tostring(msg))
end

--------------------------------------------------------------
-- 15. ТРЕКЕР РОЛІВ
--------------------------------------------------------------
function SR:ProcessRoll(pName, rollVal)
    if not self.activeRollItem then return end

    -- Перевірка чи гравець має SR на цей предмет
    local players = self:GetPlayersWithSR(self.activeRollItem)
    local pData = nil
    for _, p in ipairs(players) do
        if p.name == pName then
            pData = p
            break
        end
    end

    if not self.activeRolls[pName] then
        self.activeRolls[pName] = {}
    end

    local allowedRolls = pData and pData.count or 1
    if #self.activeRolls[pName] < allowedRolls then
        table.insert(self.activeRolls[pName], rollVal)
        if self.UpdateLootSession then self:UpdateLootSession() end
    end
end

function SR:EndLootRoll()
    if not self.activeRollItem then return end

    local chatType = self:GetAnnouncementChannel(false)
    local srPlayers = self:GetPlayersWithSR(self.activeRollItem)
    local hasSR = (#srPlayers > 0)

    local eligibleNames = {}
    if hasSR then
        for _, p in ipairs(srPlayers) do
            eligibleNames[p.name] = true
        end
    end

    local bestRoll = -1
    local winners = {}

    for pName, rolls in pairs(self.activeRolls) do
        if not hasSR or eligibleNames[pName] then
            local pBest = -1
            for _, r in ipairs(rolls) do
                if r > pBest then pBest = r end
            end
            if pBest > bestRoll then
                bestRoll = pBest
                winners = { pName }
            elseif pBest == bestRoll and bestRoll > -1 then
                table.insert(winners, pName)
            end
        end
    end

    if bestRoll == -1 then
        SendChatMessage(self.L.ROLL_NO_ROLLS, chatType)
    else
        local winnerNames = table.concat(winners, ", ")
        if #winners > 1 then
            SendChatMessage(format(self.L.ROLL_TIE, winnerNames, bestRoll), chatType)
        else
            SendChatMessage(format(self.L.ROLL_WINNER, winnerNames, bestRoll), chatType)
        end
    end

    self.lastRollItem = self.activeRollItem
    self.lastRolls = self.activeRolls
    self.activeRollItem = nil
    self.activeRolls = {}
    if self.UpdateLootSession then self:UpdateLootSession() end
end

--------------------------------------------------------------
-- КЕРУВАННЯ ПРЕДМЕТОМ РОЗДАЧІ ТА РЕЖИМАМИ СЕСІЇ
--------------------------------------------------------------

--- Перемикає режим відображення роздачі здобичі ("bag" - сканер сумок, "roll" - активний розрол)
function SR:SetLootSessionMode(mode)
    self.lootSessionMode = mode
    if mode == "bag" then
        if self.lootBagPanel then self.lootBagPanel:Show() end
        if self.lootRollPanel then self.lootRollPanel:Hide() end
        if self.btnBagLootTab and self.btnBagLootTab.bg then
            self.btnBagLootTab.bg:SetVertexColor(0.18, 0.24, 0.38, 1)
            self.btnBagLootTab.label:SetTextColor(1, 1, 1)
        end
        if self.btnActiveRollTab and self.btnActiveRollTab.bg then
            self.btnActiveRollTab.bg:SetVertexColor(0.10, 0.10, 0.16, 0.9)
            self.btnActiveRollTab.label:SetTextColor(0.55, 0.55, 0.60)
        end
        if self.RefreshBagLoot then self:RefreshBagLoot() end
    else
        if self.lootBagPanel then self.lootBagPanel:Hide() end
        if self.lootRollPanel then self.lootRollPanel:Show() end
        if self.btnBagLootTab and self.btnBagLootTab.bg then
            self.btnBagLootTab.bg:SetVertexColor(0.10, 0.10, 0.16, 0.9)
            self.btnBagLootTab.label:SetTextColor(0.55, 0.55, 0.60)
        end
        if self.btnActiveRollTab and self.btnActiveRollTab.bg then
            self.btnActiveRollTab.bg:SetVertexColor(0.18, 0.24, 0.38, 1)
            self.btnActiveRollTab.label:SetTextColor(1, 1, 1)
        end
        if self.UpdateLootSession then self:UpdateLootSession() end
    end
end

--- Оновлює стан сесії здобичі (за замовчуванням показує сумки, або активний розрол)
function SR:UpdateLootSession()
    if not self.lootSessionMode or (not self.activeRollItem and self.lootSessionMode ~= "roll") then
        self:SetLootSessionMode("bag")
        return
    end

    if self.lootSessionMode == "bag" then
        if self.RefreshBagLoot then self:RefreshBagLoot() end
        return
    end

    if self.UpdateLootRollUI then
        self:UpdateLootRollUI()
    end
end

--- Встановлює поточний предмет для розролу
function SR:SetLootItem(input)
    if not input or input == "" then return end

    -- Спроба отримати валідний лінк на предмет з рядка
    local link = input:match("(|c%x+|Hitem:.-%|h%[.-%]|h|r)")

    -- Якщо користувач ввів чистий ID, пробуємо знайти предмет
    if not link then
        local rawID = input:match("(%d+)")
        if rawID and GetItemInfo then
            local _, l = GetItemInfo(tonumber(rawID))
            if l then link = l end
        end
    end

    if not link then
        if self.Print and self.L and self.L.PRINT_ITEM_NOT_FOUND_SHIFT then
            self:Print(self.L.PRINT_ITEM_NOT_FOUND_SHIFT)
        end
        return
    end

    local itemID = self:GetItemIDFromLink(link)
    if not itemID then return end

    -- Якщо змінився предмет, очищуємо активні та попередні роли
    if self.activeRollItem and self.activeRollItem ~= itemID then
        self.activeRollItem = nil
        self.activeRolls = {}
    end
    self.lastRollItem = nil
    self.lastRolls = nil

    -- Кешування предмета
    self.currentLootItemID   = itemID
    self.currentLootItemLink = link

    -- Оновлення UI елементів, якщо вони існують
    if self.lootIconTex and GetItemInfo then
        local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(itemID)
        if tex then
            self.lootIconTex:SetTexture(tex)
        else
            self.lootIconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
    end
    if self.lootIconBtn then
        self.lootIconBtn.link = link
    end

    if self.lootItemLabel then
        self.lootItemLabel:SetText(string.format((self.L and self.L.UI_CURRENT_ITEM) or "Поточний предмет: %s", link))
    end

    if self.lootItemEditBox then
        self.lootItemEditBox:SetText(link)
        self.lootItemEditBox:ClearFocus()
    end

    -- Автоматично перемикаємо на активний розрол
    self:SetLootSessionMode("roll")
end

--- Очищує поточний предмет розролу
function SR:ClearLootItem()
    self.currentLootItemID   = nil
    self.currentLootItemLink = nil
    self.activeRollItem      = nil
    self.activeRolls         = {}
    self.lastRollItem        = nil
    self.lastRolls           = nil

    if self.lootIconTex then
        self.lootIconTex:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    end
    if self.lootIconBtn then
        self.lootIconBtn.link = nil
    end
    if self.lootItemLabel then
        self.lootItemLabel:SetText("")
    end
    if self.lootItemEditBox then
        self.lootItemEditBox:SetText("")
    end

    if self.UpdateLootSession then
        self:UpdateLootSession()
    end
end

--------------------------------------------------------------
-- 16. СКАНЕР СУМОК ТА ТАЙМЕР ПЕРЕДАЧІ
--------------------------------------------------------------

local scanTip = nil
local function GetScanTooltip()
    if not scanTip and CreateFrame then
        scanTip = CreateFrame("GameTooltip", "SRBagScanTooltip", UIParent, "GameTooltipTemplate")
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return scanTip
end

--- Зчитує залишок 2-годинного таймера передачі предмету в сумці через тултіп.
-- Також перевіряє, чи предмет є персональним (soulbound).
-- @return totalMinutes (number|nil), formattedText (string|nil), isSoulbound (boolean)
function SR:GetContainerItemTradeTime(bag, slot)
    local tip = GetScanTooltip()
    if not tip or not tip.SetBagItem then return nil, nil, false end

    tip:ClearLines()
    tip:SetBagItem(bag, slot)
    local numLines = tip:NumLines() or 0

    local isSoulbound = false
    local tradeMins = nil
    local tradeFormatted = nil
    local boundText = _G.ITEM_SOULBOUND

    for i = 1, numLines do
        local lineObj = _G["SRBagScanTooltipTextLeft" .. i]
        if lineObj and lineObj.GetText then
            local text = lineObj:GetText()
            if text and text ~= "" then
                -- Перевірка на персональність предмету (Soulbound)
                if (boundText and text:find(boundText, 1, true)) or text:find("Soulbound", 1, true) then
                    isSoulbound = true
                else
                    local lower = text:lower()
                    if lower:find("soulbound") or lower:find("персональн") or lower:find("seelengebunden") or lower:find("lié") or lower:find("ligado") then
                        isSoulbound = true
                    end
                end

                local isTradeLine = false
                if _G.BIND_TRADE_TIME_REMAINING then
                    local pat = _G.BIND_TRADE_TIME_REMAINING:gsub("%%s", ".*")
                    if text:match(pat) then isTradeLine = true end
                end
                if not isTradeLine then
                    local lower = text:lower()
                    if lower:find("trade this item") or lower:find("передать этот предмет") or lower:find("передати цей предмет") or lower:find("handeln") or lower:find("échanger") then
                        isTradeLine = true
                    end
                end

                if isTradeLine then
                    local h = text:match("(%d+)%s*[hH]")
                           or text:match("(%d+)%s*год")
                           or text:match("(%d+)%s*ч")
                           or text:match("(%d+)%s*Ч")
                           or text:match("(%d+)%s*Std")

                    local m = text:match("(%d+)%s*[mM]")
                           or text:match("(%d+)%s*хв")
                           or text:match("(%d+)%s*мин")
                           or text:match("(%d+)%s*Min")

                    local s = text:match("(%d+)%s*[sS]")
                           or text:match("(%d+)%s*сек")
                           or text:match("(%d+)%s*Sek")

                    local hours = tonumber(h) or 0
                    local mins  = tonumber(m) or 0
                    local secs  = tonumber(s) or 0
                    local totalMins = hours * 60 + mins

                    local formatted
                    if hours > 0 then
                        formatted = string.format("%dг %02dхв", hours, mins)
                    elseif mins > 0 then
                        formatted = string.format("%d хв", mins)
                    else
                        formatted = "< 1 хв"
                    end
                    tradeMins = totalMins
                    tradeFormatted = formatted
                end
            end
        end
    end
    return tradeMins, tradeFormatted, isSoulbound
end

--- Сканує всі 5 сумок (0..4) на наявність рейд-луту та повертає відсортований список.
function SR:ScanBagsForLoot()
    if not GetContainerNumSlots then return {} end

    local items = {}
    local currentInst = self.db and self.db.instance or "ICC"

    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
            if link then
                local itemID = self:GetItemIDFromLink(link)
                if itemID then
                    local count = 1
                    local quality = 4
                    if GetContainerItemInfo then
                        local _, c, _, q = GetContainerItemInfo(bag, slot)
                        count = c or 1
                        quality = q or 4
                    end

                    local tradeMins, tradeText, isSoulbound = self:GetContainerItemTradeTime(bag, slot)
                    local srs = self:GetPlayersWithSR(itemID)
                    local srCount = srs and #srs or 0
                    local isRaidItem = (self.IsValidItemForInstance and self:IsValidItemForInstance(itemID, currentInst))

                    -- Включаємо предмет, якщо його ДІЙСНО МОЖЛИВО передати:
                    -- 1. Свіжий BoP-дроп з активним таймером передачі (tradeMins ~= nil).
                    -- 2. Неперсональний (BoE) предмет рейду або з зареєстрованими софт-ролами (not isSoulbound).
                    -- КРИТИЧНО: Якщо предмет є персональним (isSoulbound) і НЕ має таймера передачі (tradeMins == nil),
                    -- це особисте спорядження лідера (наприклад, власна Воля чи офсет у сумці).
                    -- Такий предмет передати іншим гравцям фізично неможливо, тому він виключається!
                    local shouldInclude = false
                    if tradeMins ~= nil then
                        shouldInclude = true
                    elseif not isSoulbound then
                        if (srCount > 0) or (isRaidItem and quality >= 4) then
                            shouldInclude = true
                        end
                    end

                    if shouldInclude then
                        table.insert(items, {
                            bag       = bag,
                            slot      = slot,
                            itemID    = itemID,
                            itemLink  = link,
                            count     = count,
                            quality   = quality,
                            tradeMins = tradeMins,
                            tradeText = tradeText,
                            srCount   = srCount,
                            reservers = srs,
                        })
                    end
                end
            end
        end
    end

    -- Сортування:
    -- 1. Предмети з критичним таймером (<= 30 хв) завжди нагорі!
    -- 2. Предмети з зареєстрованими SR (srCount > 0) перед предметами без софтів
    -- 3. За залишком часу передачі (найменший залишок спочатку)
    -- 4. За назвою/ID
    table.sort(items, function(a, b)
        local aCrit = (a.tradeMins and a.tradeMins <= 30) and 1 or 0
        local bCrit = (b.tradeMins and b.tradeMins <= 30) and 1 or 0
        if aCrit ~= bCrit then return aCrit > bCrit end

        local aHasSR = (a.srCount > 0) and 1 or 0
        local bHasSR = (b.srCount > 0) and 1 or 0
        if aHasSR ~= bHasSR then return aHasSR > bHasSR end

        if a.tradeMins and b.tradeMins and a.tradeMins ~= b.tradeMins then
            return a.tradeMins < b.tradeMins
        end

        return a.itemID < b.itemID
    end)

    return items
end