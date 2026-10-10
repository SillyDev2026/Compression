# Compression

**Current source version: v2.6.5 (proposed patch)**  
**Binary format: 25**  
**Public API: 85 functions**

Compression is a high-performance binary serialization and adaptive data-compression library for Roblox/Luau, built to reduce network and storage payloads without sacrificing reliability, type safety, or exact restoration.

v2.6.4 analyzes supported values and selects the smallest safe representation available. Specialized codecs can be followed by canonical Huffman entropy compression, while expansion-safe Auto paths fall back to raw data whenever a candidate would make the payload larger.

It supports primitive values, Roblox datatypes, strings, buffers, arrays, maps, deeply nested tables, schemas, delta packets, repeated-string dictionaries, table-key mapping, canonical Huffman entropy coding, integrity hashes, bit-layout analysis, corruption guards, decode-size limits, and adaptive codec selection.

The main rule of the library is:

> Use the smallest safe representation available. If compression would make the value larger, preserve a raw or passthrough representation when possible.

For new code, the simplest API is:

```lua
local packet = Compression.Pack(value)
local restored = Compression.Unpack(packet)
```

The older `Compression.Auto()` / `Compression.AutoDecompress()` API remains supported and maps to the same adaptive compression path.

---

## v2.6.5 — canonical Huffman decoding

This maintenance patch retains **binary format 25** and all existing public APIs. It adds three decoder validations:

- Rejects Huffman codebooks that advertise more distinct symbols than the number of decoded bytes.
- Rejects encoded bit lengths that cannot represent the advertised output size with the supplied Huffman code lengths.
- Rejects nonzero padding bits in the final Huffman byte. Such packets were previously accepted even though the extra bits are not part of the encoded output.

Existing well-formed v2.6.4 packets still use the same on-wire format and should decode identically. This does **not** change compression ratios or establish a performance gain.

