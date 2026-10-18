local digest = require("src.digest")
local crypt = require("src.crypt")

assert(digest.hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
assert(digest.hmac("key", "The quick brown fox jumps over the lazy dog") == "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
assert(digest.encode(digest.pbkdf2("password", "salt", 1, 32)) == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")

local protected = crypt.seal("return 42", { mode = "text", secret = "correct secret", seed = 91 })
assert(not protected:find("16777619", 1, true))
assert(protected:find("f7bc", 1, true) == nil)
assert(not protected:find("dgHexKey", 1, true))
assert(not protected:find("dgRaw", 1, true))
assert(not protected:find(digest.hex("correct secret"), 1, true))
local environment = { __DazeGhostPassword = "correct secret" }
setmetatable(environment, { __index = _G })
local chunk, err = load(protected, "=digest", "t", environment)
assert(chunk, err)
assert(chunk() == 42)

print("passed: SHA-256 and HMAC integrity checks")
