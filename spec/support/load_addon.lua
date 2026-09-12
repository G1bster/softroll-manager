--------------------------------------------------------------
-- Завантажує Core.lua / Comms.lua / ChatParser.lua поверх WoW-заглушки
-- і повертає свіжий екземпляр SoftRoll для одного тесту.
-- UI/*.lua свідомо НЕ завантажується: SR:Initialize() (яка викликає
-- SR:CreateUI() тощо) теж не викликається — тести працюють напряму
-- з чистою бізнес-логікою через SR.db, який готуємо тут вручну.
--------------------------------------------------------------

local wow = require("spec.support.wow_mock")

local function project_root()
    local src = debug.getinfo(1, "S").source:sub(2) -- прибрати провідний '@'
    return src:match("(.*)/spec/support/load_addon%.lua$") or "."
end

local ROOT = project_root()

local function fresh_db()
    return {
        instance        = "ICC",
        srMode          = "classic",
        lootDifficulty  = "25H",
        roles           = {},
        reserves        = {},
        playerOverrides = {},
        wishlists       = {},
        minimapPos      = 220,
        coHosts         = {},
        locked          = true,
    }
end

local M = {}

--- Повертає { SR = ..., wow = ... } зі свіжим станом аддона й заглушки.
function M.load()
    wow.install()

    -- Кожен dofile — новий чанк; SoftRoll = {} у Core.lua створює нову
    -- глобальну таблицю щоразу, тож попередній стан не протікає між тестами.
    dofile(ROOT .. "/Core.lua")
    dofile(ROOT .. "/Comms.lua")
    dofile(ROOT .. "/ChatParser.lua")

    local SR = SoftRoll
    SR.db             = fresh_db()
    SR.locked         = SR.db.locked
    SR.sessionActive  = false
    SR.sessionHost    = nil
    SR.sessionLocked  = false
    SR.sessionCoHosts = nil

    return SR, wow
end

return M
