--- The oracle: predicts what a seed (or the current run) will produce.
---
--- Balatro's randomness is a set of independent streams keyed by name ("Tag1", "boss",
--- "soul_Tarot1", ...). Each stream's n-th value depends only on the seed, the key and n.
--- The oracle swaps in a sandboxed copy of the RNG table and calls the game's own generation
--- code (so mod hooks are honoured), then restores everything. Card creation itself is
--- emulated - only the parts that pick a key and an edition - so no real cards are made.
local FS = Foresight
local O = {}
FS.Oracle = O

local RARITY_NAMES = { 'Common', 'Uncommon', 'Rare', 'Legendary' }

O.cache = {}
O.arrays = setmetatable({}, { __mode = 'k' })
O.rarity_polls = 1
O.calibrated = false
O.active = false
O.marked = {}
O.marked_n = 0
O.vstamp = ''

-------------------------------------------------------------------------------
-- Session: memoised pools + a fast picker, installed only while predicting
-------------------------------------------------------------------------------
--- The pool the real function would build with this candidate's picks counted as used. Depending on
--- the installed mods, used entries are either dropped or kept as 'UNAVAILABLE' placeholders.
local function derive(pool, pkey, _type)
    if O.marked_n == 0 or _type == 'Tag' or _type == 'Edition' then return pool, pkey end
    local out, n, avail = {}, 0, 0
    for i = 1, #pool do
        local v = pool[i]
        if v ~= 'UNAVAILABLE' and O.marked[v] and not SMODS.showman(v) then
            if O.pad_unavailable then
                n = n + 1
                out[n] = 'UNAVAILABLE'
            end
        else
            n = n + 1
            out[n] = v
            if v ~= 'UNAVAILABLE' then avail = avail + 1 end
        end
    end
    if avail == 0 then return nil end
    O.arrays[out] = true
    return out, pkey
end

function O.memo_pool(_type, _rarity, _legendary, _append)
    local real = O._gcp
    local ante = G.GAME.round_resets.ante
    if _type == 'Joker' and not _legendary and _rarity == nil then
        -- replay the rarity roll(s) exactly as the real function does, then use a cached pool
        local r
        for _ = 1, O.rarity_polls do r = SMODS.poll_rarity('Joker', 'rarity' .. ante .. (_append or '')) end
        _rarity = RARITY_NAMES[r] or r
    elseif _type ~= 'Joker' and not _rarity and not _legendary and SMODS.ObjectTypes[_type] and SMODS.ObjectTypes[_type].rarities then
        local pool, pkey = real(_type, _rarity, _legendary, _append)
        local copy = {}
        for i = 1, #pool do copy[i] = pool[i] end
        O.arrays[copy] = true
        local p2, k2 = derive(copy, pkey, _type)
        if p2 then return p2, k2 end
        return copy, pkey
    end
    local ck = _type .. '|' .. tostring(_rarity) .. '|' .. (_legendary and 'L' or '') .. '|' .. (_append or '') .. '|' .. ante .. '|' .. O.vstamp
    local hit = O.cache[ck]
    if not hit then
        local pool, pkey = real(_type, _rarity, _legendary, _append)
        local copy = {}
        for i = 1, #pool do copy[i] = pool[i] end
        hit = { pool = copy, key = pkey }
        O.cache[ck] = hit
        O.arrays[copy] = true
    end
    local p2, k2 = derive(hit.pool, hit.key, _type)
    if p2 then return p2, k2 end
    -- everything was excluded: let the real function apply its fallback
    local ok, pool, pkey = pcall(real, _type, _rarity, _legendary, _append)
    if ok and pool then
        local copy = {}
        for i = 1, #pool do copy[i] = pool[i] end
        O.arrays[copy] = true
        return copy, pkey
    end
    return hit.pool, hit.key
end

--- Same result as pseudorandom_element for plain key arrays, without building and sorting a key list.
function O.fast_pe(_t, seed, args)
    if args == nil and O.arrays[_t] then
        if seed and type(seed) == 'string' then seed = pseudoseed(seed) end
        if seed then math.randomseed(seed) end
        local n = #_t
        if n == 0 then return nil, nil end
        local k = math.random(n)
        return _t[k], k
    end
    return O._pe(_t, seed, args)
