--[[ NetherBags - Features/QuestBar.lua
	The quest item bar: a small movable bar of the quest items you can use (the ones with a "Use:"
	effect, the ones a quest in your log tells you to use, and the ones that start a quest), so
	they are one click away without opening the bags. Turned on and off with the small quest
	button in the bags window's title bar (One bag and Insight alike); right-click that button for
	its options. Settings > Quest item bar has the rest.

	It reads what the bags already know (Data/Containers.lua: every slot's quest flags; Data/
	Usable.lua: what a quest in the log asks for), so there is no second scan of the bags.

	  - one button per item (counts of every stack added up), in the order the bags hold them;
	  - it starts in the middle of the screen; drag it anywhere with the left mouse button (by its
	    frame or its title, not by an item: a click on an item uses it);
	  - right-click it: the way new items line up turns, up -> left -> down -> right -> up. The
	    corner where the first item sits stays put, so the bar grows away from it;
	  - drop any item on the bar to keep it there (a usable non-quest item, say);
	  - Shift + right-click an item: hide it from the bar (Show hidden items again brings it back);
	  - key bindings: Key Bindings > AddOns > NetherBags, "Use quest item 1" to "4";
	  - the buttons are the game's secure item buttons: the game itself uses the item on the click.
	    While in combat the game allows no change to them, so the bar keeps what it had and catches
	    up when combat ends (counts and cooldowns still update). It never uses anything by itself.

	  QuestBar:Toggle() / SetShown(on) / Items() -> { { id, count, icon, link, bag, slot } }
	  QuestBar:Hide(id) / Keep(id) / ShowHidden() ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local QuestBar = NBG:Module("QuestBar")
local Skin, W, Settings, Containers, Items = NBG.Skin, NBG.Widgets, NBG.Settings, NBG.Containers, NBG.Items

local type, pairs, ipairs, max, min, floor, ceil = type, pairs, ipairs, math.max, math.min, math.floor, math.ceil
local Num = NBG.Num

QuestBar.MAX = 24          -- buttons at most
QuestBar.KEYS = 4          -- "Use quest item 1..4" key bindings
local NAME = "NetherBagsQuestItem"

local bar                  -- the bar (made the first time it is shown)
local buttons = {}
local shownList = {}       -- what the buttons hold now
local pending = false      -- a rebuild waits for the end of combat

---------------------------------------------------------------------------------------------
-- which items
---------------------------------------------------------------------------------------------
local function Lists()
	local p = Settings:Profile()
	p.questHide = type(p.questHide) == "table" and p.questHide or {}
	p.questKeep = type(p.questKeep) == "table" and p.questKeep or {}
	return p.questHide, p.questKeep
end

-- the items a quest in the log says to use (the quest log's "special item" button)
local function SpecialItems()
	local out = {}
	local Q = rawget(_G, "C_QuestLog")
	local count = (type(Q) == "table" and Q.GetNumQuestLogEntries) or _G.GetNumQuestLogEntries
	local special = rawget(_G, "GetQuestLogSpecialItemInfo")
	if not (count and special) then return out end
	local n = Num(NBG.Call(count)) or 0
	for i = 1, min(n, 60) do
		local ok, link = pcall(special, i)
		if ok and type(link) == "string" then
			local id = tonumber(link:match("item:(%d+)"))
			if id then out[id] = true end
		end
	end
	return out
end

local spellCache = {}
local function HasUse(id)
	local v = spellCache[id]
	if v ~= nil then return v end
	local f = NBG.API("C_Item", "GetItemSpell") or rawget(_G, "GetItemSpell")
	if not f then return false end
	local ok, name, spellID = pcall(f, id)
	v = ok and ((type(name) == "string" and name ~= "") or Num(spellID) ~= nil) or false
	spellCache[id] = v
	return v
end

local function IsQuestItem(e)
	if e.quest or e.questID then return true end
	local info = e.link and Items:Info(e.link)
	return info and info.classID == 12 or false
end

-- what the bar shows, from what the bags hold
function QuestBar:Items()
	local hide, keep = Lists()
	local onlyUsable = Settings:Get("questbar.onlyUsable")
	local special = SpecialItems()
	local out, byId = {}, {}
	for _, bag in ipairs(Containers:Bags("bags")) do
		if bag ~= Containers.KEYRING then
			for slot, e in pairs(Containers:Read(bag) or {}) do
				local id = e and e.id
				if id and not byId[id] then
					local want = keep[id]
					if not want and not hide[id] then
						local quest = IsQuestItem(e) or special[id]
						local needed = Items.QuestNeeded and Items:QuestNeeded(e)
						if quest or needed then
							local starts = e.questID and not e.questActive
							local usable = special[id] or starts or HasUse(id)
							want = usable or (not onlyUsable)
						end
					end
					if want then
						local it = { id = id, count = 0, icon = e.icon, link = e.link, bag = bag, slot = slot, keep = keep[id] and true or false }
						byId[id] = it
						out[#out + 1] = it
					end
				end
				if id and byId[id] then byId[id].count = byId[id].count + (e.count or 1) end
			end
		end
	end
	-- the bags' own order (bag, then slot), kept items first
	table.sort(out, function(a, b)
		if a.keep ~= b.keep then return a.keep end
		if a.bag ~= b.bag then return a.bag < b.bag end
		return a.slot < b.slot
	end)
	while #out > self.MAX do table.remove(out) end
	return out
end

---------------------------------------------------------------------------------------------
-- the bar
---------------------------------------------------------------------------------------------
local function LayoutStore()
	local f = Settings:Profile().layout.frames
	f.questbar = type(f.questbar) == "table" and f.questbar or {}
	return f.questbar
end

-- The bar is held by the corner its first item sits in, so it grows away from that corner:
-- up -> bottom-left, left -> top-right, down and right -> top-left. Never placed yet: the middle
-- of the screen. (Saved as the bar's edges on the screen: l, r, t, b.)
QuestBar.GROW_ORDER = { "up", "left", "down", "right" }
local CORNER = { up = "BOTTOMLEFT", left = "TOPRIGHT", down = "TOPLEFT", right = "TOPLEFT" }

local function Place()
	if not bar or NBG:InCombat() then return end
	local s = LayoutStore()
	bar:ClearAllPoints()
	local l, r, t, b = Num(s.l), Num(s.r), Num(s.t), Num(s.b)
	if not (l and r and t and b) then bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0) return end
	local corner = CORNER[Settings:Get("questbar.grow")] or "TOPLEFT"
	local x = corner == "TOPRIGHT" and r or l
	local y = corner == "BOTTOMLEFT" and b or t
	bar:SetPoint(corner, UIParent, "BOTTOMLEFT", x, y)
end

local function SavePlace()
	local l, r, t, b = bar:GetLeft(), bar:GetRight(), bar:GetTop(), bar:GetBottom()
	if not (Num(l) and Num(r) and Num(t) and Num(b)) then return end
	local s = LayoutStore()
	s.l, s.r, s.t, s.b = floor(l + 0.5), floor(r + 0.5), floor(t + 0.5), floor(b + 0.5)
	s.point, s.x, s.y = nil, nil, nil
	Settings:Touch()
	-- the game would otherwise keep its own copy of a dragged frame's place
	if bar.SetUserPlaced then pcall(bar.SetUserPlaced, bar, false) end
	Place()
end

-- right-click: the next way to grow, keeping the bar where it is on screen
function QuestBar:CycleGrow()
	if NBG:InCombat() then NBG:Print(L["The quest item bar changes when combat ends."]) return end
	if bar and bar:IsShown() then SavePlace() end
	local cur, order = Settings:Get("questbar.grow"), self.GROW_ORDER
	local nextDir = order[1]
	for i, d in ipairs(order) do if d == cur then nextDir = order[i % #order + 1] end end
	Settings:Set("questbar.grow", nextDir)
	local names = { up = L["up"], left = L["to the left"], down = L["down"], right = L["to the right"] }
	NBG:Print(L["Quest item bar: new items line up %s."], names[nextDir])
end

local function KeyText(i)
	if i > QuestBar.KEYS or not _G.GetBindingKey then return "" end
	local key = NBG.Call(GetBindingKey, "CLICK " .. NAME .. i .. ":LeftButton")
	if type(key) ~= "string" then return "" end
	if _G.GetBindingText then key = NBG.Call(GetBindingText, key, true) or key end
	key = key:gsub("SHIFT%-", "s"):gsub("CTRL%-", "c"):gsub("ALT%-", "a")
	return key:sub(1, 4)
end

local function Tooltip(b)
	local it = b.item
	if not it then return end
	GameTooltip:SetOwner(b, "ANCHOR_TOP")
	if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, it.id)
	elseif it.link then pcall(GameTooltip.SetHyperlink, GameTooltip, it.link) end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["Click: use it"], 0.55, 0.6, 0.7)
	GameTooltip:AddLine(L["Right-click: turn the way the bar grows"], 0.55, 0.6, 0.7)
	GameTooltip:AddLine(it.keep and L["Shift + right-click: take it off the bar"] or L["Shift + right-click: hide it from the bar"], 0.55, 0.6, 0.7)
	GameTooltip:Show()
end

local function ItemMenu(b)
	local it = b.item
	if not it then return end
	local name = it.link and it.link:match("%[(.-)%]") or ("#" .. it.id)
	W:Menu(b, {
		{ text = name, disabled = true },
		"-",
		{ text = it.keep and L["Take it off the bar"] or L["Hide it from the bar"], glyph = "x", onClick = function() QuestBar:Hide(it.id) end },
		{ text = L["Show hidden items again"], glyph = "eye", onClick = function() QuestBar:ShowHidden() end },
		{ text = Settings:Get("questbar.lock") and L["Unlock the bar (to move it)"] or L["Lock the bar"], glyph = "lock", onClick = function() Settings:Set("questbar.lock", not Settings:Get("questbar.lock")) end },
		{ text = L["Settings…"], glyph = "gear", onClick = function() NBG.Config:Open("questbar") end },
	})
end

-- an item dropped on the bar stays there
local function TakeCursor()
	if NBG:InCombat() or not _G.GetCursorInfo then return end
	local kind, id = GetCursorInfo()
	if kind ~= "item" then return end
	id = Num(id)
	if not id then return end
	if _G.ClearCursor then ClearCursor() end
	QuestBar:Keep(id)
end

local function Button(i)
	local b = buttons[i]
	if b then return b end
	b = CreateFrame("Button", NAME .. i, bar, "SecureActionButtonTemplate")
	b:RegisterForClicks("AnyUp", "AnyDown")
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetTexture(NBG.MEDIA .. "SlotFill")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 2, -2) b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.ring = b:CreateTexture(nil, "OVERLAY")
	b.ring:SetAllPoints()
	b.ring:SetTexture(NBG.MEDIA .. "SlotRing")
	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetAllPoints(b.icon)
	b.count = b:CreateFontString(nil, "OVERLAY")
	Skin:Font(b.count, "bold", 11, "OUTLINE", false)
	b.count:SetPoint("BOTTOMRIGHT", -3, 3)
	b.key = b:CreateFontString(nil, "OVERLAY")
	Skin:Font(b.key, "bold", 9, "OUTLINE", false)
	b.key:SetPoint("TOPRIGHT", -3, -3)
	b:SetScript("OnEnter", Tooltip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- the secure part uses the item on a left click; right-click is ours (no "type2")
	b:SetScript("PostClick", function(self, btn, down)
		if btn ~= "RightButton" or down then return end
		if _G.IsShiftKeyDown and IsShiftKeyDown() then ItemMenu(self) else QuestBar:CycleGrow() end
	end)
	b:SetScript("OnReceiveDrag", TakeCursor)
	buttons[i] = b
	return b
end

local function Paint(b)
	Skin:Paint(b.bg, "inset")
	Skin:Paint(b.ring, "border")
	Skin:Paint(b.key, "textDim")
	Skin:Paint(b.count, "text")
end

local function Make()
	if bar then return bar end
	bar = CreateFrame("Frame", "NetherBagsQuestBar", UIParent)
	bar:SetFrameStrata("MEDIUM")
	bar:SetClampedToScreen(true)
	bar:SetMovable(true)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetSize(40, 40)
	bar:Hide()
	Skin:Panel(bar)
	bar:SetScript("OnDragStart", function(self) if not Settings:Get("questbar.lock") and not NBG:InCombat() then self.moving = true self:StartMoving() end end)
	bar:SetScript("OnDragStop", function(self)
		if not self.moving then return end
		self.moving = nil
		self:StopMovingOrSizing()
		SavePlace()
	end)
	bar:SetScript("OnReceiveDrag", TakeCursor)
	bar:SetScript("OnMouseUp", function(self, btn)
		if btn == "RightButton" then QuestBar:CycleGrow() return end
		if _G.GetCursorInfo and GetCursorInfo() == "item" then TakeCursor() end
	end)
	bar:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["Quest items"], 1, 0.86, 0.55)
		local names = { up = L["up"], left = L["to the left"], down = L["down"], right = L["to the right"] }
		GameTooltip:AddLine((L["New items line up %s."]):format(names[Settings:Get("questbar.grow")] or ""), 1, 1, 1)
		if not Settings:Get("questbar.lock") then GameTooltip:AddLine(L["Drag with the left mouse button to move it"], 0.55, 0.6, 0.7) end
		GameTooltip:AddLine(L["Right-click: turn the way it grows (up, left, down, right)"], 0.55, 0.6, 0.7)
		GameTooltip:AddLine(L["Drop any item here to keep it on the bar"], 0.55, 0.6, 0.7)
		GameTooltip:Show()
	end)
	bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- the title strip along the top: it says what the bar is, and is a place to grab it
	bar.handle = W:Text(bar, 9, "textDim", "caps")
	bar.handle:SetPoint("TOPLEFT", bar, "TOPLEFT", 8, -4)
	bar.handle:SetText(L["Quest items"])
	-- the drop zone: shown while there is nothing on the bar but an item is kept or dragged
	bar.empty = W:Text(bar, 10, "textDim")
	bar.empty:SetPoint("CENTER")
	bar.empty:SetText(L["Drop an item here"])
	Skin:OnChange(function() for _, b in ipairs(buttons) do Paint(b) end end)
	Place()
	return bar
end

local function UpdateCooldowns()
	if not bar or not bar:IsShown() then return end
	local f = NBG.API("C_Container", "GetContainerItemCooldown") or _G.GetContainerItemCooldown
	for i, b in ipairs(buttons) do
		local it = b:IsShown() and b.item
		if it and f and it.bag and it.slot then
			local ok, start, dur, enable = pcall(f, it.bag, it.slot)
			if ok then
				if _G.CooldownFrame_Set then pcall(CooldownFrame_Set, b.cd, start or 0, dur or 0, enable)
				elseif (dur or 0) > 0 then b.cd:SetCooldown(start, dur) b.cd:Show() else b.cd:Hide() end
			end
		end
	end
end

-- counts only (allowed in combat): what is left of each item on the bar
local function UpdateCounts()
	if not bar then return end
	local total = {}
	for _, bag in ipairs(Containers:Bags("bags")) do
		if bag ~= Containers.KEYRING then
			for _, e in pairs(Containers:Read(bag) or {}) do
				if e and e.id then total[e.id] = (total[e.id] or 0) + (e.count or 1) end
			end
		end
	end
	for _, b in ipairs(buttons) do
		local it = b.item
		if it and b:IsShown() then
			local n = total[it.id] or 0
			b.count:SetText(n > 1 and tostring(n) or "")
			b.icon:SetDesaturated(n == 0)
			b.icon:SetAlpha(n == 0 and 0.45 or 1)
		end
	end
end

-- the full rebuild: which buttons, what each holds, the bar's size (never in combat)
function QuestBar:Rebuild()
	if not Settings:Get("questbar.on") then
		if bar and bar:IsShown() then
			if NBG:InCombat() then pending = true return end
			bar:Hide()
		end
		return
	end
	if NBG:InCombat() then pending = true UpdateCounts() return end
	pending = false
	Make()
	local list = self:Items()
	shownList = list
	local size = Settings:Get("questbar.size")
	local perRow = Settings:Get("questbar.perRow")
	local grow = Settings:Get("questbar.grow")
	local gap, pad, head = 4, 8, 14   -- head: the title strip at the top
	local n = #list
	local cols = max(1, min(perRow, n))
	local rows = max(1, ceil(n / cols))
	local vertical = grow == "up" or grow == "down"
	local across, down = cols, rows
	if vertical then across, down = rows, cols end
	for i, it in ipairs(list) do
		local b = Button(i)
		Paint(b)
		b.item = it
		b:SetSize(size, size)
		b:SetAttribute("type1", "item")
		b:SetAttribute("item", "item:" .. it.id)
		b.nbItem = it.id
		b.icon:SetTexture(it.icon)
		b.key:SetText(Settings:Get("questbar.keys") and KeyText(i) or "")
		local c, r = (i - 1) % cols, floor((i - 1) / cols)
		local x, y
		if vertical then x, y = r, c else x, y = c, r end
		b:ClearAllPoints()
		if grow == "left" then b:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -(pad + x * (size + gap)), -(pad + head + y * (size + gap)))
		elseif grow == "up" then b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", pad + x * (size + gap), pad + y * (size + gap))
		else b:SetPoint("TOPLEFT", bar, "TOPLEFT", pad + x * (size + gap), -(pad + head + y * (size + gap))) end
		b:Show()
	end
	for i = n + 1, #buttons do
		local b = buttons[i]
		b.item, b.nbItem = nil, nil
		b:SetAttribute("type1", nil)
		b:SetAttribute("item", nil)
		b:Hide()
	end
	local hideEmpty = Settings:Get("questbar.hideEmpty")
	if n == 0 then
		bar:SetSize(150, size + pad * 2 + head)
		bar.empty:ClearAllPoints()
		bar.empty:SetPoint("CENTER", 0, -head / 2)
		bar.empty:Show()
	else
		bar.empty:Hide()
		bar:SetSize(max(90, pad * 2 + across * size + (across - 1) * gap), pad * 2 + head + down * size + (down - 1) * gap)
	end
	bar:EnableMouse(true)
	Place()
	bar:SetShown(n > 0 or not hideEmpty)
	UpdateCounts()
	UpdateCooldowns()
	NBG:Fire("QUESTBAR_CHANGED", n)
