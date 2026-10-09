--[[ NetherBags - UI/Skin.lua
	The looks, and the switch between them (live, no reload). Every window and tab asks the skin
	for ROLES, never raw colours, so a skin changes all of them at once.

	  netherbags   the default: deep navy, gold trim, Insight cyan (Poppins, Philosopher, Cinzel)
	  netherui     follow NetherUI: its theme colours and fonts, and its own window and panel art
	               (ornate frames, animated theme effects), re-applied on every theme change
	  (plugins)    Skin:Register{ id, label, colors = { role = { r, g, b, a } }, fonts = { kind = path },
	               window = fn(frame) -> true, panel = fn(frame, opts) -> true, onApply = fn() }

	Roles: text, textDim, faint, header, accent, accent2, border, bg, bgTop, bgAlt, inset, row,
	rowHover, rowSel, positive, negative, warning, coinGold, coinSilver, coinCopper, shadow

	  Skin:Current()                     the skin in use (falls back to netherbags)
	  Skin:Color(role)                   r, g, b, a
	  Skin:Paint(obj, role [, opts])     colour a texture / font string by role (kept on change)
	  Skin:Font(fs, kind, size [, flags]) kind: body | medium | bold | title | caps | number
	  Skin:Gradient(tex, orient, roleA, roleB [, alphaA, alphaB])   kept on change
	  Skin:Window(frame)                 the window body (own look, or the skin's / NetherUI's)
	  Skin:Panel(frame [, opts])         an inner panel; opts.inset for a well
	  Skin:Rounded(tex [, edge])         round-cornered texture (slice margins when the client has them)
	  Skin:OnChange(fn)                  after every switch / theme change ]]

local _, ns = ...
local NBG = ns.NBG
local L = ns.L
local Skin = NBG:Module("Skin")
local MEDIA = NBG.MEDIA
local WHITE = "Interface\\Buttons\\WHITE8X8"
Skin.WHITE = WHITE

local type, pairs, ipairs, pcall = type, pairs, ipairs, pcall

local function rgb(r, g, b, a) return { r / 255, g / 255, b / 255, a or 1 } end

Skin.NETHERBAGS = {
	text = rgb(226, 230, 240), textDim = rgb(140, 150, 176), faint = rgb(88, 98, 128),
	header = rgb(250, 222, 150), accent = rgb(232, 196, 120), accentLo = rgb(176, 124, 52), accent2 = rgb(110, 210, 245),
	border = rgb(54, 64, 98), bg = rgb(9, 12, 22, 0.97), bgTop = rgb(22, 28, 50, 0.97), bgAlt = rgb(16, 20, 36, 0.92),
	inset = rgb(5, 7, 14, 0.94), row = rgb(36, 42, 66, 0.55), rowHover = rgb(110, 90, 40, 0.55), rowSel = rgb(110, 90, 40, 0.8),
	positive = rgb(90, 220, 110), negative = rgb(235, 90, 80), warning = rgb(240, 150, 80),
	coinGold = rgb(246, 200, 70), coinSilver = rgb(200, 206, 214), coinCopper = rgb(214, 128, 72), shadow = rgb(0, 0, 0, 0.75),
	special = rgb(110, 210, 245), ink = rgb(34, 22, 6),
}

-- our roles in NetherUI's palette (anything missing falls back to the own look)
local FROM_NUI = { text = "text", textDim = "textDim", header = "header", accent = "accent", accent2 = "gem", border = "border",
	bg = "bg", bgTop = "bgAlt", bgAlt = "bgAlt", inset = "bgInset", row = "bgAlt", rowHover = "accentSoft", rowSel = "accentSoft",
	positive = "positive", negative = "negative", warning = "warning" }

local skins, order = {}, {}

