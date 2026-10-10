--[[ NetherBags - UI/Window.lua
	The windows: one for the bags (it can also show the bank, the guild bank, Everywhere and
	currencies in Insight), one for the bank (opened at a banker, or from the bags window to see
	the bank offline) and one for the guild bank. Each window remembers its mode (One bag or
	Insight), position and size in the profile.

	  Windows:Get(id)               "bags" | "bank" | "guild" (made when first needed)
	  Windows:Toggle(id) / Open(id [, location]) / Close(id)
	  w:SetMode("onebag"|"insight") w:SetOwner(charKey) w:SetLocation(loc) w:Refresh()
	  w:Live()                      true when the window shows what the game holds right now
	  w:Entries()                   the items to show (live or saved), each an entry
	  w:BagList()                   { info } of the bags shown (sizes, families, icons)

	Views (UI/OneBag.lua, UI/Insight.lua) are made per window on first use (Mod:New(window)) and
	have :Show(), :Hide(), :Refresh([light]) and .shown. ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Windows = NBG:Module("Windows")
local Skin, W, Settings = NBG.Skin, NBG.Widgets, NBG.Settings
local Containers, Store, Buttons = NBG.Containers, NBG.Store, NBG.Buttons

local type, pairs, ipairs, max, min, floor = type, pairs, ipairs, math.max, math.min, math.floor

local wins = {}
Windows.list = wins

local TITLES = { bags = "", bank = L["Bank"], guild = L["Guild bank"] }
local DEFAULT_POS = { bags = { "BOTTOMRIGHT", -80, 120 }, bank = { "TOPLEFT", 60, -120 }, guild = { "TOPLEFT", 60, -120 } }

local Win = {}

function Win:LayoutStore()
	local f = Settings:Profile().layout.frames
	f[self.id] = f[self.id] or {}
	return f[self.id]
end

function Win:SavePosition()
	local s = self:LayoutStore()
	local point, _, _, x, y = self:GetPoint(1)
	s.point, s.x, s.y = point, floor((x or 0) + 0.5), floor((y or 0) + 0.5)
	Settings:Touch()
end

function Win:RestorePosition()
	local s = self:LayoutStore()
	self:ClearAllPoints()
	if s.point and s.x and s.y then
		self:SetPoint(s.point, UIParent, s.point, s.x, s.y)
	else
		local d = DEFAULT_POS[self.id] or DEFAULT_POS.bags
		self:SetPoint(d[1], UIParent, d[1], d[2], d[3])
	end
end

function Win:ModeKey() return "mode." .. (self.id == "bags" and "bags" or self.id) end
function Win:Mode() return Settings:Get(self:ModeKey()) end

function Win:SetMode(mode)
	if mode ~= "onebag" and mode ~= "insight" then return end
	Settings:Set(self:ModeKey(), mode)
	self:Refresh()
end

function Win:Live()
	local me = NBG:PlayerKey()
	if self.location == "bags" then return self.owner == me end
	if self.location == "bank" then return self.owner == me and Containers:BankOpen() end
	if self.location == "guild" then return NBG.GuildBank and NBG.GuildBank:IsOpen() or false end
	return false
end

function Win:SetOwner(key)
	self.owner = key or NBG:PlayerKey()
	self:Refresh()
end

function Win:SetLocation(loc)
	self.location = loc
	self:Refresh()
end

-- the bags of what is shown: live sizes, or the saved ones
function Win:BagList()
	if self.location == "guild" then return NBG.GuildBank and NBG.GuildBank:Tabs() or {} end
	if self:Live() then
		local out = {}
		for _, bag in ipairs(Containers:Bags(self.location)) do out[#out + 1] = Containers:Info(bag) end
		return out
	end
	return Store:Bags(self.owner, self.location)
end

function Win:Entries()
	if self.location == "guild" then return NBG.GuildBank and NBG.GuildBank:Entries() or {} end
	if self:Live() then return Containers:All(self.location) end
	return Store:Entries(self.owner, self.location)
end

-- the record age line for offline views
function Win:Age()
	if self:Live() then return nil end
	if self.location == "guild" then
		local g = NBG.GuildBank and NBG.GuildBank:Saved()
		return g and g.updated and (L["Saved"] .. " " .. Store.Ago(g.updated)) or L["Never seen: open the guild bank once"]
	end
	local c = Store:Char(self.owner)
	local t = c and c[self.location .. "Seen"]
	if not t then
		return self.location == "bank" and L["Never seen: visit a banker once with this character"] or L["Never seen: log in with this character once"]
	end
	return L["Saved"] .. " " .. Store.Ago(t)
end

function Win:Subtitle()
	local who = self.owner or NBG:PlayerKey()
	local loc = self.location
	local parts = { who }
	if loc == "bank" then parts[#parts + 1] = L["Bank"]
	elseif loc == "guild" then parts = { (NBG.GuildBank and NBG.GuildBank:Name()) or L["Guild bank"] }
	elseif loc == "everywhere" then parts = { L["Everywhere"] }
	elseif loc == "currency" then parts[#parts + 1] = L["Currencies"] end
	if loc == "bags" and who == NBG:PlayerKey() then
		local lvl = Store:Char(who) and Store:Char(who).level
		local _, class = NBG.Call(_G.UnitClass, "player")
		local cname = NBG.Call(_G.UnitClass, "player")
		if lvl and cname then parts[#parts + 1] = (L["Level"] .. " %d %s"):format(lvl, cname) end
	end
	return table.concat(parts, "  ·  ")
end

function Win:CurrentView()
	local mode = self:Mode()
	if self.location == "everywhere" or self.location == "currency" then mode = "insight" end
	return mode
end

function Win:Refresh(light)
	if not self:IsShown() then return end
	local mode = self:CurrentView()
	self.pill:SetValue(mode == "onebag" and 1 or 2)
	self.pill:SetShown(self.location ~= "everywhere" and self.location ~= "currency")
	self.subtitle:SetText(self:Subtitle())
	if self.bagBtn then
		local menu = self.location == "bags" and self:Live()
		self.bagBtn:SetEnabled(menu and true or false)
		if not menu and NBG.BagMenu and NBG.BagMenu:IsShown() then NBG.BagMenu:Hide() end
	end
	local view = self:View(mode)
	local other = self.views[mode == "onebag" and "insight" or "onebag"]
	if other and other.shown then other:Hide() end
	if not view.shown then view:Show() end
	NBG:Safe("view refresh", view.Refresh, view, light)
end

function Win:View(mode)
	self.views = self.views or {}
	local v = self.views[mode]
	if not v then
		local mod = mode == "onebag" and NBG.OneBag or NBG.Insight
		v = mod:New(self)
		self.views[mode] = v
	end
	return v
end

function Win:ApplyScale()
	local s = Settings:Get("look.scale") or 1
	self:SetScale(s)
end

local function MakeWindow(id)
	local f = CreateFrame("Frame", "NetherBagsWindow_" .. id, UIParent)
	for k, fn in pairs(Win) do f[k] = fn end
	f.id = id
	f.location = id
	f.owner = NBG:PlayerKey()
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetResizable(true)
	f:SetSize(560, 600)
	if f.SetResizeBounds then f:SetResizeBounds(420, 300, 1400, 1300) elseif f.SetMinResize then f:SetMinResize(420, 300) end
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) if not NBG.Settings:Get("window.lock") then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() self:SavePosition() end)
	f:Hide()
	Skin:Window(f)
	-- title bar
	-- the bag icon: in the bags window a button that opens the bag menu (UI/BagMenu.lua)
	f.bagBtn = W:IconButton(f, "backpack", 28, { scale = 0.72, role = "accent", onClick = function(self)
		if NBG.BagMenu then NBG.BagMenu:Toggle(f, self) end
	end, tip = { L["Bag menu"], L["What each bag holds, and its colour in One bag."] } })
	f.bagBtn:SetPoint("TOPLEFT", 10, -6)
	f.bagBtn:SetShown(id == "bags")
	f.logo = W:Glyph(f, "backpack", 20, "accent")
	f.logo:SetPoint("CENTER", f.bagBtn, "CENTER")
	if id == "bags" then f.logo:Hide() end
	f.title = W:Text(f, 17, "header", "title")
	f.title:SetPoint("LEFT", f.logo, "RIGHT", 8, 0)
	f.title:SetText("NetherBags")
	f.subtitle = W:Text(f, 11, "textDim")
	f.subtitle:SetPoint("LEFT", f.title, "RIGHT", 10, -1)
	f.close = W:IconButton(f, "x", 22, { onClick = function() f:Hide() end, tip = { L["Close"] } })
	f.close:SetPoint("TOPRIGHT", -10, -9)
	f.gear = W:IconButton(f, "gear", 22, { onClick = function() NBG.Config:Open() end, tip = { L["Settings"] } })
	f.gear:SetPoint("RIGHT", f.close, "LEFT", -4, 0)
	f.pill = W:Pill(f, { L["One bag"], L["Insight"] }, function(i) f:SetMode(i == 1 and "onebag" or "insight") end)
	f.pill:SetPoint("RIGHT", f.gear, "LEFT", -10, 0)
	f.line = f:CreateTexture(nil, "ARTWORK")
	f.line:SetTexture(NBG.MEDIA .. "Fade")
	f.line:SetPoint("TOPLEFT", 10, -40) f.line:SetPoint("TOPRIGHT", -10, -40) f.line:SetHeight(1)
	Skin:Paint(f.line, "accent", { alpha = 0.6 })
	-- the quest item bar's switch (bags window, both modes): click turns the bar on / off,
	-- right-click opens its options (Features/QuestBar.lua)
	if id == "bags" then
		f.questBtn = W:IconButton(f, "quest", 22, { role = "textDim", onClick = function(self, btn)
			local QB = NBG.QuestBar
			if not QB then return end
			if btn == "RightButton" then QB:Menu(self) else QB:Toggle() end
		end })
		f.questBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		f.questBtn:SetPoint("RIGHT", f.pill, "LEFT", -8, 0)
		f.questBtn:HookScript("OnEnter", function(self)
			local QB = NBG.QuestBar
			if not QB then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(L["Quest item bar"], 1, 0.86, 0.55)
			GameTooltip:AddLine(QB:IsOn() and (L["On: %d item(s) on the bar"]):format(QB:Count()) or L["Off"], 1, 1, 1)
			GameTooltip:AddLine(L["Your usable quest items on a small bar, one click away."], 0.9, 0.9, 0.9, true)
			GameTooltip:AddLine(L["Click: turn it on / off"], 0.55, 0.6, 0.7)
			GameTooltip:AddLine(L["Right-click: its options"], 0.55, 0.6, 0.7)
			GameTooltip:Show()
		end)
		f.questBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
		f.questBtn:SetActive(Settings:Get("questbar.on"))
		f.subtitle:SetPoint("RIGHT", f.questBtn, "LEFT", -8, 0)
	else
		f.subtitle:SetPoint("RIGHT", f.pill, "LEFT", -10, 0)
	end
	f.subtitle:SetJustifyH("LEFT")
	-- the content area views draw in
	f.body = CreateFrame("Frame", nil, f)
	f.body:SetPoint("TOPLEFT", 0, -42) f.body:SetPoint("BOTTOMRIGHT", 0, 0)
	-- resize grip (Insight)
	f.grip = CreateFrame("Button", nil, f)
	f.grip:SetSize(16, 16)
	f.grip:SetPoint("BOTTOMRIGHT", -2, 2)
	f.grip.t = W:Glyph(f.grip, "grip", 12, "faint")
	f.grip.t:SetPoint("CENTER")
	f.grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
	-- while it is being resized the rows wrap and unwrap as it goes, not only when let go
	f:SetScript("OnSizeChanged", function(self)
		if not self:IsShown() then return end
		if self:CurrentView() ~= "insight" then return end   -- One bag sizes itself to its grid
		NBG:Debounce("nbResize" .. tostring(self), 0.04, function() if self:IsShown() then self:Refresh(true) end end)
	end)
	f.grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		local s = f:LayoutStore()
		s.w, s.h = floor(f:GetWidth() + 0.5), floor(f:GetHeight() + 0.5)
		f:SavePosition()
		f:Refresh(true)
	end)
	f:SetScript("OnShow", function(self)
		self:ApplyScale()
		self:RestorePosition()
		self.shownAt = NBG:Clock()
		self.showToken = (self.showToken or 0) + 1   -- Insight's held row layout starts over
		if self.id == "bags" and _G.PlaySound and _G.SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then pcall(PlaySound, SOUNDKIT.IG_BACKPACK_OPEN) end
		self:Refresh()
		NBG:Fire("WINDOW_SHOWN", self.id)
	end)
	f:SetScript("OnHide", function(self)
		self.showToken = (self.showToken or 0) + 1   -- the held row layout ends with the window
		if self.id == "bags" and _G.PlaySound and _G.SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE then pcall(PlaySound, SOUNDKIT.IG_BACKPACK_CLOSE) end
		for _, v in pairs(self.views or {}) do if v.shown then v:Hide() end end
		W:CloseMenu()
		-- back to this character and the window's own place next time
		self.owner = NBG:PlayerKey()
		self.location = self.id
		NBG:Fire("WINDOW_HIDDEN", self.id)
	end)
	if _G.UISpecialFrames then table.insert(UISpecialFrames, f:GetName()) end
	return f
end

function Windows:Get(id)
	if not wins[id] then wins[id] = MakeWindow(id) end
	return wins[id]
end

function Windows:Open(id, location)
	local w = self:Get(id)
	if location then w.location = location end
	if NBG:InCombat() and w:IsProtected() then
		NBG:AfterCombat("open " .. id, function() self:Open(id, location) end)
		return w
	end
	if w:IsShown() then w:Refresh() else w:Show() end
	return w
end

function Windows:Close(id)
	local w = wins[id]
	if not w or not w:IsShown() then return end
	if NBG:InCombat() and w:IsProtected() then
		NBG:AfterCombat("close " .. id, function() self:Close(id) end)
		return
	end
	w:Hide()
end

function Windows:Toggle(id)
	local w = self:Get(id)
	if w:IsShown() then self:Close(id) else self:Open(id) end
end

function Windows:IsOpen(id) return wins[id] and wins[id]:IsShown() or false end

function Windows:RefreshAll(light)
	for _, w in pairs(wins) do if w:IsShown() then w:Refresh(light) end end
end

-- what changes what
NBG:Register("BAGS_CHANGED", function() Windows:RefreshAll() end)
NBG:Register("ITEMS_LOADED", function() Containers:Invalidate() Windows:RefreshAll() end)
NBG:Register("MARKS_CHANGED", function() Windows:RefreshAll() end)
NBG:Register("GROUPS_CHANGED", function() Windows:RefreshAll() end)
NBG:Register("PROFILE_CHANGED", function()
	for _, w in pairs(wins) do if w:IsShown() then w:RestorePosition() end end
	if wins.bags and wins.bags.questBtn then wins.bags.questBtn:SetActive(Settings:Get("questbar.on")) end
	Windows:RefreshAll()
end)
NBG:Register("SETTING_CHANGED", function(_, key)
	if key == "look.scale" then for _, w in pairs(wins) do w:ApplyScale() end end
	if key == "questbar.on" and wins.bags and wins.bags.questBtn then wins.bags.questBtn:SetActive(Settings:Get("questbar.on")) end
	NBG:Debounce("settingsRefresh", 0.05, function() Windows:RefreshAll() end)
end)
NBG:Register("MONEY", function() Windows:RefreshAll(true) end)
NBG:Register("CURRENCY", function() Windows:RefreshAll(true) end)
NBG:Register("STORE_CHANGED", function()
	for _, w in pairs(wins) do if w:IsShown() and not w:Live() then NBG:Debounce("storeRefresh", 0.2, function() Windows:RefreshAll() end) end end
end)
NBG:Register("FIND_EVERYWHERE", function(_, text)
	local w = Windows:Open("bags", "everywhere")
	NBG:Fire("SEARCH_SET", "bags", text)
end)

-- a finished sort moved everything on purpose: the held row layouts start over
NBG:Register("SORT", function(_, running, mode)
	if running or mode then return end     -- (merging and routing by themselves keep the layout)
	for _, w in pairs(Windows.list or {}) do w.showToken = (w.showToken or 0) + 1 end
end)
-- what the game says about items changed (level, skills, quests, prices): repaint
for _, m in ipairs({ "USABLE_CHANGED", "QUEST_NEEDS", "PRICES_LEARNED", "TRACKED_CHANGED" }) do
	NBG:Register(m, function() NBG:Debounce("repaintItems", 0.2, function() Windows:RefreshAll(true) end) end)
end
