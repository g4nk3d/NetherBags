--[[ NetherBags - Core/Init.lua
	The namespace and the plumbing every other file uses.

	  NBG:Module(name)                 a module table, created once (NBG.<name>)
	  NBG:On(event, fn) / NBG:Off(...)  game events; several handlers per event
	  NBG:Register(msg, fn [, owner])  internal messages (the same bus plugins listen on)
	  NBG:Fire(msg, ...)               every listener runs protected; a plugin listener's failure
	                                   counts against that plugin, never against the core
	  NBG:After(s, fn)                 a timer; NBG:Debounce(key, s, fn) runs once, s after the
	                                   last call with that key
	  NBG:AfterCombat(key, fn)         now, or once combat ends (one waiting entry per key)
	  NBG:Safe(context, fn, ...)       a protected call at a boundary (plugin, saved data, game)
	  NBG:Log(level, fmt, ...)         the diagnostics log (never chat unless debugging)
	  NBG.Num / NBG.Str / NBG.Open     a number / string / table, or nil (secret values and wrong
	                                   types refused)
	  NBG:PlayerKey()                  this character's key: the full Forever name ("Derp Diggler")

	Only API/Plugin.lua adds a global (NetherBags). Everything else lives in here. ]]

local ADDON, ns = ...
local NBG = { name = ADDON, modules = {} }
ns.NBG = NBG

NBG.VERSION = "1.0.0"
NBG.MEDIA = "Interface\\AddOns\\NetherBags\\Media\\"
NBG.FONTS = {
	body = NBG.MEDIA .. "Fonts\\Poppins-Regular.ttf",
	medium = NBG.MEDIA .. "Fonts\\Poppins-Medium.ttf",
	bold = NBG.MEDIA .. "Fonts\\Poppins-Bold.ttf",
	title = NBG.MEDIA .. "Fonts\\Philosopher-Bold.ttf",
	caps = NBG.MEDIA .. "Fonts\\Cinzel-Bold.ttf",
}
NBG.SCHEMA = 1        -- account saved data layout
NBG.CHAR_SCHEMA = 1   -- per-character saved data layout
NBG.API_VERSION = 1   -- plugin API
NBG.EXPORT_VERSION = 1

local type, pairs, ipairs, select, tostring, tonumber = type, pairs, ipairs, select, tostring, tonumber
local format, pcall = string.format, pcall
local tremove = table.remove
local wipe = _G.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
NBG.wipe = wipe

function NBG:Module(name)
	local m = self.modules[name]
	if not m then
		m = { name = name }
		self.modules[name] = m
		self[name] = m
	end
	return m
end

---------------------------------------------------------------------------------------------
-- Values the game may hand back as "secret" (Midnight API lineage) or of the wrong type
---------------------------------------------------------------------------------------------
local function issecret(v)
	local f = _G.issecretvalue
	if f then return f(v) and true or false end
	return false
end
NBG.IsSecret = issecret

function NBG.Num(v)
	if v == nil or issecret(v) then return nil end
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then return nil end
	return v
end

function NBG.Str(v)
	if v == nil or issecret(v) or type(v) ~= "string" or v == "" then return nil end
	return v
end

function NBG.Open(t)
	if type(t) ~= "table" or issecret(t) then return nil end
	return t
end

-- a call into the game that may error: errors become nil
function NBG.Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local function pass(ok, ...) if ok then return ... end return nil end
	return pass(pcall(fn, ...))
end

-- a function of a C_ namespace, or nil when the client has none
function NBG.API(space, fn)
	local t = rawget(_G, space)
	if type(t) ~= "table" then return nil end
	local f = t[fn]
	if type(f) ~= "function" then return nil end
	return f
end

-- a number the game defines, or the default
function NBG.Const(name, default)
	local v = rawget(_G, name)
	if type(v) == "number" then return v end
	return default
end

