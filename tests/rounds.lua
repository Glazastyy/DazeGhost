local obfuscate = require("src.obfuscate")
local crypt = require("src.crypt")
local weave = require("src.weave")

local path = "tests/fixtures/caos.lua"

local samples = {
    "return 42",
    "local x=4;local y=7;return x*y",
    "local function f(n)if n<2 then return n end;return f(n-1)+f(n-2) end;return f(7)",
    "local a=0;::again::a=a+1;if a<3 then goto again end;return a",
    "local x=1;local function g()x=x+1;return x end;g();g();return x",
    "local t={x=4};function t:sum(a)return self.x+a end;return t:sum(9)",
    "local function f(...)return select('#',...),... end;return f(nil,2,nil)",
    "local result='';for i=1,3 do result=result..i end;return result",
    "local x=0;repeat local z=1;x=x+z until x==4;return x",
    "local t={};for i=1,6 do t[i]=i*i end;return table.concat(t,',')"
}

local function result(code)
    local fn, err = load(code, "=test", "t")
    assert(fn, err)
    return table.pack(fn())
end

local function same(expected, actual)
    assert(expected.n == actual.n, "different return count")
    for i = 1, expected.n do
        assert(expected[i] == actual[i], "return differs at " .. i)
    end
end

local count = 0
for _, input in ipairs(samples) do
    local expected = result(input)
    for rounds = 1, 3 do
        local options = {
            anti_ia = true,
            decoy_src = path,
            rounds = rounds,
            mix_original = true,
            seed = 191,
            max_decoy_fragments = 12,
            decoy_density = 55,
            min_chunk_size = 32,
            max_chunk_size = 128,
            max_output_bytes = 8000000
        }
        local protected = obfuscate.obfuscate(input, options)
        same(expected, result(protected))
        local again = obfuscate.obfuscate(input, options)
        assert(again == protected, "seeded builds differ")
        local changed = obfuscate.obfuscate(input, { anti_ia = true, decoy_src = path, seed = 192, rounds = rounds, max_decoy_fragments = 12 })
        assert(protected ~= changed)
        same(expected, result(changed))
        count = count + 3
    end
end

for rounds = 4, 5 do
    local protected = obfuscate.obfuscate("return 'ok'", {
        anti_ia = true, decoy_src = path, rounds = rounds, seed = 19,
        decoy_density = 25, max_decoy_fragments = 3, max_output_bytes = 12000000
    })
    same(result("return 'ok'"), result(protected))
    count = count + 1
end

local woven = weave.weave("local x=2;return x+3", { decoy_src = path, seed = 15 })
same(result("return 5"), result(woven))
assert(woven:find("function", 1, true))
assert(not pcall(function() obfuscate.obfuscate("return 1", { anti_ia = true, decoy_src = "tests/missing.lua" }) end))
assert(not pcall(function() obfuscate.obfuscate("return 1", { rounds = 0 }) end))
assert(not pcall(function() obfuscate.obfuscate("return 1", { rounds = 6 }) end))
assert(not pcall(function() obfuscate.obfuscate("return 1", { rounds = 2.5 }) end))
assert(not pcall(function() obfuscate.obfuscate("return 1", { rounds = 2, max_output_bytes = 1024 }) end))
assert(not pcall(function() crypt.seal("return 1", { noise_density = -1 }) end))
assert(not pcall(function() crypt.seal("return 1", { noise_density = 101 }) end))
local direct = crypt.seal("return 35", { anti_ia = true, decoy_src = path, seed = 32 })
same(result("return 35"), result(direct))
print("passed: " .. count .. " multipass semantic and reproducibility checks")
