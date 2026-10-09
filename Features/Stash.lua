--[[ NetherBags - Features/Stash.lua
	At a banker: one click moves every trade good (and crafting reagent) from the bags into the
	bank, the way using an item at the bank does. Locked items stay. Stops when the bank is full,
	the banker closes, or combat starts. ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Stash = NBG:Module("Stash")
local Containers, Items, Marks = NBG.Containers, NBG.Items, NBG.Marks

local ipairs = ipairs

local function BankFree()
	local free = 0
	for _, bag in ipairs(Containers:Bags("bank")) do
		local f, fam = Containers:Free(bag)
		if (fam or 0) == 0 or bag == Containers.BANK then free = free + (f or 0) end
	end
	return free
end

local running
function Stash:Run()
	if running then return end
	if not Containers:BankOpen() then NBG:Print(L["Stash works at a banker."]) return end
	local use = NBG.API("C_Container", "UseContainerItem") or _G.UseContainerItem
	if not use then return end
	local list = {}
	for _, e in ipairs(Containers:All("bags")) do
		local i = Items:Info(e.link)
		if i and (i.classID == 7 or i.classID == 5) and not Marks:IsLocked(e.id) and not e.quest and not Items:QuestNeeded(e) then list[#list + 1] = e end
	end
	if #list == 0 then NBG:Print(L["No trade goods in the bags."]) return end
	running = true
	local i, moved = 0, 0
	local function Step()
		i = i + 1
		if i > #list or not Containers:BankOpen() or NBG:InCombat() then
			running = nil
			NBG:Print(L["Stashed %d stack(s) in the bank."], moved)
			return
		end
		if BankFree() <= 0 then
			running = nil
			NBG:Print(L["The bank is full: stashed %d stack(s)."], moved)
			return
		end
		local e = list[i]
		local now = Containers:Entry(e.bag, e.slot)
		if now and now.id == e.id and not now.locked then
			local B = rawget(_G, "C_Bank")
			local E = type(_G.Enum) == "table" and _G.Enum.BankType
			if pcall(use, e.bag, e.slot, nil, E and E.Character or nil) then moved = moved + 1 end
		end
		NBG:After(0.15, Step)
	end
	Step()
end
