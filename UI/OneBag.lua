--[[ NetherBags - UI/OneBag.lua
	One bag: every slot of every bag in one grid, the way the bags really are. Special bags
	(quivers, ammo pouches, soul bags, herb bags...) get their own tinted section; groups marked
	"own section" pull their items into a section of their own; the bank shows its tabs (or its
	bank slots and bank bags) as sections. Columns, slot size and spacing are settings; the window
	sizes itself to the grid.

	Live slots are the game's own item buttons (UI/ItemButton.lua); saved slots (another
	character, the bank away from a banker) are plain buttons. Searching dims what does not match. ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local OneBag = NBG:Module("OneBag")
local Skin, W, Settings, Common = NBG.Skin, NBG.Widgets, NBG.Settings, NBG.Common
local Containers, Store, Buttons, Search, Groups, Rules = NBG.Containers, NBG.Store, NBG.Buttons, NBG.Search, NBG.Groups, NBG.Rules

local type, pairs, ipairs, max, min, floor, ceil = type, pairs, ipairs, math.max, math.min, math.floor, math.ceil

local View = {}

function OneBag:New(w)
	local v = setmetatable({ window = w, shown = false }, { __index = View })
	local f = CreateFrame("Frame", nil, w.body)
	f:SetAllPoints()
	f:Hide()
	v.frame = f
	-- toolbar
	v.search = W:Search(f, 200, 28, L["Search   ilvl>20  boe  potion"], function(text) v.query = Search:Compile(text) v:Paint() end)
	v.search:SetPoint("TOPLEFT", 14, -8)
	v.tools = {}
	local function Tool(glyph, tip, fn)
		local b = W:IconButton(f, glyph, 24, { onClick = fn, tip = { tip } })
		v.tools[#v.tools + 1] = b
		return b
	end
	v.btnStrip = Tool("bag", L["Show the bag slots"], function() Settings:Set("onebag.bagStrip", not Settings:Get("onebag.bagStrip")) end)
	v.btnKeys = Tool("key", L["Keyring"], function() Settings:Set("onebag.keyring", not Settings:Get("onebag.keyring")) end)
	v.btnChar = Tool("user", L["Whose bags"], function(self) Common:CharMenu(self, w) end)
	v.btnBank = Tool("bank", L["The bank (saved when away from a banker)"], function()
		if w.id == "bank" then w:SetOwner(NBG:PlayerKey()) return end
		local b = NBG.Windows:Open("bank")
		b:SetOwner(w.owner)
	end)
	v.btnSort = Tool("broom", L["Sort"], function() NBG.Sort:Run(w.location) end)
	v.btnStash = Tool("deposit", L["Stash trade goods in the bank"], function() NBG.Stash:Run() end)
	v.strip = Common:BagStrip(f)
	v.ribbon = Common:Ribbon(f)
	v.grid = CreateFrame("Frame", nil, f)
	v.footer = Common:Footer(f)
	v.footer:SetPoint("BOTTOMLEFT") v.footer:SetPoint("BOTTOMRIGHT")
	v.labels = {}
	NBG:Register("BAG_HIGHLIGHT", function(_, id, bag) if id == w.id and v.shown then v.highlight = bag v:Paint() end end)
	NBG:Register("SEARCH_SET", function(_, id, text) if id == w.id and v.shown then v.search:SetText(text) end end)
	return v
end

function View:Show()
	self.shown = true
	self.frame:Show()
	self.window.grip:Hide()
end

function View:Hide()
	self.shown = false
	self.frame:Hide()
	if self.hostPlace then
		Buttons:HideAll(self.hostPlace)
		local h = Buttons:Host(self.hostPlace)
		h:Hide()
	end
end

local function Label(v, i)
	local l = v.labels[i]
	if l then return l end
	l = CreateFrame("Frame", nil, v.grid)
	l:SetHeight(22)
	l.icon = W:Glyph(l, "bag", 12)
	l.icon:SetPoint("LEFT", 2, 0)
	l.text = W:Text(l, 10.5, "header", "caps")
	l.text:SetPoint("LEFT", l.icon, "RIGHT", 6, 0)
	l.count = W:Text(l, 10, "textDim", "medium")
	l.count:SetPoint("LEFT", l.text, "RIGHT", 6, 0)
	l.line = l:CreateTexture(nil, "ARTWORK")
	l.line:SetTexture(NBG.MEDIA .. "FadeR")
	l.line:SetHeight(1)
	l.line:SetPoint("LEFT", l.count, "RIGHT", 10, 0)
	l.line:SetPoint("RIGHT", -2, 0)
	v.labels[i] = l
	return l
end

-- the sections to draw: { label, glyph, role, bags = { info }, slots = { {bag, slot} } }
function View:Sections()
	local w = self.window
	local list = w:BagList()
	local sections = {}
	local main = { label = nil, glyph = "backpack", role = "header", slots = {} }
	local live = w:Live()
	local tabs = w.location == "bank" and Containers:BankMode() == "tabs"
	local function AddBag(sec, info)
		for slot = 1, info.size or 0 do sec.slots[#sec.slots + 1] = { bag = info.id, slot = slot } end
		sec.used = (sec.used or 0)
		sec.total = (sec.total or 0) + (info.size or 0)
	end
	if w.location == "guild" then
		local GB = NBG.GuildBank
		for _, info in ipairs(list) do
			if info.id == GB.tab then
				local sec = { label = (info.name or L["Tab"]):upper(), glyph = "guild", role = "header", slots = {} }
				AddBag(sec, info)
				sections[#sections + 1] = sec
			end
		end
		return sections
	end
	if w.location == "bank" then
		for _, info in ipairs(list) do
			if (info.size or 0) > 0 then
				if tabs or info.kind == "tab" then
					local sec = { label = (info.name or L["Tab"]):upper(), glyph = "bank", role = "header", slots = {} }
					AddBag(sec, info)
					sections[#sections + 1] = sec
				elseif info.id == Containers.BANK then
					local sec = { label = L["Bank"]:upper(), glyph = "bank", role = "header", slots = {} }
					AddBag(sec, info)
					sections[#sections + 1] = sec
				elseif info.special and Settings:Get("onebag.specialSections") then
					local sec = { label = info.special.label:upper(), glyph = info.special.glyph, role = "special", special = true, slots = {} }
					AddBag(sec, info)
					sections[#sections + 1] = sec
				else
					if not self._bankBags then end
					local sec
					for _, s in ipairs(sections) do if s.key == "bankbags" then sec = s end end
					if not sec then sec = { key = "bankbags", label = L["Bank bags"]:upper(), glyph = "bag", role = "header", slots = {} } sections[#sections + 1] = sec end
					AddBag(sec, info)
				end
			end
		end
	else
		sections[1] = main
		for _, info in ipairs(list) do
			if (info.size or 0) > 0 then
				if info.kind == "keyring" or (info.special and info.special.id == "keys") then
					if Settings:Get("onebag.keyring") then
						local sec = { label = L["Keyring"]:upper(), glyph = "key", role = "special", special = true, slots = {} }
						AddBag(sec, info)
						sections[#sections + 1] = sec
					end
				elseif info.special and Settings:Get("onebag.specialSections") then
					local sec = { label = info.special.label:upper(), glyph = info.special.glyph, role = "special", special = true, slots = {} }
					AddBag(sec, info)
					sections[#sections + 1] = sec
				else
					AddBag(main, info)
				end
			end
		end
		if #main.slots == 0 then table.remove(sections, 1) end
	end
	return sections
end

-- items per slot, from the game or the store
function View:SlotEntry(bag, slot)
	local w = self.window
	if w.location == "guild" then return NBG.GuildBank:Slot(bag, slot) end
	if w:Live() then return Containers:Entry(bag, slot) end
	self.saved = self.saved or {}
	local key = bag
	if not self.saved[key] then self.saved[key] = Store:BagSlots(w.owner, w.location, bag) end
	return self.saved[key][slot]
end

function View:Refresh(light)
	local w = self.window
	local f = self.frame
	self.saved = nil
	local live = w:Live()
	local place = w.location == "bank" and "bank" or "bags"
	if w.location ~= "bags" and w.location ~= "bank" and w.location ~= "guild" then w.location = w.id end
	local guild = w.location == "guild"
	if guild then live = false end
	-- toolbar
	local cols = Settings:Get("onebag.columns")
	local size = Settings:Get("onebag.slot")
	local gap = Settings:Get("onebag.spacing")
	local gw = cols * (size + gap) - gap
	local width = max(gw + 28, 360)
	local tools = guild and {} or { self.btnStrip }
	self.btnStrip:SetShown(not guild)
	self.btnChar:SetShown(not guild)
	self.btnKeys:SetShown(w.location == "bags" and _G.HasKey ~= nil and (NBG.Call(_G.HasKey) and true or false))
	if self.btnKeys:IsShown() then tools[#tools + 1] = self.btnKeys self.btnKeys:SetActive(Settings:Get("onebag.keyring")) end
	if not guild then tools[#tools + 1] = self.btnChar end
	self.btnBank:SetShown(w.id == "bags")
	if w.id == "bags" then tools[#tools + 1] = self.btnBank end
	self.btnSort:SetShown(live)
	if live then tools[#tools + 1] = self.btnSort end
	self.btnStash:SetShown(live and w.location == "bank" and Settings:Get("stash.tradeGoods"))
	if self.btnStash:IsShown() then tools[#tools + 1] = self.btnStash end
	self.btnStrip:SetActive(Settings:Get("onebag.bagStrip"))
	local x = width - 14
	for i = #tools, 1, -1 do
		local b = tools[i]
		b:ClearAllPoints() b:SetPoint("TOPRIGHT", f, "TOPLEFT", x, -10)
		x = x - 28
	end
	self.search:SetWidth(x - 14 - 6)
	local y = -44
	-- guild tabs / bag strip
	if guild then
		self.strip:Hide()
		self.guildBar = self.guildBar or NBG.GuildUI:TabBar(f, self)
		self.guildBar:ClearAllPoints() self.guildBar:SetPoint("TOPLEFT", 14, y) self.guildBar:SetPoint("RIGHT", -14, 0)
		self.guildBar:Show()
		self.guildBar:Update(w)
		y = y - 30
	elseif self.guildBar then
		self.guildBar:Hide()
	end
	if guild then
	elseif Settings:Get("onebag.bagStrip") then
		self.strip:ClearAllPoints() self.strip:SetPoint("TOPLEFT", 14, y) self.strip:SetPoint("RIGHT", -14, 0)
		self.strip:Show()
		self.strip:Update(w)
		y = y - 40
	else
		self.strip:Hide()
	end
	if self.ribbon:Update(w) then
		self.ribbon:ClearAllPoints() self.ribbon:SetPoint("TOPLEFT", 14, y) self.ribbon:SetPoint("RIGHT", -14, 0)
		y = y - 30
	end
	-- the grid
	self.grid:ClearAllPoints()
	self.grid:SetPoint("TOPLEFT", 14, y) self.grid:SetPoint("RIGHT", -14, 0)
	local sections = self:Sections()
	-- groups with "own section": their items are pulled out of the main section
	local groupSecs = {}
	if Settings:Get("onebag.groupSections") then
		for _, g in ipairs(Groups:List()) do
			if g.custom and g.def.section then groupSecs[#groupSecs + 1] = { id = g.id, label = g.label:upper(), glyph = g.glyph, color = g.def.color, items = {} } end
		end
	end
	-- the host for live buttons
	if live then
		self.hostPlace = place
		local host = Buttons:Host(place)
		host:SetParent(self.grid)
		host:ClearAllPoints()
		host:SetAllPoints(self.grid)
		host:SetFrameLevel(self.grid:GetFrameLevel() + 2)
		host:Show()
		Buttons:Prepare(place)
	elseif self.hostPlace then
		Buttons:HideAll(self.hostPlace)
		Buttons:Host(self.hostPlace):Hide()
		self.hostPlace = nil
	end
	local shown = {}
	local gy = 0
	local labelN = 0
	local offN = 0
	local function Place(entry, bag, slot, special, sx, sy)
		local b
		if live then
			b = Buttons:Live(bag, slot)
		else
			offN = offN + 1
			b = Buttons:Offline("onebag_" .. w.id, offN, self.grid)
			b.nbOnClick = nil
			if guild then NBG.GuildBank:BindRow(b, { tab = bag, slot = slot }) end
		end
		if not b then return end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", self.grid, "TOPLEFT", sx, sy)
		b:NBGrid(size)
		b.nbSpecial = special
		b.nbCell = { bag = bag, slot = slot }
		b:Show()
		shown[b] = true
		self.cells[#self.cells + 1] = b
	end
	self.cells = {}
	local pulled = {}
	if #groupSecs > 0 then
		for _, sec in ipairs(sections) do
			if not sec.special then
				for _, c in ipairs(sec.slots) do
					local e = self:SlotEntry(c.bag, c.slot)
					if e then
						local gid = Groups:Classify(e)
						for _, gs in ipairs(groupSecs) do
							if gs.id == gid then gs.items[#gs.items + 1] = c pulled[c.bag .. ":" .. c.slot] = true end
						end
					end
				end
			end
		end
	end
	local function DrawSection(sec, slots, label, glyph, role, color)
		if label then
			labelN = labelN + 1
			local l = Label(self, labelN)
			l:ClearAllPoints()
			l:SetPoint("TOPLEFT", self.grid, "TOPLEFT", 0, gy - 2)
			l:SetPoint("RIGHT", self.grid, "RIGHT")
			W:SetGlyph(l.icon, glyph or "bag")
			if color then Skin:Unpaint(l.icon) Skin:Unpaint(l.text) l.icon:SetVertexColor(color[1], color[2], color[3]) l.text:SetTextColor(color[1], color[2], color[3])
			else Skin:Paint(l.icon, role or "header") Skin:Paint(l.text, role or "header") end
			l.text:SetText(label)
			local used = 0
			for _, c in ipairs(slots) do if self:SlotEntry(c.bag, c.slot) then used = used + 1 end end
			l.count:SetText(sec and (used .. " / " .. #slots) or tostring(#slots))
			Skin:Paint(l.line, color and "accent" or (role or "header"), { alpha = 0.6 })
			l:Show()
			gy = gy - 24
		end
		local i = 0
		for _, c in ipairs(slots) do
			if not pulled[c.bag .. ":" .. c.slot] or not sec then
				local r, col = floor(i / cols), i % cols
				if Settings:Get("onebag.reverse") then col = cols - 1 - col end
				Place(nil, c.bag, c.slot, sec and sec.special, col * (size + gap), gy - r * (size + gap))
				i = i + 1
			end
		end
		if i > 0 then gy = gy - (ceil(i / cols)) * (size + gap) - 4 end
	end
	for idx, sec in ipairs(sections) do
		local label = sec.label
		if idx == 1 and w.location == "bags" and not sec.special then label = nil end
		DrawSection(sec, sec.slots, label, sec.glyph, sec.role)
	end
	for _, gs in ipairs(groupSecs) do
		if #gs.items > 0 then DrawSection(nil, gs.items, gs.label, gs.glyph, "header", gs.color) end
	end
	for i = labelN + 1, #self.labels do self.labels[i]:Hide() end
	-- hide what is not used
	if live then Buttons:HideAll(place, shown) end
	for i = offN + 1, (self.offMax or 0) do Buttons:Offline("onebag_" .. w.id, i, self.grid):Hide() end
	self.offMax = max(self.offMax or 0, offN)
	local gridH = -gy
	self.grid:SetHeight(max(1, gridH))
	self:Paint()
	self.footer:Update(w, w:Entries())
	-- the window fits the grid
	local h = -y + gridH + 8 + 46 + 42
	if not NBG:InCombat() or not w:IsProtected() then
		w:SetSize(width, h)
	end
end

-- paint every cell (entries, search, highlight); cheap enough for every change
function View:Paint()
	if not self.cells then return end
	local q = self.query
	for _, b in ipairs(self.cells) do
		local c = b.nbCell
		local e = self:SlotEntry(c.bag, c.slot)
		local dim = false
		if q and (not e or not Search:Match(e, q)) then dim = true end
		if self.highlight and c.bag ~= self.highlight then dim = true end
		local tint = (self.window.location == "bags" and Settings:Get("onebag.bagColors") and NBG.BagRules) and NBG.BagRules:Color(c.bag) or nil
		b:NBPaint(e, { dim = dim, special = b.nbSpecial, tint = tint })
		if b.nbLive then b:NBCooldown() end
	end
end
