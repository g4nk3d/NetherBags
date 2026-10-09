--[[ NetherBags - UI/Insight.lua
	Insight: the inventory as a list, in the spirit of the Elder Scrolls Online inventory. Places
	along the top (Bags, Bank, Guild, Everywhere, Currencies), the category row, search, sortable
	columns (name, status, item level, value), and the items sorted into groups that open and
	close ("Gear > Armor [3]"). The footer has quick filters, slots, money and Sell junk.

	Live rows are the game's own item buttons drawn as a full-width row (UI/ItemButton.lua), so
	right-click uses an item and dragging moves it, exactly as in the game's bags. ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Insight = NBG:Module("Insight")
local Skin, W, Settings, Common = NBG.Skin, NBG.Widgets, NBG.Settings, NBG.Common
local Containers, Store, Buttons, Search, Groups, Rules, Items, Marks = NBG.Containers, NBG.Store, NBG.Buttons, NBG.Search, NBG.Groups, NBG.Rules, NBG.Items, NBG.Marks

local type, pairs, ipairs, max, min, floor = type, pairs, ipairs, math.max, math.min, math.floor
local lower = string.lower

local View = {}

local LOCS = {
	{ id = "bags", glyph = "backpack", label = L["Bags"] },
	{ id = "bank", glyph = "bank", label = L["Bank"] },
	{ id = "guild", glyph = "guild", label = L["Guild"] },
	{ id = "everywhere", glyph = "globe", label = L["Everywhere"] },
	{ id = "currency", glyph = "coins", label = L["Currencies"] },
}

local QUICK = {
	{ id = "new", label = L["New"], glyph = "new", role = "header", test = function(e) return e.new end },
	{ id = "upgrade", label = L["Upgrades"], glyph = "up", role = "positive", test = function(e) return e.live ~= false and Items:Upgrade(e) end },
	{ id = "unseen", label = L["Unseen looks"], glyph = "eye", role = "accent2", test = function(e) return Items:Unseen(e.link) end },
	{ id = "boe", label = L["BoE"], glyph = "link", role = "accent2", test = function(e) return Items:Binding(e) == "boe" end },
	{ id = "locked", label = L["Locked"], glyph = "lock", role = "header", test = function(e) return Marks:IsLocked(e.id) end },
}

function Insight:New(w)
	local v = setmetatable({ window = w, shown = false, cat = "all", quick = {} }, { __index = View })
	local f = CreateFrame("Frame", nil, w.body)
	f:SetAllPoints()
	f:Hide()
	v.frame = f
	-- places
	v.locs = {}
	local x = 14
	for i, loc in ipairs(LOCS) do
		local b = CreateFrame("Button", nil, f)
		b:SetHeight(30)
		b.icon = W:Glyph(b, loc.glyph, 14)
		b.icon:SetPoint("LEFT", 8, 0)
		b.text = W:Text(b, 12, "textDim", "medium")
		b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
		b.text:SetText(loc.label)
		b:SetWidth(floor((b.text:GetStringWidth() or 40) + 34))
		b.under = b:CreateTexture(nil, "ARTWORK")
		b.under:SetTexture(NBG.MEDIA .. "Pill")
		b.under:SetPoint("BOTTOMLEFT", 6, 0) b.under:SetPoint("BOTTOMRIGHT", -6, 0) b.under:SetHeight(2)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.loc = loc
		b:SetScript("OnClick", function() v:GoTo(loc.id) end)
		b:SetScript("OnEnter", function(self) if v.window.location ~= loc.id then Skin:Paint(self.text, "text") end end)
		b:SetScript("OnLeave", function(self) v:PaintLocs() end)
		v.locs[i] = b
	end
	v.locLine = f:CreateTexture(nil, "ARTWORK")
	v.locLine:SetColorTexture(1, 1, 1, 1)
	v.locLine:SetHeight(1)
	-- Everywhere's filters (shown next to the Everywhere tab while it is chosen)
	v.filterBtn = W:Button(f, L["Filters"], 90, 24, { glyph = "filter", size = 11, onClick = function(self) NBG.Everywhere:ToggleFilters(v, self) end })
	v.filterBtn:Hide()
	-- category row
	v.catLabel = W:Text(f, 14, "header", "caps")
	v.catSub = W:Text(f, 10, "textDim")
	v.cats = {}
	for i, c in ipairs(Groups.CATEGORIES) do
		local b = W:IconButton(f, c.glyph, 30, { tip = { c.label }, onClick = function() v.cat = c.id v:Refresh() end })
		v.cats[i] = b
	end
	v.junkCat = W:IconButton(f, "junk", 30, { tip = { L["Junk"] }, role = "textDim", onClick = function() v.cat = (v.cat == "junk") and "all" or "junk" v:Refresh() end })
	v.catSep = f:CreateTexture(nil, "ARTWORK")
	v.catSep:SetColorTexture(1, 1, 1, 1)
	v.catSep:SetSize(1, 22)
	v.catLine = f:CreateTexture(nil, "ARTWORK")
	v.catLine:SetTexture(NBG.MEDIA .. "Fade")
	v.catLine:SetHeight(1)
	-- search row
	v.search = W:Search(f, 300, 28, L["Search name, type, stat…   try  ilvl>20  boe  upgrade"], function(text)
		v.query = Search:Compile(text)
		NBG:Debounce("insightSearch" .. w.id, 0.12, function() v:Refresh(true) end)
	end)
	v.charBtn = W:Button(f, "", 130, 28, { glyph = "chev_d", onClick = function(self) Common:CharMenu(self, w) end })
	v.sortBtn = W:Button(f, L["Sort"], 74, 28, { glyph = "broom", onClick = function() NBG.Sort:Run(w.location) end, tip = { L["Sort the bags"], L["Moves the items in the bags themselves (locked items stay where they are)."] } })
	v.groupBtn = W:Button(f, L["Group by"], 96, 28, { glyph = "filter", onClick = function(self)
		local cur = Settings:Get("insight.groupBy")
		W:Menu(self, {
			{ text = L["Groups"], checked = cur == "groups", onClick = function() Settings:Set("insight.groupBy", "groups") end },
			{ text = w.location == "guild" and L["Tab"] or L["Bag"], checked = cur == "bag", onClick = function() Settings:Set("insight.groupBy", "bag") end },
			{ text = L["Nothing (one list)"], checked = cur == "none", onClick = function() Settings:Set("insight.groupBy", "none") end },
			"-",
			{ text = L["Edit groups…"], glyph = "pen", onClick = function() NBG.Config:Open("groups") end },
		})
	end })
	v.newGroupBtn = W:IconButton(f, "plus", 26, { tip = { L["New group"], L["Make your own group with rules (Settings > Groups)."] }, onClick = function()
		local id = Groups:NewCustom()
		NBG.Config:Open("groups", id)
	end })
	v.stashBtn = W:Button(f, L["Stash trade goods"], 140, 28, { style = "gold", glyph = "deposit", onClick = function() NBG.Stash:Run() end })
	-- Move: what the list shows, to the window that is open (bank, mail, trade; from the bank: the bags)
	v.moveBtn = W:Button(f, L["Move"], 84, 28, { glyph = "deposit", onClick = function() v:MoveShown() end })
	v.moveBtn:HookScript("OnEnter", function(self)
		local target, label = NBG.Transfer:Target(w)
		if not target then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText((L["Move what the list shows to %s"]):format(label), 1, 0.86, 0.55)
		GameTooltip:AddLine((L["%d stack(s)"]):format(v.shownCount or 0), 1, 1, 1)
		GameTooltip:AddLine(L["Locked items stay. Soulbound items never go to the mail or a trade."], 0.6, 0.65, 0.75, true)
		GameTooltip:Show()
	end)
	v.moveBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
	-- save the search as a group of your own
	v.saveBtn = W:IconButton(f, "filter", 26, { tip = { L["Save this search as a group"], L["A group of your own that holds what this search finds (Settings > Groups)."] }, onClick = function()
		if not v.query then return end
		local id = Groups:NewCustom()
		local g = Settings:Profile().groups.custom[id]
		if g then
			g.name = v.query.text:sub(1, 40)
			g.rules = { { p = "search", o = "match", v = v.query.text } }
			g.match = "all"
			Groups:SaveCustom(id, g)
			NBG:Print(L["New group \"%s\" made from the search."], g.name)
		end
	end })
	-- bank / guild chips row
	v.chipRow = CreateFrame("Frame", nil, f)
	v.chipRow:SetHeight(22)
	v.chips = {}
	-- columns
	v.head = CreateFrame("Frame", nil, f)
	v.head:SetHeight(20)
	v.heads = {}
	for _, k in ipairs({ "name", "status", "extra", "ilvl", "value" }) do
		local b = CreateFrame("Button", nil, v.head)
		b:SetHeight(20)
		b.text = W:Text(b, 9.5, "textDim", "bold")
		b.text:SetPoint("CENTER")
		b.arrow = W:Glyph(b, "chev_d", 8, "accent")
		b.arrow:SetPoint("LEFT", b.text, "RIGHT", 3, 0)
		b.key = k
		b:SetScript("OnClick", function()
			local sortKey = ({ name = "name", ilvl = "ilvl", value = "value", extra = "count" })[k]
			if not sortKey then return end
			if Settings:Get("insight.sort") == sortKey then Settings:Set("insight.sortDesc", not Settings:Get("insight.sortDesc"))
			else Settings:Set("insight.sort", sortKey) Settings:Set("insight.sortDesc", sortKey ~= "name") end
		end)
		v.heads[k] = b
	end
	v.headLine = v.head:CreateTexture(nil, "ARTWORK")
	v.headLine:SetTexture(NBG.MEDIA .. "Fade")
	v.headLine:SetPoint("BOTTOMLEFT", 0, 0) v.headLine:SetPoint("BOTTOMRIGHT", 0, 0) v.headLine:SetHeight(1)
	-- the list
	v.scroll = W:Scroll(f)
	v.scroll.step = 60
	v.ribbon = Common:Ribbon(f)
	v.empty = W:Text(v.scroll.content, 12, "textDim")
	v.empty:SetPoint("TOP", 0, -40)
	v.empty:SetWordWrap(true)
	v.headers = {}
	v.everyRows = {}
	-- footer and quick filters
	v.footer = Common:Footer(f)
	v.footer:SetPoint("BOTTOMLEFT") v.footer:SetPoint("BOTTOMRIGHT")
	v.quickChips = {}
	for i, q in ipairs(QUICK) do
		local c = W:Chip(v.footer, q.label, q.glyph, q.role, function(on) v.quick[q.id] = on or nil v:Refresh(true) end)
		v.quickChips[i] = c
	end
	NBG:Register("SEARCH_SET", function(_, id, text) if id == w.id and v.shown then v.search:SetText(text) v.query = Search:Compile(text) v:Refresh() end end)
	return v
end

function View:Show()
	self.shown = true
	self.frame:Show()
	local w = self.window
	local s = w:LayoutStore()
	w:SetSize(s.w or 800, s.h or 640)
	w.grip:Show()
end

function View:Hide()
	self.shown = false
	if NBG.Everywhere then NBG.Everywhere:HideFilters() end
	self.frame:Hide()
	if self.hostPlace then
		Buttons:HideAll(self.hostPlace)
		Buttons:Host(self.hostPlace):Hide()
		self.hostPlace = nil
	end
end

function View:GoTo(loc)
	local w = self.window
	-- the live bank and the open guild bank have their own windows
	if loc == "bank" and Containers:BankOpen() and w.id ~= "bank" and w.owner == NBG:PlayerKey() then NBG.Windows:Open("bank") return end
	if loc == "guild" and NBG.GuildBank and NBG.GuildBank:IsOpen() and w.id ~= "guild" then NBG.Windows:Open("guild") return end
	if loc == "bags" and w.id ~= "bags" then NBG.Windows:Open("bags") return end
	self.cat = "all"
	w:SetLocation(loc)
end

function View:PaintLocs()
	local w = self.window
	for _, b in ipairs(self.locs) do
		local on = w.location == b.loc.id
		Skin:Paint(b.text, on and "text" or "textDim")
		Skin:Paint(b.icon, on and "header" or "textDim")
		b.under:SetShown(on)
		Skin:Paint(b.under, "header")
		b.bg:SetShown(on)
		Skin:Gradient(b.bg, "VERTICAL", "bg", "rowSel", 0, 0.7)
	end
end

local function GuildAvailable()
	if not (NBG.GuildBank and NBG.GuildBank:Available()) then return false end
	return true
end

---------------------------------------------------------------------------------------------
-- building the list
---------------------------------------------------------------------------------------------
local function Header(v, i)
	local h = v.headers[i]
	if h then return h end
	h = CreateFrame("Button", nil, v.scroll.content)
	h:SetHeight(24)
	h.bg = h:CreateTexture(nil, "BACKGROUND")
	h.bg:SetAllPoints()
	h.bg:SetTexture(NBG.MEDIA .. "FadeR")
	h.chev = W:Glyph(h, "chev_d", 10, "accent")
	h.chev:SetPoint("LEFT", 8, 0)
	h.icon = W:Glyph(h, "star", 12)
	h.icon:SetPoint("LEFT", 24, 0)
	h.text = W:Text(h, 11, "header", "caps")
	h.text:SetPoint("LEFT", h.icon, "RIGHT", 6, 0)
	h.count = W:Text(h, 10.5, "textDim", "medium")
	h.count:SetPoint("LEFT", h.text, "RIGHT", 5, 0)
	h.line = h:CreateTexture(nil, "ARTWORK")
	h.line:SetTexture(NBG.MEDIA .. "FadeR")
	h.line:SetPoint("BOTTOMLEFT") h.line:SetPoint("BOTTOMRIGHT") h.line:SetHeight(1)
	h.action = W:Button(h, "", 120, 20, { style = "red", size = 10.5 })
	h.action:SetPoint("RIGHT", -6, 0)
	h.action:Hide()
	h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	h:SetScript("OnClick", function(self, btn)
		if btn == "RightButton" then
			local target, label = NBG.Transfer:Target(v.window)
			W:Menu("cursor", {
				{ text = self.label or "", disabled = true },
				"-",
				{ text = target and (L["Move this group to %s"]):format(label) or L["Move this group (at the bank, mailbox or a trade)"], glyph = "deposit",
					disabled = not target, onClick = function() NBG.Transfer:Run(self.items, target) end },
			})
			return
		end
		local c = Settings:Profile().layout.collapsed
		c[self.key] = not c[self.key] or nil
		Settings:Touch()
		v:Refresh(true)
	end)
	v.headers[i] = h
	return h
end

local SORTS = {
	name = function(i) return i and lower(i.name or "") or "" end,
	ilvl = function(i) return i and i.ilvl or 0 end,
	value = function(i, e) return i and (i.price or 0) * (e.count or 1) or 0 end,
	count = function(i, e) return e.count or 1 end,
	quality = function(i, e) return e.quality or (i and i.quality) or 0 end,
}

function View:Columns(width)
	local w = width - 24
	local loc = self.window.location
	local cols = { name = 62, status = floor(w * 0.52), ilvl = floor(w * 0.80), value = w - 6 }
	if loc == "bank" or loc == "guild" then cols.extra = floor(w * 0.68) cols.status = floor(w * 0.47) end
	return cols
end

function View:Collect()
	local w = self.window
	local entries = w:Entries()
	local cat
	if self.cat == "junk" then cat = Groups.JUNK_CATEGORY
	else for _, c in ipairs(Groups.CATEGORIES) do if c.id == self.cat then cat = c end end end
	local out = {}
	local q = self.query
	local counts = {}
	for _, e in ipairs(entries) do
		local okCat = not cat or cat.test(e)
		local okQ = not q or Search:Match(e, q)
		local okQuick = not self.bagFilter or e.bag == self.bagFilter
		for _, qd in ipairs(QUICK) do if self.quick[qd.id] and not qd.test(e) then okQuick = false end end
		if okCat and okQ and okQuick then out[#out + 1] = e end
		if okQ then for _, c in ipairs(Groups.CATEGORIES) do if c.test(e) then counts[c.id] = (counts[c.id] or 0) + 1 end end end
		if Marks:IsJunk(e) then counts.junk = (counts.junk or 0) + 1 end
	end
	return out, entries, counts
end

function View:Refresh(light)
	local w = self.window
	local f = self.frame
	local width = w:GetWidth()
	if w.location == "everywhere" or w.location == "currency" then w.owner = NBG:PlayerKey() end
	if w.location == "guild" and not GuildAvailable() then w.location = "bags" end
	-- places
	local x = 14
	for _, b in ipairs(self.locs) do
		local show = b.loc.id ~= "guild" or GuildAvailable()
		b:SetShown(show)
		if show then b:ClearAllPoints() b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -4) x = x + b:GetWidth() + 2 end
		if b.loc.id == "everywhere" then
			local on = w.location == "everywhere"
			self.filterBtn:SetShown(on)
			if on then
				local n = NBG.Everywhere:Narrowed()
				self.filterBtn:SetLabel(n > 0 and (L["Filters"] .. "  |cff6fd2f5(" .. n .. ")|r") or L["Filters"])
				self.filterBtn:SetWidth(max(84, (self.filterBtn.label:GetStringWidth() or 40) + 40))
				self.filterBtn:ClearAllPoints() self.filterBtn:SetPoint("TOPLEFT", f, "TOPLEFT", x + 2, -7)
				x = x + self.filterBtn:GetWidth() + 8
			else
				NBG.Everywhere:HideFilters()
			end
		end
	end
	self:PaintLocs()
	self.locLine:ClearAllPoints() self.locLine:SetPoint("TOPLEFT", 10, -34) self.locLine:SetPoint("TOPRIGHT", -10, -34)
	Skin:Paint(self.locLine, "border", { alpha = 0.8 })
	local special = w.location == "everywhere" or w.location == "currency"
	-- category row
	local filtered, all, counts = {}, {}, {}
	if not special then filtered, all, counts = self:Collect() end
	local catLabel = L["All items"]
	for _, c in ipairs(Groups.CATEGORIES) do if c.id == self.cat then catLabel = c.label end end
	if self.cat == "junk" then catLabel = L["Junk"] end
	if w.location == "everywhere" then catLabel = L["Everywhere"] elseif w.location == "currency" then catLabel = L["Currencies"] end
	if w.location == "guild" and NBG.GuildBank then catLabel = NBG.GuildBank:Name() or L["Guild bank"] end
	self.catLabel:SetText(catLabel:upper())
	self.catLabel:ClearAllPoints() self.catLabel:SetPoint("TOPLEFT", 16, -46)
	self.catSub:ClearAllPoints() self.catSub:SetPoint("TOPLEFT", self.catLabel, "BOTTOMLEFT", 1, -5)
	if w.location == "everywhere" then self.catSub:SetText(L["Every character, bank, mailbox and guild bank this account has seen"])
	elseif w.location == "currency" then self.catSub:SetText(L["This character's currencies"])
	else
		local total = 0
		for _, b in ipairs(w:BagList()) do if not b.nbSpecial then total = total + (b.size or 0) end end
		self.catSub:SetText(("%d %s  ·  %d %s"):format(#all, L["items"], max(0, total - #all), L["slots free"]))
	end
	local s = 30
	local jx = width - 14 - s
	self.junkCat:ClearAllPoints() self.junkCat:SetPoint("TOPLEFT", f, "TOPLEFT", jx, -44)
	self.junkCat:SetShown(not special)
	self.junkCat:SetActive(self.cat == "junk")
	self.junkCat:SetBadge(not special and counts.junk or nil)
	self.catSep:ClearAllPoints() self.catSep:SetPoint("TOPLEFT", f, "TOPLEFT", jx - 9, -48)
	self.catSep:SetShown(not special)
	Skin:Paint(self.catSep, "border")
	-- the icons sit right of the label; what doesn't fit there moves to a row below (and another,
	-- if need be), right-aligned, so every category can still be seen and picked
	local step, n = s + 2, #self.cats
	local rightEdge = jx - 16
	local labelW = max(self.catLabel:GetStringWidth() or 0, special and 0 or (self.catSub:GetStringWidth() or 0))
	local cap1 = max(0, floor((rightEdge - (16 + labelW + 14) + 2) / step))
	local capN = max(1, floor((rightEdge - 14 + 2) / step))
	local place, row, inRow, rowCap, rowStart = {}, 1, 0, min(n, cap1), 1
	local rowsOf = {}
	for i = 1, n do
		if inRow >= rowCap then row, inRow, rowCap = row + 1, 0, capN end
		inRow = inRow + 1
		place[i] = row
		rowsOf[row] = (rowsOf[row] or 0) + 1
	end
	local catRows = special and 1 or row
	self.catRows = catRows
	local idx = {}
	for i, b in ipairs(self.cats) do
		local r = place[i]
		idx[r] = (idx[r] or 0) + 1
		local cx = rightEdge - rowsOf[r] * step + 2
		b:ClearAllPoints() b:SetPoint("TOPLEFT", f, "TOPLEFT", cx + (idx[r] - 1) * step, -44 - (r - 1) * 34)
		b:SetShown(not special)
		b:SetActive(self.cat == Groups.CATEGORIES[i].id)
		local c = Groups.CATEGORIES[i].id
		b:SetEnabled(c == "all" or (counts[c] or 0) > 0)
	end
	local extra = (catRows - 1) * 34
	self.catLine:ClearAllPoints() self.catLine:SetPoint("TOPLEFT", 10, -84 - extra) self.catLine:SetPoint("TOPRIGHT", -10, -84 - extra)
	Skin:Paint(self.catLine, "accent", { alpha = 0.45 })
	-- search row
	local y = -92 - extra
	self.search:ClearAllPoints() self.search:SetPoint("TOPLEFT", 14, y)
	local live = w:Live()
	self.charBtn:SetLabel(w.owner or NBG:PlayerKey())
	self.charBtn:SetWidth(max(110, min(180, (self.charBtn.label:GetStringWidth() or 80) + 44)))
	local target = NBG.Transfer and NBG.Transfer:Target(w)
	-- the Sort button says how many slots a sort would free
	if live and (w.location == "bags" or w.location == "bank") then
		local n = (Settings:Get("sort.hint") and NBG.Sort.Freeable) and NBG.Sort:Freeable(w.location) or 0
		self.sortBtn:SetLabel(n > 0 and (L["Sort"] .. "  |cff5cdc6e+" .. n .. "|r") or L["Sort"])
		self.sortBtn:SetWidth(max(74, (self.sortBtn.label:GetStringWidth() or 40) + 44))
		self.sortBtn.freeable = n
	end
	local tools = {
		{ self.saveBtn, self.query ~= nil and not special },
		{ self.moveBtn, target ~= nil and not special },
		{ self.newGroupBtn, not special },
		{ self.stashBtn, live and w.location == "bank" and Settings:Get("stash.tradeGoods") },
		{ self.groupBtn, not special },
		{ self.sortBtn, live and (w.location == "bags" or w.location == "bank") },
		{ self.charBtn, w.location == "bags" or w.location == "bank" },
	}
	local toolsW = 0
	for _, t in ipairs(tools) do if t[2] then toolsW = toolsW + t[1]:GetWidth() + 6 end end
	local MIN_SEARCH = 220
	local ownRow = (width - 14 - toolsW) - 14 - 4 < MIN_SEARCH
	self.toolsOwnRow = ownRow
	local ty = ownRow and (y - 34) or y
	local rx = width - 14
	for _, t in ipairs(tools) do
		local b, show = t[1], t[2] and true or false
		b:SetShown(show)
		if show then
			b:ClearAllPoints() b:SetPoint("TOPRIGHT", f, "TOPLEFT", rx, ty)
			rx = rx - b:GetWidth() - 6
		end
	end
	if ownRow then self.search:SetWidth(width - 28)
	else self.search:SetWidth(max(160, rx - 14 - 4)) end
	y = y - 34
	if ownRow then y = y - 34 end
	-- the guild bar (withdrawals, money, log) / the bank's bag filter
	if w.location == "guild" then
		self.guildBar = self.guildBar or NBG.GuildUI:TabBar(f, self, false)
		self.guildBar:ClearAllPoints() self.guildBar:SetPoint("TOPLEFT", 14, y) self.guildBar:SetPoint("RIGHT", -14, 0)
		self.guildBar:Show()
		self.guildBar:Update(w)
		y = y - 28
	elseif self.guildBar then
		self.guildBar:Hide()
	end
	if w.location == "bank" then
		self:BagChips(y)
		y = y - 28
	else
		self.chipRow:Hide()
		self.bagFilter = nil
	end
	-- the offline note
	if self.ribbon:Update(w) then
		self.ribbon:ClearAllPoints() self.ribbon:SetPoint("TOPLEFT", 14, y) self.ribbon:SetPoint("RIGHT", -14, 0)
		y = y - 28
	end
	-- column headers
	local cols = self:Columns(width)
	self.cols = cols
	self.head:ClearAllPoints() self.head:SetPoint("TOPLEFT", 10, y) self.head:SetPoint("RIGHT", -24, 0)
	self.head:SetShown(not special)
	Skin:Paint(self.headLine, "border")
	local sortKey, desc = Settings:Get("insight.sort"), Settings:Get("insight.sortDesc")
	local headDefs = {
		name = { L["NAME"], cols.name, "LEFT", "name" },
		status = Settings:Get("insight.colStatus") and { L["STATUS"], cols.status, "LEFT" } or nil,
		extra = cols.extra and { w.location == "guild" and L["TAB"] or L["WHERE"], cols.extra, "CENTER", "count" } or nil,
		ilvl = Settings:Get("insight.colIlvl") and { L["ILVL"], cols.ilvl, "CENTER", "ilvl" } or nil,
		value = Settings:Get("insight.colValue") and { L["VALUE"], cols.value, "RIGHT", "value" } or nil,
	}
	for k, b in pairs(self.heads) do
		local d = headDefs[k]
		b:SetShown(d ~= nil)
		if d then
			b.text:SetText(d[1])
			local tw = (b.text:GetStringWidth() or 30) + 14
			b:SetWidth(tw)
			b:ClearAllPoints()
			if d[3] == "LEFT" then b:SetPoint("LEFT", self.head, "LEFT", d[2] - 2, 0)
			elseif d[3] == "RIGHT" then b:SetPoint("RIGHT", self.head, "LEFT", d[2] + 10, 0)
			else b:SetPoint("CENTER", self.head, "LEFT", d[2], 0) end
			b.arrow:SetShown(d[4] ~= nil and d[4] == sortKey)
			W:SetGlyph(b.arrow, desc and "chev_d" or "chev_r")
			Skin:Paint(b.text, d[4] == sortKey and "accent" or "textDim")
		end
	end
	if not special then y = y - 24 end
	self.listTop = y
	self:LayoutFooter(w, special, all)
	-- the content
	if w.location == "everywhere" then
		self:HideRows()
		NBG.Everywhere:Render(self)
	elseif w.location == "currency" then
		self:HideRows()
		NBG.Everywhere:RenderCurrencies(self)
	else
		if NBG.Everywhere then NBG.Everywhere:Hide(self) end
		self:BuildList(filtered)
	end
end

-- the footer: slots on the left, money (and currencies, Sell junk) on the right, the quick
-- filters between; the filters that don't fit move to a second row above, until it's wider again
function View:LayoutFooter(w, special, all)
	local ft = self.footer
	ft:Update(w, all)
	local width = w:GetWidth()
	local showChips = not special and Settings:Get("footer.chips")
	local left = 16 + 18 + 7 + max(ft.slots:GetStringWidth() or 0, ft.sub:IsShown() and (ft.sub:GetStringWidth() or 0) or 60) + 16
	left = max(left, 110)
	local rightUsed = ft.rightWidth or (18 + (ft.money:GetStringWidth() or 0) + 12)
	local limit1 = width - rightUsed
	local x1, x2, second = left, 16, false
	for i, c in ipairs(self.quickChips) do
		c:SetShown(showChips)
		c:SetOn(self.quick[QUICK[i].id])
		c:ClearAllPoints()
		local cw = c:GetWidth()
		if not second and x1 + cw <= limit1 then
			c:SetPoint("LEFT", ft, "LEFT", x1, 0)
			x1 = x1 + cw + 6
		else
			second = true
			c:SetPoint("LEFT", ft, "LEFT", x2, 30)
			x2 = x2 + cw + 6
		end
	end
	second = second and showChips
	self.footRows = second and 2 or 1
	ft.line:ClearAllPoints()
	ft.line:SetPoint("TOPLEFT", 10, second and 30 or 0) ft.line:SetPoint("TOPRIGHT", -10, second and 30 or 0)
	self.scroll:ClearAllPoints()
	self.scroll:SetPoint("TOPLEFT", 10, self.listTop or -150)
	self.scroll:SetPoint("BOTTOMRIGHT", -8, second and 78 or 48)
end

function View:BagChips(y)
	local w = self.window
	local row = self.chipRow
	row:ClearAllPoints() row:SetPoint("TOPLEFT", 14, y) row:SetPoint("RIGHT", -14, 0)
	row:Show()
	local list = { { id = nil, label = L["Everything"], glyph = "all" } }
	for i, info in ipairs(w:BagList()) do
		if (info.size or 0) > 0 then
			local label = info.kind == "tab" and (info.name or (L["Tab"] .. " " .. i)) or (info.id == Containers.BANK and L["Bank slots"] or (L["Bag"] .. " " .. (i - 1)))
			list[#list + 1] = { id = info.id, label = label, glyph = info.kind == "tab" and "bank" or "bag" }
		end
	end
	local x = 0
	for i, it in ipairs(list) do
		local c = self.chips[i]
		if not c then c = W:Chip(row, "", "bag", "accent", nil) self.chips[i] = c end
		c:SetLabel(it.label)
		W:SetGlyph(c.icon, it.glyph)
		c:ClearAllPoints() c:SetPoint("LEFT", x, 0)
		c:SetOn(self.bagFilter == it.id)
		c:SetScript("OnClick", function() self.bagFilter = it.id self:Refresh(true) end)
		c:Show()
		x = x + c:GetWidth() + 6
	end
	for i = #list + 1, #self.chips do self.chips[i]:Hide() end
end

function View:MoveShown()
	local target, label = NBG.Transfer:Target(self.window)
	if not target then return end
	local list = self.shownItems or {}
	local filtered = self.query or self.cat ~= "all" or next(self.quick) or self.bagFilter
	if filtered then NBG.Transfer:Run(list, target) return end
	W:Popup({ title = L["Move everything?"], width = 400,
		text = (L["No search or filter is on: this moves every item in the list (%d stacks) to %s. Locked items stay."]):format(#list, label),
		buttons = { { label = L["Move"], style = "gold", onClick = function() NBG.Transfer:Run(list, target) end }, { label = L["Cancel"] } } })
end

function View:HideRows()
	for _, h in ipairs(self.headers) do h:Hide() end
	if self.hostPlace then Buttons:HideAll(self.hostPlace) Buttons:Host(self.hostPlace):Hide() self.hostPlace = nil end
	for i = 1, (self.offMax or 0) do Buttons:Offline("insight_" .. self.window.id, i, self.scroll.content):Hide() end
	self.empty:Hide()
end

-- items -> groups -> rows
function View:BuildList(items)
	self.shownItems = items
	self.shownCount = #items
	local w = self.window
	local live = w:Live()
	local place = w.location
	local rh = Settings:Get("insight.rowHeight")
	local width = self.scroll:GetWidth() - 12
	if width < 100 then width = w:GetWidth() - 30 end
	local cols = self.cols
	local by = Settings:Get("insight.groupBy")
	local sortKey, desc = Settings:Get("insight.sort"), Settings:Get("insight.sortDesc")
	local keyFn = SORTS[sortKey] or SORTS.name
	-- buckets
	local buckets, order = {}, {}
	local function Bucket(key, label, glyph, color, gid)
		local b = buckets[key]
		if not b then b = { key = key, label = label, glyph = glyph, color = color, gid = gid, items = {} } buckets[key] = b order[#order + 1] = b end
		return b
	end
	if by == "groups" then
		local glist = Groups:List()
		local rank = {}
		for i, g in ipairs(glist) do rank[g.id] = i end
		for _, e in ipairs(items) do
			local gid, sub = Groups:Classify(e)
			local g = Groups:Get(gid) or Groups:Get("misc")
			local key = gid .. (sub and ("|" .. sub) or "")
			local label = g.label .. (sub and (" > " .. sub) or "")
			local b = Bucket(key, label, g.glyph, g.color, gid)
			b.rank = (rank[gid] or 99) + (sub and 0.001 or 0)
			b.items[#b.items + 1] = e
		end
		table.sort(order, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.label < b.label end)
	elseif by == "bag" then
		local names = {}
		for i, info in ipairs(w:BagList()) do names[info.id] = { i = i, name = info.name or (L["Bag"] .. " " .. i) } end
		for _, e in ipairs(items) do
			local n = names[e.bag] or { i = 99, name = L["Other"] }
			local b = Bucket("bag" .. tostring(e.bag), n.name, w.location == "guild" and "guild" or "bag", nil, nil)
			b.rank = n.i
			b.items[#b.items + 1] = e
		end
		table.sort(order, function(a, b) return a.rank < b.rank end)
	else
		local b = Bucket("all", L["Everything"], "all")
		for _, e in ipairs(items) do b.items[#b.items + 1] = e end
	end
	-- keep the rows where they are while the window stays open: the layout of the last full build
	-- is reused, items that left keep an empty row, items that arrived go at the end of their group
	-- (until the window closes, the bags are sorted, or the search, filters or grouping change)
	local quickSig = {}
	for k in pairs(self.quick) do quickSig[#quickSig + 1] = k end
	table.sort(quickSig)
	local sig = table.concat({ place, tostring(w.owner), tostring(self.cat), self.query and self.query.text or "", table.concat(quickSig, ","),
		tostring(self.bagFilter), sortKey, tostring(desc), by, tostring(live), tostring(w.showToken) }, "|")
	local hold = self.hold
	local holding = live and Settings:Get("insight.keepPlace") and hold and hold.sig == sig
	if holding then
		local cur, used = {}, {}
		for _, b in ipairs(order) do for _, e in ipairs(b.items) do if e.bag and e.slot then cur[e.bag .. ":" .. e.slot] = { e = e, b = b } end end end
		local byKey = {}
		local newOrder = {}
		for _, hb in ipairs(hold.buckets) do
			local src = buckets[hb.key]
			local nb = { key = hb.key, label = hb.label, glyph = hb.glyph, color = hb.color, gid = hb.gid, rank = hb.rank, items = {}, held = true }
			for _, slot in ipairs(hb.slots) do
				local c = cur[slot.k]
				if c and c.e.id == slot.id then
					nb.items[#nb.items + 1] = c.e
					used[c.e] = true
				else
					nb.items[#nb.items + 1] = { ghost = true }
				end
			end
			if src then nb.label, nb.glyph, nb.color = src.label, src.glyph, src.color end
			byKey[hb.key] = nb
			newOrder[#newOrder + 1] = nb
		end
		for _, b in ipairs(order) do
			for _, e in ipairs(b.items) do
				if not used[e] then
					local nb = byKey[b.key]
					if not nb then
						nb = { key = b.key, label = b.label, glyph = b.glyph, color = b.color, gid = b.gid, rank = b.rank, items = {}, held = true }
						byKey[b.key] = nb
						newOrder[#newOrder + 1] = nb
					end
					nb.items[#nb.items + 1] = e
				end
			end
		end
		order = newOrder
	end
	-- the host for live rows
	if live then
		self.hostPlace = place
		local host = Buttons:Host(place)
		host:SetParent(self.scroll.content)
		host:ClearAllPoints()
		host:SetAllPoints(self.scroll.content)
		host:SetFrameLevel(self.scroll.content:GetFrameLevel() + 2)
		host:Show()
		Buttons:Prepare(place)
	elseif self.hostPlace then
		Buttons:HideAll(self.hostPlace) Buttons:Host(self.hostPlace):Hide() self.hostPlace = nil
	end
	local collapsed = Settings:Profile().layout.collapsed
	local y, hN, offN = 0, 0, 0
	local shown = {}
	local scope = w.location .. ":"
	for _, b in ipairs(order) do
		local defCollapsed = false
		if b.gid then local g = Groups:Get(b.gid) defCollapsed = g and g.custom and g.def.collapsed end
		local key = scope .. b.key
		local isCollapsed = collapsed[key]
		if isCollapsed == nil then isCollapsed = defCollapsed end
		if not b.held then table.sort(b.items, function(x, z)
			local ix, iz = Rules.InfoOf(x), Rules.InfoOf(z)
			local vx, vz = keyFn(ix, x), keyFn(iz, z)
			if vx ~= vz then if desc then return vx > vz end return vx < vz end
			local nx, nz = ix and ix.name or "", iz and iz.name or ""
			if nx ~= nz then return nx < nz end
			if (x.bag or 0) ~= (z.bag or 0) then return (x.bag or 0) < (z.bag or 0) end
			return (x.slot or 0) < (z.slot or 0)
		end) end
		local real = 0
		for _, e in ipairs(b.items) do if not e.ghost then real = real + 1 end end
		hN = hN + 1
		local h = Header(self, hN)
		h.key = key
		h.items, h.label = b.items, b.label
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", self.scroll.content, "TOPLEFT", 0, -y)
		h:SetPoint("RIGHT", self.scroll.content, "RIGHT")
		W:SetGlyph(h.chev, isCollapsed and "chev_r" or "chev_d")
		W:SetGlyph(h.icon, b.glyph or "star")
		if b.color then Skin:Unpaint(h.icon) h.icon:SetVertexColor(b.color[1], b.color[2], b.color[3]) else Skin:Paint(h.icon, "accent") end
		local parts = {}
		for p in (b.label .. " > "):gmatch("(.-) > ") do parts[#parts + 1] = p:upper() end
		h.text:SetText(table.concat(parts, "  |cff8c96b0»|r  "))
		h.count:SetText("[" .. real .. "]")
		Skin:Gradient(h.bg, "HORIZONTAL", "bgTop", "bg", 0.95, 0)
		Skin:Paint(h.line, "accent", { alpha = 0.4 })
		-- Sell on the junk group at a vendor
		if b.gid == "junk" and live and place == "bags" and NBG.Selling:AtMerchant() then
			local n, value = NBG.Selling:JunkValue()
			h.action:SetLabel(L["Sell all"] .. "  " .. W:Money(value))
			h.action:SetWidth(max(110, (h.action.label:GetStringWidth() or 60) + 30))
			h.action:SetScript("OnClick", function() NBG.Selling:SellJunk(true) end)
			h.action:SetShown(n > 0)
		else
			h.action:Hide()
		end
		h:Show()
		y = y + 26
		if not isCollapsed then
			for _, e in ipairs(b.items) do
				local btn
				if e.ghost then
					y = y + rh                    -- an item that left: its row stays empty until the window closes
				elseif live and e.bag and e.slot and e.live ~= false then
					btn = Buttons:Live(e.bag, e.slot)
				else
					offN = offN + 1
					btn = Buttons:Offline("insight_" .. w.id, offN, self.scroll.content)
					btn.nbOnClick = nil
					if w.location == "guild" and NBG.GuildBank then NBG.GuildBank:BindRow(btn, e) end
				end
				if btn then
					btn:ClearAllPoints()
					btn:SetPoint("TOPLEFT", self.scroll.content, "TOPLEFT", 0, -y)
					btn:NBRow(width, rh, cols)
					local extra
					if cols.extra then
						if w.location == "guild" then extra = L["Tab"] .. " " .. tostring(e.tab or "")
						else
							for i, info in ipairs(w:BagList()) do if info.id == e.bag then extra = info.kind == "tab" and (info.name or (L["Tab"] .. " " .. i)) or (info.id == Containers.BANK and L["Bank"] or (L["Bag"] .. " " .. (i - 1))) end end
						end
					end
					btn:Show()
					btn:NBPaint(e, { hover = false, extra = extra })
					if btn.nbLive then btn:NBCooldown() end
					shown[btn] = true
					y = y + rh
				end
			end
			y = y + 6
		end
	end
	for i = hN + 1, #self.headers do self.headers[i]:Hide() end
	-- the layout to hold from now on
	if live and Settings:Get("insight.keepPlace") and not holding then
		local hb = {}
		for _, b in ipairs(order) do
			local slots = {}
			for _, e in ipairs(b.items) do if e.bag and e.slot then slots[#slots + 1] = { k = e.bag .. ":" .. e.slot, id = e.id } end end
			hb[#hb + 1] = { key = b.key, label = b.label, glyph = b.glyph, color = b.color, gid = b.gid, rank = b.rank, slots = slots }
		end
		self.hold = { sig = sig, buckets = hb }
	elseif not live then
		self.hold = nil
	end
	if live then Buttons:HideAll(place, shown) end
	for i = offN + 1, (self.offMax or 0) do Buttons:Offline("insight_" .. w.id, i, self.scroll.content):Hide() end
	self.offMax = max(self.offMax or 0, offN)
	if #order == 0 then
		self.empty:SetWidth(width - 40)
		self.empty:SetText(self.query and L["Nothing matches the search."] or (w:Age() and w:Age():find(L["Never seen"]) and w:Age()) or L["Nothing here."])
		self.empty:Show()
		y = 80
	else
		self.empty:Hide()
	end
	self.scroll:SetContentHeight(y)
end

-- row hover highlight (live and offline rows)
NBG:Register("ITEM_ENTER", function(_, b) if b.nbLook == "row" and b.nbEntry then b.nb.rowHl:Show() b.nb.rowBar:Show() end end)
NBG:Register("ITEM_LEAVE", function(_, b) if b.nbLook == "row" then b.nb.rowHl:Hide() b.nb.rowBar:Hide() end end)