end

function QuestBar:Refresh() NBG:Debounce("questbar", 0.2, function() QuestBar:Rebuild() end) end

function QuestBar:IsOn() return Settings:Get("questbar.on") and true or false end
function QuestBar:Count() return #shownList end
function QuestBar:Bar() return bar end
function QuestBar:Buttons() return buttons end

function QuestBar:SetShown(on)
	Settings:Set("questbar.on", on and true or false)
	if on then
		local n = #self:Items()
		if n == 0 then NBG:Print(L["Quest item bar on. No usable quest items right now: it shows when you get one (or drop any item on it)."])
		else NBG:Print(L["Quest item bar on: %d item(s)."], n) end
	end
	self:Rebuild()
	if NBG:InCombat() then NBG:Print(L["The quest item bar changes when combat ends."]) end
end

function QuestBar:Toggle() self:SetShown(not self:IsOn()) end

function QuestBar:Hide(id)
	id = Num(id)
	if not id then return end
	local hide, keep = Lists()
	if keep[id] then keep[id] = nil else hide[id] = true end
	Settings:Touch()
	self:Rebuild()
end

function QuestBar:Keep(id)
	id = Num(id)
	if not id then return end
	local hide, keep = Lists()
	hide[id] = nil
	keep[id] = true
	Settings:Touch()
	self:Rebuild()