Run `tests/HuffmanCanonicalRegression.server.lua` under Roblox Studio with the library as a sibling ModuleScript named `Compress`. It checks a valid roundtrip, an empty packet and corruption rejection. Run Script Analysis and broader saved-packet compatibility tests before merging. Full `--!strict` validation remains outstanding for the large source file.

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
- [Huffman Entropy Coding](#huffman-entropy-coding)
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
- [Performance Benchmarks](#performance-benchmarks)
- [Backward Compatibility](#backward-compatibility)
- [v2.6.4 Patch Notes](#v264-patch-notes)
- [Version](#version)
- [Download](#download)

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
- Canonical Huffman entropy coding with Auto selection
- Huffman expansion rejection when the full frame is not smaller
- Direct `HuffmanEncode`, `HuffmanDecode`, `TryHuffman`, `IsHuffman`, and `HuffmanStats` APIs
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
  - ZeroRun
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
- Backward decoding support for compatible older binary formats
- Legacy short `SparsePower2` recovery and malformed-padding validation
- Top-level buffer type preservation through entropy framing
- Expansion-safe ZeroRun buffer framing for zero-heavy small and medium buffers
- Allocation-reduced Auto buffer analysis and lazy raw fallback
- Faster canonical Huffman encode/decode hot paths
- Decode-size protection for compressed buffer frames
- Reduced top-level Luau register pressure with v2.6.4 compiler headroom

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

`Pack()` is the recommended high-level call in v2.6.x.

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

The v2.6.x `Try*` APIs return useful error text:

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

The following measurements come from the **Compression v2.6.4 full Huffman/regression suite**.

Compression ratios are input-dependent. These are measured examples, not guaranteed ratios for every value. v2.6.4 completed **132 tests passed, 0 failed, 0 skipped**.

## Primitive numbers

| Value | Raw | Encoded | Saved | Savings |
| --- | ---: | ---: | ---: | ---: |
| `0` | 8 B | **1 B** | 7 B | **87.50%** |
| `1` | 8 B | **1 B** | 7 B | **87.50%** |
| `-1` | 8 B | **1 B** | 7 B | **87.50%** |
| `100` | 8 B | **2 B** | 6 B | **75.00%** |
| `128` | 8 B | **3 B** | 5 B | **62.50%** |
| `1_000_000` | 8 B | **2 B** | 6 B | **75.00%** |
| `-123456` | 8 B | **4 B** | 4 B | **50.00%** |
| `123.125` | 8 B | **5 B** | 3 B | **37.50%** |
| `1e100` | 8 B | **3 B** | 5 B | **62.50%** |

Arbitrary Float64 values such as `math.pi` can remain at 8 bytes when no exact smaller representation exists. Compression does not silently reduce precision.

## Strings

| Example | Selected mode | Raw | Encoded | Approx. savings |
| --- | --- | ---: | ---: | ---: |
| Numeric text | `Numeric4` | 40 B | **22 B** | **45.00%** |
| Identifier-style text | `Identifier6` | 49 B | **39 B** | **20.41%** |
| ASCII text | `ASCII7` | 84 B | **76 B** | **9.52%** |
| Repetitive string | `Huffman/LZ-v2` | 1,280 B | **51 B** | **96.02%** |
| Large repetitive string | `Huffman/LZ-v2` | 3,712 B | **107 B** | **97.12%** |
| Huffman-skewed raw text | `Huffman/RawPassthrough` | 9,200 B | **1,315 B** | **85.71%** |

## Buffers

| Buffer | Selected mode | Raw | Encoded | Approx. savings |
| --- | --- | ---: | ---: | ---: |
| Zero buffer | `Zero` | 512 B | **4 B** | **99.22%** |
| One-byte fill | `Fill` | 512 B | **5 B** | **99.02%** |
| Small aligned Float64 buffer | `ZeroRun` | 12 B | **11 B** | **8.33%** |
| Small aligned `Float64(3)` buffer | `ZeroRun` | 12 B | **5 B** | **58.33%** |
| Sparse zero | `Huffman/SparseZero` | 256 B | **38 B** | **85.16%** |
| Sparse powers-of-two | `Huffman/SparsePower2` | 256 B | **35 B** | **86.33%** |
| Nibble-compatible | `Huffman/Nibble4` | 512 B | **136 B** | **73.44%** |
| Repetitive binary | `Huffman/LZ` | 4,096 B | **142 B** | **96.53%** |
| Huffman-skewed raw bytes | `Huffman/RawPassthrough` | 8,192 B | **1,243 B** | **84.83%** |
| Random/high-entropy | `RawPassthrough` | 2,048 B | **2,048 B** | 0% |

The random-buffer result is intentional: `Auto` rejects candidates that would expand the payload.

## Roblox datatypes

| Type | Raw estimate | Encoded | Savings |
| --- | ---: | ---: | ---: |
| `Vector2.new(12.5, -8.25)` | 16 B | **9 B** | **43.75%** |
| `Vector3.new(100, 0, -25.5)` | 24 B | **8 B** | **66.67%** |
| RGB8-compatible `Color3` | 12 B | **4 B** | **66.67%** |
| position-only `CFrame` | 96 B | **18 B** | **81.25%** |
| rotated `CFrame` | 96 B | **48 B** | **50.00%** |
| `UDim2` example | 24 B | **7 B** | **70.83%** |
| `Rect` example | 32 B | **15 B** | **53.12%** |
| `NumberRange` example | 16 B | **8 B** | **50.00%** |

## Arrays and tables

These values use the test suite's raw-size estimate for the original logical data.

| Value | Raw estimate / no-entropy | v2.6.4 Auto | Selected path |
| --- | ---: | ---: | --- |
| Boolean array | 2,313 B | **34 B** | `CompactBoolArray` + entropy frame |
| UInt delta array | 8,192 B | **93 B** | `CompactUIntDeltaArray` + Huffman |
| Int delta array | 8,192 B | **88 B** | `CompactIntDeltaArray` + Huffman |
| Float32 array | 8,192 B | **546 B** | `CompactFloat32Array` + Huffman |
| String array | 6,707 B | **208 B** | RLE/dynamic + Huffman |
| Vector3 array | 8,192 B | **697 B** | `Vector3F32Array` + Huffman |
| Color3 array | 5,120 B | **144 B** | `Color3RGB8Array` + Huffman |
| DateTime array | 2,048 B | **527 B** | `DateTimeArray` + Huffman |
| Repeated numeric array | 4,800 B | **10 B** | `CompactRLEArray` |

A representative nested player-data table measured:

```text
Entropy=None: 1311 B
Auto/Huffman:  761 B
Saved:         550 B
```

A representative schema measured:

```text
Entropy=None: 1939 B
Auto/Huffman: 1691 B
Entropy saved: 248 B
```

---

# Packet Metadata

Adaptive calls return a packet table.

```lua
local packet = Compression.Pack(value)
```

Common fields include:

```lua
packet.Data
packet.Bytes
packet.Bits
packet.RawBytes
packet.RawBits
packet.SavedBytes
packet.ExpandedBytes
packet.ByteDelta
packet.SavedBits
packet.ExpandedBits
packet.BitDelta
packet.UsefulBits
packet.PhysicalBits
packet.PaddingBits
packet.ValueType
packet.Codec
packet.Ratio
packet.SavingsPercent
packet.ExpansionPercent
packet.BitSavingsPercent
packet.BitExpansionPercent
packet.IsSmaller
packet.IsPhysicallySmaller
packet.IsBitSmaller

-- v2.4+ entropy metadata
packet.Entropy
packet.EntropyBytesBefore
packet.EntropyBytesAfter
packet.EntropySavedBytes
```

`packet.Entropy` is typically `"Huffman"`, `"None"`, or `nil`/not applicable depending on the selected path.

Not every field is meaningful for every packet, so some metadata can be `nil`.

v2.6.4 keeps byte-level and bit-level accounting separate. `ByteDelta` compares physical encoded bytes with the raw byte estimate, while `BitDelta` compares useful encoded bits with the raw bit estimate.

## Useful Bits vs Physical Bits

Roblox `buffer` storage is byte-addressed. A standalone boolean therefore still physically occupies at least one byte even though only one bit is meaningful.

```text
Raw boolean:
8 physical bits

Compressed boolean:
1 useful bit
8 physical bits
7 padding bits
```

Boolean arrays benefit much more because many boolean values share the same bytes. Booleans intentionally bypass Huffman because a binary alphabet is already represented at one useful bit per value in the compact path.

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
local compressed = Compression.CompressString(value)
local restored = Compression.DecompressString(compressed)
```

Inspect the selected mode:

```lua
print(Compression.StringMode(compressed))
```

Current string strategies:

```text
Auto
Raw
Numeric4
Identifier6
ASCII7
LZ
```

The selected first-stage string codec can then be Huffman-coded when entropy coding is enabled and the final Huffman frame is smaller.

## Raw

Keeps the original bytes when specialized codecs would not help. Raw payloads are protected against accidental `HUF1` frame-signature collisions.

## Numeric4

Optimized for numeric text using the supported numeric alphabet. In the v2.6.4 suite, a 40-byte numeric string encoded to 22 bytes.

## Identifier6

Optimized for identifier-style strings such as player keys, stat names, and compact IDs. A 49-byte test encoded to 39 bytes.

## ASCII7

Stores compatible ASCII characters using seven-bit symbols. An 84-byte test encoded to 76 bytes.

## LZ

LZ is the main repeated-sequence string codec. Huffman can then entropy-code the LZ representation.

Measured examples:

```text
1280 B -> 51 B   Huffman/LZ-v2
3712 B -> 107 B  Huffman/LZ-v2
```

## String statistics

```lua
local stats = Compression.StringStats(value)
print(stats.Mode)
print(stats.RawBytes)
print(stats.Bytes)
print(stats.SavedBytes)
print(stats.ExpandedBytes)
print(stats.SavingsPercent)

Compression.PrintStringStats(value)
```

---

# Buffer Compression

Use:

```lua
local compressed = Compression.CompressBuffer(value)
local restored = Compression.DecompressBuffer(compressed)
```

Inspect the selected representation:

```lua
print(Compression.BufferMode(compressed))
print(Compression.BufferFrameVersion(compressed))
```

Current buffer strategies:

```text
Auto
Raw
LZ
Sparse
Nibble
```

Current first-stage output modes include:

| Mode | Purpose |
| --- | --- |
| `RawPassthrough` | Keep original bytes when nothing smaller exists |
| `Raw` | Framed raw representation |
| `Zero` | All bytes are zero |
| `Fill` | One repeated byte |
| `ZeroRun` | Removes one profitable contiguous zero run and reconstructs it exactly |
| `SparseZero` | Mostly-zero buffers |
| `SparsePower2` | Sparse powers-of-two values |
| `Nibble4` | Values fit in low four bits |
| `NibbleHigh4` | Values fit in high four bits |
| `LZ` | Repeated binary sequences |

After the first-stage codec, canonical Huffman can be selected automatically when it produces a smaller complete frame.

## Auto selection

`Auto` compares available representations and keeps the smallest safe result. It does not force compression merely because a codec is valid.

Measured v2.6.4 examples:

```text
Zero:              512 B ->    4 B
Fill:              512 B ->    5 B
ZeroRun small:       12 B ->   11 B
ZeroRun Float64(3):  12 B ->    5 B
SparseZero:        256 B ->   38 B  with Huffman
SparsePower2:      256 B ->   35 B  with Huffman
Nibble4:           512 B ->  136 B  with Huffman
LZ pattern:       4096 B ->  142 B  with Huffman
Huffman skew:     8192 B -> 1243 B
Random:           2048 B -> 2048 B  RawPassthrough
```

## Small and high-entropy buffers

Small buffers are only compressed when the complete representation is actually smaller.

A measured 12-byte buffer containing one `i8`, padding zeros, and an arbitrary aligned Float64 used `ZeroRun`:

```text
Raw:       12 B
Encoded:   11 B
Mode:      ZeroRun
Saved:      1 B
Savings:    8.33%
```

When the aligned Float64 is exactly `3`, the byte pattern contains a much longer zero run:

```text
Raw:       12 B
Encoded:    5 B
Mode:      ZeroRun
Saved:      7 B
Savings:   58.33%
```

High-entropy data still remains raw when specialized codecs and Huffman cannot beat the source. The v2.6.4 suite keeps a 2,048-byte random buffer at exactly 2,048 bytes.

The default `HuffmanMinBytes` is 16, so tiny first-stage candidates normally skip Auto Huffman. For known structures, a Schema can still be preferable because it avoids transmitting application-level padding and repeated type information.
## Expansion safety

With `AllowExpansion = false`, forced LZ and Auto paths can fall back to raw when their encoded representation would be larger.

```lua
local compressed = Compression.CompressBuffer(value, {
    BufferStrategy = "LZ",
    AllowExpansion = false,
})
```

Set `AllowExpansion = true` only when you deliberately want to inspect or benchmark a forced codec even when it becomes larger.

## Buffer statistics

```lua
local stats = Compression.BufferStats(value)
print(stats.Mode)
print(stats.RawBytes)
print(stats.Bytes)
print(stats.SavedBytes)
print(stats.ExpandedBytes)

Compression.PrintBufferStats(value)
```

---

# Huffman Entropy Coding

v2.6.4 includes a **canonical Huffman** entropy layer. It is a second-stage codec: Compression first applies the best type-aware representation, then Huffman may reduce that byte stream further.

Typical pipeline:

```text
value
  -> type-aware codec
  -> VarInt / delta / RLE / LZ / sparse / nibble / compact table
  -> canonical Huffman when profitable
  -> final buffer
```

Huffman is lossless. It does not quantize arbitrary floats and cannot recover information removed by a lossy transform.

## Auto behavior

Default entropy behavior is expansion-safe:

```lua
{
    EntropyCoding = true,
    EntropyStrategy = "Auto",
    HuffmanMinBytes = 16,
    HuffmanMinSavings = 1,
    HuffmanMaxCodeBits = 32,
}
```

`Auto` includes the Huffman codebook/frame overhead in its comparison. If the complete Huffman frame is not smaller enough, the original first-stage representation is kept.

Random data therefore commonly stays uncompressed.

## Direct Huffman API

```lua
local frame = Compression.HuffmanEncode(data)
local restored = Compression.HuffmanDecode(frame)

print(Compression.IsHuffman(frame))
```

Try Huffman only when it wins:

```lua
local result, selected = Compression.TryHuffman(data)
```

Statistics:

```lua
local stats = Compression.HuffmanStats(data)
print(stats.Selected)
print(stats.RawBytes)
print(stats.Bytes)
print(stats.SavedBytes)
print(stats.SavingsPercent)
```

## Forced Huffman

```lua
local result, selected = Compression.TryHuffman(data, {
    EntropyStrategy = "Huffman",
    AllowExpansion = false,
})
```

With `AllowExpansion = false`, forced Huffman still returns the original representation when the Huffman frame would be larger. Set `AllowExpansion = true` for codec stress tests or direct expansion measurements.

## Boolean exception

Standalone booleans and compact boolean data do not need per-value Huffman coding. The compact boolean path already uses one useful bit per boolean. Huffman remains useful around larger structured byte streams that happen to contain a bit-packed boolean array because it can compress the surrounding structural bytes, not because it can represent an individual boolean below one bit.

---

# Roblox Datatypes

Compression v2.6.4 supports these Roblox datatypes directly:

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

If a value cannot be represented by the Compact format, v2.6.x can fall back to Dynamic instead of breaking the entire table encode.

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

v2.6.4 rejects malformed payloads containing duplicate dictionary entries.

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

Newer v2.6.x Dynamic tables also support:

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

Measured v2.6.4 examples:

```text
Bnum-like 1,3:     12 B -> 5 B   ZeroRun
Bnum-like -1,3:    12 B -> 5 B   ZeroRun
Bnum-like 1,1000:  12 B -> 6 B   ZeroRun
```

The selected buffer mode still depends on the exact byte layout, but these current regression cases all choose `ZeroRun`.

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

v2.6.4 includes the following descriptor constructors:

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

v2.6.x fixed the older schema Color3 behavior.

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

Required fields cannot be silently removed by a delta packet in v2.6.4.

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

v2.6.4 validates both changed and unchanged schema state, and required fields cannot be removed through delta encoding.

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

v2.6.x recognizes:

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

The constructors validate invalid ranges in v2.6.x.

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

    EntropyCoding = true,
    EntropyStrategy = "Auto",
    HuffmanMinBytes = 16,
    HuffmanMinSavings = 1,
    HuffmanMaxCodeBits = 32,

    VerifyHash = true,
    SchemaVersion = 1,
    AllowExpansion = false,
}
```

Not every option needs to be specified. The normal high-level call uses safe defaults:

```lua
local packet = Compression.Pack(value)
```

## EntropyStrategy

```text
Auto
Huffman
None
```

- `Auto` tries canonical Huffman when the candidate meets the minimum-size threshold and the complete Huffman frame saves enough bytes.
- `Huffman` explicitly requests Huffman, while still respecting `AllowExpansion`.
- `None` disables the entropy layer.
- `EntropyCoding = false` is also treated as `None`.

## StringStrategy

```text
Auto
Raw
LZ
ASCII7
Identifier6
Numeric4
```

## BufferStrategy

```text
Auto
Raw
LZ
Sparse
Nibble
```

## TableStrategy

```text
Auto
Compact
Dynamic
```

## Mode

```text
Binary
BinaryWithHash
```

---

# Public API Overview

v2.6.4 exposes **85 public functions**

## Huffman / Entropy

```text
IsHuffman
HuffmanEncode
HuffmanDecode
TryHuffman
HuffmanStats
```

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

## Schemas / Descriptors

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

## AllowExpansion

`AllowExpansion` controls whether an explicitly requested compression strategy is allowed to return a payload larger than its raw representation.

Default:

```lua
AllowExpansion = false
```

In v2.6.4 this applies consistently to forced string codecs, forced buffer LZ, and forced Huffman behavior.

With the default setting, explicit codecs may safely fall back to raw when their frame is larger. Set `AllowExpansion = true` when you intentionally want to benchmark the requested codec even when it expands.

---

# Performance Benchmarks

The following measurements are from the v2.6.4 full Roblox Studio regression benchmark. Timing is machine- and workload-dependent; use these values as a reference for this test corpus rather than universal guarantees.

Packing sizes remained:

```text
String: 412 B -> 190 B
Buffer: 338 B -> 139 B
Table:  1311 B -> 761 B
```

Measured throughput:

| Operation | v2.6.4 |
| --- | ---: |
| Auto encode string - Entropy=None | 3562.568 us/op |
| Auto encode string - Huffman Auto | 3911.334 us/op |
| Auto decode string - Entropy=None | 354.120 us/op |
| Auto decode string - Huffman Auto | 452.403 us/op |
| Auto encode buffer - Entropy=None | **1258.030 us/op** |
| Auto encode buffer - Huffman Auto | **1348.945 us/op** |
| Auto decode buffer - Entropy=None | **31.627 us/op** |
| Auto decode buffer - Huffman Auto | 106.248 us/op |
| Auto encode table - Entropy=None | **316.943 us/op** |
| Auto encode table - Huffman Auto | **1320.819 us/op** |
| Auto decode table - Entropy=None | 84.580 us/op |
| Auto decode table - Huffman Auto | 493.942 us/op |
| Direct Huffman encode 8 KiB | **843.921 us/op** |
| Direct Huffman decode 8 KiB | **508.772 us/op** |

Compared with v2.6.2 on the same regression workload, the largest measured improvements were approximately:

```text
Buffer encode, no entropy:   ~19% faster
Buffer encode, Huffman Auto: ~19% faster
Table encode, no entropy:    ~24% faster
Table encode, Huffman Auto:  ~15% faster
Direct Huffman encode:       ~27% faster
Direct Huffman decode:       ~11% faster
```

v2.6.4 intentionally keeps compression quality and wire compatibility ahead of benchmark-only speed changes. Always run your own representative network/DataStore workload before choosing aggressive entropy settings.

---

# Backward Compatibility

v2.6.4 writes:

```text
Binary format: 25
```

The generic decoder accepts the current format plus compatible binary versions **24 through 6**. The compact-number decoder retains compatible legacy handling for the versions implemented by the v2.x decoder, and the buffer decoder keeps recovery support for the affected legacy v2.3.1 short `SparsePower2` representation.

Important release progression:

```text
v2.3.x  -> format 22
v2.4.0  -> format 23
v2.5.x  -> format 24
v2.6.x  -> format 25
```

Format 25 was introduced for the v2.6 buffer-frame generation, including the `ZeroRun` path. v2.6.4 does not introduce another wire-format change; it keeps format 25 while improving implementation speed, safety, and Luau compiler headroom.

As with any serialization system, validate persisted production data and schema migrations before deploying a format-changing update.

---
# v2.6.4 Patch Notes

v2.6.4 is the stable performance, safety, and Luau compiler-fix release for the v2.6 branch.

```text
Version:          2.6.4
Binary format:    25
Public API:       85 functions
Regression:       132 passed / 0 failed / 0 skipped
Top-level locals: 191
```

## v2.6 branch summary

```text
v2.6.0  ZeroRun buffer frame introduced
v2.6.1  Generic Auto/Decode recognition fixed for ZeroRun
v2.6.2  Buffer decode-size hardening and option validation
v2.6.3  Performance refactor, but exceeded Luau's 200-local module limit
v2.6.4  Register-pressure fix while preserving the v2.6.3 optimizations
```

## ZeroRun buffer compression

`ZeroRun` removes one profitable contiguous zero run and stores compact reconstruction metadata. It is lossless and especially useful for aligned numeric buffers that contain long stretches of zero bytes.

Measured cases:

```text
12 B aligned Float64/log-style buffer -> 11 B
12 B aligned Float64(3) buffer        ->  5 B
Bnum-like 1,3                         ->  5 B
Bnum-like -1,3                        ->  5 B
Bnum-like 1,1000                      ->  6 B
```

## Buffer safety and malformed-input hardening

v2.6.4 keeps the v2.6.2 decode protections:

- compressed buffer outputs are checked before allocation
- oversized v2 buffer frames are rejected
- oversized ZeroRun frames are rejected
- invalid numeric buffer options are rejected
- raw/magic collisions remain protected
- high-entropy buffers remain expansion-safe

## Faster Auto buffer analysis

The v2.6 performance path reduces repeated buffer work by analyzing codec eligibility once and avoiding sparse metadata allocation until Sparse can actually win.

Raw fallback is also allocated lazily in hot Auto paths, reducing copies that would otherwise be discarded when another codec wins.

## Faster string and numeric hot paths

The optimized implementation includes:

- numeric three-byte keys for string LZ indexing instead of temporary substring keys
- cached source lengths in hot LZ loops
- a reusable Float32 exactness scratch buffer
- exact packing behavior preserved for Numeric4, Identifier6, ASCII7, LZ, numbers, and Roblox datatypes

## Faster canonical Huffman

Huffman hot paths were reworked with dense byte-frequency storage, reusable heap helpers, dense encode lookup, and flatter decode lookup.

The regression benchmark measured:

```text
Direct Huffman encode 8 KiB: 843.921 us/op
Direct Huffman decode 8 KiB: 508.772 us/op
```

The encoded Huffman format and deterministic canonical-code behavior remain compatible with format 25.

## Writer and hash hot-path cleanup

Writers avoid a final buffer copy when the backing buffer is already exactly sized, and FNV-1a hashing caches the source length for its loop.

These are implementation optimizations only; packet semantics are unchanged.

## Luau local-register fix

v2.6.3 could not load because the module exceeded Luau's top-level local/register limit:

```text
Out of local registers ... exceeded limit 200
```

v2.6.4 moves cold internal helpers onto existing internal namespaces and reduces the module to **191 top-level locals**, leaving compiler headroom while keeping performance-critical helpers local.

## Packing stability

The full v2.6.4 suite confirms the primary benchmark outputs remain:

```text
String: 412 B -> 190 B
Buffer: 338 B -> 139 B
Table:  1311 B -> 761 B
```

Core codec examples also remain stable:

```text
String LZ:          1280 B ->   51 B
Repetitive string:  3712 B ->  107 B
Buffer LZ:          4096 B ->  142 B
Skew buffer:        8192 B -> 1243 B
UInt array:         8192 B ->   93 B
Vector3 array:      8192 B ->  697 B
Color3 array:       5120 B ->  144 B
Schema:             1939 B -> 1691 B
```

## Regression validation

The full v2.6.4 Roblox Studio suite completed with:

```text
Module Loaded: true
Compression Version: 2.6.4
Tests Passed: 132
Tests Failed: 0
Tests Skipped: 0
Status: ALL PASSED
```

Coverage includes primitives, all current string and buffer modes, ZeroRun, direct canonical Huffman, malformed Huffman rejection, Roblox datatypes, arrays, maps, schemas, optional fields, deltas, quantized descriptors, expansion fallbacks, legacy SparsePower2 data, hash corruption, oversized-buffer rejection, randomized buffers, randomized arrays, randomized strings, randomized nested tables, and Bnum-compatible buffers.

---
# Version

```lua
print(
	Compression.Version()
)
```

Expected:

```text
2.6.4
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

# Download

https://create.roblox.com/store/asset/71588759746122/Compression

That covers the main Compression v2.6.4 workflow.
