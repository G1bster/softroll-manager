--------------------------------------------------------------
-- SoftRollManager  —  UI.lua  (v2.0)
-- Повний графічний інтерфейс: Панель керування, Реєстр, Оглядач здобичі, 
-- Роздача здобичі, Кнопка біля міні-карти, Перевизначення лімітів
-- Сумісно з WoW 3.3.5a (WotLK)
--------------------------------------------------------------

local SR = SoftRoll

-- ── Централізована палітра кольорів ──
local C = {
    blue   = { 0.22, 0.56, 1.00 },
    gold   = { 1.00, 0.75, 0.15 },
    green  = { 0.30, 0.95, 0.40 },
    red    = { 1.00, 0.30, 0.30 },
    orange = { 1.00, 0.55, 0.15 },
    dim    = { 0.50, 0.50, 0.55 },
    label  = { 0.68, 0.68, 0.48 },
    sep    = { 0.20, 0.32, 0.60, 0.65 },
}

-- Константи макета
local FRAME_W, FRAME_H = 520, 480
local STATUS_H = 24   -- висота нижньої статус-смуги
local TAB_H   = 30
local HDR_H   = 32
local PAD     = 12
local ROW_H   = 22
local LEDGER_ROW_H = 32   -- вищі рядки для іконок предметів
local ITEM_H  = 36   -- висота рядка предмета в оглядачі здобичі
local LEDGER_MAX_ICONS = 6

--------------------------------------------------------------
-- ДОПОМІЖНА ФУНКЦІЯ: Стилізований фон підпанелі
--------------------------------------------------------------
local PANEL_BD = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function ApplyPanelStyle(frame, r, g, b, a)
    frame:SetBackdrop(PANEL_BD)
    frame:SetBackdropColor(r or 0.08, g or 0.08, b or 0.12, a or 0.92)
    frame:SetBackdropBorderColor(0.22, 0.32, 0.55, 0.65)
end

--------------------------------------------------------------
-- ДОПОМІЖНА ФУНКЦІЯ: Багаторазова стилізована кнопка
--------------------------------------------------------------
local function MakeButton(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetText(text)
    b:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 11)
    return b
end

-- (Видалено: Горизонтальний прогрес-бар)

-- Декоративна горизонтальна лінія
local function MakeAccentLine(parent, r, g, b, a)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(2)
    t:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    t:SetVertexColor(r or C.blue[1], g or C.blue[2], b or C.blue[3], a or 0.85)
    return t
end

--------------------------------------------------------------
-- ДОПОМІЖНА ФУНКЦІЯ: Скорочення для FontString
--------------------------------------------------------------
local function MakeLabel(parent, size, r, g, b, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetFont("Fonts\\FRIZQT__.TTF", size or 11)
    fs:SetTextColor(r or 1, g or 1, b or 1, 1)
    if justify then fs:SetJustifyH(justify) end
    return fs
end

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
    accent:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 0)
    tb.accent = accent

    local txt = tb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    txt:SetPoint("CENTER", 0, 0)
    txt:SetText(text)
    txt:SetFont("Fonts\\FRIZQT__.TTF", 11)
    tb.label = txt
    
    tb:SetScript("OnEnter", function(self)
        if self.active then return end
        self.bg:SetVertexColor(0.15, 0.15, 0.22, 0.9)
    end)
    tb:SetScript("OnLeave", function(self)
        if self.active then return end
        self.bg:SetVertexColor(0.10, 0.10, 0.16, 0.9)
    end)
    return tb
end

