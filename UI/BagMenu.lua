--[[ NetherBags - UI/BagMenu.lua
	The bag menu: the bag icon next to the title of the bags window opens it.

	  - one row per bag (not the keyring): its icon, name, size, colour and what it holds;
	  - hovering a row opens its list of item kinds as tick boxes (as many as you like): that bag
	    then only takes those items (sorting moves them in, see Data/BagRules.lua);
	  - the cogwheel at the end of each row, just outside the menu's border, opens the bag's
	    colour: ten preset colours, "No colour" and "Custom..." (the game's colour picker). In One
	    bag the bag's slots get a light tint of that colour.

	  BagMenu:Toggle(window) / BagMenu:Hide() / BagMenu:IsShown() ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local BagMenu = NBG:Module("BagMenu")
local W, Skin, BagRules, Settings = NBG.Widgets, NBG.Skin, NBG.BagRules, NBG.Settings

local ipairs, floor = ipairs, math.floor

local ROW_H = 34
local MENU_W = 250

local panel

local function Raised(p)
	Skin:Window(p)
	local c = CreateFrame("Frame", nil, p)
	c:SetAllPoints()
	c:SetFrameLevel(p:GetFrameLevel() + 10)
	p.content = c
	return c
end

local function Swatch(parent, size)
	local s = CreateFrame("Button", nil, parent)
	s:SetSize(size, size)
	s.edge = s:CreateTexture(nil, "BACKGROUND")
	s.edge:SetAllPoints()
	Skin:Rounded(s.edge)
	s.fill = s:CreateTexture(nil, "ARTWORK")
	s.fill:SetPoint("TOPLEFT", 2, -2) s.fill:SetPoint("BOTTOMRIGHT", -2, 2)
	Skin:Rounded(s.fill)
	function s:SetRGB(rgb)
		self.rgb = rgb
		if rgb then
			self.fill:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)
			self.fill:SetAlpha(1)
		else
			self.fill:SetVertexColor(0.3, 0.32, 0.38, 1)
			self.fill:SetAlpha(0.35)
		end
	end
	function s:SetSelected(on)
		self.selected = on
		if on then Skin:Paint(self.edge, "header") else Skin:Paint(self.edge, "border", { alpha = 0.8 }) end
	end
	s:SetSelected(false)
	return s
end

local function Same(a, b)
	if not a or not b then return a == b end
	return math.abs(a[1] - b[1]) < 0.01 and math.abs(a[2] - b[2]) < 0.01 and math.abs(a[3] - b[3]) < 0.01
end

---------------------------------------------------------------------------------------------
-- the kinds submenu (tick boxes)
---------------------------------------------------------------------------------------------
local function BuildKinds(p)
	local s = CreateFrame("Frame", "NetherBagsBagMenuKinds", p)
	s:SetFrameStrata("DIALOG")
	s:SetClampedToScreen(true)
	s:EnableMouse(true)
	local c = Raised(s)
	s.title = W:Text(c, 11, "header", "caps")
	s.title:SetPoint("TOPLEFT", 16, -14)
	s.title:SetPoint("RIGHT", -16, 0)
	s.title:SetJustifyH("LEFT")
	s.checks = {}
	local y = 36
	for i, k in ipairs(BagRules:Kinds()) do
		local cb = W:Check(c, k.label, function() return s.bag and BagRules:Has(s.bag, k.id) end,
			function() if s.bag then BagRules:Toggle(s.bag, k.id) end end)
		cb:SetWidth(180)
		cb:SetPoint("TOPLEFT", 16, -y)
		cb.kind = k.id
		s.checks[i] = cb
		y = y + 21
	end
	s.clear = W:Button(c, L["Any item"], 90, 22, { size = 10.5, onClick = function() if s.bag then BagRules:Clear(s.bag) end end })
	s.clear:SetPoint("TOPLEFT", 16, -y - 8)
	s.hint = W:Text(c, 9.5, "faint")
	s.hint:SetWordWrap(true) s.hint:SetJustifyH("LEFT")
	s.hint:SetWidth(190)
	s.hint:SetPoint("TOPLEFT", s.clear, "BOTTOMLEFT", 0, -8)
	s.hint:SetText(L["Sorting puts these items in this bag and keeps others out. None ticked: any item."])
	s:SetSize(222, y + 8 + 22 + 8 + 40 + 12)
	s:Hide()
	function s:Refresh() for _, cb in ipairs(self.checks) do cb:Refresh() end end
	return s
end

---------------------------------------------------------------------------------------------
-- the colour side menu
---------------------------------------------------------------------------------------------
local function OpenPicker(bag)
	local cpf = rawget(_G, "ColorPickerFrame")
	if not cpf then return false end
	local old = BagRules:Color(bag)
	local r, g, b = 0.6, 0.6, 0.6
	if old then r, g, b = old[1], old[2], old[3] end
	local function Apply()
		local nr, ng, nb = cpf:GetColorRGB()
		BagRules:SetColor(bag, { nr, ng, nb })
	end
	local function Cancel() BagRules:SetColor(bag, old) end
	if cpf.SetupColorPickerAndShow then
		local ok = pcall(cpf.SetupColorPickerAndShow, cpf, { r = r, g = g, b = b, hasOpacity = false, swatchFunc = Apply, cancelFunc = Cancel })
		return ok
	end
	-- older clients
	cpf.func, cpf.cancelFunc, cpf.hasOpacity, cpf.previousValues = Apply, Cancel, false, { r, g, b }
	if cpf.SetColorRGB then pcall(cpf.SetColorRGB, cpf, r, g, b) end
	cpf:Hide() cpf:Show()
	return true
end

local function BuildColors(p)
	local s = CreateFrame("Frame", "NetherBagsBagMenuColors", p)
	s:SetFrameStrata("DIALOG")
	s:SetClampedToScreen(true)
	s:EnableMouse(true)
	local c = Raised(s)
	s.title = W:Text(c, 11, "header", "caps")
	s.title:SetPoint("TOPLEFT", 16, -14)
	s.title:SetPoint("RIGHT", -16, 0)
	s.title:SetJustifyH("LEFT")
	s.swatches = {}
	local SZ, GAP = 26, 6
	for i, rgb in ipairs(BagRules.PRESETS) do
		local sw = Swatch(c, SZ)
		local col, row = (i - 1) % 5, floor((i - 1) / 5)
		sw:SetPoint("TOPLEFT", 16 + col * (SZ + GAP), -36 - row * (SZ + GAP))
		sw:SetRGB(rgb)
		sw:SetScript("OnClick", function() if s.bag then BagRules:SetColor(s.bag, rgb) end end)
		s.swatches[i] = sw
	end
	local y = 36 + 2 * (SZ + GAP) + 6
	s.none = W:Button(c, L["No colour"], 74, 22, { size = 10.5, onClick = function() if s.bag then BagRules:SetColor(s.bag, nil) end end })
	s.none:SetPoint("TOPLEFT", 16, -y)
	s.custom = W:Button(c, L["Custom..."], 74, 22, { size = 10.5, onClick = function() if s.bag then OpenPicker(s.bag) end end })
	s.custom:SetPoint("LEFT", s.none, "RIGHT", 6, 0)
	s.hint = W:Text(c, 9.5, "faint")
	s.hint:SetWordWrap(true) s.hint:SetJustifyH("LEFT")
	s.hint:SetWidth(154)
	s.hint:SetPoint("TOPLEFT", s.none, "BOTTOMLEFT", 0, -8)
	s.hint:SetText(L["Tints this bag's slots in One bag."])
	s:SetSize(16 + 5 * (SZ + GAP) - GAP + 16, y + 22 + 8 + 26 + 10)
	s:Hide()
	function s:Refresh()
		local cur = self.bag and BagRules:Color(self.bag)
		for i, sw in ipairs(self.swatches) do sw:SetSelected(Same(cur, BagRules.PRESETS[i])) end
		if not Settings:Get("onebag.bagColors") then
			self.hint:SetText(L["Tints this bag's slots in One bag (turned off in Settings > One bag)."])
		else
			self.hint:SetText(L["Tints this bag's slots in One bag."])
		end
	end
	return s
end

---------------------------------------------------------------------------------------------
-- the menu
---------------------------------------------------------------------------------------------
local function KindsText(bag)
	local n = BagRules:Count(bag)
	if n == 0 then return L["Any item"] end
	local names = {}
	for _, k in ipairs(BagRules:Kinds()) do if BagRules:Has(bag, k.id) then names[#names + 1] = k.label end end
	local s = table.concat(names, ", ")
	if #s > 30 then s = (L["%d kinds"]):format(n) end
	return s
end

local function Row(p, i)
	p.rows = p.rows or {}
	local r = p.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, p.content)
	r:SetHeight(ROW_H)
	r.hl = r:CreateTexture(nil, "BACKGROUND")
	r.hl:SetAllPoints()
	Skin:Rounded(r.hl)
	Skin:Paint(r.hl, "rowSel", { alpha = 0.8 })
	r.hl:Hide()
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(22, 22)
	r.icon:SetPoint("LEFT", 8, 0)
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	r.ring = r:CreateTexture(nil, "OVERLAY")
	r.ring:SetPoint("TOPLEFT", r.icon, -2, 2) r.ring:SetPoint("BOTTOMRIGHT", r.icon, 2, -2)
	Skin:Rounded(r.ring, true, 6)
	r.name = W:Text(r, 11.5, "text")
	r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 9, 1)
	r.name:SetPoint("RIGHT", -30, 0)
	r.name:SetJustifyH("LEFT") r.name:SetWordWrap(false)
	r.sub = W:Text(r, 9.5, "faint")
	r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 9, -1)
	r.sub:SetPoint("RIGHT", -30, 0)
	r.sub:SetJustifyH("LEFT") r.sub:SetWordWrap(false)
	r.chev = W:Glyph(r, "chev_r", 12, "textDim")
	r.chev:SetPoint("RIGHT", -10, 0)
	-- the cogwheel: outside the menu's right border
	r.cog = W:IconButton(p, "gear", 22, { onClick = function() BagMenu:OpenColors(r) end, tip = { L["Colour"], L["Pick a colour for this bag's slots in One bag."] } })
	r.cog:SetFrameLevel(p:GetFrameLevel() + 20)
	r.cog:SetPoint("LEFT", r, "RIGHT", 14, 0)
	r.cog.dot = r.cog:CreateTexture(nil, "OVERLAY")
	r.cog.dot:SetSize(8, 8)
	r.cog.dot:SetPoint("BOTTOMRIGHT", 1, -1)
	Skin:Rounded(r.cog.dot, false, 3)
	r:SetScript("OnEnter", function(self) self.hl:Show() BagMenu:OpenKinds(self) end)
	r:SetScript("OnLeave", function(self) if not (p.kinds and p.kinds:IsShown() and p.kinds.row == self) then self.hl:Hide() end end)
	r:SetScript("OnClick", function(self) BagMenu:OpenKinds(self) end)
	p.rows[i] = r
	return r
