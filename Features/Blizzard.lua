--[[ NetherBags - Features/Blizzard.lua
	Taking the place of the game's bags, bank and guild bank, without replacing any of the game's
	code: the game's open/close functions are followed with hooksecurefunc (so the bag key, the
	backpack button and every "open the bags" in the game open NetherBags), and the game's own
	frames are moved to a hidden shelf instead of being hidden (so their own scripts, like closing
	the bank when the window goes, keep working). Each part has a switch (Settings > General /
	Bank & guild); off gives the game's own window back after a reload.

	Opening with other windows (settings, on by default): at a vendor, the bank, the mailbox, the
	auction house, a trade and the guild bank, the bags open, and close again with that window
	if they were opened for it. ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Blizzard = NBG:Module("Blizzard")
local Windows, Settings, Containers = NBG.Windows, NBG.Settings, NBG.Containers

local type, ipairs, pairs = type, ipairs, pairs

-- the shelf: shown, but too small to see, so the frames on it keep running
local shelf
local function Shelf()
	if shelf then return shelf end
	shelf = CreateFrame("Frame", "NetherBagsShelf", UIParent)
	shelf:SetSize(1, 1)
	shelf:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 1000, -1000)
	shelf:SetScale(0.001)
	shelf:SetAlpha(0)
	shelf:EnableMouse(false)
	return shelf
end

local hidden
local function Hidden()
	if hidden then return hidden end
	hidden = CreateFrame("Frame", "NetherBagsHidden", UIParent)
	hidden:Hide()
	return hidden
end

local function Park(frame, where)
	if not frame or frame.nbParked then return end
	if NBG:InCombat() and frame.IsProtected and frame:IsProtected() then
		NBG:AfterCombat("park " .. tostring(frame:GetName()), function() Park(frame, where) end)
		return
	end
	frame.nbParked = true
	pcall(frame.SetParent, frame, where)
end

-- the game's bag windows
local function ParkBags()
	if not Settings:Get("blizzard.bags") then return end
	for i = 1, NBG.Const("NUM_CONTAINER_FRAMES", 13) do Park(_G["ContainerFrame" .. i], Hidden()) end
	Park(_G.ContainerFrameCombinedBags, Hidden())
end

