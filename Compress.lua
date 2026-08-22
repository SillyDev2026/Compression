--!native
--!optimize 2

local Compression = {}

export type Mode = "Binary" | "BinaryWithHash"

export type Options = {
	Mode: Mode?,
	CompressStrings: boolean?,
	StringMinLength: number?,
	VerifyHash: boolean?,
	SchemaVersion: number?,
	UseStringDictionary: boolean?,
	DictionaryMinUses: number?,
}

export type Descriptor = {
	Kind: string,
	Optional: boolean?,
	Options: {[string]: any}?,
	Item: Descriptor?,
	Fields: {[string]: Descriptor}?,
}

export type Packet = {
	Data: buffer,
	Hash: number?,
	Bytes: number,
	Bits: number,
	SchemaVersion: number?,
}

export type BitLayoutField = {
	Name: string,
	Type: string,
	Present: boolean,
	UsefulBits: number,
	PaddingBits: number,
	PhysicalBits: number,
	RawBits: number,
	SavedBits: number,
	SavingsPercent: number,
}

export type BitLayout = {
	HeaderBits: number,
	UsefulBits: number,
	PaddingBits: number,
	PhysicalBits: number,
	PhysicalBytes: number,
	RawBits: number,
	SavedBits: number,
	SavingsPercent: number,
	Fields: {BitLayoutField},
}

type Writer = {
	Buffer: buffer,
	Position: number,
	BitBuffer: number,
	BitCount: number,
	UsedBits: number,
	PaddingBits: number,
}

type Reader = {
	Buffer: buffer,
	Position: number,
	Length: number,
	BitBuffer: number,
	BitCount: number,
}

type Field = {
	Name: string,
	Descriptor: Descriptor,
}

type DictionaryState = {
	Encode: {[string]: number},
	Decode: {string},
}

type SchemaObject = {
	Fields: {Field},
	Version: number,
	Encode: (self: SchemaObject, value: {[string]: any}, options: Options?) -> Packet,
	Decode: (self: SchemaObject, packet: Packet | buffer, options: Options?) -> {[string]: any},
	EncodeDelta: (self: SchemaObject, previous: {[string]: any}, current: {[string]: any}, options: Options?) -> Packet,
	DecodeDelta: (self: SchemaObject, previous: {[string]: any}, packet: Packet | buffer, options: Options?) -> {[string]: any},
	AnalyzeBits: (self: SchemaObject, value: {[string]: any}) -> BitLayout,
	PrintBitLayout: (self: SchemaObject, value: {[string]: any}) -> BitLayout,
}

local MAGIC_A = 0x43
local MAGIC_B = 0x50
local VERSION = 6

local MODE_DYNAMIC = 1
local MODE_SCHEMA = 2
local MODE_DELTA = 3

local TAG_NIL = 0
local TAG_FALSE = 1
local TAG_TRUE = 2
local TAG_UINT = 3
local TAG_INT = 4
local TAG_FLOAT = 5
local TAG_STRING = 6
local TAG_STRING_REF = 7
local TAG_ARRAY = 8
local TAG_MAP = 9
local TAG_VECTOR2 = 10
local TAG_VECTOR3 = 11
local TAG_COLOR3 = 12
local TAG_CFRAME = 13

local DEFAULT_CAPACITY = 256

local function fail(message: string, level: number?)
	error("Compression: " .. message, (level or 1) + 1)
end

local function newWriter(capacity: number?): Writer
	return {
		Buffer = buffer.create(capacity or DEFAULT_CAPACITY),
		Position = 0,
		BitBuffer = 0,
		BitCount = 0,
		UsedBits = 0,
		PaddingBits = 0,
	}
end

local function newReader(data: buffer): Reader
	return {
		Buffer = data,
		Position = 0,
		Length = buffer.len(data),
		BitBuffer = 0,
		BitCount = 0,
	}
end

local function ensureCapacity(w: Writer, additional: number)
	local needed = w.Position + additional
	if needed <= buffer.len(w.Buffer) then return end
	local old = w.Buffer
	local newLength = math.max(needed, math.max(16, buffer.len(old) * 2))
	local nextBuffer = buffer.create(newLength)
	buffer.copy(nextBuffer, 0, old, 0, w.Position)
	w.Buffer = nextBuffer
end

local function writeByteRaw(w: Writer, value: number)
	ensureCapacity(w, 1)
	buffer.writeu8(w.Buffer, w.Position, value % 256)
	w.Position += 1
end

local function writeByte(w: Writer, value: number)
	writeByteRaw(w, value)
	w.UsedBits += 8
end

local function readByte(r: Reader): number
	if r.Position >= r.Length then fail("unexpected end of payload", 2) end
	local value = buffer.readu8(r.Buffer, r.Position)
	r.Position += 1
	return value
end

local function flushBits(w: Writer)
	if w.BitCount > 0 then
		w.PaddingBits += 8 - w.BitCount
		writeByteRaw(w, w.BitBuffer)
		w.BitBuffer = 0
		w.BitCount = 0
	end
