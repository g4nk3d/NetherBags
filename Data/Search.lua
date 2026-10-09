--[[ NetherBags - Data/Search.lua
	The search box. A query is read once into a small tree of tests (the rule engine's, never
	code) and each item is matched against it.

	  plain words           name, type, subtype or slot contains the word ("potion", "leather")
	  "two words"           a phrase
	  -word / !word / not   NOT
	  a b  /  a and b       both (words next to each other must all match)
	  a or b  /  a | b      either
	  ( ... )               brackets: (potion or elixir) -minor
	  ilvl>20 ilvl<=30      item level (also lvl / req / reqlvl for the required level)
	  value>1g count>=5     vendor value of the stack (g / s / c), stack count
	  q:rare q>=3           quality by name or number (poor common uncommon rare epic legendary)
	  boe bop bou soulbound binding
	  upgrade new junk locked quest unseen set     the markers
	  usable unusable recent needed outgrown tracked
	  tt:text tt:"two words"  the item's tooltip contains the text ("tt:use:", tt:"chance on hit")
	  bag:2 tab:2           bag or bank tab number
	  type:armor slot:head  type / slot names, id:12345 an item ID

	  Search:Compile(text) -> query | nil (empty)
	  Search:CompileCached(text) -> query (kept, for saved searches / groups)
	  Search:Match(entry, query) -> bool ]]

local _, ns = ...
local NBG = ns.NBG
local Search = NBG:Module("Search")
local Rules = NBG.Rules
local Items = NBG.Items

local type, ipairs, tonumber, lower, gsub = type, ipairs, tonumber, string.lower, string.gsub

local QNAMES = { poor = 0, grey = 0, gray = 0, common = 1, white = 1, uncommon = 2, green = 2, rare = 3, blue = 3, epic = 4, purple = 4, legendary = 5, orange = 5 }
local BIND = { boe = "boe", bop = "soulbound", soulbound = "soulbound", bound = "soulbound", bou = "bou" }
local FLAGS = { upgrade = "upgrade", upgrades = "upgrade", new = "new", junk = "junk", locked = "locked", quest = "quest", unseen = "unseen", set = "set",
	unusable = "unusable", recent = "recent", looted = "recent", needed = "needed", outgrown = "outgrown", tracked = "tracked" }
local OPMAP = { [">="] = "ge", ["<="] = "le", [">"] = "gt", ["<"] = "lt", ["="] = "eq", [":"] = "eq", ["!="] = "ne" }

local function Money(s)
	s = lower(s)
	local total, any = 0, false
	for n, u in s:gmatch("(%d+)%s*([gsc]?)") do
		any = true
		n = tonumber(n)
		if u == "g" then total = total + n * 10000 elseif u == "s" then total = total + n * 100 else total = total + n end
	end
	return any and total or nil
end

local function Cmp(v, op, want)
	if v == nil or want == nil then return false end
	if op == "ge" then return v >= want elseif op == "le" then return v <= want elseif op == "gt" then return v > want
	elseif op == "lt" then return v < want elseif op == "eq" then return v == want elseif op == "ne" then return v ~= want end
	return false
end

local function Prop(p) return function(e) return Rules:Value(e, p) end end

local function Word(word)
	return function(e)
		local i = Rules.InfoOf(e)
		if not i then return false end
		if lower(i.name or ""):find(word, 1, true) then return true end
		if lower(i.subType or ""):find(word, 1, true) then return true end
		if lower(i.type or ""):find(word, 1, true) then return true end
		local sn = Items:SlotName(i.equipLoc)
		if sn and lower(sn):find(word, 1, true) then return true end
		return false
	end
end

