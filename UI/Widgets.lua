--[[ NetherBags - UI/Widgets.lua
	The pieces every window is built from. Every piece paints itself by role (UI/Skin.lua), so a
	skin change reaches all of them.

	  W:Text(parent, size, role [, kind])           font string
	  W:Glyph(parent, name, size [, role])          one of the addon's glyphs (Media\Glyphs)
	  W:Button(parent, label, w, h [, opts])        opts: { style = "dark"|"gold"|"red", glyph, onClick, tip }
	  W:IconButton(parent, glyph, size [, opts])    opts: { tip, onClick, role }; :SetActive(on), :SetBadge(text)
	  W:Pill(parent, labels, onSelect)              the "One bag | Insight" switch; :SetValue(i)
	  W:Chip(parent, label, glyph, role, onToggle)  a filter chip; :SetOn(on)
	  W:Check(parent, label, get, set [, sub])      check box (a setting)
	  W:Slider(parent, label, min, max, step, get, set [, fmt])
	  W:Dropdown(parent, w, options, get, set)      options: function -> { { value, label [, color] } }
	  W:Edit(parent, w, h [, hint, opts])           opts: { onChange, onEnter, onEscape, multiline, numeric }
	  W:Search(parent, w, h, hint, onChange)        the rounded search box
	  W:Scroll(parent)                              a clipped, wheel-scrolled area: :SetContentHeight(h),
	                                                :SetOffset(y), :GetOffset(), .content
	  W:Menu(anchor, items)                         context menu: items = { { text, glyph, onClick,
	                                                disabled, checked, sub = items } | "-" }
	  W:Money(copper [, size])                      text with the game's coin icons
	  W:Tip(owner, title, ...)                      a tooltip on hover
	  W:Popup(opts)                                 a dialog: { title, text, buttons = { { label, style, onClick } },
	                                                edit = { text, multiline, readOnly }, width } ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local W = NBG:Module("Widgets")
local Skin = NBG.Skin
local MEDIA = NBG.MEDIA
local WHITE = Skin.WHITE

local type, pairs, ipairs, floor, max, min = type, pairs, ipairs, math.floor, math.max, math.min

function W:Text(parent, size, role, kind, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	Skin:Font(fs, kind or "body", size or 12)
	Skin:Paint(fs, role or "text")
	fs:SetWordWrap(false)
	return fs
end

function W:SetGlyph(tex, name)
	local c = ns.GLYPHS and ns.GLYPHS[name]
	tex:SetTexture(MEDIA .. "Glyphs")
	if c then tex:SetTexCoord(c[1], c[2], c[3], c[4]) tex:Show() else tex:Hide() end
end

function W:Glyph(parent, name, size, role, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetSize(size or 14, size or 14)
	self:SetGlyph(t, name)
	if role then Skin:Paint(t, role) end
	return t
end

function W:Tip(owner, title, ...)
	local lines = { ... }
	owner:HookScript("OnEnter", function(self)
		local tt = _G.GameTooltip
		if not tt then return end
		tt:SetOwner(self, "ANCHOR_TOP")
		local t = type(title) == "function" and title() or title
		if not t then return end
		tt:SetText(t, 1, 0.86, 0.55)
		for _, l in ipairs(lines) do
			local s = type(l) == "function" and l() or l
			if s then tt:AddLine(s, 0.9, 0.9, 0.9, true) end
		end
		tt:Show()
	end)
	owner:HookScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
end

---------------------------------------------------------------------------------------------
-- buttons
---------------------------------------------------------------------------------------------
local STYLE = {
	dark = { top = "bgTop", bot = "bgAlt", edge = "border", text = "text" },
	gold = { top = "header", bot = "accentLo", edge = "accentLo", text = "ink" },
	red = { top = "negative", bot = "bg", edge = "negative", text = "text" },
}

local function ButtonLook(b)
	local st = STYLE[b.style] or STYLE.dark
	local hover = b.hover and b:IsEnabled()
	Skin:Gradient(b.fill, "VERTICAL", st.top, st.bot, b.style == "red" and 0.9 or 1, 1)
	Skin:Paint(b.edge, hover and "accent" or st.edge)
	Skin:Paint(b.label, st.text, { alpha = b:IsEnabled() and 1 or 0.45 })
	if b.icon then Skin:Paint(b.icon, st.text, { alpha = b:IsEnabled() and 1 or 0.45 }) end
	b.label:SetShadowColor(0, 0, 0, b.style == "gold" and 0 or 0.85)
end

function W:Button(parent, label, w, h, opts)
	opts = opts or {}
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w or 100, h or 26)
	b.style = opts.style or "dark"
	b.fill = b:CreateTexture(nil, "BACKGROUND")
	b.fill:SetAllPoints()
	b.edge = b:CreateTexture(nil, "BORDER")
	b.edge:SetAllPoints()
	Skin:Rounded(b.edge, true, 6)
	b.label = self:Text(b, opts.size or 11.5, "text", "medium")
	if opts.glyph then
		b.icon = self:Glyph(b, opts.glyph, floor((h or 26) * 0.5))
		b.icon:SetPoint("RIGHT", b.label, "LEFT", -5, 0)
	end
	function b:SetLabel(s)
		self.label:SetText(s or "")
		local wtxt = self.label:GetStringWidth() or 0
		local off = self.icon and (self.icon:GetWidth() + 5) / 2 or 0
		self.label:ClearAllPoints()
		self.label:SetPoint("CENTER", self, "CENTER", off, 0)
	end
	b:SetLabel(label)
	function b:SetStyle(s) self.style = s ButtonLook(self) end
	b:SetScript("OnEnter", function(self) self.hover = true ButtonLook(self) end)
	b:SetScript("OnLeave", function(self) self.hover = false ButtonLook(self) end)
	b:SetScript("OnDisable", function(self) ButtonLook(self) end)
	b:SetScript("OnEnable", function(self) ButtonLook(self) end)
	if opts.onClick then b:SetScript("OnClick", function(self, btn) NBG:Safe("button " .. tostring(label), opts.onClick, self, btn) end) end
	if opts.tip then self:Tip(b, opts.tip[1], select(2, unpack(opts.tip))) end
	Skin:OnChange(function() ButtonLook(b) end)
	ButtonLook(b)
	return b
end

function W:IconButton(parent, glyph, size, opts)
	opts = opts or {}
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size or 24, size or 24)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	Skin:Rounded(b.bg)
	b.edge = b:CreateTexture(nil, "BORDER")
	b.edge:SetAllPoints()
	Skin:Rounded(b.edge, true)
	b.icon = self:Glyph(b, glyph, floor((size or 24) * (opts.scale or 0.62)))
	b.icon:SetPoint("CENTER")
	b.role = opts.role or "textDim"
	local function Look()
		local on, hover = b.active, b.hover
		b.bg:SetShown(on or hover)
		b.edge:SetShown(on)
		Skin:Paint(b.bg, on and "rowSel" or "row", { alpha = on and 0.9 or 0.7 })
		Skin:Paint(b.edge, "accent", { alpha = 0.85 })
		Skin:Paint(b.icon, (on or hover) and "header" or b.role, { alpha = b:IsEnabled() and 1 or 0.4 })
	end
	b.Look = Look
	function b:SetActive(on) self.active = on and true or false Look() end
	function b:SetGlyph(name) W:SetGlyph(self.icon, name) end
	function b:SetBadge(text)
		if not text or text == "" or text == 0 then if self.badge then self.badge:Hide() end return end
		if not self.badge then
			local bd = CreateFrame("Frame", nil, self)
			bd:SetSize(16, 13)
			bd:SetPoint("TOPRIGHT", 5, 5)
			bd:SetFrameLevel(self:GetFrameLevel() + 3)
			bd.bg = bd:CreateTexture(nil, "BACKGROUND")
			bd.bg:SetAllPoints()
			bd.bg:SetTexture(MEDIA .. "Pill")
			Skin:Paint(bd.bg, "negative")
			bd.text = W:Text(bd, 8.5, "text", "bold")
			bd.text:SetPoint("CENTER", 0, 0)
			self.badge = bd
		end
		self.badge.text:SetText(tostring(text))
		self.badge:SetWidth(max(16, (self.badge.text:GetStringWidth() or 6) + 8))
		self.badge:Show()
	end
	b:SetScript("OnEnter", function(self) self.hover = true Look() end)
	b:SetScript("OnLeave", function(self) self.hover = false Look() end)
	b:HookScript("OnDisable", Look) b:HookScript("OnEnable", Look)
	if opts.onClick then b:SetScript("OnClick", function(self, btn) NBG:Safe("icon button " .. glyph, opts.onClick, self, btn) end) end
	if opts.tip then self:Tip(b, opts.tip[1], select(2, unpack(opts.tip))) end
	Skin:OnChange(Look)
	Look()
	return b
end

-- the "One bag | Insight" switch: a pill with two (or more) segments
function W:Pill(parent, labels, onSelect)
	local p = CreateFrame("Frame", nil, parent)
	p.bg = p:CreateTexture(nil, "BACKGROUND")
	p.bg:SetAllPoints()
	p.bg:SetTexture(MEDIA .. "Pill")
	if p.bg.SetTextureSliceMargins then pcall(p.bg.SetTextureSliceMargins, p.bg, 16, 16, 16, 16) end
	Skin:Paint(p.bg, "inset")
	p.edge = p:CreateTexture(nil, "BORDER")
	p.edge:SetAllPoints()
	p.edge:SetTexture(MEDIA .. "PillEdge")
	if p.edge.SetTextureSliceMargins then pcall(p.edge.SetTextureSliceMargins, p.edge, 16, 16, 16, 16) end
	Skin:Paint(p.edge, "border")
	p.segs = {}
	local x, h = 2, 24
	for i, label in ipairs(labels) do
		local s = CreateFrame("Button", nil, p)
		s.text = W:Text(s, 11, "textDim", "medium")
		s.text:SetPoint("CENTER")
		s.text:SetText(label)
		local w = floor((s.text:GetStringWidth() or 40) + 26)
		s:SetSize(w, h - 4)
		s:SetPoint("LEFT", x, 0)
		s.fill = s:CreateTexture(nil, "ARTWORK")
		s.fill:SetAllPoints()
		s.fill:SetTexture(MEDIA .. "Pill")
		if s.fill.SetTextureSliceMargins then pcall(s.fill.SetTextureSliceMargins, s.fill, 16, 16, 16, 16) end
		s:SetScript("OnClick", function() if p.value ~= i then p:SetValue(i) if onSelect then NBG:Safe("pill", onSelect, i) end end end)
		x = x + w
		p.segs[i] = s
	end
	p:SetSize(x + 2, h)
	function p:SetValue(i)
		self.value = i
		for k, s in ipairs(self.segs) do
			s.fill:SetShown(k == i)
			Skin:Paint(s.fill, "accent")
			Skin:Paint(s.text, k == i and "ink" or "textDim")
			Skin:Font(s.text, k == i and "bold" or "medium", 11)
			s.text:SetShadowColor(0, 0, 0, k == i and 0 or 0.85)
		end
	end
	Skin:OnChange(function() if p.value then p:SetValue(p.value) end end)
	return p
end

function W:Chip(parent, label, glyph, role, onToggle)
	local c = CreateFrame("Button", nil, parent)
	c:SetHeight(20)
	c.bg = c:CreateTexture(nil, "BACKGROUND")
	c.bg:SetAllPoints()
	c.bg:SetTexture(MEDIA .. "Pill")
	if c.bg.SetTextureSliceMargins then pcall(c.bg.SetTextureSliceMargins, c.bg, 10, 10, 10, 10) end
	c.edge = c:CreateTexture(nil, "BORDER")
	c.edge:SetAllPoints()
	c.edge:SetTexture(MEDIA .. "PillEdge")
	if c.edge.SetTextureSliceMargins then pcall(c.edge.SetTextureSliceMargins, c.edge, 10, 10, 10, 10) end
	c.role = role or "accent"
	local x = 10
	if glyph then
		c.icon = W:Glyph(c, glyph, 11)
		c.icon:SetPoint("LEFT", 9, 0)
		x = 24
	end
	c.text = W:Text(c, 10.5, "textDim", "medium")
	c.text:SetPoint("LEFT", x, 0)
	function c:SetLabel(s)
		self.text:SetText(s)
		self:SetWidth(floor((self.text:GetStringWidth() or 30) + x + 10))
	end
	c:SetLabel(label)
	local function Look()
		local on = c.on
		Skin:Paint(c.bg, on and c.role or "inset", { alpha = on and 0.28 or 0.8 })
		Skin:Paint(c.edge, on and c.role or "border", { alpha = on and 0.9 or 1 })
		Skin:Paint(c.text, on and "text" or "textDim")
		if c.icon then Skin:Paint(c.icon, on and c.role or "faint") end
	end
	function c:SetOn(on) self.on = on and true or false Look() end
	c:SetScript("OnClick", function(self)
		self:SetOn(not self.on)
		if onToggle then NBG:Safe("chip", onToggle, self.on, self) end
	end)
	Skin:OnChange(Look)
	Look()
	return c
end

---------------------------------------------------------------------------------------------
-- settings controls
---------------------------------------------------------------------------------------------
function W:Check(parent, label, get, set, sub)
	local c = CreateFrame("Button", nil, parent)
	c:SetSize(260, sub and 34 or 20)
	c.box = c:CreateTexture(nil, "BACKGROUND")
	c.box:SetSize(16, 16)
	c.box:SetPoint("TOPLEFT", 0, -2)
	Skin:Rounded(c.box)
	c.edge = c:CreateTexture(nil, "BORDER")
	c.edge:SetAllPoints(c.box)
	Skin:Rounded(c.edge, true)
	c.mark = W:Glyph(c, "check", 12)
	c.mark:SetPoint("CENTER", c.box, "CENTER")
	c.text = W:Text(c, 11.5, "text")
	c.text:SetPoint("LEFT", c.box, "RIGHT", 8, 0)
	c.text:SetText(label)
	if sub then
		c.sub = W:Text(c, 9.5, "faint")
		c.sub:SetPoint("TOPLEFT", c.text, "BOTTOMLEFT", 0, -3)
		c.sub:SetText(sub)
	end
	function c:Refresh()
		local on = get() and true or false
		self.checked = on
		self.mark:SetShown(on)
		Skin:Paint(self.box, "inset")
		Skin:Paint(self.edge, on and "accent" or "border")
		Skin:Paint(self.mark, "header")
	end
	function c:GetChecked() return self.checked end
	c:SetScript("OnClick", function(self)
		NBG:Safe("setting " .. label, set, not self.checked)
		self:Refresh()
	end)
	Skin:OnChange(function() c:Refresh() end)
	c:Refresh()
	return c
end

function W:Slider(parent, label, lo, hi, step, get, set, fmt)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(260, 40)
	f.text = W:Text(f, 11.5, "text")
	f.text:SetPoint("TOPLEFT", 0, 0)
	f.text:SetText(label)
	f.value = W:Text(f, 11, "header", "medium")
	f.value:SetPoint("TOPRIGHT", 0, 0)
	local s = CreateFrame("Slider", nil, f)
	s:SetOrientation("HORIZONTAL")
	s:SetPoint("TOPLEFT", 0, -20) s:SetPoint("TOPRIGHT", 0, -20)
	s:SetHeight(14)
	s:SetMinMaxValues(lo, hi)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT") track:SetPoint("RIGHT") track:SetHeight(4)
	track:SetTexture(MEDIA .. "Pill")
	Skin:Paint(track, "inset")
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture(MEDIA .. "Glow")
	thumb:SetSize(16, 16)
	Skin:Paint(thumb, "accent")
	s:SetThumbTexture(thumb)
	f.slider = s
	local busy = false
	local function Show(v) f.value:SetText((fmt or "%s"):format(v)) end
	s:SetScript("OnValueChanged", function(_, v, user)
		v = floor(v / step + 0.5) * step
		Show(v)
		if busy then return end
		NBG:Debounce("slider" .. label, 0.05, function() NBG:Safe("setting " .. label, set, v) end)
	end)
	function f:Refresh()
		busy = true
		local v = get()
		s:SetValue(v or lo)
		Show(v or lo)
		busy = false
	end
	f:Refresh()
	return f
end

-- a list menu attached under a control (dropdowns) or at the cursor (context menus)
local menu
local function MenuFrame()
	if menu then return menu end
	menu = CreateFrame("Frame", "NetherBagsMenu", UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	Skin:Panel(menu)
	menu.rows = {}
	menu:Hide()
	menu.closer = CreateFrame("Button", nil, UIParent)
	menu.closer:SetAllPoints(UIParent)
	menu.closer:SetFrameStrata("FULLSCREEN")
	menu.closer:Hide()
	menu.closer:RegisterForClicks("AnyUp")
	menu.closer:SetScript("OnClick", function() menu:Hide() end)
	menu:SetScript("OnHide", function() menu.closer:Hide() if menu.sub then menu.sub:Hide() end end)
	return menu
end

local function MenuRow(m, i)
	local r = m.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, m)
	r:SetHeight(22)
	r.hl = r:CreateTexture(nil, "BACKGROUND")
	r.hl:SetAllPoints()
	r.hl:SetTexture(MEDIA .. "FadeR")
	r.hl:Hide()
	r.icon = W:Glyph(r, "star", 12)
	r.icon:SetPoint("LEFT", 10, 0)
	r.text = W:Text(r, 11.5, "text")
	r.text:SetPoint("LEFT", 30, 0)
	r.arrow = W:Glyph(r, "chev_r", 9, "textDim")
	r.arrow:SetPoint("RIGHT", -8, 0)
	r.line = r:CreateTexture(nil, "ARTWORK")
	r.line:SetTexture(MEDIA .. "Fade")
	r.line:SetPoint("LEFT", 6, 0) r.line:SetPoint("RIGHT", -6, 0) r.line:SetHeight(1)
	r:SetScript("OnEnter", function(self)
		if self.sep then return end
		self.hl:Show() Skin:Paint(self.hl, "rowHover")
		if self.subItems then W:Menu(self, self.subItems, true) elseif m.sub and m ~= m.sub then m.sub:Hide() end
	end)
	r:SetScript("OnLeave", function(self) self.hl:Hide() end)
	m.rows[i] = r
	return r
end

function W:Menu(anchor, items, isSub)
	local m = MenuFrame()
	if isSub then
		if not m.sub then
			local s = CreateFrame("Frame", nil, m)
			s:SetFrameStrata("FULLSCREEN_DIALOG")
			s:SetFrameLevel(m:GetFrameLevel() + 10)
			s:SetClampedToScreen(true)
			s:EnableMouse(true)
			Skin:Panel(s)
			s.rows = {}
			m.sub = s
		end
		m = m.sub
	end
	local width, y = 160, -5
	for _, r in ipairs(m.rows) do r:Hide() end
	for i, it in ipairs(items) do
		local r = MenuRow(m, i)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 3, y) r:SetPoint("TOPRIGHT", -3, y)
		if it == "-" then
			r.sep = true
			r:SetHeight(9)
			r.text:SetText("") r.icon:Hide() r.arrow:Hide()
			r.line:Show()
			Skin:Paint(r.line, "border")
			r:SetScript("OnClick", nil)
			y = y - 9
		else
			r.sep = false
			r:SetHeight(22)
			r.line:Hide()
			r.text:SetText(it.text or "")
			Skin:Paint(r.text, it.disabled and "faint" or (it.color or "text"))
			if it.checked ~= nil then
				W:SetGlyph(r.icon, it.checked and "check" or "x")
				r.icon:SetShown(it.checked and true or false)
				Skin:Paint(r.icon, "header")
			elseif it.glyph then
				W:SetGlyph(r.icon, it.glyph) r.icon:Show()
				Skin:Paint(r.icon, it.glyphRole or "accent")
			else
				r.icon:Hide()
			end
			r.subItems = it.sub
			r.arrow:SetShown(it.sub ~= nil)
			r:SetScript("OnClick", function()
				if it.disabled or it.sub then return end
				MenuFrame():Hide()
				if it.onClick then NBG:Safe("menu " .. tostring(it.text), it.onClick) end
			end)
			width = max(width, (r.text:GetStringWidth() or 100) + 56)
			y = y - 22
		end
		r:Show()
	end
	m:SetSize(width, -y + 5)
	m:ClearAllPoints()
	if isSub then
		m:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 4)
	elseif anchor == "cursor" then
		local x, cy = GetCursorPosition()
		local s = UIParent:GetEffectiveScale()
		m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 2, cy / s - 2)
	else
		m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
		m:SetWidth(max(width, anchor:GetWidth()))
	end
	m:Show()
	if not isSub then
		MenuFrame().closer:Show()
		if MenuFrame().sub then MenuFrame().sub:Hide() end
	end
	return m