end

local function Build()
	local p = CreateFrame("Frame", "NetherBagsBagMenu", UIParent)
	p:SetFrameStrata("DIALOG")
	p:SetToplevel(true)
	p:SetClampedToScreen(true)
	p:EnableMouse(true)
	local c = Raised(p)
	p.head = W:Text(c, 11, "header", "caps")
	p.head:SetPoint("TOPLEFT", 16, -14)
	p.head:SetText(L["BAG MENU"])
	p.note = W:Text(c, 9.5, "faint")
	p.note:SetPoint("TOPLEFT", p.head, "BOTTOMLEFT", 0, -4)
	p.note:SetPoint("RIGHT", -16, 0)
	p.note:SetJustifyH("LEFT") p.note:SetWordWrap(true)
	p.note:SetText(L["Hover a bag to choose what it holds; the cogwheel gives it a colour."])
	p:Hide()
	p:SetScript("OnHide", function(self)
		if self.kinds then self.kinds:Hide() end
		if self.colors then self.colors:Hide() end
		if self.window and self.window.bagBtn then self.window.bagBtn:SetActive(false) end
	end)
	if _G.UISpecialFrames then table.insert(UISpecialFrames, "NetherBagsBagMenu") end
	return p
end

function BagMenu:Layout()
	local p = panel
	local bags = BagRules:Bags()
	local top = 52
	for i, info in ipairs(bags) do
		local r = Row(p, i)
		r.bag = info.id
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", p.content, "TOPLEFT", 8, -top - (i - 1) * (ROW_H + 2))
		r:SetPoint("RIGHT", p.content, "RIGHT", -8, 0)
		r.icon:SetTexture(info.icon or 133633)
		r.name:SetText((info.name or L["Bag"]) .. "  |cff8c96b0" .. (L["%d slots"]):format(info.size or 0) .. "|r")
		r.special = info.special and true or false
		r.sub:SetText(r.special and L["Special bag: holds its own kind"] or KindsText(info.id))
		local col = BagRules:Color(info.id)
		if col then r.ring:SetVertexColor(col[1], col[2], col[3], 1) r.ring:Show() else r.ring:Hide() end
		if col then r.cog.dot:SetVertexColor(col[1], col[2], col[3], 1) r.cog.dot:Show() else r.cog.dot:Hide() end
		r.chev:SetShown(not r.special)
		r:Show() r.cog:Show()
		r.hl:SetShown(p.kinds and p.kinds:IsShown() and p.kinds.row == r or false)
	end
	for i = #bags + 1, #(p.rows or {}) do p.rows[i]:Hide() p.rows[i].cog:Hide() end
	p:SetSize(MENU_W, top + #bags * (ROW_H + 2) + 10)
	p.count = #bags
end

function BagMenu:OpenKinds(r)
	local p = panel
	if not p then return end
	if p.colors then p.colors:Hide() end
	if r.special then
		-- a quiver, soul bag, herb bag...: the game decides what goes in it; only its colour
		if p.kinds then p.kinds:Hide() if p.kinds.row and p.kinds.row ~= r then p.kinds.row.hl:Hide() end p.kinds.row = nil end
		return
	end
	p.kinds = p.kinds or BuildKinds(p)
	local s = p.kinds
	if s.row and s.row ~= r and s.row.hl then s.row.hl:Hide() end
	s.row, s.bag = r, r.bag
	r.hl:Show()
	s.title:SetText((r.name:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x.-|r", ""):upper())
	s:ClearAllPoints()
	s:SetPoint("TOPLEFT", r.cog, "TOPRIGHT", 8, 6)
	s:SetFrameLevel(p:GetFrameLevel() + 30)
	s:Refresh()
	s:Show()
end

function BagMenu:OpenColors(r)
	local p = panel
	if not p then return end
	if p.kinds then p.kinds:Hide() end
	p.colors = p.colors or BuildColors(p)
	local s = p.colors
	if s:IsShown() and s.bag == r.bag then s:Hide() return end
	s.row, s.bag = r, r.bag
	s.title:SetText(L["COLOUR"])
	s:ClearAllPoints()
	s:SetPoint("TOPLEFT", r.cog, "TOPRIGHT", 8, 6)
	s:SetFrameLevel(p:GetFrameLevel() + 30)
	s:Refresh()
	s:Show()
end

function BagMenu:IsShown() return panel and panel:IsShown() or false end
function BagMenu:Hide() if panel then panel:Hide() end end

function BagMenu:Toggle(w, anchor)
	panel = panel or Build()
	if panel:IsShown() then panel:Hide() return end
	if not (w and w.location == "bags" and w.Live and w:Live()) then return end
	W:CloseMenu()
	panel.window = w
	self:Layout()
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", anchor or w, "BOTTOMLEFT", -6, -6)
	panel:Show()
	if w.bagBtn then w.bagBtn:SetActive(true) end
	NBG:After(0.05, function() if panel:IsShown() then Skin:Redraw() end end)
end

NBG:Register("BAG_RULES", function()
	if panel and panel:IsShown() then
		BagMenu:Layout()
		if panel.kinds and panel.kinds:IsShown() then panel.kinds:Refresh() end
		if panel.colors and panel.colors:IsShown() then panel.colors:Refresh() end
	end
	NBG:Debounce("bagRules", 0.05, function() NBG.Windows:RefreshAll() end)
end)
NBG:Register("BAGS_CHANGED", function() if panel and panel:IsShown() then BagMenu:Layout() end end)
NBG:Register("WINDOW_HIDDEN", function(_, id) if id == "bags" then BagMenu:Hide() end end)
NBG:On("PLAYER_REGEN_DISABLED", function() BagMenu:Hide() end)
