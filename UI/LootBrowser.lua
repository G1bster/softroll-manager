--------------------------------------------------------------
-- SoftRollManager  —  UI/LootBrowser.lua
-- Вкладка "Оглядач здобичі": каталог предметів за босами,
-- резервація кліком, підсвітка вже зарезервованих предметів.
-- Сумісно з WoW 3.3.5a (WotLK)
--------------------------------------------------------------

local SR = SoftRoll

-- ╔══════════════════════════════════════════════════════════╗
-- ║               ВКЛАДКА 3 — ОГЛЯДАЧ ЗДОБИЧІ               ║
-- ╚══════════════════════════════════════════════════════════╝

function SR:BuildLootBrowser(parent)

    -- ── Верхня панель: Підземелля та Героїк ──
    -- ── Вкладки Оглядача Здобичі ──
    SR.lbActiveSubTab = SR.lbActiveSubTab or "bosses"

    local function MakeFlatTab(parent, text, h)
        local tb = CreateFrame("Button", nil, parent)
        tb:SetHeight(h)
        
        local bg = tb:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        bg:SetVertexColor(0.10, 0.10, 0.16, 0.9)
        tb.bg = bg

        local accent = tb:CreateTexture(nil, "OVERLAY")
        accent:SetHeight(3)
        accent:SetPoint("TOPLEFT",  tb, "TOPLEFT",  0, 0)
        accent:SetPoint("TOPRIGHT", tb, "TOPRIGHT", 0, 0)
        accent:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        accent:SetVertexColor(SR.UI.C.blue[1], SR.UI.C.blue[2], SR.UI.C.blue[3], 0)
        tb.accent = accent

        local txt = tb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        txt:SetPoint("CENTER", 0, 0)
        txt:SetText(text)
        txt:SetFont("Fonts\\FRIZQT__.TTF", 11)
        tb.label = txt
        
        tb:SetScript("OnEnter", function(self)
            if self.active then return end
            self.bg:SetVertexColor(0.18, 0.22, 0.32, 0.9)
        end)
        tb:SetScript("OnLeave", function(self)
            if self.active then return end
            self.bg:SetVertexColor(0.10, 0.10, 0.16, 0.9)
        end)
        
        return tb
    end

    local tabBosses = MakeFlatTab(parent, "Боси", 24)
    tabBosses:SetPoint("TOPLEFT", 8, -10)
    tabBosses:SetPoint("RIGHT", parent, "CENTER", -2, 0)
    
    local tabWishlist = MakeFlatTab(parent, "Вішліст", 24)
    tabWishlist:SetPoint("LEFT", parent, "CENTER", 2, 0)
    tabWishlist:SetPoint("TOPRIGHT", -8, -10)
    
    local function UpdateSubTabs()
        if SR.lbActiveSubTab == "bosses" then
            tabBosses.active = true
            tabBosses.bg:SetVertexColor(0.15, 0.18, 0.28, 0.95)
            tabBosses.accent:SetVertexColor(SR.UI.C.blue[1], SR.UI.C.blue[2], SR.UI.C.blue[3], 1)
            tabBosses.label:SetTextColor(1, 0.82, 0)
            
            tabWishlist.active = false
            tabWishlist.bg:SetVertexColor(0.10, 0.10, 0.16, 0.9)
            tabWishlist.accent:SetVertexColor(SR.UI.C.blue[1], SR.UI.C.blue[2], SR.UI.C.blue[3], 0)
            tabWishlist.label:SetTextColor(0.5, 0.5, 0.5)
        else
            tabBosses.active = false
            tabBosses.bg:SetVertexColor(0.10, 0.10, 0.16, 0.9)
            tabBosses.accent:SetVertexColor(SR.UI.C.blue[1], SR.UI.C.blue[2], SR.UI.C.blue[3], 0)
            tabBosses.label:SetTextColor(0.5, 0.5, 0.5)
            
            tabWishlist.active = true
            tabWishlist.bg:SetVertexColor(0.15, 0.18, 0.28, 0.95)
            tabWishlist.accent:SetVertexColor(SR.UI.C.blue[1], SR.UI.C.blue[2], SR.UI.C.blue[3], 1)
            tabWishlist.label:SetTextColor(1, 0.82, 0)
        end
    end
    
    tabBosses:SetScript("OnClick", function()
        SR.lbActiveSubTab = "bosses"
        UpdateSubTabs()
        SR:UpdateLootBrowser()
    end)
    tabWishlist:SetScript("OnClick", function()
        SR.lbActiveSubTab = "wishlist"
        UpdateSubTabs()
        SR:UpdateLootBrowser()
    end)
    UpdateSubTabs()

    -- ── Елементи вкладки "Боси" ──
    local bossLabel = SR:MakeLabel(parent, 11, 0.85, 0.85, 0.55)
    bossLabel:SetPoint("TOPLEFT", 10, -42)
    bossLabel:SetText("Бос:")
    self.lbBossLabel = bossLabel

    local bossDD = CreateFrame("Frame", "SoftRollLBBossDD", parent, "UIDropDownMenuTemplate")
    bossDD:SetPoint("LEFT", bossLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(bossDD, 160)
    self.lbBossDD = bossDD

    local heroicCb = CreateFrame("CheckButton", "SRHeroicCheck", parent, "UICheckButtonTemplate")
    heroicCb:SetPoint("LEFT", bossDD, "RIGHT", 10, 2)
    heroicCb:SetSize(24, 24)
    heroicCb:SetChecked(SR.db.lootDifficulty == "25H")
    self.lbHeroicCb = heroicCb
    
    local heroicLabel = SR:MakeLabel(parent, 11, 0.85, 0.85, 0.55)
    heroicLabel:SetPoint("LEFT", heroicCb, "RIGHT", 4, 0)
    heroicLabel:SetText("Героїк")
    self.lbHeroicLabel = heroicLabel

    heroicCb:SetScript("OnClick", function(self)
        SR.db.lootDifficulty = self:GetChecked() and "25H" or "25N"
        SR:UpdateLootBrowserItems()
    end)

    if type(self.lbSelectedBoss) ~= "string" then
        self.lbSelectedBoss = "ICC_1"
    end

    -- ── Права панель: Список предметів ──
    local itemPanel = CreateFrame("Frame", nil, parent)
    itemPanel:SetPoint("TOPLEFT", 6, -68)
    itemPanel:SetPoint("BOTTOMRIGHT", -6, 44)
    SR:ApplyPanelStyle(itemPanel, 0.06, 0.06, 0.10, 0.95)

    local itemScroll = CreateFrame("ScrollFrame", "SRItemScroll", itemPanel, "UIPanelScrollFrameTemplate")
    itemScroll:SetPoint("TOPLEFT", 4, -4)
    itemScroll:SetPoint("BOTTOMRIGHT", -24, 4)
    itemScroll:SetScript("OnSizeChanged", function(self)
        if SR.lbItemChild then
            SR.lbItemChild:SetWidth(self:GetWidth())
        end
    end)

    local itemChild = CreateFrame("Frame", nil, itemScroll)
    itemChild:SetWidth(itemScroll:GetWidth() > 0 and itemScroll:GetWidth() or 456)
    itemChild:SetHeight(1)
    itemScroll:SetScrollChild(itemChild)
    self.lbItemScroll = itemScroll
    self.lbItemChild = itemChild
    self.lbItemRows  = {}

    -- ── Єдиний нижній ряд: "Кому:" [дропдаун] .......... [-][N][+] [Засофтити xN] ──
    -- (лише для РЛ/ко-хоста — показ/приховування керує SR:UpdateAdminReadOnly
    -- у UI/Shell.lua). Раніше "Кому" було окремим рядком над кнопкою
    -- "В обране" — та кнопка прибрана (вішліст тепер додається/прибирається
    -- сердечком на кожному рядку предмета, див. GetLBItemRow), тож дропдаун
    -- зайняв її місце й весь блок дій влазить в один рядок.
    local targetLabel = SR:MakeLabel(parent, 11, 0.85, 0.85, 0.55)
    targetLabel:SetPoint("BOTTOMLEFT", 8, 14)
    targetLabel:SetText(SR.L.UI_TARGET_LABEL)
    self.lbTargetLabel = targetLabel

    local targetDD = CreateFrame("Frame", "SRLootTargetDD", parent, "UIDropDownMenuTemplate")
    targetDD:SetPoint("LEFT", targetLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(targetDD, 80)
    self.lbTargetDD = targetDD

    local reserveBtn = SR:MakeButton(parent, format(SR.L.UI_RESERVE_BTN, 1), 115, 28)
    reserveBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    reserveBtn:SetScript("OnClick", function()
        if not SR.lbSelectedItemID then
            SR:Print(SR.L.PRINT_SELECT_ITEM_FIRST)
            return
        end
        local target = SR.lbTargetPlayer or SR:GetLocalPlayerName()
        SR:RequestSRFromUI(SR.lbSelectedItemID, SR.lbReserveCount or 1, target, true)
    end)
    self.lbReserveBtn = reserveBtn

    local incBtn = SR:MakeButton(parent, "+", 24, 28)
    incBtn:SetPoint("RIGHT", reserveBtn, "LEFT", -6, 0)
    incBtn:SetScript("OnClick", function()
        SR.lbReserveCount = (SR.lbReserveCount or 1) + 1
        SR:LayoutReserveButtons()
    end)
    self.lbIncBtn = incBtn

    local countBox = CreateFrame("Frame", nil, parent)
    countBox:SetSize(28, 28)
    countBox:SetPoint("RIGHT", incBtn, "LEFT", -2, 0)
    SR:ApplyPanelStyle(countBox, 0.06, 0.06, 0.10, 0.9)
    local countFS = countBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countFS:SetPoint("CENTER")
    countFS:SetFont("Fonts\\FRIZQT__.TTF", 12)
    countFS:SetText("1")
    self.lbCountFS = countFS

    local decBtn = SR:MakeButton(parent, "-", 24, 28)
    decBtn:SetPoint("RIGHT", countBox, "LEFT", -2, 0)
    decBtn:SetScript("OnClick", function()
        if (SR.lbReserveCount or 1) > 1 then
            SR.lbReserveCount = SR.lbReserveCount - 1
            SR:LayoutReserveButtons()
        end
    end)
    self.lbDecBtn = decBtn

    -- Початковий стан
    if not self.db.lootDifficulty then self.db.lootDifficulty = "25H" end
    SR:UpdateLootBrowserItems()
end

    -- Функція GetBossRow більше не потрібна

--------------------------------------------------------------
-- Фабрика рядків списку предметів
--------------------------------------------------------------
local function GetLBItemRow(container, index)
    local rows = SR.lbItemRows
    if rows[index] then return rows[index] end

    local row = CreateFrame("Button", nil, container)
    row:SetHeight(SR.UI.ITEM_H)
    row:SetPoint("TOPLEFT",  0, -(index - 1) * SR.UI.ITEM_H)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * SR.UI.ITEM_H)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bg:SetVertexColor(0.12, 0.12, 0.18, (index % 2 == 0) and 0.3 or 0)
    row.bg = bg

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    hl:SetVertexColor(0.3, 0.4, 0.6, 0.25)

    -- Іконка предмета
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(28, 28)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    -- Хрестик видалення — з'являється лише якщо поточна ціль (self.lbTargetPlayer
    -- або сам гравець) вже зарезервувала показаний в рядку предмет.
    local removeBtn = CreateFrame("Button", nil, row)
    removeBtn:SetSize(14, 14)
    removeBtn:SetPoint("TOPRIGHT", row.icon, "TOPRIGHT", 3, 3)
    removeBtn:SetNormalTexture("Interface\\BUTTONS\\UI-GroupLoot-Pass-Up")
    removeBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-GroupLoot-Pass-Highlight")
    removeBtn:SetPushedTexture("Interface\\BUTTONS\\UI-GroupLoot-Pass-Down")
    removeBtn:Hide()
    removeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(SR.L.UI_REMOVE_ITEM_TOOLTIP)
        GameTooltip:Show()
    end)
    removeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    removeBtn:SetScript("OnClick", function(self)
        local r = self:GetParent()
        if not r.itemID then return end
        local target = SR.lbTargetPlayer or SR:GetLocalPlayerName()
        if SR:IsSessionHost() or (SR:IsSessionLeader() and not SR.sessionActive) then
            SR:RemoveSR(target, r.itemID)
            SR:Print(format(SR.L.PRINT_ITEM_REMOVED_FROM, target))
        else
            SR:SendAddonMsg("R|" .. target .. "|" .. r.itemID, "WHISPER", SR.sessionHost)
            SR:Print(SR.L.PRINT_REMOVE_REQUEST_SENT)
        end
        SR:UpdateLootBrowserItems()
    end)
    row.removeBtn = removeBtn

    -- Сердечко — додати/прибрати предмет з вішліста (замість колишньої
    -- окремої кнопки "В обране" внизу панелі).
    local wlBtn = CreateFrame("Button", nil, row)
    wlBtn:SetSize(18, 18)
    wlBtn:SetPoint("RIGHT", -6, 0)
    local wlBtnTex = wlBtn:CreateTexture(nil, "ARTWORK")
    wlBtnTex:SetAllPoints()
    wlBtnTex:SetTexture("Interface\\Icons\\INV_Misc_Heart_02")
    wlBtn.tex = wlBtnTex
    wlBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    wlBtn:SetScript("OnClick", function(self)
        local r = self:GetParent()
        if not r.itemID then return end
        SR:ToggleWishlistItem(r.itemID)
        SR:UpdateLootBrowserItems()
        if SR.lbActiveSubTab == "wishlist" then
            SR:UpdateLootBrowser()
        end
    end)
    wlBtn:SetScript("OnEnter", function(self)
        local r = self:GetParent()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if r.itemID and SR:IsInWishlist(r.itemID) then
            GameTooltip:SetText(SR.L.UI_WISHLIST_REMOVE_TOOLTIP)
        else
            GameTooltip:SetText(SR.L.UI_WISHLIST_ADD_TOOLTIP)
        end
        GameTooltip:Show()
    end)
    wlBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.wlBtn = wlBtn

    -- Назва предмета
    -- Ширина 300 (було 335, було 380) — звужена ще раз, щоб звільнити
    -- місце під сердечко вішліста праворуч (те анкориться від правого
    -- краю рядка, а не має фіксованого x).
    row.nameFS = SR:MakeLabel(row, 11, 1, 0.82, 0, "LEFT")
    row.nameFS:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.nameFS:SetWidth(300)
    row.nameFS:SetWordWrap(false)

    -- Іконка вішліста (рейд-маркер зірка) — маленький бейдж на іконці
    -- предмета, окремо від інтерактивного сердечка вище.
    local wlIcon = row:CreateTexture(nil, "OVERLAY")
    wlIcon:SetSize(16, 16)
    wlIcon:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -6, 6)
    wlIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    wlIcon:Hide()
    row.wlIcon = wlIcon

    -- SR бейдж фон видалено для кращого вигляду

    -- Текст SR — анкориться від сердечка, а не від краю рядка.
    row.srFS = SR:MakeLabel(row, 10, 0.45, 0.82, 0.35, "CENTER")
    row.srFS:SetPoint("RIGHT", wlBtn, "LEFT", -4, 0)
    row.srFS:SetWidth(56)

    -- Підказка при наведенні
    row:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local _, link = GetItemInfo(self.itemID)
            if link then
                GameTooltip:SetHyperlink(link)
            else
                GameTooltip:SetText("Завантаження предмета #" .. self.itemID .. "...")
            end
            
            -- Додаємо інформацію про софти
            local srPlayers = SR:GetPlayersWithSR(self.itemID)
            if #srPlayers > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Зарезервували:", 0.40, 0.85, 0.32)
                for _, p in ipairs(srPlayers) do
                    GameTooltip:AddDoubleLine(p.name, p.count .. "x", 1, 1, 1, 1, 0.82, 0)
                end
            end
            
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Клік для вибору / shift-клік для лінку в чат
    row:SetScript("OnClick", function(self, button)
        if IsShiftKeyDown() and self.itemID then
            local _, link = GetItemInfo(self.itemID)
            if link then
                if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then
                    return
                end
                local editBox = (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()) or ChatFrame1EditBox or ChatFrameEditBox
                if editBox then
                    editBox:Show()
                    editBox:SetFocus()
                    editBox:Insert(link)
                end
            end
        else
            SR.lbSelectedItemID = self.itemID
            SR:HighlightLBItem(self.itemID)
        end
    end)

    rows[index] = row
    return row
