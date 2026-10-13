--- The seed finder runner: tests seeds against the filters a few milliseconds per frame,
--- so the game stays smooth, then starts the first seed that matches.
local FS = Foresight
local UI, O, F = FS.UI, FS.Oracle, FS.Filters
local R, C = G.UIT.R, G.UIT.C

local S = FS.Search or {}
FS.Search = S

S.running = S.running or false
S.tried = S.tried or 0
S.rate = S.rate or 0
S.elapsed = S.elapsed or 0

--- Is the current run still exactly as it started (so it can stand in for any fresh run)?
function S.fresh_template()
    if not FS.in_run() then return false end
    local gm, fresh = G.GAME, FS.Seeds.fresh
    if not fresh or fresh.seed ~= gm.pseudorandom.seed then return false end
    if FS.num(gm.round_resets.ante) ~= 1 or (gm.round or 0) ~= 0 then return false end
    if G.STATE ~= G.STATES.BLIND_SELECT then return false end
    local bs = gm.round_resets.blind_states
    if bs and bs.Small ~= 'Select' then return false end
    return #G.jokers.cards == fresh.jokers and #G.consumeables.cards == fresh.cons and #G.playing_cards == fresh.cards
end

function S.can_start()
    if not FS.in_run() then return false, 'Start a run first - the finder uses its deck and stake' end
    local list = F.active(FS.config.filters)
    if #list == 0 then
        for _, f in ipairs(FS.config.filters) do
            local p = f.on ~= false and F.problem(f)
            if p then return false, p end
        end
        return false, 'Add a filter first'
    end
    return true
end

function S.start()
    if S.running then return end
    local ok, why = S.can_start()
    if not ok then return FS.notify(why, G.C.RED, 'cancel') end
    S.list = F.active(FS.config.filters)
    S.stats = {}
    for i, f in ipairs(S.list) do S.stats[i] = { evals = 0, passes = 0, f = f } end
    S.tried, S.rate, S.elapsed, S.found = 0, 0, 0, nil
    S.counter = 0
    S.base_num = (os.time() % 100003) * 0.000731 + (love.timer.getTime() % 1) * 0.37
    S.running = true
    S.started = love.timer.getTime()
    S.previous = S.result or S.previous
    S.result = nil
    S.reopen = FS.is_open and FS.is_open()
    if S.fresh_template() then
        S.begin_searching()
    else
        -- give the finder a pristine run of this deck and stake to predict from
        S.phase = 'preparing'
        S.wait = 3
        FS.Seeds.start({ keep_challenge = true, source = 'template' })
    end
    S.show_hud()
    FS.sfx('tarot1', 1.1, 0.5)
    FS.toast('Searching... (Ctrl+P stops)', G.C.SECONDARY_SET.Spectral, false)
end

