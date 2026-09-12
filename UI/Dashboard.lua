--------------------------------------------------------------
-- SoftRollManager  —  UI/Dashboard.lua
-- Вкладка "Панель керування": список учасників рейду, ролі,
-- ліміти SR, контекстне меню ролі, попап перевизначення ліміту.
-- Сумісно з WoW 3.3.5a (WotLK)
--------------------------------------------------------------

local SR = SoftRoll

-- ╔══════════════════════════════════════════════════════════╗
-- ║               ВКЛАДКА 1 — ПАНЕЛЬ КЕРУВАННЯ              ║
-- ╚══════════════════════════════════════════════════════════╝

function SR:BuildDashboard(parent)

    -- ── Рядок 1: Випадаюче меню підземелля + режиму SR ──

    local instLabel = SR:MakeLabel(parent, 11, 0.85, 0.85, 0.55)
    instLabel:SetPoint("TOPLEFT", 10, -10)
    instLabel:SetText("Підземелля:")

    local instDD = CreateFrame("Frame", "SoftRollInstanceDD", parent, "UIDropDownMenuTemplate")
    instDD:SetPoint("LEFT", instLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(instDD, 110)
    UIDropDownMenu_Initialize(instDD, function(self, level)
        level = level or 1
        if level ~= 1 then return end
        for _, inst in ipairs(SR.INSTANCES) do
            local info  = UIDropDownMenu_CreateInfo()
            info.text   = SR.INSTANCE_LABELS[inst]
            info.value  = inst
            info.checked = (SR.db.instance == inst)
            info.func   = function()
                SR.db.instance = inst
                if inst == "RS" then
                    SR.db.srMode = "rs_x1"
                elseif SR.db.srMode == "rs_x1" then
                    SR.db.srMode = "classic"
                end

                UIDropDownMenu_SetText(instDD, SR.INSTANCE_LABELS[inst])
                if SR.modeDD then

                    UIDropDownMenu_SetText(SR.modeDD, SR.SR_MODE_LABELS[SR.db.srMode])
                end
                SR:UpdateDashboard()
                SR:UpdateLedger()
                if SR:IsSessionHost() then
                    SR:SendAddonMsg("I|" .. SR.db.instance .. "|" .. SR.db.srMode, "RAID")
                elseif SR.sessionActive and SR:CanEditSession() then
                    SR:SendAddonMsg("I|" .. SR.db.instance .. "|" .. SR.db.srMode, "WHISPER", SR.sessionHost)
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    UIDropDownMenu_SetText(instDD, SR.INSTANCE_LABELS[SR.db.instance])
    self.instDD = instDD

    -- Випадаюче меню режиму SR (x3 / 3/4)
    local modeLabel = SR:MakeLabel(parent, 11, 0.85, 0.85, 0.55)
    modeLabel:SetPoint("LEFT", instDD, "RIGHT", 10, 2)
    modeLabel:SetText("Режим софту:")

    local modeDD = CreateFrame("Frame", "SoftRollModeDD", parent, "UIDropDownMenuTemplate")
    modeDD:SetPoint("LEFT", modeLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(modeDD, 110)
    UIDropDownMenu_Initialize(modeDD, function(self, level)
        level = level or 1
        if level ~= 1 then return end
        local modes = (SR.db.instance == "RS") and { "rs_x1" } or { "classic", "dynamic" }
        for _, mode in ipairs(modes) do
            local info  = UIDropDownMenu_CreateInfo()
            info.text   = SR.SR_MODE_LABELS[mode]
            info.value  = mode
            info.checked = (SR.db.srMode == mode)
            info.func   = function()
                SR.db.srMode = mode

                UIDropDownMenu_SetText(modeDD, SR.SR_MODE_LABELS[mode])
                SR:UpdateDashboard()
                SR:UpdateLedger()
                SR:Print(format(SR.L.PRINT_MODE_CHANGED, SR.SR_MODE_LABELS[mode]))
                if SR:IsSessionHost() then
                    SR:SendAddonMsg("I|" .. SR.db.instance .. "|" .. SR.db.srMode, "RAID")
                elseif SR.sessionActive and SR:CanEditSession() then
                    SR:SendAddonMsg("I|" .. SR.db.instance .. "|" .. SR.db.srMode, "WHISPER", SR.sessionHost)
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    UIDropDownMenu_SetText(modeDD, SR.SR_MODE_LABELS[SR.db.srMode])
    self.modeDD = modeDD

    -- ── Рядок 1b: Блокування реєстрацій ──
    local lockBtn = SR:MakeButton(parent, "Заблокувати софти", 150, 22)
    lockBtn:SetPoint("TOPLEFT", 10, -40)
    lockBtn:SetScript("OnClick", function()
        if SR:IsSessionReadOnly() then return end
        local newLock = not SR.locked
        -- Ко-хост: надсилаємо запит хосту замість локальної зміни
        if SR.sessionActive and not SR:IsSessionHost() then
            if SR:CanEditSession() then
                SR:SendAddonMsg("T|" .. (newLock and "1" or "0"), "WHISPER", SR.sessionHost)
                SR:Print(SR.L.PRINT_LOCK_REQUEST_SENT)
            end
            return
        end
        SR.locked = newLock
        SR.sessionLocked = newLock
        SR.db.locked = SR.locked  -- зберігаємо в db
        SR:UpdateDashboard()
        if SR.BroadcastLockState then SR:BroadcastLockState() end
        local chatType = SR:GetAnnouncementChannel(true)
        if SR.locked then
            SR:Print(SR.L.PRINT_STATUS_LOCKED)
            SendChatMessage(SR.L.SESSION_LOCKED, chatType)
        else
            SR:Print(SR.L.PRINT_STATUS_UNLOCKED)
            SendChatMessage(SR.L.SESSION_UNLOCKED, chatType)
        end
    end)
    self.lockBtn = lockBtn

    local statsLabel = SR:MakeLabel(parent, 14, 1, 0.82, 0, "RIGHT")
    statsLabel:SetPoint("TOPRIGHT", -15, -40)
    statsLabel:SetText("0 / 0")
    self.statsLabel = statsLabel

    -- ── Заголовки стовпців ──
    local hdr = CreateFrame("Frame", nil, parent)
    hdr:SetPoint("TOPLEFT", 8, -66)
    hdr:SetPoint("TOPRIGHT", -8, -66)
    hdr:SetHeight(20)

    local function ColHdr(text, x, w, align)
        local fs = SR:MakeLabel(hdr, 9, SR.UI.C.label[1], SR.UI.C.label[2], SR.UI.C.label[3], align or "LEFT")
        if align == "CENTER" then
            fs:SetPoint("CENTER", hdr, "LEFT", x + w / 2, 0)
        elseif align == "RIGHT" then
            fs:SetPoint("RIGHT", hdr, "LEFT", x + w, 0)
        else
            fs:SetPoint("LEFT", x, 0)
            fs:SetWidth(w)
        end
        fs:SetText(text)
    end
    ColHdr("Ім'я",      15,  130)
    ColHdr("Клас",     160,  50)
    ColHdr("Роль",      230,  80, "CENTER")
    ColHdr("Викор.",    320,  60, "CENTER")
    ColHdr("Заміна",    390,  60, "CENTER")

    local sep = SR:MakeAccentLine(parent, SR.UI.C.sep[1], SR.UI.C.sep[2], SR.UI.C.sep[3], SR.UI.C.sep[4])
    sep:SetPoint("TOPLEFT",  8, -86)
    sep:SetPoint("TOPRIGHT", -8, -86)

    -- ── Фрейм прокрутки для рейду ──
    local sf = CreateFrame("ScrollFrame", "SRDashScroll", parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -89)
    sf:SetPoint("BOTTOMRIGHT", -28, 8)
    sf:SetScript("OnSizeChanged", function(self)
        if SR.dashChild then
            SR.dashChild:SetWidth(self:GetWidth())
        end
    end)

    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(sf:GetWidth() > 0 and sf:GetWidth() or 462)
    child:SetHeight(1)
    sf:SetScrollChild(child)
    self.dashScroll = sf
    self.dashChild = child
    self.dashRows  = {}

    -- ── Контекстне меню ролей (одне спільне випадаюче меню) ──
    local roleMenu = CreateFrame("Frame", "SoftRollRoleMenu", UIParent, "UIDropDownMenuTemplate")
    self.roleMenu  = roleMenu
end

--------------------------------------------------------------
-- Фабрика рядків панелі керування
--------------------------------------------------------------
local function GetDashRow(container, index)
    local rows = SR.dashRows
    if rows[index] then return rows[index] end

    local row = CreateFrame("Frame", nil, container)
    row:SetHeight(SR.UI.ROW_H)
    row:SetPoint("TOPLEFT",  0, -(index - 1) * SR.UI.ROW_H)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * SR.UI.ROW_H)

    -- Фон з чергуванням
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bg:SetVertexColor(0.12, 0.12, 0.18, (index % 2 == 0) and 0.35 or 0)
    row.bg = bg

    -- Підсвітка при наведенні
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    hl:SetVertexColor(0.3, 0.4, 0.6, 0.25)

    -- Ім'я
    row.nameFS = SR:MakeLabel(row, 11, 1, 1, 1, "LEFT")
    row.nameFS:SetPoint("LEFT", 15, 0)
    row.nameFS:SetWidth(130)

    -- Кнопка для підказки при наведенні
    row.nameBtn = CreateFrame("Button", nil, row)
    row.nameBtn:SetAllPoints(row.nameFS)
    row.nameBtn:SetScript("OnEnter", function(self)
        if self:GetParent().playerName then
            SR:ShowPlayerSRTooltip(self, self:GetParent().playerName)
        end
    end)
    row.nameBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Клас
    row.classFS = SR:MakeLabel(row, 10, 0.7, 0.7, 0.7, "LEFT")
    row.classFS:SetPoint("LEFT", 160, 0)
    row.classFS:SetWidth(50)

    -- Кнопка ролі (клік для відкриття меню)
    row.roleBtn = CreateFrame("Button", nil, row)
    row.roleBtn:SetSize(80, 18)
    row.roleBtn:SetPoint("LEFT", 230, 0)

    local roleBg = row.roleBtn:CreateTexture(nil, "BACKGROUND")
    roleBg:SetAllPoints()
    roleBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    roleBg:SetVertexColor(0.2, 0.2, 0.28, 0.8)
    row.roleBtn.bg = roleBg

    row.roleBtn.fs = SR:MakeLabel(row.roleBtn, 10, 1, 1, 1, "CENTER")
    row.roleBtn.fs:SetPoint("CENTER")

    row.roleBtn:SetScript("OnEnter", function(self)
        roleBg:SetVertexColor(0.3, 0.3, 0.42, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Клікніть для зміни ролі")
        GameTooltip:Show()
    end)
    row.roleBtn:SetScript("OnLeave", function()
        roleBg:SetVertexColor(0.2, 0.2, 0.28, 0.8)
        GameTooltip:Hide()
    end)

    -- Використано SR
    row.usedFS = SR:MakeLabel(row, 11, 0.7, 0.9, 1.0, "CENTER")
    row.usedFS:SetPoint("LEFT", 320, 0)
    row.usedFS:SetWidth(60)

    -- Кнопка заміни (встановити власний ліміт)
    row.overrideBtn = CreateFrame("Button", nil, row)
    row.overrideBtn:SetSize(60, 18)
    row.overrideBtn:SetPoint("LEFT", 390, 0)

    local ovrBg = row.overrideBtn:CreateTexture(nil, "BACKGROUND")
    ovrBg:SetAllPoints()
    ovrBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    ovrBg:SetVertexColor(0.18, 0.18, 0.25, 0.8)
    row.overrideBtn.bg = ovrBg

    row.overrideBtn.fs = SR:MakeLabel(row.overrideBtn, 10, 1, 0.7, 0.2, "CENTER")
    row.overrideBtn.fs:SetPoint("CENTER")

    row.overrideBtn:SetScript("OnEnter", function(self)
        ovrBg:SetVertexColor(0.28, 0.28, 0.38, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Змінити ліміт SR")
        GameTooltip:AddLine("Для тих, хто приєднався пізніше: встановіть", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("ліміт SR (наприклад, x1, x2)", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    row.overrideBtn:SetScript("OnLeave", function()
        ovrBg:SetVertexColor(0.18, 0.18, 0.25, 0.8)
        GameTooltip:Hide()
    end)

    rows[index] = row
    return row
end

--------------------------------------------------------------
-- ОНОВЛЕННЯ ПАНЕЛІ КЕРУВАННЯ
--------------------------------------------------------------
function SR:UpdateDashboard()
    if not self.dashChild then return end
    if self.dashScroll and self.dashScroll:GetWidth() > 0 then
        self.dashChild:SetWidth(self.dashScroll:GetWidth())
    end

    -- Перевірка чи ми лідер і чи не потрібно авто-стартнути сесію (якщо гра не повідомила вчасно при вході)
    if not self.sessionActive and self:IsSessionLeader() and (GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0) then
        self:AutoStartSession()
    end

    -- Оновлення тексту кнопки блокування
    if self.lockBtn then
        if self.locked then
            self.lockBtn:SetText("Розблокувати софти")
        else
            self.lockBtn:SetText("Заблокувати софти")
        end
    end

    -- Оновлення тексту дропдаунів (після синхронізації з хоста)
    if self.instDD and self.db.instance then
        UIDropDownMenu_SetText(self.instDD, self.INSTANCE_LABELS[self.db.instance] or self.db.instance)
    end
    if self.modeDD and self.db.srMode then
        UIDropDownMenu_SetText(self.modeDD, self.SR_MODE_LABELS[self.db.srMode] or self.db.srMode)
    end

    -- Статус сесії
    self:UpdateSessionBanner()
    self:UpdateAdminReadOnly()

    local readOnly = self:IsSessionReadOnly()
    local members = self:GetRaidMembers()

    -- Якщо не в рейді, показати хоча б самого гравця
    if #members == 0 then
        local pName = UnitName("player")
        local _, pClass = UnitClass("player")
        members = { { name = pName, rank = 2, class = pClass, online = true, level = UnitLevel("player"), raidRole = "NONE" } }
    end

    -- Заповнення рядків
    local filledCount = 0
    for i, m in ipairs(members) do
        local row = GetDashRow(self.dashChild, i)
        row:Show()

        -- Ім'я (в кольорі класу)
        local cc = self:GetClassColor(m.class)
        row.playerName = m.name
        row.nameFS:SetText(self:ColorText(m.name, cc.r, cc.g, cc.b))

        -- Клас
        local classLocale = m.class and m.class:sub(1,1) .. m.class:sub(2):lower() or "?"
        if m.class == "DEATHKNIGHT" then classLocale = "DK" end
        row.classFS:SetText(classLocale)
        row.classFS:SetTextColor(cc.r, cc.g, cc.b)

        -- Кнопка ролі
        local role  = self:GetPlayerRole(m.name)
        local rc    = self.ROLE_COLORS[role]
        row.roleBtn.fs:SetText(self.ROLE_LABELS[role])
        row.roleBtn.fs:SetTextColor(rc.r, rc.g, rc.b)
        row.roleBtn.playerName = m.name

        row.roleBtn:SetScript("OnClick", function(self)
            if SR:IsSessionReadOnly() then return end
            SR:OpenRoleMenu(self.playerName, self)
        end)
        if readOnly then row.roleBtn:Disable() else row.roleBtn:Enable() end

    -- Ліміт SR для розрахунку використання
    local limit = self:GetSRLimit(m.name)
    local hasOvr = self:HasOverride(m.name)

        -- Використано SR
        local used  = self:GetUsedSRCount(m.name)
        if used > 0 then filledCount = filledCount + 1 end
        if row.usedFS then
            row.usedFS:SetText(used .. " / " .. limit)
            if used >= limit then
                row.usedFS:SetTextColor(0.9, 0.3, 0.3)
            elseif used > 0 then
                row.usedFS:SetTextColor(1.0, 0.8, 0.2)
            else
                row.usedFS:SetTextColor(0.5, 0.5, 0.5)
            end
        end

        -- Кнопка заміни (перевизначення)
        if hasOvr then
            row.overrideBtn.fs:SetText("x" .. limit)
            row.overrideBtn.fs:SetTextColor(1, 0.6, 0.1)
        else
            row.overrideBtn.fs:SetText("—")
            row.overrideBtn.fs:SetTextColor(0.5, 0.5, 0.5)
        end
        row.overrideBtn.playerName = m.name
        row.overrideBtn:SetScript("OnClick", function(self)
            if SR:IsSessionReadOnly() then return end
            SR:ShowOverridePopup(self.playerName, self)
        end)
        if readOnly then row.overrideBtn:Disable() else row.overrideBtn:Enable() end

        -- Оновлення чергування
        row.bg:SetVertexColor(0.12, 0.12, 0.18, (i % 2 == 0) and 0.35 or 0)
    end

    -- Приховування зайвих рядків
    for i = #members + 1, #self.dashRows do
        self.dashRows[i]:Hide()
    end

    -- Встановлення висоти, щоб працювала прокрутка
    self.dashChild:SetHeight(math.max(1, #members * SR.UI.ROW_H))

    if self.statsLabel then
        self.statsLabel:SetText(filledCount .. " / " .. #members)
    end
end

--------------------------------------------------------------
-- Контекстне меню ролі
--------------------------------------------------------------
function SR:OpenRoleMenu(playerName, anchor)
    if DropDownList1 and DropDownList1:IsShown() and UIDROPDOWNMENU_OPEN_MENU == self.roleMenu then
        if self.roleMenu.lastAnchor == anchor then
            CloseDropDownMenus()
            self.roleMenu.lastAnchor = nil
            return
        else
            CloseDropDownMenus()
        end
    end
    self.roleMenu.lastAnchor = anchor

    self.roleMenuTarget = playerName
    UIDropDownMenu_Initialize(self.roleMenu, function(self, level)
        level = level or 1
        if level ~= 1 then return end
        for _, role in ipairs(SR.ROLES) do
            local info    = UIDropDownMenu_CreateInfo()
            info.text     = SR.ROLE_LABELS[role]
            info.value    = role
            local rc      = SR.ROLE_COLORS[role]
            info.colorCode = format("|cff%02x%02x%02x", rc.r*255, rc.g*255, rc.b*255)
            info.checked  = (SR:GetPlayerRole(SR.roleMenuTarget) == role)
            info.func     = function()
                SR:SetPlayerRole(SR.roleMenuTarget, role)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, self.roleMenu, anchor, 0, 0)
end


-- ╔══════════════════════════════════════════════════════════╗
-- ║         ВІКНО ПЕРЕВИЗНАЧЕННЯ ЛІМІТІВ ГРАВЦЯ             ║
-- ╚══════════════════════════════════════════════════════════╝

function SR:BuildOverridePopup()
    local popup = CreateFrame("Frame", "SROverridePopup", UIParent)
    popup:SetSize(268, 162)
    popup:SetPoint("CENTER")
    SR:ApplyDialogBackdrop(popup, 0.08, 0.08, 0.12, 0.98)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(100)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop",  popup.StopMovingOrSizing)
    popup:Hide()

    tinsert(UISpecialFrames, "SROverridePopup")

    -- Акцентна лінія під заголовком
    local popupTopLine = SR:MakeAccentLine(popup, SR.UI.C.gold[1], SR.UI.C.gold[2], SR.UI.C.gold[3], 0.75)
    popupTopLine:SetPoint("TOPLEFT",  popup, "TOPLEFT",  14, -12)
    popupTopLine:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -14, -12)

    local titleFS = SR:MakeLabel(popup, 12, SR.UI.C.gold[1], SR.UI.C.gold[2], SR.UI.C.gold[3])
    titleFS:SetPoint("TOP", 0, -18)
    popup.titleFS = titleFS

    popup.statusFS = SR:MakeLabel(popup, 10, 0.75, 0.75, 0.75, "CENTER")
    popup.statusFS:SetPoint("TOP", titleFS, "BOTTOM", 0, -4)
    popup.statusFS:SetWidth(240)

    local desc = SR:MakeLabel(popup, 10, 0.55, 0.55, 0.55, "CENTER")
    desc:SetPoint("TOP", popup.statusFS, "BOTTOM", 0, -2)
    desc:SetWidth(240)
    desc:SetText("Власний ліміт SR для тих, хто приєднався пізніше")

    -- Кнопки швидкого вибору: x1 x2 x3 x4
    local btnY = -72
    local btnW, btnGap = 52, 8
    local rowW = 4 * btnW + 3 * btnGap
    local startX = (268 - rowW) / 2
    local vals = { 1, 2, 3, 4 }
    popup.valBtns = {}
    for i, v in ipairs(vals) do
        local btn = SR:MakeButton(popup, "x" .. v, btnW, 24)
        btn:SetPoint("TOPLEFT", startX + (i - 1) * (btnW + btnGap), btnY)
        btn:SetScript("OnClick", function()
            SR:SetPlayerOverride(popup.targetPlayer, v)
            popup:Hide()
        end)
        popup.valBtns[i] = btn
    end

    local resetBtn = SR:MakeButton(popup, "За замовч.", 118, 24)
    resetBtn:SetPoint("TOPLEFT", startX, btnY - 34)
    resetBtn:SetScript("OnClick", function()
        SR:SetPlayerOverride(popup.targetPlayer, nil)
        popup:Hide()
    end)
    popup.resetBtn = resetBtn

    local cancelBtn = SR:MakeButton(popup, "Скасувати", 118, 24)
    cancelBtn:SetPoint("TOPLEFT", resetBtn, "TOPRIGHT", btnGap, 0)
    cancelBtn:SetScript("OnClick", function() popup:Hide() end)

    self.overridePopup = popup
end

function SR:ShowOverridePopup(playerName, anchor)
    local popup = self.overridePopup
    if not popup then return end

    popup.targetPlayer = playerName
    popup.titleFS:SetText("Перевизначення ліміту: " .. playerName)

    local base    = self:GetBaseSRLimit(playerName)
    local current = self:GetPlayerOverride(playerName)
    local role    = self.ROLE_SHORT[self:GetPlayerRole(playerName)] or "?"
    if current then
        popup.statusFS:SetText(
            "Стандарт для ролі (" .. role .. "): |cffffcc00x" .. base
            .. "|r   Заміна: |cff44ff44x" .. current .. "|r")
    else
        popup.statusFS:SetText(
            "Стандарт для ролі (" .. role .. "): |cffffcc00x" .. base .. "|r   (без змін)")
    end

    for i, btn in ipairs(popup.valBtns or {}) do
        local fs = btn:GetFontString()
        if fs then
            if current == i then
                fs:SetTextColor(0.4, 1, 0.4)
            else
                fs:SetTextColor(1, 1, 1)
            end
        end
    end

    -- Завжди центрувати
    popup:ClearAllPoints()
    popup:SetPoint("CENTER")
    popup:Show()
end