end

function W:CloseMenu() if menu then menu:Hide() end end

function W:Dropdown(parent, w, options, get, set)
	local d = CreateFrame("Button", nil, parent)
	d:SetSize(w or 160, 24)
	d.bg = d:CreateTexture(nil, "BACKGROUND")
	d.bg:SetAllPoints()
	Skin:Rounded(d.bg)
	Skin:Paint(d.bg, "inset")
	d.edge = d:CreateTexture(nil, "BORDER")
	d.edge:SetAllPoints()
	Skin:Rounded(d.edge, true)
	Skin:Paint(d.edge, "border")
	d.text = W:Text(d, 11.5, "text")
	d.text:SetPoint("LEFT", 10, 0)
	d.text:SetPoint("RIGHT", -24, 0)
	d.text:SetJustifyH("LEFT")
	d.arrow = W:Glyph(d, "chev_d", 10, "textDim")
	d.arrow:SetPoint("RIGHT", -9, 0)
	function d:Refresh()
		local v = get()
		local label = tostring(v or "")
		for _, o in ipairs(options()) do if o.value == v then label = o.label if o.color then Skin:Paint(self.text, o.color) end end end
		self.text:SetText(label)
	end
	d:SetScript("OnClick", function(self)
		local items = {}
		local cur = get()
		for _, o in ipairs(options()) do
			items[#items + 1] = { text = o.label, checked = o.value == cur, color = o.color, onClick = function() NBG:Safe("dropdown", set, o.value) self:Refresh() end }
		end
		W:Menu(self, items)
	end)
	d:SetScript("OnEnter", function(self) Skin:Paint(self.edge, "accent") end)
	d:SetScript("OnLeave", function(self) Skin:Paint(self.edge, "border") end)
	d:Refresh()
	return d
end

function W:Edit(parent, w, h, hint, opts)
	opts = opts or {}
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(w or 160, h or 24)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	Skin:Rounded(f.bg)
	Skin:Paint(f.bg, "inset")
	f.edge = f:CreateTexture(nil, "BORDER")
	f.edge:SetAllPoints()
	Skin:Rounded(f.edge, true)
	Skin:Paint(f.edge, "border")
	local e
	if opts.multiline then
		local sf = CreateFrame("ScrollFrame", nil, f)
		sf:SetPoint("TOPLEFT", 8, -6) sf:SetPoint("BOTTOMRIGHT", -8, 6)
		e = CreateFrame("EditBox", nil, sf)
		e:SetMultiLine(true)
		e:SetWidth((w or 160) - 16)
		sf:SetScrollChild(e)
		sf:EnableMouseWheel(true)
		sf:SetScript("OnMouseWheel", function(self, d)
			local v = (self:GetVerticalScroll() or 0) - d * 20
			local m = self:GetVerticalScrollRange() or 0
			self:SetVerticalScroll(max(0, min(m, v)))
		end)
		f:EnableMouse(true)
		f:SetScript("OnMouseDown", function() e:SetFocus() end)
		f.scroll = sf
	else
		e = CreateFrame("EditBox", nil, f)
		e:SetPoint("TOPLEFT", opts.inset or 10, 0) e:SetPoint("BOTTOMRIGHT", -8, 0)
	end
	e:SetAutoFocus(false)
	Skin:Font(e, "body", opts.size or 11.5)
	Skin:Paint(e, "text")
	if opts.numeric and e.SetNumeric then e:SetNumeric(true) end
	if opts.maxLetters and e.SetMaxLetters then e:SetMaxLetters(opts.maxLetters) end
	f.hint = W:Text(f, 11, "faint")
	-- the hint stays inside the box: it ends at the box's right edge and is cut short ("…") there
	f.hint:SetPoint("LEFT", opts.inset or 10, 0)
	f.hint:SetPoint("RIGHT", -(opts.insetRight or 10), 0)
	f.hint:SetJustifyH("LEFT")
	f.hint:SetWordWrap(false)
	if opts.multiline then f.hint:ClearAllPoints() f.hint:SetPoint("TOPLEFT", 9, -7) f.hint:SetPoint("TOPRIGHT", -9, -7) end
	f.hint:SetText(hint or "")
	local function Hint() f.hint:SetShown((e:GetText() or "") == "" and not e:HasFocus()) end
	e:SetScript("OnEditFocusGained", function() Skin:Paint(f.edge, "accent") Hint() end)
	e:SetScript("OnEditFocusLost", function() Skin:Paint(f.edge, "border") Hint() end)
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() if opts.onEscape then opts.onEscape(self) end end)
	e:SetScript("OnEnterPressed", function(self)
		if opts.multiline and not opts.onEnter then self:Insert("\n") return end
		self:ClearFocus()
		if opts.onEnter then NBG:Safe("edit enter", opts.onEnter, self:GetText(), self) end
	end)
	e:SetScript("OnTextChanged", function(self, user)
		Hint()
		if opts.onChange then NBG:Safe("edit change", opts.onChange, self:GetText(), user, self) end
	end)
	f.edit = e
	function f:SetText(t) e:SetText(t or "") Hint() end
	function f:GetText() return e:GetText() end
	Hint()
	return f
