--[[ NetherBags - Data/Rules.lua
	The rule engine behind custom groups and the search box. A rule is plain data, never code:

	  { p = "<property>", o = "<operator>", v = <value> }

	  Rules.PROPS[id]            { id, label, kind = "text"|"number"|"money"|"quality"|"choice"|"bool",
	                               ops = { ... }, choices = function() -> { { value, label } } }
	  Rules.OPS[kind]            { { id, label } } the operators a kind allows
	  Rules:Match(entry, rules, mode)   mode "all" | "any"; an empty rule list matches nothing
	  Rules:Test(entry, rule)           one rule
	  Rules:Value(entry, prop)          the property's value for an item (shown by the editor's preview)
	  Rules:Register(def)               plugins add properties (id: lower-case letters, digits, _)
	  Rules:Clean(rule) -> rule | nil   a rule fit to keep (used by import and the editor) ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Rules = NBG:Module("Rules")
local Items = NBG.Items

local type, pairs, ipairs, tostring, tonumber, lower = type, pairs, ipairs, tostring, tonumber, string.lower
local Num, Str = NBG.Num, NBG.Str

Rules.OPS = {
	text = { { id = "has", label = L["contains"] }, { id = "is", label = L["is"] }, { id = "starts", label = L["starts with"] }, { id = "hasnot", label = L["does not contain"] } },
	number = { { id = "ge", label = L["at least"] }, { id = "le", label = L["at most"] }, { id = "eq", label = L["is"] }, { id = "ne", label = L["is not"] } },
	choice = { { id = "is", label = L["is"] }, { id = "isnot", label = L["is not"] } },
	bool = { { id = "is", label = L["is"] } },
	-- a saved search ("Save as group"): the item matches the search text
	query = { { id = "match", label = L["matches"] }, { id = "nomatch", label = L["does not match"] } },
}
Rules.OPS.money = Rules.OPS.number
Rules.OPS.quality = Rules.OPS.number

local OPSET = {}
for kind, list in pairs(Rules.OPS) do
	OPSET[kind] = {}
	for _, o in ipairs(list) do OPSET[kind][o.id] = true end
end

local function I(e)
	if e._info == nil then e._info = (e.link and Items:Info(e.link)) or false end
	return e._info or nil
end
Rules.InfoOf = I

local QUALITIES = function()
	local out = {}
	for q = 0, 5 do out[#out + 1] = { value = q, label = Items:QualityName(q) } end
	return out
end

Rules.PROPS = {}
Rules.ORDER = {}

function Rules:Register(def)
	if type(def) ~= "table" or type(def.id) ~= "string" or not def.id:match("^[a-z0-9_]+$") then return nil, "bad id" end
	if self.PROPS[def.id] then return nil, "taken" end
	if not self.OPS[def.kind] or type(def.get) ~= "function" then return nil, "bad kind or get" end
	def.label = type(def.label) == "string" and def.label or def.id
	self.PROPS[def.id] = def
	self.ORDER[#self.ORDER + 1] = def.id
	return def
end

local R = function(def) Rules:Register(def) end
R { id = "name", label = L["Name"], kind = "text", get = function(e) local i = I(e) return i and i.name end }
R { id = "type", label = L["Type"], kind = "choice", get = function(e) local i = I(e) return i and i.classID or (e.id and Items:Instant(e.id)) end,
	choices = function() local out = {} for _, c in ipairs(Items.CLASSES) do out[#out + 1] = { value = c.id, label = Items:ClassName(c.id) } end return out end }
R { id = "subtype", label = L["Subtype"], kind = "text", get = function(e) local i = I(e) return i and i.subType end }
R { id = "slot", label = L["Equip slot"], kind = "choice", get = function(e) local i = I(e) return i and i.equipLoc end,
	choices = function()
		local out = {}
		for _, loc in ipairs({ "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST", "INVTYPE_ROBE", "INVTYPE_WRIST",
			"INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON",
			"INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT",
			"INVTYPE_THROWN", "INVTYPE_RELIC", "INVTYPE_BODY", "INVTYPE_TABARD", "INVTYPE_BAG", "INVTYPE_QUIVER", "INVTYPE_AMMO" }) do
			out[#out + 1] = { value = loc, label = Items:SlotName(loc) or loc }
		end
		return out
	end }
R { id = "quality", label = L["Quality"], kind = "quality", get = function(e) if e.quality then return e.quality end local i = I(e) return i and i.quality end, choices = QUALITIES }
R { id = "ilvl", label = L["Item level"], kind = "number", get = function(e) local i = I(e) return i and i.ilvl end }
R { id = "reqlevel", label = L["Required level"], kind = "number", get = function(e) local i = I(e) return i and i.reqLevel end }
R { id = "binding", label = L["Binding"], kind = "choice", get = function(e) return Items:Binding(e) end,
	choices = function() return { { value = "soulbound", label = L["Soulbound"] }, { value = "boe", label = L["Bind on equip"] },
		{ value = "bou", label = L["Bind on use"] }, { value = "quest", label = L["Quest item"] }, { value = "none", label = L["Not binding"] } } end }
R { id = "value", label = L["Vendor value (stack)"], kind = "money", get = function(e) local i = I(e) return i and (i.price or 0) * (e.count or 1) end }
R { id = "unitvalue", label = L["Vendor value (each)"], kind = "money", get = function(e) local i = I(e) return i and (i.price or 0) end }
R { id = "count", label = L["Count"], kind = "number", get = function(e) return e.count or 1 end }
R { id = "upgrade", label = L["Upgrade"], kind = "bool", get = function(e) return (e.live ~= false and Items:Upgrade(e)) and true or false end }
R { id = "new", label = L["New item"], kind = "bool", get = function(e) return e.new and true or false end }
R { id = "unseen", label = L["Unseen appearance"], kind = "bool", get = function(e) return Items:Unseen(e.link) and true or false end }
R { id = "quest", label = L["Quest item"], kind = "bool", get = function(e) local i = I(e) return (e.quest or (i and i.classID == 12) or Items:QuestNeeded(e)) and true or false end }
R { id = "needed", label = L["Needed by a quest in your log"], kind = "bool", get = function(e) return Items:QuestNeeded(e) and true or false end }
R { id = "unusable", label = L["Can't use yet"], kind = "bool", get = function(e) local ok = Items:CanUse(e) return not ok end }
R { id = "recent", label = L["Looted this session"], kind = "bool", get = function(e) return Items:IsRecent(e) and true or false end }
R { id = "outgrown", label = L["Outgrown gear"], kind = "bool", get = function(e) return Items:Outgrown(e) and true or false end }
R { id = "tracked", label = L["Tracked in the footer"], kind = "bool", get = function(e) local t = NBG.Settings:Profile().tracked return e.id and t and t[e.id] ~= nil or false end }
R { id = "search", label = L["Matches a search"], kind = "query", get = function(e) return e end }
R { id = "set", label = L["In a gear set"], kind = "bool", get = function(e) return Items:InSet(e.id) end }
R { id = "locked", label = L["Locked"], kind = "bool", get = function(e) return NBG.Marks:IsLocked(e.id) end }
R { id = "junk", label = L["Junk"], kind = "bool", get = function(e) return NBG.Marks:IsJunk(e) end }
R { id = "place", label = L["Where"], kind = "choice", get = function(e) return e.place end,
	choices = function() return { { value = "bags", label = L["Bags"] }, { value = "bank", label = L["Bank"] }, { value = "guild", label = L["Guild bank"] }, { value = "mail", label = L["Mailbox"] } } end }
R { id = "bag", label = L["Bag or tab number"], kind = "number", get = function(e) return e.bagIndex or e.tab or e.bag end }
R { id = "family", label = L["Special bag"], kind = "choice", get = function(e) return e.family or "none" end,
	choices = function()
		local out = { { value = "none", label = L["Ordinary bag"] } }
		for _, f in ipairs(NBG.Containers.FAMILIES) do out[#out + 1] = { value = f.id, label = f.label } end
		return out
	end }
R { id = "id", label = L["Item ID"], kind = "number", get = function(e) return e.id end }

function Rules:Value(e, p)
	local def = self.PROPS[p]
	if not def then return nil end
	local ok, v = pcall(def.get, e)
	if not ok then return nil end
	return v
end

function Rules:Test(e, rule)
	local def = self.PROPS[rule.p]
	if not def then return false end
	local v = self:Value(e, rule.p)
	local o, want = rule.o, rule.v
	local kind = def.kind
	if kind == "text" then
		if v == nil then return o == "hasnot" end
		v = lower(tostring(v))
		want = lower(tostring(want or ""))
		if o == "has" then return v:find(want, 1, true) ~= nil
		elseif o == "is" then return v == want
		elseif o == "starts" then return v:sub(1, #want) == want
		elseif o == "hasnot" then return v:find(want, 1, true) == nil end
		return false
	elseif kind == "number" or kind == "money" or kind == "quality" then
		v, want = Num(v), Num(want)
		if not (v and want) then return false end
		if o == "ge" then return v >= want elseif o == "le" then return v <= want
		elseif o == "eq" then return v == want elseif o == "ne" then return v ~= want end
		return false
	elseif kind == "choice" then
		if o == "is" then return v == want elseif o == "isnot" then return v ~= want end
		return false
	elseif kind == "bool" then
		return (v and true or false) == (want and true or false)
	elseif kind == "query" then
		local S = NBG.Search
		local q = S and S:CompileCached(want)
		local m = q and S:Match(e, q) or false
		if o == "match" then return m elseif o == "nomatch" then return not m end
		return false
	end
	return false
end

function Rules:Match(e, rules, mode)
	if type(rules) ~= "table" or #rules == 0 then return false end
	if mode == "any" then
		for _, r in ipairs(rules) do if self:Test(e, r) then return true end end
		return false
	end
	for _, r in ipairs(rules) do if not self:Test(e, r) then return false end end
	return true
end

-- a rule fit to keep, or nil
function Rules:Clean(r)
	if type(r) ~= "table" or type(r.p) ~= "string" then return nil end
	local def = self.PROPS[r.p]
	if not def then return nil end
	if type(r.o) ~= "string" or not OPSET[def.kind][r.o] then return nil end
	local v = r.v
	if def.kind == "text" or def.kind == "query" then
		if type(v) ~= "string" then return nil end
		if def.kind == "query" then v = v:gsub("|+", " or "):sub(1, 200)    -- ("|" is the search's OR)
		else v = v:gsub("|", ""):sub(1, 80) end
	elseif def.kind == "number" or def.kind == "money" or def.kind == "quality" then
		v = Num(v)
		if not v then return nil end
	elseif def.kind == "choice" then
		if type(v) ~= "string" and type(v) ~= "number" then return nil end
		if type(v) == "string" then v = v:sub(1, 60) end
	elseif def.kind == "bool" then
		v = v and true or false
	end
	return { p = r.p, o = r.o, v = v }
end

function Rules:Default(p)
	local def = self.PROPS[p]
	if not def then return nil end
	local o = self.OPS[def.kind][1].id
	local v
	if def.kind == "text" or def.kind == "query" then v = ""
	elseif def.kind == "bool" then v = true
	elseif def.kind == "choice" then local c = def.choices and def.choices() or {} v = c[1] and c[1].value or ""
	elseif def.kind == "quality" then v = 2
	else v = 0 end
	return { p = p, o = o, v = v }
end
