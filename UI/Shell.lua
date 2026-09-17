--------------------------------------------------------------
-- SoftRollManager  —  UI/Shell.lua
-- Головне вікно й вкладки, сесійний банер, кнопка міні-карти,
-- підказки предметів, вікно налаштувань/експорту.
-- Сумісно з WoW 3.3.5a (WotLK)
--------------------------------------------------------------

local SR = SoftRoll

--------------------------------------------------------------
-- =============== ГОЛОВНЕ ВІКНО ==============================
--------------------------------------------------------------
function SR:CreateUI()

    -- Запобігання подвійному створенню
    if self.mainFrame then return end

    -----------------------------------------------------------
    -- Головний контейнер
    -----------------------------------------------------------
    local f = CreateFrame("Frame", "SoftRollMainFrame", UIParent)
    f:SetSize(SR.UI.FRAME_W, SR.UI.FRAME_H)
    f:SetPoint("CENTER")
    SR:ApplyDialogBackdrop(f, 0.07, 0.07, 0.10, 0.97)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:Hide()

    -- Закриття на ESC
    tinsert(UISpecialFrames, "SoftRollMainFrame")

    self.mainFrame = f

    -----------------------------------------------------------
    -- Заголовок
    -----------------------------------------------------------
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetFont("Fonts\\FRIZQT__.TTF", 15)
    title:SetText("|cff33bbffSoftRoll Manager|r  |cffffbb22v" .. self.VERSION .. "|r")



    -- Декоративна лінія під заголовком
    local hdrLine = SR:MakeAccentLine(f)
    hdrLine:SetPoint("TOPLEFT",  f, "TOPLEFT",  SR.UI.PAD + 20, -(SR.UI.HDR_H + 6))
    hdrLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(SR.UI.PAD + 20), -(SR.UI.HDR_H + 6))

    -----------------------------------------------------------
    -- Кнопка закриття
    -----------------------------------------------------------
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -----------------------------------------------------------
    -- КНОПКА "ЗБЕРЕГТИ" (/reload) — дзеркально до close зверху зліва
    -----------------------------------------------------------
    local saveBtn = CreateFrame("Button", nil, f)
    saveBtn:SetSize(24, 24)
    -- y = -10, не -6: close (UIPanelCloseButton) — це 32x32 фрейм, тож його
    -- візуальний центр при TOPRIGHT -6 лежить на y=-22 від верху вікна;
    -- щоб 24x24 saveBtn мав той самий центр, треба top-offset -10, інакше
    -- кнопка виглядає вищою за решту кнопок заголовка.
    saveBtn:SetPoint("TOPLEFT", 10, -10)
    -- Кастомна іконка дискети (Media/icon_save.tga) в кольорах аддону —
    -- вже має власну золоту рамку/тінь, тож окремий фон-слот не потрібен.
    local saveIcon = saveBtn:CreateTexture(nil, "ARTWORK")
    saveIcon:SetAllPoints()
    saveIcon:SetTexture("Interface\\AddOns\\SoftRollManager\\Media\\icon_save.tga")
    saveBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    saveBtn:SetScript("OnClick", function() ReloadUI() end)
    saveBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -6)
        GameTooltip:AddLine("Зберегти (перезавантажити інтерфейс)", 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("WoW записує софт-роли на диск лише при виході з гри", 1, 1, 1, true)
        GameTooltip:AddLine("або перезавантаженні інтерфейсу — не в реальному часі.", 1, 1, 1, true)
        GameTooltip:AddLine("Натисніть цю кнопку після важливих змін (наприклад,", 1, 1, 1, true)
        GameTooltip:AddLine("багато нових софтів), щоб зафіксувати їх на диску.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Якщо гра вилетить ПІСЛЯ такого збереження — вже", 0.4, 1, 0.4, true)
        GameTooltip:AddLine("зареєстровані софти НЕ загубляться.", 0.4, 1, 0.4, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Інтерфейс на кілька секунд згасне й з'явиться знову —", 0.6, 0.6, 0.6, true)
        GameTooltip:AddLine("це нормально, рейд і чат це не зачіпає.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    saveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.saveBtn = saveBtn

    local exportBtn = CreateFrame("Button", nil, f)
    exportBtn:SetSize(24, 24)
    exportBtn:SetPoint("RIGHT", close, "LEFT", -4, 0)
    exportBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    exportBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    exportBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    local exportIcon = exportBtn:CreateTexture(nil, "OVERLAY")
    exportIcon:SetTexture("Interface\\GuildFrame\\GuildLogo-NoLogo")
    exportIcon:SetSize(14, 14)
    exportIcon:SetPoint("CENTER", exportBtn, "CENTER", 0, -1)
    
    local exportDD = CreateFrame("Frame", "SRExportDropDown", f, "UIDropDownMenuTemplate")
    exportDD:Hide()

    exportBtn:SetScript("OnClick", function(self)
        if DropDownList1 and DropDownList1:IsShown() and UIDROPDOWNMENU_OPEN_MENU == exportDD then
            CloseDropDownMenus()
            return
        end
        ToggleDropDownMenu(1, nil, exportDD, self, 0, 0)
    end)
    exportBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SR.L.UI_EXPORT_TOOLTIP or "Експорт софтів")
        GameTooltip:Show()
    end)
    exportBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.exportBtn = exportBtn

    UIDropDownMenu_Initialize(exportDD, function(self, level)
        level = level or 1
        if level ~= 1 then return end
        
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Discord"
        info.notCheckable = true
        info.func = function()
            SR:ShowExportWindow("discord")
        end
        UIDropDownMenu_AddButton(info, level)
    end)

    -----------------------------------------------------------
    -- КНОПКА "ІНФО" (автор аддону / для кого зроблено)
    -----------------------------------------------------------
    local infoBtn = CreateFrame("Button", nil, f)
    infoBtn:SetSize(24, 24)
    infoBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    infoBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    infoBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    local infoIcon = infoBtn:CreateTexture(nil, "OVERLAY")
    infoIcon:SetTexture("Interface\\FriendsFrame\\InformationIcon")
    infoIcon:SetSize(14, 14)
    infoIcon:SetPoint("CENTER", infoBtn, "CENTER", 0, -1)
    infoBtn:SetScript("OnClick", function() SR:ToggleCreditsPopup() end)
    infoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Про аддон")
        GameTooltip:Show()
    end)
    infoBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.infoBtn = infoBtn

    -----------------------------------------------------------
    -- КНОПКА НАЛАШТУВАНЬ (шестірня біля експорту)
    -----------------------------------------------------------
    local settingsBtn = CreateFrame("Button", nil, f)
    settingsBtn:SetSize(24, 24)
    settingsBtn:SetPoint("RIGHT", exportBtn, "LEFT", -4, 0)
    infoBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -4, 0)
    settingsBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    settingsBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    settingsBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    -- Значок помічника рейду (той самий щит, що Blizzard використовує в панелі
    -- рейду для асистентів) — семантично точний і чіткіший за самотню шестірню,
    -- яку важко розрізнити поруч з іконками інфо/експорту.
    local settingsIcon = settingsBtn:CreateTexture(nil, "OVERLAY")
    settingsIcon:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
    settingsIcon:SetSize(14, 14)
    settingsIcon:SetPoint("CENTER", settingsBtn, "CENTER", 0, -1)

    local coHostDD = CreateFrame("Frame", "SRCoHostDropDown", f, "UIDropDownMenuTemplate")
    coHostDD:Hide()
    
    settingsBtn:SetScript("OnClick", function(self)
        if not IsRaidLeader() then
            SR:Print(SR.L.PRINT_ONLY_RL_ASSIGN_COHOST)
            return
        end
        if DropDownList1 and DropDownList1:IsShown() and UIDROPDOWNMENU_OPEN_MENU == coHostDD then
            CloseDropDownMenus()
            return
        end
        ToggleDropDownMenu(1, nil, coHostDD, self, 0, 0)
    end)
    settingsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Ко-Хости (Помічники)")
        GameTooltip:Show()
    end)
    settingsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UIDropDownMenu_Initialize(coHostDD, function(self, level)
        level = level or 1
        if level ~= 1 then return end
        
        local infoTitle = UIDropDownMenu_CreateInfo()
        infoTitle.text = "Ко-Хости (Помічники)"
        infoTitle.isTitle = true
        infoTitle.notCheckable = true
        UIDropDownMenu_AddButton(infoTitle, level)
        
        if not GetNumRaidMembers or GetNumRaidMembers() == 0 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "Ви не у рейді"
            info.notCheckable = true
            info.disabled = true
            UIDropDownMenu_AddButton(info, level)
            return
        end
        
        local assistants = {}
        for i = 1, GetNumRaidMembers() do
            local name, rank = GetRaidRosterInfo(i)
            local cleanName = name and SR:StripRealm(name)
            if cleanName and rank > 0 and cleanName ~= SR:GetLocalPlayerName() then
                table.insert(assistants, cleanName)
            end
        end
        
        if #assistants == 0 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "Немає інших помічників"
            info.notCheckable = true
            info.disabled = true
            UIDropDownMenu_AddButton(info, level)
            return
        end
        
        if not SR.db.coHosts then SR.db.coHosts = {} end
        for _, name in ipairs(assistants) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.isNotRadio = true
            info.keepShownOnClick = true
            info.checked = SR.db.coHosts[name]
            info.func = function(_, _, _, checked)
                SR.db.coHosts[name] = (checked == true or checked == 1)
                SR:BroadcastCoHosts()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")

    self.settingsBtn = settingsBtn

    -----------------------------------------------------------
    -- КНОПКИ ВКЛАДОК (4 вкладки)
    -----------------------------------------------------------
    local tabs     = {}
    local panels   = {}
    local tabNames = {
        SR.L.TAB_DASHBOARD or "Панель керування",
        SR.L.TAB_LEDGER or "Список софтів",
        SR.L.TAB_BROWSER or "Огляд луту",
        SR.L.TAB_SESSION or "Здобич рейду",
    }

    local tabW = 116
    local spacing = 4
    local startX = 22 -- (520 - (116*4 + 4*3)) / 2

    for i, label in ipairs(tabNames) do
        local tb = CreateFrame("Button", "SRTab" .. i, f)
        tb:SetSize(tabW, SR.UI.TAB_H)
        tb:SetPoint("TOPLEFT", startX + (i - 1) * (tabW + spacing), -(SR.UI.HDR_H + 20))

        local bg = tb:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        tb.bg = bg

        -- Акцентна лінія зверху (aктивна вкладка)
        local accent = tb:CreateTexture(nil, "OVERLAY")
        accent:SetHeight(3)
        accent:SetPoint("TOPLEFT",  tb, "TOPLEFT",  0, 0)
        accent:SetPoint("TOPRIGHT", tb, "TOPRIGHT", 0, 0)
        accent:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        accent:SetVertexColor(SR.UI.C.blue[1], SR.UI.C.blue[2], SR.UI.C.blue[3], 0)
        tb.accent = accent

        local txt = tb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        txt:SetPoint("CENTER", 0, 0)
        txt:SetText(label)
        txt:SetFont("Fonts\\FRIZQT__.TTF", 11)
        tb.label = txt

        tb:SetScript("OnClick", function() SR:SelectTab(i) end)
        tb:SetScript("OnEnter", function(self)
            if self.active then return end
            self.bg:SetVertexColor(0.18, 0.22, 0.32, 0.9)
        end)
        tb:SetScript("OnLeave", function(self)
            if self.active then return end
            self.bg:SetVertexColor(0.10, 0.10, 0.16, 0.9)
        end)

        tabs[i] = tb
    end
    self.tabs = tabs

    -----------------------------------------------------------
    -- Панелі вмісту (одна на вкладку)
    -----------------------------------------------------------
    for i = 1, 4 do
        local p = CreateFrame("Frame", nil, f)
        p:SetPoint("TOPLEFT", SR.UI.PAD, -(SR.UI.HDR_H + 20 + SR.UI.TAB_H + 4))
        p:SetPoint("BOTTOMRIGHT", -SR.UI.PAD, SR.UI.PAD + SR.UI.STATUS_H + 4)
        SR:ApplyPanelStyle(p)
        p:Hide()
        panels[i] = p
    end
    self.panels = panels

    -- Нижня статус-смуга
    local statusBar = CreateFrame("Frame", nil, f)
    statusBar:SetPoint("BOTTOMLEFT",  SR.UI.PAD, SR.UI.PAD)
    statusBar:SetPoint("BOTTOMRIGHT", -SR.UI.PAD, SR.UI.PAD)
    statusBar:SetHeight(SR.UI.STATUS_H)
    SR:ApplyPanelStyle(statusBar, 0.05, 0.07, 0.12, 0.98)
    local statusTopLine = SR:MakeAccentLine(statusBar, SR.UI.C.blue[1], SR.UI.C.blue[2], SR.UI.C.blue[3], 0.30)
    statusTopLine:SetPoint("TOPLEFT",  statusBar, "TOPLEFT",  0, 0)
    statusTopLine:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT", 0, 0)
    local statusDot = statusBar:CreateTexture(nil, "ARTWORK")
    statusDot:SetSize(8, 8)
    statusDot:SetPoint("LEFT", 10, 0)
    statusDot:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    statusDot:SetVertexColor(0.40, 0.40, 0.45, 1)
    self.statusDot = statusDot
    local statusFS = SR:MakeLabel(statusBar, 10, 0.50, 0.50, 0.55, "LEFT")
    statusFS:SetPoint("LEFT", statusDot, "RIGHT", 6, 0)
    statusFS:SetWidth(460)
    self.statusBarFS = statusFS
    local statusMode = SR:MakeLabel(statusBar, 10, SR.UI.C.label[1], SR.UI.C.label[2], SR.UI.C.label[3], "RIGHT")
    statusMode:SetPoint("RIGHT", -10, 0)
    statusMode:SetWidth(290)
    self.statusModeFS = statusMode

    -- Побудова вмісту кожної вкладки
    self:BuildDashboard(panels[1])
    self:BuildLedger(panels[2])
    self:BuildLootBrowser(panels[3])
    self:BuildLootSession(panels[4])

    -- Побудова вікна перевизначення лімітів гравця (прихованого)
    self:BuildOverridePopup()
    
    -- Побудова вікна редагування софтів гравця (прихованого)
    self:BuildEditPlayerPopup()

    -- Побудова попапів відновлення даних хоста з рейду (прихованих)
    self:BuildDataLossPopup()
    self:BuildRecoveryPopup()

    -- Відкриття панелі керування за замовчуванням
    self:SelectTab(1)
end

--------------------------------------------------------------
-- ВИБІР ВКЛАДКИ
--------------------------------------------------------------
function SR:SelectTab(idx)
    for i, tb in ipairs(self.tabs) do
        if i == idx then
            tb.bg:SetVertexColor(0.13, 0.18, 0.30, 1)
            tb.label:SetTextColor(1, 1, 1)
            if tb.accent then tb.accent:SetVertexColor(SR.UI.C.blue[1], SR.UI.C.blue[2], SR.UI.C.blue[3], 1) end
            tb.active = true
            self.panels[i]:Show()
        else
            tb.bg:SetVertexColor(0.10, 0.10, 0.16, 0.9)
            tb.label:SetTextColor(0.52, 0.52, 0.58)
            if tb.accent then tb.accent:SetVertexColor(SR.UI.C.blue[1], SR.UI.C.blue[2], SR.UI.C.blue[3], 0) end
            tb.active = false
            self.panels[i]:Hide()
        end
    end
    self:UpdateSessionBanner()
    self:UpdateAdminReadOnly()
    if idx == 1 then self:UpdateDashboard()
    elseif idx == 2 then self:UpdateLedger()
    elseif idx == 3 then self:UpdateLootBrowser()
    elseif idx == 4 then self:UpdateLootSession()
    end
end

--------------------------------------------------------------
-- ПЕРЕМИКАННЯ ТА ПРАВА ДОСТУПУ
--------------------------------------------------------------
function SR:ToggleUI()
    if self.mainFrame:IsShown() then
        self.mainFrame:Hide()
    else
        self:UpdateAdminReadOnly()
        self:UpdateSessionBanner()
        self:QueueAllKnownItems()
        -- Оновлення видимої вкладки
        for i, tb in ipairs(self.tabs) do
            if tb.active then
                if i == 1 then self:UpdateDashboard()
                elseif i == 2 then self:UpdateLedger()
                elseif i == 3 then self:UpdateLootBrowser()
                elseif i == 4 then self:UpdateLootSession()
                end
                break
            end
        end
        self.mainFrame:Show()
    end
end

--------------------------------------------------------------
-- БАНЕР СЕСІЇ ТА РЕЖИМ ЧИТАННЯ
--------------------------------------------------------------
function SR:UpdateSessionBanner()
    if self.statusBarFS then
        if self.sessionActive and self.sessionHost then
            local lockSuffix = self.locked and "|cffff4444[ЗАБЛОКОВАНО]|r" or "|cff44ff44[ВІДКРИТО]|r"
            local hostName = self.sessionHost or "Невідомо"
            
            if self:IsSessionHost() then
                self.statusBarFS:SetText("Софт-роли: " .. lockSuffix)
                self.statusBarFS:SetTextColor(0.8, 0.8, 0.8)
                if self.statusDot then self.statusDot:SetVertexColor(self.locked and 0.9 or 0.2, self.locked and 0.2 or 0.9, 0.2, 1) end
            elseif self:IsSessionReadOnly() then
                self.statusBarFS:SetText("Софт-роли: " .. lockSuffix .. "  (РЛ: |cffffcc00" .. hostName .. "|r)")
                self.statusBarFS:SetTextColor(0.8, 0.8, 0.8)
                if self.statusDot then self.statusDot:SetVertexColor(0.9, 0.7, 0.1, 1) end
            else
                self.statusBarFS:SetText("Софт-роли: " .. lockSuffix .. "  (РЛ: |cffffcc00" .. hostName .. "|r)")
                self.statusBarFS:SetTextColor(0.8, 0.8, 0.8)
                if self.statusDot then self.statusDot:SetVertexColor(0.3, 0.6, 0.9, 1) end
            end
        else
            local inGroup = (GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0)
            if inGroup then
                self.statusBarFS:SetText("Очікування даних від РЛа...")
            else
                self.statusBarFS:SetText("Ви не в рейді / паті")
            end
            self.statusBarFS:SetTextColor(0.42, 0.42, 0.48)
            if self.statusDot then self.statusDot:SetVertexColor(0.35, 0.35, 0.40, 1) end
        end
    end
    if self.statusModeFS then
        local inst = SR.INSTANCE_LABELS and SR.INSTANCE_LABELS[SR.db.instance] or (SR.db.instance or "?")
        local mode = SR.SR_MODE_LABELS  and SR.SR_MODE_LABELS[SR.db.srMode]   or (SR.db.srMode  or "?")
        self.statusModeFS:SetText(inst .. "  |cff444466-|r  " .. mode)
    end
    if self.ledgerHintFS then
        self.ledgerHintFS:SetText("Наведіть на іконки для деталей  -  Shift-клік для лінку в чат")
    end
end


--- Перевстановлює якір infoBtn залежно від того, чи показана settingsBtn
-- (видима лише для РЛ) — інакше для звичайного гравця (без settingsBtn)
-- infoBtn лишається прив'язаною до її старої, тепер невидимої, позиції,
-- і між іконками "i" та експортом з'являється порожній проміжок.
function SR:UpdateHeaderButtonRow(showSettings)
    if not self.settingsBtn or not self.infoBtn or not self.exportBtn then return end
    if showSettings then
        self.settingsBtn:Show()
        self.infoBtn:ClearAllPoints()
        self.infoBtn:SetPoint("RIGHT", self.settingsBtn, "LEFT", -4, 0)
    else
        self.settingsBtn:Hide()
        self.infoBtn:ClearAllPoints()
        self.infoBtn:SetPoint("RIGHT", self.exportBtn, "LEFT", -4, 0)
    end
end

function SR:UpdateAdminReadOnly()
    local readOnly = self:IsSessionReadOnly()
    local canEdit  = self:CanEditSession()
    local inGroup  = (GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0)

    -- ── Не в паті / рейді: тільки «Огляд луту» (таб 3) доступний ──
    if not inGroup then
        for i, tb in ipairs(self.tabs) do
            if i == 3 then
                tb:Show()
                tb:Enable()
                if not tb.active then
                    tb.label:SetTextColor(0.52, 0.52, 0.58)
                end
            else
                tb:Show()
                tb:Disable()
                tb.label:SetTextColor(0.28, 0.28, 0.32)
                if tb.accent then tb.accent:SetVertexColor(SR.UI.C.blue[1], SR.UI.C.blue[2], SR.UI.C.blue[3], 0) end
                if tb.active then
                    tb.bg:SetVertexColor(0.10, 0.10, 0.16, 0.9)
                    tb.active = false
                    self.panels[i]:Hide()
                end
            end
        end
        -- Якщо таб 3 ще не активний — переключаємось на нього
        if not self.tabs[3].active then
            self:SelectTab(3)
        end
        -- Ранній вихід — решту логіки не застосовуємо
        SR:UpdateHeaderButtonRow(false)
        return
    end

    -- Керування видимістю вкладок
    if not canEdit then
        self.tabs[1]:Hide()
        self.tabs[4]:Hide()

        -- Таб 2 (Список софтів) — завжди доступний у групі
        self.tabs[2]:Show()
        self.tabs[2]:Enable()
        if not self.tabs[2].active then
            self.tabs[2].label:SetTextColor(0.52, 0.52, 0.58)
        end

        -- Якщо поточна вкладка прихована — переключаємось
        if self.tabs[1].active or self.tabs[4].active then
            self.forcedToTab3 = true
            self:SelectTab(3)
        end
    else
        self.tabs[1]:Show()
        self.tabs[1]:Enable()
        self.tabs[2]:Show()
        self.tabs[2]:Enable()
        if not self.tabs[2].active then
            self.tabs[2].label:SetTextColor(0.52, 0.52, 0.58)
        end
        self.tabs[4]:Show()
        self.tabs[4]:Enable()
        -- При першому відкритті або після релогу (таб 3 був активний через не-в-рейд)
        local anyActive = false
        for _, tb in ipairs(self.tabs) do if tb.active then anyActive = true break end end
        if not anyActive or (self.tabs[3].active and self.forcedToTab3) then
            self.forcedToTab3 = false
            -- Якщо активний тільки таб 3 і нас туди перекинуло системою — повертаємо назад
            if readOnly then self:SelectTab(2) else self:SelectTab(1) end
        end
    end

    SR:UpdateHeaderButtonRow(IsRaidLeader())

    -- Елементи керування дашборду
    if self.lockBtn then
        if canEdit then
            self.lockBtn:Enable()
        else
            self.lockBtn:Disable()
        end
    end
    if self.autoBtn then
        if readOnly then self.autoBtn:Disable() else self.autoBtn:Enable() end
    end
    local canChangeSettings = canEdit or self:IsAdmin()
    if self.instDD then
        if canChangeSettings then UIDropDownMenu_EnableDropDown(self.instDD)
        else UIDropDownMenu_DisableDropDown(self.instDD) end
    end
    if self.modeDD then
        if canChangeSettings then UIDropDownMenu_EnableDropDown(self.modeDD)
        else UIDropDownMenu_DisableDropDown(self.modeDD) end
    end
    if self.ledgerClearAll then
        if readOnly then self.ledgerClearAll:Disable() else self.ledgerClearAll:Enable() end
    end
    if self.ledgerAnnounceBtn then
        if readOnly then self.ledgerAnnounceBtn:Disable() else self.ledgerAnnounceBtn:Enable() end
    end

    -- Кнопка "Зберегти" (/reload) має сенс лише для того, хто тримає
    -- авторитетну копію даних рейду — тобто активного хоста (або лідера
    -- рейду/паті до старту сесії). У звичайного гравця/ко-хоста локальні
    -- резерви — лише дзеркало того, що синхронізував хост, тож relог
    -- нічого для нього не рятує.
    if self.saveBtn then
        if self:IsSessionHost() or (self:IsSessionLeader() and not self.sessionActive) then
            self.saveBtn:Show()
        else
            self.saveBtn:Hide()
        end
    end

    if self.lbTargetDD then
        if canEdit then
            self.lbTargetDD:Show()
            if self.lbTargetLabel then self.lbTargetLabel:Show() end
            UIDropDownMenu_Initialize(self.lbTargetDD, function(self, level)
                level = level or 1
                if level ~= 1 then return end

                local selfName = SR:GetLocalPlayerName()
                local info = UIDropDownMenu_CreateInfo()
                info.text = SR.L.UI_TARGET_SELF
                info.value = selfName
                info.checked = (SR.lbTargetPlayer == nil or SR.lbTargetPlayer == selfName)
                info.func = function()
                    SR.lbTargetPlayer = selfName
                    UIDropDownMenu_SetText(SR.lbTargetDD, SR.L.UI_TARGET_SELF)
                    if SR.UpdateLootBrowserItems then SR:UpdateLootBrowserItems() end
                end
                UIDropDownMenu_AddButton(info, level)

                local members = SR:GetRaidMembers()
                if #members > 0 then
                    local infoTitle = UIDropDownMenu_CreateInfo()
                    infoTitle.text = SR.L.UI_TARGET_RAID_HEADER
                    infoTitle.isTitle = true
                    infoTitle.notCheckable = true
                    UIDropDownMenu_AddButton(infoTitle, level)

                    for _, m in ipairs(members) do
                        local mName = m.name
                        if mName ~= selfName then
                            local pInfo = UIDropDownMenu_CreateInfo()
                            pInfo.text = mName
                            pInfo.value = mName
                            pInfo.checked = (SR.lbTargetPlayer == mName)
                            pInfo.func = function()
                                SR.lbTargetPlayer = mName
                                UIDropDownMenu_SetText(SR.lbTargetDD, mName)
                                if SR.UpdateLootBrowserItems then SR:UpdateLootBrowserItems() end
                            end
                            UIDropDownMenu_AddButton(pInfo, level)
                        end
                    end
                end
            end)
            if not SR.lbTargetPlayer or SR.lbTargetPlayer == SR:GetLocalPlayerName() then
                UIDropDownMenu_SetText(self.lbTargetDD, SR.L.UI_TARGET_SELF)
            else
                UIDropDownMenu_SetText(self.lbTargetDD, SR.lbTargetPlayer)
            end
        else
            self.lbTargetDD:Hide()
            if self.lbTargetLabel then self.lbTargetLabel:Hide() end
            if SR.lbTargetPlayer then
                SR.lbTargetPlayer = nil
                if SR.UpdateLootBrowserItems then SR:UpdateLootBrowserItems() end
            end
        end
    end

    self._uiReadOnly = readOnly
    self._uiCanEdit  = canEdit
end


-- ╔══════════════════════════════════════════════════════════╗
-- ║                КНОПКА МІНІ-КАРТИ                        ║
-- ╚══════════════════════════════════════════════════════════╝

function SR:CreateMinimapButton()
    local btn = CreateFrame("Button", "SoftRollMinimapBtn", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    btn:SetMovable(true)

    -- Фон (круглий)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -4)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    -- Іконка — кастомна гральна кістка (Media/icon_minimap.tga) в кольорах
    -- аддону, замість заглушки INV_Misc_Note_03.
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -5)
    icon:SetTexture("Interface\\AddOns\\SoftRollManager\\Media\\icon_minimap.tga")

    -- Рамка (золоте кільце)
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Позиція на краях міні-карти
    local function UpdatePosition(angle)
        local rad = math.rad(angle)
        local x = math.cos(rad) * 80
        local y = math.sin(rad) * 80
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    UpdatePosition(SR.db.minimapPos or 220)

    -- Перетягування навколо міні-карти
    local isDragging = false
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function()
        isDragging = true
        btn:SetScript("OnUpdate", function()
            local cx, cy = Minimap:GetCenter()
            local mx, my = GetCursorPosition()
            local scale  = Minimap:GetEffectiveScale()
            mx, my = mx / scale, my / scale
            local angle = math.deg(math.atan2(my - cy, mx - cx))
            SR.db.minimapPos = angle
            UpdatePosition(angle)
        end)
    end)
    btn:SetScript("OnDragStop", function()
        isDragging = false
        btn:SetScript("OnUpdate", nil)
    end)

    -- Клік для відображення вікна
    btn:SetScript("OnClick", function(self, button)
        if not isDragging then
            SR:ToggleUI()
        end
    end)

    -- Підказка
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("|cff33bbffSoftRoll Manager|r v" .. SR.VERSION)
        GameTooltip:AddLine("Клікніть, щоб відкрити/сховати вікно SR.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Перетягніть, щоб перемістити кнопку.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║                ІНТЕГРАЦІЯ У ПІДКАЗКИ (TOOLTIPS)         ║
-- ╚══════════════════════════════════════════════════════════╝

local function OnTooltipSetItem(tooltip)
    if not SR.db or not SR.db.reserves then return end

    local name, link = tooltip:GetItem()
    if not link then return end

    local itemID = SR:GetItemIDFromLink(link)
    if not itemID then return end

    local players = SR:GetPlayersWithSR(itemID)
    if not players or #players == 0 then return end

    -- Уникнення дублювання тексту
    local tooltipName = tooltip:GetName()
    if tooltipName then
        for i = 1, tooltip:NumLines() do
            local leftFS = _G[tooltipName .. "TextLeft" .. i]
            if leftFS and leftFS:GetText() == "Софт-роли:" then
                return
            end
        end
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("Софт-роли:", 1, 0.8, 0)
    for _, p in ipairs(players) do
        local rStr = p.role and (" (" .. (SR.ROLE_LABELS[p.role] or p.role) .. ")") or ""
        local cx = (p.count > 1) and (" x" .. p.count) or ""
        tooltip:AddLine("- " .. p.name .. rStr .. cx, 0.9, 0.9, 0.9)
    end
    tooltip:Show()
end

if GameTooltip:HasScript("OnTooltipSetItem") then
    GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
else
    GameTooltip:SetScript("OnTooltipSetItem", OnTooltipSetItem)
end

if ItemRefTooltip:HasScript("OnTooltipSetItem") then
    ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
else
    ItemRefTooltip:SetScript("OnTooltipSetItem", OnTooltipSetItem)
end


-- ╔══════════════════════════════════════════════════════════╗
-- ║                ВІКНО НАЛАШТУВАНЬ (SETTINGS)             ║
-- ╚══════════════════════════════════════════════════════════╝

-- Settings Frame replaced by DropDown Menu

-- ╔══════════════════════════════════════════════════════════╗
-- ║                ПОПАП "ПРО АДДОН" (автор / для кого)     ║
-- ╚══════════════════════════════════════════════════════════╝

function SR:ToggleCreditsPopup()
    if self.creditsPopup and self.creditsPopup:IsShown() then
        self.creditsPopup:Hide()
        return
    end
    if not self.creditsPopup then
        local popup = CreateFrame("Frame", "SRCreditsPopup", UIParent)
        popup:SetSize(260, 140)
        popup:SetPoint("CENTER")
        SR:ApplyDialogBackdrop(popup, 0.08, 0.08, 0.12, 0.98)
        popup:SetFrameStrata("DIALOG")
        popup:SetFrameLevel(120)
        popup:SetMovable(true)
        popup:EnableMouse(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving)
        popup:SetScript("OnDragStop",  popup.StopMovingOrSizing)
        popup:Hide()
        tinsert(UISpecialFrames, "SRCreditsPopup")

        local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)

        local topLine = SR:MakeAccentLine(popup, SR.UI.C.gold[1], SR.UI.C.gold[2], SR.UI.C.gold[3], 0.75)
        topLine:SetPoint("TOPLEFT",  popup, "TOPLEFT",  14, -12)
        topLine:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -14, -12)

        local titleFS = SR:MakeLabel(popup, 12, SR.UI.C.gold[1], SR.UI.C.gold[2], SR.UI.C.gold[3])
        titleFS:SetPoint("TOP", 0, -18)
        titleFS:SetText("SoftRoll Manager")

        local authorFS = SR:MakeLabel(popup, 11, 1, 1, 1, "CENTER")
        authorFS:SetPoint("TOP", titleFS, "BOTTOM", 0, -16)
        authorFS:SetWidth(230)
        authorFS:SetText("Автор: |cffffcc00Гризун|r")

        local forFS = SR:MakeLabel(popup, 11, 0.85, 0.85, 0.85, "CENTER")
        forFS:SetPoint("TOP", authorFS, "BOTTOM", 0, -10)
        forFS:SetWidth(230)
        forFS:SetWordWrap(true)
        forFS:SetText("Зроблено для |cffffcc00Белаз|r\nгільдія |cff40c040GARAGE|r")

        self.creditsPopup = popup
    end
    self.creditsPopup:Show()
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║                ВІКНО ІНФО (INFO)                        ║
-- ╚══════════════════════════════════════════════════════════╝

