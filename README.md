# Compression

**Current version: v2.2.1**

Compression is a binary serialization and compression library for Roblox/Luau focused on compact payloads, predictable round trips, and low overhead.

It supports primitive values, Roblox datatypes, buffers, arrays, maps, schemas, delta packets, string dictionaries, integrity hashes, and adaptive codec selection through a single API.

The library is designed around one rule:

> Use a smaller representation when it is available. If compression would make the payload larger, preserve the original representation instead.

---

## Features

- Adaptive `Compression.Auto(value)` codec selection
- Compact booleans, integers, decimals, and powers of ten
- Bit-packed boolean arrays
- Compact `Vector2`, `Vector3`, `Color3`, and `CFrame`
- String codecs:
  - Raw
  - Numeric4
  - Identifier6
  - ASCII7
  - LZ
- Buffer codecs:
  - Raw passthrough
  - Zero
  - Fill
  - SparseZero
  - SparsePower2
  - Nibble4
  - NibbleHigh4
  - LZ
- Compact table and array codecs
- Delta-encoded numeric arrays
- Run-length encoded arrays
- Nested table support
- Buffers and Roblox datatypes inside tables
- Dynamic repeated-string dictionaries
- Schema-based serialization
- Schema version validation
- Schema delta packets
- Optional FNV-1a integrity hashes
- Bit-layout analysis
- Backward decoding support for compatible older packet versions
- Reduced Luau top-level register usage for large-module stability

---

## Installation

Place the `Compression` ModuleScript somewhere accessible to both the server and client.

Example structure:

```text
ReplicatedStorage
└── NetStream
    └── Compression
```

Require it with:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Compression = require(
	ReplicatedStorage.NetStream.Compression
)
```

---

## Quick Start

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Compression = require(
	ReplicatedStorage.NetStream.Compression
)

local packet = Compression.Auto({
	Coins = 1_000_000,
	Rebirths = 25,
	Enabled = true,
})

print("Codec:", packet.Codec)
print("Bytes:", packet.Bytes)
print("Bits:", packet.Bits)

local restored = Compression.AutoDecompress(packet)

print(restored.Coins)
print(restored.Rebirths)
print(restored.Enabled)
```

---

# Automatic Compression

`Compression.Auto()` inspects the input value and selects an appropriate codec.

```lua
local packet = Compression.Auto(value)
local restored = Compression.AutoDecompress(packet)
```

Supported value categories include:

```lua
Compression.Auto(true)
Compression.Auto(123)
Compression.Auto(-25)
Compression.Auto(123.456789)
Compression.Auto("Hello World")
Compression.Auto(buffer.create(64))
Compression.Auto(Vector2.new(1, 2))
Compression.Auto(Vector3.new(1, 2, 3))
Compression.Auto(Color3.fromRGB(255, 100, 50))
Compression.Auto(CFrame.new(1, 2, 3))

Compression.Auto({
	Coins = 1000,
	Enabled = true,
})
```

The selected codec is exposed through:

```lua
print(packet.Codec)
print(packet.ValueType)
```

---

# Packet Metadata

Packets returned by APIs such as `Compression.Auto()` include compression metadata.

```lua
local packet = Compression.Auto(value)

print(packet.Data)
print(packet.Bytes)
print(packet.Bits)

print(packet.RawBytes)
print(packet.SavedBytes)
print(packet.ExpandedBytes)

print(packet.ValueType)
print(packet.Codec)

print(packet.Ratio)
print(packet.SavingsPercent)
```

Depending on the value, bit-level metadata may also be available.

---

# Booleans

A boolean contains only two states and therefore requires one meaningful bit.

```lua
local packet = Compression.Auto(true)

print(packet.Bytes)
print(packet.Bits)
```

A standalone Roblox `buffer` is still byte-addressed, so the physical buffer occupies at least one byte.

Conceptually:

```text
Physical container: 1 byte
Boolean payload:    1 bit
```

When several booleans are stored together, they can be packed into shared bytes.

For example:

```text
8 booleans  = 8 payload bits
16 booleans = 16 payload bits
```

Boolean arrays use this packed representation automatically.

---

# Number Compression

Compression includes specialized representations for common numeric patterns.

Examples:

```lua
Compression.Auto(0)
Compression.Auto(1)
Compression.Auto(-1)
Compression.Auto(100)
Compression.Auto(1_000_000)
Compression.Auto(-123456)
Compression.Auto(123.456789)
Compression.Auto(1e100)
Compression.Auto(0.000001)
```

Possible optimizations include:

- Zero
- One
- Negative one
- Compact unsigned integers
- Compact signed integers
- Powers of ten
- Compact decimal values
- Float32-compatible values
- Raw passthrough when a smaller lossless representation is unavailable

