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
assert(not transformedA:find("_dg", 1, true))
assert(not transformedB:find("_dg", 1, true))

local seededA = crypt.seal(source, { mode = "text", seed = 73 })
local seededB = crypt.seal(source, { mode = "text", seed = 73 })
assert(seededA == seededB)

local seededTransformA = obfuscate.transform("local obvious_name=7;return obvious_name", { seed = 73 })
local seededTransformB = obfuscate.transform("local obvious_name=7;return obvious_name", { seed = 74 })
assert(seededTransformA ~= seededTransformB)
assert(not seededTransformA:find("obvious_name", 1, true))
assert(not seededTransformB:find("obvious_name", 1, true))
assert(not seededTransformA:find("_dg", 1, true))
assert(not seededTransformB:find("_dg", 1, true))

local woven = obfuscate.transform("local obvious_name=7;return obvious_name", {
    anti_ia = true,
    decoy_src = "local decoy_name=8;return decoy_name",
    seed = 73
})
assert(not woven:find("_dg", 1, true))

local a = random128.new({ 1, 2, 3, 4 })
local b = random128.new({ 1, 2, 3, 4 })
for _ = 1, 16 do
    assert(a() == b())
end

print("passed: 128-bit seed and per-build randomization checks")
