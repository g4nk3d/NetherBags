--[[ NetherBags - UI/ConfigPages.lua
	The settings pages that are more than switches: Groups (order and the group editor), Junk &
	selling (the items marked junk, kept or locked), Search (what the search box understands),
	Profiles (profiles, export, import) and Plugins. ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Config = NBG.Config
local Skin, W, Settings = NBG.Skin, NBG.Widgets, NBG.Settings
local Groups, Rules, Marks, Items, Profiles, Store, Containers = NBG.Groups, NBG.Rules, NBG.Marks, NBG.Items, NBG.Profiles, NBG.Store, NBG.Containers

local type, pairs, ipairs, max, min, floor, tostring = type, pairs, ipairs, math.max, math.min, math.floor, tostring

local function Panel(parent, w, h, title)
	local p = CreateFrame("Frame", nil, parent)
	p:SetSize(w, h)
	Skin:Panel(p)
	if title then
		p.title = W:Text(p, 10, "accent", "bold")
		p.title:SetPoint("TOPLEFT", 14, -12)
		p.title:SetText(title)
	end
	return p
end

---------------------------------------------------------------------------------------------
-- Groups
---------------------------------------------------------------------------------------------
local ICONS = { "star", "coins", "gem", "sword", "chest", "ring", "potion", "trade", "leaf", "ore", "scroll", "quest", "bag", "arrow", "key", "rune",
	"hearth", "fish", "bread", "shield", "helm", "boots", "cloak", "lock", "new", "up", "eye", "link", "set", "junk", "globe", "guild" }
local COLOURS = { { 0.91, 0.77, 0.47 }, { 0.43, 0.82, 0.96 }, { 0.35, 0.86, 0.43 }, { 0.71, 0.36, 0.98 }, { 1, 0.53, 0.08 }, { 0.92, 0.35, 0.31 },
	{ 0.94, 0.55, 0.98 }, { 0.8, 0.8, 0.85 } }

function Config:PageGroups(page, y0)
	local c = page.content
	local listW = 250
	local list = Panel(c, listW, 470, L["ORDER"])
	list:SetPoint("TOPLEFT", 0, -y0)
	list.rows = {}
	local ed = Panel(c, 410, 470, L["EDIT GROUP"])
	ed:SetPoint("TOPLEFT", listW + 14, -y0)
	page.selected = nil
	local newBtn = W:Button(list, L["New group"], listW - 28, 26, { style = "gold", glyph = "plus", onClick = function()
		page.selected = Groups:NewCustom()
		page:Refresh()
	end })
	newBtn:SetPoint("BOTTOM", 0, 12)
	-- the editor's parts
	local name = W:Edit(ed, 180, 24, L["Name"], { maxLetters = 40, onChange = function(t, user)
		if not user or not page.def then return end
		page.def.name = t
		NBG:Debounce("groupName", 0.3, function() Groups:SaveCustom(page.selected, page.def) page:RefreshList() end)
	end })
	name:SetPoint("TOPLEFT", 70, -36)
	local nameL = W:Text(ed, 11, "textDim") nameL:SetPoint("RIGHT", name, "LEFT", -10, 0) nameL:SetText(L["Name"])
	local icon = W:IconButton(ed, "star", 26, { tip = { L["Icon"] }, onClick = function(self)
		local items = {}
		for _, g in ipairs(ICONS) do items[#items + 1] = { text = g, glyph = g, checked = page.def and page.def.icon == g, onClick = function()
			page.def.icon = g Groups:SaveCustom(page.selected, page.def) page:Refresh() end } end
		W:Menu(self, items)
	end })
	icon:SetPoint("LEFT", name, "RIGHT", 14, 0)
	local swatch = CreateFrame("Button", nil, ed)
	swatch:SetSize(22, 20)
	swatch:SetPoint("LEFT", icon, "RIGHT", 12, 0)
	swatch.t = swatch:CreateTexture(nil, "ARTWORK")
	swatch.t:SetAllPoints()
	Skin:Rounded(swatch.t)
	swatch:SetScript("OnClick", function()
		if not page.def then return end
		local cur = page.def.color or COLOURS[1]
		local idx = 1
		for i, col in ipairs(COLOURS) do if math.abs(col[1] - cur[1]) < 0.02 and math.abs(col[2] - cur[2]) < 0.02 then idx = i end end
		page.def.color = COLOURS[idx % #COLOURS + 1]
		Groups:SaveCustom(page.selected, page.def)
		page:Refresh()
	end)
	W:Tip(swatch, L["Colour (click for the next one)"])
	local whenL = W:Text(ed, 11.5, "text") whenL:SetPoint("TOPLEFT", 14, -76) whenL:SetText(L["Put an item here when"])
	local match = W:Dropdown(ed, 70, function() return { { value = "all", label = L["ALL"] }, { value = "any", label = L["ANY"] } } end,
		function() return page.def and page.def.match or "all" end, function(v) page.def.match = v Groups:SaveCustom(page.selected, page.def) page:Refresh() end)
	match:SetPoint("LEFT", whenL, "RIGHT", 8, 0)
	local whenR = W:Text(ed, 11.5, "text") whenR:SetPoint("LEFT", match, "RIGHT", 8, 0) whenR:SetText(L["of these are true:"])
	ed.rules = {}
	local addRule = W:Button(ed, L["Add rule"], 100, 22, { glyph = "plus", size = 10.5, onClick = function()
		if not page.def then return end
		if #page.def.rules >= 12 then return end
		page.def.rules[#page.def.rules + 1] = Rules:Default("name")
		Groups:SaveCustom(page.selected, page.def)
		page:Refresh()
	end })
	local opts = {}
	opts.section = W:Check(ed, L["Show as its own section in One bag"], function() return page.def and page.def.section end, function(v) page.def.section = v Groups:SaveCustom(page.selected, page.def) end)
	opts.collapsed = W:Check(ed, L["Start collapsed"], function() return page.def and page.def.collapsed end, function(v) page.def.collapsed = v Groups:SaveCustom(page.selected, page.def) end)
	opts.sell = W:Check(ed, L["Sell items in this group at vendors"], function() return page.def and page.def.sell end, function(v) page.def.sell = v Groups:SaveCustom(page.selected, page.def) end,
		L["Off for safety. Locked items are never sold."])
	local preview = CreateFrame("Frame", nil, ed)
	preview:SetSize(380, 70)
	Skin:Panel(preview, { inset = true })
	preview.text = W:Text(preview, 11.5, "positive", "medium")
	preview.text:SetPoint("TOPLEFT", 12, -10)
	preview.where = W:Text(preview, 10, "textDim")
	preview.where:SetPoint("TOPRIGHT", -12, -10)
	preview.slots = {}
	local del = W:Button(ed, L["Delete group"], 110, 22, { style = "red", size = 10.5, onClick = function()
		if not page.selected then return end
		local id = page.selected
		W:Popup({ title = L["Delete group"], text = L["Delete this group? Its items go back to the other groups."], buttons = {
			{ label = L["Delete"], style = "red", onClick = function() Groups:DeleteCustom(id) page.selected = nil page:Refresh() end }, { label = L["Cancel"] } } })
	end })
	del:SetPoint("BOTTOMRIGHT", -12, 12)
	local builtinText = W:Text(ed, 11.5, "textDim")
	builtinText:SetPoint("TOPLEFT", 14, -40)
	builtinText:SetWidth(380)
	builtinText:SetJustifyH("LEFT")
	builtinText:SetWordWrap(true)
	local builtinOn = W:Check(ed, L["Use this group"], function() return page.selected and not Settings:Profile().groups.off[page.selected] end,
		function(v) Groups:SetOff(page.selected, not v) page:RefreshList() end)
	builtinOn:SetPoint("TOPLEFT", 14, -100)
	local customParts = { name, nameL, icon, swatch, whenL, match, whenR, addRule, opts.section, opts.collapsed, opts.sell, preview, del }

	local function RuleRow(i)
		local r = ed.rules[i]
		if r then return r end
		r = CreateFrame("Frame", nil, ed)
		r:SetSize(390, 26)
		r.prop = W:Dropdown(r, 128, function()
			local out = {}
			for _, id in ipairs(Rules.ORDER) do out[#out + 1] = { value = id, label = Rules.PROPS[id].label } end
			return out
		end, function() return r.rule and r.rule.p end, function(v)
			page.def.rules[r.index] = Rules:Default(v)
			Groups:SaveCustom(page.selected, page.def) page:Refresh()
		end)
		r.prop:SetPoint("LEFT", 0, 0)
		r.op = W:Dropdown(r, 92, function()
			local def = r.rule and Rules.PROPS[r.rule.p]
			local out = {}
			for _, o in ipairs(def and Rules.OPS[def.kind] or {}) do out[#out + 1] = { value = o.id, label = o.label } end
			return out
		end, function() return r.rule and r.rule.o end, function(v) page.def.rules[r.index].o = v Groups:SaveCustom(page.selected, page.def) page:Refresh() end)
		r.op:SetPoint("LEFT", r.prop, "RIGHT", 6, 0)
		r.valChoice = W:Dropdown(r, 128, function()
			local def = r.rule and Rules.PROPS[r.rule.p]
			if def and def.kind == "bool" then return { { value = true, label = L["Yes"] }, { value = false, label = L["No"] } } end
			return def and def.choices and def.choices() or {}
		end, function() return r.rule and r.rule.v end, function(v) page.def.rules[r.index].v = v Groups:SaveCustom(page.selected, page.def) page:Refresh() end)
		r.valChoice:SetPoint("LEFT", r.op, "RIGHT", 6, 0)
		r.valEdit = W:Edit(r, 128, 24, "", { onChange = function(t, user)
			if not user or not r.rule then return end
			local def = Rules.PROPS[r.rule.p]
			local v = t
			if def.kind ~= "text" and def.kind ~= "query" then
				if def.kind == "money" then
					local g, sv, cc = t:match("(%d*)g"), t:match("(%d*)s"), t:match("(%d*)c")
					if g or sv or cc then v = (tonumber(g) or 0) * 10000 + (tonumber(sv) or 0) * 100 + (tonumber(cc) or 0) else v = tonumber(t) end
				else v = tonumber(t) end
				if not v then return end
			end
			page.def.rules[r.index].v = v
			NBG:Debounce("ruleEdit", 0.35, function() Groups:SaveCustom(page.selected, page.def) page:UpdatePreview() end)
		end })
		r.valEdit:SetPoint("LEFT", r.op, "RIGHT", 6, 0)
		r.del = W:IconButton(r, "trash", 22, { role = "negative", tip = { L["Remove this rule"] }, onClick = function()
			table.remove(page.def.rules, r.index)
			Groups:SaveCustom(page.selected, page.def) page:Refresh()
		end })
		r.del:SetPoint("LEFT", r.valEdit, "RIGHT", 6, 0)
		ed.rules[i] = r
		return r
	end

	function page:RefreshList()
		local all = Groups:Order()
		local g = Settings:Profile().groups
		for _, r in ipairs(list.rows) do r:Hide() end
		for i, id in ipairs(all) do
			local r = list.rows[i]
			if not r then
				r = CreateFrame("Button", nil, list)
				r:SetHeight(28)
				r.hl = r:CreateTexture(nil, "BACKGROUND") r.hl:SetAllPoints() r.hl:SetTexture(NBG.MEDIA .. "FadeR")
				r.icon = W:Glyph(r, "star", 13)
				r.icon:SetPoint("LEFT", 10, 0)
				r.text = W:Text(r, 11.5, "text", "medium")
				r.text:SetPoint("LEFT", 30, 0)
				r.text:SetWidth(130) r.text:SetJustifyH("LEFT")
				r.kind = W:Text(r, 9, "faint")
				r.kind:SetPoint("RIGHT", -50, 0)
				r.up = W:IconButton(r, "chev_r", 18, { onClick = function() Groups:Move(r.id, -1) page:RefreshList() end, tip = { L["Move up"] } })
				r.up.icon:SetRotation(math.pi / 2)
				r.up:SetPoint("RIGHT", -24, 0)
				r.down = W:IconButton(r, "chev_r", 18, { onClick = function() Groups:Move(r.id, 1) page:RefreshList() end, tip = { L["Move down"] } })
				r.down.icon:SetRotation(-math.pi / 2)
				r.down:SetPoint("RIGHT", -4, 0)
				r:SetScript("OnClick", function() page.selected = r.id page:Refresh() end)
				list.rows[i] = r
			end
			local grp = Groups:Get(id)
			r.id = id
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", 4, -30 - (i - 1) * 28) r:SetPoint("TOPRIGHT", -4, -30 - (i - 1) * 28)
			W:SetGlyph(r.icon, grp.glyph or "star")
			if grp.color then Skin:Unpaint(r.icon) r.icon:SetVertexColor(grp.color[1], grp.color[2], grp.color[3]) else Skin:Paint(r.icon, "textDim") end
			r.text:SetText(grp.label)
			local off = g.off[id]
			Skin:Paint(r.text, page.selected == id and "header" or (off and "faint" or "text"))
			r.kind:SetText(grp.custom and L["yours"] or (id == "junk" and L["always last"] or (off and L["off"] or L["built-in"])))
			Skin:Paint(r.kind, grp.custom and "accent" or "faint")
			r.hl:SetShown(page.selected == id)
			Skin:Paint(r.hl, "rowSel")
			r.up:SetShown(id ~= "junk") r.down:SetShown(id ~= "junk")
			r:Show()
		end
		list:SetHeight(max(470, 30 + #all * 28 + 50))
	end

	function page:UpdatePreview()
		if not page.def then preview:Hide() return end
		preview:Show()
		local n, inBags, inBank = 0, 0, 0
		local shown = 0
		local entries = Containers:All("bags")
		for _, e in ipairs(Store:Entries(NBG:PlayerKey(), "bank")) do entries[#entries + 1] = e end
		for _, e in ipairs(entries) do
			if Rules:Match(e, page.def.rules, page.def.match) then
				n = n + 1
				if e.place == "bank" then inBank = inBank + 1 else inBags = inBags + 1 end
				shown = shown + 1
				if shown <= 8 then
					local b = preview.slots[shown]
					if not b then b = NBG.Buttons:Offline("cfgPreview", shown, preview) preview.slots[shown] = b end
					b:ClearAllPoints() b:SetPoint("TOPLEFT", 12 + (shown - 1) * 42, -30)
					b:NBGrid(36)
					b:NBPaint(e)
					b:Show()
				end
			end
		end
		for i = shown + 1, #preview.slots do preview.slots[i]:Hide() end
		preview.text:SetText(n == 1 and L["Matches 1 item right now"] or (L["Matches %d items right now"]):format(n))
		Skin:Paint(preview.text, n > 0 and "positive" or "textDim")
		preview.where:SetText((L["bags %d  ·  bank %d"]):format(inBags, inBank))
	end

	function page:Refresh(arg)
		if arg then page.selected = arg end
		local g = Settings:Profile().groups
		if page.selected and not (g.custom[page.selected] or Groups.BUILT[page.selected]) then page.selected = nil end
		if not page.selected then
			for _, id in ipairs(Groups:Order()) do if g.custom[id] then page.selected = id break end end
			page.selected = page.selected or "new"
		end
		page:RefreshList()
		local custom = g.custom[page.selected]
		page.def = custom and NBG.Copy(custom) or nil
		for _, p in ipairs(customParts) do p:SetShown(custom ~= nil) end
		builtinText:SetShown(not custom) builtinOn:SetShown(not custom and page.selected ~= "junk" and page.selected ~= "misc")
		for _, r in ipairs(ed.rules) do r:Hide() end
		if not custom then
			local grp = Groups:Get(page.selected)
			builtinText:SetText((grp and grp.label or "") .. "\n\n|cff8c96b0" .. L["A built-in group: it takes items by what they are. Move it up or down to change which group wins, or switch it off."] .. "|r")
			builtinOn:Refresh()
			return
		end
		name:SetText(custom.name)
		icon:SetGlyph(custom.icon or "star")
		local col = custom.color or COLOURS[1]
		swatch.t:SetVertexColor(col[1], col[2], col[3])
		match:Refresh()
		local y = 108
		for i, rule in ipairs(page.def.rules) do
			local r = RuleRow(i)
			r.index, r.rule = i, rule
			r:ClearAllPoints() r:SetPoint("TOPLEFT", 14, -y)
			r.prop:Refresh() r.op:Refresh()
			local def = Rules.PROPS[rule.p]
			local isEdit = def and (def.kind == "text" or def.kind == "query" or def.kind == "number" or def.kind == "money")
			r.valEdit:SetShown(isEdit) r.valChoice:SetShown(not isEdit)
			if isEdit then
				local v = rule.v
				if def.kind == "money" and type(v) == "number" then v = (floor(v / 10000) > 0 and (floor(v / 10000) .. "g") or "") .. ((floor(v / 100) % 100 > 0) and (floor(v / 100) % 100 .. "s") or "") .. ((v % 100 > 0 or v == 0) and (v % 100 .. "c") or "") end
				r.valEdit:SetText(tostring(v or ""))
			else
				r.valChoice:Refresh()
			end
			r.del:ClearAllPoints() r.del:SetPoint("LEFT", isEdit and r.valEdit or r.valChoice, "RIGHT", 6, 0)
			r:Show()
			y = y + 30
		end
		addRule:ClearAllPoints() addRule:SetPoint("TOPLEFT", 14, -y - 4)
		y = y + 36
		opts.section:ClearAllPoints() opts.section:SetPoint("TOPLEFT", 14, -y)
		opts.collapsed:ClearAllPoints() opts.collapsed:SetPoint("TOPLEFT", 14, -y - 24)
		opts.sell:ClearAllPoints() opts.sell:SetPoint("TOPLEFT", 14, -y - 48)
		for _, o in pairs(opts) do o:Refresh() end
		preview:ClearAllPoints() preview:SetPoint("TOPLEFT", 14, -y - 92)
		ed:SetHeight(max(470, y + 92 + 70 + 50))
		page:UpdatePreview()
		page:SetContentHeight(y0 + max(ed:GetHeight(), list:GetHeight()) + 20)
	end
	page.customY = y0 + 480
end

---------------------------------------------------------------------------------------------
-- Junk & selling: the marked items
---------------------------------------------------------------------------------------------
function Config:PageJunk(page, y0)
	local c = page.content
	local box = Panel(c, 640, 260, L["YOUR MARKS"])
	box:SetPoint("TOPLEFT", 0, -y0 - 10)
	box.rows = {}
	local hint = W:Text(box, 10, "faint")
	hint:SetPoint("TOPRIGHT", -14, -12)
	hint:SetText(L["Alt+Right-click an item in the bags to mark it"])
	function page:Refresh()
		local p = Settings:Profile()
		local list = {}
		for id in pairs(p.locks) do list[#list + 1] = { id = id, kind = "lock" } end
		for id in pairs(p.junk) do list[#list + 1] = { id = id, kind = "junk" } end
		for id in pairs(p.keep) do list[#list + 1] = { id = id, kind = "keep" } end
		table.sort(list, function(a, b) if a.kind ~= b.kind then return a.kind < b.kind end return a.id < b.id end)
		for _, r in ipairs(box.rows) do r:Hide() end
		for i, it in ipairs(list) do
			if i > 40 then break end
			local r = box.rows[i]
			if not r then
				r = CreateFrame("Frame", nil, box)
				r:SetSize(600, 24)
				r.glyph = W:Glyph(r, "lock", 13)
				r.glyph:SetPoint("LEFT", 0, 0)
				r.text = W:Text(r, 11.5, "text")
				r.text:SetPoint("LEFT", 22, 0)
				r.kind = W:Text(r, 10, "textDim")
				r.kind:SetPoint("LEFT", 330, 0)
				r.del = W:IconButton(r, "x", 20, { tip = { L["Remove the mark"] } })
				r.del:SetPoint("RIGHT", 0, 0)
				box.rows[i] = r
			end
			r:ClearAllPoints() r:SetPoint("TOPLEFT", 14, -34 - (i - 1) * 26)
			local info = Items:Info("item:" .. it.id)
			r.text:SetText(info and info.name or ("item " .. it.id))
			if info then local qr, qg, qb = Items:QualityColor(info.quality) Skin:Unpaint(r.text) r.text:SetTextColor(qr, qg, qb) end
			W:SetGlyph(r.glyph, it.kind == "lock" and "lock" or it.kind == "junk" and "junk" or "check")
			Skin:Paint(r.glyph, it.kind == "lock" and "header" or "textDim")
			r.kind:SetText(it.kind == "lock" and L["locked: never sold, stashed or sorted"] or it.kind == "junk" and L["marked as junk"] or L["kept: not junk"])
			r.del:SetScript("OnClick", function()
				if it.kind == "lock" then Marks:SetLocked(it.id, false) else Marks:ClearJunk(it.id) end
				page:Refresh()
			end)
			r:Show()
		end
		if #list == 0 then
			box.empty = box.empty or W:Text(box, 11, "textDim")
			box.empty:SetPoint("TOPLEFT", 14, -40)
			box.empty:SetText(L["No marked items yet."])
			box.empty:Show()
		elseif box.empty then box.empty:Hide() end
		box:SetHeight(max(120, 50 + min(#list, 40) * 26))
		page:SetContentHeight(y0 + 30 + box:GetHeight())
	end
	page.customY = y0 + 280
end

---------------------------------------------------------------------------------------------
-- Search help
---------------------------------------------------------------------------------------------
function Config:PageSearchHelp(page, y0)
	local c = page.content
	local box = Panel(c, 640, 470, L["WHAT TO TYPE"])
	box:SetPoint("TOPLEFT", 0, -y0 - 10)
	local lines = {
		{ "silk", L["names, kinds and slots that contain the word"] },
		{ "\"linen cloth\"", L["a phrase"] },
		{ "-potion   !potion   not potion", L["NOT: everything without it"] },
		{ "potion or elixir   potion | elixir", L["OR: either one"] },
		{ "(potion or elixir) -minor", L["brackets group the parts"] },
		{ "tt:\"chance on hit\"   tt:use:", L["the item's tooltip contains the text"] },
		{ "ilvl>20   ilvl<=30   reqlvl>=40", L["item level, required level"] },
		{ "value>1g   count>=5", L["vendor value of the stack (g, s, c), stack size"] },
		{ "q:rare   q>=3   epic", L["quality, by name or number"] },
		{ "boe   bop   bou   soulbound", L["binding"] },
		{ "upgrade new junk locked quest unseen set", L["the markers"] },
		{ "usable unusable recent needed outgrown tracked", L["can use, looted this session, a quest needs it..."] },
		{ "bag:2   tab:3   id:2589", L["a bag or bank tab, an item ID"] },
		{ "type:armor   slot:head", L["kinds and slots"] },
	}
	for i, l in ipairs(lines) do
		local a = W:Text(box, 11.5, "header", "medium")
		a:SetPoint("TOPLEFT", 14, -36 - (i - 1) * 28)
		a:SetText(l[1])
		local b = W:Text(box, 11, "textDim")
		b:SetPoint("TOPLEFT", 280, -36 - (i - 1) * 28)
		b:SetText(l[2])
	end
	local tip = W:Text(box, 10, "faint")
	tip:SetPoint("BOTTOMLEFT", 14, 12)
	tip:SetText(L["Save any search as a group of your own: the filter button next to the search box."])
	page.customY = y0 + 490
end

---------------------------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------------------------
function Config:PageProfiles(page, y0)
	local c = page.content
	local pw = 650
	-- this character
	local me = Panel(c, pw, 104, L["THIS CHARACTER"])
	me:SetPoint("TOPLEFT", 0, -y0)
	local who = W:Text(me, 11.5, "text") who:SetPoint("TOPLEFT", 14, -42)
	local function Names() local out = {} for _, p in ipairs(Profiles:List()) do out[#out + 1] = { value = p.name, label = p.name } end return out end
	local cur = W:Dropdown(me, 190, Names, function() return Settings:CurrentName() end, function(v) Profiles:Use(v) end)
	cur:SetPoint("TOPLEFT", 180, -36)
	local newL = W:Text(me, 11.5, "text") newL:SetPoint("TOPLEFT", 390, -42) newL:SetText(L["New characters use"])
	local newC = W:Dropdown(me, 110, Names, function() return Settings.db.global.newChars end, function(v) Profiles:SetNewCharProfile(v) end)
	newC:SetPoint("TOPLEFT", 526, -36)
	local one = W:Check(me, L["One profile for every character on this account"], function() return Settings.db.global.useOne end,
		function(v) Profiles:SetOneForAccount(v) end, L["When on, a change on any character changes all of them."])
	one:SetPoint("TOPLEFT", 14, -66)
	one:SetWidth(600)
	-- saved profiles
	local list = Panel(c, pw, 200, L["SAVED PROFILES  (shared by your whole account)"])
	list:SetPoint("TOPLEFT", 0, -y0 - 116)
	list.rows = {}
	local function Ask(title, text, initial, fn)
		W:Popup({ title = title, text = text, edit = { text = initial or "", height = 26 }, width = 380, buttons = {
			{ label = L["OK"], style = "gold", onClick = function(t)
				local ok, why = fn(t)
				if not ok then NBG:Print(tostring(why)) return true end
			end }, { label = L["Cancel"] } } })
	end
	local bNew = W:Button(list, L["New profile"], 112, 24, { glyph = "plus", size = 10.5, onClick = function() Ask(L["New profile"], L["Name of the new profile (it starts with the default settings):"], "", function(t) return Profiles:New(t) end) end })
	local bCopy = W:Button(list, L["Copy current"], 124, 24, { glyph = "copy", size = 10.5, onClick = function()
		local from = Settings:CurrentName()
		Ask(L["Copy profile"], L["Name of the copy:"], from .. " " .. L["copy"], function(t) return Profiles:Copy(from, t) end)
	end })
	local bReset = W:Button(list, L["Reset to defaults"], 136, 24, { style = "red", size = 10.5, onClick = function()
		W:Popup({ title = L["Reset profile"], text = (L["Reset \"%s\" to the default settings? Its groups, layout and marks are cleared too."]):format(Settings:CurrentName()), buttons = {
			{ label = L["Reset"], style = "red", onClick = function() Profiles:Reset() end }, { label = L["Cancel"] } } })
	end })
	-- share
	local share = Panel(c, pw, 236, L["SHARE WITH OTHER PLAYERS"])
	local inc = { groups = true, layout = true, items = false }
	local cg = W:Check(share, L["Custom groups"], function() return inc.groups end, function(v) inc.groups = v end)
	local cl = W:Check(share, L["Window positions"], function() return inc.layout end, function(v) inc.layout = v end)
	local ci = W:Check(share, L["Locked and junk items"], function() return inc.items end, function(v) inc.items = v end)
	local box = W:Edit(share, pw - 28, 86, L["Press Export, or paste a profile string here and press Import."], { multiline = true, size = 10.5 })
	local status = W:Text(share, 10, "textDim")
	status:SetWordWrap(true) status:SetJustifyH("LEFT") status:SetWidth(pw - 28)
	local bExp = W:Button(share, L["Export"], 110, 26, { style = "gold", glyph = "export", onClick = function()
		local s, why = Profiles:Export(Settings:CurrentName(), inc)
		if not s then status:SetText(tostring(why)) return end
		box:SetText(s)
		box.edit:SetFocus() box.edit:HighlightText()
		status:SetText(("|cff5adc6e" .. L["Exported \"%s\". Press Ctrl+C to copy it."] .. "|r"):format(Settings:CurrentName()))
	end })
	local bImp = W:Button(share, L["Import"], 110, 26, { glyph = "deposit", onClick = function()
		local text = box:GetText()
		local info, why = Profiles:Preview(text)
		if not info then status:SetText("|cffeb5a50" .. tostring(why) .. "|r") return end
		W:Popup({ title = L["Import profile"], width = 420,
			text = (L["\"%s\" by %s (NetherBags %s): %d settings, %d custom groups, %d locked items%s.\n\nIt is added as a NEW profile; nothing you have is changed. Use it now?"]):format(
				info.name, info.by, info.version, info.settings, info.groups, info.locks, info.layout and (", " .. L["window layout"]) or ""),
			buttons = {
				{ label = L["Import and use"], style = "gold", onClick = function()
					local name, err = Profiles:Import(text)
					if name then Profiles:Use(name) status:SetText(("|cff5adc6e" .. L["Imported as \"%s\"."] .. "|r"):format(name)) else status:SetText("|cffeb5a50" .. tostring(err) .. "|r") end
				end },
				{ label = L["Import only"], onClick = function()
					local name, err = Profiles:Import(text)
					status:SetText(name and ("|cff5adc6e" .. (L["Imported as \"%s\"."]):format(name) .. "|r") or ("|cffeb5a50" .. tostring(err) .. "|r"))
				end },
				{ label = L["Cancel"] } } })
	end })
	function page:Refresh()
		who:SetText((L["Profile for %s"]):format(NBG:PlayerKey()))
		cur:Refresh() newC:Refresh() one:Refresh()
		local profs = Profiles:List()
		for _, r in ipairs(list.rows) do r:Hide() end
		local current = Settings:CurrentName()
		for i, p in ipairs(profs) do
			local r = list.rows[i]
			if not r then
				r = CreateFrame("Frame", nil, list)
				r:SetSize(pw - 8, 30)
				r.hl = r:CreateTexture(nil, "BACKGROUND") r.hl:SetAllPoints() r.hl:SetTexture(NBG.MEDIA .. "FadeR")
				r.check = W:Glyph(r, "check", 12, "header") r.check:SetPoint("LEFT", 12, 0)
				r.name = W:Text(r, 12, "text", "medium") r.name:SetPoint("LEFT", 34, 0)
				r.used = W:Text(r, 10.5, "textDim") r.used:SetPoint("LEFT", 200, 0) r.used:SetWidth(240) r.used:SetJustifyH("LEFT")
				r.when = W:Text(r, 10.5, "textDim") r.when:SetPoint("LEFT", 450, 0)
				r.use = W:IconButton(r, "check", 22, { tip = { L["Use this profile"] } })
				r.use:SetPoint("RIGHT", -84, 0)
				r.copy = W:IconButton(r, "copy", 22, { tip = { L["Copy"] } }) r.copy:SetPoint("RIGHT", -58, 0)
				r.ren = W:IconButton(r, "pen", 22, { tip = { L["Rename"] } }) r.ren:SetPoint("RIGHT", -32, 0)
				r.del = W:IconButton(r, "trash", 22, { tip = { L["Delete"] }, role = "negative" }) r.del:SetPoint("RIGHT", -6, 0)
				list.rows[i] = r
			end
			r:ClearAllPoints() r:SetPoint("TOPLEFT", 4, -54 - (i - 1) * 32)
			local on = p.name == current
			r.hl:SetShown(on) Skin:Paint(r.hl, "rowSel")
			r.check:SetShown(on)
			r.name:SetText(p.name) Skin:Paint(r.name, on and "header" or "text")
			r.used:SetText(#p.users > 0 and table.concat(p.users, ", ") or "-")
			r.when:SetText(p.changed and Store.Ago(p.changed) or "")
			r.use:SetScript("OnClick", function() Profiles:Use(p.name) end)
			r.copy:SetScript("OnClick", function() Ask(L["Copy profile"], L["Name of the copy:"], p.name .. " " .. L["copy"], function(t) return Profiles:Copy(p.name, t) end) end)
			r.ren:SetScript("OnClick", function() Ask(L["Rename profile"], L["New name:"], p.name, function(t) return Profiles:Rename(p.name, t) end) end)
			r.ren:SetEnabled(p.name ~= "Default")
			r.del:SetEnabled(p.name ~= "Default")
			r.del:SetScript("OnClick", function()
				W:Popup({ title = L["Delete profile"], text = (L["Delete the profile \"%s\"? Characters using it go back to Default."]):format(p.name), buttons = {
					{ label = L["Delete"], style = "red", onClick = function() Profiles:Delete(p.name) end }, { label = L["Cancel"] } } })
			end)
			r:Show()
		end
		local hdr = { L["NAME"], L["USED BY"], L["LAST CHANGED"] }
		list.hdr = list.hdr or {}
		for i, t in ipairs(hdr) do
			local fs = list.hdr[i] or W:Text(list, 9, "textDim", "bold")
			list.hdr[i] = fs
			fs:SetPoint("TOPLEFT", ({ 38, 204, 454 })[i], -34)
			fs:SetText(t)
		end
		local lh = 54 + #profs * 32 + 40
		list:SetHeight(lh)
		bNew:ClearAllPoints() bNew:SetPoint("BOTTOMLEFT", 14, 10)
		bCopy:ClearAllPoints() bCopy:SetPoint("LEFT", bNew, "RIGHT", 8, 0)
		bReset:ClearAllPoints() bReset:SetPoint("BOTTOMRIGHT", -14, 10)
		share:ClearAllPoints() share:SetPoint("TOPLEFT", 0, -y0 - 116 - lh - 12)
		bExp:ClearAllPoints() bExp:SetPoint("TOPLEFT", 14, -34)
		bImp:ClearAllPoints() bImp:SetPoint("LEFT", bExp, "RIGHT", 8, 0)
		cg:ClearAllPoints() cg:SetPoint("TOPLEFT", 262, -38) cg:SetWidth(120)
		cl:ClearAllPoints() cl:SetPoint("TOPLEFT", 392, -38) cl:SetWidth(130)
		ci:ClearAllPoints() ci:SetPoint("TOPLEFT", 530, -38) ci:SetWidth(120)
		cg:Refresh() cl:Refresh() ci:Refresh()
		box:ClearAllPoints() box:SetPoint("TOPLEFT", 14, -70)
		status:ClearAllPoints() status:SetPoint("TOPLEFT", 14, -164)
		page:SetContentHeight(y0 + 116 + lh + 12 + 236 + 20)
	end
	page.customY = y0 + 600
end

NBG:Register("PROFILE_CHANGED", function()
	local win = _G.NetherBagsConfig
	if win and win:IsShown() then
		for _, pg in pairs(win.pages or {}) do if pg:IsShown() and pg.Refresh then NBG:Safe("profiles page", pg.Refresh, pg) end end
	end
end)

---------------------------------------------------------------------------------------------
-- Plugins
---------------------------------------------------------------------------------------------
function Config:PagePlugins(page, y0)
	local c = page.content
	local box = Panel(c, 640, 200, L["INSTALLED PLUGINS"])
	box:SetPoint("TOPLEFT", 0, -y0)
	box.rows = {}
	local doc = W:Text(c, 10.5, "textDim")
	doc:SetWidth(620) doc:SetWordWrap(true) doc:SetJustifyH("LEFT")
	doc:SetText(L["Plugins are separate addons that use NetherBags' plugin interface (Docs/API.md): new rules for groups and search, new themes, entries in the item menu, and listening to NetherBags' messages. A plugin that keeps failing is switched off by itself and listed here."])
	function page:Refresh()
		local list = NBG.Plugin and NBG.Plugin:List() or {}
		for _, r in ipairs(box.rows) do r:Hide() end
		for i, p in ipairs(list) do
			local r = box.rows[i]
			if not r then
				r = CreateFrame("Frame", nil, box)
				r:SetSize(610, 40)
				r.check = W:Check(r, "", function() return r.p and not r.p.disabled end, function(v) NBG.Plugin:SetEnabled(r.p.id, v) page:Refresh() end)
				r.check:SetPoint("TOPLEFT", 0, -2)
				r.name = W:Text(r, 12, "text", "medium") r.name:SetPoint("TOPLEFT", 26, -2)
				r.desc = W:Text(r, 10, "textDim") r.desc:SetPoint("TOPLEFT", 26, -20) r.desc:SetWidth(560) r.desc:SetJustifyH("LEFT")
				box.rows[i] = r
			end
			r.p = p
			r:ClearAllPoints() r:SetPoint("TOPLEFT", 14, -36 - (i - 1) * 44)
			r.name:SetText(p.name .. (p.version and ("  |cff8c96b0" .. p.version .. "|r") or ""))
			r.desc:SetText(p.failed and ("|cffeb5a50" .. L["Switched off after errors:"] .. " " .. tostring(p.failed) .. "|r") or (p.description or ""))
			r.check:Refresh()
			r:Show()
		end
		if #list == 0 then
			box.empty = box.empty or W:Text(box, 11, "textDim")
			box.empty:SetPoint("TOPLEFT", 14, -40)
			box.empty:SetText(L["No plugins installed."])
			box.empty:Show()
		elseif box.empty then box.empty:Hide() end
		local h = max(90, 50 + #list * 44)
		box:SetHeight(h)
		doc:ClearAllPoints() doc:SetPoint("TOPLEFT", 4, -y0 - h - 14)
		page:SetContentHeight(y0 + h + 80)
	end
	page.customY = y0 + 300
end