function Skin:Register(def)
	if type(def) ~= "table" or type(def.id) ~= "string" or not def.id:match("^[%w_%-]+$") then return nil, "bad id" end
	if skins[def.id] then return nil, "taken" end
	def.label = type(def.label) == "string" and def.label or def.id
	def.colors = type(def.colors) == "table" and def.colors or {}
	skins[def.id] = def
	order[#order + 1] = def.id
	if self.ready and NBG.Settings:Get("look.skin") == def.id then self:Refresh() end
	return def
end

function Skin:List()
	local out = {}
	for _, id in ipairs(order) do
		local s = skins[id]
		if not s.available or s.available() then out[#out + 1] = { id = id, label = s.label } end
	end
	return out
end

local function NetherUI()
	local A = rawget(_G, "NetherUI")
	if type(A) == "table" and type(A.palette) == "table" and type(A.palette.bg) == "table" then return A end
	return nil
end
Skin.NetherUI = NetherUI

Skin:Register({ id = "netherbags", label = L["NetherBags (default)"], colors = Skin.NETHERBAGS })
Skin:Register({ id = "netherui", label = L["Follow NetherUI's theme"], available = function() return NetherUI() ~= nil end,
	color = function(role)
		local A = NetherUI()
		if not A then return nil end
		local key = FROM_NUI[role]
		local c = key and A.palette[key]
		if type(c) ~= "table" then return nil end
		local a = c[4] or 1
		if role == "row" then a = math.min(a, 0.55) elseif role == "rowHover" or role == "rowSel" then a = math.min(a, 0.7) end
		return c[1] or 1, c[2] or 1, c[3] or 1, a
	end,
	font = function(kind)
		local A = NetherUI()
		if not (A and type(A.fonts) == "table") then return nil end
		if kind == "title" then return A.BRAND_FONT or A.fonts.header end
		if kind == "caps" then return A.fonts.header end
		return A.fonts.body
	end })

function Skin:Current()
	local id = NBG.Settings and NBG.Settings:Get("look.skin") or "netherbags"
	local s = skins[id]
	if s and (not s.available or s.available()) then return s end
	return skins.netherbags
end

-- a role's colour / a font file in a given theme (not the current one): the theme previews
function Skin:ColorOf(id, role)
	local s = skins[id]
	if not s or (s.available and not s.available()) then s = skins.netherbags end
	if type(s.color) == "function" then
		local ok, r, g, b, a = pcall(s.color, role)
		if ok and r then return r, g, b, a or 1 end
	end
	local c = s.colors[role] or self.NETHERBAGS[role] or self.NETHERBAGS.text
	return c[1], c[2], c[3], c[4] or 1
end
function Skin:FontOf(id, kind)
	local s = skins[id]
	if s and type(s.font) == "function" and (not s.available or s.available()) then
		local ok, p = pcall(s.font, kind)
		if ok and type(p) == "string" then return p end
	elseif s and type(s.fonts) == "table" and type(s.fonts[kind]) == "string" then
		return s.fonts[kind]
	end
	local map = { body = "body", medium = "medium", bold = "bold", title = "title", caps = "caps", number = "bold" }
	return NBG.FONTS[map[kind] or "body"] or NBG.FONTS.body
end

function Skin:Color(role)
	local s = self:Current()
	if type(s.color) == "function" then
		local ok, r, g, b, a = pcall(s.color, role)
		if ok and r then return r, g, b, a or 1 end
	end
	local c = s.colors[role] or self.NETHERBAGS[role] or self.NETHERBAGS.text
	return c[1], c[2], c[3], c[4] or 1
end

---------------------------------------------------------------------------------------------
-- painted objects, re-painted on every change
---------------------------------------------------------------------------------------------
local painted = setmetatable({}, { __mode = "k" })
local fonts = setmetatable({}, { __mode = "k" })
local grads = setmetatable({}, { __mode = "k" })
local windows = setmetatable({}, { __mode = "k" })
local listeners = {}

local function Apply(obj, e)
	local r, g, b, a = Skin:Color(e.role)
	if e.alpha then a = a * e.alpha end
	if e.mul then r, g, b = r * e.mul, g * e.mul, b * e.mul end
	local kind = obj.GetObjectType and obj:GetObjectType()
	if kind == "FontString" or kind == "EditBox" then obj:SetTextColor(r, g, b, a)
	elseif obj.SetVertexColor then obj:SetVertexColor(r, g, b, a) end
end

function Skin:Paint(obj, role, opts)
	if not obj then return obj end
	local e = { role = role, alpha = opts and opts.alpha, mul = opts and opts.mul }
	painted[obj] = e
	Apply(obj, e)
	return obj
end
function Skin:Unpaint(obj) painted[obj] = nil end

local FONT_FILES = { body = "body", medium = "medium", bold = "bold", title = "title", caps = "caps", number = "bold" }
local function FontFile(kind)
	local s = Skin:Current()
	if type(s.font) == "function" then
		local ok, p = pcall(s.font, kind)
		if ok and type(p) == "string" then return p end
	elseif type(s.fonts) == "table" and type(s.fonts[kind]) == "string" then
		return s.fonts[kind]
	end
	return NBG.FONTS[FONT_FILES[kind] or "body"] or NBG.FONTS.body
end

local function ApplyFont(fs, f)
	local ok = pcall(fs.SetFont, fs, FontFile(f.kind), f.size, f.flags or "")
	if not ok or (fs.GetFont and not fs:GetFont()) then
		pcall(fs.SetFont, fs, NBG.FONTS.body, f.size, f.flags or "")
		if fs.GetFont and not fs:GetFont() then pcall(fs.SetFont, fs, _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", f.size, f.flags or "") end
	end
	if f.shadow ~= false then
		fs:SetShadowOffset(1, -1)
		fs:SetShadowColor(0, 0, 0, 0.85)
	end
end

-- the game loads a font file the first time something draws with it; text set in that same
-- moment can come out blank. Every font file is drawn once, out of sight, as the addon loads.
do
	-- on screen (something off screen is never drawn), in a corner, at 1% opacity, for a few seconds
	local warm = CreateFrame("Frame", nil, UIParent)
	warm:SetSize(4, 4)
	warm:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
	warm:SetAlpha(0.01)
	warm:SetFrameStrata("BACKGROUND")
	warm:EnableMouse(false)
	for _, path in pairs(NBG.FONTS) do
		local fs = warm:CreateFontString(nil, "OVERLAY")
		if pcall(fs.SetFont, fs, path, 12, "") then fs:SetText("Aa") fs:SetPoint("BOTTOMLEFT") end
	end
	Skin.warm = warm
end

function Skin:Font(fs, kind, size, flags, shadow)
	if not fs then return fs end
	local f = { kind = kind or "body", size = size or 12, flags = flags, shadow = shadow }
	fonts[fs] = f
	ApplyFont(fs, f)
	return fs
end

function Skin:SetFontSize(fs, size)
	local f = fonts[fs]
	if f then f.size = size ApplyFont(fs, f) end
end

-- vertical/horizontal gradient between two roles
local function SetGrad(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
	if tex.SetGradient and _G.CreateColor then
		local ok = pcall(tex.SetGradient, tex, orient, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
		if ok then return end
	end
	if tex.SetGradientAlpha then
		pcall(tex.SetGradientAlpha, tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
		return
	end
	tex:SetVertexColor((r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, (a1 + a2) / 2)
end
Skin.SetGrad = SetGrad

local function ApplyGrad(tex, e)
	local r1, g1, b1, a1 = Skin:Color(e.a)
	local r2, g2, b2, a2 = Skin:Color(e.b)
	-- (VERTICAL gradients run bottom -> top in the game; e.a is the top colour)
	if e.orient == "VERTICAL" then
		SetGrad(tex, "VERTICAL", r2, g2, b2, a2 * (e.alphaB or 1), r1, g1, b1, a1 * (e.alphaA or 1))
	else
		SetGrad(tex, "HORIZONTAL", r1, g1, b1, a1 * (e.alphaA or 1), r2, g2, b2, a2 * (e.alphaB or 1))
	end
end

function Skin:Gradient(tex, orient, roleA, roleB, alphaA, alphaB)
	if not tex then return tex end
	if tex.SetColorTexture then tex:SetColorTexture(1, 1, 1, 1) else tex:SetTexture(WHITE) end
	local e = { orient = orient or "VERTICAL", a = roleA, b = roleB, alphaA = alphaA, alphaB = alphaB }
	grads[tex] = e
	ApplyGrad(tex, e)
	return tex
end

-- round corners (Round.tga, 32 px, 8 px margins) when the client has slice margins
function Skin:Rounded(tex, edge, margin)
	tex:SetTexture(MEDIA .. (edge and "RoundEdge" or "Round"))
	if tex.SetTextureSliceMargins then
		pcall(tex.SetTextureSliceMargins, tex, margin or 8, margin or 8, margin or 8, margin or 8)
		local E = type(_G.Enum) == "table" and _G.Enum.UITextureSliceMode
		if E and tex.SetTextureSliceMode then pcall(tex.SetTextureSliceMode, tex, E.Stretched or 0) end
	end
	return tex
end

---------------------------------------------------------------------------------------------
-- windows and panels
---------------------------------------------------------------------------------------------
local function Kit()
	local A = NetherUI()
	local I = A and A.Integrations
	if not (I and I.Kit and I.Kit.New) then return nil end
	if not Skin.kitRec then
		local ok, rec = pcall(I.Kit.New, I.Kit, "netherbags")
		Skin.kitRec = ok and rec or false
	end
	return Skin.kitRec or nil
end

-- the own window look: shadow, body gradient, gold hairline, corner brackets, title band
local function OwnWindow(frame)
	local own = CreateFrame("Frame", nil, frame)
	own:SetAllPoints()
	own:SetFrameLevel(math.max(0, frame:GetFrameLevel()))
	local sh = own:CreateTexture(nil, "BACKGROUND", nil, -8)
	sh:SetTexture(MEDIA .. "Shadow")
	if sh.SetTextureSliceMargins then pcall(sh.SetTextureSliceMargins, sh, 32, 32, 32, 32) end
	sh:SetPoint("TOPLEFT", -18, 14) sh:SetPoint("BOTTOMRIGHT", 22, -26)
	sh:SetVertexColor(0, 0, 0, 0.85)
	local body = own:CreateTexture(nil, "BACKGROUND", nil, -6)
	body:SetAllPoints()
	Skin:Gradient(body, "VERTICAL", "bgTop", "bg")
	own.body = body
	local band = own:CreateTexture(nil, "BACKGROUND", nil, -5)
	band:SetPoint("TOPLEFT", 2, -2) band:SetPoint("TOPRIGHT", -2, -2) band:SetHeight(40)
	Skin:Gradient(band, "VERTICAL", "bgTop", "bgTop", 0.9, 0)
	local edges = {}
	for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" }, { "TOPLEFT", "BOTTOMLEFT", "v" }, { "TOPRIGHT", "BOTTOMRIGHT", "v" } }) do
		local e = own:CreateTexture(nil, "BORDER")
		e:SetTexture(WHITE)
		e:SetPoint(p[1]) e:SetPoint(p[2])
		if p[3] == "h" then e:SetHeight(1) else e:SetWidth(1) end
		Skin:Paint(e, "accentLo", { alpha = 0.55 })
		edges[i] = e
	end
	local cs = { { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 }, { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 } }
	for _, c in ipairs(cs) do
		local t = own:CreateTexture(nil, "ARTWORK")
		t:SetTexture(MEDIA .. "Corner")
		t:SetSize(18, 18)
		t:SetPoint(c[1], c[1]:find("LEFT") and -1 or 1, c[1]:find("TOP") and 1 or -1)
		t:SetTexCoord(c[2], c[3], c[4], c[5])
		Skin:Paint(t, "accent")
	end
	return own
end

-- frame: the window. NetherUI skin: NetherUI's own window art; plugin skins: their window();
-- otherwise (and as the fallback) the own look.
function Skin:Window(frame)
	local own = OwnWindow(frame)
	local kit
	local rec = Kit()
	if rec then
		kit = CreateFrame("Frame", nil, frame)
		kit:SetAllPoints()
		kit:SetFrameLevel(math.max(0, frame:GetFrameLevel()))
		local A = NetherUI()
		local ok = pcall(rec.Panel, rec, kit, { ornate = true })
		if ok and A.Spectrum and A.Spectrum.Register then pcall(A.Spectrum.Register, A.Spectrum, kit) end
		if not ok then kit = nil end
	end
	local custom = CreateFrame("Frame", nil, frame)
	custom:SetAllPoints()
	custom:SetFrameLevel(math.max(0, frame:GetFrameLevel()))
	windows[frame] = { own = own, kit = kit, custom = custom, built = {} }
	self:ApplyWindow(frame)
	return own
end

function Skin:ApplyWindow(frame)
	local w = windows[frame]
	if not w then return end
	local s = self:Current()
	local useKit = s.id == "netherui" and w.kit ~= nil
	local useCustom = false
	if type(s.window) == "function" then
		if not w.built[s.id] then
			local ok, res = pcall(s.window, w.custom, frame)
			w.built[s.id] = ok and res and true or false
		end
		useCustom = w.built[s.id]
	end
	w.own:SetShown(not useKit and not useCustom)
	if w.kit then w.kit:SetShown(useKit) end
	w.custom:SetShown(useCustom)
	local op = (NBG.Settings:Get("look.opacity") or 96) / 100
	w.own.body:SetAlpha(op)
	if w.kit then w.kit:SetAlpha(math.max(0.3, op)) end
end

-- inner panels (settings sections, menus, popups)
local panels = setmetatable({}, { __mode = "k" })
function Skin:Panel(frame, opts)
	opts = opts or {}
	local own = CreateFrame("Frame", nil, frame)
	own:SetAllPoints()
	own:SetFrameLevel(math.max(0, frame:GetFrameLevel()))
	local fill = own:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	self:Rounded(fill)
	self:Paint(fill, opts.inset and "inset" or "bgAlt")
	local edge = own:CreateTexture(nil, "BORDER")
	edge:SetAllPoints()
	self:Rounded(edge, true)
	self:Paint(edge, opts.edge or "border")
	local kit
	local rec = Kit()
	if rec then
		kit = CreateFrame("Frame", nil, frame)
		kit:SetAllPoints()
		kit:SetFrameLevel(math.max(0, frame:GetFrameLevel()))
		local ok = pcall(rec.Panel, rec, kit, opts.inset and { inset = true, alpha = 0.9 } or { small = true })
		if not ok then kit = nil end
	end
	panels[frame] = { own = own, kit = kit, opts = opts, built = {} }
	self:ApplyPanel(frame)
	return own
end

function Skin:ApplyPanel(frame)
	local p = panels[frame]
	if not p then return end
	local s = self:Current()
	local useKit = s.id == "netherui" and p.kit ~= nil
	local useCustom = false
	if type(s.panel) == "function" then
		if p.built[s.id] == nil then
			local ok, res = pcall(s.panel, frame, p.opts)
			p.built[s.id] = ok and res and true or false
		end
		useCustom = p.built[s.id]
	end
	p.own:SetShown(not useKit and not useCustom)
	if p.kit then p.kit:SetShown(useKit) end
end

function Skin:OnChange(fn) listeners[#listeners + 1] = fn end

function Skin:Refresh()
	for obj, e in pairs(painted) do Apply(obj, e) end
	for fs, f in pairs(fonts) do ApplyFont(fs, f) end
	for tex, e in pairs(grads) do ApplyGrad(tex, e) end
	for frame in pairs(windows) do self:ApplyWindow(frame) end
	for frame in pairs(panels) do self:ApplyPanel(frame) end
	local s = self:Current()
	if type(s.onApply) == "function" then pcall(s.onApply) end
	for _, fn in ipairs(listeners) do NBG:Safe("skin change", fn, s.id) end
	NBG:Fire("SKIN_CHANGED", s.id)
end

NBG:Register("SETTING_CHANGED", function(_, key)
	if key == "look.skin" or key == "look.opacity" or key == "*" then Skin:Refresh() end
end)
NBG:Register("PROFILE_CHANGED", function() Skin:Refresh() end)

-- text set while the game was still loading a font file draws as nothing until it is set again
-- (labels set once - tab names, chips, the mode switch, dialog text - stayed blank): once the
-- fonts are in, every font string is given its font and its text again
function Skin:Redraw()
	for fs, f in pairs(fonts) do
		ApplyFont(fs, f)
		local t = fs.GetText and fs:GetText()
		if t and t ~= "" then fs:SetText("") fs:SetText(t) end
	end
end

NBG:Register("LOGIN", function()
	Skin.ready = true
	NBG:After(0.5, function() Skin:Redraw() end)
	NBG:After(3, function() Skin:Redraw() if Skin.warm then Skin.warm:Hide() end end)
	local A = NetherUI()
	if A and type(A.RegisterCallback) == "function" then
		pcall(A.RegisterCallback, A, "THEME_CHANGED", function()
			if Skin:Current().id == "netherui" then NBG:Debounce("theme", 0.05, function() Skin:Refresh() end) end
		end)
	end
end)

-- a window's first showing can be a font's first use: redraw once, a moment after
local redrawn = {}
NBG:Register("WINDOW_SHOWN", function(_, id)
	if redrawn[id] then return end
	redrawn[id] = true
	NBG:After(0.1, function() Skin:Redraw() end)
end)

-- quality colours for item edges and names (the game's, else the standard ones)
function Skin:Quality(q)
	return NBG.Items:QualityColor(q)
end
