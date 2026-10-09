--[[ NetherBags - Features/FreeSlot.lua
	"Free a slot": when the bags are full (no free ordinary slot), a button in the footer offers the
	cheapest junk stack. Clicking it shows what it is and what it would sell for; only the Delete
	button of that dialog (a click of the player's) deletes it. Locked items, items a quest in the
	log needs and anything that is not junk are never offered. The last deletions are kept in a
	short log (Settings > Junk & selling).

	  FreeSlot:Needed() -> bool          the bags are full
	  FreeSlot:Cheapest() -> entry, value
	  FreeSlot:Offer()                   the dialog
	  FreeSlot:Log() -> { { when, link, count, value } } newest first ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local FreeSlot = NBG:Module("FreeSlot")
local Containers, Marks, Items, Settings = NBG.Containers, NBG.Marks, NBG.Items, NBG.Settings

local ipairs = ipairs

function FreeSlot:Needed()
	if not Settings:Get("junk.freeSlot") then return false end
	local used, total = Containers:Counts("bags")
	return total > 0 and used >= total
end

function FreeSlot:Cheapest()
	local best, bestValue
	for _, e in ipairs(Containers:All("bags")) do
		if e.id and not e.locked and not Marks:IsLocked(e.id) and Marks:IsJunk(e) and not Items:QuestNeeded(e) then
			local i = Items:Info(e.link)
			local value = (i and i.price or 0) * (e.count or 1)
			if not best or value < bestValue or (value == bestValue and (e.count or 1) < (best.count or 1)) then
				best, bestValue = e, value
			end
		end
	end
	return best, bestValue or 0
end

local function Log()
	local g = NBG.db and NBG.db.global
	if not g then return {} end
	g.deleted = type(g.deleted) == "table" and g.deleted or {}
	return g.deleted
end
function FreeSlot:Log() return Log() end

-- delete exactly that stack, if it is still there (called from the dialog's button: a real click)
function FreeSlot:Delete(e)
	if NBG:InCombat() then NBG:Print(L["Not in combat."]) return end
	local now = Containers:RefreshSlot(e.bag, e.slot) or Containers:Entry(e.bag, e.slot)
	if not (now and now.id == e.id and (now.count or 1) == (e.count or 1)) or Marks:IsLocked(e.id) then
		NBG:Print(L["That item moved: nothing was deleted."])
		return
	end
	local pick = NBG.API("C_Container", "PickupContainerItem") or _G.PickupContainerItem
	if not (pick and _G.DeleteCursorItem) then return end
	if _G.GetCursorInfo and GetCursorInfo() then NBG:Print(L["Something is on the cursor: nothing was deleted."]) return end
	pcall(pick, e.bag, e.slot)
	local kind, id = NBG.Call(_G.GetCursorInfo)
	if kind ~= "item" or NBG.Num(id) ~= e.id then
		if _G.ClearCursor then ClearCursor() end
		NBG:Print(L["That item moved: nothing was deleted."])
		return
	end
	pcall(DeleteCursorItem)
	local i = Items:Info(e.link)
	local log = Log()
	table.insert(log, 1, { when = NBG:Now(), link = i and i.link or e.link, count = e.count or 1, value = (i and i.price or 0) * (e.count or 1) })
	for k = #log, 51, -1 do log[k] = nil end
	NBG:Print(L["Deleted %s x%d to free a slot."], i and i.link or e.link or "?", e.count or 1)
end

function FreeSlot:Offer()
	local e, value = self:Cheapest()
	if not e then NBG:Print(L["No junk to delete."]) return end
	local i = Items:Info(e.link)
	local name = (i and i.link) or e.link or "?"
	NBG.Widgets:Popup({
		title = L["Free a slot"],
		text = (L["Delete %s x%d?\nIt sells for %s. This can't be undone."]):format(name, e.count or 1, value > 0 and NBG.Widgets:Money(value) or L["nothing"]),
		width = 420,
		buttons = {
			{ label = L["Delete"], style = "red", onClick = function() FreeSlot:Delete(e) end },
			{ label = L["Cancel"] },
		},
	})
end
