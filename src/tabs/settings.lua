--- Settings tab: hotkeys, seed finder, rewind and game options.
local FS = Foresight
local UI = FS.UI
local R, C = G.UIT.R, G.UIT.C

local W, H = 6.05, 7.55
local ACCENT = function() return G.C.UI.BACKGROUND_INACTIVE end

local function save() FS.save_config() end

local function line(label, node, sub)
    local left = { UI.row({ UI.text(label, 0.29, G.C.UI.TEXT_LIGHT, { maxw = 3.6 }) }, { align = 'cl' }) }
    if sub then left[#left + 1] = UI.row({ UI.text(sub, 0.22, UI.muted(), { maxw = 3.6 }) }, { align = 'cl' }) end
    return UI.row({
        { n = C, config = { align = 'cl', minw = 3.7 }, nodes = left },
        { n = C, config = { align = 'cr', minw = 1.95 }, nodes = { node } },
    }, { align = 'cl', padding = 0.04 })
end

local function switch(tbl, field)
    return UI.switch({ get = function() return tbl[field] and true or false end, set = function(v) tbl[field] = v; save() end })
end

local function key_button(what, get)
    return UI.button({
        label = function()
            if FS.capturing == what then return 'Press a key' end
            return string.upper(get() or '?')
        end,
        w = 1.85, h = 0.42, scale = 0.3, colour = G.C.BLUE,
        on_click = function()
            FS.capturing = what
            FS.toast('Press the new key (Esc cancels)', G.C.FILTER, 'generic1')
        end,
    })
end

local function heading(t)
    return UI.row({ UI.text(t, 0.27, UI.muted()) }, { align = 'cl', padding = 0.04 })
end

local function hotkeys()
    local cfg = FS.config
    return UI.section({ title = 'HOTKEYS', colour = G.C.BLUE, w = W, h = H, align = 'tm', nodes = { UI.col({
        line('Open Foresight', key_button('menu', function() return cfg.hotkey end)),
        line('Save state key', key_button('save_mod', function() return cfg.keys.save_mod end), 'hold it and press 1-9 / 0'),
        line('Load state key', key_button('load_mod', function() return cfg.keys.load_mod end), 'hold it and press 1-9 / 0'),
        heading('TURN SHORTCUTS ON OR OFF'),
        line('Save / load states', switch(cfg.hotkeys, 'states'), 'the keys above + a number'),
        line('New run / restart', switch(cfg.hotkeys, 'reroll'), 'Ctrl+T  /  Ctrl+Shift+T'),
        line('Seed finder', switch(cfg.hotkeys, 'search'), 'Ctrl+A start or stop  -  Ctrl+P stop'),
        line('Undo / redo', switch(cfg.hotkeys, 'rewind'), 'Ctrl+Z  /  Ctrl+Y'),
    }, { align = 'tm' }) } })
end

local function finder()
    local s = FS.config.search
    local budgets = {
        { key = 4, label = '4 ms' }, { key = 8, label = '8 ms' }, { key = 12, label = '12 ms' },
        { key = 20, label = '20 ms' }, { key = 33, label = '33 ms' },
    }
    local limits = {
        { key = 0, label = 'Never' }, { key = 100000, label = '100k' }, { key = 1000000, label = '1M' }, { key = 10000000, label = '10M' },
    }
    return UI.section({ title = 'SEED FINDER', colour = G.C.SECONDARY_SET.Spectral, w = W, h = H, align = 'tm', nodes = { UI.col({
        heading('TIME SPENT SEARCHING EACH FRAME'),
        UI.row({ UI.radio(budgets, s, 'budget_ms', { per_row = 5, w = 1.08, h = 0.42, colour = G.C.SECONDARY_SET.Spectral, on_change = save }) }),
        UI.row({ UI.text('More is faster but can make the game stutter.', 0.23, UI.muted()) }, { align = 'cl' }),
        heading('GIVE UP AFTER'),
        UI.row({ UI.radio(limits, s, 'max_seeds', { per_row = 4, w = 1.35, h = 0.42, colour = G.C.SECONDARY_SET.Spectral, on_change = save }) }),
        UI.row({ UI.spacer(0.1, 0.12) }),
        line('Found seeds count', switch(s, 'unseeded'), 'like a normal run (unlocks, stats)'),
        UI.row({ UI.text('Brainstorm worked this way too. Switch off to', 0.23, UI.muted()) }, { align = 'cl' }),
        UI.row({ UI.text('play found seeds as ordinary seeded runs.', 0.23, UI.muted()) }, { align = 'cl' }),
        UI.row({ UI.spacer(0.1, 0.12) }),
        heading('HOW IT WORKS'),
        UI.row({ UI.text('Predictions run the game\'s own code on a copy', 0.23, UI.muted()) }, { align = 'cl' }),
        UI.row({ UI.text('of the random state, so modded tags, jokers and', 0.23, UI.muted()) }, { align = 'cl' }),
        UI.row({ UI.text('packs count. Found seeds are double-checked.', 0.23, UI.muted()) }, { align = 'cl' }),
    }, { align = 'tm' }) } })
end

local function game()
    local dims = { { key = 1, label = 'Light' }, { key = 2, label = 'Medium' }, { key = 3, label = 'Dark' } }
    return UI.section({ title = 'GAME & LOOK', colour = G.C.ORANGE, w = W, h = H, align = 'tm', nodes = { UI.col({
        line('Faster game speeds', switch(FS.config, 'extended_speed'), 'adds 8x - 64x to Settings > Game'),
        line('Game speed now', UI.cycler({
            options = { { key = 0.5, label = '0.5x' }, { key = 1, label = '1x' }, { key = 2, label = '2x' }, { key = 4, label = '4x' },
                { key = 8, label = '8x' }, { key = 16, label = '16x' }, { key = 32, label = '32x' }, { key = 64, label = '64x' } },
            w = 0.9, h = 0.4, colour = G.C.ORANGE,
            get = function() return G.SETTINGS.GAMESPEED end,
            set = function(k) G.SETTINGS.GAMESPEED = k; G:save_settings() end,
        })),
        heading('MENU BACKGROUND'),
        UI.row({ UI.radio(dims, FS.config, 'dim', { per_row = 3, w = 1.75, h = 0.42, colour = G.C.ORANGE, on_change = function() FS.apply_dim(); save() end }) }),
        UI.row({ UI.spacer(0.1, 0.2) }),
        heading('ABOUT'),
        UI.row({ UI.text('Foresight ' .. FS.VERSION, 0.34, G.C.SECONDARY_SET.Spectral) }, { align = 'cl' }),
        UI.row({ UI.text('A replacement for Brainstorm: its save states,', 0.23, UI.muted()) }, { align = 'cl' }),
        UI.row({ UI.text('rerolls and auto-search, plus stackable filters,', 0.23, UI.muted()) }, { align = 'cl' }),
        UI.row({ UI.text('a crystal ball, undo and seed history.', 0.23, UI.muted()) }, { align = 'cl' }),
        UI.row({ UI.text('Brainstorm\'s save slots load from the same files.', 0.23, UI.muted()) }, { align = 'cl' }),
    }, { align = 'tm' }) } })
end

local function build()
    return UI.row({ hotkeys(), UI.spacer(0.05), finder(), UI.spacer(0.05), game() }, { align = 'tm', padding = 0.03 })
end

FS.register_tab({
    id = 'settings', label = 'Settings', colour = function() return G.C.UI.BACKGROUND_INACTIVE end, order = 6,
    build = build,
})
