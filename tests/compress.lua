local compress = require("src.compress")
local obfuscate = require("src.obfuscate")

local source = string.rep("local value = 'stable payload'\n", 80) .. "return value"
local packed = compress.pack(source)
assert(type(packed) == "string")
assert(#packed < #source)
assert(compress.unpack(packed) == source)

local loader = compress.wrap(source)
local fn, err = load(loader, "=compressed", "t")
assert(fn, err)
assert(fn() == "stable payload")
assert(loader == compress.wrap(source))

local binary = string.char(0, 1, 2, 3, 255) .. string.rep("A", 300)
assert(compress.unpack(compress.pack(binary)) == binary)

local layeredSource = string.rep("local value = 'layered'\n", 40) .. "return value"
local layered = obfuscate.obfuscate(layeredSource, {
    rounds = 3,
    mode = "text",
    seed = 17,
    compress_rounds = true
})
local layeredFn, layeredErr = load(layered, "=layered", "t")
assert(layeredFn, layeredErr)
assert(layeredFn() == "layered")
print("passed: compression and single-file loader checks")
