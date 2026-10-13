--- Run control (new run, replay, play a seed) plus seed history and favourites.
local FS = Foresight
local S = FS.Seeds or {}
FS.Seeds = S

local HISTORY_MAX = 40

--- Deck / stake / challenge of the current run, or the profile's last choice outside a run.
function S.setup()
    if FS.in_run() then
        return {
            deck = FS.current_deck_key(),
            stake = G.GAME.stake or 1,
            challenge = G.GAME.challenge and G.GAME.challenge_tab or nil,
        }
    end
    local mem = G.PROFILES and G.PROFILES[G.SETTINGS.profile] and G.PROFILES[G.SETTINGS.profile].MEMORY or {}
    local deck = 'b_red'
    if mem.deck then
        local ok, c = pcall(get_deck_from_name, mem.deck)
        if ok and c and c.key then deck = c.key end
    end
    return { deck = deck, stake = mem.stake or 1 }
end

function S.clean_seed(text)
    text = tostring(text or ''):upper():gsub('[^%w]', '')
    if #text > 8 then text = text:sub(1, 8) end
    return text
end

--- Start a run right away. opts: seed, deck, stake, challenge, keep_challenge, source, note, unseeded
function S.start(opts)
    opts = opts or {}
    local setup = S.setup()
    local deck = opts.deck or setup.deck
    local stake = opts.stake or setup.stake
    local challenge = opts.challenge
    if challenge == nil and opts.keep_challenge then challenge = setup.challenge end
    local args = { stake = stake, seed = opts.seed, challenge = challenge }
    if not challenge and deck and G.P_CENTERS[deck] then args.deck_choice = G.P_CENTERS[deck] end

    if FS.Search and FS.Search.running and opts.source ~= 'search' and opts.source ~= 'template' then
        FS.Search.stop('started another run')
    end
    S.next_source = opts.source
    S.next_note = opts.note
    if G.OVERLAY_MENU then G.FUNCS.exit_overlay_menu() end
    G.SETTINGS.paused = false
    if G.GAME then G.GAME.viewed_back = nil end

    if G.STAGE == G.STAGES.RUN then
        G:delete_run()
        G:start_run(args)
        if opts.seed and opts.unseeded then G.GAME.seeded = false end
    else
        -- from the main menu use the game's own transition
        S.pending_unseeded = opts.seed and opts.unseeded
        G.FUNCS.start_run(nil, args)
    end
end

--- Ctrl+T: a new run on a random seed with the same deck, stake and challenge.
function S.reroll()
    if not FS.in_run() then return FS.notify('Start a run first', G.C.RED, 'cancel') end
    S.start({ keep_challenge = true, source = 'random' })
    FS.notify('New run: ' .. tostring(G.GAME.pseudorandom.seed), G.C.SECONDARY_SET.Spectral, false)
end

--- Ctrl+Shift+T: restart the current seed.
function S.replay()
    if not FS.in_run() then return FS.notify('Start a run first', G.C.RED, 'cancel') end
    local seed = G.GAME.pseudorandom.seed
    local unseeded = not G.GAME.seeded
    S.start({ seed = seed, keep_challenge = true, source = 'replay', unseeded = unseeded })
    FS.notify('Restarted ' .. tostring(seed), G.C.SECONDARY_SET.Spectral, false)
end

--- Play a history or favourite entry (or any {seed, deck, stake}).
function S.play(entry)
    local seed = S.clean_seed(entry.seed)
    if seed == '' then return FS.warn('That seed is empty') end
    S.start({
        seed = seed, deck = entry.deck, stake = entry.stake, source = 'typed',
        unseeded = entry.source == 'search' and FS.config.search.unseeded or false,
        note = entry.note,
    })
end

-------------------------------------------------------------------------------
-- History & favourites
-------------------------------------------------------------------------------
local function same(a, b)
    return a and b and a.seed == b.seed and a.deck == b.deck and a.stake == b.stake
end

function S.on_run_started(args)
    if S.pending_unseeded and G.GAME then
        G.GAME.seeded = false
        S.pending_unseeded = nil
    end
    if args and args.savetext then return end
    local gm = G.GAME
    if not gm or not gm.pseudorandom or not gm.pseudorandom.seed then return end
    local seed = gm.pseudorandom.seed
    local source = S.next_source or (gm.seeded and 'typed' or 'random')
    local note = S.next_note
    S.next_source, S.next_note = nil, nil
    -- remember what a fresh run looks like, so the seed finder can tell if it is still untouched
    S.fresh = {
        seed = seed, jokers = #(G.jokers and G.jokers.cards or {}), cons = #(G.consumeables and G.consumeables.cards or {}),
        cards = #(G.playing_cards or {}), dollars = FS.num(gm.dollars),
    }
    if source == 'template' or seed == 'TUTORIAL' then return end
    local entry = {
        seed = seed, deck = FS.current_deck_key(), stake = gm.stake or 1, t = os.time(), source = source,
        best = 1, note = note, challenge = gm.challenge,
    }
    local h = FS.config.history
    for i = #h, 1, -1 do
        if same(h[i], entry) then
            entry.best = math.max(entry.best, h[i].best or 1)
            entry.note = entry.note or h[i].note
            table.remove(h, i)
        end
    end
    table.insert(h, 1, entry)
    while #h > HISTORY_MAX do table.remove(h) end
    S.current = entry
    FS.save_config()
end

--- Called on every autosave: keeps "furthest ante" and wins up to date.
function S.track()
    local e = S.current
    local gm = G.GAME
    if not e or not gm or not gm.pseudorandom or e.seed ~= gm.pseudorandom.seed then return end
    local ante = FS.num(gm.round_resets.ante)
    local changed = false
    if ante > (e.best or 1) then e.best = ante; changed = true end
    if gm.won and not e.won then e.won = true; changed = true end
    if changed then FS.save_config() end
end

function S.is_favourite(seed, deck, stake)
    for i, f in ipairs(FS.config.favorites) do
        if f.seed == seed and (deck == nil or f.deck == deck) and (stake == nil or f.stake == stake) then return i end
    end
end

function S.toggle_favourite(entry)
    local i = S.is_favourite(entry.seed, entry.deck, entry.stake)
    if i then
        table.remove(FS.config.favorites, i)
        FS.save_config()
        FS.toast('Removed ' .. entry.seed .. ' from favourites', G.C.UI.TEXT_LIGHT, 'cancel')
        return false
    end
    table.insert(FS.config.favorites, 1, {
        seed = entry.seed, deck = entry.deck, stake = entry.stake, t = os.time(), note = entry.note, source = entry.source,
    })
    FS.save_config()
    FS.toast('Starred ' .. entry.seed, G.C.MONEY, 'coin1')
    return true
end

function S.current_entry()
    if not FS.in_run() then return nil end
    local gm = G.GAME
    return {
        seed = gm.pseudorandom.seed, deck = FS.current_deck_key(), stake = gm.stake or 1,
        source = S.current and S.current.seed == gm.pseudorandom.seed and S.current.source or nil,
        note = S.current and S.current.seed == gm.pseudorandom.seed and S.current.note or nil,
    }
end

function S.copy(seed)
    pcall(love.system.setClipboardText, seed)
    G.CLIPBOARD = seed
    FS.toast('Copied ' .. seed .. ' to the clipboard', G.C.GREEN, 'generic1')
end

function S.paste()
    local ok, txt = pcall(love.system.getClipboardText)
    if not ok or not txt then return '' end
    return S.clean_seed(txt)
end

S.SOURCE_LABEL = {
    search = 'found by search', random = 'random', typed = 'typed in', replay = 'replayed',
}
