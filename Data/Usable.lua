--[[ NetherBags - Data/Usable.lua
	What an item means for this character, beyond its item data:

	  Items:CanUse(e) -> true | false, reason, text
	      false when the game's tooltip shows a requirement this character does not meet (the game
	      writes those lines in red): reason "level" (requires a higher level), "known" (recipe or
	      spell already known), "skill" (needs more of a profession), "lockpick" (a lockbox beyond
	      your Lockpicking), "class" (another class's item), "equip" (armour or weapon kind you
	      can't wear or wield), "other". text: the game's own line, shown under the item's name.
	  Items:QuestNeeded(e) -> bool
	      a quest in the log asks for this item ("Linen Cloth: 3/10"): such items are treated as
	      quest items (never sold, stashed or deleted by NetherBags)
	  Items:Outgrown(e) -> bool
	      soulbound gear (common or uncommon) at least 10 item levels below what you wear in that
	      slot, not in a gear set, not locked (setting junk.outgrown)
	  Items:IsRecent(e) -> bool
	      looted (or received) this session: the bags held more of it than at login, from loot,
	      not from the bank, the mailbox, a trade or the guild bank ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Items = NBG.Items

local type, pairs, ipairs, tostring, tonumber, lower = type, pairs, ipairs, tostring, tonumber, string.lower
local Num, Str = NBG.Num, NBG.Str

---------------------------------------------------------------------------------------------
-- can't use yet: the red lines of the item's tooltip
---------------------------------------------------------------------------------------------
-- a format string of the game's ("Requires Level %d") -> a pattern that finds it
local function Pat(fmt, fallback)
	local s = type(fmt) == "string" and fmt or fallback
	if not s then return nil end
	s = s:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	s = s:gsub("%%d", "(%%d+)"):gsub("%%s", "(.+)")
	return "^" .. s .. "$"
end
local P = {}
local function Patterns()
	if P.level then return P end
	P.level = Pat(rawget(_G, "ITEM_MIN_LEVEL"), "Requires Level %d")
	P.skill = Pat(rawget(_G, "ITEM_MIN_SKILL"), "Requires %s (%d)")
	P.known = Str(rawget(_G, "ITEM_SPELL_KNOWN")) or "Already known"
	P.classes = Pat(rawget(_G, "ITEM_CLASSES_ALLOWED"), "Classes: %s")
	P.lockpick = lower(Str(rawget(_G, "LOCKPICKING")) or "Lockpicking")
	return P
end

local function Red(c)
	if type(c) ~= "table" then return false end
	local r, g, b = Num(c.r), Num(c.g), Num(c.b)
	if not (r and g and b) and c.GetRGB then r, g, b = c:GetRGB() end
	return r and g and b and r > 0.9 and g < 0.3 and b < 0.3 or false
end

local function Classify(text)
	local p = Patterns()
	if text == p.known then return "known" end
	if p.level and text:match(p.level) then return "level" end
	if p.skill then
		local skill = text:match(p.skill)
		if skill then return lower(skill) == p.lockpick and "lockpick" or "skill" end
	end
	if p.classes and text:match(p.classes) then return "class" end
	return nil
end

local useCache = {}
local function ResetUse() NBG.wipe(useCache) end
for _, ev in ipairs({ "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB", "NEW_RECIPE_LEARNED", "SPELLS_CHANGED", "TRADE_SKILL_UPDATE" }) do
	NBG:On(ev, function() ResetUse() NBG:Debounce("usableChanged", 0.5, function() NBG:Fire("USABLE_CHANGED") end) end)
end

local function TooltipLines(e)
	local T = rawget(_G, "C_TooltipInfo")
	if type(T) ~= "table" then return nil end
	local ok, data
	if e.live ~= false and e.bag and e.slot and T.GetBagItem then ok, data = pcall(T.GetBagItem, e.bag, e.slot)
	elseif e.link and T.GetHyperlink then ok, data = pcall(T.GetHyperlink, e.link) end
	data = ok and NBG.Open(data) or nil
	return data and NBG.Open(data.lines) or nil
end

function Items:CanUse(e)
	if not (e and e.link) then return true end
	-- (in combat the game adds a red line to gear tooltips: answers kept from before)
	local key = (e.live ~= false and e.bag and e.slot) and (e.bag .. ":" .. e.slot .. ":" .. e.link) or e.link
	local c = useCache[key]
	if c then return c[1], c[2], c[3] end
	if NBG:InCombat() then return true end
	local lines = TooltipLines(e)
	if not lines then return true end
	local can, reason, text = true, nil, nil
	for i, line in ipairs(lines) do
		line = NBG.Open(line)
		if line and i > 1 then
			local lt, rt = Str(line.leftText), Str(line.rightText)
			if lt and Red(line.leftColor) then
				local r = Classify(lt)
				if r or not reason then can, reason, text = false, r or "other", lt end
				if r then break end
			elseif rt and Red(line.rightColor) and not reason then
				can, reason, text = false, "equip", rt
			end
		end
	end
	useCache[key] = { can, reason, text }
	return can, reason, text
end
NBG:Register("BAGS_CHANGED", function() ResetUse() end)
NBG:Register("ITEMS_LOADED", function() ResetUse() end)

Items.USE_REASON = {
	level = L["Requires a higher level"], known = L["Already known"], skill = L["Needs more skill"],
	lockpick = L["Needs more Lockpicking"], class = L["For another class"], equip = L["You can't use this kind"], other = L["Can't use yet"],
}

---------------------------------------------------------------------------------------------
-- needed by a quest in the log
---------------------------------------------------------------------------------------------
local needed = {}       -- lower-case item name -> true
local function Objectives()
	NBG.wipe(needed)
	local Q = rawget(_G, "C_QuestLog")
	local n
	if type(Q) == "table" and Q.GetNumQuestLogEntries then n = Num(NBG.Call(Q.GetNumQuestLogEntries))
	elseif _G.GetNumQuestLogEntries then n = Num(NBG.Call(GetNumQuestLogEntries)) end
	for i = 1, n or 0 do
		local texts = {}
		local info = type(Q) == "table" and Q.GetInfo and NBG.Open(NBG.Call(Q.GetInfo, i))
		if info then
			if not info.isHeader and Num(info.questID) and Q.GetQuestObjectives then
				for _, o in ipairs(NBG.Open(NBG.Call(Q.GetQuestObjectives, info.questID)) or {}) do
					o = NBG.Open(o)
					if o and (o.type == "item" or o.type == nil) then texts[#texts + 1] = Str(o.text) end
				end
			end
		elseif _G.GetQuestLogLeaderBoard and _G.GetNumQuestLeaderBoards then
			for j = 1, Num(NBG.Call(GetNumQuestLeaderBoards, i)) or 0 do
				local text, kind = NBG.Call(GetQuestLogLeaderBoard, j, i)
				if kind == "item" then texts[#texts + 1] = Str(text) end
			end
		end
		for _, t in ipairs(texts) do
			-- "Linen Cloth: 3/10", or "3/10 Linen Cloth" on some clients
			local name = t:match("^(.-):%s*%d+%s*/%s*%d+") or t:match("^%d+%s*/%s*%d+%s+(.+)$")
			if name and name ~= "" then needed[lower(name)] = true end
		end
	end
end
local function Rebuild() Objectives() NBG:Fire("QUEST_NEEDS") end
NBG:On("QUEST_LOG_UPDATE", function() NBG:Debounce("questNeeds", 0.5, Rebuild) end)
NBG:Register("LOGIN", function() NBG:After(2, Rebuild) end)

function Items:QuestNeeded(e)
	if not (e and (e.link or e.id)) then return false end
	if next(needed) == nil then return false end
	local i = e.link and self:Info(e.link)
	return i and i.name and needed[lower(i.name)] or false
end
Items.Needed = function() return needed end

---------------------------------------------------------------------------------------------
-- outgrown soulbound gear
---------------------------------------------------------------------------------------------
local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}
local OUTGROWN_BY = 10
function Items:Outgrown(e)
	if not (e and e.link and e.live ~= false) then return false end
	if not NBG.Settings:Get("junk.outgrown") then return false end
	if NBG.Marks:IsLocked(e.id) or self:InSet(e.id) or self:QuestNeeded(e) then return false end
	if self:Binding(e) ~= "soulbound" then return false end
	local i = self:Info(e.link)
	if not (i and (i.classID == 2 or i.classID == 4) and (i.quality or 0) <= 2 and (i.ilvl or 0) > 0) then return false end
	local slots = SLOTS[i.equipLoc]
	if not slots then return false end
	-- never trinkets, fishing poles, or anything with an effect of its own ("Use:", "Equip:",
	-- "Chance on hit:"): those are kept for what they do, not for their item level
	if i.equipLoc == "INVTYPE_TRINKET" then return false end
	if i.classID == 2 and i.subClassID == 20 then return false end
	local S = NBG.Search
	local tip = S and S.TooltipText and S:TooltipText(e)
	if tip == nil then return false end      -- (not readable yet: not judged)
	local function has(g, fb) local t = rawget(_G, g) t = type(t) == "string" and t or fb return tip:find(lower(t), 1, true) ~= nil end
	if has("ITEM_SPELL_TRIGGER_ONUSE", "Use:") or has("ITEM_SPELL_TRIGGER_ONEQUIP", "Equip:") or has("ITEM_SPELL_TRIGGER_ONPROC", "Chance on hit:") then return false end
	-- the weakest of what you wear there (two rings: the lower one)
	local worn
	for _, s in ipairs(slots) do
		local link = Str(NBG.Call(_G.GetInventoryItemLink, "player", s))
		local wi = link and self:Info(link)
		if not wi then return false end           -- an empty slot: the item may still be of use
		worn = worn and math.min(worn, wi.ilvl or 0) or (wi.ilvl or 0)
	end
	return worn ~= nil and i.ilvl <= worn - OUTGROWN_BY
end

---------------------------------------------------------------------------------------------
-- looted this session
---------------------------------------------------------------------------------------------
local base, recent = nil, {}      -- id -> count at login / id -> time first seen growing
local function Busy()
	local C = NBG.Containers
	if C:BankOpen() then return true end
	if NBG.Selling and NBG.Selling:AtMerchant() then return true end     -- (bought, not looted)
	if NBG.GuildBank and NBG.GuildBank.IsOpen and NBG.GuildBank:IsOpen() then return true end
	local mf, tf = rawget(_G, "MailFrame"), rawget(_G, "TradeFrame")
	if mf and mf.IsShown and mf:IsShown() then return true end
	if tf and tf.IsShown and tf:IsShown() then return true end
	return false
end
local function Totals()
	local t = {}
	for _, e in ipairs(NBG.Containers:All("bags")) do if e.id then t[e.id] = (t[e.id] or 0) + (e.count or 1) end end
	return t
end
local ready = false     -- (the first seconds after login: the bags are still arriving, nothing is loot)
NBG:Register("BAGS_CHANGED", function()
	NBG:Debounce("recentScan", 0.4, function()
		local now = Totals()
		-- (an empty first look means the bags had not arrived yet: it is no baseline)
		local any = next(base or {}) ~= nil
		if not base or not ready or not any then base = now return end
		if not Busy() then
			for id, n in pairs(now) do
				if n > (base[id] or 0) and not recent[id] then recent[id] = NBG:Now() end
			end
		end
		-- (what came from the bank or the mail raises the floor, so it never counts as looted)
		for id, n in pairs(now) do if Busy() or n < (base[id] or 0) then base[id] = n end end
		for id in pairs(base) do if not now[id] then base[id] = 0 end end
	end)
end)
NBG:Register("LOGIN", function() NBG:After(5, function() base = Totals() ready = true end) end)

function Items:IsRecent(e)
	return e and e.id and e.live ~= false and e.place == "bags" and recent[e.id] ~= nil or false
end
function Items:ClearRecent() NBG.wipe(recent) base = Totals() ready = true end
