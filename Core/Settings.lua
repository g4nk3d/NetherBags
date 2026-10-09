--[[ NetherBags - Core/Settings.lua
	Every option, its default, and the profile it is kept in. QoL features default to on.

	A profile holds everything a player sets up: every setting, the groups (built-in order and
	custom groups), the window layout (positions, sizes, collapsed groups), and the item marks
	(locked, junk, "always put in"). Profiles live in NetherBagsDB and are shared by the whole
	account; each character uses one (NetherBagsDB.profileKeys), or every character uses the
	same one when "one profile for the account" is on.

	  Settings:Get(key) / Set(key, value) / Reset(key)    the current profile's value
	  Settings:Profile()                                  the current profile table
	  Settings.DEFAULTS, Settings.CHOICES                 key -> default / allowed values
	  Settings:Validate(key, value) -> value | nil        used by import ]]

local _, ns = ...
local NBG = ns.NBG
local Settings = NBG:Module("Settings")

local type, pairs = type, pairs

Settings.DEFAULTS = {
	-- modes (remembered per place)
	["mode.bags"] = "insight",
	["mode.bank"] = "insight",
	["mode.guild"] = "insight",
	-- look
	["look.skin"] = "netherbags",      -- "netherbags" (own look), "netherui" (follow NetherUI's theme on every
	                                   -- window and tab; asked once at install when NetherUI is there), or a
	                                   -- skin a plugin registered
	["look.scale"] = 1,
	["window.lock"] = false,           -- no moving the windows
	["look.opacity"] = 96,             -- window background, %
	["look.qualityBorders"] = true,
	["look.qualityMin"] = 2,           -- uncommon and better get a coloured edge
	["look.newGlow"] = true,
	["look.contextFade"] = true,       -- at a vendor, mailbox, trade or auction house: what can't go there is faded
	-- One bag
	["onebag.columns"] = 12,
	["onebag.slot"] = 37,
	["onebag.spacing"] = 3,
	["onebag.bagStrip"] = true,
	["onebag.specialSections"] = true, -- quivers, soul bags, herb bags... in their own section
	["onebag.groupSections"] = true,   -- groups marked "own section" get one
	["onebag.keyring"] = false,        -- the keyring shown below the bags
	["onebag.reverse"] = false,
	["onebag.bagColors"] = true,       -- each bag's slots tinted with its colour (bag menu)
	-- Insight
	["insight.rowHeight"] = 34,
	["insight.showType"] = true,
	["insight.colStatus"] = true,
	["insight.colIlvl"] = true,
	["insight.colValue"] = true,
	["insight.sort"] = "name",         -- name | ilvl | value | count | quality
	["insight.sortDesc"] = false,
	["insight.groupBy"] = "groups",    -- groups | bag | none
	["insight.newGroup"] = true,
	["insight.emptyGroups"] = false,
	["insight.keepPlace"] = true,      -- rows stay where they are while the window is open (no shifting under the cursor)
	["insight.recentGroup"] = true,    -- "Looted this session" group
	-- markers on items
	["mark.new"] = true,
	["mark.upgrade"] = true,
	["mark.unseen"] = true,
	["mark.bind"] = true,
	["mark.lock"] = true,
	["mark.set"] = true,
	["mark.quest"] = true,
	["mark.junk"] = true,
	["mark.unusable"] = true,          -- can't use yet: level, known recipe, skill, lockpicking, class
	-- junk and selling
	["junk.autoSell"] = true,
	["junk.summary"] = true,
	["junk.poor"] = true,              -- poor (grey) items are junk
	["junk.buyback"] = false,          -- sell at most 12 at a time, so all of them can be bought back
	["junk.button"] = true,
	["junk.outgrown"] = true,          -- soulbound common/uncommon gear 10+ item levels below what you wear is junk
	["junk.freeSlot"] = true,          -- "Free a slot" button when the bags are full
	-- opening and closing
	["auto.merchant"] = true,
	["auto.bank"] = true,
	["auto.mail"] = true,
	["auto.auction"] = true,
	["auto.trade"] = true,
	["auto.guild"] = true,
	["auto.closeWith"] = true,         -- close the bags when that window closes (if it opened them)
	["auto.closeCombat"] = false,
	["auto.crafting"] = true,          -- open with a profession window
	["auto.character"] = true,         -- open with the character pane
	["auto.closeMap"] = true,          -- close when the world map opens
	["blizzard.bags"] = true,          -- NetherBags instead of the game's bags
	["blizzard.bank"] = true,          -- ...and bank
	["blizzard.guild"] = true,         -- ...and guild bank
	-- tooltips and search
	["tooltip.counts"] = true,         -- "owned by" counts on item tooltips
	["tooltip.shift"] = false,         -- ...only while Shift is held
	["tooltip.guild"] = true,
	["search.mail"] = true,
	["search.guild"] = true,
	-- footer
	["footer.currencies"] = true,
	["footer.chips"] = true,
	["footer.tracked"] = true,         -- tracked items (ammo, shards, reagents) in the footer, with low-supply warnings
	-- other
	["minimap.compartment"] = true,
	["stash.tradeGoods"] = true,       -- the Stash button moves trade goods to the bank
	["sort.hint"] = true,              -- the Sort button says how many slots a sort would free
	["sort.mergeAfter"] = true,        -- part stacks merged after the mailbox or a trade
	["bags.autoRoute"] = true,         -- items that arrive go into the bag the bag menu gives them
}

