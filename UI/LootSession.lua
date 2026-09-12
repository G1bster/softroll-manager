--------------------------------------------------------------
-- SoftRollManager  —  UI/LootSession.lua
-- Вкладка "Роздача здобичі": панель для РЛ під час роздачі
-- предметів з трупа боса, трекер /roll.
-- Сумісно з WoW 3.3.5a (WotLK)
--------------------------------------------------------------

local SR = SoftRoll

-- ╔══════════════════════════════════════════════════════════╗
-- ║               ВКЛАДКА 4 — РОЗДАЧА ЗДОБИЧІ               ║
-- ╚══════════════════════════════════════════════════════════╝

function SR:BuildLootSession(parent)

    -- ── Інструкція ──
    local instr = SR:MakeLabel(parent, 10, 0.6, 0.6, 0.6, "LEFT")
    instr:SetPoint("TOPLEFT", 10, -8)
    instr:SetPoint("TOPRIGHT", -10, -8)
    instr:SetText("Shift-клік по предмету (коли поле активне) або перетягніть його сюди.")

    -- ── Поле введення ──
    local itemFrame = CreateFrame("Frame", nil, parent)
    itemFrame:SetPoint("TOPLEFT", 8, -28)
    itemFrame:SetPoint("TOPRIGHT", -8, -28)
    itemFrame:SetHeight(38)
    SR:ApplyPanelStyle(itemFrame, 0.10, 0.10, 0.14, 0.9)

    -- Слот іконки (підтримує перетягування)
    local iconBtn = CreateFrame("Button", "SRLootIconBtn", itemFrame)
    iconBtn:SetSize(32, 32)
    iconBtn:SetPoint("LEFT", 6, 0)

    local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    self.lootIconTex = iconTex

    iconBtn:SetScript("OnReceiveDrag", function()
        local ty, id, link = GetCursorInfo()
        if ty == "item" then
            ClearCursor()
            SR:SetLootItem(link)
        end
    end)
    iconBtn:SetScript("OnClick", function(self, button)
        local ty, id, link = GetCursorInfo()
        if ty == "item" then
            ClearCursor()
            SR:SetLootItem(link)
        end
    end)
    iconBtn:SetScript("OnEnter", function(self)
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.lootIconBtn = iconBtn

    -- Кнопка "Очистити" (якоримо до правого краю)
    local clearItemBtn = SR:MakeButton(itemFrame, "Очистити", 80, 24)
    clearItemBtn:SetPoint("RIGHT", -8, 0)
    clearItemBtn:SetScript("OnClick", function()
        SR:ClearLootItem()
    end)
    self.lootClearBtn = clearItemBtn

    local eb = CreateFrame("EditBox", "SRLootEditBox", itemFrame, "InputBoxTemplate")

    -- Поле введення для shift-кліку (адаптивне)
    eb:SetPoint("LEFT", iconBtn, "RIGHT", 12, 0)
    eb:SetPoint("RIGHT", clearItemBtn, "LEFT", -12, 0)
    eb:SetHeight(22)
    eb:SetFont("Fonts\\FRIZQT__.TTF", 12)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text and text ~= "" then
            SR:SetLootItem(text)
        end
        self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    self.lootItemEditBox = eb

    -- ── Хук ChatEdit_InsertLink для підтримки shift-кліку ──
    local origInsertLink = ChatEdit_InsertLink
    ChatEdit_InsertLink = function(text, ...)
        if SR.lootItemEditBox and SR.lootItemEditBox:IsVisible() and SR.lootItemEditBox:HasFocus() then
            SR.lootItemEditBox:SetText(text)
            SR:SetLootItem(text)
            return true
        end
        if SR.editPlayerPopup and SR.editPlayerPopup.editBox and SR.editPlayerPopup.editBox:IsVisible() and SR.editPlayerPopup.editBox:HasFocus() then
            SR.editPlayerPopup.editBox:SetText(text)
            return true
        end
        if origInsertLink then
            return origInsertLink(text, ...)
        end
        return false
    end

    -- ── Відображення поточного предмета ──
    self.lootItemLabel = SR:MakeLabel(parent, 13, 1, 0.82, 0, "LEFT")
    self.lootItemLabel:SetPoint("TOPLEFT", 10, -74)
    self.lootItemLabel:SetText("")

    -- ── Заголовки результатів ──
    local resHdr = CreateFrame("Frame", nil, parent)
    resHdr:SetPoint("TOPLEFT", 8, -96)
    resHdr:SetPoint("TOPRIGHT", -8, -96)
    resHdr:SetHeight(20)

    local function ResCol(text, x, w)
        local fs = SR:MakeLabel(resHdr, 10, 0.65, 0.65, 0.45, "LEFT")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetText(text)
    end
    ResCol("Гравець",    6,   140)
    ResCol("Роль",      150, 80)
    ResCol("Кількість софтів", 235, 100)
    ResCol("Роли",      340, 120)

    local sep2 = parent:CreateTexture(nil, "ARTWORK")
    sep2:SetHeight(1)
    sep2:SetPoint("TOPLEFT", 8, -116)
    sep2:SetPoint("TOPRIGHT", -8, -116)
    sep2:SetTexture(1, 1, 1, 0.15)

    -- ── Прокрутка результатів ──
    local sf = CreateFrame("ScrollFrame", "SRLootScroll", parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -118)
    sf:SetPoint("BOTTOMRIGHT", -28, 42)
    sf:SetScript("OnSizeChanged", function(self)
        if SR.lootChild then
            SR.lootChild:SetWidth(self:GetWidth())
        end
    end)

    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(sf:GetWidth() > 0 and sf:GetWidth() or 462)
    child:SetHeight(1)
    sf:SetScrollChild(child)
    self.lootScroll = sf
    self.lootChild = child
    self.lootRows  = {}

    -- ── Повідомлення про відсутність результатів ──
    self.lootNoResult = SR:MakeLabel(parent, 12, 0.35, 0.35, 0.40, "CENTER")
    self.lootNoResult:SetPoint("CENTER", sf, "CENTER", 0, 0)
    self.lootNoResult:SetText("Ніхто не засофтив цей предмет")
    self.lootNoResult:Hide()

    local rollToggleBtn = SR:MakeButton(parent, "Почати рол (/rw)", 180, 28)
    rollToggleBtn:SetPoint("BOTTOMRIGHT", -8, 12)
    rollToggleBtn:SetScript("OnClick", function()
        if not SR.activeRollItem then
            SR:AnnounceLootRoll()
        else
            SR:EndLootRoll()
        end
    end)
    self.lootRollToggleBtn = rollToggleBtn

    -- ── Підсумкова мітка (знизу зліва) ──
    self.lootSummary = SR:MakeLabel(parent, 11, 0.7, 0.7, 0.7, "LEFT")
    self.lootSummary:SetPoint("BOTTOMLEFT", 10, 12)
    self.lootSummary:SetPoint("RIGHT", rollToggleBtn, "LEFT", -10, 0)
    self.lootSummary:SetWordWrap(true)
    self.lootSummary:SetJustifyV("BOTTOM")
    self.lootSummary:SetText("")
end

--------------------------------------------------------------
-- Фабрика рядків роздачі здобичі
--------------------------------------------------------------
local function GetLootRow(container, index)
    local rows = SR.lootRows
    if rows[index] then return rows[index] end

    local row = CreateFrame("Frame", nil, container)
    row:SetHeight(SR.UI.ROW_H + 2)
    row:SetPoint("TOPLEFT",  0, -(index - 1) * (SR.UI.ROW_H + 2))
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * (SR.UI.ROW_H + 2))

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bg:SetVertexColor(0.12, 0.12, 0.18, (index % 2 == 0) and 0.35 or 0)
    row.bg = bg

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    hl:SetVertexColor(0.3, 0.4, 0.6, 0.2)

    row.nameFS = SR:MakeLabel(row, 12, 1, 1, 1, "LEFT")
    row.nameFS:SetPoint("LEFT", 6, 0)
    row.nameFS:SetWidth(140)

    row.roleFS = SR:MakeLabel(row, 11, 1, 1, 1, "LEFT")
    row.roleFS:SetPoint("LEFT", 150, 0)
    row.roleFS:SetWidth(80)

    row.countFS = SR:MakeLabel(row, 13, 1, 0.85, 0.15, "LEFT")
    row.countFS:SetPoint("LEFT", 235, 0)
    row.countFS:SetWidth(100)

    row.rollFS = SR:MakeLabel(row, 14, 0.4, 1, 0.4, "LEFT")
    row.rollFS:SetPoint("LEFT", 340, 0)
    row.rollFS:SetWidth(120)

    rows[index] = row
    return row
