--- Save states (10 slots, Brainstorm-compatible files) and the rewind timeline.
local FS = Foresight
local ST = FS.States or {}
FS.States = ST

ST.SLOTS = 10
ST.timeline = ST.timeline or {}
ST.next_id = ST.next_id or 1

--- Same file names Brainstorm used, so its save states show up here.
local function path(n)
    return G.SETTINGS.profile .. '/saveState' .. n .. '.jkr'
end
ST.path = path

local function slot_key(n) return 's' .. n end

-------------------------------------------------------------------------------
-- Describing a moment
-------------------------------------------------------------------------------
local function blind_label()
    local gm = G.GAME
    if gm.blind and gm.blind.in_blind and gm.blind.config and gm.blind.config.blind then
        return FS.name_of(gm.blind.config.blind)
    end
    local on_deck = gm.blind_on_deck or 'Small'
    local key = gm.round_resets.blind_choices and gm.round_resets.blind_choices[on_deck]
    return key and G.P_BLINDS[key] and FS.name_of(G.P_BLINDS[key]) or (on_deck .. ' Blind')
end

function ST.meta_live()
    local gm = G.GAME
    local jokers = {}
    for i, c in ipairs(G.jokers and G.jokers.cards or {}) do
        if i > 8 then break end
        jokers[#jokers + 1] = { key = c.config.center.key, edition = c.edition and c.edition.key or nil }
    end
    return {
        t = os.time(), seed = gm.pseudorandom.seed, deck = FS.current_deck_key(), stake = gm.stake or 1,
        ante = FS.num(gm.round_resets.ante), round = FS.num(gm.round), state = FS.state_label(G.STATE),
        dollars = FS.fmt(gm.dollars), hands = gm.current_round.hands_left, discards = gm.current_round.discards_left,
        blind = blind_label(), jokers = jokers, njokers = #(G.jokers and G.jokers.cards or {}),
        hand_no = (gm.current_round.hands_played or 0) + 1,
    }
end

--- Metadata for a save made elsewhere (e.g. by Brainstorm).
function ST.meta_from_save(t)
    local gm = t.GAME or {}
    local jokers = {}
    local area = t.cardAreas and t.cardAreas.jokers
    for i, c in ipairs(area and area.cards or {}) do
        if i > 8 then break end
        local key = c.save_fields and c.save_fields.center
        if key then jokers[#jokers + 1] = { key = key } end
    end
    local deck = t.BACK and (t.BACK.key or (t.BACK.name and select(2, pcall(get_deck_from_name, t.BACK.name)) or {}).key)
    return {
        seed = gm.pseudorandom and gm.pseudorandom.seed, deck = type(deck) == 'string' and deck or nil, stake = gm.stake,
        ante = FS.num(gm.round_resets and gm.round_resets.ante or 1), round = FS.num(gm.round or 0),
        state = FS.state_label(t.STATE), dollars = FS.fmt(gm.dollars), jokers = jokers,
        njokers = area and area.cards and #area.cards or #jokers,
    }
end

function ST.describe(m)
    if not m then return '?' end
    return ('Ante %s - %s - %s'):format(tostring(m.ante or '?'), tostring(m.blind or m.state or ''), '$' .. tostring(m.dollars or '?'))
end

-------------------------------------------------------------------------------
-- Capture & load
-------------------------------------------------------------------------------
local STABLE = { 'SELECTING_HAND', 'SHOP', 'BLIND_SELECT' }

--- The freshest safe snapshot of the run. Returns the save table and a note when it had to fall back.
function ST.capture()
    if not FS.in_run() then return nil end
    local stable = false
    for _, s in ipairs(STABLE) do if G.STATE == G.STATES[s] then stable = true end end
    if stable and not G.F_NO_SAVING then
        save_run()
        return G.ARGS.save_run, nil
    end
    return G.ARGS.save_run, 'last checkpoint'
end

function ST.load_table(t, msg, colour)
    if not t then return end
    if FS.Search.running then FS.Search.stop('loaded a save') end
    if G.OVERLAY_MENU then G.FUNCS.exit_overlay_menu() end
    G.SETTINGS.paused = false
    ST.loading = true
    local ok, err = xpcall(function()
        if G.STAGE == G.STAGES.RUN then
            G:delete_run()
            G.SAVED_GAME = t
            G:start_run({ savetext = G.SAVED_GAME })
        else
            G.SAVED_GAME = t
            G.FUNCS.start_run(nil, { savetext = t })
        end
    end, debug.traceback)
    ST.loading = false
    if not ok then
        FS.err(err)
        return FS.notify('Could not load that save (details in the log)', G.C.RED, 'cancel')
    end
    if msg then FS.notify(msg, colour or G.C.SECONDARY_SET.Planet) end
end

local function unpack_data(data)
    local ok, t = pcall(function() return STR_UNPACK(love.data.decompress('string', 'deflate', data)) end)
    if ok and type(t) == 'table' then return t end
end

--- Read a slot file the way the game reads saves (compressed or not).
local function read_slot(n)
    local ok, t = pcall(function()
        local s = get_compressed(path(n))
        return s and STR_UNPACK(s)
    end)
    if ok and type(t) == 'table' then return t end
end

-------------------------------------------------------------------------------
-- Slots
-------------------------------------------------------------------------------
function ST.exists(n)
    return love.filesystem.getInfo(path(n)) ~= nil
end

function ST.info(n)
    if not ST.exists(n) then return nil end
    local m = FS.config.slots[slot_key(n)]
    if m then return m end
    -- a file without our metadata (Brainstorm made it): read it once and remember
    local t = read_slot(n)
    if not t then return { broken = true } end
    m = ST.meta_from_save(t)
    local info = love.filesystem.getInfo(path(n))
    m.t = info and info.modtime
    FS.config.slots[slot_key(n)] = m
    FS.save_config()
    return m
end

function ST.save_slot(n)
    if not FS.in_run() then return FS.notify('Start a run to save a state', G.C.RED, 'cancel') end
    local data, note = ST.capture()
    if not data then return FS.notify('Nothing to save yet', G.C.RED, 'cancel') end
    local ok, err = pcall(compress_and_save, path(n), data)
    if not ok then
        FS.err(err)
        return FS.notify('Could not write the save file', G.C.RED, 'cancel')
    end
    local m = ST.meta_live()
    m.note = note
    FS.config.slots[slot_key(n)] = m
    FS.save_config()
    FS.notify(('Saved state %d%s'):format(n, note and (' (' .. note .. ')') or ''), G.C.SECONDARY_SET.Planet, 'other1')
end

function ST.load_slot(n)
    if not ST.exists(n) then return FS.notify(('Slot %d is empty'):format(n), G.C.RED, 'cancel') end
    local t = read_slot(n)
    if not t then return FS.notify(('Slot %d could not be read'):format(n), G.C.RED, 'cancel') end
    ST.pos = nil
    ST.load_table(t, ('Loaded state %d'):format(n))
end

function ST.clear_slot(n)
    love.filesystem.remove(path(n))
    FS.config.slots[slot_key(n)] = nil
    FS.save_config()
    FS.toast(('Cleared slot %d'):format(n), G.C.UI.TEXT_LIGHT, 'cancel')
end

-------------------------------------------------------------------------------
-- Rewind timeline (in memory, one checkpoint per autosave)
-------------------------------------------------------------------------------
function ST.signature()
    local gm = G.GAME
    local bs = gm.round_resets.blind_states or {}
    return table.concat({
        tostring(gm.pseudorandom.seed), tostring(G.STATE), tostring(FS.num(gm.round_resets.ante)), tostring(gm.round or 0),
        tostring(gm.current_round.hands_played or 0), tostring(gm.current_round.discards_used or 0), FS.fmt(gm.dollars),
        #G.deck.cards, #G.hand.cards, #G.jokers.cards, #G.consumeables.cards, tostring(bs.Small), tostring(bs.Big), tostring(bs.Boss),
    }, '|')
end

function ST.on_autosave()
    if not FS.config.rewind.enabled or ST.loading or not FS.in_run() then return end
    local t = G.ARGS.save_run
    if not t or t == ST.last_table then return end
    ST.last_table = t
    local sig = ST.signature()
    local tl = ST.timeline
    if ST.pos then
        local cur = tl[ST.pos]
        if cur and cur.sig == sig then return end
        -- a new move after rewinding starts a new branch: drop the old future
        for i = #tl, ST.pos + 1, -1 do table.remove(tl, i) end
        ST.pos = nil
    end
    local ok, packed = pcall(function() return love.data.compress('string', 'deflate', STR_PACK(t), 1) end)
    if not ok then return end
    local last = tl[#tl]
    if last and last.sig == sig then
        last.data, last.t = packed, os.time()
        return
    end
    tl[#tl + 1] = { id = ST.next_id, t = os.time(), sig = sig, meta = ST.meta_live(), data = packed }
    ST.next_id = ST.next_id + 1
    local keep = FS.config.rewind.keep or 40
    while #tl > keep do table.remove(tl, 1) end
end

function ST.current_index()
    return ST.pos or #ST.timeline
end

function ST.goto(i, msg)
    local e = ST.timeline[i]
    if not e then return end
    local t = unpack_data(e.data)
    if not t then return FS.notify('That checkpoint could not be read', G.C.RED, 'cancel') end
    ST.pos = i
    ST.load_table(t, msg or ('Rewound to ' .. ST.describe(e.meta)), G.C.ORANGE)
end

--- Ctrl+Z: back one checkpoint (or to the latest one, if you've acted since it was taken).
function ST.step_back()
    if not FS.config.rewind.enabled then return FS.notify('Rewind is turned off in Settings', G.C.RED, 'cancel') end
    if not FS.in_run() then return end
    local tl = ST.timeline
    if #tl == 0 then return FS.notify('No checkpoints yet', G.C.RED, 'cancel') end
    local cur = ST.current_index()
    local target = cur - 1
    if not ST.pos and tl[cur] and tl[cur].sig ~= ST.signature() then target = cur end
    if target < 1 then return FS.notify('That is the oldest checkpoint', G.C.RED, 'cancel') end
    ST.goto(target, ('Undo - back to %s'):format(ST.describe(tl[target].meta)))
end

--- Ctrl+Y: forward again after rewinding.
function ST.step_forward()
    if not ST.pos or ST.pos >= #ST.timeline then return FS.notify('Already at the latest checkpoint', G.C.RED, 'cancel') end
    ST.goto(ST.pos + 1, ('Redo - forward to %s'):format(ST.describe(ST.timeline[ST.pos + 1].meta)))
end

--- Keep a checkpoint by copying it into a save slot.
function ST.pin(i, n)
    local e = ST.timeline[i]
    if not e then return end
    love.filesystem.write(path(n), e.data)
    local m = FS.copy(e.meta)
    m.t = os.time()
    m.note = 'from rewind'
    FS.config.slots[slot_key(n)] = m
    FS.save_config()
    FS.toast(('Checkpoint copied to slot %d'):format(n), G.C.GREEN, 'other1')
end

function ST.first_free_slot()
    for n = 1, ST.SLOTS do if not ST.exists(n) then return n end end
end

function ST.clear_timeline()
    ST.timeline = {}
    ST.pos = nil
    FS.toast('Rewind timeline cleared', G.C.UI.TEXT_LIGHT, 'cancel')
end
