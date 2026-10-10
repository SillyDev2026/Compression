--!strict
-- Studio Script beside the Compress ModuleScript; no network/data writes.
local Compression = require(script.Parent:WaitForChild("Compress"))
assert(Compression.Version() == "2.6.5", "Unexpected Compression version")

local original = buffer.fromstring("AB")
local encoded = Compression.HuffmanEncode(original)
local decoded = Compression.HuffmanDecode(encoded)
assert(buffer.len(decoded) == 2 and buffer.readstring(decoded, 0, 2) == "AB", "Valid Huffman roundtrip failed")

-- Two distinct symbols require two one-bit codes. That produces six
-- trailing padding bits in the final payload byte.
local packetLength = buffer.len(encoded)
local badPadding = buffer.create(packetLength)
buffer.copy(badPadding, 0, encoded, 0, packetLength)
local finalIndex = packetLength - 1
local finalByte = buffer.readu8(badPadding, finalIndex)
buffer.writeu8(badPadding, finalIndex, bit32.bor(finalByte, 0x80))
assert(not pcall(Compression.HuffmanDecode, badPadding), "Nonzero Huffman padding was accepted")

local truncated = buffer.fromstring("HUF1")
assert(not pcall(Compression.HuffmanDecode, truncated), "Truncated Huffman header was accepted")

local empty = Compression.HuffmanEncode(buffer.create(0))
assert(buffer.len(Compression.HuffmanDecode(empty)) == 0, "Empty Huffman roundtrip failed")
print("Compression v2.6.5 canonical Huffman regression PASS")
