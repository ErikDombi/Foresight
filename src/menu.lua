--- The overlay frame, hotkeys and integration hooks.
local FS = Foresight
local UI = FS.UI
local R, C, O = G.UIT.R, G.UIT.C, G.UIT.O

local DIM_ALPHA = { 0.3, 0.6, 0.85 }

function FS.is_open()
    return G.OVERLAY_MENU ~= nil and G.OVERLAY_MENU ~= true and G.OVERLAY_MENU.foresight == true
end

function FS.apply_dim()
    if FS.view.bg_colour then FS.view.bg_colour[4] = DIM_ALPHA[FS.config.dim] or 0.6 end
end

-------------------------------------------------------------------------------
-- Header
-------------------------------------------------------------------------------
local function badge(label, get, colour, minw)
    return {
        n = C,
        config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.BLACK, emboss = 0.04, minw = minw },
        nodes = { UI.text(label, 0.26, UI.muted()), UI.spacer(0.06), UI.live(get, 0.33, colour) },
    }
end

local function search_badge()
    return {
        n = C,
        config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.BLACK, emboss = 0.04, minw = 2.6, func = 'fsgt_sync', fs_sync = function(e)
            local on = FS.Search.running
            if on ~= e.config.fs_on then
                e.config.fs_on = on
                e.config.colour = on and UI.tint(G.C.SECONDARY_SET.Spectral, 0.45) or G.C.BLACK
            end
        end },
        nodes = { UI.live(function()
            local S = FS.Search
            if S.running then
                if S.phase == 'preparing' then return 'finder: preparing' end
                return 'finder: ' .. FS.fmt(S.tried) .. ' seeds'
            end
            return 'finder idle'
        end, 0.28, G.C.UI.TEXT_LIGHT) },
    }
end

local function header()
    local title = {
        { n = O, config = { object = DynaText({ string = { 'FORE' }, colours = { G.C.UI.TEXT_LIGHT }, shadow = true, float = true, scale = 0.62, silent = true, pop_in = 0, pop_in_rate = 4 }) } },
        { n = O, config = { object = DynaText({ string = { 'SIGHT' }, colours = { G.C.SECONDARY_SET.Spectral }, shadow = true, float = true, scale = 0.62, silent = true, pop_in = 0.15, pop_in_rate = 4 }) } },
        UI.spacer(0.15),
        { n = C, config = { align = 'bl', padding = 0.02 }, nodes = {
            UI.text(('seeds, forecasts & save states  -  %s to close'):format(string.upper(FS.config.hotkey or 'f3')), 0.26, UI.muted()),
        } },
    }
    local right = {}
    if FS.in_run() then
        local gm = G.GAME
        right = {
            badge('SEED', function() return gm.pseudorandom.seed end, G.C.FILTER), UI.spacer(0.07),
            badge('DECK', function() return FS.deck_name(FS.current_deck_key()) .. '  ' .. FS.stake_name(gm.stake) end, G.C.UI.TEXT_LIGHT), UI.spacer(0.07),
            badge('ANTE', function() return FS.fmt(gm.round_resets.ante) end, G.C.FILTER), UI.spacer(0.07),
        }
    end
    right[#right + 1] = search_badge()
    return UI.row({
        { n = C, config = { align = 'cl', minw = 7.2 }, nodes = title },
        { n = C, config = { align = 'cr', minw = UI.W - 7.2 }, nodes = right },
    }, { padding = 0.02 })
end

-------------------------------------------------------------------------------
-- Tabs
-------------------------------------------------------------------------------
local function tab_bar()
    local in_run = FS.in_run()
    local nodes = {}
    for _, t in ipairs(FS.TABS) do
        local enabled = in_run or not t.needs_run
        local col = t.colour()
        nodes[#nodes + 1] = UI.chip({
            label = t.label, w = 2.95, h = 0.56, scale = 0.38, colour = col,
            off_colour = enabled and UI.tint(col, 0.32) or G.C.UI.BACKGROUND_INACTIVE,
            tooltip = (not enabled) and { text = { 'Start a run to use this tab' } } or nil,
            selected = function() return FS.state.tab == t.id end,
            on_click = function()
                if not enabled then return FS.warn('Start a run to use the ' .. t.label .. ' tab') end
                FS.switch_tab(t.id)
            end,
        })
    end
    return UI.row(nodes, { padding = 0.05 })
