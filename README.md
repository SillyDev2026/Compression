# Compression

**Current version: v2.3.2**  
**Binary format: 22**  
**Public API: 80 functions**

Compression is a binary serialization and compression library for Roblox/Luau focused on compact payloads, predictable round trips, low overhead, and practical game-data serialization.

It supports primitive values, Roblox datatypes, strings, buffers, arrays, maps, nested tables, schemas, delta packets, repeated-string dictionaries, table-key mapping, integrity hashes, bit-layout analysis, and adaptive codec selection.

The main rule of the library is:

> Use the smallest safe representation available. If compression would make the value larger, preserve a raw or passthrough representation when possible.

For new code, the simplest API is:

```lua
local packet = Compression.Pack(value)
local restored = Compression.Unpack(packet)
```

The older `Compression.Auto()` / `Compression.AutoDecompress()` API remains supported and maps to the same adaptive compression path.

---

## Contents

- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Pack and Unpack](#pack-and-unpack)
- [Safe Calls](#safe-calls)
- [Real Compression Examples](#real-compression-examples)
- [Packet Metadata](#packet-metadata)
- [Supported Types](#supported-types)
- [Boolean Compression](#boolean-compression)
- [Number Compression](#number-compression)
- [String Compression](#string-compression)
- [Buffer Compression](#buffer-compression)
- [Roblox Datatypes](#roblox-datatypes)
- [Table Compression](#table-compression)
- [Table Key Mapping](#table-key-mapping)
- [Compact Arrays](#compact-arrays)
- [Dynamic Typed Arrays](#dynamic-typed-arrays)
- [Schemas](#schemas)
- [Descriptor API](#descriptor-api)
- [Schema Delta Encoding](#schema-delta-encoding)
- [Descriptor Inference](#descriptor-inference)
- [Integrity Hashes](#integrity-hashes)
- [Statistics and Analysis](#statistics-and-analysis)
- [Configuration](#configuration)
- [Backward Compatibility](#backward-compatibility)
- [v2.3.2 Patch Notes](#v232-patch-notes)
- [Version](#version)

---

# Features

- Adaptive `Compression.Pack(value)` / `Compression.Unpack(packet)` API
- Compatible `Compression.Auto()` / `Compression.AutoDecompress()` API
- Safe `TryPack`, `TryUnpack`, and other `Try*` calls
- `Compression.Size(value)` convenience call
- `Compression.Codec(value)` convenience call
- Compact boolean payloads
- Compact zero, one, and negative-one number atoms
- Compact unsigned and signed integers
- Power-of-ten number encoding
- Exact compact decimal representation
- Exact Float32 selection when safe
- Raw fallback when smaller compression is unavailable
- String codecs:
  - Raw
  - Numeric4
  - Identifier6
  - ASCII7
  - LZ
- Buffer codecs:
  - Raw passthrough
  - Raw framed
  - Zero
  - Fill
  - SparseZero
  - SparsePower2
  - Nibble4
  - NibbleHigh4
  - LZ
- Compact table encoding
- Dynamic tagged table encoding
- Adaptive Compact-vs-Dynamic table selection
- Bit-packed boolean arrays
- Compact UInt and Int arrays
- Float32 and Float64 array paths
- Delta-encoded numeric arrays
- Run-length encoded arrays
- Shared nested table-key mapping
- Dynamic repeated-string dictionaries
- Inline small-number tags in Dynamic tables
- Native Roblox datatype support
- Homogeneous Roblox datatype arrays
- Schema-based serialization
- Schema version validation
- Schema delta packets
- Optional fields
- Quantized number and Vector3 descriptors
- Automatic descriptor inference
- Optional FNV-1a integrity hashes
- Useful-bit vs physical-bit statistics
- Bit-layout analysis
- Malformed payload and allocation guards
- Backward decoding support for compatible older formats
- Reduced top-level Luau register pressure

---

# Installation

Place the `Compression` ModuleScript somewhere accessible to the code that needs it.

Example:

```text
ReplicatedStorage
└── Compression
```

Require it:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Compression = require(
	ReplicatedStorage:WaitForChild("Compression")
)
```

If you keep it under another folder, such as `NetStream`:

```text
ReplicatedStorage
└── NetStream
    └── Compression
```

then:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Compression = require(
	ReplicatedStorage
		:WaitForChild("NetStream")
		:WaitForChild("Compression")
)
```

---

# Quick Start

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Compression = require(
	ReplicatedStorage:WaitForChild("Compression")
)

local data = {
	Coins = 1_000_000,
	Rebirths = 25,
	Enabled = true,
}

local packet = Compression.Pack(data)

print("Codec:", packet.Codec)
print("Bytes:", packet.Bytes)
print("Bits:", packet.Bits)

local restored = Compression.Unpack(packet)

print(restored.Coins)
print(restored.Rebirths)
print(restored.Enabled)
```

For most code, this is all you need:

```lua
local packet = Compression.Pack(value)
local value = Compression.Unpack(packet)
```

---

# Pack and Unpack

`Pack()` is the recommended high-level call in v2.3.x.

```lua
local packet = Compression.Pack(value)
```

It automatically inspects the value and chooses an appropriate lossless representation.

Restore it with:

```lua
local restored = Compression.Unpack(packet)
```

These are convenience wrappers around the adaptive API:

```text
Pack       -> Auto
Unpack     -> AutoDecompress
TryPack    -> TryAuto
TryUnpack  -> TryAutoDecompress
```

The original API remains valid:

```lua
local packet = Compression.Auto(value)
local restored = Compression.AutoDecompress(packet)
```

---

## Size

Get the selected encoded size without manually reading packet fields:

```lua
local bytes, bits =
	Compression.Size(value)

print("Bytes:", bytes)
print("Bits:", bits)
```

---

## Codec

Inspect the adaptive codec:

```lua
local codec =
	Compression.Codec(value)

print(codec)
```

Examples may include:

```text
CompactBoolean1Bit
CompactNumber
CompactDecimal
CompactFloat32
CompactString
Buffer/SparsePower2
Table/CompactStringMap
CompactVector3
CompactColor3
CompactCFrame
CompactUDim
CompactUDim2
CompactRect
CompactNumberRange
CompactBrickColor
CompactDateTime
```

The exact codec depends on the value.

---

# Safe Calls

Use `TryPack()` if compression failure should be handled without throwing:

```lua
local ok, packet, err =
	Compression.TryPack(value)

if not ok then
	warn("Compression failed:", err)
	return
end
```

Restore safely:

```lua
local ok, restored, err =
	Compression.TryUnpack(packet)

if not ok then
	warn("Decompression failed:", err)
	return
end
```

The v2.3.x `Try*` APIs return useful error text:

```text
success, value, nil
```

or:

```text
false, nil, errorMessage
```

Additional safe helpers include:

```lua
Compression.TryAuto(...)
Compression.TryAutoDecompress(...)
Compression.TryDecompressString(...)
Compression.TryDecompressBuffer(...)
Compression.TryDecompressTable(...)
```

---

# Real Compression Examples

The following examples come from the v2.3.2 Studio type/regression test.

Compression ratios are input-dependent. They are examples, not guaranteed ratios for every value.

The v2.3.2 regression suite completed with **75 tests passed** and **Status: ALL PASSED**. The release primarily improves correctness, fallback behavior, metadata accuracy, and edge-case handling while preserving the strong compression ratios of v2.3.1.

## Primitive numbers

| Value | Raw | Compressed | Saved | Savings |
| --- | ---: | ---: | ---: | ---: |
| `0` | 8 B | **1 B** | 7 B | **87.50%** |
| `1` | 8 B | **1 B** | 7 B | **87.50%** |
| `-1` | 8 B | **1 B** | 7 B | **87.50%** |
| `100` | 8 B | **2 B** | 6 B | **75.00%** |
| `1_000_000` | 8 B | **2 B** | 6 B | **75.00%** |
| `-123456` | 8 B | **4 B** | 4 B | **50.00%** |
| `123.456789` | 8 B | **6 B** | 2 B | **25.00%** |
| `1e100` | 8 B | **3 B** | 5 B | **62.50%** |
| `0.000001` | 8 B | **2 B** | 6 B | **75.00%** |

For example:

```lua
local packet =
	Compression.Pack(0)

print(packet.Codec)
print(packet.Bytes)
print(packet.Bits)
```

Example result:

```text
Codec: CompactNumber

RAW
Bytes: 8 B
Bits: 64 b

COMPRESSED
Bytes: 1 B
Bits: 8 b

Saved: 7 B
Savings: 87.50%

Returned Value: 0
Exact Match: true
```

---

## Strings

| Example | Mode | Raw | Compressed | Savings |
| --- | --- | ---: | ---: | ---: |
| 30-digit numeric string | `Numeric4` | 30 B | **17 B** | **43.33%** |
| Identifier-style string | `Identifier6` | 38 B | **31 B** | **18.42%** |
| ASCII sentence | `ASCII7` | 47 B | **44 B** | **6.38%** |
| Repetitive 400 B string | `LZ-v2` | 400 B | **26 B** | **93.50%** |
| Auto repetitive 900 B string | `LZ-v2` | 900 B | **47 B** | **94.78%** |

Example:

```lua
local value =
	string.rep(
		"HelloWorld",
		40
	)

local compressed =
	Compression.CompressString(value)

print(
	Compression.StringMode(
		compressed
	)
)
```

A repetitive test string compressed from:

```text
400 B -> 26 B
```

using `LZ-v2`.

---

## Buffers

| Buffer | Selected mode | Raw | Compressed | Savings |
| --- | --- | ---: | ---: | ---: |
| 100 zero bytes | `Zero` | 100 B | **3 B** | **97.00%** |
| 100 copies of one byte | `Fill` | 100 B | **4 B** | **96.00%** |
| Sparse zero buffer | `SparseZero` | 64 B | **15 B** | **76.56%** |
| Sparse power-of-two buffer | `SparsePower2` | 64 B | **14 B** | **78.12%** |
| Repetitive binary pattern | `LZ` | 512 B | **53 B** | **89.65%** |
| Random/high-entropy buffer | `RawPassthrough` | 256 B | **256 B** | 0% |

The final row is intentional.

Compression does not force a larger representation when the bytes are already effectively incompressible.

---

## Roblox datatypes

| Type | Raw estimate | Compressed | Savings |
| --- | ---: | ---: | ---: |
| `Vector2` | 16 B | **9 B** | **43.75%** |
| `Vector3` | 24 B | **9 B** | **62.50%** |
| `Color3` | 12 B | **4 B** | **66.67%** |
| position-only `CFrame` | 96 B | **18 B** | **81.25%** |
| rotated `CFrame` | 96 B | **48 B** | **50.00%** |

A simple Auto `Vector3.new(1, 2, 3)` test reached:

```text
24 B -> 6 B
75.00% saved
```

A simple Auto `CFrame.new(1, 2, 3)` test reached:

```text
96 B -> 15 B
84.38% saved
```

Different component values can choose different internal number representations, so sizes vary.

---

## Arrays

| Array type | Mode | Raw estimate | Compressed | Savings |
| --- | --- | ---: | ---: | ---: |
| booleans | `CompactBoolArray` | 54 B | **3 B** | **94.44%** |
| UInt array | `CompactUIntArray` | 160 B | **12 B** | **92.50%** |
| Int array | `CompactIntArray` | 176 B | **14 B** | **92.05%** |
| exact Float32 array | `CompactFloat32Array` | 64 B | **19 B** | **70.31%** |
| repeated string array | `CompactRLEArray` | 72 B | **15 B** | **79.17%** |
| repeated numeric array | `CompactRLEArray` | 160 B | **14 B** | **91.25%** |
| sequential UInt array | `CompactUIntDeltaArray` | 112 B | **11 B** | **90.18%** |

---

## Tables

| Table | Mode | Raw estimate | Compressed | Savings |
| --- | --- | ---: | ---: | ---: |
| `{man = 1, exp = 3}` | `CompactStringMap` | 22 B | **12 B** | **45.45%** |
| player data map | `CompactStringMap` | 60 B | **42 B** | **30.00%** |
| mixed table | `CompactStringMap` | 166 B | **68 B** | **59.04%** |
| nested player data | `CompactStringMap` | 139 B | **95 B** | **31.65%** |
| table containing buffer | `CompactStringMap` | 91 B | **38 B** | **58.24%** |
| table containing Roblox types | `CompactStringMap` | 179 B | **105 B** | **41.34%** |

Example:

```lua
local data = {
	Coins = 1000,
	Rebirths = 10,
	Enabled = true,
}

local packet =
	Compression.Pack(data)

print(packet.Codec)
print(packet.Bytes)
```

One measured Auto test produced:

```text
Codec: Table/CompactStringMap

Raw:        37 B
Compressed: 25 B
Saved:      12 B
Savings:    32.43%
```

---

# Packet Metadata

Adaptive calls return a packet table.

```lua
local packet =
	Compression.Pack(value)
```

Common fields:

```lua
print(packet.Data)
print(packet.Bytes)
print(packet.Bits)

print(packet.RawBytes)
print(packet.RawBits)

print(packet.SavedBytes)
print(packet.ExpandedBytes)
print(packet.ByteDelta)

print(packet.SavedBits)
print(packet.ExpandedBits)
print(packet.BitDelta)

print(packet.UsefulBits)
print(packet.PhysicalBits)
print(packet.PaddingBits)

print(packet.ValueType)
print(packet.Codec)

print(packet.Ratio)
print(packet.SavingsPercent)
print(packet.ExpansionPercent)
print(packet.BitSavingsPercent)
print(packet.BitExpansionPercent)

print(packet.IsSmaller)
print(packet.IsPhysicallySmaller)
print(packet.IsBitSmaller)
```

Not every field is meaningful for every packet, so some metadata can be `nil`.

v2.3.2 makes byte-level and bit-level accounting explicit. `ByteDelta` compares physical encoded bytes with the raw byte estimate, while `BitDelta` compares useful encoded bits with the raw bit estimate. This prevents bit-packing wins from being reported as physical byte savings when the final `buffer` still occupies the same number of bytes.

---

## Useful Bits vs Physical Bits

Roblox `buffer` storage is byte-addressed.

A standalone boolean therefore still physically occupies at least one byte even though only one bit is meaningful.

For example:

```text
Raw boolean:
8 physical bits

Compressed boolean:
1 useful bit
8 physical bits
7 unused physical bits
```

The v2.3.x metadata keeps these concepts separate:

```lua
packet.UsefulBits
packet.PhysicalBits
packet.PaddingBits
```

This is especially useful for bit-packed tables and schemas.

---

# Supported Types

`Compression.Pack()` supports the following top-level value categories:

```text
nil
boolean
number
string
buffer
table

Vector2
Vector3
Color3
CFrame

UDim
UDim2
Rect
NumberRange
BrickColor
DateTime
```

Example:

```lua
Compression.Pack(true)
Compression.Pack(123)
Compression.Pack("Hello")
Compression.Pack(buffer.create(64))
Compression.Pack(Vector3.new(1, 2, 3))
Compression.Pack(UDim2.new(0.5, 0, 1, -50))
Compression.Pack(DateTime.now())
```

---

# Boolean Compression

A boolean only contains two possible states.

```lua
local packet =
	Compression.Pack(true)

print(packet.Codec)
print(packet.Bytes)
print(packet.Bits)
```

Example:

```text
Codec: CompactBoolean1Bit
Physical Bytes: 1 B
Useful Bits: 1 b
```

This distinction becomes more valuable inside arrays because many booleans can share bytes.

---

# Number Compression

Luau numbers normally use 64-bit floating point storage.

Compression detects special numeric patterns and uses smaller exact encodings when possible.

Examples:

```lua
Compression.Pack(0)
Compression.Pack(1)
Compression.Pack(-1)

Compression.Pack(100)
Compression.Pack(1_000_000)
Compression.Pack(-123456)

Compression.Pack(12.375)
Compression.Pack(123.456789)

Compression.Pack(1e100)
Compression.Pack(0.000001)
```

Possible internal paths include:

```text
Zero
One
Negative One
UInt
Int
Power10
Float32
Decimal
Float64 fallback
```

---

## Zero

```lua
local packet =
	Compression.Pack(0)
```

Measured example:

```text
8 B -> 1 B
87.50% saved
```

---

## Compact integers

Small and medium integers use variable-width representations.

Example:

```lua
local packet =
	Compression.Pack(100)
```

Measured example:

```text
8 B -> 2 B
75.00% saved
```

---

## Compact decimals

Some decimal values can be represented exactly as an integer plus decimal scale.

Example:

```lua
local packet =
	Compression.Pack(
		123.456789
	)
```

Measured example:

```text
Codec: CompactDecimal
8 B -> 6 B
25.00% saved
```

---

## Float32

Float32 is used only when converting to Float32 and back produces exactly the same Luau number.

The library does not silently reduce precision just to save bytes.

---

## Power-of-ten values

Values such as:

```lua
1e12
1e100
0.000001
```

can use specialized compact representations.

A measured `1e100` result:

```text
8 B -> 3 B
62.50% saved
```

---

# String Compression

Use:

```lua
local compressed =
	Compression.CompressString(value)

local restored =
	Compression.DecompressString(
		compressed
	)
```

Inspect the selected mode:

```lua
print(
	Compression.StringMode(
		compressed
	)
)
```

Current strategies:

```text
Auto
Raw
Numeric4
Identifier6
ASCII7
LZ
```

---

## Raw

Force raw string handling:

```lua
local compressed =
	Compression.CompressString(
		value,
		{
			StringStrategy = "Raw",
		}
	)
```

Depending on the bytes, Raw may be a direct passthrough or framed raw representation.

---

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
local compressed =
	Compression.CompressString(
		"123456789012345678901234567890",
		{
			StringStrategy = "Numeric4",
		}
	)
```

Measured:

```text
30 B -> 17 B
43.33% saved
```

---

## Identifier6

Optimized for identifier-like strings using:

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

Measured:

```text
38 B -> 31 B
18.42% saved
```

---

## ASCII7

Stores compatible characters using 7-bit symbols.

Measured example:

```text
47 B -> 44 B
6.38% saved
```

---

## LZ

Useful for repeated text:

```lua
local value =
	string.rep(
		"PlayerDataCoins",
		64
	)

local compressed =
	Compression.CompressString(
		value
	)
```

Measured examples:

```text
400 B -> 26 B
93.50% saved
```

and:

```text
900 B -> 47 B
94.78% saved
```

---

## String statistics

```lua
local stats =
	Compression.StringStats(value)

print(stats.Mode)
print(stats.RawBytes)
print(stats.Bytes)
print(stats.SavedBytes)
print(stats.ExpandedBytes)
print(stats.SavingsPercent)
print(stats.ExpansionPercent)
```

Formatted report:

```lua
Compression.PrintStringStats(
	value
)
```

---

# Buffer Compression

Use:

```lua
local compressed =
	Compression.CompressBuffer(value)

local restored =
	Compression.DecompressBuffer(
		compressed
	)
```

Mode:

```lua
print(
	Compression.BufferMode(
		compressed
	)
)
```

Frame version:

```lua
print(
	Compression.BufferFrameVersion(
		compressed
	)
)
```

Current buffer strategies:

```text
Auto
Raw
LZ
Sparse
Nibble
```

Current output modes include:

| Mode | Purpose |
| --- | --- |
| `RawPassthrough` | Keeps original bytes when compression is not smaller |
| `Raw` | Framed raw representation |
| `Zero` | All bytes are zero |
| `Fill` | One repeated byte |
| `SparseZero` | Mostly zero bytes |
| `SparsePower2` | Sparse powers-of-two values |
| `Nibble4` | Values fit in low four bits |
| `NibbleHigh4` | Values fit in high four bits |
| `LZ` | Repeated binary sequences |

---

## Zero buffers

```lua
local value =
	buffer.create(100)

local compressed =
	Compression.CompressBuffer(
		value
	)
```

Measured:

```text
100 B -> 3 B
97.00% saved
```

---

## Fill buffers

```lua
local value =
	buffer.create(100)

buffer.fill(
	value,
	0,
	123
)

local compressed =
	Compression.CompressBuffer(
		value
	)
```

Measured:

```text
100 B -> 4 B
96.00% saved
```

---

## SparseZero

```lua
local value =
	buffer.create(64)

buffer.writeu8(value, 0, 25)
buffer.writeu8(value, 20, 50)
buffer.writeu8(value, 40, 75)
buffer.writeu8(value, 63, 100)
```

Measured:

```text
64 B -> 15 B
76.56% saved
```

---

## SparsePower2

Optimized for sparse values such as:

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

Measured:

```text
64 B -> 14 B
78.12% saved
```

---

## Nibble4

Nibble4 targets byte values in:

```text
0 - 15
```

Two four-bit values can share one byte.

---

## NibbleHigh4

Targets:

```text
0
16
32
48
...
240
```

---

## Auto can beat a forced mode

If a nibble-compatible buffer is also highly repetitive, Auto may choose LZ because the final LZ result is smaller.

This is expected.

The compressor is trying to minimize the final payload, not merely choose the first valid specialized codec.

---

## LZ buffers

Repeated binary structures can compress heavily.

Measured:

```text
512 B -> 53 B
89.65% saved
```

---

## Random data

Random or encrypted-looking data may not compress.

Measured example:

```text
Raw:        256 B
Compressed: 256 B
Mode:       RawPassthrough
```

That is preferable to expanding the payload.

---

## Buffer statistics

```lua
local stats =
	Compression.BufferStats(value)

print(stats.Mode)
print(stats.RawBytes)
print(stats.Bytes)
print(stats.SavedBytes)
print(stats.ExpandedBytes)
```

Formatted output:

```lua
Compression.PrintBufferStats(
	value
)
```

---

# Roblox Datatypes

Compression v2.3.2 supports these Roblox datatypes directly:

```text
Vector2
Vector3
Color3
CFrame
UDim
UDim2
Rect
NumberRange
BrickColor
DateTime
```

---

## Vector2

```lua
local packet =
	Compression.Pack(
		Vector2.new(
			123.5,
			-456.25
		)
	)
```

Exact Float32 values can use an F32 path.

Measured test:

```text
16 B -> 9 B
43.75% saved
```

---

## Vector3

```lua
local packet =
	Compression.Pack(
		Vector3.new(
			100,
			200,
			300
		)
	)
```

Measured test:

```text
24 B -> 9 B
62.50% saved
```

A smaller `Vector3.new(1, 2, 3)` Auto case measured:

```text
24 B -> 6 B
75.00% saved
```

---

## Color3

```lua
local packet =
	Compression.Pack(
		Color3.fromRGB(
			100,
			150,
			255
		)
	)
```

Possible exact representations include:

```text
RGB8
Float32
Float64
```

The encoder only uses a smaller representation when it restores the same value.

Measured RGB8-compatible example:

```text
12 B -> 4 B
66.67% saved
```

---

## CFrame

```lua
local packet =
	Compression.Pack(
		CFrame.new(
			100,
			200,
			300
		)
	)
```

Measured position-only example:

```text
96 B -> 18 B
81.25% saved
```

A small identity-rotation CFrame measured:

```text
96 B -> 15 B
84.38% saved
```

Rotated example:

```text
96 B -> 48 B
50.00% saved
```

---

## UDim

```lua
local packet =
	Compression.Pack(
		UDim.new(
			0.5,
			12
		)
	)
```

`UDim` is supported both by the generic tagged encoder and the Schema API.

---

## UDim2

```lua
local packet =
	Compression.Pack(
		UDim2.new(
			0.5,
			-100,
			1,
			-25
		)
	)
```

Useful for UI configuration or serialized layout state.

---

## Rect

```lua
local packet =
	Compression.Pack(
		Rect.new(
			0,
			0,
			1920,
			1080
		)
	)
```

---

## NumberRange

```lua
local packet =
	Compression.Pack(
		NumberRange.new(
			1.25,
			100
		)
	)
```

---

## BrickColor

```lua
local packet =
	Compression.Pack(
		BrickColor.new(21)
	)
```

---

## DateTime

```lua
local packet =
	Compression.Pack(
		DateTime.now()
	)
```

DateTime is stored using an exact millisecond timestamp representation.

---

# Table Compression

Basic use:

```lua
local data = {
	Coins = 1000,
	Rebirths = 10,
	Enabled = true,
}

local packet =
	Compression.CompressTablePacket(
		data
	)

local restored =
	Compression.DecompressTable(
		packet
	)
```

Raw buffer-only form:

```lua
local compressed =
	Compression.CompressTable(data)

local restored =
	Compression.DecompressTable(
		compressed
	)
```

Inspect the representation:

```lua
print(
	Compression.TableMode(
		packet
	)
)

print(
	Compression.IsCompactTable(
		packet
	)
)
```

---

## Table strategies

Three strategies are available:

```text
Auto
Compact
Dynamic
```

### Auto

Recommended default.

```lua
local packet =
	Compression.CompressTablePacket(
		data,
		{
			TableStrategy = "Auto",
		}
	)
```

Auto evaluates the available table representations and chooses the smaller valid result.

---

### Compact

```lua
local packet =
	Compression.CompressTablePacket(
		data,
		{
			TableStrategy = "Compact",
		}
	)
```

If a value cannot be represented by the Compact format, v2.3.x can fall back to Dynamic instead of breaking the entire table encode.

---

### Dynamic

```lua
local packet =
	Compression.CompressTablePacket(
		data,
		{
			TableStrategy = "Dynamic",
		}
	)
```

Dynamic tables use tagged values and support the broader datatype set.

---

# Table Key Mapping

Repeated nested string keys can be stored once and referenced using compact IDs.

Example:

```lua
local pets = {
	{
		Name = "Dog",
		Level = 1,
		Power = 2,
		Equipped = true,
	},

	{
		Name = "Cat",
		Level = 5,
		Power = 4,
		Equipped = false,
	},

	{
		Name = "Dragon",
		Level = 25,
		Power = 100,
		Equipped = true,
	},
}
```

Without mapping, these keys are repeated:

```text
Name
Level
Power
Equipped
```

for every record.

Enable mapping:

```lua
local packet =
	Compression.CompressTablePacket(
		pets,
		{
			TableStrategy = "Compact",
			TableKeyMapping = true,
		}
	)
```

Possible mapped modes:

```text
CompactMappedMixedArray
CompactMappedStringMap
CompactMappedMap
```

Mapping is only selected when the mapped representation is actually smaller than normal Compact.

---

## Mapping statistics

```lua
local stats =
	Compression.TableStats(
		pets,
		{
			TableKeyMapping = true,
		}
	)

print(stats.Mapped)
print(stats.MappedKeys)
print(stats.AvailableMappedKeys)

print(stats.UnmappedCompactBytes)
print(stats.MappedCompactBytes)

print(stats.MappingSavedBytes)
print(stats.MappingSavingsPercent)
```

---

# Compact Arrays

Current Compact table array modes include:

```text
CompactBoolArray
CompactUIntArray
CompactIntArray
CompactFloatArray
CompactFloat32Array
CompactStringArray
CompactMixedArray
CompactUIntDeltaArray
CompactIntDeltaArray
CompactRLEArray
```

---

## Boolean arrays

```lua
local data = {
	true,
	false,
	true,
	true,
	false,
	true,
}
```

Booleans are bit-packed.

Measured:

```text
Raw estimate: 54 B
Compressed:   3 B
Savings:      94.44%
```

---

## UInt arrays

```lua
local data = {
	1,
	2,
	3,
	4,
	5,
	6,
}
```

Unsigned integers use variable-width encoding.

Measured example:

```text
160 B -> 12 B
92.50% saved
```

---

## Int arrays

```lua
local data = {
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

Measured:

```text
176 B -> 14 B
92.05% saved
```

---

## Float32 arrays

Values that all survive exact Float32 round trips can use:

```text
CompactFloat32Array
```

Measured:

```text
64 B -> 19 B
70.31% saved
```

If one value requires full precision, the array uses a Float64-compatible path.

---

## Delta arrays

Sequential values can store the first value followed by compact differences.

```lua
local data = {
	1000,
	1001,
	1002,
	1003,
	1004,
	1005,
}
```

Possible mode:

```text
CompactUIntDeltaArray
```

Measured:

```text
112 B -> 11 B
90.18% saved
```

---

## Run-length arrays

Repeated values can use RLE:

```lua
local data = {
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

Possible mode:

```text
CompactRLEArray
```

Measured:

```text
160 B -> 14 B
91.25% saved
```

---

# Dynamic Typed Arrays

Dynamic tables recognize homogeneous arrays for several Roblox datatypes.

Current typed-array modes include:

```text
Vector2F32Array
Vector2F64Array

Vector3F32Array
Vector3F64Array

Color3RGB8Array
Color3F32Array
Color3F64Array

UDimArray
UDim2Array
NumberRangeArray
BrickColorArray
RectArray
DateTimeArray
```

Example:

```lua
local positions = {
	Vector3.new(1, 2, 3),
	Vector3.new(4, 5, 6),
	Vector3.new(7, 8, 9),
}

local packet =
	Compression.CompressTablePacket(
		positions,
		{
			TableStrategy = "Dynamic",
		}
	)

print(
	Compression.TableMode(
		packet
	)
)
```

A homogeneous Vector3 array can avoid repeating the Vector3 type tag for every element.

---

# Dynamic String Dictionary

Dynamic payloads can detect repeated strings and store them once in a shared dictionary.

```lua
local packet =
	Compression.Encode(
		data,
		{
			UseStringDictionary = true,
			DictionaryMinUses = 2,
			MaxDictionaryEntries = 255,
		}
	)
```

Disable it:

```lua
UseStringDictionary = false
```

v2.3.2 rejects malformed payloads containing duplicate dictionary entries.

---

# Inline Small Numbers

Dynamic tables contain special inline tags for common small integers.

This reduces overhead for values such as:

```lua
{
	Level = 5,
	Tier = 2,
	Amount = 12,
	Index = 3,
}
```

Small unsigned integers and a range of small negatives can be represented directly in the tag byte instead of requiring an additional VarInt/VarUInt byte.

---

# Buffers Inside Tables

Buffers can be nested inside tables:

```lua
local payload =
	buffer.create(64)

for index = 0, 15 do
	buffer.writeu32(
		payload,
		index * 4,
		1000
	)
end

local packet =
	Compression.Pack({
		UserId = 123456789,
		Buffer = payload,
		Active = true,
	})
```

Measured table-with-buffer test:

```text
91 B -> 38 B
58.24% saved
```

---

# Roblox Types Inside Tables

Roblox datatypes can be nested:

```lua
local data = {
	Direction =
		Vector2.new(
			1,
			-1
		),

	Position =
		Vector3.new(
			100,
			200,
			300
		),

	Color =
		Color3.fromRGB(
			50,
			150,
			250
		),

	Transform =
		CFrame.new(
			10,
			20,
			30
		),
}
```

Measured:

```text
179 B -> 105 B
41.34% saved
```

Newer v2.3.x Dynamic tables also support:

```text
UDim
UDim2
Rect
NumberRange
BrickColor
DateTime
```

---

# Bnum Compatibility

If a big-number library exposes its value as a compact Roblox `buffer`, it can use the normal buffer compression pipeline.

Example:

```lua
local Bnum =
	require(
		game.ReplicatedStorage.Bnum
	)

local value =
	Bnum.new(
		1,
		3
	)

local compressed =
	Compression.CompressBuffer(
		value
	)

local restored =
	Compression.DecompressBuffer(
		compressed
	)
```

A previous measured example:

```text
Raw:        12 B
Compressed: 5 B
Mode:       SparsePower2
Savings:    58.33%
```

The selected buffer mode depends on the actual buffer contents.

---

# Schemas

Schemas are useful when the exact structure of the payload is known ahead of time.

Example:

```lua
local PlayerSchema =
	Compression.Schema({
		Coins =
			Compression.UInt(),

		Rebirths =
			Compression.UInt(),

		Enabled =
			Compression.Bool(),

		Name =
			Compression.CompressedString(),

		Position =
			Compression.Vector3(),

		UIPosition =
			Compression.UDim2(),

		LastSeen =
			Compression.DateTime(),
	}, 1)
```

Encode:

```lua
local packet =
	PlayerSchema:Encode({
		Coins = 1_000_000,
		Rebirths = 25,
		Enabled = true,
		Name = "Player_001",
		Position = Vector3.new(1, 2, 3),
		UIPosition = UDim2.new(0.5, 0, 1, -100),
		LastSeen = DateTime.now(),
	})
```

Decode:

```lua
local restored =
	PlayerSchema:Decode(
		packet
	)
```

Schema packets carry the schema version and reject incompatible schema versions.

---

# Descriptor API

v2.3.2 includes the following descriptor constructors:

| Descriptor | Purpose |
| --- | --- |
| `Compression.Bool()` | Boolean |
| `Compression.UInt()` | Unsigned integer |
| `Compression.Int()` | Signed integer |
| `Compression.Float()` | 64-bit number |
| `Compression.String()` | String |
| `Compression.CompressedString(options?)` | String using Compression string codecs |
| `Compression.Buffer(options?)` | Buffer |
| `Compression.Vector2()` | Vector2 |
| `Compression.Vector3()` | Vector3 |
| `Compression.Color3()` | Lossless Color3 |
| `Compression.CFrame()` | CFrame |
| `Compression.UDim()` | UDim |
| `Compression.UDim2()` | UDim2 |
| `Compression.Rect()` | Rect |
| `Compression.NumberRange()` | NumberRange |
| `Compression.BrickColor()` | BrickColor |
| `Compression.DateTime()` | DateTime |
| `Compression.Array(descriptor)` | Array |
| `Compression.Object(fields)` | Structured object |
| `Compression.Optional(descriptor)` | Optional value |
| `Compression.Quantized(min, max, bits)` | Quantized number |
| `Compression.QuantizedVector3(min, max, bits)` | Quantized Vector3 |

---

## Lossless Color3 schema descriptor

v2.3.x fixed the older schema Color3 behavior.

The schema descriptor now adaptively chooses an exact representation:

```text
RGB8
Float32
Float64
```

This allows arbitrary Color3 values to round-trip without silently quantizing them to RGB8.

---

# Optional Fields

```lua
local Schema =
	Compression.Schema({
		Coins =
			Compression.UInt(),

		Note =
			Compression.Optional(
				Compression.String()
			),
	}, 1)
```

Both are valid:

```lua
Schema:Encode({
	Coins = 100,
	Note = "Hello",
})
```

and:

```lua
Schema:Encode({
	Coins = 100,
})
```

Required fields cannot be silently removed by a delta packet in v2.3.2.

---

# Schema Delta Encoding

Schemas support compact change packets.

```lua
local Schema =
	Compression.Schema({
		Coins =
			Compression.UInt(),

		Level =
			Compression.UInt(),

		Enabled =
			Compression.Bool(),
	}, 1)
```

Old value:

```lua
local previous = {
	Coins = 100,
	Level = 5,
	Enabled = true,
}
```

New value:

```lua
local current = {
	Coins = 150,
	Level = 5,
	Enabled = true,
}
```

Encode only the changes:

```lua
local delta =
	Schema:EncodeDelta(
		previous,
		current
	)
```

Apply them:

```lua
local restored =
	Schema:DecodeDelta(
		previous,
		delta
	)
```

v2.3.2 validates both changed and unchanged schema state, and required fields cannot be removed through delta encoding.

---

# Descriptor Inference

Generate a descriptor from a sample value:

```lua
local descriptor =
	Compression.InferDescriptor({
		Coins = 100,
		Enabled = true,
		Name = "Player",
	})
```

Or:

```lua
local descriptor =
	Compression.AutoDescriptor(
		value
	)
```

v2.3.x recognizes:

```text
UDim
UDim2
Rect
NumberRange
BrickColor
DateTime
```

in addition to the older primitive and Roblox types.

Object-array inference also validates that every object has a compatible nested descriptor shape.

For example, this is compatible:

```lua
{
	{
		Coins = 100,
		Enabled = true,
	},

	{
		Coins = 200,
		Enabled = false,
	},
}
```

while incompatible object structures are rejected instead of producing a descriptor that will fail later.

---

# Quantized Values

Quantization is intentionally different from the normal lossless codecs.

Use it only when bounded precision is acceptable.

Example:

```lua
local Health =
	Compression.Quantized(
		0,
		100,
		8
	)
```

Vector3:

```lua
local Position =
	Compression.QuantizedVector3(
		Vector3.new(
			-1000,
			-1000,
			-1000
		),

		Vector3.new(
			1000,
			1000,
			1000
		),

		16
	)
```

The constructors validate invalid ranges in v2.3.x.

---

# Integrity Hashes

Packets can include an FNV-1a integrity hash.

```lua
local packet =
	Compression.Encode(
		data,
		{
			Mode = "BinaryWithHash",
		}
	)
```

Verify:

```lua
print(
	Compression.Verify(
		packet
	)
)
```

Or inspect:

```lua
print(packet.Hash)
```

Hash verification is intended to detect accidental corruption, not provide cryptographic authentication.

---

# Statistics and Analysis

## AutoStats

```lua
local stats =
	Compression.AutoStats(value)

print(stats.ValueType)
print(stats.Codec)

print(stats.RawBytes)
print(stats.Bytes)

print(stats.SavedBytes)
print(stats.ExpandedBytes)
print(stats.ByteDelta)

print(stats.UsefulBits)
print(stats.PhysicalBits)
print(stats.PaddingBits)

print(stats.SavedBits)
print(stats.ExpandedBits)
print(stats.BitDelta)

print(stats.SavingsPercent)
print(stats.ExpansionPercent)
print(stats.BitSavingsPercent)
print(stats.BitExpansionPercent)
```

Formatted:

```lua
Compression.PrintAutoStats(
	value
)
```

---

## NumberStats

```lua
local stats =
	Compression.NumberStats(
		123.456789
	)
```

Includes:

```text
RawBytes
RawBits
Bytes
Bits
UsefulBits
PhysicalBits
SavedBytes
SavedBits
ExpandedBytes
ExpandedBits
SavingsPercent
ExpansionPercent
Ratio
IsSmaller
```

---

## TableStats

```lua
local stats =
	Compression.TableStats(data)

print(stats.Mode)
print(stats.Format)

print(stats.RawBytes)
print(stats.Bytes)

print(stats.Mapped)
print(stats.MappedKeys)
print(stats.AvailableMappedKeys)

print(stats.MappedCompactBytes)
print(stats.UnmappedCompactBytes)
print(stats.MappingSavedBytes)
print(stats.MappingSavingsPercent)

print(stats.UsefulBits)
print(stats.PhysicalBits)
print(stats.PaddingBits)
```

Formatted:

```lua
Compression.PrintTableStats(
	data
)
```

---

## Generic Stats

```lua
local packet =
	Compression.Pack(value)

local stats =
	Compression.Stats(packet)
```

---

## Analyze

```lua
local analysis =
	Compression.Analyze(value)

print(analysis.Codec)
print(analysis.Bytes)
print(analysis.RawBytes)
```

---

## Table structure

Inspect the contents of a nested table:

```lua
local structure =
	Compression.TableStructure(data)

print(structure.Tables)
print(structure.Arrays)
print(structure.Maps)

print(structure.Booleans)
print(structure.Numbers)
print(structure.Strings)
print(structure.Buffers)

print(structure.Vector2s)
print(structure.Vector3s)
print(structure.Color3s)
print(structure.CFrames)

print(structure.UDims)
print(structure.UDim2s)
print(structure.Rects)
print(structure.NumberRanges)
print(structure.BrickColors)
print(structure.DateTimes)
```

---

# Bit Layout Analysis

Schemas can show exactly how their bits are used.

```lua
local layout =
	Schema:AnalyzeBits(data)

print(layout.HeaderBits)
print(layout.UsefulBits)
print(layout.PaddingBits)
print(layout.PhysicalBits)
print(layout.PhysicalBytes)
```

Formatted report:

```lua
Schema:PrintBitLayout(data)
```

This is useful when tuning frequently serialized structures.

---

# Configuration

Common options:

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

	TableKeyMapping = true,
	MappedKeyMinUses = 2,
	MaxMappedKeys = 255,

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

Not every option needs to be specified.

The normal high-level call can simply use defaults:

```lua
local packet =
	Compression.Pack(value)
```

---

## StringStrategy

```text
Auto
Raw
LZ
ASCII7
Identifier6
Numeric4
```

---

## BufferStrategy

```text
Auto
Raw
LZ
Sparse
Nibble
```

---

## TableStrategy

```text
Auto
Compact
Dynamic
```

---

## Mode

```text
Binary
BinaryWithHash
```

---

# Public API Overview

v2.3.2 exposes 80 public functions.

## Strings

```text
CompressString
DecompressString
StringMode
StringStats
PrintStringStats
TryDecompressString
CompressStringSmart
DecompressStringSmart
```

## Buffers

```text
CompressBuffer
DecompressBuffer
BufferMode
BufferFrameVersion
BufferStats
PrintBufferStats
TryDecompressBuffer
CompressBufferSmart
DecompressBufferSmart
```

## Generic / Adaptive

```text
Encode
Decode
Compress
Decompress
Auto
AutoDecompress
TryAuto
CanAuto
TryAutoDecompress
AutoStats
PrintAutoStats

Pack
Unpack
TryPack
TryUnpack
Size
Codec
```

## Numbers

```text
CompressNumber
DecompressNumber
NumberStats
```

## Tables

```text
CompressTable
CompressTablePacket
DecompressTable
TryDecompressTable
IsCompactTable
TableMode
TableBytes
TableEntries
TableStructure
TableStats
PrintTableStats
EstimateRawBytes
```

## Schemas

```text
Schema
Optional

Bool
UInt
Int
Float
String
CompressedString
Buffer

Vector2
Vector3
Color3
CFrame
UDim
UDim2
Rect
NumberRange
BrickColor
DateTime

Array
Object
Quantized
QuantizedVector3

InferDescriptor
AutoDescriptor
```

## Integrity / Analysis

```text
Hash
Verify
FormatBytes
Stats
Analyze
Version
```

---

## AllowExpansion

`AllowExpansion` controls whether an explicitly requested compression strategy is allowed to return a payload larger than the raw representation.

Default:

```lua
AllowExpansion = false
```

In v2.3.2, forced string strategies such as `Numeric4`, `Identifier6`, `ASCII7`, and `LZ`, plus forced buffer `LZ`, respect this setting consistently.

With the default behavior:

```lua
local compressed =
	Compression.CompressString(
		"abc",
		{
			StringStrategy = "LZ",
			AllowExpansion = false,
		}
	)
```

the compressor can fall back to raw when the requested codec would make the payload larger.

To explicitly allow the requested codec even when it expands the payload:

```lua
local compressed =
	Compression.CompressString(
		"abc",
		{
			StringStrategy = "LZ",
			AllowExpansion = true,
		}
	)
```

`Auto` still prefers the smallest safe representation.

# Backward Compatibility

v2.3.2 uses:

```text
Binary format: 22
```

v2.3.2 intentionally keeps the same binary format as v2.3.1 and v2.3.0.

The decoder retains support for compatible earlier formats handled by the v2.x decoder. v2.3.2 also includes recovery for the affected short `SparsePower2` representation produced by compatible v2.3.1 data.

Because the wire format remains `22`, the v2.3.2 bug-fix release does not require a new storage-format revision.

As with any serialization system, test persisted production data before deploying a codec or schema change.

---

# v2.3.2 Patch Notes

v2.3.2 is a compatibility-focused bug-fix and compression-handling release built on the v2.3.1 API.

It keeps:

```text
Public API: 80 functions
Binary format: 22
```

while improving strategy selection, buffer correctness, packet statistics, and malformed-payload handling.

## Safer forced string strategies

Explicit string strategies now respect `AllowExpansion` consistently.

Covered strategies:

```text
Numeric4
Identifier6
ASCII7
LZ
```

With:

```lua
AllowExpansion = false
```

a forced codec can fall back to raw if its encoded payload would be larger.

With:

```lua
AllowExpansion = true
```

the explicitly selected codec is allowed to expand the payload.

This behavior is regression-tested for every listed string strategy.

---

## Buffer LZ expansion handling

Forced buffer `LZ` now follows the same expansion policy.

```lua
local compressed =
	Compression.CompressBuffer(
		value,
		{
			BufferStrategy = "LZ",
			AllowExpansion = false,
		}
	)
```

If LZ is larger, the raw representation is preferred.

Setting `AllowExpansion = true` allows the requested LZ frame even when it is larger.

---

## SparsePower2 short-buffer fix

v2.3.1 had an edge case where a short `SparsePower2` buffer could be emitted in a bitmap representation that the short-buffer decoder interpreted as the compact positional representation.

v2.3.2 removes that ambiguous encoder path.

The regression suite covers:

```text
short SparsePower2 <= 7 entries
short SparsePower2 > 7 entries
legacy v2.3.1 short SparsePower2 recovery
```

This keeps the optimized short representation for the safe case while avoiding the ambiguous form.

---

## Legacy v2.3.1 SparsePower2 recovery

Compatible affected v2.3.1 short `SparsePower2` payloads can be recovered by the v2.3.2 decoder when their representation can be identified safely.

This is a decoder compatibility improvement and does not change binary format `22`.

---

## SparsePower2 validation

Malformed `SparsePower2` bitmap padding is rejected instead of being silently accepted.

The v2.3.2 regression test intentionally feeds an invalid payload and confirms decompression fails with a sparse-power2 padding error.

---

## More accurate packet statistics

v2.3.2 separates physical byte savings from useful-bit savings more clearly.

Packet metadata now includes or consistently reports:

```text
RawBytes
RawBits

SavedBytes
ExpandedBytes
ByteDelta

SavedBits
ExpandedBits
BitDelta

UsefulBits
PhysicalBits
PaddingBits

SavingsPercent
ExpansionPercent
BitSavingsPercent
BitExpansionPercent
```

This is especially important for standalone booleans.

Example:

```text
Raw:
1 byte
8 bits

Compressed boolean:
1 physical byte
1 useful bit
7 padding bits

ByteDelta: 0
BitDelta: 7
```

The boolean therefore saves `87.50%` of useful bits without falsely claiming that a byte-addressed Roblox `buffer` physically occupies one eighth of a byte.

---

## Passthrough accounting

Raw/passthrough packets use the actual raw representation as their comparison baseline.

This keeps `RawBytes`, ratios, expansion values, and savings values consistent when compression correctly chooses not to transform incompressible data.

---

## BinaryWithHash regression coverage

v2.3.2 verifies both sides of the integrity path:

```text
valid BinaryWithHash packet -> restores successfully
corrupted BinaryWithHash packet -> rejected
```

Hash verification continues to detect accidental corruption rather than provide cryptographic authentication.

---

## Regression validation

The v2.3.2 Studio type/regression suite completed with:

```text
Module Loaded: true
Compression Version: 2.3.2
Register Regression: PASSED
Tests Passed: 75
Status: ALL PASSED
```

The suite covers primitives, strings, buffers, Roblox datatypes, arrays, maps, nested tables, Bnum-compatible buffers, packet statistics, expansion fallback, SparsePower2 compatibility, invalid payload rejection, and hash verification.

---

## Format compatibility

v2.3.2 remains:

```text
Format 22
```

so it remains directly compatible with the v2.3.x binary format while fixing codec-selection and decoder edge cases.

---

# Version

```lua
print(
	Compression.Version()
)
```

Expected:

```text
2.3.2
```

---

# Recommended Starting Point

For most code:

```lua
local packet =
	Compression.Pack(value)

local restored =
	Compression.Unpack(packet)
```

For debugging:

```lua
local stats =
	Compression.AutoStats(value)

print(stats.Codec)
print(stats.RawBytes)
print(stats.Bytes)
print(stats.SavingsPercent)
```

For fixed structures:

```lua
local Schema =
	Compression.Schema({
		Coins =
			Compression.UInt(),

		Enabled =
			Compression.Bool(),
	}, 1)
```

For repeated nested records:

```lua
local packet =
	Compression.CompressTablePacket(
		data,
		{
			TableStrategy = "Auto",
			TableKeyMapping = true,
		}
	)
```

For calls that should not throw:

```lua
local ok, packet, err =
	Compression.TryPack(value)
```

That covers the main v2.3.2 workflow.
