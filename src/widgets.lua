--- Real game objects as UI: cards, tags, blind chips and the paged picker built from them.
local FS = Foresight
local UI = FS.UI
local R, C, O = G.UIT.R, G.UIT.C, G.UIT.O

--- Small coloured badge on a card (the slot the game uses for its "NEW" alert). text = nil removes it.
function UI.badge(card, text, colour, scale)
    if not card or card.REMOVED then return end
    if card.children.alert then card.children.alert:remove(); card.children.alert = nil end
    if not text then return end
    card.children.alert = UIBox({
        definition = create_UIBox_card_alert({ text = text, bg_col = colour or G.C.GREEN, scale = scale or 0.32, text_rot = 0.12 }),
        config = { align = 'tri', offset = { x = 0.08, y = 0.06 }, parent = card },
    })
    card.children.alert.states.collide.can = false
end

--- Badge attached once the card has been placed (children need a frame to align).
function UI.badge_later(card, text, colour, scale)
    G.E_MANAGER:add_event(Event({ trigger = 'immediate', blockable = false, blocking = false, func = function()
        UI.badge(card, text, colour, scale)
        return true
    end }))
end

--- A display Card for a prediction or picker item: {key, edition, seal, front}.
function UI.make_card(it, x, y, w, h)
    local center = type(it.key) == 'table' and it.key or G.P_CENTERS[it.key or '']
    if not center then return nil end
    local front = it.front and G.P_CARDS[it.front] or G.P_CARDS.empty
    local card = Card(x, y, w, h, front, center, { bypass_discovery_center = true, bypass_discovery_ui = true, bypass_lock = true })
    if it.edition then pcall(card.set_edition, card, it.edition, true, true) end
    if it.seal then pcall(card.set_seal, card, it.seal, true, true) end
    return card
end

