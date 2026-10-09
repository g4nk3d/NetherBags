--[[ NetherBags - Features/Tracked.lua
	Items tracked in the footer (ammo, soul shards, reagents...): their count, in red when it is
	below the player's warning level, and a warning in chat and on screen the moment it drops below
	it. Kept in the profile (tracked[itemID] = { warn = n }). Up to 5 are shown.

	  Tracked:IsTracked(id) / Toggle(id) / SetWarn(id, n)
	  Tracked:List() -> { { id, count, warn, icon, low } }   this character's bags ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Tracked = NBG:Module("Tracked")
local Containers, Items, Settings = NBG.Containers, NBG.Items, NBG.Settings

local ipairs, pairs = ipairs, pairs
Tracked.MAX = 5

local function T()
	local p = Settings:Profile()
	p.tracked = type(p.tracked) == "table" and p.tracked or {}
	return p.tracked
end

-- a sensible first warning level: ammo 200, soul shards 3, the rest 5
local function DefaultWarn(id)
	local classID = Items:Instant(id)
	if classID == 6 then return 200 end
	if id == 6265 then return 3 end
	return 5
end

function Tracked:IsTracked(id) return id and T()[id] ~= nil or false end

function Tracked:Toggle(id)
	id = NBG.Num(id)
	if not id then return end
	local t = T()
	if t[id] then t[id] = nil
	else
		local n = 0
		for _ in pairs(t) do n = n + 1 end
		if n >= self.MAX then NBG:Print(L["At most %d items can be tracked."], self.MAX) return end
		t[id] = { warn = DefaultWarn(id) }
	end
	Settings:Touch()
	NBG:Fire("TRACKED_CHANGED")
end

function Tracked:SetWarn(id, n)
	local t = T()
	if not t[id] then return end
	t[id].warn = math.max(0, math.floor(NBG.Num(n) or 0))
	Settings:Touch()
	NBG:Fire("TRACKED_CHANGED")
end

local function Counts()
	local c = {}
	for _, bag in ipairs(Containers:Bags("bags")) do
		if bag ~= Containers.KEYRING then
			for _, e in pairs(Containers:Read(bag)) do if e.id then c[e.id] = (c[e.id] or 0) + (e.count or 1) end end
		end
	end
	return c
end

function Tracked:List()
	local out = {}
	if not Settings:Get("footer.tracked") then return out end
	local counts = Counts()
	for id, d in pairs(T()) do
		local n = counts[id] or 0
		local _, _, _, icon = Items:Instant(id)
		out[#out + 1] = { id = id, count = n, warn = d.warn or 0, icon = icon, low = (d.warn or 0) > 0 and n < d.warn }
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

-- the warning, once per drop below the level (again only after it has been back above it)
local warned = {}
local ready = false
local function Check()
	if not ready or not Settings:Get("footer.tracked") then return end
	local counts = Counts()
	for id, d in pairs(T()) do
		local n, w = counts[id] or 0, d.warn or 0
		if w > 0 and n < w then
			if not warned[id] then
				warned[id] = true
				local i = Items:Info("item:" .. id)
				local name = i and i.link or ("item:" .. id)
				NBG:Print(L["Running low: %s (%d left)."], name, n)
				if _G.UIErrorsFrame and UIErrorsFrame.AddMessage then
					pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, (L["Running low: %s (%d left)."]):format(i and i.name or name, n), 1, 0.6, 0.2)
				end
				if _G.PlaySound and _G.SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
			end
		else
			warned[id] = nil
		end
	end
end
NBG:Register("BAGS_CHANGED", function() NBG:Debounce("trackedCheck", 0.5, Check) end)
NBG:Register("LOGIN", function()
	-- (no warning for what was already low at login: it is in red in the footer)
	NBG:After(3, function()
		local counts = Counts()
		for id, d in pairs(T()) do if (d.warn or 0) > 0 and (counts[id] or 0) < d.warn then warned[id] = true end end
		ready = true
	end)
end)
