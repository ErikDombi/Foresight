--- Seeds tab: the current seed, playing any seed, history and favourites.
local FS = Foresight
local UI, SD = FS.UI, FS.Seeds
local R, C = G.UIT.R, G.UIT.C

local ACCENT = function() return G.C.MONEY end
local PER_PAGE = 8
local LW, RW, H = 6.95, 11.45, 7.55

local function st() return FS.state.seeds end

local function deck_options()
    local out = {}
    for _, b in ipairs(G.P_CENTER_POOLS.Back or {}) do
        if b.unlocked ~= false and not (SMODS.hide_from_collection and SMODS.hide_from_collection(b)) then
            out[#out + 1] = { key = b.key, label = FS.deck_name(b.key) }
        end
    end
    return out
end

local function stake_options()
    local out = {}
    for i = 1, #(G.P_CENTER_POOLS.Stake or {}) do out[#out + 1] = { key = i, label = FS.stake_name(i) .. ' Stake' } end
    return out
end

local function this_run()
    local e = SD.current_entry()
    if not e then
        return UI.section({ title = 'THIS RUN', colour = ACCENT(), w = LW, h = 2.85, align = 'cm', nodes = {
            UI.notice('Not in a run', { 'Play a seed below, or start a run as usual.' }),
        } })
    end
    local starred = function() return SD.is_favourite(e.seed, e.deck, e.stake) ~= nil end
    local src = e.source and SD.SOURCE_LABEL[e.source] or (G.GAME.seeded and 'seeded run' or 'random seed')
    local rows = {
        UI.row({ UI.text(e.seed, 0.85, G.C.FILTER) }, { padding = 0.02 }),
        UI.row({ UI.text(('%s  -  %s Stake  -  %s'):format(FS.deck_name(e.deck), FS.stake_name(e.stake), src), 0.27, UI.muted(), { maxw = LW - 0.3 }) }),
    }
    if e.note then
        local note = #e.note > 70 and (e.note:sub(1, 68) .. '...') or e.note
        rows[#rows + 1] = UI.row({ UI.text(note, 0.23, UI.muted(), { maxw = LW - 0.3 }) })
    end
    rows[#rows + 1] = UI.row({
        UI.button({ label = 'Copy', w = 1.45, h = 0.5, scale = 0.3, colour = G.C.BLUE, on_click = function() SD.copy(e.seed) end }),
        UI.spacer(0.05),
        UI.button({ label = 'Restart', sub = 'Ctrl+Shift+T', w = 1.6, h = 0.5, scale = 0.3, colour = G.C.ORANGE, on_click = function() SD.replay() end }),
        UI.spacer(0.05),
        UI.button({ label = 'New run', sub = 'Ctrl+T', w = 1.6, h = 0.5, scale = 0.3, colour = G.C.GREEN, on_click = function() SD.reroll() end }),
        UI.spacer(0.05),
        UI.button({ label = function() return starred() and 'Starred' or 'Star' end, w = 1.45, h = 0.5, scale = 0.3, colour = ACCENT(),
            on_click = function() SD.toggle_favourite(e); FS.refresh() end }),
    }, { padding = 0.05 })
    return UI.section({ title = 'THIS RUN', colour = ACCENT(), w = LW, h = 2.85, align = 'tm', nodes = { UI.col(rows, { align = 'tm' }) } })
end

local function play_box()
    local s = st()
    local setup = SD.setup()
    s.deck = s.deck or setup.deck
    s.stake = s.stake or setup.stake
    local function play()
        local seed = SD.clean_seed(s.input)
        if seed == '' then return FS.warn('Type or paste a seed first') end
        SD.start({ seed = seed, deck = s.deck, stake = s.stake, source = 'typed' })
    end
    return UI.section({ title = 'PLAY A SEED', colour = ACCENT(), w = LW, h = 4.6, align = 'tm', nodes = { UI.col({
        UI.row({
            UI.input({ tbl = s, field = 'input', w = 3.6, max_length = 8, all_caps = true, prompt = 'Seed...', colour = ACCENT() }),
            UI.spacer(0.08),
            UI.button({ label = 'Paste', w = 1.2, h = 0.45, scale = 0.3, colour = G.C.BLUE, on_click = function()
                s.input = SD.paste()
                FS.refresh()
            end }),
        }, { padding = 0.04 }),
        UI.row({ UI.text('Deck', 0.27, UI.muted()) }, { align = 'cl' }),
        UI.row({ UI.cycler({ options = deck_options(), w = 4.6, colour = ACCENT(), get = function() return s.deck end, set = function(k) s.deck = k end }) }),
        UI.row({ UI.text('Stake', 0.27, UI.muted()) }, { align = 'cl' }),
        UI.row({ UI.cycler({ options = stake_options(), w = 4.6, colour = ACCENT(), get = function() return s.stake end, set = function(k) s.stake = k end }) }),
        UI.row({ UI.spacer(0.1, 0.1) }),
        UI.row({ UI.button({ label = 'Play this seed', w = LW - 0.5, h = 0.75, scale = 0.45, colour = G.C.GREEN, on_click = play }) }, { padding = 0.04 }),
        UI.row({ UI.text('Seeded runs do not count toward unlocks, like the base game.', 0.23, UI.muted()) }),
    }, { align = 'tm' }) } })
end

local build_list

local function short(text)
    text = tostring(text or '')
    if #text > 52 then text = text:sub(1, 50) .. '...' end
    return text
end

local function history_row(e)
    local fav = SD.is_favourite(e.seed, e.deck, e.stake) ~= nil
    local stats = ('best Ante %s%s'):format(tostring(e.best or 1), e.won and '  -  won' or '')
    local src = e.source and SD.SOURCE_LABEL[e.source] or ''
    local nodes = {
        UI.button({ label = fav and 'Starred' or 'Star', w = 1.05, h = 0.42, scale = 0.26, colour = fav and ACCENT() or G.C.UI.BACKGROUND_INACTIVE,
            tooltip = { text = { fav and 'Remove from favourites' or 'Add to favourites' } },
            on_click = function() SD.toggle_favourite(e); UI.replace('fsgt_seed_list', build_list) end }),
        UI.spacer(0.1),
        { n = C, config = { align = 'cl', minw = 1.75 }, nodes = { UI.text(e.seed or '?', 0.36, G.C.FILTER) } },
        { n = C, config = { align = 'cl', minw = 4.75 }, nodes = {
            UI.row({ UI.text(('%s  -  %s Stake  -  %s'):format(FS.deck_name(e.deck), FS.stake_name(e.stake), stats), 0.26, G.C.UI.TEXT_LIGHT, { maxw = 4.7 }) }, { align = 'cl' }),
            UI.row({ UI.text(FS.ago(e.t) .. '  -  ' .. short(e.note or src), 0.22, UI.muted(), { maxw = 4.7 }) }, { align = 'cl' }),
        } },
        UI.button({ label = 'Play', w = 1.15, h = 0.45, scale = 0.3, colour = G.C.GREEN, on_click = function() SD.play(e) end }),
        UI.spacer(0.05),
        UI.button({ label = 'Copy', w = 1.05, h = 0.45, scale = 0.28, colour = G.C.BLUE, on_click = function() SD.copy(e.seed) end }),
    }
    return { n = R, config = { align = 'cl', padding = 0.05, r = 0.1, colour = { 0, 0, 0, 0.18 }, minw = RW - 0.35 }, nodes = nodes }
end

build_list = function()
    local s = st()
    local list = s.view == 'favorites' and FS.config.favorites or FS.config.history
    local pages = math.max(1, math.ceil(#list / PER_PAGE))
    s.page = FS.clamp(s.page or 1, 1, pages)
    FS.view.seed_pages = pages
    local rows = {}
    if #list == 0 then
        rows[1] = UI.row({ UI.notice(s.view == 'favorites' and 'No favourites yet' or 'No history yet', {
            s.view == 'favorites' and 'Star a seed to keep it here.' or 'Every run you start is listed here.',
        }) }, { minh = 5.6 })
    else
        local first = (s.page - 1) * PER_PAGE
        for i = first + 1, math.min(#list, first + PER_PAGE) do rows[#rows + 1] = history_row(list[i]) end
    end
    return UI.root({ UI.col(rows, { align = 'tm', padding = 0.02 }) }, { align = 'tm', minw = RW - 0.2, minh = 5.85 })
end

local function turn(d)
    local s = st()
    local pages = FS.view.seed_pages or 1
    local p = (s.page or 1) + d
    if p < 1 then p = pages elseif p > pages then p = 1 end
    s.page = p
    FS.sfx('paper1', 1.05, 0.4)
    UI.replace('fsgt_seed_list', build_list)
end

local function list_box()
    local s = st()
    s.view = s.view or 'history'
    return UI.section({ title = 'YOUR SEEDS', colour = ACCENT(), w = RW, h = H, align = 'tm', nodes = { UI.col({
        UI.row({
            UI.radio({ { key = 'history', label = 'Recent runs' }, { key = 'favorites', label = 'Favourites' } }, s, 'view', {
                per_row = 2, w = 2.4, h = 0.45, colour = ACCENT(), on_change = function() s.page = 1; UI.replace('fsgt_seed_list', build_list) end,
            }),
            UI.spacer(2.6),
            UI.confirm_button({ label = 'Clear history', confirm_label = 'Sure?', w = 2.2, h = 0.4, scale = 0.27, colour = G.C.UI.BACKGROUND_INACTIVE,
                on_click = function()
                    local h = FS.config.history
                    for i = #h, 1, -1 do h[i] = nil end
                    FS.save_config()
                    UI.replace('fsgt_seed_list', build_list)
                end }),
        }, { align = 'cl', padding = 0.03 }),
        UI.row({ UI.slot('fsgt_seed_list', build_list, { minw = RW - 0.2, minh = 5.85 }) }),
        UI.row({
            UI.button({ label = '<', w = 0.55, h = 0.36, scale = 0.3, colour = ACCENT(), on_click = function() turn(-1) end }),
            { n = C, config = { align = 'cm', minw = 2.6 }, nodes = { UI.live(function()
                return ('Page %d / %d'):format(st().page or 1, FS.view.seed_pages or 1)
            end, 0.27, UI.muted()) } },
            UI.button({ label = '>', w = 0.55, h = 0.36, scale = 0.3, colour = ACCENT(), on_click = function() turn(1) end }),
        }, { padding = 0.02 }),
    }, { align = 'tm' }) } })
end

local function build()
    return UI.row({
        UI.col({ this_run(), UI.row({ UI.spacer(0.1, 0.05) }), play_box() }, { align = 'tm' }),
        UI.spacer(0.05),
        list_box(),
    }, { align = 'tm', padding = 0.03 })
end

FS.register_tab({
    id = 'seeds', label = 'Seeds', colour = function() return G.C.MONEY end, order = 5,
    build = build,
    wheel = function(y) turn(y > 0 and -1 or 1) end,
})
