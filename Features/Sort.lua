--[[ NetherBags - Features/Sort.lua
	Sorting the bags (or the bank, at a banker) by moving the items themselves, one move at a time,
	waiting for the server between moves. Locked items stay exactly where they are (their slots are
	left out). Special bags (quivers, soul bags, herb bags...) are sorted on their own, so nothing
	is moved into a bag it does not belong in. Part stacks of the same item are merged first.
	Order: by kind (weapons, armor, jewelry, consumables, trade goods, ...), then quality, item
	level, name; junk last. Stops in combat, when dead, or when something is on the cursor.

	  Sort:Run(place [, mode])         "bags" | "bank"; mode true / "merge": only part stacks are merged;
	                                   "route": only items moved into the bag the bag menu gives them
	  Sort:Busy()
	  Sort:Freeable(place) -> n        slots merging the part stacks would free (the Sort button's hint)

	After the mailbox or a trade closes, part stacks in the bags are merged by themselves (setting
	sort.mergeAfter). ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Sort = NBG:Module("Sort")
local Containers, Items, Marks = NBG.Containers, NBG.Items, NBG.Marks

local ipairs, pairs, lower = ipairs, pairs, string.lower

local CLASS_ORDER = { [2] = 1, [4] = 2, [0] = 4, [7] = 5, [5] = 6, [3] = 7, [9] = 8, [12] = 9, [1] = 10, [6] = 11, [11] = 12, [13] = 13, [15] = 14 }
local JEWEL = { INVTYPE_FINGER = true, INVTYPE_NECK = true, INVTYPE_TRINKET = true }

local function Key(e)
	local i = Items:Info(e.link)
	local junk = Marks:IsJunk(e) and 1 or 0
	local c = i and i.classID
	local rank = CLASS_ORDER[c] or 15
	if c == 4 and i and JEWEL[i.equipLoc] then rank = 3 end
	if e.quest then rank = 0 end
	return { junk, rank, i and i.subClassID or 0, -(i and i.quality or 0), -(i and i.ilvl or 0), i and lower(i.name or "") or "", e.id or 0, -(e.count or 1) }
end

local function Less(a, b)
	for k = 1, #a do
		if a[k] ~= b[k] then return a[k] < b[k] end
	end
	return false
end

local function PickupFn() return NBG.API("C_Container", "PickupContainerItem") or _G.PickupContainerItem end

local busy
function Sort:Busy() return busy ~= nil end

local function Blocked()
	if NBG:InCombat() then return L["combat"] end
	if _G.UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return L["you are dead"] end
	if _G.GetCursorInfo and GetCursorInfo() then return L["something is on the cursor"] end
	return nil
end

-- the groups of slots that are sorted together: ordinary bags, then each special bag alone (and
-- each bag the bag menu gave kinds of items: it is sorted on its own, after the items are routed)
local function Ruled(place, bag) return place == "bags" and NBG.BagRules and NBG.BagRules:Count(bag) > 0 end
local function Groups(place)
	local plain, special = {}, {}
	for _, bag in ipairs(Containers:Bags(place)) do
		local size = Containers:Size(bag)
		if size > 0 and bag ~= Containers.KEYRING then
			local fam = Containers:Family(bag)
			-- (the reagent bag takes reagents only: sorted on its own, like a special bag)
			local own = (fam and fam > 0 and bag ~= Containers.BACKPACK and bag ~= Containers.BANK) or bag == Containers.REAGENT_BAG or Ruled(place, bag)
			local list = own and {} or plain
			for slot = 1, size do list[#list + 1] = { bag = bag, slot = slot } end
			if list ~= plain then special[#special + 1] = list end
		end
	end
	local out = { plain }
	for _, l in ipairs(special) do out[#out + 1] = l end
	return out
end

local function Same(a, b)
	if not a and not b then return true end
	if not a or not b then return false end
	return a.link == b.link and (a.count or 1) == (b.count or 1)
end

-- one move to make for a group of slots, or nil when it is in order
local function NextMove(slots, mergeOnly)
	local entries, free = {}, {}
	for _, s in ipairs(slots) do
		local e = Containers:RefreshSlot(s.bag, s.slot) or Containers:Entry(s.bag, s.slot)
		if e and e.locked then return "wait" end
		if e and Marks:IsLocked(e.id) then
			-- a locked item: its slot is not part of the sort
		else
			s.e = e
			entries[#entries + 1] = s
		end
	end
	-- 1. merge part stacks of the same item
	local partial = {}
	for _, s in ipairs(entries) do
		local e = s.e
		if e then
			local i = Items:Info(e.link)
			if i and i.stack and i.stack > 1 and (e.count or 1) < i.stack then
				local k = e.link
				if partial[k] then return { from = s, to = partial[k] } end
				partial[k] = s
			end
		end
	end
	if mergeOnly then return nil end
	-- 2. order
	local items = {}
	for _, s in ipairs(entries) do if s.e then items[#items + 1] = { e = s.e, key = Key(s.e) } end end
	table.sort(items, function(a, b) return Less(a.key, b.key) end)
	for idx, s in ipairs(entries) do
		local want = items[idx] and items[idx].e or nil
		if not Same(s.e, want) then
			if not want then return nil end
			-- find where the wanted item is now (after this position)
			for j = idx + 1, #entries do
				if Same(entries[j].e, want) then return { from = entries[j], to = s } end
			end
			return nil
		end
	end
	return nil
end

-- slots that merging part stacks would free, per sort group (a stack never crosses into a special bag)
-- routing: one move that puts an item into the bag the bag menu gives it, or takes an item that
-- doesn't belong out of a ruled bag; nil when everything is where it belongs
local function Belongs(e, bag)
	local BR = NBG.BagRules
	for _, k in ipairs(BR:Kinds()) do
		if BR:Has(bag, k.id) then local ok, r = pcall(k.test, e) if ok and r then return true end end
	end
	return false
end
local function Fits(e, bag)
	if bag ~= Containers.REAGENT_BAG then return true end
	local i = Items:Info(e.link)
	return i and (i.classID == 7 or i.classID == 5) or false
end
function Sort:RouteMove(place)
	local BR = NBG.BagRules
	if place ~= "bags" or not (BR and BR:Any()) then return nil end
	local bags, ruled = {}, {}
	for _, bag in ipairs(Containers:Bags("bags")) do
		if bag ~= Containers.KEYRING and Containers:Size(bag) > 0 then
			local fam = Containers:Family(bag)
			local special = fam and fam > 0 and bag ~= Containers.BACKPACK
			if not special then bags[#bags + 1] = bag if BR:Count(bag) > 0 then ruled[bag] = true end end
		end
	end
	local function Slot(bag, want)
		-- an empty slot of the bag, else one holding an item that doesn't belong there
		local other
		for slot = 1, Containers:Size(bag) do
			local x = Containers:Entry(bag, slot)
			if not x then return slot end
			if not other and not x.locked and not Marks:IsLocked(x.id) and not Belongs(x, bag) then other = slot end
		end
		return other
	end
	for _, bag in ipairs(bags) do
		for slot = 1, Containers:Size(bag) do
			local e = Containers:Entry(bag, slot)
			if e and e.id and not e.locked and not Marks:IsLocked(e.id) then
				local here = ruled[bag] and Belongs(e, bag)
				if not here then
					local want = BR:BagFor(e)
					if want and want ~= bag and Fits(e, want) then
						local to = Slot(want)
						if to then return { from = { bag = bag, slot = slot }, to = { bag = want, slot = to } } end
					elseif not want and ruled[bag] then
						-- in a ruled bag it doesn't belong to: out, to an empty slot of an unruled bag
						for _, b2 in ipairs(bags) do
							if not ruled[b2] then
								for s2 = 1, Containers:Size(b2) do
									if not Containers:Entry(b2, s2) then return { from = { bag = bag, slot = slot }, to = { bag = b2, slot = s2 } } end
								end
							end
						end
					end
				end
			end
		end
	end
	return nil
end

function Sort:Freeable(place)
	if place ~= "bags" and place ~= "bank" then return 0 end
	if place == "bank" and not Containers:BankOpen() then return 0 end
	local freed = 0
	for _, g in ipairs(Groups(place)) do
		local per = {}
		for _, s in ipairs(g) do
			local e = Containers:Entry(s.bag, s.slot)
			if e and e.link and not Marks:IsLocked(e.id) then
				local i = Items:Info(e.link)
				local stack = i and i.stack or 1
				if stack > 1 then
					local t = per[e.link] or { n = 0, count = 0, stack = stack }
					t.n, t.count = t.n + 1, t.count + (e.count or 1)
					per[e.link] = t
				end
			end
		end
		for _, t in pairs(per) do freed = freed + math.max(0, t.n - math.ceil(t.count / t.stack)) end
	end
	return freed
end

function Sort:Run(place, mergeOnly)
	if busy then return end
	place = place == "bank" and "bank" or "bags"
	if place == "bank" and not Containers:BankOpen() then NBG:Print(L["The bank can only be sorted at a banker."]) return end
	local why = Blocked()
	if why then NBG:Print(L["Cannot sort now: %s."], why) return end
	local pickup = PickupFn()
	if not pickup then return end
	local groups = Groups(place)
	local gi, steps = 1, 0
	busy = true
	NBG:Fire("SORT", true)
	local function Done(msg)
		busy = nil
		Containers:Invalidate()
		NBG:Fire("SORT", false, mergeOnly)
		if msg then NBG:Print(msg) end
	end
	local function Step()
		local why2 = Blocked()
		if why2 then return Done(L["Sorting stopped: "] .. why2 .. ".") end
		steps = steps + 1
		if steps > 600 then return Done(L["Sorting stopped (too many moves)."]) end
		-- first the routing (the bag menu's kinds), then each group in order
		if mergeOnly ~= true and mergeOnly ~= "merge" then
			local rm = Sort:RouteMove(place)
			if rm then
				local ok = pcall(pickup, rm.from.bag, rm.from.slot) and pcall(pickup, rm.to.bag, rm.to.slot)
				if _G.GetCursorInfo and GetCursorInfo() and _G.ClearCursor then ClearCursor() end
				if not ok then return Done(L["Sorting stopped."]) end
				NBG:After(0.15, Step)
				return
			end
			if mergeOnly == "route" then return Done() end
		end
		local g = groups[gi]
		if not g then return Done() end
		local mv = NextMove(g, mergeOnly == true or mergeOnly == "merge")
		if mv == "wait" then NBG:After(0.1, Step) return end
		if not mv then gi = gi + 1 NBG:After(0, Step) return end
		local ok = pcall(pickup, mv.from.bag, mv.from.slot) and pcall(pickup, mv.to.bag, mv.to.slot)
		if _G.GetCursorInfo and GetCursorInfo() and _G.ClearCursor then ClearCursor() end
		if not ok then return Done(L["Sorting stopped."]) end
		NBG:After(0.12, Step)
	end
	Step()
end

-- part stacks merged after the mailbox or a trade (what came in lands in new stacks)
local function MergeAfter()
	if not NBG.Settings:Get("sort.mergeAfter") then return end
	NBG:After(1, function()
		if busy or NBG:InCombat() or (_G.GetCursorInfo and GetCursorInfo()) then return end
		if Sort:Freeable("bags") > 0 then Sort:Run("bags", true) end
	end)
end
NBG:On("MAIL_CLOSED", MergeAfter)
NBG:On("TRADE_CLOSED", MergeAfter)

-- items that arrive are put into the bag the bag menu gives them (setting bags.autoRoute)
NBG:Register("BAGS_CHANGED", function()
	if not (NBG.Settings:Get("bags.autoRoute") and NBG.BagRules and NBG.BagRules:Any()) then return end
	NBG:Debounce("autoRoute", 0.8, function()
		if busy or NBG:InCombat() or (_G.GetCursorInfo and GetCursorInfo()) then return end
		if Containers:BankOpen() or (NBG.Selling and NBG.Selling:AtMerchant()) or (NBG.Transfer and (NBG.Transfer:Busy() or NBG.Transfer:MailOpen() or NBG.Transfer:TradeOpen())) then return end
		if Sort:RouteMove("bags") then Sort:Run("bags", "route") end
	end)
end)