function S.begin_searching()
    S.phase = 'searching'
    S.template_seed = G.GAME.pseudorandom.seed
    S.plan = F.plan(S.list, { erratic_n = #G.playing_cards })
    S.ctx = F.make_ctx(S.plan)
    S.warm = false
    S.started = love.timer.getTime()
    if S.reopen and not FS.is_open() then FS.open('finder') end
    S.reopen = nil
end

function S.stop(reason)
    if not S.running then return end
    S.running = false
    S.phase = nil
    S.hide_hud()
    S.result = S.result or { kind = 'stopped', tried = S.tried, elapsed = S.elapsed, reason = reason }
    if reason and reason ~= 'found' then
        FS.notify('Search stopped' .. ((reason == 'user') and '' or (' - ' .. reason)), G.C.UI.TEXT_INACTIVE, 'cancel')
    end
end

function S.toggle()
    if S.running then S.stop('user') else S.start() end
end

local function next_seed()
    S.counter = S.counter + 1
    return random_string(8, S.base_num + S.counter * 0.561892350821)
end

function S.update()
    if not S.running then return end
    if S.hud then S.hud.states.visible = not (FS.is_open and FS.is_open()) end
    if S.phase == 'preparing' then
        S.wait = S.wait - 1
        if S.wait <= 0 then
            if S.fresh_template() then S.begin_searching()
            elseif S.wait < -120 then S.stop('could not prepare a fresh run') end
        end
        return
    end
    if not FS.in_run() then return S.stop('left the run') end
    if G.GAME.pseudorandom.seed ~= S.template_seed or (G.GAME.round or 0) > 0 then
        return S.stop('the run moved on')
    end
    if G.SETTINGS.paused and not (FS.is_open and FS.is_open()) then return end

    local budget = (FS.config.search.budget_ms or 12) / 1000
    local t_end = love.timer.getTime() + budget
    local found
    O.begin('seed', { keep_cache = S.warm })
    S.warm = true
    local ok, err = xpcall(function()
        local list, ctx, stats = S.list, S.ctx, S.stats
        repeat
            local seed = next_seed()
            O.set_seed(seed)
            S.tried = S.tried + 1
            if F.test(list, ctx, stats) then found = seed; break end
        until love.timer.getTime() >= t_end
    end, debug.traceback)
    O.finish()
    S.elapsed = love.timer.getTime() - S.started
    S.rate = S.tried / math.max(S.elapsed, 0.001)
    if not ok then
        FS.err(err)
        S.result = { kind = 'error', tried = S.tried, elapsed = S.elapsed }
        return S.stop('an error occurred (details in the log)')
    end
    if found then return S.on_found(found) end
    local max = FS.config.search.max_seeds or 0
    if max > 0 and S.tried >= max then
        S.result = { kind = 'limit', tried = S.tried, elapsed = S.elapsed }
        S.stop('hit the limit of ' .. FS.fmt(max) .. ' seeds')
    end
end

--- Ante-1 facts we can check once the real run starts.
local function expectations(seed)
    local exp = {}
    O.begin('seed', { keep_cache = true })
    pcall(function()
        O.set_seed(seed)
        exp.small, exp.big = O.tags(1)
        exp.boss = O.blinds(1, 1)[1].boss
        exp.voucher = O.vouchers(1, 1)[1][1]
    end)
    O.finish()
    return exp
end

function S.on_found(seed)
    local summary = F.summary(S.list)
    local exp = expectations(seed)
    S.result = { kind = 'found', seed = seed, tried = S.tried, elapsed = S.elapsed }
    S.running = false
    S.phase = nil
    S.hide_hud()
    FS.Seeds.start({ seed = seed, keep_challenge = true, source = 'search', note = summary, unseeded = FS.config.search.unseeded })
    -- sanity check against the real run
    local gm = G.GAME
    local bad = {}
    if exp.small and gm.round_resets.blind_tags.Small ~= exp.small then bad[#bad + 1] = 'small tag' end
    if exp.big and gm.round_resets.blind_tags.Big ~= exp.big then bad[#bad + 1] = 'big tag' end
    if exp.boss and gm.round_resets.blind_choices.Boss ~= exp.boss then bad[#bad + 1] = 'boss' end
    if exp.voucher and gm.current_round.voucher and gm.current_round.voucher[1] ~= exp.voucher then bad[#bad + 1] = 'voucher' end
    S.result.mismatch = #bad > 0 and table.concat(bad, ', ') or nil
    if S.result.mismatch then
        FS.err('Prediction mismatch for ' .. seed .. ': ' .. S.result.mismatch)
        FS.notify(('Found %s - but the %s differs from the prediction'):format(seed, S.result.mismatch), G.C.ORANGE, 'cancel')
    else
        FS.notify(('Found %s after %s seeds'):format(seed, FS.fmt(S.tried)), G.C.GREEN, 'polychrome1')
    end
end

-------------------------------------------------------------------------------
-- Odds & status text
-------------------------------------------------------------------------------
--- Estimated chance that a random seed passes every filter (product of conditional pass rates).
function S.odds()
    if not S.stats or #S.stats == 0 then return nil end
    local p = 1
    for _, st in ipairs(S.stats) do
        if st.evals < 20 then return nil end
        if st.passes == 0 then return 0, st end
        p = p * (st.passes / st.evals)
    end
    return p
end

function S.odds_text()
    local p, stuck = S.odds()
    if p == nil then return 'estimating odds...' end
    if p == 0 then return 'rarer than 1 in ' .. FS.fmt(math.max(S.tried or 0, 1)) end
    local n = 1 / p
    if n < 1.5 then return 'almost every seed matches' end
    return 'about 1 in ' .. FS.fmt(math.floor(n + 0.5))
end

function S.eta_text()
    local p = S.odds()
    if not p or p <= 0 or S.rate <= 0 then return '' end
    local secs = (1 / p) / S.rate
    if secs < 1 then return 'expect a hit any moment' end
    if secs < 90 then return ('typical wait ~%ds'):format(math.floor(secs + 0.5)) end
    if secs < 5400 then return ('typical wait ~%dm'):format(math.floor(secs / 60 + 0.5)) end
    return ('typical wait ~%dh'):format(math.floor(secs / 3600 + 0.5))
end

function S.clock(secs)
    secs = math.floor(secs or 0)
    return ('%d:%02d'):format(math.floor(secs / 60), secs % 60)
end

function S.rate_text()
    local r = S.rate or 0
    if r >= 1000 then return ('%.1fk/s'):format(r / 1000) end
    return ('%d/s'):format(math.floor(r))
end

--- Pass rate of filter i during the current / last search, as text.
function S.filter_rate(f)
    if not S.stats then return nil end
    for _, st in ipairs(S.stats) do
        if st.f == f and st.evals > 0 then
            local pct = st.passes / st.evals * 100
            if pct >= 10 then return ('%d%%'):format(math.floor(pct + 0.5)) end
            if pct >= 0.1 then return ('%.1f%%'):format(pct) end
            if st.passes > 0 then return ('1 in %s'):format(FS.fmt(math.floor(st.evals / st.passes + 0.5))) end
            return '0 / ' .. FS.fmt(st.evals)
        end
    end
end

-------------------------------------------------------------------------------
-- HUD (shown while searching with the menu closed)
-------------------------------------------------------------------------------
function S.show_hud()
    if S.hud then return end
    local function live(get, colour, scale) return UI.live(get, scale or 0.34, colour or G.C.UI.TEXT_LIGHT) end
    local def = {
        n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR }, nodes = {
            { n = R, config = { align = 'cm', padding = 0.1, r = 0.15, colour = { 0.12, 0.13, 0.17, 0.92 }, emboss = 0.06 }, nodes = {
                { n = C, config = { align = 'cm', minw = 0.14, minh = 0.42, r = 0.05, colour = G.C.SECONDARY_SET.Spectral } },
                UI.spacer(0.12),
                UI.text('SEED FINDER', 0.36, G.C.SECONDARY_SET.Spectral),
                UI.spacer(0.25),
                live(function()
                    if S.phase == 'preparing' then return 'preparing a fresh run...' end
                    return FS.fmt(S.tried) .. ' seeds'
                end),
                UI.spacer(0.25),
                live(S.rate_text, G.C.FILTER),
                UI.spacer(0.25),
                live(function() return S.clock(S.elapsed) end, UI.muted()),
                UI.spacer(0.25),
                live(S.odds_text, G.C.GREEN, 0.3),
                UI.spacer(0.25),
                UI.text('Ctrl+P to stop', 0.28, UI.muted()),
            } },
        },
    }
    local ok, box = pcall(UIBox, { definition = def, config = { align = 'tm', offset = { x = 0, y = 0.12 }, major = G.ROOM_ATTACH, bond = 'Weak' } })
    if ok then S.hud = box end
end

function S.hide_hud()
    if S.hud then
        pcall(function() S.hud:remove() end)
        S.hud = nil
    end
end
