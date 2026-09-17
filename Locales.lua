--------------------------------------------------------------
-- SoftRollManager  —  Locales.lua
-- Текстові константи, локалізація та повідомлення чату
-- Сумісно з WoW 3.3.5a (WotLK)
--------------------------------------------------------------

SoftRoll = SoftRoll or {}
local SR = SoftRoll

SR.L = SR.L or {}
local L = SR.L

-- Префікс для повідомлень у рейдовий/груповий чат
L.CHAT_PREFIX = "[SR] "

--------------------------------------------------------------
-- 1. ПОВІДОМЛЕННЯ В РЕЙД-ЧАТ / ГРУПУ / SAY
--------------------------------------------------------------
L.ANNOUNCE_ALL_HEADER           = "[SR] Всі софт-роли (%s):"
L.ANNOUNCE_ALL_EMPTY            = "[SR] Список софт-ролів порожній."
L.ANNOUNCE_MISSING_HEADER       = "[SR] Гравці з неповними софт-ролами:"
L.ANNOUNCE_MISSING_NONE         = "[SR] Всі вибрали софти повністю."
L.ANNOUNCE_PLAYER_NO_SR         = "[SR] %s — немає софтів%s"
L.ANNOUNCE_PLAYER_HAS_SR        = "[SR] %s — софти%s:"
L.ANNOUNCE_BOSS_EMPTY           = "[SR] %s — немає зареєстрованих софт-ролів"
L.ANNOUNCE_BOSS_HEADER          = "[SR] %s — софт-роли:"
L.ANNOUNCE_ITEM_RESERVERS       = "[SR] %s — софт-роли: %s"

L.SESSION_LOCKED                = "[SR] Реєстрацію софт-ролів ЗАБЛОКОВАНО."
L.SESSION_UNLOCKED              = "[SR] Реєстрацію софт-ролів РОЗБЛОКОВАНО."
L.SR_ADDED_FOR_PLAYER           = "[SR] Додано %s до софтів гравця %s"
L.SR_REMOVED_FOR_PLAYER         = "[SR] Видалено %s з софтів гравця %s"
L.ALL_SRS_CLEARED               = "[SR] Очищено ВСІ софт-роли рейду."
L.PLAYER_SRS_CLEARED            = "[SR] Очищено софт-роли гравця %s"

-- Анонси під час роздачі та розіграшу здобичі
L.LOOT_NO_SRS_MS                = "[SR] %s — немає софт-ролів! Ролимо на мейн-спек (/roll)"
L.LOOT_ITEM_HEADER              = "[SR] Здобич: %s"
L.LOOT_ROLL_CANDIDATES          = "[SR] Претенденти: %s — кидайте /roll!"
L.ROLL_NO_ROLLS                 = "[SR] Рол завершено! Ніхто не кинув /roll."
L.ROLL_TIE                      = "[SR] Рол завершено! Нічия між %s (Рол: %d). Перероліть!"
L.ROLL_WINNER                   = "[SR] Рол завершено! Переможець: %s (Рол: %d)!"

-- Інструкції для рейду
L.INSTRUCT_RESERVE              = "[SR] Щоб зарезервувати предмет, напишіть в ПМ або рейд-чат: sr [лінк предмета]"
L.INSTRUCT_DOUBLE               = "[SR] Для подвійного софту: sr [лінк предмета] x2"
L.INSTRUCT_COMMANDS             = "[SR] Ваші софти: sr list | Видалити один: sr clear [лінк] | Очистити всі: sr clear"