end

--------------------------------------------------------------
-- ВСТАНОВИТИ / ОЧИСТИТИ ПРЕДМЕТ ДЛЯ РОЗДАЧІ
--------------------------------------------------------------
function SR:SetLootItem(input)
    if not input or input == "" then return end

    -- Спроба отримати валідний лінк на предмет з рядка
    local link = input:match("(|c%x+|Hitem:.-%|h%[.-%]|h|r)")

    -- Якщо користувач ввів чистий ID, пробуємо знайти предмет
    if not link then
        local rawID = input:match("(%d+)")
        if rawID then
            local _, l = GetItemInfo(tonumber(rawID))
            if l then link = l end
        end
    end

    if not link then
        self:Print(self.L.PRINT_ITEM_NOT_FOUND_SHIFT)
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

    -- Оновлення іконки
    local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(itemID)
    if tex then
        self.lootIconTex:SetTexture(tex)
    else
        self.lootIconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    self.lootIconBtn.link = link

    -- Оновлення напису
    self.lootItemLabel:SetText("Поточний предмет:  " .. link)

    -- Оновлення поля введення
    if self.lootItemEditBox then
        self.lootItemEditBox:SetText(link)
        self.lootItemEditBox:ClearFocus()
    end

    -- Оновлення результатів
    self:UpdateLootSession()
