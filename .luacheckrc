-- Luacheck config for a World of Warcraft 3.3.5a (WotLK) addon.
-- Run locally with: luacheck .
-- This is a dev-only static analysis tool — it never runs inside the game
-- and has no effect on the addon at runtime.

std = "lua51"
max_line_length = 200

-- Globals this addon defines itself.
globals = {
    "SoftRoll",
    "SoftRollDB",
    "SLASH_SOFTROLL1",
    "SLASH_SOFTROLL2",
    -- Blizzard globals the addon mutates (adds slash commands / popups / hooks a function).
    "SlashCmdList",
    "StaticPopupDialogs",
    "ChatEdit_InsertLink",
}

-- Blizzard/WoW 3.3.5a client API this addon only reads or calls.
read_globals = {
    "CreateFrame", "UIParent", "Minimap", "GameTooltip", "ItemRefTooltip",
    "DEFAULT_CHAT_FRAME", "ChatFrame1EditBox", "ChatFrameEditBox",
    "DropDownList1", "UISpecialFrames",
    "UnitName", "UnitClass", "UnitLevel", "UnitExists", "UnitIsConnected",
    "GetNumRaidMembers", "GetNumPartyMembers", "GetRaidRosterInfo", "GetUnitName", "GetPartyLeaderIndex",
    "IsRaidLeader", "IsRaidOfficer", "IsPartyLeader",
    "GetItemInfo", "GetItemIcon", "GetItemQualityColor",
    "SendChatMessage", "SendAddonMessage", "RegisterAddonMessagePrefix",
    "GetCursorInfo", "GetCursorPosition", "ClearCursor", "HandleModifiedItemClick", "IsShiftKeyDown",
    "ToggleDropDownMenu", "CloseDropDownMenus",
    "UIDropDownMenu_AddButton", "UIDropDownMenu_CreateInfo", "UIDropDownMenu_Initialize",
    "UIDropDownMenu_SetWidth", "UIDropDownMenu_SetText",
    "UIDropDownMenu_EnableDropDown", "UIDropDownMenu_DisableDropDown",
    "UIDROPDOWNMENU_MENU_VALUE", "UIDROPDOWNMENU_OPEN_MENU",
    "StaticPopup_Show",
    "format", "strtrim", "tinsert", "wipe",
}

-- Blizzard's frame-script callback signature always starts with (self, ...),
-- and dropdown callbacks always pass a "button" widget — both are frequently
-- unused here by design, not by mistake.
ignore = {
    "212/self",
    "212/button",
    "231/self",
    "421/self",
}
