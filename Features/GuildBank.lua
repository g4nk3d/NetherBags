--[[ NetherBags - Features/GuildBank.lua
	The guild bank, on clients that have one. At a guild vault NetherBags reads every tab the
	character may view (asking the server for each, a little apart), keeps a copy in the store,
	and shows it in the guild window (One bag: one tab at a time; Insight: every tab, grouped).
	Away from the vault the saved copy is shown, with its age. Clicks call the game's own guild
	bank functions: Left-click picks an item up, Right-click moves it to the bags, and dropping
	an item on a slot deposits it there. Money goes through the game's own deposit / withdraw
	dialogs.

	  GuildBank:Available()   the client has a guild bank and this character is in a guild (or a
	                          copy is saved)
	  GuildBank:IsOpen()      at a guild vault now
	  GuildBank:Tabs()        { { id, name, icon, size, kind = "gtab", viewable } }
	  GuildBank:Entries()     every item (live or saved)
	  GuildBank:Slot(tab, slot), :Money(), :Name(), :Saved(), :Withdrawals()
	  GuildBank:BindRow(button, entry)   the clicks of a row / slot ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local GuildBank = NBG:Module("GuildBank")
local Store, Containers = NBG.Store, NBG.Containers

local type, pairs, ipairs, tonumber = type, pairs, ipairs, tonumber
local Num, Str = NBG.Num, NBG.Str

local SLOTS = NBG.Const("MAX_GUILDBANK_SLOTS_PER_TAB", 98)
GuildBank.open = false
GuildBank.tab = 1

function GuildBank:Has() return Store:HasGuildBank() end

function GuildBank:Name() return Str(NBG.Call(_G.GetGuildInfo, "player")) end

function GuildBank:Available()
	if not self:Has() then return false end
	local name = self:Name()
	return name ~= nil
end

function GuildBank:IsOpen() return self.open end

function GuildBank:Saved()
	local name = self:Name()
	return name and Store:Guild(name) or nil
end

function GuildBank:NumTabs()
	if self.open then return Num(NBG.Call(_G.GetNumGuildBankTabs)) or 0 end
	local g = self:Saved()
	local n = 0
	for i in pairs(g and g.tabs or {}) do n = math.max(n, i) end
	return n
end

function GuildBank:Tabs()
	local out = {}
	if self.open then
		for i = 1, self:NumTabs() do
			local name, icon, viewable = NBG.Call(_G.GetGuildBankTabInfo, i)
			out[#out + 1] = { id = i, index = i, name = Str(name) or (L["Tab"] .. " " .. i), icon = icon, size = SLOTS, kind = "gtab", viewable = viewable and true or false, place = "guild" }
		end
	else
		local g = self:Saved()
		for i, t in pairs(g and g.tabs or {}) do
			out[#out + 1] = { id = i, index = i, name = t.name, icon = t.icon, size = SLOTS, kind = "gtab", viewable = t.viewable, place = "guild" }
		end
		table.sort(out, function(a, b) return a.id < b.id end)
	end
	return out
end

local function ReadSlot(tab, slot)
	local link = Str(NBG.Call(_G.GetGuildBankItemLink, tab, slot))
	if not link then return nil end
	local icon, count, locked, _, quality = NBG.Call(_G.GetGuildBankItemInfo, tab, slot)
	local s = Containers.ItemString(link)
	return { link = link, str = s, id = tonumber(link:match("item:(%d+)")), count = Num(count) or 1, icon = icon, locked = locked and true or false,
		quality = Num(quality), place = "guild", tab = tab, bag = tab, slot = slot, live = false, guildLive = true }
end

function GuildBank:Slot(tab, slot)
	if self.open then return ReadSlot(tab, slot) end
	local g = self:Saved()
	local t = g and g.tabs[tab]
	local s = t and t.items and t.items[slot]
	local e = s and Store.Unpack(s)
	if e then e.place, e.tab, e.bag, e.slot = "guild", tab, tab, slot end
	return e
end

function GuildBank:Entries()
	local out = {}
	if self.open then
		for _, t in ipairs(self:Tabs()) do
			if t.viewable then
				for slot = 1, SLOTS do
					local e = ReadSlot(t.id, slot)
					if e then out[#out + 1] = e end
				end
			end
		end
		return out
	end
	local name = self:Name()
	return name and Store:GuildEntries(name) or out
end

function GuildBank:Money()
	if self.open then return Num(NBG.Call(_G.GetGuildBankMoney)) or 0 end
	local g = self:Saved()
	return g and g.money or 0
end

function GuildBank:Withdrawals()
	local n = Num(NBG.Call(_G.GetGuildBankRemainingWithdrawals))
	return n
end

---------------------------------------------------------------------------------------------
-- at the vault
---------------------------------------------------------------------------------------------
local function QueryAll()
	local n = GuildBank:NumTabs()
	for i = 1, n do
		NBG:After(0.15 * (i - 1), function()
			if GuildBank.open and _G.QueryGuildBankTab then pcall(QueryGuildBankTab, i) end
		end)
	end
end

local function SetOpen(open)
	if GuildBank.open == open then return end
	GuildBank.open = open
	if open then
		GuildBank.tab = Num(NBG.Call(_G.GetCurrentGuildBankTab)) or 1
		QueryAll()
		NBG:Fire("GUILD_OPEN", true)
	else
		NBG:Fire("GUILD_OPEN", false)
	end
end

local function Interaction(name)
	local E = type(_G.Enum) == "table" and _G.Enum.PlayerInteractionType
	return E and E[name]
end
NBG:On("GUILDBANKFRAME_OPENED", function() SetOpen(true) end)
NBG:On("GUILDBANKFRAME_CLOSED", function() SetOpen(false) end)
NBG:On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind) if kind ~= nil and kind == Interaction("GuildBanker") then SetOpen(true) end end)
NBG:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind) if kind ~= nil and kind == Interaction("GuildBanker") then SetOpen(false) end end)
NBG:On("GUILDBANKBAGSLOTS_CHANGED", function()
	if not GuildBank.open then return end
	NBG:Debounce("guildSlots", 0.2, function()
		for _, t in ipairs(GuildBank:Tabs()) do if t.viewable then Store:SaveGuildTab(t.id) end end
		NBG:Fire("GUILD_CHANGED")
	end)
end)
NBG:On("GUILDBANK_UPDATE_MONEY", function() if GuildBank.open then Store:SaveGuildTab(nil) NBG:Fire("GUILD_CHANGED") end end)
NBG:On("GUILDBANK_UPDATE_TABS", function() if GuildBank.open then QueryAll() NBG:Fire("GUILD_CHANGED") end end)
NBG:On("GUILDBANK_UPDATE_WITHDRAWMONEY", function() NBG:Fire("GUILD_CHANGED") end)

function GuildBank:SelectTab(tab)
	self.tab = tab
	if self.open then
		if _G.SetCurrentGuildBankTab then pcall(SetCurrentGuildBankTab, tab) end
		if _G.QueryGuildBankTab then pcall(QueryGuildBankTab, tab) end
	end
	NBG:Fire("GUILD_CHANGED")
end

function GuildBank:Close()
	local C = rawget(_G, "C_PlayerInteractionManager")
	local kind = Interaction("GuildBanker")
	if C and C.ClearInteraction and kind then pcall(C.ClearInteraction, kind)
	elseif _G.CloseGuildBankFrame then pcall(CloseGuildBankFrame) end
end

-- clicks on a guild row / slot (only at the vault)
function GuildBank:BindRow(b, e)
	b.nbOnClick = function(self, btn)
		if not GuildBank.open or not e.tab then return end
		if btn == "RightButton" then
			if _G.AutoStoreGuildBankItem then pcall(AutoStoreGuildBankItem, e.tab, e.slot) end
		else
			if _G.PickupGuildBankItem then pcall(PickupGuildBankItem, e.tab, e.slot) end
		end
	end
	b:SetScript("OnReceiveDrag", function()
		if GuildBank.open and e.tab and _G.PickupGuildBankItem then pcall(PickupGuildBankItem, e.tab, e.slot) end
	end)
end

function GuildBank:DepositMoney() pcall(StaticPopup_Show, "GUILDBANK_DEPOSIT") end
function GuildBank:WithdrawMoney() pcall(StaticPopup_Show, "GUILDBANK_WITHDRAW") end

-- the latest transactions of a tab (or the money log), as text lines
function GuildBank:Log(tab)
	local lines = {}
	if not self.open then return { L["Open the guild bank to read its log."] } end
	if tab then
		if _G.QueryGuildBankLog then pcall(QueryGuildBankLog, tab) end
		local n = Num(NBG.Call(_G.GetNumGuildBankTransactions, tab)) or 0
		for i = n, math.max(1, n - 30), -1 do
			local kind, name, link, count, tab1, tab2, year, month, day, hour = NBG.Call(_G.GetGuildBankTransaction, tab, i)
			if kind then
				local verb = (kind == "deposit" and L["deposited"]) or (kind == "withdraw" and L["withdrew"]) or (kind == "move" and L["moved"]) or tostring(kind)
				lines[#lines + 1] = ("%s %s %s%s"):format(Str(name) or "?", verb, Str(link) or "?", (Num(count) or 1) > 1 and (" x" .. count) or "")
			end
		end
	else
		local n = Num(NBG.Call(_G.GetNumGuildBankMoneyTransactions)) or 0
		for i = n, math.max(1, n - 30), -1 do
			local kind, name, amount = NBG.Call(_G.GetGuildBankMoneyTransaction, i)
			if kind then lines[#lines + 1] = ("%s %s %s"):format(Str(name) or "?", tostring(kind), NBG.Widgets:Money(Num(amount) or 0)) end
		end
	end
	if #lines == 0 then lines[1] = L["Nothing logged yet (the log loads a moment after it is asked for)."] end
	return lines
end
