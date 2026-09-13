# Localization & String Extraction Rule

## Mandatory Policy
All user-facing text strings (chat announcements, whisper responses, local prints, UI labels, button texts, tab titles, tooltips, dialog popups, and error messages) MUST be extracted to and defined in `Locales.lua`.

## Guidelines
1. **Never Hardcode Text**: Do not put raw user-visible strings inside `UI/*.lua`, `Core.lua`, `Comms.lua`, or `ChatParser.lua`.
2. **Reference via Locales**: Always use `self.L.<KEY>` or `SoftRoll.L.<KEY>`.
3. **Structured Categories in `Locales.lua`**:
   - `ANNOUNCE_*`: Chat announcements sent to raid/party.
   - `WHISPER_*`: Automated replies to player whispers.
   - `PRINT_*`: Local console feedback (`self:Print(...)`).
   - `POPUP_*`: Confirmations and modal popups.
   - `TAB_*`: Navigation tabs.
   - `BAG_LOOT_*`: Bag loot scanner and trade timer badges.
   - `HELP_*`: Command help listings.
4. **Parameterized Strings**: Use `string.format(self.L.<KEY>, ...)` with `%s`, `%d` specifiers.
