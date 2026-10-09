--[[ NetherBags - UI/Conflicts.lua
	Other bag addons, checked at login (and with /nbags conflicts):

	  replacements   addons that replace the bags themselves (Bagnon, Baganator, BetterBags, AdiBags,
	                 GudaBags...). Two of them fight over the same windows, so the player keeps one:
	                 "Keep NetherBags" turns the other one off (with its own companion addons),
	                 "Keep <other>" turns NetherBags off. Then the interface reloads to apply it.
	  helpers        addons that overlap one part: junk sellers (both would sell at a vendor), tooltip
	                 counts (two sets of "owned by" lines), and addons that only change the game's own
	                 bag windows (which NetherBags hides). Each row: Turn it off, Keep both (not asked
	                 again for that addon), and for tooltip counts: Hide NetherBags' own counts.

	Addons are turned off for every character (as the game's addon list does), only when the player
	clicks; nothing is ever turned off by itself. ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Conflicts = NBG:Module("Conflicts")
local Skin, W, Settings = NBG.Skin, NBG.Widgets, NBG.Settings

local ipairs, pairs, type = ipairs, pairs, type

-- each family: the addon players know (title), the folders that are its parts (exact names) and
-- folder-name prefixes of its plugins
Conflicts.REPLACEMENTS = {
	{ id = "Bagnon", title = "Bagnon", parts = { "Bagnon", "Bagnon_Bank", "Bagnon_GuildBank", "Bagnon_Config", "Bagnon_Masque", "Bagnon_Scrap", "Bagnon_RequiredLevel" }, prefixes = { "Bagnon_" }, shared = { "BagBrother" } },
	{ id = "Bagnonium", title = "Bagnonium", parts = { "Bagnonium", "Bagnonium_Bank", "Bagnonium_GuildBank", "Bagnonium_Config", "Combuctor" }, prefixes = { "Bagnonium_" }, shared = { "BagBrother" } },
	{ id = "Baganator", title = "Baganator", parts = { "Baganator" }, prefixes = { "Baganator_" } },
	{ id = "BetterBags", title = "BetterBags", parts = { "BetterBags" }, prefixes = { "BetterBags_", "BetterBags-" } },
	{ id = "AdiBags", title = "AdiBags", parts = { "AdiBags", "AdiBags_Config" }, prefixes = { "AdiBags_", "AdiBags-" } },
	{ id = "GudaBags", title = "GudaBags", parts = { "GudaBags" } },
	{ id = "BagSmith", title = "BagSmith", parts = { "BagSmith" } },
	{ id = "ForeverBag", title = "Forever Bag", parts = { "ForeverBag" } },
	{ id = "ForeverBags", title = "ForeverBags", parts = { "ForeverBags" } },
	{ id = "ForeverForge_Bags", title = "ForeverForge Bags", parts = { "ForeverForge_Bags" } },
	{ id = "EUIStandaloneBags", title = "EUI Bags", parts = { "EUIStandaloneBags" } },
	{ id = "VoidBags", title = "VoidBags", parts = { "VoidBags" } },
	{ id = "WicksBags", title = "Wick's Bags", parts = { "WicksBags" } },
	{ id = "LazyBags", title = "LazyBags", parts = { "LazyBags" } },
	{ id = "ArkInventory", title = "ArkInventory", parts = { "ArkInventory" }, prefixes = { "ArkInventory" } },
	{ id = "Inventorian", title = "Inventorian", parts = { "Inventorian" } },
	{ id = "LiteBag", title = "LiteBag", parts = { "LiteBag" } },
	{ id = "Sorted", title = "Sorted", parts = { "Sorted" } },
	{ id = "OneBag3", title = "OneBag3", parts = { "OneBag3", "OneBank3" } },
	{ id = "Bagshui", title = "Bagshui", parts = { "Bagshui" } },
	{ id = "BaudBag", title = "BaudBag", parts = { "BaudBag" } },
	{ id = "DJBags", title = "DJBags", parts = { "DJBags" } },
}

Conflicts.HELPERS = {
	{ id = "Scrap", title = "Scrap", parts = { "Scrap", "Scrap_Config", "Scrap_Merchant" }, kind = "sell" },
	{ id = "BagWarden", title = "BagWarden", parts = { "BagWarden" }, kind = "sell" },
	{ id = "ForeverForge", title = "ForeverForge", parts = { "ForeverForge" }, kind = "sell" },
	{ id = "BagSync", title = "BagSync", parts = { "BagSync" }, kind = "tooltip" },
	{ id = "BankTabs", title = "Bank Tabs", parts = { "BankTabs" }, kind = "tooltip" },
	{ id = "MorthenBags", title = "MorthenBags", parts = { "MorthenBags" }, kind = "tooltip" },
	{ id = "Syndicator", title = "Syndicator", parts = { "Syndicator" }, kind = "tooltip" },
	{ id = "Altoholic", title = "Altoholic", parts = { "Altoholic" }, prefixes = { "Altoholic_" }, kind = "tooltip" },
	{ id = "AKForeverBags", title = "AKForeverBags", parts = { "AKForeverBags" }, kind = "blizzard" },
	{ id = "TheBag", title = "TheBag", parts = { "TheBag" }, kind = "blizzard" },
	{ id = "ForeverBagMover", title = "Forever Bag Mover", parts = { "ForeverBagMover" }, kind = "blizzard" },
	{ id = "OpenAmmoBagSeparately", title = "Open Ammo Bag Separately", parts = { "OpenAmmoBagSeparately" }, kind = "blizzard" },
}

Conflicts.KIND_TEXT = {
	sell = L["Also sells junk at vendors: the two would sell at the same time."],
	tooltip = L["Also adds \"owned by\" counts to item tooltips: you'd see them twice."],
	blizzard = L["Changes the game's own bag windows, which NetherBags hides: it does nothing while NetherBags shows your bags."],
}

---------------------------------------------------------------------------------------------
-- the game's addon list
---------------------------------------------------------------------------------------------
local function AO(fn) return NBG.API("C_AddOns", fn) or _G[fn] end

local function Loaded(name)
	local f = AO("IsAddOnLoaded")
	return f and NBG.Call(f, name) and true or false
end

local function AllNames()
	local out = {}
	local n = NBG.Num(NBG.Call(AO("GetNumAddOns"))) or 0
	local info = AO("GetAddOnInfo")
	for i = 1, n do
		local name = info and NBG.Str((NBG.Call(info, i)))
		if name then out[#out + 1] = name end
	end
	return out
end

-- the folders of a family that are loaded now
local function LoadedParts(fam, names)
	local out, seen = {}, {}
	local function Add(n) if not seen[n] and Loaded(n) then seen[n] = true out[#out + 1] = n end end
	for _, n in ipairs(fam.parts or {}) do Add(n) end
	for _, p in ipairs(fam.prefixes or {}) do
		for _, n in ipairs(names) do if n:sub(1, #p) == p then Add(n) end end
	end
	return out
end

local function Kept() local g = NBG.db and NBG.db.global if not g then return {} end g.conflictsKept = type(g.conflictsKept) == "table" and g.conflictsKept or {} return g.conflictsKept end

-- what is in the way now: { replacements = { { fam, parts } }, helpers = { { fam, parts } } }
function Conflicts:Find(all)
	local names = AllNames()
	local found = { replacements = {}, helpers = {} }
	for _, fam in ipairs(self.REPLACEMENTS) do
		local parts = LoadedParts(fam, names)
		if #parts > 0 and Loaded(fam.parts[1]) then found.replacements[#found.replacements + 1] = { fam = fam, parts = parts } end
	end
	-- Syndicator is Baganator's own data addon: with Baganator it goes with Baganator's row
	local hasBaganator = false
	for _, r in ipairs(found.replacements) do if r.fam.id == "Baganator" then hasBaganator = true end end
	local kept = Kept()
	for _, fam in ipairs(self.HELPERS) do
		local parts = LoadedParts(fam, names)
		if #parts > 0 and (all or not kept[fam.id]) and not (fam.id == "Syndicator" and hasBaganator) then
			found.helpers[#found.helpers + 1] = { fam = fam, parts = parts }
		end
	end
	return found
end

-- turn addons off: for every character, as the game's addon list does (and for this one, for sure)
local function Disable(names)
	local f = AO("DisableAddOn")
	if not f then return false end
	local me = _G.UnitName and UnitName("player")
	local state = AO("GetAddOnEnableState")
	for _, n in ipairs(names) do
		pcall(f, n)
		local s = state and NBG.Num(NBG.Call(state, n, me))
		if s and s > 0 and me then pcall(f, n, me) end
	end
	local save = AO("SaveAddOns")
	if save then pcall(save) end
	return true
end
Conflicts.Disable = Disable

local function Reload()
	local r = NBG.API("C_UI", "Reload") or _G.ReloadUI
	if r then r() end
end

-- the companion addons a family shares with another (BagBrother: Bagnon and Bagnonium) go only
-- when no family that needs them stays on
local function WithShared(list, keepingOthers)
	local out = {}
	for _, n in ipairs(list.parts) do out[#out + 1] = n end
	for _, sh in ipairs(list.fam.shared or {}) do
		local needed = false
		for _, other in ipairs(keepingOthers or {}) do
			for _, s2 in ipairs(other.fam.shared or {}) do if s2 == sh then needed = true end end
		end
		if not needed and Loaded(sh) then out[#out + 1] = sh end
	end
	return out
end

---------------------------------------------------------------------------------------------
-- the dialog
---------------------------------------------------------------------------------------------
local WIDTH, PAD = 620, 20
local frame

local function Build()
	local f = CreateFrame("Frame", "NetherBagsConflicts", UIParent)
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
	c.logo:SetTexture(NBG.MEDIA .. "Logo")
	c.logo:SetSize(48, 48)
	c.logo:SetPoint("TOPLEFT", PAD - 4, -14)
	c.title = W:Text(c, 18, "header", "title")
	c.title:SetPoint("TOPLEFT", PAD + 54, -18)
	c.sub = W:Text(c, 11.5, "textDim")
	c.sub:SetWordWrap(true)
	c.sub:SetJustifyH("LEFT") c.sub:SetJustifyV("TOP")
	c.sub:SetWidth(WIDTH - PAD * 2 - 54 - 24)
	c.sub:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -5)
	c.close = W:IconButton(c, "x", 20, { onClick = function() f:Hide() end, tip = { L["Ask me next time"] } })
	c.close:SetPoint("TOPRIGHT", -8, -8)
	c.rule = c:CreateTexture(nil, "ARTWORK")
	c.rule:SetTexture(Skin.WHITE)
	c.rule:SetHeight(1)
	Skin:Paint(c.rule, "accentLo", { alpha = 0.45 })
	c.rows = {}
	c.buttons = {}
	f:Hide()
	if _G.UISpecialFrames then table.insert(UISpecialFrames, "NetherBagsConflicts") end
	return f
end

local function Row(c, i)
	local r = c.rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, c)
	r:SetWidth(WIDTH - PAD * 2)
	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	Skin:Rounded(r.bg)
	Skin:Paint(r.bg, "bgAlt")
	r.edge = r:CreateTexture(nil, "BORDER")
	r.edge:SetAllPoints()
	Skin:Rounded(r.edge, true)
	Skin:Paint(r.edge, "border")
	r.name = W:Text(r, 13, "header", "bold")
	r.name:SetPoint("TOPLEFT", 12, -9)
	r.parts = W:Text(r, 10, "faint")
	r.parts:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
	r.text = W:Text(r, 11, "text")
	r.text:SetWordWrap(true)
	r.text:SetJustifyH("LEFT") r.text:SetJustifyV("TOP")
	r.text:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
	r.text:SetWidth(WIDTH - PAD * 2 - 24 - 250)
	r.btns = {}
	for k = 1, 3 do
		local b = W:Button(r, "", 80, 24, { size = 10.5 })
		r.btns[k] = b
	end
	c.rows[i] = r
	return r
end

local function Layout()
	local c = frame.content
	local y = 18 + (c.title:GetStringHeight() or 20) + 5 + (c.sub:GetStringHeight() or 30) + 16
	c.rule:ClearAllPoints()
	c.rule:SetPoint("TOPLEFT", PAD, -y) c.rule:SetPoint("TOPRIGHT", -PAD, -y)
	y = y + 14
	for _, r in ipairs(c.rows) do
		if r:IsShown() then
			local h = 9 + (r.name:GetStringHeight() or 14) + 4 + math.max(r.text:GetStringHeight() or 14, 14) + 12
			h = math.max(h, 58)
			r:SetHeight(h)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", PAD, -y)
			y = y + h + 8
		end
	end
	y = y + 6
	local x = WIDTH - PAD
	for i = #c.buttons, 1, -1 do
		local b = c.buttons[i]
		if b:IsShown() then
			b:ClearAllPoints()
			b:SetPoint("TOPRIGHT", c, "TOPLEFT", x, -y)
			x = x - b:GetWidth() - 8
		end
	end
	frame:SetHeight(y + 30 + 18)
end

local function SetButtons(defs)
	local c = frame.content
	for _, b in ipairs(c.buttons) do b:Hide() end
	for i, d in ipairs(defs) do
		local b = c.buttons[i]
		if not b then b = W:Button(c, "", 120, 30, { size = 12 }) c.buttons[i] = b end
		b:SetStyle(d.style or "dark")
		b:SetLabel(d.label)
		b:SetWidth(math.max(110, (b.label:GetStringWidth() or 60) + 36))
		b:SetScript("OnClick", function() NBG:Safe("conflicts " .. d.label, d.onClick) end)
		b:Show()
	end
end

-- the rows' own buttons (helpers): a choice per row
local function RowButtons(r, defs)
	local x = -12
	for k = 3, 1, -1 do
		local b, d = r.btns[k], defs[k]
		if d then
			b:SetStyle(d.style or "dark")
			b:SetLabel(d.label)
			b:SetWidth(math.max(70, (b.label:GetStringWidth() or 40) + 24))
			b:ClearAllPoints()
			b:SetPoint("RIGHT", r, "RIGHT", x, 0)
			x = x - b:GetWidth() - 6
			b:SetScript("OnClick", function() NBG:Safe("conflict row", d.onClick) end)
			b:Show()
		else
			b:Hide()
		end
	end
end

function Conflicts:Showing() return frame and frame:IsShown() or false end

function Conflicts:ShowReplacements(list)
	frame = frame or Build()
	local c = frame.content
	c.title:SetText(L["Another bag addon is on"])
	local names = {}
	for _, r in ipairs(list) do names[#names + 1] = r.fam.title end
	c.sub:SetText((L["%s also replaces your bags. Two bag addons fight over the same windows: the bag key opens both, the bank closes for both, both sort and sell. Keep one of them; the other is turned off and the interface reloads."]):format(table.concat(names, ", ")))
	for _, r in ipairs(c.rows) do r:Hide() end
	for i, r in ipairs(list) do
		local row = Row(c, i)
		row.name:SetText(r.fam.title)
		row.parts:SetText(#r.parts > 1 and ("(" .. table.concat(r.parts, ", ") .. ")") or "")
		row.text:SetText(L["Replaces your bags (and usually the bank)."])
		RowButtons(row, {})
		row:Show()
	end
	local buttons = {
		{ label = L["Keep NetherBags"], style = "gold", onClick = function()
			local off = {}
			for _, r in ipairs(list) do for _, n in ipairs(WithShared(r)) do off[#off + 1] = n end end
			Disable(off)
			Reload()
		end },
	}
	if #list == 1 then
		buttons[#buttons + 1] = { label = (L["Keep %s"]):format(list[1].fam.title), onClick = function() Disable({ "NetherBags" }) Reload() end }
	else
		buttons[#buttons + 1] = { label = L["Keep the others"], onClick = function() Disable({ "NetherBags" }) Reload() end }
	end
	SetButtons(buttons)
	Layout()
	frame:ClearAllPoints() frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	frame:Show()
	NBG:After(0.05, function() if frame:IsShown() then Skin:Redraw() Layout() end end)
end

function Conflicts:ShowHelpers(list)
	frame = frame or Build()
	local c = frame.content
	c.title:SetText(L["Addons that overlap with NetherBags"])
	c.sub:SetText(L["These don't replace your bags, but they do part of what NetherBags does. Choose for each; nothing changes until you click."])
	for _, r in ipairs(c.rows) do r:Hide() end
	local pendingOff = {}
	local function Refresh() end
	for i, h in ipairs(list) do
		local row = Row(c, i)
		row.name:SetText(h.fam.title)
		row.parts:SetText("")
		row.text:SetText(self.KIND_TEXT[h.fam.kind] or "")
		local function Mark(state, label)
			row.state = state
			row.parts:SetText("|cff8c96b0" .. label .. "|r")
		end
		local defs = {
			{ label = L["Turn off"], style = "red", onClick = function() pendingOff[h.fam.id] = h.parts Mark("off", L["will be turned off"]) end },
			{ label = L["Keep both"], onClick = function() pendingOff[h.fam.id] = nil Kept()[h.fam.id] = true Mark("keep", L["kept"]) end },
		}
		if h.fam.kind == "tooltip" then
			defs[3] = { label = L["Hide our counts"], onClick = function()
				pendingOff[h.fam.id] = nil Kept()[h.fam.id] = true
				Settings:Set("tooltip.counts", false)
				Mark("ours", L["NetherBags' counts hidden"])
			end }
		end
		RowButtons(row, defs)
		row:Show()
	end
	SetButtons({
		{ label = L["Apply"], style = "gold", onClick = function()
			local off = {}
			for _, parts in pairs(pendingOff) do for _, n in ipairs(parts) do off[#off + 1] = n end end
			if #off > 0 then Disable(off) Reload() else frame:Hide() end
		end },
	})
	Layout()
	frame:ClearAllPoints() frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	frame:Show()
	NBG:After(0.05, function() if frame:IsShown() then Skin:Redraw() Layout() end end)
end

-- at login: replacements first (they matter most); the helpers on a login without replacements
function Conflicts:Check(all)
	local found = self:Find(all)
	if #found.replacements > 0 then self:ShowReplacements(found.replacements) return true end
	if #found.helpers > 0 then self:ShowHelpers(found.helpers) return true end
	return false
end

function Conflicts:Hide() if frame then frame:Hide() end end

NBG:Register("LOGIN", function() NBG:After(3, function() Conflicts:Check(false) end) end)
