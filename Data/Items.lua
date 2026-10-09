--[[ NetherBags - Data/Items.lua
	What an item is: name, quality, item level, type, slot, vendor value, binding, and the things
	only the tooltip knows (can this character use it). Cached per item string; item data the
	game has not sent yet arrives with GET_ITEM_INFO_RECEIVED, which fires "ITEMS_LOADED".

	  Items:Info(linkOrString) -> info | nil (not loaded yet; asked for)
	      info = { id, name, quality, ilvl, reqLevel, type, subType, classID, subClassID, equipLoc,
	               stack, icon, price, bindType, setID, expansion }
	  Items:Instant(id) -> classID, subClassID, equipLoc, icon (always, no loading)
	  Items:Unusable(entry)       red lines on the tooltip (a slot entry, live)
	  Items:Upgrade(entry)        nil | item level gained over what is worn
	  Items:Unseen(link)          true when the appearance is not collected (clients with transmog)
	  Items:InSet(id)             part of an equipment set
	  Items:Binding(entry)        "soulbound" | "boe" | "bou" | "quest" | "none"
	  Items:SlotName(equipLoc)    readable slot name ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Items = NBG:Module("Items")

local type, pairs, ipairs, tonumber, select = type, pairs, ipairs, tonumber, select
local Num, Str, Open = NBG.Num, NBG.Str, NBG.Open

local info = {}          -- item string -> info
local waiting = {}       -- item id -> true (asked the game for data)
local tipCache = {}      -- item string -> { unusable }
local gen = 0            -- bumps when equipped gear changes (upgrade cache)

local function GetItemInfoFn() return NBG.API("C_Item", "GetItemInfo") or _G.GetItemInfo end
local function InstantFn() return NBG.API("C_Item", "GetItemInfoInstant") or _G.GetItemInfoInstant end

function Items:Instant(id)
	local f = InstantFn()
	if not (f and id) then return nil end
	local ok, _, _, _, equipLoc, icon, classID, subClassID = pcall(f, id)
	if not ok then return nil end
	return Num(classID), Num(subClassID), Str(equipLoc), icon
end

function Items:Info(link)
	if not link then return nil end
	local key = link
	local cached = info[key]
	if cached then return cached end
	local f = GetItemInfoFn()
	if not f then return nil end
	local ok, name, ilink, quality, ilvl, reqLevel, itype, subType, stack, equipLoc, icon, price, classID, subClassID, bindType, expansion, setID = pcall(f, link)
	if not ok or not Str(name) then
		local id = tonumber(tostring(link):match("item:(%d+)")) or Num(link)
		if id and not waiting[id] then
			waiting[id] = true
			local req = NBG.API("C_Item", "RequestLoadItemDataByID")
			if req then pcall(req, id) end
		end
		return nil
	end
	local id = tonumber(tostring(ilink or link):match("item:(%d+)")) or Num(link)
	local real = ilvl
	local dl = NBG.API("C_Item", "GetDetailedItemLevelInfo") or _G.GetDetailedItemLevelInfo
	if dl and ilink then real = Num(NBG.Call(dl, ilink)) or ilvl end
	local t = {
		id = id, name = name, link = ilink, quality = Num(quality) or 1, ilvl = Num(real) or Num(ilvl) or 0,
		reqLevel = Num(reqLevel) or 0, type = Str(itype) or "", subType = Str(subType) or "", stack = Num(stack) or 1,
		equipLoc = Str(equipLoc) or "", icon = icon, price = Num(price) or 0, classID = Num(classID), subClassID = Num(subClassID),
		bindType = Num(bindType) or 0, expansion = Num(expansion), setID = Num(setID),
	}
	if not t.classID and id then t.classID, t.subClassID = self:Instant(id) end
	-- what vendors really pay (learned from the buyback list) beats the item data's price
	t.clientPrice = t.price
	local learned = id and self:LearnedPrice(id)
	if learned then t.price = learned end
	info[key] = t
	return t
end

---------------------------------------------------------------------------------------------
-- real vendor prices: on Forever a vendor can pay less than the item data says. What was really
-- paid is read from the buyback list after a sale and remembered (account-wide, per item).
---------------------------------------------------------------------------------------------
local function Prices()
	local g = NBG.db and NBG.db.global
	if not g then return nil end
	g.prices = type(g.prices) == "table" and g.prices or {}
	return g.prices
end
function Items:LearnedPrice(id)
	local p = Prices()
	return p and Num(p[id]) or nil
end
function Items:Learn(id, unit)
	local p = Prices()
	id, unit = Num(id), Num(unit)
	if not (p and id and unit and unit >= 0) then return false end
	-- (the price the item data gives, from the game itself: the cache may not hold the item)
	local client
	local f = GetItemInfoFn()
	if f then client = Num((select(11, NBG.Call(f, "item:" .. id)))) end
	local new = unit
	if client and unit == client then new = nil end   -- the item data was right: nothing kept
	if p[id] == new then return false end
	p[id] = new
	for _, t in pairs(info) do if t.id == id then t.price = new or t.clientPrice or t.price end end
	return true
end
-- read the buyback list (what the vendor paid for each stack sold here)
function Items:LearnFromBuyback()
	local n = Num(NBG.Call(_G.GetNumBuybackItems)) or 0
	local changed = false
	for i = 1, n do
		local link = Str(NBG.Call(_G.GetBuybackItemLink, i))
		local _, _, price, quantity = NBG.Call(_G.GetBuybackItemInfo, i)
		price, quantity = Num(price), Num(quantity) or 1
		local id = link and tonumber(link:match("item:(%d+)"))
		if id and price and quantity and quantity > 0 then
			if self:Learn(id, math.floor(price / quantity + 0.5)) then changed = true end
		end
	end
	if changed then NBG:Fire("PRICES_LEARNED") end
	return changed
end

NBG:On("GET_ITEM_INFO_RECEIVED", function(_, id, ok)
	id = Num(id)
	if id and waiting[id] then
		waiting[id] = nil
		NBG:Debounce("itemsLoaded", 0.1, function() NBG:Fire("ITEMS_LOADED") end)
	end
end)

---------------------------------------------------------------------------------------------
-- slot names
---------------------------------------------------------------------------------------------
local SLOT_NAMES = {
	INVTYPE_HEAD = L["Head"], INVTYPE_NECK = L["Neck"], INVTYPE_SHOULDER = L["Shoulder"], INVTYPE_BODY = L["Shirt"],
	INVTYPE_CHEST = L["Chest"], INVTYPE_ROBE = L["Chest"], INVTYPE_WAIST = L["Waist"], INVTYPE_LEGS = L["Legs"],
	INVTYPE_FEET = L["Feet"], INVTYPE_WRIST = L["Wrist"], INVTYPE_HAND = L["Hands"], INVTYPE_FINGER = L["Finger"],
	INVTYPE_TRINKET = L["Trinket"], INVTYPE_CLOAK = L["Back"], INVTYPE_WEAPON = L["One-Hand"], INVTYPE_SHIELD = L["Off Hand"],
	INVTYPE_2HWEAPON = L["Two-Hand"], INVTYPE_WEAPONMAINHAND = L["Main Hand"], INVTYPE_WEAPONOFFHAND = L["Off Hand"],
	INVTYPE_HOLDABLE = L["Held In Off-hand"], INVTYPE_RANGED = L["Ranged"], INVTYPE_THROWN = L["Thrown"],
	INVTYPE_RANGEDRIGHT = L["Ranged"], INVTYPE_RELIC = L["Relic"], INVTYPE_TABARD = L["Tabard"], INVTYPE_BAG = L["Bag"],
	INVTYPE_QUIVER = L["Quiver"], INVTYPE_AMMO = L["Ammo"],
}
Items.SLOT_NAMES = SLOT_NAMES
function Items:SlotName(loc)
	if not loc or loc == "" then return nil end
	return SLOT_NAMES[loc] or (type(_G[loc]) == "string" and _G[loc]) or nil
end

-- equip location -> inventory slot ids it can go to
local EQUIP_SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_THROWN = { 18 },
	INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_RELIC = { 18 },
}
Items.EQUIP_SLOTS = EQUIP_SLOTS

---------------------------------------------------------------------------------------------
-- tooltip facts (cached per item string; cleared when the character levels or learns)
---------------------------------------------------------------------------------------------
local function RedLine(line)
	line = Open(line)
	if not line then return false end
	local c = Open(line.leftColor)
	if not c then return false end
	local r, g, b = Num(c.r), Num(c.g), Num(c.b)
	if not (r and g and b) then return false end
	return r > 0.95 and g < 0.2 and b < 0.2
end

function Items:Unusable(entry)
	if not entry or not entry.str then return false end
	local c = tipCache[entry.str]
	if c then return c.unusable end
	local TI = rawget(_G, "C_TooltipInfo")
	local data
	if type(TI) == "table" then
		if entry.bag and entry.slot and type(TI.GetBagItem) == "function" and entry.live ~= false then
			local ok, d = pcall(TI.GetBagItem, entry.bag, entry.slot)
			data = ok and Open(d) or nil
		elseif entry.link and type(TI.GetHyperlink) == "function" then
			local ok, d = pcall(TI.GetHyperlink, entry.link)
			data = ok and Open(d) or nil
		end
	end
	local unusable = false
	local lines = data and Open(data.lines)
	if lines then
		for i, line in ipairs(lines) do
			if i > 1 and RedLine(line) then unusable = true break end
		end
	end
	if data then tipCache[entry.str] = { unusable = unusable } end
	return unusable
end

NBG:On("PLAYER_LEVEL_UP", function() NBG.wipe(tipCache) gen = gen + 1 end)
NBG:On("LEARNED_SPELL_IN_TAB", function() NBG.wipe(tipCache) end)
NBG:On("SKILL_LINES_CHANGED", function() NBG.wipe(tipCache) end)
NBG:On("PLAYER_EQUIPMENT_CHANGED", function() gen = gen + 1 end)

---------------------------------------------------------------------------------------------
-- upgrades: an item that can be worn now, at a higher item level than what is worn there
---------------------------------------------------------------------------------------------
local wornCache, wornGen = {}, -1
local function WornLevel(slot)
	if wornGen ~= gen then NBG.wipe(wornCache) wornGen = gen end
	local v = wornCache[slot]
	if v ~= nil then return v end
	local link = Str(NBG.Call(_G.GetInventoryItemLink, "player", slot))
	if not link then v = 0
	else
		local i = Items:Info(link)
		v = i and i.ilvl or false
	end
	wornCache[slot] = v
	return v
end

function Items:Upgrade(entry)
	if not entry or not entry.link then return nil end
	local i = self:Info(entry.link)
	if not i or (i.classID ~= 2 and i.classID ~= 4) then return nil end
	local slots = EQUIP_SLOTS[i.equipLoc]
	if not slots or i.ilvl <= 1 then return nil end
	local level = Num(NBG.Call(_G.UnitLevel, "player")) or 0
	if i.reqLevel > level then return nil end
	if self:Unusable(entry) then return nil end
	local lowest
	for _, s in ipairs(slots) do
		local w = WornLevel(s)
		if w == false then return nil end   -- worn item not loaded yet: decide later
		if not lowest or w < lowest then lowest = w end
	end
	if lowest and i.ilvl > lowest then return i.ilvl - lowest end
	return nil
end

---------------------------------------------------------------------------------------------
-- appearances (only on clients with the appearance collection)
---------------------------------------------------------------------------------------------
function Items:Unseen(link)
	local TC = rawget(_G, "C_TransmogCollection")
	if type(TC) ~= "table" or type(TC.PlayerHasTransmogByItemInfo) ~= "function" or not link then return nil end
	local i = self:Info(link)
	if not i or (i.classID ~= 2 and i.classID ~= 4) then return nil end
	if not EQUIP_SLOTS[i.equipLoc] or i.equipLoc == "INVTYPE_FINGER" or i.equipLoc == "INVTYPE_TRINKET" or i.equipLoc == "INVTYPE_NECK" then return nil end
	local ok, has = pcall(TC.PlayerHasTransmogByItemInfo, link)
	if not ok then return nil end
	return not has
end

---------------------------------------------------------------------------------------------
-- equipment sets
---------------------------------------------------------------------------------------------
local setItems, setsDirty = {}, true
NBG:On("EQUIPMENT_SETS_CHANGED", function() setsDirty = true end)
function Items:InSet(id)
	if not id then return false end
	if setsDirty then
		setsDirty = false
		NBG.wipe(setItems)
		local ES = rawget(_G, "C_EquipmentSet")
		if type(ES) == "table" and type(ES.GetEquipmentSetIDs) == "function" and type(ES.GetItemIDs) == "function" then
			local ok, ids = pcall(ES.GetEquipmentSetIDs)
			for _, sid in ipairs(ok and Open(ids) or {}) do
				local ok2, list = pcall(ES.GetItemIDs, sid)
				for _, iid in pairs(ok2 and Open(list) or {}) do
					iid = Num(iid)
					if iid and iid > 0 then setItems[iid] = true end
				end
			end
		end
	end
	return setItems[id] or false
end

---------------------------------------------------------------------------------------------
-- binding
---------------------------------------------------------------------------------------------
function Items:Binding(entry)
	if not entry then return "none" end
	if entry.quest then return "quest" end
	local i = entry.link and self:Info(entry.link)
	if entry.bound then return "soulbound" end
	if not i then return "none" end
	if i.bindType == 4 then return "quest" end
	-- (a live slot that is not bound is still unbound; offline records keep what was saved)
	if entry.boundSaved then return "soulbound" end
	if i.bindType == 2 then return "boe" end
	if i.bindType == 3 then return "bou" end
	if i.bindType == 1 then return "soulbound" end
	return "none"
end

-- quality names (the game's, with English fallbacks)
local QN = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact", "Heirloom" }
function Items:QualityName(q)
	q = Num(q) or 1
	local g = _G["ITEM_QUALITY" .. q .. "_DESC"]
	return (type(g) == "string" and g) or L[QN[q] or "Common"]
end

function Items:QualityColor(q)
	q = Num(q) or 1
	local C = rawget(_G, "ITEM_QUALITY_COLORS")
	local c = type(C) == "table" and C[q]
	if type(c) == "table" and c.r then return c.r, c.g, c.b end
	local F = { [0] = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 }, { 0.9, 0.8, 0.5 }, { 0, 0.8, 1 } }
	local f = F[q] or F[1]
	return f[1], f[2], f[3]
end

-- class names for the Type rule and the search (the game's own names when it has them)
Items.CLASSES = {
	{ id = 0, label = L["Consumable"] }, { id = 1, label = L["Container"] }, { id = 2, label = L["Weapon"] },
	{ id = 3, label = L["Gem"] }, { id = 4, label = L["Armor"] }, { id = 5, label = L["Reagent"] },
	{ id = 6, label = L["Projectile"] }, { id = 7, label = L["Trade Goods"] }, { id = 9, label = L["Recipe"] },
	{ id = 11, label = L["Quiver"] }, { id = 12, label = L["Quest"] }, { id = 13, label = L["Key"] },
	{ id = 15, label = L["Miscellaneous"] },
}
function Items:ClassName(id)
	local f = NBG.API("C_Item", "GetItemClassInfo") or _G.GetItemClassInfo
	if f and id then
		local n = Str(NBG.Call(f, id))
		if n then return n end
	end
	for _, c in ipairs(self.CLASSES) do if c.id == id then return c.label end end
	return L["Other"]
end