end

function W:Search(parent, w, h, hint, onChange)
	local f = self:Edit(parent, w, h, hint, { inset = 28, insetRight = 26, onChange = function(t, user) if onChange then onChange(t, user) end end,
		onEscape = function(e) e:SetText("") end })
	f.bg:SetTexture(MEDIA .. "Pill")
	if f.bg.SetTextureSliceMargins then pcall(f.bg.SetTextureSliceMargins, f.bg, 16, 16, 16, 16) end
	f.edge:SetTexture(MEDIA .. "PillEdge")
	if f.edge.SetTextureSliceMargins then pcall(f.edge.SetTextureSliceMargins, f.edge, 16, 16, 16, 16) end
	f.icon = self:Glyph(f, "search", 12, "textDim")
	f.icon:SetPoint("LEFT", 10, 0)
	f.clear = self:IconButton(f, "x", 18, { onClick = function() f:SetText("") f.edit:ClearFocus() end, scale = 0.5 })
	f.clear:SetPoint("RIGHT", -6, 0)
	f.clear:Hide()
	f.edit:HookScript("OnTextChanged", function(self) f.clear:SetShown((self:GetText() or "") ~= "") end)
	-- a long hint (with its search tips) while there is room for it, a short one when the box is narrow
	f.longHint, f.shortHint = hint or "", L["Search…"]
	local function FitHint()
		-- (the long hint needs about 380 px; under 300 of room its tips would be cut off mid-way)
		local room = (f:GetWidth() or 0) - 28 - 26
		f.hint:SetText(room < 300 and f.shortHint or f.longHint)
	end
	f:HookScript("OnSizeChanged", FitHint)
	FitHint()
	return f
