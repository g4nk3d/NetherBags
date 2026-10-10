--[[ NetherBags - Data/Containers.lua
	What the character carries, read from the game: the bags, the bank (bank tabs on clients that
	have them, else the classic bank slots and bank bags), the keyring. Every count and size comes
	from the game, so any bag size, any number of bags and any number of bank tabs just work.

	  Containers:Bags(place)            bag IDs of "bags" | "bank" for this character, in order
	  Containers:Size(bag), :Free(bag)  slots / free slots; :Family(bag) the bag's family bits
	  Containers:Info(bag)              { id, size, free, family, special, kind, icon, link, name,
	                                      purchased } for bag strips and section headers
	  Containers:Read(bag)              { [slot] = entry } (cached until the bag changes)
	  Containers:Entry(bag, slot)       one entry: { bag, slot, place, link, str, id, count, icon,
	                                      quality, locked, bound, readable, noValue, quest,
	                                      questActive, new }
	  Containers:BankOpen(), :BankMode()  "tabs" | "classic" | "none"
	  Containers:BankTabs()             the purchased bank tabs (tabs mode)
	  Containers:NextBankPurchase()     { cost, kind } or nil

	Messages: "BAGS_CHANGED"(bagSet) after a short debounce (one per batch of game events);
	"SLOT_LOCK"(bag, slot); "COOLDOWNS"; "BANK_OPEN"(open); "NEW_ITEMS"; "MONEY". ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Containers = NBG:Module("Containers")

local type, pairs, ipairs, tonumber, max = type, pairs, ipairs, tonumber, math.max
local Num, Str, Open = NBG.Num, NBG.Str, NBG.Open

local function CC(fn) return NBG.API("C_Container", fn) end

---------------------------------------------------------------------------------------------
-- the bag IDs
---------------------------------------------------------------------------------------------
local function N(...) for i = 1, select("#", ...) do local v = select(i, ...) if type(v) == "number" then return v end end return nil end
local BagIndex = type(_G.Enum) == "table" and type(Enum.BagIndex) == "table" and Enum.BagIndex or {}
-- (the special containers have negative IDs; anything else is not believed)
local function Neg(...) for i = 1, select("#", ...) do local v = select(i, ...) if type(v) == "number" and v < 0 then return v end end return nil end
Containers.BACKPACK = 0
Containers.BANK = Neg(rawget(_G, "BANK_CONTAINER"), BagIndex.Bank, -1)
-- (the game's own number first: on Forever the keyring is -1, the number older clients used for
-- the bank's own slots, so the bank never takes -1 there while bank tabs exist)
Containers.KEYRING = Neg(BagIndex.Keyring, rawget(_G, "KEYRING_CONTAINER"), -2)
-- the reagent bag slot (5 on clients that have it): it takes reagents only
Containers.REAGENT_BAG = (type(BagIndex.ReagentBag) == "number" and BagIndex.ReagentBag >= 1) and BagIndex.ReagentBag or nil
Containers.REAGENTBANK = Neg(rawget(_G, "REAGENTBANK_CONTAINER"), BagIndex.Reagentbank)
local IC = type(rawget(_G, "Constants")) == "table" and type(Constants.InventoryConstants) == "table" and Constants.InventoryConstants or {}
-- (read at login too: the game may set these after we load)
function Containers:ReadConstants()
	self.NUM_BAGS = N(rawget(_G, "NUM_TOTAL_EQUIPPED_BAG_SLOTS"), rawget(_G, "NUM_BAG_SLOTS"), 4)
	self.NUM_BANK_BAGS = N(rawget(_G, "NUM_BANKBAGSLOTS"), IC.NumCharacterBankSlots, 6)
end
Containers:ReadConstants()

-- bag family bits -> the kind of special bag (Classic numbering)
Containers.FAMILIES = {
	{ bit = 1, id = "quiver", label = L["Quiver"], glyph = "quiver" },
	{ bit = 2, id = "ammo", label = L["Ammo pouch"], glyph = "arrow" },
	{ bit = 4, id = "soul", label = L["Soul bag"], glyph = "soul" },
	{ bit = 8, id = "leather", label = L["Leatherworking bag"], glyph = "strap" },
	{ bit = 16, id = "inscription", label = L["Inscription bag"], glyph = "scroll" },
	{ bit = 32, id = "herb", label = L["Herb bag"], glyph = "leaf" },
	{ bit = 64, id = "enchant", label = L["Enchanting bag"], glyph = "rune" },
	{ bit = 128, id = "engineer", label = L["Engineering bag"], glyph = "gear" },
	{ bit = 256, id = "keys", label = L["Keyring"], glyph = "key" },
	{ bit = 512, id = "gems", label = L["Gem bag"], glyph = "gem" },
	{ bit = 1024, id = "mining", label = L["Mining bag"], glyph = "ore" },
}

Containers.REAGENT_KIND = { id = "reagent", label = L["Reagent bag"], glyph = "leaf" }

local function hasBit(n, b) return n and n > 0 and math.floor(n / b) % 2 == 1 end

function Containers:FamilyKind(family)
	family = Num(family) or 0
	if family <= 0 then return nil end
	for _, f in ipairs(self.FAMILIES) do if hasBit(family, f.bit) then return f end end
	return { id = "special", label = L["Special bag"], glyph = "bag" }
end

local function HasKeyring()
	local f = _G.HasKey
	if type(f) == "function" then
		local ok, v = pcall(f)
		if ok and v then return true end
	end
	-- Forever has no HasKey(): the keyring is there when the game says it has slots
	return type(BagIndex.Keyring) == "number" and Containers:Size(Containers.KEYRING) > 0
end

local function TabsAPI()
	local B = rawget(_G, "C_Bank")
	local E = type(_G.Enum) == "table" and _G.Enum.BankType
	if type(B) ~= "table" or type(E) ~= "table" then return nil end
	if type(B.FetchPurchasedBankTabData) ~= "function" then return nil end
	return B, E
end

function Containers:BankMode()
	if TabsAPI() then return "tabs" end
	if self.NUM_BANK_BAGS then return "classic" end
	return "none"
end

function Containers:BankTabs()
	local B, E = TabsAPI()
	if not B then return {} end
	local ok, list = pcall(B.FetchPurchasedBankTabData, E.Character or 0)
	list = ok and Open(list) or nil
	local out = {}
	if not list then return out end
	local seen = {}
	for i, t in ipairs(list) do
		t = Open(t)
		if t and Num(t.ID) then
			out[#out + 1] = { id = Num(t.ID), index = i, name = Str(t.name) or (L["Tab"] .. " " .. i), icon = Num(t.icon) or Str(t.icon),
				depositFlags = Num(t.depositFlags) or 0 }
			seen[Num(t.ID)] = true
		end
	end
	-- (the tab list can come later than the tabs themselves: any tab container that reports slots)
	for i = 1, 9 do
		local id = Num(BagIndex["CharacterBankTab_" .. i])
		if id and id > (self.NUM_BAGS or 4) and not seen[id] and self:Size(id) > 0 then
			out[#out + 1] = { id = id, index = i, name = L["Tab"] .. " " .. i, depositFlags = 0 }
		end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

function Containers:Bags(place)
	local out = {}
	if place == "bags" then
		for i = self.BACKPACK, self.NUM_BAGS do out[#out + 1] = i end
		if HasKeyring() then out[#out + 1] = self.KEYRING end
	elseif place == "bank" then
		if self:BankMode() == "tabs" then
			-- the old bank container only while there are no tabs (it reports slots it can't hold
			-- once they exist), and never when it is the keyring's number (Forever)
			local tabs = self:BankTabs()
			if #tabs == 0 and self.BANK ~= self.KEYRING and self:Size(self.BANK) > 0 then out[#out + 1] = self.BANK end
			for _, t in ipairs(tabs) do out[#out + 1] = t.id end
		else
			out[#out + 1] = self.BANK
			for i = self.NUM_BAGS + 1, self.NUM_BAGS + self.NUM_BANK_BAGS do out[#out + 1] = i end
			if self.REAGENTBANK and type(_G.IsReagentBankUnlocked) == "function" and NBG.Call(IsReagentBankUnlocked) then
				out[#out + 1] = self.REAGENTBANK
			end
		end
	end
	return out
end

function Containers:PlaceOf(bag)
	if bag == self.KEYRING or (bag >= self.BACKPACK and bag <= self.NUM_BAGS) then return "bags" end
	return "bank"
end

function Containers:Size(bag)
	local f = CC("GetContainerNumSlots") or _G.GetContainerNumSlots
	local n = f and Num(NBG.Call(f, bag)) or 0
	-- the keyring's size has its own call where the game has one
	if bag == self.KEYRING and type(_G.GetKeyRingSize) == "function" then
		n = max(n, Num(NBG.Call(GetKeyRingSize)) or 0)
	end
	return n
end

function Containers:Free(bag)
	local f = CC("GetContainerNumFreeSlots") or _G.GetContainerNumFreeSlots
	if not f then return 0, 0 end
	local ok, free, family = pcall(f, bag)
	if not ok then return 0, 0 end
	return Num(free) or 0, Num(family) or 0
end

function Containers:Family(bag)
	if bag == self.KEYRING then return 256 end
	if bag == self.BACKPACK or bag == self.BANK then return 0 end
	local _, fam = self:Free(bag)
	return fam
end

local function InvSlot(bag)
	local f = CC("ContainerIDToInventoryID") or _G.ContainerIDToInventoryID
	if not f then return nil end
	return Num(NBG.Call(f, bag))
end

function Containers:Info(bag)
	local size = self:Size(bag)
	local free, family = self:Free(bag)
	if bag == self.KEYRING then family = 256 end
	if bag == self.BACKPACK or bag == self.BANK then family = 0 end
	local kind = self:FamilyKind(family)
	if not kind and bag == self.REAGENT_BAG and size > 0 then kind = self.REAGENT_KIND end
	local info = { id = bag, size = size, free = free, family = family, special = kind, place = self:PlaceOf(bag) }
	if bag == self.BACKPACK then
		info.kind, info.name, info.icon = "backpack", L["Backpack"], 133633
	elseif bag == self.KEYRING then
		info.kind, info.name, info.icon = "keyring", L["Keyring"], 134237
	elseif bag == self.BANK then
		info.kind, info.name, info.icon = "bankslots", L["Bank slots"], 133628
	else
		if self:BankMode() == "tabs" and info.place == "bank" then
			for _, t in ipairs(self:BankTabs()) do
				if t.id == bag then info.kind, info.name, info.icon, info.tab = "tab", t.name, t.icon, t.index end
			end
		end
		local inv = InvSlot(bag)
		if inv and _G.GetInventoryItemLink then
			local link = Str(NBG.Call(GetInventoryItemLink, "player", inv))
			if link then
				info.link = link
				info.icon = info.icon or Num(NBG.Call(_G.GetInventoryItemTexture, "player", inv))
				local name = link:match("%[(.-)%]")
				info.name = info.name or name
			end
		end
		info.kind = info.kind or "bag"
		info.name = info.name or (info.place == "bank" and L["Bank bag"] or L["Bag"])
		info.purchased = size > 0
	end
	return info
end

---------------------------------------------------------------------------------------------
-- reading slots
---------------------------------------------------------------------------------------------
local cache = {}         -- bag -> { [slot] = entry }, rebuilt when dirty
local dirtyAll = true
local dirty = {}

local function ItemString(link)
	if not link then return nil end
	return link:match("|H(item:[^|]+)|h") or link:match("^(item:[%-%d:]+)") or link:match("|H(battlepet:[^|]+)|h") or link:match("|H(keystone:[^|]+)|h")
end
Containers.ItemString = ItemString

local function ReadSlot(bag, slot, place)
	local f = CC("GetContainerItemInfo")
	local e
	if f then
		local ok, t = pcall(f, bag, slot)
		t = ok and Open(t) or nil
		if not t then return nil end
		e = { icon = Num(t.iconFileID) or t.iconFileID, count = Num(t.stackCount) or 1, locked = t.isLocked and true or false,
			quality = Num(t.quality), readable = t.isReadable and true or false, noValue = t.hasNoValue and true or false,
			link = Str(t.hyperlink), id = Num(t.itemID), bound = t.isBound and true or false }
	elseif _G.GetContainerItemInfo then
		local ok, icon, count, locked, quality, readable, _, link, _, noValue, id, bound = pcall(GetContainerItemInfo, bag, slot)
		if not ok or not icon then return nil end
		e = { icon = icon, count = Num(count) or 1, locked = locked and true or false, quality = Num(quality), readable = readable and true or false,
			noValue = noValue and true or false, link = Str(link), id = Num(id), bound = bound and true or false }
	else
		return nil
	end
	if not e.link and not e.id then return nil end
	e.bag, e.slot, e.place = bag, slot, place
	e.str = ItemString(e.link) or (e.id and ("item:" .. e.id))
	if not e.id and e.link then e.id = tonumber(e.link:match("item:(%d+)")) end
	local q = CC("GetContainerItemQuestInfo")
	if q then
		local ok, qi = pcall(q, bag, slot)
		qi = ok and Open(qi) or nil
		if qi then
			e.quest = (qi.isQuestItem or Num(qi.questID)) and true or false
			e.questActive = qi.isActive and true or false
			e.questID = Num(qi.questID)   -- an item that starts this quest (the quest item bar)
		end
	end
	local nf = NBG.API("C_NewItems", "IsNewItem")
	if nf then e.new = NBG.Call(nf, bag, slot) and true or false end
	return e
end

function Containers:Read(bag)
	if not dirtyAll and not dirty[bag] and cache[bag] then return cache[bag] end
	local place = self:PlaceOf(bag)
	local t = {}
	for slot = 1, self:Size(bag) do
		t[slot] = ReadSlot(bag, slot, place)
	end
	cache[bag] = t
	dirty[bag] = nil
	return t
end

function Containers:Entry(bag, slot)
	return self:Read(bag)[slot]
end

-- a fresh read of one slot (lock changes don't need the whole bag)
function Containers:RefreshSlot(bag, slot)
	local t = cache[bag]
	if not t then return nil end
	t[slot] = ReadSlot(bag, slot, self:PlaceOf(bag))
	return t[slot]
end

function Containers:Invalidate(bag)
	if bag then dirty[bag] = true else dirtyAll = true end
end

-- all the entries of a place, in bag/slot order (for the list views and the store)
function Containers:All(place)
	local out = {}
	for _, bag in ipairs(self:Bags(place)) do
		local t = self:Read(bag)
		for slot = 1, self:Size(bag) do
			if t[slot] then out[#out + 1] = t[slot] end
		end
	end
	dirtyAll = false
	return out
end

function Containers:Counts(place)
	local used, total = 0, 0
	local special = {}
	for _, bag in ipairs(self:Bags(place)) do
		local size = self:Size(bag)
		local free, family = self:Free(bag)
		if bag == self.KEYRING then
			-- the keyring is not counted as bag space
		elseif (family and family > 0 and bag ~= self.BACKPACK and bag ~= self.BANK) or (bag == self.REAGENT_BAG and size > 0) then
			local k = self:FamilyKind(family) or self.REAGENT_KIND
			local s = special[k.id] or { kind = k, used = 0, total = 0 }
			s.used, s.total = s.used + (size - free), s.total + size
			special[k.id] = s
		else
			used, total = used + (size - free), total + size
		end
	end
	return used, total, special
end

---------------------------------------------------------------------------------------------
-- the bank: open or not
---------------------------------------------------------------------------------------------
Containers.bankOpen = false
function Containers:BankOpen() return self.bankOpen end

local function InteractionType(name)
	local E = type(_G.Enum) == "table" and _G.Enum.PlayerInteractionType
	return E and E[name]
end

-- walking away from the banker is not always reported (Forever sends no close at all): while
-- the bank is open, ask the game every half second whether the player still talks to a banker
-- (only once it has said yes, so a client that never answers yes can't close a real bank)
local function AtBanker()
	local PIM = rawget(_G, "C_PlayerInteractionManager")
	local f = type(PIM) == "table" and PIM.IsInteractingWithNpcOfType
	if type(f) ~= "function" then return nil end
	local t = InteractionType("Banker")
	if t == nil then return nil end
	local ok, v = pcall(f, t)
	if not ok then return nil end
	return v and true or false
end
local watching, confirmed = false, false

local SetBank
local function Watch()
	if not Containers.bankOpen then watching = false return end
	local v = AtBanker()
	if v == nil then watching = false return end   -- (a client that can't say: the game's own events decide)
	if v == true then confirmed = true
	elseif v == false and confirmed then watching = false SetBank(false) return end
	NBG:After(0.5, Watch)
end

function SetBank(open)
	if Containers.bankOpen == open then return end
	Containers.bankOpen = open
	Containers.bankOpenedAt = open and NBG:Clock() or nil
	Containers:Invalidate()
	if open and not watching then
		watching, confirmed = true, false
		NBG:After(0.5, Watch)
	end
	NBG:Fire("BANK_OPEN", open)
end
Containers.SetBank = function(_, open) SetBank(open) end

NBG:On("BANKFRAME_OPENED", function() SetBank(true) end)
NBG:On("BANKFRAME_CLOSED", function() SetBank(false) end)
NBG:On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)
	if kind ~= nil and kind == InteractionType("Banker") then SetBank(true) end
end)
NBG:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
	if kind ~= nil and kind == InteractionType("Banker") then SetBank(false) end
end)

function Containers:NextBankPurchase()
	-- (the game gives the first bank tab as the bank opens; asking for tab prices in that same
	-- moment spoils the gift, so nothing is asked in the first second and a half)
	if self.bankOpenedAt and NBG:Clock() - self.bankOpenedAt < 1.5 then
		NBG:Debounce("bankBuyLater", 1.6, function() if Containers.bankOpen then NBG:Fire("BAGS_CHANGED", { all = true }) end end)
		return nil
	end
	if self:BankMode() == "tabs" then
		local B, E = TabsAPI()
		if type(B.FetchNextPurchasableBankTabData) ~= "function" then return nil end
		local ok, d = pcall(B.FetchNextPurchasableBankTabData, E.Character or 0)
		d = ok and Open(d) or nil
		if d and Num(d.tabCost) then return { cost = Num(d.tabCost), kind = "tab" } end
		return nil
	end
	if type(_G.GetNumBankSlots) ~= "function" or type(_G.GetBankSlotCost) ~= "function" then return nil end
	local n, full = NBG.Call(GetNumBankSlots)
	if full then return nil end
	local cost = Num(NBG.Call(GetBankSlotCost, n))
	if cost then return { cost = cost, kind = "slot" } end
	return nil
end

---------------------------------------------------------------------------------------------
-- events -> one message per batch
---------------------------------------------------------------------------------------------
local pending = {}
local function Queue(bag)
	if bag ~= nil then
		pending[bag] = true
		dirty[bag] = true
	else
		pending.all = true
		dirtyAll = true
	end
	NBG:Debounce("bags", 0.05, function()
		local set = pending
		pending = {}
		NBG:Fire("BAGS_CHANGED", set)
	end)
end
Containers.Queue = Queue

NBG:On("BAG_UPDATE", function(_, bag) Queue(Num(bag)) end)
NBG:On("BAG_CLOSED", function(_, bag) Queue(Num(bag)) end)
NBG:On("PLAYERBANKSLOTS_CHANGED", function() Queue(Containers.BANK) end)
NBG:On("PLAYERBANKBAGSLOTS_CHANGED", function() Queue() end)
NBG:On("BANK_TABS_CHANGED", function() Queue() end)
NBG:On("BANK_TAB_SETTINGS_UPDATED", function() Queue() end)
NBG:On("BAG_CONTAINER_UPDATE", function() Queue() end)
NBG:On("PLAYER_EQUIPMENT_CHANGED", function() Queue() end)
NBG:On("QUEST_ACCEPTED", function() Queue() end)
NBG:On("UNIT_QUEST_LOG_CHANGED", function(_, unit) if unit == "player" then Queue() end end)
NBG:On("EQUIPMENT_SETS_CHANGED", function() Queue() end)
NBG:On("BAG_NEW_ITEMS_UPDATED", function() Queue() NBG:Fire("NEW_ITEMS") end)
NBG:On("ITEM_LOCK_CHANGED", function(_, bag, slot)
	bag, slot = Num(bag), Num(slot)
	if bag and slot then
		Containers:RefreshSlot(bag, slot)
		NBG:Fire("SLOT_LOCK", bag, slot)
	end
end)
NBG:On("BAG_UPDATE_COOLDOWN", function() NBG:Debounce("cooldowns", 0.05, function() NBG:Fire("COOLDOWNS") end) end)
NBG:On("PLAYER_MONEY", function() NBG:Fire("MONEY") end)
NBG:On("CURRENCY_DISPLAY_UPDATE", function() NBG:Debounce("currency", 0.2, function() NBG:Fire("CURRENCY") end) end)
NBG:On("PLAYER_ENTERING_WORLD", function() Containers:ReadConstants() Queue() end)

-- the player's money, minus what is on the cursor / in a trade
function Containers:Money()
	local m = Num(NBG.Call(_G.GetMoney)) or 0
	m = m - (Num(NBG.Call(_G.GetCursorMoney)) or 0) - (Num(NBG.Call(_G.GetPlayerTradeMoney)) or 0)
	return max(0, m)
end
