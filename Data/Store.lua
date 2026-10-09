--[[ NetherBags - Data/Store.lua
	What every character of the account carries, saved so it can be seen anywhere: bags, bank,
	mailbox and money, plus every guild bank tab a character has looked at. Offline views,
	Everywhere and the tooltip counts read from here; nothing is ever guessed. A record is only as
	new as the last time that character logged in or opened that bank or mailbox, and the
	windows say how old it is.

	  Store:Characters()              { { key, class, level, money, updated, guild, faction } }
	  Store:Char(key)                 the saved record (or nil)
	  Store:Bags(key, place)          { { id, size, family, icon, name, kind } } for "bags" | "bank"
	  Store:Entries(key, place)       offline entries, like Containers' but with live = false
	  Store:Mail(key)                 { entries }
	  Store:Guild(name)               { money, tabs = { [i] = { name, icon, items, seen } }, updated }
	  Store:Owners(id)                every place an item is: { { owner, where, count, kind, tab } }
	  Store:Totals(id)                cached per item: { [owner] = { bags, bank, mail }, guild = n }
	  Store:Forget(key)               drop a character's record

	Records: NetherBagsDB.chars[key] and NetherBagsDB.guilds[name]. A slot is saved as
	"item:...;count" (with ";b" when soulbound). ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Store = NBG:Module("Store")
local Containers = NBG.Containers

local type, pairs, ipairs, tonumber, tostring = type, pairs, ipairs, tonumber, tostring
local Num, Str, Open = NBG.Num, NBG.Str, NBG.Open

local gen = 0
local function Bump() gen = gen + 1 NBG:Fire("STORE_CHANGED") end

function Store:Init(db)
	self.db = db
	db.chars = type(db.chars) == "table" and db.chars or {}
	db.guilds = type(db.guilds) == "table" and db.guilds or {}
end

-- every saved character carries its GUID: a character saved under another form of its name
-- (first name only, an older client's key) is the same character and is merged into this one
function Store:Adopt()
	local db = self.db
	if not db then return end
	local guid = NBG.Str(NBG.Call(_G.UnitGUID, "player"))
	if not guid then return end
	local key = NBG:PlayerKey()
	local mine = db.chars[key]
	local same = {}
	for k, c in pairs(db.chars) do if k ~= key and type(c) == "table" and c.guid == guid then same[#same + 1] = k end end
	for _, k in ipairs(same) do
		local c = db.chars[k]
		do
			if not mine or (tonumber(c.updated) or 0) > (tonumber(mine.updated) or 0) then
				db.chars[key] = c
				mine = c
			end
			db.chars[k] = nil
			if db.profileKeys and db.profileKeys[k] then
				db.profileKeys[key] = db.profileKeys[key] or db.profileKeys[k]
				db.profileKeys[k] = nil
			end
		end
	end
	mine = mine or {}
	db.chars[key] = mine
	mine.guid = guid
end

local function Pack(e)
	if not e or not e.str then return nil end
	local s = e.str .. ";" .. (e.count or 1)
	if e.bound then s = s .. ";b" end
	return s
end

local function Unpack(s)
	if type(s) ~= "string" then return nil end
	local str, count, flags = s:match("^([^;]+);?(%d*);?(%a*)$")
	if not str then return nil end
	local id = tonumber(str:match("item:(%d+)"))
	return { str = str, link = str, id = id, count = tonumber(count) or 1, boundSaved = flags == "b", live = false }
end
Store.Unpack = Unpack

local function Me()
	local key = NBG:PlayerKey()
	local c = Store.db and Store.db.chars[key]
	if not c then
		if not Store.db then return nil end
		c = {}
		Store.db.chars[key] = c
	end
	return c, key
end

local function SaveBags(c, place)
	local out = {}
	local total = 0
	for _, bag in ipairs(Containers:Bags(place)) do
		local info = Containers:Info(bag)
		total = total + (info.size or 0)
		local items = {}
		local t = Containers:Read(bag)
		for slot = 1, info.size do
			local p = Pack(t[slot])
			if p then items[slot] = p end
		end
		out[#out + 1] = { id = bag, size = info.size, family = info.family, icon = info.icon, name = info.name, kind = info.kind, items = items }
	end
	-- the game answers "no slots at all" while it loads in and as it logs out: a read like that is
	-- not the character's bags, so it never replaces the ones saved (the backpack always has slots)
	if total == 0 and type(c[place]) == "table" and #c[place] > 0 then return false end
	if place == "bags" and total == 0 then return false end
	c[place] = out
	c[place .. "Seen"] = NBG:Now()
end

function Store:SaveMe(what)
	local c, key = Me()
	if not c then return end
	local _, class = NBG.Call(_G.UnitClass, "player")
	c.class = Str(class) or c.class
	c.level = Num(NBG.Call(_G.UnitLevel, "player")) or c.level
	c.race = Str(NBG.Call(_G.UnitRace, "player")) or c.race
	c.faction = Str(NBG.Call(_G.UnitFactionGroup, "player")) or c.faction
	c.money = Containers:Money()
	c.guild = Str(NBG.Call(_G.GetGuildInfo, "player")) or nil
	c.updated = NBG:Now()
	if what == "bags" or what == "all" then SaveBags(c, "bags") end
	if (what == "bank" or what == "all") and Containers:BankOpen() then SaveBags(c, "bank") end
	Bump()
end

NBG:Register("BAGS_CHANGED", function(_, set)
	NBG:Debounce("storeBags", 0.6, function()
		Store:SaveMe("bags")
		if Containers:BankOpen() then Store:SaveMe("bank") end
	end)
end)
NBG:Register("BANK_OPEN", function(_, open)
	if open then NBG:After(0.4, function() Store:SaveMe("bank") end) end
end)
NBG:Register("MONEY", function() local c = Me() if c then c.money = Containers:Money() Bump() end end)
NBG:Register("LOGIN", function() NBG:After(2, function() Store:SaveMe("bags") end) end)
-- (nothing is read at logout: the game has emptied its answers by then, and every change was
-- already saved as it happened)

---------------------------------------------------------------------------------------------
-- mail: what waits in the mailbox, and what was just sent to one of the account's characters
---------------------------------------------------------------------------------------------
local ATT = NBG.Const("ATTACHMENTS_MAX_RECEIVE", 16)

local function ReadInbox()
	local c = Me()
	if not c or type(_G.GetInboxNumItems) ~= "function" then return end
	local n = Num(NBG.Call(GetInboxNumItems)) or 0
	local list = {}
	for i = 1, n do
		local ok, _, _, sender, _, _, _, daysLeft, hasItem = pcall(GetInboxHeaderInfo, i)
		if ok and hasItem then
			for a = 1, ATT do
				local link = Str(NBG.Call(_G.GetInboxItemLink, i, a))
				if link then
					local count = select(4, NBG.Call(_G.GetInboxItem, i, a))
					local s = Containers.ItemString(link)
					if s then
						list[#list + 1] = { s = s .. ";" .. (Num(count) or 1), from = Str(sender), until_ = NBG:Now() + math.floor((Num(daysLeft) or 0) * 86400) }
					end
				end
			end
		end
	end
	c.mail = list
	c.mailSeen = NBG:Now()
	Bump()
end
NBG:On("MAIL_INBOX_UPDATE", function() NBG:Debounce("inbox", 0.3, ReadInbox) end)

-- items sent to another character of this account land in its mailbox record at once
local function OnSend(recipient)
	recipient = Str(recipient)
	if not recipient or not Store.db then return end
	local target
	local want = recipient:lower():gsub("%s+", " ")
	for key in pairs(Store.db.chars) do
		local k = key:lower()
		if k == want or k:match("^(.-) %- ") == want then target = key break end
	end
	if not target or target == NBG:PlayerKey() then return end
	local c = Store.db.chars[target]
	c.mail = c.mail or {}
	for a = 1, NBG.Const("ATTACHMENTS_MAX_SEND", 12) do
		local link = Str(NBG.Call(_G.GetSendMailItemLink, a))
		if link then
			local count = select(4, NBG.Call(_G.GetSendMailItem, a))
			local s = Containers.ItemString(link)
			if s then table.insert(c.mail, { s = s .. ";" .. (Num(count) or 1), from = NBG:PlayerKey(), until_ = NBG:Now() + 30 * 86400 }) end
		end
	end
	Bump()
end
-- (the old global and C_Mail's both are followed; when one calls the other, the send counts once)
local lastSend = 0
local function Sent(recipient)
	local now = NBG:Clock()
	if now - lastSend < 0.5 then return end
	lastSend = now
	NBG:Safe("send mail", OnSend, recipient)
end
NBG:Register("LOGIN", function()
	if type(_G.SendMail) == "function" then hooksecurefunc("SendMail", Sent) end
	local CM = rawget(_G, "C_Mail")
	if type(CM) == "table" and type(CM.SendMail) == "function" then hooksecurefunc(CM, "SendMail", Sent) end
end)

---------------------------------------------------------------------------------------------
-- guild banks
---------------------------------------------------------------------------------------------
function Store:HasGuildBank()
	return type(_G.GetNumGuildBankTabs) == "function" and type(_G.GetGuildBankItemLink) == "function"
end

function Store:SaveGuildTab(tab)
	if not self:HasGuildBank() or not self.db then return end
	local guild = Str(NBG.Call(_G.GetGuildInfo, "player"))
	if not guild then return end
	local g = self.db.guilds[guild] or { tabs = {} }
	self.db.guilds[guild] = g
	g.money = Num(NBG.Call(_G.GetGuildBankMoney)) or g.money
	g.updated = NBG:Now()
	local n = Num(NBG.Call(GetNumGuildBankTabs)) or 0
	for i = 1, n do
		local name, icon, viewable = NBG.Call(_G.GetGuildBankTabInfo, i)
		g.tabs[i] = g.tabs[i] or {}
		g.tabs[i].name, g.tabs[i].icon, g.tabs[i].viewable = Str(name) or (L["Tab"] .. " " .. i), icon, viewable and true or false
	end
	for i = n + 1, 8 do g.tabs[i] = nil end
	tab = Num(tab)
	if tab and g.tabs[tab] then
		local items = {}
		for slot = 1, NBG.Const("MAX_GUILDBANK_SLOTS_PER_TAB", 98) do
			local link = Str(NBG.Call(GetGuildBankItemLink, tab, slot))
			if link then
				local _, count = NBG.Call(_G.GetGuildBankItemInfo, tab, slot)
				local s = Containers.ItemString(link)
				if s then items[slot] = s .. ";" .. (Num(count) or 1) end
			end
		end
		g.tabs[tab].items = items
		g.tabs[tab].seen = NBG:Now()
	end
	Bump()
end

function Store:Guild(name) return self.db and self.db.guilds[name] end

---------------------------------------------------------------------------------------------
-- reading records
---------------------------------------------------------------------------------------------
function Store:Char(key) return self.db and self.db.chars[key] end

function Store:Characters()
	local out = {}
	if not self.db then return out end
	for key, c in pairs(self.db.chars) do
		out[#out + 1] = { key = key, class = c.class, level = c.level, money = c.money or 0, updated = c.updated, guild = c.guild, faction = c.faction }
	end
	table.sort(out, function(a, b) return a.key:lower() < b.key:lower() end)
	return out
end

function Store:Forget(key)
	if self.db and key ~= NBG:PlayerKey() then self.db.chars[key] = nil Bump() return true end
	return false
end

function Store:Bags(key, place)
	local c = self:Char(key)
	local out = {}
	for _, b in ipairs(c and c[place] or {}) do
		out[#out + 1] = { id = b.id, size = b.size or 0, family = b.family or 0, icon = b.icon, name = b.name, kind = b.kind,
			special = Containers:FamilyKind(b.family), place = place }
	end
	return out
end

function Store:Entries(key, place)
	local c = self:Char(key)
	local out = {}
	for _, b in ipairs(c and c[place] or {}) do
		for slot, s in pairs(b.items or {}) do
			local e = Unpack(s)
			if e then e.bag, e.slot, e.place, e.owner = b.id, slot, place, key out[#out + 1] = e end
		end
	end
	table.sort(out, function(a, b) if a.bag ~= b.bag then return a.bag < b.bag end return a.slot < b.slot end)
	return out
end

-- the saved slots of one bag (offline One bag view)
function Store:BagSlots(key, place, bag)
	local c = self:Char(key)
	for _, b in ipairs(c and c[place] or {}) do
		if b.id == bag then
			local out = {}
			for slot, s in pairs(b.items or {}) do
				local e = Unpack(s)
				if e then e.bag, e.slot, e.place, e.owner = bag, slot, place, key out[slot] = e end
			end
			return out
		end
	end
	return {}
end

function Store:Mail(key)
	local c = self:Char(key)
	local out = {}
	local now = NBG:Now()
	for i, m in ipairs(c and c.mail or {}) do
		if not m.until_ or m.until_ > now then
			local e = Unpack(m.s)
			if e then e.place, e.owner, e.from, e.expires, e.slot, e.bag = "mail", key, m.from, m.until_, i, 0 out[#out + 1] = e end
		end
	end
	return out
end

function Store:GuildEntries(name, tab)
	local g = self:Guild(name)
	local out = {}
	if not g then return out end
	for t, data in pairs(g.tabs or {}) do
		if not tab or tab == t then
			for slot, s in pairs(data.items or {}) do
				local e = Unpack(s)
				if e then e.place, e.owner, e.tab, e.bag, e.slot = "guild", name, t, t, slot out[#out + 1] = e end
			end
		end
	end
	return out
end

---------------------------------------------------------------------------------------------
-- Everywhere and tooltip counts
---------------------------------------------------------------------------------------------
local function Add(list, owner, where, count, kind, tab)
	for _, r in ipairs(list) do
		if r.owner == owner and r.where == where then r.count = r.count + count return end
	end
	list[#list + 1] = { owner = owner, where = where, count = count, kind = kind, tab = tab }
end

-- every place matching entries are, for a filter fn(entry) -> bool (Everywhere)
function Store:Find(match, opts)
	opts = opts or {}
	local byItem = {}
	local order = {}
	local function Take(e, owner, where, kind, tab)
		if not e.id or not match(e) then return end
		local rec = byItem[e.id]
		if not rec then
			rec = { id = e.id, link = e.link, str = e.str, total = 0, places = {} }
			byItem[e.id] = rec
			order[#order + 1] = rec
		end
		rec.total = rec.total + (e.count or 1)
		Add(rec.places, owner, where, e.count or 1, kind, tab)
	end
	for key in pairs(self.db and self.db.chars or {}) do
		if not opts.only or opts.only == key then
			if opts.bags ~= false then for _, e in ipairs(self:Entries(key, "bags")) do Take(e, key, "bags", "backpack") end end
			if opts.bank ~= false then
				for _, e in ipairs(self:Entries(key, "bank")) do Take(e, key, "bank", "bank") end
			end
			if opts.mail ~= false then for _, e in ipairs(self:Mail(key)) do Take(e, key, "mail", "mail") end end
		end
	end
	if opts.guild ~= false and not opts.only then
		for name, g in pairs(self.db and self.db.guilds or {}) do
			for t, data in pairs(g.tabs or {}) do
				for slot, s in pairs(data.items or {}) do
					local e = Unpack(s)
					if e then Take(e, name, "guild", "guild", t) end
				end
			end
		end
	end
	table.sort(order, function(a, b) return a.total > b.total end)
	for _, rec in ipairs(order) do table.sort(rec.places, function(a, b) return a.count > b.count end) end
	return order
end

local totals, totalsGen = {}, -1
function Store:Totals(id)
	if not id or not self.db then return nil end
	if totalsGen ~= gen then NBG.wipe(totals) totalsGen = gen end
	local t = totals[id]
	if t ~= nil then return t or nil end
	local res = { owners = {}, guilds = {} }
	local any = false
	for key, c in pairs(self.db.chars) do
		local o = { bags = 0, bank = 0, mail = 0 }
		for _, place in ipairs({ "bags", "bank" }) do
			for _, b in ipairs(c[place] or {}) do
				for _, s in pairs(b.items or {}) do
					local sid, cnt = s:match("^item:(%d+)[^;]*;(%d+)")
					if tonumber(sid) == id then o[place] = o[place] + (tonumber(cnt) or 1) end
				end
			end
		end
		for _, m in ipairs(c.mail or {}) do
			local sid, cnt = (m.s or ""):match("^item:(%d+)[^;]*;(%d+)")
			if tonumber(sid) == id then o.mail = o.mail + (tonumber(cnt) or 1) end
		end
		if o.bags + o.bank + o.mail > 0 then res.owners[#res.owners + 1] = { key = key, class = c.class, bags = o.bags, bank = o.bank, mail = o.mail } any = true end
	end
	for name, g in pairs(self.db.guilds) do
		local n = 0
		for _, data in pairs(g.tabs or {}) do
			for _, s in pairs(data.items or {}) do
				local sid, cnt = s:match("^item:(%d+)[^;]*;(%d+)")
				if tonumber(sid) == id then n = n + (tonumber(cnt) or 1) end
			end
		end
		if n > 0 then res.guilds[#res.guilds + 1] = { name = name, count = n } any = true end
	end
	table.sort(res.owners, function(a, b) return (a.bags + a.bank + a.mail) > (b.bags + b.bank + b.mail) end)
	totals[id] = any and res or false
	return any and res or nil
end

-- age of a record, readable
function Store.Ago(t)
	if not t then return L["never"] end
	local s = math.max(0, NBG:Now() - t)
	if s < 90 then return L["just now"] end
	if s < 3600 then return math.floor(s / 60) .. " " .. L["min ago"] end
	if s < 86400 * 2 then return math.floor(s / 3600) .. " " .. L["h ago"] end
	return math.floor(s / 86400) .. " " .. L["days ago"]
end