end

function FS.build_content()
    FS.view.wheel_target = nil
    local def = FS.TAB_BY_ID[FS.state.tab]
    local ok, node = xpcall(def.build, debug.traceback)
    if not ok then
        FS.err(node)
        node = UI.notice('This tab hit an error', { 'Details were written to the log.', 'Other tabs still work.' }, G.C.RED)
    end
    return UI.root({ node }, { minw = UI.W, minh = UI.H, align = 'tm' })
end

function FS.switch_tab(id)
    if FS.state.tab == id then return end
    FS.state.tab = id
    FS.refresh()
end

function FS.refresh()
    if not FS.is_open() then return end
    if G.CONTROLLER.text_input_hook then G.CONTROLLER.text_input_hook = nil end
    UI.replace('fsgt_content', FS.build_content)
end

-------------------------------------------------------------------------------
-- Frame
-------------------------------------------------------------------------------
local function footer()
    return UI.row({
        { n = C, config = { align = 'cl', minw = UI.W - 3.0, minh = 0.5, padding = 0.05 }, nodes = {
            { n = C, config = { align = 'cm', minw = 0.1, minh = 0.32, r = 0.05, colour = G.C.SECONDARY_SET.Spectral } },
            UI.spacer(0.12),
            { n = O, config = { ref_table = FS.view, ref_value = 'status', object = FS.view.status } },
        } },
        UI.button({ label = 'Close', w = 2.8, h = 0.55, colour = G.C.ORANGE, on_click = function() FS.close() end }),
    }, { padding = 0.02 })
end

local function frame()
    FS.view.bg_colour = { G.C.GREY[1], G.C.GREY[2], G.C.GREY[3], DIM_ALPHA[FS.config.dim] or 0.6 }
    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', minw = G.ROOM.T.w * 5, minh = G.ROOM.T.h * 5, padding = 0.1, r = 0.1, colour = FS.view.bg_colour },
        nodes = {
            { n = R, config = { align = 'cm', r = 0.3, padding = 0.07, colour = G.C.JOKER_GREY, emboss = 0.1 }, nodes = {
                { n = C, config = { align = 'cm', r = 0.2, padding = 0.12, colour = G.C.L_BLACK }, nodes = {
                    header(),
                    tab_bar(),
                    UI.row({ UI.slot('fsgt_content', FS.build_content, { minw = UI.W, minh = UI.H }) }),
                    footer(),
                } },
            } },
        },
    }
end

-------------------------------------------------------------------------------
-- Open / close
-------------------------------------------------------------------------------
function FS.open(tab)
    if not G.ROOM or G.STAGE == G.STAGES.SPLASH then return end
    if tab then FS.state.tab = tab end
    local def = FS.TAB_BY_ID[FS.state.tab]
    if not def or (def.needs_run and not FS.in_run()) then FS.state.tab = FS.in_run() and 'finder' or 'seeds' end
    if G.CONTROLLER.text_input_hook then G.CONTROLLER.text_input_hook = nil end

    -- Pause first: objects created while unpaused don't move while the game is paused.
    G.SETTINGS.paused = true
    local msg = FS.last_msg or ('Welcome! ' .. (FS.in_run() and 'Build some filters, or peek at what is coming.' or 'Start a run to unlock every tab.'))
    local col = (FS.last_msg and FS.last_col) or G.C.UI.TEXT_LIGHT
    FS.view.status = DynaText({ string = { msg }, colours = { col }, shadow = true, silent = true, pop_in = 0, pop_in_rate = 6, scale = 0.36, maxw = 11 })

    local prev = G.OVERLAY_MENU
    local ok, err = xpcall(function()
        -- Build while flagged as an overlay (like the game does) so preview cards never count as
        -- "owned" by the run - otherwise they would be kept out of shops and packs.
        if not prev then G.OVERLAY_MENU = true end
        local definition = frame()
        if G.OVERLAY_MENU == true then G.OVERLAY_MENU = nil end
        G.FUNCS.overlay_menu({ definition = definition })
    end, debug.traceback)
    if G.OVERLAY_MENU == true then G.OVERLAY_MENU = nil end
    if not ok then
        FS.err(err)
        if G.OVERLAY_MENU and G.OVERLAY_MENU ~= true then G.FUNCS.exit_overlay_menu() end
        G.SETTINGS.paused = false
        return
    end
    G.OVERLAY_MENU.foresight = true
    FS.sfx('cardSlide1', 1.05, 0.6)
