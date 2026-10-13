--- Foresight: seed finder, run forecast, save states and rewind for Balatro (Steamodded).
Foresight = Foresight or {}
Foresight.mod = SMODS.current_mod

-- icon shown in the Mods menu
SMODS.Atlas({ key = 'modicon', path = 'icon.png', px = 34, py = 34 })

local files = {
    'src/core.lua',
    'src/ui.lua',
    'src/widgets.lua',
    'src/oracle.lua',
    'src/filters.lua',
    'src/search.lua',
    'src/states.lua',
    'src/seeds.lua',
    'src/tabs/finder.lua',
    'src/tabs/forecast.lua',
    'src/tabs/states.lua',
    'src/tabs/rewind.lua',
    'src/tabs/seeds.lua',
    'src/tabs/settings.lua',
    'src/menu.lua',
}

for _, path in ipairs(files) do
    local chunk, err = SMODS.load_file(path)
    if not chunk then error(('Foresight: could not load %s: %s'):format(path, tostring(err))) end
    chunk()
end
