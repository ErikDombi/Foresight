--- Core state, helpers and names shared by every Foresight module.
local FS = Foresight
FS.VERSION = '1.0.0'

-------------------------------------------------------------------------------
-- Config (persisted through Steamodded's mod config)
-------------------------------------------------------------------------------
FS.config = FS.mod.config or {}
FS.mod.config = FS.config

local DEFAULTS = {
    hotkey = 'f3',
    keys = { save_mod = 'z', load_mod = 'x' },
    hotkeys = { states = true, reroll = true, search = true, rewind = true },
    search = { budget_ms = 12, unseeded = true, max_seeds = 0, keep_menu = true },
    rewind = { enabled = true, keep = 40 },
    extended_speed = true,
    dim = 2,
    filters = {},
    presets = {},
    slots = {},
    history = {},
    favorites = {},
}

local function fill(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == 'table' then
                local t = {}
                fill(t, v)
                dst[k] = t
            else
                dst[k] = v
            end
        elseif type(v) == 'table' and type(dst[k]) == 'table' and next(v) ~= nil then
            fill(dst[k], v)
        end
    end
end
fill(FS.config, DEFAULTS)

function FS.save_config()
    pcall(SMODS.save_mod_config, FS.mod)
end

-------------------------------------------------------------------------------
-- Session state (not persisted)
-------------------------------------------------------------------------------
FS.state = FS.state or {
    tab = 'finder',
    finder = { editing = nil, page = 1 },
    forecast = { kind = 'Arcana', rolls = 3, antes = 4 },
    states = {},
    rewind = { page = 1 },
    seeds = { input = '', view = 'history', page = 1 },
}
FS.view = FS.view or {}

-------------------------------------------------------------------------------
-- Numbers (Talisman / Amulet safe)
-------------------------------------------------------------------------------
function FS.num(x)
    local t = type(x)
    if t == 'number' then return x end
    if x == nil then return 0 end
    if type(to_number) == 'function' then
        local ok, v = pcall(to_number, x)
        if ok and type(v) == 'number' then return v end
    end
    if t == 'table' or t == 'cdata' then
        local ok, v = pcall(function() return x:to_number() end)
        if ok and type(v) == 'number' then return v end
    end
    return tonumber(x) or 0
end

function FS.fmt(x)
    if x == nil then return '-' end
    if type(x) == 'number' and x == math.floor(x) and math.abs(x) < 1e15 then
        local s = tostring(math.floor(x))
        local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
        return (out:gsub('^,', ''):gsub('^%-,', '-'))
    end
    local ok, s = pcall(number_format, x)
    if ok and s ~= nil then return tostring(s) end
    return tostring(x)
end

function FS.clamp(v, lo, hi)
    if lo and v < lo then return lo end
    if hi and v > hi then return hi end
    return v
end

function FS.step_mult()
    if love.keyboard.isDown('lshift', 'rshift') then return 10 end
    return 1
end

--- "3m ago", "2h ago", "yesterday", ...
function FS.ago(t)
    if not t then return '' end
    local d = os.time() - t
    if d < 10 then return 'just now' end
    if d < 60 then return d .. 's ago' end
    if d < 3600 then return math.floor(d / 60) .. 'm ago' end
    if d < 86400 then return math.floor(d / 3600) .. 'h ago' end
    if d < 172800 then return 'yesterday' end
    return math.floor(d / 86400) .. ' days ago'
end

function FS.clock(t)
    return os.date('%H:%M:%S', t or os.time())
end

function FS.copy(t)
    if type(t) ~= 'table' then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = FS.copy(v) end
    return o
end

-------------------------------------------------------------------------------
-- Game state helpers
-------------------------------------------------------------------------------
function FS.in_run()
    return G.STAGE == G.STAGES.RUN and G.GAME ~= nil and G.jokers ~= nil and G.hand ~= nil and G.deck ~= nil
end

function FS.state_is(...)
    for i = 1, select('#', ...) do
        local name = select(i, ...)
        if G.STATES[name] and G.STATE == G.STATES[name] then return true end
    end
    return false
end

function FS.state_label(state)
    state = state or G.STATE
    local S = G.STATES
    if state == S.BLIND_SELECT then return 'Blind select' end
    if state == S.SHOP then return 'Shop' end
    if state == S.SELECTING_HAND then return 'Playing' end
    if state == S.ROUND_EVAL then return 'Cash out' end
    if state == S.GAME_OVER then return 'Game over' end
    if state == S.TAROT_PACK or state == S.PLANET_PACK or state == S.SPECTRAL_PACK or state == S.STANDARD_PACK
        or state == S.BUFFOON_PACK or state == S.SMODS_BOOSTER_OPENED then return 'Opening pack' end
    return 'In run'
end

-------------------------------------------------------------------------------
-- Errors, dispatch, feedback
-------------------------------------------------------------------------------
function FS.log(msg)
    if sendInfoMessage then sendInfoMessage(tostring(msg), 'Foresight') else print('[Foresight] ' .. tostring(msg)) end
end

function FS.err(msg)
    if sendErrorMessage then sendErrorMessage(tostring(msg), 'Foresight') else print('[Foresight] ' .. tostring(msg)) end
end

function FS.safe(f, ...)
    local args = { n = select('#', ...), ... }
    local ok, err = xpcall(function() return f(unpack(args, 1, args.n)) end, debug.traceback)
    if not ok then
        FS.err(err)
        FS.toast('Something went wrong - details are in the log', G.C.RED, 'cancel')
    end
    return ok, err
end

G.FUNCS.fsgt_click = function(e)
    local f = e and e.config and e.config.fs_click
    if f then FS.safe(f, e) end
end

G.FUNCS.fsgt_sync = function(e)
    local f = e and e.config and e.config.fs_sync
    if not f then return end
    local ok, err = pcall(f, e)
    if not ok and not e.config.fs_sync_failed then
        e.config.fs_sync_failed = true
        FS.log('sync error: ' .. tostring(err))
    end
end

function FS.sfx(name, pitch, vol)
    if name == false then return end
    pcall(play_sound, name or 'generic1', pitch or 1, vol or 0.6)
end

--- Status-bar message inside the menu.
function FS.toast(msg, colour, sound)
    FS.last_msg = msg
    FS.last_col = colour or G.C.UI.TEXT_LIGHT
    if sound ~= false then FS.sfx(sound or 'generic1', 1.1, 0.4) end
    if not FS.is_open or not FS.is_open() then return end
    local old = FS.view.status
    FS.view.status = DynaText({
        string = { msg }, colours = { FS.last_col }, shadow = true, silent = true,
        pop_in = 0, pop_in_rate = 6, scale = 0.36, maxw = 11,
    })
    if old then
        G.E_MANAGER:add_event(Event({
            trigger = 'after', delay = 0.2, timer = 'REAL', blockable = false, blocking = false,
            func = function() if old.remove then old:remove() end return true end,
        }))
    end
end

function FS.warn(msg) FS.toast(msg, G.C.FILTER, 'cancel') end

--- In-game popup for hotkey actions (works with the menu closed). Falls back to the status bar.
function FS.notify(msg, colour, sound)
    if FS.is_open and FS.is_open() then return FS.toast(msg, colour, sound) end
    FS.last_msg, FS.last_col = msg, G.C.UI.TEXT_LIGHT
    if sound ~= false then FS.sfx(sound or 'other1', 0.9, 0.45) end
    local major = (G.STAGE == G.STAGES.RUN and G.play) or G.title_top or G.ROOM_ATTACH
    if not major then return end
    pcall(attention_text, {
        text = msg, scale = 0.55, hold = 1.6, major = major, align = 'cm', offset = { x = 0, y = -3.2 },
        backdrop_colour = colour or G.C.SECONDARY_SET.Spectral, silent = true,
    })
end

-------------------------------------------------------------------------------
-- Names
-------------------------------------------------------------------------------
FS._names = {}

local function loc_or(fallback, ...)
    local ok, s = pcall(localize, ...)
    if ok and type(s) == 'string' and s ~= '' and s ~= 'ERROR' then return s end
    return fallback
end
FS.loc_or = loc_or

function FS.name_of(obj)
    if type(obj) == 'string' then obj = G.P_CENTERS[obj] or G.P_TAGS[obj] or G.P_BLINDS[obj] or { key = obj } end
    if not obj then return '?' end
    local key = obj.key or obj.name or '?'
    local cached = FS._names[key]
    if cached then return cached end
    local set = obj.set
    if not set and G.P_TAGS[key] then set = 'Tag' end
    if not set and G.P_BLINDS[key] then set = 'Blind' end
    local n = loc_or(obj.name or key, { type = 'name_text', set = set, key = key })
    FS._names[key] = n
    return n
end

function FS.edition_name(key)
    if not key then return nil end
    return FS.name_of(G.P_CENTERS[key] or { key = key, set = 'Edition' })
end

function FS.deck_name(key)
    local c = key and G.P_CENTERS[key]
    if not c then return key or '?' end
    return FS.name_of(c)
end

function FS.stake_key(i)
    local s = G.P_CENTER_POOLS.Stake and G.P_CENTER_POOLS.Stake[i or 1]
    return s and s.key
end

function FS.stake_name(i)
    local s = G.P_CENTER_POOLS.Stake and G.P_CENTER_POOLS.Stake[i or 1]
    if not s then return 'Stake ' .. tostring(i) end
    local n = loc_or(s.name or s.key, { type = 'name_text', set = 'Stake', key = s.key })
    return (n:gsub(' Stake$', ''))
end

function FS.stake_colour(i)
    local ok, c = pcall(get_stake_col, i or 1)
    if ok and type(c) == 'table' then return c end
    return G.C.WHITE
end

function FS.current_deck_key()
    local gm = G.GAME
    if gm and gm.selected_back_key and gm.selected_back_key.key then return gm.selected_back_key.key end
    if gm and gm.selected_back and gm.selected_back.effect and gm.selected_back.effect.center then
        return gm.selected_back.effect.center.key
    end
    return 'b_red'
end

FS.EDITION_COLOURS = {
    e_foil = HEX('7aa7e0'),
    e_holo = HEX('e8608c'),
    e_negative = HEX('4b4e78'),
}

function FS.edition_colour(key)
    if not key then return G.C.UI.BACKGROUND_INACTIVE end
    if key == 'e_polychrome' then return G.C.DARK_EDITION end
    local c = G.P_CENTERS[key]
    return FS.EDITION_COLOURS[key] or (c and c.badge_colour) or G.C.DARK_EDITION
end

-------------------------------------------------------------------------------
-- Tab registry
-------------------------------------------------------------------------------
FS.TABS = {}
FS.TAB_BY_ID = {}

function FS.register_tab(def)
    for i, t in ipairs(FS.TABS) do
        if t.id == def.id then table.remove(FS.TABS, i) break end
    end
    FS.TABS[#FS.TABS + 1] = def
    FS.TAB_BY_ID[def.id] = def
    table.sort(FS.TABS, function(a, b) return (a.order or 99) < (b.order or 99) end)
end
