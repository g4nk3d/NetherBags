# NetherBags architecture

Everything lives in one namespace (`ns.NBG`); the only global is `NetherBags` (API/Plugin.lua).
Modules talk through an internal message bus (`NBG:Fire` / `NBG:Register`) and never call the
UI from the data layer.

    Core/        Init (events, bus, timers, safe calls, secret-value guards), Locale, Serialize
                 (profile strings: own reader, no code ever run), Settings (defaults, the profile),
                 Profiles (switch, copy, rename, delete, export, import), Lifecycle
    Data/        Containers (bags, bank tabs or classic bank, keyring; one debounced BAGS_CHANGED),
                 Items (item facts, upgrades, unusable, appearances, sets, binding), Store (every
                 character's bags / bank / mail / money and guild banks; Everywhere; tooltip
                 totals), Marks (lock, junk, keep, always-put-in), Rules (the rule engine), Search
                 (the query language, compiled to rules), Groups (built-in and custom groups),
                 Usable (can't use yet, quest needs, outgrown gear, looted this session),
                 BagRules (what each bag holds and its colour; the bag menu)
    UI/          Skin (themes, roles, fonts; NetherUI and plugin themes), Widgets, ItemButton (the
                 game's own container item buttons, one per bag slot, made ahead of combat),
                 Common (footer, bag strip, offline note, character menu), Window (the bags, bank
                 and guild windows), OneBag and Insight (the two views), Everywhere (Everywhere and
                 currencies), GuildUI, Config and ConfigPages (settings), GlyphAtlas,
                 ThemeChoice (the NetherUI theme question), Conflicts (other bag addons),
                 BagMenu (the bag icon's menu: kinds per bag, colour per bag)
    Features/    GuildBank, Selling, Sort, Stash, FreeSlot, Tracked, Transfer (Move, send all to an
                 alt), Blizzard (following the game's bag functions with
                 hooksecurefunc, moving the game's frames out of sight), Tooltip, Suite
                 (NetherSuite), Slash (commands, the first-run theme question)

## Rules kept

- No game function or global is replaced; the game's frames are re-parented, never hidden.
- Live items use the game's own `ContainerFrameItemButtonTemplate`; bag = parent ID, slot =
  button ID; nothing of the template is overwritten (our methods are NB-prefixed).
- Every count and size comes from the game: any bag size, bag count and bank tab count works.
- Secret values (instances) are refused by `NBG.Num/Str/Open` before use.
- Imported data is checked key by key against the defaults, choices and ranges.
- Saved data is versioned (`NBG.SCHEMA`) with migrations in Core/Lifecycle.lua.
