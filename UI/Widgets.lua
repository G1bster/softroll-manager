--------------------------------------------------------------
-- SoftRollManager  —  UI/Widgets.lua
-- Спільна палітра кольорів, константи макета та фабрика
-- перевикористовуваних UI-віджетів для решти файлів UI/*.lua.
-- Сумісно з WoW 3.3.5a (WotLK)
--------------------------------------------------------------

local SR = SoftRoll

-- ── Централізована палітра кольорів ──
SR.UI = SR.UI or {}

SR.UI.C = {
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
SR.UI.FRAME_W, SR.UI.FRAME_H = 520, 480
SR.UI.STATUS_H = 24   -- висота нижньої статус-смуги
SR.UI.TAB_H   = 30
SR.UI.HDR_H   = 32
SR.UI.PAD     = 12
SR.UI.ROW_H   = 22
SR.UI.LEDGER_ROW_H = 32   -- вищі рядки для іконок предметів
SR.UI.ITEM_H  = 36   -- висота рядка предмета в оглядачі здобичі
SR.UI.LEDGER_MAX_ICONS = 6

local C = SR.UI.C

--------------------------------------------------------------
-- ДОПОМІЖНА ФУНКЦІЯ: Стилізований фон підпанелі
--------------------------------------------------------------
local PANEL_BD = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

function SR:ApplyPanelStyle(frame, r, g, b, a)
    frame:SetBackdrop(PANEL_BD)
    frame:SetBackdropColor(r or 0.08, g or 0.08, b or 0.12, a or 0.92)
    frame:SetBackdropBorderColor(0.22, 0.32, 0.55, 0.65)
end

--------------------------------------------------------------
-- ДОПОМІЖНА ФУНКЦІЯ: Багаторазова стилізована кнопка
--------------------------------------------------------------
function SR:MakeButton(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetText(text)
    b:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 11)
    return b
end

-- Декоративна горизонтальна лінія
function SR:MakeAccentLine(parent, r, g, b, a)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(2)
    t:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    t:SetVertexColor(r or C.blue[1], g or C.blue[2], b or C.blue[3], a or 0.85)
    return t
end

--------------------------------------------------------------
-- ДОПОМІЖНА ФУНКЦІЯ: Скорочення для FontString
--------------------------------------------------------------
function SR:MakeLabel(parent, size, r, g, b, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetFont("Fonts\\FRIZQT__.TTF", size or 11)
    fs:SetTextColor(r or 1, g or 1, b or 1, 1)
    if justify then fs:SetJustifyH(justify) end
    return fs
end

function SR:MakeFlatTab(parent, text, h)
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
-- ДОПОМІЖНА ФУНКЦІЯ: Фон діалогового вікна (попапи)
--------------------------------------------------------------
local DIALOG_BD = {
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

function SR:ApplyDialogBackdrop(frame, r, g, b, a)
    frame:SetBackdrop(DIALOG_BD)
    frame:SetBackdropColor(r or 0.08, g or 0.08, b or 0.12, a or 0.98)
end

--------------------------------------------------------------
-- ДОПОМІЖНА ФУНКЦІЯ: Кнопка-іконка предмета з накладеною кнопкою видалення
-- (спільний вигляд для рядків Панелі керування та Реєстру)
--------------------------------------------------------------
function SR:MakeItemIconButton(parent, size)
    size = size or 26
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)

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
    btn.delBtn = del

    return btn
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
