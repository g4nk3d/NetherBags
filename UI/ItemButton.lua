--[[ NetherBags - UI/ItemButton.lua
	The item buttons. A live item (one this character carries now) is the game's own container
	item button (ContainerFrameItemButtonTemplate), so using, moving, splitting, linking and selling
	items all run the game's own code. Its bag is the ID of its parent (one small frame per bag) and
	its slot is its own ID; nothing of the game's button is replaced. Offline items (another
	character, or a bank seen earlier) are plain buttons that show the item's tooltip and link it.

	One button per bag slot, made out of combat ahead of time (and never re-parented later). Each
	button has two looks: "grid" (a square slot, One bag) and "row" (a full-width line, Insight).

	  Buttons:Host(place)            the frame a window anchors its bag frames to (one per place)
	  Buttons:Live(bag, slot)        the live button for a slot (made now if out of combat)
	  Buttons:Prepare(place)         make every button a place could need (out of combat)
	  Buttons:Offline(pool, i)       a plain button from a named pool
	  b:NBGrid(size)  b:NBRow(w, h, cols)   set the look
	  b:Show(entry, opts)            paint: opts { dim, hover, cols }
	  Buttons:HideAll(place)         hide every live button of a place

	Alt+Right-click any item: the item menu (lock, junk, always put in, find everywhere, link).
	Alt+Left-click: lock / unlock. (A plain overlay takes those clicks while Alt is held, so the
	game's button never sees them.) ]]

local _, ns = ...
local TINT_EMPTY, TINT_UNDER_ITEM = 0.32, 0.12   -- the bag colour in a slot's background (bag menu)
local NBG = ns.NBG
local L = ns.L
local Buttons = NBG:Module("Buttons")
local Skin, W = NBG.Skin, NBG.Widgets
local Items, Marks, Containers = NBG.Items, NBG.Marks, NBG.Containers
local MEDIA = NBG.MEDIA

local type, pairs, ipairs, floor, max = type, pairs, ipairs, math.floor, math.max

local hosts, proxies, live, pools = {}, {}, {}, {}
local made = 0

function Buttons:Host(place)
	local h = hosts[place]
	if not h then
		h = CreateFrame("Frame", "NetherBagsHost_" .. place, UIParent)
		h:SetSize(1, 1)
		h:Hide()
		hosts[place] = h
	end
	return h
end

local function Proxy(bag)
	local p = proxies[bag]
	if not p then
		local place = Containers:PlaceOf(bag)
		p = CreateFrame("Frame", nil, Buttons:Host(place))
		p:SetAllPoints()
		p:SetID(bag)
		proxies[bag] = p
	end
	return p
end
Buttons.Proxy = Proxy

---------------------------------------------------------------------------------------------
-- the decorations both kinds of button wear
---------------------------------------------------------------------------------------------
local function Decorate(b)
	local d = {}
	b.nb = d
	-- grid parts
	d.slotBg = b:CreateTexture(nil, "BACKGROUND", nil, -7)
	d.slotBg:SetTexture(MEDIA .. "SlotFill")
	d.slotBg:SetAllPoints()
	d.ring = b:CreateTexture(nil, "OVERLAY", nil, 2)
	d.ring:SetTexture(MEDIA .. "SlotRing")
	d.ring:SetAllPoints()
	d.glow = b:CreateTexture(nil, "BACKGROUND", nil, -6)
	d.glow:SetTexture(MEDIA .. "Glow")
	d.glow:SetPoint("TOPLEFT", -8, 8) d.glow:SetPoint("BOTTOMRIGHT", 8, -8)
	d.glow:SetBlendMode("ADD")
	d.dim = b:CreateTexture(nil, "OVERLAY", nil, 5)
	d.dim:SetColorTexture(0, 0, 0, 0.72)
	d.count = b:CreateFontString(nil, "OVERLAY", nil, 6)
	Skin:Font(d.count, "bold", 11, "OUTLINE", false)
	d.count:SetTextColor(1, 1, 1)
	d.marks = {}
	for i, pos in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT" }) do
		local m = b:CreateTexture(nil, "OVERLAY", nil, 7)
		m.pos = pos
		d.marks[i] = m
	end
	d.hover = b:CreateTexture(nil, "HIGHLIGHT")
	d.hover:SetTexture(MEDIA .. "SlotRing")
	d.hover:SetAllPoints()
	d.hover:SetVertexColor(1, 1, 1, 0.55)
	-- row parts
	d.rowHl = b:CreateTexture(nil, "BACKGROUND", nil, -5)
	d.rowHl:SetTexture(MEDIA .. "FadeR")
	d.rowHl:SetAllPoints()
	d.rowBar = b:CreateTexture(nil, "BACKGROUND", nil, -4)
	d.rowBar:SetColorTexture(1, 1, 1, 1)
	d.rowBar:SetPoint("TOPLEFT") d.rowBar:SetPoint("BOTTOMLEFT") d.rowBar:SetWidth(2)
	d.rowLine = b:CreateTexture(nil, "BACKGROUND", nil, -3)
	d.rowLine:SetColorTexture(1, 1, 1, 1)
	d.rowLine:SetPoint("BOTTOMLEFT", 20, 0) d.rowLine:SetPoint("BOTTOMRIGHT") d.rowLine:SetHeight(1)
	d.iconEdge = b:CreateTexture(nil, "OVERLAY", nil, 1)
	d.iconEdge:SetTexture(MEDIA .. "SlotRing")
	d.newMark = b:CreateTexture(nil, "OVERLAY")
	W:SetGlyph(d.newMark, "new")
	d.newMark:SetSize(11, 11)
	d.newMark:SetPoint("LEFT", 5, 0)
	d.name = W:Text(b, 12.5, "text", "medium")
	d.name:SetJustifyH("LEFT")
	d.sub = W:Text(b, 9.5, "faint")
	d.sub:SetJustifyH("LEFT")
	d.status = {}
	for i = 1, 4 do d.status[i] = b:CreateTexture(nil, "OVERLAY") d.status[i]:SetSize(13, 13) end
	d.upText = W:Text(b, 10, "positive", "bold")
	d.ilvl = W:Text(b, 12, "text", "medium")
	d.value = W:Text(b, 11.5, "text", "medium")
	d.value:SetJustifyH("RIGHT")
	d.extra = W:Text(b, 11, "textDim")
	return d
end

-- the game's own pieces we draw ourselves (hidden, never replaced)
local GAME_PARTS = { "IconBorder", "IconOverlay", "IconOverlay2", "NewItemTexture", "BattlepayItemTexture", "JunkIcon", "UpgradeIcon",
	"flash", "searchOverlay", "ItemContextOverlay", "IconQuestTexture", "Count", "Stock", "ExtendedSlot", "ItemSlotBackground" }

local function HideGameParts(b)
	local name = b:GetName()
	for _, k in ipairs(GAME_PARTS) do
		local t = b[k] or (name and _G[name .. k])
		if t and t.Hide then t:Hide() t:SetAlpha(0) end
	end
	local nt = b.GetNormalTexture and b:GetNormalTexture()
	if nt then nt:SetAlpha(0) end
	local ht = b.GetHighlightTexture and b:GetHighlightTexture()
	if ht then ht:SetAlpha(0) end
	local pt = b.GetPushedTexture and b:GetPushedTexture()
	if pt then pt:SetAlpha(0.35) end
end

local function IconOf(b)
	return b.icon or b.Icon or (b:GetName() and _G[b:GetName() .. "IconTexture"])
end

local function CooldownOf(b)
	return b.Cooldown or (b:GetName() and _G[b:GetName() .. "Cooldown"])
end

---------------------------------------------------------------------------------------------
-- looks
---------------------------------------------------------------------------------------------
local Methods = {}

function Methods:NBGrid(size)
	local d = self.nb
	self.nbLook = "grid"
	self:SetSize(size, size)
	local ic = IconOf(self)
	if ic then ic:ClearAllPoints() ic:SetPoint("TOPLEFT", 2, -2) ic:SetPoint("BOTTOMRIGHT", -2, 2) ic:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
	d.count:ClearAllPoints() d.count:SetPoint("BOTTOMRIGHT", -3, 3)
	Skin:SetFontSize(d.count, max(9, floor(size * 0.29)))
	local ms = max(9, floor(size * 0.3))
	for _, m in ipairs(d.marks) do
		m:SetSize(ms, ms)
		m:ClearAllPoints()
		m:SetPoint(m.pos, m.pos:find("LEFT") and 3 or -3, m.pos:find("TOP") and -3 or 3)
	end
	d.dim:ClearAllPoints() d.dim:SetPoint("TOPLEFT", 2, -2) d.dim:SetPoint("BOTTOMRIGHT", -2, 2)
	d.slotBg:Show() d.hover:Show()
	for _, k in ipairs({ "rowHl", "rowBar", "rowLine", "iconEdge", "newMark", "name", "sub", "upText", "ilvl", "value", "extra" }) do d[k]:Hide() end
	for _, s in ipairs(d.status) do s:Hide() end
	local cd = CooldownOf(self)
	if cd then cd:ClearAllPoints() cd:SetPoint("TOPLEFT", 2, -2) cd:SetPoint("BOTTOMRIGHT", -2, 2) end
end

function Methods:NBRow(w, h, cols)
	local d = self.nb
	self.nbLook = "row"
	self.nbCols = cols
	self:SetSize(w, h)
	local is = h - 8
	local ic = IconOf(self)
	if ic then ic:ClearAllPoints() ic:SetPoint("LEFT", 22, 0) ic:SetSize(is, is) ic:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
	d.iconEdge:ClearAllPoints() d.iconEdge:SetPoint("LEFT", 21, 0) d.iconEdge:SetSize(is + 2, is + 2)
	d.count:ClearAllPoints() d.count:SetPoint("BOTTOMRIGHT", ic or self, "BOTTOMRIGHT", 1, 0)
	Skin:SetFontSize(d.count, max(8, floor(h * 0.27)))
	d.name:ClearAllPoints()
	d.sub:ClearAllPoints()
	if NBG.Settings:Get("insight.showType") and h >= 28 then
		d.name:SetPoint("LEFT", 22 + is + 10, 6.5)
		d.sub:SetPoint("LEFT", 22 + is + 10, -7.5)
	else
		d.name:SetPoint("LEFT", 22 + is + 10, 0)
	end
	d.name:SetWidth(max(60, (cols and cols.status or (w * 0.5)) - (22 + is + 10) - 8))
	d.sub:SetWidth(d.name:GetWidth())
	for i, s in ipairs(d.status) do s:ClearAllPoints() s:SetPoint("LEFT", (cols and cols.status or w * 0.55) + (i - 1) * 18, 0) end
	d.ilvl:ClearAllPoints() d.ilvl:SetPoint("CENTER", self, "LEFT", cols and cols.ilvl or w * 0.78, 0)
	d.value:ClearAllPoints() d.value:SetPoint("RIGHT", self, "LEFT", cols and cols.value or (w - 8), 0)
	d.extra:ClearAllPoints() d.extra:SetPoint("CENTER", self, "LEFT", cols and cols.extra or (w * 0.66), 0)
	d.dim:ClearAllPoints() d.dim:SetAllPoints()
	d.slotBg:Hide() d.ring:Hide() d.glow:Hide() d.hover:Hide()
	for _, m in ipairs(d.marks) do m:Hide() end
	local cd = CooldownOf(self)
	if cd and ic then cd:ClearAllPoints() cd:SetAllPoints(ic) end
end

local MARK_ROLE = { x = "negative", up = "positive", eye = { 0.94, 0.55, 0.98 }, link = "accent2", lock = "header", set = { 0.51, 0.78, 1 }, excl = "header", junk = { 0.75, 0.75, 0.75 }, new = "header" }

local function PaintGlyph(t, name)
	W:SetGlyph(t, name)
	local r = MARK_ROLE[name]
	if type(r) == "table" then Skin:Unpaint(t) t:SetVertexColor(r[1], r[2], r[3], 1) else Skin:Paint(t, r or "text") end
	t:Show()
end

-- the markers an entry earns, in order
local function Markers(e)
	local S = NBG.Settings
	local out = {}
	if not e or not e.id then return out end
	local up = S:Get("mark.upgrade") and e.live ~= false and Items:Upgrade(e)
	if up then out[#out + 1] = "up" end
	if S:Get("mark.unusable") and not Items:CanUse(e) then out[#out + 1] = "x" end
	if S:Get("mark.junk") and Marks:IsJunk(e) then out[#out + 1] = "junk" end
	if S:Get("mark.quest") and (e.quest or (Items:Info(e.link) or {}).classID == 12 or Items:QuestNeeded(e)) then out[#out + 1] = "excl" end
	if S:Get("mark.unseen") and Items:Unseen(e.link) then out[#out + 1] = "eye" end
	if S:Get("mark.bind") and Items:Binding(e) == "boe" then out[#out + 1] = "link" end
	if S:Get("mark.set") and Items:InSet(e.id) then out[#out + 1] = "set" end
	if S:Get("mark.lock") and Marks:IsLocked(e.id) then out[#out + 1] = "lock" end
	return out, up
end
Buttons.Markers = Markers

---------------------------------------------------------------------------------------------
-- fading what can't go where you are: at a vendor what can't be sold, at the mailbox, a trade or
-- the auction house what is bound to you (setting look.contextFade)
---------------------------------------------------------------------------------------------
local ctx = {}
local function SetCtx(k, on)
	if ctx[k] == on then return end
	ctx[k] = on
	NBG:Debounce("contextFade", 0.05, function() if NBG.Windows then NBG.Windows:RefreshAll(true) end end)
end
for _, p in ipairs({ { "MAIL_SHOW", "MAIL_CLOSED", "mail" }, { "TRADE_SHOW", "TRADE_CLOSED", "trade" }, { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "auction" } }) do
	NBG:On(p[1], function() SetCtx(p[3], true) end)
	NBG:On(p[2], function() SetCtx(p[3], false) end)
end
do
	local KIND = { MailInfo = "mail", TradePartner = "trade", Auctioneer = "auction" }
	local function Kind(kind)
		local E = type(_G.Enum) == "table" and _G.Enum.PlayerInteractionType
		if not E or kind == nil then return nil end
		for name, k in pairs(KIND) do if E[name] == kind then return k end end
		return nil
	end
	NBG:On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind) local k = Kind(kind) if k then SetCtx(k, true) end end)
	NBG:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind) local k = Kind(kind) if k then SetCtx(k, false) end end)
end
function Buttons:Context() return ctx end

function Buttons.Faded(e)
	if not (e and e.id and e.live ~= false and e.place == "bags") then return false end
	if not NBG.Settings:Get("look.contextFade") then return false end
	if NBG.Selling and NBG.Selling:AtMerchant() then
		local i = Items:Info(e.link)
		return (e.noValue or (i and (i.price or 0) <= 0)) and true or false
	end
	if ctx.mail or ctx.trade or ctx.auction then
		local b = Items:Binding(e)
		return (b == "soulbound" or b == "quest" or e.quest) and true or false
	end
	return false
end

local function SetIcon(b, tex)
	local ic = IconOf(b)
	if not ic then return end
	if tex then ic:SetTexture(tex) ic:Show() else ic:SetTexture(nil) ic:Hide() end
end

function Methods:NBPaint(e, opts)
	opts = opts or {}
	local d = self.nb
	local S = NBG.Settings
	self.nbEntry = e
	local info = e and e.link and Items:Info(e.link)
	local icon = e and (e.icon or (info and info.icon) or (e.id and select(4, Items:Instant(e.id))))
	SetIcon(self, icon)
	-- (the game's template reads these two)
	self.hasItem = e and e.id and true or nil
	self.readable = e and e.readable or nil
	local q = e and (e.quality or (info and info.quality))
	local count = e and e.count or 0
	d.count:SetText(count > 1 and (count > 9999 and floor(count / 1000) .. "k" or tostring(count)) or "")
	d.count:SetShown(count > 1)
	d.dim:SetShown(opts.dim and true or false)
	-- can't use yet: a red icon; doesn't fit where you are: faded
	local ic = IconOf(self)
	local canUse, _, useText = true, nil, nil
	if e and S:Get("mark.unusable") then canUse, _, useText = Items:CanUse(e) end
	local faded = Buttons.Faded(e)
	if ic then
		if not canUse then ic:SetVertexColor(1, 0.32, 0.32) else ic:SetVertexColor(1, 1, 1) end
		ic:SetAlpha(faded and 0.3 or 1)
		if ic.SetDesaturated then ic:SetDesaturated((faded or (e and e.locked)) and true or false) end
	end
	self.nbFaded = faded
	local qr, qg, qb = Items:QualityColor(q or 1)
	if self.nbLook == "grid" then
		local edge = e and S:Get("look.qualityBorders") and q and q >= (S:Get("look.qualityMin") or 2)
		Skin:Paint(d.slotBg, opts.special and "special" or "inset", { alpha = opts.special and 0.18 or 1 })
		-- the bag's colour (bag menu): a light tint of it in the slot's background. An item in
		-- the slot always comes first: then the tint is only a faint wash behind it and the
		-- edge stays the item's (its quality colour, or the plain border); empty slots show
		-- the bag's colour fully.
		local tint = opts.tint
		self.nbTint = tint
		self.nbTintRing = nil
		if tint then
			local ir, ig, ib = Skin:Color("inset")
			local mix = e and TINT_UNDER_ITEM or TINT_EMPTY
			Skin:Unpaint(d.slotBg)
			d.slotBg:SetVertexColor(ir * (1 - mix) + tint[1] * mix, ig * (1 - mix) + tint[2] * mix, ib * (1 - mix) + tint[3] * mix, 1)
		end
		if edge then
			Skin:Unpaint(d.ring) d.ring:SetVertexColor(qr, qg, qb, 0.95) d.ring:Show()
		elseif e and (e.quest or (info and info.classID == 12)) then
			Skin:Paint(d.ring, "header") d.ring:Show()
		elseif tint and not e then
			Skin:Unpaint(d.ring) d.ring:SetVertexColor(tint[1], tint[2], tint[3], 0.5) d.ring:Show()
			self.nbTintRing = true
		else
			Skin:Paint(d.ring, opts.special and "special" or "border", { alpha = e and 0.6 or 0.35 }) d.ring:Show()
		end
		local glow = e and e.new and S:Get("look.newGlow") and S:Get("mark.new")
		d.glow:SetShown(glow and true or false)
		if glow then Skin:Paint(d.glow, "header", { alpha = 0.55 }) end
		local marks = Markers(e)
		-- top-left: upgrade / junk / quest; top-right: new or unseen look; bottom-left: lock
		local tl, tr, bl
		for _, m in ipairs(marks) do
			if (m == "up" or m == "x" or m == "junk" or m == "excl") and not tl then tl = m end
			if m == "eye" and not tr then tr = m end
			if m == "lock" then bl = m end
		end
		if e and e.new and S:Get("mark.new") and not tr then tr = "new" end
		local set = { tl, tr, bl }
		for i, m in ipairs(d.marks) do if set[i] then PaintGlyph(m, set[i]) else m:Hide() end end
	else
		-- row
		d.rowHl:SetShown(opts.hover and true or false)
		d.rowBar:SetShown(opts.hover and true or false)
		Skin:Paint(d.rowHl, "rowHover")
		Skin:Paint(d.rowBar, "header")
		Skin:Paint(d.rowLine, "border", { alpha = 0.45 })
		d.rowLine:Show()
		d.iconEdge:SetShown(q and q >= 2 and true or false)
		Skin:Unpaint(d.iconEdge)
		d.iconEdge:SetVertexColor(qr, qg, qb, 0.9)
		d.newMark:SetShown(e and e.new and S:Get("mark.new") and true or false)
		Skin:Paint(d.newMark, "header")
		d.name:Show()
		d.name:SetText(info and info.name or (e and e.str and "…" or ""))
		Skin:Unpaint(d.name)
		d.name:SetTextColor(qr, qg, qb, faded and 0.45 or 1)
		local showSub = S:Get("insight.showType")
		d.sub:SetShown(showSub and true or false)
		if showSub then
			local parts = {}
			if info then
				local slotName = Items:SlotName(info.equipLoc)
				if slotName then parts[#parts + 1] = slotName end
				if info.subType ~= "" and info.subType ~= slotName then parts[#parts + 1] = info.subType end
				if #parts == 0 and info.type ~= "" then parts[#parts + 1] = info.type end
			end
			if opts.subExtra then parts[#parts + 1] = opts.subExtra end
			if not canUse and useText then parts[#parts + 1] = "|cffff6060" .. useText .. "|r" end
			d.sub:SetText(table.concat(parts, "  ·  "))
		end
		local marks, up = Markers(e)
		local cols = self.nbCols or {}
		for i, s in ipairs(d.status) do
			if cols.status and S:Get("insight.colStatus") and marks[i] then PaintGlyph(s, marks[i]) else s:Hide() end
		end
		if up and cols.status and S:Get("insight.colStatus") then
			d.upText:ClearAllPoints()
			d.upText:SetPoint("LEFT", d.status[math.min(#marks, 4)], "RIGHT", 3, 0)
			d.upText:SetText("+" .. up) d.upText:Show()
		else
			d.upText:Hide()
		end
		if cols.ilvl and S:Get("insight.colIlvl") and info and (info.classID == 2 or info.classID == 4) and info.ilvl > 1 then
			d.ilvl:SetText(tostring(info.ilvl)) Skin:Paint(d.ilvl, "text") d.ilvl:Show()
		elseif cols.ilvl and S:Get("insight.colIlvl") then
			d.ilvl:SetText("-") Skin:Paint(d.ilvl, "faint") d.ilvl:Show()
		else
			d.ilvl:Hide()
		end
		if opts.ilvlText then d.ilvl:SetText(opts.ilvlText) Skin:Paint(d.ilvl, "text") d.ilvl:Show() end
		local price = info and info.price or 0
		if cols.value and S:Get("insight.colValue") and price > 0 and not (e and e.noValue) then
			d.value:SetText(W:Money(price * count)) d.value:Show()
		else
			d.value:SetText("") d.value:Hide()
		end
		if opts.extra and cols.extra then d.extra:SetText(opts.extra) d.extra:Show() else d.extra:Hide() end
	end
end

function Methods:NBCooldown()
	local cd = CooldownOf(self)
	if not cd then return end
	local e = self.nbEntry
	if not (e and e.live ~= false and e.bag and e.slot) then cd:Hide() return end
	local f = NBG.API("C_Container", "GetContainerItemCooldown") or _G.GetContainerItemCooldown
	if not f then return end
	local ok, start, dur, enable = pcall(f, e.bag, e.slot)
	if not ok then return end
	if _G.CooldownFrame_Set then pcall(CooldownFrame_Set, cd, start or 0, dur or 0, enable)
	elseif cd.SetCooldown and (dur or 0) > 0 then cd:SetCooldown(start, dur) cd:Show() else cd:Hide() end
end

---------------------------------------------------------------------------------------------
-- live buttons
---------------------------------------------------------------------------------------------
local function NewLive(bag, slot)
	made = made + 1
	local parent = Proxy(bag)
	local name = "NetherBagsItem" .. made
	local ok, b = pcall(CreateFrame, "ItemButton", name, parent, "ContainerFrameItemButtonTemplate")
	if not ok or not b then
		ok, b = pcall(CreateFrame, "Button", name, parent, "ContainerFrameItemButtonTemplate")
	end
	if not ok or not b then
		-- no template on this client: a plain button (no using items from it)
		b = CreateFrame("Button", name, parent)
		b.icon = b:CreateTexture(nil, "BORDER")
		b.Cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
		b.plain = true
	end
	b:SetID(slot)
	b:SetScript("OnEvent", nil)
	b:SetScript("OnShow", nil)
	if b.RegisterForDrag then b:RegisterForDrag("LeftButton") end
	if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
	HideGameParts(b)
	Decorate(b)
	for k, fn in pairs(Methods) do b[k] = fn end
	b.nbLive = true
	b:HookScript("OnEnter", function(self) Buttons.hovered = self Buttons:Picker(self) NBG:Fire("ITEM_ENTER", self) end)
	b:HookScript("OnLeave", function(self) if Buttons.hovered == self then Buttons.hovered = nil end NBG:Fire("ITEM_LEAVE", self) end)
	b:Hide()
	return b
end

function Buttons:Live(bag, slot)
	live[bag] = live[bag] or {}
	local b = live[bag][slot]
	if b then return b end
	-- (the game's template is not a protected one, but buttons are still made ahead of combat
	-- by Prepare; one needed in combat is made then)
	b = NewLive(bag, slot)
	live[bag][slot] = b
	return b
end

-- make every button a place could need now (out of combat), so none is made in combat
function Buttons:Prepare(place)
	if NBG:InCombat() then return end
	for _, bag in ipairs(Containers:Bags(place)) do
		for slot = 1, Containers:Size(bag) do self:Live(bag, slot) end
	end
end

function Buttons:HideAll(place, keep)
	for bag, list in pairs(live) do
		if Containers:PlaceOf(bag) == place then
			for _, b in pairs(list) do if not (keep and keep[b]) then b:Hide() end end
		end
	end
end

function Buttons:EachLive(fn)
	for _, list in pairs(live) do for _, b in pairs(list) do fn(b) end end
end

NBG:On("PLAYER_REGEN_DISABLED", function() Buttons:Prepare("bags") if Containers:BankOpen() then Buttons:Prepare("bank") end end)
NBG:Register("LOGIN", function() NBG:After(1, function() Buttons:Prepare("bags") end) end)
NBG:Register("BANK_OPEN", function(_, open) if open then Buttons:Prepare("bank") end end)

NBG:Register("SLOT_LOCK", function(_, bag, slot)
	local b = live[bag] and live[bag][slot]
	if b and b:IsVisible() then
		local e = Containers:Entry(bag, slot)
		local ic = IconOf(b)
		if ic and ic.SetDesaturated then ic:SetDesaturated(e and e.locked or false) end
	end
end)
NBG:Register("COOLDOWNS", function() Buttons:EachLive(function(b) if b:IsVisible() then b:NBCooldown() end end) end)

---------------------------------------------------------------------------------------------
-- offline buttons (plain)
---------------------------------------------------------------------------------------------
function Buttons:Offline(pool, i, parent)
	pools[pool] = pools[pool] or {}
	local b = pools[pool][i]
	if b then if parent and b:GetParent() ~= parent then b:SetParent(parent) end return b end
	b = CreateFrame("Button", nil, parent or UIParent)
	b.icon = b:CreateTexture(nil, "BORDER")
	b.Cooldown = nil
	Decorate(b)
	for k, fn in pairs(Methods) do b[k] = fn end
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnEnter", function(self)
		Buttons.hovered = self
		local e = self.nbEntry
		if not (e and e.link) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, e.link)
		if ok then
			if e.owner and e.place then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine(("%s  ·  %s"):format(e.owner, Buttons.PlaceName(e)), 0.55, 0.82, 0.96)
			end
			GameTooltip:Show()
		end
		NBG:Fire("ITEM_ENTER", self)
	end)
	b:SetScript("OnLeave", function(self) if Buttons.hovered == self then Buttons.hovered = nil end GameTooltip:Hide() NBG:Fire("ITEM_LEAVE", self) end)
	b:SetScript("OnClick", function(self, btn)
		local e = self.nbEntry
		if not e then return end
		if IsAltKeyDown() and btn == "RightButton" then Buttons:Menu(self, e) return end
		if IsAltKeyDown() and btn == "LeftButton" then Marks:ToggleLock(e.id) return end
		if e.link and _G.HandleModifiedItemClick then
			local link = e.link
			local i = Items:Info(e.link)
			if i and i.link then link = i.link end
			pcall(HandleModifiedItemClick, link)
		end
		if self.nbOnClick then self.nbOnClick(self, btn) end
	end)
	pools[pool][i] = b
	return b
end

function Buttons.PlaceName(e)
	if e.place == "bags" then return L["Bags"]
	elseif e.place == "bank" then return L["Bank"]
	elseif e.place == "mail" then return L["Mailbox"]
	elseif e.place == "guild" then return L["Guild bank"] .. (e.tab and (" · " .. L["Tab"] .. " " .. e.tab) or "") end
	return ""
end

---------------------------------------------------------------------------------------------
-- Alt+click: a plain overlay over the hovered live button takes the click
---------------------------------------------------------------------------------------------
local picker
function Buttons:Picker(b)
	if not picker then
		picker = CreateFrame("Button", nil, UIParent)
		picker:SetFrameStrata("TOOLTIP")
		picker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		picker:Hide()
		picker:SetScript("OnClick", function(self, btn)
			local e = self.target and self.target.nbEntry
			self:Hide()
			if not e then return end
			if btn == "RightButton" then Buttons:Menu(self.target, e) else Marks:ToggleLock(e.id) end
		end)
		picker:SetScript("OnLeave", function(self) self:Hide() end)
		picker:SetScript("OnEnter", function(self)
			if self.target and self.target.nbEntry and self.target.nbEntry.link then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				local e = self.target.nbEntry
				if e.live ~= false and e.bag and e.slot and GameTooltip.SetBagItem then pcall(GameTooltip.SetBagItem, GameTooltip, e.bag, e.slot)
				else pcall(GameTooltip.SetHyperlink, GameTooltip, e.link) end
				GameTooltip:AddLine(L["Alt+Right-click: item options   Alt+Left-click: lock"], 0.55, 0.82, 0.96)
				GameTooltip:Show()
			end
		end)
		NBG:On("MODIFIER_STATE_CHANGED", function() if Buttons.hovered and Buttons.hovered.nbLive then Buttons:Picker(Buttons.hovered) elseif picker:IsShown() and not IsAltKeyDown() then picker:Hide() end end)
	end
	if b and b.nbLive and b:IsVisible() and IsAltKeyDown() and b.nbEntry then
		picker.target = b
		picker:ClearAllPoints()
		picker:SetAllPoints(b)
		picker:Show()
	else
		picker:Hide()
	end
end

---------------------------------------------------------------------------------------------
-- the item menu
---------------------------------------------------------------------------------------------
-- "Send all to an alt": at a mailbox, every stack of the item to another character of the account
function Buttons.SendAllEntry(e)
	local T = NBG.Transfer
	if not (T and e.live ~= false and e.place == "bags") then return { text = L["Send all to an alt (at a mailbox)"], glyph = "mail", disabled = true } end
	if not T:MailOpen() then return { text = L["Send all to an alt (at a mailbox)"], glyph = "mail", disabled = true } end
	local alts = {}
	for _, key in ipairs(T:Alts()) do alts[#alts + 1] = { text = key, onClick = function() T:SendAll(e, key) end } end
	if #alts == 0 then return { text = L["Send all to an alt (no other characters seen yet)"], glyph = "mail", disabled = true } end
	return { text = L["Send all to"], glyph = "mail", sub = alts }
end

function Buttons:Menu(owner, e)
	if not (e and e.id) then return end
	local id = e.id
	local locked = Marks:IsLocked(id)
	local junk = Marks:IsJunk(e)
	local groups = {}
	for _, g in ipairs(NBG.Groups:List()) do
		if g.id ~= "new" then
			groups[#groups + 1] = { text = g.label, glyph = g.glyph, checked = Marks:Assigned(id) == g.id, onClick = function()
				if Marks:Assigned(id) == g.id then Marks:Assign(id, nil) else Marks:Assign(id, g.id) end end }
		end
	end
	groups[#groups + 1] = "-"
	groups[#groups + 1] = { text = L["Automatic (by the rules)"], checked = Marks:Assigned(id) == nil, onClick = function() Marks:Assign(id, nil) end }
	local info = Items:Info(e.link)
	local items = {
		{ text = info and info.name or L["Item"], disabled = true },
		"-",
		{ text = locked and L["Unlock"] or L["Lock (never sell, stash or sort)"], glyph = "lock", onClick = function() Marks:SetLocked(id, not locked) end },
		{ text = junk and L["Not junk"] or L["Mark as junk"], glyph = "junk", glyphRole = "textDim", onClick = function() Marks:SetJunk(id, not junk) end },
		{ text = L["Junk at the next vendor only"], glyph = "junk", glyphRole = "textDim", checked = Marks:IsJunkOnce(id), onClick = function() Marks:SetJunkOnce(id, not Marks:IsJunkOnce(id)) end },
		{ text = L["Always put in"], glyph = "chev_r", sub = groups },
		{ text = NBG.Tracked and NBG.Tracked:IsTracked(id) and L["Stop tracking in the footer"] or L["Track in the footer"], glyph = "eye", onClick = function() NBG.Tracked:Toggle(id) end },
		"-",
		Buttons.SendAllEntry(e),
		{ text = L["Find on all characters"], glyph = "globe", onClick = function() NBG:Fire("FIND_EVERYWHERE", info and info.name or ("id:" .. id)) end },
		{ text = L["Link in chat"], glyph = "link", onClick = function()
			local link = info and info.link or e.link
			if link and _G.ChatEdit_InsertLink then pcall(ChatEdit_InsertLink, link) end
		end },
	}
	local extra = NBG.Plugin and NBG.Plugin:MenuItems(e) or {}
	if #extra > 0 then
		items[#items + 1] = "-"
		for _, it in ipairs(extra) do items[#items + 1] = it end
	end
	W:Menu("cursor", items)
end
