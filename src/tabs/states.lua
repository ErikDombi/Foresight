--- Save States tab: ten slots with a preview of what each one holds.
local FS = Foresight
local UI, ST = FS.UI, FS.States
local R, C = G.UIT.R, G.UIT.C

local ACCENT = function() return G.C.GREEN end
local SLOT_W, SLOT_H = 9.2, 1.36

local function slot_card(n)
    local m = ST.info(n)
    local filled = m ~= nil
    local in_run = FS.in_run()
    local num_col = filled and UI.tint(ACCENT(), 0.25) or G.C.UI.BACKGROUND_INACTIVE
    local num = { n = C, config = { align = 'cm', minw = 0.72, minh = SLOT_H - 0.14, r = 0.1, colour = num_col }, nodes = {
        UI.text(n == 10 and '0' or tostring(n), 0.62, G.C.UI.TEXT_LIGHT),
    } }

    local info
    if filled and not m.broken then
        local line2 = ('%s  -  %s Stake  -  %s'):format(FS.deck_name(m.deck), FS.stake_name(m.stake), tostring(m.seed or '?'))
        local line3 = (m.t and FS.ago(m.t) or 'saved earlier') .. ('  -  %d joker%s'):format(m.njokers or #(m.jokers or {}), (m.njokers or 0) == 1 and '' or 's')
        if m.note then line3 = line3 .. '  -  ' .. m.note end
        info = {
            UI.row({ UI.text(('Ante %s  -  %s  -  $%s'):format(tostring(m.ante or '?'), tostring(m.blind or m.state or '?'), tostring(m.dollars or '?')), 0.3, G.C.UI.TEXT_LIGHT, { maxw = 3.5 }) }, { align = 'cl' }),
            UI.row({ UI.text(line2, 0.23, UI.muted(), { maxw = 3.5 }) }, { align = 'cl' }),
            UI.row({ UI.text(line3, 0.23, UI.muted(), { maxw = 3.5 }) }, { align = 'cl' }),
        }
    elseif filled then
        info = { UI.row({ UI.text('This file could not be read', 0.28, G.C.RED) }, { align = 'cl' }) }
    else
        info = {
            UI.row({ UI.text('Empty slot', 0.3, UI.muted()) }, { align = 'cl' }),
            UI.row({ UI.text(('Hold %s and press %s to save here'):format(string.upper(FS.config.keys.save_mod), n == 10 and '0' or tostring(n)), 0.23, UI.muted()) }, { align = 'cl' }),
        }
    end

    local jokers = {}
    for i, j in ipairs(m and m.jokers or {}) do
        if i > 5 then break end
        jokers[#jokers + 1] = { key = j.key, edition = j.edition }
    end

    local buttons = {}
    if filled then
        buttons[#buttons + 1] = UI.row({ UI.button({ label = 'Load', w = 1.2, h = 0.38, scale = 0.3, colour = G.C.BLUE, on_click = function() ST.load_slot(n) end }) }, { padding = 0.02 })
    end
    buttons[#buttons + 1] = UI.row({ (filled and UI.confirm_button or UI.button)({
        label = 'Save', confirm_label = 'Overwrite?', w = 1.2, h = 0.38, scale = 0.3, colour = G.C.GREEN,
        enabled = function() return FS.in_run() end,
        on_click = function() ST.save_slot(n); FS.refresh() end,
    }) }, { padding = 0.02 })
    if filled then
        buttons[#buttons + 1] = UI.row({ UI.confirm_button({ label = 'Clear', confirm_label = 'Sure?', w = 1.2, h = 0.3, scale = 0.24, colour = G.C.UI.BACKGROUND_INACTIVE,
            on_click = function() ST.clear_slot(n); FS.refresh() end }) }, { padding = 0.02 })
    end

    return {
        n = C,
        config = { align = 'cm', padding = 0.07, r = 0.12, colour = filled and { 0, 0, 0, 0.28 } or { 0, 0, 0, 0.14 }, minw = SLOT_W, minh = SLOT_H },
        nodes = {
            num,
            UI.spacer(0.12),
            { n = C, config = { align = 'cl', minw = 3.55 }, nodes = info },
            { n = C, config = { align = 'cm', minw = 3.0 }, nodes = { #jokers > 0 and UI.card_strip(jokers, { scale = 0.26, slots = 5, materialize = false }) or UI.spacer(0.1) } },
            { n = C, config = { align = 'cm', minw = 1.3 }, nodes = buttons },
        },
    }
end

local function build()
    local left, right = {}, {}
    for n = 1, 5 do left[#left + 1] = UI.row({ slot_card(n) }, { padding = 0.035 }) end
    for n = 6, 10 do right[#right + 1] = UI.row({ slot_card(n) }, { padding = 0.035 }) end
    local save, load = string.upper(FS.config.keys.save_mod), string.upper(FS.config.keys.load_mod)
    return UI.col({
        UI.row({
            UI.text(('Hold %s + a number to save, %s + a number to load  -  slot 10 is the 0 key  -  saves survive restarts'):format(save, load), 0.28, UI.muted()),
        }, { padding = 0.03 }),
        UI.row({ UI.col(left, { align = 'tm' }), UI.spacer(0.06), UI.col(right, { align = 'tm' }) }, { align = 'tm' }),
    }, { align = 'tm' })
end

FS.register_tab({
    id = 'states', label = 'Save States', colour = function() return G.C.GREEN end, order = 3,
    build = build,
})