--------------------------------------------------------------
-- 2. ВІДПОВІДІ НА КОМАНДИ В ПРИВАТ (WHISPER)
--------------------------------------------------------------
L.WHISPER_SESSION_NOT_STARTED   = "Сесія софт-ролів ще не розпочалась. Зачекайте, поки РЛ її почне."
L.WHISPER_SESSION_NOT_ACTIVE    = "Сесія софт-ролів ще не розпочалась."
L.WHISPER_CHANGES_LOCKED        = "Зміни софт-ролів наразі ЗАБЛОКОВАНІ. Спробуйте пізніше."
L.WHISPER_REGISTER_LOCKED       = "Реєстрація софт-ролів наразі ЗАБЛОКОВАНА. Спробуйте пізніше."
L.WHISPER_HELP                  = "Довідка по командам: sr [лінк] (або sr [лінк] x2) — зареєструвати софт-рол | sr list — переглянути ваші софти | sr clear [лінк] — видалити предмет | sr clear — очистити всі"
L.WHISPER_USAGE_REGISTER        = "Команда: sr [лінк на предмет] (можна додати x2, наприклад: sr [лінк] x2)"
L.WHISPER_NO_SRS                = "У вас немає зареєстрованих софт-ролів."
L.WHISPER_NO_SRS_SHORT          = "У вас немає зареєстрованих софтів."
L.WHISPER_TARGET_NO_SRS         = "У %s немає зареєстрованих софтів."
L.WHISPER_LIST_HEADER           = "Ваші зареєстровані софт-роли (%d/%d):"
L.WHISPER_REGISTER_SUCCESS      = "Софт-рол зареєстровано: %s%s (%d з %d використано)."
L.WHISPER_REGISTER_ROLE         = "Софт-рол зареєстровано: %s%s (%d з %d використано). Роль: %s%s"
L.WHISPER_REGISTER_FOR_TARGET   = "Софт-рол зареєстровано ДЛЯ %s: %s%s (%d з %d)."
L.WHISPER_RL_ADDED_SR           = "РЛ (%s) додав вам софт-рол: %s%s (%d з %d)."
L.WHISPER_REMOVE_SUCCESS        = "Ваш софт на %s було успішно видалено."
L.WHISPER_REMOVE_FOR_TARGET     = "Софт на %s для %s було видалено."
L.WHISPER_RL_REMOVED_SR         = "РЛ (%s) видалив ваш софт на %s"
L.WHISPER_CLEAR_SUCCESS         = "Ваші софт-роли було успішно очищено."
L.WHISPER_CLEAR_FOR_TARGET      = "Софт-роли гравця %s було успішно очищено."
L.WHISPER_RL_CLEARED_ALL        = "РЛ (%s) очистив ваші софт-роли."
L.WHISPER_NOT_RESERVED          = "Ви не резервували %s."
L.WHISPER_TARGET_NOT_RESERVED   = "%s не резервував(ла) %s."
L.WHISPER_NOTHING_TO_CLEAR      = "Немає що очищати."
L.WHISPER_ERR_NO_LINK           = "Помилка: Не знайдено дійсного посилання на предмет."
L.WHISPER_ERR_UNKNOWN_ITEM      = "Помилка: неможливо розпізнати предмет."
L.WHISPER_ERR_NOT_IN_RAID       = "Помилка: Гравця '%s' немає у рейді."
L.WHISPER_ERR_NOT_AUTHORIZED_ADD   = "Помилка: Тільки РЛ або помічник може додавати софт-роли іншим гравцям."
L.WHISPER_ERR_NOT_AUTHORIZED_CLEAR = "Помилка: Тільки РЛ або помічник може очищати софт-роли іншим гравцям."
L.WHISPER_ERR_PREFIX            = "Помилка: %s"

