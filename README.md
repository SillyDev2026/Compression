# Compression v1.0.0

v1.0.0 pushes the binary codec into an adaptive stage.

## New in v1.0.0

- Adaptive `Compression.Auto(value)` descriptor selection
- Dynamic repeated-string dictionary IDs
- Schema versioning embedded in binary headers
- Exact bit-layout reports retained from v1.5.1
- Binary buffers as the real storage format
- Optional FNV-1a integrity hash
- LZ-style compressed strings
- Delta encoding
- Stronger schema validation

## Quick test

```lua
local Compression = require(game.ReplicatedStorage.Compression)

local Schema = Compression.Schema({
	Boolean = Compression.Bool(),
	Number = Compression.UInt(),
	String = Compression.CompressedString(),
	Health = Compression.Quantized(0, 100, 8),
}, 1)

local data = {
	Boolean = true,
	Number = 123,
	String = "Hello Hello Hello Hello Hello Hello",
	Health = 97,
}

local packet = Schema:Encode(data, {
	Mode = "BinaryWithHash",
})

print(packet.Bytes)
print(packet.Bits)
print(packet.Hash)

Schema:PrintBitLayout(data)
```

## Auto descriptors

```lua
Compression.Auto(true)
Compression.Auto(123)
Compression.Auto(-25)
Compression.Auto(3.14)
Compression.Auto("Hello")
Compression.Auto(Vector3.zero)
```

## Dynamic dictionary compression

`Compression.Encode()` now detects strings repeated at least twice and can store them once in a payload dictionary, then use tiny IDs for subsequent occurrences.

Disable it with:

```lua
UseStringDictionary = false
```

## Schema versioning

```lua
local Schema = Compression.Schema({
	Coins = Compression.UInt(),
}, 3)
```

A packet encoded with schema version 3 will not silently decode through schema version 4.

## Version

`1.5.5`
