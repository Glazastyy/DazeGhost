local crypt = require("src.crypt")

local source = "return 42, 'protected'"
local protected = crypt.seal(source, { mode = "text", seed = 77, secret = "correct horse battery staple" })
assert(not protected:find("correct horse battery staple", 1, true))

local function run(password)
    local reads = 0
    local environment = {}
    environment._G = environment
    environment.error = error
    environment.type = type
    environment.io = {
        write = function() end,
        read = function()
            reads = reads + 1
            return password
        end
    }
    environment.load = load
    environment.rawget = rawget
    environment.rawset = rawset
    environment.string = string
    environment.table = table
    local chunk, err = load(protected, "=password", "t", environment)
    assert(chunk, err)
    local ok, first, second = pcall(chunk)
    return ok, first, second, reads
end

local ok, first, second, reads = run("correct horse battery staple")
assert(ok)
assert(first == 42)
assert(second == "protected")
assert(reads == 1)

local wrong, message = run("wrong password")
assert(not wrong)
assert(type(message) == "string")
assert(message:find("password", 1, true))

print("passed: runtime password protection")
