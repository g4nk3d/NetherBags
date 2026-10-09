--[[ NetherBags - UI/Everywhere.lua
	Two Insight places that are not bags:

	  Everywhere   type a search: every item that matches, on every character, in every bank,
	               mailbox and guild bank this account has seen, with who has how many where.
	               With nothing typed: the account's characters, their gold and when each was
	               last seen. The Filters button (next to the Everywhere tab) narrows it: tick the
	               kinds of items to see and the places to look in (bags, bank, guild bank,
	               mailbox). With filters narrowed and nothing typed, every item that passes them
	               is listed.
	  Currencies   this character's currencies, as the game lists them. ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Everywhere = NBG:Module("Everywhere")
local Skin, W, Settings, Common = NBG.Skin, NBG.Widgets, NBG.Settings, NBG.Common
local Store, Search, Items, Buttons = NBG.Store, NBG.Search, NBG.Items, NBG.Buttons

local type, pairs, ipairs, max, min, floor = type, pairs, ipairs, math.max, math.min, math.floor

local function Row(v, i)
	v.everyRows = v.everyRows or {}
	local r = v.everyRows[i]
	if r then return r end
	r = CreateFrame("Button", nil, v.scroll.content)
	r:SetHeight(26)
	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.bg:SetTexture(NBG.MEDIA .. "FadeR")
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	r.edge = r:CreateTexture(nil, "OVERLAY")
	r.edge:SetTexture(NBG.MEDIA .. "SlotRing")
	r.glyph = W:Glyph(r, "backpack", 14, "textDim")
	r.a = W:Text(r, 12, "text", "medium")
	r.a:SetJustifyH("LEFT")
	r.b = W:Text(r, 9.5, "textDim")
	r.b:SetJustifyH("LEFT")
	r.c = W:Text(r, 11.5, "text", "medium")
	r.d = W:Text(r, 11, "text")
	r.d:SetJustifyH("LEFT")
	r.n = W:Text(r, 12, "text", "medium")
	r.n:SetJustifyH("RIGHT")
	r.nsub = W:Text(r, 9, "textDim")
	r.barBg = r:CreateTexture(nil, "ARTWORK")
	r.barBg:SetTexture(NBG.MEDIA .. "Pill")
	r.bar = r:CreateTexture(nil, "OVERLAY")
	r.bar:SetTexture(NBG.MEDIA .. "Pill")
	r.pct = W:Text(r, 10, "faint")
	r.tree = r:CreateTexture(nil, "ARTWORK")
	r.tree:SetColorTexture(1, 1, 1, 1)
	r.tree2 = r:CreateTexture(nil, "ARTWORK")
	r.tree2:SetColorTexture(1, 1, 1, 1)
	r.line = r:CreateTexture(nil, "ARTWORK")
	r.line:SetTexture(NBG.MEDIA .. "FadeR")
	r.line:SetPoint("BOTTOMLEFT") r.line:SetPoint("BOTTOMRIGHT") r.line:SetHeight(1)
	r:SetScript("OnEnter", function(self)
		if self.link then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if pcall(GameTooltip.SetHyperlink, GameTooltip, self.link) then GameTooltip:Show() end
		end
		if self.hl then self.bg:Show() end
	end)
	r:SetScript("OnLeave", function(self) GameTooltip:Hide() if self.hl then self.bg:SetShown(self.keepBg) end end)
	r:SetScript("OnClick", function(self) if self.link and _G.HandleModifiedItemClick then pcall(HandleModifiedItemClick, self.link) end end)
	v.everyRows[i] = r
	return r
end

local function Clear(r)
	for _, k in ipairs({ "icon", "edge", "glyph", "a", "b", "c", "d", "n", "nsub", "barBg", "bar", "pct", "tree", "tree2", "line" }) do r[k]:Hide() end
	r.link, r.hl, r.keepBg = nil, nil, nil
	r.bg:Hide()
	Skin:Font(r.a, "medium", 12)
	Skin:Paint(r.a, "text")
end

local WHERE = { bags = { "backpack", "Bags" }, bank = { "bank", "Bank" }, mail = { "mail", "Mailbox" }, guild = { "guild", "Guild bank" } }

---------------------------------------------------------------------------------------------
-- filters: kinds of items and places, kept with the layout (profile)
---------------------------------------------------------------------------------------------
Everywhere.PLACES = {
	{ id = "bags", label = L["Bags"], glyph = "backpack" },
	{ id = "bank", label = L["Bank"], glyph = "bank" },
	{ id = "guild", label = L["Guild bank"], glyph = "guild" },
	{ id = "mail", label = L["Mailbox"], glyph = "mail" },
}
function Everywhere:Kinds()
	local out = {}
	for _, c in ipairs(NBG.Groups.CATEGORIES) do if c.id ~= "all" then out[#out + 1] = c end end
	out[#out + 1] = NBG.Groups.JUNK_CATEGORY
	return out
end
local function F()
	local lay = Settings:Profile().layout
	lay.everyFilter = type(lay.everyFilter) == "table" and lay.everyFilter or {}
	local f = lay.everyFilter
	f.kinds = type(f.kinds) == "table" and f.kinds or {}     -- id -> false when unticked
	f.places = type(f.places) == "table" and f.places or {}
	return f
end
function Everywhere:KindOn(id) return F().kinds[id] ~= false end
function Everywhere:PlaceOn(id) return F().places[id] ~= false end
function Everywhere:SetKind(id, on) if on then F().kinds[id] = nil else F().kinds[id] = false end Settings:Touch() NBG:Fire("EVERY_FILTER") end
function Everywhere:SetPlace(id, on) if on then F().places[id] = nil else F().places[id] = false end Settings:Touch() NBG:Fire("EVERY_FILTER") end
function Everywhere:Narrowed()
	local n = 0
	for _, v in pairs(F().kinds) do if v == false then n = n + 1 end end
	for _, v in pairs(F().places) do if v == false then n = n + 1 end end
	return n
end
function Everywhere:ResetFilters() local f = F() NBG.wipe(f.kinds) NBG.wipe(f.places) Settings:Touch() NBG:Fire("EVERY_FILTER") end

-- does the item pass the kind filters (any ticked kind it belongs to)?
function Everywhere:PassesKinds(e)
	local f = F()
	local any = false
	for _, v in pairs(f.kinds) do if v == false then any = true break end end
	if not any then return true end
	for _, c in ipairs(self:Kinds()) do
		if f.kinds[c.id] ~= false then
			local ok, r = pcall(c.test, e)
			if ok and r then return true end
		end
	end
	return false
end

-- the panel under the Filters button
local panel
local function BuildPanel()
	local p = CreateFrame("Frame", "NetherBagsEverywhereFilters", UIParent)
	p:SetFrameStrata("DIALOG")
	p:SetToplevel(true)
	p:SetClampedToScreen(true)
	p:EnableMouse(true)
	Skin:Window(p)
	local c = CreateFrame("Frame", nil, p)
	c:SetAllPoints()
	c:SetFrameLevel(p:GetFrameLevel() + 10)
	p.content = c
	p.h1 = W:Text(c, 11, "header", "caps")
	p.h1:SetPoint("TOPLEFT", 16, -14)
	p.h1:SetText(L["SHOW"])
	p.h2 = W:Text(c, 11, "header", "caps")
	p.h2:SetText(L["LOOK IN"])
	p.kinds, p.places = {}, {}
	local y = 36
	for i, k in ipairs(Everywhere:Kinds()) do
		local cb = W:Check(c, k.label, function() return Everywhere:KindOn(k.id) end, function(on) Everywhere:SetKind(k.id, on) end)
		cb:SetWidth(190)
		cb:SetPoint("TOPLEFT", 16, -y)
		p.kinds[i] = cb
		y = y + 22
	end
	local colH = y
	p.h2:SetPoint("TOPLEFT", 222, -14)
	y = 36
	for i, pl in ipairs(Everywhere.PLACES) do
		local cb = W:Check(c, pl.label, function() return Everywhere:PlaceOn(pl.id) end, function(on) Everywhere:SetPlace(pl.id, on) end)
		cb:SetWidth(150)
		cb:SetPoint("TOPLEFT", 222, -y)
		p.places[i] = cb
		y = y + 22
	end
	-- quick buttons
	p.all = W:Button(c, L["All"], 70, 22, { size = 10.5, onClick = function() Everywhere:ResetFilters() end })
	p.all:SetPoint("TOPLEFT", 222, -y - 14)
	p.none = W:Button(c, L["None"], 70, 22, { size = 10.5, onClick = function()
		for _, k in ipairs(Everywhere:Kinds()) do F().kinds[k.id] = false end
		Settings:Touch() NBG:Fire("EVERY_FILTER")
	end })
	p.none:SetPoint("LEFT", p.all, "RIGHT", 6, 0)
	p.hint = W:Text(c, 9.5, "faint")
	p.hint:SetWordWrap(true) p.hint:SetJustifyH("LEFT")
	p.hint:SetWidth(150)
	p.hint:SetPoint("TOPLEFT", p.all, "BOTTOMLEFT", 0, -10)
	p.hint:SetText(L["\"None\" clears the kinds; then tick only the ones you want."])
	p:SetSize(390, math.max(colH, y + 100) + 14)
	p:Hide()
	if _G.UISpecialFrames then table.insert(UISpecialFrames, "NetherBagsEverywhereFilters") end
	NBG:Register("EVERY_FILTER", function()
		for _, cb in ipairs(p.kinds) do cb:Refresh() end
		for _, cb in ipairs(p.places) do cb:Refresh() end
	end)
	return p
end

function Everywhere:ToggleFilters(v, anchor)
	panel = panel or BuildPanel()
	if panel:IsShown() then panel:Hide() return end
	panel.view = v
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
	for _, cb in ipairs(panel.kinds) do cb:Refresh() end
	for _, cb in ipairs(panel.places) do cb:Refresh() end
	panel:Show()
	NBG:After(0.05, function() if panel:IsShown() then Skin:Redraw() end end)
end
function Everywhere:HideFilters() if panel then panel:Hide() end end
NBG:Register("EVERY_FILTER", function() NBG:Debounce("everyFilter", 0.05, function() NBG.Windows:RefreshAll(true) end) end)
NBG:Register("WINDOW_HIDDEN", function() Everywhere:HideFilters() end)

function Everywhere:Hide(v)
	for _, r in ipairs(v.everyRows or {}) do r:Hide() end
end

function Everywhere:Render(v)
	local width = v.scroll:GetWidth() - 12
	local y, n = 0, 0
	local q = v.query
	local cols = { owner = floor(width * 0.40), where = floor(width * 0.62), count = width - 6 }
	local narrowed = self:Narrowed() > 0
	if not q and not narrowed then
		-- the characters
		for _, c in ipairs(Store:Characters()) do
			n = n + 1
			local r = Row(v, n)
			Clear(r)
			r:ClearAllPoints() r:SetPoint("TOPLEFT", 0, -y) r:SetPoint("RIGHT")
			r:SetHeight(34)
			r.glyph:Show() W:SetGlyph(r.glyph, "user") Skin:Paint(r.glyph, "accent")
			r.glyph:ClearAllPoints() r.glyph:SetPoint("LEFT", 12, 0)
			r.a:Show() r.a:ClearAllPoints() r.a:SetPoint("LEFT", 36, 6)
			r.a:SetText(Common.ClassColor(c.class) .. c.key .. "|r" .. (c.key == NBG:PlayerKey() and ("  |cffe8c478" .. L["(you)"] .. "|r") or ""))
			r.b:Show() r.b:ClearAllPoints() r.b:SetPoint("LEFT", 36, -8)
			r.b:SetText(((c.level and (L["Level"] .. " " .. c.level) or "") .. (c.guild and ("  ·  <" .. c.guild .. ">") or "")))
			r.d:Show() r.d:ClearAllPoints() r.d:SetPoint("LEFT", r, "LEFT", cols.owner, 0)
			r.d:SetText(L["seen"] .. " " .. Store.Ago(c.updated))
			r.n:Show() r.n:ClearAllPoints() r.n:SetPoint("RIGHT", r, "LEFT", cols.count, 0)
			r.n:SetText(W:Money(c.money))
			r.line:Show() Skin:Paint(r.line, "border", { alpha = 0.5 })
			r:Show()
			y = y + 34
		end
		n = n + 1
		local r = Row(v, n)
		Clear(r)
		r:ClearAllPoints() r:SetPoint("TOPLEFT", 0, -(y + 12)) r:SetPoint("RIGHT")
		r.d:Show() r.d:ClearAllPoints() r.d:SetPoint("LEFT", 12, 0)
		r.d:SetText("|cff8c96b0" .. L["Type in the search box to find an item on every character, bank, mailbox and guild bank, or narrow it with Filters."] .. "|r")
		r:Show()
		y = y + 46
		for i = n + 1, #(v.everyRows or {}) do v.everyRows[i]:Hide() end
		v.scroll:SetContentHeight(y)
		return
	end
	local results = Store:Find(function(e) return Search:Match(e, q) and self:PassesKinds(e) end, {
		bags = self:PlaceOn("bags"), bank = self:PlaceOn("bank"),
		mail = Settings:Get("search.mail") and self:PlaceOn("mail"), guild = Settings:Get("search.guild") and self:PlaceOn("guild") })
	local shownItems = 0
	for _, rec in ipairs(results) do
		shownItems = shownItems + 1
		if shownItems > 60 then break end
		local info = Items:Info(rec.link)
		n = n + 1
		local r = Row(v, n)
		Clear(r)
		r:ClearAllPoints() r:SetPoint("TOPLEFT", 0, -y) r:SetPoint("RIGHT")
		r:SetHeight(38)
		r.link = info and info.link or rec.link
		r.bg:Show() r.keepBg = true
		Skin:Gradient(r.bg, "HORIZONTAL", "bgTop", "bg", 0.95, 0)
		r.icon:Show() r.icon:ClearAllPoints() r.icon:SetPoint("LEFT", 12, 0) r.icon:SetSize(28, 28)
		r.icon:SetTexture(info and info.icon or (rec.id and select(4, Items:Instant(rec.id))))
		r.edge:Show() r.edge:ClearAllPoints() r.edge:SetPoint("CENTER", r.icon, "CENTER") r.edge:SetSize(30, 30)
		local qr, qg, qb = Items:QualityColor(info and info.quality or 1)
		r.edge:SetVertexColor(qr, qg, qb, (info and info.quality or 1) >= 2 and 0.9 or 0)
		r.a:Show() r.a:ClearAllPoints() r.a:SetPoint("LEFT", 50, 7)
		r.a:SetText(info and info.name or ("item " .. tostring(rec.id))) Skin:Unpaint(r.a) r.a:SetTextColor(qr, qg, qb)
		r.b:Show() r.b:ClearAllPoints() r.b:SetPoint("LEFT", 50, -8)
		r.b:SetText(info and (info.subType ~= "" and info.subType or info.type) or "")
		r.n:Show() r.n:ClearAllPoints() r.n:SetPoint("RIGHT", r, "LEFT", cols.count, 6)
		r.n:SetText(tostring(rec.total)) Skin:Paint(r.n, "header")
		r.nsub:Show() r.nsub:ClearAllPoints() r.nsub:SetPoint("TOPRIGHT", r.n, "BOTTOMRIGHT", 0, -2) r.nsub:SetText(L["total"])
		r.line:Show() Skin:Paint(r.line, "accent", { alpha = 0.4 })
		r:Show()
		y = y + 40
		for _, p in ipairs(rec.places) do
			n = n + 1
			local s = Row(v, n)
			Clear(s)
			s:ClearAllPoints() s:SetPoint("TOPLEFT", 0, -y) s:SetPoint("RIGHT")
			s:SetHeight(26)
			s.hl = true
			Skin:Paint(s.bg, "rowHover")
			s.tree:Show() s.tree:ClearAllPoints() s.tree:SetPoint("TOPLEFT", 26, 0) s.tree:SetSize(1, 26) Skin:Paint(s.tree, "border")
			s.tree2:Show() s.tree2:ClearAllPoints() s.tree2:SetPoint("LEFT", 26, 0) s.tree2:SetSize(12, 1) Skin:Paint(s.tree2, "border")
			local bw = 70
			s.barBg:Show() s.barBg:ClearAllPoints() s.barBg:SetPoint("LEFT", 50, 0) s.barBg:SetSize(bw, 4) Skin:Paint(s.barBg, "inset")
			local frac = rec.total > 0 and p.count / rec.total or 0
			s.bar:Show() s.bar:ClearAllPoints() s.bar:SetPoint("LEFT", s.barBg, "LEFT") s.bar:SetSize(max(3, bw * frac), 4)
			s.pct:Show() s.pct:ClearAllPoints() s.pct:SetPoint("LEFT", s.barBg, "RIGHT", 8, 0) s.pct:SetText(floor(frac * 100 + 0.5) .. "%")
			local c = Store:Char(p.owner)
			local who = p.kind == "guild" and ("|cff78e678<" .. p.owner .. ">|r") or (Common.ClassColor(c and c.class) .. p.owner .. "|r")
			if p.owner == NBG:PlayerKey() then who = "|cffe8c478•|r " .. who end
			s.a:Show() s.a:ClearAllPoints() s.a:SetPoint("LEFT", s, "LEFT", cols.owner, 0) s.a:SetText(who)
			Skin:Paint(s.a, "text")
			local wd = WHERE[p.where] or WHERE.bags
			s.glyph:Show() W:SetGlyph(s.glyph, wd[1]) Skin:Paint(s.glyph, "textDim")
			s.glyph:ClearAllPoints() s.glyph:SetPoint("LEFT", s, "LEFT", cols.where, 0)
			s.d:Show() s.d:ClearAllPoints() s.d:SetPoint("LEFT", s.glyph, "RIGHT", 6, 0)
			s.d:SetText(L[wd[2]] .. (p.tab and ("  ·  " .. L["Tab"] .. " " .. p.tab) or ""))
			s.n:Show() s.n:ClearAllPoints() s.n:SetPoint("RIGHT", s, "LEFT", cols.count, 0) s.n:SetText(tostring(p.count)) Skin:Paint(s.n, "text")
			Skin:Paint(s.bar, "accent")
			s:Show()
			y = y + 26
		end
		y = y + 8
	end
	if #results == 0 then
		n = n + 1
		local r = Row(v, n)
		Clear(r)
		r:ClearAllPoints() r:SetPoint("TOPLEFT", 0, -20) r:SetPoint("RIGHT")
		r.d:Show() r.d:ClearAllPoints() r.d:SetPoint("LEFT", 12, 0)
		r.d:SetText("|cff8c96b0" .. L["Nothing found on any character."] .. "|r")
		r:Show()
		y = 60
	end
	for i = n + 1, #(v.everyRows or {}) do v.everyRows[i]:Hide() end
	v.scroll:SetContentHeight(y)
end

function Everywhere:RenderCurrencies(v)
	local C = rawget(_G, "C_CurrencyInfo")
	local y, n = 0, 0
	local width = v.scroll:GetWidth() - 12
	if type(C) == "table" and type(C.GetCurrencyListSize) == "function" and type(C.GetCurrencyListInfo) == "function" then
		local size = NBG.Num(NBG.Call(C.GetCurrencyListSize)) or 0
		for i = 1, size do
			local info = NBG.Open(NBG.Call(C.GetCurrencyListInfo, i))
			if info and NBG.Str(info.name) then
				n = n + 1
				local r = Row(v, n)
				Clear(r)
				r:ClearAllPoints() r:SetPoint("TOPLEFT", 0, -y) r:SetPoint("RIGHT")
				if info.isHeader then
					r:SetHeight(24)
					r.bg:Show() r.keepBg = true
					Skin:Gradient(r.bg, "HORIZONTAL", "bgTop", "bg", 0.95, 0)
					r.a:Show() r.a:ClearAllPoints() r.a:SetPoint("LEFT", 12, 0)
					Skin:Font(r.a, "caps", 11) Skin:Paint(r.a, "header")
					r.a:SetText(info.name:upper())
					y = y + 26
				else
					r:SetHeight(28)
					Skin:Font(r.a, "medium", 12) Skin:Paint(r.a, "text")
					r.icon:Show() r.icon:ClearAllPoints() r.icon:SetPoint("LEFT", 22, 0) r.icon:SetSize(20, 20)
					r.icon:SetTexture(info.iconFileID)
					r.a:Show() r.a:ClearAllPoints() r.a:SetPoint("LEFT", 50, 0) r.a:SetText(info.name)
					r.n:Show() r.n:ClearAllPoints() r.n:SetPoint("RIGHT", r, "LEFT", width - 6, 0)
					local q = NBG.Num(info.quantity) or 0
					local mx = NBG.Num(info.maxQuantity) or 0
					r.n:SetText((BreakUpLargeNumbers and BreakUpLargeNumbers(q) or q) .. (mx > 0 and ("  |cff8c96b0/ " .. mx .. "|r") or ""))
					Skin:Paint(r.n, "text")
					if info.isShowInBackpack then
						r.glyph:Show() W:SetGlyph(r.glyph, "backpack") Skin:Paint(r.glyph, "accent")
						r.glyph:ClearAllPoints() r.glyph:SetPoint("RIGHT", r.n, "LEFT", -12, 0)
					end
					r.line:Show() Skin:Paint(r.line, "border", { alpha = 0.4 })
					y = y + 28
				end
				r:Show()
			end
		end
	end
	if n == 0 then
		n = 1
		local r = Row(v, 1)
		Clear(r)
		r:ClearAllPoints() r:SetPoint("TOPLEFT", 0, -20) r:SetPoint("RIGHT")
		r.d:Show() r.d:ClearAllPoints() r.d:SetPoint("LEFT", 12, 0)
		r.d:SetText("|cff8c96b0" .. L["No currencies yet."] .. "|r")
		r:Show()
		y = 60
	end
	for i = n + 1, #(v.everyRows or {}) do v.everyRows[i]:Hide() end
	v.scroll:SetContentHeight(y)
end
