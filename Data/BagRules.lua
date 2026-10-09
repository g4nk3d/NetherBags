--[[ NetherBags - Data/BagRules.lua
	What each of your bags is for (the bag menu, the bag icon next to the title):

	  categories   tick the kinds of items a bag holds (weapons, consumables, trade goods...). Sort
	               puts those items into that bag and keeps other items out of it; items that arrive
	               later are moved into it (setting bags.autoRoute). Where the game has its own bag
	               flags (equipment, consumables, trade goods, junk, quest items, reagents) they are
	               set too, so the game can place loot there itself.
	  colour       a colour for the bag: its slots in One bag get a light tint of it (setting
	               onebag.bagColors), and its button on the bag strip a ring of it.

	Kept in the profile (bagRules[bag] = { cats = { id = true }, color = { r, g, b } }).

	  BagRules:Bags() -> { info }                       the bags that can have rules (not the keyring)
	  BagRules:Has(bag, catId) / Toggle(bag, catId) / Clear(bag)
	  BagRules:Color(bag) -> { r, g, b } | nil / SetColor(bag, rgb | nil)
	  BagRules:BagFor(entry) -> bag | nil               the bag an item belongs in
	  BagRules:Any() -> bool                            any bag has categories
	  BagRules.PRESETS                                  the preset colours ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local BagRules = NBG:Module("BagRules")
local Containers, Settings = NBG.Containers, NBG.Settings

local type, pairs, ipairs = type, pairs, ipairs

BagRules.PRESETS = {
	{ 0.91, 0.30, 0.30 }, { 0.95, 0.58, 0.24 }, { 0.95, 0.83, 0.33 }, { 0.42, 0.82, 0.36 }, { 0.30, 0.78, 0.70 },
	{ 0.36, 0.66, 0.96 }, { 0.48, 0.42, 0.95 }, { 0.80, 0.42, 0.92 }, { 0.93, 0.47, 0.70 }, { 0.70, 0.70, 0.74 },
}

local function R()
	local p = Settings:Profile()
	p.bagRules = type(p.bagRules) == "table" and p.bagRules or {}
	return p.bagRules
end
local function Rule(bag, make)
	local r = R()
	local t = r[bag]
	if not t and make then t = { cats = {} } r[bag] = t end
	if t then t.cats = type(t.cats) == "table" and t.cats or {} end
	return t
end
local function Changed(bag)
	Settings:Touch()
	NBG:Fire("BAG_RULES", bag)
end

function BagRules:Kinds()
	local out = {}
	for _, c in ipairs(NBG.Groups.CATEGORIES) do if c.id ~= "all" then out[#out + 1] = c end end
	out[#out + 1] = NBG.Groups.JUNK_CATEGORY
	return out
end

function BagRules:Bags()
	local out = {}
	for _, bag in ipairs(Containers:Bags("bags")) do
		if bag ~= Containers.KEYRING then
			local info = Containers:Info(bag)
			if (info.size or 0) > 0 then out[#out + 1] = info end
		end
	end
	return out
end

function BagRules:Has(bag, cat) local t = Rule(bag) return t and t.cats[cat] or false end
function BagRules:Count(bag) local t = Rule(bag) local n = 0 if t then for _ in pairs(t.cats) do n = n + 1 end end return n end

function BagRules:Toggle(bag, cat)
	local t = Rule(bag, true)
	t.cats[cat] = (not t.cats[cat]) or nil
	self:SyncGameFlags(bag)
	Changed(bag)
end

function BagRules:Clear(bag)
	local t = Rule(bag)
	if t then NBG.wipe(t.cats) end
	self:SyncGameFlags(bag)
	Changed(bag)
end

function BagRules:Color(bag)
	local t = Rule(bag)
	local c = t and t.color
	if type(c) == "table" and type(c[1]) == "number" then return c end
	return nil
end

function BagRules:SetColor(bag, rgb)
	local t = Rule(bag, true)
	if type(rgb) == "table" then t.color = { tonumber(rgb[1]) or 1, tonumber(rgb[2]) or 1, tonumber(rgb[3]) or 1 } else t.color = nil end
	Changed(bag)
end

function BagRules:Any()
	for bag, t in pairs(R()) do if type(t) == "table" and type(t.cats) == "table" and next(t.cats) then return true end end
	return false
end

-- the bag an item belongs in: the first bag (in bag order) whose ticked kinds it is
function BagRules:BagFor(e)
	if not (e and e.id) then return nil end
	local kinds
	for _, info in ipairs(self:Bags()) do
		local t = not info.special and Rule(info.id)
		if t and next(t.cats) then
			kinds = kinds or self:Kinds()
			for _, k in ipairs(kinds) do
				if t.cats[k.id] then
					local ok, r = pcall(k.test, e)
					if ok and r then return info.id end
				end
			end
		end
	end
	return nil
end

-- the game's own bag flags (Enum.BagSlotFlags), where the client has them
local FLAG_OF = { weapons = "ClassEquipment", armor = "ClassEquipment", jewelry = "ClassEquipment", consumables = "ClassConsumables",
	trade = "ClassProfessionGoods", junk = "ClassJunk", quest = "ClassQuestItems" }
function BagRules:SyncGameFlags(bag)
	local set = NBG.API("C_Container", "SetBagSlotFlag")
	local F = type(_G.Enum) == "table" and _G.Enum.BagSlotFlags
	if not (set and type(F) == "table") or not bag or bag < 1 then return end
	local want = {}
	local t = Rule(bag)
	for cat in pairs(t and t.cats or {}) do local f = FLAG_OF[cat] if f and type(F[f]) == "number" then want[f] = true end end
	for _, f in pairs(FLAG_OF) do
		if type(F[f]) == "number" then pcall(set, bag, F[f], want[f] and true or false) end
	end
end
