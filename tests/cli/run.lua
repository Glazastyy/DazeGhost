local obfuscate = require("src.obfuscate")
local compress = require("src.compress")
local input = assert(io.open("tests/fixtures/script.lua", "rb"))
local source = assert(input:read("*a"))
input:close()
local output = obfuscate.obfuscate(source, {
    anti_ia = true,
    decoy_src = "tests/fixtures/caos.lua",
    rounds = 3,
    decoy_density = 60,
    mode = "text",
    seed = 101
})
local loader = compress.wrap(output)
local fn, err = load(loader, "=cli", "t")
assert(fn, err)
assert(fn() == 42)
print("passed: CLI library integration")
