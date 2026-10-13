--- Crystal Ball tab: what the current run has in store - antes, shops, packs and souls.
local FS = Foresight
local UI, O, F = FS.UI, FS.Oracle, FS.Filters
local R, C = G.UIT.R, G.UIT.C

local ACCENT = function() return G.C.SECONDARY_SET.Tarot end
local ROLLS_PER_PAGE = 3

local function fc() return FS.state.forecast end

--- Pack kinds that can be previewed, with the largest pack of each kind.
local function pack_kinds()
    local best, order = {}, {}
    for _, g in ipairs(F.booster_groups().list) do
        local c = G.P_CENTERS[g.key]
        if g.kind and c and type(c.create_card) == 'function' then
            local size = (c.config and c.config.extra) or 1
            if not best[g.kind] then order[#order + 1] = g.kind end
            if not best[g.kind] or size > best[g.kind].size then best[g.kind] = { key = g.key, size = size } end
        end
    end
    local out = {}
    for _, k in ipairs(order) do
        out[#out + 1] = { key = k, label = FS.loc_or(k, 'k_' .. tostring(k):lower() .. '_pack'):gsub(' Pack$', ''), booster = best[k].key }
    end
    return out
end

local function first_hit(list, target)
    for i, v in ipairs(list or {}) do if v == target then return i end end
end

-------------------------------------------------------------------------------
-- Prediction
-------------------------------------------------------------------------------
local function compute()
    local gm = G.GAME
    local s = fc()
    local ante = FS.num(gm.round_resets.ante)
    local res = { ante = ante, in_shop = G.STATE == G.STATES.SHOP }
    local unmark = {}
    if res.in_shop and G.shop_jokers then
        for _, c in ipairs(G.shop_jokers.cards) do
            local k = c.config.center.key
            local ok, owned = pcall(SMODS.find_card, k, true)
            if not ok or not owned or #owned == 0 then unmark[#unmark + 1] = k end
        end
    end
    -- read the real run before the oracle starts moving the sandboxed ante around
    local sa = O.next_shop_ante()
    local kinds = pack_kinds()
    local kind
    for _, k in ipairs(kinds) do if k.key == s.kind then kind = k end end
    kind = kind or kinds[1]
    if kind then s.kind = kind.key end

    local ok = O.live(function()
        local cur_v = {}
        for _, k in ipairs(gm.current_round.voucher or {}) do cur_v[#cur_v + 1] = k end
        res.road = { {
            ante = ante, now = true, small = gm.round_resets.blind_tags and gm.round_resets.blind_tags.Small,
            big = gm.round_resets.blind_tags and gm.round_resets.blind_tags.Big,
            boss = gm.round_resets.blind_choices and gm.round_resets.blind_choices.Boss, vouchers = cur_v,
        } }
        local n = s.antes or 4
        if n > 1 then
            local bl = O.blinds(ante + 1, ante + n - 1)
            local vs = O.vouchers(ante + 1, ante + n - 1, false)
            for a = ante + 1, ante + n - 1 do
                local sm, bg = O.tags(a)
                res.road[#res.road + 1] = { ante = a, small = sm, big = bg, boss = bl[a] and bl[a].boss, vouchers = vs[a] or {} }
            end
        end

        res.shop_ante = sa
        res.slots = O.shop_slots()
        local page = s.roll_page or 1
        res.shop = O.shop(sa, res.slots * ROLLS_PER_PAGE * page)
        res.packs = O.shop_packs(sa, O.packs_per_shop())
        if sa ~= ante then
            res.shop_vouchers = O.vouchers(sa, sa, false)[sa]
        else
            res.shop_vouchers = cur_v
        end

        if kind then
            res.kind = kind
            res.pack = O.pack(kind.booster, sa)
        end
        res.soul = first_hit(O.souls('Tarot', sa, 60, 5), 'c_soul')
        res.soul_spec = first_hit(O.souls('Spectral', sa, 40, 4), 'c_soul')
        res.bh = first_hit(O.souls('Planet', sa, 60, 5), 'c_black_hole')
        res.legendary = O.legendary(ante)
    end, { unmark = unmark })
    return ok and res or nil
end

-------------------------------------------------------------------------------
-- Sections
-------------------------------------------------------------------------------
local function ante_card(e)
    local tagrow = {}
    if e.small then tagrow[#tagrow + 1] = UI.tag_icon(e.small, 0.55) end
    if e.big then tagrow[#tagrow + 1] = UI.tag_icon(e.big, 0.55) end
    local boss = e.boss and G.P_BLINDS[e.boss]
    local showdown = boss and boss.boss and boss.boss.showdown
    local icons = UI.row({
        UI.col(tagrow, { padding = 0.04 }),
        UI.spacer(0.12),
        boss and UI.blind_icon(e.boss, 0.66) or UI.text('?', 0.4),
        UI.spacer(0.12),
        (e.vouchers and e.vouchers[1]) and UI.card_strip({ { key = e.vouchers[1] } }, { scale = 0.4 }) or UI.text('-', 0.3, UI.muted()),
    }, { padding = 0.02 })
    local tag_txt = (e.small and FS.name_of(e.small) or '?') .. '  /  ' .. (e.big and FS.name_of(e.big) or '?')
    local head = { UI.text('ANTE ' .. tostring(e.ante), 0.34, G.C.UI.TEXT_LIGHT) }
    if e.now then
        head[#head + 1] = UI.spacer(0.1)
        head[#head + 1] = { n = C, config = { align = 'cm', padding = 0.04, r = 0.06, colour = G.C.GREEN }, nodes = { UI.text('NOW', 0.24, G.C.WHITE) } }
    end
    if showdown then
        head[#head + 1] = UI.spacer(0.1)
        head[#head + 1] = { n = C, config = { align = 'cm', padding = 0.04, r = 0.06, colour = G.C.RED }, nodes = { UI.text('FINALE', 0.24, G.C.WHITE) } }
    end
    return {
        n = C,
        config = { align = 'tm', padding = 0.07, r = 0.12, colour = e.now and UI.tint(ACCENT(), 0.62) or { 0, 0, 0, 0.22 }, minw = 4.42, minh = 2.3 },
        nodes = {
            UI.row(head, { padding = 0.02 }),
            icons,
            UI.row({ UI.text(tag_txt, 0.24, UI.muted(), { maxw = 4.25 }) }, { padding = 0.01 }),
            UI.row({ UI.text(boss and FS.name_of(boss) or '-', 0.27, showdown and G.C.RED or G.C.UI.TEXT_LIGHT, { maxw = 4.25 }) }, { padding = 0.01 }),
        },
    }
end

local function road_section(res)
    local cards = {}
    for _, e in ipairs(res.road) do cards[#cards + 1] = ante_card(e) end
    return UI.section({
        title = 'THE ROAD AHEAD', subtitle = 'skip tags, bosses and vouchers  -  later vouchers assume you buy none',
        colour = ACCENT(), w = UI.W - 0.1, align = 'tm', row = true, padding = 0.03,
        nodes = { UI.row(cards, { padding = 0.05 }) },
    })
end

local function shop_section(res)
    local s = fc()
    local page = s.roll_page or 1
    local groups = {}
    local first_roll = (page - 1) * ROLLS_PER_PAGE + 1
    for r = first_roll, first_roll + ROLLS_PER_PAGE - 1 do
        local items = {}
        for i = 1, res.slots do
            local c = res.shop[(r - 1) * res.slots + i]
            if c and c.key then items[#items + 1] = { key = c.key, edition = c.edition, front = c.front } end
        end
        local label = res.in_shop and ('Reroll ' .. r) or (r == 1 and 'First look' or ('Reroll ' .. (r - 1)))
        groups[#groups + 1] = UI.col({
            UI.row({ UI.text(label, 0.27, r == 1 and G.C.FILTER or UI.muted()) }),
            UI.row({ UI.card_strip(items, { scale = 0.48, slots = res.slots }) }),
        }, { padding = 0.04 })
    end
    local packs = {}
    for _, k in ipairs(res.packs or {}) do packs[#packs + 1] = { key = k } end
    local vouchers = {}
    for _, k in ipairs(res.shop_vouchers or {}) do vouchers[#vouchers + 1] = { key = k } end
    local function turn(d)
        s.roll_page = math.max(1, (s.roll_page or 1) + d)
        FS.refresh()
    end
    return UI.section({
        title = res.in_shop and 'NEXT REROLLS' or 'NEXT SHOP',
        subtitle = ('rolls as Ante %d'):format(res.shop_ante), colour = G.C.RED, w = 9.3, h = 4.9, align = 'tm',
        nodes = { UI.col({
            UI.row(groups, { padding = 0.02 }),
            UI.row({
                UI.button({ label = '<', w = 0.5, h = 0.34, scale = 0.28, colour = G.C.RED, enabled = function() return (s.roll_page or 1) > 1 end, on_click = function() turn(-1) end }),
                { n = C, config = { align = 'cm', minw = 2.6 }, nodes = { UI.text(('Rolls %d-%d'):format(first_roll, first_roll + ROLLS_PER_PAGE - 1), 0.27, UI.muted()) } },
                UI.button({ label = '>', w = 0.5, h = 0.34, scale = 0.28, colour = G.C.RED, on_click = function() turn(1) end }),
            }, { padding = 0.02 }),
            UI.row({
                UI.col({ UI.row({ UI.text(res.in_shop and 'Next shop packs' or 'Packs', 0.26, UI.muted()) }), UI.row({ UI.card_strip(packs, { scale = 0.34, booster = true, slots = 2 }) }) }, { padding = 0.03 }),
                UI.spacer(0.25),
                UI.col({ UI.row({ UI.text('Voucher', 0.26, UI.muted()) }), UI.row({ UI.card_strip(vouchers, { scale = 0.44, slots = 1 }) }) }, { padding = 0.03 }),
            }, { padding = 0.02 }),
        }, { align = 'tm' }) },
    })
end

local function watch_line(label, value, colour)
    return UI.row({
        { n = C, config = { align = 'cl', minw = 2.6 }, nodes = { UI.text(label, 0.27, UI.muted()) } },
        { n = C, config = { align = 'cl', minw = 5.9 }, nodes = { UI.text(value, 0.29, colour or G.C.UI.TEXT_LIGHT, { maxw = 5.85 }) } },
    }, { align = 'cl', padding = 0.01 })
end

local function where(i, per, what)
    if not i then return 'not in the next ' .. what end
    local pack = math.floor((i - 1) / per) + 1
    local slot = (i - 1) % per + 1
    local ord = ({ '1st', '2nd', '3rd' })[pack] or (pack .. 'th')
    return ('card %d of the %s pack (5-card packs)'):format(slot, ord)
end

local function packs_section(res)
    local s = fc()
    -- read the real run before the oracle starts moving the sandboxed ante around
    local sa = O.next_shop_ante()
    local kinds = pack_kinds()
    local items = {}
    for _, c in ipairs(res.pack or {}) do items[#items + 1] = { key = c.key, edition = c.edition, seal = c.seal, front = c.front } end
    local booster = res.kind and G.P_CENTERS[res.kind.booster]
    local leg = res.legendary
    local leg_txt = leg and leg.key and (FS.name_of(leg.key) .. (leg.edition and (' (' .. FS.edition_name(leg.edition) .. ')') or '')) or '?'
    return UI.section({
        title = 'NEXT PACKS', subtitle = ('the first pack of each kind you open in Ante %d'):format(res.shop_ante),
        colour = ACCENT(), w = 9.0, h = 4.9, align = 'tm',
        nodes = { UI.col({
            UI.row({ UI.radio(kinds, s, 'kind', { per_row = 5, w = 1.6, h = 0.38, scale = 0.27, max_rows = 1, id = 'fc_kind', colour = ACCENT(), on_change = function() FS.refresh() end }) }, { align = 'cl' }),
            UI.row({ UI.card_strip(items, { scale = 0.5, slots = 5 }) }, { padding = 0.02 }),
            UI.row({ UI.text(booster and (FS.name_of(booster) .. ' - smaller packs show the first cards') or '', 0.24, UI.muted()) }, { padding = 0.01 }),
            UI.row({ UI.spacer(0.1, 0.08) }),
            watch_line('The Soul (Arcana)', where(res.soul, 5, '60 Arcana cards'), res.soul and G.C.SECONDARY_SET.Spectral),
            watch_line('The Soul (Spectral)', res.soul_spec and ('card %d of the Spectral cards you see'):format(res.soul_spec) or 'not in the next 40 Spectral cards', res.soul_spec and G.C.SECONDARY_SET.Spectral),
            watch_line('Black Hole', where(res.bh, 5, '60 Celestial cards'), res.bh and G.C.SECONDARY_SET.Planet),
            watch_line('The Soul gives', leg_txt, G.C.RARITY and G.C.RARITY[4] or G.C.PURPLE),
        }, { align = 'tm' }) },
    })
end

local function build()
    if not FS.in_run() then return UI.notice('Start a run first', { 'The crystal ball reads the run you are playing.' }) end
    local res = compute()
    if not res then
        return UI.notice('The crystal ball is cloudy', { 'Something went wrong predicting this run.', 'Details are in the log.' }, G.C.RED)
    end
    return UI.col({
        road_section(res),
        UI.row({ shop_section(res), UI.spacer(0.05), packs_section(res) }, { align = 'tm', padding = 0.02 }),
        UI.row({ UI.text('Predictions assume nothing else uses the same random rolls first - held tags, some jokers and Director\'s Cut can change them.', 0.24, UI.muted()) }, { padding = 0.02 }),
    }, { align = 'tm' })
end

FS.register_tab({
    id = 'forecast', label = 'Crystal Ball', colour = function() return G.C.SECONDARY_SET.Tarot end, order = 2, needs_run = true,
    build = build,
    wheel = function(y)
        local s = fc()
        s.roll_page = math.max(1, (s.roll_page or 1) + (y > 0 and -1 or 1))
        FS.refresh()
    end,
})