--------------------------------------------------------------
-- ДОПОМІЖНА ФУНКЦІЯ: Підказка (Tooltip) з SR гравця
--------------------------------------------------------------
function SR:ShowPlayerSRTooltip(anchor, playerName)
    local list = self.db.reserves[playerName]
    if not list or #list == 0 then return end

    local used  = self:GetUsedSRCount(playerName)
    local limit = self:GetSRLimit(playerName)

    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:SetText("Софт-роли: " .. playerName, 1, 0.82, 0)
    GameTooltip:AddLine(used .. " з " .. limit .. " використано", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Наведіть на іконки для деталей", 0.5, 0.5, 0.5)

    for _, e in ipairs(list) do
        local itemID = e.itemID or self:GetItemIDFromLink(e.itemLink)
        if itemID then self:QueueItemCache(itemID) end
        local name, _, quality = GetItemInfo(itemID or 0)
        if not name and e.itemLink then
            name = e.itemLink:match("%[(.-)%]")
        end
        name = name or ("Предмет #" .. tostring(itemID or "?"))
        local r, g, b = GetItemQualityColor(quality or 1)
        local count = e.count or 1
        local suffix = count > 1 and (" x" .. count) or ""
        GameTooltip:AddLine(name .. suffix, r, g, b)
    end
    GameTooltip:Show()
end

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
            btn = CreateFrame("Button", nil, row.iconStrip)
            btn:SetSize(26, 26)

            local iconBg = btn:CreateTexture(nil, "BACKGROUND")
            iconBg:SetAllPoints()
            iconBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
            iconBg:SetVertexColor(0.08, 0.08, 0.12, 0.8)

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", 1, -1)
            icon:SetPoint("BOTTOMRIGHT", -1, 1)
            btn.icon = icon

            local del = CreateFrame("Button", nil, btn)
            del:SetSize(12, 12)
            del:SetPoint("TOPRIGHT", 4, 4)
            del:SetNormalTexture("Interface\\BUTTONS\\UI-GroupLoot-Pass-Up")
            del:SetHighlightTexture("Interface\\BUTTONS\\UI-GroupLoot-Pass-Highlight")
            del:SetPushedTexture("Interface\\BUTTONS\\UI-GroupLoot-Pass-Down")
            del:SetScript("OnClick", function()
                if not btn.itemID then return end
                if SR:CanEditSession() and row.playerName ~= SR:GetLocalPlayerName() then
                    local dialog = StaticPopup_Show("SOFTROLL_CONFIRM_REMOVE_ITEM", btn.itemLink or ("Предмет #" .. btn.itemID), row.playerName)
                    if dialog then dialog.data = { target = row.playerName, itemID = btn.itemID, link = btn.itemLink or ("Предмет #" .. btn.itemID) } end
                else
                    if SR:IsSessionHost() or (SR:IsSessionLeader() and not SR.sessionActive) then
                        SR:RemoveSR(row.playerName, btn.itemID)
                        SR:Print("Видалено предмет зі списку " .. row.playerName)
                    else
                        SR:SendAddonMsg("R|" .. row.playerName .. "|" .. btn.itemID, "WHISPER", SR.sessionHost)
                        SR:Print("Запит на видалення надіслано хосту...")
                    end
                end
            end)
            btn.delBtn = del

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
-- =============== ГОЛОВНЕ ВІКНО ==============================
--------------------------------------------------------------
function SR:CreateUI()

    -- Запобігання подвійному створенню
    if self.mainFrame then return end

    -----------------------------------------------------------
    -- Головний контейнер
    -----------------------------------------------------------
    local f = CreateFrame("Frame", "SoftRollMainFrame", UIParent)
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetBackdropColor(0.07, 0.07, 0.10, 0.97)
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
    local hdrLine = MakeAccentLine(f)
    hdrLine:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD + 20, -(HDR_H + 6))
    hdrLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + 20), -(HDR_H + 6))

    -----------------------------------------------------------
    -- Кнопка закриття
    -----------------------------------------------------------
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local infoBtn = CreateFrame("Button", nil, f)
    infoBtn:SetSize(24, 24)
    infoBtn:SetPoint("RIGHT", close, "LEFT", -4, 0)
    infoBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    infoBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    infoBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    local infoIcon = infoBtn:CreateTexture(nil, "OVERLAY")
    infoIcon:SetTexture("Interface\\FriendsFrame\\InformationIcon")
    infoIcon:SetSize(14, 14)
    infoIcon:SetPoint("CENTER", infoBtn, "CENTER", 0, -1)
    
    infoBtn:SetScript("OnClick", function() SR:ToggleInfoFrame() end)
    infoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Інформація та Інструкція")
        GameTooltip:Show()
    end)
    infoBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.infoBtn = infoBtn

    local settingsBtn = CreateFrame("Button", nil, f)
    settingsBtn:SetSize(24, 24)
    settingsBtn:SetPoint("RIGHT", infoBtn, "LEFT", -4, 0)
    settingsBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    settingsBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    settingsBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    local settingsIcon = settingsBtn:CreateTexture(nil, "OVERLAY")
    settingsIcon:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
    settingsIcon:SetSize(14, 14)
    settingsIcon:SetPoint("CENTER", settingsBtn, "CENTER", 0, -1)
    
    local coHostDD = CreateFrame("Frame", "SRCoHostDropDown", f, "UIDropDownMenuTemplate")
    coHostDD:Hide()
    
    settingsBtn:SetScript("OnClick", function(self)
        if not IsRaidLeader() then
            SR:Print("Тільки РЛ може призначати помічників.")
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
            if name and rank > 0 and name ~= SR:GetLocalPlayerName() then
                table.insert(assistants, name)
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
                SR.db.coHosts[name] = checked
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
    local tabNames = { "Панель керування", "Список софтів", "Огляд луту", "Роздача луту" }

    local tabW = 116
    local spacing = 4
    local startX = 22 -- (520 - (116*4 + 4*3)) / 2

    for i, label in ipairs(tabNames) do
        local tb = CreateFrame("Button", "SRTab" .. i, f)
        tb:SetSize(tabW, TAB_H)
        tb:SetPoint("TOPLEFT", startX + (i - 1) * (tabW + spacing), -(HDR_H + 20))

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
        accent:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 0)
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
        p:SetPoint("TOPLEFT", PAD, -(HDR_H + 20 + TAB_H + 4))
        p:SetPoint("BOTTOMRIGHT", -PAD, PAD + STATUS_H + 4)
        ApplyPanelStyle(p)
        p:Hide()
        panels[i] = p
    end
    self.panels = panels

    -- Нижня статус-смуга
    local statusBar = CreateFrame("Frame", nil, f)
    statusBar:SetPoint("BOTTOMLEFT",  PAD, PAD)
    statusBar:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    statusBar:SetHeight(STATUS_H)
    ApplyPanelStyle(statusBar, 0.05, 0.07, 0.12, 0.98)
    local statusTopLine = MakeAccentLine(statusBar, C.blue[1], C.blue[2], C.blue[3], 0.30)
    statusTopLine:SetPoint("TOPLEFT",  statusBar, "TOPLEFT",  0, 0)
    statusTopLine:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT", 0, 0)
    local statusDot = statusBar:CreateTexture(nil, "ARTWORK")
    statusDot:SetSize(8, 8)
    statusDot:SetPoint("LEFT", 10, 0)
    statusDot:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    statusDot:SetVertexColor(0.40, 0.40, 0.45, 1)
    self.statusDot = statusDot
    local statusFS = MakeLabel(statusBar, 10, 0.50, 0.50, 0.55, "LEFT")
    statusFS:SetPoint("LEFT", statusDot, "RIGHT", 6, 0)
    statusFS:SetWidth(460)
    self.statusBarFS = statusFS
    local statusMode = MakeLabel(statusBar, 10, C.label[1], C.label[2], C.label[3], "RIGHT")
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
            if tb.accent then tb.accent:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 1) end
            tb.active = true
            self.panels[i]:Show()
        else
            tb.bg:SetVertexColor(0.10, 0.10, 0.16, 0.9)
            tb.label:SetTextColor(0.52, 0.52, 0.58)
            if tb.accent then tb.accent:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 0) end
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
                if tb.accent then tb.accent:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 0) end
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
        if self.settingsBtn then self.settingsBtn:Hide() end
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

    if self.settingsBtn then
        if IsRaidLeader() then
            self.settingsBtn:Show()
        else
            self.settingsBtn:Hide()
        end
    end

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
    local canChangeSettings = self:IsAdmin()
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
    
    if self.lbTargetDD then
        if canEdit then
            self.lbTargetDD:Show()
            UIDropDownMenu_Initialize(self.lbTargetDD, function(self, level)
                level = level or 1
                if level ~= 1 then return end
                
                local info = UIDropDownMenu_CreateInfo()
                info.text = "Собі"
                info.value = SR:GetLocalPlayerName()
                info.checked = (SR.lbTargetPlayer == nil or SR.lbTargetPlayer == info.value)
                info.func = function()
                    SR.lbTargetPlayer = info.value
                    UIDropDownMenu_SetText(SR.lbTargetDD, "Собі")
                end
                UIDropDownMenu_AddButton(info, level)

                local members = SR:GetRaidMembers()
                if #members > 0 then
                    local infoTitle = UIDropDownMenu_CreateInfo()
                    infoTitle.text = "Рейд"
                    infoTitle.isTitle = true
                    infoTitle.notCheckable = true
                    UIDropDownMenu_AddButton(infoTitle, level)

                    for _, m in ipairs(members) do
                        if m.name ~= SR:GetLocalPlayerName() then
                            local pInfo = UIDropDownMenu_CreateInfo()
                            pInfo.text = m.name
                            pInfo.value = m.name
                            pInfo.checked = (SR.lbTargetPlayer == m.name)
                            pInfo.func = function()
                                SR.lbTargetPlayer = m.name
                                UIDropDownMenu_SetText(SR.lbTargetDD, m.name)
                            end
                            UIDropDownMenu_AddButton(pInfo, level)
                        end
                    end
                end
            end)
            if not SR.lbTargetPlayer or SR.lbTargetPlayer == SR:GetLocalPlayerName() then
                UIDropDownMenu_SetText(self.lbTargetDD, "Собі")
            else
                UIDropDownMenu_SetText(self.lbTargetDD, SR.lbTargetPlayer)
            end
        else
            self.lbTargetDD:Hide()
            SR.lbTargetPlayer = nil
        end
    end

    self._uiReadOnly = readOnly
    self._uiCanEdit  = canEdit
