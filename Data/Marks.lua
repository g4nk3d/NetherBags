--[[ NetherBags - Data/Marks.lua
	The player's own marks on items, kept in the profile (by item ID):

	  locked   never sold, never stashed, never moved by NetherBags' sort
	  junk     sold with the junk (even when not grey)
	  keep     a grey item that is NOT junk
	  assign   "always put in" a group (Insight)

	  Marks:IsLocked(id) / SetLocked(id, on) / ToggleLock(id)
	  Marks:IsJunk(entry)        the junk rule: marked junk (or junk once), poor quality (setting),
	                             outgrown soulbound gear (setting); never when locked or kept, never
	                             when it has no vendor value, never when a quest in the log needs it
	                             (unless the player marked it junk)
	  Marks:SetJunkOnce(id, on)  junk at the next vendor only: the mark goes once it is sold
	  Marks:SetJunk(id, on)      on: marked junk; off: kept (a grey item stays out of junk)
	  Marks:Assign(id, groupId)  nil clears ]]

local _, ns = ...
local NBG = ns.NBG
local Marks = NBG:Module("Marks")
local Settings = NBG.Settings
local Num = NBG.Num

local function P() return Settings:Profile() end
local function Changed(what, id) NBG:Fire("MARKS_CHANGED", what, id) end

function Marks:IsLocked(id) id = Num(id) return id and P().locks[id] or false end

function Marks:SetLocked(id, on)
	id = Num(id)
	if not id then return end
	P().locks[id] = on and true or nil
	Settings:Touch()
	Changed("lock", id)
end

function Marks:ToggleLock(id) self:SetLocked(id, not self:IsLocked(id)) return self:IsLocked(id) end

function Marks:IsMarkedJunk(id) id = Num(id) return id and P().junk[id] or false end
function Marks:IsKept(id) id = Num(id) return id and P().keep[id] or false end

local function Once() local p = P() p.junkOnce = type(p.junkOnce) == "table" and p.junkOnce or {} return p.junkOnce end
function Marks:IsJunkOnce(id) id = Num(id) return id and Once()[id] or false end

function Marks:IsJunk(entry)
	if not entry or not entry.id then return false end
	local id = entry.id
	if self:IsLocked(id) or self:IsKept(id) then return false end
	if entry.noValue then return false end
	if P().junk[id] or Once()[id] then return true end
	local Items = NBG.Items
	if Items and Items.QuestNeeded and Items:QuestNeeded(entry) then return false end
	if Items and Items.Outgrown and Items:Outgrown(entry) then return true end
	if Settings:Get("junk.poor") then
		local q = entry.quality
		if q == nil and entry.link and NBG.Items then
			local i = NBG.Items:Info(entry.link)
			q = i and i.quality
		end
		if q == 0 then
			local i = entry.link and NBG.Items and NBG.Items:Info(entry.link)
			if i and i.price and i.price <= 0 then return false end
			return true
		end
	end
	return false
end

function Marks:SetJunk(id, on)
	id = Num(id)
	if not id then return end
	local p = P()
	if on then p.junk[id], p.keep[id] = true, nil else p.junk[id], p.keep[id] = nil, true end
	Settings:Touch()
	Changed("junk", id)
end

function Marks:SetJunkOnce(id, on)
	id = Num(id)
	if not id then return end
	Once()[id] = on and true or nil
	if on then P().keep[id] = nil end     -- ("not junk" would otherwise win)
	Settings:Touch()
	Changed("junk", id)
end

-- "junk once" marks go when the item has left the bags (sold) or the vendor is closed with none left
local function DropOnce()
	local once = Once()
	if not next(once) then return end
	local have = {}
	for _, e in ipairs(NBG.Containers:All("bags")) do if e.id then have[e.id] = true end end
	for id in pairs(once) do if not have[id] then once[id] = nil Changed("junk", id) end end
end
NBG:Register("MERCHANT", function(_, open) if not open then DropOnce() end end)

-- back to the plain rule (neither marked nor kept)
function Marks:ClearJunk(id)
	id = Num(id)
	if not id then return end
	local p = P()
	p.junk[id], p.keep[id] = nil, nil
	Settings:Touch()
	Changed("junk", id)
end

function Marks:Assigned(id) id = Num(id) return id and P().assign[id] or nil end

function Marks:Assign(id, groupId)
	id = Num(id)
	if not id then return end
	P().assign[id] = (type(groupId) == "string" and groupId ~= "") and groupId or nil
	Settings:Touch()
	Changed("assign", id)
end
