--[[ NetherBags - Features/Tooltip.lua
	"Owned by" lines on item tooltips: how many of the item each character of the account has, and
	where (bags, bank, mailbox), plus guild banks. From the store only (never guessed); a
	character's numbers are as new as its last visit. Setting: on by default; "only with Shift"
	optional. Item IDs handed back as secret values (in instances) are skipped: nothing is shown
	then. ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Tooltip = NBG:Module("Tooltip")
local Store, Settings, Common = NBG.Store, NBG.Settings, NBG.Common

local ipairs, tonumber = ipairs, tonumber
local Num, Open = NBG.Num, NBG.Open

local function Lines(tt, id)
	if not Settings:Get("tooltip.counts") then return end
	if Settings:Get("tooltip.shift") and not (IsShiftKeyDown and IsShiftKeyDown()) then return end
	local t = Store:Totals(id)
	if not t then return end
	local total = 0
	local shown = 0
	tt:AddLine(" ")
	for _, o in ipairs(t.owners) do
		local n = o.bags + o.bank + o.mail
		total = total + n
		shown = shown + 1
		if shown <= 8 then
			local parts = {}
			if o.bags > 0 then parts[#parts + 1] = L["bags"] .. " " .. o.bags end
			if o.bank > 0 then parts[#parts + 1] = L["bank"] .. " " .. o.bank end
			if o.mail > 0 then parts[#parts + 1] = L["mail"] .. " " .. o.mail end
			tt:AddDoubleLine(Common.ClassColor(o.class) .. o.key .. "|r", "|cffd8dce8" .. n .. "|r |cff8c96b0(" .. table.concat(parts, ", ") .. ")|r")
		end
	end
	if Settings:Get("tooltip.guild") then
		for _, g in ipairs(t.guilds) do
			total = total + g.count
			tt:AddDoubleLine("|cff78e678<" .. g.name .. ">|r", "|cffd8dce8" .. g.count .. "|r")
		end
	end
	if shown + #t.guilds > 1 then tt:AddDoubleLine("|cffe8c478" .. L["Total"] .. "|r", "|cffe8c478" .. total .. "|r") end
	tt:Show()
end

local function FromData(tt, data)
	data = Open(data)
	if not data then return end
	local id = Num(data.id)
	if not id or id <= 0 then return end
	if tt ~= _G.GameTooltip and tt ~= _G.ItemRefTooltip then return end
	NBG:Safe("tooltip counts", Lines, tt, id)
end

function Tooltip:Install()
	if self.installed then return end
	local TDP = rawget(_G, "TooltipDataProcessor")
	local E = type(_G.Enum) == "table" and _G.Enum.TooltipDataType
	if type(TDP) == "table" and type(TDP.AddTooltipPostCall) == "function" and E and E.Item then
		TDP.AddTooltipPostCall(E.Item, function(tt, data) FromData(tt, data) end)
		self.installed = true
		return
	end
	-- older clients: the tooltip's item
	local GT = _G.GameTooltip
	if GT and GT.HookScript then
		self.installed = true
		pcall(GT.HookScript, GT, "OnTooltipSetItem", function(tt)
			local _, link = tt:GetItem()
			local id = link and tonumber(tostring(link):match("item:(%d+)"))
			if id then NBG:Safe("tooltip counts", Lines, tt, id) end
		end)
	end
end

NBG:Register("LOGIN", function() Tooltip:Install() end)
