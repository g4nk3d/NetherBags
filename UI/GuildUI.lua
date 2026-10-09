--[[ NetherBags - UI/GuildUI.lua
	The guild bank's bar: its tabs (One bag shows one tab at a time), withdrawals left today, and
	Deposit / Withdraw money and Log (through the game's own dialogs and log).

	  GuildUI:TabBar(parent, view [, withTabs]) -> bar; bar:Update(window) ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local GuildUI = NBG:Module("GuildUI")
local Skin, W = NBG.Skin, NBG.Widgets

local ipairs, max = ipairs, math.max

function GuildUI:TabBar(parent, view, withTabs)
	if withTabs == nil then withTabs = true end
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(24)
	bar.tabs = {}
	bar.withdraw = W:Text(bar, 10.5, "textDim")
	bar.log = W:Button(bar, L["Log"], 64, 22, { glyph = "log", size = 10.5, onClick = function()
		local GB = NBG.GuildBank
		W:Popup({ title = L["Guild bank log"], text = table.concat(GB:Log(GB.tab), "\n"), width = 460,
			buttons = { { label = L["Money log"], onClick = function() NBG:After(0, function()
				W:Popup({ title = L["Guild bank money log"], text = table.concat(GB:Log(nil), "\n"), width = 460, buttons = { { label = L["Close"] } } })
			end) end }, { label = L["Close"] } } })
	end })
	bar.dep = W:Button(bar, L["Deposit"], 84, 22, { glyph = "deposit", size = 10.5, onClick = function() NBG.GuildBank:DepositMoney() end })
	bar.wd = W:Button(bar, L["Withdraw"], 90, 22, { glyph = "up", size = 10.5, onClick = function() NBG.GuildBank:WithdrawMoney() end })
	function bar:Update(w)
		local GB = NBG.GuildBank
		local x = 0
		local n = 0
		if withTabs then
			for _, t in ipairs(GB:Tabs()) do
				n = n + 1
				local c = self.tabs[n]
				if not c then
					c = W:Chip(self, "", "guild", "accent", nil)
					self.tabs[n] = c
				end
				c:SetLabel(t.id .. " · " .. (t.name or L["Tab"]))
				c:ClearAllPoints() c:SetPoint("LEFT", x, 0)
				c:SetScript("OnClick", function() GB:SelectTab(t.id) end)
				c:SetOn(GB.tab == t.id)
				c:SetEnabled(t.viewable ~= false)
				c:Show()
				x = x + c:GetWidth() + 6
			end
		end
		for i = n + 1, #self.tabs do self.tabs[i]:Hide() end
		local open = GB:IsOpen()
		self.dep:SetShown(open) self.wd:SetShown(open) self.log:SetShown(open)
		local rx = 0
		for _, b in ipairs({ self.wd, self.dep, self.log }) do
			if b:IsShown() then b:ClearAllPoints() b:SetPoint("RIGHT", self, "RIGHT", -rx, 0) rx = rx + b:GetWidth() + 6 end
		end
		local left = GB:Withdrawals()
		self.withdraw:ClearAllPoints()
		self.withdraw:SetPoint("RIGHT", self, "RIGHT", -rx - 6, 0)
		if open and left then
			self.withdraw:SetText(L["Withdrawals left today:"] .. " |cfffadc96" .. (left < 0 and L["unlimited"] or tostring(left)) .. "|r")
			self.withdraw:Show()
		else
			self.withdraw:Hide()
		end
	end
	return bar
end

NBG:Register("GUILD_CHANGED", function() NBG.Windows:RefreshAll() end)
NBG:Register("GUILD_OPEN", function() NBG.Windows:RefreshAll() end)
