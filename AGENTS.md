# Project Guidelines & Rules for SoftRollManager

## 1. Localization & String Extraction (`Locales.lua`) — MANDATORY RULE
- **Zero Hardcoded Strings**: All user-facing text strings MUST be extracted to and defined in `Locales.lua`.
  - This includes:
    - Button labels and titles
    - Tab headers and panel titles
    - Chat announcements and raid messages
    - Whisper responses to raid members
    - Local prints and status notifications (`self:Print`)
    - StaticPopup dialog messages and button texts
    - Tooltip text and table headers
    - Slash command help and error descriptions
- **No Direct UI Strings**: Never hardcode Ukrainian, English, or Russian text directly in `Core.lua`, `UI/*.lua`, `Comms.lua`, or `ChatParser.lua`.
- **Usage Convention**: Always reference text strings via `self.L.<KEY>` or `SoftRoll.L.<KEY>`.
- **Formatting**: For dynamic parameters, use `string.format(self.L.<KEY>, ...)` or `format(...)` with standard placeholders (`%s`, `%d`).
- **Organization**: Maintain logical, numbered sections in `Locales.lua` with descriptive uppercase keys (e.g., `ANNOUNCE_*`, `PRINT_*`, `WHISPER_*`, `POPUP_*`, `TAB_*`, `BAG_LOOT_*`).

---

## 2. UI Layout & Default Views
- **Loot Session (Tab 4) Default**:
  - The default view for Tab 4 (Loot Session) must be the **"Здобич у сумках" (Bag Loot)** scanner (`mode = "bag"`), showing all tradable drops in the player's bags.
  - The **"Активний розрол" (Active Roll)** panel (`mode = "roll"`) is activated when the player clicks "Роздати" on an item, or when a roll is in progress.

---

## 3. Inventory & Loot Trading Rules
- **Exclude Personal Soulbound Gear**:
  - The Bag Loot Scanner must ONLY list items that can actually be traded to raid members.
  - Any item that is **Soulbound** (`ITEM_SOULBOUND`) and has **no active trade timer** (`tradeMins == nil`) is the player's own personal equipment (e.g. their own Deathbringer's Will / Воля Смертоносного) and CANNOT be traded. It MUST be excluded from the bag loot list.
  - Tradable items are:
    1. BoP items with an active 2-hour trade timer (`tradeMins ~= nil`).
    2. Unbound BoE items (`isSoulbound == false`) from the raid instance or with registered soft-reserves.

---

## 4. WoW 3.3.5a (WotLK) & Lua 5.1 Compatibility
- Do NOT use Lua 5.2+ features (e.g., `goto`, `_ENV`, `table.pack`).
- Avoid multi-byte UTF-8 Cyrillic characters inside Lua pattern character classes (e.g., do NOT use `[чЧ]`; use separate pattern checks).
- All changes must pass the test suite (`spec/*.lua`) and Lua 5.1 AST syntax validation.
