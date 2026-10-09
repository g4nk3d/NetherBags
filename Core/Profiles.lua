--[[ NetherBags - Core/Profiles.lua
	Saving, switching and sharing profiles (see Core/Settings.lua for what a profile holds).

	  Profiles:List() -> { { name, users = {char keys}, changed } } sorted by name
	  Profiles:Use(name [, forCharKey])        this character (or another) uses that profile
	  Profiles:New(name) / Copy(from, to) / Rename(old, new) / Delete(name) / Reset(name)
	  Profiles:SetOneForAccount(on [, name]) / SetNewCharProfile(name)
	  Profiles:Export(name, opts) -> string    opts: { groups = true, layout = true, items = false }
	  Profiles:Preview(string) -> info | nil, why     what an import would bring, without saving
	  Profiles:Import(string [, name]) -> name | nil, why   always a NEW profile

	Every change fires "PROFILE_CHANGED"; switching the current profile also rebuilds the
	windows (through that message). Names: 1-32 visible characters, no colour codes. ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Profiles = NBG:Module("Profiles")
local Settings = NBG.Settings

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring

local function DB() return Settings.db end

function Profiles.CleanName(name)
	if type(name) ~= "string" then return nil end
	name = name:gsub("|", ""):gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" or #name > 32 then return nil end
	return name
end

function Profiles:Exists(name) local db = DB() return db and db.profiles[name] ~= nil end

function Profiles:List()
	local db = DB()
	local out = {}
	if not db then return out end
	local users = {}
	for char, pname in pairs(db.profileKeys) do
		users[pname] = users[pname] or {}
		table.insert(users[pname], char)
	end
	for name in pairs(db.profiles) do
		local u = users[name] or {}
		table.sort(u)
		out[#out + 1] = { name = name, users = u, changed = db.meta[name] and db.meta[name].changed or nil }
	end
	table.sort(out, function(a, b)
		if a.name == "Default" then return true end
		if b.name == "Default" then return false end
		return a.name:lower() < b.name:lower()
	end)
	return out
end

local function Changed(switched)
	Settings:Bind()
	NBG:Fire("PROFILE_CHANGED", Settings:CurrentName(), switched and true or false)
end

function Profiles:Use(name, charKey)
	local db = DB()
	if not (db and db.profiles[name]) then return false end
	local before = Settings:CurrentName()
	if db.global.useOne and not charKey then
		db.global.oneProfile = name
	else
		db.profileKeys[charKey or NBG:PlayerKey()] = name
	end
	Changed(before ~= Settings:CurrentName())
	return true
end

function Profiles:New(name)
	local db = DB()
	name = self.CleanName(name)
	if not (db and name) then return nil, L["Give the profile a name (up to 32 letters)."] end
	if db.profiles[name] then return nil, L["A profile with that name already exists."] end
	db.profiles[name] = Settings.NewProfile()
	db.meta[name] = { changed = NBG:Now() }
	Changed(false)
	return name
end

function Profiles:Copy(from, to)
	local db = DB()
	to = self.CleanName(to)
	if not (db and db.profiles[from]) then return nil, L["That profile no longer exists."] end
	if not to then return nil, L["Give the profile a name (up to 32 letters)."] end
	if db.profiles[to] then return nil, L["A profile with that name already exists."] end
	db.profiles[to] = Settings:Complete(NBG.Copy(db.profiles[from]))
	db.meta[to] = { changed = NBG:Now() }
	Changed(false)
	return to
end

function Profiles:Rename(old, new)
	local db = DB()
	new = self.CleanName(new)
	if not (db and db.profiles[old]) then return nil, L["That profile no longer exists."] end
	if old == "Default" then return nil, L["The Default profile keeps its name."] end
	if not new then return nil, L["Give the profile a name (up to 32 letters)."] end
	if db.profiles[new] then return nil, L["A profile with that name already exists."] end
	db.profiles[new], db.profiles[old] = db.profiles[old], nil
	db.meta[new], db.meta[old] = db.meta[old], nil
	for char, p in pairs(db.profileKeys) do if p == old then db.profileKeys[char] = new end end
	if db.global.oneProfile == old then db.global.oneProfile = new end
	if db.global.newChars == old then db.global.newChars = new end
	Changed(false)
	return new
end

function Profiles:Delete(name)
	local db = DB()
	if not (db and db.profiles[name]) then return nil, L["That profile no longer exists."] end
	if name == "Default" then return nil, L["The Default profile cannot be deleted (it can be reset)."] end
	local wasCurrent = Settings:CurrentName() == name
	db.profiles[name], db.meta[name] = nil, nil
	for char, p in pairs(db.profileKeys) do if p == name then db.profileKeys[char] = "Default" end end
	if db.global.oneProfile == name then db.global.oneProfile = "Default" end
	if db.global.newChars == name then db.global.newChars = "Default" end
	Changed(wasCurrent)
	return true
end

function Profiles:Reset(name)
	local db = DB()
	name = name or Settings:CurrentName()
	if not (db and db.profiles[name]) then return nil end
	db.profiles[name] = Settings.NewProfile()
	db.meta[name] = { changed = NBG:Now() }
	Changed(name == Settings:CurrentName())
	return true
end

function Profiles:SetOneForAccount(on, name)
	local db = DB()
	if not db then return end
	local before = Settings:CurrentName()
	db.global.useOne = on and true or false
	if on then db.global.oneProfile = (name and db.profiles[name]) and name or before end
	Changed(before ~= Settings:CurrentName())
end

function Profiles:SetNewCharProfile(name)
	local db = DB()
	if db and db.profiles[name] then db.global.newChars = name Changed(false) end
end

---------------------------------------------------------------------------------------------
-- sharing
---------------------------------------------------------------------------------------------
local function CleanSettings(src)
	local out = {}
	if type(src) ~= "table" then return out end
	for k, v in pairs(src) do
		if type(k) == "string" then
			local ok = Settings:Validate(k, v)
			if ok ~= nil then out[k] = ok end
		end
	end
	return out
end

local function CleanIDs(src, valueCheck)
	local out = {}
	if type(src) ~= "table" then return out end
	local n = 0
	for k, v in pairs(src) do
		local id = NBG.Num(k)
		if id and id > 0 and id == math.floor(id) and n < 5000 then
			local val = valueCheck(v)
			if val ~= nil then out[id] = val n = n + 1 end
		end
	end
	return out
end

local function CleanLayout(src)
	local out = { frames = {}, collapsed = {} }
	if type(src) ~= "table" then return out end
	if type(src.frames) == "table" then
		for id, f in pairs(src.frames) do
			if type(id) == "string" and #id < 40 and type(f) == "table" then
				local c = {}
				for _, k in ipairs({ "x", "y", "w", "h" }) do
					local v = NBG.Num(f[k])
					if v then c[k] = math.max(-10000, math.min(10000, v)) end
				end
				if type(f.point) == "string" and f.point:match("^[A-Z]+$") then c.point = f.point end
				out.frames[id] = c
			end
		end
	end
	if type(src.collapsed) == "table" then
		for id, v in pairs(src.collapsed) do
			if type(id) == "string" and #id < 60 and v == true then out.collapsed[id] = true end
		end
	end
	return out
end

function Profiles:Export(name, opts)
	local db = DB()
	name = name or Settings:CurrentName()
	local p = db and db.profiles[name]
	if not p then return nil, L["That profile no longer exists."] end
	opts = opts or {}
	local data = {
		kind = "NetherBags profile", v = NBG.EXPORT_VERSION, addon = NBG.VERSION,
		name = name, by = NBG:PlayerKey(),
		settings = NBG.Copy(p.settings),
	}
	if opts.groups ~= false then
		data.groups = NBG.Copy(p.groups)
		data.assign = NBG.Copy(p.assign)
	end
	if opts.layout ~= false then data.layout = NBG.Copy(p.layout) end
	if opts.items then
		data.locks = NBG.Copy(p.locks)
		data.junk = NBG.Copy(p.junk)
		data.keep = NBG.Copy(p.keep)
		data.tracked = NBG.Copy(p.tracked)
	end
	return NBG.Serialize:Pack(data)
end

-- read and clean an import; nothing is saved
function Profiles:Read(str)
	local data, why = NBG.Serialize:Unpack(str)
	if not data then return nil, why end
	if type(data) ~= "table" or data.kind ~= "NetherBags profile" then return nil, L["This is not a NetherBags profile."] end
	local p = Settings.NewProfile()
	p.settings = CleanSettings(data.settings)
	local nGroups = 0
	if NBG.Groups and type(data.groups) == "table" then
		p.groups = NBG.Groups:Sanitize(data.groups)
		for _ in pairs(p.groups.custom) do nGroups = nGroups + 1 end
	end
	local isGroup = function(v) return (type(v) == "string" and #v < 60) and v or nil end
	p.assign = CleanIDs(data.assign, isGroup)
	p.layout = CleanLayout(data.layout)
	local yes = function(v) return v == true or nil end
	p.locks = CleanIDs(data.locks, yes)
	p.junk = CleanIDs(data.junk, yes)
	p.keep = CleanIDs(data.keep, yes)
	-- tracked items: { warn = number } each
	p.tracked = CleanIDs(data.tracked, function(v)
		if type(v) ~= "table" then return nil end
		local w = tonumber(v.warn)
		return { warn = (w and w >= 0 and w <= 100000) and math.floor(w) or 0 }
	end)
	local nSettings, nLocks = 0, 0
	for _ in pairs(p.settings) do nSettings = nSettings + 1 end
	for _ in pairs(p.locks) do nLocks = nLocks + 1 end
	local info = {
		name = Profiles.CleanName(data.name) or L["Imported"],
		by = type(data.by) == "string" and data.by:gsub("|", ""):sub(1, 48) or "?",
		version = type(data.addon) == "string" and data.addon:sub(1, 16) or "?",
		settings = nSettings, groups = nGroups, locks = nLocks,
		layout = data.layout ~= nil,
	}
	return p, info
end

function Profiles:Preview(str)
	local p, info = self:Read(str)
	if not p then return nil, info end
	return info
end

function Profiles:Import(str, name)
	local db = DB()
	if not db then return nil, L["Not ready yet."] end
	local p, info = self:Read(str)
	if not p then return nil, info end
	local base = self.CleanName(name) or info.name
	local final, i = base, 2
	while db.profiles[final] do
		final = (base:sub(1, 28)) .. " " .. i
		i = i + 1
	end
	db.profiles[final] = Settings:Complete(p)
	db.meta[final] = { changed = NBG:Now(), importedFrom = info.by }
	Changed(false)
	return final, info
end
