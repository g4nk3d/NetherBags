# NetherBags

Version 1.0.0 - Interface 16001 (WoW: Forever 1.60.x) - All Rights Reserved (see LICENSE.txt)

Bringing order to Azeroth... and your inventory.

The bags, bank and guild bank for the Nether family, in two modes you switch with the
**One bag | Insight** toggle at the top right of the window. Works alone; follows NetherUI's
theme when you want it to (it asks once, at install, when NetherUI is there) and sits on
NetherSuite's shelf when the hub is installed (its tile, its page, every setting in the hub's
search).

## The two modes

- **Insight** (the default): your inventory as a sorted list, in the spirit of the Elder Scrolls
  Online inventory. Places along the top (Bags, Bank, Guild, Everywhere, Currencies), a row of
  category icons, search, and columns you can sort by (name, status, item level, vendor value).
  Items are sorted into groups that open and close: New items, Upgrades, your own groups,
  Gear > Weapons / Armor / Jewelry, Consumables, Trade goods (split by kind), Reagents, Gems,
  Recipes, Quest items, Containers, Ammo, Keys, Miscellaneous, and Junk last, with a Sell all
  button at a vendor. Quick filters in the footer: New, Upgrades, Unseen looks, BoE, Locked.
- **One bag**: every slot of every bag in one grid, like the bags really are. Quivers, ammo
  pouches, soul bags, herb bags and other special bags get their own tinted section; the bank
  shows its tabs (or its bank slots and bank bags); your groups can have a section of their own.
  Columns, slot size and spacing are settings, and the window sizes itself to the grid.
- **Bag menu**: click the bag icon next to the title. Hover a bag to tick the kinds of items it
  holds (as many as you like): sorting puts those items into it and keeps the rest out, and
  new loot is moved there. The cogwheel at the end of each bag gives it a colour (ten presets,
  or any colour from the colour picker): in One bag its slots get a light tint of that colour.

Every bag size and bag count comes from the game, so bigger bags later just work.

## Everything else

- **Markers on items**: new, upgrade (with the item levels gained), appearance not collected
  (clients that have appearances), bind on equip, locked, gear set, quest, junk. Quality colours
  on item edges.
- **Can't use yet**: items above your level, recipes you already know or lack the skill for,
  lockboxes beyond your Lockpicking and other classes' items turn red, with the game's reason
  ("Requires Level 30") under the name.
- **Fades what doesn't fit**: at a vendor, what can't be sold; at the mailbox, a trade or the
  auction house, what is bound to you.
- **Quest needs**: anything a quest in your log asks for (even plain trade goods) is a quest item:
  never sold, stashed or deleted.
- **Rows stay put**: in Insight, sold or used items leave an empty row until the window closes, so
  nothing moves under the cursor.
- **Search** that understands more than names: `ilvl>20`, `boe`, `q:rare`, `value>1g`,
  `upgrade`, `-potion`, `bag:2`, `"two words"`, `potion or elixir`, brackets, `tt:"chance on hit"`
  (tooltip text), `reqlvl>=40`, `usable`... (Settings > Search lists them all). Save any search
  as a group of your own.
- **Move**: at the bank, mailbox or a trade, one button moves what the list shows (or right-click
  a group's header to move the group); at the bank, back to the bags. **Send all to an alt**: every
  stack of an item, 12 to a mail, from the item menu at a mailbox.
- **Looted this session**: a group of what you picked up since you logged in.
- **Tracked items** in the footer (ammo, soul shards, reagents) with a warning when they run low.
- **Free a slot**: when the bags are full, delete the cheapest junk (you see what it is first).
- **Your own groups** (Settings > Groups): a name, an icon, a colour, and rules picked from lists
  (binding, item level, quality, type, slot, value, count, locked, junk...), matching ALL or ANY
  of them, with a live count of what they catch. "Always put in" any group from an item's menu.
- **The item menu**: Alt+Right-click any item. Lock it (never sold, stashed or moved by the
  sort), mark it as junk (or not junk), always put it in a group, find it on every character,
  link it. Alt+Left-click locks or unlocks.
- **Junk**: sold by itself at vendors (on by default; a setting), a few at a time, with a chat
  line saying what it fetched. Locked items are never sold. "Keep everything buyable back" sells
  at most 12 at a time. Mark an item "junk at the next vendor only"; outgrown soulbound gear can
  count as junk (a setting). What vendors really pay is learned and used for every value shown.
- **Sort**: moves the items themselves; locked items stay put, special bags (and the reagent bag)
  are sorted on their own, part stacks are merged. The Sort button says how many slots a sort
  would free; part stacks are merged by themselves after the mailbox or a trade.
- **Bank tabs**: each tab shows "X of Y free"; drop a bag on a tab to use it; buy the next tab.
- **Stash**: at a banker, one click moves the trade goods to the bank.
- **Every character**: each character's bags, bank, mailbox and money are saved, so you can look
  at them from any character (the person icon / the name button), see them on item tooltips
  ("owned by"), and search them all at once in **Everywhere**. Guild banks too, once seen.
  Offline views say how old they are. Everywhere's **Filters** pick the kinds of items and the
  places (bags, bank, guild bank, mailbox) to look in.
- **Profiles**: every setting, your groups, the window layout and your item marks, kept in a
  profile shared by the whole account. Each character picks one (or one for everyone), new
  characters start with the one you choose, and **Export / Import** turns a profile into one
  line of text to share. Import always adds a new profile; nothing you have is overwritten.
- **Themes**: NetherBags' own look, NetherUI's theme (colours, fonts and window art on every
  window and tab, following theme changes), or a theme a plugin adds.
- **Plugins**: other addons can add rules, themes and item menu entries (Docs/API.md).
- **Other bag addons**: at login NetherBags tells you about other bag addons that do the same job
  and lets you keep one (the other is turned off, then the interface reloads), or keep both for
  helpers that only overlap a little.

## Commands

    /nbags                      open / close the bags
    /nbags bank | guild | currency
    /nbags everywhere [text]    search every character
    /nbags onebag | insight     switch the mode
    /nbags sort | config | profile <name> | diag
    /nbags theme                follow NetherUI's theme or keep NetherBags' look
    /nbags conflicts            other bag addons that overlap with NetherBags

Key bindings: Options > Key Bindings > AddOns > NetherBags. The game's bag key opens
NetherBags too.

## Notes

- The windows use the game's own item buttons for your live items, so using, moving,
  splitting, linking and selling items are the game's own actions, also in combat.
- The game's bag, bank and guild bank windows are moved out of sight, not replaced; each can be
  switched back in the settings (after a /reload).