-- Our bags window follows the game's own idea of whether the bags are open (IsBagOpen(0)): every
-- way the game opens or closes them (the bag key, the backpack button, a vendor, Esc) changes
-- that, and one check a frame later sets ours to match. (Following each open/close function
-- separately would fight itself: the game's toggle calls its open and close functions too.)
local suppressUntil = 0
local function GameBagsOpen()
	if type(_G.IsBagOpen) ~= "function" then return nil end
	local ok, v = pcall(IsBagOpen, Containers.BACKPACK)
	if not ok then return nil end
	return v and true or false
end

local function Sync(hint)
	if not Settings:Get("blizzard.bags") then return end
	NBG:Debounce("bagsync", 0, function()
		local open = GameBagsOpen()
		if open == nil then
			-- no IsBagOpen on this client: the hook's own meaning
			if hint == "toggle" then Windows:Toggle("bags") elseif hint == true then Windows:Open("bags") elseif hint == false then Windows:Close("bags") end
			return
		end
		if open and not Windows:IsOpen("bags") then
			if NBG:Clock() < suppressUntil then return end
			Windows:Open("bags")
		elseif not open and Windows:IsOpen("bags") then
			Blizzard.closingFromGame = true
			Windows:Close("bags")
			Blizzard.closingFromGame = nil
		end
	end)
end

-- our window closed (its X, Esc): close the game's too, so the next bag key press opens again
NBG:Register("WINDOW_HIDDEN", function(_, id)
	if id == "bags" and not Blizzard.closingFromGame and GameBagsOpen() and _G.CloseAllBags then pcall(CloseAllBags) end
end)
-- our window opened by us (slash, key binding, minimap): the game's state follows
NBG:Register("WINDOW_SHOWN", function(_, id)
	if id == "bags" and GameBagsOpen() == false and _G.OpenBackpack and Settings:Get("blizzard.bags") then
		Blizzard.openingFromUs = true
		pcall(OpenBackpack)
		Blizzard.openingFromUs = nil
	end
end)

local function IsInventoryBag(id)
	id = tonumber(id)
	return id and (id == Containers.KEYRING or (id >= Containers.BACKPACK and id <= Containers.NUM_BAGS))
end

local hooked = {}
function Blizzard:Hook()
	local function H(name, fn)
		if hooked[name] or type(rawget(_G, name)) ~= "function" then return end
		hooked[name] = true
		hooksecurefunc(name, function(...) NBG:Safe("hook " .. name, fn, ...) end)
	end
	H("ToggleAllBags", function() Sync("toggle") end)
	H("ToggleBackpack", function() Sync("toggle") end)
	H("OpenAllBags", function() Sync(true) end)
	H("OpenBackpack", function() if not Blizzard.openingFromUs then Sync(true) end end)
	H("CloseAllBags", function() Sync(false) end)
	H("CloseBackpack", function() Sync(false) end)
	H("ToggleBag", function(id)
		if IsInventoryBag(id) then Sync("toggle")
		elseif Settings:Get("blizzard.bank") then Windows:Toggle("bank") end
	end)
	H("OpenBag", function(id) if IsInventoryBag(id) then Sync(true) end end)
	H("CloseBag", function(id) if IsInventoryBag(id) then Sync(false) end end)
end

---------------------------------------------------------------------------------------------
-- bank and guild bank
---------------------------------------------------------------------------------------------
local function CloseBankInteraction()
	local C = rawget(_G, "C_PlayerInteractionManager")
	local E = type(_G.Enum) == "table" and _G.Enum.PlayerInteractionType
	if C and C.ClearInteraction and E and E.Banker then pcall(C.ClearInteraction, E.Banker) return end
	local B = rawget(_G, "C_Bank")
	if B and B.CloseBankFrame then pcall(B.CloseBankFrame) return end
	if _G.CloseBankFrame then pcall(CloseBankFrame) end
end

NBG:Register("BANK_OPEN", function(_, open)
	if open then
		if Settings:Get("blizzard.bank") then
			Park(_G.BankFrame, Shelf())
			local w = Windows:Open("bank", "bank")
			w.owner = NBG:PlayerKey()
			w:Refresh()
		end
		if Settings:Get("auto.bank") then Blizzard:AutoOpen("bank") else suppressUntil = NBG:Clock() + 1 end
	else
		if Windows:IsOpen("bank") then
			local w = Windows:Get("bank")
			if w.owner == NBG:PlayerKey() then Windows:Close("bank") end
		end
		Blizzard:AutoClose("bank")
	end
end)

NBG:Register("WINDOW_HIDDEN", function(_, id)
	-- closing our bank window ends the visit, like the game's
	if id == "bank" and Containers:BankOpen() and Settings:Get("blizzard.bank") then CloseBankInteraction() end
	if id == "guild" and NBG.GuildBank:IsOpen() and Settings:Get("blizzard.guild") then NBG.GuildBank:Close() end
end)

NBG:Register("GUILD_OPEN", function(_, open)
	if open then
		if Settings:Get("blizzard.guild") then
			Park(_G.GuildBankFrame, Shelf())
			Windows:Open("guild", "guild")
		end
		if Settings:Get("auto.guild") then Blizzard:AutoOpen("guild") else suppressUntil = NBG:Clock() + 1 end
	else
		Windows:Close("guild")
		Blizzard:AutoClose("guild")
	end
end)
-- the game's guild bank is load on demand
NBG:On("ADDON_LOADED", function(_, name)
	if name == "Blizzard_GuildBankUI" and NBG.GuildBank:IsOpen() and Settings:Get("blizzard.guild") then Park(_G.GuildBankFrame, Shelf()) end
end)

---------------------------------------------------------------------------------------------
-- opening with other windows
---------------------------------------------------------------------------------------------
local openedFor = {}
function Blizzard:AutoOpen(why)
	if not Windows:IsOpen("bags") then
		openedFor[why] = true
		Windows:Open("bags")
	end
end
function Blizzard:AutoClose(why)
	if openedFor[why] then
		openedFor[why] = nil
		if Settings:Get("auto.closeWith") and not next(openedFor) then Windows:Close("bags") end
	end
end
NBG:Register("WINDOW_HIDDEN", function(_, id) if id == "bags" then NBG.wipe(openedFor) end end)

local AUTO = {
	{ show = "MERCHANT_SHOW", hide = "MERCHANT_CLOSED", key = "auto.merchant", kind = "Merchant" },
	{ show = "MAIL_SHOW", hide = "MAIL_CLOSED", key = "auto.mail", kind = "MailInfo" },
	{ show = "AUCTION_HOUSE_SHOW", hide = "AUCTION_HOUSE_CLOSED", key = "auto.auction", kind = "Auctioneer" },
	{ show = "TRADE_SHOW", hide = "TRADE_CLOSED", key = "auto.trade", kind = "TradePartner" },
	{ show = "TRADE_SKILL_SHOW", hide = "TRADE_SKILL_CLOSE", key = "auto.crafting" },
	{ show = "CRAFT_SHOW", hide = "CRAFT_CLOSE", key = "auto.crafting" },
}
for _, a in ipairs(AUTO) do
	NBG:On(a.show, function()
		if Settings:Get(a.key) then Blizzard:AutoOpen(a.key) else suppressUntil = NBG:Clock() + 1 end
	end)
	NBG:On(a.hide, function() Blizzard:AutoClose(a.key) end)
end
NBG:On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)
	local E = type(_G.Enum) == "table" and _G.Enum.PlayerInteractionType
	if not E or kind == nil then return end
	for _, a in ipairs(AUTO) do
		if E[a.kind] == kind then
			if Settings:Get(a.key) then Blizzard:AutoOpen(a.key) else suppressUntil = NBG:Clock() + 1 end
		end
	end