end

function QuestBar:ShowHidden()
	local hide = Lists()
	local n = 0
	for k in pairs(hide) do hide[k] = nil n = n + 1 end
	Settings:Touch()
	if n > 0 then NBG:Print(L["%d hidden item(s) back on the quest item bar."], n) end
	self:Rebuild()
end

-- the options menu (right-click on the title bar's quest button)
function QuestBar:Menu(anchor)
	local function Tog(key) return function() Settings:Set(key, not Settings:Get(key)) end end
	local grow = Settings:Get("questbar.grow")
	local function G(v, label) return { text = label, checked = grow == v, onClick = function() Settings:Set("questbar.grow", v) end } end
	W:Menu(anchor, {
		{ text = L["Show the quest item bar"], checked = self:IsOn(), onClick = function() self:Toggle() end },
		"-",
		{ text = L["Only items you can use"], checked = Settings:Get("questbar.onlyUsable"), onClick = Tog("questbar.onlyUsable") },
		{ text = L["Hide the bar when it is empty"], checked = Settings:Get("questbar.hideEmpty"), onClick = Tog("questbar.hideEmpty") },
		{ text = L["Lock the bar"], checked = Settings:Get("questbar.lock"), onClick = Tog("questbar.lock") },
		G("up", L["Grow: up"]), G("left", L["Grow: to the left"]), G("down", L["Grow: down"]), G("right", L["Grow: to the right"]),
		"-",
		{ text = L["Show hidden items again"], glyph = "eye", onClick = function() self:ShowHidden() end },
		{ text = L["Move it back to the middle"], glyph = "arrow", onClick = function()
			local s = LayoutStore()
			s.point, s.x, s.y, s.l, s.r, s.t, s.b = nil, nil, nil, nil, nil, nil, nil
			Settings:Touch()
			Place()
		end },
		{ text = L["Settings…"], glyph = "gear", onClick = function() NBG.Config:Open("questbar") end },
	})
end

---------------------------------------------------------------------------------------------
-- what changes what
---------------------------------------------------------------------------------------------
NBG:Register("BAGS_CHANGED", function() if QuestBar:IsOn() then QuestBar:Refresh() end end)
NBG:Register("QUEST_NEEDS", function() if QuestBar:IsOn() then QuestBar:Refresh() end end)
NBG:Register("ITEMS_LOADED", function() wipe(spellCache) if QuestBar:IsOn() then QuestBar:Refresh() end end)
NBG:Register("COOLDOWNS", UpdateCooldowns)
NBG:Register("PROFILE_CHANGED", function() QuestBar:Refresh() end)
NBG:Register("SETTING_CHANGED", function(_, key)
	if type(key) == "string" and key:find("^questbar%.") then QuestBar:Rebuild() end
end)
NBG:On("QUEST_LOG_UPDATE", function() if QuestBar:IsOn() then NBG:Debounce("questbarLog", 0.5, function() QuestBar:Rebuild() end) end end)
NBG:On("UPDATE_BINDINGS", function() if QuestBar:IsOn() then QuestBar:Refresh() end end)
-- combat: the game freezes the secure buttons; the bar catches up when it ends
NBG:On("PLAYER_REGEN_ENABLED", function() if pending then QuestBar:Rebuild() end end)
NBG:Register("LOGIN", function() if QuestBar:IsOn() then NBG:After(2, function() QuestBar:Rebuild() end) end end)

-- the key bindings' names (Bindings.xml)
for i = 1, QuestBar.KEYS do
	_G["BINDING_NAME_CLICK " .. NAME .. i .. ":LeftButton"] = (L["Use quest item %d"]):format(i)
end