end

function SR:ClearLootItem()
    self.currentLootItemID   = nil
    self.currentLootItemLink = nil
    self.activeRollItem      = nil
    self.activeRolls         = {}
    self.lastRollItem        = nil
    self.lastRolls           = nil
    self.lootIconTex:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    self.lootIconBtn.link = nil
    self.lootItemLabel:SetText("")
    if self.lootItemEditBox then
        self.lootItemEditBox:SetText("")
    end
    self:UpdateLootSession()
end

--------------------------------------------------------------
-- ОНОВЛЕННЯ СЕСІЇ ЗДОБИЧІ
--------------------------------------------------------------
function SR:UpdateLootSession()
    if not self.lootChild then return end
    if self.lootScroll and self.lootScroll:GetWidth() > 0 then
        self.lootChild:SetWidth(self.lootScroll:GetWidth())
    end

    if self.lootRollToggleBtn then
        if self.activeRollItem then
            self.lootRollToggleBtn:SetText("Закінчити рол")
        else
            self.lootRollToggleBtn:SetText("Почати рол (/rw)")
        end
    end

    local displayedRolls = {}
    if self.activeRollItem and self.activeRollItem == self.currentLootItemID then
        displayedRolls = self.activeRolls or {}
    elseif self.lastRollItem and self.lastRollItem == self.currentLootItemID then
        displayedRolls = self.lastRolls or {}
    end

    local players = {}
    local srCount = 0
    if self.currentLootItemID then
        local srPlayers = self:GetPlayersWithSR(self.currentLootItemID)
        for _, p in ipairs(srPlayers) do
            table.insert(players, p)
            srCount = srCount + 1
        end
    end

    for pName, _ in pairs(displayedRolls) do
        local isSR = false
        for _, p in ipairs(players) do
            if p.name == pName then
                isSR = true
                break
            end
        end
        if not isSR then
            table.insert(players, {
                name = pName,
                role = self:GetPlayerRole(pName),
                count = 0,
            })
        end
    end

    local ranks = {}
    for _, m in ipairs(self:GetRaidMembers()) do
        ranks[m.name] = m.rank
    end

    table.sort(players, function(a, b)
        -- Спочатку сортуємо за наявністю софтів (МС завжди внизу)
        if a.count > 0 and b.count == 0 then return true end
        if a.count == 0 and b.count > 0 then return false end
        
        -- Потім якщо є роли, сортуємо за найвищим ролом
        local maxA = -1
        if displayedRolls[a.name] then
            for _, r in ipairs(displayedRolls[a.name]) do
                if r > maxA then maxA = r end
            end
        end
        local maxB = -1
        if displayedRolls[b.name] then
            for _, r in ipairs(displayedRolls[b.name]) do
                if r > maxB then maxB = r end
            end
        end
        if maxA ~= maxB then
            return maxA > maxB
        end

        -- Потім сортуємо за роллю (РЛ -> Танки -> Хіли -> ДД)
        local wa = SR:GetRoleSortWeight(a.name, ranks[a.name] or 0)
        local wb = SR:GetRoleSortWeight(b.name, ranks[b.name] or 0)
        if wa ~= wb then return wa < wb end
        
        return a.name < b.name
    end)

    if #players == 0 then
        self.lootNoResult:Show()
        self.lootSummary:SetText("")
    else
        self.lootNoResult:Hide()
        self.lootSummary:SetText(srCount .. " гравців зарезервували цей предмет")
    end

    -- Визначаємо найкращий рол серед претендентів, які мають право на виграш
    local topRoll = -1
    local hasSR = (srCount > 0)
    for _, p in ipairs(players) do
        if not hasSR or p.count > 0 then
            local rolls = displayedRolls[p.name]
            if rolls then
                for _, r in ipairs(rolls) do
                    if r > topRoll then topRoll = r end
                end
            end
        end
    end

    for i, p in ipairs(players) do
        local row = GetLootRow(self.lootChild, i)
        row:Show()

        -- Колір класу
        local cc = { r = 0.8, g = 0.8, b = 0.8 }
        for _, m in ipairs(self:GetRaidMembers()) do
            if m.name == p.name then cc = self:GetClassColor(m.class); break end
        end
        row.nameFS:SetText(self:ColorText(p.name, cc.r, cc.g, cc.b))

        local rc = self.ROLE_COLORS[p.role]
        row.roleFS:SetText(self.ROLE_LABELS[p.role])
        row.roleFS:SetTextColor(rc.r, rc.g, rc.b)

        if p.count > 0 then
            row.countFS:SetText("x" .. p.count)
            row.countFS:SetTextColor(1, 1, 1)
        else
            row.countFS:SetText("МС")
            row.countFS:SetTextColor(1, 0.8, 0)
        end

        local pRolls = displayedRolls[p.name]
        if pRolls and #pRolls > 0 then
            local rollsStr = table.concat(pRolls, ", ")
            row.rollFS:SetText(rollsStr)
        else
            row.rollFS:SetText("")
        end

        -- Золотий фон лише для реального лідера / переможця (або нічиєї) при наявності ролів
        local isLeader = false
        if topRoll > -1 and (not hasSR or p.count > 0) and pRolls then
            for _, r in ipairs(pRolls) do
                if r == topRoll then
                    isLeader = true
                    break
                end
            end
        end

        if isLeader then
            row.bg:SetVertexColor(0.30, 0.22, 0.04, 0.40)
        else
            row.bg:SetVertexColor(0.11, 0.11, 0.17, (i % 2 == 0) and 0.38 or 0)
        end
    end

    for i = #players + 1, #self.lootRows do
        self.lootRows[i]:Hide()
    end

    self.lootChild:SetHeight(math.max(1, #players * (SR.UI.ROW_H + 2)))
end

--------------------------------------------------------------
-- АНОНС РОЛУ
--------------------------------------------------------------
function SR:AnnounceLootRoll()
    if not self.currentLootItemID or not self.currentLootItemLink then
        self:Print(self.L.PRINT_NO_ITEM_SELECTED)
        return
    end

    local players = self:GetPlayersWithSR(self.currentLootItemID)
    local chatType = self:GetAnnouncementChannel(true)

    if chatType == "SAY" then
        self:Print(self.L.PRINT_NOT_IN_RAID_SAY)
    end

    self.activeRollItem = self.currentLootItemID
    self.activeRolls = {}
    self.lastRollItem = nil
    self.lastRolls = nil

    -- Резервна логіка "Немає SR"
    if #players == 0 then
        SendChatMessage(format(self.L.LOOT_NO_SRS_MS, self.currentLootItemLink), chatType)
    else
        SendChatMessage(format(self.L.LOOT_ITEM_HEADER, self.currentLootItemLink), chatType)

        -- Формування списку претендентів (безпечне розбиття для уникнення ліміту 255 символів)
        local names = {}
        for _, p in ipairs(players) do
            local cx = (p.count > 1) and (" x" .. p.count) or ""
            names[#names + 1] = p.name .. cx
        end

        local header = self.L.LOOT_ROLL_CANDIDATES:gsub("%%s", "")
        local line = header
        for i, nameStr in ipairs(names) do
            local sep = (i == 1) and "" or ", "
            if #line + #sep + #nameStr > 220 then
                SendChatMessage(line, chatType)
                line = "   " .. nameStr
            else
                line = line .. sep .. nameStr
            end
        end
        if line ~= "" then
            SendChatMessage(line, chatType)
        end
    end

    if self.UpdateLootSession then self:UpdateLootSession() end
end