end)
NBG:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
	local E = type(_G.Enum) == "table" and _G.Enum.PlayerInteractionType
	if not E or kind == nil then return end
	for _, a in ipairs(AUTO) do if E[a.kind] == kind then Blizzard:AutoClose(a.key) end end
end)

-- the character pane opens the bags too; the world map closes them (both settings). The game's
-- frames are only followed (HookScript), never changed.
local function FollowFrames()
	local cf = rawget(_G, "CharacterFrame")
	if cf and cf.HookScript and not Blizzard.charHooked then
		Blizzard.charHooked = true
		cf:HookScript("OnShow", function() if Settings:Get("auto.character") then Blizzard:AutoOpen("auto.character") end end)
		cf:HookScript("OnHide", function() Blizzard:AutoClose("auto.character") end)
	end
	local wm = rawget(_G, "WorldMapFrame")
	if wm and wm.HookScript and not Blizzard.mapHooked then
		Blizzard.mapHooked = true
		wm:HookScript("OnShow", function()
			if Settings:Get("auto.closeMap") and Windows:IsOpen("bags") and not NBG:InCombat() then Windows:Close("bags") end
		end)
	end
end
NBG:Register("LOGIN", function() NBG:After(0.5, FollowFrames) end)
NBG:On("ADDON_LOADED", function() if NBG.loggedIn then FollowFrames() end end)

NBG:On("PLAYER_REGEN_DISABLED", function()
	if Settings:Get("auto.closeCombat") then
		for _, id in ipairs({ "bags", "bank", "guild" }) do
			local w = Windows.list[id]
			if w and w:IsShown() and not w:IsProtected() then w:Hide() end
		end
	end
end)

NBG:Register("LOGIN", function()
	Blizzard:Hook()
	ParkBags()
	-- the game's bags may be built later (load order): park them again a moment after login
	NBG:After(1, ParkBags)
end)