local infoPages = {
    {
        title = "Про аддон",
        text = "SoftRoll Manager — це зручний інструмент для автоматизації системи 'софт-ролів'.\n\nВін дозволяє Лідерам Рейду відслідковувати, редагувати та анонсувати зарезервовані предмети, а гравцям — швидко переглядати лут-таблиці та реєструвати свої софт-роли.\n\n\n|cffFFD700VIP Edition|r\nЕксклюзивно розроблено та оптимізовано.\nMade by: |cff00FF96Гризун|r\nFor: |cffFF7D0AБелаз|r"
    },
    {
        title = "Для гравців",
        text = "Для реєстрації софт-ролу:\n\n1. Натисніть кнопку 'Огляд луту' в аддоні.\n2. Виберіть потрібний предмет і натисніть 'Зарезервувати'.\n\nАбо через чат: напишіть РЛу в ПМ (або в рейд чат) команду:\nsr [лінк предмета]\n\nЩоб видалити свій софт-рол: sr clear [лінк]"
    },
    {
        title = "Для РЛів",
        text = "Як провести сесію:\n\n1. В панелі керування натисніть 'Почати сесію'.\n2. Виберіть підземелля та ліміт (напр. 'Стандарт x3').\n3. Гравці почнуть додавати свої предмети.\n4. Коли всі предмети зібрано, натисніть 'Заблокувати', щоб заборонити нові реєстрації.\n5. Під час роздачі здобичі, переходьте у 'Роздача луту' для автоматичних анонсів."
    },
    {
        title = "Синхронізація",
        text = "Дані сесії автоматично синхронізуються між РЛом та всіма учасниками рейду, у яких встановлено аддон.\n\nЯкщо увімкнено відповідне налаштування, Помічники рейду (Assistants) також можуть допомагати РЛу керувати софт-ролами (видаляти/додавати чужі софти)."
    }
}

