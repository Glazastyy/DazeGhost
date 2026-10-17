package.path = "./?.lua;./?/init.lua;" .. package.path

local parser = require("src.parser")
local minify = require("src.minify")
local obfuscate = require("src.obfuscate")

local failed = 0

local function check(name, cond, extra)
    if cond then
        print("ok  " .. name)
    else
        failed = failed + 1
        print("FAIL  " .. name .. "  " .. (extra or ""))
    end
end

local function exec(src)
    local fn, err = load(src, name, "t")
    if not fn then
        return nil, err
    end
    return fn()
end

do
    local src = [[
        -- comment
        local function add(x, y)
            return x + y
        end
        return add(2, 3)
    ]]
    local out = minify.minify(src)
    check("minify load", load(out, "m", "t"))
    check("minify result", exec(out) == 5, out)
    check("minify drops comments", not out:find("%-%-"), out)
end

do
    local src = [[
        local a = 10
        local function f(b)
            local a = a + b
            return a
        end
        return f(3)
    ]]
    local out = obfuscate.obfuscate(src)
    check("obfuscate load", load(out, "o", "t"), out)
    check("obfuscate result", exec(out) == 13, out)
    check("obfuscate renames locals", not out:find("local a") and not out:find("function f"), out)
end

do
    local src = "local x = 1 - -2\nreturn x"
    local out = minify.minify(src)
    check("minus minus", exec(out) == 3, out)
end

do
    local src = [[
        local t = { n = 1, [2] = 3, 4 }
        function t:inc(k)
            self.n = self.n + k
            return self.n
        end
        return t:inc(4)
    ]]
    local out = minify.minify(src)
    check("method minify", exec(out) == 5, out)
    local ob = obfuscate.obfuscate(src)
    check("method obfuscate", exec(ob) == 5, ob)
end

do
    local src = [[
        local s = "hi"
        if s == "hi" then
            return 1
        else
            return 0
        end
    ]]
    local ob = obfuscate.obfuscate(src)
    check("string encode still equals", exec(ob) == 1, ob)
    check("string not plaintext", not ob:find('"hi"') and not ob:find("'hi'"), ob)
end

do
    local src = [[
        local n = 0
        for i = 1, 4 do
            n = n + i
        end
        for _, v in ipairs({1, 2}) do
            n = n + v
        end
        return n
    ]]
    check("for loops", exec(obfuscate.obfuscate(src)) == 13)
end

do
    local src = "return (1 + 2) * 3 // 2 ^ 2"
    check("ops minify", exec(minify.minify(src)) == exec(src), minify.minify(src))
end

do
    local src = [[
        local function fact(n)
            if n <= 1 then return 1 end
            return n * fact(n - 1)
        end
        return fact(5)
    ]]
    check("recursion", exec(obfuscate.obfuscate(src)) == 120)
end

print(failed == 0 and "all passed" or (failed .. " failed"))
os.exit(failed == 0 and 0 or 1)
