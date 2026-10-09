--[[ NetherBags - Core/Lifecycle.lua
	Start-up and shut-down, in order:

	  ADDON_LOADED (ours)   saved tables read and migrated; settings (the profile) and the store
	                        ready; fires "DB_READY"
	  PLAYER_LOGIN          fires "LOGIN" (hooks into the game's bags, tooltips, NetherSuite,
	                        the first-run question)
	  PLAYER_LOGOUT         fires "LOGOUT" (nothing is read then: the bags were saved as they changed)

	Saved tables: NetherBagsDB (account: profiles, which profile each character uses, every
	character's saved bags / bank / mail, guild banks, plugin switches) and NetherBagsCharDB (this
	character: schema only for now). ]]

local ADDON, ns = ...
local NBG = ns.NBG

local MIGRATIONS = {
	-- [2] = function(db, char) ... end   (later layouts add their steps here, oldest first)
}

local function Migrate(db, char)
	db.schema = tonumber(db.schema) or NBG.SCHEMA
	char.schema = tonumber(char.schema) or NBG.CHAR_SCHEMA
	for v = db.schema + 1, NBG.SCHEMA do
		if MIGRATIONS[v] then NBG:Safe("migration " .. v, MIGRATIONS[v], db, char) end
		db.schema = v
	end
end

NBG:On("ADDON_LOADED", function(_, name)
	if name ~= ADDON or NBG.loaded then return end
	_G.NetherBagsDB = type(_G.NetherBagsDB) == "table" and _G.NetherBagsDB or {}
	_G.NetherBagsCharDB = type(_G.NetherBagsCharDB) == "table" and _G.NetherBagsCharDB or {}
	local db, char = _G.NetherBagsDB, _G.NetherBagsCharDB
	NBG.db, NBG.char = db, char
	Migrate(db, char)
	NBG.Settings:Init(db, char)
	NBG.Store:Init(db)
	NBG.loaded = true
	NBG:Fire("DB_READY")
end)

NBG:On("PLAYER_LOGIN", function()
	NBG.loggedIn = true
	-- the player's key needs the game world (the name is not known before)
	NBG.playerKey = nil
	local key = NBG:PlayerKey()
	NBG.Store:Adopt()
	local db = NBG.db
	if db and db.profileKeys and not db.profileKeys[key] then
		db.profileKeys[key] = db.profiles[db.global.newChars] and db.global.newChars or "Default"
	end
	-- the profile is bound again with the full name (at load the name may not have been known)
	local old = NBG.Settings.profile
	NBG.Settings:Bind()
	if NBG.Settings.profile ~= old then NBG:Fire("PROFILE_CHANGED", NBG.Settings:CurrentName(), true) end
	NBG:Fire("LOGIN")
end)

NBG:On("PLAYER_LOGOUT", function()
	NBG:Fire("LOGOUT")
end)
