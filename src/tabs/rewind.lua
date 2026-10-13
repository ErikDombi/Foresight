--- Rewind tab: every autosave becomes a checkpoint you can jump back to.
local FS = Foresight
local UI, ST = FS.UI, FS.States
local R, C = G.UIT.R, G.UIT.C

local ACCENT = function() return G.C.ORANGE end
local PER_PAGE = 9
local LW, RW, H = 12.4, 6.0, 7.55

local function st() return FS.state.rewind end

local function row(i, e, current)
    local m = e.meta or {}
    local col = current and G.C.GREEN or G.C.UI.BACKGROUND_INACTIVE
    local desc = ('Ante %s  -  %s  -  %s  -  $%s'):format(tostring(m.ante or '?'), tostring(m.blind or '?'), tostring(m.state or '?'), tostring(m.dollars or '?'))
    local sub = ('%s  -  %s  -  hand %s  -  %d joker%s'):format(tostring(m.seed or '?'), FS.deck_name(m.deck), tostring(m.hand_no or '?'), m.njokers or 0, (m.njokers or 0) == 1 and '' or 's')
    local nodes = {
        { n = C, config = { align = 'cm', minw = 0.1, minh = 0.6, r = 0.04, colour = col } },
        UI.spacer(0.1),
        { n = C, config = { align = 'cl', minw = 1.55 }, nodes = {
            UI.row({ UI.text(FS.clock(e.t), 0.28, G.C.UI.TEXT_LIGHT) }, { align = 'cl' }),
            UI.row({ UI.text(FS.ago(e.t), 0.22, UI.muted()) }, { align = 'cl' }),
        } },
        { n = C, config = { align = 'cl', minw = 6.75 }, nodes = {
            UI.row({ UI.text(desc, 0.29, G.C.UI.TEXT_LIGHT, { maxw = 6.7 }) }, { align = 'cl' }),
            UI.row({ UI.text(sub, 0.22, UI.muted(), { maxw = 6.7 }) }, { align = 'cl' }),
        } },
    }
    if current then
        nodes[#nodes + 1] = { n = C, config = { align = 'cm', minw = 2.35 }, nodes = {
            { n = C, config = { align = 'cm', padding = 0.05, r = 0.06, colour = G.C.GREEN }, nodes = { UI.text('YOU ARE HERE', 0.24, G.C.WHITE) } },
        } }
    else
        nodes[#nodes + 1] = UI.button({ label = 'Go here', w = 1.3, h = 0.42, scale = 0.28, colour = ACCENT(), on_click = function() ST.goto(i) end })
        nodes[#nodes + 1] = UI.spacer(0.05)
        nodes[#nodes + 1] = UI.button({ label = 'Keep', w = 0.95, h = 0.42, scale = 0.28, colour = G.C.GREEN,
            tooltip = { text = { 'Copy this checkpoint into', 'the first free save slot' } },
            on_click = function()
                local n = ST.first_free_slot()
                if not n then return FS.warn('All 10 save slots are full') end
                ST.pin(i, n)
            end })
    end
    return { n = R, config = { align = 'cl', padding = 0.05, r = 0.1, colour = current and UI.tint(G.C.GREEN, 0.75) or { 0, 0, 0, 0.18 }, minw = LW - 0.35 }, nodes = nodes }
end

local function build_list()
    local tl = ST.timeline
    local cur = FS.in_run() and ST.current_index() or nil
    local live_matches = cur and tl[cur] and (ST.pos ~= nil or tl[cur].sig == ST.signature())
    local rows = {}
    local pages = math.max(1, math.ceil(#tl / PER_PAGE))
    local page = FS.clamp(st().page or 1, 1, pages)
    st().page = page
    FS.view.rewind_pages = pages
    if #tl == 0 then
        rows[#rows + 1] = UI.row({ UI.notice('No checkpoints yet', {
            'The game autosaves at the start of every hand, shop and blind choice.',
            'Each autosave lands here - play a little and they will appear.',
        }) }, { minh = 6 })
    else
        -- newest first
        local order = {}
        for i = #tl, 1, -1 do order[#order + 1] = i end
        local first = (page - 1) * PER_PAGE
        for k = first + 1, math.min(#order, first + PER_PAGE) do
            local i = order[k]
            rows[#rows + 1] = row(i, tl[i], live_matches and i == cur)
        end
    end
    return UI.root({ UI.col(rows, { align = 'tm', padding = 0.02 }) }, { align = 'tm', minw = LW - 0.2, minh = 6.35 })
end

local function turn(d)
    local pages = FS.view.rewind_pages or 1
    local p = (st().page or 1) + d
    if p < 1 then p = pages elseif p > pages then p = 1 end
    st().page = p
    FS.sfx('paper1', 1.05, 0.4)
    UI.replace('fsgt_rewind_list', build_list)
end

local function build()
    local left = UI.section({
        title = 'TIMELINE', subtitle = 'a checkpoint every time the game autosaves  -  newest first', colour = ACCENT(), w = LW, h = H, align = 'tm',
        nodes = { UI.col({
            UI.row({ UI.slot('fsgt_rewind_list', build_list, { minw = LW - 0.2, minh = 6.35 }) }),
            UI.row({
                UI.button({ label = '<', w = 0.55, h = 0.36, scale = 0.3, colour = ACCENT(), on_click = function() turn(-1) end }),
                { n = C, config = { align = 'cm', minw = 2.6 }, nodes = { UI.live(function()
                    return ('Page %d / %d'):format(st().page or 1, FS.view.rewind_pages or 1)
                end, 0.27, UI.muted()) } },
                UI.button({ label = '>', w = 0.55, h = 0.36, scale = 0.3, colour = ACCENT(), on_click = function() turn(1) end }),
            }, { padding = 0.02 }),
        }, { align = 'tm' }) },
    })

    local kb = 0
    for _, e in ipairs(ST.timeline) do kb = kb + #(e.data or '') end
    local keep_items = {}
    for _, n in ipairs({ 20, 40, 80, 150 }) do keep_items[#keep_items + 1] = { key = n, label = tostring(n) } end
    local right = UI.section({
        title = 'UNDO & REDO', colour = ACCENT(), w = RW, h = H, align = 'tm',
        nodes = { UI.col({
            UI.row({ UI.button({ label = 'Undo', sub = 'Ctrl+Z  -  back one checkpoint', w = RW - 0.4, h = 0.85, scale = 0.46, colour = ACCENT(),
                enabled = function() return FS.in_run() and #ST.timeline > 0 end,
                on_click = function() ST.step_back() end }) }, { padding = 0.04 }),
            UI.row({ UI.button({ label = 'Redo', sub = 'Ctrl+Y  -  after an undo', w = RW - 0.4, h = 0.7, scale = 0.4, colour = G.C.BLUE,
                enabled = function() return ST.pos ~= nil and ST.pos < #ST.timeline end,
                on_click = function() ST.step_forward() end }) }, { padding = 0.04 }),
            UI.row({ UI.spacer(0.1, 0.1) }),
            UI.row({ UI.text('Undo restores the moment the game last saved:', 0.26, UI.muted()) }, { align = 'cl' }),
            UI.row({ UI.text('before each hand, each shop and each blind choice.', 0.26, UI.muted()) }, { align = 'cl' }),
            UI.row({ UI.text('Playing on after an undo starts a new branch.', 0.26, UI.muted()) }, { align = 'cl' }),
            UI.row({ UI.text('They last until you quit - Keep saves one to a slot.', 0.26, UI.muted()) }, { align = 'cl' }),
            UI.row({ UI.spacer(0.1, 0.15) }),
            UI.row({
                { n = C, config = { align = 'cl', minw = 2.6 }, nodes = { UI.text('Record checkpoints', 0.29, G.C.UI.TEXT_LIGHT) } },
                UI.switch({ get = function() return FS.config.rewind.enabled end, set = function(v) FS.config.rewind.enabled = v; FS.save_config() end }),
            }, { align = 'cl', padding = 0.04 }),
            UI.row({ UI.text('Checkpoints to keep', 0.27, UI.muted()) }, { align = 'cl' }),
            UI.row({ UI.radio(keep_items, FS.config.rewind, 'keep', { per_row = 4, w = 1.25, h = 0.4, colour = ACCENT(), on_change = function() FS.save_config() end }) }),
            UI.row({ UI.spacer(0.1, 0.12) }),
            UI.row({ UI.text(('%d checkpoint%s in memory  -  %d KB'):format(#ST.timeline, #ST.timeline == 1 and '' or 's', math.floor(kb / 1024 + 0.5)), 0.26, UI.muted()) }),
            UI.row({ UI.confirm_button({ label = 'Clear timeline', confirm_label = 'Click again to clear', w = 3.2, h = 0.45, scale = 0.3, colour = G.C.RED,
                on_click = function() ST.clear_timeline(); FS.refresh() end }) }, { padding = 0.04 }),
        }, { align = 'tm' }) },
    })
    return UI.row({ left, UI.spacer(0.05), right }, { align = 'tm', padding = 0.03 })
end

FS.register_tab({
    id = 'rewind', label = 'Rewind', colour = function() return G.C.ORANGE end, order = 4, needs_run = true,
    build = build,
    wheel = function(y) turn(y > 0 and -1 or 1) end,
})
