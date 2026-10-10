--[[ NetherBags - UI/Config.lua
	The settings window: pages on the left, the page on the right. Every plain setting is declared
	once in Config.PAGES (NetherSuite's search reads the same list), and three pages have their own
	builders: Groups (the group editor), Profiles (profiles, export and import) and Junk & selling
	(the marked items).

	  Config:Open(page, arg)        page: general | insight | onebag | groups | junk | bank | search
	                                | profiles | plugins; arg: a custom group to edit
	  Config.PAGES                  { { id, label, glyph, desc, controls = { ... } } } ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Config = NBG:Module("Config")
local Skin, W, Settings = NBG.Skin, NBG.Widgets, NBG.Settings

local type, pairs, ipairs, max, min, floor = type, pairs, ipairs, math.max, math.min, math.floor

local function T(key, label, sub, kw) return { kind = "toggle", key = key, label = label, sub = sub, keywords = kw } end
local function S(key, label, lo, hi, step, fmt, kw) return { kind = "slider", key = key, label = label, min = lo, max = hi, step = step, fmt = fmt, keywords = kw } end
local function C(key, label, values, kw) return { kind = "choice", key = key, label = label, values = values, keywords = kw } end
local function H(label) return { kind = "header", label = label } end

local function SkinValues()
	local out = {}
	for _, s in ipairs(Skin:List()) do out[#out + 1] = { value = s.id, label = s.label } end
	return out
end

Config.PAGES = {
	{ id = "general", label = L["General"], glyph = "gear", desc = L["The look of every NetherBags window, the markers on items, tooltips and the game's own bag windows."], controls = {
		H(L["Look"]),
		C("look.skin", L["Theme"], SkinValues, { "skin", "netherui", "colours", "colors", "theme" }),
		S("look.scale", L["Window size"], 0.5, 2, 0.05, "%.2f", { "scale" }),
		S("look.opacity", L["Window background opacity"], 30, 100, 1, "%d%%", { "alpha", "transparency" }),
		T("look.qualityBorders", L["Quality colour on item edges"], nil, { "rarity", "border" }),
		S("look.qualityMin", L["...from quality"], 0, 5, 1, "%d", { "rarity" }),
		T("look.newGlow", L["New items glow"], nil, { "new" }),
		T("look.contextFade", L["Fade what can't go where you are"], L["At a vendor: what can't be sold. At the mailbox, a trade or the auction house: what is bound to you."], { "dim", "fade", "vendor", "mail" }),
		T("window.lock", L["Lock the windows in place"]),
		H(L["Markers on items"]),
		T("mark.new", L["New"]), T("mark.upgrade", L["Upgrade (higher item level than what you wear)"]),
		T("mark.unseen", L["Appearance not collected (clients with appearances)"], nil, { "transmog" }),
		T("mark.bind", L["Bind on equip"], nil, { "boe" }), T("mark.lock", L["Locked"]), T("mark.set", L["Part of a gear set"]),
		T("mark.quest", L["Quest item (also what a quest in your log asks for)"]), T("mark.junk", L["Junk"]),
		T("mark.unusable", L["Can't use yet (level, known recipe, skill, Lockpicking, class)"], L["The item turns red and the reason shows under its name."], { "usable", "level", "recipe", "lockpick" }),
		H(L["Tooltips"]),
		T("tooltip.counts", L["How many each character has, on item tooltips"], L["From what each character carried when last seen."], { "count", "alts", "owned" }),
		T("tooltip.shift", L["...only while Shift is held"]),
		T("tooltip.guild", L["...including guild banks"]),
		H(L["The game's windows"]),
		T("blizzard.bags", L["Use NetherBags instead of the game's bags"], L["Off: the game's bags come back after /reload."]),
		T("minimap.compartment", L["Entry in the minimap's addon menu"], L["Takes effect after /reload."]),
	} },
	{ id = "insight", label = L["Insight"], glyph = "all", desc = L["The list view: groups, columns and the footer's quick filters."], controls = {
		S("insight.rowHeight", L["Row height"], 22, 48, 1, "%d", { "size" }),
		T("insight.showType", L["Show the item's kind under its name"]),
		T("insight.colStatus", L["Status column"]), T("insight.colIlvl", L["Item level column"]), T("insight.colValue", L["Vendor value column"]),
		T("insight.newGroup", L["New items in a group of their own"]),
		T("insight.recentGroup", L["\"Looted this session\" group"], nil, { "recent", "loot" }),
		T("insight.keepPlace", L["Rows stay in place while the window is open"], L["Sold or used items leave an empty row, so nothing moves under the cursor. It tidies up when the window closes."], { "shift", "gap", "keep" }),
		C("insight.groupBy", L["Group the list by"], function() return { { value = "groups", label = L["Groups"] }, { value = "bag", label = L["Bag / tab"] }, { value = "none", label = L["Nothing (one list)"] } } end),
		C("insight.sort", L["Sort the rows by"], function() return { { value = "name", label = L["Name"] }, { value = "ilvl", label = L["Item level"] }, { value = "value", label = L["Vendor value"] }, { value = "count", label = L["Count"] }, { value = "quality", label = L["Quality"] } } end),
		T("insight.sortDesc", L["Highest first"]),
		T("footer.chips", L["Quick filters in the footer"]),
		T("footer.currencies", L["Tracked currencies in the footer"]),
		T("footer.tracked", L["Tracked items in the footer (ammo, shards, reagents), with a warning when low"], L["Track an item from its menu (Alt+Right-click)."], { "ammo", "shard", "reagent", "low" }),
	} },
	{ id = "onebag", label = L["One bag"], glyph = "backpack", desc = L["The grid view: every slot of every bag in one window."], controls = {
		S("onebag.columns", L["Columns"], 4, 30, 1, "%d"),
		S("onebag.slot", L["Slot size"], 24, 60, 1, "%d"),
		S("onebag.spacing", L["Space between slots"], 0, 10, 1, "%d"),
		T("onebag.bagStrip", L["Show the bag slots above the grid"]),
		T("onebag.specialSections", L["Special bags (quivers, soul bags, herb bags...) in their own section"]),
		T("onebag.groupSections", L["Groups set to \"own section\" get one"]),
		T("onebag.keyring", L["Show the keyring"]),
		T("onebag.reverse", L["Fill from the right"]),
		T("onebag.bagColors", L["Tint each bag's slots with its colour"], L["Pick a bag's colour in the bag menu: the bag icon next to the title."], { "colour", "color", "tint" }),
	} },
	{ id = "questbar", label = L["Quest item bar"], glyph = "quest", desc = L["Your usable quest items on a small bar, one click away. Turn it on with the quest button in the bags window's title bar (right-click it for these options too). Drop any item on the bar to keep it there; right-click an item on the bar to hide it."], controls = {
		T("questbar.on", L["Show the quest item bar"], nil, { "quest", "item bar", "use" }),
		T("questbar.onlyUsable", L["Only items you can use"], L["Items with a \"Use:\" effect, the ones a quest tells you to use and the ones that start a quest. Off: every quest item, and what a quest in your log asks for."]),
		T("questbar.hideEmpty", L["Hide the bar when it is empty"]),
		T("questbar.lock", L["Lock the bar"], L["Unlocked: drag the bar with the left mouse button (by its frame or title) to move it. Right-click the bar to turn the way it grows."], { "move" }),
		T("questbar.keys", L["Show the key bound to each button"], L["Key Bindings > AddOns > NetherBags: Use quest item 1 to 4."], { "keybind", "binding", "hotkey" }),
		S("questbar.size", L["Button size"], 24, 60, 1, "%d", { "size" }),
		S("questbar.perRow", L["Buttons per row"], 1, 24, 1, "%d", { "columns", "row" }),
		C("questbar.grow", L["Grow"], function() return { { value = "up", label = L["Up"] }, { value = "left", label = L["To the left"] }, { value = "down", label = L["Down"] }, { value = "right", label = L["To the right"] } } end),
	} },
	{ id = "groups", label = L["Groups"], glyph = "filter", desc = L["Insight sorts every item into the first group whose rules it matches. Change the order with the arrows."], custom = "Groups" },
	{ id = "junk", label = L["Junk & selling"], glyph = "junk", desc = L["What counts as junk, and selling it at vendors."], custom = "Junk", controls = {
		T("junk.autoSell", L["Sell junk at vendors by itself"], L["Locked items are never sold."], { "vendor", "sell", "grey", "gray" }),
		T("junk.summary", L["Say in chat what was sold"]),
		T("junk.poor", L["Poor (grey) items are junk"]),
		T("junk.buyback", L["Keep everything buyable back (sell at most 12 at a time)"]),
		T("junk.button", L["Sell junk button at vendors"]),
		T("junk.outgrown", L["Outgrown gear is junk"], L["Soulbound common and uncommon gear at least 10 item levels below what you wear in that slot. Never locked items or gear sets."], { "outgrown", "old gear" }),
		T("junk.freeSlot", L["\"Free a slot\" button when the bags are full"], L["Deletes the cheapest junk, after showing you what it is."], { "delete", "full" }),
	} },
	{ id = "bank", label = L["Bank & guild"], glyph = "bank", desc = L["The bank and guild bank windows, and opening the bags with other windows."], controls = {
		T("blizzard.bank", L["Use NetherBags instead of the game's bank window"]),
		T("blizzard.guild", L["Use NetherBags instead of the game's guild bank window"]),
		T("stash.tradeGoods", L["Stash button: trade goods to the bank in one click"]),
		H(L["Open the bags with"]),
		T("auto.merchant", L["Vendors"]), T("auto.bank", L["The bank"]), T("auto.mail", L["The mailbox"]), T("auto.auction", L["The auction house"]),
		T("auto.trade", L["Trades"]), T("auto.guild", L["The guild bank"]),
		T("auto.crafting", L["A profession window"]), T("auto.character", L["The character pane"]),
		T("auto.closeWith", L["...and close them again with that window"]),
		T("auto.closeCombat", L["Close the bags when combat starts"]),
		T("auto.closeMap", L["Close the bags when the world map opens"]),
		H(L["Sorting"]),
		T("sort.hint", L["The Sort button says how many slots a sort would free"]),
		T("sort.mergeAfter", L["Merge part stacks after the mailbox or a trade"]),
		T("bags.autoRoute", L["Put new items into the bag chosen for their kind (bag menu)"], L["Never in combat, nor at a vendor, the bank, the mailbox or a trade."], { "route", "bag menu", "assign" }),
	} },
	{ id = "search", label = L["Search"], glyph = "search", desc = L["The search box understands more than names."], custom = "SearchHelp", controls = {
		T("search.mail", L["Everywhere searches mailboxes"]),
		T("search.guild", L["Everywhere searches guild banks"]),
	} },
	{ id = "profiles", label = L["Profiles"], glyph = "user", desc = L["A profile holds every setting and your whole bag layout: groups, columns, sizes, window positions."], custom = "Profiles" },
	{ id = "plugins", label = L["Plugins"], glyph = "plus", desc = L["Addons made for NetherBags. Each can be switched off here."], custom = "Plugins" },
}

---------------------------------------------------------------------------------------------
-- the window
---------------------------------------------------------------------------------------------
local win
local function Build()
	win = CreateFrame("Frame", "NetherBagsConfig", UIParent)
	win:SetSize(900, 640)
	win:SetPoint("CENTER")
	win:SetFrameStrata("HIGH")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	win:Hide()
	Skin:Window(win)
	win.logo = W:Glyph(win, "backpack", 20, "accent")
	win.logo:SetPoint("TOPLEFT", 14, -10)
	win.title = W:Text(win, 17, "header", "title")
	win.title:SetPoint("LEFT", win.logo, "RIGHT", 8, 0)
	win.title:SetText("NetherBags")
	win.sub = W:Text(win, 11, "textDim")
	win.sub:SetPoint("LEFT", win.title, "RIGHT", 10, -1)
	win.sub:SetText(L["Settings"] .. "  ·  " .. NBG.VERSION)
	win.close = W:IconButton(win, "x", 22, { onClick = function() win:Hide() end })
	win.close:SetPoint("TOPRIGHT", -10, -9)
	local line = win:CreateTexture(nil, "ARTWORK")
	line:SetTexture(NBG.MEDIA .. "Fade")
	line:SetPoint("TOPLEFT", 10, -40) line:SetPoint("TOPRIGHT", -10, -40) line:SetHeight(1)
	Skin:Paint(line, "accent", { alpha = 0.6 })
	-- navigation
	win.nav = CreateFrame("Frame", nil, win)
	win.nav:SetPoint("TOPLEFT", 12, -52) win.nav:SetPoint("BOTTOMLEFT", 12, 12) win.nav:SetWidth(180)
	Skin:Panel(win.nav, { inset = true })
	win.navButtons = {}
	for i, p in ipairs(Config.PAGES) do
		local b = CreateFrame("Button", nil, win.nav)
		b:SetHeight(30)
		b:SetPoint("TOPLEFT", 4, -8 - (i - 1) * 34) b:SetPoint("TOPRIGHT", -4, -8 - (i - 1) * 34)
		b.hl = b:CreateTexture(nil, "BACKGROUND")
		b.hl:SetAllPoints() b.hl:SetTexture(NBG.MEDIA .. "FadeR")
		b.bar = b:CreateTexture(nil, "ARTWORK")
		b.bar:SetColorTexture(1, 1, 1, 1) b.bar:SetPoint("LEFT", 0, 0) b.bar:SetSize(2, 22)
		b.icon = W:Glyph(b, p.glyph, 14)
		b.icon:SetPoint("LEFT", 12, 0)
		b.text = W:Text(b, 12, "textDim", "medium")
		b.text:SetPoint("LEFT", 36, 0)
		b.text:SetText(p.label)
		b.page = p.id
		b:SetScript("OnClick", function() Config:Show(p.id) end)
		win.navButtons[i] = b
	end
	win.version = W:Text(win.nav, 9.5, "faint")
	win.version:SetPoint("BOTTOMLEFT", 12, 10)
	win.version:SetText("NetherBags " .. NBG.VERSION)
	-- page area
	win.head = W:Text(win, 16, "header", "caps")
	win.head:SetPoint("TOPLEFT", 212, -60)
	win.desc = W:Text(win, 10.5, "textDim")
	win.desc:SetPoint("TOPLEFT", win.head, "BOTTOMLEFT", 0, -6)
	win.desc:SetPoint("RIGHT", win, "RIGHT", -20, 0)
	win.desc:SetJustifyH("LEFT")
	win.pages = {}
	if _G.UISpecialFrames then table.insert(UISpecialFrames, "NetherBagsConfig") end
end

local function PaintNav(active)
	for _, b in ipairs(win.navButtons) do
		local on = b.page == active
		b.hl:SetShown(on) b.bar:SetShown(on)
		Skin:Paint(b.hl, "rowSel")
		Skin:Paint(b.bar, "header")
		Skin:Paint(b.icon, on and "header" or "textDim")
		Skin:Paint(b.text, on and "text" or "textDim")
	end
end

-- a page's scroll area with its controls laid out top to bottom
function Config:Controls(content, controls, y)
	y = y or 0
	local made = {}
	for _, c in ipairs(controls or {}) do
		if c.kind == "header" then
			local t = W:Text(content, 11, "header", "caps")
			t:SetPoint("TOPLEFT", 0, -y - 6)
			t:SetText(c.label:upper())
			y = y + 28
		elseif c.kind == "toggle" then
			local ch = W:Check(content, c.label, function() return Settings:Get(c.key) end, function(v) Settings:Set(c.key, v) end, c.sub)
			ch:SetPoint("TOPLEFT", 4, -y)
			ch:SetWidth(560)
			made[#made + 1] = ch
			y = y + (c.sub and 38 or 26)
		elseif c.kind == "slider" then
			local sl = W:Slider(content, c.label, c.min, c.max, c.step, function() return Settings:Get(c.key) end, function(v) Settings:Set(c.key, v) end, c.fmt)
			sl:SetPoint("TOPLEFT", 4, -y)
			sl:SetWidth(320)
			made[#made + 1] = sl
			y = y + 46
		elseif c.kind == "choice" then
			local lab = W:Text(content, 11.5, "text")
			lab:SetPoint("TOPLEFT", 4, -y - 5)
			lab:SetText(c.label)
			local dd = W:Dropdown(content, 220, c.values, function() return Settings:Get(c.key) end, function(v) Settings:Set(c.key, v) end)
			dd:SetPoint("TOPLEFT", 300, -y)
			made[#made + 1] = dd
			y = y + 32
		end
	end
	return y, made
end

function Config:Page(id)
	local p
	for _, x in ipairs(self.PAGES) do if x.id == id then p = x end end
	if not p then return nil end
	local page = win.pages[id]
	if page then return page, p end
	page = W:Scroll(win)
	page:SetPoint("TOPLEFT", 212, -100)
	page:SetPoint("BOTTOMRIGHT", -14, 14)
	page.def = p
	local y = 0
	if p.controls then
		local made
		y, made = self:Controls(page.content, p.controls, 0)
		page.controls = made
	end
	if p.custom and self["Page" .. p.custom] then
		NBG:Safe("settings page " .. p.custom, self["Page" .. p.custom], self, page, y)
		if page.customY then y = page.customY end
	end
	page:SetContentHeight(y + 20)
	win.pages[id] = page
	return page, p
end

function Config:Show(id, arg)
	if not win then Build() end
	for _, pg in pairs(win.pages) do pg:Hide() end
	local page, p = self:Page(id or "general")
	if not page then page, p = self:Page("general") end
	page:Show()
	for _, c in ipairs(page.controls or {}) do if c.Refresh then c:Refresh() end end
	if page.Refresh then NBG:Safe("settings page refresh", page.Refresh, page, arg) end
	win.head:SetText(p.label:upper())
	win.desc:SetText(p.desc or "")
	PaintNav(p.id)
	win.current = p.id
end

function Config:Open(id, arg)
	if not win then Build() end
	win:Show()
	self:Show(id or win.current or "general", arg)
end

function Config:Toggle()
	if win and win:IsShown() then win:Hide() else self:Open() end
end

-- a profile switch or import rebuilds the open page from the new profile
NBG:Register("PROFILE_CHANGED", function()
	if not win then return end
	for id, pg in pairs(win.pages) do pg:Hide() win.pages[id] = nil end
	if win:IsShown() then Config:Show(win.current) end
end)
