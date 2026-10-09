--[[ NetherBags - Data/Groups.lua
	Insight sorts every item into one group. Groups come in two kinds:

	  built-in   New items, Upgrades, Gear > Weapons / Armor / Jewelry, Consumables, Trade goods,
	             Reagents, Gems, Recipes, Quest items, Containers, Ammo, Keys, Miscellaneous, Junk
	  custom     made by the player in Settings > Groups: a name, an icon, a colour, rules (ALL or
	             ANY of them), "own section in One bag", "start collapsed", "sell at vendors"

	An item goes to: its "Always put in" group (Marks), else New items (if on), else Junk, else the
	first group in the player's order whose test it passes. Junk is always shown last.

	  Groups:List()                      the groups in display order: { id, label, glyph, color,
	                                     custom, def }
	  Groups:Classify(entry) -> id, sub  sub: a second label (e.g. the trade good's kind)
	  Groups:Get(id)                     one group
	  Groups:NewCustom() -> id / Groups:SaveCustom(id, def) / Groups:DeleteCustom(id)
	  Groups:Move(id, delta)             change the order
	  Groups:Sanitize(t)                 clean imported group data
	  Groups.CATEGORIES                  the category row filters (Insight) ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Groups = NBG:Module("Groups")
local Rules, Items, Marks, Settings = NBG.Rules, NBG.Items, NBG.Marks, NBG.Settings

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local Num, Str = NBG.Num, NBG.Str

local JEWEL = { INVTYPE_FINGER = true, INVTYPE_NECK = true, INVTYPE_TRINKET = true }
local function I(e) return Rules.InfoOf(e) end
local function Class(e) local i = I(e) if i then return i.classID end return e.id and (Items:Instant(e.id)) end
local function SubOf(e) local i = I(e) return i and i.subType ~= "" and i.subType or nil end

Groups.BUILTIN = {
	{ id = "new", label = L["New items"], glyph = "new", color = { 0.98, 0.87, 0.59 }, test = function(e) return e.new end },
	{ id = "recent", label = L["Looted this session"], glyph = "star", color = { 0.43, 0.82, 0.96 }, test = function(e) return Settings:Get("insight.recentGroup") and Items:IsRecent(e) end },
	{ id = "upgrade", label = L["Upgrades"], glyph = "up", color = { 0.35, 0.86, 0.43 }, test = function(e) return e.live ~= false and Items:Upgrade(e) end },
	{ id = "weapons", label = L["Gear"] .. " > " .. L["Weapons"], glyph = "sword", test = function(e) return Class(e) == 2 end },
	{ id = "armor", label = L["Gear"] .. " > " .. L["Armor"], glyph = "chest", test = function(e) local i = I(e) return Class(e) == 4 and not (i and JEWEL[i.equipLoc]) end },
	{ id = "jewelry", label = L["Gear"] .. " > " .. L["Jewelry"], glyph = "ring", test = function(e) local i = I(e) return Class(e) == 4 and i and JEWEL[i.equipLoc] end },
	{ id = "consumables", label = L["Consumables"], glyph = "potion", test = function(e) return Class(e) == 0 end, split = SubOf },
	{ id = "tradegoods", label = L["Trade goods"], glyph = "trade", test = function(e) return Class(e) == 7 end, split = SubOf },
	{ id = "reagents", label = L["Reagents"], glyph = "leaf", test = function(e) return Class(e) == 5 end },
	{ id = "gems", label = L["Gems"], glyph = "gem", test = function(e) return Class(e) == 3 end },
	{ id = "recipes", label = L["Recipes"], glyph = "scroll", test = function(e) return Class(e) == 9 end },
	{ id = "quest", label = L["Quest items"], glyph = "quest", color = { 0.98, 0.87, 0.59 }, test = function(e) return e.quest or Class(e) == 12 or Items:QuestNeeded(e) end },
	{ id = "containers", label = L["Containers"], glyph = "bag", test = function(e) return Class(e) == 1 end },
	{ id = "ammo", label = L["Ammo"], glyph = "arrow", test = function(e) local c = Class(e) return c == 6 or c == 11 end },
	{ id = "keys", label = L["Keys"], glyph = "key", test = function(e) return Class(e) == 13 end },
	{ id = "misc", label = L["Miscellaneous"], glyph = "star", test = function() return true end },
	{ id = "junk", label = L["Junk"], glyph = "junk", color = { 0.75, 0.75, 0.75 }, test = function(e) return Marks:IsJunk(e) end },
}
local BUILT = {}
for _, g in ipairs(Groups.BUILTIN) do BUILT[g.id] = g end
Groups.BUILT = BUILT

-- the category row (Insight): independent of the groups, by what an item is
Groups.CATEGORIES = {
	{ id = "all", label = L["All items"], glyph = "all", test = function() return true end },
	{ id = "weapons", label = L["Weapons"], glyph = "sword", test = function(e) return Class(e) == 2 end },
	{ id = "armor", label = L["Armor"], glyph = "chest", test = function(e) local i = I(e) return Class(e) == 4 and not (i and JEWEL[i.equipLoc]) end },
	{ id = "jewelry", label = L["Jewelry"], glyph = "ring", test = function(e) local i = I(e) return Class(e) == 4 and i and JEWEL[i.equipLoc] end },
	{ id = "consumables", label = L["Consumables"], glyph = "potion", test = function(e) return Class(e) == 0 end },
	{ id = "trade", label = L["Trade goods"], glyph = "trade", test = function(e) local c = Class(e) return c == 7 or c == 5 end },
	{ id = "gems", label = L["Gems"], glyph = "gem", test = function(e) return Class(e) == 3 end },
	{ id = "recipes", label = L["Recipes"], glyph = "scroll", test = function(e) return Class(e) == 9 end },
	{ id = "quest", label = L["Quest items"], glyph = "quest", test = function(e) return e.quest or Class(e) == 12 or Items:QuestNeeded(e) end },
	{ id = "containers", label = L["Containers & ammo"], glyph = "bag", test = function(e) local c = Class(e) return c == 1 or c == 6 or c == 11 end },
	{ id = "misc", label = L["Miscellaneous"], glyph = "star", test = function(e) local c = Class(e) return c == 15 or c == 13 or c == nil end },
}
Groups.JUNK_CATEGORY = { id = "junk", label = L["Junk"], glyph = "junk", test = function(e) return Marks:IsJunk(e) end }

local DEFAULT_ORDER = { "new", "recent", "upgrade", "weapons", "armor", "jewelry", "consumables", "tradegoods", "reagents", "gems", "recipes", "quest", "containers", "ammo", "keys", "misc", "junk" }

local function G() return Settings:Profile().groups end

-- the player's order, completed: every built-in once, every custom once, junk last
local orderCache
NBG:Register("GROUPS_CHANGED", function() orderCache = nil end)
NBG:Register("PROFILE_CHANGED", function() orderCache = nil end)

function Groups:Order()
	if orderCache then
		local copy = {}
		for i, id in ipairs(orderCache) do copy[i] = id end
		return copy
	end
	local out = self:BuildOrder()
	orderCache = out
	local copy = {}
	for i, id in ipairs(out) do copy[i] = id end
	return copy
end

function Groups:BuildOrder()
	local g = G()
	local out, seen = {}, {}
	for _, id in ipairs(g.order) do
		if not seen[id] and (BUILT[id] or g.custom[id]) and id ~= "junk" then out[#out + 1] = id seen[id] = true end
	end
	-- customs not yet placed go just after New items (before the built-ins: a group of your own is more specific)
	local customs = {}
	for id in pairs(g.custom) do if not seen[id] then customs[#customs + 1] = id end end
	table.sort(customs)
	if #customs > 0 then
		local at = 1
		for i, id in ipairs(out) do if id == "new" then at = i end end
		for k, id in ipairs(customs) do table.insert(out, math.min(#out + 1, at + k), id) seen[id] = true end
	end
	for _, id in ipairs(DEFAULT_ORDER) do
		if not seen[id] and id ~= "junk" then
			-- a built-in missing from the saved order goes where it is by default
			local pos = #out + 1
			for i, o in ipairs(out) do
				local di
				for j, d in ipairs(DEFAULT_ORDER) do if d == o then di = j end end
				local dme
				for j, d in ipairs(DEFAULT_ORDER) do if d == id then dme = j end end
				if di and dme and di > dme then pos = i break end
			end
			table.insert(out, pos, id)
			seen[id] = true
		end
	end
	out[#out + 1] = "junk"
	return out
end

function Groups:Get(id)
	local c = G().custom[id]
	if c then
		return { id = id, label = c.name or L["My group"], glyph = c.icon or "star", color = c.color, custom = true, def = c }
	end
	local b = BUILT[id]
	if b then return { id = id, label = b.label, glyph = b.glyph, color = b.color, custom = false, def = b } end
	return nil
end

function Groups:List()
	local out = {}
	for _, id in ipairs(self:Order()) do
		local g = self:Get(id)
		if g and not G().off[id] then out[#out + 1] = g end
	end
	return out
end

function Groups:Classify(e)
	local g = G()
	local a = e.id and Marks:Assigned(e.id)
	if a and (g.custom[a] or BUILT[a]) and not g.off[a] then return a end
	if e.new and Settings:Get("insight.newGroup") and not g.off.new then return "new" end
	-- what a quest in the log asks for is a quest item, whatever it is
	if not g.off.quest and Items:QuestNeeded(e) then return "quest" end
	if Marks:IsJunk(e) then return "junk" end
	if not orderCache then self:Order() end
	for _, id in ipairs(orderCache) do
		if id ~= "new" and id ~= "junk" and not g.off[id] then
			local c = g.custom[id]
			if c then
				if Rules:Match(e, c.rules, c.match) then return id end
			else
				local b = BUILT[id]
				local ok, r = pcall(b.test, e)
				if ok and r then return id, b.split and b.split(e) or nil end
			end
		end
	end
	return "misc"
end

---------------------------------------------------------------------------------------------
-- custom groups
---------------------------------------------------------------------------------------------
local function Changed() orderCache = nil Settings:Touch() NBG:Fire("GROUPS_CHANGED") end

function Groups:NewCustom()
	local g = G()
	local n = 1
	while g.custom["c" .. n] do n = n + 1 end
	local id = "c" .. n
	g.custom[id] = { name = L["My group"] .. " " .. n, icon = "star", color = { 0.91, 0.77, 0.47 }, match = "all",
		rules = { Rules:Default("quality") }, section = true, collapsed = false, sell = false }
	-- place it after New items, before the built-ins
	local order = self:Order()
	local at = 1
	for i, o in ipairs(order) do if o == "new" then at = i end end
	table.insert(order, at + 1, id)
	g.order = order
	Changed()
	return id
end

function Groups:SaveCustom(id, def)
	local g = G()
	if not g.custom[id] then return end
	local clean = self:CleanCustom(def)
	if clean then g.custom[id] = clean Changed() end
end

function Groups:DeleteCustom(id)
	local g = G()
	if not g.custom[id] then return end
	g.custom[id] = nil
	for i = #g.order, 1, -1 do if g.order[i] == id then table.remove(g.order, i) end end
	for item, gid in pairs(Settings:Profile().assign) do if gid == id then Settings:Profile().assign[item] = nil end end
	Changed()
end

function Groups:SetOff(id, off)
	if BUILT[id] then G().off[id] = off and true or nil Changed() end
end

function Groups:Move(id, delta)
	local order = self:Order()
	local i
	for k, o in ipairs(order) do if o == id then i = k end end
	if not i or id == "junk" then return end
	local j = math.max(1, math.min(#order - 1, i + delta))
	if j == i then return end
	table.remove(order, i)
	table.insert(order, j, id)
	G().order = order
	Changed()
end

function Groups:CleanCustom(c)
	if type(c) ~= "table" then return nil end
	local out = {}
	out.name = (type(c.name) == "string" and c.name:gsub("|", ""):sub(1, 40)) or L["My group"]
	if out.name == "" then out.name = L["My group"] end
	out.icon = (type(c.icon) == "string" and ns.GLYPHS and ns.GLYPHS[c.icon]) and c.icon or "star"
	local col = type(c.color) == "table" and c.color or {}
	out.color = { Num(col[1]) or 0.91, Num(col[2]) or 0.77, Num(col[3]) or 0.47 }
	for i = 1, 3 do out.color[i] = math.max(0, math.min(1, out.color[i])) end
	out.match = c.match == "any" and "any" or "all"
	out.rules = {}
	for _, r in ipairs(type(c.rules) == "table" and c.rules or {}) do
		local cr = Rules:Clean(r)
		if cr and #out.rules < 12 then out.rules[#out.rules + 1] = cr end
	end
	out.section = c.section and true or false
	out.collapsed = c.collapsed and true or false
	out.sell = c.sell and true or false
	return out
end

function Groups:Sanitize(t)
	local out = { order = {}, custom = {}, off = {} }
	if type(t) ~= "table" then return out end
	if type(t.custom) == "table" then
		local n = 0
		for id, c in pairs(t.custom) do
			if type(id) == "string" and id:match("^c%d+$") and n < 40 then
				local cc = self:CleanCustom(c)
				if cc then out.custom[id] = cc n = n + 1 end
			end
		end
	end
	if type(t.order) == "table" then
		for _, id in ipairs(t.order) do
			if type(id) == "string" and (BUILT[id] or out.custom[id]) then out.order[#out.order + 1] = id end
		end
	end
	if type(t.off) == "table" then
		for id, v in pairs(t.off) do if BUILT[id] and v == true then out.off[id] = true end end
	end
	return out
end

-- custom groups that sell at vendors
function Groups:SellsAtVendor(e)
	local g = G()
	for id, c in pairs(g.custom) do
		if c.sell and Rules:Match(e, c.rules, c.match) then return id end
	end
	return nil
end
