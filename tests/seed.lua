local crypt = require("src.crypt")
local obfuscate = require("src.obfuscate")
local random128 = require("src.random")

local source = "local x=7;return x*6"

local first = crypt.seal(source, { mode = "text" })
local second = crypt.seal(source, { mode = "text" })
assert(first ~= second)

local transformedA = obfuscate.obfuscate(source, { mode = "text" })
local transformedB = obfuscate.obfuscate(source, { mode = "text" })
assert(transformedA ~= transformedB)

local seededA = crypt.seal(source, { mode = "text", seed = 73 })
local seededB = crypt.seal(source, { mode = "text", seed = 73 })
assert(seededA == seededB)

local a = random128.new({ 1, 2, 3, 4 })
local b = random128.new({ 1, 2, 3, 4 })
for _ = 1, 16 do
    assert(a() == b())
end

print("passed: 128-bit seed and per-build randomization checks")
