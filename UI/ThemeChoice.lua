--[[ NetherBags - UI/ThemeChoice.lua
	The theme question, asked once when NetherUI is installed (and any time with /nbags theme):
	two cards side by side, "Follow NetherUI" and "Keep NetherBags' look", each with a live preview
	drawn in that theme's own colours and fonts (NetherUI's come from NetherUI itself), what the
	choice means, and its button. Clicking anywhere on a card chooses it. ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local TC = NBG:Module("ThemeChoice")
local Skin = NBG.Skin
local W = NBG.Widgets
local MEDIA = NBG.MEDIA
local WHITE = Skin.WHITE

local WIDTH, PAD, GAP = 600, 20, 14
local CARD_W = (WIDTH - PAD * 2 - GAP) / 2

local CHOICES = {
	{
		id = "netherui", title = L["Follow NetherUI"], tag = L["Matches your interface"], style = "gold",
		points = {
			L["NetherUI's colours, fonts and window art on every NetherBags window and tab."],
			L["Changes with you whenever you switch NetherUI's theme."],
			L["Your bags, bank and guild bank look like part of NetherUI."],
		},
	},
	{
		id = "netherbags", title = L["Keep NetherBags' look"], tag = L["The default"], style = "dark",
		points = {
			L["NetherBags' own midnight-and-gold look, made for your bags."],
			L["Stays the same whatever theme NetherUI is wearing."],
			L["Its own fonts and window art, with quality colours on every item."],
		},
	},
}

-- the preview: a small bag window drawn in one theme's colours and fonts
local SLOTS = { { "sword", 4 }, { "potion", 1 }, { "gem", 3 }, { "ring", 2 }, { "helm", 4 }, { "ore", 0 } }

local function Preview(parent, w, h)
	local pv = CreateFrame("Frame", nil, parent)
	pv:SetSize(w, h)
	pv.bg = pv:CreateTexture(nil, "BACKGROUND")
	pv.bg:SetAllPoints()
	pv.bg:SetTexture(WHITE)
	pv.edge = pv:CreateTexture(nil, "BORDER")
	pv.edge:SetAllPoints()
	Skin:Rounded(pv.edge, true, 6)
	pv.title = pv:CreateFontString(nil, "OVERLAY")
	pv.title:SetPoint("TOPLEFT", 10, -7)
	pv.line = pv:CreateTexture(nil, "ARTWORK")
	pv.line:SetTexture(WHITE)
	pv.line:SetSize(30, 2)
	pv.line:SetPoint("TOPLEFT", pv.title, "BOTTOMLEFT", 0, -3)
	pv.money = pv:CreateFontString(nil, "OVERLAY")
	pv.money:SetPoint("TOPRIGHT", -10, -9)
	pv.slots = {}
	local size = 24
	for i, sd in ipairs(SLOTS) do
		local s = CreateFrame("Frame", nil, pv)
		s:SetSize(size, size)
		s:SetPoint("BOTTOMLEFT", 10 + (i - 1) * (size + 5), 9)
		s.fill = s:CreateTexture(nil, "BACKGROUND")
		s.fill:SetAllPoints()
		s.fill:SetTexture(WHITE)
		s.edge = s:CreateTexture(nil, "BORDER")
		s.edge:SetAllPoints()
		Skin:Rounded(s.edge, true, 4)
		s.icon = W:Glyph(s, sd[1], 14)
		s.icon:SetPoint("CENTER")
		s.quality = sd[2]
		pv.slots[i] = s
	end
	pv.rows = {}
	for i = 1, 2 do
		local r = pv:CreateTexture(nil, "ARTWORK")
		r:SetTexture(WHITE)
		r:SetSize(w - (10 + #SLOTS * (size + 5)) - 14, 8)
		r:SetPoint("BOTTOMRIGHT", -10, 11 + (i - 1) * 12)
		pv.rows[i] = r
	end
	return pv
end

local function PaintPreview(pv, id)
	local function C(role) return Skin:ColorOf(id, role) end
	local r1, g1, b1 = C("bgTop")
	local r2, g2, b2 = C("bg")
	Skin.SetGrad(pv.bg, "VERTICAL", r2, g2, b2, 1, r1, g1, b1, 1)
	pv.edge:SetVertexColor(C("border"))
	pcall(pv.title.SetFont, pv.title, Skin:FontOf(id, "title"), 14, "")
	pv.title:SetText(L["Bags"])
	pv.title:SetTextColor(C("header"))
	pv.line:SetVertexColor(C("accent"))
	pcall(pv.money.SetFont, pv.money, Skin:FontOf(id, "bold"), 11, "")
	pv.money:SetText("128g")
	pv.money:SetTextColor(C("accent"))
	for _, s in ipairs(pv.slots) do
		s.fill:SetVertexColor(C("inset"))
		local qr, qg, qb = Skin:Quality(s.quality)
		s.edge:SetVertexColor(qr or 1, qg or 1, qb or 1, 1)
		s.icon:SetVertexColor(C("text"))
	end
	local rr, rg, rb, ra = C("row")
	pv.rows[1]:SetVertexColor(rr, rg, rb, math.max(ra, 0.6))
	pv.rows[2]:SetVertexColor(C("accent2"))
	pv.rows[2]:SetWidth(pv.rows[1]:GetWidth() * 0.6)
end

local function CardLook(card)
	local hover = card.hover
	Skin:Paint(card.edge, hover and "accent" or "border", { alpha = hover and 1 or 0.9 })
	Skin:Paint(card.fill, hover and "bgTop" or "bgAlt")
	Skin:Paint(card.glow, "accent", { alpha = hover and 0.10 or 0 })
end

local function Card(parent, def, onPick)
	local card = CreateFrame("Button", nil, parent)
	card:SetWidth(CARD_W)
	card.fill = card:CreateTexture(nil, "BACKGROUND")
	card.fill:SetAllPoints()
	Skin:Rounded(card.fill)
	card.glow = card:CreateTexture(nil, "BORDER")
	card.glow:SetAllPoints()
	Skin:Rounded(card.glow)
	card.edge = card:CreateTexture(nil, "ARTWORK")
	card.edge:SetAllPoints()
	Skin:Rounded(card.edge, true)

	card.preview = Preview(card, CARD_W - 24, 66)
	card.preview:SetPoint("TOP", 0, -12)

	card.title = W:Text(card, 15, "header", "bold")
	card.title:SetPoint("TOPLEFT", card.preview, "BOTTOMLEFT", 0, -12)
	card.title:SetText(def.title)
	card.tag = W:Text(card, 10, "accent2", "medium")
	card.tag:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
	card.tag:SetText(def.tag)

	card.points = {}
	for i, txt in ipairs(def.points) do
		local g = W:Glyph(card, "check", 11, "accent")
		local t = W:Text(card, 11.5, "text")
		t:SetWordWrap(true)
		t:SetJustifyH("LEFT") t:SetJustifyV("TOP")
		t:SetWidth(CARD_W - 24 - 18)
		t:SetText(txt)
		card.points[i] = { glyph = g, text = t }
	end

	card.button = W:Button(card, def.title, CARD_W - 24, 30, { style = def.style, size = 12,
		onClick = function() onPick(def.id) end })
	card.button:SetPoint("BOTTOM", 0, 12)

	card:SetScript("OnClick", function() NBG:Safe("theme card", onPick, def.id) end)
	card:SetScript("OnEnter", function(self) self.hover = true CardLook(self) end)
	card:SetScript("OnLeave", function(self) if not self:IsMouseOver() then self.hover = false CardLook(self) end end)
	card.button:HookScript("OnEnter", function() card.hover = true CardLook(card) end)
	card.button:HookScript("OnLeave", function() if not card:IsMouseOver() then card.hover = false CardLook(card) end end)
	Skin:OnChange(function() CardLook(card) end)
	CardLook(card)
	card.def = def
	return card
end

-- the card's natural height (preview, title, tag, the points, the button)
local function CardHeight(card)
	local y = 12 + 66 + 12 + (card.title:GetStringHeight() or 16) + 3 + (card.tag:GetStringHeight() or 12) + 12
	for i, p in ipairs(card.points) do
		p.text:ClearAllPoints()
		p.text:SetPoint("TOPLEFT", card, "TOPLEFT", 12 + 18, -y)
		p.glyph:ClearAllPoints()
		p.glyph:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -y - 2)
		local h = p.text:GetStringHeight() or 0
		if h < 10 then h = 30 end   -- measured before its font loaded: two lines, until the re-layout
		y = y + h + (i < #card.points and 8 or 0)
	end
	return y + 16 + 30 + 12
end

local frame
local function Build()
	local f = CreateFrame("Frame", "NetherBagsThemeChoice", UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetWidth(WIDTH)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	Skin:Window(f)
	local c = CreateFrame("Frame", nil, f)
	c:SetAllPoints()
	c:SetFrameLevel(f:GetFrameLevel() + 10)
	f.content = c

	c.logo = c:CreateTexture(nil, "ARTWORK")
	c.logo:SetTexture(MEDIA .. "Logo")
	c.logo:SetSize(56, 56)
	c.logo:SetPoint("TOPLEFT", PAD - 4, -14)
	c.title = W:Text(c, 19, "header", "title")
	c.title:SetPoint("TOPLEFT", PAD + 62, -20)
	c.title:SetText(L["Welcome to NetherBags"])
	c.sub = W:Text(c, 12, "textDim")
	c.sub:SetWordWrap(true)
	c.sub:SetJustifyH("LEFT") c.sub:SetJustifyV("TOP")
	c.sub:SetWidth(WIDTH - PAD * 2 - 62 - 24)
	c.sub:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -5)
	c.sub:SetText(L["NetherUI is installed, so NetherBags can wear its theme. Choose the look you'd like for your bags, bank and guild bank."])
	c.close = W:IconButton(c, "x", 20, { onClick = function() f:Hide() end, tip = { L["Ask me next time"] } })
	c.close:SetPoint("TOPRIGHT", -8, -8)

	c.rule = c:CreateTexture(nil, "ARTWORK")
	c.rule:SetTexture(WHITE)
	c.rule:SetHeight(1)
	Skin:Paint(c.rule, "accentLo", { alpha = 0.45 })
	c.diamond = W:Glyph(c, "gem", 12, "accent")

	local function Pick(id) TC:Choose(id) end
	c.cards = {}
	for i, def in ipairs(CHOICES) do c.cards[i] = Card(c, def, Pick) end

	c.foot = W:Text(c, 10.5, "faint")
	c.foot:SetText(L["You can switch any time: Settings > General > Theme, or type /nbags theme."])
	c.footIcon = W:Glyph(c, "gear", 12, "faint")
	c.footIcon:SetPoint("RIGHT", c.foot, "LEFT", -5, 0)

	f:Hide()
	if _G.UISpecialFrames then table.insert(UISpecialFrames, "NetherBagsThemeChoice") end
	return f
end

local function Layout()
	local c = frame.content
	local headH = 20 + (c.title:GetStringHeight() or 22) + 5 + math.max(c.sub:GetStringHeight() or 0, 16)
	local ruleY = math.max(14 + 56, headH) + 14
	c.rule:ClearAllPoints()
	c.rule:SetPoint("TOPLEFT", PAD, -ruleY)
	c.rule:SetPoint("TOPRIGHT", -PAD, -ruleY)
	c.diamond:ClearAllPoints()
	c.diamond:SetPoint("CENTER", c.rule, "CENTER", 0, 0)
	local cardY = ruleY + 16
	local ch = 0
	for _, card in ipairs(c.cards) do
		PaintPreview(card.preview, card.def.id)
		ch = math.max(ch, CardHeight(card))
	end
	for i, card in ipairs(c.cards) do
		card:SetHeight(ch)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", PAD + (i - 1) * (CARD_W + GAP), -cardY)
	end
	c.foot:ClearAllPoints()
	c.foot:SetPoint("BOTTOM", 8, 16)
	frame:SetHeight(cardY + ch + 16 + 14 + 16)
end

function TC:Show()
	frame = frame or Build()
	Layout()
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	frame:Show()
	NBG:After(0.05, function() if frame:IsShown() then Skin:Redraw() Layout() end end)
end

function TC:Hide() if frame then frame:Hide() end end

function TC:Choose(id)
	local db = NBG.db
	if db then db.global.themeAsked = true end
	NBG.Settings:Set("look.skin", id)
	if frame then frame:Hide() end
	NBG:Print(id == "netherui" and L["NetherBags now follows NetherUI's theme."] or L["NetherBags keeps its own look."])
end