end


-- ╔══════════════════════════════════════════════════════════╗
-- ║               ВКЛАДКА 1 — ПАНЕЛЬ КЕРУВАННЯ              ║
-- ╚══════════════════════════════════════════════════════════╝

function SR:BuildDashboard(parent)

    -- ── Рядок 1: Випадаюче меню підземелля + режиму SR ──

    local instLabel = MakeLabel(parent, 11, 0.85, 0.85, 0.55)
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
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    UIDropDownMenu_SetText(instDD, SR.INSTANCE_LABELS[SR.db.instance])
    self.instDD = instDD

    -- Випадаюче меню режиму SR (x3 / 3/4)
    local modeLabel = MakeLabel(parent, 11, 0.85, 0.85, 0.55)
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
                SR:Print("Режим SR змінено на |cffffcc00" .. SR.SR_MODE_LABELS[mode] .. "|r")
                if SR:IsSessionHost() then
                    SR:SendAddonMsg("I|" .. SR.db.instance .. "|" .. SR.db.srMode, "RAID")
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    UIDropDownMenu_SetText(modeDD, SR.SR_MODE_LABELS[SR.db.srMode])
    self.modeDD = modeDD

    -- ── Рядок 1b: Блокування реєстрацій ──
    local lockBtn = MakeButton(parent, "Заблокувати софти", 150, 22)
    lockBtn:SetPoint("TOPLEFT", 10, -40)
    lockBtn:SetScript("OnClick", function()
        if SR:IsSessionReadOnly() then return end
        SR.locked = not SR.locked
        SR.db.locked = SR.locked  -- зберігаємо в db
        SR:UpdateDashboard()
        if SR.BroadcastLockState then SR:BroadcastLockState() end
        local chatType = (GetNumRaidMembers() > 0) and "RAID_WARNING" or "SAY"
        if SR.locked then
            SR:Print("Софт-роли |cffff4444ЗАБЛОКОВАНО|r.")
            SendChatMessage("Реєстрацію софт-ролів ЗАБЛОКОВАНО.", chatType)
        else
            SR:Print("Софт-роли |cff44ff44РОЗБЛОКОВАНО|r.")
            SendChatMessage("Реєстрацію софт-ролів РОЗБЛОКОВАНО.", chatType)
        end
    end)
    self.lockBtn = lockBtn

    local statsLabel = MakeLabel(parent, 14, 1, 0.82, 0, "RIGHT")
    statsLabel:SetPoint("TOPRIGHT", -15, -40)
    statsLabel:SetText("0 / 0")
    self.statsLabel = statsLabel

    -- ── Заголовки стовпців ──
    local hdr = CreateFrame("Frame", nil, parent)
    hdr:SetPoint("TOPLEFT", 8, -66)
    hdr:SetPoint("TOPRIGHT", -8, -66)
    hdr:SetHeight(20)

    local function ColHdr(text, x, w, align)
        local fs = MakeLabel(hdr, 9, C.label[1], C.label[2], C.label[3], align or "LEFT")
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

    local sep = MakeAccentLine(parent, C.sep[1], C.sep[2], C.sep[3], C.sep[4])
    sep:SetPoint("TOPLEFT",  8, -86)
    sep:SetPoint("TOPRIGHT", -8, -86)

    -- ── Фрейм прокрутки для рейду ──
    local sf = CreateFrame("ScrollFrame", "SRDashScroll", parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -89)
    sf:SetPoint("BOTTOMRIGHT", -28, 8)

    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(sf:GetWidth())
    child:SetHeight(1)
    sf:SetScrollChild(child)
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
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT",  0, -(index - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_H)

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
    row.nameFS = MakeLabel(row, 11, 1, 1, 1, "LEFT")
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
    row.classFS = MakeLabel(row, 10, 0.7, 0.7, 0.7, "LEFT")
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

    row.roleBtn.fs = MakeLabel(row.roleBtn, 10, 1, 1, 1, "CENTER")
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
    row.usedFS = MakeLabel(row, 11, 0.7, 0.9, 1.0, "CENTER")
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

    row.overrideBtn.fs = MakeLabel(row.overrideBtn, 10, 1, 0.7, 0.2, "CENTER")
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
    self.dashChild:SetHeight(math.max(1, #members * ROW_H))

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
    popup:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    popup:SetBackdropColor(0.08, 0.08, 0.12, 0.98)
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
    local popupTopLine = MakeAccentLine(popup, C.gold[1], C.gold[2], C.gold[3], 0.75)
    popupTopLine:SetPoint("TOPLEFT",  popup, "TOPLEFT",  14, -12)
    popupTopLine:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -14, -12)

    local titleFS = MakeLabel(popup, 12, C.gold[1], C.gold[2], C.gold[3])
    titleFS:SetPoint("TOP", 0, -18)
    popup.titleFS = titleFS

    popup.statusFS = MakeLabel(popup, 10, 0.75, 0.75, 0.75, "CENTER")
    popup.statusFS:SetPoint("TOP", titleFS, "BOTTOM", 0, -4)
    popup.statusFS:SetWidth(240)

    local desc = MakeLabel(popup, 10, 0.55, 0.55, 0.55, "CENTER")
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
        local btn = MakeButton(popup, "x" .. v, btnW, 24)
        btn:SetPoint("TOPLEFT", startX + (i - 1) * (btnW + btnGap), btnY)
        btn:SetScript("OnClick", function()
            SR:SetPlayerOverride(popup.targetPlayer, v)
            popup:Hide()
        end)
        popup.valBtns[i] = btn
    end

    local resetBtn = MakeButton(popup, "За замовч.", 118, 24)
    resetBtn:SetPoint("TOPLEFT", startX, btnY - 34)
    resetBtn:SetScript("OnClick", function()
        SR:SetPlayerOverride(popup.targetPlayer, nil)
        popup:Hide()
    end)
    popup.resetBtn = resetBtn

    local cancelBtn = MakeButton(popup, "Скасувати", 118, 24)
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

--------------------------------------------------------------
-- ПОПАП РЕДАГУВАННЯ ГРАВЦЯ (Додавання софту)
--------------------------------------------------------------
function SR:BuildEditPlayerPopup()
    if self.editPlayerPopup then return end

    local popup = CreateFrame("Frame", "SREditPlayerPopup", UIParent)
    popup:SetSize(400, 140)
    popup:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    popup:SetBackdropColor(0.08, 0.08, 0.12, 0.98)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(100)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop",  popup.StopMovingOrSizing)
    popup:Hide()

    -- Видалено глобальний хук, оскільки ElvUI та інші аддони переписують OnEnter для DropDown кнопок
    local popupTopLine = MakeAccentLine(popup, C.gold[1], C.gold[2], C.gold[3], 0.75)
    popupTopLine:SetPoint("TOPLEFT",  popup, "TOPLEFT",  14, -12)
    popupTopLine:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -14, -12)

    local titleFS = MakeLabel(popup, 12, C.gold[1], C.gold[2], C.gold[3])
    titleFS:SetPoint("TOP", 0, -18)
    popup.titleFS = titleFS

    local ddDesc = MakeLabel(popup, 10, 0.75, 0.75, 0.75, "CENTER")
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

    local addBtn = MakeButton(popup, "Додати", 100, 24)
    addBtn:SetPoint("BOTTOMLEFT", 15, 18)
    addBtn:SetScript("OnClick", function()
        local itemID = popup.selectedItemID
        if not itemID then
            SR:Print("Оберіть предмет зі списку.")
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

    local closeBtn = MakeButton(popup, "Закрити", 100, 24)
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
    local tabPlayers = MakeFlatTab(parent, "По гравцях", 24)
    tabPlayers:SetPoint("TOPLEFT", 8, -10)
    tabPlayers:SetPoint("RIGHT", parent, "CENTER", -2, 0)
    tabPlayers:SetScript("OnClick", function()
        SR.ledgerActiveSubTab = "players"
        SR:UpdateLedger()
    end)
    self.ledgerTabs.players = tabPlayers

    local tabBosses = MakeFlatTab(parent, "По босах", 24)
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
        local fs = MakeLabel(hdr, 9, C.label[1], C.label[2], C.label[3], align or "LEFT")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetText(text)
        if key then self.ledgerHeaders[key] = fs end
    end
    ColHdr("Гравець",         6,   120, "LEFT", "col1")
    ColHdr("Роль",           130,  40, "LEFT", "col2")
    ColHdr("Предмети",       175, 168, "LEFT", "col3")
    ColHdr("Викор.",         340,  50, "CENTER", "col4")
    ColHdr("Дії",           405,  50, "CENTER", "col5")

    local sep = MakeAccentLine(parent, C.sep[1], C.sep[2], C.sep[3], C.sep[4])
    sep:SetPoint("TOPLEFT",  8, -62)
    sep:SetPoint("TOPRIGHT", -8, -62)

    self.ledgerEmptyFS = MakeLabel(parent, 13, 0.35, 0.35, 0.40, "CENTER")
    self.ledgerEmptyFS:SetPoint("CENTER", 0, 20)
    self.ledgerEmptyFS:SetWidth(420)
    self.ledgerEmptyFS:SetText("Ще немає зареєстрованих софт-ролів")
    self.ledgerEmptyFS:Hide()
    self.ledgerEmptySub = MakeLabel(parent, 10, 0.28, 0.28, 0.34, "CENTER")
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
    child:SetWidth(sf:GetWidth())
    child:SetHeight(1)
    sf:SetScrollChild(child)
    self.ledgerScroll = sf
    self.ledgerChild = child
    self.ledgerRows  = {}

    -- ── Кнопки внизу ──
    local clearAll = MakeButton(parent, "Очистити всі софти", 138, 24)
    clearAll:SetPoint("BOTTOMLEFT", 8, 10)
    clearAll:SetScript("OnClick", function()
        if SR:IsSessionReadOnly() then return end
        StaticPopup_Show("SOFTROLL_CONFIRM_CLEAR")
    end)
    self.ledgerClearAll = clearAll

    local announceBtn = MakeButton(parent, "Анонс у рейд", 140, 24)
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
                SR:Print("Тільки лідер рейду або помічник аддону може анонсувати інструкції.")
                return
            end
            local chatType = "SAY"
            if GetNumRaidMembers() > 0 then
                chatType = "RAID_WARNING"
            elseif GetNumPartyMembers() > 0 then
                chatType = "PARTY"
            end
            SendChatMessage("Щоб зарезервувати предмет, напишіть в ПМ або рейд чат: sr [лінк предмета]", chatType)
            if SR.db.srMode ~= "rs_x1" then
                SendChatMessage("Для подвійного софту: sr [лінк предмета] x2", chatType)
            end
            SendChatMessage("Ваші софти: sr list - Видалити один: sr clear [лінк] - Очистити всі: sr clear", chatType)
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
        text         = "Очистити ВСІ софти? Це неможливо відмінити.",
        button1      = "Так, очистити",
        button2      = "Скасувати",
        OnAccept     = function()
            local chatType = (GetNumRaidMembers() > 0) and "RAID" or "PARTY"
            if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then chatType = "SAY" end
            
            if SR:IsSessionHost() or (SR:IsSessionLeader() and not SR.sessionActive) then
                SR:ResetAllSR()
                SendChatMessage("Очищено ВСІ софт-роли рейду.", chatType)
            else
                SR:SendAddonMsg("W", "WHISPER", SR.sessionHost)
                SR:Print("Запит на очищення всіх софтів надіслано хосту...")
                SendChatMessage("Очищено ВСІ софт-роли рейду.", chatType)
            end
        end,
        timeout      = 0,
        whileDead    = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["SOFTROLL_CONFIRM_CLEAR_PLAYER"] = {
        text         = "Очистити всі софти гравця %s?",
        button1      = "Очистити",
        button2      = "Скасувати",
        OnAccept     = function(self, data)
            local target = data.target
            
            if SR:IsSessionHost() or (SR:IsSessionLeader() and not SR.sessionActive) then
                SR:ClearPlayerSR(target)
                SR:Print("Очищено софт-роли для " .. target)
                local chatType = (GetNumRaidMembers() > 0) and "RAID" or "PARTY"
                if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then chatType = "SAY" end
                SendChatMessage("Очищено софт-роли гравця " .. target, chatType)
            else
                SR:SendAddonMsg("C|" .. target, "WHISPER", SR.sessionHost)
                SR:Print("Запит на очищення надіслано хосту...")
            end
        end,
        timeout      = 0,
        whileDead    = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["SOFTROLL_CONFIRM_REMOVE_ITEM"] = {
        text         = "Видалити %s з софтів гравця %s?",
        button1      = "Видалити",
        button2      = "Скасувати",
        OnAccept     = function(self, data)
            local chatType = (GetNumRaidMembers() > 0) and "RAID" or "PARTY"
            if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then chatType = "SAY" end
            
            if SR:IsSessionHost() or (SR:IsSessionLeader() and not SR.sessionActive) then
                SR:RemoveSR(data.target, data.itemID)
                SR:Print("Видалено предмет зі списку " .. data.target)
                SendChatMessage("Видалено " .. data.link .. " з софтів гравця " .. data.target, chatType)
            else
                SR:SendAddonMsg("R|" .. data.target .. "|" .. data.itemID, "WHISPER", SR.sessionHost)
                SR:Print("Запит на видалення надіслано хосту...")
                SendChatMessage("Видалено " .. data.link .. " з софтів гравця " .. data.target, chatType)
            end
        end,
        timeout      = 0,
        whileDead    = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["SOFTROLL_CONFIRM_ADD_ITEM"] = {
        text         = "Додати %s гравцю %s?",
        button1      = "Додати",
        button2      = "Скасувати",
        OnAccept     = function(self, data)
            local ok = SR:RequestSRFromUI(data.itemID, 1, data.target)
            if ok == true then
                local chatType = (GetNumRaidMembers() > 0) and "RAID" or "PARTY"
                if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then chatType = "SAY" end
                SendChatMessage("Додано " .. data.link .. " до софтів гравця " .. data.target, chatType)
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
    row:SetHeight(LEDGER_ROW_H)
    row:SetPoint("TOPLEFT",  0, -(index - 1) * LEDGER_ROW_H)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * LEDGER_ROW_H)

    -- Чергування фону
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bg:SetVertexColor(0.12, 0.12, 0.18, (index % 2 == 0) and 0.35 or 0)
    row.bg = bg

    -- Гравець (наведення = підсумок у підказці)
    row.nameFS = MakeLabel(row, 11, 1, 1, 1, "LEFT")
    row.nameFS:SetPoint("LEFT", 6, 0)
    row.nameFS:SetWidth(120)

    row.nameBtn = CreateFrame("Button", nil, row)
    row.nameBtn:SetPoint("TOPLEFT", 6, -2)
    row.nameBtn:SetSize(120, LEDGER_ROW_H - 4)
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
    row.roleFS = MakeLabel(row, 10, 1, 1, 1, "LEFT")
    row.roleFS:SetPoint("LEFT", 130, 0)
    row.roleFS:SetWidth(40)

    -- Кнопка анонсу
    local annBtn = CreateFrame("Button", nil, row)
    annBtn:SetSize(22, 22)
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
                            local msg = linkOut .. " засофтили: " .. table.concat(parts, ", ")
                            local chatType = "SAY"
                            if GetNumRaidMembers() > 0 then
                                chatType = "RAID"
                            elseif GetNumPartyMembers() > 0 then
                                chatType = "PARTY"
                            end
                            SendChatMessage(msg, chatType)
                        end
                        UIDropDownMenu_AddButton(info2, level)
                        
                        local listFrame = _G["DropDownList" .. level]
                        local button = _G["DropDownList" .. level .. "Button" .. listFrame.numButtons]
                        if button then
                            local itemLink = itemEntry.itemLink
                            local origOnEnter = button:GetScript("OnEnter")
                            local origOnLeave = button:GetScript("OnLeave")
                            button:SetScript("OnEnter", function(self)
                                if origOnEnter then origOnEnter(self) end
                                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                                if itemLink and itemLink:match("item:") then
                                    GameTooltip:SetHyperlink(itemLink)
                                else
                                    GameTooltip:SetText(fallbackName, 1, 1, 1)
                                end
                                GameTooltip:Show()
                            end)
                            button:SetScript("OnLeave", function(self)
                                if origOnLeave then origOnLeave(self) end
                                GameTooltip:Hide()
                            end)
                        end
                    end
                end
            end)
            ToggleDropDownMenu(1, nil, SR.bossAnnounceMenu, self, 0, 0)
        else
            SR:AnnouncePlayerSR(row.playerName)
        end
    end)
    row.annBtn = annBtn

    -- Ряд іконок предметів
    row.iconStrip = CreateFrame("Frame", nil, row)
    row.iconStrip:SetPoint("LEFT", 175, 0)
    row.iconStrip:SetSize(168, LEDGER_ROW_H)
    row.itemIcons = {}

    for j = 1, LEDGER_MAX_ICONS do
        local btn = CreateFrame("Button", nil, row.iconStrip)
        btn:SetSize(26, 26)
        btn:SetPoint("LEFT", (j - 1) * 28 + 2, 0)

        local iconBg = btn:CreateTexture(nil, "BACKGROUND")
        iconBg:SetAllPoints()
        iconBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        iconBg:SetVertexColor(0.08, 0.08, 0.12, 0.8)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        btn.icon = icon

        -- Кнопка видалення
        local del = CreateFrame("Button", nil, btn)
        del:SetSize(12, 12)
        del:SetPoint("TOPRIGHT", 4, 4)
        del:SetNormalTexture("Interface\\BUTTONS\\UI-GroupLoot-Pass-Up")
        del:SetHighlightTexture("Interface\\BUTTONS\\UI-GroupLoot-Pass-Highlight")
        del:SetPushedTexture("Interface\\BUTTONS\\UI-GroupLoot-Pass-Down")
        del:SetScript("OnClick", function()
            if not btn.itemID then return end
            local dialog = StaticPopup_Show("SOFTROLL_CONFIRM_REMOVE_ITEM", btn.itemLink or ("Предмет #" .. btn.itemID), row.playerName)
            if dialog then dialog.data = { target = row.playerName, itemID = btn.itemID, link = btn.itemLink or ("Предмет #" .. btn.itemID) } end
        end)
        btn.delBtn = del

        btn.countFS = btn:CreateFontString(nil, "OVERLAY")
        btn.countFS:SetFont("Fonts\\ARIALN.TTF", 11, "OUTLINE")
        btn.countFS:SetPoint("BOTTOMRIGHT", 2, -2)
        btn.countFS:SetTextColor(1, 0.85, 0.2)

        btn:Hide()
        AttachItemIconTooltip(btn)
        row.itemIcons[j] = btn
    end

    row.moreFS = MakeLabel(row.iconStrip, 10, 0.55, 0.55, 0.55, "LEFT")
    row.moreFS:SetPoint("LEFT", LEDGER_MAX_ICONS * 28 + 4, 0)
    row.moreFS:SetWidth(60)
    row.moreFS:Hide()

    -- Текстовий резерв, якщо іконки ще не закешовані
    row.summaryFS = MakeLabel(row, 10, 0.55, 0.55, 0.55, "LEFT")
    row.summaryFS:SetPoint("LEFT", 175, -10)
    row.summaryFS:SetWidth(160)

    row.usedFS = MakeLabel(row, 10, 0.75, 0.75, 0.75, "CENTER")
    row.usedFS:SetPoint("LEFT", 320, 0)
    row.usedFS:SetWidth(50)

    row.editBtn = CreateFrame("Button", nil, row)
    row.editBtn:SetSize(20, 20)
    row.editBtn:SetPoint("LEFT", 405, 0)
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
    row.clearBtn:SetSize(22, 22)
    row.clearBtn:SetPoint("LEFT", 430, 0)
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
        self.ledgerHeaders.col4:SetPoint("LEFT", 320, 0)
        self.ledgerHeaders.col5:Show()
        self.ledgerHeaders.col5:SetWidth(72)
        self.ledgerHeaders.col5:SetPoint("LEFT", 380, 0)
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
        local rowH = math.max(LEDGER_ROW_H, lines * 28 + 4)
        
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

        -- Count how many action buttons will be visible
        local showAnn = canEditSession
        local showEdit = canEditSession
        local showClear = canEdit
        local btnCount = (showAnn and 1 or 0) + (showEdit and 1 or 0) + (showClear and 1 or 0)
        
        -- Center of "Дії" column is around 405 (header at 380, width ~50)
        local actionSpacing = 25
        local totalWidth = btnCount > 0 and ((btnCount - 1) * actionSpacing) or 0
        local actionX = 405 - totalWidth / 2 - 10  -- start so group is centered

        if showAnn then
            row.annBtn:Show()
            row.annBtn:ClearAllPoints()
            row.annBtn:SetPoint("LEFT", actionX, 0)
            actionX = actionX + actionSpacing
        else
            row.annBtn:Hide()
        end

        if showEdit then
            row.editBtn:Show()
            row.editBtn:ClearAllPoints()
            row.editBtn:SetPoint("LEFT", actionX, 0)
            actionX = actionX + actionSpacing
        else
            row.editBtn:Hide()
        end

        if showClear then
            row.clearBtn:Show()
            row.clearBtn:ClearAllPoints()
            row.clearBtn:SetPoint("LEFT", actionX, 0)
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

    self.ledgerClearAll:Hide()
    self.ledgerAnnounceBtn:Hide()

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
        local rowH = math.max(LEDGER_ROW_H, lines * 28 + 4)
        
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

    if self.ledgerTabs then
        self.ledgerTabs.players.active = (self.ledgerActiveSubTab == "players")
        self.ledgerTabs.bosses.active = (self.ledgerActiveSubTab == "bosses")
        
        if self.ledgerTabs.players.active then
            self.ledgerTabs.players.bg:SetVertexColor(0.15, 0.18, 0.28, 0.95)
            self.ledgerTabs.players.accent:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 1)
            self.ledgerTabs.players.label:SetTextColor(1, 0.82, 0)
        else
            self.ledgerTabs.players.bg:SetVertexColor(0.10, 0.10, 0.16, 0.9)
            self.ledgerTabs.players.accent:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 0)
            self.ledgerTabs.players.label:SetTextColor(0.5, 0.5, 0.5)
        end
        
        if self.ledgerTabs.bosses.active then
            self.ledgerTabs.bosses.bg:SetVertexColor(0.15, 0.18, 0.28, 0.95)
            self.ledgerTabs.bosses.accent:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 1)
            self.ledgerTabs.bosses.label:SetTextColor(1, 0.82, 0)
        else
            self.ledgerTabs.bosses.bg:SetVertexColor(0.10, 0.10, 0.16, 0.9)
            self.ledgerTabs.bosses.accent:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 0)
            self.ledgerTabs.bosses.label:SetTextColor(0.5, 0.5, 0.5)
        end
    end

    if self.ledgerActiveSubTab == "bosses" then
        self:UpdateLedgerBosses()
    else
        self:UpdateLedgerPlayers()
    end
