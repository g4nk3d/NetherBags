--[[ NetherBags - Features/Suite.lua
	NetherBags on NetherSuite's shelf, when the hub is installed: a tile with the family banner on
	the home page, its own page in the hub (nether://netherbags), status lines, diagnostics, and
	every setting in the hub's search (a result opens the right page of the settings window). The
	hub only reads values; every change is made here.

	Nothing in this file runs without NetherSuite: the descriptor is handed over at login when the
	hub's API is there, or left in NetherSuite_Queue for it to collect. ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Suite = NBG:Module("Suite")

local type, pairs, ipairs, pcall, concat = type, pairs, ipairs, pcall, table.concat

local function Records()
	local out = {}
	for _, p in ipairs(NBG.Config.PAGES) do
		for _, c in ipairs(p.controls or {}) do
			if c.kind == "toggle" then
				out[#out + 1] = { id = c.key, kind = "toggle", label = c.label, page = p.id, tip = c.sub, keywords = c.keywords }
			elseif c.kind == "slider" then
				out[#out + 1] = { id = c.key, kind = "slider", label = c.label, page = p.id, min = c.min, max = c.max, step = c.step, fmt = c.fmt, keywords = c.keywords }
			elseif c.kind == "choice" then
				local vals = {}
				local ok, list = pcall(c.values)
				for _, v in ipairs(ok and list or {}) do vals[#vals + 1] = { value = v.value, label = v.label } end
				out[#out + 1] = { id = c.key, kind = "choice", label = c.label, page = p.id, values = vals, keywords = c.keywords }
			end
		end
	end
	out[#out + 1] = { id = "profiles.export", kind = "button", label = L["Export or import a profile"], page = "profiles", keywords = { "share", "string", "copy" } }
	out[#out + 1] = { id = "groups.new", kind = "button", label = L["Make a new group"], page = "groups", keywords = { "category", "rules", "filter" } }
	for _, r in ipairs(out) do r.path = { r.id } end
	return out
end

local function Pages()
	local out = {}
	for _, p in ipairs(NBG.Config.PAGES) do out[#out + 1] = { id = p.id, label = p.label } end
	return out
end

local function Descriptor()
	return {
		id = "netherbags", name = "NetherBags", version = NBG.VERSION, apiVersion = 1, addon = "NetherBags",
		icon = NBG.MEDIA .. "Logo", banner = NBG.MEDIA .. "Banner",
		description = L["Your bags, bank and guild bank in One bag or Insight: groups you define, search everywhere, every character."],
		category = "Inventory", slash = { "/nbags", "/netherbags" },
		optional = { "NetherUI" },
		pages = Pages(),
		open = function(page) NBG.Config:Open(page) return true end,
		status = function()
			local used, total = NBG.Containers:Counts("bags")
			local chars = #NBG.Store:Characters()
			return {
				{ L["Bags"], ("%d / %d"):format(used, total) },
				{ L["Profile"], NBG.Settings:CurrentName() },
				{ L["Characters saved"], tostring(chars) },
				{ L["Theme"], NBG.Skin:Current().label },
			}
		end,
		diagnostics = function()
			local E = NBG.errors
			return { errors = E.count, latest = E.latest and (E.latest.context .. ": " .. E.latest.err) or nil,
				report = ("NetherBags v%s, Forever %s, bank %s, guild bank %s"):format(NBG.VERSION, tostring(NBG:IsForever()), NBG.Containers:BankMode(), tostring(NBG.Store:HasGuildBank())) }
		end,
		settings = Records,
		value = function(path)
			local key = type(path) == "table" and concat(path, ".") or tostring(path)
			return NBG.Settings:Get(key)
		end,
		focus = function(id, page)
			NBG.Config:Open(page)
			return true
		end,
	}
end

function Suite:Join()
	if self.joined then return end
	local S = rawget(_G, "NetherSuite")
	if type(S) == "table" and type(S.RegisterAddon) == "function" then
		self.joined = pcall(S.RegisterAddon, S, Descriptor())
	elseif _G.C_AddOns and C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist("NetherSuite") then
		_G.NetherSuite_Queue = _G.NetherSuite_Queue or {}
		table.insert(_G.NetherSuite_Queue, Descriptor())
		self.joined = true
	end
end

NBG:Register("LOGIN", function() Suite:Join() end)
NBG:On("ADDON_LOADED", function(_, name) if name == "NetherSuite" then NBG:After(0, function() Suite:Join() end) end end)
