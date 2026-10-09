--[[ NetherBags - UI/Common.lua
	Pieces both views share.

	  Common:CharMenu(anchor, window)        pick whose bags / bank to look at
	  Common:Footer(parent)                  slots, special bags, tracked currencies, money, junk:
	                                         f:Update(window, entries)
	  Common:Ribbon(parent)                  the "offline view" note: r:Update(window)
	  Common:BagStrip(parent)                the bag slots: s:Update(window) -> width
	  Common:SellJunkButton(parent)          shown at a vendor when there is junk ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Common = NBG:Module("Common")
local Skin, W, Settings = NBG.Skin, NBG.Widgets, NBG.Settings
local Containers, Store, Items, Marks = NBG.Containers, NBG.Store, NBG.Items, NBG.Marks

local type, pairs, ipairs, max, floor = type, pairs, ipairs, math.max, math.floor

local CLASS_COLORS = rawget(_G, "RAID_CLASS_COLORS")
function Common.ClassColor(class)
	local c = CLASS_COLORS and class and CLASS_COLORS[class]
	if c then return ("|cff%02x%02x%02x"):format(floor(c.r * 255), floor(c.g * 255), floor(c.b * 255)) end
	return "|cffd8dce8"
end

function Common:CharMenu(anchor, w)
	local items = {}
	for _, c in ipairs(Store:Characters()) do
		local me = c.key == NBG:PlayerKey()
		items[#items + 1] = { text = Common.ClassColor(c.class) .. c.key .. "|r" .. (c.level and ("  |cff8c96b0" .. c.level .. "|r") or "") .. (me and ("  |cffe8c478" .. L["(you)"] .. "|r") or ""),
			checked = w.owner == c.key, onClick = function() w:SetOwner(c.key) end }
	end
	if #items == 0 then items[1] = { text = NBG:PlayerKey(), checked = true, onClick = function() w:SetOwner(NBG:PlayerKey()) end } end
	W:Menu(anchor, items)
end

---------------------------------------------------------------------------------------------
-- footer
---------------------------------------------------------------------------------------------
function Common:Footer(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(44)
	f.line = f:CreateTexture(nil, "ARTWORK")
	f.line:SetTexture(NBG.MEDIA .. "Fade")
	f.line:SetPoint("TOPLEFT", 10, 0) f.line:SetPoint("TOPRIGHT", -10, 0) f.line:SetHeight(1)
	Skin:Paint(f.line, "accent", { alpha = 0.5 })
	f.icon = W:Glyph(f, "backpack", 18, "accent")
	f.icon:SetPoint("LEFT", 16, 0)
	f.slots = W:Text(f, 12, "text", "bold")
	f.slots:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 7, 2)
	f.sub = W:Text(f, 9, "textDim")
	f.sub:SetPoint("TOPLEFT", f.slots, "BOTTOMLEFT", 0, -2)
	f.bar = f:CreateTexture(nil, "ARTWORK")
	f.bar:SetTexture(NBG.MEDIA .. "Pill")
	f.bar:SetHeight(3)
	f.barBg = f:CreateTexture(nil, "BACKGROUND")
	f.barBg:SetTexture(NBG.MEDIA .. "Pill")
	f.barBg:SetHeight(3)
	f.money = W:Text(f, 12.5, "text", "medium")
	f.money:SetPoint("RIGHT", -18, 0)
	f.cur = W:Text(f, 11.5, "text", "medium")
	f.cur:SetJustifyH("LEFT")
	f.junk = W:Button(f, "", 140, 24, { style = "red", glyph = "junk", onClick = function() NBG.Selling:SellJunk(true) end })
	f.junk:Hide()
	-- "Free a slot" (bags full) and the tracked items
	f.free = W:Button(f, L["Free a slot"], 110, 24, { style = "red", glyph = "trash", onClick = function() NBG.FreeSlot:Offer() end,
		tip = { L["Free a slot"], L["Your bags are full: delete the cheapest junk (you see what it is first)."] } })
	f.free:SetWidth(max(100, (f.free.label:GetStringWidth() or 70) + 44))
	f.free:Hide()
	f.tracked = {}
	local function TrackedBtn(i)
		local b = f.tracked[i]
		if b then return b end
		b = CreateFrame("Button", nil, f)
		b:SetHeight(18)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(16, 16) b.icon:SetPoint("LEFT")
		b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		b.text = W:Text(b, 11.5, "text", "medium")
		b.text:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnEnter", function(self)
			if not self.t then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.t.id)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine((L["Tracked: %d in your bags"]):format(self.t.count), 0.43, 0.82, 0.96)
			if self.t.warn > 0 then GameTooltip:AddLine((L["Warns below %d"]):format(self.t.warn), 0.8, 0.8, 0.8) end
			GameTooltip:AddLine(L["Right-click: warning level, stop tracking"], 0.55, 0.6, 0.7)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:SetScript("OnClick", function(self, btn) if btn == "RightButton" and self.t then Common:TrackedMenu(self, self.t.id) end end)
		f.tracked[i] = b
		return b
	end
	f.chips = CreateFrame("Frame", nil, f)
	f.chips:SetSize(1, 20)
	function f:Update(w, entries)
		local loc = w.location
		local live = w:Live()
		local used, total, special = 0, 0, {}
		if live and (loc == "bags" or loc == "bank") then
			used, total, special = Containers:Counts(loc)
		else
			for _, b in ipairs(w:BagList()) do
				if b.special and b.special.id ~= "keys" then
					local s = special[b.special.id] or { kind = b.special, used = 0, total = 0 }
					s.total = s.total + (b.size or 0)
					special[b.special.id] = s
				elseif not (b.special and b.special.id == "keys") then
					total = total + (b.size or 0)
				end
			end
			for _, e in ipairs(entries or {}) do
				local bi
				for _, b in ipairs(w:BagList()) do if b.id == e.bag then bi = b end end
				if bi and bi.special and bi.special.id ~= "keys" then special[bi.special.id].used = special[bi.special.id].used + 1
				elseif not (bi and bi.special) then used = used + 1 end
			end
		end
		W:SetGlyph(self.icon, loc == "bank" and "bank" or loc == "guild" and "guild" or "backpack")
		self.slots:SetText(("%d / %d"):format(used, total))
		local subs = {}
		for _, s in pairs(special) do subs[#subs + 1] = ("+ %d / %d %s"):format(s.used, s.total, s.kind.label:lower()) end
		self.sub:SetText(table.concat(subs, "  "))
		self.sub:SetShown(#subs > 0)
		local bw = 60
		self.barBg:ClearAllPoints() self.barBg:SetPoint("TOPLEFT", self.slots, "BOTTOMLEFT", 0, #subs > 0 and -14 or -4) self.barBg:SetWidth(bw)
		self.bar:ClearAllPoints() self.bar:SetPoint("LEFT", self.barBg, "LEFT")
		local frac = total > 0 and used / total or 0
		self.bar:SetWidth(max(1, bw * frac))
		Skin:Paint(self.barBg, "inset")
		Skin:Paint(self.bar, frac > 0.9 and "negative" or "accent")
		-- money: this character's (or the saved one), the guild's in the guild bank
		local money
		if loc == "guild" then money = NBG.GuildBank and NBG.GuildBank:Money() or 0
		elseif w.owner == NBG:PlayerKey() then money = Containers:Money()
		else local c = Store:Char(w.owner) money = c and c.money or 0 end
		self.money:SetText(W:Money(money))
		-- tracked currencies (the game's backpack currencies), this character only
		local cur = {}
		if Settings:Get("footer.currencies") and w.owner == NBG:PlayerKey() and loc == "bags" then
			local get = NBG.API("C_CurrencyInfo", "GetBackpackCurrencyInfo")
			for i = 1, 3 do
				local ok, info = pcall(get or function() return nil end, i)
				info = ok and NBG.Open(info) or nil
				if info and info.quantity then
					local icon = info.iconFileID and ("|T" .. info.iconFileID .. ":14:14:0:0|t ") or ""
					cur[#cur + 1] = icon .. (BreakUpLargeNumbers and BreakUpLargeNumbers(info.quantity) or tostring(info.quantity))
				end
			end
		end
		self.cur:SetText(table.concat(cur, "   "))
		self.cur:ClearAllPoints()
		self.cur:SetPoint("RIGHT", self.money, "LEFT", -18, 0)
		-- the right-hand group, right to left: money, currencies, tracked items, Sell junk, Free a slot
		local rightW = 18 + (self.money:GetStringWidth() or 0)
		local anchor, gap = self.money, 18
		if #cur > 0 then anchor = self.cur rightW = rightW + 18 + (self.cur:GetStringWidth() or 0) end
		local tl = (live and loc == "bags" and w.owner == NBG:PlayerKey() and NBG.Tracked) and NBG.Tracked:List() or {}
		for i = #tl, 1, -1 do
			local t = tl[i]
			local b = TrackedBtn(i)
			b.t = t
			b.icon:SetTexture(t.icon)
			b.text:SetText(tostring(t.count))
			if t.low then Skin:Paint(b.text, "negative") else Skin:Paint(b.text, "text") end
			b:SetWidth(20 + (b.text:GetStringWidth() or 20))
			b:ClearAllPoints()
			b:SetPoint("RIGHT", anchor, "LEFT", -gap, 0)
			b:Show()
			anchor, gap = b, 10
			rightW = rightW + 10 + b:GetWidth()
		end
		for i = #tl + 1, #self.tracked do self.tracked[i]:Hide() end
		if #tl > 0 then gap = 14 rightW = rightW + 4 end
		-- junk
		local showJunk = live and loc == "bags" and NBG.Selling and NBG.Selling:AtMerchant() and Settings:Get("junk.button")
		if showJunk then
			local n, value = NBG.Selling:JunkValue()
			if n > 0 then
				self.junk:SetLabel(L["Sell junk"] .. "  ·  " .. W:Money(value))
				self.junk:SetWidth(max(120, (self.junk.label:GetStringWidth() or 80) + 40))
				self.junk:ClearAllPoints()
				self.junk:SetPoint("RIGHT", anchor, "LEFT", -12, 0)
				self.junk:Show()
				anchor = self.junk
				rightW = rightW + 12 + self.junk:GetWidth()
			else showJunk = false end
		end
		if not showJunk then self.junk:Hide() end
		local showFree = live and loc == "bags" and NBG.FreeSlot and NBG.FreeSlot:Needed() and NBG.FreeSlot:Cheapest() ~= nil
		if showFree then
			self.free:ClearAllPoints()
			self.free:SetPoint("RIGHT", anchor, "LEFT", -12, 0)
			self.free:Show()
			rightW = rightW + 12 + self.free:GetWidth()
		else
			self.free:Hide()
		end
		self.rightWidth = rightW + 12
		self.chips:ClearAllPoints()
		self.chips:SetPoint("LEFT", self.slots, "LEFT", 96, -6)
	end
	return f
end

---------------------------------------------------------------------------------------------
-- offline ribbon
---------------------------------------------------------------------------------------------
function Common:Ribbon(parent)
	local r = CreateFrame("Frame", nil, parent)
	r:SetHeight(24)
	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.bg:SetTexture(NBG.MEDIA .. "Pill")
	if r.bg.SetTextureSliceMargins then pcall(r.bg.SetTextureSliceMargins, r.bg, 12, 12, 12, 12) end
	r.edge = r:CreateTexture(nil, "BORDER")
	r.edge:SetAllPoints()
	r.edge:SetTexture(NBG.MEDIA .. "PillEdge")
	if r.edge.SetTextureSliceMargins then pcall(r.edge.SetTextureSliceMargins, r.edge, 12, 12, 12, 12) end
	r.icon = W:Glyph(r, "eye", 12, "accent2")
	r.icon:SetPoint("LEFT", 10, 0)
	r.text = W:Text(r, 10, "text")
	r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
	r.text:SetPoint("RIGHT", -10, 0)
	r.text:SetJustifyH("LEFT")
	function r:Update(w)
		local age = w:Age()
		if not age then self:Hide() return false end
		Skin:Paint(self.bg, "accent2", { alpha = 0.16 })
		Skin:Paint(self.edge, "accent2", { alpha = 0.55 })
		self.text:SetText(L["Offline view"] .. "  ·  " .. age)
		self:Show()
		return true
	end
	return r
end

---------------------------------------------------------------------------------------------
-- bag strip
---------------------------------------------------------------------------------------------
-- the game's own "buy a bank tab" button where the client has it (buying is the game's to do):
-- laid over NetherBags' "+" so the click is the game's button's
local buyBtn
local function GameBuyButton(parent)
	if buyBtn ~= nil then if buyBtn then buyBtn:SetParent(parent) end return buyBtn end
	buyBtn = false
	local XU = rawget(_G, "C_XMLUtil")
	if type(XU) == "table" and XU.GetTemplateInfo and not NBG.Call(XU.GetTemplateInfo, "BankPanelPurchaseButtonScriptTemplate") then return false end
	local ok, b = pcall(CreateFrame, "Button", nil, parent, "BankPanelPurchaseButtonScriptTemplate")
	if ok and b then
		pcall(b.SetAttribute, b, "overrideBankType", (Enum and Enum.BankType and Enum.BankType.Character) or 0)
		b:SetAlpha(0.01)
		buyBtn = b
	end
	return buyBtn
end

local function BuyPrompt(kind)
	if kind == "tab" then
		-- (buying a tab is the game's own to do: from an addon's dialog it would be blocked)
		NBG:Print(L["Buy the next bank tab at the game's bank window."])
	else
		local ok = pcall(StaticPopup_Show, "CONFIRM_BUY_BANK_SLOT")
		if not ok then NBG:Print(L["Buy the next bank slot at the game's bank window."]) end
	end
end

-- the tracked item's menu (footer right-click, item menu)
function Common:TrackedMenu(owner, id)
	local T = NBG.Tracked
	local cur = (Settings:Profile().tracked or {})[id]
	local levels = {}
	for _, n in ipairs({ 0, 1, 3, 5, 10, 20, 50, 100, 200, 500, 1000 }) do
		levels[#levels + 1] = { text = n == 0 and L["Never"] or tostring(n), checked = cur and cur.warn == n, onClick = function() T:SetWarn(id, n) end }
	end
	W:Menu("cursor", {
		{ text = L["Warn when below"], glyph = "chev_r", sub = levels, disabled = not cur },
		{ text = cur and L["Stop tracking"] or L["Track in the footer"], glyph = "eye", onClick = function() T:Toggle(id) end },
	})
end

function Common:BagStrip(parent)
	local s = CreateFrame("Frame", nil, parent)
	s:SetHeight(32)
	s.buttons = {}
	s.highlight = nil
	s.note = W:Text(s, 10, "textDim", "medium")
	s.note2 = W:Text(s, 9, "faint")
	local function Btn(i)
		local b = s.buttons[i]
		if b then return b end
		b = CreateFrame("Button", nil, s)
		b:SetSize(32, 32)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints() b.bg:SetTexture(NBG.MEDIA .. "SlotFill")
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetPoint("TOPLEFT", 2, -2) b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
		b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		b.ring = b:CreateTexture(nil, "OVERLAY")
		b.ring:SetAllPoints() b.ring:SetTexture(NBG.MEDIA .. "SlotRing")
		b.glyph = W:Glyph(b, "plus", 14)
		b.glyph:SetPoint("CENTER", 0, 3)
		b.count = b:CreateFontString(nil, "OVERLAY")
		Skin:Font(b.count, "bold", 9, "OUTLINE", false)
		b.count:SetPoint("BOTTOMRIGHT", -2, 2)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:RegisterForDrag("LeftButton")
		b:SetScript("OnEnter", function(self)
			local info = self.info
			if not info then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			if self.buy then
				GameTooltip:SetText(self.buy.kind == "tab" and L["Buy a bank tab"] or L["Buy a bank bag slot"], 1, 0.86, 0.55)
				GameTooltip:AddLine(W:Money(self.buy.cost), 1, 1, 1)
			elseif info.invSlot and self.live and GameTooltip.SetInventoryItem then
				pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", info.invSlot)
			else
				GameTooltip:SetText(info.name or L["Bag"], 1, 0.86, 0.55)
			end
			if not self.buy then
				if (info.size or 0) > 0 then
					GameTooltip:AddLine((L["%d of %d free"]):format(info.free or 0, info.size or 0), 0.8, 0.8, 0.8)
				elseif info.kind == "tab" then
					GameTooltip:AddLine(L["Empty: drop a bag here to use this tab"], 0.43, 0.82, 0.96)
				end
				if info.special then GameTooltip:AddLine(info.special.label, 0.43, 0.82, 0.96) end
				GameTooltip:AddLine(L["Click: show this bag's slots"], 0.55, 0.6, 0.7)
			end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:SetScript("OnClick", function(self)
			if self.buy then BuyPrompt(self.buy.kind) return end
			s.highlight = (s.highlight ~= self.info.id) and self.info.id or nil
			NBG:Fire("BAG_HIGHLIGHT", s.window and s.window.id, s.highlight)
		end)
		b:SetScript("OnDragStart", function(self)
			if self.live and self.info and self.info.invSlot and not NBG:InCombat() and _G.PickupBagFromSlot then pcall(PickupBagFromSlot, self.info.invSlot) end
		end)
		b:SetScript("OnReceiveDrag", function(self)
			if not (self.live and self.info) or NBG:InCombat() then return end
			if self.info.invSlot and _G.PutItemInBag then pcall(PutItemInBag, self.info.invSlot) end
			-- a bank tab whose bag lives in the bank-tab container (Forever): the bag goes in its slot there
			local still = _G.CursorHasItem and NBG.Call(CursorHasItem)
			local BI = type(_G.Enum) == "table" and Enum.BagIndex
			if still and self.info.kind == "tab" and BI and type(BI.Characterbanktab) == "number" and self.info.tab then
				local pick = NBG.API("C_Container", "PickupContainerItem") or _G.PickupContainerItem
				if pick then pcall(pick, BI.Characterbanktab, self.info.tab) end
			end
		end)
		b:SetScript("OnMouseUp", function(self)
			-- (a bag dropped by clicking with it on the cursor)
			if _G.CursorHasItem and NBG.Call(CursorHasItem) then self:GetScript("OnReceiveDrag")(self) end
		end)
		s.buttons[i] = b
		return b
	end
	function s:Update(w)
		self.window = w
		if buyBtn and not NBG:InCombat() then buyBtn:Hide() end
		local list = w:BagList()
		local live = w:Live()
		local x, n = 0, 0
		local hadSpecial = false
		for _, info in ipairs(list) do
			if info.size and (info.size > 0 or info.kind == "bag" or info.kind == "tab") and info.kind ~= "keyring" then
				n = n + 1
				local b = Btn(n)
				if info.special and not hadSpecial and n > 1 then x = x + 8 hadSpecial = true end
				b.info, b.live, b.buy = info, live, nil
				local inv = NBG.API("C_Container", "ContainerIDToInventoryID") or _G.ContainerIDToInventoryID
				info.invSlot = info.invSlot or (inv and info.id and info.id > 0 and NBG.Call(inv, info.id)) or nil
				b:ClearAllPoints() b:SetPoint("LEFT", x, 0)
				local icon = info.icon
				if info.kind == "backpack" then icon = 133633 end
				b.icon:SetTexture(icon) b.icon:SetShown(icon ~= nil)
				b.glyph:Hide()
				b.count:SetText(info.size and info.size > 0 and info.size or "")
				Skin:Paint(b.bg, "inset")
				local bc = w.location == "bags" and NBG.BagRules and NBG.BagRules:Color(info.id)
				if bc and self.highlight ~= info.id then Skin:Unpaint(b.ring) b.ring:SetVertexColor(bc[1], bc[2], bc[3], 1)
				else Skin:Paint(b.ring, info.special and "special" or (self.highlight == info.id and "header" or "border")) end
				b:Show()
				x = x + 36
			end
		end
		-- the next bank slot / tab to buy (live bank only)
		if live and w.location == "bank" then
			local buy = Containers:NextBankPurchase()
			if buy then
				n = n + 1
				local b = Btn(n)
				b.info, b.live, b.buy = { id = -999, name = "" }, live, buy
				b:ClearAllPoints() b:SetPoint("LEFT", x, 0)
				-- the game's own purchase button over it, where the client has one (bank tabs)
				local gb = buy.kind == "tab" and not NBG:InCombat() and GameBuyButton(b)
				if gb then
					gb:ClearAllPoints() gb:SetAllPoints(b) gb:SetFrameLevel(b:GetFrameLevel() + 5) gb:Show()
					if not gb.nbHooked then
						gb.nbHooked = true
						gb:HookScript("OnEnter", function(self) local p = self:GetParent() local f = p and p:GetScript("OnEnter") if f then f(p) end end)
						gb:HookScript("OnLeave", function() GameTooltip:Hide() end)
					end
				end
				b.icon:Hide()
				W:SetGlyph(b.glyph, "plus") b.glyph:Show()
				Skin:Paint(b.glyph, "positive")
				Skin:Paint(b.bg, "positive", { alpha = 0.15 })
				Skin:Paint(b.ring, "positive", { alpha = 0.7 })
				b.count:SetText("")
				b:Show()
				x = x + 36
			end
		end
		for i = n + 1, #self.buttons do self.buttons[i]:Hide() end
		self.note:ClearAllPoints() self.note:SetPoint("TOPLEFT", x + 6, -4)
		self.note:SetText(w.location == "bank" and L["Bank bags & tabs"] or L["Bag slots"])
		self.note2:ClearAllPoints() self.note2:SetPoint("TOPLEFT", self.note, "BOTTOMLEFT", 0, -3)
		self.note2:SetText(L["click a bag to show its slots"])
		return x
	end
	return s
end