end


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
        accent:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 0)
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
            tabBosses.accent:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 1)
            tabBosses.label:SetTextColor(1, 0.82, 0)
            
            tabWishlist.active = false
            tabWishlist.bg:SetVertexColor(0.10, 0.10, 0.16, 0.9)
            tabWishlist.accent:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 0)
            tabWishlist.label:SetTextColor(0.5, 0.5, 0.5)
        else
            tabBosses.active = false
            tabBosses.bg:SetVertexColor(0.10, 0.10, 0.16, 0.9)
            tabBosses.accent:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 0)
            tabBosses.label:SetTextColor(0.5, 0.5, 0.5)
            
            tabWishlist.active = true
            tabWishlist.bg:SetVertexColor(0.15, 0.18, 0.28, 0.95)
            tabWishlist.accent:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 1)
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
    local bossLabel = MakeLabel(parent, 11, 0.85, 0.85, 0.55)
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
    
    local heroicLabel = MakeLabel(parent, 11, 0.85, 0.85, 0.55)
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
    itemPanel:SetPoint("BOTTOMRIGHT", -6, 38)
    ApplyPanelStyle(itemPanel, 0.06, 0.06, 0.10, 0.95)

    local itemScroll = CreateFrame("ScrollFrame", "SRItemScroll", itemPanel, "UIPanelScrollFrameTemplate")
    itemScroll:SetPoint("TOPLEFT", 4, -4)
    itemScroll:SetPoint("BOTTOMRIGHT", -24, 4)

    local itemChild = CreateFrame("Frame", nil, itemScroll)
    itemChild:SetWidth(itemScroll:GetWidth())
    itemChild:SetHeight(1)
    itemScroll:SetScrollChild(itemChild)
    self.lbItemChild = itemChild
    self.lbItemRows  = {}

    local reserveBtn = MakeButton(parent, "Засофтити", 140, 28)
    reserveBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    reserveBtn:SetScript("OnClick", function()
        if not SR.lbSelectedItemID then
            SR:Print("Спочатку виберіть предмет зі списку.")
            return
        end
        SR:RequestSRFromUI(SR.lbSelectedItemID, 1, SR:GetLocalPlayerName())
    end)
    self.lbReserveBtn = reserveBtn

    local wishlistBtn = MakeButton(parent, "В обране", 160, 28)
    wishlistBtn:SetPoint("RIGHT", reserveBtn, "LEFT", -10, 0)
    wishlistBtn:SetScript("OnClick", function()
        if not SR.lbSelectedItemID then return end
        SR:ToggleWishlistItem(SR.lbSelectedItemID)
        SR:UpdateLootBrowserItems()
        if SR.lbSelectedBoss == 1 then
            SR:UpdateLootBrowser()
        end
    end)
    self.lbWishlistBtn = wishlistBtn

    local lbHint = MakeLabel(parent, 10, C.dim[1], C.dim[2], C.dim[3], "LEFT")
    lbHint:SetPoint("BOTTOMLEFT", 8, 14)
    lbHint:SetWidth(150)
    lbHint:SetText("Shift-клік - лінк в чат")

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
    row:SetHeight(ITEM_H)
    row:SetPoint("TOPLEFT",  0, -(index - 1) * ITEM_H)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * ITEM_H)

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

    -- Назва предмета
    row.nameFS = MakeLabel(row, 11, 1, 0.82, 0, "LEFT")
    row.nameFS:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.nameFS:SetWidth(380)
    row.nameFS:SetWordWrap(false)

    -- Іконка вішліста (рейд-маркер зірка)
    local wlIcon = row:CreateTexture(nil, "OVERLAY")
    wlIcon:SetSize(16, 16)
    wlIcon:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -6, 6)
    wlIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    wlIcon:Hide()
    row.wlIcon = wlIcon

    -- SR бейдж фон видалено для кращого вигляду

    -- Текст SR
    row.srFS = MakeLabel(row, 10, 0.45, 0.82, 0.35, "CENTER")
    row.srFS:SetPoint("RIGHT", -4, 0)
    row.srFS:SetWidth(66)

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
                local editBox = ChatFrame1EditBox or ChatFrameEditBox
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

    for i, itemID in ipairs(items) do
        local row = GetLBItemRow(self.lbItemChild, i)
        row:Show()
        row.itemID = itemID

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

        -- Відображення іконки вішліста
        if SR:IsInWishlist(itemID) then
            row.wlIcon:Show()
        else
            row.wlIcon:Hide()
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

    if self.lbWishlistBtn then
        if self.lbSelectedItemID and self:IsInWishlist(self.lbSelectedItemID) then
            self.lbWishlistBtn:SetText("Видалити з обраного")
            self.lbWishlistBtn:SetWidth(160)
        else
            self.lbWishlistBtn:SetText("В обране")
            self.lbWishlistBtn:SetWidth(110)
        end
    end

    self.lbItemChild:SetHeight(math.max(1, #items * ITEM_H))
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

    if self.lbWishlistBtn then
        if self.lbSelectedItemID and self:IsInWishlist(self.lbSelectedItemID) then
            self.lbWishlistBtn:SetText("Видалити з обраного")
            self.lbWishlistBtn:SetWidth(160)
        else
            self.lbWishlistBtn:SetText("В обране")
            self.lbWishlistBtn:SetWidth(110)
        end
    end
end


-- ╔══════════════════════════════════════════════════════════╗
-- ║               ВКЛАДКА 4 — РОЗДАЧА ЗДОБИЧІ               ║
-- ╚══════════════════════════════════════════════════════════╝

function SR:BuildLootSession(parent)

    -- ── Інструкція ──
    local instr = MakeLabel(parent, 10, 0.6, 0.6, 0.6, "LEFT")
    instr:SetPoint("TOPLEFT", 10, -8)
    instr:SetPoint("TOPRIGHT", -10, -8)
    instr:SetText("Shift-клік по предмету (коли поле активне) або перетягніть його сюди.")

    -- ── Поле введення ──
    local itemFrame = CreateFrame("Frame", nil, parent)
    itemFrame:SetPoint("TOPLEFT", 8, -28)
    itemFrame:SetPoint("TOPRIGHT", -8, -28)
    itemFrame:SetHeight(38)
    ApplyPanelStyle(itemFrame, 0.10, 0.10, 0.14, 0.9)

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
    local clearItemBtn = MakeButton(itemFrame, "Очистити", 80, 24)
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
        return origInsertLink(text, ...)
    end

    -- ── Відображення поточного предмета ──
    self.lootItemLabel = MakeLabel(parent, 13, 1, 0.82, 0, "LEFT")
    self.lootItemLabel:SetPoint("TOPLEFT", 10, -74)
    self.lootItemLabel:SetText("")

    -- ── Заголовки результатів ──
    local resHdr = CreateFrame("Frame", nil, parent)
    resHdr:SetPoint("TOPLEFT", 8, -96)
    resHdr:SetPoint("TOPRIGHT", -8, -96)
    resHdr:SetHeight(20)

    local function ResCol(text, x, w)
        local fs = MakeLabel(resHdr, 10, 0.65, 0.65, 0.45, "LEFT")
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

    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(sf:GetWidth())
    child:SetHeight(1)
    sf:SetScrollChild(child)
    self.lootChild = child
    self.lootRows  = {}

    -- ── Повідомлення про відсутність результатів ──
    self.lootNoResult = MakeLabel(parent, 12, 0.35, 0.35, 0.40, "CENTER")
    self.lootNoResult:SetPoint("CENTER", sf, "CENTER", 0, 0)
    self.lootNoResult:SetText("Ніхто не засофтив цей предмет")
    self.lootNoResult:Hide()

    local rollToggleBtn = MakeButton(parent, "Почати рол (/rw)", 180, 28)
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
    self.lootSummary = MakeLabel(parent, 11, 0.7, 0.7, 0.7, "LEFT")
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
    row:SetHeight(ROW_H + 2)
    row:SetPoint("TOPLEFT",  0, -(index - 1) * (ROW_H + 2))
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * (ROW_H + 2))

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bg:SetVertexColor(0.12, 0.12, 0.18, (index % 2 == 0) and 0.35 or 0)
    row.bg = bg

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    hl:SetVertexColor(0.3, 0.4, 0.6, 0.2)

    row.nameFS = MakeLabel(row, 12, 1, 1, 1, "LEFT")
    row.nameFS:SetPoint("LEFT", 6, 0)
    row.nameFS:SetWidth(140)

    row.roleFS = MakeLabel(row, 11, 1, 1, 1, "LEFT")
    row.roleFS:SetPoint("LEFT", 150, 0)
    row.roleFS:SetWidth(80)

    row.countFS = MakeLabel(row, 13, 1, 0.85, 0.15, "LEFT")
    row.countFS:SetPoint("LEFT", 235, 0)
    row.countFS:SetWidth(100)

    row.rollFS = MakeLabel(row, 14, 0.4, 1, 0.4, "LEFT")
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
        self:Print("Не вдалося визначити предмет. Переконайтеся, що ви зробили Shift-клік на правильний лінк.")
        return
    end

    local itemID = self:GetItemIDFromLink(link)
    if not itemID then return end

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

    if self.lootRollToggleBtn then
        if self.activeRollItem then
            self.lootRollToggleBtn:SetText("Закінчити рол")
        else
            self.lootRollToggleBtn:SetText("Почати рол (/rw)")
        end
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

    for pName, _ in pairs(self.activeRolls) do
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

        if SR.activeRollItem == SR.currentLootItemID and SR.activeRolls[p.name] then
            local rollsStr = table.concat(SR.activeRolls[p.name], ", ")
            row.rollFS:SetText(rollsStr)
        else
            row.rollFS:SetText("")
        end

        -- Перший претендент - золотий фон
        if i == 1 then
            row.bg:SetVertexColor(0.30, 0.22, 0.04, 0.40)
        else
            row.bg:SetVertexColor(0.11, 0.11, 0.17, (i % 2 == 0) and 0.38 or 0)
        end
    end

    for i = #players + 1, #self.lootRows do
        self.lootRows[i]:Hide()
    end

    self.lootChild:SetHeight(math.max(1, #players * (ROW_H + 2)))
end

--------------------------------------------------------------
-- АНОНС РОЛУ
--------------------------------------------------------------
function SR:AnnounceLootRoll()
    if not self.currentLootItemID or not self.currentLootItemLink then
        self:Print("Предмет для роздачі не вибрано.")
        return
    end

    local players = self:GetPlayersWithSR(self.currentLootItemID)
    local chatType = (GetNumRaidMembers() > 0) and "RAID_WARNING" or "SAY"

    if chatType == "SAY" then
        self:Print("Ви не в рейді — використовуємо /say.")
    end

    self.activeRollItem = self.currentLootItemID
    self.activeRolls = {}

    -- Резервна логіка "Немає SR"
    if #players == 0 then
        SendChatMessage(self.currentLootItemLink .. " не має софт-ролів! Ролимо на мейн спек (/roll)", chatType)
    else
        SendChatMessage("Здобич: " .. self.currentLootItemLink, chatType)

        -- Формування списку претендентів
        local names = {}
        for _, p in ipairs(players) do
            local cx = (p.count > 1) and (" x" .. p.count) or ""
            names[#names + 1] = p.name .. cx
        end

        SendChatMessage("Претенденти: " .. table.concat(names, ", ") .. " — роліть (/roll)!", chatType)
    end

    if self.UpdateLootSession then self:UpdateLootSession() end
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

    -- Іконка
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -5)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_03")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

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
