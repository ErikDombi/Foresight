--- Seed filters: what each kind checks, how it describes itself, and its editor.
local FS = Foresight
local UI, O = FS.UI, FS.Oracle
local R, C = G.UIT.R, G.UIT.C

local F = {}
FS.Filters = F

F.TYPES = {}
F.ORDER = { 'tag', 'boss', 'voucher', 'soul', 'legendary', 'shop', 'shop_pack', 'pack', 'erratic' }

local EDW = 11.35 -- editor content width

-------------------------------------------------------------------------------
-- Small helpers
-------------------------------------------------------------------------------
local function count_set(s)
    local n = 0
    for _ in pairs(s or {}) do n = n + 1 end
    return n
end

local function names(set, max)
    local list = {}
    for k in pairs(set or {}) do list[#list + 1] = FS.name_of(k) end
    table.sort(list)
    max = max or 3
    if #list == 0 then return 'anything' end
    if #list > max then return ('one of %d choices'):format(#list) end
    if #list == 1 then return list[1] end
    return table.concat(list, ', ', 1, #list - 1) .. ' or ' .. list[#list]
end

local function edition_ok(want, got)
    if not want or want == 'any' then return true end
    if want == 'none' then return got == nil end
    if want == 'some' then return got ~= nil end
    return got == want
end

local function edition_label(want)
    if not want or want == 'any' then return nil end
    if want == 'none' then return 'no edition' end
    if want == 'some' then return 'any edition' end
    return FS.edition_name(want)
end

function F.edition_items(with_some)
    local out = { { key = 'any', label = 'Any', colour = G.C.UI.BACKGROUND_INACTIVE } }
    out[#out + 1] = { key = 'none', label = 'None', colour = G.C.GREY }
    if with_some then out[#out + 1] = { key = 'some', label = 'Any edition', colour = G.C.DARK_EDITION } end
    for _, v in ipairs(G.P_CENTER_POOLS.Edition or {}) do
        if v.key ~= 'e_base' then
            out[#out + 1] = { key = v.key, label = FS.edition_name(v.key), colour = FS.edition_colour(v.key) }
        end
    end
    return out
end

local function hidden(c)
    return SMODS.hide_from_collection and SMODS.hide_from_collection(c)
end

local function center_items(pool, keep)
    local out = {}
    for _, c in ipairs(pool or {}) do
        if c.key and not hidden(c) and (not keep or keep(c)) then out[#out + 1] = { key = c.key } end
    end
    return out
end

--- Booster groups ("Mega Spectral Pack"): one representative per kind and size.
function F.booster_groups()
    if F._groups then return F._groups end
    local groups, by_key, order = {}, {}, {}
    for _, c in ipairs(G.P_CENTER_POOLS.Booster or {}) do
        local size = c.key:find('_mega') and 'Mega' or c.key:find('_jumbo') and 'Jumbo' or 'Normal'
        local gid = tostring(c.kind or c.key) .. '|' .. size
        if not groups[gid] then
            groups[gid] = { id = gid, key = c.key, kind = c.kind, size = size, keys = {} }
            order[#order + 1] = groups[gid]
        end
        groups[gid].keys[c.key] = true
        by_key[c.key] = gid
    end
    for _, g in ipairs(order) do
        local n = FS.name_of(G.P_CENTERS[g.key])
        g.label = n
    end
    F._groups = { list = order, by_id = groups, by_key = by_key }
    return F._groups
end

-------------------------------------------------------------------------------
-- Editor controls
-------------------------------------------------------------------------------
local function label_box(text, w)
    return { n = C, config = { align = 'cl', minw = w or 1.3 }, nodes = { UI.text(text, 0.28, UI.muted()) } }
end

--- [-] value [+] bound to f[field] within lo..hi.
function F.num_ctrl(f, field, lo, hi, fmt, on_change, colour)
    local function set(v)
        local nv = FS.clamp(v, lo, hi)
        if nv ~= f[field] then
            f[field] = nv
            FS.sfx('generic1', 1.2, 0.3)
            if on_change then on_change() end
        end
    end
    return UI.col({
        UI.button({ label = '-', w = 0.42, h = 0.4, scale = 0.32, colour = colour or G.C.UI.BACKGROUND_INACTIVE,
            on_click = function() set((f[field] or lo) - FS.step_mult()) end }),
        UI.pill(function() return fmt and fmt(f[field]) or tostring(f[field]) end, G.C.UI.TEXT_LIGHT, 1.25, 0.4, 0.31),
        UI.button({ label = '+', w = 0.42, h = 0.4, scale = 0.32, colour = colour or G.C.UI.BACKGROUND_INACTIVE,
            on_click = function() set((f[field] or lo) + FS.step_mult()) end }),
    }, { padding = 0.03 })
end

local function ante_ctrl(f, field, on_change, lo, hi)
    return F.num_ctrl(f, field or 'ante', lo or 1, hi or 8, function(v) return 'Ante ' .. tostring(v) end, on_change)
end

local function controls(list)
    local nodes = {}
    for i, n in ipairs(list) do
        if i > 1 then nodes[#nodes + 1] = UI.spacer(0.18) end
        -- rows inside a row stack vertically; keep every control inline
        if n.n == R then n = { n = C, config = { align = 'cm' }, nodes = { n } } end
        nodes[#nodes + 1] = n
    end
    return UI.row(nodes, { align = 'cl', padding = 0.03 })
end

local function hint(text)
    return UI.row({ UI.text(text, 0.26, UI.muted(), { maxw = EDW - 0.3 }) }, { align = 'cl', padding = 0.02 })
end

local function field(label, node, w)
    return UI.col({ label_box(label, w), node }, { padding = 0 })
end

-------------------------------------------------------------------------------
-- Type registry
-------------------------------------------------------------------------------
local function def(id, t)
    t.id = id
    F.TYPES[id] = t
end

function F.new(type_id, params)
    local t = F.TYPES[type_id]
    local f = t.defaults()
    f.type = type_id
    f.on = true
    if params then for k, v in pairs(params) do f[k] = v end end
    return f
end

function F.describe(f)
    local t = F.TYPES[f.type]
    if not t then return 'Unknown filter' end
    local ok, s = pcall(t.describe, f)
    return ok and s or t.label
end

function F.problem(f)
    local t = F.TYPES[f.type]
    if not t then return 'Unknown filter type' end
    if t.problem then return t.problem(f) end
end

-------------------------------------------------------------------------------
-- Skip tags
-------------------------------------------------------------------------------
def('tag', {
    label = 'Skip Tag', cost = 1,
    colour = function() return G.C.GREEN end,
    blurb = 'The tag offered for skipping a blind',
    defaults = function() return { keys = {}, ante = 1, blind = 'small' } end,
    describe = function(f)
        local which = ({ small = 'Small Blind', big = 'Big Blind', either = 'either blind', both = 'both blinds' })[f.blind] or 'Small Blind'
        return ('Ante %d %s: %s'):format(f.ante, which, names(f.keys))
    end,
    problem = function(f) if count_set(f.keys) == 0 then return 'Pick at least one tag' end end,
    test = function(f, ctx)
        local s, b = ctx:tags(f.ante)
        if f.blind == 'small' then return f.keys[s] end
        if f.blind == 'big' then return f.keys[b] end
        if f.blind == 'both' then return f.keys[s] and f.keys[b] end
        return f.keys[s] or f.keys[b]
    end,
    editor = function(f, refresh)
        local node = UI.picker({
            id = 'tag', kind = 'tag', items = center_items(G.P_CENTER_POOLS.Tag), cols = 12, rows = 3, size = 0.62,
            set = f.keys, width = EDW, height = 3.0, colour = G.C.GREEN, on_change = refresh,
        })
        return {
            controls({
                field('Ante', ante_ctrl(f, 'ante', refresh), 0.7),
                field('Blind', UI.radio({
                    { key = 'small', label = 'Small' }, { key = 'big', label = 'Big' },
                    { key = 'either', label = 'Either' }, { key = 'both', label = 'Both' },
                }, f, 'blind', { per_row = 4, w = 1.25, h = 0.4, colour = G.C.GREEN, on_change = refresh }), 0.8),
            }),
            hint('Pick one or more tags - the seed passes when the blind offers any of them. Hover a tag for its effect.'),
            UI.row({ node }),
        }
    end,
})

-------------------------------------------------------------------------------
-- Boss blinds
-------------------------------------------------------------------------------
local function boss_items()
    local out = {}
    for _, v in ipairs(SMODS.collection_pool and SMODS.collection_pool(G.P_BLINDS) or {}) do
        if v.boss then out[#out + 1] = { key = v.key } end
    end
    return out
end

def('boss', {
    label = 'Boss Blind', cost = 4,
    colour = function() return G.C.BOOSTER end,
    blurb = 'Which bosses show up, or which never do',
    defaults = function() return { keys = {}, ante = 1, mode = 'is' } end,
    describe = function(f)
        if f.mode == 'avoid' then
            return ('No %s in antes 1-%d'):format(names(f.keys, 2):gsub(' or ', ' / '), f.ante)
        end
        return ('Ante %d boss: %s'):format(f.ante, names(f.keys))
    end,
    problem = function(f) if count_set(f.keys) == 0 then return 'Pick at least one boss' end end,
    test = function(f, ctx)
        local b = ctx:blinds(f.ante)
        if f.mode == 'avoid' then
            for a = 1, f.ante do
                if b[a] and f.keys[b[a].boss] then return false end
            end
            return true
        end
        return b[f.ante] and f.keys[b[f.ante].boss]
    end,
    editor = function(f, refresh)
        local node = UI.picker({
            id = 'boss', kind = 'blind', items = boss_items(), cols = 13, rows = 3, size = 0.62,
            set = f.keys, width = EDW, height = 2.75, colour = G.C.BOOSTER, on_change = refresh,
        })
        return {
            controls({
                field('Rule', UI.radio({
                    { key = 'is', label = 'Boss is one of these' }, { key = 'avoid', label = 'Avoid all of these' },
                }, f, 'mode', { per_row = 2, w = 2.7, h = 0.4, colour = G.C.BOOSTER, on_change = function() refresh(true) end }), 0.75),
                field(f.mode == 'avoid' and 'Through' or 'Ante', ante_ctrl(f, 'ante', refresh, 1, 16), 0.9),
            }),
            hint(f.mode == 'avoid' and 'No selected boss may appear in any ante up to the one shown (assumes no boss rerolls).'
                or 'The boss for that ante must be one of the selected (assumes no boss rerolls). Ante 8 is the finale.'),
            UI.row({ node }),
        }
    end,
})

-------------------------------------------------------------------------------
-- Vouchers
-------------------------------------------------------------------------------
def('voucher', {
    label = 'Voucher', cost = 3,
    colour = function() return G.C.SECONDARY_SET.Voucher end,
    blurb = 'The voucher in an ante\'s shop',
    defaults = function() return { keys = {}, ante = 1, buy = true } end,
    describe = function(f)
        local s = ('Ante %d voucher: %s'):format(f.ante, names(f.keys))
        if f.ante > 1 then s = s .. (f.buy and ' (buying earlier ones)' or ' (buying none)') end
        return s
    end,
    problem = function(f) if count_set(f.keys) == 0 then return 'Pick at least one voucher' end end,
    test = function(f, ctx)
        local v = ctx:vouchers(f.ante, f.buy)[f.ante] or {}
        for _, k in ipairs(v) do if f.keys[k] then return true end end
        return false
    end,
    editor = function(f, refresh)
        local node = UI.picker({
            id = 'voucher', kind = 'card', items = center_items(G.P_CENTER_POOLS.Voucher), cols = 10, rows = 2, scale = 0.5,
            set = f.keys, width = EDW, height = 3.15, colour = G.C.SECONDARY_SET.Voucher, on_change = refresh,
        })
        return {
            controls({
                field('Ante', ante_ctrl(f, 'ante', refresh), 0.7),
                field('Earlier vouchers', UI.switch({ get = function() return f.buy end, set = function(v) f.buy = v; refresh() end }), 1.9),
            }),
            hint('Later antes depend on what you redeem. With the switch on, every earlier voucher counts as bought.'),
            UI.row({ node }),
        }
    end,
})

-------------------------------------------------------------------------------
-- The Soul / Black Hole
-------------------------------------------------------------------------------
local SOUL_PACKS = {
    c_soul = {
        { key = 'p_arcana_mega_1', label = 'Mega Arcana (Charm Tag)' },
        { key = 'p_arcana_jumbo_1', label = 'Jumbo Arcana' },
        { key = 'p_arcana_normal_1', label = 'Arcana' },
        { key = 'p_spectral_normal_1', label = 'Spectral (Ethereal Tag)' },
        { key = 'p_spectral_jumbo_1', label = 'Jumbo Spectral' },
        { key = 'p_spectral_mega_1', label = 'Mega Spectral' },
    },
    c_black_hole = {
        { key = 'p_celestial_mega_1', label = 'Mega Celestial (Meteor Tag)' },
        { key = 'p_celestial_jumbo_1', label = 'Jumbo Celestial' },
        { key = 'p_celestial_normal_1', label = 'Celestial' },
        { key = 'p_spectral_normal_1', label = 'Spectral (Ethereal Tag)' },
        { key = 'p_spectral_jumbo_1', label = 'Jumbo Spectral' },
        { key = 'p_spectral_mega_1', label = 'Mega Spectral' },
    },
}
local KIND_TYPE = { Arcana = 'Tarot', Spectral = 'Spectral', Celestial = 'Planet' }

local function pack_size(key)
    local c = G.P_CENTERS[key]
    if not c then return 1 end
    return math.max(1, ((c.config and c.config.extra) or 1) + ((G.GAME and G.GAME.modifiers and G.GAME.modifiers.booster_size_mod) or 0))
end

local function soul_pack_label(key)
    for _, list in pairs(SOUL_PACKS) do
        for _, p in ipairs(list) do if p.key == key then return p.label end end
    end
    return FS.name_of(key)
end

def('soul', {
    label = 'The Soul', cost = 2,
    colour = function() return G.C.SECONDARY_SET.Spectral end,
    blurb = 'The Soul or Black Hole inside packs',
    defaults = function() return { target = 'c_soul', pack = 'p_arcana_mega_1', count = 1, ante = 1 } end,
    describe = function(f)
        local what = FS.name_of(f.target)
        local pack = soul_pack_label(f.pack):gsub('%s*%b()', '')
        if f.count > 1 then
            return ('%dx %s across your first %d %s packs - Ante %d'):format(f.count, what, f.count, pack, f.ante)
        end
        return ('%s in your first %s pack - Ante %d'):format(what, pack, f.ante)
    end,
    test = function(f, ctx)
        local c = G.P_CENTERS[f.pack]
        local typ = c and KIND_TYPE[c.kind] or 'Tarot'
        local per = pack_size(f.pack)
        local pos = ctx:souls(typ, f.ante, per * f.count, per)
        local hits = 0
        for i = 1, #pos do if pos[i] == f.target then hits = hits + 1 end end
        return hits >= f.count
    end,
    editor = function(f, refresh)
        local packs = SOUL_PACKS[f.target] or SOUL_PACKS.c_soul
        local valid = false
        for _, p in ipairs(packs) do if p.key == f.pack then valid = true end end
        if not valid then f.pack = packs[1].key end
        local preview = UI.card_strip({ { key = f.target } }, { scale = 0.7 })
        return {
            controls({
                field('Card', UI.radio({
                    { key = 'c_soul', label = 'The Soul' }, { key = 'c_black_hole', label = 'Black Hole' },
                }, f, 'target', { per_row = 2, w = 1.9, h = 0.4, colour = G.C.SECONDARY_SET.Spectral, on_change = function() refresh(true) end }), 0.7),
                field('How many', F.num_ctrl(f, 'count', 1, 4, nil, refresh), 1.25),
                field('Ante', ante_ctrl(f, 'ante', refresh), 0.7),
            }),
            UI.row({
                UI.col({
                    hint('Which pack does it have to be in?'),
                    UI.row({ UI.radio(packs, f, 'pack', { per_row = 2, w = 3.6, h = 0.44, scale = 0.3, colour = G.C.SECONDARY_SET.Spectral, on_change = refresh }) }),
                    hint('Counts the first pack of that kind you open in the ante - from a tag or the shop.'),
                    hint('With 2 or more, each extra one must show up in the next pack after it.'),
                }, { align = 'tl' }),
                UI.spacer(0.4),
                preview,
            }, { align = 'cl' }),
        }
    end,
})

-------------------------------------------------------------------------------
-- Legendary from The Soul
-------------------------------------------------------------------------------
def('legendary', {
    label = 'Legendary', cost = 2,
    colour = function() return G.C.RARITY and G.C.RARITY[4] or G.C.PURPLE end,
    blurb = 'Which legendary joker The Soul creates',
    defaults = function() return { keys = {}, edition = 'any', ante = 1 } end,
    describe = function(f)
        local s = 'The Soul gives ' .. (count_set(f.keys) == 0 and 'any legendary' or names(f.keys))
        local e = edition_label(f.edition)
        if e then s = s .. ' (' .. e .. ')' end
        if f.ante > 1 then s = s .. (' - used in Ante %d'):format(f.ante) end
        return s
    end,
    problem = function(f)
        if count_set(f.keys) == 0 and (f.edition == 'any' or not f.edition) then return 'Pick a legendary or an edition' end
    end,
    test = function(f, ctx)
        local c = ctx:legendary(f.ante)
        if count_set(f.keys) > 0 and not f.keys[c.key] then return false end
        return edition_ok(f.edition, c.edition)
    end,
    editor = function(f, refresh)
        local items = center_items(G.P_JOKER_RARITY_POOLS and G.P_JOKER_RARITY_POOLS[4] or {})
        local node = UI.picker({
            id = 'legendary', kind = 'card', items = items, cols = 9, rows = 1, scale = 0.58,
            set = f.keys, width = EDW, height = 1.75, colour = G.C.PURPLE, on_change = refresh,
        })
        return {
            controls({
                field('Used in', ante_ctrl(f, 'ante', refresh), 0.9),
            }),
            hint('Edition'),
            UI.row({ UI.radio(F.edition_items(true), f, 'edition', { per_row = 8, w = 1.32, h = 0.38, scale = 0.27, max_rows = 2, id = 'leg_ed', on_change = refresh }) }, { align = 'cl' }),
            hint('Leave the cards unselected to accept any legendary. Edition depends on the ante you use The Soul in.'),
            UI.row({ node }),
        }
    end,
})

-------------------------------------------------------------------------------
-- Shop cards
-------------------------------------------------------------------------------
local function shop_categories()
    local cats = { { key = 'Joker', label = 'Jokers', colour = G.C.RED } }
    for _, k in ipairs(SMODS.ConsumableType.obj_buffer or {}) do
        if G.P_CENTER_POOLS[k] then
            cats[#cats + 1] = { key = k, label = FS.loc_or(k, 'b_' .. k:lower() .. '_cards'), colour = G.C.SECONDARY_SET[k] or G.C.PURPLE }
        end
    end
    return cats
end

local function rarity_options()
    local list = { { key = 'any', label = 'Any rarity' } }
    local seen = {}
    for _, c in ipairs(G.P_CENTER_POOLS.Joker or {}) do
        local r = c.rarity
        if r and r ~= 4 and r ~= 'Legendary' and not seen[r] then
            seen[r] = true
            local label = type(r) == 'number' and FS.loc_or(tostring(r), ({ 'k_common', 'k_uncommon', 'k_rare' })[r] or '') or FS.loc_or(tostring(r), 'k_' .. tostring(r):lower())
            list[#list + 1] = { key = r, label = label }
        end
    end
    return list
end

def('shop', {
    label = 'Shop Card', cost = 8,
    colour = function() return G.C.RED end,
    blurb = 'Jokers or cards the shop will offer',
    defaults = function() return { keys = {}, ante = 1, depth = 2, count = 1, edition = 'any', rarity = 'any', cat = 'Joker', q = '' } end,
    describe = function(f)
        local what
        local e = edition_label(f.edition)
        if count_set(f.keys) > 0 then
            what = names(f.keys)
            if e then what = what .. ' (' .. e .. ')' end
        else
            local r = f.rarity ~= 'any' and (type(f.rarity) == 'number' and ({ 'Common', 'Uncommon', 'Rare' })[f.rarity] or tostring(f.rarity)) or nil
            local words = {}
            if e and f.edition ~= 'none' then words[#words + 1] = e == 'any edition' and 'editioned' or e end
            if r then words[#words + 1] = r end
            words[#words + 1] = 'joker'
            what = 'a ' .. table.concat(words, ' ')
            if f.edition == 'none' then what = what .. ' without an edition' end
        end
        local n = f.count > 1 and (f.count .. 'x ') or ''
        return ('%s%s in the first %d shop cards of Ante %d'):format(n, what, f.depth, f.ante)
    end,
    problem = function(f)
        if count_set(f.keys) == 0 and f.rarity == 'any' and (f.edition == 'any' or not f.edition) then
            return 'Pick cards, a rarity or an edition'
        end
    end,
    test = function(f, ctx)
        local cards = ctx:shop(f.ante, f.depth)
        local need, hits = f.count, 0
        local any_keys = next(f.keys) ~= nil
        for i = 1, math.min(#cards, f.depth) do
            local c = cards[i]
            local ok
            if any_keys then
                ok = c.key and f.keys[c.key]
            else
                ok = c.set == 'Joker'
                if ok and f.rarity ~= 'any' then
                    local center = G.P_CENTERS[c.key]
                    ok = center and center.rarity == f.rarity
                end
            end
            if ok and edition_ok(f.edition, c.edition) then
                hits = hits + 1
                if hits >= need then return true end
            end
        end
        return false
    end,
    editor = function(f, refresh)
        local cats = shop_categories()
        local cat_ok = false
        for _, c in ipairs(cats) do if c.key == f.cat then cat_ok = true end end
        if not cat_ok then f.cat = 'Joker' end
        local pool = G.P_CENTER_POOLS[f.cat] or {}
        local items = center_items(pool, function(c) return f.cat ~= 'Joker' or (c.rarity ~= 4 and c.rarity ~= 'Legendary') end)
        f.search = f.search or { q = '' }
        local node, re = UI.picker({
            id = 'shop_' .. f.cat, kind = 'card', items = items, cols = 10, rows = 2, scale = 0.5,
            set = f.keys, width = EDW, height = 3.15, colour = G.C.RED, search = f.search, on_change = refresh,
        })
        return {
            controls({
                field('Ante', ante_ctrl(f, 'ante', refresh), 0.7),
                field('Look through', F.num_ctrl(f, 'depth', 1, 60, function(v) return v .. ' cards' end, refresh), 1.35),
                field('Need', F.num_ctrl(f, 'count', 1, 10, function(v) return v .. 'x' end, refresh), 0.6),
            }),
            controls({
                UI.radio(cats, f, 'cat', { per_row = 5, w = 1.4, h = 0.38, scale = 0.27, max_rows = 1, id = 'shop_cat', on_change = function() refresh(true) end }),
                UI.input({ tbl = f.search, field = 'q', w = 2.4, prompt = 'Search...', colour = G.C.RED, on_change = function() re() end }),
            }),
            controls({
                UI.cycler({ options = rarity_options(), w = 1.9, colour = G.C.RED, get = function() return f.rarity end, set = function(k) f.rarity = k; refresh() end }),
                UI.radio(F.edition_items(true), f, 'edition', { per_row = 7, w = 1.05, h = 0.38, scale = 0.25, max_rows = 1, id = 'shop_ed', on_change = refresh }),
            }),
            UI.row({ node }),
        }
    end,
})

-------------------------------------------------------------------------------
-- Shop booster packs
-------------------------------------------------------------------------------
def('shop_pack', {
    label = 'Shop Pack', cost = 3,
    colour = function() return G.C.BOOSTER end,
    blurb = 'Booster packs the shop will offer',
    defaults = function() return { keys = {}, ante = 1, depth = 2, count = 1 } end,
    describe = function(f)
        local n = f.count > 1 and (f.count .. 'x ') or ''
        return ('%s%s in the first %d shop packs of Ante %d'):format(n, names(f.keys), f.depth, f.ante)
    end,
    problem = function(f) if count_set(f.keys) == 0 then return 'Pick at least one pack' end end,
    test = function(f, ctx)
        local g = F.booster_groups()
        local packs = ctx:shop_packs(f.ante, f.depth)
        local hits = 0
        for i = 1, math.min(#packs, f.depth) do
            local gid = packs[i] and g.by_key[packs[i]]
            local rep = gid and g.by_id[gid] and g.by_id[gid].key
            if rep and f.keys[rep] then
                hits = hits + 1
                if hits >= f.count then return true end
            end
        end
        return false
    end,
    editor = function(f, refresh)
        local items = {}
        for _, g in ipairs(F.booster_groups().list) do items[#items + 1] = { key = g.key } end
        local node = UI.picker({
            id = 'shop_pack', kind = 'card', items = items, cols = 9, rows = 2, scale = 0.44, booster = true,
            set = f.keys, width = EDW, height = 3.6, colour = G.C.BOOSTER, on_change = refresh,
        })
        return {
            controls({
                field('Ante', ante_ctrl(f, 'ante', refresh), 0.7),
                field('Look through', F.num_ctrl(f, 'depth', 1, 20, function(v) return v .. ' packs' end, refresh), 1.35),
                field('Need', F.num_ctrl(f, 'count', 1, 6, function(v) return v .. 'x' end, refresh), 0.6),
            }),
            hint('Each shop offers 2 packs; the very first one is always a Buffoon Pack. Pick every size you accept.'),
            UI.row({ node }),
        }
    end,
})

-------------------------------------------------------------------------------
-- Pack contents
-------------------------------------------------------------------------------
local KIND_SETS = { Arcana = { 'Tarot' }, Celestial = { 'Planet' }, Spectral = { 'Spectral' }, Buffoon = { 'Joker' } }

local function pack_kinds()
    local seen, out = {}, {}
    for _, g in ipairs(F.booster_groups().list) do
        local c = G.P_CENTERS[g.key]
        if g.kind and not seen[g.kind] and c and type(c.create_card) == 'function' and g.kind ~= 'Standard' then
            seen[g.kind] = true
            out[#out + 1] = { key = g.kind, label = FS.loc_or(g.kind, 'k_' .. tostring(g.kind):lower() .. '_pack'):gsub(' Pack$', '') }
        end
    end
    return out
end

local function group_for(kind, size)
    for _, g in ipairs(F.booster_groups().list) do
        if g.kind == kind and g.size == size then return g end
    end
    for _, g in ipairs(F.booster_groups().list) do
        if g.kind == kind then return g end
    end
end

local function content_items(kind)
    local sets = KIND_SETS[kind]
    if not sets then
        -- modded packs: offer the consumable type of the same name if there is one
        for _, ct in ipairs(SMODS.ConsumableType.obj_buffer or {}) do
            if tostring(kind):lower():find(ct:lower(), 1, true) or ct:lower():find(tostring(kind):lower(), 1, true) then sets = { ct } end
        end
    end
    local out = {}
    for _, s in ipairs(sets or {}) do
        for _, c in ipairs(G.P_CENTER_POOLS[s] or {}) do
            if not hidden(c) and (s ~= 'Joker' or (c.rarity ~= 4 and c.rarity ~= 'Legendary')) then out[#out + 1] = { key = c.key } end
        end
    end
    if kind == 'Arcana' and G.P_CENTERS.c_soul then table.insert(out, 1, { key = 'c_soul' }) end
    if kind == 'Celestial' and G.P_CENTERS.c_black_hole then table.insert(out, 1, { key = 'c_black_hole' }) end
    return out
end

def('pack', {
    label = 'Pack Contents', cost = 6,
    colour = function() return G.C.SECONDARY_SET.Tarot end,
    blurb = 'Cards inside the first pack you open',
    defaults = function() return { kind = 'Buffoon', size = 'Normal', ante = 1, keys = {}, mode = 'any', edition = 'any' } end,
    describe = function(f)
        local g = group_for(f.kind, f.size)
        local pack = g and FS.name_of(g.key) or (f.kind .. ' Pack')
        local what = count_set(f.keys) == 0 and 'any card' or (f.mode == 'all' and count_set(f.keys) > 1 and ('all of ' .. names(f.keys, 3):gsub(' or ', ' and ')) or names(f.keys))
        local e = edition_label(f.edition)
        if e then what = what .. ' (' .. e .. ')' end
        return ('First %s in Ante %d has %s'):format(pack, f.ante, what)
    end,
    problem = function(f)
        if not group_for(f.kind, f.size) then return 'That pack does not exist' end
        if count_set(f.keys) == 0 and (f.edition == 'any' or not f.edition) then return 'Pick cards or an edition' end
    end,
    test = function(f, ctx)
        local g = group_for(f.kind, f.size)
        if not g then return false end
        local cards = ctx:pack(g.key, f.ante)
        local any_keys = next(f.keys) ~= nil
        if f.mode == 'all' and any_keys then
            for k in pairs(f.keys) do
                local found = false
                for _, c in ipairs(cards) do
                    if c.key == k and edition_ok(f.edition, c.edition) then found = true break end
                end
                if not found then return false end
            end
            return true
        end
        for _, c in ipairs(cards) do
            if (not any_keys or f.keys[c.key]) and edition_ok(f.edition, c.edition) then return true end
        end
        return false
    end,
    editor = function(f, refresh)
        local kinds = pack_kinds()
        local ok_kind = false
        for _, k in ipairs(kinds) do if k.key == f.kind then ok_kind = true end end
        if not ok_kind and kinds[1] then f.kind = kinds[1].key end
        local g = group_for(f.kind, f.size)
        if g then f.size = g.size end
        local sizes = {}
        for _, s in ipairs({ 'Normal', 'Jumbo', 'Mega' }) do
            for _, gg in ipairs(F.booster_groups().list) do
                if gg.kind == f.kind and gg.size == s then sizes[#sizes + 1] = { key = s, label = s } break end
            end
        end
        f.search = f.search or { q = '' }
        local node, re = UI.picker({
            id = 'pack_' .. tostring(f.kind), kind = 'card', items = content_items(f.kind), cols = 10, rows = 2, scale = 0.5,
            set = f.keys, width = EDW, height = 3.15, colour = G.C.SECONDARY_SET.Tarot, search = f.search, on_change = refresh,
        })
        local size_txt = g and ('%d cards'):format(pack_size(g.key)) or ''
        return {
            controls({
                UI.radio(kinds, f, 'kind', { per_row = 5, w = 1.3, h = 0.38, scale = 0.28, max_rows = 1, id = 'pack_kind', colour = G.C.SECONDARY_SET.Tarot,
                    on_change = function() for k in pairs(f.keys) do f.keys[k] = nil end refresh(true) end }),
                UI.radio(sizes, f, 'size', { per_row = 3, w = 1.0, h = 0.38, scale = 0.28, colour = G.C.SECONDARY_SET.Tarot, on_change = function() refresh(true) end }),
                UI.text(size_txt, 0.26, UI.muted()),
            }),
            controls({
                field('Ante', ante_ctrl(f, 'ante', refresh), 0.7),
                field('Match', UI.radio({ { key = 'any', label = 'Any of them' }, { key = 'all', label = 'All of them' } }, f, 'mode',
                    { per_row = 2, w = 1.7, h = 0.38, colour = G.C.SECONDARY_SET.Tarot, on_change = refresh }), 0.75),
                UI.input({ tbl = f.search, field = 'q', w = 2.4, prompt = 'Search...', colour = G.C.SECONDARY_SET.Tarot, on_change = function() re() end }),
            }),
            controls({
                field('Edition', UI.radio(F.edition_items(true), f, 'edition', { per_row = 8, w = 1.15, h = 0.38, scale = 0.25, max_rows = 1, id = 'pack_ed', on_change = refresh }), 0.75),
            }),
            hint('The first pack of this kind you open in that ante - e.g. Charm Tag = Mega Arcana, the first shop\'s Buffoon Pack = Buffoon.'),
            UI.row({ node }),
        }
    end,
})

-------------------------------------------------------------------------------
-- Erratic Deck composition
-------------------------------------------------------------------------------
def('erratic', {
    label = 'Erratic Deck', cost = 3,
    colour = function() return G.C.ORANGE end,
    blurb = 'What the randomised starting deck contains',
    defaults = function() return { what = 'suit', suit = 'Hearts', rank = 'Ace', min = 20 } end,
    describe = function(f)
        local target = f.what == 'suit' and FS.loc_or(f.suit, f.suit, 'suits_plural')
            or f.what == 'rank' and (FS.loc_or(f.rank, f.rank, 'ranks') .. 's')
            or 'face cards'
        return ('Erratic Deck: at least %d %s'):format(f.min, target)
    end,
    problem = function(f)
        if FS.in_run() and not O.is_erratic() then return 'Only works with the Erratic Deck' end
    end,
    test = function(f, ctx)
        local cards = ctx:erratic()
        local n = 0
        for _, k in ipairs(cards) do
            local p = G.P_CARDS[k]
            if p then
                local hit
                if f.what == 'suit' then hit = p.suit == f.suit
                elseif f.what == 'rank' then hit = p.value == f.rank
                else local r = SMODS.Ranks[p.value]; hit = r and r.face end
                if hit then n = n + 1 end
            end
        end
        return n >= f.min
    end,
    editor = function(f, refresh)
        local suits, ranks = {}, {}
        for _, k in ipairs(SMODS.Suit.obj_buffer) do
            suits[#suits + 1] = { key = k, label = FS.loc_or(k, k, 'suits_plural'), colour = G.C.SUITS and G.C.SUITS[k] or nil }
        end
        for _, k in ipairs(SMODS.Rank.obj_buffer) do
            local r = SMODS.Ranks[k]
            ranks[#ranks + 1] = { key = k, label = r and r.shorthand or k }
        end
        local rows = {
            controls({
                field('Count', UI.radio({ { key = 'suit', label = 'A suit' }, { key = 'rank', label = 'A rank' }, { key = 'face', label = 'Face cards' } },
                    f, 'what', { per_row = 3, w = 1.6, h = 0.4, colour = G.C.ORANGE, on_change = function() refresh(true) end }), 0.8),
                field('At least', F.num_ctrl(f, 'min', 1, 52, nil, refresh), 1.0),
            }),
        }
        if f.what == 'suit' then
            rows[#rows + 1] = UI.row({ UI.radio(suits, f, 'suit', { per_row = 6, w = 1.7, h = 0.42, max_rows = 2, id = 'err_suit', on_change = refresh }) }, { align = 'cl' })
        elseif f.what == 'rank' then
            rows[#rows + 1] = UI.row({ UI.radio(ranks, f, 'rank', { per_row = 14, w = 0.74, h = 0.42, max_rows = 2, id = 'err_rank', colour = G.C.ORANGE, on_change = refresh }) }, { align = 'cl' })
        end
        rows[#rows + 1] = hint('Erratic swaps every starting card for a random one. A normal deck has 13 per suit, 4 per rank.')
        if FS.in_run() and not O.is_erratic() then
            rows[#rows + 1] = UI.row({ UI.text('Your current run is not using the Erratic Deck - start one first.', 0.3, G.C.RED) }, { align = 'cl', padding = 0.06 })
        end
        return rows
    end,
})

-------------------------------------------------------------------------------
-- Evaluation context (one per search; reset for every candidate seed)
-------------------------------------------------------------------------------
local Ctx = {}
Ctx.__index = Ctx

function F.make_ctx(plan)
    return setmetatable({ plan = plan }, Ctx)
end

function Ctx:reset()
    self._tags, self._blinds, self._blinds_to, self._v = nil, nil, 0, nil
    self._shop, self._packs, self._pack, self._souls, self._leg, self._erratic = nil, nil, nil, nil, nil, nil
end

function Ctx:tags(a)
    self._tags = self._tags or {}
    local c = self._tags[a]
    if not c then
        local s, b = O.tags(a)
        c = { s, b }
        self._tags[a] = c
    end
    return c[1], c[2]
end

function Ctx:blinds(to)
    to = math.max(to, self.plan.blinds_to or 1)
    if not self._blinds or self._blinds_to < to then
        self._blinds = O.blinds(1, to)
        self._blinds_to = to
    end
    return self._blinds
end

function Ctx:vouchers(to, buy)
    self._v = self._v or {}
    local key = buy and 'b' or 'n'
    local c = self._v[key]
    local need = math.max(to, (self.plan.vouchers_to or {})[key] or 1)
    if not c or c.to < to then
        c = { to = need, list = O.vouchers(1, need, buy) }
        self._v[key] = c
    end
    return c.list
end

function Ctx:shop(a, n)
    self._shop = self._shop or {}
    n = math.max(n, ((self.plan.shop or {})[a]) or 0)
    local c = self._shop[a]
    if not c or #c < n then
        c = O.shop(a, n)
        self._shop[a] = c
    end
    return c
end

function Ctx:shop_packs(a, n)
    self._packs = self._packs or {}
    n = math.max(n, ((self.plan.packs or {})[a]) or 0)
    local c = self._packs[a]
    if not c or #c < n then
        c = O.shop_packs(a, n)
        self._packs[a] = c
    end
    return c
end

function Ctx:pack(key, a)
    self._pack = self._pack or {}
    local id = key .. '|' .. a
    local c = self._pack[id]
    if not c then
        c = O.pack(key, a)
        self._pack[id] = c
    end
    return c
end

function Ctx:souls(typ, a, n, per)
    self._souls = self._souls or {}
    local id = typ .. '|' .. a .. '|' .. per
    local c = self._souls[id]
    if not c or #c < n then
        c = O.souls(typ, a, n, per)
        self._souls[id] = c
    end
    return c
end

function Ctx:legendary(a)
    self._leg = self._leg or {}
    local c = self._leg[a]
    if not c then
        c = O.legendary(a)
        self._leg[a] = c
    end
    return c
end

function Ctx:erratic()
    if not self._erratic then self._erratic = O.erratic(self.plan.erratic_n or 52) end
    return self._erratic
end

--- Work out how far each predictor needs to look so it runs once per seed.
function F.plan(list, extra)
    local plan = { shop = {}, packs = {}, vouchers_to = {}, blinds_to = 1, erratic_n = extra and extra.erratic_n or 52 }
    for _, f in ipairs(list) do
        if f.type == 'shop' then plan.shop[f.ante] = math.max(plan.shop[f.ante] or 0, f.depth) end
        if f.type == 'shop_pack' then plan.packs[f.ante] = math.max(plan.packs[f.ante] or 0, f.depth) end
        if f.type == 'boss' then plan.blinds_to = math.max(plan.blinds_to, f.ante) end
        if f.type == 'voucher' then
            local k = f.buy and 'b' or 'n'
            plan.vouchers_to[k] = math.max(plan.vouchers_to[k] or 1, f.ante)
        end
    end
    return plan
end

--- Active, valid filters, cheapest first (so most seeds are rejected early).
function F.active(list)
    local out = {}
    for i, f in ipairs(list or {}) do
        if f.on ~= false and F.TYPES[f.type] and not F.problem(f) then
            out[#out + 1] = f
            f._order = i
        end
    end
    table.sort(out, function(a, b)
        local ca, cb = F.TYPES[a.type].cost or 5, F.TYPES[b.type].cost or 5
        if ca ~= cb then return ca < cb end
        return a._order < b._order
    end)
    return out
end

--- Test one candidate (inside an oracle session with the seed already set).
function F.test(list, ctx, stats)
    ctx:reset()
    for i, f in ipairs(list) do
        local st = stats and stats[i]
        if st then st.evals = st.evals + 1 end
        if not F.TYPES[f.type].test(f, ctx) then return false end
        if st then st.passes = st.passes + 1 end
    end
    return true
end

-------------------------------------------------------------------------------
-- Presets
-------------------------------------------------------------------------------
F.PRESETS = {
    { name = 'Charm Tag + The Soul', sub = 'the classic Brainstorm search', filters = {
        { type = 'tag', keys = { tag_charm = true }, ante = 1, blind = 'small' },
        { type = 'soul', target = 'c_soul', pack = 'p_arcana_mega_1', count = 1, ante = 1 },
    } },
    { name = 'Perkeo start', sub = 'Charm Tag, The Soul, Perkeo', filters = {
        { type = 'tag', keys = { tag_charm = true }, ante = 1, blind = 'small' },
        { type = 'soul', target = 'c_soul', pack = 'p_arcana_mega_1', count = 1, ante = 1 },
        { type = 'legendary', keys = { j_perkeo = true }, edition = 'any', ante = 1 },
    } },
    { name = 'Negative legendary', sub = 'Charm Tag, The Soul, Negative', filters = {
        { type = 'tag', keys = { tag_charm = true }, ante = 1, blind = 'small' },
        { type = 'soul', target = 'c_soul', pack = 'p_arcana_mega_1', count = 1, ante = 1 },
        { type = 'legendary', keys = {}, edition = 'e_negative', ante = 1 },
    } },
    { name = 'Double Charm', sub = 'Double Tag into Charm Tag', filters = {
        { type = 'tag', keys = { tag_double = true }, ante = 1, blind = 'small' },
        { type = 'tag', keys = { tag_charm = true }, ante = 1, blind = 'big' },
    } },
    { name = 'Negative first shop', sub = 'a Negative joker right away', filters = {
        { type = 'shop', keys = {}, ante = 1, depth = 2, count = 1, edition = 'e_negative', rarity = 'any', cat = 'Joker' },
    } },
    { name = 'Blueprint + Brainstorm', sub = 'both in Ante 1 shop rerolls', filters = {
        { type = 'shop', keys = { j_blueprint = true }, ante = 1, depth = 10, count = 1, edition = 'any', rarity = 'any', cat = 'Joker' },
        { type = 'shop', keys = { j_brainstorm = true }, ante = 1, depth = 10, count = 1, edition = 'any', rarity = 'any', cat = 'Joker' },
    } },
    { name = 'Telescope to Observatory', sub = 'vouchers in Ante 1 and 2', filters = {
        { type = 'voucher', keys = { v_telescope = true }, ante = 1, buy = true },
        { type = 'voucher', keys = { v_observatory = true }, ante = 2, buy = true },
    } },
    { name = 'Spectral pack early', sub = 'in the first shop', filters = {
        { type = 'shop_pack', keys = { p_spectral_normal_1 = true, p_spectral_jumbo_1 = true, p_spectral_mega_1 = true }, ante = 1, depth = 2, count = 1 },
    } },
}

--- Fresh filter instances from a preset (unknown keys from missing mods are dropped).
function F.from_preset(p)
    local out = {}
    for _, src in ipairs(p.filters) do
        local f = F.new(src.type)
        for k, v in pairs(FS.copy(src)) do f[k] = v end
        if type(f.keys) == 'table' then
            for k in pairs(f.keys) do
                if not (G.P_CENTERS[k] or G.P_TAGS[k] or G.P_BLINDS[k]) then f.keys[k] = nil end
            end
        end
        f.on = true
        out[#out + 1] = f
    end
    return out
end

--- Short summary of a filter list, for history entries and preset names.
function F.summary(list)
    local parts = {}
    for _, f in ipairs(list or {}) do
        if f.on ~= false then parts[#parts + 1] = F.describe(f) end
    end
    return table.concat(parts, ' + ')
end
