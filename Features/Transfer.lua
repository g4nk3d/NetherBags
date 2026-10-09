--[[ NetherBags - Features/Transfer.lua
	Moving many items at once to the window that is open:

	  - from the bags to the open bank, mailbox (the Send tab) or trade window;
	  - from the bank back to the bags.

	What moves is what the Insight list shows (the search, the category and the quick filters
	decide), or one group (right-click its header). Locked items never move; soulbound and quest
	items never go to the mailbox or a trade. One item at a time, waiting for the game between
	moves (the server takes one move at a time); it stops when the other side is full or closes.

	"Send all to an alt": every stack of an item (not locked) to another character of the account,
	12 attachments per mail. NetherBags fills in the game's mail form; each mail goes when the player
	clicks Send in NetherBags' dialog (a click of the player's for every mail).

	  Transfer:Target(window) -> "bank" | "mail" | "trade" | "bags" | nil, label
	  Transfer:Run(entries, target)
	  Transfer:SendAll(entry, recipient)
	  Transfer:Alts() -> { key, ... } the account's other characters of the same faction ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Transfer = NBG:Module("Transfer")
local Containers, Marks, Items, Settings = NBG.Containers, NBG.Marks, NBG.Items, NBG.Settings

local ipairs, pairs = ipairs, pairs
local MAIL_MAX = 12
local TRADE_MAX = 6

local function Shown(name) local f = rawget(_G, name) return f and f.IsShown and f:IsShown() or false end
local function Visible(name) local f = rawget(_G, name) return f and f.IsVisible and f:IsVisible() or false end

function Transfer:MailOpen() return Shown("MailFrame") end
function Transfer:TradeOpen() return Shown("TradeFrame") end

function Transfer:Target(w)
	if not (w and w.Live and w:Live()) then return nil end
	if w.location == "bank" then return "bags", L["your bags"] end
	if w.location ~= "bags" then return nil end
	if self:TradeOpen() then return "trade", L["the trade"] end
	if self:MailOpen() then return "mail", L["the mail"] end
	if Containers:BankOpen() then return "bank", L["the bank"] end
	return nil
end

local function Bound(e)
	local b = Items:Binding(e)
	return b == "soulbound" or b == "quest" or e.quest
end

local function MailUsed()
	local n = 0
	for a = 1, MAIL_MAX do if NBG.Str(NBG.Call(_G.GetSendMailItemLink, a)) then n = n + 1 end end
	return n
end
local function TradeUsed()
	local n = 0
	for a = 1, TRADE_MAX do if NBG.Str(NBG.Call(_G.GetTradePlayerItemLink, a)) then n = n + 1 end end
	return n
end

local function UseFn() return NBG.API("C_Container", "UseContainerItem") or _G.UseContainerItem end

local running
function Transfer:Busy() return running ~= nil end

function Transfer:Run(entries, target)
	if running or NBG:InCombat() then return end
	local use = UseFn()
	if not use then return end
	local list = {}
	for _, e in ipairs(entries or {}) do
		if e.bag and e.slot and e.id and e.live ~= false and not e.ghost and not Marks:IsLocked(e.id)
			and not ((target == "mail" or target == "trade") and Bound(e)) then
			list[#list + 1] = e
		end
	end
	if #list == 0 then NBG:Print(L["Nothing here can be moved there."]) return end
	if target == "mail" and not Visible("SendMailFrame") and _G.MailFrameTab2 and MailFrameTab2.Click then pcall(MailFrameTab2.Click, MailFrameTab2) end
	local room = target == "mail" and (MAIL_MAX - MailUsed()) or target == "trade" and (TRADE_MAX - TradeUsed()) or #list
	running = { moved = 0 }
	NBG:Fire("TRANSFER", true)
	local i = 0
	local function Done(msg)
		local r = running
		running = nil
		NBG:Fire("TRANSFER", false)
		if r and r.moved > 0 then NBG:Print(L["Moved %d stack(s)."], r.moved) end
		if msg then NBG:Print(msg) end
	end
	local function Open()
		if target == "bank" or target == "bags" then return Containers:BankOpen() end
		if target == "mail" then return self:MailOpen() end
		if target == "trade" then return self:TradeOpen() end
		return false
	end
	local function Step()
		if not Open() then return Done() end
		if NBG:InCombat() then return Done(L["Stopped: combat."]) end
		i = i + 1
		if i > #list then return Done() end
		if running.moved >= room then return Done(target == "mail" and L["The mail is full (12 items): send it, then move the rest."] or L["The trade is full."]) end
		local e = list[i]
		local now = Containers:RefreshSlot(e.bag, e.slot) or Containers:Entry(e.bag, e.slot)
		if not (now and now.id == e.id) or now.locked then NBG:After(0.05, Step) return end
		if not pcall(use, e.bag, e.slot) then return Done() end
		-- did it go? (the bank or the bags may be full)
		NBG:After(0.3, function()
			if not running then return end
			local after = Containers:RefreshSlot(e.bag, e.slot)
			if after and after.id == e.id and (after.count or 1) == (e.count or 1) and not after.locked then
				if target == "bank" or target == "bags" then return Done(target == "bank" and L["The bank is full."] or L["Your bags are full."]) end
			else
				running.moved = running.moved + 1
			end
			Step()
		end)
	end
	Step()
end

---------------------------------------------------------------------------------------------
-- send every stack of an item to an alt
---------------------------------------------------------------------------------------------
function Transfer:Alts()
	local out = {}
	local me = NBG:PlayerKey()
	local db = NBG.Store and NBG.Store.db
	local mine = db and db.chars[me]
	for key, c in pairs(db and db.chars or {}) do
		if key ~= me and type(c) == "table" and (not mine or not mine.faction or not c.faction or c.faction == mine.faction) then
			out[#out + 1] = key
		end
	end
	table.sort(out)
	return out
end

local sending
local function Stacks(id)
	local out = {}
	for _, e in ipairs(Containers:All("bags")) do
		if e.id == id and not e.locked and not Marks:IsLocked(e.id) then out[#out + 1] = e end
	end
	return out
end

local function SendFn() return NBG.API("C_Mail", "SendMail") or _G.SendMail end

-- attach the next mail's stacks, then ask
local function NextMail()
	local s = sending
	if not s then return end
	if not Transfer:MailOpen() then sending = nil return end
	local stacks = Stacks(s.id)
	if #stacks == 0 then
		sending = nil
		NBG:Print(L["All sent."])
		return
	end
	if not Visible("SendMailFrame") and _G.MailFrameTab2 and MailFrameTab2.Click then pcall(MailFrameTab2.Click, MailFrameTab2) end
	local use = UseFn()
	local room = MAIL_MAX - MailUsed()
	local i = 0
	local function Attach()
		i = i + 1
		if i <= math.min(room, #stacks) and Transfer:MailOpen() then
			pcall(use, stacks[i].bag, stacks[i].slot)
			NBG:After(0.15, Attach)
			return
		end
		-- the form: who it goes to and a subject; then the player clicks Send
		local box = rawget(_G, "SendMailNameEditBox")
		if box and box.SetText then pcall(box.SetText, box, s.to) end
		local sub = rawget(_G, "SendMailSubjectEditBox")
		if sub and sub.SetText then pcall(sub.SetText, sub, s.name) end
		local left = #stacks - math.min(room, #stacks)
		NBG.Widgets:Popup({
			title = L["Send to an alt"],
			text = (L["Send %d stack(s) of %s to %s?"]):format(math.min(room, #stacks), s.name, s.to) .. (left > 0 and ("\n" .. (L["%d more stack(s) go in the next mail."]):format(left)) or ""),
			width = 420,
			buttons = {
				{ label = L["Send"], style = "gold", onClick = function()
					local send = SendFn()
					if not send then return end
					s.waiting = true
					if not pcall(send, s.to, s.name, "") then s.waiting = nil NBG:Print(L["The mail could not be sent."]) end
				end },
				{ label = L["Cancel"], onClick = function() sending = nil end },
			},
		})
	end
	Attach()
end

function Transfer:SendAll(e, recipient)
	if not (e and e.id and recipient) then return end
	if not self:MailOpen() then NBG:Print(L["Open a mailbox first."]) return end
	if NBG:InCombat() then return end
	local i = Items:Info(e.link)
	if Bound(e) then NBG:Print(L["Soulbound items can't be mailed."]) return end
	sending = { id = e.id, to = recipient, name = i and i.name or L["Items"] }
	NextMail()
end

NBG:On("MAIL_SEND_SUCCESS", function()
	if sending and sending.waiting then
		sending.waiting = nil
		NBG:After(0.5, NextMail)
	end
end)
NBG:On("MAIL_FAILED", function() if sending then sending.waiting = nil end end)
NBG:On("MAIL_CLOSED", function() sending = nil end)