local function Token(tok)
	local key, op, val = tok:match("^(%a+)([<>=!:]=?)(.+)$")
	if key then
		key = lower(key)
		local o = OPMAP[op]
		if not o then return nil end
		if key == "ilvl" or key == "il" or key == "level" then
			local n = tonumber(val) return n and function(e) return Cmp(Prop("ilvl")(e), o, n) end
		elseif key == "lvl" or key == "req" or key == "reqlevel" or key == "reqlvl" or key == "rl" then
			local n = tonumber(val) return n and function(e) return Cmp(Prop("reqlevel")(e), o, n) end
		elseif key == "value" or key == "price" or key == "v" then
			local n = Money(val) return n and function(e) return Cmp(Prop("value")(e), o, n) end
		elseif key == "count" or key == "n" then
			local n = tonumber(val) return n and function(e) return Cmp(e.count or 1, o, n) end
		elseif key == "q" or key == "quality" then
			local n = tonumber(val) or QNAMES[lower(val)]
			if o == "eq" and not tonumber(val) then o = "eq" end
			return n and function(e) return Cmp(Prop("quality")(e), o, n) end
		elseif key == "bag" or key == "tab" then
			local n = tonumber(val) return n and function(e) return Cmp(e.bagIndex or e.tab or e.bag, o, n) end
		elseif key == "id" then
			local n = tonumber(val) return n and function(e) return e.id == n end
		elseif key == "type" or key == "t" then
			val = lower(val)
			return function(e)
				local i = Rules.InfoOf(e)
				return i and (lower(i.type or ""):find(val, 1, true) or lower(i.subType or ""):find(val, 1, true)) and true or false
			end
		elseif key == "slot" then
			val = lower(val)
			return function(e)
				local i = Rules.InfoOf(e)
				local sn = i and Items:SlotName(i.equipLoc)
				return sn and lower(sn):find(val, 1, true) and true or false
			end
		elseif key == "bind" or key == "binding" then
			local b = BIND[lower(val)] return b and function(e) return Items:Binding(e) == b end
		elseif key == "tt" or key == "tip" or key == "tooltip" then
			val = lower(val)
			return function(e) local t = Search:TooltipText(e) return t ~= nil and t:find(val, 1, true) ~= nil end
		end
		return nil
	end
	local l = lower(tok)
	if BIND[l] then local b = BIND[l] return function(e) return Items:Binding(e) == b end end
	if FLAGS[l] then local p = FLAGS[l] return function(e) return Rules:Value(e, p) and true or false end end
	if l == "usable" then return function(e) return not Rules:Value(e, "unusable") end end
	if QNAMES[l] and #l > 3 and l ~= "blue" and l ~= "green" and l ~= "white" and l ~= "orange" then
		-- quality names as words also match names ("Rare Spice" is found by "rare")
		local q = QNAMES[l]
		local w = Word(l)
		return function(e) return Prop("quality")(e) == q or w(e) end
	end
	return Word(l)
end

