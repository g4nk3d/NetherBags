# NetherBags plugin interface (API version 1)

NetherBags has one global, `NetherBags`. A plugin is a separate addon that lists NetherBags in
its `## Dependencies` (or `## OptionalDeps`) and registers itself:

    local api = NetherBags:RegisterPlugin({
        id = "myplugin",                 -- letters, digits, - and _ (40 at most)
        name = "My Plugin", version = "1.0", description = "What it adds.",
        OnEnable = function(api) ... end, -- at login (or at once, after login)
        OnDisable = function(api) ... end,-- when the player switches it off (Settings > Plugins)
    })

`RegisterPlugin` returns `nil, why` for a missing or taken id.

## What a plugin can do

- `api:On(message, fn)` - NetherBags' messages (below). `fn(...)` gets the message's values.
- `api:AddRule(def)` - a rule property for custom groups and search:
  `{ id = "mything", label = "My thing", kind = "bool" | "text" | "number" | "money" | "quality" | "choice",
  get = function(entry) return value end, choices = function() return { { value, label } } end }`.
  `entry` is a copy of an item record (below). The id must be lower-case letters, digits, `_`.
- `api:AddSkin(def)` - a theme every NetherBags window and tab can wear (Settings > General > Theme):
  `{ id, label, colors = { role = { r, g, b, a } }, fonts = { body, medium, bold, title, caps = path },
  window = function(layer, frame) ... return true end, panel = function(frame, opts) ... return true end,
  onApply = function() end, available = function() return true end }`.
  Roles: text, textDim, faint, header, accent, accentLo, accent2, border, bg, bgTop, bgAlt, inset,
  row, rowHover, rowSel, positive, negative, warning, special, ink. `window` draws into `layer`
  (a frame covering the window) and returns true; when it returns false the own look is used.
  This is how a plugin makes NetherBags match another interface.
- `api:AddMenuItem(fn)` - `fn(entry)` returns `{ text, glyph, onClick }` or nil; the entry is added
  to the Alt+Right-click item menu.
- `api:Settings()` - a table saved for the plugin (account-wide).
- `api:Print(fmt, ...)`

A plugin's errors are caught and counted against it; after 5 it is switched off and the player
sees it in Settings > Plugins with the last error. Plugins never get NetherBags' own tables:
records handed to them are copies.

## Reading and opening

- `NetherBags:Toggle([id])`, `:Open(id [, place])`, `:Close(id)` - id "bags" | "bank" | "guild";
  place "bags" | "bank" | "guild" | "everywhere" | "currency".
- `NetherBags:Search(text)` - Everywhere with that text.
- `NetherBags:Items(place [, charKey])` - copies of the item records of "bags" or "bank" for this
  character (live) or a saved one.
- `NetherBags:Owners(itemID)` - `{ owners = { { key, class, bags, bank, mail } }, guilds = { { name, count } } }`.

## Item records

`{ bag, slot, place, link, str, id, count, icon, quality, locked, bound, quest, new, live }` -
`live = false` for saved records (another character, a bank seen earlier).

## Messages

`BAGS_CHANGED(set)`, `BANK_OPEN(open)`, `GUILD_OPEN(open)`, `MERCHANT(open)`, `WINDOW_SHOWN(id)`,
`WINDOW_HIDDEN(id)`, `SETTING_CHANGED(key, value)`, `PROFILE_CHANGED(name)`, `GROUPS_CHANGED`,
`MARKS_CHANGED(kind, itemID)`, `STORE_CHANGED`, `SKIN_CHANGED(id)`, `SORT(running)`,
`ITEM_ENTER(button)`, `ITEM_LEAVE(button)`.

All Rights Reserved; plugins are allowed (LICENSE.txt, 1b).