function SR:ToggleInfoFrame()
    if self.infoFrame and self.infoFrame:IsShown() then
        self.infoFrame:Hide()
        return
    end
    if not self.infoFrame then
        local f = CreateFrame("Frame", "SoftRollInfoFrame", UIParent)
        f:SetSize(500, 350)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        tinsert(UISpecialFrames, "SoftRollInfoFrame")
        
        f:SetBackdrop({
            bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        f:SetBackdropColor(0.05, 0.05, 0.1, 0.95)
        f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -12)
        title:SetText("Довідка та Інструкції")
        
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)

        -- Бокове меню
        local navList = CreateFrame("Frame", nil, f)
        navList:SetSize(140, 280)
        navList:SetPoint("TOPLEFT", 10, -40)

        -- Основна текстова область
        local contentArea = CreateFrame("Frame", nil, f)
        contentArea:SetPoint("TOPLEFT", navList, "TOPRIGHT", 10, 0)
        contentArea:SetPoint("BOTTOMRIGHT", -15, 15)
        
        local contentTitle = contentArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        contentTitle:SetPoint("TOPLEFT", 0, -10)
        
        local contentText = contentArea:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        contentText:SetPoint("TOPLEFT", contentTitle, "BOTTOMLEFT", 0, -15)
        contentText:SetPoint("BOTTOMRIGHT", 0, 0)
        contentText:SetJustifyH("LEFT")
        contentText:SetJustifyV("TOP")
        contentText:SetWordWrap(true)
        
        -- Створення кнопок навігації
        local buttons = {}
        for i, page in ipairs(infoPages) do
            local btn = CreateFrame("Button", nil, navList)
            btn:SetSize(140, 30)
            btn:SetPoint("TOPLEFT", 0, -(i - 1) * 35)
            
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
            bg:SetVertexColor(0.1, 0.1, 0.15, 1)
            btn.bg = bg
            
            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("CENTER")
            label:SetText(page.title)
            
            btn:SetScript("OnClick", function()
                for _, b in ipairs(buttons) do b.bg:SetVertexColor(0.1, 0.1, 0.15, 1) end
                btn.bg:SetVertexColor(0.2, 0.4, 0.8, 1)
                contentTitle:SetText(page.title)
                contentText:SetText(page.text)
            end)
            buttons[i] = btn
        end
        
        -- Вибір першої вкладки за замовчуванням
        buttons[1]:GetScript("OnClick")()
        
        self.infoFrame = f
    end
    self.infoFrame:Show()
