local minify = require("src.minify")
local obfuscate = require("src.obfuscate")
local crypt = require("src.crypt")

local function result(code)
    local fn, err = load(code, "=property", "t")
    assert(fn, err)
    return table.pack(fn())
end

local function compare(original, generated)
    local a, b = result(original), result(generated)
    assert(a.n == b.n)
    for i = 1, a.n do
        assert(a[i] == b[i])
    end
end

local rng = 0x12AB34CD
local function number(minimum, maximum)
    rng = (rng * 1664525 + 1013904223) & 0xFFFFFFFF
    return minimum + rng % (maximum - minimum + 1)
end

for i = 1, 120 do
    local a = number(-1000, 1000)
    local b = number(-1000, 1000)
    local k = number(1, 300)
    local text = string.format("item_%d", i)
    local code = string.format([[
local total=%d
local offset=%d
local function calculate(value)
    local total=value+offset
    return total*%d
end
local t={}
for j=1,3 do
    t[j]=calculate(j)
end
local function label(...)return ... end
return total+calculate(%d),t[2],label(%q)
]], a, b, k, i, text)
    compare(code, minify.minify(code))
    compare(code, obfuscate.transform(code, { flatten = true, seed = i }))
    compare(code, obfuscate.obfuscate(code, { flatten = true, anti_ia = true, seed = i, min_chunk_size = 5, max_chunk_size = 19 }))
    compare(code, crypt.seal(code, { seed = i, mode = "text", anti_ia = true }))
end

local sample = "return 'sensitive value'"
local transformed = obfuscate.transform(sample, { seed = 123 })
assert(not transformed:find("sensitive value", 1, true))
assert(transformed:find("string.char", 1, true))
compare(sample, transformed)

local stableA = crypt.seal("return 42", { seed = 12345, anti_ia = true })
local stableB = crypt.seal("return 42", { seed = 12345, anti_ia = true })
assert(stableA == stableB)
local tampered, changes = stableA:gsub("(%{%{)(%d+)", function(prefix, value)
    return prefix .. tostring((tonumber(value) + 1) % 256)
end, 1)
assert(changes == 1 and tampered ~= stableA)
local fn = assert(load(tampered, "=tampered", "t"))
assert(not pcall(fn))
print("passed: 480 randomized semantic checks and integrity checks")
