--- Seed Finder tab: build a stack of filters, then let the finder hunt for a matching seed.
local FS = Foresight
local UI, F, S = FS.UI, FS.Filters, FS.Search
local R, C = G.UIT.R, G.UIT.C

local LW, RW, H = 12.05, 6.35, 7.55
local ROWS_PER_PAGE = 6
local ACCENT = function() return G.C.SECONDARY_SET.Spectral end

local function filters() return FS.config.filters end
local function st() return FS.state.finder end

local build_left

local function rebuild_left()
    UI.replace('fsgt_finder_left', build_left)
end

local function persist()
    FS.save_config()
end

local function edit(i)
    st().editing = i
    FS.sfx('paper1', 1.1, 0.5)
    rebuild_left()
end

local function stop_editing()
    st().editing = nil
    persist()
    rebuild_left()
end

local function add(type_id)
    local list = filters()
    list[#list + 1] = F.new(type_id)
    persist()
    edit(#list)
end

local function remove(i)
    table.remove(filters(), i)
    if st().editing == i then st().editing = nil end
    persist()
    FS.sfx('crumple1', 1, 0.4)
    rebuild_left()
end

-------------------------------------------------------------------------------
-- List view
-------------------------------------------------------------------------------
local function filter_row(i, f)
    local t = F.TYPES[f.type]
    local col = t.colour()
    local text_col = G.C.UI.TEXT_LIGHT
    local info = {
        UI.row({ UI.text(t.label:upper(), 0.23, UI.muted()) }, { align = 'cl' }),
        UI.row({ UI.live(function() return F.describe(f) end, 0.3, text_col, { maxw = 6.75 }) }, { align = 'cl' }),
    }
    local problem = F.problem(f)
    if problem then info[#info + 1] = UI.row({ UI.text(problem, 0.23, G.C.RED) }, { align = 'cl' }) end
    return {
        n = R,
        config = { align = 'cl', padding = 0.06, r = 0.1, colour = { 0, 0, 0, 0.18 }, minw = LW - 0.35 },
        nodes = {
            { n = C, config = { align = 'cm', minw = 0.1, minh = 0.62, r = 0.04, colour = col } },
            UI.spacer(0.1),
            { n = C, config = { align = 'cl', minw = 6.9 }, nodes = info },
            { n = C, config = { align = 'cm', tooltip = { text = { 'How often a seed passes this', 'filter during the search' } }, hover = true }, nodes = {
                UI.pill(function() return S.filter_rate(f) or '-' end, G.C.GREEN, 1.2, 0.42, 0.27),
            } },
            UI.spacer(0.08),
            UI.switch({ w = 0.88, get = function() return f.on ~= false end, set = function(v) f.on = v; persist() end }),
            UI.spacer(0.06),
            UI.button({ label = 'Edit', w = 0.85, h = 0.42, scale = 0.3, colour = col, on_click = function() edit(i) end }),
            UI.spacer(0.06),
            UI.button({ label = 'x', w = 0.45, h = 0.42, scale = 0.3, colour = G.C.RED, tooltip = { text = { 'Remove this filter' } }, on_click = function() remove(i) end }),
        },
    }
end

local function add_grid()
    local nodes = {}
    for _, id in ipairs(F.ORDER) do
        local t = F.TYPES[id]
        nodes[#nodes + 1] = UI.button({
            label = t.label, colour = t.colour(), w = 2.25, h = 0.58, scale = 0.33,
            tooltip = { text = { t.blurb } },
            on_click = function() add(id) end,
        })
    end
    return UI.flow(nodes, 5, { gap = 0.05 })
end

local function list_view()
    local list = filters()
    local rows = {}
    local page = st().page or 1
    local pages = math.max(1, math.ceil(#list / ROWS_PER_PAGE))
    page = FS.clamp(page, 1, pages)
    st().page = page
    if #list == 0 then
        rows[#rows + 1] = UI.row({ UI.notice('No filters yet', {
            'Add one below, or load a preset on the right.',
            'Every filter that is switched on must match.',
        }) }, { minh = 3.9 })
    else
        local first = (page - 1) * ROWS_PER_PAGE
        for i = first + 1, math.min(#list, first + ROWS_PER_PAGE) do
            rows[#rows + 1] = filter_row(i, list[i])
        end
    end
    local list_box = UI.col(rows, { align = 'tm', minh = 4.35, padding = 0.02 })
    local nav = {}
    if pages > 1 then
        nav = { UI.row({
            UI.button({ label = '<', w = 0.55, h = 0.34, scale = 0.28, colour = ACCENT(), on_click = function()
                st().page = page <= 1 and pages or page - 1; rebuild_left()
            end }),
            { n = C, config = { align = 'cm', minw = 2 }, nodes = { UI.text(('Page %d / %d'):format(page, pages), 0.27, UI.muted()) } },
            UI.button({ label = '>', w = 0.55, h = 0.34, scale = 0.28, colour = ACCENT(), on_click = function()
                st().page = page >= pages and 1 or page + 1; rebuild_left()
            end }),
        }, { padding = 0.02 }) }
    end
    local out = { UI.row({ list_box }) }
    for _, n in ipairs(nav) do out[#out + 1] = n end
    out[#out + 1] = UI.row({ UI.text('ADD A FILTER', 0.27, UI.muted()) }, { align = 'cl', padding = 0.04 })
    out[#out + 1] = UI.row({ add_grid() })
    return UI.col(out, { align = 'tm' })
end

-------------------------------------------------------------------------------
-- Editor view
-------------------------------------------------------------------------------
local function editor_view(i)
    local f = filters()[i]
    if not f then st().editing = nil; return list_view() end
    local t = F.TYPES[f.type]
    local col = t.colour()
    local function refresh(full)
        persist()
        if full then rebuild_left() end
    end
    local head = {
        n = R,
        config = { align = 'cl', padding = 0.06, r = 0.1, colour = { 0, 0, 0, 0.18 }, minw = LW - 0.35 },
        nodes = {
            { n = C, config = { align = 'cm', minw = 0.1, minh = 0.6, r = 0.04, colour = col } },
            UI.spacer(0.1),
            { n = C, config = { align = 'cl', minw = 8.35 }, nodes = {
                UI.row({ UI.text('EDITING  ' .. t.label:upper(), 0.25, col) }, { align = 'cl' }),
                UI.row({ UI.live(function()
                    local p = F.problem(f)
                    return p and ('! ' .. p) or F.describe(f)
                end, 0.3, G.C.UI.TEXT_LIGHT, { maxw = 8.2 }) }, { align = 'cl' }),
            } },
            UI.button({ label = 'Done', w = 1.35, h = 0.5, scale = 0.34, colour = G.C.GREEN, on_click = stop_editing }),
            UI.spacer(0.06),
            UI.confirm_button({ label = 'Delete', confirm_label = 'Sure?', w = 1.2, h = 0.5, scale = 0.3, colour = G.C.RED, on_click = function() remove(i) end }),
        },
    }
    local body = { head, UI.row({ UI.spacer(0.1, 0.06) }) }
    local ok, rows = xpcall(t.editor, debug.traceback, f, refresh)
    if not ok then
        FS.err(rows)
        rows = { UI.notice('This editor hit an error', { 'Details are in the log.' }, G.C.RED) }
    end
    for _, n in ipairs(rows) do body[#body + 1] = n end
    return UI.col(body, { align = 'tm' })
end

build_left = function()
    local node
    if st().editing and filters()[st().editing] then node = editor_view(st().editing) else node = list_view() end
    return UI.root({ node }, { align = 'tm', minw = LW - 0.2, minh = H - 0.55 })
end

-------------------------------------------------------------------------------
-- Search panel
-------------------------------------------------------------------------------
local function stat_line(label, get, colour)
    return UI.row({
        { n = C, config = { align = 'cl', minw = 2.1 }, nodes = { UI.text(label, 0.28, UI.muted()) } },
        { n = C, config = { align = 'cl', minw = 3.7 }, nodes = { UI.live(get, 0.31, colour or G.C.UI.TEXT_LIGHT, { maxw = 3.65 }) } },
    }, { align = 'cl', padding = 0.015 })
end

local function apply_preset(p, append)
    local fresh = F.from_preset(p)
    local list = filters()
    if not append then
        for i = #list, 1, -1 do list[i] = nil end
    end
    for _, f in ipairs(fresh) do list[#list + 1] = f end
    st().editing, st().page = nil, 1
    persist()
    rebuild_left()
    FS.toast((append and 'Added preset: ' or 'Loaded preset: ') .. p.name, G.C.GREEN, 'card1')
end

local function save_preset()
    local list = filters()
    if #list == 0 then return FS.warn('Add some filters first') end
    local name = F.summary(list)
    if #name > 44 then name = name:sub(1, 42) .. '...' end
    if name == '' then name = 'My preset' end
    table.insert(FS.config.presets, 1, { name = name, sub = ('%d filter%s'):format(#list, #list == 1 and '' or 's'), filters = FS.copy(list), user = true })
    persist()
    FS.toast('Saved your filters as a preset', G.C.GREEN, 'card1')
    FS.refresh()
end

local function presets_panel()
    local items = {}
    for _, p in ipairs(FS.config.presets) do items[#items + 1] = { preset = p, user = true } end
    for _, p in ipairs(F.PRESETS) do items[#items + 1] = { preset = p } end
    local grid = UI.group(items, function(it, w, h)
        local p = it.preset
        local btn = UI.button({
            label = p.name, sub = p.sub, colour = it.user and G.C.SECONDARY_SET.Planet or UI.tint(ACCENT(), 0.15),
            w = it.user and (w - 0.45) or w, h = h, scale = 0.27,
            tooltip = { text = { 'Click: replace your filters', 'Shift+click: add to them' } },
            on_click = function() apply_preset(p, love.keyboard.isDown('lshift', 'rshift')) end,
        })
        if not it.user then return btn end
        return UI.col({
            btn,
            UI.button({ label = 'x', w = 0.4, h = h, scale = 0.26, colour = G.C.RED, on_click = function()
                for i, q in ipairs(FS.config.presets) do if q == p then table.remove(FS.config.presets, i) break end end
                persist()
                FS.refresh()
            end }),
        }, { padding = 0 })
    end, { per_row = 2, max_rows = 4, width = RW - 0.25, h = 0.62, gap = 0.05, id = 'presets' })
    return grid
end

local function search_panel()
    local setup = FS.Seeds.setup()
    local start_btn = UI.button({
        label = function()
            if S.running then return S.phase == 'preparing' and 'Preparing...' or 'Stop search' end
            return 'Start search'
        end,
        sub = function() return S.running and 'Ctrl+P' or 'Ctrl+A' end,
        colour = G.C.GREEN, w = RW - 0.35, h = 0.85, scale = 0.5,
        on_click = function() S.toggle() end,
    })
    -- recolour the big button with the search state
    start_btn.config.func = 'fsgt_sync'
    start_btn.config.fs_sync = function(e)
        local on = S.running and true or false
        if on ~= e.config.fs_on then
            e.config.fs_on = on
            e.config.colour = on and G.C.RED or G.C.GREEN
        end
    end

    local last = function()
        local r = S.result
        if S.running then r = S.previous end
        if not r then return S.running and 'First search this session...' or 'No search yet this session' end
        if r.kind == 'found' then
            return ('Last: found %s after %s seeds (%s)%s'):format(r.seed, FS.fmt(r.tried), S.clock(r.elapsed), r.mismatch and ' - check it!' or '')
        end
        return ('Last: stopped after %s seeds (%s)'):format(FS.fmt(r.tried or 0), S.clock(r.elapsed))
    end

    return UI.section({ title = 'SEARCH', colour = ACCENT(), w = RW, h = H, align = 'tm', nodes = { UI.col({
        UI.row({ UI.text('Uses this run\'s deck & stake:', 0.26, UI.muted()) }, { align = 'cl' }),
        UI.row({ UI.text(FS.deck_name(setup.deck) .. '  -  ' .. FS.stake_name(setup.stake) .. ' Stake', 0.32, G.C.UI.TEXT_LIGHT, { maxw = RW - 0.4 }) }, { align = 'cl', padding = 0.02 }),
        UI.row({ start_btn }, { padding = 0.05 }),
        stat_line('Seeds checked', function() return FS.fmt(S.tried or 0) end),
        stat_line('Speed', function() return S.running and S.rate_text() or '-' end, G.C.FILTER),
        stat_line('Time', function() return S.clock(S.elapsed) end),
        stat_line('Odds', function() return S.stats and S.odds_text() or '-' end, G.C.GREEN),
        stat_line('', function() return S.running and S.eta_text() or '' end, UI.muted()),
        UI.row({ UI.live(last, 0.26, UI.muted(), { maxw = RW - 0.35 }) }, { align = 'cl', padding = 0.03 }),
        UI.row({
            UI.text('PRESETS', 0.27, UI.muted()),
            UI.spacer(1.6),
            UI.button({ label = 'Save mine', w = 1.55, h = 0.36, scale = 0.27, colour = G.C.SECONDARY_SET.Planet, on_click = save_preset }),
            UI.spacer(0.06),
            UI.confirm_button({ label = 'Clear all', confirm_label = 'Sure?', w = 1.45, h = 0.36, scale = 0.27, colour = G.C.RED, on_click = function()
                local list = filters()
                for i = #list, 1, -1 do list[i] = nil end
                st().editing = nil
                persist()
                rebuild_left()
            end }),
        }, { align = 'cl', padding = 0.03 }),
        UI.row({ presets_panel() }),
    }, { align = 'tm' }) } })
end

local function build()
    if not FS.in_run() then
        return UI.notice('Start a run first', { 'The seed finder uses your run\'s deck and stake.', 'Pick any deck, then come back here.' })
    end
    local left = UI.section({
        title = 'FILTERS', subtitle = 'a seed has to match every filter that is on', colour = ACCENT(), w = LW, h = H, align = 'tm',
        nodes = { UI.slot('fsgt_finder_left', build_left, { minw = LW - 0.2, minh = H - 0.55 }) },
    })
    return UI.row({ left, UI.spacer(0.05), search_panel() }, { align = 'tm', padding = 0.03 })
end

FS.register_tab({
    id = 'finder', label = 'Seed Finder', colour = function() return G.C.SECONDARY_SET.Spectral end, order = 1, needs_run = true,
    build = build,
})
