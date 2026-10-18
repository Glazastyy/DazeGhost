local crypt = require("src.crypt")

local function values(code)
    local fn, err = load(code, "=runtime", "t")
    assert(fn, err)
    return table.pack(fn())
end

local source = [[
local total = 0
for i = 1, 6 do
    total = total + i * i
end
return total, "runtime"
]]

local expected = values(source)
local outputs = {}
for _, runtime in ipairs({ "linear", "state", "table" }) do
    local protected = crypt.seal(source, { seed = 441, runtime = runtime, mode = "text" })
    local actual = values(protected)
    assert(actual.n == expected.n)
    for i = 1, expected.n do
        assert(actual[i] == expected[i])
    end
    outputs[runtime] = protected
    assert(protected == crypt.seal(source, { seed = 441, runtime = runtime, mode = "text" }))
end

assert(outputs.linear ~= outputs.state)
assert(outputs.state ~= outputs.table)
assert(outputs.linear ~= outputs.table)
assert(crypt.seal(source, { seed = 442, runtime = "auto", mode = "text" }) ~= crypt.seal(source, { seed = 441, runtime = "auto", mode = "text" }))
assert(not pcall(function() crypt.seal(source, { runtime = "unknown" }) end))
print("passed: runtime variants and reproducibility checks")
