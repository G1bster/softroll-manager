--------------------------------------------------------------
-- SoftRollManager  —  UI/Ledger.lua
-- Вкладка "Реєстр": список софт-ролів по гравцях і по босах,
-- попап додавання софту гравцю, анонс у чат.
-- Сумісно з WoW 3.3.5a (WotLK)
--------------------------------------------------------------

local SR = SoftRoll

--- Компактний однорядковий підсумок списку SR гравця для Реєстру.
function SR:BuildSRSummaryText(list, maxLen)
    if not list or #list == 0 then return "" end

    local parts = {}
    for _, e in ipairs(list) do
        local name = (e.itemLink and e.itemLink:match("%[(.-)%]")) or ("Предмет #" .. (e.itemID or "?"))
        local count = e.count or 1
        if count > 1 then
            parts[#parts + 1] = name .. " x" .. count
        else
            parts[#parts + 1] = name
        end
    end

    local text = table.concat(parts, ", ")
    if maxLen and #text > maxLen then
        return text:sub(1, maxLen - 3) .. "..."
    end
    return text
end

--- Налаштування кнопки з іконкою для відображення повної підказки предмета при наведенні.
local function AttachItemIconTooltip(btn)
    btn:SetScript("OnEnter", function(self)
        local link = self.itemLink
        if not link and self.itemID then
            link = SR:GetSafeItemLink(self.itemID, nil)
            SR:QueueItemCache(self.itemID)
        end
        if not link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:SetHyperlink(link)
        if self.srCount and self.srCount > 1 then
            GameTooltip:AddLine("Засофчено x" .. self.srCount, 0.4, 0.9, 0.3)
        end
        if self.reservers then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Резерви:", 1, 0.82, 0)
            for _, res in ipairs(self.reservers) do
                local rName = type(res) == "table" and res.name or res
                local count = type(res) == "table" and res.count or 1
                local rc
                local status = ""
                if SR:IsInRaid(rName) then
                    local role = SR:GetPlayerRole(rName)
                    rc = SR.ROLE_COLORS[role] or {r=1,g=1,b=1}
                else
                    rc = {r=0.5, g=0.5, b=0.5} -- сірий для не в рейді
                    status = " (не в рейді)"
                end
                local suffix = count > 1 and (" x" .. count) or ""
                GameTooltip:AddLine("- " .. rName .. status .. suffix, rc.r, rc.g, rc.b)
            end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function(self)
        if self.itemLink then
            HandleModifiedItemClick(self.itemLink)
        end
    end)
end

--- Заповнення кнопок з іконками для одного рядка реєстру зі списку резервів.
function SR:UpdateLedgerItemIcons(row, list, mode)
    list = list or {}
    local iconsPerRow = (mode == "bosses") and 10 or 6
    local maxIcons = 30
    local anyIcon = false

    for j = 1, #list do
        if j > maxIcons then break end
        local btn = row.itemIcons[j]
        if not btn then
            btn = SR:MakeItemIconButton(row.iconStrip, 26)
            local del = btn.delBtn
            del:SetScript("OnClick", function()
                if not btn.itemID then return end
                if SR:CanEditSession() and row.playerName ~= SR:GetLocalPlayerName() then
                    local dialog = StaticPopup_Show("SOFTROLL_CONFIRM_REMOVE_ITEM", btn.itemLink or ("Предмет #" .. btn.itemID), row.playerName)
                    if dialog then dialog.data = { target = row.playerName, itemID = btn.itemID, link = btn.itemLink or ("Предмет #" .. btn.itemID) } end
                else
                    if SR:IsSessionHost() or (SR:IsSessionLeader() and not SR.sessionActive) then
                        SR:RemoveSR(row.playerName, btn.itemID)
                        SR:Print(format(SR.L.PRINT_ITEM_REMOVED_FROM, row.playerName))
                    else
                        SR:SendAddonMsg("R|" .. row.playerName .. "|" .. btn.itemID, "WHISPER", SR.sessionHost)
                        SR:Print(SR.L.PRINT_REMOVE_REQUEST_SENT)
                    end
                end
            end)

            btn.countFS = btn:CreateFontString(nil, "OVERLAY")
            btn.countFS:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
            btn.countFS:SetPoint("BOTTOMRIGHT", 2, -2)
            btn.countFS:SetTextColor(1, 0.85, 0.2)

            btn:Hide()
            AttachItemIconTooltip(btn)
            row.itemIcons[j] = btn
        end

        local entry = list[j]
        local itemID = entry.itemID or self:GetItemIDFromLink(entry.itemLink)
        self:QueueItemCache(itemID)
        local _, link, _, _, _, _, _, _, _, tex = GetItemInfo(itemID or 0)
        btn.itemID   = itemID
        btn.itemLink = self:GetSafeItemLink(itemID, entry.itemLink or link)
        btn.srCount  = entry.count or 1
        btn.reservers = entry.reservers
        if tex then
            btn.icon:SetTexture(tex)
            anyIcon = true
        else
            btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
        if btn.srCount > 1 then
            btn.countFS:SetText("x" .. btn.srCount)
            btn.countFS:Show()
        else
            btn.countFS:Hide()
        end
        
        btn:ClearAllPoints()
        local col = (j - 1) % iconsPerRow
        local rowIdx = math.floor((j - 1) / iconsPerRow)
        btn:SetPoint("TOPLEFT", row.iconStrip, "TOPLEFT", col * 28 + 2, -rowIdx * 28 - 3)
        
        if btn.linkFS then
            btn.linkFS:Hide()
        end
        btn:Show()
        
        local canEdit = SR:CanEditPlayerSR(row.playerName)
        if canEdit and SR.ledgerActiveSubTab ~= "bosses" then
            btn.delBtn:Show()
        else
            btn.delBtn:Hide()
        end

        if btn.itemLink or itemID then
            anyIcon = true
        end
    end

    -- Hide remaining icons
    for j = #list + 1, #row.itemIcons do
        row.itemIcons[j]:Hide()
    end

    local shown = math.min(#list, maxIcons)
    local extra = #list - shown
    if extra > 0 and shown > 0 then
        local btn = row.itemIcons[shown]
        row.moreFS:ClearAllPoints()
        row.moreFS:SetPoint("LEFT", btn, "RIGHT", 4, 0)
        row.moreFS:SetText("+" .. extra)
        row.moreFS:Show()
    else
        row.moreFS:Hide()
    end

    if anyIcon then
        row.summaryFS:Hide()
    elseif #list > 0 then
        row.summaryFS:SetText(self:BuildSRSummaryText(list, 52))
        row.summaryFS:Show()
    else
        row.summaryFS:Hide()
    end
end

--------------------------------------------------------------
-- ПОПАП РЕДАГУВАННЯ ГРАВЦЯ (Додавання софту)
--------------------------------------------------------------
function SR:BuildEditPlayerPopup()
    if self.editPlayerPopup then return end

    local popup = CreateFrame("Frame", "SREditPlayerPopup", UIParent)
    popup:SetSize(400, 140)
    SR:ApplyDialogBackdrop(popup, 0.08, 0.08, 0.12, 0.98)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(100)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop",  popup.StopMovingOrSizing)
    popup:Hide()

    -- Видалено глобальний хук, оскільки ElvUI та інші аддони переписують OnEnter для DropDown кнопок
    local popupTopLine = SR:MakeAccentLine(popup, SR.UI.C.gold[1], SR.UI.C.gold[2], SR.UI.C.gold[3], 0.75)
    popupTopLine:SetPoint("TOPLEFT",  popup, "TOPLEFT",  14, -12)
    popupTopLine:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -14, -12)

    local titleFS = SR:MakeLabel(popup, 12, SR.UI.C.gold[1], SR.UI.C.gold[2], SR.UI.C.gold[3])
    titleFS:SetPoint("TOP", 0, -18)
    popup.titleFS = titleFS

    local ddDesc = SR:MakeLabel(popup, 10, 0.75, 0.75, 0.75, "CENTER")
    ddDesc:SetPoint("TOP", titleFS, "BOTTOM", 0, -10)
    ddDesc:SetText("Виберіть зі списку босів:")

    -- Бос Dropdown
    local bossDD = CreateFrame("Frame", "SREditPlayerBossDD", popup, "UIDropDownMenuTemplate")
    bossDD:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, -60)
    UIDropDownMenu_SetWidth(bossDD, 125)
    popup.bossDD = bossDD

    local function ShowItemTooltip(self)
        if popup.selectedItemID then
            local _, link = GetItemInfo(popup.selectedItemID)
            if link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end
        end
    end
    local function HideItemTooltip()
        GameTooltip:Hide()
    end

    -- Кнопка для іконки вибраного предмета
    local selectedIconBtn = CreateFrame("Button", nil, popup)
    selectedIconBtn:SetSize(28, 28)
    selectedIconBtn:SetPoint("LEFT", bossDD, "RIGHT", -10, 2)
    
    local iconBg = selectedIconBtn:CreateTexture(nil, "BACKGROUND")
    iconBg:SetAllPoints()
    iconBg:SetTexture("Interface\\Buttons\\UI-EmptySlot-White")
    iconBg:SetVertexColor(0.4, 0.4, 0.4, 0.8)

    local selectedIconTex = selectedIconBtn:CreateTexture(nil, "ARTWORK")
    selectedIconTex:SetPoint("TOPLEFT", 2, -2)
    selectedIconTex:SetPoint("BOTTOMRIGHT", -2, 2)
    selectedIconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    popup.selectedIconTex = selectedIconTex

    selectedIconBtn:SetScript("OnEnter", ShowItemTooltip)
    selectedIconBtn:SetScript("OnLeave", HideItemTooltip)

    -- Предмет Dropdown
    local itemDD = CreateFrame("Frame", "SREditPlayerItemDD", popup, "UIDropDownMenuTemplate")
    itemDD:SetPoint("LEFT", selectedIconBtn, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(itemDD, 125)
    popup.itemDD = itemDD

    local addBtn = SR:MakeButton(popup, "Додати", 100, 24)
    addBtn:SetPoint("BOTTOMLEFT", 15, 18)
    addBtn:SetScript("OnClick", function()
        local itemID = popup.selectedItemID
        if not itemID then
            SR:Print(SR.L.PRINT_SELECT_ITEM_FIRST)
            return
        end

        local target = popup.targetPlayer
        local _, link = GetItemInfo(itemID)
        link = link or ("Предмет #" .. itemID)

        local dialog = StaticPopup_Show("SOFTROLL_CONFIRM_ADD_ITEM", link, target)
        if dialog then dialog.data = { itemID = itemID, count = 1, target = target, link = link } end
        
        popup:Hide()
        popup.selectedItemID = nil
        UIDropDownMenu_SetText(popup.itemDD, "Оберіть предмет")
        popup.selectedIconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end)

    local closeBtn = SR:MakeButton(popup, "Закрити", 100, 24)
    closeBtn:SetPoint("BOTTOMRIGHT", -15, 18)
    closeBtn:SetScript("OnClick", function()
        popup:Hide()
    end)

    self.editPlayerPopup = popup
end

function SR:ShowEditPlayerPopup(playerName, anchorFrame)
    if not self.editPlayerPopup then self:BuildEditPlayerPopup() end
    local popup = self.editPlayerPopup

    popup.targetPlayer = playerName
    popup.titleFS:SetText("Додавання софту: " .. playerName)
    
    if anchorFrame then
        popup:ClearAllPoints()
        popup:SetPoint("LEFT", anchorFrame, "RIGHT", 10, 0)
    else
        popup:ClearAllPoints()
        popup:SetPoint("CENTER", UIParent, "CENTER")
    end
    
    -- Ініціалізація Boss DD
    UIDropDownMenu_Initialize(popup.bossDD, function(self, level)
        level = level or 1
        if level ~= 1 then return end
        
        for _, inst in ipairs({"ICC", "RS"}) do
            local infoTitle = UIDropDownMenu_CreateInfo()
            infoTitle.text = "--- " .. inst .. " ---"
            infoTitle.isTitle = true
            infoTitle.notCheckable = true
            UIDropDownMenu_AddButton(infoTitle, level)
            
            if SR.LOOT_DATA[inst] then
                for i = 1, #SR.LOOT_DATA[inst] do
                    local bossName = SR.LOOT_DATA[inst][i].name
                    local bossVal = inst .. "_" .. i
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = bossName
                    info.value = bossVal
                    info.checked = (popup.selectedBoss == bossVal)
                    info.func = function()
                        popup.selectedBoss = bossVal
                        UIDropDownMenu_SetText(popup.bossDD, bossName)
                        -- Очистити itemDD при зміні боса
                        UIDropDownMenu_SetText(popup.itemDD, "Оберіть предмет")
                        popup.selectedItemID = nil
                        popup.selectedIconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end
        end
    end)
    
    -- Встановити текст за замовчуванням
    if not popup.selectedBoss then
        UIDropDownMenu_SetText(popup.bossDD, "Оберіть боса")
    else
        local inst, idxStr = string.match(popup.selectedBoss, "^(%a+)_(%d+)$")
        if inst and idxStr and SR.LOOT_DATA[inst] and SR.LOOT_DATA[inst][tonumber(idxStr)] then
            UIDropDownMenu_SetText(popup.bossDD, SR.LOOT_DATA[inst][tonumber(idxStr)].name)
        else
            UIDropDownMenu_SetText(popup.bossDD, "Оберіть боса")
        end
    end

    -- Ініціалізація Item DD
    UIDropDownMenu_Initialize(popup.itemDD, function(self, level)
        level = level or 1
        if level ~= 1 then return end
        
        if not popup.selectedBoss then return end
        local inst, idxStr = string.match(popup.selectedBoss, "^(%a+)_(%d+)$")
        if not inst or not idxStr then return end
        
        local bossData = SR.LOOT_DATA[inst][tonumber(idxStr)]
        if not bossData then return end
        
        local items = SR:GetBossLoot(bossData)
        for _, itemID in ipairs(items) do
            local itemName, itemLink = GetItemInfo(itemID)
            if not itemName then 
                SR:ForceQueryItem(itemID)
                itemName = "ID: " .. itemID
                itemLink = "ID: " .. itemID
            end
            
            local itemIcon
            if type(GetItemIcon) == "function" then
                itemIcon = GetItemIcon(itemID)
            else
                _, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(itemID)
            end
            itemIcon = itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
            local inlineIcon = "|T" .. itemIcon .. ":14:14:0:0|t "
            
            local info = UIDropDownMenu_CreateInfo()
            info.text = inlineIcon .. itemName
            info.value = itemID
            info.checked = false
            info.arg1 = "SoftRollItem"
            info.arg2 = itemID
            info.func = function()
                UIDropDownMenu_SetText(popup.itemDD, itemName)
                popup.selectedItemID = itemID
                popup.selectedIconTex:SetTexture(itemIcon)
            end
            UIDropDownMenu_AddButton(info, level)

            -- Надійно хукаємо OnEnter для кнопок, бо аддони (ElvUI тощо) можуть обходити глобальний хук
            local btnIndex = 1
            while _G["DropDownList1Button" .. btnIndex] do
                local btn = _G["DropDownList1Button" .. btnIndex]
                if not btn.srHooked then
                    btn:HookScript("OnEnter", function(self)
                        if self.arg1 == "SoftRollItem" and self.arg2 then
                            local _, link = GetItemInfo(self.arg2)
                            if link then
                                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                                GameTooltip:SetHyperlink(link)
                                GameTooltip:Show()
                            end
                        end
                    end)
                    btn.srHooked = true
                end
                btnIndex = btnIndex + 1
            end
        end
    end)
    
    UIDropDownMenu_SetText(popup.itemDD, "Оберіть предмет")
    popup.selectedItemID = nil
    popup.selectedIconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    
    popup:Show()
end


-- ╔══════════════════════════════════════════════════════════╗
-- ║                  ВКЛАДКА 2 — РЕЄСТР SR                  ║
-- ╚══════════════════════════════════════════════════════════╝

function SR:BuildLedger(parent)

    SR.ledgerActiveSubTab = SR.ledgerActiveSubTab or "players"

    -- Вкладки перемикання "По гравцях" / "По босах"
    self.ledgerTabs = {}
    local tabPlayers = SR:MakeFlatTab(parent, "По гравцях", 24)
    tabPlayers:SetPoint("TOPLEFT", 8, -10)
    tabPlayers:SetPoint("RIGHT", parent, "CENTER", -2, 0)
    tabPlayers:SetScript("OnClick", function()
        SR.ledgerActiveSubTab = "players"
        SR:UpdateLedger()
    end)
    self.ledgerTabs.players = tabPlayers

    local tabBosses = SR:MakeFlatTab(parent, "По босах", 24)
    tabBosses:SetPoint("LEFT", parent, "CENTER", 2, 0)
    tabBosses:SetPoint("TOPRIGHT", -8, -10)
    tabBosses:SetScript("OnClick", function()
        SR.ledgerActiveSubTab = "bosses"
        SR:UpdateLedger()
    end)
    self.ledgerTabs.bosses = tabBosses

    -- ── Заголовки стовпців ──
    local hdr = CreateFrame("Frame", nil, parent)
    hdr:SetPoint("TOPLEFT", 8, -42)
    hdr:SetPoint("TOPRIGHT", -8, -42)
    hdr:SetHeight(20)

    self.ledgerHeaders = {}
    local function ColHdr(text, x, w, align, key)
        local fs = SR:MakeLabel(hdr, 9, SR.UI.C.label[1], SR.UI.C.label[2], SR.UI.C.label[3], align or "LEFT")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetText(text)
        if key then self.ledgerHeaders[key] = fs end
    end
    ColHdr("Гравець",         6,   120, "LEFT", "col1")
    ColHdr("Роль",           130,  40, "LEFT", "col2")
    ColHdr("Предмети",       175, 168, "LEFT", "col3")
    ColHdr("Викор.",         340,  34, "CENTER", "col4")
    ColHdr("Дії",           405,  58, "CENTER", "col5")

    local sep = SR:MakeAccentLine(parent, SR.UI.C.sep[1], SR.UI.C.sep[2], SR.UI.C.sep[3], SR.UI.C.sep[4])
    sep:SetPoint("TOPLEFT",  8, -62)
    sep:SetPoint("TOPRIGHT", -8, -62)

    self.ledgerEmptyFS = SR:MakeLabel(parent, 13, 0.35, 0.35, 0.40, "CENTER")
    self.ledgerEmptyFS:SetPoint("CENTER", 0, 20)
    self.ledgerEmptyFS:SetWidth(420)
    self.ledgerEmptyFS:SetText("Ще немає зареєстрованих софт-ролів")
    self.ledgerEmptyFS:Hide()
    self.ledgerEmptySub = SR:MakeLabel(parent, 10, 0.28, 0.28, 0.34, "CENTER")
    self.ledgerEmptySub:SetPoint("TOP", self.ledgerEmptyFS, "BOTTOM", 0, -4)
    self.ledgerEmptySub:SetWidth(380)
    self.ledgerEmptySub:SetText("Гравці можуть додати предмети через чат або Огляд луту")
    self.ledgerEmptySub:Hide()

    -- ── Фрейм прокрутки ──
    local sf = CreateFrame("ScrollFrame", "SRLedgerScroll", parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -64)
    sf:SetPoint("BOTTOMRIGHT", -28, 42)
    sf:SetScript("OnSizeChanged", function(self)
        if SR.ledgerChild then
            SR.ledgerChild:SetWidth(self:GetWidth())
        end
    end)

    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(sf:GetWidth() > 0 and sf:GetWidth() or 462)
    child:SetHeight(1)
    sf:SetScrollChild(child)
    self.ledgerScroll = sf
    self.ledgerChild = child
    self.ledgerRows  = {}

    -- ── Кнопки внизу ──
    local clearAll = SR:MakeButton(parent, "Очистити всі софти", 138, 24)
    clearAll:SetPoint("BOTTOMLEFT", 8, 10)
    clearAll:SetScript("OnClick", function()
        if SR:IsSessionReadOnly() then return end
        StaticPopup_Show("SOFTROLL_CONFIRM_CLEAR")
    end)
    self.ledgerClearAll = clearAll

    local announceBtn = SR:MakeButton(parent, "Анонс у рейд", 140, 24)
    announceBtn:SetPoint("BOTTOMRIGHT", -8, 10)
    
    local announceMenu = CreateFrame("Frame", "SoftRollAnnounceMenu", parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(announceMenu, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Анонсувати всі софти"
        info.func = function() SR:AnnounceAllSR() end
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
        
        info.text = "Анонсувати неповні софти"
        info.func = function() SR:AnnounceMissingSR() end
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

        info.text = "Інструкція в чат (для гравців)"
        info.func = function()
            if not SR:CanEditSession() then
                SR:Print(SR.L.PRINT_ONLY_LEADER_ANNOUNCE)
                return
            end
            local chatType = "SAY"
            if GetNumRaidMembers() > 0 then
                chatType = "RAID_WARNING"
            elseif GetNumPartyMembers() > 0 then
                chatType = "PARTY"
            end
            SendChatMessage(SR.L.INSTRUCT_RESERVE, chatType)
            if SR.db.srMode ~= "rs_x1" then
                SendChatMessage(SR.L.INSTRUCT_DOUBLE, chatType)
            end
            SendChatMessage(SR.L.INSTRUCT_COMMANDS, chatType)
        end
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
    end)
    
    announceBtn:SetScript("OnClick", function(self)
        if DropDownList1 and DropDownList1:IsShown() and UIDROPDOWNMENU_OPEN_MENU == announceMenu then
            CloseDropDownMenus()
            return
        end
        ToggleDropDownMenu(1, nil, announceMenu, self, 0, 0)
    end)
    self.ledgerAnnounceBtn = announceBtn

    -- Діалог підтвердження
    StaticPopupDialogs["SOFTROLL_CONFIRM_CLEAR"] = {
        text         = SR.L.POPUP_CONFIRM_CLEAR_ALL,
        button1      = "Так, очистити",
        button2      = "Скасувати",
        OnAccept     = function()
            local chatType = (GetNumRaidMembers() > 0) and "RAID" or "PARTY"
            if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then chatType = "SAY" end
            
            if SR:IsSessionHost() or (SR:IsSessionLeader() and not SR.sessionActive) then
                SR:ResetAllSR()
                SendChatMessage(SR.L.ALL_SRS_CLEARED, chatType)
            else
                SR:SendAddonMsg("W", "WHISPER", SR.sessionHost)
                SR:Print(SR.L.PRINT_CLEAR_ALL_REQUEST_SENT)
                SendChatMessage(SR.L.ALL_SRS_CLEARED, chatType)
            end
        end,
        timeout      = 0,
        whileDead    = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["SOFTROLL_CONFIRM_CLEAR_PLAYER"] = {
        text         = SR.L.POPUP_CONFIRM_CLEAR_PLAYER,
        button1      = "Очистити",
        button2      = "Скасувати",
        OnAccept     = function(self, data)
            data = data or (self and self.data)
            if not data or not data.target then return end
            local target = data.target
            
            if SR:IsSessionHost() or (SR:IsSessionLeader() and not SR.sessionActive) then
                SR:ClearPlayerSR(target)
                SR:Print(format(SR.L.PRINT_SRS_CLEARED_FOR, target))
                local chatType = (GetNumRaidMembers() > 0) and "RAID" or "PARTY"
                if target ~= SR:GetLocalPlayerName() then
                    SendChatMessage(format(SR.L.PLAYER_SRS_CLEARED, target), chatType)
                end
            else
                SR:SendAddonMsg("C|" .. target, "WHISPER", SR.sessionHost)
                SR:Print(SR.L.PRINT_CLEAR_PLAYER_SENT)
            end
        end,
        timeout      = 0,
        whileDead    = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["SOFTROLL_CONFIRM_REMOVE_ITEM"] = {
        text         = SR.L.POPUP_CONFIRM_REMOVE_ITEM,
        button1      = "Видалити",
        button2      = "Скасувати",
        OnAccept     = function(self, data)
            data = data or (self and self.data)
            if not data or not data.target or not data.itemID then return end
            local chatType = (GetNumRaidMembers() > 0) and "RAID" or "PARTY"
            if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then chatType = "SAY" end
            
            if SR:IsSessionHost() or (SR:IsSessionLeader() and not SR.sessionActive) then
                SR:RemoveSR(data.target, data.itemID)
                SR:Print(format(SR.L.PRINT_ITEM_REMOVED_FROM, data.target))
                SendChatMessage(format(SR.L.SR_REMOVED_FOR_PLAYER, (data.link or ("Предмет #" .. data.itemID)), data.target), chatType)
            else
                SR:SendAddonMsg("R|" .. data.target .. "|" .. data.itemID, "WHISPER", SR.sessionHost)
                SR:Print(SR.L.PRINT_REMOVE_REQUEST_SENT)
            end
        end,
        timeout      = 0,
        whileDead    = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["SOFTROLL_CONFIRM_ADD_ITEM"] = {
        text         = SR.L.POPUP_CONFIRM_ADD_ITEM,
        button1      = "Додати",
        button2      = "Скасувати",
        OnAccept     = function(self, data)
            data = data or (self and self.data)
            if not data or not data.target or not data.itemID then return end
            local ok = SR:RequestSRFromUI(data.itemID, 1, data.target)
            if ok == true then
                local chatType = (GetNumRaidMembers() > 0) and "RAID" or "PARTY"
                if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then chatType = "SAY" end
                SendChatMessage(format(SR.L.SR_ADDED_FOR_PLAYER, (data.link or ("Предмет #" .. data.itemID)), data.target), chatType)
            end
        end,
        timeout      = 0,
        whileDead    = true,
        hideOnEscape = true,
    }
end

--------------------------------------------------------------
-- Фабрика рядків Реєстру
--------------------------------------------------------------
local function GetLedgerRow(container, index)
    local rows = SR.ledgerRows
    if rows[index] then return rows[index] end

    local row = CreateFrame("Frame", nil, container)
    row:SetHeight(SR.UI.LEDGER_ROW_H)
    row:SetPoint("TOPLEFT",  0, -(index - 1) * SR.UI.LEDGER_ROW_H)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * SR.UI.LEDGER_ROW_H)

    -- Чергування фону
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bg:SetVertexColor(0.12, 0.12, 0.18, (index % 2 == 0) and 0.35 or 0)
    row.bg = bg

    -- Гравець (наведення = підсумок у підказці)
    row.nameFS = SR:MakeLabel(row, 11, 1, 1, 1, "LEFT")
    row.nameFS:SetPoint("LEFT", 6, 0)
    row.nameFS:SetWidth(120)

    row.nameBtn = CreateFrame("Button", nil, row)
    row.nameBtn:SetPoint("TOPLEFT", 6, -2)
    row.nameBtn:SetSize(120, SR.UI.LEDGER_ROW_H - 4)
    row.nameBtn:SetHighlightTexture("Interface\\ChatFrame\\ChatFrameBackground")
    local nameHl = row.nameBtn:GetHighlightTexture()
    if nameHl then nameHl:SetVertexColor(0.3, 0.4, 0.6, 0.15) end
    row.nameBtn:SetScript("OnEnter", function(self)
        if SR.ledgerActiveSubTab == "bosses" then return end
        local pName = self:GetParent().playerName
        if pName then SR:ShowPlayerSRTooltip(self, pName) end
    end)
    row.nameBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Іконка "не в рейді" — замість ролі (та ж позиція, x=130)
    local notInRaidIcon = CreateFrame("Button", nil, row)
    notInRaidIcon:SetSize(16, 16)
    notInRaidIcon:SetPoint("LEFT", 130, 0)
    local notInRaidTex = notInRaidIcon:CreateTexture(nil, "ARTWORK")
    notInRaidTex:SetAllPoints()
    notInRaidTex:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
    notInRaidIcon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Відсутній у рейді", 1, 0.4, 0.4)
        GameTooltip:AddLine("Гравець більше не в рейді.\nЙого резерви збережені.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    notInRaidIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    notInRaidIcon:Hide()
    row.notInRaidIcon = notInRaidIcon

    -- Роль
    row.roleFS = SR:MakeLabel(row, 10, 1, 1, 1, "LEFT")
    row.roleFS:SetPoint("LEFT", 130, 0)
    row.roleFS:SetWidth(40)

    -- Кнопка анонсу
    local annBtn = CreateFrame("Button", nil, row)
    annBtn:SetSize(18, 18)
    annBtn:SetPoint("LEFT", 380, 0)
    annBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
    annBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
    annBtn:GetNormalTexture():SetVertexColor(1, 0.8, 0)
    annBtn:SetScript("OnClick", function(self)
        if SR:IsSessionReadOnly() then return end
        if SR.ledgerActiveSubTab == "bosses" then
            if not SR.bossAnnounceMenu then
                SR.bossAnnounceMenu = CreateFrame("Frame", "SRBossAnnounceMenu", UIParent, "UIDropDownMenuTemplate")
            end
            if DropDownList1 and DropDownList1:IsShown() and UIDROPDOWNMENU_OPEN_MENU == SR.bossAnnounceMenu then
                if SR.bossAnnounceMenu.lastAnchor == self then
                    CloseDropDownMenus()
                    SR.bossAnnounceMenu.lastAnchor = nil
                    return
                else
                    CloseDropDownMenus()
                end
            end
            SR.bossAnnounceMenu.lastAnchor = self
            UIDropDownMenu_Initialize(SR.bossAnnounceMenu, function(menu, level)
                level = level or 1
                if level == 1 then
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = "Анонс усіх предметів боса"
                    info.notCheckable = true
                    info.func = function()
                        SR:AnnounceBossItems(row.playerName, row.bossItems)
                    end
                    UIDropDownMenu_AddButton(info, level)

                    if row.bossItems and #row.bossItems > 0 then
                        local infoSub = UIDropDownMenu_CreateInfo()
                        infoSub.text = "Анонс окремого предмета"
                        infoSub.notCheckable = true
                        infoSub.hasArrow = true
                        infoSub.value = "single_items"
                        UIDropDownMenu_AddButton(infoSub, level)
                    end
                elseif level == 2 and UIDROPDOWNMENU_MENU_VALUE == "single_items" then
                    for _, itemEntry in ipairs(row.bossItems) do
                        local info2 = UIDropDownMenu_CreateInfo()
                        local name, link, quality, _, _, _, _, _, _, texture = GetItemInfo(itemEntry.itemID)
                        local fallbackName = name or (itemEntry.itemLink and itemEntry.itemLink:match("%[(.-)%]")) or ("Предмет #" .. itemEntry.itemID)
                        if name then
                            local r, g, b = GetItemQualityColor(quality or 1)
                            local hex = string.format("ff%02x%02x%02x", (r or 1)*255, (g or 1)*255, (b or 1)*255)
                            info2.text = "|T" .. texture .. ":14:14:0:0:64:64:4:60:4:60|t |c" .. hex .. name .. "|r"
                        else
                            info2.text = "|TInterface\\Icons\\INV_Misc_QuestionMark:14:14:0:0:64:64:4:60:4:60|t " .. fallbackName
                        end
                        info2.notCheckable = true
                        info2.func = function()
                            local parts = {}
                            for _, res in ipairs(itemEntry.reservers) do
                                local rName = type(res) == "table" and res.name or res
                                local count = type(res) == "table" and res.count or 1
                                if count > 1 then
                                    table.insert(parts, rName .. " x" .. count)
                                else
                                    table.insert(parts, rName)
                                end
                            end
                            local linkOut = itemEntry.itemLink or ("Предмет #" .. (itemEntry.itemID or "?"))
                            local msg = format(SR.L.ANNOUNCE_ITEM_RESERVERS, linkOut, table.concat(parts, ", "))
                            local chatType = "SAY"
                            if GetNumRaidMembers() > 0 then
                                chatType = "RAID"
                            elseif GetNumPartyMembers() > 0 then
                                chatType = "PARTY"
                            end
                            SendChatMessage(msg, chatType)
                        end
                        info2.arg1 = "SoftRollBossItem"
                        info2.arg2 = itemEntry.itemLink or fallbackName
                        UIDropDownMenu_AddButton(info2, level)
                        
                        local listFrame = _G["DropDownList" .. level]
                        local button = _G["DropDownList" .. level .. "Button" .. listFrame.numButtons]
                        if button and not button.srHooked then
                            button:HookScript("OnEnter", function(self)
                                if self.arg1 == "SoftRollBossItem" and self.arg2 then
                                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                                    if type(self.arg2) == "string" and self.arg2:match("item:") then
                                        GameTooltip:SetHyperlink(self.arg2)
                                    else
                                        GameTooltip:SetText(tostring(self.arg2), 1, 1, 1)
                                    end
                                    GameTooltip:Show()
                                end
                            end)
                            button:HookScript("OnLeave", function(self)
                                if self.arg1 == "SoftRollBossItem" then
                                    GameTooltip:Hide()
                                end
                            end)
                            button.srHooked = true
                        end
                    end
                end
            end)
            ToggleDropDownMenu(1, nil, SR.bossAnnounceMenu, self, 0, 0)
        else
            SR:AnnouncePlayerSR(row.playerName)
        end
    end)
    annBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if SR.ledgerActiveSubTab == "bosses" then
            GameTooltip:SetText("Анонсувати луп боса в чат")
        else
            GameTooltip:SetText("Анонсувати софти гравця в чат")
        end
        GameTooltip:Show()
    end)
    annBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.annBtn = annBtn

    -- Ряд іконок предметів
    row.iconStrip = CreateFrame("Frame", nil, row)
    row.iconStrip:SetPoint("LEFT", 175, 0)
    row.iconStrip:SetSize(168, SR.UI.LEDGER_ROW_H)
    row.itemIcons = {}

    for j = 1, SR.UI.LEDGER_MAX_ICONS do
        local btn = SR:MakeItemIconButton(row.iconStrip, 26)
        btn:SetPoint("LEFT", (j - 1) * 28 + 2, 0)

        local del = btn.delBtn
        del:SetScript("OnClick", function()
            if not btn.itemID then return end
            if SR:CanEditSession() and row.playerName ~= SR:GetLocalPlayerName() then
                local dialog = StaticPopup_Show("SOFTROLL_CONFIRM_REMOVE_ITEM", btn.itemLink or ("Предмет #" .. btn.itemID), row.playerName)
                if dialog then dialog.data = { target = row.playerName, itemID = btn.itemID, link = btn.itemLink or ("Предмет #" .. btn.itemID) } end
            else
                if SR:IsSessionHost() or (SR:IsSessionLeader() and not SR.sessionActive) then
                    SR:RemoveSR(row.playerName, btn.itemID)
                    SR:Print(format(SR.L.PRINT_ITEM_REMOVED_FROM, row.playerName))
                else
                    SR:SendAddonMsg("R|" .. row.playerName .. "|" .. btn.itemID, "WHISPER", SR.sessionHost)
                    SR:Print(SR.L.PRINT_REMOVE_REQUEST_SENT)
                end
            end
        end)

        btn.countFS = btn:CreateFontString(nil, "OVERLAY")
        btn.countFS:SetFont("Fonts\\ARIALN.TTF", 11, "OUTLINE")
        btn.countFS:SetPoint("BOTTOMRIGHT", 2, -2)
        btn.countFS:SetTextColor(1, 0.85, 0.2)

        btn:Hide()
        AttachItemIconTooltip(btn)
        row.itemIcons[j] = btn
    end

    row.moreFS = SR:MakeLabel(row.iconStrip, 10, 0.55, 0.55, 0.55, "LEFT")
    row.moreFS:SetPoint("LEFT", SR.UI.LEDGER_MAX_ICONS * 28 + 4, 0)
    row.moreFS:SetWidth(60)
    row.moreFS:Hide()

    -- Текстовий резерв, якщо іконки ще не закешовані
    row.summaryFS = SR:MakeLabel(row, 10, 0.55, 0.55, 0.55, "LEFT")
    row.summaryFS:SetPoint("LEFT", 175, -10)
    row.summaryFS:SetWidth(160)

    -- "Викор." (X/Y) та кнопки дій прив'язані до ПРАВОГО краю смуги іконок
    -- (не до фіксованих координат) — інакше при LEDGER_MAX_ICONS=6 повністю
    -- заповнена смуга (175..343px) наїжджає на текст "Викор." при
    -- жорсткому x=320, що досяжно для гравця з персональним override ліміту.
    --
    -- Ширини/зазори тут навмисно компактні: реальна видима ширина рядка
    -- (446px — вужча за 480px "hdr", бо рядки всередині ScrollFrame з
    -- вирахуваним місцем під скролбар) залишає від правого краю смуги
    -- іконок (343) лише ~100px на "Викор." + 3 кнопки дій. Ширші значення
    -- виштовхували clearBtn за межі видимої/непроскроленої області, де
    -- ScrollFrame його обрізає — кнопка "Очистити всі софти" гравця
    -- ставала невидимою.
    row.usedFS = SR:MakeLabel(row, 10, 0.75, 0.75, 0.75, "CENTER")
    row.usedFS:SetPoint("LEFT", row.iconStrip, "RIGHT", 8, 0)
    row.usedFS:SetWidth(34)

    row.editBtn = CreateFrame("Button", nil, row)
    row.editBtn:SetSize(16, 16)
    row.editBtn:SetPoint("LEFT", row.usedFS, "RIGHT", 2, 0)
    row.editBtn:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    row.editBtn:SetHighlightTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    if row.editBtn:GetHighlightTexture() then
        row.editBtn:GetHighlightTexture():SetBlendMode("ADD")
    end
    row.editBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Додати софти")
        GameTooltip:Show()
    end)
    row.editBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.clearBtn = CreateFrame("Button", nil, row)
    row.clearBtn:SetSize(18, 18)
    row.clearBtn:SetPoint("LEFT", row.editBtn, "RIGHT", 2, 0)
    row.clearBtn:SetNormalTexture("Interface\\BUTTONS\\UI-GroupLoot-Pass-Up")
    row.clearBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-GroupLoot-Pass-Highlight")
    row.clearBtn:SetPushedTexture("Interface\\BUTTONS\\UI-GroupLoot-Pass-Down")
    row.clearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Очистити всі софти")
        GameTooltip:Show()
    end)
    row.clearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    rows[index] = row
    return row
end

--------------------------------------------------------------
-- ОНОВЛЕННЯ РЕЄСТРУ (Гравці)
--------------------------------------------------------------
function SR:UpdateLedgerPlayers()
    if not self.ledgerChild then return end

    self:UpdateAdminReadOnly()
    
    local canEditSession = self:CanEditSession()
    local readOnly = self:IsSessionReadOnly()

    if not canEditSession then
        self.ledgerClearAll:Hide()
        self.ledgerAnnounceBtn:Hide()
    else
        -- Очистити всі: тільки хост сесії або РЛ без активної сесії (не ко-хости)
        local canClearAll = self:IsSessionHost() or (not self.sessionActive and self:IsSessionLeader())
        if canClearAll then
            self.ledgerClearAll:Show()
            self.ledgerClearAll:Enable()
        else
            self.ledgerClearAll:Hide()
        end
        self.ledgerAnnounceBtn:Show()
    end

    -- Відновлюємо колонки для гравців
    if self.ledgerHeaders then
        self.ledgerHeaders.col1:SetText("Гравець")
        self.ledgerHeaders.col2:SetText("Роль")
        self.ledgerHeaders.col2:Show()
        self.ledgerHeaders.col4:Show()
        -- Вирівнюємо з новою позицією row.usedFS (прив'язана до правого краю
        -- смуги іконок, а не до фіксованого x) — див. GetLedgerRow.
        self.ledgerHeaders.col4:SetPoint("LEFT", self.ledgerHeaders.col3, "RIGHT", 8, 0)
        self.ledgerHeaders.col5:Show()
        self.ledgerHeaders.col5:SetWidth(58)
        self.ledgerHeaders.col5:SetPoint("LEFT", self.ledgerHeaders.col4, "RIGHT", 2, 0)
    end

    -- ── Збираємо список гравців ──
    -- Група 1: Всі учасники рейду (навіть без софтів), сортовані за роллю
    -- Група 2: Гравці зі списку резервів, яких немає в рейді (сірим)

    local raidMembers = self:GetRaidMembers()
    local raidSet = {}
    for _, m in ipairs(raidMembers) do
        raidSet[m.name] = m
    end

    local inRaidPlayers = {}
    for _, m in ipairs(raidMembers) do
        local list = self.db.reserves[m.name] or {}
        inRaidPlayers[#inRaidPlayers + 1] = {
            name   = m.name,
            role   = self:GetPlayerRole(m.name),
            list   = list,
            used   = self:GetUsedSRCount(m.name),
            limit  = self:GetSRLimit(m.name),
            rank   = m.rank,
            class  = m.class,
            inRaid = true,
        }
    end
    table.sort(inRaidPlayers, function(a, b)
        local wa = SR:GetRoleSortWeight(a.name, a.rank or 0)
        local wb = SR:GetRoleSortWeight(b.name, b.rank or 0)
        if wa ~= wb then return wa < wb end
        return a.name < b.name
    end)

    local offRaidPlayers = {}
    for pName, list in pairs(self.db.reserves) do
        if not raidSet[pName] and list and #list > 0 then
            offRaidPlayers[#offRaidPlayers + 1] = {
                name   = pName,
                role   = self:GetPlayerRole(pName),
                list   = list,
                used   = self:GetUsedSRCount(pName),
                limit  = self:GetSRLimit(pName),
                rank   = 0,
                class  = nil,
                inRaid = false,
            }
        end
    end
    table.sort(offRaidPlayers, function(a, b)
        local wa = SR:GetRoleSortWeight(a.name, 0)
        local wb = SR:GetRoleSortWeight(b.name, 0)
        if wa ~= wb then return wa < wb end
        return a.name < b.name
    end)

    local players = {}
    for _, p in ipairs(inRaidPlayers)  do players[#players + 1] = p end
    for _, p in ipairs(offRaidPlayers) do players[#players + 1] = p end

    local hasContent = #raidMembers > 0 or #offRaidPlayers > 0
    if not hasContent then
        self.ledgerEmptyFS:Show()
        if self.ledgerEmptySub then self.ledgerEmptySub:Show() end
        if self.ledgerScroll then self.ledgerScroll:Hide() end
    else
        self.ledgerEmptyFS:Hide()
        if self.ledgerEmptySub then self.ledgerEmptySub:Hide() end
        if self.ledgerScroll then self.ledgerScroll:Show() end
    end

    if self.ledgerScroll and self.ledgerChild then
        self.ledgerChild:SetWidth(self.ledgerScroll:GetWidth())
    end

    local currentY = 0
    for i, p in ipairs(players) do
        local row = GetLedgerRow(self.ledgerChild, i)
        
        local numItems = #(p.list or {})
        local lines = math.ceil(numItems / 6)
        if lines < 1 then lines = 1 end
        local rowH = math.max(SR.UI.LEDGER_ROW_H, lines * 28 + 4)
        
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 8, -currentY)
        row:SetPoint("TOPRIGHT", -8, -currentY)
        row:SetHeight(rowH)
        row:Show()

        if row.iconStrip then
            row.iconStrip:ClearAllPoints()
            row.iconStrip:SetPoint("TOPLEFT", row, "TOPLEFT", 175, 0)
            row.iconStrip:SetHeight(rowH)
        end

        -- Попереднє кешування предметів з сервера
        local idList = {}
        for _, e in ipairs(p.list) do
            if e.itemID then idList[#idList + 1] = e.itemID end
        end
        self:QueueItemCacheList(idList)

        -- Ім'я (disabled-стиль для гравців не з рейду)
        local cc
        if p.inRaid then
            if p.class then
                cc = self:GetClassColor(p.class)
            else
                cc = { r = 0.8, g = 0.8, b = 0.8 }
            end
        else
            cc = { r = 0.40, g = 0.40, b = 0.42 }  -- сірий — немає в рейді
        end
        row.playerName = p.name
        row.nameFS:SetText(self:ColorText(p.name, cc.r, cc.g, cc.b))

        -- Іконка "не в рейді" / Роль (взаємовиключно)
        local rc = self.ROLE_COLORS[p.role]
        if p.inRaid then
            if row.notInRaidIcon then row.notInRaidIcon:Hide() end
            row.roleFS:Show()
            row.roleFS:SetText(self.ROLE_SHORT[p.role] or "?")
            row.roleFS:SetTextColor(rc.r, rc.g, rc.b)
        else
            row.roleFS:Hide()
            if row.notInRaidIcon then row.notInRaidIcon:Show() end
        end

        -- Іконки предметів
        self:UpdateLedgerItemIcons(row, p.list, "players")

        -- Progress bar SR
        if row.usedFS then
            row.usedFS:Show()
            row.usedFS:SetText(p.used .. " / " .. p.limit)
            if p.used >= p.limit then
                row.usedFS:SetTextColor(0.9, 0.3, 0.3)
            elseif p.used > 0 then
                row.usedFS:SetTextColor(1.0, 0.8, 0.2)
            else
                row.usedFS:SetTextColor(0.5, 0.5, 0.5)
            end
        end

        row.clearBtn:SetScript("OnClick", function()
            local dialog = StaticPopup_Show("SOFTROLL_CONFIRM_CLEAR_PLAYER", p.name)
            if dialog then dialog.data = { target = p.name } end
        end)

        row.editBtn:SetScript("OnClick", function()
            if SR:IsSessionReadOnly() then return end
            SR:ShowEditPlayerPopup(p.name, row.editBtn)
        end)
        
        local readOnly = SR:IsSessionReadOnly()
        local canEdit = SR:CanEditPlayerSR(p.name)

        local canEditSession = SR:CanEditSession()

        -- Кнопки дій прив'язані ланцюжком до правого краю usedFS (яка сама
        -- прив'язана до смуги іконок) — не до фіксованих x, інакше вони
        -- розходяться з колонкою "Дії" щоразу, коли змінюється склад
        -- видимих кнопок або ширина попередніх колонок.
        local showAnn = canEditSession
        local showEdit = canEditSession
        local showClear = canEdit

        local anchor = row.usedFS

        if showAnn then
            row.annBtn:Show()
            row.annBtn:ClearAllPoints()
            row.annBtn:SetPoint("LEFT", anchor, "RIGHT", 2, 0)
            anchor = row.annBtn
        else
            row.annBtn:Hide()
        end

        if showEdit then
            row.editBtn:Show()
            row.editBtn:ClearAllPoints()
            row.editBtn:SetPoint("LEFT", anchor, "RIGHT", 2, 0)
            anchor = row.editBtn
        else
            row.editBtn:Hide()
        end

        if showClear then
            row.clearBtn:Show()
            row.clearBtn:ClearAllPoints()
            row.clearBtn:SetPoint("LEFT", anchor, "RIGHT", 2, 0)
        else
            row.clearBtn:Hide()
        end

        -- Фон рядку: для не-рейдерів помітно сіріший
        if p.inRaid then
            row.bg:SetVertexColor(0.12, 0.12, 0.18, (i % 2 == 0) and 0.35 or 0)
        else
            row.bg:SetVertexColor(0.08, 0.08, 0.10, 0.55)
        end
        currentY = currentY + rowH
    end

    -- Приховування зайвих рядків
    for i = #players + 1, #self.ledgerRows do
        self.ledgerRows[i]:Hide()
    end

    self.ledgerChild:SetHeight(math.max(1, currentY))
end

--------------------------------------------------------------
-- ОНОВЛЕННЯ РЕЄСТРУ (Боси)
--------------------------------------------------------------
function SR:UpdateLedgerBosses()
    if not self.ledgerChild then return end

    local canEditSession = SR:CanEditSession()
    if not canEditSession then
        if self.ledgerClearAll then self.ledgerClearAll:Hide() end
        if self.ledgerAnnounceBtn then self.ledgerAnnounceBtn:Hide() end
    else
        local canClearAll = SR:IsSessionHost() or (not self.sessionActive and SR:IsSessionLeader())
        if canClearAll then
            if self.ledgerClearAll then
                self.ledgerClearAll:Show()
                self.ledgerClearAll:Enable()
            end
        else
            if self.ledgerClearAll then self.ledgerClearAll:Hide() end
        end
        if self.ledgerAnnounceBtn then self.ledgerAnnounceBtn:Show() end
    end

    -- Налаштовуємо колонки для босів
    if self.ledgerHeaders then
        self.ledgerHeaders.col1:SetText("Бос")
        self.ledgerHeaders.col2:Hide()
        self.ledgerHeaders.col4:Hide()
        self.ledgerHeaders.col5:Hide()
    end

    -- Збираємо дані
    local bossMap = {}
    local bossOrder = {}
    local currentInst = self.db.instance or "ICC"
    local lootData = self.LOOT_DATA[currentInst] or {}

    for i, b in ipairs(lootData) do
        bossMap[b.name] = { name = b.name, order = i, items = {} }
        bossOrder[#bossOrder + 1] = b.name
    end
    bossMap["Trash/Інше"] = { name = "Trash/Інше", order = 999, items = {} }
    bossOrder[#bossOrder + 1] = "Trash/Інше"

    for pName, list in pairs(self.db.reserves) do
        for _, e in ipairs(list) do
            local itemID = e.itemID or self:GetItemIDFromLink(e.itemLink)
            if itemID then
                local foundBoss = "Trash/Інше"
                local eq = self:GetEquivalentItemIDs(itemID)
                for _, b in ipairs(lootData) do
                    local lootH = b.loot25H or {}
                    local lootN = b.loot25N or {}
                    local drops = false
                    for _, id in ipairs(lootH) do
                        if eq[id] then 
                            drops = true 
                            break 
                        end 
                    end
                    if not drops then
                        for _, id in ipairs(lootN) do 
                            if eq[id] then 
                                drops = true 
                                break 
                            end 
                        end
                    end
                    if drops then
                        foundBoss = b.name
                        break
                    end
                end

                local bItems = bossMap[foundBoss].items
                local existing = nil
                for _, itemEntry in ipairs(bItems) do
                    if eq[itemEntry.itemID] then
                        existing = itemEntry
                        break
                    end
                end

                if existing then
                    existing.count = existing.count + (e.count or 1)
                    local foundRes = false
                    for _, res in ipairs(existing.reservers) do
                        if res.name == pName then
                            res.count = res.count + (e.count or 1)
                            foundRes = true
                            break
                        end
                    end
                    if not foundRes then
                        table.insert(existing.reservers, {name = pName, count = e.count or 1})
                    end
                else
                    table.insert(bItems, {
                        itemID = itemID,
                        itemLink = e.itemLink,
                        count = e.count or 1,
                        reservers = { {name = pName, count = e.count or 1} }
                    })
                end
            end
        end
    end

    local rowsData = {}
    for _, bName in ipairs(bossOrder) do
        local b = bossMap[bName]
        if #b.items > 0 then
            table.sort(b.items, function(i1, i2) return (i1.count or 0) > (i2.count or 0) end)
            rowsData[#rowsData + 1] = b
        end
    end

    if #rowsData == 0 then
        self.ledgerEmptyFS:Show()
        if self.ledgerEmptySub then self.ledgerEmptySub:Show() end
        if self.ledgerScroll then self.ledgerScroll:Hide() end
    else
        self.ledgerEmptyFS:Hide()
        if self.ledgerEmptySub then self.ledgerEmptySub:Hide() end
        if self.ledgerScroll then self.ledgerScroll:Show() end
    end

    local currentY = 0
    for i, bData in ipairs(rowsData) do
        local row = GetLedgerRow(self.ledgerChild, i)
        
        local numItems = #(bData.items or {})
        local lines = math.ceil(numItems / 10)
        if lines < 1 then lines = 1 end
        local rowH = math.max(SR.UI.LEDGER_ROW_H, lines * 28 + 4)
        
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 8, -currentY)
        row:SetPoint("TOPRIGHT", -8, -currentY)
        row:SetHeight(rowH)
        row:Show()

        if row.iconStrip then
            row.iconStrip:ClearAllPoints()
            row.iconStrip:SetPoint("TOPLEFT", row, "TOPLEFT", 160, 0)
            row.iconStrip:SetHeight(rowH)
        end

        local idList = {}
        for _, e in ipairs(bData.items) do
            if e.itemID then idList[#idList + 1] = e.itemID end
        end
        self:QueueItemCacheList(idList)

        row.playerName = bData.name
        row.bossItems = bData.items
        row.nameFS:SetText(self:ColorText(bData.name, 1, 0.82, 0))
        row.roleFS:Hide()
        if row.notInRaidIcon then row.notInRaidIcon:Hide() end
        if row.usedFS then row.usedFS:Hide() end
        row.clearBtn:Hide()
        if row.editBtn then row.editBtn:Hide() end
        
        if not self:CanEditSession() then
            row.annBtn:Hide()
        else
            row.annBtn:Show()
            row.annBtn:ClearAllPoints()
            row.annBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 130, -3)
        end

        self:UpdateLedgerItemIcons(row, bData.items, "bosses")

        row.bg:SetVertexColor(0.12, 0.12, 0.18, (i % 2 == 0) and 0.35 or 0)
        currentY = currentY + rowH
    end

    for i = #rowsData + 1, #self.ledgerRows do
        self.ledgerRows[i]:Hide()
    end

    self.ledgerChild:SetHeight(math.max(1, currentY))
end

--------------------------------------------------------------
-- ДИСПЕТЧЕР ОНОВЛЕННЯ РЕЄСТРУ
--------------------------------------------------------------
function SR:UpdateLedger()
    if not self.ledgerChild then return end
    if self.ledgerScroll and self.ledgerScroll:GetWidth() > 0 then
        self.ledgerChild:SetWidth(self.ledgerScroll:GetWidth())
    end

    if self.ledgerTabs then
        self.ledgerTabs.players.active = (self.ledgerActiveSubTab == "players")
        self.ledgerTabs.bosses.active = (self.ledgerActiveSubTab == "bosses")
        
        if self.ledgerTabs.players.active then
            self.ledgerTabs.players.bg:SetVertexColor(0.15, 0.18, 0.28, 0.95)
            self.ledgerTabs.players.accent:SetVertexColor(SR.UI.C.blue[1], SR.UI.C.blue[2], SR.UI.C.blue[3], 1)
            self.ledgerTabs.players.label:SetTextColor(1, 0.82, 0)
        else
            self.ledgerTabs.players.bg:SetVertexColor(0.10, 0.10, 0.16, 0.9)
            self.ledgerTabs.players.accent:SetVertexColor(SR.UI.C.blue[1], SR.UI.C.blue[2], SR.UI.C.blue[3], 0)
            self.ledgerTabs.players.label:SetTextColor(0.5, 0.5, 0.5)
        end
        
        if self.ledgerTabs.bosses.active then
            self.ledgerTabs.bosses.bg:SetVertexColor(0.15, 0.18, 0.28, 0.95)
            self.ledgerTabs.bosses.accent:SetVertexColor(SR.UI.C.blue[1], SR.UI.C.blue[2], SR.UI.C.blue[3], 1)
            self.ledgerTabs.bosses.label:SetTextColor(1, 0.82, 0)
        else
            self.ledgerTabs.bosses.bg:SetVertexColor(0.10, 0.10, 0.16, 0.9)
            self.ledgerTabs.bosses.accent:SetVertexColor(SR.UI.C.blue[1], SR.UI.C.blue[2], SR.UI.C.blue[3], 0)
            self.ledgerTabs.bosses.label:SetTextColor(0.5, 0.5, 0.5)
        end
    end

    if self.ledgerActiveSubTab == "bosses" then
        self:UpdateLedgerBosses()
    else
        self:UpdateLedgerPlayers()
    end
end


