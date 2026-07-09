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
    end
end)

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

    self:Print("v" .. self.VERSION .. " завантажено. Введіть |cff00ff00/sr|r, щоб відкрити.")
end

--------------------------------------------------------------
-- 6. ОБРОБНИК СЛЕШ КОМАНД
--------------------------------------------------------------
function SR:SlashHandler(msg)
    msg = strtrim(msg or ""):lower()

    if msg == "reset" then
        if self.sessionActive and not self:IsSessionHost() then
            SR:Print("Лише активний хост може скидати софт-роли під час сесії.")
        else
            self:ResetAllSR()
        end
    elseif msg == "lock" then
        self.locked = true
        self:Print("Софт-роли |cffff4444ЗАБЛОКОВАНО|r — нові реєстрації не приймаються.")
    elseif msg == "unlock" then
        self.locked = false
        self:Print("Софт-роли |cff44ff44РОЗБЛОКОВАНО|r.")
    elseif msg == "announce" then
        self:AnnounceAllSR()
    elseif msg == "help" then
        SR:Print("Команди:")
        self:Print("  |cff00ff00/sr|r — Відкрити/закрити головне вікно")
        self:Print("  |cff00ff00/sr reset|r — Очистити всі софт-роли")
        self:Print("  |cff00ff00/sr lock / unlock|r — Заблокувати/розблокувати реєстрацію")
        self:Print("  |cff00ff00/sr announce|r — Опублікувати всі софти в рейдовий чат")
        self:Print("  |cff00ff00/sr help|r — Ця довідка")
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
            self:Print("Ви отримали лідера рейду. Сесію SR автоматично перенесено на вас.")
            
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
            self:Print("Хост " .. self.sessionHost .. " " .. (not hostInGroup and "покинув групу" or "вийшов з гри") .. ". Сесію призупинено.")
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
                    self:Print("Гравець " .. name .. " втратив права помічника рейду і був видалений з ко-хостів аддону.")
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
                    name     = name,
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
    for i = 1, GetNumRaidMembers() do
        if (GetRaidRosterInfo(i)) == playerName then return true end
    end
    return false
end

function SR:IsAdmin()
    if GetNumRaidMembers() > 0 then
        return IsRaidLeader() or IsRaidOfficer()
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
    if not name then return "DPS" end
    if self.db and self.db.roles and self.db.roles[name] then
        return self.db.roles[name]
    end
    return "DPS"
end

function SR:SetPlayerRole(name, role)
    if self.sessionActive and not self:IsSessionHost() then
        if self:CanEditSession() then
            self:SendAddonMsg("V|" .. name .. "|" .. role, "WHISPER", self.sessionHost)
            self:Print("Запит на зміну ролі надіслано хосту...")
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
    -- Персональне перевизначення має пріоритет
    local override = self.db.playerOverrides[name]
    if override and override > 0 then
        return override
    end

    local role    = self:GetPlayerRole(name)
    local inst    = self.db.instance or "ICC"
    local mode    = self.db.srMode or "classic"
    local modeDef = self.SR_MODE_DEFS[mode]

    if modeDef and modeDef[inst] and modeDef[inst][role] then
        return modeDef[inst][role]
    end
    return 3  -- безпечне резервне значення
end

--- Повертає "базовий" ліміт (без перевизначень) для відображення.
function SR:GetBaseSRLimit(name)
    local role    = self:GetPlayerRole(name)
    local inst    = self.db.instance or "ICC"
    local mode    = self.db.srMode or "classic"
    local modeDef = self.SR_MODE_DEFS[mode]
    if modeDef and modeDef[inst] and modeDef[inst][role] then
        return modeDef[inst][role]
    end
    return 3
end

function SR:GetUsedSRCount(name)
    local list = self.db.reserves[name]
    if not list then return 0 end
    local t = 0
    for _, e in ipairs(list) do t = t + (e.count or 1) end
    return t
end

function SR:GetRemainingSR(name)
    return self:GetSRLimit(name) - self:GetUsedSRCount(name)
end

--------------------------------------------------------------
-- 10. ПЕРСОНАЛЬНІ ПЕРЕВИЗНАЧЕННЯ  (v2)
--------------------------------------------------------------

--- Встановлює спеціальний ліміт SR для певного гравця (наприклад, для тих, хто приєднався пізніше).
-- Передайте nil або 0, щоб скасувати перевизначення.
function SR:SetPlayerOverride(name, maxSRs)
    if self.sessionActive and not self:IsSessionHost() then
        if self:CanEditSession() then
            self:SendAddonMsg("U|" .. name .. "|" .. (maxSRs or 0), "WHISPER", self.sessionHost)
            self:Print("Запит на зміну ліміту надіслано хосту...")
        end
        return
    end
    if maxSRs and maxSRs > 0 then
        self.db.playerOverrides[name] = maxSRs
        self:Print("Ліміт SR для " .. name .. " змінено на |cffffcc00x" .. maxSRs .. "|r")
    else
        self.db.playerOverrides[name] = nil
        self:Print("Ліміт SR для " .. name .. " скинуто до стандартного для ролі")
    end
    if self.UpdateDashboard then self:UpdateDashboard() end
    if self.UpdateLedger    then self:UpdateLedger()    end
    
    if self.sessionActive and self:IsSessionHost() then
        self:SendAddonMsg("P|" .. name .. "|" .. (maxSRs or 0), "RAID")
    end
end

function SR:GetPlayerOverride(name)
    return self.db.playerOverrides[name]
end

function SR:HasOverride(name)
    return self.db.playerOverrides[name] ~= nil
end

