--[[ NetherBags - Features/Slash.lua
	/nbags (or /netherbags) and the minimap's addon menu, and the question asked once at install
	when NetherUI is there: follow NetherUI's theme, or keep NetherBags' own look.

	  /nbags                 open / close the bags
	  /nbags bank | guild | everywhere [text] | currency
	  /nbags onebag | insight    switch the mode
	  /nbags questbar        the quest item bar on / off
	  /nbags sort | config | profile <name> | theme | diag | help ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Slash = NBG:Module("Slash")

local function Help()
	NBG:Print(L["commands:"])
	for _, l in ipairs({
		"/nbags  -  " .. L["open / close the bags"],
		"/nbags bank | guild | currency  -  " .. L["the bank, the guild bank, currencies"],
		"/nbags everywhere [text]  -  " .. L["search every character"],
		"/nbags onebag | insight  -  " .. L["switch the mode"],
		"/nbags sort  -  " .. L["sort the bags"],
		"/nbags questbar  -  " .. L["the quest item bar on / off (right-click the quest button in the title bar for its options)"],
		"/nbags config  -  " .. L["settings"],
		"/nbags profile <name>  -  " .. L["use a profile"],
		"/nbags theme  -  " .. L["follow NetherUI's theme or keep NetherBags' look"],
		"/nbags conflicts  -  " .. L["other bag addons that overlap with NetherBags"],
		"/nbags diag  -  " .. L["errors caught, for a bug report"],
	}) do NBG.Chat("  " .. l) end
end

local function Run(msg)
	msg = type(msg) == "string" and msg or ""
	local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	if cmd == "" then NBG.Windows:Toggle("bags")
	elseif cmd == "help" or cmd == "?" then Help()
	elseif cmd == "bank" then NBG.Windows:Toggle("bank")
	elseif cmd == "guild" then
		if NBG.GuildBank:Available() then NBG.Windows:Open("bags", "guild") else NBG:Print(L["No guild bank for this character."]) end
	elseif cmd == "everywhere" or cmd == "find" or cmd == "search" then
		NBG.Windows:Open("bags", "everywhere")
		if rest ~= "" then NBG:Fire("SEARCH_SET", "bags", rest) end
	elseif cmd == "currency" or cmd == "currencies" then NBG.Windows:Open("bags", "currency")
	elseif cmd == "onebag" or cmd == "insight" then
		NBG.Settings:Set("mode.bags", cmd)
		NBG.Windows:Open("bags")
	elseif cmd == "questbar" or cmd == "quest" or cmd == "qbar" then NBG.QuestBar:Toggle()
	elseif cmd == "sort" then NBG.Sort:Run("bags")
	elseif cmd == "config" or cmd == "settings" or cmd == "options" then NBG.Config:Open()
	elseif cmd == "profile" then
		if rest == "" then NBG:Print(L["Profile in use: %s"], NBG.Settings:CurrentName())
		elseif not NBG.Profiles:Use(rest) then NBG:Print(L["No profile called %s."], rest) end
	elseif cmd == "conflicts" then
		if not NBG.Conflicts:Check(true) then NBG:Print(L["No other bag addon is in the way."]) end
	elseif cmd == "theme" then
		if NBG.Skin.NetherUI() then NBG.ThemeChoice:Show()
		else NBG:Print(L["NetherUI isn't installed, so NetherBags uses its own look. Other themes: Settings > General > Theme."]) end
	elseif cmd == "diag" then
		local E = NBG.errors
		NBG:Print("v%s, Forever %s, bank %s, guild bank %s, %d error(s)", NBG.VERSION, tostring(NBG:IsForever()), NBG.Containers:BankMode(), tostring(NBG.Store:HasGuildBank()), E.count)
		if E.latest then NBG:Print("latest: %s: %s", E.latest.context, E.latest.err) end
	else
		Help()
	end
end

_G.SLASH_NETHERBAGS1 = "/nbags"
_G.SLASH_NETHERBAGS2 = "/netherbags"
SlashCmdList.NETHERBAGS = function(msg) NBG:Safe("slash", Run, msg) end

-- the minimap's addon menu
function _G.NetherBags_OnAddonCompartmentClick(_, button)
	if button == "RightButton" then NBG.Config:Open() else NBG.Windows:Toggle("bags") end
end
-- the entry is added from here (not by the TOC) so the setting decides; a change applies after /reload
NBG:Register("LOGIN", function()
	local ACF = rawget(_G, "AddonCompartmentFrame")
	if not (NBG.Settings:Get("minimap.compartment") and ACF and type(ACF.RegisterAddon) == "function") then return end
	pcall(ACF.RegisterAddon, ACF, {
		text = "NetherBags",
		icon = "Interface\\AddOns\\NetherBags\\Media\\Icon",
		notCheckable = true,
		registerForAnyClick = true,
		func = function(_, inputData, menu)
			local button = type(inputData) == "table" and inputData.buttonName or inputData
			_G.NetherBags_OnAddonCompartmentClick(nil, button)
		end,
		funcOnEnter = function(btn)
			if not GameTooltip then return end
			GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
			GameTooltip:SetText("NetherBags", 1, 0.86, 0.55)
			GameTooltip:AddLine(L["Click: open or close the bags.  Right-click: settings."], 0.8, 0.8, 0.8)
			GameTooltip:Show()
		end,
		funcOnLeave = function() if GameTooltip then GameTooltip:Hide() end end,
	})
end)

---------------------------------------------------------------------------------------------
-- asked once: follow NetherUI's theme?
---------------------------------------------------------------------------------------------
function Slash:AskTheme(delay)
	local db = NBG.db
	if not db or db.global.themeAsked then return end
	if not NBG.Skin.NetherUI() then return end
	NBG:After(delay or 4, function()
		if db.global.themeAsked then return end
		if NBG.Conflicts and NBG.Conflicts:Showing() then Slash:AskTheme(3) return end
		NBG.ThemeChoice:Show()   -- UI/ThemeChoice.lua; closing it without a choice asks again next login
	end)
end
NBG:Register("LOGIN", function() Slash:AskTheme(4) end)