--- A row of real cards. items: list of {key, edition, seal, front, badge, badge_colour}.
--- a: scale, slots (minimum width in cards), on_click(it, card), materialize, booster
function UI.card_strip(items, a)
    a = a or {}
    local scale = a.scale or 0.6
    local cw, ch = G.CARD_W * scale, G.CARD_H * scale
    if a.booster then cw, ch = cw * 1.27, ch * 1.27 end
    local slots = math.max(#items, a.slots or 1)
    local area = CardArea(G.ROOM.T.x, G.ROOM.T.h, slots * cw * (a.spread or 1.1) + 0.05, ch,
        { card_limit = slots, type = 'title', highlight_limit = 0, card_w = cw })
    for i, it in ipairs(items) do
        local card = UI.make_card(it, area.T.x + area.T.w / 2, area.T.y, cw, ch)
        if card then
            card.fs_item = it
            if a.on_click then
                card.click = function(self) FS.safe(a.on_click, it, self) end
            else
                card.click = function(self) self:juice_up(0.3, 0.3); FS.sfx('card1', 1.2, 0.35) end
            end
            if a.materialize ~= false then card:start_materialize(nil, i > 1) end
            area:emplace(card)
            if it.badge then UI.badge_later(card, it.badge, it.badge_colour, a.badge_scale) end
        end
    end
    return { n = O, config = { object = area } }
end

--- Tag sprite with the game's own hover tooltip. Returns the UI node and the sprite.
function UI.tag_icon(key, size, on_click)
    local ok, tag = pcall(Tag, key, true)
    if not ok or not tag then return UI.text(tostring(key), 0.25) end
    local tag_ui, sprite = tag:generate_UI(size or 0.6)
    if on_click and sprite then
        sprite.states.click.can = true
        sprite.click = function(self) FS.safe(on_click, self) end
    end
    return tag_ui, sprite
end

--- Blind chip sprite with the game's blind tooltip on hover.
function UI.blind_icon(key, size, on_click)
    local blind = G.P_BLINDS[key]
    if not blind then return UI.text(tostring(key), 0.25) end
    size = size or 0.7
    local ok, sprite = pcall(SMODS.create_sprite, 0, 0, size, size, blind.atlas or 'blind_chips', blind.pos, blind.sprite_args)
    if not ok or not sprite then return UI.text(FS.name_of(blind), 0.25) end
    sprite:define_draw_steps({ { shader = 'dissolve', shadow_height = 0.05 }, { shader = 'dissolve' } })
    sprite.float = true
    sprite.states.hover.can = true
    sprite.states.drag.can = false
    sprite.states.collide.can = true
    sprite.config = { force_focus = true }
    sprite.hover = function(self)
        if (not G.CONTROLLER.dragging.target or G.CONTROLLER.using_touch) and not self.hovering and self.states.visible then
            self.hovering = true
            self.hover_tilt = 3
            self:juice_up(0.05, 0.02)
            FS.sfx('chips1', math.random() * 0.1 + 0.55, 0.12)
            self.config.h_popup = create_UIBox_blind_popup(blind, true)
            self.config.h_popup_config = (self.T.x > G.ROOM.T.w * 0.4)
                and { align = 'cl', offset = { x = -0.1, y = 0 }, parent = self }
                or { align = 'cr', offset = { x = 0.1, y = 0 }, parent = self }
            Node.hover(self)
        end
    end
    sprite.stop_hover = function(self)
        self.hovering = false
        Node.stop_hover(self)
        self.hover_tilt = 0
    end
    if on_click then
        sprite.states.click.can = true
        sprite.click = function(self) FS.safe(on_click, self) end
    end
    return { n = C, config = { align = 'cm' }, nodes = { { n = O, config = { w = size, h = size, object = sprite, focus_with_object = true } } } }, sprite
end

--- Paged multi-select picker of real cards, tags or blind chips.
--- a: id, kind ('card'|'tag'|'blind'), items ({key, label}), cols, rows, scale|size, set (key -> true),
---    single (radio behaviour), on_change(key), width, height, search (table with .q), colour, booster
--- Returns the node and a refresh() function (re-filters and jumps to page 1).
function UI.picker(a)
    local id = 'fsgt_pick_' .. a.id
    FS.view.pick_pages = FS.view.pick_pages or {}
    FS.view.pick_count = FS.view.pick_count or {}
    local cols, rows = a.cols or 6, a.rows or 2
    local per = cols * rows

    local function list()
        local q = ''
        if a.search then q = tostring(a.search.q or ''):lower():gsub('^%s+', ''):gsub('%s+$', '') end
        if q == '' then return a.items end
        local out = {}
        for _, it in ipairs(a.items) do
            local name = (it.label or FS.name_of(it.key)):lower()
            if name:find(q, 1, true) or tostring(it.key):lower():find(q, 1, true) then out[#out + 1] = it end
        end
        return out
    end
    local function selected(key) return a.set[key] and true or false end
    local function toggle(key)
        if a.single then
            local was = a.set[key]
            for k in pairs(a.set) do a.set[k] = nil end
            if not was or not a.allow_none then a.set[key] = true end
        else
            a.set[key] = (not a.set[key]) or nil
        end
        FS.sfx('cardSlide1', 1.15, 0.35)
        if a.on_change then a.on_change(key) end
    end

    local build
    local function rebuild() UI.replace(id, build) end

    build = function()
        local items = list()
        local pages = math.max(1, math.ceil(#items / per))
        local p = FS.clamp(FS.view.pick_pages[id] or 1, 1, pages)
        FS.view.pick_pages[id] = p
        FS.view.pick_count[id] = { n = #items, pages = pages }
        if #items == 0 then
            return UI.root({ UI.notice('Nothing matches', { 'Try another search.' }) }, { minw = a.width, minh = a.height })
        end
        local first = (p - 1) * per
        local out_rows = {}
        if a.kind == 'card' then
            local scale = a.scale or 0.62
            local cw, ch = G.CARD_W * scale, G.CARD_H * scale
            if a.booster then cw, ch = cw * 1.27, ch * 1.27 end
            for r = 1, rows do
                local slice = {}
                for c = 1, cols do
                    local it = items[first + (r - 1) * cols + c]
                    if it then slice[#slice + 1] = it end
                end
                if #slice > 0 then
                    local area = CardArea(G.ROOM.T.x, G.ROOM.T.h, cols * cw * 1.08, ch,
                        { card_limit = cols, type = 'title', highlight_limit = 0, card_w = cw })
                    for i, it in ipairs(slice) do
                        local card = UI.make_card({ key = it.key, edition = it.edition }, area.T.x + area.T.w / 2, area.T.y, cw, ch)
                        if card then
                            card.click = function(self)
                                toggle(it.key)
                                if a.single then
                                    rebuild()
                                else
                                    UI.badge(self, selected(it.key) and (a.badge or 'ON') or nil, a.badge_colour or G.C.GREEN)
                                    self:juice_up(0.35, 0.35)
                                end
                            end
                            card:start_materialize(nil, i > 1)
                            area:emplace(card)
                            if selected(it.key) then UI.badge_later(card, a.badge or 'ON', a.badge_colour or G.C.GREEN) end
                        end
                    end
                    out_rows[#out_rows + 1] = { n = R, config = { align = 'cm', padding = 0.03, no_fill = true }, nodes = { { n = O, config = { object = area } } } }
                end
            end
        else
            local size = a.size or 0.62
            local col = a.badge_colour or G.C.GREEN
            for r = 1, rows do
                local cells = {}
                for c = 1, cols do
                    local it = items[first + (r - 1) * cols + c]
                    if it then
                        local on_click = function(spr) toggle(it.key); if spr.juice_up then spr:juice_up(0.3, 0.3) end end
                        local icon = (a.kind == 'tag') and UI.tag_icon(it.key, size, on_click) or UI.blind_icon(it.key, size, on_click)
                        cells[#cells + 1] = {
                            n = C,
                            config = {
                                align = 'cm', padding = 0.07, r = 0.12, colour = G.C.CLEAR, func = 'fsgt_sync',
                                fs_sync = function(e)
                                    local s = selected(it.key)
                                    if s ~= e.config.fs_sel then
                                        e.config.fs_sel = s
                                        e.config.colour = s and col or G.C.CLEAR
                                    end
                                end,
                            },
                            nodes = { icon },
                        }
                    end
                end
                if #cells > 0 then out_rows[#out_rows + 1] = { n = R, config = { align = 'cm', padding = 0.02 }, nodes = cells } end
            end
        end
        return UI.root({ UI.col(out_rows) }, { minw = a.width, minh = a.height })
    end

    local function turn(d)
        local info = FS.view.pick_count[id] or { pages = 1 }
        if (info.pages or 1) <= 1 then return end
        local p = (FS.view.pick_pages[id] or 1) + d
        if p < 1 then p = info.pages elseif p > info.pages then p = 1 end
        FS.view.pick_pages[id] = p
        FS.sfx('paper1', 1.05, 0.4)
        rebuild()
    end
    FS.view.wheel_target = turn

    local nav = UI.row({
        UI.button({ label = '<', w = 0.55, h = 0.36, scale = 0.3, colour = a.colour or G.C.UI.BACKGROUND_INACTIVE, on_click = function() turn(-1) end }),
        { n = C, config = { align = 'cm', minw = 3.4 }, nodes = { UI.live(function()
            local info = FS.view.pick_count[id] or { n = 0, pages = 1 }
            local n = 0
            for _ in pairs(a.set) do n = n + 1 end
            return ('Page %d/%d  -  %d selected'):format(FS.view.pick_pages[id] or 1, info.pages or 1, n)
        end, 0.27, UI.muted()) } },
        UI.button({ label = '>', w = 0.55, h = 0.36, scale = 0.3, colour = a.colour or G.C.UI.BACKGROUND_INACTIVE, on_click = function() turn(1) end }),
    }, { padding = 0.02 })

    local function refresh()
        FS.view.pick_pages[id] = 1
        rebuild()
    end
    return UI.col({
        UI.row({ UI.slot(id, build, { minw = a.width, minh = a.height }) }),
        nav,
    }), refresh
end

--- Text input bound to tbl[field]; calls on_change(text) whenever the text changes.
function UI.input(a)
    local node = create_text_input({
        w = a.w or 3, h = a.h or 0.42, max_length = a.max_length or 20, all_caps = a.all_caps or false,
        extended_corpus = a.extended_corpus ~= false, prompt_text = a.prompt or 'Type...',
        ref_table = a.tbl, ref_value = a.field, colour = G.C.BLACK, hooked_colour = UI.tint(a.colour or G.C.BLUE, 0.6),
        text_scale = a.text_scale or 0.32, id = a.id,
    })
    if not a.on_change then return node end
    local last = a.tbl[a.field]
    local watcher = { n = C, config = { func = 'fsgt_sync', fs_sync = function()
        local now = a.tbl[a.field]
        if now ~= last then
            last = now
            a.on_change(now)
        end
    end }, nodes = {} }
    return UI.col({ node, watcher }, { padding = 0 })
end