--------------------------------------------------------------
-- 3. ЛОКАЛЬНІ ПОВІДОМЛЕННЯ В ЧАТ (SR:Print)
--------------------------------------------------------------
L.PRINT_LOADED                  = "v%s завантажено. Введіть |cff00ff00/sr|r, щоб відкрити."
L.PRINT_ONLY_HOST_RESET         = "Лише активний хост може скидати софт-роли під час сесії."
L.PRINT_STATUS_LOCKED           = "Софт-роли |cffff4444ЗАБЛОКОВАНО|r — нові реєстрації не приймаються."
L.PRINT_STATUS_UNLOCKED         = "Софт-роли |cff44ff44РОЗБЛОКОВАНО|r."
L.PRINT_ALL_CLEARED             = "Всі софти успішно |cffff4444очищено|r."
L.PRINT_RL_TRANSFERRED          = "Ви отримали лідера рейду. Сесію SR автоматично перенесено на вас."
L.PRINT_HOST_LEFT               = "Хост %s %s. Сесію призупинено."
L.PRINT_COHOST_DEMOTED          = "Гравець %s втратив права помічника рейду і був видалений з помічників аддону."
L.PRINT_LIMIT_CHANGED           = "Ліміт SR для %s змінено на |cffffcc00x%d|r"
L.PRINT_LIMIT_RESET             = "Ліміт SR для %s скинуто до стандартного для ролі"
L.PRINT_ROLE_REQUEST_SENT       = "Запит на зміну ролі надіслано хосту..."
L.PRINT_LIMIT_REQUEST_SENT      = "Запит на зміну ліміту надіслано хосту..."
L.PRINT_LOCK_REQUEST_SENT       = "Запит на зміну блокування надіслано хосту..."
L.PRINT_CLEAR_ALL_REQUEST_SENT  = "Запит на очищення всіх софтів надіслано хосту..."
L.PRINT_CLEAR_PLAYER_SENT       = "Запит на очищення надіслано хосту..."
L.PRINT_REMOVE_REQUEST_SENT     = "Запит на видалення надіслано хосту..."
L.PRINT_REG_REQUEST_SENT        = "Запит на реєстрацію SR надіслано хосту |cffffcc00%s|r…"
L.PRINT_REG_REQUEST_COHOST      = "Запит на реєстрацію SR (помічник) надіслано хосту..."
L.PRINT_CANNOT_ADD_OTHERS       = "Ви не можете додавати софт-роли іншим гравцям."
L.PRINT_SELECT_ITEM_FIRST       = "Спочатку виберіть предмет зі списку."
L.PRINT_ITEM_REMOVED_FROM       = "Видалено предмет зі списку %s"
L.PRINT_SRS_CLEARED_FOR         = "Очищено софт-роли для %s"
L.PRINT_SR_REGISTERED           = "SR зареєстровано."
L.PRINT_SR_REGISTERED_FOR       = "SR зареєстровано для %s."
L.PRINT_SR_REG_ERROR            = "Помилка реєстрації SR: %s"
L.PRINT_USER_REGISTERED         = "%s зареєстрував(ла) софт-рол: %s"
L.PRINT_COHOST_ADDED_FOR        = "%s (помічник) додав софт-рол для %s: %s"
L.PRINT_COHOST_CHANGED_DUNGEON  = "Помічник %s змінив налаштування підземелля."
L.PRINT_COHOST_CHANGED_ROLE     = "Помічник %s змінив роль %s на %s"
L.PRINT_COHOST_CHANGED_LIMIT    = "Помічник %s змінив ліміт %s на %s"
L.PRINT_COHOST_LOCKED           = "Помічник %s ЗАБЛОКУВАВ софт-роли."
L.PRINT_COHOST_UNLOCKED         = "Помічник %s РОЗБЛОКУВАВ софт-роли."
L.PRINT_COHOST_CLEARED_ALL      = "Помічник %s очистив усі софт-роли."
L.PRINT_HOST_CLEARED_ALL        = "Хост очистив усі софт-роли."
L.PRINT_HOST_RELOADED           = "Хост %s перезавантажив гру. Сесію призупинено (очікування відновлення)."
L.PRINT_SYNC_COMPLETE           = "Синхронізацію завершено."
L.PRINT_RECOVERY_COMPLETE       = "Відновлено софт-роли для |cff44ff44%d|r гравців із копії |cffffcc00%s|r."
L.PRINT_SESSION_START_LEADER    = "Лише лідер групи або рейду може почати сесію SR."
L.PRINT_SESSION_ALREADY_ACTIVE  = "Сесія вже активна — хост: |cffffcc00%s|r."
L.PRINT_SESSION_STARTED_HOST    = "Сесію SR |cff44ff44РОЗПОЧАТО|r — ви активний хост."
L.PRINT_SESSION_AUTO_STARTED    = "Сесію SR |cff44ff44авто-розпочато|r. Реєстрації |cffff4444ЗАБЛОКОВАНІ|r — розблокуйте коли готові."
L.PRINT_SESSION_NO_ACTIVE       = "Немає активної сесії SR."
L.PRINT_SESSION_ONLY_HOST_END   = "Тільки активний хост (|cffffcc00%s|r) може завершити сесію."
L.PRINT_SESSION_ENDED           = "Сесію SR |cffff4444ЗАВЕРШЕНО|r."
L.PRINT_SESSION_ENDED_BY        = "Сесію SR завершено гравцем |cffffcc00%s|r."
L.PRINT_SESSION_HOST_IS_YOU     = "Ви є хостом сесії софт-ролів."
L.PRINT_SESSION_STARTED_BY      = "Сесію SR розпочато — хост: |cffffcc00%s|r."
L.PRINT_ONLY_RL_ASSIGN_COHOST   = "Тільки РЛ може призначати помічників."
L.PRINT_ITEM_NOT_FOUND_SHIFT    = "Не вдалося визначити предмет. Переконайтеся, що ви зробили Shift-клік на правильний лінк."
L.PRINT_NO_ITEM_SELECTED        = "Предмет для роздачі не вибрано."
L.PRINT_NOT_IN_RAID_SAY         = "Ви не в рейді — використовуємо /say."
L.PRINT_RECOVERY_SELECT_SOURCE  = "Спершу оберіть джерело зі списку."
L.PRINT_MODE_CHANGED            = "Режим SR змінено на |cffffcc00%s|r"
L.PRINT_ONLY_LEADER_ANNOUNCE    = "Тільки лідер рейду або помічник аддону може анонсувати інструкції."