end

function O.install()
    if O.active then return end
    O._gcp = get_current_pool
    O._pe = pseudorandom_element
    get_current_pool = O.memo_pool
    pseudorandom_element = O.fast_pe
    O.active = true
end

function O.uninstall()
    if not O.active then return end
    get_current_pool = O._gcp
    pseudorandom_element = O._pe
    O.active = false
end

--- Count how many rarity rolls the installed get_current_pool makes (mods can change this).
function O.calibrate()
    if O.calibrated or not G.GAME then return end
    local GG = G.GAME
    local saved = GG.pseudorandom
    local probe = 'rarity' .. GG.round_resets.ante .. 'fsgtcal'
    local count = 0
    local ps = pseudoseed
    pseudoseed = function(k, p)
        if k == probe then count = count + 1 end
        return ps(k, p)
    end
    local paused = G.SETTINGS.paused
    G.SETTINGS.paused = false
    local ok = pcall(function()
        GG.pseudorandom = { seed = 'FSGTCAL1', hashed_seed = pseudohash('FSGTCAL1') }
        get_current_pool('Joker', nil, nil, 'fsgtcal')
    end)
    G.SETTINGS.paused = paused
    pseudoseed = ps
    GG.pseudorandom = saved
    O.rarity_polls = (ok and count >= 1) and count or 1

    -- Does the installed get_current_pool keep used cards as 'UNAVAILABLE' placeholders
    -- (stock Steamodded) or drop them (some mods patch that out)? Mark one card used and compare.
    O.pad_unavailable = true
    pcall(function()
        local function snapshot()
            local pool = get_current_pool('Tarot')
            local copy = {}
            for i = 1, #pool do copy[i] = pool[i] end
            return copy
        end
        local before = snapshot()
        local probe
        for _, v in ipairs(before) do
            if v ~= 'UNAVAILABLE' and not GG.used_jokers[v] then probe = v break end
        end
        if not probe then return end
        GG.used_jokers[probe] = true
        local ok2, after = pcall(snapshot)
        GG.used_jokers[probe] = nil
        if ok2 then O.pad_unavailable = #after == #before end
    end)
    O.calibrated = true
end

-------------------------------------------------------------------------------
-- Begin / finish: snapshot everything the predictors touch
-------------------------------------------------------------------------------
--- mode 'seed': predictions for fresh runs of arbitrary seeds (set each with O.set_seed).
--- mode 'live': predictions continuing the current run's RNG.
function O.begin(mode, opts)
    opts = opts or {}
    local GG = G.GAME
    O.calibrate()
    O.saved = {
        pr = GG.pseudorandom, ante = GG.round_resets.ante, fsb = GG.first_shop_buffoon,
        bu = GG.bosses_used, bc = GG.round_resets.blind_choices, bo = GG.round_resets.blind_order,
        uv = GG.used_vouchers, uj = GG.used_jokers, sv = G.shop_vouchers, paused = G.SETTINGS.paused,
    }
    -- pseudoseed hands out throwaway numbers while the game is paused (so menus can't disturb
    -- the run); predictions need the real streams, and they only ever touch the sandboxed copy
    G.SETTINGS.paused = false
    O.mode = mode
    if not opts.keep_cache then O.cache = {} end
    O.uj = {}
    for k, v in pairs(GG.used_jokers or {}) do O.uj[k] = v end
    if opts.unmark then
        for _, k in ipairs(opts.unmark) do O.uj[k] = nil end
    end
    GG.used_jokers = O.uj
    G.shop_vouchers = nil
    O.base = mode == 'live' and O.saved.pr or { seed = 'FSGTINIT', hashed_seed = pseudohash('FSGTINIT') }
    O.install()
end

function O.set_seed(seed)
    O.base = { seed = seed, hashed_seed = pseudohash(seed) }
end