end

--------------------------------------------------------------
-- ОНОВЛЕННЯ ОГЛЯДАЧА ЗДОБИЧІ
--------------------------------------------------------------
function SR:UpdateLootBrowser()
    if self.lbItemScroll and self.lbItemScroll:GetWidth() > 0 and self.lbItemChild then
        self.lbItemChild:SetWidth(self.lbItemScroll:GetWidth())
    end
    if self.lbActiveSubTab == "wishlist" then
        self.lbBossLabel:Hide()
        self.lbBossDD:Hide()
        self.lbHeroicCb:Hide()
        self.lbHeroicLabel:Hide()
    else
        self.lbBossLabel:Show()
        self.lbBossDD:Show()
        self.lbHeroicCb:Show()
        self.lbHeroicLabel:Show()
    end

    -- Додавання в чергу всіх предметів з таблиці здобичі
    if SR.LOOT_DATA.ICC then
        local allIds = {}
        for _, boss in ipairs(SR.LOOT_DATA.ICC) do
            local loot = self:GetBossLoot(boss)
            if loot then
                for _, id in ipairs(loot) do allIds[#allIds + 1] = id end
            end
        end
        self:QueueItemCacheList(allIds)
    end
    if SR.LOOT_DATA.RS then
        local allIds = {}
        for _, boss in ipairs(SR.LOOT_DATA.RS) do
            local loot = self:GetBossLoot(boss)
            if loot then
                for _, id in ipairs(loot) do allIds[#allIds + 1] = id end
            end
        end
        self:QueueItemCacheList(allIds)
    end
    self:QueueAllKnownItems()

    -- Ініціалізація випадаючого меню босів
    UIDropDownMenu_Initialize(self.lbBossDD, function(self, level)
        level = level or 1
        if level ~= 1 then return end
        
        local infoICC = UIDropDownMenu_CreateInfo()
        infoICC.text = "--- ЦЛК ---"
        infoICC.isTitle = true
        infoICC.notCheckable = true
        UIDropDownMenu_AddButton(infoICC, level)

        if SR.LOOT_DATA.ICC then
            for i = 1, #SR.LOOT_DATA.ICC do
                local info = UIDropDownMenu_CreateInfo()
                local bossName = SR.LOOT_DATA.ICC[i].name
                local bossVal = "ICC_" .. i
                info.text = bossName
                info.value = bossVal
                info.checked = (SR.lbSelectedBoss == bossVal)
                info.func = function()
                    SR.lbSelectedBoss = bossVal
                    UIDropDownMenu_SetText(SR.lbBossDD, bossName)
                    SR:UpdateLootBrowserItems()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end

        local infoRS = UIDropDownMenu_CreateInfo()
        infoRS.text = "--- Рубінове Святилище ---"
        infoRS.isTitle = true
        infoRS.notCheckable = true
        UIDropDownMenu_AddButton(infoRS, level)

        if SR.LOOT_DATA.RS then
            for i = 1, #SR.LOOT_DATA.RS do
                local info = UIDropDownMenu_CreateInfo()
                local bossName = SR.LOOT_DATA.RS[i].name
                local bossVal = "RS_" .. i
                info.text = bossName
                info.value = bossVal
                info.checked = (SR.lbSelectedBoss == bossVal)
                info.func = function()
                    SR.lbSelectedBoss = bossVal
                    UIDropDownMenu_SetText(SR.lbBossDD, bossName)
                    SR:UpdateLootBrowserItems()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end)
    
    local inst, idxStr = string.match(self.lbSelectedBoss or "", "^(%a+)_(%d+)$")
    if inst and idxStr and SR.LOOT_DATA[inst] and SR.LOOT_DATA[inst][tonumber(idxStr)] then
        UIDropDownMenu_SetText(self.lbBossDD, SR.LOOT_DATA[inst][tonumber(idxStr)].name)
    else
        self.lbSelectedBoss = "ICC_1"
        if SR.LOOT_DATA.ICC and SR.LOOT_DATA.ICC[1] then
            UIDropDownMenu_SetText(self.lbBossDD, SR.LOOT_DATA.ICC[1].name)
        end
    end

    -- Оновлення предметів
    self:UpdateLootBrowserItems()
end

--- Перераховує степер кількості + кнопку "Засофтити xN" для поточного
-- вибраного предмета й гравця-цілі (self.lbTargetPlayer, або сам гравець).
-- Викликається при зміні вибраного предмета, цілі, або після (де)реєстрації SR.
function SR:LayoutReserveButtons()
    if not self.lbReserveBtn then return end
    local myName = self:GetLocalPlayerName()
    local targetName = self.lbTargetPlayer or myName

    local myLimit = self:GetSRLimit(targetName) or 3
    local used = self:GetUsedSRCount(targetName)

    local itemID = self.lbSelectedItemID
    local currentItemCount = 0
    if itemID and self.db.reserves[targetName] then
        local eq = self.GetEquivalentItemIDs and self:GetEquivalentItemIDs(itemID) or { [itemID] = true }
        for _, e in ipairs(self.db.reserves[targetName]) do
            if eq[e.itemID] then
                currentItemCount = e.count or 1
                break
            end
        end
    end

    local maxAllowed = math.max(0, (myLimit - used) + currentItemCount)
    local canEditTarget = self:CanEditPlayerSR(targetName)

    -- Скидаємо степер лише коли реально змінився предмет або ціль —
    -- інакше випадкове оновлення UI (наприклад, чиясь інша дія в рейді)
    -- збивало б кількість, яку гравець щойно почав вибирати.
    local selectionKey = tostring(itemID) .. "|" .. targetName
    if self._lbLastSelectionKey ~= selectionKey then
        self._lbLastSelectionKey = selectionKey
        self.lbReserveCount = (currentItemCount > 0) and currentItemCount or 1
    end
    self.lbReserveCount = self.lbReserveCount or 1
    if maxAllowed > 0 then
        if self.lbReserveCount < 1 then self.lbReserveCount = 1 end
        if self.lbReserveCount > maxAllowed then self.lbReserveCount = maxAllowed end
    end

    self.lbCountFS:SetText(self.lbReserveCount)
    self.lbReserveBtn:SetText(format(SR.L.UI_RESERVE_BTN, self.lbReserveCount))

    local canAct = canEditTarget and itemID ~= nil and maxAllowed > 0
    if canAct then
        self.lbReserveBtn:Enable()
    else
        self.lbReserveBtn:Disable()
    end
    if canAct and self.lbReserveCount > 1 then
        self.lbDecBtn:Enable()
    else
        self.lbDecBtn:Disable()
    end
    if canAct and self.lbReserveCount < maxAllowed then
        self.lbIncBtn:Enable()
    else
        self.lbIncBtn:Disable()
    end
end

function SR:UpdateLootBrowserItems()
    local items = {}

    if self.lbActiveSubTab == "wishlist" then
        items = self:GetWishlistItems()
    else
        local inst, idxStr = string.match(self.lbSelectedBoss or "", "^(%a+)_(%d+)$")
        if inst and idxStr then
            local idx = tonumber(idxStr)
            if SR.LOOT_DATA[inst] and SR.LOOT_DATA[inst][idx] then
                items = self:GetBossLoot(SR.LOOT_DATA[inst][idx])
            end
        end
    end

    -- Автоматичний вибір першого предмета, якщо поточний не в списку
    local found = false
    if self.lbSelectedItemID then
        for _, id in ipairs(items) do
            if id == self.lbSelectedItemID then found = true; break end
        end
    end
    if not found and #items > 0 then
        self.lbSelectedItemID = items[1]
    elseif not found and #items == 0 then
        self.lbSelectedItemID = nil
    end

    self:QueueItemCacheList(items)

    local targetName = self.lbTargetPlayer or self:GetLocalPlayerName()
    local targetReserves = self.db.reserves[targetName]
    local canRemoveForTarget = self:CanEditPlayerSR(targetName)

    for i, itemID in ipairs(items) do
        local row = GetLBItemRow(self.lbItemChild, i)
        row:Show()
        row.itemID = itemID

        local reservedByTarget = false
        if targetReserves then
            local eq = self.GetEquivalentItemIDs and self:GetEquivalentItemIDs(itemID) or { [itemID] = true }
            for _, e in ipairs(targetReserves) do
                if eq[e.itemID] then reservedByTarget = true; break end
            end
        end
        if reservedByTarget and canRemoveForTarget then
            row.removeBtn:Show()
        else
            row.removeBtn:Hide()
        end

        local name, link, quality, _, _, _, _, _, _, tex = GetItemInfo(itemID)
        if name then
            row.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
            -- Колір за якістю
            local r, g, b = GetItemQualityColor(quality or 1)
            row.nameFS:SetText(format("|cff%02x%02x%02x%s|r", r*255, g*255, b*255, name))
        else
            row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.nameFS:SetText("|cff888888[Завантаження #" .. itemID .. "...]|r")
        end

        local srPlayers = self:GetPlayersWithSR(itemID)
        if #srPlayers > 0 then
            local total = 0
            for _, p in ipairs(srPlayers) do total = total + p.count end
            row.srFS:SetText(total .. " SR")
            row.srFS:SetTextColor(0.40, 0.85, 0.32)
        else
            row.srFS:SetText("")
        end

        -- Відображення іконки вішліста + стан сердечка (заповнене й
        -- кольорове, якщо предмет вже в обраному, інакше приглушене сіре)
        if SR:IsInWishlist(itemID) then
            row.wlIcon:Show()
            row.wlBtn.tex:SetVertexColor(1, 0.25, 0.35)
            row.wlBtn.tex:SetDesaturated(false)
        else
            row.wlIcon:Hide()
            row.wlBtn.tex:SetVertexColor(0.5, 0.5, 0.5)
            row.wlBtn.tex:SetDesaturated(true)
        end

        -- Підсвітка, якщо предмет вибрано
        if self.lbSelectedItemID and self.lbSelectedItemID == itemID then
            row.bg:SetVertexColor(0.2, 0.4, 0.25, 0.5)
        else
            row.bg:SetVertexColor(0.12, 0.12, 0.18, (i % 2 == 0) and 0.3 or 0)
        end
    end

    -- Приховування зайвих предметів
    for i = #items + 1, #self.lbItemRows do
        self.lbItemRows[i]:Hide()
    end

    self.lbItemChild:SetHeight(math.max(1, #items * SR.UI.ITEM_H))

    -- Оновлення видимості кнопок Засофтити (x0, x1, x2, x3, x4)
    self:LayoutReserveButtons()
end

function SR:HighlightLBItem(itemID)
    for _, row in ipairs(self.lbItemRows) do
        if row:IsShown() then
            if row.itemID == itemID then
                row.bg:SetVertexColor(0.2, 0.4, 0.25, 0.5)
            else
                local idx = 1
                for j, r in ipairs(self.lbItemRows) do
                    if r == row then idx = j; break end
                end
                row.bg:SetVertexColor(0.12, 0.12, 0.18, (idx % 2 == 0) and 0.3 or 0)
            end
        end
    end

    -- Оновлення кнопок Засофтити при зміні предмета
    self:LayoutReserveButtons()
end