end

local function alignReader(r: Reader)
	r.BitBuffer = 0
	r.BitCount = 0
end

local function writeBits(w: Writer, value: number, count: number)
	w.UsedBits += count
	local remaining = count
	local current = value
	while remaining > 0 do
		local free = 8 - w.BitCount
		local take = math.min(free, remaining)
		local base = 2 ^ take
		local chunk = current % base
		w.BitBuffer += chunk * 2 ^ w.BitCount
		w.BitCount += take
		current = math.floor(current / base)
		remaining -= take
		if w.BitCount == 8 then
			writeByteRaw(w, w.BitBuffer)
			w.BitBuffer = 0
			w.BitCount = 0
		end
	end
end

local function readBits(r: Reader, count: number): number
	local result = 0
	local multiplier = 1
	local remaining = count
	while remaining > 0 do
		if r.BitCount == 0 then
			r.BitBuffer = readByte(r)
			r.BitCount = 8
		end
		local take = math.min(r.BitCount, remaining)
		local base = 2 ^ take
		local chunk = r.BitBuffer % base
		result += chunk * multiplier
		r.BitBuffer = math.floor(r.BitBuffer / base)
		r.BitCount -= take
		remaining -= take
		multiplier *= base
	end
	return result
end

local function writeVarUInt(w: Writer, value: number)
	if value < 0 or value % 1 ~= 0 then fail("expected unsigned integer", 2) end
	flushBits(w)
	repeat
		local byte = value % 128
		value = math.floor(value / 128)
		if value > 0 then byte += 128 end
		writeByte(w, byte)
	until value == 0
end

local function readVarUInt(r: Reader): number
	alignReader(r)
	local result = 0
	local multiplier = 1
	for _ = 1, 10 do
		local byte = readByte(r)
		result += (byte % 128) * multiplier
		if byte < 128 then return result end
		multiplier *= 128
	end
	fail("invalid VarUInt", 2)
	return 0
end

local function zigzagEncode(value: number): number
	if value >= 0 then return value * 2 end
	return -value * 2 - 1
end

local function zigzagDecode(value: number): number
	if value % 2 == 0 then return value / 2 end
	return -(value + 1) / 2
end

local function writeVarInt(w: Writer, value: number)
	writeVarUInt(w, zigzagEncode(value))
end

local function readVarInt(r: Reader): number
	return zigzagDecode(readVarUInt(r))
end

local function writeF64(w: Writer, value: number)
	flushBits(w)
	ensureCapacity(w, 8)
	buffer.writef64(w.Buffer, w.Position, value)
	w.Position += 8
	w.UsedBits += 64
end

local function readF64(r: Reader): number
	alignReader(r)
	if r.Position + 8 > r.Length then fail("truncated float", 2) end
	local value = buffer.readf64(r.Buffer, r.Position)
	r.Position += 8
	return value
end