function O.finish()
    O.uninstall()
    local s = O.saved
    if s and G.GAME then
        local GG = G.GAME
        GG.pseudorandom = s.pr
        GG.round_resets.ante = s.ante
        GG.first_shop_buffoon = s.fsb
        GG.bosses_used = s.bu
        GG.round_resets.blind_choices = s.bc
        GG.round_resets.blind_order = s.bo
        GG.used_vouchers = s.uv
        GG.used_jokers = s.uj
        G.shop_vouchers = s.sv
    end
    if s then G.SETTINGS.paused = s.paused end
    O.saved = nil
    O.mode = nil
    O.marked, O.marked_n, O.vstamp = {}, 0, ''
    -- leave unseeded math.random lively for code that relies on it
    math.randomseed(os.time() + (G.TIMERS and G.TIMERS.REAL or 0) * 1000)
end

--- Run fn inside a live session; always restores state. Returns ok, result.
function O.live(fn, opts)
    if not FS.in_run() then return false, 'not in a run' end
    O.begin('live', opts)
    local ok, res = xpcall(fn, debug.traceback)
    O.finish()
    if not ok then FS.err(res) end
    return ok, res
end

--- A pristine copy of the RNG for one prediction (predictions never contaminate each other).
function O.fresh(ante)
    local GG = G.GAME
    local t = {}
    for k, v in pairs(O.base) do t[k] = v end
    GG.pseudorandom = t
    GG.round_resets.ante = ante or (O.mode == 'seed' and 1) or O.saved.ante
    if O.mode == 'seed' then GG.first_shop_buffoon = nil else GG.first_shop_buffoon = O.saved.fsb end
    GG.used_vouchers = O.saved.uv
    O.vstamp = ''
    O.marked, O.marked_n = {}, 0
end

function O.used(key)
    return (O.uj[key] or O.marked[key]) and true or false
end

function O.mark(key)
    if not key then return end
    O.marked[key] = (O.marked[key] or 0) + 1
    O.marked_n = O.marked_n + 1
end

function O.unmark(key)
    local n = key and O.marked[key]
    if not n then return end
    O.marked[key] = (n > 1) and (n - 1) or nil
    O.marked_n = math.max(0, O.marked_n - 1)
end

--- Normalise whatever poll_edition returned to an edition key.
function O.edition_key(e)
    if e == nil or e == false then return nil end
    if type(e) == 'string' then return e end
    if type(e) == 'table' then
        if e.key then return e.key end
        for k, v in pairs(e) do
            if v == true and G.P_CENTERS['e_' .. k] then return 'e_' .. k end
        end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Card selection (mirrors SMODS.create_card + create_card up to the point a key is chosen)