function NBG:IsForever()
	if _G.WOW_PROJECT_ID == 18 then return true end
	if not _G.GetBuildInfo then return false end
	local version, _, _, build = GetBuildInfo()
	version = tostring(version or "")
	if version:match("^1%.6%d") then return true end
	build = tonumber(build) or 0
	return build >= 16000 and build < 20000
end

-- This character's key. Forever names are two words (name and surname) and unique across the
-- region, so the full name is the key; elsewhere "Name - Realm".
function NBG:PlayerKey()
	if self.playerKey then return self.playerKey end
	local name, second
	if _G.UnitFullName then name, second = UnitFullName("player") end
	name = self.Str(name) or (self.Str(_G.UnitName and UnitName("player")) or "Unknown")
	second = self.Str(second)
	local key
	if self:IsForever() then
		-- the surname comes back in the realm's place (client 1.60.1.70170 on); a realm name there
		-- (older builds) is not a surname, and a name that already has two words keeps them
		local realm = self.Str(_G.GetNormalizedRealmName and GetNormalizedRealmName()) or self.Str(_G.GetRealmName and GetRealmName())
		if second and (second == realm or name:find(" ", 1, true)) then second = nil end
		key = second and (name .. " " .. second) or name
		-- early in the login only the first name may be known: not kept until it is the full name
		-- (or the game world is up, when whatever it is is final)
		if not (second or name:find(" ", 1, true) or self.loggedIn) then return key end
	else
		local realm = self.Str(_G.GetRealmName and GetRealmName())
		key = realm and (name .. " - " .. realm) or name
	end
	if name ~= "Unknown" then self.playerKey = key end
	return key
end

---------------------------------------------------------------------------------------------
-- Log (diagnostics): chat only for errors (once per context) and for debug when asked
---------------------------------------------------------------------------------------------
NBG.LEVELS = { error = 1, warn = 2, info = 3, debug = 4 }
local LOG_SIZE = 200
local log, logHead = {}, 0
NBG.errors = { count = 0, byContext = {}, latest = nil }
NBG.TITLE = "|cffe8c46aNether|r|cff6fd2f5Bags|r"

local function Chat(msg)
	local f = _G.DEFAULT_CHAT_FRAME
	if f and f.AddMessage then f:AddMessage(NBG.TITLE .. ": " .. msg) end
end
NBG.Chat = Chat

function NBG:Print(fmt, ...)
	local ok, msg = pcall(format, tostring(fmt), ...)
	Chat(ok and msg or tostring(fmt))
end

function NBG:Log(level, fmt, ...)
	local lv = self.LEVELS[level] or 3
	local limit = self.LEVELS[self.db and self.db.logLevel or "warn"] or 2
	if lv > limit then return end
	local ok, msg = pcall(format, tostring(fmt), ...)
	msg = ok and msg or tostring(fmt)
	logHead = logHead % LOG_SIZE + 1
	log[logHead] = { t = _G.GetTime and GetTime() or 0, level = level, msg = msg }
	if level == "debug" then Chat("|cff888888" .. msg .. "|r") end
end

function NBG:GetLog()
	local out = {}
	for i = 0, LOG_SIZE - 1 do
		local e = log[(logHead - i - 1) % LOG_SIZE + 1]
		if e then out[#out + 1] = e end
	end
	return out
end

function NBG:RecordError(context, err)
	local E = self.errors
	E.count = E.count + 1
	E.byContext[context] = (E.byContext[context] or 0) + 1
	E.latest = { context = context, err = tostring(err), t = _G.GetTime and GetTime() or 0 }
	self:Log("error", "%s: %s", context, tostring(err))
	if E.byContext[context] == 1 then
		Chat(format("|cffff6060an error in %s was caught; /nbags diag shows it.|r", tostring(context)))
	end
end

function NBG:Safe(context, fn, ...)
	if type(fn) ~= "function" then return false end
	local res = { pcall(fn, ...) }
	if not res[1] then
		self:RecordError(context, res[2])
		return false
	end
	return unpack(res)
end

---------------------------------------------------------------------------------------------
-- Game events
---------------------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
NBG.frame = frame
local handlers = {}

frame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		local fn = list[i]
		if fn then
			local ok, err = pcall(fn, event, ...)
			if not ok then NBG:RecordError("event " .. event, err) end
		end
	end
end)