Small and structured numbers can be significantly smaller than the normal 64-bit Lua number representation.

---

# String Compression

Use:

```lua
local compressed = Compression.CompressString(value)
local restored = Compression.DecompressString(compressed)
```

Available strategies:

```text
Auto
Raw
Numeric4
Identifier6
ASCII7
LZ
```

Specify a strategy with:

```lua
local compressed = Compression.CompressString(
	value,
	{
		StringStrategy = "Numeric4",
	}
)
```

## Numeric4

Optimized for numeric text containing:

```text
0-9
+
-
.
e
E
```

Example:

```lua
local compressed = Compression.CompressString(
	"123456789012345678901234567890",
	{
		StringStrategy = "Numeric4",
	}
)
```

## Identifier6

Optimized for identifier-style strings containing:

```text
A-Z
a-z
0-9
_
-
```

Example:

```text
PlayerData_Coins_Rebirths_Level_123456
```

## ASCII7

Stores ASCII-compatible text with 7-bit symbols.

## LZ

Useful for repetitive strings.

```lua
local value = string.rep(
	"PlayerDataCoinsPlayerDataCoins",
	30
)

local compressed = Compression.CompressString(value)
```

Inspect the selected string mode with:

```lua
print(
	Compression.StringMode(compressed)
)
```

---

# Buffer Compression

Buffers can be compressed directly.

```lua
local compressed = Compression.CompressBuffer(value)
local restored = Compression.DecompressBuffer(compressed)
```

Inspect the selected codec:

```lua
print(
	Compression.BufferMode(compressed)
)
```

Inspect the frame version:

```lua
print(
	Compression.BufferFrameVersion(compressed)
)
```

Current buffer modes include:

| Mode | Purpose |
| --- | --- |
| `RawPassthrough` | Leaves incompressible data unchanged |
| `Zero` | Buffers containing only zero bytes |
| `Fill` | Buffers containing one repeated byte |
| `SparseZero` | Buffers containing mostly zeroes |
| `SparsePower2` | Sparse buffers containing powers-of-two byte values |
| `Nibble4` | Values that fit inside the low 4 bits |
| `NibbleHigh4` | Values that fit inside the high 4 bits |
| `LZ` | Repeated binary patterns |

---

## Zero Buffers

```lua
local value = buffer.create(100)

local compressed =
	Compression.CompressBuffer(value)
```

Instead of storing every zero byte, Compression stores the buffer length and the selected Zero mode.

---

## Fill Buffers

```lua
local value = buffer.create(100)

buffer.fill(
	value,
	0,
	123
)

local compressed =
	Compression.CompressBuffer(value)
```

The repeated byte only needs to be stored once.

---

## SparseZero

```lua
local value = buffer.create(64)

buffer.writeu8(value, 0, 25)
buffer.writeu8(value, 20, 50)
buffer.writeu8(value, 40, 75)
buffer.writeu8(value, 63, 100)

local compressed =
	Compression.CompressBuffer(value)
```

SparseZero stores a bitmap describing non-zero locations plus the non-zero byte values.

---

## SparsePower2

SparsePower2 is optimized for sparse buffers whose non-zero bytes are:

```text
1
2
4
8
16
32
64
128
```

This works particularly well with some compact binary structures.

---

## Nibble Compression

Nibble codecs store two four-bit values in one byte.

Low nibble values:

```text
0 - 15
```

High nibble values:

```text
0
16
32
48
...
240
```

---

## LZ Buffers

Repeated binary patterns can use the LZ buffer codec.

```lua
local value = buffer.create(512)

for i = 0, 511 do
	buffer.writeu8(
		value,
		i,
		i % 32
	)
end

local compressed =
	Compression.CompressBuffer(value)
```

---

## Raw Passthrough

Lossless compression cannot guarantee that every input becomes smaller.

Random or high-entropy data may already be close to incompressible.

When no compressed representation is smaller, Compression can preserve the original bytes:

```text
Raw:        256 B
Stored:     256 B
Mode:       RawPassthrough
```

This avoids adding unnecessary compression overhead.

---

# Roblox Datatypes

Compression supports Roblox datatypes directly.

## Vector2

```lua
local packet = Compression.Auto(
	Vector2.new(
		123.456,
		-987.654
	)
)
```

Float32-compatible values can use a compact representation when the original Roblox value is restored exactly.

## Vector3

```lua
local packet = Compression.Auto(
	Vector3.new(
		100,
		200,
		300
	)
)
```

Integer-like components can use compact number encoding.

## Color3

```lua
local packet = Compression.Auto(
	Color3.fromRGB(
		100,
		150,
		255
	)
)
```