Settings.CHOICES = {
	["mode.bags"] = { insight = true, onebag = true },
	["mode.bank"] = { insight = true, onebag = true },
	["mode.guild"] = { insight = true, onebag = true },
	["insight.sort"] = { name = true, ilvl = true, value = true, count = true, quality = true },
	["insight.groupBy"] = { groups = true, bag = true, none = true },
	-- skins are registered at run time (UI/Skin.lua and plugins): any short id is kept, an unknown one
	-- falls back to the own look when it is used
	["look.skin"] = function(v) return type(v) == "string" and v:match("^[%w_%-]+$") and #v <= 40 end,
}

Settings.RANGES = {
	["look.scale"] = { 0.5, 2 },
	["look.opacity"] = { 30, 100 },
	["look.qualityMin"] = { 0, 5 },
	["onebag.columns"] = { 4, 30 },
	["onebag.slot"] = { 24, 60 },
	["onebag.spacing"] = { 0, 10 },
	["insight.rowHeight"] = { 22, 48 },
}

-- a value fit for key, or nil (used by import and by Set)
function Settings:Validate(key, value)
	local def = self.DEFAULTS[key]
	if def == nil then return nil end
	if type(value) ~= type(def) then return nil end
	local ch = self.CHOICES[key]
	if type(ch) == "function" then
		if not ch(value) then return nil end
	elseif ch and not ch[value] then return nil end
	local r = self.RANGES[key]
	if r and type(value) == "number" then
		if value ~= value then return nil end
		if value < r[1] then value = r[1] elseif value > r[2] then value = r[2] end
	end
	return value
end

---------------------------------------------------------------------------------------------
-- profiles
---------------------------------------------------------------------------------------------
local function NewProfile()
	return { settings = {}, groups = { order = {}, custom = {}, off = {} }, layout = { frames = {}, collapsed = {} },
		locks = {}, junk = {}, keep = {}, assign = {}, junkOnce = {}, tracked = {} }
end
Settings.NewProfile = NewProfile

-- make sure every part of a profile exists (old or imported profiles)
function Settings:Complete(p)
	if type(p) ~= "table" then p = NewProfile() end
	local fresh = NewProfile()
	for k, v in pairs(fresh) do
		if type(p[k]) ~= "table" then p[k] = v end
	end
	for k, v in pairs(fresh.groups) do if type(p.groups[k]) ~= "table" then p.groups[k] = v end end
	for k, v in pairs(fresh.layout) do if type(p.layout[k]) ~= "table" then p.layout[k] = v end end
	return p
end

function Settings:Init(db, char)
	self.db, self.char = db, char
	db.profiles = type(db.profiles) == "table" and db.profiles or {}
	db.profileKeys = type(db.profileKeys) == "table" and db.profileKeys or {}
	db.global = type(db.global) == "table" and db.global or {}
	db.meta = type(db.meta) == "table" and db.meta or {}
	local g = db.global
	if g.useOne == nil then g.useOne = false end
	if type(g.oneProfile) ~= "string" then g.oneProfile = "Default" end
	if type(g.newChars) ~= "string" then g.newChars = "Default" end
	db.profiles.Default = self:Complete(db.profiles.Default)
	for name, p in pairs(db.profiles) do db.profiles[name] = self:Complete(p) end
	local key = NBG:PlayerKey()
	-- (only a full, known name gets a profile entry: before login it may be the first name alone)
	if NBG.playerKey and key ~= "Unknown" and (not db.profileKeys[key] or not db.profiles[db.profileKeys[key]]) then
		db.profileKeys[key] = db.profiles[g.newChars] and g.newChars or "Default"
	end
	db.profileKeys.Unknown = nil
	self:Bind()
end

function Settings:CurrentName()
	if not self.db then return "Default" end
	local g = self.db.global
	if g.useOne then return self.db.profiles[g.oneProfile] and g.oneProfile or "Default" end
	local name = self.db.profileKeys[NBG:PlayerKey()]
	return (name and self.db.profiles[name]) and name or "Default"
end

function Settings:Bind()
	self.profile = self.db.profiles[self:CurrentName()]
end

function Settings:Profile()
	if not self.profile then return NewProfile() end
	return self.profile
end

function Settings:Touch()
	if not self.db then return end
	local name = self:CurrentName()
	self.db.meta[name] = self.db.meta[name] or {}
	self.db.meta[name].changed = NBG:Now()
end

function Settings:Get(key)
	local p = self.profile
	local v = p and p.settings[key]
	if v == nil then v = self.DEFAULTS[key] end
	return v
end

function Settings:Set(key, value)
	if not self.profile then return end
	if value ~= nil then
		value = self:Validate(key, value)
		if value == nil then return end
	end
	if value == self.DEFAULTS[key] then value = nil end
	self.profile.settings[key] = value
	self:Touch()
	NBG:Fire("SETTING_CHANGED", key, self:Get(key))
end

function Settings:Reset(key) self:Set(key, nil) end