---------------------------------------------------------------------------------------------
-- the item's tooltip as one lower-case text (kept per link)
---------------------------------------------------------------------------------------------
local tipCache, tipCount = {}, 0
function Search:TooltipText(e)
	local key = e and e.link
	if not key then return nil end
	local t = tipCache[key]
	if t ~= nil then return t or nil end
	local T = rawget(_G, "C_TooltipInfo")
	if type(T) ~= "table" or not T.GetHyperlink then return nil end
	local ok, data = pcall(T.GetHyperlink, key)
	data = ok and NBG.Open(data) or nil
	local parts = {}
	for _, line in ipairs(data and NBG.Open(data.lines) or {}) do
		line = NBG.Open(line)
		if line then
			if NBG.Str(line.leftText) then parts[#parts + 1] = line.leftText end
			if NBG.Str(line.rightText) then parts[#parts + 1] = line.rightText end
		end
	end
	if #parts == 0 then return nil end      -- (not loaded yet: asked again next time)
	t = lower(table.concat(parts, "\n"))
	if tipCount > 4000 then tipCache, tipCount = {}, 0 end
	tipCache[key] = t
	tipCount = tipCount + 1
	return t
end

---------------------------------------------------------------------------------------------
-- reading a query: words, phrases, brackets, and / or / not
---------------------------------------------------------------------------------------------
local function Tokens(text)
	local out, i, n = {}, 1, #text
	while i <= n do
		local c = text:sub(i, i)
		if c:match("%s") then
			i = i + 1
		elseif c == "(" or c == ")" then
			out[#out + 1] = { kind = c } i = i + 1
		else
			-- a word, which may hold a quoted part: -"two words"  tt:"chance on hit"
			local j, buf = i, {}
			while j <= n do
				local d = text:sub(j, j)
				if d == '"' then
					local close = text:find('"', j + 1, true)
					if not close then close = n + 1 end
					buf[#buf + 1] = { q = text:sub(j + 1, close - 1) }
					j = close + 1
				elseif d:match("%s") or d == "(" or d == ")" then
					break
				else
					buf[#buf + 1] = d
					j = j + 1
				end
			end
			local raw, quoted, plain = {}, false, {}
			for _, b in ipairs(buf) do
				if type(b) == "table" then quoted = true raw[#raw + 1] = b.q else raw[#raw + 1] = b plain[#plain + 1] = b end
			end
			out[#out + 1] = { kind = "word", text = table.concat(raw), quoted = quoted, plain = table.concat(plain) }
			i = j
		end
	end
	return out
end

local function Leaf(tok)
	local text, neg = tok.text, false
	local first = tok.plain:sub(1, 1)
	if (first == "-" or first == "!") and #text > 1 then neg, text = true, text:sub(2) end
	local fn
	if tok.quoted and not text:find(":", 1, true) and not text:find("[<>=]") then
		fn = Word(lower(text))                    -- a phrase
	else
		fn = Token(text)
	end
	if not fn then return nil end
	return { leaf = fn, neg = neg }
end

local function Parse(tokens)
	local pos = 1
	local function Peek() return tokens[pos] end
	local function IsWord(t, w) return t and t.kind == "word" and not t.quoted and lower(t.text) == w end
	local Or
	local function Primary()
		local t = Peek()
		if not t then return nil end
		if t.kind == "(" then
			pos = pos + 1
			local inner = Or()
			if Peek() and Peek().kind == ")" then pos = pos + 1 end
			return inner
		elseif t.kind == ")" then
			return nil
		end
		pos = pos + 1
		return Leaf(t)
	end
	local function Unary()
		local t = Peek()
		if IsWord(t, "not") then
			pos = pos + 1
			local inner = Unary()
			return inner and { notop = inner } or nil
		end
		-- "-(" : NOT a bracket
		if t and t.kind == "word" and (t.text == "-" or t.text == "!") and tokens[pos + 1] and tokens[pos + 1].kind == "(" then
			pos = pos + 1
			local inner = Unary()
			return inner and { notop = inner } or nil
		end
		return Primary()
	end
	local function And()
		local list = {}
		while true do
			local t = Peek()
			if not t or t.kind == ")" or IsWord(t, "or") or (t.kind == "word" and (t.text == "|" or t.text == "||")) then break end
			if IsWord(t, "and") or (t.kind == "word" and (t.text == "&" or t.text == "&&")) then
				pos = pos + 1
			else
				local before = pos
				local node = Unary()
				if node then list[#list + 1] = node end
				if pos == before then pos = pos + 1 end
			end
		end
		if #list == 0 then return nil end
		if #list == 1 then return list[1] end
		return { all = list }
	end
	function Or()
		local list = {}
		local node = And()
		if node then list[#list + 1] = node end
		while true do
			local t = Peek()
			if IsWord(t, "or") or (t and t.kind == "word" and (t.text == "|" or t.text == "||")) then
				pos = pos + 1
				local n2 = And()
				if n2 then list[#list + 1] = n2 end
			else
				break
			end
		end
		if #list == 0 then return nil end
		if #list == 1 then return list[1] end
		return { any = list }
	end
	local tree = Or()
	-- a stray ")" or anything left: read the rest as more words to match
	while pos <= #tokens do
		local rest = And()
		if rest then tree = tree and { all = { tree, rest } } or rest else pos = pos + 1 end
	end
	return tree
end

function Search:Compile(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return nil end
	local tree = Parse(Tokens(text))
	if not tree then return nil end
	return { text = text, tree = tree }
end

local compiled, nCompiled = {}, 0
function Search:CompileCached(text)
	if type(text) ~= "string" then return nil end
	local q = compiled[text]
	if q == nil then
		q = self:Compile(text) or false
		if nCompiled > 200 then compiled, nCompiled = {}, 0 end
		compiled[text] = q
		nCompiled = nCompiled + 1
	end
	return q or nil
end

local function Eval(node, e)
	if node.leaf then
		local ok, r = pcall(node.leaf, e)
		r = ok and r and true or false
		if node.neg then return not r end
		return r
	elseif node.notop then
		return not Eval(node.notop, e)
	elseif node.all then
		for _, n in ipairs(node.all) do if not Eval(n, e) then return false end end
		return true
	elseif node.any then
		for _, n in ipairs(node.any) do if Eval(n, e) then return true end end
		return false
	end
	return false
end

function Search:Match(e, q)
	if not q then return true end
	if not q.tree then return true end
	return Eval(q.tree, e)
end