end

function FS.close()
    if FS.is_open() then
        G.FUNCS.exit_overlay_menu()
        FS.sfx('cardSlide2', 1, 0.5)
    end
end

G.FUNCS.fsgt_open = function() FS.open() end

function FS.on_hotkey()
    if FS.capturing or G.CONTROLLER.text_input_hook then return end
    if FS.is_open() then return FS.close() end
    if G.OVERLAY_MENU then return end
    FS.open()
end

FS.keybind = FS.keybind or SMODS.Keybind({
    key = 'open_menu',
    key_pressed = FS.config.hotkey or 'f3',
    action = function() FS.safe(FS.on_hotkey) end,
})

-------------------------------------------------------------------------------
-- Brainstorm-style hotkeys
-------------------------------------------------------------------------------
local DIGITS = { ['1'] = 1, ['2'] = 2, ['3'] = 3, ['4'] = 4, ['5'] = 5, ['6'] = 6, ['7'] = 7, ['8'] = 8, ['9'] = 9, ['0'] = 10 }

local function ctrl() return love.keyboard.isDown('lctrl', 'rctrl') end
local function shift() return love.keyboard.isDown('lshift', 'rshift') end
local function down(k) return k and k ~= '' and love.keyboard.isDown(k) end

local function held_digit()
    for k, n in pairs(DIGITS) do
        if love.keyboard.isDown(k) then return n end
    end
end

--- Returns true when Foresight used the key press.
function FS.handle_key(key)
    if G.CONTROLLER.text_input_hook or G.STAGE == G.STAGES.SPLASH then return false end
    local cfg = FS.config
    if cfg.hotkeys.states and not ctrl() then
        local n = DIGITS[key]
        if n then
            if down(cfg.keys.save_mod) then FS.States.save_slot(n) return true end
            if down(cfg.keys.load_mod) then FS.States.load_slot(n) return true end
        end
        if key == cfg.keys.save_mod or key == cfg.keys.load_mod then
            local d = held_digit()
            if d then
                if key == cfg.keys.save_mod then FS.States.save_slot(d) else FS.States.load_slot(d) end
                return true
            end
        end
    end
    if ctrl() then
        if key == 't' and cfg.hotkeys.reroll then
            if shift() then FS.Seeds.replay() else FS.Seeds.reroll() end
            return true
        end
        if key == 'a' and cfg.hotkeys.search then FS.Search.toggle() return true end
        if key == 'p' and cfg.hotkeys.search then
            if FS.Search.running then FS.Search.stop('user') end
            return true
        end
        if key == 'z' and cfg.hotkeys.rewind then
            if shift() then FS.States.step_forward() else FS.States.step_back() end
            return true
        end
        if key == 'y' and cfg.hotkeys.rewind then FS.States.step_forward() return true end
    end
    return false
end

