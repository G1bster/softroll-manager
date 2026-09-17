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

    -- ── Верхній тулбар (Під-вкладки: Здобич у сумках / Розрол) ──
    local topBar = CreateFrame("Frame", nil, parent)
    topBar:SetPoint("TOPLEFT", 8, -6)
    topBar:SetPoint("TOPRIGHT", -8, -6)
    topBar:SetHeight(28)

    local btnBagLootTab = SR:MakeFlatTab(topBar, self.L.BAG_LOOT_TAB, 24)
    btnBagLootTab:SetWidth(170)
    btnBagLootTab:SetPoint("LEFT", 0, 0)
    btnBagLootTab:SetScript("OnClick", function()
        SR:SetLootSessionMode("bag")
    end)
    self.btnBagLootTab = btnBagLootTab

    local btnActiveRollTab = SR:MakeFlatTab(topBar, self.L.BAG_LOOT_ACTIVE_ROLL, 24)
    btnActiveRollTab:SetWidth(170)
    btnActiveRollTab:SetPoint("LEFT", btnBagLootTab, "RIGHT", 6, 0)
    btnActiveRollTab:SetScript("OnClick", function()
        SR:SetLootSessionMode("roll")
    end)
    self.btnActiveRollTab = btnActiveRollTab

    -- Іконка замість текстової кнопки: з трьома текстовими елементами (дві
    -- вкладки + повнорозмірна кнопка) у топбарі майже не лишалось зазору
    -- (~480px доступно, ~486px потрібно) — текст "Оновити сумки" наїжджав
    -- на вкладку "Активний розрол".
    local btnRefreshBags = CreateFrame("Button", nil, topBar)
    btnRefreshBags:SetSize(24, 24)
    btnRefreshBags:SetPoint("RIGHT", 0, 0)
    btnRefreshBags:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    btnRefreshBags:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    btnRefreshBags:SetScript("OnClick", function()
        SR:RefreshBagLoot()
    end)
    btnRefreshBags:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(SR.L.BAG_LOOT_REFRESH)
        GameTooltip:Show()
    end)
    btnRefreshBags:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.btnRefreshBags = btnRefreshBags

    local sepNav = parent:CreateTexture(nil, "ARTWORK")
    sepNav:SetHeight(1)
    sepNav:SetPoint("TOPLEFT", 8, -34)
    sepNav:SetPoint("TOPRIGHT", -8, -34)
    sepNav:SetTexture(1, 1, 1, 0.15)

    -----------------------------------------------------------
    -- ПАНЕЛЬ 1: ЗДОБИЧ У СУМКАХ (Bag Loot Panel)
    -----------------------------------------------------------
    local bagPanel = CreateFrame("Frame", nil, parent)
    bagPanel:SetPoint("TOPLEFT", 0, -36)
    bagPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    self.lootBagPanel = bagPanel

    local bagHdr = CreateFrame("Frame", nil, bagPanel)
    bagHdr:SetPoint("TOPLEFT", 8, -4)
    bagHdr:SetPoint("TOPRIGHT", -8, -4)
    bagHdr:SetHeight(20)

    local function BagCol(text, x, w)
        local fs = SR:MakeLabel(bagHdr, 10, 0.65, 0.65, 0.45, "LEFT")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetText(text)
    end
    BagCol("Предмет",     10, 145)
    BagCol("К-ть",        180, 35)
    BagCol("Софт-роли",   220, 85)
    BagCol("Таймер",      310, 85)
    BagCol("Дія",         400, 65)

    local sepBag = bagPanel:CreateTexture(nil, "ARTWORK")
    sepBag:SetHeight(1)
    sepBag:SetPoint("TOPLEFT", 8, -24)
    sepBag:SetPoint("TOPRIGHT", -8, -24)
    sepBag:SetTexture(1, 1, 1, 0.12)

    local bsf = CreateFrame("ScrollFrame", "SRBagLootScroll", bagPanel, "UIPanelScrollFrameTemplate")
    bsf:SetPoint("TOPLEFT", 6, -26)
    bsf:SetPoint("BOTTOMRIGHT", -28, 30)

    local bchild = CreateFrame("Frame", nil, bsf)
    bchild:SetWidth(bsf:GetWidth() > 0 and bsf:GetWidth() or 462)
    bchild:SetHeight(1)
    bsf:SetScrollChild(bchild)
    self.lootBagScroll = bsf
    self.lootBagChild = bchild
    self.bagLootRows = {}

    self.bagLootNoResult = SR:MakeLabel(bagPanel, 12, 0.45, 0.45, 0.50, "CENTER")
    self.bagLootNoResult:SetPoint("CENTER", bsf, "CENTER", 0, 0)
    self.bagLootNoResult:SetText(self.L.BAG_LOOT_EMPTY)
    self.bagLootNoResult:Hide()

    self.bagLootSummary = SR:MakeLabel(bagPanel, 11, 0.7, 0.7, 0.7, "LEFT")
    self.bagLootSummary:SetPoint("BOTTOMLEFT", 10, 8)
    self.bagLootSummary:SetPoint("BOTTOMRIGHT", -10, 8)
    self.bagLootSummary:SetText("")

    -----------------------------------------------------------
    -- ПАНЕЛЬ 2: АКТИВНИЙ РОЗРОЛ (Active Roll Panel)
    -----------------------------------------------------------
    local rollPanel = CreateFrame("Frame", nil, parent)
    rollPanel:SetPoint("TOPLEFT", 0, -36)
    rollPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    rollPanel:Hide()
    self.lootRollPanel = rollPanel

    -- ── Інструкція ──
    local instr = SR:MakeLabel(rollPanel, 10, 0.6, 0.6, 0.6, "LEFT")
    instr:SetPoint("TOPLEFT", 10, -4)
    instr:SetPoint("TOPRIGHT", -10, -4)
    instr:SetText("Shift-клік по предмету (коли поле активне) або виберіть його зі списку сумок.")

    -- ── Поле введення ──
    local itemFrame = CreateFrame("Frame", nil, rollPanel)
    itemFrame:SetPoint("TOPLEFT", 8, -22)
    itemFrame:SetPoint("TOPRIGHT", -8, -22)
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

    -- Кнопка "Очистити"
    local clearItemBtn = SR:MakeButton(itemFrame, "Очистити", 70, 24)
    clearItemBtn:SetPoint("RIGHT", -6, 0)
    clearItemBtn:SetScript("OnClick", function()
        SR:ClearLootItem()
    end)
    self.lootClearBtn = clearItemBtn

    -- Кнопка "⬅ До сумок"
    local backToBagsBtn = SR:MakeButton(itemFrame, self.L.BAG_LOOT_BACK_TO_BAGS, 85, 24)
    backToBagsBtn:SetPoint("RIGHT", clearItemBtn, "LEFT", -6, 0)
    backToBagsBtn:SetScript("OnClick", function()
        SR:SetLootSessionMode("bag")
    end)
    self.lootBackToBagsBtn = backToBagsBtn

    local eb = CreateFrame("EditBox", "SRLootEditBox", itemFrame, "InputBoxTemplate")
    eb:SetPoint("LEFT", iconBtn, "RIGHT", 10, 0)
    eb:SetPoint("RIGHT", backToBagsBtn, "LEFT", -10, 0)
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
    self.lootItemLabel = SR:MakeLabel(rollPanel, 13, 1, 0.82, 0, "LEFT")
    self.lootItemLabel:SetPoint("TOPLEFT", 10, -66)
    self.lootItemLabel:SetText("")

    -- ── Заголовки результатів ──
    local resHdr = CreateFrame("Frame", nil, rollPanel)
    resHdr:SetPoint("TOPLEFT", 8, -88)
    resHdr:SetPoint("TOPRIGHT", -8, -88)
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

    local sep2 = rollPanel:CreateTexture(nil, "ARTWORK")
    sep2:SetHeight(1)
    sep2:SetPoint("TOPLEFT", 8, -108)
    sep2:SetPoint("TOPRIGHT", -8, -108)
    sep2:SetTexture(1, 1, 1, 0.15)

    -- ── Прокрутка результатів ──
    local sf = CreateFrame("ScrollFrame", "SRLootScroll", rollPanel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -110)
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
    self.lootNoResult = SR:MakeLabel(rollPanel, 12, 0.35, 0.35, 0.40, "CENTER")
    self.lootNoResult:SetPoint("CENTER", sf, "CENTER", 0, 0)
    self.lootNoResult:SetText(self.L.UI_NO_SRS_FOR_ITEM or "Ніхто не засофтив цей предмет")
    self.lootNoResult:Hide()

    local rollToggleBtn = SR:MakeButton(rollPanel, self.L.UI_START_ROLL_BTN or "Почати рол (/rw)", 180, 28)
    rollToggleBtn:SetPoint("BOTTOMRIGHT", -8, 10)
    rollToggleBtn:SetScript("OnClick", function()
        if not SR.activeRollItem then
            SR:AnnounceLootRoll()
        else
            SR:EndLootRoll()
        end
    end)
    self.lootRollToggleBtn = rollToggleBtn

    -- ── Підсумкова мітка (знизу зліва) ──
    self.lootSummary = SR:MakeLabel(rollPanel, 11, 0.7, 0.7, 0.7, "LEFT")
    self.lootSummary:SetPoint("BOTTOMLEFT", 10, 10)
    self.lootSummary:SetPoint("RIGHT", rollToggleBtn, "LEFT", -10, 0)
    self.lootSummary:SetWordWrap(true)
    self.lootSummary:SetJustifyV("BOTTOM")
    self.lootSummary:SetText("")

    -- За замовчуванням відкриваємо сканер здобичі у сумках
    self:SetLootSessionMode("bag")