end

---------------------------------------------------------------------------------------------
-- scroll area: clipped content, mouse wheel, a thin gold thumb
---------------------------------------------------------------------------------------------
function W:Scroll(parent)
	local s = CreateFrame("Frame", nil, parent)
	if s.SetClipsChildren then s:SetClipsChildren(true) end
	s.content = CreateFrame("Frame", nil, s)
	s.content:SetPoint("TOPLEFT") s.content:SetPoint("TOPRIGHT", -10, 0)
	s.content:SetHeight(1)
	s.track = s:CreateTexture(nil, "BACKGROUND")
	s.track:SetPoint("TOPRIGHT", -2, -2) s.track:SetPoint("BOTTOMRIGHT", -2, 2) s.track:SetWidth(4)
	s.track:SetTexture(MEDIA .. "Pill")
	Skin:Paint(s.track, "inset")
	s.thumb = CreateFrame("Frame", nil, s)
	s.thumb:SetWidth(4)
	s.thumb.t = s.thumb:CreateTexture(nil, "ARTWORK")
	s.thumb.t:SetAllPoints()
	s.thumb.t:SetTexture(MEDIA .. "Pill")
	Skin:Paint(s.thumb.t, "accent")
	s.offset, s.contentH = 0, 0
	local function Layout()
		local h = s:GetHeight() or 1
		local maxo = max(0, s.contentH - h)
		s.offset = max(0, min(maxo, s.offset))
		s.content:ClearAllPoints()
		s.content:SetPoint("TOPLEFT", 0, s.offset) s.content:SetPoint("TOPRIGHT", -10, s.offset)
		local show = maxo > 0
		s.track:SetShown(show) s.thumb:SetShown(show)
		if show then
			local th = max(20, h * h / s.contentH)
			s.thumb:SetHeight(th)
			s.thumb:ClearAllPoints()
			s.thumb:SetPoint("TOPRIGHT", -2, -2 - (h - th - 4) * (s.offset / maxo))
		end
		if s.onScroll then NBG:Safe("scroll", s.onScroll, s.offset) end
	end
	s.Layout = Layout
	function s:SetContentHeight(h) self.contentH = h or 0 self.content:SetHeight(max(1, h or 1)) Layout() end
	function s:SetOffset(o) self.offset = o or 0 Layout() end
	function s:GetOffset() return self.offset end
	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(self, d) self.offset = self.offset - d * (self.step or 40) Layout() end)
	s:SetScript("OnSizeChanged", Layout)
	return s
