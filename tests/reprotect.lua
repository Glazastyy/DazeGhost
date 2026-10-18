local obfuscate = require("src.obfuscate")
local compress = require("src.compress")

local options = {
    mode = "text",
    rounds = 5,
    seed = 41,
    anti_ia = true,
    decoy_src = "tests/fixtures/caos.lua",
    max_decoy_fragments = 4,
    max_output_bytes = 67108864
}

local first = obfuscate.obfuscate("return 6 * 7", options)
local originalTransform = obfuscate.transform
obfuscate.transform = function()
    error("protected input was sent to the AST transformer")
end
local second = obfuscate.obfuscate(first, options)
obfuscate.transform = originalTransform
local chunk, err = load(second, "=reprotected", "t")
assert(chunk, err)
assert(chunk() == 42)

local compressed = compress.wrap("return 42")
obfuscate.transform = function()
    error("compressed input was sent to the AST transformer")
end
local compressedSecond = obfuscate.obfuscate(compressed, options)
obfuscate.transform = originalTransform
local compressedChunk, compressedErr = load(compressedSecond, "=recompressed", "t")
assert(compressedChunk, compressedErr)
assert(compressedChunk() == 42)
print("passed: protected artifacts can be re-sealed")
