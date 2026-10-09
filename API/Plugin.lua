--[[ NetherBags - API/Plugin.lua
	The one global, NetherBags: what other addons may use. Docs/API.md describes it in full.

	  NetherBags.version, NetherBags.apiVersion
	  NetherBags:Toggle([id]) / :Open(id [, place]) / :Close(id)       id: "bags" | "bank" | "guild"
	  NetherBags:Search(text)                                          Everywhere, with that text
	  NetherBags:Items(place [, charKey]) -> { entries }               read-only copies
	  NetherBags:Owners(itemID) -> { owners, guilds }                  the tooltip counts
	  NetherBags:RegisterPlugin(def) -> api | nil, why
	      def = { id, name, version, description, OnEnable(api), OnDisable(api) }
	      api:On(message, fn)              NetherBags' messages (BAGS_CHANGED, WINDOW_SHOWN, ...)
	      api:AddRule(def)                 a rule property for groups and search (Data/Rules.lua)
	      api:AddSkin(def)                 a theme (UI/Skin.lua): plugins can make NetherBags match
	                                       another interface's look on every window and tab
	      api:AddMenuItem(fn)              fn(entry) -> { text, glyph, onClick } | nil, added to the
	                                       Alt+Right-click item menu
	      api:Print(fmt, ...)
	  A plugin's errors are caught and counted against it; after 5 it is switched off and listed in
	  Settings > Plugins. A plugin can be switched off there by the player. ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Plugin = NBG:Module("Plugin")

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring

local plugins, order = {}, {}
Plugin.menuItems = {}

function Plugin:List()
	local out = {}
	for _, id in ipairs(order) do out[#out + 1] = plugins[id] end
	return out
end

function Plugin:Failed(owner, where, err)
	owner.errors = (owner.errors or 0) + 1
	NBG:Log("error", "plugin %s (%s): %s", tostring(owner.id), tostring(where), tostring(err))
	if owner.errors >= 5 and not owner.disabled then
		owner.failed = tostring(err)
		self:SetEnabled(owner.id, false)
		NBG:Print(L["The plugin %s kept failing and was switched off (Settings > Plugins)."], tostring(owner.name or owner.id))
	end
end

local function Call(p, what, fn, ...)
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, ...)
	if not ok then Plugin:Failed(p, what, err) end
end

function Plugin:SetEnabled(id, on)
	local p = plugins[id]
	if not p then return end
	local db = NBG.db and NBG.db.plugins
	if on then
		p.disabled = false
		if db then db[id] = nil end
		Call(p, "OnEnable", p.def.OnEnable, p.api)
	else
		if not p.disabled then Call(p, "OnDisable", p.def.OnDisable, p.api) end
		p.disabled = true
		if db and not p.failed then db[id] = false end
	end
	NBG.Windows:RefreshAll()
end

local function MakeAPI(p)
	local api = {}
	function api:On(msg, fn) return NBG:Register(msg, function(_, ...) return fn(...) end, p) end
	function api:AddRule(def)
		if type(def) == "table" and type(def.get) == "function" then
			local get = def.get
			def.get = function(e) if p.disabled then return nil end local ok, v = pcall(get, NBG.Copy(e)) if not ok then Plugin:Failed(p, "rule " .. tostring(def.id), v) return nil end return v end
		end
		return NBG.Rules:Register(def)
	end
	function api:AddSkin(def) return NBG.Skin:Register(def) end
	function api:AddMenuItem(fn)
		if type(fn) == "function" then Plugin.menuItems[#Plugin.menuItems + 1] = { owner = p, fn = fn } end
	end
	function api:Print(fmt, ...) NBG:Print("[" .. tostring(p.name) .. "] " .. tostring(fmt), ...) end
	function api:Settings() NBG.db.pluginData = NBG.db.pluginData or {} NBG.db.pluginData[p.id] = NBG.db.pluginData[p.id] or {} return NBG.db.pluginData[p.id] end
	return api
end

function Plugin:Register(def)
	if type(def) ~= "table" or type(def.id) ~= "string" or not def.id:match("^[%w_%-]+$") or #def.id > 40 then return nil, "an id (letters, digits, - and _) is needed" end
	if plugins[def.id] then return nil, "a plugin with that id is already registered" end
	local p = { id = def.id, name = type(def.name) == "string" and def.name or def.id, version = type(def.version) == "string" and def.version or nil,
		description = type(def.description) == "string" and def.description or nil, def = def, disabled = false, errors = 0 }
	p.api = MakeAPI(p)
	plugins[def.id] = p
	order[#order + 1] = def.id
	if NBG.loaded and NBG.db then
		if NBG.db.plugins and NBG.db.plugins[def.id] == false then p.disabled = true else Call(p, "OnEnable", def.OnEnable, p.api) end
	end
	return p.api
end

-- plugins that registered before our saved data was read start now
NBG:Register("DB_READY", function()
	NBG.db.plugins = type(NBG.db.plugins) == "table" and NBG.db.plugins or {}
	for _, id in ipairs(order) do
		local p = plugins[id]
		if NBG.db.plugins[id] == false then p.disabled = true elseif not p.started then p.started = true Call(p, "OnEnable", p.def.OnEnable, p.api) end
	end
end)

-- extra item menu entries
function Plugin:MenuItems(e)
	local out = {}
	for _, m in ipairs(self.menuItems) do
		if not m.owner.disabled then
			local ok, it = pcall(m.fn, NBG.Copy(e))
			if not ok then self:Failed(m.owner, "menu", it)
			elseif type(it) == "table" and type(it.text) == "string" then
				local click = it.onClick
				out[#out + 1] = { text = it.text, glyph = it.glyph, onClick = function() if type(click) == "function" then Call(m.owner, "menu click", click) end end }
			end
		end
	end
	return out
end

---------------------------------------------------------------------------------------------
-- the global
---------------------------------------------------------------------------------------------
local API = { version = NBG.VERSION, apiVersion = NBG.API_VERSION }
function API:Toggle(id) NBG.Windows:Toggle(id or "bags") end
function API:Open(id, place) NBG.Windows:Open(id or "bags", place) end
function API:Close(id) NBG.Windows:Close(id or "bags") end
function API:Search(text) NBG:Fire("FIND_EVERYWHERE", tostring(text or "")) end
function API:Items(place, key)
	key = key or NBG:PlayerKey()
	local list
	if key == NBG:PlayerKey() and place == "bags" then list = NBG.Containers:All("bags")
	elseif key == NBG:PlayerKey() and place == "bank" and NBG.Containers:BankOpen() then list = NBG.Containers:All("bank")
	else list = NBG.Store:Entries(key, place) end
	local out = {}
	for i, e in ipairs(list) do out[i] = NBG.Copy(e) end
	return out
end
function API:Owners(id) return NBG.Copy(NBG.Store:Totals(tonumber(id)) or {}) end
function API:RegisterPlugin(def) return Plugin:Register(def) end
_G.NetherBags = API

-- key bindings (Bindings.xml)
_G.BINDING_HEADER_NETHERBAGS = "NetherBags"
_G.BINDING_NAME_NETHERBAGS_TOGGLE = L["Open / close the bags"]
_G.BINDING_NAME_NETHERBAGS_BANK = L["Open / close the bank (saved when away)"]
_G.BINDING_NAME_NETHERBAGS_EVERYWHERE = L["Everywhere: search every character"]
_G.BINDING_NAME_NETHERBAGS_MODE = L["Switch One bag / Insight"]
function API:ToggleMode()
	local w = NBG.Windows:Get("bags")
	if not w:IsShown() then NBG.Windows:Open("bags") return end
	w:SetMode(w:Mode() == "onebag" and "insight" or "onebag")
end
