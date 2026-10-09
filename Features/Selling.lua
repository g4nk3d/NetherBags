--[[ NetherBags - Features/Selling.lua
	Junk at a vendor. When a merchant window opens, NetherBags sells the junk by itself (setting,
	on by default) a few items at a time, and says in chat what it sold and for how much. Locked
	items are never sold. "Junk" is: poor (grey) items with a vendor price (setting), items the
	player marked as junk, and items in a custom group set to "sell at vendors"; never an item the
	player keeps or locked. With "keep buyback" on, at most 12 are sold at a time, so every one of
	them can still be bought back.

	  Selling:AtMerchant()
	  Selling:JunkList() -> { entries }; Selling:JunkValue() -> count, copper
	  Selling:SellJunk(manual) ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Selling = NBG:Module("Selling")
local Containers, Marks, Items, Settings, Groups = NBG.Containers, NBG.Marks, NBG.Items, NBG.Settings, NBG.Groups

local ipairs = ipairs
Selling.merchant = false

function Selling:AtMerchant() return self.merchant end

function Selling:JunkList()
	local out = {}
	for _, e in ipairs(Containers:All("bags")) do
		if e.id and not Marks:IsLocked(e.id) and not e.noValue and not Items:QuestNeeded(e) then
			local junk = Marks:IsJunk(e) or (Groups:SellsAtVendor(e) ~= nil)
			if junk then
				local i = Items:Info(e.link)
				if i and (i.price or 0) > 0 then out[#out + 1] = e end
			end
		end
	end
	return out
end

function Selling:JunkValue()
	local n, value = 0, 0
	for _, e in ipairs(self:JunkList()) do
		local i = Items:Info(e.link)
		n = n + 1
		value = value + (i and i.price or 0) * (e.count or 1)
	end
	return n, value
end

local selling
function Selling:SellJunk(manual)
	if selling or not self.merchant then return end
	local list = self:JunkList()
	if #list == 0 then
		if manual then NBG:Print(L["No junk to sell."]) end
		return
	end
	local use = NBG.API("C_Container", "UseContainerItem") or _G.UseContainerItem
	if not use then return end
	local limit = Settings:Get("junk.buyback") and math.min(12, #list) or #list
	selling = { sold = 0, value = 0 }
	local i = 0
	local function Step()
		i = i + 1
		if not Selling.merchant or i > limit or NBG:InCombat() then
			local s = selling
			-- (the last checks land 0.4 s after the last sale)
			NBG:After(0.5, function()
			selling = nil
			Items:LearnFromBuyback()
			if s.sold > 0 and Settings:Get("junk.summary") then
				NBG:Print(L["Sold %d junk item(s) for %s."], s.sold, NBG.Widgets:Money(s.value))
			end
			if Settings:Get("junk.buyback") and #list > limit and Selling.merchant then
				NBG:Print(L["%d more to sell: they are left for now so everything sold can still be bought back."], #list - limit)
			end
			end)
			return
		end
		local e = list[i]
		-- the slot must still hold the same item
		local now = Containers:RefreshSlot(e.bag, e.slot) or Containers:Entry(e.bag, e.slot)
		if now and now.id == e.id and not now.locked and not Marks:IsLocked(e.id) and not Items:QuestNeeded(now) then
			local info = Items:Info(e.link)
			if pcall(use, e.bag, e.slot) then
				-- counted once the slot is really empty (the server can drop a sale sent too fast);
				-- a sale that didn't go through is sent again the other way: on the cursor, onto the vendor
				local value = (info and info.price or 0) * (e.count or 1)
				NBG:After(0.4, function()
					if not selling then return end
					local after = Containers:RefreshSlot(e.bag, e.slot)
					if not after or after.id ~= e.id then
						selling.sold = selling.sold + 1
						selling.value = selling.value + value
					elseif Selling.merchant and not NBG:InCombat() and not after.locked then
						local pick = NBG.API("C_Container", "PickupContainerItem") or _G.PickupContainerItem
						if pick and _G.PickupMerchantItem and pcall(pick, e.bag, e.slot) then
							pcall(PickupMerchantItem, 0)
							if _G.CursorHasItem and NBG.Call(CursorHasItem) and _G.ClearCursor then ClearCursor() end
						end
					end
				end)
			end
		end
		-- (one at a time, a quarter second apart: faster and the server silently drops some)
		NBG:After(0.25, Step)
	end
	Step()
end

local function Interaction(name)
	local E = type(_G.Enum) == "table" and _G.Enum.PlayerInteractionType
	return E and E[name]
end

local function Open(on)
	if Selling.merchant == on then return end
	Selling.merchant = on
	NBG:Fire("MERCHANT", on)
	if on and Settings:Get("junk.autoSell") then NBG:After(0.3, function() Selling:SellJunk(false) end) end
end
NBG:On("MERCHANT_SHOW", function() Open(true) end)
NBG:On("MERCHANT_CLOSED", function() Open(false) end)
NBG:On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind) if kind ~= nil and kind == Interaction("Merchant") then Open(true) end end)
NBG:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind) if kind ~= nil and kind == Interaction("Merchant") then Open(false) end end)
NBG:Register("MERCHANT", function() NBG.Windows:RefreshAll(true) end)
-- anything sold here, by hand too: the price the vendor really paid is learned
NBG:On("MERCHANT_UPDATE", function() NBG:Debounce("learnPrices", 0.3, function() Items:LearnFromBuyback() end) end)
