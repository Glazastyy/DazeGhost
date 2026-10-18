local crypt = require("src.crypt")
local digest = require("src.digest")
local obfuscate = require("src.obfuscate")

assert(not pcall(function()
    crypt.seal("return 1", { chain_next = true, chain_context = "ctx" })
end))
assert(not pcall(function()
    crypt.seal("return 1", { secret = "root", chain_next = true })
end))

local source = "return 23"
local context = "layer-context-2"
local protected = crypt.seal(source, {
    mode = "text",
    seed = 17,
    secret = "layer-secret-1",
    chain_context = context,
    chain_next = true
})

local environment = { __DazeGhostPassword = "layer-secret-1" }
setmetatable(environment, { __index = _G })
local chunk, err = load(protected, "=chain", "t", environment)
assert(chunk, err)
assert(chunk() == 23)
assert(environment.__DazeGhostPassword == digest.hmac("layer-secret-1", context))

local layered = crypt.seal("return 7", {
    mode = "text",
    seed = 31,
    secret = digest.hmac("root-secret", "DazeGhost/chain/v1/2")
})
local outer = crypt.seal(layered, {
    mode = "text",
    seed = 32,
    secret = "root-secret",
    chain_context = "DazeGhost/chain/v1/2",
    chain_next = true
})
local chainedEnvironment = { __DazeGhostPassword = "root-secret" }
setmetatable(chainedEnvironment, { __index = _G })
local chainedChunk, chainedErr = load(outer, "=chained", "t", chainedEnvironment)
assert(chainedChunk, chainedErr)
assert(chainedChunk() == 7)

local multiLayered = obfuscate.obfuscate("return 41 + 1", {
    mode = "text",
    rounds = 3,
    secret = "multi-layer-root",
    seed = 44
})
local multiEnvironment = { __DazeGhostPassword = "multi-layer-root" }
setmetatable(multiEnvironment, { __index = _G })
local multiChunk, multiErr = load(multiLayered, "=multi-layer", "t", multiEnvironment)
assert(multiChunk, multiErr)
assert(multiChunk() == 42)

local wrongEnvironment = { __DazeGhostPassword = "wrong-root" }
setmetatable(wrongEnvironment, { __index = _G })
local wrongChunk = assert(load(multiLayered, "=multi-layer-wrong", "t", wrongEnvironment))
assert(not pcall(wrongChunk))

local compressedLayered = obfuscate.obfuscate("return 6 * 7", {
    mode = "text",
    rounds = 2,
    compress_rounds = true,
    secret = "compressed-root",
    seed = 55
})
local compressedEnvironment = { __DazeGhostPassword = "compressed-root" }
setmetatable(compressedEnvironment, { __index = _G })
local compressedChunk, compressedErr = load(compressedLayered, "=compressed-chain", "t", compressedEnvironment)
assert(compressedChunk, compressedErr)
assert(compressedChunk() == 42)

print("passed: chained layer secret derivation")
