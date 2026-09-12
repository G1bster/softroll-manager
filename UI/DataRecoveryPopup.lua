--------------------------------------------------------------
-- SoftRollManager  —  UI/DataRecoveryPopup.lua
-- Попапи для сценарію "у хоста загубились софт-роли" (напр. після краху
-- гри): пропозиція відновити дані, і вибір джерела серед тих учасників
-- рейду, у кого аддон має закешовану копію (протокол RP/RA/RQ/RY/RZ
-- в Comms.lua).
-- Сумісно з WoW 3.3.5a (WotLK)
--------------------------------------------------------------

local SR = SoftRoll

--------------------------------------------------------------
-- ПОПАП 1: "Софт-роли відсутні"
--------------------------------------------------------------
function SR:BuildDataLossPopup()
    if self.dataLossPopup then return end

    local popup = CreateFrame("Frame", "SRDataLossPopup", UIParent)
    popup:SetSize(320, 150)
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

    tinsert(UISpecialFrames, "SRDataLossPopup")

    local topLine = SR:MakeAccentLine(popup, SR.UI.C.red[1], SR.UI.C.red[2], SR.UI.C.red[3], 0.85)
    topLine:SetPoint("TOPLEFT",  popup, "TOPLEFT",  14, -12)
    topLine:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -14, -12)

    local titleFS = SR:MakeLabel(popup, 12, SR.UI.C.red[1], SR.UI.C.red[2], SR.UI.C.red[3])
    titleFS:SetPoint("TOP", 0, -18)
    titleFS:SetText("Софт-роли відсутні")

    local desc = SR:MakeLabel(popup, 10, 0.75, 0.75, 0.75, "CENTER")
    desc:SetPoint("TOP", titleFS, "BOTTOM", 0, -8)
    desc:SetWidth(280)
    desc:SetText("Резерви порожні, хоча в рейді вже є учасники. Це новий рейд, чи дані могли загубитись (наприклад, через краш)?")

    local newRaidBtn = SR:MakeButton(popup, "Це новий рейд", 140, 24)
    newRaidBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 14, 16)
    newRaidBtn:SetScript("OnClick", function()
        SR._dataLossPromptDismissed = true
        popup:Hide()
    end)

    local recoverBtn = SR:MakeButton(popup, "Спробувати відновити", 140, 24)
    recoverBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -14, 16)
    recoverBtn:SetScript("OnClick", function()
        popup:Hide()
        SR:StartRecoveryScan()
        SR:ShowRecoveryPopup()
    end)

    self.dataLossPopup = popup
end

function SR:ShowDataRecoveryPrompt()
    if not self.dataLossPopup then self:BuildDataLossPopup() end
    self.dataLossPopup:Show()
end

--------------------------------------------------------------
-- ПОПАП 2: вибір джерела відновлення серед тих, хто відповів на RP
--------------------------------------------------------------
function SR:BuildRecoveryPopup()
    if self.recoveryPopup then return end

    local popup = CreateFrame("Frame", "SRRecoveryPopup", UIParent)
    popup:SetSize(320, 190)
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

    tinsert(UISpecialFrames, "SRRecoveryPopup")

    local topLine = SR:MakeAccentLine(popup, SR.UI.C.gold[1], SR.UI.C.gold[2], SR.UI.C.gold[3], 0.75)
    topLine:SetPoint("TOPLEFT",  popup, "TOPLEFT",  14, -12)
    topLine:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -14, -12)

    local titleFS = SR:MakeLabel(popup, 12, SR.UI.C.gold[1], SR.UI.C.gold[2], SR.UI.C.gold[3])
    titleFS:SetPoint("TOP", 0, -18)
    titleFS:SetText("Відновлення з рейду")

    local statusFS = SR:MakeLabel(popup, 10, 0.75, 0.75, 0.75, "CENTER")
    statusFS:SetPoint("TOP", titleFS, "BOTTOM", 0, -8)
    statusFS:SetWidth(280)
    statusFS:SetText("Опитую рейд, хто має закешовані софт-роли...")
    popup.statusFS = statusFS

    local ddLabel = SR:MakeLabel(popup, 10, 0.75, 0.75, 0.75, "LEFT")
    ddLabel:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -76)
    ddLabel:SetText("Джерело:")

    local sourceDD = CreateFrame("Frame", "SRRecoverySourceDD", popup, "UIDropDownMenuTemplate")
    sourceDD:SetPoint("TOPLEFT", ddLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(sourceDD, 220)
    UIDropDownMenu_SetText(sourceDD, "Ще ніхто не відповів")
    popup.sourceDD = sourceDD

    UIDropDownMenu_Initialize(sourceDD, function(menu, level)
        level = level or 1
        if level ~= 1 then return end

        -- Найповніша копія — зверху.
        local rows = {}
        for _, resp in pairs(SR._recoveryResponses or {}) do
            rows[#rows + 1] = resp
        end
        table.sort(rows, function(a, b) return a.count > b.count end)

        if #rows == 0 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "Ще ніхто не відповів"
            info.notCheckable = true
            info.disabled = true
            UIDropDownMenu_AddButton(info, level)
            return
        end

        for _, resp in ipairs(rows) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = resp.name .. " (" .. resp.count .. " гравців)"
            info.value = resp.name
            info.checked = (popup.selectedSource == resp.name)
            info.func = function()
                popup.selectedSource = resp.name
                UIDropDownMenu_SetText(sourceDD, info.text)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local cancelBtn = SR:MakeButton(popup, "Скасувати", 100, 24)
    cancelBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 16, 16)
    cancelBtn:SetScript("OnClick", function() popup:Hide() end)

    local requestBtn = SR:MakeButton(popup, "Запросити", 100, 24)
    requestBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -16, 16)
    requestBtn:SetScript("OnClick", function()
        if not popup.selectedSource then
            SR:Print("Спершу оберіть джерело зі списку.")
            return
        end
        popup.statusFS:SetText("Запитую копію в |cffffcc00" .. popup.selectedSource .. "|r...")
        SR:RequestRecoveryFrom(popup.selectedSource)
    end)

    self.recoveryPopup = popup
end

function SR:ShowRecoveryPopup()
    if not self.recoveryPopup then self:BuildRecoveryPopup() end
    self.recoveryPopup.selectedSource = nil
    UIDropDownMenu_SetText(self.recoveryPopup.sourceDD, "Ще ніхто не відповів")
    self.recoveryPopup.statusFS:SetText("Опитую рейд, хто має закешовані софт-роли...")
    self.recoveryPopup:Show()
end

--- Викликається з Comms.lua щоразу, коли приходить нова відповідь (RA) на пінг —
-- оновлює статус-текст, поки попап відкритий. Саме меню читає
-- SR._recoveryResponses "ліниво" (щоразу при відкритті), тож досить лише
-- повідомити гравцю, скільки копій вже знайдено.
function SR:UpdateRecoveryPopup()
    if not self.recoveryPopup or not self.recoveryPopup:IsShown() then return end

    local count = 0
    for _ in pairs(self._recoveryResponses or {}) do count = count + 1 end
    self.recoveryPopup.statusFS:SetText(
        "Знайдено копій: |cff44ff44" .. count .. "|r. Оберіть джерело нижче.")
end

--- Викликається з Comms.lua після успішного застосування відновлених даних.
function SR:HideRecoveryPopup()
    if self.recoveryPopup then self.recoveryPopup:Hide() end
end