RGB values can use compact byte components.

## CFrame

```lua
local packet = Compression.Auto(
	CFrame.new(
		100,
		200,
		300
	)
)
```

Simple transforms can compress heavily.

Rotated transforms can use Float32 component encoding when it is smaller.

```lua
local packet = Compression.Auto(
	CFrame.new(
		10,
		20,
		30
	) * CFrame.Angles(
		math.rad(45),
		math.rad(90),
		math.rad(15)
	)
)
```

---

# Table Compression

Use:

```lua
local compressed = Compression.CompressTable({
	Coins = 1000,
	Rebirths = 10,
	Enabled = true,
})

local restored =
	Compression.DecompressTable(compressed)
```

Inspect the selected table representation:

```lua
print(
	Compression.TableMode(compressed)
)

print(
	Compression.IsCompactTable(compressed)
)
```

---

# Compact Arrays

Compression recognizes common array layouts automatically.

Current compact array modes include:

```text
CompactBoolArray
CompactUIntArray
CompactIntArray
CompactFloatArray
CompactStringArray
CompactMixedArray
CompactUIntDeltaArray
CompactIntDeltaArray
CompactRLEArray
```

## Boolean Arrays

```lua
{
	true,
	false,
	true,
	true,
	false,
	true,
}
```

Boolean values are bit-packed.

## UInt Arrays

```lua
{
	1,
	2,
	3,
	4,
	5,
	6,
}
```

Unsigned integers use compact variable-width encoding.

## Signed Integer Arrays

```lua
{
	-5,
	-4,
	-3,
	-2,
	-1,
	0,
	1,
	2,
	3,
}
```

## Delta Arrays

Sequential numbers can store the first value followed by small differences.

```lua
{
	1000,
	1001,
	1002,
	1003,
	1004,
	1005,
}
```

## Run-Length Arrays

Repeated values can use run-length encoding.

```lua
{
	100,
	100,
	100,
	100,
	100,
	200,
	200,
	200,
	300,
	300,
}
```

---

# Maps and Nested Tables

String-key tables can use compact map encoding.

```lua
local data = {
	Coins = 1_000_000,
	Rebirths = 25,
	Level = 100,
	Enabled = true,
	Name = "Player",
}

local compressed =
	Compression.CompressTable(data)
```

Nested structures are supported:

```lua
local data = {
	Version = 2,

	Data = {
		Coins = 1e12,
		Rebirths = 100,
		Prestiges = 5,

		Stats = {
			Strength = 1000,
			Speed = 500,
			Luck = 25,
		},
	},

	Settings = {
		Music = true,
		SFX = true,
		Particles = false,
	},
}
```

---

# Buffers Inside Tables

Buffers can be stored inside compressed tables.

```lua
local payload = buffer.create(64)

for i = 0, 15 do
	buffer.writeu32(
		payload,
		i * 4,
		1000
	)
end

local compressed = Compression.CompressTable({
	UserId = 123456789,
	Buffer = payload,
	Active = true,
})
```

---

# Bnum Compatibility

Bnum uses a compact 12-byte buffer representation, so it can use the normal buffer compression pipeline.

```lua
local Bnum = require(
	game.ReplicatedStorage.Bnum
)

local value = Bnum.new(1, 3)

local compressed =
	Compression.CompressBuffer(value)

local restored =
	Compression.DecompressBuffer(compressed)
```

Example result from v2.2.x testing:

```text
Bnum.new(1, 3)

Raw:        12 B
Compressed: 5 B
Mode:       SparsePower2
Savings:    58.33%
```

Different Bnum values may select `SparseZero`, `SparsePower2`, or another buffer mode automatically.

---

# Schemas

Schemas are recommended when the structure of the payload is known ahead of time.

```lua
local Schema = Compression.Schema({
	Boolean = Compression.Bool(),
	Number = Compression.UInt(),
	String = Compression.CompressedString(),

	Health = Compression.Quantized(
		0,
		100,
		8
	),
}, 1)
```

Encode:

```lua
local data = {
	Boolean = true,
	Number = 123,
	String = "Hello Hello Hello Hello Hello Hello",
	Health = 97,
}

local packet = Schema:Encode(
	data,
	{
		Mode = "BinaryWithHash",
	}
)
```

Decode:

```lua
local restored =
	Schema:Decode(packet)
```

---

# Descriptor API

Available descriptor constructors include:

| Descriptor | Purpose |
| --- | --- |
| `Compression.Bool()` | Boolean |
| `Compression.UInt()` | Unsigned integer |
| `Compression.Int()` | Signed integer |
| `Compression.Float()` | Floating-point number |
| `Compression.String()` | Raw string |
| `Compression.CompressedString()` | Compressible string |
| `Compression.Buffer()` | Buffer |
| `Compression.Vector2()` | Vector2 |
| `Compression.Vector3()` | Vector3 |
| `Compression.Color3()` | Color3 |
| `Compression.CFrame()` | CFrame |
| `Compression.Array(descriptor)` | Array |
| `Compression.Object(fields)` | Structured object |
| `Compression.Quantized(min, max, bits)` | Quantized number |
| `Compression.QuantizedVector3(min, max, bits)` | Quantized Vector3 |
| `Compression.Optional(descriptor)` | Optional field |

---

# Schema Versioning

Schemas can define an explicit version.

```lua
local Schema = Compression.Schema({
	Coins = Compression.UInt(),
}, 3)
```

The version is embedded in the encoded packet.

This prevents a packet intended for one schema version from silently being decoded using an incompatible schema definition.

---

# Delta Encoding

Schemas support delta packets.

```lua
local previous = {
	Coins = 100,
	Level = 5,
}

local current = {
	Coins = 150,
	Level = 6,
}

local delta =
	Schema:EncodeDelta(
		previous,
		current
	)

local restored =
	Schema:DecodeDelta(
		previous,
		delta
	)
```

Delta packets are useful when only a small portion of the payload changes.

---

# Dynamic String Dictionary

Dynamic payloads can detect repeated strings and place them into a shared dictionary.

Later occurrences can reference a compact dictionary ID.

```lua
local packet = Compression.Encode(
	data,
	{
		UseStringDictionary = true,
		DictionaryMinUses = 2,
		MaxDictionaryEntries = 255,
	}
)
```

Disable the dictionary with:

```lua
UseStringDictionary = false
```

---

# Integrity Hash

Packets can optionally include an FNV-1a integrity hash.

```lua
local packet = Compression.Encode(
	data,
	{
		Mode = "BinaryWithHash",
	}
)

print(packet.Hash)
```

When hash verification is enabled, corrupted payloads can be rejected during decoding.

---

# Bit Layout Analysis

Schemas can report how the encoded payload uses its bits.

```lua
local layout =
	Schema:AnalyzeBits(data)

print(layout.HeaderBits)
print(layout.UsefulBits)
print(layout.PaddingBits)
print(layout.PhysicalBits)
print(layout.PhysicalBytes)
```

A formatted report is also available:

```lua
Schema:PrintBitLayout(data)
```

This is useful for tuning frequently replicated or stored payloads.

---

# Configuration

Common options include:

```lua
{
	Mode = "Binary",

	CompressStrings = true,
	StringMinLength = 16,
	StringStrategy = "Auto",
	StringSearchDepth = 24,
	StringWindowSize = 16383,
	StringMaxMatch = 66,

	UseStringDictionary = true,
	DictionaryMinUses = 2,
	MaxDictionaryEntries = 255,

	TableCompression = true,
	HomogeneousArrays = true,
	DeltaArrays = true,
	RunLengthArrays = true,
	CompactMapKeys = true,
	TableStrategy = "Auto",

	CompressBuffers = true,
	BufferStrategy = "Auto",
	BufferMinLength = 6,
	BufferSearchDepth = 32,
	BufferWindowSize = 32767,
	BufferMaxMatch = 66,

	VerifyHash = true,
	SchemaVersion = 1,

	AllowExpansion = false,
}
```

---

# v2.2.1

v2.2.1 builds on the v2.2 internal restructuring and improves compact scalar and Roblox datatype compression.

## Primitive values

- Compact boolean payload metadata
- Compact integer paths
- Compact decimal representation
- Float32-compatible scalar representation
- Improved no-expansion fallback behavior

## Roblox datatypes

- Compact Vector2 encoding
- Compact Vector3 encoding
- Compact Color3 encoding
- Compact CFrame encoding
- Float32 CFrame fallback for complex transforms

## Buffers

- Zero
- Fill
- SparseZero
- SparsePower2
- Nibble4
- NibbleHigh4
- LZ
- Raw passthrough

## Tables

- Bit-packed boolean arrays
- Compact unsigned integer arrays
- Compact signed integer arrays
- Compact float arrays
- Compact string arrays
- Delta arrays
- Run-length arrays
- Compact string maps
- Nested tables
- Buffers and Roblox datatypes inside tables

## Stability

v2.2 reorganized large groups of internal constants and codec state to reduce top-level Luau register pressure.

This resolved module load failures such as:

```text
Out of local registers
exceeded limit 200
```

The public API remains compatible with the v2 series.

---

# Version

```text
2.2.1
```

```lua
print(
	Compression.Version()
)
```

Expected output:

```text
2.2.1
```
