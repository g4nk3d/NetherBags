--[[ NetherBags - Core/Locale.lua
	Every string the player reads goes through L. Keys are the English text itself, so a missing
	translation simply shows English. There is no other language yet; a translation would add a
	Locales/<locale>.lua that fills ns.L. ]]
local _, ns = ...
local L = setmetatable({}, { __index = function(_, k) return k end })
ns.L = L
ns.NBG.L = L