--------------------------------------------------------------
-- 4. ДОВІДКА ПО КОМАНДАМ (/sr help)
--------------------------------------------------------------
L.HELP_HEADER                   = "Команди:"
L.HELP_CMD_OPEN                 = "  |cff00ff00/sr|r — Відкрити/закрити головне вікно"
L.HELP_CMD_RESET                = "  |cff00ff00/sr reset|r — Очистити всі софт-роли"
L.HELP_CMD_LOCK                 = "  |cff00ff00/sr lock / unlock|r — Заблокувати/розблокувати реєстрацію"
L.HELP_CMD_ANNOUNCE             = "  |cff00ff00/sr announce|r — Опублікувати всі софти в рейдовий чат"
L.HELP_CMD_HELP                 = "  |cff00ff00/sr help|r — Ця довідка"

--------------------------------------------------------------
-- 5. ДІАЛОГОВІ ВІКНА ПІДТВЕРДЖЕННЯ (StaticPopupDialogs)
--------------------------------------------------------------
L.POPUP_CONFIRM_CLEAR_ALL       = "Ви впевнені, що хочете очистити ВСІ софт-роли рейду?\nЦю дію неможливо скасувати!"
L.POPUP_CONFIRM_CLEAR_PLAYER    = "Очистити всі софт-роли для %s?"
L.POPUP_CONFIRM_REMOVE_ITEM     = "Видалити %s для %s?"
L.POPUP_CONFIRM_ADD_ITEM        = "Додати %s для %s?"

--------------------------------------------------------------
-- 6. СКАНЕР СУМОК ТА ТАЙМЕР ПЕРЕДАЧІ (BAG LOOT & TRADE TIMER)
--------------------------------------------------------------
L.BAG_LOOT_TAB                  = "Здобич у сумках"
L.BAG_LOOT_TAB_WITH_COUNT       = "Здобич у сумках (%d)"
L.BAG_LOOT_ACTIVE_ROLL          = "Активний розрол"
L.BAG_LOOT_BACK_TO_BAGS         = "⬅ До сумок"
L.BAG_LOOT_REFRESH              = "Оновити сумки"
L.BAG_LOOT_EMPTY                = "У ваших сумках не знайдено здобичі рейду або софт-ролів."
L.BAG_LOOT_SR_BADGE             = "%d SR"
L.BAG_LOOT_FREE_BADGE           = "Вільний (0 SR)"
L.BAG_LOOT_DISTRIBUTE_BTN       = "Роздати"
L.BAG_LOOT_TIMER_EXPIRED        = "Час сплив"
L.BAG_LOOT_TIMER_CRITICAL       = "%s (!)"
L.BAG_LOOT_NO_TIMER             = "Без таймера"
L.BAG_LOOT_SUMMARY              = "Предметів у сумках: %d | З софтами: %d | Спливає час (<30хв): %d"

--------------------------------------------------------------
-- 7. ГОЛОВНІ ВКЛАДКИ (MAIN TABS)
--------------------------------------------------------------
L.TAB_DASHBOARD                 = "Панель керування"
L.TAB_LEDGER                    = "Список софтів"
L.TAB_BROWSER                   = "Огляд луту"
L.TAB_SESSION                   = "Здобич рейду"

--------------------------------------------------------------
-- 8. ЕЛЕМЕНТИ ІНТЕРФЕЙСУ (UI LABELS & BUTTONS)
--------------------------------------------------------------
L.UI_CURRENT_ITEM               = "Поточний предмет: %s"
L.UI_NO_ITEM_CHOSEN             = "Поточний предмет: [Не вибрано]"
L.UI_NO_SRS_FOR_ITEM            = "Ніхто не засофтив цей предмет"
L.UI_START_ROLL_BTN             = "Почати рол (/rw)"
L.UI_END_ROLL_BTN               = "Завершити рол"
L.UI_EXPORT_TOOLTIP             = "Експорт софтів"
L.LOOT_RESERVED_SUMMARY         = "%d гравців зарезервували цей предмет"
L.UI_TARGET_LABEL               = "Кому:"
L.UI_TARGET_SELF                = "Собі"
L.UI_TARGET_RAID_HEADER         = "Рейд"
L.UI_RESERVE_BTN                = "Засофтити x%d"
L.UI_REMOVE_ITEM_TOOLTIP        = "Прибрати софт"