end

---------------------------------------------------------------------------------------------
-- money: the game's coin icons when it has them
---------------------------------------------------------------------------------------------
function W:Money(copper, size)
	copper = math.max(0, floor(tonumber(copper) or 0))
	local f = _G.GetMoneyString or _G.GetCoinTextureString
	if f then
		local ok, s = pcall(f, copper, true)
		if ok and type(s) == "string" and s ~= "" then return s end
	end
	local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
	local out = {}
	if g > 0 then out[#out + 1] = ("|cfff6c846%d|rg"):format(g) end
	if g > 0 or s > 0 then out[#out + 1] = ("|cffc8ced6%d|rs"):format(s) end
	out[#out + 1] = ("|cffd68048%d|rc"):format(c)
	return table.concat(out, " ")
end

---------------------------------------------------------------------------------------------
-- dialogs
---------------------------------------------------------------------------------------------
local popup
-- the dialog's contents sit on their own layer, above the window art (Skin:Window's layers share
-- the dialog's frame level), and are measured again a moment after showing (a font file loading
-- in that moment measures as nothing)
local function PopupLayout(p, opts)
	local width = p:GetWidth()
	local c = p.content
	c.text:SetWidth(width - 86)
	c.text:SetText(opts.text or "")
	local th = c.text:GetStringHeight() or 0
	if opts.text and opts.text ~= "" and th < 12 then th = 14 * (select(2, (opts.text):gsub("\n", "")) + 1) end
	local y = 42 + th + 14
	if c.edit and opts.edit then
		c.edit:ClearAllPoints()
		c.edit:SetPoint("TOPLEFT", 20, -y)
		y = y + (opts.edit.height or 90) + 12
	end
	p:SetHeight(math.max(110, y + 54))
end

function W:Popup(opts)
	if not popup then
		popup = CreateFrame("Frame", "NetherBagsPopup", UIParent)
		popup:SetFrameStrata("DIALOG")
		popup:SetClampedToScreen(true)
		popup:EnableMouse(true)
		popup:SetMovable(true)
		popup:RegisterForDrag("LeftButton")
		popup:SetScript("OnDragStart", popup.StartMoving)
		popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
		Skin:Window(popup)
		local c = CreateFrame("Frame", nil, popup)
		c:SetAllPoints()
		c:SetFrameLevel(popup:GetFrameLevel() + 10)
		popup.content = c
		c.icon = c:CreateTexture(nil, "ARTWORK")
		c.icon:SetTexture(MEDIA .. "Logo")
		c.icon:SetSize(44, 44)
		c.icon:SetPoint("TOPLEFT", 14, -12)
		c.title = W:Text(c, 16, "header", "title")
		c.title:SetPoint("TOPLEFT", 66, -18)
		c.text = W:Text(c, 11.5, "text")
		c.text:SetPoint("TOPLEFT", 66, -42)
		c.text:SetJustifyH("LEFT") c.text:SetJustifyV("TOP")
		c.text:SetWordWrap(true)
		popup.title, popup.text = c.title, c.text
		popup.close = W:IconButton(c, "x", 20, { onClick = function() popup:Hide() end })
		popup.close:SetPoint("TOPRIGHT", -8, -8)
		popup.buttons = {}
		popup:Hide()
		if _G.UISpecialFrames then table.insert(UISpecialFrames, "NetherBagsPopup") end
	end
	local p = popup
	local c = p.content
	local width = opts.width or 420
	p:SetWidth(width)
	c.title:SetText(opts.title or "NetherBags")
	if c.edit then c.edit:Hide() end
	if opts.edit then
		if not c.edit then c.edit = W:Edit(c, width - 40, 90, "", { multiline = true, size = 10.5 }) end
		c.edit:SetSize(width - 40, opts.edit.height or 90)
		c.edit.edit:SetWidth(width - 56)
		c.edit:SetText(opts.edit.text or "")
		c.edit:Show()
	end
	p.edit = opts.edit and c.edit or nil
	for _, b in ipairs(p.buttons) do b:Hide() end
	local x = width - 16
	for i = #(opts.buttons or {}), 1, -1 do
		local bd = opts.buttons[i]
		local b = p.buttons[i]
		if not b then b = W:Button(c, "", 110, 26) p.buttons[i] = b end
		b:SetStyle(bd.style or "dark")
		b:SetLabel(bd.label)
		local bw = math.max(90, (b.label:GetStringWidth() or 60) + 30)
		b:SetWidth(bw)
		b:ClearAllPoints()
		b:SetPoint("BOTTOMRIGHT", p, "BOTTOMLEFT", x, 14)
		x = x - bw - 8
		b:SetScript("OnClick", function()
			-- a button's onClick returns true to keep the dialog open (e.g. a refused import)
			local ok, keep = true, false
			if bd.onClick then ok, keep = NBG:Safe("popup " .. tostring(bd.label), bd.onClick, p.edit and p.edit:GetText()) end
			if not (ok and keep == true) then p:Hide() end
		end)
		b:Show()
	end
	PopupLayout(p, opts)
	p:ClearAllPoints()
	p:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	p:Show()
	if opts.edit and opts.edit.select then
		c.edit.edit:SetFocus()
		c.edit.edit:HighlightText()
	end
	local token = {}
	p.token = token
	NBG:After(0.05, function() if p.token == token and p:IsShown() then Skin:Redraw() PopupLayout(p, opts) end end)
	return p
end
