--[[ NetherBags - Core/Serialize.lua
	Profiles leave and enter the game as one line of text a player can copy and paste.

	  Serialize:Encode(value) -> text            plain data only (tables with string/number keys;
	                                             strings, numbers, booleans); nothing else is written
	  Serialize:Decode(text) -> value | nil, why a hand-written reader: no code is ever run, sizes and
	                                             depth are capped, anything malformed is refused
	  Serialize:Pack(value) -> string            "!NBAGS:1:<mode>:<check>:<payload>": compressed by the
	                                             game when it can (C_EncodingUtil), else base64
	  Serialize:Unpack(string) -> value | nil, why

	Text layout: t...e is a table (key then value, repeated); s<len>:<bytes> a string;
	n<number>; a number; T and F the booleans. ]]

local _, ns = ...
local NBG = ns.NBG
local Serialize = NBG:Module("Serialize")

local type, pairs, tostring, tonumber, floor = type, pairs, tostring, tonumber, math.floor
local byte, char, sub, concat, format = string.byte, string.char, string.sub, table.concat, string.format

local MAX_TEXT = 400000
local MAX_DEPTH = 24
local MAX_NODES = 60000

---------------------------------------------------------------------------------------------
-- plain text form
---------------------------------------------------------------------------------------------
local function enc(v, out, depth, seen)
	local t = type(v)
	if t == "string" then
		out[#out + 1] = "s" .. #v .. ":" .. v
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "n0;"
		elseif v == floor(v) and v > -1e15 and v < 1e15 then out[#out + 1] = format("n%d;", v)
		else out[#out + 1] = "n" .. format("%.17g", v) .. ";" end
	elseif t == "boolean" then
		out[#out + 1] = v and "T" or "F"
	elseif t == "table" then
		if depth > MAX_DEPTH or seen[v] then out[#out + 1] = "te" return end
		seen[v] = true
		out[#out + 1] = "t"
		-- keys in a stable order so the same profile always gives the same text
		local keys = {}
		for k, x in pairs(v) do
			local tk, tx = type(k), type(x)
			if (tk == "string" or tk == "number") and (tx == "string" or tx == "number" or tx == "boolean" or tx == "table") then
				keys[#keys + 1] = k
			end
		end
		table.sort(keys, function(a, b)
			local ta, tb = type(a), type(b)
			if ta ~= tb then return ta == "number" end
			return a < b
		end)
		for _, k in ipairs(keys) do
			enc(k, out, depth + 1, seen)
			enc(v[k], out, depth + 1, seen)
		end
		out[#out + 1] = "e"
		seen[v] = nil
	end
end

function Serialize:Encode(value)
	local out = {}
	enc(value, out, 0, {})
	return concat(out)
end

function Serialize:Decode(text)
	if type(text) ~= "string" then return nil, "not text" end
	if #text > MAX_TEXT then return nil, "too long" end
	local pos, nodes = 1, 0
	local read
	local function fail(why) error({ why = why }, 0) end
	read = function(depth)
		nodes = nodes + 1
		if nodes > MAX_NODES then fail("too many entries") end
		if depth > MAX_DEPTH + 2 then fail("nested too deeply") end
		local c = sub(text, pos, pos)
		if c == "s" then
			local colon = text:find(":", pos + 1, true)
			if not colon then fail("broken string") end
			local n = tonumber(sub(text, pos + 1, colon - 1))
			if not n or n < 0 or n ~= floor(n) then fail("broken string length") end
			local s = sub(text, colon + 1, colon + n)
			if #s ~= n then fail("string runs past the end") end
			pos = colon + n + 1
			return s
		elseif c == "n" then
			local semi = text:find(";", pos + 1, true)
			if not semi then fail("broken number") end
			local n = tonumber(sub(text, pos + 1, semi - 1))
			if not n or n ~= n then fail("broken number") end
			pos = semi + 1
			return n
		elseif c == "T" then pos = pos + 1 return true
		elseif c == "F" then pos = pos + 1 return false
		elseif c == "t" then
			pos = pos + 1
			local t = {}
			while true do
				local nc = sub(text, pos, pos)
				if nc == "e" then pos = pos + 1 return t end
				if nc == "" then fail("table never closed") end
				local k = read(depth + 1)
				if type(k) ~= "string" and type(k) ~= "number" then fail("bad key") end
				t[k] = read(depth + 1)
			end
		end
		fail("unexpected '" .. c .. "'")
	end
	local ok, res = pcall(read, 0)
	if not ok then return nil, type(res) == "table" and res.why or "unreadable" end
	if pos <= #text then return nil, "extra text at the end" end
	return res
end

---------------------------------------------------------------------------------------------
-- base64 (arithmetic only: no bit library needed)
---------------------------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64I = {}
for i = 1, 64 do B64I[byte(B64, i)] = i - 1 end

function Serialize.ToBase64(s)
	local out = {}
	for i = 1, #s, 3 do
		local a, b, c = byte(s, i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1 = floor(n / 262144) % 64
		local c2 = floor(n / 4096) % 64
		local c3 = floor(n / 64) % 64
		local c4 = n % 64
		out[#out + 1] = sub(B64, c1 + 1, c1 + 1) .. sub(B64, c2 + 1, c2 + 1)
			.. (b and sub(B64, c3 + 1, c3 + 1) or "=") .. (c and sub(B64, c4 + 1, c4 + 1) or "=")
	end
	return concat(out)
end

function Serialize.FromBase64(s)
	s = s:gsub("[^%w%+/=]", "")
	if #s % 4 ~= 0 then return nil end
	local out = {}
	for i = 1, #s, 4 do
		local q = { byte(s, i, i + 3) }
		local v = {}
		for j = 1, 4 do
			if q[j] == 61 then v[j] = nil else v[j] = B64I[q[j]] if v[j] == nil then return nil end end
		end
		if not (v[1] and v[2]) then return nil end
		local n = v[1] * 262144 + v[2] * 4096 + (v[3] or 0) * 64 + (v[4] or 0)
		out[#out + 1] = char(floor(n / 65536) % 256)
		if v[3] then out[#out + 1] = char(floor(n / 256) % 256) end
		if v[4] then out[#out + 1] = char(n % 256) end
	end
	return concat(out)
end

-- a short check of the text (Adler-32), so a broken paste is caught before it is read
function Serialize.Check(s)
	local a, b = 1, 0
	for i = 1, #s do
		a = (a + byte(s, i)) % 65521
		b = (b + a) % 65521
	end
	return format("%08x", b * 65536 + a)
end

---------------------------------------------------------------------------------------------
-- the shareable string
---------------------------------------------------------------------------------------------
local function Compressor()
	local C = rawget(_G, "C_EncodingUtil")
	if type(C) ~= "table" then return nil end
	if type(C.CompressString) ~= "function" or type(C.DecompressString) ~= "function"
		or type(C.EncodeBase64) ~= "function" or type(C.DecodeBase64) ~= "function" then return nil end
	return C
end

function Serialize:Pack(value)
	local text = self:Encode(value)
	local check = self.Check(text)
	local C = Compressor()
	if C then
		local ok, z = pcall(C.CompressString, text)
		if ok and type(z) == "string" then
			local ok2, b = pcall(C.EncodeBase64, z)
			if ok2 and type(b) == "string" then
				return "!NBAGS:" .. NBG.EXPORT_VERSION .. ":z:" .. check .. ":" .. b
			end
		end
	end
	return "!NBAGS:" .. NBG.EXPORT_VERSION .. ":b:" .. check .. ":" .. self.ToBase64(text)
end

function Serialize:Unpack(str)
	if type(str) ~= "string" then return nil, "nothing pasted" end
	str = str:gsub("^%s+", ""):gsub("%s+$", "")
	local ver, mode, check, payload = str:match("^!NBAGS:(%d+):(%a):(%x+):(.+)$")
	if not ver then return nil, "this is not a NetherBags profile string" end
	if tonumber(ver) > NBG.EXPORT_VERSION then return nil, "made by a newer NetherBags: update first" end
	payload = payload:gsub("%s+", "")
	local text
	if mode == "z" then
		local C = Compressor()
		if not C then return nil, "this game client cannot unpack compressed profiles" end
		local ok, z = pcall(C.DecodeBase64, payload)
		if not ok or type(z) ~= "string" then return nil, "the text is damaged" end
		local ok2, t = pcall(C.DecompressString, z)
		if not ok2 or type(t) ~= "string" then return nil, "the text is damaged" end
		text = t
	elseif mode == "b" then
		text = self.FromBase64(payload)
		if not text then return nil, "the text is damaged" end
	else
		return nil, "unknown packing"
	end
	if self.Check(text) ~= check:lower() then return nil, "the text is incomplete or changed (copy all of it)" end
	return self:Decode(text)
end