-------------------------------------------------------------------------------
-- Hooks (installed once, so modules can be hot-reloaded)
-------------------------------------------------------------------------------
if not FS._hooks then
    FS._hooks = true

    local key_press_ref = Controller.key_press_update
    function Controller:key_press_update(key, dt)
        if FS.capturing then
            local what = FS.capturing
            FS.capturing = nil
            if key == 'escape' then
                FS.toast('Key unchanged', G.C.UI.TEXT_LIGHT, 'cancel')
            elseif what == 'menu' then
                FS.config.hotkey = key
                if FS.keybind then FS.keybind.key_pressed = key end
                FS.save_config()
                FS.toast('Menu hotkey is now ' .. string.upper(key), G.C.GREEN, 'generic1')
            else
                FS.config.keys[what] = key
                FS.save_config()
                FS.toast(('%s key is now %s'):format(what == 'save_mod' and 'Save' or 'Load', string.upper(key)), G.C.GREEN, 'generic1')
            end
            if FS.is_open() then FS.refresh() end
            return
        end
        local ok, used = pcall(FS.handle_key, key)
        if not ok then FS.err(used) end
        if ok and used then return end
        return key_press_ref(self, key, dt)
    end

    local update_ref = love.update
    function love.update(dt)
        update_ref(dt)
        if FS.Search and FS.Search.running then
            local ok, err = xpcall(FS.Search.update, debug.traceback)
            if not ok then
                FS.err(err)
                FS.Search.running = false
                FS.Search.hide_hud()
            end
        end
    end

    local wheel_ref = love.wheelmoved
    function love.wheelmoved(x, y)
        if wheel_ref then wheel_ref(x, y) end
        if y ~= 0 and FS.is_open() and not G.CONTROLLER.text_input_hook then
            local def = FS.TAB_BY_ID[FS.state.tab]
            if def and def.wheel then FS.safe(def.wheel, y)
            elseif FS.view.wheel_target then FS.safe(FS.view.wheel_target, y > 0 and -1 or 1) end
        end
    end

    local start_run_ref = Game.start_run
    function Game:start_run(args, ...)
        local ret = start_run_ref(self, args, ...)
        pcall(FS.Seeds.on_run_started, args)
        return ret
    end

    local save_run_ref = save_run
    function save_run(...)
        local ret = save_run_ref(...)
        if FS.States then
            local ok, err = pcall(FS.States.on_autosave)
            if not ok then FS.err(err) end
        end
        if FS.Seeds then pcall(FS.Seeds.track) end
        return ret
    end

    -- More game speed options (Brainstorm added these through a patch).
    local option_cycle_ref = create_option_cycle
    function create_option_cycle(args)
        if args and args.opt_callback == 'change_gamespeed' and FS.config.extended_speed then
            local speeds = { 0.5, 1, 2, 4, 8, 16, 32, 64 }
            local cur, idx = G.SETTINGS.GAMESPEED, 2
            for i, v in ipairs(speeds) do if v == cur then idx = i end end
            args.options = speeds
            args.current_option = idx
        end
        return option_cycle_ref(args)
    end

    -- A Foresight button in the pause / options menu.
    local options_ref = create_UIBox_options
    function create_UIBox_options(...)
        local t = options_ref(...)
        local ok = pcall(function()
            local contents = t.nodes[1].nodes[1].nodes[1].nodes
            local last = 0
            for k in pairs(contents) do if type(k) == 'number' and k > last then last = k end end
            contents[last + 1] = UIBox_button({ label = { 'Foresight' }, button = 'fsgt_open', minw = 5, colour = G.C.SECONDARY_SET.Spectral })
        end)
        if not ok then FS.log('could not add the options-menu button') end
        return t
    end
end

-- Mods-menu config tab.
FS.mod.config_tab = function()
    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.2, r = 0.1, colour = G.C.BLACK, minw = 8, minh = 4 },
        nodes = {
            UI.row({ UI.text('Foresight', 0.6, G.C.SECONDARY_SET.Spectral) }, { padding = 0.1 }),
            UI.row({ UI.text(('Press %s to open the menu.'):format(string.upper(FS.config.hotkey or 'f3')), 0.36) }, { padding = 0.05 }),
            UI.row({ UI.text('Ctrl+T new run  -  Ctrl+A seed finder  -  Ctrl+Z undo  -  Z/X + number save/load', 0.3, UI.muted()) }, { padding = 0.05 }),
            UI.row({ UIBox_button({ label = { 'Open Foresight' }, button = 'fsgt_open', minw = 4, colour = G.C.SECONDARY_SET.Spectral }) }, { padding = 0.15 }),
        },
    }
end

FS.log(('Foresight %s loaded - press %s to open'):format(FS.VERSION, string.upper(FS.config.hotkey or 'f3')))