end

--------------------------------------------------------------
-- ЕКСПОРТ (Discord)
--------------------------------------------------------------
function SR:ShowExportWindow(formatType)
    if not self.exportFrame then
        local f = CreateFrame("Frame", "SRExportFrame", UIParent)
        f:SetSize(450, 500)
        f:SetPoint("CENTER")
        f:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        f:SetBackdropColor(0, 0, 0, 0.95)
        f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        title:SetPoint("TOP", 0, -12)
        title:SetText("Експорт софтів (Discord)")

        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)

        local scrollFrame = CreateFrame("ScrollFrame", "SRExportScrollFrame", f, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 15, -45)
        scrollFrame:SetPoint("BOTTOMRIGHT", -35, 40)

        local editBox = CreateFrame("EditBox", "SRExportEditBox", scrollFrame)
        editBox:SetWidth(380)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject("ChatFontNormal")
        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scrollFrame:SetScrollChild(editBox)
        scrollFrame:SetScript("OnSizeChanged", function(self)
            editBox:SetWidth(self:GetWidth() > 0 and self:GetWidth() or 380)
        end)

        f.editBox = editBox

        local copyLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        copyLabel:SetPoint("BOTTOM", 0, 15)
        copyLabel:SetText("Натисніть Ctrl+C щоб скопіювати текст")

        self.exportFrame = f
    end

    local text = ""
    if formatType == "discord" then
        local bossTrans = {
            ["Лорд Марроугар"] = "Lord Marrowgar",
            ["Леді Смертний Шепіт"] = "Lady Deathwhisper",
            ["Битва на кораблях"] = "Gunship Battle",
            ["Смертоносний Саурфанг"] = "Deathbringer Saurfang",
            ["Тухлопуз"] = "Festergut",
            ["Гниломорд"] = "Rotface",
            ["Професор Мерзоцид"] = "Professor Putricide",
            ["Рада Принців Крові"] = "Blood Prince Council",
            ["Кривава королева Лана'тель"] = "Blood-Queen Lana'thel",
            ["Валітрія Сновидиця"] = "Valithria Dreamwalker",
            ["Синдрагоса"] = "Sindragosa",
            ["Король-ліч"] = "The Lich King",
            ["Треш ЦЛК"] = "ICC Trash",
            ["Халіон"] = "Halion",
            ["Trash/Інше"] = "Trash/Other"
        }
        
        local bossMap = {}
        local bossOrder = {}
        local currentInst = self.db.instance or "ICC"
        local lootData = self.LOOT_DATA[currentInst] or {}
        local instLabel = currentInst == "ICC" and "ICC 25" or "RS 25"

        text = "**--- Soft Reserves (" .. instLabel .. ") ---**\n\n"

        for i, b in ipairs(lootData) do
            bossMap[b.name] = { name = b.name, items = {} }
            bossOrder[#bossOrder + 1] = b.name
        end
        bossMap["Trash/Інше"] = { name = "Trash/Інше", items = {} }
        bossOrder[#bossOrder + 1] = "Trash/Інше"

        for pName, list in pairs(self.db.reserves) do
            for _, e in ipairs(list) do
                local itemID = e.itemID or self:GetItemIDFromLink(e.itemLink)
                if itemID then
                    local foundBoss = "Trash/Інше"
                    local eq = self:GetEquivalentItemIDs(itemID)
                    for _, b in ipairs(lootData) do
                        local drops = false
                        for _, id in ipairs(b.loot25H or {}) do if eq[id] then drops = true break end end
                        if not drops then
                            for _, id in ipairs(b.loot25N or {}) do if eq[id] then drops = true break end end
                        end
                        if drops then foundBoss = b.name break end
                    end

                    local bItems = bossMap[foundBoss].items
                    local existing = nil
                    for _, itemEntry in ipairs(bItems) do
                        if eq[itemEntry.itemID] then existing = itemEntry break end
                    end

                    local itemName = GetItemInfo(itemID) or ("Item " .. itemID)

                    if existing then
                        existing.count = existing.count + (e.count or 1)
                        local foundRes = false
                        for _, res in ipairs(existing.reservers) do
                            if res.name == pName then
                                res.count = res.count + (e.count or 1)
                                foundRes = true break
                            end
                        end
                        if not foundRes then table.insert(existing.reservers, {name = pName, count = e.count or 1}) end
                    else
                        table.insert(bItems, {
                            itemID = itemID,
                            itemName = itemName,
                            count = e.count or 1,
                            reservers = { {name = pName, count = e.count or 1} }
                        })
                    end
                end
            end
        end

        for _, bName in ipairs(bossOrder) do
            local b = bossMap[bName]
            if #b.items > 0 then
                table.sort(b.items, function(i1, i2) return (i1.count or 0) > (i2.count or 0) end)
                local engBossName = bossTrans[bName] or bName
                text = text .. "**[" .. engBossName .. "]**\n"
                for _, item in ipairs(b.items) do
                    local parts = {}
                    for _, res in ipairs(item.reservers) do
                        local countStr = res.count > 1 and (" x" .. res.count) or ""
                        table.insert(parts, res.name .. countStr)
                    end
                    text = text .. "* " .. item.itemName .. " (" .. item.count .. "): " .. table.concat(parts, ", ") .. "\n"
                end
                text = text .. "\n"
            end
        end
    end

    self.exportFrame.editBox:SetText(text)
    self.exportFrame:Show()
    self.exportFrame.editBox:HighlightText()
    self.exportFrame.editBox:SetFocus()
end