local function writeStringRaw(w: Writer, value: string)
	flushBits(w)
	writeVarUInt(w, #value)
	ensureCapacity(w, #value)
	buffer.writestring(w.Buffer, w.Position, value)
	w.Position += #value
	w.UsedBits += #value * 8
end

local function readStringRaw(r: Reader): string
	alignReader(r)
	local length = readVarUInt(r)
	if r.Position + length > r.Length then fail("truncated string", 2) end
	local value = buffer.readstring(r.Buffer, r.Position, length)
	r.Position += length
	return value
end

local function finish(w: Writer): buffer
	flushBits(w)
	local result = buffer.create(w.Position)
	buffer.copy(result, 0, w.Buffer, 0, w.Position)
	return result
end

local function hashBuffer(data: buffer): number
	local hash = 2166136261
	for i = 0, buffer.len(data) - 1 do
		hash = bit32.bxor(hash, buffer.readu8(data, i))
		hash = (hash * 16777619) % 4294967296
	end
	return hash
end

local function isInteger(value: number): boolean
	return value % 1 == 0
end

local function isArray(value: {[any]: any}): boolean
	local n = #value
	for key in pairs(value) do
		if typeof(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > n then return false end
	end
	return true
end

local function deepEqual(a: any, b: any): boolean
	if a == b then return true end
	if typeof(a) ~= typeof(b) then return false end
	if typeof(a) ~= "table" then return false end
	for key, value in pairs(a) do if not deepEqual(value, b[key]) then return false end end
	for key, value in pairs(b) do if not deepEqual(value, a[key]) then return false end end
	return true
end

local function collectStrings(value: any, counts: {[string]: number})
	local kind = typeof(value)
	if kind == "string" then
		counts[value] = (counts[value] or 0) + 1
	elseif kind == "table" then
		for key, child in pairs(value) do
			collectStrings(key, counts)
			collectStrings(child, counts)
		end
	end
end

local function makeDictionary(value: any, options: Options?): DictionaryState
	local state: DictionaryState = {Encode = {}, Decode = {}}
	if options and options.UseStringDictionary == false then return state end
	local counts = {}
	collectStrings(value, counts)
	local minUses = options and options.DictionaryMinUses or 2
	local candidates = {}
	for stringValue, count in pairs(counts) do
		if count >= minUses and #stringValue >= 3 then
			candidates[#candidates + 1] = {Value = stringValue, Count = count}
		end
	end
	table.sort(candidates, function(a, b)
		if a.Count == b.Count then return a.Value < b.Value end
		return a.Count > b.Count
	end)
	for i = 1, math.min(255, #candidates) do
		local valueString = candidates[i].Value
		state.Encode[valueString] = i
		state.Decode[i] = valueString
	end
	return state
end

local function findStringMatch(value: string, position: number): (number, number)
	local bestDistance = 0
	local bestLength = 0
	local start = math.max(1, position - 4095)
	local maxLength = math.min(18, #value - position + 1)
	if maxLength < 3 then return 0, 0 end
	for candidate = position - 1, start, -1 do
		local distance = position - candidate
		local length = 0
		while length < maxLength do
			local source = candidate + (length % distance)
			if string.byte(value, source) ~= string.byte(value, position + length) then break end
			length += 1
		end
		if length > bestLength and length >= 3 then
			bestLength = length
			bestDistance = distance
			if length == maxLength then break end
		end
	end
	return bestDistance, bestLength
end

function Compression.CompressString(value: string, options: Options?): buffer
	if typeof(value) ~= "string" then fail("CompressString expects string", 2) end
	local minLength = options and options.StringMinLength or 24
	local w = newWriter(math.max(32, #value))
	if #value < minLength then
		writeByte(w, 0)
		writeStringRaw(w, value)
		return finish(w)
	end
	local body = newWriter(math.max(32, #value))
	local position = 1
	while position <= #value do
		local distance, length = findStringMatch(value, position)
		if length >= 3 then
			writeByte(body, 1)
			local packed = (distance - 1) * 16 + (length - 3)
			writeByte(body, math.floor(packed / 256))
			writeByte(body, packed % 256)
			position += length
		else
			local start = position
			local count = 1
			position += 1
			while position <= #value and count < 255 do
				local _, nextLength = findStringMatch(value, position)
				if nextLength >= 3 then break end
				count += 1
				position += 1
			end
			writeByte(body, 0)
			writeByte(body, count)
			for i = start, start + count - 1 do writeByte(body, string.byte(value, i)) end
		end
	end
	local compressed = finish(body)
	if buffer.len(compressed) >= #value then
		writeByte(w, 0)
		writeStringRaw(w, value)
	else
		writeByte(w, 1)
		writeVarUInt(w, #value)
		writeVarUInt(w, buffer.len(compressed))
		ensureCapacity(w, buffer.len(compressed))
		buffer.copy(w.Buffer, w.Position, compressed, 0, buffer.len(compressed))
		w.Position += buffer.len(compressed)
		w.UsedBits += buffer.len(compressed) * 8
	end
	return finish(w)
end

function Compression.DecompressString(data: buffer): string
	if typeof(data) ~= "buffer" then fail("DecompressString expects buffer", 2) end
	local r = newReader(data)
	local mode = readByte(r)
	if mode == 0 then return readStringRaw(r) end
	if mode ~= 1 then fail("invalid compressed string mode", 2) end
	local originalLength = readVarUInt(r)
	local compressedLength = readVarUInt(r)
	if r.Position + compressedLength > r.Length then fail("truncated compressed string", 2) end
	local output = table.create(originalLength)
	while r.Position < r.Length and #output < originalLength do
		local token = readByte(r)
		if token == 0 then
			local count = readByte(r)
			for _ = 1, count do output[#output + 1] = string.char(readByte(r)) end
		elseif token == 1 then
			local packed = readByte(r) * 256 + readByte(r)
			local distance = math.floor(packed / 16) + 1
			local length = packed % 16 + 3
			if distance > #output then fail("invalid back-reference", 2) end
			for _ = 1, length do
				local index = #output - distance + 1
				output[#output + 1] = output[index]
			end
		else
			fail("invalid compressed string token", 2)
		end
	end
	local result = table.concat(output)
	if #result ~= originalLength then fail("decompressed string length mismatch", 2) end
	return result
end

local function quantize(value: number, minimum: number, maximum: number, bits: number): number
	local levels = 2 ^ bits - 1
	local alpha = math.clamp((value - minimum) / (maximum - minimum), 0, 1)
	return math.floor(alpha * levels + 0.5)
end

local function dequantize(value: number, minimum: number, maximum: number, bits: number): number
	return minimum + (value / (2 ^ bits - 1)) * (maximum - minimum)
end

local function validate(descriptor: Descriptor, value: any, path: string)
	if value == nil then
		if descriptor.Optional then return end
		fail(path .. " is required", 3)
	end
	local kind = descriptor.Kind
	local actual = typeof(value)
	if kind == "Bool" and actual ~= "boolean" then fail(path .. " expected boolean", 3)
	elseif kind == "UInt" and (actual ~= "number" or value < 0 or not isInteger(value)) then fail(path .. " expected unsigned integer", 3)
	elseif kind == "Int" and (actual ~= "number" or not isInteger(value)) then fail(path .. " expected integer", 3)
	elseif (kind == "Float" or kind == "Quantized") and actual ~= "number" then fail(path .. " expected number", 3)
	elseif (kind == "String" or kind == "CompressedString") and actual ~= "string" then fail(path .. " expected string", 3)
	elseif kind == "Vector2" and actual ~= "Vector2" then fail(path .. " expected Vector2", 3)
	elseif (kind == "Vector3" or kind == "QuantizedVector3") and actual ~= "Vector3" then fail(path .. " expected Vector3", 3)
	elseif kind == "Color3" and actual ~= "Color3" then fail(path .. " expected Color3", 3)
	elseif kind == "Array" then
		if actual ~= "table" or not isArray(value) then fail(path .. " expected array", 3) end
		for i, item in ipairs(value) do validate(descriptor.Item :: Descriptor, item, path .. "[" .. tostring(i) .. "]") end
	elseif kind == "Object" then
		if actual ~= "table" then fail(path .. " expected table", 3) end
		for name, child in pairs(descriptor.Fields :: {[string]: Descriptor}) do validate(child, value[name], path .. "." .. name) end
	end
end

local function writeDescriptor(w: Writer, descriptor: Descriptor, value: any)
	local kind = descriptor.Kind
	local o = descriptor.Options
	if kind == "Bool" then writeBits(w, value and 1 or 0, 1)
	elseif kind == "UInt" then writeVarUInt(w, value)
	elseif kind == "Int" then writeVarInt(w, value)
	elseif kind == "Float" then writeF64(w, value)
	elseif kind == "String" then writeStringRaw(w, value)
	elseif kind == "CompressedString" then
		local compressed = Compression.CompressString(value, o)
		writeVarUInt(w, buffer.len(compressed))
		flushBits(w)
		ensureCapacity(w, buffer.len(compressed))
		buffer.copy(w.Buffer, w.Position, compressed, 0, buffer.len(compressed))
		w.Position += buffer.len(compressed)
		w.UsedBits += buffer.len(compressed) * 8
	elseif kind == "Vector2" then writeF64(w, value.X); writeF64(w, value.Y)
	elseif kind == "Vector3" then writeF64(w, value.X); writeF64(w, value.Y); writeF64(w, value.Z)
	elseif kind == "Color3" then
		flushBits(w)
		writeByte(w, math.floor(value.R * 255 + 0.5))
		writeByte(w, math.floor(value.G * 255 + 0.5))
		writeByte(w, math.floor(value.B * 255 + 0.5))
	elseif kind == "Quantized" then writeBits(w, quantize(value, o.Minimum, o.Maximum, o.Bits), o.Bits)
	elseif kind == "QuantizedVector3" then
		writeBits(w, quantize(value.X, o.Minimum.X, o.Maximum.X, o.Bits), o.Bits)
		writeBits(w, quantize(value.Y, o.Minimum.Y, o.Maximum.Y, o.Bits), o.Bits)
		writeBits(w, quantize(value.Z, o.Minimum.Z, o.Maximum.Z, o.Bits), o.Bits)
	elseif kind == "Array" then
		writeVarUInt(w, #value)
		for _, item in ipairs(value) do writeDescriptor(w, descriptor.Item :: Descriptor, item) end
	elseif kind == "Object" then
		local names = {}
		for name in pairs(descriptor.Fields :: {[string]: Descriptor}) do names[#names + 1] = name end
		table.sort(names)
		for _, name in ipairs(names) do
			local child = (descriptor.Fields :: {[string]: Descriptor})[name]
			local present = value[name] ~= nil
			if child.Optional then writeBits(w, present and 1 or 0, 1) end
			if present then writeDescriptor(w, child, value[name]) end
		end
	end
end

local function readDescriptor(r: Reader, descriptor: Descriptor): any
	local kind = descriptor.Kind
	local o = descriptor.Options
	if kind == "Bool" then return readBits(r, 1) == 1
	elseif kind == "UInt" then return readVarUInt(r)
	elseif kind == "Int" then return readVarInt(r)
	elseif kind == "Float" then return readF64(r)
	elseif kind == "String" then return readStringRaw(r)
	elseif kind == "CompressedString" then
		local length = readVarUInt(r)
		alignReader(r)
		if r.Position + length > r.Length then fail("truncated compressed string", 2) end
		local slice = buffer.create(length)
		buffer.copy(slice, 0, r.Buffer, r.Position, length)
		r.Position += length
		return Compression.DecompressString(slice)
	elseif kind == "Vector2" then return Vector2.new(readF64(r), readF64(r))
	elseif kind == "Vector3" then return Vector3.new(readF64(r), readF64(r), readF64(r))
	elseif kind == "Color3" then alignReader(r); return Color3.fromRGB(readByte(r), readByte(r), readByte(r))
	elseif kind == "Quantized" then return dequantize(readBits(r, o.Bits), o.Minimum, o.Maximum, o.Bits)
	elseif kind == "QuantizedVector3" then
		return Vector3.new(
			dequantize(readBits(r, o.Bits), o.Minimum.X, o.Maximum.X, o.Bits),
			dequantize(readBits(r, o.Bits), o.Minimum.Y, o.Maximum.Y, o.Bits),
			dequantize(readBits(r, o.Bits), o.Minimum.Z, o.Maximum.Z, o.Bits)
		)
	elseif kind == "Array" then
		local count = readVarUInt(r)
		local result = table.create(count)
		for i = 1, count do result[i] = readDescriptor(r, descriptor.Item :: Descriptor) end
		return result
	elseif kind == "Object" then
		local result = {}
		local names = {}
		for name in pairs(descriptor.Fields :: {[string]: Descriptor}) do names[#names + 1] = name end
		table.sort(names)
		for _, name in ipairs(names) do
			local child = (descriptor.Fields :: {[string]: Descriptor})[name]
			local present = true
			if child.Optional then present = readBits(r, 1) == 1 end
			if present then result[name] = readDescriptor(r, child) end
		end
		return result
	end
	fail("unsupported descriptor " .. kind, 2)
	return nil
end

local function writeHeader(w: Writer, mode: number, schemaVersion: number?)
	writeByte(w, MAGIC_A)
	writeByte(w, MAGIC_B)
	writeByte(w, VERSION)
	writeByte(w, mode)
	writeVarUInt(w, schemaVersion or 1)
end

local function readHeader(r: Reader, expectedMode: number): number
	if readByte(r) ~= MAGIC_A or readByte(r) ~= MAGIC_B then fail("invalid binary header", 2) end
	if readByte(r) ~= VERSION then fail("unsupported binary version", 2) end
	if readByte(r) ~= expectedMode then fail("unexpected binary mode", 2) end
	return readVarUInt(r)
end

local function packetFromBuffer(data: buffer, options: Options?, schemaVersion: number?): Packet
	local mode = options and options.Mode or "Binary"
	local hash = nil
	if mode == "BinaryWithHash" then hash = hashBuffer(data) end
	return {Data = data, Hash = hash, Bytes = buffer.len(data), Bits = buffer.len(data) * 8, SchemaVersion = schemaVersion}
end

local function unwrapPacket(packet: Packet | buffer, options: Options?): (buffer, number?)
	if typeof(packet) == "buffer" then return packet, nil end
	if typeof(packet) ~= "table" or typeof((packet :: any).Data) ~= "buffer" then fail("expected Packet or buffer", 2) end
	local object = packet :: Packet
	if object.Hash ~= nil and (not options or options.VerifyHash ~= false) then
		if hashBuffer(object.Data) ~= object.Hash then fail("hash verification failed", 2) end
	end
	return object.Data, object.SchemaVersion
end

local function rawValueBits(value: any): number
	local kind = typeof(value)
	if kind == "boolean" then return 8
	elseif kind == "number" then return 64
	elseif kind == "string" then return #value * 8
	elseif kind == "Vector2" then return 128
	elseif kind == "Vector3" then return 192
	elseif kind == "Color3" then return 96
	elseif kind == "CFrame" then return 768
	elseif kind == "table" then
		local bits = 0
		for key, child in pairs(value) do bits += rawValueBits(key); bits += rawValueBits(child) end
		return bits
	end
	return 0
end

local Schema = {}
Schema.__index = Schema

function Compression.Schema(definition: {[string]: Descriptor}, version: number?): SchemaObject
	if typeof(definition) ~= "table" then fail("Schema expects descriptor table", 2) end
	local fields = {}
	for name, descriptor in pairs(definition) do
		if typeof(name) ~= "string" then fail("schema field names must be strings", 2) end
		if typeof(descriptor) ~= "table" or typeof(descriptor.Kind) ~= "string" then fail("invalid descriptor for field " .. name, 2) end
		fields[#fields + 1] = {Name = name, Descriptor = descriptor}
	end
	table.sort(fields, function(a, b) return a.Name < b.Name end)
	return setmetatable({Fields = fields, Version = version or 1}, Schema) :: any
end

function Schema:Encode(value: {[string]: any}, options: Options?): Packet
	local w = newWriter()
	writeHeader(w, MODE_SCHEMA, self.Version)
	for _, field in ipairs(self.Fields) do
		local descriptor = field.Descriptor
		local fieldValue = value[field.Name]
		local present = fieldValue ~= nil
		if descriptor.Optional then writeBits(w, present and 1 or 0, 1)
		elseif not present then fail("missing required field " .. field.Name, 2) end
		if present then validate(descriptor, fieldValue, field.Name); writeDescriptor(w, descriptor, fieldValue) end
	end
	return packetFromBuffer(finish(w), options, self.Version)
end

function Schema:Decode(packet: Packet | buffer, options: Options?): {[string]: any}
	local data, packetVersion = unwrapPacket(packet, options)
	local r = newReader(data)
	local encodedVersion = readHeader(r, MODE_SCHEMA)
	if packetVersion ~= nil and packetVersion ~= encodedVersion then fail("packet/schema version mismatch", 2) end
	if encodedVersion ~= self.Version then fail("schema version mismatch", 2) end
	local result = {}
	for _, field in ipairs(self.Fields) do
		local descriptor = field.Descriptor
		local present = true
		if descriptor.Optional then present = readBits(r, 1) == 1 end
		if present then result[field.Name] = readDescriptor(r, descriptor) end
	end
	return result
end

function Schema:EncodeDelta(previous: {[string]: any}, current: {[string]: any}, options: Options?): Packet
	local w = newWriter()
	writeHeader(w, MODE_DELTA, self.Version)
	for _, field in ipairs(self.Fields) do writeBits(w, deepEqual(previous[field.Name], current[field.Name]) and 0 or 1, 1) end
	for _, field in ipairs(self.Fields) do
		if not deepEqual(previous[field.Name], current[field.Name]) then
			local value = current[field.Name]
			writeBits(w, value ~= nil and 1 or 0, 1)
			if value ~= nil then validate(field.Descriptor, value, field.Name); writeDescriptor(w, field.Descriptor, value) end
		end
	end
	return packetFromBuffer(finish(w), options, self.Version)
end

function Schema:DecodeDelta(previous: {[string]: any}, packet: Packet | buffer, options: Options?): {[string]: any}
	local data = unwrapPacket(packet, options)
	local r = newReader(data)
	local version = readHeader(r, MODE_DELTA)
	if version ~= self.Version then fail("schema version mismatch", 2) end
	local changed = table.create(#self.Fields)
	for i = 1, #self.Fields do changed[i] = readBits(r, 1) == 1 end
	local result = table.clone(previous)
	for i, field in ipairs(self.Fields) do
		if changed[i] then
			local present = readBits(r, 1) == 1
			if present then result[field.Name] = readDescriptor(r, field.Descriptor) else result[field.Name] = nil end
		end
	end
	return result
end

function Schema:AnalyzeBits(value: {[string]: any}): BitLayout
	local w = newWriter()
	local fields = {}
	local rawBits = 0
	writeHeader(w, MODE_SCHEMA, self.Version)
	local headerBits = w.UsedBits
	for _, field in ipairs(self.Fields) do
		local descriptor = field.Descriptor
		local fieldValue = value[field.Name]
		local present = fieldValue ~= nil
		local usedBefore = w.UsedBits
		local paddingBefore = w.PaddingBits
		if descriptor.Optional then writeBits(w, present and 1 or 0, 1)
		elseif not present then fail("missing required field " .. field.Name, 2) end
		if present then validate(descriptor, fieldValue, field.Name); writeDescriptor(w, descriptor, fieldValue) end
		local useful = w.UsedBits - usedBefore
		local padding = w.PaddingBits - paddingBefore
		local raw = present and rawValueBits(fieldValue) or 0
		local physical = useful + padding
		local saved = raw - physical
		rawBits += raw
		fields[#fields + 1] = {
			Name = field.Name, Type = descriptor.Kind, Present = present,
			UsefulBits = useful, PaddingBits = padding, PhysicalBits = physical,
			RawBits = raw, SavedBits = saved,
			SavingsPercent = raw > 0 and (saved / raw) * 100 or 0,
		}
	end
	local data = finish(w)
	local physicalBits = buffer.len(data) * 8
	local savedBits = rawBits - physicalBits
	return {
		HeaderBits = headerBits, UsefulBits = w.UsedBits, PaddingBits = w.PaddingBits,
		PhysicalBits = physicalBits, PhysicalBytes = buffer.len(data), RawBits = rawBits,
		SavedBits = savedBits, SavingsPercent = rawBits > 0 and (savedBits / rawBits) * 100 or 0,
		Fields = fields,
	}
end

function Schema:PrintBitLayout(value: {[string]: any}): BitLayout
	local layout = self:AnalyzeBits(value)
	print("========== Compression v1.5.5 Bit Layout ==========")
	print("Header bits:", layout.HeaderBits)
	for _, field in ipairs(layout.Fields) do
		print(string.format(
			"%s [%s] | useful=%d bits | padding=%d | physical=%d | raw=%d | saved=%.2f%%",
			field.Name, field.Type, field.UsefulBits, field.PaddingBits, field.PhysicalBits, field.RawBits, field.SavingsPercent
			))
	end
	print("---------------------------------------------------")
	print("Useful bits:", layout.UsefulBits)
	print("Padding bits:", layout.PaddingBits)
	print("Physical:", layout.PhysicalBits, "bits /", layout.PhysicalBytes, "bytes")
	print("Raw:", layout.RawBits, "bits")
	print("Saved:", layout.SavedBits, "bits")
	print(string.format("Savings: %.2f%%", layout.SavingsPercent))
	print("===================================================")
	return layout
end

local function dynamicWrite(w: Writer, value: any, options: Options?, dictionary: DictionaryState)
	local kind = typeof(value)
	if kind == "nil" then flushBits(w); writeByte(w, TAG_NIL)
	elseif kind == "boolean" then flushBits(w); writeByte(w, value and TAG_TRUE or TAG_FALSE)
	elseif kind == "number" then
		flushBits(w)
		if isInteger(value) and value >= 0 then writeByte(w, TAG_UINT); writeVarUInt(w, value)
		elseif isInteger(value) then writeByte(w, TAG_INT); writeVarInt(w, value)
		else writeByte(w, TAG_FLOAT); writeF64(w, value) end
	elseif kind == "string" then
		local id = dictionary.Encode[value]
		flushBits(w)
		if id then
			writeByte(w, TAG_STRING_REF)
			writeVarUInt(w, id)
		else
			writeByte(w, TAG_STRING)
			local packed = Compression.CompressString(value, options)
			writeVarUInt(w, buffer.len(packed))
			ensureCapacity(w, buffer.len(packed))
			buffer.copy(w.Buffer, w.Position, packed, 0, buffer.len(packed))
			w.Position += buffer.len(packed)
			w.UsedBits += buffer.len(packed) * 8
		end
	elseif kind == "Vector2" then flushBits(w); writeByte(w, TAG_VECTOR2); writeF64(w, value.X); writeF64(w, value.Y)
	elseif kind == "Vector3" then flushBits(w); writeByte(w, TAG_VECTOR3); writeF64(w, value.X); writeF64(w, value.Y); writeF64(w, value.Z)
	elseif kind == "Color3" then
		flushBits(w); writeByte(w, TAG_COLOR3)
		writeByte(w, math.floor(value.R * 255 + 0.5))
		writeByte(w, math.floor(value.G * 255 + 0.5))
		writeByte(w, math.floor(value.B * 255 + 0.5))
	elseif kind == "CFrame" then
		flushBits(w); writeByte(w, TAG_CFRAME)
		local components = {value:GetComponents()}
		for i = 1, 12 do writeF64(w, components[i]) end
	elseif kind == "table" then
		flushBits(w)
		if isArray(value) then
			writeByte(w, TAG_ARRAY)
			writeVarUInt(w, #value)
			for _, item in ipairs(value) do dynamicWrite(w, item, options, dictionary) end
		else
			writeByte(w, TAG_MAP)
			local keys = {}
			for key in pairs(value) do
				if typeof(key) ~= "string" and typeof(key) ~= "number" then fail("map keys must be strings or numbers", 2) end
				keys[#keys + 1] = key
			end
			table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
			writeVarUInt(w, #keys)
			for _, key in ipairs(keys) do dynamicWrite(w, key, options, dictionary); dynamicWrite(w, value[key], options, dictionary) end
		end
	else
		fail("unsupported dynamic type " .. kind, 2)
	end
end

local function dynamicRead(r: Reader, dictionary: DictionaryState): any
	alignReader(r)
	local tag = readByte(r)
	if tag == TAG_NIL then return nil
	elseif tag == TAG_FALSE then return false
	elseif tag == TAG_TRUE then return true
	elseif tag == TAG_UINT then return readVarUInt(r)
	elseif tag == TAG_INT then return readVarInt(r)
	elseif tag == TAG_FLOAT then return readF64(r)
	elseif tag == TAG_STRING_REF then
		local id = readVarUInt(r)
		return dictionary.Decode[id]
	elseif tag == TAG_STRING then
		local length = readVarUInt(r)
		if r.Position + length > r.Length then fail("truncated dynamic string", 2) end
		local data = buffer.create(length)
		buffer.copy(data, 0, r.Buffer, r.Position, length)
		r.Position += length
		return Compression.DecompressString(data)
	elseif tag == TAG_VECTOR2 then return Vector2.new(readF64(r), readF64(r))
	elseif tag == TAG_VECTOR3 then return Vector3.new(readF64(r), readF64(r), readF64(r))
	elseif tag == TAG_COLOR3 then return Color3.fromRGB(readByte(r), readByte(r), readByte(r))
	elseif tag == TAG_CFRAME then
		local components = table.create(12)
		for i = 1, 12 do components[i] = readF64(r) end
		return CFrame.new(table.unpack(components))
	elseif tag == TAG_ARRAY then
		local count = readVarUInt(r)
		local result = table.create(count)
		for i = 1, count do result[i] = dynamicRead(r, dictionary) end
		return result
	elseif tag == TAG_MAP then
		local count = readVarUInt(r)
		local result = {}
		for _ = 1, count do
			local key = dynamicRead(r, dictionary)
			result[key] = dynamicRead(r, dictionary)
		end
		return result
	end
	fail("invalid dynamic tag", 2)
	return nil
end

function Compression.Encode(value: any, options: Options?): Packet
	local w = newWriter()
	local dictionary = makeDictionary(value, options)
	local schemaVersion = options and options.SchemaVersion or 1
	writeHeader(w, MODE_DYNAMIC, schemaVersion)
	writeVarUInt(w, #dictionary.Decode)
	for i = 1, #dictionary.Decode do writeStringRaw(w, dictionary.Decode[i]) end
	dynamicWrite(w, value, options, dictionary)
	return packetFromBuffer(finish(w), options, schemaVersion)
end

function Compression.Decode(packet: Packet | buffer, options: Options?): any
	local data = unwrapPacket(packet, options)
	local r = newReader(data)
	readHeader(r, MODE_DYNAMIC)
	local dictionary: DictionaryState = {Encode = {}, Decode = {}}
	local count = readVarUInt(r)
	for i = 1, count do
		local value = readStringRaw(r)
		dictionary.Decode[i] = value
		dictionary.Encode[value] = i
	end
	return dynamicRead(r, dictionary)
end

function Compression.Hash(data: buffer): number
	if typeof(data) ~= "buffer" then fail("Hash expects buffer", 2) end
	return hashBuffer(data)
end

function Compression.Verify(data: buffer, hash: number): boolean
	return hashBuffer(data) == hash
end

function Compression.Optional(descriptor: Descriptor): Descriptor
	local copy = table.clone(descriptor)
	copy.Optional = true
	return copy
end

function Compression.Bool(): Descriptor return {Kind = "Bool"} end
function Compression.UInt(): Descriptor return {Kind = "UInt"} end
function Compression.Int(): Descriptor return {Kind = "Int"} end
function Compression.Float(): Descriptor return {Kind = "Float"} end
function Compression.String(): Descriptor return {Kind = "String"} end
function Compression.CompressedString(options: Options?): Descriptor return {Kind = "CompressedString", Options = options} end
function Compression.Vector2(): Descriptor return {Kind = "Vector2"} end
function Compression.Vector3(): Descriptor return {Kind = "Vector3"} end
function Compression.Color3(): Descriptor return {Kind = "Color3"} end
function Compression.Array(item: Descriptor): Descriptor return {Kind = "Array", Item = item} end
function Compression.Object(fields: {[string]: Descriptor}): Descriptor return {Kind = "Object", Fields = fields} end

function Compression.Quantized(minimum: number, maximum: number, bits: number): Descriptor
	if maximum <= minimum then fail("maximum must be greater than minimum", 2) end
	if bits < 1 or bits > 24 or bits % 1 ~= 0 then fail("bits must be integer 1-24", 2) end
	return {Kind = "Quantized", Options = {Minimum = minimum, Maximum = maximum, Bits = bits}}
end

function Compression.QuantizedVector3(minimum: Vector3, maximum: Vector3, bits: number): Descriptor
	if typeof(minimum) ~= "Vector3" or typeof(maximum) ~= "Vector3" then fail("QuantizedVector3 expects Vector3 bounds", 2) end
	if bits < 1 or bits > 24 or bits % 1 ~= 0 then fail("bits must be integer 1-24", 2) end
	return {Kind = "QuantizedVector3", Options = {Minimum = minimum, Maximum = maximum, Bits = bits}}
end

function Compression.Auto(value: any): Descriptor
	local kind = typeof(value)
	if kind == "boolean" then return Compression.Bool()
	elseif kind == "number" then
		if isInteger(value) then
			if value >= 0 then return Compression.UInt() end
			return Compression.Int()
		end
		return Compression.Float()
	elseif kind == "string" then
		if #value >= 24 then return Compression.CompressedString() end
		return Compression.String()
	elseif kind == "Vector2" then return Compression.Vector2()
	elseif kind == "Vector3" then return Compression.Vector3()
	elseif kind == "Color3" then return Compression.Color3()
	elseif kind == "table" and isArray(value) and #value > 0 then
		return Compression.Array(Compression.Auto(value[1]))
	end
	fail("Auto could not infer descriptor for " .. kind, 2)
	return Compression.String()
end

function Compression.Stats(packet: Packet | buffer): {Bytes: number, Bits: number, Hash: number?}
	if typeof(packet) == "buffer" then
		return {Bytes = buffer.len(packet), Bits = buffer.len(packet) * 8, Hash = nil}
	end
	return {Bytes = packet.Bytes, Bits = packet.Bits, Hash = packet.Hash}
end

function Compression.Version(): string
	return "1.0.0"
end

return Compression