function NBG:On(event, fn)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		if not pcall(frame.RegisterEvent, frame, event) then
			handlers[event] = nil
			self:Log("info", "event %s is not available on this client", event)
			return false
		end
	end
	list[#list + 1] = fn
	return true
end

function NBG:Off(event, fn)
	local list = handlers[event]
	if not list then return end
	for i = #list, 1, -1 do if list[i] == fn then tremove(list, i) end end
	if #list == 0 then
		handlers[event] = nil
		pcall(frame.UnregisterEvent, frame, event)
	end
end

---------------------------------------------------------------------------------------------
-- Internal message bus (also what plugins listen to)
---------------------------------------------------------------------------------------------
local bus = {}

function NBG:Register(msg, fn, owner)
	if type(fn) ~= "function" then return nil end
	local list = bus[msg]
	if not list then list = {} bus[msg] = list end
	local h = { fn = fn, owner = owner }
	list[#list + 1] = h
	return h
end

function NBG:Unregister(msg, h)
	local list = bus[msg]
	if not list then return end
	for i = #list, 1, -1 do if list[i] == h then tremove(list, i) end end
end

function NBG:Fire(msg, ...)
	local list = bus[msg]
	if not list then return end
	for i = 1, #list do
		local h = list[i]
		if h and not (h.owner and h.owner.disabled) then
			local ok, err = pcall(h.fn, msg, ...)
			if not ok then
				if h.owner and self.Plugin then self.Plugin:Failed(h.owner, msg, err)
				else self:RecordError("message " .. msg, err) end
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Timers
---------------------------------------------------------------------------------------------
function NBG:After(s, fn)
	if _G.C_Timer and C_Timer.After then
		C_Timer.After(s or 0, function() NBG:Safe("timer", fn) end)
	end
end

local debounce = {}
function NBG:Debounce(key, s, fn)
	local entry = debounce[key]
	if entry then entry.fn = fn entry.gen = entry.gen + 1 else entry = { fn = fn, gen = 1 } debounce[key] = entry end
	local gen = entry.gen
	self:After(s, function()
		local e = debounce[key]
		if e and e.gen == gen then debounce[key] = nil e.fn() end
	end)
end

local afterCombat, afterOrder = {}, {}
function NBG:InCombat() return _G.InCombatLockdown and InCombatLockdown() or false end
function NBG:AfterCombat(key, fn)
	if not self:InCombat() then return self:Safe("after combat " .. tostring(key), fn) end
	if not afterCombat[key] then afterOrder[#afterOrder + 1] = key end
	afterCombat[key] = fn
end
NBG:On("PLAYER_REGEN_ENABLED", function()
	local order = afterOrder
	afterOrder = {}
	for _, key in ipairs(order) do
		local fn = afterCombat[key]
		afterCombat[key] = nil
		if fn then NBG:Safe("after combat " .. tostring(key), fn) end
	end
end)

function NBG:Now() return _G.GetServerTime and GetServerTime() or (_G.time and time()) or 0 end
function NBG:Clock() return _G.GetTime and GetTime() or 0 end

-- a shallow-to-deep copy of plain data (strings, numbers, booleans, tables)
function NBG.Copy(v, seen)
	if type(v) ~= "table" then return v end
	seen = seen or {}
	if seen[v] then return nil end
	seen[v] = true
	local out = {}
	for k, x in pairs(v) do
		local tk = type(k)
		if tk == "string" or tk == "number" then
			local tx = type(x)
			if tx == "table" then out[k] = NBG.Copy(x, seen)
			elseif tx == "string" or tx == "number" or tx == "boolean" then out[k] = x end
		end
	end
	seen[v] = nil
	return out
end