end


--------------------------------------------------------------
-- ФАБРИКА РЯДКІВ ЗДОБИЧІ У СУМКАХ
--------------------------------------------------------------
function SR:GetBagLootRow(container, index)
    self.bagLootRows = self.bagLootRows or {}
    if self.bagLootRows[index] then return self.bagLootRows[index] end

    local rowH = 26
    local row = CreateFrame("Button", nil, container)
    row:SetHeight(rowH)
    row:SetPoint("TOPLEFT",  0, -(index - 1) * (rowH + 2))
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * (rowH + 2))

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bg:SetVertexColor(0.11, 0.11, 0.17, (index % 2 == 0) and 0.35 or 0)
    row.bg = bg

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    hl:SetVertexColor(0.25, 0.35, 0.50, 0.25)

    -- Icon button
    local iconBtn = CreateFrame("Button", nil, row)
    iconBtn:SetSize(22, 22)
    iconBtn:SetPoint("LEFT", 6, 0)
    local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    row.iconTex = iconTex
    row.iconBtn = iconBtn

    iconBtn:SetScript("OnEnter", function(self)
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Item name / link (clickable for chat paste / tooltip / selection)
    local nameBtn = CreateFrame("Button", nil, row)
    nameBtn:SetPoint("LEFT", iconBtn, "RIGHT", 6, 0)
    nameBtn:SetSize(145, 22)
    local nameFS = SR:MakeLabel(nameBtn, 11, 1, 1, 1, "LEFT")
    nameFS:SetAllPoints()
    row.nameFS = nameFS
    row.nameBtn = nameBtn

    nameBtn:SetScript("OnEnter", function(self)
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    nameBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    nameBtn:SetScript("OnClick", function(self)
        if IsModifiedClick and IsModifiedClick("CHATLINK") and self.link and ChatEdit_InsertLink then
            ChatEdit_InsertLink(self.link)
        elseif self.link then
            SR:SetLootItem(self.link)
        end
    end)

    -- Count
    row.countFS = SR:MakeLabel(row, 11, 0.85, 0.85, 0.85, "CENTER")
    row.countFS:SetPoint("LEFT", 180, 0)
    row.countFS:SetWidth(35)

    -- SR Badge
    row.srBadge = SR:MakeLabel(row, 11, 0.4, 1, 0.4, "LEFT")
    row.srBadge:SetPoint("LEFT", 220, 0)
    row.srBadge:SetWidth(85)

    -- Trade Timer Badge
    row.timerBadge = SR:MakeLabel(row, 11, 1, 1, 1, "LEFT")
    row.timerBadge:SetPoint("LEFT", 310, 0)
    row.timerBadge:SetWidth(85)

    -- Distribute button
    -- x=400, ширина 58 → закінчується на 458px, що влазить у видиму
    -- область скролу (462px = 496px панелі − 6 відступ − 28 під скролбар);
    -- на x=415 (стара позиція) кнопка обрізалась скролом на ~11px.
    local rollBtn = SR:MakeButton(row, self.L.BAG_LOOT_DISTRIBUTE_BTN, 58, 20)
    rollBtn:SetPoint("LEFT", 400, 0)
    row.rollBtn = rollBtn

    self.bagLootRows[index] = row
    return row
end

--------------------------------------------------------------
-- ОНОВЛЕННЯ СПИСКУ ЗДОБИЧІ У СУМКАХ
--------------------------------------------------------------
function SR:RefreshBagLoot()
    if not self.lootBagChild then return end

    local bagItems = self:ScanBagsForLoot()
    self.cachedBagItems = bagItems

    local totalItems = #bagItems
    local srCountTotal = 0
    local critTimerTotal = 0

    for i, item in ipairs(bagItems) do
        if item.srCount > 0 then srCountTotal = srCountTotal + 1 end
        if item.tradeMins and item.tradeMins <= 30 then critTimerTotal = critTimerTotal + 1 end

        local row = self:GetBagLootRow(self.lootBagChild, i)
        row:Show()

        -- Icon
        local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(item.itemID)
        row.iconTex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.iconBtn.link = item.itemLink

        -- Link / Name
        row.nameFS:SetText(item.itemLink or ("Item #" .. item.itemID))
        row.nameBtn.link = item.itemLink

        -- Count
        if item.count and item.count > 1 then
            row.countFS:SetText("x" .. item.count)
        else
            row.countFS:SetText("x1")
        end

        -- SR Badge
        if item.srCount > 0 then
            row.srBadge:SetText("|cff44ff44" .. string.format(self.L.BAG_LOOT_SR_BADGE, item.srCount) .. "|r")
        else
            row.srBadge:SetText("|cff888888" .. self.L.BAG_LOOT_FREE_BADGE .. "|r")
        end

        -- Timer Badge
        if item.tradeMins then
            if item.tradeMins <= 30 then
                row.timerBadge:SetText("|cffff4444" .. string.format(self.L.BAG_LOOT_TIMER_CRITICAL, item.tradeText or "") .. "|r")
            elseif item.tradeMins <= 60 then
                row.timerBadge:SetText("|cffffff44" .. (item.tradeText or "") .. "|r")
            else
                row.timerBadge:SetText("|cff44ff44" .. (item.tradeText or "") .. "|r")
            end
        else
            row.timerBadge:SetText("|cff777777" .. self.L.BAG_LOOT_NO_TIMER .. "|r")
        end

        -- Button action
        row.rollBtn:SetScript("OnClick", function()
            SR:SetLootItem(item.itemLink)
        end)

        -- Row background
        if item.tradeMins and item.tradeMins <= 30 then
            row.bg:SetVertexColor(0.35, 0.08, 0.08, 0.45) -- Alert red tint
        elseif item.srCount > 0 then
            row.bg:SetVertexColor(0.12, 0.18, 0.28, (i % 2 == 0) and 0.40 or 0.20)
        else
            row.bg:SetVertexColor(0.11, 0.11, 0.17, (i % 2 == 0) and 0.35 or 0)
        end
    end

    -- Hide remaining rows
    for i = totalItems + 1, #(self.bagLootRows or {}) do
        self.bagLootRows[i]:Hide()
    end

    self.lootBagChild:SetHeight(math.max(1, totalItems * 28))

    -- Empty state
    if totalItems == 0 then
        self.bagLootNoResult:Show()
    else
        self.bagLootNoResult:Hide()
    end

    -- Update tab title with count
    if self.btnBagLootTab then
        local tabText = (critTimerTotal > 0)
            and string.format("%s (%d) |cffff4444[! %d]|r", self.L.BAG_LOOT_TAB, totalItems, critTimerTotal)
            or string.format("%s (%d)", self.L.BAG_LOOT_TAB, totalItems)
        if self.btnBagLootTab.label and self.btnBagLootTab.label.SetText then
            self.btnBagLootTab.label:SetText(tabText)
        elseif self.btnBagLootTab.SetText then
            self.btnBagLootTab:SetText(tabText)
        end
    end

    -- Update summary
    if self.bagLootSummary then
        self.bagLootSummary:SetText(string.format(self.L.BAG_LOOT_SUMMARY, totalItems, srCountTotal, critTimerTotal))
    end
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
-- ОНОВЛЕННЯ ПАНЕЛІ РОЗРОЛУ (UI)
--------------------------------------------------------------
function SR:UpdateLootRollUI()
    if not self.lootChild then return end
    if self.lootScroll and self.lootScroll:GetWidth() > 0 then
        self.lootChild:SetWidth(self.lootScroll:GetWidth())
    end

    if self.lootRollToggleBtn then
        if self.activeRollItem then
            self.lootRollToggleBtn:SetText(self.L.UI_END_ROLL_BTN or "Завершити рол")
        else
            self.lootRollToggleBtn:SetText(self.L.UI_START_ROLL_BTN or "Почати рол (/rw)")
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
        self.lootSummary:SetText(string.format(self.L.LOOT_RESERVED_SUMMARY or "%d гравців зарезервували цей предмет", srCount))
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