-------------------------------------------------------------------------------
--- t: set, key, key_append, soulable, legendary, rarity, edition, seal, front, rank, suit,
---    enhancement, no_edition, fs_area ('shop'|'pack')
function O.card(t)
    local GG = G.GAME
    local ante = GG.round_resets.ante
    local _type = t.set
    local append = t.key_append
    local forced = t.key
    local front

    if t.enhancement then forced = t.enhancement; _type = 'Enhanced' end
    if _type == 'Playing Card' or _type == 'Base' or _type == 'Enhanced' or (not _type and (t.front or t.rank or t.suit)) then
        if not _type or _type == 'Playing Card' then
            _type = forced and 'Enhanced'
                or ((pseudorandom('sccset' .. (append or '') .. ante) > (t.enhanced_poll or 0.6)) and 'Enhanced' or 'Base')
        end
        if t.front == nil then
            local r_suit, r_rank
            if not t.suit or not t.rank then
                local s = pseudorandom_element(SMODS.Suits, pseudoseed('sccsuit' .. (append or '') .. ante))
                local r = pseudorandom_element(SMODS.Ranks, pseudoseed('sccrank' .. (append or '') .. ante))
                r_suit, r_rank = s and s.card_key, r and r.card_key
            end
            local suit = t.suit and (SMODS.Suits['' .. t.suit] or {}).card_key or t.suit or r_suit
            local rank = t.rank and (SMODS.Ranks['' .. t.rank] or {}).card_key or t.rank or r_rank
            front = suit and rank and (suit .. '_' .. rank) or nil
        elseif t.front then
            front = t.front
        end
    end

    if not forced and (t.fs_area == 'shop' or t.fs_area == 'pack') then
        local ok, list = pcall(SMODS.find_card, 'j_jokerhub_going_viral', false)
        local gv = (ok and type(list) == 'table') and #list or 0
        for _ = 1, gv do
            if pseudorandom(pseudoseed('going_viral' .. ante)) > 1 - (0.25 * GG.probabilities.normal) then
                _type = 'Joker'
                forced = 'j_jokerhub_going_viral'
                break
            end
        end
    end

    if not forced and t.soulable and not GG.banned_keys['c_soul'] then
        local total, non, list = 0, 1, nil
        for _, v in ipairs(SMODS.Consumable.legendaries or {}) do
            if (_type == (v.type and v.type.key) or _type == v.soul_set)
                and not (O.used(v.key) and not SMODS.showman(v.key) and not v.can_repeat_soul) and SMODS.add_to_pool(v) then
                total = total + v.soul_rate
                non = math.max(non * (1 - v.soul_rate), 0)
                list = list or {}
                list[#list + 1] = v
            end
        end
        local roll = pseudorandom('soul_smods_' .. _type .. ante)
        if list then
            local th = 1
            for _, v in ipairs(list) do
                th = th - v.soul_rate / total * (1 - non)
                if roll > th then forced = v.key; break end
            end
        end
        if (_type == 'Tarot' or _type == 'Spectral' or _type == 'Tarot_Planet') and not (O.used('c_soul') and not SMODS.showman('c_soul')) then
            if pseudorandom('soul_' .. _type .. ante) > 0.997 then forced = 'c_soul' end
        end
        if (_type == 'Planet' or _type == 'Spectral') and not (O.used('c_black_hole') and not SMODS.showman('c_black_hole')) then
            if pseudorandom('soul_' .. _type .. ante) > 0.997 then forced = 'c_black_hole' end
        end
    end

    if _type == 'Base' then forced = 'c_base' end

    local key
    if forced and not GG.banned_keys[forced] then
        key = forced
        local c = G.P_CENTERS[forced]
        if c and c.set ~= 'Default' then _type = c.set end
    else
        local pool, pkey = get_current_pool(_type, t.rarity, t.legendary, append)
        local c = pseudorandom_element(pool, pseudoseed(pkey))
        local it = 1
        while c == 'UNAVAILABLE' and it < 100 do
            it = it + 1
            c = pseudorandom_element(pool, pseudoseed(pkey .. '_resample' .. it))
        end
        key = c
    end

    if not front and (_type == 'Base' or _type == 'Enhanced') then
        local _, k = pseudorandom_element(G.P_CARDS, pseudoseed('front' .. (append or '') .. ante))
        front = k
    end

    local edition = O.edition_key(t.edition)
    if _type == 'Joker' and not t.no_edition and not edition then
        edition = O.edition_key(poll_edition('edi' .. (append or '') .. ante))
    end
    return { key = key, set = _type, edition = edition, seal = t.seal, front = front }
end

-------------------------------------------------------------------------------
-- Predictors. Each starts from a pristine RNG copy, so they never interfere.
-------------------------------------------------------------------------------
--- Small and Big blind skip tags for an ante.
function O.tags(ante)
    O.fresh(ante)
    local s = get_next_tag_key()
    local b = get_next_tag_key()
    return s, b
end

--- Blinds for antes from..to: {[ante] = {small, big, boss}}.
function O.blinds(from, to)
    O.fresh(from)
    local GG = G.GAME
    if O.mode == 'seed' then
        GG.bosses_used = SMODS.normalize_bosses_used_table({})
    else
        GG.bosses_used = SMODS.normalize_bosses_used_table(O.saved.bu)
    end
    local out = {}
    for a = from, to do
        GG.round_resets.ante = a
        GG.round_resets.blind_choices = {}
        SMODS.reset_blind_choices(GG.round_resets.blind_choices)
        local bc = GG.round_resets.blind_choices
        out[a] = { small = bc.Small, big = bc.Big, boss = bc.Boss }
    end
    return out
end

--- Shop vouchers for antes from..to: {[ante] = {keys}}. assume_bought: earlier ones count as redeemed.
function O.vouchers(from, to, assume_bought)
    O.fresh(from)
    local GG = G.GAME
    local uv = {}
    for k, v in pairs(O.saved.uv or {}) do uv[k] = v end
    GG.used_vouchers = uv
    local out = {}
    for a = from, to do
        GG.round_resets.ante = a
        local list = SMODS.get_next_vouchers()
        local keys = {}
        for i, k in ipairs(list) do keys[i] = k end
        out[a] = keys
        if assume_bought then
            for _, k in ipairs(keys) do
                uv[k] = true
                O.vstamp = O.vstamp .. k
            end
        end
    end
    return out
end

--- One shop slot (the joker/consumable row), as create_card_for_shop would roll it.
function O.shop_card()
    local GG = G.GAME
    local ante = GG.round_resets.ante
    local num = FS.num
    local total = num(GG.joker_rate) + num(GG.playing_card_rate)
    for _, v in ipairs(SMODS.ConsumableType.obj_buffer) do total = total + num(GG[v:lower() .. '_rate']) end
    local polled = pseudorandom(pseudoseed('cdt' .. ante)) * total
    local rates = {
        { type = 'Joker', val = num(GG.joker_rate) },
        { type = 'Tarot', val = num(GG.tarot_rate) },
        { type = 'Planet', val = num(GG.planet_rate) },
        { type = (GG.used_vouchers['v_illusion'] and pseudorandom(pseudoseed('illusion')) > 0.6) and 'Enhanced' or 'Base', val = num(GG.playing_card_rate) },
        { type = 'Spectral', val = num(GG.spectral_rate) },
    }
    for _, v in ipairs(SMODS.ConsumableType.obj_buffer) do
        if not (v == 'Tarot' or v == 'Planet' or v == 'Spectral') then
            rates[#rates + 1] = { type = v, val = num(GG[v:lower() .. '_rate']) }
        end
    end
    local check = 0
    for _, v in ipairs(rates) do
        if polled > check and polled <= check + v.val then
            local c = O.card({ set = v.type, key_append = 'sho', front = false, fs_area = 'shop' })
            if (v.type == 'Base' or v.type == 'Enhanced') and GG.used_vouchers['v_illusion'] and pseudorandom(pseudoseed('illusion')) > 0.8 then
                c.edition = O.edition_key(poll_edition('illusion', nil, true, true))
            end
            return c
        end
        check = check + v.val
    end
    return { key = nil }
end

function O.shop_slots()
    local GG = G.GAME
    return (GG.shop and GG.shop.joker_max) or 2
end

--- The first n shop cards an ante will show (each roll of slots = the shop, then each reroll).
function O.shop(ante, n)
    O.fresh(ante)
    local per = O.shop_slots()
    local out = {}
    while #out < n do
        local roll = {}
        for _ = 1, per do
            local c = O.shop_card()
            out[#out + 1] = c
            if c.key then O.mark(c.key); roll[#roll + 1] = c.key end
            if #out >= n then break end
        end
        for _, k in ipairs(roll) do O.unmark(k) end
    end
    return out
end

function O.packs_per_shop()
    local GG = G.GAME
    return (GG.starting_params and GG.starting_params.boosters_in_shop or 2) + (GG.modifiers and GG.modifiers.extra_boosters or 0)
end

--- The first n booster packs offered in shops during an ante.
function O.shop_packs(ante, n)
    O.fresh(ante)
    local out = {}
    for i = 1, n do
        local c = get_pack('shop_pack')
        out[i] = c and c.key or nil
    end
    return out
end

local function fake_booster(center)
    local cfg = {}
    for k, v in pairs(center.config or {}) do cfg[k] = v end
    return { ability = cfg, config = { center = center }, T = { x = 0, y = 0, w = 1, h = 1 } }
end

--- Contents of the first pack of this booster opened during an ante.
function O.pack(booster_key, ante, count)
    O.fresh(ante)
    local center = G.P_CENTERS[booster_key]
    if not center then return {} end
    local GG = G.GAME
    local size = count or math.max(1, ((center.config and center.config.extra) or 1) + (GG.modifiers.booster_size_mod or 0))
    local fake = fake_booster(center)
    local out = {}
    for i = 1, size do
        local spec
        if type(center.create_card) == 'function' then
            local ok, res = pcall(center.create_card, center, fake, i)
            if ok then spec = res end
        end
        local c
        if type(spec) == 'table' and type(spec.is) == 'function' then
            -- the booster built a real card itself: read it, then throw it away
            local ckey = spec.config and spec.config.center and spec.config.center.key
            c = { key = ckey, edition = spec.edition and spec.edition.key }
            pcall(spec.remove, spec)
        elseif type(spec) == 'table' then
            local t = {}
            for k, v in pairs(spec) do t[k] = v end
            t.area = nil
            t.fs_area = 'pack'
            c = O.card(t)
        else
            c = { key = nil }
        end
        out[i] = c
        if c.key then O.mark(c.key) end
    end
    return out
end

--- Where The Soul / Black Hole land among the first n soulable cards of a type in an ante.
--- per_pack: cards per pack (a held Soul stops more Souls in the same pack; assumed used between packs).
function O.souls(_type, ante, n, per_pack)
    O.fresh(ante)
    local GG = G.GAME
    local out = {}
    if GG.banned_keys['c_soul'] then return out end
    local base_soul = O.used('c_soul') and not SMODS.showman('c_soul')
    local base_bh = O.used('c_black_hole') and not SMODS.showman('c_black_hole')
    local soul_used, bh_used = base_soul, base_bh
    per_pack = per_pack or n
    for i = 1, n do
        if (i - 1) % per_pack == 0 then soul_used, bh_used = base_soul, base_bh end
        local res
        if (_type == 'Tarot' or _type == 'Spectral' or _type == 'Tarot_Planet') and not soul_used then
            if pseudorandom('soul_' .. _type .. ante) > 0.997 then res = 'c_soul' end
        end
        if (_type == 'Planet' or _type == 'Spectral') and not bh_used then
            if pseudorandom('soul_' .. _type .. ante) > 0.997 then res = 'c_black_hole' end
        end
        if res == 'c_soul' then soul_used = true elseif res == 'c_black_hole' then bh_used = true end
        out[i] = res or false
    end
    return out
end

--- What using The Soul would create (legendary joker + edition), used during the given ante.
function O.legendary(ante)
    O.fresh(ante)
    return O.card({ set = 'Joker', legendary = true, key_append = 'sou' })
end

--- Erratic Deck: the starting cards (card keys like "H_A").
function O.erratic_keys()
    if O._erratic_keys then return O._erratic_keys end
    local keys = {}
    for k, v in pairs(G.P_CARDS) do
        local ok, keep = pcall(function()
            return SMODS.add_to_pool(SMODS.Ranks[v.value], { initial_deck = true, suit = v.suit })
                and SMODS.add_to_pool(SMODS.Suits[v.suit], { initial_deck = true, rank = v.value })
        end)
        if ok and keep then keys[#keys + 1] = { k = k, v = v } end
    end
    if keys[1] and keys[1].v.sort_id then
        table.sort(keys, function(a, b) return a.v.sort_id < b.v.sort_id end)
    else
        table.sort(keys, function(a, b) return a.k < b.k end)
    end
    O._erratic_keys = keys
    return keys
end

function O.erratic(n)
    O.fresh(1)
    local keys = O.erratic_keys()
    local out = {}
    if #keys == 0 then return out end
    for i = 1, n do
        math.randomseed(pseudoseed('erratic'))
        out[i] = keys[math.random(#keys)].k
    end
    return out
end

--- Does the current run use a deck that randomises ranks and suits?
function O.is_erratic()
    local GG = G.GAME
    if GG and GG.starting_params and GG.starting_params.erratic_suits_and_ranks then return true end
    local b = GG and GG.selected_back
    local cfg = b and b.effect and b.effect.config
    return cfg and cfg.randomize_rank_suit and true or false
end

-------------------------------------------------------------------------------
-- Labels
-------------------------------------------------------------------------------
--- "Ante 2 shop" bookkeeping: the shop after a Boss Blind already rolls as the next ante.
function O.next_shop_ante()
    local GG = G.GAME
    local a = GG.round_resets.ante
    local on_deck = GG.blind_on_deck
    if G.STATE == G.STATES.SHOP then return a end
    if on_deck == 'Boss' and GG.round_resets.blind_states and GG.round_resets.blind_states.Boss ~= 'Defeated' then return a + 1 end
    return a
end