--------------------------------------------------------------
-- 11. КЕРУВАННЯ ДАНИМИ SR
--------------------------------------------------------------

--- Реєструє 'count' кількість SR на 'itemLink' для гравця 'playerName'.
-- @return успішність (bool), повідомлення про помилку (string|nil)
function SR:AddSR(playerName, itemLink, count, isSet)
    count = count or 1

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

function SR:RemoveSR(playerName, itemID)
    if self.sessionActive and not self:IsSessionHost() then return end
    local list = self.db.reserves[playerName]
    if not list then return end
    local eq = self.GetEquivalentItemIDs and self:GetEquivalentItemIDs(itemID) or { [itemID] = true }
    for i, e in ipairs(list) do
        if eq[e.itemID] then
            table.remove(list, i)
            break
        end
    end
    if self.RefreshSessionUI then self:RefreshSessionUI() end
    if self.BroadcastPlayerSync then self:BroadcastPlayerSync(playerName) end
end

function SR:CanEditPlayerSR(playerName)
    if self:CanEditSession() then return true end
    if playerName == self:GetLocalPlayerName() then
        if self.locked or self.sessionLocked then return false end
        return true
    end
    return false
end

function SR:RemoveSR(playerName, itemID)
    local list = self.db.reserves[playerName]
    if not list then return false end
    
    local eq = self.GetEquivalentItemIDs and self:GetEquivalentItemIDs(itemID) or { [itemID] = true }
    
    for i, entry in ipairs(list) do
        if entry.itemID == tonumber(itemID) or eq[entry.itemID] then
            table.remove(list, i)
            if #list == 0 then
                self.db.reserves[playerName] = nil
            end
            if self:IsSessionHost() or (self:IsSessionLeader() and not self.sessionActive) then
                self:BroadcastPlayerSync(playerName)
            end
            self:RefreshSessionUI()
            return true
        end
    end
    return false
end

function SR:ClearPlayerSR(playerName)
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
    self:Print("Всі софти успішно |cffff4444очищено|r.")
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
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

--- Повертає відсортований список гравців, які зарезервували заданий itemID.
-- Кожен запис: { name, count, role, itemLink }
function SR:GetPlayersWithSR(itemID)
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
        SendChatMessage(pName .. " — немає софтів" .. missingStr, chatType)
        return
    end

    -- Відправляємо заголовок гравця
    SendChatMessage(pName .. " — софти" .. missingStr .. ":", chatType)
    
    -- Кожен предмет окремим повідомленням, щоб обійти ліміт у 255 символів
    for _, e in ipairs(list) do
        local link = e.itemLink or ("[Item " .. e.itemID .. "]")
        local countStr = (e.count and e.count > 1) and (" x" .. e.count) or ""
        SendChatMessage(" - " .. link .. countStr, chatType)
    end
end

function SR:AnnounceAllSR()
    local chatType = (GetNumRaidMembers() > 0) and "RAID" or "SAY"
    local inst = self.db.settings and self.db.settings.instance or "ICC"
    SendChatMessage("Всі софт-роли (" .. (self.INSTANCE_LABELS[inst] or inst) .. "):", chatType)
    
    local names = {}
    for i = 1, GetNumRaidMembers() do
        local name = GetRaidRosterInfo(i)
        if name then names[#names+1] = name end
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
        SendChatMessage("Список порожній.", chatType)
    end
end

function SR:AnnounceMissingSR()
    local chatType = (GetNumRaidMembers() > 0) and "RAID" or "SAY"
    SendChatMessage("Гравці з неповними софт-ролами:", chatType)
    
    local names = {}
    for i = 1, GetNumRaidMembers() do
        local name = GetRaidRosterInfo(i)
        if name then names[#names+1] = name end
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
        SendChatMessage("Всі вибрали софти повністю.", chatType)
    end
end

function SR:AnnouncePlayerSR(pName)
    local chatType = (GetNumRaidMembers() > 0) and "RAID" or "SAY"
    self:AnnouncePlayer(pName, chatType)
end

function SR:AnnounceBossItems(bossName, items)
    local chatType = (GetNumRaidMembers() > 0) and "RAID" or "SAY"
    if not items or #items == 0 then
        SendChatMessage(bossName .. " — немає зареєстрованих софт-ролів", chatType)
        return
    end

    SendChatMessage(bossName .. " — софт-роли:", chatType)
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
        local players = table.concat(playersList, ", ")
        SendChatMessage(" - " .. link .. countStr .. ": " .. players, chatType)
    end
end

--------------------------------------------------------------
-- 14. ЗАГАЛЬНІ УТИЛІТИ
--------------------------------------------------------------
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

    local chatType = (GetNumRaidMembers() > 0) and "RAID" or "SAY"
    local bestRoll = -1
    local winners = {}

    for pName, rolls in pairs(self.activeRolls) do
        for _, r in ipairs(rolls) do
            if r > bestRoll then
                bestRoll = r
                winners = { pName }
            elseif r == bestRoll then
                table.insert(winners, pName)
            end
        end
    end

    if bestRoll == -1 then
        SendChatMessage("Рол завершено! Ніхто не кинув /roll.", chatType)
    else
        local winnerNames = table.concat(winners, ", ")
        if #winners > 1 then
            SendChatMessage("Рол завершено! Нічия між " .. winnerNames .. " (Рол: " .. bestRoll .. "). Перероліть!", chatType)
        else
            SendChatMessage("Рол завершено! Переможець: " .. winnerNames .. " (Рол: " .. bestRoll .. ")!", chatType)
        end
    end

    self.activeRollItem = nil
    self.activeRolls = {}
    if self.UpdateLootSession then self:UpdateLootSession() end
end