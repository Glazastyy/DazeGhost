local minify = require("src.minify")
local obfuscate = require("src.obfuscate")
local crypt = require("src.crypt")

local sources = {
    'local function f(x) return x * 2 end; return f(21), "hello"',
    'local x=1;do local x=5; x=x+2 end;return x',
    'local x=1;local function f()local x=2;return function()return x end end;return f()()',
    'local t={x=7};function t:go(a)return self.x+a end;return t:go(5)',
    'local t={a={x=3}};function t.a:b(v)return self.x+v end;return t.a:b(4)',
    'local function f(a,...)local b,c=...;return a,b,c end;return f(1,2,3)',
    'local n=0;repeat local x=3;n=n+x until n>9;return n',
    'local n=0;::again::n=n+1;if n<4 then goto again end;return n',
    'local v={["one"]=1,[2]=2,three=3,4};return v.one,v[2],v.three,v[1]',
    'return -2^2,(-2)^2,7//2,2^3^2',
    'local _ENV={value=11};return value',
    'local a<const> =4;return a',
    'local t={x=2};function t:y()local self={x=10};return self.x end;return t:y()',
    'return 0x1.fp2,0xFF,0.5,.25,12e2,1 .. 2',
    'return [[a\nb]], [=[hi "there"]=]',
    'return "a\\z  \n   b", "A\\065\\x42\\u{43}", "\\0\\255"',
    'local function f(x)return x,x*2 end;local t={1,2,f(3)};return t[1],t[2],t[3],t[4]',
    'local function f(...)return select("#",...),... end;return f(nil,2,nil)',
    'local x=1;local x=2;local function f()return x end;return f()',
    'local function f(n)if n==0 then return 0 elseif n==1 then return 1 else return f(n-1)+f(n-2) end end;return f(8)',
    'local a=0;for i=1,10 do a=a+i end;for k,v in ipairs({1,2,3}) do a=a+v end;return a',
    'local x=0;local function f()x=x+1 end;f();f();f();return x',
    'local a,b,c=1,2,3;a,b,c=c,a,b;return a,b,c',
    'local t={};function t.f(self,x)return x+1 end;return t:f(8)',
    'local function f(a,b,...)return a,b,... end;return f(1,2,3,4)',
    'local x=[=[test\nsafely]=];return #x,x',
    'return true and 4 or 5,not false,~0&255,1<<4',
    'local function f(x)return x end;local function g(x)return x end;f(1);g(2);f(3);g(4);return 8',
    'local a=1;local function f()return a end;do local a=2 end;return f()',
    'local t={n=0};function t:inc()self.n=self.n+1;self.n=self.n+1;self.n=self.n+1;return self.n end;return t:inc()'
}

local function values(src)
    local fn, err = load(src, "=case", "t")
    assert(fn, err)
    return table.pack(fn())
end

local function equal(a, b)
    if a.n ~= b.n then
        return false
    end
    for i = 1, a.n do
        if type(a[i]) ~= type(b[i]) or a[i] ~= b[i] then
            return false
        end
    end
    return true
end

local count = 0
for i, src in ipairs(sources) do
    local expected = values(src)
    local variants = {
        minify.minify(src),
        obfuscate.transform(src),
        obfuscate.transform(src, { flatten = true, seed = 27 }),
        crypt.seal(src, { anti_ia = true, seed = i }),
        obfuscate.obfuscate(src, { anti_ia = true, flatten = true, seed = i, min_chunk_size = 8, max_chunk_size = 24 }),
        obfuscate.obfuscate(src, { anti_ia = false, seed = i, mode = "text" })
    }
    for j, variant in ipairs(variants) do
        local ok, actual = pcall(values, variant)
        assert(ok, "case " .. i .. " variant " .. j .. " failed: " .. tostring(actual))
        assert(equal(expected, actual), "case " .. i .. " variant " .. j .. " differs")
        count = count + 1
    end
end

local a = crypt.seal("return 42", { anti_ia = true, seed = 1 })
local b = crypt.seal("return 42", { anti_ia = true, seed = 2 })
assert(a ~= b)
assert(values(a)[1] == 42 and values(b)[1] == 42)
assert(not pcall(function() crypt.seal("this is not lua") end))
assert(not pcall(function() crypt.seal("return 1", { decoy_src = "???", anti_ia = true }) end))
assert(not pcall(function() crypt.seal("return 1", { min_chunk_size = 100, max_chunk_size = 10 }) end))
print("passed: " .. count .. " semantic checks")
